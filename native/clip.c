/*
 * The last 30 seconds as a video, for bug reports: the player presses F11 (lua/coop.lua) and
 * Net.CoopClip("save") writes Documents\Codemasters\Clive Barker's Jericho\Coop\
 * clip-<date>-<time>.avi (Motion JPEG: Windows, VLC and browsers play it).
 *
 * Eight times a second the frame about to be shown (IDirect3DDevice9::Present, vtable slot 17)
 * is scaled down on the GPU to 640 pixels wide and read back; a worker thread compresses it to
 * JPEG with Windows' own codecs (WIC) and keeps the last 30 seconds (about 10 MB) in memory.
 * Only what the game draws: never the screen. JERICHO_NOCLIP=1 turns it off.
 */
#define COBJMACROS
#include <initguid.h>
#include <windows.h>
#include <d3d9.h>
#include <objidl.h>
#include <wincodec.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "clip.h"
#include "coop_net.h"

#define VT_PRESENT 17
#define CLIP_W 640
#define CLIP_FPS 8
#define CLIP_SECONDS 30
#define RING (CLIP_FPS * CLIP_SECONDS)

typedef HRESULT (WINAPI *Present_t)(IDirect3DDevice9 *, const RECT *, const RECT *, HWND, const RGNDATA *);
static Present_t real_Present;

typedef struct {
    unsigned char *jpg;
    DWORD len;
    double t;
} Slot;

static CRITICAL_SECTION lock;
static Slot ring[RING];
static int head, count;
static UINT ring_w, ring_h;           /* size of the frames in the ring */

/* One raw frame handed from the render thread to the worker (24-bit BGR, bottom row last). */
static unsigned char *raw;
static UINT raw_w, raw_h;
static double raw_t;
static volatile LONG raw_ready;
static HANDLE wake;
static volatile LONG save_req;
static char save_path[MAX_PATH];

static IDirect3DSurface9 *sysmem;
static UINT sm_w, sm_h;
static D3DFORMAT sm_f;
static double last_at;
static int complaints;

static double now(void)
{
    static LARGE_INTEGER f;
    LARGE_INTEGER t;
    if (!f.QuadPart)
        QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart / (double)f.QuadPart;
}

static void complain(const char *what, long code)
{
    if (complaints++ < 5)
        coop_log("clip: %s (0x%08lx)", what, (unsigned long)code);
}

/* ---- render thread: scale down, read back ---- */
static void grab(IDirect3DDevice9 *dev, double t)
{
    IDirect3DSurface9 *bb = NULL, *resolved = NULL, *small = NULL;
    D3DSURFACE_DESC d;
    HRESULT hr = IDirect3DDevice9_GetBackBuffer(dev, 0, 0, D3DBACKBUFFER_TYPE_MONO, &bb);
    if (FAILED(hr))
        return;
    IDirect3DSurface9_GetDesc(bb, &d);
    if ((d.Format != D3DFMT_X8R8G8B8 && d.Format != D3DFMT_A8R8G8B8) || d.Width < 64 || d.Height < 64)
        goto done;
    UINT w = d.Width < CLIP_W ? d.Width : CLIP_W;
    UINT h = (UINT)((unsigned long long)d.Height * w / d.Width) & ~1u;
    IDirect3DSurface9 *src = bb;
    /* A multisampled back buffer is resolved first: D3D9 does not scale out of one. Created
     * per grab and released at once, so nothing of ours is in the way of a device Reset. */
    if (d.MultiSampleType != D3DMULTISAMPLE_NONE) {
        hr = IDirect3DDevice9_CreateRenderTarget(dev, d.Width, d.Height, d.Format, D3DMULTISAMPLE_NONE, 0, FALSE,
                                                 &resolved, NULL);
        if (SUCCEEDED(hr))
            hr = IDirect3DDevice9_StretchRect(dev, bb, NULL, resolved, NULL, D3DTEXF_NONE);
        if (FAILED(hr)) {
            complain("resolve failed", hr);
            goto done;
        }
        src = resolved;
    }
    hr = IDirect3DDevice9_CreateRenderTarget(dev, w, h, d.Format, D3DMULTISAMPLE_NONE, 0, FALSE, &small, NULL);
    if (SUCCEEDED(hr))
        hr = IDirect3DDevice9_StretchRect(dev, src, NULL, small, NULL, D3DTEXF_LINEAR);
    if (FAILED(hr)) {
        complain("scale failed", hr);
        goto done;
    }
    if (!sysmem || sm_w != w || sm_h != h || sm_f != d.Format) {
        if (sysmem)
            IDirect3DSurface9_Release(sysmem);
        sysmem = NULL;
        if (FAILED(IDirect3DDevice9_CreateOffscreenPlainSurface(dev, w, h, d.Format, D3DPOOL_SYSTEMMEM, &sysmem, NULL)))
            goto done;
        sm_w = w, sm_h = h, sm_f = d.Format;
    }
    hr = IDirect3DDevice9_GetRenderTargetData(dev, small, sysmem);
    if (FAILED(hr)) {
        complain("read back failed", hr);
        goto done;
    }
    /* The worker still busy with the last frame: this one is skipped. */
    if (InterlockedCompareExchange(&raw_ready, 0, 0))
        goto done;
    D3DLOCKED_RECT lr;
    if (FAILED(IDirect3DSurface9_LockRect(sysmem, &lr, NULL, D3DLOCK_READONLY)))
        goto done;
    if (!raw || raw_w != w || raw_h != h) {
        free(raw);
        raw = malloc((size_t)w * h * 3);
        raw_w = w, raw_h = h;
    }
    if (raw) {
        for (UINT y = 0; y < h; y++) {
            const unsigned char *s = (const unsigned char *)lr.pBits + (size_t)y * lr.Pitch;
            unsigned char *o = raw + (size_t)y * w * 3;
            for (UINT x = 0; x < w; x++, s += 4, o += 3)
                o[0] = s[0], o[1] = s[1], o[2] = s[2];
        }
        raw_t = t;
        InterlockedExchange(&raw_ready, 1);
        SetEvent(wake);
    }
    IDirect3DSurface9_UnlockRect(sysmem);
done:
    if (small)
        IDirect3DSurface9_Release(small);
    if (resolved)
        IDirect3DSurface9_Release(resolved);
    IDirect3DSurface9_Release(bb);
}

static HRESULT WINAPI hook_Present(IDirect3DDevice9 *dev, const RECT *s, const RECT *d, HWND w, const RGNDATA *r)
{
    double t = now();
    if (t - last_at >= 1.0 / CLIP_FPS) {
        last_at = t;
        grab(dev, t);
    }
    return real_Present(dev, s, d, w, r);
}

/* ---- worker: JPEG, ring, AVI ---- */
static unsigned char *encode_jpeg(IWICImagingFactory *fac, const unsigned char *px, UINT w, UINT h, DWORD *len)
{
    IStream *st = NULL;
    IWICBitmapEncoder *enc = NULL;
    IWICBitmapFrameEncode *fr = NULL;
    IPropertyBag2 *props = NULL;
    unsigned char *out = NULL;
    if (FAILED(CreateStreamOnHGlobal(NULL, TRUE, &st)))
        return NULL;
    if (FAILED(IWICImagingFactory_CreateEncoder(fac, &GUID_ContainerFormatJpeg, NULL, &enc)) ||
        FAILED(IWICBitmapEncoder_Initialize(enc, st, WICBitmapEncoderNoCache)) ||
        FAILED(IWICBitmapEncoder_CreateNewFrame(enc, &fr, &props)))
        goto done;
    PROPBAG2 opt;
    memset(&opt, 0, sizeof opt);
    opt.pstrName = L"ImageQuality";
    VARIANT v;
    memset(&v, 0, sizeof v);
    v.vt = VT_R4;
    v.fltVal = 0.75f;
    IPropertyBag2_Write(props, 1, &opt, &v);
    WICPixelFormatGUID pf = GUID_WICPixelFormat24bppBGR;
    if (FAILED(IWICBitmapFrameEncode_Initialize(fr, props)) || FAILED(IWICBitmapFrameEncode_SetSize(fr, w, h)) ||
        FAILED(IWICBitmapFrameEncode_SetPixelFormat(fr, &pf)) ||
        FAILED(IWICBitmapFrameEncode_WritePixels(fr, h, w * 3, w * 3 * h, (BYTE *)px)) ||
        FAILED(IWICBitmapFrameEncode_Commit(fr)) || FAILED(IWICBitmapEncoder_Commit(enc)))
        goto done;
    LARGE_INTEGER zero = {0};
    ULARGE_INTEGER end;
    if (FAILED(IStream_Seek(st, zero, STREAM_SEEK_CUR, &end)) || end.QuadPart == 0 || end.QuadPart > (1u << 24))
        goto done;
    HGLOBAL hg;
    if (FAILED(GetHGlobalFromStream(st, &hg)))
        goto done;
    const void *p = GlobalLock(hg);
    if (p && (out = malloc((size_t)end.QuadPart)) != NULL) {
        memcpy(out, p, (size_t)end.QuadPart);
        *len = (DWORD)end.QuadPart;
    }
    if (p)
        GlobalUnlock(hg);
done:
    if (props)
        IPropertyBag2_Release(props);
    if (fr)
        IWICBitmapFrameEncode_Release(fr);
    if (enc)
        IWICBitmapEncoder_Release(enc);
    IStream_Release(st);
    return out;
}

static void put32(FILE *f, DWORD v) { fwrite(&v, 4, 1, f); }
static void put16(FILE *f, WORD v) { fwrite(&v, 2, 1, f); }
static void fourcc(FILE *f, const char *c) { fwrite(c, 1, 4, f); }

/* Motion-JPEG AVI at CLIP_FPS: frame k shows the newest JPEG taken by first + k / CLIP_FPS, so
 * the video keeps real time when the game drew slower than that. */
static int write_avi(const char *path, Slot *s, int n, UINT w, UINT h)
{
    double t0 = s[0].t, t1 = s[n - 1].t;
    int frames = (int)((t1 - t0) * CLIP_FPS) + 1;
    int *pick = malloc(sizeof(int) * (size_t)frames);
    if (!pick)
        return 0;
    DWORD maxlen = 0;
    for (int k = 0, j = 0; k < frames; k++) {
        while (j + 1 < n && s[j + 1].t <= t0 + (double)k / CLIP_FPS + 1e-6)
            j++;
        pick[k] = j;
        if (s[j].len > maxlen)
            maxlen = s[j].len;
    }
    FILE *f = fopen(path, "wb");
    if (!f) {
        free(pick);
        return 0;
    }
    DWORD movi = 4;
    for (int k = 0; k < frames; k++)
        movi += 8 + ((s[pick[k]].len + 1) & ~1u);
    DWORD hdrl = 4 + (8 + 56) + (8 + 4 + (8 + 56) + (8 + 40));
    DWORD idx = 16u * (DWORD)frames;
    fourcc(f, "RIFF");
    put32(f, 4 + (8 + hdrl) + (8 + movi) + (8 + idx));
    fourcc(f, "AVI ");
    fourcc(f, "LIST"); put32(f, hdrl); fourcc(f, "hdrl");
    fourcc(f, "avih"); put32(f, 56);
    put32(f, 1000000 / CLIP_FPS); put32(f, maxlen * CLIP_FPS); put32(f, 0); put32(f, 0x10);
    put32(f, (DWORD)frames); put32(f, 0); put32(f, 1); put32(f, maxlen); put32(f, w); put32(f, h);
    put32(f, 0); put32(f, 0); put32(f, 0); put32(f, 0);
    fourcc(f, "LIST"); put32(f, 4 + (8 + 56) + (8 + 40)); fourcc(f, "strl");
    fourcc(f, "strh"); put32(f, 56);
    fourcc(f, "vids"); fourcc(f, "MJPG"); put32(f, 0); put16(f, 0); put16(f, 0); put32(f, 0);
    put32(f, 1); put32(f, CLIP_FPS); put32(f, 0); put32(f, (DWORD)frames); put32(f, maxlen);
    put32(f, (DWORD)-1); put32(f, 0); put16(f, 0); put16(f, 0); put16(f, (WORD)w); put16(f, (WORD)h);
    fourcc(f, "strf"); put32(f, 40);
    put32(f, 40); put32(f, w); put32(f, h); put16(f, 1); put16(f, 24); fourcc(f, "MJPG");
    put32(f, w * h * 3); put32(f, 0); put32(f, 0); put32(f, 0); put32(f, 0);
    fourcc(f, "LIST"); put32(f, movi); fourcc(f, "movi");
    for (int k = 0; k < frames; k++) {
        Slot *x = &s[pick[k]];
        fourcc(f, "00dc"); put32(f, x->len);
        fwrite(x->jpg, 1, x->len, f);
        if (x->len & 1)
            fputc(0, f);
    }
    fourcc(f, "idx1"); put32(f, idx);
    DWORD off = 4;
    for (int k = 0; k < frames; k++) {
        Slot *x = &s[pick[k]];
        fourcc(f, "00dc"); put32(f, 0x10); put32(f, off); put32(f, x->len);
        off += 8 + ((x->len + 1) & ~1u);
    }
    int ok = !ferror(f);
    fclose(f);
    free(pick);
    return ok;
}

static void save(void)
{
    /* A copy of the ring, oldest first; the JPEGs stay owned by the ring while the worker
     * (the only one freeing them) writes. */
    Slot *s = malloc(sizeof(Slot) * RING);
    int n = 0;
    UINT w, h;
    EnterCriticalSection(&lock);
    for (int i = 0; s && i < count; i++)
        s[n++] = ring[(head - count + i + RING) % RING];
    w = ring_w, h = ring_h;
    LeaveCriticalSection(&lock);
    int ok = s && n > 1 && write_avi(save_path, s, n, w, h);
    coop_log("clip: %s %s (%d frames, %.0f s)", ok ? "saved" : "NOT saved", save_path, n,
             n > 1 ? s[n - 1].t - s[0].t : 0.0);
    free(s);
}

static DWORD WINAPI worker(LPVOID arg)
{
    (void)arg;
    IWICImagingFactory *fac = NULL;
    if (FAILED(CoInitializeEx(NULL, COINIT_MULTITHREADED)) ||
        FAILED(CoCreateInstance(&CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, &IID_IWICImagingFactory,
                                (void **)&fac))) {
        coop_log("clip: no JPEG codec (WIC), clips off");
        return 0;
    }
    for (;;) {
        WaitForSingleObject(wake, 500);
        if (InterlockedCompareExchange(&raw_ready, 0, 0)) {
            DWORD len = 0;
            unsigned char *jpg = encode_jpeg(fac, raw, raw_w, raw_h, &len);
            UINT w = raw_w, h = raw_h;
            double t = raw_t;
            InterlockedExchange(&raw_ready, 0);
            if (jpg) {
                EnterCriticalSection(&lock);
                if (w != ring_w || h != ring_h) {   /* new size (window resized): start over */
                    for (int i = 0; i < RING; i++) {
                        free(ring[i].jpg);
                        ring[i].jpg = NULL;
                    }
                    head = count = 0;
                    ring_w = w, ring_h = h;
                }
                free(ring[head].jpg);
                ring[head].jpg = jpg, ring[head].len = len, ring[head].t = t;
                head = (head + 1) % RING;
                if (count < RING)
                    count++;
                LeaveCriticalSection(&lock);
            }
        }
        if (InterlockedCompareExchange(&save_req, 0, 0)) {
            save();
            InterlockedExchange(&save_req, 0);
        }
    }
}

void clip_release_device(void)
{
    if (sysmem)
        IDirect3DSurface9_Release(sysmem);
    sysmem = NULL;
    sm_w = sm_h = 0;
}

void clip_on_device(IDirect3DDevice9 *dev)
{
    static int done;
    char v[8];
    if (!dev || done || (GetEnvironmentVariableA("JERICHO_NOCLIP", v, sizeof v) > 0 && v[0] == '1'))
        return;
    done = 1;
    InitializeCriticalSection(&lock);
    wake = CreateEventA(NULL, FALSE, FALSE, NULL);
    HANDLE th = CreateThread(NULL, 0, worker, NULL, 0, NULL);
    if (!th)
        return;
    SetThreadPriority(th, THREAD_PRIORITY_BELOW_NORMAL);
    CloseHandle(th);
    void **vt = *(void ***)dev;
    DWORD old;
    if (VirtualProtect(&vt[VT_PRESENT], sizeof(void *), PAGE_READWRITE, &old)) {
        real_Present = (Present_t)vt[VT_PRESENT];
        vt[VT_PRESENT] = (void *)hook_Present;
        VirtualProtect(&vt[VT_PRESENT], sizeof(void *), old, &old);
        coop_log("clip: keeping the last %d s (F11 saves them)", CLIP_SECONDS);
    }
}

/* Net.CoopClip("save") -> the file being written, "" when there is nothing yet or a save runs. */
const char *clip_save(void)
{
    if (!wake || InterlockedCompareExchange(&save_req, 0, 0))
        return "";
    EnterCriticalSection(&lock);
    int n = count;
    LeaveCriticalSection(&lock);
    if (n < 2)
        return "";
    SYSTEMTIME st;
    GetLocalTime(&st);
    char name[64];
    snprintf(name, sizeof name, "coop:clip-%04u%02u%02u-%02u%02u%02u.avi", st.wYear, st.wMonth, st.wDay, st.wHour,
             st.wMinute, st.wSecond);
    if (!coop_data_path(name, save_path, sizeof save_path))
        return "";
    InterlockedExchange(&save_req, 1);
    SetEvent(wake);
    return save_path;
}

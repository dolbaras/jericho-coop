/*
 * In-game video capture for tests (env driven), so recordings contain only what the game
 * draws: screen grabs also catch whatever windows lie on top of the game.
 *
 *   JERICHO_RECORD=<file.raw>   append frames as raw BGRA, half resolution
 *   JERICHO_RECORD_FPS=<n>      frames per second (default 8)
 *   JERICHO_RECORD_START=<s>    seconds after device creation before recording (default 0)
 *
 * Writes <file.raw>.txt with "width height fps" once the size is known. Frames are copied
 * from the back buffer right before IDirect3DDevice9::Present (vtable slot 17).
 */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <stdlib.h>

#include "capture.h"
#include "coop_net.h"

#define VT_PRESENT 17

typedef HRESULT (WINAPI *Present_t)(IDirect3DDevice9 *, const RECT *, const RECT *, HWND, const RGNDATA *);
static Present_t real_Present;
static char path[MAX_PATH];
static FILE *out;
static double interval, start_after, created_at, last_at = -1e9;
static IDirect3DSurface9 *sysmem;
static UINT sw, sh;
static D3DFORMAT sf;
static unsigned char *row;
static int frames;

static double now(void)
{
    static LARGE_INTEGER freq;
    LARGE_INTEGER t;
    if (!freq.QuadPart)
        QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart / (double)freq.QuadPart;
}

static int complaints;

static void complain(const char *what, long code)
{
    if (complaints++ < 5)
        coop_log("capture: %s (0x%08lx)", what, (unsigned long)code);
}

static void grab(IDirect3DDevice9 *dev)
{
    IDirect3DSurface9 *bb = NULL;
    D3DSURFACE_DESC d;
    HRESULT hr = IDirect3DDevice9_GetBackBuffer(dev, 0, 0, D3DBACKBUFFER_TYPE_MONO, &bb);
    if (FAILED(hr)) {
        complain("GetBackBuffer failed", hr);
        return;
    }
    IDirect3DSurface9_GetDesc(bb, &d);
    if (d.Format != D3DFMT_X8R8G8B8 && d.Format != D3DFMT_A8R8G8B8) {
        complain("back buffer format", d.Format);
        IDirect3DSurface9_Release(bb);
        return;
    }
    /* The game renders with MSAA: resolve into a plain render target first. It is created
     * per frame and released at once, so it never blocks a device Reset. */
    IDirect3DSurface9 *src = bb, *resolved = NULL;
    if (d.MultiSampleType != D3DMULTISAMPLE_NONE) {
        hr = IDirect3DDevice9_CreateRenderTarget(dev, d.Width, d.Height, d.Format, D3DMULTISAMPLE_NONE, 0,
                                                 FALSE, &resolved, NULL);
        if (SUCCEEDED(hr))
            hr = IDirect3DDevice9_StretchRect(dev, bb, NULL, resolved, NULL, D3DTEXF_NONE);
        if (FAILED(hr)) {
            complain("MSAA resolve failed", hr);
            if (resolved)
                IDirect3DSurface9_Release(resolved);
            IDirect3DSurface9_Release(bb);
            return;
        }
        src = resolved;
    }
    if (!sysmem || d.Width != sw || d.Height != sh || d.Format != sf) {
        if (sysmem)
            IDirect3DSurface9_Release(sysmem);
        sysmem = NULL;
        if (FAILED(IDirect3DDevice9_CreateOffscreenPlainSurface(dev, d.Width, d.Height, d.Format,
                                                               D3DPOOL_SYSTEMMEM, &sysmem, NULL))) {
            if (resolved)
                IDirect3DSurface9_Release(resolved);
            IDirect3DSurface9_Release(bb);
            return;
        }
        sw = d.Width;
        sh = d.Height;
        sf = d.Format;
        free(row);
        row = malloc((sw / 2) * 4);
        char meta[MAX_PATH + 8];
        snprintf(meta, sizeof meta, "%s.txt", path);
        FILE *m = fopen(meta, "w");
        if (m) {
            fprintf(m, "%u %u %.3f\n", sw / 2, sh / 2, 1.0 / interval);
            fclose(m);
        }
        coop_log("capture: %ux%u -> %ux%u", sw, sh, sw / 2, sh / 2);
    }
    hr = IDirect3DDevice9_GetRenderTargetData(dev, src, sysmem);
    if (FAILED(hr))
        complain("GetRenderTargetData failed", hr);
    if (SUCCEEDED(hr)) {
        D3DLOCKED_RECT lr;
        if (SUCCEEDED(IDirect3DSurface9_LockRect(sysmem, &lr, NULL, D3DLOCK_READONLY))) {
            /* Half resolution: every other pixel of every other row. */
            for (UINT y = 0; y + 1 < sh; y += 2) {
                const unsigned int *src = (const unsigned int *)((const unsigned char *)lr.pBits + y * lr.Pitch);
                unsigned int *dst = (unsigned int *)row;
                for (UINT x = 0; x + 1 < sw; x += 2)
                    dst[x / 2] = src[x];
                fwrite(row, 4, sw / 2, out);
            }
            IDirect3DSurface9_UnlockRect(sysmem);
            fflush(out);   /* test runs end with the process killed */
            frames++;
        }
    }
    if (resolved)
        IDirect3DSurface9_Release(resolved);
    IDirect3DSurface9_Release(bb);
}

static HRESULT WINAPI hook_Present(IDirect3DDevice9 *dev, const RECT *s, const RECT *d, HWND w, const RGNDATA *r)
{
    static int seen;
    if (!seen++)
        coop_log("capture: first Present");
    double t = now();
    if (out && t - created_at >= start_after && t - last_at >= interval) {
        last_at = t;
        grab(dev);
    }
    return real_Present(dev, s, d, w, r);
}

int capture_enabled(void)
{
    if (!path[0] && GetEnvironmentVariableA("JERICHO_RECORD", path, MAX_PATH) == 0)
        return 0;
    return path[0] != 0;
}

void capture_on_device(IDirect3DDevice9 *dev)
{
    if (!dev || !capture_enabled() || out)
        return;
    char v[32];
    double fps = GetEnvironmentVariableA("JERICHO_RECORD_FPS", v, sizeof v) ? atof(v) : 8.0;
    if (fps <= 0)
        fps = 8.0;
    interval = 1.0 / fps;
    start_after = GetEnvironmentVariableA("JERICHO_RECORD_START", v, sizeof v) ? atof(v) : 0.0;
    created_at = now();
    out = fopen(path, "wb");
    if (!out)
        return;
    void **vt = *(void ***)dev;
    DWORD old;
    if (VirtualProtect(&vt[VT_PRESENT], sizeof(void *), PAGE_READWRITE, &old)) {
        real_Present = (Present_t)vt[VT_PRESENT];
        vt[VT_PRESENT] = (void *)hook_Present;
        VirtualProtect(&vt[VT_PRESENT], sizeof(void *), old, &old);
        coop_log("capture: recording to %s at %.1f fps after %.0f s", path, fps, start_after);
    }
}

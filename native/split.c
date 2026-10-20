/*
 * Local split screen in one game (work/splitscreen-research.md). The engine kept the
 * Scrapland split screen data: four users, a camera per user, and a HUD per user drawn in
 * the top and bottom halves (SplitScreen=1), but it renders the world once per frame, from
 * camera slot R_SplitScreenCamera (R_SplitScreen=1). The Lua side switches that slot every
 * frame and tells us which one this frame shows (Net.CoopSplit); here each frame's world is
 * squeezed into its half of a composite picture, and the composite (both halves, the other
 * one a frame old) goes back into the back buffer before the HUDs are drawn on top.
 *
 * The moment between world and HUD: the HUD loop sets the viewport of user 0's half
 * (0, 0, W, H/2) on the back buffer; nothing in the world pass does that.
 */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdlib.h>

#include "split.h"
#include "coop_net.h"
#include "display_hooks.h"

#define VT_RESET 16
#define VT_PRESENT 17
#define VT_SETVIEWPORT 47
#define VT_DRAWPRIMITIVE 81
#define VT_DRAWINDEXEDPRIMITIVE 82
#define VT_DRAWPRIMITIVEUP 83
#define VT_DRAWINDEXEDPRIMITIVEUP 84
#define VT_SETFVF 89

typedef HRESULT (WINAPI *Reset_t)(IDirect3DDevice9 *, D3DPRESENT_PARAMETERS *);
typedef HRESULT (WINAPI *Present_t)(IDirect3DDevice9 *, const RECT *, const RECT *, HWND, const RGNDATA *);
typedef HRESULT (WINAPI *SetViewport_t)(IDirect3DDevice9 *, const D3DVIEWPORT9 *);
typedef HRESULT (WINAPI *DrawPrimitiveUP_t)(IDirect3DDevice9 *, D3DPRIMITIVETYPE, UINT, const void *, UINT);
typedef HRESULT (WINAPI *DrawIndexedPrimitiveUP_t)(IDirect3DDevice9 *, D3DPRIMITIVETYPE, UINT, UINT, UINT, const void *,
                                                   D3DFORMAT, const void *, UINT);
typedef HRESULT (WINAPI *DrawPrimitive_t)(IDirect3DDevice9 *, D3DPRIMITIVETYPE, UINT, UINT);
typedef HRESULT (WINAPI *DrawIndexedPrimitive_t)(IDirect3DDevice9 *, D3DPRIMITIVETYPE, INT, UINT, UINT, UINT, UINT);
static DrawPrimitiveUP_t real_DrawPrimitiveUP;
static DrawIndexedPrimitiveUP_t real_DrawIndexedPrimitiveUP;
static DrawPrimitive_t real_DrawPrimitive;
static DrawIndexedPrimitive_t real_DrawIndexedPrimitive;
static Reset_t real_Reset;
static Present_t real_Present;
static SetViewport_t real_SetViewport;

static volatile LONG mode;        /* 0 off, 1 top/bottom (each half drawn wide), 2 top/bottom with the
                                     whole frame fitted in the half (black sides) */
static volatile LONG cam;         /* camera slot of the frame being drawn: 0 top, 1 bottom */
static int done_this_frame;
static IDirect3DSurface9 *composite, *resolved;
static IDirect3DTexture9 *composite_tex;   /* the composite as a texture (a multisampled back buffer
                                              takes it as a quad: StretchRect cannot write there) */
static IDirect3DStateBlock9 *saved_state;
static LONG composed_mode;                 /* the mode the composite was last drawn in */
static UINT cw, ch;
static D3DFORMAT cf;
static int complaints;

static void complain(const char *what, long code)
{
    if (complaints++ < 8)
        coop_log("split: %s (0x%08lx)", what, (unsigned long)code);
}

static void release_surfaces(void)
{
    if (saved_state) { IDirect3DStateBlock9_Release(saved_state); saved_state = NULL; }
    if (composite) { IDirect3DSurface9_Release(composite); composite = NULL; }
    if (composite_tex) { IDirect3DTexture9_Release(composite_tex); composite_tex = NULL; }
    if (resolved) { IDirect3DSurface9_Release(resolved); resolved = NULL; }
    cw = ch = 0;
}

/* The composite over the whole (multisampled) back buffer as one textured quad, the device's
   state saved and restored around it. */
static void draw_composite(IDirect3DDevice9 *dev)
{
    if (!saved_state && FAILED(IDirect3DDevice9_CreateStateBlock(dev, D3DSBT_ALL, &saved_state))) {
        complain("state block", 0);
        return;
    }
    IDirect3DStateBlock9_Capture(saved_state);
    struct { float x, y, z, rhw, u, v; } q[4] = {
        {-0.5f, -0.5f, 0, 1, 0, 0}, {(float)cw - 0.5f, -0.5f, 0, 1, 1, 0},
        {-0.5f, (float)ch - 0.5f, 0, 1, 0, 1}, {(float)cw - 0.5f, (float)ch - 0.5f, 0, 1, 1, 1}};
    D3DVIEWPORT9 vp = {0, 0, cw, ch, 0.0f, 1.0f};
    real_SetViewport(dev, &vp);
    IDirect3DDevice9_SetVertexShader(dev, NULL);
    IDirect3DDevice9_SetPixelShader(dev, NULL);
    IDirect3DDevice9_SetFVF(dev, D3DFVF_XYZRHW | D3DFVF_TEX1);
    IDirect3DDevice9_SetTexture(dev, 0, (IDirect3DBaseTexture9 *)composite_tex);
    IDirect3DDevice9_SetTextureStageState(dev, 0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
    IDirect3DDevice9_SetTextureStageState(dev, 0, D3DTSS_COLORARG1, D3DTA_TEXTURE);
    IDirect3DDevice9_SetTextureStageState(dev, 0, D3DTSS_ALPHAOP, D3DTOP_DISABLE);
    IDirect3DDevice9_SetTextureStageState(dev, 1, D3DTSS_COLOROP, D3DTOP_DISABLE);
    IDirect3DDevice9_SetSamplerState(dev, 0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
    IDirect3DDevice9_SetSamplerState(dev, 0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_ZENABLE, FALSE);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_ZWRITEENABLE, FALSE);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_ALPHABLENDENABLE, FALSE);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_ALPHATESTENABLE, FALSE);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_CULLMODE, D3DCULL_NONE);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_LIGHTING, FALSE);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_FOGENABLE, FALSE);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_STENCILENABLE, FALSE);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_SCISSORTESTENABLE, FALSE);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_COLORWRITEENABLE, 0xf);
    HRESULT hr = IDirect3DDevice9_DrawPrimitiveUP(dev, D3DPT_TRIANGLESTRIP, 2, q, sizeof q[0]);
    if (FAILED(hr)) complain("composite quad", hr);
    IDirect3DStateBlock9_Apply(saved_state);
}

/* Back buffer -> (resolved copy if multisampled) -> its half of the composite -> back buffer. */
static void compose(IDirect3DDevice9 *dev)
{
    IDirect3DSurface9 *bb = NULL, *rt = NULL;
    D3DSURFACE_DESC d;
    if (FAILED(IDirect3DDevice9_GetBackBuffer(dev, 0, 0, D3DBACKBUFFER_TYPE_MONO, &bb)))
        return;
    if (FAILED(IDirect3DDevice9_GetRenderTarget(dev, 0, &rt)) || rt != bb)
        goto out;   /* the HUD of an off-screen pass, not the frame */
    IDirect3DSurface9_GetDesc(bb, &d);
    if (d.Width != cw || d.Height != ch || d.Format != cf || !composite) {
        release_surfaces();
        HRESULT hr = IDirect3DDevice9_CreateTexture(dev, d.Width, d.Height, 1, D3DUSAGE_RENDERTARGET, d.Format,
                                                    D3DPOOL_DEFAULT, &composite_tex, NULL);
        if (FAILED(hr)) { complain("composite", hr); goto out; }
        IDirect3DTexture9_GetSurfaceLevel(composite_tex, 0, &composite);
        if (d.MultiSampleType != D3DMULTISAMPLE_NONE) {
            hr = IDirect3DDevice9_CreateRenderTarget(dev, d.Width, d.Height, d.Format, D3DMULTISAMPLE_NONE, 0,
                                                     FALSE, &resolved, NULL);
            if (FAILED(hr)) { complain("resolve target", hr); release_surfaces(); goto out; }
        }
        cw = d.Width; ch = d.Height; cf = d.Format;
        IDirect3DDevice9_ColorFill(dev, composite, NULL, D3DCOLOR_XRGB(0, 0, 0));
        composed_mode = mode;
        coop_log("split: composite %ux%u%s", cw, ch, resolved ? " (multisampled back buffer)" : "");
    }
    if (composed_mode != mode) {   /* another layout: no leftovers of the old one at the sides */
        IDirect3DDevice9_ColorFill(dev, composite, NULL, D3DCOLOR_XRGB(0, 0, 0));
        composed_mode = mode;
    }
    IDirect3DSurface9 *src = bb;
    if (resolved) {
        HRESULT hr = IDirect3DDevice9_StretchRect(dev, bb, NULL, resolved, NULL, D3DTEXF_NONE);
        if (FAILED(hr)) { complain("resolve", hr); goto out; }
        src = resolved;
    }
    static int composes;
    if (composes++ < 16)
        coop_log("split: compose cam %ld", (long)cam);
    LONG mid = (LONG)(ch + 1) / 2;   /* the HUD's halves: an odd height gives the top one more row */
    RECT half = {0, cam ? mid : 0, (LONG)cw, cam ? (LONG)ch : mid};
    if (mode == 2) {
        /* Full view: the whole frame, its shape kept, in the middle of the half (black sides). */
        LONG h = half.bottom - half.top, w = (LONG)((double)cw * h / ch + 0.5);
        half.left = ((LONG)cw - w) / 2;
        half.right = half.left + w;
    }
    HRESULT hr = IDirect3DDevice9_StretchRect(dev, src, NULL, composite, &half, D3DTEXF_LINEAR);
    if (FAILED(hr)) { complain("squeeze", hr); goto out; }
    if (!resolved) {
        hr = IDirect3DDevice9_StretchRect(dev, composite, NULL, bb, NULL, D3DTEXF_NONE);
        if (FAILED(hr)) complain("back to the back buffer", hr);
    } else {
        draw_composite(dev);
    }
out:
    if (rt) IDirect3DSurface9_Release(rt);
    IDirect3DSurface9_Release(bb);
}

static UINT bbw, bbh;   /* back buffer size, read at every Present */

static int vp_logged;   /* the first viewports after split mode is on, for diagnosis */
static int trace_frames;   /* JERICHO_SPLITTRACE: log the HUD pass draws of a few frames */
static int in_hud;         /* after the composite went back into the back buffer, until Present */
/* The power icons of the ammo HUD come one HUD pass late: user 0's are drawn first thing in user
   1's half viewport, user 1's on the whole screen after it (both in whole-screen places).
   4 (default) puts each in its user's half; tests (JERICHO_SPLITICONS): 0 as drawn, 1 skip
   the last ones, 2/3 split the last list by halves. */
static int icons_mode = 4;
static int hud_halves;     /* half viewports seen in this HUD pass (2 = both users' HUDs are done) */
static int bottom_draws;   /* draws since user 1's half viewport was set */
static D3DVIEWPORT9 cur_vp;

static void trace_draw(IDirect3DDevice9 *dev, const char *what, UINT count, const void *v, UINT stride)
{
    if (!in_hud || trace_frames <= 0)
        return;
    DWORD fvf = 0;
    IDirect3DDevice9_GetFVF(dev, &fvf);
    float miny = 1e9f, maxy = -1e9f, minx = 1e9f, maxx = -1e9f;
    if (v && stride >= 16 && (fvf & D3DFVF_XYZRHW)) {
        for (UINT i = 0; i < count && i < 64; i++) {
            const float *p = (const float *)((const char *)v + i * stride);
            if (p[0] < minx) minx = p[0];
            if (p[0] > maxx) maxx = p[0];
            if (p[1] < miny) miny = p[1];
            if (p[1] > maxy) maxy = p[1];
        }
    }
    coop_log("split trace: %s n=%u fvf=0x%lx vp=%lu,%lu %lux%lu x=%.0f..%.0f y=%.0f..%.0f", what, count, fvf,
             cur_vp.X, cur_vp.Y, cur_vp.Width, cur_vp.Height, minx, maxx, miny, maxy);
}

static HRESULT WINAPI hook_DrawPrimitiveUP(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE t, UINT n, const void *v, UINT stride)
{
    trace_draw(dev, "DrawPrimitiveUP", t == D3DPT_TRIANGLESTRIP || t == D3DPT_TRIANGLEFAN ? n + 2 : n * 3, v, stride);
    return real_DrawPrimitiveUP(dev, t, n, v, stride);
}

static HRESULT WINAPI hook_DrawIndexedPrimitiveUP(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE t, UINT mn, UINT nv, UINT n,
                                                  const void *idx, D3DFORMAT f, const void *v, UINT stride)
{
    trace_draw(dev, "DrawIndexedPrimitiveUP", nv, v, stride);
    return real_DrawIndexedPrimitiveUP(dev, t, mn, nv, n, idx, f, v, stride);
}

static HRESULT WINAPI hook_DrawPrimitive(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE t, UINT start, UINT n)
{
    trace_draw(dev, "DrawPrimitive", n, NULL, 0);
    /* After both users' HUDs, on the whole screen: the power icons of both users in one list
       (two quads each), placed in whole-screen space. Each user's pair goes to its half. */
    /* Icon lists: pairs of quads (a fade or a single sprite is 2 triangles and stays as it is). */
    int icons = t == D3DPT_TRIANGLELIST && n >= 4 && n <= 16 && n % 4 == 0;
    if (mode && in_hud && icons_mode == 4 && icons) {
        D3DVIEWPORT9 top = cur_vp, bottom = cur_vp;
        DWORD mid = (bbh + 1) / 2;
        top.Y = 0; top.Height = mid; bottom.Y = mid; bottom.Height = bbh - mid;
        if (hud_halves >= 2 && cur_vp.Y == mid && bottom_draws++ == 0) {
            /* user 0's icons, drawn late, in user 1's pass */
            real_SetViewport(dev, &top);
            HRESULT hr = real_DrawPrimitive(dev, t, start, n);
            real_SetViewport(dev, &cur_vp);
            return hr;
        }
        if (hud_halves >= 2 && cur_vp.Y == 0 && cur_vp.Height == bbh) {
            real_SetViewport(dev, &bottom);
            HRESULT hr = real_DrawPrimitive(dev, t, start, n);
            real_SetViewport(dev, &cur_vp);
            return hr;
        }
    }
    if (mode && in_hud && hud_halves >= 2 && icons_mode > 0 && icons_mode < 4 && t == D3DPT_TRIANGLELIST && n >= 4 &&
        n % 4 == 0 && cur_vp.Height == bbh) {
        if (icons_mode == 1)
            return D3D_OK;
        D3DVIEWPORT9 full = cur_vp, top = cur_vp, bottom = cur_vp;
        DWORD mid = (bbh + 1) / 2;
        top.Height = mid;
        bottom.Y = mid;
        bottom.Height = bbh - mid;
        UINT h = n / 2;
        real_SetViewport(dev, icons_mode == 2 ? &top : &bottom);
        real_DrawPrimitive(dev, t, start, h);
        real_SetViewport(dev, icons_mode == 2 ? &bottom : &top);
        HRESULT hr = real_DrawPrimitive(dev, t, start + h * 3, n - h);
        real_SetViewport(dev, &full);
        return hr;
    }
    return real_DrawPrimitive(dev, t, start, n);
}

static HRESULT WINAPI hook_DrawIndexedPrimitive(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE t, INT base, UINT mn, UINT nv,
                                                UINT si, UINT n)
{
    trace_draw(dev, "DrawIndexedPrimitive", nv, NULL, 0);
    return real_DrawIndexedPrimitive(dev, t, base, mn, nv, si, n);
}

static HRESULT WINAPI hook_SetViewport(IDirect3DDevice9 *dev, const D3DVIEWPORT9 *vp)
{
    if (vp)
        cur_vp = *vp;
    if (in_hud && vp && vp->X == 0 && vp->Width == bbw && vp->Y > 0 && vp->Y + vp->Height == bbh)
    {
        hud_halves = 2;   /* the bottom half: user 1's HUD; the next whole-screen draws follow it */
        bottom_draws = 0;
    }
    if (mode && vp && vp_logged < 12) {
        IDirect3DSurface9 *rt = NULL, *bb = NULL;
        IDirect3DDevice9_GetRenderTarget(dev, 0, &rt);
        IDirect3DDevice9_GetBackBuffer(dev, 0, 0, D3DBACKBUFFER_TYPE_MONO, &bb);
        coop_log("split: viewport %lu,%lu %lux%lu rt%s bb %ux%u", vp->X, vp->Y, vp->Width, vp->Height,
                 rt == bb ? "=bb" : "", bbw, bbh);
        if (rt) IDirect3DSurface9_Release(rt);
        if (bb) IDirect3DSurface9_Release(bb);
        vp_logged++;
    }
    if (mode && !done_this_frame && vp && bbw && vp->X == 0 && vp->Y == 0 && vp->Width == bbw &&
        vp->Height == (bbh + 1) / 2) {
        done_this_frame = 1;
        compose(dev);
        in_hud = 1;
        hud_halves = 1;
        if (trace_frames > 0)
            coop_log("split trace: ---- HUD pass, cam %ld", (long)cam);
    }
    return real_SetViewport(dev, vp);
}

static HRESULT WINAPI hook_Present(IDirect3DDevice9 *dev, const RECT *s, const RECT *d, HWND w, const RGNDATA *r)
{
    if (in_hud && trace_frames > 0)
        trace_frames--;
    in_hud = 0;
    /* A frame without the HUD (menus, scenes, HUD off): put it in its half anyway. */
    if (mode && !done_this_frame && cw)
        compose(dev);
    done_this_frame = 0;
    if (mode) {
        /* The next frame shows the other camera (Lua's per-frame update can run more than
           once per drawn frame, so the switch is made here, once per Present). */
        InterlockedExchange(&cam, cam ? 0 : 1);
        IDirect3DSurface9 *bb = NULL;
        D3DSURFACE_DESC desc;
        if (SUCCEEDED(IDirect3DDevice9_GetBackBuffer(dev, 0, 0, D3DBACKBUFFER_TYPE_MONO, &bb))) {
            IDirect3DSurface9_GetDesc(bb, &desc);
            IDirect3DSurface9_Release(bb);
            bbw = desc.Width;
            bbh = desc.Height;
        }
    }
    return real_Present(dev, s, d, w, r);
}

static HRESULT WINAPI hook_Reset(IDirect3DDevice9 *dev, D3DPRESENT_PARAMETERS *pp)
{
    release_surfaces();   /* D3DPOOL_DEFAULT: gone before a reset */
    return real_Reset(dev, pp);
}

static void *patch(void **vt, int slot, void *hook)
{
    DWORD old;
    void *orig = NULL;
    if (VirtualProtect(&vt[slot], sizeof(void *), PAGE_READWRITE, &old)) {
        orig = vt[slot];
        vt[slot] = hook;
        VirtualProtect(&vt[slot], sizeof(void *), old, &old);
    }
    return orig;
}

void split_on_device(IDirect3DDevice9 *dev)
{
    static int hooked;
    if (!dev || hooked)
        return;
    hooked = 1;
    void **vt = *(void ***)dev;
    real_Reset = (Reset_t)patch(vt, VT_RESET, (void *)hook_Reset);
    real_Present = (Present_t)patch(vt, VT_PRESENT, (void *)hook_Present);
    real_SetViewport = (SetViewport_t)patch(vt, VT_SETVIEWPORT, (void *)hook_SetViewport);
    char v[16];
    icons_mode = GetEnvironmentVariableA("JERICHO_SPLITICONS", v, sizeof v) > 0 ? atoi(v) : 4;
    real_DrawPrimitive = (DrawPrimitive_t)patch(vt, VT_DRAWPRIMITIVE, (void *)hook_DrawPrimitive);
    if (GetEnvironmentVariableA("JERICHO_SPLITTRACE", v, sizeof v) > 0) {
        trace_frames = atoi(v);
        real_DrawPrimitiveUP = (DrawPrimitiveUP_t)patch(vt, VT_DRAWPRIMITIVEUP, (void *)hook_DrawPrimitiveUP);
        real_DrawIndexedPrimitiveUP = (DrawIndexedPrimitiveUP_t)patch(vt, VT_DRAWINDEXEDPRIMITIVEUP,
                                                                      (void *)hook_DrawIndexedPrimitiveUP);
        real_DrawIndexedPrimitive = (DrawIndexedPrimitive_t)patch(vt, VT_DRAWINDEXEDPRIMITIVE,
                                                                  (void *)hook_DrawIndexedPrimitive);
    }
}

int split_set(int m)
{
    if (m != mode)
        coop_log("split: mode %d", m);
    if (m && !mode)
        display_hooks_pads_split(1, 0);
    InterlockedExchange(&mode, m);
    return (int)cam;
}

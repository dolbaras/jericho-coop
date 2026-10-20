/*
 * Local split screen in one game (docs/splitscreen-research.md). The engine kept the
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

/* Back buffer -> (resolved copy if multisampled) -> its half of the composite -> back buffer.
   0: not the frame's back buffer (the HUD of an off-screen pass), nothing done. */
static int compose(IDirect3DDevice9 *dev)
{
    IDirect3DSurface9 *bb = NULL, *rt = NULL;
    D3DSURFACE_DESC d;
    int frame = 1;
    if (FAILED(IDirect3DDevice9_GetBackBuffer(dev, 0, 0, D3DBACKBUFFER_TYPE_MONO, &bb)))
        return 0;
    if (FAILED(IDirect3DDevice9_GetRenderTarget(dev, 0, &rt)) || rt != bb) {
        frame = 0;
        goto out;
    }
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
    return frame;
}

static UINT bbw, bbh;   /* back buffer size, read at every Present */

/* Mode 2: a user's half viewport for the HUD shrunk to the picture in it (black sides), so the
   HUD keeps the shape it has on the whole screen instead of being stretched over the bars. */
static D3DVIEWPORT9 fit_vp(const D3DVIEWPORT9 *v)
{
    D3DVIEWPORT9 r = *v;
    if (mode == 2 && bbw && bbh && v->X == 0 && v->Width == bbw && v->Height < bbh) {
        DWORD w = (DWORD)((double)bbw * v->Height / bbh + 0.5);
        r.X = (bbw - w) / 2;
        r.Width = w;
    }
    return r;
}

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


/* Mode 2: each user's HUD is laid out as on the whole screen over its picture (fit_vp), and
   (hud_edges, default) what sits in its corners (weapons and ammo, squad, power icons, SMOD's
   health) goes out to the black sides, next to the screen's edges, so only the crosshair,
   messages and subtitles stay over the picture. The engine batches many HUD items in one draw,
   so each HUD draw is repeated: once over the picture with the corners cut away (scissor), and
   once per side, moved out by the side's width, cut to the corners. HUD units: 640x480. */
static int hud_edges = 1;   /* JERICHO_SPLITHUD=0: the whole HUD over the picture */
static IDirect3DBaseTexture9 *bound_texture(IDirect3DDevice9 *dev);
#define HUD_X_L 140
#define HUD_X_R 500
#define HUD_Y_T 110
#define HUD_Y_B 330

typedef struct {
    int indexed;   /* 0 DrawPrimitive, 1 DrawIndexedPrimitive, 2 DrawPrimitiveUP, 3 DrawIndexedPrimitiveUP */
    D3DPRIMITIVETYPE t;
    INT base;
    UINT start, n, mn, nv;
    const void *v, *idx;
    UINT stride;
    D3DFORMAT ifmt;
} hud_draw;

static HRESULT do_draw(IDirect3DDevice9 *dev, const hud_draw *g)
{
    switch (g->indexed) {
    case 1: return real_DrawIndexedPrimitive(dev, g->t, g->base, g->mn, g->nv, g->start, g->n);
    case 2: return real_DrawPrimitiveUP(dev, g->t, g->n, g->v, g->stride);
    case 3: return real_DrawIndexedPrimitiveUP(dev, g->t, g->mn, g->nv, g->n, g->idx, g->ifmt, g->v, g->stride);
    }
    return real_DrawPrimitive(dev, g->t, g->start, g->n);
}

static HRESULT draw_scissored(IDirect3DDevice9 *dev, const hud_draw *g, LONG l, LONG t, LONG r, LONG b)
{
    if (r <= l || b <= t)
        return D3D_OK;
    RECT rc = {l, t, r, b};
    IDirect3DDevice9_SetScissorRect(dev, &rc);
    return do_draw(dev, g);
}

/* A single quad (2 triangles) across most of the HUD: a fade or a full-screen overlay, drawn
   as it is over the picture. Read from the vertex buffer (the position comes first). */
static int is_overlay(IDirect3DDevice9 *dev, const hud_draw *g)
{
    if ((g->indexed != 0 && g->indexed != 2) || g->n != 2 ||
        (g->t != D3DPT_TRIANGLELIST && g->t != D3DPT_TRIANGLESTRIP && g->t != D3DPT_TRIANGLEFAN))
        return 0;
    UINT nverts = g->t == D3DPT_TRIANGLELIST ? 6 : 4;
    IDirect3DVertexBuffer9 *vb = NULL;
    UINT off = 0, stride = g->stride;
    const void *p = g->v;
    if (g->indexed == 0) {
        if (FAILED(IDirect3DDevice9_GetStreamSource(dev, 0, &vb, &off, &stride)) || !vb)
            return 0;
        void *lp = NULL;
        if (stride < 12 || FAILED(IDirect3DVertexBuffer9_Lock(vb, off + g->start * stride, nverts * stride, &lp,
                                                               D3DLOCK_READONLY)))
            lp = NULL;
        p = lp;
    }
    DWORD fvf = 0;
    IDirect3DDevice9_GetFVF(dev, &fvf);
    int full = 0;
    if (p && stride >= 12 && (fvf & D3DFVF_POSITION_MASK) == D3DFVF_XYZRHW) {
        float minx = 1e9f, maxx = -1e9f;
        for (UINT i = 0; i < nverts; i++) {
            float x = *(const float *)((const char *)p + i * stride);
            if (x < minx) minx = x;
            if (x > maxx) maxx = x;
        }
        full = maxx - minx > 0.6f * cur_vp.Width;
    } else if (p && stride >= 12) {
        D3DMATRIX w, v, pr;
        IDirect3DDevice9_GetTransform(dev, D3DTS_WORLD, &w);
        IDirect3DDevice9_GetTransform(dev, D3DTS_VIEW, &v);
        IDirect3DDevice9_GetTransform(dev, D3DTS_PROJECTION, &pr);
        const D3DMATRIX *m[3] = {&w, &v, &pr};
        float minx = 1e9f, maxx = -1e9f;
        for (UINT i = 0; i < nverts; i++) {
            const float *q = (const float *)((const char *)p + i * stride);
            float in[4] = {q[0], q[1], q[2], 1}, a[4];
            for (int k = 0; k < 3; k++) {
                for (int j = 0; j < 4; j++)
                    a[j] = in[0] * m[k]->m[0][j] + in[1] * m[k]->m[1][j] + in[2] * m[k]->m[2][j] + in[3] * m[k]->m[3][j];
                for (int j = 0; j < 4; j++)
                    in[j] = a[j];
            }
            float x = in[3] != 0 ? in[0] / in[3] : in[0];
            if (x < minx) minx = x;
            if (x > maxx) maxx = x;
        }
        full = maxx - minx > 1.2f;
    }
    if (vb) {
        if (p) IDirect3DVertexBuffer9_Unlock(vb);
        IDirect3DVertexBuffer9_Release(vb);
    }
    return full;
}

static HRESULT draw_hud(IDirect3DDevice9 *dev, const D3DVIEWPORT9 *pic, const hud_draw *g)
{
    real_SetViewport(dev, pic);
    int overlay = hud_edges && mode == 2 && is_overlay(dev, g);
    if (trace_frames > 0 && g->n == 2)
        coop_log("split trace: 2-triangle draw, overlay %d, texture %p", overlay, (void *)bound_texture(dev));
    if (!hud_edges || mode != 2 || overlay)
        return do_draw(dev, g);
    DWORD sc = FALSE;
    RECT old = {0, 0, (LONG)bbw, (LONG)bbh};
    IDirect3DDevice9_GetRenderState(dev, D3DRS_SCISSORTESTENABLE, &sc);
    IDirect3DDevice9_GetScissorRect(dev, &old);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_SCISSORTESTENABLE, TRUE);
    float sx = pic->Width / 640.0f, sy = pic->Height / 480.0f;
    LONG left = (LONG)pic->X, right = (LONG)(pic->X + pic->Width), top = (LONG)pic->Y, bot = (LONG)(pic->Y + pic->Height);
    LONG L = left + (LONG)(HUD_X_L * sx), R = left + (LONG)(HUD_X_R * sx);
    LONG T = top + (LONG)(HUD_Y_T * sy), B = top + (LONG)(HUD_Y_B * sy);
    /* over the picture: the middle band, and the top and bottom bands between the corners */
    HRESULT hr = draw_scissored(dev, g, left, T, right, B);
    draw_scissored(dev, g, L, top, R, T);
    draw_scissored(dev, g, L, B, R, bot);
    /* the left corners at the screen's left edge */
    D3DVIEWPORT9 v = *pic;
    LONG dl = left;
    v.X = 0;
    real_SetViewport(dev, &v);
    draw_scissored(dev, g, 0, top, L - dl, T);
    draw_scissored(dev, g, 0, B, L - dl, bot);
    /* the right corners at the right edge */
    LONG dr = (LONG)bbw - right;
    v.X = pic->X + dr;
    real_SetViewport(dev, &v);
    draw_scissored(dev, g, R + dr, top, (LONG)bbw, T);
    draw_scissored(dev, g, R + dr, B, (LONG)bbw, bot);
    IDirect3DDevice9_SetScissorRect(dev, &old);
    IDirect3DDevice9_SetRenderState(dev, D3DRS_SCISSORTESTENABLE, sc);
    return hr;
}

/* The picture viewport a HUD draw goes to (0: not a user's HUD draw). After both users'
   HUDs, on the whole screen: the power icons of both users in one list (two quads each),
   placed in whole-screen space; user 0's come first thing in user 1's pass. */
static IDirect3DBaseTexture9 *icons_tex;   /* the power icons' texture (compared only, no reference) */

static IDirect3DBaseTexture9 *bound_texture(IDirect3DDevice9 *dev)
{
    IDirect3DBaseTexture9 *t = NULL;
    if (SUCCEEDED(IDirect3DDevice9_GetTexture(dev, 0, &t)) && t)
        IDirect3DBaseTexture9_Release(t);   /* the pointer only identifies it */
    return t;
}

static int hud_target(IDirect3DDevice9 *dev, const hud_draw *g, D3DVIEWPORT9 *out)
{
    if (!mode || !in_hud)
        return 0;
    DWORD mid = (bbh + 1) / 2;
    D3DVIEWPORT9 top = cur_vp, bottom = cur_vp;
    top.X = 0; top.Width = bbw; top.Y = 0; top.Height = mid;
    bottom.X = 0; bottom.Width = bbw; bottom.Y = mid; bottom.Height = bbh - mid;
    /* two quads per icon, plus one when a power glows (trace: 8 or 10 triangles) */
    int icons = !g->indexed && g->t == D3DPT_TRIANGLELIST && g->n >= 4 && g->n <= 16 && g->n % 2 == 0;
    if (icons_mode == 4 && icons && hud_halves >= 2) {
        IDirect3DBaseTexture9 *tex = bound_texture(dev);
        /* user 0's: the first draw of user 1's pass, with the icons' texture once it is known
           (user 0 may have no icons this frame: then it is user 1's own first draw) */
        if (cur_vp.Y == mid && bottom_draws++ == 0 && (!icons_tex || tex == icons_tex)) {
            *out = fit_vp(&top);
            return 1;
        }
        if (cur_vp.Y == 0 && cur_vp.Height == bbh && cur_vp.Width == bbw) {
            icons_tex = tex;   /* user 1's, after both passes on the whole screen */
            *out = fit_vp(&bottom);
            return 1;
        }
    }
    if (mode == 2 && cur_vp.X == 0 && cur_vp.Width == bbw && cur_vp.Height < bbh) {
        *out = fit_vp(&cur_vp);
        return 1;
    }
    return 0;
}

static HRESULT hud_or_plain(IDirect3DDevice9 *dev, const hud_draw *g)
{
    D3DVIEWPORT9 pic;
    if (!hud_target(dev, g, &pic))
        return do_draw(dev, g);
    if (mode == 1) {   /* wide halves: the icons into their half, as drawn */
        real_SetViewport(dev, &pic);
        HRESULT hr = do_draw(dev, g);
        real_SetViewport(dev, &cur_vp);
        return hr;
    }
    HRESULT hr = draw_hud(dev, &pic, g);
    D3DVIEWPORT9 back = fit_vp(&cur_vp);
    real_SetViewport(dev, &back);
    return hr;
}

static HRESULT WINAPI hook_DrawPrimitive(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE t, UINT start, UINT n)
{
    trace_draw(dev, "DrawPrimitive", n, NULL, 0);
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
    hud_draw g = {0, t, 0, start, n, 0, 0, NULL, NULL, 0, D3DFMT_UNKNOWN};
    return hud_or_plain(dev, &g);
}

static HRESULT WINAPI hook_DrawIndexedPrimitive(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE t, INT base, UINT mn, UINT nv,
                                                UINT si, UINT n)
{
    trace_draw(dev, "DrawIndexedPrimitive", nv, NULL, 0);
    hud_draw g = {1, t, base, si, n, mn, nv, NULL, NULL, 0, D3DFMT_UNKNOWN};
    return hud_or_plain(dev, &g);
}

static HRESULT WINAPI hook_DrawPrimitiveUP(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE t, UINT n, const void *v, UINT stride)
{
    trace_draw(dev, "DrawPrimitiveUP", t == D3DPT_TRIANGLESTRIP || t == D3DPT_TRIANGLEFAN ? n + 2 : n * 3, v, stride);
    hud_draw g = {2, t, 0, 0, n, 0, 0, v, NULL, stride, D3DFMT_UNKNOWN};
    return hud_or_plain(dev, &g);
}

static HRESULT WINAPI hook_DrawIndexedPrimitiveUP(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE t, UINT mn, UINT nv, UINT n,
                                                  const void *idx, D3DFORMAT f, const void *v, UINT stride)
{
    trace_draw(dev, "DrawIndexedPrimitiveUP", nv, v, stride);
    hud_draw g = {3, t, 0, 0, n, mn, nv, v, idx, stride, f};
    return hud_or_plain(dev, &g);
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
        vp->Height == (bbh + 1) / 2 && compose(dev)) {
        done_this_frame = 1;
        in_hud = 1;
        hud_halves = 1;
        if (trace_frames > 0)
            coop_log("split trace: ---- HUD pass, cam %ld", (long)cam);
    }
    if (mode == 2 && in_hud && vp) {
        D3DVIEWPORT9 f = fit_vp(vp);
        return real_SetViewport(dev, &f);
    }
    return real_SetViewport(dev, vp);
}

/* Frames drawn without a Lua update before them (the per-view state set in Lua would be the
   other view's): counted for the log. */
static volatile LONG lua_calls;
static long presents, missed, doubled;

static HRESULT WINAPI hook_Present(IDirect3DDevice9 *dev, const RECT *s, const RECT *d, HWND w, const RGNDATA *r)
{
    if (mode) {
        LONG c = InterlockedExchange(&lua_calls, 0);
        presents++;
        if (c == 0) missed++;
        if (c > 1) doubled++;
        if (presents % 600 == 0)
            coop_log("split: %ld frames, %ld without a Lua update, %ld with several", presents, missed, doubled);
    }
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
    icons_tex = NULL;
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
    real_DrawIndexedPrimitive = (DrawIndexedPrimitive_t)patch(vt, VT_DRAWINDEXEDPRIMITIVE, (void *)hook_DrawIndexedPrimitive);
    hud_edges = GetEnvironmentVariableA("JERICHO_SPLITHUD", v, sizeof v) > 0 ? atoi(v) : 1;
    real_DrawPrimitiveUP = (DrawPrimitiveUP_t)patch(vt, VT_DRAWPRIMITIVEUP, (void *)hook_DrawPrimitiveUP);
    real_DrawIndexedPrimitiveUP = (DrawIndexedPrimitiveUP_t)patch(vt, VT_DRAWINDEXEDPRIMITIVEUP,
                                                                  (void *)hook_DrawIndexedPrimitiveUP);
    if (GetEnvironmentVariableA("JERICHO_SPLITTRACE", v, sizeof v) > 0) {
        trace_frames = atoi(v);
    }
}

int split_set(int m)
{
    InterlockedIncrement(&lua_calls);
    if (m != mode)
        coop_log("split: mode %d", m);
    if (m && !mode)
        display_hooks_pads_split(1, 0);
    InterlockedExchange(&mode, m);
    return (int)cam;
}

/* Import slot hooks of the exe that a loader patched first cannot undo (iat_guard.c). */
#ifndef IAT_GUARD_H
#define IAT_GUARD_H

typedef struct {
    void **slot;            /* the exe's import slot, NULL: dll!func is not imported by name */
    void *prev;             /* what the slot (or this DLL's cell for it) held: the "real" function to call on */
    int prepatched;         /* the slot held neither the system's function nor a hook of this DLL */
    int redirected;         /* the exe's instructions pointed at this DLL's cell (only when prepatched) */
    char by[64];            /* the module prev lies in (prepatched only) */
} iat_guard_result;

/* Hooks the exe's import of dll!func (by name) with hook; 1 when hooked. */
int iat_guard_hook(const char *dll, const char *func, void *hook, iat_guard_result *r);

#endif

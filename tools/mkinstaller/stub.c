/* Self-extracting setup stub for the co-op mods.
 *
 * The exe carries a release zip as resource 1 (RCDATA) and a small UTF-8 config as resource 2.
 * It checks the zip's SHA-256, unpacks it into a fresh folder under %TEMP%, runs the zip's
 * PowerShell installer from there (the installer's own window is the interface), waits,
 * returns its exit code and deletes the folder.
 *
 *   setup.exe [installer options]       everything after the exe name goes to the installer unchanged
 *   setup.exe --extract <folder>        only unpack into <folder> (audit/tests; nothing is run or deleted)
 *
 * Environment given to the installer: COOP_SETUP_DIR = the folder the setup exe lies in (the installer
 * looks for the game and for a Steam update package there), COOP_SETUP_FLAG = a file the installer
 * writes as its first act (not in -Quiet mode); a failed run without it means PowerShell never ran it.
 *
 * Build: tools/mkinstaller/mkinstaller.ps1 (zig cc -target x86-windows-gnu, windows subsystem).
 * No network, no registry, nothing is installed by the stub itself: files go to the temp folder only
 * and are removed again. Source file is UTF-8.
 */
#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <bcrypt.h>
#include <shellapi.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#define PATHMAX 1024
#define MAX_FILE (1u << 30)
#define LOCAL_SIG 0x04034b50u
#define CENTRAL_SIG 0x02014b50u
#define EOCD_SIG 0x06054b50u

/* ---------------------------------------------------------------- strings */

enum { M_DAMAGED, M_UNPACK, M_PS, M_NOSTART, M_ZIP, M_COUNT };

static const wchar_t *const TEXTS[6][M_COUNT] = {
    { /* en */
        L"This setup file is damaged (its built-in checksum does not match). Please download it again.",
        L"The installer could not be unpacked into the temporary folder.",
        L"Windows PowerShell could not be started. The installer needs it (it is part of Windows).",
        L"The installer window did not start. Windows, a security policy or an antivirus may have blocked PowerShell.",
        L"The .zip package of the same release does the same: unpack it and run \"Install Co-op.bat\".",
    },
    { /* ru */
        L"Файл установки повреждён (не совпадает встроенная контрольная сумма). Скачайте его ещё раз.",
        L"Не удалось распаковать установщик во временную папку.",
        L"Не удалось запустить Windows PowerShell. Установщику он нужен (это часть Windows).",
        L"Окно установщика не открылось. Возможно, PowerShell заблокировали Windows, политика безопасности или антивирус.",
        L"То же делает .zip-пакет этого же релиза: распакуйте его и запустите \"Install Co-op.bat\".",
    },
    { /* de */
        L"Diese Setup-Datei ist beschädigt (die eingebaute Prüfsumme stimmt nicht). Bitte laden Sie sie erneut herunter.",
        L"Das Installationsprogramm konnte nicht in den temporären Ordner entpackt werden.",
        L"Windows PowerShell konnte nicht gestartet werden. Das Installationsprogramm braucht es (es gehört zu Windows).",
        L"Das Installationsfenster wurde nicht gestartet. Windows, eine Sicherheitsrichtlinie oder ein Virenscanner hat PowerShell möglicherweise blockiert.",
        L"Das .zip-Paket derselben Version tut dasselbe: entpacken und \"Install Co-op.bat\" ausführen.",
    },
    { /* fr */
        L"Ce fichier d'installation est endommagé (sa somme de contrôle intégrée ne correspond pas). Veuillez le télécharger à nouveau.",
        L"L'installateur n'a pas pu être décompressé dans le dossier temporaire.",
        L"Windows PowerShell n'a pas pu être démarré. L'installateur en a besoin (il fait partie de Windows).",
        L"La fenêtre de l'installateur ne s'est pas ouverte. Windows, une stratégie de sécurité ou un antivirus a peut-être bloqué PowerShell.",
        L"Le paquet .zip de la même version fait la même chose : décompressez-le et lancez \"Install Co-op.bat\".",
    },
    { /* es */
        L"Este archivo de instalación está dañado (su suma de comprobación integrada no coincide). Descárguelo de nuevo.",
        L"No se pudo descomprimir el instalador en la carpeta temporal.",
        L"No se pudo iniciar Windows PowerShell. El instalador lo necesita (forma parte de Windows).",
        L"La ventana del instalador no se abrió. Windows, una directiva de seguridad o un antivirus puede haber bloqueado PowerShell.",
        L"El paquete .zip de la misma versión hace lo mismo: descomprímalo y ejecute \"Install Co-op.bat\".",
    },
    { /* it */
        L"Questo file di installazione è danneggiato (il checksum incorporato non corrisponde). Scaricalo di nuovo.",
        L"Non è stato possibile estrarre il programma di installazione nella cartella temporanea.",
        L"Impossibile avviare Windows PowerShell. Il programma di installazione ne ha bisogno (fa parte di Windows).",
        L"La finestra del programma di installazione non si è aperta. Windows, un criterio di sicurezza o un antivirus potrebbe aver bloccato PowerShell.",
        L"Il pacchetto .zip della stessa versione fa lo stesso: estrailo ed esegui \"Install Co-op.bat\".",
    },
};

static const wchar_t *msg(int id)
{
    int l;
#ifdef FORCE_LANG   /* tests only: -CFlags "-DFORCE_LANG=<0..5>" renders every language's boxes on one PC */
    return TEXTS[FORCE_LANG][id];
#endif
    switch (PRIMARYLANGID(GetUserDefaultUILanguage())) {
    case LANG_RUSSIAN: l = 1; break;
    case LANG_GERMAN: l = 2; break;
    case LANG_FRENCH: l = 3; break;
    case LANG_SPANISH: l = 4; break;
    case LANG_ITALIAN: l = 5; break;
    default: l = 0;
    }
    return TEXTS[l][id];
}

/* ------------------------------------------------------------ small helpers */

typedef struct { wchar_t product[128], prefix[64], installer[128]; char sha[65]; } Config;
static Config cfg;

static size_t wlen(const wchar_t *s) { size_t n = 0; while (s[n]) n++; return n; }
static void wcopy(wchar_t *d, size_t cap, const wchar_t *s)
{
    size_t i = 0;
    if (!cap) return;
    for (; s[i] && i + 1 < cap; i++) d[i] = s[i];
    d[i] = 0;
}
static int wcat(wchar_t *d, size_t cap, const wchar_t *s)
{
    size_t n = wlen(d), i = 0;
    for (; s[i]; i++) { if (n + 1 >= cap) { d[n] = 0; return 0; } d[n++] = s[i]; }
    d[n] = 0;
    return 1;
}
static wchar_t lower(wchar_t c) { return (c >= L'A' && c <= L'Z') ? (wchar_t)(c + 32) : c; }
static int wprefix_i(const wchar_t *s, const wchar_t *p)
{
    while (*p) { if (lower(*s) != lower(*p)) return 0; s++; p++; }
    return 1;
}
static int weq_i(const wchar_t *a, const wchar_t *b) { return wprefix_i(a, b) && wlen(a) == wlen(b); }

static void show_error(const wchar_t *text, const wchar_t *detail)
{
    static wchar_t buf[4096];
    wcopy(buf, 4096, text);
    if (detail && detail[0]) { wcat(buf, 4096, L"\n\n"); wcat(buf, 4096, detail); }
    MessageBoxW(NULL, buf, cfg.product[0] ? cfg.product : L"Setup", MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
}

/* what + " (Windows error N)" */
static void detail_of(wchar_t *out, size_t cap, const wchar_t *what, DWORD err)
{
    wcopy(out, cap, what);
    if (err) {
        wchar_t t[16], num[16];
        int k = 0, n = 0, i;
        DWORD v = err;
        while (v) { t[k++] = (wchar_t)(L'0' + v % 10); v /= 10; }
        for (i = k - 1; i >= 0; i--) num[n++] = t[i];
        num[n] = 0;
        wcat(out, cap, L"  (Windows error ");
        wcat(out, cap, num);
        wcat(out, cap, L")");
    }
}

static void put_line(const char *p, size_t len, const char *key, wchar_t *dst, int cap)
{
    size_t kl = strlen(key);
    if (len > kl && !memcmp(p, key, kl) && p[kl] == '=') {
        int n = MultiByteToWideChar(CP_UTF8, 0, p + kl + 1, (int)(len - kl - 1), dst, cap - 1);
        dst[n > 0 ? n : 0] = 0;
    }
}

static int parse_config(const char *p, size_t n)
{
    size_t i = 0;
    cfg.product[0] = cfg.prefix[0] = cfg.installer[0] = 0; cfg.sha[0] = 0;
    while (i < n) {
        size_t s = i, e;
        while (i < n && p[i] != '\n') i++;
        e = i; if (i < n) i++;
        while (e > s && (p[e - 1] == '\r' || p[e - 1] == ' ')) e--;
        put_line(p + s, e - s, "product", cfg.product, 128);
        put_line(p + s, e - s, "prefix", cfg.prefix, 64);
        put_line(p + s, e - s, "installer", cfg.installer, 128);
        if (e - s == 7 + 64 && !memcmp(p + s, "sha256=", 7)) { memcpy(cfg.sha, p + s + 7, 64); cfg.sha[64] = 0; }
    }
    return cfg.product[0] && cfg.prefix[0] && cfg.installer[0] && cfg.sha[0];
}

/* ---------------------------------------------------------------- SHA-256 (the system's bcrypt) */

static int sha256_hex(const uint8_t *data, size_t len, char *out)
{
    BCRYPT_ALG_HANDLE alg = NULL; BCRYPT_HASH_HANDLE h = NULL;
    uint8_t d[32]; int ok = 0, i;
    static const char hex[] = "0123456789abcdef";
    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, NULL, 0) < 0) return 0;
    if (BCryptCreateHash(alg, &h, NULL, 0, NULL, 0, 0) >= 0) {
        size_t off = 0; ok = 1;
        while (ok && off < len) {
            size_t c = len - off; if (c > (1u << 24)) c = 1u << 24;
            if (BCryptHashData(h, (PUCHAR)data + off, (ULONG)c, 0) < 0) ok = 0;
            off += c;
        }
        if (ok && BCryptFinishHash(h, d, 32, 0) < 0) ok = 0;
        BCryptDestroyHash(h);
    }
    BCryptCloseAlgorithmProvider(alg, 0);
    if (!ok) return 0;
    for (i = 0; i < 32; i++) { out[2 * i] = hex[d[i] >> 4]; out[2 * i + 1] = hex[d[i] & 15]; }
    out[64] = 0;
    return 1;
}

static uint32_t crc_table[256];
static void crc_init(void)
{
    uint32_t n, k;
    for (n = 0; n < 256; n++) { uint32_t c = n; for (k = 0; k < 8; k++) c = (c & 1) ? 0xedb88320u ^ (c >> 1) : c >> 1; crc_table[n] = c; }
}
static uint32_t crc32_of(const uint8_t *p, size_t n)
{
    uint32_t c = 0xffffffffu;
    while (n--) c = crc_table[(c ^ *p++) & 0xff] ^ (c >> 8);
    return c ^ 0xffffffffu;
}

/* ---------------------------------------------------------------- inflate (RFC 1951; the canonical-Huffman method of zlib's puff) */

typedef struct {
    const uint8_t *in; size_t inlen, incnt; uint32_t bitbuf; int bitcnt;
    uint8_t *out; size_t outlen, outcnt; int eof;
} Inf;
typedef struct { short count[16]; short symbol[288]; } Huff;

static int ibits(Inf *s, int need)
{
    uint32_t val = s->bitbuf;
    while (s->bitcnt < need) {
        if (s->incnt >= s->inlen) { s->eof = 1; return 0; }
        val |= (uint32_t)s->in[s->incnt++] << s->bitcnt;
        s->bitcnt += 8;
    }
    s->bitbuf = val >> need;
    s->bitcnt -= need;
    return (int)(val & ((1u << need) - 1));
}

static int idecode(Inf *s, const Huff *h)
{
    int code = 0, first = 0, index = 0, len;
    for (len = 1; len <= 15; len++) {
        int count;
        code |= ibits(s, 1);
        if (s->eof) return -1;
        count = h->count[len];
        if (code - count < first) return h->symbol[index + (code - first)];
        index += count; first += count; first <<= 1; code <<= 1;
    }
    return -2;
}

static int iconstruct(Huff *h, const short *length, int n)
{
    int offs[16], len, sym, left;
    for (len = 0; len <= 15; len++) h->count[len] = 0;
    for (sym = 0; sym < n; sym++) h->count[length[sym]]++;
    if (h->count[0] == n) return 0;
    left = 1;
    for (len = 1; len <= 15; len++) { left <<= 1; left -= h->count[len]; if (left < 0) return left; }
    offs[1] = 0;
    for (len = 1; len < 15; len++) offs[len + 1] = offs[len] + h->count[len];
    for (sym = 0; sym < n; sym++) if (length[sym]) h->symbol[offs[length[sym]]++] = (short)sym;
    return left;
}

static int icodes(Inf *s, const Huff *lc, const Huff *dc)
{
    static const short lens[29] = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
    static const short lext[29] = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
    static const short dists[30] = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
    static const short dext[30] = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};
    for (;;) {
        int sym = idecode(s, lc);
        if (sym < 0) return 1;
        if (sym < 256) {
            if (s->outcnt >= s->outlen) return 2;
            s->out[s->outcnt++] = (uint8_t)sym;
        } else if (sym == 256) {
            return 0;
        } else {
            int len, ds; size_t dist;
            sym -= 257;
            if (sym >= 29) return 3;
            len = lens[sym] + ibits(s, lext[sym]);
            if (s->eof) return 1;
            ds = idecode(s, dc);
            if (ds < 0) return 1;
            if (ds >= 30) return 3;
            dist = (size_t)dists[ds] + (size_t)ibits(s, dext[ds]);
            if (s->eof) return 1;
            if (dist > s->outcnt) return 4;
            if (s->outcnt + (size_t)len > s->outlen) return 2;
            while (len--) { s->out[s->outcnt] = s->out[s->outcnt - dist]; s->outcnt++; }
        }
    }
}

static int istored(Inf *s)
{
    unsigned len, nlen;
    s->bitbuf = 0; s->bitcnt = 0;
    if (s->incnt + 4 > s->inlen) return 1;
    len = s->in[s->incnt] | (s->in[s->incnt + 1] << 8);
    nlen = s->in[s->incnt + 2] | (s->in[s->incnt + 3] << 8);
    s->incnt += 4;
    if (len != (~nlen & 0xffff)) return 2;
    if (s->incnt + len > s->inlen) return 1;
    if (s->outcnt + len > s->outlen) return 2;
    memcpy(s->out + s->outcnt, s->in + s->incnt, len);
    s->incnt += len; s->outcnt += len;
    return 0;
}

static int ifixed(Inf *s)
{
    static Huff fl, fd;
    static int built;
    if (!built) {
        short lengths[288]; int sym;
        for (sym = 0; sym < 144; sym++) lengths[sym] = 8;
        for (; sym < 256; sym++) lengths[sym] = 9;
        for (; sym < 280; sym++) lengths[sym] = 7;
        for (; sym < 288; sym++) lengths[sym] = 8;
        iconstruct(&fl, lengths, 288);
        for (sym = 0; sym < 30; sym++) lengths[sym] = 5;
        iconstruct(&fd, lengths, 30);
        built = 1;
    }
    return icodes(s, &fl, &fd);
}

static int idynamic(Inf *s)
{
    static const short order[19] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};
    short lengths[320]; Huff lc, dc;
    int nlen, ndist, ncode, index, err;
    nlen = ibits(s, 5) + 257; ndist = ibits(s, 5) + 1; ncode = ibits(s, 4) + 4;
    if (s->eof) return 1;
    if (nlen > 286 || ndist > 30) return 3;
    for (index = 0; index < ncode; index++) lengths[order[index]] = (short)ibits(s, 3);
    for (; index < 19; index++) lengths[order[index]] = 0;
    if (s->eof) return 1;
    if (iconstruct(&lc, lengths, 19) != 0) return 4;
    index = 0;
    while (index < nlen + ndist) {
        int symbol = idecode(s, &lc);
        if (symbol < 0) return 1;
        if (symbol < 16) {
            lengths[index++] = (short)symbol;
        } else {
            int len = 0, rep;
            if (symbol == 16) { if (index == 0) return 5; len = lengths[index - 1]; rep = 3 + ibits(s, 2); }
            else if (symbol == 17) rep = 3 + ibits(s, 3);
            else rep = 11 + ibits(s, 7);
            if (s->eof) return 1;
            if (index + rep > nlen + ndist) return 6;
            while (rep--) lengths[index++] = (short)len;
        }
    }
    if (lengths[256] == 0) return 7;
    err = iconstruct(&lc, lengths, nlen);
    if (err && (err < 0 || nlen != lc.count[0] + lc.count[1])) return 8;
    err = iconstruct(&dc, lengths + nlen, ndist);
    if (err && (err < 0 || ndist != dc.count[0] + dc.count[1])) return 9;
    return icodes(s, &lc, &dc);
}

/* 0 = ok, and exactly outlen bytes were produced */
static int inflate_raw(const uint8_t *in, size_t inlen, uint8_t *out, size_t outlen)
{
    Inf s; int last, type, err = 0;
    memset(&s, 0, sizeof s);
    s.in = in; s.inlen = inlen; s.out = out; s.outlen = outlen;
    do {
        last = ibits(&s, 1); type = ibits(&s, 2);
        if (s.eof) return 1;
        if (type == 0) err = istored(&s);
        else if (type == 1) err = ifixed(&s);
        else if (type == 2) err = idynamic(&s);
        else err = 10;
        if (err) return err;
    } while (!last);
    return s.outcnt == outlen ? 0 : 11;
}

/* ---------------------------------------------------------------- files and folders */

/* "\\?\" + path for a drive-letter path, so that long paths work */
static void ext_path(wchar_t *out, size_t cap, const wchar_t *p)
{
    if (p[0] && p[1] == L':' && p[2] == L'\\') { wcopy(out, cap, L"\\\\?\\"); wcat(out, cap, p); }
    else wcopy(out, cap, p);
}

static int make_dirs(const wchar_t *path)   /* path = absolute, backslashes */
{
    wchar_t buf[PATHMAX], ext[PATHMAX + 8];
    size_t i, n = wlen(path);
    if (n + 1 >= PATHMAX) return 0;
    wcopy(buf, PATHMAX, path);
    for (i = 3; i <= n; i++) {
        if (buf[i] == L'\\' || buf[i] == 0) {
            wchar_t c = buf[i];
            buf[i] = 0;
            ext_path(ext, PATHMAX + 8, buf);
            if (!CreateDirectoryW(ext, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) return 0;
            buf[i] = c;
            if (c == 0) break;
        }
    }
    return 1;
}

static int write_file(const wchar_t *path, const uint8_t *data, size_t n)
{
    wchar_t ext[PATHMAX + 8];
    HANDLE f; size_t off = 0;
    ext_path(ext, PATHMAX + 8, path);
    f = CreateFileW(ext, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) return 0;
    while (off < n) {
        DWORD w, c = (DWORD)((n - off) > (1u << 24) ? (1u << 24) : (n - off));
        if (!WriteFile(f, data + off, c, &w, NULL) || !w) { CloseHandle(f); return 0; }
        off += w;
    }
    return CloseHandle(f) != 0;
}

/* removes dir and everything in it; a junction/symlink inside is unlinked, never followed */
static void rmtree(const wchar_t *dir, int depth)
{
    wchar_t pat[PATHMAX], full[PATHMAX], ext[PATHMAX + 8];
    WIN32_FIND_DATAW fd; HANDLE h;
    if (depth > 32 || wlen(dir) + 4 >= PATHMAX) return;
    wcopy(pat, PATHMAX, dir); wcat(pat, PATHMAX, L"\\*");
    ext_path(ext, PATHMAX + 8, pat);
    h = FindFirstFileW(ext, &fd);
    if (h != INVALID_HANDLE_VALUE) {
        do {
            if (fd.cFileName[0] == L'.' && (!fd.cFileName[1] || (fd.cFileName[1] == L'.' && !fd.cFileName[2]))) continue;
            wcopy(full, PATHMAX, dir); wcat(full, PATHMAX, L"\\");
            if (!wcat(full, PATHMAX, fd.cFileName)) continue;
            ext_path(ext, PATHMAX + 8, full);
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                if (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) RemoveDirectoryW(ext);
                else rmtree(full, depth + 1);
            } else {
                SetFileAttributesW(ext, FILE_ATTRIBUTE_NORMAL);
                DeleteFileW(ext);
            }
        } while (FindNextFileW(h, &fd));
        FindClose(h);
    }
    ext_path(ext, PATHMAX + 8, dir);
    RemoveDirectoryW(ext);
}

static int dir_exists(const wchar_t *p)
{
    DWORD a = GetFileAttributesW(p);
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY);
}
static int file_exists(const wchar_t *p) { return GetFileAttributesW(p) != INVALID_FILE_ATTRIBUTES; }

/* ---------------------------------------------------------------- zip */

static uint32_t rd32(const uint8_t *p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }
static unsigned rd16(const uint8_t *p) { return p[0] | (p[1] << 8); }

/* a zip entry name -> relative path with backslashes; 0 when it could escape the target folder or is not a plain name */
static int safe_name(const char *name, size_t n, wchar_t *out, size_t cap, int *is_dir)
{
    wchar_t w[PATHMAX]; int wn; size_t i, start = 0;
    if (n == 0 || n >= PATHMAX / 2) return 0;
    wn = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, (int)n, w, PATHMAX - 1);
    if (wn <= 0) return 0;
    w[wn] = 0;
    for (i = 0; i < (size_t)wn; i++) if (w[i] == L'\\') w[i] = L'/';   /* (Windows PowerShell 5.1's Compress-Archive writes backslashes into entry names) */
    *is_dir = (w[wn - 1] == L'/');
    if (*is_dir) w[--wn] = 0;
    if (wn == 0) return 0;
    for (i = 0; i <= (size_t)wn; i++) {
        if (w[i] == L'/' || w[i] == 0) {
            size_t len = i - start;
            if (len == 0) return 0;
            if (len == 1 && w[start] == L'.') return 0;
            if (len == 2 && w[start] == L'.' && w[start + 1] == L'.') return 0;
            if (w[i - 1] == L'.' || w[i - 1] == L' ') return 0;
            start = i + 1;
        }
        if (w[i] == L':' || w[i] == L'*' || w[i] == L'?' || w[i] == L'"' || w[i] == L'<' || w[i] == L'>' || w[i] == L'|' || (w[i] != 0 && w[i] < 32)) return 0;
    }
    for (i = 0; i < (size_t)wn; i++) if (w[i] == L'/') w[i] = L'\\';
    wcopy(out, cap, w);
    return 1;
}

/* unpacks the zip into dest (an existing absolute folder); 0 = ok, else a text in why */
static int extract_zip(const uint8_t *z, size_t zn, const wchar_t *dest, wchar_t *why, size_t whycap, int *nfiles)
{
    size_t eo, i, cdoff, cdsize; unsigned count, k;
    uint8_t *buf = NULL; size_t bufsize = 0;
    const uint8_t *cd;
    *nfiles = 0;
    if (zn < 22) { wcopy(why, whycap, L"payload: not a zip"); return 1; }
    eo = zn - 22;
    for (;; eo--) {
        if (rd32(z + eo) == EOCD_SIG) break;
        if (eo == 0 || zn - eo > 65557) { wcopy(why, whycap, L"payload: no zip directory"); return 1; }
    }
    count = rd16(z + eo + 10); cdsize = rd32(z + eo + 12); cdoff = rd32(z + eo + 16);
    if (count == 0xffff || cdsize == 0xffffffffu || cdoff == 0xffffffffu) { wcopy(why, whycap, L"payload: zip64 is not supported"); return 1; }
    if (cdoff + cdsize > zn) { wcopy(why, whycap, L"payload: bad zip directory"); return 1; }
    /* the biggest file decides the one buffer */
    cd = z + cdoff;
    for (k = 0, i = 0; k < count; k++) {
        size_t nl, el, cl;
        if (i + 46 > cdsize || rd32(cd + i) != CENTRAL_SIG) { wcopy(why, whycap, L"payload: bad zip entry"); return 1; }
        nl = rd16(cd + i + 28); el = rd16(cd + i + 30); cl = rd16(cd + i + 32);
        if (rd32(cd + i + 24) > bufsize) bufsize = rd32(cd + i + 24);
        i += 46 + nl + el + cl;
    }
    if (bufsize > MAX_FILE) { wcopy(why, whycap, L"payload: a file is too big"); return 1; }
    if (bufsize) {
        buf = (uint8_t *)VirtualAlloc(NULL, bufsize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (!buf) { detail_of(why, whycap, L"memory", GetLastError()); return 1; }
    }
    for (k = 0, i = 0; k < count; k++) {
        unsigned flags, method; uint32_t crc, csize, usize, lho;
        size_t nl, el, cl, dataoff; const uint8_t *lh;
        wchar_t rel[PATHMAX], full[PATHMAX]; int isdir;
        flags = rd16(cd + i + 8); method = rd16(cd + i + 10); crc = rd32(cd + i + 16);
        csize = rd32(cd + i + 20); usize = rd32(cd + i + 24);
        nl = rd16(cd + i + 28); el = rd16(cd + i + 30); cl = rd16(cd + i + 32); lho = rd32(cd + i + 42);
        if (!safe_name((const char *)cd + i + 46, nl, rel, PATHMAX, &isdir)) { wcopy(why, whycap, L"payload: unsafe file name"); goto fail; }
        i += 46 + nl + el + cl;
        wcopy(full, PATHMAX, dest); wcat(full, PATHMAX, L"\\");
        if (!wcat(full, PATHMAX, rel)) { wcopy(why, whycap, L"payload: path too long"); goto fail; }
        if (isdir) {
            if (!make_dirs(full)) { detail_of(why, whycap, full, GetLastError()); goto fail; }
            continue;
        }
        if (flags & 1) { wcopy(why, whycap, L"payload: encrypted entry"); goto fail; }
        if ((size_t)lho + 30 > zn) { wcopy(why, whycap, L"payload: bad entry"); goto fail; }
        lh = z + lho;
        if (rd32(lh) != LOCAL_SIG) { wcopy(why, whycap, L"payload: bad entry"); goto fail; }
        dataoff = (size_t)lho + 30 + rd16(lh + 26) + rd16(lh + 28);
        if (dataoff + csize > zn) { wcopy(why, whycap, L"payload: truncated entry"); goto fail; }
        /* the parent folder */
        {
            size_t p = wlen(full);
            wchar_t parent[PATHMAX];
            while (p > 0 && full[p - 1] != L'\\') p--;
            wcopy(parent, PATHMAX, full); parent[p > 0 ? p - 1 : 0] = 0;
            if (!make_dirs(parent)) { detail_of(why, whycap, parent, GetLastError()); goto fail; }
        }
        if (method == 0) {
            if (csize != usize) { wcopy(why, whycap, L"payload: bad stored entry"); goto fail; }
            if (crc32_of(z + dataoff, usize) != crc) { wcopy(why, whycap, L"payload: CRC mismatch"); goto fail; }
            if (!write_file(full, z + dataoff, usize)) { detail_of(why, whycap, full, GetLastError()); goto fail; }
        } else if (method == 8) {
            if (inflate_raw(z + dataoff, csize, buf, usize)) { wcopy(why, whycap, L"payload: bad compressed data"); goto fail; }
            if (crc32_of(buf, usize) != crc) { wcopy(why, whycap, L"payload: CRC mismatch"); goto fail; }
            if (!write_file(full, buf, usize)) { detail_of(why, whycap, full, GetLastError()); goto fail; }
        } else { wcopy(why, whycap, L"payload: unsupported compression"); goto fail; }
        (*nfiles)++;
    }
    if (buf) VirtualFree(buf, 0, MEM_RELEASE);
    return 0;
fail:
    if (buf) VirtualFree(buf, 0, MEM_RELEASE);
    return 1;
}

/* ---------------------------------------------------------------- command line */

/* the rest of the command line after the program name */
static const wchar_t *cmd_tail(const wchar_t *cl)
{
    if (*cl == L'"') { cl++; while (*cl && *cl != L'"') cl++; if (*cl) cl++; }
    else while (*cl && *cl != L' ' && *cl != L'\t') cl++;
    while (*cl == L' ' || *cl == L'\t') cl++;
    return cl;
}

static int append_quoted(wchar_t *d, size_t cap, const wchar_t *a)
{
    size_t n = wlen(d), bs = 0;
    if (n + 2 >= cap) return 0;
    d[n++] = L'"';
    for (; *a; a++) {
        if (*a == L'\\') { bs++; if (n + 2 >= cap) return 0; d[n++] = L'\\'; continue; }
        if (*a == L'"') { while (bs--) { if (n + 2 >= cap) return 0; d[n++] = L'\\'; } if (n + 3 >= cap) return 0; d[n++] = L'\\'; d[n++] = L'"'; bs = 0; continue; }
        bs = 0;
        if (n + 2 >= cap) return 0;
        d[n++] = *a;
    }
    while (bs--) { if (n + 2 >= cap) return 0; d[n++] = L'\\'; }
    d[n++] = L'"'; d[n] = 0;
    return 1;
}

/* ---------------------------------------------------------------- main */

static int find_ps(wchar_t *out, size_t cap)
{
    wchar_t win[MAX_PATH];
    BOOL wow = FALSE;
    UINT n = GetWindowsDirectoryW(win, MAX_PATH);
    if (!n || n >= MAX_PATH) return 0;
    IsWow64Process(GetCurrentProcess(), &wow);   /* a 32-bit stub on 64-bit Windows must reach the 64-bit PowerShell */
    wcopy(out, cap, win);
    wcat(out, cap, wow ? L"\\Sysnative\\WindowsPowerShell\\v1.0\\powershell.exe" : L"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe");
    if (file_exists(out)) return 1;
    wcopy(out, cap, win); wcat(out, cap, L"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe");
    return file_exists(out);
}

static void clean_stale(const wchar_t *base)
{
    wchar_t pat[PATHMAX], dir[PATHMAX], marker[PATHMAX];
    WIN32_FIND_DATAW fd; HANDLE h; FILETIME now; ULARGE_INTEGER n, c;
    GetSystemTimeAsFileTime(&now);
    n.LowPart = now.dwLowDateTime; n.HighPart = now.dwHighDateTime;
    wcopy(pat, PATHMAX, base); wcat(pat, PATHMAX, cfg.prefix); wcat(pat, PATHMAX, L"-*");
    h = FindFirstFileW(pat, &fd);
    if (h == INVALID_HANDLE_VALUE) return;
    do {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) continue;
        c.LowPart = fd.ftCreationTime.dwLowDateTime; c.HighPart = fd.ftCreationTime.dwHighDateTime;
        if (n.QuadPart < c.QuadPart || n.QuadPart - c.QuadPart < (ULONGLONG)24 * 3600 * 10000000ull) continue;
        wcopy(dir, PATHMAX, base); wcat(dir, PATHMAX, fd.cFileName);
        wcopy(marker, PATHMAX, dir); wcat(marker, PATHMAX, L"\\.coop-setup-temp");
        if (file_exists(marker)) rmtree(dir, 0);   /* only folders this stub made */
    } while (FindNextFileW(h, &fd));
    FindClose(h);
}

static const void *res(int id, DWORD *n)
{
    HRSRC r = FindResourceW(NULL, MAKEINTRESOURCEW(id), RT_RCDATA);
    HGLOBAL g;
    if (!r) return NULL;
    g = LoadResource(NULL, r);
    if (!g) return NULL;
    *n = SizeofResource(NULL, r);
    return LockResource(g);
}

static wchar_t g_tmp[PATHMAX], g_cmd[32768], g_why[2048], g_det[2048], g_exe[PATHMAX], g_dir[PATHMAX];

int WINAPI WinMain(HINSTANCE hi, HINSTANCE hp, LPSTR cl, int show)
{
    const uint8_t *zip; DWORD zipn = 0, cfgn = 0;
    const char *cfgdata; char sha[65];
    const wchar_t *tail; int extract_only = 0, quiet = 0, nfiles = 0, i, argc;
    wchar_t **argv; wchar_t base[PATHMAX], script[PATHMAX], ps[PATHMAX], flag[PATHMAX], marker[PATHMAX];
    uint8_t rnd[4]; static const char hexd[] = "0123456789abcdef";
    (void)hi; (void)hp; (void)cl; (void)show;
    crc_init();
    cfgdata = (const char *)res(2, &cfgn);
    zip = (const uint8_t *)res(1, &zipn);
    if (!cfgdata || !zip || !parse_config(cfgdata, cfgn)) { show_error(msg(M_DAMAGED), NULL); return 1; }
    if (!sha256_hex(zip, zipn, sha) || memcmp(sha, cfg.sha, 64)) { show_error(msg(M_DAMAGED), NULL); return 1; }

    tail = cmd_tail(GetCommandLineW());
    argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv && argc >= 3 && weq_i(argv[1], L"--extract")) {
        extract_only = 1;
        if (!GetFullPathNameW(argv[2], PATHMAX, g_tmp, NULL)) { show_error(msg(M_UNPACK), NULL); return 1; }
    }
    if (argv) for (i = 1; i < argc; i++) if (wprefix_i(argv[i], L"-q") || wprefix_i(argv[i], L"/q")) quiet = 1;

    if (!GetTempPathW(PATHMAX, base)) { detail_of(g_det, 2048, L"%TEMP%", GetLastError()); show_error(msg(M_UNPACK), g_det); return 1; }
    if (!extract_only) {
        int made = 0, tries;
        clean_stale(base);
        for (tries = 0; tries < 20 && !made; tries++) {
            wchar_t suffix[9];
            if (BCryptGenRandom(NULL, rnd, 4, BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0) { DWORD t = GetTickCount() ^ (GetCurrentProcessId() << 8) ^ (tries * 2654435761u); memcpy(rnd, &t, 4); }
            for (i = 0; i < 4; i++) { suffix[2 * i] = (wchar_t)hexd[rnd[i] >> 4]; suffix[2 * i + 1] = (wchar_t)hexd[rnd[i] & 15]; }
            suffix[8] = 0;
            wcopy(g_tmp, PATHMAX, base); wcat(g_tmp, PATHMAX, cfg.prefix); wcat(g_tmp, PATHMAX, L"-"); wcat(g_tmp, PATHMAX, suffix);
            if (CreateDirectoryW(g_tmp, NULL)) made = 1;
            else if (GetLastError() != ERROR_ALREADY_EXISTS) break;
        }
        if (!made) { detail_of(g_det, 2048, g_tmp, GetLastError()); show_error(msg(M_UNPACK), g_det); return 1; }
        { wchar_t lp[PATHMAX]; DWORD r = GetLongPathNameW(g_tmp, lp, PATHMAX); if (r && r < PATHMAX) wcopy(g_tmp, PATHMAX, lp); }
        wcopy(marker, PATHMAX, g_tmp); wcat(marker, PATHMAX, L"\\.coop-setup-temp");
        write_file(marker, (const uint8_t *)"1", 1);
    } else if (!make_dirs(g_tmp)) {
        detail_of(g_det, 2048, g_tmp, GetLastError()); show_error(msg(M_UNPACK), g_det); return 1;
    }

    if (extract_zip(zip, zipn, g_tmp, g_why, 2048, &nfiles)) {
        show_error(msg(M_UNPACK), g_why);
        if (!extract_only) rmtree(g_tmp, 0);
        return 1;
    }
    if (extract_only) return 0;

    /* where this exe lies */
    {
        size_t n = GetModuleFileNameW(NULL, g_exe, PATHMAX);
        if (n && n < PATHMAX) { wcopy(g_dir, PATHMAX, g_exe); while (n > 0 && g_dir[n - 1] != L'\\') n--; if (n > 3) n--; g_dir[n] = 0; }
    }
    wcopy(script, PATHMAX, g_tmp); wcat(script, PATHMAX, L"\\"); wcat(script, PATHMAX, cfg.installer);
    wcopy(flag, PATHMAX, g_tmp); wcat(flag, PATHMAX, L"\\.started");
    if (!file_exists(script) || !find_ps(ps, PATHMAX)) {
        detail_of(g_det, 2048, !file_exists(script) ? script : L"powershell.exe", 0);
        show_error(msg(M_PS), g_det);
        rmtree(g_tmp, 0);
        return 1;
    }
    SetEnvironmentVariableW(L"COOP_SETUP_DIR", g_dir);
    SetEnvironmentVariableW(L"COOP_SETUP_FLAG", flag);

    /* "powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<tmp>\installer.ps1" <the player's options> */
    g_cmd[0] = 0;
    append_quoted(g_cmd, 32768, ps);
    wcat(g_cmd, 32768, L" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ");
    append_quoted(g_cmd, 32768, script);
    if (*tail) { wcat(g_cmd, 32768, L" "); if (!wcat(g_cmd, 32768, tail)) { show_error(msg(M_PS), NULL); rmtree(g_tmp, 0); return 1; } }

    {
        STARTUPINFOW si; PROCESS_INFORMATION pi; DWORD flags = 0, code = 1; BOOL inherit = FALSE, ok;
        HANDLE hin = NULL, hout = NULL, herr = NULL;
        memset(&si, 0, sizeof si); si.cb = sizeof si;
        if (quiet) {
            /* console output of the installer: join the starter's console, or hand over the redirected handles */
            BOOL attached = AttachConsole(ATTACH_PARENT_PROCESS);
            SECURITY_ATTRIBUTES sa = { sizeof sa, NULL, TRUE };
            hin = GetStdHandle(STD_INPUT_HANDLE); hout = GetStdHandle(STD_OUTPUT_HANDLE); herr = GetStdHandle(STD_ERROR_HANDLE);
            if (attached) {
                if (!hout || hout == INVALID_HANDLE_VALUE) hout = CreateFileW(L"CONOUT$", GENERIC_WRITE | GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
                if (!herr || herr == INVALID_HANDLE_VALUE) herr = hout;
                if (!hin || hin == INVALID_HANDLE_VALUE) hin = CreateFileW(L"CONIN$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
            } else {
                flags = CREATE_NO_WINDOW;
            }
            if (hout && hout != INVALID_HANDLE_VALUE) {
                SetHandleInformation(hout, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
                if (herr && herr != INVALID_HANDLE_VALUE) SetHandleInformation(herr, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
                if (hin && hin != INVALID_HANDLE_VALUE) SetHandleInformation(hin, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
                si.dwFlags = STARTF_USESTDHANDLES;
                si.hStdOutput = hout; si.hStdError = (herr && herr != INVALID_HANDLE_VALUE) ? herr : hout;
                si.hStdInput = (hin && hin != INVALID_HANDLE_VALUE) ? hin : NULL;
                inherit = TRUE;
            }
        } else {
            flags = CREATE_NO_WINDOW;
        }
        /* (working folder: %TEMP%, not the unpacked folder, so that nothing the installer starts keeps that one locked) */
        ok = CreateProcessW(ps, g_cmd, NULL, NULL, inherit, flags, NULL, base, &si, &pi);
        if (!ok) {
            detail_of(g_det, 2048, ps, GetLastError());
            show_error(msg(M_PS), g_det);
            rmtree(g_tmp, 0);
            return 1;
        }
        CloseHandle(pi.hThread);
        WaitForSingleObject(pi.hProcess, INFINITE);
        if (!GetExitCodeProcess(pi.hProcess, &code)) code = 1;
        CloseHandle(pi.hProcess);
        if (!quiet && code != 0 && !file_exists(flag)) {
            wchar_t text[3072];
            wcopy(text, 3072, msg(M_NOSTART)); wcat(text, 3072, L"\n\n"); wcat(text, 3072, msg(M_ZIP));
            show_error(text, NULL);
        }
        /* the folder goes (an antivirus may still hold a file for a moment) */
        for (i = 0; i < 10; i++) { rmtree(g_tmp, 0); if (!dir_exists(g_tmp)) break; Sleep(300); }
        return (int)code;
    }
}

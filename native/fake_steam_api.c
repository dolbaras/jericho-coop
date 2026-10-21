/*
 * Test stand-in for steam_api.dll: the flat API functions steam_net.c uses, over UDP on
 * 127.0.0.1, so two game instances on one PC can run the whole Steam path (lobby, session
 * request, hello/welcome, data, parts, leaving) without two Steam accounts.
 * Used only when JERICHO_STEAM_DLL points at it (tools/run_pair.ps1 -FakeSteam).
 *
 *   JERICHO_FAKESTEAM_ID=<n>   this instance's Steam id (default: the process id)
 * Each id listens on UDP port 41000 + id % 1000. A lobby is a file in
 * %TEMP%\jericho-fakesteam: lobby_<owner>.txt with "jcoop=1"; joiners add member_<lobby>_<id>.
 * Every instance lists every lobby file but its own as a friend's lobby.
 * Packets: u8 channel, u64 from, payload. Messages from an unknown sender wait until the
 * session request (callback 1251) is accepted, as on Steam.
 *
 * Two PCs (added here; one game per PC):
 *   JERICHO_FAKESTEAM_PORT=<n>            this instance's UDP port (default 41000 + id % 1000)
 *   JERICHO_FAKESTEAM_REMOTE=<ip>:<port>:<id>   the other PC's instance: its packets go there,
 *                                         its lobby (id = its id) is joinable, it counts as a
 *                                         member of this one's lobby once it has sent anything
 *   JERICHO_FAKESTEAM_LISTREMOTE=1        list the remote instance as a friend with a lobby
 */
#include <winsock2.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EXPORT __declspec(dllexport)
typedef unsigned long long u64;

typedef struct Cb {
    struct Cb *next;
    int id;
    int size;
    char param[300];
} Cb;

typedef struct Msg {
    /* layout read by steam_net.c: data at 0, size at 4, sender identity at 16 */
    void *data;
    int size;
    int conn;
    int pad;
    char identity[136];
    /* ours */
    struct Msg *next;
    int channel;
    char buf[];
} Msg;

static SOCKET sock = INVALID_SOCKET;
static u64 me;
static Cb *cb_head, *cb_tail, *cb_current;
static Msg *held, *ready_q[2];
static u64 accepted[16];
static u64 my_lobby, joined_lobby;
static char dir[MAX_PATH];
static u64 next_call = 100;
static int dummy;

static void cb_push(int id, const void *param, int size)
{
    Cb *c = calloc(1, sizeof *c);
    c->id = id;
    c->size = size;
    memcpy(c->param, param, size);
    if (cb_tail)
        cb_tail->next = c;
    else
        cb_head = c;
    cb_tail = c;
}

/* An async call result: 703 now, the result through GetAPICallResult (and as a broadcast). */
static u64 call_result(int cb, const void *param, int size)
{
    u64 call = next_call++;
    char done[16] = {0};
    memcpy(done, &call, 8);
    memcpy(done + 8, &cb, 4);
    memcpy(done + 12, &size, 4);
    Cb *parked = calloc(1, sizeof *parked);   /* fetched by GetAPICallResult */
    parked->id = cb;
    parked->size = size;
    memcpy(parked->param, param, size);
    parked->next = cb_current;
    cb_current = parked;
    cb_push(703, done, 16);
    cb_push(cb, param, size);                  /* the broadcast (real Steam sends both) */
    return call;
}

static void lobby_path(char *out, u64 owner) { snprintf(out, MAX_PATH, "%s\\lobby_%llu.txt", dir, owner); }

static int port_of(u64 id) { return 41000 + (int)(id % 1000); }

static u64 remote_id;
static int remote_port, remote_seen, list_remote;
static unsigned long remote_ip;

static void read_remote(void)
{
    char v[96];
    if (GetEnvironmentVariableA("JERICHO_FAKESTEAM_REMOTE", v, sizeof v) > 0) {
        char *c1 = strchr(v, ':'), *c2 = c1 ? strchr(c1 + 1, ':') : NULL;
        if (c1 && c2) {
            *c1 = 0;
            *c2 = 0;
            remote_ip = inet_addr(v);
            remote_port = atoi(c1 + 1);
            remote_id = _strtoui64(c2 + 1, NULL, 10);
        }
    }
    list_remote = GetEnvironmentVariableA("JERICHO_FAKESTEAM_LISTREMOTE", v, sizeof v) > 0 && v[0] == '1';
}

EXPORT int __cdecl SteamAPI_InitFlat(char *err)
{
    char v[32];
    WSADATA w;
    WSAStartup(MAKEWORD(2, 2), &w);
    me = GetEnvironmentVariableA("JERICHO_FAKESTEAM_ID", v, sizeof v) ? _strtoui64(v, NULL, 10) : GetCurrentProcessId();
    GetTempPathA(MAX_PATH, dir);
    strcat(dir, "jericho-fakesteam");
    CreateDirectoryA(dir, NULL);
    sock = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET;
    read_remote();
    char pv[16];
    int own = GetEnvironmentVariableA("JERICHO_FAKESTEAM_PORT", pv, sizeof pv) > 0 ? atoi(pv) : port_of(me);
    a.sin_port = htons((u_short)own);
    a.sin_addr.s_addr = remote_id ? htonl(INADDR_ANY) : htonl(INADDR_LOOPBACK);
    if (bind(sock, (struct sockaddr *)&a, sizeof a) != 0) {
        strcpy(err, "fake steam: port in use");
        return 1;
    }
    u_long nb = 1;
    ioctlsocket(sock, FIONBIO, &nb);
    int big = 8 << 20;
    setsockopt(sock, SOL_SOCKET, SO_RCVBUF, (char *)&big, sizeof big);
    return 0;
}

EXPORT int __cdecl SteamAPI_GetHSteamPipe(void) { return 1; }
EXPORT void __cdecl SteamAPI_ManualDispatch_Init(void) {}

static void pump(void)
{
    static char buf[70000];
    for (;;) {
        int n = recv(sock, buf, sizeof buf, 0);
        if (n < 9)
            return;
        u64 from;
        memcpy(&from, buf + 1, 8);
        if (remote_id && from == remote_id)
            remote_seen = 1;
        Msg *m = calloc(1, sizeof *m + n - 9);
        m->channel = buf[0];
        m->size = n - 9;
        m->data = m->buf;
        memcpy(m->buf, buf + 9, n - 9);
        memcpy(m->identity + 8, &from, 8);   /* read back by GetSteamID64 */
        int ok = 0;
        for (int i = 0; i < 16; i++)
            ok |= accepted[i] == from;
        Msg **q = ok ? &ready_q[m->channel & 1] : &held;
        if (!ok) {
            int asked = 0;
            for (Msg *h = held; h; h = h->next)
                asked |= *(u64 *)(h->identity + 8) == from;
            if (!asked) {
                char id[136] = {0};
                memcpy(id + 8, &from, 8);
                cb_push(1251, id, 136);
            }
        }
        while (*q)
            q = &(*q)->next;
        *q = m;
    }
}

EXPORT void __cdecl SteamAPI_ManualDispatch_RunFrame(int pipe) { (void)pipe; pump(); }

EXPORT unsigned char __cdecl SteamAPI_ManualDispatch_GetNextCallback(int pipe, void *out)
{
    (void)pipe;
    if (!cb_head)
        return 0;
    struct { int user; int cb; char *param; int size; } *m = out;
    m->user = 1;
    m->cb = cb_head->id;
    m->param = cb_head->param;
    m->size = cb_head->size;
    return 1;
}

EXPORT void __cdecl SteamAPI_ManualDispatch_FreeLastCallback(int pipe)
{
    (void)pipe;
    if (!cb_head)
        return;
    Cb *c = cb_head;
    cb_head = c->next;
    if (!cb_head)
        cb_tail = NULL;
    free(c);
}

EXPORT unsigned char __cdecl SteamAPI_ManualDispatch_GetAPICallResult(int pipe, u64 call, void *buf, int size, int cb, unsigned char *failed)
{
    (void)pipe;
    (void)call;
    for (Cb **p = &cb_current; *p; p = &(*p)->next)
        if ((*p)->id == cb && (*p)->size <= size) {
            Cb *c = *p;
            memcpy(buf, c->param, c->size);
            *p = c->next;
            free(c);
            *failed = 0;
            return 1;
        }
    *failed = 1;
    return 0;
}

EXPORT void *__cdecl SteamAPI_SteamUser_v023(void) { return &dummy; }
EXPORT u64 __cdecl SteamAPI_ISteamUser_GetSteamID(void *s) { (void)s; return me; }
EXPORT void *__cdecl SteamAPI_SteamMatchmaking_v009(void) { return &dummy; }
EXPORT void *__cdecl SteamAPI_SteamFriends_v018(void) { return &dummy; }
EXPORT void *__cdecl SteamAPI_SteamNetworkingMessages_SteamAPI_v002(void) { return &dummy; }
EXPORT void *__cdecl SteamAPI_SteamNetworkingUtils_SteamAPI_v004(void) { return &dummy; }
EXPORT void __cdecl SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess(void *s) { (void)s; }

EXPORT u64 __cdecl SteamAPI_ISteamMatchmaking_CreateLobby(void *s, int type, int max)
{
    (void)s; (void)type; (void)max;
    char p[MAX_PATH];
    my_lobby = me;   /* the lobby id is the owner's id */
    lobby_path(p, me);
    FILE *f = fopen(p, "w");
    if (f) {
        fprintf(f, "jcoop=1\n");
        fclose(f);
    }
    char r[16] = {0};
    int ok = 1;
    memcpy(r, &ok, 4);
    memcpy(r + 8, &my_lobby, 8);
    return call_result(513, r, 16);
}

EXPORT u64 __cdecl SteamAPI_ISteamMatchmaking_JoinLobby(void *s, u64 lobby)
{
    (void)s;
    char p[MAX_PATH], r[24] = {0};
    lobby_path(p, lobby);
    unsigned response = GetFileAttributesA(p) != INVALID_FILE_ATTRIBUTES ? 1 : 2;
    if (remote_id && lobby == remote_id) {
        joined_lobby = lobby;
        response = 1;
    } else if (response == 1) {
        joined_lobby = lobby;
        char mp[MAX_PATH];
        snprintf(mp, MAX_PATH, "%s\\member_%llu_%llu", dir, lobby, me);
        FILE *f = fopen(mp, "w");
        if (f)
            fclose(f);
    }
    memcpy(r, &lobby, 8);
    memcpy(r + 16, &response, 4);
    return call_result(504, r, 24);
}

EXPORT void __cdecl SteamAPI_ISteamMatchmaking_LeaveLobby(void *s, u64 lobby)
{
    (void)s;
    char p[MAX_PATH];
    if (lobby == my_lobby) {
        lobby_path(p, lobby);
        DeleteFileA(p);
        my_lobby = 0;
    } else {
        snprintf(p, MAX_PATH, "%s\\member_%llu_%llu", dir, lobby, me);
        DeleteFileA(p);
        joined_lobby = 0;
    }
}

EXPORT unsigned char __cdecl SteamAPI_ISteamMatchmaking_SetLobbyData(void *s, u64 l, const char *k, const char *v)
{
    (void)s; (void)l; (void)k; (void)v;
    return 1;
}

EXPORT const char *__cdecl SteamAPI_ISteamMatchmaking_GetLobbyData(void *s, u64 l, const char *k)
{
    (void)s;
    char p[MAX_PATH];
    lobby_path(p, l);
    if (remote_id && l == remote_id)
        return strcmp(k, "jcoop") == 0 ? "1" : "";
    return GetFileAttributesA(p) != INVALID_FILE_ATTRIBUTES && strcmp(k, "jcoop") == 0 ? "1" : "";
}

EXPORT u64 __cdecl SteamAPI_ISteamMatchmaking_GetLobbyOwner(void *s, u64 l) { (void)s; return l; }

static u64 members[16];
static int count_members(u64 lobby)
{
    WIN32_FIND_DATAA fd;
    char pat[MAX_PATH], pre[64];
    int n = 0;
    members[n++] = lobby;
    if (remote_id && lobby == remote_id) {
        members[n++] = me;
        return n;
    }
    if (remote_id && lobby == my_lobby && remote_seen)
        members[n++] = remote_id;
    snprintf(pat, MAX_PATH, "%s\\member_%llu_*", dir, lobby);
    snprintf(pre, sizeof pre, "member_%llu_", lobby);
    HANDLE h = FindFirstFileA(pat, &fd);
    if (h != INVALID_HANDLE_VALUE) {
        do {
            if (n < 16)
                members[n++] = _strtoui64(fd.cFileName + strlen(pre), NULL, 10);
        } while (FindNextFileA(h, &fd));
        FindClose(h);
    }
    return n;
}

EXPORT int __cdecl SteamAPI_ISteamMatchmaking_GetNumLobbyMembers(void *s, u64 l) { (void)s; return count_members(l); }
EXPORT u64 __cdecl SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex(void *s, u64 l, int i)
{
    (void)s;
    count_members(l);
    return i >= 0 && i < 16 ? members[i] : 0;
}

EXPORT const char *__cdecl SteamAPI_ISteamFriends_GetPersonaName(void *s)
{
    (void)s;
    static char n[32];
    snprintf(n, sizeof n, "Fake%llu", me);
    return n;
}

static u64 friend_lobbies[16];
EXPORT int __cdecl SteamAPI_ISteamFriends_GetFriendCount(void *s, int flags)
{
    (void)s; (void)flags;
    WIN32_FIND_DATAA fd;
    char pat[MAX_PATH];
    int n = 0;
    if (remote_id && list_remote)
        friend_lobbies[n++] = remote_id;
    snprintf(pat, MAX_PATH, "%s\\lobby_*.txt", dir);
    HANDLE h = FindFirstFileA(pat, &fd);
    if (h != INVALID_HANDLE_VALUE) {
        do {
            u64 id = _strtoui64(fd.cFileName + 6, NULL, 10);
            if (id != me && n < 16)
                friend_lobbies[n++] = id;
        } while (FindNextFileA(h, &fd));
        FindClose(h);
    }
    return n;
}

EXPORT u64 __cdecl SteamAPI_ISteamFriends_GetFriendByIndex(void *s, int i, int flags)
{
    (void)s; (void)flags;
    return i >= 0 && i < 16 ? friend_lobbies[i] : 0;
}

EXPORT unsigned char __cdecl SteamAPI_ISteamFriends_GetFriendGamePlayed(void *s, u64 f, void *info)
{
    (void)s;
    char *p = info;
    u64 game = 480;
    memcpy(p, &game, 8);
    memcpy(p + 16, &f, 8);   /* the friend's lobby id is the friend's id */
    return 1;
}

EXPORT const char *__cdecl SteamAPI_ISteamFriends_GetFriendPersonaName(void *s, u64 f)
{
    (void)s;
    static char n[32];
    snprintf(n, sizeof n, "Fake%llu", f);
    return n;
}

EXPORT unsigned char __cdecl SteamAPI_ISteamFriends_SetRichPresence(void *s, const char *k, const char *v)
{
    (void)s; (void)k; (void)v;
    return 1;
}

EXPORT void __cdecl SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog(void *s, u64 l) { (void)s; (void)l; }

EXPORT void __cdecl SteamAPI_SteamNetworkingIdentity_SetSteamID64(void *id, u64 v) { memcpy((char *)id + 8, &v, 8); }
EXPORT u64 __cdecl SteamAPI_SteamNetworkingIdentity_GetSteamID64(const void *id)
{
    u64 v;
    memcpy(&v, (const char *)id + 8, 8);
    return v;
}

EXPORT int __cdecl SteamAPI_ISteamNetworkingMessages_SendMessageToUser(void *s, const void *id, const void *data, unsigned len, int flags, int channel)
{
    (void)s; (void)flags;
    static char buf[70000];
    if (len + 9 > sizeof buf)
        return 25;   /* limit exceeded */
    u64 to = SteamAPI_SteamNetworkingIdentity_GetSteamID64(id);
    buf[0] = (char)channel;
    memcpy(buf + 1, &me, 8);
    memcpy(buf + 9, data, len);
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET;
    a.sin_port = htons((u_short)port_of(to));
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (remote_id && to == remote_id) {
        a.sin_port = htons((u_short)remote_port);
        a.sin_addr.s_addr = remote_ip;
    }
    sendto(sock, buf, (int)len + 9, 0, (struct sockaddr *)&a, sizeof a);
    return 1;
}

EXPORT int __cdecl SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel(void *s, int channel, void **out, int max)
{
    (void)s;
    pump();
    int n = 0;
    Msg **q = &ready_q[channel & 1];
    while (*q && n < max) {
        Msg *m = *q;
        *q = m->next;
        out[n++] = m;
    }
    return n;
}

EXPORT unsigned char __cdecl SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser(void *s, const void *id)
{
    (void)s;
    u64 who = SteamAPI_SteamNetworkingIdentity_GetSteamID64(id);
    for (int i = 0; i < 16; i++)
        if (!accepted[i] || accepted[i] == who) {
            accepted[i] = who;
            break;
        }
    /* release what was held for this sender, in order */
    for (Msg **p = &held; *p;) {
        Msg *m = *p;
        if (*(u64 *)(m->identity + 8) == who) {
            *p = m->next;
            m->next = NULL;
            Msg **q = &ready_q[m->channel & 1];
            while (*q)
                q = &(*q)->next;
            *q = m;
        } else {
            p = &m->next;
        }
    }
    return 1;
}

EXPORT unsigned char __cdecl SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser(void *s, const void *id)
{
    (void)s;
    u64 who = SteamAPI_SteamNetworkingIdentity_GetSteamID64(id);
    for (int i = 0; i < 16; i++)
        if (accepted[i] == who)
            accepted[i] = 0;
    return 1;
}

EXPORT void __cdecl SteamAPI_SteamNetworkingMessage_t_Release(void *m) { free(m); }

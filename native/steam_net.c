/*
 * Steam transport for the co-op mod: friends join through a Steam lobby and all traffic goes
 * through Valve's relay network (ISteamNetworkingMessages), so nobody types an IP address or
 * opens a port. The game is not a Steam game, so the mod runs as Valve's free sample app
 * "Spacewar" (AppID 480): Steam shows both players as playing Spacewar.
 *
 * From the fork MAK-PIVO/jericho-coop (MIT). steam_api.dll (32-bit, Steamworks.NET standalone
 * 2025.164.1, SHA-256 fdafb7c65ec7d4182b42bf92cc8671c68e4dc547cc6e613899d2618a47eb65da) is
 * loaded from the mod's coop folder and driven through its flat C API with manual callback
 * dispatch; no Steamworks headers are needed. Struct offsets are the 32-bit ones listed in
 * coop-anything's playbook/networking-steam-spacewar.md.
 *
 * Protocol on top of NetworkingMessages:
 *   channel 1 (control): 'H' hello (client -> lobby owner until welcomed), 'W' welcome,
 *            'P'+time ping and 'Q'+time pong every second (keep-alive and round trip), 'B' bye.
 *   channel 0 (data): 'A'+payload a whole message; large reliable messages go as 'F' parts
 *            ending with an 'L' part.
 * A peer silent for 20 s, or one that leaves the lobby, is dropped. Steam reports no
 * disconnects on its own.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "coop_net.h"
#include "steam_net.h"

#define SC __cdecl
typedef int HSteamPipe;
typedef unsigned char sbool;   /* C++ bool returned in AL */

/* ---- flat API ---- */
static int(SC *s_InitFlat)(char *err);
static HSteamPipe(SC *s_GetHSteamPipe)(void);
static void(SC *s_MD_Init)(void);
static void(SC *s_MD_RunFrame)(HSteamPipe);
static sbool(SC *s_MD_GetNext)(HSteamPipe, void *msg);
static void(SC *s_MD_Free)(HSteamPipe);
static sbool(SC *s_MD_GetResult)(HSteamPipe, steam_id call, void *buf, int size, int cb, sbool *failed);
static void *(SC *s_User)(void);
static steam_id(SC *s_User_GetSteamID)(void *);
static void *(SC *s_MM)(void);
static steam_id(SC *s_MM_CreateLobby)(void *, int type, int max);
static steam_id(SC *s_MM_JoinLobby)(void *, steam_id);
static void(SC *s_MM_LeaveLobby)(void *, steam_id);
static sbool(SC *s_MM_SetLobbyData)(void *, steam_id, const char *, const char *);
static const char *(SC *s_MM_GetLobbyData)(void *, steam_id, const char *);
static steam_id(SC *s_MM_GetLobbyOwner)(void *, steam_id);
static int(SC *s_MM_GetNumMembers)(void *, steam_id);
static steam_id(SC *s_MM_GetMember)(void *, steam_id, int);
static void *(SC *s_Friends)(void);
static const char *(SC *s_F_GetPersonaName)(void *);
static int(SC *s_F_GetFriendCount)(void *, int flags);
static steam_id(SC *s_F_GetFriendByIndex)(void *, int, int flags);
static sbool(SC *s_F_GetFriendGamePlayed)(void *, steam_id, void *info);
static const char *(SC *s_F_GetFriendPersonaName)(void *, steam_id);
static sbool(SC *s_F_SetRichPresence)(void *, const char *, const char *);
static void(SC *s_F_InviteDialog)(void *, steam_id lobby);
static int(SC *s_F_GetPersonaState)(void *, steam_id);
static sbool(SC *s_MM_InviteUser)(void *, steam_id lobby, steam_id who);
static void *(SC *s_NM)(void);
static int(SC *s_NM_Send)(void *, const void *identity, const void *data, unsigned len, int flags, int channel);
static int(SC *s_NM_Receive)(void *, int channel, void **out, int max);
static sbool(SC *s_NM_Accept)(void *, const void *identity);
static sbool(SC *s_NM_Close)(void *, const void *identity);
static void(SC *s_Id_Set)(void *identity, steam_id);
static steam_id(SC *s_Id_Get)(const void *identity);
static void(SC *s_Msg_Release)(void *msg);
static void *(SC *s_Utils)(void);
static void(SC *s_U_InitRelay)(void *);

static const struct { void *slot; const char *name; } api[] = {
    {&s_InitFlat, "SteamAPI_InitFlat"},
    {&s_GetHSteamPipe, "SteamAPI_GetHSteamPipe"},
    {&s_MD_Init, "SteamAPI_ManualDispatch_Init"},
    {&s_MD_RunFrame, "SteamAPI_ManualDispatch_RunFrame"},
    {&s_MD_GetNext, "SteamAPI_ManualDispatch_GetNextCallback"},
    {&s_MD_Free, "SteamAPI_ManualDispatch_FreeLastCallback"},
    {&s_MD_GetResult, "SteamAPI_ManualDispatch_GetAPICallResult"},
    {&s_User, "SteamAPI_SteamUser_v023"},
    {&s_User_GetSteamID, "SteamAPI_ISteamUser_GetSteamID"},
    {&s_MM, "SteamAPI_SteamMatchmaking_v009"},
    {&s_MM_CreateLobby, "SteamAPI_ISteamMatchmaking_CreateLobby"},
    {&s_MM_JoinLobby, "SteamAPI_ISteamMatchmaking_JoinLobby"},
    {&s_MM_LeaveLobby, "SteamAPI_ISteamMatchmaking_LeaveLobby"},
    {&s_MM_SetLobbyData, "SteamAPI_ISteamMatchmaking_SetLobbyData"},
    {&s_MM_GetLobbyData, "SteamAPI_ISteamMatchmaking_GetLobbyData"},
    {&s_MM_GetLobbyOwner, "SteamAPI_ISteamMatchmaking_GetLobbyOwner"},
    {&s_MM_GetNumMembers, "SteamAPI_ISteamMatchmaking_GetNumLobbyMembers"},
    {&s_MM_GetMember, "SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex"},
    {&s_Friends, "SteamAPI_SteamFriends_v018"},
    {&s_F_GetPersonaName, "SteamAPI_ISteamFriends_GetPersonaName"},
    {&s_F_GetFriendCount, "SteamAPI_ISteamFriends_GetFriendCount"},
    {&s_F_GetFriendByIndex, "SteamAPI_ISteamFriends_GetFriendByIndex"},
    {&s_F_GetFriendGamePlayed, "SteamAPI_ISteamFriends_GetFriendGamePlayed"},
    {&s_F_GetFriendPersonaName, "SteamAPI_ISteamFriends_GetFriendPersonaName"},
    {&s_F_SetRichPresence, "SteamAPI_ISteamFriends_SetRichPresence"},
    {&s_F_InviteDialog, "SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog"},
    {&s_F_GetPersonaState, "SteamAPI_ISteamFriends_GetFriendPersonaState"},
    {&s_MM_InviteUser, "SteamAPI_ISteamMatchmaking_InviteUserToLobby"},
    {&s_NM, "SteamAPI_SteamNetworkingMessages_SteamAPI_v002"},
    {&s_NM_Send, "SteamAPI_ISteamNetworkingMessages_SendMessageToUser"},
    {&s_NM_Receive, "SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel"},
    {&s_NM_Accept, "SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser"},
    {&s_NM_Close, "SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser"},
    {&s_Id_Set, "SteamAPI_SteamNetworkingIdentity_SetSteamID64"},
    {&s_Id_Get, "SteamAPI_SteamNetworkingIdentity_GetSteamID64"},
    {&s_Msg_Release, "SteamAPI_SteamNetworkingMessage_t_Release"},
    {&s_Utils, "SteamAPI_SteamNetworkingUtils_SteamAPI_v004"},
    {&s_U_InitRelay, "SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess"},
};

/* Callback ids */
#define CB_LOBBY_JOIN_REQUESTED 333
#define CB_RICH_JOIN_REQUESTED 337
#define CB_LOBBY_ENTER 504
#define CB_LOBBY_CHAT_UPDATE 506
#define CB_LOBBY_CREATED 513
#define CB_CALL_COMPLETED 703
#define CB_SESSION_REQUEST 1251
#define CB_SESSION_FAILED 1252

#define SEND_UNRELIABLE 0
#define SEND_NO_NAGLE 1
#define SEND_RELIABLE 8
#define SEND_AUTO_RESTART 32
#define RESULT_OK 1
#define RESULT_LIMIT_EXCEEDED 25

#define CH_DATA 0
#define CH_CONTROL 1
static size_t part_size = 400000;   /* reliable messages above this go in parts (JERICHO_STEAM_PART in tests) */
#define TIMEOUT_S 20.0
#define MAX_REMOTES 16

typedef struct {
    steam_id id;
    int linked;                   /* host: said hello and joined; client: the host, welcomed us */
    double heard, last_ping;
    int rtt;
    char *part;                   /* message being reassembled from 'F' parts */
    size_t part_len, part_cap;
} Remote;

typedef struct Pending {
    struct Pending *next;
    steam_id to;
    int flags;
    unsigned len;
    char data[];
} Pending;

static int ready, tried;
static char error_text[1100];
static char persona[128];
static HSteamPipe pipe;
static void *user, *mm, *friends, *nm;
static steam_id me;

static int role;                  /* 0 none, 1 host, 2 client */
static steam_id lobby, owner, pending_lobby;
static int lobby_max;
static char lobby_text[256];
static double last_hello;
static Remote remotes[MAX_REMOTES];
static Pending *pend_head, *pend_tail;
static steam_event_fn emit;

static double now_s(void)
{
    static LARGE_INTEGER f;
    LARGE_INTEGER t;
    if (!f.QuadPart)
        QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart / (double)f.QuadPart;
}

static void to_cp1251(const char *utf8, char *out, size_t size)
{
    WCHAR w[256];
    out[0] = 0;
    if (!utf8 || !MultiByteToWideChar(CP_UTF8, 0, utf8, -1, w, 256))
        return;
    if (!WideCharToMultiByte(1251, 0, w, -1, out, (int)size, "?", NULL))
        out[0] = 0;
    out[size - 1] = 0;
    for (char *c = out; *c; c++)
        if (*c == '|' || *c == ';')
            *c = ' ';   /* separators of steam_net_friends and the lobby text */
}

int steam_net_init(void)
{
    if (ready || tried)
        return ready;
    tried = 1;
    char path[MAX_PATH], off[4];
    /* Test runs: the owner's Steam profile would show "playing Spacewar" with an open lobby. */
    if (GetEnvironmentVariableA("JERICHO_NOSTEAM", off, sizeof off) == 1 && off[0] == '1') {
        strcpy(error_text, "off for this run");
        return 0;
    }
    DWORD n = GetModuleFileNameA(NULL, path, MAX_PATH);
    char *slash = n ? strrchr(path, '\\') : NULL;
    if (!slash || (size_t)(slash - path) + 16 >= MAX_PATH) {
        strcpy(error_text, "no game folder");
        return 0;
    }
    /* <game>\coop\steam_api.dll: the mod's own copy, next to its Lua, so a steam_api.dll the
       game may have in bin is never replaced (here, unlike the fork MAK-PIVO/jericho-coop). */
    *slash = 0;
    char *up = strrchr(path, '\\');
    if (!up) {
        strcpy(error_text, "no game folder");
        return 0;
    }
    strcpy(up + 1, "coop\\steam_api.dll");
    /* Tests: native/fake_steam_api.c (Steam over localhost UDP) and its smaller packets. */
    char v[MAX_PATH];
    if (GetEnvironmentVariableA("JERICHO_STEAM_DLL", v, sizeof v) > 0)
        strcpy(path, v);
    if (GetEnvironmentVariableA("JERICHO_STEAM_PART", v, sizeof v) > 0 && atoi(v) > 0)
        part_size = (size_t)atoi(v);
    /* Spacewar: steam_api reads the app id from the environment before steam_appid.txt. */
    SetEnvironmentVariableA("SteamAppId", "480");
    SetEnvironmentVariableA("SteamGameId", "480");
    HMODULE dll = LoadLibraryA(path);
    if (!dll) {
        snprintf(error_text, sizeof error_text, "steam_api.dll not found");
        coop_log("steam: %s", error_text);
        return 0;
    }
    for (size_t i = 0; i < sizeof api / sizeof api[0]; i++) {
        FARPROC f = GetProcAddress(dll, api[i].name);
        if (!f) {
            snprintf(error_text, sizeof error_text, "steam_api.dll too old (no %s)", api[i].name);
            coop_log("steam: %s", error_text);
            return 0;
        }
        *(FARPROC *)api[i].slot = f;
    }
    char err[1024] = "";
    int r = s_InitFlat(err);
    if (r != 0) {
        snprintf(error_text, sizeof error_text, "%s",
                 r == 2 ? "Steam is not running" : r == 3 ? "Steam client too old" : err[0] ? err : "Steam init failed");
        coop_log("steam: init %d: %s", r, err);
        return 0;
    }
    s_MD_Init();
    pipe = s_GetHSteamPipe();
    user = s_User();
    mm = s_MM();
    friends = s_Friends();
    nm = s_NM();
    if (!user || !mm || !friends || !nm) {
        strcpy(error_text, "Steam interfaces missing");
        coop_log("steam: %s", error_text);
        return 0;
    }
    void *utils = s_Utils();
    if (utils)
        s_U_InitRelay(utils);
    me = s_User_GetSteamID(user);
    to_cp1251(s_F_GetPersonaName(friends), persona, sizeof persona);
    ready = 1;
    coop_log("steam: ready, id %llu, name %s", me, persona);
    return 1;
}

int steam_net_ready(void) { return ready; }
const char *steam_net_error(void) { return error_text; }
const char *steam_net_persona(void) { return persona; }
int steam_net_session(void) { return role != 0; }
steam_id steam_net_lobby(void) { return lobby; }

/* ---- remotes ---- */
static Remote *find_remote(steam_id id)
{
    for (int i = 0; i < MAX_REMOTES; i++)
        if (remotes[i].id == id)
            return &remotes[i];
    return NULL;
}

static Remote *get_remote(steam_id id)
{
    Remote *r = find_remote(id);
    if (r)
        return r;
    for (int i = 0; i < MAX_REMOTES; i++)
        if (!remotes[i].id) {
            memset(&remotes[i], 0, sizeof remotes[i]);
            remotes[i].id = id;
            remotes[i].heard = now_s();
            remotes[i].rtt = -1;
            return &remotes[i];
        }
    return NULL;
}

static void identity(char *buf, steam_id id)
{
    memset(buf, 0, 160);
    s_Id_Set(buf, id);
}

static int raw_send(steam_id to, int flags, int channel, const void *data, unsigned len)
{
    char id[160];
    identity(id, to);
    return s_NM_Send(nm, id, data, len, flags | SEND_NO_NAGLE | SEND_AUTO_RESTART, channel);
}

static void control(steam_id to, char what, int reliable)
{
    char b[9];
    double t = now_s();
    b[0] = what;
    memcpy(b + 1, &t, 8);
    raw_send(to, reliable ? SEND_RELIABLE : SEND_UNRELIABLE, CH_CONTROL, b, what == 'P' ? 9 : 1);
}

static void drop_remote(Remote *r, const char *why)
{
    if (!r || !r->id)
        return;
    coop_log("steam: drop %llu (%s)", r->id, why);
    if (r->linked && emit)
        emit(r->id, 'l', NULL, 0);
    char id[160];
    identity(id, r->id);
    s_NM_Close(nm, id);
    free(r->part);
    memset(r, 0, sizeof *r);
}

static int in_lobby(steam_id id)
{
    int n = s_MM_GetNumMembers(mm, lobby);
    for (int i = 0; i < n; i++)
        if (s_MM_GetMember(mm, lobby, i) == id)
            return 1;
    return 0;
}

/* ---- sending ---- */
static void pend_push(steam_id to, int flags, const void *data, unsigned len)
{
    Pending *p = malloc(sizeof *p + len);
    if (!p)
        return;
    p->next = NULL;
    p->to = to;
    p->flags = flags;
    p->len = len;
    memcpy(p->data, data, len);
    if (pend_tail)
        pend_tail->next = p;
    else
        pend_head = p;
    pend_tail = p;
}

static void pend_flush(void)
{
    while (pend_head) {
        int r = raw_send(pend_head->to, pend_head->flags, CH_DATA, pend_head->data, pend_head->len);
        if (r == RESULT_LIMIT_EXCEEDED)
            return;   /* the send buffer is still full: try on the next poll */
        Pending *p = pend_head;
        pend_head = p->next;
        if (!pend_head)
            pend_tail = NULL;
        free(p);
    }
}

static void send_frame(steam_id to, int reliable, char kind, const char *data, size_t len)
{
    char *b = malloc(len + 1);
    if (!b)
        return;
    b[0] = kind;
    memcpy(b + 1, data, len);
    int flags = reliable ? SEND_RELIABLE : SEND_UNRELIABLE;
    if (reliable && pend_head) {
        pend_push(to, flags, b, (unsigned)len + 1);   /* keep reliable messages in order */
    } else {
        int r = raw_send(to, flags, CH_DATA, b, (unsigned)len + 1);
        if (r == RESULT_LIMIT_EXCEEDED && reliable)
            pend_push(to, flags, b, (unsigned)len + 1);
        else if (r != RESULT_OK && reliable)
            coop_log("steam: send to %llu failed %d", to, r);
    }
    free(b);
}

int steam_net_send(steam_id to, int reliable, const void *data, size_t len)
{
    if (!ready || !role)
        return 0;
    const char *p = (const char *)data;
    if (!reliable || len <= part_size) {
        send_frame(to, reliable, 'A', p, len);
        return 1;
    }
    for (size_t off = 0; off < len; off += part_size) {
        size_t n = len - off < part_size ? len - off : part_size;
        send_frame(to, 1, off + n >= len ? 'L' : 'F', p + off, n);
    }
    return 1;
}

/* ---- lobby ---- */
void steam_net_set_text(const char *text)
{
    snprintf(lobby_text, sizeof lobby_text, "%s", text ? text : "");
    if (ready && role == 1 && lobby)
        s_MM_SetLobbyData(mm, lobby, "text", lobby_text);
}

void steam_net_host(int max_players, const char *text)
{
    if (!ready)
        return;
    steam_net_leave();
    role = 1;
    lobby_max = max_players;
    snprintf(lobby_text, sizeof lobby_text, "%s", text ? text : "");
    s_MM_CreateLobby(mm, 1 /* friends only */, max_players);
    coop_log("steam: creating lobby for %d", max_players);
}

void steam_net_join(steam_id id)
{
    if (!ready || !id)
        return;
    steam_net_leave();
    role = 2;
    lobby = id;
    owner = 0;
    s_MM_JoinLobby(mm, id);
    coop_log("steam: joining lobby %llu", id);
}

void steam_net_leave(void)
{
    if (!ready)
        return;
    for (int i = 0; i < MAX_REMOTES; i++)
        if (remotes[i].id) {
            control(remotes[i].id, 'B', 1);
            remotes[i].linked = 0;   /* no 'l' event: the caller closes the session itself */
            drop_remote(&remotes[i], "leaving");
        }
    if (lobby)
        s_MM_LeaveLobby(mm, lobby);
    if (role == 1) {
        s_F_SetRichPresence(friends, "connect", "");
        s_F_SetRichPresence(friends, "status", "");
    }
    while (pend_head) {
        Pending *p = pend_head;
        pend_head = p->next;
        free(p);
    }
    pend_tail = NULL;
    role = 0;
    lobby = owner = 0;
}

static void on_lobby_created(const char *p)
{
    int result;
    steam_id id;
    memcpy(&result, p, 4);
    memcpy(&id, p + 8, 8);
    if (role != 1 || lobby == id)
        return;   /* arrives twice: as the call result and as a broadcast */
    if (result != RESULT_OK) {
        coop_log("steam: lobby not created (%d)", result);
        snprintf(error_text, sizeof error_text, "Steam lobby not created (%d)", result);
        return;
    }
    lobby = id;
    owner = me;
    char connect[64];
    snprintf(connect, sizeof connect, "+connect_lobby %llu", id);
    s_MM_SetLobbyData(mm, id, "jcoop", "1");
    s_MM_SetLobbyData(mm, id, "text", lobby_text);
    s_F_SetRichPresence(friends, "connect", connect);
    s_F_SetRichPresence(friends, "status", "Clive Barker's Jericho co-op");
    coop_log("steam: lobby %llu ready", id);
}

static void on_lobby_enter(const char *p)
{
    steam_id id;
    unsigned response;
    memcpy(&id, p, 8);
    memcpy(&response, p + 16, 4);
    if (role != 2 || id != lobby || owner)
        return;
    const char *tag = s_MM_GetLobbyData(mm, id, "jcoop");
    if (response != 1 || !tag || strcmp(tag, "1") != 0) {
        coop_log("steam: lobby %llu refused (response %u, tag %s)", id, response, tag ? tag : "-");
        snprintf(error_text, sizeof error_text, response != 1 ? "Steam lobby full or closed" : "not a co-op lobby");
        s_MM_LeaveLobby(mm, id);
        role = 0;
        lobby = 0;
        if (emit)
            emit(0, 'l', NULL, 0);
        return;
    }
    owner = s_MM_GetLobbyOwner(mm, id);
    Remote *r = get_remote(owner);
    if (r)
        r->heard = now_s();
    last_hello = 0;
    coop_log("steam: in lobby %llu, host %llu", id, owner);
}

static void parse_connect(const char *s)
{
    const char *k = strstr(s, "+connect_lobby ");
    if (k)
        pending_lobby = _strtoui64(k + 15, NULL, 10);
}

static void on_callback(int cb, const char *p, int size)
{
    steam_id a, b;
    unsigned state;
    switch (cb) {
    case CB_LOBBY_CREATED:
        on_lobby_created(p);
        break;
    case CB_LOBBY_ENTER:
        on_lobby_enter(p);
        break;
    case CB_LOBBY_CHAT_UPDATE:
        memcpy(&a, p, 8);
        memcpy(&b, p + 8, 8);
        memcpy(&state, p + 24, 4);
        if (a == lobby && (state & 0x1e)) {   /* left, disconnected, kicked, banned */
            Remote *r = find_remote(b);
            if (r)
                drop_remote(r, "left the lobby");
        }
        break;
    case CB_LOBBY_JOIN_REQUESTED:
        memcpy(&pending_lobby, p, 8);
        coop_log("steam: invite accepted for lobby %llu", pending_lobby);
        break;
    case CB_RICH_JOIN_REQUESTED:
        if (size >= 8 + 16)
            parse_connect(p + 8);
        coop_log("steam: join game -> lobby %llu", pending_lobby);
        break;
    case CB_SESSION_REQUEST:
        a = s_Id_Get(p);
        if ((role == 1 && lobby) || (role == 2 && a == owner)) {
            s_NM_Accept(nm, p);
            coop_log("steam: session with %llu accepted", a);
        } else {
            coop_log("steam: session from %llu ignored", a);
        }
        break;
    case CB_SESSION_FAILED:
        a = s_Id_Get(p);
        drop_remote(find_remote(a), "session failed");
        break;
    default:
        break;
    }
}

static void on_control(Remote *r, const char *d, int n)
{
    double t;
    switch (d[0]) {
    case 'H':
        if (role == 1 && lobby && !r->linked && in_lobby(r->id)) {
            int count = 0;
            for (int i = 0; i < MAX_REMOTES; i++)
                count += remotes[i].linked;
            if (count + 1 >= lobby_max) {
                coop_log("steam: %llu refused, session full", r->id);
                break;
            }
            r->linked = 1;
            coop_log("steam: %llu joined", r->id);
            if (emit)
                emit(r->id, 'j', NULL, 0);
        }
        if (r->linked)
            control(r->id, 'W', 1);
        break;
    case 'W':
        if (role == 2 && r->id == owner && !r->linked) {
            r->linked = 1;
            coop_log("steam: welcomed by host %llu", r->id);
            if (emit)
                emit(r->id, 'j', NULL, 0);
        }
        break;
    case 'P':
        if (n >= 9) {
            char q[9];
            memcpy(q, d, 9);
            q[0] = 'Q';
            raw_send(r->id, SEND_UNRELIABLE, CH_CONTROL, q, 9);
        }
        break;
    case 'Q':
        if (n >= 9) {
            memcpy(&t, d + 1, 8);
            r->rtt = (int)((now_s() - t) * 1000.0 + 0.5);
        }
        break;
    case 'B':
        drop_remote(r, "said bye");
        break;
    }
}

static void on_data(Remote *r, const char *d, int n)
{
    if (!r->linked || n < 1)
        return;
    if (d[0] == 'A') {
        if (emit)
            emit(r->id, 'm', d + 1, (size_t)n - 1);
        return;
    }
    if (d[0] != 'F' && d[0] != 'L')
        return;
    size_t need = r->part_len + (size_t)n - 1;
    /* (a message never ended by an 'L' must not grow without end: the mod's biggest, a
       joining player's catch-up, is far below this) */
    if (need > ((size_t)8 << 20)) {
        r->part_len = 0;
        return;
    }
    if (need > r->part_cap) {
        char *g = realloc(r->part, need);
        if (!g)
            return;
        r->part = g;
        r->part_cap = need;
    }
    memcpy(r->part + r->part_len, d + 1, (size_t)n - 1);
    r->part_len = need;
    if (d[0] == 'L') {
        if (emit)
            emit(r->id, 'm', r->part, r->part_len);
        r->part_len = 0;
    }
}

/* The sender's identity in a SteamNetworkingMessage_t: at 16 by the 8-byte packing of the
   headers; at 12 if the identity is packed to 1 byte (KeeperFX tries both too). The first
   message that decodes decides. A wrong offset reads sender 0: in the first real two-account
   test (0.2.1) the host then never saw the client's hello and nothing said why. */
static int id_offset;   /* 0: not known yet */

static steam_id sender(const char *m)
{
    if (id_offset)
        return s_Id_Get(m + id_offset);
    steam_id a = s_Id_Get(m + 16), b = s_Id_Get(m + 12);
    if (a || b) {
        id_offset = a ? 16 : 12;
        coop_log("steam: message sender identity at offset %d", id_offset);
    }
    return a ? a : b;
}

static void receive(int channel)
{
    void *msgs[32];
    int n;
    while ((n = s_NM_Receive(nm, channel, msgs, 32)) > 0) {
        for (int i = 0; i < n; i++) {
            const char *m = (const char *)msgs[i];
            const char *data = *(const char **)m;
            int size = *(const int *)(m + 4);
            steam_id from = sender(m);
            if (!from) {
                static int told;
                if (!told++)
                    coop_log("steam: a message without a readable sender, dropped");
                s_Msg_Release(msgs[i]);
                continue;
            }
            Remote *r = (role == 2 && from != owner) ? NULL : get_remote(from);
            if (r && size > 0) {
                r->heard = now_s();
                if (channel == CH_CONTROL)
                    on_control(r, data, size);
                else
                    on_data(r, data, size);
            }
            s_Msg_Release(msgs[i]);
        }
    }
}

void steam_net_poll(steam_event_fn fn)
{
    if (!ready)
        return;
    emit = fn;
    s_MD_RunFrame(pipe);
    struct { int user; int cb; char *param; int size; } msg;
    while (s_MD_GetNext(pipe, &msg)) {
        if (msg.cb == CB_CALL_COMPLETED) {
            steam_id call;
            int cb;
            unsigned size;
            memcpy(&call, msg.param, 8);
            memcpy(&cb, msg.param + 8, 4);
            memcpy(&size, msg.param + 12, 4);
            char buf[512];
            sbool failed = 0;
            if (size <= sizeof buf && s_MD_GetResult(pipe, call, buf, (int)size, cb, &failed) && !failed)
                on_callback(cb, buf, (int)size);
        } else {
            on_callback(msg.cb, msg.param, msg.size);
        }
        s_MD_Free(pipe);
    }
    if (role) {
        receive(CH_CONTROL);
        receive(CH_DATA);
        pend_flush();
        double t = now_s();
        if (role == 2 && owner) {
            Remote *h = find_remote(owner);
            if (h && !h->linked && t - last_hello > 1.0) {
                control(owner, 'H', 1);
                last_hello = t;
            }
        }
        for (int i = 0; i < MAX_REMOTES; i++) {
            Remote *r = &remotes[i];
            if (!r->id)
                continue;
            if (t - r->heard > TIMEOUT_S) {
                drop_remote(r, "silent for 20 s");
                continue;
            }
            if (r->linked && t - r->last_ping > 1.0) {
                control(r->id, 'P', 0);
                r->last_ping = t;
            }
        }
    }
    emit = NULL;
}

int steam_net_rtt(steam_id who)
{
    Remote *r = find_remote(who);
    return r ? r->rtt : -1;
}

void steam_net_friends(char *out, size_t size)
{
    size_t used = 0;
    out[0] = 0;
    if (!ready)
        return;
    int n = s_F_GetFriendCount(friends, 4 /* immediate friends */);
    for (int i = 0; i < n; i++) {
        steam_id f = s_F_GetFriendByIndex(friends, i, 4);
        struct { unsigned long long game; unsigned ip; unsigned short port, qport; unsigned long long lobby; } info;
        memset(&info, 0, sizeof info);
        if (!s_F_GetFriendGamePlayed(friends, f, &info) || (info.game & 0xffffff) != 480 || !info.lobby)
            continue;
        char name[96];
        to_cp1251(s_F_GetFriendPersonaName(friends, f), name, sizeof name);
        int k = snprintf(out + used, size - used, "%s%s|%llu", used ? ";" : "", name, info.lobby);
        if (k < 0 || used + (size_t)k >= size)
            break;
        used += (size_t)k;
    }
}

steam_id steam_net_take_pending(void)
{
    steam_id l = pending_lobby;
    pending_lobby = 0;
    return l;
}

int steam_net_invite(void)
{
    if (!ready || role != 1 || !lobby)
        return 0;
    s_F_InviteDialog(friends, lobby);
    return 1;
}

/* Steam's overlay invite dialog does not open in this game (0.2.1, two accounts): the co-op
   menu lists the friends online itself and invites the one picked. */
void steam_net_online(char *out, size_t size)
{
    size_t used = 0;
    out[0] = 0;
    if (!ready)
        return;
    int n = s_F_GetFriendCount(friends, 4 /* immediate friends */);
    for (int i = 0; i < n; i++) {
        steam_id f = s_F_GetFriendByIndex(friends, i, 4);
        if (s_F_GetPersonaState(friends, f) == 0)
            continue;   /* offline */
        char name[96];
        to_cp1251(s_F_GetFriendPersonaName(friends, f), name, sizeof name);
        int k = snprintf(out + used, size - used, "%s%s|%llu", used ? ";" : "", name, f);
        if (k < 0 || used + (size_t)k >= size)
            break;
        used += (size_t)k;
    }
}

int steam_net_invite_user(steam_id who)
{
    if (!ready || role != 1 || !lobby || !who)
        return 0;
    int ok = s_MM_InviteUser(mm, lobby, who) != 0;
    coop_log("steam: invite to %llu %s", who, ok ? "sent" : "failed");
    return ok;
}

void steam_net_status(char *out, size_t size)
{
    int linked = 0;
    for (int i = 0; i < MAX_REMOTES; i++)
        linked += remotes[i].linked;
    if (!ready)
        snprintf(out, size, "steam=off error=%s", error_text[0] ? error_text : "not started");
    else
        snprintf(out, size, "steam=ready role=%s lobby=%llu peers=%d name=%s", role == 1 ? "host" : role == 2 ? "client" : "none",
                 lobby, linked, persona);
}

/*
 * Co-op transport for Clive Barker's Jericho, exposed to the game's Lua as Net.Coop*.
 *
 * The game links Lua 5.1.1 statically. We reuse its C API (addresses below, Jericho.exe
 * SHA-256 7fb5b759...2a62) and register our functions by rewriting unused entries of the
 * engine's `Net` luaL_Reg table before Lua starts. ENet runs on a background thread so
 * connections survive long level loads; Lua talks to it through two locked queues.
 *
 * Lua API (all on the Net table):
 *   Net.CoopHost(port, maxPeers)        -> 1/0
 *   Net.CoopJoin(address, port)         -> 1/0
 *   Net.CoopSend(peer, reliable, data)  -> 1/0   peer -1 = everyone, host is peer 0 on clients
 *   Net.CoopRecv()                      -> peer, kind, data | nil   kind: "msg"/"join"/"leave"
 *   Net.CoopStatus()                    -> "role=host peers=1 ids=1 rtt=3"
 *   Net.CoopClose()                     -> 1
 *   Net.CoopTime()                      -> seconds (high resolution)
 *   Net.CoopLog(text)                   -> 1     appends a line to %JERICHO_COOP_LOG%
 *   Net.CoopBackground(on)              -> 1     keep running while unfocused (see display_hooks.c)
 *   Net.CoopKey(vk)                     -> 1/0   key held, only while the game window is in front
 *   Net.CoopAnnounce(text)              -> 1     host: answer LAN queries with text ("" = stop)
 *   Net.CoopDiscover()                  -> "ip|text;ip|text..."  LAN games heard so far; each
 *                                                 call (at most once a second) asks the LAN again
 *
 * LAN discovery: UDP port DISCOVERY_PORT. A client broadcasts "JCOOP?" (and sends it to
 * 127.0.0.1 for a second instance on the same PC); a host that announces answers
 * "JCOOP!<text>" to the sender. Runs on the network thread.
 */
#include <winsock2.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <enet/enet.h>

#include "coop_net.h"
#include "display_hooks.h"

/* ---- Jericho.exe Lua 5.1.1 C API (cdecl) ---- */
typedef struct lua_State lua_State;
typedef int (*lua_CFunction)(lua_State *L);

#define LUA_FN(name, addr, ret, ...) static ret (*const name)(__VA_ARGS__) = (ret (*)(__VA_ARGS__))(addr)
LUA_FN(lua_pushnil, 0x00662770, void, lua_State *);
LUA_FN(lua_pushnumber, 0x00662790, void, lua_State *, double);
LUA_FN(lua_pushlstring, 0x006627d0, void, lua_State *, const char *, size_t);
LUA_FN(lua_pushstring, 0x00662810, void, lua_State *, const char *);
LUA_FN(lua_tolstring, 0x00663e90, const char *, lua_State *, int, size_t *);
LUA_FN(lua_tonumber, 0x00663f30, double, lua_State *, int);
LUA_FN(lua_tointeger, 0x00663ff0, int, lua_State *, int);

/* lua_State: top at +8, base at +0xc, 16-byte TValues (seen in the exe's index2adr). */
static int lua_gettop(lua_State *L)
{
    char *top = *(char **)((char *)L + 8), *base = *(char **)((char *)L + 0xc);
    return (int)((top - base) / 16);
}

/* ---- message queues ---- */
typedef struct Msg {
    struct Msg *next;
    int peer;
    char kind;      /* 'm' message, 'j' join, 'l' leave */
    int reliable;
    size_t len;
    char data[];
} Msg;

typedef struct {
    Msg *head, *tail;
} Queue;

static void q_push(Queue *q, Msg *m)
{
    m->next = NULL;
    if (q->tail)
        q->tail->next = m;
    else
        q->head = m;
    q->tail = m;
}

static Msg *q_pop(Queue *q)
{
    Msg *m = q->head;
    if (m) {
        q->head = m->next;
        if (!q->head)
            q->tail = NULL;
    }
    return m;
}

static Msg *msg_new(int peer, char kind, int reliable, const char *data, size_t len)
{
    Msg *m = malloc(sizeof *m + len + 1);
    m->peer = peer;
    m->kind = kind;
    m->reliable = reliable;
    m->len = len;
    if (len)
        memcpy(m->data, data, len);
    m->data[len] = 0;
    return m;
}

/* ---- state ---- */
#define MAX_PEERS 8

static CRITICAL_SECTION lock;
static Queue inbox, outbox;
static ENetHost *host;
static ENetPeer *peers[MAX_PEERS + 1];  /* index = Lua peer id; host is 0 on clients */
static int is_host, running;

/* ---- LAN discovery state (guarded by lock) ---- */
#define DISCOVERY_PORT 28199
#define MAX_FOUND 16
static ENetSocket disc_listen = ENET_SOCKET_NULL;   /* host: bound to DISCOVERY_PORT */
static ENetSocket disc_query = ENET_SOCKET_NULL;    /* client: ephemeral, broadcast */
static char announce_text[256];
static struct { enet_uint32 ip; char text[256]; double seen; } found[MAX_FOUND];
static int query_pending;
static HANDLE thread;
static char log_path[MAX_PATH];

void coop_log(const char *fmt, ...)
{
    if (!log_path[0])
        return;
    FILE *f = fopen(log_path, "a");
    if (!f)
        return;
    SYSTEMTIME t;
    GetLocalTime(&t);
    fprintf(f, "%02d:%02d:%02d.%03d ", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

static int peer_id(ENetPeer *p)
{
    for (int i = 0; i <= MAX_PEERS; i++)
        if (peers[i] == p)
            return i;
    return -1;
}

static void send_one(ENetPeer *p, Msg *m)
{
    ENetPacket *pk = enet_packet_create(m->data, m->len,
                                        m->reliable ? ENET_PACKET_FLAG_RELIABLE : 0);
    enet_peer_send(p, m->reliable ? 0 : 1, pk);
}

static double now_seconds(void)
{
    static LARGE_INTEGER freq;
    LARGE_INTEGER t;
    if (!freq.QuadPart)
        QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart / (double)freq.QuadPart;
}

/* Called with lock held, from the network thread. */
static void discovery_poll(void)
{
    char buf[300];
    ENetAddress from;
    ENetBuffer b;
    if (announce_text[0] && disc_listen == ENET_SOCKET_NULL) {
        disc_listen = enet_socket_create(ENET_SOCKET_TYPE_DATAGRAM);
        if (disc_listen != ENET_SOCKET_NULL) {
            ENetAddress a = {ENET_HOST_ANY, DISCOVERY_PORT};
            enet_socket_set_option(disc_listen, ENET_SOCKOPT_REUSEADDR, 1);
            enet_socket_set_option(disc_listen, ENET_SOCKOPT_NONBLOCK, 1);
            if (enet_socket_bind(disc_listen, &a) < 0) {
                coop_log("lan: cannot bind discovery port %d", DISCOVERY_PORT);
                enet_socket_destroy(disc_listen);
                disc_listen = ENET_SOCKET_NULL;
                announce_text[0] = 0;
            } else {
                coop_log("lan: announcing on port %d", DISCOVERY_PORT);
            }
        }
    }
    if (!announce_text[0] && disc_listen != ENET_SOCKET_NULL) {
        enet_socket_destroy(disc_listen);
        disc_listen = ENET_SOCKET_NULL;
    }
    for (int i = 0; i < 8 && disc_listen != ENET_SOCKET_NULL; i++) {
        b.data = buf;
        b.dataLength = sizeof buf - 1;
        int n = enet_socket_receive(disc_listen, &from, &b, 1);
        if (n <= 0)
            break;
        if (n >= 6 && memcmp(buf, "JCOOP?", 6) == 0) {
            char reply[300];
            int len = snprintf(reply, sizeof reply, "JCOOP!%s", announce_text);
            ENetBuffer r;
            r.data = reply;
            r.dataLength = (size_t)len;
            enet_socket_send(disc_listen, &from, &r, 1);
        }
    }
    if (query_pending) {
        query_pending = 0;
        if (disc_query == ENET_SOCKET_NULL) {
            disc_query = enet_socket_create(ENET_SOCKET_TYPE_DATAGRAM);
            if (disc_query != ENET_SOCKET_NULL) {
                enet_socket_set_option(disc_query, ENET_SOCKOPT_BROADCAST, 1);
                enet_socket_set_option(disc_query, ENET_SOCKOPT_NONBLOCK, 1);
            }
        }
        if (disc_query != ENET_SOCKET_NULL) {
            ENetBuffer q;
            q.data = (void *)"JCOOP?";
            q.dataLength = 6;
            ENetAddress bc = {ENET_HOST_BROADCAST, DISCOVERY_PORT};
            ENetAddress lo;
            enet_address_set_host(&lo, "127.0.0.1");
            lo.port = DISCOVERY_PORT;
            enet_socket_send(disc_query, &bc, &q, 1);
            enet_socket_send(disc_query, &lo, &q, 1);
        }
    }
    for (int i = 0; i < 16 && disc_query != ENET_SOCKET_NULL; i++) {
        b.data = buf;
        b.dataLength = sizeof buf - 1;
        int n = enet_socket_receive(disc_query, &from, &b, 1);
        if (n <= 0)
            break;
        buf[n] = 0;
        if (n < 6 || memcmp(buf, "JCOOP!", 6) != 0)
            continue;
        int slot = -1;
        for (int k = 0; k < MAX_FOUND; k++)
            if (found[k].seen > 0 && found[k].ip == from.host) { slot = k; break; }
        if (slot < 0)
            for (int k = 0; k < MAX_FOUND; k++)
                if (found[k].seen == 0) { slot = k; break; }
        if (slot >= 0) {
            found[slot].ip = from.host;
            snprintf(found[slot].text, sizeof found[slot].text, "%s", buf + 6);
            found[slot].seen = now_seconds();
        }
    }
}

static DWORD WINAPI net_thread(LPVOID unused)
{
    (void)unused;
    while (running) {
        EnterCriticalSection(&lock);
        discovery_poll();
        Msg *m;
        while ((m = q_pop(&outbox)) != NULL) {
            if (m->peer < 0) {
                for (int i = 0; i <= MAX_PEERS; i++)
                    if (peers[i])
                        send_one(peers[i], m);
            } else if (m->peer <= MAX_PEERS && peers[m->peer]) {
                send_one(peers[m->peer], m);
            }
            free(m);
        }
        ENetEvent ev;
        while (host && enet_host_service(host, &ev, 0) > 0) {
            switch (ev.type) {
            case ENET_EVENT_TYPE_CONNECT: {
                int id = -1;
                if (is_host) {
                    for (int i = 1; i <= MAX_PEERS; i++)
                        if (!peers[i]) { id = i; break; }
                } else {
                    id = 0;
                }
                if (id < 0) {
                    enet_peer_disconnect_now(ev.peer, 0);
                    break;
                }
                peers[id] = ev.peer;
                enet_peer_timeout(ev.peer, 0, 60000, 120000);
                coop_log("connect peer %d", id);
                q_push(&inbox, msg_new(id, 'j', 1, NULL, 0));
                break;
            }
            case ENET_EVENT_TYPE_RECEIVE: {
                int id = peer_id(ev.peer);
                if (id >= 0)
                    q_push(&inbox, msg_new(id, 'm', ev.channelID == 0,
                                           (const char *)ev.packet->data, ev.packet->dataLength));
                enet_packet_destroy(ev.packet);
                break;
            }
            case ENET_EVENT_TYPE_DISCONNECT: {
                int id = peer_id(ev.peer);
                if (id >= 0) {
                    peers[id] = NULL;
                    coop_log("disconnect peer %d", id);
                    q_push(&inbox, msg_new(id, 'l', 1, NULL, 0));
                }
                break;
            }
            default:
                break;
            }
        }
        LeaveCriticalSection(&lock);
        Sleep(2);
    }
    return 0;
}

static void start_thread(void)
{
    if (!running) {
        running = 1;
        thread = CreateThread(NULL, 0, net_thread, NULL, 0, NULL);
    }
}

static void close_host(void)
{
    EnterCriticalSection(&lock);
    if (host) {
        for (int i = 0; i <= MAX_PEERS; i++)
            if (peers[i])
                enet_peer_disconnect_now(peers[i], 0);
        enet_host_destroy(host);
        host = NULL;
    }
    memset(peers, 0, sizeof peers);
    Msg *m;
    while ((m = q_pop(&outbox)) != NULL)
        free(m);
    LeaveCriticalSection(&lock);
}

/* ---- Lua functions ---- */
static int l_host(lua_State *L)
{
    int port = lua_tointeger(L, 1), max = lua_gettop(L) >= 2 ? lua_tointeger(L, 2) : MAX_PEERS;
    if (max < 1 || max > MAX_PEERS)
        max = MAX_PEERS;
    close_host();
    ENetAddress a = {ENET_HOST_ANY, (enet_uint16)port};
    EnterCriticalSection(&lock);
    host = enet_host_create(&a, max, 2, 0, 0);
    is_host = 1;
    LeaveCriticalSection(&lock);
    coop_log("host port %d max %d -> %s", port, max, host ? "ok" : "FAILED");
    if (host)
        start_thread();
    lua_pushnumber(L, host ? 1 : 0);
    return 1;
}

static int l_join(lua_State *L)
{
    const char *addr = lua_tolstring(L, 1, NULL);
    int port = lua_tointeger(L, 2);
    close_host();
    EnterCriticalSection(&lock);
    host = enet_host_create(NULL, 1, 2, 0, 0);
    is_host = 0;
    ENetPeer *p = NULL;
    if (host && addr) {
        ENetAddress a;
        enet_address_set_host(&a, addr);
        a.port = (enet_uint16)port;
        p = enet_host_connect(host, &a, 2, 0);
    }
    LeaveCriticalSection(&lock);
    coop_log("join %s:%d -> %s", addr ? addr : "(nil)", port, p ? "connecting" : "FAILED");
    if (host)
        start_thread();
    lua_pushnumber(L, p ? 1 : 0);
    return 1;
}

static int l_send(lua_State *L)
{
    int peer = lua_tointeger(L, 1), reliable = lua_tointeger(L, 2);
    size_t len = 0;
    const char *data = lua_tolstring(L, 3, &len);
    if (!data || !host) {
        lua_pushnumber(L, 0);
        return 1;
    }
    Msg *m = msg_new(peer, 'm', reliable, data, len);
    EnterCriticalSection(&lock);
    q_push(&outbox, m);
    LeaveCriticalSection(&lock);
    lua_pushnumber(L, 1);
    return 1;
}

static int l_recv(lua_State *L)
{
    EnterCriticalSection(&lock);
    Msg *m = q_pop(&inbox);
    LeaveCriticalSection(&lock);
    if (!m) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushnumber(L, m->peer);
    lua_pushstring(L, m->kind == 'j' ? "join" : m->kind == 'l' ? "leave" : "msg");
    lua_pushlstring(L, m->data, m->len);
    free(m);
    return 3;
}

static int l_status(lua_State *L)
{
    char buf[256];
    int n = 0, len;
    EnterCriticalSection(&lock);
    len = snprintf(buf, sizeof buf, "role=%s", !host ? "none" : is_host ? "host" : "client");
    for (int i = 0; i <= MAX_PEERS && len < (int)sizeof buf - 24; i++)
        if (peers[i]) {
            len += snprintf(buf + len, sizeof buf - len, " p%d:rtt=%u", i, peers[i]->roundTripTime);
            n++;
        }
    LeaveCriticalSection(&lock);
    snprintf(buf + len, sizeof buf - len, " peers=%d", n);
    lua_pushstring(L, buf);
    return 1;
}

static int l_close(lua_State *L)
{
    close_host();
    coop_log("close");
    lua_pushnumber(L, 1);
    return 1;
}

static int l_time(lua_State *L)
{
    static LARGE_INTEGER freq;
    LARGE_INTEGER now;
    if (!freq.QuadPart)
        QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&now);
    lua_pushnumber(L, (double)now.QuadPart / (double)freq.QuadPart);
    return 1;
}

static int l_log(lua_State *L)
{
    const char *s = lua_tolstring(L, 1, NULL);
    coop_log("lua: %s", s ? s : "(nil)");
    lua_pushnumber(L, 1);
    return 1;
}

static int l_background(lua_State *L)
{
    display_hooks_set_background(lua_tointeger(L, 1));
    lua_pushnumber(L, 1);
    return 1;
}

static int l_announce(lua_State *L)
{
    const char *t = lua_tolstring(L, 1, NULL);
    EnterCriticalSection(&lock);
    snprintf(announce_text, sizeof announce_text, "%s", t ? t : "");
    for (char *c = announce_text; *c; c++)
        if (*c == ';')
            *c = ',';   /* ';' separates entries in CoopDiscover */
    LeaveCriticalSection(&lock);
    start_thread();
    lua_pushnumber(L, 1);
    return 1;
}

static int l_discover(lua_State *L)
{
    static double last_query;
    char out[MAX_FOUND * 300];
    size_t used = 0;
    double t = now_seconds();
    EnterCriticalSection(&lock);
    if (t - last_query > 1.0) {
        query_pending = 1;
        last_query = t;
    }
    out[0] = 0;
    for (int k = 0; k < MAX_FOUND; k++) {
        if (found[k].seen == 0)
            continue;
        if (t - found[k].seen > 5.0) {   /* not heard for 5 s: gone */
            found[k].seen = 0;
            continue;
        }
        enet_uint32 ip = found[k].ip;   /* network byte order */
        int n = snprintf(out + used, sizeof out - used, "%s%u.%u.%u.%u|%s", used ? ";" : "",
                         ip & 255, (ip >> 8) & 255, (ip >> 16) & 255, (ip >> 24) & 255, found[k].text);
        if (n > 0 && used + (size_t)n < sizeof out)
            used += (size_t)n;
    }
    LeaveCriticalSection(&lock);
    start_thread();
    lua_pushstring(L, out);
    return 1;
}

static int l_key(lua_State *L)
{
    lua_pushnumber(L, display_hooks_key_down(lua_tointeger(L, 1)));
    return 1;
}

/* ---- registration: rewrite unused entries of the engine's Net luaL_Reg table ---- */
typedef struct {
    const char *name;
    lua_CFunction func;
} luaL_Reg;

#define NET_REG_TABLE 0x0072e4f8  /* 24 entries + {NULL, NULL} */
#define NET_REG_COUNT 24

static const struct {
    const char *replaces, *name;
    lua_CFunction func;
} coop_funcs[] = {
    {"GetServerData", "CoopHost", l_host},
    {"AddResource", "CoopJoin", l_join},
    {"ModifyUsrData", "CoopSend", l_send},
    {"GetBotName", "CoopRecv", l_recv},
    {"GetObjName", "CoopStatus", l_status},
    {"Kick", "CoopClose", l_close},
    {"GetClientData", "CoopTime", l_time},
    {"GetMyClientShip", "CoopLog", l_log},
    {"InitBrowser", "CoopBackground", l_background},
    {"DoneBrowser", "CoopKey", l_key},
    {"SendUsrString", "CoopAnnounce", l_announce},
    {"SendChatString", "CoopDiscover", l_discover},
};

int coop_net_install(void)
{
    luaL_Reg *reg = (luaL_Reg *)NET_REG_TABLE;
    DWORD old;
    int done = 0;
    GetEnvironmentVariableA("JERICHO_COOP_LOG", log_path, MAX_PATH);
    if (!VirtualProtect(reg, sizeof(luaL_Reg) * NET_REG_COUNT, PAGE_READWRITE, &old))
        return 0;
    for (int i = 0; i < NET_REG_COUNT; i++)
        for (size_t k = 0; k < sizeof coop_funcs / sizeof coop_funcs[0]; k++)
            if (reg[i].name && strcmp(reg[i].name, coop_funcs[k].replaces) == 0) {
                reg[i].name = coop_funcs[k].name;
                reg[i].func = coop_funcs[k].func;
                done++;
            }
    VirtualProtect(reg, sizeof(luaL_Reg) * NET_REG_COUNT, old, &old);
    InitializeCriticalSection(&lock);
    enet_initialize();
    coop_log("coop_net installed %d functions", done);
    return done;
}

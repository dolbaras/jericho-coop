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
 *   Net.CoopFile(path)                  -> 1/0   a file exists (relative to the game folder)
 *   Net.CoopFile("coop:name", "r")      -> text | nil   read a co-op save file
 *   Net.CoopFile("coop:name", "w", s)   -> 1/0   write a co-op save file (atomic replace)
 *     "coop:" files live in %JERICHO_COOP_SAVEDIR% (tests) or
 *     Documents\Codemasters\Clive Barker's Jericho\Coop, apart from the game's profile.
 *     Only "coop:" files can be read or written; names are [A-Za-z0-9_.-].
 *   Net.CoopBoot()                      -> Lua chunk that starts the mod: sets COOP_DIR (the
 *                                                 coop folder) and COOP_CFG (%JERICHO_COOP_CFG%
 *                                                 in test runs, else {}), runs boot.lua
 *   Net.CoopDisplay("get" | "rates" | "set", hz, borderless)  refresh rate and borderless window
 *                                                 (display_hooks.c)
 *   Net.CoopDiscover()                  -> "ip|text;ip|text..."  LAN games heard so far; each
 *                                                 call (at most once a second) asks the LAN again
 *
 * LAN discovery: UDP port DISCOVERY_PORT. A client broadcasts "JCOOP?" (and sends it to
 * 127.0.0.1 for a second instance on the same PC, and to the broadcast address of each
 * network: Windows sends 255.255.255.255 out of one adapter only, the one with the lowest
 * metric, e.g. Radmin VPN's; 0.2.1 test PC); a host that announces answers
 * "JCOOP!<text>" to the sender. Runs on the network thread.
 */
#include <winsock2.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <shlobj.h>
#include <iphlpapi.h>
#include <enet/enet.h>

#include "coop_net.h"
#include "display_hooks.h"
#include "clip.h"
#include "boot_inject.h"
#include "split.h"
#include "steam_net.h"

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
/* The same ids for players connected through Steam (steam_net.c; from the fork
   MAK-PIVO/jericho-coop). A session is LAN (ENet) or Steam, the host's choice in the menu. */
static steam_id steam_peers[MAX_PEERS + 1];
static int is_host, running;

static int slot_used(int i) { return peers[i] || steam_peers[i]; }
static int session_active(void) { return host || steam_net_session(); }

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
static int log_resolved;
static volatile LONG log_allowed;          /* set on the first Lua call (l_boot) */
static CRITICAL_SECTION log_lock;
static int log_lock_ok;
static char log_early[8192];               /* lines before the path is known */
static size_t log_early_len;
static int coop_save_path(const char *name, char *out, size_t size);

/* %JERICHO_COOP_LOG% (tests), else coop.log in the co-op save folder, the previous session's
 * kept as coop.prev.log. The folder is looked up only once the game runs Lua (l_boot), never
 * in DllMain: no shell calls under the loader lock. Called with log_lock held. */
static void log_resolve(void)
{
    if (log_path[0] || log_resolved || !log_allowed)
        return;
    log_resolved = 1;
    char p[MAX_PATH], prev[MAX_PATH];
    if (!coop_save_path("coop:coop.log", p, sizeof p) || !coop_save_path("coop:coop.prev.log", prev, sizeof prev))
        return;
    MoveFileExA(p, prev, MOVEFILE_REPLACE_EXISTING);
    strcpy(log_path, p);
}

void coop_log(const char *fmt, ...)
{
    char line[2048];
    SYSTEMTIME t;
    GetLocalTime(&t);
    int n = snprintf(line, sizeof line, "%02d:%02d:%02d.%03d ", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
    va_list ap;
    va_start(ap, fmt);
    int m = vsnprintf(line + n, sizeof line - n - 1, fmt, ap);
    va_end(ap);
    n += m < 0 ? 0 : (m >= (int)(sizeof line - n - 1) ? (int)(sizeof line - n - 2) : m);
    line[n++] = '\n';
    line[n] = 0;
    if (!log_lock_ok)
        return;
    EnterCriticalSection(&log_lock);
    log_resolve();
    if (!log_path[0]) {
        if (!log_resolved && log_early_len + n < sizeof log_early) {
            memcpy(log_early + log_early_len, line, n);
            log_early_len += n;
        }
    } else {
        FILE *f = fopen(log_path, "a");
        if (f) {
            if (log_early_len) {
                fwrite(log_early, 1, log_early_len, f);
                log_early_len = 0;
            }
            fwrite(line, 1, n, f);
            fclose(f);
        }
    }
    LeaveCriticalSection(&log_lock);
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
            /* each network's own broadcast address (address | ~mask), loopback and single
               addresses (VPN /32) left out */
            ULONG size = 0;
            if (GetIpAddrTable(NULL, &size, FALSE) == ERROR_INSUFFICIENT_BUFFER && size) {
                MIB_IPADDRTABLE *t = (MIB_IPADDRTABLE *)malloc(size);
                if (t && GetIpAddrTable(t, &size, FALSE) == NO_ERROR) {
                    for (DWORD k = 0; k < t->dwNumEntries; k++) {
                        DWORD ip = t->table[k].dwAddr, mask = t->table[k].dwMask;
                        if (!ip || mask == 0xFFFFFFFFu || (ntohl(ip) >> 24) == 127)
                            continue;
                        ENetAddress nb = {ip | ~mask, DISCOVERY_PORT};
                        enet_socket_send(disc_query, &nb, &q, 1);
                    }
                }
                free(t);
            }
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

/* Steam transport events (steam_net.c), on the network thread with the lock held. */
static void on_steam_event(steam_id who, char kind, const char *data, size_t len)
{
    int id = -1;
    for (int i = 0; i <= MAX_PEERS; i++)
        if (who && steam_peers[i] == who)
            id = i;
    if (kind == 'j' && id < 0) {
        if (is_host) {
            for (int i = 1; i <= MAX_PEERS; i++)
                if (!slot_used(i)) { id = i; break; }
        } else {
            id = 0;
        }
        if (id < 0)
            return;
        steam_peers[id] = who;
        coop_log("connect peer %d (Steam %llu)", id, who);
        q_push(&inbox, msg_new(id, 'j', 1, NULL, 0));
    } else if (kind == 'm' && id >= 0) {
        q_push(&inbox, msg_new(id, 'm', 1, data, len));
    } else if (kind == 'l') {
        if (id < 0 && !is_host)
            id = 0;   /* the lobby refused us or the host is gone */
        if (id < 0)
            return;
        steam_peers[id] = 0;
        coop_log("disconnect peer %d (Steam)", id);
        q_push(&inbox, msg_new(id, 'l', 1, NULL, 0));
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
            for (int i = 0; i <= MAX_PEERS; i++) {
                if (m->peer >= 0 && m->peer != i)
                    continue;
                if (peers[i])
                    send_one(peers[i], m);
                else if (steam_peers[i])
                    steam_net_send(steam_peers[i], m->reliable, m->data, m->len);
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
                        if (!slot_used(i)) { id = i; break; }
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
        steam_net_poll(on_steam_event);
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
    steam_net_leave();
    memset(steam_peers, 0, sizeof steam_peers);
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
    if (!data || !session_active()) {
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
    len = snprintf(buf, sizeof buf, "role=%s", !session_active() ? "none" : is_host ? "host" : "client");
    for (int i = 0; i <= MAX_PEERS && len < (int)sizeof buf - 24; i++)
        if (peers[i]) {
            len += snprintf(buf + len, sizeof buf - len, " p%d:rtt=%u", i, peers[i]->roundTripTime);
            n++;
        } else if (steam_peers[i]) {
            len += snprintf(buf + len, sizeof buf - len, " p%d:rtt=%d:steam", i, steam_net_rtt(steam_peers[i]));
            n++;
        }
    LeaveCriticalSection(&lock);
    snprintf(buf + len, sizeof buf - len, " peers=%d", n);
    lua_pushstring(L, buf);
    return 1;
}

/* Net.CoopClose([peer]): the whole session, or (host) one peer, after what was sent to it. */
static int l_close(lua_State *L)
{
    if (lua_gettop(L) >= 1 && lua_tointeger(L, 1) > 0) {
        int id = lua_tointeger(L, 1);
        EnterCriticalSection(&lock);
        if (is_host && id <= MAX_PEERS && peers[id])
            enet_peer_disconnect_later(peers[id], 0);
        LeaveCriticalSection(&lock);
        coop_log("close peer %d", id);
        lua_pushnumber(L, 1);
        return 1;
    }
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
    steam_net_set_text(announce_text);
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

static int to_ansi(const wchar_t *w, char *out, size_t size)
{
    BOOL lossy = FALSE;
    UINT cp = GetACP();
    /* (UTF-8 as the code page: every character fits, and these flags are not allowed) */
    int n = cp == CP_UTF8 ? WideCharToMultiByte(cp, 0, w, -1, out, (int)size, NULL, NULL)
                          : WideCharToMultiByte(cp, WC_NO_BEST_FIT_CHARS, w, -1, out, (int)size, NULL, &lossy);
    return n > 0 && !lossy;
}

int coop_ansi_path(const wchar_t *path, char *out, size_t size)
{
    if (to_ansi(path, out, size))
        return 1;
    wchar_t s[MAX_PATH];
    DWORD n = GetShortPathNameW(path, s, MAX_PATH);
    return n > 0 && n < MAX_PATH && to_ansi(s, out, size);
}

/* "coop:<name>" -> full path in the co-op save folder (created on demand); 0 if invalid. */
static int coop_save_path(const char *name, char *out, size_t size)
{
    char dir[MAX_PATH];
    wchar_t wdir[MAX_PATH];
    if (strncmp(name, "coop:", 5) != 0)
        return 0;
    name += 5;
    if (!name[0] || strlen(name) > 64)
        return 0;
    for (const char *c = name; *c; c++)
        if (!((*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') || (*c >= '0' && *c <= '9') ||
              *c == '_' || *c == '-' || (*c == '.' && c != name)))
            return 0;
    DWORD n = GetEnvironmentVariableA("JERICHO_COOP_SAVEDIR", dir, sizeof dir);
    if (n == 0 || n >= sizeof dir) {
        /* (wide: a user name outside the code page, see coop_ansi_path) */
        if (SHGetFolderPathW(NULL, CSIDL_PERSONAL | CSIDL_FLAG_CREATE, NULL, 0, wdir) != S_OK)
            return 0;
        static const wchar_t *const parts[] = {L"\\Codemasters", L"\\Clive Barker's Jericho", L"\\Coop"};
        for (size_t i = 0; i < sizeof parts / sizeof parts[0]; i++) {
            if (wcslen(wdir) + wcslen(parts[i]) >= MAX_PATH)
                return 0;
            wcscat(wdir, parts[i]);
            CreateDirectoryW(wdir, NULL);
        }
        if (!coop_ansi_path(wdir, dir, sizeof dir))
            return 0;
    } else {
        CreateDirectoryA(dir, NULL);
    }
    return snprintf(out, size, "%s\\%s", dir, name) < (int)size;
}

int coop_data_path(const char *name, char *out, size_t size)
{
    return coop_save_path(name, out, size);
}

/* Net.CoopClip("save") -> the clip being written (clip.c: the last 30 s), "" if none. */
/* Net.CoopDisplay("get") -> hz, borderless; ("rates") -> "60,75,144"; ("monitor") -> w, h,
 * borderless now (1/0), refresh rate now; ("set", hz, borderless) -> 1/0 */
static int l_display(lua_State *L)
{
    const char *cmd = lua_tolstring(L, 1, NULL);
    if (cmd && strcmp(cmd, "get") == 0) {
        int hz, bl;
        display_get(&hz, &bl);
        lua_pushnumber(L, hz);
        lua_pushnumber(L, bl);
        return 2;
    }
    if (cmd && strcmp(cmd, "rates") == 0) {
        char rates[512];
        display_rates(rates, sizeof rates);
        lua_pushstring(L, rates);
        return 1;
    }
    if (cmd && strcmp(cmd, "monitor") == 0) {
        int w, h, hz, on = display_monitor(&w, &h, &hz);
        lua_pushnumber(L, w);
        lua_pushnumber(L, h);
        lua_pushnumber(L, on);
        lua_pushnumber(L, hz);
        return 4;
    }
    if (cmd && strcmp(cmd, "set") == 0) {
        lua_pushnumber(L, display_set(lua_tointeger(L, 2), lua_tointeger(L, 3)));
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

static int l_clip(lua_State *L)
{
    const char *cmd = lua_tolstring(L, 1, NULL);
    lua_pushstring(L, cmd && strcmp(cmd, "save") == 0 ? clip_save() : "");
    return 1;
}

static int l_file(lua_State *L)
{
    const char *path = lua_tolstring(L, 1, NULL);
    const char *mode = lua_gettop(L) >= 2 ? lua_tolstring(L, 2, NULL) : NULL;
    char full[MAX_PATH + 80];
    if (path && coop_save_path(path, full, sizeof full))
        path = full;
    else if (mode)
        path = NULL;   /* reading and writing only in the co-op save folder */
    if (mode && mode[0] == 'r') {
        FILE *f = path ? fopen(path, "rb") : NULL;
        if (!f) {
            lua_pushnil(L);
            return 1;
        }
        fseek(f, 0, SEEK_END);
        long len = ftell(f);
        fseek(f, 0, SEEK_SET);
        char *buf = len >= 0 && len < (16 << 20) ? malloc((size_t)len + 1) : NULL;
        size_t got = buf ? fread(buf, 1, (size_t)len, f) : 0;
        fclose(f);
        if (!buf) {
            lua_pushnil(L);
            return 1;
        }
        lua_pushlstring(L, buf, got);
        free(buf);
        return 1;
    }
    if (mode && mode[0] == 'w') {
        size_t len = 0;
        const char *data = lua_tolstring(L, 3, &len);
        char tmp[MAX_PATH + 90];
        int ok = 0;
        if (path && data && snprintf(tmp, sizeof tmp, "%s.tmp", path) < (int)sizeof tmp) {
            FILE *f = fopen(tmp, "wb");
            if (f) {
                ok = fwrite(data, 1, len, f) == len;
                ok = fclose(f) == 0 && ok;
                ok = ok && MoveFileExA(tmp, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
                if (!ok)
                    DeleteFileA(tmp);
            }
        }
        lua_pushnumber(L, ok);
        return 1;
    }
    DWORD attr = path ? GetFileAttributesA(path) : INVALID_FILE_ATTRIBUTES;
    lua_pushnumber(L, attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY));
    return 1;
}

static int l_boot(lua_State *L)
{
    /* static: the test config (story step chains) can be several kilobytes */
    static char cfg[16384], chunk[20480];
    InterlockedExchange(&log_allowed, 1);   /* out of DllMain now: the log folder may be looked up */
    char dir[2 * MAX_PATH];
    size_t k = 0;
    DWORD n = GetEnvironmentVariableA("JERICHO_COOP_CFG", cfg, sizeof cfg);
    if (n == 0 || n >= sizeof cfg)
        strcpy(cfg, "{}");
    /* The folder as a Lua string body: the default install folder has a quote in it. */
    for (const char *p = boot_inject_dir(); *p && k + 2 < sizeof dir; p++) {
        if (*p == '\\' || *p == '\'')
            dir[k++] = '\\';
        dir[k++] = *p;
    }
    dir[k] = 0;
    snprintf(chunk, sizeof chunk, "COOP_DIR='%s' COOP_CFG=%s dofile(COOP_DIR..'boot.lua')", dir, cfg);
    lua_pushstring(L, chunk);
    return 1;
}

/* Net.CoopSplit(mode) -> camera slot of this frame: local split screen (split.c). */
static int l_split(lua_State *L)
{
    /* arg 2 (split screen session): 1 while a menu or scene is up (pads merged), 0 back in play,
       -1 split screen over (pads as the game reads them), 2 merged without holding back the
       buttons held at the change. */
    if (lua_gettop(L) >= 2) {
        int p = lua_tointeger(L, 2);
        display_hooks_pads_split(p >= 0, p >= 1 ? p : 0);
    }
    lua_pushnumber(L, split_set(lua_tointeger(L, 1)));
    return 1;
}

/* Net.CoopKey(vk) -> 1/0; Net.CoopKey(-1, user) -> buttons, lt, rt, lx, ly, rx, ry of that
   split screen user's own pad (straight from XInput: the game updates no "Walk" input while
   the action set is player 1's "Astral"), or nothing when it has none. */
static int l_key(lua_State *L)
{
    int vk = lua_tointeger(L, 1);
    if (vk == -3) {   /* Net.CoopKey(-3): the four XInput slots as read (diagnosis) */
        int v[4];
        if (!display_hooks_pad_raw(v))
            return 0;
        for (int i = 0; i < 4; i++)
            lua_pushnumber(L, v[i]);
        return 4;
    }
    if (vk == -4) {   /* Net.CoopKey(-4, user): the hidden first-person model's user (split.c) */
        split_hidden_fp_user(lua_tointeger(L, 2));
        return 0;
    }
    if (vk == -2) {   /* Net.CoopKey(-2): split screen pads plugged in or out -> 1 on a change */
        lua_pushnumber(L, display_hooks_pads_rescan());
        return 1;
    }
    if (vk == -1) {
        int v[7];
        if (!display_hooks_pad_read(lua_tointeger(L, 2), v))
            return 0;
        for (int i = 0; i < 7; i++)
            lua_pushnumber(L, v[i]);
        return 7;
    }
    lua_pushnumber(L, display_hooks_key_down(vk));
    return 1;
}

/* Net.CoopConsole([reply]): the test console (tools/luacon.py), only when the environment
 * names its UDP port (JERICHO_CONSOLE=<port>; test runs, never a player's game), on
 * 127.0.0.1 only, and run by lua/dev.lua, which the release does not ship:
 *   no argument -> the next Lua chunk sent to that port, nil if none (lua/dev.lua runs it)
 *   reply       -> 1   sent back to whoever sent the last chunk */
static SOCKET con_sock = INVALID_SOCKET;
static int con_tried;
static struct sockaddr_in con_from;

static int l_console(lua_State *L)
{
    if (!con_tried) {
        con_tried = 1;
        char v[16];
        if (GetEnvironmentVariableA("JERICHO_CONSOLE", v, sizeof v) > 0 && atoi(v) > 0) {
            con_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
            struct sockaddr_in a = {0};
            a.sin_family = AF_INET;
            a.sin_port = htons((u_short)atoi(v));
            a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);   /* this PC only (the N100 through ssh) */
            u_long nb = 1;
            if (con_sock == INVALID_SOCKET || bind(con_sock, (struct sockaddr *)&a, sizeof a) != 0 ||
                ioctlsocket(con_sock, FIONBIO, &nb) != 0) {
                if (con_sock != INVALID_SOCKET)
                    closesocket(con_sock);
                con_sock = INVALID_SOCKET;
                coop_log("console: UDP port %s not available", v);
            } else {
                coop_log("console: listening on UDP port %s", v);
            }
        }
    }
    if (con_sock == INVALID_SOCKET) {
        lua_pushnil(L);
        return 1;
    }
    if (lua_gettop(L) >= 1) {
        size_t n = 0;
        const char *s = lua_tolstring(L, 1, &n);
        if (s && con_from.sin_family == AF_INET)
            sendto(con_sock, s, (int)(n > 60000 ? 60000 : n), 0, (struct sockaddr *)&con_from, sizeof con_from);
        lua_pushnumber(L, 1);
        return 1;
    }
    static char buf[60001];
    int fl = sizeof con_from;
    int r = recvfrom(con_sock, buf, sizeof buf - 1, 0, (struct sockaddr *)&con_from, &fl);
    if (r <= 0) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushlstring(L, buf, (size_t)r);
    return 1;
}

/* Net.CoopSteam(command [, argument]): the Steam transport (steam_net.c, from the fork
 * MAK-PIVO/jericho-coop). Steam starts only when the player picks it in the co-op menu.
 *   "init"     -> "steam=ready ..." or "steam=off error=..."   (starts Steam once)
 *   "status"   -> the same, without starting Steam
 *   "host", max -> 1/0  a friends-only Steam lobby for the session being hosted (after
 *                       Net.CoopHost; LAN discovery is not announced for it)
 *   "join", id -> 1/0   join the friend's lobby id (decimal string); then Net.CoopRecv as usual
 *   "friends"  -> "name|lobby;..." friends playing Spacewar with a lobby open
 *   "pending"  -> lobby id the player accepted in Steam (invite or "Join game"), "" if none
 *   "text", s  -> 1     the Steam lobby's text (nick|level|players|max)
 *   "invite"   -> 1/0   open the Steam overlay's invite dialog (host)
 *   "online"   -> "name|id;..." friends online (the co-op menu's own invite list)
 *   "inviteuser", id -> 1/0   invite that friend to the lobby (host)
 *   "name"     -> the player's Steam name (cp1251), "" without Steam */
static int l_steam(lua_State *L)
{
    const char *cmd = lua_tolstring(L, 1, NULL);
    const char *arg = lua_gettop(L) >= 2 ? lua_tolstring(L, 2, NULL) : NULL;
    static char out[4096];
    out[0] = 0;
    if (!cmd) {
        lua_pushnil(L);
        return 1;
    }
    if (strcmp(cmd, "init") == 0 || strcmp(cmd, "status") == 0) {
        if (cmd[0] == 'i')
            steam_net_init();
        EnterCriticalSection(&lock);
        steam_net_status(out, sizeof out);
        LeaveCriticalSection(&lock);
        lua_pushstring(L, out);
        return 1;
    }
    if (strcmp(cmd, "name") == 0) {
        lua_pushstring(L, steam_net_ready() ? steam_net_persona() : "");
        return 1;
    }
    if (!steam_net_init()) {
        lua_pushnumber(L, 0);
        return 1;
    }
    if (strcmp(cmd, "host") == 0) {
        int max = arg ? atoi(arg) : MAX_PEERS;
        if (max < 1 || max > MAX_PEERS)
            max = MAX_PEERS;
        EnterCriticalSection(&lock);
        is_host = 1;
        steam_net_host(max + 1, announce_text);
        LeaveCriticalSection(&lock);
        start_thread();
        coop_log("steam: hosting a lobby for %d", max + 1);
        lua_pushnumber(L, 1);
    } else if (strcmp(cmd, "join") == 0) {
        steam_id id = arg ? _strtoui64(arg, NULL, 10) : 0;
        close_host();
        EnterCriticalSection(&lock);
        is_host = 0;
        steam_net_join(id);
        LeaveCriticalSection(&lock);
        if (id)
            start_thread();
        lua_pushnumber(L, id ? 1 : 0);
    } else if (strcmp(cmd, "text") == 0) {
        /* the Steam lobby's text ("nick|level|players|max"): not announced on the LAN */
        EnterCriticalSection(&lock);
        steam_net_set_text(arg ? arg : "");
        LeaveCriticalSection(&lock);
        lua_pushnumber(L, 1);
    } else if (strcmp(cmd, "friends") == 0) {
        EnterCriticalSection(&lock);
        steam_net_friends(out, sizeof out);
        LeaveCriticalSection(&lock);
        lua_pushstring(L, out);
    } else if (strcmp(cmd, "pending") == 0) {
        EnterCriticalSection(&lock);
        steam_id id = steam_net_take_pending();
        LeaveCriticalSection(&lock);
        if (id)
            snprintf(out, sizeof out, "%llu", id);
        lua_pushstring(L, out);
    } else if (strcmp(cmd, "invite") == 0) {
        EnterCriticalSection(&lock);
        int ok = steam_net_invite();
        LeaveCriticalSection(&lock);
        lua_pushnumber(L, ok);
    } else if (strcmp(cmd, "online") == 0) {
        EnterCriticalSection(&lock);
        steam_net_online(out, sizeof out);
        LeaveCriticalSection(&lock);
        lua_pushstring(L, out);
    } else if (strcmp(cmd, "inviteuser") == 0) {
        steam_id id = arg ? _strtoui64(arg, NULL, 10) : 0;
        EnterCriticalSection(&lock);
        int ok = steam_net_invite_user(id);
        LeaveCriticalSection(&lock);
        lua_pushnumber(L, ok);
    } else {
        lua_pushnil(L);
    }
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
    {"SendCtrlString", "CoopFile", l_file},
    {"PingInetSvrs", "CoopBoot", l_boot},
    {"SendMasterString", "CoopSplit", l_split},
    {"ServerChangeLevel", "CoopSteam", l_steam},
    {"GetPing", "CoopConsole", l_console},
    {"IsMaster", "CoopClip", l_clip},
    {"InitClient", "CoopDisplay", l_display},
};

int coop_net_install(void)
{
    luaL_Reg *reg = (luaL_Reg *)NET_REG_TABLE;
    DWORD old;
    int done = 0;
    InitializeCriticalSection(&log_lock);
    log_lock_ok = 1;
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
    /* 4096 MB once the installer marked the exe large-address-aware (2048 without). */
    MEMORYSTATUSEX ms = {sizeof ms};
    if (GlobalMemoryStatusEx(&ms))
        coop_log("memory: address space %llu MB, %llu MB free", ms.ullTotalVirtual >> 20, ms.ullAvailVirtual >> 20);
    return done;
}

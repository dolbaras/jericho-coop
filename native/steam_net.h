/* Steam transport: lobbies and relayed P2P messages through the Steam client (Spacewar). */
#pragma once
#include <stddef.h>

typedef unsigned long long steam_id;

/* Load bin\steam_api.dll and start the Steam API (once). 1 = ready. */
int steam_net_init(void);
int steam_net_ready(void);
const char *steam_net_error(void);
/* The local Steam name in the game's code page (cp1251), "" before init. */
const char *steam_net_persona(void);

/* The functions below are called with coop_net's lock held. */
void steam_net_host(int max_players, const char *lobby_text);   /* friends-only lobby */
void steam_net_set_text(const char *lobby_text);                /* "nick|level|players|max" */
void steam_net_join(steam_id lobby);
void steam_net_leave(void);
int steam_net_session(void);           /* hosting a lobby or inside one */
steam_id steam_net_lobby(void);
int steam_net_send(steam_id to, int reliable, const void *data, size_t len);
int steam_net_rtt(steam_id who);       /* ms, -1 unknown */
/* Callbacks, messages, keep-alives, time-outs. kind: 'j' joined, 'm' message, 'l' left. */
typedef void (*steam_event_fn)(steam_id who, char kind, const char *data, size_t len);
void steam_net_poll(steam_event_fn fn);
/* Friends playing with a lobby open: "name|lobby;name|lobby" (names in cp1251). */
void steam_net_friends(char *out, size_t size);
/* A lobby the player accepted through Steam (invite or "Join game"), 0 if none; cleared. */
steam_id steam_net_take_pending(void);
int steam_net_invite(void);            /* Steam overlay invite dialog for the lobby */
/* Friends online: "name|id;name|id" (names in cp1251); an invite to this lobby for one. */
void steam_net_online(char *out, size_t size);
int steam_net_invite_user(steam_id who);
void steam_net_status(char *out, size_t size);

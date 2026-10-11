# ServerAdmin

ServerAdmin is a full-screen, in-game administration centre for Garry's Mod. It uses native Derma UI and server-authoritative networking; it is not a remote web panel and it does not require ULX.

## Installation

1. Download or clone this repository into the garrysmod/addons/ServerAdmin directory.
2. Restart the server or change map so the server and clients load the updated Lua files.
3. Connect with a Garry's Mod administrator account.
4. Open the panel using **F6** or run **serveradmin** in the client console.

## Functionality

### Dashboard and diagnostics
- Server hostname, current map, gamemode and DarkRP detection.
- Live connected-player overview and player-slot count.
- Estimated tickrate, Lua memory, module uptime, bot count and entity count.
- Build-lockdown status and latest ServerAdmin audit entries.
- Refreshable server snapshot; metrics that the normal GMod Lua API does not expose are not fabricated.

### Player management
- Search by player name, SteamID, SteamID64, job/team and admin rank.
- Player listing with job, wallet balance, ping, SteamID and rank.
- Kick with a reason.
- Timed and permanent bans with a reason.
- Persistent ban records and a selected-record unban action.
- Persistent warning history and in-game warning messages.
- Bring, teleport to player, freeze/unfreeze, heal, respawn and slay.
- Voice mute/unmute, chat gag/ungag, god mode, strip weapons, ignite/extinguish, set health and set armour.
- DarkRP wallet set/adjust and registered job switching.
- Create custom DarkRP professions from the in-game editor: name, chat command, description, player models, weapon loadout, F4 category, salary, player limit, access level, voting, license requirement and RGB color.
- Edit and delete ServerAdmin-created professions; definitions are stored in `data/serveradmin/custom_jobs.json` and restored after DarkRP finishes loading.
- When deleting a custom profession, connected players using it are moved to a safe fallback job first; default DarkRP and third-party professions cannot be deleted from this panel.
- Custom profession definitions are synchronized to connected clients and reflected in the local DarkRP job registry/F4 categories.
- Profession chat commands remain fixed after creation because DarkRP maintains an internal command registry. Default jobs from DarkRP or other addons are not edited in-place to avoid overwriting third-party configuration.

### Server controls
- Set hostname, gravity and change map.
- Edit a persistent MOTD title and message from the panel; it is shown to new joiners and can be previewed or broadcast to everyone online.
- Superadmin-only RCON-style server console with validated single-command execution and quoted arguments. Command output remains in the dedicated server console/logs.
- Create up to ten bots per request, remove all bots, and kick individual bots from the player list.
- Broadcast an announcement to all players.
- Clean up map entities, with a confirmation prompt.
- Enable/disable build lockdown for non-admin players.
- Edit a fixed allow-list of server variables: gravity, password, voice/all-talk, LAN/friendly-fire flags, Sandbox permissions and common Sandbox entity limits.
- Secret values (such as sv_password) are never sent back to the client. The password editor starts blank; a blank value clears the password.

### Audit and persistence
- SQLite tables store ServerAdmin actions, bans and warnings.
- The audit log records the administrator, action, target and details.
- Superadmins can clear the ServerAdmin audit log from the in-game panel; this does not delete ban or warning records.
- Timed ServerAdmin ban records are marked expired when their expiry time has passed.
- A built-in ULX-compatible command layer provides console commands (`ulx <command>`) and chat aliases (`!command` or `/command`), persistent custom user groups, immunity, group inheritance, per-group/per-user command allow/deny overrides, voting, admin chat, and a separate command log. It does not embed the upstream ULX/ULib packages.

### ULX-compatible command layer

Use `ulx help` in server/client console or `!help` in chat to list commands. Quoted player names are supported in chat, and player selectors include `@all`, `@admins`, `@bots`, `@random` and `@me`.

Included command families: kick/ban/banid/unban/banlist/warn, slay/slap/freeze, bring/goto/send/return, jail/unjail, heal/hp/armor/respawn, god, cloak/blind, ignite/extinguish, voice mute and chat gag, speed/jump restoration, weapon giving, map/hostname/gravity/timescale/cleanup, announcements/private/admin chat, yes/no polls, votemap/votekick, log viewing, group creation/removal, user group assignment, immunity, and per-user/per-group access overrides. The `menu` command opens the existing ServerAdmin panel.

Group data is saved in `data/serveradmin/ulx_access.json`; command logs are saved in `data/serveradmin/ulx.log`. Existing built-in ServerAdmin ban and warning records are shared with this command layer. This is an original ULX-compatible implementation, not the upstream ULX package, so it should not be described as binary/API-compatible with ULX extensions requiring ULib.

## Permissions and safety

- Only players recognised by Garry's Mod as administrators can use the panel.
- Server configuration, map changes, economy/job changes, custom profession creation/editing, unbans, bot management, announcements, cleanup, lockdown and health/armour overrides require superadmin.
- Every action is permission-checked again on the server; hiding a button in the client is never considered access control.
- A regular admin cannot target a superadmin. Several high-impact actions against administrators are restricted to superadmins.
- Server variable updates use a strict allow-list and validated values. The separate RCON-style command tool is superadmin-only, rejects command separators/newlines, parses quoted arguments, and blocks high-risk script/config/shutdown commands.
- Map names are validated and the requested .bsp file must exist on the server.
- Build lockdown blocks common Sandbox spawn hooks for non-admins. Gamemodes and other addons that replace those hooks may require compatibility testing.

## Compatibility and testing

The add-on uses standard Garry's Mod APIs and optional DarkRP APIs. DarkRP job switching depends on the server's actual DarkRP configuration and other installed addons. ServerAdmin ban history tracks bans and warnings created through the panel and the built-in ULX-compatible command layer; bans created outside both may not appear in its history.

**Test on a private server before using it in production.** In particular, verify ban/unban persistence, DarkRP job switching, server-variable availability, voice mute behaviour and interactions with other moderation or Sandbox addons. I can update the code directly, but cannot claim in-game validation without running a Garry's Mod server.

## Analytics

- Analytics dashboard with totals for bans, active bans, warnings and recorded administration actions.
- Rolling 60-minute line charts for connected players, entity count, estimated tickrate and Lua memory estimate. Samples are held in memory and reset when the server restarts.

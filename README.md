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
- The add-on does not provide group/role management or arbitrary RCON/console-command execution.

## Permissions and safety

- Only players recognised by Garry's Mod as administrators can use the panel.
- Server configuration, map changes, economy/job changes, custom profession creation/editing, unbans, bot management, announcements, cleanup, lockdown and health/armour overrides require superadmin.
- Every action is permission-checked again on the server; hiding a button in the client is never considered access control.
- A regular admin cannot target a superadmin. Several high-impact actions against administrators are restricted to superadmins.
- Variable updates use a strict allow-list and validated values; the client cannot submit arbitrary commands.
- Map names are validated and the requested .bsp file must exist on the server.
- Build lockdown blocks common Sandbox spawn hooks for non-admins. Gamemodes and other addons that replace those hooks may require compatibility testing.

## Compatibility and testing

The add-on uses standard Garry's Mod APIs and optional DarkRP APIs. DarkRP job switching depends on the server's actual DarkRP configuration and other installed addons. ServerAdmin ban history tracks bans created through this panel; bans created outside ServerAdmin may not appear in its history.

**Test on a private server before using it in production.** In particular, verify ban/unban persistence, DarkRP job switching, server-variable availability, voice mute behaviour and interactions with other moderation or Sandbox addons. I can update the code directly, but cannot claim in-game validation without running a Garry's Mod server.

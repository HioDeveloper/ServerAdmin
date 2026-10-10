# ServerAdmin

A fullscreen, dark administration control center for Garry's Mod, with optional DarkRP-aware job and wallet tools.

## Installation

1. Download or clone this repository into `garrysmod/addons/ServerAdmin`.
2. Restart the server or change map.
3. Join with an administrator account.
4. Open the panel with **F6** or run `serveradmin` in the console.

The addon uses the Garry's Mod Derma UI and server-authoritative net messages. It is an in-game panel, not a remote web panel.

## Current features

### Dashboard
- Fullscreen interface with sidebar navigation
- Live hostname, map, player count and player table
- Tickrate estimate, server uptime and Lua memory estimate
- Current gravity and gamemode status

### Player management
- Search by name, SteamID, team/job and rank
- Player role, ping, health, armor, alive state and DarkRP wallet
- Kick with reason
- Timed/permanent ban with reason
- Warnings
- Freeze and unfreeze
- Bring and goto
- Heal, respawn and slay
- Set wallet balance and adjust wallet balance (DarkRP + superadmin)
- Change player job (DarkRP + superadmin)

### Server settings
- Change hostname
- Change gravity
- Change map after confirming the action
- Server-side validation and superadmin checks

### Audit and diagnostics
- SQLite-backed audit log for ServerAdmin actions
- Recent log viewer
- Runtime information, estimated tickrate, uptime and Lua memory estimate

## Permissions and safety

- Only players recognized by Garry's Mod as admins can open/use the panel.
- Sensitive settings, map changes, wallet changes and job changes require superadmin.
- All actions are validated on the server; client UI visibility is not treated as permission.
- A regular admin cannot target a superadmin. Some actions against other admins are restricted to superadmins.
- Map changes require a matching map file to exist on the server.
- Audit entries are stored in the server's SQLite database.

## DarkRP compatibility

DarkRP-specific controls are shown when DarkRP job data and player wallet functions are available. The addon reads registered jobs from `RPExtraTeams`; it does not attempt to rewrite DarkRP configuration files or override unrelated addons.

## Metrics note

Garry's Mod does not expose every operating-system metric through ordinary addon Lua. The dashboard labels the tickrate and Lua memory values as estimates; it does not fabricate CPU or system RAM readings.

## Testing recommendation

Test on a private server first, especially the moderation actions and DarkRP job changes. Other server addons can alter job-switching rules or moderation behavior.

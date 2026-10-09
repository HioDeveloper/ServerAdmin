# ServerAdmin

A modern, dark administration panel for Garry's Mod servers.

## Installation
1. Download or clone this repository.
2. Place the repository folder in `garrysmod/addons/ServerAdmin`.
3. Restart the server or change map.
4. Open the panel with **F6** or run `serveradmin` in the console.

Only users recognized by Garry's Mod as admins can open the panel. Sensitive server settings and map changes require superadmin privileges. Every action is checked server-side.

## Features
- Live overview: hostname, map, player count and gravity
- Player list with search, SteamID, team and ping
- Kick and timed/permanent ban with reason
- Freeze, unfreeze, slay, bring and goto
- Superadmin settings for hostname, gravity and map
- Server console audit messages for moderation actions
- `addon.json` included for gmpublish

## Notes
- Ban duration is measured in minutes; `0` means permanent.
- This is an in-game administration panel, not a remote web panel.
- Test on a private server before deploying to a public server.

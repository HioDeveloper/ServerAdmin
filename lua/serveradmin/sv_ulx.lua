-- ServerAdmin ULX-compatible command layer.
-- Original implementation; does not depend on the upstream ULib/ULX runtime.
-- Server-authoritative commands, persisted groups/access overrides, chat aliases and voting.

ServerAdminULX = ServerAdminULX or {}
local U = ServerAdminULX
U.Version = "1.1.0"

if not SERVER then return end

local DATA_DIR = "serveradmin"
local DATA_FILE = DATA_DIR .. "/ulx_access.json"
local LOG_FILE = DATA_DIR .. "/ulx.log"
file.CreateDir(DATA_DIR)

local function clean(value, limit)
    value = tostring(value or "")
    value = string.gsub(value, "[%c]", " ")
    value = string.gsub(value, "[\r\n;]", " ")
    value = string.Trim(value)
    return string.sub(value, 1, limit or 180)
end

local function validSteamID(value)
    return isstring(value) and string.match(value, "^STEAM_%d:%d:%d+$") ~= nil
end

local function validSteamID64(value)
    return isstring(value) and #value == 17 and string.match(value, "^%d+$") ~= nil
end

local function resolveSteamID64(value)
    value = tostring(value or "")
    if validSteamID64(value) then return value end
    if validSteamID(value) and isfunction(util.SteamIDTo64) then
        local ok, converted = pcall(util.SteamIDTo64, value)
        if ok and validSteamID64(tostring(converted or "")) then return tostring(converted) end
    end
    return nil
end

local function keyFor(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return nil end
    local value = ply:SteamID64()
    if not validSteamID64(value) then return nil end
    return value
end

local function defaultStore()
    return {
        groups = {
            user = { immunity = 0, parent = "", access = {} },
            operator = { immunity = 25, parent = "user", access = {} },
            admin = { immunity = 50, parent = "operator", access = {} },
            superadmin = { immunity = 100, parent = "admin", access = {} }
        },
        users = {},
        groupAccess = {},
        userAccess = {}
    }
end

local store = defaultStore()
local function saveStore()
    local json = util.TableToJSON(store, true)
    if not isstring(json) then
        ErrorNoHalt("[ServerAdmin/ULX] Could not encode access configuration.\n")
        return false
    end
    file.Write(DATA_FILE, json)
    return true
end

local function loadStore()
    local contents = file.Read(DATA_FILE, "DATA")
    if not contents or contents == "" then
        saveStore()
        return
    end
    local decoded = util.JSONToTable(contents)
    if not istable(decoded) or not istable(decoded.groups) or not istable(decoded.users) then
        ErrorNoHalt("[ServerAdmin/ULX] Invalid access file; defaults loaded and original file left untouched.\n")
        return
    end
    local defaults = defaultStore()
    store = decoded
    store.groupAccess = istable(store.groupAccess) and store.groupAccess or {}
    store.userAccess = istable(store.userAccess) and store.userAccess or {}
    for name, group in pairs(defaults.groups) do
        if not istable(store.groups[name]) then store.groups[name] = group end
        store.groups[name].access = istable(store.groups[name].access) and store.groups[name].access or {}
        store.groups[name].immunity = math.Clamp(math.floor(tonumber(store.groups[name].immunity) or group.immunity), 0, 1000)
        store.groups[name].parent = tostring(store.groups[name].parent or group.parent)
    end
    for id, group in pairs(store.users) do
        if not validSteamID64(tostring(id)) or not isstring(group) or not store.groups[group] then
            store.users[id] = nil
        end
    end
    saveStore()
end
loadStore()

local COMMANDS, ALIASES = {}, {}
local CHAT_MUTES, CHAT_GAGS, FROZEN, BLINDED, CLOAKED = {}, {}, {}, {}, {}
local GIMPed, NOCLIPPED = {}, {}
local SPECTATING = {}
local ORIGINAL_MOVEMENT, ORIGINAL_JAIL_POS = {}, {}
local currentVote, voteSerial = nil, 0

local function tell(ply, message)
    message = "[ServerAdmin/ULX] " .. clean(message, 220)
    if IsValid(ply) and ply:IsPlayer() then ply:ChatPrint(message) else print(message) end
end

local function tellAll(message)
    PrintMessage(HUD_PRINTTALK, "[ServerAdmin/ULX] " .. clean(message, 220))
end

local function logAction(ply, action, target, detail)
    local stamp = os.date("%Y-%m-%d %H:%M:%S")
    local actor = IsValid(ply) and ply:IsPlayer() and (ply:Nick() .. " [" .. ply:SteamID() .. "]") or "Console"
    local line = stamp .. " | " .. clean(actor, 96) .. " | " .. clean(action, 48) ..
        " | " .. clean(target or "-", 96) .. " | " .. clean(detail or "", 220) .. "\n"
    file.Append(LOG_FILE, line)
    print("[ServerAdmin/ULX] " .. string.gsub(string.Trim(line), "\n", ""))
end

local function getGroupName(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return "superadmin" end
    local sid64 = keyFor(ply)
    local saved = sid64 and store.users[sid64] or nil
    if isstring(saved) and istable(store.groups[saved]) then return saved end

    local native = "user"
    if ply:IsSuperAdmin() then native = "superadmin"
    elseif ply:IsAdmin() then native = "admin"
    elseif isfunction(ply.GetUserGroup) then
        local group = tostring(ply:GetUserGroup() or "user")
        if store.groups[group] then native = group end
    end
    return native
end

local function groupImmunity(groupName, seen)
    seen = seen or {}
    if seen[groupName] then return 0 end
    seen[groupName] = true
    local group = store.groups[groupName]
    if not istable(group) then return 0 end
    local own = math.Clamp(math.floor(tonumber(group.immunity) or 0), 0, 1000)
    local parent = tostring(group.parent or "")
    if parent ~= "" and store.groups[parent] then
        return math.max(own, groupImmunity(parent, seen))
    end
    return own
end

function U.GetGroup(ply)
    return getGroupName(ply)
end

function U.GetImmunity(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return 10000 end
    local immunity = groupImmunity(getGroupName(ply))
    -- A custom assignment may grant privileges but must never silently demote a
    -- native Garry's Mod admin/superadmin below the engine's own rank.
    if ply:IsSuperAdmin() then return math.max(immunity, 100) end
    if ply:IsAdmin() then return math.max(immunity, 50) end
    return immunity
end

function U.IsAdmin(ply)
    return IsValid(ply) and ply:IsPlayer() and (ply:IsAdmin() or U.GetImmunity(ply) >= 50)
end

function U.IsSuperAdmin(ply)
    return IsValid(ply) and ply:IsPlayer() and (ply:IsSuperAdmin() or U.GetImmunity(ply) >= 100)
end

local function refreshPlayerPermissions()
    for _, target in ipairs(player.GetAll()) do
        if IsValid(target) then
            target:SetNWString("ServerAdminULXGroup", getGroupName(target))
            target:SetNWBool("ServerAdminULXIsAdmin", U.IsAdmin(target))
            target:SetNWBool("ServerAdminULXIsSuperAdmin", U.IsSuperAdmin(target))
        end
    end
end

local function explicitAccess(ply, commandName)
    if not IsValid(ply) or not ply:IsPlayer() then return nil end
    local sid64 = keyFor(ply)
    local byUser = sid64 and store.userAccess[sid64] or nil
    if istable(byUser) and isbool(byUser[commandName]) then return byUser[commandName] end

    local visited, groupName = {}, getGroupName(ply)
    for _ = 1, 16 do
        if visited[groupName] then break end
        visited[groupName] = true
        local access = store.groupAccess[groupName]
        if istable(access) and isbool(access[commandName]) then return access[commandName] end
        local group = store.groups[groupName]
        groupName = istable(group) and tostring(group.parent or "") or ""
        if groupName == "" then break end
    end
    return nil
end

function U.HasAccess(ply, commandName, minImmunity)
    if not IsValid(ply) or not ply:IsPlayer() then return true end
    local override = explicitAccess(ply, commandName)
    if override ~= nil then return override end
    return U.GetImmunity(ply) >= (tonumber(minImmunity) or 50)
end

local function canTarget(actor, target)
    if not IsValid(target) or not target:IsPlayer() then return false end
    if not IsValid(actor) or not actor:IsPlayer() then return true end
    if actor == target then return true end
    local a, b = U.GetImmunity(actor), U.GetImmunity(target)
    if a >= 100 and b < 100 then return true end
    return a > b
end

local function listTargets(query, actor)
    query = clean(query, 96)
    if query == "" then return {}, "Specify a player target." end
    local lower = string.lower(query)
    local players = player.GetAll()
    local selected = {}

    if lower == "@me" then
        if IsValid(actor) and actor:IsPlayer() then return { actor } end
        return {}, "Console has no player entity."
    elseif lower == "@all" then
        return players
    elseif lower == "@admins" then
        for _, target in ipairs(players) do
            if U.GetImmunity(target) >= 50 then selected[#selected + 1] = target end
        end
        return selected
    elseif lower == "@bots" then
        return player.GetBots()
    elseif lower == "@random" then
        if #players == 0 then return {}, "There are no connected players." end
        return { players[math.random(#players)] }
    end

    local userID = string.match(query, "^#?(%d+)$")
    if userID then
        for _, target in ipairs(players) do
            if tostring(target:UserID()) == userID then return { target } end
        end
    end

    if validSteamID(query) or validSteamID64(query) then
        for _, target in ipairs(players) do
            if target:SteamID() == query or target:SteamID64() == query then return { target } end
        end
        return {}, "Player is not online. Use the banid command for offline SteamIDs."
    end

    local exact, partial = {}, {}
    for _, target in ipairs(players) do
        local name = string.lower(target:Nick())
        if name == lower then exact[#exact + 1] = target
        elseif string.find(name, lower, 1, true) then partial[#partial + 1] = target end
    end
    if #exact == 1 then return exact end
    if #exact > 1 then return {}, "More than one player matches; use a SteamID or user ID." end
    if #partial == 1 then return partial end
    if #partial > 1 then return {}, "More than one player matches; use a more specific name." end
    return {}, "No connected player matches '" .. query .. "'."
end

local function singleTarget(actor, args, index)
    local targets, err = listTargets(args[index or 1], actor)
    if #targets ~= 1 then
        tell(actor, err or "This command requires exactly one target.")
        return nil
    end
    local target = targets[1]
    if IsValid(actor) and actor:IsPlayer() and not canTarget(actor, target) then
        tell(actor, "You do not have enough immunity to target " .. target:Nick() .. ".")
        return nil
    end
    return target
end

local function eachTarget(actor, query, callback)
    local targets, err = listTargets(query, actor)
    if #targets == 0 then tell(actor, err or "No targets found."); return 0 end
    if err then tell(actor, err) end
    local count = 0
    for _, target in ipairs(targets) do
        if canTarget(actor, target) then
            local ok, failure = pcall(callback, target)
            if ok then count = count + 1 else
                tell(actor, "Action failed for " .. target:Nick() .. ": " .. clean(failure, 140))
            end
        else
            tell(actor, "Skipped " .. target:Nick() .. " (target immunity is too high).")
        end
    end
    return count
end

local function rest(args, start)
    local items = {}
    for i = start or 1, #args do items[#items + 1] = tostring(args[i]) end
    return table.concat(items, " ")
end

local function parseNumber(value, min, max, fallback)
    local number = tonumber(value)
    if not number or number ~= number then return fallback end
    return math.Clamp(number, min, max)
end

local function minutesArg(args, index)
    local value = tonumber(args[index or 2])
    if not value or value ~= value then return nil end
    return math.Clamp(math.floor(value), 0, 525600)
end

local function register(name, minImmunity, help, run, aliases)
    local entry = {
        name = string.lower(name),
        minImmunity = tonumber(minImmunity) or 50,
        help = tostring(help or ""),
        run = run,
        aliases = aliases or {}
    }
    COMMANDS[entry.name] = entry
    ALIASES[entry.name] = entry.name
    for _, alias in ipairs(entry.aliases) do ALIASES[string.lower(alias)] = entry.name end
end

local function findCommand(name)
    name = string.lower(tostring(name or ""))
    return COMMANDS[ALIASES[name] or name]
end

local function dispatch(actor, commandName, args)
    local cmd = findCommand(commandName)
    if not cmd then
        tell(actor, "Unknown command '" .. clean(commandName, 48) .. "'. Run ulx help.")
        return false
    end
    if not U.HasAccess(actor, cmd.name, cmd.minImmunity) then
        tell(actor, "Access denied for command '" .. cmd.name .. "'.")
        return false
    end
    local ok, err = pcall(cmd.run, actor, args or {})
    if not ok then
        ErrorNoHalt("[ServerAdmin/ULX] Command '" .. cmd.name .. "' failed: " .. clean(err, 240) .. "\n")
        tell(actor, "The command failed. Check the server console.")
        return false
    end
    return true
end

local function playerListText()
    local result = {}
    for _, ply in ipairs(player.GetAll()) do
        result[#result + 1] = string.format("%s | %s | #%d | %s",
            clean(ply:Nick(), 64), ply:SteamID(), ply:UserID(), U.GetGroup(ply))
    end
    return result
end

local function requireArgs(actor, args, count, usage)
    if #args < count then
        tell(actor, "Usage: ulx " .. usage)
        return false
    end
    return true
end

local function setMoveSpeed(ply, walk, run, jump)
    ORIGINAL_MOVEMENT[ply] = ORIGINAL_MOVEMENT[ply] or {
        walk = ply:GetWalkSpeed(), run = ply:GetRunSpeed(), jump = ply:GetJumpPower()
    }
    if walk then ply:SetWalkSpeed(walk) end
    if run then ply:SetRunSpeed(run) end
    if jump then ply:SetJumpPower(jump) end
end

local function restoreMoveSpeed(ply)
    local original = ORIGINAL_MOVEMENT[ply]
    if not original then return end
    if IsValid(ply) then
        ply:SetWalkSpeed(original.walk)
        ply:SetRunSpeed(original.run)
        ply:SetJumpPower(original.jump)
    end
    ORIGINAL_MOVEMENT[ply] = nil
end

-- Public information commands
register("help", 0, "List available commands and aliases.", function(ply, args)
    local filter = string.lower(tostring(args[1] or ""))
    local rows = {}
    for name, command in pairs(COMMANDS) do
        if name ~= "help" and U.HasAccess(ply, name, command.minImmunity) and
            (filter == "" or string.find(name, filter, 1, true)) then
            rows[#rows + 1] = name .. " - " .. command.help
        end
    end
    table.sort(rows)
    tell(ply, "Commands (" .. #rows .. "):")
    for i = 1, math.min(#rows, 45) do tell(ply, rows[i]) end
    if #rows > 45 then tell(ply, "Showing first 45; run 'ulx help <filter>' to narrow the list.") end
end, {"commands"})

register("cmdhelp", 0, "Show usage and permission details for a command. Usage: ulx cmdhelp <command>", function(ply, args)
    if not requireArgs(ply, args, 1, "cmdhelp <command>") then return end
    local command = findCommand(args[1])
    if not command then tell(ply, "Unknown command. Run ulx help."); return end
    tell(ply, "Command: ulx " .. command.name)
    tell(ply, "Usage/details: " .. command.help)
    tell(ply, "Minimum immunity: " .. tostring(command.minImmunity))
    if #command.aliases > 0 then tell(ply, "Aliases: " .. table.concat(command.aliases, ", ")) end
end, {"commandhelp"})

register("menu", 0, "Open the ServerAdmin management panel.", function(ply)
    if IsValid(ply) and ply:IsPlayer() then ply:ConCommand("serveradmin")
    else tell(ply, "Open the ServerAdmin panel in-game with F6 or the serveradmin console command.") end
end, {"xgui"})

register("who", 0, "List connected players, SteamIDs, user IDs and groups.", function(ply)
    local rows = playerListText()
    tell(ply, "Connected players: " .. #rows)
    for i = 1, math.min(#rows, 45) do tell(ply, rows[i]) end
end, {"players"})

register("userinfo", 0, "Show details for a connected player. Usage: ulx userinfo <player>", function(ply, args)
    local target = singleTarget(ply, args)
    if not target then return end
    tell(ply, "Name: " .. target:Nick() .. " | SteamID: " .. target:SteamID() ..
        " | SteamID64: " .. target:SteamID64() .. " | UserID: " .. target:UserID() ..
        " | Group: " .. U.GetGroup(target) .. " | Immunity: " .. U.GetImmunity(target) ..
        " | Ping: " .. target:Ping() .. " | Health: " .. target:Health() .. "/" .. target:GetMaxHealth())
end, {"playerinfo"})

register("uptime", 0, "Show server uptime.", function(ply)
    local seconds = math.floor(CurTime())
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    tell(ply, "Current map uptime: " .. hours .. "h " .. mins .. "m.")
end)

-- Moderation
register("kick", 50, "Kick a connected player. Usage: ulx kick <player> [reason]", function(ply, args)
    if not requireArgs(ply, args, 1, "kick <player> [reason]") then return end
    local reason = clean(rest(args, 2), 160)
    if reason == "" then reason = "Kicked by an administrator" end
    local count = eachTarget(ply, args[1], function(target)
        if target == ply and IsValid(ply) and ply:IsPlayer() then error("You cannot kick yourself.") end
        local name = target:Nick()
        target:Kick(reason)
        logAction(ply, "kick", name .. " [" .. target:SteamID() .. "]", reason)
    end)
    if count > 0 then tell(ply, "Kicked " .. count .. " player(s).") end
end, {"boot", "kickid"})

register("ban", 50, "Ban online player(s). Minutes 0 = permanent. Usage: ulx ban <player> <minutes> [reason]", function(ply, args)
    if not requireArgs(ply, args, 2, "ban <player> <minutes> [reason]") then return end
    local minutes = minutesArg(args, 2)
    if not minutes then tell(ply, "Minutes must be a number from 0 to 525600 (0 = permanent)."); return end
    local reason = clean(rest(args, 3), 160)
    if reason == "" then reason = "Banned by an administrator" end
    local count = eachTarget(ply, args[1], function(target)
        if target:IsBot() or not validSteamID(target:SteamID()) then error("Only real Steam players can be banned.") end
        if target == ply and IsValid(ply) and ply:IsPlayer() then error("You cannot ban yourself.") end
        local name, sid, sid64 = target:Nick(), target:SteamID(), target:SteamID64()
        local now = os.time()
        local expires = minutes > 0 and (now + minutes * 60) or 0
        local actor = IsValid(ply) and ply:IsPlayer() and (ply:Nick() .. " [" .. ply:SteamID() .. "]") or "Console"
        sql.Query("INSERT INTO serveradmin_bans (steamid, steamid64, name, reason, actor, created, expires, active) VALUES (" ..
            sql.SQLStr(sid) .. ", " .. sql.SQLStr(sid64) .. ", " .. sql.SQLStr(clean(name, 64)) .. ", " ..
            sql.SQLStr(reason) .. ", " .. sql.SQLStr(clean(actor, 90)) .. ", " .. tostring(now) .. ", " ..
            tostring(expires) .. ", 1)")
        target:Ban(minutes, false)
        timer.Simple(0, function() RunConsoleCommand("writeid") end)
        target:Kick(reason)
        logAction(ply, "ban", name .. " [" .. sid .. "]", tostring(minutes) .. " minute(s): " .. reason)
    end)
    if count > 0 then tell(ply, "Banned " .. count .. " player(s).") end
end, {"banid-online"})

register("banid", 100, "Ban an offline SteamID. Usage: ulx banid <STEAM_ID> <minutes> [reason]", function(ply, args)
    if not requireArgs(ply, args, 2, "banid <STEAM_ID> <minutes> [reason]") then return end
    local sid = tostring(args[1] or "")
    if not validSteamID(sid) then tell(ply, "A valid SteamID is required, e.g. STEAM_0:1:12345."); return end
    local minutes = minutesArg(args, 2)
    if not minutes then tell(ply, "Minutes must be a number from 0 to 525600 (0 = permanent)."); return end
    local reason = clean(rest(args, 3), 160)
    local now = os.time()
    local expires = minutes > 0 and (now + minutes * 60) or 0
    local actor = IsValid(ply) and ply:IsPlayer() and (ply:Nick() .. " [" .. ply:SteamID() .. "]") or "Console"
    sql.Query("INSERT INTO serveradmin_bans (steamid, steamid64, name, reason, actor, created, expires, active) VALUES (" ..
        sql.SQLStr(sid) .. ", '', " .. sql.SQLStr(sid) .. ", " .. sql.SQLStr(reason) .. ", " ..
        sql.SQLStr(clean(actor, 90)) .. ", " .. tostring(now) .. ", " .. tostring(expires) .. ", 1)")
    RunConsoleCommand("banid", tostring(minutes), sid)
    RunConsoleCommand("writeid")
    logAction(ply, "banid", sid, tostring(minutes) .. " minute(s): " .. reason)
    tell(ply, "Native ban applied to " .. sid .. ". The engine ban system does not store a reason.")
end)

register("unban", 100, "Remove a native ban. Usage: ulx unban <STEAM_ID>", function(ply, args)
    if not requireArgs(ply, args, 1, "unban <STEAM_ID>") then return end
    local sid = tostring(args[1] or "")
    if not validSteamID(sid) then tell(ply, "A valid SteamID is required."); return end
    RunConsoleCommand("removeid", sid)
    RunConsoleCommand("writeid")
    sql.Query("UPDATE serveradmin_bans SET active = 0 WHERE steamid = " .. sql.SQLStr(sid))
    logAction(ply, "unban", sid, "Native ban removed")
    tell(ply, "Unban command sent for " .. sid .. ".")
end, {"removeban"})

register("warn", 50, "Store a persistent warning and notify target(s). Usage: ulx warn <player> <reason>", function(ply, args)
    if not requireArgs(ply, args, 2, "warn <player> <reason>") then return end
    local reason = clean(rest(args, 2), 160)
    if reason == "" then tell(ply, "Usage: ulx warn <player> <reason>"); return end
    local count = eachTarget(ply, args[1], function(target)
        local actor = IsValid(ply) and ply:IsPlayer() and (ply:Nick() .. " [" .. ply:SteamID() .. "]") or "Console"
        sql.Query("INSERT INTO serveradmin_warnings (steamid, name, reason, actor, created) VALUES (" ..
            sql.SQLStr(target:SteamID()) .. ", " .. sql.SQLStr(clean(target:Nick(), 64)) .. ", " ..
            sql.SQLStr(reason) .. ", " .. sql.SQLStr(clean(actor, 90)) .. ", " .. tostring(os.time()) .. ")")
        target:ChatPrint("[ServerAdmin] Warning: " .. reason)
        logAction(ply, "warn", target:Nick() .. " [" .. target:SteamID() .. "]", reason)
    end)
    if count > 0 then tell(ply, "Warned " .. count .. " player(s).") end
end)

register("banlist", 50, "Show recent ServerAdmin/ULX ban records.", function(ply)
    local rows = sql.Query("SELECT steamid, name, reason, actor, expires, active FROM serveradmin_bans ORDER BY id DESC LIMIT 25")
    if not istable(rows) then tell(ply, "Could not read ban history: " .. tostring(sql.LastError())); return end
    tell(ply, "Recent ban records: " .. #rows)
    for _, row in ipairs(rows) do
        local status = tonumber(row.active) == 1 and "ACTIVE" or "EXPIRED/REMOVED"
        local expiry = tonumber(row.expires) or 0
        local expiresText = expiry == 0 and "permanent" or os.date("%Y-%m-%d %H:%M", expiry)
        tell(ply, status .. " | " .. clean(row.name, 64) .. " | " .. clean(row.steamid, 32) ..
            " | " .. clean(row.reason, 100) .. " | by " .. clean(row.actor, 64) .. " | " .. expiresText)
    end
end)

register("slay", 50, "Kill target player(s). Usage: ulx slay <player>", function(ply, args)
    if not requireArgs(ply, args, 1, "slay <player>") then return end
    local count = eachTarget(ply, args[1], function(target)
        if target == ply and IsValid(ply) and ply:IsPlayer() then error("You cannot slay yourself.") end
        local name = target:Nick()
        target:Kill()
        logAction(ply, "slay", name, "")
    end)
    if count > 0 then tell(ply, "Slayed " .. count .. " player(s).") end
end, {"slaynr"})

register("slap", 50, "Damage and push a player. Usage: ulx slap <player> [damage]", function(ply, args)
    local target = singleTarget(ply, args)
    if not target then return end
    local damage = parseNumber(args[2], 0, 100, 0)
    if damage > 0 then
        local info = DamageInfo()
        info:SetDamage(damage)
        info:SetAttacker(IsValid(ply) and ply:IsPlayer() and ply or game.GetWorld())
        info:SetInflictor(IsValid(ply) and ply:IsPlayer() and ply or game.GetWorld())
        info:SetDamageType(DMG_CLUB)
        target:TakeDamageInfo(info)
    end
    target:SetVelocity(Vector(math.random(-180, 180), math.random(-180, 180), math.random(180, 320)))
    logAction(ply, "slap", target:Nick(), "damage=" .. damage)
    tell(ply, "Slapped " .. target:Nick() .. ".")
end)

register("freeze", 50, "Freeze target player(s). Usage: ulx freeze <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        if not FROZEN[target] then FROZEN[target] = target:IsFrozen() end
        target:Freeze(true)
        logAction(ply, "freeze", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Froze " .. count .. " player(s).") end
end)

register("unfreeze", 50, "Unfreeze target player(s). Usage: ulx unfreeze <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        target:Freeze(false)
        FROZEN[target] = nil
        logAction(ply, "unfreeze", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Unfroze " .. count .. " player(s).") end
end)

register("bring", 50, "Teleport target(s) to you. Usage: ulx bring <player>", function(ply, args)
    if not IsValid(ply) or not ply:IsPlayer() then tell(ply, "Bring requires an in-game administrator."); return end
    local count = eachTarget(ply, args[1], function(target)
        ORIGINAL_JAIL_POS[target] = target:GetPos()
        target:SetPos(ply:GetPos() + ply:GetForward() * 72 + Vector(0, 0, 8))
        logAction(ply, "bring", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Brought " .. count .. " player(s).") end
end, {"summon"})

register("goto", 50, "Teleport yourself to a player. Usage: ulx goto <player>", function(ply, args)
    if not IsValid(ply) or not ply:IsPlayer() then tell(ply, "Goto requires an in-game administrator."); return end
    local target = singleTarget(ply, args)
    if not target then return end
    if target == ply then tell(ply, "You are already at your own location."); return end
    ORIGINAL_JAIL_POS[ply] = ply:GetPos()
    ply:SetPos(target:GetPos() + target:GetForward() * 72 + Vector(0, 0, 8))
    logAction(ply, "goto", target:Nick(), "")
    tell(ply, "Teleported to " .. target:Nick() .. ".")
end, {"teleportto", "teleport"})

register("send", 50, "Send a player to another player. Usage: ulx send <player> <destination>", function(ply, args)
    if not requireArgs(ply, args, 2, "send <player> <destination>") then return end
    local target = singleTarget(ply, args, 1)
    if not target then return end
    local destination = singleTarget(ply, { args[2] }, 1)
    if not destination then return end
    if not canTarget(ply, destination) then tell(ply, "Destination player has too much immunity."); return end
    ORIGINAL_JAIL_POS[target] = target:GetPos()
    target:SetPos(destination:GetPos() + destination:GetForward() * 72 + Vector(0, 0, 8))
    logAction(ply, "send", target:Nick(), "to " .. destination:Nick())
    tell(ply, "Moved " .. target:Nick() .. " to " .. destination:Nick() .. ".")
end)

register("return", 50, "Return a player to their saved pre-teleport position. Usage: ulx return <player>", function(ply, args)
    local target = singleTarget(ply, args)
    if not target then return end
    local position = ORIGINAL_JAIL_POS[target]
    if not position then tell(ply, "No saved return position exists for that player."); return end
    target:SetPos(position)
    ORIGINAL_JAIL_POS[target] = nil
    tell(ply, "Returned " .. target:Nick() .. " to their saved position.")
end)

register("strip", 50, "Remove all weapons from target(s). Usage: ulx strip <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        target:StripWeapons()
        logAction(ply, "strip", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Stripped weapons from " .. count .. " player(s).") end
end, {"stripweapons"})

register("heal", 50, "Restore health and armour. Usage: ulx heal <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        target:SetHealth(math.max(target:GetMaxHealth(), 100))
        target:SetArmor(100)
        logAction(ply, "heal", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Healed " .. count .. " player(s).") end
end)

register("hp", 50, "Set health. Usage: ulx hp <player> <amount>", function(ply, args)
    if not requireArgs(ply, args, 2, "hp <player> <amount>") then return end
    local amount = tonumber(args[2])
    if not amount or amount < 1 or amount > 1000 then tell(ply, "Health must be between 1 and 1000."); return end
    local count = eachTarget(ply, args[1], function(target)
        target:SetHealth(math.floor(amount))
        logAction(ply, "health", target:Nick(), tostring(math.floor(amount)))
    end)
    if count > 0 then tell(ply, "Health set for " .. count .. " player(s).") end
end, {"sethealth"})

register("armor", 50, "Set armour. Usage: ulx armor <player> <amount>", function(ply, args)
    if not requireArgs(ply, args, 2, "armor <player> <amount>") then return end
    local amount = tonumber(args[2])
    if not amount or amount < 0 or amount > 1000 then tell(ply, "Armour must be between 0 and 1000."); return end
    local count = eachTarget(ply, args[1], function(target)
        target:SetArmor(math.floor(amount))
        logAction(ply, "armor", target:Nick(), tostring(math.floor(amount)))
    end)
    if count > 0 then tell(ply, "Armour set for " .. count .. " player(s).") end
end, {"setarmor"})

register("respawn", 50, "Respawn target(s). Usage: ulx respawn <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        target:Spawn()
        logAction(ply, "respawn", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Respawned " .. count .. " player(s).") end
end, {"spawn"})

register("god", 50, "Enable god mode for target(s). Usage: ulx god <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target) target:GodEnable(); logAction(ply, "god", target:Nick(), "enabled") end)
    if count > 0 then tell(ply, "God mode enabled for " .. count .. " player(s).") end
end, {"godmode"})

register("ungod", 50, "Disable god mode for target(s). Usage: ulx ungod <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target) target:GodDisable(); logAction(ply, "god", target:Nick(), "disabled") end)
    if count > 0 then tell(ply, "God mode disabled for " .. count .. " player(s).") end
end)

register("ignite", 50, "Ignite target(s). Usage: ulx ignite <player> [seconds]", function(ply, args)
    local seconds = parseNumber(args[2], 1, 120, 10)
    local count = eachTarget(ply, args[1], function(target) target:Ignite(seconds); logAction(ply, "ignite", target:Nick(), seconds .. " seconds") end)
    if count > 0 then tell(ply, "Ignited " .. count .. " player(s).") end
end)

register("extinguish", 50, "Extinguish target(s). Usage: ulx extinguish <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target) target:Extinguish(); logAction(ply, "extinguish", target:Nick(), "") end)
    if count > 0 then tell(ply, "Extinguished " .. count .. " player(s).") end
end, {"unignite"})

register("blind", 50, "Apply a screen fade to target(s). Usage: ulx blind <player> [seconds]", function(ply, args)
    local seconds = parseNumber(args[2], 1, 120, 20)
    local count = eachTarget(ply, args[1], function(target)
        target:ScreenFade(SCREENFADE.IN, Color(0, 0, 0, 255), 0.3, seconds)
        BLINDED[target] = true
        timer.Simple(seconds, function() if IsValid(target) then BLINDED[target] = nil end end)
        logAction(ply, "blind", target:Nick(), seconds .. " seconds")
    end)
    if count > 0 then tell(ply, "Screen fade applied to " .. count .. " player(s).") end
end)

register("unblind", 50, "Clear the screen fade on target(s). Usage: ulx unblind <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        target:ScreenFade(SCREENFADE.PURGE, color_white, 0, 0)
        BLINDED[target] = nil
        logAction(ply, "unblind", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Screen fade cleared for " .. count .. " player(s).") end
end)

register("cloak", 50, "Make target(s) invisible. Usage: ulx cloak <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        if not CLOAKED[target] then
            CLOAKED[target] = { color = target:GetColor(), renderMode = target:GetRenderMode(), noDraw = target:GetNoDraw(), solid = target:GetSolid() }
        end
        target:SetRenderMode(RENDERMODE_TRANSALPHA)
        target:SetColor(Color(255, 255, 255, 0))
        target:SetNoDraw(true)
        target:SetNotSolid(true)
        logAction(ply, "cloak", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Cloaked " .. count .. " player(s).") end
end)

register("uncloak", 50, "Restore visibility of target(s). Usage: ulx uncloak <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        local old = CLOAKED[target]
        if old then
            target:SetColor(old.color)
            target:SetRenderMode(old.renderMode)
            target:SetNoDraw(old.noDraw)
            target:SetSolid(old.solid)
            CLOAKED[target] = nil
        else
            target:SetColor(color_white)
            target:SetNoDraw(false)
            target:SetNotSolid(false)
        end
        logAction(ply, "uncloak", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Uncloaked " .. count .. " player(s).") end
end)

register("mute", 50, "Mute voice chat for target(s). Usage: ulx mute <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        CHAT_MUTES[target] = true
        if target.SetMuted then target:SetMuted(true) end
        logAction(ply, "mute", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Muted " .. count .. " player(s).") end
end)

register("unmute", 50, "Restore voice chat for target(s). Usage: ulx unmute <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        CHAT_MUTES[target] = nil
        if target.SetMuted then target:SetMuted(false) end
        logAction(ply, "unmute", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Unmuted " .. count .. " player(s).") end
end)

register("gag", 50, "Block chat messages from target(s). Usage: ulx gag <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        CHAT_GAGS[target] = true
        logAction(ply, "gag", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Gagged " .. count .. " player(s).") end
end)

register("ungag", 50, "Restore chat messages for target(s). Usage: ulx ungag <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        CHAT_GAGS[target] = nil
        logAction(ply, "ungag", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Ungagged " .. count .. " player(s).") end
end)

register("gimp", 50, "Replace target chat with a harmless preset message. Usage: ulx gimp <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        GIMPed[target] = true
        logAction(ply, "gimp", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Gimped " .. count .. " player(s).") end
end)

register("ungimp", 50, "Restore target chat. Usage: ulx ungimp <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        GIMPed[target] = nil
        logAction(ply, "ungimp", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Ungimped " .. count .. " player(s).") end
end)

register("gagall", 100, "Block chat messages from all players below your immunity.", function(ply)
    local count = eachTarget(ply, "@all", function(target)
        if target == ply then return end
        CHAT_GAGS[target] = true
        logAction(ply, "gag", target:Nick(), "gagall")
    end)
    tell(ply, "Gag-all processed " .. count .. " player(s).")
end)

register("ungagall", 100, "Restore chat messages for all players below your immunity.", function(ply)
    local count = eachTarget(ply, "@all", function(target) CHAT_GAGS[target] = nil end)
    tell(ply, "Ungag-all processed " .. count .. " player(s).")
end)

register("muteall", 100, "Mute voice chat for all players below your immunity.", function(ply)
    local count = eachTarget(ply, "@all", function(target)
        if target == ply then return end
        CHAT_MUTES[target] = true
        if target.SetMuted then target:SetMuted(true) end
        logAction(ply, "mute", target:Nick(), "muteall")
    end)
    tell(ply, "Mute-all processed " .. count .. " player(s).")
end)

register("unmuteall", 100, "Restore voice chat for all players below your immunity.", function(ply)
    local count = eachTarget(ply, "@all", function(target)
        CHAT_MUTES[target] = nil
        if target.SetMuted then target:SetMuted(false) end
    end)
    tell(ply, "Unmute-all processed " .. count .. " player(s).")
end)

register("noclip", 75, "Enable noclip for target(s). Usage: ulx noclip <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        if not NOCLIPPED[target] then NOCLIPPED[target] = target:GetMoveType() end
        target:SetMoveType(MOVETYPE_NOCLIP)
        logAction(ply, "noclip", target:Nick(), "enabled")
    end)
    if count > 0 then tell(ply, "Noclip enabled for " .. count .. " player(s).") end
end)

register("unnoclip", 75, "Disable noclip for target(s). Usage: ulx unnoclip <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        target:SetMoveType(NOCLIPPED[target] or MOVETYPE_WALK)
        NOCLIPPED[target] = nil
        logAction(ply, "noclip", target:Nick(), "disabled")
    end)
    if count > 0 then tell(ply, "Noclip disabled for " .. count .. " player(s).") end
end)

register("ammo", 50, "Give reserve ammo for a player's active weapon. Usage: ulx ammo <player> [amount]", function(ply, args)
    local amount = math.floor(parseNumber(args[2], 1, 1000, 120))
    local count = eachTarget(ply, args[1], function(target)
        local weapon = target:GetActiveWeapon()
        if not IsValid(weapon) then error("Player has no active weapon.") end
        local ammoType = weapon:GetPrimaryAmmoType()
        if not ammoType or ammoType < 0 then error("Active weapon has no primary ammo type.") end
        target:GiveAmmo(amount, ammoType, true)
        logAction(ply, "ammo", target:Nick(), tostring(amount))
    end)
    if count > 0 then tell(ply, "Ammo supplied to " .. count .. " player(s).") end
end)

register("csay", 50, "Show a centre-screen announcement. Usage: ulx csay <message>", function(ply, args)
    local message = clean(rest(args, 1), 160)
    if message == "" then tell(ply, "Usage: ulx csay <message>"); return end
    PrintMessage(HUD_PRINTCENTER, message)
    logAction(ply, "csay", "-", message)
end)

register("ssay", 50, "Broadcast a server message. Usage: ulx ssay <message>", function(ply, args)
    local message = clean(rest(args, 1), 180)
    if message == "" then tell(ply, "Usage: ulx ssay <message>"); return end
    tellAll(message)
    logAction(ply, "ssay", "-", message)
end)

register("maprestart", 100, "Restart the current map. Usage: ulx maprestart", function(ply)
    local currentMap = game.GetMap()
    logAction(ply, "maprestart", "-", currentMap)
    tellAll("Restarting map " .. currentMap .. ".")
    timer.Simple(1, function() RunConsoleCommand("changelevel", currentMap) end)
end, {"restartmap"})

register("freezeall", 100, "Freeze all players below your immunity.", function(ply)
    local count = eachTarget(ply, "@all", function(target)
        if target == ply then return end
        FROZEN[target] = target:IsFrozen()
        target:Freeze(true)
        logAction(ply, "freeze", target:Nick(), "freezeall")
    end)
    tell(ply, "Freeze-all processed " .. count .. " player(s).")
end)

register("jail", 75, "Freeze and save current position. Usage: ulx jail <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        ORIGINAL_JAIL_POS[target] = target:GetPos()
        target:Freeze(true)
        target:SetVelocity(Vector(0, 0, 0))
        logAction(ply, "jail", target:Nick(), "Frozen at current position; use ulx unjail to release.")
    end)
    if count > 0 then tell(ply, "Restrained " .. count .. " player(s).") end
end)

register("unjail", 75, "Release a restrained player. Usage: ulx unjail <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        target:Freeze(false)
        ORIGINAL_JAIL_POS[target] = nil
        logAction(ply, "unjail", target:Nick(), "")
    end)
    if count > 0 then tell(ply, "Released " .. count .. " player(s).") end
end)

register("speed", 50, "Set walk and run speed. Usage: ulx speed <player> <value>", function(ply, args)
    if not requireArgs(ply, args, 2, "speed <player> <value>") then return end
    local speed = tonumber(args[2])
    if not speed or speed < 50 or speed > 1500 then tell(ply, "Speed must be between 50 and 1500."); return end
    local count = eachTarget(ply, args[1], function(target)
        setMoveSpeed(target, speed, speed, nil)
        logAction(ply, "speed", target:Nick(), tostring(speed))
    end)
    if count > 0 then tell(ply, "Speed updated for " .. count .. " player(s).") end
end)

register("jump", 50, "Set jump power. Usage: ulx jump <player> <value>", function(ply, args)
    if not requireArgs(ply, args, 2, "jump <player> <value>") then return end
    local power = tonumber(args[2])
    if not power or power < 0 or power > 1000 then tell(ply, "Jump power must be between 0 and 1000."); return end
    local count = eachTarget(ply, args[1], function(target)
        setMoveSpeed(target, nil, nil, power)
        logAction(ply, "jump", target:Nick(), tostring(power))
    end)
    if count > 0 then tell(ply, "Jump power updated for " .. count .. " player(s).") end
end)

register("restoremoves", 50, "Restore saved walk/run/jump settings. Usage: ulx restoremoves <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target) restoreMoveSpeed(target); logAction(ply, "restore movement", target:Nick(), "") end)
    if count > 0 then tell(ply, "Movement settings restored for " .. count .. " player(s).") end
end)

register("giveweapon", 50, "Give a weapon class to target(s). Usage: ulx giveweapon <player> <weapon_class>", function(ply, args)
    if not requireArgs(ply, args, 2, "giveweapon <player> <weapon_class>") then return end
    local class = clean(args[2], 64)
    if not string.match(class, "^[%w_%-]+$") or not weapons.Get(class) then
        tell(ply, "That weapon class is not registered.")
        return
    end
    local count = eachTarget(ply, args[1], function(target) target:Give(class); logAction(ply, "giveweapon", target:Nick(), class) end)
    if count > 0 then tell(ply, "Weapon given to " .. count .. " player(s).") end
end, {"weapon"})

register("cleanup", 100, "Clean up map entities.", function(ply)
    game.CleanUpMap(false, {})
    logAction(ply, "cleanup", "-", "Map entities cleaned")
    tell(ply, "Map cleanup executed.")
end, {"cleanupmap"})

register("map", 100, "Change map. Usage: ulx map <mapname>", function(ply, args)
    if not requireArgs(ply, args, 1, "map <mapname>") then return end
    local mapName = clean(args[1], 64)
    if not string.match(mapName, "^[%w_%-]+$") or not file.Exists("maps/" .. mapName .. ".bsp", "GAME") then
        tell(ply, "Map name is invalid or map file was not found.")
        return
    end
    logAction(ply, "map", "-", mapName)
    tellAll("Changing map to " .. mapName .. ".")
    timer.Simple(1, function() RunConsoleCommand("changelevel", mapName) end)
end, {"changemap"})

register("hostname", 100, "Set the server hostname. Usage: ulx hostname <text>", function(ply, args)
    local value = clean(rest(args, 1), 100)
    if value == "" then tell(ply, "Usage: ulx hostname <text>"); return end
    RunConsoleCommand("hostname", value)
    logAction(ply, "hostname", "-", value)
    tell(ply, "Hostname updated.")
end)

register("gravity", 100, "Set server gravity. Usage: ulx gravity <0-2000>", function(ply, args)
    local value = tonumber(args[1])
    if not value or value < 0 or value > 2000 then tell(ply, "Usage: ulx gravity <0-2000>"); return end
    RunConsoleCommand("sv_gravity", tostring(math.floor(value)))
    logAction(ply, "gravity", "-", tostring(math.floor(value)))
    tell(ply, "Gravity updated.")
end, {"setgravity"})

register("timescale", 100, "Set host_timescale. Usage: ulx timescale <0.1-3>", function(ply, args)
    local value = tonumber(args[1])
    if not value or value < 0.1 or value > 3 then tell(ply, "Timescale must be between 0.1 and 3."); return end
    RunConsoleCommand("host_timescale", tostring(value))
    logAction(ply, "timescale", "-", tostring(value))
    tell(ply, "Timescale updated.")
end)

register("announce", 50, "Broadcast a server announcement. Usage: ulx announce <message>", function(ply, args)
    local text = clean(rest(args, 1), 180)
    if text == "" then tell(ply, "Usage: ulx announce <message>"); return end
    tellAll(text)
    logAction(ply, "announce", "-", text)
    tell(ply, "Announcement sent.")
end, {"tsay"})

register("psay", 50, "Send a private message. Usage: ulx psay <player> <message>", function(ply, args)
    if not requireArgs(ply, args, 2, "psay <player> <message>") then return end
    local target = singleTarget(ply, args, 1)
    if not target then return end
    local message = clean(rest(args, 2), 180)
    if message == "" then tell(ply, "Message cannot be empty."); return end
    target:ChatPrint("[Admin PM] " .. clean(IsValid(ply) and ply:IsPlayer() and ply:Nick() or "Console", 64) .. ": " .. message)
    tell(ply, "Private message sent to " .. target:Nick() .. ".")
    logAction(ply, "psay", target:Nick(), message)
end)

register("adminchat", 0, "Send a message to connected administrators. Usage: ulx adminchat <message>", function(ply, args)
    local message = clean(rest(args, 1), 180)
    if message == "" then tell(ply, "Usage: ulx adminchat <message>"); return end
    local actor = IsValid(ply) and ply:IsPlayer() and ply:Nick() or "Console"
    for _, target in ipairs(player.GetAll()) do
        if U.GetImmunity(target) >= 50 then target:ChatPrint("[Admin Chat] " .. actor .. ": " .. message) end
    end
    tell(ply, "Admin chat message sent.")
end, {"ac", "asay"})

register("vote", 50, "Start a yes/no poll. Usage: ulx vote <question>", function(ply, args)
    local question = clean(rest(args, 1), 140)
    if question == "" then tell(ply, "Usage: ulx vote <question>"); return end
    if currentVote then tell(ply, "A vote is already running."); return end
    voteSerial = voteSerial + 1
    currentVote = { id = voteSerial, question = question, yes = {}, no = {}, kind = "poll", duration = 20 }
    tellAll("Vote: " .. question .. " — type !yes or !no (20 seconds).")
    timer.Create("ServerAdminULX_Vote", 20, 1, function()
        local vote = currentVote
        if not vote then return end
        local yes, no = table.Count(vote.yes), table.Count(vote.no)
        tellAll("Vote ended: YES " .. yes .. " / NO " .. no .. ".")
        logAction(nil, "vote", "-", question .. " (yes=" .. yes .. ", no=" .. no .. ")")
        currentVote = nil
    end)
end)

local function startActionVote(actor, kind, target, question)
    if currentVote then tell(actor, "A vote is already running."); return end
    voteSerial = voteSerial + 1
    currentVote = { id = voteSerial, question = question, yes = {}, no = {}, kind = kind, target = target, duration = 20 }
    tellAll(question .. " — type !yes or !no (20 seconds).")
    timer.Create("ServerAdminULX_Vote", 20, 1, function()
        local vote = currentVote
        if not vote then return end
        local yes, no = table.Count(vote.yes), table.Count(vote.no)
        local passed = yes >= 2 and yes > no and yes / math.max(yes + no, 1) >= 0.6
        tellAll("Vote " .. (passed and "PASSED" or "FAILED") .. ": YES " .. yes .. " / NO " .. no .. ".")
        if passed and vote.kind == "votekick" and IsValid(vote.target) then
            local target = vote.target
            target:Kick("Removed by player vote")
            logAction(nil, "votekick", target:Nick(), "yes=" .. yes .. ", no=" .. no)
        elseif passed and vote.kind == "votemap" then
            local mapName = vote.target
            if isstring(mapName) and file.Exists("maps/" .. mapName .. ".bsp", "GAME") then
                timer.Simple(1, function() RunConsoleCommand("changelevel", mapName) end)
                logAction(nil, "votemap", "-", mapName)
            end
        elseif passed and vote.kind == "voteban" and IsValid(vote.target) then
            local target = vote.target
            if not target:IsBot() and validSteamID(target:SteamID()) then
                local sid, sid64, name = target:SteamID(), target:SteamID64(), target:Nick()
                local minutes = math.Clamp(math.floor(tonumber(vote.minutes) or 0), 0, 525600)
                local reason = clean(vote.reason or "Removed by player vote", 160)
                local now = os.time()
                local expires = minutes > 0 and (now + minutes * 60) or 0
                sql.Query("INSERT INTO serveradmin_bans (steamid, steamid64, name, reason, actor, created, expires, active) VALUES (" ..
                    sql.SQLStr(sid) .. ", " .. sql.SQLStr(sid64) .. ", " .. sql.SQLStr(clean(name, 64)) .. ", " ..
                    sql.SQLStr(reason) .. ", 'Player vote', " .. tostring(now) .. ", " .. tostring(expires) .. ", 1)")
                target:Ban(minutes, false)
                timer.Simple(0, function() RunConsoleCommand("writeid") end)
                target:Kick(reason)
                logAction(nil, "voteban", name .. " [" .. sid .. "]", tostring(minutes) .. " minute(s): " .. reason)
            end
        end
        currentVote = nil
    end)
end

register("votemap", 50, "Start a map vote. Usage: ulx votemap <mapname>", function(ply, args)
    if not requireArgs(ply, args, 1, "votemap <mapname>") then return end
    local mapName = clean(args[1], 64)
    if not string.match(mapName, "^[%w_%-]+$") or not file.Exists("maps/" .. mapName .. ".bsp", "GAME") then
        tell(ply, "Map file was not found.")
        return
    end
    startActionVote(ply, "votemap", mapName, "Change map to " .. mapName .. "?")
end)

register("votekick", 50, "Start a kick vote. Usage: ulx votekick <player> [reason]", function(ply, args)
    local target = singleTarget(ply, args)
    if not target then return end
    local reason = clean(rest(args, 2), 120)
    startActionVote(ply, "votekick", target, "Kick " .. target:Nick() .. (reason ~= "" and " (" .. reason .. ")" or "") .. "?")
end)

register("voteban", 75, "Start a ban vote. Usage: ulx voteban <player> [minutes] [reason]", function(ply, args)
    local target = singleTarget(ply, args)
    if not target then return end
    local minutes = minutesArg(args, 2) or 0
    local reason = clean(rest(args, minutesArg(args, 2) and 3 or 2), 160)
    startActionVote(ply, "voteban", target, "Ban " .. target:Nick() ..
        (minutes == 0 and " permanently" or " for " .. minutes .. " minute(s)") ..
        (reason ~= "" and " (" .. reason .. ")" or "") .. "?")
    if currentVote and currentVote.kind == "voteban" then
        currentVote.minutes = minutes
        currentVote.reason = reason ~= "" and reason or "Removed by player vote"
    end
end)

register("yes", 0, "Vote yes in the current poll.", function(ply)
    if not currentVote then tell(ply, "No active vote."); return end
    local id = IsValid(ply) and ply:IsPlayer() and ply:SteamID64() or "Console"
    if currentVote.yes[id] or currentVote.no[id] then tell(ply, "You have already voted."); return end
    currentVote.yes[id] = true
    tell(ply, "Vote registered: YES.")
end)

register("no", 0, "Vote no in the current poll.", function(ply)
    if not currentVote then tell(ply, "No active vote."); return end
    local id = IsValid(ply) and ply:IsPlayer() and ply:SteamID64() or "Console"
    if currentVote.yes[id] or currentVote.no[id] then tell(ply, "You have already voted."); return end
    currentVote.no[id] = true
    tell(ply, "Vote registered: NO.")
end)


-- Additional ULX-style utilities: player models, weapon/ammo delivery, DarkRP jobs,
-- spectating, ban lookup and a tightly allow-listed cvar manager.
register("setmodel", 75, "Set a player's model. Usage: ulx setmodel <player> <models/path.mdl>", function(ply, args)
    if not requireArgs(ply, args, 2, "setmodel <player> <models/path.mdl>") then return end
    local model = tostring(args[2] or "")
    if #model > 180 or not string.match(model, "^models/[%w_/%-%.]+%.mdl$") or
        string.find(model, "..", 1, true) or not file.Exists(model, "GAME") or
        (util.IsValidModel and not util.IsValidModel(model)) then
        tell(ply, "Model path is invalid or the model is not mounted on the server.")
        return
    end
    util.PrecacheModel(model)
    local count = eachTarget(ply, args[1], function(target)
        target:SetModel(model)
        logAction(ply, "setmodel", target:Nick(), model)
    end)
    if count > 0 then tell(ply, "Model updated for " .. count .. " player(s).") end
end, {"model"})

register("give", 50, "Give a registered weapon class. Usage: ulx give <player> <weapon_class>", function(ply, args)
    if not requireArgs(ply, args, 2, "give <player> <weapon_class>") then return end
    local class = clean(args[2], 64)
    if not string.match(class, "^[%w_%-]+$") or not weapons.Get(class) then
        tell(ply, "That weapon class is not registered.")
        return
    end
    local count = eachTarget(ply, args[1], function(target)
        local given = target:Give(class)
        if not IsValid(given) then error("The weapon could not be given.") end
        logAction(ply, "give", target:Nick(), class)
    end)
    if count > 0 then tell(ply, "Weapon given to " .. count .. " player(s).") end
end)

register("giveammo", 50, "Give reserve ammo for a player's active weapon. Usage: ulx giveammo <player> [amount]", function(ply, args)
    local amount = math.floor(parseNumber(args[2], 1, 1000, 120))
    local count = eachTarget(ply, args[1], function(target)
        local weapon = target:GetActiveWeapon()
        if not IsValid(weapon) then error("Player has no active weapon.") end
        local ammoType = weapon:GetPrimaryAmmoType()
        if not ammoType or ammoType < 0 then error("Active weapon has no primary ammo type.") end
        target:GiveAmmo(amount, ammoType, true)
        logAction(ply, "giveammo", target:Nick(), tostring(amount))
    end)
    if count > 0 then tell(ply, "Ammo supplied to " .. count .. " player(s).") end
end, {"givebullets"})

register("setjob", 75, "Change a player's DarkRP job by ID or command. Usage: ulx setjob <player> <job_id|command>", function(ply, args)
    if not requireArgs(ply, args, 2, "setjob <player> <job_id|command>") then return end
    if not istable(RPExtraTeams) then tell(ply, "DarkRP jobs are not available on this server."); return end
    local query = tostring(args[2] or "")
    local jobID = tonumber(query)
    if not jobID then
        local lower = string.lower(query)
        for id, job in pairs(RPExtraTeams) do
            if istable(job) and (string.lower(tostring(job.command or "")) == lower or string.lower(tostring(job.name or "")) == lower) then
                jobID = tonumber(id)
                break
            end
        end
    end
    if not jobID or not istable(RPExtraTeams[jobID]) then
        tell(ply, "DarkRP job was not found. Use a job ID or its chat command.")
        return
    end
    local count = eachTarget(ply, args[1], function(target)
        if not isfunction(target.changeTeam) then error("This DarkRP version does not expose changeTeam.") end
        target:changeTeam(jobID, true, true)
        logAction(ply, "setjob", target:Nick(), tostring(jobID) .. " (" .. clean(RPExtraTeams[jobID].command or "", 32) .. ")")
    end)
    if count > 0 then tell(ply, "DarkRP job change requested for " .. count .. " player(s).") end
end, {"job"})

register("spectate", 75, "Put a player into roaming spectator mode. Usage: ulx spectate <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        if not SPECTATING[target] then
            SPECTATING[target] = { pos = target:GetPos(), moveType = target:GetMoveType() }
        end
        target:Spectate(OBS_MODE_ROAMING)
        target:SpectateEntity(NULL)
        logAction(ply, "spectate", target:Nick(), "enabled")
    end)
    if count > 0 then tell(ply, "Spectator mode enabled for " .. count .. " player(s).") end
end)

register("unspectate", 75, "Return a player from spectator mode. Usage: ulx unspectate <player>", function(ply, args)
    local count = eachTarget(ply, args[1], function(target)
        local saved = SPECTATING[target]
        target:UnSpectate()
        if saved then
            if isvector(saved.pos) then target:SetPos(saved.pos) end
            target:SetMoveType(saved.moveType or MOVETYPE_WALK)
        elseif target:GetMoveType() == MOVETYPE_OBSERVER then
            target:SetMoveType(MOVETYPE_WALK)
        end
        SPECTATING[target] = nil
        logAction(ply, "spectate", target:Nick(), "disabled")
    end)
    if count > 0 then tell(ply, "Spectator mode disabled for " .. count .. " player(s).") end
end, {"unspec"})

register("baninfo", 50, "Look up the latest ServerAdmin ban record. Usage: ulx baninfo <SteamID|SteamID64>", function(ply, args)
    if not requireArgs(ply, args, 1, "baninfo <SteamID|SteamID64>") then return end
    local identity = clean(args[1], 32)
    if not validSteamID(identity) and not validSteamID64(identity) then
        tell(ply, "Provide a valid SteamID or SteamID64.")
        return
    end
    local rows = sql.Query("SELECT steamid, steamid64, name, reason, actor, created, expires, active FROM serveradmin_bans WHERE steamid = " ..
        sql.SQLStr(identity) .. " OR steamid64 = " .. sql.SQLStr(identity) .. " ORDER BY id DESC LIMIT 1")
    if not istable(rows) or not rows[1] then
        tell(ply, istable(rows) and "No ServerAdmin ban record exists for that identity." or ("Ban lookup failed: " .. tostring(sql.LastError())))
        return
    end
    local row = rows[1]
    local expires = tonumber(row.expires) or 0
    local expiresText = expires == 0 and "Permanent" or os.date("%Y-%m-%d %H:%M:%S", expires)
    tell(ply, "Ban record: " .. clean(row.name, 64) .. " | " .. clean(row.steamid, 32) ..
        " | " .. (tonumber(row.active) == 1 and "ACTIVE" or "INACTIVE") ..
        " | reason: " .. clean(row.reason, 140) .. " | by: " .. clean(row.actor, 80) ..
        " | created: " .. os.date("%Y-%m-%d %H:%M:%S", tonumber(row.created) or 0) ..
        " | expires: " .. expiresText)
end, {"banlookup"})

local ULX_CVAR_ALLOWLIST = {
    sv_gravity = { kind = "number", min = 0, max = 2000 },
    host_timescale = { kind = "number", min = 0.1, max = 3 },
    hostname = { kind = "string", maxLength = 100 },
    sv_alltalk = { kind = "bool" },
    sv_voiceenable = { kind = "bool" },
    mp_friendlyfire = { kind = "bool" },
    sbox_maxprops = { kind = "integer", min = 0, max = 10000 },
    sbox_maxragdolls = { kind = "integer", min = 0, max = 10000 },
    sbox_maxnpcs = { kind = "integer", min = 0, max = 10000 },
    sbox_maxballoons = { kind = "integer", min = 0, max = 10000 },
    sbox_maxeffects = { kind = "integer", min = 0, max = 10000 },
    sbox_maxdynamite = { kind = "integer", min = 0, max = 10000 },
    sbox_maxlamps = { kind = "integer", min = 0, max = 10000 },
    sbox_maxthrusters = { kind = "integer", min = 0, max = 10000 },
    sbox_maxwheels = { kind = "integer", min = 0, max = 10000 },
    sbox_maxhoverballs = { kind = "integer", min = 0, max = 10000 },
    sbox_maxvehicles = { kind = "integer", min = 0, max = 10000 },
    sbox_maxbuttons = { kind = "integer", min = 0, max = 10000 },
    sbox_maxemitters = { kind = "integer", min = 0, max = 10000 }
}

register("cvar", 100, "Read or set an allow-listed server cvar. Usage: ulx cvar <name> [value]", function(ply, args)
    if not requireArgs(ply, args, 1, "cvar <name> [value]") then return end
    local name = string.lower(clean(args[1], 48))
    local definition = ULX_CVAR_ALLOWLIST[name]
    if not definition then
        tell(ply, "Cvar is not in the ServerAdmin allow-list. Use ulx cvars to list supported names.")
        return
    end
    local cvar = GetConVar(name)
    if not cvar then tell(ply, "Cvar '" .. name .. "' is not available in this gamemode/server build."); return end
    if args[2] == nil then
        tell(ply, name .. " = " .. clean(cvar:GetString(), 100))
        return
    end

    local value = clean(rest(args, 2), definition.maxLength or 32)
    if definition.kind == "string" then
        if value == "" then tell(ply, "Value cannot be empty."); return end
    elseif definition.kind == "bool" then
        local normalized = string.lower(value)
        if normalized == "true" or normalized == "on" then value = "1"
        elseif normalized == "false" or normalized == "off" then value = "0" end
        if value ~= "0" and value ~= "1" then tell(ply, "Boolean cvars accept only 0/1, true/false or on/off."); return end
    else
        local number = tonumber(value)
        if not number or number ~= number or number < definition.min or number > definition.max then
            tell(ply, "Value is outside the allowed range for " .. name .. ".")
            return
        end
        if definition.kind == "integer" then number = math.floor(number) end
        value = tostring(number)
    end
    cvar:SetString(value)
    logAction(ply, "cvar", name, value)
    tell(ply, name .. " updated to " .. value .. ".")
end)

register("cvars", 100, "List cvars supported by the ServerAdmin allow-list.", function(ply)
    local names = {}
    for name in pairs(ULX_CVAR_ALLOWLIST) do names[#names + 1] = name end
    table.sort(names)
    tell(ply, "Supported cvars: " .. table.concat(names, ", "))
end)


-- High-impact ULX tools. These are superadmin-only and always audited.
-- RunConsoleCommand is used with separate arguments, never by concatenating a command string.
register("rcon", 100, "Run a server console command. Usage: ulx rcon <command> [arguments]", function(ply, args)
    if not requireArgs(ply, args, 1, "rcon <command> [arguments]") then return end
    local commandName = clean(args[1], 64)
    if commandName == "" or not string.match(commandName, "^[%w_%.%-]+$") then
        tell(ply, "Invalid console command name.")
        return
    end
    local commandArgs = {}
    for i = 2, #args do
        commandArgs[#commandArgs + 1] = clean(args[i], 180)
    end
    logAction(ply, "rcon", commandName, table.concat(commandArgs, " "))
    RunConsoleCommand(commandName, unpack(commandArgs))
    tell(ply, "Server console command dispatched: " .. commandName .. ". Check the server console/logs for its output.")
end)

register("lua", 100, "Execute Lua on the server. Usage: ulx lua <code>", function(ply, args)
    local code = string.Trim(string.gsub(tostring(rest(args, 1) or ""), "[\r\n]", " "))
    code = string.sub(code, 1, 4000)
    if code == "" then tell(ply, "Usage: ulx lua <code>"); return end
    logAction(ply, "lua", "-", string.sub(code, 1, 180))
    local ok, err = pcall(RunString, code, "ServerAdminULX", false)
    if not ok then
        tell(ply, "Lua execution failed: " .. clean(err, 160))
        ErrorNoHalt("[ServerAdmin/ULX] Lua command failed: " .. clean(err, 240) .. "\n")
        return
    end
    tell(ply, "Lua code submitted to the server runtime.")
end, {"runlua"})

register("ent", 100, "Spawn an entity at your aim position. Usage: ulx ent <class> [key:value|key:value]", function(ply, args)
    if not IsValid(ply) or not ply:IsPlayer() then tell(ply, "Entity spawning requires an in-game superadmin."); return end
    if not requireArgs(ply, args, 1, "ent <class> [key:value|key:value]") then return end
    local class = clean(args[1], 64)
    if not string.match(class, "^[%w_%-]+$") then tell(ply, "Invalid entity class."); return end
    local trace = ply:GetEyeTrace()
    if not trace or not trace.HitPos then tell(ply, "Could not find a spawn position."); return end

    local entity = ents.Create(class)
    if not IsValid(entity) then tell(ply, "Unknown or non-spawnable entity class: " .. class); return end
    local params = clean(rest(args, 2), 600)
    if params ~= "" then
        for pair in string.gmatch(params, "([^|]+)") do
            local key, value = string.match(pair, "^%s*([^:]+)%s*:%s*(.-)%s*$")
            if key and value then
                key = clean(key, 64)
                value = clean(value, 128)
                if key ~= "" then entity:SetKeyValue(key, value) end
            end
        end
    end
    entity:SetPos(trace.HitPos + Vector(0, 0, 20))
    entity:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    entity:Spawn()
    entity:Activate()
    if not IsValid(entity) then tell(ply, "Entity failed to spawn."); return end
    if undo and undo.Create then
        undo.Create("ServerAdmin ULX entity")
        undo.AddEntity(entity)
        undo.SetPlayer(ply)
        undo.Finish()
    end
    logAction(ply, "ent", class, params)
    tell(ply, "Spawned entity '" .. class .. "' (#" .. entity:EntIndex() .. ").")
end)

-- Persistent user groups and access control
local protectedGroups = { user = true, operator = true, admin = true, superadmin = true }

register("groups", 0, "List configured user groups.", function(ply)
    local names = {}
    for name, group in pairs(store.groups) do names[#names + 1] = name .. " (immunity " .. groupImmunity(name) .. ")" end
    table.sort(names)
    tell(ply, "Groups: " .. table.concat(names, ", "))
end, {"grouplist"})

register("addgroup", 100, "Create a group. Usage: ulx addgroup <name> [immunity] [parent]", function(ply, args)
    if not requireArgs(ply, args, 1, "addgroup <name> [immunity] [parent]") then return end
    local name = string.lower(clean(args[1], 32))
    if not string.match(name, "^[%w_%-]+$") or store.groups[name] then tell(ply, "Group name is invalid or already exists."); return end
    local immunity = parseNumber(args[2], 0, 99, 25)
    local parent = tostring(args[3] or "user")
    if not store.groups[parent] then tell(ply, "Parent group does not exist."); return end
    store.groups[name] = { immunity = immunity, parent = parent, access = {} }
    store.groupAccess[name] = {}
    saveStore()
    logAction(ply, "addgroup", name, "immunity=" .. immunity .. ", parent=" .. parent)
    tell(ply, "Created group '" .. name .. "'.")
end)

register("removegroup", 100, "Remove a custom group. Usage: ulx removegroup <name>", function(ply, args)
    if not requireArgs(ply, args, 1, "removegroup <name>") then return end
    local name = string.lower(clean(args[1], 32))
    if protectedGroups[name] or not store.groups[name] then tell(ply, "Group cannot be removed or does not exist."); return end
    for childName, child in pairs(store.groups) do
        if childName ~= name and tostring(child.parent or "") == name then
            tell(ply, "Cannot remove this group: '" .. childName .. "' inherits from it. Reassign the child group's parent first.")
            return
        end
    end
    for sid64, group in pairs(store.users) do
        if group == name then store.users[sid64] = "user" end
    end
    store.groups[name], store.groupAccess[name] = nil, nil
    for _, access in pairs(store.userAccess) do
        if istable(access) then access[name] = nil end
    end
    saveStore()
    refreshPlayerPermissions()
    logAction(ply, "removegroup", name, "")
    tell(ply, "Removed group '" .. name .. "'. Users assigned to it were moved to user.")
end)

register("adduser", 100, "Assign a player or SteamID64 to a group. Usage: ulx adduser <player|SteamID64> <group>", function(ply, args)
    if not requireArgs(ply, args, 2, "adduser <player|SteamID64> <group>") then return end
    local group = string.lower(clean(args[2], 32))
    if not store.groups[group] then tell(ply, "Group does not exist."); return end
    local sid64, display
    local identity = tostring(args[1] or "")
    sid64 = resolveSteamID64(identity)
    if sid64 then
        display = identity
    else
        local target = singleTarget(ply, args, 1)
        if not target then return end
        sid64, display = keyFor(target), target:Nick()
    end
    if not sid64 then tell(ply, "Could not resolve a valid SteamID64."); return end
    store.users[sid64] = group
    saveStore()
    for _, target in ipairs(player.GetAll()) do
        if keyFor(target) == sid64 then
            target:SetNWString("ServerAdminULXGroup", group)
            target:SetNWBool("ServerAdminULXIsAdmin", U.IsAdmin(target))
            target:SetNWBool("ServerAdminULXIsSuperAdmin", U.IsSuperAdmin(target))
        end
    end
    logAction(ply, "adduser", display .. " [" .. sid64 .. "]", group)
    tell(ply, "Assigned " .. display .. " to group '" .. group .. "'.")
end, {"usergroup"})

register("removeuser", 100, "Remove a custom group assignment. Usage: ulx removeuser <player|SteamID64>", function(ply, args)
    if not requireArgs(ply, args, 1, "removeuser <player|SteamID64>") then return end
    local sid64, display
    local identity = tostring(args[1] or "")
    sid64 = resolveSteamID64(identity)
    if sid64 then display = identity
    else
        local target = singleTarget(ply, args, 1)
        if not target then return end
        sid64, display = keyFor(target), target:Nick()
    end
    if not sid64 or not store.users[sid64] then tell(ply, "No saved group assignment exists for that player."); return end
    store.users[sid64] = nil
    saveStore()
    for _, target in ipairs(player.GetAll()) do
        if keyFor(target) == sid64 then
            target:SetNWString("ServerAdminULXGroup", getGroupName(target))
            target:SetNWBool("ServerAdminULXIsAdmin", U.IsAdmin(target))
            target:SetNWBool("ServerAdminULXIsSuperAdmin", U.IsSuperAdmin(target))
        end
    end
    logAction(ply, "removeuser", display, "")
    tell(ply, "Removed custom group assignment for " .. display .. ".")
end)

local function setGroupPermission(ply, args, groupMode, value)
    if not requireArgs(ply, args, 2, (groupMode and "groupallow/groupdeny <group> <command>" or "userallow/userdeny <SteamID64> <command>")) then return end
    local subject = clean(args[1], 32)
    local command = string.lower(clean(args[2], 48))
    local definition = findCommand(command)
    if not definition then tell(ply, "Unknown command name. Run ulx help."); return end
    command = definition.name
    if groupMode then
        if not store.groups[subject] then tell(ply, "Group does not exist."); return end
        store.groupAccess[subject] = istable(store.groupAccess[subject]) and store.groupAccess[subject] or {}
        store.groupAccess[subject][command] = value
    else
        local sid64 = resolveSteamID64(subject)
        if not sid64 then tell(ply, "A valid SteamID or 17-digit SteamID64 is required."); return end
        subject = sid64
        store.userAccess[sid64] = istable(store.userAccess[sid64]) and store.userAccess[sid64] or {}
        store.userAccess[sid64][command] = value
    end
    saveStore()
    logAction(ply, groupMode and "group access" or "user access", subject, command .. "=" .. tostring(value))
    tell(ply, "Access " .. (value and "granted" or "denied") .. " for " .. command .. ".")
end

register("groupallow", 100, "Allow a group to use a command. Usage: ulx groupallow <group> <command>", function(ply, args)
    setGroupPermission(ply, args, true, true)
end)

register("groupdeny", 100, "Deny a group a command. Usage: ulx groupdeny <group> <command>", function(ply, args)
    setGroupPermission(ply, args, true, false)
end)

register("userallow", 100, "Allow a SteamID/SteamID64 to use a command. Usage: ulx userallow <SteamID|SteamID64> <command>", function(ply, args)
    setGroupPermission(ply, args, false, true)
end, {"userallowid"})

register("userdeny", 100, "Deny a SteamID/SteamID64 a command. Usage: ulx userdeny <SteamID|SteamID64> <command>", function(ply, args)
    setGroupPermission(ply, args, false, false)
end, {"userdenyid"})

register("access", 100, "Show resolved group, immunity and command overrides. Usage: ulx access <player|SteamID64>", function(ply, args)
    if not requireArgs(ply, args, 1, "access <player|SteamID64>") then return end
    local sid64, groupName
    local identity = tostring(args[1] or "")
    sid64 = resolveSteamID64(identity)
    if sid64 then
        groupName = store.users[sid64] or "user"
    else
        local target = singleTarget(ply, args, 1)
        if not target then return end
        sid64, groupName = keyFor(target), getGroupName(target)
    end
    tell(ply, "SteamID64=" .. tostring(sid64) .. " | group=" .. groupName ..
        " | immunity=" .. groupImmunity(groupName))
    local access = store.userAccess[sid64]
    if istable(access) then
        for command, allowed in pairs(access) do tell(ply, command .. "=" .. tostring(allowed)) end
    end
end)

register("setgroupinheritance", 100, "Set a custom group's parent. Usage: ulx setgroupinheritance <group> <parent|none>", function(ply, args)
    if not requireArgs(ply, args, 2, "setgroupinheritance <group> <parent|none>") then return end
    local name = string.lower(clean(args[1], 32))
    local parent = string.lower(clean(args[2], 32))
    if parent == "none" then parent = "" end
    if protectedGroups[name] or not store.groups[name] then
        tell(ply, "Choose an existing custom group; built-in groups cannot be edited.")
        return
    end
    if parent ~= "" and not store.groups[parent] then tell(ply, "Parent group does not exist."); return end
    if parent == name then tell(ply, "A group cannot inherit from itself."); return end

    local cursor, visited = parent, {}
    while cursor ~= "" and store.groups[cursor] do
        if cursor == name then tell(ply, "This inheritance would create a cycle."); return end
        if visited[cursor] then tell(ply, "The existing inheritance chain contains a cycle."); return end
        visited[cursor] = true
        cursor = tostring(store.groups[cursor].parent or "")
    end

    store.groups[name].parent = parent
    saveStore()
    refreshPlayerPermissions()
    logAction(ply, "setgroupinheritance", name, parent ~= "" and parent or "none")
    tell(ply, "Parent group for '" .. name .. "' set to '" .. (parent ~= "" and parent or "none") .. "'.")
end, {"setgroupparent"})

register("immunity", 100, "Set a group's immunity. Usage: ulx immunity <group> <0-99>", function(ply, args)
    if not requireArgs(ply, args, 2, "immunity <group> <0-99>") then return end
    local name = tostring(args[1] or "")
    local value = tonumber(args[2])
    if not store.groups[name] or not value or value < 0 or value > 99 or protectedGroups[name] then
        tell(ply, "Choose a custom group and immunity from 0 to 99.")
        return
    end
    store.groups[name].immunity = math.floor(value)
    saveStore()
    refreshPlayerPermissions()
    logAction(ply, "immunity", name, tostring(math.floor(value)))
    tell(ply, "Immunity updated for '" .. name .. "'.")
end, {"setgroupimmunity"})

register("logs", 50, "Show recent ServerAdmin ULX command log entries. Usage: ulx logs [count]", function(ply, args)
    local count = math.floor(parseNumber(args[1], 1, 20, 10))
    local rows = string.Explode("\n", file.Read(LOG_FILE, "DATA") or "")
    tell(ply, "Recent ULX actions (file: data/" .. LOG_FILE .. "):")
    local first = math.max(1, #rows - count)
    for i = first, #rows do if rows[i] ~= "" then tell(ply, rows[i]) end end
end, {"log"})

register("clearlog", 100, "Clear the ServerAdmin ULX command log.", function(ply)
    file.Write(LOG_FILE, "")
    tell(ply, "ULX command log cleared.")
end)

-- The group editor talks through a dedicated channel. It never trusts a client-supplied
-- immunity or command name without validating it again on the server.
local ULX_NET = "serveradmin_ulx_net"
util.AddNetworkString(ULX_NET)

local function sendGroupSnapshot(ply)
    local snapshot = { groups = {}, users = {}, commands = {} }
    for name, group in pairs(store.groups) do
        snapshot.groups[#snapshot.groups + 1] = {
            name = name,
            immunity = math.floor(tonumber(group.immunity) or 0),
            parent = tostring(group.parent or "")
        }
    end
    table.sort(snapshot.groups, function(a, b) return a.name < b.name end)

    local seenUsers = {}
    for _, target in ipairs(player.GetAll()) do
        local sid64 = keyFor(target)
        if sid64 then seenUsers[sid64] = true end
        snapshot.users[#snapshot.users + 1] = {
            name = clean(target:Nick(), 64),
            steamid = target:SteamID(),
            steamid64 = target:SteamID64(),
            group = getGroupName(target),
            immunity = U.GetImmunity(target),
            online = true
        }
    end

    -- Include assigned offline identities in the group editor so they can be managed
    -- without requiring the player to join. Cap the offline portion to keep the net payload small.
    local offlineIDs = {}
    for sid64, groupName in pairs(store.users) do
        sid64 = tostring(sid64)
        if validSteamID64(sid64) and not seenUsers[sid64] and store.groups[groupName] then
            offlineIDs[#offlineIDs + 1] = sid64
        end
    end
    table.sort(offlineIDs)
    for i = 1, math.min(#offlineIDs, 150) do
        local sid64 = offlineIDs[i]
        local groupName = store.users[sid64]
        snapshot.users[#snapshot.users + 1] = {
            name = sid64,
            steamid = isfunction(util.SteamIDFrom64) and util.SteamIDFrom64(sid64) or "",
            steamid64 = sid64,
            group = groupName,
            immunity = groupImmunity(groupName),
            online = false
        }
    end
    table.sort(snapshot.users, function(a, b) return string.lower(a.name) < string.lower(b.name) end)

    for name, command in pairs(COMMANDS) do
        snapshot.commands[#snapshot.commands + 1] = { name = name, help = command.help }
    end
    table.sort(snapshot.commands, function(a, b) return a.name < b.name end)

    local payload = util.TableToJSON(snapshot, false) or "{}"
    -- Trim only offline assignments when an unusually large roster would exceed the net
    -- payload budget. Those identities remain saved and can still be entered manually.
    while #payload > 58000 do
        local removeIndex
        for i = #snapshot.users, 1, -1 do
            if snapshot.users[i].online == false then
                removeIndex = i
                break
            end
        end
        if not removeIndex then break end
        table.remove(snapshot.users, removeIndex)
        payload = util.TableToJSON(snapshot, false) or "{}"
    end
    if #payload > 60000 then
        tell(ply, "Group editor snapshot is too large to send safely.")
        return
    end
    net.Start(ULX_NET)
        net.WriteString("snapshot")
        net.WriteString(payload)
    net.Send(ply)
end

net.Receive(ULX_NET, function(_, ply)
    if not IsValid(ply) or not ply:IsPlayer() or not U.IsSuperAdmin(ply) then return end
    local action = net.ReadString()
    if action == "snapshot" then
        sendGroupSnapshot(ply)
        return
    end

    if action == "create_group" then
        local name = string.lower(clean(net.ReadString(), 32))
        local immunity = math.Clamp(net.ReadUInt(10), 0, 99)
        local parent = string.lower(clean(net.ReadString(), 32))
        if not string.match(name, "^[%w_%-]+$") or store.groups[name] or protectedGroups[name] then
            tell(ply, "Invalid or existing group name.")
            sendGroupSnapshot(ply)
            return
        end
        if not store.groups[parent] then tell(ply, "Parent group does not exist."); sendGroupSnapshot(ply); return end
        store.groups[name] = { immunity = immunity, parent = parent, access = {} }
        store.groupAccess[name] = {}
        saveStore()
        logAction(ply, "addgroup", name, "immunity=" .. immunity .. ", parent=" .. parent)
        sendGroupSnapshot(ply)
    elseif action == "update_group" then
        local name = string.lower(clean(net.ReadString(), 32))
        local immunity = net.ReadUInt(10)
        local parent = string.lower(clean(net.ReadString(), 32))
        if parent == "none" then parent = "" end
        if protectedGroups[name] or not store.groups[name] or immunity > 99 then
            tell(ply, "Built-in groups cannot be edited and immunity must be from 0 to 99.")
            sendGroupSnapshot(ply)
            return
        end
        if parent ~= "" and not store.groups[parent] then
            tell(ply, "Parent group does not exist.")
            sendGroupSnapshot(ply)
            return
        end
        if parent == name then
            tell(ply, "A group cannot inherit from itself.")
            sendGroupSnapshot(ply)
            return
        end
        local cursor, visited = parent, {}
        while cursor ~= "" and store.groups[cursor] do
            if cursor == name or visited[cursor] then
                tell(ply, "That parent would create a group inheritance cycle.")
                sendGroupSnapshot(ply)
                return
            end
            visited[cursor] = true
            cursor = tostring(store.groups[cursor].parent or "")
        end
        store.groups[name].immunity = immunity
        store.groups[name].parent = parent
        saveStore()
        refreshPlayerPermissions()
        logAction(ply, "update group", name, "immunity=" .. immunity .. ", parent=" .. (parent ~= "" and parent or "none"))
        sendGroupSnapshot(ply)
    elseif action == "delete_group" then
        local name = string.lower(clean(net.ReadString(), 32))
        if protectedGroups[name] or not store.groups[name] then
            tell(ply, "Default or unknown groups cannot be removed.")
            sendGroupSnapshot(ply)
            return
        end
        for childName, child in pairs(store.groups) do
            if childName ~= name and tostring(child.parent or "") == name then
                tell(ply, "Cannot delete this group because '" .. childName .. "' inherits from it.")
                sendGroupSnapshot(ply)
                return
            end
        end
        for sid64, groupName in pairs(store.users) do
            if groupName == name then store.users[sid64] = "user" end
        end
        store.groups[name], store.groupAccess[name] = nil, nil
        saveStore()
        for _, target in ipairs(player.GetAll()) do
            local sid64 = keyFor(target)
            if sid64 and store.users[sid64] == "user" then
                target:SetNWString("ServerAdminULXGroup", "user")
                target:SetNWBool("ServerAdminULXIsAdmin", U.IsAdmin(target))
                target:SetNWBool("ServerAdminULXIsSuperAdmin", U.IsSuperAdmin(target))
            end
        end
        logAction(ply, "removegroup", name, "Removed through group editor")
        sendGroupSnapshot(ply)
    elseif action == "assign_group" then
        local identity = clean(net.ReadString(), 32)
        local sid64 = resolveSteamID64(identity)
        local name = string.lower(clean(net.ReadString(), 32))
        if not sid64 or not store.groups[name] then
            tell(ply, "Invalid SteamID/SteamID64 or group.")
            sendGroupSnapshot(ply)
            return
        end
        store.users[sid64] = name
        saveStore()
        for _, target in ipairs(player.GetAll()) do
            if keyFor(target) == sid64 then
                target:SetNWString("ServerAdminULXGroup", name)
                target:SetNWBool("ServerAdminULXIsAdmin", U.IsAdmin(target))
                target:SetNWBool("ServerAdminULXIsSuperAdmin", U.IsSuperAdmin(target))
            end
        end
        logAction(ply, "adduser", sid64, name .. " (group editor; identity " .. identity .. ")")
        sendGroupSnapshot(ply)
    elseif action == "set_group_access" then
        local groupName = string.lower(clean(net.ReadString(), 32))
        local commandName = string.lower(clean(net.ReadString(), 48))
        local commandDefinition = findCommand(commandName)
        local mode = net.ReadUInt(2)
        if not store.groups[groupName] or not commandDefinition or mode > 2 then
            tell(ply, "Invalid group, command or permission mode.")
            sendGroupSnapshot(ply)
            return
        end
        commandName = commandDefinition.name
        store.groupAccess[groupName] = istable(store.groupAccess[groupName]) and store.groupAccess[groupName] or {}
        if mode == 0 then
            store.groupAccess[groupName][commandName] = nil
        else
            store.groupAccess[groupName][commandName] = mode == 1
        end
        saveStore()
        logAction(ply, "group access", groupName, commandName .. "=" .. (mode == 0 and "inherit" or (mode == 1 and "allow" or "deny")))
        sendGroupSnapshot(ply)
    else
        tell(ply, "Unknown group editor request.")
    end
end)

-- ULX-style prefix commands and admin chat. A small tokenizer keeps quoted player names intact.
local function tokenize(text)
    local out, current, quote, escaped = {}, "", nil, false
    text = tostring(text or "")
    for i = 1, #text do
        local ch = string.sub(text, i, i)
        if escaped then
            current = current .. ch
            escaped = false
        elseif ch == "\\" then
            escaped = true
        elseif quote then
            if ch == quote then quote = nil else current = current .. ch end
        elseif ch == "\"" or ch == "'" then
            quote = ch
        elseif string.match(ch, "%s") then
            if current ~= "" then out[#out + 1] = current; current = "" end
        else
            current = current .. ch
        end
    end
    if escaped then current = current .. "\\" end
    if current ~= "" then out[#out + 1] = current end
    return out
end

concommand.Add("ulx", function(ply, _, args)
    local commandName = args[1] or "help"
    local argv = {}
    for i = 2, #args do argv[#argv + 1] = args[i] end
    dispatch(ply, commandName, argv)
end)

concommand.Add("serveradmin_ulx", function(ply, _, args)
    local commandName = args[1] or "help"
    local argv = {}
    for i = 2, #args do argv[#argv + 1] = args[i] end
    dispatch(ply, commandName, argv)
end)

hook.Add("PlayerSay", "ServerAdminULX_ChatCommands", function(ply, text)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if CHAT_GAGS[ply] then return "" end
    if GIMPed[ply] then return "I have been gagged by an administrator." end
    if string.sub(text or "", 1, 1) == "@" and string.sub(text, 1, 2) ~= "@@" then
        local message = clean(string.sub(text, 2), 180)
        if message == "" then return "" end
        for _, admin in ipairs(player.GetAll()) do
            if U.GetImmunity(admin) >= 50 then admin:ChatPrint("[Admin Chat] " .. ply:Nick() .. ": " .. message) end
        end
        return ""
    end

    local first = string.sub(text or "", 1, 1)
    if first ~= "!" and first ~= "/" then return end
    local argv = tokenize(string.sub(text, 2))
    if #argv == 0 then return "" end
    local commandName = string.lower(argv[1])
    table.remove(argv, 1)
    if commandName == "yes" or commandName == "no" then
        dispatch(ply, commandName, {})
        return ""
    end
    if not findCommand(commandName) then return end
    dispatch(ply, commandName, argv)
    return ""
end)

hook.Add("PlayerCanHearPlayersVoice", "ServerAdminULX_Mute", function(_, talker)
    if IsValid(talker) and CHAT_MUTES[talker] then return false end
end)

hook.Add("PlayerDisconnected", "ServerAdminULX_ClearState", function(ply)
    CHAT_MUTES[ply], CHAT_GAGS[ply], FROZEN[ply], BLINDED[ply], CLOAKED[ply] = nil, nil, nil, nil, nil
    GIMPed[ply], NOCLIPPED[ply], SPECTATING[ply] = nil, nil, nil
    ORIGINAL_MOVEMENT[ply], ORIGINAL_JAIL_POS[ply] = nil, nil
    if currentVote then
        local id = keyFor(ply)
        if id then currentVote.yes[id], currentVote.no[id] = nil, nil end
    end
end)

hook.Add("PlayerInitialSpawn", "ServerAdminULX_SetGroupNW", function(ply)
    timer.Simple(1, function()
        if IsValid(ply) then
            ply:SetNWString("ServerAdminULXGroup", getGroupName(ply))
            ply:SetNWBool("ServerAdminULXIsAdmin", U.IsAdmin(ply))
            ply:SetNWBool("ServerAdminULXIsSuperAdmin", U.IsSuperAdmin(ply))
        end
    end)
end)

concommand.Add("serveradmin_ulx_status", function(ply)
    if IsValid(ply) and not U.IsSuperAdmin(ply) then tell(ply, "Superadmin permission required."); return end
    print("[ServerAdmin/ULX] Command layer v" .. U.Version .. " loaded; " .. table.Count(COMMANDS) .. " commands registered.")
end)

print("[ServerAdmin/ULX] Loaded v" .. U.Version .. " with " .. table.Count(COMMANDS) .. " commands. Type 'ulx help' in console or '!help' in chat.")

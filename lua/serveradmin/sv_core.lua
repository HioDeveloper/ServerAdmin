-- ServerAdmin: server-authoritative moderation, DarkRP integration and audit log
ServerAdmin = ServerAdmin or {}

local NET = "serveradmin_net"
util.AddNetworkString(NET)
local startedAt = SysTime()
local MAX_REASON = 160

local function cleanText(value, maxLength)
    value = tostring(value or "")
    value = string.Trim(value)
    value = string.gsub(value, "[%c]", "")
    return string.sub(value, 1, maxLength or 120)
end

local function isAdmin(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:IsAdmin()
end

local function isSuperAdmin(ply)
    return isAdmin(ply) and ply:IsSuperAdmin()
end

local function sendNotice(ply, ok, message)
    if not IsValid(ply) then return end
    net.Start(NET)
        net.WriteString("notice")
        net.WriteString(cleanText(message, 220))
        net.WriteBool(ok == true)
    net.Send(ply)
end

local function actorName(ply)
    if not IsValid(ply) then return "Console" end
    return cleanText(ply:Nick(), 64) .. " [" .. cleanText(ply:SteamID(), 32) .. "]"
end

local function targetName(target)
    if not IsValid(target) then return "-" end
    return cleanText(target:Nick(), 64) .. " [" .. cleanText(target:SteamID(), 32) .. "]"
end

local function ensureLogTable()
    if not sql.TableExists("serveradmin_audit") then
        sql.Query([[CREATE TABLE serveradmin_audit (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created TEXT NOT NULL,
            actor TEXT NOT NULL,
            action TEXT NOT NULL,
            target TEXT NOT NULL,
            detail TEXT NOT NULL
        )]])
    end
end
ensureLogTable()

local function audit(ply, action, target, detail)
    local created = os.date("%Y-%m-%d %H:%M:%S")
    local actor = actorName(ply)
    local targetText = targetName(target)
    local safeAction = cleanText(action, 48)
    local safeDetail = cleanText(detail or "", 220)
    sql.Query("INSERT INTO serveradmin_audit (created, actor, action, target, detail) VALUES (" ..
        sql.SQLStr(created) .. ", " .. sql.SQLStr(actor) .. ", " .. sql.SQLStr(safeAction) .. ", " ..
        sql.SQLStr(targetText) .. ", " .. sql.SQLStr(safeDetail) .. ")")
    print(string.format("[ServerAdmin] %s | %s | %s | target=%s | %s", created, actor, safeAction, targetText, safeDetail))
end

local function getRecentLogs(limit)
    ensureLogTable()
    local rows = sql.Query("SELECT created, actor, action, target, detail FROM serveradmin_audit ORDER BY id DESC LIMIT " .. tostring(math.Clamp(tonumber(limit) or 40, 1, 50)))
    if not istable(rows) then return {} end
    return rows
end

local function findByUserID(userID)
    userID = tonumber(userID)
    if not userID then return nil end
    for _, target in ipairs(player.GetAll()) do
        if target:UserID() == userID then return target end
    end
end

local function getMoney(target)
    if not IsValid(target) then return 0 end
    if target.getDarkRPVar then
        local amount = tonumber(target:getDarkRPVar("money"))
        if amount then return math.Clamp(math.floor(amount), -2000000000, 2000000000) end
    end
    return 0
end

local function isDarkRP()
    return DarkRP ~= nil or (GAMEMODE and GAMEMODE.Name and string.find(string.lower(GAMEMODE.Name), "darkrp", 1, true) ~= nil)
end

local function sendSnapshot(ply)
    if not isAdmin(ply) then
        sendNotice(ply, false, "You do not have permission to use ServerAdmin.")
        return
    end

    local players = player.GetAll()
    local maxPlayers = math.Clamp(tonumber(game.MaxPlayers()) or 0, 0, 255)
    local jobs = {}
    if istable(RPExtraTeams) then
        for id, job in pairs(RPExtraTeams) do
            if isnumber(id) and istable(job) then
                jobs[#jobs + 1] = {
                    id = math.Clamp(math.floor(id), 0, 65535),
                    name = cleanText(job.name or ("Job " .. tostring(id)), 64),
                    command = cleanText(job.command or "", 32),
                    salary = math.Clamp(math.floor(tonumber(job.salary) or 0), -2000000000, 2000000000)
                }
            end
        end
        table.sort(jobs, function(a, b) return a.id < b.id end)
    end

    local logs = getRecentLogs(40)
    net.Start(NET)
        net.WriteString("snapshot")
        net.WriteString(cleanText(GetHostName() or "Garry's Mod Server", 100))
        net.WriteString(cleanText(game.GetMap() or "unknown", 64))
        net.WriteUInt(maxPlayers, 8)
        net.WriteFloat(tonumber(GetConVarString("sv_gravity")) or 600)
        net.WriteString(cleanText(engine.ActiveGamemode() or "unknown", 48))
        net.WriteFloat(1 / math.max(engine.TickInterval(), 0.001))
        net.WriteFloat(math.max(0, SysTime() - startedAt))
        net.WriteFloat(math.max(0, collectgarbage("count") / 1024))
        net.WriteBool(isDarkRP())
        net.WriteUInt(math.min(#players, 255), 8)
        for i = 1, math.min(#players, 255) do
            local target = players[i]
            local teamName = team.GetName(target:Team()) or "Unknown"
            local role = target:IsSuperAdmin() and "Superadmin" or (target:IsAdmin() and "Admin" or "Player")
            local jobID = target:Team()
            net.WriteUInt(math.Clamp(target:UserID(), 0, 65535), 16)
            net.WriteString(cleanText(target:Nick(), 64))
            net.WriteString(cleanText(target:SteamID(), 32))
            net.WriteUInt(math.Clamp(tonumber(target:Ping()) or 0, 0, 65535), 16)
            net.WriteString(cleanText(teamName, 64))
            net.WriteBool(target:IsAdmin())
            net.WriteBool(target:IsSuperAdmin())
            net.WriteBool(target:Alive())
            net.WriteInt(getMoney(target), 32)
            net.WriteUInt(math.Clamp(target:Health(), 0, 255), 8)
            net.WriteUInt(math.Clamp(target:Armor(), 0, 255), 8)
            net.WriteString(role)
            net.WriteUInt(math.Clamp(tonumber(jobID) or 0, 0, 65535), 16)
        end

        net.WriteUInt(math.min(#jobs, 1023), 10)
        for i = 1, math.min(#jobs, 1023) do
            local job = jobs[i]
            net.WriteUInt(job.id, 16)
            net.WriteString(job.name)
            net.WriteString(job.command)
            net.WriteInt(job.salary, 32)
        end

        net.WriteUInt(math.min(#logs, 50), 7)
        for i = 1, math.min(#logs, 50) do
            local row = logs[i]
            net.WriteString(cleanText(row.created, 32))
            net.WriteString(cleanText(row.actor, 90))
            net.WriteString(cleanText(row.action, 48))
            net.WriteString(cleanText(row.target, 90))
            net.WriteString(cleanText(row.detail, 220))
        end
    net.Send(ply)
end

local SUPERADMIN_ACTIONS = {
    hostname = true, gravity = true, map = true, setmoney = true, addmoney = true, setjob = true
}

local TARGET_ACTIONS = {
    kick = true, ban = true, warn = true, freeze = true, unfreeze = true, slay = true,
    bring = true, ["goto"] = true, heal = true, respawn = true, setmoney = true, addmoney = true, setjob = true
}

local function runAction(ply, action)
    if not isAdmin(ply) then
        sendNotice(ply, false, "Permission denied.")
        return
    end

    if action == "refresh" then sendSnapshot(ply) return end
    if SUPERADMIN_ACTIONS[action] and not isSuperAdmin(ply) then
        sendNotice(ply, false, "Superadmin permission required.")
        return
    end

    if action == "hostname" then
        local hostname = cleanText(net.ReadString(), 100)
        if hostname == "" then sendNotice(ply, false, "Hostname cannot be empty.") return end
        RunConsoleCommand("hostname", hostname)
        audit(ply, "hostname changed", nil, hostname)
        sendNotice(ply, true, "Hostname updated.")
        sendSnapshot(ply)
        return
    elseif action == "gravity" then
        local gravity = net.ReadFloat()
        if not isnumber(gravity) or gravity ~= gravity then sendNotice(ply, false, "Invalid gravity value.") return end
        gravity = math.Clamp(gravity, 0, 2000)
        RunConsoleCommand("sv_gravity", tostring(math.floor(gravity)))
        audit(ply, "gravity changed", nil, tostring(math.floor(gravity)))
        sendNotice(ply, true, "Gravity updated.")
        sendSnapshot(ply)
        return
    elseif action == "map" then
        local mapName = cleanText(net.ReadString(), 64)
        if mapName == "" or not string.match(mapName, "^[%w_%-]+$") then
            sendNotice(ply, false, "Invalid map name.")
            return
        end
        if not file.Exists("maps/" .. mapName .. ".bsp", "GAME") then
            sendNotice(ply, false, "Map file was not found on the server.")
            return
        end
        audit(ply, "map change", nil, mapName)
        sendNotice(ply, true, "Changing map to " .. mapName .. ".")
        game.ConsoleCommand("changelevel " .. mapName .. "\n")
        return
    end

    if not TARGET_ACTIONS[action] then
        sendNotice(ply, false, "Unknown action.")
        return
    end

    local userID = net.ReadUInt(16)
    local target = findByUserID(userID)
    if not IsValid(target) then
        sendNotice(ply, false, "That player is no longer connected.")
        sendSnapshot(ply)
        return
    end
    if target == ply then sendNotice(ply, false, "You cannot target yourself.") return end
    if target:IsSuperAdmin() and not isSuperAdmin(ply) then
        sendNotice(ply, false, "Only a superadmin can target a superadmin.")
        return
    end
    if target:IsAdmin() and not isSuperAdmin(ply) and (action == "ban" or action == "kick" or action == "slay" or action == "setmoney" or action == "addmoney" or action == "setjob") then
        sendNotice(ply, false, "Only a superadmin can perform this action on another administrator.")
        return
    end

    if action == "kick" then
        local reason = cleanText(net.ReadString(), MAX_REASON)
        if reason == "" then reason = "Kicked by an administrator" end
        audit(ply, "kick", target, reason)
        target:Kick(reason)
        sendNotice(ply, true, "Player kicked.")
    elseif action == "ban" then
        local minutes = math.Clamp(net.ReadUInt(16), 0, 65535)
        local reason = cleanText(net.ReadString(), MAX_REASON)
        if reason == "" then reason = "Banned by an administrator" end
        audit(ply, "ban", target, tostring(minutes) .. " minute(s); " .. reason)
        target:Ban(minutes, true)
        target:Kick(reason)
        sendNotice(ply, true, minutes == 0 and "Player permanently banned." or "Player banned.")
    elseif action == "warn" then
        local reason = cleanText(net.ReadString(), MAX_REASON)
        if reason == "" then reason = "Please follow the server rules." end
        audit(ply, "warning", target, reason)
        if DarkRP and DarkRP.notify then
            DarkRP.notify(target, 1, 6, "Admin warning: " .. reason)
        else
            target:ChatPrint("[ServerAdmin] Admin warning: " .. reason)
        end
        sendNotice(ply, true, "Warning sent.")
    elseif action == "freeze" then
        target:Freeze(true); audit(ply, "freeze", target); sendNotice(ply, true, "Player frozen.")
    elseif action == "unfreeze" then
        target:Freeze(false); audit(ply, "unfreeze", target); sendNotice(ply, true, "Player unfrozen.")
    elseif action == "slay" then
        target:Kill(); audit(ply, "slay", target); sendNotice(ply, true, "Player slain.")
    elseif action == "bring" then
        target:SetPos(ply:GetPos() + ply:GetForward() * 80 + Vector(0, 0, 8))
        audit(ply, "bring", target); sendNotice(ply, true, "Player brought to you.")
    elseif action == "goto" then
        ply:SetPos(target:GetPos() + target:GetForward() * 80 + Vector(0, 0, 8))
        audit(ply, "goto", target); sendNotice(ply, true, "Teleported to player.")
    elseif action == "heal" then
        target:SetHealth(math.max(1, target:GetMaxHealth()))
        if target.SetArmor then target:SetArmor(100) end
        audit(ply, "heal", target); sendNotice(ply, true, "Player healed.")
    elseif action == "respawn" then
        target:Spawn()
        audit(ply, "respawn", target); sendNotice(ply, true, "Player respawned.")
    elseif action == "setmoney" or action == "addmoney" then
        if not isDarkRP() or not target.addMoney or not target.getDarkRPVar then
            sendNotice(ply, false, "DarkRP money functions are unavailable.")
            return
        end
        local amount = net.ReadInt(32)
        amount = math.Clamp(amount, -2000000000, 2000000000)
        local current = getMoney(target)
        local desired = action == "setmoney" and math.max(0, amount) or math.Clamp(current + amount, 0, 2000000000)
        local delta = desired - current
        target:addMoney(delta)
        audit(ply, action == "setmoney" and "money set" or "money adjusted", target, "$" .. tostring(current) .. " -> $" .. tostring(desired))
        sendNotice(ply, true, "DarkRP wallet updated.")
    elseif action == "setjob" then
        local jobID = net.ReadUInt(16)
        if not isDarkRP() or not istable(RPExtraTeams) or not RPExtraTeams[jobID] then
            sendNotice(ply, false, "That DarkRP job does not exist.")
            return
        end
        if not target.changeTeam then sendNotice(ply, false, "DarkRP job switching is unavailable.") return end
        local ok, err = pcall(function() target:changeTeam(jobID, true, true) end)
        if not ok then
            sendNotice(ply, false, "Could not change job: " .. cleanText(err, 120))
            return
        end
        audit(ply, "job changed", target, cleanText(RPExtraTeams[jobID].name or jobID, 64))
        sendNotice(ply, true, "Player job updated.")
    end

    timer.Simple(0.35, function()
        if IsValid(ply) then sendSnapshot(ply) end
    end)
end

net.Receive(NET, function(_, ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local action = net.ReadString()
    if not isstring(action) or #action > 24 then return end
    runAction(ply, action)
end)

hook.Add("PlayerInitialSpawn", "ServerAdmin_AdminHint", function(ply)
    timer.Simple(8, function()
        if IsValid(ply) and ply:IsAdmin() then
            ply:ChatPrint("[ServerAdmin] Fullscreen panel ready. Press F6 or type serveradmin.")
        end
    end)
end)

concommand.Add("serveradmin_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    print("[ServerAdmin] v" .. (ServerAdmin.Version or "2.0.0") .. " loaded.")
end)

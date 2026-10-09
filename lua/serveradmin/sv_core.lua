-- ServerAdmin: server-authoritative logic
ServerAdmin = ServerAdmin or {}

local NET = "serveradmin_net"
util.AddNetworkString(NET)

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
        net.WriteBool(ok == true)
        net.WriteString(cleanText(message, 220))
    net.Send(ply)
end

local function audit(ply, action, target, detail)
    local actor = IsValid(ply) and (ply:Nick() .. " [" .. ply:SteamID() .. "]") or "Console"
    local targetInfo = IsValid(target) and (target:Nick() .. " [" .. target:SteamID() .. "]") or "-"
    print(string.format("[ServerAdmin] %s | %s | target=%s | %s",
        os.date("%Y-%m-%d %H:%M:%S"), actor, targetInfo,
        action .. (detail and (": " .. detail) or "")))
end

local function findByUserID(userID)
    userID = tonumber(userID)
    if not userID then return nil end
    for _, target in ipairs(player.GetAll()) do
        if target:UserID() == userID then return target end
    end
end

local function sendSnapshot(ply)
    if not isAdmin(ply) then
        sendNotice(ply, false, "You do not have permission to use ServerAdmin.")
        return
    end

    local players = player.GetAll()
    net.Start(NET)
        net.WriteString("snapshot")
        net.WriteString(GetHostName() or "Garry's Mod Server")
        net.WriteString(game.GetMap() or "unknown")
        net.WriteUInt(#players, 8)
        net.WriteUInt(math.max(0, game.MaxPlayers() or 0), 8)
        net.WriteFloat(tonumber(GetConVarString("sv_gravity")) or 600)
        for _, target in ipairs(players) do
            net.WriteUInt(target:UserID(), 16)
            net.WriteString(cleanText(target:Nick(), 64))
            net.WriteString(target:SteamID() or "UNKNOWN")
            net.WriteUInt(math.Clamp(target:Ping(), 0, 65535), 16)
            net.WriteString(cleanText(team.GetName(target:Team()) or "Unknown", 48))
            net.WriteBool(target:IsAdmin())
            net.WriteBool(target:IsSuperAdmin())
            net.WriteBool(target:Alive())
        end
    net.Send(ply)
end

local function runAction(ply, action)
    if not isAdmin(ply) then
        sendNotice(ply, false, "Permission denied.")
        return
    end

    if action == "refresh" then
        sendSnapshot(ply)
        return
    end

    if action == "hostname" then
        if not isSuperAdmin(ply) then sendNotice(ply, false, "Superadmin permission required.") return end
        local hostname = cleanText(net.ReadString(), 100)
        if hostname == "" then sendNotice(ply, false, "Hostname cannot be empty.") return end
        RunConsoleCommand("hostname", hostname)
        audit(ply, "hostname changed", nil, hostname)
        sendNotice(ply, true, "Hostname updated.")
        sendSnapshot(ply)
        return
    elseif action == "gravity" then
        if not isSuperAdmin(ply) then sendNotice(ply, false, "Superadmin permission required.") return end
        local gravity = math.Clamp(net.ReadFloat(), 0, 2000)
        RunConsoleCommand("sv_gravity", tostring(math.floor(gravity)))
        audit(ply, "gravity changed", nil, tostring(math.floor(gravity)))
        sendNotice(ply, true, "Gravity updated.")
        sendSnapshot(ply)
        return
    elseif action == "map" then
        if not isSuperAdmin(ply) then sendNotice(ply, false, "Superadmin permission required.") return end
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

    local userID = net.ReadUInt(16)
    local target = findByUserID(userID)
    if not IsValid(target) then
        sendNotice(ply, false, "That player is no longer connected.")
        sendSnapshot(ply)
        return
    end
    if target == ply then sendNotice(ply, false, "You cannot target yourself.") return end
    if target:IsSuperAdmin() and not ply:IsSuperAdmin() then
        sendNotice(ply, false, "Only a superadmin can target a superadmin.")
        return
    end

    if action == "kick" then
        local reason = cleanText(net.ReadString(), 160)
        if reason == "" then reason = "Kicked by an administrator" end
        audit(ply, "kick", target, reason)
        target:Kick(reason)
        sendNotice(ply, true, "Player kicked.")
    elseif action == "ban" then
        local minutes = math.Clamp(net.ReadUInt(16), 0, 525600)
        local reason = cleanText(net.ReadString(), 160)
        if reason == "" then reason = "Banned by an administrator" end
        audit(ply, "ban", target, minutes .. " minute(s); " .. reason)
        target:Ban(minutes, true)
        target:Kick(reason)
        sendNotice(ply, true, minutes == 0 and "Player permanently banned." or "Player banned.")
    elseif action == "freeze" then
        target:Freeze(true)
        audit(ply, "freeze", target)
        sendNotice(ply, true, "Player frozen.")
    elseif action == "unfreeze" then
        target:Freeze(false)
        audit(ply, "unfreeze", target)
        sendNotice(ply, true, "Player unfrozen.")
    elseif action == "slay" then
        target:Kill()
        audit(ply, "slay", target)
        sendNotice(ply, true, "Player slain.")
    elseif action == "bring" then
        target:SetPos(ply:GetPos() + ply:GetForward() * 80 + Vector(0, 0, 8))
        audit(ply, "bring", target)
        sendNotice(ply, true, "Player brought to you.")
    elseif action == "goto" then
        ply:SetPos(target:GetPos() + target:GetForward() * 80 + Vector(0, 0, 8))
        audit(ply, "goto", target)
        sendNotice(ply, true, "Teleported to player.")
    else
        sendNotice(ply, false, "Unknown action.")
    end

    timer.Simple(0.3, function()
        if IsValid(ply) then sendSnapshot(ply) end
    end)
end

net.Receive(NET, function(_, ply)
    local action = net.ReadString()
    if not isstring(action) or #action > 24 then return end
    runAction(ply, action)
end)

hook.Add("PlayerInitialSpawn", "ServerAdmin_AdminHint", function(ply)
    timer.Simple(8, function()
        if IsValid(ply) and ply:IsAdmin() then
            ply:ChatPrint("[ServerAdmin] Panel ready. Press F6 or type serveradmin.")
        end
    end)
end)

concommand.Add("serveradmin_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    print("[ServerAdmin] v" .. (ServerAdmin.Version or "1.0.0") .. " loaded.")
end)

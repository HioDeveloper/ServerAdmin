-- ServerAdmin v3: server-authoritative admin API for Garry's Mod.
-- All client input is treated as untrusted. Do not replace the cvar allow-list with arbitrary commands.

ServerAdmin = ServerAdmin or {}
ServerAdmin.Version = "3.0.0"

local NET = "serveradmin_net"
util.AddNetworkString(NET)

local startedAt = SysTime()
local lastRequest = setmetatable({}, { __mode = "k" })
local Frozen, Muted, Gagged, GodMode = {}, {}, {}, {}
ServerAdmin.Lockdown = ServerAdmin.Lockdown == true

local MAX_REASON = 160
local function cleanText(value, maxLength)
    value = tostring(value or "")
    value = string.gsub(value, "[%c]", " ")
    value = string.gsub(value, "[\r\n;]", " ")
    value = string.Trim(value)
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

local function ensureTables()
    sql.Query([[CREATE TABLE IF NOT EXISTS serveradmin_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created TEXT NOT NULL,
        actor TEXT NOT NULL,
        action TEXT NOT NULL,
        target TEXT NOT NULL,
        detail TEXT NOT NULL
    )]])
    sql.Query([[CREATE TABLE IF NOT EXISTS serveradmin_bans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        steamid TEXT NOT NULL,
        steamid64 TEXT NOT NULL,
        name TEXT NOT NULL,
        reason TEXT NOT NULL,
        actor TEXT NOT NULL,
        created INTEGER NOT NULL,
        expires INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1
    )]])
    sql.Query([[CREATE TABLE IF NOT EXISTS serveradmin_warnings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        steamid TEXT NOT NULL,
        name TEXT NOT NULL,
        reason TEXT NOT NULL,
        actor TEXT NOT NULL,
        created INTEGER NOT NULL
    )]])
end
ensureTables()

local function audit(ply, action, target, detail)
    ensureTables()
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
    ensureTables()
    local rows = sql.Query("SELECT created, actor, action, target, detail FROM serveradmin_audit ORDER BY id DESC LIMIT " ..
        tostring(math.Clamp(math.floor(tonumber(limit) or 40), 1, 50)))
    return istable(rows) and rows or {}
end

local function getBans(limit)
    ensureTables()
    sql.Query("UPDATE serveradmin_bans SET active = 0 WHERE active = 1 AND expires > 0 AND expires <= " .. tostring(os.time()))
    local rows = sql.Query("SELECT id, steamid, steamid64, name, reason, actor, created, expires, active FROM serveradmin_bans ORDER BY id DESC LIMIT " ..
        tostring(math.Clamp(math.floor(tonumber(limit) or 50), 1, 63)))
    if not istable(rows) then return {} end
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            id = math.max(0, tonumber(row.id) or 0),
            steamid = cleanText(row.steamid, 32),
            name = cleanText(row.name, 64),
            reason = cleanText(row.reason, 160),
            actor = cleanText(row.actor, 90),
            created = tonumber(row.created) or 0,
            expires = tonumber(row.expires) or 0,
            active = tonumber(row.active) == 1
        }
    end
    return out
end

local function getWarnings(limit)
    ensureTables()
    local rows = sql.Query("SELECT id, steamid, name, reason, actor, created FROM serveradmin_warnings ORDER BY id DESC LIMIT " ..
        tostring(math.Clamp(math.floor(tonumber(limit) or 50), 1, 63)))
    if not istable(rows) then return {} end
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            id = math.max(0, tonumber(row.id) or 0),
            steamid = cleanText(row.steamid, 32),
            name = cleanText(row.name, 64),
            reason = cleanText(row.reason, 160),
            actor = cleanText(row.actor, 90),
            created = tonumber(row.created) or 0
        }
    end
    return out
end

local function insertBan(target, reason, minutes, actor)
    local now = os.time()
    local expires = minutes > 0 and (now + minutes * 60) or 0
    sql.Query("INSERT INTO serveradmin_bans (steamid, steamid64, name, reason, actor, created, expires, active) VALUES (" ..
        sql.SQLStr(cleanText(target:SteamID(), 32)) .. ", " ..
        sql.SQLStr(cleanText(target:SteamID64(), 32)) .. ", " ..
        sql.SQLStr(cleanText(target:Nick(), 64)) .. ", " ..
        sql.SQLStr(cleanText(reason, MAX_REASON)) .. ", " ..
        sql.SQLStr(cleanText(actor, 90)) .. ", " .. tostring(now) .. ", " .. tostring(expires) .. ", 1)")
end

local function insertWarning(target, reason, actor)
    sql.Query("INSERT INTO serveradmin_warnings (steamid, name, reason, actor, created) VALUES (" ..
        sql.SQLStr(cleanText(target:SteamID(), 32)) .. ", " ..
        sql.SQLStr(cleanText(target:Nick(), 64)) .. ", " ..
        sql.SQLStr(cleanText(reason, MAX_REASON)) .. ", " ..
        sql.SQLStr(cleanText(actor, 90)) .. ", " .. tostring(os.time()) .. ")")
end

local function findByUserID(userID)
    userID = tonumber(userID)
    if not userID then return nil end
    for _, target in ipairs(player.GetAll()) do
        if target:UserID() == userID then return target end
    end
end

local function getMoney(target)
    if not IsValid(target) or not target.getDarkRPVar then return 0 end
    local amount = tonumber(target:getDarkRPVar("money"))
    return amount and math.Clamp(math.floor(amount), -2000000000, 2000000000) or 0
end

local function isDarkRP()
    return DarkRP ~= nil or (GAMEMODE and GAMEMODE.Name and
        string.find(string.lower(GAMEMODE.Name), "darkrp", 1, true) ~= nil)
end

local CUSTOM_JOBS_FILE = "serveradmin/custom_jobs.json"
local MAX_CUSTOM_JOBS = 32
ServerAdmin.CustomJobs = ServerAdmin.CustomJobs or {}
ServerAdmin.StoredCustomJobs = ServerAdmin.StoredCustomJobs or {}
ServerAdmin.CustomJobsLoaded = ServerAdmin.CustomJobsLoaded or false
util.AddNetworkString("serveradmin_job_sync")
file.CreateDir("serveradmin")

local function jobClean(value, maxLength)
    value = tostring(value or "")
    value = string.gsub(value, "[%c]", " ")
    value = string.Trim(value)
    return string.sub(value, 1, maxLength or 120)
end

local function splitJobList(value, maxItems, maxLength, pattern)
    local out, seen = {}, {}
    value = tostring(value or "")
    value = string.gsub(value, "\r", "\n")
    for entry in string.gmatch(value .. ",", "(.-)[,\n]") do
        entry = jobClean(entry, maxLength)
        if entry ~= "" then
            if #out >= maxItems then return nil, "Too many list entries." end
            if not string.match(entry, pattern) then return nil, "Invalid list entry: " .. entry end
            if not seen[string.lower(entry)] then
                seen[string.lower(entry)] = true
                out[#out + 1] = entry
            end
        end
    end
    return out
end

local function normalizeJobSpec(raw)
    if not istable(raw) then return nil, "Invalid job data." end

    local spec = {}
    spec.name = jobClean(raw.name, 48)
    spec.command = string.lower(jobClean(raw.command, 32))
    spec.description = jobClean(raw.description, 320)
    spec.category = jobClean(raw.category, 48)
    spec.salary = tonumber(raw.salary)
    spec.max = tonumber(raw.max)
    spec.admin = tonumber(raw.admin)
    spec.r, spec.g, spec.b = tonumber(raw.r), tonumber(raw.g), tonumber(raw.b)
    spec.vote = raw.vote == true
    spec.hasLicense = raw.hasLicense == true

    if spec.name == "" or #spec.name < 2 then return nil, "Profession name must contain at least 2 characters." end
    if not string.match(spec.command, "^[a-z][a-z0-9_]*$") then
        return nil, "Command must start with a letter and contain only English letters, numbers and underscores."
    end
    if spec.category == "" then return nil, "Category cannot be empty." end
    if #spec.description < 1 then return nil, "Description cannot be empty." end
    if not spec.salary or spec.salary ~= spec.salary or spec.salary < 0 or spec.salary > 1000000 then
        return nil, "Salary must be between 0 and 1000000."
    end
    if not spec.max or spec.max ~= spec.max or spec.max < 0 or spec.max > 255 then
        return nil, "Player limit must be between 0 and 255 (0 means unlimited)."
    end
    if not spec.admin or spec.admin < 0 or spec.admin > 2 then return nil, "Invalid access level." end
    if not spec.r or not spec.g or not spec.b then return nil, "Choose a profession color." end
    for _, channel in ipairs({spec.r, spec.g, spec.b}) do
        if channel ~= channel or channel < 0 or channel > 255 then return nil, "Color channels must be between 0 and 255." end
    end
    spec.salary, spec.max, spec.admin = math.floor(spec.salary), math.floor(spec.max), math.floor(spec.admin)
    spec.r, spec.g, spec.b = math.floor(spec.r), math.floor(spec.g), math.floor(spec.b)

    local modelsRaw = raw.modelText
    if not isstring(modelsRaw) and istable(raw.models) then modelsRaw = table.concat(raw.models, ",") end
    spec.models = splitJobList(modelsRaw, 4, 128, "^models/[%w_/%-%.]+%.mdl$")
    if not spec.models then return nil, "Model list is invalid or contains more than 4 models." end
    if #spec.models == 0 then return nil, "Add at least one model path." end
    for _, modelPath in ipairs(spec.models) do
        if string.find(modelPath, "..", 1, true) or not file.Exists(modelPath, "GAME") then
            return nil, "Model was not found on the mounted server: " .. modelPath
        end
    end

    local weaponsRaw = raw.weaponsText
    if not isstring(weaponsRaw) and istable(raw.weapons) then weaponsRaw = table.concat(raw.weapons, ",") end
    spec.weapons = splitJobList(weaponsRaw, 8, 48, "^[%w_%-]+$")
    if not spec.weapons then return nil, "Weapon list is invalid or contains more than 8 weapon classes." end

    return spec
end

local function findJobByCommand(command, exceptID)
    if not istable(RPExtraTeams) then return nil end
    for id, job in pairs(RPExtraTeams) do
        if isnumber(id) and id ~= exceptID and istable(job) and
            string.lower(tostring(job.command or "")) == string.lower(command or "") then
            return id, job
        end
    end
end

local function findStoredIndex(command)
    for index, spec in ipairs(ServerAdmin.StoredCustomJobs) do
        if string.lower(tostring(spec.command or "")) == string.lower(tostring(command or "")) then return index end
    end
end

local function persistCustomJobs()
    file.CreateDir("serveradmin")
    local payload = util.TableToJSON(ServerAdmin.StoredCustomJobs or {}, true)
    if not isstring(payload) then return false end
    file.Write(CUSTOM_JOBS_FILE, payload)
    return true
end

local function jobToDarkRP(spec)
    return {
        color = Color(spec.r, spec.g, spec.b, 255),
        model = table.Copy(spec.models),
        description = spec.description,
        weapons = table.Copy(spec.weapons),
        command = spec.command,
        max = spec.max,
        salary = spec.salary,
        admin = spec.admin,
        vote = spec.vote,
        hasLicense = spec.hasLicense,
        category = spec.category
    }
end

local function sendCustomJobSync(recipient)
    local specs = {}
    for id, spec in pairs(ServerAdmin.CustomJobs) do
        local copy = table.Copy(spec)
        copy.id = id
        specs[#specs + 1] = copy
    end
    table.sort(specs, function(a, b) return (a.id or 0) < (b.id or 0) end)
    local payload = util.TableToJSON(specs, false) or "[]"
    if #payload > 60000 then
        ErrorNoHalt("[ServerAdmin] Custom job sync payload exceeds safe network limit.\n")
        return
    end
    net.Start("serveradmin_job_sync")
        net.WriteString(payload)
    if IsValid(recipient) then net.Send(recipient) else net.Broadcast() end
end

local function applyEditedJob(jobID, spec)
    local job = RPExtraTeams[jobID]
    if not istable(job) then return false, "The selected DarkRP profession no longer exists." end

    if DarkRP and isfunction(DarkRP.removeFromCategory) then
        pcall(DarkRP.removeFromCategory, job, "jobs")
    end

    job.name = spec.name
    job.color = Color(spec.r, spec.g, spec.b, 255)
    job.model = table.Copy(spec.models)
    job.description = spec.description
    job.weapons = table.Copy(spec.weapons)
    job.max = spec.max
    job.salary = spec.salary
    job.admin = spec.admin
    job.vote = spec.vote
    job.hasLicense = spec.hasLicense
    job.category = spec.category
    job.ServerAdminCustom = true

    if team and team.SetUp then team.SetUp(jobID, job.name, job.color) end
    if DarkRP and isfunction(DarkRP.addToCategory) then
        pcall(DarkRP.addToCategory, job, "jobs", job.category)
    end
    for _, modelPath in ipairs(spec.models) do util.PrecacheModel(modelPath) end
    return true
end

local function loadStoredCustomJobs()
    if ServerAdmin.CustomJobsLoaded or not isDarkRP() or not isfunction(DarkRP.createJob) or
        not istable(RPExtraTeams) or #RPExtraTeams < 1 or DarkRP.DARKRP_LOADING then return end

    ServerAdmin.CustomJobsLoaded = true
    local payload = file.Read(CUSTOM_JOBS_FILE, "DATA")
    local records = payload and util.JSONToTable(payload) or {}
    if not istable(records) then
        ErrorNoHalt("[ServerAdmin] Could not parse " .. CUSTOM_JOBS_FILE .. "; stored professions were ignored.\n")
        return
    end

    for _, raw in ipairs(records) do
        if #ServerAdmin.StoredCustomJobs >= MAX_CUSTOM_JOBS then break end
        local spec, err = normalizeJobSpec(raw)
        if spec then
            if not findJobByCommand(spec.command) then
                local ok, id = pcall(DarkRP.createJob, spec.name, jobToDarkRP(spec))
                if ok and isnumber(id) and istable(RPExtraTeams[id]) then
                    RPExtraTeams[id].ServerAdminCustom = true
                    ServerAdmin.CustomJobs[id] = spec
                    ServerAdmin.StoredCustomJobs[#ServerAdmin.StoredCustomJobs + 1] = spec
                else
                    ErrorNoHalt("[ServerAdmin] Could not load saved profession '" .. spec.name .. "': " .. jobClean(id, 160) .. "\n")
                end
            else
                ErrorNoHalt("[ServerAdmin] Skipped saved profession '" .. spec.name .. "' because command '/" .. spec.command .. "' is already registered.\n")
            end
        else
            ErrorNoHalt("[ServerAdmin] Invalid saved profession skipped: " .. jobClean(err, 180) .. "\n")
        end
    end
    persistCustomJobs()
    timer.Simple(2, function() sendCustomJobSync() end)
end

hook.Add("DarkRPFinishedLoading", "ServerAdmin_LoadCustomJobs", loadStoredCustomJobs)
timer.Create("ServerAdmin_WaitForDarkRPJobs", 1, 90, function()
    if ServerAdmin.CustomJobsLoaded then timer.Remove("ServerAdmin_WaitForDarkRPJobs") return end
    if isDarkRP() and isfunction(DarkRP.createJob) and istable(RPExtraTeams) and #RPExtraTeams > 0 and not DarkRP.DARKRP_LOADING then
        loadStoredCustomJobs()
        if ServerAdmin.CustomJobsLoaded then timer.Remove("ServerAdmin_WaitForDarkRPJobs") end
    end
end)

local function idForPlayer(ply)
    if not IsValid(ply) then return "" end
    return cleanText(ply:SteamID64() or "", 32)
end

local CVARS = {
    { name = "sv_gravity", kind = "number", min = 0, max = 2000 },
    { name = "sv_password", kind = "secret", maxLength = 64 },
    { name = "sv_alltalk", kind = "bool" },
    { name = "sv_voiceenable", kind = "bool" },
    { name = "sv_lan", kind = "bool" },
    { name = "mp_friendlyfire", kind = "bool" },
    { name = "sbox_noclip", kind = "bool" },
    { name = "sbox_godmode", kind = "bool" },
    { name = "sbox_weapons", kind = "bool" },
    { name = "sbox_playershurtplayers", kind = "bool" },
    { name = "sbox_maxprops", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxragdolls", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxnpcs", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxballoons", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxeffects", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxdynamite", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxlamps", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxthrusters", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxwheels", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxhoverballs", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxvehicles", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxbuttons", kind = "number", min = 0, max = 1000 },
    { name = "sbox_maxsents", kind = "number", min = 0, max = 1000 },
    { name = "sv_timeout", kind = "number", min = 30, max = 600 }
}
local CVAR_BY_NAME = {}
for _, item in ipairs(CVARS) do CVAR_BY_NAME[item.name] = item end

local function readCvar(item)
    local cv = GetConVar(item.name)
    if not cv then return "unavailable" end
    if item.kind == "secret" then return cv:GetString() ~= "" and "set" or "not set" end
    return cleanText(cv:GetString(), 80)
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
    local logs, bans, warnings = getRecentLogs(20), getBans(25), getWarnings(25)
    local entities = ents.GetAll()
    local botCount = 0
    for _, target in ipairs(players) do if target:IsBot() then botCount = botCount + 1 end end

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
            net.WriteString(idForPlayer(target))
            net.WriteInt(math.Clamp(target:Frags(), -32768, 32767), 16)
            net.WriteInt(math.Clamp(target:Deaths(), -32768, 32767), 16)
            net.WriteUInt(math.Clamp(#target:GetWeapons(), 0, 255), 8)
            net.WriteBool(Muted[idForPlayer(target)] == true)
            net.WriteBool(Gagged[idForPlayer(target)] == true)
            net.WriteBool(Frozen[idForPlayer(target)] == true)
            net.WriteBool(GodMode[idForPlayer(target)] == true)
        end

        net.WriteUInt(math.min(#jobs, 255), 10)
        for i = 1, math.min(#jobs, 255) do
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

        net.WriteUInt(math.min(#bans, 63), 6)
        for i = 1, math.min(#bans, 63) do
            local row = bans[i]
            net.WriteUInt(math.min(row.id, 4294967295), 32)
            net.WriteString(row.steamid)
            net.WriteString(row.name)
            net.WriteString(row.reason)
            net.WriteString(row.actor)
            net.WriteString(row.created > 0 and os.date("%Y-%m-%d %H:%M:%S", row.created) or "-")
            net.WriteInt(math.Clamp(row.expires, -2147483648, 2147483647), 32)
            net.WriteBool(row.active)
        end

        net.WriteUInt(math.min(#warnings, 63), 6)
        for i = 1, math.min(#warnings, 63) do
            local row = warnings[i]
            net.WriteUInt(math.min(row.id, 4294967295), 32)
            net.WriteString(row.steamid)
            net.WriteString(row.name)
            net.WriteString(row.reason)
            net.WriteString(row.actor)
            net.WriteString(row.created > 0 and os.date("%Y-%m-%d %H:%M:%S", row.created) or "-")
        end

        net.WriteUInt(math.min(#CVARS, 63), 6)
        for i = 1, math.min(#CVARS, 63) do
            net.WriteString(CVARS[i].name)
            net.WriteString(readCvar(CVARS[i]))
            net.WriteString(CVARS[i].kind)
        end
        net.WriteBool(ServerAdmin.Lockdown == true)
        net.WriteUInt(math.Clamp(botCount, 0, 255), 8)
        net.WriteUInt(math.Clamp(#entities, 0, 65535), 16)
    net.Send(ply)
    sendCustomJobSync(ply)
end

local SUPERADMIN_ACTIONS = {
    job_create = true, job_edit = true,
    hostname = true, gravity = true, map = true, setmoney = true, addmoney = true, setjob = true,
    unban = true, setcvar = true, botadd = true, botkickall = true, announce = true,
    cleanup = true, lockdown = true, sethealth = true, setarmor = true
}
local TARGET_ACTIONS = {
    kick = true, ban = true, warn = true, freeze = true, unfreeze = true, slay = true,
    bring = true, ["goto"] = true, heal = true, respawn = true, setmoney = true, addmoney = true,
    setjob = true, mute = true, unmute = true, gag = true, ungag = true, god = true, ungod = true,
    strip = true, ignite = true, extinguish = true, sethealth = true, setarmor = true
}

local function targetIsProtected(ply, target, action)
    if target == ply then
        sendNotice(ply, false, "You cannot target yourself.")
        return true
    end
    if target:IsSuperAdmin() and not isSuperAdmin(ply) then
        sendNotice(ply, false, "Only a superadmin can target a superadmin.")
        return true
    end
    if target:IsAdmin() and not isSuperAdmin(ply) and
        (action == "ban" or action == "kick" or action == "slay" or action == "setmoney" or
        action == "addmoney" or action == "setjob" or action == "ignite" or action == "strip" or
        action == "sethealth" or action == "setarmor") then
        sendNotice(ply, false, "Only a superadmin can perform this action on another administrator.")
        return true
    end
    return false
end

local function runAction(ply, action)
    if not isAdmin(ply) then sendNotice(ply, false, "Permission denied.") return end
    if action == "refresh" then sendSnapshot(ply) return end
    if SUPERADMIN_ACTIONS[action] and not isSuperAdmin(ply) then
        sendNotice(ply, false, "Superadmin permission required.")
        return
    end

    if action == "job_create" or action == "job_edit" then
        if not isDarkRP() or not isfunction(DarkRP.createJob) or not istable(RPExtraTeams) then
            sendNotice(ply, false, "DarkRP job API is unavailable.")
            return
        end

        local jobID
        if action == "job_edit" then jobID = net.ReadUInt(16) end
        local payload = net.ReadString()
        if not isstring(payload) or #payload > 12000 then
            sendNotice(ply, false, "Profession data is too large.")
            return
        end
        local raw = util.JSONToTable(payload)
        if not istable(raw) then sendNotice(ply, false, "Profession data could not be parsed.") return end

        local oldSpec
        if action == "job_edit" then
            oldSpec = ServerAdmin.CustomJobs[jobID]
            if not oldSpec or not istable(RPExtraTeams[jobID]) or not RPExtraTeams[jobID].ServerAdminCustom then
                sendNotice(ply, false, "Only professions created by ServerAdmin can be edited here.")
                return
            end
            -- The chat command is tied to DarkRP's internal command registry and is immutable after creation.
            raw.command = oldSpec.command
        elseif #ServerAdmin.StoredCustomJobs >= MAX_CUSTOM_JOBS then
            sendNotice(ply, false, "Custom profession limit reached (32).")
            return
        end

        local spec, err = normalizeJobSpec(raw)
        if not spec then sendNotice(ply, false, err or "Invalid profession data.") return end
        local existingID = findJobByCommand(spec.command, action == "job_edit" and jobID or nil)
        if existingID then
            sendNotice(ply, false, "This command is already used by profession ID " .. tostring(existingID) .. ".")
            return
        end

        if action == "job_create" then
            local ok, newID = pcall(DarkRP.createJob, spec.name, jobToDarkRP(spec))
            if not ok or not isnumber(newID) or not istable(RPExtraTeams[newID]) then
                ErrorNoHalt("[ServerAdmin] DarkRP.createJob failed: " .. jobClean(newID, 180) .. "\n")
                sendNotice(ply, false, "DarkRP rejected the profession. Check the server console.")
                return
            end
            RPExtraTeams[newID].ServerAdminCustom = true
            ServerAdmin.CustomJobs[newID] = spec
            ServerAdmin.StoredCustomJobs[#ServerAdmin.StoredCustomJobs + 1] = spec
            persistCustomJobs()
            audit(ply, "custom DarkRP profession created", nil, spec.name .. " (/" .. spec.command .. ")")
            sendNotice(ply, true, "Profession '" .. spec.name .. "' created and saved.")
        else
            local ok, editError = applyEditedJob(jobID, spec)
            if not ok then sendNotice(ply, false, editError) return end
            ServerAdmin.CustomJobs[jobID] = spec
            local storedIndex = findStoredIndex(oldSpec.command)
            if storedIndex then ServerAdmin.StoredCustomJobs[storedIndex] = spec end
            if not persistCustomJobs() then
                sendNotice(ply, false, "Profession changed in memory, but the JSON file could not be saved.")
                return
            end
            audit(ply, "custom DarkRP profession edited", nil, spec.name .. " (/" .. spec.command .. ")")
            sendNotice(ply, true, "Profession '" .. spec.name .. "' updated and saved.")
        end

        timer.Simple(0.5, function()
            sendCustomJobSync()
            for _, admin in ipairs(player.GetAll()) do
                if isAdmin(admin) then sendSnapshot(admin) end
            end
        end)
    elseif action == "hostname" then
        local hostname = cleanText(net.ReadString(), 100)
        if hostname == "" then sendNotice(ply, false, "Hostname cannot be empty.") return end
        RunConsoleCommand("hostname", hostname)
        audit(ply, "hostname changed", nil, hostname)
        sendNotice(ply, true, "Hostname updated.")
    elseif action == "gravity" then
        local gravity = net.ReadFloat()
        if gravity ~= gravity or gravity < 0 or gravity > 2000 then sendNotice(ply, false, "Gravity must be between 0 and 2000.") return end
        RunConsoleCommand("sv_gravity", tostring(math.floor(gravity)))
        audit(ply, "gravity changed", nil, tostring(math.floor(gravity)))
        sendNotice(ply, true, "Gravity updated.")
    elseif action == "map" then
        local mapName = cleanText(net.ReadString(), 64)
        if mapName == "" or not string.match(mapName, "^[%w_%-]+$") then sendNotice(ply, false, "Invalid map name.") return end
        if not file.Exists("maps/" .. mapName .. ".bsp", "GAME") then sendNotice(ply, false, "Map file was not found on the server.") return end
        audit(ply, "map change", nil, mapName)
        sendNotice(ply, true, "Changing map to " .. mapName .. ".")
        RunConsoleCommand("changelevel", mapName)
    elseif action == "setcvar" then
        local name = cleanText(net.ReadString(), 64)
        local value = cleanText(net.ReadString(), 80)
        local item = CVAR_BY_NAME[name]
        if not item then sendNotice(ply, false, "This server variable is not allowed by ServerAdmin.") return end
        local cv = GetConVar(name)
        if not cv then sendNotice(ply, false, "Server variable is unavailable: " .. name) return end
        if item.kind == "bool" then
            if value ~= "0" and value ~= "1" then sendNotice(ply, false, "Boolean values must be 0 or 1.") return end
        elseif item.kind == "number" then
            local number = tonumber(value)
            if not number or number ~= number or number < item.min or number > item.max then
                sendNotice(ply, false, "Value out of range for " .. name .. ".")
                return
            end
            value = tostring(math.floor(number))
        elseif item.kind == "secret" then
            if #value > (item.maxLength or 64) then sendNotice(ply, false, "Value is too long.") return end
        end
        RunConsoleCommand(name, value)
        audit(ply, "server setting changed", nil, name .. " = " .. (item.kind == "secret" and (value == "" and "(cleared)" or "(updated)") or value))
        sendNotice(ply, true, name .. " updated.")
    elseif action == "botadd" then
        local amount = math.Clamp(net.ReadUInt(4), 1, 10)
        local freeSlots = math.max(0, game.MaxPlayers() - player.GetCount())
        amount = math.min(amount, freeSlots)
        if amount < 1 then sendNotice(ply, false, "No free player slots for bots.") return end
        local created = 0
        for i = 1, amount do
            local ok, bot = pcall(player.CreateNextBot, "ServerAdmin_Bot")
            if ok and IsValid(bot) then created = created + 1 end
        end
        audit(ply, "bots added", nil, tostring(created))
        sendNotice(ply, created > 0, tostring(created) .. " bot(s) created.")
    elseif action == "botkickall" then
        local count = 0
        for _, bot in ipairs(player.GetBots()) do bot:Kick("Bots removed by an administrator"); count = count + 1 end
        audit(ply, "bots removed", nil, tostring(count))
        sendNotice(ply, true, tostring(count) .. " bot(s) removed.")
    elseif action == "announce" then
        local message = cleanText(net.ReadString(), 180)
        if message == "" then sendNotice(ply, false, "Announcement cannot be empty.") return end
        PrintMessage(HUD_PRINTTALK, "[SERVER] " .. message)
        audit(ply, "server announcement", nil, message)
        sendNotice(ply, true, "Announcement sent to all players.")
    elseif action == "cleanup" then
        game.CleanUpMap(false, {})
        audit(ply, "map cleanup", nil, "Admin cleanup executed")
        sendNotice(ply, true, "Map cleanup requested.")
    elseif action == "lockdown" then
        ServerAdmin.Lockdown = net.ReadBool()
        audit(ply, ServerAdmin.Lockdown and "build lockdown enabled" or "build lockdown disabled", nil, "")
        sendNotice(ply, true, ServerAdmin.Lockdown and "Build lockdown enabled." or "Build lockdown disabled.")
    elseif action == "unban" then
        local banID = net.ReadUInt(32)
        local rows = sql.Query("SELECT id, steamid, active FROM serveradmin_bans WHERE id = " .. tostring(banID) .. " LIMIT 1")
        if not istable(rows) or not rows[1] then sendNotice(ply, false, "Ban record not found.") return end
        local sid = cleanText(rows[1].steamid, 32)
        if not string.match(sid, "^STEAM_%d:%d:%d+$") then
            sendNotice(ply, false, "Stored SteamID is invalid; native unban was not run.")
            return
        end
        RunConsoleCommand("removeid", sid)
        RunConsoleCommand("writeid")
        sql.Query("UPDATE serveradmin_bans SET active = 0 WHERE id = " .. tostring(banID))
        audit(ply, "unban", nil, sid .. " (record " .. tostring(banID) .. ")")
        sendNotice(ply, true, "Unban command sent and record deactivated.")
    end

    if TARGET_ACTIONS[action] then
        local userID = net.ReadUInt(16)
        local target = findByUserID(userID)
        if not IsValid(target) then sendNotice(ply, false, "That player is no longer connected."); sendSnapshot(ply); return end
        if targetIsProtected(ply, target, action) then return end

        if action == "kick" then
            local reason = cleanText(net.ReadString(), MAX_REASON)
            if reason == "" then reason = "Kicked by an administrator" end
            audit(ply, "kick", target, reason)
            target:Kick(reason)
            sendNotice(ply, true, "Player kicked.")
        elseif action == "ban" then
            local minutes = math.Clamp(net.ReadUInt(16), 0, 65535)
            local reason = cleanText(net.ReadString(), MAX_REASON)
            if target:IsBot() or not string.match(target:SteamID() or "", "^STEAM_%d:%d:%d+$") then
                sendNotice(ply, false, "Only real Steam players can be banned.")
                return
            end
            if reason == "" then reason = "Banned by an administrator" end
            insertBan(target, reason, minutes, actorName(ply))
            audit(ply, "ban", target, (minutes == 0 and "Permanent" or (tostring(minutes) .. " minutes")) .. "; " .. reason)
            target:Ban(minutes, true)
            sendNotice(ply, true, minutes == 0 and "Player permanently banned." or "Player banned.")
        elseif action == "warn" then
            local reason = cleanText(net.ReadString(), MAX_REASON)
            if reason == "" then reason = "Please follow the server rules." end
            insertWarning(target, reason, actorName(ply))
            audit(ply, "warning", target, reason)
            if DarkRP and DarkRP.notify then DarkRP.notify(target, 1, 6, "Admin warning: " .. reason)
            else target:ChatPrint("[ServerAdmin] Admin warning: " .. reason) end
            sendNotice(ply, true, "Warning sent.")
        elseif action == "freeze" then
            target:Freeze(true); Frozen[idForPlayer(target)] = true
            audit(ply, "freeze", target); sendNotice(ply, true, "Player frozen.")
        elseif action == "unfreeze" then
            target:Freeze(false); Frozen[idForPlayer(target)] = nil
            audit(ply, "unfreeze", target); sendNotice(ply, true, "Player unfrozen.")
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
            target:SetArmor(100)
            audit(ply, "heal", target); sendNotice(ply, true, "Player healed and armor restored.")
        elseif action == "respawn" then
            target:Spawn(); audit(ply, "respawn", target); sendNotice(ply, true, "Player respawned.")
        elseif action == "mute" or action == "unmute" then
            local id = idForPlayer(target)
            Muted[id] = action == "mute" and true or nil
            if target.SetMuted then target:SetMuted(action == "mute") end
            audit(ply, action, target); sendNotice(ply, true, action == "mute" and "Voice muted." or "Voice unmuted.")
        elseif action == "gag" or action == "ungag" then
            local id = idForPlayer(target)
            Gagged[id] = action == "gag" and true or nil
            audit(ply, action, target); sendNotice(ply, true, action == "gag" and "Chat gag enabled." or "Chat gag removed.")
        elseif action == "god" or action == "ungod" then
            local id = idForPlayer(target)
            GodMode[id] = action == "god" and true or nil
            if action == "god" then target:GodEnable() else target:GodDisable() end
            audit(ply, action, target); sendNotice(ply, true, action == "god" and "God mode enabled." or "God mode disabled.")
        elseif action == "strip" then
            target:StripWeapons(); audit(ply, "strip weapons", target); sendNotice(ply, true, "Weapons stripped.")
        elseif action == "ignite" then
            target:Ignite(10); audit(ply, "ignite", target, "10 seconds"); sendNotice(ply, true, "Player ignited.")
        elseif action == "extinguish" then
            target:Extinguish(); audit(ply, "extinguish", target); sendNotice(ply, true, "Player extinguished.")
        elseif action == "sethealth" then
            local health = math.Clamp(net.ReadUInt(16), 1, 1000)
            target:SetHealth(health); audit(ply, "health set", target, tostring(health)); sendNotice(ply, true, "Health updated.")
        elseif action == "setarmor" then
            local armor = math.Clamp(net.ReadUInt(16), 0, 1000)
            target:SetArmor(armor); audit(ply, "armor set", target, tostring(armor)); sendNotice(ply, true, "Armor updated.")
        elseif action == "setmoney" or action == "addmoney" then
            if not isDarkRP() or not target.addMoney or not target.getDarkRPVar then sendNotice(ply, false, "DarkRP money functions are unavailable."); return end
            local amount = net.ReadInt(32)
            amount = math.Clamp(amount, -2000000000, 2000000000)
            local current = getMoney(target)
            local desired = action == "setmoney" and math.max(0, amount) or math.Clamp(current + amount, 0, 2000000000)
            target:addMoney(desired - current)
            audit(ply, action == "setmoney" and "money set" or "money adjusted", target, "$" .. tostring(current) .. " -> $" .. tostring(desired))
            sendNotice(ply, true, "DarkRP wallet updated.")
        elseif action == "setjob" then
            local jobID = net.ReadUInt(16)
            if not isDarkRP() or not istable(RPExtraTeams) or not RPExtraTeams[jobID] then sendNotice(ply, false, "That DarkRP job does not exist."); return end
            if not target.changeTeam then sendNotice(ply, false, "DarkRP job switching is unavailable."); return end
            local ok, err = pcall(function() target:changeTeam(jobID, true, true) end)
            if not ok then sendNotice(ply, false, "Could not change job: " .. cleanText(err, 120)); return end
            audit(ply, "job changed", target, cleanText(RPExtraTeams[jobID].name or jobID, 64))
            sendNotice(ply, true, "Player job updated.")
        end
    end

    timer.Simple(0.25, function()
        if IsValid(ply) then sendSnapshot(ply) end
    end)
end

net.Receive(NET, function(_, ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local action = net.ReadString()
    if not isstring(action) or #action > 24 then return end
    -- A small server-side cooldown prevents packet spam without delaying normal panel use.
    local now = CurTime()
    if lastRequest[ply] and now - lastRequest[ply] < 0.08 then return end
    lastRequest[ply] = now
    local ok, err = pcall(runAction, ply, action)
    if not ok then
        ErrorNoHalt("[ServerAdmin] Action '" .. cleanText(action, 24) .. "' failed: " .. cleanText(err, 180) .. "\n")
        sendNotice(ply, false, "Action failed. Check the server console for details.")
    end
end)

hook.Add("PlayerSay", "ServerAdmin_ChatGag", function(ply)
    if IsValid(ply) and Gagged[idForPlayer(ply)] then return "" end
end)

hook.Add("PlayerCanHearPlayersVoice", "ServerAdmin_VoiceMute", function(listener, talker)
    if IsValid(talker) and Muted[idForPlayer(talker)] then return false end
end)

local blockedSpawnHooks = {
    "PlayerSpawnProp", "PlayerSpawnSENT", "PlayerSpawnSWEP", "PlayerSpawnNPC",
    "PlayerSpawnVehicle", "PlayerSpawnEffect", "PlayerSpawnRagdoll", "PlayerSpawnObject"
}
for _, hookName in ipairs(blockedSpawnHooks) do
    hook.Add(hookName, "ServerAdmin_BuildLockdown_" .. hookName, function(ply)
        if ServerAdmin.Lockdown and IsValid(ply) and ply:IsPlayer() and not ply:IsAdmin() then return false end
    end)
end

hook.Add("PlayerDisconnected", "ServerAdmin_ClearRuntimeFlags", function(ply)
    local id = idForPlayer(ply)
    Frozen[id], Muted[id], Gagged[id], GodMode[id] = nil, nil, nil, nil
end)

hook.Add("PlayerInitialSpawn", "ServerAdmin_SyncCustomJobs", function(ply)
    timer.Simple(10, function()
        if IsValid(ply) then sendCustomJobSync(ply) end
    end)
end)

hook.Add("PlayerInitialSpawn", "ServerAdmin_AdminHint", function(ply)
    timer.Simple(8, function()
        if IsValid(ply) and ply:IsAdmin() then
            ply:ChatPrint("[ServerAdmin] Admin panel ready. Press F6 or type serveradmin.")
        end
    end)
end)

concommand.Add("serveradmin_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    print("[ServerAdmin] v" .. (ServerAdmin.Version or "3.0.0") .. " loaded.")
end)

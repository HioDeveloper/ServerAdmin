-- ServerAdmin v3: full-screen in-game administration interface.
ServerAdmin = ServerAdmin or {}

local NET = "serveradmin_net"
local C = {
    bg = Color(10, 13, 19), sidebar = Color(16, 20, 29), panel = Color(21, 27, 38),
    panel2 = Color(29, 37, 51), border = Color(48, 60, 80), text = Color(237, 242, 250),
    muted = Color(143, 156, 177), blue = Color(73, 117, 255), green = Color(55, 184, 128),
    red = Color(220, 75, 91), orange = Color(234, 168, 68), cyan = Color(67, 194, 214)
}
local state = {
    hostname = "Loading...", map = "unknown", maxPlayers = 0, gravity = 600, players = {},
    jobs = {}, logs = {}, bans = {}, warnings = {}, cvars = {}, gamemode = "unknown",
    tickrate = 0, uptime = 0, memory = 0, darkrp = false, lockdown = false, bots = 0, entities = 0
}
local frame, playerList, searchEntry, selectedUserID, pages, navButtons
local notice = { text = "", ok = true, untilTime = 0 }
local f6WasDown = false
local activePage = "overview"

local function request(action, writer)
    net.Start(NET)
        net.WriteString(action)
        if writer then writer() end
    net.SendToServer()
end

local function notify(message, ok)
    notice.text = tostring(message or "")
    notice.ok = ok == true
    notice.untilTime = CurTime() + 4
end

local function rounded(x, y, w, h, color, radius)
    draw.RoundedBox(radius or 8, x, y, w, h, color)
end

local function label(parent, text, font, color)
    local item = vgui.Create("DLabel", parent)
    item:SetText(text or "")
    item:SetFont(font or "DermaDefault")
    item:SetTextColor(color or C.text)
    item:SetContentAlignment(4)
    return item
end

local function button(parent, text, color, callback, tall)
    local item = vgui.Create("DButton", parent)
    item:SetText("")
    item:SetTall(tall or 36)
    item.Paint = function(self, w, h)
        local fill = color
        if self:IsHovered() then
            fill = Color(math.min(color.r + 13, 255), math.min(color.g + 13, 255), math.min(color.b + 13, 255))
        end
        rounded(0, 0, w, h, fill, 7)
        draw.SimpleText(text, "DermaDefaultBold", w / 2, h / 2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    item.DoClick = callback
    return item
end

local function selectedPlayer()
    for _, ply in ipairs(state.players) do
        if ply.userid == selectedUserID then return ply end
    end
end

local function sendTargetAction(action, target, extra)
    if not target then notify("Select a player first.", false) return end
    request(action, function()
        net.WriteUInt(target.userid, 16)
        if extra then extra() end
    end)
end

local function refreshPlayerList()
    if not IsValid(playerList) then return end
    playerList:Clear()
    local query = IsValid(searchEntry) and string.lower(searchEntry:GetValue() or "") or ""
    local found = false
    for _, ply in ipairs(state.players) do
        local haystack = string.lower(table.concat({
            ply.name or "", ply.steamid or "", ply.steamid64 or "", ply.team or "", ply.role or ""
        }, " "))
        if query == "" or string.find(haystack, query, 1, true) then
            local line = playerList:AddLine(ply.name, ply.team, "$" .. string.Comma(ply.money or 0),
                tostring(ply.ping), ply.steamid, ply.role)
            line.serveradminUserID = ply.userid
            if selectedUserID == ply.userid then line:SetSelected(true); found = true end
        end
    end
    if not found then selectedUserID = nil end
end

local function addStatCard(parent, titleText, valueFn, accent)
    local card = vgui.Create("DPanel", parent)
    card.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.panel2, 9)
        surface.SetDrawColor(accent)
        surface.DrawRect(0, 0, 3, h)
        draw.SimpleText(string.upper(titleText), "DermaDefaultBold", 14, 24, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(valueFn()), "DermaLarge", 14, 62, accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return card
end

local function addSection(parent, titleText, subtitle)
    local title = label(parent, titleText, "DermaLarge", C.text)
    title:Dock(TOP)
    title:SetTall(36)
    if subtitle then
        local sub = label(parent, subtitle, "DermaDefault", C.muted)
        sub:Dock(TOP)
        sub:SetTall(24)
    end
    return title
end

local function addInput(parent, titleText, initial, placeholder)
    local wrap = vgui.Create("DPanel", parent)
    wrap:Dock(TOP)
    wrap:SetTall(66)
    wrap:DockMargin(0, 4, 0, 6)
    wrap.Paint = nil
    local title = label(wrap, titleText, "DermaDefaultBold", C.muted)
    title:Dock(TOP)
    title:SetTall(22)
    local entry = vgui.Create("DTextEntry", wrap)
    entry:Dock(TOP)
    entry:SetTall(34)
    entry:SetText(tostring(initial or ""))
    if placeholder then entry:SetPlaceholderText(placeholder) end
    return entry
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds / 3600) % 24
    local minutes = math.floor(seconds / 60) % 60
    if days > 0 then return days .. "d " .. hours .. "h" end
    if hours > 0 then return hours .. "h " .. minutes .. "m" end
    return minutes .. "m"
end

local function buildPanel()
    if IsValid(frame) then frame:Remove() end
    frame = vgui.Create("DFrame")
    frame:SetSize(ScrW(), ScrH())
    frame:SetPos(0, 0)
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:MakePopup()
    frame:SetKeyboardInputEnabled(true)
    frame.Paint = function(self, w, h)
        surface.SetDrawColor(C.bg)
        surface.DrawRect(0, 0, w, h)
        draw.SimpleText("SERVERADMIN", "DermaLarge", 28, 30, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("SERVER CONTROL CENTER  /  v" .. (ServerAdmin.Version or "3.0.0"), "DermaDefault",
            218, 32, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if CurTime() < notice.untilTime then
            draw.SimpleText(notice.text, "DermaDefaultBold", w - 142, 32,
                notice.ok and C.green or C.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        surface.SetDrawColor(C.border)
        surface.DrawRect(0, 61, w, 1)
    end

    local close = button(frame, "CLOSE  X", C.panel2, function() frame:Close() end, 34)
    close:SetSize(100, 34)
    close:SetPos(ScrW() - 122, 14)

    local sidebar = vgui.Create("DPanel", frame)
    sidebar:SetPos(16, 78)
    sidebar:SetSize(220, ScrH() - 94)
    sidebar.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.sidebar, 10)
        draw.SimpleText("WORKSPACE", "DermaDefaultBold", 16, 20, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(C.border); surface.DrawRect(14, 39, w - 28, 1)
        draw.SimpleText(string.sub(state.hostname or "Server", 1, 25), "DermaDefaultBold", 16, h - 49, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(state.map .. "  /  " .. #state.players .. " players", "DermaDefault", 16, h - 28, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if state.lockdown then
            draw.SimpleText("BUILD LOCKDOWN", "DermaDefaultBold", w - 12, 20, C.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    local content = vgui.Create("DPanel", frame)
    content:SetPos(250, 78)
    content:SetSize(ScrW() - 266, ScrH() - 94)
    content.Paint = function(self, w, h) rounded(0, 0, w, h, C.panel, 10) end

    pages, navButtons = {}, {}
    local function showPage(key)
        activePage = key
        for name, page in pairs(pages) do if IsValid(page) then page:SetVisible(name == key) end end
        for name, nav in pairs(navButtons) do if IsValid(nav) then nav.serveradminActive = name == key end end
        if key == "players" or key == "logs" or key == "bans" or key == "darkrp" or key == "server" then request("refresh") end
    end
    local function addNav(text, key, y)
        local nav = vgui.Create("DButton", sidebar)
        nav:SetText("")
        nav:SetPos(10, y)
        nav:SetSize(200, 40)
        nav.Paint = function(self, w, h)
            local fill = self.serveradminActive and C.blue or (self:IsHovered() and C.panel2 or C.sidebar)
            rounded(0, 0, w, h, fill, 7)
            if self.serveradminActive then surface.SetDrawColor(C.cyan); surface.DrawRect(0, 8, 3, h - 16) end
            draw.SimpleText(text, "DermaDefaultBold", 14, h / 2, self.serveradminActive and color_white or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        nav.DoClick = function() showPage(key) end
        navButtons[key] = nav
    end

    local function makePage(key)
        local page = vgui.Create("DPanel", content)
        page:Dock(FILL)
        page:DockMargin(20, 18, 20, 18)
        page.Paint = nil
        pages[key] = page
        return page
    end

    addNav("Overview", "overview", 54)
    addNav("Players & moderation", "players", 100)
    addNav("DarkRP jobs & economy", "darkrp", 146)
    addNav("Bans & warnings", "bans", 192)
    addNav("Audit logs", "logs", 238)
    addNav("Server settings", "settings", 284)
    addNav("Server controls", "server", 330)
    addNav("Diagnostics", "diagnostics", 376)

    -- Dashboard
    local overview = makePage("overview")
    addSection(overview, "Server overview", "Live status, connected players and operational statistics.")
    local cards = vgui.Create("DPanel", overview)
    cards:Dock(TOP); cards:SetTall(105); cards:DockMargin(0, 10, 0, 18); cards.Paint = nil
    local cardDefs = {
        {"PLAYERS ONLINE", function() return #state.players .. " / " .. state.maxPlayers end, C.green},
        {"CURRENT MAP", function() return state.map end, C.cyan},
        {"SERVER TICKRATE", function() return math.floor(state.tickrate + 0.5) .. " TPS" end, C.blue},
        {"UPTIME", function()
            local s = math.max(0, math.floor(state.uptime))
            return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
        end, C.orange}
    }
    local statCards = {}
    for _, def in ipairs(cardDefs) do statCards[#statCards + 1] = addStatCard(cards, def[1], def[2], def[3]) end
    cards.PerformLayout = function(self, w, h)
        local gap = 10; local cw = (w - gap * (#statCards - 1)) / #statCards
        for i, card in ipairs(statCards) do card:SetPos((i - 1) * (cw + gap), 0); card:SetSize(cw, h) end
    end

    local status = vgui.Create("DPanel", overview)
    status:Dock(TOP); status:SetTall(170); status:DockMargin(0, 0, 0, 14)
    status.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.panel2, 9)
        draw.SimpleText("SERVER STATUS", "DermaDefaultBold", 16, 22, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local lines = {
            {"Hostname", state.hostname},
            {"Gamemode", state.gamemode .. (state.darkrp and "  /  DarkRP detected" or "")},
            {"Gravity", tostring(math.floor(state.gravity))},
            {"Lua memory estimate", string.format("%.1f MB", state.memory)},
            {"Bots / entities", tostring(state.bots) .. " bots  /  " .. tostring(state.entities) .. " entities"}
        }
        for i, pair in ipairs(lines) do
            local y = 49 + (i - 1) * 25
            draw.SimpleText(pair[1], "DermaDefault", 16, y, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(tostring(pair[2]), "DermaDefaultBold", 170, y, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    local onlineTitle = label(overview, "Connected players", "DermaDefaultBold", C.text)
    onlineTitle:Dock(TOP); onlineTitle:SetTall(28)
    local online = vgui.Create("DListView", overview)
    online:Dock(FILL)
    online:AddColumn("Player"):SetFixedWidth(220)
    online:AddColumn("Job / team"):SetFixedWidth(210)
    online:AddColumn("Money"):SetFixedWidth(110)
    online:AddColumn("Ping")
    online:SetDataHeight(25)
    online.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end
    online.Think = function(self)
        if self.serveradminRefresh and self.serveradminRefresh > CurTime() then return end
        self.serveradminRefresh = CurTime() + 2
        local signature = tostring(#state.players)
        for _, p in ipairs(state.players) do
            signature = signature .. "|" .. tostring(p.userid) .. ":" .. tostring(p.name) .. ":" .. tostring(p.team) .. ":" .. tostring(p.money) .. ":" .. tostring(p.ping)
        end
        if self.serveradminSignature == signature then return end
        self.serveradminSignature = signature
        self:Clear()
        for _, p in ipairs(state.players) do self:AddLine(p.name, p.team, "$" .. string.Comma(p.money or 0), p.ping) end
    end
    local refresh = button(overview, "Refresh data", C.blue, function() request("refresh") end)
    refresh:Dock(BOTTOM); refresh:DockMargin(0, 10, 0, 0); refresh:SetWide(140)

    -- Player management and moderation actions
    local playersPage = makePage("players")
    addSection(playersPage, "Players & moderation", "Choose a connected player. The server checks permissions again for every action.")
    searchEntry = vgui.Create("DTextEntry", playersPage)
    searchEntry:Dock(TOP); searchEntry:DockMargin(0, 8, 0, 10); searchEntry:SetTall(34)
    searchEntry:SetPlaceholderText("Search name, SteamID, SteamID64, job or rank...")
    searchEntry:SetUpdateOnType(true)
    searchEntry.OnValueChange = refreshPlayerList
    playerList = vgui.Create("DListView", playersPage)
    playerList:Dock(FILL)
    playerList:AddColumn("Player"):SetFixedWidth(175)
    playerList:AddColumn("Job / team"):SetFixedWidth(135)
    playerList:AddColumn("Money"):SetFixedWidth(88)
    playerList:AddColumn("Ping"):SetFixedWidth(48)
    playerList:AddColumn("SteamID"):SetFixedWidth(135)
    playerList:AddColumn("Rank")
    playerList:SetMultiSelect(false); playerList:SetDataHeight(24)
    playerList.OnRowSelected = function(_, _, line) selectedUserID = line.serveradminUserID end
    playerList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end

    local actionBar = vgui.Create("DPanel", playersPage)
    actionBar:Dock(BOTTOM); actionBar:SetTall(158); actionBar:DockMargin(0, 10, 0, 0); actionBar.Paint = nil
    local function actionButton(text, x, y, w, color, fn)
        local b = button(actionBar, text, color, fn, 32); b:SetPos(x, y); b:SetSize(w, 32); return b
    end
    actionButton("Kick", 0, 0, 78, C.red, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Kick player", "Reason:", "Kicked by an administrator", function(reason)
            sendTargetAction("kick", p, function() net.WriteString(reason or "") end)
        end)
    end)
    actionButton("Ban", 84, 0, 78, C.red, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Ban player", "Duration in minutes (0 = permanent):", "60", function(duration)
            local n = tonumber(duration); if not n or n < 0 or n > 65535 then notify("Enter a duration from 0 to 65535 minutes.", false) return end
            Derma_StringRequest("Ban player", "Reason:", "Banned by an administrator", function(reason)
                sendTargetAction("ban", p, function() net.WriteUInt(math.floor(n), 16); net.WriteString(reason or "") end)
            end)
        end)
    end)
    actionButton("Warn", 168, 0, 78, C.orange, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Warn player", "Warning reason:", "Please follow the server rules", function(reason)
            sendTargetAction("warn", p, function() net.WriteString(reason or "") end)
        end)
    end)
    local quick = {
        {"Bring", "bring", C.blue}, {"Goto", "goto", C.blue}, {"Freeze", "freeze", C.orange},
        {"Unfreeze", "unfreeze", C.panel2}, {"Heal", "heal", C.green}, {"Respawn", "respawn", C.cyan},
        {"Slay", "slay", C.red}
    }
    for i, spec in ipairs(quick) do
        local x = ((i - 1) % 7) * 90
        actionButton(spec[1], x, 38, 82, spec[3], function()
            local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
            if spec[2] == "slay" or spec[2] == "respawn" then
                Derma_Query("Confirm " .. spec[1]:lower() .. " for " .. p.name .. "?", "Confirm action",
                    spec[1], function() sendTargetAction(spec[2], p) end, "Cancel")
            else sendTargetAction(spec[2], p) end
        end)
    end
    actionButton("Set money", 0, 76, 104, C.green, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Set player money", "New amount:", tostring(p.money or 0), function(value)
            local n = tonumber(value); if not n then notify("Enter a valid amount.", false) return end
            sendTargetAction("setmoney", p, function() net.WriteInt(math.Clamp(math.floor(n), 0, 2000000000), 32) end)
        end)
    end)
    actionButton("Add money", 110, 76, 104, C.green, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Adjust player money", "Amount to add (negative removes money):", "100", function(value)
            local n = tonumber(value); if not n then notify("Enter a valid amount.", false) return end
            sendTargetAction("addmoney", p, function() net.WriteInt(math.Clamp(math.floor(n), -2000000000, 2000000000), 32) end)
        end)
    end)
    actionButton("Toggle voice mute", 220, 76, 136, C.orange, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        sendTargetAction(p.muted and "unmute" or "mute", p)
    end)
    actionButton("Toggle chat gag", 362, 76, 128, C.orange, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        sendTargetAction(p.gagged and "ungag" or "gag", p)
    end)
    actionButton("Toggle god mode", 496, 76, 128, C.blue, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        sendTargetAction(p.god and "ungod" or "god", p)
    end)
    actionButton("Strip weapons", 0, 114, 104, C.panel2, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_Query("Remove all weapons from " .. p.name .. "?", "Confirm action", "Strip", function() sendTargetAction("strip", p) end, "Cancel")
    end)
    actionButton("Ignite", 110, 114, 88, C.red, function()
        local p = selectedPlayer(); if p then sendTargetAction("ignite", p) else notify("Select a player first.", false) end
    end)
    actionButton("Extinguish", 204, 114, 98, C.blue, function()
        local p = selectedPlayer(); if p then sendTargetAction("extinguish", p) else notify("Select a player first.", false) end
    end)
    actionButton("Set health", 308, 114, 100, C.green, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Set health", "Health (1–1000):", tostring(p.health or 100), function(value)
            local n = tonumber(value); if not n or n < 1 or n > 1000 then notify("Enter health from 1 to 1000.", false) return end
            sendTargetAction("sethealth", p, function() net.WriteUInt(math.floor(n), 16) end)
        end)
    end)
    actionButton("Set armor", 414, 114, 100, C.green, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Set armor", "Armor (0–1000):", tostring(p.armor or 0), function(value)
            local n = tonumber(value); if not n or n < 0 or n > 1000 then notify("Enter armor from 0 to 1000.", false) return end
            sendTargetAction("setarmor", p, function() net.WriteUInt(math.floor(n), 16) end)
        end)
    end)

    -- DarkRP job and wallet tools
    local darkrpPage = makePage("darkrp")
    addSection(darkrpPage, "DarkRP jobs & economy", "Registered jobs, salaries and per-player wallet adjustments.")
    local rpNotice = label(darkrpPage, "", "DermaDefaultBold", C.orange)
    rpNotice:Dock(TOP); rpNotice:SetTall(26)
    rpNotice.Think = function(self)
        self:SetText(state.darkrp and ("DarkRP detected  /  " .. #state.jobs .. " registered jobs") or "DarkRP was not detected. Generic server tools remain available.")
    end
    local selectedJob
    local jobList = vgui.Create("DListView", darkrpPage)
    jobList:Dock(FILL); jobList:DockMargin(0, 8, 0, 8)
    jobList:AddColumn("Job"):SetFixedWidth(240)
    jobList:AddColumn("Command"):SetFixedWidth(120)
    jobList:AddColumn("Salary")
    jobList:SetDataHeight(25)
    jobList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end
    jobList.OnRowSelected = function(_, _, line) selectedJob = line.serveradminJobID end
    jobList.Think = function(self)
        local signature = ""
        for _, job in ipairs(state.jobs) do signature = signature .. "|" .. job.id .. ":" .. job.name .. ":" .. job.command .. ":" .. job.salary end
        if self.serveradminJobsSignature == signature then return end
        self.serveradminJobsSignature = signature
        self:Clear()
        for _, job in ipairs(state.jobs) do
            local line = self:AddLine(job.name, job.command, "$" .. tostring(job.salary))
            line.serveradminJobID = job.id
        end
    end
    local jobActions = vgui.Create("DPanel", darkrpPage)
    jobActions:Dock(BOTTOM); jobActions:SetTall(80); jobActions.Paint = nil
    local jobTarget = button(jobActions, "Set selected player's job", C.blue, function()
        local p = selectedPlayer()
        if not p then notify("Select a player on the Players page first.", false) return end
        if not selectedJob then notify("Select a job first.", false) return end
        sendTargetAction("setjob", p, function() net.WriteUInt(selectedJob, 16) end)
    end)
    jobTarget:Dock(LEFT); jobTarget:SetWide(230); jobTarget:DockMargin(0, 8, 10, 0)
    local moneyHint = label(jobActions, "Money controls are available on Players & moderation. Economy changes require superadmin.", "DermaDefault", C.muted)
    moneyHint:Dock(FILL); moneyHint:DockMargin(4, 8, 0, 0)

    -- Separate persistent bans and warning histories
    local bansPage = makePage("bans")
    addSection(bansPage, "Bans & warnings", "Moderation records persist in the server SQLite database. Select an active ban to unban.")
    local moderationSheet = vgui.Create("DPropertySheet", bansPage)
    moderationSheet:Dock(FILL); moderationSheet:DockMargin(0, 8, 0, 0)
    local bansTab = vgui.Create("DPanel", moderationSheet); bansTab:Dock(FILL); bansTab.Paint = nil
    local banList = vgui.Create("DListView", bansTab)
    banList:Dock(FILL); banList:DockMargin(0, 0, 0, 8)
    banList:AddColumn("Status"):SetFixedWidth(75)
    banList:AddColumn("Player"):SetFixedWidth(155)
    banList:AddColumn("SteamID"):SetFixedWidth(135)
    banList:AddColumn("Reason"):SetFixedWidth(210)
    banList:AddColumn("By"):SetFixedWidth(140)
    banList:AddColumn("Expires")
    banList:SetDataHeight(24)
    banList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end
    local selectedBanID
    banList.OnRowSelected = function(_, _, line) selectedBanID = line.serveradminBanID end
    banList.Think = function(self)
        local signature = ""
        for _, b in ipairs(state.bans) do signature = signature .. "|" .. b.id .. ":" .. b.active .. ":" .. b.steamid .. ":" .. b.reason .. ":" .. b.expires end
        if self.serveradminBansSignature == signature then return end
        self.serveradminBansSignature = signature
        self:Clear()
        for _, b in ipairs(state.bans) do
            local active = b.active and not (b.expires > 0 and b.expires <= os.time())
            local expires = not active and "—" or (b.expires == 0 and "Permanent" or os.date("%Y-%m-%d %H:%M", b.expires))
            local line = self:AddLine(active and "ACTIVE" or "Expired", b.name, b.steamid, b.reason, b.actor, expires)
            line.serveradminBanID = b.id
        end
    end
    local banButtons = vgui.Create("DPanel", bansTab)
    banButtons:Dock(BOTTOM); banButtons:SetTall(42); banButtons.Paint = nil
    local unbanButton = button(banButtons, "Unban selected", C.red, function()
        if not selectedBanID then notify("Select a ban record first.", false) return end
        Derma_Query("Unban the SteamID attached to this record?", "Confirm unban", "Unban", function()
            request("unban", function() net.WriteUInt(selectedBanID, 32) end)
        end, "Cancel")
    end)
    unbanButton:Dock(LEFT); unbanButton:SetWide(150)
    local refreshBans = button(banButtons, "Refresh", C.blue, function() request("refresh") end)
    refreshBans:Dock(LEFT); refreshBans:SetWide(110); refreshBans:DockMargin(8, 0, 0, 0)
    moderationSheet:AddSheet("Bans", bansTab, "icon16/lock.png")

    local warningsTab = vgui.Create("DPanel", moderationSheet); warningsTab:Dock(FILL); warningsTab.Paint = nil
    local warningList = vgui.Create("DListView", warningsTab)
    warningList:Dock(FILL)
    warningList:AddColumn("Date"):SetFixedWidth(145)
    warningList:AddColumn("Player"):SetFixedWidth(160)
    warningList:AddColumn("SteamID"):SetFixedWidth(140)
    warningList:AddColumn("Warning"):SetFixedWidth(250)
    warningList:AddColumn("Administrator")
    warningList:SetDataHeight(24)
    warningList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end
    warningList.Think = function(self)
        local signature = ""
        for _, item in ipairs(state.warnings) do signature = signature .. "|" .. item.id .. ":" .. item.steamid .. ":" .. item.reason end
        if self.serveradminWarningsSignature == signature then return end
        self.serveradminWarningsSignature = signature
        self:Clear()
        for _, item in ipairs(state.warnings) do self:AddLine(item.created, item.name, item.steamid, item.reason, item.actor) end
    end
    moderationSheet:AddSheet("Warnings", warningsTab, "icon16/error.png")

    -- Audit log
    local logsPage = makePage("logs")
    addSection(logsPage, "Audit logs", "Server-side records of actions and configuration changes.")
    local logsRefresh = button(logsPage, "Refresh logs", C.blue, function() request("refresh") end)
    logsRefresh:Dock(TOP); logsRefresh:DockMargin(0, 8, 0, 10); logsRefresh:SetWide(130)
    local logList = vgui.Create("DListView", logsPage)
    logList:Dock(FILL)
    logList:AddColumn("Time"):SetFixedWidth(150)
    logList:AddColumn("Administrator"):SetFixedWidth(180)
    logList:AddColumn("Action"):SetFixedWidth(135)
    logList:AddColumn("Target"):SetFixedWidth(170)
    logList:AddColumn("Details")
    logList:SetDataHeight(25)
    logList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end
    logList.Think = function(self)
        local signature = ""
        for _, item in ipairs(state.logs) do signature = signature .. "|" .. item.time .. ":" .. item.actor .. ":" .. item.action .. ":" .. item.target .. ":" .. item.detail end
        if self.serveradminLogSignature == signature then return end
        self.serveradminLogSignature = signature
        self:Clear()
        for _, item in ipairs(state.logs) do self:AddLine(item.time, item.actor, item.action, item.target, item.detail) end
    end

    -- Basic server configuration, with input validation performed server-side as well.
    local settings = makePage("settings")
    addSection(settings, "Server settings", "Common live settings. Sensitive changes are restricted to superadmins.")
    local hostEntry = addInput(settings, "Server hostname", state.hostname, "Enter hostname")
    local saveHost = button(settings, "Save hostname", C.blue, function()
        request("hostname", function() net.WriteString(hostEntry:GetValue() or "") end)
    end)
    saveHost:Dock(TOP); saveHost:DockMargin(0, 0, 0, 10); saveHost:SetWide(180)
    local gravityEntry = addInput(settings, "Gravity (0–2000)", state.gravity, "600")
    local saveGravity = button(settings, "Apply gravity", C.blue, function()
        local n = tonumber(gravityEntry:GetValue()); if not n then notify("Gravity must be numeric.", false) return end
        request("gravity", function() net.WriteFloat(n) end)
    end)
    saveGravity:Dock(TOP); saveGravity:DockMargin(0, 0, 0, 10); saveGravity:SetWide(180)
    local mapEntry = addInput(settings, "Change map (map name, without .bsp)", state.map, "gm_flatgrass")
    local changeMap = button(settings, "Change map", C.red, function()
        local mapName = string.Trim(mapEntry:GetValue() or "")
        if mapName == "" then notify("Enter a map name.", false) return end
        Derma_Query("Change map to " .. mapName .. "? Everyone will reconnect.", "Confirm map change",
            "Change map", function() request("map", function() net.WriteString(mapName) end) end, "Cancel")
    end)
    changeMap:Dock(TOP); changeMap:DockMargin(0, 0, 0, 10); changeMap:SetWide(180)
    local settingsHint = label(settings, "More granular server variables, bot controls, announcements and build lockdown are under Server controls.", "DermaDefault", C.muted)
    settingsHint:Dock(TOP); settingsHint:SetTall(28)

    -- Bots, allow-listed cvars, announcements and operational tools
    local serverPage = makePage("server")
    addSection(serverPage, "Server controls", "Only explicitly supported server variables can be changed here; arbitrary console commands are never accepted.")
    local botPanel = vgui.Create("DPanel", serverPage)
    botPanel:Dock(TOP); botPanel:SetTall(112); botPanel:DockMargin(0, 8, 0, 12)
    botPanel.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.panel2, 9)
        draw.SimpleText("BOT MANAGEMENT", "DermaDefaultBold", 14, 18, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(state.bots) .. " bot(s) online  /  " .. tostring(state.maxPlayers - #state.players) .. " open slot(s)", "DermaDefault", 14, 42, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local addBots = button(botPanel, "Add bots", C.green, function()
        Derma_StringRequest("Add bots", "Number of bots (1–10):", "1", function(value)
            local n = tonumber(value)
            if not n or n < 1 or n > 10 then notify("Enter a number from 1 to 10.", false) return end
            request("botadd", function() net.WriteUInt(math.floor(n), 4) end)
        end)
    end)
    addBots:SetPos(14, 60); addBots:SetSize(120, 34)
    local removeBots = button(botPanel, "Kick all bots", C.red, function()
        Derma_Query("Kick every bot currently connected?", "Confirm bot removal", "Kick bots", function() request("botkickall") end, "Cancel")
    end)
    removeBots:SetPos(142, 60); removeBots:SetSize(140, 34)
    local cleanup = button(botPanel, "Clean up map", C.orange, function()
        Derma_Query("Clean up map-spawned entities? This can remove props and other spawned objects.", "Confirm map cleanup",
            "Clean up", function() request("cleanup") end, "Cancel")
    end)
    cleanup:SetPos(290, 60); cleanup:SetSize(140, 34)
    local lockdownButton = button(botPanel, "Toggle build lockdown", C.red, function()
        Derma_Query("Toggle build lockdown for non-admin players?", "Confirm build lockdown",
            "Toggle", function() request("lockdown", function() net.WriteBool(not state.lockdown) end) end, "Cancel")
    end)
    lockdownButton:SetPos(438, 60); lockdownButton:SetSize(190, 34)

    local announceEntry = addInput(serverPage, "Broadcast announcement", "", "Message to display in all players' chat")
    local announceButton = button(serverPage, "Send announcement", C.blue, function()
        local message = string.Trim(announceEntry:GetValue() or "")
        if message == "" then notify("Enter an announcement first.", false) return end
        Derma_Query("Send this message to every connected player?", "Confirm announcement",
            "Send", function() request("announce", function() net.WriteString(message) end) end, "Cancel")
    end)
    announceButton:Dock(TOP); announceButton:DockMargin(0, 0, 0, 10); announceButton:SetWide(200)

    local cvarTitle = label(serverPage, "Allow-listed server variables", "DermaDefaultBold", C.text)
    cvarTitle:Dock(TOP); cvarTitle:SetTall(28)
    local cvarList = vgui.Create("DListView", serverPage)
    cvarList:Dock(FILL); cvarList:DockMargin(0, 0, 0, 8)
    cvarList:AddColumn("Variable"):SetFixedWidth(230)
    cvarList:AddColumn("Current value"):SetFixedWidth(180)
    cvarList:AddColumn("Type")
    cvarList:SetDataHeight(22)
    cvarList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end
    local selectedCvar
    cvarList.OnRowSelected = function(_, _, line)
        selectedCvar = line.serveradminCVar
        for _, cv in ipairs(state.cvars) do
            if cv.name == selectedCvar then
                if IsValid(cvarEntry) then cvarEntry:SetText(cv.kind == "secret" and "" or (cv.value == "unavailable" and "" or cv.value)) end
                if IsValid(cvarHint) then
                    cvarHint:SetText(cv.kind == "secret" and "Password is never sent to the client. Leave empty to clear it." or
                        (cv.kind == "bool" and "Use 0 or 1." or "Numeric values are range-checked on the server."))
                end
                break
            end
        end
    end
    cvarList.Think = function(self)
        local signature = ""
        for _, cv in ipairs(state.cvars) do signature = signature .. "|" .. cv.name .. ":" .. cv.value .. ":" .. cv.kind end
        if self.serveradminCvarSignature == signature then return end
        self.serveradminCvarSignature = signature
        self:Clear()
        for _, cv in ipairs(state.cvars) do
            local line = self:AddLine(cv.name, cv.value, cv.kind)
            line.serveradminCVar = cv.name
        end
    end
    local cvarEntry = addInput(serverPage, "New value for selected variable", "", "Select a variable above")
    local cvarHint = label(serverPage, "Select an item to edit it. Secret values are never disclosed.", "DermaDefault", C.muted)
    cvarHint:Dock(TOP); cvarHint:SetTall(24)
    local saveCvar = button(serverPage, "Apply selected variable", C.blue, function()
        if not selectedCvar then notify("Select a server variable first.", false) return end
        request("setcvar", function() net.WriteString(selectedCvar); net.WriteString(cvarEntry:GetValue() or "") end)
    end)
    saveCvar:Dock(TOP); saveCvar:DockMargin(0, 0, 0, 4); saveCvar:SetWide(220)

    -- Diagnostics
    local diagnostics = makePage("diagnostics")
    addSection(diagnostics, "Diagnostics", "Only metrics exposed by the game engine or Lua runtime are shown; values are not fabricated.")
    local diag = vgui.Create("DPanel", diagnostics)
    diag:Dock(TOP); diag:SetTall(250); diag:DockMargin(0, 10, 0, 14)
    diag.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.panel2, 9)
        local lines = {
            {"Gamemode", state.gamemode},
            {"DarkRP integration", state.darkrp and "Available" or "Not detected"},
            {"Tickrate estimate", string.format("%.1f ticks/sec", state.tickrate)},
            {"Lua memory estimate", string.format("%.1f MB (collectgarbage)", state.memory)},
            {"Connected players", tostring(#state.players) .. " / " .. tostring(state.maxPlayers)},
            {"Bots / entities", tostring(state.bots) .. " / " .. tostring(state.entities)},
            {"Current map", state.map},
            {"Server uptime since module load", formatDuration(state.uptime)},
            {"Build lockdown", state.lockdown and "Enabled" or "Disabled"},
            {"Recent audit entries", tostring(#state.logs)}
        }
        for i, pair in ipairs(lines) do
            local y = 18 + (i - 1) * 23
            draw.SimpleText(pair[1], "DermaDefault", 16, y, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(tostring(pair[2]), "DermaDefaultBold", 230, y, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    local diagRefresh = button(diagnostics, "Refresh diagnostics", C.blue, function() request("refresh") end)
    diagRefresh:Dock(TOP); diagRefresh:SetWide(190)

    showPage(activePage or "overview")
    request("refresh")
end

net.Receive(NET, function()
    local kind = net.ReadString()
    if kind == "notice" then
        notify(net.ReadString(), net.ReadBool())
        return
    end
    if kind ~= "snapshot" then return end

    state.hostname = net.ReadString()
    state.map = net.ReadString()
    state.maxPlayers = net.ReadUInt(8)
    state.gravity = net.ReadFloat()
    state.gamemode = net.ReadString()
    state.tickrate = net.ReadFloat()
    state.uptime = net.ReadFloat()
    state.memory = net.ReadFloat()
    state.darkrp = net.ReadBool()
    local count = net.ReadUInt(8)
    state.players = {}
    for i = 1, count do
        local p = {
            userid = net.ReadUInt(16), name = net.ReadString(), steamid = net.ReadString(),
            ping = net.ReadUInt(16), team = net.ReadString(), admin = net.ReadBool(),
            superadmin = net.ReadBool(), alive = net.ReadBool(), money = net.ReadInt(32),
            health = net.ReadUInt(8), armor = net.ReadUInt(8), role = net.ReadString(), jobid = net.ReadUInt(16)
        }
        p.steamid64 = net.ReadString()
        p.frags = net.ReadInt(16)
        p.deaths = net.ReadInt(16)
        p.weapons = net.ReadUInt(8)
        p.muted = net.ReadBool()
        p.gagged = net.ReadBool()
        p.frozen = net.ReadBool()
        p.god = net.ReadBool()
        state.players[#state.players + 1] = p
    end

    local jobCount = net.ReadUInt(10)
    state.jobs = {}
    for i = 1, jobCount do
        state.jobs[#state.jobs + 1] = {
            id = net.ReadUInt(16), name = net.ReadString(), command = net.ReadString(), salary = net.ReadInt(32)
        }
    end
    local logCount = net.ReadUInt(7)
    state.logs = {}
    for i = 1, logCount do
        state.logs[#state.logs + 1] = {
            time = net.ReadString(), actor = net.ReadString(), action = net.ReadString(),
            target = net.ReadString(), detail = net.ReadString()
        }
    end

    local banCount = net.ReadUInt(6)
    state.bans = {}
    for i = 1, banCount do
        state.bans[#state.bans + 1] = {
            id = net.ReadUInt(32), steamid = net.ReadString(), name = net.ReadString(),
            reason = net.ReadString(), actor = net.ReadString(), created = net.ReadString(),
            expires = net.ReadInt(32), active = net.ReadBool()
        }
    end
    local warningCount = net.ReadUInt(6)
    state.warnings = {}
    for i = 1, warningCount do
        state.warnings[#state.warnings + 1] = {
            id = net.ReadUInt(32), steamid = net.ReadString(), name = net.ReadString(),
            reason = net.ReadString(), actor = net.ReadString(), created = net.ReadString()
        }
    end
    local cvarCount = net.ReadUInt(6)
    state.cvars = {}
    for i = 1, cvarCount do
        state.cvars[#state.cvars + 1] = { name = net.ReadString(), value = net.ReadString(), kind = net.ReadString() }
    end
    state.lockdown = net.ReadBool()
    state.bots = net.ReadUInt(8)
    state.entities = net.ReadUInt(16)

    refreshPlayerList()
end)

local function openPanel()
    if not LocalPlayer():IsAdmin() then
        notify("You do not have permission to use ServerAdmin.", false)
        return
    end
    buildPanel()
end

concommand.Add("serveradmin", openPanel)
hook.Add("Think", "ServerAdmin_F6", function()
    if not IsValid(LocalPlayer()) then return end
    local down = input.IsKeyDown(KEY_F6)
    if down and not f6WasDown and not vgui.CursorVisible() then openPanel() end
    f6WasDown = down
end)

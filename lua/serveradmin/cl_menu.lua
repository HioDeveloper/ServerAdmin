-- ServerAdmin: fullscreen DarkRP administration UI
ServerAdmin = ServerAdmin or {}

local NET = "serveradmin_net"
local C = {
    bg = Color(12, 15, 21), sidebar = Color(17, 21, 29), panel = Color(22, 27, 37),
    panel2 = Color(29, 36, 48), border = Color(48, 58, 75), text = Color(235, 240, 248),
    muted = Color(139, 151, 171), blue = Color(75, 119, 255), green = Color(56, 181, 127),
    red = Color(218, 76, 91), orange = Color(231, 164, 68), cyan = Color(63, 188, 207)
}
local state = {
    hostname = "Loading...", map = "unknown", maxPlayers = 0, gravity = 600, players = {},
    jobs = {}, logs = {}, gamemode = "unknown", tickrate = 0, uptime = 0, memory = 0, darkrp = false
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
            ply.name or "", ply.steamid or "", ply.team or "", ply.role or ""
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
        draw.SimpleText("DARKRP CONTROL CENTER  /  v" .. (ServerAdmin.Version or "2.0.0"), "DermaDefault",
            218, 32, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if CurTime() < notice.untilTime then
            draw.SimpleText(notice.text, "DermaDefaultBold", w - 70, 32,
                notice.ok and C.green or C.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        surface.SetDrawColor(C.border)
        surface.DrawRect(0, 61, w, 1)
    end

    local close = button(frame, "CLOSE  ✕", C.panel2, function() frame:Close() end, 34)
    close:SetSize(100, 34)
    close:SetPos(ScrW() - 122, 14)

    local sidebar = vgui.Create("DPanel", frame)
    sidebar:SetPos(16, 78)
    sidebar:SetSize(220, ScrH() - 94)
    sidebar.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.sidebar, 10)
        draw.SimpleText("WORKSPACE", "DermaDefaultBold", 16, 20, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(C.border); surface.DrawRect(14, 39, w - 28, 1)
        draw.SimpleText(state.hostname, "DermaDefaultBold", 16, h - 49, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(state.map .. "  •  " .. #state.players .. " players", "DermaDefault", 16, h - 28, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
        if key == "players" then request("refresh") end
        if key == "logs" then request("refresh") end
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
    addNav("Audit logs", "logs", 192)
    addNav("Server settings", "settings", 238)
    addNav("Diagnostics", "diagnostics", 284)

    -- Overview page
    local overview = makePage("overview")
    addSection(overview, "Server overview", "Live status and operational statistics")
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
        draw.SimpleText("Hostname", "DermaDefault", 16, 55, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(state.hostname, "DermaDefaultBold", 170, 55, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Gamemode", "DermaDefault", 16, 84, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(state.gamemode .. (state.darkrp and "  •  DarkRP detected" or ""), "DermaDefaultBold", 170, 84, state.darkrp and C.green or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Gravity", "DermaDefault", 16, 113, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(math.floor(state.gravity)), "DermaDefaultBold", 170, 113, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Lua memory estimate", "DermaDefault", 16, 142, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("%.1f MB", state.memory), "DermaDefaultBold", 170, 142, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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

    -- Players page
    local playersPage = makePage("players")
    addSection(playersPage, "Players & moderation", "Select a player to manage their session. Every action is permission-checked server-side.")
    searchEntry = vgui.Create("DTextEntry", playersPage)
    searchEntry:Dock(TOP); searchEntry:DockMargin(0, 8, 0, 10); searchEntry:SetTall(34)
    searchEntry:SetPlaceholderText("Search name, SteamID, job or role...")
    searchEntry:SetUpdateOnType(true)
    searchEntry.OnValueChange = refreshPlayerList
    playerList = vgui.Create("DListView", playersPage)
    playerList:Dock(FILL)
    playerList:AddColumn("Player"):SetFixedWidth(190)
    playerList:AddColumn("Job / team"):SetFixedWidth(155)
    playerList:AddColumn("Money"):SetFixedWidth(95)
    playerList:AddColumn("Ping"):SetFixedWidth(55)
    playerList:AddColumn("SteamID"):SetFixedWidth(145)
    playerList:AddColumn("Rank")
    playerList:SetMultiSelect(false); playerList:SetDataHeight(25)
    playerList.OnRowSelected = function(_, _, line) selectedUserID = line.serveradminUserID end
    playerList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end

    local actionBar = vgui.Create("DPanel", playersPage)
    actionBar:Dock(BOTTOM); actionBar:SetTall(122); actionBar:DockMargin(0, 10, 0, 0); actionBar.Paint = nil
    local function actionButton(text, x, y, w, color, fn)
        local b = button(actionBar, text, color, fn, 32); b:SetPos(x, y); b:SetSize(w, 32); return b
    end
    actionButton("Kick", 0, 0, 82, C.red, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Kick player", "Reason:", "Kicked by an administrator", function(reason)
            sendTargetAction("kick", p, function() net.WriteString(reason or "") end)
        end)
    end)
    actionButton("Ban", 90, 0, 82, C.red, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Ban player", "Duration in minutes (0 = permanent):", "60", function(duration)
            local n = tonumber(duration); if not n or n < 0 then notify("Enter a valid duration.", false) return end
            Derma_StringRequest("Ban player", "Reason:", "Banned by an administrator", function(reason)
                sendTargetAction("ban", p, function() net.WriteUInt(math.Clamp(math.floor(n), 0, 65535), 16); net.WriteString(reason or "") end)
            end)
        end)
    end)
    actionButton("Warn", 180, 0, 82, C.orange, function()
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
        local x = ((i - 1) % 7) * 91
        actionButton(spec[1], x, 42, 83, spec[3], function()
            local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
            if spec[2] == "slay" or spec[2] == "respawn" then
                Derma_Query("Confirm " .. spec[1]:lower() .. " for " .. p.name .. "?", "Confirm action",
                    spec[1], function() sendTargetAction(spec[2], p) end, "Cancel")
            else sendTargetAction(spec[2], p) end
        end)
    end
    actionButton("Set money", 0, 82, 110, C.green, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Set player money", "New amount:", tostring(p.money or 0), function(value)
            local n = tonumber(value); if not n then notify("Enter a valid amount.", false) return end
            sendTargetAction("setmoney", p, function() net.WriteInt(math.Clamp(math.floor(n), 0, 2000000000), 32) end)
        end)
    end)
    actionButton("Add money", 118, 82, 110, C.green, function()
        local p = selectedPlayer(); if not p then notify("Select a player first.", false) return end
        Derma_StringRequest("Adjust player money", "Amount to add (negative removes money):", "100", function(value)
            local n = tonumber(value); if not n then notify("Enter a valid amount.", false) return end
            sendTargetAction("addmoney", p, function() net.WriteInt(math.Clamp(math.floor(n), -2000000000, 2000000000), 32) end)
        end)
    end)

    -- DarkRP page
    local darkrpPage = makePage("darkrp")
    addSection(darkrpPage, "DarkRP jobs & economy", "Inspect registered jobs and manage a selected player's job or wallet.")
    local rpNotice = label(darkrpPage, "", "DermaDefaultBold", C.orange)
    rpNotice:Dock(TOP); rpNotice:SetTall(26)
    rpNotice.Think = function(self)
        self:SetText(state.darkrp and ("DarkRP detected • " .. #state.jobs .. " registered jobs") or "DarkRP was not detected. Generic server controls remain available.")
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
        if self.serveradminJobsVersion == #state.jobs then return end
        self.serveradminJobsVersion = #state.jobs
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
    local moneyHint = label(jobActions, "Use Players & moderation → Set money / Add money to manage wallets.", "DermaDefault", C.muted)
    moneyHint:Dock(FILL); moneyHint:DockMargin(4, 8, 0, 0)

    -- Logs page
    local logsPage = makePage("logs")
    addSection(logsPage, "Audit logs", "Recent ServerAdmin actions recorded by the server. Refresh to load the latest entries.")
    local logsRefresh = button(logsPage, "Refresh logs", C.blue, function() request("refresh") end)
    logsRefresh:Dock(TOP); logsRefresh:DockMargin(0, 8, 0, 10); logsRefresh:SetWide(130)
    local logList = vgui.Create("DListView", logsPage)
    logList:Dock(FILL)
    logList:AddColumn("Time"):SetFixedWidth(150)
    logList:AddColumn("Administrator"):SetFixedWidth(180)
    logList:AddColumn("Action"):SetFixedWidth(120)
    logList:AddColumn("Target"):SetFixedWidth(170)
    logList:AddColumn("Details")
    logList:SetDataHeight(25)
    logList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end
    logList.Think = function(self)
        local first = state.logs[1]
        local signature = tostring(#state.logs) .. ":" .. tostring(first and first.time) .. ":" .. tostring(first and first.action) .. ":" .. tostring(first and first.detail)
        if self.serveradminLogSignature == signature then return end
        self.serveradminLogSignature = signature
        self:Clear()
        for _, item in ipairs(state.logs) do self:AddLine(item.time, item.actor, item.action, item.target, item.detail) end
    end

    -- Settings page
    local settings = makePage("settings")
    addSection(settings, "Server settings", "Sensitive changes require superadmin privileges. Changes affect the live server.")
    local hostEntry = addInput(settings, "Server hostname", state.hostname, "Enter hostname")
    local saveHost = button(settings, "Save hostname", C.blue, function()
        request("hostname", function() net.WriteString(hostEntry:GetValue() or "") end)
    end)
    saveHost:Dock(TOP); saveHost:DockMargin(0, 0, 0, 10); saveHost:SetWide(180)
    local gravityEntry = addInput(settings, "Gravity (0–2000)", state.gravity, "600")
    local saveGravity = button(settings, "Apply gravity", C.blue, function()
        local n = tonumber(gravityEntry:GetValue()); if not n then notify("Gravity must be numeric.", false) return end
        request("gravity", function() net.WriteFloat(math.Clamp(n, 0, 2000)) end)
    end)
    saveGravity:Dock(TOP); saveGravity:DockMargin(0, 0, 0, 10); saveGravity:SetWide(180)
    local mapEntry = addInput(settings, "Change map (map name, without .bsp)", state.map, "gm_flatgrass")
    local changeMap = button(settings, "Change map", C.red, function()
        local mapName = string.Trim(mapEntry:GetValue() or "")
        if mapName == "" then notify("Enter a map name.", false) return end
        Derma_Query("Change map to " .. mapName .. "? This will move everyone to a new map.", "Confirm map change",
            "Change map", function() request("map", function() net.WriteString(mapName) end) end, "Cancel")
    end)
    changeMap:Dock(TOP); changeMap:DockMargin(0, 0, 0, 10); changeMap:SetWide(180)
    local settingsHint = label(settings, "Map changes interrupt the current session. Use only trusted map names installed on the server.", "DermaDefault", C.muted)
    settingsHint:Dock(TOP); settingsHint:SetTall(28)

    -- Diagnostics page
    local diagnostics = makePage("diagnostics")
    addSection(diagnostics, "Diagnostics", "Runtime values exposed by the Garry's Mod server. Some engine metrics are not available through Lua.")
    local diag = vgui.Create("DPanel", diagnostics)
    diag:Dock(TOP); diag:SetTall(220); diag:DockMargin(0, 10, 0, 14)
    diag.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.panel2, 9)
        local lines = {
            {"Gamemode", state.gamemode},
            {"DarkRP integration", state.darkrp and "Available" or "Not detected"},
            {"Tickrate estimate", string.format("%.1f ticks/sec", state.tickrate)},
            {"Lua memory estimate", string.format("%.1f MB (collectgarbage)", state.memory)},
            {"Connected players", tostring(#state.players) .. " / " .. tostring(state.maxPlayers)},
            {"Current map", state.map},
            {"Server uptime", string.format("%d minutes", math.floor(state.uptime / 60))}
        }
        for i, pair in ipairs(lines) do
            local y = 22 + (i - 1) * 28
            draw.SimpleText(pair[1], "DermaDefault", 16, y, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(pair[2], "DermaDefaultBold", 220, y, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
        state.players[#state.players + 1] = {
            userid = net.ReadUInt(16), name = net.ReadString(), steamid = net.ReadString(),
            ping = net.ReadUInt(16), team = net.ReadString(), admin = net.ReadBool(),
            superadmin = net.ReadBool(), alive = net.ReadBool(), money = net.ReadInt(32),
            health = net.ReadUInt(8), armor = net.ReadUInt(8), role = net.ReadString(), jobid = net.ReadUInt(16)
        }
    end
    local jobCount = net.ReadUInt(10)
    state.jobs = {}
    for i = 1, jobCount do
        state.jobs[#state.jobs + 1] = { id = net.ReadUInt(16), name = net.ReadString(), command = net.ReadString(), salary = net.ReadInt(32) }
    end
    local logCount = net.ReadUInt(7)
    state.logs = {}
    for i = 1, logCount do
        state.logs[#state.logs + 1] = { time = net.ReadString(), actor = net.ReadString(), action = net.ReadString(), target = net.ReadString(), detail = net.ReadString() }
    end
    refreshPlayerList()
end)

local function openPanel()
    buildPanel()
end

concommand.Add("serveradmin", openPanel)
hook.Add("Think", "ServerAdmin_F6", function()
    local down = input.IsKeyDown(KEY_F6)
    if down and not f6WasDown then
        if not vgui.CursorVisible() then openPanel() end
    end
    f6WasDown = down
end)

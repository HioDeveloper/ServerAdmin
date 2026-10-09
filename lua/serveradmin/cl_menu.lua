-- ServerAdmin: dark in-game control panel
ServerAdmin = ServerAdmin or {}

local NET = "serveradmin_net"
local C = {
    bg = Color(15, 18, 25),
    panel = Color(23, 28, 38),
    panel2 = Color(31, 37, 49),
    border = Color(49, 59, 76),
    text = Color(235, 240, 248),
    muted = Color(145, 157, 176),
    blue = Color(84, 126, 255),
    green = Color(61, 183, 129),
    red = Color(218, 75, 91),
    orange = Color(226, 158, 62)
}
local state = { hostname = "Loading...", map = "unknown", gravity = 600, maxPlayers = 0, players = {} }
local frame
local playerList
local searchEntry
local selectedUserID
local notice = { text = "", ok = true, untilTime = 0 }
local f6WasDown = false

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

local function button(parent, text, color, callback)
    local item = vgui.Create("DButton", parent)
    item:SetText("")
    item:SetTall(34)
    item.Paint = function(self, w, h)
        local fill = color
        if self:IsHovered() then
            fill = Color(math.min(color.r + 16, 255), math.min(color.g + 16, 255), math.min(color.b + 16, 255))
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
    local selectionFound = false
    for _, ply in ipairs(state.players) do
        local haystack = string.lower(ply.name .. " " .. ply.steamid .. " " .. ply.team)
        if query == "" or string.find(haystack, query, 1, true) then
            local role = ply.superadmin and "Superadmin" or (ply.admin and "Admin" or "Player")
            local line = playerList:AddLine(ply.name, ply.team, tostring(ply.ping), ply.steamid, role)
            line.serveradminUserID = ply.userid
            if selectedUserID == ply.userid then
                line:SetSelected(true)
                selectionFound = true
            end
        end
    end
    if not selectionFound then selectedUserID = nil end
end

local function buildPanel()
    if IsValid(frame) then frame:Remove() end

    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(ScrW() - 40, 1180), math.min(ScrH() - 40, 760))
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(true)
    frame:MakePopup()
    frame.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.bg, 12)
        rounded(0, 0, w, 68, C.panel, 12)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("SERVERADMIN", "DermaLarge", 22, 25, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("SERVER CONTROL CENTER  /  v" .. (ServerAdmin.Version or "1.0.0"),
            "DermaDefault", 222, 33, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if CurTime() < notice.untilTime then
            draw.SimpleText(notice.text, "DermaDefaultBold", w - 60, 34,
                notice.ok and C.green or C.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    local close = button(frame, "X", C.panel2, function() frame:Close() end)
    close:SetSize(34, 32)
    close:SetPos(frame:GetWide() - 46, 18)
    close.Think = function(self) if IsValid(frame) then self:SetPos(frame:GetWide() - 46, 18) end end

    local sidebar = vgui.Create("DPanel", frame)
    sidebar:SetPos(14, 82)
    sidebar:SetSize(178, frame:GetTall() - 96)
    sidebar.Paint = function(self, w, h) rounded(0, 0, w, h, C.panel, 9) end

    local content = vgui.Create("DPanel", frame)
    content:SetPos(204, 82)
    content:SetSize(frame:GetWide() - 218, frame:GetTall() - 96)
    content.Paint = function(self, w, h) rounded(0, 0, w, h, C.panel, 9) end

    local pages = {}
    local navButtons = {}
    local function showPage(key)
        for name, page in pairs(pages) do page:SetVisible(name == key) end
        for name, nav in pairs(navButtons) do nav.serveradminActive = name == key end
    end
    local function addNav(text, key, y)
        local nav = button(sidebar, text, C.panel2, function() showPage(key) end)
        nav:SetPos(10, y)
        nav:SetSize(158, 38)
        nav.Paint = function(self, w, h)
            local fill = self.serveradminActive and C.blue or (self:IsHovered() and C.panel2 or C.panel)
            rounded(0, 0, w, h, fill, 7)
            draw.SimpleText(text, "DermaDefaultBold", 13, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        navButtons[key] = nav
    end

    local overview = vgui.Create("DPanel", content)
    overview:Dock(FILL); overview:DockMargin(16, 14, 16, 14); overview.Paint = nil
    pages.overview = overview

    local playersPage = vgui.Create("DPanel", content)
    playersPage:Dock(FILL); playersPage:DockMargin(16, 14, 16, 14); playersPage.Paint = nil
    pages.players = playersPage

    local settings = vgui.Create("DPanel", content)
    settings:Dock(FILL); settings:DockMargin(16, 14, 16, 14); settings.Paint = nil
    pages.settings = settings

    addNav("Overview", "overview", 12)
    addNav("Players", "players", 58)
    addNav("Server settings", "settings", 104)

    -- Overview
    local title = label(overview, "Server overview", "DermaLarge", C.text)
    title:Dock(TOP); title:SetTall(40)

    local cards = vgui.Create("DPanel", overview)
    cards:Dock(TOP); cards:SetTall(112); cards:DockMargin(0, 8, 0, 14); cards.Paint = nil
    local cardData = {
        { title = "PLAYERS ONLINE", value = function() return #state.players .. " / " .. state.maxPlayers end, color = C.green },
        { title = "CURRENT MAP", value = function() return state.map end, color = C.text },
        { title = "SERVER GRAVITY", value = function() return tostring(math.floor(state.gravity)) end, color = C.orange }
    }
    local statCards = {}
    for _, data in ipairs(cardData) do
        local card = vgui.Create("DPanel", cards)
        card.Paint = function(self, w, h)
            rounded(0, 0, w, h, C.panel2, 9)
            draw.SimpleText(data.title, "DermaDefault", 13, 23, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(tostring(data.value()), "DermaLarge", 13, 67, data.color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        statCards[#statCards + 1] = card
    end
    cards.PerformLayout = function(self, w, h)
        local gap = 10
        local cw = (w - gap * 2) / 3
        for i, card in ipairs(statCards) do card:SetPos((i - 1) * (cw + gap), 0); card:SetSize(cw, h) end
    end

    local host = label(overview, "", "DermaDefaultBold", C.text)
    host:Dock(TOP); host:SetTall(30)
    host.Think = function(self) self:SetText("Server: " .. state.hostname) end
    local map = label(overview, "", "DermaDefault", C.muted)
    map:Dock(TOP); map:SetTall(24)
    map.Think = function(self) self:SetText("Map: " .. state.map) end
    local refresh = button(overview, "Refresh server data", C.blue, function() request("refresh") end)
    refresh:Dock(TOP); refresh:DockMargin(0, 14, 0, 0); refresh:SetWide(190)

    -- Players
    local playersTitle = label(playersPage, "Player management", "DermaLarge", C.text)
    playersTitle:Dock(TOP); playersTitle:SetTall(40)
    searchEntry = vgui.Create("DTextEntry", playersPage)
    searchEntry:Dock(TOP); searchEntry:DockMargin(0, 6, 0, 10); searchEntry:SetTall(32)
    searchEntry:SetPlaceholderText("Search by name, SteamID or team...")
    searchEntry:SetUpdateOnType(true)
    searchEntry.OnValueChange = refreshPlayerList

    playerList = vgui.Create("DListView", playersPage)
    playerList:Dock(FILL)
    playerList:AddColumn("Player"):SetFixedWidth(175)
    playerList:AddColumn("Team"):SetFixedWidth(115)
    playerList:AddColumn("Ping"):SetFixedWidth(48)
    playerList:AddColumn("SteamID"):SetFixedWidth(150)
    playerList:AddColumn("Role")
    playerList:SetMultiSelect(false)
    playerList:SetDataHeight(26)
    playerList.OnRowSelected = function(_, _, line) selectedUserID = line.serveradminUserID end
    playerList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end

    local actions = vgui.Create("DPanel", playersPage)
    actions:Dock(BOTTOM); actions:SetTall(76); actions:DockMargin(0, 10, 0, 0); actions.Paint = nil

    local function addPlayerButton(text, x, y, w, color, callback)
        local b = button(actions, text, color, callback)
        b:SetPos(x, y); b:SetSize(w, 32)
        return b
    end
    addPlayerButton("Kick", 0, 0, 92, C.red, function()
        local target = selectedPlayer()
        if not target then notify("Select a player first.", false) return end
        Derma_StringRequest("Kick player", "Reason:", "Kicked by an administrator", function(reason)
            sendTargetAction("kick", target, function() net.WriteString(reason or "") end)
        end)
    end)
    addPlayerButton("Ban", 100, 0, 92, Color(155, 55, 72), function()
        local target = selectedPlayer()
        if not target then notify("Select a player first.", false) return end
        Derma_StringRequest("Ban player", "Duration in minutes (0 = permanent):", "60", function(minutesText)
            local minutes = tonumber(minutesText)
            if not minutes then notify("Duration must be a number.", false) return end
            Derma_StringRequest("Ban player", "Reason:", "Banned by an administrator", function(reason)
                sendTargetAction("ban", target, function()
                    net.WriteUInt(math.Clamp(math.floor(minutes), 0, 525600), 16)
                    net.WriteString(reason or "")
                end)
            end)
        end)
    end)

    local actionsData = {
        {"Bring", "bring", C.blue},
        {"Goto", "goto", C.blue},
        {"Freeze", "freeze", C.orange},
        {"Unfreeze", "unfreeze", C.panel2},
        {"Slay", "slay", C.red}
    }
    for i, spec in ipairs(actionsData) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        addPlayerButton(spec[1], 204 + col * 104, row * 38, 96, spec[3], function()
            local target = selectedPlayer()
            if not target then notify("Select a player first.", false) return end
            if spec[2] == "slay" then
                Derma_Query("Slay " .. target.name .. "?", "Confirm action",
                    "Slay", function() sendTargetAction("slay", target) end, "Cancel")
            else
                sendTargetAction(spec[2], target)
            end
        end)
    end

    -- Settings
    local settingsTitle = label(settings, "Server settings", "DermaLarge", C.text)
    settingsTitle:Dock(TOP); settingsTitle:SetTall(40)
    local hint = label(settings, "Superadmin only. Permissions are checked on the server.", "DermaDefault", C.orange)
    hint:Dock(TOP); hint:SetTall(26)

    local hostLabel = label(settings, "Server hostname", "DermaDefaultBold", C.text)
    hostLabel:Dock(TOP); hostLabel:SetTall(24); hostLabel:DockMargin(0, 12, 0, 4)
    local hostEntry = vgui.Create("DTextEntry", settings)
    hostEntry:Dock(TOP); hostEntry:SetTall(32); hostEntry:SetText(state.hostname)
    local hostSave = button(settings, "Save hostname", C.blue, function()
        request("hostname", function() net.WriteString(hostEntry:GetValue()) end)
    end)
    hostSave:Dock(TOP); hostSave:DockMargin(0, 8, 0, 12)

    local gravityLabel = label(settings, "Gravity (0–2000)", "DermaDefaultBold", C.text)
    gravityLabel:Dock(TOP); gravityLabel:SetTall(24)
    local gravityEntry = vgui.Create("DTextEntry", settings)
    gravityEntry:Dock(TOP); gravityEntry:SetTall(32); gravityEntry:SetText(tostring(state.gravity))
    local gravitySave = button(settings, "Apply gravity", C.blue, function()
        local value = tonumber(gravityEntry:GetValue())
        if not value then notify("Gravity must be numeric.", false) return end
        request("gravity", function() net.WriteFloat(math.Clamp(value, 0, 2000)) end)
    end)
    gravitySave:Dock(TOP); gravitySave:DockMargin(0, 8, 0, 12)

    local mapLabel = label(settings, "Change map (map name without .bsp)", "DermaDefaultBold", C.text)
    mapLabel:Dock(TOP); mapLabel:SetTall(24)
    local mapEntry = vgui.Create("DTextEntry", settings)
    mapEntry:Dock(TOP); mapEntry:SetTall(32); mapEntry:SetText(state.map)
    local mapChange = button(settings, "Change map", C.red, function()
        local mapName = string.Trim(mapEntry:GetValue() or "")
        if mapName == "" then notify("Enter a map name.", false) return end
        Derma_Query("Change map to " .. mapName .. "?", "Confirm map change",
            "Change map", function() request("map", function() net.WriteString(mapName) end) end,
            "Cancel")
    end)
    mapChange:Dock(TOP); mapChange:DockMargin(0, 8, 0, 12)

    showPage("overview")
    request("refresh")
end

net.Receive(NET, function()
    local kind = net.ReadString()
    if kind == "notice" then
        local ok = net.ReadBool()
        local message = net.ReadString()
        notify(message, ok)
        return
    end
    if kind ~= "snapshot" then return end

    state.hostname = net.ReadString()
    state.map = net.ReadString()
    local count = net.ReadUInt(8)
    state.maxPlayers = net.ReadUInt(8)
    state.gravity = net.ReadFloat()
    state.players = {}
    for i = 1, count do
        state.players[#state.players + 1] = {
            userid = net.ReadUInt(16),
            name = net.ReadString(),
            steamid = net.ReadString(),
            ping = net.ReadUInt(16),
            team = net.ReadString(),
            admin = net.ReadBool(),
            superadmin = net.ReadBool(),
            alive = net.ReadBool()
        }
    end
    refreshPlayerList()
end)

local function openPanel()
    request("refresh")
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

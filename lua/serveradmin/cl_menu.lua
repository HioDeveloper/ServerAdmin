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
    jobs = {}, customJobs = {}, logs = {}, bans = {}, warnings = {}, cvars = {}, gamemode = "unknown",
    tickrate = 0, uptime = 0, memory = 0, darkrp = false, lockdown = false, bots = 0, entities = 0,
    totalBans = 0, activeBans = 0, totalWarnings = 0, totalActions = 0, metrics = {}
}
local frame, playerList, searchEntry, selectedUserID, pages, navButtons
local motdTitleEntry, motdBodyEntry, rconCommandEntry, rconArgsEntry
local motdViewer
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


local function styleListLine(list, line)
    if not IsValid(line) then return end

    line.Paint = function(row, w, h)
        local fill
        if row:IsLineSelected() then
            fill = Color(73, 117, 255, 100)
        elseif row:GetAltLine() then
            fill = Color(31, 39, 53, 245)
        else
            fill = Color(22, 28, 39, 245)
        end
        draw.RoundedBox(4, 1, 1, w - 2, h - 2, fill)
        if row:IsLineSelected() then
            surface.SetDrawColor(C.cyan)
            surface.DrawRect(1, 5, 3, h - 10)
        elseif row:IsHovered() then
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(1, 1, w - 2, h - 2, 1)
        end
    end

    for index = 1, #(list.Columns or {}) do
        local cell = line:SetValue(index, line:GetColumnText(index))
        if IsValid(cell) then
            cell:SetTextColor(C.text)
            cell:SetFont("DermaDefault")
            cell:SetContentAlignment(4)
        end
    end
end

local function styleListView(list)
    if not IsValid(list) then return end
    list:SetHeaderHeight(30)
    list:SetDataHeight(27)
    list:SetMultiSelect(false)
    list:SetSortable(true)
    list.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    for _, column in ipairs(list.Columns or {}) do
        local header = column.Header
        if IsValid(header) then
            -- DListView_Column headers inherit a DLabel that draws the title itself.
            -- Hide only that built-in text; the custom Paint below draws the visible title once.
            header:SetTextColor(Color(C.text.r, C.text.g, C.text.b, 0))
            header:SetFont("DermaDefaultBold")
            header.Paint = function(self, w, h)
                draw.RoundedBox(4, 2, 2, w - 4, h - 4, C.panel2)
                draw.SimpleText(self:GetText() or "", "DermaDefaultBold", 9, h / 2,
                    C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end

    local originalAddLine = list.AddLine
    list.AddLine = function(self, ...)
        local line = originalAddLine(self, ...)
        styleListLine(self, line)
        return line
    end

    for _, line in ipairs(list:GetLines()) do
        styleListLine(list, line)
    end
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


local function openMOTDViewer(titleText, bodyText)
    if IsValid(motdViewer) then motdViewer:Remove() end

    motdViewer = vgui.Create("DFrame")
    motdViewer:SetSize(math.min(760, ScrW() - 48), math.min(620, ScrH() - 48))
    motdViewer:Center()
    motdViewer:SetTitle("")
    motdViewer:ShowCloseButton(false)
    motdViewer:SetDraggable(true)
    motdViewer:MakePopup()
    motdViewer.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.bg, 12)
        draw.RoundedBoxEx(12, 0, 0, w, 68, C.panel2, true, true, false, false)
        draw.SimpleText(string.sub(tostring(titleText or "Message of the day"), 1, 80),
            "DermaLarge", 20, 27, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("SERVER MESSAGE", "DermaDefaultBold", 22, 49, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local body = vgui.Create("DTextEntry", motdViewer)
    body:Dock(FILL)
    body:DockMargin(18, 82, 18, 58)
    body:SetMultiline(true)
    body:SetEditable(false)
    body:SetFont("DermaDefault")
    body:SetText(tostring(bodyText or ""))

    local close = button(motdViewer, "CLOSE", C.blue, function()
        if IsValid(motdViewer) then motdViewer:Close() end
    end, 36)
    close:SetSize(120, 36)
    close:AlignBottom(12)
    close:CenterHorizontal()
end

local function openJobEditor(mode, jobData)
    jobData = jobData or {}
    local editing = mode == "edit"
    local jobColor = Color(
        math.Clamp(tonumber(jobData.r) or 40, 0, 255),
        math.Clamp(tonumber(jobData.g) or 150, 0, 255),
        math.Clamp(tonumber(jobData.b) or 220, 0, 255)
    )

    local editor = vgui.Create("DFrame")
    editor:SetSize(math.min(680, ScrW() - 60), math.min(760, ScrH() - 60))
    editor:Center()
    editor:SetTitle("")
    editor:ShowCloseButton(false)
    editor:SetDraggable(true)
    editor:MakePopup()
    editor.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.bg, 12)
        draw.RoundedBoxEx(12, 0, 0, w, 68, C.panel2, true, true, false, false)
        draw.SimpleText(editing and "EDIT CUSTOM PROFESSION" or "CREATE CUSTOM PROFESSION",
            "DermaLarge", 22, 25, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("DARKRP JOB EDITOR  /  SAVED ON SERVER",
            "DermaDefaultBold", 24, 49, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local body = vgui.Create("DScrollPanel", editor)
    body:Dock(FILL)
    body:DockMargin(18, 82, 18, 10)

    local function field(titleText, initial, height, multiline, placeholder)
        local wrap = vgui.Create("DPanel", body)
        wrap:Dock(TOP)
        wrap:SetTall((height or 34) + 27)
        wrap:DockMargin(0, 0, 0, 8)
        wrap.Paint = function(self, w, h)
            draw.SimpleText(titleText, "DermaDefaultBold", 2, 10, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local entry = vgui.Create("DTextEntry", wrap)
        entry:Dock(BOTTOM)
        entry:SetTall(height or 34)
        entry:SetText(tostring(initial or ""))
        entry:SetPlaceholderText(placeholder or "")
        entry:SetFont("DermaDefault")
        entry:SetTextColor(C.text)
        if multiline then entry:SetMultiline(true) end
        entry.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.panel2)
            surface.SetDrawColor(self:HasFocus() and C.blue or C.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            self:DrawTextEntryText(C.text, C.blue, C.text)
        end
        return entry
    end

    local nameEntry = field("Profession name", jobData.name or "", 34, false, "e.g. Emergency Medic")
    local commandEntry = field("Chat command (without /)", jobData.command or "newjob", 34, false, "e.g. emergency_medic")
    if editing then
        commandEntry:SetEditable(false)
        commandEntry:SetTooltip("DarkRP registers job commands internally. The command is fixed after creation.")
    end
    local descriptionEntry = field("Description", jobData.description or "", 76, true, "Describe the role and its duties")
    local modelEntry = field("Player models (comma-separated)", table.concat(jobData.models or {"models/player/kleiner.mdl"}, ", "), 46, false, "models/player/kleiner.mdl")
    local weaponEntry = field("Spawn weapons (comma-separated class names)", table.concat(jobData.weapons or {}, ", "), 46, false, "weapon_fists, weapon_physcannon")
    local categoryEntry = field("F4 category", jobData.category or "Citizens", 34, false, "e.g. Civil Protection")
    local salaryEntry = field("Salary per payout", jobData.salary or 45, 34, false, "45")
    local maxEntry = field("Maximum players (0 = unlimited)", jobData.max or 0, 34, false, "0")

    local accessWrap = vgui.Create("DPanel", body)
    accessWrap:Dock(TOP)
    accessWrap:SetTall(62)
    accessWrap:DockMargin(0, 0, 0, 8)
    accessWrap.Paint = function(self, w, h)
        draw.SimpleText("Who can use this profession?", "DermaDefaultBold", 2, 10, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local accessEntry = vgui.Create("DComboBox", accessWrap)
    accessEntry:Dock(BOTTOM)
    accessEntry:SetTall(34)
    accessEntry:AddChoice("Everyone", 0)
    accessEntry:AddChoice("Administrators", 1)
    accessEntry:AddChoice("Superadmins", 2)
    accessEntry:SetValue(({[0] = "Everyone", [1] = "Administrators", [2] = "Superadmins"})[tonumber(jobData.admin) or 0])
    accessEntry:SetTextColor(C.text)
    accessEntry.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.panel2)
        surface.SetDrawColor(self:IsHovered() and C.blue or C.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText(self:GetValue() or "Everyone", "DermaDefault", 10, h / 2,
            C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("▼", "DermaDefaultBold", w - 18, h / 2,
            C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local switches = vgui.Create("DPanel", body)
    switches:Dock(TOP)
    switches:SetTall(36)
    switches:DockMargin(0, 0, 0, 8)
    switches.Paint = nil
    local voteCheck = vgui.Create("DCheckBoxLabel", switches)
    voteCheck:SetText("Requires a vote")
    voteCheck:SetTextColor(C.text)
    voteCheck:SetValue(jobData.vote and 1 or 0)
    voteCheck:SizeToContents()
    voteCheck:SetPos(2, 8)
    local licenseCheck = vgui.Create("DCheckBoxLabel", switches)
    licenseCheck:SetText("Requires gun license")
    licenseCheck:SetTextColor(C.text)
    licenseCheck:SetValue(jobData.hasLicense and 1 or 0)
    licenseCheck:SizeToContents()
    licenseCheck:SetPos(220, 8)

    local colorButton
    colorButton = button(body, "Choose profession color", C.panel2, function()
        if not Derma_ColorRequest then
            notify("The color picker is unavailable in this client.", false)
            return
        end
        Derma_ColorRequest("Profession color", jobColor, function(chosen)
            if not IsValid(editor) or not IsColor(chosen) then return end
            jobColor = Color(chosen.r, chosen.g, chosen.b)
            colorButton:SetText("")
            colorButton.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, jobColor)
                surface.SetDrawColor(C.border); surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText("COLOR  RGB " .. jobColor.r .. ", " .. jobColor.g .. ", " .. jobColor.b,
                    "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end)
    end, 36)
    colorButton:Dock(TOP)
    colorButton:DockMargin(0, 0, 0, 12)
    colorButton.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, jobColor)
        surface.SetDrawColor(C.border); surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("COLOR  RGB " .. jobColor.r .. ", " .. jobColor.g .. ", " .. jobColor.b,
            "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local help = label(body, editing and
        "Only ServerAdmin-created professions can be edited here. The chat command stays fixed so DarkRP command registrations remain consistent." or
        "Use mounted models and valid weapon class names. Changes are saved to server data and restored when DarkRP loads.", "DermaDefault", C.muted)
    help:Dock(TOP)
    help:SetTall(38)

    local footer = vgui.Create("DPanel", editor)
    footer:Dock(BOTTOM)
    footer:SetTall(54)
    footer:DockMargin(18, 0, 18, 14)
    footer.Paint = function(self, w, h)
        surface.SetDrawColor(C.border)
        surface.DrawRect(0, 0, w, 1)
    end
    local cancel = button(footer, "Cancel", C.panel2, function() editor:Close() end, 36)
    cancel:Dock(RIGHT)
    cancel:SetWide(110)
    cancel:DockMargin(8, 8, 0, 0)

    local save = button(footer, editing and "Save changes" or "Create profession", C.blue, function()
        local accessIndex = accessEntry:GetSelectedID()
        local accessLevel = accessIndex and tonumber(accessEntry:GetOptionData(accessIndex)) or nil
        if accessLevel == nil then
            local accessByName = {Everyone = 0, Administrators = 1, Superadmins = 2}
            accessLevel = accessByName[accessEntry:GetValue()] or 0
        end
        local data = {
            name = nameEntry:GetValue(),
            command = commandEntry:GetValue(),
            description = descriptionEntry:GetValue(),
            modelText = modelEntry:GetValue(),
            weaponsText = weaponEntry:GetValue(),
            category = categoryEntry:GetValue(),
            salary = tonumber(salaryEntry:GetValue()),
            max = tonumber(maxEntry:GetValue()),
            admin = accessLevel,
            vote = voteCheck:GetChecked(),
            hasLicense = licenseCheck:GetChecked(),
            r = jobColor.r, g = jobColor.g, b = jobColor.b
        }
        local json = util.TableToJSON(data, false)
        if not json or #json > 12000 then
            notify("Profession form is too large. Shorten the description or lists.", false)
            return
        end
        request(editing and "job_edit" or "job_create", function()
            if editing then net.WriteUInt(tonumber(jobData.id) or 0, 16) end
            net.WriteString(json)
        end)
        editor:Close()
    end, 36)
    save:Dock(FILL)
    save:DockMargin(0, 8, 0, 0)

    return editor
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
        if key == "players" or key == "logs" or key == "bans" or key == "darkrp" or key == "server" then
            request("refresh")
        elseif key == "motd" then
            request("motd_get")
        end
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
    addNav("Analytics & diagnostics", "diagnostics", 376)
    addNav("MOTD & RCON", "motd", 422)

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
    styleListView(online)
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
    styleListView(playerList)
    playerList.OnRowSelected = function(_, _, line) selectedUserID = line.serveradminUserID end
    playerList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end

    local selectedCard = vgui.Create("DPanel", playersPage)
    selectedCard:Dock(BOTTOM)
    selectedCard:SetTall(72)
    selectedCard:DockMargin(0, 8, 0, 0)
    selectedCard.Paint = function(self, w, h)
        rounded(0, 0, w, h, C.panel2, 9)
        surface.SetDrawColor(C.blue)
        surface.DrawRect(0, 8, 3, h - 16)
        local p = selectedPlayer()
        if not p then
            draw.SimpleText("NO PLAYER SELECTED", "DermaDefaultBold", 16, 23, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Select a row above to view player details and enable the actions below.", "DermaDefault", 16, 47, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            return
        end

        draw.SimpleText(p.name or "Unknown player", "DermaLarge", 16, 23, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText((p.role or "Player") .. "  /  " .. (p.team or "Unknown team") .. "  /  " .. (p.steamid or "Unknown SteamID"),
            "DermaDefault", 18, 49, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local status = (p.alive and "ALIVE" or "DEAD") ..
            "  •  HP " .. tostring(p.health or 0) ..
            "  •  ARMOR " .. tostring(p.armor or 0) ..
            "  •  PING " .. tostring(p.ping or 0) .. " ms"
        draw.SimpleText(status, "DermaDefaultBold", w - 16, 22,
            p.alive and C.green or C.orange, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        local flags = {}
        if p.muted then flags[#flags + 1] = "VOICE MUTED" end
        if p.gagged then flags[#flags + 1] = "CHAT GAG" end
        if p.frozen then flags[#flags + 1] = "FROZEN" end
        if p.god then flags[#flags + 1] = "GOD MODE" end
        draw.SimpleText(#flags > 0 and table.concat(flags, "  /  ") or "No active moderation flags",
            "DermaDefault", w - 16, 48, #flags > 0 and C.orange or C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local actionBar = vgui.Create("DPanel", playersPage)
    actionBar:Dock(BOTTOM); actionBar:SetTall(158); actionBar:DockMargin(0, 10, 0, 0)
    actionBar.Paint = function(self, w, h)
        surface.SetDrawColor(C.border)
        surface.DrawRect(0, 0, w, 1)
    end
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
    styleListView(jobList)
    jobList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end
    jobList.OnRowSelected = function(_, _, line) selectedJob = line.serveradminJobID end
    jobList.Think = function(self)
        local signature = ""
        for _, job in ipairs(state.jobs) do signature = signature .. "|" .. job.id .. ":" .. job.name .. ":" .. job.command .. ":" .. job.salary .. ":" .. tostring(state.customJobs[job.id] ~= nil) end
        if self.serveradminJobsSignature == signature then return end
        self.serveradminJobsSignature = signature
        self:Clear()
        for _, job in ipairs(state.jobs) do
            local line = self:AddLine(job.name .. (state.customJobs[job.id] and "  [CUSTOM]" or ""), job.command, "$" .. tostring(job.salary))
            line.serveradminJobID = job.id
        end
    end
    local jobActions = vgui.Create("DPanel", darkrpPage)
    jobActions:Dock(BOTTOM); jobActions:SetTall(100); jobActions:DockMargin(0, 8, 0, 0)
    jobActions.Paint = function(self, w, h)
        surface.SetDrawColor(C.border)
        surface.DrawRect(0, 0, w, 1)
    end

    local createJobButton = button(jobActions, "Create profession", C.green, function()
        if not LocalPlayer():IsSuperAdmin() then notify("Only superadmins can create professions.", false) return end
        if not state.darkrp then notify("DarkRP is not available.", false) return end
        openJobEditor("create")
    end, 36)
    createJobButton:SetPos(0, 8); createJobButton:SetSize(160, 36)

    local editJobButton = button(jobActions, "Edit selected", C.blue, function()
        if not LocalPlayer():IsSuperAdmin() then notify("Only superadmins can edit professions.", false) return end
        if not selectedJob then notify("Select a profession first.", false) return end
        local custom = state.customJobs[selectedJob]
        if not custom then
            notify("Only ServerAdmin-created professions can be edited here.", false)
            return
        end
        openJobEditor("edit", custom)
    end, 36)
    editJobButton:SetPos(168, 8); editJobButton:SetSize(145, 36)

    local deleteJobButton = button(jobActions, "Delete selected", C.red, function()
        if not LocalPlayer():IsSuperAdmin() then notify("Only superadmins can delete professions.", false) return end
        if not selectedJob then notify("Select a profession first.", false) return end
        local custom = state.customJobs[selectedJob]
        if not custom then
            notify("Only ServerAdmin-created professions can be deleted.", false)
            return
        end

        Derma_Query(
            "Permanently delete custom profession '" .. tostring(custom.name or "Unknown") ..
                "' (/" .. tostring(custom.command or "") .. ")? Players currently using it will be moved to a fallback profession.",
            "Delete custom profession",
            "Delete profession",
            function()
                request("job_delete", function() net.WriteUInt(tonumber(selectedJob) or 0, 16) end)
                selectedJob = nil
            end,
            "Cancel"
        )
    end, 36)
    deleteJobButton:SetPos(550, 8); deleteJobButton:SetSize(135, 36)

    local jobTarget = button(jobActions, "Assign to selected player", C.panel2, function()
        local p = selectedPlayer()
        if not p then notify("Select a player on the Players page first.", false) return end
        if not selectedJob then notify("Select a job first.", false) return end
        sendTargetAction("setjob", p, function() net.WriteUInt(selectedJob, 16) end)
    end, 36)
    jobTarget:SetPos(321, 8); jobTarget:SetSize(220, 36)

    local moneyHint = label(jobActions, "Custom professions are saved to server data. Changes are synchronized to clients.", "DermaDefault", C.muted)
    moneyHint:SetPos(2, 54); moneyHint:SetSize(650, 28)

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
    styleListView(banList)
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
            local active = b.active
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
    styleListView(warningList)
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
    local logActions = vgui.Create("DPanel", logsPage)
    logActions:Dock(TOP); logActions:SetTall(42); logActions:DockMargin(0, 8, 0, 8)
    logActions.Paint = nil

    local logsRefresh = button(logActions, "Refresh logs", C.blue, function() request("refresh") end)
    logsRefresh:SetPos(0, 3); logsRefresh:SetSize(130, 34)

    local clearLogs = button(logActions, "Clear all logs", C.red, function()
        if not LocalPlayer():IsSuperAdmin() then
            notify("Only superadmins can clear audit logs.", false)
            return
        end
        Derma_Query(
            "This permanently deletes all ServerAdmin audit log entries. Ban and warning records will not be affected.",
            "Clear audit logs",
            "Clear logs",
            function() request("clearlogs") end,
            "Cancel"
        )
    end)
    clearLogs:SetPos(140, 3); clearLogs:SetSize(150, 34)

    local logList = vgui.Create("DListView", logsPage)
    logList:Dock(FILL)
    logList:AddColumn("Time"):SetFixedWidth(150)
    logList:AddColumn("Administrator"):SetFixedWidth(180)
    logList:AddColumn("Action"):SetFixedWidth(135)
    logList:AddColumn("Target"):SetFixedWidth(170)
    logList:AddColumn("Details")
    logList:SetDataHeight(25)
    styleListView(logList)
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
    styleListView(cvarList)
    cvarList.Paint = function(self, w, h) rounded(0, 0, w, h, C.bg, 7) end
    local selectedCvar
    local cvarEntry, cvarHint
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
    cvarEntry = addInput(serverPage, "New value for selected variable", "", "Select a variable above")
    cvarHint = label(serverPage, "Select an item to edit it. Secret values are never disclosed.", "DermaDefault", C.muted)
    cvarHint:Dock(TOP); cvarHint:SetTall(24)
    local saveCvar = button(serverPage, "Apply selected variable", C.blue, function()
        if not selectedCvar then notify("Select a server variable first.", false) return end
        request("setcvar", function() net.WriteString(selectedCvar); net.WriteString(cvarEntry:GetValue() or "") end)
    end)
    saveCvar:Dock(TOP); saveCvar:DockMargin(0, 0, 0, 4); saveCvar:SetWide(220)

    -- MOTD editor and RCON-style server console
    local motdPage = makePage("motd")
    addSection(motdPage, "MOTD & RCON", "Edit the saved message shown to joining players, or run a server console command as superadmin.")
    local motdScroll = vgui.Create("DScrollPanel", motdPage)
    motdScroll:Dock(FILL)
    motdScroll:DockMargin(0, 8, 0, 0)

    local motdHeader = label(motdScroll, "MESSAGE OF THE DAY", "DermaDefaultBold", C.cyan)
    motdHeader:Dock(TOP)
    motdHeader:SetTall(28)
    motdTitleEntry = addInput(motdScroll, "MOTD title", "Welcome to the server", "Welcome to the server")

    local motdBodyWrap = vgui.Create("DPanel", motdScroll)
    motdBodyWrap:Dock(TOP)
    motdBodyWrap:SetTall(244)
    motdBodyWrap:DockMargin(0, 4, 0, 8)
    motdBodyWrap.Paint = function(self, w, h) rounded(0, 0, w, h, C.panel2, 8) end
    local motdBodyLabel = label(motdBodyWrap, "Message text (up to 8000 characters)", "DermaDefaultBold", C.muted)
    motdBodyLabel:SetPos(10, 7)
    motdBodyLabel:SetSize(420, 22)
    motdBodyEntry = vgui.Create("DTextEntry", motdBodyWrap)
    motdBodyEntry:SetMultiline(true)
    motdBodyEntry:SetFont("DermaDefault")
    motdBodyEntry:SetPos(10, 32)
    motdBodyWrap.PerformLayout = function(self, w, h)
        motdBodyEntry:SetSize(math.max(100, w - 20), h - 42)
    end

    local saveMOTD = button(motdScroll, "Save MOTD", C.blue, function()
        if not IsValid(motdTitleEntry) or not IsValid(motdBodyEntry) then return end
        local titleText = string.Trim(motdTitleEntry:GetValue() or "")
        local bodyText = motdBodyEntry:GetValue() or ""
        if #bodyText > 8000 then notify("MOTD is too long (maximum 8000 characters).", false) return end
        request("motd_save", function()
            net.WriteString(titleText)
            net.WriteString(bodyText)
        end)
    end, 38)
    saveMOTD:Dock(TOP); saveMOTD:DockMargin(0, 0, 0, 6)

    local previewMOTD = button(motdScroll, "Preview current editor text", C.panel2, function()
        openMOTDViewer(IsValid(motdTitleEntry) and motdTitleEntry:GetValue() or "MOTD",
            IsValid(motdBodyEntry) and motdBodyEntry:GetValue() or "")
    end, 36)
    previewMOTD:Dock(TOP); previewMOTD:DockMargin(0, 0, 0, 6)

    local broadcastMOTD = button(motdScroll, "Show saved MOTD to everyone online", C.orange, function()
        Derma_Query("Show the currently saved MOTD to every connected player?", "Broadcast MOTD",
            "Show to everyone", function() request("motd_broadcast") end, "Cancel")
    end, 36)
    broadcastMOTD:Dock(TOP); broadcastMOTD:DockMargin(0, 0, 0, 14)

    local rconHeader = label(motdScroll, "RCON / SERVER CONSOLE", "DermaDefaultBold", C.cyan)
    rconHeader:Dock(TOP)
    rconHeader:SetTall(28)
    rconCommandEntry = addInput(motdScroll, "Console command", "status", "e.g. status, version, hostname")
    rconArgsEntry = addInput(motdScroll, "Arguments (quotes keep words together)", "", 'e.g. "My server name"')
    local rconHint = label(motdScroll,
        "Superadmin only. Output is printed in the dedicated server console/logs. Script loaders, config loaders, password-changing RCON and shutdown commands are blocked.",
        "DermaDefault", C.muted)
    rconHint:Dock(TOP); rconHint:SetTall(38)
    local runRCON = button(motdScroll, "Run server console command", C.red, function()
        local command = string.Trim(IsValid(rconCommandEntry) and rconCommandEntry:GetValue() or "")
        local args = IsValid(rconArgsEntry) and rconArgsEntry:GetValue() or ""
        if command == "" then notify("Enter a console command name.", false) return end
        if #command > 64 or not string.match(command, "^[%w_%.%-]+$") then
            notify("Use one console command name without spaces.", false)
            return
        end
        if #args > 512 then notify("Console arguments are too long.", false) return end
        Derma_Query("Run '" .. command .. "' on the server? This may change live server behaviour.",
            "Confirm server console command", "Run command",
            function()
                request("rcon", function()
                    net.WriteString(command)
                    net.WriteString(args)
                end)
            end,
            "Cancel")
    end, 38)
    runRCON:Dock(TOP); runRCON:DockMargin(0, 0, 0, 12)

    -- Diagnostics
    local diagnostics = makePage("diagnostics")
    addSection(diagnostics, "Analytics & diagnostics", "Live server metrics, moderation totals and a rolling 60-minute history. History resets on server restart.")
    local analyticsScroll = vgui.Create("DScrollPanel", diagnostics)
    analyticsScroll:Dock(FILL)
    analyticsScroll:DockMargin(0, 6, 0, 0)

    local analyticsCards = vgui.Create("DPanel", analyticsScroll)
    analyticsCards:Dock(TOP); analyticsCards:SetTall(88); analyticsCards:DockMargin(0, 0, 0, 12)
    analyticsCards.Paint = nil
    local analyticsDefs = {
        {"TOTAL BANS", function() return tostring(state.totalBans) end, C.red},
        {"ACTIVE BANS", function() return tostring(state.activeBans) end, C.orange},
        {"WARNINGS", function() return tostring(state.totalWarnings) end, C.cyan},
        {"ADMIN ACTIONS", function() return tostring(state.totalActions) end, C.blue}
    }
    local analyticsStatCards = {}
    for _, def in ipairs(analyticsDefs) do
        analyticsStatCards[#analyticsStatCards + 1] = addStatCard(analyticsCards, def[1], def[2], def[3])
    end
    analyticsCards.PerformLayout = function(self, w, h)
        local gap = 8
        local cw = (w - gap * (#analyticsStatCards - 1)) / #analyticsStatCards
        for i, card in ipairs(analyticsStatCards) do
            card:SetPos((i - 1) * (cw + gap), 0)
            card:SetSize(cw, h)
        end
    end

    local chartRow = vgui.Create("DPanel", analyticsScroll)
    chartRow:Dock(TOP); chartRow:SetTall(224); chartRow:DockMargin(0, 0, 0, 12)
    chartRow.Paint = nil

    local function drawLineChart(panel, titleText, metricKey, accent, valueSuffix, maxValue)
        panel.Paint = function(self, w, h)
            rounded(0, 0, w, h, C.panel2, 9)
            draw.SimpleText(titleText, "DermaDefaultBold", 14, 18, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local history = state.metrics or {}
            local left, top, right, bottom = 36, 42, w - 14, h - 28
            local plotW, plotH = math.max(1, right - left), math.max(1, bottom - top)
            surface.SetDrawColor(C.border)
            for i = 0, 4 do
                local y = top + plotH * i / 4
                surface.DrawLine(left, y, right, y)
            end
            local peak = tonumber(maxValue) or 0
            for _, sample in ipairs(history) do peak = math.max(peak, tonumber(sample[metricKey]) or 0) end
            peak = math.max(1, peak)
            draw.SimpleText(string.format("%.0f%s", peak, valueSuffix or ""), "DermaDefault", 5, top, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("0", "DermaDefault", 14, bottom, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if #history == 0 then
                draw.SimpleText("Waiting for metric samples...", "DermaDefault", w / 2, h / 2 + 8, C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                return
            end
            if #history == 1 then
                local sample = history[1]
                local x, y = left, bottom - ((tonumber(sample[metricKey]) or 0) / peak) * plotH
                surface.SetDrawColor(accent)
                surface.DrawRect(x - 2, y - 2, 5, 5)
            else
                for i = 2, #history do
                    local a, b = history[i - 1], history[i]
                    local x1 = left + (i - 2) / (#history - 1) * plotW
                    local x2 = left + (i - 1) / (#history - 1) * plotW
                    local y1 = bottom - math.Clamp((tonumber(a[metricKey]) or 0) / peak, 0, 1) * plotH
                    local y2 = bottom - math.Clamp((tonumber(b[metricKey]) or 0) / peak, 0, 1) * plotH
                    surface.SetDrawColor(accent)
                    surface.DrawLine(x1, y1, x2, y2)
                    surface.DrawRect(x2 - 2, y2 - 2, 4, 4)
                end
            end
            local latest = history[#history]
            draw.SimpleText("Now: " .. string.format("%.1f", tonumber(latest[metricKey]) or 0) .. (valueSuffix or ""),
                "DermaDefaultBold", right, 18, accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    local playersChart = vgui.Create("DPanel", chartRow)
    local entitiesChart = vgui.Create("DPanel", chartRow)
    drawLineChart(playersChart, "PLAYER COUNT · LAST 60 MIN", "players", C.green, "", state.maxPlayers)
    drawLineChart(entitiesChart, "ENTITY COUNT · LAST 60 MIN", "entities", C.cyan, "", 0)
    chartRow.PerformLayout = function(self, w, h)
        local gap = 12
        local cw = (w - gap) / 2
        playersChart:SetPos(0, 0); playersChart:SetSize(cw, h)
        entitiesChart:SetPos(cw + gap, 0); entitiesChart:SetSize(cw, h)
    end

    local performanceRow = vgui.Create("DPanel", analyticsScroll)
    performanceRow:Dock(TOP); performanceRow:SetTall(224); performanceRow:DockMargin(0, 0, 0, 12)
    performanceRow.Paint = nil
    local tickChart = vgui.Create("DPanel", performanceRow)
    local memoryChart = vgui.Create("DPanel", performanceRow)
    drawLineChart(tickChart, "ESTIMATED TICKRATE", "tickrate", C.blue, " TPS", 66)
    drawLineChart(memoryChart, "LUA MEMORY ESTIMATE", "memory", C.orange, " MB", 0)
    performanceRow.PerformLayout = function(self, w, h)
        local gap = 12
        local cw = (w - gap) / 2
        tickChart:SetPos(0, 0); tickChart:SetSize(cw, h)
        memoryChart:SetPos(cw + gap, 0); memoryChart:SetSize(cw, h)
    end

    local diagRefresh = button(analyticsScroll, "Refresh analytics", C.blue, function() request("refresh") end)
    diagRefresh:Dock(TOP); diagRefresh:SetTall(36); diagRefresh:DockMargin(0, 0, 0, 12)
    local diag = vgui.Create("DPanel", analyticsScroll)
    diag:Dock(TOP); diag:SetTall(250); diag:DockMargin(0, 0, 0, 14)
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
    showPage(activePage or "overview")
    request("refresh")
end

local syncedCustomJobCommands = {}

local function applyClientCustomJobs(specs, attempt)
    attempt = attempt or 0
    if not istable(specs) then return end
    if not istable(RPExtraTeams) or not istable(DarkRP) or not isfunction(DarkRP.createJob) then
        if attempt < 20 then
            timer.Simple(1, function() applyClientCustomJobs(specs, attempt + 1) end)
        end
        return
    end

    local incoming = {}
    for _, spec in ipairs(specs) do
        local id = istable(spec) and tonumber(spec.id) or nil
        if id and id > 0 and id < 65536 and isstring(spec.command) then
            incoming[id] = spec.command
        end
    end

    -- If the server removed a custom job, remove only the exact job this client previously
    -- registered via DarkRP's API. Never delete or replace an unrelated job by team ID alone.
    for id, oldCommand in pairs(syncedCustomJobCommands) do
        if not incoming[id] then
            local current = RPExtraTeams[id]
            if current and current.ServerAdminCustom == true and
                tostring(current.command or "") == tostring(oldCommand) and isfunction(DarkRP.removeJob) then
                local ok, removeError = pcall(DarkRP.removeJob, id)
                if not istable(RPExtraTeams[id]) then
                    syncedCustomJobCommands[id] = nil
                else
                    ErrorNoHalt("[ServerAdmin] Could not remove synced custom profession ID " ..
                        tostring(id) .. ": " .. tostring(removeError) .. "\\n")
                end
            else
                syncedCustomJobCommands[id] = nil
            end
        end
    end

    state.customJobs = {}
    table.sort(specs, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)

    for _, spec in ipairs(specs) do
        local id = tonumber(spec.id)
        if id and id > 0 and id < 65536 and isstring(spec.command) and istable(spec.models) and istable(spec.weapons) then
            state.customJobs[id] = spec

            local current = RPExtraTeams[id]
            if current and tostring(current.command or "") == tostring(spec.command) then
                -- The job already exists locally; do not rewrite DarkRP's registered team.
                current.ServerAdminCustom = true
                syncedCustomJobCommands[id] = spec.command
            elseif current then
                -- Another profession occupies this ID. Never overwrite it.
                ErrorNoHalt("[ServerAdmin] Skipped client registration for '" ..
                    tostring(spec.name or spec.command) .. "': team ID " .. tostring(id) ..
                    " is occupied by '" .. tostring(current.name or current.command or "unknown") .. "'.\\n")
            elseif #RPExtraTeams + 1 ~= id then
                ErrorNoHalt("[ServerAdmin] Skipped client registration for '" ..
                    tostring(spec.name or spec.command) .. "': local team order does not match server ID " ..
                    tostring(id) .. ".\\n")
            else
                local categories
                if isfunction(DarkRP.getCategories) then
                    local ok, result = pcall(DarkRP.getCategories)
                    if ok and istable(result) then categories = result.jobs end
                end
                local categoryExists = false
                for _, entry in ipairs(istable(categories) and categories or {}) do
                    if istable(entry) and tostring(entry.name or "") == tostring(spec.category or "") then
                        categoryExists = true
                        break
                    end
                end

                local jobData = {
                    color = Color(
                        math.Clamp(tonumber(spec.r) or 40, 0, 255),
                        math.Clamp(tonumber(spec.g) or 150, 0, 255),
                        math.Clamp(tonumber(spec.b) or 220, 0, 255),
                        255
                    ),
                    model = table.Copy(spec.models),
                    description = tostring(spec.description or ""),
                    weapons = table.Copy(spec.weapons),
                    command = tostring(spec.command or ""),
                    max = tonumber(spec.max) or 0,
                    salary = tonumber(spec.salary) or 0,
                    admin = tonumber(spec.admin) or 0,
                    vote = spec.vote == true,
                    hasLicense = spec.hasLicense == true,
                    category = categoryExists and tostring(spec.category) or "Other"
                }

                local ok, createdID = pcall(DarkRP.createJob, tostring(spec.name or "Custom profession"), jobData)
                if ok and tonumber(createdID) == id and istable(RPExtraTeams[id]) and
                    tostring(RPExtraTeams[id].command or "") == tostring(spec.command) then
                    RPExtraTeams[id].ServerAdminCustom = true
                    syncedCustomJobCommands[id] = spec.command
                else
                    ErrorNoHalt("[ServerAdmin] Could not safely register client profession '" ..
                        tostring(spec.name or spec.command) .. "': " .. tostring(createdID) .. "\\n")
                end
            end
        end
    end
end

net.Receive("serveradmin_job_sync", function()
    local payload = net.ReadString()
    local specs = util.JSONToTable(payload or "")
    if not istable(specs) then
        ErrorNoHalt("[ServerAdmin] Received invalid custom profession sync payload.\n")
        return
    end
    applyClientCustomJobs(specs)
end)

net.Receive(NET, function()
    local kind = net.ReadString()
    if kind == "notice" then
        notify(net.ReadString(), net.ReadBool())
        return
    elseif kind == "motd_data" then
        local titleText = net.ReadString()
        local bodyText = net.ReadString()
        if IsValid(motdTitleEntry) then motdTitleEntry:SetText(titleText) end
        if IsValid(motdBodyEntry) then motdBodyEntry:SetText(bodyText) end
        return
    elseif kind == "motd_show" then
        openMOTDViewer(net.ReadString(), net.ReadString())
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
    state.totalBans = net.ReadUInt(32)
    state.activeBans = net.ReadUInt(32)
    state.totalWarnings = net.ReadUInt(32)
    state.totalActions = net.ReadUInt(32)
    local metricCount = net.ReadUInt(7)
    state.metrics = {}
    for i = 1, metricCount do
        state.metrics[#state.metrics + 1] = {
            time = net.ReadUInt(32),
            players = net.ReadUInt(8),
            bots = net.ReadUInt(8),
            entities = net.ReadUInt(16),
            tickrate = net.ReadFloat(),
            memory = net.ReadFloat()
        }
    end

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

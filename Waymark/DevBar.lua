-- The /bfi commands as buttons: on the settings' Dev page, and on a small bar
-- that can be dragged anywhere (/bfi bar). Each runs the slash command itself,
-- so the two never drift apart from BattlefieldInfo.lua's list.
local _, ns = ...

-- every command, in groups: { label, command, what it does, slash = another slash command's
-- SlashCmdList key (the dev-only /bfideaths, /bfiroutes: left off when that file isn't loaded) }
ns.DevCommands = {
    { group = "Windows" },
    { "Options",        "options",        "Open or close the settings." },
    { "Command bar",    "bar",            "This list as a small bar, to drag anywhere. It opens again after a reload." },
    { "Ink bar",        "ink",            "Draw on the map." },
    { group = "Found notes" },
    { "Notebook",       "notes",          "The found notes: the wanderer's dungeon notebook." },
    { "Write in it",    "notes write",    "The notebook open, the quill in hand." },
    { "Watch for",      "watch",          "The dungeon's generated \"watch for\" lines (who runs, calls, fears, silences), to write into the notebook. Hover: their spells." },
    { "Page shots",     "notes shots",    "Every spread and \"before we go\" page in turn, a screenshot each (Screenshots\\)." },
    { "Deaths layer",   "",               "Where Hardcore players die, red x's on the dungeon maps (dev only, not shipped).", slash = "BFIDEATHS", shown = "/bfideaths" },
    { "Example routes", "",               "Example routes on the dungeon maps (dev only, not shipped).", slash = "BFIROUTES", shown = "/bfiroutes" },
    { "Node probe",     "",               "Whether the game tells us a herb or ore node is in reach, printed to chat (dev only, not shipped).", slash = "BFINODES", shown = "/bfinodes" },
    { group = "Dungeon maps" },
    { "Boss place",     "bosses place",   "Place boss spots on dungeon maps: drag a marker, the wheel over a name moves it in the kill order." },
    { "Boss list",      "bosses list",    "The dungeon maps and their placed bosses." },
    { "Probe dungeon",  "probe",          "What the map knows about this dungeon." },
    { "Probe cave",     "cave",           "What the map knows about this cave." },
    { "Where: record",  "where rec",      "Record what you meet inside, and clicks on the dungeon map where you really are, for tools\\where_replay.lua. Again to stop." },
    { group = "Quests" },
    { "Quest probe",    "questprobe",     "Quest data around you, printed to chat." },
    { "Quest art",      "questart",       "The quest art pieces, printed to chat." },
    { "Unhide quests",  "unhide",         "Quests hidden with Shift-click back on the map." },
    { group = "Checks" },
    { "Check",          "check",          "Write the in-game check for tools\\read_check.py, then reload." },
    { "Check (no rl)",  "check noreload", "The check without the reload." },
    { "Debug",          "debug",          "Map frame details, printed to chat." },
    { "Probe town",     "town",           "Whether this place counts as a town, and why." },
    { "Layers",         "layers",         "The map's frame levels, printed to chat." },
    { "Buttons",        "buttons",        "The map buttons' setup, printed to chat." },
    { group = "Map art" },
    { "Outline edit",   "cut",            "Hand-adjust clear view's outlines." },
    { "Zone shapes",    "shapes",         "Sample the zones' outlines for tools\\zone_shapes.py." },
    { "Dev art",        "devart",         "Era: dev art on or off (reloads)." },
    { "Forever's maps", "forevermap",     "Era: Forever's maps on or off, from Waymark_ForeverMap (reloads)." },
}

-- (not shown: /bfi <number> sets the map's scale, 0.3-3; /bfi quest <id> has its box on the bar)

-- whether a command can run here (a dev-only slash command's file may be left out)
function ns.DevCommandHere(e)
    return not e.slash or SlashCmdList[e.slash] ~= nil
end

-- what to type for it, for its tooltip
function ns.DevCommandText(e)
    return e.shown or ("/waymark " .. e[2])
end

function ns.RunDevCommand(e)
    if type(e) == "string" then e = { nil, e } end
    if e.slash then
        if SlashCmdList[e.slash] then SlashCmdList[e.slash]("") end
        return
    end
    if SlashCmdList.BFI then SlashCmdList.BFI(e[2]) end
end

local bar
local COLS, BW, BH = 3, 104, 22

local function SavePos()
    local p, _, rp, x, y = bar:GetPoint()
    WaymarkDB.devBarPos = { p, rp, x, y }
end

local function Build()
    bar = CreateFrame("Frame", "WaymarkDevBar", UIParent, "BasicFrameTemplateWithInset")
    local pos = WaymarkDB.devBarPos
    if pos then
        bar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        bar:SetPoint("TOP", 0, -120)
    end
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePos()
    end)
    bar:SetScript("OnHide", function() WaymarkDB.devBarShown = nil end)
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("/waymark (dev)")

    -- each group: its name, then its buttons three to a row
    local y, c = -28, 0
    local function NewRow()
        if c > 0 then y = y - (BH + 2) end
        c = 0
    end
    for _, e in ipairs(ns.DevCommands) do
        if e.group then
            NewRow()
            local h = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h:SetPoint("TOPLEFT", 12, y - 2)
            h:SetText(e.group)
            y = y - 16
        elseif ns.DevCommandHere(e) then
            if c == COLS then NewRow() end
            local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
            b:SetSize(BW - 2, BH)
            b:SetText(e[1])
            b:SetPoint("TOPLEFT", 10 + c * BW, y)
            c = c + 1
            b:SetScript("OnClick", function() ns.RunDevCommand(e) end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(ns.DevCommandText(e), 1, 1, 1)
                GameTooltip:AddLine(e[3], nil, nil, nil, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", GameTooltip_Hide)
        end
    end
    NewRow()

    -- /bfi quest <id>: an id box and its button, the last row
    local h = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", 12, y - 2)
    h:SetText("Explain a quest")
    y = y - 16
    local box = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    box:SetSize(BW - 12, BH - 2)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetPoint("TOPLEFT", 10 + 8, y - 1)
    local q = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    q:SetSize(BW - 2, BH)
    q:SetText("Explain quest")
    q:SetPoint("TOPLEFT", 10 + BW, y)
    local function Explain()
        local id = tonumber(box:GetText())
        if id then ns.RunDevCommand("quest " .. id) end
        box:ClearFocus()
    end
    q:SetScript("OnClick", Explain)
    box:SetScript("OnEnterPressed", Explain)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    q:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("/waymark quest <id>", 1, 1, 1)
        GameTooltip:AddLine("Whether the quest id in the box shows as available, and why not.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    q:SetScript("OnLeave", GameTooltip_Hide)
    y = y - (BH + 2)
    bar:SetSize(COLS * BW + 20, -y + 8)
end

function ns.ToggleDevBar(on)
    if not bar then Build() end
    if on == nil then on = not bar:IsShown() end
    bar:SetShown(on)
    WaymarkDB.devBarShown = on or nil
end

-- open again after a reload (Check reloads) if it was open
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if WaymarkDB and WaymarkDB.devBarShown then ns.ToggleDevBar(true) end
end)

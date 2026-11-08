local _, ns = ...

-- The first run (mockups/welcome.html): a small note beside the minimap at login, once, then a page
-- beside the map the first time the map opens. Nothing blocks the game, and it never comes back by
-- itself, on any character; Start here can show the page again. ns.db.welcome: noted (the note's been
-- shown), done (the page's been closed). Settings from before this start with both set (InitDB), so
-- players updating don't see it. Not part of a setup or preset (Setups.lua EXCLUDE).

local W = 330
local note, page
local quietly  -- (the page going with the map: it still counts as unseen)

local function Cfg() return ns.db.welcome end

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function Window(name)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    ns.AddonWindow(f)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    return f
end

local function MapOpen()
    return BattlefieldMapFrame and BattlefieldMapFrame:IsShown()
end

local function OpenMap()
    if not MapOpen() and ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
end

-- The note ------------------------------------------------------------------------------------

local function NoteText()
    local key = GetBindingKey and GetBindingKey("TOGGLEBATTLEFIELDMINIMAP")
    key = key and GetBindingText and GetBindingText(key) or key
    if key then return "It works on the Battlefield Map: " .. key .. ", or this button." end
    return "It works on the Battlefield Map: this button opens it."
end

local function BuildNote()
    note = Window("WaymarkWelcomeNote")
    note:SetWidth(250)
    local title = note:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Waymark is ready")
    local text = note:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    text:SetWidth(226)
    text:SetJustifyH("LEFT")
    text:SetText(NoteText())
    local open = ns.RedButton(note, 120, 22)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -8)
    open:SetText("Open the map")
    open:SetScript("OnClick", function()
        note:Hide()
        OpenMap()
    end)
    local later = ns.RedButton(note, 80, 22)
    later:SetPoint("LEFT", open, "RIGHT", 6, 0)
    later:SetText("Later")
    later:SetScript("OnClick", function() note:Hide() end)
    note:SetHeight(10 + title:GetStringHeight() + 4 + text:GetStringHeight() + 8 + 22 + 12)
end

local function ShowNote()
    if MapOpen() then return end
    Cfg().noted = true
    if not note then BuildNote() end
    note:ClearAllPoints()
    note:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -14, 0)
    note:Show()
end

-- The page ------------------------------------------------------------------------------------

local function Switch(col, label, group, key, what)
    col:Check(label, group, key)
    if what then col:Note(what, nil, nil, nil, 26) end
end

local function BuildPage()
    page = Window("WaymarkWelcome")
    page:SetWidth(W)
    tinsert(UISpecialFrames, "WaymarkWelcome")  -- (Esc)
    page:SetScript("OnHide", function()
        if not quietly then Cfg().done = true end
        quietly = nil
    end)
    local ok, close = pcall(CreateFrame, "Button", nil, page, "UIPanelCloseButton")
    if ok then close:SetPoint("TOPRIGHT", 0, 0) end

    local col = ns.PanelColumn(page, 10, -6, W - 20)
    col:Header("Welcome to Waymark")
    col:Note("This is your map. It follows you, shows quest givers and turn-ins, and fills in the parts of "
        .. "the world you haven't found yet. Wheel to zoom, right-click to go out a level.", 1, 0.96, 0.86)
    col:Header("Would you like more on it?")
    Switch(col, "Townsfolk", "townsfolk", "shown", "Trainers, vendors and innkeepers.")
    col:CheckWith("Quest objectives", ns.ObjectivesOn, function(v)
        ns.SetObjectives(v)
        ns.RefreshControls()
    end)
    col:Note("Where your quests' monsters and items are.", nil, nil, nil, 26)
    col:Header("You can also have")
    Switch(col, "Waymark's quest tracker", "tracker", "shown", "In place of the game's.")
    Switch(col, "A clock on the map", "clock", "shown")
    Switch(col, "Clear view", "clearView", "on", "Just the map, no frame.")
    -- (performance mode: its own settings page, where the player picks what it lightens)
    col.y = col.y - 6
    col:Note("The addon has a lower performance cost mode for handhelds and older PC's.", 1, 0.96, 0.86)
    col:Button("Click here to enable", function()
        if ns.ToggleOptions then ns.ToggleOptions("performance") end
    end)
    if ns.FOREVER then
        col.y = col.y - 6
        col:Note("Forever is new, and I'm still squashing issues with the new client. If something looks "
            .. "wrong, tell me on CurseForge or GitHub.")
    end

    local done = ns.RedButton(page, 80, 22)
    done:SetPoint("TOPRIGHT", -12, col.y - 6)
    done:SetText("Done")
    done:SetScript("OnClick", function() page:Hide() end)
    local foot = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("LEFT", page, "TOPLEFT", 14, col.y - 17)
    foot:SetText("All of this is in the settings too.")
    page:SetHeight(-col.y + 6 + 22 + 12)
end

-- beside the map, on the side with room; docked, left of the square
local function PlacePage()
    local map = BattlefieldMapFrame
    page:ClearAllPoints()
    if ns.Docked and ns.Docked() and Minimap then
        page:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -14, 0)
        return
    end
    local right = map:GetRight()
    local room = right and UIParent:GetRight()
        and UIParent:GetRight() * UIParent:GetEffectiveScale() - right * map:GetEffectiveScale()
            > W * page:GetEffectiveScale() + 8
    if room then
        page:SetPoint("TOPLEFT", map, "TOPRIGHT", 8, 0)
    else
        page:SetPoint("TOPRIGHT", map, "TOPLEFT", -8, 0)
    end
end

local function ShowPage()
    if not page then BuildPage() end
    PlacePage()
    page:Show()
    if ns.RefreshControls then ns.RefreshControls() end
end

-- out of the way, still unseen
function ns.HideWelcome()
    if page and page:IsShown() then
        quietly = true
        page:Hide()
    end
end

-- Start here's button: the page again, the map opened for it
function ns.ShowWelcome()
    OpenMap()
    if BattlefieldMapFrame then C_Timer.After(0.2, function() if MapOpen() then ShowPage() end end) end
end

-- Inside a dungeon while the dungeon map is off (ns.DungeonsOff): a line along the foot of the map
-- saying so, the first time only (welcome.dungeonSeen), for that visit or till its X. Existing players
-- get it too. Gone with that one line.
local dungeonNote, dungeonClosed
local function InDungeon()
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid")
end
local function UpdateDungeonNote()
    if not ns.DungeonsOff then return end
    local map = BattlefieldMapFrame
    if not map then return end
    local inside = InDungeon()
    if Cfg().dungeonSeen and not (dungeonNote and dungeonNote:IsShown()) then return end
    if not dungeonNote then
        if not inside then return end
        local f = CreateFrame("Frame", nil, map, "BackdropTemplate")
        f:SetBackdrop(BACKDROP)
        f:SetBackdropColor(0, 0, 0, 0.9)
        f:EnableMouse(true)
        f:SetPoint("BOTTOMLEFT", 8, 8)
        f:SetPoint("BOTTOMRIGHT", -8, 8)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("TOPLEFT", 10, -8)
        f.text:SetPoint("TOPRIGHT", -26, -8)
        f.text:SetJustifyH("LEFT")
        f.text:SetText("A lot of dungeon features are off for now. I'm fixing them, and they'll be back in the days to come.")
        local ok, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
        if ok then
            close:SetSize(22, 22)
            close:SetPoint("TOPRIGHT", 0, 0)
            close:SetScript("OnClick", function()
                dungeonClosed = true
                f:Hide()
            end)
        end
        dungeonNote = f
    end
    dungeonNote:SetFrameLevel(ns.ButtonLevel(map))
    dungeonNote:SetHeight(dungeonNote.text:GetStringHeight() + 16)
    dungeonNote:SetShown(inside and not dungeonClosed and true or false)
    if dungeonNote:IsShown() then Cfg().dungeonSeen = true end
end

function ns.SetupWelcome(map)
    local function Opened()
        UpdateDungeonNote()
        if note then note:Hide() end
        if Cfg().done then return end
        C_Timer.After(0.2, function()   -- (the map's size and place are set by now)
            -- (not for the map opening as it docks: that's a minimap, and you're busy; Start here has it)
            local docking = ns.db.dock.on or (ns.Docked and ns.Docked())
            if MapOpen() and not Cfg().done and not docking then ShowPage() end
        end)
    end
    map:HookScript("OnShow", Opened)
    map:HookScript("OnHide", function()
        if page and page:IsShown() then
            quietly = true
            page:Hide()
        end
    end)
    if map:IsShown() then Opened() end
end

local zones = CreateFrame("Frame")
zones:RegisterEvent("PLAYER_ENTERING_WORLD")
zones:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zones:SetScript("OnEvent", function()
    if ns.db and not ns.standBy then C_Timer.After(1, UpdateDungeonNote) end
end)

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_ENTERING_WORLD")
login:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(3, function()
        if ns.db and not ns.standBy and not Cfg().noted and not Cfg().done then ShowNote() end
    end)
end)

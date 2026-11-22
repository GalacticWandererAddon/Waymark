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
    -- (the settings window's frame, title bar and red X, as the gear's quick panel: the user, 2026-11-16.
    -- Its title says the welcome, so the page starts at its first words.)
    local dressed = ns.MetalWindow ~= nil
    if dressed then
        page = CreateFrame("Frame", "WaymarkWelcome", UIParent)
        ns.AddonWindow(page)
        page:SetFrameStrata("HIGH")
        page:SetClampedToScreen(true)
        page:EnableMouse(true)
        page:Hide()
        ns.MetalWindow(page, "Welcome to Waymark")
    else
        page = Window("WaymarkWelcome")
    end
    page:SetWidth(W)
    tinsert(UISpecialFrames, "WaymarkWelcome")  -- (Esc)
    page:SetScript("OnHide", function()
        if not quietly then Cfg().done = true end
        quietly = nil
    end)
    if not dressed then
        local ok, close = pcall(CreateFrame, "Button", nil, page, "UIPanelCloseButton")
        if ok then close:SetPoint("TOPRIGHT", 0, 0) end
    end

    -- The settings pass, 2026-11-14: what a new player sees first, kept short. What the map is in 1.3 (it no
    -- longer "fills in" unexplored land: that is blank and pencilled now), the glance in one line (the best
    -- of folding, and nothing else told a player it exists), where the map can live (so the minimap
    -- replacement and clear view are met here), then the few switches worth a first look, and the book.
    local col = ns.PanelColumn(page, 10, dressed and -26 or -6, W - 20)
    if not dressed then col:Header("Welcome to Waymark") end
    col:Note("This is your map. It follows you, and the land on it is shaded from the game's real terrain. "
        .. "Land you have seen but not walked is sketched in pencil. Mouse wheel to zoom, right-click to go up to the continent.",
        1, 0.96, 0.86)
    local key = GetBindingKey and GetBindingKey("TOGGLEBATTLEFIELDMINIMAP")
    key = key and GetBindingText and GetBindingText(key) or key
    col:Note("Hold " .. (key or "the map's key") .. " and the map shows only while you hold it: a glance.", 1, 0.96, 0.86)
    if ns.MapRole and ns.SetMapRole then
        col:Choice("Where the map goes", nil, nil, {
            { "window", "A window" }, { "clear", "Clear view: no frame" }, { "dock", "In the minimap's place" },
        }, ns.MapRole, function(v)
            -- (the page stays where it is on the screen: it hangs on the map, and jumped away with it when
            -- the map went to the minimap's place, from under the pointer. The user, 2026-11-15)
            local l, t = page:GetLeft(), page:GetTop()
            if l and t then
                page:ClearAllPoints()
                page:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
            end
            ns.SetMapRole(v)
            ns.RefreshControls()
        end)
    end
    -- the world map on M: the first-run question about M (the user, 2026-11-22; the pick of big map or world map
    -- went the same day: the world map is the big map). Only where Waymark's world map is (Lab for now).
    if ns.MapKinds and ns.MapKinds.Here() then
        col.y = col.y - 6
        col:CheckWith("Open the world map with M", ns.MapKinds.OnM, ns.MapKinds.SetM)
        col:Tip(ns.MapKinds.M_TIP)
    end
    col:Header("Want more on the map?")
    Switch(col, "Townsfolk", "townsfolk", "shown", "Trainers, vendors and innkeepers.")
    col:CheckWith("Quest objectives", ns.ObjectivesOn, function(v)
        ns.SetObjectives(v)
        ns.RefreshControls()
    end)
    col:Note("Where your quest mobs and items are.", nil, nil, nil, 26)
    col:Header("Beside it")
    -- (As told first here: its panel stands beside the map, not on it. The user, 2026-11-15)
    if ns.ToldNow then
        Switch(col, "As told", "told", "on", "Your quest in its giver's words, on a small panel.")
    end
    Switch(col, "Waymark's quest tracker", "tracker", "shown", "In place of the game's.")
    -- (the words, then their button, as the performance lines under it. The user, 2026-11-15)
    col.y = col.y - 6
    col:Note("A wanderer's dungeon notebook came with the map.", 1, 0.96, 0.86)
    col:Button("Open the book", function() if ns.ToggleNotebook then ns.ToggleNotebook() end end)
    -- (performance mode: its own settings page, where the player picks what it lightens)
    col.y = col.y - 6
    col:Note("There's a performance mode for handhelds and older PCs.", 1, 0.96, 0.86)
    col:Button("Open performance mode", function()
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
    -- (the way on: Start here lists everything Waymark can do, what is off too)
    local more = ns.RedButton(page, 150, 22)
    more:SetPoint("TOPLEFT", 12, col.y - 6)
    more:SetText("See all it can do")
    more:SetScript("OnClick", function()
        page:Hide()
        if ns.ToggleOptions then ns.ToggleOptions("overview") end
    end)
    page:SetHeight(-col.y + 6 + 22 + 12)
end

-- beside the map, on the side with room; docked, left of the square
local function PlacePage()
    local map = BattlefieldMapFrame
    page:ClearAllPoints()
    -- (docked too, by the map itself: the live dots shrink the real minimap and lay it on your arrow, so a
    -- page hung on the minimap opened from the middle of the map, as the gear's panel did, 2026-11-16)
    local right = map:GetRight()
    local room = right and UIParent:GetRight()
        and UIParent:GetRight() * UIParent:GetEffectiveScale() - right * map:GetEffectiveScale()
            > W * page:GetEffectiveScale() + 8
    if room then
        page:SetPoint("TOPLEFT", map, "TOPRIGHT", 18, 0)   -- (clear of the metal frame, which reaches past the page)
    else
        page:SetPoint("TOPRIGHT", map, "TOPLEFT", -18, 0)
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

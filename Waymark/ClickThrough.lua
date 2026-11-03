local _, ns = ...

-- Click-through: the map lets clicks and the mouse wheel through to the world
-- (or whatever lies under it) unless the chosen modifier is held. The mouse
-- still moves over it: pin tooltips, hover fading and the zone highlight stay.
-- combat: only while you're in combat.
-- Every frame in the map's tree that takes clicks has them turned off, and back
-- on for as long as the modifier is down. Not while docked (Dock.lua turns the
-- map's mouse off and on itself on the minimap face).

local function Cfg() return ns.db.clickThrough end

local MODIFIER = { ALT = IsAltKeyDown, CTRL = IsControlKeyDown, SHIFT = IsShiftKeyDown }

local clicksOff = {}  -- [frame] = true: its clicks turned off here
local wheelOff = {}   -- [frame] = true: its wheel turned off here
local through = false
local walkQueued
local inCombat = InCombatLockdown() or UnitAffectingCombat("player")

-- (no SetMouseClickEnabled on a client: the whole mouse, tooltips too)
local function SetClicks(f, on)
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(on) else f:EnableMouse(on) end
end
local function ClicksOn(f)
    if f.IsMouseClickEnabled then return f:IsMouseClickEnabled() end
    return f:IsMouseEnabled()
end

local function Walk(f)
    if f:IsForbidden() or f:IsProtected() then return end
    if ClicksOn(f) then
        SetClicks(f, false)
        clicksOff[f] = true
    end
    if f:IsMouseWheelEnabled() then
        f:EnableMouseWheel(false)
        wheelOff[f] = true
    end
    for _, child in ipairs({ f:GetChildren() }) do Walk(child) end
end

local function Restore()
    for f in pairs(clicksOff) do
        -- (one turned off since, by EnableMouse(false), e.g. Dock's minimap
        -- face, stays off: the mouse moving over it is off too then)
        if not f.IsMouseMotionEnabled or f:IsMouseMotionEnabled() then SetClicks(f, true) end
    end
    for f in pairs(wheelOff) do f:EnableMouseWheel(true) end
    wipe(clicksOff)
    wipe(wheelOff)
end

local function Wanted()
    local c = ns.db and Cfg()
    if not (c and c.on and BattlefieldMapFrame) then return false end
    if ns.Docked and ns.Docked() then return false end
    if ns.InkDrawing and ns.InkDrawing() then return false end  -- (drawing on it: Ink.lua)
    if ns.CutEditing and ns.CutEditing() then return false end  -- (the outline editor: CutEdit.lua)
    if c.combat and not inCombat then return false end  -- (only in combat: the map yours otherwise)
    local held = MODIFIER[c.modifier] or IsAltKeyDown
    return not held()
end

local waiter = CreateFrame("Frame")

function ns.ApplyClickThrough()
    local want = Wanted()
    -- (going through mid-press, the map would miss its mouse-up and keep
    -- panning or moving: wait until the buttons are up)
    if want and not through and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
        waiter:SetScript("OnUpdate", function(self)
            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then return end
            self:SetScript("OnUpdate", nil)
            ns.ApplyClickThrough()
        end)
        return
    end
    waiter:SetScript("OnUpdate", nil)
    if want then
        Walk(BattlefieldMapFrame)  -- (again when already through: frames made since)
    elseif through then
        Restore()
    end
    through = want
end

-- new pins, and frames made as the map changes (cave and dungeon views), go
-- through too: once a frame later, however many come at once
local function QueueWalk()
    if not through or walkQueued then return end
    walkQueued = true
    C_Timer.After(0, function()
        walkQueued = nil
        if through and Wanted() then Walk(BattlefieldMapFrame) end
    end)
end

-- While the modifier is down, its key is asked a few times a second too: let go
-- of in another window (Alt-Tab), the game sends no MODIFIER_STATE_CHANGED for
-- it, and the map stayed usable until the key was pressed again
local watch = CreateFrame("Frame")
local since = 0
local function Watch(_, elapsed)
    since = since + elapsed
    if since < 0.1 then return end
    since = 0
    local c = Cfg()
    local held = c and c.on and (MODIFIER[c.modifier] or IsAltKeyDown)()
    if held then return end
    watch:SetScript("OnUpdate", nil)
    if c and c.on then ns.ApplyClickThrough() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:SetScript("OnEvent", function()
    local c = Cfg()
    if not (c and c.on) then return end
    ns.ApplyClickThrough()
    if (MODIFIER[c.modifier] or IsAltKeyDown)() then
        since = 0
        watch:SetScript("OnUpdate", Watch)
    end
end)

-- "Only in combat": through as combat starts, back when it ends
local fight = CreateFrame("Frame")
fight:RegisterEvent("PLAYER_REGEN_DISABLED")
fight:RegisterEvent("PLAYER_REGEN_ENABLED")
fight:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    local c = Cfg()
    if c and c.on and c.combat then ns.ApplyClickThrough() end
end)

function ns.SetupClickThrough(map)
    hooksecurefunc(map, "AcquirePin", QueueWalk)
    hooksecurefunc(map, "OnMapChanged", QueueWalk)
    map:HookScript("OnShow", function() ns.ApplyClickThrough() end)
    ns.ApplyClickThrough()
end

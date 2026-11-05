local _, ns = ...

-- Context profiles: while you're in combat, a battleground, a dungeon or a city,
-- that profile can switch layers on or off (layers[group] = true/false; nil
-- leaves the layer as you set it) and can hide the whole map. Your own settings
-- are never changed: ns.IsShown asks the active profile first.

-- checked in this order: the first enabled one that matches wins
ns.PROFILE_ORDER = { "combat", "battleground", "dungeon", "city" }
ns.PROFILE_LABELS = {
    combat = "In combat", battleground = "Battlegrounds", dungeon = "Dungeons & raids", city = "Towns & cities",
}

local inCombat = false
local active      -- key of the active profile, or nil
local hiddenByUs = false

local function Matches(key)
    if key == "combat" then return inCombat end
    local inInstance, kind = IsInInstance()
    if key == "battleground" then return inInstance and (kind == "pvp" or kind == "arena") end
    if key == "dungeon" then return inInstance and (kind == "party" or kind == "raid" or kind == "scenario") end
    if key == "city" then  -- towns as Town.lua sees them (sub-zone, flight point, vendors, resting)
        -- capitals always; other towns only with town view on (its one switch)
        if ns.InCityView and ns.InCityView() then return true end
        if ns.InTownView then return ns.InTownView() end
        return not inInstance and IsResting()
    end
    return false
end

local function Detect()
    for _, key in ipairs(ns.PROFILE_ORDER) do
        local p = ns.db.profiles[key]
        if p and p.enabled and Matches(key) then return key end
    end
    return nil
end

function ns.ActiveProfile()
    return active and ns.db.profiles[active] or nil
end

function ns.ActiveProfileKey() return active end
-- (the map closed by a profile's "hide the map", not by you: Dungeon.lua keeps it open over a reload)
function ns.MapHiddenByProfile() return hiddenByUs and true or false end

local function ApplyMapVisibility()
    local map = BattlefieldMapFrame
    if not map then return end
    local p = ns.ActiveProfile()
    if p and p.hideMap then
        if map:IsShown() then
            map:Hide()
            hiddenByUs = true
        end
    elseif hiddenByUs then
        hiddenByUs = false
        map:Show()
    end
end

function ns.UpdateProfile()
    if not ns.db then return end
    local now = Detect()
    local changed = now ~= active
    active = now
    ApplyMapVisibility()
    -- also redraw when only the profile's contents changed (edited in settings)
    ns.RedrawAll()
    if changed and ns.RefreshControls then ns.RefreshControls() end
end

function ns.SetupProfiles()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("PLAYER_UPDATE_RESTING")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false end
        local was = active
        local now = Detect()
        if now ~= was then ns.UpdateProfile() end
    end)
    -- walking into a town fires no event of its own: re-check every 2 s
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 2 then return end
        elapsed = 0
        if Detect() ~= active then ns.UpdateProfile() end
    end)
    inCombat = InCombatLockdown and InCombatLockdown() or false
    ns.UpdateProfile()
end

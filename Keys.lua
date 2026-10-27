local _, ns = ...

-- Key bindings (Bindings.xml lists them; Esc > Options > Keybindings > AddOns >
-- Battlefield Info). Each one calls BattlefieldInfo_Key with its action.

BINDING_HEADER_BFI = "Battlefield Info"

local ACTIONS = {
    zoomin   = { "Zoom in", function() ns.MapZoom(1) end },
    zoomout  = { "Zoom out", function() ns.MapZoom(-1) end },
    center   = { "Keep centered on me (on/off)", function()
                    ns.db.mapFrame.center = not ns.db.mapFrame.center
                    ns.OnSettingChanged("mapFrame", "center")
                end },
    clearview = { "Clear view (on/off)", function() if ns.ToggleClearView then ns.ToggleClearView() end end },
    dock     = { "Minimap replacement (on/off)", function() if ns.ToggleDock then ns.ToggleDock() end end },
    options  = { "Settings window", function() ns.ToggleOptions() end },
    setup    = { "Next saved setup", function() if ns.NextSetup then ns.NextSetup() end end },
    continent = { "Continent map (again: back to my map)", function() if ns.BrowseKey then ns.BrowseKey() end end },
    -- (with the minimap replacement the Battlefield Map's own Shift+M does
    -- nothing, so the name suggests the usual map key for this)
    bigmap   = { "Big map (again: normal size; opens the map). Tip for Minimap replacement: put this on M",
                 function() if ns.ToggleBigMap then ns.ToggleBigMap() end end },
    collapse = { "Collapse the map (again: open it)", function() if ns.ToggleCollapse then ns.ToggleCollapse() end end },
}

-- one per layer toggle, from the toggle strip's list (Options.lua)
local LAYER_KEYS = { "questie", "turnins", "learned", "spots", "townsfolk", "rares", "gather", "party", "line",
                     "explore", "dungeons", "detail", "zoom", "zoneName", "coords" }

-- (names for the layers that have a key but no button on the map)
local NO_BUTTON = { learned = "Learned quest givers", party = "Player & group", explore = "Unexplored areas",
                    zoneName = "Header", coords = "Coordinates" }

-- (the key does less than the button: auto-zoom's button also centers on shift-click)
local KEY_LABEL = { zoom = "Auto-zoom" }

local function LayerLabel(id)
    for _, t in ipairs(ns.TOGGLES or {}) do
        if t[1] == id and KEY_LABEL[id] then return KEY_LABEL[id], t[2] end
        if t[1] == id then return t[4], t[2] end
    end
    return NO_BUTTON[id] or id, "shown"
end

for _, id in ipairs(LAYER_KEYS) do
    ACTIONS["layer_" .. id] = { "Show/hide: " .. LayerLabel(id), function()
        local _, key = LayerLabel(id)
        if not ns.db[id] then return end
        ns.ToggleLayer(id, key)  -- (wins over an active profile, like the map's buttons)
        if ns.RefreshToggles then ns.RefreshToggles() end
        print("|cff33ff99BattlefieldInfo:|r " .. LayerLabel(id) .. (ns.LayerOn(id, key) and " on" or " off"))
    end }
end

for name, a in pairs(ACTIONS) do
    _G["BINDING_NAME_BFI_" .. name:upper()] = a[1]
end

-- for the Key bindings page: { command, label }, in Bindings.xml's order,
-- the map actions first, then the layers
function ns.KeyBindingList()
    local out = {}
    for _, name in ipairs({ "zoomin", "zoomout", "center", "continent", "bigmap", "collapse", "clearview", "dock", "options", "setup" }) do
        out[#out + 1] = { "BFI_" .. name:upper(), ACTIONS[name][1] }
    end
    for _, id in ipairs(LAYER_KEYS) do
        out[#out + 1] = { "BFI_LAYER_" .. id:upper(), (LayerLabel(id)), layer = true }
    end
    return out
end

function BattlefieldInfo_Key(action)
    if not ns.db then return end
    local a = ACTIONS[action]
    if a then a[2]() end
end

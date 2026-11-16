local _, ns = ...

-- Key bindings (Bindings.xml lists them; Esc > Options > Keybindings > AddOns >
-- Waymark). Each one calls Waymark_Key with its action. The BFI_ binding names stay:
-- players' keys are saved under them.

BINDING_HEADER_BFI = "Waymark"
-- (the groups in the game's Keybindings list, the same as on our Key bindings page: Bindings.xml's headers)
BINDING_HEADER_BFI_WORTH = "The keys worth having"
BINDING_HEADER_BFI_PAD = "With a controller"
BINDING_HEADER_BFI_MORE = "More keys"
BINDING_HEADER_BFI_LAYERS = "Show or hide a layer"

local ACTIONS = {
    zoomin   = { "Zoom in", function() ns.MapZoom(1) end },
    zoomout  = { "Zoom out", function() ns.MapZoom(-1) end },
    center   = { "Follows you", function()
                    ns.db.mapFrame.center = not ns.db.mapFrame.center
                    ns.OnSettingChanged("mapFrame", "center")
                end },
    clearview = { "Clear view", function() if ns.ToggleClearView then ns.ToggleClearView() end end },
    dock     = { "Dock/undock the map", function() if ns.ToggleDock then ns.ToggleDock() end end },
    options  = { "Settings", function() ns.ToggleOptions() end },
    setup    = { "Next saved setup", function() if ns.NextSetup then ns.NextSetup() end end },
    continent = { "Continent map", function() if ns.BrowseKey then ns.BrowseKey() end end },
    bigmap   = { "Big map", function() if ns.ToggleBigMap then ns.ToggleBigMap(true) end end },
    -- (tap: fold or open; held: only while you hold it. Collapse.lua's glance)
    collapse = { "Fold the map", function(state) if ns.CollapseKey then ns.CollapseKey(state) end end, upToo = true },
    ink      = { "Draw on the map", function() if ns.ToggleInkBar then ns.ToggleInkBar() end end },
    book     = { "Open the book", function() if ns.ToggleNotebook then ns.ToggleNotebook() end end },
}
-- (names fit the game's Keybindings column, about 25 letters; each key
-- toggles, a second press puts it back)

-- one per layer toggle, from the toggle strip's list (Options.lua)
local LAYER_KEYS = { "questie", "turnins", "learned", "spots", "townsfolk", "rares", "gather", "party", "line",
                     "explore", "dungeons", "detail", "zoom", "zoneName", "coords", "ink" }

-- (names for the layers that have a key but no button on the map)
local NO_BUTTON = { learned = "Learned quest givers", party = "Player & group", explore = "Unexplored land",
                    zoneName = "Header", coords = "Coordinates" }

-- (shorter, to fit the Keybindings column)
local KEY_LABEL = { zoom = "Follows you", learned = "Learned quests", rares = "RareScanner",
                    gather = "Gathering", explore = "Unexplored", dungeons = "Dungeon doors", ink = "Your ink" }

local function LayerLabel(id)
    for _, t in ipairs(ns.TOGGLES or {}) do
        if t[1] == id then return KEY_LABEL[id] or t[4], t[2] end
    end
    return KEY_LABEL[id] or NO_BUTTON[id] or id, "shown"
end

for _, id in ipairs(LAYER_KEYS) do
    ACTIONS["layer_" .. id] = { "Show/hide: " .. LayerLabel(id), function()
        local _, key = LayerLabel(id)
        if not ns.db[id] then return end
        ns.ToggleLayer(id, key)  -- (wins over an active profile, like the map's buttons)
        if ns.RefreshToggles then ns.RefreshToggles() end
        print("|cff33ff99Waymark:|r " .. LayerLabel(id) .. (ns.LayerOn(id, key) and " on" or " off"))
    end }
end

for name, a in pairs(ACTIONS) do
    _G["BINDING_NAME_BFI_" .. name:upper()] = a[1]
end

-- for the Key bindings page: groups of { command, label, a line saying what it gives }, in Bindings.xml's
-- order. The first row is the game's own key for the map, not one of ours. "Show/hide: Keep centered"
-- (layer_zoom) does what "Keep me centred" does: it keeps its binding, so a saved key works, and has no row.
function ns.KeyGroups()
    local function Row(name, line) return { "BFI_" .. name:upper(), ACTIONS[name][1], line } end
    local layers = { title = "Show or hide a layer" }
    for _, id in ipairs(LAYER_KEYS) do
        if id ~= "zoom" then layers[#layers + 1] = { "BFI_LAYER_" .. id:upper(), (LayerLabel(id)) } end
    end
    -- (the key they really have on the map, so the line is true for them; nothing bound, nothing to say)
    local bound = GetBindingKey and GetBindingKey("TOGGLEBATTLEFIELDMINIMAP")
    local mapKey = bound and (" " .. ((GetBindingText and GetBindingText(bound)) or bound) .. " disabled while docked.") or ""
    return {
        { title = "The keys worth having",
          { "TOGGLEBATTLEFIELDMINIMAP", "Open the map", "The game's own map key, Shift-M by default. Tap: open or close. Hold: a glance." },
          Row("bigmap", "Enlarges the map. Press again to go back."),
          Row("dock", "Docked, the map sits in the minimap's place." .. mapKey) },
        { title = "With a controller", note = "Zoom in, zoom out and back out a level, on buttons.",
          Row("zoomin"), Row("zoomout"), Row("continent") },
        { title = "More keys",
          -- (the book among these: it has its button on the map, its camps and the dungeon map's own; the
          -- user, 2026-11-14: "I dont think people will keybind that. In wow, keybinds are precious")
          -- (folding: the glance is on the map's own key, so this one only earns a key with the ribbon or an
          -- attached tracker. Clear view: a style you choose, not something switched many times a session)
          Row("collapse"), Row("clearview"), Row("center"), Row("ink"), Row("book"), Row("setup"), Row("options") },
        layers,
    }
end

-- state: "down" / "up" from a binding with runOnUp (Bindings.xml), else nil
function Waymark_Key(action, state)
    if not ns.db or ns.standBy then return end
    local a = ACTIONS[action]
    if not a or (state == "up" and not a.upToo) then return end
    a[2](state)
end

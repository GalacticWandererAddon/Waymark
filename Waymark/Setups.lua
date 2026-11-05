local addonName, ns = ...

-- Saved setups: snapshots of all your settings under a name (ns.db.setups), to
-- switch between and to share as a text string. A setup only changes when you save it.
-- Each character also keeps its own settings: saved as it logs out (ns.db.characters),
-- loaded again when it logs in, and copyable to another character.
-- The string is shaped like other addons' profile strings (WeakAuras, BetterBlizzFrames,
-- Plater): "!BFI:1!", then the settings written out as a plain table, compressed with
-- LibDeflate and made printable (letters, digits and brackets: one line, safe in chat
-- or a .txt). It's read back by our own small reader, never run as code. The old
-- "BFI1:" strings (the table as it is) are still read.

local PREFIX, OLD_PREFIX = "!BFI:1!", "BFI1:"
-- what's been learned as you play (Learn.lua): quest givers, their quests, monster spots
local LEARNED_PREFIX = "!BFIL:1!"
local LibDeflate = LibStub("LibDeflate")

-- not part of a setup: per-run and learned data, and the setups themselves
local EXCLUDE = { addonScale = true,  -- (Waymark size: follows your screen, not a setup or character)
                  setups = true, characters = true, dungeonRun = true, blockedLog = true, towns = true,
                  diag = true, lastErrors = true,  -- (/bfi check's results)
                  devArtOff = true,  -- (/bfi devart, Art.lua)
                  -- your own things on the maps, kept whatever setup is loaded
                  bossSpots = true, bossNotes = true, inkMarks = true, bossOrder = true,
                  notebook = true,  -- (the found notes: your pages, marks, the book's place)
                  objectSpots = true, objectHidden = true,  -- (dungeon pins you moved or hid)
                  optionsWindow = true,  -- (the settings window's own state: folds, last page)
                  beforeCleared = true, questieBoth = true,
                  myPresets = true,  -- (your presets: names of setups, kept with the setups)  -- (SetupSetups: the old "Before ..." setups cleared, once)
                  zoneShapes = true,  -- (dev: ZoneArt.lua's measurements)
                  cutEdits = true, cutEditsBeforeRestore = true, cutRestored = true }  -- (dev: CutEdit.lua)
-- inside a group: also yours, kept when a setup is loaded (quests you hid, folds)
local KEEP_IN = { questie = { hidden = true, source = true }, tracker = { folded = true, foldedAreas = true },
                  questlog = { zoneOpen = true } }

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Snapshot()
    local s = {}
    for k, v in pairs(ns.db) do
        if not EXCLUDE[k] then s[k] = Copy(v) end
    end
    for g, keys in pairs(KEEP_IN) do
        for k in pairs(keys) do
            if type(s[g]) == "table" then s[g][k] = nil end
        end
    end
    return s
end

-- Applying -----------------------------------------------------------------

-- every part of the addon takes its settings afresh
function ns.ApplyAll()
    pcall(ns.ShareQuestLook)
    for _, ch in ipairs({
        { nil, "scale" }, { "questie", "shown" }, { "waypoints", "shown" }, { "rares", "shown" },
        { "townsfolk", "shown" }, { "mapFrame" }, { "zoom" }, { "detail" }, { "line" },
        { "gather", "shown" }, { "dungeon" }, { "zoneName" }, { "cave" }, { "profiles" },
        { "explore" }, { "border" }, { "learned", "shown" }, { "dungeons", "shown" }, { "toggles" }, { "party", "classColors" }, { "clearView" },
        -- (the rest, so a loaded setup or preset shows at once, not after a /reload)
        { "tracker" }, { "questlog", "shown" }, { "townView", "enabled" }, { "townView", "types" }, { "cityView", "types" },
        { "collapse" }, { "clickThrough" }, { "dock" }, { "browse" }, { "ink" }, { "pins" }, { "gather", "types" },
    }) do
        pcall(ns.OnSettingChanged, ch[1], ch[2])
    end
    for _, g in ipairs({ "questie", "turnins", "spots", "objectives", "townsfolk", "rares", "gather" }) do
        pcall(ns.ApplyScales, g)
    end
    pcall(ns.RedrawAll)
end

local function Apply(s)
    local kept = {}
    for g, keys in pairs(KEEP_IN) do
        for k in pairs(keys) do
            if type(ns.db[g]) == "table" and ns.db[g][k] ~= nil then
                kept[g] = kept[g] or {}
                kept[g][k] = ns.db[g][k]
            end
        end
    end
    for k in pairs(ns.db) do
        if not EXCLUDE[k] then ns.db[k] = nil end
    end
    for k, v in pairs(s) do
        if not EXCLUDE[k] then ns.db[k] = Copy(v) end
    end
    for g, t in pairs(kept) do
        ns.db[g] = ns.db[g] or {}
        for k, v in pairs(t) do ns.db[g][k] = v end
    end
    ns.ClockFirstTime(ns.db)   -- (a setup or character saved before the clock)
    ns.CopyDefaults(ns.db, ns.DEFAULTS)
    ns.keepSizeOff = true  -- (its scale and its sizes as saved: ns.SetScale)
    pcall(ns.ApplyAll)
    ns.keepSizeOff = nil
end

-- Named setups ------------------------------------------------------------------

function ns.SetupNames()
    local names = {}
    for name in pairs(ns.db.setups) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function ns.SaveSetup(name)
    name = name and strtrim(name) or ""
    if name == "" then return false end
    ns.db.setups[name] = Snapshot()
    ns.lastSetup = name  -- (what you have is that setup now: "(current)" on the Setups page)
    return true
end

function ns.LoadSetup(name)
    local s = ns.db.setups[name]
    if not s then return false end
    Apply(s)
    ns.lastSetup = name
    ns.Log("Loaded setup \"" .. name .. "\".")
    return true
end

function ns.DeleteSetup(name)
    ns.db.setups[name] = nil
end

-- the next one after the last loaded (for the key binding)
function ns.NextSetup()
    local names = ns.SetupNames()
    if #names == 0 then
        ns.Log("No saved setups yet: save one on the Setups page.")
        return
    end
    local i = 0
    for j, n in ipairs(names) do
        if n == ns.lastSetup then i = j end
    end
    ns.LoadSetup(names[i % #names + 1])
end

-- Presets ----------------------------------------------------------------------
-- Whole starting setups for the Start here page (mockups\options-presets.html is the
-- spec, mockups\options-review.md the decisions). Each sets every setting: the
-- Creator's, the Purist's and the Minimap Replacement's are locked in whole
-- (Data\PresetCreator.lua, PresetPurist.lua, PresetNavigator.lua, by
-- tools\lock_preset.lua; the Creator's is also what the release ships as its
-- defaults), the others start from the Creator's; then the rows below. Where things sit stays yours (POS), and so does what the addon
-- keeps as you play (your notes, ink, folds: EXCLUDE, KEEP_IN).

ns.PRESETS = {
    { id = "creator", name = "Creator's", icon = "Interface\\Icons\\INV_Shield_06",
      who = "How Waymark ships: the author's own settings. Quest givers, turn-ins, objective spots, the tracker and quest log, a framed map that follows you." },
    { id = "purist", name = "Purist", icon = "Interface\\Icons\\INV_Misc_Map_01",
      who = "Classic vanilla: the plain Battlefield Map. No quest marks on it, just the quest tracker and quest window." },
    { id = "navigator", name = "Minimap Replacement", icon = "Interface\\Icons\\Spell_Nature_FarSight",
      who = "Replaces your minimap with a square one, every map feature on it: quest givers, quest ink, the tracker and quest window." },
    { id = "minimalist", name = "Minimalist", icon = "Interface\\Icons\\Spell_Magic_LesserInvisibilty",
      who = "Clear view: no clutter, masked zones, no frame and low footprint." },
}

-- what a value reads as in the list of changes (booleans: on / off)
local ROLES = { window = "a window", clear = "clear view", dock = "over the minimap" }
local FOG = { fog = "fog", sepia = "sepia", ink = "dark ink", faded = "faded", full = "as explored" }
local BORDERS = { game = "the game's", dialog = "classic dialog", gold = "gold", tooltip = "tooltip", wood = "wood",
                  line = "thin line", none = "none" }
local COLOURS = { natural = "as drawn", gold = "gold", bronze = "bronze", silver = "silver", dark = "dark", class = "class colour" }
local PLATES = { plate = "classic plate", tan = "tan leather", stone = "stone", parchment = "parchment", tooltip = "dark",
                 text = "text only" }
local GROUND = { haze = "soft haze", ink = "ink", dots = "dots", pins = "objective pins" }
local GROUND_BY = { quest = "each quest its own", type = "by quest type" }

-- { label, setting ("group.key", or "role": the map as a window, in clear view or
-- docked), names, then the value for each preset in ns.PRESETS' order:
-- creator, purist, navigator, minimalist }
-- (The Creator's column: Lunarbow Wanderer's own settings (live Forever, 2026-11-05),
-- but for arrows to lone spots, off.)
local T, F = true, false
local ROWS = {
    { "The map", "role", ROLES,                          "window", "window", "dock", "clear" },
    { "Quest givers", "questie.shown", nil,                  T, F, T, T },
    { "Coloured by difficulty", "questie.color", nil,        T, F, T, T },
    { "Turn-ins", "turnins.shown", nil,                      T, F, T, T },
    { "Objective spots", "spots.shown", nil,                 T, F, F, F },
    { "A colour per quest", "spots.color", nil,              F, F, F, F },
    { "Quest ground", "ground.shown", nil,                   F, F, T, T },
    { "Its look", "ground.look", GROUND,                 "ink", "ink", "ink", "ink" },
    { "Its colours", "ground.colorBy", GROUND_BY,        "type", "type", "type", "type" },
    { "Arrows to lone spots and turn-ins", "ground.arrows", nil, F, F, F, F },
    { "Objective markers (the game's)", "objectives.shown", nil, F, F, T, T },
    { "Quest areas (the game's)", "areas.shown", nil,        F, F, F, F },
    { "Learned quest givers", "learned.shown", nil,          T, F, T, T },
    { "Quest tracker", "tracker.shown", nil,                 T, T, T, T },
    { "Quest window", "questlog.shown", nil,                 T, T, T, T },
    { "Opens with the quest log key", "questlog.keyL", nil,  T, F, T, T },
    { "Quest givers on the continent", "browse.continentGivers", nil, T, F, T, T },
    { "Townsfolk", "townsfolk.shown", nil,                   F, F, F, F },
    { "Townsfolk in towns and cities", "townsfolkInTown", nil, T, T, T, T },
    { "Dungeon entrances", "dungeons.shown", nil,            T, F, T, T },
    { "Group dots in class colours", "party.classColors", nil, T, F, T, T },
    { "Group tooltips", "party.hover", nil,                  T, F, T, T },
    { "Unexplored areas", "explore.shown", nil,              T, F, T, T },
    { "Their look", "explore.fogStyle", FOG,                 "full", "fog", "full", "full" },
    { "Quest pins hidden there", "explore.hideQuests", nil,  F, F, F, F },
    { "Other pins hidden there", "explore.hideOthers", nil,  F, F, F, F },
    { "Area names under the cursor", "explore.hoverNames", nil, T, F, T, T },
    { "Unexplored names a secret", "explore.hideUnexplored", nil, F, T, F, F },
    { "Gold flash on discovery", "explore.flash", nil,       T, F, T, T },
    { "The zone in the header", "zoneName.showZone", nil,      T, F, T, T },
    { "Explored % in the header", "zoneName.progress", nil,        F, F, F, F },
    { "Level range in the header", "zoneName.levels", nil,         F, F, F, F },
    { "Close-up detail", "detail.shown", nil,                T, F, T, T },
    { "Coordinates", "coords.shown", nil,                    T, F, T, T },
    { "Keep centred on me", "mapFrame.center", nil,          T, F, T, T },
    { "Auto-zoom", "zoom.autoZoom", nil,                     F, F, F, F },
    { "Town view", "townView.enabled", nil,                  T, F, T, T },
    { "Zoom in towns", "townView.zoom", nil,                 T, F, T, T },
    { "Whole city in capitals", "cityView.zoom", nil,        T, F, T, T },
    { "Border", "border.style", BORDERS,                 "dialog", "game", "dialog", "tooltip" },
    { "Border colour", "border.color", COLOURS,          "bronze", "natural", "bronze", "dark" },
    { "Header style", "zoneName.style", PLATES,          "parchment", "plate", "text", "text" },
    { "Fade while moving", "fade.moving", nil,               F, F, F, F },
    { "Fade in combat", "fade.combat", nil,                  F, F, F, F },
    { "Map buttons fade", "toggles.fadeOut", nil,            T, T, T, T },
    { "Line to target", "line.shown", nil,                   T, F, T, T },
}

local function PresetIndex(id)
    for i, p in ipairs(ns.PRESETS) do
        if p.id == id then return i, p end
    end
end

-- a row's value in your settings, or in a saved setup's (db)
local function Get(setting, db)
    db = db or ns.db
    local function G(g) return db[g] or ns.DEFAULTS[g] or {} end
    if setting == "role" then
        return G("dock").on and "dock" or G("clearView").on and "clear" or "window"
    end
    if setting == "townsfolkInTown" then  -- the "in town" context shows them
        local c = G("profiles").city
        return c and c.enabled and c.layers and c.layers.townsfolk == true or false
    end
    local g, k = setting:match("^(%w+)%.(%w+)$")
    local v = G(g)[k]
    if v == nil then v = ns.DEFAULTS[g] and ns.DEFAULTS[g][k] end
    return v
end

-- set a row in settings (db), noting { group, key } changed
local function Put(db, setting, v, changed)
    if setting == "role" then
        for _, gk in ipairs({ { "dock", v == "dock" }, { "clearView", v == "clear" } }) do
            db[gk[1]] = db[gk[1]] or {}
            if db[gk[1]].on ~= gk[2] then
                db[gk[1]].on = gk[2]
                changed[#changed + 1] = { gk[1], "on" }
            end
        end
        return
    end
    if setting == "townsfolkInTown" then  -- off: no override left (the context's own on/off kept)
        db.profiles = db.profiles or {}
        db.profiles.city = db.profiles.city or { enabled = false, hideMap = false, layers = {} }
        local c = db.profiles.city
        c.layers = c.layers or {}
        if v then c.enabled = true end
        c.layers.townsfolk = v or nil
        changed[#changed + 1] = { "profiles" }
        return
    end
    local g, k = setting:match("^(%w+)%.(%w+)$")
    db[g] = db[g] or {}
    db[g][k] = v
    changed[#changed + 1] = { g, k }
end

-- set it in your settings and let that part of the addon know
local function Set(setting, v, changed)
    Put(ns.db, setting, v, changed)
    if setting == "townsfolkInTown" and ns.UpdateProfile then pcall(ns.UpdateProfile) end
end

-- Every other setting ------------------------------------------------------------

-- where things sit and how big: yours, whatever the preset (POS: these names at
-- any depth; MINE: these paths). Looks, fonts and text sizes follow the preset.
local POS = { pos = true, stockPos = true, lootPos = true, buttonPos = true, bigTR = true, bigCorner = true,
              zoneSizes = true, minimap = true, width = true, height = true, bigWidth = true, bigHeight = true,
              bigW = true, bigH = true, bigSize = true, freeHeight = true, maxHeight = true }
local MINE = { scale = true, ["dock.size"] = true, ["questlog.scale"] = true }
-- Keep my quest pins (Start here; on by default with Questie loaded): presets leave which
-- quest pins show, their icons, sizes and colours, and the tooltips as they are
local KEEP_QUEST = {}
for _, p in ipairs({ "questie.shown", "questie.color", "questie.alpha", "questie.scale", "questie.iconSet",
                     "questie.tooltip", "turnins.shown", "turnins.alpha", "turnins.scale", "turnins.iconSet",
                     "spots.shown", "spots.color", "spots.alpha", "spots.scale" }) do
    KEEP_QUEST[p] = true
end
function ns.KeepQuestPins()
    local v = ns.db.keepQuestPins
    if v == nil then return ns.QuestieArt() end
    return v
end
local function KeptQuest(p) return KEEP_QUEST[p] and ns.KeepQuestPins() end
local function Yours(k, p) return POS[k] or MINE[p] or KeptQuest(p) end
-- the paths the rows set (counted as rows, not again as "every other setting")
local ROW_PATHS = { ["dock.on"] = true, ["clearView.on"] = true, ["profiles.city.enabled"] = true,
                    ["profiles.city.layers.townsfolk"] = true }
for _, row in ipairs(ROWS) do ROW_PATHS[row[2]] = true end
-- (after that, so these two still don't count as "every other setting")
for i = #ROWS, 1, -1 do
    if ns.NoGameLayer((ROWS[i][2]:match("^(%w+)%.shown$"))) then table.remove(ROWS, i) end
end

-- the preset's whole settings (nil: its rows only; the file missing)
local function Base(id)
    local all = ns.PRESET_SETTINGS
    return all and (all[id] or all.creator)
end

local function IsList(t)
    local n = #t
    if n == 0 then return false end
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
    end
    return true
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- where things sit and how big in s: yours (db)
local function KeepMine(s, db, path)
    for k, v in pairs(db) do
        local p = path .. "." .. tostring(k)
        if Yours(k, p) then
            s[k] = v
        elseif type(v) == "table" and type(s[k]) == "table" then
            KeepMine(s[k], v, p)
        end
    end
end

-- the preset's whole settings in: only what it carries is replaced (what the
-- addon keeps as you play, dev things, aren't in it and aren't touched)
local function ApplyWhole(base)
    local all = Copy(base)
    for k, v in pairs(all) do
        if EXCLUDE[k] then
            all[k] = nil
        elseif Yours(k, k) then
            all[k] = ns.db[k]
        elseif type(v) == "table" and type(ns.db[k]) == "table" then
            KeepMine(v, ns.db[k], k)
            for x in pairs(KEEP_IN[k] or {}) do v[x] = ns.db[k][x] end
        end
    end
    for k, v in pairs(all) do ns.db[k] = v end
    ns.CopyDefaults(ns.db, ns.DEFAULTS)
    ns.keepSizeOff = true  -- (its scale and its sizes as set: ns.SetScale)
    pcall(ns.ApplyAll)
    ns.keepSizeOff = nil
end

-- the preset's settings as they'd be, rows and defaults in (built once)
local targets = {}
local function Target(i, id)
    if not targets[id] then
        local t = Copy(Base(id))
        for k, v in pairs(ns.DEFAULTS) do  -- (settings newer than the locked file)
            if type(v) == "table" and type(t[k]) == "table" then ns.CopyDefaults(t[k], v) end
        end
        for _, row in ipairs(ROWS) do Put(t, row[2], row[3 + i], {}) end
        targets[id] = t
    end
    return targets[id]
end

-- how many settings outside the rows differ from the preset's (list: each one's
-- { path, preset's, yours } added to it)
local function Differs(t, db, path, n, list)
    for k, v in pairs(t) do
        local p = path and (path .. "." .. tostring(k)) or tostring(k)
        if not Yours(k, p) and not ROW_PATHS[p] and not (path == nil and EXCLUDE[k])
            and not (path and KEEP_IN[path] and KEEP_IN[path][k]) then
            local d
            if type(db) == "table" then d = db[k] end
            if type(v) == "table" and not IsList(v) then
                n = Differs(v, d, p, n, list)
            elseif not Same(v, d) then
                n = n + 1
                if list then list[#list + 1] = { p, v, d } end
            end
        end
    end
    return n
end

local function Reads(row, v)
    if type(v) == "boolean" then return v and "on" or "off" end
    return row[3] and row[3][v] or tostring(v)
end

-- The presets you make yourself: a changed preset saved under a name (a setup,
-- listed in My()[name] = the built-in preset it came from, for its icon).
-- ns.db.presetBase: the preset (or "my:<name>") last applied, nil while the
-- settings are your own; its card says "current", its name "(altered)" once a
-- row differs. Your own settings aren't saved for you: that's the Setups page.
local function My()
    ns.db.myPresets = ns.db.myPresets or {}
    return ns.db.myPresets
end

-- the setup behind one of your presets ("my:<name>"), if it's there
local function SetupOf(id)
    local name = type(id) == "string" and id:match("^my:(.+)$")
    return name and My()[name] and ns.db.setups[name], name
end

-- your own presets: { { id = "my:<name>", name, base }, ... } by name
function ns.MyPresets()
    local out = {}
    for name, base in pairs(My()) do
        if ns.db.setups[name] then
            out[#out + 1] = { id = "my:" .. name, name = name, base = base }
        else
            My()[name] = nil  -- (deleted on the Setups page)
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

-- what using the preset would change from your settings now:
-- { { label, now, then }, ... } (in words), empty when you have it already
function ns.PresetChanges(id)
    local i = PresetIndex(id)
    local s = SetupOf(id)
    local out = {}
    if not (i or s) then return out end
    for _, row in ipairs(ROWS) do
        local want, now = row[3 + (i or 0)], Get(row[2])
        if s then want = Get(row[2], s) end
        if not KeptQuest(row[2])
            and ((now and true or false) ~= (want and true or false) or (type(want) == "string" and now ~= want)) then
            out[#out + 1] = { row[1], Reads(row, now), Reads(row, want) }
        end
    end
    if i and Base(id) then
        local list = {}
        local n = Differs(Target(i, id), ns.db, nil, 0, list)
        if n > 0 then
            table.sort(list, function(a, b) return a[1] < b[1] end)
            out[#out + 1] = { "Minor setting differences", text = n .. " from " .. ns.PRESETS[i].name, list = list }
        end
    end
    return out
end

-- the preset set (a built-in one: every setting, then its rows), each part of
-- the addon told
local function SetRows(id)
    local i = PresetIndex(id)
    local s = SetupOf(id)
    local changed = {}
    if i and Base(id) then
        ApplyWhole(Base(id))
    end
    for _, row in ipairs(ROWS) do
        local want = row[3 + (i or 0)]
        if s then want = Get(row[2], s) end
        if not KeptQuest(row[2]) and Get(row[2]) ~= want then Set(row[2], want, changed) end
    end
    for _, gk in ipairs(changed) do pcall(ns.OnSettingChanged, gk[1], gk[2]) end
    pcall(ns.RedrawAll)
end

local function NameOf(id)
    local _, p = PresetIndex(id)
    if p then return p.name end
    return type(id) == "string" and id:match("^my:(.+)$") or tostring(id)
end
ns.PresetName = NameOf

-- Use a preset: built in (every setting) or "my:<name>" (one of yours: the whole
-- setup, positions and sizes too). Nothing is saved first. True if applied.
function ns.ApplyPreset(id)
    local s, name = SetupOf(id)
    if not (s or PresetIndex(id)) or #ns.PresetChanges(id) == 0 then return false end
    if s then
        ns.LoadSetup(name)
    else
        SetRows(id)
        ns.lastSetup = nil
    end
    ns.db.presetBase = id
    ns.Log("Applied " .. NameOf(id) .. ".")
    return true
end

-- The preset you're on, its rows put back (nothing saved, nothing else changed)
function ns.RestorePreset(id)
    if not (SetupOf(id) or PresetIndex(id)) then return false end
    SetRows(id)
    ns.db.presetBase = id
    ns.lastSetup = SetupOf(id) and id:sub(4) or nil
    ns.Log("Restored " .. NameOf(id) .. ".")
    return true
end

-- Your settings now, kept as a preset of your own under a name (a setup, and a
-- card on Start here); then the preset you were on put back (restore). Saving
-- under its own name again updates it.
function ns.SavePresetAs(name, restore)
    name = name and strtrim(name) or ""
    if name == "" then return false end
    local from = ns.db.presetBase
    local base = from and (from:match("^my:") and My()[from:sub(4)] or from) or "own"
    ns.db.presetBase = "my:" .. name
    My()[name] = base
    ns.SaveSetup(name)
    ns.Log("Saved your preset \"" .. name .. "\": it's a card on Start here, and on the Setups page.")
    if restore and from and from ~= "my:" .. name then ns.RestorePreset(from) else ns.lastSetup = name end
    return true
end

-- Writing and reading the text -----------------------------------------------------

local function Escape(s)
    return (s:gsub("[%c\"\\]", function(c)
        if c == "\n" then return "\\n" end
        if c == "\"" or c == "\\" then return "\\" .. c end
        return string.format("\\%03d", c:byte())
    end))
end

local function Write(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local val = v[k]
            local tv = type(val)
            if tv == "table" or tv == "string" or tv == "number" or tv == "boolean" then
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    out[#out + 1] = k .. "="
                elseif type(k) == "string" then
                    out[#out + 1] = "[\"" .. Escape(k) .. "\"]="
                else
                    out[#out + 1] = "[" .. tostring(k) .. "]="
                end
                Write(val, out)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = "\"" .. Escape(v) .. "\""
    elseif t == "number" then
        out[#out + 1] = (v == math.floor(v)) and string.format("%d", v) or string.format("%.4f", v):gsub("0+$", "")
    else
        out[#out + 1] = tostring(v)
    end
end

-- A reader for exactly what Write makes: tables, strings, numbers, true/false
local function Read(text)
    local pos, depth = 1, 0
    local function fail(msg) error({ bfi = msg .. " (at " .. pos .. ")" }) end
    local function skip() pos = text:find("[^%s]", pos) or (#text + 1) end
    local value
    local function str()
        pos = pos + 1
        local buf = {}
        while true do
            local c = text:sub(pos, pos)
            if c == "" then fail("unfinished text") end
            if c == "\"" then pos = pos + 1 break end
            if c == "\\" then
                local n = text:sub(pos + 1, pos + 1)
                if n == "n" then buf[#buf + 1] = "\n" pos = pos + 2
                elseif n == "\"" or n == "\\" then buf[#buf + 1] = n pos = pos + 2
                elseif n:match("%d") then
                    local d = text:match("^%d%d?%d?", pos + 1)
                    buf[#buf + 1] = string.char(tonumber(d) % 256)
                    pos = pos + 1 + #d
                else fail("bad escape") end
            else
                buf[#buf + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(buf)
    end
    local function tbl()
        depth = depth + 1
        if depth > 20 then fail("too deep") end
        pos = pos + 1
        local t = {}
        while true do
            skip()
            local c = text:sub(pos, pos)
            if c == "}" then pos = pos + 1 break end
            local key
            if c == "[" then
                pos = pos + 1
                skip()
                key = value()
                skip()
                if text:sub(pos, pos) ~= "]" then fail("expected ]") end
                pos = pos + 1
            else
                key = text:match("^[%a_][%w_]*", pos)
                if not key then fail("expected a name") end
                pos = pos + #key
            end
            skip()
            if text:sub(pos, pos) ~= "=" then fail("expected =") end
            pos = pos + 1
            skip()
            t[key] = value()
            skip()
            if text:sub(pos, pos) == "," then pos = pos + 1 end
        end
        depth = depth - 1
        return t
    end
    value = function()
        skip()
        local c = text:sub(pos, pos)
        if c == "{" then return tbl() end
        if c == "\"" then return str() end
        if text:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
        if text:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
        local num = text:match("^%-?%d+%.?%d*", pos)
        if num then
            pos = pos + #num
            return tonumber(num)
        end
        fail("unexpected \"" .. c .. "\"")
    end
    local ok, result = pcall(value)
    if not ok then return nil, type(result) == "table" and result.bfi or tostring(result) end
    return result
end

-- what's in the string besides the settings: its name, and where it came from
local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

function ns.ExportString(name)
    local s = name and ns.db.setups[name] or Snapshot()
    local out = {}
    Write({
        name = name,
        version = GetMeta and GetMeta(addonName, "Version") or nil,
        edition = ns.EDITION,
        settings = s,
    }, out)
    local packed = LibDeflate:CompressDeflate(table.concat(out), { level = 9 })
    return PREFIX .. LibDeflate:EncodeForPrint(packed)
end

-- What's been learned as you play, as a string to share (Learn.lua's data)
function ns.LearnedExportString()
    local out = {}
    Write({ version = GetMeta and GetMeta(addonName, "Version") or nil,
            learned = ns.LearnedShareData and ns.LearnedShareData() or {} }, out)
    local packed = LibDeflate:CompressDeflate(table.concat(out), { level = 9 })
    return LEARNED_PREFIX .. LibDeflate:EncodeForPrint(packed)
end

-- The learned strings in a paste, any number of them one after another (as players
-- send them: a Discord thread copied whole): { data, ... } and what's in them, or nil
-- (no learned string at all) or nil and why (none of them could be read).
function ns.ParseLearned(text)
    text = text or ""
    if not text:find(LEARNED_PREFIX, 1, true) then return nil end
    local function Count(v)
        local n = 0
        for _ in pairs(type(v) == "table" and v or {}) do n = n + 1 end
        return n
    end
    local list, info, bad = {}, { givers = 0, quests = 0, mobs = 0, strings = 0, bad = 0 }, nil
    -- (each string is one unbroken run of letters, digits and brackets: words after it,
    -- "thanks!", aren't part of it)
    for body in text:gmatch(LEARNED_PREFIX:gsub("%p", "%%%0") .. "([%w%(%)]*)") do
        local packed = LibDeflate:DecodeForPrint(body)
        local plain = packed and LibDeflate:DecompressDeflate(packed)
        local t = plain and Read(plain)
        if type(t) == "table" and type(t.learned) == "table" then
            local d = t.learned
            list[#list + 1] = d
            info.strings = info.strings + 1
            info.givers = info.givers + Count(d.givers)
            info.quests = info.quests + Count(d.quests)
            info.mobs = info.mobs + Count(d.mobs)
        else
            info.bad = info.bad + 1
            bad = "The string is cut short or changed: copy all of it again."
        end
    end
    if #list == 0 then return nil, bad or "unreadable" end
    return list, info
end

-- other addons' strings, to say so instead of "unreadable"
local OTHERS = {
    { "!BBF", "BetterBlizzFrames" }, { "!BBP", "BetterBlizzPlates" }, { "!WA:", "WeakAuras" },
    { "!PLATER", "Plater" }, { "!E1!", "ElvUI" },
}

-- the settings in an export string and what it says about itself, or nil and why not
function ns.ParseExport(text)
    text = text and strtrim(text) or ""
    if text == "" then return nil, "" end
    local s, info
    if text:sub(1, #PREFIX) == PREFIX then
        -- (a .txt or a chat may have broken it into lines)
        local packed = LibDeflate:DecodeForPrint((text:sub(#PREFIX + 1):gsub("%s", "")))
        local plain = packed and LibDeflate:DecompressDeflate(packed)
        if not plain then return nil, "The string is cut short or changed: copy all of it again." end
        local t, err = Read(plain)
        if type(t) ~= "table" or type(t.settings) ~= "table" then return nil, err or "unreadable" end
        s = t.settings
        info = { name = type(t.name) == "string" and t.name or nil,
                 version = type(t.version) == "string" and t.version or nil,
                 edition = type(t.edition) == "string" and t.edition or nil }
    elseif text:sub(1, #OLD_PREFIX) == OLD_PREFIX then
        local err
        s, err = Read(text:sub(#OLD_PREFIX + 1))
        if type(s) ~= "table" then return nil, err or "unreadable" end
        info = {}
    else
        for _, o in ipairs(OTHERS) do
            if text:sub(1, #o[1]) == o[1] then
                return nil, "That's a " .. o[2] .. " string, not a Waymark setup."
            end
        end
        return nil, "Not a Waymark setup (those start with " .. PREFIX .. ")."
    end
    -- only the settings groups this version knows
    local groups = 0
    for k in pairs(s) do
        if EXCLUDE[k] or ns.DEFAULTS[k] == nil then s[k] = nil else groups = groups + 1 end
    end
    if groups == 0 then return nil, "There are no settings in it." end
    info.groups = groups
    return s, info
end

-- saveAs: keep it under that name (and load it if use); without: just use it
function ns.ImportString(text, saveAs, use)
    local s, err = ns.ParseExport(text)
    if not s then return false, err end
    saveAs = saveAs and strtrim(saveAs) or ""
    if saveAs ~= "" then
        ns.db.setups[saveAs] = s
        if use then ns.LoadSetup(saveAs) end
    else
        Apply(s)
    end
    return true
end

-- Per character --------------------------------------------------------------------

-- ns.db.characters["Name - Realm"] = { settings, class, time }: written as the
-- character logs out (and on /reload), so another character can copy them exactly.
-- WaymarkCharDB.loaded: the setup this character loaded last (for "(loaded)").

local function Me()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

function ns.CharSetup()
    WaymarkCharDB = WaymarkCharDB or {}
    return WaymarkCharDB
end

-- the other characters with settings kept, by name
function ns.CharacterNames()
    local me, names = Me(), {}
    for name in pairs(ns.db.characters) do
        if name ~= me then names[#names + 1] = name end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function ns.CharacterInfo(name)
    return ns.db.characters[name]
end

function ns.CopyCharacter(name)
    local ch = ns.db.characters[name]
    if not ch or type(ch.settings) ~= "table" then return false end
    Apply(ch.settings)
    ns.lastSetup = nil
    ns.Log("Copied the settings of " .. name .. ".")
    return true
end

function ns.ForgetCharacter(name)
    ns.db.characters[name] = nil
end

function ns.SetupSetups()
    -- the presets' first "Before <preset>" setups (2026-10-31) held the preset used
    -- before, not your own settings: cleared once (the user asked)
    if not ns.db.beforeCleared then
        for name in pairs(ns.db.setups) do
            if name:match("^Before The .+") then ns.db.setups[name] = nil end
        end
        ns.db.beforeCleared = true
    end
    local c = ns.CharSetup()
    local mine = ns.db.characters[Me()]
    if mine and type(mine.settings) == "table" then
        -- this character's own settings, as it left them
        Apply(mine.settings)
    elseif c.setup and ns.db.setups[c.setup] then
        -- (before characters kept their own: the setup it was linked to)
        Apply(ns.db.setups[c.setup])
    end
    -- (else, a character's first time: it starts from the settings last in use)
    -- a preset since removed (the Explorer, the Tactician, 2026-11-03): no preset applied then
    local base = ns.db.presetBase
    if type(base) == "string" and not base:match("^my:") and not PresetIndex(base) then ns.db.presetBase = nil end
    c.setup, c.autoSave = nil, nil
    ns.lastSetup = c.loaded
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function()
        c.loaded = ns.lastSetup
        ns.db.characters[Me()] = { settings = Snapshot(), class = select(2, UnitClass("player")), time = time() }
    end)
end

-- Export and import windows ----------------------------------------------------------------
-- As other addons share profiles: Export shows the string selected, ready for Ctrl+C;
-- Import is an empty box to paste into, which says what it found before you import.

local function SizeText(n)
    return n < 1024 and (n .. " characters") or string.format("%.1f KB", n / 1024)
end

local function Window(name, title, height)
    local w = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    ns.AddonWindow(w)
    w:SetSize(480, height)
    w:SetPoint("CENTER")
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetToplevel(true)
    w:SetMovable(true)
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    tinsert(UISpecialFrames, name)
    if w.TitleText then w.TitleText:SetText(title) end

    w.what = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.what:SetPoint("TOPLEFT", 16, -32)
    w.what:SetPoint("TOPRIGHT", -16, -32)
    w.what:SetJustifyH("LEFT")

    -- the text box, on a dark field like the game's own edit boxes
    local field = CreateFrame("Frame", nil, w, "BackdropTemplate")
    field:SetPoint("TOPLEFT", 12, -52)
    field:SetPoint("BOTTOMRIGHT", -12, 96)
    if field.SetBackdrop then
        field:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                            edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        field:SetBackdropColor(0, 0, 0, 0.6)
        field:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    local scroll = CreateFrame("ScrollFrame", nil, field, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetMaxLetters(0)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontSmall or GameFontHighlightSmall)
    box:SetWidth(410)
    box:SetScript("OnEscapePressed", function() w:Hide() end)
    box:SetScript("OnCursorChanged", function(_, _, y, _, h)
        -- (keep the cursor in view)
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight()
        y = -y
        if y < top then scroll:SetVerticalScroll(y)
        elseif y + h > top + view then scroll:SetVerticalScroll(y + h - view) end
    end)
    scroll:SetScrollChild(box)
    -- a click anywhere in the field goes to the text
    field:EnableMouse(true)
    field:SetScript("OnMouseDown", function() box:SetFocus() end)
    w.box = box

    w.status = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.status:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 4, -6)
    w.status:SetPoint("TOPRIGHT", field, "BOTTOMRIGHT", -4, -6)
    w.status:SetJustifyH("LEFT")
    w.status:SetJustifyV("TOP")
    w.status:SetHeight(28)

    local close = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    close:SetSize(90, 22)
    close:SetPoint("BOTTOMRIGHT", -14, 14)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() w:Hide() end)
    w:Hide()
    return w
end

local exportWin, importWin

local function BuildExport()
    local w = Window("WaymarkExport", "Export setup", 320)
    -- read only: whatever is typed, the string comes back (and stays selected)
    w.box:SetScript("OnTextChanged", function(self, user)
        if user and w.text then
            self:SetText(w.text)
            self:HighlightText()
        end
    end)
    w.box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    w.box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    local all = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    all:SetSize(110, 22)
    all:SetPoint("BOTTOMLEFT", 14, 14)
    all:SetText("Select all")
    all:SetScript("OnClick", function() w.box:SetFocus() w.box:HighlightText() end)
    local hint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 46)
    hint:SetPoint("BOTTOMRIGHT", -16, 46)
    hint:SetJustifyH("LEFT")
    hint:SetText("Paste it anywhere: Discord sends a long one as a .txt file, which imports just the same.")
    exportWin = w
end

local function BuildImport()
    local w = Window("WaymarkImport", "Import setup", 340)
    w.what:SetText("Paste a setup string, or learned quests and monsters, below (Ctrl+V)")

    local label = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", 18, 54)
    label:SetText("Save as")
    local name = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    name:SetSize(170, 20)
    name:SetPoint("LEFT", label, "RIGHT", 10, 0)
    name:SetAutoFocus(false)
    name:SetMaxLetters(40)
    w.name = name
    local use = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
    use:SetSize(24, 24)
    use:SetPoint("LEFT", name, "RIGHT", 10, 0)
    use:SetChecked(true)
    local useText = use:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    useText:SetPoint("LEFT", use, "RIGHT", 2, 1)
    useText:SetText("Use it now")

    local import = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    import:SetSize(110, 22)
    import:SetPoint("BOTTOMLEFT", 14, 14)
    import:SetText("Import")
    w.import = import

    -- what the pasted text is, as soon as it's there
    local function Check()
        local learned, linfo = ns.ParseLearned(w.box:GetText())
        w.learned = learned
        if learned or linfo then
            import:SetEnabled(learned ~= nil)
            local from = learned and (linfo.strings > 1 and (linfo.strings .. " learned strings") or "Learned quests and monsters")
            w.status:SetText(learned and ("|cff33ff33" .. from .. "|r: " .. linfo.givers .. " quest givers, "
                .. linfo.quests .. " quests, " .. linfo.mobs .. " monsters. Importing adds them to yours."
                .. (linfo.bad > 0 and ("\n|cffffd200" .. linfo.bad .. " more couldn't be read (cut short?).|r") or ""))
                or ("|cffff5555" .. linfo .. "|r"))
            return
        end
        local s, info = ns.ParseExport(w.box:GetText())
        import:SetEnabled(s ~= nil)
        if not s then
            w.status:SetText(info ~= "" and ("|cffff5555" .. info .. "|r")
                or "A .txt from Discord: open it, select all, copy, and paste here.")
            return
        end
        local from = info.version and ("Waymark " .. info.version) or "Waymark"
        if info.edition and info.edition ~= "?" then from = from .. " (" .. info.edition .. ")" end
        if info.name and not w.named then name:SetText(info.name) end
        local line = "|cff33ff33" .. (info.name and ("\"" .. info.name .. "\"") or "A setup")
                     .. "|r from " .. from .. ", " .. info.groups .. " groups of settings."
        local n = strtrim(name:GetText() or "")
        if n ~= "" and ns.db.setups[n] then
            line = line .. "\n|cffffd200Importing replaces your setup \"" .. n .. "\".|r"
        end
        w.status:SetText(line)
    end
    w.box:SetScript("OnTextChanged", function(_, user) if user then Check() end end)
    name:SetScript("OnTextChanged", function(_, user)
        if user then
            w.named = true
            Check()
        end
    end)
    name:SetScript("OnEnterPressed", function() import:Click() end)
    name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    import:SetScript("OnClick", function()
        if w.learned then
            local g, q, m = 0, 0, 0
            for _, d in ipairs(w.learned) do
                if ns.MergeLearned then
                    local a, b, c = ns.MergeLearned(d)
                    g, q, m = g + a, q + b, m + c
                end
            end
            ns.Log("Took in what someone learned: " .. g .. " new quest givers, " .. q .. " quests, " .. m .. " monsters.")
            pcall(ns.RefreshControls)
            w:Hide()
            return
        end
        local n = strtrim(name:GetText() or "")
        if n == "" then
            w.status:SetText("|cffff5555Type a name for it first.|r")
            name:SetFocus()
            return
        end
        local ok, err = ns.ImportString(w.box:GetText(), n, use:GetChecked())
        if not ok then
            w.status:SetText("|cffff5555" .. err .. "|r")
            return
        end
        ns.Log("Imported setup \"" .. n .. "\"" .. (use:GetChecked() and ", now in use." or "."))
        pcall(ns.RefreshControls)
        w:Hide()
    end)
    w.Check = Check
    importWin = w
end

-- name: export that saved setup (nil: what's in use now)
function ns.ShowExport(name)
    if not exportWin then BuildExport() end
    if importWin then importWin:Hide() end
    local w = exportWin
    w.text = ns.ExportString(name)
    w.what:SetText(name and ("Setup \"" .. name .. "\"") or "Your settings as they are now")
    w.box:SetText(w.text)
    w.status:SetText("Press |cffffffffCtrl+C|r to copy it (" .. SizeText(#w.text) .. ").")
    w:Show()
    w.box:SetFocus()
    w.box:HighlightText()
end

-- what's been learned as you play, to share (the Setups page's button)
function ns.ShowLearnedExport()
    if not exportWin then BuildExport() end
    if importWin then importWin:Hide() end
    local w = exportWin
    w.text = ns.LearnedExportString()
    w.what:SetText("Learned quests and monsters (quest givers, their quests, monster spots)")
    w.box:SetText(w.text)
    w.status:SetText("Press |cffffffffCtrl+C|r to copy it (" .. SizeText(#w.text) .. "). Whoever imports it adds it to theirs.")
    w:Show()
    w.box:SetFocus()
    w.box:HighlightText()
end

function ns.ShowImport()
    if not importWin then BuildImport() end
    if exportWin then exportWin:Hide() end
    local w = importWin
    w.box:SetText("")
    w.name:SetText("")
    w.named = nil
    w.import:SetEnabled(false)
    w.Check()
    w:Show()
    w.box:SetFocus()
end

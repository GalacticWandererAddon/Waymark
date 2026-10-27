local _, ns = ...

-- Townsfolk on the Battlefield Map: innkeepers, flight masters, trainers, vendors...
-- Who and where comes from QuestieDB (which NPCs are which type: QuestData.lua's
-- ns.TownsfolkIds; each NPC's spawn points), and from our own, learned as you
-- play (below; shown with townsfolk.useLearned, and then without QuestieDB too).
-- Icons are Blizzard's own minimap tracking art where it exists. Same-type
-- townsfolk close together share one pin listing them all (townsfolk.mergeYards).

local TEMPLATE = "BFITownsfolkPinTemplate"
local TRACKING = "Interface\\Minimap\\tracking\\"
local MEDIA = "Interface\\AddOns\\BattlefieldInfo\\Media\\"

-- key = townsfolk/vendor type (QuestData.lua sorts NPCs into these); icon =
-- Blizzard art, or our own in the tracking style where Blizzard has no tracking
-- icon for it (Media\Vendor*.tga, drawn by tools\vendor_icons.py)
ns.TOWNSFOLK_TYPES = {
    services = {
        { key = "Repair",         label = "Repair",          icon = TRACKING .. "repair" },
        { key = "Innkeeper",      label = "Innkeeper",       icon = TRACKING .. "innkeeper" },
        { key = "Mailbox",        label = "Mailbox",         icon = TRACKING .. "mailbox", object = true },
        { key = "Flight Master",  label = "Flight master",   icon = TRACKING .. "flightmaster" },
        { key = "Stable Master",  label = "Stable master",   icon = TRACKING .. "stablemaster" },
        { key = "Auctioneer",     label = "Auctioneer",      icon = TRACKING .. "auctioneer" },
        { key = "Banker",         label = "Banker",          icon = TRACKING .. "banker" },
        { key = "Battlemaster",   label = "Battlemaster",    icon = TRACKING .. "battlemaster" },
        { key = "Spirit Healer",  label = "Spirit healer",   icon = "Interface\\RaidFrame\\Raid-Icon-Rez" },
        { key = "Class Trainer",  label = "Class trainer",   icon = TRACKING .. "class" },
        { key = "Weapon Master",  label = "Weapon master",   icon = "Interface\\Icons\\INV_Sword_04" },
        { key = "Portal Trainer", label = "Portal trainer",  icon = "Interface\\Minimap\\Vehicle-AllianceMagePortal" },
    },
    vendors = {
        { key = "Food",        label = "Food & drink",  icon = TRACKING .. "food" },
        { key = "Ammo",        label = "Ammo",          icon = TRACKING .. "ammunition" },
        { key = "Reagents",    label = "Reagents",      icon = TRACKING .. "reagents" },
        { key = "Poisons",     label = "Poisons",       icon = TRACKING .. "poisons" },
        { key = "General",     label = "General goods", icon = MEDIA .. "VendorGeneral" },
        { key = "Trade Goods", label = "Trade goods",   icon = MEDIA .. "VendorTradeGoods" },
        { key = "Potions",     label = "Potions",       icon = MEDIA .. "VendorPotions" },
    },
}
local PROFESSION_ICON = TRACKING .. "profession"

-- vendor lists depend on level; QuestData.lua re-sorts them on level-up
local LEVEL_DEPENDENT = { Food = true, Ammo = true }

-- One pin per NPC: someone who is several of these at once (an innkeeper
-- selling food, a general supplier with arrows) is drawn as the first of its
-- types that's ticked, in this order; the tooltip lists the others. Services
-- before vendors, then the vendor most people look for first.
local PIN_ORDER = {
    "Flight Master", "Innkeeper", "Banker", "Auctioneer", "Stable Master", "Battlemaster", "Spirit Healer",
    "Class Trainer", "Weapon Master", "Portal Trainer", "professions", "Repair",
    "Ammo", "Reagents", "Poisons", "General", "Food", "Trade Goods", "Potions",
}
local PIN_RANK = {}
for i, key in ipairs(PIN_ORDER) do PIN_RANK[key] = i end
local function PinRank(key)
    if type(key) == "number" then key = "professions" end  -- (a profession's trainers)
    return PIN_RANK[key] or #PIN_ORDER + 1
end

-- older learned townsfolk were filed under types since folded into others
local LEARNED_AS = { Food = "Drink", General = "Bags" }

local function Cfg() return ns.db.townsfolk end

-- Index ---------------------------------------------------------------------

-- cache[key] = { [uiMapID] = { {x=, y=, id=, name=, sub=}, ... } }
local cache = {}
local building = {}  -- keys waiting to be indexed
local notReadyUntil = {}  -- key -> time; QuestieDB's types weren't sorted yet
local builder        -- coroutine doing the indexing

local iconByKey = {}
for _, list in pairs(ns.TOWNSFOLK_TYPES) do
    for _, t in ipairs(list) do iconByKey[t.key] = t end
end

local function Add(index, entry)
    return function(uiMapID, x, y)
        local list = index[uiMapID]
        if not list then list = {} index[uiMapID] = list end
        list[#list + 1] = { x = x, y = y, id = entry.id, name = entry.name, sub = entry.sub }
    end
end

local function BuildKey(key)
    local L = ns.QDB and ns.QDB()
    local ids = L and ns.TownsfolkIds(key)
    if not ids then return nil end  -- not ready: try later
    local isObject = iconByKey[key] and iconByKey[key].object

    local index, n = {}, 0
    for _, id in ipairs(ids) do
        if isObject then
            ns.EachSpawnOnMap(L.Object.spawns(id), Add(index, { id = id, name = L.Object.name(id) }))
        else
            local entry = { id = id, name = L.Npc.name(id), sub = L.Npc.subName(id) }
            local spawns = L.Npc.spawns(id)
            if spawns and next(spawns) then
                ns.EachSpawnOnMap(spawns, Add(index, entry))
            else
                -- NPCs that only walk a path: its first point
                for areaID, paths in pairs(L.Npc.waypoints(id) or {}) do
                    local first = paths[1] and paths[1][1]
                    if first then ns.EachSpawnOnMap({ [areaID] = { first } }, Add(index, entry)) end
                end
            end
        end
        n = n + 1
        if n % 40 == 0 then coroutine.yield() end  -- spread the work over frames
    end
    return index
end

local driver = CreateFrame("Frame")

local current  -- key being indexed, for error messages

local function RunBuilder()
    if builder and coroutine.status(builder) ~= "dead" then return end
    -- no pcall in here: Lua 5.1 can't yield across one. Errors surface from
    -- coroutine.resume below instead.
    builder = coroutine.create(function()
        while true do
            local key = next(building)
            if key == nil then return end
            building[key] = nil
            current = key
            local index = BuildKey(key)
            if index then
                cache[key] = index
            else
                -- not sorted yet: don't ask again for a few seconds, or
                -- draw -> request -> draw would loop every frame
                notReadyUntil[key] = GetTime() + 5
            end
        end
    end)
    driver:SetScript("OnUpdate", function()
        local ok, err = coroutine.resume(builder)
        if not ok then ns.Log("Townsfolk index error (" .. tostring(current) .. "):", err) end
        if coroutine.status(builder) == "dead" then
            driver:SetScript("OnUpdate", nil)
            -- an error stops this run; carry on with whatever is still queued
            if next(building) then RunBuilder() end
            if ns.RedrawTownsfolk then ns.RedrawTownsfolk() end
        end
    end)
end

local function Request(key)
    if cache[key] or building[key] then return end
    if notReadyUntil[key] and GetTime() < notReadyUntil[key] then return end
    building[key] = true
    RunBuilder()
end

-- level-up changes which food/drink/ammo vendors are relevant; QuestData.lua
-- re-sorts its lists when next asked, so re-index a few seconds later
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function()
    C_Timer.After(5, function()
        for key in pairs(LEVEL_DEPENDENT) do cache[key] = nil end
        if ns.RedrawTownsfolk then ns.RedrawTownsfolk() end
    end)
end)

-- How many kinds of service NPC (inn, flight, repair, stable, mail, bank,
-- auction) have one within `yards` of a point on a map: kinds, not NPCs, so a
-- lone camp of three repair vendors isn't a town. Also returns what it found
-- ("Innkeeper Belm 40 yd, ..."), for the Town view page and /bfi town. For
-- "in town"; indexes these types in the background even when the Townsfolk
-- layer is off.
local TOWN_KEYS = { "Innkeeper", "Flight Master", "Repair", "Stable Master", "Mailbox", "Banker", "Auctioneer" }
function ns.TownServicesNear(mapID, px, py, yards)
    local w, h
    if ns.MapYards then w, h = ns.MapYards(mapID) end
    if not w then return 0, "", false end
    local kinds, found, r2 = 0, {}, yards * yards
    local ready = true  -- (every kind indexed: "none near" can be trusted)
    for _, key in ipairs(TOWN_KEYS) do
        local index = cache[key]
        if index then
            local best, bestP
            for _, p in ipairs(index[mapID] or {}) do
                local dx, dy = (p.x - px) * w, (p.y - py) * h
                local d2 = dx * dx + dy * dy
                if d2 <= r2 and (not best or d2 < best) then best, bestP = d2, p end
            end
            if best then
                kinds = kinds + 1
                found[#found + 1] = string.format("%s %s %d yd", key, bestP.name or "?", math.sqrt(best))
            end
        else
            ready = false
            Request(key)
        end
    end
    return kinds, table.concat(found, ", "), ready
end

-- Which townsfolk show: the settings with `types` and `myProfessionsOnly`. In
-- town or city view with its own list on (townView/cityView.ownTypes), that
-- list; it starts as a copy of the map's the first time.
function ns.TownsfolkSettings()
    if ns.db.cityView.ownTypes and ns.InCityView and ns.InCityView() then return ns.TownTownsfolk("cityView") end
    if ns.db.townView.ownTypes and ns.InTownView and ns.InTownView() then return ns.TownTownsfolk() end
    return Cfg()
end

-- town (or city) view's own list (for the Town view / City view pages too)
function ns.TownTownsfolk(view)
    local tv = ns.db[view or "townView"]
    if not tv.typesCopied then
        for k, v in pairs(Cfg().types) do tv.types[k] = v end
        tv.myProfessionsOnly = Cfg().myProfessionsOnly
        tv.typesCopied = true
    end
    return tv
end

-- which keys are switched on, with the icon each uses
local function EnabledKeys()
    local c = ns.TownsfolkSettings()
    local out = {}
    for _, list in pairs(ns.TOWNSFOLK_TYPES) do
        for _, t in ipairs(list) do
            if c.types[t.key] then out[#out + 1] = { key = t.key, icon = t.icon, label = t.label } end
        end
    end
    if c.types.professions then
        local mine = c.myProfessionsOnly and ns.MyProfessionIDs and ns.MyProfessionIDs() or nil
        for profKey in pairs(ns.PROFESSION_TRAINER_IDS or {}) do
            if not mine or mine[profKey] then
                out[#out + 1] = { key = profKey, icon = PROFESSION_ICON, label = "Profession trainer" }
            end
        end
        -- the learned ones, all professions in one (they know theirs by name)
        out[#out + 1] = { key = "professions", icon = PROFESSION_ICON, label = "Profession trainer",
                          learnedOnly = true, myProfessionsOnly = c.myProfessionsOnly }
    end
    return out
end

-- Learned townsfolk ---------------------------------------------------------

-- Townsfolk learned as you play, kept account-wide next to the learned quest
-- givers (BattlefieldInfoQuestDB.townsfolk, Learn.lua): talking to a vendor,
-- trainer, flight master, banker... records who it is and, from where you
-- stand, about where. Vendors get their types from what they sell.
--
-- townsfolk = { [key] = { name, faction = "Alliance"|"Horde"|nil (neutral),
--               class = classFile (class trainers), prof = skill line name
--               (profession trainers), types = { [type key] = true },
--               spots = { [uiMapID] = { x, y, n } } } }
-- key: "c<npcID>"; a mailbox has no ID of its own: "m<n>", one per spot
local MAX_N = 12           -- visits averaged into a spot (as Learn.lua's)
local MAILBOX_YARDS = 15   -- a mailbox this close to a known one is that one

local function LDB()
    BattlefieldInfoQuestDB = BattlefieldInfoQuestDB or {}
    local db = BattlefieldInfoQuestDB
    db.townsfolk = db.townsfolk or {}
    return db.townsfolk
end

local learnedChanged = false

-- where you stand, averaged into the spots already known
local function AddSpots(e)
    for mapID, p in pairs(ns.PlayerSpots and ns.PlayerSpots() or {}) do
        local s = e.spots[mapID]
        if not s then
            e.spots[mapID] = { p[1], p[2], 1 }
        else
            local n = math.min(s[3], MAX_N)
            s[1] = (s[1] * n + p[1]) / (n + 1)
            s[2] = (s[2] * n + p[2]) / (n + 1)
            s[3] = s[3] + 1
        end
    end
end

-- the NPC you're talking to, by ID (nil: an object, an item, yourself)
local function NpcID()
    local ok, kind, id = pcall(function()
        local guid = UnitGUID("npc")
        if not guid then return end
        local k, _, _, _, _, i = strsplit("-", guid)
        return k, i
    end)
    if ok and (kind == "Creature" or kind == "Vehicle") then return tonumber(id) end
end

-- What an NPC does comes only from the window that opens: never from its
-- tooltip. Reading the NPC's tooltip (a hidden tooltip of ours, or the game's
-- tooltip data) as its window opened set off the game's tooltip health bar
-- on Forever, where a unit's health is a "secret value": a Lua error,
-- "tainted by BattlefieldInfo". The NPC's title isn't needed for anything else.

-- an innkeeper: its chat offers to make the inn your home (the binder option)
local BINDER_ICON = 132052  -- Interface\GossipFrame\BinderGossipIcon
local function GossipTypes()
    local types = {}
    if C_GossipInfo and C_GossipInfo.GetOptions then
        local ok, options = pcall(C_GossipInfo.GetOptions)
        for _, o in ipairs(ok and options or {}) do
            if o.icon == BINDER_ICON or o.type == "binder" then types.Innkeeper = true end
        end
    end
    return types
end

-- a trainer that isn't a profession trainer: a weapon master (weapon skills),
-- a portal trainer (portals), else a class trainer. (English names; elsewhere
-- they count as class trainers, shown only to the class that learned them.)
local WEAPON_WORDS = { "sword", "axe", "mace", "dagger", "stave", "staves", "polearm", "bow", "gun", "thrown", "fist" }
local function TrainerKind()
    local weapons, portals = false, false
    for i = 1, (GetNumTrainerServices and GetNumTrainerServices() or 0) do
        local ok, name = pcall(GetTrainerServiceInfo, i)
        local n = ok and type(name) == "string" and name:lower() or ""
        if n:find("^portal") then portals = true end
        for _, w in ipairs(WEAPON_WORDS) do
            if n:find(w, 1, true) and not n:find(":", 1, true) then weapons = true end
        end
    end
    if portals then return "Portal Trainer" end
    if weapons then return "Weapon Master" end
    return "Class Trainer"
end

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local FOOD = GetSpellInfo and GetSpellInfo(433) or "Food"
local DRINK = GetSpellInfo and GetSpellInfo(430) or "Drink"

local function MerchantItemName(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        return info and info.name
    end
    return GetMerchantItemInfo and (GetMerchantItemInfo(i))
end

-- a vendor's types, from what it sells (and whether it repairs)
local function MerchantTypes()
    local types = {}
    if CanMerchantRepair and CanMerchantRepair() then types.Repair = true end
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local link = GetMerchantItemLink and GetMerchantItemLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and GetInstant then
            local _, _, _, _, _, classID = GetInstant(id)
            local name = MerchantItemName(i) or ""
            local spell = GetSpell and GetSpell(id)
            if classID == 6 then types.Ammo = true              -- arrows and bullets
            elseif classID == 1 then types.General = true      -- bags: a general supplier
            elseif classID == 5 then types.Reagents = true     -- spell reagents
            elseif classID == 7 then types["Trade Goods"] = true
            elseif classID == 0 then                           -- consumables
                if spell == FOOD or spell == DRINK then types.Food = true
                elseif name:find("Poison") then types.Poisons = true
                elseif name:find("Potion") then types.Potions = true
                end
            end
        end
    end
    return types
end

-- the profession a trainer teaches (its first service's skill line)
local function TrainerProfession()
    if not GetTrainerServiceSkillLine then return end
    for i = 1, (GetNumTrainerServices and GetNumTrainerServices() or 0) do
        local ok, line = pcall(GetTrainerServiceSkillLine, i)
        if ok and line and line ~= "" then return line end
    end
end

local function Record(types, opts)
    local c = Cfg()
    if not (c.record and ns.PlayerSpots) or IsInInstance() then return end
    local id = NpcID()
    if not id then return end
    local name = UnitName("npc")
    if name == "Spirit Healer" then types["Spirit Healer"] = true end
    if not next(types) then return end  -- nothing we show (a guard, a quest giver...)
    local key = "c" .. id
    local e = LDB()[key] or { types = {}, spots = {} }
    LDB()[key] = e
    e.name = name or e.name
    e.faction = UnitFactionGroup("npc")  -- (nil: neutral, for everyone)
    for t in pairs(types) do e.types[t] = true end
    if opts and opts.prof then e.prof = opts.prof end
    if types["Class Trainer"] then e.class = select(2, UnitClass("player")) end
    if not (opts and opts.noSpot) then AddSpots(e) end
    learnedChanged = true
end

-- a mailbox: no NPC, so by where you stand
local function RecordMailbox()
    if not (Cfg().record and ns.PlayerSpots) or IsInInstance() then return end
    local spots = ns.PlayerSpots()
    for _, e in pairs(LDB()) do
        if e.types.Mailbox then
            for mapID, p in pairs(spots) do
                local s = e.spots[mapID]
                local w, h = ns.MapYards(mapID)
                if s and w and ((s[1] - p[1]) * w) ^ 2 + ((s[2] - p[2]) * h) ^ 2 <= MAILBOX_YARDS ^ 2 then
                    AddSpots(e)
                    learnedChanged = true
                    return
                end
            end
        end
    end
    local n = 1
    while LDB()["m" .. n] do n = n + 1 end
    local e = { name = MAILBOX or "Mailbox", types = { Mailbox = true }, spots = {} }
    AddSpots(e)
    if next(e.spots) then
        LDB()["m" .. n] = e
        learnedChanged = true
    end
end

local learnEvents = CreateFrame("Frame")
local ON_EVENT = {
    GOSSIP_SHOW        = function() Record(GossipTypes()) end,  -- (innkeepers, spirit healers)
    MERCHANT_SHOW      = function() Record(MerchantTypes()) end,
    -- (items still loading on the first look: look again, without counting a visit)
    MERCHANT_UPDATE    = function() Record(MerchantTypes(), { noSpot = true }) end,
    TAXIMAP_OPENED     = function() Record({ ["Flight Master"] = true }) end,
    BANKFRAME_OPENED   = function() Record({ Banker = true }) end,
    AUCTION_HOUSE_SHOW = function() Record({ Auctioneer = true }) end,
    PET_STABLE_SHOW    = function() Record({ ["Stable Master"] = true }) end,
    BATTLEFIELDS_SHOW  = function() Record({ Battlemaster = true }) end,
    MAIL_SHOW          = RecordMailbox,
    TRAINER_SHOW       = function()
        if IsTradeskillTrainer and IsTradeskillTrainer() then
            Record({ professions = true }, { prof = TrainerProfession() })
        else
            Record({ [TrainerKind()] = true })
        end
    end,
}
for e in pairs(ON_EVENT) do pcall(learnEvents.RegisterEvent, learnEvents, e) end
learnEvents:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if ns.Safe then ns.Safe("Townsfolk learn " .. event, ON_EVENT[event]) else pcall(ON_EVENT[event]) end
end)

-- the player's professions by name (for "only my professions")
local function MyProfessionNames()
    local out = {}
    for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
        local name, header = GetSkillLineInfo(i)
        if name and not header then out[name] = true end
    end
    return out
end

-- learned townsfolk of type t on this map, not already in QuestieDB's (`have`: NPC IDs)
local function LearnedPoints(t, mapID, have, out)
    local faction, class = UnitFactionGroup("player"), select(2, UnitClass("player"))
    local mine = t.myProfessionsOnly and MyProfessionNames()
    local old = LEARNED_AS[t.key]
    for key, e in pairs(LDB()) do
        local s = e.spots[mapID]
        local id = tonumber(key:match("^c(%d+)$"))
        if s and (e.types[t.key] or (old and e.types[old])) and not (id and have[id])
           and (not e.faction or e.faction == faction)
           and (not e.class or t.key ~= "Class Trainer" or e.class == class)
           and (not mine or (e.prof and mine[e.prof])) then
            out[#out + 1] = { x = s[1], y = s[2], id = id, name = e.name, sub = e.sub, learned = true }
        end
    end
end

-- for the options page: how many we know
function ns.LearnedTownsfolkStats()
    local n, here = 0, 0
    local mapID = BattlefieldMapFrame and BattlefieldMapFrame:GetMapID()
    for _, e in pairs(LDB()) do
        n = n + 1
        if mapID and e.spots[mapID] then here = here + 1 end
    end
    return n, here
end

function ns.ForgetLearnedTownsfolk()
    LDB()
    BattlefieldInfoQuestDB.townsfolk = {}
    if ns.RedrawTownsfolk then ns.RedrawTownsfolk() end
end

-- Merging -------------------------------------------------------------------

-- Same-type townsfolk within `yards` of each other share one pin: grouped
-- around the first of each group, the pin at their middle
local function Merge(points, mapID, yards)
    local w, h = ns.MapYards(mapID)
    if not (yards and yards > 0 and w) then
        local out = {}
        for i, p in ipairs(points) do out[i] = { x = p.x, y = p.y, name = p.name, members = { p } } end
        return out
    end
    local groups, r2 = {}, yards * yards
    for _, p in ipairs(points) do
        local into
        for _, g in ipairs(groups) do
            local dx, dy = (g.ax - p.x) * w, (g.ay - p.y) * h
            if dx * dx + dy * dy <= r2 then into = g break end
        end
        if into then
            into.members[#into.members + 1] = p
        else
            groups[#groups + 1] = { ax = p.x, ay = p.y, name = p.name, members = { p } }
        end
    end
    for _, g in ipairs(groups) do
        local sx, sy = 0, 0
        for _, p in ipairs(g.members) do sx, sy = sx + p.x, sy + p.y end
        g.x, g.y = sx / #g.members, sy / #g.members
    end
    return groups
end

-- Pin -----------------------------------------------------------------------

BFITownsfolkPinMixin = CreateFromMixins(MapCanvasPinMixin)
BFITownsfolkPinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough  -- see Pin.lua

function BFITownsfolkPinMixin:OnLoad()
    if self.UseFrameLevelType then
        pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_TOWNSFOLK")
    end
end

function BFITownsfolkPinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    self:SetScale(ns.PinScale("townsfolk", Cfg().scale) / canvasScale)  -- (PinScale: town view, small map)
    ns.ReanchorPin(self, map)
end

function BFITownsfolkPinMixin:ApplyCurrentAlpha()
    self:SetAlpha(ns.PinAlpha("townsfolk"))
end

function BFITownsfolkPinMixin:OnAcquired(p, icon, label)
    self.info, self.label = p, label
    self.Icon:SetTexture(icon)
    self:ApplyCurrentScale()
    self:ApplyCurrentAlpha()
    self:SetPosition(p.x, p.y)
end

function BFITownsfolkPinMixin:OnEnter()
    local members = self.info.members
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if #members == 1 then
        local p = members[1]
        GameTooltip:AddLine(p.name or self.label)
        GameTooltip:AddLine(p.sub or self.label, 1, 1, 1)
    else
        -- merged: the type, then everyone here
        GameTooltip:AddLine(string.format("%s (%d)", self.label, #members))
        for _, p in ipairs(members) do
            GameTooltip:AddDoubleLine(p.name or "?", p.sub or "", 1, 1, 1, 0.7, 0.7, 0.7)
        end
    end
    if self.info.also then
        GameTooltip:AddLine("Also: " .. self.info.also, 0.8, 0.8, 0.6, true)  -- (one pin per NPC)
    end
    local learned = 0
    for _, p in ipairs(members) do if p.learned then learned = learned + 1 end end
    if learned > 0 then
        GameTooltip:AddLine(learned == #members and "Learned by Battlefield Info"
            or string.format("%d learned by Battlefield Info", learned), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function BFITownsfolkPinMixin:OnMouseUp(button)
    if ns.PinAltClick then ns.PinAltClick(self, button) end  -- line target (Line.lua)
end

function BFITownsfolkPinMixin:OnLeave()
    GameTooltip:Hide()
end
-- the map wires a pin's mouse-over to these (see Pin.xml)
BFITownsfolkPinMixin.OnMouseEnter = BFITownsfolkPinMixin.OnEnter
BFITownsfolkPinMixin.OnMouseLeave = BFITownsfolkPinMixin.OnLeave

-- Provider ------------------------------------------------------------------

BFITownsfolkProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFITownsfolkProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, TEMPLATE)
end

function BFITownsfolkProviderMixin:RefreshAllData()
    self:Draw()
end

function BFITownsfolkProviderMixin:OnMapChanged()
    self:Draw()
end

function BFITownsfolkProviderMixin:Draw()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    local c = Cfg()
    local useLearned = c.useLearned
    local hasDB = ns.QDB and ns.QDB() ~= nil
    if not (mapID and ns.IsShown("townsfolk") and (hasDB or useLearned)) then return end

    local keys = EnabledKeys()
    -- QuestieDB's profession trainers here, all professions (learned ones are
    -- drawn as one type, so they're checked against all of these)
    local profIDs = {}
    for _, t in ipairs(keys) do
        if type(t.key) == "number" and cache[t.key] then
            for _, p in ipairs(cache[t.key][mapID] or {}) do profIDs[p.id] = true end
        end
    end

    -- each ticked type's townsfolk here, QuestieDB's and learned
    local perType = {}
    for _, t in ipairs(keys) do
        local points, have = {}, {}
        if hasDB and not t.learnedOnly then
            local index = cache[t.key]
            if index then
                for _, p in ipairs(index[mapID] or {}) do
                    points[#points + 1] = p
                    if p.id then have[p.id] = true end
                end
            else
                Request(t.key)  -- drawn once indexed (the builder calls RedrawTownsfolk)
            end
        end
        if useLearned and type(t.key) ~= "number" then
            LearnedPoints(t, mapID, t.learnedOnly and profIDs or have, points)
        end
        local object = iconByKey[t.key] and iconByKey[t.key].object  -- (mailboxes: not NPC IDs)
        perType[#perType + 1] = { t = t, points = points, object = object }
    end

    -- one pin per NPC: the first of its ticked types in PIN_ORDER; the others
    -- go in its tooltip
    local best, labels = {}, {}
    for _, e in ipairs(perType) do
        if not e.object then
            for _, p in ipairs(e.points) do
                if p.id then
                    local cur = best[p.id]
                    if not cur or PinRank(e.t.key) < PinRank(cur.t.key) then best[p.id] = e end
                    local l = labels[p.id] or {}
                    labels[p.id] = l
                    if not l[e.t.label] then
                        l[e.t.label] = true
                        l[#l + 1] = e.t.label
                    end
                end
            end
        end
    end

    for _, e in ipairs(perType) do
        local keep = {}
        for _, p in ipairs(e.points) do
            if e.object or not p.id or best[p.id] == e then keep[#keep + 1] = p end
        end
        for _, g in ipairs(Merge(keep, mapID, c.mergeYards)) do
            -- what these also are (an innkeeper: food & drink too)
            local also, seen = {}, { [e.t.label] = true }
            for _, p in ipairs(g.members) do
                for _, l in ipairs(p.id and not e.object and labels[p.id] or {}) do
                    if not seen[l] then
                        seen[l] = true
                        also[#also + 1] = l
                    end
                end
            end
            g.also = #also > 0 and table.concat(also, ", ") or nil
            pcall(map.AcquirePin, map, TEMPLATE, g, e.t.icon, e.t.label)
        end
    end
end

function ns.SetupTownsfolk(map)
    local provider = CreateFromMixins(BFITownsfolkProviderMixin)
    local ok, err = pcall(map.AddDataProvider, map, provider)
    if not ok then
        ns.Log("Townsfolk layer failed:", err)
        return
    end
    function ns.RedrawTownsfolk()
        if map:IsShown() then pcall(provider.Draw, provider) end
    end

    -- QuestData.lua sorts the types in the background; until then nothing
    -- indexes, so retry now and then while the layer is on and the map is open
    -- (and what you learn shows up while the map is open)
    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 5 or not map:IsVisible() then return end
        elapsed = 0
        if learnedChanged and Cfg().useLearned and ns.IsShown("townsfolk") then
            learnedChanged = false
            ns.RedrawTownsfolk()
            return
        end
        if ns.QDB and ns.QDB() and ns.IsShown("townsfolk") then
            for _, t in ipairs(EnabledKeys()) do
                if not t.learnedOnly and not cache[t.key] then
                    ns.RedrawTownsfolk()
                    return
                end
            end
        end
    end)
end

-- the townsfolk types are sorted (again): index what's on the map
function ns.TownsfolkIndexReady()
    wipe(cache)
    wipe(notReadyUntil)
    if ns.RedrawTownsfolk then ns.RedrawTownsfolk() end
end

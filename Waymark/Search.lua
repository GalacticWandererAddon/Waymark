local _, ns = ...
local GetItemInfo = GetItemInfo or ns.GetItemInfo
local GetItemIcon = GetItemIcon or ns.GetItemIcon
local GetItemQualityColor = GetItemQualityColor or ns.GetItemQualityColor
local GetCoinTextureString = GetCoinTextureString or ns.GetCoinTextureString

-- Map search (mock-up mockups\map-search.html, the user 2026-11-09): a magnifier in the map's bottom-left (the top-right until 2026-11-15)
-- inside corner opens a box; type a trainer, a service or an item a vendor sells, pick a line, and the
-- map rings the closest friendly NPC for it (another zone's: the map goes there), numbers the next two,
-- and a bar under the map says where, with arrows to step to the next closest. Closest is straight
-- distance on your continent when you pick, not live. Stays until the bar's x or a right-click on the
-- magnifier. Who: the townsfolk index (Townsfolk.lua ns.TownsfolkIndex, learned townsfolk too); what
-- vendors sell: Data\VendorStock.lua, with the stock you've seen yourself winning (VendorList.lua's rule).
-- Item names come from the game, loaded the first time the box opens. In the Lab from 2026-11-09 ("keep it lab for now"), out of it for 1.3 on 2026-11-14; its switch is ns.db.searchButton.

local TRACKING = "Interface\\Minimap\\tracking\\"
local RING = ns.MEDIA .. "QuillRing"
local W = 260
local ROW, HEAD = 20, 15
local MAX_ITEMS = 8
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DIGIT = {}
for i = 1, 64 do DIGIT[B64:byte(i)] = i - 1 end

local GROUPS = { "Trainers", "Services", "Vendors", "Sold by vendors" }
-- other words a player might type for a type
local WORDS = {
    ["Flight Master"] = "fly flying taxi gryphon wyvern hippogryph bat", Repair = "repair anvil armour armor",
    Innkeeper = "inn hearth rest", Banker = "bank vault", Auctioneer = "auction ah", Mailbox = "mail post letter",
    ["Spirit Healer"] = "graveyard rez resurrect", ["Stable Master"] = "stable pet", Battlemaster = "battleground pvp",
    ["Class Trainer"] = "class spells", ["Weapon Master"] = "weapon skill", ["Portal Trainer"] = "portal teleport",
    Food = "food drink water eat", Ammo = "ammo arrow bullet", Reagents = "reagent", Poisons = "poison",
    General = "general goods bag supplies", ["Trade Goods"] = "trade thread flux vial", Potions = "potion heal mana",
}
local TRAINER_KEYS = { ["Class Trainer"] = true, ["Weapon Master"] = true, ["Portal Trainer"] = true }

local button, box, edit, bar, provider
local rows, heads = {}, {}
local found   -- { entry =, list = { candidates, closest first }, step =, waiting = tries }

-- What can be searched -------------------------------------------------------

local entries
local function Entries()
    if entries then return entries end
    entries = {}
    local types = ns.TOWNSFOLK_TYPES or { services = {}, vendors = {} }
    for _, t in ipairs(types.services) do
        entries[#entries + 1] = { key = t.key, label = t.label, icon = t.icon, object = t.object,
            group = TRAINER_KEYS[t.key] and 1 or 2, find = (t.label .. " " .. (WORDS[t.key] or "")):lower() }
    end
    for _, t in ipairs(types.vendors) do
        entries[#entries + 1] = { key = t.key, label = t.label, icon = t.icon, group = 3,
            find = (t.label .. " vendor " .. (WORDS[t.key] or "")):lower() }
    end
    local skills = ns.VendorStock and ns.VendorStock.skills or {}
    for id, words in pairs(ns.PROFESSION_TRAINER_IDS or {}) do
        -- (the stock data names this client's professions: no jewelcrafting in Classic)
        if skills[id] or not next(skills) then
            local name = skills[id] or words[1]
            entries[#entries + 1] = { key = id, label = name .. " trainer", icon = TRACKING .. "profession", group = 1,
                find = (name .. " trainer"):lower() }
        end
    end
    table.sort(entries, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.label < b.label
    end)
    return entries
end

-- item -> the vendors selling it (the reference, or what you saw a vendor have)
local itemVendors, itemList
local function ItemIndex()
    if itemVendors then return itemVendors end
    itemVendors, itemList = {}, {}
    local data = ns.VendorStock or {}
    local seen = WaymarkQuestDB and WaymarkQuestDB.stock or {}
    local function Add(item, npc)
        local l = itemVendors[item]
        if not l then
            l = {}
            itemVendors[item] = l
            itemList[#itemList + 1] = item
        end
        l[#l + 1] = npc
    end
    for npc, s in pairs(data.sells or {}) do
        if not seen[npc] then
            local i = 1
            while i <= #s do
                if s:byte(i) == 33 then  -- "!" (limited stock)
                    i = i + 1
                else
                    local a, b, c = s:byte(i, i + 2)
                    Add(DIGIT[a] * 4096 + DIGIT[b] * 64 + DIGIT[c], npc)
                    i = i + 3
                end
            end
        end
    end
    for npc, v in pairs(seen) do
        for _, r in ipairs(v.items or {}) do Add(r[1], npc) end
    end
    return itemVendors
end

-- names, lower case, as the game hands them over
local names = {}
local namesAsked
local function AskNames()
    if namesAsked then return end
    namesAsked = true
    ItemIndex()
    local i = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self)
        for _ = 1, 60 do  -- (spread over frames: each unknown one is a question to the server)
            i = i + 1
            local id = itemList[i]
            if not id then self:SetScript("OnUpdate", nil) return end
            if not names[id] then
                local n = GetItemInfo(id)
                if n then names[id] = n:lower() end
            end
        end
    end)
end

local itemEntries = {}
local function ItemEntry(id)
    local e = itemEntries[id]
    if not e then
        local name, _, quality = GetItemInfo(id)
        local data = ns.VendorStock or {}
        e = { item = id, label = name or ("item " .. id), icon = GetItemIcon and GetItemIcon(id), quality = quality,
              price = data.price and data.price[id], group = 4 }
        if name then itemEntries[id] = e end
    end
    return e
end

local function Matches(q)
    local groups = { {}, {}, {}, {} }
    for _, e in ipairs(Entries()) do
        if e.find:find(q, 1, true) then table.insert(groups[e.group], e) end
    end
    if #q >= 3 then
        AskNames()
        local hits = {}
        for _, id in ipairs(itemList) do
            local n = names[id]
            local at = n and n:find(q, 1, true)
            if at then hits[#hits + 1] = { id = id, score = (at == 1 and 0 or 1000) + #n } end
        end
        table.sort(hits, function(a, b)
            if a.score ~= b.score then return a.score < b.score end
            return a.id < b.id
        end)
        for i = 1, math.min(#hits, MAX_ITEMS) do groups[4][i] = ItemEntry(hits[i].id) end
    end
    return groups
end

-- Who, where -----------------------------------------------------------------

local function Friendly(f)
    if not f or f == "AH" then return true end
    local mine = UnitFactionGroup("player")
    return (mine == "Alliance" and f == "A") or (mine == "Horde" and f == "H")
end

local function Learned() return WaymarkQuestDB and WaymarkQuestDB.townsfolk end

-- { id, name, sub, map, x, y }... for a type; nil while its index is being built
local function TypeCandidates(e)
    local index = ns.TownsfolkIndex and ns.TownsfolkIndex(e.key)
    if not index then return nil end
    local out, have = {}, {}
    for mapID, list in pairs(index) do
        for _, p in ipairs(list) do
            out[#out + 1] = { id = p.id, name = p.name, sub = p.sub, map = mapID, x = p.x, y = p.y, object = e.object }
            if p.id then have[p.id] = true end
        end
    end
    if type(e.key) == "string" then
        local mine = UnitFactionGroup("player")
        for k, l in pairs(Learned() or {}) do
            local id = tonumber(tostring(k):match("^c(%d+)$"))
            if l.types and l.types[e.key] and not (id and have[id]) and (not l.faction or l.faction == mine) then
                for mapID, s in pairs(l.spots or {}) do
                    out[#out + 1] = { id = id or k, name = l.name, map = mapID, x = s[1], y = s[2], object = e.object }
                end
            end
        end
    end
    return out
end

local function ItemCandidates(e)
    local L = ns.QuestSource and ns.QuestSource()
    local learned, mine = Learned() or {}, UnitFactionGroup("player")
    local out = {}
    for _, npc in ipairs(ItemIndex()[e.item] or {}) do
        local done = false
        if L and L.Npc then
            pcall(function()
                if not Friendly(L.Npc.friendlyToFaction(npc)) then done = true return end
                local name, sub = L.Npc.name(npc), L.Npc.subName(npc)
                local function Put(m, x, y)
                    out[#out + 1] = { id = npc, name = name, sub = sub, map = m, x = x, y = y }
                    done = true
                end
                local spawns = L.Npc.spawns(npc)
                if spawns and next(spawns) then
                    ns.EachSpawnOnMap(spawns, Put)
                else
                    for areaID, paths in pairs(L.Npc.waypoints(npc) or {}) do
                        local first = paths[1] and paths[1][1]
                        if first then ns.EachSpawnOnMap({ [areaID] = { first } }, Put) end
                    end
                end
            end)
        end
        local l = not done and learned["c" .. npc]
        if l and (not l.faction or l.faction == mine) then
            for m, s in pairs(l.spots or {}) do out[#out + 1] = { id = npc, name = l.name, map = m, x = s[1], y = s[2] } end
        end
    end
    return out
end

local function PlayerWorld()
    local m = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local p = m and C_Map.GetPlayerMapPosition(m, "player")
    if not p then return end
    local ok, inst, w = pcall(C_Map.GetWorldPosFromMapPos, m, p)
    if ok and w then return inst, w:GetXY() end
end

-- closest first: on your continent by straight distance, the rest after by name; one per NPC and map
local function Rank(list)
    local pinst, px, py = PlayerWorld()
    local best = {}
    for _, c in ipairs(list) do
        local ok, inst, w = pcall(C_Map.GetWorldPosFromMapPos, c.map, CreateVector2D(c.x, c.y))
        if ok and w then
            c.inst = inst
            c.wx, c.wy = w:GetXY()
            if pinst and inst == pinst then c.d = (c.wx - px) ^ 2 + (c.wy - py) ^ 2 end
        end
        -- (a mailbox's ID is every mailbox's)
        local k = c.object and (c.map .. ":" .. c.x .. ":" .. c.y) or (tostring(c.id) .. ":" .. c.map)
        local b = best[k]
        if not b or (c.d or math.huge) < (b.d or math.huge) then best[k] = c end
    end
    local out = {}
    for _, c in pairs(best) do out[#out + 1] = c end
    table.sort(out, function(a, b)
        if (a.d ~= nil) ~= (b.d ~= nil) then return a.d ~= nil end
        if a.d and a.d ~= b.d then return a.d < b.d end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

-- where a candidate is on a map (its own, or one it lies on: the zone round a capital, the continent)
local function OnMap(c, mapID)
    if c.map == mapID then return c.x, c.y end
    if not (c.inst and C_Map.GetMapPosFromWorldPos) then return end
    local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, c.inst, CreateVector2D(c.wx, c.wy), mapID)
    if not (ok and pos) then return end
    local x, y = pos:GetXY()
    if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

-- The map ----------------------------------------------------------------------

local mapNames = {}
local function MapName(id)
    if mapNames[id] == nil then
        local info = C_Map.GetMapInfo(id)
        mapNames[id] = info and info.name or "?"
    end
    return mapNames[id]
end

local function Redraw()
    if provider then pcall(provider.RefreshAllData, provider) end
end

local function UpdateBar()
    if not bar then return end
    local docked = ns.Docked and ns.Docked()
    if not found or docked then bar:Hide() return end
    local e, text = found.entry, nil
    local label = e.label
    if e.quality and GetItemQualityColor then
        local _, _, _, hex = GetItemQualityColor(e.quality)
        if hex then label = "|c" .. hex .. label .. "|r" end
    end
    if found.waiting then
        text = label .. "|cff8c8c8c: looking...|r"
    elseif #found.list == 0 then
        text = label .. "|cff8c8c8c: none known|r"
    else
        local c = found.list[found.step]
        local where = MapName(c.map) .. (c.d and "" or " |cff8c8c8c(not on this continent)|r")
        text = label .. "|cff8c8c8c  " .. (found.step == 1 and "closest" or (found.step .. " of " .. #found.list)) .. ":|r " .. where
    end
    bar.text:SetText(text)
    local many = found.list and #found.list > 1
    bar.prev:SetShown(many)
    bar.next:SetShown(many)
    bar.text:ClearAllPoints()
    bar.text:SetPoint("LEFT", 9, 0)
    bar:SetWidth(bar.text:GetStringWidth() + 18 + (many and 44 or 0) + 22)
    bar:Show()
end

local function Go(step)
    if not (found and found.list and found.list[step]) then return end
    found.step = step
    local c = found.list[step]
    local map = BattlefieldMapFrame
    local cur = map and map:GetMapID()
    local info = cur and C_Map.GetMapInfo(cur)
    local T = Enum and Enum.UIMapType
    local zoneOrIn = info and T and info.mapType >= T.Zone
    if map and not (zoneOrIn and OnMap(c, cur)) then
        if ns.BrowseTo then ns.BrowseTo(c.map) else pcall(map.SetMapID, map, c.map) end
    end
    Redraw()
    UpdateBar()
    -- zoomed in: over to it
    if map and map.GetCanvasZoomPercent and (map:GetCanvasZoomPercent() or 0) > 0.01 and map.PanTo then
        local x, y = OnMap(c, map:GetMapID())
        if x then pcall(map.PanTo, map, x, y) end
    end
end

local function Clear()
    found = nil
    Redraw()
    UpdateBar()
end

local function Resolve()
    local e = found and found.entry
    if not e then return end
    local list
    if e.item then list = ItemCandidates(e) else list = TypeCandidates(e) end
    if not list then
        -- (the townsfolk index is still being built: ask again shortly)
        found.waiting = (found.waiting or 0) + 1
        if found.waiting > 40 then found.waiting, found.list, found.step = nil, {}, 1 UpdateBar() return end
        UpdateBar()
        C_Timer.After(0.5, function() if found and found.entry == e then Resolve() end end)
        return
    end
    found.waiting = nil
    found.list = Rank(list)
    found.step = 1
    if #found.list > 0 then Go(1) else Redraw() UpdateBar() end
end

local function Pick(e)
    if not e then return end
    box:Hide()
    found = { entry = e, list = {}, step = 1 }
    Resolve()
end

-- Pins: the ring on the closest, numbers on the next two -------------------------

BFISearchPinMixin = CreateFromMixins(MapCanvasPinMixin)

local function Pulse(self)
    local tex = self:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(RING)
    tex:SetDesaturated(true)
    tex:SetVertexColor(1, 0.82, 0)
    tex:SetPoint("CENTER")
    local g = tex:CreateAnimationGroup()
    local s = g:CreateAnimation("Scale")
    if s.SetScaleTo then s:SetScaleFrom(1, 1) s:SetScaleTo(1.8, 1.8) else s:SetScale(1.8, 1.8) end
    s:SetDuration(1.1)
    local a = g:CreateAnimation("Alpha")
    if a.SetFromAlpha then a:SetFromAlpha(0.9) a:SetToAlpha(0) end
    a:SetDuration(1.1)
    g:SetScript("OnFinished", function()
        self.pulses = (self.pulses or 0) + 1
        if self.pulses < 3 then g:Play() else tex:Hide() end
    end)
    self.pulseTex, self.pulse = tex, g
end

function BFISearchPinMixin:OnLoad()
    if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_QUESTIE") end
    self:EnableMouse(false)  -- (the townsfolk pin under it keeps its tooltip and menu)
    self.ring = self:CreateTexture(nil, "OVERLAY")
    self.ring:SetTexture(RING)
    self.ring:SetDesaturated(true)
    self.ring:SetPoint("CENTER")
    Pulse(self)
    self.num = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.num:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", -6, -6)
    self.tagBg = self:CreateTexture(nil, "ARTWORK")
    self.tagBg:SetColorTexture(0.04, 0.03, 0.02, 0.85)
    self.tagName = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.tagName:SetPoint("TOP", self, "BOTTOM", 0, -4)
    self.tagSub = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.tagSub:SetPoint("TOP", self.tagName, "BOTTOM", 0, -1)
end

function BFISearchPinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    self:SetScale((ns.AddonScale and ns.AddonScale() or 1) / canvasScale)
    ns.ReanchorPin(self, map)
end

function BFISearchPinMixin:ApplyCurrentAlpha() self:SetAlpha(1) end

function BFISearchPinMixin:OnAcquired(d, x, y)
    local hit = d.rank == 0
    local size = hit and 34 or 26
    self:SetSize(size, size)
    self.ring:SetSize(size, size)
    if hit then self.ring:SetVertexColor(1, 0.82, 0, 1) else self.ring:SetVertexColor(0.95, 0.9, 0.75, 0.8) end
    self.num:SetText(hit and "" or tostring(d.rank + 1))
    self.pulse:Stop()
    self.pulses = 0
    self.pulseTex:SetSize(size, size)
    self.pulseTex:SetShown(hit)
    if hit then self.pulse:Play() end
    local c = d.c
    local sub = c.sub or ""
    if d.entry.price and GetCoinTextureString then
        sub = (sub ~= "" and sub .. "  " or "") .. GetCoinTextureString(d.entry.price)
    end
    self.tagName:SetText(hit and (c.name or "") or "")
    self.tagSub:SetText(hit and sub or "")
    self.tagBg:SetShown(hit)
    if hit then
        local w = math.max(self.tagName:GetStringWidth(), self.tagSub:GetStringWidth()) + 10
        local h = self.tagName:GetStringHeight() + (sub ~= "" and self.tagSub:GetStringHeight() + 1 or 0) + 6
        self.tagBg:ClearAllPoints()
        self.tagBg:SetPoint("TOP", self, "BOTTOM", 0, -1)
        self.tagBg:SetSize(w, h)
    end
    self:ApplyCurrentScale()
    self:SetPosition(x, y)
    -- (over the townsfolk and quest pins round it)
    self.baseLevel = self.baseLevel or self:GetFrameLevel()
    self:SetFrameLevel(self.baseLevel + 20)
end

BFISearchProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFISearchProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, "BFISearchPinTemplate")
end

function BFISearchProviderMixin:RefreshAllData()
    self:RemoveAllData()
    if not (found and found.list and #found.list > 0) then return end
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not mapID then return end
    for k = 0, 2 do
        local c = found.list[found.step + k]
        if not c then break end
        local x, y = OnMap(c, mapID)
        if x then pcall(map.AcquirePin, map, "BFISearchPinTemplate", { c = c, rank = k, entry = found.entry }, x, y) end
    end
end

function BFISearchProviderMixin:OnMapChanged() self:RefreshAllData() end

-- The box --------------------------------------------------------------------------

local function Text(parent, font, r, g, b)
    local t = parent:CreateFontString(nil, "OVERLAY", font)
    if r then t:SetTextColor(r, g, b) end
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    return t
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, box)
    r:SetSize(W - 10, ROW)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(0.16, 0.14, 0.10, 1)
    r.hl:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 4, 0)
    r.right = Text(r, "GameFontHighlightSmall", 0.55, 0.55, 0.55)
    r.right:SetJustifyH("RIGHT")
    r.right:SetPoint("RIGHT", -4, 0)
    r.label = Text(r, "GameFontHighlight", 1, 1, 1)
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.label:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        if self.entry and self.entry.item and GameTooltip.SetItemByID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetItemByID, GameTooltip, self.entry.item)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        self.hl:SetShown(self.first and true or false)
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self) Pick(self.entry) end)
    rows[i] = r
    return r
end

local function Head(i)
    local h = heads[i]
    if not h then
        h = Text(box, "GameFontNormalSmall", 1, 0.82, 0)
        heads[i] = h
    end
    return h
end

local first  -- the line Enter picks
local function Refresh()
    if not (box and box:IsShown()) then return end
    for _, r in ipairs(rows) do r:Hide() end
    for _, h in ipairs(heads) do h:Hide() end
    local q = strtrim(edit:GetText() or ""):lower()
    box.hint:SetShown(q == "")
    edit.placeholder:SetShown(q == "")
    first = nil
    local y, nr, nh = -34, 0, 0
    if q ~= "" then
        local groups = Matches(q)
        for g, list in ipairs(groups) do
            if #list > 0 then
                nh = nh + 1
                local h = Head(nh)
                h:SetText(GROUPS[g])
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", 10, y - 2)
                h:Show()
                y = y - HEAD
                for _, e in ipairs(list) do
                    nr = nr + 1
                    local r = Row(nr)
                    r.entry = e
                    r.icon:SetTexture(e.icon or 134400)
                    local label = e.label
                    if e.quality and GetItemQualityColor then
                        local cr, cg, cb = GetItemQualityColor(e.quality)
                        r.label:SetTextColor(cr or 1, cg or 1, cb or 1)
                    else
                        r.label:SetTextColor(1, 1, 1)
                    end
                    r.label:SetText(label)
                    r.right:SetText(e.price and GetCoinTextureString and GetCoinTextureString(e.price) or "")
                    r.first = nr == 1
                    r.hl:SetShown(r.first)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", 5, y)
                    r:Show()
                    y = y - ROW
                    if not first then first = e end
                end
            end
        end
        if nr == 0 then
            box.none:ClearAllPoints()
            box.none:SetPoint("TOPLEFT", 10, y - 4)
            y = y - 20
        end
    else
        y = y - 20
    end
    box.none:SetShown(q ~= "" and nr == 0)
    box:SetHeight(-y + 6)
end

-- The box opens toward the map's middle from wherever the magnifier sits: up from the bottom, down from the
-- top, and to the side with room.
local function AimBox()
    local map = BattlefieldMapFrame
    local area = map and (map.ScrollContainer or map)
    local bx, by = button:GetCenter()
    local mx, my = 0, 0
    if area and area.GetCenter then mx, my = area:GetCenter() end
    local s, ms = button:GetEffectiveScale(), area and area:GetEffectiveScale() or 1
    local low = bx and my and by * s < my * ms
    local left = bx and mx and bx * s < mx * ms
    box:ClearAllPoints()
    if low then
        box:SetPoint(left and "BOTTOMLEFT" or "BOTTOMRIGHT", button, left and "TOPLEFT" or "TOPRIGHT", left and -2 or 2, 4)
    else
        box:SetPoint(left and "TOPLEFT" or "TOPRIGHT", button, left and "BOTTOMLEFT" or "BOTTOMRIGHT", left and -2 or 2, -4)
    end
end

local function OpenBox()
    AimBox()
    box:Show()
    edit:SetFocus()
    edit:HighlightText()
    Refresh()
end

local function MakeBox()
    box = CreateFrame("Frame", nil, button, "BackdropTemplate")
    box:SetWidth(W)
    box:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 2, -4)
    box:SetClampedToScreen(true)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    box:SetBackdropColor(0.08, 0.067, 0.05, 0.96)
    box:SetBackdropBorderColor(0.48, 0.42, 0.30)
    box:EnableMouse(true)
    box:Hide()

    edit = CreateFrame("EditBox", nil, box, "BackdropTemplate")
    edit:SetHeight(22)
    edit:SetPoint("TOPLEFT", 6, -6)
    edit:SetPoint("TOPRIGHT", -6, -6)
    edit:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    edit:SetBackdropColor(0, 0, 0, 0.6)
    edit:SetBackdropBorderColor(0.3, 0.26, 0.18)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(40)
    edit.placeholder = Text(edit, "GameFontDisable", 0.5, 0.5, 0.5)
    edit.placeholder:SetPoint("LEFT", 7, 0)
    edit.placeholder:SetText("Trainer, service or item...")
    edit:SetScript("OnTextChanged", Refresh)
    edit:SetScript("OnEscapePressed", function() box:Hide() end)
    edit:SetScript("OnEnterPressed", function() if first then Pick(first) end end)
    box:SetScript("OnHide", function() edit:ClearFocus() end)

    box.hint = Text(box, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    box.hint:SetPoint("TOPLEFT", 10, -36)
    box.hint:SetText("A trainer, a service, or an item a vendor sells.")
    box.none = Text(box, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    box.none:SetText("Nobody we know of sells or teaches that.")

    -- names arriving from the server: the list again (a few at a time)
    local pending
    box:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    box:SetScript("OnEvent", function(_, _, id, ok)
        if ok and id and itemVendors and itemVendors[id] and not names[id] then
            local n = GetItemInfo(id)
            if n then names[id] = n:lower() end
        end
        if pending or not box:IsShown() then return end
        pending = true
        C_Timer.After(0.3, function() pending = nil Refresh() end)
    end)
end

local function MakeBar(map)
    bar = CreateFrame("Frame", nil, map, "BackdropTemplate")
    bar:SetHeight(24)
    bar:SetPoint("BOTTOM", map.ScrollContainer or map, "BOTTOM", 0, 6)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bar:SetBackdropColor(0.04, 0.03, 0.02, 0.9)
    bar:SetBackdropBorderColor(0.42, 0.35, 0.23)
    bar:EnableMouse(true)
    bar.text = Text(bar, "GameFontHighlightSmall")
    local function Btn(tex, onClick)
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(22, 22)
        b:SetNormalTexture(tex .. "-Up")
        b:SetPushedTexture(tex .. "-Down")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnClick", onClick)
        return b
    end
    bar.close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
    bar.close:SetSize(22, 22)
    bar.close:SetPoint("RIGHT", -1, 0)
    bar.close:SetScript("OnClick", Clear)
    bar.next = Btn("Interface\\Buttons\\UI-SpellbookIcon-NextPage", function()
        if found and found.list and #found.list > 0 then Go(found.step % #found.list + 1) end
    end)
    bar.next:SetPoint("RIGHT", bar.close, "LEFT", 0, 0)
    bar.prev = Btn("Interface\\Buttons\\UI-SpellbookIcon-PrevPage", function()
        if found and found.list and #found.list > 0 then Go((found.step - 2) % #found.list + 1) end
    end)
    bar.prev:SetPoint("RIGHT", bar.next, "LEFT", 0, 0)
    bar:Hide()
    ns.debugFrames.searchBar = bar
end

-- Out of the Lab for 1.3 on 2026-11-14 (the user: "Map search comes"). Its switch is the addon's own, a map
-- button's like the gear's (ns.db.searchButton, DEFAULTS in BattlefieldInfo.lua), carried over once from the
-- Lab's store where a dev copy had it there.
local function On()
    local db = ns.db
    if not db then return true end
    local old = WaymarkDB and WaymarkDB.lab and WaymarkDB.lab.search
    if old and not old.moved then
        if old.on ~= nil then db.searchButton = old.on and true or false end
        old.moved = true
    end
    return db.searchButton ~= false
end

-- The magnifier ------------------------------------------------------------------

local function Place()
    if not button then return end
    local map = BattlefieldMapFrame
    local on = ns.db.mapButtons ~= false and On() and not (ns.Docked and ns.Docked())
    button:SetShown(on and true or false)
    if not ns.PlaceMoved(button) then
        button:ClearAllPoints()
        -- (the bottom left corner, over the coordinates when they are there: the user, 2026-11-15. It was
        -- the top right.)
        button:SetPoint("BOTTOMLEFT", map.ScrollContainer or map, "BOTTOMLEFT", 6, 6 + (ns.CoordsCornerLift and ns.CoordsCornerLift() or 0))
    end
    UpdateBar()
end

local function Scale()
    local map = BattlefieldMapFrame
    if not (map and button) then return end
    local inv = (ns.AddonScale and ns.AddonScale() or 1) / math.max(0.1, map:GetScale())
    button:SetScale(inv)
    bar:SetScale(inv)
    local level = ns.ButtonLevel(map)
    button:SetFrameLevel(level)
    box:SetFrameLevel(level + 5)
    bar:SetFrameLevel(level)
end

local function Setup(map)
    if button or not map then return end
    button = CreateFrame("Button", nil, map)
    button:SetSize(20, 20)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    bg:SetVertexColor(0.07, 0.05, 0.03, 0.75)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER", 0.5, 0)
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetVertexColor(1, 0.85, 0.4)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, which)
        GameTooltip:Hide()
        if which == "RightButton" then
            box:Hide()
            Clear()
        elseif box:IsShown() then
            box:Hide()
        else
            OpenBox()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, ns.PlaceMoved(self) and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
        GameTooltip:AddLine("Search the map")
        GameTooltip:AddLine("Finds the closest trainer, service or vendor item.", 1, 1, 1, true)
        ns.Hints({ { "Click", "search" }, { "Right-click", "clear the search" }, { "Hold", "move it (any map button)" } })
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    MakeBox()
    MakeBar(map)
    ns.HoldToMove(button, "search")
    ns.debugFrames.searchButton = button

    provider = CreateFromMixins(BFISearchProviderMixin)
    local ok, err = pcall(map.AddDataProvider, map, provider)
    if not ok then ns.Log("Search pins failed:", err) provider = nil end

    -- the gear's fading (toggles.fadeOut, clear view's hover, the frame's opacity), or fully there while
    -- the box is open
    local shownAlpha
    local tick = ns.TimedFrame("Search tick", map)
    tick:SetScript("OnUpdate", function()
        local gear = ns.debugFrames.gear
        local a = (box:IsShown() or not gear) and 1 or gear:GetAlpha()
        if a ~= shownAlpha then
            shownAlpha = a
            button:SetAlpha(a)
            bar:SetAlpha(math.max(a, 0.6))
        end
    end)
    Place()
    Scale()
end

ns.RedrawSearch = Redraw

-- how far the brass switch of a cave's or a dungeon's map goes up to clear the magnifier, while it is in its
-- own corner (Cave.lua, Dungeon.lua, on top of ns.CoordsCornerLift)
function ns.SearchCornerLift()
    if not (button and button:IsShown()) or ns.PlaceMoved(button) then return 0 end
    return 24
end

-- Its switch (searchButton, Buttons & coordinates): Options.lua through ns.OnSettingChanged
function ns.SearchSettingChanged()
    if not On() then
        if box then box:Hide() end
        Clear()
    end
    Place()
end
ns.PlaceSearch = Place
-- (for tools\search_test.lua)
ns.searchParts = { Matches = Matches, Rank = Rank, ItemIndex = ItemIndex, TypeCandidates = TypeCandidates,
                   ItemCandidates = ItemCandidates, OnMap = OnMap, names = names, Entries = Entries }
-- After Options.lua's own. Plain Lua wrappers, not hooksecurefunc: its wrapper isn't a function to
-- C_Timer.After (Dock.lua passes ns.ApplyChromeScale to it: "bad argument #2", the user 2026-11-09)
local function After(name, fn)
    local orig = ns[name]
    if not orig then return end
    ns[name] = function(...)
        local a, b, c = orig(...)
        fn(...)
        return a, b, c
    end
end
After("SetupQuickButton", Setup)
After("UpdateQuickButton", Place)
After("ApplyChromeScale", Scale)
After("ApplyButtonLevels", Scale)

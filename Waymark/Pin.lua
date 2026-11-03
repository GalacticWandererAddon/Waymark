local _, ns = ...

local PLAIN_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local TURNIN_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"

-- Questie's small corner badge on quests started by an item or an object
local STARTER_OVERLAYS = {
    itemFromMonster = "Interface/AddOns/Questie/Icons/loot_overlay.png",
    itemFromObject  = "Interface/AddOns/Questie/Icons/loot_overlay.png",
    Object          = "Interface/AddOns/Questie/Icons/object_overlay.png",
}

BFIQuestiePinMixin = CreateFromMixins(MapCanvasPinMixin)

function BFIQuestiePinMixin:OnLoad()
    if self.UseFrameLevelType then
        -- our own level, registered last in SetupFrameLevels so it sits above everything
        pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_QUESTIE")
    end
end

-- settings for whichever Questie group this pin currently shows
local function Cfg(pin)
    return ns.db and ns.db[pin.bfiGroup or "questie"] or {}
end

-- Red/orange/yellow/green/gray, as the game colours quest levels
local function DifficultyColor(level)
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and c and c.r then return c.r, c.g, c.b end
    end
    local diff = level - UnitLevel("player")
    if diff >= 5 then return 1, 0.1, 0.1 end
    if diff >= 3 then return 1, 0.5, 0.25 end
    if diff >= -2 then return 1, 0.82, 0 end
    local green = GetQuestGreenRange and GetQuestGreenRange() or 8
    if -diff <= green then return 0.25, 0.75, 0.25 end
    return 0.5, 0.5, 0.5
end
ns.QuestDifficultyColor = DifficultyColor

-- The game's cursor art as an icon: Media\CursorMask.tga hides the mouse
-- pointer's tip in its top-left corner (on: masked; cropR / cropB: how much of
-- the art's width / height is drawn, so the mask lines up with the whole art).
-- Off takes the mask away again (pins and tracker lines are reused).
local CURSOR_MASK = ns.MEDIA .. "CursorMask"
function ns.CursorMask(owner, tex, on, cropR, cropB)
    if not (owner.CreateMaskTexture and tex.AddMaskTexture) then return end
    local m = tex.bfiMask
    if on then
        if not m then
            m = owner:CreateMaskTexture()
            m:SetTexture(CURSOR_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            tex.bfiMask = m
        end
        local w, h = tex:GetSize()
        m:ClearAllPoints()
        -- (the whole art drawn: tied to all four corners, nothing to work out;
        -- a size set on a scaled map pin's mask didn't line up)
        if (cropR or 1) >= 1 and (cropB or 1) >= 1 then
            m:SetAllPoints(tex)
        elseif w and w > 0 and h and h > 0 then
            m:SetPoint("TOPLEFT", tex, "TOPLEFT")
            m:SetSize(w / (cropR or 1), h / (cropB or 1))
        else
            m:SetAllPoints(tex)
        end
        if not tex.bfiMasked then
            tex:AddMaskTexture(m)
            tex.bfiMasked = true
        end
    elseif m and tex.bfiMasked then
        tex:RemoveMaskTexture(m)
        tex.bfiMasked = false
    end
end

-- Difficulty colours as they sit on the map's parchment: yellow is left to the
-- icon's own gold (nil), and the others are toned down: pure red and green
-- glare on the paper. Returns r, g, b, or nil for "as drawn".
function ns.SoftQuestColor(r, g, b)
    if r > 0.9 and g > 0.75 and b < 0.35 then return nil end   -- yellow: your level
    if g > r and g > b then return 0.45, 0.78, 0.32 end        -- green: easy
    if r > 0.9 and g < 0.3 then return 0.80, 0.34, 0.24 end    -- red: dangerous, muted brick
    if r > 0.9 and g < 0.75 then return 0.92, 0.58, 0.30 end   -- orange: hard, warm amber
    return r, g, b                                             -- grey (trivial) as it is
end

-- When the map places a pin it sets right-click pass-through (SetPassThroughButtons),
-- which the game blocks in combat for addon pins ("action only available to the
-- Blizzard UI"). The Battlefield Map is used a lot in combat, so skip it there; the
-- only cost is that right-clicking our pin in combat doesn't reach the map underneath.
-- (Same fix as Hunter's Field Guide.)
-- (our pins keep their right-click: it's the pin's menu, Controls.lua, not the map's zoom out)
function ns.SafePassthrough(self, ...)
    if InCombatLockdown and InCombatLockdown() then return end
    if not (MapCanvasPinMixin and MapCanvasPinMixin.CheckMouseButtonPassthrough) then return end
    local keep = {}
    for i = 1, select("#", ...) do
        local b = select(i, ...)
        if b ~= "RightButton" then keep[#keep + 1] = b end
    end
    MapCanvasPinMixin.CheckMouseButtonPassthrough(self, unpack(keep))
end
BFIQuestiePinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough

-- A TomTom arrow to a pin (again on the same one: off). x, y: 0-1 on the pin's map
local tomtomUid, tomtomAt
function ns.PinArrow(pin, title, x, y)
    if not (TomTom and TomTom.AddWaypoint) then return end
    local map = pin.GetMap and pin:GetMap()
    local mapID = map and map:GetMapID()
    x, y = x or pin.normalizedX, y or pin.normalizedY
    if tomtomUid and TomTom.RemoveWaypoint then
        pcall(TomTom.RemoveWaypoint, TomTom, tomtomUid)
        tomtomUid = nil
        if tomtomAt == pin then tomtomAt = nil return end
    end
    if not (mapID and x and y) then return end
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, mapID, x, y, { title = title or "", from = "Waymark" })
    if ok then tomtomUid, tomtomAt = uid, pin end
end

-- A pin's menu (right-click on a thing, Controls.lua): its own rows, then a TomTom
-- arrow. title: the arrow's name
function ns.PinMenu(pin, items, title)
    items = items or {}
    if TomTom and TomTom.AddWaypoint and pin.normalizedX then
        items[#items + 1] = { "a TomTom arrow to it", function() ns.PinArrow(pin, title) end }
    end
    if #items > 0 and ns.QuillMenu then ns.QuillMenu(items) end
end

-- the hint lines every pin of ours ends with (before them: the pin's own)
function ns.PinHints(own)
    own = own or {}
    own[#own + 1] = { "Right-click", "its menu" }
    ns.Hints(own)
end

-- A faint golden glow behind a pin (the tracker's hovered quest, Tracker.lua);
-- made on first use, on our pins and the game's objective markers alike
local GLOW = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
function ns.PinGlow(pin, on)
    local g = pin.bfiGlow
    if not on then
        if g then g:Hide() end
        return
    end
    if not g then
        g = pin:CreateTexture(nil, "BACKGROUND", nil, -8)
        g:SetTexture(GLOW)
        g:SetBlendMode("ADD")
        g:SetVertexColor(1, 0.8, 0.3, 0.75)
        g:SetPoint("CENTER")
        pin.bfiGlow = g
    end
    local w, h = pin:GetSize()
    g:SetSize(w * 2.2, h * 2.2)
    g:Show()
end

function BFIQuestiePinMixin:ApplyCurrentAlpha()
    self:SetAlpha(ns.PinAlpha(self.bfiGroup or "questie"))
end

-- After one of our pins is rescaled: pin offsets are in the pin's own scaled
-- units, so it's re-anchored. (Every pin type's ApplyCurrentScale ends with this.)
function ns.ReanchorPin(pin, map)
    -- (Classic Era: the game rescales pins not placed yet, and placing one without
    -- its map or a position errors in the game's own code)
    if not ns.FOREVER and not (map and pin.normalizedX) then return end
    if pin.ApplyCurrentPosition then
        pin:ApplyCurrentPosition()
    elseif pin.normalizedX then
        pin:SetPosition(pin.normalizedX, pin.normalizedY)
    end
end

-- The Battlefield Map shrinks pins (globalPinScale 0.6), leaving ~10px icons that
-- pixel snapping renders unevenly. Keep a fixed on-screen size of our own instead.
function BFIQuestiePinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    self:SetScale(ns.PinScale(self.bfiGroup or "questie", Cfg(self).scale) / canvasScale)  -- (PinScale: town view, small map)
    ns.ReanchorPin(self, map)
end

-- a quest icon's look (its icon set, the giver's level colour, a spot's quest colour), for our
-- pins and Cave.lua's minimap-style caves; true when it's drawn plain (no Questie badges)
function ns.DressQuestIcon(owner, tex, group, icon)
    local isGiver = group == "questie"
    local cfg = ns.db and ns.db[group] or {}
    -- icon sets for givers and turn-ins: Questie's or the modern map atlases
    -- (the gossip "!" and "?" stand in where neither is there)
    local isTurnin = group == "turnins"
    local set = (isGiver or isTurnin) and (cfg.iconSet or "questie") or "questie"
    -- (Questie's icons without Questie installed: the modern "!" for givers,
    -- the classic "?" for turn-ins; modern falls back to classic below where
    -- the client has no such atlas)
    if set == "questie" and (isGiver or isTurnin) and not icon.kind then set = isGiver and "modern" or "classic" end
    local modern = set == "modern" and (isGiver and "QuestNormal" or "QuestTurnin")
    if modern and not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(modern)) then
        set = "classic"
    end
    -- (Questie's set without Questie installed: the classic icons, no badges)
    local plain = set ~= "questie" or not (ns.QuestieArt and ns.QuestieArt())
    if set == "modern" then
        tex:SetAtlas(modern)
    elseif set == "classic" then
        tex:SetTexture(isTurnin and TURNIN_ICON or PLAIN_ICON)
        tex:SetTexCoord(0, 1, 0, 1)
    elseif icon.kind == "atlas" then
        tex:SetAtlas(icon.value)
    elseif icon.kind == "file" then
        tex:SetTexture(icon.value)
        tex:SetTexCoord(icon.l, icon.r, icon.t, icon.b)
    else
        tex:SetTexture(PLAIN_ICON)
        tex:SetTexCoord(0, 1, 0, 1)
    end

    -- desaturate first so the tint gives a clean color instead of tinting the yellow
    if isGiver and cfg.color and icon.level then
        -- (a grey icon tinted pure yellow comes out lemon-green: yellow stays the
        -- icon's own gold; the rest toned down for the parchment)
        local r, g, b = ns.SoftQuestColor(DifficultyColor(icon.level))
        if not r then
            tex:SetDesaturated(false)
            tex:SetVertexColor(1, 1, 1)
        else
            tex:SetDesaturated(true)
            tex:SetVertexColor(r, g, b)
        end
    elseif icon.iconColor then
        -- each quest's spots in a colour of its own (spots.color)
        tex:SetDesaturated(false)
        tex:SetVertexColor(icon.iconColor[1], icon.iconColor[2], icon.iconColor[3], 1)
    else
        tex:SetDesaturated(false)
        tex:SetVertexColor(1, 1, 1, 1)
    end
    -- the game's cursor art (spots without Questie): its pointer tip hidden
    ns.CursorMask(owner, tex, (icon.mask and icon.kind == "file" and set == "questie") and true or false, icon.r, icon.b)
    tex:SetAlpha(1)
    if tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
    end
    return plain
end

function BFIQuestiePinMixin:OnAcquired(icon)
    self.questName = icon.name
    self.questId = icon.id
    self.icon = icon  -- (who, quests, objective: for the tooltip and clicks)
    self.bfiGroup = icon.group or "questie"

    -- pins are pooled across groups, so the drawing level is picked per use
    local isGiver = self.bfiGroup == "questie"
    if self.UseFrameLevelType then
        local level = self.bfiGroup == "spots" and "PIN_FRAME_LEVEL_BFI_SPOTS" or "PIN_FRAME_LEVEL_BFI_QUESTIE"
        pcall(self.UseFrameLevelType, self, level)
        if self.ApplyFrameLevel then pcall(self.ApplyFrameLevel, self) end
    end

    local plain = ns.DressQuestIcon(self, self.Icon, self.bfiGroup, icon)

    ns.PinGlow(self, false)  -- (pooled: a glow from its last quest goes)

    local overlay = self.Overlay
    local overlayPath = isGiver and not plain and STARTER_OVERLAYS[icon.starterType or ""]
    if overlay and overlayPath then
        overlay:SetTexture(overlayPath)
        overlay:Show()
    elseif overlay then
        overlay:Hide()
    end
    self:ApplyCurrentScale()
    self:ApplyCurrentAlpha()

    -- debug aid: tint solid yellow until we confirm pins render
    if BFI_DEBUG_SQUARES then tex:SetColorTexture(1, 0.8, 0, 1) end

    self:SetPosition(icon.x / 100, icon.y / 100)
end

-- "[12] Quest name", coloured by difficulty (title, level: where QuestieDB
-- doesn't know the quest, e.g. learned ones)
local function QuestLine(id, title, level)
    level = level or ns.QuestLevelOf and ns.QuestLevelOf(id) or 0
    local r, g, b = DifficultyColor(level)
    local known = ns.QDBKnowsQuest and ns.QDBKnowsQuest(id)
    title = known and ns.QuestNameOf(id) or title or ("Quest " .. id)
    return string.format("[%d] %s", level, title), r, g, b, title
end
ns.QuestLine = QuestLine   -- (QuestData.lua's tooltip lines)

-- Tooltips ---------------------------------------------------------------------
-- The quest pins under the cursor share one tooltip, as Questie's do: each NPC
-- (givers and turn-ins) with its quests, then each quest's objectives there.
-- Shift shows more: XP, the quest text, reputation, breadcrumbs, the chain.
-- With Questie loaded its own tooltip draws it (QuestieTip, so Questie's
-- tooltip settings apply); without Questie, ours (OwnTip). Either way the
-- icons and clicks stay ours.

local MAX_QUESTS = 6      -- quests listed per NPC without Shift
local CLUSTER = 0.8       -- pins overlapping on screen share a tooltip: centres within this of a pin's size
                          -- (on screen, not map %: zoomed in, Questie's 1% took in a whole camp)
local GREY, SOFT = { 0.6, 0.6, 0.6 }, { 0.85, 0.85, 0.85 }
local GREEN, REP = { 0.2, 1, 0.2 }, { 0.4, 0.7, 1 }
local OBJECTIVE_VERBS = { slay = "Kill", loot = "Collect", object = "Use", event = "" }

-- the quest pins near this one (itself first), shown ones only
local function Cluster(pin)
    local out, map = { pin }, pin:GetMap()
    local mx, my = pin:GetCenter()
    if not (map and map.EnumeratePinsByTemplate and mx) then return out end
    local s = pin:GetEffectiveScale()
    mx, my = mx * s, my * s
    local reach = pin:GetWidth() * s * CLUSTER
    for other in map:EnumeratePinsByTemplate("BFIQuestiePinTemplate") do
        if other ~= pin and other.icon and other:IsShown() and other:GetAlpha() > 0 then
            local ox, oy = other:GetCenter()
            if ox then
                local os = other:GetEffectiveScale()
                if math.abs(ox * os - mx) < reach and math.abs(oy * os - my) < reach then out[#out + 1] = other end
            end
        end
    end
    return out
end

-- npcs: { { name, sub, quests = { { id, turnin } } } }, turn-ins first;
-- spots: { { id, lines = { icon, ... } } }, one line per objective and who
local function Gather(pins)
    local npcs, spots, byName, byQuest = {}, {}, {}, {}
    for _, p in ipairs(pins) do
        local icon = p.icon or {}
        if p.bfiGroup == "spots" then
            local q = byQuest[p.questId]
            if not q then
                q = { id = p.questId, lines = {}, seen = {} }
                byQuest[p.questId], spots[#spots + 1] = q, q
            end
            local key = (icon.who or "") .. "|" .. (icon.objective or "")
            if not q.seen[key] then q.seen[key] = true q.lines[#q.lines + 1] = icon end
        else
            local name = icon.who or p.questName or "?"
            local n = byName[name]
            if not n then
                n = { name = name, sub = icon.sub, quests = {}, seen = {} }
                byName[name], npcs[#npcs + 1] = n, n
            end
            local turnin = p.bfiGroup == "turnins"
            for _, id in ipairs(icon.quests or { p.questId }) do
                if not n.seen[id] then
                    n.seen[id] = true
                    table.insert(n.quests, turnin and 1 or #n.quests + 1, { id = id, turnin = turnin })
                end
            end
        end
    end
    return npcs, spots
end

-- Questie's tooltip, fed our quests in the shape its map icons give it: it's
-- shown for a stand-in frame over our pin (no Questie icon matches it, so only
-- what we hand it is listed). False: Questie isn't there or something failed.
local proxy, tipFailed
local function QuestieTip(pin, npcs, spots)
    if not (ns.QuestieArt() and QuestieLoader and Questie and Questie.db and Questie.db.profile) then return false end
    local ok, err = pcall(function()
        local function Mod(name) return QuestieLoader:ImportModule(name) end
        local Tip, Lib, DB, l10n = Mod("MapIconTooltip"), Mod("QuestieLib"), Mod("QuestieDB"), Mod("l10n")
        assert(Tip.ShowOnTooltip and Lib.GetColoredQuestName and DB.GetQuest)
        local function Paren(s) return l10n("(") .. l10n(s) .. l10n(")") end
        local showLevel = Questie.db.profile.enableTooltipsQuestLevel
        local npcOrder, questOrder = {}, {}
        for _, n in ipairs(npcs) do
            local t = {}
            for _, q in ipairs(n.quests) do
                local quest = DB.GetQuest(q.id)
                local title = Lib:GetColoredQuestName(q.id, showLevel, false)
                t[title] = {
                    questId = q.id, title = title, subData = quest and quest.Description,
                    type = q.turnin and Paren("Complete")
                        or (DB.IsRepeatable and DB.IsRepeatable(q.id) and Paren("Repeatable")) or Paren("Available"),
                }
            end
            npcOrder[n.name] = t
        end
        for _, s in ipairs(spots) do
            local list = {}
            for _, icon in ipairs(s.lines) do
                local have, need = (icon.objective or ""):match("(%d+)%s*/%s*(%d+)")
                local color = Lib:GetRGBForObjective({ Collected = tonumber(have), Needed = tonumber(need) })
                local who = icon.source or icon.who
                list[#list + 1] = { [color .. (icon.objective or icon.who or "")] = who and { [who] = true } or {} }
            end
            questOrder[s.id] = list
        end
        if not proxy then
            proxy = CreateFrame("Frame")
            proxy.texture = { GetVertexColor = function() return 1, 1, 1, 1 end }
        end
        proxy:SetParent(pin)
        proxy:SetAllPoints(pin)
        proxy.bfiFor = pin  -- (Shift redraws the pin's tooltip, Controls.lua: the tooltip is the proxy's)
        proxy:Show()
        proxy.data, proxy.x, proxy.y, proxy.AreaID = { Id = -1, ObjectiveIndex = 0 }, -1000, -1000, -1
        GameTooltip:Hide()  -- (Questie skips a call 0.05 s after the last while shown)
        Tip.ShowOnTooltip(proxy, GameTooltip)
        GameTooltip.npcAndObjectOrder, GameTooltip.questOrder, GameTooltip.manualOrder = npcOrder, questOrder, {}
        GameTooltip:ClearLines()
        GameTooltip:SetOwner(proxy, "ANCHOR_CURSOR")
        GameTooltip:_Rebuild()
    end)
    if not ok and not tipFailed then
        tipFailed = true  -- (once a session: ours draws it instead)
        ns.Log("Questie's tooltip failed, using ours:", tostring(err))
    end
    return ok
end


-- "135 xp " in a calm faint blue, or ""
local function XPText(id)
    local xp = ns.QuestXP and ns.QuestXP(id) or 0
    if xp <= 0 then return "" end
    return "|cff8cb4d8" .. (FormatLargeNumber and FormatLargeNumber(xp) or xp) .. " xp|r "
end

-- a quest further along (chain, breadcrumb): its line and XP, indented
local function AddLinkedQuest(id)
    local line, r, g, b = QuestLine(id)
    GameTooltip:AddDoubleLine("        " .. line, XPText(id), r, g, b, 1, 1, 1)
end

-- a long text as indented lines, each its own: the tooltip's wrap starts its
-- second line at the left edge, out of the indent
local TEXT_WIDTH = 280   -- px, the text's lines at most
local measure
local function AddIndented(indent, text, r, g, b)
    if not measure then
        measure = UIParent:CreateFontString(nil, "OVERLAY")
        measure:Hide()
    end
    measure:SetFontObject(GameTooltipText)
    local line = ""
    for word in text:gmatch("%S+") do
        local try = line == "" and word or line .. " " .. word
        measure:SetText(indent .. try)
        if line ~= "" and measure:GetStringWidth() > TEXT_WIDTH then
            GameTooltip:AddLine(indent .. line, r, g, b)
            line = word
        else
            line = try
        end
    end
    if line ~= "" then GameTooltip:AddLine(indent .. line, r, g, b) end
end

-- Shift's extras for one quest: dungeon, text, reputation, breadcrumbs, chain
local function AddMore(id, withText)
    local more = ns.QuestMore and ns.QuestMore(id) or {}
    if more.dungeon then GameTooltip:AddLine("      Instance: " .. more.dungeon, 0.7, 0.7, 0.7) end
    local text = withText and (ns.QuestDetails(id) or {}).text
    if text and text ~= "" then AddIndented("      ", text, SOFT[1], SOFT[2], SOFT[3]) end
    local rw = ns.QuestRewards and ns.QuestRewards(id)
    if rw then
        local function Item(e)
            local _, _, quality, _, _, _, sub, _, slot = GetItemInfo(e[1])
            local r, g, b = 1, 1, 1
            if quality and GetItemQualityColor then r, g, b = GetItemQualityColor(quality) end
            if not quality and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, e[1]) end
            local kind = sub and sub ~= "" and sub or (slot and _G[slot]) or ""
            GameTooltip:AddDoubleLine("        " .. e[2] .. (e[3] > 1 and " x" .. e[3] or ""), kind, r, g, b, GREY[1], GREY[2], GREY[3])
        end
        if rw.choice[1] then
            GameTooltip:AddLine("      " .. (#rw.choice > 1 and "Choose one:" or "Reward:"), GREY[1], GREY[2], GREY[3])
            for _, e in ipairs(rw.choice) do Item(e) end
        end
        if rw.fixed[1] then
            GameTooltip:AddLine("      " .. (rw.choice[1] and "And:" or "Reward:"), GREY[1], GREY[2], GREY[3])
            for _, e in ipairs(rw.fixed) do Item(e) end
        end
        if rw.copper and GetCoinTextureString then
            GameTooltip:AddLine("      " .. GetCoinTextureString(rw.copper), 1, 1, 1)
        end
    end
    for _, rep in ipairs(more.rep or {}) do
        GameTooltip:AddLine(string.format("      %+d %s", rep[2], rep[1]), REP[1], REP[2], REP[3])
    end
    if more.breadcrumbs and more.breadcrumbs[1] then
        GameTooltip:AddLine("Breadcrumb quests:", SOFT[1], SOFT[2], SOFT[3])  -- (from the line's start, as chain's)
        for _, b in ipairs(more.breadcrumbs) do AddLinkedQuest(b) end
    end
    if more.chain and more.chain[1] then
        GameTooltip:AddLine("Next in chain:", SOFT[1], SOFT[2], SOFT[3])  -- (from the line's start: the user)
        for _, c in ipairs(more.chain) do AddLinkedQuest(c) end
    end
end

-- ours (mock-up mockups\quest-tooltip.html, C): the giver's name in gold, then a
-- line a quest: its ! (or ?) and name in the quest's difficulty colour, on the
-- right its tag (Group, Dungeon...) and what it asks in a word. Shift: its XP, text
-- and the extras. Objective spots: their quest, then each objective
local TAG, WORD = "|cffff9a40", "|cff999999"
local TAG_COLOR = { Raid = "|cff2e9a3c", PvP = "|cffb8352a" }   -- (a tag's own colour; the rest TAG's orange)
local function OwnTip(pin, npcs, spots, shift)
    GameTooltip:SetOwner(pin, "ANCHOR_CURSOR")
    local first = true
    local function Head(text, r, g, b, right)
        if first and not shift then
            GameTooltip:AddDoubleLine(text, "(Hold Shift)", r, g, b, 0.43, 0.43, 0.43)
        else
            if not first then GameTooltip:AddLine(" ") end
            GameTooltip:AddDoubleLine(text, right or "", r, g, b, 1, 1, 0)
        end
        first = false
    end
    for _, n in ipairs(npcs) do
        if not first then GameTooltip:AddLine(" ") end
        first = false
        GameTooltip:AddLine(n.name, 1, 0.82, 0)   -- (no <title> under it: quiet before Shift)
        for i, q in ipairs(n.quests) do
            if i > MAX_QUESTS and not shift then
                GameTooltip:AddLine(string.format("  ...and %d more", #n.quests - MAX_QUESTS), GREY[1], GREY[2], GREY[3])
                break
            end
            local d = ns.QuestDetails and ns.QuestDetails(q.id) or {}
            local _, r, g, b, title = QuestLine(q.id, q.title, q.level)
            local mr, mg, mb = r, g, b
            if q.turnin then mr, mg, mb = 1, 0.82, 0
            elseif d.repeatable or q.repeatable then mr, mg, mb = 0.3, 0.65, 1 end
            local word, tag
            if ns.QuestKind then word, tag = ns.QuestKind(q.id) end
            local right = tag and (TAG_COLOR[tag] or TAG) .. tag .. "|r" or ""
            local sep = right ~= "" and "  " or ""
            if q.turnin then
                right = right .. sep .. "|cff33ff33Complete|r"
            elseif shift then
                right = right .. sep .. XPText(q.id)
            elseif word then
                -- (in its kind's colour, as on quest ground; grey without one)
                local wr, wg, wb
                if ns.QuestTypeColor then wr, wg, wb = ns.QuestTypeColor(word) end
                local wc = wr and string.format("|cff%02x%02x%02x", wr * 255, wg * 255, wb * 255) or WORD
                right = right .. (right ~= "" and " · " or "") .. wc .. word .. "|r"
            end
            GameTooltip:AddDoubleLine(string.format("|cff%02x%02x%02x%s|r  %s", mr * 255, mg * 255, mb * 255,
                q.turnin and "?" or "!", title), right, r, g, b, 1, 1, 1)
            if d.items and d.items[1] then
                GameTooltip:AddLine("      Starts from: " .. table.concat(d.items, ", "), GREY[1], GREY[2], GREY[3])
            end
            if shift then AddMore(q.id, true) end
        end
    end
    if #npcs > 0 and not shift then ns.HoldShift() end  -- (what they ask, and the hints)
    for _, s in ipairs(spots) do
        local line, r, g, b = QuestLine(s.id)
        Head(line, r, g, b, shift and XPText(s.id) or nil)
        for _, icon in ipairs(s.lines) do
            local have, need = (icon.objective or ""):match("(%d+)%s*/%s*(%d+)")
            local done = have and tonumber(have) >= tonumber(need)
            local c = done and GREEN or SOFT
            if shift and icon.who then
                local verb = OBJECTIVE_VERBS[icon.objIcon or ""] or ""
                GameTooltip:AddLine("    " .. (verb ~= "" and verb .. ": " or "") .. icon.who, 1, 1, 1)
                if icon.source and icon.source ~= icon.who then
                    local ch = ns.ChanceText and ns.ChanceText(icon.chance)
                    GameTooltip:AddLine("      Dropped by " .. icon.source .. (ch and ", " .. ch or ""), GREY[1], GREY[2], GREY[3])
                end
            end
            local text = icon.objective or icon.who
            if text and not (shift and text == icon.who) then
                GameTooltip:AddLine((shift and "      " or "    ") .. text, c[1], c[2], c[3], true)
            end
        end
        if shift then AddMore(s.id, false) end
    end
end

-- the pin under the cursor: Shift down or up redraws its tooltip (Controls.lua)
local hovered

-- Every tooltip over the map (any pin, ours or not, and the map's buttons):
-- pins.tipScale of its size, back to normal when it hides or moves elsewhere.
-- Hooked on Show and SetOwner, which run on every call (OnShow only fires
-- going from hidden to shown). The tooltip's scale is tried first. Frame
-- movers like MoveAny hold GameTooltip at their own scale (they hook
-- SetScale and put theirs back), so where it doesn't stick, the text is
-- made smaller instead and the tooltip re-fitted to it.
local baseScale, fitting
local shrunk = {}  -- [fontString] = { path, size, flags } as it was
local function OnTheMap(frame)
    local map = BattlefieldMapFrame
    while frame and map do
        if frame == map then return true end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end
local function RestoreFonts()
    for fs, f in pairs(shrunk) do fs:SetFont(f[1], f[2], f[3]) end
    wipe(shrunk)
end
-- each line's text at s of its size (lines added since, or reset by the
-- game, are caught on the next Show); true if any changed
local function ShrinkFonts(tip, s)
    local name, changed = tip:GetName(), false
    for i = 1, tip:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G[name .. "Text" .. side .. i]
            local path, size, flags
            if fs then path, size, flags = fs:GetFont() end
            if path and size then
                local f = shrunk[fs]
                if not (f and math.abs(size - f[2] * s) < 0.05) then
                    shrunk[fs] = { path, size, flags }
                    fs:SetFont(path, size * s, flags)
                    changed = true
                end
            end
        end
    end
    return changed
end
local function Restore(tip)
    if baseScale then
        tip:SetScale(baseScale)
        baseScale = nil
    end
    if next(shrunk) then RestoreFonts() end
end
local function ApplyTipScale(tip)
    if fitting then return end
    local s = ns.db and ns.db.pins and ns.db.pins.tipScale or 1
    local owner = tip.GetOwner and tip:GetOwner()
    if not (s ~= 1 and OnTheMap(owner)) then
        Restore(tip)
        return
    end
    baseScale = baseScale or tip:GetScale()
    tip:SetScale(baseScale * s)
    local how = "scale"
    if math.abs(tip:GetScale() - baseScale * s) > 0.01 then
        -- (held at another scale: the text instead, then fit the tooltip to it)
        how = "text"
        if tip:IsShown() and ShrinkFonts(tip, s) then
            fitting = true
            tip:Show()
            fitting = false
        end
    end
    ns.lastMapTip = { owner = owner.GetName and owner:GetName() or tostring(owner), scale = tip:GetScale(), how = how }
end
hooksecurefunc(GameTooltip, "Show", ApplyTipScale)
hooksecurefunc(GameTooltip, "SetOwner", ApplyTipScale)
GameTooltip:HookScript("OnShow", ApplyTipScale)
GameTooltip:HookScript("OnHide", Restore)

-- Any quest pin's tooltip (Learn.lua's too): npcs / spots as Gather makes
-- them (a quest may carry title, level, repeatable of its own); questie:
-- Questie's tooltip where it's loaded; hints: grey lines at the bottom
function ns.QuestTooltip(pin, npcs, spots, questie, hints)
    hovered = pin
    ns.ShiftRefresh(pin, function(p) p:OnEnter() end)
    -- (objective spots alone: Questie's where loaded; givers and turn-ins too with
    -- questie.tooltip on, else ours)
    local theirs = questie and (#npcs == 0 or ns.db.questie.tooltip)
    if not (theirs and QuestieTip(pin, npcs, spots)) then
        GameTooltip.ShownAsMapIcon, GameTooltip._Rebuild = nil, nil
        OwnTip(pin, npcs, spots or {}, IsShiftKeyDown())
    end
    for _, h in ipairs(hints or {}) do GameTooltip:AddLine(h, 0.5, 0.5, 0.5) end
    GameTooltip:Show()
end

function ns.QuestTooltipLeave()
    hovered = nil
    GameTooltip:Hide()
    -- (Questie's own icons do this on leave; its unit tooltips wait on it)
    GameTooltip.ShownAsMapIcon, GameTooltip._Rebuild = false, nil
    if proxy then proxy:Hide() end
end

-- (the Quest log page's "also from its pins": a click on a spot or turn-in of a quest in your
-- log opens its page, Tracker.lua; a spot's glow is then in its menu)
local function OpensQuestWindow(self)
    local q = ns.db and ns.db.questlog
    return q and q.shown and q.fromPins and (self.bfiGroup == "spots" or self.bfiGroup == "turnins") and self.questId
end

function BFIQuestiePinMixin:OnEnter()
    local npcs, spots = Gather(Cluster(self))
    ns.QuestTooltip(self, npcs, spots, true)
    ns.PinHints({ OpensQuestWindow(self) and { "Click", "open in quest log" } or self.bfiGroup == "spots" and { "Click", "keep its quest's spots lit" } or nil,
                  self.questId and { "Shift-click", "link it in chat" } or nil,
                  TomTom and TomTom.AddWaypoint and { "Ctrl-click", "a TomTom arrow" } or nil })
    GameTooltip:Show()
    -- an objective spot: all of its quest's spots glow (Tracker.lua)
    if self.bfiGroup == "spots" and ns.HoverQuestGlow then ns.HoverQuestGlow(self.questId) end
end

function BFIQuestiePinMixin:OnLeave()
    ns.QuestTooltipLeave()
    if ns.HoverQuestGlow then ns.HoverQuestGlow(nil) end
end
-- one quest icon's tooltip, for Cave.lua's minimap-style caves (owner: a frame with an
-- OnEnter method, for Shift's refresh)
function ns.QuestIconTooltip(owner, icon)
    local npcs, spots = Gather({ { icon = icon, bfiGroup = icon.group, questId = icon.id, questName = icon.name } })
    ns.QuestTooltip(owner, npcs, spots, true)
end

-- the map wires a pin's mouse-over to these (see Pin.xml)
BFIQuestiePinMixin.OnMouseEnter = BFIQuestiePinMixin.OnEnter
BFIQuestiePinMixin.OnMouseLeave = BFIQuestiePinMixin.OnLeave

-- Click (an objective spot): its quest's spots lit; Ctrl-click: a TomTom arrow to the pin
-- (again: off); Shift-click with chat open: a link to the quest. Right-click: its menu (the
-- quest's page, the arrow, the glow, hiding a giver's quests: asks first, /bfi unhide brings
-- them back)
StaticPopupDialogs["BFI_HIDE_QUESTS"] = {
    text = "Hide %s from the map?\n(/waymark unhide shows them again)",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data) if ns.HideQuests then ns.HideQuests(data) end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function QuestArrow(self)
    local icon = self.icon or {}
    if not icon.x then return end
    ns.PinArrow(self, (icon.who and icon.who .. ": " or "") .. (self.questName or ""), icon.x / 100, icon.y / 100)
end

function BFIQuestiePinMixin:OnMouseUp(button)
    local icon = self.icon or {}
    if button == "RightButton" then
        local items = {}
        local quests = icon.quests or { self.questId }
        if #quests > 1 and ns.OpenQuest then
            -- a giver with several: a row for each quest's details, by name
            for _, id in ipairs(quests) do
                local _, _, _, _, title = QuestLine(id)
                items[#items + 1] = { "details: " .. title, function() ns.OpenQuest(id) end }
            end
        elseif self.questId and ns.OpenQuest then
            items[#items + 1] = { "quest details", function() ns.OpenQuest(self.questId) end }
        end
        if self.bfiGroup == "spots" and self.questId and ns.ToggleQuestGlow then
            items[#items + 1] = { "its spots lit (again: off)", function() ns.ToggleQuestGlow(self.questId) end }
        end
        if self.bfiGroup == "questie" then
            local what = #quests == 1 and ("\"" .. (self.questName or "") .. "\"") or (#quests .. " quests")
            items[#items + 1] = { #quests == 1 and "hide this quest" or "hide these quests", function()
                StaticPopup_Show("BFI_HIDE_QUESTS", what, nil, quests)
            end }
        end
        if TomTom and TomTom.AddWaypoint and icon.x then
            items[#items + 1] = { "a TomTom arrow to it", function() QuestArrow(self) end }
        end
        if #items > 0 and ns.QuillMenu then ns.QuillMenu(items) end
        return
    end
    if button ~= "LeftButton" then return end
    if IsControlKeyDown() and TomTom and TomTom.AddWaypoint then
        QuestArrow(self)
    elseif IsShiftKeyDown() then
        -- (as everywhere in the game: a link, with chat open)
        local edit = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if edit and self.questId then
            local level = ns.QuestLevelOf and ns.QuestLevelOf(self.questId) or 0
            ChatEdit_InsertLink(string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", self.questId, level, self.questName or ""))
        end
    elseif OpensQuestWindow(self) and ns.ShowQuestWindow then
        ns.ShowQuestWindow(self.questId)
    elseif self.bfiGroup == "spots" and self.questId and ns.ToggleQuestGlow then
        -- an objective spot: its quest's glow held on until clicked again (Tracker.lua)
        ns.ToggleQuestGlow(self.questId)
    end
end
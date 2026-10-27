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
local CURSOR_MASK = "Interface\\AddOns\\BattlefieldInfo\\Media\\CursorMask"
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
function ns.SafePassthrough(self, ...)
    if InCombatLockdown and InCombatLockdown() then return end
    if MapCanvasPinMixin and MapCanvasPinMixin.CheckMouseButtonPassthrough then
        MapCanvasPinMixin.CheckMouseButtonPassthrough(self, ...)
    end
end
-- (with the Quest log page's "from a quest's spot or turn-in", those pins keep
-- their right-click: it opens the quest window, Tracker.lua)
local function OpensQuestWindow(self)
    local q = ns.db and ns.db.questlog
    return q and q.shown and q.fromPins and (self.bfiGroup == "spots" or self.bfiGroup == "turnins") and self.questId
end
function BFIQuestiePinMixin:CheckMouseButtonPassthrough(...)
    if not OpensQuestWindow(self) then return ns.SafePassthrough(self, ...) end
    local keep = {}
    for i = 1, select("#", ...) do
        local b = select(i, ...)
        if b ~= "RightButton" then keep[#keep + 1] = b end
    end
    return ns.SafePassthrough(self, unpack(keep))
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

    local cfg = Cfg(self)
    local tex = self.Icon
    -- icon sets for givers and turn-ins: Questie's or the modern map atlases
    -- (the gossip "!" and "?" stand in where neither is there)
    local isTurnin = self.bfiGroup == "turnins"
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
    ns.CursorMask(self, tex, (icon.mask and icon.kind == "file" and set == "questie") and true or false, icon.r, icon.b)
    tex:SetAlpha(1)
    if tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
    end

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
    return string.format("[%d] %s", level, title), r, g, b
end

-- Tooltips ---------------------------------------------------------------------
-- The quest pins under the cursor share one tooltip, as Questie's do: each NPC
-- (givers and turn-ins) with its quests, then each quest's objectives there.
-- Shift shows more: XP, the quest text, reputation, breadcrumbs, the chain.
-- With Questie loaded its own tooltip draws it (QuestieTip, so Questie's
-- tooltip settings apply); without Questie, ours (OwnTip). Either way the
-- icons and clicks stay ours.

local MAX_QUESTS = 6      -- quests listed per NPC without Shift
local CLUSTER = 1         -- map %: pins this close share a tooltip (Questie's distance)
local GREY, SOFT = { 0.6, 0.6, 0.6 }, { 0.85, 0.85, 0.85 }
local GREEN, REP = { 0.2, 1, 0.2 }, { 0.4, 0.7, 1 }
local OBJECTIVE_VERBS = { slay = "Kill", loot = "Collect", object = "Use", event = "" }

-- the quest pins near this one (itself first), shown ones only
local function Cluster(pin)
    local out, me, map = { pin }, pin.icon, pin:GetMap()
    if not (map and map.EnumeratePinsByTemplate and me and me.x) then return out end
    for other in map:EnumeratePinsByTemplate("BFIQuestiePinTemplate") do
        local o = other.icon
        if other ~= pin and o and o.x and other:IsShown() and other:GetAlpha() > 0
           and math.abs(o.x - me.x) < CLUSTER and math.abs(o.y - me.y) < CLUSTER then
            out[#out + 1] = other
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

local function Hex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end

-- "(135 xp) " in the quest's difficulty colour, or ""
local function XPText(id)
    local xp = ns.QuestXP and ns.QuestXP(id) or 0
    if xp <= 0 then return "" end
    local r, g, b = DifficultyColor(ns.QuestLevelOf and ns.QuestLevelOf(id) or 0)
    return Hex(r, g, b) .. "(" .. (FormatLargeNumber and FormatLargeNumber(xp) or xp) .. " xp)|r "
end

-- a quest further along (chain, breadcrumb): its line and XP, indented
local function AddLinkedQuest(id)
    local line, r, g, b = QuestLine(id)
    GameTooltip:AddDoubleLine("        " .. line, XPText(id), r, g, b, 1, 1, 1)
end

-- Shift's extras for one quest: dungeon, text, reputation, breadcrumbs, chain
local function AddMore(id, withText)
    local more = ns.QuestMore and ns.QuestMore(id) or {}
    if more.dungeon then GameTooltip:AddLine("      Instance: " .. more.dungeon, 0.7, 0.7, 0.7) end
    local text = withText and (ns.QuestDetails(id) or {}).text
    if text and text ~= "" then GameTooltip:AddLine("      " .. text, SOFT[1], SOFT[2], SOFT[3], true) end
    for _, rep in ipairs(more.rep or {}) do
        GameTooltip:AddLine(string.format("      %+d %s", rep[2], rep[1]), REP[1], REP[2], REP[3])
    end
    if more.breadcrumbs and more.breadcrumbs[1] then
        GameTooltip:AddLine("      Breadcrumb quests:", SOFT[1], SOFT[2], SOFT[3])
        for _, b in ipairs(more.breadcrumbs) do AddLinkedQuest(b) end
    end
    if more.chain and more.chain[1] then
        GameTooltip:AddLine("      Next in chain:", SOFT[1], SOFT[2], SOFT[3])
        for _, c in ipairs(more.chain) do AddLinkedQuest(c) end
    end
end

-- ours, laid out as Questie's: NPC in green, "(Hold Shift)" on the first line,
-- each quest with its state on the right (with Shift: its XP and the extras)
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
        Head(n.name, GREEN[1], GREEN[2], GREEN[3])
        if n.sub and n.sub ~= "" then GameTooltip:AddLine("<" .. n.sub .. ">", GREY[1], GREY[2], GREY[3]) end
        for i, q in ipairs(n.quests) do
            if i > MAX_QUESTS and not shift then
                GameTooltip:AddLine(string.format("  ...and %d more", #n.quests - MAX_QUESTS), GREY[1], GREY[2], GREY[3])
                break
            end
            local d = ns.QuestDetails and ns.QuestDetails(q.id) or {}
            local line, r, g, b = QuestLine(q.id, q.title, q.level)
            local state = q.turnin and "(Complete)" or (d.repeatable or q.repeatable) and "(Repeatable)" or "(Available)"
            GameTooltip:AddDoubleLine("  " .. line, (shift and XPText(q.id) or "") .. state, r, g, b, 1, 1, 0)
            if d.items and d.items[1] then
                GameTooltip:AddLine("      Starts from: " .. table.concat(d.items, ", "), GREY[1], GREY[2], GREY[3])
            end
            if shift then AddMore(q.id, true) end
        end
    end
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
                    GameTooltip:AddLine("      Dropped by " .. icon.source, GREY[1], GREY[2], GREY[3])
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

-- the pin under the cursor: Shift down or up redraws its tooltip
local hovered
local modifiers = CreateFrame("Frame")
modifiers:RegisterEvent("MODIFIER_STATE_CHANGED")
modifiers:SetScript("OnEvent", function()
    if hovered and hovered:IsShown() and hovered:IsMouseOver() and GameTooltip:IsShown() then hovered:OnEnter() end
end)

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
    if not (questie and QuestieTip(pin, npcs, spots)) then
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

function BFIQuestiePinMixin:OnEnter()
    local npcs, spots = Gather(Cluster(self))
    local hints = {}
    if TomTom and TomTom.AddWaypoint then hints[#hints + 1] = "Ctrl-click: TomTom arrow" end
    if self.bfiGroup == "questie" then hints[#hints + 1] = "Shift-click: hide" end
    ns.QuestTooltip(self, npcs, spots, true, { #hints > 0 and table.concat(hints, "   ") or nil })
    -- an objective spot: all of its quest's spots glow (Tracker.lua)
    if self.bfiGroup == "spots" and ns.HoverQuestGlow then ns.HoverQuestGlow(self.questId) end
end

function BFIQuestiePinMixin:OnLeave()
    ns.QuestTooltipLeave()
    if ns.HoverQuestGlow then ns.HoverQuestGlow(nil) end
end
-- the map wires a pin's mouse-over to these (see Pin.xml)
BFIQuestiePinMixin.OnMouseEnter = BFIQuestiePinMixin.OnEnter
BFIQuestiePinMixin.OnMouseLeave = BFIQuestiePinMixin.OnLeave

-- Ctrl-click: a TomTom arrow to the pin (again: off); Shift-click with chat
-- open: a link to the quest; Shift-click on a giver: hide its quests (asks
-- first; /bfi unhide brings them back). Plain clicks do nothing.
local tomtomUid
StaticPopupDialogs["BFI_HIDE_QUESTS"] = {
    text = "Hide %s from the map?\n(/bfi unhide shows them again)",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data) if ns.HideQuests then ns.HideQuests(data) end end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function BFIQuestiePinMixin:OnMouseUp(button)
    if ns.PinAltClick and ns.PinAltClick(self, button) then return end  -- line target (Line.lua)
    if button == "RightButton" and OpensQuestWindow(self) and ns.ShowQuestWindow then
        ns.ShowQuestWindow(self.questId)
        return
    end
    if button ~= "LeftButton" then return end
    local icon = self.icon or {}
    if IsControlKeyDown() and TomTom and TomTom.AddWaypoint then
        if tomtomUid and TomTom.RemoveWaypoint then
            pcall(TomTom.RemoveWaypoint, TomTom, tomtomUid)
            tomtomUid = nil
            return
        end
        local mapID = self:GetMap() and self:GetMap():GetMapID()
        if mapID and icon.x then
            local ok, uid = pcall(TomTom.AddWaypoint, TomTom, mapID, icon.x / 100, icon.y / 100,
                { title = (icon.who and icon.who .. ": " or "") .. (self.questName or ""), from = "Battlefield Info" })
            if ok then tomtomUid = uid end
        end
    elseif IsShiftKeyDown() then
        local edit = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if edit and self.questId then
            local level = ns.QuestLevelOf and ns.QuestLevelOf(self.questId) or 0
            ChatEdit_InsertLink(string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", self.questId, level, self.questName or ""))
        elseif self.bfiGroup == "questie" then
            local quests = icon.quests or { self.questId }
            local what = #quests == 1 and ("\"" .. (self.questName or "") .. "\"") or (#quests .. " quests")
            StaticPopup_Show("BFI_HIDE_QUESTS", what, nil, quests)
        end
    elseif self.bfiGroup == "spots" and self.questId and ns.ToggleQuestGlow then
        -- an objective spot: its quest's glow held on until clicked again (Tracker.lua)
        ns.ToggleQuestGlow(self.questId)
    end
end
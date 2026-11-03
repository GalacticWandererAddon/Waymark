local _, ns = ...

-- Doors, chests, switches, quest things and friendly NPCs on the dungeon map (Data\DungeonObjects.lua):
-- which door wants which key, which open with a fight, where the chests, switches, the things quests
-- send you to, and the quest givers, trainers and vendors are; also on the outside caves before it.
--  dungeon.objects = "icons":  a small round icon on each, its tooltip on hover
--                    "hidden": no icons, the tooltip still shows over the spot (so a quill mark
--                              drawn there carries it)
--                    "off":    nothing
--  dungeon.objectScale: the icons' size.
--  dungeon.allChests / allQuests: also the lesser chests (only sometimes there) and the quest things
--                    found all over a floor; patrols: the monsters that walk, their way in dots.
-- The lesser ones (a door that opens with the fight, a chest that's only sometimes there) are
-- smaller and fainter; several of the same thing close together are one icon with a count;
-- an icon that would sit on a boss marker moves aside.
-- With the quill in hand (Notebook.lua) a pin can be dragged where it belongs; right-click: put it
-- back, or hide it (ns.db.objectSpots, ns.db.objectHidden). With the quill the pins show even in
-- "hidden" (faintly), and a pin you hid shows fainter still, to bring it back.
-- A layer on the floor's canvas (ns.DungeonInkSurface, as the found notes' rings), in the
-- picture's own pixels, so the icons grow and shrink with the map; looked at a few times a second.
-- Otherwise hover only: clicks go through to the map and the quill.

local SHEET = ns.MEDIA .. "DungeonPins"
local CELLS = 16                                               -- (64 px cells, left to right)
local CELL = { locked = 0, event = 1, chest = 2, switch = 3, postbox = 4, fire = 5, rune = 6, gear = 7,
               quest = 8, npc = 9, patrol = 12, dot = 13 }  -- (10: the reticle, 11: the old easy-pull mark: unused)
-- a monster a quest sends you to wears the quest pin: a dungeon's (or cave's) quest is a quest
-- like any other here, and the reticle is never ours for slay quests (the user, 2026-11-02)
CELL.mob = CELL.quest
local DOT = 3                                                  -- a patrol's dots: size, and...
local DOT_GAP = 9                                              -- ...px between them, on the picture
local SIZE = 24                                                -- on the 1002 x 668 picture
local MINOR = 0.72                                             -- the lesser ones' size and...
local MINOR_ALPHA = 0.7                                        -- ...strength
local BOSS_CLEAR = 20                                          -- px kept between an icon and a boss marker

local layer, sig
local pins, dots = {}, {}
local onCave = false  -- (on a minimap-style outside cave, Cave.lua, not the dungeon map)

local function Minor(o)
    return o[8] or o[1] == "event" or (o[5] or ""):find("^Sometimes here") ~= nil
end

local function Pin(i)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Frame", nil, layer)
    p.bfiTag = "object pin"
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetAllPoints()
    p.tex:SetTexture(SHEET)
    p.count = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.count:SetPoint("CENTER", p, "TOPRIGHT", -3, -3)
    p.count:SetTextColor(1, 0.9, 0.6)
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.name .. (self.n and ("  (" .. self.n .. ")") or ""), 1, 0.82, 0.3)
        for line in (self.note or ""):gmatch("[^\n]+") do GameTooltip:AddLine(line, 1, 1, 1, true) end
        if self.hidden then GameTooltip:AddLine("Hidden: shown only while the quill's out.", 0.6, 0.8, 1, true) end
        local quill = ns.QuillOut()
        ns.Hints({ { quill and "Drag" or "Ctrl-drag", "move it" },
                   { "Right-click", self.hidden and "show it again" or "put it back, or hide it" } })
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- (Controls.lua) picked up with Ctrl, or the quill out; right-click: its menu, quill or not;
    -- any other press is the map's under it (the quill's catcher, else the dungeon map: a drag pans)
    p:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if ns.PicksUp() then
            self.dragging = { GetCursorPosition() }
            GameTooltip:Hide()
            return
        end
        self.handed = true
        if onCave then return ns.CaveViewPress(true, button) end
        if not (ns.InkCatcherPress and ns.InkCatcherPress(true, button)) and ns.DungeonMapDown then ns.DungeonMapDown(button) end
    end)
    p:SetScript("OnMouseUp", function(self, button)
        local spots = ns.db.objectSpots
        if button == "LeftButton" and self.handed then
            self.handed = nil
            if onCave then return ns.CaveViewPress(false, button) end
            if not (ns.InkCatcherPress and ns.InkCatcherPress(false, button)) and ns.DungeonMapUp then ns.DungeonMapUp(button) end
            return
        end
        if button == "RightButton" then
            local fk, k = self.floorKey, self.key
            local hid = ns.db.objectHidden
            local function Hide(on)
                hid[fk] = hid[fk] or {}
                hid[fk][k] = on or nil
                sig = nil
            end
            local items = {}
            if self.hidden then
                items[#items + 1] = { "show it again", function() Hide(false) end }
            else
                if spots[fk] and spots[fk][k] then
                    items[#items + 1] = { "back to its place", function() spots[fk][k] = nil; sig = nil end }
                end
                items[#items + 1] = { "hide this pin", function() Hide(true) end }
            end
            if ns.QuillMenu then ns.QuillMenu(items) end
        elseif self.dragging then
            local d = self.dragging
            self.dragging = false
            local cx, cy = GetCursorPosition()
            if math.abs(cx - d[1]) + math.abs(cy - d[2]) < 4 * UIParent:GetEffectiveScale() then sig = nil return end  -- (a click: no move)
            local x, y = self:GetCenter()
            local s = self:GetEffectiveScale() / layer:GetEffectiveScale()
            x, y = x * s - layer:GetLeft(), layer:GetTop() - y * s
            spots[self.floorKey] = spots[self.floorKey] or {}
            spots[self.floorKey][self.key] = { math.floor(x / 1002 * 10000 + 0.5) / 10000, math.floor(y / 668 * 10000 + 0.5) / 10000 }
            sig = nil
        end
    end)
    p:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        if not IsMouseButtonDown("LeftButton") then return end
        local cx, cy = GetCursorPosition()
        local s = layer:GetEffectiveScale()
        local x = math.max(0, math.min(1002, cx / s - layer:GetLeft()))
        local y = math.max(0, math.min(668, layer:GetTop() - cy / s))
        self:ClearAllPoints()
        self:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
    end)
    pins[i] = p
    return p
end

-- the boss markers' spots on this floor (yours over the shipped ones, as Dungeon.lua), in picture px
local function BossSpots(inst, floor)
    local out = {}
    local mine = ns.db.bossSpots and ns.db.bossSpots[inst] or {}
    for name, s in pairs(ns.DungeonBosses and ns.DungeonBosses[inst] or {}) do
        if mine[name] == nil and s[1] == floor then out[#out + 1] = { s[2] * 1002, s[3] * 668 } end
    end
    for _, s in pairs(mine) do
        if s and s[1] == floor then out[#out + 1] = { s[2] * 1002, s[3] * 668 } end
    end
    return out
end

-- a spot moved straight away from any boss marker it would cover
local function Clear(x, y, bosses)
    for _ = 1, 3 do
        local moved = false
        for _, b in ipairs(bosses) do
            local dx, dy = x - b[1], y - b[2]
            local d = math.sqrt(dx * dx + dy * dy)
            if d < BOSS_CLEAR then
                if d < 0.5 then dx, dy, d = 1, 0, 1 end
                x, y = b[1] + dx / d * BOSS_CLEAR, b[2] + dy / d * BOSS_CLEAR
                moved = true
            end
        end
        if not moved then break end
    end
    return x, y
end

-- what this floor shows: its pins the settings let through, and a pin for each patrol (at the middle
-- of its way, carrying its tooltip)
local function Shown(c, list, patrols)
    local out = {}
    for _, o in ipairs(list or {}) do
        local minor = Minor(o)
        local k = o[1]
        if (k == "chest" and minor and not c.allChests) or ((k == "quest" or k == "mob") and minor and not c.allQuests)
           or k == "danger" or (k == "patrol" and c.patrols == false) then  -- ("danger": easy pulls, gone)
            -- (left out)
        else
            out[#out + 1] = o
        end
    end
    if c.patrols ~= false then
        for _, pt in ipairs(patrols or {}) do
            local w = pt[3]
            local m = math.floor(#w / 4) * 2 + 1            -- (its middle point)
            out[#out + 1] = { "patrol", w[m], w[m + 1], pt[1], pt[2] }
        end
    end
    return out
end

local function Dot(i)
    local d = dots[i]
    if d then return d end
    d = layer:CreateTexture(nil, "ARTWORK")
    d:SetTexture(SHEET)
    d:SetTexCoord(CELL.dot / CELLS, (CELL.dot + 1) / CELLS, 0, 1)
    d:SetVertexColor(0.85, 0.32, 0.22)
    dots[i] = d
    return d
end

-- each patrol's way as dots DOT_GAP px apart along it
local function DrawWays(patrols, scale, on)
    local n = 0
    if on then
        for _, pt in ipairs(patrols or {}) do
            local w, carry = pt[3], 0
            for j = 1, #w - 3, 2 do
                local x0, y0, x1, y1 = w[j] * 1002, w[j + 1] * 668, w[j + 2] * 1002, w[j + 3] * 668
                local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
                local t = carry
                while t < len do
                    n = n + 1
                    local d = Dot(n)
                    d:SetSize(DOT * scale, DOT * scale)
                    d:ClearAllPoints()
                    d:SetPoint("CENTER", layer, "TOPLEFT", x0 + (x1 - x0) * t / len, -(y0 + (y1 - y0) * t / len))
                    d:SetAlpha(0.7)
                    d:Show()
                    t = t + DOT_GAP * scale
                end
                carry = t - len
            end
        end
    end
    for i = n + 1, #dots do dots[i]:Hide() end
end

local function Hide()
    if layer then layer:Hide() end
    sig = nil
end

local function Update()
    local c = ns.db.dungeon
    local mode = c.objects or "icons"
    local scale = c.objectScale or 1
    local canvas, key = ns.DungeonInkSurface()
    onCave = false
    -- (else a dungeon's outside cave in the minimap style: Cave.lua; presses there are its view's)
    if not canvas and ns.CavePinSurface then
        canvas, key = ns.CavePinSurface()
        onCave = canvas ~= nil
    end
    local inst, floor = (key or ""):match("^d(%d+):(%w+)$")
    inst, floor = tonumber(inst), tonumber(floor) or floor  -- ("out", "out2": the outside caves)
    local list = inst and ns.DungeonObjects and ns.DungeonObjects[inst]
    list = list and list[floor]
    local patrols = inst and ns.DungeonPatrols and ns.DungeonPatrols[inst]
    patrols = patrols and patrols[floor]
    if mode == "off" or not (list or patrols) then return Hide() end
    if not layer then layer = CreateFrame("Frame", nil, canvas) end
    if layer:GetParent() ~= canvas then layer:SetParent(canvas) sig = nil end  -- (another surface: laid out again)
    local writing = ns.Quill and ns.Quill() and true or false
    for _, p in ipairs(pins) do if p.dragging then return end end  -- (not while one's being moved)
    local s = key .. ":" .. mode .. ":" .. scale .. ":" .. tostring(writing) .. ":" .. tostring(c.allChests) .. tostring(c.allQuests)
              .. tostring(c.patrols)
    if s ~= sig then
        sig = s
        layer:ClearAllPoints()
        layer:SetPoint("TOPLEFT", canvas, "TOPLEFT")
        layer:SetSize(1002, 668)
        layer:SetFrameLevel(canvas:GetFrameLevel() + 6)  -- (over the found notes' rings and the ink)
        local bosses = BossSpots(inst, floor)
        local floorKey = inst .. ":" .. floor
        local mine = ns.db.objectSpots[floorKey] or {}
        local hidden = ns.db.objectHidden[floorKey] or {}
        list = Shown(c, list, patrols)
        DrawWays(patrols, scale, c.patrols ~= false and (mode == "icons" or writing))
        for i, o in ipairs(list) do
            local p = Pin(i)
            local minor = Minor(o)
            local size = SIZE * scale * (minor and MINOR or 1)
            p:SetSize(size, size)
            p:SetFrameLevel(layer:GetFrameLevel() + (minor and 1 or 2))
            p:ClearAllPoints()
            p.floorKey, p.key = floorKey, string.format("%s@%.3f,%.3f", o[4], o[2], o[3])
            local moved = mine[p.key]
            local x, y
            if moved then x, y = moved[1] * 1002, moved[2] * 668 else x, y = Clear(o[2] * 1002, o[3] * 668, bosses) end
            p:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
            local cell = CELL[o[7] or o[1]] or 0
            p.tex:SetTexCoord(cell / CELLS, (cell + 1) / CELLS, 0, 1)
            p.hidden = hidden[p.key] and true or nil
            p.tex:SetShown(mode == "icons" or writing)
            p.tex:SetAlpha((minor and MINOR_ALPHA or 1) * ((mode ~= "icons") and 0.5 or 1) * (p.hidden and 0.35 or 1))
            p.count:SetText(o[6] and o[6] > 1 and o[6] or "")
            p.count:SetShown(mode == "icons" or writing)
            p.name, p.note, p.n = o[4], o[5], o[6]
            p:SetShown(writing or not p.hidden)  -- (one you hid: only with the quill, to bring it back)
        end
        for i = #list + 1, #pins do pins[i]:Hide() end
    end
    layer:Show()
end

-- a boss's quest lines (Data\DungeonObjects.lua's DungeonBossQuests) into the open tooltip (Dungeon.lua's markers and list)
function ns.DungeonBossQuestLines(inst, name)
    local t = ns.DungeonBossQuests and ns.DungeonBossQuests[inst]
    local lines = t and name and t[name]
    if not lines then return end
    for line in lines:gmatch("[^\n]+") do GameTooltip:AddLine(line, 1, 0.82, 0.3, true) end
end

-- for /bfi check (Check.lua): what the layer shows now
function ns.DungeonObjectsShown()
    if not (layer and layer:IsShown()) then return 0 end
    local n = 0
    for _, p in ipairs(pins) do if p:IsShown() then n = n + 1 end end
    return n
end

C_Timer.NewTicker(0.3, ns.Timed("DungeonObjects tick", function()
    if ns.db and ns.db.dungeon and ns.DungeonInkSurface then Update() end
end))

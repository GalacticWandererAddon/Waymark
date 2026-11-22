local _, ns = ...

-- Frames (out of the Lab for 1.3 on 2026-11-14, cleared by the user; ns.db.frames; mock-up mockups\style-study.html). A frame set
-- (FrameSets.lua) for the Battlefield Map's border and header, the tracker and the game's tooltip, and a tint for
-- the settings window. "keep" in any part leaves that part exactly as Waymark has it, so nothing here changes
-- anything until chosen. The header's styles join its own table, the border answers through ns.MapBorderStyle,
-- the rest are looks laid on frames by name.
-- Since 2026-11-15 (the user: "Themes is not done AT ALL, but some of the frames/borders are") the finished part
-- is rows on the Header & borders page: a set is one more style of the map's border and of the header
-- (ns.FrameStyle), and the tooltip, the tracker and the settings window have a row each (ns.FramesRows). The
-- themes, the Night Watch, the fold marks and the quest log's papers are on a page of the Lab (ns.FramesLabPage).
--   border  keep, a frame set, and in the Lab deckle, singed, neat, slate, moon     fold  creases over the map (Lab)
--   header  keep, a frame set
--   tracker keep, a frame set, and in the Lab slip, ledger, slim     tip  keep, a frame set (the game's tooltip)
--   log  keep, and in the Lab leaf, book, moon     panel  keep, folio, and in the Lab slate, moon
--   watch   (Lab) turns to the Night Watch theme after dark, by the map's hour

local DEFAULT = { theme = "none", border = "keep", fold = false, header = "keep", tracker = "keep", tip = "keep", log = "keep", panel = "keep", watch = false }
local PARTS = { "border", "fold", "header", "tracker", "tip", "log", "panel" }
local THEMES = {
    { key = "bronze",   name = "Forever bronze",     border = "bronze",   fold = false, header = "bronze",   tracker = "bronze",   tip = "bronze",   log = "keep", panel = "keep",  minimap = "msurvey" },
    { key = "book",     name = "Book cover",         border = "leather",  fold = false, header = "leather",  tracker = "leather",  tip = "leather",  log = "keep", panel = "keep",  minimap = "mleather" },
    { key = "engraver", name = "Engraver's corners", border = "engraver", fold = false, header = "engraver", tracker = "engraver", tip = "engraver", log = "keep", panel = "keep",  minimap = "mengraver" },
    { key = "moonlit",  name = "Moonlit silver",     border = "silver",   fold = false, header = "silver",   tracker = "silver",   tip = "silver",   log = "keep", panel = "keep",  minimap = "msilver" },
    { key = "sun",      name = "Sun gold",           border = "gold",     fold = false, header = "gold",     tracker = "gold",     tip = "gold",     log = "keep", panel = "keep",  minimap = "mgold" },
    { key = "night",    name = "Night Watch",        border = "silver",   fold = false, header = "silver",   tracker = "silver",   tip = "silver",   log = "moon", panel = "moon",  minimap = "msilver" },
    { key = "slate",    name = "Slate",              border = "slate",    fold = false, header = "keep",     tracker = "slim",     tip = "keep",     log = "keep", panel = "slate", minimap = "slate" },
}
local BORDERS = {
    deckle = { art = "FrameDeckle", out = 24, edge = 44 },
    singed = { art = "FrameSinged", out = 24, edge = 44 },
    neat   = { art = "FrameNeat",   out = 16, edge = 28 },
    slate  = { line = { 1, 1, 1, 0.16 }, out = 1 },
    moon   = { line = { 0.68, 0.72, 0.82, 0.9 }, out = 2 },
}
for _, key in ipairs(ns.LabSetKeys()) do BORDERS[key] = { set = key, out = ns.LabSet(key).out } end
local PANEL_TINT = { folio = { 0.82, 0.66, 0.46 }, slate = { 0.52, 0.52, 0.52 }, moon = { 0.56, 0.64, 0.92 } }
local LOG_PAPER = { leaf = { 1, 1, 1 }, book = { 0.92, 0.84, 0.68 }, moon = { 0.72, 0.78, 0.92 } }

-- Its settings are the addon's own (ns.db.frames; DEFAULTS in BattlefieldInfo.lua, the same as DEFAULT here, which
-- only stands in before the settings are read), carried over once from the Lab's store where a dev copy had them.
local standIn
local function Cfg()
    local c = ns.db and ns.db.frames
    if not c then
        if not standIn then
            standIn = {}
            for k, v in pairs(DEFAULT) do standIn[k] = v end
        end
        return standIn
    end
    local old = WaymarkDB and WaymarkDB.lab and WaymarkDB.lab.frames
    if old and not old.moved then
        for k, v in pairs(old) do c[k] = v end
        old.moved = true
    end
    return c
end
-- (the paper frames' and panels' own pictures: none of those looks is cleared, so the art stays in the Lab)
local function Art(name) return ns.MEDIA .. "Lab\\" .. name end

-- What a release offers (the user, 2026-11-14: the frame they use, the moonlight and the sun ones; the rest "I'll
-- check off when I get home"): the three cleared sets on the border, header, tracker and tooltips, their three
-- themes, and the settings window's folio tint, which the user wears. Everything else only where the Lab is; a
-- saved choice that is not open (a setup made on a dev copy) reads as "keep".
local OPEN_PANEL = { folio = true }
local LAB_TRACKER = { slip = true, ledger = true, slim = true }
local HEADERS            -- (filled below)
local function Open(key, v)
    if v == "keep" or v == false or v == nil then return true end
    local lab = ns.LabPage ~= nil
    -- (a set that was removed, the first engraver's, or a paper header: a saved choice of one reads as "keep")
    if key == "border" then return BORDERS[v] ~= nil and (lab or ns.FrameSetOpen(v)) end
    if key == "header" then return HEADERS[v] ~= nil and ns.FrameSetOpen(v) end
    if key == "tracker" then return ns.FrameSetOpen(v) or (lab and LAB_TRACKER[v] or false) end
    if key == "tip" then return ns.FrameSetOpen(v) end
    if key == "panel" then return OPEN_PANEL[v] or (lab and PANEL_TINT[v] ~= nil) end
    if key == "log" then return lab and LOG_PAPER[v] ~= nil end
    return lab     -- (fold)
end

-- after dark, with the watch on, Night Watch's parts instead of the chosen ones
local dusk = false
local function Part(key)
    -- (the fold marks wait with the map's wear, till after 1.3: the user, 2026-11-14. Only where the Lab is)
    if key == "fold" and not ns.LabPage then return false end
    local c = Cfg()
    if not Open(key, c[key]) then return "keep" end
    if dusk and c.watch and ns.LabPage then
        for _, t in ipairs(THEMES) do
            if t.key == "night" then return t[key] end
        end
    end
    return c[key]
end

-- The map's border ------------------------------------------------------------------------------

local edge, slice, lineTex, foldTex, setFrame
local UpdateBorder

local function Lines()
    if lineTex then return lineTex end
    lineTex = {}
    for i = 1, 4 do lineTex[i] = edge:CreateTexture(nil, "ARTWORK") end
    lineTex[1]:SetPoint("TOPLEFT")
    lineTex[1]:SetPoint("TOPRIGHT")
    lineTex[2]:SetPoint("BOTTOMLEFT")
    lineTex[2]:SetPoint("BOTTOMRIGHT")
    lineTex[3]:SetPoint("TOPLEFT")
    lineTex[3]:SetPoint("BOTTOMLEFT")
    lineTex[4]:SetPoint("TOPRIGHT")
    lineTex[4]:SetPoint("BOTTOMRIGHT")
    return lineTex
end

function UpdateBorder()
    local map = BattlefieldMapFrame
    if not map then return end
    local def = BORDERS[Part("border")]
    if not edge then
        edge = CreateFrame("Frame", nil, map)
        edge:EnableMouse(false)
        if ns.debugFrames then ns.debugFrames.labBorder = edge end   -- (/bfi check: its level against the art's)
        if ns.KeepBorderLevel then ns.KeepBorderLevel(edge) end   -- (Style.lua: held over the map's art)
    end
    edge:SetShown(def ~= nil and map:IsShown())
    if ns.ApplyFrameAlpha then ns.ApplyFrameAlpha() end   -- (the settings' Frame opacity: Style.lua)
    if slice then
        for _, p in ipairs(slice.pieces) do p:Hide() end
    end
    if lineTex then
        for _, t in ipairs(lineTex) do t:Hide() end
    end
    if setFrame then setFrame:Hide() end
    local area = ns.MapFace and ns.MapFace(map) or map
    if def and def.set and not area.bfiLabSized then
        -- (docking and the big map change the map's size: smaller corners docked, full on the big map)
        area.bfiLabSized = true
        area:HookScript("OnSizeChanged", function()
            local d = BORDERS[Part("border")]
            if d and d.set then UpdateBorder() end
        end)
    end
    local scale = def and def.set and ns.LabSetScale(def.set) or 1
    if def then
        local out = def.set and ns.LabSetOut(def.set, scale) or def.out
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", area, "TOPLEFT", -out, out)
        edge:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", out, -out)
        edge:SetFrameLevel(ns.MapBorderLevel and ns.MapBorderLevel(map) or (map.BorderFrame or map):GetFrameLevel() + 1)
        if def.set then
            setFrame = setFrame or ns.LabFrame(edge)
            setFrame:SetAllPoints(edge)
            setFrame:SetLook(def.set, scale)
            setFrame:Show()
        elseif def.art then
            local e = def.edge
            if not slice then
                slice = ns.SliceArt(edge, Art(def.art), 0.25, 0.25, 0.25, 0.25, e, e, e, e, "ARTWORK")
            else
                slice:Layout(0.25, 0.25, 0.25, 0.25, e, e, e, e)
                slice:Set(Art(def.art))
            end
            for _, p in ipairs(slice.pieces) do p:Show() end
        else
            for i, t in ipairs(Lines()) do
                t:SetColorTexture(unpack(def.line))
                if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
                t:Show()
            end
        end
    end
    local fold = Part("fold")
    if fold and not foldTex then
        local host = CreateFrame("Frame", nil, map)
        host:EnableMouse(false)
        host:SetFrameLevel((map.BorderFrame or map):GetFrameLevel())
        foldTex = host:CreateTexture(nil, "OVERLAY")
        foldTex:SetTexture(Art("Folds"))
        foldTex:SetAllPoints(host)
        foldTex.host = host
    end
    if foldTex then
        foldTex.host:ClearAllPoints()
        foldTex.host:SetAllPoints(area)
        foldTex.host:SetShown(fold and true or false)
    end
    if ns.GripFollowBorder then ns.GripFollowBorder() end  -- (the corner grip sits in the frame's corner)
end

-- The header: more rows in its own table ----------------------------------------------------------

-- (the four paper headers, tab, rule, scroll and seal, were removed on 2026-11-15 at the user's word)
HEADERS = {}
for _, key in ipairs(ns.LabSetKeys()) do
    HEADERS[key] = { art = ns.LabSetArt(key, "Tab"), padX = 26, text = ns.LabSet(key).tab }
end
local INK = { 0.18, 0.12, 0.06 }

local function UpdateHeader()
    local list = ns.HEADER_STYLES
    if not list then return end
    local c = ns.db.zoneName
    local lab = Cfg()
    local want = Part("header")
    -- (once: an earlier Lab wrote "auto" over the header's own border; the user's was the bronze
    -- dialog edge, as in the Creator's preset. Lab headers now hide that edge with ownEdge instead.)
    if lab.headerBorderWas ~= nil then
        if c.border == "auto" then c.border = lab.headerBorderWas ~= "auto" and lab.headerBorderWas or "dialog" end
        lab.headerBorderWas = nil
    end
    if want == "keep" then
        if lab.headerWas then
            c.style = lab.headerWas
            lab.headerWas = nil
        elseif c.style:find("^lab") then
            c.style = "plate"     -- (a look that is gone or not open, with nothing remembered: the header's first)
        end
    else
        for key, h in pairs(HEADERS) do
            list["lab" .. key] = list["lab" .. key] or { text = h.text or INK, padX = h.padX, paper = h.art, paperCoords = { 0, 1, 0, 1 }, ownEdge = true }
        end
        if not c.style:find("^lab") then lab.headerWas = c.style end
        c.style = "lab" .. want
    end
    if ns.UpdateZoneName then ns.UpdateZoneName() end
end

-- The tracker, the quest log, the settings window -----------------------------------------------

local function Around(frame, holder, key)
    local o = ns.LabSetOut(key, ns.LAB_PANEL)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", holder, "TOPLEFT", -o, o)
    frame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", o, -o)
    frame:SetLook(key, ns.LAB_PANEL)
    frame:Show()
end

local backing, trackFrame
local function UpdateTracker()
    local f = _G.WaymarkTracker
    if not f then return end
    local look = Part("tracker")
    local set = ns.LabSet(look)
    -- (its own border, while a set's frame is round it)
    for _, child in ipairs({ f:GetChildren() }) do
        if child ~= trackFrame and child.SetBackdropBorderColor then child:SetAlpha(set and 0 or 1) end
    end
    if set then
        trackFrame = trackFrame or ns.LabFrame(f)
        Around(trackFrame, f, look)
    elseif trackFrame then
        trackFrame:Hide()
    end
    if not backing then
        backing = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        backing:SetAllPoints()
    end
    -- (a set's frame is a border and no more: the tracker's ground stays the tracker's own, its Background
    -- setting. The user, 2026-11-15: "dont let quest-tracker border change affect its backdrop")
    backing:SetShown(look == "slip" or look == "ledger" or look == "slim")
    if look == "slip" or look == "ledger" then
        -- (paper in the shade: the tracker's own light text stays readable on it)
        backing:SetTexture(Art("Leaf"))
        local v = look == "slip" and 0.34 or 0.27
        backing:SetVertexColor(v, v * 0.86, v * 0.66, 0.92)
    elseif look == "slim" then
        backing:SetColorTexture(0.04, 0.04, 0.035, 0.7)
    end
end

-- the game's tooltip: a set's frame in place of its border, its dark middle kept
local TIP_EDGES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }
local tipFrame
local function UpdateTip()
    local look = Part("tip")
    local set = ns.LabSet(look)
    if not (set or tipFrame) then return end
    local slices = GameTooltip.NineSlice
    if slices then
        for _, k in ipairs(TIP_EDGES) do
            if slices[k] then slices[k]:SetAlpha(set and 0 or 1) end
        end
    end
    if set then
        tipFrame = tipFrame or ns.LabFrame(GameTooltip)
        -- (on the dark box itself: the tooltip's bounds reach a few pixels past it)
        Around(tipFrame, slices and slices.Center or GameTooltip, look)
    else
        tipFrame:Hide()
    end
end

local logWas
local function UpdateLog()
    local q = _G.WaymarkQuestWindow
    if not (q and q.page) then return false end
    local look = Part("log")
    local tint = LOG_PAPER[look]
    if tint then
        q.page:SetTexture(Art("Leaf"))
        q.page:SetTexCoord(0, 1, 0, 1)
        q.page:SetVertexColor(unpack(tint))
        logWas = true
    elseif logWas then
        logWas = nil
        q.page:SetVertexColor(1, 1, 1)
        ns.SetArt(q.page, "QuestDetailsBackgrounds", "Interface\\QuestFrame\\QuestBG")
    end
    return true
end

-- the settings window: a multiply over it, never its own textures' colours (setting those back
-- turned its dark ground white after a few theme changes)
-- (the gear's quick panel wears the same frame and ground, Options.lua, and the same tint: the user,
-- 2026-11-16, "Make quick settings backing match settings backdrop choice")
local panelTints = {}   -- [window] = its tint texture, or false while it has none
local UpdatePanel
local function TintWindow(p)
    if not p then return end
    if panelTints[p] == nil then
        panelTints[p] = false
        p:HookScript("OnShow", function() UpdatePanel() end)
    end
    local tint = PANEL_TINT[Part("panel")]
    if tint and not panelTints[p] then
        local t = p:CreateTexture(nil, "BORDER", nil, 7)
        t:SetAllPoints(p)
        t:SetBlendMode("MOD")
        panelTints[p] = t
    end
    local t = panelTints[p]
    if t then
        if tint then t:SetColorTexture(tint[1], tint[2], tint[3], 1) end
        t:SetShown(tint ~= nil)
    end
end
UpdatePanel = function()
    TintWindow(_G.WaymarkOptions)
    TintWindow(ns.quickPanelFrame)
    for _, f in ipairs(ns.tintWindows or {}) do TintWindow(f) end   -- (ns.MetalWindow: the welcome page)
end

local function UpdateAll()
    UpdateHeader()
    if ns.UpdateStyle then ns.UpdateStyle() end   -- (the border, through the hook below)
    UpdateTracker()
    UpdateTip()
    UpdateLog()
    UpdatePanel()
end

local HEADER_NUDGE = { engraver = -4, silver = -4, gold = -4 }
local function Theme(key)
    local c = Cfg()
    c.theme = key
    for _, t in ipairs(THEMES) do
        if t.key == key then
            for _, p in ipairs(PARTS) do c[p] = t[p] end
            -- (a frame set's header sits 4 px lower than the nudge's zero: the user's numbers for the
            -- Engraver's corners, Moonlit silver and Sun gold, 2026-11-16. PlaceLooks.lua)
            if HEADER_NUDGE[t.header] and Open("header", t.header) and ns.HeaderLookNudge then
                ns.HeaderLookNudge(HEADER_NUDGE[t.header])
                if ns.OnSettingChanged then pcall(ns.OnSettingChanged, "zoneName") end
            end
            if ns.MinimapLookStyle then
                if t.minimap then ns.MinimapLookStyle(t.minimap) elseif ns.MinimapLookOn then ns.MinimapLookOn(false) end
            end
        end
    end
    UpdateAll()
    if ns.RefreshControls then ns.RefreshControls() end
end

-- back to how Waymark comes: every part, the Night Watch and the minimap's look
local function Clear()
    local c = Cfg()
    for _, p in ipairs(PARTS) do c[p] = DEFAULT[p] end
    c.theme, c.watch = "none", false
    dusk = false
    if ns.MinimapLookOn then ns.MinimapLookOn(false) end
    UpdateAll()
    if ns.RefreshControls then ns.RefreshControls() end
end
ns.PageResets = ns.PageResets or {}
-- (ns.PageResets.labframes, at the end: the Lab page's Reset this page)
ns.FramesRefresh = UpdateAll         -- (a loaded setup or preset: ns.OnSettingChanged)

-- what the theme row shows: parts changed by hand are a mix, not "none"
local function ThemeNow()
    local c = Cfg()
    if c.theme ~= "none" and c.theme ~= "gold" then return c.theme end
    for _, p in ipairs(PARTS) do
        if c[p] ~= DEFAULT[p] then return "mix" end
    end
    return "none"
end

local function Watch()
    if not Cfg().watch then
        if dusk then
            dusk = false
            UpdateAll()
        end
        return
    end
    local h = ns.MapHourNow and ns.MapHourNow() or 12
    local now = h >= 20 or h < 6
    if now ~= dusk then
        dusk = now
        UpdateAll()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    -- our border instead of the map's own, only when one is chosen
    local style = ns.MapBorderStyle
    ns.MapBorderStyle = function(own)
        if BORDERS[Part("border")] then return "none" end
        return style(own)
    end
    hooksecurefunc(ns, "UpdateStyle", UpdateBorder)
    C_Timer.After(2, UpdateAll)
    C_Timer.NewTicker(60, Watch)
    -- (the quest log is made the first time it's opened)
    local waiting = CreateFrame("Frame")
    local since = 0
    waiting:SetScript("OnUpdate", function(self, elapsed)
        since = since + elapsed
        if since < 1 then return end
        since = 0
        if Part("log") == "keep" then return end
        if UpdateLog() then self:SetScript("OnUpdate", nil) end
    end)
end)

-- The settings (Options.lua asks for each; made only where this file is) ----------------------------------

-- a part's looks as rows: the cleared sets, then, where the Lab is, the looks nobody has cleared
local LAB_ROWS = {
    border = { { "deckle", "Deckled paper" }, { "singed", "Singed" }, { "neat", "Neatline with ticks" }, { "slate", "Slate" }, { "moon", "Moonlit line" } },
    tracker = { { "slip", "Paper slip" }, { "ledger", "Ledger" }, { "slim", "Slim" } },
    panel = { { "slate", "Slate" }, { "moon", "Moonlit" } },
}
local function Rows(part, rows)
    if part == "panel" then rows[#rows + 1] = { "folio", "Folio" } else ns.LabSetChoices(rows) end
    if ns.LabPage then
        for _, r in ipairs(LAB_ROWS[part] or {}) do rows[#rows + 1] = r end
    end
    return rows
end

local function Changed()
    Cfg().theme = "none"
    UpdateAll()
    if ns.RefreshControls then ns.RefreshControls() end   -- (the same choice shows on Start here; the Lab's theme row)
end

-- A frame set as one more style of the map's border or of the header: the page's own rows, then ours; get and
-- set are the setting's own (border.style, zoneName.style). Ours are named "f:<set>": "gold" is a border
-- style of the map's already.
function ns.FrameStyle(part, list, get, set)
    local rows = {}
    for i, r in ipairs(list) do rows[i] = r end
    for _, r in ipairs(Rows(part, {})) do rows[#rows + 1] = { "f:" .. r[1], r[2] } end
    return rows, function()
        local v = Cfg()[part]
        if v ~= "keep" and Open(part, v) then return "f:" .. v end
        local own = get()
        -- (the header wears ours as a style of its own table: the one it had is remembered)
        if part == "header" and type(own) == "string" and own:find("^lab") then return Cfg().headerWas or "plate" end
        return own
    end, function(v)
        local c = Cfg()
        local mine = v:match("^f:(.+)$")
        if mine then
            c[part] = mine
        else
            c[part] = "keep"
            if part == "header" then c.headerWas = nil end
            set(v)
        end
        Changed()
    end
end

-- The rows for what is not the map's own frame. They stood at the foot of Header & border, where nobody
-- looks for a tooltip's border (the user, 2026-11-16: "Hidden or ok?"). Now each where it belongs:
-- which = "tips": the tooltip's border and the settings window's backdrop, on the tab Tooltips & menus;
-- which = "tracker": the tracker's frame, one row in the Tracker tab's own Border section.
function ns.FramesRows(a, which)
    local function Choose(label, key, first, tip)
        a:Choice(label, nil, nil, Rows(key, { first }), function()
            local v = Cfg()[key]
            return Open(key, v) and v or "keep"
        end, function(v)
            Cfg()[key] = v
            Changed()
        end)
        if tip then a:Tip(tip) end
    end
    if which == "tracker" then
        Choose("A frame round it", "tracker", { "keep", "None: the border below" }, "A frame round the tracker in place of its own border. Its background stays as you set it.")
        return
    end
    a:Header("Tooltip border")
    Choose("Style", "tip", { "keep", "The game's own" }, "A frame on the game's tooltip, all of them. Its dark middle stays.")
    a:Header("Settings window")
    Choose("Backdrop", "panel", { "keep", "As it is" }, "A warm tint on this window and on the gear's quick panel.")
end

-- the header page's "Reset this page": our parts of it too (the Lab's parts, by the Lab page's own reset)
local function ResetParts(parts)
    return function()
        local c = Cfg()
        for _, p in ipairs(parts) do c[p] = DEFAULT[p] end
        c.theme = "none"
        UpdateAll()
        if ns.RefreshControls then ns.RefreshControls() end
    end
end
ns.PageResets.header = ResetParts({ "border", "header" })
ns.PageResets.tipsmenus = ResetParts({ "tip", "panel" })
ns.PageResets.tracker = ResetParts({ "tracker" })

-- The Lab's page: what is not done. The themes (the user, 2026-11-15: "not done AT ALL"), the Night Watch, the
-- fold marks, the quest log's papers. Only where the Lab is; Lab\Lab.lua's reset for the page is Clear.
function ns.FramesLabPage(a)
    local themes = { { "none", "None: as Waymark comes" }, { "mix", "My own mix" } }
    for _, t in ipairs(THEMES) do themes[#themes + 1] = { t.key, t.name } end
    a:Header("Themes")
    a:Choice("Theme", nil, nil, themes, ThemeNow, function(v)
        if v == "none" then Clear() elseif v ~= "mix" then Theme(v) end
        -- ("My own mix" is what the row reads once a part differs: choosing it changes nothing, and the row
        -- goes back to what is true)
        if ns.RefreshControls then ns.RefreshControls() end
    end)
    a:Tip("Not done. One choice dresses the map, its header, the tracker, the tooltip, the log, the settings window and the Lab's minimap look. A part changed on Header & borders makes it My own mix. None takes everything back.")
    a:CheckWith("Night Watch after dark", function() return Cfg().watch end, function(v)
        Cfg().watch = v and true or false
        Watch()
    end)
    a:Tip("The frames turn to Moonlit silver at 20:00 and back at 06:00, by the map's hour. The minimap keeps its look.")
    a:Header("Unfinished looks")
    a:CheckWith("Fold marks on the map", function() return Cfg().fold end, function(v)
        Cfg().fold = v and true or false
        Changed()
    end)
    a:Tip("On hold with the map's wear, till after 1.3.")
    a:Choice("Quest log paper", nil, nil, { { "keep", "As it is" }, { "leaf", "Loose leaf" }, { "book", "Book page" }, { "moon", "Moonlit" } }, function()
        return Cfg().log
    end, function(v)
        Cfg().log = v
        Changed()
    end)
    a:Tip("Does not work yet.")
    a:Note("The other unfinished borders (bronze, book cover, the paper edges, the thin lines), the tracker's papers and the settings window's other tints are in their rows on Header & borders, only on a copy that has the Lab.")
end
ns.PageResets.labframes = Clear

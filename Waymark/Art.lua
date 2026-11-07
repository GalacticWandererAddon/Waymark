local _, ns = ...

-- Forever's UI art, the same on every client we test on.
--
-- ns.SetArt(tex, name[, fallback]): name is an atlas name, a file path or a file ID.
-- On Forever the game has them all. On the stand-ins (Classic Era, Anniversary) many
-- are missing or look different, so the dev-only addon Waymark_DevArt carries
-- copies of Forever's files plus its atlas coordinates (made by tools\dev_art.py,
-- installed on the stand-in clients only, never shipped). It wins over the stand-in's
-- own art, so testing there shows what Forever will show.
--
-- Where each name's art comes from (/bfi check lists it):
--   game        the client's own: on Forever always; elsewhere when the client has it
--   dev copy    Waymark_DevArt: Blizzard's files copied out. Testing only, never ship
--   substitute  ART_SUBSTITUTE below: client art Era has, or our own. Safe to ship;
--               used when there's no dev art (an Era-only player) or it's off (/bfi devart)
--
-- tools\dev_art.py picks up every name written literally as ns.SetArt(x, "name"...).
-- Names chosen at run time go in ART below so it finds those too.
ns.ART = {
    -- the toggle buttons and the settings headings (Options.lua TOGGLES, ns.ToggleIcon)
    "cursor_quest_128", "cursor_questturnin_128", "cursor_attack_128", "cursor_questinteract_128", "cursor_inspect_128",
    "cursor_gatherherbs_128", "cursor_palette_128", "cursor_directions_128",
    "poi-workorders",
    "bonus-objective-star", "vignettekill", "vignettekillelite", "minimap-questarrow", "dungeon",
    "Interface\\WorldMap\\UI-World-Icon",
    "Interface\\Minimap\\UI-Minimap-ZoomInButton-Up",
    "Interface\\Minimap\\Tracking\\Innkeeper",
    "poi-town", "poi-alliance", "poi-horde", "Interface\\Icons\\INV_Misc_Map_01",
    "Interface\\Icons\\INV_Misc_Note_01",  -- (a preset card of your own, Options.lua)
    -- the settings window, in the game's own Options look (Options.lua)
    "ui-frame-metal-cornertopleft-2x", "ui-frame-metal-cornertopright-2x",
    "ui-frame-metal-cornerbottomleft-2x", "ui-frame-metal-cornerbottomright-2x",
    "_ui-frame-metal-edgetop-2x", "_ui-frame-metal-edgebottom-2x",
    "!ui-frame-metal-edgeleft-2x", "!ui-frame-metal-edgeright-2x",
    "redbutton-exit-c60-2x", "redbutton-exit-pressed-c60-2x", "redbutton-highlight-c60-2x",
    -- the map's shrink / grow button (MapControls SetupBigButton)
    "redbutton-condense-2x", "redbutton-condense-pressed-2x", "redbutton-highlight-2x",
    "redbutton-expand-2x", "redbutton-expand-pressed-2x",
    -- and the map's close X beside it, in the same art
    "redbutton-exit-2x", "redbutton-exit-pressed-2x", "redbutton-exit-disabled-2x",
    "options_innerframe", "options_categoryheader_1", "options_list_active", "options_list_hover",
    "Interface\\Buttons\\UI-PlusMinus-Buttons", "options_horizontaldivider",
    "common-search-border-left", "common-search-border-middle", "common-search-border-right",
    "checkbox-minimal", "checkmark-minimal", "checkmark-minimal-disabled",
    "minimal_sliderbar_left", "_minimal_sliderbar_middle", "minimal_sliderbar_right",
    "minimal_sliderbar_button", "minimal_sliderbar_button_left", "minimal_sliderbar_button_right",
    "common-dropdown-b-button", "common-dropdown-b-button-hover", "common-dropdown-b-button-open",
    "common-dropdown-bg", "common-dropdown-icon-checkmark-yellow",
    "128-redbutton-up", "128-redbutton-pressed", "128-redbutton-disable", "128-redbutton-highlight",
    "minimal-scrollbar-thumb-top", "minimal-scrollbar-thumb-bottom", "minimal-scrollbar-thumb-middle",
    "minimal-scrollbar-track-top", "minimal-scrollbar-track-bottom", "!minimal-scrollbar-track-middle",
    "minimal-scrollbar-arrow-top", "minimal-scrollbar-arrow-top-down", "minimal-scrollbar-arrow-top-over",
    "minimal-scrollbar-arrow-bottom", "minimal-scrollbar-arrow-bottom-down", "minimal-scrollbar-arrow-bottom-over",
    -- the quest window's scroll thumb (Tracker.lua Piece)
    "minimal-scrollbar-small-thumb-top", "minimal-scrollbar-small-thumb-bottom", "minimal-scrollbar-small-thumb-middle",
}

-- Substitutes: what a client without Forever's art draws instead. That's the Classic
-- Era release, or testing with the dev art off (/bfi devart). Only art the client
-- has itself (its atlas names and file paths) or our own Media\ files: nothing
-- copied from Blizzard, so it's fine to ship. Names Era has itself need no entry.
-- [Forever name] = the client's name or path; { name or path, left, right, top,
-- bottom } for part of it (top > bottom: upside down); false: nothing drawn. Checked against Era 1.15.9.70003's atlas tables (wago.tools).
local RED_BUTTONS = ns.MEDIA .. "RedButtons"
local PALETTE = ns.MEDIA .. "Palette"
ns.ART_SUBSTITUTE = {
    -- the dock button (Options.lua VIEW_ICONS): Era hasn't Forever's map icon; its sibling
    ["Interface\\Icons\\INV_Misc_Map_01"] = "Interface\\Icons\\INV_Misc_Map02",
    -- your own preset's card (Options.lua): Era's own Note_01 draws nothing, as Map_01; its old note
    ["Interface\\Icons\\INV_Misc_Note_01"] = "Interface\\Icons\\INV_Misc_Note_06",
    -- the settings window frame: Era's own classic window (ButtonFrameTemplateNoPortrait),
    -- laid out at that art's sizes in Options.lua MetalFrame
    ["ui-frame-metal-cornertopleft-2x"] = "UI-Frame-TopLeftCornerNoPortrait",
    ["ui-frame-metal-cornertopright-2x"] = "UI-Frame-TopCornerRight",
    ["ui-frame-metal-cornerbottomleft-2x"] = "UI-Frame-BotCornerLeft",
    ["ui-frame-metal-cornerbottomright-2x"] = "UI-Frame-BotCornerRight",
    ["_ui-frame-metal-edgetop-2x"] = "_UI-Frame-TitleTile",
    ["_ui-frame-metal-edgebottom-2x"] = "_UI-Frame-Bot",
    ["!ui-frame-metal-edgeleft-2x"] = "!UI-Frame-LeftTile",
    ["!ui-frame-metal-edgeright-2x"] = "!UI-Frame-RightTile",
    -- the map's close X and shrink / grow arrows, and the settings window's X: our
    -- own (Media\RedButtons, tools\red_buttons.py). Era has this art only at 18 px,
    -- blurred at the map's size; the classic round X was pixelated too.
    ["redbutton-exit-2x"] = { RED_BUTTONS, 0, 0.25, 0, 0.25 },
    ["redbutton-condense-2x"] = { RED_BUTTONS, 0.25, 0.5, 0, 0.25 },
    ["redbutton-expand-2x"] = { RED_BUTTONS, 0.5, 0.75, 0, 0.25 },
    ["redbutton-highlight-2x"] = { RED_BUTTONS, 0.75, 1, 0, 0.25 },
    ["redbutton-exit-pressed-2x"] = { RED_BUTTONS, 0, 0.25, 0.25, 0.5 },
    ["redbutton-condense-pressed-2x"] = { RED_BUTTONS, 0.25, 0.5, 0.25, 0.5 },
    ["redbutton-expand-pressed-2x"] = { RED_BUTTONS, 0.5, 0.75, 0.25, 0.5 },
    ["redbutton-exit-disabled-2x"] = { RED_BUTTONS, 0, 0.25, 0.5, 0.75 },
    ["redbutton-exit-c60-2x"] = { RED_BUTTONS, 0, 0.25, 0, 0.25 },
    ["redbutton-exit-pressed-c60-2x"] = { RED_BUTTONS, 0, 0.25, 0.25, 0.5 },
    ["redbutton-highlight-c60-2x"] = { RED_BUTTONS, 0.75, 1, 0, 0.25 },
    -- the settings' red buttons (Options.lua RedButton): the classic panel button
    -- (its art is the top left 80 x 22 px of the file). Era has a highlight of its
    -- own, but that's a different shape, so it's swapped too.
    ["128-redbutton-up"] = { "Interface\\Buttons\\UI-Panel-Button-Up", 0, 0.625, 0, 0.6875 },
    ["128-redbutton-pressed"] = { "Interface\\Buttons\\UI-Panel-Button-Down", 0, 0.625, 0, 0.6875 },
    ["128-redbutton-disable"] = { "Interface\\Buttons\\UI-Panel-Button-Disabled", 0, 0.625, 0, 0.6875 },
    ["128-redbutton-highlight"] = { "Interface\\Buttons\\UI-Panel-Button-Highlight", 0, 0.625, 0, 0.6875 },
    -- the toggle icons: the client's own (smaller) cursors
    ["cursor_quest_128"] = "Interface\\Cursor\\Quest",
    ["cursor_questturnin_128"] = "Interface\\Cursor\\QuestTurnIn",
    ["cursor_attack_128"] = "Interface\\Cursor\\Attack",
    ["cursor_questinteract_128"] = "Interface\\Cursor\\Interact",
    ["cursor_inspect_128"] = "Interface\\Cursor\\Inspect",
    ["cursor_gatherherbs_128"] = "Interface\\Cursor\\GatherHerbs",
    -- the Rares & chests and RareScanner toggles: Era spells these atlases with capitals
    -- (VignetteKill); its own names, in case its lookup minds the case
    ["vignettekill"] = "VignetteKill",
    ["vignettekillelite"] = "VignetteKillElite",
    ["cursor_directions_128"] = "Interface\\Cursor\\Directions",
    -- the ink toggle: Era has no palette cursor; our own (tools\palette_icon.py)
    ["cursor_palette_128"] = PALETTE,
    ["bonus-objective-star"] = "tradeskills-star",
    -- the quest window (Tracker.lua). Era lists the QuestLog-* atlases but hasn't
    -- their file (questlogframe.blp: green). Its frame: Era's dark metal frame, a
    -- single picture in the top left 72 px (sliced at its own sizes in Tracker.lua);
    -- the rest from Era's older quest details art (QuestMapLogAtlas): the top bar
    -- upside down (its straight edge up), the rewards panel cut in three
    ["QuestLog-frame"] = { "Interface\\DialogFrame\\UIFrameDiamondMetalClassicBorder", 0, 72 / 128, 0, 72 / 128 },
    ["QuestLog-frame-filigree"] = false,
    ["QuestLog-reward-top-frame"] = { "QuestDetails-TopOverlay", 0, 1, 1, 0 },
    ["QuestLog-reward-header-top"] = { "QuestDetails-RewardsOverlay", 0, 1, 0, 56 / 275 },
    ["QuestLog-reward-tile-vertical"] = { "QuestDetails-RewardsOverlay", 0, 1, 60 / 275, 180 / 275 },
    ["QuestLog-reward-bottom"] = { "QuestDetails-RewardsOverlay", 0, 1, 188 / 275, 1 },
}

ns.artMissing = {}  -- name -> true: asked for but nowhere to be found (/bfi check)
ns.artFrom = {}     -- name -> "dev copy", "substitute" or "game" (/bfi check)

local function IsFile(name)
    return type(name) == "number" or name:find("[\\/]") ~= nil
end

-- the dev-only copies of Forever's art, when they're installed and not switched off
local function DevArt()
    if ns.FOREVER or (WaymarkDB and WaymarkDB.devArtOff) then return nil end
    return WaymarkDevArt
end

-- Draws without Forever's art (substitutes): the Classic Era release, or dev art off
function ns.UsingSubstitutes()
    return not ns.FOREVER and not DevArt()
end

-- The atlas behind a name, and its info. (Live Forever only knows the plain names,
-- as its own UI uses them, and picks the -2x or -c60 size itself. The beta took both.)
local function FindAtlas(name)
    local get = C_Texture and C_Texture.GetAtlasInfo
    if not get then return name end
    local info = get(name)
    if info or not ns.FOREVER then return name, info end
    local plain = name:gsub("%-2x$", "")
    plain = plain:gsub("%-c60$", "")
    if plain == name then return name end
    return plain, get(plain)
end

-- The metal frame's bottom corners, in step with its top ones drawn 75 wide. (Live
-- picks the c60 art for a plain name, where they're as big as the top; in the -2x
-- art they're 64 to the top's 150, so 32.)
function ns.MetalCornerSize(name)
    local _, top = FindAtlas("ui-frame-metal-cornertopleft-2x")
    local _, me = FindAtlas(name)
    if not (top and me and top.width and top.width > 0) then return 32, 32 end
    local k = 75 / top.width
    return me.width * k, me.height * k
end

-- for /waymark check: every name on the list, also those in windows not opened yet
function ns.CheckAllArt()
    for _, name in ipairs(ns.ART) do
        if type(name) == "string" and not IsFile(name) then
            local _, info = FindAtlas(name)
            if not info then ns.artMissing[name] = "unknown" end
        end
    end
end

function ns.SetArt(tex, name, fallback)
    local dev = DevArt()
    local a = dev and dev.atlas[name]
    if a then
        tex:SetTexture(a[1])
        tex:SetTexCoord(a[2], a[3], a[4], a[5])
        ns.artFrom[name] = "dev copy"
        return true
    end
    local f = dev and dev.files[name]
    if f then
        tex:SetTexture(f)
        tex:SetTexCoord(0, 1, 0, 1)
        ns.artFrom[name] = "dev copy"
        return true
    end
    -- (not `x and y`: false here means "draw nothing", and blanked all art on Forever)
    local s
    if ns.UsingSubstitutes() then s = ns.ART_SUBSTITUTE[name] end
    if s == false then
        tex:SetTexture(nil)
        ns.artFrom[name] = "substitute"
        return true
    elseif type(s) == "table" and ns.SetArtPart(tex, s[1], s[2], s[3], s[4], s[5]) then
        ns.artFrom[name] = "substitute"
        return true
    elseif type(s) == "string" and ns.SetArt(tex, s) then
        ns.artFrom[name] = "substitute"
        return true
    end
    ns.artFrom[name] = "game"
    if IsFile(name) then
        tex:SetTexture(name)
        tex:SetTexCoord(0, 1, 0, 1)
        return true
    end
    local atlas, info = FindAtlas(name)
    -- (off Forever, its file and coordinates set ourselves: Era's SetAtlas seems to
    -- keep a piece's old SetTexCoord when the file is the same, so ns.SetArtPart cut
    -- a part of a part: the dropdowns lost their ends on hover. Tiled art keeps
    -- SetAtlas, which sets the tiling.)
    local file = info and (info.file or info.filename)
    if file and not ns.FOREVER and not info.tilesHorizontally and not info.tilesVertically then
        tex:SetTexture(file)
        tex:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord)
        return true
    end
    if info and tex:SetAtlas(atlas) ~= false then
        return true
    end
    -- (what the check shows: the game doesn't know it, or knows it and won't draw it)
    ns.artMissing[name] = info and "refused" or "unknown"
    ns.artFrom[name] = nil
    -- (live Forever turned down some atlases its tables list: our own stand-in beats a blank)
    local own = ns.FOREVER and ns.ART_SUBSTITUTE[name]
    if type(own) == "table" and ns.SetArtPart(tex, own[1], own[2], own[3], own[4], own[5]) then
        return true
    end
    if fallback then return ns.SetArt(tex, fallback) end
    return false
end

-- Only part of a piece of art: l, r, t, b are fractions of it (0 to 1, from its
-- left and its top). For drawing a frame of any size out of one picture.
function ns.SetArtPart(tex, name, l, r, t, b)
    if not ns.SetArt(tex, name) then return false end
    -- (Forever: cut from the atlas's own figures. Read back after SetAtlas they gave
    -- the red buttons in broken pieces)
    local _, info = FindAtlas(name)
    local file = ns.FOREVER and info and (info.file or info.filename)
    if file then
        local x, y = info.leftTexCoord, info.topTexCoord
        local aw, ah = info.rightTexCoord - x, info.bottomTexCoord - y
        tex:SetTexture(file)
        tex:SetTexCoord(x + aw * l, x + aw * r, y + ah * t, y + ah * b)
        return true
    end
    local ulx, uly, _, lly, urx = tex:GetTexCoord()
    local w, h = urx - ulx, lly - uly
    tex:SetTexCoord(ulx + w * l, ulx + w * r, uly + h * t, uly + h * b)
    return true
end

-- Art stretched over a frame with its edges kept their size (a nine-slice).
-- l, r, t, b: how much of the art is its left, right, top and bottom edge
-- (fractions); L, R, T, B: how wide those are drawn (pixels). 0: no edge there.
-- Returns the pieces: s:Set(name) swaps the art (hover, pressed), s:Layout(...)
-- cuts it again (new sizes), s:SetShown, s:SetAlpha, s:SetVertexColor.
local Slice = {}
Slice.__index = Slice

-- area: { left, right, top, bottom } fractions: only that part of the art is
-- used (l, r, t, b are then fractions of it)
function ns.SliceArt(frame, name, l, r, t, b, L, R, T, B, layer, sublevel, area)
    local s = setmetatable({ frame = frame, pieces = {}, area = area }, Slice)
    for i = 1, 9 do
        s.pieces[i] = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    end
    s:Layout(l, r, t, b, L, R, T, B)
    s:Set(name)
    return s
end

function Slice:Layout(l, r, t, b, L, R, T, B)
    self.cut = { l, r, t, b }
    -- per column / row: art from, art to, and the frame points it spans
    local cols = {
        { 0, l, "LEFT", 0, "LEFT", L },
        { l, 1 - r, "LEFT", L, "RIGHT", -R },
        { 1 - r, 1, "RIGHT", -R, "RIGHT", 0 },
    }
    local rows = {
        { 0, t, "TOP", 0, "TOP", -T },
        { t, 1 - b, "TOP", -T, "BOTTOM", B },
        { 1 - b, 1, "BOTTOM", B, "BOTTOM", 0 },
    }
    local i = 0
    for _, ry in ipairs(rows) do
        for _, cx in ipairs(cols) do
            i = i + 1
            local tex = self.pieces[i]
            tex.part = nil
            tex:ClearAllPoints()
            if cx[2] > cx[1] and ry[2] > ry[1] then
                tex:SetPoint("TOPLEFT", self.frame, ry[3] .. cx[3], cx[4], ry[4])
                tex:SetPoint("BOTTOMRIGHT", self.frame, ry[5] .. cx[5], cx[6], ry[6])
                tex.part = { cx[1], cx[2], ry[1], ry[2] }
            end
            tex:SetShown(tex.part ~= nil and not self.hidden)
        end
    end
    if self.name then self:Set(self.name) end
end

function Slice:Set(name)
    self.name = name
    local a = self.area or { 0, 1, 0, 1 }
    local function X(f) return a[1] + (a[2] - a[1]) * f end
    local function Y(f) return a[3] + (a[4] - a[3]) * f end
    for _, tex in ipairs(self.pieces) do
        local p = tex.part
        if p then ns.SetArtPart(tex, name, X(p[1]), X(p[2]), Y(p[3]), Y(p[4])) end
    end
end

function Slice:SetShown(on)
    self.hidden = not on
    for _, tex in ipairs(self.pieces) do tex:SetShown(on and tex.part ~= nil) end
end

function Slice:SetAlpha(a)
    for _, tex in ipairs(self.pieces) do tex:SetAlpha(a) end
end

function Slice:SetVertexColor(r, g, b, a)
    for _, tex in ipairs(self.pieces) do tex:SetVertexColor(r, g, b, a or 1) end
end

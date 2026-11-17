local _, ns = ...

-- The settings panel (categories on the left, a page each on the right), the
-- quick-options panel on the map, and a stub in the game's own AddOns settings.

-- Every control on every page and the quick panel, so a change made in one
-- shows up in the others
local controls = {}

-- the pages were built with the advanced (fine-tuning) settings: on with the
-- "Show advanced settings" switch, and while searching (DropPages rebuilds them)
local advancedShown = false

function ns.RefreshControls()
    for _, c in ipairs(controls) do
        if c:IsVisible() then
            c.Refresh()
            -- greyed while the switch it depends on is off (Column's Requires)
            if c.bfiDep then c:SetAlpha(c.bfiDep() and 1 or 0.4) end
        end
    end
end

-- group = settings group (nil for top-level settings)
local function Setting(group, key)
    local function tbl() return group and ns.db[group] or ns.db end
    return function() return tbl()[key] end,
           function(v)
               tbl()[key] = v
               ns.OnSettingChanged(group, key)
           end
end

-- the same for a checkbox; a layer's switch ("shown") as you see it, switched as
-- its toggle button does (a context profile can decide it: setting .shown alone
-- did nothing then)
local function LayerSetting(group, key)
    if not (group and key == "shown") then return Setting(group, key) end
    return function() return ns.IsShown(group) end,
           function(v)
               if ns.IsShown(group) ~= (v and true or false) then ns.ToggleLayer(group, "shown") end
           end
end

-- Widgets ---------------------------------------------------------------

-- The settings pages look like the game's own Options window (Forever's art):
-- labels in gold, section headings in white, notes in a soft grey, all with
-- the game's black shadow. The same helpers on the quick panel keep their own
-- colours. (A page frame has bfiSettingsPage set before its controls are built.)
local INK, INK_SOFT, INK_HEAD = { 1, 0.82, 0 }, { 0.80, 0.78, 0.72 }, { 1, 1, 1 }

-- Your text sizes for the settings pages (the "Settings window" page), real
-- font sizes: headings, and labels (the small notes and values a size less).
-- (Kept as offsets by an earlier version: small numbers are read as those.)
local NORMAL_SIZE = 12
local HEADING_SIZE = 15  -- (the game's Options headings are larger than its labels)
local function OptionSize(key)
    local normal = key == "heading" and HEADING_SIZE or NORMAL_SIZE
    local v = ns.db and ns.db.optionsText and ns.db.optionsText[key] or normal
    if v < 6 then v = NORMAL_SIZE + v end
    return v
end
local function HeadExtra() return OptionSize("heading") - NORMAL_SIZE end
local function TextExtra() return OptionSize("text") - NORMAL_SIZE end

-- heading: a section title (its own size setting)
local function Ink(parent, fs, color, heading)
    if parent and parent.bfiSettingsPage then
        local c = color or INK
        fs:SetTextColor(c[1], c[2], c[3])
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        local font, size, flags = fs:GetFont()
        if font and size then
            local want
            if heading then
                want = OptionSize("heading")
            else
                want = OptionSize("text") - (size < 12 and 1 or 0)
            end
            if math.abs(want - size) > 0.1 then fs:SetFont(font, want, flags or "") end
        end
    end
end

-- A button's look from Forever's art: state = "Normal", "Pushed", "Highlight",
-- "Disabled", "Checked" or "DisabledChecked"; the button's own texture for that
-- state, then the art on it
local function StateArt(b, state, name, fallback)
    b["Set" .. state .. "Texture"](b, fallback or "Interface\\Buttons\\WHITE8X8")
    local tex = b["Get" .. state .. "Texture"](b)
    if tex then ns.SetArt(tex, name, fallback) end
    return tex
end

-- The gold + / - that folds a group away and opens it again (the classic
-- quest log's, UI-PlusMinus-Buttons: + on the left of its top half, - on the
-- right). folded() says which to show; b.Look() redraws it.
local function FoldButton(parent, folded, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    local glyph = b:CreateTexture(nil, "ARTWORK")
    glyph:SetSize(11, 11)
    glyph:SetPoint("CENTER")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(glyph)
    hl:SetBlendMode("ADD")
    b.Look = function()
        local l = folded() and 0 or 0.5
        for _, t in ipairs({ glyph, hl }) do
            ns.SetArtPart(t, "Interface\\Buttons\\UI-PlusMinus-Buttons", l, l + 0.5, 0, 0.5)
        end
    end
    b:SetScript("OnClick", onClick)
    b.Look()
    return b
end

-- The game's red button (128-redbutton): its ends keep their shape at any
-- width, the middle stretches. Text in gold, white under the mouse.
local RED_W, RED_H, RED_END = 470, 128, 118  -- (the art's size and its ends, in its pixels)
local function RedButton(parent, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetNormalFontObject(GameFontNormal)
    b:SetHighlightFontObject(GameFontHighlight)
    b:SetDisabledFontObject(GameFontDisable)
    b:SetPushedTextOffset(1, -1)
    b.art = ns.SliceArt(b, "128-redbutton-up", 0.25, 0.25, 0, 0, 10, 10, 0, 0)
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    ns.SetArt(glow, "128-redbutton-highlight")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.6)
    -- the ends as wide as the button's height allows (half the button at most)
    local function Cut()
        local bw, bh = b:GetSize()
        if not bw or bw <= 0 or not bh or bh <= 0 then return end
        local scale = bh / RED_H
        local cap = math.min(RED_END * scale, bw / 2)
        local frac = cap / scale / RED_W
        b.art:Layout(frac, frac, 0, 0, cap, cap, 0, 0)
    end
    local function Look()
        b.art:Set(not b:IsEnabled() and "128-redbutton-disable"
            or b.down and "128-redbutton-pressed" or "128-redbutton-up")
    end
    b:SetScript("OnSizeChanged", Cut)
    b:HookScript("OnMouseDown", function() if b:IsEnabled() then b.down = true Look() end end)
    b:HookScript("OnMouseUp", function() b.down = nil Look() end)
    b:HookScript("OnDisable", Look)
    b:HookScript("OnEnable", Look)
    b:SetSize(w or 120, h or 22)
    Cut()
    return b
end

-- fmt is the value's display format; zeroText, if given, is shown for 0.
-- row: the settings pages' rows (the label column's width): the label sits
-- that far left of the slider, with the game's < > step arrows round the bar
-- and the value after it; otherwise "label: value" above the bar.
local function CreateSlider(parent, width, label, minV, maxV, step, get, set, fmt, zeroText, row)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 17)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:EnableMouse(true)
    s:SetHitRectInsets(0, 0, -4, -4)

    -- the bar (minimal_sliderbar: rounded ends, a stretching middle) and its knob
    local left = s:CreateTexture(nil, "BACKGROUND")
    left:SetSize(11, 17)
    left:SetPoint("LEFT")
    ns.SetArt(left, "minimal_sliderbar_left")
    local right = s:CreateTexture(nil, "BACKGROUND")
    right:SetSize(11, 17)
    right:SetPoint("RIGHT")
    ns.SetArt(right, "minimal_sliderbar_right")
    local mid = s:CreateTexture(nil, "BACKGROUND")
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    ns.SetArt(mid, "_minimal_sliderbar_middle")
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = s:GetThumbTexture()
    if ns.SetArt(thumb, "minimal_sliderbar_button") then thumb:SetSize(20, 19) end

    local text = s:CreateFontString(nil, "OVERLAY", row and "GameFontNormal" or "GameFontHighlightSmall")
    Ink(parent, text)
    text:SetJustifyH("LEFT")
    local value = text
    if row then
        -- (a step either way, as the game's sliders have)
        local function Arrow(name, w, h, d)
            local a = CreateFrame("Button", nil, s)
            a:SetSize(w, h)
            StateArt(a, "Normal", name)
            local hl = StateArt(a, "Highlight", name)
            if hl then hl:SetBlendMode("ADD") hl:SetAlpha(0.5) end
            a:SetScript("OnClick", function() s:SetValue(s:GetValue() + d * step) end)
            return a
        end
        local less = Arrow("minimal_sliderbar_button_left", 11, 19, -1)
        less:SetPoint("RIGHT", s, "LEFT", -2, 0)
        local more = Arrow("minimal_sliderbar_button_right", 9, 18, 1)
        more:SetPoint("LEFT", s, "RIGHT", 2, 0)
        text:SetPoint("LEFT", s, "LEFT", -row - 13, 0)
        text:SetWidth(row - 12)
        text:SetText(label)
        s.text = text
        value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        Ink(parent, value, INK_HEAD)
        value:SetPoint("LEFT", more, "RIGHT", 6, 0)
        value:SetJustifyH("LEFT")
    else
        text:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
    end
    local function SetLabel(v)
        -- (fmt: a format, or a function turning the value into text)
        local shown = (zeroText and v == 0) and zeroText
            or type(fmt) == "function" and fmt(v) or string.format(fmt or "%.2f", v)
        value:SetText(row and shown or (label .. ": " .. shown))
    end

    s:SetScript("OnValueChanged", function(_, v)
        SetLabel(v)
        if s.ready then set(v) end
    end)
    s.Refresh = function()
        s.ready = false
        s:SetValue(get() or minV)
        SetLabel(get() or minV)
        s.ready = true
    end
    controls[#controls + 1] = s
    return s
end

-- The game's minimal checkbox, its tick in gold
local function MinimalCheck(c)
    c:SetSize(24, 23)
    StateArt(c, "Normal", "checkbox-minimal", "Interface\\Buttons\\UI-CheckBox-Up")
    StateArt(c, "Pushed", "checkbox-minimal", "Interface\\Buttons\\UI-CheckBox-Down")
    local hl = StateArt(c, "Highlight", "checkbox-minimal", "Interface\\Buttons\\UI-CheckBox-Highlight")
    if hl then hl:SetBlendMode("ADD") hl:SetAlpha(0.35) end
    StateArt(c, "Checked", "checkmark-minimal", "Interface\\Buttons\\UI-CheckBox-Check")
    StateArt(c, "DisabledChecked", "checkmark-minimal-disabled", "Interface\\Buttons\\UI-CheckBox-Check-Disabled")
end

-- invert = the checkbox shows the opposite of the stored value (e.g. "hide");
-- width: the room for box and label (a longer label wraps instead of running
-- into the next column); icon: its toggle button's (ns.ToggleIcon), between
-- box and label. row: the settings pages' rows: the label sits that far left
-- of the box (the label column's width), as in the game's Options.
local function CreateCheck(parent, label, get, set, invert, width, icon, row)
    local c = CreateFrame("CheckButton", nil, parent)
    MinimalCheck(c)
    local text = c:CreateFontString(nil, "OVERLAY", row and "GameFontNormal" or "GameFontHighlight")
    Ink(parent, text)
    text:SetJustifyH("LEFT")
    text:SetText(label)
    c.text = text
    if row then
        local start = -row  -- (the label's left edge, from the box's)
        if icon then
            local tex = c:CreateTexture(nil, "OVERLAY")
            tex:SetSize(16, 16)
            tex:SetPoint("LEFT", c, "LEFT", start, 0)
            if not ns.SetIconArt(c, tex, icon) and icon:find("\\Icons\\", 1, true) then
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            start = start + 20
        end
        text:SetPoint("LEFT", c, "LEFT", start, 0)
        text:SetWidth(-start - 12)
        text:SetWordWrap(true)
        -- (the whole row clickable, label too)
        c:SetHitRectInsets(-row, 0, -3, -3)
    else
        local room = 30  -- (box and gap, left of the label)
        if icon then
            local tex = c:CreateTexture(nil, "OVERLAY")
            tex:SetSize(16, 16)
            tex:SetPoint("LEFT", c, "RIGHT", 2, 0)
            if not ns.SetIconArt(c, tex, icon) and icon:find("\\Icons\\", 1, true) then
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- (a spell or item icon: without its frame)
            end
            c.iconTex = tex
            text:SetPoint("LEFT", tex, "RIGHT", 4, 0)
            room = 50
        else
            text:SetPoint("LEFT", c, "RIGHT", 2, 0)
        end
        if width and text:GetStringWidth() > width - room then
            text:SetWidth(width - room)
            text:SetWordWrap(true)
        end
        -- (label clickable too)
        c:SetHitRectInsets(0, -(room - 30) - math.min(text:GetStringWidth(), width and width - room or 9999), 0, 0)
    end
    c:SetScript("OnClick", function()
        local v = c:GetChecked() and true or false
        if invert then v = not v end
        set(v)
    end)
    c.Refresh = function()
        local v = get() and true or false
        if invert then v = not v end
        c:SetChecked(v)
    end
    controls[#controls + 1] = c
    return c
end

-- three states for profiles: nil = leave as set, true = show, false = hide
local CYCLE = { [1] = { nil, "|cff888888-|r" }, [2] = { true, "|cff33ff33Show|r" }, [3] = { false, "|cffff5555Hide|r" } }
local function CreateCycle(parent, width, label, get, set)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 22)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ink(parent, text)
    text:SetPoint("LEFT")
    text:SetWidth(width - 50)  -- narrow columns (5 profiles): don't run under the button
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetText(label)
    local b = RedButton(row, 46, 20)
    b:SetPoint("RIGHT")
    local function IndexOf(v)
        for i, s in ipairs(CYCLE) do if s[1] == v then return i end end
        return 1
    end
    b:SetScript("OnClick", function()
        set(CYCLE[IndexOf(get()) % 3 + 1][1])
        row.Refresh()
    end)
    row.Refresh = function() b:SetText(CYCLE[IndexOf(get())][2]) end
    controls[#controls + 1] = row
    return row
end

-- Dropdowns: a box showing the current choice; click it for the list. Our own,
-- not the game's dropdown menus (those are known to spread "blocked action"
-- taint). choices: { { value, label }, ... }, or a function returning that.
local list, listOwner  -- the open list, and the box it belongs to
local listRows = {}

local function CloseList()
    if list then list:Hide() end
    local owner = listOwner
    listOwner = nil
    if owner and owner.Look then owner.Look() end
end

local LIST_ROW, LIST_PAD = 20, 10  -- (a choice's height; the menu's inner margin)
local LIST_ROWS = 18  -- (longer lists, such as many SharedMedia fonts, go into columns)
-- a text part's sizes (Column's TextPart)
local TEXT_SIZES = {}
for v = 8, 28 do TEXT_SIZES[#TEXT_SIZES + 1] = { v, tostring(v) } end
-- the font dropdowns' tip (their list is ns.FontChoices, Fonts.lua)
local FONT_TIP = "The game's fonts, then any that other addons share through SharedMedia. One that can't be loaded shows in Morpheus."
local function OpenList(box, choices, current, pick)
    if not list then
        -- the game's dropdown menu: a dark rounded panel, a gold tick by the choice
        list = CreateFrame("Frame", nil, UIParent)
        list:SetFrameStrata("FULLSCREEN_DIALOG")
        local e = 20 / 68  -- (common-dropdown-bg's edge, of its 68 pixels)
        ns.SliceArt(list, "common-dropdown-bg", e, e, e, e, 14, 14, 14, 14)
        list:EnableMouse(true)
        -- a click anywhere else closes it
        list:SetScript("OnEvent", function()
            if not (list:IsMouseOver() or (listOwner and listOwner:IsMouseOver())) then CloseList() end
        end)
        list:SetScript("OnShow", function() pcall(list.RegisterEvent, list, "GLOBAL_MOUSE_DOWN") end)
        list:SetScript("OnHide", function() pcall(list.UnregisterEvent, list, "GLOBAL_MOUSE_DOWN") end)
    end
    local perCol = math.ceil(#choices / math.ceil(#choices / LIST_ROWS))
    -- (a font list a little wider: other addons' font names run long)
    local colW = math.max(box:GetWidth(), choices[1] and choices[1][3] and 170 or 120) - 2 * LIST_PAD
    for i, ch in ipairs(choices) do
        local r = listRows[i]
        if not r then
            r = CreateFrame("Button", nil, list)
            r:SetHeight(LIST_ROW)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 22, 0)
            r.text:SetPoint("RIGHT", -6, 0)
            r.text:SetJustifyH("LEFT")
            -- (one line, cut short: "AR ZhongkaiGBK Medium" wrapped onto the row under it, the user 2026-11-08)
            r.text:SetWordWrap(false)
            r.text:SetMaxLines(1)
            r.font = { r.text:GetFont() }  -- (back to this after a font list)
            r.check = r:CreateTexture(nil, "OVERLAY")
            ns.SetArt(r.check, "common-dropdown-icon-checkmark-yellow", "Interface\\Buttons\\UI-CheckBox-Check")
            r.check:SetSize(15, 14)
            r.check:SetPoint("LEFT", 4, 0)
            r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
            r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.25)
            listRows[i] = r
        end
        local col, row = math.floor((i - 1) / perCol), (i - 1) % perCol
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", LIST_PAD + col * colW, -LIST_PAD - row * LIST_ROW)
        r:SetWidth(colW)
        -- (a font choice, ch[3] its file: its name shown in it; the rows are
        -- shared by every dropdown, so the others get their own font back)
        if ch[3] then ns.SetFontSafe(r.text, ch[1], 13)
        elseif r.font[1] then r.text:SetFont(r.font[1], r.font[2], r.font[3] or "") end
        r.text:SetText(ch[2])
        r.check:SetShown(ch[1] == current)
        r:SetScript("OnClick", function()
            CloseList()
            pick(ch[1])
        end)
        r:Show()
    end
    for i = #choices + 1, #listRows do listRows[i]:Hide() end
    -- the same size on screen as the box, under it
    list:SetScale(box:GetEffectiveScale() / UIParent:GetEffectiveScale())
    list:SetSize(math.ceil(#choices / perCol) * colW + 2 * LIST_PAD, perCol * LIST_ROW + 2 * LIST_PAD)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
    list:SetClampedToScreen(true)
    local prev = listOwner
    listOwner = box
    if prev and prev ~= box and prev.Look then prev.Look() end
    if box.Look then box.Look() end
    list:Show()
end

-- the game's dropdown box (common-dropdown-b-button: its arrow in the art),
-- lit under the mouse and while its list is open
local function CreateDropdown(parent, width, get, set, choices)
    local box = CreateFrame("Button", nil, parent)
    box:SetSize(width, 24)
    box.art = ns.SliceArt(box, "common-dropdown-b-button", 10 / 97, 26 / 97, 0, 0, 9, 24, 0, 0)
    box.Look = function()
        box.art:Set(listOwner == box and "common-dropdown-b-button-open"
            or box:IsMouseOver() and "common-dropdown-b-button-hover" or "common-dropdown-b-button")
    end
    box:SetScript("OnEnter", box.Look)
    box:SetScript("OnLeave", box.Look)
    local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 9, 0)
    text:SetPoint("RIGHT", -26, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    local function Choices() return type(choices) == "function" and choices() or choices end
    box.Refresh = function()
        local v, all = get(), Choices()
        for _, ch in ipairs(all) do
            if ch[1] == v then text:SetText(ch[2]) return end
        end
        text:SetText(all[1] and all[1][2] or "")
    end
    box:SetScript("OnClick", function()
        if listOwner == box then CloseList() return end
        OpenList(box, Choices(), get(), function(v)
            set(v)
            box.Refresh()
        end)
    end)
    box:SetScript("OnHide", function() if listOwner == box then CloseList() end end)
    controls[#controls + 1] = box
    return box
end

-- Key binding buttons: click one, then press a key (with Shift, Ctrl or Alt if
-- you like) to bind it, Escape to cancel; right-click clears it. They're the
-- game's own bindings (Bindings.xml), saved the game's way, so they also show
-- in Esc > Options > Keybindings. A key bound to something else moves here.
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
                        LALT = true, RALT = true, LMETA = true, RMETA = true }
local listening  -- the button waiting for a key

local function CreateKeyButton(parent, command)
    local b = RedButton(parent)
    b:SetSize(130, 22)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.Refresh = function()
        if listening == b then b:SetText("Press a key...") return end
        local key = GetBindingKey(command)
        b:SetText(key and (GetBindingText and GetBindingText(key) or key) or "|cff888888Not bound|r")
    end
    b.Stop = function()
        if listening == b then listening = nil end
        b:EnableKeyboard(false)
        b.Refresh()
    end
    local function Save()
        SaveBindings(GetCurrentBindingSet())
        ns.RefreshControls()  -- (another action may have lost the key)
    end
    b:SetScript("OnKeyDown", function(_, key)
        if MODIFIER_KEYS[key] then return end
        if key == "ESCAPE" then b.Stop() return end
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        for _, old in ipairs({ GetBindingKey(command) }) do SetBinding(old) end
        SetBinding(combo, command)
        b.Stop()
        Save()
    end)
    b:SetScript("OnClick", function(_, button)
        if InCombatLockdown() then ns.Log("Key bindings can't be changed in combat.") return end
        if button == "RightButton" then
            b.Stop()
            for _, old in ipairs({ GetBindingKey(command) }) do SetBinding(old) end
            Save()
            return
        end
        if listening == b then b.Stop() return end
        if listening then listening.Stop() end
        listening = b
        b:EnableKeyboard(true)
        b:SetPropagateKeyboardInput(false)
        b.Refresh()
    end)
    b:SetScript("OnHide", b.Stop)
    b:EnableKeyboard(false)
    controls[#controls + 1] = b
    return b
end

-- The game's colour picker. onChange(r, g, b) as you pick; Cancel puts the
-- colour you started with back. (Newer clients set it up with one call; older
-- ones through fields on the frame.)
local function OpenColorPicker(r, g, b, onChange)
    local function Picked() onChange(ColorPickerFrame:GetColorRGB()) end
    local function Cancel() onChange(r, g, b) end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false, swatchFunc = Picked, cancelFunc = Cancel,
        })
    else
        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func, ColorPickerFrame.cancelFunc = Picked, Cancel
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Show()
    end
    ColorPickerFrame:Raise()  -- (above our settings window)
end

-- Where each setting's control sits on its page, so a toggle button's
-- right-click can open the page and mark it: page.bfiMarks["group/key"]
-- (sec: the section it's in, page.bfiSection, so ShowOption can open it)
local function Mark(page, group, key, x, y, width, height)
    if not (group and key) then return end
    page.bfiMarks = page.bfiMarks or {}
    page.bfiMarks[group .. "/" .. key] = { x = x, y = y, w = width, h = height, sec = page.bfiSection }
end

-- The settings pages' rows: how wide a row is, and where its control starts;
-- a section's contents sit SEC_IN in from its heading's +/-
local ROW_W, ROW_LABEL, SEC_IN = 620, 290, 20

-- A section you haven't touched starts folded, on every page but Start here (the user, 2026-11-06)
local function SectionFolded(key)
    local v = ns.db.optionsWindow.folded[key]
    -- (nor on the two pages made to be read down in one go: what the map does by itself, and the keys'
    -- first two groups)
    if v == nil then
        return not (key:sub(1, 9) == "overview/" or key:sub(1, 5) == "acts/"
            or key == "keys/The keys worth having" or key == "keys/With a controller")
    end
    return v
end

-- Sections fold (their heading's +/-, ns.db.optionsWindow.folded) except
-- while searching: then every one is open, so all matches are found
local foldsOpen = false

-- Stacks controls top to bottom from (x, y), `width` wide.
-- side (settings pages): a column beside another, x and width as given, not
-- stacked into rows; y nil = under everything on the page so far. Make both
-- of a pair before filling either, so they start level.
local function Column(parent, x, y, width, side)
    width = width or 300
    -- (a new column ends the sections still open in the page's others, so a
    -- folded one hides only what was made in it)
    for _, c in ipairs(parent.bfiColumns or {}) do c:EndCard() end
    if y == nil then y = (parent.bfiLowest or 0) < 0 and parent.bfiLowest - 8 or 0 end
    -- col.y: where the next row goes. Setting it also keeps the page's lowest
    -- row (parent.bfiLowest), which sizes the page for scrolling.
    local yv = y
    local col = setmetatable({}, {
        __index = function(_, k) if k == "y" then return yv end end,
        __newindex = function(t, k, v)
            if k == "y" then
                yv = v
                if v < (parent.bfiLowest or 0) then parent.bfiLowest = v end
            else
                rawset(t, k, v)
            end
        end,
    })
    -- bigger text (the settings pages' own sizes) gets taller rows
    local he = parent.bfiSettingsPage and math.max(0, HeadExtra()) or 0
    local te = parent.bfiSettingsPage and math.max(0, TextExtra()) or 0

    -- Rows (settings pages), as in the game's Options: one column as wide as
    -- the page, each setting's label on the left and its control on the right,
    -- every control starting at the same place (ctrlX). A page's columns stack,
    -- each below the last; a page with bfiKeepColumns keeps them side by side.
    local rows = parent.bfiSettingsPage and not parent.bfiKeepColumns and not side
    if rows then
        x, width = 0, ROW_W
        if (parent.bfiLowest or 0) < 0 then yv = parent.bfiLowest - 8 end
    end
    local ctrlX = x + ROW_LABEL
    -- (a section's contents a step in from its heading)
    local secIn = parent.bfiSettingsPage and not parent.bfiKeepColumns and SEC_IN or 0
    x, width = x + secIn, width - secIn
    local baseX, baseW = x, width
    if parent.bfiSettingsPage then
        parent.bfiColumns = parent.bfiColumns or {}
        table.insert(parent.bfiColumns, col)
    end

    -- Settings that hang off the switch right above them (Requires) are
    -- indented, with a thin guide line down their left
    local runTop
    local function StartIndent()
        if runTop then return end
        runTop = col.y
        x, width = baseX + 16, baseW - 16
    end
    local function EndIndent(y)
        if not runTop then return end
        if runTop - y > 4 then
            local guide = parent:CreateTexture(nil, "ARTWORK")
            guide:SetColorTexture(1, 0.82, 0, 0.18)
            guide:SetPoint("TOPLEFT", baseX + 7, runTop - 3)
            guide:SetSize(1, runTop - y - 6)
        end
        x, width = baseX, baseW
        runTop = nil
    end
    -- where this column's controls start now (for pages placing their own widgets)
    function col:Left() return x end
    -- one step further in for what follows (Indent(true) ... Indent()), for a
    -- choice that belongs to the one above it; nests inside a Requires indent
    function col:Indent(on)
        local d = on and 16 or -16
        x, width = x + d, width - d
    end
    -- A section (settings pages) runs from its Header to the next one or the
    -- page's end. Folded, everything made in it is hidden once it ends, and
    -- the column goes on right under its heading. (Made, then hidden: pages
    -- that place widgets of their own need nothing special.)
    local section
    local function Kids() return select("#", parent:GetChildren()) end
    local function CloseSection()
        local s = section
        section = nil
        if not (s and s.folded) then return end
        local kids = { parent:GetChildren() }
        for i = s.kids + 1, #kids do kids[i]:Hide() end
        local regions = { parent:GetRegions() }
        for i = s.regions + 1, #regions do regions[i]:Hide() end
        yv = s.y
        parent.bfiLowest = math.min(s.lowest, s.y)
    end
    -- the end of a section (the next Header, or the page's end: BuildPage)
    function col:EndCard()
        EndIndent(self.y)
        CloseSection()
    end
    -- In rows, the label of a control that isn't a checkbox or slider: at the
    -- row's left, as wide as the label column, on the control (so it greys out
    -- with it), in the middle of a row h high. Returns it and the row's height,
    -- and a frame over it so hovering the label shows the control's Tip too.
    local function RowLabel(owner, label)
        local fs = owner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        Ink(parent, fs)
        fs:SetWidth(ctrlX - x - 12)
        fs:SetJustifyH("LEFT")
        fs:SetText(label)
        local h = math.max(28, fs:GetStringHeight() + 12 + te)
        -- (lined up with the checkbox and slider labels: at x itself)
        fs:SetPoint("LEFT", parent, "TOPLEFT", x, col.y - h / 2)
        local hover = CreateFrame("Frame", nil, parent)
        hover:SetAllPoints(fs)
        hover:EnableMouse(true)
        return fs, h, hover
    end
    -- what the options search finds (see Search), and where it sits on the page
    local function Index(text, top, height)
        if not text or text == "" then return end
        parent.bfiSearch = parent.bfiSearch or {}
        local plain = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        local e = { text = plain:lower(), x = x, y = top, w = width, h = height }
        table.insert(parent.bfiSearch, e)
        return e
    end
    local dep  -- (Requires) the switch the next controls depend on
    local adv  -- (Advanced) the next controls are fine-tuning
    -- the next controls are fine-tuning, left out unless advanced settings are
    -- shown; Advanced() with nothing ends it. (Settings pages only.)
    function col:Advanced(on) adv = on and parent.bfiSettingsPage and true or nil end
    -- leave this one out? It's counted (the page says so) and its setting still
    -- reset with the page; the next Tip has nothing to go on
    local function Skipped(group, key)
        if not adv or advancedShown then return false end
        parent.bfiSkipped = (parent.bfiSkipped or 0) + 1
        if key then
            parent.bfiKeys = parent.bfiKeys or {}
            table.insert(parent.bfiKeys, { group, key })
        end
        col.last, col.lastLabel, col.lastEntry, col.lastKey, col.lastHover = nil, nil, nil, nil, nil
        return true
    end
    -- A control just made: what the next Tip goes on, greyed while `dep` is off,
    -- and its setting kept for the page's reset button. hover: a frame over its
    -- label in a row (RowLabel), which shows the Tip too.
    local function Made(frame, label, entry, group, key, hover)
        col.last, col.lastLabel, col.lastEntry, col.lastHover = frame, label, entry, hover
        col.lastKey = key and ((group or "") .. "/" .. key) or nil  -- (Requires: the switch right above)
        if dep and frame then frame.bfiDep = dep end
        if key and parent.bfiSettingsPage then
            parent.bfiKeys = parent.bfiKeys or {}
            table.insert(parent.bfiKeys, { group, key })
        end
    end
    -- the controls after this are greyed out while that setting is off;
    -- Requires() with nothing ends it
    -- (group may be a function instead: on while it returns true, no indent)
    function col:Requires(group, key)
        EndIndent(self.y)
        if type(group) == "function" then
            dep = group
            if key == true then StartIndent() end  -- (a switch of its own making right above)
        elseif key then
            local get = LayerSetting(group, key)
            dep = function() return get() and true or false end
            -- the switch is the control right above: what follows hangs under it
            if self.lastKey == (group or "") .. "/" .. key then StartIndent() end
        else
            dep = nil
        end
    end
    -- what the control just above does, on hover (why you'd want it, a
    -- sentence or two); how: the mouse and keys for it, a grey line under, as
    -- the game's own hints. The search finds both.
    function col:Tip(text, how)
        local f, label = self.last, self.lastLabel
        if not f then return end
        for _, on in ipairs({ f, self.lastHover }) do
            on:HookScript("OnEnter", function()
                GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
                GameTooltip:SetText(label or "", 1, 0.82, 0)
                if text ~= "" then GameTooltip:AddLine(text, 1, 1, 1, true) end
                if how then GameTooltip:AddLine(how, 0.6, 0.6, 0.6, true) end
                GameTooltip:Show()
            end)
            on:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
        if self.lastEntry then
            self.lastEntry.text = self.lastEntry.text .. "  " .. text:lower() .. (how and "  " .. how:lower() or "")
        end
    end
    -- a section title (icon: its toggle button's, ns.ToggleIcon, in front of
    -- it). On the settings pages: the gold +/- that folds the section away,
    -- the title in white (gold under the mouse; click it to fold too), and a
    -- faint line under it. Elsewhere: a gold rule under the title.
    function col:Header(text, icon)
        if adv and not advancedShown then return end  -- (a whole fine-tuning section)
        self:EndCard()
        if parent.bfiSettingsPage then
            self.y = self.y - (self.y < -1 and 12 or 2)
            local hx = baseX - secIn  -- (the heading starts where the column does)
            local key = (parent.bfiKey or "") .. "/" .. text
            local folded = not foldsOpen and SectionFolded(key)
            local function Toggle() if ns.ToggleOptionSection then ns.ToggleOptionSection(key) end end
            local h = 22 + he
            local b = CreateFrame("Button", nil, parent)
            b:SetPoint("TOPLEFT", hx, self.y + 2)
            b:SetSize(baseW + secIn, h)
            local fold = FoldButton(b, function() return folded end, Toggle)
            fold:SetPoint("LEFT", -3, 0)
            local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("LEFT", icon and 38 or 18, 0)
            fs:SetText(text)
            Ink(parent, fs, INK_HEAD, true)
            if icon then
                local tex = b:CreateTexture(nil, "OVERLAY")
                tex:SetSize(16, 16)
                tex:SetPoint("LEFT", 18, 0)
                if not ns.SetIconArt(b, tex, icon) and icon:find("\\Icons\\", 1, true) then
                    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- (a spell or item icon: without its frame)
                end
            end
            b:SetScript("OnClick", Toggle)
            b:SetScript("OnEnter", function() fs:SetTextColor(1, 0.82, 0) end)
            b:SetScript("OnLeave", function() fs:SetTextColor(INK_HEAD[1], INK_HEAD[2], INK_HEAD[3]) end)
            Index(text, self.y, h)
            parent.bfiHeads = parent.bfiHeads or {}   -- (the scroll bar's marks: BuildPage)
            table.insert(parent.bfiHeads, { key = key, text = text, y = self.y })
            local line = parent:CreateTexture(nil, "ARTWORK")
            line:SetPoint("TOPLEFT", hx + 18, self.y - h + 1)
            line:SetSize(baseW + secIn - 18, 1)
            line:SetColorTexture(1, 1, 1, 1)
            if not pcall(line.SetGradient, line, "HORIZONTAL",
                         CreateColor(1, 1, 1, 0.22), CreateColor(1, 1, 1, 0)) then
                line:SetColorTexture(1, 1, 1, 0.12)  -- (older SetGradient signature)
            end
            self.y = self.y - h - 4
            parent.bfiSection = key
            parent.bfiSections = parent.bfiSections or {}  -- (the page title's +/-)
            table.insert(parent.bfiSections, key)
            section = { folded = folded, kids = Kids(), regions = parent:GetNumRegions(),
                        lowest = math.min(parent.bfiLowest or 0, self.y), y = self.y }
            return
        end
        self.y = self.y - 6
        Index(text, self.y, 18)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", x + (icon and 20 or 0), self.y)
        fs:SetText(text)
        if icon then
            local tex = parent:CreateTexture(nil, "OVERLAY")
            tex:SetSize(16, 16)
            tex:SetPoint("RIGHT", fs, "LEFT", -4, 0)
            if not ns.SetIconArt(parent, tex, icon) and icon:find("\\Icons\\", 1, true) then
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- (a spell or item icon: without its frame)
            end
        end
        local rule = parent:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 0.82, 0, 0.25)
        rule:SetPoint("TOPLEFT", x, self.y - 16 - he)
        rule:SetSize(width - 10, 1)
        self.y = self.y - 22 - he
    end
    -- A checklist in columns (settings pages): Grid(n) ... Grid(). Each
    -- SubHeader inside starts the next of n columns, level with the first
    -- (a further n: a new band under them); the checkboxes in it go box first,
    -- label after, not in rows. Grid() goes on under the longest column.
    local grid
    function col:Grid(n)
        if n then
            grid = { n = n, top = self.y, low = self.y, i = 0, x = x, w = width, rows = rows }
            rows = false
            return
        end
        if not grid then return end
        grid.low = math.min(grid.low, self.y)
        x, width, rows = grid.x, grid.w, grid.rows
        self.y = grid.low - 4
        grid = nil
    end
    -- a small heading inside a section, for a list in parts (no rule)
    function col:SubHeader(text)
        if adv and not advancedShown then return end
        if grid then
            grid.low = math.min(grid.low, self.y)
            grid.i = grid.i + 1
            local at = (grid.i - 1) % grid.n
            if at == 0 and grid.i > 1 then grid.top = grid.low - 6 end
            local cw = grid.w / grid.n
            x, width = grid.x + at * cw, cw - 8
            self.y = grid.top
        end
        self.y = self.y - 4
        Index(text, self.y, 16)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", x + 2, self.y)
        fs:SetText(text:upper())
        Ink(parent, fs, INK_SOFT)
        self.y = self.y - 16 - te
    end
    -- (a wrapped label takes the rows it needs)
    local function Step(c, base)
        local h = c.text and c.text:GetStringHeight() or 0
        return math.max(base, h + 10)
    end
    -- A row's height for a label (rows: 28 at least, more for a wrapped one)
    local function RowHeight(fs, base)
        return math.max(base or 28, (fs and fs:GetStringHeight() or 0) + 12 + te)
    end
    -- a slider in a row: its label on the left, < bar > value from ctrlX
    local function RowSlider(s)
        local h = RowHeight(s.text)
        s:SetPoint("LEFT", parent, "TOPLEFT", ctrlX + 13, col.y - h / 2)
        local hover = CreateFrame("Frame", nil, parent)
        hover:SetAllPoints(s.text)
        hover:EnableMouse(true)
        return h, hover
    end
    function col:Slider(label, minV, maxV, step, group, key, fmt, zeroText)
        if Skipped(group, key) then return end
        -- every opacity (0 to 1) reads as a percentage
        if not fmt and maxV == 1 and label:lower():find("opacity", 1, true) then
            fmt = function(v) return string.format("%d%%", v * 100 + 0.5) end
        end
        -- and every size (a layer's scale) as times its usual, as the others show it
        if not fmt and (key == "scale" or key == "objectScale") then fmt = "%.2fx" end
        local get, set = Setting(group, key)
        -- (a layer's size: in town or city view with a size of its own there, it's that one the slider
        -- shows and moves. A slider that did nothing in Darnassus read as broken, the user)
        if key == "scale" and ns.TownPinSize and not (ns.PIN_NOT_IN_TOWN and ns.PIN_NOT_IN_TOWN[group]) then
            local get0, set0 = get, set
            local function View()
                local v = (ns.InCityView and ns.InCityView() and "cityView") or (ns.InTownView and ns.InTownView() and "townView")
                return v and ns.db[v].sizes and ns.db[v].sizes[group] and v or nil
            end
            get = function()
                local v = View()
                if v then return ns.db[v].sizes[group] end   -- (the place's own slider comes on top: ns.TownPinSize)
                return get0()
            end
            set = function(value)
                local v = View()
                if v then
                    ns.db[v].sizes[group] = value
                    ns.OnSettingChanged(v, "sizes")
                else
                    set0(value)
                end
            end
        end
        if rows then
            local s = CreateSlider(parent, 170, label, minV, maxV, step, get, set, fmt, zeroText, ctrlX - x)
            local h, hover = RowSlider(s)
            Mark(parent, group, key, x, self.y, width, h)
            Made(s, label, Index(label, self.y, h), group, key, hover)
            self.y = self.y - h
            return
        end
        local s = CreateSlider(parent, width - 30, label, minV, maxV, step, get, set, fmt, zeroText)
        s:SetPoint("TOPLEFT", x + 4, self.y - 16 - te)
        Mark(parent, group, key, x, self.y, width, 40 + te)
        Made(s, label, Index(label, self.y, 40 + te), group, key)
        self.y = self.y - 42 - te
    end
    -- a slider with its own get/set, for values that aren't a plain setting
    function col:SliderWith(label, minV, maxV, step, get, set, fmt, zeroText)
        if Skipped() then return end
        if rows then
            local s = CreateSlider(parent, 170, label, minV, maxV, step, get, set, fmt, zeroText, ctrlX - x)
            local h, hover = RowSlider(s)
            Made(s, label, Index(label, self.y, h), nil, nil, hover)
            self.y = self.y - h
            return
        end
        local s = CreateSlider(parent, width - 30, label, minV, maxV, step, get, set, fmt, zeroText)
        s:SetPoint("TOPLEFT", x + 4, self.y - 16 - te)
        Made(s, label, Index(label, self.y, 40 + te))
        self.y = self.y - 42 - te
    end
    -- Stops along one track: stops = { { key, name }, ... }, each a setting in
    -- `group`, in order and at least a step apart. The bar between them is
    -- coloured by what happens there: colours has one more than the stops
    -- (before the first, between each two, after the last). ticks = { { value,
    -- text }, ... } under it. Pressing the track brings the nearest stop there,
    -- and it follows the mouse while the button is held.
    function col:Stops(label, group, stops, minV, maxV, step, colours, ticks, fmt)
        if Skipped(group, stops[1][1]) then
            -- (the others reset with the page too)
            for i = 2, #stops do table.insert(parent.bfiKeys, { group, stops[i][1] }) end
            return
        end
        local tw = rows and 290 or width - 20
        local top = rows and 0 or 16 + te  -- (not rows: the label above)
        local h = top + 52 + te
        local PAD = 6
        local barY = -(top + 26)  -- (the bar's middle; the stops' names above it)
        local f = CreateFrame("Frame", nil, parent)
        f:SetSize(tw, h)
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", rows and ctrlX or x + 4, self.y)
        f:EnableMouse(true)
        local hover
        if rows then
            local fs, _, hv = RowLabel(f, label)
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", parent, "TOPLEFT", x, self.y + barY)
            hover = hv
        else
            local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            Ink(parent, fs)
            fs:SetPoint("TOPLEFT", 0, 0)
            fs:SetText(label)
        end
        local function X(v) return PAD + (v - minV) / (maxV - minV) * (tw - 2 * PAD) end

        local edge = f:CreateTexture(nil, "BACKGROUND")
        edge:SetColorTexture(0, 0, 0, 0.8)
        edge:SetPoint("LEFT", f, "TOPLEFT", PAD - 1, barY)
        edge:SetSize(tw - 2 * PAD + 2, 10)
        local segs = {}
        for i, c in ipairs(colours) do
            local t = f:CreateTexture(nil, "BORDER")
            t:SetColorTexture(c[1], c[2], c[3], 1)
            t:SetHeight(8)
            segs[i] = t
        end
        for _, tk in ipairs(ticks or {}) do
            local line = f:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(1, 1, 1, 0.35)
            line:SetSize(1, 16)
            line:SetPoint("CENTER", f, "TOPLEFT", X(tk[1]), barY)
            local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            Ink(parent, fs, INK_SOFT)
            fs:SetPoint("TOP", f, "TOPLEFT", X(tk[1]), barY - 11)
            fs:SetText(tk[2])
        end
        local gets, sets, knobs, names = {}, {}, {}, {}
        for i, s in ipairs(stops) do
            gets[i], sets[i] = Setting(group, s[1])
            local k = f:CreateTexture(nil, "OVERLAY")
            k:SetColorTexture(0.1, 0.07, 0.03, 1)
            k:SetSize(12, 20)
            local fill = f:CreateTexture(nil, "OVERLAY", nil, 1)
            fill:SetColorTexture(1, 0.82, 0, 1)
            fill:SetPoint("TOPLEFT", k, 2, -2)
            fill:SetPoint("BOTTOMRIGHT", k, -2, 2)
            knobs[i] = k
            names[i] = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            Ink(parent, names[i], INK_HEAD)
        end

        local n = #stops
        local function Value(i) return gets[i]() or minV end
        local function Layout()
            for i = 1, n + 1 do
                local left = i == 1 and PAD or X(Value(i - 1))
                local right = i <= n and X(Value(i)) or tw - PAD
                local t = segs[i]
                t:ClearAllPoints()
                t:SetPoint("LEFT", f, "TOPLEFT", left, barY)
                t:SetWidth(math.max(1, right - left))
                t:SetShown(right - left >= 0.5)
            end
            for i = 1, n do
                knobs[i]:ClearAllPoints()
                knobs[i]:SetPoint("CENTER", f, "TOPLEFT", X(Value(i)), barY)
                names[i]:SetText(stops[i][2] .. " " .. fmt(Value(i)))
            end
            -- each name over its stop, pushed apart where stops sit close, and
            -- kept over the track
            local at, w = {}, {}
            for i = 1, n do w[i] = names[i]:GetStringWidth() end
            for i = 1, n do
                local lo = i == 1 and w[i] / 2 or at[i - 1] + (w[i - 1] + w[i]) / 2 + 6
                at[i] = math.max(X(Value(i)), lo)
            end
            for i = n, 1, -1 do
                local hi = i == n and tw - w[i] / 2 or at[i + 1] - (w[i + 1] + w[i]) / 2 - 6
                at[i] = math.min(at[i], hi)
            end
            for i = 1, n do
                names[i]:ClearAllPoints()
                names[i]:SetPoint("BOTTOM", f, "TOPLEFT", at[i], barY + 12)
            end
        end

        local function CursorValue()
            local cx = GetCursorPosition() / f:GetEffectiveScale()
            return minV + (cx - f:GetLeft() - PAD) / (tw - 2 * PAD) * (maxV - minV)
        end
        local function Move(i, v)
            local lo = i > 1 and Value(i - 1) + step or minV
            local hi = i < n and Value(i + 1) - step or maxV
            v = math.floor(math.max(lo, math.min(hi, v)) / step + 0.5) * step
            if math.abs(v - Value(i)) > step / 4 then
                sets[i](v)
                Layout()
            end
        end
        local function Stop() f:SetScript("OnUpdate", nil) end
        f:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local v, best, bd = CursorValue()
            for i = 1, n do
                -- (the nearest; of two as near, the one the mouse is past)
                local d = math.abs(Value(i) - v)
                if not best or d < bd or (d == bd and v > Value(i)) then best, bd = i, d end
            end
            Move(best, v)
            f:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then Stop() return end
                Move(best, CursorValue())
            end)
        end)
        f:SetScript("OnMouseUp", Stop)
        f:HookScript("OnHide", Stop)
        f.Refresh = Layout
        controls[#controls + 1] = f

        local text = label
        for _, s in ipairs(stops) do
            Mark(parent, group, s[1], x, self.y, width, h)
            text = text .. "  " .. s[2]
        end
        Made(f, label, Index(text, self.y, h), group, stops[1][1], hover)
        if parent.bfiSettingsPage then
            for i = 2, n do table.insert(parent.bfiKeys, { group, stops[i][1] }) end
        end
        self.y = self.y - h
        Layout()
    end
    -- a checkbox in a row: label on the left, the box at ctrlX, both in the
    -- row's middle; or (not rows) the box at the left, its label after it
    local function PlaceCheck(c, compact)
        if rows then
            local h = RowHeight(c.text, compact and 22 or 28)
            c:SetPoint("LEFT", parent, "TOPLEFT", ctrlX, col.y - h / 2)
            return h
        end
        c:SetPoint("TOPLEFT", x, col.y)
        return Step(c, compact and 20 or 25)
    end
    function col:Check(label, group, key, invert, icon)
        if Skipped(group, key) then return end
        local get, set = LayerSetting(group, key)
        local c = CreateCheck(parent, label, get, set, invert, width, icon, rows and ctrlX - x)
        if grid then c:SetSize(20, 20) end  -- (in a checklist: as small as its neighbours)
        local h = PlaceCheck(c, grid ~= nil)
        Mark(parent, group, key, x, self.y, width, h)
        Made(c, label, Index(label, self.y, h), group, key)
        self.y = self.y - h
    end
    -- a checkbox with its own get/set, for values that aren't a plain setting
    -- compact: a smaller box and tighter rows (long lists); icon: see CreateCheck
    -- marks: { { group, key }, ... }: the settings this row stands for, so "its settings" from a map button
    -- (ns.ShowOption) lands on it
    function col:CheckWith(label, get, set, compact, icon, marks)
        if Skipped() then return end
        local c = CreateCheck(parent, label, get, set, nil, width, icon, rows and ctrlX - x)
        if compact then c:SetSize(20, 20) end
        local h = PlaceCheck(c, compact)
        for _, m in ipairs(marks or {}) do Mark(parent, m[1], m[2], x, self.y, width, h) end
        Made(c, label, Index(label, self.y, h))
        self.y = self.y - h
    end
    -- a feature on the Overview page: { name, what it does, where it comes from,
    -- group, key, its page, the addon it needs }. Its switch, the line saying
    -- what it does, its source, and > to its page.
    function col:Feature(f)
        local present = not f[7] or ns.AddonPresent(f[7])
        local get, set = LayerSetting(f[4], f[5])
        if f.get then get, set = f.get, f.set end
        -- (its map button's icon, where it has one: "We should use icons where we have and it fits, it reads
        -- easier", the user 2026-11-15)
        local c = CreateCheck(parent, f[1], get, set, nil, width - 120, f.icon or (ns.LayerIcon and ns.LayerIcon(f[4], f[5])))
        if f.iconSize and c.iconTex then c.iconTex:SetSize(f.iconSize, f.iconSize) end
        c:SetPoint("TOPLEFT", x, self.y)
        local desc = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        Ink(parent, desc, INK_SOFT)
        desc:SetPoint("TOPLEFT", c.text, "BOTTOMLEFT", 0, -2)
        desc:SetWidth(width - 120)
        desc:SetJustifyH("LEFT")
        desc:SetText(f[2])
        local tag = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        Ink(parent, tag, INK_SOFT)
        tag:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width - 42, self.y - 6)
        -- (only where it comes from elsewhere: "built in" on most rows was noise)
        local source = f[3] ~= "built in" and f[3] or ""
        tag:SetText(present and source or ("|cffff6a4dneeds " .. f[7] .. "|r"))
        local go = RedButton(parent)
        go:SetSize(26, 20)
        go:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width - 12, self.y - 2)
        go:SetText(">")
        go:SetScript("OnClick", function() ns.OpenOptionAt(f[6], f[4], f[5]) end)
        -- hovering it: a tooltip, and the page it opens lights up in the list
        go:SetScript("OnEnter", function()
            GameTooltip:SetOwner(go, "ANCHOR_RIGHT")
            GameTooltip:SetText("More settings")
            GameTooltip:Show()
            ns.GlowNavPage(f[6], true)
        end)
        go:SetScript("OnLeave", function()
            GameTooltip:Hide()
            ns.GlowNavPage(f[6], false)
        end)
        if not present then c.bfiDep = function() return false end end  -- (greyed: see RefreshControls)
        local h = math.max(32, 20 + desc:GetStringHeight() + 8)
        Made(c, f[1], Index(f[1] .. "  " .. f[2], self.y, h), f[4], f[5])
        self.y = self.y - h
    end
    -- one of several values, as checkboxes that behave like radio buttons:
    -- choices = { { value, label }, ... }
    function col:Radio(group, key, choices)
        if Skipped(group, key) then return end
        for _, ch in ipairs(choices) do
            local value = ch[1]
            local c
            c = CreateCheck(parent, ch[2],
                function() return ns.db[group][key] == value end,
                function(v)
                    if v then
                        ns.db[group][key] = value
                        ns.OnSettingChanged(group, key)
                    end
                    ns.RefreshControls()  -- unticks the others; re-ticks this one if clicked off
                end, nil, width, nil, rows and ctrlX - x)
            local h = PlaceCheck(c)
            Made(c, ch[2], Index(ch[2], self.y, h))
            self.y = self.y - h
            if ch[3] then self:Note(ch[3], nil, nil, nil, 24) end  -- (what the option means)
        end
        Made(self.last, self.lastLabel, self.lastEntry, group, key)  -- (kept once for the reset)
    end
    function col:Cycle(label, get, set)
        local r = CreateCycle(parent, width - 10, label, get, set)
        r:SetPoint("TOPLEFT", x + 4, self.y)
        Index(label, self.y, 24 + te)
        self.y = self.y - 24 - te
    end
    -- one of several values, from a dropdown. choices = { { value, label }, ... }
    -- (or a function returning that); get/set: optional, else the setting
    function col:Choice(label, group, key, choices, get, set)
        if Skipped(group, key) then return end
        if not get then get, set = Setting(group, key) end
        if rows then
            local box = CreateDropdown(parent, 220, get, set, choices)
            local _, h, hover = RowLabel(box, label)
            box:SetPoint("LEFT", parent, "TOPLEFT", ctrlX, self.y - h / 2)
            if group and key then Mark(parent, group, key, x, self.y, width, h) end
            Made(box, label, Index(label, self.y, h), group, key, hover)
            self.y = self.y - h
            return
        end
        if group and key then Mark(parent, group, key, x, self.y, width, 26) end
        local box = CreateDropdown(parent, 160, get, set, choices)
        box:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width - 12, self.y)
        -- (the label belongs to the box, so it greys out with it)
        local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        Ink(parent, text)
        text:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, self.y - 5)
        text:SetText(label)
        Made(box, label, Index(label, self.y, 26 + te), group, key)  -- (a reset skips what has no default)
        self.y = self.y - 28 - te
    end
    -- A text part (Quest log text) in one row: its font, its size and an
    -- outline box. Settings <group>.<prefix>Font / Size / Outline; the outline
    -- box also greys out while outlineOk() is false.
    function col:TextPart(label, group, prefix, outlineOk)
        local fk, sk, ok = prefix .. "Font", prefix .. "Size", prefix .. "Outline"
        if Skipped(group, fk) then
            table.insert(parent.bfiKeys, { group, sk })
            table.insert(parent.bfiKeys, { group, ok })
            return
        end
        local fget, fset = Setting(group, fk)
        local font = CreateDropdown(parent, 150, fget, fset, ns.FontChoices)
        local _, h, hover = RowLabel(font, label)
        font:SetPoint("LEFT", parent, "TOPLEFT", ctrlX, self.y - h / 2)
        local sget, sset = Setting(group, sk)
        local size = CreateDropdown(parent, 56, sget, sset, TEXT_SIZES)
        size:SetPoint("LEFT", font, "RIGHT", 6, 0)
        local oget, oset = Setting(group, ok)
        local out = CreateCheck(parent, "Outline", oget, oset)
        out:SetPoint("LEFT", size, "RIGHT", 8, 0)
        Mark(parent, group, fk, x, self.y, width, h)
        Made(font, label, Index(label, self.y, h), group, fk, hover)
        table.insert(parent.bfiKeys, { group, sk })
        table.insert(parent.bfiKeys, { group, ok })
        local d = dep
        size.bfiDep = d
        out.bfiDep = (d or outlineOk) and function()
            return (not d or d()) and (not outlineOk or outlineOk())
        end or nil
        self.y = self.y - h
    end
    -- a line of text that keeps itself up to date: fn() returns it
    function col:Live(fn)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", x + 4, self.y - 2)
        fs:SetWidth(width - 14)
        fs:SetJustifyH("LEFT")
        Ink(parent, fs, INK_HEAD)
        local holder = CreateFrame("Frame", nil, parent)
        local t = 0
        holder:SetScript("OnUpdate", function(_, dt)
            t = t + dt
            if t < 0.5 then return end
            t = 0
            fs:SetText(fn() or "")
        end)
        fs:SetText(fn() or "")
        self.y = self.y - 20 - te
    end
    -- A box of what's true right now: rows of { label, value }, each text or a function, the
    -- values in gold, kept up to date as Live's. title, note: soft text above and below them.
    function col:StatusBox(title, rows, note)
        local LABEL_W = 150
        local inner = width - 14
        local box = CreateFrame("Frame", nil, parent)
        box:SetPoint("TOPLEFT", x + 4, self.y - 2)
        box:SetWidth(inner)
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.35)
        for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                                { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local edge = box:CreateTexture(nil, "BORDER")
            edge:SetColorTexture(0.36, 0.29, 0.18, 0.8)
            edge:SetPoint(side[1])
            edge:SetPoint(side[2])
            if i <= 2 then edge:SetHeight(1) else edge:SetWidth(1) end
        end
        local y = -6
        local function Text(of) return type(of) == "function" and of() or of or "" end
        local function Line(text, colour, left, w)
            local fs = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", left, y)
            fs:SetWidth(w)
            fs:SetJustifyH("LEFT")
            Ink(parent, fs, colour)
            fs:SetText(text)
            return fs
        end
        if title then
            Line(title, INK_SOFT, 8, inner - 16)
            y = y - 20
        end
        local live = {}
        for _, row in ipairs(rows) do
            live[#live + 1] = { Line(Text(row[1]), INK_SOFT, 8, LABEL_W), row[1] }
            live[#live + 1] = { Line(Text(row[2]), INK, 8 + LABEL_W, inner - LABEL_W - 16), row[2] }
            y = y - 20
        end
        if note then
            local fs = Line(note, INK_SOFT, 8, inner - 16)
            y = y - fs:GetStringHeight() - 4
        end
        box:SetHeight(4 - y)
        local t = 0
        box:SetScript("OnUpdate", function(_, dt)
            t = t + dt
            if t < 0.5 then return end
            t = 0
            for _, l in ipairs(live) do l[1]:SetText(Text(l[2])) end
        end)
        Index(title or "Showing now", self.y, 8 - y)
        self.y = self.y + y - 14
    end
    -- a colour, stored as { r, g, b }: a swatch to click, then the game's picker
    function col:Color(label, group, key)
        if Skipped(group, key) then return end
        local get, set = Setting(group, key)
        local sw = CreateFrame("Button", nil, parent, "BackdropTemplate")
        sw:SetSize(rows and 26 or 22, rows and 20 or 18)
        sw:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
        sw:SetBackdropBorderColor(0.6, 0.6, 0.6)
        local fill = sw:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", -3, 3)
        sw:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        local h, hover = 24 + te, nil
        if rows then
            local _, rh, rhover = RowLabel(sw, label)
            h, hover = rh, rhover
            sw:SetPoint("LEFT", parent, "TOPLEFT", ctrlX, self.y - h / 2)
        else
            sw:SetPoint("TOPLEFT", x + 4, self.y - 3)
            local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            Ink(parent, text)
            text:SetPoint("LEFT", sw, "RIGHT", 6, 0)
            text:SetText(label)
        end
        sw.Refresh = function()
            local c = get() or { 1, 1, 1 }
            fill:SetColorTexture(c[1], c[2], c[3])
        end
        sw:SetScript("OnClick", function()
            local c = get() or { 1, 1, 1 }
            OpenColorPicker(c[1], c[2], c[3], function(r, g, b)
                set({ r, g, b })
                sw.Refresh()
            end)
        end)
        controls[#controls + 1] = sw
        Mark(parent, group, key, x, self.y, width, h)
        Made(sw, label, Index(label, self.y, h), group, key, hover)
        self.y = self.y - (rows and h or 26 + te)
    end
    -- a key binding row: what it does, and the key (see CreateKeyButton)
    function col:KeyBind(label, command)
        local b = CreateKeyButton(parent, command)
        if rows then
            local _, h = RowLabel(b, label)
            b:SetPoint("LEFT", parent, "TOPLEFT", ctrlX, self.y - h / 2)
            Index(label, self.y, h)
            self.y = self.y - h
            return
        end
        local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        Ink(parent, text)
        text:SetPoint("TOPLEFT", x + 4, self.y - 5)
        text:SetWidth(width - 150)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        text:SetText(label)
        b:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width - 12, self.y)
        Index(label, self.y, 24 + te)
        self.y = self.y - 26 - te
    end
    function col:Button(label, onClick)
        if Skipped() then return end
        local b = RedButton(parent)
        b:SetPoint("TOPLEFT", x + 4, self.y - 2)
        b:SetText(label)
        -- as wide as its words (with room for the button's ends), within the column
        local fs = b:GetFontString()
        local w = fs and (fs:GetStringWidth() + 28) or 180
        b:SetSize(math.max(120, math.min(w, width - 20)), 22)
        b:SetScript("OnClick", onClick)
        Made(b, label, Index(label, self.y, 28))  -- (a Tip after it goes on it)
        self.y = self.y - 30
    end
    -- A list to put in order, in a sunk frame: drag a row to move it, or click
    -- the arrows that show on it while the mouse is there. items[id] =
    -- { label, icon }; get() the ids in order, set(ids) a new order; on(id)
    -- false greys a row (it keeps its place). group/key: for the page's reset.
    function col:OrderList(label, items, get, set, on, group, key)
        if Skipped(group, key) then return end
        local ROW = 20 + te
        local count = #get()
        local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        box:SetPoint("TOPLEFT", x + 2, self.y - 2)
        box:SetSize(width - 14, count * ROW + 8)
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                          edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                          insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        box:SetBackdropColor(0, 0, 0, 0.35)
        box:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.8)
        local rows, dragId = {}, nil
        local function Move(id, to)
            local order = get()
            for i, v in ipairs(order) do
                if v == id then table.remove(order, i) break end
            end
            table.insert(order, math.max(1, math.min(to, #order + 1)), id)
            set(order)
            box.Refresh()
        end
        box.Refresh = function()
            local order = get()
            for i, row in ipairs(rows) do
                local id = order[i]
                local it = id and items[id]
                row.id = id
                row:SetShown(it ~= nil)
                if it then
                    row.text:SetText(it[1])
                    if row.iconPath ~= it[2] then
                        row.iconPath = it[2]
                        if not ns.SetIconArt(row, row.icon, it[2]) and it[2]:find("\\Icons\\", 1, true) then
                            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        end
                    end
                    local lit = not on or on(id)
                    row.icon:SetDesaturated(not lit)
                    row.icon:SetAlpha(lit and 1 or 0.5)
                    row.text:SetAlpha(lit and 1 or 0.5)
                    row.lit:SetShown(id == dragId)
                    row.up:SetEnabled(i > 1)
                    row.down:SetEnabled(i < #order)
                end
            end
        end
        -- while dragging: the row under the cursor takes the dragged one's place
        local function Follow()
            local _, cy = GetCursorPosition()
            cy = cy / box:GetEffectiveScale()
            for i, row in ipairs(rows) do
                if row:IsShown() and cy <= row:GetTop() and cy > row:GetBottom() then
                    if row.id ~= dragId then Move(dragId, i) end
                    return
                end
            end
        end
        local function Arrows(row)
            local show = row:IsMouseOver() and not dragId
            row.up:SetShown(show)
            row.down:SetShown(show)
        end
        for i = 1, count do
            local row = CreateFrame("Button", nil, box)
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW)
            row:SetPoint("RIGHT", box, "RIGHT", -4, 0)
            row:SetHeight(ROW)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.lit = row:CreateTexture(nil, "BACKGROUND")
            row.lit:SetAllPoints()
            row.lit:SetColorTexture(1, 0.82, 0, 0.3)
            row.lit:Hide()
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW - 4, ROW - 4)
            row.icon:SetPoint("LEFT", 4, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            Ink(parent, row.text)
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -40, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            for _, dir in ipairs({ "up", "down" }) do
                local a = CreateFrame("Button", nil, row)
                a:SetSize(16, 16)
                local art = dir == "up" and "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-" or "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-"
                a:SetNormalTexture(art .. "Up")
                a:SetPushedTexture(art .. "Down")
                a:SetDisabledTexture(art .. "Disabled")
                a:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
                a:SetPoint("RIGHT", row, "RIGHT", dir == "up" and -18 or -2, 0)
                a:SetScript("OnClick", function()
                    local id = row.id
                    Move(id, i + (dir == "up" and -1 or 1))
                    -- (the arrows stay under the mouse: on the row it moved to)
                    for _, r in ipairs(rows) do Arrows(r) end
                end)
                a:SetScript("OnLeave", function() Arrows(row) end)
                a:Hide()
                row[dir] = a
            end
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", function()
                dragId = row.id
                Arrows(row)
                box:SetScript("OnUpdate", Follow)
                box.Refresh()
            end)
            row:SetScript("OnDragStop", function()
                dragId = nil
                box:SetScript("OnUpdate", nil)
                box.Refresh()
                for _, r in ipairs(rows) do Arrows(r) end
            end)
            row:SetScript("OnEnter", function() Arrows(row) end)
            row:SetScript("OnLeave", function() Arrows(row) end)
            rows[i] = row
        end
        controls[#controls + 1] = box
        box.Refresh()
        local h = count * ROW + 12
        Mark(parent, group, key, x, self.y, width, h)
        Made(box, label, Index(label, self.y, h), group, key)
        self.y = self.y - h
    end
    -- a wrapped line of small text (warnings, hints)
    function col:Note(text, r, g, b, indent)
        if adv and not advancedShown then return end  -- (not counted: not a setting)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", x + 4 + (indent or 0), self.y - 2)
        fs:SetWidth(width - 14 - (indent or 0))
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(r or 0.75, g or 0.75, b or 0.75)
        if not r then Ink(parent, fs, INK_SOFT) end  -- (warnings keep their colour)
        fs:SetText(text)
        Index(text, self.y, fs:GetStringHeight() + 6)
        self.y = self.y - fs:GetStringHeight() - 8
    end
    -- a note that stands out: gold and a size up from the small grey notes
    function col:Strong(text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", x + 4, self.y - 2)
        fs:SetWidth(width - 14)
        fs:SetJustifyH("LEFT")
        Ink(parent, fs)
        fs:SetText(text)
        Index(text, self.y, fs:GetStringHeight() + 6)
        self.y = self.y - fs:GetStringHeight() - 8
    end
    return col
end

-- Which addon a feature reads from, and whether it's here
local ADDON_PRESENT = {
    QuestieDB = function() return ns.QDB and ns.QDB() ~= nil end,
    RareScanner = function() return RareScannerDataProviderMixin ~= nil end,
    GatherMate2 = function() return _G.GatherMate2 ~= nil end,
    TomTom = function() return TomTom ~= nil end,
    Questie = function() return ns.QuestieArt and ns.QuestieArt() end,
}
function ns.AddonPresent(name)
    local f = ADDON_PRESENT[name]
    return not f or f()
end

-- A section heading for something another addon provides: "Name (QuestieDB)",
-- plus a warning when that addon isn't installed
local function Needs(title, addon)
    if not title:find(addon, 1, true) then title = title .. " (" .. addon .. ")" end
    if ns.AddonPresent(addon) then return title end
    return title .. "  |cffff6a4dneeds " .. addon .. "|r"
end

-- The map border's and the header's looks, for Start here and Header & borders
local BORDER_STYLES = {
    { "game", "The game's own" }, { "dialog", "Classic dialog" }, { "gold", "Gold" },
    { "tooltip", "Tooltip" }, { "wood", "Wood" }, { "line", "Thin line" }, { "none", "None" },
}
-- Wood and Gold are trimmed from every border list (the user, 2026-11-15: "Gold is just classic dialog with
-- a tint"). Gold is still drawn for a player who has it saved, and listed for that player alone, so their
-- box is not blank. Wood is gone for everyone: saved ones become Classic dialog (ns.NoWood).
local function Trimmed(list, saved)
    local out = {}
    for _, row in ipairs(list) do
        if row[1] ~= "wood" and (row[1] ~= "gold" or saved == "gold") then out[#out + 1] = row end
    end
    return out
end
local HEADER_STYLES = {
    { "plate", "Classic plate" }, { "tan", "Tan leather" }, { "stone", "Stone" },
    { "parchment", "Parchment" }, { "tooltip", "Dark" }, { "text", "Text only" },
}

-- The Style row of the map's border or of the header: where Frames.lua is in the build, its frame sets are more
-- styles in the same list (ns.FrameStyle: the engraver's corners, the silver, the gold).
local function StyleChoice(col, label, part, group, key, list)
    if not ns.FrameStyle then return col:Choice(label, group, key, list) end
    local rows, get, set = ns.FrameStyle(part, list, Setting(group, key))
    col:Choice(label, group, key, rows, get, set)
end

-- the map's role: a window, clear view, or over the minimap
local function MapRole()
    return ns.db.dock.on and "dock" or ns.db.clearView.on and "clear" or "window"
end
local function SetMapRole(v)
    for _, gk in ipairs({ { "dock", v == "dock" }, { "clearView", v == "clear" } }) do
        if ns.db[gk[1]].on ~= gk[2] then
            ns.db[gk[1]].on = gk[2]
            ns.OnSettingChanged(gk[1], "on")
        end
    end
end

ns.MapRole, ns.SetMapRole = MapRole, SetMapRole  -- (the welcome page: Welcome.lua)

-- Pages -----------------------------------------------------------------

local CONTENT_W = 640
local HALF = CONTENT_W / 2

ns.PanelColumn, ns.RedButton = Column, RedButton  -- (the welcome page: Welcome.lua)

local PAGES = {}

-- the preset picked on Start here (its changes listed), and what the last use said
local presetPick, presetDone

-- (summary: a page of shortcuts to settings that live on other pages, so a
-- toggle button's right-click goes past it, to the setting's own page)
-- The first page: a whole setup to start from (Setups.lua's presets), then the
-- choices that matter most, a row each, > to its page; credits folded at the end.
PAGES[#PAGES + 1] = { key = "overview", label = "Start here", summary = true, build = function(p)
    local w = Column(p, 0, 0, CONTENT_W)
    w:Note("A preset sets up the whole map in one go. Anything can be changed afterwards, here or on the other pages.")

    -- the presets as cards, two a row; the one picked lit gold
    w:Header("Presets")
    local left, avail = w:Left(), ROW_W - w:Left()
    local cw = (avail - 8) / 2
    -- the cards: your own presets, then the built-in ones (Setups.lua)
    local presets = {}
    local icons = {}
    for _, pr in ipairs(ns.PRESETS or {}) do icons[pr.id] = pr.icon end
    for _, my in ipairs(ns.MyPresets and ns.MyPresets() or {}) do
        presets[#presets + 1] = { id = my.id, name = my.name, mine = true,
            icon = icons[my.base] or "Interface\\Icons\\INV_Misc_Note_01",
            who = "Your own preset" .. (icons[my.base] and (", made from " .. ns.PresetName(my.base)) or "")
                .. ". Applying it brings back the whole setup. Delete it on the Your presets page." }
    end
    for _, pr in ipairs(ns.PRESETS or {}) do presets[#presets + 1] = pr end

    -- which card is current: the preset last applied (its name "(altered)" once
    -- a row differs), or, with none applied, one your settings match
    local base = ns.db.presetBase
    local function Current(id)
        if id == base then return "current" end
        if not base and #ns.PresetChanges(id) == 0 then return "current" end
    end
    local altered = base and #ns.PresetChanges(base) > 0
    if not presetPick then presetPick = base end
    local rowTop, rowH, lastCard = w.y, 0, nil
    for i, pr in ipairs(presets) do
        local col = (i - 1) % 2
        if col == 0 and i > 1 then
            rowTop = rowTop - rowH - 8
            rowH = 0
        end
        local card = CreateFrame("Button", nil, p, "BackdropTemplate")
        card:SetPoint("TOPLEFT", left + col * (cw + 8), rowTop)
        card:SetWidth(cw)
        card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                           edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                           insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        local picked = pr.id == presetPick
        card:SetBackdropColor(picked and 0.17 or 0.07, picked and 0.13 or 0.06, picked and 0.05 or 0.05, 0.9)
        if picked then card:SetBackdropBorderColor(1, 0.82, 0, 1) else card:SetBackdropBorderColor(0.4, 0.37, 0.33, 0.9) end
        card:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(36, 36)
        icon:SetPoint("TOPLEFT", 9, -9)
        icon:SetTexture(pr.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- (the name gets the card's width but for the "current" tag, and wraps
        -- rather than being cut off)
        local state, tagW = Current(pr.id), 0
        if state then
            local now = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            Ink(p, now, { 0.3, 0.87, 0.3 })
            now:SetPoint("TOPRIGHT", -9, -10)
            now:SetText(state)
            tagW = now:GetStringWidth() + 8
        end
        local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        Ink(p, name)
        name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, 0)
        name:SetWidth(cw - 64 - tagW)
        name:SetJustifyH("LEFT")
        name:SetText(pr.name .. ((pr.id == base and altered) and " |cffff9933(altered)|r" or ""))
        local who = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        Ink(p, who, INK_SOFT)
        who:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
        who:SetWidth(cw - 64)
        who:SetJustifyH("LEFT")
        who:SetText(pr.who)
        local h = math.max(54, 9 + name:GetStringHeight() + 3 + who:GetStringHeight() + 10)
        -- Apply on the picked card itself: with eight cards the box below, with what it would change and its
        -- own Apply, lies under the fold, and a click on a card seemed to do nothing. (First tried: scrolling
        -- the box into view. "Apply on the card", the user 2026-11-15.) Not on the card you are on: its
        -- Restore and save row are in the box.
        if picked and pr.id ~= base and #ns.PresetChanges(pr.id) > 0 then
            local go = RedButton(card)
            go:SetText("Apply")
            go:SetSize(90, 20)
            go:SetPoint("BOTTOMRIGHT", -8, 7)
            go:SetScript("OnClick", function()
                ns.ApplyPreset(pr.id)
                presetDone = "Applied."
                ns.RebuildOptionsPages()
            end)
            h = h + 24
        end
        card:SetHeight(h)
        rowH = math.max(rowH, h)
        card:SetScript("OnClick", function()
            presetPick, presetDone = pr.id, nil
            ns.RebuildOptionsPages()
        end)
        -- (cards of a row as tall as the tallest)
        if col == 1 then
            lastCard:SetHeight(rowH)
            card:SetHeight(rowH)
        end
        lastCard = card
    end
    w.y = rowTop - rowH - 10

    -- the picked card: what applying it would change, and the button; or, on the
    -- one you've altered, what you changed, Restore, and a name to keep it under
    local box = CreateFrame("Frame", nil, p, "BackdropTemplate")
    box:SetPoint("TOPLEFT", left, w.y)
    box:SetWidth(avail)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    box:SetBackdropColor(0, 0, 0, 0.35)
    box:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.8)
    local title = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Ink(p, title, INK_HEAD)
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetWidth(avail - 24)
    title:SetJustifyH("LEFT")
    local pick
    for _, pr in ipairs(presets) do
        if pr.id == presetPick then pick = pr end
    end
    local changes = pick and ns.PresetChanges(pick.id) or {}
    local onIt = pick and pick.id == base  -- (the one you're on, altered or not)
    local inner = 10
    if not pick then
        title:SetText("Click a preset to see what it would change.")
    elseif #changes == 0 then
        title:SetText("Your settings match " .. pick.name .. ".")
    elseif onIt then
        title:SetText("You've changed " .. #changes .. (#changes == 1 and " setting" or " settings")
            .. " from " .. pick.name .. ". Restore would put back:")
    else
        title:SetText(pick.name .. " would change:")
    end
    inner = inner + title:GetStringHeight() + 6
    local function Done(text)
        presetDone = text
        ns.RebuildOptionsPages()
    end
    if #changes > 0 then
        -- two columns of "Label: now to then"
        local half = math.ceil(#changes / 2)
        local cols = {}
        for c = 1, 2 do
            local lines = {}
            for j = (c - 1) * half + 1, math.min(#changes, c * half) do
                local ch = changes[j]
                lines[#lines + 1] = "|cffffffff" .. ch[1] .. ":|r " .. (ch.text or (ch[2] .. " to |cffffd100" .. ch[3] .. "|r"))
            end
            local fs = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            Ink(p, fs, INK_SOFT)
            fs:SetPoint("TOPLEFT", 12 + (c - 1) * (avail - 24) / 2, -inner)
            fs:SetWidth((avail - 24) / 2 - 8)
            fs:SetJustifyH("LEFT")
            fs:SetSpacing(2)
            fs:SetText(table.concat(lines, "\n"))
            cols[c] = fs
            -- (the minor differences, by name, in a tooltip over their column)
            for j = (c - 1) * half + 1, math.min(#changes, c * half) do
                local list = changes[j].list
                if list then
                    local hov = CreateFrame("Frame", nil, box)
                    hov:SetAllPoints(fs)
                    hov:EnableMouse(true)
                    hov:SetScript("OnEnter", function(self)
                        local function Say(v)
                            if v == nil then return "not set" end
                            if type(v) == "boolean" then return v and "on" or "off" end
                            if type(v) == "number" then return tostring(math.floor(v * 1000 + 0.5) / 1000) end
                            return type(v) == "table" and "(a list)" or tostring(v)
                        end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:AddLine("Minor setting differences")
                        for _, d in ipairs(list) do
                            GameTooltip:AddDoubleLine(d[1], Say(d[3]) .. "  |cff999999(preset: " .. Say(d[2]) .. ")|r",
                                0.8, 0.8, 0.8, 1, 1, 1)
                        end
                        GameTooltip:AddLine("Restore puts back the preset's.", 0.5, 0.5, 0.5)
                        GameTooltip:Show()
                    end)
                    hov:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
            end
        end
        inner = inner + math.max(cols[1]:GetStringHeight(), cols[2]:GetStringHeight()) + 10
        local use = RedButton(box)
        use:SetText(onIt and "Restore" or "Apply")
        use:SetSize(onIt and 100 or 140, 22)
        use:SetPoint("TOPLEFT", 10, -inner)
        use:SetScript("OnClick", function()
            if onIt then
                ns.RestorePreset(pick.id)
                Done("Restored " .. pick.name .. ".")
                return
            end
            ns.ApplyPreset(pick.id)
            Done("Applied.")
        end)
        -- (on the altered card: a name, and save yours as a new preset, beside Restore)
        local right = use
        if onIt then
            local nameBox = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
            nameBox:SetSize(190, 20)
            nameBox:SetPoint("LEFT", use, "RIGHT", 16, 0)
            nameBox:SetAutoFocus(false)
            nameBox:SetText(pick.mine and pick.name or (pick.name .. " (altered)"))
            nameBox:SetCursorPosition(0)
            local save = RedButton(box)
            -- (you stay on what you saved: it used to put the old preset's rows back over your settings. "should
            -- not change you to the restored preset, but instead keep your current", the user 2026-11-15. The
            -- old preset's card is itself again either way: you are on your own now.)
            save:SetText("Save as your own preset")
            save:SetSize((save:GetFontString():GetStringWidth() or 160) + 30, 22)
            save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
            save:SetScript("OnClick", function()
                local n = strtrim(nameBox:GetText() or "")
                if ns.SavePresetAs(n) then
                    presetPick = "my:" .. n
                    Done("Saved \"" .. n .. "\" as a preset of your own, and you are on it. " .. pick.name .. " is as it was.")
                end
            end)
            save:SetScript("OnEnter", function()
                GameTooltip:SetOwner(save, "ANCHOR_RIGHT")
                GameTooltip:SetText("Save as your own preset", 1, 0.82, 0)
                GameTooltip:AddLine("Saves your current settings as a new preset under the name beside it. Nothing on your map changes. " .. pick.name .. " stays as it is.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            save:SetScript("OnLeave", function() GameTooltip:Hide() end)
            nameBox:SetScript("OnEnterPressed", function() save:Click() end)
            nameBox:SetScript("OnEscapePressed", function() nameBox:ClearFocus() end)
            inner = inner + 22 + 8
            right = nil
        end
        local after = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        Ink(p, after, INK_SOFT)
        if right then
            after:SetPoint("LEFT", use, "RIGHT", 10, 0)
            after:SetWidth(avail - 40 - use:GetWidth())
        else
            after:SetPoint("TOPLEFT", 12, -inner)
            after:SetWidth(avail - 24)
        end
        after:SetJustifyH("LEFT")
        local note = ""
        if onIt then
            note = "Only these rows go back."
        elseif pick.mine then
            note = "The whole setup comes back, positions and sizes too."
        elseif not base then
            note = "Your settings aren't saved: keep them on the Your presets page first if you want them back."
        end
        if altered and not onIt then
            note = note .. (note ~= "" and " " or "") .. "Your changes to " .. ns.PresetName(base) .. " aren't kept: save them on its card first."
        end
        if onIt then note = "Restore puts back only these rows. Save as your own preset keeps your changes as a new preset." end
        after:SetText(note)
        inner = inner + (right and math.max(22, after:GetStringHeight()) or after:GetStringHeight()) + 10
    end
    -- (one of your own: a way to take its card away here, where the cards pile up. Two clicks.)
    if pick and pick.mine then
        local del = RedButton(box)
        del:SetText("Delete this preset")
        del:SetSize((del:GetFontString():GetStringWidth() or 120) + 30, 22)
        del:SetPoint("TOPLEFT", 10, -inner)
        local sure
        del:SetScript("OnClick", function()
            if not sure then
                sure = true
                del:SetText("Click again to delete")
                del:SetWidth((del:GetFontString():GetStringWidth() or 140) + 30)
                return
            end
            ns.DeleteSetup(pick.name)
            if ns.db.presetBase == pick.id then ns.db.presetBase = nil end
            presetPick = nil
            Done("Deleted \"" .. pick.name .. "\". Your settings stay as they are.")
        end)
        inner = inner + 22 + 8
    end
    if presetDone then
        local done = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        Ink(p, done, { 0.3, 0.87, 0.3 })
        done:SetPoint("TOPLEFT", 12, -inner)
        done:SetWidth(avail - 24)
        done:SetJustifyH("LEFT")
        done:SetText(presetDone)
        inner = inner + done:GetStringHeight() + 8
    end
    box:SetHeight(inner + 4)
    -- (a change made below, or anywhere, can change the list or a card's state:
    -- built afresh then)
    local function State()
        local t = { tostring(ns.db.presetBase), pick and #ns.PresetChanges(pick.id) or 0 }
        for _, pr in ipairs(presets) do t[#t + 1] = Current(pr.id) or "-" end
        return table.concat(t, "|")
    end
    local built = State()
    box.Refresh = function()
        local now = State()
        if now ~= built then
            built = now
            presetDone = nil
            ns.RebuildOptionsPages()
        end
    end
    controls[#controls + 1] = box
    w.y = w.y - inner - 12
    w:Note("Presets leave your quest pins, objectives and quest ground as you have them.")

    -- then everything Waymark can do, a line each with its switch and > to its page: what is off shows too,
    -- so a feature nobody turned on still says it exists (the settings pass, 2026-11-14)
    w:Header("What Waymark can do")
    -- (page: a page's key, or a function giving one when asked)
    local function Go(top, page)
        local function Page() if type(page) == "function" then return page() end return page end
        local go = RedButton(p)
        go:SetSize(26, 20)
        go:SetPoint("RIGHT", p, "TOPLEFT", ROW_W - 2, (top + w.y) / 2)
        go:SetText(">")
        go:SetScript("OnClick", function() ns.OpenOptionsPage(Page()) end)
        go:SetScript("OnEnter", function()
            GameTooltip:SetOwner(go, "ANCHOR_RIGHT")
            GameTooltip:SetText("More settings")
            GameTooltip:Show()
            ns.GlowNavPage(Page(), true)
        end)
        go:SetScript("OnLeave", function()
            GameTooltip:Hide()
            ns.GlowNavPage(Page(), false)
        end)
    end

    -- the map's role, its three choices side by side (clear view always in reach)
    -- With pictures (Data\RoleShots.lua, made by tools\role_shots.py from /wmshots): one above each choice,
    -- a real corner of a screen with the map in that place. "three screenshots here? one for each mode, would
    -- show alot", the user 2026-11-15. Without them the row is the three buttons alone.
    local top = w.y
    local PIC_W, PIC_H = 176, 132
    local pics = ns.ROLE_SHOTS
    local picOff = pics and (PIC_H + 10 + 20) or 0   -- (and a line for the label, above them)
    local roleH = 30 + picOff
    local label = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Ink(p, label)
    if pics then label:SetPoint("LEFT", p, "TOPLEFT", left, top - 10) else label:SetPoint("LEFT", p, "TOPLEFT", left, top - 15) end
    label:SetText("The map")
    local roleTip = "Window: a map you can move. Clear view: no frame, just the map over the world. Minimap: the map replaces your minimap."
    local hover = CreateFrame("Frame", nil, p)
    hover:SetAllPoints(label)
    hover:EnableMouse(true)
    local roles, prev = {}, nil
    for _, r in ipairs({ { "window", "Window", "window" }, { "clear", "Clear view", "clearview" },
                         { "dock", "Minimap", "minimap" } }) do
        local b = RedButton(p)
        b:SetText(r[2])
        b:SetSize(pics and PIC_W or ((b:GetFontString():GetStringWidth() or 60) + 30), 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", pics and 6 or 4, 0) else
            -- (with pictures: from the page's left edge, the label on a line above, not at the rows' control
            -- column, where the third picture ran off the page's right edge. The user's screenshot, 2026-11-15)
            b:SetPoint("LEFT", p, "TOPLEFT", pics and (left + 2) or ROW_LABEL, top - picOff - 15)
        end
        b:SetScript("OnClick", function()
            SetMapRole(r[1])
            ns.RefreshControls()
        end)
        b.role = r[1]
        local cut = pics and pics[r[1]]
        if cut then
            local pic = CreateFrame("Button", nil, p)
            pic:SetSize(PIC_W, PIC_H)
            pic:SetPoint("BOTTOM", b, "TOP", 0, 6)
            local tex = pic:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", 2, -2)
            tex:SetPoint("BOTTOMRIGHT", -2, 2)
            tex:SetTexture(ns.MEDIA .. "Roles\\" .. cut.file)
            tex:SetTexCoord(cut[1], cut[2], cut[3], cut[4])
            b.edge = pic:CreateTexture(nil, "BACKGROUND")
            b.edge:SetAllPoints()
            pic:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
            pic:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.12)
            pic:SetScript("OnClick", function() b:Click() end)
        end
        roles[#roles + 1] = b
        prev = b
    end
    for _, on in ipairs({ hover, unpack(roles) }) do
        on:HookScript("OnEnter", function()
            GameTooltip:SetOwner(on, "ANCHOR_RIGHT")
            GameTooltip:SetText("The map", 1, 0.82, 0)
            GameTooltip:AddLine(roleTip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        on:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local roleRow = CreateFrame("Frame", nil, p)
    roleRow.Refresh = function()
        local now = MapRole()
        for _, b in ipairs(roles) do
            if b.role == now then b:LockHighlight() else b:UnlockHighlight() end
            -- (the picture of the place the map is in: a gold edge; the others a dim one)
            if b.edge then
                if b.role == now then b.edge:SetColorTexture(1, 0.82, 0, 1) else b.edge:SetColorTexture(0.4, 0.37, 0.33, 0.9) end
            end
        end
    end
    controls[#controls + 1] = roleRow
    roleRow.Refresh()
    w.y = top - roleH
    -- (the arrow: the settings of the place the map is in now. It was fixed when the page was built, and for
    -- a window it went to Clear view. "Arrow takes me to the one i selected. inteded?", the user 2026-11-15)
    Go(top, function()
        local now = MapRole()
        return now == "dock" and "minimap" or now == "clear" and "clearview" or "window"
    end)

    local function Feature(name, what, group, key, page, addon)
        w:Feature({ name, what, "", group, key, page, addon })
    end
    w:Header("On your map")
    if ns.ReliefSetting then Feature("The lie of the land", "Hills, valleys and shadows from the game's real terrain.", "relief", "on", "look") end
    if ns.PencilSetting then Feature("Land you've seen, in pencil", "Land you've seen is sketched in pencil. It gets its colour once you walk there.", "pencil", "on", "look") end
    Feature("Townsfolk", "Trainers, vendors, innkeepers, flight masters.", "townsfolk", "shown", "people")
    Feature("Rares and chests", "Rares, rare elites and treasure chests.", "wilds", "shown", "rares")
    if not ns.GatherPulled() then Feature("Herbs, ore and fishing spots", "Small ink marks, on the map and the minimap.", "gather", "shown", "rares") end
    if ns.SetupTransports then Feature("Boats & zeppelins", "Their ways across the sea, drawn on the continent.", "transports", "shown", "traversal") end
    Feature("Dungeon entrances", "Click one for the dungeon's map.", "dungeons", "shown", "dungeon")
    -- (the clock is on the map: it sat under "Beside the map" with the book's button, "strange mix", the
    -- user 2026-11-15)
    Feature("Clock", "An engraved clock on the map.", "clock", "shown", "clock")

    -- (each way of questing a line of its own, not one choice of a few mixes: the giver's words and the
    -- objectives on the map do the same job two ways, and a player may want either, both or neither)
    w:Header("Quests")
    w:Feature({ "Quest givers", "Where you pick quests up and hand them in.", "", "questie", "shown", "quests",
        get = function() return ns.QuestGiversOn() end, set = function(v) ns.SetQuestGivers(v) ns.RefreshControls() end })
    if ns.ToldNow then Feature("As told", "A small panel with what the quest giver said. The map marks only the places they named.", "told", "on", "told") end
    w:Feature({ "Where your quest mobs are", "Objectives marked on the map.", "", "spots", "shown", "quests",
        get = function() return ns.ObjectivesOn() end, set = function(v) ns.SetObjectives(v) ns.RefreshControls() end })
    Feature("Quest tracker", "This zone's quests, nearest first, in place of the game's.", "tracker", "shown", "tracker")
    Feature("Quest log", "A quest's page in a window of its own.", "questlog", "shown", "questlog")
    if ns.ToldNow then w:Note("As told and quest objectives are two ways to find your quest. As told gives you the giver's words and pencils in the places they named. Objectives mark where the mobs and items are. Most players pick one.") end

    w:Header("The book", ns.ToggleIcon and ns.ToggleIcon("book"))
    -- (the welcome page's own line first, the same words in both places: the user, 2026-11-15)
    w:Note("A wanderer's dungeon notebook came with the map. It also opens from its button on the map, and from a dungeon's map.")
    w:Button("Open the book", function() if ns.ToggleNotebook then ns.ToggleNotebook() end end)

    w:Header("How it acts")
    Feature("Follows you", "The map keeps you in its middle as you move.", "mapFrame", "center", "acts")
    w:Button("Everything the map does by itself", function() ns.OpenOptionsPage("acts") end)
    w:Tip("Zooming in towns, changing shape per zone, folding, fading: one list, each with its switch.")
    w:Note("Hold the map key (Shift-M by default) to show the map only while you hold it. More keys are on the Keys page.")

    w:Header("Its frame")
    top = w.y
    StyleChoice(w, "Border", "border", "border", "style", Trimmed(BORDER_STYLES, ns.db.border.style))
    Go(top, "header")
    top = w.y
    StyleChoice(w, "Header", "header", "zoneName", "style", HEADER_STYLES)
    Go(top, "header")

    w:Button("Show the welcome page again", function()
        ns.ToggleOptions()
        if ns.ShowWelcome then ns.ShowWelcome() end
    end)

    -- folded the first time it's seen
    local ow = ns.db.optionsWindow
    if not ow.aboutFolded then
        ow.aboutFolded = true
        ow.folded["overview/About"] = true
    end
    w:Header("About")
    w:Note("Hover any setting to see what it does. Show advanced settings, at the bottom, adds the fine-tuning.")
    w:Note("Minimap and dungeon map data: OpenMap (MIT licence, see LICENSES). QuestieDB, RareScanner and GatherMate2 data are read from those addons while the game runs; nothing of theirs is copied into this addon. Where Questie is installed, its quest icons are used." .. (ns.FOREVER and "" or " Gathering spots: the Waymark Nodes addon beside this one (GPL v3, from the CMaNGOS database)."))
end }

local function Percent(v) return string.format("%d%%", v * 100 + 0.5) end

-- One row, two ticks (the lie of the land's line on Performance mode). first: the row's own box, just
-- made (col.last): it gets a caption after it, and a second box with its own caption follows on the same line.
-- dep: the second is greyed while this says no.
local function TwoTicks(p, first, caption, label, get, set, tip, dep)
    local cap = first:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Ink(p, cap)
    cap:SetPoint("LEFT", first, "RIGHT", 2, 0)
    cap:SetText(caption)
    local c = CreateCheck(p, label, get, set)
    c:SetPoint("LEFT", cap, "RIGHT", 22, 0)
    c.bfiDep = dep
    c:HookScript("OnEnter", function()
        GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 0.82, 0)
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    c:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

-- Performance mode (ns.Perf, BattlefieldInfo.lua): one switch, then each thing it lightens, ticked
-- unless the player wants that one kept as it is. Their own settings elsewhere stay untouched
local PERF_ROWS = {
    { "art", "Continents: the game's own map",
      "Uses the game's own continent map, which is much lighter than Waymark's painted one." },
    { "warm", "Don't load map pictures ahead",
      "Stops Waymark loading map pictures in the background after you log in. The map may flicker the first time you open it." },
    { "detail", "No close-up detail",
      "The trees, rocks and buildings that fade in as you zoom in stay off." },
    { "ground", "Quest areas as spots",
      "Quest areas on the ground, if you have them on, show as objective spots instead." },
    { "effects", "No map effects",
      "The time of day tint, soft edges and clear view are switched off." },
    { "ticks", "Fewer map updates",
      "The map updates 4 times a second instead of 10. Pins can show up a moment late." },
}

PAGES[#PAGES + 1] = { key = "performance", label = "Performance mode", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Performance mode")
    a:Note("For handhelds and older PCs. The map runs lighter, so the game keeps its framerate. Turn it off and everything is as you had it.")
    a:CheckWith("On", function() return ns.db.perf.on end, function(v)
        ns.db.perf.on = v and true or false
        ns.OnSettingChanged("perf", "on")
    end)
    a:Note("What it makes lighter. Untick what you'd rather keep:")
    a:Requires(function() return ns.db.perf.on end)  -- (greyed while it's off)
    for _, row in ipairs(PERF_ROWS) do
        local item = row[1]
        a:CheckWith(row[2], function() return ns.db.perf.items[item] ~= false end, function(v)
            -- (false: kept as it is; nil: lightened. "(not v) and false or nil" was always nil)
            if v then ns.db.perf.items[item] = nil else ns.db.perf.items[item] = false end
            ns.OnSettingChanged("perf", item)
        end)
        a:Tip(row[3])
    end
    -- the lie of the land (while it is in the build): one line, two ticks. Off, as it comes; unticked it stays,
    -- and Steady light holds its light in one place (the user, 2026-11-14)
    if ns.ReliefSetting then
        local function Tick(item)
            return function() return ns.db.perf.items[item] ~= false end, function(v)
                if v then ns.db.perf.items[item] = nil else ns.db.perf.items[item] = false end
                ns.OnSettingChanged("perf", item)
                ns.RefreshControls()
            end
        end
        local get, set = Tick("relief")
        a:CheckWith("The lie of the land", get, set)
        a:Tip("Turns the shaded hills off. Untick Off to keep them. Steady light keeps them at a lower cost.")
        get, set = Tick("reliefHour")
        TwoTicks(p, a.last, "Off", "Steady light", get, set,
            "The light stays in the north-west instead of moving with the time of day. About half the cost.",
            function() return ns.db.perf.on and ns.db.perf.items.relief == false end)
    end
    a:Requires()
end }

PAGES[#PAGES + 1] = { key = "window", label = "Size & shape", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Size and shape")
    a:Slider("Waymark size", ns.MIN_ADDON_SCALE, ns.MAX_ADDON_SCALE, 0.05, nil, "addonScale", "%.2fx")
    a:Tip("All of Waymark bigger or smaller together: the map, tracker, quest log and book. This settings window and the game's own UI stay as they are.")
    -- (ns.db.scale, the map frame's own scale. It has been "Map scale", "Pin & text size" and "Everything on
    -- the map"; it is the map's scale, and it lives with the map's size.)
    -- Its slider is out of the settings (2026-11-15). The corner drag took over the map's size long ago, the
    -- buttons, area text and pins were each made to keep their size against it, and what was left (border,
    -- header, an attached tracker) has settings of its own: "it doesnt resize anything on or near the map",
    -- the user. The saved value stays and is still applied, so no map changes. Its floor for pins is the
    -- Layers tab's "Size of all pins".
    a:Note("Drag the map's bottom-right corner to resize it. Right-click the corner to reset: first to this zone's own shape, then to the game's default size.")
    a:Check("Changes shape per zone", "mapFrame", "autoWidth")
    a:Tip("The map changes shape to fit the zone: taller for the Barrens, wider for Duskwood. It stays about the size you set.")
    a:Requires("mapFrame", "autoWidth")
    a:Advanced(true)
    a:Slider("How much of the zone's shape", 0, 1, 0.05, "mapFrame", "shapeFollow", function(v)
        return string.format("%d%%", v * 100 + 0.5)
    end)
    a:Tip("100%: exactly the zone's shape. Lower: closer to your own shape, so the map changes less from zone to zone.")
    a:Slider("Room to grow", 0, 0.5, 0.05, "mapFrame", "shapeGrow", function(v)
        return string.format("up to %d%%", v * 100 + 0.5)
    end, "none")
    a:Tip("Lets the map grow for zones that are much taller or wider than your shape, so you see more of them.")
    a:Choice("Shapes you drag", "mapFrame", "rememberShapes", {
        { true, "Remember it for that zone" }, { false, "Forget it when you leave" },
    })
    a:Tip("Remember: a zone keeps the shape you drag it to. Forget: it goes back to its own shape when you leave.")
    a:Button("Reset shape to defaults", function() ns.ConfirmResetGroup("shape") end)
    a:Advanced()
    a:Requires()
    a:Header("Soft edges")
    a:Check("Fade the map into the world at its edges", "softEdges", "on")
    a:Tip("Hides the border. Doesn't apply on continent maps or while docked. If clear view is cutting the zone out, only when zoomed in.")
    a:Requires("softEdges", "on")
    a:Choice("Shape", "softEdges", "shape", {
        { "square", "Soft square" }, { "round", "Round corners" }, { "oval", "Oval" }, { "worn", "Worn edge" },
    })
    a:Choice("Reach", "softEdges", "reach", { { 1, "Small" }, { 2, "Medium" }, { 3, "Large" } })
    a:Check("Pins fade at the edge too", "softEdges", "pins")
    a:Tip("Off: pins stay sharp right up to the edge.")
    a:Requires()
    a:Button("Go to: The colours follow the time of day", function() ns.ShowOption("mapHour", "on") end)

    local b = Column(p, HALF, 0, HALF)
    b:Header("Placement")
    b:Check("Lock the map", "mapFrame", "locked")
    b:Tip("The map stays where it is: dragging its header (or edge) doesn't move it. Also in the header's right-click menu.")
    -- (fine-tuning since the settings pass, 2026-11-14: both are on in every preset and set once at most)
    b:Advanced(true)
    b:Requires(function() return not ns.db.mapFrame.locked end)
    b:Check("Move the map by its edge", "mapFrame", "unlocked")
    b:Tip("Drag any edge of the map to move it. Off: only its header moves it.")
    b:Requires()
    b:Check("Hide the Zone Map tab", "mapFrame", "hideTab")
    b:Tip("The game's own tab sits above the map and stops it from reaching the top of the screen.")
    b:Advanced()
    if ns.LeatrixBattleMapActive and ns.LeatrixBattleMapActive() then
        b:Note("Leatrix Maps' battlefield map options are on too. Use one or the other, or they'll fight over the map.", 1, 0.5, 0.3)
    end
end }

-- What the map does by itself, all of it on one page, each line a sentence about what you would see: so the
-- switch for "it just did that" is found by reading down one list, not by guessing a setting's name (the
-- settings pass, 2026-11-14; the user: "page A is great and I love it"). Folding, fading and click-through
-- live here; the rest are the same settings as on their own tabs, which hold their fine-tuning.
PAGES[#PAGES + 1] = { key = "acts", label = "What the map does by itself", build = function(p)
    local w = Column(p, 0, 0, CONTENT_W)
    w:Note("Everything the map does by itself. Untick what you don't want.")
    local function More(label, page)
        w:Button(label, function() ns.OpenOptionsPage(page) end)
    end

    w:Header("As you travel")
    w:Check("Follows you", "mapFrame", "center")
    w:Tip("Keeps you in the middle of the map. Dragging or zooming the map pauses this until you move again. While you look at another zone it waits until the map comes back to you: Looking at another zone, below.", "Hold Shift to pause it.")
    w:Check("Changes shape per zone", "mapFrame", "autoWidth")
    w:Tip("A tall zone like the Barrens gets a taller, narrower map, a wide one like Duskwood a wider, shorter one, at about your size. Off: the map keeps the shape you dragged it to.")
    w:Requires("townView", "enabled")
    w:Check("Zooms in on towns", "townView", "zoom")
    w:Tip("Zooms in when you enter a town and back out when you leave. Not while you've moved or zoomed the map yourself.")
    w:Requires()
    w:Check("Shows the whole city in a capital", "cityView", "zoom")
    w:Check("Shows a cave's map inside a cave", "cave", "enabled")
    if not ns.DungeonsOff then
        w:Check("Switches to the dungeon's map inside one", "dungeon", "fallback")
        w:Tip("Off: inside a dungeon the map shows the zone outside.")
    end
    More("More for towns and cities", "town")

    w:Header("Folding away")
    w:KeyBind("A glance: hold the map's own key", "TOGGLEBATTLEFIELDMINIMAP")
    w:CheckWith("A glance when you hold the map's key", function() return ns.db.collapse.glance ~= false end, function(v)
        ns.db.collapse.glance = v and true or false
        if ns.ApplyMapKey then ns.ApplyMapKey() end
    end)
    w:Tip("Off: the key only opens and closes the map. If you change this in combat, it applies when combat ends.")
    w:Note("Tap the map key (Shift-M by default) to open or close the map. Hold it to show the map only while you hold it, or to hide an open map while you hold it. Does nothing while docked.")
    w:Check("Folds in combat", "collapse", "combat")
    w:Tip("The map folds up under its header in combat and opens again after it. An attached quest tracker stays.")
    w:Check("Folds when you open a window over it", "collapse", "windows")
    w:Tip("The map folds when a window opens on top of it (loot, a quest, a vendor, your bags) and comes back when you close it.", "Not while docked over the minimap.")
    w:Check("Folded, it leaves a ribbon of the map visible", "collapse", "ribbon")
    w:Tip("When folded, a ribbon of the map stays, zoomed in on where you are.", "Not while docked over the minimap.")
    w:KeyBind("A key that folds the map", "BFI_COLLAPSE")
    w:Note("Folds the map but keeps the ribbon and an attached quest tracker. The map key closes everything.")

    w:Header("Fading and clicks")
    w:Check("Fades while you move", "fade", "moving")
    w:Tip("Flight paths don't count as moving.")
    w:Requires("fade", "moving")
    w:Slider("Opacity while moving", 0, 100, 5, "fade", "movingAlpha", "%d%%")
    w:Requires()
    w:Check("Fades in combat", "fade", "combat")
    w:Requires("fade", "combat")
    w:Slider("Opacity in combat", 0, 100, 5, "fade", "combatAlpha", "%d%%")
    w:Requires()
    w:Check("Full again on hover", "fade", "hover")
    w:Tip("Fading adds to the map's own opacity, so a see-through map gets fainter still. At 0% the map still takes clicks.")
    w:Check("Its buttons fade until you hover it", "toggles", "fadeOut")
    w:Tip("The small buttons on the map, the gear with them.")
    -- (behind the fine-tuning: the user, 2026-11-16, "Almost shouldnt be a setting at all". Ticked by
    -- accident, the map takes no clicks any more.)
    w:Advanced(true)
    w:Check("Lets your clicks through to the world", "clickThrough", "on")
    w:Tip("Clicks and the mouse wheel go through the map to the game. Not while docked.", "Hold the key below to use the map; pin tooltips still show.")
    w:Requires("clickThrough", "on")
    w:Choice("Hold to use the map", "clickThrough", "modifier", {
        { "ALT", "Alt" }, { "CTRL", "Ctrl" }, { "SHIFT", "Shift" },
    })
    w:Check("Only in combat", "clickThrough", "combat")
    w:Tip("Out of combat the map takes clicks as usual.")
    w:Requires()
    w:Advanced()

    w:Header("Looking at another zone")
    -- (said once, the rows short: "Comes back" on each row said back to what on none, and two of them
    -- wrapped. The user, 2026-11-16.)
    w:Note("The map returns to your own zone:")
    w:Requires("browse", "enabled")
    w:Check("When you close and open the map", "browse", "onReopen")
    w:Check("When you walk into a new zone", "browse", "onZone")
    w:Slider("After the mouse has been away", 0, 60, 1, "browse", "idle", "%d s", "never")
    w:Tip("Back to your own map once the mouse has been off the map this long.", "Middle-click the map: back at once.")
    w:Requires()

    w:Header("As you play")
    if ns.ReliefSetting then
        w:Check("The land's light follows the time of day", "relief", "hour")
        w:Tip("Shadows on the map follow the time of day. Off: the light stays still.")
    end
    w:Check("A gold flash where you discover an area", "explore", "flash")
    w:Check("Learns quest givers as you talk to them", "learned", "record")
    w:Tip("For quests the quest data lacks. Shared by all your characters.")
    w:Check("Learns vendors and trainers as you talk to them", "townsfolk", "record")
    w:Check("Quest progress on mob and item tooltips", "questie", "unitTips")
    w:Tip("Hover a mob or item out in the world to see your quest progress on its tooltip.")
end }

-- Clear view and the minimap replacement: modes of the window, each its own page
PAGES[#PAGES + 1] = { key = "clearview", label = "Clear view", build = function(p)
    local b = Column(p, 0, 0, HALF)
    b:Header("Clear view")
    b:Check("Clear view", "clearView", "on")
    b:Tip("Only the map over the world. No border, and the zone name and buttons show only when you hover.", "Key bindings page: Clear view.")
    b:Slider("Map opacity in clear view", 0.1, 1, 0.05, "clearView", "opacity", Percent)
    b:Tip("Used instead of the normal map opacity while clear view is on. Pins keep their own.")
    b:Advanced(true)
    -- (greyed with no border to hide: the border is switched off on Header & border; the user, 2026-11-15)
    b:Requires(function() return ns.db.border.shown and true or false end)
    b:Check("Hide the border", "clearView", "noFrame")
    b:Requires()
    b:Choice("Zone name", "clearView", "header", {
        { "hover", "On mouse-over" }, { "shown", "Shown" }, { "hidden", "Hidden" },
    })
    b:Choice("Buttons and coordinates", "clearView", "buttons", {
        { "hover", "On mouse-over" }, { "shown", "Shown" },
    })
    b:Check("Only the zone you're in", "clearView", "zoneOnly")
    b:Tip("Cuts away the neighbouring zones and the sea, so only your zone shows. Zone maps only.")
    b:Check("Cut city maps too", "clearView", "cities")
    b:Tip("A city's map cut to the city, where it has an outline.")
    b:Check("Cut dungeon maps too", "clearView", "dungeons")
    b:Tip("Cuts a dungeon map to its rooms, so you see the game around it instead of black.")
    b:Check("Whole map when big", "clearView", "bigUncut")
    b:Tip("No cutting while the map is big (the big map button or key): the whole map shows.")
    -- (the optional views made in the outline editor, CutEdit.lua: one box each)
    b:Advanced()
    -- (the optional outlines made in the outline editor, CutEdit.lua: one box each)
    local views = ns.CutViews and ns.CutViews() or {}
    if #views > 0 then
        b:Advanced(true)
        b:SubHeader("Other outlines")
        for _, v in ipairs(views) do
            b:Check(v.label, "clearView", "view_" .. v.name)
            local info = type(v.base) == "number" and C_Map.GetMapInfo(v.base)
            b:Tip("Another outline for " .. (info and info.name or "this map") .. ", shown in place of its usual one.")
        end
        b:Advanced()
    end
end }

PAGES[#PAGES + 1] = { key = "minimap", label = "Minimap replacement", build = function(p)
    local b = Column(p, 0, 0, HALF)
    b:Header("Minimap replacement")
    b:Check("Dock the map over the minimap", "dock", "on")
    b:Tip("The map replaces your minimap, square and north up, with your minimap dots on it. If you switch in combat, it changes when combat ends.")
    b:Requires("dock", "on")
    -- (no row for dock.ourGround, "Waymark's map under the minimap's blips": the user, 2026-11-16, "Should
    -- it even be an option at all?". Off was the old way, the game's minimap picture up close, and left a
    -- line of it outside the frame. The switch lives on as /waymark blips, for a bug reply.)
    b:Slider("Size", 100, 400, 10, "dock", "size", "%d")
    b:Tip("The square's size; on the big map, the big map's.", "Or drag its corner grip (bottom left); right-click the grip for 160.")
    local shapes = { { "square", "Square" }, { "54", "5:4" }, { "43", "4:3" }, { "1610", "16:10" },
                     { "45", "4:5" }, { "34", "3:4" }, { "1016", "10:16" } }
    b:Choice("Shape", "dock", "shape", shapes)
    b:Tip("Wide: you see less north and south. Tall: you see less east and west. Size sets the longer side.")
    -- (how it is moved was nowhere on its own page)
    b:Note("Drag its border or its header to move it. Right-click either: its menu, with \"back to the minimap's spot\".")
    b:Advanced(true)
    -- (not on Forever: the minimap goes where you like with Edit Mode, the square by a Ctrl-drag, and the
    -- header's "back to the minimap's spot"; the corner was one more say in it, the user 2026-11-08)
    if not ns.FOREVER then
        b:Check("Into the screen's top-right corner", "dock", "corner")
        b:Tip("Off: where the minimap was.")
    end
    if ns.FOREVER then
        b:Check("Hide the game's title bar", "dock", "hideTitle")
        b:Tip("The minimap's zone name bar. Its tracking button stays. Takes effect the next time you dock.")
    end
    if not ns.FOREVER then b:Check("Hide the day / night indicator", "dock", "hideSun") end
    b:Tip((ns.FOREVER and "The minimap's buttons" or "The minimap's sun and moon. Its other buttons") .. " (clock, tracking, mail...): hold one to move it, right-click while holding to put it back.")
    b:Advanced()
    b:Requires()

    -- (its keys shown here, not only on the Key bindings page: docked, the map's own key rests, so these two
    -- are how it's worked; the tip sat behind advanced settings before)
    local n = Column(p, HALF, 0, HALF)
    n:Header("Its keys")
    n:KeyBind("Dock/undock the map", "BFI_DOCK")
    n:KeyBind("Big map", "BFI_BIGMAP")
    n:Note("Tip: put Big map on M. Shift M does nothing while docked.")
    n:Note("Big map key or arrow: the big map beside the square. Drag its edge to move it, its corner grip to size it.")
    n:Advanced(true)
    n:Note("Hold any of the minimap's buttons to move it; right-click while holding puts it back.")
    n:Advanced()
end }

-- zoom as art on screen (MapControls' ArtX): screen pixels per pixel of the map art
local function ArtSize(v) return string.format("art at %.1fx", v) end
local function Closer(v) return string.format("%.1fx closer", v) end
local function HowClose(v)
    if v < 0.05 then return "fully out" end
    return ArtSize(v)
end
local HOW_CLOSE_TIP = "How far the map zooms in. 0 is fully zoomed out. It never goes past your closest zoom."

-- The What's shown group's own page: every layer, and what filters them all
local SHOWN_SWITCHES = {
    { "Quest givers", "Where you pick quests up and hand them in.", "built in, or QuestieDB", "questie", "shown", "quests", nil,
      get = function() return ns.QuestGiversOn() end, set = function(v) ns.SetQuestGivers(v) ns.RefreshControls() end },
    { "Quest objectives", "Where your quest mobs and items are.", "", "spots", "shown", "quests", nil,
      get = function() return ns.ObjectivesOn() end, set = function(v) ns.SetObjectives(v) ns.RefreshControls() end },
    -- (the user's walk, 2026-11-15: learned quest givers "never touched", its switch is on Quest pins; the line
    -- to a party member "soo niche, only under group is fine". Both off this list.)
    { "Townsfolk", "Trainers, vendors, innkeepers...", "built in, or QuestieDB; learned", "townsfolk", "shown", "people" },
    { "Player & group", "Your arrow and your group.", "the game", "party", "shown", "group",
      icon = "Interface\\Minimap\\MinimapArrow", iconSize = 19 },   -- (the game's own player arrow: it has no map button)
    { "Rares & treasures", "Rare mobs, treasures and events.", "RareScanner", "rares", "shown", "rares", "RareScanner" },
    { "Rares & chests", "Rares, rare elites and treasure chests.", "built in", "wilds", "shown", "rares" },
    { "Gathering nodes", "Herbs, ore, fish and more.", "", "gather", "shown", "rares" },
    { "Unexplored land", "Shows what you haven't found yet.", "", "explore", "shown", "explore" },
    { "Area names", "Names the area under the cursor.", "", "explore", "hoverNames", "explore" },
    -- (the boats' and zeppelins' routes: on Start here and on their own tab, but not on this list of every
    -- layer, where the user looked for their switch, 2026-11-16)
    { "Boats & zeppelins", "Their dotted routes across the sea, and the tram.", "", "transports", "shown", "traversal" },
}

-- The Extras group's own page: what's beside the map, each off until wanted
local EXTRAS_SWITCHES = {
    { "Quest tracker", "This zone's quests, nearest first, in place of the game's.", "", "tracker", "shown", "tracker" },
    { "Quest log", "A quest's page in a window of its own.", "", "questlog", "shown", "questlog" },
    { "Clock", "A clock on the map.", "", "clock", "shown", "clock" },
    { "Your ink on the world map", "Routes, marks and notes you drew.", "", "ink", "shown", "ink" },
}

PAGES[#PAGES + 1] = { key = "shownhome", label = "What's shown", summary = true, build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Layers")
    -- (another addon's layer only with that addon there: greyed "Rares & treasures, needs RareScanner" above
    -- our own "Rares & chests" read as rares twice, the user 2026-11-15. Its page still says what it needs.)
    for _, f in ipairs(ns.DropNoGameLayers(SHOWN_SWITCHES, 4)) do
        -- (the boats only where the build has them: not on Era)
        if (not f[7] or ns.AddonPresent(f[7])) and (f[4] ~= "transports" or ns.SetupTransports) then a:Feature(f) end
    end

    local b = Column(p, HALF, 0, HALF)
    -- (the map's own scale: pins, text, the border, and how large the art is at each zoom step. It was "Pin &
    -- text size": "It sizes border to??", the user 2026-11-15. Its floor for pins sits right under it, out of
    -- advanced: below the floor the slider stops moving pins, and the row that holds them was hidden.)
    -- (the map's scale and its floor for pins are on Size & shape: it sizes the border and an attached
    -- tracker too, "It still doesnt belong", the user 2026-11-15)
    b:Header("All pins")
    b:Slider("Pin opacity", 0, 1, 0.05, "pins", "alpha", Percent)
    b:Tip("Fades every pin on the map together. Each kind of pin also has its own opacity on its page.")
    -- (pins.minMapScale, once "Pins no smaller than": with the map's scale out of the settings it is the size
    -- of every pin. Shown as it stands now; once moved it is that size outright: ns.PinScale, pins.sizeAll)
    b:SliderWith("Size of all pins", 0.5, 3, 0.05,
        function()
            local floor, scale = ns.db.pins.minMapScale or 0, ns.db.scale or 1
            if ns.db.pins.sizeAll then return floor end
            return math.max(floor, scale)
        end,
        function(v)
            ns.db.pins.minMapScale = v
            ns.db.pins.sizeAll = true
            ns.OnSettingChanged("pins", "minMapScale")
        end, "%.2fx")
    b:Tip("Every pin on the map at once, bigger or smaller. One kind of pin alone: the Size slider on its own tab.")
    b:Slider("Tooltip size", 0.6, 1.2, 0.05, "pins", "tipScale", Percent)
    b:Tip("The size of tooltips on the map's pins and buttons. Other tooltips aren't changed.")
    b:Header("Fewer pins")
    b:Check("Hide quest pins outside the zone", "outside", "hideQuests")
    b:Tip("Hides quest pins that fall in the neighbouring zones at the map's edges.")
    b:Button("Go to: Hide pins in unexplored land", function() ns.ShowOption("explore", "hideQuests") end)
    b:Button("Go to: Colour by quest difficulty", function() ns.ShowOption("questie", "color") end)
end }

PAGES[#PAGES + 1] = { key = "extrashome", label = "Extras", summary = true, build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Beside the map")
    for _, f in ipairs(EXTRAS_SWITCHES) do a:Feature(f) end
    a:Button("Open the book", function() if ns.ToggleNotebook then ns.ToggleNotebook() end end)
end }

PAGES[#PAGES + 1] = { key = "browse", label = "Zoom, other zones & continent", build = function(p)
    local a = Column(p, 0, 0, HALF)
    -- (the zoom page's rows: it had two showing, and Keep centred is on What the map does by itself now)
    a:Header("Zoom")
    a:Slider("Closest zoom", 2, 24, 0.5, "zoom", "closestX", ArtSize)
    a:Tip("How far in you can zoom with the mouse wheel.")
    a:Advanced(true)
    a:Slider("Smoother zoom", 1, 5, 1, "zoom", "smoothness", "%dx steps", "1.5x a click")
    a:Tip("Splits each wheel click into this many smaller steps.")
    a:Check("Zoomed out shows just the zone", "zoom", "fitZone")
    a:Tip("Fully zoomed out shows your zone edge to edge, without the neighbouring zones around it.")
    a:Slider("Zoom speed", 0.3, 3, 0.1, "zoom", "animTime", "%.1f s")
    a:Tip("How long an automatic zoom in or out takes, here and in towns and cities.")
    a:Button("Reset zoom & detail to defaults", function() ns.ConfirmResetGroup("zoom") end)
    a:Tip("Resets the zoom and close-up detail sliders. Your on and off switches stay.")
    a:Advanced()
    a:Header("Getting there")
    a:Check("Look at other zones and the continent", "browse", "enabled")
    a:Tip("Lets you look at other zones and the continent on this map. It stops following you until you come back.", "Right-click: one map up. Left-click a zone or a capital: that map. Middle-click: back to yours.")
    a:Requires("browse", "enabled")
    a:Check("The mouse wheel climbs maps", "browse", "wheel")
    a:Tip("Wheel out past fully zoomed out for the continent; wheel in over a zone, or a capital, to open it.")
    a:Requires("browse", "wheel")
    a:Slider("Wheel clicks past fully out", 1, 6, 1, "browse", "friction", "%d")
    a:Tip("How many extra wheel clicks it takes to zoom out of the zone. The map's edge glows on each one, so you don't leave by accident.")
    a:Requires("browse", "enabled")
    a:Header("While you look")
    a:Advanced(true)
    a:Check("Silver header on a map you're not in", "browse", "silver")
    a:Advanced()
    a:Check("Zone names on hover", "browse", "overviewNames")
    a:Tip("The zone's name and levels as you move the mouse over the continent or the world.")
    a:Check("Quest givers on the continent", "browse", "continentGivers")
    a:Tip("Shows quest givers on the continent map too. Grey quests show on zone maps only.")
    a:Button("Go to: Painted continents", function() ns.OpenOptionsPage("look") end)
    a:Requires()

    local b = Column(p, HALF, 0, HALF)
    b:Header("Back to your map")
    b:Note("Middle-click the map to go back.")
    b:Requires("browse", "enabled")
    b:Check("When you close and open the map", "browse", "onReopen")
    b:Check("When you walk into a new zone", "browse", "onZone")
    b:Slider("After the mouse has been away", 0, 60, 1, "browse", "idle", "%d s", "never")
    b:Tip("Back to your own map once the mouse has been off the map this long.")
    b:Requires()
    b:Check("Keep what you're looking at on a flight path", "browse", "taxi")
    b:Tip("If you're looking at another zone or the continent when you take a flight, the map stays there until you land.")
    b:Note("Key binding: Continent map (Key bindings page). Again: back to your map.")
end }

-- The map's look: how the map itself is drawn, in one place (the user, 2026-11-14: "Its all part of the same
-- deal, so it should feel that way"; mockups/map-look-settings.html). A look on top sets the four switches
-- that carry it, each look one step richer than the last; every switch is underneath, in three groups. The
-- rows came from Size, shape & fade (the hour), Zoom, centring & detail (close-up detail) and Other zones &
-- continent (painted continents). Soft edges went back to the window's page: a frame setting, as clear view. The thresholds the user tuned to find the sweet spot stay
-- behind Show advanced settings.
local LOOKS = {
    { "game",    "The game's map",      relief = false, painted = false, detail = false, hour = false },
    { "painted", "Painted",             relief = false, painted = true,  detail = true,  hour = false },
    { "land",    "The lie of the land", relief = true,  painted = true,  detail = true,  hour = false },
    { "hour",    "The lie of the land, by the hour", relief = true,  painted = true,  detail = true,  hour = true },
}
-- (a build without the relief: three looks, and the relief's part is not asked)
local function LookFits(l)
    local has = ns.ReliefSetting ~= nil
    if not has and l[1] == "land" then return false end
    return (not has or l.relief == (ns.db.relief.on and true or false))
        and l.painted == (ns.db.browse.zoneArt and true or false)
        and l.detail == (ns.IsShown("detail") and true or false)
        and l.hour == (ns.db.mapHour.on and true or false)
end
local function LookNow()
    for _, l in ipairs(LOOKS) do
        if LookFits(l) then return l[1] end
    end
    return "own"
end
local function LookSet(key)
    for _, l in ipairs(LOOKS) do
        if l[1] == key then
            if ns.ReliefSetting then select(2, Setting("relief", "on"))(l.relief) end
            select(2, Setting("browse", "zoneArt"))(l.painted)
            select(2, LayerSetting("detail", "shown"))(l.detail)
            select(2, Setting("mapHour", "on"))(l.hour)
        end
    end
    ns.RefreshControls()
end
ns.MapLook = { now = LookNow, set = LookSet }      -- (tools/options_pages_smoke.lua)

-- The pencilled map's one switch for players (Pencil.lua, cleared for 1.3 on 2026-11-14), on The map's
-- look (it was on Exploration too until the settings pass took the doubles out): a plain setting (pencil.on), and the row is made only while ns.PencilSetting is there
-- (Pencil.lua defines it on Forever), so a build without the pencil (Classic Era) has no dead row. Greyed while
-- unexplored land is drawn "As explored": every area shows whole then, and there is nothing left to sketch.
-- Land you have not found: one choice of three, and for the middle one how much of it shows. (It was a
-- list of six looks, Left blank / Fog / Sepia / Dark ink / Faded / As explored, and a tick for the pencil
-- beside it: "We need to rework this whole thing. Dark ink looks bad, sepia is unneeded. It doeesnt explain
-- penciling sighted. The important switches are, show as explored, as unexplored with a gradient choice, and
-- paint in sighted (with rest unexplored)", the user 2026-11-15.) The settings underneath are the same:
-- explore.shown, explore.fogStyle, explore.fogAlpha, pencil.on. Sepia and Dark ink are no longer offered; a
-- map that has one keeps it until this choice is touched.
local function UnfoundRows(col)
    local shown, setShown = LayerSetting("explore", "shown")
    local function Pencil() return ns.PencilSetting and ns.db.pencil and ns.db.pencil.on end
    local function SetPencil(on)
        if not ns.PencilSetting then return end
        ns.db.pencil.on = on and true or false
        ns.OnSettingChanged("pencil", "on")
    end
    local function Now()
        if shown() and ns.db.explore.fogStyle == "full" then return "full" end
        if Pencil() and not shown() then return "pencil" end
        return "dim"
    end
    local function Dim()   -- (a look that dims: the one it has, else Faded)
        local st = ns.db.explore.fogStyle
        if st == "full" or st == nil then
            ns.db.explore.fogStyle = "faded"
            ns.OnSettingChanged("explore", "fogStyle")
        end
    end
    local choices = { { "full", "Shown, as if explored" }, { "dim", "Dimmed until you find it" } }
    if ns.PencilSetting then choices[#choices + 1] = { "pencil", "Blank, pencilled in as you see it" } end
    -- ("Unexplored land": "the word unexplored is fammiliar", the user 2026-11-15)
    col:Choice("Unexplored land", nil, nil, choices, Now, function(v)
        if v == "full" then
            ns.db.explore.fogStyle = "full"
            ns.OnSettingChanged("explore", "fogStyle")
            setShown(true)
        elseif v == "pencil" then
            setShown(false)
            SetPencil(true)
        else
            SetPencil(false)
            Dim()
            setShown(true)
        end
        ns.RefreshControls()
    end)
    col:Tip("Shown: the whole zone from the start. Dimmed: unexplored land is faint until you find it. Pencilled: unexplored land is blank. What you've seen is sketched in pencil, and it gets colour where you walk.")
    col:Requires(function() return Now() == "dim" end)
    col:SliderWith("How much of it shows", 0, 1, 0.05,
        function() return shown() and (ns.db.explore.fogAlpha or 0.7) or 0 end,
        function(v)
            if v < 0.03 then
                setShown(false)
            else
                ns.db.explore.fogAlpha = v
                ns.OnSettingChanged("explore", "fogAlpha")
                Dim()
                if not shown() then setShown(true) end
            end
        end, function(v) return v < 0.03 and "nothing" or string.format("%d%%", v * 100 + 0.5) end)
    col:Tip("From blank to nearly as clear as explored land.")
    col:Requires()
end

PAGES[#PAGES + 1] = { key = "look", label = "The map's look", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("The map's look")
    a:Note("How the map itself is drawn. Pick a look, or set each part yourself below.")
    a:Choice("Look", nil, nil, function()
        local out = {}
        for _, l in ipairs(LOOKS) do
            if ns.ReliefSetting or l[1] ~= "land" then out[#out + 1] = { l[1], l[2] } end
        end
        if LookNow() == "own" then out[#out + 1] = { "own", "Your own mix" } end
        return out
    end, LookNow, LookSet)
    a:Tip("The game's map: as the game draws it. Painted: sharper continents, with trees and buildings up close. The lie of the land: adds hills and shadows. By the hour: adds colours that change with the time of day.")
    -- (the look named on top follows a switch changed by hand at once: "Your own mix", or the look it now fits)
    do
        local box, shown = a.last, LookNow()
        local watch = CreateFrame("Frame", nil, p)
        watch:SetScript("OnUpdate", function()
            local now = LookNow()
            if now ~= shown then
                shown = now
                if box and box.Refresh then box.Refresh() end
            end
        end)
    end

    a:Header("The land")
    if ns.ReliefSetting then
        a:Check("The lie of the land", "relief", "on")
        a:Tip("Hills, valleys and shadows from the game's real terrain. Off in performance mode unless you keep it on there.")
        a:Requires("relief", "on")
        a:Slider("Strength", 30, 160, 5, "relief", "shadeAlpha", "%d%%")
        a:Check("Shadows thrown by ridges", "relief", "cast")
        a:Tip("Mountains and ridges cast shadows over the land behind them.")
        a:Requires()
    end
    a:Check("Painted continents", "browse", "zoneArt")
    a:Tip("Zoomed in on a continent, each zone's own sharper map replaces the game's blocky one. The lie of the land needs this on to show on continents.")
    a:Advanced(true)
    a:Requires("browse", "zoneArt")
    a:Stops("How they come in", "browse",
        { { "fadeFrom", "map from" }, { "fadeFull", "in" }, { "detailFull", "areas full" } },
        0.05, 1.2, 0.05,
        { { 0.23, 0.18, 0.13 }, { 0.85, 0.77, 0.61 }, { 0.50, 0.69, 0.41 }, { 1, 0.82, 0 } },
        { { 0.25, "25%" }, { 0.5, "50%" }, { 0.75, "75%" }, { 1, "opens" } },
        function(v) return string.format("%d%%", v * 100 + 0.5) end)
    a:Tip("How far you zoom in before each zone's own map starts to show, is fully shown, and has its colours.", "Press the track to bring the nearest stop there, and drag.")
    a:Requires()
    a:Advanced()
    a:Check("Close-up detail", "detail", "shown", nil, ns.ToggleIcon("detail"))
    a:Tip("Trees, rocks and buildings fade in as you zoom in. Eastern Kingdoms and Kalimdor only. Tile data from OpenMap (MIT).")
    a:Requires("detail", "shown")
    a:Slider("Opacity when zoomed in", 0.1, 1, 0.05, "detail", "strength")
    a:Advanced(true)
    a:Check("On the big map too", "detail", "bigMap")
    a:Tip("Off: the detail shows on the small map only, the big map keeps to the map art.")
    a:Slider("Starts to show at", 1, 16, 0.1, "detail", "fromZoom", Closer)
    a:Tip("How far you zoom in before the detail starts to show.")
    a:Slider("Full detail at", 1, 16, 0.1, "detail", "fullZoom", Closer)
    a:Tip("How far you zoom in before the detail is fully shown.")
    a:Check("Full detail at every zoom", "detail", "always", nil, ns.ToggleIcon("detailAll"))
    a:Tip("Shows the detail at any zoom, on continent maps too.")
    a:Check("Blend with the map's colours", "detail", "blend")
    a:Advanced()
    a:Requires()

    local b = Column(p, HALF, 0, HALF)
    b:Header("The light")
    if ns.ReliefSetting then
        b:Check("The land's light follows the time of day", "relief", "hour")
        b:Tip("The light on the hills comes from the east in the morning, the south at noon and the west at dusk, weaker at night. Off: one steady light from the north-west.")
        b.last.bfiDep = function() return ns.db.relief.on and true or false end
    end
    b:Check("The colours follow the time of day too", "mapHour", "on")
    b:Tip("Zone maps turn warm at dawn and dusk and blue at night, with a lamp around you in the dark. Goes by the clock's time (Time from, on the Clock settings).")

    b:Header("Unexplored land")
    UnfoundRows(b)
    p.bfiKeys = p.bfiKeys or {}
    table.insert(p.bfiKeys, { "explore", "fogStyle" })     -- (Reset this page)
    -- (from Size & shape, a leftover of when that tab was "Size, shape & fade": how see-through the map is
    -- belongs with how it is drawn. "these are found under size and shape. why", the user 2026-11-15)
    b:Header("See-through")
    -- (clear view has an opacity of its own, in place of this one while it is on: the slider read 0% beside
    -- a map in clear view at full strength, and moving it did nothing. The user's two screenshots,
    -- 2026-11-15. It now shows and moves the opacity the map has as it is, and its number says which.)
    local function Clear() return ns.db.clearView and ns.db.clearView.on end
    b:SliderWith("Map opacity", 0, 1, 0.05,
        function()
            if Clear() then return ns.db.clearView.opacity or 1 end
            return ns.db.mapFrame.opacity or 1
        end,
        function(v)
            if Clear() then
                ns.db.clearView.opacity = math.max(0.1, v)
                ns.OnSettingChanged("clearView", "opacity")
            else
                ns.db.mapFrame.opacity = v
                ns.OnSettingChanged("mapFrame", "opacity")
            end
        end,
        function(v) return string.format("%d%%", v * 100 + 0.5) .. (Clear() and "  in clear view" or "") end)
    b:Tip("How see-through the map picture is. At 0% only pins, border, header and buttons are left. Clear view has its own opacity.")
    p.bfiKeys = p.bfiKeys or {}
    table.insert(p.bfiKeys, { "mapFrame", "opacity" })     -- (Reset this page, and "its settings" from elsewhere)
    b:Button("Go to: Border and header opacity", function() ns.ShowOption("mapFrame", "frameAlpha") end)
    b:Button("Go to: Pin opacity", function() ns.ShowOption("pins", "alpha") end)
    b:Button("Go to: Fades while you move", function() ns.ShowOption("fade", "moving") end)
    b:Note("Performance mode switches off the lie of the land" .. (ns.PencilSetting and ", the time-of-day colours and the pencil" or " and the time-of-day colours") .. " while it is on.")
end }

-- Town view and City view (view: "townView" / "cityView") -----------------

-- One slider a place: every pin there, bigger or smaller (view.pinScale, on top of each pin's own size:
-- ns.TownPinSize). The seven sliders a place for single layers are gone (2026-11-15): a layer has one Size
-- slider, on its own tab, and it moves the pin you are looking at.
local function ViewPinSizes(a, view, where)
    a:Header("Pin size " .. where)
    a:Slider("All pins " .. where, 0.5, 3, 0.05, view, "pinScale", "%.2fx")
    a:Tip("Every pin on the map while you are there, bigger or smaller. One kind of pin alone: the Size slider on its own tab.")
    -- ("Same sizes as in the open world", a button under the fine-tuning, is gone: the user, 2026-11-15, "no
    -- need".)
end

-- Towns and cities on one page (they were two with the same layout, the settings pass, 2026-11-14): what the
-- map does in a town, then in a capital, each with its pin sizes; the tools for a place the town finding got
-- wrong; and, as fine-tuning, a townsfolk list of their own for each.
PAGES[#PAGES + 1] = { key = "town", label = "Towns & cities", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("In a town", ns.ToggleIcon("town"))
    a:Check("Town view", "townView", "enabled")
    a:Tip("Turns all of town view on or off: the zoom, bigger pins and the townsfolk list. Capital cities have their own switch below.")
    a:Check("Zooms in on towns", "townView", "zoom")
    a:Tip("A close-up of the town when you arrive, following you; back to your own zoom when you leave. Paused while you've panned or zoomed the map yourself.")
    a:Requires("townView", "zoom")
    a:Slider("How close", 0.5, 16, 0.1, "zoom", "townX", HowClose)
    a:Tip("", HOW_CLOSE_TIP)
    a:Requires(nil, "mapButtons")
    a:Check("Town view button on the map", nil, "townButton")
    a:Tip("Beside the gear: switches all of town view on or off with one click.")
    a:Requires()
    a:CheckWith("Show townsfolk in towns", function()
        local c = ns.db.profiles.city
        return c and c.enabled and c.layers.townsfolk == true or false
    end, function(v)
        local c = ns.db.profiles.city
        if v then c.enabled = true end
        c.layers.townsfolk = v or nil
        ns.OnSettingChanged("profiles", "layers")
        if ns.UpdateProfile then ns.UpdateProfile() end
        ns.RefreshControls()
    end)
    a:Tip("Shows trainers, vendors and the rest in towns and cities, even if Townsfolk is off elsewhere.")

    ViewPinSizes(a, "townView", "in town")

    a:Header("In a capital city", ns.ToggleIcon("city"))
    a:Check("Zoom when you enter a capital", "cityView", "zoom")
    a:Tip("In a capital city the map shows the whole city, and goes back to your zoom when you leave.")
    a:Requires("cityView", "zoom")
    a:Slider("How close", 0, 16, 0.1, "cityView", "zoomX", function(v)
        if v < 0.05 then return "the whole city" end
        return ArtSize(v)
    end)
    a:Tip("0 shows the whole city.", HOW_CLOSE_TIP)
    a:Requires(nil, "mapButtons")
    a:Check("City view button on the map", nil, "cityButton")
    a:Tip("The button with your faction's crest. Turns the whole-city zoom on or off.")
    a:Requires()
    a:Note("Off: in a capital city the map keeps your own zoom.")

    ViewPinSizes(a, "cityView", "in a city")

    -- (the tools for when the town finding gets a place wrong, and where it thinks you are now)
    local b = Column(p, HALF, 0, HALF)
    b:Header("Is this a town?")
    local status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Ink(p, status)
    status:SetPoint("TOPLEFT", b:Left() + 4, b.y - 2)
    status:SetWidth(HALF - 30)
    status:SetJustifyH("LEFT")
    b.y = b.y - 40
    local ticker = CreateFrame("Frame", nil, p)
    ticker:SetScript("OnUpdate", function()
        local sub = ns.CurrentSubZone and ns.CurrentSubZone() or ""
        local inTown, why = false, "-"
        if ns.TownStatus then inTown, why = ns.TownStatus() end
        local here = inTown and "|cff4ddf4dIn town|r" or "|cffff6a4dNot a town|r"
        if ns.InCityView and ns.InCityView() then here = "|cff4ddf4dIn a capital city|r" end
        status:SetText((sub ~= "" and sub or "(no sub-zone)") .. "\n" .. here .. "  |cff9d9d9d(" .. why .. ")|r")
    end)
    b:Button("This place is a town", function() ns.MarkTown(true) end)
    b:Button("This place is not a town", function() ns.MarkTown(false) end)
    b:Button("Back to automatic", function() ns.MarkTown(nil) end)
    b:Note("Waymark counts a place as a town when it has two services close together, like an inn and a flight master. A place you mark with the buttons above wins.")
    b:Button("Forget remembered towns", function() ns.ForgetLearnedTowns() end)

    -- (which townsfolk show in a town or a capital: the Townsfolk tab's list, with its place switch)
    b:Button("Go to: Which townsfolk show here", function() ns.OpenOptionsPage("people") end)
end }

-- the header on the left; the map's border and the header's side by side on the right
-- Header & border (the settings pass, 2026-11-15; mockups\header-borders.html). It was two columns of some
-- thirty controls: the header, the map's border, the header's own border, the tooltip's and the tracker's
-- frames, one look for wherever the map was. Now: each place the map lives keeps its own look (PlaceLooks.lua),
-- picked here by the place's tab, which also puts the map there so the change is seen; a ready-made look
-- first; the few choices a player makes; the rest with the fine-tuning.
PAGES[#PAGES + 1] = { key = "header", label = "Header & border", build = function(p)
    local a = Column(p, 0, 0, CONTENT_W)
    a:Header("The look, for each place the map lives")
    a:Note("The map can look different as a window, in clear view and as your minimap. Pick one to switch the map to it and change its look.")
    do
        local tabs = {}
        local function TabLook()
            local now = MapRole()
            for _, b in ipairs(tabs) do
                local on = b.place == now
                if on then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(1, 0.82, 0) end
                b.under:SetShown(on)
            end
        end
        local tx = a:Left() + 4
        for _, t in ipairs({ { "window", "A window" }, { "clear", "Clear view" }, { "dock", "The minimap's place" } }) do
            local b = CreateFrame("Button", nil, p)
            b.place = t[1]
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            b.text:SetText(t[2])
            b.text:SetPoint("CENTER", 0, 1)
            b:SetSize(b.text:GetStringWidth() + 24, 24)
            b:SetPoint("TOPLEFT", p, "TOPLEFT", tx, a.y)
            b.under = b:CreateTexture(nil, "ARTWORK")
            b.under:SetColorTexture(1, 0.82, 0, 0.9)
            b.under:SetPoint("BOTTOMLEFT", 6, 0)
            b.under:SetPoint("BOTTOMRIGHT", -6, 0)
            b.under:SetHeight(2)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            b:SetScript("OnClick", function()
                SetMapRole(t[1])
                ns.RefreshControls()
            end)
            tabs[#tabs + 1] = b
            tx = tx + b:GetWidth() + 6
        end
        -- (the tab of the place the map is in, whoever moved it there)
        local look = CreateFrame("Frame", nil, p)
        look.Refresh = TabLook
        controls[#controls + 1] = look
        TabLook()
        a.y = a.y - 32
    end
    if ns.PlaceLookChoices then
        a:Choice("Ready-made look", nil, nil, ns.PlaceLookChoices, ns.PlaceLookNow, function(v)
            if v ~= "own" then ns.PlaceLookSet(v) end
            ns.RefreshControls()
        end)
        a:Tip("A matching header and border. It says Your own once you've changed a part yourself.")
    end

    a:Header("Header")
    -- (clear view has switches of its own over these two: its zone name shown, on mouse-over or hidden, and
    -- its border hidden, Clear view tab. There the ticks here answer for both, or a tick that is on showed
    -- nothing: the user, 2026-11-15, "feels broken".)
    local function InClear() return MapRole() == "clear" end
    local function HeaderOn()
        return ns.db.zoneName.shown and not (InClear() and ns.db.clearView.header == "hidden") and true or false
    end
    a:CheckWith("Show the header", HeaderOn, function(v)
        ns.db.zoneName.shown = v and true or false
        ns.OnSettingChanged("zoneName", "shown")
        if v and InClear() and ns.db.clearView.header == "hidden" then
            ns.db.clearView.header = "shown"
            ns.OnSettingChanged("clearView", "header")
        end
        ns.RefreshControls()
    end)
    a:Requires(HeaderOn, true)
    -- each spot keeps its own nudge (zoneName.nudges[mode] = { x, y }): the one nudge counted for all three,
    -- so a nudge made above the map threw the header off inside or below it (the user, 2026-11-15: "nudge
    -- sliders count for all dropdowns, which doesnt make sense"). The drawing code reads offsetX / offsetY
    -- as ever; a change of spot puts the old spot's away and brings out the new one's (a spot never nudged: 0).
    a:Choice("Where it sits", "zoneName", "mode", {
        { "header", "Above the map" },
        { "below", "Below the map" },
    }, function() return ns.db.zoneName.mode end, function(v)
        local z = ns.db.zoneName
        local old = z.mode == "below" and "below" or "header"
        if v == old then return end
        z.nudges = type(z.nudges) == "table" and z.nudges or {}
        z.nudges[old] = { z.offsetX or 0, z.offsetY or 0 }
        local n = z.nudges[v]
        z.mode = v
        z.offsetX, z.offsetY = n and n[1] or 0, n and n[2] or 0
        ns.OnSettingChanged("zoneName", "mode")
        ns.RefreshControls()
    end)
    a:Slider("Text size", 9, 24, 1, "zoneName", "fontSize", "%d")
    a:Check("The zone too (Sentinel Hill, Westfall)", "zoneName", "showZone")
    a:Check("The zone's level range", "zoneName", "levels")
    a:Tip("Coloured like quests: green is easy for you, red is dangerous.")
    a:Check("How much of the zone you've explored", "zoneName", "progress")
    a:Check("Coloured like the zone text", "zoneName", "pvpColors")
    a:Tip("Red, green or gold for hostile, friendly or contested land, as the game's zone text.")
    a:Advanced(true)
    -- (the fine-tuning in three small groups, for reading: the user, 2026-11-15)
    a:SubHeader("Style and border")
    StyleChoice(a, "Header style", "header", "zoneName", "style", HEADER_STYLES)
    -- (the header's own border sits with the header, not in a section of its own: the user, 2026-11-15,
    -- "Header border belongs together with header". A ready-made look sets these: by hand only with the
    -- fine-tuning.)
    a:Choice("Header border", "zoneName", "border", Trimmed({
        { "auto", "The style's own" }, { "dialog", "Classic dialog" }, { "gold", "Gold" },
        { "tooltip", "Tooltip" }, { "wood", "Wood" }, { "line", "Thin line" }, { "none", "None" },
    }, ns.db.zoneName.border))
    a:Choice("Header border colour", "zoneName", "borderColor", {
        { "natural", "As drawn" }, { "gold", "Gold" }, { "bronze", "Bronze" },
        { "silver", "Silver" }, { "dark", "Dark" }, { "class", "My class colour" },
    })
    a:Slider("Header border thickness", 0.5, 2, 0.05, "zoneName", "borderSize", "%.2fx")
    a:Slider("Header border distance", -12, 20, 1, "zoneName", "borderGap", "%d px")
    a:SubHeader("Font and width")
    a:Choice("Font", "zoneName", "font", ns.FontChoices)
    a:Tip("Morpheus is the font of the game's own zone text.", FONT_TIP)
    a:Check("As wide as the map", "zoneName", "fullWidth")
    a:Choice("Text alignment (wide)", "zoneName", "align", {
        { "CENTER", "Centre" }, { "LEFT", "Left" }, { "RIGHT", "Right" },
    })
    a:SubHeader("Nudge")
    a:Slider("Nudge left / right", -150, 150, 1, "zoneName", "offsetX", "%d px")
    -- (down far enough to sit inside the map: "Inside, at the top" is the nudge now)
    a:Slider("Nudge down / up", -150, 60, 1, "zoneName", "offsetY", "%d px")
    a:Tip("Each spot in Where it sits keeps a nudge of its own.")
    a:Advanced()
    a:Requires()

    a:Header("Border")
    local function BorderOn()
        return ns.db.border.shown and not (InClear() and ns.db.clearView.noFrame) and true or false
    end
    a:CheckWith("Show the border", BorderOn, function(v)
        ns.db.border.shown = v and true or false
        ns.OnSettingChanged("border", "shown")
        if v and InClear() and ns.db.clearView.noFrame then
            ns.db.clearView.noFrame = false
            ns.OnSettingChanged("clearView", "noFrame")
        end
        ns.RefreshControls()
    end)
    a:Tip("Off: no frame round the map at all, the game's own included. Your style is kept for when you switch it back on.")
    a:Requires(BorderOn, true)
    a:Choice("Colour", "border", "color", {
        { "natural", "As drawn" }, { "gold", "Gold" }, { "bronze", "Bronze" },
        { "silver", "Silver" }, { "dark", "Dark" }, { "class", "My class colour" },
    })
    a:Advanced(true)
    StyleChoice(a, "Border style", "border", "border", "style", Trimmed(BORDER_STYLES, ns.db.border.style))
    a:Slider("Thickness", 0.5, 2, 0.05, "border", "size", "%.2fx")
    a:Slider("Distance from the map", -12, 20, 1, "border", "gap", "%d px")
    a:Advanced()
    a:Requires()

    a:Advanced(true)
    a:Header("See-through")
    a:Slider("Border and header opacity", 0, 1, 0.05, "mapFrame", "frameAlpha", Percent)
    a:Tip("How see-through the border and header are. The map's buttons fade separately, on the Buttons tab.")
    a:Advanced()

end }

-- Tooltips & menus (2026-11-16): what is styled and is not the map's own frame. It stood at the foot of
-- Header & border, under the nudge sliders. The tracker's frame went to the Tracker tab's Border section.
PAGES[#PAGES + 1] = { key = "tipsmenus", label = "Tooltips & menus", build = function(p)
    local a = Column(p, 0, 0, CONTENT_W)
    if ns.FramesRows then ns.FramesRows(a, "tips") end
    a:Header("Menus & questions")
    a:Choice("Font", "menus", "font", ns.FontChoices)
    a:Tip("Waymark's right-click menus and the box where it asks you something. Friz Quadrata, the game's own, reads best.", FONT_TIP)
end }

PAGES[#PAGES + 1] = { key = "controls", label = "Buttons", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Map buttons")
    a:Check("Show the map's buttons", nil, "mapButtons")
    a:Tip("All of them at once: the toggle buttons, the gear, the magnifier, and the town and city view buttons. Each also has its own switch below.")
    a:Requires(nil, "mapButtons")
    a:Check("Toggle buttons", nil, "quickToggles")
    a:Tip("Small buttons on the map that switch layers on and off. Right-click one for its settings.")
    a:Check("Quick-options button (the gear)", nil, "quickButton")
    a:Tip("The most-used switches in a small panel. Right-click it for these settings.")
    -- (Search.lua, out of the Lab for 1.3: only in a build that carries it)
    if ns.RedrawSearch then
        a:Check("Search the map (the magnifier)", nil, "searchButton")
        a:Tip("Type a trainer, a service or an item a vendor sells: the map rings the closest one. Not shown while the map is docked.")
    end
    -- (the same two switches as on How it acts, In a town and In a capital city: here too, with the map's other
    -- buttons, where the user looked for them, 2026-11-15)
    a:Check("Town view button", nil, "townButton", nil, ns.ToggleIcon("town"))
    a:Tip("Beside the gear: switches all of town view on or off with one click.")
    a:Check("City view button", nil, "cityButton", nil, ns.ToggleIcon("city"))
    a:Tip("The button with your faction's crest. Turns the whole-city zoom on or off.")
    a:Requires()
    a:Button("Put the map's buttons back", function() ns.ResetButtonPositions() end)
    a:Tip("Press and hold any button on the map to move it; right-click while holding puts that one back.")
    if not AddonCompartmentFrame then
        a:Check("Minimap button", "minimap", "hide", true)
        a:Tip("On the game's own minimap, not on this map.", "Click: the Battlefield Map. Right-click: these settings.")
    end
    a:Header("Toggle buttons")
    a:Requires(nil, "quickToggles")
    a:Advanced(true)
    a:Choice("Look", "toggles", "style", {
        { "square", "Square" }, { "plain", "Icons only" },
    })
    a:Slider("Size", 10, 32, 1, "toggles", "size", "%d px")
    local getEdge, setEdge = ns.TogglePlaceSetting("edge")
    a:Choice("Edge", "toggles", "edge", {
        { "top", "Top (a row)" }, { "bottom", "Bottom (a row)" },
        { "left", "Left (a column)" }, { "right", "Right (a column)" },
    }, getEdge, setEdge)
    local getFrom, setFrom = ns.TogglePlaceSetting("from")
    a:Advanced(true)
    a:Choice("Starting from", "toggles", "from", ns.ToggleFromChoices, getFrom, setFrom)
    a:Choice("Side", "toggles", "side", {
        { "inside", "Inside the map" }, { "outside", "Outside the map" },
    })
    a:Advanced()
    a:Check("Fade when the mouse isn't on the map", "toggles", "fadeOut")
    a:Tip("The gear fades with them.")
    a:Advanced(true)
    a:Slider("Faded to", 0, 100, 5, "toggles", "fadeAlpha", "%d%%")
    a:Check("The close button too", "toggles", "fadeClose")
    a:Check("Remember clicks per context profile", "toggles", "saveToProfile")
    a:Tip("On: a layer you switch with a button while in a town stays that way every time you're in a town. Off: it only lasts until you leave. The same goes for combat, dungeons and battlegrounds.")
    a:Advanced()
    a:Requires()

    -- Which buttons beside Button order (two columns, level), Coordinates under both
    local l = Column(p, 0, nil, HALF, true)
    local r = Column(p, HALF, nil, HALF, true)
    -- which buttons, under where each layer comes from (t[6]; ours when none)
    local ORDER = ns.FOREVER and { "QuestieDB", "The game's own", "Other addons", "Waymark" }
        or { "QuestieDB", "Other addons", "Waymark" }
    l:Header("Which buttons")
    l:Requires(nil, "quickToggles")
    for _, source in ipairs(ORDER) do
        l:SubHeader(source == "Waymark" and "Waymark's own" or source)
        for _, t in ipairs(ns.TOGGLES) do  -- (defined further down, read when the page opens)
            if (t[6] or "Waymark") == source then
                l:CheckWith(t[4],
                    function() return ns.db.toggles.list[t[1]] end,
                    function(v)
                        ns.db.toggles.list[t[1]] = v and true or false
                        ns.OnSettingChanged("toggles", "list")
                        ns.RefreshControls()  -- (greys it in Button order)
                    end, true, t[3])
            end
        end
    end
    l:Requires()
    l:EndCard()
    r:Header("Button order")
    r:Requires(nil, "quickToggles")
    local items = {}
    for _, t in ipairs(ns.TOGGLES) do items[t[1]] = { t[4], t[3] } end
    r:OrderList("Button order", items, ns.ToggleOrder,
        function(order)
            ns.db.toggles.order = order
            ns.OnSettingChanged("toggles", "order")
        end,
        function(id) return ns.db.toggles.list[id] end, "toggles", "order")
    r:Note("Drag a row to change the order. The top row is the first button.")
    r:Button("Default order", function()
        ns.db.toggles.order = {}
        ns.OnSettingChanged("toggles", "order")
        ns.RefreshControls()
    end)
    r:Requires()
    r:EndCard()

end }

PAGES[#PAGES + 1] = { key = "clock", label = "Clock & coordinates", build = function(p)
    local c = Column(p, 0, 0, HALF)
    c:Header("Clock")
    c:Check("Show a clock on the map", "clock", "shown")
    c:Requires("clock", "shown")
    c:Choice("Look", "clock", "look", {
        { "plain", "Plain digits" }, { "head", "In the header" }, { "sun", "Moon dial" }, { "arc", "The day's arc" },
        { "stamp", "Stamp" }, { "ink", "In ink" },
    })
    c:Tip("In the header: next to the zone name. In ink: the time written out in words, to the nearest 5 minutes.", "Drag the clock to move it. Right-click it to detach it from the map, or anchor it again.")
    c:Check("24-hour time", "clock", "h24")
    c:Advanced(true)
    c:Choice("Time from", "clock", "source", { { "realm", "The realm" }, { "computer", "My computer" } })
    c:Choice("Show", "clock", "show", { { "always", "Always" }, { "hover", "With the mouse on the map" } })
    c:Slider("Size", 70, 150, 5, "clock", "size", "%d%%")
    c:Slider("Opacity", 20, 100, 5, "clock", "alpha", "%d%%")
    c:Requires(function() return ns.IsShown("clock") and (ns.db.clock.look == "sun" or ns.db.clock.look == "arc") end)
    c:Check("Hide the digits", "clock", "hideDigits")
    c:Tip("The time still shows when you hover the clock. With the digits on, drag them to move them around the clock.")
    c:Requires(function() return ns.IsShown("clock") and ns.db.clock.look == "plain" end)
    c:Choice("Font", "clock", "font", ns.FontChoices)
    c:Choice("Digit colour", "clock", "tint", { { "parchment", "Parchment" }, { "gold", "Gold" }, { "white", "White" } })
    c:Slider("Background", 0, 100, 5, "clock", "backing", "%d%%", "none")
    c:Choice("Frame", "clock", "frame", {
        { "none", "None" }, { "dialog", "Classic dialog" }, { "gold", "Gold" },
        { "tooltip", "Tooltip" }, { "line", "Thin line" },
    })
    c:Requires("clock", "shown")
    c:Button("Reset clock position", function() ns.ResetClock() end)
    c:Tip("Puts it under the minimap, detached from the map, with the digits back under the art.")
    c:Advanced()
    c:Requires()
    -- (from the Buttons tab: coordinates are something shown on the map, as the clock is. "Coordiantes belong
    -- on the map dont they?", the user 2026-11-15)
    local d = Column(p, HALF, 0, HALF)
    d:Header("Coordinates")
    d:Check("Show", "coords", "shown")
    d:Requires("coords", "shown")
    d:Advanced(true)
    d:Slider("Text size", 4, 20, 1, "coords", "size", "%d")
    local SPOTS = {
        { "TOPLEFT", "Top left" }, { "TOP", "Top middle" }, { "TOPRIGHT", "Top right" },
        { "BOTTOMLEFT", "Bottom left" }, { "BOTTOM", "Bottom middle" }, { "BOTTOMRIGHT", "Bottom right" },
    }
    d:Choice("Player: where", "coords", "where", SPOTS)
    local cursorSpots = { { "beside", "Beside the player's" } }
    for _, s in ipairs(SPOTS) do cursorSpots[#cursorSpots + 1] = s end
    d:Choice("Cursor: where", "coords", "cursorWhere", cursorSpots)
    d:Tip("Beside the player's: they move together. A spot of its own: placed and nudged apart from the player's.")
    d:Advanced(true)
    d:Color("Text colour", "coords", "color")
    d:Choice("Player: side", "coords", "side", {
        { "inside", "Inside the map" }, { "outside", "Outside the map" },
    })
    d:Choice("Cursor: side", "coords", "cursorSide", {
        { "same", "As the player's" }, { "inside", "Inside the map" }, { "outside", "Outside the map" },
    })
    d:Tip("Only for a spot of its own; beside the player's it sits on the same line.")
    d:Slider("Player: nudge left / right", -100, 100, 1, "coords", "offsetX", "%d px", "none")
    d:Slider("Player: nudge down / up", -100, 100, 1, "coords", "offsetY", "%d px", "none")
    d:Slider("Cursor: nudge left / right", -200, 200, 1, "coords", "cursorX", "%d px", "none")
    d:Tip("From its own spot, or from beside the player's.")
    d:Slider("Cursor: nudge down / up", -100, 100, 1, "coords", "cursorY", "%d px", "none")
    d:Slider("Dark backing", 0, 100, 5, "coords", "backing", "%d%%", "none")
    d:Check("Text shadow", "coords", "shadow")
    d:Check("Text outline", "coords", "outline")
    d:Tip("A dark outline round the letters: easier to read without the backing.")
    d:Advanced()
    d:Requires()
end }

-- The keys, in four groups (Keys.lua's ns.KeyGroups, as in the game's own Keybindings list): the few worth
-- having, each with a line saying what it gives; what a controller needs; the rest; and a key a layer, folded.
-- The first row is the game's own Toggle Battlefield Map: shown and set here, not ours (the settings pass,
-- 2026-11-14: the key that matters most was not on the page).
PAGES[#PAGES + 1] = { key = "keys", label = "Key bindings", build = function(p)
    local w = Column(p, 0, 0, CONTENT_W)
    w:Note("Click a button, then press the key you want. Shift, Ctrl and Alt work too. Escape cancels, right-click clears. A key that was used for something else moves here.")
    w:Note("These are the game's own key bindings, so they're also in Esc > Options > Keybindings, under Waymark.")
    for _, g in ipairs(ns.KeyGroups and ns.KeyGroups() or {}) do
        w:Header(g.title)
        if g.note then w:Note(g.note) end
        for _, k in ipairs(g) do
            w:KeyBind(k[2], k[1])
            if k[3] then w:Note(k[3], nil, nil, nil, 16) end
        end
        -- (Waymark's quest log has no key of its own: it opens on the game's quest log key, by two ticks
        -- on its own tab. Nothing on this page said so, and the user looked for it here, 2026-11-16.)
        if g.title == "The keys worth having" and ns.db.questlog then
            w:Note("Waymark's quest log needs no key of its own: it opens on your quest log key (L).")
            w:Button("Go to: Open it with the quest log key", function() ns.ShowOption("questlog", "keyL") end)
        end
    end
end }

PAGES[#PAGES + 1] = { key = "quests", label = "Quests", build = function(p)
    local a = Column(p, 0, 0, HALF)
    local questie = ns.QuestieArt()
    local function Docked() return ns.Docked and ns.Docked() end
    -- (our pins, in whose look: the givers' and turn-ins' Icons; spots always take Questie's)
    local function OurPins()
        local spots = ns.IsShown("spots") or ns.SpotsAsGround()
        if not (spots or ns.IsShown("questie") or ns.IsShown("turnins")) then return "No quest pins on" end
        if not questie then return "Waymark's pins" end
        if ns.db.questie.iconSet ~= "modern" then return "Waymark's pins with Questie's icons" end
        return spots and ns.SpotsQuestieArt() and "Waymark's pins, with Questie's look" or "Waymark's pins"
    end
    if questie then
        a:Header("Quest tooltips")
        a:Radio("questie", "tooltip", {
            { false, "Waymark's", "Waymark's tooltips on its pins." },
            { true, "Questie's", "Questie's tooltips on Waymark's pins. Right-click still gives details." },
        })
    else
        a:Header("Showing now")
    end
    local rows = { { function() return Docked() and "Map and minimap" or "The map" end, OurPins } }
    if questie then
        rows[2] = { function() return Docked() and "Questie's pins" or "Round minimap" end,
            function() return Docked() and "Hidden while docked" or "Questie's pins, by its own settings" end }
        rows[3] = { "Tooltips", function() return ns.db.questie.tooltip and "Questie's" or "Waymark's" end }
    end
    a:StatusBox(questie and "Showing now" or nil, rows, ns.FOREVER
        and "The game's own ! and ? still show on the minimap. Turn off Track Quests in the minimap's tracking menu to hide them." or nil)
    a:Header("Which pins")
    a:CheckWith("Quest givers", ns.QuestGiversOn, function(v)
        ns.SetQuestGivers(v)
        ns.RefreshControls()
    end, nil, ns.ToggleIcon("questie"), { { "questie", "shown" }, { "turnins", "shown" } })
    a:Tip("Where you pick quests up and hand them in.")
    -- (one tick for both: the two rows for pick-ups and turn-ins alone are out of the settings, "1 toggle is
    -- enough for all of these right?", the user 2026-11-15. The two settings stay, and the map's own
    -- Turn-ins button still switches that half.)
    a:CheckWith("Quest objectives", ns.ObjectivesOn, function(v)
        ns.SetObjectives(v)
        ns.RefreshControls()
    end, nil, ns.ToggleIcon("objview"))
    a:Tip("Where your quest mobs, items and places are.")
    local looks = {}
    looks[#looks + 1] = { "waymark", "Waymark's" }
    if ns.QuestieArt() then looks[#looks + 1] = { "questie", "Questie's" } end
    if ns.FOREVER then looks[#looks + 1] = { "yours", "Blizzard's" } end
    if #looks > 1 then
        a:Choice("Look", nil, nil, looks, ns.ObjectiveLook, function(v)
            ns.SetObjectives(ns.ObjectivesOn(), v)
            ns.RefreshControls()
        end)
        a:Tip("Waymark's: coloured dots where the mobs are, or icons (below). Questie's: Questie's icons, with your Questie settings. Blizzard's: the game's own markers and quest areas.", "With advanced settings on, each layer has its own switch.")
    end
    a:Requires(function() return ns.ObjectiveLook() == "waymark" end)
    a:CheckWith("Objective icons", function() return ns.db.objectivePins end, function(v)
        ns.SetObjectivePins(v)
        ns.RefreshControls()
    end, nil, ns.ToggleIcon("spots"))
    a:Tip("Icons instead of dots: a sword or a bag on each spot.")
    a:Requires()
    a:Advanced(true)
    a:Advanced()
    a:Header("Look of givers and turn-ins", ns.ToggleIcon("questie"))
    a:Requires("questie", "shown")
    a:Check("Colour by quest difficulty", "questie", "color")
    a:CheckWith("Low-level (grey) quests", ns.GetTrivialQuests, ns.SetTrivialQuests)
    a:Tip("Grey quest givers: quests far below your level.")
    a:Button("Show hidden quests again", function()
        if ns.UnhideQuests then ns.UnhideQuests() end
    end)
    a:Tip("Right-click a quest giver and pick hide to hide its quests; this brings them all back (also /waymark unhide).")
    a:Requires()
    -- (one look for both: turn-ins copy these, ns.ShareQuestLook)
    a:Requires(function() return ns.IsShown("questie") or ns.IsShown("turnins") end)
    a:Advanced(true)
    a:Slider("Opacity", 0, 1, 0.05, "questie", "alpha")
    a:Slider("Size", 0.2, 2, 0.05, "questie", "scale")
    a:Choice("Icons", "questie", "iconSet", {
        { "questie", "Questie's" }, { "modern", "Modern" },
    })
    if questie then
        a:Note("Changes the icons only. The pins stay where Waymark puts them.")
    else
        a:Tip("Questie's: its round icons where Questie is installed; without it, the modern \"!\" and \"?\".")
    end
    a:Advanced()
    a:Check("Quest progress on tooltips", "questie", "unitTips")
    a:Tip("Hover a mob or item your quests need to see the quest and your progress (Kobold Vermin slain: 3/10). With Questie installed, Questie shows this instead.")
    a:Requires()
    a:Advanced(true)
    -- (the pins of Waymark's look with Objective icons, and of Questie's: whose icons is the Look's to say)
    a:Header("Objective pins", ns.ToggleIcon("spots"))
    a:Requires("spots", "shown")
    a:Slider("Opacity", 0, 1, 0.05, "spots", "alpha")
    a:Slider("Size", 0.2, 2, 0.05, "spots", "scale")
    a:Check("A colour per quest", "spots", "color")
    a:Tip("Each quest gets its own colour, so you can tell quests apart.")
    a:Slider("Spots of one objective at least", 0, 150, 5, "spots", "spacing", "%d yd apart", "off")
    a:Tip("Mobs that stand close together share one pin.")
    a:Slider("At most, per objective", 0, 40, 1, "spots", "maxPer", "%d pins", "no limit")
    a:Tip("With more spots than this, only the most spread-out ones show, so the whole area is still covered.")
    a:Requires()
    a:Header("Objective dots", ns.ToggleIcon("ground"))
    a:Tip("Coloured areas on the map where your quest mobs and items are. Hover one to see what's there and which quest it's for.")
    a:Requires("ground", "shown")
    a:Slider("Opacity", 0, 1, 0.05, "ground", "alpha")
    a:Check("Coloured", "ground", "color")
    a:Tip("Off: every quest's ground in one red.")
    a:Requires(function() return ns.db.ground.shown and ns.db.ground.color end)
    a:Choice("Colour by", "ground", "colorBy", { { "quest", "Each quest" }, { "type", "Quest type" } })
    a:Tip("Each quest: a colour per quest. Quest type: kill red, gather green, use blue, explore purple, escort teal.")
    a:Requires("ground", "shown")
    a:Check("Fade other quests while one is lit", "ground", "hush")
    a:Tip("Hovering a quest in the tracker, the log or on the map highlights it in gold. With this on, your other quests fade while it's highlighted.")
    a:Check("One dot for quests not in view", "ground", "quiet")
    a:Tip("Shows all the dots only for the quest you're hovering or have open. Other quests get one dot each. Off: every dot for every quest.")
    a:Requires()
    if ns.FOREVER then
        a:Header("Blizzard's objective markers", ns.ToggleIcon("questMarkers"))
        if ns.QuestieKeepsObjectivesOff() then a:Note("Questie's theme keeps these and the quest areas off. Choose its Blizzard theme to use them.") end
        a:Check("Show", "objectives", "shown")
        a:Requires("objectives", "shown")
        a:Slider("Opacity", 0, 1, 0.05, "objectives", "alpha")
        a:Slider("Size", 0.2, 2, 0.05, "objectives", "scale")
        a:Requires()
        a:Header("Blizzard's quest areas (blue zones)", ns.ToggleIcon("questAreas"))
        a:Check("Show", "areas", "shown")
        a:Requires("areas", "shown")
        a:Slider("Opacity", 0, 1, 0.05, "areas", "alpha")
        a:Requires()
    end
    a:Header("Pin filters")
    a:Check("Objectives of tracked quests only", "outside", "trackedOnly")
    a:Tip(ns.FOREVER and "Objective spots and the game's objective markers only for the quests you track." or "Objective spots only for the quests you track.")
    a:Button("Go to: Hide pins in unexplored land", function() ns.ShowOption("explore", "hideQuests") end)
    a:Header("Quest data")
    a:Choice("Quests from", "questie", "source", {
        { "own", "Waymark's own" }, { "both", "Waymark's, filled from QuestieDB" }, { "questiedb", "QuestieDB" },
    })
    a:Tip("Waymark's own: built in, no other addon needed. Filled from QuestieDB: Waymark's data, with QuestieDB filling the gaps. QuestieDB: QuestieDB only. The last two need QuestieDB installed. Townsfolk use the same source. Changing it needs a /reload.")
    a:Button("Reload now", function() ReloadUI() end)

    a:Advanced()

    local b = Column(p, HALF, 0, HALF)
    b:Header("Learned quest givers")
    b:Check("Show", "learned", "shown")
    -- (the quest data in use, by name: "Quests from" above; a change takes a /reload,
    -- which builds this page again)
    local from = ns.QuestSourceName and ns.QuestSourceName()
    local data = from == "QuestieDB" and "QuestieDB" or from == "both" and "Waymark's data and QuestieDB" or "Waymark's data"
    b:Tip("Quest givers you've talked to are remembered, on all your characters. Fills in quests " .. data .. " is missing, like Forever's new ones.")
    b:Requires("learned", "shown")
    b:Advanced(true)
    b:Choice("Which quests", "learned", "mode", {
        { "gaps", "Only ones " .. data .. " lacks" }, { "all", "All you've learned" },
    })
    b:Tip("\"Only ones " .. data .. " lacks\" fills its gaps. \"All you've learned\" shows the rest too, but never a second pin for a quest Quest givers or Turn-ins already show.")
    b:Slider("Opacity", 0, 1, 0.05, "learned", "alpha")
    b:Slider("Size", 0.2, 2, 0.05, "learned", "scale")
    b:Requires()
    b:Check("Keep learning", "learned", "record")
    b:Advanced()
    b:Button("Your learned quests", function() if ns.ToggleLearnedWindow then ns.ToggleLearnedWindow() end end)
    b:Tip("A list of everything you've learned, by zone. You can share it or import someone else's from there.", "Also: /waymark learned")
    b:Live(function()
        if not ns.LearnedStats then return "" end
        local givers, quests, here, mobs = ns.LearnedStats()
        return string.format("Known: %d quest givers, %d quests (%d on this map), %d mob spots", givers, quests, here, mobs or 0)
    end)
    b:Button("Forget all of it (Shift-click)", function()
        if IsShiftKeyDown() then ns.ForgetLearned() end
    end)
    b:Note("Forever's new quests are still being gathered. If you'd like to help, share what you've learned from the Setups page.")
end }

-- As told (AsTold.lua, AsToldPanel.lua; out of the Lab for 1.3): a tab of its own among the quest pages, and a
-- line on Start here beside the other ways to quest. The page follows its session's mock-up
-- (mockups/as-told-settings.html): the panel, the places on the map, how the panel is worked, and the two
-- switches that leave only the giver's words. Only in a build that carries it (BuildPanel drops it otherwise).
PAGES[#PAGES + 1] = { key = "told", label = "As told", build = function(p)
    local a = Column(p, 0, 0, CONTENT_W)
    a:Note("Your quest as its giver told it: the story on a small panel, and on the map only the places they named.")
    a:Header("As told")
    a:Check("Show", "told", "on")
    a:Tip("A small panel with your quest in the quest giver's own words. The map marks the places they named, and nothing else.", "Also: /told")
    a:Requires("told", "on")
    a:Check("The story panel", "told", "panel")
    a:Tip("Your current quest in the giver's own words. It shows a line or two until you hover it.")
    -- (the panel is always on its dark glass: "text only, no backdrop" removed 2026-11-15, the user: "unusable")
    -- (the panel's own rows grey out with the panel off: the user, 2026-11-15)
    local function PanelOn() return ns.db.told.on and ns.db.told.panel ~= false and true or false end
    -- ("pencil" is the seen land's word now: the user, 2026-11-15)
    a:Check("Mark the places on the map", "told", "map")
    a:Tip("A mark for each place the giver named, and nothing more.")
    a:Requires(function() return ns.db.told.on and ns.db.told.map ~= false and true or false end)
    a:CheckWith("Name the places", function() return ns.db.told.names ~= false end, function(v)
        ns.db.told.names = v and true or false
        ns.OnSettingChanged("told", "names")
    end)
    a:Tip("The place's name written by its mark. Off: the marks alone.")
    a:Requires("told", "on")
    a:Advanced(true)
    a:Slider("The marks' opacity", 20, 100, 5, "told", "alpha", "%d%%")
    a:Slider("Lettering size", 8, 18, 1, "told", "size", "%d")
    a:Advanced()
    a:Requires()
    a:Header("Using the panel")
    a:Note("Hover: the full text, and what you need to do.")
    a:Note("Click: keep it open, or shrink it again.")
    a:Note("Wheel: your other quests; click one to read it.")
    a:Note("Right-click: its menu. Hold a quest, hide it for now, fade it out in combat.")
    a:Note("Drag: moves it.")
    -- (the panel's own menu has these three; here for whoever looks in the settings first. Its place and size
    -- are AsToldPanel.lua's: ns.ToldPanelPlace)
    a:Requires(PanelOn)
    a:Button("Put the panel back", function()
        if ns.ToldCfg then ns.ToldCfg().panelAt = nil end
        if ns.ToldPanelPlace then ns.ToldPanelPlace() end
    end)
    a:Tip("Where it stood before you moved it, at the right of the screen.")
    -- (one size for letters, width and glass together: the user, 2026-11-15, "Yes, one slider")
    a:SliderWith("Panel size", 80, 160, 5,
        function() return (ns.ToldCfg and tonumber(ns.ToldCfg().scale)) or 100 end,
        function(v)
            if ns.ToldCfg then ns.ToldCfg().scale = v end
            if ns.ToldPanelPlace then ns.ToldPanelPlace() end
        end, "%d%%")
    a:Tip("Makes the whole panel and its text bigger or smaller.")
    a:Choice("In combat", nil, nil, { { "stay", "Stays" }, { "aside", "Fades out" } },
        function() return ns.ToldCfg and ns.ToldCfg().fight == "aside" and "aside" or "stay" end,
        function(v) if ns.ToldCfg then ns.ToldCfg().fight = v == "aside" and "aside" or nil end end)
    a:Tip("Fades out: the panel goes faint while you are in combat and comes back after.")
    a:Requires()
    a:Header("Which quest it shows")
    a:Note("The panel shows the quest for the place you're in, or else the one you picked up last. To keep one quest on it, right-click the panel and pick \"hold this quest\". It stays until you turn it in or pick \"back to automatic\".")
    -- (a button here, "Follow the quest I'm on", did what the panel's menu does: out, the user 2026-11-15)
    a:Header("Go by the words alone")
    a:Note("As told is for reading your way to a quest. If that's all you want, turn these two off. They're the same switches as on their own tabs.")
    a:CheckWith("Quest objectives on the map", function() return ns.ObjectivesOn() end,
        function(v) ns.SetObjectives(v) ns.RefreshControls() end)
    a:Tip("Untick to keep only what the giver named.")
    a:Check("Quest tracker", "tracker", "shown")
end }

PAGES[#PAGES + 1] = { key = "tracker", label = "Quest tracker", build = function(p)
    local T = function() return ns.db.tracker end
    local a = Column(p, 0, 0, HALF)
    a:Header("Quest tracker", ns.ToggleIcon("tracker"))
    a:Check("Show the quest tracker", "tracker", "shown")
    a:Tip("Your tracked quests with something to do in this zone, and their objectives.", "Right-click: view details, find on map. Shift-click: stop tracking, or with chat open, link it. Hover: its areas light up. Wheel: scroll.")
    -- (hideGameTracker: false, true (while ours shows) or "always")
    a:Choice("The game's quest tracker", "tracker", "hideGameTracker", {
        { "show", "Shown" }, { "with", "Hidden while this one shows" }, { "always", "Hidden always" },
    }, function()
        local v = T().hideGameTracker
        return v == "always" and "always" or v and "with" or "show"
    end, function(v)
        T().hideGameTracker = v == "always" and "always" or v == "with"
        ns.OnSettingChanged("tracker", "hideGameTracker")
    end)
    a:Tip("The game's own tracker, under the minimap. Hidden while this one shows: back when the map or this tracker closes. Hidden always: gone even then.")
    a:Requires("tracker", "shown")
    a:Choice("Click a quest", "tracker", "click", {
        { "fold", "Fold its objectives" }, { "details", "Open its details" }, { "map", "Open the game's map" },
    }, function() return T().click or "fold" end, function(v)
        T().click = v ~= "fold" and v or nil
    end)
    a:Tip("Its details: Waymark's quest log. The game's map: the world map with the quest beside it; with a controller, its objectives fold instead.")
    a:Check("Attach to the map", "tracker", "detached", true)  -- (ticked: not detached)
    a:Tip("Attached, it moves, fades and hides with the map. Off, it goes anywhere and stays open when the map closes.", "Off: drag its edge or zone name to move it, its corner to size it.")
    a:Requires(function() return T().shown and T().detached end)
    a:Check("Lock it in place", "tracker", "locked")
    a:Tip("No moving or sizing it. Also in the menu on its zone name (right-click).")
    a:Requires(function() return T().shown and not T().detached end)
    a:Choice("Where", "tracker", "attach", {
        { "below", "Below the map" }, { "above", "Above the map" }, { "left", "Left of the map" },
        { "right", "Right of the map" },
    })
    a:Requires("tracker", "shown")
    a:Slider("Width", 140, 800, 5, "tracker", "width", "%d")
    a:Tip("Beside the map (left or right of it) or detached. Above or below the map it's as wide as the map.")
    a:Choice("Order", "tracker", "sort", {
        { "distance", "Nearest first" }, { "alpha", "Alphabetically" }, { "area", "By sub-zone name" },
        { "level", "By level" }, { "log", "As in the quest log" },
    })
    a:Tip("Nearest first: quests about as near keep their places, so the list doesn't jump about as you walk.")
    a:Check("Finished quests last", "tracker", "finishedLast")
    a:Check("Buttons for quest items", "tracker", "itemButtons")
    a:Check("Sub-zone headings", "tracker", "groupByArea")
    a:Tip("Each quest under the area its nearest objective is in (Kharanos, Coldridge Valley...); quests with nothing here go under Elsewhere.")
    a:Check("Objectives under each quest", "tracker", "objectives")
    a:Indent(true)
    a:Check("Hide finished objectives", "tracker", "hideDoneObjectives")
    a:Check("Counts in a column at the right", "tracker", "countColumn")
    a:Tip("On: \"Harvest Watcher  13/20\", with the counts lined up on the right. Off: \"- Harvest Watcher slain: 13/20\", as the game writes it.")
    a:Requires(function() return T().shown and T().countColumn ~= false end)
    a:Choice("Finished objectives", "tracker", "doneCount", {
        { "count", "Grey, count kept" }, { "tick", "Grey, a tick for the count" },
    })
    a:Requires("tracker", "shown")
    a:Indent()
    a:Check("Name who takes a finished quest in", "tracker", "turninName")
    a:Tip("A finished quest shows who to turn it in to and where. Needs QuestieDB. Off: \"Ready for turn-in\".")
    a:Requires(function() return T().shown and T().turninName ~= false end)
    a:Indent(true)
    a:Choice("As", "tracker", "turninStyle", {
        { "place", "Gryan Stoutmantle, Sentinel Hill" }, { "prefix", "Turn in: Gryan Stoutmantle" },
        { "where", "Sentinel Hill" },
    })
    a:Indent()
    a:Requires("tracker", "shown")
    a:Advanced(true)
    a:Slider("Tallest before it scrolls", 80, 600, 10, "tracker", "maxHeight", "%d px")
    a:Tip("A longer list scrolls with the mouse wheel.")
    a:Advanced()
    a:Requires()

    local b = Column(p, HALF, 0, HALF)
    b:Header("Which quests")
    b:Requires("tracker", "shown")
    b:Choice("Finished quests", "tracker", "finished", {
        { "show", "Show them" }, { "hide", "Hide them" }, { "only", "Only them" },
    })
    b:Check("Hide low-level (grey) quests", "tracker", "hideGrey")
    b:Check("Hide elite quests", "tracker", "hideElite")
    b:Check("Hide dungeon and raid quests", "tracker", "hideDungeon")
    b:Check("Hide group quests", "tracker", "hideGroup")
    b:Check("Only quests you track", "tracker", "onlyTracked")
    b:Tip("Only quests you've tracked. Off: every quest you can do in this zone.")
    b:Check("Track quests as you accept them", "tracker", "autoTrack")
    b:Tip("Tracks every quest as soon as you accept it.")
    b:Check("Hide it where there are none", "tracker", "hideEmpty")
    b:Choice("Quests in other zones", "tracker", "otherZones", {
        { "always", "Always" }, { "continent", "Only when the map shows a continent" }, { "off", "Never" },
    })
    b:Tip("Tracked quests from other zones, listed under their zone's name after this zone's quests.")
    b:Requires()

    -- the look, under both columns
    local y = math.min(a.y, b.y) - 10
    local pct = function(v) return string.format("%d%%", v * 100 + 0.5) end
    local d = Column(p, 0, y, HALF)
    d:Header("Look")
    d:Requires("tracker", "shown")
    d:Check("Same text as the quest log", "tracker", "textAsLog")
    d:Tip("Uses the same fonts and sizes as Waymark's quest log. Off: set them below.")
    d:Requires(function() return T().shown and not T().textAsLog end)
    d:Slider("Quest name size", 8, 20, 1, "tracker", "fontSize", "%d")
    d:Requires("tracker", "shown")
    d:TextPart("Sub-zone headings", "tracker", "textSub")
    d:Tip("The sub-zone headings over its quests (and Elsewhere). Its own either way. ", FONT_TIP)
    d:Check("Quest icons", "tracker", "icons")
    d:Tip("A small icon for what each objective wants: kill, collect, use, an event, turn in. Questie's where it's installed, else the game's.")
    d:Check("Titles coloured by difficulty", "tracker", "levelColors")
    d:Tip("Off: every title in gold, as in the game's tracker.")
    d:Check("Levels in a column of their own", "tracker", "levelColumn")
    d:Tip("\"12+  The Killing Fields\": the level (with + for elite or group, D dungeon, R raid) in a column before the title, so the titles line up. Off: \"[12+] The Killing Fields\".")
    d:Requires(function() return T().shown and T().levelColumn ~= false end)
    d:Indent(true)
    d:Check("Gold titles, coloured levels", "tracker", "goldTitles")
    d:Indent()
    d:Requires("tracker", "shown")
    d:Check("Quiet sub-zone headings", "tracker", "quietHeadings")
    d:Tip("Sub-zone headings in dim capitals with a thin rule, so they stand apart from the quest titles.")
    d:Check("Flash an objective as it counts up", "tracker", "flashProgress")
    d:Tip("A line flashes white when you get a kill or an item for it, or when the quest is done.")
    d:Advanced(true)
    d:Requires(function() return T().shown and not T().textAsLog end)
    d:Choice("Quest title font", "tracker", "titleFont", ns.FontChoices)
    d:Tip("", FONT_TIP)
    d:Choice("Objective font", "tracker", "textFont", ns.FontChoices)
    d:Tip("", FONT_TIP)
    d:Slider("Zone name size", 8, 24, 1, "tracker", "headerSize", "%d")
    d:Slider("Objective size", 8, 18, 1, "tracker", "objSize", "%d")
    d:Choice("Outline", "tracker", "outline", {
        { "none", "None" }, { "outline", "Thin" }, { "thick", "Thick" },
    })
    d:Requires("tracker", "shown")
    d:Check("Drop shadow", "tracker", "shadow")
    d:Check("Gold rule under the zone name", "tracker", "headerArt")
    d:Advanced()
    d:Requires()
    local e = Column(p, HALF, y, HALF)
    e:Header("Spacing and fading")
    e:Requires("tracker", "shown")
    e:Slider("Background opacity", 0, 1, 0.05, "tracker", "bgAlpha", pct, "none")
    e:Slider("Soft shade behind the text", 0, 1, 0.05, "tracker", "textShade", pct, "none")
    e:Advanced(true)
    e:Slider("Between lines", 0, 8, 1, "tracker", "lineGap", "%d px")
    e:Slider("Between quests", 0, 20, 1, "tracker", "questGap", "%d px")
    e:Advanced()
    e:Check("Fade when the mouse isn't on it", "tracker", "fadeOut")
    e:Requires("tracker", "fadeOut")
    e:Advanced(true)
    e:Slider("Faded to", 0, 100, 5, "tracker", "fadeAlpha", "%d%%")
    e:Advanced()
    e:Requires()
    -- its border: the map border's styles
    e:Header("Border")
    e:Requires("tracker", "shown")
    if ns.FramesRows then ns.FramesRows(e, "tracker") end   -- (a frame set round it: from Header & border, 2026-11-16)
    -- (Wood and Gold trimmed from the tracker's list, the user 2026-11-15: "Gold is just classic dialog with
    -- a tint". Still drawn for a player who has one saved, and listed for them alone so the box is not blank)
    local styles = { { "map", "Same as the map's" }, { "dialog", "Classic dialog" }, { "tooltip", "Tooltip" },
                     { "line", "Thin line" }, { "none", "None" } }
    local had = ns.db.tracker.borderStyle
    if had == "gold" then table.insert(styles, 3, { "gold", "Gold" }) end
    e:Choice("Style", "tracker", "borderStyle", styles)
    e:Tip("Same as the map's: copies the map's border so the two match. The settings below are for the other styles.")
    e:Advanced(true)
    e:Check("Joined to the map's border", "tracker", "joinBorders")
    e:Tip("When attached, the tracker and the map share one border. Doesn't work with the game's own map border.")
    e:Slider("Thickness", 0.5, 2, 0.05, "tracker", "borderSize", "%.2fx")
    e:Slider("Distance from the tracker", -12, 20, 1, "tracker", "borderGap", "%d px")
    e:Choice("Colour", "tracker", "borderColor", {
        { "natural", "As drawn" }, { "gold", "Gold" }, { "bronze", "Bronze" },
        { "silver", "Silver" }, { "dark", "Dark" }, { "class", "My class colour" },
    })
    e:Advanced()
    e:Requires()
end }

-- the quest window (Tracker.lua): how it opens, where it sits, what's on it
PAGES[#PAGES + 1] = { key = "questlog", label = "Quest log", build = function(p)
    local q = function() return ns.db.questlog end
    local attached = function() return q().shown and not q().detached end
    local a = Column(p, 0, 0, HALF)
    a:Header("Quest log")
    a:Check("Use Waymark's quest log", "questlog", "shown")
    a:Tip("A quest's page beside the map: objectives, description, rewards and buttons. Off: the game's quest log instead.", "Right-click a quest in the tracker: view details.")
    a:Requires("questlog", "shown")
    a:Check("Also from its pins on the map", "questlog", "fromPins")
    a:Tip("Clicking a quest's pin or area on the map opens its page. Highlighting the quest moves to the right-click menu.")
    -- (with the window's own settings, not its buttons: moved here 2026-11-03)
    a:Check("Light up its spots and areas while open", "questlog", "glow")
    a:Tip("Highlights the open quest's spots and turn-in on the map, like hovering it in the tracker.")
    a:Check("Open it with the big map", "questlog", "withBig")
    a:Tip("The quest log opens beside the map when the map goes big, and closes when it goes small. The big map leaves room for it.")
    a:Check("Open it with the quest log key", "questlog", "keyL")
    a:Tip("While the map shows, your quest log key (L) opens this window instead of the game's quest log.")
    a:Check("Replace the game's quest log", "questlog", "replaceGame")
    a:Tip("Your quest log key opens this window, map or not, and the game's quest log stays closed.")
    -- (your whole log at the window's top is always there now: no switch, 2026-11-03)
    a:Check("Your zone's quests first", "questlog", "listHereFirst")
    a:Tip("Lists your quests at the top of the window. Click a zone to fold it, Shift-click to track or untrack all its quests. Drag the line under the list to resize it.")
    a:Check("Fold other zones at first", "questlog", "listFoldOthers")
    a:Tip("The zone you're in starts open, the others folded. A zone you fold or open yourself stays that way (until you change this).")
    a:Check("Levels in difficulty colours", "questlog", "listLevelColors")
    a:Tip("Grey, green, yellow, orange, red, as the game colours quests, toned darker on the parchment.")
    -- (the log's share: dragging the line under it; Escape always closes the window. No settings, 2026-11-03)
    a:Requires()

    a:Header("Placement")
    a:Requires("questlog", "shown")
    a:Check("Attach to the map", "questlog", "detached", true)  -- (ticked: not detached)
    a:Tip("Attached, it sits beside the map. Off, you place it anywhere: drag its top bar to move it, its bottom-right corner to scale it, its bottom edge for its height.")
    a:Requires(attached)
    a:Choice("Side", "questlog", "side", {
        { "auto", "Whichever has room (right first)" }, { "right", "Right of the map" }, { "left", "Left of the map" },
    })
    a:Check("Match the map's height", "questlog", "matchHeight")
    a:Tip("As tall as the map. Off: set its height below, or drag its bottom edge.")
    a:Requires(function() return attached() and q().matchHeight end)
    a:Indent(true)
    a:Check("Reach down past the tracker", "questlog", "pastTracker")
    a:Tip("With the tracker below the map: down to the tracker's bottom.")
    a:Indent()
    a:Requires(attached)
    a:Advanced(true)
    a:Check("Shadow in the seam", "questlog", "seam")
    a:Slider("Gap from the map", -6, 20, 1, "questlog", "gap", "%d px")
    a:Advanced()
    a:Requires(function() return q().shown and (q().detached or not q().matchHeight) end)
    a:Slider("Height", 260, 900, 10, "questlog", "height", "%d")
    a:Tip("When it doesn't match the map's height, or is detached.")
    a:Requires("questlog", "shown")
    a:Slider("Size", 0.6, 2, 0.05, "questlog", "scale", "%.2fx")
    a:Tip("1x: as big as the rest of your interface. Detached, its corner grip sets this too.")
    a:Requires(function() return q().shown and q().detached end)
    a:Check("Only while the map shows", "questlog", "onlyWithMap")
    a:Tip("Off: it stays open when the map closes, until you close it.")
    a:Check("Lock it in place", "questlog", "locked")
    -- (lost off the screen: back where the game's quest log opens, still on its own)
    a:Button("Reset position", function()
        q().pos = { 16, UIParent:GetHeight() - 104 }
        ns.OnSettingChanged("questlog", "detached")
        ns.RefreshControls()
    end)
    a:Tip("Lost it off the screen? Back to the top left, where the game's quest log opens.")
    a:Requires()

    local b = Column(p, HALF, 0, HALF)
    b:Header("On the page")
    b:Requires("questlog", "shown")
    b:Check("Objectives", "questlog", "objectives")
    b:Check("Description", "questlog", "description")
    b:Check("Rewards panel", "questlog", "rewards")
    b:Check("Level and type by the title", "questlog", "levelTag")
    b:Tip("[12] for its level; Elite, Dungeon, Raid or Group where it's one.")
    b:Check("Quest chain", "questlog", "chain")
    b:Tip("Every step of the quest's chain, with the ones you've done ticked. Click a step you don't have yet to read about it. Needs QuestieDB.")
    -- (QuestWords.lua, out of the Lab for 1.3: only in a build that carries it)
    if ns.QuestWords then
        b:Check("The giver's words for steps you don't have yet", "questlog", "chainWords")
        b:Tip("For a chain step you don't have yet, shows what its quest giver says.")
        b.last.bfiDep = function() return ns.db.questlog.chain and true or false end
    end
    b:Check("Who gave it and who takes it", "questlog", "people")
    b:Tip("From QuestieDB: the names of the quest's giver and of who takes it in, with their zones.")
    b:Advanced(true)
    b:Check("Quest ID", "questlog", "questID")
    b:Advanced()
    b:Requires()

    -- (which of the page's four buttons show: fine-tuning, all four on in every preset)
    b:Advanced(true)
    b:Header("Buttons")
    b:Requires("questlog", "shown")
    b:Check("Abandon", "questlog", "abandon")
    b:Check("Share", "questlog", "share")
    b:Check("Track", "questlog", "track")
    b:Check("Focus", "questlog", "focus")
    b:Requires()
    b:Advanced()

    local pct = function(v) return string.format("%d%%", v * 100 + 0.5) end
    b:Header("Look")
    b:Requires("questlog", "shown")
    b:Choice("Page", "questlog", "paper", {
        { "parchment", "Parchment (Forever's quest log)" }, { "dark", "Dark, as the tracker" },
    })
    -- (the log list's look, here with the page's since 2026-11-03)
    b:Choice("Quest list", "questlog", "logStyle", {
        { "leather", "Leather" }, { "classic", "Classic dark list" }, { "parchment", "Plain parchment" },
    })
    b:Tip("The list of your quests at the top. Leather: a dark brown pane, cream text. Classic dark list: as the game's own log, gold titles on black. Plain parchment: the page's own colours (on the Dark page, the tracker's).")
    b:Requires(function() return q().shown and q().logStyle == "parchment" and q().paper == "dark" end)
    b:Check("Gold quest titles", "questlog", "listGoldTitles")
    b:Tip("With the Dark page: the quest titles in the game's gold, white when selected, instead of light grey.")
    b:Requires("questlog", "shown")
    b:Slider("Opacity", 0.3, 1, 0.05, "questlog", "alpha", pct)
    b:Advanced(true)
    b:Check("Fade when the mouse isn't on it", "questlog", "fadeOut")
    b:Requires("questlog", "fadeOut")
    b:Slider("Faded to", 0, 100, 5, "questlog", "fadeAlpha", "%d%%")
    b:Advanced()
    b:Requires()

    -- its frame: its own, or the map border's styles
    b:Header("Border")
    b:Requires("questlog", "shown")
    b:Choice("Style", "questlog", "borderStyle", Trimmed({
        { "own", "The quest log's own" }, { "dialog", "Classic dialog" },
        { "gold", "Gold" }, { "tooltip", "Tooltip" }, { "wood", "Wood" }, { "line", "Thin line" }, { "none", "None" },
    }, ns.db.questlog.borderStyle))
    b:Advanced(true)
    b:Slider("Thickness", 0.5, 2, 0.05, "questlog", "borderSize", "%.2fx")
    b:Slider("Distance from the window", -12, 20, 1, "questlog", "borderGap", "%d px")
    b:Choice("Colour", "questlog", "borderColor", {
        { "natural", "As drawn" }, { "gold", "Gold" }, { "bronze", "Bronze" },
        { "silver", "Silver" }, { "dark", "Dark" }, { "class", "My class colour" },
    })
    b:Advanced()
    b:Requires()

    -- each part of the window's text: font, size, outline (colours: the look); fine-tuning
    b:Advanced(true)
    b:Header("Quest log text")
    b:Note("Each part of the window's text: its font, size and a thin outline. The colours come from the log look and the page. The tracker can follow these too (Quest tracker page).")
    b:SubHeader("In the log list")
    b:Requires("questlog", "shown")
    -- (no outline on plain parchment with the Parchment page: it smudged the ink)
    local inkOk = function() return not (q().logStyle == "parchment" and q().paper ~= "dark") end
    b:TextPart("\"Quest Log\" heading", "questlog", "textHead", inkOk)
    b:Tip("The heading over the list, and its quest count. ", FONT_TIP)
    b:TextPart("Zone names", "questlog", "textZone", inkOk)
    b:Tip("The zone headings in the list (no outline on plain parchment).", FONT_TIP)
    b:TextPart("Quest names in the list", "questlog", "textQuest", inkOk)
    b:Tip("Each quest in the list, its level and (Complete) too. ", FONT_TIP)
    b:SubHeader("On the quest's page")
    b:Requires("questlog", "shown")
    b:TextPart("Quest title", "questlog", "textTitle")
    b:Tip("The quest's name at the top of its page. ", FONT_TIP)
    b:TextPart("Section headings", "questlog", "textSect")
    b:Tip("Description and Quest chain. ", FONT_TIP)
    b:TextPart("Quest details", "questlog", "textDetail")
    b:Tip("The short summary, the objectives and the description. ", FONT_TIP)
    b:TextPart("Small print", "questlog", "textSmall")
    b:Tip("Level and part of the chain, From and To, notes. ", FONT_TIP)
    b:TextPart("Quest chain steps", "questlog", "textChain")
    b:Tip("Each step of the chain (the level and \"in your log\" a little smaller).", FONT_TIP)
    b:Requires()
    b:Advanced()
end }

local function TypeCheck(col, label, key)
    col:CheckWith(label,
        function() return ns.db.townsfolk.types[key] end,
        function(v)
            ns.db.townsfolk.types[key] = v or nil
            ns.OnSettingChanged("townsfolk", "types")
        end, true)
end

PAGES[#PAGES + 1] = { key = "people", label = "Townsfolk", build = function(p)
    local types = ns.TOWNSFOLK_TYPES or { services = {}, vendors = {} }
    local trainers = { ["Class Trainer"] = true, ["Weapon Master"] = true, ["Portal Trainer"] = true }
    local a = Column(p, 0, 0, HALF)
    a:Header("Townsfolk", ns.ToggleIcon("townsfolk"))
    a:Check("Show", "townsfolk", "shown")
    a:Tip("Uses the same data as quests (Quests page), plus the townsfolk you've learned by talking to them.")
    a:Requires("townsfolk", "shown")
    a:Slider("Opacity", 0, 1, 0.05, "townsfolk", "alpha")
    a:Requires()
    -- which ones, and how big: by place
    a:Header("Which townsfolk, and how big")
    -- One list, and a switch for the place it is for: the open world, towns, capitals. It opens on the place
    -- you stand in, so a tick changes the map in front of you. (Towns and capitals had their own lists on the
    -- Towns page, behind advanced: a tick here did nothing in a town. "SO easily missed", the user 2026-11-15.)
    -- ns.folkPlace: the place picked on this page (nil: where you stand).
    local VIEW = { town = "townView", city = "cityView" }
    local function Standing()
        local map = BattlefieldMapFrame
        local onCity = map and map.GetMapID and ns.CITY_MAPS and ns.CITY_MAPS[map:GetMapID()]
        if onCity or (ns.InCityView and ns.InCityView()) then return "city" end
        if ns.InTownView and ns.InTownView() then return "town" end
        return "world"
    end
    local function Place() return ns.folkPlace or Standing() end
    local function Own() local v = VIEW[Place()] return v and ns.db[v].ownTypes and v or nil end
    local function List() local v = Own() return v and ns.TownTownsfolk(v) or ns.db.townsfolk end
    local function Changed(key) ns.OnSettingChanged(Own() or "townsfolk", key) end
    -- (three tabs, not a dropdown: "Dropdown is not hitting it for me", the user 2026-11-15. The Size under
    -- them is that place's, said by the tab: on its own above it changed with where you stood, unsaid.)
    local here = Standing()
    local tabs = {}
    local function TabLook()
        for _, b in ipairs(tabs) do
            local on = b.place == Place()
            if on then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(1, 0.82, 0) end
            b.under:SetShown(on)
        end
    end
    do
        local tx = a:Left() + 4
        for _, t in ipairs({ { "world", "The open world" }, { "town", "Towns" }, { "city", "Capitals" } }) do
            local b = CreateFrame("Button", nil, p)
            b.place = t[1]
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            b.text:SetText(t[2] .. (t[1] == here and "  |cff4ddf4d(you are here)|r" or ""))
            -- (the town view's and the city view's own icons, as on the map's buttons and the Towns tab)
            local icon = t[1] ~= "world" and ns.ToggleIcon and ns.ToggleIcon(t[1])
            if icon then
                local tex = b:CreateTexture(nil, "OVERLAY")
                tex:SetSize(16, 16)
                tex:SetPoint("LEFT", 8, 1)
                if not ns.SetIconArt(b, tex, icon) and icon:find("\\Icons\\", 1, true) then
                    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                b.text:SetPoint("LEFT", tex, "RIGHT", 5, 0)
                b:SetSize(b.text:GetStringWidth() + 24 + 21, 24)
            else
                b.text:SetPoint("CENTER", 0, 1)
                b:SetSize(b.text:GetStringWidth() + 24, 24)
            end
            b:SetPoint("TOPLEFT", p, "TOPLEFT", tx, a.y)
            b.under = b:CreateTexture(nil, "ARTWORK")
            b.under:SetColorTexture(1, 0.82, 0, 0.9)
            b.under:SetPoint("BOTTOMLEFT", 6, 0)
            b.under:SetPoint("BOTTOMRIGHT", -6, 0)
            b.under:SetHeight(2)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            b:SetScript("OnClick", function()
                ns.folkPlace = t[1]
                TabLook()
                ns.RefreshControls()
            end)
            tabs[#tabs + 1] = b
            tx = tx + b:GetWidth() + 6
        end
        TabLook()
        a.y = a.y - 32
    end
    a:SliderWith("Size", 0.2, 2, 0.05,
        function()
            local v = VIEW[Place()]
            return v and ns.db[v].sizes.townsfolk or ns.db.townsfolk.scale
        end,
        function(value)
            local v = VIEW[Place()]
            if v then
                ns.db[v].sizes.townsfolk = value
                ns.OnSettingChanged(v, "sizes")
            else
                ns.db.townsfolk.scale = value
                ns.OnSettingChanged("townsfolk", "scale")
            end
        end, "%.2fx")
    a:Tip("How big townsfolk are drawn in the place picked above.")
    a:Requires(function() return Place() ~= "world" end)
    a:CheckWith("The same kinds as the open world", function() return VIEW[Place()] ~= nil and not Own() end, function(on)
        local v = VIEW[Place()]
        if not v then return end
        ns.db[v].ownTypes = not on
        ns.OnSettingChanged(v, "ownTypes")
        ns.RefreshControls()
    end)
    a:Requires(function()
        if VIEW[Place()] then return Own() ~= nil end
        return ns.IsShown("townsfolk")
    end)
    local function Folk(label, key)
        a:CheckWith(label, function() return List().types[key] end, function(v)
            List().types[key] = v or nil
            Changed("types")
        end, true)
    end
    a:Grid(3)
    a:SubHeader("Trainers")
    Folk("Profession trainers", "professions")
    a:Indent(true)
    a:CheckWith("Only your professions", function() return List().myProfessionsOnly end, function(v)
        List().myProfessionsOnly = v and true or false
        Changed("myProfessionsOnly")
    end, true)
    a:Indent()
    for _, t in ipairs(types.services) do
        if trainers[t.key] then Folk(t.label, t.key) end
    end
    a:SubHeader("Services")
    for _, t in ipairs(types.services) do
        if not trainers[t.key] then Folk(t.label, t.key) end
    end
    a:SubHeader("Vendors")
    for _, t in ipairs(types.vendors) do Folk(t.label, t.key) end
    a:Grid()
    a:Advanced(true)
    a:Requires()
    a:Choice("A spirit healer is drawn as", "townsfolk", "graveMark", {
        { "stone", "A headstone" }, { "game", "The game's icon" },
    })
    a:Advanced()
    a:Note("Food, drink and ammo follow your level: no more than 20 levels below it.")

    -- merging and learned townsfolk (Townsfolk.lua)
    local m = Column(p, 0, nil, HALF)
    m:Header("Less clutter")
    m:Requires("townsfolk", "shown")
    m:Slider("Merge same type within", 0, 100, 5, "townsfolk", "mergeYards", "%d yd", "off")
    m:Tip("Townsfolk of the same type this close together share one pin; its tooltip lists them all. Off: one pin each.")
    m:Check("Different types too", "townsfolk", "mergeKinds")
    m:Tip("A smith, an armourer and a cook side by side share one pin as well, showing the first type in the list; its tooltip lists each of them.")
    m:Requires()
    local l = Column(p, HALF, nil, HALF)
    l:Header("Learned townsfolk")
    l:Check("Keep learning", "townsfolk", "record")
    l:Tip("Vendors, trainers and flight masters you talk to are remembered, on all your characters.")
    l:Check("Show them on the map", "townsfolk", "useLearned")
    l:Tip("Shows the ones you've learned too. No NPC is shown twice.")
    l:Live(function()
        if not ns.LearnedTownsfolkStats then return "" end
        local n, here = ns.LearnedTownsfolkStats()
        return string.format("Known: %d townsfolk (%d on this map)", n, here)
    end)
    l:Button("Forget all of them (Shift-click)", function()
        if IsShiftKeyDown() then ns.ForgetLearnedTownsfolk() end
    end)
end }

-- Boats, zeppelins and the tram (Transports.lua): a page of their own since 2026-11-13. They are ink on
-- the map, not pins, and were on the Townsfolk page before. (Forever releases only: tools/build_era_release.py)
PAGES[#PAGES + 1] = { key = "traversal", label = "Boats & zeppelins", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Boats & zeppelins")
    a:Check("Show", "transports", "shown")
    a:Tip("Inked on the map itself: the tram at its stops, and on a continent's map a dotted line along the way each boat and zeppelin goes.")
    a:Requires("transports", "shown")
    a:Check("Boats", "transports", "boats")
    a:Check("Zeppelins & skyships", "transports", "zeppelins")
    a:Check("The tram", "transports", "trams")
    a:Check("On the continent map too", "transports", "continent")
    a:Check("Dotted routes", "transports", "routes")
    a:Tip("On a continent's map, zoomed out: the sea lanes and where they go.")
    -- (Boats.lua, out of the Lab for 1.3: only in a build that carries it)
    if ns.BoatsRefresh then
        a:Check("Boats where they are", "transports", "live")
        a:Tip("Once you have ridden a boat or zeppelin, its ship is drawn on the map where the boat is now.")
        a:Check("A dotted wake behind them", "transports", "wake")
        a.last.bfiDep = function() return ns.db.transports.live and true or false end
        -- (the moving ships' own size: "Size" below never touched them, a player on CurseForge 2026-11-16)
        a:Slider("Ships & zeppelins: size", 0.5, 3, 0.05, "transports", "shipScale", "%.2fx")
        a.last.bfiDep = function() return ns.db.transports.live and true or false end
    end
    a:Check("Anchors & pennants", "transports", "marks")
    a:Tip("A small anchor at each pier and a pennant at each zeppelin tower.")
    a:Slider("Anchors, pennants & tram: size", 0.2, 2, 0.05, "transports", "scale")
    -- (nothing to size with the anchors off and the tram off)
    a.last.bfiDep = function() local t = ns.db.transports return (t.marks or t.trams) and true or false end
    a:Slider("Opacity", 0, 1, 0.05, "transports", "alpha")
    a:Requires()
end }

PAGES[#PAGES + 1] = { key = "group", label = "You & your group", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Player & group")
    a:Check("Show", "party", "shown")
    a:Tip("Hiding these also hides your own arrow: the game draws them together.")
    a:Slider("Opacity", 0, 1, 0.05, "party", "alpha")
    -- (docked over the minimap the arrow's size does not follow this: greyed there, and said so only then.
    -- "We know why, but they dont", the user 2026-11-15)
    local function NotDocked() return not (ns.Docked and ns.Docked()) end
    a:Requires(NotDocked)
    a:Slider("Player arrow", 0, 48, 1, "mapFrame", "arrowSize", "%d", "game default")
    a:Requires()
    if not NotDocked() then a:Note("The arrow's size can't be changed while the map is docked over the minimap.") end
    a:Check("Classic map arrow", "cave", "classicArrow")
    a:Tip("The classic world map's arrow for you, on the zone map and in caves.")
    a:Slider("Group icons", 0, 32, 1, "mapFrame", "groupSize", "%d", "game default")
    a:Header("Group members")
    a:Check("Dots in class colours", "party", "classColors")
    a:Check("Tooltips on hover", "party", "hover")
    a:Tip("Name, level, health and distance. Several members close together share one tooltip.")

    local b = Column(p, HALF, 0, HALF)
    b:Header("Line to party member", ns.ToggleIcon("line"))
    b:Check("Show", "line", "shown")
    b:Requires("line", "shown")
    b:Slider("Opacity", 0.1, 1, 0.05, "line", "alpha")
    b:Slider("Thickness", 1, 8, 1, "line", "thickness", "%d")
    b:Requires()
end }

-- rares, and gathering nodes (TomTom's waypoints: left
-- off the pages until they show on this map; Waypoints.lua and its settings are kept)
PAGES[#PAGES + 1] = { key = "rares", label = ns.GatherPulled() and "Rares & treasures" or "Rares & gathering nodes", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header(Needs("Rares & treasures", "RareScanner"), ns.ToggleIcon("rares"))
    a:Check("Show", "rares", "shown")
    a:Tip("What shows follows RareScanner's own world map filters.")
    a:Requires("rares", "shown")
    a:Advanced(true)
    a:Slider("Opacity", 0, 1, 0.05, "rares", "alpha")
    a:Slider("Size", 0.2, 2, 0.05, "rares", "scale")
    a:Check("RareScanner's own icons", "rares", "rsIcons")
    a:Requires()

    a:Advanced()
    a:Header("Rares & chests (built in)", ns.ToggleIcon("wilds"))
    a:Check("Show", "wilds", "shown")
    a:Tip("Where each rare is, its level and what it drops." .. (ns.WILDS_TREASURE and " Also where chests can spawn." or "") .. " No respawn timers; RareScanner has those.")
    a:Requires("wilds", "shown")
    a:Check("Rares", "wilds", "rares")
    a:Check("Rare elites", "wilds", "elites")
    if ns.WILDS_TREASURE then  -- (off for 1.2, Wilds.lua)
        a:Check("Treasure chest spots", "wilds", "treasure")
        a:Tip("Every spot a chest can spawn. Some zones have dozens, so it's off by default.")
    end
    a:Advanced(true)
    a:Check("A rare's path while hovered", "wilds", "paths")
    do  -- (unset: the coin on Forever, the dragons on Era, as Wilds.lua draws it)
        local get, set = Setting("wilds", "look")
        a:Choice("Rare mark", "wilds", "look", {
            { "coin", ns.FOREVER and "The game's (dark coin, white star)" or "The game's (gold star)" },
            { "dragon", "Classic dragons (silver rare, gold elite)" },
        }, function() return get() or (ns.FOREVER and "coin" or "dragon") end, set)
    end
    a:Slider("Size", 10, 28, 1, "wilds", "size", "%d")
    a:Requires()
    a:Advanced()
    a:Check("Boss loot: \"what they carry\" in boss menus", "wilds", "bossLoot")
    a:Tip("A boss's own loot with drop chances, then its quest items. No world drops.")

    -- (from the Townsfolk tab, where it sat between the pins' rows and their list: "placement?", the user
    -- 2026-11-15. It is about what the water gives, as the nodes are.)
    if ns.SetupFishing then
        a:Header("Fisherman's mode")
        a:Check("Show", "fishing", "shown")
        a:Tip("Colours the water by how well you can fish there. Green: no fish get away. Yellow: some do. Red: most do. The header also shows the zone's fishing level.")
        a:Requires("fishing", "shown")
        a:Slider("Strength", 0.2, 1, 0.05, "fishing", "alpha")
        a:Requires()
    end
    local b = Column(p, HALF, 0, HALF)
    if ns.GatherPulled() then
        b:Header("Gathering nodes")
        b:Note("Needs the GatherMate2 addon: with it on, its nodes show on the map, and the switches appear here.")
        return
    end
    b:Header("Gathering nodes", ns.ToggleIcon("gather"))
    b:Check("Show", "gather", "shown")
    b:Requires("gather", "shown")
    b:Advanced(true)
    b:Slider("Opacity", 0, 1, 0.05, "gather", "alpha")
    b:Slider("Size", 0.2, 2, 0.05, "gather", "scale")
    b:Advanced()
    local ownNodes = ns.GatherOwnData and ns.GatherOwnData()  -- (no Waymark_Nodes in Forever's release)
    if ns.AddonPresent("GatherMate2") then
        if ownNodes then
            b:Choice("Nodes from", "gather", "source", {
                { "gathermate", "GatherMate2" }, { "own", "Waymark" },
            })
            b:Tip("GatherMate2: its database and its node filters, shown on this map and the minimap. Waymark: its own data, with what you gather added.")
        end
        b:Choice("Look", "gather", "look", {
            { "ink", "Waymark's marks" }, { "gathermate", "GatherMate2's icons" },
        })
        b:Tip("Waymark's marks: a small drawing for each herb, ore, chest or fish. GatherMate2's icons: on its own nodes only.")
        b:Check("Follow GatherMate's own rules", "gather", "follow")
        b:Tip("Also hides what GatherMate2's own filters hide, like nodes for a profession you don't have.")
    else
        b:Note(ownNodes and "With GatherMate2 installed, you can show its nodes here instead of Waymark's."
            or "Needs GatherMate2: install it and its nodes show here in Waymark's marks.")
    end
    b:Check("Only what you can gather", "gather", "canGather")
    b:Tip("Hides herbs and ore your skill can't gather yet. Without the profession, none of its nodes show.")
    b:Advanced(true)
    b:Check("Colour by skill-up chance", "gather", "tint")
    b:Tip("Marks take the trade skill colours: orange, yellow, green and grey by your skill, red when it's too low.")
    b:Check("Fade spots you've never gathered", "gather", "fadeUnseen")
    b:Check("Show on the minimap", "gather", "minimap")
    b:Tip("The nearest spots, on the game's minimap. With the map as your minimap, they're on it anyway.")
    b:Slider("Ring distance", 50, 240, 5, "gather", "ringYards", "%d yards")
    b:Tip("While you track herbs or ore, nearby spots become rings. A dot inside the ring means the node is up. An empty ring means it isn't.")
    b:Advanced()
    b:SubHeader("Node types")   -- (part of this section, not one of its own)
    for _, t in ipairs(ns.GATHER_TYPES or {}) do
        b:CheckWith(t.label,
            function() return ns.db.gather.types[t.key] end,
            function(v)
                ns.db.gather.types[t.key] = v or nil
                ns.OnSettingChanged("gather", "types")
            end)
    end
    b:Button("Show hidden node types again", function()
        wipe(ns.db.gather.off)
        ns.OnSettingChanged("gather", "off")
    end)
    b:Tip("Right-clicking a mark hides that kind of node. This brings them all back.")
    if ns.AddonPresent("GatherMate2") then
        b:Button("Copy your GatherMate2 nodes", function()
            local n = ns.ImportGatherMate and ns.ImportGatherMate()
            print("Waymark: " .. tostring(n or 0) .. " GatherMate2 nodes copied to your own spots.")
        end)
        b:Tip("Adds your GatherMate2 nodes to Waymark's. Only do this once, or they're counted twice.")
    end
    b:Requires()
end }

-- your own marks on the maps, and the found notes' book (Ink.lua, Notebook.lua)
PAGES[#PAGES + 1] = { key = "ink", label = "The book & map ink", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Your map ink", ns.ToggleIcon("quill"))
    a:Check("On the world map", "ink", "shown")
    a:Tip("Routes, marks and notes you drew on the zone maps. The ink button on the map switches it.", "Ctrl-drag a mark to move it (with the quill out, just drag); right-click it for more.")
    a:Check("Dungeons too", "ink", "dungeons")
    a:Tip("The ink button hides your ink on dungeon floors as well. Off: it stays on them whatever the button says.")
    a:Requires("ink", "shown")
    a:Slider("Opacity", 0.1, 1, 0.05, "ink", "alpha")
    a:Slider("Note size", 0.6, 1.6, 0.1, "ink", "textSize", "%.1f")
    a:Requires()
    a:Button("Take up the quill", function() if ns.QuillToggle then ns.QuillToggle() end end)
    a:Tip("Opens the quill's bar: draw routes and marks and write notes on the map.", "Also: Shift-click the ink button on the map, or /waymark ink. Again: put it down.")
    a:Header("The book", ns.ToggleIcon("book"))
    a:Choice("What's in the book", "notebook", "kind", {
        { "story", "The wanderer's story" }, { "notes", "Notes only" }, { "blank", "Blank journal" },
    })
    a:Tip("Notes only: the dungeon tips, maps and quest lines, without the story. Blank: empty pages of your own. Changing it hides pages, it deletes nothing.")
    a:CheckWith("Book button on the map",
        function() return ns.db.toggles.list.book end,
        function(v)
            ns.db.toggles.list.book = v and true or false
            ns.OnSettingChanged("toggles", "list")
        end, true, ns.MEDIA .. "BookIcon")
    a:Tip("Click it to open the book, right-click for more. There's also a key: Esc > Options > Keybindings > AddOns > Waymark.")
    a:Button("Open the book", function() if ns.ToggleNotebook then ns.ToggleNotebook() end end)
    a:Button("Reset the whole book", function() if ns.AskBookReset then ns.AskBookReset() end end)
    a:Button("Bring back what was reset", function() if ns.BookBack then ns.BookBack(true) end end)
    a:Tip("A reset sets your words and ink aside. Nothing is deleted. To reset one page, use the quill's bar.")
    -- (the book's campsites on the zone maps, Camps.lua: only in a build that carries it. On or off, and the ones
    -- a right-click hid brought back: the user, 2026-11-14)
    if ns.SetupCamps then
        a:CheckWith("Campsites on the map",
            function() return ns.db.notebook.camps ~= false end,
            function(v) ns.db.notebook.camps = v and true or false end)
        a:Button("Bring back hidden campsites", function() if ns.CampDev then ns.CampDev("show") end end)
        a:Tip("A small campfire where each page was written. Click one for its page, right-click to hide it.")
    end
    a:Tip("Pages someone left about the dungeons. Their numbered rings show on the dungeon maps.", "Click the stamp in a dungeon map's corner for its page. /waymark notes opens the book too.")
end }

PAGES[#PAGES + 1] = { key = "explore", label = "Exploration", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Unexplored land")
    UnfoundRows(a)   -- (the same rows as on The map's look)
    -- (its settings have no row of their own now: named here so "its settings" from the map's button, and a
    -- reset of this page, still find the page)
    p.bfiKeys = p.bfiKeys or {}
    for _, k in ipairs({ { "explore", "shown" }, { "explore", "fogAlpha" }, { "pencil", "on" } }) do table.insert(p.bfiKeys, k) end
    a:Header("Pins in unexplored land")
    a:Check("Hide quest pins there", "explore", "hideQuests")
    a:Check("Hide townsfolk, rares, nodes there", "explore", "hideOthers")
    a:Header("Discoveries")
    a:Check("Gold flash where you discover an area", "explore", "flash")
    a:Live(function()
        local map = BattlefieldMapFrame
        local id = map and map:GetMapID()
        -- (called plainly: "a and f()" would keep only its first result)
        if not (ns.ExplorationProgress and id) then return "This map: nothing to explore" end
        local pct, n, total = ns.ExplorationProgress(id)
        if not pct then return "This map: nothing to explore" end
        local info = C_Map.GetMapInfo(id)
        return string.format("%s: %d%% explored (%d of %d areas)", info and info.name or "This map", pct, n, total)
    end)
    local b = Column(p, HALF, 0, HALF)
    b:Header("Area names")
    b:Check("Name the area under the cursor", "explore", "hoverNames")
    b:Tip("On a continent: the zone under the cursor, with its level range.")
    b:Requires("explore", "hoverNames")
    b:Choice("Where", "explore", "hoverWhere", {
        { "top", "Top of the map" },
        { "cursor", "At the cursor" },
    })
    b:Check("Keep unexplored names a secret", "explore", "hideUnexplored")
    b:Tip("Over an area you haven't explored, no name shows. Off: its name in grey.")
    b:Advanced(true)
    b:Slider("Text size", 10, 24, 1, "explore", "hoverSize", "%d")
    b:Advanced()
    b:Requires()
end }

PAGES[#PAGES + 1] = { key = "dungeon", label = "Caves & dungeons", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Caves (open world)")
    a:Check("Cave view", "cave", "enabled")
    a:Tip("Inside a cave the map shows the cave: the game's own cave map where there is one, or a minimap-style map.")
    a:Advanced(true)
    a:Check("Switch to the game's cave maps", "dungeon", "followMaps")
    a:Tip("Switches to the game's own cave or dungeon map where it has one.")
    a:Requires("cave", "enabled")
    a:Check("Blizzard's cave maps", "cave", "blizzardMaps")
    a:Tip("Where a cave has one, the game's own map of it.")
    a:Check("Minimap style in every cave", "cave", "minimapStyleEverywhere")
    a:Check("Switch button in caves", "cave", "styleButton")
    a:Tip("A button on the map to switch between the two kinds of cave map, where a cave has both.")
    a:Check("Keep the cave still", "cave", "still")
    a:Tip("The whole cave fitted to the map; only your arrow moves.")
    a:Advanced(true)
    a:Slider("Cave view zoom", 0.3, 8, 0.1, "cave", "zoom", "%.1f px per yard")
    a:Slider("Arrow size", 10, 40, 1, "cave", "arrowSize", "%d px")
    a:Advanced()
    a:Requires()
    a:Header("Dungeon entrances", ns.ToggleIcon("dungeons"))
    a:Check("On the zone map (click one: its map)", "dungeons", "shown")
    a:Tip("Right-click the dungeon's map (not on a boss or a pin) to return to the zone.")
    a:Requires("dungeons", "shown")
    a:Check("On continent maps too", "dungeons", "continent")
    a:Tip("Every dungeon entrance on the continent map, drawn smaller. On the world map too.")
    a:Advanced(true)
    a:Slider("Size", 0.4, 2, 0.05, "dungeons", "scale")
    a:Advanced()
    a:Requires()

    if ns.DungeonsOff then return end
    local b = Column(p, HALF, 0, HALF)
    b:Header("Inside dungeons")
    b:Check("Show the dungeon's map", "dungeon", "fallback")
    b:Tip("The game's own art of the dungeon, with its bosses.", "Wheel: zoom. Drag: pan. Right-click: whole map. < >: floors.")
    b:Requires("dungeon", "fallback")
    -- (the settings pass, 2026-11-15, "clean this up": it was seventeen rows in one run. Now the map itself,
    -- then its bosses and dangers, then what else is marked inside as a short checklist in two parts.)
    b:Check("Opens as you go in", "dungeon", "showInside")
    b:Choice("View", "dungeon", "view", {
        { "art", "Map (boss markers)" },
        { "minimap", "Minimap (your arrow)" },
    })
    b:Tip("Map: the dungeon's map with its bosses. Minimap: your minimap shown large inside the map window.")
    b:SubHeader("Bosses and dangers")
    b:Check("Boss markers", "dungeon", "bosses")
    b:Tip("Numbered in kill order, with a red X once killed.")
    b:Check("Boss list", "dungeon", "bossList")
    b:Tip("The bosses in kill order down the map's left side, ticked as they die.", "Click a name: its floor. Click the title: fold it.")
    if ns.DangersSet then
        b:CheckWith("What kills here", function() return ns.DangersOn() end, function(v) ns.DangersSet(v) end)
        b:Tip("Marks on a dungeon's map and a note beside it for the pulls and casts that wipe groups. Open it from the ! tab.", "Off: the tab, the marks and the note are all gone.")
    end
    b:SubHeader("Also marked inside")
    b:Choice("Shown as", "dungeon", "objects", {
        { "icons", "Icons" },
        { "hidden", "Hidden (tooltip on hover)" },
        { "off", "Off" },
    })
    b:Tip("Quest spots always; the rest as ticked below. Hidden: no icons, but the tooltip still shows over the spot.", "With the quill: drag a pin to move it, right-click to put it back or hide it.")
    local function Marks() return ns.db.dungeon.fallback and ns.db.dungeon.objects ~= "off" end
    b:Requires(Marks)
    b:Grid(2)
    b:SubHeader("The way through")
    b:Check("Locked doors", "dungeon", "keyDoors")
    b:Tip("Doors that want a key, and which key.")
    b:Check("Doors a fight opens", "dungeon", "fightDoors")
    b:Tip("Doors shut until the fight near them is won.")
    b:Check("Levers", "dungeon", "switches")
    b:Tip("The levers and switches that open a way.")
    b:Check("Patrols", "dungeon", "patrols")
    b:Tip("Patrols and their paths, as dotted lines.")
    b:SubHeader("What is in there")
    b:Check("Chests", "dungeon", "chests")
    b:Tip("The chests that always spawn in the same spot.")
    b:Requires(function() return Marks() and ns.db.dungeon.chests end)
    b:Check("The random ones too", "dungeon", "allChests")
    b:Tip("Also the chests that only sometimes spawn in a spot (one of several, picked at random).")
    b:Requires(Marks)
    b:Check("Friendly NPCs", "dungeon", "npcs")
    b:Tip("Quest givers, trainers and vendors inside.")
    b:Check("Forges, mailboxes", "dungeon", "otherThings")
    b:Tip("The other things marked inside: a forge, a mailbox, a rune, a machine.")
    b:Check("Every quest spot", "dungeon", "allQuests")
    b:Tip("Also the quest things found all over a floor. Off: only the ones that stand out.")
    b:Grid()
    b:Advanced(true)
    b:Slider("Icon size", 0.5, 2, 0.05, "dungeon", "objectScale")
    b:Advanced()
    b:Requires("dungeon", "fallback")
    if ns.DungeonMobs then                                 -- (dev only: not shipped, tools\build_era_release.py)
        b:Check("Mob dots (dev)", "dungeon", "devMobs")
        b:Tip("A small dot where each mob is. Hover: its name and level.", "Hold Shift: what to watch for, and what it casts.")
    end
    if ns.DungeonWhere then                                -- (not on Forever: the names it needs are hidden there, DungeonWhere.lua)
        b:Check("Where you are (a guess)", "dungeon", "where")
        b:Tip("The game doesn't tell addons where you are in a dungeon. Waymark guesses from the mobs you've fought and lights up that part of the map.")
    end
    b:Requires()
end }

-- when each context is on (Profiles.lua's Matches)
local PROFILE_WHEN = {
    combat = "While you're in combat.",
    battleground = "Inside a battleground or an arena.",
    dungeon = "Inside a dungeon or a raid.",
    city = "In a capital, or a town while town view is on (else where you rest).",
}

-- One table: the layers down the left, a column per context (Show / Hide / -
-- each), so the contexts read side by side at the window's width
PAGES[#PAGES + 1] = { key = "profiles", label = "Context profiles", advancedOnly = true, build = function(p)
    local LAYERS = {
        { "questie", "Quest givers" }, { "turnins", "Turn-ins" }, { "spots", "Objective spots" },
        { "objectives", "Objectives (the game's)" }, { "areas", "Quest areas (the game's)" },
        { "learned", "Learned quest givers" }, { "tracker", "Quest tracker" },
        { "townsfolk", "Townsfolk" }, { "dungeons", "Dungeon entrances" }, { "party", "Player & group" },
        { "rares", "Rares & treasures" }, { "gather", "Gathering nodes" }, { "line", "Line to party member" },
        { "explore", "Unexplored land" }, { "detail", "Close-up detail" }, { "zoneName", "Header" },
        { "coords", "Coordinates" }, { "clock", "Clock" },
    }
    ns.DropNoGameLayers(LAYERS, 1)
    local order = ns.PROFILE_ORDER or {}
    local w = Column(p, 0, 0, CONTENT_W)
    w:Note("In combat, a dungeon, a battleground or a town, each layer can be shown, hidden or left alone (-). If two apply at once, the one further left wins. Your normal settings don't change.")
    w:Live(function()
        local k = ns.ActiveProfileKey and ns.ActiveProfileKey()
        return "Active now: " .. (k and ns.PROFILE_LABELS[k] or "none")
    end)
    w:Header("Contexts")

    local left = w:Left()
    local LABEL_W = 180
    local colW = math.floor((ROW_W - left - LABEL_W) / math.max(1, #order))
    local function ColX(i) return left + LABEL_W + (i - 1) * colW end
    local function Tip(owner, title, text)
        owner:HookScript("OnEnter", function()
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(title, 1, 0.82, 0)
            if text and text ~= "" then GameTooltip:AddLine(text, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- the contexts' names over their columns (two lines where they need them)
    local headH = 0
    local heads = {}
    for i, key in ipairs(order) do
        local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        Ink(p, fs, INK_HEAD)
        fs:SetWidth(colW - 6)
        fs:SetJustifyH("CENTER")
        -- (one long word: broken by hand, as the column is narrower than it)
        fs:SetText(key == "battleground" and "Battle-\ngrounds" or ns.PROFILE_LABELS[key])
        heads[i] = fs
        headH = math.max(headH, fs:GetStringHeight())
    end
    for i, key in ipairs(order) do
        heads[i]:SetPoint("BOTTOM", p, "TOPLEFT", ColX(i) + colW / 2, w.y - headH)
        local hover = CreateFrame("Frame", nil, p)
        hover:SetAllPoints(heads[i])
        hover:EnableMouse(true)
        Tip(hover, ns.PROFILE_LABELS[key], PROFILE_WHEN[key])
    end
    w.y = w.y - headH - 8

    local ROW = 24
    local n = 0
    -- a row: its label at the left, a faint band behind every other one
    local function Row(label, tip)
        n = n + 1
        if n % 2 == 0 then
            local band = p:CreateTexture(nil, "BACKGROUND")
            band:SetColorTexture(1, 1, 1, 0.04)
            band:SetPoint("TOPLEFT", p, "TOPLEFT", left - 4, w.y)
            band:SetSize(ROW_W - left + 4, ROW)
        end
        local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        Ink(p, fs)
        fs:SetPoint("LEFT", p, "TOPLEFT", left, w.y - ROW / 2)
        fs:SetWidth(LABEL_W - 8)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(label)
        if tip then
            local hover = CreateFrame("Frame", nil, p)
            hover:SetAllPoints(fs)
            hover:EnableMouse(true)
            Tip(hover, label, tip)
        end
    end
    local function On(key) return function() return ns.db.profiles[key].enabled end end

    -- Enabled, then Hide the map: a box per context
    for _, r in ipairs({ { "enabled", "Enabled", "Use this context's column while it's on." },
                         { "hideMap", "Hide the map", "The whole map hidden while this context is on." } }) do
        Row(r[2], r[3])
        for i, key in ipairs(order) do
            local c = CreateCheck(p, "",
                function() return ns.db.profiles[key][r[1]] end,
                function(v) ns.db.profiles[key][r[1]] = v ns.OnSettingChanged("profiles", r[1]) end)
            c:SetSize(22, 22)
            c:SetPoint("CENTER", p, "TOPLEFT", ColX(i) + colW / 2, w.y - ROW / 2)
            Tip(c, ns.PROFILE_LABELS[key] .. ": " .. r[2], r[1] == "enabled" and PROFILE_WHEN[key] or r[3])
            if r[1] == "hideMap" then c.bfiDep = On(key) end
        end
        w.y = w.y - ROW
    end
    local rule = p:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 0.82, 0, 0.25)
    rule:SetPoint("TOPLEFT", p, "TOPLEFT", left, w.y - 3)
    rule:SetSize(ROW_W - left, 1)
    w.y = w.y - 8
    n = 0

    -- each layer: Show, Hide or - per context (a click goes round the three)
    local function IndexOf(v)
        for i, s in ipairs(CYCLE) do if s[1] == v then return i end end
        return 1
    end
    for _, l in ipairs(LAYERS) do
        Row(l[2])
        for i, key in ipairs(order) do
            local b = RedButton(p, colW - 14, 20)
            b:SetSize(colW - 14, 20)
            b:SetPoint("CENTER", p, "TOPLEFT", ColX(i) + colW / 2, w.y - ROW / 2)
            local function Get() return ns.db.profiles[key].layers[l[1]] end
            b.Refresh = function() b:SetText(CYCLE[IndexOf(Get())][2]) end
            b:SetScript("OnClick", function()
                ns.db.profiles[key].layers[l[1]] = CYCLE[IndexOf(Get()) % 3 + 1][1]
                ns.OnSettingChanged("profiles", "layers")
                b.Refresh()
            end)
            Tip(b, ns.PROFILE_LABELS[key] .. ": " .. l[2], "Show, Hide, or - to leave it as you set it. Click to go round them.")
            b.bfiDep = On(key)
            controls[#controls + 1] = b
            b.Refresh()
        end
        w.y = w.y - ROW
    end
end }

-- A button that replaces or removes something for good asks once: the first click turns it into "Sure?",
-- the second does it; the pointer leaving takes the question back. For Forget. (Load and Copy replace every
-- setting of the character in one click: they keep a backup first, Setups.lua, and do not ask.)
local function AskTwice(b, label, fn)
    b:SetText(label)
    local sure
    b:SetScript("OnClick", function()
        if not sure then
            sure = true
            b:SetText("Sure?")
            return
        end
        sure = nil
        b:SetText(label)
        fn()
    end)
    b:HookScript("OnLeave", function()
        sure = nil
        b:SetText(label)
    end)
end

PAGES[#PAGES + 1] = { key = "setups", label = "Your presets & sharing", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Save as a preset")
    a:Note("Your settings are saved per character. A preset of your own is a named copy of them, including positions and sizes. It also shows as a card on Start here.")
    local nameBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    nameBox:SetSize(170, 20)
    nameBox:SetPoint("TOPLEFT", a:Left() + 6, a.y - 4)
    nameBox:SetAutoFocus(false)
    local save = RedButton(p)
    save:SetSize(100, 22)
    save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    save:SetText("Save")
    a.y = a.y - 34

    a:Header("Your presets")
    -- the list: a row per setup with Load, Export and Delete
    local ROWS = 9
    local rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, p)
        r:SetSize(HALF - 10, 22)
        r:SetPoint("TOPLEFT", a:Left(), a.y - (i - 1) * 24)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        Ink(p, r.text)
        r.text:SetPoint("LEFT")
        r.text:SetWidth(260)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        local function Btn(label, w, anchor, fn)
            local b = RedButton(r)
            b:SetSize(w, 20)
            b:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
            b:SetText(label)
            b:SetScript("OnClick", function() fn(r.name) end)
            return b
        end
        -- (no question: what you had is kept as a backup first, Setups.lua)
        r.load = Btn("Load", 50, r.text, function(n) ns.LoadSetup(n) ns.RefreshControls() end)
        r.export = Btn("Export", 56, r.load, function(n) ns.ShowExport(n) end)
        -- (two clicks, as on Start here: one click took a preset for good, the user 2026-11-16. The
        -- pointer leaving the button takes the question back.)
        r.delete = Btn("Delete", 56, r.export, function(n)
            if r.sure ~= n then
                r.sure = n
                r.delete:SetText("Sure?")
                return
            end
            r.sure = nil
            ns.DeleteSetup(n)
            if ns.lastSetup == n then ns.lastSetup = nil end
            ns.RefreshControls()
            ns.RebuildOptionsPages()
        end)
        r.delete:HookScript("OnLeave", function()
            r.sure = nil
            r.delete:SetText("Delete")
        end)
        rows[i] = r
    end
    a.y = a.y - ROWS * 24
    local empty = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ink(p, empty, INK_SOFT)
    empty:SetPoint("TOPLEFT", rows[1], "TOPLEFT", 0, -4)
    empty:SetText("None yet.")
    local list = CreateFrame("Frame", nil, p)
    list.Refresh = function()
        local names = ns.SetupNames()
        for i, r in ipairs(rows) do
            r.name = names[i]
            r.sure = nil
            r.delete:SetText("Delete")
            r:SetShown(names[i] ~= nil)
            -- (the one loaded last, as other addons mark the current profile)
            if names[i] then
                r.text:SetText(names[i] == ns.lastSetup and ("|cff4ddf4d" .. names[i] .. " (current)|r") or names[i])
            end
        end
        empty:SetShown(#names == 0)
    end
    controls[#controls + 1] = list
    save:SetScript("OnClick", function()
        if ns.SavePresetAs(nameBox:GetText()) then
            nameBox:SetText("")
            nameBox:ClearFocus()
            ns.RefreshControls()
            ns.RebuildOptionsPages()  -- (its card on Start here)
        end
    end)
    nameBox:SetScript("OnEnterPressed", function() save:Click() end)

    local b = Column(p, HALF, 0, HALF)
    b:Header("Your other characters")
    b:Note("Each character keeps its own settings, changes and all. Copy takes another character's settings exactly as it last logged out.")
    -- a row per character with Copy and Forget
    local CHAR_ROWS = 6
    local chars = {}
    for i = 1, CHAR_ROWS do
        local r = CreateFrame("Frame", nil, p)
        r:SetSize(HALF - 10, 22)
        r:SetPoint("TOPLEFT", b:Left(), b.y - (i - 1) * 24)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        Ink(p, r.text)
        r.text:SetPoint("LEFT")
        r.text:SetWidth(170)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.copy = RedButton(r)
        r.copy:SetSize(50, 20)
        r.copy:SetPoint("LEFT", r.text, "RIGHT", 4, 0)
        r.copy:SetText("Copy")
        r.copy:SetScript("OnClick", function() ns.CopyCharacter(r.name) ns.RefreshControls() end)
        r.forget = RedButton(r)
        r.forget:SetSize(56, 20)
        r.forget:SetPoint("LEFT", r.copy, "RIGHT", 4, 0)
        AskTwice(r.forget, "Forget", function() ns.ForgetCharacter(r.name) ns.RefreshControls() end)
        chars[i] = r
    end
    b.y = b.y - CHAR_ROWS * 24
    local noChars = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ink(p, noChars, INK_SOFT)
    noChars:SetPoint("TOPLEFT", chars[1], "TOPLEFT", 0, -4)
    noChars:SetText("None yet: a character shows here once it has logged out.")
    local charList = CreateFrame("Frame", nil, p)
    charList.Refresh = function()
        local names = ns.CharacterNames()
        for i, r in ipairs(chars) do
            r.name = names[i]
            r:SetShown(names[i] ~= nil)
            if names[i] then r.text:SetText(names[i]) end
        end
        noChars:SetShown(#names == 0)
    end
    controls[#controls + 1] = charList
    b:Header("Import and export")
    b:Button("Import", function() ns.ShowImport() end)
    b:Button("Export the settings in use", function() ns.ShowExport() end)
    b:Button("Share learned quests and mobs", function() if ns.ShowLearnedExport then ns.ShowLearnedExport() end end)
    b:Tip("The quest givers, quests and mob spots learned as you play, as a string. Whoever imports it (Import...) adds them to theirs.")
    b:Note("Export gives you a text string to copy and paste anywhere, like other addons' profiles. Import lets you paste one in.")
    b:Note("Your boss notes, placed boss spots and map markings stay yours: they're not part of a setup.")
end }

-- the settings pages' text sizes, as real sizes
local function SizeChoices(lo, hi, default)
    local out = {}
    for s = lo, hi do out[#out + 1] = { s, s == default and (s .. "  (normal)") or tostring(s) } end
    return out
end

-- work in progress, kept apart from the finished settings
-- Waymark: Combat's page (its own addon: it fills the page in, Combat\Waymark_Combat\Menus.lua)
PAGES[#PAGES + 1] = { key = "combat", label = "Combat bars", build = function(p)
    WaymarkCombat.BuildSettings(Column(p, 0, 0, CONTENT_W))
    WaymarkCombat.RefreshSettings = ns.RefreshControls
end }

PAGES[#PAGES + 1] = { key = "dev", label = "Dev", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("AI-upscaled map art")
    a:Check("Sharp map art (upscaled)", "detail", "sharpArt")
    a:Tip("The zone maps drawn from the Waymark_MapArt folder's upscaled pictures instead of the game's own. Made from WoW Forever's maps, so on other clients they may not line up.")
    a:Live(function()
        return ns.MapArtAvailable and ns.MapArtAvailable() and "Installed: Waymark_MapArt"
            or "Not installed: the Waymark_MapArt folder"
    end)

    if ns.MapLifeSettings then ns.MapLifeSettings(a) end  -- (DevMapLife.lua: not in releases)

    -- every command (DevBar.lua's list), a section a group, in the one column: two columns' buttons
    -- landed on top of each other where the window is narrow
    for _, e in ipairs(ns.DevCommands or {}) do
        if e.group then
            a:Header(e.group)
        elseif ns.DevCommandHere(e) then
            a:Button(e[1], function() ns.RunDevCommand(e) end)
            a:Tip(ns.DevCommandText(e) .. ": " .. e[3])
        end
    end
    a:Note("Also: /waymark quest <id> and /route why <name> (their boxes are on the command bar), /waymark <number> (the map's scale, 0.3-3).")
end }

-- the Lab's pages (Lab\Lab.lua, never in a release): what's held for 1.3, in one place
-- Themes and the unfinished frames (Frames.lua builds it; a Lab page since 2026-11-15, the finished frames are
-- rows on Header & borders)
PAGES[#PAGES + 1] = { key = "labframes", label = "Themes (not done)", build = function(p)
    if ns.FramesLabPage then ns.FramesLabPage(Column(p, 0, 0, CONTENT_W)) end
end }

for _, page in ipairs({ { "lab", "What's in here" }, { "labminimap", "Minimap look" }, { "labhorizon", "The ground" } }) do
    PAGES[#PAGES + 1] = { key = page[1], label = page[2], build = function(p)
        ns.LabPage(page[1], Column(p, 0, 0, CONTENT_W))
    end }
end

-- Panel -------------------------------------------------------------------

local panel, content
local pageFrames, navButtons = {}, {}
local currentPage
-- the title bar over the page (it doesn't scroll): the name of the list entry the page is under, the
-- page's own name after it in grey, and under them the entry's pages as tabs (navItems.Tabs)
local pageTitle, pageCrumb
local pageFold  -- (before the title: folds every section on the page, or opens them)
-- The list on the left: a few entries, each a name and a line saying what's in it (the user, 2026-11-14, of
-- five folded group names: "If I didn't know the addon, this wouldn't tell me anything"). An entry's pages
-- are tabs over the page. An entry: { title, line, pages = { def, ... }, button, head, shows = { [page key]
-- = in the tabs now }, found = { [page key] = search matches }, first = its first page showing, last = the
-- tab last open }. navItems.of[page key] = its entry.
local navItems = { of = {} }

local query = ""  -- the search box's text, lower case ("" = not searching)

-- Pages are built the first time they're shown (or searched). Each sits in a
-- scroll frame: f is the page itself (its controls' parent), f.bfiScroll what
-- gets shown and hidden. The scroll bar only shows when the page is too long.
local function ShowPage(f, on)
    f.bfiScroll:SetShown(on)
end

-- The game's minimal scroll bar on a UIPanelScrollFrame's bar: a thin track,
-- a rounded thumb, small arrows at its ends (minimal-scrollbar-*)
local function MinimalScrollBar(bar)
    local thumb = bar:GetThumbTexture()
    for _, r in ipairs({ bar:GetRegions() }) do
        if r ~= thumb then r:Hide() end
    end
    local function Piece(name, layer, w, h)
        local t = bar:CreateTexture(nil, layer, nil, 7)
        ns.SetArt(t, name)
        t:SetSize(w, h)
        return t
    end
    local top = Piece("minimal-scrollbar-track-top", "BACKGROUND", 8, 8)
    top:SetPoint("TOP")
    local bottom = Piece("minimal-scrollbar-track-bottom", "BACKGROUND", 8, 8)
    bottom:SetPoint("BOTTOM")
    local mid = bar:CreateTexture(nil, "BACKGROUND", nil, 7)
    ns.SetArt(mid, "!minimal-scrollbar-track-middle")
    mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    mid:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
    if thumb then
        -- (the art is a long strip, 715 high: just the top of it, unsquashed)
        ns.SetArtPart(thumb, "minimal-scrollbar-thumb-middle", 0, 1, 0, 40 / 715)
        thumb:SetSize(8, 40)
        local cap = Piece("minimal-scrollbar-thumb-top", "OVERLAY", 8, 8)
        cap:SetPoint("TOP", thumb, "TOP")
        local foot = bar:CreateTexture(nil, "OVERLAY", nil, 7)
        ns.SetArtPart(foot, "minimal-scrollbar-thumb-bottom", 0, 1, 28 / 36, 1)
        foot:SetSize(8, 8)
        foot:SetPoint("BOTTOM", thumb, "BOTTOM")
        bar.bfiThumbEnds = { cap, foot }   -- (hidden where a page draws its own thumb: BuildPage)
    end
    -- No arrows (2026-11-15): the 17 x 11 arrow art came out big and soft on the old scroll buttons whatever
    -- was tried ("Scrollbar still looks bad", the user). A track and a thumb: the wheel, the drag and a
    -- page's section marks do the rest. The buttons stay, unseen and unclickable (the template wants them).
    local function Arrow(b)
        if not b then return end
        b:SetAlpha(0)
        b:EnableMouse(false)
    end
    Arrow(bar.ScrollUpButton, "top")
    Arrow(bar.ScrollDownButton, "bottom")
end

local function BuildPage(def)
    local f = pageFrames[def.key]
    if f then return f end
    local scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scroll:SetAllPoints(content)
    f = CreateFrame("Frame", nil, scroll)
    f:SetSize(CONTENT_W + 10, 10)  -- (the content frame may not be laid out yet)
    scroll:SetScrollChild(f)
    f.bfiScroll = scroll
    f.bfiSettingsPage = true  -- (dark ink: see Ink)
    f.bfiKey = def.key         -- (its sections' fold keys: "page/heading")
    f.bfiLowest = 0        -- (Column keeps it: the page's lowest row)
    scroll:Hide()
    def.build(f)
    for _, c in ipairs(f.bfiColumns or {}) do c:EndCard() end  -- (each column's last section)
    -- fine-tuning left out (Column's Advanced): say so at the bottom
    local n = f.bfiSkipped or 0
    if n > 0 then
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        Ink(f, hint, INK_SOFT)
        hint:SetPoint("TOPLEFT", 4, f.bfiLowest - 14)
        hint:SetWidth(CONTENT_W - 10)
        hint:SetJustifyH("LEFT")
        hint:SetText(string.format("%d fine-tuning setting%s hidden on this page: tick Show advanced settings, below.",
            n, n == 1 and " is" or "s are"))
        f.bfiLowest = f.bfiLowest - 14 - hint:GetStringHeight()
    end
    f:SetHeight(math.max(10, -f.bfiLowest + 12))
    local bar = scroll.ScrollBar
    if bar then
        MinimalScrollBar(bar)
        -- (the track takes the room the arrows had)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -3)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 3)
    end
    scroll:HookScript("OnScrollRangeChanged", function(self, _, yRange)
        if bar then bar:SetShown((yRange or self:GetVerticalScrollRange()) > 1) end
        if (yRange or 0) < 1 then self:SetVerticalScroll(0) end
    end)
    if bar then bar:SetShown(f:GetHeight() > content:GetHeight() + 1) end
    -- The sections of a page that scrolls, as gold marks along its scroll bar: each where its heading is.
    -- Point at one: its name. Click: there, unfolded. (The user's sketch, 2026-11-15: the names written by
    -- the bar; marks with the name on hover, since two-column pages run right up to the bar.)
    if bar and f.bfiHeads and #f.bfiHeads > 1 then
        local heads = {}
        for _, h in ipairs(f.bfiHeads) do heads[#heads + 1] = h end
        table.sort(heads, function(x, y) return x.y > y.y end)
        -- (headings level with each other, one in each column: one mark, both names)
        local groups = {}
        for _, h in ipairs(heads) do
            local g = groups[#groups]
            if g and g.y - h.y < 24 then g.text = g.text .. "\n" .. h.text else groups[#groups + 1] = { y = h.y, text = h.text, key = h.key } end
        end
        local marks = {}
        for _, g in ipairs(groups) do
            local m = CreateFrame("Button", nil, bar)
            m:SetSize(14, 9)
            m:SetFrameLevel((tonumber(bar:GetFrameLevel()) or 1) + 5)
            local t = m:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(1, 0.82, 0, 0.85)
            t:SetSize(9, 2)
            t:SetPoint("RIGHT", -1, 0)
            m:SetScript("OnEnter", function(self)
                t:SetColorTexture(1, 1, 1, 1)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(g.text, 1, 0.82, 0)
                GameTooltip:Show()
            end)
            m:SetScript("OnLeave", function()
                t:SetColorTexture(1, 0.82, 0, 0.85)
                GameTooltip:Hide()
            end)
            m:SetScript("OnClick", function()
                local function Go(page)
                    local sc = page and page.bfiScroll
                    if not sc then return end
                    local y = g.y
                    for _, h in ipairs(page.bfiHeads or {}) do
                        if h.key == g.key then y = h.y end
                    end
                    sc:SetVerticalScroll(math.max(0, math.min(-y - 6, sc:GetVerticalScrollRange())))
                end
                if SectionFolded(g.key) and ns.ToggleOptionSection then
                    ns.ToggleOptionSection(g.key)   -- (the pages are laid out again: the new one, a moment on)
                    C_Timer.After(0, function() Go(pageFrames[def.key]) end)
                else
                    Go(f)
                end
            end)
            m.g = g
            marks[#marks + 1] = m
        end
        local function Place()
            local H = tonumber(bar:GetHeight()) or 0
            local range = (tonumber(f:GetHeight()) or 0) - (tonumber(scroll:GetHeight()) or 0)
            if H < 60 or range < 1 then
                for _, m in ipairs(marks) do m:Hide() end
                return
            end
            -- The thumb as long as the share of the page in view, so it is a window that slides over the
            -- marks: a mark inside it is a section on screen. (It was 40 px whatever the page: "Tiny scroller
            -- for a scrollbar with 3 steps", the user 2026-11-15.)
            local page = tonumber(f:GetHeight()) or 1
            local th = math.max(30, math.min(H, H * (page - range) / page))
            -- (drawn here, not the slider's own: a slider keeps its thumb's middle on the bar, so a long one
            -- stuck out past both ends, over the arrows. The slider's own stays, unseen, for the drag.)
            local thumb = bar:GetThumbTexture()
            if thumb then
                thumb:SetSize(8, th)
                thumb:SetAlpha(0)
            end
            for _, e in ipairs(bar.bfiThumbEnds or {}) do e:Hide() end
            if not bar.bfiOwn then
                local o = {}
                o.top = bar:CreateTexture(nil, "OVERLAY", nil, 7)
                ns.SetArt(o.top, "minimal-scrollbar-thumb-top")
                o.top:SetSize(8, 8)
                o.bot = bar:CreateTexture(nil, "OVERLAY", nil, 7)
                ns.SetArtPart(o.bot, "minimal-scrollbar-thumb-bottom", 0, 1, 28 / 36, 1)
                o.bot:SetSize(8, 8)
                o.mid = bar:CreateTexture(nil, "OVERLAY", nil, 6)
                o.mid:SetPoint("TOPLEFT", o.top, "BOTTOMLEFT")
                o.mid:SetPoint("BOTTOMRIGHT", o.bot, "TOPRIGHT")
                bar.bfiOwn = o
                scroll:HookScript("OnVerticalScroll", function() if bar.bfiDraw then bar.bfiDraw() end end)
            end
            bar.bfiDraw = function()
                local o = bar.bfiOwn
                local r = tonumber(scroll:GetVerticalScrollRange()) or 0
                local at = r > 0 and math.max(0, math.min(1, (tonumber(scroll:GetVerticalScroll()) or 0) / r)) or 0
                local y = at * (H - th)
                ns.SetArtPart(o.mid, "minimal-scrollbar-thumb-middle", 0, 1, 0, math.min(1, math.max(1, th - 16) / 715))
                o.top:ClearAllPoints()
                o.top:SetPoint("TOP", bar, "TOP", 0, -y)
                o.bot:ClearAllPoints()
                o.bot:SetPoint("TOP", bar, "TOP", 0, -(y + th - 8))
            end
            bar.bfiDraw()
            for _, m in ipairs(marks) do
                -- (the heading's place down the page, on the bar; at the top of the view the thumb's top is on it)
                local frac = math.max(0, math.min(1, -m.g.y / range))
                m:ClearAllPoints()
                m:SetPoint("RIGHT", bar, "TOPLEFT", 1, -(frac * (H - th) + 5))
                m:Show()
            end
        end
        bar:HookScript("OnShow", Place)
        bar:HookScript("OnSizeChanged", Place)
        scroll:HookScript("OnScrollRangeChanged", Place)
        Place()
    end
    pageFrames[def.key] = f
    return f
end

-- scroll a page so the spot y (page units, from its top: <= 0) is in view
local function ScrollTo(f, y)
    local scroll = f.bfiScroll
    local view = scroll:GetHeight()
    local top = scroll:GetVerticalScroll()
    if -y < top or -y > top + view - 40 then
        scroll:SetVerticalScroll(math.max(0, math.min(-y - 30, scroll:GetVerticalScrollRange())))
    end
end

-- every setting on a page (Column's Track) back to its default
local function CopyValue(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = CopyValue(x) end
    return t
end
-- keys: { { group, key }, ... } (nil group = top level)
local function ResetKeys(keys)
    for _, gk in ipairs(keys) do
        local group, k = gk[1], gk[2]
        local defaults = group and ns.DEFAULTS[group] or ns.DEFAULTS
        local tbl = group and ns.db[group] or ns.db
        if defaults and tbl and defaults[k] ~= nil then
            tbl[k] = CopyValue(defaults[k])
            ns.OnSettingChanged(group, k)
        end
    end
    ns.RefreshControls()
end

-- ns.PageResets[page key]: what a file of the addon puts back besides the page's own settings when its page is
-- reset (Pencil.lua: the form its one switch stands for). The Lab's pages have their own (ns.LabReset).
ns.PageResets = ns.PageResets or {}
local function ResetPage(key)
    local f = pageFrames[key]
    if f and f.bfiKeys then ResetKeys(f.bfiKeys) end
    if ns.PageResets[key] then ns.PageResets[key]() end
    if ns.LabReset then ns.LabReset(key) end
end

-- the thresholds that are hard to get back by hand, for their own reset buttons
local RESET_GROUPS = {
    zoom = { label = "every zoom and close-up detail threshold",
             { "zoom", "closestX" }, { "zoom", "smoothness" }, { "zoom", "townX" },
             { "zoom", "animTime" }, { "cityView", "zoomX" },
             { "detail", "strength" }, { "detail", "fromZoom" }, { "detail", "fullZoom" } },
    shape = { label = "the shape settings (how much of the zone's shape, room to grow)",
              { "mapFrame", "shapeFollow" }, { "mapFrame", "shapeGrow" } },
}

-- Are you sure? Our own small dialog (not the game's popups, which can spread
-- "blocked action" taint like its dropdowns): text, then Reset / Cancel.
local confirm
local function Confirm(text, onYes)
    if not confirm then
        confirm = CreateFrame("Frame", "WaymarkConfirm", UIParent)
        ns.AddonWindow(confirm)
        confirm:SetFrameStrata("FULLSCREEN_DIALOG")
        -- (the dark rounded panel of the game's dropdown menus)
        local e = 20 / 68
        ns.SliceArt(confirm, "common-dropdown-bg", e, e, e, e, 16, 16, 16, 16)
        confirm:EnableMouse(true)
        confirm:SetWidth(340)
        confirm.text = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        confirm.text:SetPoint("TOP", 0, -22)
        confirm.text:SetWidth(290)
        local yes = RedButton(confirm)
        yes:SetSize(110, 22)
        yes:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -6, 18)
        yes:SetText("Reset")
        yes:SetScript("OnClick", function()
            confirm:Hide()
            if confirm.onYes then confirm.onYes() end
        end)
        local no = RedButton(confirm)
        no:SetSize(110, 22)
        no:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 6, 18)
        no:SetText("Cancel")
        no:SetScript("OnClick", function() confirm:Hide() end)
        tinsert(UISpecialFrames, "WaymarkConfirm")  -- (Escape cancels)
    end
    confirm.text:SetText(text)
    confirm.onYes = onYes
    confirm:SetHeight(confirm.text:GetStringHeight() + 76)
    confirm:ClearAllPoints()
    confirm:SetPoint("CENTER", panel or UIParent)
    confirm:Show()
    confirm:Raise()
end

function ns.ConfirmResetGroup(name)
    local g = RESET_GROUPS[name]
    Confirm("Put " .. g.label .. " back to how the addon comes?", function() ResetKeys(g) end)
end

-- Search ------------------------------------------------------------------

-- the entries on a page (Column's Index) that match the search
local function Matches(def)
    local out = {}
    if query == "" then return out end
    for _, e in ipairs(BuildPage(def).bfiSearch or {}) do
        if e.text:find(query, 1, true) then out[#out + 1] = e end
    end
    return out
end

-- a soft gold wash behind each match on the shown page
local function MarkMatches(def)
    local f = pageFrames[def.key]
    if not f then return end
    f.bfiFound = f.bfiFound or {}
    local found = Matches(def)
    for i, e in ipairs(found) do
        local t = f.bfiFound[i]
        if not t then
            t = f:CreateTexture(nil, "BACKGROUND")
            t:SetColorTexture(1, 0.82, 0, 0.14)
            f.bfiFound[i] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f, "TOPLEFT", e.x - 4, e.y + 2)
        t:SetSize(e.w - 6, e.h + 2)
        t:Show()
    end
    for i = #found + 1, #f.bfiFound do f.bfiFound[i]:Hide() end
end

local function SelectPage(key)
    for _, def in ipairs(PAGES) do
        local f = def.key == key and BuildPage(def) or pageFrames[def.key]
        if f then ShowPage(f, def.key == key) end
        local nb = navButtons[def.key]
        if nb then
            nb.selected:SetShown(def.key == key)
            if nb.Color then nb.Color() end
        end
        if def.key == key then
            MarkMatches(def)
            local first = Matches(def)[1]  -- (searching: the first match in view)
            if first then ScrollTo(f, first.y) end
            if pageTitle then
                local it = navItems.of[key]
                pageTitle:SetText(it and it.title or def.label)
                pageCrumb:SetText(it and #it.pages > 1 and def.label ~= it.title and def.label or "")
                -- (not while searching: every section is open then)
                pageFold:SetShown(f.bfiSections ~= nil and not foldsOpen)
                pageFold.Look()
            end
        end
    end
    -- (the way back: the pages you came through, newest last; the arrow left of the search box. "Go to:"
    -- buttons jump between pages, so there has to be a way back. The user, 2026-11-15. Kept on navItems:
    -- this file is near its limit of names.)
    navItems.trail = navItems.trail or {}
    if currentPage and currentPage ~= key and not navItems.goingBack then
        local t = navItems.trail
        t[#t + 1] = currentPage
        if #t > 30 then table.remove(t, 1) end
    end
    if navItems.backButton then navItems.backButton:SetEnabled(#navItems.trail > 0) end
    currentPage = key
    local entry = navItems.of[key]
    if entry then entry.last = key end
    for _, it in ipairs(navItems) do
        it.button.selected:SetShown(it == entry)
        it.Color()
    end
    if navItems.Tabs then navItems.Tabs() end
    ns.db.optionsWindow.page = key  -- (opens there again next time, after a reload too)
    if ns.HideOptionShadow then ns.HideOptionShadow() end  -- (a mark belongs to its page)
    ns.RefreshControls()
end

-- the list: every entry; or, while searching, only the entries with a page that matches (a page's name
-- counts too), each with how many. Returns the first page showing.
local noMatches
local nav, navScroll  -- (the list, and the scroll frame it sits in)
local NAV_TOP = -2
local NAV_W = 186  -- (options_list_active's width, near enough: the column's)
local NAV_BAR = 14  -- (narrower by this while the list's scroll bar shows)
local PANEL_W, PANEL_H = 900, 700  -- (the window, BuildPanel)

local function LayoutNav()
    local y, first = NAV_TOP, nil
    for _, it in ipairs(navItems) do
        local n, firstPage = 0, nil
        for _, def in ipairs(it.pages) do
            local m = query ~= "" and #Matches(def) or 0
            local show
            if query == "" then
                show = not (def.advancedOnly and not advancedShown)
            else
                show = m > 0 or def.label:lower():find(query, 1, true) ~= nil
            end
            it.found[def.key], it.shows[def.key] = m, show
            if show then firstPage = firstPage or def.key end
            n = n + m
        end
        it.first = firstPage
        it.button:SetShown(firstPage ~= nil)
        if firstPage then
            it.button:SetPoint("TOPLEFT", 0, y)
            it.head:SetText(it.title .. (n > 0 and ("  |cff999999(" .. n .. ")|r") or ""))
            y = y - it.button:GetHeight() - 2
            first = first or firstPage
        end
    end
    noMatches:SetShown(query ~= "" and not first)
    noMatches:SetPoint("TOPLEFT", 10, NAV_TOP - 6)
    -- longer than the column: it scrolls, its rows narrowed for the bar
    local view = navScroll:GetHeight()
    if view < 1 then view = PANEL_H - 64 - 46 - 16 end  -- (not laid out yet)
    local over = -y > view + 1
    local w = over and NAV_W - NAV_BAR or NAV_W
    for _, it in ipairs(navItems) do it.button:SetWidth(w) end
    nav:SetHeight(math.max(1, -y))
    if navScroll.ScrollBar then navScroll.ScrollBar:SetShown(over) end
    if not over then navScroll:SetVerticalScroll(0) end
    if navItems.Tabs then navItems.Tabs() end
    return first
end
-- throw every built page away; each is built again the next time it's needed
local function DropPages()
    CloseList()
    if listening then listening.Stop() end
    for _, f in pairs(pageFrames) do
        ShowPage(f, false)
        f.bfiDead = true
    end
    wipe(pageFrames)
    -- forget the old pages' controls
    for i = #controls, 1, -1 do
        local p = controls[i]:GetParent()
        if p and p.bfiDead then table.remove(controls, i) end
    end
    if ns.HideOptionShadow then ns.HideOptionShadow() end
end

-- New text sizes: the pages are thrown away and built again (rows are laid out
-- for their text's size). Waits until you let go of the mouse, so a slider
-- you're dragging isn't swapped out under the cursor.
local rebuildWaiting = false
-- A page built again, back where it was scrolled to, with no look at its top on the way: the scroll range is
-- asked for at once (UpdateScrollChildRect), and where the client still has none the page is unseen for the
-- one frame until it has. (Opening a section far down showed the top of the page for a blink, the user
-- 2026-11-15.)
-- Before a page is thrown away: the heading its view hangs on (the last one above the view's middle) and how
-- far the view's top is from it. Built again, the view is set from that heading, so what you were looking at
-- stays under your eyes when something higher up grew or shrank. (A tick on Start here changed the presets'
-- box at the page's top and everything below slid 90 px: the user's two screenshots, 2026-11-15.)
function navItems.Anchor(f, at)
    if not (f and f.bfiHeads) then return end
    local mid = at + (f.bfiScroll:GetHeight() or 0) / 2
    local best
    for _, h in ipairs(f.bfiHeads) do
        if -h.y <= mid and (not best or h.y < best.y) then best = h end
    end
    return best and { key = best.key, off = at + best.y }
end

function navItems.KeepScroll(f, at, anchor)
    if not (f and at) then return end
    for _, h in ipairs(anchor and f.bfiHeads or {}) do
        if h.key == anchor.key then at = math.max(0, -h.y + anchor.off) end
    end
    if at <= 0 then return end
    local sc = f.bfiScroll
    -- (how far it can scroll, from the page's own height: the frame's answer comes a frame late. A page made
    -- shorter, a section closed, ends at its new foot.)
    local want = math.min(at, math.max(0, (f:GetHeight() or 0) - (sc:GetHeight() or 0)))
    if sc.UpdateScrollChildRect then sc:UpdateScrollChildRect() end
    sc:SetVerticalScroll(want)
    local there = math.abs((sc:GetVerticalScroll() or 0) - want) < 1
    if not there then sc:SetAlpha(0) end   -- (only where the client would not take it yet)
    C_Timer.After(0, function()
        if math.abs((sc:GetVerticalScroll() or 0) - want) >= 1 then sc:SetVerticalScroll(want) end
        sc:SetAlpha(1)
    end)
end
local function RebuildPages()
    if IsMouseButtonDown("LeftButton") then
        C_Timer.After(0.2, RebuildPages)
        return
    end
    rebuildWaiting = false
    if not panel then return end
    -- (the page stays where it was scrolled to: built again it sprang to its top, on a tick on Start here
    -- and on a resize, the user 2026-11-15)
    local old = currentPage and pageFrames[currentPage]
    local at = old and old.bfiScroll:GetVerticalScroll() or 0
    local anchor = old and at > 0 and navItems.Anchor(old, at)
    DropPages()
    if currentPage then SelectPage(currentPage) end
    if query ~= "" then LayoutNav() end
    local f = currentPage and pageFrames[currentPage]
    navItems.KeepScroll(f, at, anchor)
end

function ns.RebuildOptionsPages()
    if rebuildWaiting then return end
    rebuildWaiting = true
    C_Timer.After(0.2, RebuildPages)
end

-- the pages built with or without the fine-tuning settings, as the switch and
-- the search want them (searching finds the hidden ones too); true if rebuilt
-- (and with every section open while searching, folded ones too)
local function MatchAdvanced()
    local want = (ns.db.optionsWindow.advanced or query ~= "") and true or false
    local open = query ~= ""
    if want == advancedShown and open == foldsOpen then return false end
    advancedShown, foldsOpen = want, open
    DropPages()
    return true
end

-- A section's +/- (Column's Header): fold it away or open it, and lay the
-- page out again, scrolled where it was
local function RelayoutPage()
    if not currentPage then return end
    local old = pageFrames[currentPage]
    local at = old and old.bfiScroll:GetVerticalScroll() or 0
    local anchor = old and at > 0 and navItems.Anchor(old, at)
    DropPages()
    SelectPage(currentPage)
    navItems.KeepScroll(pageFrames[currentPage], at, anchor)
end

function ns.ToggleOptionSection(key)
    ns.db.optionsWindow.folded[key] = not SectionFolded(key)
    RelayoutPage()
end

-- The page's sections all folded (the title's +/- then shows +)
local function PageFolded()
    local f = currentPage and pageFrames[currentPage]
    if not (f and f.bfiSections) then return false end
    for _, key in ipairs(f.bfiSections) do
        if not SectionFolded(key) then return false end
    end
    return true
end

-- The page title's +/-: any section open folds them all, else opens them all
local function FoldPage()
    local f = currentPage and pageFrames[currentPage]
    if not (f and f.bfiSections) then return end
    local fold = not PageFolded()
    for _, key in ipairs(f.bfiSections) do ns.db.optionsWindow.folded[key] = fold end
    RelayoutPage()
end

local function Search(text)
    query = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if MatchAdvanced() and currentPage then SelectPage(currentPage) end
    local first = LayoutNav()
    -- stay on the page you're on if it still matches, else the first that does
    local entry = currentPage and navItems.of[currentPage]
    local stay = entry and entry.shows[currentPage]
    if stay or not first then
        for _, def in ipairs(PAGES) do
            if def.key == currentPage then MarkMatches(def) end
        end
    else
        SelectPage(first)
    end
end

-- The window: the game's own Options look, from Forever's art. A metal frame
-- with its title bar and red close button, the search box under the title, a
-- dark inner panel (options_innerframe) with the category list in its left
-- column and the page on the right, and a footer under it.
local function MetalFrame(f)
    -- (the 2x art drawn at half size; its top 18 px are clear, above the title
    -- bar. It isn't symmetrical: the left pieces' edge line is 12.5 px in, the
    -- right and bottom pieces' 4 px, so they're moved out by that, as the game
    -- does, to put every line on the window's edge.)
    local L, R, B = -12, 4, -3
    local function Piece(name, w, h)
        local t = f:CreateTexture(nil, "BORDER", nil, 1)
        ns.SetArt(t, name)
        if w then t:SetSize(w, h) end
        return t
    end
    -- Without Forever's art (an Era-only player) it's Era's own classic window
    -- frame instead (Art.lua ART_SUBSTITUTE), at that art's sizes, its 28 px
    -- title bar along the top round the title
    if ns.UsingSubstitutes() then
        local tl = Piece("ui-frame-metal-cornertopleft-2x", 34, 33)
        tl:SetPoint("TOPLEFT", 0, 4)
        local tr = Piece("ui-frame-metal-cornertopright-2x", 33, 33)
        tr:SetPoint("TOPRIGHT", 0, 4)
        local bl = Piece("ui-frame-metal-cornerbottomleft-2x", 14, 14)
        bl:SetPoint("BOTTOMLEFT")
        local br = Piece("ui-frame-metal-cornerbottomright-2x", 11, 11)
        br:SetPoint("BOTTOMRIGHT")
        local top = Piece("_ui-frame-metal-edgetop-2x")
        top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
        top:SetPoint("TOPRIGHT", tr, "TOPLEFT")
        top:SetHeight(28)
        local bottom = Piece("_ui-frame-metal-edgebottom-2x")
        bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT")
        bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
        bottom:SetHeight(9)
        local left = Piece("!ui-frame-metal-edgeleft-2x")
        left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
        left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
        left:SetWidth(16)
        local right = Piece("!ui-frame-metal-edgeright-2x")
        right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
        right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
        right:SetWidth(10)
    else
        local tl = Piece("ui-frame-metal-cornertopleft-2x", 75, 75)
        tl:SetPoint("TOPLEFT", L, 18)
        local tr = Piece("ui-frame-metal-cornertopright-2x", 75, 75)
        tr:SetPoint("TOPRIGHT", R, 18)
        local bl = Piece("ui-frame-metal-cornerbottomleft-2x", ns.MetalCornerSize("ui-frame-metal-cornerbottomleft-2x"))
        bl:SetPoint("BOTTOMLEFT", L, B)
        local br = Piece("ui-frame-metal-cornerbottomright-2x", ns.MetalCornerSize("ui-frame-metal-cornerbottomright-2x"))
        br:SetPoint("BOTTOMRIGHT", R, B)
        local top = Piece("_ui-frame-metal-edgetop-2x")
        top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
        top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
        local bottom = Piece("_ui-frame-metal-edgebottom-2x")
        bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
        bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
        -- (the edges at the art's own 75 px width, so their line sits where the
        -- corners' does; squeezed, it was pulled out past the window)
        local left = Piece("!ui-frame-metal-edgeleft-2x")
        left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
        left:SetPoint("BOTTOMRIGHT", bl, "TOPLEFT", 75, 0)
        local right = Piece("!ui-frame-metal-edgeright-2x")
        right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
        right:SetPoint("BOTTOMLEFT", br, "TOPRIGHT", -75, 0)
    end
    -- the window's ground, under the frame
    local bg = f:CreateTexture(nil, "BACKGROUND")
    -- (the classic frame's title bar is see-through, so the ground goes up under it)
    bg:SetPoint("TOPLEFT", 2, ns.UsingSubstitutes() and 2 or -12)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(1, 1, 1, 1)
    if not pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(0.05, 0.05, 0.05, 1), CreateColor(0.11, 0.11, 0.11, 1)) then
        bg:SetColorTexture(0.08, 0.08, 0.08, 1)  -- (older SetGradient signature)
    end
end

-- the game's search box look (common-search-border) on SearchBoxTemplate's box
local function SearchLook(box)
    for _, k in ipairs({ "Left", "Middle", "Right", "Mid" }) do
        if box[k] and box[k].Hide then box[k]:Hide() end
    end
    local function Piece(name)
        local t = box:CreateTexture(nil, "BACKGROUND")
        ns.SetArt(t, name)
        return t
    end
    local l = Piece("common-search-border-left")
    l:SetSize(10, 26)
    l:SetPoint("LEFT", -6, 0)
    local r = Piece("common-search-border-right")
    r:SetSize(10, 26)
    r:SetPoint("RIGHT", 2, 0)
    local m = Piece("common-search-border-middle")
    m:SetPoint("TOPLEFT", l, "TOPRIGHT")
    m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
end

-- A small window of ours in the settings window's dress: its metal frame and ground, a title in the bar,
-- the red X in the corner, and the settings' backdrop tint (Frames.lua). The gear's quick panel builds the
-- same by hand; the welcome page takes it from here (the user, 2026-11-16: "Give same as quickpanel").
function ns.MetalWindow(f, titleText)
    MetalFrame(f)
    f:SetHitRectInsets(-4, -4, -8, -4)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, ns.FOREVER and 1 or -4)
    title:SetText(titleText or "Waymark")
    local x = CreateFrame("Button", nil, f)
    x:SetSize(24, 24)
    x:SetPoint("TOPRIGHT", ns.FOREVER and -2 or -5, ns.FOREVER and 4 or 1)
    if ns.UsingSubstitutes() then
        x:SetSize(21, 21)
        x:SetPoint("TOPRIGHT", -2, 3)
    end
    x:SetFrameLevel(f:GetFrameLevel() + 5)
    StateArt(x, "Normal", "redbutton-exit-c60-2x", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    StateArt(x, "Pushed", "redbutton-exit-pressed-c60-2x", "Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    local glow = StateArt(x, "Highlight", "redbutton-highlight-c60-2x", "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    if glow then glow:SetBlendMode("ADD") end
    x:SetScript("OnClick", function() f:Hide() end)
    ns.tintWindows = ns.tintWindows or {}
    ns.tintWindows[#ns.tintWindows + 1] = f
    if ns.FramesRefresh then pcall(ns.FramesRefresh) end
    return f
end

local function BuildPanel()
    advancedShown = ns.db.optionsWindow.advanced and true or false
    panel = CreateFrame("Frame", "WaymarkOptions", UIParent)
    -- (not an ns.AddonWindow: the settings keep their size whatever "Waymark size" says, the user 2026-11-15.
    -- Their own text size is the box at the foot of the window.)
    panel:SetSize(PANEL_W, ns.db.optionsWindow.height or PANEL_H)
    panel:SetScale(ns.db.optionsWindow.scale or 1)
    -- (the metal frame is drawn a little past the window: clicks there went into the world)
    panel:SetHitRectInsets(-4, -4, -8, -4)
    panel:SetPoint("CENTER")
    -- (a layer above DIALOG: the quill bar and other bars there stay under it; its
    -- dropdowns, pop-ups and the import / export windows are in FULLSCREEN_DIALOG)
    panel:SetFrameStrata("FULLSCREEN")
    panel:SetToplevel(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:SetClampRectInsets(0, 0, 18, 0)
    tinsert(UISpecialFrames, "WaymarkOptions")  -- closes on Escape
    MetalFrame(panel)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, ns.FOREVER and 1 or -4)  -- (Forever: in the middle of the title bar)
    title:SetText("Waymark")
    -- the close button: Forever's own red X, in its bronze rim (redbutton-*-c60)
    local close = CreateFrame("Button", nil, panel)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", ns.FOREVER and -2 or -5, ns.FOREVER and 4 or 1)
    if ns.UsingSubstitutes() then
        -- (our own X, Art.lua: no margin round it, so a smaller button, in the
        -- socket of the classic frame's top-right corner: UI-Frame-TopCornerRight,
        -- 33 px at TOPRIGHT 0, 4 (MetalFrame), has a 16 px hole centred at 20.5,
        -- 11.5 of it, so -12.5, -7.5 from the window's corner)
        close:SetSize(21, 21)
        close:SetPoint("TOPRIGHT", -2, 3)
    end
    close:SetFrameLevel(panel:GetFrameLevel() + 5)
    StateArt(close, "Normal", "redbutton-exit-c60-2x", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    StateArt(close, "Pushed", "redbutton-exit-pressed-c60-2x", "Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    local glow = StateArt(close, "Highlight", "redbutton-highlight-c60-2x", "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    if glow then glow:SetBlendMode("ADD") end
    close:SetScript("OnClick", function() panel:Hide() end)

    -- its bottom-right corner follows the mouse, as the quest window's: sideways scales it
    -- (pages are built CONTENT_W across, so it can't widen), the rest goes to its height
    local grip = CreateFrame("Button", nil, panel)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", 3, 2)   -- (5 px further right: it sat short of the frame's corner, the user 2026-11-15)
    grip:SetFrameLevel(panel:GetFrameLevel() + 30)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local ow = ns.db.optionsWindow
        local ui = UIParent:GetEffectiveScale()
        local k0 = panel:GetScale()
        local left, top = panel:GetLeft() * k0, panel:GetTop() * k0  -- (UIParent units; the top-left stays put)
        local w0, h0 = PANEL_W * k0, panel:GetHeight() * k0
        local x0, y0 = GetCursorPosition()
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local k = math.max(0.7, math.min(1.4, k0 * (w0 + (x - x0) / ui) / w0))
            local h = math.max(520, math.min(1100, (h0 + (y0 - y) / ui) / k))
            panel:SetScale(k)
            panel:SetHeight(h)
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / k, top / k)
            ow.scale, ow.height = k, h
        end)
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not grip:GetScript("OnUpdate") then return end
        grip:SetScript("OnUpdate", nil)
        local ow = ns.db.optionsWindow
        if ow.height then ow.height = math.floor(ow.height + 0.5) end
        ns.RebuildOptionsPages()  -- (the lists' scrolling, for the new height)
    end)
    grip:SetScript("OnClick", function()   -- (right-click: as it comes)
        local ow = ns.db.optionsWindow
        ow.scale, ow.height = nil, nil
        panel:SetScale(1)
        panel:SetHeight(PANEL_H)
        panel:ClearAllPoints()
        panel:SetPoint("CENTER")
        ns.RebuildOptionsPages()
    end)
    grip:SetScript("OnEnter", function()
        GameTooltip:SetOwner(grip, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Size")
        ns.Hints({ { "Drag", "sideways its scale, up and down its height" }, { "Right-click", "back to its own size" } })
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- the inner panel: options_innerframe, its line at about 198 px is the
    -- category column's right edge
    local inner = CreateFrame("Frame", nil, panel)
    inner:SetPoint("TOPLEFT", 12, -64)
    inner:SetPoint("BOTTOMRIGHT", -12, 46)
    local innerArt = inner:CreateTexture(nil, "BACKGROUND")
    innerArt:SetAllPoints()
    ns.SetArt(innerArt, "options_innerframe")

    -- category list, in the inner panel's left column; it scrolls when it's
    -- longer than the column (LayoutNav), the page's thin bar at its right
    navScroll = CreateFrame("ScrollFrame", nil, inner, "UIPanelScrollFrameTemplate")
    navScroll:SetPoint("TOPLEFT", 6, -8)
    navScroll:SetPoint("BOTTOMLEFT", 6, 8)
    navScroll:SetWidth(NAV_W)
    nav = CreateFrame("Frame", nil, navScroll)
    nav:SetSize(NAV_W, 10)
    navScroll:SetScrollChild(nav)
    local navBar = navScroll.ScrollBar
    if navBar then
        MinimalScrollBar(navBar)
        navBar:ClearAllPoints()
        navBar:SetPoint("TOPRIGHT", navScroll, "TOPRIGHT", 2, -2)
        navBar:SetPoint("BOTTOMRIGHT", navScroll, "BOTTOMRIGHT", 2, 2)
        navBar:SetWidth(10)
        navBar:Hide()
        navScroll:HookScript("OnScrollRangeChanged", function(self, _, yRange)
            navBar:SetShown((yRange or self:GetVerticalScrollRange()) > 1)
        end)
    end

    -- (Combat's page only with its addon switched on, the Lab's only where Lab\ is, Dev only where
    -- DevBar.lua is: releases leave it out)
    for i = #PAGES, 1, -1 do
        local key = PAGES[i].key
        if (key == "combat" and not WaymarkCombat) or (key == "dev" and not ns.DevCommands) or (key == "traversal" and not ns.SetupTransports) or (key == "told" and not ns.ToldNow) or (key:find("^lab") and not ns.LabPage) then table.remove(PAGES, i) end
    end
    -- ("What the map does by itself" last: a map button's right-click goes to the first page with its
    -- setting (ns.ShowOption), and that should be the setting's own page where it has one)
    for i, def in ipairs(PAGES) do
        if def.key == "acts" then
            table.insert(PAGES, table.remove(PAGES, i))
            break
        end
    end
    local byKey = {}
    for _, def in ipairs(PAGES) do byKey[def.key] = def end

    -- A page in the list: gold, white under the mouse and while it's open
    -- (options_list_hover / options_list_active behind it)
    local function NavButton(parent, w, h)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(w, h)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        ns.SetArt(hl, "options_list_hover")
        b.selected = b:CreateTexture(nil, "BACKGROUND", nil, 2)
        b.selected:SetAllPoints()
        ns.SetArt(b.selected, "options_list_active")
        b.selected:Hide()
        return b
    end

    -- The entries: { name, the line under it, its pages in tab order }. A page that isn't in this build
    -- (Traversal, Frames, the Lab's, Dev, Combat's) is left out; an entry with none left is too.
    local ENTRIES = {
        { "Start here", "Presets, and all Waymark can do", "overview" },
        { "How it looks", "Shaded land, frame, clear view, buttons", "look", "header", "clearview", "window", "controls", "tipsmenus" },
        { "How it acts", "Follows you, zooms in towns, folds", "acts", "town", "browse" },
        { "On the map", "Townsfolk, rares, herbs and ore, boats", "shownhome", "people", "group", "rares", "explore", "traversal", "clock" },
        { "Quests", ns.ToldNow and "Givers, their words, tracker, quest log" or "Givers, tracker, quest log", "quests", "told", "tracker", "questlog" },
        { "Dungeons & the book", "Dungeon maps, the found notes, your ink", "dungeon", "ink" },
        { "As your minimap", "The map in the minimap's place", "minimap" },
        { "Keys", "Three worth having", "keys" },
        { "Your setups", "Save, share, weaker PCs", "setups", "performance", "profiles" },
        { "Development", "Dev commands and the Lab", "dev", "lab", "labminimap", "labhorizon", "labframes" },
        { "Combat bars", "Waymark: Combat", "combat" },
    }
    -- (a tab's name where the page's own is too long for a row of tabs, or says the entry's name again;
    -- the page's own name stays beside the title)
    local TAB = { look = "The map", labframes = "Themes", controls = "Buttons",
                  acts = "All of it", browse = "Zoom & other zones", shownhome = "Layers",
                  group = "Group", rares = "Rares & nodes", quests = "Quest pins", tracker = "Tracker",
                  setups = "Your presets", clock = "Clock & coords" }
    local TAB_ICON = { dungeon = "dungeons", ink = "book" }
    -- the tabs' row, between the title and the divider; an entry of one page has its line there instead
    local strip = CreateFrame("Frame", nil, inner)
    strip:SetPoint("TOPLEFT", inner, "TOPLEFT", 212, -40)
    strip:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    strip:SetHeight(24)
    local stripLine = strip:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    stripLine:SetPoint("LEFT", 20, 0)
    stripLine:SetTextColor(0.6, 0.6, 0.6)

    for _, e in ipairs(ENTRIES) do
        local it = { title = e[1], line = e[2], pages = {}, shows = {}, found = {} }
        for i = 3, #e do
            local def = byKey[e[i]]
            if def then
                it.pages[#it.pages + 1] = def
                navItems.of[def.key] = it
                local b = NavButton(strip, 60, 22)
                local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                text:SetPoint("CENTER")
                b.text, b.label = text, TAB[def.key] or def.label
                -- (the icon the thing has on the map, before its tab's name: the user, 2026-11-15)
                local icon = TAB_ICON[def.key] and ns.ToggleIcon and ns.ToggleIcon(TAB_ICON[def.key])
                if icon then
                    local tex = b:CreateTexture(nil, "OVERLAY")
                    tex:SetSize(16, 16)
                    tex:SetPoint("RIGHT", text, "LEFT", -4, 0)
                    ns.SetIconArt(b, tex, icon)
                    text:SetPoint("CENTER", 10, 0)
                    b.iconW = 20
                end
                -- (greyed: the addon it needs isn't installed)
                local missing = def.needs and not ns.AddonPresent(def.needs)
                -- (underlines, as the tabs on the pages themselves (Townsfolk, Header & border): a thin dim
                -- line under a tab not picked, white words and a bright line under the picked one, and no
                -- glow behind it. As plain gold words the row read as a caption; with a backing each, as
                -- grey slabs. The user, 2026-11-15: "People will find these tabs, right?", "This looks bad".)
                b.selected:SetAlpha(0)   -- (still what says which is picked)
                local under = b:CreateTexture(nil, "ARTWORK")
                under:SetPoint("BOTTOMLEFT", 4, 0)
                under:SetPoint("BOTTOMRIGHT", -4, 0)
                b.Color = function()
                    local picked, over = b.selected:IsShown(), b:IsMouseOver()
                    if missing then text:SetTextColor(0.55, 0.5, 0.45)
                    elseif picked or over then text:SetTextColor(1, 1, 1)
                    else text:SetTextColor(1, 0.82, 0) end
                    under:SetHeight(picked and 2 or 1)
                    under:SetColorTexture(1, 0.82, 0, picked and 0.9 or missing and 0.12 or over and 0.6 or 0.28)
                end
                b:SetScript("OnEnter", function()
                    b.Color()
                    if missing then
                        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
                        GameTooltip:SetText("Needs " .. def.needs, 1, 0.5, 0.3)
                        GameTooltip:Show()
                    end
                end)
                b:SetScript("OnLeave", function()
                    b.Color()
                    GameTooltip:Hide()
                end)
                b.Color()
                b:SetScript("OnClick", function() SelectPage(def.key) end)
                b:Hide()
                navButtons[def.key] = b
            end
        end
        if #it.pages > 0 then
            local b = NavButton(nav, NAV_W, 40)
            b:SetFrameLevel(nav:GetFrameLevel() + 4)
            local head = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            head:SetPoint("TOPLEFT", 10, -6)
            head:SetWidth(NAV_W - 16)
            head:SetJustifyH("LEFT")
            head:SetWordWrap(false)
            head:SetText(it.title)
            local sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
            sub:SetWidth(NAV_W - 30)  -- (room for the list's scroll bar, when it shows)
            sub:SetJustifyH("LEFT")
            sub:SetTextColor(0.62, 0.6, 0.56)
            sub:SetText(it.line)
            b:SetHeight(math.max(38, 6 + head:GetStringHeight() + 2 + sub:GetStringHeight() + 7))
            it.Color = function()
                if b.selected:IsShown() or b:IsMouseOver() then head:SetTextColor(1, 1, 1)
                else head:SetTextColor(1, 0.82, 0) end
            end
            b:SetScript("OnEnter", it.Color)
            b:SetScript("OnLeave", it.Color)
            -- (back to the tab you had open in it; searching: its first page with a match)
            b:SetScript("OnClick", function()
                SelectPage((it.last and it.shows[it.last] and it.last) or it.first or it.pages[1].key)
            end)
            it.Color()
            it.button, it.head = b, head
            navItems[#navItems + 1] = it
        end
    end

    -- the open page's entry: its pages as tabs, left to right (searching: those with a match, each with
    -- how many, and the open one); pressed together when they'd run past the row
    navItems.Tabs = function()
        for _, b in pairs(navButtons) do b:Hide() end
        local it = currentPage and navItems.of[currentPage]
        local tabs = {}
        for _, def in ipairs(it and it.pages or {}) do
            if it.shows[def.key] ~= false or def.key == currentPage then tabs[#tabs + 1] = def end
        end
        stripLine:SetShown(#tabs < 2)
        stripLine:SetText(it and it.line or "")
        if #tabs < 2 then return end
        local total = 0
        for _, def in ipairs(tabs) do
            local b = navButtons[def.key]
            local n = query ~= "" and it.found[def.key] or 0
            b.text:SetText(b.label .. (n > 0 and ("  |cff999999(" .. n .. ")|r") or ""))
            total = total + b.text:GetStringWidth() + (b.iconW or 0)
        end
        local room = strip:GetWidth()
        if room < 1 then room = PANEL_W - 24 - 212 - 12 end  -- (not laid out yet)
        local pad = math.max(8, math.min(24, (room - 20 - total) / #tabs - 2))
        local x = 16
        for _, def in ipairs(tabs) do
            local b = navButtons[def.key]
            b:SetWidth(b.text:GetStringWidth() + (b.iconW or 0) + pad)
            b:ClearAllPoints()
            b:SetPoint("LEFT", strip, "LEFT", x, 0)
            b:Show()
            b.Color()
            x = x + b:GetWidth() + 2
        end
    end

    -- the search box, under the title (the game's search box look)
    local ok, box = pcall(CreateFrame, "EditBox", nil, panel, "SearchBoxTemplate")
    if not ok then box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate") end
    box:SetSize(154, 22)
    box:SetPoint("TOPLEFT", 50, -32)
    -- back to the page you were on (the game's own page arrow)
    local back = CreateFrame("Button", nil, panel)
    back:SetSize(24, 24)
    back:SetPoint("RIGHT", box, "LEFT", -8, 0)
    back:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    back:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    back:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    back:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    back:SetScript("OnClick", function()
        local t = navItems.trail or {}
        local key = table.remove(t)
        -- (a page that has gone since: the one before it)
        while key and not navItems.of[key] do key = table.remove(t) end
        if not key then back:SetEnabled(false) return end
        navItems.goingBack = true
        local ok, err = pcall(ns.OpenOptionsPage, key)
        navItems.goingBack = nil
        if not ok and ns.Log then ns.Log("Back:", tostring(err)) end
        back:SetEnabled(#t > 0)
    end)
    back:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Back to the page you were on")
        GameTooltip:Show()
    end)
    back:SetScript("OnLeave", function() GameTooltip:Hide() end)
    back:SetEnabled(#(navItems.trail or {}) > 0)
    navItems.backButton = back
    SearchLook(box)
    box:SetAutoFocus(false)
    box:HookScript("OnTextChanged", function(self) Search(self:GetText()) end)
    box:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    noMatches = nav:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noMatches:SetText("No settings match.")
    noMatches:Hide()
    LayoutNav()

    -- over the page: its name, large and white, the group it's in after it in
    -- grey, and the game's divider under them; the page scrolls beneath
    -- (the +/- in line with the sections' own, the title with their headings)
    pageFold = FoldButton(inner, PageFolded, FoldPage)
    pageFold:SetPoint("TOPLEFT", inner, "TOPLEFT", 211, -15)
    pageFold:SetScript("OnEnter", function()
        GameTooltip:SetOwner(pageFold, "ANCHOR_RIGHT")
        GameTooltip:SetText(PageFolded() and "Open every section" or "Fold every section away")
        GameTooltip:Show()
    end)
    pageFold:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pageTitle = inner:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    pageTitle:SetPoint("TOPLEFT", inner, "TOPLEFT", 232, -14)
    local font, _, flags = pageTitle:GetFont()
    if font then pageTitle:SetFont(font, 20, flags or "") end
    pageTitle:SetShadowColor(0, 0, 0, 1)
    pageTitle:SetShadowOffset(1, -1)
    pageCrumb = inner:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    pageCrumb:SetPoint("BOTTOMLEFT", pageTitle, "BOTTOMRIGHT", 10, 1)
    pageCrumb:SetTextColor(0.6, 0.6, 0.6)
    local divider = inner:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", inner, "TOPLEFT", 212, -68)
    divider:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    divider:SetHeight(1)
    ns.SetArt(divider, "options_horizontaldivider")

    -- the page, right of the list (room for the scroll bar on its right)
    content = CreateFrame("Frame", nil, inner)
    content:SetPoint("TOPLEFT", inner, "TOPLEFT", 214, -76)
    content:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -26, 6)

    -- footer, right: put this page's settings back to how the addon comes
    -- (once you've said yes)
    local reset = RedButton(panel, 160, 24)
    reset:SetPoint("BOTTOMRIGHT", -22, 14)
    reset:SetText("Reset this page")
    reset:SetScript("OnClick", function()
        local key = currentPage
        local def = key and byKey[key]
        if not def then return end
        Confirm("Put every setting on " .. def.label .. " back to how the addon comes?",
            function() ResetPage(key) end)
    end)
    reset:SetScript("OnEnter", function()
        GameTooltip:SetOwner(reset, "ANCHOR_TOP")
        GameTooltip:SetText("Reset this page")
        GameTooltip:AddLine("Every setting on this page back to how the addon comes. Other pages stay as they are.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- footer, left: the fine-tuning settings on every page, or not
    local adv = CreateCheck(panel, "Show advanced settings",
        function() return ns.db.optionsWindow.advanced end,
        function(v)
            ns.db.optionsWindow.advanced = v
            if MatchAdvanced() and currentPage then SelectPage(currentPage) end
            LayoutNav()
        end)
    adv.text:SetFontObject(GameFontNormal)
    adv.text:SetTextColor(1, 0.82, 0)
    adv:SetHitRectInsets(0, -adv.text:GetStringWidth() - 4, 0, 0)
    adv:SetPoint("BOTTOMLEFT", 22, 14)
    adv:HookScript("OnEnter", function()
        GameTooltip:SetOwner(adv, "ANCHOR_TOP")
        GameTooltip:SetText("Show advanced settings")
        GameTooltip:AddLine("Adds the fine-tuning to every page: nudges, thicknesses, fonts, spacing. Search finds these settings even when this is off.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    adv:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- footer, beside it: the settings pages' text size (headings kept 3 above it,
    -- as the game's Options have them); the pages are laid out again for it
    local sizeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("LEFT", adv.text, "RIGHT", 28, 0)
    sizeLabel:SetText("Text size")
    local size = CreateDropdown(panel, 64, function() return OptionSize("text") end, function(v)
        ns.db.optionsText.text = v
        ns.db.optionsText.heading = v + (HEADING_SIZE - NORMAL_SIZE)
        ns.OnSettingChanged("optionsText", "text")
    end, SizeChoices(9, 18, NORMAL_SIZE))
    size:SetPoint("LEFT", sizeLabel, "RIGHT", 8, 0)
    size:HookScript("OnEnter", function()
        GameTooltip:SetOwner(size, "ANCHOR_TOP")
        GameTooltip:SetText("Text size")
        GameTooltip:AddLine("Of these settings pages: labels, values and notes, the headings a little larger.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    size:HookScript("OnLeave", function() GameTooltip:Hide() end)
    size.Refresh()

    panel:SetScript("OnShow", ns.RefreshControls)
    panel:SetScript("OnHide", function() ns.HideOptionShadow() end)
end

-- page: optional page key to open on
function ns.ToggleOptions(page)
    if not ns.db then return end
    -- (the quick panel shares the screen's top layer: never left over the window)
    if ns.HideQuickPanel then ns.HideQuickPanel() end
    if not panel then
        BuildPanel()
        panel:Hide()
    end
    if page then
        SelectPage(page)
        panel:Show()
        return
    end
    if not currentPage then
        -- the page you had open last, even before a reload
        local last = ns.db.optionsWindow.page
        local known = false
        -- (a page the list no longer holds, the old Extras summary: Start here)
        for _, def in ipairs(PAGES) do if def.key == last and navItems.of[last] then known = true end end
        SelectPage(known and last or PAGES[1].key)
    end
    panel:SetShown(not panel:IsShown())
end

function ns.ToggleTownsfolkOptions() ns.ToggleOptions("people") end

-- for the Overview page's > buttons
function ns.OpenOptionsPage(key)
    -- (from outside the window, Waymark: Combat's settings say: the window built and opened first.
    -- Before it was ever opened its page frame didn't exist yet, an error, the user 2026-11-09)
    if not (panel and panel:IsShown()) then return ns.ToggleOptions(key) end
    ns.GlowNavPage(key, false)  -- (the mouse is still on the button as the page changes)
    SelectPage(key)
end

-- a page's name in the list, lit as if hovered (on) or back to normal
function ns.GlowNavPage(key, on)
    local it = navItems.of[key]
    local tab, entry = navButtons[key], it and it.button
    if tab then if on then tab:LockHighlight() else tab:UnlockHighlight() end end
    if entry then if on then entry:LockHighlight() else entry:UnlockHighlight() end end
end

-- Open the page a setting lives on and put a soft shadow behind it (until you
-- go to another page or close the window). From a toggle button's right-click.
-- The page is the one with that setting's control on it (its Mark).
local shaded  -- the page with a shade on it

function ns.ShowOption(group, key)
    if not ns.db then return end
    if not panel then
        BuildPanel()
        panel:Hide()
    end
    local page, m
    for _, def in ipairs(PAGES) do
        local marks = not def.summary and BuildPage(def).bfiMarks
        if marks and marks[group .. "/" .. key] then
            page, m = def.key, marks[group .. "/" .. key]
            break
        end
    end
    if not page then
        for _, def in ipairs(PAGES) do
            for _, k in ipairs(not def.summary and BuildPage(def).bfiKeys or {}) do
                if k[1] == group and k[2] == key then
                    ns.ToggleOptions(def.key)
                    return
                end
            end
        end
        return
    end
    -- its section folded away: open it, and find it on the page laid out again
    if m.sec and SectionFolded(m.sec) then
        ns.db.optionsWindow.folded[m.sec] = false
        DropPages()
        for _, def in ipairs(PAGES) do
            if def.key == page then m = BuildPage(def).bfiMarks[group .. "/" .. key] or m end
        end
    end
    ns.ToggleOptions(page)
    local f = pageFrames[page]
    ScrollTo(f, m.y)
    -- textures on the page itself, in its lowest layer: under the labels
    if not f.bfiShade then
        f.bfiShade = f:CreateTexture(nil, "BACKGROUND")
        f.bfiShade:SetColorTexture(1, 0.82, 0, 0.10)  -- a faint gold wash
        f.bfiShadeEdge = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.bfiShadeEdge:SetColorTexture(1, 0.82, 0, 0.8)
        f.bfiShadeEdge:SetWidth(2)
    end
    f.bfiShade:ClearAllPoints()
    f.bfiShade:SetPoint("TOPLEFT", f, "TOPLEFT", m.x - 4, m.y + 2)
    f.bfiShade:SetSize(m.w - 6, m.h + 2)
    f.bfiShadeEdge:ClearAllPoints()
    f.bfiShadeEdge:SetPoint("TOPLEFT", f.bfiShade, "TOPLEFT")
    f.bfiShadeEdge:SetPoint("BOTTOMLEFT", f.bfiShade, "BOTTOMLEFT")
    f.bfiShade:Show()
    f.bfiShadeEdge:Show()
    shaded = f
end

-- A page opened for one setting (the ">" on a layer's row): that setting's section unfolded and in view. The
-- page alone when the setting has no row of its own there. (Unexplored land and Area names opened their tab
-- with every section shut, the user 2026-11-15.)
function ns.OpenOptionAt(page, group, key)
    local def
    for _, d in ipairs(PAGES) do
        if d.key == page then def = d end
    end
    local id = tostring(group) .. "/" .. tostring(key)
    local m = def and not def.summary and (BuildPage(def).bfiMarks or {})[id]
    if m and m.sec and SectionFolded(m.sec) then
        ns.db.optionsWindow.folded[m.sec] = false
        DropPages()
        m = (BuildPage(def).bfiMarks or {})[id] or m
    end
    ns.OpenOptionsPage(page)
    if m and pageFrames[page] then ScrollTo(pageFrames[page], m.y) end
end

function ns.HideOptionShadow()
    if shaded then
        shaded.bfiShade:Hide()
        shaded.bfiShadeEdge:Hide()
        shaded = nil
    end
end

-- In the game's own Settings > AddOns: a short page that opens ours
local function RegisterGameSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local stub = CreateFrame("Frame")
    local t = stub:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("Waymark")
    local b = RedButton(stub)
    b:SetSize(200, 26)
    b:SetPoint("TOPLEFT", 16, -50)
    b:SetText("Open settings")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns.ToggleOptions(currentPage or PAGES[1].key)
    end)
    pcall(function()
        local cat = Settings.RegisterCanvasLayoutCategory(stub, "Waymark")
        Settings.RegisterAddOnCategory(cat)
    end)
end
RegisterGameSettings()

-- Quick options on the Battlefield Map ------------------------------------

local quickButton, quickPanel
local townButton, cityButton  -- town / city view on/off, left of the gear (BuildViewButton)
local dockButton              -- minimap replacement on/off, left of those

local function BuildQuickPanel(map)
    -- parented to UIParent, not the map, so it keeps a normal size on a scaled-up
    -- map; anchors work across scales, so it still hangs off the gear button
    quickPanel = CreateFrame("Frame", nil, UIParent)
    ns.AddonWindow(quickPanel)
    -- (the settings window's own frame and ground, its title in the bar: it had a tooltip's border, and
    -- "doesnt match our settings frame", the user 2026-11-16)
    MetalFrame(quickPanel)
    quickPanel:SetHitRectInsets(-4, -4, -8, -4)
    ns.quickPanelFrame = quickPanel   -- (Frames.lua: the settings window's backdrop choice tints it too)
    if ns.FramesRefresh then pcall(ns.FramesRefresh) end
    do
        local title = quickPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, ns.FOREVER and 1 or -4)
        title:SetText("Waymark")
    end
    quickPanel:SetFrameStrata("DIALOG")
    quickPanel:EnableMouse(true)
    -- beside the map, not over it: to its left, or to its right when the left
    -- side of the screen hasn't room (decided each time it opens)
    -- Then it is pinned to the screen at that spot. It hung on the map (docked: on the minimap), so it
    -- jumped about while the docked map was dragged, and landed oddly when the map was docked from the
    -- panel's own buttons: the user, 2026-11-15. Now it stays where it opened, whatever the map does, and
    -- a drag moves it for as long as it is open.
    local function Place(self)
        self:ClearAllPoints()
        self:SetClampedToScreen(true)
        -- (docked: beside the square, which sits where the minimap is. To its left, or to its right when
        -- the square has been moved to the left of the screen: it opened over the map there, the user,
        -- 2026-11-16)
        -- (always by the map itself, clear of the metal frame, which reaches past the panel. Docked it hung
        -- on the minimap, but the live dots shrink the real minimap and lay it on your arrow, so the panel
        -- opened from the middle of the map: the user's shot, 2026-11-16)
        local by, pad = map, 18
        local left = by:GetLeft() and by:GetLeft() * by:GetEffectiveScale() / self:GetEffectiveScale()
        if left and left < self:GetWidth() + pad then
            self:SetPoint("TOPLEFT", by, "TOPRIGHT", pad, 0)
        else
            self:SetPoint("TOPRIGHT", by, "TOPLEFT", -pad, 0)
        end
        local l, t = self:GetLeft(), self:GetTop()
        if l and t then
            -- (kept on the screen: a pinned spot past the edge would be pushed back by the clamp each frame)
            local sw = UIParent:GetWidth() * UIParent:GetEffectiveScale() / self:GetEffectiveScale()
            local sh = UIParent:GetHeight() * UIParent:GetEffectiveScale() / self:GetEffectiveScale()
            l = math.max(0, math.min(l, sw - self:GetWidth()))
            t = math.max(self:GetHeight(), math.min(t, sh))
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
        end
    end
    quickPanel:SetMovable(true)
    quickPanel:RegisterForDrag("LeftButton")
    quickPanel:SetScript("OnDragStart", quickPanel.StartMoving)
    quickPanel:SetScript("OnDragStop", quickPanel.StopMovingOrSizing)

    -- (mockups\quick-options.html, round 2: only what you switch as you play;
    -- set-once switches stay in the settings window)
    local W = 200
    local FULL = 2 * W + 6
    local function Tip(owner, title, text)
        owner:HookScript("OnEnter", function()
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(title, 1, 0.82, 0)
            if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- while a context profile overrides a row's layer: where, after its label
    -- ("(in town)"), green when it shows the layer there, red when it hides it
    local WHERE = { combat = "in combat", battleground = "in a battleground", dungeon = "in a dungeon",
                    city = "in town" }
    local ctx = {}
    local function Context(label, groups)
        local fs = quickPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", label, "RIGHT", 5, 0)
        ctx[#ctx + 1] = { fs = fs, groups = groups }
    end
    -- (with no context on, a row some context does change says "(open world)",
    -- in grey: your own setting is what you see now)
    local function RefreshContext()
        local k = ns.ActiveProfileKey and ns.ActiveProfileKey()
        local p = k and ns.db.profiles[k]
        for _, c in ipairs(ctx) do
            local v, somewhere
            for _, g in ipairs(c.groups) do
                if p and p.layers[g] ~= nil then v = p.layers[g] end
                for _, key in ipairs(ns.PROFILE_ORDER or {}) do
                    local q = ns.db.profiles[key]
                    if q and q.enabled and q.layers[g] ~= nil then somewhere = true end
                end
            end
            if v ~= nil then
                c.fs:SetText((v and "|cff4ddf4d(" or "|cffff6a4d(") .. (WHERE[k] or k) .. ")|r")
            elseif not k and somewhere then
                c.fs:SetText("|cff9d9d9d(open world)|r")
            else
                c.fs:SetText("")
            end
        end
    end

    -- right-click a row: a menu with "settings", which opens the settings window
    -- at that setting, marked (ns.ShowOption), as the map's toggle buttons do
    local function SettingsMenu(f, group, key)
        f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local orig = f:GetScript("OnClick")
        f:SetScript("OnClick", function(self, button, ...)
            if button == "RightButton" then
                if self.Refresh then self.Refresh() end  -- (a box ticks itself on any click: put it back)
                GameTooltip:Hide()
                if ns.QuillMenu then
                    ns.QuillMenu({ { "settings", function()
                        quickPanel:Hide()
                        ns.ShowOption(group, key)
                    end } })
                end
                return
            end
            if orig then orig(self, button, ...) end
        end)
    end

    -- the map: a window, clear view, or over the minimap (as on Start here)
    local top = Column(quickPanel, 10, -22, FULL)   -- (under the frame's title bar)
    top:Header("The map")
    local roles, prev = {}, nil
    for _, r in ipairs({ { "window", "Window" }, { "clear", "Clear view" }, { "dock", "Minimap" } }) do
        local b = RedButton(quickPanel)
        b:SetSize((FULL - 8) / 3, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, top.y - 2) end
        b:SetText(r[2])
        b:SetScript("OnClick", function()
            -- (the panel stays where it is on the screen: these buttons are under the pointer)
            SetMapRole(r[1])
            ns.RefreshControls()
        end)
        b.role = r[1]
        roles[#roles + 1] = b
        prev = b
    end
    Tip(roles[1], "The map", "Window: a map you can move. Clear view: no frame, just the map over the world. Minimap: the map replaces your minimap.")
    for i = 2, 3 do Tip(roles[i], "The map", "Window: a map you can move. Clear view: no frame, just the map over the world. Minimap: the map replaces your minimap.") end
    top.y = top.y - 30

    -- the preset you're on, and a way to the presets (Start here)
    local presetText = quickPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    presetText:SetPoint("LEFT", quickPanel, "TOPLEFT", 14, top.y - 11)
    presetText:SetWidth(FULL - 110)
    presetText:SetJustifyH("LEFT")
    presetText:SetWordWrap(false)
    local presets = RedButton(quickPanel)
    presets:SetSize(96, 22)
    presets:SetPoint("RIGHT", quickPanel, "TOPLEFT", 10 + FULL, top.y - 11)
    presets:SetText("Presets")
    presets:SetScript("OnClick", function()
        quickPanel:Hide()
        ns.ToggleOptions("overview")
    end)
    top.y = top.y - 26
    local head = CreateFrame("Frame", nil, quickPanel)
    head.Refresh = function()
        local now = MapRole()
        for _, b in ipairs(roles) do
            if b.role == now then b:LockHighlight() else b:UnlockHighlight() end
        end
        local base = ns.db.presetBase
        if base and ns.PresetName then
            local altered = ns.PresetChanges and #ns.PresetChanges(base) > 0
            presetText:SetText("Preset: |cffffffff" .. ns.PresetName(base) .. "|r" .. (altered and " |cffff9933(altered)|r" or ""))
        elseif ns.PresetChanges and #ns.PresetChanges("simple") == 0 then
            presetText:SetText("Preset: |cffffffffSimple|r")  -- (as it ships: none picked yet)
        else
            presetText:SetText("Preset: |cffffffffnone|r (your own settings)")
        end
        RefreshContext()
    end
    local tick = 0
    head:SetScript("OnUpdate", function(_, dt)
        tick = tick + dt
        if tick < 0.5 then return end
        tick = 0
        RefreshContext()
    end)
    controls[#controls + 1] = head

    -- a row with its label at the left and a button going round its values
    -- (values = { { label, matches(), set() }, ... }; none matching: "Your mix")
    local function CycleRow(col, label, values, tip, groups, where)
        local f = CreateFrame("Frame", nil, quickPanel)
        f:SetSize(W, 24)
        f:SetPoint("TOPLEFT", quickPanel, "TOPLEFT", col:Left(), col.y)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", 2, 0)
        fs:SetText(label)
        if groups then Context(fs, groups) end
        local b = RedButton(f)
        b:SetSize(112, 20)
        b:SetPoint("RIGHT", -6, 0)
        local function Now()
            for i, v in ipairs(values) do if v[2]() then return i end end
        end
        f.Refresh = function()
            local i = Now()
            b:SetText(i and values[i][1] or "Your mix")
        end
        b:SetScript("OnClick", function()
            local i = Now() or 0
            -- (the next one that can be had: e.g. RareScanner only where it's installed)
            for step = 1, #values do
                local v = values[(i + step - 1) % #values + 1]
                if not v[4] or v[4]() then v[3]() break end
            end
            ns.RefreshControls()
        end)
        Tip(b, label, tip)
        if where then SettingsMenu(b, where[1], where[2]) end
        controls[#controls + 1] = f
        col.y = col.y - 26
    end
    -- a layer as you see it now, and a click as the map's toggle buttons take it
    -- (BattlefieldInfo.lua ns.IsShown / ns.ToggleLayer): in a context, its profile's
    -- say, so this panel and the buttons always agree
    local function Shown(g) return ns.IsShown(g) end
    local function SetShown(list)
        for g, v in pairs(list) do
            if Shown(g) ~= v then ns.ToggleLayer(g, "shown") end
        end
    end
    local function Layer(col, label, g)
        col:CheckWith(label, function() return ns.IsShown(g) end, function()
            ns.ToggleLayer(g, "shown")
            ns.RefreshControls()
        end)
        SettingsMenu(col.last, g, "shown")
    end
    -- objectives: off, or on in either look (ns.SetObjectives)
    local OBJECTIVES = {
        { "Off", function() return not ns.ObjectivesOn() end, function() ns.SetObjectives(false) end },
        { "Questie's", function() return ns.ObjectivesOn() and ns.ObjectiveLook() == "questie" end,
          function() ns.SetObjectives(true, "questie") end, function() return ns.QuestieArt() end },
        { "Waymark's", function() return ns.ObjectivesOn() and ns.ObjectiveLook() == "waymark" end,
          function() ns.SetObjectives(true, "waymark") end },
        { "Blizzard's", function() return ns.ObjectivesOn() and ns.ObjectiveLook() == "yours" end,
          function() ns.SetObjectives(true, "yours") end, function() return ns.FOREVER end },
    }
    -- rares: the addon's own (Rares & chests), RareScanner's, or none
    local function Rares(wilds, rs)
        return function() return Shown("wilds") == wilds and Shown("rares") == rs end,
               function() SetShown({ wilds = wilds, rares = rs }) end
    end
    local RARES = {}
    for _, r in ipairs({ { "Built in", true, false }, { "RareScanner", false, true, function() return ns.AddonPresent("RareScanner") end },
                         { "Off", false, false } }) do
        local is, set = Rares(r[2], r[3])
        RARES[#RARES + 1] = { r[1], is, set, r[4] }
    end

    local a = Column(quickPanel, 10, top.y, W)
    a:Header("Quests")
    a:CheckWith("Quest givers", ns.QuestGiversOn, function(v)
        ns.SetQuestGivers(v)
        ns.RefreshControls()
    end)
    a:Tip("Where you pick quests up and hand them in.")
    SettingsMenu(a.last, "questie", "shown")
    Context(a.last.text, { "questie", "turnins" })
    CycleRow(a, "Objectives", OBJECTIVES, "Where your quest mobs and items are. Questie's: Questie's icons. Waymark's: Waymark's own. Yours: Waymark shows none, and the game's own show.",
        { "spots" }, { "spots", "shown" })
    a:CheckWith("Low-level (grey) quests", ns.GetTrivialQuests, ns.SetTrivialQuests)
    a:Tip("Quest givers far below your level.")
    SettingsMenu(a.last, "questie", "color")
    if ns.ToldNow then
        a:Check("As told", "told", "on")
        a:Tip("A small panel with what the quest giver said. The map marks only the places they named.")
        SettingsMenu(a.last, "told", "on")
    end
    Layer(a, "Quest tracker", "tracker")
    Context(a.last.text, { "tracker" })
    a:Header("Places")
    Layer(a, "Townsfolk", "townsfolk")
    Context(a.last.text, { "townsfolk" })
    CycleRow(a, "Rares", RARES, "Built in: rares and chests the addon knows. RareScanner: its pins instead, where it's installed. Off: none.",
        nil, { "wilds", "shown" })  -- (no context marker here)
    if not ns.GatherPulled() then
        Layer(a, "Gathering nodes", "gather")
        Context(a.last.text, { "gather" })
        a:Tip("Herbs, ore, treasure and fishing spots.")
    end
    -- (the way to the buttons' own settings from the buttons: their tab is the fifth under How it looks,
    -- and a player who wants one off the map starts here, not there. The user, 2026-11-15: "a bit hidden?")
    -- (the button itself: the panel's foot, where Close was. Here, what nothing said: every row's
    -- right-click opens its own settings)
    a.y = a.y - 6
    a:Note("Right-click a row: its settings.")
    -- The right column (the settings pass, 2026-11-14): how the map is drawn, then what it does by itself,
    -- in the words of the settings' own page for that ("What the map does by itself"), so the player who
    -- just saw the map do something finds its switch one click from the gear. It had three ticks before.
    local b = Column(quickPanel, 10 + W + 6, top.y, W)
    b:Header("On the map")
    if ns.ReliefSetting then
        b:Check("The lie of the land", "relief", "on")
        b:Tip("Hills, valleys and shadows from the game's real terrain.")
        SettingsMenu(b.last, "relief", "on")
    end
    Layer(b, "Unexplored land", "explore")
    Context(b.last.text, { "explore" })
    Layer(b, "Close-up detail", "detail")
    if ns.SetupFishing then
        Layer(b, "Fisherman's mode", "fishing")
        b:Tip("The water washed by your fishing there: sage, every fish stays on; ochre, some get away; red, most do.")
    end

    -- what moves, switches or hides the map on its own: quick to turn off when
    -- it acts up or doesn't suit the moment
    b:Header("By itself")
    b:Check("Follows you", "mapFrame", "center")
    SettingsMenu(b.last, "mapFrame", "center")
    b:Check("Changes shape per zone", "mapFrame", "autoWidth")
    b:Tip("A tall zone gets a taller map, a wide one a wider map, at about your size.")
    SettingsMenu(b.last, "mapFrame", "autoWidth")
    b:Check("Zooms in on towns", "townView", "zoom")
    SettingsMenu(b.last, "townView", "zoom")
    b:Check("Fades while you move", "fade", "moving")
    SettingsMenu(b.last, "fade", "moving")
    b:Check("Fades in combat", "fade", "combat")
    SettingsMenu(b.last, "fade", "combat")
    b:Check("Folds in combat", "collapse", "combat")
    SettingsMenu(b.last, "collapse", "combat")
    b:Button("All it does by itself", function()
        quickPanel:Hide()
        ns.ToggleOptions("acts")
    end)

    local bottom = math.min(a.y, b.y)
    -- (the red X in the frame's corner closes it, as on the settings window; Close's place at the foot
    -- goes to something of use. The user, 2026-11-16: "we can replace close with something useful")
    local x = CreateFrame("Button", nil, quickPanel)
    x:SetSize(24, 24)
    x:SetPoint("TOPRIGHT", ns.FOREVER and -2 or -5, ns.FOREVER and 4 or 1)
    if ns.UsingSubstitutes() then
        x:SetSize(21, 21)
        x:SetPoint("TOPRIGHT", -2, 3)
    end
    x:SetFrameLevel(quickPanel:GetFrameLevel() + 5)
    StateArt(x, "Normal", "redbutton-exit-c60-2x", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    StateArt(x, "Pushed", "redbutton-exit-pressed-c60-2x", "Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    local xGlow = StateArt(x, "Highlight", "redbutton-highlight-c60-2x", "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    if xGlow then xGlow:SetBlendMode("ADD") end
    x:SetScript("OnClick", function() quickPanel:Hide() end)
    local close = RedButton(quickPanel)
    close:SetSize(160, 22)
    close:SetPoint("TOPLEFT", 12, bottom - 6)
    close:SetText("Which buttons show")
    close:SetScript("OnClick", function()
        quickPanel:Hide()
        ns.ToggleOptions("controls")
    end)
    local more = RedButton(quickPanel)
    more:SetSize(120, 22)
    more:SetPoint("TOPRIGHT", quickPanel, "TOPLEFT", 10 + FULL, bottom - 6)
    more:SetText("Settings")
    more:SetScript("OnClick", function()
        quickPanel:Hide()
        ns.ToggleOptions()
    end)

    quickPanel:SetSize(FULL + 20, -bottom + 40)
    quickPanel:SetScript("OnShow", function(self)
        if ns.HideWelcome then ns.HideWelcome() end  -- (they'd sit on one another; it's back with the map)
        Place(self)
        ns.RefreshControls()
    end)
    quickPanel:Hide()
    map:HookScript("OnHide", function() quickPanel:Hide() end)
end

-- Toggle strip: small buttons on the map for the features you pick, greyed out
-- when off. Which ones, their look, size, corner and fading are settings
-- (ns.db.toggles). { id (also the settings group), key, icon, label }
-- (t[6]: where the layer comes from, for the Toggle buttons page's headings)
local TOGGLES = {
    { "questie",   "shown",    "cursor_quest_128",                               "Quest givers", nil, nil,
      { { "questie", "shown" }, { "turnins", "shown" }, { "learned", "shown" } } },
    { "turnins",   "shown",    "cursor_questturnin_128",                         "Turn-ins" },
    { "objview",   "shown",    "cursor_questinteract_128",                       "Quest objectives", "spots" },  -- (one button, either look: ns.SetObjectives)
    { "spots",     "shown",    "cursor_attack_128",                              "Objective spots" },
    { "ground",    "shown",    ns.MEDIA .. "InkDot",                             "Objective dots" },
    { "wilds",     "shown",    "vignettekill",                                   "Rares & chests" },
    { "townsfolk", "shown",    "Interface\\Minimap\\Tracking\\Innkeeper",         "Townsfolk" },
    { "tracker",   "shown",    "poi-workorders",                                 "Quest tracker" },
    { "questMarkers", "shown", "bonus-objective-star",                           "Objective markers (the game's)", "objectives", "The game's own" },
    -- (not "areas": that old id is cleared from toggles.list at login, BattlefieldInfo.lua)
    { "questAreas", "shown",   ns.MEDIA .. "QuestArea",                          "Quest areas (blue zones)", "areas", "The game's own" },
    { "rares",     "shown",    "vignettekillelite",                              "Rares & treasures (RareScanner)", nil, "Other addons" },
    { "gather",    "shown",    "cursor_gatherherbs_128",                         "Gathering nodes", nil, "Other addons" },
    { "line",      "shown",    "minimap-questarrow",                             "Line to party member" },
    { "dungeons",  "shown",    "dungeon",                                        "Dungeon entrances" },
    -- (asked for on CurseForge 2026-11-17: the mode had a switch in settings but no button; FishingMap.lua; the header's fish)
    { "fishing",   "shown",    ns.MEDIA .. "Marks\\FishOutlined",                "Fisherman's mode" },
    { "detail",    "shown",    "cursor_inspect_128",                             "Close-up detail" },
    { "detailAll", "always",   "Interface\\WorldMap\\UI-World-Icon",             "Full detail at every zoom", "detail" },
    { "zoom",      "center",   "Interface\\Minimap\\UI-Minimap-ZoomInButton-Up",  "Follows you", "mapFrame" },  -- (id "zoom" kept for your saved order; Shift-click: auto-zoom)
    { "ink",       "shown",    "cursor_palette_128",                             "Your ink on the world map" },
    -- (not a layer: the quill taken up or put down, lit while it's in hand; Notebook.lua)
    { "quill",     "shown",    ns.MEDIA .. "Quill",                              "The quill (write and draw)", "ink" },
    -- (not a layer either: the book, opened; its right-click is its own menu, Notebook.lua)
    { "book",      "shown",    ns.MEDIA .. "BookIcon",                           "The book", "ink" },
}
ns.DropNoGameLayers(TOGGLES, 5)
ns.DropNoGameLayers(TOGGLES, 1)
ns.TOGGLES = TOGGLES

-- the buttons' ids in your order (toggles.order, from the Buttons & coordinates
-- page); one it doesn't have (none saved yet, or a new button) goes where
-- TOGGLES has it
function ns.ToggleOrder()
    local out, seen, known = {}, {}, {}
    for _, t in ipairs(TOGGLES) do known[t[1]] = true end
    for _, id in ipairs(ns.db.toggles.order or {}) do
        if known[id] and not seen[id] then
            out[#out + 1] = id
            seen[id] = true
        end
    end
    for i, t in ipairs(TOGGLES) do
        if not seen[t[1]] then table.insert(out, math.min(i, #out + 1), t[1]) end
    end
    return out
end

-- A toggle's icon (t[3]): an atlas name or a file path, through ns.SetArt. The
-- game's cursors (cursor_*) get Media\CursorMask over their pointer tip. Also
-- for the settings window's headings (col:Header's icon), with "town" and
-- "city" for the town view button and City view (the player's faction's crest).
local VIEW_ICONS = { town = "poi-town", dock = "Interface\\Icons\\INV_Misc_Map_01" }
-- the icon of the map button that switches a setting (nil: it has none)
function ns.LayerIcon(group, key)
    for _, t in ipairs(TOGGLES) do
        if (t[5] or t[1]) == group and t[2] == key then return t[3] end
    end
end

function ns.ToggleIcon(id)
    if id == "city" then return UnitFactionGroup("player") == "Horde" and "poi-horde" or "poi-alliance" end
    if VIEW_ICONS[id] then return VIEW_ICONS[id] end
    for _, t in ipairs(TOGGLES) do
        if t[1] == id then return t[3] end
    end
end

-- puts icon name on tex (owner: the frame the cursor mask is made on); returns
-- the cut of it (left, right, top, bottom) for an atlas, nil for a whole file
function ns.SetIconArt(owner, tex, name)
    -- (a cursor swapped for our own file, the palette on Era: it's that file from here
    -- on, with no pointer tip to mask)
    local own = ns.UsingSubstitutes() and ns.ART_SUBSTITUTE[name]
    if type(own) == "string" and own:find("\\AddOns\\", 1, true) then name = own end
    ns.SetArt(tex, name, "Interface\\Icons\\INV_Misc_QuestionMark")
    ns.CursorMask(owner, tex, name:find("^cursor_") ~= nil)
    if name:find("\\", 1, true) then
        -- (Era: a file's first SetTexture sometimes leaves it empty, set again a
        -- moment later it shows: the quill's and the quest areas' icons. Tried
        -- again a few times; the cut set on it meanwhile is kept)
        local tries = 0
        local function Retry()
            if tex:GetTexture() then return end
            tries = tries + 1
            local l, t, _, b, r = tex:GetTexCoord()
            tex:SetTexture(name)
            tex:SetTexCoord(l, r, t, b)
            if not tex:GetTexture() and tries < 5 then C_Timer.After(0.5, Retry) end
        end
        if not tex:GetTexture() then C_Timer.After(0, Retry) end
        return nil
    end
    local l, top, _, _, _, _, r, bottom = tex:GetTexCoord()
    return { l, r, top, bottom }
end

-- (t[7]: a button that switches several settings together, { { group, key }, ... }:
-- on while any of them is, and a click sets them all the same way)
local function ToggleOn(b)
    if b.def and b.def.lit then return b.def.lit() end  -- (a button another file added: its own state)
    if b.id == "book" then return true end
    if b.id == "quill" then return ns.QuillOut() end
    if b.id == "objview" then return ns.ObjectivesOn() end
    if not b.pairs then return ns.LayerOn(b.group, b.key) end
    for _, gk in ipairs(b.pairs) do
        if ns.LayerOn(gk[1], gk[2]) then return true end
    end
    return false
end

local function ToggleClick(b)
    if b.def and b.def.click then
        b.def.click()
        return
    end
    if b.id == "book" then
        if ns.ToggleNotebook then ns.ToggleNotebook() end
        return
    end
    if b.id == "quill" then
        if ns.QuillToggle then ns.QuillToggle() end
        return
    end
    if b.id == "objview" then
        ns.SetObjectives(not ns.ObjectivesOn())
        return
    end
    if not b.pairs then
        ns.ToggleLayer(b.group, b.key)
        return
    end
    local want = not ToggleOn(b)
    for _, gk in ipairs(b.pairs) do
        if ns.LayerOn(gk[1], gk[2]) ~= want then ns.ToggleLayer(gk[1], gk[2]) end
    end
end

local SPACING = 2

local toggleStrip, toggleButtons = nil, {}

-- in the row by the X: shown and not moved away (hold to move, MapControls)
local function InRow(b)
    return b and b:IsShown() and not ns.ButtonMoved(b) or false
end

local function RefreshToggles()
    for _, b in ipairs(toggleButtons) do
        local on = ToggleOn(b)  -- (as you see it: a profile may decide it)
        -- (a file's icon can come out empty when the strip is built, set again it
        -- shows: ns.SetIconArt tries again; here too, whenever it's empty. Its cut
        -- is StyleButton's, kept)
        if b.iconPath:find("\\", 1, true) and not b.icon:GetTexture() then
            local l, t, _, bt, r = b.icon:GetTexCoord()
            b.icon:SetTexture(b.iconPath)
            b.icon:SetTexCoord(l, r, t, bt)
        end
        b.icon:SetDesaturated(not on)
        if ns.db.toggles.style == "plain" then
            b.icon:SetVertexColor(1, 1, 1)
            b.icon:SetAlpha(on and 1 or 0.45)
        else
            local v = on and 1 or 0.55
            b.icon:SetVertexColor(v, v, v)
            b.icon:SetAlpha(1)
        end
        -- (Fisherman's mode, on: its fish in the header's colour for the map on view, the wash's for
        -- your skill there; soft ink brown where the header has no fish. "Maybe make it the same
        -- color", the user 2026-11-17)
        if on and b.id == "fishing" then
            local map = BattlefieldMapFrame
            local c = ns.FishingTint and map and ns.FishingTint(map:GetMapID()) or { 0.6, 0.56, 0.48 }
            b.icon:SetVertexColor(c[1], c[2], c[3])
        end
    end
end
ns.RefreshToggles = RefreshToggles

-- the look of one button: "square" (a thin dark-gold edge) or "plain" (the
-- icon alone). (Anything else, such as the removed "framed" from an old
-- setup, is drawn square.)
local function StyleButton(b, style, size)
    b:SetSize(size, size)
    b.icon:ClearAllPoints()
    b:SetBackdrop(nil)
    local isIcon = b.iconPath:find("\\Icons\\") ~= nil
    -- (b.iconCoords: one icon cut from a sheet, the town view button's)
    local c = b.iconCoords or (isIcon and { 0.08, 0.92, 0.08, 0.92 }) or { 0, 1, 0, 1 }
    if style == "plain" then
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(unpack(c))
    else
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(unpack(c))
        b:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
                        bgFile = "Interface\\Buttons\\WHITE8X8", insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        b:SetBackdropColor(0, 0, 0, 0.7)
        b:SetBackdropBorderColor(0.75, 0.6, 0.3)
    end
end

-- Where the strip goes: along an edge (top, bottom: a row; left, right: a
-- column), from one end of it ("start" = left / top, "last" = right / bottom),
-- inside the map or just outside it. Settings toggles.edge/from/side; the
-- older single toggles.where is read when those aren't set yet.
local OLD_WHERE = {
    topright = { "top", "last" }, topleft = { "top", "start" },
    bottomleft = { "bottom", "start" }, bottomright = { "bottom", "last" },
    left = { "left", "start" }, right = { "right", "start" },
}

local function TogglePlace(c)
    local old = OLD_WHERE[c.where] or OLD_WHERE.topright
    local edge, from = c.edge or old[1], c.from or old[2]
    local side = c.side or "inside"
    local row = edge == "top" or edge == "bottom"
    -- the strip's corner the buttons start from, and which way they grow
    local point, dx, dy
    if row then
        point = edge:upper() .. (from == "start" and "LEFT" or "RIGHT")
        dx, dy = from == "start" and 1 or -1, 0
    else
        point = (from == "start" and "TOP" or "BOTTOM") .. edge:upper()
        dx, dy = 0, from == "start" and -1 or 1
    end
    return edge, from, side, point, dx, dy
end

-- Docked, the map sits in the screen's corner: a strip outside its top or right has no room
-- there, so it goes outside the left. Only for now: the setting stays, and undocked it's back.
-- (A strip or button held and moved stays where it was put.)
local function TogglePlaceNow(c)
    local edge, from, side = TogglePlace(c)
    if side == "outside" and (edge == "top" or edge == "right") and ns.Docked and ns.Docked() then
        return TogglePlace({ edge = "left", from = edge == "right" and from or "start", side = side })
    end
    return TogglePlace(c)
end

-- for the options: the ends of the chosen edge, by name
function ns.ToggleFromChoices()
    local edge = TogglePlace(ns.db.toggles)
    if edge == "top" or edge == "bottom" then
        return { { "start", "The left end" }, { "last", "The right end" } }
    end
    return { { "start", "The top end" }, { "last", "The bottom end" } }
end
function ns.TogglePlaceSetting(key)
    return function() return (select(key == "edge" and 1 or 2, TogglePlace(ns.db.toggles))) end,
           function(v)
               ns.db.toggles[key] = v
               ns.OnSettingChanged("toggles", key)
           end
end

local LayoutTogglesNow
-- (an error here would silently leave no buttons at all: say it in chat, once)
local layoutError
local function LayoutToggles()
    local ok, err = ns.Safe("Options LayoutToggles", LayoutTogglesNow)
    if not ok and err ~= layoutError then
        layoutError = err
        ns.Log("toggle buttons: " .. tostring(err))
    end
end

-- for /bfi buttons
function ns.ToggleInfo()
    local function Describe(f, name)
        if not f then return name .. ": not made" end
        local p, rel, rp, x, y = f:GetPoint(1)
        return string.format("%s: shown %s, visible %s, alpha %.2f, size %dx%d, scale %.2f, level %d, at %s of %s %s (%d, %d)",
            name, tostring(f:IsShown()), tostring(f:IsVisible()), f.GetEffectiveAlpha and f:GetEffectiveAlpha() or f:GetAlpha(),
            f:GetWidth(), f:GetHeight(), f:GetEffectiveScale(), f:GetFrameLevel(),
            tostring(p), rel and (rel.GetName and rel:GetName() or "a frame") or "nothing", tostring(rp), x or 0, y or 0)
    end
    local n = 0
    for _, b in ipairs(toggleButtons) do if b:IsShown() then n = n + 1 end end
    return Describe(quickButton, "gear") .. "\n" .. Describe(toggleStrip, "strip") ..
        string.format("\n%d of %d buttons on; style %s, size %s, where %s, fade %s (%s%%); last error: %s",
            n, #toggleButtons, tostring(ns.db.toggles.style), tostring(ns.db.toggles.size),
            table.concat({ select(1, TogglePlace(ns.db.toggles)) }, " ", 1, 4),
            tostring(ns.db.toggles.fadeOut), tostring(ns.db.toggles.fadeAlpha), tostring(layoutError))
end

LayoutTogglesNow = function()
    if not toggleStrip then return end
    local map = BattlefieldMapFrame
    local c = ns.db.toggles
    local size = c.size or 16
    local edge, from, side, point, dx, dy = TogglePlaceNow(c)
    local n = 0
    local byId = {}
    for _, b in ipairs(toggleButtons) do byId[b.id] = b end
    for _, id in ipairs(ns.ToggleOrder()) do
        local b = byId[id]
        local on = c.list[id] and true or false
        b:SetShown(on)
        if on then
            StyleButton(b, c.style, size)
            if not ns.PlaceMoved(b) then  -- (taken out of the row: where it was put)
                b:ClearAllPoints()
                b:SetPoint(point, toggleStrip, point, n * (size + SPACING) * dx, n * (size + SPACING) * dy)
                n = n + 1
            end
        end
    end
    -- the + in the next place along, its cross about half the button's size
    local add = toggleStrip.add
    if add then
        add:SetSize(size, size)
        add:ClearAllPoints()
        add:SetPoint(point, toggleStrip, point, n * (size + SPACING) * dx, n * (size + SPACING) * dy)
        local s = math.max(8, math.floor(size * 0.6 + 0.5))
        add.plus:SetSize(s, s)
        n = n + 1
    end
    local long = math.max(1, n * (size + SPACING))
    toggleStrip:SetSize(dx ~= 0 and long or size, dy ~= 0 and long or size)
    -- the gear: the same size and look as the toggle buttons
    if quickButton and quickButton.icon then StyleButton(quickButton, c.style, size) end
    if townButton and townButton.icon then StyleButton(townButton, c.style, size) end
    if cityButton and cityButton.icon then StyleButton(cityButton, c.style, size) end
    if dockButton and dockButton.icon then StyleButton(dockButton, c.style, size) end
    if ns.RefreshViewGlow then ns.RefreshViewGlow() end  -- (sized to the buttons)

    toggleStrip:ClearAllPoints()
    local area = map and (map.ScrollContainer or map)
    local gear = InRow(quickButton)
    -- the leftmost of the gear and the town / city view and dock buttons beside it
    local leftmost = InRow(dockButton) and dockButton
        or InRow(cityButton) and cityButton
        or InRow(townButton) and townButton or (gear and quickButton)
    -- (offsets in the strip's own units; it's counter-scaled like the gear)
    if ns.PlaceMoved(toggleStrip) then
        -- (held and moved: where it was put)
    elseif side == "inside" and edge == "top" and from == "last" and leftmost then
        -- left of the gear (and the town view button), as before
        toggleStrip:SetPoint("RIGHT", leftmost, "LEFT", -4, 0)
    elseif side == "outside" and map then
        -- just beyond the map's edge: the strip's opposite side against it,
        -- e.g. along the top, its bottom corner on the map's top corner
        local OPP = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" }
        local mine = point:gsub(edge:upper(), OPP[edge:upper()])
        local ox = edge == "left" and -4 or edge == "right" and 4 or 0
        local oy = edge == "top" and 4 or edge == "bottom" and -4 or 0
        toggleStrip:SetPoint(mine, map, point, ox, oy)
    elseif area then
        local inX = (point:find("LEFT") and 6 or -6)
        local inY = (point:find("TOP") and -6 or 6)
        -- (clear of a soft edge's fade)
        if ns.SoftEdgeInset then
            local ix, iy = ns.SoftEdgeInset()
            inX = inX + (point:find("LEFT") and ix or -ix)
            inY = inY + (point:find("TOP") and -iy or iy)
        end
        if point == "TOPRIGHT" then
            -- clear of the close X and the gear: a row starts left of them, a
            -- column below them
            if edge == "top" then inX = -28 else inY = gear and -28 - 6 or -28 end
            -- (and of the big map's shrink button beside the X)
            local big = ns.bigMapButton
            if edge == "top" and InRow(big) then inX = inX - big:GetWidth() end
        end
        toggleStrip:SetPoint(point, area, point, inX, inY)
    end
    RefreshToggles()
end
ns.LayoutToggles = LayoutToggles

-- the mouse is on the map or on its toggle buttons (which can sit outside it):
-- what the fades go by
function ns.MouseOnMap(map)
    -- (collapsed, Collapse.lua: only the strip that's left)
    local inset = ns.CollapsedInset and ns.CollapsedInset() or 0
    return map:IsMouseOver(0, inset, 0, 0) or (toggleStrip and toggleStrip:IsVisible() and toggleStrip:IsMouseOver()) or false
end

-- Townsfolk menu (shift-click the townsfolk toggle button) ---------------------

-- Which kinds of townsfolk show, from the map: a small menu of the groups
-- (trainers, services, vendors), each opening a list to tick, with icons.
-- It changes the list in use right now: town view's or city view's own in a
-- town or capital that has one (ns.TownsfolkSettings), else the map's.
local tfMenu, tfSub
local TF_TRAINERS = { ["Class Trainer"] = true, ["Weapon Master"] = true, ["Portal Trainer"] = true }
local PROFESSION_ICON = "Interface\\Icons\\Trade_BlackSmithing"

-- the list in use, the settings group it's saved in, and where that is
local function ActiveTownsfolk()
    local t = ns.TownsfolkSettings and ns.TownsfolkSettings() or ns.db.townsfolk
    if t == ns.db.cityView then return t, "cityView", "in a city" end
    if t == ns.db.townView then return t, "townView", "in town" end
    return t, "townsfolk", "on the map"
end

local function MenuFrame(width)
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ns.AddonWindow(f)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.07, 0.05, 0.03, 0.96)
    f:SetBackdropBorderColor(0.75, 0.6, 0.35)
    f:SetWidth(width)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f.rows = {}
    f:Hide()
    return f
end

-- row i of a menu: a tick, its words, an icon or an arrow at its end
local function MenuRow(f, i, top)
    local r = f.rows[i]
    if not r then
        r = CreateFrame("Button", nil, f)
        r:SetHeight(20)
        r.check = r:CreateTexture(nil, "OVERLAY")
        r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        r.check:SetSize(16, 16)
        r.check:SetPoint("LEFT", 2, 0)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 20, 0)
        r.text:SetJustifyH("LEFT")
        r.icon = r:CreateTexture(nil, "OVERLAY")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("RIGHT", -4, 0)
        r.arrow = r:CreateTexture(nil, "OVERLAY")
        r.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        r.arrow:SetSize(11, 11)
        r.arrow:SetPoint("RIGHT", -4, 0)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        f.rows[i] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 4, top - (i - 1) * 20)
    r:SetPoint("TOPRIGHT", -4, top - (i - 1) * 20)
    r:SetScript("OnClick", nil)
    r:SetScript("OnEnter", nil)
    r.check:Hide()
    r.icon:Hide()
    r.arrow:Hide()
    r:Show()
    return r
end

-- the ticks of one group: { label, icon, key }, or a "myProfessionsOnly" row
local function GroupItems(name)
    local types = ns.TOWNSFOLK_TYPES or { services = {}, vendors = {} }
    local items = {}
    if name == "Trainers" then
        items[#items + 1] = { "Profession trainers", PROFESSION_ICON, "professions" }
        items[#items + 1] = { "   only your professions", nil, nil, "myProfessionsOnly" }
        for _, t in ipairs(types.services) do
            if TF_TRAINERS[t.key] then items[#items + 1] = { t.label, t.icon, t.key } end
        end
    elseif name == "Services" then
        for _, t in ipairs(types.services) do
            if not TF_TRAINERS[t.key] then items[#items + 1] = { t.label, t.icon, t.key } end
        end
    else
        for _, t in ipairs(types.vendors) do items[#items + 1] = { t.label, t.icon, t.key } end
    end
    return items
end

local function FillSub(name, row)
    local list, group = ActiveTownsfolk()
    local items = GroupItems(name)
    for i, it in ipairs(items) do
        local r = MenuRow(tfSub, i, -4)
        r.text:SetText(it[1])
        local function On()
            if it[4] then return list[it[4]] end
            return list.types[it[3]]
        end
        r.check:SetShown(On() and true or false)
        if it[2] then
            r.icon:SetTexture(it[2])
            r.icon:Show()
        end
        r:SetScript("OnClick", function()
            if it[4] then
                list[it[4]] = not list[it[4]]
                ns.OnSettingChanged(group, it[4])
            else
                list.types[it[3]] = (not list.types[it[3]]) or nil
                ns.OnSettingChanged(group, "types")
            end
            FillSub(name, row)  -- (the ticks again)
        end)
    end
    for i = #items + 1, #tfSub.rows do tfSub.rows[i]:Hide() end
    tfSub:SetHeight(#items * 20 + 8)
    tfSub:ClearAllPoints()
    tfSub:SetPoint("TOPLEFT", row, "TOPRIGHT", 6, 4)
    tfSub.group = name
    tfSub:Show()
end

local function CloseTownsfolkMenu()
    if tfMenu then tfMenu:Hide() end
    if tfSub then tfSub:Hide() end
end

function ns.ShowTownsfolkMenu(anchor)
    if not tfMenu then
        tfMenu, tfSub = MenuFrame(170), MenuFrame(190)
        tfMenu.title = tfMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tfMenu.title:SetPoint("TOPLEFT", 10, -8)
        -- a click anywhere else closes it
        tfMenu:SetScript("OnEvent", function()
            if not (tfMenu:IsMouseOver() or tfSub:IsMouseOver()) then CloseTownsfolkMenu() end
        end)
        tfMenu:SetScript("OnShow", function() pcall(tfMenu.RegisterEvent, tfMenu, "GLOBAL_MOUSE_DOWN") end)
        tfMenu:SetScript("OnHide", function()
            pcall(tfMenu.UnregisterEvent, tfMenu, "GLOBAL_MOUSE_DOWN")
            tfSub:Hide()
        end)
        if BattlefieldMapFrame then BattlefieldMapFrame:HookScript("OnHide", CloseTownsfolkMenu) end
    end
    if tfMenu:IsShown() then CloseTownsfolkMenu() return end
    local _, _, where = ActiveTownsfolk()
    tfMenu.title:SetText("Townsfolk " .. where)
    for i, name in ipairs({ "Trainers", "Services", "Vendors" }) do
        local r = MenuRow(tfMenu, i, -24)
        r.text:SetText(name)
        r.arrow:Show()
        r:SetScript("OnEnter", function() FillSub(name, r) end)
        r:SetScript("OnClick", function() FillSub(name, r) end)
    end
    tfMenu:SetHeight(3 * 20 + 30)
    tfMenu:ClearAllPoints()
    tfMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    tfSub:Hide()
    tfMenu:Show()
end

-- what holding a toggle button does, for its tooltip
function ns.ToggleMoveHints(b)
    if ns.ButtonMoved(b) then return { { "Hold", "move it" }, { "Hold, right-click", "back in the row" } } end
    return { { "Hold", "move the row" }, { "Shift + hold", "take it out of the row" } }
end

local function BuildToggleStrip(map)
    toggleStrip = CreateFrame("Frame", nil, map)
    toggleStrip:SetFrameLevel(quickButton:GetFrameLevel())
    for _, t in ipairs(TOGGLES) do
        local b = CreateFrame("Button", nil, toggleStrip, "BackdropTemplate")
        -- (t[5]: the settings group, when it isn't the id)
        b.id, b.group, b.key, b.iconPath = t[1], t[5] or t[1], t[2], t[3]
        b.pairs = t[7]
        -- (t.click / t.right / t.lit / t.tip: a button another file adds to ns.TOGGLES, such as the Lab's
        -- waybook, Lab\Road.lua; it says itself what a click does and what the tooltip shows)
        b.def = t
        b.icon = b:CreateTexture(nil, "ARTWORK")
        -- (an atlas: keep its cut, StyleButton sets the coords again)
        b.iconCoords = ns.SetIconArt(b, b.icon, t[3])
        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                -- its settings: the page it lives on, the option marked
                GameTooltip:Hide()
                if t.right then
                    t.right(b)
                    return
                end
                if b.id == "book" then
                    ns.BookMenu()
                    return
                end
                if b.id == "objview" then
                    ns.ToggleOptions("quests")
                    return
                end
                ns.ShowOption(b.group, b.key)
                return
            end
            -- shift-click townsfolk: which kinds, in a menu
            -- shift-click ink: the drawing bar (Ink.lua)
            if b.id == "ink" and IsShiftKeyDown() then
                if ns.ToggleInkBar then ns.ToggleInkBar() end
                return
            end
            if b.id == "townsfolk" and IsShiftKeyDown() then
                GameTooltip:Hide()
                ns.ShowTownsfolkMenu(b)
                return
            end
            ToggleClick(b)
            RefreshToggles()
            if GameTooltip:IsOwned(b) then b:GetScript("OnEnter")(b) end
        end)
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(b, "ANCHOR_TOP")
            GameTooltip:AddLine(t[4])
            if t.tip then
                t.tip(b)
                ns.Hints({ { "Click", "open it" }, unpack(ns.ToggleMoveHints(b)) })
                GameTooltip:Show()
                return
            end
            local key = ns.ActiveProfileKey and ns.ActiveProfileKey()
            local label = key and ns.PROFILE_LABELS and ns.PROFILE_LABELS[key]
            if b.id == "book" then
                GameTooltip:AddLine(ns.BookKindName(ns.db.notebook.kind), 1, 1, 1)
                GameTooltip:AddLine("Keep it your way: story, notes or blank.", 0.7, 0.7, 0.7, true)
                ns.Hints({ { "Click", "open it" }, { "Right-click", "more" }, unpack(ns.ToggleMoveHints(b)) })
                GameTooltip:Show()
                return
            elseif b.id == "quill" then
                -- (not a layer: no profile)
            elseif b.key == "shown" and key == "combat" then
                -- (a click in a fight is a plain one: nothing to say)
            elseif b.key == "shown" and label and ns.db.toggles.saveToProfile and ns.ProfileOverrides(b.group) then
                GameTooltip:AddLine("Your click is saved in the " .. label .. " profile.", 0.7, 0.7, 0.7, true)
            elseif b.key == "shown" and ns.ProfileOverrides(b.group) then
                GameTooltip:AddLine("The " .. ns.ProfileOverrides(b.group) .. " profile decides this here; your click wins until you leave it.", 0.7, 0.7, 0.7, true)
            end
            ns.Hints({ { "Click", b.id == "quill" and (ns.QuillOut() and "put it down" or "take it up") or "on or off" },
                       b.id == "townsfolk" and { "Shift-click", "filter townsfolk" } or nil,
                       b.id == "ink" and { "Shift-click", "the quill" } or nil,
                       { "Right-click", "its settings" }, unpack(ns.ToggleMoveHints(b)) })
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        toggleButtons[#toggleButtons + 1] = b
    end

    -- a faint gold + after the last button: to the page where you pick and
    -- order them (LayoutTogglesNow places it)
    local add = CreateFrame("Button", nil, toggleStrip)
    add.plus = add:CreateTexture(nil, "ARTWORK")
    add.plus:SetTexture(ns.MEDIA .. "AddButton")
    add.plus:SetPoint("CENTER")
    add:SetAlpha(0.45)
    add:SetScript("OnEnter", function()
        add:SetAlpha(1)
        GameTooltip:SetOwner(add, "ANCHOR_TOP")
        GameTooltip:AddLine("Add or manage buttons")
        GameTooltip:Show()
    end)
    add:SetScript("OnLeave", function()
        add:SetAlpha(0.45)
        GameTooltip:Hide()
    end)
    add:SetScript("OnClick", function()
        GameTooltip:Hide()
        ns.ShowOption("toggles", "order")
    end)
    toggleStrip.add = add

    -- fade the gear, the strip (and the close X, if you like) while the mouse
    -- isn't over the map; the frame opacity (ns.FrameAlpha) comes on top
    local alpha, shown = 1, nil
    local sinceRefresh = 0
    local fader = CreateFrame("Frame")
    fader:SetScript("OnUpdate", function(_, dt)
        if not map:IsShown() then return end
        -- a profile coming or going changes what's on: keep the buttons honest
        sinceRefresh = sinceRefresh + dt
        if sinceRefresh >= 1 then
            sinceRefresh = 0
            RefreshToggles()
        end
        local c = ns.db.toggles
        local want = 1
        if c.fadeOut and not (ns.MouseOnMap(map) or (quickPanel and quickPanel:IsShown())) then
            want = (c.fadeAlpha or 0) / 100
        end
        if alpha ~= want then
            local step = dt * 4
            alpha = math.abs(want - alpha) <= step and want or alpha + (want > alpha and step or -step)
        end
        -- (clear view: only with the mouse on the map, ClearView.lua)
        local cv = ns.ClearViewButtonAlpha and ns.db.clearView.on and ns.db.clearView.buttons == "hover"
                   and ns.ClearViewButtonAlpha() or 1
        -- (not the border's and header's opacity any more: the buttons have a fading of their own, "Fade when
        -- the mouse isn't on the map", and two dimmers on one button was a setting twice. 2026-11-15)
        local a = alpha * cv
        if a ~= shown then
            shown = a
            toggleStrip:SetAlpha(a)
            if quickButton then quickButton:SetAlpha(a) end
            if townButton then townButton:SetAlpha(a) end
            if cityButton then cityButton:SetAlpha(a) end
            if dockButton then dockButton:SetAlpha(a) end
        end
        local close = map.BorderFrame and map.BorderFrame.CloseButton
        if close then close:SetAlpha((c.fadeClose and alpha or 1) * cv) end
        if ns.bigMapButton then ns.bigMapButton:SetAlpha((c.fadeClose and alpha or 1) * cv) end
    end)
    LayoutToggles()
end

-- The map's close X and our buttons keep their size on screen whatever the map's
-- scale: each is scaled by 1 / the map's scale (their parent is the map).
function ns.ApplyChromeScale()
    local map = BattlefieldMapFrame
    if not map then return end
    local inv = ns.AddonScale() / math.max(0.1, map:GetScale())
    local close = map.BorderFrame and map.BorderFrame.CloseButton
    if close then close:SetScale(inv) end
    if ns.closeHome then ns.closeHome:SetScale(inv) end
    if ns.bigMapButton then ns.bigMapButton:SetScale(inv) end
    if quickButton then quickButton:SetScale(inv) end
    if townButton then townButton:SetScale(inv) end
    if cityButton then cityButton:SetScale(inv) end
    if dockButton then dockButton:SetScale(inv) end
    if toggleStrip then toggleStrip:SetScale(inv) end
    ns.ApplyButtonLevels()
    if ns.ScaleHeader then ns.ScaleHeader() end  -- (ZoneName; after the X's level)
end

-- and they stay above whatever covers the map (the dungeon map, the cave view):
-- ns.ButtonLevel, set again each time the map shows
function ns.ApplyButtonLevels()
    local map = BattlefieldMapFrame
    if not map then return end
    local level = ns.ButtonLevel(map)
    -- (the border's strata, not the map's: the border is the higher one, and the X under it went.
    -- Docked too, the higher of the two: the map is raised over the minimap there, and the border
    -- (HIGH, takes the mouse) lay over a strip moved out past the map's left edge, the user 2026-11-14)
    local ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                    FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
    local strata = (map.BorderFrame or map):GetFrameStrata()
    if (ORDER[map:GetFrameStrata()] or 0) > (ORDER[strata] or 0) then strata = map:GetFrameStrata() end
    local d = ns.debugFrames
    local close = map.BorderFrame and map.BorderFrame.CloseButton
    for _, f in ipairs({ close, ns.bigMapButton, quickButton, townButton, cityButton, dockButton,
                         d.coords, d.coordsCursor, d.clock, d.dockMapOnly }) do
        -- (undocked, their strata too: docking lays the map's parts in other stratas, and one
        -- left under the map after undocking wasn't helped by its level)
        if f and strata and f:GetFrameStrata() ~= strata then f:SetFrameStrata(strata) end
        if f and f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
    end
    if toggleStrip then
        if strata and toggleStrip:GetFrameStrata() ~= strata then toggleStrip:SetFrameStrata(strata) end
        toggleStrip:SetFrameLevel(level)
        for _, b in ipairs({ toggleStrip:GetChildren() }) do b:SetFrameLevel(level + 1) end
    end
end

-- Town view and city view on/off in one click, beside the gear rather than
-- among the toggles: town view all of it (townView.enabled: its zoom, pin
-- sizes, townsfolk list and profile), city view its zoom to the whole capital
-- (cityView.zoom). Icons: the map's town icon, the player's faction crest.
-- A golden glow while it's at work (active); the tooltip says where you are.
local function PlaceName()
    local sub = ns.CurrentSubZone and ns.CurrentSubZone() or ""
    return sub ~= "" and sub or GetRealZoneText() or ""
end
local VIEW_BUTTONS = {
    town = { group = "townView", key = "enabled",
             active = function() return ns.InTownView and ns.InTownView() end,
             status = function()
                 if ns.IsInTown and ns.IsInTown() and not (ns.InCityView and ns.InCityView()) then
                     return "In town: " .. PlaceName()
                 end
                 return "Not in town"
             end },
    city = { group = "cityView", key = "zoom",
             active = function() return ns.db.cityView.zoom and ns.InCityView and ns.InCityView() end,
             status = function()
                 return (ns.InCityView and ns.InCityView()) and "In city: " .. (GetRealZoneText() or "") or "Not in a city"
             end },
    -- (minimap replacement, Dock.lua: the same kind of button, though not a view)
    dock = { group = "dock", key = "on",
             active = function() return ns.Docked and ns.Docked() end,
             status = function()
                 if ns.db.dock.on then
                     return (ns.Docked and ns.Docked()) and "Docked over the minimap" or "Docks when combat ends"
                 end
                 return (ns.Docked and ns.Docked()) and "Undocks when combat ends" or "Not docked"
             end },
}
local function BuildViewButton(map, id)
    local v = VIEW_BUTTONS[id]
    local b = CreateFrame("Button", nil, map, "BackdropTemplate")
    b:SetSize(13, 13)
    b:SetFrameLevel(quickButton:GetFrameLevel())
    b.view = v
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.iconPath = ns.ToggleIcon(id)
    b.iconCoords = ns.SetIconArt(b, b.icon, b.iconPath)
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    b.glow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(1, 0.8, 0.3, 0.9)
    b.glow:SetPoint("CENTER", b.icon, "CENTER")
    b.glow:Hide()
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            GameTooltip:Hide()
            ns.ShowOption(v.group, v.key)
            return
        end
        ns.db[v.group][v.key] = not ns.db[v.group][v.key]
        ns.OnSettingChanged(v.group, v.key)
        if GameTooltip:IsOwned(b) then b:GetScript("OnEnter")(b) end
    end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:AddLine(v.status(), 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function ns.SetupQuickButton(map)
    -- built like the toggle buttons, so it takes their size and look (LayoutToggles)
    quickButton = CreateFrame("Button", nil, map, "BackdropTemplate")
    quickButton:SetSize(13, 13)
    local border = map.BorderFrame
    local close = border and border.CloseButton
    if close then
        quickButton:SetPoint("RIGHT", close, "LEFT", -2, 0)
    else
        quickButton:SetPoint("TOPRIGHT", map, "TOPRIGHT", -26, -4)
    end
    -- above the border art, but not parented to it: the border fades with the map's opacity;
    -- and above the dungeon map and cave view, which cover the map's pins
    -- (ns.ButtonLevel). The town / city / dock buttons and the toggle strip take
    -- this level too.
    quickButton:SetFrameLevel(ns.ButtonLevel(map))

    local b = quickButton
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    -- the world map's slim gear where the client has it, else the gear icon
    b.iconPath = "Interface\\WorldMap\\Gear_64Grey"
    if b.icon:SetTexture(b.iconPath) == false then
        b.iconPath = "Interface\\Icons\\INV_Misc_Gear_01"
        b.icon:SetTexture(b.iconPath)
    end
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    quickButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    quickButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            -- the settings window
            GameTooltip:Hide()
            quickPanel:Hide()
            ns.ToggleOptions()
            return
        end
        quickPanel:SetShown(not quickPanel:IsShown())
    end)
    quickButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(quickButton, "ANCHOR_LEFT")
        GameTooltip:AddLine("Waymark")
        GameTooltip:AddLine("Quick options", 1, 1, 1)
        ns.Hints({ { "Click", "quick options" }, { "Right-click", "settings" }, { "Hold", "move it (any map button)" } })
        GameTooltip:Show()
    end)
    quickButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    BuildQuickPanel(map)
    townButton = BuildViewButton(map, "town")
    cityButton = BuildViewButton(map, "city")
    dockButton = BuildViewButton(map, "dock")
    BuildToggleStrip(map)
    -- press and hold to move (MapControls); a toggle button takes its strip along,
    -- placed by the corner it grows from
    ns.HoldToMove(quickButton, "gear")
    ns.HoldToMove(townButton, "town")
    ns.HoldToMove(cityButton, "city")
    ns.HoldToMove(dockButton, "dock")
    local stripPoint = function() return (select(4, TogglePlace(ns.db.toggles))) end
    for _, b in ipairs(toggleButtons) do
        ns.HoldToMove(b, "toggles", toggleStrip, stripPoint)
        b.bfiMoveKey = "toggle:" .. b.id  -- (its own place, once Shift + hold takes it out of the row)
    end
    ns.HoldToMove(toggleStrip.add, "toggles", toggleStrip, stripPoint)
    ns.debugFrames.gear, ns.debugFrames.toggleStrip = quickButton, toggleStrip
    ns.debugFrames.townButton, ns.debugFrames.cityButton = townButton, cityButton
    ns.debugFrames.dockButton = dockButton
    map:HookScript("OnShow", ns.ApplyChromeScale)
    ns.UpdateQuickButton()
    ns.ApplyChromeScale()
end

-- the town and city view buttons' glow: on while that view is at work (Town.lua
-- calls this when you walk into or out of a town); the dock button's while docked
function ns.RefreshViewGlow()
    for _, b in ipairs({ townButton, cityButton, dockButton }) do
        if b then
            local w = b:GetWidth()
            b.glow:SetSize(w * 1.9, w * 1.9)
            b.glow:SetShown(b.view.active() and true or false)
        end
    end
end

-- what our buttons line up left of: the map's shrink / grow arrow (MapControls),
-- else the close X, else (both moved away) where the X would be
local function RightOfButtons()
    local big = ns.bigMapButton
    if InRow(big) then return big end
    local close = BattlefieldMapFrame.BorderFrame and BattlefieldMapFrame.BorderFrame.CloseButton
    if close and not ns.ButtonMoved(close) then return close end
    return ns.closeHome
end

-- the town and city view buttons (and the dock button): on in colour, off greyed
-- out; in a row left of the gear (town view nearest it), or where the gear would be
local function RefreshViewButtons()
    local close = RightOfButtons()
    local right = InRow(quickButton) and quickButton
    for _, b in ipairs({ townButton, cityButton, dockButton }) do
        local on = ns.db[b.view.group][b.view.key]
        b.icon:SetDesaturated(not on)
        b.icon:SetVertexColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6)
        b:ClearAllPoints()
        if ns.PlaceMoved(b) then
            -- (held and moved: out of the row)
        elseif right then
            b:SetPoint("RIGHT", right, "LEFT", -3, 0)
        elseif close then
            b:SetPoint("RIGHT", close, "LEFT", -2, 0)
        else
            b:SetPoint("TOPRIGHT", BattlefieldMapFrame, "TOPRIGHT", -26, -4)
        end
        if InRow(b) then right = b end
    end
    ns.RefreshViewGlow()
end

function ns.HideQuickPanel()
    if quickPanel then quickPanel:Hide() end
end

function ns.UpdateQuickButton()
    if not quickButton then return end
    -- (mapButtons: all of them at once, over each one's own switch)
    local all = ns.db.mapButtons ~= false
    quickButton:SetShown(all and ns.db.quickButton and true or false)
    local right = RightOfButtons()
    if not ns.PlaceMoved(quickButton) and right then
        quickButton:ClearAllPoints()
        quickButton:SetPoint("RIGHT", right, "LEFT", -2, 0)
    end
    if townButton then
        townButton:SetShown(all and ns.db.townButton and true or false)
        cityButton:SetShown(all and ns.db.cityButton and true or false)
        -- (the dock button is gone from the map: the header's right-click menu docks)
        dockButton:SetShown(false)
        RefreshViewButtons()
    end
    if not quickButton:IsShown() then quickPanel:Hide() end
    if toggleStrip then
        toggleStrip:SetShown(all and ns.db.quickToggles ~= false)
        LayoutToggles()
    end
end

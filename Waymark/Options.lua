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
    local colW = math.max(box:GetWidth(), 120) - 2 * LIST_PAD
    for i, ch in ipairs(choices) do
        local r = listRows[i]
        if not r then
            r = CreateFrame("Button", nil, list)
            r:SetHeight(LIST_ROW)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 22, 0)
            r.text:SetPoint("RIGHT", -6, 0)
            r.text:SetJustifyH("LEFT")
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
            local folded = not foldsOpen and ns.db.optionsWindow.folded[key] == true
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
    function col:CheckWith(label, get, set, compact, icon)
        if Skipped() then return end
        local c = CreateCheck(parent, label, get, set, nil, width, icon, rows and ctrlX - x)
        if compact then c:SetSize(20, 20) end
        local h = PlaceCheck(c, compact)
        Made(c, label, Index(label, self.y, h))
        self.y = self.y - h
    end
    -- a feature on the Overview page: { name, what it does, where it comes from,
    -- group, key, its page, the addon it needs }. Its switch, the line saying
    -- what it does, its source, and > to its page.
    function col:Feature(f)
        local present = not f[7] or ns.AddonPresent(f[7])
        local get, set = LayerSetting(f[4], f[5])
        local c = CreateCheck(parent, f[1], get, set, nil, width - 120)
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
        go:SetScript("OnClick", function() ns.OpenOptionsPage(f[6]) end)
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
    function col:Note(text, r, g, b)
        if adv and not advancedShown then return end  -- (not counted: not a setting)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", x + 4, self.y - 2)
        fs:SetWidth(width - 14)
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

-- The map border's and the header's looks, for Start here and Header & border
local BORDER_STYLES = {
    { "game", "The game's own" }, { "dialog", "Classic dialog" }, { "gold", "Gold" },
    { "tooltip", "Tooltip" }, { "wood", "Wood" }, { "line", "Thin line" }, { "none", "None" },
}
local HEADER_STYLES = {
    { "plate", "Classic plate" }, { "tan", "Tan leather" }, { "stone", "Stone" },
    { "parchment", "Parchment" }, { "tooltip", "Dark" }, { "text", "Text only" },
}

-- Start here's quest help: the quest layers in four steps (the Quests page has each)
local QUEST_LAYERS = { "questie", "turnins", "spots", "objectives", "areas", "learned", "tracker" }
local QUEST_HELP = {
    { "none", "None", {} },
    { "givers", "Quest givers", { questie = true, objectives = true, areas = true, learned = true } },
    { "tracker", "Givers, turn-ins & the tracker",
      { questie = true, turnins = true, objectives = true, areas = true, learned = true, tracker = true } },
    { "all", "Everything, objective spots too",
      { questie = true, turnins = true, spots = true, objectives = true, areas = true, learned = true, tracker = true } },
}
local function QuestHelp()
    for _, h in ipairs(QUEST_HELP) do
        local same = true
        for _, g in ipairs(QUEST_LAYERS) do
            if (ns.db[g].shown and true or false) ~= (h[3][g] or false) then same = false end
        end
        if same then return h[1] end
    end
    return "mix"
end
local function SetQuestHelp(v)
    for _, h in ipairs(QUEST_HELP) do
        if h[1] == v then
            for _, g in ipairs(QUEST_LAYERS) do
                local want = h[3][g] or false
                if ns.db[g].shown ~= want then
                    ns.db[g].shown = want
                    ns.OnSettingChanged(g, "shown")
                end
            end
        end
    end
end
local QUEST_HELP_CHOICES = { { "mix", "Your own mix (Quests page)" } }
for _, h in ipairs(QUEST_HELP) do QUEST_HELP_CHOICES[#QUEST_HELP_CHOICES + 1] = { h[1], h[2] } end

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

-- Pages -----------------------------------------------------------------

local CONTENT_W = 640
local HALF = CONTENT_W / 2

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
                .. ". Applying it brings back the whole setup. Delete it on the Setups page." }
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
            save:SetText("Save as new and restore")
            save:SetSize((save:GetFontString():GetStringWidth() or 160) + 30, 22)
            save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
            save:SetScript("OnClick", function()
                local n = strtrim(nameBox:GetText() or "")
                if ns.SavePresetAs(n, true) then
                    Done("Saved \"" .. n .. "\" as a preset of your own (a card here, and on the Setups page); "
                        .. pick.name .. " is restored.")
                end
            end)
            save:SetScript("OnEnter", function()
                GameTooltip:SetOwner(save, "ANCHOR_RIGHT")
                GameTooltip:SetText("Save as new and restore", 1, 0.82, 0)
                GameTooltip:AddLine("Your settings now become a preset of your own under the name beside it: a card here, and a setup on the Setups page. Then " .. pick.name .. " is put back.", 1, 1, 1, true)
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
            note = "Your settings aren't saved: keep them on the Setups page first if you want them back."
        end
        if altered and not onIt then
            note = note .. (note ~= "" and " " or "") .. "Your changes to " .. ns.PresetName(base) .. " aren't kept: save them on its card first."
        end
        if onIt then note = "Restore: only these rows go back. Save as new and restore: yours are kept as a preset of your own first." end
        after:SetText(note)
        inner = inner + (right and math.max(22, after:GetStringHeight()) or after:GetStringHeight()) + 10
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

    -- then the choices that matter most, each with > to its page
    w:Header("Main settings")
    local function Go(top, page)
        local go = RedButton(p)
        go:SetSize(26, 20)
        go:SetPoint("RIGHT", p, "TOPLEFT", ROW_W - 2, (top + w.y) / 2)
        go:SetText(">")
        go:SetScript("OnClick", function() ns.OpenOptionsPage(page) end)
        go:SetScript("OnEnter", function()
            GameTooltip:SetOwner(go, "ANCHOR_RIGHT")
            GameTooltip:SetText("More settings")
            GameTooltip:Show()
            ns.GlowNavPage(page, true)
        end)
        go:SetScript("OnLeave", function()
            GameTooltip:Hide()
            ns.GlowNavPage(page, false)
        end)
    end

    -- the map's role, its three choices side by side (clear view always in reach)
    local top = w.y
    local roleH = 30
    local label = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Ink(p, label)
    label:SetPoint("LEFT", p, "TOPLEFT", left, top - roleH / 2)
    label:SetText("The map")
    local roleTip = "Window: the Battlefield Map where you put it. Clear view: the map without its frame, laid over the world. Minimap: it replaces your minimap, and every map feature still works there."
    local hover = CreateFrame("Frame", nil, p)
    hover:SetAllPoints(label)
    hover:EnableMouse(true)
    local roles, prev = {}, nil
    for _, r in ipairs({ { "window", "Window", "window" }, { "clear", "Clear view", "clearview" },
                         { "dock", "Minimap", "minimap" } }) do
        local b = RedButton(p)
        b:SetText(r[2])
        b:SetSize((b:GetFontString():GetStringWidth() or 60) + 30, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", p, "TOPLEFT", ROW_LABEL, top - roleH / 2) end
        b:SetScript("OnClick", function()
            SetMapRole(r[1])
            ns.RefreshControls()
        end)
        b.role = r[1]
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
        end
    end
    controls[#controls + 1] = roleRow
    roleRow.Refresh()
    w.y = top - roleH
    Go(top, MapRole() == "dock" and "minimap" or "clearview")

    top = w.y
    w:Choice("Quest help", nil, nil, QUEST_HELP_CHOICES, QuestHelp, SetQuestHelp)
    w:Tip("Quest givers and the game's objectives; then turn-ins and the quest tracker; then every objective spot. Each layer is on the Quests page.")
    Go(top, "quests")
    top = w.y
    w:Check("Townsfolk", "townsfolk", "shown")
    w:Tip("Trainers, vendors, innkeepers, flight masters and the like.")
    Go(top, "people")
    top = w.y
    w:Check("Unexplored areas", "explore", "shown")
    w:Tip("The areas you haven't found yet, drawn in, where the game leaves them blank.")
    Go(top, "explore")
    top = w.y
    w:Check("Keep centred on me", "mapFrame", "center")
    w:Tip("The map follows you as you move.")
    Go(top, "behaviour")
    top = w.y
    w:Check("Auto-zoom", "zoom", "autoZoom")
    w:Tip("Zooms in near quest objectives and gathering nodes, back out when you leave.")
    Go(top, "behaviour")
    top = w.y
    w:Choice("Border", "border", "style", BORDER_STYLES)
    Go(top, "header")
    top = w.y
    w:Choice("Header", "zoneName", "style", HEADER_STYLES)
    Go(top, "header")

    -- folded the first time it's seen
    local ow = ns.db.optionsWindow
    if not ow.aboutFolded then
        ow.aboutFolded = true
        ow.folded["overview/About"] = true
    end
    w:Header("About")
    w:Note("The list on the left has three groups: The window, Getting around and What's shown. Click a group's name for its main switches on one page. Hover any setting for what it does; Show advanced settings, at the bottom, adds the fine-tuning to every page.")
    w:Note("Minimap and dungeon map data: OpenMap (MIT licence, see LICENSES). QuestieDB, RareScanner and GatherMate2 data are read from those addons while the game runs; nothing of theirs is copied into this addon. Where Questie is installed, its quest icons are used.")
end }

local function Percent(v) return string.format("%d%%", v * 100 + 0.5) end

-- The window group's own page (its heading in the list): the main switches
-- and the three opacities, each with > to where the rest of it is
local WINDOW_SWITCHES = {
    { "Auto shape", "The map follows each zone's shape, at about your size.", "", "mapFrame", "autoWidth", "window" },
    { "Movable", "Drag the map's edge to move it.", "", "mapFrame", "unlocked", "window" },
    { "Header", "Where you are, above or on the map.", "", "zoneName", "shown", "header" },
    { "Border", "A frame round the map, in the style you pick.", "", "border", "shown", "header" },
    { "Map buttons", "The gear, the town and city view buttons and the toggle buttons.", "", nil, "mapButtons", "controls" },
    { "Coordinates", "Yours and the cursor's.", "", "coords", "shown", "controls" },
    { "Clear view", "Just the map, laid over the world.", "", "clearView", "on", "clearview" },
    { "Minimap replacement", "The map docks over a square minimap.", "", "dock", "on", "minimap" },
}

PAGES[#PAGES + 1] = { key = "windowhome", label = "The window", summary = true, build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Switches")
    for _, f in ipairs(WINDOW_SWITCHES) do a:Feature(f) end

    local b = Column(p, HALF, 0, HALF)
    b:Header("Opacity")
    b:Slider("Map opacity", 0, 1, 0.05, "mapFrame", "opacity", Percent)
    b:Tip("The map picture itself. At 0% only the pins, border, header and buttons are left.")
    b:Slider("Frame opacity", 0, 1, 0.05, "mapFrame", "frameAlpha", Percent)
    b:Tip("The border, the header and the buttons on the map.")
    b:Slider("Pin opacity", 0, 1, 0.05, "pins", "alpha", Percent)
    b:Tip("Every pin on the map at once, on top of each layer's own opacity (on its page).")
    b:Note("Fading while you move or in combat comes on top of these: Size, shape & fade.")
end }

PAGES[#PAGES + 1] = { key = "window", label = "Size, shape & fade", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Size and shape")
    a:Note("Drag the map's bottom-right corner to give it any size and shape. Right-click the corner: with auto shape, this zone goes back to its automatic shape; once it's automatic (or without auto shape), the game's own size comes back.")
    a:Check("Auto shape: follow each zone's shape", "mapFrame", "autoWidth")
    a:Tip("The map takes on the zone's shape at about your size: tall zones like the Barrens get narrower and taller, wide ones like Duskwood wider and shorter.")
    a:Requires("mapFrame", "autoWidth")
    a:Advanced(true)
    a:Slider("How much of the zone's shape", 0, 1, 0.05, "mapFrame", "shapeFollow", function(v)
        return string.format("%d%%", v * 100 + 0.5)
    end)
    a:Tip("100%: exactly the zone's shape. Less: part way from your own shape, so the map changes less between zones; zoomed out, a strip of the neighbouring zones shows round the zone.")
    a:Slider("Room to grow", 0, 0.5, 0.05, "mapFrame", "shapeGrow", function(v)
        return string.format("up to %d%%", v * 100 + 0.5)
    end, "none")
    a:Tip("The more a zone's shape differs from yours, the more area the map may take, so more of the zone shows. All of it from twice as wide (or tall) on.")
    a:Choice("Shapes you drag", "mapFrame", "rememberShapes", {
        { true, "Remember it for that zone" }, { false, "Forget it when I leave" },
    })
    a:Tip("Remember: a zone keeps the shape you drag it to. Forget: it goes back to its own shape when you leave.")
    a:Button("Reset shape to defaults", function() ns.ConfirmResetGroup("shape") end)
    a:Advanced()
    a:Requires()

    local b = Column(p, HALF, 0, HALF)
    b:Header("Placement")
    b:Check("Lock the map", "mapFrame", "locked")
    b:Tip("The map stays where it is: dragging its header (or edge) doesn't move it. Also in the header's right-click menu.")
    b:Requires(function() return not ns.db.mapFrame.locked end)
    b:Check("Move the map by its edge", "mapFrame", "unlocked")
    b:Tip("Drag any edge of the map to move it. Off: it stays where it is.")
    b:Requires()
    b:Check("Hide the Zone Map tab", "mapFrame", "hideTab")
    b:Tip("The tab sits above the map and stops it from reaching the top of the screen.")
    b:Check("Clicks go through the map", "clickThrough", "on")
    b:Tip("Clicks and the mouse wheel reach the world behind the map, so it never gets in your way. Not while docked over the minimap.", "Hold the key below to use the map; pin tooltips still show.")
    b:Requires("clickThrough", "on")
    b:Choice("Hold to use the map", "clickThrough", "modifier", {
        { "ALT", "Alt" }, { "CTRL", "Ctrl" }, { "SHIFT", "Shift" },
    })
    b:Check("Only in combat", "clickThrough", "combat")
    b:Tip("Out of combat the map takes clicks as usual.")
    b:Requires()
    if ns.LeatrixBattleMapActive and ns.LeatrixBattleMapActive() then
        b:Note("Leatrix Maps' battlefield map options are on too. Use one or the other, or they'll fight over the map.", 1, 0.5, 0.3)
    end
    b:Header("Opacity and fading")
    b:Slider("Map opacity", 0, 1, 0.05, "mapFrame", "opacity", Percent)
    b:Tip("The map picture itself. At 0% only the pins, border, header and buttons are left.")
    b:Slider("Frame opacity", 0, 1, 0.05, "mapFrame", "frameAlpha", Percent)
    b:Tip("The border, the header and the buttons on the map.")
    b:Slider("Pin opacity", 0, 1, 0.05, "pins", "alpha", Percent)
    b:Tip("Every pin on the map at once, on top of each layer's own opacity (on its page).")
    b:Check("Fade the map while I move", "fade", "moving")
    b:Tip("Flight paths don't count as moving.")
    b:Requires("fade", "moving")
    b:Slider("Opacity while moving", 0, 100, 5, "fade", "movingAlpha", "%d%%")
    b:Requires()
    b:Check("Fade the map in combat", "fade", "combat")
    b:Requires("fade", "combat")
    b:Slider("Opacity in combat", 0, 100, 5, "fade", "combatAlpha", "%d%%")
    b:Requires()
    b:Check("Full opacity under the mouse", "fade", "hover")
    b:Tip("Fading comes on top of the map's own opacity: 50% opacity faded to 40% shows at 20%. At 0% the map still catches clicks.")
    b:Header("Collapsing")
    b:Check("Collapse the map in combat", "collapse", "combat")
    b:Tip("The map folds up under its header during a fight and opens again after it. An attached quest tracker stays.", "Key bindings page: Collapse the map.")
end }

-- Clear view and the minimap replacement: modes of the window, each its own page
PAGES[#PAGES + 1] = { key = "clearview", label = "Clear view", build = function(p)
    local b = Column(p, 0, 0, HALF)
    b:Header("Clear view")
    b:Check("Clear view", "clearView", "on")
    b:Tip("Just the map, laid over the world: no border, the zone name and buttons under the mouse only, your pins kept clear.", "Key bindings page: Clear view.")
    b:Check("Hide the border", "clearView", "noFrame")
    b:Choice("Zone name", "clearView", "header", {
        { "hover", "On mouse-over" }, { "shown", "Shown" }, { "hidden", "Hidden" },
    })
    b:Choice("Buttons and coordinates", "clearView", "buttons", {
        { "hover", "On mouse-over" }, { "shown", "Shown" },
    })
    b:Check("Only the zone I'm in", "clearView", "zoneOnly")
    b:Tip("The neighbouring zones and the sea round its edges are cut away, on a zone's map (not continents or caves).")
    b:Check("Cut city maps too", "clearView", "cities")
    b:Tip("A city's map cut to the city, where it has an outline.")
    b:Check("Cut dungeon maps too", "clearView", "dungeons")
    b:Tip("A dungeon floor's map cut to its halls, where it has an outline: the world shows round it, not black.")
    b:Check("Whole map when big", "clearView", "bigUncut")
    b:Tip("No cutting while the map is big (the big map button or key): the whole map shows.")
    -- (the optional views made in the outline editor, CutEdit.lua: one box each)
    b:Slider("Map opacity in clear view", 0.1, 1, 0.05, "clearView", "opacity", Percent)
    b:Tip("In place of the map opacity (The window page) while clear view is on. Pins keep their own opacity.")
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
    b:Tip("The minimap turns square and north up, and the map lies over it at the same size: one square, two faces.", "The map's X switches between them; Shift+M does nothing meanwhile (put Big map on M: Key bindings page). Changes to the minimap wait until a fight ends.")
    b:Requires("dock", "on")
    b:Slider("Size", 100, 400, 10, "dock", "size", "%d")
    b:Tip("The square's size; on the big map, the big map's.", "Or drag its corner grip (bottom left); right-click the grip for 160.")
    b:CheckWith("Map only, never the minimap", function() return ns.db.dock.mapOnly end,
        function(v) if ns.DockSetMapOnly then ns.DockSetMapOnly(v) end ns.RefreshControls() end)
    b:Tip("The square stays the map: the wheel and a double-click don't switch it back to the game's minimap.")
    b:Check("Into the screen's top-right corner", "dock", "corner")
    b:Tip("Off: where the minimap was.")
    b:Check("Hide the day / night indicator", "dock", "hideSun")
    b:Tip("The minimap's sun and moon. Its other buttons (clock, tracking, mail...): hold one to move it, right-click while holding to put it back.")
    b:Check("Mouse wheel switches between minimap and map", "dock", "wheel")
    b:Tip("One wheel for both: zoom the minimap out past its farthest and the map opens just as close; wheel in on the map to come back.", "Right-click the minimap: the map. Double-click the map: the minimap. Replaces the minimap's + and - buttons.")
    b:Slider("Wheel friction", 0, 5, 1, "dock", "friction", "%d")
    b:Tip("Extra clicks before it switches. The edge glows on each.")
    b:Requires()

    local n = Column(p, HALF, 0, HALF)
    n:Header("Controls")
    n:Note("Wheel on the minimap: zoom. Out past its farthest zoom: the map.")
    n:Note("Wheel in on the map, at the minimap's zoom with you in view: back to the minimap.")
    n:Note("Right-click the minimap: the map at the same zoom. Drag on it: the map, panned as you drag.")
    n:Note("Double-click the map: back to the minimap. With Map only, or on the big map: back on you.")
    n:Note("The map's X: map or minimap. Shift+M does nothing while docked.")
    n:Note("Big map key or arrow: the big map beside the square, which stays the minimap. Drag its edge to move it, its corner grip to size it.")
    n:Note("Hold any of the minimap's buttons to move it; right-click while holding puts it back.")
    n:Note("Key bindings page: Minimap replacement (on/off) turns the mode off. Tip: put Big map on M.")
end }

-- zoom as art on screen (MapControls' ArtX): screen pixels per pixel of the map art
local function ArtSize(v) return string.format("art at %.1fx", v) end
local function Closer(v) return string.format("%.1fx closer", v) end
local function HowClose(v)
    if v < 0.05 then return "fully out" end
    return ArtSize(v)
end
local HOW_CLOSE_TIP = "How big the map picture is drawn: at 1x each pixel of it is one pixel of your screen, at 2x two. The same closeness at any map size. 0 is fully zoomed out; past the closest zoom it stops there."

-- The Getting around group's own page: how the map follows you, where it
-- zooms in, and the closeness of each
local AROUND_SWITCHES = {
    { "Keep centred on me", "The map follows you as you move.", "", "mapFrame", "center", "behaviour" },
    { "Other maps", "Right-click or wheel out to the continent.", "", "browse", "enabled", "browse" },
    { "Auto-zoom", "Zooms in near quest objectives and gathering nodes.", "", "zoom", "autoZoom", "behaviour" },
    { "Close-up detail", "The minimap's trees and rocks as you zoom in.", "", "detail", "shown", "behaviour" },
    { "Town view", "A close-up of the town when you arrive.", "", "townView", "enabled", "town" },
    { "City view", "The whole capital city when you arrive.", "", "cityView", "zoom", "city" },
    { "Cave view", "Inside a cave, the map shows the cave.", "", "cave", "enabled", "dungeon" },
    { "Dungeon maps", "Inside a dungeon, the map shows the dungeon.", "", "dungeon", "fallback", "dungeon" },
    { "Unexplored areas", "Shows what you haven't found yet.", "", "explore", "shown", "explore" },
    { "Area names", "Names the area under the cursor.", "", "explore", "hoverNames", "explore" },
}

PAGES[#PAGES + 1] = { key = "aroundhome", label = "Getting around", summary = true, build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Switches")
    for _, f in ipairs(AROUND_SWITCHES) do a:Feature(f) end

    local b = Column(p, HALF, 0, HALF)
    b:Header("How close")
    b:Slider("Closest zoom", 2, 24, 0.5, "zoom", "closestX", ArtSize)
    b:Tip("How far in the mouse wheel goes.")
    b:Slider("Near objectives", 0.5, 16, 0.1, "zoom", "clusterX", HowClose)
    b:Tip("How close it zooms near objectives and gathering nodes. ", HOW_CLOSE_TIP)
    b:Slider("In a town", 0.5, 16, 0.1, "zoom", "townX", HowClose)
    b:Tip("Town view's close-up. ", HOW_CLOSE_TIP)
    b:Header("Unexplored areas")
    b:Slider("Opacity", 0.1, 1, 0.05, "explore", "fogAlpha", Percent)
    b:Tip("On top of the map opacity (The window).")
end }

-- The What's shown group's own page: every layer, and what filters them all
local SHOWN_SWITCHES = {
    { "Quest givers", "Who has a quest for you.", "built in, or QuestieDB", "questie", "shown", "quests" },
    { "Turn-ins", "Where to hand in finished quests.", "built in, or QuestieDB", "turnins", "shown", "quests" },
    { "Objective spots", "Where your quest mobs and items are.", "built in, or QuestieDB", "spots", "shown", "quests" },
    { "Quest ground", "Where your quests' monsters and things are.", "built in, or QuestieDB", "ground", "shown", "quests" },
    { "Quest objectives", "The game's own objective markers.", "the game", "objectives", "shown", "quests" },
    { "Quest areas", "The game's blue quest zones.", "the game", "areas", "shown", "quests" },
    { "Learned quest givers", "For quests the quest data lacks.", "built in", "learned", "shown", "quests" },
    { "Quest tracker", "This zone's quests, nearest first.", "built in", "tracker", "shown", "tracker" },
    { "Quest log", "A quest's page beside the map.", "built in", "questlog", "shown", "questlog" },
    { "Townsfolk", "Trainers, vendors, innkeepers...", "built in, or QuestieDB; learned", "townsfolk", "shown", "people" },
    { "Player & group", "Your arrow and your group.", "the game", "party", "shown", "group" },
    { "Line to target", "A line from you to a pin.", "built in", "line", "shown", "group" },
    { "Rares & treasures", "Rare mobs, treasures and events.", "RareScanner", "rares", "shown", "rares", "RareScanner" },
    { "Rares & chests", "Rares, rare elites and treasure chests.", "built in", "wilds", "shown", "rares" },
    { "Gathering nodes", "Herbs, ore, fish and more.", "GatherMate2", "gather", "shown", "rares", "GatherMate2" },
    { "Your ink on the world map", "Routes, marks and notes you drew.", "built in", "ink", "shown", "ink" },
}

PAGES[#PAGES + 1] = { key = "shownhome", label = "What's shown", summary = true, build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Layers")
    for _, f in ipairs(SHOWN_SWITCHES) do a:Feature(f) end

    local b = Column(p, HALF, 0, HALF)
    b:Header("All pins")
    b:Slider("Pin opacity", 0, 1, 0.05, "pins", "alpha", Percent)
    b:Tip("Every pin on the map at once, on top of each layer's own opacity (on its page).")
    b:Slider("Pin & text size", ns.MIN_MAP_SCALE, ns.MAX_MAP_SCALE, 0.05, nil, "scale", "%.2fx")
    b:Tip("Everything drawn on the map (pins, text, the border) bigger or smaller; the map keeps its size. Each layer has its own size on its page too.")
    b:Slider("Tooltip size", 0.6, 1.2, 0.05, "pins", "tipScale", Percent)
    b:Tip("Tooltips of anything you hover on the map (pins, buttons), as a share of their usual size. Tooltips elsewhere keep theirs.")
    b:Advanced(true)
    b:Slider("Pins no smaller than", 0, 3, 0.1, "pins", "minMapScale", "%.1fx", "off")
    b:Tip("With the size above set lower than this, pins keep the size they'd have at this one, so they stay readable. Off: they shrink with it.")
    b:Advanced()
    b:Header("Fewer pins")
    b:Check("Hide quest pins outside the zone", "outside", "hideQuests")
    b:Tip("The zone map shows bits of the zones around it; quest pins that fall there are hidden.")
    b:Check("Hide quest pins in unexplored areas", "explore", "hideQuests")
    b:Check("Hide other pins in unexplored areas", "explore", "hideOthers")
    b:Tip("Townsfolk, rares, nodes and dungeon entrances.")
    b:CheckWith("Low-level (grey) quests", ns.GetTrivialQuests, ns.SetTrivialQuests)
    b:Tip("Grey quest givers: quests far below your level.")
    b:Check("Quest givers coloured by difficulty", "questie", "color")
end }

PAGES[#PAGES + 1] = { key = "browse", label = "Other zones & continent", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Getting there")
    a:Check("Look at other zones and the continent", "browse", "enabled")
    a:Tip("Look at the continent and other zones on this map, then come back to yours. What follows you waits until you're back.", "Right-click: one map up. Left-click a zone or a capital: that map. Middle-click: back to yours.")
    a:Requires("browse", "enabled")
    a:Check("The mouse wheel climbs maps", "browse", "wheel")
    a:Tip("Wheel out past fully zoomed out for the continent; wheel in over a zone, or a capital, to open it.")
    a:Requires("browse", "wheel")
    a:Slider("Wheel clicks past fully out", 1, 6, 1, "browse", "friction", "%d")
    a:Tip("How many more clicks out it takes to leave the zone. The inside of the map's frame blinks with a glow on each but the last, so you feel where the zone's own zoom ends.")
    a:Requires("browse", "enabled")
    a:Header("While you look")
    a:Check("Silver header on a map you're not in", "browse", "silver")
    a:Check("Zone names under the mouse", "browse", "overviewNames")
    a:Tip("The zone's name and levels as you move the mouse over the continent or the world.")
    a:Check("Quest givers on the continent", "browse", "continentGivers")
    a:Tip("Every zone's quest givers on the continent map, as your quest giver settings show them.")
    a:Check("Sharp zone maps on the continent", "browse", "zoneArt")
    a:Tip("As you zoom in on a continent, each zone's own sharp map fades in over the blocky continent picture.")
    a:Requires("browse", "zoneArt")
    a:Advanced(true)
    a:Stops("How they come in", "browse",
        { { "fadeFrom", "map from" }, { "fadeFull", "in" }, { "detailFull", "areas full" } },
        0.05, 1.2, 0.05,
        { { 0.23, 0.18, 0.13 }, { 0.85, 0.77, 0.61 }, { 0.50, 0.69, 0.41 }, { 1, 0.82, 0 } },
        { { 0.25, "25%" }, { 0.5, "50%" }, { 0.75, "75%" }, { 1, "opens" } },
        function(v) return string.format("%d%%", v * 100 + 0.5) end)
    a:Tip("How close you are when each zone's plain map starts to show, when it's fully in, and when its area colours have filled in (a share of the zone's own map; \"opens\": where the wheel opens the zone).", "Press the track to bring the nearest stop there, and drag.")
    a:Check("Smooth zone colours underneath", "browse", "zoneWash")
    a:Tip("Each zone's colour laid smooth under its map, in place of the continent's blocky picture. Off: the blocky picture shows through.")
    a:Advanced()
    a:Requires("browse", "enabled")
    a:Requires()

    local b = Column(p, HALF, 0, HALF)
    b:Header("Back to your map")
    b:Note("Click the header to go back.")
    b:Requires("browse", "enabled")
    b:Slider("After the mouse is away", 0, 60, 1, "browse", "idle", "%d s", "never")
    b:Tip("Back to your own map once the mouse has been off the map this long.")
    b:Check("When the map is closed and opened", "browse", "onReopen")
    b:Check("When I walk into another zone", "browse", "onZone")
    b:Requires()
    b:Check("Keep what I'm looking at on a flight path", "browse", "taxi")
    b:Tip("Looking at the continent or another zone when you take off: it stays there while you fly, and your map comes back when you land. Your own zone's map follows you as usual.")
    b:Note("Key binding: Continent map (Key bindings page). Again: back to your map.")
end }

PAGES[#PAGES + 1] = { key = "behaviour", label = "Zoom, centring & detail", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Centring and zoom", ns.ToggleIcon("zoom"))  -- (the Keep centered button's)
    a:Check("Keep centred on me", "mapFrame", "center")
    a:Tip("The map follows you as you move; after you pan or zoom it waits until you move on.", "Hold Shift to pause it.")
    a:Slider("Closest zoom", 2, 24, 0.5, "zoom", "closestX", ArtSize)
    a:Tip("How far in the mouse wheel goes: the map picture this many times its own size on your screen, whatever the map's size.")
    a:Advanced(true)
    a:Slider("Smoother zoom", 1, 5, 1, "zoom", "smoothness", "%dx steps", "1.5x a click")
    a:Tip("Each wheel click zooms 1.5x, split into this many smaller clicks.")
    a:Advanced()
    a:Check("Zoomed out shows just the zone", "zoom", "fitZone")
    a:Tip("Fully zoomed out frames the zone itself, not the whole map picture with its neighbours. Zooming out stays inside the zone.")

    local b = Column(p, HALF, 0, HALF)
    b:Header("Auto-zoom")
    b:Check("Zoom in near objectives and nodes", "zoom", "autoZoom")
    b:Tip("Zooms in when you reach a cluster of objectives or nodes and back out when you leave; it waits while you've panned or zoomed yourself.")
    b:Requires("zoom", "autoZoom")
    b:Check("Clusters of quest objectives", "zoom", "nearSpots")
    b:Check("Gathering nodes (GatherMate)", "zoom", "nearNodes")
    b:Slider("How close", 0.5, 16, 0.1, "zoom", "clusterX", HowClose)
    b:Tip("", HOW_CLOSE_TIP)
    b:Requires()
    b:Advanced(true)
    b:Slider("Zoom speed", 0.3, 3, 0.1, "zoom", "animTime", "%.1f s")
    b:Tip("How long an automatic zoom in or out takes, here and in town and city view.")
    b:Advanced()
    b:Header("Close-up detail", ns.ToggleIcon("detail"))
    b:Check("The minimap's detail up close", "detail", "shown")
    b:Tip("Trees, rocks and buildings from the game's minimap fade in as you zoom in, and stay at full detail however far past that you zoom. Eastern Kingdoms and Kalimdor; tile data from OpenMap (MIT).")
    b:Requires("detail", "shown")
    b:Slider("Opacity when zoomed in", 0.1, 1, 0.05, "detail", "strength")
    b:Check("On the big map too", "detail", "bigMap")
    b:Tip("Off: the detail shows on the small map only, the big map keeps to the map art.")
    b:Advanced(true)
    b:Slider("Starts to show at", 1, 16, 0.1, "detail", "fromZoom", Closer)
    b:Tip("How close the zoom is when it starts to fade in: this many times closer than fully zoomed out. The same view of the zone at any map size, so resizing the map doesn't change it.")
    b:Slider("Full detail at", 1, 16, 0.1, "detail", "fullZoom", Closer)
    b:Tip("Fully faded in from this close on. Never past the closest zoom (left), so it can always be reached.")
    b:Advanced()
    b:Check("Full detail at every zoom", "detail", "always", nil, ns.ToggleIcon("detailAll"))
    b:Tip("Also on the continent maps, which otherwise keep to the map art however close you zoom.")
    b:Advanced(true)
    b:Check("Blend with the map's colours", "detail", "blend")
    b:Advanced()
    b:Requires()
    b:Button("Reset zoom & detail to defaults", function() ns.ConfirmResetGroup("zoom") end)
    b:Tip("Every zoom and close-up detail threshold back to how the addon comes. Your switches stay as they are.")
end }

-- Town view and City view (view: "townView" / "cityView") -----------------

-- each layer's size there (view.sizes; unset: its map size times "All pins")
local function ViewPinSizes(a, view, where)
    a:Header("Pin sizes " .. where)
    a:Slider("All pins", 0.5, 3, 0.05, view, "pinScale", "%.2fx")
    a:Tip("Every layer's map size times this, for the layers you haven't set below.")
    a:Advanced(true)
    local LAYERS = {
        { "questie", "Quest givers" }, { "turnins", "Turn-ins" },
        { "spots", "Objective spots" }, { "objectives", "Quest objectives (the game's)" },
        { "learned", "Learned quest givers" }, { "townsfolk", "Townsfolk" },
        { "rares", "Rares & treasures" }, { "gather", "Gathering nodes" },
        { "dungeons", "Dungeon entrances" },
    }
    for _, l in ipairs(LAYERS) do
        a:SliderWith(l[2], 0.2, 3, 0.05,
            function() return ns.TownPinSize(l[1], view) end,
            function(v)
                ns.db[view].sizes[l[1]] = v
                ns.OnSettingChanged(view, "sizes")
            end, "%.2fx")
    end
    a:Button("Same sizes as on the map", function()
        wipe(ns.db[view].sizes)
        ns.db[view].pinScale = 1
        ns.OnSettingChanged(view, "sizes")
        ns.RefreshControls()
    end)
    a:Advanced()
end

-- townsfolk there: their own list (view.types), a copy of the map's at first
local function ViewTownsfolk(b, view, where, when)
    b:Header("Townsfolk " .. where)
    b:Check("Their own list " .. where, view, "ownTypes")
    b:Tip("On: the townsfolk ticked here " .. when .. ", so the map elsewhere can stay quiet. Off: the map's own list (Townsfolk page).")
    b:Requires(view, "ownTypes")
    local function TownType(label, key)
        b:CheckWith(label,
            function() return ns.TownTownsfolk(view).types[key] end,
            function(v)
                ns.TownTownsfolk(view).types[key] = v or nil
                ns.OnSettingChanged(view, "types")
            end, true)
    end
    -- in the Townsfolk page's groups: trainers, services, vendors
    local types = ns.TOWNSFOLK_TYPES or { services = {}, vendors = {} }
    local trainers = { ["Class Trainer"] = true, ["Weapon Master"] = true, ["Portal Trainer"] = true }
    b:Grid(3)  -- (side by side, as on the Townsfolk page)
    b:SubHeader("Trainers")
    TownType("Profession trainers", "professions")
    b:Indent(true)
    b:CheckWith("Only my professions",
        function() return ns.TownTownsfolk(view).myProfessionsOnly end,
        function(v)
            ns.TownTownsfolk(view).myProfessionsOnly = v and true or false
            ns.OnSettingChanged(view, "myProfessionsOnly")
        end, true)
    b:Indent()
    for _, t in ipairs(types.services) do
        if trainers[t.key] then TownType(t.label, t.key) end
    end
    b:SubHeader("Services")
    for _, t in ipairs(types.services) do
        if not trainers[t.key] then TownType(t.label, t.key) end
    end
    b:SubHeader("Vendors")
    for _, t in ipairs(types.vendors) do TownType(t.label, t.key) end
    b:Grid()
    b:Requires()
end

PAGES[#PAGES + 1] = { key = "town", label = "Town view", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("In a town", ns.ToggleIcon("town"))
    a:Check("Town view", "townView", "enabled")
    a:Tip("All of town view at once: its zoom, pin sizes, townsfolk list and the Towns & cities profile. Capitals have City view instead.")
    a:Check("Zoom in when I'm in a town", "townView", "zoom")
    a:Tip("A close-up of the town when you arrive, following you; back to your own zoom when you leave. It waits while you've panned or zoomed yourself.")
    a:Requires("townView", "zoom")
    a:Slider("How close", 0.5, 16, 0.1, "zoom", "townX", HowClose)
    a:Tip("", HOW_CLOSE_TIP)
    a:Requires(nil, "mapButtons")
    a:Check("Town view button on the map", nil, "townButton")
    a:Tip("Beside the gear: switches all of town view on or off with one click.")
    a:Requires()
    a:Note("Which layers show in town: the Towns & cities context profile (Context profiles page).")

    ViewPinSizes(a, "townView", "in town")

    local b = Column(p, HALF, 0, HALF)
    ViewTownsfolk(b, "townView", "in town", "while you're in a town")

    -- (last: the tools for when the town finding gets a place wrong)
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
        status:SetText((sub ~= "" and sub or "(no sub-zone)") .. "\n"
            .. (inTown and "|cff4ddf4dIn town|r" or "|cffff6a4dNot a town|r") .. "  |cff9d9d9d(" .. why .. ")|r")
    end)
    b:Button("This place is a town", function() ns.MarkTown(true) end)
    b:Button("This place is not a town", function() ns.MarkTown(false) end)
    b:Button("Back to automatic", function() ns.MarkTown(nil) end)
    b:Note("A town is where two kinds of service NPC (inn, repair, mail, flight, stable, bank, auction) stand within 60 yards; its sub-zone is then remembered. A place you mark wins. /waymark town shows each step.")
    b:Button("Forget remembered towns", function() ns.ForgetLearnedTowns() end)
end }

PAGES[#PAGES + 1] = { key = "city", label = "City view", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("In a capital city", ns.ToggleIcon("city"))
    a:Check("Zoom when I enter a capital", "cityView", "zoom")
    a:Tip("In a capital the map shows the whole city (or as close as below), and your own zoom again when you leave.")
    a:Requires("cityView", "zoom")
    a:Slider("How close", 0, 16, 0.1, "cityView", "zoomX", function(v)
        if v < 0.05 then return "the whole city" end
        return ArtSize(v)
    end)
    a:Tip("0 shows the whole city.", HOW_CLOSE_TIP)
    a:Requires(nil, "mapButtons")
    a:Check("City view button on the map", nil, "cityButton")
    a:Tip("Beside the town view button, with your faction's crest: switches city view's zoom to the whole capital on or off.")
    a:Requires()
    a:Note("Off: in a capital the map stays at your own zoom (town view never zooms in a capital).")

    ViewPinSizes(a, "cityView", "in a city")

    local b = Column(p, HALF, 0, HALF)
    ViewTownsfolk(b, "cityView", "in a city", "while you're in a capital")

    b:Header("Where you are")
    local status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Ink(p, status)
    status:SetPoint("TOPLEFT", b:Left() + 4, b.y - 2)
    status:SetWidth(HALF - 30)
    status:SetJustifyH("LEFT")
    b.y = b.y - 24
    local ticker = CreateFrame("Frame", nil, p)
    ticker:SetScript("OnUpdate", function()
        local inCity = ns.InCityView and ns.InCityView()
        status:SetText(inCity and "|cff4ddf4dIn a capital city|r" or "|cffff6a4dNot in a capital city|r")
    end)
end }

-- the header on the left; the map's border and the header's side by side on the right
PAGES[#PAGES + 1] = { key = "header", label = "Header & border", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Header")
    a:Check("Show", "zoneName", "shown")
    a:Requires("zoneName", "shown")
    a:Choice("Where", "zoneName", "mode", {
        { "header", "Above the map" },
        { "inside", "Inside, at the top" },
        { "below", "Below the map" },
    })
    a:Choice("Style", "zoneName", "style", HEADER_STYLES)
    a:Slider("Text size", 9, 24, 1, "zoneName", "fontSize", "%d")
    -- what it says, then the fine-tuning of its look last
    a:SubHeader("What it says")
    a:Check("The zone too (Sentinel Hill, Westfall)", "zoneName", "showZone")
    a:Check("The zone's level range", "zoneName", "levels")
    a:Tip("Coloured like quests: green is easy for you, red is dangerous.")
    a:Check("How much of the zone I've explored", "zoneName", "progress")
    a:Check("Coloured like the zone text", "zoneName", "pvpColors")
    a:Tip("Red, green or gold for hostile, friendly or contested land, as the game's zone text.")
    a:Advanced(true)
    a:Choice("Font", "zoneName", "font", ns.FontChoices)
    a:Tip("Morpheus is the font of the game's own zone text.", FONT_TIP)
    a:Check("As wide as the map", "zoneName", "fullWidth")
    a:Choice("Text alignment (wide)", "zoneName", "align", {
        { "CENTER", "Centre" }, { "LEFT", "Left" }, { "RIGHT", "Right" },
    })
    a:Slider("Nudge left / right", -150, 150, 1, "zoneName", "offsetX", "%d px")
    a:Slider("Nudge down / up", -60, 60, 1, "zoneName", "offsetY", "%d px")
    a:Advanced()
    a:Requires()

    local b = Column(p, HALF, 0, HALF)
    b:Header("Map border")
    b:Check("Show", "border", "shown")
    b:Tip("Off: no frame round the map at all, the game's own included. Your style is kept for when you switch it back on.")
    b:Requires("border", "shown")
    b:Choice("Style", "border", "style", BORDER_STYLES)
    b:Choice("Colour", "border", "color", {
        { "natural", "As drawn" }, { "gold", "Gold" }, { "bronze", "Bronze" },
        { "silver", "Silver" }, { "dark", "Dark" }, { "class", "My class colour" },
    })
    b:Advanced(true)
    b:Slider("Thickness", 0.5, 2, 0.05, "border", "size", "%.2fx")
    b:Slider("Distance from the map", -12, 20, 1, "border", "gap", "%d px")
    b:Advanced()
    b:Requires("zoneName", "shown")
    b:Header("Header border")
    b:Choice("Style", "zoneName", "border", {
        { "auto", "The style's own" }, { "dialog", "Classic dialog" }, { "gold", "Gold" },
        { "tooltip", "Tooltip" }, { "wood", "Wood" }, { "line", "Thin line" }, { "none", "None" },
    })
    b:Choice("Colour", "zoneName", "borderColor", {
        { "natural", "As drawn" }, { "gold", "Gold" }, { "bronze", "Bronze" },
        { "silver", "Silver" }, { "dark", "Dark" }, { "class", "My class colour" },
    })
    b:Advanced(true)
    b:Slider("Thickness", 0.5, 2, 0.05, "zoneName", "borderSize", "%.2fx")
    b:Slider("Distance from the header", -12, 20, 1, "zoneName", "borderGap", "%d px")
    b:Advanced()
    b:Requires()
end }

PAGES[#PAGES + 1] = { key = "controls", label = "Buttons & coordinates", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Map buttons")
    a:Check("Show the map's buttons", nil, "mapButtons")
    a:Tip("All of them at once: the toggle buttons, the gear, and the town and city view buttons. Each also has its own switch: below, or for the town and city view buttons on their own pages.")
    a:Requires(nil, "mapButtons")
    a:Check("Toggle buttons", nil, "quickToggles")
    a:Tip("Small buttons on the map that switch layers on and off. Right-click one for its settings.")
    a:Check("Quick-options button (the gear)", nil, "quickButton")
    a:Tip("The most-used switches in a small panel. Right-click it for these settings.")
    a:Requires()
    a:Button("Put the map's buttons back", function() ns.ResetButtonPositions() end)
    a:Tip("Press and hold any button on the map to move it; right-click while holding puts that one back.")
    a:Check("Minimap button", "minimap", "hide", true)
    a:Tip("On the game's own minimap, not on this map.", "Click: the Battlefield Map. Right-click: these settings.")
    a:Header("Toggle buttons")
    a:Requires(nil, "quickToggles")
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
    a:Tip("On: in a town, a click is kept in the Towns & cities profile, so it's that way every time you're in town. Off: a click lasts until you leave the context.")
    a:Advanced()
    a:Requires()

    -- Which buttons beside Button order (two columns, level), Coordinates under both
    local l = Column(p, 0, nil, HALF, true)
    local r = Column(p, HALF, nil, HALF, true)
    -- which buttons, under where each layer comes from (t[6]; ours when none)
    local ORDER = { "QuestieDB", "The game's own", "Other addons", "Waymark" }
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
    r:Note("Drag a row to move it. The top one is the button at the starting end of the strip. Unticked buttons keep their place, greyed.")
    r:Button("Default order", function()
        ns.db.toggles.order = {}
        ns.OnSettingChanged("toggles", "order")
        ns.RefreshControls()
    end)
    r:Requires()
    r:EndCard()

    local c = Column(p, 0, nil, HALF)
    c:Header("Coordinates")
    c:Check("Show", "coords", "shown")
    c:Requires("coords", "shown")
    c:Slider("Text size", 4, 20, 1, "coords", "size", "%d")
    local SPOTS = {
        { "TOPLEFT", "Top left" }, { "TOP", "Top middle" }, { "TOPRIGHT", "Top right" },
        { "BOTTOMLEFT", "Bottom left" }, { "BOTTOM", "Bottom middle" }, { "BOTTOMRIGHT", "Bottom right" },
    }
    c:Choice("Player: where", "coords", "where", SPOTS)
    local cursorSpots = { { "beside", "Beside the player's" } }
    for _, s in ipairs(SPOTS) do cursorSpots[#cursorSpots + 1] = s end
    c:Choice("Cursor: where", "coords", "cursorWhere", cursorSpots)
    c:Tip("Beside the player's: they move together. A spot of its own: placed and nudged apart from the player's.")
    c:Advanced(true)
    c:Color("Text colour", "coords", "color")
    c:Choice("Player: side", "coords", "side", {
        { "inside", "Inside the map" }, { "outside", "Outside the map" },
    })
    c:Choice("Cursor: side", "coords", "cursorSide", {
        { "same", "As the player's" }, { "inside", "Inside the map" }, { "outside", "Outside the map" },
    })
    c:Tip("Only for a spot of its own; beside the player's it sits on the same line.")
    c:Slider("Player: nudge left / right", -100, 100, 1, "coords", "offsetX", "%d px", "none")
    c:Slider("Player: nudge down / up", -100, 100, 1, "coords", "offsetY", "%d px", "none")
    c:Slider("Cursor: nudge left / right", -200, 200, 1, "coords", "cursorX", "%d px", "none")
    c:Tip("From its own spot, or from beside the player's.")
    c:Slider("Cursor: nudge down / up", -100, 100, 1, "coords", "cursorY", "%d px", "none")
    c:Slider("Dark backing", 0, 100, 5, "coords", "backing", "%d%%", "none")
    c:Check("Text shadow", "coords", "shadow")
    c:Check("Text outline", "coords", "outline")
    c:Tip("A dark outline round the letters: easier to read without the backing.")
    c:Advanced()
    c:Requires()
end }

PAGES[#PAGES + 1] = { key = "keys", label = "Key bindings", build = function(p)
    -- (each column whole before the next: on the settings pages they stack)
    local list = ns.KeyBindingList and ns.KeyBindingList() or {}
    local a = Column(p, 0, 0, HALF)
    a:Note("Click a key's button, then press the key: with Shift, Ctrl or Alt too if you like. Escape cancels, right-click clears it. A key already used for something else moves here.")
    a:Note("These are the game's own key bindings, so they're also in Esc > Options > Keybindings, under Waymark.")
    a:Header("Map")
    for _, k in ipairs(list) do
        if not k.layer then a:KeyBind(k[2], k[1]) end
    end
    local b = Column(p, HALF, 0, HALF)
    b:Header("Show/hide")
    for _, k in ipairs(list) do
        if k.layer then b:KeyBind((k[2]:gsub("%s*%(.-%)$", "")), k[1]) end
    end
end }

PAGES[#PAGES + 1] = { key = "quests", label = "Quests", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Quest data")
    a:Choice("Quests from", "questie", "source", {
        { "own", "Waymark's own" }, { "questiedb", "QuestieDB" },
    })
    a:Tip("Waymark's own: quest givers, turn-ins, objectives and quest ground from data built into the addon, no other addon needed. QuestieDB: read from QuestieDB where it's installed. Townsfolk follow this too. A change takes a /reload.")
    a:Button("Reload now", function() ReloadUI() end)
    a:Header("Quest givers & turn-ins", ns.ToggleIcon("questie"))
    a:Check("Show quest givers", "questie", "shown")
    a:Requires("questie", "shown")
    a:Check("Colour by quest difficulty", "questie", "color")
    a:CheckWith("Low-level (grey) quests", ns.GetTrivialQuests, ns.SetTrivialQuests)
    a:Tip("Grey quest givers: quests far below your level.")
    a:Button("Show hidden quests again", function()
        if ns.UnhideQuests then ns.UnhideQuests() end
    end)
    a:Tip("Right-click a quest giver and pick hide to hide its quests; this brings them all back (also /waymark unhide).")
    a:Requires()
    a:Check("Show turn-ins", "turnins", "shown", nil, ns.ToggleIcon("turnins"))
    a:Tip("Where to hand in finished quests.")
    -- (one look for both: turn-ins copy these, ns.ShareQuestLook)
    a:Requires(function() return ns.IsShown("questie") or ns.IsShown("turnins") end)
    a:Slider("Opacity", 0, 1, 0.05, "questie", "alpha")
    a:Slider("Size", 0.2, 2, 0.05, "questie", "scale")
    a:Choice("Icons", "questie", "iconSet", {
        { "questie", "Questie's" }, { "modern", "Modern" },
    })
    a:Tip("Questie's: its round icons where Questie is installed; without it, the modern \"!\" and \"?\".")
    a:Check(Needs("Questie's tooltip", "Questie"), "questie", "tooltip")
    a:Tip("Hovering a quest giver or turn-in shows Questie's own tooltip (its tooltip settings apply) instead of Waymark's. Objective spots use Questie's either way.")
    a:Check("Quest progress on tooltips", "questie", "unitTips")
    a:Tip("Hovering a monster, an item or a thing in the world your quests want: the quest and how far along that objective is (Kobold Vermin slain: 3/10). Where Questie is loaded, Questie's own lines do this instead.")
    a:Requires()
    a:Header("Objective spots", ns.ToggleIcon("spots"))
    a:Check("Show", "spots", "shown")
    a:Requires("spots", "shown")
    a:Slider("Opacity", 0, 1, 0.05, "spots", "alpha")
    a:Slider("Size", 0.2, 2, 0.05, "spots", "scale")
    a:Check("A colour per quest", "spots", "color")
    a:Tip("Each quest's spots in a colour of its own, so neighbouring quests' spots tell apart.")
    a:Advanced(true)
    a:Slider("Spots of one objective at least", 0, 150, 5, "spots", "spacing", "%d yd apart", "off")
    a:Tip("Mobs often stand in packs: one pin per pack is enough. Questie's own setting for this isn't used.")
    a:Slider("At most, per objective", 0, 40, 1, "spots", "maxPer", "%d pins", "no limit")
    a:Tip("Above this, the most spread-out spots are kept, so the whole area is still marked. The tracker's distances still use every spawn.")
    a:Advanced()
    a:Requires()
    a:Header("Quest ground", ns.ToggleIcon("ground"))
    a:Check("Show", "ground", "shown")
    a:Tip("Where your quests' monsters, drops and things to use are, as ground on the map in each quest's colour. Hover it: what it is, what it drops and for which quest.")
    a:Requires("ground", "shown")
    a:Choice("Look", "ground", "look", {
        { "haze", "Haze" }, { "ink", "Ink rim" }, { "dots", "Spawn dots" }, { "pins", "Pins (loot bags)" },
    })
    a:Tip("Pins: the objective spot pins instead of ground, a loot bag, sword or cog on each spot, as before the ground.")
    a:Slider("Opacity", 0, 1, 0.05, "ground", "alpha")
    a:Check("Also quests I could take", "ground", "all")
    a:Tip("The ground of quests that givers on this map offer you and you haven't taken, fainter.")
    a:Check("Coloured", "ground", "color")
    a:Tip("Off: every quest's ground in one red.")
    a:Requires(function() return ns.db.ground.shown and ns.db.ground.color end)
    a:Choice("Colour by", "ground", "colorBy", { { "quest", "Each quest" }, { "type", "Quest type" } })
    a:Tip("Each quest: neighbouring quests in different colours. Quest type: by what the quest asks. Slay red, gather green, use blue, explore purple, escort teal. (Deliver and speak quests have no ground, only their ? pin.)")
    a:Requires("ground", "shown")
    a:Check("Tooltip names the dropped item", "ground", "drops")
    a:Check("Arrows at lone spots and turn-ins", "ground", "arrows")
    a:Tip("For a quest in focus or found with \"find on map\": a small inked arrow at what's easy to miss, an objective with only one or two spots on the map (a thing to use, an item to pick up, one named monster) and where you hand it in.")
    a:Check("Fade other quests while one is lit", "ground", "hush")
    a:Tip("Hovering a quest (its tracker line, its log line or its ground) or finding it on the map lights it up in gold. With this on, the other quests' ground fades meanwhile so the lit one stands out. Off: they stay as they are, only the gold is added.")
    a:Requires()
    a:Header("Pin filters")
    a:Check("Hide quest pins outside the zone", "outside", "hideQuests")
    a:Tip("The zone map shows bits of the zones around it; quest pins that fall there are hidden. The blue quest areas are one picture, so they stay.")
    a:Check("Objectives of tracked quests only", "outside", "trackedOnly")
    a:Tip("Objective spots and the game's objective markers only for the quests you track.")
    a:Note("Hiding pins in unexplored areas is on the Exploration page.")

    local b = Column(p, HALF, 0, HALF)
    b:Header("Quest objectives (the game's)", ns.ToggleIcon("questMarkers"))
    b:Check("Show", "objectives", "shown")
    b:Requires("objectives", "shown")
    b:Slider("Opacity", 0, 1, 0.05, "objectives", "alpha")
    b:Slider("Size", 0.2, 2, 0.05, "objectives", "scale")
    b:Requires()
    b:Header("Quest areas (blue zones)", ns.ToggleIcon("questAreas"))
    b:Check("Show", "areas", "shown")
    b:Requires("areas", "shown")
    b:Slider("Opacity", 0, 1, 0.05, "areas", "alpha")
    b:Requires()
    b:Header("Learned quest givers")
    b:Check("Show", "learned", "shown")
    -- (the quest data in use, by name: "Quests from" above; a change takes a /reload,
    -- which builds this page again)
    local data = ns.QuestSourceName and ns.QuestSourceName() == "QuestieDB" and "QuestieDB" or "Waymark's data"
    b:Tip("Quest givers your characters have talked to, remembered with where they stand. Covers quests " .. data .. " lacks, such as Forever's new ones.")
    b:Requires("learned", "shown")
    b:Choice("Which quests", "learned", "mode", {
        { "gaps", "Only ones " .. data .. " lacks" }, { "all", "All I've learned" },
    })
    b:Tip("\"Only ones " .. data .. " lacks\" fills its gaps without doubling its pins.")
    b:Check("Turn-ins (\"?\")", "learned", "turnins")
    b:Tip("A \"?\" where a finished quest is handed in.")
    b:Check("Low-level (grey) quests", "learned", "trivial")
    b:Check("Repeatable quests", "learned", "repeatable")
    b:Slider("Opacity", 0, 1, 0.05, "learned", "alpha")
    b:Slider("Size", 0.2, 2, 0.05, "learned", "scale")
    b:Requires()
    b:Check("Keep learning", "learned", "record")
    b:Button("Your learned quests...", function() if ns.ToggleLearnedWindow then ns.ToggleLearnedWindow() end end)
    b:Tip("What you've learned, in a window: the quests by zone and the monsters' spots. Share them or import someone's from there.", "Also: /waymark learned")
    b:Live(function()
        if not ns.LearnedStats then return "" end
        local givers, quests, here, mobs = ns.LearnedStats()
        return string.format("Known: %d quest givers, %d quests (%d on this map), %d monster spots", givers, quests, here, mobs or 0)
    end)
    b:Button("Forget all of it (Shift-click)", function()
        if IsShiftKeyDown() then ns.ForgetLearned() end
    end)
    b:Note("About 25 quests in Era have no spot for their monster, most of them brought by an event. Forever's quests are still being gathered: what you learn is very welcome (Share learned quests and monsters, Setups page).")
end }

PAGES[#PAGES + 1] = { key = "tracker", label = "Quest tracker", build = function(p)
    local T = function() return ns.db.tracker end
    local a = Column(p, 0, 0, HALF)
    a:Header("Quest tracker", ns.ToggleIcon("tracker"))
    a:Check("Show the quest tracker", "tracker", "shown")
    a:Tip("Your tracked quests with something to do in this zone, and their objectives.", "Click: fold. Right-click: view details, find on map. Shift-click: stop tracking. Hover: its areas light up. Wheel: scroll.")
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
    a:Check("Sub-zone headings", "tracker", "groupByArea")
    a:Tip("Each quest under the area its nearest objective is in (Kharanos, Coldridge Valley...); quests with nothing here go under Elsewhere.")
    a:Check("Objectives under each quest", "tracker", "objectives")
    a:Indent(true)
    a:Check("Hide finished objectives", "tracker", "hideDoneObjectives")
    a:Check("Counts in a column at the right", "tracker", "countColumn")
    a:Tip("\"Harvest Watcher  13/20\": the objective's name at the left (no dash, and on English clients no \"slain\"), its count lined up at the right. Off: the game's own line, \"- Harvest Watcher slain: 13/20\".")
    a:Requires(function() return T().shown and T().countColumn ~= false end)
    a:Choice("Finished objectives", "tracker", "doneCount", {
        { "count", "Grey, count kept" }, { "tick", "Grey, a tick for the count" },
    })
    a:Requires("tracker", "shown")
    a:Indent()
    a:Check("Name who takes a finished quest in", "tracker", "turninName")
    a:Tip("A finished quest's line names who to hand it in to, and where (the sub-zone in this zone, else the zone), from QuestieDB. Off, or without QuestieDB: \"Ready for turn-in\".")
    a:Requires(function() return T().shown and T().turninName ~= false end)
    a:Indent(true)
    a:Choice("As", "tracker", "turninStyle", {
        { "place", "Gryan Stoutmantle, Sentinel Hill" }, { "prefix", "Turn in: Gryan Stoutmantle" },
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
    b:Check("Only quests I track", "tracker", "onlyTracked")
    b:Tip("The quests you watch in the quest log, plus any you track from here (hand-in only, or past the game's limit of 5). Off: every quest with something to do here.")
    b:Check("Track quests as I accept them", "tracker", "autoTrack")
    b:Tip("Every quest you pick up is tracked straight away; the game's list first, ours once that is full or for hand-in-only quests.")
    b:Check("Hide it where there are none", "tracker", "hideEmpty")
    b:Choice("Quests in other zones", "tracker", "otherZones", {
        { "always", "Always" }, { "continent", "Only when the map shows a continent" }, { "off", "Never" },
    })
    b:Tip("The quests you track in other zones (as your quest log files them), after this zone's, each zone under its name in gold. Untracked ones from other zones never show.")
    b:Requires()

    -- the look, under both columns
    local y = math.min(a.y, b.y) - 10
    local pct = function(v) return string.format("%d%%", v * 100 + 0.5) end
    local d = Column(p, 0, y, HALF)
    d:Header("Look")
    d:Requires("tracker", "shown")
    d:Check("Same text as the quest log", "tracker", "textAsLog")
    d:Tip("Its zone name like the quest log's Zone names, its quests like Quest names in the list, its objectives like Quest details (Quest log page, Quest log text). Off: its own fonts and sizes below.")
    d:Requires(function() return T().shown and not T().textAsLog end)
    d:Slider("Quest name size", 8, 20, 1, "tracker", "fontSize", "%d")
    d:Requires("tracker", "shown")
    d:TextPart("Sub-zone headings", "tracker", "textSub")
    d:Tip("The sub-zone headings over its quests (and Elsewhere). Its own either way. ", FONT_TIP)
    d:Check("Quest icons", "tracker", "icons")
    d:Tip("A small icon for what each objective wants: kill, collect, use, an event, hand in. Questie's where it's installed, else the game's.")
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
    d:Tip("A kill or a pick-up that counts: that line goes white and fades back over a second. A quest that's just finished: its turn-in line.")
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
    e:Choice("Style", "tracker", "borderStyle", {
        { "map", "Same as the map's" }, { "dialog", "Classic dialog" }, { "gold", "Gold" }, { "tooltip", "Tooltip" },
        { "wood", "Wood" }, { "line", "Thin line" }, { "none", "None" },
    })
    e:Tip("Same as the map's: the map border's style, thickness, distance and colour (Header & border page), so the two line up. The settings below are for the other styles.")
    e:Advanced(true)
    e:Check("Joined to the map's border", "tracker", "joinBorders")
    e:Tip("Attached: no border on the side facing the map, and it hangs straight off the map's border, so the two read as one frame. (Not with the game's own map border.)")
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
    a:Check("Use the quest window", "questlog", "shown")
    a:Tip("A quest's page beside the map: objectives, description, rewards and buttons. Off: the game's quest log instead.", "Right-click a quest in the tracker: view details.")
    a:Requires("questlog", "shown")
    a:Check("Also from its pins on the map", "questlog", "fromPins")
    a:Tip("Click an objective spot, a turn-in or a quest's ground: its page opens. (Lighting a spot's quest is then in its right-click menu.)")
    -- (with the window's own settings, not its buttons: moved here 2026-11-03)
    a:Check("Light up its spots and areas while open", "questlog", "glow")
    a:Tip("As hovering it in the tracker does: its objective spots and turn-in glow, and with the Quest areas layer on, its areas.")
    a:Check("Open it with the quest log key", "questlog", "keyL")
    a:Tip("While the map shows, your quest log key (L) opens this window instead of the game's quest log.")
    a:Check("Replace the game's quest log", "questlog", "replaceGame")
    a:Tip("Your quest log key opens this window, map or not, and the game's quest log stays closed.")
    -- (your whole log at the window's top is always there now: no switch, 2026-11-03)
    a:Check("Your zone's quests first", "questlog", "listHereFirst")
    a:Tip("Your log at the top of the window: click a zone to fold it, Shift-click it to track all its quests (again: none). Drag the line under it for more room.")
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
    a:Tip("From the top of the map's border to its bottom. Off: its own height (below, or drag its bottom edge), hanging from the map's top.")
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
    b:Tip("From QuestieDB: every step of the quest's chain (done ones ticked, this one marked, the rest with their levels), and quests that lead into it. Click a step not in your log to read about it.")
    b:Check("Who gave it and who takes it", "questlog", "people")
    b:Tip("From QuestieDB: the names of the quest's giver and of who takes it in, with their zones.")
    b:Advanced(true)
    b:Check("Quest ID", "questlog", "questID")
    b:Advanced()
    b:Requires()

    b:Header("Buttons")
    b:Requires("questlog", "shown")
    b:Check("Abandon", "questlog", "abandon")
    b:Check("Share", "questlog", "share")
    b:Check("Track", "questlog", "track")
    b:Check("Focus", "questlog", "focus")
    b:Requires()

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
    b:Choice("Style", "questlog", "borderStyle", {
        { "own", "The quest log's own" }, { "map", "Same as the map's" }, { "dialog", "Classic dialog" },
        { "gold", "Gold" }, { "tooltip", "Tooltip" }, { "wood", "Wood" }, { "line", "Thin line" }, { "none", "None" },
    })
    b:Tip("Same as the map's: the map border's style, thickness, distance and colour, so the two line up. The settings below are for the other styles.")
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
    a:Tip("Positions come from the quest data (built in, or QuestieDB: Quests page), and from the townsfolk learned as you play (below).")
    a:Requires("townsfolk", "shown")
    a:Slider("Opacity", 0, 1, 0.05, "townsfolk", "alpha")
    a:Slider("Size", 0.2, 2, 0.05, "townsfolk", "scale")
    a:Requires()
    -- which ones: trainers, services and vendors side by side (a checklist)
    a:Header("Which townsfolk")
    a:Requires(function() return ns.db.townsfolk.shown end)
    a:Grid(3)
    a:SubHeader("Trainers")
    TypeCheck(a, "Profession trainers", "professions")
    a:Indent(true)
    a:Check("Only my professions", "townsfolk", "myProfessionsOnly")
    a:Indent()
    for _, t in ipairs(types.services) do
        if trainers[t.key] then TypeCheck(a, t.label, t.key) end
    end
    a:SubHeader("Services")
    for _, t in ipairs(types.services) do
        if not trainers[t.key] then TypeCheck(a, t.label, t.key) end
    end
    a:SubHeader("Vendors")
    for _, t in ipairs(types.vendors) do TypeCheck(a, t.label, t.key) end
    a:Grid()
    a:Requires()
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
    l:Tip("Vendors, trainers, flight masters and the like you talk to are remembered with where they stand, by every character on your account.")
    l:Check("Show them on the map", "townsfolk", "useLearned")
    l:Tip("Alongside the quest data's townsfolk (the same NPC isn't shown twice), or on their own. Off until you've learned enough to be useful.")
    l:Live(function()
        if not ns.LearnedTownsfolkStats then return "" end
        local n, here = ns.LearnedTownsfolkStats()
        return string.format("Known: %d townsfolk (%d on this map)", n, here)
    end)
    l:Button("Forget all of them (Shift-click)", function()
        if IsShiftKeyDown() then ns.ForgetLearnedTownsfolk() end
    end)
end }

PAGES[#PAGES + 1] = { key = "group", label = "You & your group", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Player & group")
    a:Check("Show", "party", "shown")
    a:Tip("Hiding these also hides your own arrow: the game draws them together.")
    a:Slider("Opacity", 0, 1, 0.05, "party", "alpha")
    a:Slider("Player arrow", 0, 48, 1, "mapFrame", "arrowSize", "%d", "game default")
    a:Check("Classic map arrow", "cave", "classicArrow")
    a:Tip("The classic world map's arrow for you, on the zone map and in caves.")
    a:Slider("Group icons", 0, 32, 1, "mapFrame", "groupSize", "%d", "game default")
    a:Header("Group members")
    a:Check("Dots in class colours", "party", "classColors")
    a:Check("Tooltips on hover", "party", "hover")
    a:Tip("Name, level, health and distance. Several members close together share one tooltip.")

    local b = Column(p, HALF, 0, HALF)
    b:Header("Line to target", ns.ToggleIcon("line"))
    b:Check("Show", "line", "shown")
    b:Requires("line", "shown")
    b:Slider("Opacity", 0.1, 1, 0.05, "line", "alpha")
    b:Slider("Thickness", 1, 8, 1, "line", "thickness", "%d")
    b:Requires()
    b:Header("Line aims at")
    b:Requires("line", "shown")
    b:Check("My target, when it's in my group", "line", "groupTarget")
    b:Tip("The game only tells addons where group members are, so NPCs and other players can't be targeted.")
    b:Check("The nearest objective spot", "line", "nearestSpot")
    b:Requires()
end }

-- what other addons put on the map: RareScanner, GatherMate2 (TomTom's waypoints: left
-- off the pages until they show on this map; Waypoints.lua and its settings are kept)
PAGES[#PAGES + 1] = { key = "rares", label = "Rares & gathering nodes", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header(Needs("Rares & treasures", "RareScanner"), ns.ToggleIcon("rares"))
    a:Check("Show", "rares", "shown")
    a:Tip("What shows follows RareScanner's own world map filters.")
    a:Requires("rares", "shown")
    a:Slider("Opacity", 0, 1, 0.05, "rares", "alpha")
    a:Slider("Size", 0.2, 2, 0.05, "rares", "scale")
    a:Check("RareScanner's own icons", "rares", "rsIcons")
    a:Requires()

    a:Header("Rares & chests (built in)", ns.ToggleIcon("wilds"))
    a:Check("Show", "wilds", "shown")
    a:Tip("From the addon's own data: where each rare and rare elite stands, its level and its own drops with their chances." .. (ns.WILDS_TREASURE and " And the spots random treasure chests may stand at." or "") .. " No respawn times or sightings (RareScanner has those).")
    a:Requires("wilds", "shown")
    a:Check("Rares", "wilds", "rares")
    a:Check("Rare elites", "wilds", "elites")
    if ns.WILDS_TREASURE then  -- (off for 1.2, Wilds.lua)
        a:Check("Treasure chest spots", "wilds", "treasure")
        a:Tip("Every spot a random chest may stand at: a busy zone has dozens, so off at first.")
    end
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
    a:Check("Boss loot: \"what they carry\" in boss menus", "wilds", "bossLoot")
    a:Tip("A boss's own drops with their chances, greens and better first, then its quest items. Not the world drops every monster shares.")

    local b = Column(p, HALF, 0, HALF)
    b:Header(Needs("Gathering nodes", "GatherMate2"), ns.ToggleIcon("gather"))
    b:Check("Show", "gather", "shown")
    b:Requires("gather", "shown")
    b:Slider("Opacity", 0, 1, 0.05, "gather", "alpha")
    b:Slider("Size", 0.2, 2, 0.05, "gather", "scale")
    b:Check("Follow GatherMate's own rules", "gather", "follow")
    b:Tip("On: a type also needs GatherMate to show it (e.g. only with the profession). GatherMate's per-node filters always apply.")
    b:SubHeader("Node types")   -- (part of GatherMate's section, not one of its own)
    for _, t in ipairs(ns.GATHER_TYPES or {}) do
        b:CheckWith(t.label,
            function() return ns.db.gather.types[t.key] end,
            function(v)
                ns.db.gather.types[t.key] = v or nil
                ns.OnSettingChanged("gather", "types")
            end)
    end
    b:Requires()
end }

-- your own marks on the maps, and the found notes' book (Ink.lua, Notebook.lua)
PAGES[#PAGES + 1] = { key = "ink", label = "Map ink & notes", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Your map ink")
    a:Check("On the world map", "ink", "shown")
    a:Tip("Routes, marks and notes you drew on the zone maps. The ink button on the map switches it.", "Ctrl-drag a mark to move it (with the quill out, just drag); right-click it for more.")
    a:Check("Dungeons too", "ink", "dungeons")
    a:Tip("The ink button hides your ink on dungeon floors as well. Off: it stays on them whatever the button says.")
    a:Requires("ink", "shown")
    a:Slider("Opacity", 0.1, 1, 0.05, "ink", "alpha")
    a:Slider("Note size", 0.6, 1.6, 0.1, "ink", "textSize", "%.1f")
    a:Requires()
    a:Button("Take up the quill", function() if ns.QuillToggle then ns.QuillToggle() end end)
    a:Tip("The quill's bar: draw routes and marks and write notes on the map, as in the found notes.", "Also: Shift-click the ink button on the map, or /waymark ink. Again: put it down.")
    a:Header("Found notes")
    a:Button("Open the notebook", function() if ns.ToggleNotebook then ns.ToggleNotebook() end end)
    a:Tip("Pages someone left about the dungeons. Their numbered rings show on the dungeon maps.", "Click the stamp in a dungeon map's corner for its page. /waymark notes opens the book too.")
end }

PAGES[#PAGES + 1] = { key = "explore", label = "Exploration", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Unexplored areas")
    a:Check("Show", "explore", "shown")
    a:Tip("The game leaves them blank. All zones of Kalimdor and the Eastern Kingdoms; the area art is the game's own.")
    a:Requires("explore", "shown")
    a:Choice("Look", "explore", "fogStyle", {
        { "fog", "Fog" }, { "sepia", "Sepia" }, { "ink", "Dark ink" }, { "faded", "Faded" }, { "full", "As explored" },
    })
    a:Slider("Opacity", 0.1, 1, 0.05, "explore", "fogAlpha")
    a:Tip("The unexplored areas' own opacity. The map opacity (The window) comes on top: at 0% they're gone with the rest of the map.")
    a:Requires()
    a:Header("Pins in unexplored areas")
    a:Check("Hide quest pins there", "explore", "hideQuests")
    a:Check("Hide townsfolk, rares, nodes there", "explore", "hideOthers")
    a:Header("Discoveries")
    a:Check("Gold flash where I discover an area", "explore", "flash")
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
    a:Check("Switch to the game's cave maps", "dungeon", "followMaps")
    a:Tip("Where the game itself puts you on a cave or dungeon map with art, the map switches to it.")
    a:Check("Cave view", "cave", "enabled")
    a:Tip("Inside a cave the map shows the cave: Blizzard's cave map, or the cave's minimap pictures round you.")
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
    a:Tip("Right-click the dungeon's map (not on a boss or a pin) to return to the zone. The classic dungeons and raids; the game's data has no entrance for Forever's new ones.")
    a:Requires("dungeons", "shown")
    a:Check("On continent maps too", "dungeons", "continent")
    a:Tip("Every door of the continent at once, drawn smaller. On the Battlefield map and the world map.")
    a:Slider("Size", 0.4, 2, 0.05, "dungeons", "scale")
    a:Requires()

    local b = Column(p, HALF, 0, HALF)
    b:Header("Inside dungeons")
    b:Check("Show the dungeon's map", "dungeon", "fallback")
    b:Tip("The game's own art of the dungeon, with its bosses.", "Wheel: zoom. Drag: pan. Right-click: whole map. < >: floors.")
    b:Requires("dungeon", "fallback")
    b:Check("Open the Battlefield Map as I go in", "dungeon", "showInside")
    b:Choice("View", "dungeon", "view", {
        { "art", "Map (boss markers)" },
        { "minimap", "Minimap (your arrow)" },
    })
    b:Tip("Map: the dungeon's map with its bosses. Minimap: your real minimap shown large in the map, with your arrow; it's back in its place when you switch, leave or close the map.")
    b:Check("Boss markers", "dungeon", "bosses")
    b:Tip("Numbered in kill order, with a red X once killed.")
    b:Check("Boss list", "dungeon", "bossList")
    b:Tip("The bosses in kill order down the map's left side, ticked as they die.", "Click a name: its floor. Click the title: fold it.")
    b:Choice("Doors, chests, quests, NPCs", "dungeon", "objects", {
        { "icons", "Icons" },
        { "hidden", "Hidden (tooltip on hover)" },
        { "off", "Off" },
    })
    b:Tip("Doors and the keys they want, chests, switches, quest spots and friendly NPCs. Hidden: no icons, but the tooltip still shows over the spot.", "With the quill: drag a pin to move it, right-click to put it back or hide it.")
    b:Slider("Icon size", 0.5, 2, 0.05, "dungeon", "objectScale")
    b:Check("All chests", "dungeon", "allChests")
    b:Tip("Also the chests that only sometimes stand in a spot (one of several, picked at random).")
    b:Check("All quest pins", "dungeon", "allQuests")
    b:Tip("Also the quest things found all over a floor. Off: only the ones that stand out.")
    b:Check("Patrols", "dungeon", "patrols")
    b:Tip("The monsters that walk, and their way as a line of dots.")
    if ns.DungeonMobs then                                 -- (dev only: not shipped, tools\build_era_release.py)
        b:Check("Monster dots (dev)", "dungeon", "devMobs")
        b:Tip("A small dot where each monster stands. Hover: its name and level.", "Hold Shift: what to watch for, and what it casts.")
    end
    b:Check("Where you are (a guess)", "dungeon", "where")
    b:Tip("The game gives no position inside, so the part of the floor whose monsters you've been seeing and fighting lights up softly.")
    b:Requires()
end }

-- when each context is on (Profiles.lua's Matches)
local PROFILE_WHEN = {
    combat = "While you're in a fight.",
    battleground = "Inside a battleground or an arena.",
    dungeon = "Inside a dungeon or a raid.",
    city = "In a capital, or a town while town view is on (else where you rest).",
    gathering = "Out in the world with two or more gathering nodes (GatherMate2) within 100 yards.",
}

-- One table: the layers down the left, a column per context (Show / Hide / -
-- each), so the contexts read side by side at the window's width
PAGES[#PAGES + 1] = { key = "profiles", label = "Context profiles", build = function(p)
    local LAYERS = {
        { "questie", "Quest givers" }, { "turnins", "Turn-ins" }, { "spots", "Objective spots" },
        { "objectives", "Objectives (the game's)" }, { "areas", "Quest areas (the game's)" },
        { "learned", "Learned quest givers" }, { "tracker", "Quest tracker" },
        { "townsfolk", "Townsfolk" }, { "dungeons", "Dungeon entrances" }, { "party", "Player & group" },
        { "rares", "Rares & treasures" }, { "gather", "Gathering nodes" }, { "line", "Line to target" },
        { "explore", "Unexplored areas" }, { "detail", "Close-up detail" }, { "zoneName", "Header" },
        { "coords", "Coordinates" },
    }
    local order = ns.PROFILE_ORDER or {}
    local w = Column(p, 0, 0, CONTENT_W)
    w:Note("While a context is on, its column overrides the layers: Show or Hide, or - to leave the layer as you set it. Where two contexts are on, the one further left wins. Your own settings aren't changed.")
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

PAGES[#PAGES + 1] = { key = "setups", label = "Setups", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("Save this setup")
    a:Note("Your settings are always kept on this character, as you leave them. A setup is a copy of them under a name, to load again or share. Changes you make after loading one stay on this character, but they're only in the setup once you save it again. Ready-made ones to start from: Start here.")
    local nameBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    nameBox:SetSize(170, 20)
    nameBox:SetPoint("TOPLEFT", a:Left() + 6, a.y - 4)
    nameBox:SetAutoFocus(false)
    local save = RedButton(p)
    save:SetSize(100, 22)
    save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    save:SetText("Save")
    a.y = a.y - 34

    a:Header("Saved setups")
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
        r.load = Btn("Load", 50, r.text, function(n) ns.LoadSetup(n) ns.RefreshControls() end)
        r.export = Btn("Export", 56, r.load, function(n) ns.ShowExport(n) end)
        r.delete = Btn("Delete", 56, r.export, function(n)
            ns.DeleteSetup(n)
            ns.RefreshControls()
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
        if ns.SaveSetup(nameBox:GetText()) then
            nameBox:SetText("")
            nameBox:ClearFocus()
            ns.RefreshControls()
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
        r.forget:SetText("Forget")
        r.forget:SetScript("OnClick", function() ns.ForgetCharacter(r.name) ns.RefreshControls() end)
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
    b:Button("Import...", function() ns.ShowImport() end)
    b:Button("Export the settings in use", function() ns.ShowExport() end)
    b:Button("Share learned quests and monsters", function() if ns.ShowLearnedExport then ns.ShowLearnedExport() end end)
    b:Tip("The quest givers, quests and monster spots learned as you play, as a string. Whoever imports it (Import...) adds them to theirs.")
    b:Note("A setup travels as a string of text, like other addons' profiles: Export, copy it (Ctrl+C) and paste it in Discord, a forum or a note. Import opens a box to paste one into; it's saved under its name.")
    b:Note("Your boss notes, placed boss spots and map markings stay yours: they're not part of a setup.")
end }

-- the settings pages' text sizes, as real sizes
local function SizeChoices(lo, hi, default)
    local out = {}
    for s = lo, hi do out[#out + 1] = { s, s == default and (s .. "  (normal)") or tostring(s) } end
    return out
end

-- work in progress, kept apart from the finished settings
PAGES[#PAGES + 1] = { key = "dev", label = "Dev", build = function(p)
    local a = Column(p, 0, 0, HALF)
    a:Header("AI-upscaled map art")
    a:Check("Sharp map art (upscaled)", "detail", "sharpArt")
    a:Tip("The zone maps drawn from the Waymark_MapArt folder's upscaled pictures instead of the game's own. Made from WoW Forever's maps, so on other clients they may not line up.")
    a:Live(function()
        return ns.MapArtAvailable and ns.MapArtAvailable() and "Installed: Waymark_MapArt"
            or "Not installed: the Waymark_MapArt folder"
    end)

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
    a:Note("Also: /waymark quest <id> (its box is on the command bar), /waymark <number> (the map's scale, 0.3-3).")
end }

-- Panel -------------------------------------------------------------------

local panel, content
local pageFrames, navButtons = {}, {}
local currentPage
-- the title bar over the page (it doesn't scroll): the page's name, after the
-- group it's in (pageGroup[key], from the category list)
local pageTitle, pageCrumb
local pageFold  -- (before the title: folds every section on the page, or opens them)
local pageGroup = {}

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
    end
    local function Arrow(b, dir)
        if not b then return end
        local name = "minimal-scrollbar-arrow-" .. dir
        b:SetSize(17, 11)
        StateArt(b, "Normal", name)
        StateArt(b, "Pushed", name .. "-down")
        StateArt(b, "Highlight", name .. "-over")
        local off = StateArt(b, "Disabled", name)
        if off then off:SetAlpha(0.35) end
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
    if bar then MinimalScrollBar(bar) end
    scroll:HookScript("OnScrollRangeChanged", function(self, _, yRange)
        if bar then bar:SetShown((yRange or self:GetVerticalScrollRange()) > 1) end
        if (yRange or 0) < 1 then self:SetVerticalScroll(0) end
    end)
    if bar then bar:SetShown(f:GetHeight() > content:GetHeight() + 1) end
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

local function ResetPage(key)
    local f = pageFrames[key]
    if f and f.bfiKeys then ResetKeys(f.bfiKeys) end
end

-- the thresholds that are hard to get back by hand, for their own reset buttons
local RESET_GROUPS = {
    zoom = { label = "every zoom and close-up detail threshold",
             { "zoom", "closestX" }, { "zoom", "smoothness" }, { "zoom", "clusterX" }, { "zoom", "townX" },
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
                pageTitle:SetText(def.label)
                pageCrumb:SetText(pageGroup[key] or "")
                -- (not while searching: every section is open then)
                pageFold:SetShown(f.bfiSections ~= nil and not foldsOpen)
                pageFold.Look()
            end
        end
    end
    currentPage = key
    ns.db.optionsWindow.page = key  -- (opens there again next time, after a reload too)
    if ns.HideOptionShadow then ns.HideOptionShadow() end  -- (a mark belongs to its page)
    ns.RefreshControls()
end

-- the category list: everything, grouped; or, while searching, only the pages
-- with matches (the page's name counts too), each with how many.
-- a group: { title, box = its heading's bar, head = fontstring, button = the
-- heading, fold = its +/- button, def = its summary page or nil }; a page:
-- { def, button, text, group }
local navItems = {}
local noMatches
local nav, navScroll  -- (the list, and the scroll frame it sits in)
local NAV_TOP = -2
local NAV_W = 186  -- (options_list_active's width, near enough: the column's)
local NAV_BAR = 14  -- (narrower by this while the list's scroll bar shows)
local PANEL_W, PANEL_H = 900, 700  -- (the window, BuildPanel)

-- a group's pages folded away in the list (kept by its title)
local function Collapsed(title) return ns.db.optionsWindow.collapsed[title] == true end

local function LayoutNav()
    -- which show: everything, or (searching) the pages with matches or a
    -- matching name, and the groups they're in
    for _, it in ipairs(navItems) do
        if it.title then
            it.n = (query ~= "" and it.def) and #Matches(it.def) or 0
            it.any = false
        else
            it.n = query ~= "" and #Matches(it.def) or 0
            it.show = query == "" or it.n > 0 or it.def.label:lower():find(query, 1, true) ~= nil
            if it.show and it.group then it.group.any = true end
        end
    end
    local y, first, open = NAV_TOP, nil, nil
    -- a gap after a group's last page
    local function Close()
        if not open then return end
        y = y - 10
        open = nil
    end
    local function Count(n) return n > 0 and ("  |cff999999(" .. n .. ")|r") or "" end
    for _, it in ipairs(navItems) do
        if it.title then
            Close()
            it.shown = query == "" or it.n > 0 or it.any
            it.box:SetShown(it.shown)
            if it.shown then
                it.box:SetPoint("TOPLEFT", 0, y)
                open = { box = it.box, top = y }
                it.folded = query == "" and Collapsed(it.title)
                it.fold:SetShown(query == "")
                it.fold.Look()
                it.head:SetText((it.def and it.def.label or it.title) .. Count(it.n))
                y = y - 28
                if it.def and (query == "" or it.n > 0) then first = first or it.def.key end
            end
        elseif it.group and (not it.group.shown or it.group.folded) or not it.show then
            it.button:Hide()
        else
            it.button:Show()
            it.button:SetPoint("TOPLEFT", it.group and 1 or 0, y)
            it.text:SetText(it.def.label .. (query ~= "" and Count(it.n) or ""))
            y = y - (it.group and 21 or 25)
            first = first or it.def.key
        end
    end
    Close()
    noMatches:SetShown(query ~= "" and not first)
    noMatches:SetPoint("TOPLEFT", 10, NAV_TOP - 6)
    -- longer than the column: it scrolls, its rows narrowed for the bar
    local view = navScroll:GetHeight()
    if view < 1 then view = PANEL_H - 64 - 46 - 16 end  -- (not laid out yet)
    local over = -y > view + 1
    local w = over and NAV_W - NAV_BAR or NAV_W
    for _, it in ipairs(navItems) do
        if it.title then
            it.box:SetWidth(w)
            it.button:SetWidth(w)
        else
            it.button:SetWidth(it.group and w - 2 or w)
        end
    end
    nav:SetHeight(math.max(1, -y))
    if navScroll.ScrollBar then navScroll.ScrollBar:SetShown(over) end
    if not over then navScroll:SetVerticalScroll(0) end
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
local function RebuildPages()
    if IsMouseButtonDown("LeftButton") then
        C_Timer.After(0.2, RebuildPages)
        return
    end
    rebuildWaiting = false
    if not panel then return end
    DropPages()
    if currentPage then SelectPage(currentPage) end
    if query ~= "" then LayoutNav() end
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
    DropPages()
    SelectPage(currentPage)
    local f = pageFrames[currentPage]
    if not f then return end
    local function Scroll()
        f.bfiScroll:SetVerticalScroll(math.min(at, f.bfiScroll:GetVerticalScrollRange()))
    end
    Scroll()
    C_Timer.After(0, Scroll)  -- (the range is known once the new page is laid out)
end

function ns.ToggleOptionSection(key)
    local folded = ns.db.optionsWindow.folded
    folded[key] = not folded[key] or nil
    RelayoutPage()
end

-- The page's sections all folded (the title's +/- then shows +)
local function PageFolded()
    local f = currentPage and pageFrames[currentPage]
    if not (f and f.bfiSections) then return false end
    for _, key in ipairs(f.bfiSections) do
        if not ns.db.optionsWindow.folded[key] then return false end
    end
    return true
end

-- The page title's +/-: any section open folds them all, else opens them all
local function FoldPage()
    local f = currentPage and pageFrames[currentPage]
    if not (f and f.bfiSections) then return end
    local fold = not PageFolded()
    for _, key in ipairs(f.bfiSections) do ns.db.optionsWindow.folded[key] = fold or nil end
    RelayoutPage()
end

local function Search(text)
    query = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if MatchAdvanced() and currentPage then SelectPage(currentPage) end
    local first = LayoutNav()
    -- stay on the page you're on if it still matches, else the first that does
    local stay = currentPage and navButtons[currentPage] and navButtons[currentPage]:IsShown()
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
        local bl = Piece("ui-frame-metal-cornerbottomleft-2x", 32, 32)
        bl:SetPoint("BOTTOMLEFT", L, B)
        local br = Piece("ui-frame-metal-cornerbottomright-2x", 32, 32)
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

local function BuildPanel()
    advancedShown = ns.db.optionsWindow.advanced and true or false
    panel = CreateFrame("Frame", "WaymarkOptions", UIParent)
    panel:SetSize(PANEL_W, PANEL_H)
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
    title:SetPoint("TOP", 0, -4)
    title:SetText("Waymark")
    -- the close button: Forever's own red X, in its bronze rim (redbutton-*-c60)
    local close = CreateFrame("Button", nil, panel)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -5, 1)
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
        navBar:SetPoint("TOPRIGHT", navScroll, "TOPRIGHT", 2, -12)
        navBar:SetPoint("BOTTOMRIGHT", navScroll, "BOTTOMRIGHT", 2, 12)
        navBar:SetWidth(10)
        navBar:Hide()
        navScroll:HookScript("OnScrollRangeChanged", function(self, _, yRange)
            navBar:SetShown((yRange or self:GetVerticalScrollRange()) > 1)
        end)
    end

    -- the pages grouped: "#" entries are group headings. The window itself; how
    -- it moves with you and where you are; what's drawn on it; and your own setup.
    -- "#Heading>key": the heading opens that page (the group's own summary)
    local NAV = {
        "overview",
        "#The window>windowhome", "window", "clearview", "minimap", "header", "controls",
        "#Getting around>aroundhome", "behaviour", "browse", "town", "city", "dungeon", "explore",
        "#What's shown>shownhome", "quests", "tracker", "questlog", "people", "group", "rares", "ink",
        "#Your setup", "profiles", "setups", "keys",
        "#Development", "dev",
    }
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

    -- A group: the heading's dark bar over an outline round its pages
    -- (options_categoryheader_1), a +/- at the bar's end that folds the pages
    -- away and back. A heading with a page of its own (def) opens it when
    -- clicked; a plain one folds when clicked anywhere.
    local function GroupHeading(title, def)
        -- (just the bar of options_categoryheader_1: the outline under it,
        -- meant to run round the pages, stuck out past the list's edges)
        local box = CreateFrame("Frame", nil, nav)
        box:SetSize(NAV_W, 26)
        box:SetFrameLevel(nav:GetFrameLevel() + 1)
        ns.SliceArt(box, "options_categoryheader_1", 8 / 197, 8 / 197, 0, 0, 6, 6, 0, 0,
            nil, nil, { 1 / 199, 198 / 199, 3 / 144, 28 / 144 })
        local b = NavButton(box, NAV_W, 26)
        b:SetPoint("TOPLEFT")
        local h = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        h:SetPoint("LEFT", 10, 0)
        h:SetShadowColor(0, 0, 0, 1)
        h:SetShadowOffset(1, -1)

        local it = { title = title, box = box, head = h, button = b, def = def }
        local function Toggle()
            ns.db.optionsWindow.collapsed[title] = not Collapsed(title)
            LayoutNav()
        end
        local fold = FoldButton(b, function() return it.folded end, Toggle)
        fold:SetPoint("RIGHT", -6, 0)
        fold:SetScript("OnEnter", function()
            GameTooltip:SetOwner(fold, "ANCHOR_RIGHT")
            GameTooltip:SetText(Collapsed(title) and "Show this group's pages" or "Hide this group's pages")
            GameTooltip:Show()
        end)
        fold:SetScript("OnLeave", function() GameTooltip:Hide() end)
        it.fold = fold

        if def then
            b:SetScript("OnClick", function() SelectPage(def.key) end)
            -- (gold under the mouse; no tooltip: it covered the page)
            b:SetScript("OnEnter", function() h:SetTextColor(1, 0.82, 0) end)
            b:SetScript("OnLeave", function() h:SetTextColor(1, 1, 1) end)
            navButtons[def.key] = b
        else
            b:SetScript("OnClick", Toggle)
        end
        return it
    end

    local group  -- (the heading the pages below are under)
    for _, entry in ipairs(NAV) do
        local title, pageKey = entry:match("^#(.-)>(.+)$")
        if title and byKey[pageKey] then
            group = GroupHeading(title, byKey[pageKey])
            navItems[#navItems + 1] = group
        elseif entry:sub(1, 1) == "#" then
            group = GroupHeading(entry:sub(2))
            navItems[#navItems + 1] = group
        elseif byKey[entry] then
            pageGroup[entry] = group and group.title
            local def = byKey[entry]
            local b = NavButton(nav, group and NAV_W - 2 or NAV_W, group and 21 or 23)
            b:SetFrameLevel(nav:GetFrameLevel() + 4)
            local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", group and 16 or 10, 0)
            text:SetPoint("RIGHT", -6, 0)
            text:SetJustifyH("LEFT")
            text:SetWordWrap(false)
            text:SetText(def.label)
            -- (greyed: the addon it needs isn't installed)
            local missing = def.needs and not ns.AddonPresent(def.needs)
            b.Color = function()
                if missing then text:SetTextColor(0.55, 0.5, 0.45)
                elseif b.selected:IsShown() or b:IsMouseOver() then text:SetTextColor(1, 1, 1)
                else text:SetTextColor(1, 0.82, 0) end
            end
            b:SetScript("OnEnter", function()
                b.Color()
                if missing then
                    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
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
            navButtons[def.key] = b
            navItems[#navItems + 1] = { def = def, button = b, text = text, group = group }
        end
    end

    -- the search box, under the title (the game's search box look)
    local ok, box = pcall(CreateFrame, "EditBox", nil, panel, "SearchBoxTemplate")
    if not ok then box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate") end
    box:SetSize(180, 22)
    box:SetPoint("TOPLEFT", 24, -32)
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
    divider:SetPoint("TOPLEFT", inner, "TOPLEFT", 212, -44)
    divider:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    divider:SetHeight(1)
    ns.SetArt(divider, "options_horizontaldivider")

    -- the page, right of the list (room for the scroll bar on its right)
    content = CreateFrame("Frame", nil, inner)
    content:SetPoint("TOPLEFT", inner, "TOPLEFT", 214, -52)
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
        GameTooltip:AddLine("Fine-tuning on every page: nudges, thicknesses, fonts, spacing, exact thresholds. Off keeps the pages to their main choices; searching finds the hidden ones anyway.", 1, 1, 1, true)
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
        for _, def in ipairs(PAGES) do if def.key == last then known = true end end
        SelectPage(known and last or PAGES[1].key)
    end
    panel:SetShown(not panel:IsShown())
end

function ns.ToggleTownsfolkOptions() ns.ToggleOptions("people") end

-- for the Overview page's > buttons
function ns.OpenOptionsPage(key)
    ns.GlowNavPage(key, false)  -- (the mouse is still on the button as the page changes)
    SelectPage(key)
end

-- a page's name in the list, lit as if hovered (on) or back to normal
function ns.GlowNavPage(key, on)
    local b = navButtons[key]
    if not b then return end
    if on then b:LockHighlight() else b:UnlockHighlight() end
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
    if not page then return end
    -- its section folded away: open it, and find it on the page laid out again
    if m.sec and ns.db.optionsWindow.folded[m.sec] then
        ns.db.optionsWindow.folded[m.sec] = nil
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
    quickPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    quickPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    quickPanel:SetBackdropColor(0, 0, 0, 0.9)
    quickPanel:SetFrameStrata("DIALOG")
    quickPanel:EnableMouse(true)
    -- beside the map, not over it: to its left, or to its right when the left
    -- side of the screen hasn't room (decided each time it opens)
    local function Place(self)
        self:ClearAllPoints()
        self:SetClampedToScreen(true)
        -- (docked: left of the square, which sits where the minimap is)
        if ns.Docked and ns.Docked() and Minimap then
            self:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -14, 0)
            return
        end
        local left = map:GetLeft() and map:GetLeft() * map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if left and left < self:GetWidth() + 4 then
            self:SetPoint("TOPLEFT", map, "TOPRIGHT", 4, 0)
        else
            self:SetPoint("TOPRIGHT", map, "TOPLEFT", -4, 0)
        end
    end

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
                    city = "in town", gathering = "gathering" }
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
    local top = Column(quickPanel, 10, -4, FULL)
    top:Header("The map")
    local roles, prev = {}, nil
    for _, r in ipairs({ { "window", "Window" }, { "clear", "Clear view" }, { "dock", "Minimap" } }) do
        local b = RedButton(quickPanel)
        b:SetSize((FULL - 8) / 3, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, top.y - 2) end
        b:SetText(r[2])
        b:SetScript("OnClick", function()
            SetMapRole(r[1])
            ns.RefreshControls()
            -- (docking moves the map: the panel follows once it has)
            C_Timer.After(0.2, function() if quickPanel:IsShown() then Place(quickPanel) end end)
        end)
        b.role = r[1]
        roles[#roles + 1] = b
        prev = b
    end
    Tip(roles[1], "The map", "Window: the Battlefield Map where you put it. Clear view: the map without its frame, laid over the world. Minimap: it replaces your minimap, and every map feature still works there.")
    for i = 2, 3 do Tip(roles[i], "The map", "Window: the Battlefield Map where you put it. Clear view: the map without its frame, laid over the world. Minimap: it replaces your minimap, and every map feature still works there.") end
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
    presets:SetText("Presets...")
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
    -- quest marks in four steps (learned givers and the game's objectives and
    -- areas come with the givers, as Start here's quest help)
    local function Marks(givers, turnins, spots)
        local want = { questie = givers, learned = givers, objectives = givers, areas = givers,
                       turnins = turnins, spots = spots }
        return function()
            for g, v in pairs(want) do if Shown(g) ~= v then return false end end
            return true
        end, function() SetShown(want) end
    end
    local MARKS = {}
    for _, m in ipairs({ { "Off", false, false, false }, { "Givers", true, false, false },
                         { "Givers & turn-ins", true, true, false }, { "All", true, true, true } }) do
        local is, set = Marks(m[2], m[3], m[4])
        MARKS[#MARKS + 1] = { m[1], is, set }
    end
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
    CycleRow(a, "Quest marks", MARKS, "Off; quest givers; givers and turn-ins; or all, objective spots too. Each layer is on the Quests page.",
        { "questie", "turnins", "spots" }, { "questie", "shown" })
    a:CheckWith("Low-level (grey) quests", ns.GetTrivialQuests, ns.SetTrivialQuests)
    a:Tip("Quest givers far below your level.")
    SettingsMenu(a.last, "questie", "color")
    Layer(a, "Quest ground", "ground")
    Layer(a, "Quest tracker", "tracker")
    Context(a.last.text, { "tracker" })
    a:Header("Places")
    Layer(a, "Townsfolk", "townsfolk")
    Context(a.last.text, { "townsfolk" })
    CycleRow(a, "Rares", RARES, "Built in: rares and chests the addon knows. RareScanner: its pins instead, where it's installed. Off: none.",
        nil, { "wilds", "shown" })  -- (no context marker here)
    a:Requires(function() return ns.AddonPresent("GatherMate2") end)
    Layer(a, "Gathering nodes", "gather")
    Context(a.last.text, { "gather" })
    a:Tip("From GatherMate2, where it's installed.")
    a:Requires()
    a:Header("On the map")
    Layer(a, "Unexplored areas", "explore")
    Context(a.last.text, { "explore" })
    Layer(a, "Close-up detail", "detail")
    -- (and on the same line: at every zoom, continents too)
    local detailRow = a.last
    local gAll, sAll = Setting("detail", "always")
    local always = CreateCheck(quickPanel, "Every zoom level", gAll, sAll, nil, 160)
    always:SetSize(20, 20)
    always:SetPoint("LEFT", detailRow.text, "RIGHT", 10, 0)
    always.bfiDep = function() return ns.IsShown("detail") end
    Tip(always, "Every zoom level", "Full detail however far out, the continents too.")
    SettingsMenu(always, "detail", "always")
    Context(always.text, { "detail" })
    Layer(a, "Your ink on the world map", "ink")
    Layer(a, "Coordinates", "coords")
    Context(a.last.text, { "coords" })

    -- what moves, switches or hides the map on its own: quick to turn off when
    -- it acts up or doesn't suit the moment
    local b = Column(quickPanel, 10 + W + 6, top.y, W)
    b:Header("Automatic")
    b:Check("Keep centred on me", "mapFrame", "center")
    SettingsMenu(b.last, "mapFrame", "center")
    b:Check("Auto-zoom", "zoom", "autoZoom")
    SettingsMenu(b.last, "zoom", "autoZoom")
    b:Tip("Zooms in near quest objectives and gathering nodes.")
    b:Check("Town view", "townView", "enabled")
    SettingsMenu(b.last, "townView", "enabled")
    b:Check("City view", "cityView", "zoom")
    SettingsMenu(b.last, "cityView", "zoom")
    b:Check("Cave view", "cave", "enabled")
    SettingsMenu(b.last, "cave", "enabled")
    b:Check("Dungeon maps", "dungeon", "fallback")
    SettingsMenu(b.last, "dungeon", "fallback")
    b:Check("Fade while I move", "fade", "moving")
    SettingsMenu(b.last, "fade", "moving")
    b:Check("Fade in combat", "fade", "combat")
    SettingsMenu(b.last, "fade", "combat")

    local bottom = math.min(a.y, b.y)
    local close = RedButton(quickPanel)
    close:SetSize(90, 22)
    close:SetPoint("TOPLEFT", 12, bottom - 6)
    close:SetText("Close")
    close:SetScript("OnClick", function() quickPanel:Hide() end)
    local more = RedButton(quickPanel)
    more:SetSize(120, 22)
    more:SetPoint("TOPRIGHT", quickPanel, "TOPLEFT", 10 + FULL, bottom - 6)
    more:SetText("Settings...")
    more:SetScript("OnClick", function()
        quickPanel:Hide()
        ns.ToggleOptions()
    end)

    quickPanel:SetSize(FULL + 20, -bottom + 40)
    quickPanel:SetScript("OnShow", function(self)
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
    { "questie",   "shown",    "cursor_quest_128",                               "Quest givers" },
    { "turnins",   "shown",    "cursor_questturnin_128",                         "Turn-ins" },
    { "spots",     "shown",    "cursor_attack_128",                              "Objective spots" },
    { "ground",    "shown",    "cursor_directions_128",                          "Quest ground" },
    { "wilds",     "shown",    "vignettekill",                                   "Rares & chests" },
    { "townsfolk", "shown",    "Interface\\Minimap\\Tracking\\Innkeeper",         "Townsfolk" },
    { "tracker",   "shown",    "poi-workorders",                                 "Quest tracker" },
    { "questMarkers", "shown", "bonus-objective-star",                           "Quest objectives (the game's)", "objectives", "The game's own" },
    -- (not "areas": that old id is cleared from toggles.list at login, BattlefieldInfo.lua)
    { "questAreas", "shown",   ns.MEDIA .. "QuestArea",                          "Quest areas (blue zones)", "areas", "The game's own" },
    { "rares",     "shown",    "vignettekillelite",                              "Rares & treasures (RareScanner)", nil, "Other addons" },
    { "gather",    "shown",    "cursor_gatherherbs_128",                         "Gathering nodes (GatherMate)", nil, "Other addons" },
    { "line",      "shown",    "minimap-questarrow",                             "Line to target" },
    { "dungeons",  "shown",    "dungeon",                                        "Dungeon entrances" },
    { "detail",    "shown",    "cursor_inspect_128",                             "Close-up detail" },
    { "detailAll", "always",   "Interface\\WorldMap\\UI-World-Icon",             "Full detail at every zoom", "detail" },
    { "zoom",      "center",   "Interface\\Minimap\\UI-Minimap-ZoomInButton-Up",  "Keep centered", "mapFrame" },  -- (id "zoom" kept for your saved order; Shift-click: auto-zoom)
    { "ink",       "shown",    "cursor_palette_128",                             "Your ink on the world map" },
    -- (not a layer: the quill taken up or put down, lit while it's in hand; Notebook.lua)
    { "quill",     "shown",    ns.MEDIA .. "Quill",                              "The quill (write and draw)", "ink" },
}
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
    if b.id == "quill" then return ns.QuillOut() end
    if not b.pairs then return ns.LayerOn(b.group, b.key) end
    for _, gk in ipairs(b.pairs) do
        if ns.LayerOn(gk[1], gk[2]) then return true end
    end
    return false
end

local function ToggleClick(b)
    if b.id == "quill" then
        if ns.QuillToggle then ns.QuillToggle() end
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
    local edge, from, side, point, dx, dy = TogglePlace(c)
    local n = 0
    local byId = {}
    for _, b in ipairs(toggleButtons) do byId[b.id] = b end
    for _, id in ipairs(ns.ToggleOrder()) do
        local b = byId[id]
        local on = c.list[id] and true or false
        b:SetShown(on)
        if on then
            StyleButton(b, c.style, size)
            b:ClearAllPoints()
            b:SetPoint(point, toggleStrip, point, n * (size + SPACING) * dx, n * (size + SPACING) * dy)
            n = n + 1
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
        items[#items + 1] = { "   only my professions", nil, nil, "myProfessionsOnly" }
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

local function BuildToggleStrip(map)
    toggleStrip = CreateFrame("Frame", nil, map)
    toggleStrip:SetFrameLevel(quickButton:GetFrameLevel())
    for _, t in ipairs(TOGGLES) do
        local b = CreateFrame("Button", nil, toggleStrip, "BackdropTemplate")
        -- (t[5]: the settings group, when it isn't the id)
        b.id, b.group, b.key, b.iconPath = t[1], t[5] or t[1], t[2], t[3]
        b.pairs = t[7]
        b.icon = b:CreateTexture(nil, "ARTWORK")
        -- (an atlas: keep its cut, StyleButton sets the coords again)
        b.iconCoords = ns.SetIconArt(b, b.icon, t[3])
        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                -- its settings: the page it lives on, the option marked
                GameTooltip:Hide()
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
            -- shift-click keep centred: auto-zoom on or off
            if b.id == "zoom" and IsShiftKeyDown() then
                ns.db.zoom.autoZoom = not ns.db.zoom.autoZoom
                ns.OnSettingChanged("zoom", "autoZoom")
                if GameTooltip:IsOwned(b) then b:GetScript("OnEnter")(b) end
                return
            end
            ToggleClick(b)
            RefreshToggles()
            if GameTooltip:IsOwned(b) then b:GetScript("OnEnter")(b) end
        end)
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(b, "ANCHOR_TOP")
            GameTooltip:AddLine(t[4])
            local key = ns.ActiveProfileKey and ns.ActiveProfileKey()
            local label = key and ns.PROFILE_LABELS and ns.PROFILE_LABELS[key]
            if b.id == "quill" then
                -- (not a layer: no profile)
            elseif b.key == "shown" and label and ns.db.toggles.saveToProfile then
                GameTooltip:AddLine("Your click is saved in the " .. label .. " profile.", 0.7, 0.7, 0.7, true)
            elseif b.key == "shown" and ns.ProfileOverrides(b.group) then
                GameTooltip:AddLine("The " .. ns.ProfileOverrides(b.group) .. " profile decides this here; your click wins until you leave it.", 0.7, 0.7, 0.7, true)
            end
            ns.Hints({ { "Click", b.id == "quill" and (ns.QuillOut() and "put it down" or "take it up") or "on or off" },
                       b.id == "townsfolk" and { "Shift-click", "filter townsfolk" } or nil,
                       b.id == "ink" and { "Shift-click", "the quill" } or nil,
                       b.id == "zoom" and { "Shift-click", "auto-zoom (" .. (ns.db.zoom.autoZoom and "on" or "off") .. ")" } or nil,
                       { "Right-click", "its settings" }, { "Hold", "move it" } })
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
        local a = alpha * ns.FrameAlpha() * cv
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
    local inv = 1 / math.max(0.1, map:GetScale())
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
    local d = ns.debugFrames
    local close = map.BorderFrame and map.BorderFrame.CloseButton
    for _, f in ipairs({ close, ns.bigMapButton, quickButton, townButton, cityButton, dockButton,
                         d.coords, d.coordsCursor, d.dockMapOnly }) do
        if f and f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
    end
    if toggleStrip then
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
                     return (ns.Docked and ns.Docked()) and "Docked over the minimap" or "Docks when the fight ends"
                 end
                 return (ns.Docked and ns.Docked()) and "Undocks when the fight ends" or "Not docked"
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
    for _, b in ipairs(toggleButtons) do ns.HoldToMove(b, "toggles", toggleStrip, stripPoint) end
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

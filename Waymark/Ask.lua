local _, ns = ...

-- Waymark's own ask box: a question, or a line to write, in Waymark's window look, for everything Waymark asks
-- (the book's words, a boss note, hiding a giver's quests, abandoning from the quest window,
-- resetting the book). Until 2026-11-10 these were the game's StaticPopup. With the gamepad UI,
-- the game's popup takes the pad's buttons while it shows, and when Waymark had opened it that
-- ran under our taint and the buttons came back broken (the same block as the world map's,
-- found the same night). This box never touches the game's popups or its binding stack: the
-- mouse, Enter and Escape, and a pad's A and B straight to the frame (EnableGamePadButton).
-- The user chose it for everyone, not only with a controller (2026-11-10).
--
-- ns.Ask({ text = "the question", sub = "a grey line under it", edit = "prefilled words" (a line
-- to write; false/nil: a plain question), maxLetters = 255, ok = "Write it", cancel = "Cancel",
-- onAccept = function(words) end, onCancel = function() end })
-- One at a time: a new one replaces the one showing (which counts as cancelled).

local FONTS = ns.MEDIA .. "Fonts\\"
local HAND = FONTS .. "Felipa-Regular.ttf"       -- the book's titles
local HAND_YOURS = FONTS .. "ReenieBeanie.ttf"   -- what you write in the book
-- (the look of Waymark's windows, "What they carry": dark brown, a pale border, light words;
-- the first try on bright parchment was too loud, the user 2026-11-10)
local WORDS = { 0.91, 0.84, 0.66 }
local GOLD = { 1, 0.82, 0 }
local SOFT = { 0.55, 0.55, 0.55 }
local EDGE = { 0.48, 0.42, 0.30 }
local WIDTH = 340

local box, current

local function Font(fs, file, size)
    if not (pcall(fs.SetFont, fs, file, size, "") and fs:GetFont()) then
        fs:SetFont("Fonts\\FRIZQT__.TTF", math.floor(size * 0.85), "")
    end
end

local function PadOn()
    return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end

local function Close(accepted)
    local o = current
    if not o then return end
    current = nil
    local words = box.edit:IsShown() and strtrim(box.edit:GetText() or "") or nil
    box.edit:ClearFocus()
    box:Hide()
    local fn = accepted and o.onAccept or (not accepted and o.onCancel)
    if fn then ns.Safe("Ask", fn, words) end
end

local function Button(parent)
    local b = CreateFrame("Button", nil, parent)
    b.label = b:CreateFontString(nil, "OVERLAY")
    Font(b.label, HAND, 15)
    b.label:SetTextColor(WORDS[1], WORDS[2], WORDS[3])
    b.label:SetPoint("CENTER")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", -6, 1)
    hl:SetPoint("BOTTOMRIGHT", 6, -1)
    hl:SetColorTexture(1, 0.82, 0, 0.12)
    b:SetHeight(22)
    function b:Set(text, pad, color)
        self.label:SetText((PadOn() and ("|cff" .. color .. pad .. "|r  ") or "") .. text)
        self:SetWidth(self.label:GetStringWidth() + 8)
    end
    return b
end

local function Make()
    local f = CreateFrame("Frame", "WaymarkAskBox", UIParent, "BackdropTemplate")
    if ns.AddonWindow then ns.AddonWindow(f) end
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.08, 0.067, 0.05, 0.96)
    f:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3])
    f:EnableMouse(true)
    f:SetWidth(WIDTH)
    f:Hide()

    f.text = f:CreateFontString(nil, "OVERLAY")
    Font(f.text, HAND, 17)
    f.text:SetTextColor(WORDS[1], WORDS[2], WORDS[3])
    f.text:SetWidth(WIDTH - 36)
    f.text:SetJustifyH("LEFT")
    f.text:SetPoint("TOPLEFT", 18, -16)

    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.sub:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
    f.sub:SetWidth(WIDTH - 36)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -5)

    local e = CreateFrame("EditBox", nil, f)
    e:SetAutoFocus(false)
    e:SetHeight(26)
    Font(e, HAND_YOURS, 22)
    e:SetTextColor(1, 1, 1)
    e:SetTextInsets(4, 4, 0, 0)
    local line = e:CreateTexture(nil, "BACKGROUND")
    line:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.8)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    local well = e:CreateTexture(nil, "BACKGROUND", nil, -1)
    well:SetAllPoints()
    well:SetColorTexture(1, 1, 1, 0.05)
    e:SetScript("OnEnterPressed", function() Close(true) end)
    e:SetScript("OnEscapePressed", function() Close(false) end)
    f.edit = e

    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.4)
    f.rule:SetHeight(1)

    f.ok = Button(f)
    f.no = Button(f)
    f.ok:SetScript("OnClick", function() Close(true) end)
    f.ok.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.no:SetScript("OnClick", function() Close(false) end)

    -- Enter and Escape without a line to write (with one, the edit box takes them). Other keys
    -- go on to the game, so you can still move; outside a fight only (passing keys on is
    -- protected in one: there the box keeps the mouse and the pad).
    f:SetScript("OnKeyDown", function(self, key)
        local mine = key == "ENTER" or key == "ESCAPE"
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(not mine) end
        if key == "ENTER" then Close(true) elseif key == "ESCAPE" then Close(false) end
    end)
    -- a pad's A and B: straight to this frame, not through the game's binding stack
    if f.EnableGamePadButton then
        f:SetScript("OnGamePadButtonDown", function(_, button)
            if button == "PAD1" then Close(true) elseif button == "PAD2" then Close(false) end
        end)
    end
    f:SetScript("OnHide", function()
        if current then Close(false) end  -- (hidden some other way: a cancel)
    end)
    return f
end

function ns.Ask(o)
    if not o then return end
    box = box or Make()
    if current then Close(false) end
    current = o
    local f = box
    -- (the menus' font, Header & border > Menus & questions: Friz reads best, a size smaller)
    local mf = ns.db and ns.db.menus and ns.db.menus.font or "friz"
    if ns.SetFontSafe then
        local big = mf == "felipa"
        ns.SetFontSafe(f.text, mf, big and 17 or 14, "")
        ns.SetFontSafe(f.ok.label, mf, big and 15 or 13, "")
        ns.SetFontSafe(f.no.label, mf, big and 15 or 13, "")
    end
    f.text:SetText(o.text or "")
    f.sub:SetText(o.sub or "")
    f.sub:SetShown(o.sub ~= nil)
    local y = 16 + f.text:GetStringHeight() + (o.sub and (5 + f.sub:GetStringHeight()) or 0)
    local writing = o.edit ~= nil and o.edit ~= false
    f.edit:SetShown(writing)
    if writing then
        f.edit:ClearAllPoints()
        f.edit:SetPoint("TOPLEFT", 18, -(y + 10))
        f.edit:SetWidth(WIDTH - 36)
        f.edit:SetMaxLetters(o.maxLetters or 255)
        f.edit:SetText(type(o.edit) == "string" and o.edit or "")
        f.edit:HighlightText()
        y = y + 10 + 26
    end
    f.rule:ClearAllPoints()
    f.rule:SetPoint("TOPLEFT", 14, -(y + 12))
    f.rule:SetWidth(WIDTH - 28)
    f.ok:Set(o.ok or OKAY or "Okay", "A", "3c8f3a")
    f.no:Set(o.cancel or CANCEL or "Cancel", "B", "b23a2e")
    f.ok:ClearAllPoints()
    f.ok:SetPoint("TOPRIGHT", f.rule, "BOTTOMRIGHT", -4, -5)
    f.no:ClearAllPoints()
    f.no:SetPoint("RIGHT", f.ok, "LEFT", -16, 0)
    f:SetHeight(y + 12 + 5 + 22 + 10)
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -135)  -- (where the game's popup stands)
    f:EnableKeyboard(not writing and not InCombatLockdown())  -- (in a fight it would eat your movement keys)
    if f.EnableGamePadButton then pcall(f.EnableGamePadButton, f, true) end
    f:Show()
    f:Raise()
    if writing then f.edit:SetFocus() end
end

function ns.AskShown() return current ~= nil end

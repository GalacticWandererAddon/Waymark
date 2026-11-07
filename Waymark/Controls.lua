local _, ns = ...
local GetMouseFocus = GetMouseFocus or ns.GetMouseFocus

-- One control scheme for every map: the Battlefield zone map, its dungeon map and the
-- notebook's maps (agreed at gate A, mockups/controls-review.md):
-- - right-click a thing: its menu, quill or no quill, whatever tool is in hand;
-- - right-click empty map: out a level, never with a modifier; with the quill out, the
--   map's own menu instead (undo, out, put the quill down), so a near miss never leaves;
-- - click a thing: its main action (a drawing tool in hand: the tool);
-- - Ctrl + drag: moves anything movable, quill or not; with the quill out, a plain drag
--   picks things up too (any tool but rub out);
-- - Shift + click: a link (quests) or your note (bosses, marks, rings);
-- - wheel: zoom; Shift + wheel: floors; Ctrl + wheel on a thing: its size.
-- The rules live here; each surface asks.

-- a press on a movable thing picks it up (Ctrl: whatever's in hand; the quill out: any
-- tool, or none, but rub out)
function ns.PicksUp()
    if IsControlKeyDown() then return true end
    if not ns.Quill then return false end
    local writing, _, tool = ns.Quill()
    return writing and tool ~= "erase" or false
end

-- the quill out (the writing bar up)
function ns.QuillOut() return ns.Quill and ns.Quill() and true or false end

-- right-click on empty map: out a level (true), the map's menu with the quill out, or
-- nothing with a modifier held. out: what "out" does here; label: its words in the menu
function ns.MapRightClick(out, label)
    if ns.QuillOut() then
        ns.MapMenu(out, label)
        return
    end
    if IsModifierKeyDown() or not out then return end
    out()
end

-- the map's own menu, with the quill out
function ns.MapMenu(out, label)
    if not ns.QuillMenu then return end
    local items = {}
    if ns.QuillCanUndo and ns.QuillCanUndo() then items[#items + 1] = { "undo", ns.QuillUndoLast } end
    if out then items[#items + 1] = { label or "out", out } end
    items[#items + 1] = { "put the quill down", function() if ns.SetQuill then ns.SetQuill(false) end end }
    ns.QuillMenu(items)
end

-- /bfi controls: a trace in chat of who gets each click (the frames under the cursor) and
-- what the handlers made of it; for finding a click that goes astray
local trace
local function Describe(f)
    if not f then return "nothing" end
    local name = f.bfiTag or (f.GetDebugName and f:GetDebugName()) or f:GetName() or tostring(f)
    local clicks = f.IsMouseClickEnabled and (f:IsMouseClickEnabled() and "" or " (no clicks)") or ""
    return name .. " @" .. (f.GetFrameLevel and f:GetFrameLevel() or "?") .. clicks
end
function ns.CTrace(...)
    if trace and trace.on then print("|cff88ccffWaymark controls:|r", ...) end
end
function ns.ToggleControlsTrace()
    if not trace then
        trace = CreateFrame("Frame")
        trace:SetScript("OnEvent", function(_, event, button)
            local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
            local list = {}
            for i = 1, math.min(3, #foci) do list[i] = Describe(foci[i]) end
            ns.CTrace(event == "GLOBAL_MOUSE_DOWN" and "down" or "up", button, "on", table.concat(list, " | "),
                      "quill:", tostring(ns.QuillOut()), "ring:", tostring(ns.FoundSpotUnder and ns.FoundSpotUnder()))
        end)
    end
    if trace:IsEventRegistered("GLOBAL_MOUSE_UP") then
        trace:UnregisterAllEvents()
        print("Waymark controls trace: off")
        trace.on = nil
    else
        trace:RegisterEvent("GLOBAL_MOUSE_DOWN")
        trace:RegisterEvent("GLOBAL_MOUSE_UP")
        print("Waymark controls trace: on (/waymark controls again: off)")
        trace.on = true
    end
end

-- Tooltip hint lines, the same words everywhere: grey, one per gesture, after the
-- tooltip's own lines, only while Shift is held (as Questie: "(Hold Shift)" in the
-- top right corner until then). hints = { { "Click", "what it does" }, ... }; an
-- entry may be nil or have no text (left out), so callers can list only what applies now.
-- Gesture words: Click, Right-click, Shift-click, Ctrl-click, Alt-click, Drag,
-- Ctrl-drag, Right-drag, Wheel, Shift-wheel, Ctrl-wheel, Middle-click, Hold.
local HINT = { 0.6, 0.6, 0.6 }
local HOLD = { 0.43, 0.43, 0.43 }

-- the tooltip Shift redraws: its owner and how (nil: the owner's own OnEnter)
local shiftOwner, shiftFn
function ns.ShiftRefresh(owner, fn) shiftOwner, shiftFn = owner, fn end

-- the tooltip's owner, or the frame it stands in for (f.bfiFor: Questie's tooltip
-- is shown for a stand-in over our pin, Pin.lua)
local function TipOwner(tip)
    local owner = tip.GetOwner and tip:GetOwner()
    return owner and owner.bfiFor or owner
end

-- "(Hold Shift)" in the tooltip's top right corner, unless something is there already
local WRAP_AT = 250  -- px: a first line wider than this wraps in the tooltip
function ns.HoldShift(tip)
    tip = tip or GameTooltip
    local right = _G[(tip:GetName() or "") .. "TextRight1"]
    if not right or tip:NumLines() < 1 or (right:IsShown() and (right:GetText() or "") ~= "") then return end
    -- a first line that wraps (a long note's text): the right side would sit over it,
    -- so a line of its own under the rest
    -- (CanWordWrap is true for a short line too: only one too long for a line counts)
    local name = tip:GetName() or ""
    local left = _G[name .. "TextLeft1"]
    local w = left and (left.GetUnboundedStringWidth and left:GetUnboundedStringWidth() or left:GetStringWidth())
    -- (live hides the width at times, in and out of fights: judged by the text's length then, about
    -- 6 px a letter, so a long note's line still gets its own row)
    if w and not ns.Known(w) then
        local text = left and ns.Known(left:GetText())
        w = text and #text * 6
    end
    if left and left.CanWordWrap and left:CanWordWrap() and w and w > WRAP_AT then
        for i = 2, tip:NumLines() do  -- (asked twice, once is enough)
            local fs = _G[name .. "TextLeft" .. i]
            if fs and fs:GetText() == "(Hold Shift)" then return end
        end
        tip:AddLine("(Hold Shift)", HOLD[1], HOLD[2], HOLD[3])
        return
    end
    right:SetText("(Hold Shift)")
    right:SetTextColor(HOLD[1], HOLD[2], HOLD[3])
    right:Show()
end

-- a tooltip's own description lines, only while Shift is held ("(Hold Shift)" till then), as the
-- hints: for buttons whose name says enough (the dungeon map's switch, the quill)
function ns.ShiftLines(owner, lines, tip)
    tip = tip or GameTooltip
    ns.ShiftRefresh(owner)
    if not IsShiftKeyDown() then ns.HoldShift(tip) return end
    for _, line in ipairs(lines) do tip:AddLine(line, 1, 1, 1, true) end
end

function ns.Hints(hints, tip)
    tip = tip or GameTooltip
    local owner = TipOwner(tip)
    if owner and owner ~= shiftOwner then ns.ShiftRefresh(owner) end
    local any = false
    for i = 1, table.maxn(hints) do
        if hints[i] and hints[i][2] then any = true break end
    end
    if not any then return end
    if not IsShiftKeyDown() then
        ns.HoldShift(tip)
        return
    end
    for i = 1, table.maxn(hints) do
        local h = hints[i]
        if h and h[2] then tip:AddLine(h[1] .. ": " .. h[2], HINT[1], HINT[2], HINT[3], true) end
    end
end

-- Shift down or up: the hovered tooltip is built again
local shiftEvents = CreateFrame("Frame")
shiftEvents:RegisterEvent("MODIFIER_STATE_CHANGED")
shiftEvents:SetScript("OnEvent", function(_, _, key)
    if not (key == "LSHIFT" or key == "RSHIFT") then return end
    local owner = shiftOwner
    if not (owner and GameTooltip:IsShown() and TipOwner(GameTooltip) == owner and owner:IsVisible() and owner:IsMouseOver()) then return end
    local fn = shiftFn or (owner.GetScript and owner:GetScript("OnEnter")) or owner.OnMouseEnter or owner.OnEnter
    if fn then pcall(fn, owner) end
end)

local addonName, ns = ...

-- Reports of blocked actions (2026-11-10). The game names only the function it blocked, and most
-- blocks reach players we can't watch (controller players: the user plays with mouse and keys).
-- So Waymark keeps a short trail of what it did in the last seconds, and when the game blocks
-- something and names Waymark, it writes a report a player can copy into a CurseForge comment:
-- what was blocked, where (fight, map, controller), the trail, and for a controller block the
-- game's values Waymark had touched (the check that found the 1.2.7 world map fix). No names.
--
-- ns.Trail(text): a line in the trail. ns.Safe's labels go in by themselves (Check.lua), the
-- map's changes and the game's pins placed in a fight from here. Each repeat of a recent line
-- counts up on that line, so a ticker doesn't push the rest out.
-- ns.NoteBlock(event, func): from BattlefieldInfo.lua's block watch, Waymark's blocks only.
-- ns.ShowReport(): the window (/waymark report, or the chat line's link).

local N = 40          -- lines kept
local SAME = 4        -- a line repeating one of the last few counts up on it
local trail, head = {}, 0

function ns.Trail(text)
    if not text then return end
    local now = GetTime()
    for k = 0, SAME - 1 do
        local e = trail[(head - k - 1) % N + 1]
        if e and e.text == text then
            e.n, e.t = e.n + 1, now
            return
        end
    end
    head = head % N + 1
    local e = trail[head]
    if not e then
        e = {}
        trail[head] = e
    end
    e.t, e.text, e.n = now, text, 1
end

-- Of note: the few things a ticker would push out of the trail within a second (a command typed,
-- a window of ours taking the keyboard, a fight, a new zone). The last 14, with who had the keyboard.
local NOTES = 14
local notes, noteHead = {}, 0
local function Keyboard()
    local f = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if not f then return "" end
    local name = f.GetName and f:GetName() or ""
    if name:find("^ChatFrame%d+EditBox") then return " (the chat box had the keyboard)" end
    if name:find("^Waymark") or name:find("^BFI") then return " (a Waymark box had the keyboard)" end
    return " (another box had the keyboard)"
end
function ns.Note(text)
    if not text then return end
    noteHead = noteHead % NOTES + 1
    local e = notes[noteHead] or {}
    notes[noteHead] = e
    e.t, e.text = GetTime(), text .. Keyboard()
    ns.Trail(text)
end
local function NoteLines(Add, t0)
    local any
    for k = 1, NOTES do
        local e = notes[(noteHead + k - 1) % NOTES + 1]
        if e and e.text then
            Add(string.format("  %+.1f  %s", e.t - t0, e.text))
            any = true
        end
    end
    if not any then Add("  nothing") end
end

-- the trail as lines, times counted from t0
local function TrailLines(Add, t0)
    for k = 1, N do
        local e = trail[(head + k - 1) % N + 1]
        if e and e.text then
            Add(string.format("  %+.1f  %s%s", e.t - t0, e.text, e.n > 1 and (" (x" .. e.n .. ")") or ""))
        end
    end
end

-- the nearest line of ours below a hook: "(Dungeon.lua:43)", or the game's own call
local MINE = "AddOns/" .. addonName .. "/"
local function Caller()
    local s = debugstack and debugstack(3, 16, 0) or ""
    for line in s:gmatch("[^\n]+") do
        local at = line:find(MINE, 1, true)
        if at then
            local file, ln = line:sub(at + #MINE):match("^([^%]:]+)%]?:(%d+)")
            if file and file ~= "Report.lua" then return " (" .. file .. ":" .. ln .. ")" end
        end
    end
    return " (the game)"
end

-- Taint check: the game's values Waymark has touched, in the tables the game's controller and
-- world map code read, and the globals we wrote that aren't our own names. At a controller block
-- only (a short hitch, once), and for /bfi padcheck before a release (DevCommands.lua).
local OWN_GLOBAL = { "^Waymark", "^BFI", "^SLASH_", "^BINDING_", "^GetMinimapShape$", "^LibStub$" }
local ROOTS = { { "WorldMapFrame", 4 }, { "QuestMapFrame", 4 }, { "QuestScrollFrame", 3 },
                { "SmartNavigation", 3 }, { "SoftCursor", 2 }, { "GameTooltip", 2 },
                { "GamepadMode", 3 }, { "GamepadSharedUtility", 3 }, { "GamepadMainActionBarFrame", 4 },
                { "GameMenuFrame", 2 }, { "QuestCache", 3 }, { "POIButtonHighlightManager", 2 },
                { "StaticPopup1", 2 }, { "UIParent", 1 }, { "EventRegistry", 3 }, { "CVarCallbackRegistry", 2 } }
function ns.TaintSweep(maxVisits, maxFound)
    if not issecurevariable then return { "(this client can't check)" } end
    maxVisits, maxFound = maxVisits or 150000, maxFound or 60
    local out, seen, visits = {}, {}, 0
    local function Walk(t, path, depth)
        if seen[t] or visits > maxVisits or #out >= maxFound then return end
        seen[t] = true
        for k, v in pairs(t) do
            visits = visits + 1
            local ok, secure, by = pcall(issecurevariable, t, k)
            if ok and not secure and by == addonName then
                -- (a table we made: its fields are all ours, and listing them hid the rest)
                out[#out + 1] = path .. "." .. tostring(k) .. (type(v) == "table" and " (and all in it)" or "")
            elseif type(v) == "table" and depth > 0 then
                Walk(v, path .. "." .. tostring(k), depth - 1)
            end
        end
    end
    for _, root in ipairs(ROOTS) do
        local t = _G[root[1]]
        if type(t) == "table" then pcall(Walk, t, root[1], root[2]) end
    end
    for k in pairs(_G) do
        if #out >= maxFound then break end
        if type(k) == "string" then
            local ok, by = issecurevariable(k)
            if not ok and by == addonName then
                local own = false
                for _, p in ipairs(OWN_GLOBAL) do if k:find(p) then own = true break end end
                if not own then out[#out + 1] = "global " .. k end
            end
        end
    end
    return out, visits
end

-- The first touch -----------------------------------------------------------------------------
-- A controller block comes long after its cause: the world map's own view values turn "ours"
-- first, and the trail at the block shows nothing of that moment (the 1.2.8 report, 2026-11-11).
-- So with the controller UI on (and always in the dev copy) those values are asked each frame,
-- five cheap questions, and the frame the first turns ours is kept with what the world map did
-- last and the trail up to then. Once: the watch ends there. Reads only, nothing of the game's
-- hooked or written.
-- Since 1.2.9's first report (2026-11-14: the world map clean, the controller's focus manager and
-- its bindings ours) those are asked too: they turn ours when the chat box loses the keyboard in
-- our code (a /waymark command typed, a window of ours taking the keyboard).
local WATCH = { "mapID", "zoomLevels", "baseScale", "targetScale", "edgePanDistance" }
local function PadWatch()
    local out
    local fcm = GamepadMode and GamepadMode.FrameControlsManager
    local ibm = GamepadSharedUtility and GamepadSharedUtility.BindingStack
        and GamepadSharedUtility.BindingStack.InputBindingManager
    for _, w in ipairs({ { fcm, "focusedFrame", "the controller's focused frame" },
                         { fcm, "fallThroughCatcherActive", "the controller's focus catcher" },
                         { ibm, "currentCoreBindingActive", "the controller's bindings" } }) do
        if type(w[1]) == "table" then
            local ok, secure, by = pcall(issecurevariable, w[1], w[2])
            if ok and not secure and by == addonName then out = (out and (out .. ", ") or "") .. w[3] end
        end
    end
    return out
end
do
    local watcher = CreateFrame("Frame")
    local started, since, on = GetTime(), 0, false
    local primed, lastMap, lastW, lastH, wasShown, mapAt, sizeAt, shownAt
    local function Ago(t, now)
        return t and string.format("%.1f s before", now - t) or "not since the watch began"
    end
    watcher:SetScript("OnUpdate", function(self, elapsed)
        if not on then
            -- (is there a reason to watch? asked every two seconds)
            since = since + elapsed
            if since < 2 then return end
            since = 0
            on = (ns.DevCommands ~= nil) or (InputUtil and InputUtil.IsGamepadUIEnabled
                and InputUtil.IsGamepadUIEnabled()) or false
            if not on then return end
        end
        local wm = WorldMapFrame
        local sc = wm and wm.ScrollContainer
        if not sc or not issecurevariable then return end
        local now = GetTime()
        local id, w, h, shown = wm.mapID, wm:GetWidth(), wm:GetHeight(), wm:IsShown()
        if primed then
            if id ~= lastMap then mapAt = now end
            if w ~= lastW or h ~= lastH then sizeAt = now end
            if shown ~= wasShown then shownAt = now end
        end
        primed, lastMap, lastW, lastH, wasShown = true, id, w, h, shown
        local found
        for _, k in ipairs(WATCH) do
            local secure, by = issecurevariable(sc, k)
            if not secure and by == addonName then found = (found and (found .. ", ") or "") .. "the world map's " .. k end
        end
        local pad = PadWatch()
        if pad then found = (found and (found .. ", ") or "") .. pad end
        if not found then return end
        self:SetScript("OnUpdate", nil)
        local L = {}
        local function Add(...) L[#L + 1] = table.concat({ ... }) end
        Add("First touched: ", found, " (", date("%H:%M:%S"), ", ",
            string.format("%.0f", now - started), " s after loading). World map ", shown and "open" or "closed",
            ", ", shown and "opened " or "closed ", Ago(shownAt, now), "; its map (", tostring(id), ") changed ",
            Ago(mapAt, now), "; its size changed ", Ago(sizeAt, now),
            InCombatLockdown() and ". In a fight" or "", ".")
        Add("Of note before that:")
        NoteLines(Add, now)
        Add("What Waymark did just before that:")
        TrailLines(Add, now)
        ns.FirstTouch = L
        WaymarkDB = WaymarkDB or {}
        WaymarkDB.firstTouch = table.concat(L, "\n")
        WaymarkDB.firstTouchWhen = date("%Y-%m-%d %H:%M")
        if ns.DevCommands and ns.Log then ns.Log("the world map's values turned ours: /waymark report") end
    end)
end

-- The first write -----------------------------------------------------------------------------
-- The watch above says when a value turned ours; this says how. The game's own functions that
-- write the controller's focus and bindings get a hooksecurefunc each, and after every call the
-- values are asked. The first call that leaves one ours is kept with its stack: the call path at
-- the marking itself, with our line in it if our code is why (2026-11-14: on a clean client with
-- a player's other addons the focused frame turned ours 32 s after loading, no block event at all).
-- Once; a hook costs a function call and three questions per focus change.
do
    local caught, already
    local function Caught(what)
        if caught or not issecurevariable then return end
        local found = PadWatch()
        if not found then return end
        caught = true
        local L = { "Marked as Waymark's: " .. found .. " (" .. date("%H:%M:%S") .. "), in the game's " .. what
            .. (already and ", but already so when the hooks went in" or "") .. ". Called from:" }
        local s = debugstack and debugstack(3, 40, 0) or ""
        for line in s:gmatch("[^\n]+") do
            if line:find("^Locals") or line:find("^%(%*temporary") then break end
            L[#L + 1] = "  " .. line:gsub("^%s+", ""):gsub("Interface/AddOns/", ""):sub(1, 150)
            if #L > 34 then break end
        end
        L[#L + 1] = "Of note before that:"
        NoteLines(function(...) L[#L + 1] = table.concat({ ... }) end, GetTime())
        ns.FirstWrite = L
        WaymarkDB = WaymarkDB or {}
        WaymarkDB.firstWrite = table.concat(L, "\n")
        if ns.DevCommands and ns.Log then ns.Log("the controller's focus was marked as ours: /waymark report") end
    end
    local function Hook(t, name, label)
        if type(t) == "table" and type(t[name]) == "function" then
            pcall(hooksecurefunc, t, name, function() Caught(label .. ":" .. name) end)
        end
    end
    local at = CreateFrame("Frame")
    at:RegisterEvent("PLAYER_LOGIN")
    at:SetScript("OnEvent", function()
        -- (dev copy only: the user, 2026-11-15, left them out of 1.3; ns.DevCommands is DevBar.lua's)
        if not (ns.DevCommands and ns.FOREVER and GamepadMode and GamepadSharedUtility and hooksecurefunc) then return end
        already = PadWatch() ~= nil
        local fcm = GamepadMode.FrameControlsManager
        for _, name in ipairs({ "FrameShown", "FrameHidden", "FocusFrame", "FocusNextFrame", "FocusPreviousFrame",
                                "FocusFirstFrameShown", "SetUIFocusState", "SetFallThroughCatcherActive",
                                "SuspendFrame", "UnsuspendFrame", "HideActiveFrames" }) do
            Hook(fcm, name, "FrameControlsManager")
        end
        local ibm = GamepadSharedUtility.BindingStack and GamepadSharedUtility.BindingStack.InputBindingManager
        for _, name in ipairs({ "AddBindingSet", "RemoveSet", "SetCoreBindingSet", "ClearBindings",
                                "AssumeCoreBindingsAreUsable" }) do
            Hook(ibm, name, "InputBindingManager")
        end
    end)
end

-- The report ---------------------------------------------------------------------------------

local function PadUI()
    return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end

local function Version()
    local A = C_AddOns or {}
    local GetMeta = A.GetAddOnMetadata or GetAddOnMetadata
    return GetMeta and GetMeta(addonName, "Version") or "dev"
end

local function OtherAddons()
    local A = C_AddOns or {}
    local Num, Info, Loaded = A.GetNumAddOns or GetNumAddOns, A.GetAddOnInfo or GetAddOnInfo,
        A.IsAddOnLoaded or IsAddOnLoaded
    local list = {}
    for i = 1, Num and Num() or 0 do
        local name = Info(i)
        if name and name ~= addonName and not name:find("^Blizzard_") and Loaded(name) then list[#list + 1] = name end
    end
    table.sort(list)
    return #list > 0 and table.concat(list, ", ") or "none"
end

-- Every block of the session stays listed, and the trail and the sweep are the first block's:
-- a later block is often our own doing (1.2.9: opening this report with the controller UI on),
-- and rebuilding from it threw the first one's evidence away.
local blocks, building = {}, false
local firstTrail, firstSweep

local function Build()
    building = false
    local L = {}
    local function Add(...) L[#L + 1] = table.concat({ ... }) end
    local ver, build, _, toc = GetBuildInfo()
    Add("Waymark report: Waymark ", Version(), ns.FOREVER and " (Forever)" or "", ", game ", tostring(ver),
        " (", tostring(build), ", ", tostring(toc), "), ", GetLocale())
    local pad = false
    for _, b in ipairs(blocks) do
        Add("Blocked: ", b.func, " (", b.event, ", ", b.combat and "in combat" or "out of combat", ", ", b.when, ")")
        if b.func:find("Gamepad", 1, true) then pad = true end
    end
    local map = BattlefieldMapFrame
    local id = map and map.GetMapID and map:GetMapID()
    local info = id and C_Map.GetMapInfo(id)
    local _, kind = IsInInstance()
    Add("Controller UI: ", PadUI() and "on" or "off",
        ". Map: ", map and map:IsShown() and "open" or "closed",
        ns.Docked and ns.Docked() and ", docked" or "", ns.MapIsBig and ns.MapIsBig() and ", big" or "",
        id and (", " .. id .. " " .. (info and info.name or "")) or "",
        ". Instance: ", tostring(kind or "none"),
        WorldMapFrame and WorldMapFrame:IsShown() and ". World map open" or "")
    Add("")
    local t0 = blocks[1] and blocks[1].t or GetTime()
    for i, b in ipairs(blocks) do
        if b.stack and #b.stack > 0 then
            Add(i == 1 and "Where the first block's call came from:" or "Where the second block's call came from:")
            for _, line in ipairs(b.stack) do Add(line) end
            Add("")
        end
    end
    Add("Of note (seconds from the first block):")
    NoteLines(Add, t0)
    Add("")
    Add("What Waymark did just before (seconds before the first block):")
    if not firstTrail then
        firstTrail = {}
        TrailLines(function(...) firstTrail[#firstTrail + 1] = table.concat({ ... }) end, t0)
    end
    for _, line in ipairs(firstTrail) do Add(line) end
    if ns.FirstTouch then
        Add("")
        for _, line in ipairs(ns.FirstTouch) do Add(line) end
    end
    if ns.FirstWrite then
        Add("")
        for _, line in ipairs(ns.FirstWrite) do Add(line) end
    end
    if pad then
        if not firstSweep then
            local found, visits = ns.TaintSweep(80000, 30)
            firstSweep = { "Game values Waymark had touched at the first controller block ("
                .. tostring(visits or 0) .. " checked):" }
            if #found == 0 then firstSweep[2] = "  none" end
            for _, f in ipairs(found) do firstSweep[#firstSweep + 1] = "  " .. f end
        end
        Add("")
        for _, line in ipairs(firstSweep) do Add(line) end
    end
    Add("")
    Add("Other addons: ", OtherAddons())
    WaymarkDB = WaymarkDB or {}
    WaymarkDB.report = table.concat(L, "\n")
    WaymarkDB.reportWhen = date("%Y-%m-%d %H:%M")
end

-- Where the blocked call came from: the game sends the block's event from inside the call it
-- blocked, so the stack here runs down through that call to whatever began it: a line of ours
-- (our code made the call happen, there and then), or only the game's own (its code ran on values
-- of ours touched earlier). Three readings of the client could not tell those apart (2026-11-14);
-- the stack can. File names and line numbers only. The first two blocks' are kept.
local function Stack()
    local s = debugstack and debugstack(2, 30, 0) or ""
    local out, all, began = {}, {}, false
    for line in s:gmatch("[^\n]+") do
        if line:find("^Locals") or line:find("^%(%*temporary") then break end
        line = line:gsub("^%s+", ""):gsub("Interface/AddOns/", "")
        all[#all + 1] = "  " .. line:sub(1, 150)
        -- (from the refused call down: what's above it is our own way here from the event. Seen in
        -- game 2026-11-14 with /waymark blocktest: two lines of the block watch, then "[C]: in
        -- function 'TargetUnit'")
        if not began and line:find("^%[C%]") then began = true end
        if began and #out < 26 then out[#out + 1] = all[#all] end
    end
    return began and out or all
end

function ns.NoteBlock(event, func)
    blocks[#blocks + 1] = { event = tostring(event), func = tostring(func), combat = InCombatLockdown(),
                            when = date("%H:%M:%S"), t = GetTime(), stack = #blocks < 2 and Stack() or nil }
    if #blocks > 8 then table.remove(blocks, 2) end  -- (the first stays: the times count from it)
    -- (next frame: our hooks run after the call the game blocked, and their lines belong in it)
    if not building then
        building = true
        C_Timer.After(0, function() ns.Safe("Report", Build) end)
    end
end

-- a chat link that opens the window: a link type of our own, where the client takes one (Forever's
-- LinkUtil.RegisterLinkHandler: the click goes to us, no tooltip); elsewhere the command to type
local LINK_TYPE = "waymarkreport"
local linkOn = false
if LinkUtil and LinkUtil.RegisterLinkHandler and not (LinkUtil.IsLinkHandlerRegistered
        and LinkUtil.IsLinkHandlerRegistered(LINK_TYPE)) then
    linkOn = pcall(LinkUtil.RegisterLinkHandler, LINK_TYPE, function()
        ns.Safe("Report window", ns.ShowReport)
    end)
end
function ns.ReportLink()
    if linkOn then return "|cff69ccf0|H" .. LINK_TYPE .. ":1|h[Copy a report]|h|r" end
    return "|cff69ccf0/waymark report|r"
end

-- The window -----------------------------------------------------------------------------------

local WORDS = { 0.91, 0.84, 0.66 }
local SOFT = { 0.55, 0.55, 0.55 }
local EDGE = { 0.48, 0.42, 0.30 }
local W, H = 470, 400
local win

local HOWTO = "The game stopped something Waymark did. To get it fixed, copy the text below and paste it "
    .. "in a comment on Waymark's CurseForge page (Waymark: Battlefield Map, the Comments tab). "
    .. "A line on what you were doing helps too."
local KEYS = "It's selected already: Ctrl+C copies it. No names in it, only what Waymark was doing."
local KEYS_PAD = "Press Select all, then Ctrl+C. No names in it, only what Waymark was doing."
local KEYS_BUSY = "|cffffd100Leave the chat box first (B or Escape), then press Select all.|r"

-- With the controller UI on, the game's chat box clears the controller's focus as it loses the
-- keyboard, and when our code took the keyboard that ran as ours: the controller's focus and
-- bindings marked, SetPreferredGamepadInteractTarget blocked from then on (floatingchatframe.lua,
-- chatframeeditbox.lua OnEditFocusLost; the 1.2.9 report). So there the window takes the keyboard
-- only when no other box has it.
local function TakeKeyboard(f)
    local e = f.edit
    local has = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if PadUI() and has and has ~= e then
        f.keys:SetText(KEYS_BUSY)
        return false
    end
    e:SetFocus()
    e:HighlightText()
    f.keys:SetText(KEYS)
    return true
end

local function Make()
    local f = CreateFrame("Frame", "WaymarkReportFrame", UIParent, "BackdropTemplate")
    if ns.AddonWindow then ns.AddonWindow(f) end
    f:SetSize(W, H)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.08, 0.067, 0.05, 0.96)
    f:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3])
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetPoint("CENTER", 0, 60)
    f:Hide()
    tinsert(UISpecialFrames, "WaymarkReportFrame")  -- (Escape closes it)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -11)
    f.title:SetText("Report a blocked action")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -3)

    f.howto = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.howto:SetTextColor(WORDS[1], WORDS[2], WORDS[3])
    f.howto:SetJustifyH("LEFT")
    f.howto:SetWidth(W - 26)
    f.howto:SetPoint("TOPLEFT", 13, -34)
    f.howto:SetText(HOWTO)

    f.keys = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.keys:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
    f.keys:SetJustifyH("LEFT")
    f.keys:SetWidth(W - 26)
    f.keys:SetPoint("TOPLEFT", f.howto, "BOTTOMLEFT", 0, -6)
    f.keys:SetText(KEYS)

    -- the text, in a dark well
    local well = CreateFrame("Frame", nil, f, "BackdropTemplate")
    well:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    well:SetBackdropColor(0, 0, 0, 0.35)
    well:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], 0.5)
    well:SetPoint("TOPLEFT", f.keys, "BOTTOMLEFT", -2, -8)
    well:SetPoint("BOTTOMRIGHT", -12, 40)

    local sc = CreateFrame("ScrollFrame", nil, well, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 6, -6)
    sc:SetPoint("BOTTOMRIGHT", -26, 6)
    local e = CreateFrame("EditBox", nil, sc)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(GameFontHighlightSmall)
    e:SetTextColor(0.85, 0.85, 0.85)
    e:SetWidth(W - 70)
    e:SetScript("OnEscapePressed", function() f:Hide() end)
    e:SetScript("OnCursorChanged", function(self, _, y, _, h)
        -- (keep the cursor in sight while it moves)
        local top, view = sc:GetVerticalScroll(), sc:GetHeight()
        y = -y
        if y < top then sc:SetVerticalScroll(y) elseif y + h > top + view then sc:SetVerticalScroll(y + h - view) end
    end)
    sc:SetScrollChild(e)
    f.edit = e
    -- (a click anywhere in the well: into the text)
    well:EnableMouse(true)
    well:SetScript("OnMouseDown", function() TakeKeyboard(f) end)

    local function Button(label, gold)
        local b = CreateFrame("Button", nil, f)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.label:SetPoint("CENTER")
        b.label:SetText(label)
        if gold then b.label:SetTextColor(1, 0.82, 0) else b.label:SetTextColor(WORDS[1], WORDS[2], WORDS[3]) end
        b:SetSize(b.label:GetStringWidth() + 16, 22)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.12)
        return b
    end
    f.select = Button("Select all", true)
    f.select:SetPoint("BOTTOMRIGHT", -14, 12)
    f.select:SetScript("OnClick", function() TakeKeyboard(f) end)
    f.done = Button("Close")
    f.done:SetPoint("RIGHT", f.select, "LEFT", -12, 0)
    f.done:SetScript("OnClick", function() f:Hide() end)
    f.when = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.when:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
    f.when:SetPoint("BOTTOMLEFT", 14, 17)
    return f
end

function ns.ShowReport()
    local text = WaymarkDB and WaymarkDB.report
    -- (nothing blocked, but the first touch seen this session: that alone)
    if not text and (ns.FirstWrite or ns.FirstTouch) then
        text = (ns.FirstWrite and (table.concat(ns.FirstWrite, "\n") .. "\n\n") or "")
            .. (ns.FirstTouch and table.concat(ns.FirstTouch, "\n") or "")
    end
    if not text then
        print("|cff33ff99Waymark:|r nothing has been blocked yet, so there's no report.")
        return
    end
    win = win or Make()
    if ns.SetFontSafe and ns.db and ns.db.menus then
        local mf = ns.db.menus.font or "friz"
        ns.SetFontSafe(win.howto, mf, mf == "felipa" and 15 or 12, "")
    end
    win.edit:SetText(text)
    win.when:SetText(WaymarkDB.reportWhen and ("From " .. WaymarkDB.reportWhen) or "")
    win:Show()
    win:Raise()
    win.edit:SetCursorPosition(0)
    if PadUI() then
        win.keys:SetText(KEYS_PAD)
        ns.Note("report window opened, keyboard left alone")
    else
        TakeKeyboard(win)
        ns.Note("report window opened")
    end
end

-- Hooks ------------------------------------------------------------------------------------------

do
    local ev = CreateFrame("Frame")
    local SAY = { PLAYER_REGEN_DISABLED = "a fight starts", PLAYER_REGEN_ENABLED = "the fight ends",
                  PLAYER_ENTERING_WORLD = "a loading screen ends", ZONE_CHANGED_NEW_AREA = "a new zone",
                  ZONE_CHANGED_INDOORS = "indoors/outdoors", PLAYER_DEAD = "you died" }
    for e in pairs(SAY) do ev:RegisterEvent(e) end
    ev:SetScript("OnEvent", function(_, e) ns.Note(SAY[e]) end)
end

-- On our map (BattlefieldInfo.lua Setup): its changes, its showing, and in a fight the game's own
-- pins placed (each sets pass-through, which the game blocks in a fight when our code is the cause)
function ns.SetupReport(map)
    hooksecurefunc(map, "SetMapID", function(_, id)
        ns.Trail("map to " .. tostring(id) .. Caller())
    end)
    hooksecurefunc(map, "AcquirePin", function(_, template)
        if InCombatLockdown() and type(template) == "string" and not template:find("^BFI") then
            ns.Trail("in a fight, game pin " .. template .. Caller())
        end
    end)
    map:HookScript("OnShow", function() ns.Trail("map opened") end)
    map:HookScript("OnHide", function() ns.Trail("map closed") end)
end

local _, ns = ...

-- Before you go (the Lab; the user, 2026-11-19: "Show me what you've got on this"). Everyone has flown out of a
-- zone with a finished quest still in the bag, or one count short of done. The log knows; it never says so at
-- the one moment it matters. This does: a small dark slip, at most three lines, while a flight master's map is
-- open, and for the length of a hearthstone's cast. Nothing to say: no slip. Nothing to click.
--   1. a quest that is ready and handed in in the zone you stand in: who takes it
--   2. a quest whose ground is here and that is nearly done: how many short
--   3. a loose end here that you can take now: who has it
-- It leans on a rule (the addon does not tell you what to do): it speaks only of what you already hold, in
-- the zone you stand in, and says nothing otherwise. The user's to judge. Its name is the book's own
-- ("Before we go"). The slip is ours and touches nothing of the game's flight map. Part of Lab\WorldLog.lua's
-- settings: `before` (/worldlog before). Notes: mockups\world-map-level3-notes.md.

local W = ns.WorldLog
local FRIZ = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local HEARTH = { [8690] = true }
local MAX = 3
local slip

local function Lines()
    local out = {}
    if not (W and W.Ready()) then return out end
    local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zone = here and W.ZoneMap(here)
    if not zone then return out end
    local g = W.Groups(zone)
    for _, h in ipairs(g.ready) do
        if #out < MAX and h.toHere ~= false then
            out[#out + 1] = { ("|cffffd100%s|r is ready%s."):format(h.name, h.to and (": " .. h.to) or "") }
        end
    end
    for _, group in ipairs(g.groups) do
        for _, h in ipairs(group.quests) do
            -- (nearly done: three or fewer short, and most of the way there)
            if #out < MAX and h.short and h.short > 0 and h.short <= 3 and h.most and h.most > 0 and h.short / h.most <= 0.34 then
                out[#out + 1] = { ("%s: %d short."):format(h.name, h.short) }
            end
        end
    end
    if W.Cfg().loose then
        for _, e in ipairs(W.LooseOn(zone)) do
            if #out < MAX and e.kind == "chain" and not e.tooHigh and not e.grey and e.who then
                out[#out + 1] = { ("%s has the next step of a quest chain."):format(e.who) }
                break
            end
        end
    end
    return out
end
-- (for the panel's own use and the dry run)
function ns.BeforeYouGoLines() return Lines() end

local function Make()
    slip = CreateFrame("Frame", "WaymarkBeforeYouGo", UIParent)
    slip:SetFrameStrata("HIGH")
    slip:SetWidth(270)
    slip:Hide()
    -- As told's own glass (AsToldPanel.lua): dark, full under the words, fading out beyond them at the right, a little
    -- at the left and the bottom, the gold rule its top edge fading with it at both ends. The user, 2026-11-22: "It
    -- looks like as-told panel, but not quite. It has hard backing edges, not feathered". Hard edges where the client
    -- has no gradient call
    local GR, GG, GB, GA = 0.055, 0.06, 0.07, 0.78
    local GOLD = { 0.73, 0.55, 0.32 }
    local EDGE, SOFT_L, SOFT_B, ROWS = 18, 10, 8, 4
    local function Piece(layer)
        local t = slip:CreateTexture(nil, layer or "BACKGROUND")
        t:SetColorTexture(1, 1, 1, 1)
        return t
    end
    local function Grad(t, way, r, g, b, a, z)
        local ok
        if t.SetGradient and CreateColor then ok = pcall(t.SetGradient, t, way, CreateColor(r, g, b, a), CreateColor(r, g, b, z)) end
        if not ok and t.SetGradientAlpha then ok = pcall(t.SetGradientAlpha, t, way, r, g, b, a, r, g, b, z) end
        return ok
    end
    local back = Piece()
    back:SetAllPoints()
    back:SetColorTexture(GR, GG, GB, GA)
    local rule = Piece("BORDER")
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
    local right = Piece()
    right:SetPoint("TOPLEFT", slip, "TOPRIGHT")
    right:SetPoint("BOTTOMLEFT", slip, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(EDGE)
    if Grad(right, "HORIZONTAL", GR, GG, GB, GA, 0) then
        local left = Piece()
        left:SetPoint("TOPRIGHT", slip, "TOPLEFT")
        left:SetPoint("BOTTOMRIGHT", slip, "BOTTOMLEFT")
        left:SetWidth(SOFT_L)
        Grad(left, "HORIZONTAL", GR, GG, GB, 0, GA)
        local under = Piece()
        under:SetPoint("TOPLEFT", slip, "BOTTOMLEFT")
        under:SetPoint("TOPRIGHT", slip, "BOTTOMRIGHT")
        under:SetHeight(SOFT_B)
        Grad(under, "VERTICAL", GR, GG, GB, 0, GA)
        local step = SOFT_B / ROWS
        for i = 0, ROWS - 1 do
            local a = GA * (1 - (i + 0.5) / ROWS)
            local l = Piece()
            l:SetSize(SOFT_L, step)
            l:SetPoint("TOPRIGHT", slip, "BOTTOMLEFT", 0, -i * step)
            Grad(l, "HORIZONTAL", GR, GG, GB, 0, a)
            local r = Piece()
            r:SetSize(EDGE, step)
            r:SetPoint("TOPLEFT", slip, "BOTTOMRIGHT", 0, -i * step)
            Grad(r, "HORIZONTAL", GR, GG, GB, a, 0)
        end
        local ruleL = Piece("BORDER")
        ruleL:SetSize(SOFT_L, 1)
        ruleL:SetPoint("TOPRIGHT", slip, "TOPLEFT")
        Grad(ruleL, "HORIZONTAL", GOLD[1], GOLD[2], GOLD[3], 0, 0.95)
        local ruleR = Piece("BORDER")
        ruleR:SetSize(EDGE, 1)
        ruleR:SetPoint("TOPLEFT", slip, "TOPRIGHT")
        Grad(ruleR, "HORIZONTAL", GOLD[1], GOLD[2], GOLD[3], 0.95, 0)
    else
        right:SetColorTexture(GR, GG, GB, GA)
    end
    slip.title = slip:CreateFontString(nil, "OVERLAY")
    slip.title:SetFont(FRIZ, 10.5, "")
    slip.title:SetPoint("TOPLEFT", 12, -9)
    slip.title:SetTextColor(0.73, 0.55, 0.32)
    slip.title:SetText("BEFORE YOU GO")
    slip.text = {}
    for i = 1, MAX do
        local fs = slip:CreateFontString(nil, "OVERLAY")
        fs:SetFont(FRIZ, 12.5, "")
        fs:SetJustifyH("LEFT")
        fs:SetWidth(246)
        fs:SetTextColor(0.92, 0.90, 0.85)
        slip.text[i] = fs
    end
end

local function Show(anchor, forSeconds)
    -- (only with the world map picked: it is the world map's, and its switch is in the world map's panel)
    if not (ns.db and ns.db.worldLog and W and W.Cfg().before and ns.MapKind and ns.MapKind() == "world") then return end
    local ok, lines = pcall(Lines)
    if not ok or #lines == 0 then
        if slip then slip:Hide() end
        return
    end
    if not slip then Make() end
    local y = 26
    for i, fs in ipairs(slip.text) do
        local l = lines[i]
        fs:SetShown(l ~= nil)
        if l then
            fs:SetText(l[1])
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 12, -y)
            y = y + fs:GetStringHeight() + 6
        end
    end
    slip:SetHeight(y + 6)
    slip:ClearAllPoints()
    if anchor and anchor.IsShown and anchor:IsShown() then
        slip:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, -20)
    else
        slip:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230)
    end
    slip:Show()
    slip.until_ = forSeconds and (GetTime() + forSeconds) or nil
    if forSeconds and C_Timer and ns.BeforeYouGoTimeOut then C_Timer.After(forSeconds + 0.05, ns.BeforeYouGoTimeOut) end
end

local function Hide()
    if slip then slip:Hide() end
end

local f = CreateFrame("Frame")
-- (the casts the player's own only, not every unit's in a city: the code critic, 2026-11-22)
for _, e in ipairs({ "TAXIMAP_OPENED", "TAXIMAP_CLOSED" }) do pcall(f.RegisterEvent, f, e) end
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED" }) do
    if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, e, "player") else pcall(f.RegisterEvent, f, e) end
end
f:SetScript("OnEvent", function(_, event, unit, _, spell)
    if event == "TAXIMAP_OPENED" then
        ns.Safe("Before you go", Show, FlightMapFrame and FlightMapFrame:IsShown() and FlightMapFrame or TaxiFrame)
    elseif event == "TAXIMAP_CLOSED" then
        Hide()
    elseif unit == "player" and HEARTH[spell or 0] then
        if event == "UNIT_SPELLCAST_START" then ns.Safe("Before you go", Show, nil, 10.5) else Hide() end
    end
end)
-- (its timeout a timer, not a check every frame for every player: the code critic, 2026-11-22)
local function TimeOut()
    if slip and slip:IsShown() and slip.until_ then
        if GetTime() >= slip.until_ then Hide() else C_Timer.After(slip.until_ - GetTime() + 0.05, TimeOut) end
    end
end
ns.BeforeYouGoTimeOut = TimeOut

-- /beforeyougo: the slip as it would say now, for a look (ten seconds)
SLASH_WAYMARKBEFORE1 = "/beforeyougo"
SlashCmdList.WAYMARKBEFORE = function()
    if not ns.DevCommands then return end   -- (a dev's look only: players have the slip itself)
    local ok, lines = pcall(Lines)
    if ok and #lines == 0 then print("|cffc79a52Waymark|r: before you go: nothing to say here.") return end
    ns.Safe("Before you go", Show, nil, 10)
end

local _, ns = ...

-- Saved setups: snapshots of all your settings under a name (ns.db.setups), to
-- switch between, to link to a character (loaded when it logs in, and optionally
-- saved back when it logs out), and to share as a text string.
-- The string is "BFI1:" and the settings written out as a plain table. It's read
-- back by our own small reader, never run as code.

local PREFIX = "BFI1:"

-- not part of a setup: per-run and learned data, and the setups themselves
local EXCLUDE = { setups = true, dungeonRun = true, blockedLog = true, towns = true,
                  diag = true, lastErrors = true,  -- (/bfi check's results)
                  devArtOff = true }  -- (/bfi devart, Art.lua)

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Snapshot()
    local s = {}
    for k, v in pairs(ns.db) do
        if not EXCLUDE[k] then s[k] = Copy(v) end
    end
    return s
end

-- Applying -----------------------------------------------------------------

-- every part of the addon takes its settings afresh
function ns.ApplyAll()
    pcall(ns.ShareQuestLook)
    for _, ch in ipairs({
        { nil, "scale" }, { "questie", "shown" }, { "waypoints", "shown" }, { "rares", "shown" },
        { "townsfolk", "shown" }, { "mapFrame" }, { "zoom" }, { "detail" }, { "line" },
        { "gather", "shown" }, { "dungeon" }, { "zoneName" }, { "cave" }, { "profiles" },
        { "explore" }, { "border" }, { "learned", "shown" }, { "dungeons", "shown" }, { "toggles" }, { "party", "classColors" },
    }) do
        pcall(ns.OnSettingChanged, ch[1], ch[2])
    end
    for _, g in ipairs({ "questie", "turnins", "spots", "objectives", "townsfolk", "rares", "gather" }) do
        pcall(ns.ApplyScales, g)
    end
    pcall(ns.RedrawAll)
end

local function Apply(s)
    for k in pairs(ns.db) do
        if not EXCLUDE[k] then ns.db[k] = nil end
    end
    for k, v in pairs(s) do
        if not EXCLUDE[k] then ns.db[k] = Copy(v) end
    end
    ns.CopyDefaults(ns.db, ns.DEFAULTS)
    ns.keepSizeOff = true  -- (its scale and its sizes as saved: ns.SetScale)
    pcall(ns.ApplyAll)
    ns.keepSizeOff = nil
end

-- Named setups ------------------------------------------------------------------

function ns.SetupNames()
    local names = {}
    for name in pairs(ns.db.setups) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function ns.SaveSetup(name)
    name = name and strtrim(name) or ""
    if name == "" then return false end
    ns.db.setups[name] = Snapshot()
    return true
end

function ns.LoadSetup(name)
    local s = ns.db.setups[name]
    if not s then return false end
    Apply(s)
    ns.lastSetup = name
    ns.Log("Loaded setup \"" .. name .. "\".")
    return true
end

function ns.DeleteSetup(name)
    ns.db.setups[name] = nil
    local c = BattlefieldInfoCharDB
    if c and c.setup == name then c.setup = nil end
end

-- the next one after the last loaded (for the key binding)
function ns.NextSetup()
    local names = ns.SetupNames()
    if #names == 0 then
        ns.Log("No saved setups yet: save one on the Setups page.")
        return
    end
    local i = 0
    for j, n in ipairs(names) do
        if n == ns.lastSetup then i = j end
    end
    ns.LoadSetup(names[i % #names + 1])
end

-- Writing and reading the text -----------------------------------------------------

local function Escape(s)
    return (s:gsub("[%c\"\\]", function(c)
        if c == "\n" then return "\\n" end
        if c == "\"" or c == "\\" then return "\\" .. c end
        return string.format("\\%03d", c:byte())
    end))
end

local function Write(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local val = v[k]
            local tv = type(val)
            if tv == "table" or tv == "string" or tv == "number" or tv == "boolean" then
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    out[#out + 1] = k .. "="
                elseif type(k) == "string" then
                    out[#out + 1] = "[\"" .. Escape(k) .. "\"]="
                else
                    out[#out + 1] = "[" .. tostring(k) .. "]="
                end
                Write(val, out)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = "\"" .. Escape(v) .. "\""
    elseif t == "number" then
        out[#out + 1] = (v == math.floor(v)) and string.format("%d", v) or string.format("%.4f", v):gsub("0+$", "")
    else
        out[#out + 1] = tostring(v)
    end
end

-- A reader for exactly what Write makes: tables, strings, numbers, true/false
local function Read(text)
    local pos, depth = 1, 0
    local function fail(msg) error({ bfi = msg .. " (at " .. pos .. ")" }) end
    local function skip() pos = text:find("[^%s]", pos) or (#text + 1) end
    local value
    local function str()
        pos = pos + 1
        local buf = {}
        while true do
            local c = text:sub(pos, pos)
            if c == "" then fail("unfinished text") end
            if c == "\"" then pos = pos + 1 break end
            if c == "\\" then
                local n = text:sub(pos + 1, pos + 1)
                if n == "n" then buf[#buf + 1] = "\n" pos = pos + 2
                elseif n == "\"" or n == "\\" then buf[#buf + 1] = n pos = pos + 2
                elseif n:match("%d") then
                    local d = text:match("^%d%d?%d?", pos + 1)
                    buf[#buf + 1] = string.char(tonumber(d) % 256)
                    pos = pos + 1 + #d
                else fail("bad escape") end
            else
                buf[#buf + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(buf)
    end
    local function tbl()
        depth = depth + 1
        if depth > 20 then fail("too deep") end
        pos = pos + 1
        local t = {}
        while true do
            skip()
            local c = text:sub(pos, pos)
            if c == "}" then pos = pos + 1 break end
            local key
            if c == "[" then
                pos = pos + 1
                skip()
                key = value()
                skip()
                if text:sub(pos, pos) ~= "]" then fail("expected ]") end
                pos = pos + 1
            else
                key = text:match("^[%a_][%w_]*", pos)
                if not key then fail("expected a name") end
                pos = pos + #key
            end
            skip()
            if text:sub(pos, pos) ~= "=" then fail("expected =") end
            pos = pos + 1
            skip()
            t[key] = value()
            skip()
            if text:sub(pos, pos) == "," then pos = pos + 1 end
        end
        depth = depth - 1
        return t
    end
    value = function()
        skip()
        local c = text:sub(pos, pos)
        if c == "{" then return tbl() end
        if c == "\"" then return str() end
        if text:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
        if text:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
        local num = text:match("^%-?%d+%.?%d*", pos)
        if num then
            pos = pos + #num
            return tonumber(num)
        end
        fail("unexpected \"" .. c .. "\"")
    end
    local ok, result = pcall(value)
    if not ok then return nil, type(result) == "table" and result.bfi or tostring(result) end
    return result
end

function ns.ExportString(name)
    local s = name and ns.db.setups[name] or Snapshot()
    local out = {}
    Write(s, out)
    return PREFIX .. table.concat(out)
end

-- the settings in an export string, or nil and why not
function ns.ParseExport(text)
    text = text and strtrim(text) or ""
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, "not a Battlefield Info setup (it starts with " .. PREFIX .. ")" end
    local s, err = Read(text:sub(#PREFIX + 1))
    if type(s) ~= "table" then return nil, err or "unreadable" end
    -- only the settings groups this version knows
    for k in pairs(s) do
        if EXCLUDE[k] or ns.DEFAULTS[k] == nil then s[k] = nil end
    end
    return s
end

function ns.ImportString(text, saveAs)
    local s, err = ns.ParseExport(text)
    if not s then return false, err end
    if saveAs and strtrim(saveAs) ~= "" then
        ns.db.setups[strtrim(saveAs)] = s
    else
        Apply(s)
    end
    return true
end

-- Per character --------------------------------------------------------------------

-- BattlefieldInfoCharDB (per character): setup = the name it uses, autoSave = save
-- your changes back into it when you log out
function ns.CharSetup()
    BattlefieldInfoCharDB = BattlefieldInfoCharDB or {}
    return BattlefieldInfoCharDB
end

function ns.SetupSetups()
    local c = ns.CharSetup()
    if c.setup and ns.db.setups[c.setup] then
        Apply(ns.db.setups[c.setup])
        ns.lastSetup = c.setup
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function()
        if c.setup and c.autoSave and ns.db.setups[c.setup] then
            ns.db.setups[c.setup] = Snapshot()
        end
    end)
end

-- Export / import window ----------------------------------------------------------------

local win, box, nameBox, status

local function BuildWindow()
    win = CreateFrame("Frame", "BattlefieldInfoShare", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(460, 300)
    win:SetPoint("CENTER")
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "BattlefieldInfoShare")
    if win.TitleText then win.TitleText:SetText("Share a setup") end

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 76)
    box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontSmall or GameFontHighlightSmall)
    box:SetWidth(400)
    box:SetScript("OnEscapePressed", function() win:Hide() end)
    scroll:SetScrollChild(box)

    status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 16, 58)
    status:SetPoint("BOTTOMRIGHT", -16, 58)
    status:SetJustifyH("LEFT")

    local apply = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    apply:SetSize(130, 22)
    apply:SetPoint("BOTTOMLEFT", 14, 28)
    apply:SetText("Import and use")
    apply:SetScript("OnClick", function()
        local ok, err = ns.ImportString(box:GetText())
        status:SetText(ok and "|cff33ff33Imported: these settings are now in use.|r" or ("|cffff5555" .. err .. "|r"))
        if ok then ns.RefreshControls() end
    end)

    nameBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    nameBox:SetSize(130, 20)
    nameBox:SetPoint("LEFT", apply, "RIGHT", 16, 0)
    nameBox:SetAutoFocus(false)
    local save = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    save:SetSize(130, 22)
    save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    save:SetText("Import as setup")
    save:SetScript("OnClick", function()
        local name = strtrim(nameBox:GetText() or "")
        if name == "" then status:SetText("|cffff5555Type a name for it first.|r") return end
        local ok, err = ns.ImportString(box:GetText(), name)
        status:SetText(ok and ("|cff33ff33Saved as \"" .. name .. "\" (not in use yet: load it on the Setups page).|r")
                           or ("|cffff5555" .. err .. "|r"))
        if ok then ns.RefreshControls() end
    end)

    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 10)
    hint:SetText("Ctrl+A, Ctrl+C to copy. Paste someone's string and import it.")
    win:Hide()
end

-- name: export that saved setup (nil: what's in use now); import = open empty
function ns.ShowShare(name, import)
    if not win then BuildWindow() end
    status:SetText("")
    if import then
        box:SetText("")
        status:SetText("Paste a setup string above.")
    else
        box:SetText(ns.ExportString(name))
        box:HighlightText()
        status:SetText(name and ("Setup \"" .. name .. "\"") or "Your settings as they are now")
    end
    win:Show()
    box:SetFocus()
end

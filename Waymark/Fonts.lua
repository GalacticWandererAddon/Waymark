local _, ns = ...

-- The fonts our font settings offer, one list for all of them (the zone
-- header, the tracker's titles and objectives, the quest window's titles).
--
-- A setting holds a key: one of the game's fonts below, or "lsm:<name>" for a
-- font another addon registered with LibSharedMedia-3.0. We use that library
-- only when some other addon has loaded it; it isn't shipped here.
-- A font that can't be had (an addon's that's gone, one this client lacks)
-- falls back to Morpheus, the addon's own default, then to Friz Quadrata.

ns.FONT_DEFAULT = "morpheus"
local FRIZ = "Fonts\\FRIZQT__.TTF"
local MORPHEUS, SKURRI, ARIALN = "Fonts\\MORPHEUS.ttf", "Fonts\\skurri.ttf", "Fonts\\ARIALN.TTF"
local PAGETEXT, DAMAGE = "Fonts\\K_Pagetext.TTF", "Fonts\\K_Damage.TTF"
local FELIPA = ns.MEDIA .. "Fonts\\Felipa-Regular.ttf"

-- A client in another script. The files above hold Latin letters only, so on a
-- Russian client a zone's or a quest's name came out as a row of empty squares
-- (GitHub issue 2, 2026-11-18). There the game ships its own Cyrillic cuts of
-- the same faces; each is tried on a hidden line first, and one that will not
-- load gives way to the client's own text font (STANDARD_TEXT_FONT), which
-- always has the client's letters. Korean and Chinese clients: that font for
-- every face. Fonts another addon shares are left as the player picked them.
local LOCALE = GetLocale and GetLocale() or "enUS"
local OWN = STANDARD_TEXT_FONT
local probe
local function Loads(path)
    if not (CreateFrame and UIParent) then return false end
    probe = probe or CreateFrame("Frame"):CreateFontString()
    if not pcall(probe.SetFont, probe, path, 12, "") then return false end
    local now = probe:GetFont()
    return now ~= nil and now:lower() == path:lower()
end
local function Cut(path) return Loads(path) and path or OWN end
if LOCALE == "ruRU" and OWN then
    FRIZ = OWN
    MORPHEUS = Cut("Fonts\\MORPHEUS_CYR.TTF")
    SKURRI = Cut("Fonts\\SKURRI_CYR.TTF")
    PAGETEXT, DAMAGE, FELIPA = OWN, OWN, MORPHEUS   -- (no Cyrillic in these three)
elseif (LOCALE == "koKR" or LOCALE == "zhCN" or LOCALE == "zhTW") and OWN then
    FRIZ, MORPHEUS, SKURRI, ARIALN, PAGETEXT, DAMAGE, FELIPA = OWN, OWN, OWN, OWN, OWN, OWN, OWN
end
-- for the files that set one of the game's faces by name (Tracker.lua, ZoneName.lua)
ns.FONT_FRIZ, ns.FONT_MORPHEUS, ns.FONT_ARIALN = FRIZ, MORPHEUS, ARIALN

-- (key, name in the list, file)
local GAME = {
    { "morpheus", "Morpheus", MORPHEUS },   -- the classic zone and quest title font
    { "friz", "Friz Quadrata", FRIZ },
    { "skurri", "Skurri", SKURRI },
    { "arial", "Arial Narrow", ARIALN },
    { "2002", "2002", "Fonts\\2002.ttf" },
    { "2002b", "2002 Bold", "Fonts\\2002B.ttf" },
    { "pagetext", "Page text", PAGETEXT },
    { "damage", "Damage numbers", DAMAGE },
    { "nimrod", "Nimrod", "Fonts\\NIM_____.ttf" },
    -- (Waymark's own: the book's title hand, the menus' font until 2026-11-10)
    { "felipa", "Felipa (the book's hand)", FELIPA },
}
ns.FONTS = {}
for _, f in ipairs(GAME) do ns.FONTS[f[1]] = f[3] end

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- the file for a setting's key (nil key: the default)
function ns.FontFile(key)
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local lsm = LSM()
        local path = lsm and lsm:Fetch("font", key:sub(5), true)
        if path then return path end
    end
    return ns.FONTS[key] or ns.FONTS[ns.FONT_DEFAULT]
end

-- SetFont with the fallbacks. (A file the client can't load leaves the old
-- font set, so it's checked by the path GetFont gives back.)
local function Try(fs, path, size, flags)
    if not pcall(fs.SetFont, fs, path, size, flags) then return false end
    local now = fs:GetFont()
    return now ~= nil and now:lower() == path:lower()
end
function ns.SetFontSafe(fs, key, size, flags)
    flags = flags or ""
    if Try(fs, ns.FontFile(key), size, flags) then return end
    if Try(fs, ns.FONTS[ns.FONT_DEFAULT], size, flags) then return end
    fs:SetFont(FRIZ, size, flags)
end

-- the choices for a font dropdown: { key, name, file }, the game's first, then
-- SharedMedia's (by name; ones that are the game's own files left out)
function ns.FontChoices()
    local out, seen = {}, {}
    for _, f in ipairs(GAME) do
        out[#out + 1] = { f[1], f[2], f[3] }
        seen[f[3]:lower()] = true
    end
    local lsm = LSM()
    if lsm then
        local names = lsm:List("font") or {}
        local sorted = {}
        for _, name in ipairs(names) do sorted[#sorted + 1] = name end
        table.sort(sorted, function(a, b) return a:lower() < b:lower() end)
        for _, name in ipairs(sorted) do
            local path = lsm:Fetch("font", name, true)
            if type(path) == "string" and not seen[path:lower()] then
                seen[path:lower()] = true
                out[#out + 1] = { "lsm:" .. name, name, path }
            end
        end
    end
    return out
end

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

-- (key, name in the list, file)
local GAME = {
    { "morpheus", "Morpheus", "Fonts\\MORPHEUS.ttf" },   -- the classic zone and quest title font
    { "friz", "Friz Quadrata", FRIZ },
    { "skurri", "Skurri", "Fonts\\skurri.ttf" },
    { "arial", "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "2002", "2002", "Fonts\\2002.ttf" },
    { "2002b", "2002 Bold", "Fonts\\2002B.ttf" },
    { "pagetext", "Page text", "Fonts\\K_Pagetext.TTF" },
    { "damage", "Damage numbers", "Fonts\\K_Damage.TTF" },
    { "nimrod", "Nimrod", "Fonts\\NIM_____.ttf" },
    -- (Waymark's own: the book's title hand, the menus' font until 2026-11-10)
    { "felipa", "Felipa (the book's hand)", ns.MEDIA .. "Fonts\\Felipa-Regular.ttf" },
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

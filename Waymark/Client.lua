local addonName, ns = ...

-- Which client this is. The addon is made for WoW Forever (1.60, interface 16001);
-- Classic Era (1.15) and Anniversary (2.5) only stand in for it while its servers
-- are down. Fixes for a stand-in go behind `if not ns.FOREVER`, so Forever keeps
-- its own behaviour.
local interface = select(4, GetBuildInfo()) or 0
ns.INTERFACE = interface
ns.FOREVER = interface >= 16000 and interface < 20000
ns.CLASSIC_ERA = interface >= 11500 and interface < 12000
ns.CLIENT = ns.FOREVER and "forever" or ns.CLASSIC_ERA and "classic era" or "other"

-- Live Forever hides some unit values as "secret": comparing one, testing it or using it
-- as a table key errors. This gives nil instead, so a caller treats it as not known.
function ns.Known(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Calls live Forever took away from the globals. Each file that uses one starts with
-- `local GetItemInfo = GetItemInfo or ns.GetItemInfo`. (Not put back as globals: that
-- would be ours in the game's own code. /waymark check lists any other that goes.)
ns.GetItemInfo = C_Item and C_Item.GetItemInfo
ns.GetItemIcon = C_Item and C_Item.GetItemIconByID
ns.GetItemQualityColor = C_Item and C_Item.GetItemQualityColor
function ns.GetSpellInfo(id)
    local i = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    if i then return i.name, nil, i.iconID, i.castTime, i.minRange, i.maxRange, i.spellID end
end
ns.GetNumSkillLines = C_SkillInfo and C_SkillInfo.GetNumSkillLines
function ns.GetSkillLineInfo(index)
    local i = C_SkillInfo and C_SkillInfo.GetSkillLineInfo(index)
    if i then return i.name, i.isHeader, not i.isCollapsed, i.rank, i.tempPoints, i.modifier, i.maxRank end
end
function ns.GetMerchantItemInfo(index)
    local m = C_MerchantFrame and C_MerchantFrame.GetItemInfo(index)
    if m then return m.name, m.texture, m.price, m.stackCount, m.numAvailable, m.isPurchasable, m.isUsable, m.hasExtendedCost end
end
ns.GetZonePVPInfo = C_PvP and C_PvP.GetZonePVPInfo
ns.GetCoinTextureString = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
ns.GetSpellLink = C_Spell and C_Spell.GetSpellLink
-- An item or spell the game won't give details of (some of Forever's new vendors and drops):
-- our text instead of its bare "Retrieving item information". label: the name we have.
ns.GAP_SHORT = "Details to come"
ns.GAP_TEXT = "Still filling in the gaps after Forever's launch. The game hasn't shared this one's details yet."
local function GapTip(label)
    GameTooltip:AddLine(label or "Unknown", 1, 1, 1)
    GameTooltip:AddLine(ns.GAP_TEXT, 0.6, 0.6, 0.6, true)
end
function ns.ItemTip(item, label)
    if (GetItemInfo or ns.GetItemInfo)(item) then GameTooltip:SetItemByID(item) else GapTip(label) end
end
function ns.SpellTip(spell, label)
    if (GetSpellInfo or ns.GetSpellInfo)(spell) then GameTooltip:SetSpellByID(spell) else GapTip(label) end
end

function ns.GetMouseFocus()
    local foci = GetMouseFoci and GetMouseFoci()
    return foci and foci[1]
end

-- The dungeon map and all that runs inside dungeons: off on Forever till it's been played there. None of
-- it has run in a live dungeon, and nobody should have to turn the addon off to do one. Entrances
-- on the zone maps stay. One line to undo.
ns.DungeonsOff = ns.FOREVER

-- The game's own objective markers and blue quest areas are Forever's only (the map's
-- providers aren't attached elsewhere, BattlefieldInfo.lua): their settings, buttons
-- and preset rows don't show there. Their saved values are left alone.
-- Without Gather.lua in the build, the rest of gathering switches off (it was out of Forever's zips
-- until 1.2.3, before GatherMate2 worked there).
-- And with nothing to draw from: no GatherMate2 and no Waymark_Nodes (Forever's zip has none), a
-- button that does nothing only confuses. It all comes back with GatherMate2 on.
function ns.GatherPulled()
    if not ns.FOREVER then return false end
    if not ns.SetupGather then return true end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if loaded and loaded("GatherMate2") then return false end
    return not (ns.GatherOwnData and ns.GatherOwnData())
end

function ns.NoGameLayer(group)
    return not ns.FOREVER and (group == "objectives" or group == "areas")
        or (group == "gather" and ns.GatherPulled())
end
function ns.DropNoGameLayers(list, field)
    for i = #list, 1, -1 do
        if ns.NoGameLayer(list[i][field]) then table.remove(list, i) end
    end
    return list
end

-- Which edition this copy is, from the TOC's X-Edition: "Forever" (branch main; also
-- run on the stand-ins for testing) or "Era" (the frozen Classic Era release, branch
-- era, in F:\AddonWorkspace\BattlefieldInfo-Era). Shown by /bfi check.
local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.EDITION = GetMeta and GetMeta(addonName, "X-Edition") or "?"

-- Our own files, by the folder's name (Waymark; 1.x was BattlefieldInfo, see
-- mockups\waymark-rename-audit.md). Every media path starts here.
ns.ADDON = addonName
ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

-- Whose maps are drawn: "Forever" or "Era". On Classic Era it can be Forever's (dev,
-- /bfi forevermap: toolsorever_map.py's Waymark_ForeverMap holds Forever's
-- tiles and zone places), so Forever's masks, outlines and continent work can be made
-- there. Every per-edition map file (ZoneShapes, ZoneCut, ZoneClone, overlays) goes by it.
function ns.ForeverMapDev()
    return not ns.FOREVER and type(WaymarkForeverMap) == "table"
        and WaymarkDB and WaymarkDB.foreverMap and WaymarkForeverMap or nil
end
function ns.MapEdition() return (ns.FOREVER or ns.ForeverMapDev()) and "Forever" or "Era" end

-- A map's place on another (C_Map.GetMapRectOnMap: left, right, top, bottom), Forever's
-- under /bfi forevermap: four zones sit differently there
function ns.MapRectOnMap(id, parent)
    local fm = ns.ForeverMapDev()
    local r = fm and fm.rects[id]
    if r and r[1] == parent then return r[2], r[3], r[4], r[5] end
    return C_Map.GetMapRectOnMap(id, parent)
end
-- a map's base art: its layer (layerWidth, layerHeight, tileWidth, tileHeight) and tile
-- file IDs, row by row. Under /bfi forevermap the zones only Forever has (Mount Hyjal,
-- Shen'dralas, Riverglades) come from Waymark_ForeverMap's extra
function ns.MapArtLayer(id)
    local fm = ns.ForeverMapDev()
    local x = fm and fm.extra and fm.extra[id]
    if x then
        return { layerWidth = x[2], layerHeight = x[3], tileWidth = 256, tileHeight = 256 }, x[4]
    end
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(id)
    local ok, files = pcall(C_Map.GetMapArtLayerTextures, id, 1)
    return layers and layers[1], ok and files or nil
end

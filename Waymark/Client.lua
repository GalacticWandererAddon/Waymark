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

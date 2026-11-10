local _, ns = ...

-- Each zone's fishing level: from this skill on, no fish gets away there. The game's own steps
-- (25, 75, 150, 225, 300, 425: a zone's base fishing level and 95), written by hand per zone
-- (uiMapID). Capitals take their zone's. Zones with no water to speak of are left out. Forever's
-- own new zones aren't here: FishingMap.lua learns them from your getaways ("Fishing ?" till then).
ns.FishingLevels = {
    -- Kalimdor
    [1411] = 25,  [1412] = 25,  [1438] = 25,  [1454] = 25,  [1456] = 25,  [1457] = 25,   -- Durotar, Mulgore, Teldrassil, capitals
    [1413] = 75,  [1439] = 75,                                                            -- the Barrens, Darkshore
    [1440] = 150, [1442] = 150,                                                           -- Ashenvale, Stonetalon
    [1441] = 225, [1443] = 225, [1445] = 225,                                             -- Thousand Needles, Desolace, Dustwallow
    [1444] = 300, [1446] = 300, [1447] = 300, [1448] = 300, [1449] = 300, [1450] = 300,   -- Feralas, Tanaris, Azshara, Felwood, Un'Goro, Moonglade
    [1451] = 425, [1452] = 425,                                                           -- Silithus, Winterspring
    -- Eastern Kingdoms
    [1420] = 25,  [1426] = 25,  [1429] = 25,  [1453] = 25,  [1455] = 25,  [1458] = 25,   -- Tirisfal, Dun Morogh, Elwynn, capitals
    [1421] = 75,  [1432] = 75,  [1436] = 75,                                              -- Silverpine, Loch Modan, Westfall
    [1424] = 150, [1431] = 150, [1433] = 150, [1437] = 150,                               -- Hillsbrad, Duskwood, Redridge, Wetlands
    [1416] = 225, [1417] = 225, [1434] = 225, [1435] = 225,                               -- Alterac, Arathi, Stranglethorn, Swamp of Sorrows
    [1422] = 300, [1425] = 300,                                                           -- Western Plaguelands, the Hinterlands
    [1423] = 425, [1428] = 425, [1430] = 425,                                             -- Eastern Plaguelands, Burning Steppes, Deadwind Pass
}

local _, ns = ...

-- Forever's vendor stock and dungeon loot from AllTheThings (github.com/ATTWoWAddon/AllTheThings, its
-- .contrib/.db/forever database; MIT, see LICENSES/AllTheThings-LICENSE.txt). Made by tools/att_bake.py: don't
-- edit by hand. Only what our own data lacks. Forever only: WorldQuests.lua merges ForeverQuestData on Forever,
-- VendorList.lua reads ns.ForeverStock on Forever.
--   ns.ForeverStock.sells[npc] = { item, ... } (negative: limited supply); price[item] = copper

ns.ForeverStock = { sells = {
[4612]={278265},
[8118]={8626,8625,8624},
[8122]={8626,8625,8624},
[10667]={184937},
[12245]={-12232,-5643,-12240,-3735,-12231,-5489,-12228},
[12246]={-7087,-4609,-3734,-12239,-12229,-12227,-12233,-13310,-7561},
[12792]={22860,22858,22857,22855,22859,22852,22856,22843,16485,17576,16509,16531,17616,16518,16498,16494,16530,22862,16496,22863,17577,22865,22864,16499,16519,22867,22868,16510,17617,22869,16487,22870,16525,22874,16504,22877,17572,22884,22879,16505,16522,22876,16513,22872,22885,17612,16491,22886,16527,22875,22878,16502,17571,22881,16508,22880,16523,22887,22873,16515,22882,17611,22883,16490,16526,23251,23253,16503,23255,17570,16506,23257,23259,16521,16514,23244,17610,23261,23263,16489,23264,23256,23243,23258,17573,16516,16492,23260,16528,23254,17613,16524,16507,16501,23262,23252,16571,16555,17588,16560,16574,16548,17620,16540,16567,16552,17593,16564,16579,16543,17625,16534,16569,16554,17586,16558,16573,16545,17618,16539,16566,16550,17591,16561,16578,16542,17623,16533,16565,16549,17592,16563,16577,16541,17624,16535,16568,16551,17590,16562,16580,16544,17622,16536},
[14581]={18831,23464,16345,18866,18828,18837,23465,18877,18848,18871,18868,23467,18840,18835,18844,23466,18860,23468,23469,18874},
[16014]={22115},
[29547]={285359},
[32337]={260631,285362},
[227853]={272151,272393,272394,272395,272396,272397,272398,272399,272401,272402,272403,272404,272405,272406,272407,272408,272409,272410,272411,272413,272414,272415,272427,272428,272429,272430,272431,272432,272433,272434,272435,272436,272437,272438,272439,272440},
[248809]={248613},
[251905]={21219,21099},
[251991]={253665,253668},
[253139]={249486,249489,274491,252833,253974,254682,251390,251458,250985,250979,269901,269903},
[253140]={249486,249489,274491,252833,253974,254682,251390,251458,250985,250979,269901,269903},
[254089]={252027,252026,252029},
[255151]={274025,274379},
[255894]={18046},
[255895]={16767},
[255940]={252027,252026,252029},
[256372]={285104},
[256384]={270887,262764,284664},
[256389]={270888,262765,284664},
[256400]={262766},
[256629]={274417,262801,274419,274418,268873,274424,256036,254134,274415,274420},
[256731]={249888,249887,21219,249886,21099,249889,249885,249890},
[256736]={262766},
[257006]={6326,6328,6325},
[257422]={-287063},
[258306]={252761,252762,252832,252764,252763,252826,252830,252831,252827,252828,252829},
[258568]={253665,253668},
[259860]={251460,274977},
[259962]={21219,21099},
[260487]={6330,6368,271657},
[260560]={271654},
[260565]={271653,16046,16047},
[260566]={18650},
[262471]={-8489},
[263230]={-271646,-271648,-271647},
[263384]={271871,12363,249425,13468,248822,248819,249399,249426,249427,249428,249429,249391,249424,249274,248820},
[264797]={273976,273977,273978,273979,273980,273981,273982,273983,273984,273985,273986,273987,274012,274013,274014,274015,274016,274017,274018,274019,273999,273997,273996,273998,273963,273965,273953,273961,273956,273964,273960,273958,273957,273962,273959,273954,273966,273955,273967,273952,276545,274006,274005,276543,274007,274001,276542,274000,276544,274004,274002,274003,273969,273971,273968,273970,273972,273973,273974,273975,273988,273989,273990,273991,273992,273993,273994,273995,274008,274009,274010,274011},
[265346]={-275892},
[265347]={278119,278122,278120,278117,278118,278121},
[265576]={274753,274750,274752,274023,274751,274754},
[265577]={274758,274760,274759,274024,274756,274761,274755,274757},
[265756]={269681,269683,269671,269678,274933,274930},
[266901]={255729,254124,252933,252877,251468,264233},
[268745]={-277508},
[269152]={277960},
[271478]={277083,277080},
[271480]={273812,273813,273814},
[271483]={277093,277086,277094,277095},
[272646]={21219,21099},
}, price = {
} }

local Q = ns.ForeverQuestData
if Q then
    Q.bossloot = Q.bossloot or {}
    Q.lootAdded = Q.lootAdded or {}
    -- dungeons with no loot of ours: ATT's bosses, no chances
    Q.bossloot[2970] = Q.bossloot[2970] or {{"Zul'Alai",{274600,274598,274599},{}},{"Var'Taka",{274602,274601},{}},{"Captain Dreadrise",{274605,274603,274604},{}},{"Primeval Elemental",{274611,274612},{}},{"Min'loth the Serpent",{274608,274610,274609},{}}}
    Q.bossloot[2994] = Q.bossloot[2994] or {{"Tidemistress Ca'zass",{276737,276736,276735},{}},{"Katerina the Cleaner",{276739,276738,276740},{}},{"The Questioner",{276741,276743,276742},{}},{"Blazeroar",{276745,276746,276744},{}}}
    Q.bossloot[3039] = Q.bossloot[3039] or {{"Slavecrusher Grox",{273101,274997,274996,274995},{}},{"Twilight Commander Zarmok",{274999,274998,275000},{}},{"Handler Ashka",{275001,275002,275003},{}},{"Nar'gurk",{275004,275005,275006},{}},{"Overseer Mugg",{275009,271721,275008,275007,275010},{}},{"Bossman Toof",{286428,286429,286430},{}}}
    -- items ATT gives a boss that our data has nowhere in that dungeon
    Q.lootAdded[33] = Q.lootAdded[33] or {}
    do local t = Q.lootAdded[33]; local k = "Commander Springvale"; t[k] = t[k] or {}; for _, i in ipairs({273105,6341}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[33]; local k = "Razorclaw the Butcher"; t[k] = t[k] or {}; for _, i in ipairs({273096}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[33]; local k = "Rethilgore"; t[k] = t[k] or {}; for _, i in ipairs({5254}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[34] = Q.lootAdded[34] or {}
    do local t = Q.lootAdded[34]; local k = "Dextren Ward"; t[k] = t[k] or {}; for _, i in ipairs({273819,273817,273820}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[36] = Q.lootAdded[36] or {}
    do local t = Q.lootAdded[36]; local k = "Cookie"; t[k] = t[k] or {}; for _, i in ipairs({8490,273102}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[36]; local k = "Rhahk'Zor"; t[k] = t[k] or {}; for _, i in ipairs({5187}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[36]; local k = "Sneed"; t[k] = t[k] or {}; for _, i in ipairs({273092,210178,5194,5195}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[36]; local k = "Sneed's Shredder"; t[k] = t[k] or {}; for _, i in ipairs({7365,2169,1937}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[47] = Q.lootAdded[47] or {}
    do local t = Q.lootAdded[47]; local k = "Aggem Thorncurse"; t[k] = t[k] or {}; for _, i in ipairs({6681}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[47]; local k = "Charlga Razorflank"; t[k] = t[k] or {}; for _, i in ipairs({17008}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[47]; local k = "Roogug"; t[k] = t[k] or {}; for _, i in ipairs({6841}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[48] = Q.lootAdded[48] or {}
    do local t = Q.lootAdded[48]; local k = "Baron Aquanis"; t[k] = t[k] or {}; for _, i in ipairs({16782}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[48]; local k = "Gelihast"; t[k] = t[k] or {}; for _, i in ipairs({1470,273141}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[48]; local k = "Lorgus Jett"; t[k] = t[k] or {}; for _, i in ipairs({273843,273841,273842}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[109] = Q.lootAdded[109] or {}
    do local t = Q.lootAdded[109]; local k = "Atal'alarion"; t[k] = t[k] or {}; for _, i in ipairs({22444,10799,10800,10798,252871}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[109]; local k = "Avatar of Hakkar"; t[k] = t[k] or {}; for _, i in ipairs({10663,10844,10838,10843,12462,10845,10842,10846}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[129] = Q.lootAdded[129] or {}
    do local t = Q.lootAdded[129]; local k = "Mordresh Fire Eye"; t[k] = t[k] or {}; for _, i in ipairs({252843}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[129]; local k = "Plaguemaw the Rotting"; t[k] = t[k] or {}; for _, i in ipairs({10766,10760}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[129]; local k = "Tuten'kash"; t[k] = t[k] or {}; for _, i in ipairs({10776,10775,10777}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[189] = Q.lootAdded[189] or {}
    do local t = Q.lootAdded[189]; local k = "Arcanist Doan"; t[k] = t[k] or {}; for _, i in ipairs({274294}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[189]; local k = "Herod"; t[k] = t[k] or {}; for _, i in ipairs({14679,22897,13385,13386,16692,13387,18716}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[189]; local k = "High Inquisitor Fairbanks"; t[k] = t[k] or {}; for _, i in ipairs({13250,14512,13520,13348,18717,13360,13353,13359,18718,12103,18720,13358,13369,16725}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[189]; local k = "High Inquisitor Whitemane"; t[k] = t[k] or {}; for _, i in ipairs({13408,13404,13405,13409,16717}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[189]; local k = "Houndmaster Loksey"; t[k] = t[k] or {}; for _, i in ipairs({12839,22406,22404,13380,22407,22403,22405,16708,18721,13381,13382,13377}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[189]; local k = "Interrogator Vishas"; t[k] = t[k] or {}; for _, i in ipairs({7683}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[209] = Q.lootAdded[209] or {}
    do local t = Q.lootAdded[209]; local k = "Nekrum Gutchewer"; t[k] = t[k] or {}; for _, i in ipairs({9471}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[209]; local k = "Sandarr Dunereaver"; t[k] = t[k] or {}; for _, i in ipairs({9512,9511,6440,9480,9483,5616,862,9484,9481,2040,9482}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[229] = Q.lootAdded[229] or {}
    do local t = Q.lootAdded[229]; local k = "General Drakkisath"; t[k] = t[k] or {}; for _, i in ipairs({16663,15730,13519,16730,16690,16700,16726,16721,16706}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[229]; local k = "Gizrul the Slavener"; t[k] = t[k] or {}; for _, i in ipairs({13205,16718,13208,13206}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[229]; local k = "Lord Valthalak"; t[k] = t[k] or {}; for _, i in ipairs({22336,22335,22302,22340,22337,22343,22342,22339}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[229]; local k = "Overlord Wyrmthalak"; t[k] = t[k] or {}; for _, i in ipairs({13148,13164}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[229]; local k = "Quartermaster Zigris"; t[k] = t[k] or {}; for _, i in ipairs({13247}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[229]; local k = "Shadow Hunter Vosh'gajin"; t[k] = t[k] or {}; for _, i in ipairs({12740}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[229]; local k = "The Beast"; t[k] = t[k] or {}; for _, i in ipairs({12731}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[229]; local k = "Urok Doomhowl"; t[k] = t[k] or {}; for _, i in ipairs({12712,18784,13258,22232,13259,13178}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[229]; local k = "War Master Voone"; t[k] = t[k] or {}; for _, i in ipairs({12741,13175}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[229]; local k = "Warchief Rend Blackhand"; t[k] = t[k] or {}; for _, i in ipairs({12630,12583,12940,12939,12590,12587,12588,16733,12936,18104,12935,18102,22247,18103}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[230] = Q.lootAdded[230] or {}
    do local t = Q.lootAdded[230]; local k = "Emperor Dagran Thaurissan"; t[k] = t[k] or {}; for _, i in ipairs({16724,12033}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[230]; local k = "Fineous Darkvire"; t[k] = t[k] or {}; for _, i in ipairs({11840}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[230]; local k = "High Interrogator Gerstahn"; t[k] = t[k] or {}; for _, i in ipairs({11140}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[230]; local k = "Hurley Blackbreath"; t[k] = t[k] or {}; for _, i in ipairs({11312,18043,18044,11735}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[230]; local k = "Lord Incendius"; t[k] = t[k] or {}; for _, i in ipairs({11768}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[230]; local k = "Magmus"; t[k] = t[k] or {}; for _, i in ipairs({22275}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[230]; local k = "Phalanx"; t[k] = t[k] or {}; for _, i in ipairs({11743}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[230]; local k = "Ring of Law"; t[k] = t[k] or {}; for _, i in ipairs({11678,11677,11731,11675,11686,11679,11730,11685,11726,11610,11722,11702,11703,11635,11729,11634,11633,11662,11824,11665,11728,22047,22305,22317,22318,22330}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[230]; local k = "The Seven"; t[k] = t[k] or {}; for _, i in ipairs({11922,11926,11925,11929,11921,11927,11923,11920}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[249] = Q.lootAdded[249] or {}
    do local t = Q.lootAdded[249]; local k = "Onyxia"; t[k] = t[k] or {}; for _, i in ipairs({17966}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[289] = Q.lootAdded[289] or {}
    do local t = Q.lootAdded[289]; local k = "Darkmaster Gandling"; t[k] = t[k] or {}; for _, i in ipairs({14514,13501,13937,13938,13953,13964,16677,16667,16693,16698,16731,16727,16686,16707,16720,13944,13951,13950,13398,22433,19276}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[289]; local k = "Doctor Theolen Krastinov"; t[k] = t[k] or {}; for _, i in ipairs({14617}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[289]; local k = "Jandice Barov"; t[k] = t[k] or {}; for _, i in ipairs({13725}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[289]; local k = "Kormok"; t[k] = t[k] or {}; for _, i in ipairs({22332,22333,22303,22326,22331}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[289]; local k = "Rattlegore"; t[k] = t[k] or {}; for _, i in ipairs({13873}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[329] = Q.lootAdded[329] or {}
    do local t = Q.lootAdded[329]; local k = "Archivist Galford"; t[k] = t[k] or {}; for _, i in ipairs({13245,6447,273084}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[329]; local k = "Balnazzar"; t[k] = t[k] or {}; for _, i in ipairs({6448,6449,273137}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[329]; local k = "Baroness Anastari"; t[k] = t[k] or {}; for _, i in ipairs({9741,6469,5970,10411,6459,273087}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[329]; local k = "Cannon Master Willey"; t[k] = t[k] or {}; for _, i in ipairs({9738,6465,6460,10410}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[329]; local k = "Hearthsinger Forresten"; t[k] = t[k] or {}; for _, i in ipairs({7672,9418,9413,11118}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[329]; local k = "Maleki the Pallid"; t[k] = t[k] or {}; for _, i in ipairs({10441,6461,6627,6463}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[329]; local k = "Malor the Zealous"; t[k] = t[k] or {}; for _, i in ipairs({9740,6472,6473,273089}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[329]; local k = "Nerub'enkan"; t[k] = t[k] or {}; for _, i in ipairs({6631,6630,6629}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[329]; local k = "The Unforgiven"; t[k] = t[k] or {}; for _, i in ipairs({7670,9416,9415,9414}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[329]; local k = "Timmy the Cruel"; t[k] = t[k] or {}; for _, i in ipairs({9739,5404,10412,273088,6446,273098}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[349] = Q.lootAdded[349] or {}
    do local t = Q.lootAdded[349]; local k = "Noxxion"; t[k] = t[k] or {}; for _, i in ipairs({9459,9458,9492,9461,4415,4413,6716,4411,6672,7742,7560,7561,4416,7192,4417,4408,4412,4414,4410,4409}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[429] = Q.lootAdded[429] or {}
    do local t = Q.lootAdded[429]; local k = "Alzzin the Wildshaper"; t[k] = t[k] or {}; for _, i in ipairs({18501}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Guard Fengus"; t[k] = t[k] or {}; for _, i in ipairs({18266}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Guard Mol'dar"; t[k] = t[k] or {}; for _, i in ipairs({18268}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Hydrospawn"; t[k] = t[k] or {}; for _, i in ipairs({18299,18305,18307}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Illyanna Ravenoak"; t[k] = t[k] or {}; for _, i in ipairs({18349,18347}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Lethtendris"; t[k] = t[k] or {}; for _, i in ipairs({18426,18302,18301}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Lord Hel'nurath"; t[k] = t[k] or {}; for _, i in ipairs({18757,18756,18754,18755}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Magister Kalendris"; t[k] = t[k] or {}; for _, i in ipairs({18350,18351}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Prince Tortheldrin"; t[k] = t[k] or {}; for _, i in ipairs({18336}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Pusillin"; t[k] = t[k] or {}; for _, i in ipairs({18249,18255}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Stomper Kreeg"; t[k] = t[k] or {}; for _, i in ipairs({18287,18269,18284,18288}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Tendris Warpwood"; t[k] = t[k] or {}; for _, i in ipairs({18352,18353}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Tsu'zee"; t[k] = t[k] or {}; for _, i in ipairs({18346}) do t[k][#t[k] + 1] = i end end
    do local t = Q.lootAdded[429]; local k = "Zevrim Thornhoof"; t[k] = t[k] or {}; for _, i in ipairs({18308,18306}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[2998] = Q.lootAdded[2998] or {}
    do local t = Q.lootAdded[2998]; local k = "Highland Horror"; t[k] = t[k] or {}; for _, i in ipairs({270180}) do t[k][#t[k] + 1] = i end end
    Q.lootAdded[2999] = Q.lootAdded[2999] or {}
    do local t = Q.lootAdded[2999]; local k = "Lordaeron Captain"; t[k] = t[k] or {}; for _, i in ipairs({6641,6642}) do t[k][#t[k] + 1] = i end end
end

local addonName, ns = ...

-- One settings group per map element; each has its own toggle and opacity
local DEFAULTS = {
    scale = 1,
    -- all of Waymark at once, the game's own UI left as it is (ns.AddonScale). Forever's
    -- automatic UI scale is 0.64 at 1440p; Waymark was drawn at 0.8, so 1.25 there
    addonScale = ns.FOREVER and 1.25 or 1,
    quickButton = true,
    townButton = true,    -- town view on/off, beside the quick-options gear (Options.lua)
    cityButton = true,    -- city view's zoom on/off, beside the town view button
    dockButton = true,    -- minimap replacement on/off, beside the city view button
    quickToggles = true,  -- the small feature toggle buttons on the map
    mapButtons = true,    -- all of the map's buttons at once (toggles, gear, town view, dock)
    minimap    = { hide = false, angle = 225 },
    -- the font of Waymark's right-click menus and its ask box (Notebook.lua, Ask.lua); Friz
    -- Quadrata, the game's own, reads best; Felipa was the first look (the user, 2026-11-10)
    menus      = { font = "friz" },
    -- quest givers, turn-ins and objective spots come from QuestieDB (QuestData.lua)
    -- iconSet: "questie" (Questie's icons, where Questie is installed) or
    -- "modern" (the map atlases)
    -- trivial: grey quest givers too (nil: Questie's own setting, the first time);
    -- hidden[questID]: quests hidden with Shift-click
    -- source: where quests come from, "own" (our data, WorldQuests.lua), "both" (ours, filled from
    -- QuestieDB where it's installed: Forever's default) or "questiedb" (a /reload follows)
    -- tooltip: Questie's tooltips on our quest pins, where Questie is loaded (Pin.lua, the
    -- Quests page). Off: ours
    -- unitTips: a quest's objective count on monster, item and object tooltips (QuestData.lua)
    questie    = { shown = true, alpha = 1, scale = 1, color = false, iconSet = "questie", hidden = {}, source = ns.FOREVER and "both" or "own", tooltip = false, unitTips = true },
    -- new quest layers start hidden so existing setups look unchanged
    turnins    = { shown = false, alpha = 1, scale = 1, iconSet = "questie" },
    -- color: each quest's spots in a colour of its own
    -- spacing: no two spots of one objective closer than this, yards (0 = off);
    -- maxPer: at most this many per objective on a map (0 = no limit)
    -- questieIcons: Questie's icons on them, where it's loaded
    spots      = { shown = false, alpha = 0.9, scale = 0.8, color = false, spacing = 40, maxPer = 12, questieIcons = false },
    objectives = { shown = true, alpha = 1, scale = 1 },
    areas      = { shown = true, alpha = 1 },
    -- quest ground (QuestGround.lua): where your quests' monsters and things are,
    -- drawn on the map; all: also quests you could take here; look "haze" / "ink" /
    -- "dots"; color: a colour per quest; drops: the tooltip names the dropped item
    ground     = { shown = true, alpha = 0.7, all = false, look = "dots", color = true, colorBy = "quest", drops = true, hush = true, arrows = true, quiet = true },
    -- rares and treasure chests from our own data (Wilds.lua): rares, elites (rare
    -- elites), treasure (chest spots); paths: a rare's patrol path while hovered;
    -- size in px; bossLoot: "what they carry" in boss menus (BossLoot.lua; lootWear, lootPos)
    -- (look: a rare's mark, "coin" or "dragon"; unset: the coin on Forever, the dragons on Era: Wilds.lua)
    wilds      = { shown = true, rares = true, elites = true, treasure = false, paths = true, size = 14, bossLoot = true },
    -- classColors: group dots in class colour; hover: name, health, distance tooltip
    party      = { shown = true, alpha = 1, classColors = false, hover = false },
    -- the whole map fades while you move / in combat, to these opacities (%);
    -- hover: full again under the mouse
    fade       = { moving = false, movingAlpha = 40, combat = false, combatAlpha = 40, hover = true },
    -- the map folded up to its header in combat (Collapse.lua; also a key)
    collapse   = { combat = false },
    -- just the map over the world (ClearView.lua; also a key): noFrame hides the
    -- border; header / buttons "shown", "hover" (header also "hidden"); opacity:
    -- the map picture's, in place of mapFrame.opacity; zoneOnly: the neighbours cut away
    -- the map docked over the minimap, which turns square and north up
    -- (Dock.lua): size its side in UI units; wheel: the wheel zooms the
    -- minimap and goes between the two, friction: extra clicks past the end;
    -- face: "minimap" or "map", the one showing; corner: pushed into the
    -- screen's top-right corner; big / bigSize: the map face grown (UI units)
    -- splitQuests: objective spots on the minimap face, quest ground on the map's (ns.SplitHides)
    dock       = { on = false, size = 160, wheel = true, friction = 2, face = "map", ourGround = true, splitQuests = false,
                   corner = true, big = false, bigSize = 360, mapOnly = true, hideSun = false, hideTitle = true,
                   shape = "square" },  -- (shape: "square", "54", "43", "1610": Dock.lua SHAPES)
    -- the map lets clicks through unless this modifier (ALT, CTRL, SHIFT) is held (ClickThrough.lua)
    clickThrough = { on = false, modifier = "ALT", combat = false },
    clearView  = { on = false, noFrame = true, header = "hover", buttons = "hover", opacity = 0.7, zoneOnly = true,
                   cities = true, dungeons = true, bigUncut = false },
    -- the settings window's text (Options.lua): font sizes of the section
    -- headings and of everything else (an earlier version kept small offsets)
    optionsText = { heading = 15, text = 12 },
    -- the settings window's own state: advanced = show the fine-tuning
    -- settings; page = the page last open; collapsed[group] = its pages folded
    -- away in the list; folded["page/heading"] = a section folded away on its page
    optionsWindow = { advanced = false, page = nil, collapsed = { Development = true, Extras = true, ["The window"] = true, ["Getting around"] = true, ["What's shown"] = true, ["Your setup"] = true }, folded = {} },
    -- clock (Clock.lua) and soft edges (SoftEdges.lua): their files say what each setting does
    clock      = { shown = false, look = "plain", where = "BOTTOMRIGHT", source = "realm", h24 = true, show = "always",
                   size = 100, alpha = 100, hideGame = false,
                   font = "morpheus", tint = "parchment", backing = 50, frame = "none", frameColor = "natural", frameSize = 0.75, frameGap = 0, plate = true,
                   hideDigits = false, digitsX = 0, digitsY = 0,
                   digitSize = 100, digitBack = 0, digitBold = false },
    softEdges  = { on = false, shape = "square", reach = 2, pins = true },
    mapHour    = { on = false },  -- (MapHour.lua; on in the Creator's preset alone)
    -- coordinates (Coords.lua): size = font size; where = a spot on the map's top
    -- or bottom edge (TOPLEFT, TOP, TOPRIGHT, BOTTOMLEFT, BOTTOM, BOTTOMRIGHT);
    -- side: inside / outside the map; backing: the dark box behind, opacity %;
    -- shadow: the text's drop shadow; outline: a dark outline round the letters;
    -- offsetX / offsetY: a nudge right / up from that spot, in map pixels;
    -- color: the text's { r, g, b }
    -- (offsetX / offsetY: the player's; the cursor's own: cursorWhere ("beside": next to the
    -- player's, else a spot as where), cursorSide ("same": as the player's), cursorX / cursorY)
    coords     = { shown = false, size = 10, where = "BOTTOMLEFT", side = "inside", backing = 50,
                   shadow = true, outline = false, offsetX = 0, offsetY = 0,
                   cursorWhere = "beside", cursorSide = "same", cursorX = 0, cursorY = 0,
                   color = { 1, 1, 1 } },
    waypoints  = { shown = false, alpha = 1, scale = 1, clickToAdd = true },  -- TomTom
    transports = { shown = true, alpha = 1, scale = 1, boats = true, zeppelins = true, trams = true, continent = true, routes = true, boat = "cog" },  -- Transports.lua
    rares      = { shown = false, alpha = 1, scale = 1, rsIcons = false },  -- RareScanner
    fishing    = { shown = false, alpha = 0.55 },  -- Fisherman's mode (FishingMap.lua)
    -- quest givers learned as you play (Learn.lua): mode "gaps" = only quests
    -- QuestieDB doesn't know (all of them without QuestieDB), "all" = every one;
    -- record = keep learning; turnins = "?" where a finished quest is handed in
    learned    = { shown = true, alpha = 1, scale = 0.8, mode = "gaps", record = true, turnins = true,
                   trivial = false, repeatable = true },
    -- the quest tracker (Tracker.lua): this zone's quests, nearest first;
    -- attach: below / above / left / right of the map; detached: on its own (pos)
    -- (onlyTracked: the quests you track; folded[questID]: its objectives hidden;
    -- groupByArea: under sub-zone headings; maxHeight: taller than this scrolls)
    -- hideGameTracker: the game's own quest tracker hidden while ours shows
    -- (true) or "always" (even with the map closed);
    -- autoTrack: quests you accept are tracked at once
    -- (showUntracked: the "Not tracked" quests unfolded at the list's end)
    tracker    = { shown = true, finishedLast = true, itemButtons = true, textShade = 0, hideGameTracker = false, autoTrack = true, showUntracked = false, attach = "below", detached = false, width = 220, pos = nil, sort = "distance",
                   finished = "show", hideGrey = false, hideElite = false, hideDungeon = false,
                   hideGroup = false, onlyTracked = true, objectives = true, hideDoneObjectives = false,
                   collapsed = false, hideEmpty = false, folded = {}, groupByArea = true, maxHeight = 260,
                   -- look: as the game's own tracker by default (no background, no border)
                   -- textAsLog: its text as the quest log's text parts; else its own:
                   -- sizes headerSize the zone name, fontSize quest names, objSize
                   -- objectives. Sub-zone headings: textSubFont / Size / Outline.
                   textAsLog = true, textSubFont = "morpheus", textSubSize = 11, textSubOutline = false,
                   titleFont = "morpheus", textFont = "morpheus", headerSize = 13,
                   fontSize = 12, objSize = 11, outline = "none",
                   shadow = true, icons = true, headerArt = true, levelColors = true,
                   lineGap = 1, questGap = 6, bgAlpha = 0, fadeOut = false, fadeAlpha = 30,
                   -- otherZones: tracked quests from other zones too, "always" /
                   -- "continent" (while the map shows a continent) / "off".
                   -- turninName (turninStyle "place" / "prefix" / "where": the place alone), countColumn
                   -- (doneCount "count" / "tick"), levelColumn (goldTitles),
                   -- quietHeadings, flashProgress
                   otherZones = "always", turninName = true, turninStyle = "place",
                   countColumn = true, doneCount = "count", levelColumn = true, goldTitles = false,
                   quietHeadings = true, flashProgress = true,
                   -- borderStyle "map": the map border's own settings, lined up with it;
                   -- joinBorders: attached, no border on the side facing the map
                   -- freeHeight: on its own, the height from its corner grip
                   borderStyle = "map", borderSize = 1, borderGap = 0, borderColor = "natural",
                   joinBorders = true, freeHeight = 260 },
    -- the quest log window (Tracker.lua): a quest's page beside the map.
    -- Opening: right-click in the tracker; fromPins also a quest's objective
    -- spot or turn-in; keyL the quest log key while the map shows; escape
    -- closes it. list: the whole log at the top of the window (listShare of
    -- it), the selected quest's page below; listHereFirst your zone first,
    -- listFoldOthers the others folded until opened (zoneOpen[zone] = true /
    -- false once clicked), listLevelColors, logStyle (its look: "parchment" /
    -- "classic" / "leather"), listGoldTitles (parchment on the dark page:
    -- gold titles). chain: the quest's chain on the page (QuestieDB).
    -- Text parts (Quest log text): text<Part>Font (Fonts.lua key), Size,
    -- Outline for Head, Zone, Quest (names in the log), Title, Sect (section
    -- headings), Detail, Small (small print), Chain. (The list parts' outline
    -- never on plain parchment with the parchment page.)
    -- Attached: side "auto" / "right" / "left", matchHeight (the map's, and
    -- pastTracker the tracker's below it; else height), seam, gap. detached:
    -- pos (top-left, UIParent units), height; onlyWithMap, locked. scale both.
    -- Page: objectives, description, rewards, levelTag, people (giver and
    -- turn-in, QuestieDB), questID; buttons abandon / share / track / focus;
    -- glow (its spots and areas lit while open). Look: paper "parchment" /
    -- "dark", alpha, fadeOut to fadeAlpha %. Frame: borderStyle "own" (its own
    -- art) / "map" (the map border's) / a map border style, with borderSize,
    -- borderGap, borderColor.
    -- replaceGame: the quest log key opens it map or not, the game's closes as it opens
    questlog   = { shown = true, fromPins = false, keyL = false, replaceGame = false,
                   listHereFirst = true, listFoldOthers = true, listLevelColors = true, listShare = 0.27, logStyle = "leather",
                   listGoldTitles = false,
                   textHeadFont = "morpheus", textHeadSize = 14, textHeadOutline = true,
                   textZoneFont = "morpheus", textZoneSize = 12, textZoneOutline = true,
                   textQuestFont = "friz", textQuestSize = 11, textQuestOutline = true,
                   textTitleFont = "morpheus", textTitleSize = 18, textTitleOutline = false,
                   textSectFont = "morpheus", textSectSize = 18, textSectOutline = false,
                   textDetailFont = "friz", textDetailSize = 13, textDetailOutline = false,
                   textSmallFont = "friz", textSmallSize = 11, textSmallOutline = false,
                   textChainFont = "friz", textChainSize = 12, textChainOutline = false,
                   chain = true,
                   zoneOpen = {},
                   detached = false, side = "auto", matchHeight = true, pastTracker = true, seam = true, gap = 0,
                   height = 570, pos = nil, onlyWithMap = true, locked = false, scale = 1,
                   objectives = true, description = true, rewards = true, levelTag = true, people = true,
                   questID = false, abandon = true, share = true, track = true, focus = true, glow = true,
                   paper = "parchment", alpha = 1,
                   fadeOut = false, fadeAlpha = 30,
                   borderStyle = "own", borderSize = 1, borderGap = 0, borderColor = "natural" },
    -- types[key] = true per townsfolk/vendor key (Townsfolk.lua), plus "professions"
    -- mergeYards: same-type townsfolk this close share one pin (0 = off);
    -- mergeKinds: different types too
    -- record: learn townsfolk as you play (Townsfolk.lua); useLearned: show
    -- them too, alongside QuestieDB's (off until the database has grown)
    townsfolk  = { shown = false, alpha = 1, scale = 1, graveMark = "stone", myProfessionsOnly = true, types = {},
                   mergeYards = 40, mergeKinds = true, record = true, useLearned = false },
    -- size 0 = leave the game's (or another addon's) size alone
    -- hideTab: hide Blizzard's "Zone Map" tab (it blocks the top of the screen);
    -- opacity: the map's own opacity (normally set from that tab's menu)
    -- (opacity isn't defaulted: it starts from Blizzard's own value, MapControls)
    -- frameAlpha: the border, header and buttons (ns.FrameAlpha)
    mapFrame   = { unlocked = false, locked = false, center = false, arrowSize = 0, groupSize = 0, pos = nil,
                   hideTab = false, frameAlpha = 1,
                   -- width/height: your size from the corner grip (nil = the game's);
                   -- autoWidth: auto shape, part of the zone's shape at about your
                   -- size (shapeFollow 0..1 of the way; shapeGrow: up to that much
                   -- more area for a very different shape); zoneSizes[mapID] =
                   -- { w, h } dragged on that map (MapControls' Shape)
                   autoWidth = false, width = nil, height = nil,
                   -- rememberShapes: use (and keep) zoneSizes; off leaves them stored
                   shapeFollow = 0.8, shapeGrow = 0.15, zoneSizes = {}, rememberShapes = true,
                   -- big: the big map key's mode; bigWidth/bigHeight its size (nil =
                   -- 1.8x yours); bigCorner { right, bottom }: the edges kept still
                   big = false },
    -- Zoom is measured as the map art's size on screen, screen pixels per art
    -- pixel (MapControls' ArtX: "2x"), the same at any map size or scale.
    -- closestX: the closest zoom; smoothness: each 1.5x step split into this
    -- many. (autoZoom, nearSpots, nearNodes, clusterX: auto-zoom near objectives, gone since
    -- 2026-11-06, no longer read; kept so older presets still match.)
    -- townX: town view's zoom (0 = fully out); animTime: seconds an auto-zoom
    -- in/out takes; fitZone: fully zoomed out shows the zone itself, not the
    -- whole map art
    zoom       = { closestX = 8, smoothness = 2, fitZone = true, autoZoom = false, inTowns = true, nearSpots = true,
                   nearNodes = true, townX = 2.5, clusterX = 2, animTime = 1.2 },
    -- the game's minimap tiles over the map when zoomed in (from OpenMap's data)
    -- strength: opacity at full detail; fromX / fullX: it fades in from that
    -- art size on screen to full at this one (MapControls' ns.DetailFade);
    -- blend: tint toward the parchment
    -- always: at full strength at every zoom, not only up close
    -- sharpArt: the sharp (2x upscaled) map art, where the Waymark_MapArt addon is installed
    -- fromZoom / fullZoom: times closer than fully zoomed out (fromX / fullX:
    -- an earlier version's, art on screen, no longer read)
    detail     = { shown = false, strength = 1, fromZoom = 3.5, fullZoom = 5.5, blend = false, always = false, sharpArt = true, bigMap = true },
    -- Performance mode (ns.Perf), for handhelds and older PCs: on, and items[k] false for the
    -- things the player wants kept as they are. Not part of a setup or preset (Setups.lua EXCLUDE)
    perf       = { on = false, items = {} },
    -- line from you to: a pin you Alt-click, your target if in your group, or the
    -- nearest objective spot
    line       = { shown = false, alpha = 0.9, thickness = 3, groupTarget = true, nearestSpot = false },
    -- gathering nodes (Gather.lua): types[type] = true; off[node name] = true: that one hidden
    gather     = { shown = false, alpha = 1, scale = 1, source = "gathermate", follow = true, look = "ink", canGather = true, tint = false, ringYards = 125,
                   fadeUnseen = true, minimap = true, off = {},
                   types = { ["Herb Gathering"] = true, ["Mining"] = true, ["Fishing"] = true,
                             ["Treasure"] = true } },
    -- caves and dungeons: follow you onto cave/dungeon maps; fallback = draw the
    -- dungeon's map ourselves when the game has none to switch to
    -- (fallback on by default: inside instances this client gives addons no map,
    -- position or facing, so our drawn dungeon map is all there is)
    -- view: "art" (the dungeon's map, boss markers) or "minimap" (the borrowed
    -- minimap: the game's own arrow and detail); bosses: boss markers;
    -- bossList: the list of its bosses on it, ticked as they die (folded: just its title)
    dungeon    = { followMaps = false, fallback = true, showInside = true, view = "art", bosses = true,
                   bossList = true, bossListFolded = false, objects = "icons", objectScale = 1,
                   allChests = false, allQuests = false, switches = false, fightDoors = false, patrols = true, devMobs = false, where = true },
    -- this dungeon run's boss kills (Dungeon.lua): id = instance, leftAt = time you left
    dungeonRun = { id = nil, kills = {}, leftAt = 0 },
    -- the found notes (Notebook.lua): the spread the ribbon marks, where the book was dragged
    notebook   = { spread = 0, kind = "story" },
    -- boss spots you placed on Blizzard's dungeon maps (/bfi bosses place):
    -- [instance] = { [boss] = { floor, x, y } }; tools/boss_spots.lua bakes them into Data\DungeonBosses.lua
    bossSpots  = {},
    objectSpots = {},  -- dungeon pins you moved (DungeonObjects.lua): ["inst:floor"]["name@x,y"] = { x, y }
    objectHidden = {}, -- dungeon pins you hid: ["inst:floor"]["name@x,y"] = true
    -- your own notes on the bosses (shift-click one, Dungeon.lua): [instance] = { [boss] = text }
    bossNotes  = {},
    -- map ink (Ink.lua): your markings, their opacity, the hand for new notes
    -- (a key of ns.INK_HANDS) and the notes' size; inkMarks[map key] = { mark, ... }
    ink        = { shown = true, dungeons = false, alpha = 1, hand = "morpheus", textSize = 1 },
    inkMarks   = {},
    -- dungeon and raid entrances on zone maps (click one: its map)
    dungeons   = { shown = true, continent = false, alpha = 1, scale = 1 },
    -- open-world caves (Cave.lua): blizzardMaps = use Blizzard's cave map where
    -- there is one; zoom = pixels per yard in the view; still = whole cave fitted,
    -- only the arrow moves; arrowSize = pixels; minimapStyleEverywhere = in caves
    -- with a Blizzard map too, the cave's minimap pictures (Data\CaveMinimapExtra.lua)
    -- styleButton: in a cave with both kinds of art, a button on the map to switch
    -- classicArrow: the classic world map's player arrow, in caves and on the zone map (MapControls)
    cave       = { enabled = true, blizzardMaps = true, zoom = 3, still = false, arrowSize = 18, minimapStyleEverywhere = true,
                   styleButton = true, classicArrow = false },
    -- the header, where you are by name (ZoneName.lua): mode "header" (above the
    -- map), "inside" or "below"; style: plate, stone, parchment, tooltip, text
    zoneName   = { shown = true, mode = "header", style = "plate", font = "morpheus", fontSize = 13,
                   align = "CENTER", fullWidth = false, showZone = false, levels = false,
                   progress = false, pvpColors = false, offsetX = 0, offsetY = 0,
                   -- its edge: "auto" (the style's own) or one of the map border's
                   -- styles, with that one's thickness, distance and colour
                   border = "auto", borderSize = 1, borderGap = 0, borderColor = "natural" },
    -- browsing other maps (Browse.lua): right-click goes a map up, left-click a
    -- zone on a continent opens it. wheel: the mouse wheel climbs too, after
    -- friction notches out past fully zoomed out; idle: back to your map after
    -- the mouse is off the map this many seconds (0 = never); onReopen: back
    -- when the map closes; onZone: back when you walk into another zone; taxi: the map
    -- stays put on a flight path, your zone on landing;
    -- silver: the header in silver on a map you're not in; continentGivers: on a continent,
    -- every zone's quest givers; zoneArt: on a continent, each zone's own map
    -- over it as you zoom in (ZoneArt.lua): fading in from where the zones are
    -- drawn fadeFrom of their own fully-out size to fadeFull; their area pieces
    -- then fill in from nothing, full by detailFull; zoneWash: each zone's
    -- colour flat under its map, in place of the continent's blocky art
    -- (artFrom / artFull, haze / hazeClear, detailStart: earlier versions', no longer read)
    -- overviewNames: zone names under the cursor on a continent or the world
    browse     = { enabled = true, wheel = true, friction = 3, idle = 10, onReopen = true, onZone = false, taxi = true,
                   overviewNames = true,
                   silver = true, continentGivers = true,
                   zoneArt = true, fadeFrom = 0.1, fadeFull = 0.25, detailFull = 0.95, zoneWash = true },
    -- exploration (Explore.lua): shown = draw the areas you haven't found, in
    -- fogStyle (faded, fog, sepia, ink, full) at fogAlpha; flash = a gold flash
    -- where you discover one; hoverNames: the area under the cursor, at the map's
    -- "top" or at the "cursor"; hideUnexplored: no name at all for those
    -- hideQuests / hideOthers: no quest pins / no other pins (townsfolk, rares,
    -- nodes, dungeon entrances) in areas you haven't explored
    explore    = { shown = false, fogStyle = "fog", fogAlpha = 0.7, flash = false,
                   hideQuests = false, hideOthers = false,
                   hoverNames = false, hoverWhere = "top", hoverSize = 15, hideUnexplored = true },
    -- hideQuests: no quest pins (ours or the game's) in the neighbouring
    -- zones the zone map's art shows round its edges
    -- trackedOnly: objective pins (Questie's spots, the game's markers) of the
    -- quests you track only
    outside    = { hideQuests = false, trackedOnly = false },
    -- every pin: on a map scaled down below minMapScale they keep the size they'd
    -- have at that scale (0 = off; ns.PinSize); alpha: every pin's opacity, on
    -- top of its layer's own (ns.PinAlpha); tipScale: tooltips of anything
    -- on the map, this much of their size (Pin.lua)
    pins       = { minMapScale = 1.1, alpha = 1, tipScale = 0.85 },
    -- town view (Town.lua, MapControls): in a town the map zooms in (zoom, how
    -- close: zoom.townX); each pin layer has its town size, sizes[group],
    -- or its own times pinScale where unset (ns.PinScale); ownTypes: townsfolk
    -- from types / myProfessionsOnly here instead of the map's (a copy of the
    -- map's at first: typesCopied). (zoom was auto-zoom's "in towns" before:
    -- migrated is set once it's taken over.)
    -- enabled: town view at all (its zoom, pin sizes, townsfolk list, and the
    -- Towns & cities profile in towns): one switch, also on the map's toggles
    townView   = { enabled = true, zoom = false, pinScale = 1.3, sizes = {}, ownTypes = false, types = {},
                   myProfessionsOnly = false },
    -- city view (Town.lua's capitals): town view's settings for capital cities;
    -- zoomX here is its own how close (art on screen; 0: fully out, the whole city)
    cityView   = { zoom = true, zoomX = 0, pinScale = 1, sizes = {}, ownTypes = false, types = {},
                   myProfessionsOnly = false },
    -- the map's border (Style.lua): style "game" (the game's own), dialog, gold,
    -- tooltip, wood, line, none; size: thickness; gap: pixels further out (or, below
    -- 0, in); shown: off is no border at all, the style kept (ns.MapBorderStyle)
    border     = { shown = true, style = "game", size = 1, gap = 0, color = "natural" },
    -- the toggle buttons on the map (Options.lua): list[id] = shown; style
    -- square/plain; edge: top, bottom (a row), left, right (a column);
    -- from: "start" (left / top end) or "last"; side: inside, outside the map.
    -- (edge and from have no default: until set, the older `where` (topright,
    -- topleft, bottomleft, bottomright, left, right) decides; Options.lua)
    -- fadeOut: fade to fadeAlpha (%) while the mouse isn't on the map
    -- order: the buttons' ids from the starting end (empty: as TOGGLES has them)
    toggles    = { style = "square", size = 18, where = "topright", side = "inside", fadeOut = false, fadeAlpha = 0,
                   fadeClose = false, saveToProfile = true, order = {},
                   list = { questie = true, townsfolk = true, rares = true, gather = true,
                            zoom = true, detail = true, tracker = true, ink = true, quill = true, book = true } },
    -- saved setups by name (Setups.lua)
    setups     = {},
    -- each character's own settings as it logged out, to copy to another (Setups.lua):
    -- ["Name - Realm"] = { settings = {...}, class = "MAGE", time = seconds }
    characters = {},
    -- town detection (Town.lua): marked[subzone] = true/false set by you,
    -- learned[subzone] = true from resting or a flight point there
    towns      = { marked = {}, learned = {} },
    -- context profiles: layers[group] = true/false overrides that layer's Show
    -- while the context is on (nil = leave as is); hideMap hides the whole map
    profiles   = {
        combat       = { enabled = false, hideMap = false, layers = {} },
        battleground = { enabled = false, hideMap = false, layers = {} },
        dungeon      = { enabled = false, hideMap = false, layers = {} },
        city         = { enabled = false, hideMap = false, layers = {} },
    },
}

-- Settings groups drawn by our quest provider (data: QuestData.lua)
local QUESTIE_GROUPS = { questie = true, turnins = true, spots = true }
ns.MIN_MAP_SCALE, ns.MAX_MAP_SCALE = 0.3, 3

BFI_DEBUG_SQUARES = false  -- true = solid yellow squares instead of icons

local function Log(...) print("|cff33ff99Waymark:|r", ...) end
ns.Log = Log

-- our own frames by name, for /bfi check (each module adds its own)
ns.debugFrames = {}

-- The clock's first time: on with the Creator's preset, off with the others (the shipped defaults: Simple).
-- Settings from before the clock that chose another preset start with it off, and the game's
-- clock kept (the user, 2026-11-04). Call before the defaults go in.
-- The map's hour, for settings from before it: on with the Creator's or none chosen, else off.
-- A new player has no settings yet (no pins): the defaults decide.
function ns.ClockFirstTime(db)
    if db.mapHour == nil and db.pins then db.mapHour = { on = not db.presetBase or db.presetBase == "creator" } end
    if db.clock == nil and db.presetBase and db.presetBase ~= "creator" then
        db.clock = { shown = false, hideGame = false }
    elseif db.clock == nil and db.pins then
        -- (settings from before the clock: an update never takes the game's own clock away)
        db.clock = { hideGame = false }
    end
end

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- The rename to Waymark (2026-11; mockups\waymark-rename-audit.md). 1.x kept its data in
-- BattlefieldInfoDB / QuestDB / CharDB, saved in BattlefieldInfo.lua (the file is named after
-- the folder). The release ships a BattlefieldInfo\ helper folder that only declares those
-- (X-Waymark-Stub) and loads before us, so its tables are there now: copy each one into
-- ours once, if ours is still empty. The old table only gets a movedToWaymark stamp, so
-- it's never copied twice and never lost. The character pair runs per character (its
-- own file), on that character's first login.
local OLD_SV = {
    { "WaymarkDB", "BattlefieldInfoDB" }, { "WaymarkQuestDB", "BattlefieldInfoQuestDB" },
    { "WaymarkCharDB", "BattlefieldInfoCharDB" },
}
local function DeepCopy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and DeepCopy(v) or v end
    return c
end
local function Migrate()
    -- the dev copy still in the old folder (until the switch): its TOC declares the old
    -- names, so ours are the same tables, put back at logout (a reset may replace ours)
    if addonName == "BattlefieldInfo" then
        for _, p in ipairs(OLD_SV) do
            _G[p[2]] = _G[p[2]] or {}
            _G[p[1]] = _G[p[2]]
        end
        local back = CreateFrame("Frame")
        back:RegisterEvent("PLAYER_LOGOUT")
        back:SetScript("OnEvent", function()
            for _, p in ipairs(OLD_SV) do _G[p[2]] = _G[p[1]] end
        end)
        return
    end
    local moved
    for _, p in ipairs(OLD_SV) do
        local new, old = _G[p[1]], _G[p[2]]
        if type(old) == "table" and next(old) ~= nil and not old.movedToWaymark
            and (new == nil or (type(new) == "table" and next(new) == nil)) then
            _G[p[1]] = DeepCopy(old)
            old.movedToWaymark = time()
            moved = true
        end
    end
    if moved then
        C_Timer.After(4, function()
            print("|cff33ff99Waymark:|r your Battlefield Info settings, ink and notes came along. "
                .. "The BattlefieldInfo helper folder can go once each of your characters has logged in.")
        end)
    end
end

-- A full 1.x BattlefieldInfo running too (an old copy kept beside Waymark, not the helper
-- folder): both on one Battlefield Map won't do. Its data still comes over (Migrate);
-- then we stay out of the map this session, turn it off for this character (per
-- character: an alt's own data comes over on its first login) and ask for a /reload.
local function OldCopyRunning()
    if addonName == "BattlefieldInfo" then return false end
    local A = C_AddOns or {}
    local IsLoaded = A.IsAddOnLoaded or IsAddOnLoaded
    local GetMeta = A.GetAddOnMetadata or GetAddOnMetadata
    return IsLoaded and IsLoaded("BattlefieldInfo") and GetMeta
        and GetMeta("BattlefieldInfo", "X-Waymark-Stub") == nil or false
end
local function StandBy()
    ns.standBy = true
    local A = C_AddOns or {}
    local Disable = A.DisableAddOn or DisableAddOn
    if Disable then pcall(Disable, "BattlefieldInfo", UnitName("player")) end
    local msg = "|cff33ff99Waymark:|r the old Battlefield Info is installed too. It's been turned off "
        .. "for this character: type /reload to use Waymark. (Or delete Interface\\AddOns\\BattlefieldInfo "
        .. "and use the BattlefieldInfo helper folder from Waymark's download.)"
    ns.standByMsg = msg
    C_Timer.After(4, function() print(msg) end)
end

-- Saved variables only exist once our own ADDON_LOADED fires
local function InitDB()
    Migrate()
    WaymarkDB = WaymarkDB or {}
    local db = WaymarkDB
    -- the welcome (Welcome.lua): for new players only, so settings from before it count as seen
    if db.zoom then db.zoom.autoZoom = false end  -- (gone: DEFAULTS' zoom)
    if db.dock then db.dock.mapOnly, db.dock.face = true, "map" end  -- (docked is the map: Dock.lua)
    if db.welcome == nil then db.welcome = { noted = db.pins ~= nil, done = db.pins ~= nil } end
    -- (spots took Questie's icons before they had a say: settings from then keep them)
    if db.pins and db.spots and db.spots.questieIcons == nil then db.spots.questieIcons = true end
    -- (the docked split of pins and dots is gone, the user, 2026-11-07)
    if db.dock and db.dock.splitQuests then db.dock.splitQuests, db.dock.splitGround = false, nil end
    -- (Waymark's dots and pins became one look, 2026-11-07: which of the two you had is kept)
    if db.objectivePins == nil and db.objectiveLook then
        db.objectivePins = db.objectiveLook == "waymark"
        if db.objectiveLook == "dots" then db.objectiveLook = "waymark" end
    end
    -- (quest ground's Pins look is gone: it was objective spots by another name)
    if db.ground and db.ground.look == "pins" then
        db.ground.look = "dots"
        if db.ground.shown and db.spots then db.spots.shown, db.ground.shown = true, false end
    end
    -- carry over settings from the earlier flat layout
    if db.questieAlpha ~= nil or db.objectivesAlpha ~= nil then
        db.questie = db.questie or {}
        db.questie.alpha = db.questieAlpha
        db.questie.scale = db.iconScale
        db.questie.plain = db.plainIcons
        db.objectives = db.objectives or {}
        db.objectives.alpha = db.objectivesAlpha
        db.questieAlpha, db.iconScale, db.plainIcons, db.objectivesAlpha = nil, nil, nil, nil
    end
    -- the parchment mat behind the map is gone
    if db.border then db.border.mat, db.border.matPad = nil, nil end
    -- (the settings window in the game's Options look: headings a size above
    -- the labels, 15, where the old default 12 was kept; once)
    if db.optionsText and not db.optionsText.look then
        if db.optionsText.heading == 12 then db.optionsText.heading = 15 end
        db.optionsText.look = "forever"
    end
    -- the detail layer's first default (0.6) was too faint: move it to the new one
    if db.detail and db.detail.strength == 0.6 and db.detail.blend == nil then db.detail.strength = 1 end
    -- "plain icons" became the classic icon set; the header's "off" its own switch
    if db.questie and db.questie.plain ~= nil then
        if db.questie.plain then db.questie.iconSet = "classic" end
        db.questie.plain = nil
    end
    if db.townsfolk then db.townsfolk.framed = nil end  -- (round frames: removed, looked bad)
    -- the toggle buttons' "Classic round" look: removed
    if db.toggles and db.toggles.style == "framed" then db.toggles.style = "square" end
    db.daynight = nil  -- (the day & night tint: removed)
    if db.detail then  -- (smoothing removed; sharp art: on or off, 2x only)
        if db.detail.hdArt ~= nil then db.detail.sharpArt = db.detail.hdArt ~= "off" end
        db.detail.hdArt, db.detail.smooth = nil, nil
    end
    if db.toggles and db.toggles.list then db.toggles.list.daynight = nil end
    -- (Forever's default became ours filled from QuestieDB: once, then it's the player's choice)
    if ns.FOREVER and not db.questieBoth then
        if db.questie and db.questie.source == "own" then db.questie.source = "both" end
        db.questieBoth = true
    end
    -- (the classic "!" "?" icon set: removed, back to Questie's)
    for _, g in ipairs({ "questie", "turnins" }) do
        if db[g] and db[g].iconSet == "classic" then db[g].iconSet = "questie" end
    end
    for _, p in pairs(db.profiles or {}) do
        if type(p) == "table" and p.layers then p.layers.daynight = nil end
    end
    -- (town view's switch moved from the toggle strip to its own button)
    if db.toggles and db.toggles.list then db.toggles.list.townView = nil end
    -- (vendor types: drink folded into food, bags into general goods, pet food
    -- gone; in the map's list and town / city view's own)
    for _, g in ipairs({ "townsfolk", "townView", "cityView" }) do
        local t = db[g] and db[g].types
        if t then
            if t.Drink then t.Food = true end
            if t.Bags then t.General = true end
            t.Drink, t.Bags, t["Pet Food"] = nil, nil, nil
        end
    end
    -- (the toggle strip trimmed: two pairs became one button each, and the
    -- set-once layers lost theirs; a pair's button shows if either half did. The
    -- unexplored areas' pins have none now: a setting on the Exploration page)
    if db.toggles and db.toggles.list then
        local l = db.toggles.list
        if l.objectives or l.areas then l.questMarkers = true end
        for _, id in ipairs({ "fogQuests", "fogOthers", "fogPins", "objectives", "areas", "learned", "party",
                              "explore", "zoneName", "coords" }) do
            l[id] = nil
        end
    end
    if db.tracker then
        local t = db.tracker
        t.showDistance = nil  -- (how far: in the tooltip only now)
        -- the tracker shows only tracked quests (no "*" marking them), scrolls
        -- instead of "+ N more", and is in Morpheus: once, over what was saved
        if (t.version or 1) < 2 then
            t.onlyTracked, t.titleFont, t.textFont = true, "morpheus", "morpheus"
            t.markTracked, t.maxQuests = nil, nil
            t.version = 2
        end
        -- its border became "same as the map's" (lined up with it): once
        if t.version < 3 then
            t.borderStyle = "map"
            t.version = 3
        end
        -- the zone name and sub-zone headings got their own sizes: as they
        -- were (a step either side of the quest names), once
        if t.version < 4 then
            local s = t.fontSize or 12
            t.headerSize, t.areaSize = t.headerSize or s + 1, t.areaSize or s - 1
            t.version = 4
        end
    end
    if db.zoneName and db.zoneName.mode == "off" then
        db.zoneName.shown, db.zoneName.mode = false, "header"
    end
    -- zoom counted in the game's steps became art size on screen (MapControls'
    -- ArtX): the old step counts mean nothing now, the new ones start at defaults
    if db.zoom then db.zoom.extraZoom, db.zoom.zoomLevel, db.zoom.clusterLevel = nil, nil, nil end
    if db.detail then db.detail.fullAt, db.detail.fadeLength = nil, nil end
    if db.cityView then db.cityView.zoomLevel = nil end
    -- art size on screen was first measured in UI units, not screen pixels (the
    -- screen's height was lost): values set then are scaled once, so the map
    -- zooms just as it did; only the numbers shown change
    if db.zoom and db.zoom.closestX ~= nil and (db.zoom.artVersion or 1) < 2 and ns.PhysicalPerUI then
        local k = ns.PhysicalPerUI()
        local function Scale(t, key, max)
            if t and t[key] then t[key] = math.min(max, t[key] * k) end
        end
        Scale(db.zoom, "closestX", 24)
        Scale(db.zoom, "townX", 16)
        Scale(db.zoom, "clusterX", 16)
        Scale(db.cityView, "zoomX", 16)
        Scale(db.detail, "fromX", 16)
        Scale(db.detail, "fullX", 16)
    end
    if db.zoom then db.zoom.artVersion = 2 end
    -- the quest window's size moved from the tracker to its own Quest log page
    if db.tracker and db.tracker.pageScale then
        db.questlog = db.questlog or {}
        if db.questlog.scale == nil then db.questlog.scale = db.tracker.pageScale end
        db.tracker.pageScale = nil
    end
    -- (your whole log in the quest window: always now, its switch gone)
    if db.questlog then db.questlog.list, db.questlog.escape = nil, nil end  -- (and Escape always closes it)
    ns.ClockFirstTime(db)
    -- a first install with Questie: what its player expects, Questie's icons and objective
    -- spots on, before anyone picks anything (no pins table: no settings yet; updates never get
    -- here). Questie loads first: OptionalDeps.
    if db.pins == nil and ns.QuestieArt() then
        db.questie = db.questie or {}
        db.turnins = db.turnins or {}
        db.spots = db.spots or {}
        db.questie.iconSet, db.turnins.iconSet, db.spots.shown = "questie", "questie", true
    end
    CopyDefaults(db, DEFAULTS)
    ns.db = db
    ns.ShareQuestLook()  -- (turn-ins: the givers' opacity, size, icons)
end
ns.DEFAULTS, ns.CopyDefaults = DEFAULTS, CopyDefaults

-- Whether a layer shows right now: its own setting, unless the active context
-- profile (Profiles.lua) says otherwise. Use this instead of reading .shown.
-- A layer you switch on the map (toggle button, key binding) while a profile
-- overrides it: your switch wins, until the active profile changes.
local manual, manualFor = {}, nil

local function ActiveKey()
    return ns.ActiveProfileKey and ns.ActiveProfileKey() or nil
end

function ns.IsShown(group)
    local cfg = ns.db and ns.db[group]
    if not cfg then return false end
    local profile = ns.ActiveProfile and ns.ActiveProfile()
    if profile and profile.layers and profile.layers[group] ~= nil then
        local key = ActiveKey()
        if manualFor ~= key then wipe(manual) manualFor = key end
        if manual[group] ~= nil then return manual[group] end
        return profile.layers[group]
    end
    return cfg.shown and true or false
end

-- Performance mode (Options' Performance mode page): for handhelds and older PCs. While it's on,
-- each item the player left ticked runs lighter; their own settings stay as they are, so turning
-- it off brings everything back. Items: art (painted continents), warm (map art loaded ahead),
-- detail (close-up tiles), ground (quest areas: objective spots instead), effects (time of day,
-- soft edges, clear view), ticks (the map's checks 4 a second, not 10). ns.IsShown stays the
-- player's choice (the settings and toggle buttons show and switch that): it's applied where drawn
ns.PERF_ITEMS = { "art", "warm", "detail", "ground", "effects", "ticks" }
function ns.Perf(item)
    local p = ns.db and ns.db.perf
    return p and p.on and p.items[item] ~= false or false
end
-- a ticker's seconds between looks, slower in performance mode
function ns.Tick(s) return ns.Perf("ticks") and math.max(s, 0.25) or s end

-- whether the active profile decides this layer right now (its label, or nil)
function ns.ProfileOverrides(group)
    local profile = ns.ActiveProfile and ns.ActiveProfile()
    if profile and profile.layers and profile.layers[group] ~= nil then
        local key = ActiveKey()
        return key and ns.PROFILE_LABELS and ns.PROFILE_LABELS[key] or "a profile"
    end
end

-- Switch a layer from the map: what you see flips, whether your own setting or
-- the active profile decides it. key: the setting ("shown" for layers).
function ns.ToggleLayer(group, key)
    local cfg = ns.db[group]
    if not cfg then return end
    local profile = ns.ActiveProfile and ns.ActiveProfile()
    -- a fight is too short a context to remember clicks in: switching a layer off mid-fight and
    -- having it back after confuses people. So there a click is plain: it's your own setting, and
    -- a rule the combat profile had for the layer goes, or the click wouldn't hold
    if key == "shown" and ActiveKey() == "combat" then
        cfg.shown = not ns.IsShown(group)
        if profile and profile.layers and profile.layers[group] ~= nil then
            profile.layers[group] = nil
            if ns.RefreshControls then ns.RefreshControls() end  -- (the profiles page)
        end
        ns.OnSettingChanged(group, key)
        return
    end
    -- toggles.saveToProfile: where the active context profile decides the layer, the click is
    -- kept in it, so the layer is that way every time you're in that context again. A layer it
    -- leaves alone is a plain click: your own setting, not one undone as you leave town
    if key == "shown" and ns.ProfileOverrides(group) and ns.db.toggles.saveToProfile then
        profile.layers[group] = not ns.IsShown(group)
        manual[group] = nil
        ns.OnSettingChanged(group, key)
        if ns.RefreshControls then ns.RefreshControls() end  -- (the profiles page)
        return
    end
    if key == "shown" and ns.ProfileOverrides(group) then
        local now = ns.IsShown(group)  -- (also starts the override list for this profile)
        manual[group] = not now
    else
        cfg[key] = not cfg[key]
    end
    ns.OnSettingChanged(group, key)
end

-- Quest givers: one switch for pick-ups and turn-ins, learned givers too. Each has its own with
-- advanced settings; read from the layers, as objectives are.
local GIVERS = { "questie", "turnins", "learned" }
function ns.QuestGiversOn()
    for _, g in ipairs(GIVERS) do
        if ns.IsShown(g) then return true end
    end
    return false
end
function ns.SetQuestGivers(on)
    for _, g in ipairs(GIVERS) do
        if ns.IsShown(g) ~= (on and true or false) then ns.ToggleLayer(g, "shown") end
    end
end

-- Objectives: one switch and a look. "questie": our objective spots in Questie's icons, where it's
-- loaded, and then the first choice. "waymark": in our own. "yours": we leave them alone, the game's
-- own markers and quest areas. db.objectiveLook: the look last picked. Worked out from the layers themselves (each still has its
-- own switch with advanced settings), so a preset or a profile can't leave it out of step.
-- Since 2026-11-07 (the user): three looks. Waymark's: our dots (quest ground), or with db.objectivePins
-- our pins (the spots); docked with dock.splitQuests both, pins on the minimap and dots on the map.
-- Questie's: the pins in Questie's icons, as set in Questie. Blizzard's ("yours"): the game's own.
-- (A "dots" look was briefly its own: it reads as Waymark's.)
local function LookLayers(look)
    if look == "questie" then return { spots = true } end
    if look == "yours" then return { objectives = true, areas = true } end
    return ns.db.objectivePins and { spots = true } or { ground = true }
end
local function Objectives() return ns.FOREVER and { "spots", "ground", "objectives", "areas" } or { "spots", "ground" } end
function ns.ObjectivesOn()
    for _, g in ipairs(Objectives()) do
        if ns.IsShown(g) then return true end
    end
    return false
end
-- (the look you picked wins where the layers agree with it: read from the spots' icons alone, a
-- switch off and on came back as Waymark's though Questie's was picked, the user)
function ns.ObjectiveLook()
    local look, questie = ns.db.objectiveLook, ns.QuestieArt()
    if look == "dots" then look = "waymark" end
    if (look == "questie" and not questie) or (look == "yours" and not ns.FOREVER) then look = nil end
    if ns.IsShown("spots") then
        if look == "questie" or look == "waymark" then return look end
        return ns.SpotsQuestieArt() and "questie" or "waymark"
    end
    if ns.IsShown("ground") then return "waymark" end
    if ns.FOREVER and (ns.IsShown("objectives") or ns.IsShown("areas")) then return "yours" end
    return look or (questie and "questie" or "waymark")
end
function ns.SetObjectives(on, look)
    look = look or ns.ObjectiveLook()
    if look == "dots" then look = "waymark" end
    ns.db.objectiveLook = look
    if (look == "questie" or look == "waymark") and (ns.db.spots.questieIcons and true or false) ~= (look == "questie") then
        ns.db.spots.questieIcons = look == "questie"
        ns.SpotIconsChanged()
        if ns.RedrawQuestie then ns.RedrawQuestie() end
    end
    for _, g in ipairs(Objectives()) do
        local want = on and LookLayers(look)[g] or false
        if ns.IsShown(g) ~= want then ns.ToggleLayer(g, "shown") end
    end
end

-- Waymark's look as pins (true) or dots
function ns.SetObjectivePins(v)
    ns.db.objectivePins = v and true or false
    if ns.ObjectivesOn() and ns.ObjectiveLook() == "waymark" then ns.SetObjectives(true, "waymark") end
end

-- what a toggle shows: the layer as you see it now
function ns.LayerOn(group, key)
    if key == "shown" then return ns.IsShown(group) end
    return ns.db[group] and ns.db[group][key] and true or false
end

-- A map's size in yards (width east-west, height north-south), from the game's
-- world positions of its corners; cached per map
local mapYards = {}
function ns.MapYards(mapID)
    if mapYards[mapID] then return mapYards[mapID][1], mapYards[mapID][2] end
    if not (mapID and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok1, c1, a = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
    local ok2, c2, b = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
    if not (ok1 and ok2 and a and b and c1 == c2) then return end
    local ax, ay = a:GetXY()
    local bx, by = b:GetXY()
    local w, h = math.abs(ay - by), math.abs(ax - bx)
    if w == 0 or h == 0 then return end
    mapYards[mapID] = { w, h }
    return w, h
end

-- Everything redraws: after a profile switch, or when unsure what changed
-- (also what a context profile can switch that isn't a pin layer: the tracker,
-- close-up detail, unexplored areas, the header; and learned givers and dungeon
-- entrances. A profile starting or ending, or a setup loaded, calls this.)
function ns.RedrawAll()
    for _, fn in ipairs({ "RedrawQuestie", "RedrawRares", "RedrawTownsfolk", "RedrawWaypoints",
                          "RedrawGather", "RedrawTransports", "RedrawFishing", "UpdateCoords", "UpdateClock", "UpdateMapHour", "UpdateLine", "RedrawLearned",
                          "RedrawDungeonEntrances", "UpdateDetail", "UpdateZoneName" }) do
        if ns[fn] then pcall(ns[fn]) end
    end
    if ns.UpdateTracker then pcall(ns.UpdateTracker, true) end
    if ns.UpdateExplore then pcall(ns.UpdateExplore, true) end
    if ns.UpdateZoneArt then pcall(ns.UpdateZoneArt) end  -- (the fog on the continent too)
    if ns.ApplyGroups then pcall(ns.ApplyGroups) end
end

-- This client's map canvas has no EnumerateAllPins, so walk the pools directly
local function EachPin(map, fn)
    for template, pool in pairs(map.pinPools or {}) do
        for pin in pool:EnumerateActive() do fn(pin, template) end
    end
end
ns.EachPin = EachPin

-- The level of the map's buttons (the X, the big map arrow, the gear, town / city /
-- dock, the toggles, coordinates, Map only): above everything laid over the map
-- area, the dungeon map and the cave view (area + 5000 and their layers, Dungeon.lua
-- / Cave.lua), the hover label (+5500, Explore) and an inside header (+5600, ZoneName)
function ns.ButtonLevel(map)
    local area = map.ScrollContainer or map
    return math.min(math.max((map.BorderFrame or map):GetFrameLevel() + 10, area:GetFrameLevel() + 5700), 9700)
end

-- Frame levels of the map's own layers, for things we draw on the canvas that
-- aren't pins (detail tiles, the line). The explored-area art is a pin around
-- level 2000, above the base map, so anything drawn under it is hidden where
-- the zone is explored. Returns the explored-art level and the highest pin level.
local levelCache = { t = 0 }
function ns.CanvasLevels(map)
    -- walking every pin is cheap once, not ten times a second: reuse for 1 s
    local now, mapID = GetTime(), map:GetMapID()
    if now - levelCache.t < 1 and levelCache.mapID == mapID then
        return levelCache.explore, levelCache.top, levelCache.bottom
    end
    local explore, top, bottom = nil, 0, nil
    local others = {}
    EachPin(map, function(pin, template)
        local lvl = pin:GetFrameLevel()
        if template == "MapExplorationPinTemplate" then
            explore = math.max(explore or 0, lvl)
        else
            others[#others + 1] = lvl
        end
        if lvl > top then top = lvl end
    end)
    -- bottom: the lowest pin above the explored art (the ones under it are hidden by it)
    for _, lvl in ipairs(others) do
        if lvl > (explore or 0) then bottom = math.min(bottom or lvl, lvl) end
    end
    -- (the lowest seen, not the lowest now: a layer switched off or redrawing left the art
    -- levels free to move, and a masked layer moved to a new level blinks)
    if bottom and (not levelCache.floor or bottom < levelCache.floor) then levelCache.floor = bottom end
    bottom = levelCache.floor
    levelCache.t, levelCache.mapID, levelCache.explore, levelCache.top, levelCache.bottom = now, mapID, explore, top, bottom
    return explore, top, bottom
end

-- A level for something we draw over the map art (unexplored areas, detail
-- tiles, the day tint): `above` levels over the explored-area art, but always
-- under every pin, whatever levels this client gives them
function ns.ArtLevel(map, above)
    local explore, _, bottom = ns.CanvasLevels(map)
    local want = (explore or (map:GetCanvas():GetFrameLevel() + 1997)) + (above or 0)
    if bottom and want > bottom - 1 then
        want = math.max(1, bottom - 4 + (above or 0))
    end
    return want
end

-- Pin groups ------------------------------------------------------------

local TEMPLATE_GROUPS = {
    BFIQuestiePinTemplate   = "questie",
    QuestPinTemplate        = "objectives",
    QuestBlobPinTemplate    = "areas",
    BFIQuestPOIPinTemplate  = "objectives",  -- (ours since 2026-11-10: QuestPOI.lua)
    BFIQuestBlobPinTemplate = "areas",
    GroupMembersPinTemplate = "party",
    BFIWaypointPinTemplate  = "waypoints",
    BFITransportPinTemplate = "transports",
    BFIRarePinTemplate      = "rares",
    BFITownsfolkPinTemplate = "townsfolk",
    BFIGatherPinTemplate    = "gather",
    BFILearnedPinTemplate   = "learned",
    BFIDungeonPinTemplate   = "dungeons",
}

local function GroupOf(pin, template)
    return pin.bfiGroup or TEMPLATE_GROUPS[template]
end
ns.PinGroupOf = GroupOf  -- (for /bfi check)

-- Blizzard pins can show themselves or reset their alpha, so this is reapplied
-- after provider refreshes and once a second while the map is open
-- Pins in areas you haven't explored can be hidden: quest pins and the rest
-- (townsfolk, rares, nodes...) each by their own setting (explore.hideQuests /
-- hideOthers; Explore.lua knows which areas you've found)
local QUEST_PIN_GROUPS = { questie = true, turnins = true, spots = true, objectives = true, learned = true }
local OTHER_PIN_GROUPS = { townsfolk = true, rares = true, gather = true, waypoints = true, transports = true, dungeons = true }

local function HiddenUnexplored(pin, group, mapID)
    local e = ns.db.explore
    local quest = QUEST_PIN_GROUPS[group]
    if not ((quest and e.hideQuests) or (OTHER_PIN_GROUPS[group] and e.hideOthers)) then return false end
    local x, y = pin.normalizedX, pin.normalizedY
    return x and ns.IsUnexploredAt and ns.IsUnexploredAt(mapID, x, y) or false
end

-- quest pins (ours and the game's) sitting in a neighbouring zone's part
-- of the map art (outside.hideQuests; Explore.lua asks the continent map)
local function HiddenOutside(pin, group, mapID)
    if not (ns.db.outside.hideQuests and QUEST_PIN_GROUPS[group]) then return false end
    local x, y = pin.normalizedX, pin.normalizedY
    return x and ns.IsOutsideZone and ns.IsOutsideZone(mapID, x, y) or false
end

-- objective pins of quests you don't track (outside.trackedOnly; tracked: the
-- set from ns.TrackedQuests, made once per pass)
local function HiddenUntracked(pin, group, tracked)
    if not tracked then return false end
    local id
    if group == "spots" then id = pin.questId
    elseif group == "objectives" then id = pin.questID end
    return id ~= nil and not tracked[id]
end

-- A pin layer's opacity: its own, times every pin's (pins.alpha)
function ns.PinAlpha(group)
    local cfg = ns.db[group]
    return (cfg and cfg.alpha or 1) * (ns.db.pins.alpha or 1)
end

-- The border, header and buttons' opacity (mapFrame.frameAlpha)
function ns.FrameAlpha()
    return ns.db and ns.db.mapFrame.frameAlpha or 1
end

-- The map border's style as drawn: "none" while the border is switched off
-- (or clear view hides it)
-- own: the map border as set, clear view or not (the tracker and quest window
-- "same as the map's" take it so: clear view hides only the map's own)
function ns.MapBorderStyle(own)
    local b = ns.db.border
    if not own and ns.ClearViewHidesFrame and ns.ClearViewHidesFrame() then return "none" end
    if not own and ns.SoftEdgesOn and ns.SoftEdgesOn() then return "none" end
    return b.shown == false and "none" or b.style
end

-- quest ground's "pins" look: the objective spot pins stand in for the ground
function ns.SpotsAsGround()
    local g = ns.db and ns.db.ground
    return g and (g.look == "pins" or ns.Perf("ground")) and ns.IsShown("ground") or false
end
-- Docked with dock.splitQuests: one of the two faces each, spots on the minimap, ground on the
-- map (the big map counts as the map). Only with both to choose from; "pins" ground is the spots.
function ns.DockSplit()
    return ns.db.dock.splitQuests and ns.Docked and ns.Docked() and ns.IsShown("ground")
        and ns.db.ground.look ~= "pins" or false
end
function ns.SplitHides(layer)
    if not ns.DockSplit() then return false end
    local minimap = ns.DockMinimapFace() and not ns.DockBigMovable()
    if layer == "ground" then return minimap end
    return not minimap
end

-- (building: the pins made for this map, the face aside: ApplyGroups shows them per face.
-- Left out here, the map face's spots were never made and the minimap had none.)
local function PinsShown(group, building)
    -- (the Lab: the real minimap lies over the map and draws you and your group itself)
    if group == "party" and ns.MinimapDrawsYou and ns.MinimapDrawsYou() then return false end
    if group == "spots" and ns.SpotsAsGround() then return true end
    if group == "spots" and not building and ns.SplitHides("spots") then return false end
    -- (the game's blue quest areas: a mesh over a map this small. On the big map they stay)
    if group == "areas" and ns.Docked and ns.Docked() and not (ns.MapIsBig and ns.MapIsBig()) then return false end
    return ns.IsShown(group)
end

-- Quest ground draws on the zone's map, which a cave's view or map covers: in a cave its objective
-- spot pins stand in, whatever its look (the "pins" look already is them)
local function GroundInCave(group)
    return group == "spots" and ns.IsShown("ground")
end

-- One pin per quest: what our givers and turn-ins show on this map (ours), and the learned
-- turn-ins (handIn). The game's "?" for a finished quest stands where ours does, and
-- learned's "All I've learned" can repeat a giver. Nil with neither of those layers on.
local function ShownQuests(map, mapID)
    if not (ns.IsShown("objectives") or ns.IsShown("learned")) then return nil end
    local ours, handIn = {}, {}
    EachPin(map, function(pin, template)
        local group = GroupOf(pin, template)
        if (group == "questie" or group == "turnins") and PinsShown(group)
            and not HiddenUnexplored(pin, group, mapID) and not HiddenOutside(pin, group, mapID) then
            for _, id in ipairs(pin.icon and pin.icon.quests or { pin.questId }) do ours[id] = true end
        elseif group == "learned" and PinsShown(group) and pin.info then
            for _, id in ipairs(pin.info.turnins) do handIn[id] = true end
        end
    end)
    return ours, handIn
end

local function HiddenDouble(pin, group, ours, handIn)
    if not ours then return false end
    if group == "objectives" then
        return pin.questID ~= nil and (ours[pin.questID] or handIn[pin.questID]) or false
    elseif group == "learned" and pin.info then
        for _, list in ipairs({ pin.info.available, pin.info.turnins }) do
            for _, id in ipairs(list) do
                if not ours[id] then return false end
            end
        end
        return true
    end
    return false
end

function ns.ApplyGroups()
    local map = BattlefieldMapFrame
    if not map or not ns.db then return end
    if ns.DockQuestiePins then ns.DockQuestiePins() end
    if ns.QuestGroundFace then ns.QuestGroundFace() end
    -- (the game's objectives and quest areas both draw nothing with this off, whatever
    -- our toggles say, and a new character has it off. It's only ever turned on here.)
    if ns.FOREVER and (ns.IsShown("objectives") or ns.IsShown("areas")) and not GetCVarBool("questPOI")
        and not (ns.QuestieKeepsObjectivesOff and ns.QuestieKeepsObjectivesOff()) then
        SetCVar("questPOI", "1")
    end
    local mapID = map:GetMapID()
    local tracked = ns.db.outside.trackedOnly and ns.TrackedQuests and ns.TrackedQuests() or nil
    local ours, handIn = ShownQuests(map, mapID)
    EachPin(map, function(pin, template)
        local group = GroupOf(pin, template)
        local cfg = group and ns.db[group]
        if cfg then
            local cave = ns.MapCaves and ns.MapCaves[mapID] and GroundInCave(group)
            pin:SetShown((PinsShown(group) or cave) and not HiddenUnexplored(pin, group, mapID)
                and not HiddenOutside(pin, group, mapID) and not HiddenUntracked(pin, group, tracked)
                and not HiddenDouble(pin, group, ours, handIn))
            -- our pins add their own dimming (party objectives) on top of the group alpha
            if template == "BFIQuestiePinTemplate" then
                pin:ApplyCurrentAlpha()
            else
                pin:SetAlpha(ns.PinAlpha(group))
            end
        end
    end)
end

-- A pin layer's size right now (group: its settings group; own: its size
-- setting). In town view it's the layer's town size (townView.sizes[group]),
-- or its own times townView.pinScale where that isn't set. On a map scaled
-- down below pins.minMapScale, pins keep the size they'd have at that scale,
-- so they stay readable.
-- (view: "townView" or "cityView", the same for a capital in city view)
function ns.TownPinSize(group, view)
    local t = ns.db[view or "townView"]
    -- (in town and city view the turn-ins are the givers' size: one slider for both, the user 2026-11-08)
    if group == "turnins" then
        return t.sizes.questie or (ns.db.turnins and ns.db.turnins.scale or 1) * (t.pinScale or 1)
    end
    return t.sizes[group] or (ns.db[group] and ns.db[group].scale or 1) * (t.pinScale or 1)
end

-- (objective pins and dots: one size everywhere, the Quests page's; town view's own row for them didn't move
-- the dots and read as broken, the user 2026-11-08 by the Relay: decoupled)
local NOT_IN_TOWN = { spots = true, ground = true }
ns.PIN_NOT_IN_TOWN = NOT_IN_TOWN

function ns.PinScale(group, own)
    local s = own or 1
    if NOT_IN_TOWN[group] then
        -- (as on the map)
    elseif ns.InCityView and ns.InCityView() then
        s = ns.TownPinSize(group, "cityView")
    elseif ns.InTownView and ns.InTownView() then
        s = ns.TownPinSize(group)
    end
    local map = BattlefieldMapFrame
    local floor = ns.db.pins.minMapScale or 0
    if map and floor > 0 then
        -- (the slider's scale: Waymark's size isn't a shrunken map)
        local scale = map:GetEffectiveScale() / UIParent:GetEffectiveScale() / ns.AddonScale()
        if scale > 0 then s = s * math.max(1, floor / scale) end
    end
    return s
end

-- Objective size goes through the map's own pin scale (0.6 on this map), so
-- Blizzard keeps positions right. Pins without scaling limits, like the quest
-- area overlay, ignore it.
function ns.ApplyScales(group)
    local map = BattlefieldMapFrame
    if not map or not ns.db then return end
    if group == "objectives" and ns.basePinScale then
        local s = ns.basePinScale * ns.PinScale("objectives", ns.db.objectives.scale)
        -- SetGlobalPinScale may rely on EnumerateAllPins, which this client lacks;
        -- the field is what pins read, and we rescale them ourselves below
        if not (map.SetGlobalPinScale and pcall(map.SetGlobalPinScale, map, s)) then
            map.globalPinScale = s
        end
    end
    EachPin(map, function(pin)
        if pin.ApplyCurrentScale then pin:ApplyCurrentScale() end
    end)
end

-- Blizzard's quest pins set right-click pass-through when placed, which the game
-- blocks in combat once our code is on the path (see ns.SafePassthrough). So in
-- combat a refresh waits for combat to end; on a map change the old pins go now.
local deferred = {}
local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:SetScript("OnEvent", function()
    for provider in pairs(deferred) do
        deferred[provider] = nil
        pcall(provider.RefreshAllData, provider)
    end
end)

-- Tags every pin a provider creates so it can be handled as a group
local function TrackPins(map, provider, group)
    local orig = provider.RefreshAllData
    provider.RefreshAllData = function(self, ...)
        if InCombatLockdown() then
            if self.bfiDrawnMap ~= map:GetMapID() and self.RemoveAllData then
                pcall(self.RemoveAllData, self)
            end
            deferred[self] = true
            if ns.Trail then ns.Trail("in a fight, held: " .. tostring(group)) end
            return
        end
        self.bfiDrawnMap = map:GetMapID()
        local before = {}
        pcall(EachPin, map, function(pin) before[pin] = true end)
        orig(self, ...)
        pcall(EachPin, map, function(pin)
            if not before[pin] then pin.bfiGroup = group end
        end)
        pcall(ns.ApplyGroups)
    end
end

-- The game's other pins set themselves up the same way, each one blocked in a fight: rares and
-- points of interest appear mid-fight (a friend's 1.2.2: SetPropagateMouseClicks and
-- SetPassThroughButtons, from AcquirePin). Same wait for those that place pins as things change.
-- Not the flags, the corpse, or the group's and the art's own pins, wanted at once and made once.
local WAIT_IN_COMBAT = { "VignetteDataProviderMixin", "AreaPOIDataProviderMixin", "AreaPOIEventDataProviderMixin",
    "GossipDataProviderMixin", "FlightPointDataProviderMixin", "PetTamerDataProviderMixin", "DigSiteDataProviderMixin",
    "DungeonEntranceDataProviderMixin", "MapLinkDataProviderMixin", "SelectableGraveyardDataProviderMixin",
    "EncounterJournalDataProviderMixin", "QuestOfferDataProviderMixin" }
local function GamePinsWait(map)
    local base = MapCanvasDataProviderMixin and MapCanvasDataProviderMixin.RefreshAllData
    local wait = {}
    for _, name in ipairs(WAIT_IN_COMBAT) do
        local mixin = _G[name]
        if mixin and mixin.RefreshAllData and mixin.RefreshAllData ~= base then wait[mixin.RefreshAllData] = name end
    end
    for provider in pairs(map.dataProviders or {}) do
        local orig = provider.RefreshAllData
        local name = wait[orig]
        if name then
            provider.bfiDrawnMap = map:GetMapID()  -- (what's on the map now is this map's)
            provider.RefreshAllData = function(self, ...)
                if InCombatLockdown() then
                    if self.bfiDrawnMap ~= map:GetMapID() and self.RemoveAllData then
                        pcall(self.RemoveAllData, self)
                    end
                    deferred[self] = true
                    if ns.Trail then ns.Trail("in a fight, held: " .. name) end
                    return
                end
                self.bfiDrawnMap = map:GetMapID()
                return orig(self, ...)
            end
        end
    end
end

-- The corpse's tombstone is only looked for as the map opens or changes: fine for the world map,
-- but ours stays open, so dying and releasing drew nothing. So it's looked for at those moments too.
local function CorpseFollows(map)
    local mixin = DeathMapDataProviderMixin
    local provider
    for p in pairs(mixin and map.dataProviders or {}) do
        if p.RefreshAllData == mixin.RefreshAllData then provider = p end
    end
    if not provider then return end
    local function Look()
        if InCombatLockdown() then
            deferred[provider] = true
            return
        end
        pcall(provider.RefreshAllData, provider)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_DEAD")
    f:RegisterEvent("PLAYER_ALIVE")   -- (released: a ghost, the corpse has a place)
    f:RegisterEvent("PLAYER_UNGHOST")
    f:SetScript("OnEvent", function()
        Look()
        C_Timer.After(1, Look)  -- (in case the game knows the place a moment later)
    end)
end

local function AddProvider(map, mixin, label, group)
    if not mixin then
        Log(label, "provider not found, skipping")
        return
    end
    local provider = CreateFromMixins(mixin)
    if group then TrackPins(map, provider, group) end
    if group == "areas" then ns.questAreas = provider end  -- (QuestGround thins its border as you zoom)
    local ok, err = pcall(map.AddDataProvider, map, provider)
    if not ok then
        -- half set up (Classic Era's quest provider): it would error on every map change
        if not ns.FOREVER then pcall(map.RemoveDataProvider, map, provider) end
        Log(label, "failed:", err)
        return nil
    end
    return provider
end

-- Resize ----------------------------------------------------------------

-- Waymark's size: every frame of ours bigger or smaller together, without the
-- game's UI scale. The map's scale is ns.db.scale times this; our windows on
-- UIParent register with ns.AddonWindow; things kept "the same size on screen"
-- on the map use ns.AddonScale() / the map's scale. Pins stay in step with the map.
ns.MIN_ADDON_SCALE, ns.MAX_ADDON_SCALE = 0.7, 2
function ns.AddonScale() return ns.db and ns.db.addonScale or 1 end
function ns.MapScale() return ns.db.scale * ns.AddonScale() end

-- save: called after a size change, to keep the window's saved spot in step
local addonWindows = {}
function ns.AddonWindow(f, save)
    addonWindows[f] = save or true
    f:SetScale(ns.AddonScale())
    return f
end

-- each stays where it is on screen. Not while the slider is held: the settings
-- window is one of these, and would slide out from under the cursor.
local windowsWaiting
local function ScaleWindows()
    if IsMouseButtonDown("LeftButton") then
        C_Timer.After(0.1, ScaleWindows)
        return
    end
    windowsWaiting = nil
    local g = ns.AddonScale()
    for f, save in pairs(addonWindows) do
        local k = f:GetScale() / g
        if math.abs(k - 1) > 0.001 then
            local p, rel, rp, x, y = f:GetPoint(1)
            local one = p and f:GetNumPoints() == 1
            f:SetScale(g)
            if one then
                f:ClearAllPoints()
                f:SetPoint(p, rel, rp, x * k, y * k)
            end
            if save ~= true then save() end
        end
    end
end

function ns.ApplyAddonScale()
    local map = BattlefieldMapFrame
    if map then
        map:SetScale(ns.MapScale())
        if ns.RestoreMapPosition then ns.RestoreMapPosition() end
        if ns.ApplyChromeScale then ns.ApplyChromeScale() end
        if ns.RefreshZoomLevels then ns.RefreshZoomLevels() end
        pcall(ns.ApplyScales, "objectives")
    end
    if ns.Docked and ns.Docked() and ns.ApplyDock then ns.ApplyDock() end
    if ns.UpdateTracker then ns.UpdateTracker(true) end
    if ns.ApplyQuestWindow then ns.ApplyQuestWindow("scale") end
    if ns.UpdateClock then ns.UpdateClock() end
    if not windowsWaiting then
        windowsWaiting = true
        ScaleWindows()
    end
end

function ns.SetScale(s)
    s = math.max(ns.MIN_MAP_SCALE, math.min(ns.MAX_MAP_SCALE, s))
    -- (the scale the map has now: the slider has already written the new one)
    local old = BattlefieldMapFrame and BattlefieldMapFrame:GetScale() / ns.AddonScale() or s
    ns.db.scale = s
    if BattlefieldMapFrame then BattlefieldMapFrame:SetScale(ns.MapScale()) end
    -- the map keeps its size on screen: the scale is the size of what's on it
    -- (pins, text, border). Its size is the corner grip's. (Scale and size each
    -- changing the map on screen let them pile up: a tiny map at scale 3.)
    -- A loaded setup brings its own sizes (Setups.lua: keepSizeOff).
    if math.abs(old - s) > 0.001 and ns.KeepScreenSize and not ns.keepSizeOff then ns.KeepScreenSize(old / s) end
    -- a moved map keeps its top-left corner where it is (MapControls)
    if ns.RestoreMapPosition then ns.RestoreMapPosition() end
    -- the close X and our buttons keep their size on screen (Options)
    if ns.ApplyChromeScale then ns.ApplyChromeScale() end
    -- the zoom levels' art size on screen changes with the scale (MapControls'
    -- ArtX), and a scaled-down map's pins keep a readable size (ns.PinSize)
    if ns.RefreshZoomLevels then ns.RefreshZoomLevels() end
    pcall(ns.ApplyScales, "objectives")
end

local function SetupResize(map)
    map:SetScale(ns.MapScale())
    map:HookScript("OnShow", function() map:SetScale(ns.MapScale()) end)

    local grip = CreateFrame("Button", nil, map)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -2, 2)
    ns.debugFrames.grip = grip
    grip:SetFrameStrata("DIALOG")
    grip:SetHitRectInsets(-7, -7, -7, -7)  -- (a miss lands on the map and pans it: an easier target)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

    -- drag: the map's width and height (MapControls, Shape), nothing else (the
    -- scale is What's shown's "Pin & text size" slider). Right-click: the game's size.
    local startX, startY, startW, startH, sizing
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        sizing = ns.SetMapSize ~= nil
        if not sizing then return end
        startX, startY = GetCursorPosition()
        -- (from the size it is now, so the corner stays under the cursor)
        startW, startH = map:GetWidth(), map:GetHeight()
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local s = map:GetEffectiveScale()
            ns.SetMapSize(startW + (x - startX) / s, startH + (startY - y) / s, true)
        end)
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            if ns.SetMapSize then ns.SetMapSize(nil, nil) end
            return
        end
        grip:SetScript("OnUpdate", nil)
        -- let go: the size it was dragged to (with auto shape, this zone's)
        if sizing then ns.SetMapSize(map:GetWidth(), map:GetHeight()) end
        if ns.RefreshControls then ns.RefreshControls() end
    end)
    grip:SetScript("OnEnter", function()
        GameTooltip:SetOwner(grip, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Resize")
        local auto = ns.db.mapFrame.autoWidth and ns.db.mapFrame.rememberShapes
        if auto then GameTooltip:AddLine("Auto shape: a drag is kept for this zone", 1, 1, 1, true) end
        ns.Hints({ { "Drag", "size and shape" }, { "Right-click", auto and "this zone automatic again" or "default aspect" } })
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Settings --------------------------------------------------------------

-- Called by every options control after it writes its value
-- turn-ins share the quest givers' look (one set of controls on the Quests
-- page); only their Show stays their own
local SHARED_WITH_TURNINS = { alpha = true, scale = true, iconSet = true }
function ns.ShareQuestLook()
    local q, t = ns.db.questie, ns.db.turnins
    if not (q and t) then return end
    for k in pairs(SHARED_WITH_TURNINS) do t[k] = q[k] end
end

function ns.OnSettingChanged(group, key)
    -- the toggle strip on the map follows changes made in the options window
    if ns.RefreshToggles then ns.RefreshToggles() end
    if group == "perf" then  -- (performance mode: everything it touches, again)
        ns.OnSettingChanged("detail", "shown")
        ns.OnSettingChanged("ground", "shown")
        ns.OnSettingChanged("clearView", "on")
        ns.OnSettingChanged("browse", "zoneArt")
        if ns.UpdateMapHour then ns.UpdateMapHour() end
        if ns.ZoneArtUnwarm then ns.ZoneArtUnwarm() end
        if not (ns.Perf("art") or ns.Perf("warm")) and ns.ZoneArtWarm then ns.ZoneArtWarm() end
        return
    end
    if group == "notebook" and ns.NotebookRefresh then ns.NotebookRefresh() end
    if group == "questie" and SHARED_WITH_TURNINS[key] then
        ns.ShareQuestLook()
        if key == "scale" then ns.ApplyScales("turnins") end
    end
    if group == nil and key == "scale" then
        ns.SetScale(ns.db.scale)
    elseif group == nil and key == "addonScale" then
        ns.ApplyAddonScale()
    elseif (QUESTIE_GROUPS[group] and (key == "shown" or key == "color" or key == "plain"
                                      or key == "spacing" or key == "maxPer"))
        or (group == "ground" and (key == "shown" or key == "look")) then  -- ("pins": the spot pins)
        if ns.RedrawQuestie then ns.RedrawQuestie() end
    elseif group == "waypoints" and key == "shown" then
        if ns.RedrawWaypoints then ns.RedrawWaypoints() end
    elseif group == "fishing" then
        if ns.RedrawFishing then ns.RedrawFishing() end
    elseif group == "rares" and (key == "shown" or key == "rsIcons") then
        if ns.RedrawRares then ns.RedrawRares() end
    elseif group == "townsfolk" and key ~= "alpha" and key ~= "scale" then
        if ns.RedrawTownsfolk then ns.RedrawTownsfolk() end
    elseif group == "optionsText" then
        if ns.RebuildOptionsPages then ns.RebuildOptionsPages() end
    elseif group == "pins" or ((group == "townView" or group == "cityView") and (key == "pinScale" or key == "sizes")) then
        ns.ApplyScales("objectives")  -- (every pin's size: ns.PinScale)
    elseif group == "tracker" then
        if ns.UpdateTracker then ns.UpdateTracker(true) end
    elseif group == "questlog" then
        if ns.ApplyQuestWindow then ns.ApplyQuestWindow(key) end
        -- (the tracker can follow the log's text parts: tracker.textAsLog)
        if key and key:sub(1, 4) == "text" and ns.UpdateTracker then ns.UpdateTracker(true) end
    elseif group == "townView" and key == "enabled" then
        -- all of town view at once: decide "in town" afresh, then its zoom,
        -- pin sizes, townsfolk list and profile follow
        if ns.UpdateTown then ns.UpdateTown(true) end
        if ns.ApplyMapControls then ns.ApplyMapControls("zoom") end  -- (auto-zoom decides afresh)
    elseif (group == "townView" or group == "cityView")
       and (key == "ownTypes" or key == "types" or key == "myProfessionsOnly") then
        if ns.RedrawTownsfolk then ns.RedrawTownsfolk() end
    elseif group == "mapFrame" or group == "zoom" then
        if ns.ApplyMapControls then ns.ApplyMapControls(group) end
    elseif group == "detail" then
        if ns.UpdateDetail then ns.UpdateDetail(true) end
        if key == "sharpArt" then
            if ns.SharpenMapArt then ns.SharpenMapArt() end
            if ns.UpdateExplore then ns.UpdateExplore(true) end  -- (its pieces too)
        end
    elseif group == "line" then
        if ns.UpdateLine then ns.UpdateLine() end
    elseif group == "ink" then
        if ns.UpdateInk then ns.UpdateInk() end
    elseif group == "gather" and key ~= "alpha" and key ~= "scale" then
        if ns.RedrawGather then ns.RedrawGather() end
    elseif group == "dungeon" then
        if ns.UpdateDungeon then ns.UpdateDungeon() end
    elseif group == "collapse" then
        if ns.ApplyCollapse then ns.ApplyCollapse() end
    elseif group == "clickThrough" then
        if ns.ApplyClickThrough then ns.ApplyClickThrough() end
    elseif group == "clearView" then
        if ns.ApplyClearView then ns.ApplyClearView() end
        if ns.RedrawFishing then ns.RedrawFishing() end  -- (no wash on a zone's map in clear view)
    elseif group == "dock" then
        -- (the corner ticked again: your own spot from a Ctrl-drag goes, or it would still win)
        if key == "corner" and ns.db.dock.corner and ns.DockSpotReset then ns.DockSpotReset() end
        if ns.ApplyDock then ns.ApplyDock() end
    elseif group == "zoneName" then
        if ns.UpdateZoneName then ns.UpdateZoneName() end
    elseif group == "browse" then
        if ns.UpdateZoneName then ns.UpdateZoneName() end  -- (silver)
        if key == "continentGivers" and ns.RedrawQuestie then ns.RedrawQuestie() end
        -- (the fade's stops only change opacities: no rebuild while one is dragged)
        -- (zoneWash too: only the wash's opacity changes; a rebuild relaid every zone map)
        local fade = key == "fadeFrom" or key == "fadeFull" or key == "detailFull" or key == "zoneWash"
        if fade and ns.UpdateZoneArt then ns.UpdateZoneArt()
        elseif ns.RebuildZoneArt then ns.RebuildZoneArt() end
    elseif group == "cave" then
        if ns.UpdateCave then ns.UpdateCave() end
        -- cave.classicArrow also sets the zone map's arrow (MapControls)
        if ns.ApplyMapControls then ns.ApplyMapControls(group) end
    elseif group == "profiles" then
        if ns.UpdateProfile then ns.UpdateProfile() end
    elseif group == "party" and key == "classColors" then
        if ns.ApplyMapControls then ns.ApplyMapControls(group) end
    elseif group == "dungeons" and (key == "shown" or key == "continent") then
        if ns.RedrawDungeonEntrances then ns.RedrawDungeonEntrances() end
    elseif group == "learned" and key ~= "alpha" and key ~= "scale" then
        if ns.RedrawLearned then ns.RedrawLearned() end
    elseif group == "explore" then
        if ns.UpdateExplore then ns.UpdateExplore(true) end
        if ns.UpdateZoneArt then ns.UpdateZoneArt() end  -- (the fog's look there too)
    elseif group == "border" then
        if ns.UpdateStyle then ns.UpdateStyle() end
    elseif group == "toggles" then
        if ns.LayoutToggles then ns.LayoutToggles() end
    elseif group == "questie" and key == "iconSet" then
        if ns.RedrawQuestie then ns.RedrawQuestie() end
    elseif key == "scale" then
        ns.ApplyScales(group)
    end
    pcall(ns.ApplyGroups)
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    if ns.UpdateQuickButton then ns.UpdateQuickButton() end
    if ns.UpdateCoords then ns.UpdateCoords() end
    if group == "clock" and ns.UpdateClock then ns.UpdateClock() end
    if group == "softEdges" and ns.UpdateSoftEdges then ns.UpdateSoftEdges() end
    if group == "mapHour" and ns.UpdateMapHour then ns.UpdateMapHour() end
    if ns.RefreshControls then ns.RefreshControls() end
end

-- Quests ------------------------------------------------------------------

-- Quest givers, turn-ins and objective spots on this map, from QuestieDB
-- (QuestData.lua), only the layers that are switched on
-- the zones on a continent and where each sits on it: { mapID, left, right,
-- top, bottom } (0..1 of the continent), cached
local zoneRects = {}
local function ZonesOn(mapID)
    local list = zoneRects[mapID]
    if list then return list end
    list = {}
    local T = Enum and Enum.UIMapType
    if T and C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap then
        local ok, children = pcall(C_Map.GetMapChildrenInfo, mapID, T.Zone)
        for _, info in ipairs(ok and children or {}) do
            local ok2, l, r, t, b = pcall(C_Map.GetMapRectOnMap, info.mapID, mapID)
            if ok2 and l and r > l and b > t then list[#list + 1] = { info.mapID, l, r, t, b } end
        end
    end
    zoneRects[mapID] = list
    return list
end

local function IsContinent(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent or false
end

-- On a continent you browse to (Browse.lua): every zone's quest givers, moved
-- to where the zone sits on it (browse.continentGivers). Turn-ins and spots
-- stay on the zone maps, and so do low-level (grey) givers: with them Kalimdor had 1156
-- pins and the game stopped our scripts. Zones not built yet are built for at most
-- GIVERS_BUDGET ms a frame (all at once was a 50 ms hitch on Kalimdor's first open): returns
-- out, or true as its second answer while some are still to come, and nothing is drawn yet.
local GIVERS_BUDGET = 5
local function ContinentGivers(mapID, out)
    if not (ns.db.browse.continentGivers and ns.IsShown("questie")) then return out end
    local t0 = debugprofilestop()
    for _, z in ipairs(ZonesOn(mapID)) do
        if ns.QuestIconsKept and not ns.QuestIconsKept(z[1]) then
            if debugprofilestop() - t0 > GIVERS_BUDGET then return out, true end
            ns.QuestIcons(z[1])
        end
    end
    for _, z in ipairs(ZonesOn(mapID)) do
        local id, l, r, t, b = z[1], z[2], z[3], z[4], z[5]
        for _, icon in ipairs(ns.QuestIcons(id)) do
            if icon.group == "questie" and not icon.trivial then
                local c = {}
                for k, v in pairs(icon) do c[k] = v end
                c.x = (l + icon.x / 100 * (r - l)) * 100
                c.y = (t + icon.y / 100 * (b - t)) * 100
                out[#out + 1] = c
            end
        end
    end
    return out
end

-- the quest pins shown on a zone (Cave.lua: the zone's pins in a minimap-style cave)
function ns.QuestIconsShown(mapID, inCave)
    local out = {}
    if not ns.QuestIcons then return out end
    for _, icon in ipairs(ns.QuestIcons(mapID)) do
        if (PinsShown(icon.group, true) or (inCave and GroundInCave(icon.group))) and not icon.thinned then
            out[#out + 1] = icon
        end
    end
    return out
end

-- A cave's own map (OpenMap's caves, ns.MapCaves: Jangolode Mine...): the quest data is the
-- zone's, so its pins inside the cave, moved to where the cave lies on the zone
local function CaveIcons(mapID, out)
    if not (ns.MapCaves and ns.MapCaves[mapID] and C_Map.GetMapRectOnMap and Enum and Enum.UIMapType) then return end
    local zone = MapUtil and MapUtil.GetMapParentInfo and MapUtil.GetMapParentInfo(mapID, Enum.UIMapType.Zone, true)
    if not zone then return end
    local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, mapID, zone.mapID)
    if not (ok and l and r > l and b > t) then return end
    -- (objective spots only of the quests the log files under the cave's name, when it files
    -- any there: the ones above ground over the cave stay off it; the user, 2026-11-03)
    local only = ns.QuestsUnder and ns.QuestsUnder(ns.MapCaves[mapID][1])
    for _, icon in ipairs(ns.QuestIconsShown(zone.mapID, true)) do
        local x, y = (icon.x / 100 - l) / (r - l), (icon.y / 100 - t) / (b - t)
        if x >= 0 and x <= 1 and y >= 0 and y <= 1 and not (only and icon.group == "spots" and not only[icon.id]) then
            local c = {}
            for k, v in pairs(icon) do c[k] = v end
            c.x, c.y = x * 100, y * 100
            out[#out + 1] = c
        end
    end
    return out
end

local function GetQuestieIcons(mapID)
    local out = {}
    if not ns.QuestIcons then return out end
    if IsContinent(mapID) then return ContinentGivers(mapID, out) end
    if CaveIcons(mapID, out) then return out end
    return ns.QuestIconsShown(mapID)
end

BFIQuestieProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFIQuestieProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, "BFIQuestiePinTemplate")
end

-- Blizzard-initiated refreshes only mark our pins as stale;
-- the ticker in SetupQuestie does the actual drawing.
function BFIQuestieProviderMixin:RefreshAllData()
    self:RemoveAllData()
    self.dirty = true
end

function BFIQuestieProviderMixin:OnMapChanged()
    self:RefreshAllData()
end

local function DrawPins(provider)
    local map = provider:GetMap()
    if not provider.ready or not map:IsShown() then
        provider.dirty = true
        return
    end
    local mapID = map:GetMapID()
    if not mapID then return end

    local t0 = debugprofilestop()  -- (the pieces timed for /bfi check's frame cost)
    local icons, more = GetQuestieIcons(mapID)
    provider.more = more   -- (the ticker comes back next frame)
    ns.CostAdd("Pins icons", t0)
    if more then return end   -- (one draw once all are built, not every pin again each frame)
    t0 = debugprofilestop()
    provider:RemoveAllData()
    ns.CostAdd("Pins remove", t0)
    t0 = debugprofilestop()

    -- hidden groups are already filtered out in GetQuestieIcons
    local okCount, failCount, firstErr, firstName = 0, 0, nil, nil
    for _, icon in ipairs(icons) do
        local ok, err = pcall(map.AcquirePin, map, "BFIQuestiePinTemplate", icon)
        if ok then
            okCount = okCount + 1
        else
            failCount = failCount + 1
            if not firstErr then
                firstErr = err
                firstName = tostring(icon.name) .. " (quest " .. tostring(icon.id) .. ")"
            end
        end
    end
    ns.CostAdd("Pins acquire " .. (okCount >= 100 and "100+" or okCount >= 30 and "30-99" or "<30"), t0)
    -- (a quest hovered in the tracker: its new spots glow too)
    if ns.TrackerRefreshGlow then ns.TrackerRefreshGlow() end

    if failCount > 0 then
        provider.dirty = true
        provider.failStreak = (provider.failStreak or 0) + 1
        -- a single early failure is retried automatically; only report repeated ones
        if provider.failStreak == 3 then
            Log(string.format("Pins keep failing: %d ok, %d failed (map %s). First: %s -> %s",
                okCount, failCount, tostring(mapID), firstName, tostring(firstErr)))
        end
    else
        provider.failStreak = 0
    end
end

local function SetupQuestie(map)
    local ticker, elapsed, lastSig = ns.TimedFrame("Pins tick"), 0, nil
    local lastLook
    local provider

    if not (ns.QuestSource and ns.QuestSource()) then
        Log("No quest data (Waymark's or QuestieDB): no quest givers, turn-ins or objective spots")
    else
        provider = CreateFromMixins(BFIQuestieProviderMixin)
        local ok, err = pcall(map.AddDataProvider, map, provider)
        if not ok then
            Log("Quest provider failed:", err)
            provider = nil
        else
            -- lets the options force a redraw on the next frame
            function ns.RedrawQuestie()
                if ns.BumpQuests then ns.BumpQuests() end
                provider.dirty = true
                elapsed = 1
            end
        end
    end

    -- also drives ApplyGroups, so it runs even without QuestieDB
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < (provider and provider.more and 0 or 1) or not map:IsVisible() then return end
        elapsed = 0

        if provider then
            provider.ready = true
            local mapID = map:GetMapID()
            if mapID then
                -- (a Questie theme changed: the spots follow it, no reload)
                local look = ns.QuestieLookSig()
                if lastLook and look ~= lastLook then ns.RedrawQuestie() end
                lastLook = look
                -- QuestData's version changes with the quest log, level, skills...
                -- (player level too, so difficulty colors follow level-ups)
                local sig = table.concat({ mapID, UnitLevel("player"), ns.QuestVersion() }, ":")
                if provider.dirty or provider.more then
                    provider.dirty, provider.more = false, false
                    lastSig = nil
                end
                if sig ~= lastSig then
                    lastSig = sig
                    local t0 = debugprofilestop()
                    local ok2, err2 = pcall(DrawPins, provider)
                    ns.CostAdd("Pins draw", t0)
                    if not ok2 then Log("Quest pin draw error:", err2) end
                end
            end
        end

        local t0 = debugprofilestop()
        local ok3, err3 = pcall(ns.ApplyGroups)
        ns.CostAdd("Pins groups", t0)
        if not ok3 and not ns.groupErrorShown then
            ns.groupErrorShown = true
            Log("visibility error:", err3)
        end
    end)
end

-- Frame levels ----------------------------------------------------------

-- The Battlefield Map only registers frame levels for its own pins. Pins whose
-- level type isn't registered fall to the bottom, underneath the map tiles.
local function SetupFrameLevels(map)
    local mgr = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    if not mgr then
        Log("no pin frame levels manager, skipping")
        return
    end
    local maxQuests = C_QuestLog and C_QuestLog.GetMaxNumQuests and C_QuestLog.GetMaxNumQuests() or 25
    -- all under the player and party arrows: each one lands just below that level,
    -- so they stack in the order written here
    local under = "PIN_FRAME_LEVEL_VEHICLE_BELOW_GROUP_MEMBER"
    local function Add(level, range)
        if not (mgr.InsertFrameLevelBelow and mgr:InsertFrameLevelBelow(level, under, range)) then
            mgr:AddFrameLevel(level, range)
        end
    end
    local ok, err = pcall(function()
        Add("PIN_FRAME_LEVEL_QUEST_BLOB")
        Add("PIN_FRAME_LEVEL_ACTIVE_QUEST", maxQuests)
        Add("PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST")
        Add("PIN_FRAME_LEVEL_BFI_GATHER")    -- gathering nodes, lowest of ours
        Add("PIN_FRAME_LEVEL_BFI_TOWNSFOLK") -- townsfolk
        Add("PIN_FRAME_LEVEL_BFI_SPOTS")    -- objective spots, under givers/turn-ins
        Add("PIN_FRAME_LEVEL_BFI_RARES")    -- RareScanner, above spots
        Add("PIN_FRAME_LEVEL_BFI_DUNGEONS") -- dungeon entrances
        Add("PIN_FRAME_LEVEL_BFI_LEARNED")  -- quest givers we learned, with QuestieDB's
        Add("PIN_FRAME_LEVEL_BFI_QUESTIE")
        -- (pins made before this keep their old level until told)
        if map.ReapplyPinFrameLevels then
            for _, level in ipairs({ under, "PIN_FRAME_LEVEL_BATTLEFIELD_FLAG", "PIN_FRAME_LEVEL_GROUP_MEMBER",
                                     "PIN_FRAME_LEVEL_VEHICLE_ABOVE_GROUP_MEMBER", "PIN_FRAME_LEVEL_CORPSE" }) do
                map:ReapplyPinFrameLevels(level)
            end
        end
    end)
    if not ok then Log("frame levels failed:", err) end
end

-- Debug -----------------------------------------------------------------

local function TexInfo(t)
    if not t then return "no texture" end
    -- textures have no GetEffectiveAlpha in this client
    return string.format("atlas=%s tex=%s blend=%s alpha=%.2f layer=%s",
        tostring(t:GetAtlas()), tostring(t:GetTexture()), tostring(t:GetBlendMode()),
        t:GetAlpha(), tostring((t:GetDrawLayer())))
end

local function Debug()
    local map = BattlefieldMapFrame
    if not map or not map:IsShown() then
        Log("open the Battlefield Map first")
        return
    end
    local canvas = map:GetCanvas()
    Log("map", map:GetMapID(), "canvas level", canvas:GetFrameLevel(),
        "pin scale", tostring(map.globalPinScale))
    if ns.DetailInfo then Log(ns.DetailInfo()) end

    local groups = {}
    EachPin(map, function(pin, key)
        local g = groups[key]
        if not g then
            g = { n = 0, min = math.huge, max = 0, alpha = pin:GetEffectiveAlpha() }
            groups[key] = g
        end
        local lvl = pin:GetFrameLevel()
        g.n, g.min, g.max = g.n + 1, math.min(g.min, lvl), math.max(g.max, lvl)
    end)
    for key, g in pairs(groups) do
        Log(string.format("%s: %d pins, levels %d-%d, alpha %.2f", key, g.n, g.min, g.max, g.alpha))
    end

    for _, child in ipairs({ canvas:GetChildren() }) do
        if not child.pinTemplate then
            Log(string.format("layer %s: level %d, alpha %.2f",
                tostring(child:GetDebugName()), child:GetFrameLevel(), child:GetEffectiveAlpha()))
        end
    end

    for pin in map:EnumeratePinsByTemplate("BFIQuestiePinTemplate") do
        Log("mine:", pin.questName, TexInfo(pin.Icon))
        break
    end
end

-- Setup -----------------------------------------------------------------

local function Setup()
    local map = BattlefieldMapFrame
    if not map or map.WaymarkDone then return end
    map.WaymarkDone = true

    ns.basePinScale = map.GetGlobalPinScale and map:GetGlobalPinScale() or map.globalPinScale or 1

    SetupFrameLevels(map)
    if ns.GuardMapWheel then ns.GuardMapWheel(map) end  -- (first: before the wheel hooks)
    SetupResize(map)
    -- (Forever only: the game's other providers wait out fights, and quest objectives and areas
    -- are drawn; on Era the game's quest providers failed half set up, chat spam every login)
    if ns.FOREVER then
        GamePinsWait(map)
        -- (the game's quest objectives and areas, drawn by Waymark: QuestPOI.lua says why)
        if ns.SetupQuestPOI then ns.SetupQuestPOI(map, AddProvider) end
    end
    CorpseFollows(map)
    SetupQuestie(map)
    if ns.SetupQuestGround then ns.SetupQuestGround(map) end
    if ns.SetupWilds then ns.SetupWilds(map) end
    if ns.SetupWaypoints then ns.SetupWaypoints(map) end
    if ns.SetupRares then ns.SetupRares(map) end
    if ns.SetupTownsfolk then ns.SetupTownsfolk(map) end
    if ns.SetupGather then ns.SetupGather(map) end
    if ns.SetupLearned then ns.SetupLearned(map) end
    if ns.SetupTracker then ns.SetupTracker(map) end
    if ns.SetupMapControls then ns.SetupMapControls(map) end
    if ns.SetupDetail then ns.SetupDetail(map) end
    if ns.SetupLine then ns.SetupLine(map) end
    if ns.SetupDungeon then ns.SetupDungeon(map) end
    if ns.SetupCave then ns.SetupCave(map) end
    if ns.SetupExplore then ns.SetupExplore(map) end
    if ns.SetupInk then ns.SetupInk(map) end
    if ns.SetupCamps then ns.SetupCamps(map) end  -- (the book's camps on the zone maps: Camps.lua, dev copy only for now)
    if ns.SetupDangers then ns.SetupDangers(map) end  -- (what kills here, on and beside the dungeon map: Dangers.lua, dev copy only for now)
    if ns.SetupZoneArt then ns.SetupZoneArt(map) end
    if ns.SetupStyle then ns.SetupStyle(map) end
    if ns.SetupZoneName then ns.SetupZoneName(map) end
    if ns.SetupBrowse then ns.SetupBrowse(map) end
    if ns.SetupTown then ns.SetupTown() end
    if ns.SetupProfiles then ns.SetupProfiles(map) end
    ns.ApplyScales("objectives")
    if ns.SetupQuickButton then ns.SetupQuickButton(map) end
    if ns.SetupCoords then ns.SetupCoords(map) end
    if ns.SetupClock then ns.SetupClock(map) end
    -- The game's own bug, gamepad mode: the map canvas checks edge panning every frame with
    -- ScrollContainer.edgePanDistance, which only SetGamepadFocus sets, and only the world map gets
    -- that. The Battlefield Map's stayed nil: an error a frame (live Forever, the user 2026-11-07, 1007
    -- of them). Given the game's own value; a plain number, read nowhere protected.
    local sc = map.ScrollContainer
    if sc and sc.CheckForEdgePan and sc.edgePanDistance == nil then
        sc.edgePanDistance = (GetCVarNumberOrDefault and GetCVarNumberOrDefault("GamepadMapEdgePanDistance")) or 0
    end
    -- Gamepad UI: A stopped jumping and SetPreferredGamepadInteractTarget was blocked (Caetras and
    -- another CurseForge player, the user 2026-11-08). The map canvas's gamepad code runs on our
    -- map too: UnregisterPin calls every released pin's OnMouseLeave, hovered or not, and
    -- UpdateGamepadCursor enters and leaves pins under the world map's soft cursor. A game quest
    -- pin's leave/enter fires MapCanvas.QuestPin.OnLeave/OnEnter, and the world map's quest list
    -- answers with QuestLogQuests_Update: run from our refreshes, it wrote QuestMapFrame.layoutIndex
    -- under our taint, and the gamepad focus of the quest panel read it and ran tainted from then on.
    -- Our map never has gamepad focus (only the world map is a panel), so: no soft-cursor hover here,
    -- and a released pin is only "left" if it was entered.
    if map.UpdateGamepadCursor and map.UnregisterPin and map.currentPoIPins then
        map.UpdateGamepadCursor = function() end
        map.UnregisterPin = function(self, pin)
            if pin:IsPinSuppressor() then
                tDeleteItem(self.pinSuppressors, pin)
                self:SetPinSuppressionDirty()
            end
            if tContains(self.currentPoIPins, pin) then
                tDeleteItem(self.currentPoIPins, pin)
                if pin.OnExit then pin:OnExit() end
                pin:SetHighlightLocked(false)
                pin:OnMouseLeave()
            end
        end
    end
    if ns.SetupTransports then ns.SetupTransports(map) end
    if ns.SetupFishing then ns.SetupFishing(map) end
    if ns.SetupMapHour then ns.SetupMapHour(map) end
    if ns.SetupMapLife then ns.SetupMapLife(map) end  -- (dev only)
    if ns.SetupCollapse then ns.SetupCollapse(map) end
    if ns.SetupClearView then ns.SetupClearView(map) end
    if ns.SetupSoftEdges then ns.SetupSoftEdges(map) end
    if ns.SetupCutEdit then ns.SetupCutEdit(map) end
    if ns.SetupDock then ns.SetupDock(map) end
    if ns.SetupClickThrough then ns.SetupClickThrough(map) end
    if ns.SetupWelcome then ns.SetupWelcome(map) end
    if ns.SetupReport then ns.SetupReport(map) end
end

-- Blocked actions: the game says which function it blocked in these events (the
-- popup doesn't). Shown in chat and kept, so one during a /reload is shown again
-- after it (the chat from before a reload is gone).
local function ReportBlocked(event, addon, func)
    -- (every addon's, kept across reloads, the last 20: the game's chat line "Interface action
    -- failed because of an AddOn" doesn't say whose; /waymark check and Claude read it)
    WaymarkDB = WaymarkDB or {}
    local all = WaymarkDB.blockedHistory or {}
    all[#all + 1] = { addon = tostring(addon), func = tostring(func), event = event, when = date("%m-%d %H:%M:%S"),
                      where = InCombatLockdown() and "in combat" or "out of combat",
                      map = BattlefieldMapFrame and BattlefieldMapFrame:IsShown() and "map open" or "map closed" }
    while #all > 20 do table.remove(all, 1) end
    WaymarkDB.blockedHistory = all
    if addon ~= addonName then return end
    local when = date("%H:%M:%S")
    local where = InCombatLockdown() and "in combat" or "out of combat"
    -- (Report.lua: a report players can copy into a CurseForge comment, and its link)
    if ns.NoteBlock then pcall(ns.NoteBlock, event, func) end
    Log("|cffff6060blocked:|r", tostring(func), "(" .. event .. ", " .. where .. ", " .. when .. ")",
        ns.ReportLink and ns.ReportLink() or "")
    WaymarkDB = WaymarkDB or {}
    local list = WaymarkDB.blockedLog or {}
    list[#list + 1] = { func = tostring(func), event = event, where = where, when = when }
    while #list > 10 do table.remove(list, 1) end
    WaymarkDB.blockedLog = list
    -- (dev: DevGamepad.lua saves what Waymark tainted; not in releases, so nil there)
    if ns.GamepadTaintProbe and tostring(func):find("Gamepad", 1, true) then pcall(ns.GamepadTaintProbe) end
end

local blockWatch = CreateFrame("Frame")
blockWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
blockWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockWatch:SetScript("OnEvent", function(_, event, addon, func) ReportBlocked(event, addon, func) end)

-- after a reload: repeat what was blocked last time (once), then forget it
local function ShowBlockedFromLastTime()
    local list = WaymarkDB and WaymarkDB.blockedLog
    if not (list and #list > 0) then return end
    C_Timer.After(3, function()
        Log("blocked before the last reload/logout:")
        for _, b in ipairs(list) do
            Log("  " .. b.func .. " (" .. b.event .. ", " .. b.where .. ", " .. b.when .. ")")
        end
        if ns.ReportLink then Log("a report to copy for Waymark's CurseForge page:", ns.ReportLink()) end
        WaymarkDB.blockedLog = nil
    end)
end

-- Open at logout or reload (Dungeon.lua saves showBattlefieldMinimap "1" then): open again after
-- it, wherever you are. The game only does that itself in the open world and battlegrounds, and
-- loads its map too late for our dungeon hooks to catch a reload inside an instance (the user,
-- 2026-11-02: still closed after /reload). A profile that hides the map hides it again after.
local reopenAfterFight
local function ReopenMap()
    if ns.standBy or GetCVar("showBattlefieldMinimap") ~= "1" then return end
    if not BattlefieldMapFrame then
        -- (loaded by our code in a fight, the game's own map pins are blocked as they're made:
        -- SetPassThroughButtons. A guess at a player's 1.2.7 report "in combat", not proved. After the fight.)
        if InCombatLockdown() then
            if not reopenAfterFight then
                reopenAfterFight = CreateFrame("Frame")
                reopenAfterFight:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    ReopenMap()
                end)
            end
            reopenAfterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then pcall(load, "Blizzard_BattlefieldMap") end
    end
    local map = BattlefieldMapFrame
    if map and not map:IsShown() then map:Show() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, name, isReload)
    if event == "PLAYER_ENTERING_WORLD" then
        -- (name is isInitialLogin here; after the game's own handling of the map)
        if (name or isReload) and ns.db then C_Timer.After(0.5, ReopenMap) end
        return
    end
    if name == addonName then
        InitDB()
        if OldCopyRunning() then StandBy() return end
        -- this character's saved setup, if it has one (Setups.lua)
        if ns.SetupSetups then pcall(ns.SetupSetups) end
        ShowBlockedFromLastTime()
        if ns.CreateMinimapButton then ns.CreateMinimapButton() end
        if BattlefieldMapFrame then Setup() end
    elseif name == "Blizzard_BattlefieldMap" and ns.db and not ns.standBy then
        Setup()
    end
end)

-- commands for development only: in a release (no DevBar.lua, so no ns.DevCommands) a player gets the
-- usage line, as for a word we don't know. debug and check stay: they help with bug reports.
local DEV_SLASH = {}
for _, c in ipairs({ "bar", "bosses list", "bosses place", "buttons", "cave", "controls", "cut", "devart", "forevermap",
    "layers", "notes me", "notes ship", "notes shots", "probe", "questart", "questprobe", "shapes", "tour", "town",
    "watch", "where rec", "fillwatch", "padcheck" }) do DEV_SLASH[c] = true end
local function DevOnly(msg)
    return not ns.DevCommands and (DEV_SLASH[msg] or msg:match("^tour ") or msg:match("^quest%s")) and true or false
end
SLASH_BFI1, SLASH_BFI2 = "/waymark", "/bfi"
SlashCmdList.BFI = function(msg)
    if ns.standBy then print(ns.standByMsg) return end
    msg = strtrim(msg or "")
    if DevOnly(msg) then msg = "?" end
    if msg == "debug" then
        Debug()
        return
    end
    -- the last blocked action's report, to copy into a CurseForge comment (Report.lua)
    if msg == "report" then
        if ns.ShowReport then ns.ShowReport() end
        return
    end
    -- (dev commands: the map scale by number, turned words' size; DevCommands.lua, not shipped)
    if ns.DevSlash and ns.DevSlash(msg) then return end
    -- a trace of who gets each click (Controls.lua)
    if msg == "controls" then
        if ns.ToggleControlsTrace then ns.ToggleControlsTrace() end
        return
    end
    if msg == "where rec" then
        if ns.DungeonWhereRecord then ns.DungeonWhereRecord() end
        return
    end
    if msg == "probe" then
        if ns.Probe then ns.Probe() end
        return
    end
    -- every command as a button on a bar (DevBar.lua)
    if msg == "bar" then
        if ns.ToggleDevBar then ns.ToggleDevBar() end
        return
    end
    -- drawing on the map (Ink.lua)
    if msg == "ink" then
        if ns.ToggleInkBar then ns.ToggleInkBar() end
        return
    end
    -- the found notes, the wanderer's dungeon notebook (Notebook.lua)
    -- the generated "watch for" lines of a dungeon, to write from (DungeonWatch.lua)
    if msg == "fillwatch" then
        if ns.ZoneArtTrace then ns.ZoneArtTrace() end
        return
    end
    if msg == "watch" then
        if ns.ToggleDungeonWatchList then ns.ToggleDungeonWatchList() end
        return
    end
    if msg == "notes" then
        if ns.ToggleNotebook then ns.ToggleNotebook() end
        return
    end
    if msg == "notes shots" then  -- (dev: every page, a screenshot each)
        if ns.NotebookShots then ns.NotebookShots() end
        return
    end
    if msg == "notes ship" then  -- (dev: the book as the release has it, unfinished pages locked)
        if ns.NotebookShipView then ns.NotebookShipView() end
        return
    end
    if msg == "notes me" then  -- (dev: writing as a player would)
        if ns.BOOK_AUTHOR and ns.NotebookAsPlayer then ns.NotebookAsPlayer() end
        return
    end
    if msg == "notes write" then
        if ns.NotebookWrite then ns.NotebookWrite() end
        return
    end
    -- dev: hand-adjusting clear view's outlines (CutEdit.lua)
    if msg == "cut" then
        if ns.ToggleCutEdit then ns.ToggleCutEdit() end
        return
    end
    -- what's been learned as you play, in its window (LearnedWindow.lua)
    if msg == "learned" then
        if ns.ToggleLearnedWindow then ns.ToggleLearnedWindow() end
        return
    end
    -- placing boss spots on Blizzard's dungeon maps (Dungeon.lua)
    if msg == "bosses place" then
        if ns.ToggleBossPlacing then ns.ToggleBossPlacing() end
        return
    end
    if msg == "bosses list" then
        if ns.ToggleDevBossList then ns.ToggleDevBossList() end
        return
    end
    if msg == "questprobe" then
        if ns.QuestProbe then ns.QuestProbe() end
        return
    end
    if msg == "questart" then
        if ns.QuestArtProbe then ns.QuestArtProbe() end
        return
    end
    -- quests hidden with Shift-click back on the map
    if msg == "unhide" then
        local n = ns.HiddenQuestCount and ns.HiddenQuestCount() or 0
        if ns.UnhideQuests then ns.UnhideQuests() end
        Log(n .. " hidden quest(s) shown again")
        return
    end
    -- /bfi quest 123: whether that quest shows as available, and why not
    local questID = tonumber(msg:match("^quest%s+(%d+)$") or "")
    if questID then
        Log(ns.ExplainQuest and ns.ExplainQuest(questID) or "no quest data")
        return
    end
    if msg == "check" or msg == "check noreload" then
        if ns.RunCheck then ns.RunCheck(msg == "check noreload") end
        return
    end
    if msg == "tour" or msg:match("^tour ") then
        if ns.RunTour then ns.RunTour(msg:sub(6)) end
        return
    end
    if msg == "layers" then
        local map = BattlefieldMapFrame
        if not map then Log("the map isn't loaded yet") return end
        local explore, top, bottom = ns.CanvasLevels(map)
        Log(string.format("canvas %d; explored art %s; pins %s to %d; our art level %d",
            map:GetCanvas():GetFrameLevel(), tostring(explore), tostring(bottom), top, ns.ArtLevel(map, 0)))
        if ns.ExploreInfo then Log(ns.ExploreInfo()) end
        if ns.DetailInfo then Log(ns.DetailInfo()) end
        return
    end
    if msg == "buttons" then
        for line in (ns.ToggleInfo and ns.ToggleInfo() or "not set up"):gmatch("[^\n]+") do Log(line) end
        return
    end
    if msg == "town" then
        if ns.TownProbe then ns.TownProbe() end
        return
    end
    if msg == "cave" then
        if ns.CaveProbe then ns.CaveProbe() end
        return
    end
    -- testing: Forever's art from Waymark_DevArt, or the substitutes an
    -- Era-only player gets (Art.lua); the art is set as frames are made, so reload
    if msg == "devart" then
        if ns.FOREVER then Log("Forever has its own art: nothing to switch") return end
        WaymarkDB.devArtOff = not WaymarkDB.devArtOff or nil
        Log(WaymarkDB.devArtOff and "dev art off: substitutes, as an Era-only player sees it; reloading"
            or "dev art on (if Waymark_DevArt is installed); reloading")
        ReloadUI()
        return
    end
    -- testing: Forever's maps on Classic Era (Client.lua ns.MapEdition; tools\forever_map.py)
    if msg == "forevermap" then
        if ns.FOREVER then Log("Forever draws its own maps: nothing to switch") return end
        if type(WaymarkForeverMap) ~= "table" then
            Log("Waymark_ForeverMap isn't loaded: run tools\\forever_map.py, enable it, restart the game")
            return
        end
        WaymarkDB.foreverMap = not WaymarkDB.foreverMap or nil
        Log(WaymarkDB.foreverMap and "Forever's maps on: masks, outlines and continent work are Forever's; reloading"
            or "Forever's maps off: Classic Era's own; reloading")
        ReloadUI()
        return
    end
    -- the zones' outlines on each continent, for tools\zone_shapes.py (ZoneArt.lua)
    if msg == "shapes" then
        if ns.SampleZoneShapes then ns.SampleZoneShapes() end
        return
    end
    if msg == "" or msg == "options" then
        ns.ToggleOptions()
    else
        Log(ns.ToggleDevBar and "usage: /waymark (options), /waymark bar (all commands as buttons)" or "usage: /waymark (options)")
    end
end

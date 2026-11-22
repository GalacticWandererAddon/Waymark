# Changelog

## 1.3.2 (2026-11-22)

**Players' bugs fixed, a new sea on the painted continents, and Waymark's land on the game's world map.**

New
- **Waymark's look on the game's own world map.** Two switches in Settings > The map's look, both off as they come:
  - "Shaded land on the game's world map": the same hills and shadows on the game's world map, with unexplored land shown too.
  - "Painted continents on the game's world map": on a continent, each zone's own map, with our sea and coasts.
  Only pictures are laid on that map. Its quest log, its zoom and other addons' pins stay as they are.
- **A new sea on the painted continents**, on Waymark's map and on the game's world map: one sea round each continent, with new rows of waves along the coasts.
- **Coasts redrawn** all round both continents: Stormwind, Dun Morogh, the Wetlands, the Hinterlands, the Eastern Plaguelands, Quel'Thalas, Gilneas, Redridge, Tirisfal, the Blasted Lands, Moonglade, Tanaris, Uldum, Silithus and more.
- On the painted continents, the game's place icons (the houses over the cities) are hidden while the paint shows.
- The resize grip can sit in any corner of the map, in the minimap's place too, and has its own opacity. Shift-drag: the same shape, only bigger or smaller.
- A switch and a size for the two red buttons on the map.
- A key for Waymark's quest log, under More keys in Key bindings.
- As told: "Before this" shows the earlier quests' names; click it for what they told you. Quest chains find more of their earlier and later steps.

Fixed
- Russian text showed as empty squares.
- Tirisfal Glades in clear view was cut off in the west, where Forever added land.
- With QuestieDB installed, the other side's town and its innkeeper could show on your map.
- Quests for another race or side could show (a Night Elf saw a Horde quest).
- Quest givers could stay missing until a /reload.
- Givers of Forever's new quests showed at any level (a level 4 saw level 60 givers).
- Brother Paxton offered Book Inventory before you had the Nibbled-On Book.
- A finished quest's turn-in "?" could be missing on a learned giver.
- Clear view could turn into a full rectangle out of nowhere, when the game put the map on a continent. The zone now stays until there is a new zone map for you. On the tram it keeps your zone's map too.
- The zoom on a zone map was forgotten over a /reload.
- A map that follows you opened on your arrow, then slid over. It now opens where it ends up.
- The campfire marks grew huge when zoomed far in.
- An auctioneer pin on Master Smith Burninate, and innkeeper pins on mount sellers.
- The big map could end up above the screen, out of reach.
- The resize grip could slip under the map, and sat inside the frame instead of in its corner.
- Docked, our arrow could vanish while the minimap was hidden.
- A docked map could fold away. Docking a folded map opens it.
- A clock taken off the map lay over the game's windows.
- The top quest's shading in the tracker was cut off in a hard line.
- Fully zoomed out, the Eastern Kingdoms never showed their zone maps in full, as Kalimdor did.

Changed
- The sliders for "Changes shape per zone" are with its tick, on How it acts.
- The search's marks are smaller and quieter.
- The tracker's resize corner shows only when you point at the tracker.

Known
- With Waymark's quest tracker switched off again, the game's own tracker can stay hidden. Chat says so when it happens: a /reload brings it back.
- Class trainers don't have their lists yet. A right-click says so.
- "SetPreferredGamepadInteractTarget()" can still come up with a controller. If you see it, click [Copy a report] in the chat line and paste it in a comment on Waymark's CurseForge page.
- After updating, restart the game (not just /reload) to see the new map art.

## 1.3.1 (2026-11-17)

**A smoother map on the continents, and the zone maps there come in clear.**

Performance
- Opening a continent, or wheeling out of a zone onto one, no longer hitches. Waymark laid every zone map of the continent in one go. Now it lays them in small steps, and has your own continent ready soon after you log in.
- Zoomed in on a continent, only the zone maps in view are drawn.
- Zooming on a continent does less work on every step.

New
- Escape shuts a big map you opened with its key, and makes any other big map small again.
- The map search finds zones and named places too.
- The quest log can open with the big map: Settings > Quest log > "Open it with the big map". Off as it comes.
- Boats: a size slider for the moving ships and zeppelins.
- Fisherman's mode can have a button on the map: Settings > Toggle buttons. Off as it comes.

Changed
- On a continent, each zone's own map now comes in almost as soon as you wheel out, so the continent looks as clear as the zones do. For new installs and a setup picked afresh: your own settings stay as they are. The three sliders are on The map's look, under Show advanced settings.
- A quest started by a dropped item shows one "!" on a map, at the busiest camp, where it could cover a whole zone in them before. Point at it and the other camps show faintly.
- As told: the "Asked" part of the panel has its own warm gold.
- The shaded land, here and there: Kalimdor's ground is rounder, Un'Goro keeps its wall, the sea off Gilneas lies flat, and two walls that are not on the painted map (the Blasted Lands' coast, east of the Shimmering Flats) no longer throw a shadow.

Fixed
- Coloured specks on the painted continents: small red, yellow or purple dots in the sea and along coasts, more of them the further you zoomed out. Every piece of the continents is made again without them.
- Zoomed all the way out on a continent, the shaded land lay at full strength over the game's own continent map, with halos and dark patches on the coasts. The shading now comes in together with Waymark's painted zone maps.

Known
- With Waymark's quest tracker switched off again, the game's own tracker can stay hidden. Chat says so when it happens: a /reload brings it back.
- The first time a continent opens after you log in, the frame rate can dip for a second or two while the game loads the art.
- Class trainers don't have their lists yet. A right-click says so.
- "SetPreferredGamepadInteractTarget()" can still come up with a controller. If you see it, click [Copy a report] in the chat line and paste it in a comment on Waymark's CurseForge page.

## 1.3.0 (2026-11-16)

**The map gets its land: shaded hills, pencil where you've only looked, boats where they really are, and your quests as the quest giver told them.**

New
- **The land has shape.** The whole map is shaded from the game's own terrain, zones and continents both. The light goes round with the time of day.
- **Pencil where you've only looked.** Land you have seen but not walked is sketched in pencil. It takes its colour when you walk it. Simple now starts this way: unexplored land is blank, and fills in as you go.
- **Boats where they really are.** Once you've ridden a boat or zeppelin, the map draws it where it is on its crossing.
- **As told.** A small panel with your quest in the quest giver's own words, and the places they named pencilled on the map. Every quest in the game has been read for it.
- **What kills here.** In a dungeon, the things that wipe groups are marked on its map with a note beside it. Click one for what to do about it. No boss guides.
- **Search the map.** A magnifier in the map's corner. Type a trainer, a service or an item a vendor sells, and the map shows the closest one.
- **The notebook has drawings.** Each dungeon's "before we go" page opens on a pen drawing of the place, and a small campfire on the zone map shows where it was drawn.
- **Hold to glance.** Hold the map's key and the map is there only while you hold it. The map can also fold out of the way when you open a window over it.
- **New frames** for the map, the tracker and the tooltips: Engraver's corners, Moonlit silver and Sun gold.
- **Ready-made looks** for the header and border, one choice on Header & border. Each puts the header where it fits.
- **Settings you can find things in.** One list of nine entries, and a Start here page that shows everything Waymark can do, each with its switch.
- Clear view cuts the six capital cities and Forever's newer zones to their own outlines.
- The quest window shows what a quest giver says for the next step in a chain.
- Forever's new vendors have their stock, and Forever's new boss drops are in the loot lists.

Changed
- The download is bigger, about 58 MB: the shaded land is most of it. Performance mode rests the shading and the pencil on handhelds and older PCs.
- The download holds one folder now, `Waymark`. If you install by hand, you can delete the old `BattlefieldInfo` folder.
- The small "?" marks under quest pins on the notebook's dungeon maps are gone. Bare of their pins they looked like turn-ins.

Fixed
- Clear view with the pencil on stopped halfway through cutting the map to the zone's shape.
- The header sat too low after picking a ready-made setup or look.
- The map moved to the right on a /reload.
- Map art sat over the border's corners.
- Controller: typing in chat could lose its focus after a blocked-action report opened.

Known
- With Waymark's quest tracker switched off again, the game's own tracker can stay hidden. Chat says so when it happens: a /reload brings it back.
- Class trainers don't have their lists yet. A right-click says so.
- A few of Forever's newest dungeons have no map pictures yet.
- "SetPreferredGamepadInteractTarget()" can still come up with a controller. If you see it, click [Copy a report] in the chat line and paste it in a comment on Waymark's CurseForge page.

## 1.2.9 (2026-11-12)

**Controller players: the blocked-action report now catches where the error begins.**

Changed
- The report for a blocked action ([Copy a report] in chat, or /waymark report) now also names the moment Waymark first touched the game's world map, and what Waymark was doing just then. With the controller UI on, Waymark looks for that moment as you play: a few light checks, nothing of the game's changed.
- The report lists more of what was touched: one long entry no longer crowds out the rest.
- Waymark's map no longer announces its own map changes to the game.

Still open
- "SetPreferredGamepadInteractTarget()" can still come up with a controller. 1.2.8 took out one cause, not all of them. If you see it on 1.2.9, please paste the report in a comment on Waymark's CurseForge page: this version's report should show where it starts.
- "Button:SetPassThroughButtons()" in a fight: the same, please send the report.

## 1.2.8 (2026-11-11)

**Controller players: another cause of the blocked-action error is out, and a blocked action now comes with a report you can copy.**

New
- When the game blocks something of Waymark's, the chat line has a [Copy a report] link (or type /waymark report). It opens a window with what Waymark was doing just before. Paste it in a comment on Waymark's CurseForge page: it tells us where to look. No character or realm names are in it.
- Quest tracker: with chat open, Shift-click a quest to link it in chat. The quest window's rows do the same.
- Quest tracker: choose what a click on a quest does. Settings > Tracker > "Click a quest": fold its objectives (as before), open its details, or open the game's map.

Changed
- The book: the last spread has a new pocket and letter, and more pages have new lines and drawings.

Fixed
- Controller (gamepad UI): "Waymark tried to call SetPreferredGamepadInteractTarget()" could still come with the game's quest tracker hidden by Waymark (the default) and quests tracked. Hiding it made the game rebuild its tracker on Waymark's account, at login and whenever Waymark's map opened or closed. It no longer does.
- "Button:SetPassThroughButtons()" in a fight: two places where it could come from are closed (the quest-area marker, and the map loading after a reload in a fight). If you still see it, please send the report.
- Undercity and Ironforge: the map no longer draws the land above over the city's own map.
- A drawing in the book no longer lies over the last line of a page's text.

## 1.2.7 (2026-11-10)

**Controller players: the blocked-action error and the broken jump button are fixed, and there's a new Fisherman's mode.**

New
- Fisherman's mode: the map's water is tinted by how your fishing does there. Sage: no fish gets away. Ochre: some do. Red: most do. While it's on, the zone header shows the zone's fishing level. Turn it on in the quick panel, or Settings > Townsfolk > Fisherman's mode.
- Entrance pins for Forever's own dungeons: the Hall of Thanes (Ironforge), the Ruins of Lordaeron (Undercity), the Excavation Site (Wetlands) and the City of Dalaran (Alterac Mountains).
- Quests started by an item say so in their details, and where the item drops. "Find on map" lights the dungeon's entrance.
- Menus & questions font: Settings > Header & border. The game's Friz Quadrata by default, for easy reading.
- The quest tracker can show just the place for a finished quest ("Sentinel Hill").

Changed
- Waymark asks its questions in its own box: hiding a giver's quests, a boss note, your words in the book, abandoning from the quest window, resetting the book. Enter or A to confirm, Esc or B to cancel.
- Right-click menus are dark, like Waymark's other windows, with a little more room. The book's quill tools keep their parchment list.
- The game's quest objective markers and blue quest areas are now drawn by Waymark. They look the same. Clicking a marker opens the quest's page in Waymark's quest window.
- Cities: profession trainers show, and "Only my professions" is off in every preset.
- "Find on map" for Forever quests our data doesn't know: it goes to the givers you've met, then the game's own marker. A quest with no giver lights who takes it in.
- The book: every page is open now, Blackrock Depths, Blackrock Spire, Dire Maul, Scholomance and Stratholme included, with new lines and fixes.

Fixed
- Controller (gamepad UI): opening and closing the world map, its quest log or a quest's details no longer gives "Waymark tried to call SetPreferredGamepadInteractTarget()", and A (jump) keeps working. The cause was the game's own quest markers on Waymark's map. Waymark draws them itself now.
- Controller: Waymark's questions no longer leave the pad's buttons broken.
- Opening a settings page from outside the settings window no longer errors.

Known
- Forever's new dungeons have no map pictures yet.

## 1.2.6 (2026-11-08)

**Boats on the map, a docked minimap in the shape you like, a performance mode, and the map stays where you put it.**

New
- Boats and zeppelins on Forever: their piers on the map and dotted routes on the continent map, Forever's own crossings included (Stormwind Harbor to Auberdine, Steamwheedle Port to Powderfuse Port, the skyships from Valanaar).
- Docked over the minimap, pick its shape: square, wide (5:4, 4:3, 16:10) or tall (4:5, 3:4, 10:16). Minimap replacement > Shape.
- Performance mode: one switch for handhelds and older PCs that lightens the map. Each part it lightens can be kept as it was. The welcome page links to it.
- Walk within 60 yards of an objective at a single spot and its X shows in place of the quest's dot.
- A quest giver's pin stands where you met them, and who you've met giving a quest wins over the built-in data.
- In a capital, givers and hand-ins filed under its zone show on the city map.

Changed
- Quest objective dots: a quest spread over a zone shows up to four dots, not one; a quest's own dots close together are drawn as one.
- Hovering a quest's dot lights that quest, the one under the cursor; the other quests fade without a blink.
- Vendors: nearby pins show different types before repeating one, so a forge full of repairers still shows its trade goods. Town view shows every vendor type in all presets.
- Close-up detail fades in by how close you are to the closest zoom, the same at any map size. Resizing the map keeps your zoom.
- On Forever the "top-right corner" setting for the docked map is gone: move the minimap in Edit Mode, or the map with Ctrl-drag. "Back to the minimap's spot" in the map's menu puts it back.
- Town and city view: one size slider for quest givers and turn-ins.
- Clear view steps aside while the map is docked, and in town view the frame stays away while the zone is cut to its outline.
- Boats and their words shrink on a small map.
- The tracker shows a finished quest's hand-in place at the right.
- The Creator's preset is now the creator's own setup. All presets cleaned of settings that did nothing.

Fixed
- The map no longer creeps toward the middle of the screen after a reload, undocked or docked.
- A detached clock comes back to its own spot after a reload.
- Gamepad on Forever: A (jump) works again after opening and closing the map.
- Docked: other addons' minimap buttons you keep hidden (Leatrix Plus's button bag) stay hidden, before and after undocking.
- Docked: opening and closing Edit Mode no longer moves the map off the spot you dragged it to.
- Quest dots and X marks keep their size at the closest zoom, and only catch the mouse close to them.
- Quest dots keep their own colours after you hover another quest.
- A quest you've handed in no longer comes back as a quest pin.
- How Big a Threat? shows all three furbolg camps that complete it, not only the southern one.
- Quests Forever doesn't offer are off the map ("Your Reward has Arrived!"); Teldrassil on Forever comes after The Oracle Tree.
- Long font names in the font menus stay on one line.

Known
- Forever's new dungeons have no map pictures yet.

## 1.2.5 (2026-11-07)

**The dungeon map is back on Forever, quest objectives redone, and the book opens up to the Sunken Temple.**

New
- The dungeon map is on again on Forever: floors, boss list, bosses ticked as they die, the book's notes on the map. Floor arrows are clickable, and the floor name stays clear of the buttons on a small docked map.
- A brass switch on dungeon and cave maps (bottom left) turns between the map and your minimap.
- Docked in a dungeon, the X or the map's key now switches the square between the dungeon map and your minimap.
- Each dungeon remembers its own map size. The first time in, it keeps the size the map had outside.
- The book opens up to and including the Sunken Temple, with Forever's own dungeons (Ruins of Lordaeron, Excavation Site, City of Dalaran) on Forever.
- Quest objectives as coloured dots, one colour per quest, with the quest you're on shown at its nearest camp. Or as pins, or Questie's, or the game's own: pick under Quests.
- Quest tooltips show each objective's kind as an icon (slay, gather, use, explore, talk), the quest's level, and with Shift the XP for a finished quest.
- Quests started by an item that drops: one "!" per camp of the monsters that drop it, the busiest camp clearest.
- Quest items you buy show who sells them.
- The tracker: buttons for quest items, finished quests last, and a soft shade behind the text.
- Taming the Beast marks the beast to tame.

Changed
- Docked, the boss list, the book and the quill only show on the big map; the floor name sits top middle and its arrows bottom middle.
- Dungeon levers and doors that open after a fight are off by default (Caves & dungeons, to turn them on).
- The game's own minimap clock hides while Waymark's clock shows.
- Docked, the game's own coordinates hide when Waymark's are on, or sit under the map.
- Settings on the Quests page reworded: Objective icons, pins and dots. A few that did nothing are gone.
- Quest tooltips are calmer: no rewards or drop chances, one line per objective.
- All presets updated with the new settings.

Fixed
- Dungeons on Forever: no more errors from the game hiding monster names and GUIDs inside (looting, boss kills, tooltips).
- Gamepad mode: the Battlefield Map no longer throws an error every frame (the game's own bug).
- Docked: drag the map by its frame's edge with Ctrl, right-click the edge for the map's menu. Undocked: plain drag on the edge again.
- Off a boat, the map shows your zone, not the continent.
- The clock no longer catches clicks where its digits used to be.
- Objectives in a capital show on its zone's map too.

Known
- Where you are inside a dungeon (the soft light) is off on Forever: the game hides the monster names it needs.
- Forever's new dungeons have no map pictures yet.

## 1.2.4 (2026-11-06)

**Simpler from the first install: a calmer map, far fewer settings, and a lot of docking fixes.** Current players keep their settings: pick Simple on Start here to get the new look.

New
- New players start on Simple: a calm map that leaves the game's tracker, quest log and clock alone.
- A welcome page, shown once, the first time the map opens.
- Presets redone, each clearly different: Simple, Creator's, Purist, Minimap Replacement and Minimalist.
- One Objectives switch, in three looks: Questie's (where it's installed), Waymark's, or Yours (the game's own).
- "Focus quest" on a quest's right-click menu in the tracker.

Changed
- Far fewer settings on show. The map comes first, with Extras for the tracker, quest log, clock and book. Pages start folded, and the fine-tuning is under Show advanced settings.
- Quest givers now means pick-ups and turn-ins together.
- Presets no longer change your quest pins, objectives or quest ground. Purist is the exception: it turns quest help off, and leaving it brings it back.
- Quick options trimmed to what you switch while playing.
- The tracker's text is easier to read, and no line is cut in half.
- Docked is always the map now. Map only and the wheel switching are gone.
- Saved setups are presets now: they show as cards on Start here.
- Line to target is now Line to party member, as that's all the game allows.
- Gathering options only show with GatherMate2 on.
- The round minimap button is gone: Waymark is in the game's addon dropdown.
- Auto-zoom near objectives is removed.

Fixed
- Docked: the map keeps the minimap's spot and clears the game's tracker. Addon buttons sit on its edge, the clock and calendar go under it, and Edit Mode's box comes along.
- Docked: the header, X and gear stay on top after undocking. The game's blue quest areas no longer cover the square.
- Keep centred now does what it says, docked and in towns.
- "View details" opens the game's small quest page when our quest log is off.
- "Quest details" works on a giver with an empty quest log, or with our quest log off.
- Right-click menus stay on the screen.
- Fewer blocked-action errors in fights.
- The map is at full opacity the first time it opens.
- The corpse's tombstone shows on the map.

Known
- A lot of dungeon features are still off. I'm fixing them in the days to come.

## 1.2.3 (2026-11-05)

**Live tracking on your map, gathering nodes back, and a much better docked map.**

New
- Docked: live minimap blips on your map. Find Herbs, Find Minerals, hunter tracking and the rest now sit on the detailed map art at every zoom, with their names on hover. Past the minimap's farthest zoom they show in a patch around you, for as far as the minimap can see. On by default; you'll find the switch on the Minimap replacement page.
- Gathering nodes are back on Forever, through GatherMate2. Install GatherMate2 and GatherMate2_Data, then import Herbs, Mines and Treasure in GatherMate2's options. Spots are corrected in Mulgore, Eastern Plaguelands and Redridge, which Forever redrew.
- Docked: drag the header to move the square. The frame's menu sends it back.
- Docked: right-click the frame for the map's menu, for those who play without a header.
- Docked: the corner drags an outline, and the square changes once when you let go.

Changed
- The dungeon map is switched off on Forever for now, while it's tested in live dungeons. Dungeon entrances on zone maps stay.
- Map toggles: a click during a fight now stays, instead of lasting only for that fight.
- The Gathering context profile is gone.
- The Creator's dock settings are refreshed.
- Docked: the game's day and night icon is hidden, as we have our own clock.

Fixed
- Docked: the minimap's + and - no longer show.
- Docked: pins no longer stick to the cursor when you wheel in with the button held.
- Docked: the buffs don't jump aside for the big map, and the clock stays by the square.
- Docked: the arrow keeps one size at every zoom.
- The corner grip is easier to hit.

## 1.2.2 (2026-11-05)

**Key bindings at last, a smoother docked map, and a simpler Quests page.** Please update: no earlier release had working key bindings.

Fixed
- Key bindings: Waymark now has its section in Keybindings, and binding keys works.
- Docked: pins no longer slide into place, and a fast zoom out stays out.
- Docked: the header's lower half takes clicks again.
- Docked: the wheel's friction holds the map still on the way in.

New and changed
- Docked: one set of quest pins. Always ours, on the map and the minimap, in the same colours. Questie's minimap pins wait while docked and come back undocked.
- Docked: toggle buttons outside the map's top or right move to its left.
- New: docked, objective spots on the minimap and quest ground on the map (Quests page).
- Quests page reworked: a Showing now box, clearer sections, and the tooltip choice in one place.
- Objective spots take Questie's own colours where it's loaded.
- Presets: a Keep my quest pins tick, on by default with Questie, so a preset leaves your quest pins and tooltips alone.
- A first install with Questie starts on its icons with objective spots on.
- The Creator's preset, what Waymark ships with, is refreshed.
- The book: right-click a quest in Who asked us for details and find on map.
- Find on map works for a quest you're only looking at: it goes to the giver's map, and the giver glows.

## 1.2.1 (2026-11-05)

**Fixes for live Forever, and a few new things.** If you're on 1.2.0, please update: on the live client Waymark's buttons and icons drew blank, and a "blocked" popup showed at login. Your notes and ink carry over.

Fixed
- Waymark's buttons, frames and icons drew blank.
- A "Waymark has been blocked" popup at login (the game no longer lets addons read the combat log).
- Quest lines on mob, item and object tooltips.
- Errors from item data in reward tooltips, vendor lists and boss loot.
- Professions weren't read, so skill checks did nothing. Also PvP colours on the zone name and money in rewards.

New and changed
- New: Waymark size, one slider for the whole addon (Size, shape & fade). The game's own UI stays as it is. Forever starts at 1.25x.
- Zoomed in, quest rings stay thin and the player arrow grows.
- Quest window and settings window: the corner sets height and scale; the quest window's art loads without a delay. The settings window's frame takes clicks.
- Docked: the map follows the minimap in Edit Mode, the game's title bar can be hidden, quest pins aren't doubled, right-click no longer drops you out of the minimap, and undocking gives the minimap back whole.
- With Questie: objective spots follow its theme (icons, colours, glow), live.
- The game's quest areas show for every quest on the map, and the Objective markers and Quest areas toggles work without touching Blizzard's settings.
- Items and spells the game hasn't shared yet say so instead of "Retrieving item information".
- Zone maps on the continent now use Forever's real shapes.
- Removed developer tools that went out by mistake in 1.2.0: the Dev settings page, the command bar and the developer commands.
- The book: you now write as yourself, and notes from 1.2.0 carry over.
- New: a sun clock on the map, and the map follows the hour (Creator's preset).
- Quests filled from QuestieDB when you have it.
- New drops in "What they carry" for the classic dungeons.
- Quests started by an item read Deliver; Forever's trainers no longer show as general goods.

Not in this release: gathering marks. They wait until GatherMate2 works on Forever.

## 1.2.0 for Classic Era (2026-11-04)

**Waymark comes to Classic Era.** Battlefield Info is now Waymark. Same addon, new name. Your settings, ink, notes, setups and key bindings come along by themselves.

The download has three folders: `Waymark` (the addon), `BattlefieldInfo` (a small helper that carries your old settings over) and `Waymark_Nodes` (gathering spots, data only, GPL v3). The CurseForge app installs them all. If you install by hand, extract all three into `Interface\AddOns`. Once each of your characters has logged in with Waymark, the helper can be deleted. `/waymark` opens the settings; `/bfi` still works.

This release is for Classic Era (interface 11509). It has everything in Forever's 1.2.0, plus what's below. On Era the continent map is drawn with our own land and strokes, with no Blizzard map art in the download.

New since Forever's 1.2.0
- Gathering nodes: herbs, ore and treasure on the map and minimap from Waymark's own data, with GatherMate2 as an option.
- A sun clock on the map. New installs start with it on and the game's minimap clock off; if you're updating, the game's clock stays.
- The map follows the hour, in the Creator's preset only.

New since 1.1.0
- The found notebook: an old wanderer's dungeon notes, with maps, routes and warnings, reached from the dungeon doors and the map's quill button. Write in it and draw on its maps yourself. Pages up to Gnomeregan are open; later ones come in later updates.
- Map ink: a quill to draw your own marks, routes and notes on any zone or dungeon map.
- Dungeon maps for every classic dungeon: bosses you can number and reorder, doors, chests and switches, quest monsters, and a light that guesses where you are inside from the monsters you meet.
- Caves: quest pins and objective spots inside caves, a floor bar for caves with several levels, and a right-click out to the zone.
- The continent map: zones joined into one painted continent, with coasts, seas and fading names.
- Quest ground: objective areas drawn on the map, coloured by quest type; hover for the quest, right-click for its menu, arrows to lone spots and turn-ins.
- Quest window: rewards and drop chances, a "Looking at" section for quests you don't have, one row per quest on givers with several, Shift-click links and Ctrl-click try-ons.
- Quest progress on the game's own tooltips, and giver tooltips with each quest's kind in its colour (or Questie's tooltip, if you prefer).
- Rares from our own data, with their drops behind Shift; boss loot in a "What they carry" window.
- Vendors and trainers: what they sell and what they teach.
- "What you've learned": quest givers and monster spots learned as you play, shareable as a string.
- Start here: presets that set up the whole map in one click (Creator's, Purist, Minimap Replacement, Minimalist), "(altered)" when you change one, and presets of your own.
- Quick options panel beside the map; toggle buttons for quest areas and the quill; lock the map in place.
- The big map key opens and closes the map; the map stays open through zone changes and reloads, and holds still on a flight path while you browse.

Changes
- Auto-zoom is off by default; its button is now "Keep centered".
- Clearer settings: plain words, pages that read top to bottom, a welcome page.
- One set of controls everywhere: left-click acts, right-click gives a menu, hold to move.

Fixes and polish
- Quest-provider chat spam on Classic Era gone.
- Duplicate key binding warnings gone.
- Many smaller tooltip, tracker and docked-minimap fixes.

## 1.2.0 (2026-11-03)

**Battlefield Info is now Waymark.** Same addon, new name. Your settings, ink, notes, setups and key bindings come along by themselves.

The download now has two folders: `Waymark` (the addon) and `BattlefieldInfo` (a small helper that carries your old settings over). The CurseForge app installs both. If you install by hand, extract both into `Interface\AddOns`; the helper replaces the old BattlefieldInfo folder's contents. Once each of your characters has logged in with Waymark, the helper can be deleted (it is safe to keep). `/waymark` opens the settings; `/bfi` still works. If you kept an old copy of Battlefield Info as well, Waymark turns it off for you and asks for a /reload.

This release is for WoW Forever.

New
- The found notebook: an old wanderer's dungeon notes, with maps, routes and warnings, reached from the dungeon doors and the map's quill button. Write in it and draw on its maps yourself.
- Map ink: a quill to draw your own marks, routes and notes on any zone or dungeon map.
- Dungeon maps for every classic dungeon: bosses you can number and reorder, doors, chests and switches, quest monsters, and a light that guesses where you are inside from the monsters you meet.
- Caves: quest pins and objective spots inside caves, a floor bar for caves with several levels, and a right-click out to the zone.
- The continent map: zone maps joined into one painted continent, with coasts, seas and fading names.
- Quest ground: objective areas drawn on the map, coloured by quest type; hover for the quest, right-click for its menu, arrows to lone spots and turn-ins.
- Quest window: rewards and drop chances, a "Looking at" section for quests you don't have, one row per quest on givers with several, Shift-click links and Ctrl-click try-ons.
- Quest progress on the game's own tooltips, and giver tooltips with each quest's kind in its colour (or Questie's tooltip, if you prefer).
- Rares and chests from our own data, with their drops behind Shift; boss loot in a "What they carry" window.
- Vendors and trainers: what they sell and what they teach.
- "What you've learned": quest givers and monster spots learned as you play, shareable as a string.
- Start here: presets that set up the whole map in one click (Creator's, Purist, Minimap Replacement, Minimalist), "(altered)" when you change one, and presets of your own.
- Quick options panel beside the map; toggle buttons for quest areas and the quill; lock the map in place.
- The big map key opens and closes the map; the map stays open through zone changes and reloads, and holds still on a flight path while you browse.

Changes
- Auto-zoom is off by default; its button is now "Keep centered".
- Clearer settings: plain words, pages that read top to bottom, a welcome page.
- One set of controls everywhere: left-click acts, right-click gives a menu, hold to move.

Fixes and polish
- Quest-provider chat spam on Classic Era gone.
- Duplicate key binding warnings gone.
- Many smaller tooltip, tracker and docked-minimap fixes.

## 1.1.0 (2026-10-27)

New
- Minimap replacement: a square, north-up minimap with the Battlefield Map docked over it. Right-click releases to my maps view and doubleclick goes back to minimap, and in caves and dungeons it fits the cave zoom or brings back the game's minimap.
- Clear view: border, header and buttons show only on mouse-over, the map's opacity can be set, and only the zone you're in is drawn, with tight zone outlines.
- Collapse: a key (or entering combat) folds the map down to its header. The buttons hide and the tracker stays.
- The quest window can replace the game's quest log, and it uses the map's border styles.
- The quest tracker can detach from the map. Detached, it grows to the right when resized and stays open with the map closed.
- Hold any map button to move it. Right-click the gear for settings.
- Settings have their own pages for Clear view and Minimap replacement, plus a welcome page.

Fixes and polish
- Map buttons placed away from the map stay on the screen.
- Red buttons updated
- The tracker's progress flash is fixed

## 1.0.0 (2026-10-26)

First release, for Classic Era (11509).

- Quests on the Battlefield Map: givers, turn-ins and objective spots (with QuestieDB or Questie), the game's own objectives and quest areas, and quests learned as you play.
- Quest tracker attached to the map and a full quest window beside it.
- Towns and cities: vendors, trainers, innkeepers and flight masters, with town and city views.
- Rares and treasures (RareScanner), gathering nodes (GatherMate2), TomTom waypoints.
- Dungeon entrances, dungeon maps inside instances, cave maps underground.
- Exploration: fog, sepia or ink over unexplored areas, area names on hover, zone progress.
- Party and raid members, a line to your target, coordinates.
- Resizable, movable, zoomable map with a large mode, close-up detail and zone browsing.
- Header and border styles; per-layer switches, opacity and size; a toggle strip you arrange yourself.
- Context profiles, saved setups (per character if you like) and key bindings.

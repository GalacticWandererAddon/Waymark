# Changelog

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

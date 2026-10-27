<p align="center"><img src=".github/logo.png" width="160" alt="Battlefield Info logo"></p>

# Battlefield Info

**The small Battlefield Map, turned into the map you actually play with.**

Battlefield Info builds on the game's own Battlefield Map (Shift-M): the small map you can keep open while you play. It adds quests, townsfolk, rares, gathering nodes and exploration to it, and lets you size, zoom and style it however you like. It's an exploration aid in the classic spirit: it shows you the world and leaves the route to you.

## On the map

- **Quests:** quest givers, turn-ins and objective spots, plus the game's own objectives and quest areas. Quests you pick up from givers the database doesn't know about are learned as you play.
- **Quest tracker and quest window:** a tracker attached to the map, sorted by distance, level or area, and a full quest window beside the map with description, objectives and rewards. Focus the quests you care about, even from other zones.
- **Towns and cities:** vendors, trainers, innkeepers and flight masters by type. A town view zooms in when you arrive; a city view shows a whole capital.
- **Rares and treasures** (with RareScanner), **gathering nodes** (with GatherMate2) and **TomTom waypoints**.
- **Dungeons and caves:** dungeon entrances on the world, a dungeon's own map while you're inside, and cave maps underground.
- **Exploration:** unexplored areas shown in fog, sepia or ink, area names as you hover, and how much of a zone you've seen.
- **Your group:** party and raid members in class colours, a line to your target, and coordinates.

## The map itself

- Resize it, move it, zoom it in and out, and switch to a large mode for a proper look around.
- Close-up detail when you zoom in near.
- Browse other zones and continents without losing your own; it comes back on its own.
- Header and border styles to choose from: classic plate, parchment, leather, stone, gold, wood and more.

## Made to fit you

- Every layer has its own switch, opacity and size, and a row of toggle buttons on the map that you pick and order yourself.
- **Context profiles:** different layers in combat, battlegrounds, dungeons, towns or while gathering, or hide the map there.
- **Saved setups:** keep several complete setups and switch between them; each character can use its own.
- Key bindings for the things you use most.

## Installing

**From CurseForge:** install *Battlefield Info* with the CurseForge app.

**By hand:** download `BattlefieldInfo-Era-1.0.0.zip` from the [latest release](../../releases/latest) and unzip it into
`World of Warcraft\_classic_era_\Interface\AddOns\`, so you end up with `AddOns\BattlefieldInfo\BattlefieldInfo.toc`.

**From git:** clone into the AddOns folder under the name `BattlefieldInfo`:

```
git clone https://github.com/GalacticWandererAddon/BattlefieldInfo.git BattlefieldInfo
```

Made for **Classic Era** (interface 11509).

## Getting started

- Open the map with **Shift-M** (the game's own key).
- **/bfi** opens the settings. The gear on the map opens a quick panel with the most-used switches.
- Fonts and textures from SharedMedia are picked up if you have it.

## Works with

All optional; the map works without them:

- **QuestieDB** or **Questie**: quest givers, turn-ins and objective spots (needed for these layers)
- **RareScanner**: rares and treasures
- **GatherMate2**: gathering nodes
- **TomTom**: waypoints
- **SharedMedia**: more fonts and textures

## Bugs and ideas

Open an [issue](../../issues). For a bug, say what you did, what you saw, and which other map or quest addons you run.
`/bfi check` prints a self-test to chat that helps.

## Credits

Cave and dungeon map data come from [OpenMap](https://www.curseforge.com/wow/addons/openmap) (MIT licence). Battlefield Info is MIT licensed. It contains no Blizzard art: everything you see from the game is drawn from your own client.

See [LICENSE](LICENSE) and [CHANGELOG](CHANGELOG.md).

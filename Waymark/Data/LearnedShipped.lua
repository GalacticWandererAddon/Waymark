local _, ns = ...

-- What players learned as they played, shipped with the addon (tools\bake_learned.lua, don't
-- edit by hand): added to each player's own learned data once per version (Learn.lua).
-- 15 quest givers, 18 quests, 0 monsters.
ns.LearnedShipped = {
version = 1793604589,
givers = {
c10219={kind="npc",name="Gwennyth Bly'Leggonde",offers={},spots={[1439]={0.3662,0.4556,3}},takes={[4730]=true,[4731]=true,[4732]=true}},
c197={kind="npc",name="Marshal McBride",offers={[54]=true},spots={[1429]={0.4886,0.4165,3}},takes={[21]=true}},
c240={kind="npc",name="Marshal Dughan",offers={[62]=true},spots={[1429]={0.4215,0.6593,5}},takes={[54]=true}},
c241={kind="npc",name="Remy \"Two Times\"",offers={[47]=true},spots={[1429]={0.4216,0.6718,1}},takes={}},
c244={kind="npc",name="Ma Stonefield",offers={[88]=true},spots={[1429]={0.3462,0.8450,1}},takes={}},
c246={kind="npc",name="\"Auntie\" Bernice Stonefield",offers={[85]=true},spots={[1429]={0.3444,0.8427,2}},takes={}},
c247={kind="npc",name="Billy Maclure",offers={[86]=true},spots={[1429]={0.4309,0.8579,6}},takes={[85]=true}},
c251={kind="npc",name="Maybell Maclure",offers={[106]=true},spots={[1429]={0.4312,0.8957,1}},takes={}},
c253={kind="npc",name="William Pestle",offers={[60]=true},spots={[1429]={0.4331,0.6582,1}},takes={}},
c295={kind="npc",name="Innkeeper Farley",offers={},spots={[1429]={0.4378,0.6593,1}},takes={[2158]=true}},
c3616={kind="npc",name="Onu",offers={[951]=true},spots={[1439]={0.4360,0.7636,3}},takes={[950]=true}},
c6774={kind="npc",name="Falkhaan Isenstrider",offers={[2158]=true},spots={[1429]={0.4563,0.4779,1}},takes={}},
c9296={kind="npc",name="Milly Osworth",offers={[3905]=true},spots={[1429]={0.5074,0.3948,2}},takes={[3904]=true}},
c952={kind="npc",name="Brother Neals",offers={},spots={[1429]={0.4946,0.4153,1}},takes={[3905]=true}},
o175320={kind="object",name="WANTED: Murkdeep!",offers={[4740]=true},spots={[1439]={0.3726,0.4419,2}},takes={}},
},
quests = {
[106]={factions={Alliance=true},title="Young Lovers"},
[21]={factions={Alliance=true},title="Skirmish at Echo Ridge"},
[2158]={factions={Alliance=true},title="Rest and Relaxation"},
[3904]={factions={Alliance=true},title="Milly's Harvest"},
[3905]={factions={Alliance=true},title="Grape Manifest"},
[47]={factions={Alliance=true},title="Gold Dust Exchange"},
[4730]={factions={Alliance=true},title="Beached Sea Creature"},
[4731]={factions={Alliance=true},title="Beached Sea Turtle"},
[4732]={factions={Alliance=true},title="Beached Sea Turtle"},
[4740]={factions={Alliance=true},title="WANTED: Murkdeep!"},
[54]={factions={Alliance=true},title="Report to Goldshire"},
[60]={factions={Alliance=true},title="Kobold Candles"},
[62]={factions={Alliance=true},title="The Fargodeep Mine"},
[85]={factions={Alliance=true},title="Lost Necklace"},
[86]={factions={Alliance=true},title="Pie for Billy"},
[88]={factions={Alliance=true},title="Princess Must Die!"},
[950]={factions={Alliance=true},title="Return to Onu"},
[951]={factions={Alliance=true},title="Mathystra Relics"},
},
mobs = {
},
}

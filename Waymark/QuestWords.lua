local _, ns = ...

-- The givers' whole words, for quests you do not hold (2026-11-14; out of the Lab the same day: the user, "its in it works").
--
-- The user, of a chain step in the quest window: "we're still missing the quest details (quest text) from the
-- forever ones in our chain in quest log". A quest's description only ever came from your own log; a chain step
-- not in it showed its objective and nothing else. Data/QuestWords.lua (tools/quest_words.py, from a sweep of
-- the game's quest cache) holds the words for every quest the server answered for; this file hands them out
-- with the game's marks filled in for whoever is playing.
--
--   ns.QuestWords(id)  -> the words, or nil (none known, or the piece is off)
--   /questwords        on or off; /questwords <id> prints a quest's words to the chat
--
-- Read by the quest window's chain preview (Tracker.lua). Its switch is the quest window's own
-- (ns.db.questlog.chainWords, a row under Quest chain on the Quest log page), carried over once from the Lab's
-- store where a dev copy had it there.

local function On()
    local c = ns.db and ns.db.questlog
    if not c then return true end
    local old = WaymarkDB and WaymarkDB.lab and WaymarkDB.lab.words
    if old and not old.moved then
        if old.on ~= nil then c.chainWords = old.on and true or false end
        old.moved = true
    end
    return c.chainWords ~= false
end
ns.QuestWordsOn = On     -- (the test bench, which stays in the Lab)

-- $N the name, $C the class, $R the race, $G his:her; by sex, $B a line end; "$1oa " and the like (a count
-- the cache does not carry) drop out
local function Fill(text)
    local name = UnitName("player") or "traveller"
    local class = (UnitClass("player") or "adventurer"):lower()
    local race = (UnitRace("player") or "stranger"):lower()
    local woman = UnitSex and UnitSex("player") == 3
    text = text:gsub("%$[Gg]%s*([^:;]-)%s*:%s*([^;]-)%s*;", function(he, she) return woman and she or he end)
    text = text:gsub("%$%d+oa ", ""):gsub("%$%d+", "")
    text = text:gsub("%$[Bb]", "\n"):gsub("%$[Nn]", name):gsub("%$[Cc]", class):gsub("%$[Rr]", race)
    return text
end
ns.QuestWordsFill = Fill

function ns.QuestWords(id)
    local raw = id and ns.QuestWordsData and ns.QuestWordsData[id]
    if not raw or not On() then return nil end
    return Fill(raw)
end

SLASH_WAYMARKWORDS1 = "/questwords"
SlashCmdList["WAYMARKWORDS"] = function(msg)
    local id = tonumber((msg or ""):match("%d+"))
    if id then
        local words = ns.QuestWordsData and ns.QuestWordsData[id]
        print("|cffd9cfb5Waymark:|r " .. (words and Fill(words) or ("No words kept for quest " .. id .. ".")))
        return
    end
    local on = not On()
    if ns.db and ns.db.questlog then ns.db.questlog.chainWords = on end
    if ns.QuestWindowRefresh then pcall(ns.QuestWindowRefresh) end
    print("|cffd9cfb5Waymark:|r The giver's words for quests you don't have yet: " .. (on and "on" or "off") .. ".")
end

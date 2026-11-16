local _, ns = ...

-- As told: what each sentence of a quest is (the Lab). No game calls: tools\as_told_labels.lua runs this file.
--
-- The user, 2026-11-13: "This is first and foremost a story and immersion tool... getting the eyes off the
-- quest pins and quest tracker, and reading some stories while leveling", and: weigh for removing, not only for
-- keeping, "so you dont leave out good story details, or fun flavour". Word rules could not find the sentence
-- that carries a quest (tools\as_told_pick.lua: right on about half), so every quest is read once and each of
-- its sentences given one letter. The rubric with its examples: mockups\as-told-rubric.md.
--
--   S  story     the trouble, the why, the turn                    at rest (and in the full telling)
--   F  flavour   voice, jokes, colour, lore                        in the full telling
--   A  ask       the order                                         in the full telling, the way's colour
--   W  way       where to go, how to find it                       in the full telling, the way's colour
--   X  chaff     greeting, logistics, the objective said again     never
--
-- Data\AsToldLabels.lua holds a string of letters a quest, one a sentence, in the giver's order
-- (ns.ToldLabelData[questID] = "XSSFAW"), made from tools\as_told_labels\*.txt by tools\as_told_labels.lua.
-- No quest text is in it. The letters only fit the words they were read from: when the game's text has another
-- number of sentences (Forever rewrote the quest), the quest counts as unread and the panel falls back to the
-- removal rule below.

local function Clean(s)
    return (tostring(s or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- the sentences of a text, in order. THE splitter: the labels count sentences by it, so a change here means
-- every quest must be read again (tools\as_told_labels.lua check says which no longer fit).
local function Sentences(text)
    local out = {}
    text = Clean(text)
    local from = 1
    while from <= #text do
        local a, b = text:find("[%.!%?]+[\"']?%s", from)
        local s
        if a then s = text:sub(from, b - 1) from = b + 1 else s = text:sub(from) from = #text + 1 end
        s = Clean(s)
        if #s > 1 then out[#out + 1] = s end
    end
    return out
end
ns.ToldSentences = Sentences

-- The removal rule, for a quest nobody has read: what is plainly chaff goes, everything else stays as flavour,
-- and the first sentence left is the story. Errs toward keeping.
local GREET = { "^hail", "^greetings", "^well met", "^hello", "^ah, ", "^ah! ", "^good day", "^welcome" }
local LEAVE = { "return to me", "come back to me", "report back to me", "bring them to me", "bring it to me", "when you are done",
                "when you're done", "when you have", "once you have", "i will reward", "you will be rewarded", "good luck",
                "be careful", "safe travels", "elune be with you", "light be with you" }
local function Rule(sentences)
    local out, story = {}, false
    for i, s in ipairs(sentences) do
        local low = s:lower()
        local letter = "F"
        if i <= 2 then
            for _, g in ipairs(GREET) do if low:find(g) and #s < 60 then letter = "X" end end
        end
        for _, l in ipairs(LEAVE) do if low:find(l, 1, true) and #s < 90 then letter = "X" end end
        if letter == "F" and not story then letter, story = "S", true end
        out[i] = letter
    end
    return out
end

-- a quest's sentences with their letters: { { text, letter }, ... }, and whether it was read (true) or ruled
function ns.ToldLabelled(id, text)
    local ss = Sentences(text)
    local data = ns.ToldLabelData and ns.ToldLabelData[id]
    local letters, read
    if type(data) == "string" and #data == #ss then
        letters, read = {}, true
        for i = 1, #ss do letters[i] = data:sub(i, i) end
    else
        letters, read = Rule(ss), false
    end
    local out = {}
    for i, s in ipairs(ss) do out[i] = { s, letters[i] } end
    return out, read
end

-- the sentences of some letters, joined in the giver's order ("S", or "SFAW"); a gap between two that were
-- not neighbours is left as a plain space: the words are the giver's, the cut is ours and is not shown
function ns.ToldPart(labelled, which)
    local out = {}
    for _, e in ipairs(labelled) do
        if which:find(e[2], 1, true) then out[#out + 1] = e[1] end
    end
    return table.concat(out, " ")
end

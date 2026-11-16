local _, ns = ...

-- Made by tools\relief_continent.py: see Relief.lua. The continents with relief art in Media\Relief
-- (c<continent><layer>.blp) and the ground the pictures cover: box as ns.ReliefZones (world x at the bottom,
-- y at the right, x at the top, y at the left); frac: the same on Forever's continent map (left, right, top,
-- bottom), used where the client cannot say where the map lies.
ns.ReliefContinents = {
    [1414] = { box = { -10974.989, -8847.900, 12331.252, 5941.654 }, frac = { 0.30231, 0.70420, 0.01910, 0.96909 } },
    [1415] = { box = { -15922.912, -8209.839, 6694.038, 3950.005 }, frac = { 0.34233, 0.68778, 0.03292, 0.99671 } },
}

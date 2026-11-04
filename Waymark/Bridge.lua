local _, ns = ...

-- The little Waymark lends to Waymark: Combat, its own addon: the same menus, tooltip hints and
-- settings window. Combat looks for this and manages without it.
WaymarkBridge = {
    Hints = function(hints, tip) ns.Hints(hints, tip) end,
    Menu = function(items) ns.QuillMenu(items) end,
    Settings = function() ns.OpenOptionsPage("combat") end,
}

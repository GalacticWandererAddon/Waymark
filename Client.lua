local addonName, ns = ...

-- Which client this is. The addon is made for WoW Forever (1.60, interface 16001);
-- Classic Era (1.15) and Anniversary (2.5) only stand in for it while its servers
-- are down. Fixes for a stand-in go behind `if not ns.FOREVER`, so Forever keeps
-- its own behaviour.
local interface = select(4, GetBuildInfo()) or 0
ns.INTERFACE = interface
ns.FOREVER = interface >= 16000 and interface < 20000
ns.CLASSIC_ERA = interface >= 11500 and interface < 12000
ns.CLIENT = ns.FOREVER and "forever" or ns.CLASSIC_ERA and "classic era" or "other"

-- Which edition this copy is, from the TOC's X-Edition: "Forever" (branch main; also
-- run on the stand-ins for testing) or "Era" (the frozen Classic Era release, branch
-- era, in F:\AddonWorkspace\BattlefieldInfo-Era). Shown by /bfi check.
local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.EDITION = GetMeta and GetMeta(addonName, "X-Edition") or "?"

local _, ns = ...

local function Set(ids)
	local set = {}
	for _, id in ipairs(ids) do
		set[id] = true
	end
	return set
end

ns.Data = {
	-- Conjure Food, ranks 1-7: Muffin, Bread, Rye, Pumpernickel, Sourdough, Sweet Roll, Cinnamon Roll
	conjuredFood = Set({ 5349, 1113, 1114, 1487, 8075, 8076, 22895 }),

	-- Conjure Water, ranks 1-7: Water, Fresh, Purified, Spring, Mineral, Sparkling, Crystal
	conjuredWater = Set({ 5350, 2288, 2136, 3772, 8077, 8078, 8079 }),

	-- Create Healthstone: Minor, Lesser, Healthstone, Greater, Major - each plain and with
	-- 1/2 and 2/2 points in Improved Healthstone
	healthstones = Set({
		5512, 19004, 19005,
		5511, 19006, 19007,
		5509, 19008, 19009,
		5510, 19010, 19011,
		9421, 19012, 19013,
	}),

	-- Mage portal spells: Stormwind, Ironforge, Darnassus, Orgrimmar, Undercity, Thunder Bluff
	portalSpells = Set({ 10059, 11416, 11419, 11417, 11418, 11420 }),

	-- The player's own ways to travel: Hearthstone and the mage Teleport spells to the same cities
	ownTeleports = Set({ 8690, 3561, 3562, 3565, 3567, 3563, 3566 }),
}

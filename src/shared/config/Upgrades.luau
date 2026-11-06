--!strict
-- Upgrade tracks. `costs[i]` is the price of level i (level 0 is free/base).

export type UpgradeDef = {
	id: string,
	displayName: string,
	description: string,
	base: number,
	perLevel: number,
	costs: { number },
}

local Upgrades = {}

Upgrades.list = {
	{
		id = "nestSlots",
		displayName = "Nest Beds",
		description = "+1 nest bed",
		base = 3,
		perLevel = 1,
		costs = { 300, 1500, 6000, 25000, 100000 },
	},
	{
		id = "habitatSlots",
		displayName = "Habitats",
		description = "+1 habitat pad",
		base = 2,
		perLevel = 1,
		costs = { 200, 1200, 5000, 20000, 80000, 250000 },
	},
	{
		id = "growthSpeed",
		displayName = "Growth Speed",
		description = "+10% growth speed",
		base = 1,
		perLevel = 0.1,
		costs = { 500, 3000, 12000, 50000, 200000 },
	},
	{
		id = "luck",
		displayName = "Luck",
		description = "+5% luck (Rare and better)",
		base = 1,
		perLevel = 0.05,
		costs = { 1000, 6000, 25000, 100000, 400000 },
	},
	{
		id = "backpack",
		displayName = "Backpack",
		description = "+25 critter capacity",
		base = 50,
		perLevel = 25,
		costs = { 250, 1500, 7500, 30000, 120000 },
	},
} :: { UpgradeDef }

Upgrades.byId = {} :: { [string]: UpgradeDef }
for _, def in Upgrades.list do
	Upgrades.byId[def.id] = def
end

-- Absolute caps including game pass bonuses (world layout depends on these).
Upgrades.maxNestSlots = 10
Upgrades.maxHabitatSlots = 8

return table.freeze(Upgrades)

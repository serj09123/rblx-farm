--!strict
-- Nest definitions: the only place where hatch randomness happens.
-- weights are relative (they do not need to sum to 100).

export type NestDef = {
	id: string,
	displayName: string,
	tier: number, -- progression tier, used to scale rewards and Skyheart share
	cost: number?, -- nil = not purchasable (reward/tutorial only)
	growSeconds: number,
	unlockAtHatched: number,
	weights: { [string]: number }, -- rarity id -> weight
	color: { number },
	seasonSpecies: boolean, -- active seasons may inject event species
	guaranteed: { species: string, mutations: { string }, size: number }?,
}

local Nests = {}

Nests.list = {
	{
		id = "meadow",
		displayName = "Meadow Nest",
		tier = 1,
		cost = 60,
		growSeconds = 30,
		unlockAtHatched = 0,
		weights = { Common = 70, Uncommon = 25, Rare = 4.5, Epic = 0.5 },
		color = { 140, 210, 110 },
		seasonSpecies = false,
	},
	{
		id = "grove",
		displayName = "Grove Nest",
		tier = 2,
		cost = 280,
		growSeconds = 90,
		unlockAtHatched = 5,
		weights = { Common = 40, Uncommon = 38, Rare = 17, Epic = 4.5, Legendary = 0.5 },
		color = { 60, 150, 80 },
		seasonSpecies = true,
	},
	{
		id = "crystal",
		displayName = "Crystal Nest",
		tier = 3,
		cost = 1600,
		growSeconds = 240,
		unlockAtHatched = 25,
		weights = { Uncommon = 40, Rare = 37, Epic = 19, Legendary = 3.7, Mythic = 0.3 },
		color = { 150, 210, 255 },
		seasonSpecies = true,
	},
	{
		id = "storm",
		displayName = "Storm Nest",
		tier = 4,
		cost = 6500,
		growSeconds = 600,
		unlockAtHatched = 75,
		weights = { Rare = 40, Epic = 42, Legendary = 16, Mythic = 2 },
		color = { 90, 90, 150 },
		seasonSpecies = true,
	},
	{
		id = "celestial",
		displayName = "Celestial Nest",
		tier = 5,
		cost = 19000,
		growSeconds = 1200,
		unlockAtHatched = 200,
		weights = { Epic = 52, Legendary = 40, Mythic = 8 },
		color = { 255, 230, 150 },
		seasonSpecies = true,
	},
	{
		-- Reward from Skyheart Bloom and daily rewards. Never sold.
		id = "skyheart",
		displayName = "Skyheart Nest",
		tier = 3,
		cost = nil,
		growSeconds = 150,
		unlockAtHatched = 0,
		weights = { Uncommon = 40, Rare = 40, Epic = 17, Legendary = 2.7, Mythic = 0.3 },
		color = { 255, 120, 200 },
		seasonSpecies = true,
	},
	{
		-- Tutorial only: fast and scripted so the first hatch is always exciting.
		id = "starter",
		displayName = "Starter Nest",
		tier = 1,
		cost = nil,
		growSeconds = 10,
		unlockAtHatched = 0,
		weights = { Common = 1 },
		color = { 255, 220, 120 },
		seasonSpecies = false,
		guaranteed = { species = "puffpaw", mutations = { "Shiny" }, size = 1.1 },
	},
} :: { NestDef }

Nests.byId = {} :: { [string]: NestDef }
Nests.purchasable = {} :: { NestDef }
for _, def in Nests.list do
	Nests.byId[def.id] = def
	if def.cost ~= nil then
		table.insert(Nests.purchasable, def)
	end
end

return table.freeze(Nests)

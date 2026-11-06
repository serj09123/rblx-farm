--!strict
-- Mutations: rolled independently per hatch, then resolved by group and max count.

export type MutationDef = {
	id: string,
	displayName: string,
	chance: number, -- base probability 0..1
	multiplier: number, -- value multiplier
	group: string?, -- at most one mutation per group survives (highest multiplier wins)
	color: { number },
	eventOnly: boolean?, -- base chance 0; only seasons/events raise it
}

export type ComboDef = {
	id: string,
	displayName: string,
	requires: { string },
	multiplier: number,
}

local Mutations = {}

Mutations.maxPerCreature = 3
Mutations.maxChance = 0.5 -- cap after all modifiers

Mutations.list = {
	{ id = "Shiny", displayName = "Shiny", chance = 0.04, multiplier = 1.5, color = { 255, 255, 200 } },
	{ id = "Giant", displayName = "Giant", chance = 0.02, multiplier = 2, group = "size", color = { 255, 200, 120 } },
	{ id = "Tiny", displayName = "Tiny", chance = 0.02, multiplier = 1.3, group = "size", color = { 200, 255, 200 } },
	{ id = "Frozen", displayName = "Frozen", chance = 0.01, multiplier = 2.5, color = { 150, 230, 255 } },
	{ id = "Electric", displayName = "Electric", chance = 0.01, multiplier = 2.5, color = { 255, 240, 80 } },
	{
		id = "Golden",
		displayName = "Golden",
		chance = 0.005,
		multiplier = 4,
		group = "metal",
		color = { 255, 200, 40 },
	},
	{ id = "Shadow", displayName = "Shadow", chance = 0.0025, multiplier = 5, color = { 60, 40, 80 } },
	{
		id = "Rainbow",
		displayName = "Rainbow",
		chance = 0.0015,
		multiplier = 8,
		group = "metal",
		color = { 255, 100, 200 },
	},
	{ id = "Cosmic", displayName = "Cosmic", chance = 0.0005, multiplier = 12, color = { 120, 80, 255 } },
	{ id = "Harvest", displayName = "Harvest", chance = 0, multiplier = 3, color = { 255, 150, 40 }, eventOnly = true },
} :: { MutationDef }

Mutations.combos = {
	{ id = "Thunderfrost", displayName = "Thunderfrost", requires = { "Frozen", "Electric" }, multiplier = 1.5 },
	{ id = "Voidborn", displayName = "Voidborn", requires = { "Shadow", "Cosmic" }, multiplier = 2 },
	{ id = "Gilded", displayName = "Gilded", requires = { "Golden", "Shiny" }, multiplier = 1.25 },
	{ id = "PrismaticTitan", displayName = "Prismatic Titan", requires = { "Rainbow", "Giant" }, multiplier = 1.5 },
} :: { ComboDef }

Mutations.byId = {} :: { [string]: MutationDef }
for _, def in Mutations.list do
	Mutations.byId[def.id] = def
end

return table.freeze(Mutations)

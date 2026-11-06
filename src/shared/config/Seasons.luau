--!strict
-- Seasonal events. Add an entry to schedule an event; no code changes needed.
-- Times are UTC unix seconds. Use https://www.epochconverter.com/ or os.time in Studio.

export type SeasonDef = {
	id: string,
	displayName: string,
	description: string,
	startsAt: number,
	endsAt: number,
	color: { number },
	coinBonus: number?,
	growthMultiplier: number?,
	mutationChances: { [string]: number }?, -- multipliers
	mutationBaseChances: { [string]: number }?, -- absolute chance for eventOnly mutations
	speciesWeightInRarity: number?, -- weight of event species inside their rarity (base species weigh 1)
}

local Seasons = {}

Seasons.list = {
	{
		id = "harvest_festival_2026",
		displayName = "Harvest Festival",
		description = "Gourdlings hatch from Grove+ nests! Harvest mutation, +10% coins.",
		startsAt = 1795132800, -- 2026-11-20 00:00 UTC
		endsAt = 1796342400, -- 2026-12-04 00:00 UTC
		color = { 255, 150, 40 },
		coinBonus = 0.1,
		mutationBaseChances = { Harvest = 0.02 },
		speciesWeightInRarity = 2,
	},
	{
		id = "winter_frost_2026",
		displayName = "Winter Frost",
		description = "Frostfawn appears! Frozen mutations x2.",
		startsAt = 1797552000, -- 2026-12-18 00:00 UTC
		endsAt = 1799366400, -- 2027-01-08 00:00 UTC
		color = { 200, 235, 255 },
		mutationChances = { Frozen = 2 },
		speciesWeightInRarity = 1,
	},
} :: { SeasonDef }

Seasons.byId = {} :: { [string]: SeasonDef }
for _, def in Seasons.list do
	Seasons.byId[def.id] = def
end

return table.freeze(Seasons)

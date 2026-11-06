--!strict
-- Server-wide weather/anomaly events that change mutation chances.

export type Modifiers = {
	coinBonus: number?, -- additive
	growthMultiplier: number?,
	luckMultiplier: number?,
	mutationMultiplier: number?, -- all mutations
	mutationChances: { [string]: number }?, -- per-mutation multipliers
}

export type WeatherDef = {
	id: string,
	displayName: string,
	description: string,
	weight: number,
	durationSeconds: number,
	color: { number },
	modifiers: Modifiers,
}

local Weather = {}

Weather.minGapSeconds = 10 * 60
Weather.maxGapSeconds = 16 * 60
Weather.warningSeconds = 30
Weather.firstEventDelaySeconds = 4 * 60

Weather.list = {
	{
		id = "blizzard",
		displayName = "Blizzard",
		description = "Frozen mutations x6",
		weight = 3,
		durationSeconds = 180,
		color = { 180, 230, 255 },
		modifiers = { mutationChances = { Frozen = 6 } },
	},
	{
		id = "thunderstorm",
		displayName = "Thunderstorm",
		description = "Electric mutations x6",
		weight = 3,
		durationSeconds = 180,
		color = { 255, 240, 90 },
		modifiers = { mutationChances = { Electric = 6 } },
	},
	{
		id = "golden_hour",
		displayName = "Golden Hour",
		description = "Golden mutations x5, +10% coins",
		weight = 2,
		durationSeconds = 180,
		color = { 255, 200, 60 },
		modifiers = { coinBonus = 0.1, mutationChances = { Golden = 5 } },
	},
	{
		id = "eclipse",
		displayName = "Eclipse",
		description = "Shadow x5, Cosmic x2",
		weight = 1.5,
		durationSeconds = 210,
		color = { 90, 60, 130 },
		modifiers = { mutationChances = { Shadow = 5, Cosmic = 2 } },
	},
	{
		id = "aurora",
		displayName = "Aurora",
		description = "Rainbow x4, all mutations x1.25",
		weight = 1,
		durationSeconds = 240,
		color = { 150, 255, 200 },
		modifiers = { mutationMultiplier = 1.25, mutationChances = { Rainbow = 4 } },
	},
	{
		id = "meteor_shower",
		displayName = "Meteor Shower",
		description = "Cosmic x6, Giant x2",
		weight = 1,
		durationSeconds = 180,
		color = { 160, 120, 255 },
		modifiers = { mutationChances = { Cosmic = 6, Giant = 2 } },
	},
	{
		id = "growth_rain",
		displayName = "Growth Rain",
		description = "Nests grow 30% faster",
		weight = 2,
		durationSeconds = 240,
		color = { 120, 200, 255 },
		modifiers = { growthMultiplier = 1.3 },
	},
} :: { WeatherDef }

Weather.byId = {} :: { [string]: WeatherDef }
for _, def in Weather.list do
	Weather.byId[def.id] = def
end

return table.freeze(Weather)

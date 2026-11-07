--!strict
-- Cases: opened with one key of the same tier. Keys come from quests/daily rewards,
-- coins (price below) or Robux products (see Monetization). Pools contain nests and
-- mutagens only. Weights are relative. `grade` is a rarity id (Rarities) used for the
-- strip colour and for pity. Odds shown to players come from CaseRoller.odds, which
-- uses the same math as the roll.

export type Entry = {
	kind: "nest" | "mutagen",
	id: string, -- nest id or mutation id
	count: number,
	weight: number,
	grade: string,
}

export type Pity = {
	minGrade: string,
	threshold: number, -- the Nth open without reaching minGrade is guaranteed to
}

export type TierDef = {
	id: string,
	displayName: string,
	icon: string,
	keyName: string,
	coinPrice: number, -- coins per key
	color: { number },
	pity: Pity,
	pool: { Entry },
}

local Cases = {}

Cases.maxKeysPerTier = 999
Cases.maxMutagensPerType = 999
Cases.maxBuyAmount = 10

Cases.list = {
	{
		id = "sprout",
		displayName = "Sprout Case",
		icon = "🌱",
		keyName = "Sprout Key",
		coinPrice = 0, -- TEMP: free for testing (was 500)
		color = { 120, 210, 110 },
		pity = { minGrade = "Rare", threshold = 10 },
		pool = {
			{ kind = "nest", id = "meadow", count = 3, weight = 38, grade = "Common" },
			{ kind = "nest", id = "meadow", count = 6, weight = 20, grade = "Uncommon" },
			{ kind = "nest", id = "grove", count = 2, weight = 20, grade = "Uncommon" },
			{ kind = "mutagen", id = "Shiny", count = 1, weight = 9, grade = "Rare" },
			{ kind = "mutagen", id = "Tiny", count = 1, weight = 4, grade = "Rare" },
			{ kind = "nest", id = "crystal", count = 1, weight = 4, grade = "Rare" },
			{ kind = "mutagen", id = "Giant", count = 1, weight = 2, grade = "Epic" },
			{ kind = "mutagen", id = "Frozen", count = 1, weight = 1.2, grade = "Epic" },
			{ kind = "mutagen", id = "Electric", count = 1, weight = 1.2, grade = "Epic" },
			{ kind = "nest", id = "crystal", count = 3, weight = 0.5, grade = "Epic" },
			{ kind = "mutagen", id = "Golden", count = 1, weight = 0.1, grade = "Legendary" },
		},
	},
	{
		id = "moon",
		displayName = "Moonlit Case",
		icon = "🌙",
		keyName = "Moon Key",
		coinPrice = 0, -- TEMP: free for testing (was 3000)
		color = { 120, 150, 255 },
		pity = { minGrade = "Epic", threshold = 10 },
		pool = {
			{ kind = "nest", id = "grove", count = 4, weight = 30, grade = "Uncommon" },
			{ kind = "nest", id = "crystal", count = 2, weight = 26, grade = "Rare" },
			{ kind = "mutagen", id = "Shiny", count = 2, weight = 12, grade = "Rare" },
			{ kind = "nest", id = "storm", count = 1, weight = 12, grade = "Rare" },
			{ kind = "mutagen", id = "Frozen", count = 1, weight = 6, grade = "Epic" },
			{ kind = "mutagen", id = "Electric", count = 1, weight = 6, grade = "Epic" },
			{ kind = "nest", id = "storm", count = 3, weight = 3.5, grade = "Epic" },
			{ kind = "mutagen", id = "Golden", count = 1, weight = 2.5, grade = "Epic" },
			{ kind = "nest", id = "celestial", count = 1, weight = 1.2, grade = "Legendary" },
			{ kind = "mutagen", id = "Shadow", count = 1, weight = 0.7, grade = "Legendary" },
			{ kind = "mutagen", id = "Rainbow", count = 1, weight = 0.1, grade = "Mythic" },
		},
	},
	{
		id = "star",
		displayName = "Starforged Case",
		icon = "⭐",
		keyName = "Star Key",
		coinPrice = 0, -- TEMP: free for testing (was 12000)
		color = { 255, 200, 70 },
		pity = { minGrade = "Legendary", threshold = 12 },
		pool = {
			{ kind = "nest", id = "crystal", count = 4, weight = 30, grade = "Rare" },
			{ kind = "nest", id = "storm", count = 3, weight = 26, grade = "Epic" },
			{ kind = "mutagen", id = "Golden", count = 1, weight = 14, grade = "Epic" },
			{ kind = "nest", id = "celestial", count = 2, weight = 12, grade = "Epic" },
			{ kind = "mutagen", id = "Shadow", count = 1, weight = 7, grade = "Legendary" },
			{ kind = "nest", id = "celestial", count = 4, weight = 5, grade = "Legendary" },
			{ kind = "mutagen", id = "Rainbow", count = 1, weight = 3.5, grade = "Legendary" },
			{ kind = "mutagen", id = "Cosmic", count = 1, weight = 2, grade = "Mythic" },
			{ kind = "nest", id = "celestial", count = 8, weight = 0.5, grade = "Mythic" },
		},
	},
} :: { TierDef }

Cases.byId = {} :: { [string]: TierDef }
Cases.order = {} :: { string }
for _, def in Cases.list do
	Cases.byId[def.id] = def
	table.insert(Cases.order, def.id)
end

return table.freeze(Cases)

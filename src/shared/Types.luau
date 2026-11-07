--!strict
-- Shared data shapes. Persisted shapes must stay DataStore-serializable:
-- string keys for dictionaries, no Instances, no NaN/inf.

export type Creature = {
	id: string,
	species: string,
	rarity: string,
	mutations: { string },
	size: number,
	obtainedAt: number,
	source: string, -- "hatch" | "trade" | "reward" | "tutorial"
	locked: boolean?,
}

export type NestSlot = {
	nestId: string,
	progress: number, -- seconds of growth accumulated
	required: number, -- seconds needed
	lastUpdate: number, -- unix time of last progress integration
	cheers: { [string]: boolean }, -- userId (string) -> true
	mutagen: string?, -- mutation id applied from a case mutagen; guaranteed at hatch
}

export type QuestState = {
	id: string,
	progress: number,
	target: number,
	claimed: boolean,
}

export type TradeHistoryEntry = {
	id: string,
	at: number,
	partner: number?, -- partner's UserId
	gave: number, -- critters given
	got: number, -- critters received
	coins: number, -- net coins (after tax)
	top: string?, -- best rarity received
}

export type Profile = {
	schemaVersion: number,
	coins: number,
	creatures: { [string]: Creature },
	inventoryNests: { [string]: number },
	mutagens: { [string]: number }, -- mutation id -> count
	cases: {
		keys: { [string]: number }, -- case tier id -> keys
		pity: { [string]: number }, -- case tier id -> opens since last minGrade+
		opened: number,
	},
	nests: { [string]: NestSlot },
	habitats: { [string]: string },
	upgrades: { [string]: number },
	index: {
		species: { [string]: { at: number, mutations: { [string]: boolean } } },
		claimed: { [string]: boolean },
	},
	pity: { [string]: number },
	boosts: { luckUntil: number, growthUntil: number },
	income: { lastAccrual: number, carry: number },
	daily: { lastClaimDay: number, cycleDay: number },
	quests: {
		dayKey: number,
		daily: { QuestState },
		rerollsUsed: number,
		weekKey: number,
		weekly: { QuestState },
	},
	tutorial: { step: number, done: boolean, starterGiven: boolean },
	purchases: { receipts: { [string]: number }, passes: { [string]: boolean } },
	trades: { applied: { [string]: number }, history: { TradeHistoryEntry } },
	stats: {
		coinsEarned: number,
		hatched: number,
		sold: number,
		donated: number,
		cheersGiven: number,
		trades: number,
		playSeconds: number,
		firstJoin: number,
		lastJoin: number,
		sessions: number,
	},
	settings: { sfx: boolean, music: boolean },
}

-- Combined gameplay modifiers for one player at one moment.
export type Modifiers = {
	coinMultiplier: number, -- multiplicative (passes)
	coinBonus: number, -- additive bonus (bloom, events, community)
	growthMultiplier: number,
	luckMultiplier: number,
	mutationMultiplier: number,
	mutationChances: { [string]: number }, -- per-mutation multipliers
	mutationBaseChances: { [string]: number }, -- overrides for event-only mutations
	activeSeasons: { string },
}

-- Abstraction over a GlobalDataStore so persistence logic is testable.
export type StoreAdapter = {
	update: (self: StoreAdapter, key: string, transform: (current: any) -> any) -> (boolean, any),
	get: (self: StoreAdapter, key: string) -> (boolean, any),
}

-- Pseudo-random source; Roblox `Random` satisfies this.
export type Rng = {
	NextNumber: (self: Rng) -> number,
	NextInteger: (self: Rng, min: number, max: number) -> number,
}

return {}

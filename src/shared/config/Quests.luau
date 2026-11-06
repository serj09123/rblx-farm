--!strict
-- Daily and weekly quest pools. Kinds are emitted by gameplay services via QuestService.

local RewardsConfig = require(script.Parent.Rewards)

export type QuestKind =
	"hatch"
	| "hatchRarePlus"
	| "hatchMutated"
	| "sell"
	| "earnCoins"
	| "essence"
	| "placeHabitat"
	| "cheer"
	| "discover"
	| "upgrade"
	| "donate"

export type QuestDef = {
	id: string,
	kind: QuestKind,
	target: number,
	targetScalesWithTier: boolean?, -- multiplies target by tierCoinScale (for coin quests)
	text: string, -- "%d" is replaced with the target
	reward: RewardsConfig.Reward,
}

local Quests = {}

Quests.dailyCount = 3
Quests.weeklyCount = 3
Quests.freeDailyRerolls = 1

Quests.daily = {
	{ id = "d_hatch10", kind = "hatch", target = 10, text = "Hatch %d critters", reward = { coins = 150, scaleWithTier = true } },
	{ id = "d_hatch25", kind = "hatch", target = 25, text = "Hatch %d critters", reward = { coins = 350, scaleWithTier = true } },
	{ id = "d_rare", kind = "hatchRarePlus", target = 1, text = "Hatch a Rare or better", reward = { coins = 250, scaleWithTier = true } },
	{ id = "d_mutated", kind = "hatchMutated", target = 1, text = "Hatch a mutated critter", reward = { coins = 200, scaleWithTier = true } },
	{ id = "d_sell8", kind = "sell", target = 8, text = "Sell %d critters", reward = { coins = 150, scaleWithTier = true } },
	{ id = "d_earn", kind = "earnCoins", target = 1500, targetScalesWithTier = true, text = "Earn %d coins", reward = { nests = { meadow = 3 } } },
	{ id = "d_essence", kind = "essence", target = 30, text = "Give %d essence to the Skyheart", reward = { coins = 200, scaleWithTier = true } },
	{ id = "d_habitat", kind = "placeHabitat", target = 2, text = "Place %d critters in habitats", reward = { coins = 100, scaleWithTier = true } },
	{ id = "d_donate", kind = "donate", target = 2, text = "Donate %d critters to the Skyheart", reward = { coins = 200, scaleWithTier = true } },
} :: { QuestDef }

Quests.weekly = {
	{ id = "w_hatch150", kind = "hatch", target = 150, text = "Hatch %d critters", reward = { coins = 3000, scaleWithTier = true } },
	{ id = "w_essence", kind = "essence", target = 500, text = "Give %d essence to the Skyheart", reward = { nests = { skyheart = 2 } } },
	{ id = "w_cheer", kind = "cheer", target = 10, text = "Cheer %d neighbour nests", reward = { nests = { skyheart = 1 }, coins = 1000, scaleWithTier = true } },
	{ id = "w_discover", kind = "discover", target = 3, text = "Discover %d new index entries", reward = { coins = 2500, scaleWithTier = true } },
	{ id = "w_upgrade", kind = "upgrade", target = 3, text = "Buy %d upgrades", reward = { growthBoostSeconds = 900 } },
	{ id = "w_rare5", kind = "hatchRarePlus", target = 5, text = "Hatch %d Rare or better", reward = { coins = 2000, scaleWithTier = true } },
} :: { QuestDef }

Quests.byId = {} :: { [string]: QuestDef }
for _, def in Quests.daily do
	Quests.byId[def.id] = def
end
for _, def in Quests.weekly do
	Quests.byId[def.id] = def
end

return table.freeze(Quests)

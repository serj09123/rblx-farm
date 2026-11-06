--!strict
-- Collection index milestones. "entries" = discovered species + discovered species×mutation pairs.

local RewardsConfig = require(script.Parent.Rewards)

export type Milestone = {
	id: string,
	entries: number,
	reward: RewardsConfig.Reward,
}

return table.freeze({
	milestones = {
		{ id = "idx5", entries = 5, reward = { coins = 300 } },
		{ id = "idx10", entries = 10, reward = { nests = { grove = 2 } } },
		{ id = "idx20", entries = 20, reward = { coins = 4000 } },
		{ id = "idx30", entries = 30, reward = { nests = { crystal = 2 } } },
		{ id = "idx45", entries = 45, reward = { nests = { skyheart = 2 } } },
		{ id = "idx60", entries = 60, reward = { coins = 60000 } },
		{ id = "idx80", entries = 80, reward = { nests = { storm = 2 } } },
		{ id = "idx110", entries = 110, reward = { nests = { celestial = 2 } } },
	} :: { Milestone },
})

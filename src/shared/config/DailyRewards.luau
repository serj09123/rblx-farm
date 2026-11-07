--!strict
-- 7-day non-punishing cycle: missing a day never resets progress.

local RewardsConfig = require(script.Parent.Rewards)

return table.freeze({
	cycle = {
		{ coins = 100, scaleWithTier = true },
		{ coins = 200, scaleWithTier = true },
		{ nests = { meadow = 3 } },
		{ coins = 400, scaleWithTier = true },
		{ growthBoostSeconds = 600 },
		{ coins = 800, scaleWithTier = true, keys = { sprout = 1 } },
		{ nests = { skyheart = 1 }, keys = { moon = 1 } },
	} :: { RewardsConfig.Reward },
})

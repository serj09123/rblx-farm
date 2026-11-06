--!strict
-- Currency sources/sinks that are not owned by a more specific config.

return table.freeze({
	startingCoins = 100,
	maxCoins = 1e15, -- hard clamp, protects against overflow bugs

	-- Habitat income: a creature earns its own value every `incomePaybackSeconds`.
	incomePaybackSeconds = 1800,
	offlineIncomeRate = 0.5,
	offlineIncomeCapSeconds = 8 * 3600,
	incomeTickSeconds = 5, -- server credits income in batches

	-- Sell multipliers (bonuses are additive, pass multiplier is multiplicative).
	communityBonusPerPlayer = 0.05,
	communityBonusMax = 0.2,

	-- Inventory
	inventoryHardCap = 400,

	-- Donating a creature to the Skyheart
	donateEssenceMultiplier = 3,

	-- Trade tax on coins (burned)
	tradeCoinTax = 0.05,
})

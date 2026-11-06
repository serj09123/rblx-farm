--!strict
-- Skyheart (server goal), Bloom buff and Cheer (helping neighbours).

return table.freeze({
	skyheart = {
		minTarget = 60,
		-- Each player's share of the target, by highest unlocked nest tier.
		sharePerTier = { 40, 80, 200, 480, 1200 },
		bloomSeconds = 8 * 60,
		rewardNest = "skyheart",
		topContributorBonusNests = 1,
		minContributorsForTopBonus = 2,
		cheerEssence = 1,
	},
	bloom = {
		coinBonus = 0.5, -- additive sell/income bonus
		growthMultiplier = 1.25,
		mutationMultiplier = 1.5,
	},
	cheer = {
		progressFraction = 0.04, -- of the nest's required growth
		maxCheerersPerNest = 5,
		maxPerHourPerHelper = 40,
		helperCoinsPerTier = { 5, 12, 30, 70, 160 },
		maxDistance = 20, -- studs between helper and nest
	},
})

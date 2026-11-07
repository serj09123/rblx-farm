--!strict
-- Shared reward shape + progression scaling used by quests, daily rewards and index.

export type Reward = {
	coins: number?,
	nests: { [string]: number }?,
	keys: { [string]: number }?, -- case tier id -> keys
	growthBoostSeconds: number?,
	scaleWithTier: boolean?, -- multiply coins by tierCoinScale[playerTier]
}

return table.freeze({
	-- Coin reward multiplier by the player's highest unlocked nest tier.
	tierCoinScale = { 1, 3, 10, 30, 90 },
})

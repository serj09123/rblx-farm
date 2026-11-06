--!strict
-- Luck and pity rules. Shown verbatim to players in the odds panel.

return table.freeze({
	-- Luck multiplies the weight of luckAffected rarities, then renormalises.
	maxLuck = 3,

	-- Pity: after `threshold` hatches without reaching `minRarity` or better,
	-- the next hatch only rolls rarities >= minRarity that the nest can produce.
	pity = {
		{ id = "rarePlus", minRarity = "Rare", threshold = 15 },
		{ id = "epicPlus", minRarity = "Epic", threshold = 75 },
		{ id = "legendaryPlus", minRarity = "Legendary", threshold = 400 },
	},

	-- Size roll (uniform). Value scales linearly with size.
	sizeMin = 0.8,
	sizeMax = 1.25,

	roundingDisclaimer = "Probabilities are rounded; the total of displayed individual probabilities may not equal 100%.",
})

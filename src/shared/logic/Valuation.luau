--!strict
-- Creature value, sell price and passive income.

local config = script.Parent.Parent.config
local Creatures = require(config.Creatures)
local Economy = require(config.Economy)
local Mutations = require(config.Mutations)

local Valuation = {}

type CreatureLike = { species: string, mutations: { string }, size: number }

function Valuation.combos(mutations: { string }): { Mutations.ComboDef }
	local has = {}
	for _, id in mutations do
		has[id] = true
	end
	local list = {}
	for _, combo in Mutations.combos do
		local ok = true
		for _, required in combo.requires do
			if not has[required] then
				ok = false
				break
			end
		end
		if ok then
			table.insert(list, combo)
		end
	end
	return list
end

function Valuation.multiplier(mutations: { string }): number
	local mult = 1
	for _, id in mutations do
		local def = Mutations.byId[id]
		if def then
			mult *= def.multiplier
		end
	end
	for _, combo in Valuation.combos(mutations) do
		mult *= combo.multiplier
	end
	return mult
end

-- Intrinsic value (integer). Shown in inventory and trade windows.
function Valuation.value(creature: CreatureLike): number
	local species = Creatures.byId[creature.species]
	if not species then
		return 0
	end
	local size = math.clamp(tonumber(creature.size) or 1, 0.1, 10)
	return math.max(1, math.floor(species.baseValue * Valuation.multiplier(creature.mutations) * size + 0.5))
end

-- Price paid when selling now with the player's current multipliers.
function Valuation.sellPrice(creature: CreatureLike, coinMultiplier: number, coinBonus: number): number
	return math.floor(Valuation.value(creature) * coinMultiplier * (1 + coinBonus))
end

-- Base habitat income per second (before personal/global multipliers).
function Valuation.incomePerSecond(creature: CreatureLike): number
	return Valuation.value(creature) / Economy.incomePaybackSeconds
end

return table.freeze(Valuation)

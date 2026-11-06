--!strict
-- Odds for a hatch. The server rolls with these exact functions and the client
-- displays their output, so displayed odds are always the real odds.

local config = script.Parent.Parent.config
local Creatures = require(config.Creatures)
local Nests = require(config.Nests)
local Odds = require(config.Odds)
local Rarities = require(config.Rarities)
local Seasons = require(config.Seasons)

local HatchOdds = {}

export type PityStatus = {
	id: string,
	minRarity: string,
	threshold: number,
	count: number,
	remaining: number, -- hatches until guaranteed (1 = next hatch)
	applies: boolean, -- nest can produce this rarity
}

local function isSeasonActive(seasonId: string, activeSeasons: { string }): boolean
	return table.find(activeSeasons, seasonId) ~= nil
end

-- Species weights inside one rarity for a nest.
function HatchOdds.speciesWeights(
	nestDef: Nests.NestDef,
	rarity: string,
	activeSeasons: { string }
): { [string]: number }
	local weights = {}
	for _, species in Creatures.byRarity[rarity] or {} do
		if species.eventOnly == nil then
			weights[species.id] = species.weight or 1
		elseif nestDef.seasonSpecies and isSeasonActive(species.eventOnly, activeSeasons) then
			local season = Seasons.byId[species.eventOnly]
			weights[species.id] = if season then season.speciesWeightInRarity or 1 else 1
		end
	end
	return weights
end

local function normalize(weights: { [string]: number }): { [string]: number }
	local total = 0
	for _, w in weights do
		total += w
	end
	local result = {}
	if total <= 0 then
		return result
	end
	for key, w in weights do
		result[key] = w / total
	end
	return result
end

local function rarityAvailable(nestDef: Nests.NestDef, minOrder: number): boolean
	for rarity, weight in nestDef.weights do
		if weight > 0 and Rarities.order(rarity) >= minOrder then
			return true
		end
	end
	return false
end

-- Status of each pity rule for this nest and counter state.
function HatchOdds.pityStatus(nestDef: Nests.NestDef, pity: { [string]: number }): { PityStatus }
	local list = {}
	for _, rule in Odds.pity do
		local count = pity[rule.id] or 0
		table.insert(list, {
			id = rule.id,
			minRarity = rule.minRarity,
			threshold = rule.threshold,
			count = count,
			remaining = math.max(1, rule.threshold - count),
			applies = rarityAvailable(nestDef, Rarities.order(rule.minRarity)),
		})
	end
	return list
end

-- Highest guaranteed minimum rarity for the next hatch, if a pity rule triggers.
function HatchOdds.pityTarget(nestDef: Nests.NestDef, pity: { [string]: number }): string?
	local best: string? = nil
	local bestOrder = 0
	for _, status in HatchOdds.pityStatus(nestDef, pity) do
		if status.applies and status.remaining <= 1 then
			local order = Rarities.order(status.minRarity)
			if order > bestOrder then
				best, bestOrder = status.minRarity, order
			end
		end
	end
	return best
end

-- Probability of each rarity for the next hatch.
function HatchOdds.rarityOdds(
	nestDef: Nests.NestDef,
	luck: number,
	pity: { [string]: number },
	activeSeasons: { string }
): ({ [string]: number }, string?)
	local effectiveLuck = math.clamp(luck, 1, Odds.maxLuck)
	local target = HatchOdds.pityTarget(nestDef, pity)
	local minOrder = if target then Rarities.order(target) else 0
	local weights = {}
	for rarity, weight in nestDef.weights do
		local def = Rarities.byId[rarity]
		if
			def
			and weight > 0
			and def.order >= minOrder
			and next(HatchOdds.speciesWeights(nestDef, rarity, activeSeasons))
		then
			weights[rarity] = weight * (if def.luckAffected then effectiveLuck else 1)
		end
	end
	return normalize(weights), target
end

export type SpeciesOdds = { species: string, rarity: string, probability: number }

-- Full breakdown P(species) = P(rarity) * P(species | rarity), sorted rarest first.
function HatchOdds.speciesOdds(
	nestDef: Nests.NestDef,
	luck: number,
	pity: { [string]: number },
	activeSeasons: { string }
): { SpeciesOdds }
	local rarityOdds = HatchOdds.rarityOdds(nestDef, luck, pity, activeSeasons)
	local list = {}
	for rarity, p in rarityOdds do
		for species, q in normalize(HatchOdds.speciesWeights(nestDef, rarity, activeSeasons)) do
			table.insert(list, { species = species, rarity = rarity, probability = p * q })
		end
	end
	table.sort(list, function(a, b)
		local oa, ob = Rarities.order(a.rarity), Rarities.order(b.rarity)
		if oa ~= ob then
			return oa > ob
		end
		return a.species < b.species
	end)
	return list
end

-- Picks a key from a probability map using one uniform number in [0, 1).
-- Keys are iterated in sorted order so results are deterministic for a given roll.
function HatchOdds.pick(probabilities: { [string]: number }, roll: number): string?
	local keys = {}
	for key in probabilities do
		table.insert(keys, key)
	end
	table.sort(keys)
	local acc = 0
	local last: string? = nil
	for _, key in keys do
		acc += probabilities[key]
		last = key
		if roll < acc then
			return key
		end
	end
	return last -- floating point remainder
end

return table.freeze(HatchOdds)

--!strict
-- Rolls the outcome of a hatch: rarity -> species -> mutations -> size.
-- Pure: all randomness comes from `rng`, all state from `ctx`.

local config = script.Parent.Parent.config
local HatchOdds = require(script.Parent.HatchOdds)
local MutationRoller = require(script.Parent.MutationRoller)
local Nests = require(config.Nests)
local Odds = require(config.Odds)
local Rarities = require(config.Rarities)
local Creatures = require(config.Creatures)
local Types = require(script.Parent.Parent.Types)

local Hatchery = {}

export type Context = {
	luck: number,
	pity: { [string]: number },
	modifiers: Types.Modifiers?,
	activeSeasons: { string },
}

export type Outcome = {
	species: string,
	rarity: string,
	mutations: { string },
	size: number,
	pityTriggered: string?,
}

local function rollSize(rng: Types.Rng): number
	local size = Odds.sizeMin + rng:NextNumber() * (Odds.sizeMax - Odds.sizeMin)
	return math.floor(size * 100 + 0.5) / 100
end

function Hatchery.roll(nestDef: Nests.NestDef, ctx: Context, rng: Types.Rng): Outcome
	local guaranteed = nestDef.guaranteed
	if guaranteed then
		local species = Creatures.byId[guaranteed.species]
		return {
			species = guaranteed.species,
			rarity = species.rarity,
			mutations = table.clone(guaranteed.mutations),
			size = guaranteed.size,
			pityTriggered = nil,
		}
	end

	local rarityOdds, pityTarget = HatchOdds.rarityOdds(nestDef, ctx.luck, ctx.pity, ctx.activeSeasons)
	local rarity = HatchOdds.pick(rarityOdds, rng:NextNumber())
	assert(rarity, "nest " .. nestDef.id .. " has no rollable rarity")
	local speciesWeights = HatchOdds.speciesWeights(nestDef, rarity, ctx.activeSeasons)
	local total = 0
	for _, w in speciesWeights do
		total += w
	end
	local speciesOdds = {}
	for id, w in speciesWeights do
		speciesOdds[id] = w / total
	end
	local species = HatchOdds.pick(speciesOdds, rng:NextNumber()) :: string

	local mutations = MutationRoller.roll(MutationRoller.chances(ctx.modifiers), rng)

	return {
		species = species,
		rarity = rarity,
		mutations = mutations,
		size = rollSize(rng),
		pityTriggered = pityTarget,
	}
end

-- New pity counters after hatching `rarity` from `nestDef`. Counters only advance
-- for rules whose rarity the nest can produce.
function Hatchery.nextPity(nestDef: Nests.NestDef, pity: { [string]: number }, rarity: string): { [string]: number }
	local result = table.clone(pity)
	local order = Rarities.order(rarity)
	for _, status in HatchOdds.pityStatus(nestDef, pity) do
		if order >= Rarities.order(status.minRarity) then
			result[status.id] = 0
		elseif status.applies then
			result[status.id] = status.count + 1
		end
	end
	return result
end

return table.freeze(Hatchery)

--!strict
-- Combines modifier sources (weather, bloom, seasons, boosts) into one table.
-- Coin bonuses add up; growth, luck and mutation multipliers multiply.

local config = script.Parent.Parent.config
local Odds = require(config.Odds)
local Seasons = require(config.Seasons)
local Types = require(script.Parent.Parent.Types)
local Weather = require(config.Weather)

local ModifierMath = {}

export type Base = {
	coinMultiplier: number,
	growthMultiplier: number,
	luckMultiplier: number,
}

function ModifierMath.activeSeasons(now: number): { Seasons.SeasonDef }
	local list = {}
	for _, def in Seasons.list do
		if now >= def.startsAt and now < def.endsAt then
			table.insert(list, def)
		end
	end
	return list
end

function ModifierMath.combine(
	base: Base,
	sources: { Weather.Modifiers },
	seasons: { Seasons.SeasonDef }
): Types.Modifiers
	local result: Types.Modifiers = {
		coinMultiplier = base.coinMultiplier,
		coinBonus = 0,
		growthMultiplier = base.growthMultiplier,
		luckMultiplier = base.luckMultiplier,
		mutationMultiplier = 1,
		mutationChances = {},
		mutationBaseChances = {},
		activeSeasons = {},
	}
	local function mergeChances(chances: { [string]: number }?)
		if chances then
			for id, mult in chances do
				result.mutationChances[id] = (result.mutationChances[id] or 1) * mult
			end
		end
	end
	for _, source in sources do
		result.coinBonus += source.coinBonus or 0
		result.growthMultiplier *= source.growthMultiplier or 1
		result.luckMultiplier *= source.luckMultiplier or 1
		result.mutationMultiplier *= source.mutationMultiplier or 1
		mergeChances(source.mutationChances)
	end
	for _, season in seasons do
		result.coinBonus += season.coinBonus or 0
		result.growthMultiplier *= season.growthMultiplier or 1
		mergeChances(season.mutationChances)
		if season.mutationBaseChances then
			for id, chance in season.mutationBaseChances do
				result.mutationBaseChances[id] = math.max(result.mutationBaseChances[id] or 0, chance)
			end
		end
		table.insert(result.activeSeasons, season.id)
	end
	result.luckMultiplier = math.clamp(result.luckMultiplier, 1, Odds.maxLuck)
	return result
end

return table.freeze(ModifierMath)

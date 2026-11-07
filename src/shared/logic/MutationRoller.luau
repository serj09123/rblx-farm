--!strict
-- Mutation chances and rolling. Each mutation rolls independently; then group
-- conflicts and the max count are resolved by keeping the highest multipliers.

local config = script.Parent.Parent.config
local Mutations = require(config.Mutations)
local Types = require(script.Parent.Parent.Types)

local MutationRoller = {}

-- Final per-mutation chance after modifiers (what the odds panel shows).
function MutationRoller.chances(mods: Types.Modifiers?): { [string]: number }
	local result = {}
	for _, def in Mutations.list do
		local base = def.chance
		if mods and mods.mutationBaseChances[def.id] then
			base = math.max(base, mods.mutationBaseChances[def.id])
		end
		if base <= 0 then
			result[def.id] = 0
			continue
		end
		local chance = base
		if mods then
			chance *= mods.mutationMultiplier * (mods.mutationChances[def.id] or 1)
		end
		result[def.id] = math.min(chance, Mutations.maxChance)
	end
	return result
end

local function resolveCapped(rolled: { string }, cap: number): { string }
	local bestInGroup: { [string]: Mutations.MutationDef } = {}
	local kept: { Mutations.MutationDef } = {}
	for _, id in rolled do
		local def = Mutations.byId[id]
		if not def then
			continue
		end
		if def.group then
			local current = bestInGroup[def.group]
			if not current or def.multiplier > current.multiplier then
				bestInGroup[def.group] = def
			end
		else
			table.insert(kept, def)
		end
	end
	for _, def in bestInGroup do
		table.insert(kept, def)
	end
	table.sort(kept, function(a, b)
		return a.multiplier > b.multiplier
	end)
	local survivors: { [string]: boolean } = {}
	for i = 1, math.min(#kept, cap) do
		survivors[kept[i].id] = true
	end
	local result = {}
	for _, def in Mutations.list do
		if survivors[def.id] then
			table.insert(result, def.id)
		end
	end
	return result
end

-- Applies group exclusivity and the per-creature cap. Output keeps config order.
function MutationRoller.resolve(rolled: { string }): { string }
	return resolveCapped(rolled, Mutations.maxPerCreature)
end

-- Like resolve, but `forced` (a mutagen) always survives: it displaces any rolled
-- mutation in its group and takes one of the maxPerCreature slots.
function MutationRoller.resolveForced(rolled: { string }, forced: string): { string }
	local forcedDef = Mutations.byId[forced]
	if not forcedDef then
		return MutationRoller.resolve(rolled)
	end
	local others = {}
	for _, id in rolled do
		local def = Mutations.byId[id]
		if def and id ~= forced and not (forcedDef.group ~= nil and def.group == forcedDef.group) then
			table.insert(others, id)
		end
	end
	local kept = resolveCapped(others, Mutations.maxPerCreature - 1)
	table.insert(kept, forced)
	local result = {}
	for _, def in Mutations.list do
		if table.find(kept, def.id) then
			table.insert(result, def.id)
		end
	end
	return result
end

-- Independent per-mutation rolls, before group/cap resolution.
function MutationRoller.rollRaw(chances: { [string]: number }, rng: Types.Rng): { string }
	local rolled = {}
	for _, def in Mutations.list do
		local chance = chances[def.id] or 0
		if chance > 0 and rng:NextNumber() < chance then
			table.insert(rolled, def.id)
		end
	end
	return rolled
end

function MutationRoller.roll(chances: { [string]: number }, rng: Types.Rng): { string }
	return MutationRoller.resolve(MutationRoller.rollRaw(chances, rng))
end

return table.freeze(MutationRoller)

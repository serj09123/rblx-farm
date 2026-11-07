--!strict
-- Case rolls and displayed odds. Pure: randomness comes from `rng`. The server rolls
-- with `roll` and the client shows `odds`; both use `candidates`, so displayed odds
-- are the real odds (including the pity restriction).

local config = script.Parent.Parent.config
local Cases = require(config.Cases)
local Icons = require(config.Icons)
local Mutations = require(config.Mutations)
local Nests = require(config.Nests)
local Rarities = require(config.Rarities)
local Types = require(script.Parent.Parent.Types)

local CaseRoller = {}

export type OddsEntry = {
	index: number, -- index into tier.pool
	kind: string,
	id: string,
	count: number,
	grade: string,
	probability: number,
	label: string,
}

export type Odds = {
	entries: { OddsEntry },
	grades: { { grade: string, probability: number } },
	pityActive: boolean, -- the next open is restricted to minGrade or better
	opensUntilPity: number, -- 1 = the next open is the guaranteed one
}

function CaseRoller.label(entry: Cases.Entry): string
	if entry.kind == "nest" then
		local def = Nests.byId[entry.id]
		return string.format("%dx %s", entry.count, if def then def.displayName else entry.id)
	end
	local def = Mutations.byId[entry.id]
	local name = if def then def.displayName else entry.id
	if entry.count > 1 then
		return string.format("%dx %s Mutagen", entry.count, name)
	end
	return name .. " Mutagen"
end

function CaseRoller.icon(entry: Cases.Entry): string
	return if entry.kind == "nest" then Icons.nestIcon(entry.id) else Icons.mutationIcon(entry.id)
end

function CaseRoller.pityActive(tier: Cases.TierDef, pityCount: number): boolean
	return pityCount >= tier.pity.threshold - 1
end

-- Pool entries that can be rolled right now: the whole pool, or only minGrade+ when
-- the pity guarantee is due.
function CaseRoller.candidates(tier: Cases.TierDef, pityCount: number): { number }
	local restricted = CaseRoller.pityActive(tier, pityCount)
	local minOrder = Rarities.order(tier.pity.minGrade)
	local indices = {}
	for index, entry in tier.pool do
		if entry.weight > 0 and (not restricted or Rarities.order(entry.grade) >= minOrder) then
			table.insert(indices, index)
		end
	end
	return indices
end

function CaseRoller.odds(tier: Cases.TierDef, pityCount: number): Odds
	local indices = CaseRoller.candidates(tier, pityCount)
	local total = 0
	for _, index in indices do
		total += tier.pool[index].weight
	end
	local entries = {}
	local byGrade: { [string]: number } = {}
	for _, index in indices do
		local entry = tier.pool[index]
		local p = entry.weight / total
		table.insert(entries, {
			index = index,
			kind = entry.kind,
			id = entry.id,
			count = entry.count,
			grade = entry.grade,
			probability = p,
			label = CaseRoller.label(entry),
		})
		byGrade[entry.grade] = (byGrade[entry.grade] or 0) + p
	end
	local grades = {}
	for grade, p in byGrade do
		table.insert(grades, { grade = grade, probability = p })
	end
	table.sort(grades, function(a, b)
		return Rarities.order(a.grade) < Rarities.order(b.grade)
	end)
	return {
		entries = entries,
		grades = grades,
		pityActive = CaseRoller.pityActive(tier, pityCount),
		opensUntilPity = math.max(1, tier.pity.threshold - pityCount),
	}
end

-- Returns the pool index that was won and whether pity forced this roll.
function CaseRoller.roll(tier: Cases.TierDef, pityCount: number, rng: Types.Rng): (number, boolean)
	local indices = CaseRoller.candidates(tier, pityCount)
	assert(#indices > 0, "case " .. tier.id .. " has no rollable entry")
	local total = 0
	for _, index in indices do
		total += tier.pool[index].weight
	end
	local roll = rng:NextNumber() * total
	local acc = 0
	local won = indices[#indices]
	for _, index in indices do
		acc += tier.pool[index].weight
		if roll < acc then
			won = index
			break
		end
	end
	return won, CaseRoller.pityActive(tier, pityCount)
end

function CaseRoller.nextPity(tier: Cases.TierDef, pityCount: number, entry: Cases.Entry): number
	if Rarities.order(entry.grade) >= Rarities.order(tier.pity.minGrade) then
		return 0
	end
	return pityCount + 1
end

-- Config sanity check used by tests: returns a list of problems (empty = ok).
function CaseRoller.validate(): { string }
	local problems = {}
	for _, tier in Cases.list do
		if #tier.pool == 0 then
			table.insert(problems, tier.id .. ": empty pool")
		end
		local reachesPity = false
		for index, entry in tier.pool do
			local where = string.format("%s[%d]", tier.id, index)
			if entry.count < 1 or entry.count ~= math.floor(entry.count) then
				table.insert(problems, where .. ": bad count")
			end
			if entry.weight <= 0 then
				table.insert(problems, where .. ": weight must be > 0")
			end
			if not Rarities.byId[entry.grade] then
				table.insert(problems, where .. ": unknown grade " .. entry.grade)
			elseif Rarities.order(entry.grade) >= Rarities.order(tier.pity.minGrade) then
				reachesPity = true
			end
			if entry.kind == "nest" then
				local def = Nests.byId[entry.id]
				if not def then
					table.insert(problems, where .. ": unknown nest " .. entry.id)
				elseif def.guaranteed then
					table.insert(problems, where .. ": guaranteed (tutorial) nest in pool")
				end
			else
				local def = Mutations.byId[entry.id]
				if not def then
					table.insert(problems, where .. ": unknown mutation " .. entry.id)
				elseif def.eventOnly then
					table.insert(problems, where .. ": event-only mutation in pool")
				end
			end
		end
		if not reachesPity then
			table.insert(problems, tier.id .. ": no entry satisfies the pity grade")
		end
	end
	return problems
end

return table.freeze(CaseRoller)

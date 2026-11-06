--!strict
-- Pure co-op rules: Skyheart target and rewards, weather scheduling, cheer limits.

local config = script.Parent.Parent.config
local Coop = require(config.Coop)
local Types = require(script.Parent.Parent.Types)
local Weather = require(config.Weather)

local CoopMath = {}

-- Goal size from the progression tiers of the players currently on the server.
function CoopMath.skyheartTarget(tiers: { number }): number
	local shares = Coop.skyheart.sharePerTier
	local total = 0
	for _, tier in tiers do
		total += shares[math.clamp(tier, 1, #shares)]
	end
	return math.max(Coop.skyheart.minTarget, total)
end

-- Nest rewards per contributor when the Skyheart blooms. Only `eligible` users
-- (still on the server) are rewarded. Ties for top contributor go to the lower id.
function CoopMath.bloomRewards(
	contributions: { [string]: number },
	eligible: { [string]: boolean }
): { [string]: number }
	local rewards = {}
	local contributors = {}
	for userId, amount in contributions do
		if amount > 0 and eligible[userId] then
			rewards[userId] = 1
			table.insert(contributors, userId)
		end
	end
	if #contributors >= Coop.skyheart.minContributorsForTopBonus then
		table.sort(contributors, function(a, b)
			local ca, cb = contributions[a], contributions[b]
			if ca ~= cb then
				return ca > cb
			end
			return (tonumber(a) or 0) < (tonumber(b) or 0)
		end)
		local top = contributors[1]
		rewards[top] += Coop.skyheart.topContributorBonusNests
	end
	return rewards
end

-- Overflow kept for the next round (capped at half of the next target).
function CoopMath.carryOver(progress: number, target: number, nextTarget: number): number
	return math.clamp(progress - target, 0, nextTarget * 0.5)
end

-- Weighted pick of the next weather event, never repeating the previous one
-- when an alternative exists.
function CoopMath.pickWeather(rng: Types.Rng, previousId: string?): Weather.WeatherDef
	local candidates = {}
	local total = 0
	for _, def in Weather.list do
		if def.id ~= previousId or #Weather.list == 1 then
			table.insert(candidates, def)
			total += def.weight
		end
	end
	local roll = rng:NextNumber() * total
	local acc = 0
	for _, def in candidates do
		acc += def.weight
		if roll < acc then
			return def
		end
	end
	return candidates[#candidates]
end

function CoopMath.weatherGap(rng: Types.Rng): number
	return Weather.minGapSeconds + rng:NextNumber() * (Weather.maxGapSeconds - Weather.minGapSeconds)
end

export type CheerCheck = "ok" | "self" | "notGrowing" | "alreadyCheered" | "nestFull" | "hourlyLimit"

-- Validates a cheer against nest state and the helper's recent cheer timestamps.
function CoopMath.checkCheer(
	nest: Types.NestSlot?,
	ownerId: number,
	helperId: number,
	recent: { number },
	now: number
): CheerCheck
	if ownerId == helperId then
		return "self"
	end
	if not nest or nest.progress >= nest.required then
		return "notGrowing"
	end
	if nest.cheers[tostring(helperId)] then
		return "alreadyCheered"
	end
	local count = 0
	for _ in nest.cheers do
		count += 1
	end
	if count >= Coop.cheer.maxCheerersPerNest then
		return "nestFull"
	end
	local inLastHour = 0
	for _, t in recent do
		if now - t < 3600 then
			inLastHour += 1
		end
	end
	if inLastHour >= Coop.cheer.maxPerHourPerHelper then
		return "hourlyLimit"
	end
	return "ok"
end

return table.freeze(CoopMath)

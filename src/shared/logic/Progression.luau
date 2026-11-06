--!strict
-- Pure progression math: upgrade values/costs, slot limits, player tier.

local config = script.Parent.Parent.config
local Economy = require(config.Economy)
local Monetization = require(config.Monetization)
local Nests = require(config.Nests)
local Rewards = require(config.Rewards)
local Upgrades = require(config.Upgrades)

export type Limits = { nestSlots: number, habitatSlots: number, backpack: number }

local Progression = {}

function Progression.level(upgrades: { [string]: number }, id: string): number
	return math.max(0, math.floor(tonumber(upgrades[id]) or 0))
end

function Progression.value(id: string, level: number): number
	local def = Upgrades.byId[id]
	assert(def, "unknown upgrade " .. id)
	return def.base + def.perLevel * math.clamp(level, 0, #def.costs)
end

-- Cost of the next level, or nil when maxed.
function Progression.nextCost(id: string, level: number): number?
	local def = Upgrades.byId[id]
	if not def then
		return nil
	end
	return def.costs[level + 1]
end

function Progression.limits(upgrades: { [string]: number }, passes: { [string]: boolean }): Limits
	local nestSlots = Progression.value("nestSlots", Progression.level(upgrades, "nestSlots"))
	if passes.ExtraNestSlots then
		nestSlots += Monetization.extraNestSlotsFromPass
	end
	local backpack = Progression.value("backpack", Progression.level(upgrades, "backpack"))
	if passes.BigBackpack then
		backpack += Monetization.backpackFromPass
	end
	return {
		nestSlots = math.min(nestSlots, Upgrades.maxNestSlots),
		habitatSlots = math.min(
			Progression.value("habitatSlots", Progression.level(upgrades, "habitatSlots")),
			Upgrades.maxHabitatSlots
		),
		backpack = math.min(backpack, Economy.inventoryHardCap),
	}
end

function Progression.isNestUnlocked(nestId: string, hatched: number): boolean
	local def = Nests.byId[nestId]
	return def ~= nil and hatched >= def.unlockAtHatched
end

-- Highest tier among purchasable nests the player has unlocked (1..5).
function Progression.tier(hatched: number): number
	local tier = 1
	for _, def in Nests.purchasable do
		if hatched >= def.unlockAtHatched and def.tier > tier then
			tier = def.tier
		end
	end
	return tier
end

function Progression.scaleCoins(amount: number, tier: number): number
	local scale = Rewards.tierCoinScale[math.clamp(tier, 1, #Rewards.tierCoinScale)]
	return math.floor(amount * scale)
end

return table.freeze(Progression)

--!nocheck
-- Config integrity and economy sanity checks. These fail when a config edit breaks
-- the loop (e.g. a nest that loses money) or references something that does not exist.

local Shared = game:GetService("ReplicatedStorage").Shared
local config = Shared.config
local Creatures = require(config.Creatures)
local Nests = require(config.Nests)
local Rarities = require(config.Rarities)
local Mutations = require(config.Mutations)
local Quests = require(config.Quests)
local DailyRewards = require(config.DailyRewards)
local IndexConfig = require(config.Index)
local Seasons = require(config.Seasons)
local Monetization = require(config.Monetization)
local Upgrades = require(config.Upgrades)
local Weather = require(config.Weather)
local HatchOdds = require(Shared.logic.HatchOdds)
local MutationRoller = require(Shared.logic.MutationRoller)
local Valuation = require(Shared.logic.Valuation)

local NO_PITY = { rarePlus = 0, epicPlus = 0, legendaryPlus = 0 }

-- Expected mutation value multiplier, assuming independent rolls (ignores the
-- small effect of group/cap resolution, which only lowers it slightly).
local function expectedMutationMultiplier()
	local chances = MutationRoller.chances(nil)
	local ev = 1
	for _, def in Mutations.list do
		local p = chances[def.id]
		ev *= (1 - p) + p * def.multiplier
	end
	return ev
end

local function expectedValue(nest)
	local ev = 0
	for _, entry in HatchOdds.speciesOdds(nest, 1, NO_PITY, {}) do
		ev += entry.probability * Creatures.byId[entry.species].baseValue
	end
	-- size averages 1.025 (uniform 0.8..1.25)
	return ev * expectedMutationMultiplier() * 1.025
end

local function checkReward(reward)
	if reward.nests then
		for nestId, count in reward.nests do
			expect(Nests.byId[nestId] ~= nil).to.equal(true)
			expect(count > 0).to.equal(true)
		end
	end
end

return function()
	describe("Economy balance", function()
		it("every purchasable nest returns at least 1.25x its cost on average", function()
			for _, nest in Nests.purchasable do
				local ratio = expectedValue(nest) / nest.cost
				if ratio < 1.25 then
					error(string.format("%s EV/cost = %.2f", nest.id, ratio))
				end
			end
		end)

		it("profit per minute per slot increases with nest tier", function()
			local last = 0
			for _, nest in Nests.purchasable do
				local perMinute = (expectedValue(nest) - nest.cost) / (nest.growSeconds / 60)
				if perMinute <= last then
					error(string.format("%s profit/min %.1f <= previous %.1f", nest.id, perMinute, last))
				end
				last = perMinute
			end
		end)

		it("upgrade costs strictly increase", function()
			for _, def in Upgrades.list do
				for i = 2, #def.costs do
					expect(def.costs[i] > def.costs[i - 1]).to.equal(true)
				end
			end
		end)
	end)

	describe("Config integrity", function()
		it("species reference valid rarities and have unique ids", function()
			local seen = {}
			for _, def in Creatures.list do
				expect(seen[def.id]).to.equal(nil)
				seen[def.id] = true
				expect(Rarities.byId[def.rarity] ~= nil).to.equal(true)
				expect(def.baseValue > 0).to.equal(true)
				if def.eventOnly then
					expect(Seasons.byId[def.eventOnly] ~= nil).to.equal(true)
				end
			end
			expect(Creatures.baseSpeciesCount >= 20).to.equal(true)
		end)

		it("nests only use valid rarities that have species", function()
			for _, nest in Nests.list do
				for rarity in nest.weights do
					expect(Rarities.byId[rarity] ~= nil).to.equal(true)
					expect(next(HatchOdds.speciesWeights(nest, rarity, {})) ~= nil).to.equal(true)
				end
				if nest.guaranteed then
					expect(Creatures.byId[nest.guaranteed.species] ~= nil).to.equal(true)
					for _, m in nest.guaranteed.mutations do
						expect(Mutations.byId[m] ~= nil).to.equal(true)
					end
				end
			end
		end)

		it("combos and weather reference real mutations", function()
			for _, combo in Mutations.combos do
				for _, id in combo.requires do
					expect(Mutations.byId[id] ~= nil).to.equal(true)
				end
			end
			for _, def in Weather.list do
				for id in def.modifiers.mutationChances or {} do
					expect(Mutations.byId[id] ~= nil).to.equal(true)
				end
			end
		end)

		it("rewards reference real nests", function()
			for _, q in Quests.daily do
				checkReward(q.reward)
			end
			for _, q in Quests.weekly do
				checkReward(q.reward)
			end
			for _, r in DailyRewards.cycle do
				checkReward(r)
			end
			for _, m in IndexConfig.milestones do
				checkReward(m.reward)
			end
		end)

		it("seasons have valid windows", function()
			for _, s in Seasons.list do
				expect(s.endsAt > s.startsAt).to.equal(true)
				for id in s.mutationBaseChances or {} do
					expect(Mutations.byId[id] ~= nil).to.equal(true)
				end
			end
		end)

		it("monetization keys are unique and boosts are sane", function()
			local seen = {}
			for _, p in Monetization.products do
				expect(seen[p.key]).to.equal(nil)
				seen[p.key] = true
				if p.durationSeconds then
					expect(p.durationSeconds <= Monetization.maxBoostSeconds).to.equal(true)
				end
			end
			for _, p in Monetization.passes do
				expect(seen[p.key]).to.equal(nil)
				seen[p.key] = true
			end
		end)

		it("valuation handles every species with every mutation", function()
			for _, species in Creatures.list do
				for _, m in Mutations.list do
					expect(Valuation.value({ species = species.id, mutations = { m.id }, size = 1 }) > 0).to.equal(true)
				end
			end
		end)
	end)
end

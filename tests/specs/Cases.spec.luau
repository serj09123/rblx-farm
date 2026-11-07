--!nocheck
local Shared = game:GetService("ReplicatedStorage").Shared
local Cases = require(Shared.config.Cases)
local CaseRoller = require(Shared.logic.CaseRoller)
local Hatchery = require(Shared.logic.Hatchery)
local Monetization = require(Shared.config.Monetization)
local Mutations = require(Shared.config.Mutations)
local MutationRoller = require(Shared.logic.MutationRoller)
local Nests = require(Shared.config.Nests)
local Rarities = require(Shared.config.Rarities)
local Rewards = require(Shared.config.Rewards)
local Quests = require(Shared.config.Quests)
local DailyRewards = require(Shared.config.DailyRewards)

local NO_PITY = { rarePlus = 0, epicPlus = 0, legendaryPlus = 0 }

return function()
	describe("Cases config", function()
		it("has no validation problems", function()
			local problems = CaseRoller.validate()
			expect(#problems).to.equal(0)
		end)

		it("every tier has a Robux key product flagged as paid random", function()
			for _, tier in Cases.list do
				local found = false
				for _, product in Monetization.products do
					if product.caseKeys and product.caseKeys[tier.id] then
						found = true
						expect(product.paidRandom).to.equal(true)
					end
				end
				expect(found).to.equal(true)
			end
		end)

		it("reward key ids in quests and daily rewards exist", function()
			local function check(reward)
				for tierId in reward.keys or {} do
					expect(Cases.byId[tierId] ~= nil).to.equal(true)
				end
			end
			for _, def in Quests.daily do
				check(def.reward)
			end
			for _, def in Quests.weekly do
				check(def.reward)
			end
			for _, reward in DailyRewards.cycle do
				check(reward)
			end
			local _ = Rewards
		end)
	end)

	describe("CaseRoller.odds", function()
		it("probabilities sum to 1 for every tier, with and without pity", function()
			for _, tier in Cases.list do
				for _, pity in { 0, tier.pity.threshold - 1 } do
					local odds = CaseRoller.odds(tier, pity)
					local total = 0
					for _, entry in odds.entries do
						total += entry.probability
					end
					expect(total).to.be.near(1, 1e-9)
				end
			end
		end)

		it("pity restricts the pool to minGrade or better", function()
			for _, tier in Cases.list do
				local odds = CaseRoller.odds(tier, tier.pity.threshold - 1)
				expect(odds.pityActive).to.equal(true)
				local minOrder = Rarities.order(tier.pity.minGrade)
				for _, entry in odds.entries do
					expect(Rarities.order(entry.grade) >= minOrder).to.equal(true)
				end
			end
		end)
	end)

	describe("CaseRoller.roll", function()
		it("observed frequencies match the displayed odds", function()
			local tier = Cases.byId.sprout
			local rng = Random.new(2024)
			local counts = {}
			local n = 80000
			for _ = 1, n do
				local index = CaseRoller.roll(tier, 0, rng)
				counts[index] = (counts[index] or 0) + 1
			end
			for _, entry in CaseRoller.odds(tier, 0).entries do
				expect((counts[entry.index] or 0) / n).to.be.near(entry.probability, 0.01)
			end
		end)

		it("guarantees minGrade or better within `threshold` opens", function()
			for _, tier in Cases.list do
				local rng = Random.new(7)
				local pity = 0
				local worstGap = 0
				local gap = 0
				for _ = 1, 4000 do
					local index = CaseRoller.roll(tier, pity, rng)
					local entry = tier.pool[index]
					pity = CaseRoller.nextPity(tier, pity, entry)
					if pity == 0 then
						worstGap = math.max(worstGap, gap)
						gap = 0
					else
						gap += 1
					end
				end
				expect(worstGap <= tier.pity.threshold - 1).to.equal(true)
			end
		end)

		it("the forced roll always lands in the restricted pool", function()
			local tier = Cases.byId.star
			local rng = Random.new(3)
			local minOrder = Rarities.order(tier.pity.minGrade)
			for _ = 1, 500 do
				local index, forced = CaseRoller.roll(tier, tier.pity.threshold - 1, rng)
				expect(forced).to.equal(true)
				expect(Rarities.order(tier.pool[index].grade) >= minOrder).to.equal(true)
			end
		end)
	end)

	describe("mutagen (forced mutation)", function()
		it("resolveForced always keeps the forced mutation and respects the cap", function()
			local rolled = { "Shiny", "Frozen", "Electric", "Cosmic", "Shadow" }
			for _, forced in { "Shiny", "Giant", "Golden", "Tiny" } do
				local result = MutationRoller.resolveForced(rolled, forced)
				expect(table.find(result, forced) ~= nil).to.equal(true)
				expect(#result <= Mutations.maxPerCreature).to.equal(true)
			end
		end)

		it("the forced mutation displaces a rolled one in the same group", function()
			local result = MutationRoller.resolveForced({ "Rainbow" }, "Golden")
			expect(table.find(result, "Golden") ~= nil).to.equal(true)
			expect(table.find(result, "Rainbow")).to.equal(nil)
		end)

		it("Hatchery.roll includes the forced mutation on every hatch", function()
			local rng = Random.new(99)
			for _ = 1, 300 do
				local outcome = Hatchery.roll(
					Nests.byId.grove,
					{ luck = 1, pity = NO_PITY, activeSeasons = {}, forcedMutation = "Shiny" },
					rng
				)
				expect(table.find(outcome.mutations, "Shiny") ~= nil).to.equal(true)
			end
		end)

		it("without a mutagen the rng stream and result are unchanged", function()
			local a = Hatchery.roll(Nests.byId.grove, { luck = 1, pity = NO_PITY, activeSeasons = {} }, Random.new(5))
			local b = Hatchery.roll(
				Nests.byId.grove,
				{ luck = 1, pity = NO_PITY, activeSeasons = {}, forcedMutation = nil },
				Random.new(5)
			)
			expect(a.species).to.equal(b.species)
			expect(#a.mutations).to.equal(#b.mutations)
			expect(a.size).to.equal(b.size)
		end)
	end)
end

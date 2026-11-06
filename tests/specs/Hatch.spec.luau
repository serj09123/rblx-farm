--!nocheck
local Shared = game:GetService("ReplicatedStorage").Shared
local Nests = require(Shared.config.Nests)
local Mutations = require(Shared.config.Mutations)
local HatchOdds = require(Shared.logic.HatchOdds)
local Hatchery = require(Shared.logic.Hatchery)
local MutationRoller = require(Shared.logic.MutationRoller)
local ModifierMath = require(Shared.logic.ModifierMath)

local NO_PITY = { rarePlus = 0, epicPlus = 0, legendaryPlus = 0 }

local function sum(map)
	local total = 0
	for _, v in map do
		total += v
	end
	return total
end

return function()
	describe("HatchOdds.rarityOdds", function()
		it("sums to 1 for every nest", function()
			for _, nest in Nests.list do
				local odds = HatchOdds.rarityOdds(nest, 1, NO_PITY, {})
				expect(sum(odds)).to.be.near(1, 1e-9)
			end
		end)

		it("matches the configured weights without modifiers", function()
			local odds = HatchOdds.rarityOdds(Nests.byId.meadow, 1, NO_PITY, {})
			expect(odds.Common).to.be.near(0.70, 1e-9)
			expect(odds.Epic).to.be.near(0.005, 1e-9)
			expect(odds.Legendary).to.equal(nil)
		end)

		it("luck raises only luck-affected rarities and is capped", function()
			local base = HatchOdds.rarityOdds(Nests.byId.grove, 1, NO_PITY, {})
			local lucky = HatchOdds.rarityOdds(Nests.byId.grove, 2, NO_PITY, {})
			expect(lucky.Rare > base.Rare).to.equal(true)
			expect(lucky.Legendary > base.Legendary).to.equal(true)
			expect(lucky.Common < base.Common).to.equal(true)
			local capped = HatchOdds.rarityOdds(Nests.byId.grove, 100, NO_PITY, {})
			local atCap = HatchOdds.rarityOdds(Nests.byId.grove, 3, NO_PITY, {})
			expect(capped.Rare).to.be.near(atCap.Rare, 1e-12)
		end)

		it("pity restricts the next hatch to the guaranteed tier or better", function()
			local odds, target = HatchOdds.rarityOdds(
				Nests.byId.meadow,
				1,
				{ rarePlus = 14, epicPlus = 0, legendaryPlus = 0 },
				{}
			)
			expect(target).to.equal("Rare")
			expect(odds.Common).to.equal(nil)
			expect(odds.Uncommon).to.equal(nil)
			expect(sum(odds)).to.be.near(1, 1e-9)
			expect(odds.Rare).to.be.near(0.9, 1e-9)
		end)

		it("ignores pity rules the nest cannot satisfy", function()
			local _, target = HatchOdds.rarityOdds(
				Nests.byId.meadow,
				1,
				{ rarePlus = 0, epicPlus = 0, legendaryPlus = 999 },
				{}
			)
			expect(target).to.equal(nil)
		end)

		it("event species appear only while their season is active", function()
			local without = HatchOdds.speciesWeights(Nests.byId.grove, "Epic", {})
			local with = HatchOdds.speciesWeights(Nests.byId.grove, "Epic", { "harvest_festival_2026" })
			expect(without.gourdling).to.equal(nil)
			expect(with.gourdling).to.equal(2)
			local meadow = HatchOdds.speciesWeights(Nests.byId.meadow, "Epic", { "harvest_festival_2026" })
			expect(meadow.gourdling).to.equal(nil)
		end)

		it("species odds sum to 1", function()
			local list = HatchOdds.speciesOdds(Nests.byId.crystal, 1.5, NO_PITY, { "winter_frost_2026" })
			local total = 0
			for _, entry in list do
				total += entry.probability
			end
			expect(total).to.be.near(1, 1e-9)
			expect(list[1].rarity).to.equal("Mythic")
		end)
	end)

	describe("Hatchery.roll", function()
		it("observed rarity frequencies match the displayed odds", function()
			local rng = Random.new(12345)
			local nest = Nests.byId.grove
			local counts = {}
			local n = 60000
			for _ = 1, n do
				local outcome = Hatchery.roll(nest, { luck = 1, pity = NO_PITY, activeSeasons = {} }, rng)
				counts[outcome.rarity] = (counts[outcome.rarity] or 0) + 1
			end
			local odds = HatchOdds.rarityOdds(nest, 1, NO_PITY, {})
			for rarity, p in odds do
				expect((counts[rarity] or 0) / n).to.be.near(p, 0.01)
			end
		end)

		it("starter nest always gives the scripted first critter", function()
			local outcome =
				Hatchery.roll(Nests.byId.starter, { luck = 1, pity = NO_PITY, activeSeasons = {} }, Random.new(1))
			expect(outcome.species).to.equal("puffpaw")
			expect(outcome.mutations[1]).to.equal("Shiny")
		end)

		it("rolls sizes within bounds", function()
			local rng = Random.new(7)
			for _ = 1, 500 do
				local outcome = Hatchery.roll(Nests.byId.meadow, { luck = 1, pity = NO_PITY, activeSeasons = {} }, rng)
				expect(outcome.size >= 0.8 and outcome.size <= 1.25).to.equal(true)
			end
		end)

		it("updates pity counters", function()
			local nest = Nests.byId.meadow
			local pity = Hatchery.nextPity(nest, NO_PITY, "Common")
			expect(pity.rarePlus).to.equal(1)
			expect(pity.epicPlus).to.equal(1)
			expect(pity.legendaryPlus).to.equal(0) -- meadow cannot roll Legendary
			pity = Hatchery.nextPity(nest, { rarePlus = 9, epicPlus = 30, legendaryPlus = 0 }, "Rare")
			expect(pity.rarePlus).to.equal(0)
			expect(pity.epicPlus).to.equal(31)
			pity =
				Hatchery.nextPity(Nests.byId.crystal, { rarePlus = 3, epicPlus = 30, legendaryPlus = 100 }, "Legendary")
			expect(pity.rarePlus).to.equal(0)
			expect(pity.epicPlus).to.equal(0)
			expect(pity.legendaryPlus).to.equal(0)
		end)

		it("a guaranteed pity hatch never rolls below the target", function()
			local rng = Random.new(99)
			for _ = 1, 300 do
				local outcome = Hatchery.roll(Nests.byId.grove, {
					luck = 1,
					pity = { rarePlus = 0, epicPlus = 74, legendaryPlus = 0 },
					activeSeasons = {},
				}, rng)
				expect(outcome.rarity == "Epic" or outcome.rarity == "Legendary").to.equal(true)
				expect(outcome.pityTriggered).to.equal("Epic")
			end
		end)
	end)

	describe("MutationRoller", function()
		it("applies multipliers, event base chances and the cap", function()
			local mods = ModifierMath.combine({ coinMultiplier = 1, growthMultiplier = 1, luckMultiplier = 1 }, {
				{ mutationChances = { Frozen = 6 } },
				{ mutationMultiplier = 1.5 },
			}, ModifierMath.activeSeasons(1795132800 + 10))
			local chances = MutationRoller.chances(mods)
			expect(chances.Frozen).to.be.near(0.01 * 6 * 1.5, 1e-12)
			expect(chances.Shiny).to.be.near(0.04 * 1.5, 1e-12)
			expect(chances.Harvest).to.be.near(0.02 * 1.5, 1e-12)
			local base = MutationRoller.chances(nil)
			expect(base.Harvest).to.equal(0)
			local huge = ModifierMath.combine({ coinMultiplier = 1, growthMultiplier = 1, luckMultiplier = 1 }, {
				{ mutationMultiplier = 1000 },
			}, {})
			expect(MutationRoller.chances(huge).Shiny).to.equal(Mutations.maxChance)
		end)

		it("keeps the best mutation per group and at most 3 overall", function()
			local result = MutationRoller.resolve({ "Shiny", "Giant", "Tiny", "Golden", "Rainbow", "Cosmic", "Frozen" })
			expect(#result).to.equal(3)
			local set = {}
			for _, id in result do
				set[id] = true
			end
			expect(set.Cosmic).to.equal(true)
			expect(set.Rainbow).to.equal(true)
			expect(set.Golden).to.equal(nil)
			expect(set.Tiny).to.equal(nil)
			expect(set.Frozen).to.equal(true)
		end)

		it("observed mutation frequency matches the chance", function()
			local rng = Random.new(2024)
			local chances = { Shiny = 0.2 }
			local hits = 0
			for _ = 1, 20000 do
				local list = MutationRoller.roll(chances, rng)
				if list[1] == "Shiny" then
					hits += 1
				end
			end
			expect(hits / 20000).to.be.near(0.2, 0.01)
		end)
	end)
end

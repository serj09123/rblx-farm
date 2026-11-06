--!nocheck
local Shared = game:GetService("ReplicatedStorage").Shared
local CoopMath = require(Shared.logic.CoopMath)
local Coop = require(Shared.config.Coop)
local Weather = require(Shared.config.Weather)

return function()
	describe("Skyheart target", function()
		it("never drops below the minimum (solo server)", function()
			expect(CoopMath.skyheartTarget({})).to.equal(Coop.skyheart.minTarget)
			expect(CoopMath.skyheartTarget({ 1 })).to.equal(
				math.max(Coop.skyheart.minTarget, Coop.skyheart.sharePerTier[1])
			)
		end)

		it("scales with players and their tier", function()
			local shares = Coop.skyheart.sharePerTier
			expect(CoopMath.skyheartTarget({ 1, 3, 5 })).to.equal(shares[1] + shares[3] + shares[5])
			expect(CoopMath.skyheartTarget({ 99 })).to.equal(shares[#shares])
		end)
	end)

	describe("Bloom rewards", function()
		it("rewards every eligible contributor and gives the top one a bonus", function()
			local rewards = CoopMath.bloomRewards({ ["1"] = 10, ["2"] = 30, ["3"] = 0, ["4"] = 50 }, {
				["1"] = true,
				["2"] = true,
				["3"] = true,
			})
			expect(rewards["1"]).to.equal(1)
			expect(rewards["2"]).to.equal(1 + Coop.skyheart.topContributorBonusNests)
			expect(rewards["3"]).to.equal(nil) -- contributed nothing
			expect(rewards["4"]).to.equal(nil) -- left the server
		end)

		it("solo contributor gets no top bonus", function()
			local rewards = CoopMath.bloomRewards({ ["7"] = 100 }, { ["7"] = true })
			expect(rewards["7"]).to.equal(1)
		end)

		it("breaks ties deterministically", function()
			local rewards = CoopMath.bloomRewards({ ["20"] = 5, ["10"] = 5 }, { ["10"] = true, ["20"] = true })
			expect(rewards["10"]).to.equal(2)
			expect(rewards["20"]).to.equal(1)
		end)

		it("caps carry over", function()
			expect(CoopMath.carryOver(150, 100, 60)).to.equal(30)
			expect(CoopMath.carryOver(110, 100, 60)).to.equal(10)
			expect(CoopMath.carryOver(90, 100, 60)).to.equal(0)
		end)
	end)

	describe("Weather", function()
		it("never repeats the previous event and respects weights", function()
			local rng = Random.new(5)
			local counts = {}
			local previous = nil
			for _ = 1, 5000 do
				local def = CoopMath.pickWeather(rng, previous)
				expect(def.id ~= previous).to.equal(true)
				counts[def.id] = (counts[def.id] or 0) + 1
				previous = def.id
			end
			for _, def in Weather.list do
				expect((counts[def.id] or 0) > 0).to.equal(true)
			end
		end)

		it("gap stays within bounds", function()
			local rng = Random.new(1)
			for _ = 1, 200 do
				local gap = CoopMath.weatherGap(rng)
				expect(gap >= Weather.minGapSeconds and gap <= Weather.maxGapSeconds).to.equal(true)
			end
		end)
	end)

	describe("Cheer rules", function()
		local function nest(cheers, progress)
			return { nestId = "meadow", progress = progress or 0, required = 30, lastUpdate = 0, cheers = cheers or {} }
		end

		it("allows a valid cheer", function()
			expect(CoopMath.checkCheer(nest(), 1, 2, {}, 1000)).to.equal("ok")
		end)

		it("rejects self, finished nests and repeat cheers", function()
			expect(CoopMath.checkCheer(nest(), 1, 1, {}, 1000)).to.equal("self")
			expect(CoopMath.checkCheer(nest({}, 30), 1, 2, {}, 1000)).to.equal("notGrowing")
			expect(CoopMath.checkCheer(nil, 1, 2, {}, 1000)).to.equal("notGrowing")
			expect(CoopMath.checkCheer(nest({ ["2"] = true }), 1, 2, {}, 1000)).to.equal("alreadyCheered")
		end)

		it("limits cheerers per nest and cheers per hour", function()
			local full = {}
			for i = 10, 9 + Coop.cheer.maxCheerersPerNest do
				full[tostring(i)] = true
			end
			expect(CoopMath.checkCheer(nest(full), 1, 2, {}, 1000)).to.equal("nestFull")
			local recent = {}
			for i = 1, Coop.cheer.maxPerHourPerHelper do
				recent[i] = 5000 - i
			end
			expect(CoopMath.checkCheer(nest(), 1, 2, recent, 5000)).to.equal("hourlyLimit")
			expect(CoopMath.checkCheer(nest(), 1, 2, recent, 5000 + 3600)).to.equal("ok")
		end)
	end)
end

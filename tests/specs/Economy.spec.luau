--!nocheck
local Shared = game:GetService("ReplicatedStorage").Shared
local Valuation = require(Shared.logic.Valuation)
local GrowthMath = require(Shared.logic.GrowthMath)
local Progression = require(Shared.logic.Progression)
local Economy = require(Shared.config.Economy)

return function()
	describe("Valuation", function()
		it("computes base value with size", function()
			expect(Valuation.value({ species = "puffpaw", mutations = {}, size = 1 })).to.equal(24)
			expect(Valuation.value({ species = "puffpaw", mutations = {}, size = 1.25 })).to.equal(30)
		end)

		it("multiplies mutations and combos", function()
			-- Frozen 2.5 * Electric 2.5 * Thunderfrost 1.5 = 9.375
			local v = Valuation.value({ species = "voltkit", mutations = { "Frozen", "Electric" }, size = 1 })
			expect(v).to.equal(math.floor(480 * 9.375 + 0.5))
			expect(#Valuation.combos({ "Shadow", "Cosmic" })).to.equal(1)
			expect(#Valuation.combos({ "Shadow" })).to.equal(0)
		end)

		it("unknown species are worth nothing and never error", function()
			expect(Valuation.value({ species = "nope", mutations = {}, size = 1 })).to.equal(0)
		end)

		it("sell price applies pass multiplier and additive bonuses", function()
			local creature = { species = "solmane", mutations = {}, size = 1 }
			expect(Valuation.sellPrice(creature, 1, 0)).to.equal(24000)
			expect(Valuation.sellPrice(creature, 2, 0.5)).to.equal(72000)
		end)

		it("income pays back the value over the configured period", function()
			local creature = { species = "solmane", mutations = {}, size = 1 }
			expect(Valuation.incomePerSecond(creature) * Economy.incomePaybackSeconds).to.be.near(24000, 1e-6)
		end)
	end)

	describe("GrowthMath", function()
		it("integrates base rate", function()
			expect(GrowthMath.integrate(0, 100, 1.2, {})).to.be.near(120, 1e-9)
		end)

		it("applies overlapping windows piecewise", function()
			local windows = { { from = 50, to = 150, multiplier = 2 } }
			-- 0..50 at 1, 50..100 at 2
			expect(GrowthMath.integrate(0, 100, 1, windows)).to.be.near(150, 1e-9)
			-- stacked windows multiply
			windows = { { from = 0, to = 10, multiplier = 2 }, { from = 5, to = 10, multiplier = 3 } }
			expect(GrowthMath.integrate(0, 10, 1, windows)).to.be.near(5 * 2 + 5 * 6, 1e-9)
		end)

		it("caps offline income", function()
			local coins, seconds = GrowthMath.offlineIncome(1, 1000, 1000 + 100 * 3600)
			expect(seconds).to.equal(Economy.offlineIncomeCapSeconds)
			expect(coins).to.be.near(Economy.offlineIncomeCapSeconds * Economy.offlineIncomeRate, 1e-9)
			expect((GrowthMath.offlineIncome(1, 0, 5000))).to.equal(0)
		end)
	end)

	describe("Progression", function()
		it("computes limits with passes and caps", function()
			local limits = Progression.limits({ nestSlots = 5, habitatSlots = 6, backpack = 5 }, {})
			expect(limits.nestSlots).to.equal(8)
			expect(limits.habitatSlots).to.equal(8)
			expect(limits.backpack).to.equal(175)
			local passLimits = Progression.limits({ nestSlots = 5 }, { ExtraNestSlots = true, BigBackpack = true })
			expect(passLimits.nestSlots).to.equal(10)
			expect(passLimits.backpack).to.equal(150)
		end)

		it("returns nil cost when maxed", function()
			expect(Progression.nextCost("nestSlots", 0)).to.equal(300)
			expect(Progression.nextCost("nestSlots", 5)).to.equal(nil)
		end)

		it("derives tier from hatch count", function()
			expect(Progression.tier(0)).to.equal(1)
			expect(Progression.tier(5)).to.equal(2)
			expect(Progression.tier(200)).to.equal(5)
		end)
	end)
end

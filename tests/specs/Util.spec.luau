--!nocheck
local Shared = game:GetService("ReplicatedStorage").Shared
local Guard = require(Shared.util.Guard)
local RateLimiter = require(Shared.util.RateLimiter)
local TableUtil = require(Shared.util.TableUtil)
local TimeUtil = require(Shared.util.TimeUtil)

return function()
	describe("Guard", function()
		it("validates integers and rejects NaN/inf/fractions", function()
			local check = Guard.integer(1, 10)
			expect((check(5))).to.equal(true)
			expect((check(0))).to.equal(false)
			expect((check(2.5))).to.equal(false)
			expect((check(0 / 0))).to.equal(false)
			expect((check(math.huge))).to.equal(false)
			expect((check("5"))).to.equal(false)
		end)

		it("validates creature ids", function()
			expect((Guard.creatureId("0123ABCD-0000-0000-0000-00000000ABCD"))).to.equal(true)
			expect((Guard.creatureId("not-a-guid"))).to.equal(false)
			expect((Guard.creatureId(string.rep("A", 36)))).to.equal(false)
		end)

		it("validates arrays strictly", function()
			local check = Guard.uniqueArray(Guard.identifier, 3)
			expect((check({ "a", "b" }))).to.equal(true)
			expect((check({ "a", "a" }))).to.equal(false)
			expect((check({ "a", "b", "c", "d" }))).to.equal(false)
			expect((check({ [1] = "a", [3] = "c" }))).to.equal(false)
			expect((check({ a = "x" }))).to.equal(false)
		end)

		it("rejects extra arguments", function()
			local ok = Guard.validateArgs({ Guard.boolean }, { true, "extra" }, 2)
			expect(ok).to.equal(false)
			expect((Guard.validateArgs({ Guard.boolean }, { true }, 1))).to.equal(true)
		end)
	end)

	describe("RateLimiter", function()
		it("allows bursts up to capacity then refills over time", function()
			local now = 0
			local limiter = RateLimiter.new(3, 1, function()
				return now
			end)
			expect(limiter:consume("p")).to.equal(true)
			expect(limiter:consume("p")).to.equal(true)
			expect(limiter:consume("p")).to.equal(true)
			expect(limiter:consume("p")).to.equal(false)
			now += 1
			expect(limiter:consume("p")).to.equal(true)
			expect(limiter:consume("p")).to.equal(false)
			expect(limiter:consume("other")).to.equal(true)
		end)
	end)

	describe("TableUtil.findUnserializable", function()
		it("finds NaN, mixed tables and functions", function()
			expect(TableUtil.findUnserializable({ a = 1, b = { 1, 2 } })).to.equal(nil)
			expect(TableUtil.findUnserializable({ a = 0 / 0 })).to.be.ok()
			expect(TableUtil.findUnserializable({ [1] = "x", y = 2 })).to.be.ok()
			expect(TableUtil.findUnserializable({ f = print })).to.be.ok()
			expect(TableUtil.findUnserializable({ [1] = "a", [3] = "b" })).to.be.ok()
		end)
	end)

	describe("TimeUtil", function()
		it("computes UTC day and Monday-based week keys", function()
			-- 2026-11-09 is a Monday
			local monday = 1794182400
			local sunday = monday - 1
			expect(TimeUtil.weekKey(monday)).to.equal(TimeUtil.weekKey(sunday) + 1)
			expect(TimeUtil.weekKey(monday + 6 * 86400 + 86399)).to.equal(TimeUtil.weekKey(monday))
			expect(TimeUtil.dayKey(monday + 86399)).to.equal(TimeUtil.dayKey(monday))
			expect(TimeUtil.secondsUntilNextWeek(monday)).to.equal(7 * 86400)
		end)
	end)
end

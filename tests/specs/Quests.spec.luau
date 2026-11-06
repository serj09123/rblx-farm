--!nocheck
local Shared = game:GetService("ReplicatedStorage").Shared
local QuestLogic = require(Shared.logic.QuestLogic)
local Quests = require(Shared.config.Quests)
local DailyRewards = require(Shared.config.DailyRewards)

local DAY = 86400
local T0 = 1794182400 -- Monday 2026-11-09 00:00 UTC

local function freshQuests()
	return { dayKey = -1, daily = {}, rerollsUsed = 0, weekKey = -1, weekly = {} }
end

return function()
	describe("Quest refresh", function()
		it("rolls distinct daily and weekly quests deterministically", function()
			local a, b = freshQuests(), freshQuests()
			expect(QuestLogic.refresh(a, 42, T0 + 100, 1)).to.equal(true)
			QuestLogic.refresh(b, 42, T0 + 5000, 1)
			expect(#a.daily).to.equal(Quests.dailyCount)
			expect(#a.weekly).to.equal(Quests.weeklyCount)
			local seen = {}
			for i, q in a.daily do
				expect(seen[q.id]).to.equal(nil)
				seen[q.id] = true
				expect(b.daily[i].id).to.equal(q.id)
			end
		end)

		it("resets daily at UTC midnight and weekly on Monday only", function()
			local q = freshQuests()
			QuestLogic.refresh(q, 7, T0 + 10, 1)
			local week = q.weekKey
			q.daily[1].progress = 1
			expect(QuestLogic.refresh(q, 7, T0 + 20, 1)).to.equal(false)
			expect(QuestLogic.refresh(q, 7, T0 + DAY + 1, 1)).to.equal(true)
			expect(q.daily[1].progress).to.equal(0)
			expect(q.weekKey).to.equal(week)
			QuestLogic.refresh(q, 7, T0 + 7 * DAY, 1)
			expect(q.weekKey).to.equal(week + 1)
		end)

		it("scales coin targets with tier", function()
			local q = QuestLogic.roll({ Quests.byId.d_earn }, 1, 1, 3)
			expect(q[1].target).to.equal(Quests.byId.d_earn.target * 10)
		end)
	end)

	describe("Quest progress and rerolls", function()
		it("progresses matching kinds and caps at the target", function()
			local q = freshQuests()
			q.daily = { { id = "d_hatch10", progress = 0, target = 10, claimed = false } }
			q.weekly = { { id = "w_hatch150", progress = 0, target = 150, claimed = false } }
			expect(QuestLogic.progress(q, "hatch", 25)).to.equal(true)
			expect(q.daily[1].progress).to.equal(10)
			expect(q.weekly[1].progress).to.equal(25)
			expect(QuestLogic.progress(q, "sell", 3)).to.equal(false)
			expect(QuestLogic.canClaim(q.daily[1])).to.equal(true)
			q.daily[1].claimed = true
			expect(QuestLogic.canClaim(q.daily[1])).to.equal(false)
		end)

		it("allows the configured number of free rerolls and never duplicates", function()
			local q = freshQuests()
			QuestLogic.refresh(q, 9, T0, 1)
			local before = q.daily[2].id
			expect(QuestLogic.reroll(q, 2, 9, 1)).to.equal(true)
			expect(q.daily[2].id ~= before).to.equal(true)
			local ids = {}
			for _, s in q.daily do
				expect(ids[s.id]).to.equal(nil)
				ids[s.id] = true
			end
			expect(QuestLogic.reroll(q, 1, 9, 1)).to.equal(Quests.freeDailyRerolls > 1)
		end)
	end)

	describe("Daily reward", function()
		it("claims once per UTC day and cycles through 7 rewards", function()
			local daily = { lastClaimDay = -1, cycleDay = 0 }
			expect(QuestLogic.claimDaily(daily, T0)).to.equal(1)
			expect(QuestLogic.claimDaily(daily, T0 + 3600)).to.equal(nil)
			for day = 1, #DailyRewards.cycle - 1 do
				expect(QuestLogic.claimDaily(daily, T0 + day * DAY)).to.equal(day + 1)
			end
			expect(QuestLogic.claimDaily(daily, T0 + 7 * DAY)).to.equal(1)
		end)

		it("never resets progress after missing days", function()
			local daily = { lastClaimDay = -1, cycleDay = 0 }
			QuestLogic.claimDaily(daily, T0)
			QuestLogic.claimDaily(daily, T0 + DAY)
			expect(QuestLogic.claimDaily(daily, T0 + 10 * DAY)).to.equal(3)
		end)
	end)
end

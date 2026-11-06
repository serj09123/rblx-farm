--!strict
-- Pure daily/weekly quest and daily-reward rules.

local config = script.Parent.Parent.config
local DailyRewards = require(config.DailyRewards)
local Quests = require(config.Quests)
local Rewards = require(config.Rewards)
local TimeUtil = require(script.Parent.Parent.util.TimeUtil)
local Types = require(script.Parent.Parent.Types)

local QuestLogic = {}

type QuestsData = {
	dayKey: number,
	daily: { Types.QuestState },
	rerollsUsed: number,
	weekKey: number,
	weekly: { Types.QuestState },
}

local function scaledTarget(def: Quests.QuestDef, tier: number): number
	if def.targetScalesWithTier then
		local scale = Rewards.tierCoinScale[math.clamp(tier, 1, #Rewards.tierCoinScale)]
		return def.target * scale
	end
	return def.target
end

-- Deterministic pick of `count` distinct quests (same user + period = same quests).
function QuestLogic.roll(
	pool: { Quests.QuestDef },
	count: number,
	seed: number,
	tier: number,
	exclude: { [string]: boolean }?
): { Types.QuestState }
	local rng = Random.new(seed)
	local candidates = {}
	for _, def in pool do
		if not (exclude and exclude[def.id]) then
			table.insert(candidates, def)
		end
	end
	local result = {}
	for _ = 1, math.min(count, #candidates) do
		local index = rng:NextInteger(1, #candidates)
		local def = table.remove(candidates, index) :: Quests.QuestDef
		table.insert(result, { id = def.id, progress = 0, target = scaledTarget(def, tier), claimed = false })
	end
	return result
end

local function seedFor(userId: number, period: number, salt: number): number
	return (userId % 1000003) * 7919 + period * 104729 + salt
end

-- Resets expired quest sets. Returns true when something changed.
function QuestLogic.refresh(quests: QuestsData, userId: number, now: number, tier: number): boolean
	local changed = false
	local day = TimeUtil.dayKey(now)
	if quests.dayKey ~= day then
		quests.dayKey = day
		quests.daily = QuestLogic.roll(Quests.daily, Quests.dailyCount, seedFor(userId, day, 1), tier)
		quests.rerollsUsed = 0
		changed = true
	end
	local week = TimeUtil.weekKey(now)
	if quests.weekKey ~= week then
		quests.weekKey = week
		quests.weekly = QuestLogic.roll(Quests.weekly, Quests.weeklyCount, seedFor(userId, week, 2), tier)
		changed = true
	end
	return changed
end

-- Adds progress to every unclaimed quest of `kind`. Returns true when changed.
function QuestLogic.progress(quests: QuestsData, kind: string, amount: number): boolean
	if amount <= 0 then
		return false
	end
	local changed = false
	for _, list in { quests.daily, quests.weekly } do
		for _, state in list do
			local def = Quests.byId[state.id]
			if def and def.kind == kind and not state.claimed and state.progress < state.target then
				state.progress = math.min(state.target, state.progress + amount)
				changed = true
			end
		end
	end
	return changed
end

function QuestLogic.canClaim(state: Types.QuestState?): boolean
	return state ~= nil and not state.claimed and state.progress >= state.target
end

-- Replaces an unclaimed daily quest with a different one (free rerolls per day).
function QuestLogic.reroll(quests: QuestsData, index: number, userId: number, tier: number): boolean
	local state = quests.daily[index]
	if not state or state.claimed or quests.rerollsUsed >= Quests.freeDailyRerolls then
		return false
	end
	local exclude = {}
	for _, s in quests.daily do
		exclude[s.id] = true
	end
	local replacement =
		QuestLogic.roll(Quests.daily, 1, seedFor(userId, quests.dayKey, 100 + quests.rerollsUsed), tier, exclude)[1]
	if not replacement then
		return false
	end
	quests.daily[index] = replacement
	quests.rerollsUsed += 1
	return true
end

-- Daily reward ------------------------------------------------------------------

type DailyData = { lastClaimDay: number, cycleDay: number }

function QuestLogic.dailyAvailable(daily: DailyData, now: number): boolean
	return daily.lastClaimDay < TimeUtil.dayKey(now)
end

-- Next reward index (1..7). Missing days never resets progress.
function QuestLogic.nextDailyIndex(daily: DailyData): number
	return (daily.cycleDay % #DailyRewards.cycle) + 1
end

-- Claims today's reward. Returns the reward index or nil if already claimed today.
function QuestLogic.claimDaily(daily: DailyData, now: number): number?
	if not QuestLogic.dailyAvailable(daily, now) then
		return nil
	end
	local index = QuestLogic.nextDailyIndex(daily)
	daily.cycleDay = index
	daily.lastClaimDay = TimeUtil.dayKey(now)
	return index
end

return table.freeze(QuestLogic)

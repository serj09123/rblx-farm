--!strict
-- Non-punishing 7-day login reward cycle.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DailyRewards = require(Shared.config.DailyRewards)
local Net = require(Shared.net.Net)
local QuestLogic = require(Shared.logic.QuestLogic)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local SyncService = require(script.Parent.SyncService)
local Notifier = require(script.Parent.Parent.Notifier)

local DailyRewardService = {}

local function onClaim(player: Player)
	local data = DataService:get(player)
	if not data then
		return
	end
	local index = QuestLogic.claimDaily(data.daily, os.time())
	if not index then
		Notifier.error(player, "Come back tomorrow!")
		return
	end
	local summary = RewardService:grant(player, DailyRewards.cycle[index], "daily_" .. index, "TimedReward")
	SyncService:markDirty(player, "daily")
	Notifier.send(player, "reward", string.format("Day %d reward! %s", index, RewardService:describe(summary)), "daily")
	Analytics.custom(player, "DailyClaimed", index)
end

function DailyRewardService:Init()
	Net.Server.on("ClaimDaily", onClaim)
end

return DailyRewardService

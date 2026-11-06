--!strict
-- First-session onboarding. The server owns step state and rewards; the client only
-- draws arrows/highlights for the current step. Steps advance on real gameplay events.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.net.Net)
local Tutorial = require(Shared.config.Tutorial)
local Types = require(Shared.Types)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local RewardService = require(script.Parent.RewardService)
local SyncService = require(script.Parent.SyncService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local TutorialService = {}

local function currentStepId(data: Types.Profile): string?
	if data.tutorial.done then
		return nil
	end
	local step = Tutorial.steps[data.tutorial.step]
	return if step then step.id else nil
end

local function logFunnel(player: Player, stepNumber: number, name: string)
	-- Onboarding funnel: 1 = joined, 2.. = completed tutorial steps.
	Analytics.onboarding(player, stepNumber, name)
end

local function advance(player: Player, expectedStepId: string)
	local data = DataService:get(player)
	if not data or currentStepId(data) ~= expectedStepId then
		return
	end
	local stepIndex = data.tutorial.step
	local step = Tutorial.steps[stepIndex]
	if step.reward then
		local summary = RewardService:grant(player, step.reward, "tutorial_" .. step.id, "Onboarding")
		Notifier.send(player, "reward", RewardService:describe(summary), "gift")
	end
	logFunnel(player, stepIndex + 1, step.id)
	if stepIndex >= #Tutorial.steps then
		data.tutorial.done = true
		Analytics.custom(player, "TutorialComplete")
	else
		data.tutorial.step = stepIndex + 1
	end
	SyncService:markDirty(player, "tutorial")
end

function TutorialService:isActive(player: Player): boolean
	local data = DataService:get(player)
	return data ~= nil and not data.tutorial.done
end

function TutorialService:Init()
	Net.Server.on("TutorialAction", function(player: Player, action: string)
		if action == "openGift" then
			advance(player, "reward")
		elseif action == "skip" then
			local data = DataService:get(player)
			if data and not data.tutorial.done then
				data.tutorial.done = true
				SyncService:markDirty(player, "tutorial")
				Analytics.custom(player, "TutorialSkipped")
			end
		end
	end)
	SyncService:registerProvider("tutorial", function(_player: Player, data: Types.Profile)
		return {
			step = data.tutorial.step,
			done = data.tutorial.done,
			stepId = currentStepId(data),
		}
	end)
end

function TutorialService:PlayerReady(player: Player, data: Types.Profile)
	if data.tutorial.done then
		return
	end
	if not data.tutorial.starterGiven then
		if data.stats.hatched > 0 then
			-- Existing player without tutorial state (e.g. migrated): skip onboarding.
			data.tutorial.done = true
			return
		end
		data.tutorial.starterGiven = true
		InventoryService:addNests(player, Tutorial.starterNest, 1)
		logFunnel(player, 1, "joined")
	end
end

function TutorialService:Start()
	ServerEvents.nestPlanted:Connect(function(player: Player, _slot: number, nestId: string)
		if nestId == Tutorial.starterNest then
			advance(player, "plant")
		else
			advance(player, "plant2")
		end
	end)
	ServerEvents.hatched:Connect(function(player: Player)
		advance(player, "hatch")
	end)
	ServerEvents.habitatPlaced:Connect(function(player: Player)
		advance(player, "habitat")
	end)
	ServerEvents.nestBought:Connect(function(player: Player)
		advance(player, "buy")
	end)
end

return TutorialService

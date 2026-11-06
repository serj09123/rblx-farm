--!strict
-- Cheer: visit a neighbour's ranch and boost one of their growing nests.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Coop = require(Shared.config.Coop)
local CoopMath = require(Shared.logic.CoopMath)
local Net = require(Shared.net.Net)
local Progression = require(Shared.logic.Progression)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FarmService = require(script.Parent.FarmService)
local PlotService = require(script.Parent.PlotService)
local SyncService = require(script.Parent.SyncService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local CheerService = {}

-- Keyed by userId and kept after leaving, so rejoining does not reset the hourly cap.
local recent: { [number]: { number } } = {}

local MESSAGES = {
	self = "That's your own nest!",
	notGrowing = "This nest isn't growing",
	alreadyCheered = "You already cheered this nest",
	nestFull = "This nest has enough cheers",
	hourlyLimit = "You're out of cheers for now",
}

local function onCheer(helper: Player, ownerUserId: number, slot: number)
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local helperData = DataService:get(helper)
	local ownerData = owner and DataService:get(owner)
	if not owner or not helperData or not ownerData then
		return
	end
	local layout = PlotService:get(owner)
	local bed = layout and layout.beds[slot]
	local character = helper.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not bed or not root or (root.Position - bed.Position).Magnitude > Coop.cheer.maxDistance then
		return
	end

	local nest = ownerData.nests[tostring(slot)]
	local now = os.time()
	local history = recent[helper.UserId] or {}
	recent[helper.UserId] = history
	local check = CoopMath.checkCheer(nest, owner.UserId, helper.UserId, history, now)
	if check ~= "ok" then
		Notifier.error(helper, MESSAGES[check] or "Can't cheer")
		return
	end
	local nestSlot = nest :: any
	nestSlot.cheers[tostring(helper.UserId)] = true
	if not FarmService:addProgress(owner, slot, nestSlot.required * Coop.cheer.progressFraction) then
		nestSlot.cheers[tostring(helper.UserId)] = nil
		return
	end

	table.insert(history, now)
	while #history > Coop.cheer.maxPerHourPerHelper do
		table.remove(history, 1)
	end
	helperData.stats.cheersGiven += 1
	SyncService:markDirty(helper, "stats")

	local tier = Progression.tier(helperData.stats.hatched)
	local coins = Coop.cheer.helperCoinsPerTier[math.clamp(tier, 1, #Coop.cheer.helperCoinsPerTier)]
	EconomyService:add(helper, coins, "cheer", "Gameplay")
	Notifier.send(helper, "success", string.format("Cheered %s! +%d", owner.DisplayName, coins), "cheer")
	Notifier.send(owner, "info", helper.DisplayName .. " cheered your nest!", "cheer")
	ServerEvents.cheered:Fire(helper, owner, slot)
end

function CheerService:Init()
	Net.Server.on("CheerNest", onCheer)
end

function CheerService:Start()
	-- Drop histories whose entries have all expired so the table cannot grow forever.
	Players.PlayerRemoving:Connect(function(player)
		task.delay(3700, function()
			if not Players:GetPlayerByUserId(player.UserId) then
				recent[player.UserId] = nil
			end
		end)
	end)
end

return CheerService

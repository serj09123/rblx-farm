--!strict
-- Daily and weekly quests driven by gameplay events.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.net.Net)
local Progression = require(Shared.logic.Progression)
local QuestLogic = require(Shared.logic.QuestLogic)
local Quests = require(Shared.config.Quests)
local Rarities = require(Shared.config.Rarities)
local Types = require(Shared.Types)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local SyncService = require(script.Parent.SyncService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local QuestService = {}

local function refresh(player: Player, data: Types.Profile)
	if QuestLogic.refresh(data.quests, player.UserId, os.time(), Progression.tier(data.stats.hatched)) then
		SyncService:markDirty(player, "quests")
	end
end

function QuestService:progress(player: Player, kind: string, amount: number)
	local data = DataService:get(player)
	if not data then
		return
	end
	refresh(player, data)
	if QuestLogic.progress(data.quests, kind, amount) then
		SyncService:markDirty(player, "quests")
	end
end

local function onClaim(player: Player, kind: string, index: number)
	local data = DataService:get(player)
	if not data then
		return
	end
	refresh(player, data)
	local list = if kind == "daily" then data.quests.daily else data.quests.weekly
	local state = list[index]
	if not QuestLogic.canClaim(state) then
		return
	end
	local questState = state :: Types.QuestState
	local def = Quests.byId[questState.id]
	if not def then
		return
	end
	questState.claimed = true
	local summary = RewardService:grant(player, def.reward, "quest_" .. def.id, "Gameplay")
	SyncService:markDirty(player, "quests")
	Notifier.send(player, "reward", "Quest complete! " .. RewardService:describe(summary), "quests")
	Analytics.custom(player, "QuestClaimed_" .. kind)
end

local function onReroll(player: Player, index: number)
	local data = DataService:get(player)
	if not data then
		return
	end
	refresh(player, data)
	if QuestLogic.reroll(data.quests, index, player.UserId, Progression.tier(data.stats.hatched)) then
		SyncService:markDirty(player, "quests")
	else
		Notifier.error(player, "No rerolls left today")
	end
end

function QuestService:Init()
	Net.Server.on("ClaimQuest", onClaim)
	Net.Server.on("RerollQuest", onReroll)
end

function QuestService:PlayerReady(player: Player, data: Types.Profile)
	refresh(player, data)
end

function QuestService:Start()
	ServerEvents.hatched:Connect(function(player: Player, creature: Types.Creature)
		QuestService:progress(player, "hatch", 1)
		if Rarities.order(creature.rarity) >= Rarities.order("Rare") then
			QuestService:progress(player, "hatchRarePlus", 1)
		end
		if #creature.mutations > 0 then
			QuestService:progress(player, "hatchMutated", 1)
		end
	end)
	ServerEvents.creaturesSold:Connect(function(player: Player, sold: { Types.Creature })
		QuestService:progress(player, "sell", #sold)
	end)
	ServerEvents.coinsEarned:Connect(function(player: Player, amount: number, sku: string)
		if string.sub(sku, 1, 6) ~= "quest_" then
			QuestService:progress(player, "earnCoins", amount)
		end
	end)
	ServerEvents.essenceContributed:Connect(function(player: Player, amount: number)
		QuestService:progress(player, "essence", amount)
	end)
	ServerEvents.habitatPlaced:Connect(function(player: Player)
		QuestService:progress(player, "placeHabitat", 1)
	end)
	ServerEvents.cheered:Connect(function(helper: Player)
		QuestService:progress(helper, "cheer", 1)
	end)
	ServerEvents.indexDiscovered:Connect(function(player: Player, count: number)
		QuestService:progress(player, "discover", count)
	end)
	ServerEvents.upgraded:Connect(function(player: Player)
		QuestService:progress(player, "upgrade", 1)
	end)
	ServerEvents.creatureDonated:Connect(function(player: Player)
		QuestService:progress(player, "donate", 1)
	end)

	-- Roll new quests for online players at UTC midnight / Monday.
	task.spawn(function()
		while true do
			task.wait(30)
			for _, player in DataService:getLoadedPlayers() do
				local data = DataService:get(player)
				if data then
					refresh(player, data)
				end
			end
		end
	end)
end

return QuestService

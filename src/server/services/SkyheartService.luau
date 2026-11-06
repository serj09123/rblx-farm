--!strict
-- Server-wide co-op goal. Everyone feeds Essence; when the meter fills, the whole
-- server Blooms (buff) and every contributor on the server gets a Skyheart Nest.
-- All state is in server memory keyed by userId, so leaving players never break it.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Coop = require(Shared.config.Coop)
local CoopMath = require(Shared.logic.CoopMath)
local Nests = require(Shared.config.Nests)
local Net = require(Shared.net.Net)
local Progression = require(Shared.logic.Progression)
local Rarities = require(Shared.config.Rarities)
local Types = require(Shared.Types)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local ModifierService = require(script.Parent.ModifierService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local SkyheartService = {}

local state = {
	progress = 0,
	target = Coop.skyheart.minTarget,
	contributions = {} :: { [string]: number },
	bloomUntil = 0,
	round = 1,
}

local broadcastQueued = false

local function snapshot(): any
	local contributors = 0
	for _, amount in state.contributions do
		if amount > 0 then
			contributors += 1
		end
	end
	return {
		progress = math.floor(state.progress),
		target = state.target,
		bloomUntil = state.bloomUntil,
		round = state.round,
		contributors = contributors,
	}
end

local function broadcast()
	if broadcastQueued then
		return
	end
	broadcastQueued = true
	task.delay(0.5, function()
		broadcastQueued = false
		Net.Server.fireAll("WorldState", { skyheart = snapshot() })
	end)
end

local function currentTiers(): { number }
	local tiers = {}
	for _, player in DataService:getLoadedPlayers() do
		local data = DataService:get(player)
		if data then
			table.insert(tiers, Progression.tier(data.stats.hatched))
		end
	end
	return tiers
end

function SkyheartService:contributionOf(player: Player): number
	return state.contributions[tostring(player.UserId)] or 0
end

function SkyheartService:isBlooming(): boolean
	return state.bloomUntil > os.time()
end

local function applyBloom(seconds: number)
	local now = os.time()
	local base = math.max(state.bloomUntil, now)
	state.bloomUntil = math.min(base + seconds, now + seconds * 2)
	ModifierService:setGlobal("bloom", {
		coinBonus = Coop.bloom.coinBonus,
		growthMultiplier = Coop.bloom.growthMultiplier,
		mutationMultiplier = Coop.bloom.mutationMultiplier,
	}, state.bloomUntil, "Skyheart Bloom")
end

local function completeRound()
	local eligible: { [string]: boolean } = {}
	local byId: { [string]: Player } = {}
	for _, player in Players:GetPlayers() do
		eligible[tostring(player.UserId)] = true
		byId[tostring(player.UserId)] = player
	end
	local rewards = CoopMath.bloomRewards(state.contributions, eligible)
	local nestDef = Nests.byId[Coop.skyheart.rewardNest]
	for userId, count in rewards do
		local player = byId[userId]
		if player and InventoryService:addNests(player, Coop.skyheart.rewardNest, count) then
			Notifier.send(
				player,
				"reward",
				string.format("Skyheart Bloom! +%d %s", count, if nestDef then nestDef.displayName else "nest"),
				"skyheart"
			)
			Analytics.custom(player, "BloomReward", count)
		end
	end
	local overflowTarget = state.target
	state.target = CoopMath.skyheartTarget(currentTiers())
	state.progress = CoopMath.carryOver(state.progress, overflowTarget, state.target)
	state.contributions = {}
	state.round += 1
	applyBloom(Coop.skyheart.bloomSeconds)
	Notifier.announce({ kind = "bloom", source = "goal", untilTime = state.bloomUntil })
	ServerEvents.bloomStarted:Fire(nil, "goal")
	broadcast()
end

local function checkComplete()
	if state.progress >= state.target then
		completeRound()
	end
end

function SkyheartService:addEssence(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local key = tostring(player.UserId)
	state.contributions[key] = (state.contributions[key] or 0) + amount
	state.progress += amount
	ServerEvents.essenceContributed:Fire(player, amount)
	broadcast()
	checkComplete()
end

-- Server Bloom product: buff for everyone right now (does not consume progress).
function SkyheartService:triggerPurchasedBloom(purchaser: Player)
	applyBloom(Coop.skyheart.bloomSeconds)
	Notifier.announce({
		kind = "bloom",
		source = "purchase",
		playerName = purchaser.DisplayName,
		untilTime = state.bloomUntil,
	})
	ServerEvents.bloomStarted:Fire(purchaser, "purchase")
	broadcast()
end

local function recomputeTarget()
	state.target = CoopMath.skyheartTarget(currentTiers())
	broadcast()
	checkComplete()
end

function SkyheartService:PlayerReady(player: Player, _data: Types.Profile)
	recomputeTarget()
	Net.Server.fire(player, "WorldState", { skyheart = snapshot() })
end

function SkyheartService:Start()
	ServerEvents.hatched:Connect(function(player: Player, creature: Types.Creature)
		local rarity = Rarities.byId[creature.rarity]
		SkyheartService:addEssence(player, if rarity then rarity.essence else 1)
	end)
	ServerEvents.creatureDonated:Connect(function(player: Player, _creature: Types.Creature, essence: number)
		SkyheartService:addEssence(player, essence)
		Notifier.send(player, "success", string.format("+%d essence to the Skyheart", essence), "skyheart")
	end)
	ServerEvents.cheered:Connect(function(helper: Player)
		SkyheartService:addEssence(helper, Coop.skyheart.cheerEssence)
	end)
	ServerEvents.upgraded:Connect(recomputeTarget)
	Players.PlayerRemoving:Connect(function()
		task.defer(recomputeTarget)
	end)
end

return SkyheartService

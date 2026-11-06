--!strict
-- Computes each player's live gameplay modifiers from upgrades, boosts, passes,
-- server-wide sources (weather, Skyheart Bloom), seasons and community bonus.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.config.Economy)
local GrowthMath = require(Shared.logic.GrowthMath)
local ModifierMath = require(Shared.logic.ModifierMath)
local Monetization = require(Shared.config.Monetization)
local Progression = require(Shared.logic.Progression)
local Signal = require(Shared.util.Signal)
local Types = require(Shared.Types)
local Weather = require(Shared.config.Weather)

local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)
local SyncService = require(script.Parent.SyncService)

local ModifierService = {
	-- fired when any modifier that affects all players changes
	changed = Signal.new(),
}

type GlobalSource = { modifiers: Weather.Modifiers, untilTime: number?, label: string }

local globals: { [string]: GlobalSource } = {}
local boostState: { [Player]: number } = {}

local luckBoost = Monetization.productByKey.LuckBoost15
local growthBoost = Monetization.productByKey.GrowthBoost15

function ModifierService:setGlobal(name: string, modifiers: Weather.Modifiers?, untilTime: number?, label: string?)
	if modifiers then
		globals[name] = { modifiers = modifiers, untilTime = untilTime, label = label or name }
	else
		globals[name] = nil
	end
	ModifierService.changed:Fire()
end

function ModifierService:isGlobalActive(name: string): boolean
	local source = globals[name]
	return source ~= nil and (source.untilTime == nil or source.untilTime > os.time())
end

local function boostActive(untilTime: number?, now: number): boolean
	return untilTime ~= nil and untilTime > now
end

local function base(player: Player, data: Types.Profile, now: number): ModifierMath.Base
	local growth = Progression.value("growthSpeed", Progression.level(data.upgrades, "growthSpeed"))
	if boostActive(data.boosts.growthUntil, now) then
		growth *= growthBoost and growthBoost.growthMultiplier or 2
	end
	local luck = Progression.value("luck", Progression.level(data.upgrades, "luck"))
	if boostActive(data.boosts.luckUntil, now) then
		luck *= luckBoost and luckBoost.luckMultiplier or 2
	end
	return {
		coinMultiplier = if PassService:owns(player, "DoubleCoins") then Monetization.doubleCoinsMultiplier else 1,
		growthMultiplier = growth,
		luckMultiplier = luck,
	}
end

local function communityBonus(): number
	local others = math.max(0, #DataService:getLoadedPlayers() - 1)
	return math.min(others * Economy.communityBonusPerPlayer, Economy.communityBonusMax)
end

function ModifierService:get(player: Player): Types.Modifiers
	local data = DataService:get(player)
	local now = os.time()
	local sources = {}
	for _, source in globals do
		if source.untilTime == nil or source.untilTime > now then
			table.insert(sources, source.modifiers)
		end
	end
	local bonus = communityBonus()
	if bonus > 0 then
		table.insert(sources, { coinBonus = bonus })
	end
	local baseMods: ModifierMath.Base = if data
		then base(player, data, now)
		else { coinMultiplier = 1, growthMultiplier = 1, luckMultiplier = 1 }
	return ModifierMath.combine(baseMods, sources, ModifierMath.activeSeasons(now))
end

-- Modifiers that apply while the player is offline (no global/server sources).
function ModifierService:offlineGrowth(data: Types.Profile): (number, { GrowthMath.Window })
	local rate = Progression.value("growthSpeed", Progression.level(data.upgrades, "growthSpeed"))
	local windows: { GrowthMath.Window } = {}
	if data.boosts.growthUntil > 0 then
		table.insert(windows, {
			from = 0,
			to = data.boosts.growthUntil,
			multiplier = growthBoost and growthBoost.growthMultiplier or 2,
		})
	end
	return rate, windows
end

-- Extends a personal boost (stacking duration, capped).
function ModifierService:extendBoost(player: Player, field: "luckUntil" | "growthUntil", seconds: number)
	local data = DataService:get(player)
	if not data then
		return
	end
	local now = os.time()
	local current = math.max(data.boosts[field], now)
	data.boosts[field] = math.min(current + seconds, now + Monetization.maxBoostSeconds)
	SyncService:markDirty(player, "boosts", "modifiers", "nests")
end

local function summary(player: Player): any
	local mods = ModifierService:get(player)
	local labels = {}
	local now = os.time()
	for _, source in globals do
		if source.untilTime == nil or source.untilTime > now then
			table.insert(labels, { label = source.label, untilTime = source.untilTime })
		end
	end
	return {
		coinMultiplier = mods.coinMultiplier,
		coinBonus = mods.coinBonus,
		growthMultiplier = mods.growthMultiplier,
		luckMultiplier = mods.luckMultiplier,
		mutationMultiplier = mods.mutationMultiplier,
		activeSeasons = mods.activeSeasons,
		sources = labels,
	}
end

function ModifierService:Init()
	SyncService:registerProvider("modifiers", summary)
end

function ModifierService:Start()
	ModifierService.changed:Connect(function()
		for _, player in Players:GetPlayers() do
			SyncService:markDirty(player, "modifiers", "nests")
		end
	end)
	-- Player count changes the community bonus.
	local function refreshAll()
		ModifierService.changed:Fire()
	end
	DataService.profileLoaded:Connect(refreshAll)
	Players.PlayerRemoving:Connect(function(player)
		boostState[player] = nil
		task.defer(refreshAll)
	end)
	-- Expire timed sources and personal boosts.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			local expired = false
			for name, source in globals do
				if source.untilTime and source.untilTime <= now then
					globals[name] = nil
					expired = true
				end
			end
			if expired then
				ModifierService.changed:Fire()
			end
			for _, player in DataService:getLoadedPlayers() do
				local data = DataService:get(player)
				if data then
					local state = (if data.boosts.luckUntil > now then 1 else 0)
						+ (if data.boosts.growthUntil > now then 2 else 0)
					if boostState[player] ~= nil and boostState[player] ~= state then
						SyncService:markDirty(player, "boosts", "modifiers", "nests")
					end
					boostState[player] = state
				end
			end
		end
	end)
end

return ModifierService

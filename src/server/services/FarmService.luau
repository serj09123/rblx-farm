--!strict
-- Core farm loop: buy -> plant -> grow (online ticks + offline catch-up) -> hatch,
-- habitats with passive income, and the odds endpoint used by the shop UI.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.config.Economy)
local Format = require(Shared.util.Format)
local GrowthMath = require(Shared.logic.GrowthMath)
local HatchOdds = require(Shared.logic.HatchOdds)
local Hatchery = require(Shared.logic.Hatchery)
local Monetization = require(Shared.config.Monetization)
local MutationRoller = require(Shared.logic.MutationRoller)
local Mutations = require(Shared.config.Mutations)
local Nests = require(Shared.config.Nests)
local Net = require(Shared.net.Net)
local Odds = require(Shared.config.Odds)
local Progression = require(Shared.logic.Progression)
local Rarities = require(Shared.config.Rarities)
local Types = require(Shared.Types)
local Valuation = require(Shared.logic.Valuation)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local ModifierService = require(script.Parent.ModifierService)
local PlotService = require(script.Parent.PlotService)
local SyncService = require(script.Parent.SyncService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local FarmService = {}

local rng = Random.new()
local ETA_REFRESH_SECONDS = 10

-- Growth -----------------------------------------------------------------------

local function updateGrowth(player: Player, data: Types.Profile, now: number): boolean
	local changed = false
	local rate: number? = nil
	for key, nest in data.nests do
		if nest.progress < nest.required then
			local dt = now - nest.lastUpdate
			if dt > 0 then
				rate = rate or ModifierService:get(player).growthMultiplier
				nest.progress = math.min(nest.required, nest.progress + dt * (rate :: number))
				nest.lastUpdate = now
				if nest.progress >= nest.required then
					changed = true
					PlotService:refreshBed(player, tonumber(key) :: number)
				end
			end
		else
			nest.lastUpdate = now
		end
	end
	return changed
end

local function refreshEtas(player: Player, data: Types.Profile, now: number)
	local rate = ModifierService:get(player).growthMultiplier
	for key, nest in data.nests do
		local slot = tonumber(key) :: number
		if nest.progress < nest.required and rate > 0 then
			PlotService:setBedEta(player, slot, now + math.ceil((nest.required - nest.progress) / rate))
		else
			PlotService:setBedEta(player, slot, now)
		end
	end
end

-- Adds flat growth seconds to one nest (Cheer). Returns true if applied.
function FarmService:addProgress(player: Player, slot: number, seconds: number): boolean
	local data = DataService:get(player)
	local nest = data and data.nests[tostring(slot)]
	if not data or not nest or nest.progress >= nest.required then
		return false
	end
	updateGrowth(player, data, os.time())
	nest.progress = math.min(nest.required, nest.progress + seconds)
	PlotService:refreshBed(player, slot)
	refreshEtas(player, data, os.time())
	SyncService:markDirty(player, "nests")
	return true
end

-- Instantly completes every growing nest (Instant Grow product).
function FarmService:finishAll(player: Player): number
	local data = DataService:get(player)
	if not data then
		return 0
	end
	local count = 0
	for key, nest in data.nests do
		if nest.progress < nest.required then
			nest.progress = nest.required
			count += 1
			PlotService:refreshBed(player, tonumber(key) :: number)
		end
	end
	refreshEtas(player, data, os.time())
	SyncService:markDirty(player, "nests")
	return count
end

-- Income -----------------------------------------------------------------------

local function baseIncomeRate(data: Types.Profile): number
	local rate = 0
	for _, creatureId in data.habitats do
		local creature = data.creatures[creatureId]
		if creature then
			rate += Valuation.incomePerSecond(creature)
		end
	end
	return rate
end

local function accrueIncome(player: Player, data: Types.Profile, now: number)
	if data.income.lastAccrual <= 0 then
		data.income.lastAccrual = now
		return
	end
	local dt = now - data.income.lastAccrual
	if dt <= 0 then
		return
	end
	data.income.lastAccrual = now
	local rate = baseIncomeRate(data)
	if rate <= 0 then
		return
	end
	local mult, bonus = EconomyService:coinModifiers(player)
	local amount = rate * dt * mult * (1 + bonus) + data.income.carry
	local whole = math.floor(amount)
	data.income.carry = amount - whole
	if whole > 0 then
		EconomyService:add(player, whole, "habitat_income", "Gameplay")
	end
end

-- Odds -------------------------------------------------------------------------

local function rarityList(odds: { [string]: number }): { { id: string, p: number } }
	local list = {}
	for id, p in odds do
		table.insert(list, { id = id, p = p })
	end
	table.sort(list, function(a, b)
		return Rarities.order(a.id) < Rarities.order(b.id)
	end)
	return list
end

function FarmService:oddsFor(player: Player, nestId: string): any
	local data = DataService:get(player)
	local def = Nests.byId[nestId]
	if not data or not def then
		return { ok = false, error = "unknown nest" }
	end
	local mods = ModifierService:get(player)
	local rarityOdds, pityTarget = HatchOdds.rarityOdds(def, mods.luckMultiplier, data.pity, mods.activeSeasons)
	local chances = MutationRoller.chances(mods)
	local mutationList = {}
	for _, m in Mutations.list do
		table.insert(mutationList, { id = m.id, chance = chances[m.id], multiplier = m.multiplier })
	end
	local boost = Monetization.productByKey.LuckBoost15
	local boostedLuck = math.min(mods.luckMultiplier * (if boost then boost.luckMultiplier or 2 else 2), Odds.maxLuck)
	local boosted = HatchOdds.rarityOdds(def, boostedLuck, data.pity, mods.activeSeasons)
	return {
		ok = true,
		nestId = nestId,
		guaranteed = def.guaranteed,
		luck = mods.luckMultiplier,
		rarities = rarityList(rarityOdds),
		species = HatchOdds.speciesOdds(def, mods.luckMultiplier, data.pity, mods.activeSeasons),
		mutations = mutationList,
		maxMutations = Mutations.maxPerCreature,
		pity = HatchOdds.pityStatus(def, data.pity),
		pityTarget = pityTarget,
		luckBoostPreview = { luck = boostedLuck, rarities = rarityList(boosted) },
		disclaimer = Odds.roundingDisclaimer,
	}
end

-- Handlers ---------------------------------------------------------------------

local function onPlant(player: Player, slot: number, nestId: string)
	local data = DataService:get(player)
	local def = Nests.byId[nestId]
	if not data or not def then
		return
	end
	if slot > InventoryService:limits(player).nestSlots then
		Notifier.error(player, "Bed locked")
		return
	end
	local key = tostring(slot)
	if data.nests[key] then
		return
	end
	if not InventoryService:takeNest(player, nestId) then
		Notifier.error(player, "No " .. def.displayName)
		return
	end
	local now = os.time()
	data.nests[key] = { nestId = nestId, progress = 0, required = def.growSeconds, lastUpdate = now, cheers = {} }
	PlotService:refreshBed(player, slot)
	refreshEtas(player, data, now)
	SyncService:markDirty(player, "nests")
	ServerEvents.nestPlanted:Fire(player, slot, nestId)
end

local function celebrateLevel(creature: Types.Creature): number
	local rarity = Rarities.byId[creature.rarity]
	local level = if rarity then rarity.celebrate else 0
	if #creature.mutations >= 2 then
		level = math.max(level, 2)
	elseif #creature.mutations == 1 then
		level = math.max(level, 1)
	end
	return level
end

local function onHatch(player: Player, slot: number)
	local data = DataService:get(player)
	if not data then
		return
	end
	local key = tostring(slot)
	local nest = data.nests[key]
	if not nest then
		return
	end
	updateGrowth(player, data, os.time())
	if nest.progress < nest.required then
		return
	end
	local def = Nests.byId[nest.nestId]
	if not def then
		warn("[FarmService] unknown nest " .. tostring(nest.nestId) .. " removed for " .. player.UserId)
		data.nests[key] = nil
		SyncService:markDirty(player, "nests")
		return
	end
	if InventoryService:freeSpace(player) <= 0 then
		Notifier.error(player, "Backpack full! Sell or place critters")
		return
	end

	local mods = ModifierService:get(player)
	local outcome = Hatchery.roll(def, {
		luck = mods.luckMultiplier,
		pity = data.pity,
		modifiers = mods,
		activeSeasons = mods.activeSeasons,
	}, rng)
	local isNewSpecies = data.index.species[outcome.species] == nil
	local source = if def.guaranteed then "tutorial" else "hatch"
	local creature = InventoryService:create(player, outcome, source)
	if not creature then
		Notifier.error(player, "Backpack full!")
		return
	end
	if not def.guaranteed then
		data.pity = Hatchery.nextPity(def, data.pity, outcome.rarity)
	end
	data.nests[key] = nil
	data.stats.hatched += 1
	PlotService:refreshBed(player, slot)
	PlotService:setBedEta(player, slot, nil)
	SyncService:markDirty(player, "nests", "pity", "stats", "limits")

	ServerEvents.hatched:Fire(player, creature, def)
	Net.Server.fire(player, "HatchResult", {
		creature = creature,
		value = Valuation.value(creature),
		celebrate = celebrateLevel(creature),
		newSpecies = isNewSpecies,
		pityTriggered = outcome.pityTriggered,
	})
	local rarity = Rarities.byId[creature.rarity]
	if (rarity and rarity.announceServer) or #creature.mutations >= 2 then
		Notifier.announce({
			kind = "hatch",
			playerName = player.DisplayName,
			species = creature.species,
			rarity = creature.rarity,
			mutations = creature.mutations,
		})
	end
	Analytics.custom(player, "Hatch_" .. creature.rarity)
	if #creature.mutations > 0 then
		Analytics.custom(player, "HatchMutated", #creature.mutations)
	end
end

local function onBuyNest(player: Player, nestId: string, amount: number)
	local data = DataService:get(player)
	local def = Nests.byId[nestId]
	if not data or not def or not def.cost then
		return
	end
	if not Progression.isNestUnlocked(nestId, data.stats.hatched) then
		Notifier.error(player, "Hatch more critters to unlock")
		return
	end
	if not InventoryService:canHoldNests(player, nestId, amount) then
		return
	end
	local cost = def.cost * amount
	if not EconomyService:spend(player, cost, "nest_" .. nestId, "Shop") then
		Notifier.error(player, "Not enough coins")
		return
	end
	InventoryService:addNests(player, nestId, amount)
	ServerEvents.nestBought:Fire(player, nestId, amount)
	Notifier.send(player, "success", string.format("+%d %s", amount, def.displayName), "nest")
end

local function onPlaceHabitat(player: Player, slot: number, creatureId: string)
	local data = DataService:get(player)
	if not data then
		return
	end
	if slot > InventoryService:limits(player).habitatSlots then
		Notifier.error(player, "Habitat locked")
		return
	end
	local creature = data.creatures[creatureId]
	if not creature or InventoryService:isReserved(player, creatureId) then
		return
	end
	accrueIncome(player, data, os.time())
	local previousSlot = InventoryService:habitatSlotOf(data, creatureId)
	if previousSlot then
		data.habitats[previousSlot] = nil
		PlotService:refreshPad(player, tonumber(previousSlot) :: number)
	end
	data.habitats[tostring(slot)] = creatureId
	PlotService:refreshPad(player, slot)
	SyncService:markDirty(player, "habitats", "incomeRate")
	ServerEvents.habitatPlaced:Fire(player, creature)
end

local function onClearHabitat(player: Player, slot: number)
	local data = DataService:get(player)
	if not data or not data.habitats[tostring(slot)] then
		return
	end
	accrueIncome(player, data, os.time())
	data.habitats[tostring(slot)] = nil
	PlotService:refreshPad(player, slot)
	SyncService:markDirty(player, "habitats", "incomeRate")
end

-- Lifecycle --------------------------------------------------------------------

function FarmService:Init()
	Net.Server.on("PlantNest", onPlant)
	Net.Server.on("HatchNest", onHatch)
	Net.Server.on("BuyNest", onBuyNest)
	Net.Server.on("PlaceHabitat", onPlaceHabitat)
	Net.Server.on("ClearHabitat", onClearHabitat)
	Net.Server.handle("GetOdds", function(player: Player, nestId: string)
		return FarmService:oddsFor(player, nestId)
	end)
	SyncService:registerProvider("incomeRate", function(player: Player, data: Types.Profile)
		local mult, bonus = EconomyService:coinModifiers(player)
		return baseIncomeRate(data) * mult * (1 + bonus)
	end)
	SyncService:registerProvider("growthRate", function(player: Player)
		return ModifierService:get(player).growthMultiplier
	end)
end

function FarmService:PlayerReady(player: Player, data: Types.Profile)
	local now = os.time()
	-- Offline growth: permanent speed + personal boost windows only.
	local rate, windows = ModifierService:offlineGrowth(data)
	for _, nest in data.nests do
		if nest.progress < nest.required and nest.lastUpdate > 0 and now > nest.lastUpdate then
			nest.progress =
				math.min(nest.required, nest.progress + GrowthMath.integrate(nest.lastUpdate, now, rate, windows))
		end
		nest.lastUpdate = now
	end
	-- Offline income: base rate x pass multiplier x offline rate, capped.
	local mult = EconomyService:coinModifiers(player)
	local coins, seconds = GrowthMath.offlineIncome(baseIncomeRate(data) * mult, data.income.lastAccrual, now)
	data.income.lastAccrual = now
	if coins >= 1 then
		local credited = EconomyService:add(player, coins, "offline_income", "Gameplay")
		Notifier.send(
			player,
			"reward",
			string.format("Welcome back! +%s coins (%s away)", Format.number(credited), Format.duration(seconds)),
			"coins"
		)
	end
	PlotService:refreshAll(player)
	refreshEtas(player, data, now)
end

function FarmService:Start()
	ModifierService.changed:Connect(function()
		local now = os.time()
		for _, player in DataService:getLoadedPlayers() do
			local data = DataService:get(player)
			if data then
				updateGrowth(player, data, now) -- catch up before ETAs use the new rate
				refreshEtas(player, data, now)
				SyncService:markDirty(player, "growthRate", "incomeRate")
			end
		end
	end)

	task.spawn(function()
		local elapsed = 0
		while true do
			task.wait(1)
			elapsed += 1
			local now = os.time()
			for _, player in DataService:getLoadedPlayers() do
				local data = DataService:get(player)
				if not data then
					continue
				end
				if updateGrowth(player, data, now) then
					SyncService:markDirty(player, "nests")
				end
				if elapsed % Economy.incomeTickSeconds == 0 then
					accrueIncome(player, data, now)
				end
				if elapsed % ETA_REFRESH_SECONDS == 0 then
					refreshEtas(player, data, now)
				end
			end
		end
	end)
end

return FarmService

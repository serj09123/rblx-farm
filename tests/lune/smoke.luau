--!nocheck
-- Smoke test for code that builds Instances (world, critter visuals, every UI panel).
-- Uses Lune's Roblox reflection database, so a wrong property name, a wrong value
-- type or an unknown class/enum fails here instead of in Studio.
--
--   lune run tests/lune/smoke.luau
--
-- Limitations: no physics/rendering/events; derived properties (e.g. Part.Position)
-- cannot be read; TweenService/RunService/etc. are stubs.

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local luneTask = require("@lune/task")

local Loader = require("./loader")

local failures = {}
local warnings = {}
local checks = 0

-- Watchdog: background loops started by controllers must not keep us alive.
luneTask.delay(60, function()
	print("Smoke test timed out")
	process.exit(2)
end)

local function check(name, fn)
	checks += 1
	local ok, err = pcall(fn)
	if not ok then
		table.insert(failures, name .. ": " .. tostring(err))
	end
end

-------------------------------------------------------------------------------
-- Instance proxies: real Lune instances (property validation) + fake events
-------------------------------------------------------------------------------

local realOf = setmetatable({}, { __mode = "k" })
local proxyOf = {}

local function fakeSignal()
	local signal = {}
	function signal.Connect(_self, _fn)
		return { Connected = true, Disconnect = function() end }
	end
	signal.Once = signal.Connect
	function signal.Wait() end
	return signal
end

local EVENTS = {
	Activated = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseButton1Click = true,
	MouseEnter = true,
	MouseLeave = true,
	Changed = true,
	Triggered = true,
	FocusLost = true,
	ChildAdded = true,
	ChildRemoved = true,
	CharacterAdded = true,
	Destroying = true,
}

-- Runtime-only methods Lune does not implement (playback, etc.)
local METHOD_STUBS = { Play = true, Stop = true, Pause = true, Resume = true }

local wrap, unwrap
local ProxyMT = {}

function wrap(value)
	if typeof(value) == "Instance" then
		local existing = proxyOf[value]
		if existing then
			return existing
		end
		local proxy = setmetatable({}, ProxyMT)
		realOf[proxy] = value
		proxyOf[value] = proxy
		return proxy
	elseif type(value) == "table" and getmetatable(value) == nil then
		local out = {}
		for k, v in value do
			out[k] = wrap(v)
		end
		return out
	end
	return value
end

function unwrap(value)
	if type(value) == "table" and realOf[value] then
		return realOf[value]
	end
	return value
end

ProxyMT.__index = function(proxy, key)
	local real = realOf[proxy]
	if EVENTS[key] then
		return fakeSignal()
	end
	if key == "GetPropertyChangedSignal" or key == "GetAttributeChangedSignal" then
		return function()
			return fakeSignal()
		end
	end
	if METHOD_STUBS[key] then
		return function() end
	end
	if key == "WaitForChild" then
		return function(_self, name)
			local child = real:FindFirstChild(name)
			if not child then
				error("WaitForChild would hang: " .. tostring(name) .. " in " .. real:GetFullName(), 2)
			end
			return wrap(child)
		end
	end
	local ok, value = pcall(function()
		return real[key]
	end)
	if not ok then
		error(value, 2)
	end
	if type(value) == "function" then
		return function(_self, ...)
			local args = table.pack(...)
			for i = 1, args.n do
				args[i] = unwrap(args[i])
			end
			local results = table.pack(value(real, table.unpack(args, 1, args.n)))
			for i = 1, results.n do
				results[i] = wrap(results[i])
			end
			return table.unpack(results, 1, results.n)
		end
	end
	return wrap(value)
end

ProxyMT.__newindex = function(proxy, key, value)
	local real = realOf[proxy]
	local ok, err = pcall(function()
		real[key] = unwrap(value)
	end)
	if not ok then
		error(string.format("setting %s.%s: %s", real.ClassName, tostring(key), tostring(err)), 2)
	end
end

ProxyMT.__tostring = function(proxy)
	return tostring(realOf[proxy])
end

local InstanceShim = {
	new = function(className, parent)
		local instance = wrap(roblox.Instance.new(className))
		if parent then
			instance.Parent = parent
		end
		return instance
	end,
}

-------------------------------------------------------------------------------
-- Service stubs
-------------------------------------------------------------------------------

local dataModel = roblox.Instance.new("DataModel")
local workspaceReal = dataModel:GetService("Workspace")
local workspaceProxy = wrap(workspaceReal)

local camera = {
	ViewportSize = roblox.Vector2.new(844, 390),
	GetPropertyChangedSignal = function()
		return fakeSignal()
	end,
}
local workspaceShim = setmetatable({
	CurrentCamera = camera,
	GetAttribute = function()
		return nil
	end,
}, {
	__index = function(_, key)
		return workspaceProxy[key]
	end,
})
-- Parenting to the shim must reach the real workspace.
realOf[workspaceShim] = workspaceReal

local playerGui = wrap(roblox.Instance.new("PlayerGui"))
local localPlayer = setmetatable({
	UserId = 1,
	Name = "Tester",
	DisplayName = "Tester",
	Character = nil,
	CharacterAdded = fakeSignal(),
	GetAttribute = function()
		return nil
	end,
	SetAttribute = function() end,
	WaitForChild = function(_self, name)
		if name == "PlayerGui" then
			return playerGui
		end
		error("no " .. name)
	end,
	FindFirstChild = function()
		return nil
	end,
}, {
	__index = function(_, key)
		error("Player." .. tostring(key) .. " is not stubbed", 2)
	end,
})

local services = {
	Players = {
		LocalPlayer = localPlayer,
		PlayerRemoving = fakeSignal(),
		PlayerAdded = fakeSignal(),
		GetPlayers = function()
			return { localPlayer }
		end,
		GetPlayerByUserId = function()
			return nil
		end,
	},
	TweenService = {
		Create = function()
			return { Play = function() end, Cancel = function() end, Completed = fakeSignal() }
		end,
	},
	RunService = {
		Heartbeat = fakeSignal(),
		RenderStepped = fakeSignal(),
		Stepped = fakeSignal(),
		IsStudio = function()
			return true
		end,
		IsServer = function()
			return false
		end,
		IsClient = function()
			return true
		end,
	},
	CollectionService = {
		AddTag = function(_self, instance, tag)
			unwrap(instance):AddTag(tag)
		end,
		RemoveTag = function(_self, instance, tag)
			unwrap(instance):RemoveTag(tag)
		end,
		GetTags = function(_self, instance)
			return unwrap(instance):GetTags()
		end,
		GetTagged = function()
			return {}
		end,
		GetInstanceAddedSignal = function()
			return fakeSignal()
		end,
		GetInstanceRemovedSignal = function()
			return fakeSignal()
		end,
	},
	ProximityPromptService = { PromptTriggered = fakeSignal() },
	TextChatService = {},
	Lighting = wrap(dataModel:GetService("Lighting")),
	SoundService = wrap(dataModel:GetService("SoundService")),
	Workspace = workspaceShim,
}

local loader = Loader.new({
	services = services,
	globals = {
		Instance = InstanceShim,
		workspace = workspaceShim,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		ColorSequence = roblox.ColorSequence,
		NumberSequence = roblox.NumberSequence,
		NumberRange = roblox.NumberRange,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint or {
			new = function(time, value)
				return { Time = time, Value = value }
			end,
		},
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint or {
			new = function(time, value)
				return { Time = time, Value = value }
			end,
		},
		TweenInfo = {
			new = function(...)
				return { ... }
			end,
		},
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			table.insert(warnings, table.concat(parts, " "))
		end,
	},
})

local tree = loader.tree
local Shared = tree.ReplicatedStorage.Shared
local require = loader.require

-------------------------------------------------------------------------------
-- Server-side builders
-------------------------------------------------------------------------------

local Creatures = require(Shared.config.Creatures)
local Mutations = require(Shared.config.Mutations)
local Nests = require(Shared.config.Nests)

check("WorldService:Init builds hub and plots", function()
	local WorldService = require(tree.ServerScriptService.Server.services.WorldService)
	WorldService:Init()
	local plots = WorldService:getPlots()
	assert(#plots == 6, "expected 6 plots, got " .. #plots)
	for _, plot in plots do
		assert(#plot.beds == 10 and #plot.pads == 8, "bed/pad counts")
	end
end)

check("CreatureVisuals builds every species with every mutation", function()
	local CreatureVisuals = require(tree.ServerScriptService.Server.CreatureVisuals)
	local base = roblox.CFrame.new(0, 1, 0)
	for _, species in Creatures.list do
		local all = {}
		for _, m in Mutations.list do
			local model = CreatureVisuals.build({
				id = "x",
				species = species.id,
				rarity = species.rarity,
				mutations = { m.id },
				size = 1.1,
				obtainedAt = 0,
				source = "hatch",
			}, base)
			assert(model, "no model for " .. species.id)
			CreatureVisuals.release(model)
			table.insert(all, m.id)
		end
		local model = CreatureVisuals.build({
			id = "y",
			species = species.id,
			rarity = species.rarity,
			mutations = { "Frozen", "Electric", "Cosmic" },
			size = 0.8,
			obtainedAt = 0,
			source = "hatch",
		}, base)
		CreatureVisuals.release(model)
	end
	for _, nest in Nests.list do
		CreatureVisuals.releaseEgg(CreatureVisuals.egg(nest.id, base, false))
		CreatureVisuals.releaseEgg(CreatureVisuals.egg(nest.id, base, true))
	end
end)

-------------------------------------------------------------------------------
-- Client: controllers + every panel with representative state
-------------------------------------------------------------------------------

local Net = require(Shared.net.Net)
local handlers = {}
Net.Client.fire = function() end
Net.Client.on = function(name, fn)
	handlers[name] = fn
	return { Disconnect = function() end }
end

local HatchOdds = require(Shared.logic.HatchOdds)
local MutationRoller = require(Shared.logic.MutationRoller)
local Monetization = require(Shared.config.Monetization)
local Odds = require(Shared.config.Odds)
local QuestLogic = require(Shared.logic.QuestLogic)

local NO_PITY = { rarePlus = 3, epicPlus = 74, legendaryPlus = 0 }

Net.Client.invoke = function(name, arg)
	if name == "GetOdds" then
		local def = Nests.byId[arg]
		local rarities = {}
		for id, p in HatchOdds.rarityOdds(def, 1.2, NO_PITY, {}) do
			table.insert(rarities, { id = id, p = p })
		end
		local mutations = {}
		for id, chance in MutationRoller.chances(nil) do
			table.insert(mutations, { id = id, chance = chance, multiplier = Mutations.byId[id].multiplier })
		end
		return {
			ok = true,
			nestId = arg,
			luck = 1.2,
			rarities = rarities,
			species = HatchOdds.speciesOdds(def, 1.2, NO_PITY, {}),
			mutations = mutations,
			maxMutations = Mutations.maxPerCreature,
			pity = HatchOdds.pityStatus(def, NO_PITY),
			pityTarget = HatchOdds.pityTarget(def, NO_PITY),
			luckBoostPreview = { luck = 2.4, rarities = rarities },
			disclaimer = Odds.roundingDisclaimer,
		}
	elseif name == "GetCaseOdds" then
		local Cases = require(Shared.config.Cases)
		local CaseRoller = require(Shared.logic.CaseRoller)
		local odds = CaseRoller.odds(Cases.byId[arg], 3)
		return {
			ok = true,
			tier = arg,
			entries = odds.entries,
			grades = odds.grades,
			pity = { minGrade = "Rare", threshold = 10, active = odds.pityActive, remaining = odds.opensUntilPity },
		}
	elseif name == "GetShop" then
		local passes, products = {}, {}
		for _, p in Monetization.passes do
			table.insert(passes, {
				key = p.key,
				displayName = p.displayName,
				description = p.description,
				available = true,
				owned = p.key == "VIP",
				price = p.suggestedPrice,
			})
		end
		for _, p in Monetization.products do
			table.insert(products, {
				key = p.key,
				displayName = p.displayName,
				description = p.description,
				available = p.key ~= "CoinsLarge",
				price = p.suggestedPrice,
			})
		end
		return { ok = true, passes = passes, products = products }
	end
	return { ok = true, boards = {} }
end

local client = tree.StarterPlayer.Client
local ClientState = require(client.ClientState)
ClientState.init()

local ORDER = {
	"SoundController",
	"UIController",
	"NotificationController",
	"HudController",
	"WorldFxController",
	"AtmosphereController",
	"FarmController",
	"ShopController",
	"CaseController",
	"InventoryController",
	"IndexController",
	"QuestController",
	"TradeController",
	"TutorialController",
	"EventController",
	"LeaderboardController",
}
local controllers = {}
for _, name in ORDER do
	check("require " .. name, function()
		controllers[name] = require(client.controllers[name])
	end)
end
for _, name in ORDER do
	local c = controllers[name]
	if c and c.Init then
		check(name .. ":Init", function()
			c:Init()
		end)
	end
end
for _, name in ORDER do
	local c = controllers[name]
	if c and c.Start then
		check(name .. ":Start", function()
			c:Start()
		end)
	end
end

local now = os.time()
local function creature(n, species, mutations, locked)
	return {
		id = string.format("00000000-0000-0000-0000-%012d", n),
		species = species,
		rarity = Creatures.byId[species].rarity,
		mutations = mutations,
		size = 1.05,
		obtainedAt = now - n,
		source = "hatch",
		locked = locked,
	}
end
local creatures = {}
for i, spec in
	{
		{ "puffpaw", { "Shiny" } },
		{ "voltkit", { "Frozen", "Electric" }, true },
		{ "solmane", {} },
		{ "nimbuswhale", { "Rainbow", "Giant", "Cosmic" } },
		{ "mossnib", {} },
	}
do
	local c = creature(i, spec[1], spec[2], spec[3])
	creatures[c.id] = c
end
local firstId = creature(1, "puffpaw", {}).id
local quests = { dayKey = -1, daily = {}, rerollsUsed = 0, weekKey = -1, weekly = {} }
QuestLogic.refresh(quests, 1, now, 2)
quests.daily[1].progress = quests.daily[1].target

check("full Sync payload applies", function()
	handlers.Sync({
		full = true,
		serverTime = now,
		creatures = creatures,
		state = {
			coins = 12345,
			inventoryNests = { starter = 1, meadow = 3, skyheart = 1 },
			mutagens = { Shiny = 2, Golden = 1 },
			cases = { keys = { sprout = 2, moon = 0, star = 1 }, pity = { sprout = 3, moon = 0, star = 0 }, opened = 5 },
			nests = { ["1"] = { nestId = "meadow", progress = 10, required = 30, lastUpdate = now, cheers = {} } },
			habitats = { ["1"] = firstId },
			upgrades = { nestSlots = 1, habitatSlots = 0, growthSpeed = 2, luck = 5, backpack = 0 },
			index = { species = { puffpaw = { at = now, mutations = { Shiny = true } } }, claimed = {} },
			pity = NO_PITY,
			boosts = { luckUntil = now + 300, growthUntil = 0 },
			daily = { lastClaimDay = -1, cycleDay = 2 },
			quests = quests,
			tutorial = { step = 1, done = false, stepId = "plant" },
			settings = { sfx = true, music = true },
			stats = {
				hatched = 30,
				coinsEarned = 5000,
				sold = 3,
				donated = 0,
				cheersGiven = 0,
				trades = 0,
				playSeconds = 0,
				firstJoin = now,
				lastJoin = now,
				sessions = 1,
			},
			limits = { nestSlots = 4, habitatSlots = 2, backpack = 50 },
			passes = { DoubleCoins = true },
			modifiers = {
				coinMultiplier = 2,
				coinBonus = 0.1,
				growthMultiplier = 1.2,
				luckMultiplier = 1.25,
				mutationMultiplier = 1,
				activeSeasons = {},
				sources = { { label = "Blizzard", untilTime = now + 90 } },
			},
			incomeRate = 2.5,
			growthRate = 1.2,
			plot = {
				index = 1,
				center = roblox.Vector3.new(120, 0, 0),
				beds = { roblox.Vector3.new(110, 1, -12) },
				pads = { roblox.Vector3.new(110, 1, 14) },
			},
		},
	})
	handlers.WorldState({
		skyheart = { progress = 40, target = 60, bloomUntil = now + 100, round = 2, contributors = 2 },
		weather = { id = "blizzard", state = "active", startsAt = now - 10, endsAt = now + 120 },
		seasons = {
			{
				id = "harvest_festival_2026",
				displayName = "Harvest Festival",
				description = "x",
				endsAt = now + 86400,
				color = { 255, 150, 40 },
			},
		},
		leaderboards = { coins = { { userId = 1, name = "Tester", value = 5000 } }, index = {} },
	})
end)

local UIController = controllers.UIController
local panels = {
	{ "Inventory" },
	{ "Critter", firstId },
	{ "Market" },
	{ "Shop" },
	{ "Odds", "crystal" },
	{ "Odds", "starter" },
	{ "Odds", "grove", true },
	{ "Cases" },
	{ "Cases", "Shiny" },
	{ "CaseOdds", "sprout" },
	{ "CaseOdds", "star" },
	{ "Upgrades" },
	{ "Store" },
	{ "Index" },
	{ "Quests" },
	{ "Daily" },
	{ "Skyheart" },
	{ "Trade" },
	{ "Plant", 2 },
	{ "Habitat", 1 },
	{ "Habitat", 2 },
	{ "Notice", "Hello" },
	{ "Settings" },
}
for _, spec in panels do
	check("panel " .. spec[1], function()
		local before = #warnings
		UIController:open(table.unpack(spec))
		UIController:refresh(spec[1])
		luneTask.wait() -- let async builders (odds/store) run
		UIController:close()
		if #warnings > before then
			error(table.concat(warnings, "\n", before + 1))
		end
	end)
end

check("picker", function()
	local before = #warnings
	controllers.InventoryController:pick({
		title = "Pick",
		multi = true,
		max = 3,
		filter = function()
			return true, "ok"
		end,
	}, function() end)
	UIController:close()
	assert(#warnings == before, table.concat(warnings, "\n", before + 1))
end)

check("trade window states", function()
	local before = #warnings
	local c = creatures[firstId]
	local offer = { creatures = { { creature = c, value = 25 } }, coins = 10, totalValue = 35 }
	for _, s in { "open", "locked", "confirming", "executing" } do
		handlers.TradeState({
			tradeId = "T",
			state = s,
			version = 3,
			lockUntil = now + 4,
			me = { offer = offer, ready = s ~= "open", confirmed = false },
			them = { userId = 2, name = "Friend", offer = offer, ready = true, confirmed = s == "confirming" },
		})
	end
	handlers.TradeState({
		tradeId = "T",
		state = "cancelled",
		reason = "test",
		version = 3,
		lockUntil = 0,
		me = { offer = offer },
		them = { offer = offer, name = "Friend" },
	})
	handlers.TradeIncoming({ requestId = "R", fromUserId = 2, fromName = "Friend", expiresAt = now + 30 })
	assert(#warnings == before, table.concat(warnings, "\n", before + 1))
end)

check("notifications and celebrations", function()
	local before = #warnings
	handlers.Notify({ kind = "reward", text = "Hi", icon = "coins" })
	handlers.Notify({ kind = "error", text = "Nope" })
	handlers.HatchResult({
		creature = creatures[firstId],
		value = 30,
		celebrate = 2,
		newSpecies = true,
		pityTriggered = "Rare",
	})
	handlers.HatchResult({ creature = creatures[firstId], value = 30, celebrate = 0 })
	handlers.Announce({
		kind = "hatch",
		playerName = "A",
		species = "solmane",
		rarity = "Legendary",
		mutations = { "Shiny" },
	})
	handlers.Announce({ kind = "bloom", source = "purchase", playerName = "B" })
	handlers.Announce({ kind = "weather", id = "eclipse" })
	assert(#warnings == before, table.concat(warnings, "\n", before + 1))
end)

for _, stepId in { "plant", "hatch", "habitat", "reward", "buy", "plant2" } do
	check("tutorial step " .. stepId, function()
		handlers.Sync({ full = false, state = { tutorial = { step = 1, done = false, stepId = stepId } } })
	end)
end

-------------------------------------------------------------------------------

print(string.format("Smoke checks: %d run, %d failed", checks, #failures))
for _, failure in failures do
	print("FAIL " .. failure)
end
process.exit(if #failures > 0 then 1 else 0)

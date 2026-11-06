--!strict
-- Owns player profiles: session-locked load, migrations, load/release hooks,
-- autosave, save-on-leave and BindToClose.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DataConfig = require(Shared.config.Data)
local Net = require(Shared.net.Net)
local Signal = require(Shared.util.Signal)
local Types = require(Shared.Types)

local dataFolder = script.Parent.Parent.data
local DataStoreAdapter = require(dataFolder.DataStoreAdapter)
local Migrations = require(dataFolder.Migrations)
local MockDataStore = require(dataFolder.MockDataStore)
local ProfileTemplate = require(dataFolder.ProfileTemplate)
local SessionStore = require(dataFolder.SessionStore)

type Hook = (player: Player, profile: SessionStore.Profile) -> boolean?

local DataService = {
	-- (player, data: Profile) fired once the profile is ready for gameplay
	profileLoaded = Signal.new(),
	usingMock = false,
}

local store: SessionStore.SessionStore
local profiles: { [Player]: SessionStore.Profile } = {}
local releasing: { [string]: boolean } = {}
local closing: { [Player]: boolean } = {}
local loadHooks: { { name: string, fn: Hook } } = {}
local releaseHooks: { { name: string, fn: (player: Player, data: Types.Profile) -> () } } = {}

local function log(level: string, message: string)
	if level == "error" or level == "warn" then
		warn("[DataService] " .. message)
	elseif RunService:IsStudio() then
		print("[DataService] " .. message)
	end
end

-- Returns a StoreAdapter for `storeName`, falling back to memory in Studio when the
-- DataStore API is unavailable (unpublished place / API access disabled).
function DataService.createAdapter(storeName: string): Types.StoreAdapter
	local ok, adapterOrErr = pcall(DataStoreAdapter.new, storeName)
	if ok then
		if not RunService:IsStudio() then
			return adapterOrErr :: any
		end
		local probeOk, probeErr = (adapterOrErr :: any):get("__probe")
		if probeOk then
			return adapterOrErr :: any
		end
		log("warn", "DataStore probe failed in Studio: " .. tostring(probeErr))
	else
		log("warn", "GetDataStore failed: " .. tostring(adapterOrErr))
	end
	if RunService:IsStudio() and DataConfig.useMockInStudioWhenUnavailable then
		DataService.usingMock = true
		log("warn", "USING IN-MEMORY MOCK DATASTORE for " .. storeName .. " (progress will NOT persist)")
		return MockDataStore.new() :: any
	end
	error("DataStore unavailable: " .. tostring(adapterOrErr))
end

function DataService:Init()
	store = SessionStore.new({
		adapter = DataService.createAdapter(DataConfig.profileStoreName),
		makeSessionId = function()
			return game.JobId .. ":" .. HttpService:GenerateGUID(false)
		end,
		now = os.time,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		createData = function()
			return ProfileTemplate.create() :: any
		end,
		lockStaleSeconds = DataConfig.lockStaleSeconds,
		loadAttempts = DataConfig.loadAttempts,
		loadRetryDelay = DataConfig.loadRetryDelaySeconds,
		saveAttempts = DataConfig.saveAttempts,
		backoffBase = DataConfig.saveBackoffBaseSeconds,
		log = log,
	})

	Net.Server.setGate(function(player: Player): boolean
		return profiles[player] ~= nil and not closing[player]
	end)
end

-- Load hooks run after migration and before gameplay. Returning false aborts the
-- load (player is kicked, nothing is saved). Used by the trade journal roll-forward.
function DataService:addLoadHook(name: string, fn: Hook)
	table.insert(loadHooks, { name = name, fn = fn })
end

-- Release hooks run synchronously right before the final save (finalise accruals,
-- cancel trades). They must not yield for long.
function DataService:addReleaseHook(name: string, fn: (player: Player, data: Types.Profile) -> ())
	table.insert(releaseHooks, { name = name, fn = fn })
end

function DataService:get(player: Player): Types.Profile?
	local profile = profiles[player]
	if profile and profile:isActive() then
		return profile.data :: any
	end
	return nil
end

function DataService:isLoaded(player: Player): boolean
	return self:get(player) ~= nil
end

function DataService:getLoadedPlayers(): { Player }
	local list = {}
	for player, profile in profiles do
		if profile:isActive() then
			table.insert(list, player)
		end
	end
	return list
end

-- Forces an immediate save (after purchases and trades). Yields.
function DataService:saveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local ok = profile:save()
	return ok
end

local function kick(player: Player, message: string)
	if player.Parent ~= nil then
		player:Kick(message)
	end
end

local function onPlayerAdded(player: Player)
	local key = DataConfig.keyPrefix .. tostring(player.UserId)

	-- Same-server rejoin: wait for the previous session's release to finish.
	local waited = 0
	while releasing[key] and waited < 30 do
		waited += task.wait(0.25)
	end

	local profile, err = store:load(key)
	if not profile then
		log("warn", string.format("Could not load %s: %s", key, tostring(err)))
		if err == "locked" then
			kick(player, "Your data is still being saved on another server. Please rejoin in a minute.")
		else
			kick(player, "Roblox data services are having trouble. Please rejoin shortly - your progress is safe.")
		end
		return
	end

	if player.Parent == nil then
		profile:release()
		return
	end

	local migrated, result =
		Migrations.run(profile.data, ProfileTemplate.create() :: any, ProfileTemplate.CURRENT_VERSION)
	if result ~= "ok" or not migrated then
		log("error", string.format("Migration of %s returned %s", key, result))
		profile:releaseWithoutSaving()
		if result == "future" then
			kick(player, "This server is outdated. Please rejoin to get a new server.")
		else
			kick(player, "We could not read your save. It has NOT been changed. Please contact support.")
		end
		return
	end
	profile.data = migrated

	for _, hook in loadHooks do
		local ok, hookResult = pcall(hook.fn, player, profile)
		if not ok or hookResult == false then
			log("error", string.format("Load hook %s failed for %s: %s", hook.name, key, tostring(hookResult)))
			profile:releaseWithoutSaving()
			kick(player, "Your data is being verified. Please rejoin in a moment.")
			return
		end
	end

	local data = profile.data :: any
	local now = os.time()
	if data.stats.firstJoin == 0 then
		data.stats.firstJoin = now
	end
	data.stats.lastJoin = now
	data.stats.sessions += 1

	profile.onLost = function()
		profiles[player] = nil
		kick(player, "Your data was opened on another server. Please rejoin.")
	end

	if player.Parent == nil then
		profile:release()
		return
	end

	profiles[player] = profile
	DataService.profileLoaded:Fire(player, profile.data)
end

local function releasePlayer(player: Player)
	local profile = profiles[player]
	if not profile or closing[player] then
		return
	end
	if not profile:isActive() then
		profiles[player] = nil
		return
	end
	closing[player] = true -- remotes are rejected from now on
	for _, hook in releaseHooks do
		local ok, err = pcall(hook.fn, player, profile.data :: any)
		if not ok then
			log("error", string.format("Release hook %s failed: %s", hook.name, tostring(err)))
		end
	end
	profiles[player] = nil
	closing[player] = nil
	releasing[profile.key] = true
	local ok = profile:release()
	releasing[profile.key] = nil
	if not ok then
		log("error", "Final save failed for " .. profile.key)
	end
end

function DataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(releasePlayer)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				releasePlayer(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < DataConfig.bindToCloseBudgetSeconds do
			task.wait(0.1)
		end
		if pending > 0 then
			log("error", string.format("BindToClose: %d profiles did not finish saving", pending))
		end
	end)

	-- Autosave: each profile saves when its last save is older than the interval.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.time()
			for player, profile in profiles do
				if profile:isActive() and now - profile.lastSavedAt >= DataConfig.autosaveSeconds then
					profile.lastSavedAt = now -- prevents double scheduling while saving
					task.spawn(function()
						local ok = profile:save()
						if not ok and profile:isActive() then
							log("warn", "Autosave failed for " .. player.Name .. "; will retry next cycle")
						end
					end)
				end
			end
		end
	end)
end

return DataService

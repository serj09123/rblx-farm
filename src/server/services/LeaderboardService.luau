--!strict
-- Global leaderboards on OrderedDataStores. Writes are periodic and on leave;
-- reads are cached and pushed to clients. All calls are pcall-wrapped and
-- budget-aware; in Studio without API access the boards stay empty.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Leaderboards = require(Shared.config.Leaderboards)
local Net = require(Shared.net.Net)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local IndexService = require(script.Parent.IndexService)

local LeaderboardService = {}

local stores: { [string]: OrderedDataStore } = {}
local cache: { [string]: { { name: string, value: number, userId: number } } } = {}
local names: { [number]: string } = {}
local lastWrite: { [Player]: number } = {}
local enabled = true

local function statValue(boardStat: string, data: Types.Profile): number
	if boardStat == "coinsEarned" then
		return math.floor(data.stats.coinsEarned)
	elseif boardStat == "indexEntries" then
		return IndexService:entries(data)
	end
	return 0
end

local function hasBudget(requestType: Enum.DataStoreRequestType): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)
	return ok and budget > 1
end

local function write(player: Player)
	local data = DataService:get(player)
	if not data or not enabled then
		return
	end
	lastWrite[player] = os.time()
	for _, board in Leaderboards.boards do
		local store = stores[board.id]
		if store and hasBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync) then
			local value = statValue(board.stat, data)
			local ok, err = pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
			if not ok then
				warn("[LeaderboardService] write failed: " .. tostring(err))
			end
		end
	end
end

local function nameFor(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else "Rancher"
	names[userId] = result
	return result
end

local function refresh()
	if not enabled then
		return
	end
	for _, board in Leaderboards.boards do
		local store = stores[board.id]
		if not store or not hasBudget(Enum.DataStoreRequestType.GetSortedAsync) then
			continue
		end
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, Leaderboards.topCount)
		end)
		if not ok then
			warn("[LeaderboardService] read failed: " .. tostring(pages))
			continue
		end
		local entries = {}
		for _, item in (pages :: DataStorePages):GetCurrentPage() do
			local userId = tonumber(item.key)
			if userId then
				table.insert(entries, { userId = userId, name = nameFor(userId), value = item.value })
			end
		end
		cache[board.id] = entries
	end
	Net.Server.fireAll("WorldState", { leaderboards = cache })
end

function LeaderboardService:Init()
	Net.Server.handle("GetLeaderboards", function()
		return { ok = true, boards = cache }
	end)
	if DataService.usingMock then
		enabled = false
		return
	end
	for _, board in Leaderboards.boards do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.storeName)
		end)
		if ok then
			stores[board.id] = store
		else
			enabled = false
		end
	end
end

function LeaderboardService:PlayerReady(player: Player)
	Net.Server.fire(player, "WorldState", { leaderboards = cache })
end

function LeaderboardService:Start()
	if not enabled then
		return
	end
	-- Final write happens before the profile is released.
	DataService:addReleaseHook("leaderboard", function(player: Player)
		task.spawn(write, player)
		lastWrite[player] = nil
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(Leaderboards.refreshSeconds)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(30)
			local now = os.time()
			for _, player in DataService:getLoadedPlayers() do
				if now - (lastWrite[player] or 0) >= Leaderboards.writeEverySeconds then
					task.spawn(write, player)
				end
			end
		end
	end)
end

return LeaderboardService

--!strict
-- Collection index: discovered species and species x mutation entries, milestone rewards.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local IndexConfig = require(Shared.config.Index)
local Net = require(Shared.net.Net)
local Types = require(Shared.Types)

local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local SyncService = require(script.Parent.SyncService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local IndexService = {}

local milestoneById: { [string]: IndexConfig.Milestone } = {}
for _, m in IndexConfig.milestones do
	milestoneById[m.id] = m
end

function IndexService:entries(data: Types.Profile): number
	local total = 0
	for _, entry in data.index.species do
		total += 1
		for _ in entry.mutations do
			total += 1
		end
	end
	return total
end

local function setLeaderstat(player: Player, value: number)
	local stats = player:FindFirstChild("leaderstats")
	local stat = stats and stats:FindFirstChild("Index")
	if stat and stat:IsA("IntValue") then
		stat.Value = value
	end
end

-- Records a creature in the index; returns number of new entries.
function IndexService:record(player: Player, creature: Types.Creature): number
	local data = DataService:get(player)
	if not data then
		return 0
	end
	local added = 0
	local entry = data.index.species[creature.species]
	if not entry then
		entry = { at = os.time(), mutations = {} }
		data.index.species[creature.species] = entry
		added += 1
	end
	for _, mutation in creature.mutations do
		if not entry.mutations[mutation] then
			entry.mutations[mutation] = true
			added += 1
		end
	end
	if added > 0 then
		SyncService:markDirty(player, "index")
		setLeaderstat(player, self:entries(data))
		ServerEvents.indexDiscovered:Fire(player, added)
	end
	return added
end

local function onClaim(player: Player, milestoneId: string)
	local data = DataService:get(player)
	local milestone = milestoneById[milestoneId]
	if not data or not milestone or data.index.claimed[milestoneId] then
		return
	end
	if IndexService:entries(data) < milestone.entries then
		return
	end
	data.index.claimed[milestoneId] = true
	local summary = RewardService:grant(player, milestone.reward, "index_" .. milestoneId, "Gameplay")
	SyncService:markDirty(player, "index")
	Notifier.send(player, "reward", "Index reward! " .. RewardService:describe(summary), "index")
end

function IndexService:Init()
	Net.Server.on("ClaimIndexMilestone", onClaim)
end

function IndexService:PlayerReady(player: Player, data: Types.Profile)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local stat = Instance.new("IntValue")
		stat.Name = "Index"
		stat.Value = self:entries(data)
		stat.Parent = stats
	end
end

function IndexService:Start()
	ServerEvents.creatureObtained:Connect(function(player: Player, creature: Types.Creature)
		if player.Parent ~= Players then
			return
		end
		IndexService:record(player, creature)
	end)
end

return IndexService

--!strict
-- Cross-server announcements for the rarest hatches (rarities with announceGlobal).
-- MessagingService is best-effort: every call is pcall'd, publishing is rate limited
-- per server, and the receiving side validates the payload before showing anything.

local MessagingService = game:GetService("MessagingService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Creatures = require(Shared.config.Creatures)
local Rarities = require(Shared.config.Rarities)

local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local GlobalAnnounceService = {}

local TOPIC = "SkyheartGlobalHatch"
local MIN_SECONDS_BETWEEN_PUBLISH = 10 -- per server
local MAX_RECEIVED_PER_MINUTE = 6 -- per server, protects players from spam

local lastPublish = 0
local receivedTimes: { number } = {}

local function canReceive(now: number): boolean
	while #receivedTimes > 0 and now - receivedTimes[1] > 60 do
		table.remove(receivedTimes, 1)
	end
	if #receivedTimes >= MAX_RECEIVED_PER_MINUTE then
		return false
	end
	table.insert(receivedTimes, now)
	return true
end

local function onMessage(message: any)
	local data = message and message.Data
	if type(data) ~= "table" or data.job == game.JobId then
		return
	end
	local rarity = if type(data.rarity) == "string" then Rarities.byId[data.rarity] else nil
	if
		not rarity
		or not rarity.announceGlobal
		or type(data.species) ~= "string"
		or not Creatures.byId[data.species]
		or type(data.playerName) ~= "string"
		or #data.playerName > 50
	then
		return
	end
	if not canReceive(os.clock()) then
		return
	end
	Notifier.announce({
		kind = "hatch",
		playerName = data.playerName,
		species = data.species,
		rarity = data.rarity,
		mutations = {},
		otherServer = true,
	})
end

function GlobalAnnounceService:Start()
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, onMessage)
		end)
		if not ok then
			warn("[GlobalAnnounceService] Subscribe failed (cross-server announcements off): " .. tostring(err))
		end
	end)

	ServerEvents.hatched:Connect(function(player: Player, creature: any)
		local rarity = Rarities.byId[creature.rarity]
		if not rarity or not rarity.announceGlobal then
			return
		end
		local now = os.clock()
		if now - lastPublish < MIN_SECONDS_BETWEEN_PUBLISH then
			return
		end
		lastPublish = now
		task.spawn(function()
			local ok, err = pcall(function()
				MessagingService:PublishAsync(TOPIC, {
					job = game.JobId,
					playerName = player.DisplayName,
					species = creature.species,
					rarity = creature.rarity,
				})
			end)
			if not ok then
				warn("[GlobalAnnounceService] Publish failed: " .. tostring(err))
			end
		end)
	end)
end

return GlobalAnnounceService

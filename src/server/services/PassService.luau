--!strict
-- Game pass ownership. Source of truth is UserOwnsGamePassAsync at join; purchases
-- made during the session are granted from PromptGamePassPurchaseFinished.
-- The profile keeps a record that is used only when the ownership API is down.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Monetization = require(Shared.config.Monetization)
local Signal = require(Shared.util.Signal)
local Types = require(Shared.Types)

local SyncService = require(script.Parent.SyncService)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local PassService = {
	-- (player, passKey)
	passGranted = Signal.new(),
}

local owned: { [Player]: { [string]: boolean } } = {}

local function ownedFor(player: Player): { [string]: boolean }
	local map = owned[player]
	if not map then
		map = {}
		owned[player] = map
	end
	return map
end

function PassService:owns(player: Player, key: string): boolean
	local map = owned[player]
	return map ~= nil and map[key] == true
end

local function grant(player: Player, key: string)
	local map = ownedFor(player)
	if map[key] then
		return
	end
	map[key] = true
	SyncService:markDirty(player, "passes", "limits")
	PassService.passGranted:Fire(player, key)
end

function PassService:Init()
	SyncService:registerProvider("passes", function(player: Player)
		return table.clone(ownedFor(player))
	end)
end

function PassService:PlayerReady(player: Player, data: Types.Profile)
	local map = ownedFor(player)
	for _, def in Monetization.passes do
		if def.id == 0 then
			continue
		end
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.id)
		end)
		if ok then
			map[def.key] = result == true
			if result == true then
				data.purchases.passes[def.key] = true -- confirmed record
			end
		else
			-- API unavailable: fall back to the confirmed record from a past session.
			map[def.key] = data.purchases.passes[def.key] == true
		end
	end
end

function PassService:Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if not purchased then
				return
			end
			local def = Monetization.passById[passId]
			if not def then
				return
			end
			-- Granted for this session; the persistent record is only written once
			-- UserOwnsGamePassAsync confirms ownership on a later join.
			grant(player, def.key)
			ServerEvents.purchased:Fire(player, "pass", def.key)
		end
	)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
end

return PassService

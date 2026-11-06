--!strict
-- Persists simple player settings (sound effects, music).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.net.Net)

local DataService = require(script.Parent.DataService)
local SyncService = require(script.Parent.SyncService)

local SettingsService = {}

function SettingsService:Init()
	Net.Server.on("SetSetting", function(player: Player, key: string, value: boolean)
		local data = DataService:get(player)
		if not data then
			return
		end
		-- Remotes.luau already restricts `key` to known settings and `value` to booleans.
		(data.settings :: any)[key] = value
		SyncService:markDirty(player, "settings")
	end)
end

return SettingsService

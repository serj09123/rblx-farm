--!strict
-- Server entry point. Services are plain modules with optional lifecycle methods:
--   Init()                     -- wire dependencies, register remotes (no yielding)
--   Start()                    -- start loops / connect events
--   PlayerReady(player, data)  -- profile loaded; runs in list order before the first Sync
-- Order matters: a service may only depend on services listed before it.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.net.Net)

local servicesFolder = script.services

local ORDER = {
	"DataService",
	"SyncService",
	"Analytics",
	"PolicyCache",
	"PassService",
	"ModifierService",
	"EconomyService",
	"InventoryService",
	"RewardService",
	"WorldService",
	"PlotService",
	"FarmService",
	"MarketService",
	"UpgradeService",
	"IndexService",
	"WeatherService",
	"SkyheartService",
	"CheerService",
	"TradeService",
	"QuestService",
	"DailyRewardService",
	"SettingsService",
	"TutorialService",
	"LeaderboardService",
	"MonetizationService",
}

type Service = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	PlayerReady: ((self: any, player: Player, data: any) -> ())?,
}

local services: { { name: string, module: Service } } = {}
for _, name in ORDER do
	local moduleScript = servicesFolder:FindFirstChild(name)
	if moduleScript then
		table.insert(services, { name = name, module = require(moduleScript) :: any })
	end
end

Net.Server.init()

for _, entry in services do
	if entry.module.Init then
		local ok, err = pcall(entry.module.Init, entry.module)
		if not ok then
			warn(string.format("[Server] %s:Init failed: %s", entry.name, tostring(err)))
		end
	end
end

local DataService = require(servicesFolder.DataService) :: any
local SyncService = require(servicesFolder.SyncService) :: any

DataService.profileLoaded:Connect(function(player: Player, data: any)
	for _, entry in services do
		local ready = entry.module.PlayerReady
		if ready then
			local ok, err = pcall(ready, entry.module, player, data)
			if not ok then
				warn(
					string.format("[Server] %s:PlayerReady failed for %d: %s", entry.name, player.UserId, tostring(err))
				)
			end
		end
	end
	SyncService:sendFull(player)
end)

-- DataService starts last so every other service is listening before profiles load.
for _, entry in services do
	if entry.module.Start and entry.name ~= "DataService" then
		local ok, err = pcall(entry.module.Start, entry.module)
		if not ok then
			warn(string.format("[Server] %s:Start failed: %s", entry.name, tostring(err)))
		end
	end
end
DataService:Start()

print("[Server] Skyheart Ranch started")

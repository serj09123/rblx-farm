--!strict
-- Client entry point. Controllers render state and send intents; they never decide
-- outcomes. Same lifecycle as server services: Init() then Start().

local ClientState = require(script.ClientState)

local controllersFolder = script.controllers

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

ClientState.init()

local controllers = {}
for _, name in ORDER do
	local moduleScript = controllersFolder:FindFirstChild(name)
	if moduleScript then
		table.insert(controllers, { name = name, module = require(moduleScript) :: any })
	end
end

for _, entry in controllers do
	if entry.module.Init then
		local ok, err = pcall(entry.module.Init, entry.module)
		if not ok then
			warn(string.format("[Client] %s:Init failed: %s", entry.name, tostring(err)))
		end
	end
end

for _, entry in controllers do
	if entry.module.Start then
		local ok, err = pcall(entry.module.Start, entry.module)
		if not ok then
			warn(string.format("[Client] %s:Start failed: %s", entry.name, tostring(err)))
		end
	end
end

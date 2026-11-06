--!strict
-- Coin upgrades: nest beds, habitats, growth speed, luck, backpack.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.net.Net)
local Progression = require(Shared.logic.Progression)
local Upgrades = require(Shared.config.Upgrades)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ModifierService = require(script.Parent.ModifierService)
local PlotService = require(script.Parent.PlotService)
local SyncService = require(script.Parent.SyncService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local UpgradeService = {}

local function onBuy(player: Player, upgradeId: string)
	local data = DataService:get(player)
	local def = Upgrades.byId[upgradeId]
	if not data or not def then
		return
	end
	local level = Progression.level(data.upgrades, upgradeId)
	local cost = Progression.nextCost(upgradeId, level)
	if not cost then
		Notifier.error(player, "Max level")
		return
	end
	if not EconomyService:spend(player, cost, "upgrade_" .. upgradeId, "Shop") then
		Notifier.error(player, "Not enough coins")
		return
	end
	data.upgrades[upgradeId] = level + 1
	SyncService:markDirty(player, "upgrades", "limits", "modifiers", "growthRate")
	if upgradeId == "nestSlots" or upgradeId == "habitatSlots" then
		PlotService:refreshAll(player)
	elseif upgradeId == "growthSpeed" or upgradeId == "luck" then
		ModifierService.changed:Fire()
	end
	ServerEvents.upgraded:Fire(player, upgradeId, level + 1)
	Notifier.send(player, "success", def.displayName .. " Lv." .. (level + 1), "upgrade")
end

function UpgradeService:Init()
	Net.Server.on("BuyUpgrade", onBuy)
end

return UpgradeService

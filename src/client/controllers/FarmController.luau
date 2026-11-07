--!strict
-- Nest bed and habitat pad interactions on your own ranch.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Format = require(Shared.util.Format)
local Nests = require(Shared.config.Nests)
local Net = require(Shared.net.Net)

local ClientState = require(script.Parent.Parent.ClientState)
local CreatureCard = require(script.Parent.Parent.ui.CreatureCard)
local InventoryController = require(script.Parent.InventoryController)
local UIController = require(script.Parent.UIController)
local Icons = require(Shared.config.Icons)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local FarmController = {}

local function buildPlant(content: Frame, slot: number)
	local owned = ClientState.get("inventoryNests") or {}
	local list = UI.scroll({ Parent = content })
	UI.list(Enum.FillDirection.Vertical, 8).Parent = list
	local any = false
	for order, def in Nests.list do
		local count = owned[def.id]
		if count and count > 0 then
			any = true
			local button = UI.button(
				string.format(
					"%s %s  x%d  ·  %s",
					Icons.nestIcon(def.id),
					def.displayName,
					count,
					Format.duration(def.growSeconds)
				),
				Theme.rgb(def.color):Lerp(Theme.colors.panelLight, 0.35),
				function()
					Net.Client.fire("PlantNest", slot, def.id)
					UIController:close()
				end,
				{ Size = UDim2.new(1, -16, 0, Theme.touch), LayoutOrder = order, Parent = list }
			)
			if def.id == "starter" or def.id == "meadow" then
				UIController:registerElement("PlantOption", button)
			end
		end
	end
	if not any then
		UI.label("You have no nests.", { Size = UDim2.new(1, 0, 0, 40), Parent = list })
		UI.button(Assets.icons.shop .. " Buy nests", Theme.colors.good, function()
			UIController:open("Shop")
		end, { Size = UDim2.fromOffset(240, Theme.touch), Parent = list })
	end
end

local function buildPad(content: Frame, slot: number)
	local habitats = ClientState.get("habitats") or {}
	local creatureId = habitats[tostring(slot)]
	local creature = if creatureId then ClientState.creature(creatureId) else nil
	if creature then
		local card = CreatureCard.create(creature)
		card.Position = UDim2.fromOffset(10, 10)
		card.Parent = content
	end
	local column = UI.new("Frame", {
		Position = UDim2.fromOffset(160, 10),
		Size = UDim2.new(1, -170, 1, -20),
		BackgroundTransparency = 1,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 10) })
	UI.button(
		Assets.icons.habitat .. (if creature then " Swap critter" else " Choose critter"),
		Theme.colors.good,
		function()
			InventoryController:pick({
				title = "Place a critter",
				filter = function(c)
					if c.id == creatureId then
						return false, "Here"
					end
					if InventoryController.isReservedForTrade(c.id) then
						return false, "In trade"
					end
					return true, nil
				end,
			}, function(ids)
				Net.Client.fire("PlaceHabitat", slot, ids[1])
			end)
		end,
		{ Size = UDim2.new(1, 0, 0, Theme.touch), Parent = column }
	)
	if creature then
		UI.button("Remove", Theme.colors.bad, function()
			Net.Client.fire("ClearHabitat", slot)
			UIController:close()
		end, { Size = UDim2.new(1, 0, 0, Theme.touch), Parent = column })
	end
end

function FarmController:openPlant(slot: number)
	UIController:open("Plant", slot)
end

function FarmController:openPad(slot: number)
	UIController:open("Habitat", slot)
end

function FarmController:hatch(slot: number)
	Net.Client.fire("HatchNest", slot)
end

function FarmController:Init()
	UIController:registerPanel(
		"Plant",
		{ title = "Plant a nest", icon = Assets.icons.nest, size = Vector2.new(480, 380), build = buildPlant }
	)
	UIController:registerPanel(
		"Habitat",
		{ title = "Habitat", icon = Assets.icons.habitat, size = Vector2.new(480, 300), build = buildPad }
	)
end

function FarmController:Start()
	ClientState.observe("inventoryNests", function()
		local panel = UIController:currentPanel()
		if panel == "Plant" then
			UIController:close()
		end
	end)
end

return FarmController

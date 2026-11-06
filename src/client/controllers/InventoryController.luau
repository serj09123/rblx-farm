--!strict
-- Critter inventory, critter details, the Market (multi-sell) and a generic picker
-- used by habitats, trading and donations.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Creatures = require(Shared.config.Creatures)
local Format = require(Shared.util.Format)
local Net = require(Shared.net.Net)
local Rarities = require(Shared.config.Rarities)
local Types = require(Shared.Types)
local Valuation = require(Shared.logic.Valuation)
local Economy = require(Shared.config.Economy)

local ClientState = require(script.Parent.Parent.ClientState)
local CreatureCard = require(script.Parent.Parent.ui.CreatureCard)
local UIController = require(script.Parent.UIController)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local InventoryController = {}

export type PickOptions = {
	title: string,
	multi: boolean?,
	max: number?,
	preselected: { string }?,
	confirmText: string?,
	filter: ((creature: Types.Creature) -> (boolean, string?))?,
}

type SortMode = "value" | "newest" | "rarity"

local sortMode: SortMode = "value"
-- Set by TradeController: returns true for critters offered in the open trade.
InventoryController.isReservedForTrade = function(_id: string): boolean
	return false
end

local function placedIds(): { [string]: boolean }
	local set = {}
	for _, id in ClientState.get("habitats") or {} do
		set[id] = true
	end
	return set
end

local function sortedCreatures(): { Types.Creature }
	local list = {}
	for _, creature in ClientState.creatures() do
		table.insert(list, creature)
	end
	table.sort(list, function(a, b)
		if sortMode == "newest" then
			return a.obtainedAt > b.obtainedAt
		elseif sortMode == "rarity" then
			local oa, ob = Rarities.order(a.rarity), Rarities.order(b.rarity)
			if oa ~= ob then
				return oa > ob
			end
		end
		return Valuation.value(a) > Valuation.value(b)
	end)
	return list
end

local function sellPrice(creature: Types.Creature): number
	local mods = ClientState.get("modifiers")
	return Valuation.sellPrice(creature, if mods then mods.coinMultiplier else 1, if mods then mods.coinBonus else 0)
end

local function essenceFor(creature: Types.Creature): number
	local rarity = Rarities.byId[creature.rarity]
	return (if rarity then rarity.essence else 1) * Economy.donateEssenceMultiplier * (1 + #creature.mutations)
end

local function headerRow(content: Frame, text: string): Frame
	local row = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Parent = content,
	})
	UI.label(text, {
		Size = UDim2.fromScale(0.5, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	return row
end

local function grid(content: Frame, top: number): ScrollingFrame
	local scroll = UI.scroll({
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		Parent = content,
	})
	UI.grid(CreatureCard.size, 8).Parent = scroll
	UI.padding(4).Parent = scroll
	return scroll
end

-- Inventory ---------------------------------------------------------------------

local function buildInventory(content: Frame)
	local limits = ClientState.get("limits")
	local count = 0
	for _ in ClientState.creatures() do
		count += 1
	end
	local row = headerRow(
		content,
		string.format("%s %d / %d", Assets.icons.inventory, count, if limits then limits.backpack else 0)
	)
	local labels = { value = "Sort: Value", newest = "Sort: New", rarity = "Sort: Rarity" }
	UI.button(labels[sortMode], Theme.colors.panelLight, function()
		sortMode = if sortMode == "value" then "newest" elseif sortMode == "newest" then "rarity" else "value"
		UIController:refresh("Inventory")
	end, { Size = UDim2.fromOffset(150, 40), Position = UDim2.new(1, -310, 0, 2), Parent = row })
	UI.button(Assets.icons.sell .. " Sell", Theme.colors.warn, function()
		UIController:open("Market")
	end, { Size = UDim2.fromOffset(140, 40), Position = UDim2.new(1, -150, 0, 2), Parent = row })

	local scroll = grid(content, 50)
	local placed = placedIds()
	if count == 0 then
		UI.label(
			"No critters yet - plant a nest! " .. Assets.icons.nest,
			{ Size = UDim2.new(1, 0, 0, 60), Parent = scroll }
		)
	end
	for order, creature in sortedCreatures() do
		local tag = if placed[creature.id]
			then Assets.icons.habitat .. " Placed"
			elseif InventoryController.isReservedForTrade(creature.id) then Assets.icons.trade .. " Trade"
			else nil
		local card = CreatureCard.create(creature, {
			tag = tag,
			onClick = function()
				UIController:open("Critter", creature.id)
			end,
		})
		card.LayoutOrder = order
		card.Parent = scroll
	end
end

local function buildCritter(content: Frame, creatureId: string)
	local creature = ClientState.creature(creatureId)
	if not creature then
		UI.label("This critter is gone.", { Parent = content })
		return
	end
	local card = CreatureCard.create(creature)
	card.Position = UDim2.fromOffset(10, 10)
	card.Parent = content

	local actions = UI.new("Frame", {
		Position = UDim2.fromOffset(160, 0),
		Size = UDim2.new(1, -160, 1, 0),
		BackgroundTransparency = 1,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Left) })

	local species = Creatures.byId[creature.species]
	UI.label(string.format("Size %.2f  ·  Value %s", creature.size, Format.number(Valuation.value(creature))), {
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.fontBody,
		Parent = actions,
	})
	local placed = placedIds()[creature.id]
	local reserved = InventoryController.isReservedForTrade(creature.id)
	local function action(text: string, color: Color3, enabled: boolean, fn: () -> ())
		local button = UI.button(text, if enabled then color else Theme.colors.disabled, if enabled then fn else nil, {
			Size = UDim2.new(1, -10, 0, 52),
			Parent = actions,
		})
		return button
	end
	action(
		if creature.locked then Assets.icons.lock .. " Unlock" else Assets.icons.lock .. " Lock (protect)",
		Theme.colors.panelLight,
		true,
		function()
			Net.Client.fire("SetLocked", creature.id, not creature.locked)
			UIController:close()
		end
	)
	action(
		Assets.icons.habitat .. (if placed then " Already placed" else " Place in habitat"),
		Theme.colors.good,
		not placed and not reserved,
		function()
			local habitats = ClientState.get("habitats") or {}
			local limits = ClientState.get("limits")
			local maxSlots = if limits then limits.habitatSlots else 2
			for slot = 1, maxSlots do
				if not habitats[tostring(slot)] then
					Net.Client.fire("PlaceHabitat", slot, creature.id)
					UIController:close()
					return
				end
			end
			UIController:open("Notice", "All habitats are full. Tap a habitat pad on your ranch to swap.")
		end
	)
	local canSell = not creature.locked and not placed and not reserved
	action(
		string.format("%s Sell for %s", Assets.icons.sell, Format.number(sellPrice(creature))),
		Theme.colors.warn,
		canSell,
		function()
			Net.Client.fire("SellCreatures", { creature.id })
			UIController:close()
		end
	)
	action(
		string.format("%s Give to Skyheart (+%d)", Assets.icons.skyheart, essenceFor(creature)),
		Theme.colors.accent,
		canSell,
		function()
			Net.Client.fire("DonateCreature", creature.id)
			UIController:close()
		end
	)
	local _ = species
end

-- Market (multi-sell) -----------------------------------------------------------

local marketSelection: { [string]: boolean } = {}

local function buildMarket(content: Frame)
	local placed = placedIds()
	local total = 0
	local selectedCount = 0
	for id in marketSelection do
		local creature = ClientState.creature(id)
		if creature then
			total += sellPrice(creature)
			selectedCount += 1
		else
			marketSelection[id] = nil
		end
	end
	local row = headerRow(
		content,
		string.format("Selected %d  ·  %s %s", selectedCount, Assets.icons.coins, Format.number(total))
	)
	UI.button("Commons", Theme.colors.panelLight, function()
		for _, creature in ClientState.creatures() do
			if
				(creature.rarity == "Common" or creature.rarity == "Uncommon")
				and not creature.locked
				and not placed[creature.id]
				and not InventoryController.isReservedForTrade(creature.id)
			then
				marketSelection[creature.id] = true
			end
		end
		UIController:refresh("Market")
	end, { Size = UDim2.fromOffset(110, 40), Position = UDim2.new(1, -370, 0, 2), Parent = row })
	UI.button("Clear", Theme.colors.panelLight, function()
		table.clear(marketSelection)
		UIController:refresh("Market")
	end, { Size = UDim2.fromOffset(90, 40), Position = UDim2.new(1, -254, 0, 2), Parent = row })
	UI.button(
		Assets.icons.sell .. " Sell",
		if selectedCount > 0 then Theme.colors.warn else Theme.colors.disabled,
		function()
			if selectedCount == 0 then
				return
			end
			local ids = {}
			for id in marketSelection do
				table.insert(ids, id)
				if #ids >= 50 then
					break
				end
			end
			Net.Client.fire("SellCreatures", ids)
			table.clear(marketSelection)
			UIController:close()
		end,
		{ Size = UDim2.fromOffset(150, 40), Position = UDim2.new(1, -156, 0, 2), Parent = row }
	)

	local scroll = grid(content, 50)
	for order, creature in sortedCreatures() do
		local blocked = creature.locked or placed[creature.id] or InventoryController.isReservedForTrade(creature.id)
		local card = CreatureCard.create(creature, {
			value = sellPrice(creature),
			selected = marketSelection[creature.id] == true,
			dimmed = blocked,
			tag = if placed[creature.id] then "Placed" elseif creature.locked then "Locked" else nil,
			onClick = if blocked
				then nil
				else function()
					marketSelection[creature.id] = if marketSelection[creature.id] then nil else true
					UIController:refresh("Market")
				end,
		})
		card.LayoutOrder = order
		card.Parent = scroll
	end
end

-- Picker ------------------------------------------------------------------------

local pickState: { options: PickOptions, selected: { string }, callback: ({ string }) -> () }? = nil

local function buildPicker(content: Frame)
	local state = pickState
	if not state then
		return
	end
	local options = state.options
	local max = options.max or (if options.multi then 50 else 1)
	local row = headerRow(content, options.title)
	if options.multi then
		UI.button(
			string.format("%s (%d)", options.confirmText or "Confirm", #state.selected),
			Theme.colors.good,
			function()
				local chosen = table.clone(state.selected)
				pickState = nil
				UIController:close()
				state.callback(chosen)
			end,
			{ Size = UDim2.fromOffset(200, 40), Position = UDim2.new(1, -200, 0, 2), Parent = row }
		)
	end
	local scroll = grid(content, 50)
	for order, creature in sortedCreatures() do
		local allowed, tag = true, nil :: string?
		if options.filter then
			allowed, tag = options.filter(creature)
		end
		local index = table.find(state.selected, creature.id)
		local card = CreatureCard.create(creature, {
			selected = index ~= nil,
			dimmed = not allowed,
			tag = tag,
			onClick = if not allowed
				then nil
				else function()
					if not options.multi then
						pickState = nil
						UIController:close()
						state.callback({ creature.id })
						return
					end
					if index then
						table.remove(state.selected, index)
					elseif #state.selected < max then
						table.insert(state.selected, creature.id)
					end
					UIController:refresh("Picker")
				end,
		})
		card.LayoutOrder = order
		card.Parent = scroll
	end
end

-- Opens the picker; `callback` receives the chosen ids.
function InventoryController:pick(options: PickOptions, callback: ({ string }) -> ())
	pickState = { options = options, selected = table.clone(options.preselected or {}), callback = callback }
	UIController:open("Picker")
end

-- Default filter: critters that can leave the inventory (not locked/placed/in trade).
function InventoryController:freeFilter(creature: Types.Creature): (boolean, string?)
	if creature.locked then
		return false, "Locked"
	end
	if placedIds()[creature.id] then
		return false, "Placed"
	end
	if InventoryController.isReservedForTrade(creature.id) then
		return false, "In trade"
	end
	return true, nil
end

function InventoryController:Init()
	UIController:registerPanel(
		"Inventory",
		{ title = "Critters", icon = Assets.icons.inventory, size = Vector2.new(720, 440), build = buildInventory }
	)
	UIController:registerPanel(
		"Critter",
		{ title = "Critter", icon = Assets.icons.hatch, size = Vector2.new(520, 360), build = buildCritter }
	)
	UIController:registerPanel(
		"Market",
		{ title = "Market", icon = Assets.icons.sell, size = Vector2.new(720, 440), build = buildMarket }
	)
	UIController:registerPanel("Picker", {
		title = "Choose",
		icon = Assets.icons.inventory,
		size = Vector2.new(720, 440),
		build = buildPicker,
		onClose = function()
			pickState = nil
		end,
	})
	UIController:registerPanel("Notice", {
		title = "Info",
		size = Vector2.new(420, 220),
		build = function(content: Frame, text: string)
			UI.label(text, { Size = UDim2.fromScale(1, 1), Parent = content })
		end,
	})
end

function InventoryController:Start()
	ClientState.creaturesChanged:Connect(function()
		UIController:refresh("Inventory")
		UIController:refresh("Market")
	end)
end

return InventoryController

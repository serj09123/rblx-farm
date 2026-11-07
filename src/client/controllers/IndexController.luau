--!strict
-- Collection index: species grid (undiscovered shown as ???) and milestone rewards.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Creatures = require(Shared.config.Creatures)
local IndexConfig = require(Shared.config.Index)
local Mutations = require(Shared.config.Mutations)
local Net = require(Shared.net.Net)
local Rarities = require(Shared.config.Rarities)

local ClientState = require(script.Parent.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local Icon = require(script.Parent.Parent.ui.Icon)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local IndexController = {}

local function entries(index: any): number
	local total = 0
	for _, entry in index.species do
		total += 1
		for _ in entry.mutations do
			total += 1
		end
	end
	return total
end

local function buildIndex(content: Frame)
	local index = ClientState.get("index") or { species = {}, claimed = {} }
	local count = entries(index)
	local maxEntries = Creatures.baseSpeciesCount * (1 + #Mutations.list)

	local list = UI.scroll({ Parent = content })
	UI.list(Enum.FillDirection.Vertical, 8).Parent = list
	UI.label(string.format("%s %d entries discovered (of %d+)", Assets.icons.index, count, maxEntries), {
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 0,
		Parent = list,
	})

	-- Milestones
	local milestones = UI.new("Frame", {
		Size = UDim2.new(1, -8, 0, 64),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = list,
	})
	local strip = UI.scroll({
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		Parent = milestones,
	})
	UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left).Parent = strip
	for order, m in IndexConfig.milestones do
		local claimed = index.claimed[m.id] == true
		local reached = count >= m.entries
		local button = UI.button(
			if claimed
				then "✓ " .. m.entries
				elseif reached then Assets.icons.gift .. " " .. m.entries
				else Assets.icons.lock .. " " .. m.entries,
			if claimed then Theme.colors.disabled elseif reached then Theme.colors.good else Theme.colors.panelLight,
			if reached and not claimed
				then function()
					Net.Client.fire("ClaimIndexMilestone", m.id)
				end
				else nil,
			{ Size = UDim2.fromOffset(110, 54), LayoutOrder = order, Parent = strip }
		)
		local _ = button
	end

	-- Species grid, grouped by rarity
	local gridFrame = UI.new("Frame", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = list,
	})
	UI.grid(Vector2.new(124, 96), 8).Parent = gridFrame
	local sorted = table.clone(Creatures.list)
	table.sort(sorted, function(a, b)
		local oa, ob = Rarities.order(a.rarity), Rarities.order(b.rarity)
		if oa ~= ob then
			return oa < ob
		end
		return a.displayName < b.displayName
	end)
	for order, species in sorted do
		local entry = index.species[species.id]
		if species.eventOnly and not entry then
			continue -- event species are only listed once discovered
		end
		local rarity = Rarities.byId[species.rarity]
		local color = if rarity then Theme.rgb(rarity.color) else Theme.colors.text
		local cell = UI.new("Frame", {
			BackgroundColor3 = if entry then Theme.colors.card else Theme.colors.panelLight,
			LayoutOrder = order,
			Parent = gridFrame,
		}, { UI.corner(12), UI.stroke(color, 2) })
		Icon.portrait(cell, species, 38, UDim2.new(0.5, -19, 0, 5), color, entry ~= nil)
		UI.label(if entry then species.displayName else "???", {
			Size = UDim2.new(1, -6, 0, 22),
			Position = UDim2.fromOffset(3, 44),
			TextColor3 = color,
			Parent = cell,
		})
		local mutationCount = 0
		if entry then
			for _ in entry.mutations do
				mutationCount += 1
			end
		end
		UI.label(
			if entry then string.format("%d mutations", mutationCount) else (if rarity then rarity.displayName else ""),
			{
				Size = UDim2.new(1, -6, 0, 20),
				Position = UDim2.fromOffset(3, 68),
				TextSize = Theme.textSize.small,
				Font = Theme.fontBody,
				TextColor3 = Theme.colors.textDim,
				Parent = cell,
			}
		)
	end
end

function IndexController:Init()
	UIController:registerPanel(
		"Index",
		{ title = "Index", icon = Assets.icons.index, size = Vector2.new(720, 440), build = buildIndex }
	)
end

function IndexController:Start()
	ClientState.observe("index", function()
		UIController:refresh("Index")
	end)
end

return IndexController

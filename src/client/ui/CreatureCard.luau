--!strict
-- Card used by inventory, trade, index and pickers.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Creatures = require(Shared.config.Creatures)
local Format = require(Shared.util.Format)
local Mutations = require(Shared.config.Mutations)
local Rarities = require(Shared.config.Rarities)
local Types = require(Shared.Types)
local Valuation = require(Shared.logic.Valuation)

local Theme = require(script.Parent.Theme)
local UI = require(script.Parent.UI)

local CreatureCard = {}

export type Options = {
	onClick: (() -> ())?,
	selected: boolean?,
	dimmed: boolean?,
	tag: string?, -- small text like "Placed" or "In trade"
	value: number?,
}

CreatureCard.size = Vector2.new(132, 150)

function CreatureCard.create(creature: Types.Creature, options: Options?): TextButton
	local opts: Options = options or {}
	local species = Creatures.byId[creature.species]
	local rarity = Rarities.byId[creature.rarity]
	local rarityColor = if rarity then Theme.rgb(rarity.color) else Theme.colors.text
	local value = opts.value or Valuation.value(creature)

	local card = UI.button("", Theme.colors.card, opts.onClick, {
		Size = UDim2.fromOffset(CreatureCard.size.X, CreatureCard.size.Y),
		AutoButtonColor = opts.onClick ~= nil,
	})
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if opts.selected then Theme.colors.good else rarityColor
		stroke.Thickness = if opts.selected then 4 else 2
	end
	if opts.dimmed then
		card.BackgroundColor3 = Theme.colors.disabled
	end

	-- Placeholder portrait: coloured circle in the species colour.
	UI.new("Frame", {
		Size = UDim2.fromOffset(54, 54),
		Position = UDim2.new(0.5, -27, 0, 8),
		BackgroundColor3 = if species then Theme.rgb(species.color) else Color3.new(1, 1, 1),
		Parent = card,
	}, { UI.corner(27), UI.stroke(rarityColor, 3) })

	UI.label(if species then species.displayName else creature.species, {
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.fromOffset(4, 64),
		TextSize = Theme.textSize.body,
		TextColor3 = rarityColor,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})

	local names = {}
	for _, id in creature.mutations do
		local def = Mutations.byId[id]
		table.insert(names, if def then def.displayName else id)
	end
	UI.label(if #names > 0 then table.concat(names, " · ") else (if rarity then rarity.displayName else ""), {
		Size = UDim2.new(1, -8, 0, 32),
		Position = UDim2.fromOffset(4, 86),
		TextSize = Theme.textSize.small,
		TextColor3 = if #names > 0 then Theme.colors.warn else Theme.colors.textDim,
		Font = Theme.fontBody,
		Parent = card,
	})

	UI.label(Assets.icons.coins .. " " .. Format.number(value), {
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.new(0, 4, 1, -26),
		TextSize = Theme.textSize.body,
		TextColor3 = Theme.colors.coins,
		Parent = card,
	})

	if creature.locked then
		UI.label(Assets.icons.lock, {
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.new(1, -28, 0, 2),
			TextSize = 20,
			Parent = card,
		})
	end
	if opts.tag then
		UI.label(opts.tag, {
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 2),
			TextSize = Theme.textSize.small,
			TextColor3 = Theme.colors.info,
			Parent = card,
		})
	end
	return card
end

return CreatureCard

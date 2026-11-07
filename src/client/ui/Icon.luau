--!strict
-- Icon builders: a coloured badge carrying an emoji, and creature portraits that show
-- the uploaded model's thumbnail on top of a species-coloured circle (the circle and
-- shape glyph stay visible while the thumbnail loads or if it is unavailable).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Icons = require(Shared.config.Icons)

local Theme = require(script.Parent.Theme)
local UI = require(script.Parent.UI)

local Icon = {}

-- Round badge in the nest's colour with its symbol on top.
function Icon.nest(parent: Instance, nestId: string, color: Color3, size: number, position: UDim2): Frame
	local badge = UI.new("Frame", {
		Name = "NestIcon",
		Size = UDim2.fromOffset(size, size),
		Position = position,
		BackgroundColor3 = color,
		Parent = parent,
	}, {
		UI.corner(size / 2),
		UI.new("UIStroke", { Color = Theme.colors.outline, Thickness = 3 }),
		UI.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(165, 165, 165)),
		}),
	})
	UI.label(Icons.nestIcon(nestId), {
		Size = UDim2.fromScale(1, 1),
		TextSize = math.floor(size * 0.55),
		Parent = badge,
	})
	return badge
end

-- Creature portrait. `discovered = false` shows a dark "?" silhouette.
function Icon.portrait(
	parent: Instance,
	species: any?,
	size: number,
	position: UDim2,
	ringColor: Color3,
	discovered: boolean?
): Frame
	local known = discovered ~= false and species ~= nil
	local portrait = UI.new("Frame", {
		Name = "Portrait",
		Size = UDim2.fromOffset(size, size),
		Position = position,
		BackgroundColor3 = if known then Theme.rgb(species.color) else Color3.fromRGB(14, 24, 52),
		Parent = parent,
	}, { UI.corner(size / 2), UI.new("UIStroke", { Color = ringColor, Thickness = 3 }) })
	if not known then
		UI.label("?", {
			Size = UDim2.fromScale(1, 1),
			TextSize = math.floor(size * 0.6),
			TextColor3 = Theme.colors.textDim,
			Parent = portrait,
		})
		return portrait
	end
	UI.label(Icons.shape[species.shape] or "🐾", {
		Size = UDim2.fromScale(1, 1),
		TextSize = math.floor(size * 0.5),
		Parent = portrait,
	})
	if species.modelAssetId then
		UI.new("ImageLabel", {
			Name = "Thumb",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = string.format("rbxthumb://type=Asset&id=%s&w=150&h=150", species.modelAssetId),
			ScaleType = Enum.ScaleType.Fit,
			Parent = portrait,
		})
	end
	return portrait
end

return Icon

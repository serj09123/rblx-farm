--!strict
-- Emoji icons used wherever a colour placeholder used to stand in for art.
-- Swap any entry for an image later (see ui/Icon.luau) without touching the panels.

local Icons = {}

Icons.nest = {
	meadow = "🌿",
	grove = "🌳",
	crystal = "💎",
	storm = "⛈️",
	celestial = "🌟",
	skyheart = "💗",
	starter = "🥚",
} :: { [string]: string }

Icons.mutation = {
	Shiny = "✨",
	Giant = "🏔️",
	Tiny = "🐜",
	Frozen = "❄️",
	Electric = "⚡",
	Golden = "🥇",
	Shadow = "🌑",
	Rainbow = "🌈",
	Cosmic = "🌌",
	Harvest = "🎃",
} :: { [string]: string }

-- Fallback portrait glyph by body shape when a species has no uploaded model.
Icons.shape = {
	Ball = "🐾",
	Block = "🐻",
	Cylinder = "🦎",
} :: { [string]: string }

function Icons.nestIcon(nestId: string): string
	return Icons.nest[nestId] or "🥚"
end

function Icons.mutationIcon(mutationId: string): string
	return Icons.mutation[mutationId] or "🧬"
end

return table.freeze(Icons)

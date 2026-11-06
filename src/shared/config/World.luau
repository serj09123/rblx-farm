--!strict
-- Procedural world layout (placeholder geometry). Units are studs.

return table.freeze({
	maxPlots = 6,
	plotRingRadius = 120,
	plotSize = 64,
	groundY = 0,
	-- Nest beds: two rows of five in front of the plot centre.
	nestBedGrid = { columns = 5, rows = 2, spacing = 9, offsetZ = -12 },
	-- Habitat pads: two rows of four behind the plot centre.
	habitatGrid = { columns = 4, rows = 2, spacing = 11, offsetZ = 14 },
	hub = {
		radius = 40,
		shopOffset = { 0, 0, -26 },
		marketOffset = { 26, 0, 0 },
		skyheartOffset = { 0, 0, 0 },
		leaderboardOffsets = { { -26, 0, -10 }, { -26, 0, 10 } },
		upgradeOffset = { 0, 0, 26 },
	},
	promptDistance = 12,
	creatureBobAmplitude = 0.4,
})

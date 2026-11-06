--!strict
-- Pure decoration for the placeholder world: floating-island rock, trees, flowers,
-- fences, lanterns, a hub fountain and ambient particles. Nothing here is interactive
-- and nothing here touches game state. Part budget is kept low (~600 parts total).

local WorldDecor = {}

local ROCK = Color3.fromRGB(120, 112, 140)
local ROCK_DARK = Color3.fromRGB(88, 82, 108)
local WOOD = Color3.fromRGB(130, 90, 60)
local LEAF_COLORS = {
	Color3.fromRGB(96, 190, 110),
	Color3.fromRGB(120, 205, 100),
	Color3.fromRGB(255, 165, 190), -- blossom tree
}
local FLOWER_COLORS = {
	Color3.fromRGB(255, 120, 160),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(170, 140, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(120, 200, 255),
}

local function make(class: string, props: { [string]: any }): any
	local instance = Instance.new(class)
	for key, value in props do
		instance[key] = value
	end
	return instance
end

local function block(props: { [string]: any }): Part
	local base: { [string]: any } = {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Material = Enum.Material.SmoothPlastic,
	}
	for key, value in props do
		base[key] = value
	end
	return make("Part", base)
end

local function ball(name: string, diameter: number, cframe: CFrame, color: Color3, parent: Instance): Part
	return block({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = cframe,
		Color = color,
		Parent = parent,
	})
end

local function glow(parent: Instance, color: Color3, range: number, brightness: number)
	make("PointLight", { Color = color, Range = range, Brightness = brightness, Shadows = false, Parent = parent })
end

local function sparkles(parent: Instance, color: Color3, rate: number, lifetime: number, speed: number, size: number)
	make("ParticleEmitter", {
		Name = "Sparkle",
		Color = ColorSequence.new(color),
		LightEmission = 1,
		LightInfluence = 0,
		Rate = rate,
		Lifetime = NumberRange.new(lifetime * 0.6, lifetime),
		Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, size),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = parent,
	})
end

-- Pieces ---------------------------------------------------------------------------

local function tree(rng: Random, cframe: CFrame, parent: Instance)
	local height = rng:NextNumber(5, 8)
	local leaf = LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)]
	block({
		Name = "Trunk",
		Size = Vector3.new(1.2, height, 1.2),
		CFrame = cframe * CFrame.new(0, height / 2, 0),
		Color = WOOD,
		Material = Enum.Material.Wood,
		CanCollide = true,
		Parent = parent,
	})
	local crown = height * 0.8
	ball("Crown", crown, cframe * CFrame.new(0, height + crown * 0.25, 0), leaf, parent)
	ball(
		"CrownSide",
		crown * 0.65,
		cframe * CFrame.new(crown * 0.35, height, crown * 0.15),
		leaf:Lerp(Color3.new(1, 1, 1), 0.12),
		parent
	)
end

local function flowers(rng: Random, center: CFrame, radius: number, count: number, parent: Instance)
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(rng:NextNumber()) * radius
		local at = center * CFrame.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		block({
			Name = "Stem",
			Size = Vector3.new(0.15, 0.9, 0.15),
			CFrame = at * CFrame.new(0, 0.45, 0),
			Color = Color3.fromRGB(80, 160, 80),
			Parent = parent,
		})
		ball("Bloom", 0.7, at * CFrame.new(0, 1, 0), FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)], parent)
	end
end

local function lantern(cframe: CFrame, color: Color3, parent: Instance)
	block({
		Name = "LanternPost",
		Size = Vector3.new(0.5, 4, 0.5),
		CFrame = cframe * CFrame.new(0, 2, 0),
		Color = Color3.fromRGB(70, 60, 85),
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	local lamp = ball("LanternGlow", 1.4, cframe * CFrame.new(0, 4.4, 0), color, parent)
	lamp.Material = Enum.Material.Neon
	glow(lamp, color, 16, 1.2)
	sparkles(lamp, color, 2, 3, 1.5, 0.35)
end

-- Rock underside so every island reads as floating in the sky.
local function rockUnderside(cframe: CFrame, diameter: number, parent: Instance)
	local layers = 4
	for i = 1, layers do
		local d = diameter * (1 - i * 0.2)
		block({
			Name = "Rock" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(5, d, d),
			CFrame = cframe * CFrame.new(0, -2.5 - (i - 1) * 4.5, 0) * CFrame.Angles(0, i * 0.7, math.rad(90)),
			Color = if i % 2 == 0 then ROCK_DARK else ROCK,
			Material = Enum.Material.Slate,
			CanCollide = false,
			Parent = parent,
		})
	end
	local tip = block({
		Name = "RockTip",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter * 0.18, diameter * 0.3, diameter * 0.18),
		CFrame = cframe * CFrame.new(0, -2.5 - layers * 4.5 - 2, 0),
		Color = ROCK_DARK,
		Material = Enum.Material.Slate,
		Parent = parent,
	})
	sparkles(tip, Color3.fromRGB(200, 190, 255), 1.5, 4, 1, 0.4)
end

local function fenceRing(cframe: CFrame, halfSize: number, gapHalfWidth: number, parent: Instance)
	local step = 8
	local posts = math.floor(halfSize * 2 / step)
	for side = 0, 3 do
		local rot = CFrame.Angles(0, side * math.pi / 2, 0)
		for i = 0, posts do
			local along = -halfSize + i * step
			-- Leave a gap on the hub-facing side (local -Z) for the path.
			if side == 0 and math.abs(along) < gapHalfWidth then
				continue
			end
			local at = cframe * rot * CFrame.new(along, 0, -halfSize + 0.5)
			block({
				Name = "FencePost",
				Size = Vector3.new(0.7, 2.2, 0.7),
				CFrame = at * CFrame.new(0, 1.6, 0),
				Color = Color3.fromRGB(245, 235, 220),
				Material = Enum.Material.Wood,
				CanCollide = false,
				Parent = parent,
			})
			if i < posts and not (side == 0 and math.abs(along + step / 2) < gapHalfWidth) then
				block({
					Name = "FenceRail",
					Size = Vector3.new(step, 0.35, 0.3),
					CFrame = at * CFrame.new(step / 2, 2, 0),
					Color = Color3.fromRGB(235, 220, 200),
					Material = Enum.Material.Wood,
					Parent = parent,
				})
			end
		end
	end
end

-- Public API -----------------------------------------------------------------------

function WorldDecor.decoratePlot(plot: Model, cframe: CFrame, size: number, index: number)
	local rng = Random.new(index * 7919)
	local folder = make("Folder", { Name = "Decor", Parent = plot })
	local half = size / 2

	rockUnderside(cframe, size, folder)
	fenceRing(cframe, half - 1, 6, folder)

	-- Trees in the back corners and along the sides, clear of beds and pads.
	local treeSpots = {
		Vector3.new(-half + 6, 1, half - 6),
		Vector3.new(half - 6, 1, half - 6),
		Vector3.new(-half + 5, 1, -2),
		Vector3.new(half - 5, 1, -2),
		Vector3.new(-half + 8, 1, half - 18),
	}
	for _, spot in treeSpots do
		tree(rng, cframe * CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), folder)
	end

	flowers(rng, cframe * CFrame.new(0, 1, -half + 8), 10, 14, folder)
	flowers(rng, cframe * CFrame.new(-half + 8, 1, 6), 5, 8, folder)
	flowers(rng, cframe * CFrame.new(half - 8, 1, 6), 5, 8, folder)

	-- Lanterns flank the entrance path.
	lantern(cframe * CFrame.new(-6, 1, -half + 1), Color3.fromRGB(255, 214, 140), folder)
	lantern(cframe * CFrame.new(6, 1, -half + 1), Color3.fromRGB(255, 214, 140), folder)
end

function WorldDecor.decorateHub(hub: Model, radius: number)
	local folder = make("Folder", { Name = "Decor", Parent = hub })
	local rng = Random.new(31337)
	local origin = CFrame.new(0, 0, 0)

	rockUnderside(origin * CFrame.new(0, 0, 0), radius * 2, folder)

	-- Ring of lanterns and flower beds around the plaza edge.
	local count = 12
	for i = 1, count do
		local angle = i / count * math.pi * 2
		local at = origin * CFrame.new(math.cos(angle) * (radius - 2), 1, math.sin(angle) * (radius - 2))
		if i % 2 == 0 then
			lantern(at, Color3.fromRGB(255, 160, 220), folder)
		else
			flowers(rng, at, 2.5, 6, folder)
		end
	end

	-- Trees between the stalls.
	for _, angle in { math.pi * 0.25, math.pi * 0.75, math.pi * 1.25, math.pi * 1.75 } do
		tree(rng, origin * CFrame.new(math.cos(angle) * (radius - 8), 1, math.sin(angle) * (radius - 8)), folder)
	end

	-- Orbiting shards around the Skyheart crystal.
	local shards = make("Folder", { Name = "SkyheartShards", Parent = folder })
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local shard = block({
			Name = "Shard" .. i,
			Size = Vector3.new(0.8, 2.4, 0.8),
			CFrame = origin
				* CFrame.new(math.cos(angle) * 8, 13 + (i % 2) * 2, math.sin(angle) * 8)
				* CFrame.Angles(0.4, angle, 0.3),
			Color = Color3.fromRGB(255, 150, 215),
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			Parent = shards,
		})
		shard:SetAttribute("Orbit", angle)
	end
end

-- Adds particles, rays and a halo to the Skyheart crystal itself.
function WorldDecor.dressSkyheart(crystal: BasePart)
	sparkles(crystal, Color3.fromRGB(255, 170, 225), 12, 3, 5, 0.8)
	make("ParticleEmitter", {
		Name = "Halo",
		Color = ColorSequence.new(Color3.fromRGB(255, 120, 200)),
		LightEmission = 1,
		LightInfluence = 0,
		Rate = 3,
		Lifetime = NumberRange.new(2),
		Speed = NumberRange.new(0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 8),
			NumberSequenceKeypoint.new(1, 16),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.85),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = crystal,
	})
end

return WorldDecor

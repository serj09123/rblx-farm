--!strict
-- Client-only mood: a soft dawn-to-golden-hour sky cycle, atmosphere, bloom, sun rays,
-- depth of field, a gentle camera-following petal drift, and a spinning, pulsing
-- Skyheart crystal with orbiting shards. All purely cosmetic.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local World = require(Shared.config.World)

local AtmosphereController = {}

-- A looping palette: (time-of-day clock, sky tint, ambient, outdoor ambient, fog colour)
local CYCLE_SECONDS = 600
local KEYFRAMES = {
	{
		clock = 7,
		ambient = Color3.fromRGB(150, 140, 175),
		outdoor = Color3.fromRGB(190, 175, 205),
		fog = Color3.fromRGB(255, 205, 190),
		brightness = 2.4,
	},
	{
		clock = 12,
		ambient = Color3.fromRGB(160, 170, 195),
		outdoor = Color3.fromRGB(190, 205, 230),
		fog = Color3.fromRGB(190, 225, 255),
		brightness = 3,
	},
	{
		clock = 17.5,
		ambient = Color3.fromRGB(175, 135, 150),
		outdoor = Color3.fromRGB(235, 170, 150),
		fog = Color3.fromRGB(255, 175, 140),
		brightness = 2.6,
	},
	{
		clock = 19.5,
		ambient = Color3.fromRGB(110, 100, 160),
		outdoor = Color3.fromRGB(150, 130, 200),
		fog = Color3.fromRGB(180, 130, 200),
		brightness = 1.8,
	},
}

local atmosphere: Atmosphere?
local petalAnchor: Part?

local function sample(progress: number)
	local count = #KEYFRAMES
	local scaled = progress * count
	local index = math.floor(scaled) % count + 1
	local nextIndex = index % count + 1
	local alpha = scaled - math.floor(scaled)
	-- Ease so colours linger on each keyframe.
	alpha = alpha * alpha * (3 - 2 * alpha)
	local a, b = KEYFRAMES[index], KEYFRAMES[nextIndex]
	local clock = a.clock + (b.clock - a.clock + (if b.clock < a.clock then 24 else 0)) * alpha
	return {
		clock = clock % 24,
		ambient = a.ambient:Lerp(b.ambient, alpha),
		outdoor = a.outdoor:Lerp(b.outdoor, alpha),
		fog = a.fog:Lerp(b.fog, alpha),
		brightness = a.brightness + (b.brightness - a.brightness) * alpha,
	}
end

local function setupLighting()
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.ExposureCompensation = 0.1

	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	local atmo = existing or Instance.new("Atmosphere")
	atmo.Density = 0.28
	atmo.Offset = 0.25
	atmo.Glare = 0.2
	atmo.Haze = 1.4
	atmo.Color = Color3.fromRGB(255, 215, 200)
	atmo.Decay = Color3.fromRGB(255, 190, 170)
	atmo.Parent = Lighting
	atmosphere = atmo

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "SkyheartBloom"
	bloom.Intensity = 0.55
	bloom.Size = 28
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "SkyheartRays"
	rays.Intensity = 0.12
	rays.Spread = 0.6
	rays.Parent = Lighting

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SkyheartGrade"
	grade.Saturation = 0.18
	grade.Contrast = 0.08
	grade.Brightness = 0.02
	grade.Parent = Lighting
end

local function setupPetals()
	local anchor = Instance.new("Part")
	anchor.Name = "SkyheartPetalAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(60, 1, 60)
	anchor.Parent = workspace
	petalAnchor = anchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Petals"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 190, 215), Color3.fromRGB(255, 240, 200))
	emitter.LightEmission = 0.4
	emitter.LightInfluence = 0.6
	emitter.Rate = 6
	emitter.Lifetime = NumberRange.new(6, 9)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.Acceleration = Vector3.new(2, -1.5, 1)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Size = NumberSequence.new(0.35)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = anchor
end

local function findSkyheart(): (BasePart?, Instance?)
	local world = workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	if not hub then
		return nil, nil
	end
	local crystal = hub:FindFirstChild("Skyheart")
	local decor = hub:FindFirstChild("Decor")
	local shards = decor and decor:FindFirstChild("SkyheartShards")
	return if crystal and crystal:IsA("BasePart") then crystal else nil, shards
end

function AtmosphereController:Init()
	setupLighting()
	setupPetals()
end

function AtmosphereController:Start()
	local crystal, shards = findSkyheart()
	local started = os.clock()
	local home = crystal and crystal.CFrame
	local camera = workspace.CurrentCamera

	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local progress = ((t - started) % CYCLE_SECONDS) / CYCLE_SECONDS
		local frame = sample(progress)
		Lighting.ClockTime = frame.clock
		Lighting.Ambient = frame.ambient
		Lighting.OutdoorAmbient = frame.outdoor
		Lighting.Brightness = frame.brightness
		if atmosphere then
			atmosphere.Color = frame.fog
		end

		camera = workspace.CurrentCamera or camera
		if petalAnchor and camera then
			petalAnchor.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(-10, 18, 0))
		end

		if not crystal then
			crystal, shards = findSkyheart()
			home = crystal and crystal.CFrame
		end
		if crystal and home then
			local pulse = 1 + math.sin(t * 2) * 0.04
			crystal.Size = Vector3.new(9, 9, 9) * pulse
			crystal.CFrame = home * CFrame.new(0, math.sin(t * 1.2) * 0.6, 0) * CFrame.Angles(0, t * 0.4, 0)
		end
		if shards then
			for _, shard in shards:GetChildren() do
				if shard:IsA("BasePart") then
					local base = shard:GetAttribute("Orbit")
					if type(base) == "number" then
						local angle = base + t * 0.5
						local radius = World.hub.radius * 0.2
						shard.CFrame = CFrame.new(
							math.cos(angle) * radius,
							13 + math.sin(t + base * 3) * 1.2,
							math.sin(angle) * radius
						) * CFrame.Angles(0.4 + t * 0.6, angle, 0.3)
					end
				end
			end
		end
	end)
end

return AtmosphereController

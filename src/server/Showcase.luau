--!strict
-- Review display: one of every critter species (all rarities) in rows in front of a player,
-- facing them. Used by the admin `/showcase` command. Toggle again to remove it.
-- The models are server-side only and are not saved anywhere.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Creatures = require(Shared.config.Creatures)
local Types = require(Shared.Types)

local CreatureVisuals = require(script.Parent.CreatureVisuals)
local Notifier = require(script.Parent.Notifier)

local Showcase = {}

local COLUMNS = 9
local SPACING = 7
local active: { [Player]: { Model } } = {}

function Showcase.clear(player: Player)
	local models = active[player]
	if models then
		for _, model in models do
			CreatureVisuals.release(model)
		end
		active[player] = nil
	end
	local folder = workspace:FindFirstChild("Showcase_" .. player.UserId)
	if folder then
		folder:Destroy()
	end
end

function Showcase.toggle(player: Player)
	if active[player] then
		Showcase.clear(player)
		Notifier.send(player, "info", "Showcase removed")
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		Notifier.error(player, "No character")
		return
	end
	CreatureVisuals.waitUntilReady(8)
	local folder = Instance.new("Folder")
	folder.Name = "Showcase_" .. player.UserId
	folder.Parent = workspace
	local models: { Model } = {}
	active[player] = models

	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local right = look:Cross(Vector3.yAxis)
	local origin = root.Position + look * 22
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { player.Character :: Instance }

	for index, species in Creatures.list do
		local column = (index - 1) % COLUMNS
		local row = (index - 1) // COLUMNS
		local offset = right * ((column - (COLUMNS - 1) / 2) * SPACING) + look * (row * SPACING)
		local spot = origin + offset
		local hit = workspace:Raycast(spot + Vector3.new(0, 60, 0), Vector3.new(0, -140, 0), rayParams)
		local ground = if hit then hit.Position else Vector3.new(spot.X, root.Position.Y - 3, spot.Z)
		-- A critter faces its local -Z, so aim -Z back at the player.
		local base = CFrame.lookAt(ground, Vector3.new(root.Position.X, ground.Y, root.Position.Z))
		local creature: Types.Creature = {
			id = "showcase_" .. species.id,
			species = species.id,
			rarity = species.rarity,
			mutations = {},
			size = 1,
			obtainedAt = 0,
			source = "reward",
		}
		local model = CreatureVisuals.build(creature, base)
		if model then
			model.Parent = folder
			table.insert(models, model)
		end
	end
	Notifier.send(player, "success", "Showcase: " .. #models .. " critters. Run /showcase again to remove it.")
end

Players.PlayerRemoving:Connect(Showcase.clear)

return Showcase

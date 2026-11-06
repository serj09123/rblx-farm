--!strict
-- Renders the global leaderboards on the hub boards (SurfaceGui, client-side).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.util.Format)
local Leaderboards = require(Shared.config.Leaderboards)

local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local LeaderboardController = {}

local surfaces: { [string]: ScrollingFrame } = {}

local function titleFor(id: string): string
	for _, board in Leaderboards.boards do
		if board.id == id then
			return board.displayName
		end
	end
	return id
end

local function ensureSurface(part: BasePart): ScrollingFrame?
	local id = part:GetAttribute("Board")
	if type(id) ~= "string" then
		return nil
	end
	local existing = surfaces[id]
	if existing and existing.Parent then
		return existing
	end
	local gui = UI.new("SurfaceGui", {
		Name = "ClientBoard",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
		Parent = part,
	})
	UI.label(titleFor(id), {
		Size = UDim2.new(1, 0, 0, 60),
		TextSize = 44,
		TextColor3 = Theme.colors.warn,
		Parent = gui,
	})
	local scroll = UI.scroll({ Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -64), Parent = gui })
	UI.list(Enum.FillDirection.Vertical, 2).Parent = scroll
	surfaces[id] = scroll
	return scroll
end

local function render()
	local world = workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	if not hub then
		return
	end
	local data = ClientState.world().leaderboards or {}
	for _, part in hub:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Board") then
			local scroll = ensureSurface(part)
			if scroll then
				UI.clear(scroll)
				local entries = data[part:GetAttribute("Board") :: string] or {}
				if #entries == 0 then
					UI.label("Loading...", { Size = UDim2.new(1, 0, 0, 40), TextSize = 30, Parent = scroll })
				end
				for rank, entry in entries do
					UI.label(string.format("%d. %s  -  %s", rank, entry.name, Format.number(entry.value)), {
						Size = UDim2.new(1, -20, 0, 36),
						TextSize = 28,
						TextXAlignment = Enum.TextXAlignment.Left,
						LayoutOrder = rank,
						Parent = scroll,
					})
				end
			end
		end
	end
end

function LeaderboardController:Start()
	ClientState.worldChanged:Connect(function(world)
		if world.leaderboards then
			render()
		end
	end)
	task.spawn(function()
		-- Boards may stream in later; retry a few times.
		for _ = 1, 10 do
			task.wait(5)
			render()
		end
	end)
end

return LeaderboardController

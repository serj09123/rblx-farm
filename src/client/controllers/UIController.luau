--!strict
-- Root ScreenGui, responsive scaling, safe areas and the panel manager.
-- One modal panel is open at a time; panels are built lazily by their controllers.

local Players = game:GetService("Players")

local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Signal = require(Shared.util.Signal)

local UIController = {
	panelOpened = Signal.new(), -- (name)
	panelClosed = Signal.new(), -- (name)
}

export type PanelSpec = {
	title: string,
	icon: string?,
	size: Vector2?,
	build: (content: Frame, ...any) -> (),
	onClose: (() -> ())?,
}

local player = Players.LocalPlayer
local screen: ScreenGui
local overlayScreen: ScreenGui
local uiScale: UIScale
local blocker: TextButton
local panelSpecs: { [string]: PanelSpec } = {}
local elements: { [string]: GuiObject } = {}
local current: { name: string, frame: Frame, args: { n: number, [number]: any } }? = nil

function UIController:root(): ScreenGui
	return screen
end

-- Separate always-on-top layer for toasts and celebrations.
function UIController:overlay(): ScreenGui
	return overlayScreen
end

function UIController:scale(): number
	return uiScale.Scale
end

function UIController:registerPanel(name: string, spec: PanelSpec)
	panelSpecs[name] = spec
end

-- Named GUI elements (HUD buttons etc.) the tutorial can point at.
function UIController:registerElement(name: string, element: GuiObject)
	elements[name] = element
end

function UIController:getElement(name: string): GuiObject?
	return elements[name]
end

function UIController:currentPanel(): string?
	return if current then current.name else nil
end

function UIController:close()
	local open = current
	if not open then
		return
	end
	current = nil
	local spec = panelSpecs[open.name]
	if spec and spec.onClose then
		task.spawn(spec.onClose)
	end
	open.frame:Destroy()
	blocker.Visible = false
	UIController.panelClosed:Fire(open.name)
end

-- Opens (or rebuilds) a panel. Extra args are passed to the panel's build function.
function UIController:open(name: string, ...: any)
	local spec = panelSpecs[name]
	if not spec then
		warn("[UIController] unknown panel " .. name)
		return
	end
	self:close()
	local size = spec.size or Theme.panelSize
	local frame = UI.new("Frame", {
		Name = "Panel_" .. name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Theme.colors.panel,
		ZIndex = 10,
		Parent = screen,
	}, {
		UI.corner(18),
		UI.stroke(Color3.new(0, 0, 0), 3),
		-- Never larger than the safe screen area (phones in portrait/landscape).
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(size.X, size.Y) }),
	})
	UI.label((spec.icon and (spec.icon .. " ") or "") .. spec.title, {
		Size = UDim2.new(1, -120, 0, 40),
		Position = UDim2.fromOffset(16, 8),
		TextSize = Theme.textSize.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local closeButton = UI.button(Assets.icons.close, Theme.colors.bad, function()
		UIController:close()
	end, {
		Size = UDim2.fromOffset(Theme.touch - 6, Theme.touch - 6),
		Position = UDim2.new(1, -(Theme.touch + 2), 0, 6),
		TextSize = Theme.textSize.title,
		Parent = frame,
	})
	closeButton.Name = "Close"
	local content = UI.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 62),
		Size = UDim2.new(1, -24, 1, -74),
		Parent = frame,
	})
	current = { name = name, frame = frame, args = table.pack(...) }
	blocker.Visible = true
	local ok, err = pcall(spec.build, content, ...)
	if not ok then
		warn("[UIController] panel " .. name .. " failed: " .. tostring(err))
	end
	local popScale = UI.new("UIScale", { Scale = 0.85, Parent = frame })
	UI.tween(popScale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
	UIController.panelOpened:Fire(name)
end

function UIController:toggle(name: string, ...: any)
	if current and current.name == name then
		self:close()
	else
		self:open(name, ...)
	end
end

-- Rebuilds the open panel if it is `name` (used when state changes). Without extra
-- arguments the panel is rebuilt with the arguments it was opened with.
function UIController:refresh(name: string, ...: any)
	if current and current.name == name then
		local args = if select("#", ...) > 0 then table.pack(...) else current.args
		local content = current.frame:FindFirstChild("Content")
		if content then
			-- Keep scroll positions so live updates don't yank the list back to the top.
			local positions = {}
			for _, descendant in content:GetDescendants() do
				if descendant:IsA("ScrollingFrame") then
					table.insert(positions, descendant.CanvasPosition)
				end
			end
			UI.clear(content)
			local spec = panelSpecs[name]
			local ok, err = pcall(spec.build, content :: Frame, table.unpack(args, 1, args.n))
			if not ok then
				warn("[UIController] refresh " .. name .. " failed: " .. tostring(err))
			end
			task.defer(function()
				local index = 0
				for _, descendant in content:GetDescendants() do
					if descendant:IsA("ScrollingFrame") then
						index += 1
						if positions[index] then
							descendant.CanvasPosition = positions[index]
						end
					end
				end
			end)
		end
	end
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local design = Theme.designResolution
	local scale = math.min(viewport.X / design.X, viewport.Y / design.Y)
	uiScale.Scale = math.clamp(scale, Theme.minScale, Theme.maxScale)
end

function UIController:Init()
	local playerGui = player:WaitForChild("PlayerGui")
	screen = UI.new("ScreenGui", {
		Name = "SkyheartUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
		Parent = playerGui,
	})
	uiScale = UI.new("UIScale", { Parent = screen })
	-- Gamepad/keyboard focus ring: a bright rounded outline instead of the default
	-- thin white box, so the selected button is obvious from the couch.
	local selection = UI.new("Frame", {
		Name = "SkyheartSelection",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, { UI.corner(14), UI.stroke(Color3.fromRGB(255, 235, 120), 4) })
	playerGui.SelectionImageObject = selection
	overlayScreen = UI.new("ScreenGui", {
		Name = "SkyheartOverlay",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = playerGui,
	})
	UI.new("UIScale", { Parent = overlayScreen })
	blocker = UI.new("TextButton", {
		Name = "Blocker",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.colors.overlay,
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 9,
		Parent = screen,
		Activated = function()
			UIController:close()
		end,
	})
end

function UIController:Start()
	local function bindCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
		local overlayScale = overlayScreen:FindFirstChildOfClass("UIScale")
		if overlayScale then
			overlayScale.Scale = uiScale.Scale
		end
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()
	uiScale:GetPropertyChangedSignal("Scale"):Connect(function()
		local overlayScale = overlayScreen:FindFirstChildOfClass("UIScale")
		if overlayScale then
			overlayScale.Scale = uiScale.Scale
		end
	end)
end

return UIController

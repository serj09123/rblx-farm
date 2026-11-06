--!strict
-- Tiny declarative UI helper + reusable components. Function-valued props whose
-- key is an event (e.g. Activated) are connected; `Children` are parented last.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local UI = {}

type Props = { [string]: any }

function UI.new(className: string, props: Props?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif type(value) == "function" then
				(instance :: any)[key]:Connect(value)
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Modifiers ---------------------------------------------------------------------

function UI.corner(radius: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.corner) })
end

function UI.stroke(color: Color3?, thickness: number?): UIStroke
	return UI.new("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		Transparency = 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.padding(px: number): UIPadding
	local p = UDim.new(0, px)
	return UI.new("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

function UI.list(
	direction: Enum.FillDirection,
	padding: number?,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UI.grid(cellSize: Vector2, padding: number?): UIGridLayout
	return UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cellSize.X, cellSize.Y),
		CellPadding = UDim2.fromOffset(padding or 8, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
end

-- Components --------------------------------------------------------------------

function UI.label(text: string, props: Props?): TextLabel
	local base: Props = {
		BackgroundTransparency = 1,
		Text = text,
		Font = Theme.font,
		TextSize = Theme.textSize.body,
		TextColor3 = Theme.colors.text,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, Theme.textSize.body + 6),
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return UI.new("TextLabel", base, { UI.new("UIStroke", { Thickness = 1.5, Transparency = 0.5 }) })
end

local function pressFeedback(button: GuiButton)
	local scale = UI.new("UIScale", { Parent = button })
	local info = TweenInfo.new(0.08, Enum.EasingStyle.Quad)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, info, { Scale = 0.92 }):Play()
	end)
	local function release()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
end

-- Big rounded text button. onClick fires on Activated (mouse, touch, gamepad).
function UI.button(text: string, color: Color3, onClick: (() -> ())?, props: Props?): TextButton
	local base: Props = {
		Text = text,
		Font = Theme.font,
		TextSize = Theme.textSize.body,
		TextColor3 = Theme.colors.text,
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(160, Theme.touch),
		TextWrapped = true,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local button = UI.new("TextButton", base, {
		UI.corner(),
		UI.stroke(Color3.new(0, 0, 0), 2),
		UI.new("UIStroke", { Thickness = 1.5, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }),
	})
	pressFeedback(button)
	if onClick then
		button.Activated:Connect(function()
			UI.onAnyClick()
			onClick()
		end)
	end
	return button
end

-- Square icon button with a caption underneath (HUD style).
function UI.iconButton(icon: string, caption: string, color: Color3, onClick: () -> (), size: number?): TextButton
	local s = size or 76
	local button = UI.button("", color, onClick, { Size = UDim2.fromOffset(s, s) })
	UI.label(icon, {
		Size = UDim2.fromScale(1, 0.62),
		Position = UDim2.fromScale(0, 0.04),
		TextSize = math.floor(s * 0.42),
		Parent = button,
	})
	UI.label(caption, {
		Size = UDim2.fromScale(1, 0.32),
		Position = UDim2.fromScale(0, 0.64),
		TextSize = Theme.textSize.small,
		Parent = button,
	})
	return button
end

-- Small red dot used to signal something claimable.
function UI.badge(parent: GuiObject): Frame
	return UI.new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(1, -12, 0, -6),
		BackgroundColor3 = Theme.colors.bad,
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	}, { UI.corner(9), UI.stroke(Color3.new(1, 1, 1), 2) })
end

function UI.progressBar(color: Color3, props: Props?): (Frame, (fraction: number) -> ())
	local base: Props = {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = Color3.fromRGB(20, 22, 36),
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local frame = UI.new("Frame", base, { UI.corner(7) })
	local fill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color,
		Parent = frame,
	}, { UI.corner(7) })
	local function set(fraction: number)
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	end
	return frame, set
end

function UI.scroll(props: Props?): ScrollingFrame
	local base: Props = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return UI.new("ScrollingFrame", base)
end

function UI.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Overridden by SoundController so every button clicks.
function UI.onAnyClick() end

function UI.tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad), goals)
	tween:Play()
	return tween
end

return UI

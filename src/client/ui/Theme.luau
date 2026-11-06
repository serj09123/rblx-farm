--!strict
-- Visual constants. Sizes are in "design pixels" at 960x540; UIController scales
-- the whole interface with a UIScale so phones and desktops get proportional sizes.

local Theme = {}

Theme.designResolution = Vector2.new(960, 540)
Theme.minScale = 0.6
Theme.maxScale = 1.4

Theme.font = Enum.Font.FredokaOne
Theme.fontBody = Enum.Font.GothamBold

Theme.colors = {
	panel = Color3.fromRGB(32, 36, 58),
	panelLight = Color3.fromRGB(48, 54, 84),
	card = Color3.fromRGB(58, 64, 98),
	text = Color3.fromRGB(255, 255, 255),
	textDim = Color3.fromRGB(190, 195, 220),
	accent = Color3.fromRGB(255, 120, 200),
	good = Color3.fromRGB(90, 210, 110),
	warn = Color3.fromRGB(255, 190, 60),
	bad = Color3.fromRGB(235, 80, 80),
	info = Color3.fromRGB(90, 160, 255),
	coins = Color3.fromRGB(255, 210, 70),
	essence = Color3.fromRGB(255, 120, 200),
	disabled = Color3.fromRGB(100, 104, 125),
	overlay = Color3.fromRGB(0, 0, 0),
}

Theme.textSize = {
	small = 14,
	body = 18,
	title = 26,
	huge = 40,
}

-- Minimum touch target (design px). ~44pt on a typical phone after scaling.
Theme.touch = 60
Theme.corner = 12
Theme.panelSize = Vector2.new(640, 420)

function Theme.rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

return Theme

--!strict
-- Visual constants. Sizes are in "design pixels" at 960x540; UIController scales
-- the whole interface with a UIScale so phones and desktops get proportional sizes.

local Theme = {}

Theme.designResolution = Vector2.new(960, 540)
Theme.minScale = 0.6
Theme.maxScale = 1.4

Theme.font = Enum.Font.LuckiestGuy
Theme.fontBody = Enum.Font.GothamBlack

Theme.colors = {
	panel = Color3.fromRGB(46, 128, 224),
	panelLight = Color3.fromRGB(32, 98, 190),
	card = Color3.fromRGB(26, 80, 160),
	header = Color3.fromRGB(255, 176, 36),
	headerEdge = Color3.fromRGB(205, 112, 8),
	outline = Color3.fromRGB(12, 28, 64),
	text = Color3.fromRGB(255, 255, 255),
	textDim = Color3.fromRGB(214, 232, 255),
	accent = Color3.fromRGB(255, 110, 200),
	good = Color3.fromRGB(70, 214, 100),
	warn = Color3.fromRGB(255, 200, 50),
	bad = Color3.fromRGB(240, 70, 85),
	info = Color3.fromRGB(70, 160, 255),
	coins = Color3.fromRGB(255, 210, 70),
	essence = Color3.fromRGB(255, 120, 200),
	disabled = Color3.fromRGB(100, 104, 125),
	overlay = Color3.fromRGB(0, 0, 0),
}

Theme.textSize = {
	small = 14,
	body = 19,
	title = 30,
	huge = 46,
}

-- Minimum touch target (design px). ~44pt on a typical phone after scaling.
Theme.touch = 60
Theme.corner = 12
Theme.panelSize = Vector2.new(640, 420)

function Theme.rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

return Theme

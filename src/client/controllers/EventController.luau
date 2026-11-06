--!strict
-- Weather / season banner and the Skyheart (co-op) panel.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)
local Coop = require(Shared.config.Coop)
local Economy = require(Shared.config.Economy)
local Format = require(Shared.util.Format)
local Net = require(Shared.net.Net)
local Rarities = require(Shared.config.Rarities)
local Weather = require(Shared.config.Weather)

local ClientState = require(script.Parent.Parent.ClientState)
local InventoryController = require(script.Parent.InventoryController)
local UIController = require(script.Parent.UIController)
local Theme = require(script.Parent.Parent.ui.Theme)
local UI = require(script.Parent.Parent.ui.UI)

local EventController = {}

local banner: Frame
local bannerLabel: TextLabel
local seasonLabel: TextLabel

local function refreshBanner()
	local world = ClientState.world()
	local now = ClientState.now()
	local weather = world.weather
	if type(weather) == "table" and Weather.byId[weather.id] then
		local def = Weather.byId[weather.id]
		local color = Theme.rgb(def.color)
		if weather.state == "incoming" then
			bannerLabel.Text = string.format(
				"%s %s in %s",
				Assets.icons.weather,
				def.displayName,
				Format.duration(weather.startsAt - now)
			)
		else
			bannerLabel.Text = string.format(
				"%s %s %s · %s",
				Assets.icons.weather,
				def.displayName,
				Format.duration(weather.endsAt - now),
				def.description
			)
		end
		bannerLabel.TextColor3 = color
		local stroke = banner:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
		banner.Visible = true
	else
		banner.Visible = false
	end
	local seasons = world.seasons
	if type(seasons) == "table" and seasons[1] then
		local season = seasons[1]
		seasonLabel.Text = string.format("🎉 %s · %s left", season.displayName, Format.duration(season.endsAt - now))
		seasonLabel.TextColor3 = Theme.rgb(season.color)
		seasonLabel.Visible = true
	else
		seasonLabel.Visible = false
	end
end

local function essenceFor(creature: any): number
	local rarity = Rarities.byId[creature.rarity]
	return (if rarity then rarity.essence else 1) * Economy.donateEssenceMultiplier * (1 + #creature.mutations)
end

local function buildSkyheart(content: Frame)
	local sky = ClientState.world().skyheart or { progress = 0, target = 1, bloomUntil = 0, contributors = 0 }
	local now = ClientState.now()
	local list = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = content }, {
		UI.list(Enum.FillDirection.Vertical, 10),
	})
	local blooming = sky.bloomUntil > now
	UI.label(
		if blooming
			then string.format("%s BLOOMING for %s!", Assets.icons.skyheart, Format.duration(sky.bloomUntil - now))
			else "Fill the Skyheart together to make it Bloom!",
		{ Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.colors.accent, LayoutOrder = 1, Parent = list }
	)
	local bar, set =
		UI.progressBar(Theme.colors.essence, { Size = UDim2.new(0.9, 0, 0, 22), LayoutOrder = 2, Parent = list })
	local _ = bar
	set(sky.progress / math.max(1, sky.target))
	UI.label(string.format("%d / %d essence  ·  %d helpers this round", sky.progress, sky.target, sky.contributors), {
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 3,
		Parent = list,
	})
	UI.label(
		string.format(
			"Bloom (%s): +%d%% coins, growth x%.2f, mutations x%.1f for everyone. Every helper gets a Skyheart Nest!",
			Format.duration(Coop.skyheart.bloomSeconds),
			math.floor(Coop.bloom.coinBonus * 100),
			Coop.bloom.growthMultiplier,
			Coop.bloom.mutationMultiplier
		),
		{
			Size = UDim2.new(1, -20, 0, 48),
			TextSize = Theme.textSize.small,
			Font = Theme.fontBody,
			TextColor3 = Theme.colors.textDim,
			LayoutOrder = 4,
			Parent = list,
		}
	)
	UI.label("Essence comes from hatching, cheering neighbours and donating critters.", {
		Size = UDim2.new(1, -20, 0, 24),
		TextSize = Theme.textSize.small,
		Font = Theme.fontBody,
		TextColor3 = Theme.colors.textDim,
		LayoutOrder = 5,
		Parent = list,
	})
	local buttons = UI.new(
		"Frame",
		{ Size = UDim2.new(1, 0, 0, Theme.touch), BackgroundTransparency = 1, LayoutOrder = 6, Parent = list },
		{
			UI.list(Enum.FillDirection.Horizontal, 10),
		}
	)
	UI.button(Assets.icons.skyheart .. " Donate a critter", Theme.colors.accent, function()
		InventoryController:pick({
			title = "Donate to the Skyheart",
			filter = function(creature)
				local ok, tag = InventoryController:freeFilter(creature)
				if not ok then
					return false, tag
				end
				return true, "+" .. essenceFor(creature) .. " " .. Assets.icons.essence
			end,
		}, function(ids)
			Net.Client.fire("DonateCreature", ids[1])
		end)
	end, { Size = UDim2.fromOffset(260, Theme.touch), Parent = buttons })
	UI.button(Assets.icons.vip .. " Server Bloom", Theme.colors.warn, function()
		UIController:open("Store")
	end, { Size = UDim2.fromOffset(220, Theme.touch), Parent = buttons })
end

function EventController:Init()
	local root = UIController:root()
	banner = UI.new("Frame", {
		Name = "EventBanner",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(330, 40),
		BackgroundColor3 = Theme.colors.panel,
		Visible = false,
		Parent = root,
	}, { UI.corner(12), UI.stroke(Theme.colors.info, 3) })
	bannerLabel = UI.label("", {
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.fromOffset(6, 0),
		TextSize = Theme.textSize.small,
		Parent = banner,
	})
	seasonLabel = UI.label("", {
		Position = UDim2.fromOffset(8, 52),
		Size = UDim2.fromOffset(330, 26),
		TextSize = Theme.textSize.small,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = root,
	})
	UIController:registerPanel(
		"Skyheart",
		{ title = "Skyheart", icon = Assets.icons.skyheart, size = Vector2.new(600, 380), build = buildSkyheart }
	)
end

function EventController:Start()
	ClientState.worldChanged:Connect(function()
		refreshBanner()
		UIController:refresh("Skyheart")
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			refreshBanner()
		end
	end)
end

return EventController

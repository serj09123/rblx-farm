--!strict
-- Server weather/anomaly events (mutation boosts) and seasonal event broadcast.
-- Players see a warning, then a banner with a countdown.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CoopMath = require(Shared.logic.CoopMath)
local ModifierMath = require(Shared.logic.ModifierMath)
local Net = require(Shared.net.Net)
local Types = require(Shared.Types)
local Weather = require(Shared.config.Weather)

local ModifierService = require(script.Parent.ModifierService)
local Notifier = require(script.Parent.Parent.Notifier)

local WeatherService = {}

local rng = Random.new()
local current: { id: string, state: string, startsAt: number, endsAt: number }? = nil
local forced: string? = nil
local lastSeasonKey = ""

local function weatherSnapshot(): any
	if not current then
		return false -- `false` clears the client value (nil would be dropped)
	end
	return table.clone(current)
end

local function seasonSnapshot(): any
	local list = {}
	for _, def in ModifierMath.activeSeasons(os.time()) do
		table.insert(list, {
			id = def.id,
			displayName = def.displayName,
			description = def.description,
			endsAt = def.endsAt,
			color = def.color,
		})
	end
	return list
end

local function publish()
	Net.Server.fireAll("WorldState", { weather = weatherSnapshot() })
end

function WeatherService:current(): string?
	return if current and current.state == "active" then current.id else nil
end

local function runEvent(def: Weather.WeatherDef)
	local now = os.time()
	current = {
		id = def.id,
		state = "incoming",
		startsAt = now + Weather.warningSeconds,
		endsAt = now + Weather.warningSeconds + def.durationSeconds,
	}
	publish()
	task.wait(Weather.warningSeconds)
	local active = current :: any
	active.state = "active"
	ModifierService:setGlobal("weather", def.modifiers, active.endsAt, def.displayName)
	publish()
	Notifier.announce({ kind = "weather", id = def.id, untilTime = active.endsAt })
	task.wait(def.durationSeconds)
	ModifierService:setGlobal("weather", nil)
	current = nil
	publish()
end

-- Studio testing helper: set workspace attribute ForceWeather = "<id>".
function WeatherService:force(id: string)
	if Weather.byId[id] then
		forced = id
	end
end

function WeatherService:PlayerReady(player: Player, _data: Types.Profile)
	Net.Server.fire(player, "WorldState", { weather = weatherSnapshot(), seasons = seasonSnapshot() })
end

function WeatherService:Start()
	task.spawn(function()
		local previous: string? = nil
		local waitUntil = os.clock() + Weather.firstEventDelaySeconds
		while true do
			while os.clock() < waitUntil and not forced do
				task.wait(1)
			end
			local def = if forced then Weather.byId[forced] else CoopMath.pickWeather(rng, previous)
			forced = nil
			previous = def.id
			local ok, err = pcall(runEvent, def)
			if not ok then
				warn("[WeatherService] event failed: " .. tostring(err))
				ModifierService:setGlobal("weather", nil)
				current = nil
				publish()
			end
			waitUntil = os.clock() + CoopMath.weatherGap(rng)
		end
	end)

	-- Seasons start/end on their own; re-broadcast when the active set changes.
	task.spawn(function()
		while true do
			local key = ""
			for _, def in ModifierMath.activeSeasons(os.time()) do
				key ..= def.id .. ";"
			end
			if key ~= lastSeasonKey then
				lastSeasonKey = key
				Net.Server.fireAll("WorldState", { seasons = seasonSnapshot() })
				ModifierService.changed:Fire()
			end
			task.wait(30)
		end
	end)

	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("ForceWeather"):Connect(function()
			local id = workspace:GetAttribute("ForceWeather")
			if type(id) == "string" then
				WeatherService:force(id)
			end
		end)
	end
end

return WeatherService

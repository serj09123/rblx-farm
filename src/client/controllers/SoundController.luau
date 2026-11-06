--!strict
-- Plays UI/feedback sounds by key (config/Assets.sounds). Empty ids are silent.

local SoundService = game:GetService("SoundService")

local ClientState = require(script.Parent.Parent.ClientState)
local UI = require(script.Parent.Parent.ui.UI)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.config.Assets)

local SoundController = {}

local sounds: { [string]: Sound } = {}
local music: Sound?
local lastPlayed: { [string]: number } = {}

local function enabled(): boolean
	local settings = ClientState.get("settings")
	return settings == nil or settings.sfx ~= false
end

function SoundController:play(key: string, pitch: number?)
	local sound = sounds[key]
	if not sound or not enabled() then
		return
	end
	local now = os.clock()
	if (lastPlayed[key] or 0) + 0.05 > now then
		return
	end
	lastPlayed[key] = now
	sound.PlaybackSpeed = pitch or 1
	sound:Play()
end

local function refreshMusic()
	local track = music
	if not track then
		return
	end
	local settings = ClientState.get("settings")
	local on = settings == nil or settings.music ~= false
	if on and not track.Playing then
		track:Play()
	elseif not on and track.Playing then
		track:Pause()
	end
end

function SoundController:Start()
	-- Background music: silent until Assets.sounds.music holds an uploaded track id.
	if Assets.sounds.music ~= "" then
		local track = Instance.new("Sound")
		track.Name = "Music"
		track.SoundId = Assets.sounds.music
		track.Volume = 0.25
		track.Looped = true
		track.Parent = SoundService
		music = track
		ClientState.observe("settings", refreshMusic)
		refreshMusic()
	end
end

function SoundController:Init()
	local folder = Instance.new("Folder")
	folder.Name = "SkyheartSounds"
	for key, id in Assets.sounds do
		if id ~= "" and key ~= "music" then
			local sound = Instance.new("Sound")
			sound.Name = key
			sound.SoundId = id
			sound.Volume = 0.5
			sound.Parent = folder
			sounds[key] = sound
		end
	end
	folder.Parent = SoundService
	UI.onAnyClick = function()
		SoundController:play("click", 1.2)
	end
end

return SoundController

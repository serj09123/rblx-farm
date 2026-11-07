--!strict
-- Uploads assets/audio/<key>.mp3 to Roblox through Open Cloud (Assets API) and writes
-- the resulting rbxassetid:// ids into src/shared/config/Assets.luau (sounds table).
--
-- Usage:
--   ROBLOX_API_KEY=... lune run scripts/upload-audio -- --user <yourUserId> [--dry-run] [--force]
--   ROBLOX_API_KEY=... lune run scripts/upload-audio -- --group <groupId>   [--dry-run] [--force]
--
-- The API key (Creator Hub -> Open Cloud -> API Keys) needs "asset:read" and
-- "asset:write" permissions. Never commit the key; pass it as an environment variable.
--
-- Notes:
--   * Roblox moderates audio. An upload can finish while the asset is still pending;
--     it is usable in-game once approved.
--   * Keys that already hold an rbxassetid:// are skipped unless --force is given.
--   * Not exercised against the live service from the build environment: run with
--     --dry-run first. If the API rejects a request, its error body is printed.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local task = require("@lune/task")

local AUDIO_DIR = "assets/audio"
local ASSETS_FILE = "src/shared/config/Assets.luau"
local ENDPOINT = "https://apis.roblox.com/assets/v1"
local KEYS = { "click", "coins", "hatch", "rare", "mythic", "bloom", "trade", "error", "music" }
local DESCRIPTIONS = {
	click = "UI click",
	coins = "Coins reward jingle",
	hatch = "Egg hatch",
	rare = "Rare hatch sting",
	mythic = "Mythic hatch fanfare",
	bloom = "Skyheart bloom swell",
	trade = "Trade chime",
	error = "Error buzz",
	music = "Background music loop",
}

local args = process.args
local function flag(name: string): boolean
	return table.find(args, name) ~= nil
end
local function option(name: string): string?
	local index = table.find(args, name)
	return if index then args[index + 1] else nil
end

local dryRun = flag("--dry-run")
local force = flag("--force")
local userId = option("--user")
local groupId = option("--group")
local apiKey = process.env.ROBLOX_API_KEY

if (userId == nil) == (groupId == nil) then
	print("pass exactly one of --user <id> or --group <id>")
	process.exit(2)
end
if not dryRun and not apiKey then
	print("ROBLOX_API_KEY is not set")
	process.exit(2)
end

local function jsonString(value: string): string
	return net.jsonEncode(value)
end

local function readAssets(): string
	return fs.readFile(ASSETS_FILE)
end

-- Current id for a sound key ("" when silent).
local function currentId(source: string, key: string): string
	local value = string.match(source, "\t\t" .. key .. ' = "([^"]*)"')
	return value or ""
end

local function setId(source: string, key: string, id: string): string
	local replaced, count = string.gsub(source, "(\t\t" .. key .. ' = )"[^"]*"', function(prefix)
		return prefix .. '"' .. id .. '"'
	end)
	assert(count == 1, "could not find sounds." .. key .. " in " .. ASSETS_FILE)
	return replaced
end

local function multipart(boundary: string, requestJson: string, fileName: string, content: string): string
	return table.concat({
		"--" .. boundary,
		'Content-Disposition: form-data; name="request"',
		"Content-Type: application/json",
		"",
		requestJson,
		"--" .. boundary,
		'Content-Disposition: form-data; name="fileContent"; filename="' .. fileName .. '"',
		"Content-Type: audio/mpeg",
		"",
		content,
		"--" .. boundary .. "--",
		"",
	}, "\r\n")
end

local function upload(key: string): (string?, string?)
	local path = AUDIO_DIR .. "/" .. key .. ".mp3"
	local content = fs.readFile(path)
	local creator = if userId then '{"userId":"' .. userId .. '"}' else '{"groupId":"' .. (groupId :: string) .. '"}'
	local requestJson = string.format(
		'{"assetType":"Audio","displayName":%s,"description":%s,"creationContext":{"creator":%s}}',
		jsonString("Skyheart " .. key),
		jsonString(DESCRIPTIONS[key] or key),
		creator
	)
	local boundary = "----skyheart" .. tostring(os.time())
	local response = net.request({
		url = ENDPOINT .. "/assets",
		method = "POST",
		headers = {
			["x-api-key"] = apiKey :: string,
			["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
		},
		body = multipart(boundary, requestJson, key .. ".mp3", content),
	})
	if not response.ok then
		return nil, string.format("upload failed (%d): %s", response.statusCode, response.body)
	end
	local operation = net.jsonDecode(response.body)
	local operationPath = operation.path or ("operations/" .. tostring(operation.operationId))
	for _ = 1, 30 do
		local poll = net.request({
			url = ENDPOINT .. "/" .. operationPath,
			method = "GET",
			headers = { ["x-api-key"] = apiKey :: string },
		})
		if not poll.ok then
			return nil, string.format("poll failed (%d): %s", poll.statusCode, poll.body)
		end
		local state = net.jsonDecode(poll.body)
		if state.done then
			if state.error then
				return nil, "asset rejected: " .. net.jsonEncode(state.error)
			end
			local assetId = state.response and state.response.assetId
			if assetId then
				return tostring(assetId), nil
			end
			return nil, "finished without an asset id: " .. poll.body
		end
		task.wait(2)
	end
	return nil, "timed out waiting for the upload to finish"
end

local source = readAssets()
local failures = 0
for _, key in KEYS do
	local existing = currentId(source, key)
	if string.find(existing, "^rbxassetid://") and not force then
		print(string.format("skip %-7s already %s", key, existing))
		continue
	end
	if dryRun then
		print(
			string.format(
				"[dry-run] would upload %s/%s.mp3 (%d bytes)",
				AUDIO_DIR,
				key,
				#fs.readFile(AUDIO_DIR .. "/" .. key .. ".mp3")
			)
		)
		continue
	end
	local id, err = upload(key)
	if id then
		source = setId(source, key, "rbxassetid://" .. id)
		fs.writeFile(ASSETS_FILE, source) -- save after every success so a failure keeps progress
		print(string.format("ok   %-7s rbxassetid://%s", key, id))
	else
		failures += 1
		print(string.format("FAIL %-7s %s", key, err or "unknown error"))
	end
end
process.exit(if failures > 0 then 1 else 0)

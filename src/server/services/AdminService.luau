--!strict
-- Support tools for staff, as chat commands:
--   /inspect <name>          summary of a player's profile
--   /trade <tradeId>         summary of a committed trade record
--   /grant <name> <coins>    compensation (capped, audit-logged)
--   /showcase                toggles a display of every critter species in front of you
-- Non-admins get no response at all, so the commands are not discoverable.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Admin = require(Shared.config.Admin)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local TradeService = require(script.Parent.TradeService)
local Notifier = require(script.Parent.Parent.Notifier)
local Showcase = require(script.Parent.Parent.Showcase)

local AdminService = {}

function AdminService.isAdmin(player: Player): boolean
	if table.find(Admin.adminUserIds, player.UserId) then
		return true
	end
	return Admin.allowExperienceOwner and game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId
end

local function audit(admin: Player, message: string)
	warn(string.format("[Admin] %s (%d): %s", admin.Name, admin.UserId, message))
end

local function findPlayer(query: string): Player?
	local lowered = string.lower(query)
	for _, candidate in Players:GetPlayers() do
		if string.lower(candidate.Name) == lowered or string.lower(candidate.DisplayName) == lowered then
			return candidate
		end
	end
	for _, candidate in Players:GetPlayers() do
		if string.find(string.lower(candidate.Name), lowered, 1, true) then
			return candidate
		end
	end
	return nil
end

local function words(text: string): { string }
	local list = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(list, word)
	end
	return list
end

-- Pure formatter, kept separate so it can be unit tested.
function AdminService.describeProfile(name: string, data: any): string
	local creatureCount = 0
	for _ in data.creatures do
		creatureCount += 1
	end
	return string.format(
		"%s: coins %d, hatched %d, critters %d, sessions %d, trades %d",
		name,
		data.coins,
		data.stats.hatched,
		creatureCount,
		data.stats.sessions,
		data.stats.trades
	)
end

local function inspect(admin: Player, args: { string })
	local target = if args[2] then findPlayer(args[2]) else nil
	local data = target and DataService:get(target)
	if not target or not data then
		Notifier.error(admin, "Player not found")
		return
	end
	local text = AdminService.describeProfile(target.Name, data)
	audit(admin, "inspect " .. text)
	Notifier.send(admin, "info", text)
end

local function trade(admin: Player, args: { string })
	local id = args[2]
	if not id then
		Notifier.error(admin, "Usage: /trade <tradeId>")
		return
	end
	task.spawn(function()
		local ok, record = TradeService:getRecord(id)
		if not ok then
			Notifier.error(admin, "Could not read trade record")
		elseif record == nil then
			Notifier.error(admin, "No such trade")
		else
			local HttpService = game:GetService("HttpService")
			local encoded = HttpService:JSONEncode(record)
			audit(admin, "trade " .. id .. ": " .. encoded)
			Notifier.send(admin, "info", "Trade record printed to the server log")
		end
	end)
end

local function grant(admin: Player, args: { string })
	local target = if args[2] then findPlayer(args[2]) else nil
	local amount = tonumber(args[3])
	if not target or not amount or amount <= 0 or amount ~= math.floor(amount) then
		Notifier.error(admin, "Usage: /grant <name> <coins>")
		return
	end
	if amount > Admin.maxGrantCoins then
		Notifier.error(admin, "Max grant is " .. Admin.maxGrantCoins)
		return
	end
	local given = EconomyService:add(target, amount, "admin_grant", "Gameplay")
	audit(admin, string.format("grant %d coins to %s (%d)", given, target.Name, target.UserId))
	Notifier.send(admin, "success", string.format("Granted %d coins to %s", given, target.Name))
	Notifier.send(target, "reward", "Support sent you " .. given .. " coins", "coins")
end

local COMMANDS: { [string]: (Player, { string }) -> () } = {
	["/inspect"] = inspect,
	["/trade"] = trade,
	["/grant"] = grant,
	["/showcase"] = Showcase.toggle,
}

function AdminService:Start()
	for alias, handler in COMMANDS do
		local command = Instance.new("TextChatCommand")
		command.Name = "Skyheart" .. string.sub(alias, 2)
		command.PrimaryAlias = alias
		command.Parent = TextChatService
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player and AdminService.isAdmin(player) then
				handler(player, words(text))
			end
		end)
	end
end

return AdminService

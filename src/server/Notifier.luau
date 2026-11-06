--!strict
-- Small helper for player-facing toasts. Text is short; icons carry meaning.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.net.Net)

export type Kind = "info" | "success" | "error" | "reward" | "rare"

local Notifier = {}

function Notifier.send(player: Player, kind: Kind, text: string, icon: string?)
	Net.Server.fire(player, "Notify", { kind = kind, text = text, icon = icon })
end

function Notifier.error(player: Player, text: string)
	Notifier.send(player, "error", text, "close")
end

function Notifier.announce(payload: { [string]: any })
	Net.Server.fireAll("Announce", payload)
end

return Notifier

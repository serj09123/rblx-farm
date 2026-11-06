--!strict
-- Pure decision logic for MarketplaceService.ProcessReceipt. Guarantees each
-- PurchaseId is granted at most once per profile, and that PurchaseGranted is only
-- returned after the grant was persisted.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DataConfig = require(Shared.config.Data)
local Types = require(Shared.Types)

local ReceiptLogic = {}

export type Decision = "grant" | "alreadyGranted" | "notReady" | "unknownProduct"

function ReceiptLogic.decide(data: Types.Profile?, purchaseId: string, productKnown: boolean): Decision
	if not data then
		return "notReady"
	end
	if data.purchases.receipts[purchaseId] then
		return "alreadyGranted"
	end
	if not productKnown then
		return "unknownProduct"
	end
	return "grant"
end

-- Records a granted receipt, keeping only the most recent entries.
function ReceiptLogic.record(data: Types.Profile, purchaseId: string, now: number, maxHistory: number?)
	local receipts = data.purchases.receipts
	receipts[purchaseId] = now
	local limit = maxHistory or DataConfig.maxReceiptHistory
	local entries = {}
	for id, at in receipts do
		table.insert(entries, { id = id, at = at })
	end
	if #entries <= limit then
		return
	end
	table.sort(entries, function(a, b)
		return a.at < b.at
	end)
	for i = 1, #entries - limit do
		if entries[i].id ~= purchaseId then
			receipts[entries[i].id] = nil
		end
	end
end

-- Final answer for Roblox given the grant/save outcome.
function ReceiptLogic.result(
	decision: Decision,
	granted: boolean,
	saved: boolean
): "PurchaseGranted" | "NotProcessedYet"
	if decision == "alreadyGranted" then
		return "PurchaseGranted"
	end
	if decision == "grant" and granted and saved then
		return "PurchaseGranted"
	end
	return "NotProcessedYet"
end

return table.freeze(ReceiptLogic)

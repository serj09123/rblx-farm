--!strict
-- Developer products (ProcessReceipt), purchase prompts with policy checks, shop
-- catalogue and VIP cosmetics. Game pass ownership lives in PassService.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Monetization = require(Shared.config.Monetization)
local Net = require(Shared.net.Net)

local ReceiptLogic = require(script.Parent.Parent.data.ReceiptLogic)
local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local FarmService = require(script.Parent.FarmService)
local ModifierService = require(script.Parent.ModifierService)
local PassService = require(script.Parent.PassService)
local PolicyCache = require(script.Parent.PolicyCache)
local SkyheartService = require(script.Parent.SkyheartService)
local Notifier = require(script.Parent.Parent.Notifier)
local ServerEvents = require(script.Parent.Parent.ServerEvents)

local MonetizationService = {}

local priceCache: { [string]: number } = {}

local function isHidden(player: Player, def: Monetization.ProductDef): boolean
	return def.paidRandom and PolicyCache:get(player).paidRandomItemsRestricted
end

local function price(kind: "pass" | "product", id: number): number?
	if id == 0 then
		return nil
	end
	local cacheKey = kind .. id
	if priceCache[cacheKey] then
		return priceCache[cacheKey]
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(
			id,
			if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		)
	end)
	if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
		priceCache[cacheKey] = info.PriceInRobux
		return info.PriceInRobux
	end
	return nil
end

-- Applies a product's effect. Errors propagate so the receipt is retried.
local function grant(player: Player, def: Monetization.ProductDef)
	if def.key == "LuckBoost15" then
		ModifierService:extendBoost(player, "luckUntil", def.durationSeconds or 900)
	elseif def.key == "GrowthBoost15" then
		ModifierService:extendBoost(player, "growthUntil", def.durationSeconds or 900)
	elseif def.key == "InstantGrow" then
		FarmService:finishAll(player)
	elseif def.key == "ServerBloom" then
		SkyheartService:triggerPurchasedBloom(player)
	elseif def.coins then
		EconomyService:add(player, def.coins, "product_" .. def.key, "IAP")
	else
		error("No grant handler for product " .. def.key)
	end
end

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService:get(player)
	local purchaseId = tostring(receiptInfo.PurchaseId)
	local def = Monetization.productById[receiptInfo.ProductId]
	local decision = ReceiptLogic.decide(data, purchaseId, def ~= nil)
	if decision == "unknownProduct" then
		warn(
			"[MonetizationService] Unknown product id "
				.. tostring(receiptInfo.ProductId)
				.. " - check config/Monetization.luau"
		)
	end
	local granted, saved = false, false
	if decision == "grant" and data and def then
		local ok, err = pcall(grant, player, def)
		if ok then
			granted = true
			ReceiptLogic.record(data, purchaseId, os.time())
			saved = DataService:saveNow(player)
			Notifier.send(player, "reward", "Thank you! " .. def.displayName, "gift")
			Analytics.custom(player, "Purchase_" .. def.key, receiptInfo.CurrencySpent)
			ServerEvents.purchased:Fire(player, "product", def.key)
		else
			warn("[MonetizationService] Grant failed for " .. def.key .. ": " .. tostring(err))
		end
	end
	local result = ReceiptLogic.result(decision, granted, saved)
	return if result == "PurchaseGranted"
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

local function onPromptPurchase(player: Player, kind: string, key: string)
	if kind == "pass" then
		local def = Monetization.passByKey[key]
		if not def or def.id == 0 then
			Notifier.error(player, "Not available yet")
			return
		end
		if PassService:owns(player, key) then
			Notifier.send(player, "info", "You already own " .. def.displayName, "vip")
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, def.id)
	else
		local def = Monetization.productByKey[key]
		if not def or def.id == 0 then
			Notifier.error(player, "Not available yet")
			return
		end
		if isHidden(player, def) then
			Notifier.error(player, "This item isn't available for your account")
			return
		end
		MarketplaceService:PromptProductPurchase(player, def.id)
	end
end

local function shopCatalogue(player: Player): any
	local passes = {}
	for _, def in Monetization.passes do
		table.insert(passes, {
			key = def.key,
			displayName = def.displayName,
			description = def.description,
			available = def.id ~= 0,
			owned = PassService:owns(player, def.key),
			price = price("pass", def.id),
		})
	end
	local products = {}
	for _, def in Monetization.products do
		if not isHidden(player, def) then
			table.insert(products, {
				key = def.key,
				displayName = def.displayName,
				description = def.description,
				available = def.id ~= 0,
				price = price("product", def.id),
				paidRandom = def.paidRandom,
				luckMultiplier = def.luckMultiplier,
				growthMultiplier = def.growthMultiplier,
				durationSeconds = def.durationSeconds,
				coins = def.coins,
			})
		end
	end
	return { ok = true, passes = passes, products = products }
end

-- VIP cosmetic: gold tag above the head + attribute the client uses for chat tags.
local function applyVip(player: Player, character: Model?)
	player:SetAttribute("VIP", true)
	if not character then
		return
	end
	local head = character:WaitForChild("Head", 10)
	if not head or head:FindFirstChild("VipTag") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "VipTag"
	gui.Size = UDim2.fromOffset(120, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "👑 VIP"
	label.TextColor3 = Color3.fromRGB(255, 215, 80)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = head
end

local function watchVip(player: Player)
	player.CharacterAdded:Connect(function(character)
		if PassService:owns(player, "VIP") then
			applyVip(player, character)
		end
	end)
	if PassService:owns(player, "VIP") then
		task.spawn(applyVip, player, player.Character) -- never yield inside PlayerReady
	end
end

function MonetizationService:Init()
	Net.Server.on("PromptPurchase", onPromptPurchase)
	Net.Server.handle("GetShop", shopCatalogue)
end

function MonetizationService:PlayerReady(player: Player)
	watchVip(player)
end

function MonetizationService:Start()
	MarketplaceService.ProcessReceipt = processReceipt
	PassService.passGranted:Connect(function(player: Player, key: string)
		if key == "VIP" then
			task.spawn(applyVip, player, player.Character)
		end
	end)
end

return MonetizationService

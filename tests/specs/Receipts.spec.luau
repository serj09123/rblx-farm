--!nocheck
local Server = game:GetService("ServerScriptService").Server
local ReceiptLogic = require(Server.data.ReceiptLogic)
local ProfileTemplate = require(Server.data.ProfileTemplate)

return function()
	describe("ReceiptLogic", function()
		it("waits while the profile is not loaded", function()
			local decision = ReceiptLogic.decide(nil, "p1", true)
			expect(decision).to.equal("notReady")
			expect(ReceiptLogic.result(decision, false, false)).to.equal("NotProcessedYet")
		end)

		it("grants once and acknowledges repeats without granting again", function()
			local data = ProfileTemplate.create()
			expect(ReceiptLogic.decide(data, "p1", true)).to.equal("grant")
			ReceiptLogic.record(data, "p1", 100)
			local again = ReceiptLogic.decide(data, "p1", true)
			expect(again).to.equal("alreadyGranted")
			expect(ReceiptLogic.result(again, false, false)).to.equal("PurchaseGranted")
		end)

		it("only reports success after the grant was saved", function()
			expect(ReceiptLogic.result("grant", true, false)).to.equal("NotProcessedYet")
			expect(ReceiptLogic.result("grant", false, true)).to.equal("NotProcessedYet")
			expect(ReceiptLogic.result("grant", true, true)).to.equal("PurchaseGranted")
		end)

		it("never grants unknown products", function()
			local data = ProfileTemplate.create()
			local decision = ReceiptLogic.decide(data, "p9", false)
			expect(decision).to.equal("unknownProduct")
			expect(ReceiptLogic.result(decision, false, false)).to.equal("NotProcessedYet")
		end)

		it("keeps a bounded receipt history but always the newest", function()
			local data = ProfileTemplate.create()
			for i = 1, 10 do
				ReceiptLogic.record(data, "r" .. i, i, 5)
			end
			local count = 0
			for _ in data.purchases.receipts do
				count += 1
			end
			expect(count).to.equal(5)
			expect(data.purchases.receipts.r10).to.equal(10)
			expect(data.purchases.receipts.r1).to.equal(nil)
		end)
	end)
end

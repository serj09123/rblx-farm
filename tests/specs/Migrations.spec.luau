--!nocheck
local ServerScriptService = game:GetService("ServerScriptService")
local Migrations = require(ServerScriptService.Server.data.Migrations)
local ProfileTemplate = require(ServerScriptService.Server.data.ProfileTemplate)
local TableUtil = require(game:GetService("ReplicatedStorage").Shared.util.TableUtil)

return function()
	local steps = {
		[1] = function(data)
			data.gems = (data.coins or 0) // 100
			return data
		end,
		[2] = function(data)
			data.nickname = nil
			data.renamed = true
			return data
		end,
	}

	describe("Migrations.run", function()
		it("applies steps in order and stamps the version", function()
			local data, result = Migrations.run({ schemaVersion = 1, coins = 500, nickname = "x" }, {}, 3, steps)
			expect(result).to.equal("ok")
			expect(data.schemaVersion).to.equal(3)
			expect(data.gems).to.equal(5)
			expect(data.nickname).to.equal(nil)
			expect(data.renamed).to.equal(true)
		end)

		it("treats unversioned data as v1", function()
			local data, result = Migrations.run({ coins = 300 }, {}, 2, steps)
			expect(result).to.equal("ok")
			expect(data.gems).to.equal(3)
		end)

		it("refuses data from a newer schema", function()
			local _, result = Migrations.run({ schemaVersion = 9 }, {}, 3, steps)
			expect(result).to.equal("future")
		end)

		it("reports a missing step", function()
			local _, result = Migrations.run({ schemaVersion = 1 }, {}, 3, { [2] = steps[2] })
			expect(result).to.equal("missingStep")
		end)

		it("rejects non-table data", function()
			local _, result = Migrations.run("garbage", {}, 1)
			expect(result).to.equal("invalid")
		end)

		it("reconciles missing fields from the template without touching existing ones", function()
			local template = ProfileTemplate.create()
			local old = { schemaVersion = ProfileTemplate.CURRENT_VERSION, coins = 12345, upgrades = { luck = 3 } }
			local data, result = Migrations.run(old, template, ProfileTemplate.CURRENT_VERSION)
			expect(result).to.equal("ok")
			expect(data.coins).to.equal(12345)
			expect(data.upgrades.luck).to.equal(3)
			expect(data.upgrades.nestSlots).to.equal(0)
			expect(type(data.creatures)).to.equal("table")
			expect(data.stats.hatched).to.equal(0)
		end)

		it("a fresh template is DataStore-serializable", function()
			expect(TableUtil.findUnserializable(ProfileTemplate.create())).to.equal(nil)
		end)
	end)
end

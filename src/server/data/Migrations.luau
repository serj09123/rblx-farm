--!strict
-- Ordered schema migrations. `steps[v]` upgrades a profile from version v to v+1.
-- Rules:
--   * Never edit a released step; add a new one and bump ProfileTemplate.CURRENT_VERSION.
--   * Steps must be pure functions of the data (no yields, no services).
--   * Additive fields do not need a step: reconcile() fills them from the template.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local TableUtil = require(Shared.util.TableUtil)

export type Step = (data: { [string]: any }) -> { [string]: any }

local Migrations = {}

Migrations.steps = {
	-- [1] = function(data) -- example: v1 -> v2
	-- 	data.newField = data.oldField or 0
	-- 	data.oldField = nil
	-- 	return data
	-- end,
} :: { [number]: Step }

export type MigrationResult = "ok" | "future" | "missingStep" | "invalid"

-- Upgrades `data` in place to `currentVersion` and reconciles it with `template`.
-- Returns the (possibly new) data table and a result code. "future" means the data
-- was written by a newer server: callers must NOT save over it.
function Migrations.run(
	data: any,
	template: { [string]: any },
	currentVersion: number,
	steps: { [number]: Step }?
): ({ [string]: any }?, MigrationResult)
	if type(data) ~= "table" then
		return nil, "invalid"
	end
	local list = steps or Migrations.steps
	local version = data.schemaVersion
	if type(version) ~= "number" then
		version = 1 -- profiles saved before versioning are treated as v1
	end
	if version > currentVersion then
		return data, "future"
	end
	while version < currentVersion do
		local step = list[version]
		if not step then
			return data, "missingStep"
		end
		data = step(data)
		version += 1
		data.schemaVersion = version
	end
	data.schemaVersion = currentVersion
	TableUtil.reconcile(data, template)
	return data, "ok"
end

return Migrations

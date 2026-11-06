--!nocheck
-- Runs the specs inside Studio with real TestEZ (rojo serve test.project.json, then Play).
-- Requires `wally install` so DevPackages/TestEZ exists.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestEZ = require(ReplicatedStorage:WaitForChild("DevPackages"):WaitForChild("TestEZ"))
TestEZ.TestBootstrap:run({ ServerScriptService:WaitForChild("Tests") })

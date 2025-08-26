--!strict
-- Minimal TestEZ bootstrap. Only runs when a Workspace attribute RunTests=true is set.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
    return
end

local okAttr, shouldRun = pcall(function()
    return workspace:GetAttribute("RunTests") == true
end)
if not okAttr or not shouldRun then
    return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Attempt to find TestEZ in ReplicatedStorage or ServerScriptService
local TestEZModule = ReplicatedStorage:FindFirstChild("TestEZ") or ServerScriptService:FindFirstChild("TestEZ")
if not TestEZModule or not TestEZModule:IsA("ModuleScript") then
    warn("[TestBootstrap] TestEZ not found; skipping tests.")
    return
end

local TestEZ = require(TestEZModule)

local testContainers = {}
-- Place tests under a top-level Folder named 'tests' in DataModel via Rojo
local testsFolder = game:FindFirstChild("tests")
if testsFolder then
    table.insert(testContainers, testsFolder)
end

if #testContainers == 0 then
    warn("[TestBootstrap] No tests folder found.")
    return
end

print("[TestBootstrap] Running TestEZ...")
local results = TestEZ.TestBootstrap:run(testContainers, TestEZ.Reporters.TextReporter)
if results.failureCount and results.failureCount > 0 then
    warn("[TestBootstrap] Tests failed: ", results.failureCount)
else
    print("[TestBootstrap] All tests passed.")
end

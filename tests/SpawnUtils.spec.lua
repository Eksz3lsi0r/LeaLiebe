--!strict
-- TestEZ spec for SpawnUtils

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpawnUtils = require(Shared:WaitForChild("SpawnUtils"))

return function()
    describe("SpawnUtils.getBiomeIndex", function()
        it("returns 1 when no biomes", function()
            expect(SpawnUtils.getBiomeIndex(1, 8, 0)).to.equal(1)
        end)

        it("wraps across segments with given period", function()
            -- With 3 biomes, segmentsPerBiome=2
            expect(SpawnUtils.getBiomeIndex(1, 2, 3)).to.equal(1)
            expect(SpawnUtils.getBiomeIndex(2, 2, 3)).to.equal(1)
            expect(SpawnUtils.getBiomeIndex(3, 2, 3)).to.equal(2)
            expect(SpawnUtils.getBiomeIndex(4, 2, 3)).to.equal(2)
            expect(SpawnUtils.getBiomeIndex(5, 2, 3)).to.equal(3)
            expect(SpawnUtils.getBiomeIndex(6, 2, 3)).to.equal(3)
            expect(SpawnUtils.getBiomeIndex(7, 2, 3)).to.equal(1)
        end)
    end)

    describe("SpawnUtils.pickLaneContent", function()
        local cfg = {
            OverhangChance = 0.1,
            ObstacleChance = 0.2,
            CoinChance = 0.3,
            PowerupChance = 0.1,
        }
        it("chooses Overhang in first range", function()
            expect(SpawnUtils.pickLaneContent(0.05, cfg)).to.equal("Overhang")
        end)
        it("chooses Obstacle next", function()
            expect(SpawnUtils.pickLaneContent(0.15, cfg)).to.equal("Obstacle")
        end)
        it("chooses Coin next", function()
            expect(SpawnUtils.pickLaneContent(0.35, cfg)).to.equal("Coin")
        end)
        it("chooses Powerup next", function()
            expect(SpawnUtils.pickLaneContent(0.65, cfg)).to.equal("Powerup")
        end)
        it("returns nil beyond configured sum", function()
            expect(SpawnUtils.pickLaneContent(0.95, cfg)).to.equal(nil)
        end)
    end)

    describe("SpawnUtils.pickPowerupKind", function()
        it("picks Magnet when r <= cut", function()
            expect(SpawnUtils.pickPowerupKind(0.0, 1, 1)).to.equal("Magnet")
            expect(SpawnUtils.pickPowerupKind(0.5, 1, 1)).to.equal("Magnet")
        end)
        it("picks Shield when r > cut", function()
            expect(SpawnUtils.pickPowerupKind(0.51, 1, 1)).to.equal("Shield")
        end)
        it("handles zero/degenerate weights", function()
            expect(SpawnUtils.pickPowerupKind(0.3, 0, 0)).to.equal("Magnet")
            expect(SpawnUtils.pickPowerupKind(0.3, 0, 1)).to.equal("Shield")
            expect(SpawnUtils.pickPowerupKind(0.0, 2, 0)).to.equal("Magnet")
        end)
    end)
end

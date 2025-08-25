local Constants = {}

Constants.LANES = {
	-6, 0, 6, -- X positions for 3 lanes
}

Constants.PLAYER = {
	BaseSpeed = 28, -- studs/sec forward
	MaxSpeed = 60,
	LaneSwitchSpeed = 24, -- studs/sec lateral
	Acceleration = 0.025, -- per second
}

Constants.SPAWN = {
	SegmentLength = 80, -- studs per segment along +Z
	ViewDistance = 8, -- number of segments to keep spawned ahead
	CleanupBehind = 3, -- number of segments to keep behind before cleanup
	ObstacleChance = 0.45, -- chance per lane per segment to spawn an obstacle
	CoinChance = 0.30, -- chance per lane per segment to spawn a coin if no obstacle
}

Constants.COLLISION = {
	ObstacleDamage = 1, -- simple hit value; can be expanded
	CoinValue = 1,
}

return Constants

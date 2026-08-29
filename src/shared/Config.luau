--!strict
--[[
	Caribbean Beach Survival - shared configuration.

	All gameplay tuning for the Caribbean escape experience lives here.
	Server and client scripts read from this single source of truth.
]]

export type CrabConfig = {
	spawnHoleCount: number,
	spawnInterval: number, -- seconds between crab waves
	maxCrabs: number,
	speed: number,
	damage: number,
	biteCooldown: number,
}

export type OctopusConfig = {
	activeInterval: number, -- seconds between surfacing events
	surfaceDuration: number, -- how long the monster stays up
	tentacleRange: number, -- studs
	speed: number,
	damage: number,
	stunTime: number,
}

export type PirateConfig = {
	patrolCount: number,
	patrolSpeed: number,
	detectionRange: number, -- studs before they give chase
	chaseSpeed: number,
	damage: number,
	patrolCrossingTime: number, -- seconds to clear the beach
}

export type RescueConfig = {
	boatPosition: Vector3,
	bargeTriggerPosition: Vector3,
	escapeRadius: number, -- studs around boat that triggers victory
}

export type GameConfig = {
	survivalTarget: number, -- seconds
	spawnPoint: Vector3,
	playerHealth: number,
	regenerateAfterHits: number,
	victoryToasts: boolean,
	debug: boolean,
}

local Config: {
	Game: GameConfig,
	Crab: CrabConfig,
	Octopus: OctopusConfig,
	Pirate: PirateConfig,
	Rescue: RescueConfig,
	EnemyColors: { [string]: Color3 },
	Objectives: { starter: string, boat: string },
} = {
	Game = {
		survivalTarget = 120, -- survive 2 minutes of beach madness
		spawnPoint = Vector3.new(-60, 0, 0),
		playerHealth = 100,
		regenerateAfterHits = 3, -- how many safe hits heal
		victoryToasts = true,
		debug = false,
	},

	Crab = {
		spawnHoleCount = 8,
		spawnInterval = 9,
		maxCrabs = 14,
		speed = 16,
		damage = 15,
		biteCooldown = 1.2,
	},

	Octopus = {
		activeInterval = 22,
		surfaceDuration = 10,
		tentacleRange = 45,
		speed = 22,
		damage = 30,
		stunTime = 2.5,
	},

	Pirate = {
		patrolCount = 5,
		patrolSpeed = 10,
		detectionRange = 28,
		chaseSpeed = 15,
		damage = 20,
		patrolCrossingTime = 30,
	},

	Rescue = {
		-- rescue boat sits at the FAR end of the beach (positive X)
		boatPosition = Vector3.new(220, 0, 0),
		bargeTriggerPosition = Vector3.new(180, 0, 0),
		escapeRadius = 12,
	},

	EnemyColors = {
		Crab = Color3.fromRGB(190, 40, 40),
		CrabSand = Color3.fromRGB(214, 180, 130),
		Octopus = Color3.fromRGB(120, 20, 160),
		Pirate = Color3.fromRGB(40, 40, 40),
		Boat = Color3.fromRGB(70, 130, 90),
	},

	Objectives = {
		starter = "SURVIVE the beach! Reach the rescue boat at the far end.",
		boat = "BOAT REACHED - escaping!",
	},
}

return Config

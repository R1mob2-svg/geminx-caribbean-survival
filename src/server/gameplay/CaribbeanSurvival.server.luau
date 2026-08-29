--!strict
--[[
	Caribbean Beach Survival - server gameplay.

	Builds the beach world, runs the three enemy threats
	(killer crabs from sand holes, a giant octopus from the
	ocean, and wandering pirates), and drives the escape goal:
	survive the beach, reach the rescue boat at the far end.

	Rojo maps this folder's contents onto a Script under
	ServerScriptService in Studio.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(script.Parent.Parent.Parent:WaitForChild("Shared"):WaitForChild("Config"))

local Beach = Instance.new("Folder")
Beach.Name = "CaribbeanBeach"
Beach.Parent = Workspace

-- Shared mutable threat state guarded on the server only.
local threats = {
	crabs = {},
	octopus = {
		model = nil,
		surfaced = false,
		currentlyAttacking = false,
	},
	pirates = {},
}

local State = {
	escaped = false,
	survivalStarted = false,
}

------------------------------------------------------------
-- WORLD BUILDING
------------------------------------------------------------

local function round(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

local function makePart(parent: Instance, size: Vector3, pos: Vector3, color: Color3, anchor: boolean)
	local p = Instance.new("Part")
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = Enum.Material.Sand
	p.Anchored = anchor
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildBeach()
	-- Sand beach running along the X axis toward the rescue boat.
	local beach = makePart(Beach, Vector3.new(400, 6, 220), Vector3.new(80, -3, 0), Color3.fromRGB(214, 180, 130), true)
	beach.Name = "SandBeach"

	-- Ocean: a wide low body of water on the +Z edge of the beach.
	local ocean = makePart(Beach, Vector3.new(420, 18, 160), Vector3.new(80, -6, 170), Color3.fromRGB(40, 110, 190), true)
	ocean.Name = "Ocean"
	ocean.Material = Enum.Material.Water
	ocean.Transparency = 0.35

	-- Palm trees lining the back of the beach for atmosphere.
	for i = 1, 14 do
		local x = -180 + (i * 26)
		local trunk = makePart(Beach, Vector3.new(1.6, 14, 1.6), Vector3.new(x, 7, -70), Color3.fromRGB(90, 60, 30), true)
		trunk.Material = Enum.Material.Wood
		local frond = makePart(Beach, Vector3.new(14, 1.2, 14), Vector3.new(x, 15, -70), Color3.fromRGB(40, 140, 60), true)
		frond.Material = Enum.Material.Foliage
	end

	-- Sand holes the crabs burst out of, dotted across the mid-beach.
	for i = 1, Config.Crab.spawnHoleCount do
		local x = -160 + (i * 22)
		local z = (i % 3) * 24 - 24
		local hole = makePart(Beach, Vector3.new(8, 1, 8), Vector3.new(x, 0.6, z), Color3.fromRGB(120, 95, 65), true)
		hole.Name = "SandHole_" .. i
	end

	-- Rescue boat at the far end of the beach.
	local boat = makePart(Beach, Vector3.new(38, 8, 14), Config.Rescue.boatPosition, Config.EnemyColors.Boat, true)
	boat.Name = "RescueBoat"
	local hull = makePart(Beach, Vector3.new(26, 4, 12), Config.Rescue.boatPosition - Vector3.new(0, 5, 0), Color3.fromRGB(50, 60, 55), true)
	hull.Material = Enum.Material.Plastic

	-- Start beacon so the player always knows which way to run.
	local beacon = makePart(Beach, Vector3.new(6, 4, 6), Config.Rescue.boatPosition - Vector3.new(0, 2, 0), Color3.fromRGB(250, 220, 60), true)
	beacon.Material = Enum.Material.Neon
	beacon.Name = "BoatBeacon"
end

------------------------------------------------------------
-- KILLER CRABS (from sand holes)
------------------------------------------------------------

local function colorBody(parts: { Part }, tint: Color3)
	for _, p in ipairs(parts) do
		p.Color = tint
	end
end

local function buildCrab(position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "KillerCrab"
	local body = makePart(model, Vector3.new(5, 2.4, 6), position, Config.EnemyColors.Crab, false)
	body.Name = "Body"
	local head = makePart(model, Vector3.new(2.4, 1.6, 2.4), position + Vector3.new(3, 0.8, 0), Color3.fromRGB(120, 220, 190), false)
	head.Name = "Head"
	-- claws
	local clawL = makePart(model, Vector3.new(2, 1, 2), position + Vector3.new(1, 0.6, -3), Config.EnemyColors.Crab, false)
	clawL.Name = "ClawLeft"
	local clawR = makePart(model, Vector3.new(2, 1, 2), position + Vector3.new(1, 0.6, 3), Config.EnemyColors.Crab, false)
	clawR.Name = "ClawRight"

	model.PrimaryPart = body
	model:SetPrimaryPartCFrame(CFrame.new(position))
	return model
end

local function spawnCrabWave()
	if #threats.crabs >= Config.Crab.maxCrabs then
		return
	end
	local sign = math.random(0, 1) == 1 and 1 or -1
	local x = math.random(-150, 120)
	local z = sign * math.random(10, 40)
	local crab = buildCrab(Vector3.new(x, 1, z))
	crab.Parent = Beach
	threats.crabs[#threats.crabs + 1] = crab

	-- pop-up effect out of the sand hole
	local pop = Instance.new("Sound")
	pop.SoundId = "rbxassetid://0" -- placeholder; original audio not bundled
	pop.Parent = crab
	pop:Destroy()
end

local function updateCrabs(dt: number, escapeRadius: number)
	local boatPos = Config.Rescue.boatPosition
	for _, crab in ipairs(threats.crabs) do
		local primary = crab.PrimaryPart
		if primary then
			local target = State.escaped and boatPos or Workspace:FindFirstChild("Camera") and Workspace.Camera.CFrame.Position or boatPos
			-- Crabs skitter toward the nearest player.
			local nearest, nearestDist = nil, math.huge
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				if char and char:FindFirstChild("HumanoidRootPart") then
					local dist = (char.HumanoidRootPart.Position - primary.Position).Magnitude
					if dist < nearestDist then
						nearestDist = dist
						nearest = char.HumanoidRootPart
					end
				end
			end
			if nearest then
				local dir = (nearest.Position - primary.Position).Unit
				primary.CFrame = primary.CFrame:Lerp(nearest.Position, dt * Config.Crab.speed)
				primary.CFrame = CFrame.lookAt(primary.Position, nearest.Position)
			end
		end
	end
end

-- Cleanup when a crab dies or the game ends.
Debris:AddItem(Beach, math.huge)

------------------------------------------------------------
-- GIANT OCTOPUS (from the ocean)
------------------------------------------------------------

local function buildOctopus(): Model
	local model = Instance.new("Model")
	model.Name = "GiantOctopus"
	local body = makePart(model, Vector3.new(16, 12, 16), Vector3.new(60, -4, 210), Config.EnemyColors.Octopus, true)
	body.Name = "Body"
	-- tentacles
	for i = 1, 6 do
		local tent = makePart(model, Vector3.new(2, 18, 2), Vector3.new(60 + math.cos(i) * 10, -10, 210 + math.sin(i) * 10), Config.EnemyColors.Octopus, true)
		tent.Name = "Tentacle" .. i
		tent.Material = Enum.Material.SmoothPlastic
	end
	-- eye
	local eye = makePart(model, Vector3.new(4, 3, 0.6), Vector3.new(60, -6, 198), Color3.fromRGB(255, 255, 255), true)
	eye.Name = "Eye"
	model.PrimaryPart = body
	return model
end

local function octopusAttack(dt: number)
	local oc = threats.octopus
	if oc.currentlyAttacking then
		if oc.surfaced then
			oc.surfaced = false
			oc.currentlyAttacking = false
		else
			oc.surfaced = true
			oc.currentlyAttacking = false
		end
	end

	if oc.surfaced and oc.model then
		local body = oc.model.PrimaryPart
		if body then
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				if char and char:FindFirstChild("HumanoidRootPart") then
					local hrp = char.HumanoidRootPart
					local dist = (hrp.Position - Config.Rescue.boatPosition).Magnitude
					if dist > Config.Octopus.tentacleRange then
						-- near the shallows: smack an incoming runner
					end
				end
			end
		end
	end
end

------------------------------------------------------------
-- PIRATES (prowling the shore)
------------------------------------------------------------

local function buildPirate(startPos: Vector3, axis: string): Model
	local model = Instance.new("Model")
	model.Name = "Pirate"
	-- body, hat, peg leg
	local body = makePart(model, Vector3.new(4, 7, 3), startPos, Config.EnemyColors.Pirate, false)
	body.Name = "Body"
	local hat = makePart(model, Vector3.new(4.4, 1.6, 3.6), startPos + Vector3.new(0, 4, 0), Color3.fromRGB(20, 20, 20), false)
	hat.Name = "Hat"
	local leg = makePart(model, Vector3.new(1.6, 4, 1.6), startPos + Vector3.new(0, -4, 1.2), Color3.fromRGB(150, 120, 70), false)
	leg.Name = "PegLeg"
	model.PrimaryPart = body
	model:SetAttribute("PatrolAxis", axis)
	return model
end

local function updatePirates(dt: number)
	for _, pirate in ipairs(threats.pirates) do
		local primary = pirate.PrimaryPart
		if primary then
			-- find nearest player
			local nearest, nearestDist = nil, math.huge
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				if char and char:FindFirstChild("HumanoidRootPart") then
					local hrp = char.HumanoidRootPart
					local dist = (hrp.Position - primary.Position).Magnitude
					if dist < nearestDist then
						nearestDist = dist
						nearest = hrp
					end
				end
			end

			local axis = pirate:GetAttribute("PatrolAxis")
			if nearest and nearestDist < Config.Pirate.detectionRange then
				-- Chase the player.
				local dir = (nearest.Position - primary.Position).Unit
				primary.CFrame = primary.CFrame:Lerp(primary.Position + dir * Config.Pirate.chaseSpeed * dt, 1)
				primary.CFrame = CFrame.lookAt(primary.Position, nearest.Position)
			else
				-- Patrol laterally along the shore.
				local pos = primary.Position
				if axis == "Z" then
					pos = Vector3.new(pos.X, pos.Y, pos.Z + math.sin(os.clock() * 0.6) * (Config.Pirate.patrolSpeed / 2))
				else
					pos = Vector3.new(pos.X + math.sin(os.clock() * 0.5) * (Config.Pirate.patrolSpeed / 2), pos.Y, pos.Z)
				end
				primary.CFrame = CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0))
			end
		end
	end
end

------------------------------------------------------------
-- DAMAGE + ESCAPE
------------------------------------------------------------

local function damagePlayer(character: Model, amount: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(amount)
	end
end

local function checkEscape()
	-- Player who reaches the boat's escape radius wins.
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local hrp = char.HumanoidRootPart
			if (hrp.Position - Config.Rescue.boatPosition).Magnitude <= Config.Rescue.escapeRadius then
				if not State.escaped then
					State.escaped = true
					for _, gp in ipairs(Players:GetPlayers()) do
						local hud = gp:FindFirstChildOfClass("PlayerGui"):FindFirstChild("Objective")
						if hud then
							hud.Text = Config.Objectives.boat
						end
						if gp:FindFirstChildOfClass("PlayerGui"):FindFirstChild("VictoryOverlay") then
							gp:FindFirstChildOfClass("PlayerGui"):FindFirstChild("VictoryOverlay").Visible = true
						end
					end
				end
				-- freeze threats once safely aboard
				for _, crab in ipairs(threats.crabs) do
					crab.PrimaryPart.Anchored = true
				end
			end
		end
	end
end

------------------------------------------------------------
-- GAME LOOP
------------------------------------------------------------

local function startLoop()
	buildBeach()

	local ocModel = buildOctopus()
	ocModel.Parent = Beach
	threats.octopus.model = ocModel

	for i = 1, Config.Pirate.patrolCount do
		local z = -30 + (i * 12)
		local pirate = buildPirate(Vector3.new(-120 + i * 55, 1, z), (i % 2 == 0) and "X" or "Z")
		pirate.Parent = Beach
		threats.pirates[#threats.pirates + 1] = pirate
	end

	local elapsed = 0
	local crabTimer = 0
	local octoTimer = 0

	RunService.Heartbeat:Connect(function(dt)
		if State.escaped then
			return
		end
		elapsed += dt
		crabTimer += dt
		octoTimer += dt

		if crabTimer >= Config.Crab.spawnInterval then
			crabTimer = 0
			spawnCrabWave()
		end

		updateCrabs(dt, Config.Rescue.escapeRadius)
		updatePirates(dt)

		if octoTimer >= Config.Octopus.activeInterval then
			octoTimer = 0
			threats.octopus.currentlyAttacking = true
			threats.octopus.surfaced = true
		end
		octopusAttack(dt)

		checkEscape()
	end)
end

------------------------------------------------------------
-- PLAYER JOIN: spawn and objective HUD
------------------------------------------------------------

local function onPlayerAdded(p: Player)
	p.CharacterAdded:Connect(function(char)
		local hrp = char:WaitForChild("HumanoidRootPart")
		hrp.Position = Config.Game.spawnPoint
		State.survivalStarted = true

		task.delay(1, function()
			local h = char:FindFirstChildOfClass("Humanoid")
			if h then
				h.Health = Config.Game.playerHealth
			end
		end)
	end)

	-- objective banner (client listens for text)
	local plrGui = p:WaitForChild("PlayerGui")
	local objective = Instance.new("TextLabel")
	objective.Name = "Objective"
	objective.Size = UDim2.new(1, 0, 0, 44)
	objective.Position = UDim2.new(0, 0, 0, 8)
	objective.BackgroundTransparency = 0.5
	objective.BackgroundColor3 = Color3.fromRGB(20, 30, 60)
	objective.TextColor3 = Color3.fromRGB(255, 240, 180)
	objective.Text = Config.Objectives.starter
	objective.Font = Enum.Font.Highway
	objective.TextSize = 18
	objective.Parent = plrGui
end

Players.PlayerAdded:Connect(onPlayerAdded)

startLoop()

print("[CaribbeanSurvival] Server ready. Reach the rescue boat at X=220!")

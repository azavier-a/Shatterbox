--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)

--[=[
	@interface PuppetDataType

	An array that holds information about a given Puppet.

	On the client side, only [1] the Puppet Part exists. On the server side, I highly suggest you do not touch [2], [3], or [4].

	.1 Part -- The puppet voxel part.
	.2 (doNotSignal : boolean?) -> () -- Function that properly destroys the voxel. I will be changing this in the future, don't worry.
	.3 RBXScriptSignal -- Connection that listens for the Destroying event on the voxel. Doesn't exist if ObjectCache is enabled.
	.4 number -- Timeout until this voxel becomes anchored

	@within Shatterbox
]=]

local RunService = game:GetService("RunService")

local isServer = RunService:IsServer()

local components = script.Parent
local core = components.Parent
local src = core.Parent
local lib = core:WaitForChild("lib")

--local Types = require(src:WaitForChild("Types"))

local Settings = require(src:WaitForChild("Settings"))
local PUPPET_TWEEN_MODE = Settings.PUPPET_TWEEN_MODE
local USE_OBJECT_CACHE = Settings.USE_OBJECT_CACHE

local IndestructibleTag = Settings.INDESTRUCTIBLE_TAG

local DirtyGroupLogic = require(components:WaitForChild("DirtyGroupLogic"))
local DestroyPart = DirtyGroupLogic.DestroyPart

local PartOperations = require(lib:WaitForChild("PartOperations"))
local SerializedPartInstance = PartOperations.SerializedPartInstance
local DeserializedPartInstance = PartOperations.DeserializedPartInstance

local State = require(components.Parent:WaitForChild("State"))
local IsPuppet = State.IsPuppet

local Blink = State.Blink

local CachedParts = State.CachedParts

local mapContainer = State.MapContainer

local Puppets = State.Puppets
local CreatePuppetQueue = State.CreatePuppetQueue
local PuppetsLerpData = State.PuppetsLerpData


local WorldAnchor
if PUPPET_TWEEN_MODE == "TRANSFORM" then
	WorldAnchor = Instance.new("Part")
	WorldAnchor.Anchored = true
	WorldAnchor.CanCollide = false
	WorldAnchor.CanTouch = false
	WorldAnchor.CanQuery = false
	WorldAnchor.Transparency = 1
	WorldAnchor.CFrame = CFrame.identity
	WorldAnchor.Parent = workspace
end


local TAU = 2*math.pi
local RAD2U8 = 40.5845104884

local function WriteFloatI25(b, bitOff, x)
	local S = 0
	if x < 0 then
		S = 1
		x = -x
	end
	buffer.writebits(b, bitOff, 1, S)
	buffer.writebits(b, bitOff + 1, 24, math.round(x * 1000))
end

local function ReadFloatI25(b, bitOff)
	local X = buffer.readbits(b, bitOff + 1, 24) * 0.001
	return buffer.readbits(b, bitOff, 1) == 0 and X or -X
end

local U82RAD = 0.0246399423811
local PRECISE_45_DEGREES = {}
PRECISE_45_DEGREES[32] = math.pi * 0.25
PRECISE_45_DEGREES[64] = math.pi * 0.5
PRECISE_45_DEGREES[96] = math.pi * 0.75
PRECISE_45_DEGREES[128] = math.pi
PRECISE_45_DEGREES[159] = -PRECISE_45_DEGREES[96]
PRECISE_45_DEGREES[191] = -PRECISE_45_DEGREES[64]
PRECISE_45_DEGREES[223] = -PRECISE_45_DEGREES[32]
PRECISE_45_DEGREES[255] = 0

local function ReadRadianU8(b, bitOff)
	local X = buffer.readbits(b, bitOff, 8)
	return PRECISE_45_DEGREES[X] or (X * U82RAD)
end



local PuppeteerLogic = {}
PuppeteerLogic.WorldAnchor = WorldAnchor



function PuppeteerLogic.Puppeteer(voxel : Part) : number
	assert(isServer, "This function can only be called from the server")

	voxel.Anchored = false

	local isAlreadyPuppet = IsPuppet(voxel)
	if isAlreadyPuppet then return isAlreadyPuppet end

	voxel.Parent = mapContainer

	local s, e = pcall(voxel.SetNetworkOwner, voxel, nil)
	if not s then
		warn("Failed to set the network owner of the Puppet, is it welded to an anchored part?\n" .. e)
	end

	local noSleepCon : RBXScriptConnection
	noSleepCon = RunService.Heartbeat:Connect(function()
		voxel:ApplyImpulse(Vector3.yAxis * -0.00001)
	end)


	local OldPuppetData = Puppets[State.PuppetNextIndex]

	if OldPuppetData then
		if not USE_OBJECT_CACHE then
			OldPuppetData[3]:Disconnect()
		end
		OldPuppetData[2](true)
		DestroyPart(OldPuppetData[1])
	end

	table.insert(CreatePuppetQueue, voxel)
	local QueueInsertedIndex = #CreatePuppetQueue
	local PuppetInsertedIndex = State.PuppetNextIndex

	local PuppetData = {
		voxel,
		function(doNotSignal) -- I know i shouldn't be using an anonymous function, ill change it later
			noSleepCon:Disconnect()

			-- if this server side voxel is queued for client-side creation, remove it from that queue
			local found
			for i = 1, QueueInsertedIndex do
				if CreatePuppetQueue[i] == voxel then
					found = i
					break
				end
			end

			if found then
				table.remove(CreatePuppetQueue, found)
			end

			if doNotSignal then return end

			-- signal to the client that the puppet needs to be destroyed and remove it (probably will batch these in the future)

			Puppets[PuppetInsertedIndex] = nil
			PuppetsLerpData[PuppetInsertedIndex] = nil
			Blink.DestroyPuppet.FireAll(PuppetInsertedIndex)
		end
	}

	if not USE_OBJECT_CACHE then
		PuppetData[3] = voxel.Destroying:Once(PuppetData[2])
	end

	PuppetData[4] = 0 -- The sleep anchoring timeout


	Puppets[PuppetInsertedIndex] = PuppetData
	PuppetsLerpData[PuppetInsertedIndex] = {}
	State.PuppetNextIndex += 1
	if State.PuppetNextIndex > Settings.PuppetMaxCount then
		State.PuppetNextIndex = 1
	end

	return PuppetInsertedIndex
end



function PuppeteerLogic.DestroyPuppet(index)
	DestroyPart(Puppets[index][1])
	Puppets[index] = nil
	PuppetsLerpData[index] = nil
end



function PuppeteerLogic.GetPuppetAsync(puppetID : number|string, waitCount : number?) : Part?
	puppetID = tonumber(puppetID)
	waitCount = waitCount or 20
	local PuppetPart : Part = Puppets[puppetID] and Puppets[puppetID][1]
	if not PuppetPart then
		local i = 1
		repeat
			RunService.Heartbeat:Wait()
			PuppetPart = Puppets[puppetID] and Puppets[puppetID][1]
			i += 1
		until PuppetPart or i > waitCount
	end

	return PuppetPart
end



local function DeserializedPuppet(serialPuppet)
	local Part = DeserializedPartInstance(serialPuppet, CachedParts)

	Part.Anchored = true

	Part:AddTag(IndestructibleTag)

	Part.Parent = mapContainer

	return Part
end
PuppeteerLogic.DeserializedPuppet = DeserializedPuppet



function PuppeteerLogic.CreatePuppetsFromServer(puppets, startIndex)
	local index = startIndex
	--debug.profilebegin("Create Puppets")
	for _, serialPuppet in ipairs(puppets) do
		local OldPuppetData = Puppets[index]
		if OldPuppetData then
			DestroyPart(OldPuppetData[1])
			PuppetsLerpData[index] = nil
		end

		local Part = DeserializedPuppet(serialPuppet)

		--
		if PUPPET_TWEEN_MODE == "TRANSFORM" then
			local Motor6D = Instance.new("Motor6D")
			Motor6D.Enabled = false

			Motor6D.Transform = serialPuppet.CFrame
			Motor6D.Part0 = WorldAnchor
			Motor6D.Part1 = Part
			Motor6D.Parent = Part
		end
		--]]

		Puppets[index] = { Part }

		index += 1
		if index > Settings.PuppetMaxCount then
			index = 1
		end
	end
	--FakePuppetOverrideIndex = State.PuppetNextIndex

	if USE_OBJECT_CACHE then
		State.ScheduledUpdate = false
		CachedParts:Update()
	end
end



function PuppeteerLogic.ReplicatePuppetStatesFromServer(puppetStatesBuffer, stepDelta)
	State.ClientPuppetStepDelta = stepDelta

	local bitLength = buffer.len(puppetStatesBuffer)

	local i = 1
	local updatedPuppets, updatedStates = {}, {}

	bitLength *= 8
	local bitOffset = 0

	local clientCamPos = workspace.CurrentCamera.CFrame.Position

	local sqLimit = Settings.ClientTweenDistanceLimit ^ 2
	local doNotTweenPuppets = not Settings.ClientTweenPuppets
	while bitOffset < bitLength do
		local index = buffer.readbits(puppetStatesBuffer, bitOffset + 99, 13)
		local puppetData = Puppets[index]
		if puppetData then
			local cframe = CFrame.new(
				ReadFloatI25(puppetStatesBuffer, bitOffset),
				ReadFloatI25(puppetStatesBuffer, bitOffset + 25),
				ReadFloatI25(puppetStatesBuffer, bitOffset + 50)
			) * CFrame.fromEulerAngles(
				ReadRadianU8(puppetStatesBuffer, bitOffset + 75),
				ReadRadianU8(puppetStatesBuffer, bitOffset + 83),
				ReadRadianU8(puppetStatesBuffer, bitOffset + 91)
			)

			local toPlr = clientCamPos - cframe.Position
			-- Puppets outside of the interpolation distance limit are moved directly to their updated position in bulk (or if the interpolation setting is disabled)
			if doNotTweenPuppets or (toPlr.X^2 + toPlr.Y^2 + toPlr.Z^2 >= sqLimit) then
				if PuppetsLerpData[index] then
					PuppetsLerpData[index] = nil
				end
				--puppetData[1].CFrame = cframe
				if PUPPET_TWEEN_MODE == "TRANSFORM" then
					local Motor6D = puppetData[1]:FindFirstChildWhichIsA("Motor6D")
					if not Motor6D.Enabled then
						Motor6D.Enabled = true
						puppetData[1].Anchored = false
					end
					Motor6D.Transform = cframe
				else
					updatedPuppets[i] = puppetData[1]
					updatedStates[i] = cframe
					i += 1
				end
			else
				PuppetsLerpData[index] = {
					puppetData[1].CFrame,
					cframe,
					0
				}
			end
		end

		bitOffset += 112
	end

	if i > 1 then
		workspace:BulkMoveTo(updatedPuppets, updatedStates, Enum.BulkMoveMode.FireCFrameChanged)
	end
end



function PuppeteerLogic.PuppeteerHeartbeatBehavior(deltaTime)
	local PQL = #CreatePuppetQueue
	if PQL > 0 then
		local toReplicate = table.create(PQL)
		for i, puppetToCreate in ipairs(CreatePuppetQueue) do
			toReplicate[i] = SerializedPartInstance(puppetToCreate)
		end
		table.clear(CreatePuppetQueue)
		Blink.CreatePuppets.FireAll(toReplicate, State.PuppetNextIndex - PQL)
	end

	State.PuppetTimeAccumulation += deltaTime
	local P = 1 / Settings.PuppetReplicationFrequency
	if State.PuppetTimeAccumulation >= P then
		repeat
			State.PuppetTimeAccumulation -= P
		until State.PuppetTimeAccumulation < P

		for i, puppetData in pairs(Puppets) do -- every time the period is reached, push all available voxel CFrames to their state replication queue
			local puppetVoxel = puppetData[1]

			if puppetVoxel.Anchored then continue end

			if puppetVoxel.AssemblyLinearVelocity.Magnitude <= Settings.PuppetSleepVelocity then
				local d = puppetData[4] + deltaTime
				if d >= Settings.PuppetAnchorTimeout then
					puppetVoxel.Anchored = true
					table.insert(PuppetsLerpData[i], 1, puppetVoxel.CFrame) -- replicate the final resting state of this voxel
					puppetData[4] = 0
				else
					puppetData[4] = d
				end
				continue
			end

			puppetData[4] = 0

			table.insert(PuppetsLerpData[i], 1, puppetVoxel.CFrame)
		end

		local AvailablePuppets = {}
		local StartIndex = State.PuppetNextReplicationIndex
		while #AvailablePuppets < 70 do
			local ReplicationIndex = State.PuppetNextReplicationIndex
			State.PuppetNextReplicationIndex += 1
			if State.PuppetNextReplicationIndex > Settings.PuppetMaxCount then
				State.PuppetNextReplicationIndex = 1
			end
			if State.PuppetNextReplicationIndex == StartIndex then break end

			local puppetData = Puppets[ReplicationIndex]
			if not puppetData then continue end

			if #PuppetsLerpData[ReplicationIndex] == 0 then continue end

			if table.find(CreatePuppetQueue, puppetData[1]) then continue end

			table.insert(AvailablePuppets, ReplicationIndex)
		end

		local countToReplicate = #AvailablePuppets
		if countToReplicate > 0 then
			local puppetStates = buffer.create(countToReplicate * 14)

			for i, ReplicationIndex in ipairs(AvailablePuppets) do
				--local puppetVoxel = Puppets[ReplicationIndex][1]

				--[[
				i25 - X
				i25 - Y
				i25 - Z

				u8 - aX
				u8 - aY
				u8 - aZ

				u13 - Puppet ID

				Total : 112 bits per puppet state
				]]

				local bufferBitOffset = (i - 1) * 112

				local cframe = table.remove(PuppetsLerpData[ReplicationIndex])
				WriteFloatI25(puppetStates, bufferBitOffset, cframe.X)
				WriteFloatI25(puppetStates, bufferBitOffset + 25, cframe.Y)
				WriteFloatI25(puppetStates, bufferBitOffset + 50, cframe.Z)

				local rX, rY, rZ = cframe:ToEulerAngles()
				buffer.writebits(puppetStates, bufferBitOffset + 75, 8, math.round((rX % TAU) * RAD2U8))
				buffer.writebits(puppetStates, bufferBitOffset + 83, 8, math.round((rY % TAU) * RAD2U8))
				buffer.writebits(puppetStates, bufferBitOffset + 91, 8, math.round((rZ % TAU) * RAD2U8))

				buffer.writebits(puppetStates, bufferBitOffset + 99, 13, ReplicationIndex)
			end

			local stepDelta = 0
			for _, queuedCFrames in pairs(PuppetsLerpData) do
				if #queuedCFrames == 0 then continue end
				stepDelta += 1
			end
			stepDelta = stepDelta > 70 and stepDelta // 70 or 1

			Blink.ReplicatePuppetStates.FireAll(puppetStates, stepDelta)
		end
	end
end


if isServer then return PuppeteerLogic end


-- Client side interpolation loop that "tweens" every puppet voxel and moves them in bulk
RunService.PreRender:Connect(function(deltaTime)
	if not next(PuppetsLerpData) then return end

	--debug.profilebegin("Direct set CFrame Puppets")
	local P = State.ClientPuppetStepDelta / Settings.PuppetReplicationFrequency

	local i = 1
	local puppets, interpolatedPositions, finishedLerps = {}, {}, {}
	for index, lerpData in pairs(PuppetsLerpData) do
		local d = lerpData[3] + deltaTime
		if d >= P then
			d = P
			table.insert(finishedLerps, index)
		else
			lerpData[3] = d
		end

		local newPos = d < P and lerpData[1]:Lerp(lerpData[2], d / P) or lerpData[2]

		if PUPPET_TWEEN_MODE == "TRANSFORM" then
			local Motor6D = Puppets[index][1]:FindFirstChildWhichIsA("Motor6D")
			if not Motor6D.Enabled then
				Motor6D.Enabled = true
				Puppets[index][1].Anchored = false
			end
			Motor6D.Transform = newPos
		else
			interpolatedPositions[i] = newPos
			puppets[i] = Puppets[index][1]
			i += 1
		end
	end

	for _, index in ipairs(finishedLerps) do
		PuppetsLerpData[index] = nil
	end

	if i > 1 then
		workspace:BulkMoveTo(puppets, interpolatedPositions, Enum.BulkMoveMode.FireCFrameChanged)
	end
	--debug.profileend()
end)



--[[
function Shatterbox.FakeClientPuppets(fakePuppets : { Part })
	for _, fake in ipairs(fakePuppets) do
		local OldPuppetData = Puppets[FakePuppetOverrideIndex]
		if OldPuppetData then
			DestroyPart(OldPuppetData[1])
			PuppetsLerpData[FakePuppetOverrideIndex] = nil
		end

		Puppets[FakePuppetOverrideIndex] = { fake }

		FakePuppetOverrideIndex += 1
		if FakePuppetOverrideIndex > Settings.PuppetMaxCount then
			FakePuppetOverrideIndex = 1
		end
	end
end
--]]



return PuppeteerLogic
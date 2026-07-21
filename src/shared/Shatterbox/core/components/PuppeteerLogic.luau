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

local PartOperations = require(lib:WaitForChild("PartOperations"))

local DirtyGroupLogic = require(components:WaitForChild("DirtyGroupLogic"))

local State = require(components.Parent:WaitForChild("State"))
local Blink = State.Blink


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


local WorldAnchor
if Settings.PUPPET_TWEEN_MODE == "TRANSFORM" then
	WorldAnchor = Instance.new("Part")
	WorldAnchor.Anchored = true
	WorldAnchor.CanCollide = false
	WorldAnchor.CanTouch = false
	WorldAnchor.CanQuery = false
	WorldAnchor.Transparency = 1
	WorldAnchor.CFrame = CFrame.identity
	WorldAnchor.Parent = workspace
end
PuppeteerLogic.WorldAnchor = WorldAnchor



function PuppeteerLogic.Puppeteer(voxel : Part) : number
	assert(isServer, "This function can only be called from the server")

	voxel.Anchored = false

	local isAlreadyPuppet = State.IsPuppet(voxel)
	if isAlreadyPuppet then return isAlreadyPuppet end

	voxel.Parent = State.MapContainer

	local s, e = pcall(voxel.SetNetworkOwner, voxel, nil)
	if not s then
		warn("Failed to set the network owner of the Puppet, is it welded to an anchored part?\n" .. e)
	end

	local noSleepCon : RBXScriptConnection
	noSleepCon = RunService.Heartbeat:Connect(function()
		voxel:ApplyImpulse(Vector3.yAxis * -0.00001)
	end)


	local OldPuppetData = State.Puppets[State.PuppetNextIndex]

	if OldPuppetData then
		if not Settings.USE_OBJECT_CACHE then
			OldPuppetData[3]:Disconnect()
		end
		OldPuppetData[2](true)
		DirtyGroupLogic.DestroyPart(OldPuppetData[1])
	end

	table.insert(State.CreatePuppetQueue, voxel)
	local QueueInsertedIndex = #State.CreatePuppetQueue
	local PuppetInsertedIndex = State.PuppetNextIndex

	local PuppetData = {
		voxel,
		function(doNotSignal) -- I know i shouldn't be using an anonymous function, ill change it later
			noSleepCon:Disconnect()

			-- if this server side voxel is queued for client-side creation, remove it from that queue
			local found
			for i = 1, QueueInsertedIndex do
				if State.CreatePuppetQueue[i] == voxel then
					found = i
					break
				end
			end

			if found then
				table.remove(State.CreatePuppetQueue, found)
			end

			if doNotSignal then return end

			-- signal to the client that the puppet needs to be destroyed and remove it (probably will batch these in the future)

			State.Puppets[PuppetInsertedIndex] = nil
			State.PuppetsLerpData[PuppetInsertedIndex] = nil
			Blink.DestroyPuppet.FireAll(PuppetInsertedIndex)
		end
	}

	if not Settings.USE_OBJECT_CACHE then
		PuppetData[3] = voxel.Destroying:Once(PuppetData[2])
	end

	PuppetData[4] = 0 -- The sleep anchoring timeout


	State.Puppets[PuppetInsertedIndex] = PuppetData
	State.PuppetsLerpData[PuppetInsertedIndex] = {}
	State.PuppetNextIndex += 1
	if State.PuppetNextIndex > Settings.PuppetMaxCount then
		State.PuppetNextIndex = 1
	end

	return PuppetInsertedIndex
end



function PuppeteerLogic.DestroyPuppet(index)
	DirtyGroupLogic.DestroyPart(State.Puppets[index][1])
	State.Puppets[index] = nil
	State.PuppetsLerpData[index] = nil
end



function PuppeteerLogic.GetPuppetAsync(puppetID : number|string, waitCount : number?) : Part?
	puppetID = tonumber(puppetID)
	waitCount = waitCount or 20
	local PuppetPart : Part = State.Puppets[puppetID] and State.Puppets[puppetID][1]
	if not PuppetPart then
		local i = 1
		repeat
			RunService.Heartbeat:Wait()
			PuppetPart = State.Puppets[puppetID] and State.Puppets[puppetID][1]
			i += 1
		until PuppetPart or i > waitCount
	end

	return PuppetPart
end



local function DeserializedPuppet(serialPuppet)
	local Part = PartOperations.DeserializedPartInstance(serialPuppet, State.CachedParts)

	Part.Anchored = true

	Part:AddTag(Settings.INDESTRUCTIBLE_TAG)

	Part.Parent = State.MapContainer

	return Part
end
PuppeteerLogic.DeserializedPuppet = DeserializedPuppet



function PuppeteerLogic.CreatePuppetsFromServer(puppets, startIndex)
	local index = startIndex
	--debug.profilebegin("Create Puppets")
	for _, serialPuppet in ipairs(puppets) do
		local OldPuppetData = State.Puppets[index]
		if OldPuppetData then
			DirtyGroupLogic.DestroyPart(OldPuppetData[1])
			State.PuppetsLerpData[index] = nil
		end

		local Part = DeserializedPuppet(serialPuppet)

		--
		if Settings.PUPPET_TWEEN_MODE == "TRANSFORM" then
			local Motor6D = Instance.new("Motor6D")
			Motor6D.Enabled = false

			Motor6D.Transform = serialPuppet.CFrame
			Motor6D.Part0 = WorldAnchor
			Motor6D.Part1 = Part
			Motor6D.Parent = Part
		end
		--]]

		State.Puppets[index] = { Part }

		index += 1
		if index > Settings.PuppetMaxCount then
			index = 1
		end
	end
	--FakePuppetOverrideIndex = State.PuppetNextIndex

	if Settings.USE_OBJECT_CACHE then
		State.ScheduledUpdate = false
		State.CachedParts:Update()
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
		local puppetData = State.Puppets[index]
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
				if State.PuppetsLerpData[index] then
					State.PuppetsLerpData[index] = nil
				end
				--puppetData[1].CFrame = cframe
				if Settings.PUPPET_TWEEN_MODE == "TRANSFORM" then
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
				State.PuppetsLerpData[index] = {
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



function PuppeteerLogic.Heartbeat(deltaTime)
	local PQL = #State.CreatePuppetQueue
	if PQL > 0 then
		local toReplicate = table.create(PQL)
		for i, puppetToCreate in ipairs(State.CreatePuppetQueue) do
			toReplicate[i] = PartOperations.SerializedPartInstance(puppetToCreate)
		end
		table.clear(State.CreatePuppetQueue)
		Blink.CreatePuppets.FireAll(toReplicate, State.PuppetNextIndex - PQL)
	end

	State.PuppetTimeAccumulation += deltaTime
	local P = 1 / Settings.PuppetReplicationFrequency
	if State.PuppetTimeAccumulation >= P then
		repeat
			State.PuppetTimeAccumulation -= P
		until State.PuppetTimeAccumulation < P

		for i, puppetData in pairs(State.Puppets) do -- every time the period is reached, push all available voxel CFrames to their state replication queue
			local puppetVoxel = puppetData[1]

			if puppetVoxel.Anchored then continue end

			if puppetVoxel.AssemblyLinearVelocity.Magnitude <= Settings.PuppetSleepVelocity then
				local d = puppetData[4] + deltaTime
				if d >= Settings.PuppetAnchorTimeout then
					puppetVoxel.Anchored = true
					table.insert(State.PuppetsLerpData[i], 1, puppetVoxel.CFrame) -- replicate the final resting state of this voxel
					puppetData[4] = 0
				else
					puppetData[4] = d
				end
				continue
			end

			puppetData[4] = 0

			table.insert(State.PuppetsLerpData[i], 1, puppetVoxel.CFrame)
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

			local puppetData = State.Puppets[ReplicationIndex]
			if not puppetData then continue end

			if #State.PuppetsLerpData[ReplicationIndex] == 0 then continue end

			if table.find(State.CreatePuppetQueue, puppetData[1]) then continue end

			table.insert(AvailablePuppets, ReplicationIndex)
		end

		local countToReplicate = #AvailablePuppets
		if countToReplicate > 0 then
			local puppetStates = buffer.create(countToReplicate * 14)

			for i, ReplicationIndex in ipairs(AvailablePuppets) do
				--local puppetVoxel = State.Puppets[ReplicationIndex][1]

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

				local cframe = table.remove(State.PuppetsLerpData[ReplicationIndex])
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
			for _, queuedCFrames in pairs(State.PuppetsLerpData) do
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
	if not next(State.PuppetsLerpData) then return end

	--debug.profilebegin("Direct set CFrame Puppets")
	local P = State.ClientPuppetStepDelta / Settings.PuppetReplicationFrequency

	local i = 1
	local puppets, interpolatedPositions, finishedLerps = {}, {}, {}
	for index, lerpData in pairs(State.PuppetsLerpData) do
		local d = lerpData[3] + deltaTime
		if d >= P then
			d = P
			table.insert(finishedLerps, index)
		else
			lerpData[3] = d
		end

		local newPos = d < P and lerpData[1]:Lerp(lerpData[2], d / P) or lerpData[2]

		if Settings.PUPPET_TWEEN_MODE == "TRANSFORM" then
			local Motor6D = State.Puppets[index][1]:FindFirstChildWhichIsA("Motor6D")
			if not Motor6D.Enabled then
				Motor6D.Enabled = true
				State.Puppets[index][1].Anchored = false
			end
			Motor6D.Transform = newPos
		else
			interpolatedPositions[i] = newPos
			puppets[i] = State.Puppets[index][1]
			i += 1
		end
	end

	for _, index in ipairs(finishedLerps) do
		State.PuppetsLerpData[index] = nil
	end

	if i > 1 then
		workspace:BulkMoveTo(puppets, interpolatedPositions, Enum.BulkMoveMode.FireCFrameChanged)
	end
	--debug.profileend()
end)



--[[
function Shatterbox.FakeClientPuppets(fakePuppets : { Part })
	for _, fake in ipairs(fakePuppets) do
		local OldPuppetData = State.Puppets[FakePuppetOverrideIndex]
		if OldPuppetData then
			DirtyGroupLogic.DestroyPart(OldPuppetData[1])
			State.PuppetsLerpData[FakePuppetOverrideIndex] = nil
		end

		State.Puppets[FakePuppetOverrideIndex] = { fake }

		FakePuppetOverrideIndex += 1
		if FakePuppetOverrideIndex > Settings.PuppetMaxCount then
			FakePuppetOverrideIndex = 1
		end
	end
end
--]]



return PuppeteerLogic
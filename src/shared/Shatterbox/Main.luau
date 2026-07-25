--!native
--!optimize 2

-- Shatterbox dev build July 25, 2026

--#selene: allow(incorrect_standard_library_use)

local RunService = game:GetService("RunService")
local isServer, isClient = RunService:IsServer(), RunService:IsClient()

local src = script.Parent
local core = src:WaitForChild("core")
local components = core:WaitForChild("components")
local lib = core:WaitForChild("lib")

local Settings = require(src:WaitForChild("Settings"))
local Types = require(src:WaitForChild("Types"))
local Metatables = require(lib:WaitForChild("Metatables"))
export type ShatterboxHitbox = Metatables.ShatterboxHitbox
export type ShatterboxDestructionParameters = Metatables.ShatterboxDestructionParameters

local Serializer = require(lib:WaitForChild("Serializer"))
local VertexMath = require(lib:WaitForChild("VertexMath"))
local GetVerts, GetNormals = VertexMath.GetVerts, VertexMath.GetNormals

local DirtyGroupLogic = require(components:WaitForChild("DirtyGroupLogic"))
local FallingGroupLogic = require(components:WaitForChild("FallingGroupLogic"))
local ShatterQueueLogic = require(components:WaitForChild("ShatterQueueLogic"))
local DeferredInstantiationLogic = require(components:WaitForChild("DeferredInstantiationLogic"))
local ClientServerLogic = require(components:WaitForChild("ClientServerLogic"))
local PuppeteerLogic = require(components:WaitForChild("PuppeteerLogic"))

local State = require(core:WaitForChild("State"))
local Blink = State.Blink


local function ShatterboxHeartbeatCycle(deltaTime)
	if State.IsProcessing then return end
	State.IsProcessing = true

	-- Smooth cleanup queue and delayed cleanup queue are processed here.
	DirtyGroupLogic.Heartbeat(deltaTime)

	-- All queued destructions for this frame (from Shatterbox.Destroy) are processed here, without modifying or creating any map parts (only voxel debris are instantiated/destroyed).
	ShatterQueueLogic.Heartbeat()

	-- The state the map should be after all voxel destruction for this frame is now known. The affected dirty groups are Greedy Meshed without modifying or creating any map parts.
	-- Finally the new map parts are created and the old ones are destroyed (if necessary). This algorithm results in the minimum map part creation/deletion count possible, or as close to it as Greedy Meshing allows.
	DeferredInstantiationLogic.Heartbeat()

	if isServer then
		FallingGroupLogic.Heartbeat()
	end

	-- Client-Server makes each client run their own version of Shatterbox (for recv gains and part flashing mitigation with streaming enabled). This ensures new players have their state synchronized with the server.
	if #State.NewPlayerStateReplicationQueue > 0 then
		for _, plr in ipairs(State.NewPlayerStateReplicationQueue) do
			ClientServerLogic.ReplicateStateToPlayer(plr)
		end
		table.clear(State.NewPlayerStateReplicationQueue)
	end

	-- Handle limited replication of the CFrames of voxels that are interpolated on the client side.
	if isServer then
		PuppeteerLogic.Heartbeat(deltaTime)
	end

	table.clear(State.ChangedDirtyGroups)

	Blink.StepReplication()
	State.IsProcessing = false
end


--- @class Shatterbox
local Shatterbox = {}

Metatables:SetReference(Shatterbox)
State.EffectsModuleCallbacks:SetReference(Shatterbox)

Shatterbox.Settings = Settings

--[=[
	Server side function. Begins controlled replication of `voxel` to the clients according to the Puppeteer settings.

	Returns the index of the new Puppet in the [Shatterbox.Puppets] sparse array. If the voxel was already a puppet, then the puppetID of that voxel is returned.

	When the part stops moving, it will become anchored to allow for a larger number of ground debris while still having good motion.

	It is safe to un-anchor these parts again in your destruction effects to have them start replicating again, they will still anchor themselves when they stop moving.

	@function Puppeteer
	@param voxel Part
	@return number
	@within Shatterbox
	@server
]=]
Shatterbox.Puppeteer = PuppeteerLogic.Puppeteer

--[=[
	Returns the ID of the passed in part, only if it is a member of the [Shatterbox.Puppets] sparse array.

	On the client side, this will always be false because the client sided puppets are indestructible.

	@function IsPuppet
	@param voxel Part
	@return number?
	@within Shatterbox
	@server
]=]
Shatterbox.IsPuppet = State.IsPuppet

--[=[
	A sparse array that holds information for every puppet in existence.

	### Example

	Server:
	```lua
	Shatterbox.RegisterOnVoxelDestruct("Fall", function(voxel, info)
		-- voxels try to fly away from the center of the destruction hitbox
		voxel.AssemblyLinearVelocity = (voxel.Position - info.CuttingPart.CFrame.Position).Unit * 30

		-- create map to store the Puppet IDs generated or affected by this destruction if it doesnt exist
		local PuppetIDs = info.UserData.PuppetIDs 
		if not PuppetIDs then
			PuppetIDs = {}
			info.UserData.PuppetIDs = PuppetIDs
		end

		-- if the voxel was already a puppet, Puppeteer returns the ID of that puppet.
		-- Puppeteer also automatically unanchors voxels.
		local puppetID = Shatterbox.Puppeteer(voxel)
		PuppetIDs[puppetID] = true
	end)


	local hb = Shatterbox.CreateHitbox()
	hb.Size = Vector3.one * 16
	hb.OnVoxelDestruct = "Fall"

	hb.OnDestructCompleted = function()
		local PuppetIDs = hb.UserData.PuppetIDs

		if PuppetIDs then
			-- Tell clients to do stuff with the found and created puppets.
			SignalClientPuppetVFX:FireAllClients(PuppetIDs)

			-- clear the map after each destruction
			hb.UserData.PuppetIDs = {}
		end
	end
	```

	Client:
	```lua
	SignalClientPuppetVFX.OnClientEvent:Connect(function(voxelIDs)

		for id in pairs(voxelIDs) do
			local PuppetPart = Shatterbox.GetPuppetAsync(id)
			if not PuppetPart then continue end

			-- do whatever you want with the client side puppet part
		end
	end)
	```

	@prop Puppets {PuppetDataType}
	@within Shatterbox
]=]
Shatterbox.Puppets = State.Puppets

--[=[
	A function that will wait for a Puppet with a given id to exist in [Shatterbox.Puppets], and return it if it was found.

	@function GetPuppetAsync
	@param puppetID number
	@param waitCount number? -- The number of Heartbeats to wait. Defaults to 10.
	@within Shatterbox
	@client
]=]
Shatterbox.GetPuppetAsync = PuppeteerLogic.GetPuppetAsync

--[=[
	Queues voxel destruction to be performed around the hitbox according to the `params` supplied.

	@param params DestructionParameters | Hitbox
]=]
function Shatterbox.Destroy(params : Types.DestructionParams)
	if ShatterQueueLogic.ModelQueueBehavior(Shatterbox.Destroy, params) then return end

	local Parameters = Serializer.ValidateDestructionParams(params)

	if Settings.USE_CLIENT_SERVER then
		local _, createdDirtyGroups = ShatterQueueLogic.GetDestructibleParts(Parameters)

		if isServer then
			ClientServerLogic.ReplicateDestructionToClients("DEFAULT", Parameters, createdDirtyGroups)
		else
			ClientServerLogic.SendDirtyGroupsToServer(createdDirtyGroups)
		end
	end

	table.insert(State.ShatterQueue, Parameters)
end


--[=[
	Performs voxel destruction around the hitbox according to the `params` supplied.

	Yields until the end of the current Heartbeat, returns the imaginary voxels to be created, any existing debris encountered, and the number of voxels this destruction destroyed.

	These imaginary voxels are to be instantiated using [Shatterbox.InstantiateImaginaryVoxel].

	@deprecated Release 9 -- Use [Shatterbox.Destroy] and a destruction effect instead.
	@param params DestructionParameters | Hitbox
	@return {ImaginaryVoxel}
	@return {BasePart}
	@return number
]=]
function Shatterbox.ImaginaryVoxels(params : Types.ImaginaryDestructionParams) : ({Types.ImaginaryVoxel}, {BasePart}, number)
	local destructionParams = Serializer.ValidateDestructionParams(params)
	destructionParams.ManualVoxelInstantiation = true
	destructionParams.OnVoxelDestruct = "CollectVoxelsAndDebris"
	destructionParams.OnDestructCompleted = "CollectDestroyedVoxelCount"

	local imaginaryVoxels, existingDebris = {}, {}
	destructionParams.UserData.ImaginaryVoxels = imaginaryVoxels
	destructionParams.UserData.ExistingDebris = existingDebris

	Shatterbox.Destroy(destructionParams)

	RunService.Heartbeat:Wait()
	local thread = coroutine.running()
	task.defer(function()
		destructionParams.UserData.ImaginaryVoxels = nil
		destructionParams.UserData.ExistingDebris = nil
		local destroyedVoxelCount = destructionParams.UserData.DestroyedVoxelCount
		destructionParams.UserData.DestroyedVoxelCount = nil

		task.spawn(thread, imaginaryVoxels, existingDebris, destroyedVoxelCount)
	end)
	return coroutine.yield()
end


--[=[
	Returns a created voxel using the supplied `ImaginaryVoxel`.

	Will automatically parent the voxel to the original parent of the group.

	Will also automatically give the voxel the `"ShatterboxDebris"` tag unless you pass in `doNotGiveDebrisTag`.

	:::tip
	You would want to pass in `doNotGiveDebrisTag` if you're going to use the static function [Shatterbox.OnVoxelDestruct] to use/extend an existing effect.
	:::

	@function InstantiateImaginaryVoxel
	@param ImaginaryVoxel ImaginaryVoxel
	@param doNotGiveDebrisTag boolean?
	@return Part
	@within Shatterbox
]=]
Shatterbox.InstantiateImaginaryVoxel = ShatterQueueLogic.InstantiateImaginaryVoxel


--[=[
	Resets an area. Currently only supports Box shaped areas.

	Does not revert the ownership of parts with Client-Server enabled.

	@param area Part|ImaginaryPart
]=]
function Shatterbox.ResetArea(area : Part | Types.WorldInfo)

	local ACF, AS = area.CFrame, area.Size
	if isServer then
		Blink.SignalResetArea.FireAll(ACF, AS)
	end

	local AreaVerts = VertexMath.GetVerts.Block(ACF, AS)
	local AreaNormals = VertexMath.GetNormals.Block(ACF)

	-- Check all of the dirty groups to see if any of them intersect the area
	for DirtyGroupID, groupData in pairs(State.DirtyGroupData) do

		-- intersection test between the area and the original part that was destroyed (the original part can be of any shape for future compatibility)
		local originalPart = groupData.OriginalPart
		local cpcf, cps, cpsh = originalPart.CFrame, originalPart.Size, originalPart.Shape.Name
		local iBl, iBa, iC = cpsh == "Block", cpsh == "Ball", cpsh == "Cylinder"

		local intersectingVerts, intersectingNormals
		if iBl or iC then
			intersectingVerts = GetVerts.Block(cpcf, cps)
			intersectingNormals = GetNormals.Block(cpcf)
		elseif not iBa then
			intersectingVerts = GetVerts[cpsh](cpcf, cps)
			intersectingNormals = GetNormals[cpsh](cpcf, cps)
		end

		local intersected = VertexMath.PartContainsAVert(originalPart, AreaVerts)
		if not intersected then
			if iBa then
				intersected = VertexMath.BallIntersectsBlock(cpcf, cps, ACF, AS)
			elseif iC then
				intersected = VertexMath.CylinderIntersectsBlock(cpcf, cps, intersectingVerts, intersectingNormals, ACF, AS, AreaVerts, AreaNormals)
			else
				intersected = VertexMath.SAT(intersectingVerts, intersectingNormals, AreaVerts, AreaNormals)
			end
		end

		if intersected then
			DirtyGroupLogic.UndoDirtyGroup(DirtyGroupID)
		end
	end
end


--[=[
	Resets all modified parts and clears Shatterbox queues/maps.

	If `doNotRevertOwnership` is `true` with Client-Server enabled, the clients do not delete their owned map parts.

	@function Reset
	@param doNotRevertOwnership boolean?
	@within Shatterbox
]=]
function Shatterbox.Reset(doNotRevertOwnership : boolean?, replicated)
	table.clear(State.ChangedDirtyGroups)

	table.clear(State.DelayedCleanupQueue)
	table.clear(State.SmoothCleanupQueue)
	table.clear(State.SmoothCleanupFallingQueue)

	table.clear(State.ShatterQueue)
	table.clear(State.ImaginaryCreateQueue)
	table.clear(State.ImaginaryDestroyQueue)
	table.clear(State.GreedyMeshedImaginaryParts)

	if isServer then
		for _, puppetData in pairs(State.Puppets) do
			if not Settings.USE_OBJECT_CACHE then
				puppetData[3]:Disconnect()
			end
			puppetData[2](true)
			DirtyGroupLogic.DestroyPart(puppetData[1])
		end

		Blink.SignalReset.FireAll(doNotRevertOwnership)
	else
		for _, puppetData in pairs(State.Puppets) do
			DirtyGroupLogic.DestroyPart(puppetData[1])
		end
	end

	table.clear(State.Puppets)
	table.clear(State.CreatePuppetQueue)
	State.PuppetNextIndex = 1
	table.clear(State.PuppetsLerpData)
	State.PuppetNextReplicationIndex = 1

	for _, SectionAnchors in pairs(State.FallingGroupSectionAnchors) do
		for _, SectionAnchor in pairs(SectionAnchors) do
			SectionAnchor:Destroy()
		end
	end
	table.clear(State.FallingGroupSectionAnchors)
	table.clear(State.FallingGroupPartWeldMap)

	if doNotRevertOwnership and Settings.USE_CLIENT_SERVER then
		for DirtyGroupID in pairs(State.DirtyGroupData) do
			DirtyGroupLogic.UndoDirtyGroup(DirtyGroupID)
		end
	else
		for DirtyGroupID, groupData in pairs(State.DirtyGroupData) do
			local OriginalPart = groupData.OriginalPart
			if replicated then
				OriginalPart:Destroy()
			else
				OriginalPart:SetAttribute(Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME)
				OriginalPart.Parent = groupData.OriginalParent
			end

			for member in pairs(State.DirtyGroupMembers[DirtyGroupID]) do
				DirtyGroupLogic.DestroyPart(member)
			end

			if not replicated and OriginalPart:GetAttribute(Settings.FALLING_GROUP_ID_ATTRIBUTE_NAME) then
				OriginalPart:SetAttribute(Settings.FALLING_GROUP_ID_ATTRIBUTE_NAME)
				OriginalPart:SetAttribute(Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME)
				OriginalPart.CFrame = State.FallingDirtyGroupOriginalCFrames[DirtyGroupID]
				OriginalPart.Anchored = true
			end
		end

		table.clear(State.DirtyGroupData)
		table.clear(State.DirtyGroupMembers)

		table.clear(State.FallingGroupDirtyGroups)
		table.clear(State.FallingDirtyGroupMinCornerLocalToAnchor)
		table.clear(State.FallingDirtyGroupOriginalCFrames)
		table.clear(State.FallingGroupOriginalAnchorCFrames)
	end

	table.clear(State.FallingGroupSectionMembers)
end

--[=[
	Resets the given dirty group to the state it was in before Shatterbox touched it.

	:::tip
	Use `part:GetAttribute("DirtyGroupID")` to get the DirtyGroupID of a part that is a member of a dirty group.
	:::
]=]
function Shatterbox.ResetDirtyGroup(DirtyGroupID : string)
	DirtyGroupLogic.ResetDirtyGroup(DirtyGroupID)

	if Settings.USE_CLIENT_SERVER and isServer then
		Blink.SignalResetDirtyGroup.FireAll(DirtyGroupID)
	end
end


--[=[
	Creates a Hitbox object which can be used in place of the destruction functions, and has additional functionality. (like VoxBreaker moveable hitbox)

	If you use ExcludePlayersReplication, that will be cleared after every destruction automatically, for convenience.

	@return Hitbox
]=]
function Shatterbox.CreateHitbox() : ShatterboxHitbox

	local hitbox = setmetatable({}, Metatables.HitboxMT)

	hitbox.UserData = {}

	return hitbox :: ShatterboxHitbox
end


--[=[
	Returns the original part that is associated with this DirtyGroupID.

	This part is never destroyed, just has its parent set to `nil`.
]=]
function Shatterbox.GetOriginalPart(DirtyGroupID : string) : BasePart
	local groupData = State.DirtyGroupData[DirtyGroupID]
	if not groupData then return nil end
	return groupData.OriginalPart
end


--[=[
	Takes a `point` and converts it to the voxel space distance relative to `voxel`.

	This is a vector which tells you how many voxels away `point` is on each local axis, as fractional quantities.

	It is possible for an axis to be less than one, but never negative.

	:::tip
	See `Shatterbox/effects/Server/MappingVoxelSpace` for an example on how to use VoxelDistanceVector
	:::
	@param voxel Part|ImaginaryPart
	@param point Vector3
]=]
function Shatterbox.VoxelDistanceVector(voxel : Part|Types.ImaginaryBox, point : Vector3) : Vector3
	return voxel.CFrame:PointToObjectSpace(point):Abs() / voxel.Size
end


--[=[
	Returns a vector that tells you how many voxels (relative to `voxel`) a box determined by `boxSize` has on each local axis, as fractional quantities.

	It is *not* possible for an axis to be less than one, because there is always at least one voxel on every axis.

	:::tip
	See `Shatterbox/effects/Server/MappingVoxelSpace` for an example on how to use VoxelCountVector
	:::
	@param voxel Part|ImaginaryPart
	@param boxSize Vector3
]=]
function Shatterbox.VoxelCountVector(voxel : Part|Types.ImaginaryBox, boxSize : Vector3) : Vector3
	return Vector3.one:Max(boxSize / voxel.Size)
end


--[=[
	Will register the given OnVoxelDestruct callback to the given name.

	If you call this function on the server side, you are creating a server-side effect. Vice-versa for registering on the client side.

	Consider using `Shatterbox/effects` modules for effect definitions.

	:::warning
	Register any given effect only once, you are free to use it by name in scripts other than the one it is defined in.
	:::

	@param name string
	@param callback OnVoxelDestructType
]=]
function Shatterbox.RegisterOnVoxelDestruct(name : string, callback : Types.OnVoxelDestruct)
	assert(typeof(name) == "string", "You must register the OnVoxelDestruct callback with a string as the name")
	local id = name:lower()
	assert(not rawget(State.OnVoxelDestructRegistry, id), `Callback with name {id} already exists in the registry`)
	State.OnVoxelDestructRegistry[id] = callback
end


--[=[
	Will register the given OnDestructCompleted callback to the given name.

	If you call this function on the server side, you are creating a server-side callback. Vice-versa for registering on the client side.

	Consider using `Shatterbox/effects` modules for callback definitions.

	:::warning
	Register any given callback name only once, you are free to use it by name in scripts other than the one it is defined in.
	:::

	@param name string
	@param callback OnDestructCompletedType
]=]
function Shatterbox.RegisterOnDestructCompleted(name : string, callback : Types.OnDestructCompleted)
	assert(typeof(name) == "string", "You must register the OnDestructCompleted callback with a string as the name")
	local id = name:lower()
	assert(not rawget(State.OnDestructCompletedRegistry, id), `Callback with name {id} already exists in the registry`)
	State.OnDestructCompletedRegistry[id] = callback
end


--[=[
	Properly returns a tuple of parts to the cache if ObjectCache is enabled. Parts not from the cache or if ObjectCache is disabled are directly destroyed.

	:::danger
	If you have ObjectCache enabled, you **must** use this function instead of `Instance:Destroy()` to destroy map parts and voxels created by this library.
	:::
]=]
function Shatterbox.Cleanup(... : BasePart)
	for _, Part in ipairs({...}) do
		DirtyGroupLogic.DestroyPart(Part)
	end
end

--[=[
	After a delay, properly returns a tuple of parts to the cache if ObjectCache is enabled. Parts not from the cache or if ObjectCache is disabled are directly destroyed.

	If the part is already present in the ShatterboxDebris map and the new delay is longer than the remaining time, the remaining time is extended to the new delay.

	:::danger
	If you have ObjectCache enabled, you **must** use this function instead of `game.Debris:AddItem()` to destroy map parts and voxels created by this library.
	:::
]=]
function Shatterbox.DelayedCleanup(delay : number, ... : BasePart)
	for _, Part in ipairs({...}) do
		State.DelayedCleanupQueue[Part] = math.max(State.DelayedCleanupQueue[Part] or 0, delay)
	end
end


--[=[
	A function to manually call a registered OnVoxelDestruct effect.

	:::tip
	This can be used as a way to constructively build on top of any existing effects, saving you time.

	#### Example
	```lua
	-- BumpyFloorBreakWalls but it makes every voxel black
	Shatterbox.RegisterOnVoxelDestruct("ExtendingAnEffect", function(voxel, info)
		voxel.Color = Color3.new()
		Shatterbox.OnVoxelDestruct("BumpyFloorBreakWalls", voxel, info)
	end)
	```
	:::

	@function OnVoxelDestruct
	@param name string
	@param voxel Part
	@param info VoxelInfo
	@within Shatterbox
]=]
Shatterbox.OnVoxelDestruct = ShatterQueueLogic.HandleOnVoxelDestruct

--[=[
	A function to manually call a registered OnDestructCompleted callback.

	:::tip
	This can be used as a way to constructively build on top of any existing effects, saving you time.

	#### Example
	```lua
	-- Do something with the return value of an existing callback (GetMaterialsMap is defined in `effects/Server`)
	Shatterbox.RegisterOnDestructCompleted("ExtendingACallback", function(voxelCount, affectedIDs, destructionParams)
		local destroyedMaterials = Shatterbox.OnDestructCompleted("GetMaterialsMap", voxelCount, affectedIDs, destructionParams)
		for material in pairs(destroyedMaterials) do
			print(material.Name)
		end
	end)
	```
	:::

	@function OnDestructCompleted
	@param name string
	@param voxelCount number
	@param affectedIDs {[string] : boolean}
	@param destructionParameters DestructionParameters
	@within Shatterbox
	@return any
]=]
Shatterbox.OnDestructCompleted = ShatterQueueLogic.HandleOnDestructCompleted

Shatterbox.VertexMath = VertexMath



-- Debug function to print the state of local variables
local function PrintState()
	local P, str = "\n|\n| ", nil

	print(P .. `SHATTERBOX ({isServer and "SERVER" or "CLIENT"})`)

	print(P .. "State.ShatterQueue length: " .. #State.ShatterQueue)

	str = P .. "State.SmoothCleanupQueue: {"
	for DirtyGroupID, countdown in pairs(State.SmoothCleanupQueue) do
		str = str..P.. "  [" .. DirtyGroupID .. "] = " .. countdown
	end
	str = str..P.. "}"
	print(str)

	str = P .. "State.DirtyGroupMembers length: {"
	for DirtyGroupID, members in pairs(State.DirtyGroupMembers) do
		--if not next(members) then continue end
		local count = 0
		for _ in pairs(members) do
			count += 1
		end
		str = str..P.. "  [" .. DirtyGroupID .. "] = " .. count
	end
	str = str..P.. "}"
	print(str)


	--print("Instanced: " .. ci)
	--print("Destroyed: " .. cd)

	print(str)
end

function Shatterbox.PrintState()

	if isServer then
		Blink.SignalPrintState.FireAll()
	end

	PrintState()
end



-- Core Shatterbox event connections

RunService.Heartbeat:Connect(ShatterboxHeartbeatCycle)

if isServer then

	if Settings.USE_CLIENT_SERVER then
		Blink.ClientInitComplete.On(ClientServerLogic.QueueNewPlayerStateReplication)

		Blink.CreateDirtyGroupsFromClient.On(ClientServerLogic.CreateDirtyGroupsFromClient)
	end

elseif isClient then

	if Settings.USE_CLIENT_SERVER then
		Blink.ReplicateState.On(ClientServerLogic.ReplicateStateFromServer)

		Blink.ReplicateDestruction.On(function(destructionType, serialParams, serialNewDirtyGroups)
			if not State.ClientInitComplete then return end
			ClientServerLogic.ReplicateDestructionFromServer(destructionType, serialParams, serialNewDirtyGroups)
		end)

		Blink.CreateDirtyGroupsFromServer.On(function(SerialDirtyGroups)
			if not State.ClientInitComplete then return end
			ClientServerLogic.CreateSerialDirtyGroups(SerialDirtyGroups)
		end)

		Blink.ClientInitComplete.Fire()
	end

	Blink.SignalReset.On(function(doNotRevertOwnership)
		if Settings.USE_CLIENT_SERVER and not State.ClientInitComplete then return end
		Shatterbox.Reset(doNotRevertOwnership, true)
	end)
	Blink.SignalResetArea.On(function(cframe, size)
		if Settings.USE_CLIENT_SERVER and not State.ClientInitComplete then return end
		Shatterbox.ResetArea({ CFrame = cframe, Size = size })
	end)
	Blink.SignalResetDirtyGroup.On(function(DirtyGroupID)
		DirtyGroupLogic.ResetDirtyGroup(DirtyGroupID, true)
	end)

	Blink.CreatePuppets.On(function(serialPuppets, startIndex)
		if Settings.USE_CLIENT_SERVER and not State.ClientInitComplete then return end
		PuppeteerLogic.CreatePuppetsFromServer(serialPuppets, startIndex)
	end)
	Blink.ReplicatePuppetStates.On(function(puppetStates, stepDelta)
		if Settings.USE_CLIENT_SERVER and not State.ClientInitComplete then return end
		PuppeteerLogic.ReplicatePuppetStatesFromServer(puppetStates, stepDelta)
	end)
	Blink.DestroyPuppet.On(function(index)
		if Settings.USE_CLIENT_SERVER and not State.ClientInitComplete then return end
		PuppeteerLogic.DestroyPuppet(index)
	end)

	Blink.SignalPrintState.On(PrintState)
end

return Shatterbox
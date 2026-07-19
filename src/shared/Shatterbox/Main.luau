--!native
--!optimize 2


-- Shatterbox dev build May 12, 2026


--#selene: allow(incorrect_standard_library_use)


local src = script.Parent
local core = src:WaitForChild("core")
local components = core:WaitForChild("components")
local lib = core:WaitForChild("lib")

local RunService = game:GetService("RunService")

local isServer, isClient = RunService:IsServer(), RunService:IsClient()

local Settings = require(src:WaitForChild("Settings"))
local USE_CLIENT_SERVER = Settings.USE_CLIENT_SERVER
local USE_OBJECT_CACHE = Settings.USE_OBJECT_CACHE
local DirtyGroupIDAttribute = Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME

local Types = require(src:WaitForChild("Types"))

local DirtyGroupLogic = require(components:WaitForChild("DirtyGroupLogic"))
local SmoothCleanupHeartbeatBehavior = DirtyGroupLogic.SmoothCleanupHeartbeatBehavior
local DestroyPart = DirtyGroupLogic.DestroyPart
local UndoDirtyGroup = DirtyGroupLogic.UndoDirtyGroup

local ShatterQueueLogic = require(components:WaitForChild("ShatterQueueLogic"))
local ShatterQueueHeartbeatBehavior = ShatterQueueLogic.ShatterQueueHeartbeatBehavior
local ModelQueueBehavior = ShatterQueueLogic.ModelQueueBehavior
local HandleOnVoxelDestruct = ShatterQueueLogic.HandleOnVoxelDestruct
local HandleOnDestructCompleted = ShatterQueueLogic.HandleOnDestructCompleted
local GetDestructibleParts = ShatterQueueLogic.GetDestructibleParts
local ImaginaryVoxels = ShatterQueueLogic.ImaginaryVoxels
local InstantiateImaginaryVoxel = ShatterQueueLogic.InstantiateImaginaryVoxel

local DeferredInstantiationLogic = require(components:WaitForChild("DeferredInstantiationLogic"))
local DeferredInstantiationHeartbeatBehavior = DeferredInstantiationLogic.DeferredInstantiationHeartbeatBehavior

local ClientServerLogic = require(components:WaitForChild("ClientServerLogic"))
local ReplicateStateToPlayer = ClientServerLogic.ReplicateStateToPlayer
local ReplicateStateFromServer = ClientServerLogic.ReplicateStateFromServer
local QueueNewPlayerStateReplication = ClientServerLogic.QueueNewPlayerStateReplication
local SendDirtyGroupsToServer = ClientServerLogic.SendDirtyGroupsToServer
local CreateDirtyGroupsFromClient = ClientServerLogic.CreateDirtyGroupsFromClient
local ReplicateDestructionToClients = ClientServerLogic.ReplicateDestructionToClients
local ReplicateDestructionFromServer = ClientServerLogic.ReplicateDestructionFromServer
local CreateSerialDirtyGroups = ClientServerLogic.CreateSerialDirtyGroups

local PuppeteerLogic = require(components:WaitForChild("PuppeteerLogic"))
local PuppeteerHeartbeatBehavior = PuppeteerLogic.PuppeteerHeartbeatBehavior
local DestroyPuppet = PuppeteerLogic.DestroyPuppet
local CreatePuppetsFromServer = PuppeteerLogic.CreatePuppetsFromServer
local ReplicatePuppetStatesFromServer = PuppeteerLogic.ReplicatePuppetStatesFromServer

local Metatables = require(lib:WaitForChild("Metatables"))
local HitboxMT = Metatables.HitboxMT
export type ShatterboxHitbox = Metatables.ShatterboxHitbox
export type ShatterboxDestructionParameters = Metatables.ShatterboxDestructionParameters

local Serializer = require(lib:WaitForChild("Serializer"))
local ValidateDestructionParams = Serializer.ValidateDestructionParams

local VertexMath = require(lib:WaitForChild("VertexMath"))
local GetVerts, GetNormals = VertexMath.GetVerts, VertexMath.GetNormals
local BlockVerts, BlockNormals = GetVerts.Block, GetNormals.Block
local PartContainsAVert = VertexMath.PartContainsAVert

local State = require(core:WaitForChild("State"))

local Blink = State.Blink
local StepReplication = Blink.StepReplication

local OnVoxelDestructRegistry = State.OnVoxelDestructRegistry
local OnDestructCompletedRegistry = State.OnDestructCompletedRegistry

local DirtyGroupData = State.DirtyGroupData
local DirtyGroupMembers = State.DirtyGroupMembers

local SmoothCleanupQueue = State.SmoothCleanupQueue

local GreedyMeshedImaginaryParts = State.GreedyMeshedImaginaryParts
local ImaginaryCreateQueue = State.ImaginaryCreateQueue
local ImaginaryDestroyQueue = State.ImaginaryDestroyQueue

local ShatterQueue = State.ShatterQueue

local Puppets = State.Puppets

local PuppetsLerpData = State.PuppetsLerpData

local CreatePuppetQueue = State.CreatePuppetQueue

local NewPlayerStateReplicationQueue = State.NewPlayerStateReplicationQueue

-- The Heartbeat cycle of Shatterbox.
local function HeartbeatWorker(deltaTime)

	if Settings.UseSmoothCleanup then
		coroutine.wrap(SmoothCleanupHeartbeatBehavior)(deltaTime)
	end

	ShatterQueueHeartbeatBehavior()

	DeferredInstantiationHeartbeatBehavior()

	if #NewPlayerStateReplicationQueue > 0 then
		for _, plr in ipairs(NewPlayerStateReplicationQueue) do
			ReplicateStateToPlayer(plr)
		end
		table.clear(NewPlayerStateReplicationQueue)
	end

	if isServer then
		PuppeteerHeartbeatBehavior(deltaTime)
	end

	StepReplication()
end


--- @class Shatterbox
local Shatterbox = {}

State.EffectsModuleCallbacks:SetReference(Shatterbox)
State.EffectsModuleCallbacks = nil

Metatables:SetReference(Shatterbox)

Shatterbox.Settings = Settings

--[=[
	Server side function. Begins controlled replication of `voxel` to the clients according to the Puppeteer settings.

	Returns the index of the new Puppet in the [Shatterbox.Puppets] sparse array. If the voxel was already a puppet, then the puppetID of that voxel is returned.

	When the part stops moving, it will become anchored to allow for a larger number of ground debris while still having good motion.

	It is safe to un-anchor these parts again in your destruction effects to have them start replicating again, they will still anchor themselves when they stop moving.

	@return number
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
		local Puppets = Shatterbox.Puppets

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
Shatterbox.Puppets = Puppets

--[=[
	A function that will wait for a Puppet with a given id to exist in [Shatterbox.Puppets], and return it if it was found.

	@param puppetID number
	@param waitCount number? -- The number of Heartbeats to wait. Defaults to 10.
	@client
]=]
Shatterbox.GetPuppetAsync = PuppeteerLogic.GetPuppetAsync

--[=[
	Queues voxel destruction to be performed around the hitbox according to the `params` supplied.

	@param params DestructionParameters | Hitbox
]=]
function Shatterbox.Destroy(params : Types.DestructionParams)
	if ModelQueueBehavior(Shatterbox.Destroy, params) then return end

	local Parameters = ValidateDestructionParams(params)

	if USE_CLIENT_SERVER then
		local _, createdDirtyGroups = GetDestructibleParts(Parameters)

		if isServer then
			ReplicateDestructionToClients("DEFAULT", Parameters, createdDirtyGroups)
		else
			SendDirtyGroupsToServer(createdDirtyGroups)
		end
	end

	table.insert(ShatterQueue, Parameters)
end


--[=[
	Instantly performs voxel destruction around the hitbox according to the `params` supplied.

	Returns the imaginary voxels to be created as well as any existing debris encountered.

	These are to be instantiated using [Shatterbox.InstantiateImaginaryVoxel].

	:::warning
	If you use SkipEncapsulatedVoxels, the #length of the imaginary voxels array will show up as larger than it really is.

	This is to give the same functionality as [OnDestructCompleted voxelCount](/api/Shatterbox#OnDestructCompleted) without the need for a third return value.

	Use `ipairs` or generalized iteration to iterate over this array.
	:::
	@param params DestructionParameters | Hitbox
	@return {ImaginaryVoxel}
	@return {BasePart}
]=]
function Shatterbox.ImaginaryVoxels(params : Types.ImaginaryDestructionParams) : ({Types.ImaginaryVoxel}, {BasePart})

	local did, voxels, existingDebris = ModelQueueBehavior(Shatterbox.ImaginaryVoxels, params)
	if did then return voxels, existingDebris end

	local Parameters = ValidateDestructionParams(params)

	local destructibleParts, createdDirtyGroups, _, affectedIDs = GetDestructibleParts(Parameters)

	if USE_CLIENT_SERVER then
		if isServer then
			ReplicateDestructionToClients("IMAGINARY", Parameters, createdDirtyGroups)
		else
			SendDirtyGroupsToServer(createdDirtyGroups)
		end
	end

	voxels, existingDebris = ImaginaryVoxels(Parameters, destructibleParts, affectedIDs)

	return voxels or {}, existingDebris
end


--[=[
	Returns a created voxel using the supplied `ImaginaryVoxel`.

	Will automatically parent the voxel to the original parent of the group.

	Will also automatically give the voxel the `"ShatterboxDebris"` tag unless you pass in `doNotGiveDebrisTag`.

	:::tip
	You would want to pass in `doNotGiveDebrisTag` if you're going to use the static function [Shatterbox.OnVoxelDestruct] to use/extend an existing effect.
	:::
	@param ImaginaryVoxel ImaginaryVoxel
	@param doNotGiveDebrisTag boolean?
]=]
Shatterbox.InstantiateImaginaryVoxel = InstantiateImaginaryVoxel


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
	for DirtyGroupID, groupData in pairs(DirtyGroupData) do

		-- intersection test between the area and the original part that was destroyed (the original part can be of any shape for future compatibility)
		local originalPart = groupData.OriginalPart
		local cpcf, cps, cpsh = originalPart.CFrame, originalPart.Size, originalPart.Shape.Name
		local iBl, iBa, iC = cpsh == "Block", cpsh == "Ball", cpsh == "Cylinder"

		local intersectingVerts, intersectingNormals
		if iBl or iC then
			intersectingVerts = BlockVerts(cpcf, cps)
			intersectingNormals = BlockNormals(cpcf)
		elseif not iBa then
			intersectingVerts = GetVerts[cpsh](cpcf, cps)
			intersectingNormals = GetNormals[cpsh](cpcf, cps)
		end

		local intersected = PartContainsAVert(originalPart, AreaVerts)
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
			UndoDirtyGroup(DirtyGroupID)
		end
	end
end


--[=[
	Resets all modified parts and re-allocates system queues/maps.

	If `doNotRevertOwnership` is `true` with Client-Server enabled, the clients do not delete their owned map parts.

	@function Reset
	@param doNotRevertOwnership boolean?
	@within Shatterbox
]=]
function Shatterbox.Reset(doNotRevertOwnership : boolean?, replicated)
	-- stop all queued destructions
	table.clear(ShatterQueue)

	table.clear(SmoothCleanupQueue)

	table.clear(ImaginaryCreateQueue)
	table.clear(ImaginaryDestroyQueue)
	table.clear(GreedyMeshedImaginaryParts)

	if isServer then
		for _, puppetData in pairs(Puppets) do
			if not USE_OBJECT_CACHE then
				puppetData[3]:Disconnect()
			end
			puppetData[2](true)
			DestroyPart(puppetData[1])
		end

		Blink.SignalReset.FireAll(doNotRevertOwnership)
	else
		for _, puppetData in pairs(Puppets) do
			DestroyPart(puppetData[1])
		end
	end

	table.clear(Puppets)
	table.clear(CreatePuppetQueue)
	State.PuppetNextIndex = 1
	table.clear(PuppetsLerpData)
	State.PuppetNextReplicationIndex = 1

	if doNotRevertOwnership and USE_CLIENT_SERVER then
		-- every operation is undone if the ownership is not meant to be reverted
		for DirtyGroupID in pairs(DirtyGroupData) do
			UndoDirtyGroup(DirtyGroupID)
		end
	else
		for DirtyGroupID, groupData in pairs(DirtyGroupData) do
			local OriginalPart = groupData.OriginalPart
			if replicated then
				OriginalPart:Destroy()
			else
				-- clear the dirty group information
				OriginalPart:SetAttribute(DirtyGroupIDAttribute)
				-- put the original part back where it was before Shatterbox touched it
				OriginalPart.Parent = groupData.OriginalParent
			end
			-- destroy all members of the dirty group
			for member in pairs(DirtyGroupMembers[DirtyGroupID]) do
				DestroyPart(member)
			end
		end

		table.clear(DirtyGroupData)
		table.clear(DirtyGroupMembers)
	end
end


--[=[
	Creates a Hitbox object which can be used in place of the destruction functions, and has additional functionality. (like VoxBreaker moveable hitbox)

	If you use ExcludePlayersReplication, that will be cleared after every destruction automatically, for convenience.

	@return Hitbox
]=]
function Shatterbox.CreateHitbox() : ShatterboxHitbox

	local hitbox = setmetatable({}, HitboxMT)

	hitbox.UserData = {}

	return hitbox :: ShatterboxHitbox
end


--[=[
	Returns the original part that is associated with this DirtyGroupID.

	This part is never destroyed, just has its parent set to `nil`.
]=]
function Shatterbox.GetOriginalPart(DirtyGroupID : string) : BasePart
	local groupData = DirtyGroupData[DirtyGroupID]
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
	assert(not rawget(OnVoxelDestructRegistry, id), `Callback with name {id} already exists in the registry`)
	OnVoxelDestructRegistry[id] = callback
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
	assert(not rawget(OnDestructCompletedRegistry, id), `Callback with name {id} already exists in the registry`)
	OnDestructCompletedRegistry[id] = callback
end


--[=[
	Properly returns a tuple of parts to the cache if ObjectCache is enabled. Parts not from the cache or if ObjectCache is disabled are directly destroyed.

	:::danger
	If you have ObjectCache enabled, you **must** use this function to destroy map parts and voxels created by this library.
	:::
]=]
function Shatterbox.Cleanup(... : BasePart)
	for _, Part in ipairs({...}) do
		DestroyPart(Part)
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
Shatterbox.OnVoxelDestruct = HandleOnVoxelDestruct

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

	@param name string
	@param voxelCount number
	@param affectedIDs {[string] : boolean}
	@param destructionParameters DestructionParameters
	@within Shatterbox
	@return any
]=]
Shatterbox.OnDestructCompleted = HandleOnDestructCompleted

Shatterbox.VertexMath = VertexMath



-- Debug function to print the state of local variables
local function PrintState()
	local P, str = "\n|\n| ", nil

	print(P .. `SHATTERBOX ({isServer and "SERVER" or "CLIENT"})`)

	print(P .. "ShatterQueue length: " .. #ShatterQueue)

	str = P .. "SmoothCleanupQueue: {"
	for DirtyGroupID, countdown in pairs(SmoothCleanupQueue) do
		str = str..P.. "  [" .. DirtyGroupID .. "] = " .. countdown
	end
	str = str..P.. "}"
	print(str)

	str = P .. "DirtyGroupMembers length: {"
	for DirtyGroupID, members in pairs(DirtyGroupMembers) do
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

RunService.Heartbeat:Connect(HeartbeatWorker)

if isServer then

	if USE_CLIENT_SERVER then
		Blink.ClientInitComplete.On(QueueNewPlayerStateReplication)

		Blink.CreateDirtyGroupsFromClient.On(CreateDirtyGroupsFromClient)
	end

elseif isClient then

	if USE_CLIENT_SERVER then
		Blink.ReplicateState.On(ReplicateStateFromServer)

		Blink.ReplicateDestruction.On(function(destructionType, serialParams, serialNewDirtyGroups)
			if not State.ClientInitComplete then return end
			ReplicateDestructionFromServer(destructionType, serialParams, serialNewDirtyGroups)
		end)

		Blink.CreateDirtyGroupsFromServer.On(function(SerialDirtyGroups)
			if not State.ClientInitComplete then return end
			CreateSerialDirtyGroups(SerialDirtyGroups)
		end)

		Blink.ClientInitComplete.Fire()
	end

	Blink.SignalReset.On(function(doNotRevertOwnership)
		if USE_CLIENT_SERVER and not State.ClientInitComplete then return end
		Shatterbox.Reset(doNotRevertOwnership, true)
	end)
	Blink.SignalResetArea.On(function(cframe, size)
		if USE_CLIENT_SERVER and not State.ClientInitComplete then return end
		Shatterbox.ResetArea({ CFrame = cframe, Size = size })
	end)

	Blink.CreatePuppets.On(function(serialPuppets, startIndex)
		if USE_CLIENT_SERVER and not State.ClientInitComplete then return end
		CreatePuppetsFromServer(serialPuppets, startIndex)
	end)
	Blink.ReplicatePuppetStates.On(function(puppetStates, stepDelta)
		if USE_CLIENT_SERVER and not State.ClientInitComplete then return end
		ReplicatePuppetStatesFromServer(puppetStates, stepDelta)
	end)
	Blink.DestroyPuppet.On(function(index)
		if USE_CLIENT_SERVER and not State.ClientInitComplete then return end
		DestroyPuppet(index)
	end)

	Blink.SignalPrintState.On(PrintState)
end

return Shatterbox
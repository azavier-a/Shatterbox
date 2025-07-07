--!native
--!optimize 2


-- Shatterbox release 7.2


--#selene: allow(multiple_statements)
--#selene: allow(unused_variable)
--#selene: allow(incorrect_standard_library_use)
--#selene: allow(shadowing)

-- Shatterbox uses Blink for Client-Server communications
local lib = script.Parent:WaitForChild("lib")
local PathToClient = lib:WaitForChild("Client")
local PathToServer = lib:WaitForChild("Server")

--[[ IF YOU ALSO USE BLINK:

	1. Import the "Shatterbox.blink" file to your Blink config:		import "PATH_TO_SHATTERBOX/Shatterbox.blink"

	2. Rebuild your blink files

	3. Re-define PathToServer and PathToClient local variables defined above to the location of your blink files


	These steps ensure events are properly batched using Blink
]]

local IndestructibleTag = "Indestructible"

local RunService = game:GetService("RunService")
local isServer, isClient = RunService:IsServer(), RunService:IsClient()

--[[ Settings Explained:

UseSmoothCleanup:
|	If false, the CleanupDelay will be ignored and no smooth cleanups will happen at all.

MaxDivisionsPerFrame:
|	The target number of part divisions per frame. (1 division = up to 8 new parts)

DefaultSmoothCleanupDelay:
|	The default amount of time it takes for smooth restoration to happen if no value is provided.
|	Currently, smooth cleanup is a forced feature.

DefaultGridSize:
|	The default grid size to use when none is passed and the part doesn't have a GridSize attribute.

UsePriorityQueue:
|	If true, will process newly added divisions before continuing to process old ones.

PrioritizeRecentN:
|	Priority queue will prioritize the most recent N operations using round-robin processing.

PuppetReplicationFrequency:
|	The default of 20 means every 1/20 seconds a replication of puppet debris happens.

ClientTweenPuppets:
|	Does nothing on server-side. Whether or not to tween in between the replication of puppet CFrames.

PuppetReplicationFrameLimit:
|	How many puppets are batched per frame for replication to all clients.

PuppetSleepVelocity:
|	If a server puppet is moving slower than this magnitude, its CFrame does not get replicated to clients.

SkipInstanceCheck:
|	A function for you to specify behavior for instances that are trying to be considered for destruction.
|	should return true if it was skipped and return false if it was not.

]]

local Settings = {}

Settings.UseSmoothCleanup = true

Settings.MaxDivisionsPerFrame = 200

Settings.DefaultSmoothCleanupDelay = 60

Settings.DefaultGridSize = 1

Settings.UsePriorityQueue = true

Settings.PrioritizeRecentN = 10

Settings.PuppetReplicationFrequency = 20

Settings.ClientTweenPuppets = true

Settings.PuppetReplicationFrameLimit = 10

Settings.PuppetSleepVelocity = 0.01

Settings.SkipInstanceCheck = function(i : Instance)

	-- return true if you want to skip the instance "i"

	return false
end



local tmpFolder = workspace:FindFirstChild("ShatterboxTemporary") or Instance.new("Folder")
tmpFolder.Parent = workspace
tmpFolder.Name = "ShatterboxTemporary"

local function RecursiveFindHumanoid(i : Instance) return i:FindFirstChildWhichIsA("Humanoid") or  ( i.Parent and RecursiveFindHumanoid(i.Parent) ) end

-- Returns true if an instance should NOT be considered for voxel destruction
local function ShouldSkipInstance(i : Instance)
	-- skip anything that passed the SkipInstanceCheck
	if Settings.SkipInstanceCheck(i) then return true end
	-- skip anything that isnt a block part
	if not i:IsA("Part") or i.Shape ~= Enum.PartType.Block then return true end
	-- skip anything with the "Indestructible" tag
	if i:HasTag(IndestructibleTag) then return true end
	-- skip anything that is a descendant of the "ShatterboxTemporary" folder
	if i:IsDescendantOf(tmpFolder) then return true end
	-- skip anything which has a Humanoid child, or if any of its ancestors have a Humanoid child.
	if RecursiveFindHumanoid(i) then return true end

	return false
end


--[[ How to use:

	Place Shatterbox anywhere as a descendant of ReplicatedStorage (or in the "shared" directory if you are using Rojo)

	Require the module on ONLY the server side.

	This library assumes STATIC objects (i.e, buildings, the ground, walls). Not yet fully supporting moving objects.

	Giving a part the GridSize attribute will override the default GridSize.
	| the GridSize passed to destruction functions will override this attribute.

	To create your own debris effects, use Shatterbox.RegisterOnVoxelDestruct(name, func)
	| if you need one effect to do different things on server side and client side
	| you have to register it in this scipt using the local function RegisterOnVoxelDestruct(name, clientFunc, serverFunc)
	| see below (around line 120) for an example.

	Using a debris effect requires you to set OnVoxelDestruct = name

	CreateHitbox() will create a hitbox object very similar to a VoxBreaker Hitbox.
	I suggest you use this to get a feel for the module, it is very user-friendly.

	OnVoxelDestruct parameters explained (anything past the 3rd is supplied via DestructParams, examples are above):

		- voxel is the part that is to be destroyed

		- dirtyParent is the source model which is affected by smooth cleanup. See "Rough" for an example on the usage.

		- cuttingPart is the cloned hitbox which destroyed "voxel" in the state that it was in when it queued the operation. See "Rough" for an example on the usage.

		- isEdge is true if the voxel is along the edge of the intersection.

		- any parameters past isEdge are defined by the DestructParams array.
]]



-- If you modify any code below here, you are at serious risk of breaking the module. It probably already has a way to do what you need to do.



local Types = require(script.Parent:WaitForChild("Types"))


local OnVoxelDestructRegistry = setmetatable({}, {
	__index = function(tbl, k) return (k and rawget(tbl, k:lower())) or rawget(tbl, "default") end
}) :: { [string] : Types.OnVoxelDestruct }

local function RegisterOnVoxelDestruct(name : string, client : Types.OnVoxelDestruct?, server : Types.OnVoxelDestruct?)
	assert(typeof(name) == "string", "You must register the OnVoxelDestruct callback with a string as the name")
	local id = name:lower()
	assert(not rawget(OnVoxelDestructRegistry, id), `Callback with name {id} already exists in the registry`)
	OnVoxelDestructRegistry[id] = isClient and client or server
end

local Shatterbox = {}

if isServer then
	local serverEffects = require(script.Parent.effects.Server)
	serverEffects:SetReference(Shatterbox)
	serverEffects.SetReference = nil
	for name, func in pairs(serverEffects) do
		OnVoxelDestructRegistry[name:lower()] = func
	end
end
if isClient then
	local clientEffects = require(script.Parent:WaitForChild("effects"):WaitForChild("Client"))
	clientEffects:SetReference(Shatterbox)
	clientEffects.SetReference = nil
	for name, func in pairs(clientEffects) do
		OnVoxelDestructRegistry[name:lower()] = func
	end
end



local defaultOverlapParams = OverlapParams.new()
defaultOverlapParams.FilterType = Enum.RaycastFilterType.Exclude
defaultOverlapParams.FilterDescendantsInstances = { tmpFolder }


local clientMapFolder
if isClient then
	clientMapFolder = Instance.new("Folder")
	clientMapFolder.Parent = workspace
	clientMapFolder.Name = "ClientMap"

	defaultOverlapParams.FilterType = Enum.RaycastFilterType.Include
	defaultOverlapParams.FilterDescendantsInstances = { clientMapFolder }
end


if isServer then
	local scr = lib.InitializeShatterbox

	local ref = Instance.new("ObjectValue")
	ref.Name = "ShatterboxModule"
	ref.Value = script
	ref.Parent = scr

	scr.Parent = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
	scr.Enabled = true
end


-- A CFrame that is really far away. Disrespectfully stolen straight from the PartCahce module.
-- local CF_REALLY_FAR_AWAY = CFrame.new(0, 10e8, 0)


local VertexMath = require(lib:WaitForChild("VertexMath"))
local PartEncapsulatesBlockPart = VertexMath.PartEncapsulatesBlockPart
local GetBlockPartVertices = VertexMath.GetBlockPartVertices
local PartContainsAVert, PartContainsAllVerts = VertexMath.PartContainsAVert, VertexMath.PartContainsAllVerts

local SubdivideFunctions = {
	KD = VertexMath.KDS,
	MOT = VertexMath.MOTS
}

local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")



local opDirties = {} :: { 
	[string]: {
		intersectingPart : Part, 
		dirtied : {
			{ Part : Part, OriginalParent : Instance, model : Model }
		}
	}
}

local ShatterQueue = {} :: { Types.DestructionParams }
local DivQueue = {}
local frameDivs = 0


local Puppets = {} :: { [string] : Part }
local CreatePuppetQueue = {}


local ToReset = {} :: {{Part : Part, OriginalParent : Instance}}


local ClientEvents = isClient and require(PathToClient).Shatterbox or nil
local ServerEvents = isServer and require(PathToServer).Shatterbox or nil


local function FindDirtyOp(intersectingPart : Part)
	for _, intersectedDirties in pairs(opDirties) do
		if intersectingPart == intersectedDirties.intersectingPart then return intersectedDirties.dirtied end
	end
	return nil
end


local function ImaginaryVoxelize(part, GridSize)

	GridSize = GridSize or Settings.DefaultGridSize

	local imaginaryParts = {}

	local dividing = { part }

	while #dividing > 0 do

		local toDivide = table.remove(dividing)
		local s = toDivide.Size
		local sx, sy, sz = s.X, s.Y, s.Z
		local Subdivide = SubdivideFunctions[(math.max(sx, sy, sz) > 2 * math.min(sx, sy, sz)) and "KD" or "MOT"]

		local dividedParts = Subdivide(toDivide, GridSize)

		if dividedParts then 
			table.move(dividedParts, 1, #dividedParts, #dividing + 1, dividing)
		else
			table.insert(imaginaryParts, toDivide)
		end
	end

	return imaginaryParts
end





local waitingForClients = {}

local function StopWaitingOnUser(plr, ID)
	local waiting = waitingForClients[ID]
	local found = table.find(waiting, plr.UserId)
	if not found then return end
	table.remove(waiting, found)
	if #waiting == 0 then waitingForClients[ID] = nil end
end

local function StartWaitingOnUser(plr, ID)
	waitingForClients[ID] = waitingForClients[ID] or {}
	table.insert(waitingForClients[ID], plr.UserId)
end




local function UndoDirtyOp(ID : string)

	local intersectedDirties = opDirties[ID]
	if not intersectedDirties then return end
	opDirties[ID] = nil

	local found
	for i, v in ipairs(ShatterQueue) do
		if v.ID ~= ID then continue end
		v.CuttingPart:Destroy()
		found = i;
		break
	end
	if found then table.remove(ShatterQueue, found) end

	if isServer then ServerEvents.SignalUndo.FireAll(ID) end

	for _, dirtied in ipairs(intersectedDirties.dirtied) do
		local model = dirtied.model
		local restored = dirtied.Part:Clone()
		restored.Parent = model.Parent
		model:Destroy()
	end
end



local function MarkDirty(Part : Part, dirtied, doNotReparent)

	if Part:HasTag("ShatterboxDebris") then return end

	local PartParent = Part.Parent

	if PartParent and not PartParent:HasTag("ShatterboxInstance") then
		local model = Instance.new("Model")

		if isServer then 
			table.insert(ToReset, {
				Part = Part,
				OriginalParent = PartParent
			})
		end

		if doNotReparent then
			model.Parent = PartParent
		else
			model.Parent = isClient and clientMapFolder or workspace.CurrentCamera
		end

		model.Name = Part.Name
		model:AddTag("ShatterboxInstance")

		if isClient then
			local ot = Part.Transparency
			Part.Transparency = 1
			Part.Parent = nil
			Part = Part:Clone()
			Part.Transparency = ot
		end

		Part.Parent = model

		table.insert(dirtied, {
			Part = Part,
			OriginalParent = PartParent,
			model = model
		})
	end
end


-- Uses the given callback from the OnVoxelDestruct registry to destroy the given voxel
local function HandleVoxelDestruction(callbackName : string?, voxel : Part, dirtyParent : Model, intersectingPart : BasePart, isEdge : boolean, ... : any)
	if not voxel:HasTag("ShatterboxDebris") then voxel.Parent = tmpFolder end
	task.spawn(OnVoxelDestructRegistry[callbackName], voxel, dirtyParent, intersectingPart, isEdge, ...)
	task.defer(voxel.AddTag, voxel, "ShatterboxDebris")
end


local function GetDestructibleParts(cuttingPart, overlapParams, doNotReparent)
	local dirtied = {}
	local partsInPart = {}

	local op = cuttingPart.Parent
	cuttingPart.Parent = tmpFolder
	for _, part in ipairs( workspace:GetPartsInPart(cuttingPart, overlapParams) ) do

		if ShouldSkipInstance(part) then continue end

		MarkDirty(part, dirtied, doNotReparent) -- adds this part to the smooth cleanup for this destruction, if it's not already destroyed by something else

		table.insert(partsInPart, part)
	end
	cuttingPart.Parent = op

	if #dirtied > 0 then
		local found = FindDirtyOp(cuttingPart)
		table.move(dirtied, 1, #dirtied, #found + 1, found)
	end

	return partsInPart
end


-- pops an element from the ShatterQueue, removing the completed operations that it might find before finding one to complete.
local function PopShatterQueue()
	local popped, shatterPart, partsInPart
	local v = table.remove(ShatterQueue)

	while v and not popped do

		shatterPart, partsInPart = v.CuttingPart, {}

		for _, part in ipairs( GetDestructibleParts(shatterPart, v.OverlapParams) ) do

			if part:HasTag("ShatterboxDebris") then
				HandleVoxelDestruction(v.OnVoxelDestruct, part, part.Parent, shatterPart, false, unpack(v.DestructParameters))
				continue
			end

			table.insert(partsInPart, part)
		end

		if #partsInPart == 0 then
			shatterPart:Destroy()
			if v.OnDestructCompleted then v.OnDestructCompleted() end
			v = table.remove(ShatterQueue)
		else
			popped = v
			table.insert(ShatterQueue, Settings.UsePriorityQueue and math.max(1, #ShatterQueue + 1 - Settings.PrioritizeRecentN) or 1, popped)
		end
	end

	return popped, partsInPart
end



-- processes one of the divisions in the DivQueue, returns true if a divison was processed.
local function SubdivWorker()

	if #DivQueue == 0 then return false end

	local v = table.remove(DivQueue)
	local Part = v[1]
	local dirtyParent = Part.Parent

	if not dirtyParent then return true end

	local s = Part.Size
	local sx, sy, sz = s.X, s.Y, s.Z
	local Subdivide = SubdivideFunctions[(math.max(sx, sy, sz) > 2 * math.min(sx, sy, sz)) and "KD" or "MOT"]

	frameDivs += 1

	local created = Subdivide(Part, v[2])
	if not created then
		HandleVoxelDestruction(v[4], Part, dirtyParent, v[3], true, unpack(v[5]))
		return true
	end

	local originalGridSize = Part:GetAttribute("GridSize")
	for _, c in ipairs(created) do
		local instanced = Part:Clone()
		instanced.Anchored = true
		instanced.CFrame = c.CFrame
		instanced.Size = c.Size
		instanced.Parent = dirtyParent
		instanced:SetAttribute("GridSize", originalGridSize)
	end
	Part:Destroy()

	return true
end


-- processes one of the operations in the ShatterQueue, removing it if the operation is finished. It queues all divisions for this step of the operation.
-- returns true if an operation step was procesed.
local function ShatterWorker()

	local popped, partsInPart = PopShatterQueue()
	if not popped then return false end

	local intersectingPart, GridSize, onVoxelDestruct, skipEncapsulatedVoxels = popped.CuttingPart, popped.GridSize, popped.OnVoxelDestruct, popped.SkipEncapsulatedVoxels
	local canUseEncapsulationChecks = intersectingPart:IsA("Part")

	for _, Part in ipairs(partsInPart) do

		local PartSize = Part.Size
		local partGridSize = GridSize or Part:GetAttribute("GridSize") or Settings.DefaultGridSize

		if canUseEncapsulationChecks and PartEncapsulatesBlockPart(intersectingPart, Part.CFrame, PartSize) then

			if skipEncapsulatedVoxels then Part:Destroy() else
				local dirtyParent = Part.Parent
				local destructParams = popped.DestructParameters
				for _, voxel in ipairs(Shatterbox.Voxelize(Part, partGridSize)) do HandleVoxelDestruction(onVoxelDestruct, voxel, dirtyParent, intersectingPart, false, unpack(destructParams)) end
			end

		else table.insert(DivQueue, { Part, partGridSize, intersectingPart, onVoxelDestruct, popped.DestructParameters }) end
	end

	return true
end


local function InsertToShatterQueue(params : Types.DestructionParams)

	local intersectingPart = params.CuttingPart

	if #GetDestructibleParts(intersectingPart, params.OverlapParams) == 0 then return end

	if isClient then params.OverlapParams = defaultOverlapParams end

	table.insert(ShatterQueue, params)
end



local function ImaginaryVoxels(params)

	local voxels = {} :: {Types.ImaginaryVoxel}

	local partsInPart, destructibleParts = {}, GetDestructibleParts(params.CuttingPart, params.OverlapParams, true)
	for _, part in ipairs(destructibleParts) do
		table.insert(partsInPart, {
			CFrame = part.CFrame,
			Size = part.Size,
			DirtyParent = part.Parent,
			Original = part,
			GridSize = params.GridSize or part:GetAttribute("GridSize") or Settings.DefaultGridSize
		})
	end

	if #partsInPart == 0 then
		if params.destroyIntersectingPart then params.CuttingPart:Destroy() end

		if Settings.UseSmoothCleanup then task.delay(params.CleanupDelay, UndoDirtyOp, params.ID) end

		return {}
	end

	local dividing = {} :: {Types.ImaginaryBox}

	-- base dividing step
	for _, part in ipairs(partsInPart) do

		local s = part.Size
		local sx,sy,sz = s.X, s.Y, s.Z
		local minsize, maxsize = math.min(sx, sy, sz), math.max(sx, sy, sz)
		local Subdivide = SubdivideFunctions[(maxsize > 2 * minsize) and "KD" or "MOT"]

		local isEncapsulated = PartContainsAllVerts(params.CuttingPart, GetBlockPartVertices(part.CFrame, part.Size))

		if params.SkipEncapsulatedVoxels and isEncapsulated then continue end

		local createdParts = Subdivide(part, part.GridSize)
		if createdParts then
			local o = part.Original
			for _, created in ipairs(createdParts) do
				created.Original = o
				created.GridSize = part.GridSize
				created.DirtyParent = part.DirtyParent
				table.insert(dividing, created)
			end
		else
			part.isEdge = not isEncapsulated
			table.insert(voxels, part)
		end
	end

	-- imaginary approximation division step
	while #dividing > 0 do

		local toDivide = table.remove(dividing)
		local verts = GetBlockPartVertices(toDivide.CFrame, toDivide.Size)

		local foundVert = PartContainsAVert(params.CuttingPart, verts)
		if foundVert then
			table.remove(verts, foundVert)
			local s, o, gridSize, dirtyParent = toDivide.Size, toDivide.Original, toDivide.GridSize, toDivide.DirtyParent

			if PartContainsAllVerts(params.CuttingPart, verts) then
				if params.SkipEncapsulatedVoxels then continue end

				for _, created in ipairs(ImaginaryVoxelize(toDivide, gridSize)) do
					created.Original = o
					created.GridSize = gridSize
					created.DirtyParent = dirtyParent
					table.insert(voxels, created)
				end
				continue
			end

			toDivide.isEdge = true

			local sx,sy,sz = s.X, s.Y, s.Z
			if sx <= gridSize and sy <= gridSize and sz <= gridSize then table.insert(voxels, toDivide) continue end

			local minsize, maxsize = math.min(sx, sy, sz), math.max(sx, sy, sz)
			local Subdivide = SubdivideFunctions[(maxsize > 2 * minsize) and "KD" or "MOT"]

			local createdParts = Subdivide(toDivide, gridSize)
			if createdParts then
				for _, created in ipairs(createdParts) do
					created.Original = o
					created.GridSize = gridSize
					created.DirtyParent = dirtyParent
					table.insert(dividing, created)
				end
			else
				table.insert(voxels, toDivide)
			end
		else

			local newStatic = toDivide.Original:Clone()
			newStatic.Anchored = true
			newStatic.CFrame = toDivide.CFrame
			newStatic.Size = toDivide.Size
			newStatic.Parent = toDivide.DirtyParent
		end
	end

	-- destroy original parts
	for _, p in ipairs(destructibleParts) do p:Destroy() end

	-- recursive step (increase approximation accuracy until convergence)
	local rvox = ImaginaryVoxels(params)
	table.move(rvox, 1, #rvox, #voxels + 1, voxels)

	return voxels :: {Types.ImaginaryVoxel}
end



local function ValidateDestructionParams(intersectingPart : Part | Model | Types.DestructionParams, overlapParams : OverlapParams?, CleanupDelay : number?, OnVoxelDestruct : string?, GridSize : number?, SkipEncapsulatedVoxels : boolean?, OnDestructCompleted : (() -> ())?, ... : any)
	local isTbl = typeof(intersectingPart) == "table"

	local cuttingPart
	local params = {} :: Types.DestructionParams
	local iP = {} :: Types.DestructionParams

	if isTbl then
		iP = intersectingPart
		if iP.CuttingPart then
			cuttingPart = iP.CuttingPart:Clone()
			params.CFrame = cuttingPart.CFrame
			params.Size = cuttingPart.Size
			params.Shape = cuttingPart.Shape
		else
			local c, s, sh = iP.CFrame, iP.Size, iP.Shape
			cuttingPart = Instance.new("Part")
			cuttingPart.CFrame = c
			cuttingPart.Size = s
			cuttingPart.Shape = sh
			params.CFrame, params.Size, params.Shape = c, s, sh
		end
	elseif intersectingPart:IsA("Part") then
		cuttingPart = intersectingPart:Clone()
		params.CFrame = intersectingPart.CFrame
		params.Size = intersectingPart.Size
		params.Shape = intersectingPart.Shape
	end

	if cuttingPart then
		cuttingPart.Anchored = true
		cuttingPart.CanCollide = false
		cuttingPart.CanTouch = false
		cuttingPart.Transparency = 1
		cuttingPart.Locked = true
		params.CuttingPart = cuttingPart
	end

			params.OverlapParams = iP.OverlapParams 		   or overlapParams 		     or defaultOverlapParams
			  params.CleanupDelay = iP.CleanupDelay			   or CleanupDelay   		     or Settings.DefaultSmoothCleanupDelay
		    params.OnVoxelDestruct = iP.OnVoxelDestruct 		   or OnVoxelDestruct
				    params.GridSize = iP.GridSize 				   or GridSize
	params.SkipEncapsulatedVoxels = iP.SkipEncapsulatedVoxels   or SkipEncapsulatedVoxels
	  params.OnDestructCompleted = iP.OnDestructCompleted      or OnDestructCompleted
		params.DestructParameters = iP.DestructParameters     	   or { ... }
		params.finalOpTick = iP.finalOpTick
		params.ID = iP.ID

	return params :: Types.DestructionParams
end



local accum = 0

local function HeartbeatWorker(deltaTime)
	frameDivs = 0

	while frameDivs < Settings.MaxDivisionsPerFrame do
		if #DivQueue == 0 then ShatterWorker() end
		if not SubdivWorker() then break end
	end

	if isClient then return end

	local PQL = #CreatePuppetQueue
	if PQL > 0 then
		local toReplicate = {}
		for _ = 1, math.min(PQL, Settings.PuppetReplicationFrameLimit) do
			local GUID, voxel = unpack(table.remove(CreatePuppetQueue))
			table.insert(toReplicate, {
				GUID = GUID,
				CFrame = voxel.CFrame,
				Size = voxel.Size,
				Material = voxel.Material.Value,
				Color = voxel.Color,
				Transparency = voxel.Transparency
			})
		end
		ServerEvents.CreatePuppets.FireAll(toReplicate)
	end

	accum += deltaTime
	local P = 1 / Settings.PuppetReplicationFrequency
	while accum > P do
		accum -= P
		local puppetStates = {}
		for guid, puppetVoxel in pairs(Puppets) do

			local found
			for _, toCreate in ipairs(CreatePuppetQueue) do
				if toCreate[1] == guid then found = true break end
			end
			if found then continue end

			if puppetVoxel.AssemblyLinearVelocity.Magnitude < Settings.PuppetSleepVelocity then continue end
			table.insert(puppetStates, {
				GUID = guid,
				CFrame = puppetVoxel.CFrame
			})
		end
		if #puppetStates == 0 then return end
		ServerEvents.ReplicatePuppetStates.FireAll(puppetStates)
	end
end



local function ReplicateDestructionFromServer(params, skipEvent)

	params.Shape = Enum.PartType:FromValue(params.Shape)

	local dParams = ValidateDestructionParams(params)

	if dParams.CuttingPart:IsA("Model") then
		for _, desc in ipairs(dParams.CuttingPart:GetDescendants()) do
			if not desc:IsA("Part") then continue end
			params.CuttingPart = desc
			ReplicateDestructionFromServer(params, true)
		end
		ClientEvents.MapReplicationCompleted.Fire()
		return
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType:FromValue(params.OverlapFilterType)
	overlapParams.FilterDescendantsInstances = params.OverlapFilterDescendants

	dParams.OverlapParams = overlapParams

	local ID = dParams.ID
	opDirties[ID] = {
		intersectingPart = dParams.CuttingPart,
		dirtied = {}
	}

	InsertToShatterQueue(dParams)

	if not skipEvent then ClientEvents.MapReplicationCompleted.Fire(ID) end
end


local function ReplicateDestructionToClients(destructionParams : Types.DestructionParams, finalOpTick : number)

	destructionParams = table.clone(destructionParams)
	destructionParams.Shape = destructionParams.Shape.Value
	destructionParams.OnDestructCompleted = nil

	destructionParams.finalOpTick = finalOpTick

	local overlapParams = destructionParams.OverlapParams
	destructionParams.OverlapFilterType = overlapParams.FilterType.Value
	destructionParams.OverlapFilterDescendants= overlapParams.FilterDescendantsInstances

	destructionParams.OverlapParams = nil
	destructionParams.CuttingPart = nil

	local ID = destructionParams.ID
	for _, plr in ipairs(Players:GetPlayers()) do StartWaitingOnUser(plr, ID) end
	ServerEvents.SignalDestruction.FireAll(destructionParams)
	while waitingForClients[ID] do RunService.Heartbeat:Wait() end
end



local function CreatePuppets(puppets)
	for _, puppet in ipairs(puppets) do
		local Part = Instance.new("Part")
		Part:AddTag(IndestructibleTag)
		Part.Anchored = true
		Part.Color = puppet.Color
		Part.Size = puppet.Size
		Part.CFrame = puppet.CFrame
		Part.Material = Enum.Material:FromValue(puppet.Material)
		Part.Transparency = puppet.Transparency
		Part.Parent = tmpFolder

		Puppets[puppet.GUID] = Part
	end
end


local function ReplicatePuppetStates(puppetStates)
	local numPuppets = 0
	for _ in pairs(Puppets) do numPuppets += 1 end
	print(#puppetStates, numPuppets)
    for _, state in ipairs(puppetStates) do
        local voxel = Puppets[state.GUID]
		if not voxel then continue end

		if Settings.ClientTweenPuppets then
			TweenService:Create(voxel, TweenInfo.new(1 / Settings.PuppetReplicationFrequency, Enum.EasingStyle.Linear), {
				CFrame = state.CFrame
			}):Play()
		else
			voxel.CFrame = state.CFrame
		end
    end
end


local function DestroyPuppet(guid)
	local found = Puppets[guid]
	if not found then return end
	found:Destroy()

	Puppets[guid] = nil
end



local function ReplicateMapToNewPlayer(plr)
	local toReplicate = {}
	for _, child in ipairs(workspace.CurrentCamera:GetChildren()) do
		if not child:IsA("Part") then continue end
		table.insert(toReplicate, {
			CFrame = child.CFrame,
			Size = child.Size,
			Color = child.Color,
			Material = child.Material.Value,
			Transparency = child.Transparency
		})
	end
	for _, opDirty in pairs(opDirties) do
		for _, dirty in ipairs(opDirty.dirtied) do
			local p = dirty.Part
			table.insert(toReplicate, {
				CFrame = p.CFrame,
				Size = p.Size,
				Color = p.Color,
				Material = p.Material.Value,
				Transparency = p.Transparency
			})
		end
	end
	if #toReplicate == 0 then return end
	ServerEvents.ReplicateMap.Fire(plr, toReplicate)
end


local function ReplicateMapFromServer(MapParts)

	for _, mapPart in ipairs(MapParts) do
		local Part = Instance.new("Part")
		Part.Anchored = true
		Part.Color = mapPart.Color
		Part.Size = mapPart.Size
		Part.CFrame = mapPart.CFrame
		Part.Material = Enum.Material:FromValue(mapPart.Material)
		Part.Transparency = mapPart.Transparency
		Part.Parent = clientMapFolder
	end
end








Shatterbox.Settings = Settings



function Shatterbox.Puppeteer(voxel : Part)
	assert(isServer, "This function can only be called from the server")

	voxel:AddTag(IndestructibleTag)
	voxel.Parent = workspace.CurrentCamera

	local noSleepDelay = 0.5
	local accum = 0

	local noSleepCon : RBXScriptConnection
	noSleepCon = RunService.Heartbeat:Connect(function(deltaTime)
		accum += deltaTime
		while accum > noSleepDelay do
			accum -= noSleepDelay
			voxel:ApplyImpulse(Vector3.yAxis * -0.0001)
		end
	end)

	local guid = HttpService:GenerateGUID(false)

	Puppets[guid] = voxel

	table.insert(CreatePuppetQueue, { guid, voxel })
	voxel.Destroying:Connect(function()
		noSleepCon:Disconnect()
		Puppets[guid] = nil

		local found
		for i, toCreate in ipairs(CreatePuppetQueue) do
			if toCreate[1] == guid then found = i break end
		end
		if found then table.remove(CreatePuppetQueue, found) end

		ServerEvents.DestroyPuppet.FireAll(guid)
	end)
end



-- Completely voxelizes a given part down to a specified GridSize, or uses the default GridSize specified in the Settings. <br>
--
-- Returns the created voxels as an array. <br>
--
-- Optimized by using math to fully subdivide a part before creating only the final voxels. However, it effectively has an O(N^3) runtime due to the nature of 3D grids.
function Shatterbox.Voxelize(Part : Part, GridSize : number?) : {Part}

	local createdParts = {}

	for _, imaginaryPart in ipairs(ImaginaryVoxelize(Part, GridSize)) do

		local created = Part:Clone()
		created.CFrame = imaginaryPart.CFrame
		created.Size = imaginaryPart.Size
		created.Parent = Part.Parent

		table.insert(createdParts, created)
	end

	Part:Destroy()

	return createdParts
end



-- Performs voxel destruction around the 'intersectingPart' according to the OverlapParams supplied.
function Shatterbox.Destroy(intersectingPart : Part | Model | Types.DestructionParams, overlapParams : OverlapParams?, CleanupDelay : number?, OnVoxelDestruct : string?, GridSize : number?, SkipEncapsulatedVoxels : boolean?, OnDestructCompleted : (() -> ())?, ... : any)
	assert(isServer, "You can only use Destroy on the server-side in this release.")

	local isPart, isModel, isTbl = false, false, typeof(intersectingPart) == "table"
	local cuttingPart = intersectingPart
	if isTbl then  cuttingPart = intersectingPart.CuttingPart end
	isPart, isModel = cuttingPart and cuttingPart:IsA("Part"), cuttingPart and cuttingPart:IsA("Model")
	assert(isPart or isModel or isTbl, "The input parameter to the destruction function must be a Part, Model, or a Table")
	assert(not isTbl or (intersectingPart.CuttingPart or (intersectingPart.CFrame and intersectingPart.Size and intersectingPart.Shape)), "If you supply a table, it must have a CuttingPart or at least a CFrame, Size, and Shape.")

	local params = ValidateDestructionParams(intersectingPart, overlapParams, CleanupDelay, OnVoxelDestruct, GridSize, SkipEncapsulatedVoxels, OnDestructCompleted, ...)
	task.defer(function()

		if isModel then
			for _, desc in ipairs(cuttingPart:GetDescendants()) do 
				if not desc:IsA("Part") then continue end
				local p = table.clone(params)
				p.CuttingPart = desc
				Shatterbox.Destroy(p) 
			end
			return
		end

		params.ID = params.ID or HttpService:GenerateGUID(false)

		if isServer then
			ReplicateDestructionToClients(params, os.time() + params.CleanupDelay)
		end

		local del = params.CleanupDelay

		if del > 0 then
			opDirties[params.ID] = opDirties[params.ID] or {
				intersectingPart = params.CuttingPart,
				dirtied = {}
			}

			-- starts the smooth cleanup counter
			if isServer and Settings.UseSmoothCleanup then task.delay(del, UndoDirtyOp, params.ID) end

			InsertToShatterQueue(params)
		end
	end)
end



-- Instantly performs voxel destruction around 'intersectingPart', skipping as many intermediate parts as possible. <br>
--
-- Returns an array of imaginary voxels for you to optionally create as debris.
function Shatterbox.ImaginaryVoxels(intersectingPart : Part | Model | Types.DestructionParams, overlapParams : OverlapParams?, CleanupDelay : number?, GridSize : number?, SkipEncapsulatedVoxels : boolean?, destroyIntersectingPart : boolean?) : {Types.ImaginaryVoxel}
	local isPart, isModel, isTbl = false, false, typeof(intersectingPart) == "table"
	local cuttingPart = intersectingPart
	if isTbl then  cuttingPart = intersectingPart.CuttingPart end
	isPart, isModel = cuttingPart and cuttingPart:IsA("Part"), cuttingPart and cuttingPart:IsA("Model")
	assert(isPart or isModel or isTbl, "The input parameter to the destruction function must be a Part, Model, or a Table")
	assert(not isTbl or (intersectingPart.CuttingPart or (intersectingPart.CFrame and intersectingPart.Size and intersectingPart.Shape)), "If you supply a table, it must have a CuttingPart or at least a CFrame, Size, and Shape.")

	local params = ValidateDestructionParams(intersectingPart, overlapParams, CleanupDelay, nil, GridSize, SkipEncapsulatedVoxels)
	if isTbl and (intersectingPart.destroyIntersectingPart or not intersectingPart.CuttingPart) then params.destroyIntersectingPart = true end

	local voxels = {} :: {Types.ImaginaryVoxel}

	if isModel then
		for _, desc in ipairs(cuttingPart:GetDescendants()) do
			if not desc:IsA("Part") then continue end
			local p = table.clone(params)
			p.CuttingPart = desc
			local imaginaryVoxels = ImaginaryVoxels(p)
			table.move(imaginaryVoxels, 1, #imaginaryVoxels, #voxels + 1, voxels)
		end
		return voxels
	end

	params.ID = params.ID or HttpService:GenerateGUID(false)

	opDirties[params.ID] = opDirties[params.ID] or {
		intersectingPart = params.CuttingPart,
		dirtied = {}
	}

	return ImaginaryVoxels(params)
end



-- resets all modified parts to where they originally were (turning the map back to normal)
function Shatterbox.Reset()
	DivQueue = {}
	ShatterQueue = {}

	tmpFolder:ClearAllChildren()

	for ID in pairs(opDirties) do UndoDirtyOp(ID) end

	opDirties = {}

	if isClient then
		clientMapFolder:ClearAllChildren()
	end

	if isServer then
		workspace.CurrentCamera:ClearAllChildren()
		for _, toRestore in ipairs(ToReset) do
			local cloned = toRestore.Part:Clone()
			cloned.Parent = toRestore.OriginalParent
		end
		ToReset = {}
		ServerEvents.SignalReset.FireAll()
	end
end



-- Cancels any ongoing operations
function Shatterbox.ClearQueue()
	DivQueue = {}
	ShatterQueue = {}

	if isServer then ServerEvents.SignalClearQueue.FireAll() end
end



-- Creates a "Hitbox" object which can be used in place of the destruction functions, and has additional functionality. (like VoxBreaker moveable hitbox)
function Shatterbox.CreateHitbox()

	local hitbox = {}
	hitbox.CFrame = CFrame.new() :: CFrame
	hitbox.Size = Vector3.new(1, 1, 1) :: Vector3
	hitbox.Shape = Enum.PartType.Ball :: Enum.PartType
	hitbox.OverlapParams = nil :: OverlapParams?
	hitbox.OnVoxelDestruct = nil :: string?
	hitbox.DestructParameters = {} :: {any}
	hitbox.OperationCompletedCallback = nil :: (() -> ())?
	hitbox.CleanupDelay = nil :: number?
	hitbox.DestructDelay = nil :: number?
	hitbox.GridSize = nil :: number?
	hitbox.SkipEncapsulatedVoxels = false :: boolean

	-- Performs voxel destruction around the hitbox
	function hitbox:Destroy() Shatterbox.Destroy(hitbox) end

	-- returns the imaginary voxels bounded by the hitbox as an array, for you to optionally create
	function hitbox:ImaginaryVoxels() return Shatterbox.ImaginaryVoxels(hitbox) :: {Types.ImaginaryVoxel} end


	local wcon : RBXScriptConnection?
	local dcon : RBXScriptConnection?

	-- will "weld" the hitbox to the given part, continously setting its CFrame to be equal to the parts CFrame.
	-- If the Part is destroyed using ":Destroy()", the hitbox will be automatically stopped and disconnected.
	function hitbox:WeldTo(Part : BasePart)
		if wcon then wcon:Disconnect() end
		if dcon then dcon:Disconnect() end
		hitbox.CFrame = Part.CFrame
		wcon = RunService.PostSimulation:Connect(function() hitbox.CFrame = Part.CFrame end)
		dcon = Part.Destroying:Connect(hitbox.Destroy)
	end

	-- will "unweld" the hitbox
	function hitbox:Unweld()
		if wcon then wcon:Disconnect() end
		if dcon then dcon:Disconnect() end
		wcon, dcon = nil, nil
	end

	local ccon : RBXScriptConnection?
	local lastCut : number 

	local function DestroyConnection()
		local t = time()
		if lastCut and t - lastCut < (hitbox.DestructDelay or 0.1) then return end
		lastCut = t
		hitbox:Destroy()
	end

	-- will continuously cut around the hitbox every hitbox.DestructDelay seconds, which defaults to 0.1
	function hitbox:Start()
		if ccon then return end
		ccon = RunService.Heartbeat:Connect(DestroyConnection)
	end

	-- will stop continuous destruction
	function hitbox:Stop()
		if ccon then ccon:Disconnect() end
		ccon = nil
	end

	-- will disconnect all connections.
	function hitbox:DestroyHitbox()
		hitbox:Unweld()
		hitbox:Stop()
	end

	return hitbox
end



-- Will return true if "contains" is FULLY contained by "part", otherwise false
function Shatterbox.PartEncapsulatesBlockPart(part : Part, contains : Part)
	assert(part:IsA("Part"), "You can only use this function when a Part is the container.")
	assert(contains:IsA("Part") and contains.Shape == Enum.PartType.Block, "You can only use this function when a Block Part is the contained object.")	
	return PartEncapsulatesBlockPart(part, contains.CFrame, contains.Size)
end



-- Will register the given callback to the given name. It's suggested you do this at the top of the module instead, otherwise it is only registered on the side you called this function from.
function Shatterbox.RegisterOnVoxelDestruct(name : string, callback : Types.OnVoxelDestruct) RegisterOnVoxelDestruct(name, callback, callback) end



-- Will wait for the given OnVoxelDestruct callback to be registered with a default timeout of 5 seconds
function Shatterbox.WaitForRegistry(name : string, timeout : number?) : string
	timeout = timeout or 5
	local elapsed, start = 0, time()	
	while elapsed < timeout and not rawget(OnVoxelDestructRegistry, name:lower()) do
		RunService.Heartbeat:Wait()
		elapsed = time() - start
	end
	if elapsed > timeout then warn(`Infinite yield possible on WaitForRegistry("{name}")`) end
	return name
end



Shatterbox.OnVoxelDestruct = HandleVoxelDestruction



if isServer then
	ServerEvents.MapReplicationCompleted.On(StopWaitingOnUser)

	Players.PlayerAdded:Connect(ReplicateMapToNewPlayer)
end


if isClient then
	ClientEvents.SignalDestruction.On(ReplicateDestructionFromServer)
	ClientEvents.SignalUndo.On(UndoDirtyOp)
	ClientEvents.SignalClearQueue.On(Shatterbox.ClearQueue)
	ClientEvents.SignalReset.On(Shatterbox.Reset)

	ClientEvents.CreatePuppets.On(CreatePuppets)
	ClientEvents.ReplicatePuppetStates.On(ReplicatePuppetStates)
	ClientEvents.DestroyPuppet.On(DestroyPuppet)

	ClientEvents.ReplicateMap.On(ReplicateMapFromServer)
end



RunService.Heartbeat:Connect(HeartbeatWorker)

return Shatterbox
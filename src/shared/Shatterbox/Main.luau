--!native
--!optimize 2


-- Shatterbox release 7.7


--#selene: allow(multiple_statements)
--#selene: allow(unused_variable)
--#selene: allow(incorrect_standard_library_use)
--#selene: allow(shadowing)

local IndestructibleTag = "Indestructible"


local lib = script.Parent:WaitForChild("lib")
-- Shatterbox uses Blink for Client-Server communications
local PathToClient = lib:WaitForChild("Client")
local PathToServer = lib:WaitForChild("Server")

--[[ IF YOU ALSO USE BLINK:

	These steps ensure events are properly batched using Blink, saving performance.
	I don't think anything bad happens if you don't set up batching using these steps.

	1. Import the "Shatterbox.blink" file to your Blink config:		import "PATH_TO_SHATTERBOX/Shatterbox.blink"

	2. Rebuild your blink files

	3. Re-define PathToServer and PathToClient local variables defined above to the location of your blink files
]]

--[[ ROBLOX STUDIO BLINK USERS:

	You can run this in the command line to populate/update the Shatterbox blink file, then you can continue above from Step 1 (use  import "Shatterbox" ):

	local HS = game:GetService("HttpService");
	local O = HS.HttpEnabled;
	HS.HttpEnabled = true;
	local S = HS:GetAsync("https://raw.githubusercontent.com/azavier-a/Shatterbox/refs/heads/main/src/shared/Shatterbox/Shatterbox.blink");
	HS.HttpEnabled = O;
	local SS = game:GetService("ServerStorage");
	local F = SS:FindFirstChild("BLINK_CONFIGURATION_FILES");
	if not F then
		F = Instance.new("Folder");
		F.Name = "BLINK_CONFIGURATION_FILES";
		F.Parent = SS;
	end
	local SV = F:FindFirstChild("Shatterbox");
	if not SV then
		SV = Instance.new("StringValue");
		SV.Name = "Shatterbox";
		SV.Parent = F;
	end
	SV.Value = S;
]]
local RunService = game:GetService("RunService")
local isServer, isClient = RunService:IsServer(), RunService:IsClient()

-- See "HowToUse" for an explanation of the settings.

-- Set this to false if you don't want to use client-server functionality (false = fully server side destructions)
local USE_CLIENT_SERVER = true


local Settings = {}

Settings.UseSmoothCleanup = true

--Settings.UseDynamicReset = true

--Settings.DynamicResetDelay = 3

Settings.MaxDivisionsPerFrame = 100

Settings.DefaultSmoothCleanupDelay = 60

Settings.DefaultGridSize = 1

Settings.UsePriorityQueue = true

Settings.PrioritizeRecentN = 10

Settings.PuppetReplicationFrequency = 10 -- 10 fps/Hz target replication frequency

Settings.ClientTweenPuppets = true

Settings.PuppetReplicationFrameLimit = 10

Settings.PuppetSleepVelocity = 0.001

Settings.SkipInstanceCheck = function(i : Instance)

	-- return true if you want to skip the instance "i"

	return false
end



local ClientEvents, ServerEvents, clientMapFolder, tmpFolder
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



-- The ShatterboxTemporary folder, which contains things like debris (but also sometimes CuttingParts for a single frame)
tmpFolder = workspace:FindFirstChild("ShatterboxTemporary") or Instance.new("Folder")
tmpFolder.Parent = workspace
tmpFolder.Name = "ShatterboxTemporary"



-- If you modify any code below here, you are at serious risk of breaking the module. It probably already has a way to do what you need to do.

local Shatterbox = {}

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

if isServer then
	if USE_CLIENT_SERVER then
		local ref = Instance.new("ObjectValue")
		ref.Name = "ShatterboxModule"
		ref.Value = script
		local scr = lib.InitializeShatterbox
		ref.Parent = scr
		scr.Parent = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
		scr.Enabled = true
	end
	ServerEvents = require(PathToServer).Shatterbox

	local serverEffects = require(script.Parent.effects.Server)
	serverEffects:SetReference(Shatterbox)
	serverEffects.SetReference = nil
	for name, func in pairs(serverEffects) do OnVoxelDestructRegistry[name:lower()] = func end
elseif isClient then
	if USE_CLIENT_SERVER then
		clientMapFolder = workspace:FindFirstChild("ClientMap") or Instance.new("Folder")
		clientMapFolder.Parent = workspace
		clientMapFolder.Name = "ClientMap"
	end
	ClientEvents = require(PathToClient).Shatterbox

	local clientEffects = require(script.Parent:WaitForChild("effects"):WaitForChild("Client"))
	clientEffects:SetReference(Shatterbox)
	clientEffects.SetReference = nil
	for name, func in pairs(clientEffects) do OnVoxelDestructRegistry[name:lower()] = func end
end

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local VertexMath = require(lib:WaitForChild("VertexMath"))
local TaggedArray = require(script.Parent:WaitForChild("util"):WaitForChild("TaggedArray"))
local PartEncapsulatesBlockPart = VertexMath.PartEncapsulatesBlockPart
local GetBlockPartVertices = VertexMath.GetBlockPartVertices
local PartContainsAVert, PartContainsAllVerts = VertexMath.PartContainsAVert, VertexMath.PartContainsAllVerts

local SubdivideFunctions = {
	KD = VertexMath.KDS,
	MOT = VertexMath.MOTS
}

local defaultOverlapParams = OverlapParams.new()
defaultOverlapParams.FilterType = Enum.RaycastFilterType.Exclude
defaultOverlapParams.FilterDescendantsInstances = { tmpFolder }

local opDirties = {} :: {
	[string]: {
		{ Part : Part, OriginalParent : Instance, model : Model }
	}
}

local ShatterQueue = {} :: { Types.DestructionParams }
local DivQueue = {}
local frameDivs = 0

local Puppets = {} :: { [string] : Part }
local CreatePuppetQueue = {}

local ToReset = {} :: { [string] : {{Part : Part, OriginalParent : Instance, model : Model}}}

--local activeReset = false
--local lastOpTick = nil

local accum = 0


local function AncestorGroupTags(i : Instance, tags) : {string}
	tags = tags or {}

	local ancestor = i:FindFirstAncestorWhichIsA("Folder")
	if not ancestor then
		ancestor = i:FindFirstAncestorWhichIsA("Model")
		if not ancestor then return tags end
	end

	local t = ancestor:GetTags()
	if #t > 0 then
		table.move(t, 1, #t, #tags + 1, tags)
	end

	return AncestorGroupTags(ancestor, tags)
end


-- returns OverlapParams including all instances with the given tags.
local function OverlapParamsOfTagged(tags : { string }, instant) : OverlapParams
	local arr = {}

	if #tags == 1 then
		arr = if instant then CollectionService:GetTagged(tags[1]) else TaggedArray(tags[1])
	else
		for _, tag in ipairs(tags) do
			local taggedArray = if instant then CollectionService:GetTagged(tag) else TaggedArray(tag)
			table.move(taggedArray, 1, #taggedArray, #arr + 1, arr)
		end
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = arr

	return overlapParams
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


local function UndoDirtyOp(ID : string, replicated : boolean?)

	if USE_CLIENT_SERVER and isServer then ServerEvents.SignalUndo.FireAll(ID) end

	local intersectedDirties = opDirties[ID]
	if not intersectedDirties then
		if replicated then
			local reset = false
			local disconnect = ClientEvents.SignalReset.On(function() reset = true end)
			repeat RunService.Heartbeat:Wait() until opDirties[ID] or reset
			disconnect()
			if reset then return end
			intersectedDirties = opDirties[ID]
		else return end
	end
	opDirties[ID] = nil

	local found
	for i, v in ipairs(ShatterQueue) do
		if v.ID ~= ID then continue end
		v.CuttingPart:Destroy()
		found = i;
		break
	end
	if found then table.remove(ShatterQueue, found) end

	for _, dirtied in ipairs(intersectedDirties) do
		local restored = dirtied.Part:Clone()
		restored.Parent = dirtied.model.Parent
		dirtied.model:Destroy()
	end

	--[[
	if isServer then
		if next(opDirties) then
			ServerEvents.SignalUndo.FireAll(ID)
		elseif Settings.UseDynamicReset and not activeReset then
			lastOpTick = os.time()
			activeReset = true
			while os.time() - lastOpTick < Settings.DynamicResetDelay do
				RunService.Heartbeat:Wait()
			end
			activeReset = false
			Shatterbox.Reset()
		end
	end
	--]]
end


local function MarkDirty(ID, Part : Part)

	if Part:HasTag("ShatterboxDebris") then return end

	local PartParent = Part.Parent

	if PartParent and not PartParent:HasTag("ShatterboxInstance") then
		local model = Instance.new("Model")

		if USE_CLIENT_SERVER and isServer then
			for _, tag in ipairs(AncestorGroupTags(Part)) do
				model:AddTag(tag)
				Part:AddTag(tag)
			end

			if not Part:IsDescendantOf(workspace.CurrentCamera) then
				--if activeReset then lastOpTick = os.time() end
				ToReset[ID] = ToReset[ID] or {}
				table.insert(ToReset[ID], {
					Part = Part,
					OriginalParent = PartParent,
					model = model
				})
			end

			model.Parent = workspace.CurrentCamera
		elseif USE_CLIENT_SERVER then
			model.Parent = clientMapFolder
		else
			model.Parent = PartParent
		end

		model.Name = Part.Name
		model:AddTag("ShatterboxInstance")
		model:SetAttribute("GridSize", Part:GetAttribute("GridSize"))
		for _, tag in ipairs(Part:GetTags()) do
			model:AddTag(tag)
		end

		Part.Parent = model

		opDirties[ID] = opDirties[ID] or {}
		table.insert(opDirties[ID], {
			Part = Part,
			OriginalParent = PartParent,
			model = model
		})
	end
end


-- Uses the given callback from the OnVoxelDestruct registry to destroy the given voxel
local function HandleVoxelDestruction(callbackName : string?, voxel : Part, dirtyParent : Model, intersectingPart : BasePart, isEdge : boolean, ... : any)
	if not voxel:HasTag("ShatterboxDebris") then voxel.Parent = tmpFolder end
	local args = { ... }
	coroutine.wrap(function()
		OnVoxelDestructRegistry[callbackName](voxel, dirtyParent, intersectingPart, isEdge, unpack(args))
		voxel:AddTag("ShatterboxDebris")
	end)()
end


local function GetDestructibleParts(ID, cuttingPart, filterTagged, instant, replicated)
	local partsInPart = {}

	local overlapParams =
		if filterTagged then
			OverlapParamsOfTagged(filterTagged, instant)
		else
			defaultOverlapParams

	local op = cuttingPart.Parent
	cuttingPart.Parent = tmpFolder
	for _, part in ipairs( workspace:GetPartsInPart(cuttingPart, overlapParams) ) do

		if replicated and not part:IsDescendantOf(clientMapFolder) then continue end

		if ShouldSkipInstance(part) then continue end

		MarkDirty(ID, part) -- adds this part to the smooth cleanup for this destruction, if it's not already destroyed by something else

		table.insert(partsInPart, part)
	end
	cuttingPart.Parent = op

	return partsInPart
end


-- pops an element from the ShatterQueue, removing the completed operations that it might find before finding one to complete.
local function PopShatterQueue()
	local popped, shatterPart, partsInPart
	local v = table.remove(ShatterQueue)

	while v and not popped do

		shatterPart, partsInPart = v.CuttingPart, {}

		for _, part in ipairs( GetDestructibleParts(v.ID, shatterPart, v.FilterTagged, false, v.replicated) ) do

			if part:HasTag("ShatterboxDebris") then
				HandleVoxelDestruction(v.OnVoxelDestruct, part, part.Parent, shatterPart, Shatterbox.PartEncapsulatesBlockPart(shatterPart, part), unpack(v.DestructParameters))
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

	for _, c in ipairs(created) do
		local instanced = Instance.new("Part")
		instanced.Transparency = Part.Transparency
		instanced.Reflectance = Part.Reflectance
		instanced.Material = Part.Material
		instanced.Color = Part.Color
		instanced.Anchored = true
		instanced.CFrame = c.CFrame
		instanced.Size = c.Size
		instanced.Parent = dirtyParent
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
		local partGridSize = GridSize or Part:GetAttribute("GridSize") or Part.Parent:GetAttribute("GridSize") or Settings.DefaultGridSize

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

	table.insert(ShatterQueue, params)
end


local function ImaginaryVoxels(params)

	local voxels = {} :: {Types.ImaginaryVoxel}

	local partsInPart, destructibleParts = {}, GetDestructibleParts(params.ID, params.CuttingPart, params.FilterTagged, true, params.replicated)

	for _, part in ipairs(destructibleParts) do
		table.insert(partsInPart, {
			CFrame = part.CFrame,
			Size = part.Size,
			DirtyParent = part.Parent,
			Original = part,
			GridSize = params.GridSize or part:GetAttribute("GridSize") or part.Parent:GetAttribute("GridSize") or Settings.DefaultGridSize
		})
	end

	if #partsInPart == 0 then
		if params.destroyIntersectingPart then params.CuttingPart:Destroy() end

		if not params.replicated and Settings.UseSmoothCleanup then task.delay(params.CleanupDelay, UndoDirtyOp, params.ID, params.replicated) end

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

			local P = toDivide.Original
			local newStatic = Instance.new("Part")
			newStatic.Material = P.Material
			newStatic.Transparency = P.Transparency
			newStatic.Reflectance = P.Reflectance
			newStatic.Color = P.Color
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


local function ValidateDestructionParams(intersectingPart : Part | Model | Types.DestructionParams, FilterTagged : (string | {string})?, CleanupDelay : number?, OnVoxelDestruct : string?, GridSize : number?, SkipEncapsulatedVoxels : boolean?, OnDestructCompleted : (() -> ())?, ... : any)
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

	local filterTagged = iP.FilterTagged or FilterTagged
	if typeof(filterTagged) == "string" then filterTagged = { filterTagged } end

			params.FilterTagged = filterTagged
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
				Transparency = voxel.Transparency,
				Reflectance = voxel.Reflectance
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



local function SerializedPartInstance(p)
	return {
		CFrame = p.CFrame,
		Size = p.Size,

		Color = p.Color,
		Material = p.Material.Value,
		Transparency = p.Transparency,
		Reflectance = p.Reflectance,

		Tags = p:GetTags(),
		GridSize = p:GetAttribute("GridSize")
	}
end



local function GetMapParts(ID)
	local tr = ToReset[ID]
	if not tr then return nil end

	local mapParts = {}

	for _, dirtied in ipairs(tr) do
		table.insert(mapParts, SerializedPartInstance(dirtied.Part))
	end

	return mapParts
end


local function CreateReplicatedMapParts(ID, mapParts)
	if not mapParts then return end

	for _, serialPart in ipairs(mapParts) do
		local Part = Instance.new("Part")
		Part.Anchored = true
		Part.Size = serialPart.Size
		Part.CFrame = serialPart.CFrame

		Part.Color = serialPart.Color
		Part.Material = Enum.Material:FromValue(serialPart.Material)
		Part.Transparency = serialPart.Transparency
		Part.Reflectance = serialPart.Reflectance

		Part:SetAttribute("GridSize", serialPart.GridSize)
		for _, tag in ipairs(serialPart.Tags) do
			Part:AddTag(tag)
		end

		Part.Parent = clientMapFolder

		if ID then MarkDirty(ID, Part) end
	end
end


local function ReplicateDestructionFromServer(params, mapParts)
	params.Shape = Enum.PartType:FromValue(params.Shape)

	local dParams = ValidateDestructionParams(params)

 	CreateReplicatedMapParts(dParams.ID, mapParts)

	dParams.replicated = true

	InsertToShatterQueue(dParams)
end


local function ReplicateDestructionToClients(destructionParams : Types.DestructionParams)
	destructionParams = table.clone(destructionParams)
	destructionParams.Shape = destructionParams.Shape.Value
	destructionParams.OnDestructCompleted = nil
	destructionParams.CuttingPart = nil

	ServerEvents.ReplicateDestruction.FireAll(destructionParams, GetMapParts(destructionParams.ID))
end


local function ReplicateImaginaryFromServer(params, mapParts)
	params.Shape = Enum.PartType:FromValue(params.Shape)
	params.SkipEncapsulatedVoxels = true

	local dParams = ValidateDestructionParams(params)

	CreateReplicatedMapParts(dParams.ID, mapParts)

	dParams.replicated = true

	RunService.Heartbeat:Wait()
	DivQueue = {}
	ImaginaryVoxels(dParams)
end


local function ReplicateImaginaryToClients(destructionParams : Types.DestructionParams)
	destructionParams = table.clone(destructionParams)
	destructionParams.Shape = destructionParams.Shape.Value
	destructionParams.OnDestructCompleted = nil
	destructionParams.OnVoxelDestruct = nil
	destructionParams.CuttingPart = nil
	destructionParams.SkipEncapsulatedVoxels = nil

	ServerEvents.ReplicateImaginary.FireAll(destructionParams, GetMapParts(destructionParams.ID))
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
		Part.Reflectance = puppet.Reflectance
		Part.Parent = tmpFolder

		Puppets[puppet.GUID] = Part
	end
end


local function ReplicatePuppetStates(puppetStates)
	local numPuppets = 0
	for _ in pairs(Puppets) do numPuppets += 1 end
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
	local visitiedIDs = {}
	local replicatedDirties = {}
	local replicatedResets = {}

	local filterDesc = {}

	for ID, dirtied in pairs(opDirties) do
		visitiedIDs[ID] = true
		local serialDirties = {}
		for _, dirty in ipairs(dirtied) do
			local serialChildren = {}
			for _, p in ipairs(dirty.model:GetChildren()) do
				table.insert(serialChildren, {
					CFrame = p.CFrame,
					Size = p.Size,
				})
			end
			table.insert(filterDesc, dirty.model)
			local p = dirty.Part
			local serialDirtied = {}
			serialDirtied.OriginalPart = { CFrame = p.CFrame, Size = p.Size }
			serialDirtied.Children = serialChildren
			serialDirtied.GridSize = p:GetAttribute("GridSize")
			serialDirtied.Tags = p:GetTags()
			serialDirtied.Color = p.Color
			serialDirtied.Material = p.Material.Value
			serialDirtied.Transparency = p.Transparency
			serialDirtied.Reflectance = p.Reflectance
			table.insert(serialDirties, serialDirtied)
		end
		table.insert(replicatedDirties, {
			ID = ID,
			Dirties = serialDirties
		})
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = filterDesc

	for ID, toReset in pairs(ToReset) do
		if visitiedIDs[ID] then continue end

		for _, dirtied in ipairs(toReset) do
			if #workspace:GetPartsInPart(dirtied.Part, overlapParams) > 0 then continue end
			table.insert(replicatedResets, SerializedPartInstance(dirtied.Part))
		end
	end

	if #replicatedDirties == 0 and #replicatedResets == 0 then return end

	ServerEvents.ReplicateMap.Fire(plr, replicatedDirties, replicatedResets)
end


local function ReplicateMapFromServer(SerialOpDirties, mapParts)

	for _, serialOpDirty in ipairs(SerialOpDirties) do
		local dirtied = {}

		for _, serialDirtied in ipairs(serialOpDirty.Dirties) do
			local C = serialDirtied.Color
			local M = Enum.Material:FromValue(serialDirtied.Material)
			local T = serialDirtied.Transparency
			local R = serialDirtied.Reflectance

			local replicatedOriginal = Instance.new("Part")
			replicatedOriginal.Anchored = true
			replicatedOriginal.CFrame = serialDirtied.OriginalPart.CFrame
			replicatedOriginal.Size = serialDirtied.OriginalPart.Size
			replicatedOriginal.Color = C
			replicatedOriginal.Material = M
			replicatedOriginal.Transparency = T
			replicatedOriginal.Reflectance = R or 0
			replicatedOriginal:SetAttribute("GridSize", serialDirtied.GridSize)

			local model = Instance.new("Model");
			model:AddTag("ShatterboxInstance")
			model:SetAttribute("GridSize", serialDirtied.GridSize)

			for _, tag in ipairs(serialDirtied.Tags) do
				replicatedOriginal:AddTag(tag)
				model:AddTag(tag)
			end

			for _, serialChild in ipairs(serialDirtied.Children) do
				local Part = Instance.new("Part")
				Part.Anchored = true
				Part.Size = serialChild.Size
				Part.CFrame = serialChild.CFrame
				Part.Color = C
				Part.Material = M
				Part.Transparency = T
				Part.Reflectance = R or 0
				Part.Parent = model
			end

			model.Parent = clientMapFolder
			table.insert(dirtied, { model = model, Part = replicatedOriginal })
		end

		opDirties[serialOpDirty.ID] = dirtied
	end

	CreateReplicatedMapParts(nil, mapParts)
end







Shatterbox.Settings = Settings



function Shatterbox.Puppeteer(voxel : Part)
	assert(isServer, "This function can only be called from the server")

	voxel:AddTag(IndestructibleTag)
	if not voxel.Anchored then voxel:SetNetworkOwner(nil) end
	voxel.Parent = workspace.CurrentCamera

	local noSleepCon : RBXScriptConnection
	noSleepCon = RunService.Heartbeat:Connect(function(deltaTime)
		voxel:ApplyImpulse(Vector3.yAxis * -0.0001)
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


-- Performs voxel destruction around the 'intersectingPart' according to the FilterTagged supplied.
--
-- if no FilterTagged is given, everything except IndestructibleTag tagged Block parts are considered for destruction.
function Shatterbox.Destroy(intersectingPart : Part | Model | Types.DestructionParams, FilterTagged : (string | {string})?, CleanupDelay : number?, OnVoxelDestruct : string?, GridSize : number?, SkipEncapsulatedVoxels : boolean?, OnDestructCompleted : (() -> ())?, ... : any)
	local isPart, isModel, isTbl = false, false, typeof(intersectingPart) == "table"
	local cuttingPart = intersectingPart
	if isTbl then  cuttingPart = intersectingPart.CuttingPart end
	isPart, isModel = cuttingPart and cuttingPart:IsA("Part"), cuttingPart and cuttingPart:IsA("Model")
	assert(isPart or isModel or isTbl, "The input parameter to the destruction function must be a Part, Model, or a Table")
	assert(not isTbl or (intersectingPart.CuttingPart or (intersectingPart.CFrame and intersectingPart.Size and intersectingPart.Shape)), "If you supply a table, it must have a CuttingPart or at least a CFrame, Size, and Shape.")

	local params = ValidateDestructionParams(intersectingPart, FilterTagged, CleanupDelay, OnVoxelDestruct, GridSize, SkipEncapsulatedVoxels, OnDestructCompleted, ...)
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

		if #GetDestructibleParts(params.ID, params.CuttingPart, params.FilterTagged, true) == 0 then
			return
		end

		-- starts the smooth cleanup counter
		if Settings.UseSmoothCleanup then task.delay(params.CleanupDelay, UndoDirtyOp, params.ID) end

		if params.CleanupDelay <= 0 then return end

		if USE_CLIENT_SERVER and isServer then
			ReplicateDestructionToClients(params)
		end

		InsertToShatterQueue(params)
	end)
end


--*Yields until the NEXT Heartbeat to perform instant destruction.* <br>
--
--Performs voxel destruction around 'intersectingPart', skipping as many intermediate parts as possible. <br>
--
-- Returns an array of imaginary voxels for you to optionally create as debris.
function Shatterbox.ImaginaryVoxels(intersectingPart : Part | Model | Types.DestructionParams, FilterTagged : (string | {string})?, CleanupDelay : number?, GridSize : number?, SkipEncapsulatedVoxels : boolean?, destroyIntersectingPart : boolean?) : {Types.ImaginaryVoxel}
	local isPart, isModel, isTbl = false, false, typeof(intersectingPart) == "table"
	local cuttingPart = intersectingPart
	if isTbl then  cuttingPart = intersectingPart.CuttingPart end
	isPart, isModel = cuttingPart and cuttingPart:IsA("Part"), cuttingPart and cuttingPart:IsA("Model")
	assert(isPart or isModel or isTbl, "The input parameter to the destruction function must be a Part, Model, or a Table")
	assert(not isTbl or (intersectingPart.CuttingPart or (intersectingPart.CFrame and intersectingPart.Size and intersectingPart.Shape)), "If you supply a table, it must have a CuttingPart or at least a CFrame, Size, and Shape.")

	local params = ValidateDestructionParams(intersectingPart, FilterTagged, CleanupDelay, nil, GridSize, SkipEncapsulatedVoxels)
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

	if #GetDestructibleParts(params.ID, params.CuttingPart, params.FilterTagged, true) == 0 then
		return voxels
	end

	if USE_CLIENT_SERVER and isServer then
		ReplicateImaginaryToClients(params)
	end

	RunService.Heartbeat:Wait()
	DivQueue = {}
	return ImaginaryVoxels(params)
end


-- resets all modified parts to where they originally were (turning the map back to normal)
function Shatterbox.Reset()
	DivQueue = {}
	ShatterQueue = {}

	tmpFolder:ClearAllChildren()

	for ID in pairs(opDirties) do UndoDirtyOp(ID, USE_CLIENT_SERVER and isClient) end

	opDirties = {}

	if USE_CLIENT_SERVER then
		if isServer then
			workspace.CurrentCamera:ClearAllChildren()
			for _, toReset in pairs(ToReset) do
				for _, toRestore in ipairs(toReset) do
					local cloned = toRestore.Part:Clone()
					cloned.Parent = toRestore.OriginalParent
				end
			end
			ToReset = {}
			ServerEvents.SignalReset.FireAll()
		elseif isClient then
			clientMapFolder:ClearAllChildren()
		end
	end
end


-- Cancels any ongoing operations
function Shatterbox.ClearQueue()
	DivQueue = {}
	ShatterQueue = {}

	if USE_CLIENT_SERVER and isServer then ServerEvents.SignalClearQueue.FireAll() end
end


-- Creates a "Hitbox" object which can be used in place of the destruction functions, and has additional functionality. (like VoxBreaker moveable hitbox)
function Shatterbox.CreateHitbox()

	local hitbox = {}
	hitbox.CFrame = CFrame.new() :: CFrame
	hitbox.Size = Vector3.new(1, 1, 1) :: Vector3
	hitbox.Shape = Enum.PartType.Ball :: Enum.PartType
	hitbox.FilterTagged = nil :: (string | {string})?
	hitbox.OnVoxelDestruct = nil :: string?
	hitbox.DestructParameters = {} :: {any}
	hitbox.OperationCompletedCallback = nil :: (() -> ())?
	hitbox.CleanupDelay = nil :: number?
	hitbox.DestructDelay = nil :: number?
	hitbox.GridSize = nil :: number?
	hitbox.SkipEncapsulatedVoxels = false :: boolean

	-- Performs voxel destruction around the hitbox
	function hitbox:Destroy() Shatterbox.Destroy(hitbox) end

	--*Yields until the NEXT Heartbeat to perform instant destruction.* <br>
	--
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


local cachedOriginalClones = {} :: { [Model] : Part }

local function deleteClone(model)
	cachedOriginalClones[model]:Destroy()
	cachedOriginalClones[model] = nil
end

-- Returns a clone of the original, untouched part (before it was ever voxelized).
--
-- This is used for effects like JJS where they obliterate walls but only minorly destroy what you are standing on.
--
-- If you use this within an OnVoxelDestruct callback, it is guaranteed to work.
--
-- Clones are cached for 5 seconds, so calling this function multiple times within that timeframe returns the same instance.
function Shatterbox.GetOriginalPart(dirtyParent : Model) : Part?
	local found = cachedOriginalClones[dirtyParent]
	if found then return found end

	for _, dirties in pairs(opDirties) do
		for _, dirtied in ipairs(dirties) do
			if dirtied.model == dirtyParent then
				local clone = dirtied.Part:Clone()
				cachedOriginalClones[dirtyParent] = clone
				task.delay(5, deleteClone, dirtyParent)
				return clone
			end
		end
	end

	return nil
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
	if USE_CLIENT_SERVER then
		Players.PlayerAdded:Connect(ReplicateMapToNewPlayer)
	end
elseif isClient then
	if USE_CLIENT_SERVER then
		ClientEvents.SignalUndo.On(function(ID : string) UndoDirtyOp(ID, true) end)
		ClientEvents.SignalClearQueue.On(Shatterbox.ClearQueue)
		ClientEvents.SignalReset.On(Shatterbox.Reset)

		ClientEvents.ReplicateMap.On(ReplicateMapFromServer)
		ClientEvents.ReplicateDestruction.On(ReplicateDestructionFromServer)
		ClientEvents.ReplicateImaginary.On(ReplicateImaginaryFromServer)
	end
	ClientEvents.CreatePuppets.On(CreatePuppets)
	ClientEvents.ReplicatePuppetStates.On(ReplicatePuppetStates)
	ClientEvents.DestroyPuppet.On(DestroyPuppet)
end


RunService.Heartbeat:Connect(HeartbeatWorker)

return Shatterbox

--!native
--!optimize 2


-- Shatterbox release 7.8 beta 2


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

Settings.UseGreedyMeshing = true

Settings.GMTraversalsPerFrame = 2000

Settings.GMPartCreationsPerFrame = 5

Settings.GMWorkerCount = 10

Settings.UseSmoothCleanup = true

--Settings.UseDynamicReset = true

--Settings.DynamicResetDelay = 3

Settings.MaxDivisionsPerFrame = 300

--Settings.ImaginaryCreatedStaticPartsPerFrame = 200

--Settings.ImaginaryDestroyedStaticsPartsPerFrame = 200

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

--local ObjectCache = require(lib:WaitForChild("ObjectCache"))


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



-- The ShatterboxTemporary folder, which contains things like debris
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

local VertexMath = require(lib:WaitForChild("VertexMath"))
local TaggedArray = require(script.Parent:WaitForChild("util"):WaitForChild("TaggedArray"))
local PartEncapsulatesBlockPart = VertexMath.PartEncapsulatesBlockPart
local GetVerts, GetNormals = VertexMath.GetVerts, VertexMath.GetNormals
local BlockVerts, BlockNormals = GetVerts.Block, GetNormals.Block
local PartContainsAVert, PartContainsAllVerts = VertexMath.PartContainsAVert, VertexMath.PartContainsAllVerts

local SubdivideFunctions = {
	KD = VertexMath.KDS,
	MOT = VertexMath.MOTS
}

local defaultOverlapParams = OverlapParams.new()
defaultOverlapParams.FilterType = Enum.RaycastFilterType.Exclude
defaultOverlapParams.FilterDescendantsInstances = { tmpFolder }

local overlapParams = OverlapParams.new()

local opDirties = {} :: {
	[string]: {
		{ Part : Part, OriginalParent : Instance, model : Model, GridSize : number }
	}
}

local FlaggedDirty = {} :: {
	[string] : { {DirtyParent : Model, GridSize : number} }
}

local GreedyWorkers = {} :: { [Model] : thread }
local GreedyWorkersTerminationFlags = {} :: { [Model] : boolean }
local ActiveGMWorkerCount = 0

local ShatterQueue = {} :: { Types.DestructionParams }
local frameDivs = 0

local Puppets = {} :: { [string] : Part }
local CreatePuppetQueue = {}

--[[
local ImaginaryCreateQueue = {} :: { Types.ImaginaryBox }
local ImaginaryWorkQueue = {} :: { Types.ImaginaryBox }
local ImaginaryDestroyQueue = {} :: { Part }
--]]

local ToReset = {} :: { [string] : {{Part : Part, OriginalParent : Instance, model : Model}}}

-- pre-allocated part instance which is used to get the parts whenever `GetPartsInPart` is needed
local IntersectingPart = Instance.new("Part")

--local activeReset = false
--local lastOpTick = nil

local accum = 0



local function PartFromTemplate(template)

	local part = Instance.new("Part")
	part.Material = if typeof(template.Material) == "number" then Enum.Material:FromValue(template.Material) else template.Material
	part.Transparency = template.Transparency
	part.Reflectance = template.Reflectance or 0
	part.Color = template.Color
	--part.Color = Color3.fromHSV(math.random(), 1, 1)
	part.Anchored = true
	part.CollisionGroup = template.CollisionGroup
	part.MaterialVariant = template.MaterialVariant

	if typeof(template) == "Instance" then
		for _, tag in ipairs(template:GetTags()) do
			part:AddTag(tag)
		end
		for k, v in pairs(template:GetAttributes()) do
			part:SetAttribute(k, v)
		end
	else
		for _, tag in ipairs(template.Tags) do
			part:AddTag(tag)
		end
		for k, v in pairs(template.Attributes) do
			part:SetAttribute(k, v)
		end
	end

	return part
end


local function SerializedPartInstance(p, ignoreWorldState)
	local serial = {
		Color = p.Color,
		Material = p.Material.Value,
		Transparency = p.Transparency,
		Reflectance = p.Reflectance,
		CollisionGroup = p.CollisionGroup,
		MaterialVariant = p.MaterialVariant,

		Tags = p:GetTags(),
		Attributes = p:GetAttributes()
	}

	if not ignoreWorldState then
		serial.CFrame = p.CFrame
		serial.Size = p.Size
	end

	return serial
end


local function GridInfo(PartCFrame : CFrame, PartSize : Vector3, GridSize : number)
	local DIM = Vector3.one:Max(PartSize // GridSize)
	local NVX, NVY, NVZ = DIM.X, DIM.Y, DIM.Z

	local VoxelSize = PartSize / DIM
	local VSX, VSY, VSZ = VoxelSize.X, VoxelSize.Y, VoxelSize.Z

	local lsx, lsy, lsz = PartCFrame.XVector*VSX, PartCFrame.YVector*VSY, PartCFrame.ZVector*VSZ

	local ExtentOffset = 0.5*( lsx*(NVX - 1) + lsy*(NVY - 1) + lsz*(NVZ - 1) )

	return (PartCFrame - ExtentOffset):Orthonormalize(), -- Minimum cframe
		   (PartCFrame + ExtentOffset):Orthonormalize(), -- Maximum cframe
		   VoxelSize, -- voxel size
		   lsx, lsy, lsz, -- local axis vectors scaled by the size of the part,
		   NVX, NVY, NVZ -- the number of voxels along each axis
end


local EPSILON = 1e-3

local function InitGreedyState(part, GridSize, groupMin, State, DIMYDIMZ, DIMZ)

	local minCFrame, _, S, _, _, _, NVX, NVY, NVZ = GridInfo(part.CFrame:Orthonormalize(), part.Size, GridSize)

	if not minCFrame.Rotation:FuzzyEq(groupMin.Rotation, EPSILON) then
		return 0
	end

	local off = minCFrame.Position - groupMin.Position

	local ODX, ODY, ODZ = off:Dot(groupMin.XVector) / S.X,
					      off:Dot(groupMin.YVector) / S.Y,
					      off:Dot(groupMin.ZVector) / S.Z
	local DX, DY, DZ = math.floor(ODX + 0.5),
					   math.floor(ODY + 0.5),
					   math.floor(ODZ + 0.5)

	if math.abs(DX - ODX) > EPSILON or math.abs(DY - ODY) > EPSILON or math.abs(DZ - ODZ) > EPSILON then
		return 0
	end

	DX -= 1
	DY -= 1

	local traversed = 0
	-- Initialize the 3d state volume
	for X = 1, NVX do
		local dixz = (X + DX)*DIMYDIMZ + DZ
		for Y = 1, NVY do
			local di = dixz + (Y + DY)*DIMZ
			for Z = 1, NVZ do
				if traversed == Settings.GMTraversalsPerFrame then
					coroutine.yield()
					traversed = 0
				end

				State[di + Z] = true

				traversed += 1
			end
		end
	end

	DX += 1
	DY += 1

	return {1 + DX, 1 + DY, 1 + DZ, DX + NVX, DY + NVY, DZ + NVZ}, NVX * NVY * NVZ
end


local function GreedyMeshWorker(DirtyParent : Model, GridSize : number?)

	local Original = Shatterbox.GetOriginalPart(DirtyParent)

	-- The bounding area of Greedy Meshing, defined by the original part before it was ever destroyed
	local groupMin, _, VoxelSize, _, _, _, DIMX, DIMY, DIMZ = GridInfo(Original.CFrame, Original.Size, GridSize)
	local DIMYDIMZ = DIMY*DIMZ
	local VSX, VSY, VSZ = VoxelSize.X, VoxelSize.Y, VoxelSize.Z

	-- flat 3d state/visited array : index = (X - 1)*DIMYDIMZ + (Y - 1)*DIMZ + Z
	local State, Visited = {}, {}

	-- information about the original parts, used for smoothly displaying the output of greedy meshing
	local OriginalPartsInfo = {} :: {
		{Part : Part, PartGridInfo : {any}, Contributed : {number}}
	}

	-- the total number of voxels in the State array
	local count = 0

	for _, child in ipairs(DirtyParent:GetChildren()) do
		local gridInfo, n = InitGreedyState(child, GridSize, groupMin, State, DIMYDIMZ, DIMZ)
		if n > 0 then
			count += n

			table.insert(OriginalPartsInfo, {
				Part = child,
				PartGridInfo = gridInfo,

				Contributed = {}
			})
		end
	end

	local meshed = {}

	local traversed = 0

	local sx, sy, sz = 1, 1, 1
	while count > 0 do
		local X, Y, Z = sx, sy, sz
		local iyz = (Y - 1)*DIMZ + Z
		local si = (X - 1)*DIMYDIMZ + iyz
		-- find first unvisited and active state position
		while Visited[si] or not State[si] do
			if traversed == Settings.GMTraversalsPerFrame then
				coroutine.yield()
				traversed = 0
			end

			if X < DIMX then
				X += 1
			else
				X = 1
				if Y < DIMY then
					Y += 1
				else
					Y = 1
					if Z < DIMZ then
						Z += 1
					else
						Z = 1
					end
				end
				iyz = (Y - 1)*DIMZ + Z
			end

			traversed += 1
			si = (X - 1)*DIMYDIMZ + iyz
		end
		sx, sy, sz = X, Y, Z

		Visited[si] = true

		-- planar expansion along X axis
		while X < DIMX do
			local DX = X + 1

			if traversed == Settings.GMTraversalsPerFrame then
				coroutine.yield()
				traversed = 0
			end

			local index = (DX - 1)*DIMYDIMZ + (Y - 1)*DIMZ + Z
			if Visited[index] or not State[index] then break end

			Visited[index] = true
			traversed += 1

			X = DX
		end

		-- planar expansion along Y axis
		while Y < DIMY do
			local DY = Y + 1
			local iyz = (DY - 1)*DIMZ + Z
			local breakExpansion = false

			local indices = {}

			for ix = sx, X do
				if traversed == Settings.GMTraversalsPerFrame then
					coroutine.yield()
					traversed = 0
				end

				local index = (ix - 1)*DIMYDIMZ + iyz
				if Visited[index] or not State[index] then
					breakExpansion = true
					break
				end

				indices[index] = true
				traversed += 1
			end

			if breakExpansion then break end

			for index in pairs(indices) do
				Visited[index] = true
			end

			Y = DY
		end

		-- planar expansion along Z axis
		while Z < DIMZ do
			local DZ = Z + 1
			local breakExpansion = false

			local indices = {}

			for ix = sx, X do
				local ixz = (ix - 1)*DIMYDIMZ + DZ
				for iy = sy, Y do
					if traversed == Settings.GMTraversalsPerFrame then
						coroutine.yield()
						traversed = 0
					end

					local index = ixz + (iy - 1)*DIMZ
					if Visited[index] or not State[index] then
						breakExpansion = true
						break
					end

					indices[index] = true
					traversed += 1
				end

				if breakExpansion then break end
			end

			if breakExpansion then break end

			for index in pairs(indices) do
				Visited[index] = true
			end

			Z = DZ
		end

		-- the number of voxels in the meshed span on every axis
		local NX, NY, NZ = X - sx + 1, Y - sy + 1, Z - sz + 1
		-- subtract the total number of voxels in the meshed span
		count -= NX * NY * NZ

		-- define a cuboid using the start and end positions.
		table.insert(meshed, {
			CFrame = ( groupMin + groupMin.XVector*VSX*((X + sx)*0.5 - 1) + groupMin.YVector*VSY*((Y + sy)*0.5 - 1) + groupMin.ZVector*VSZ*((Z + sz)*0.5 - 1) ):Orthonormalize(),
			Size = VoxelSize * Vector3.new(NX, NY, NZ),

			Contributed = {},

			MINX = sx,
			MINY = sy,
			MINZ = sz,

			MAXX = X,
			MAXY = Y,
			MAXZ = Z
		})
	end

	-- process voxel count contributions (for smooth display of greedy meshing)
	for meshedIndex, MI in ipairs(meshed) do
		local contributedToMeshed, MINX, MINY, MINZ, MAXX, MAXY, MAXZ = MI.Contributed, MI.MINX, MI.MINY, MI.MINZ, MI.MAXX, MI.MAXY, MI.MAXZ

		for i, partInfo in ipairs(OriginalPartsInfo) do
			local PMINX, PMINY, PMINZ, PMAXX, PMAXY, PMAXZ = unpack(partInfo.PartGridInfo)

			-- SAT test in voxel coordinate space??
			if math.max(PMINX, MINX) > math.min(PMAXX, MAXX) or math.max(PMINY, MINY) > math.min(PMAXY, MAXY) or math.max(PMINZ, MINZ) > math.min(PMAXZ, MAXZ) then continue end

			table.insert(contributedToMeshed, i)
			table.insert(partInfo.Contributed, meshedIndex)
		end
	end

	local InstancedMeshIDs, numInstanced, numMeshed = {}, 0, #meshed

	count = 0

	-- Expertly performing dual DFS for smooth display of meshing (visual groups are instantiated one by one)
	while numInstanced < numMeshed do
		if count >= Settings.GMPartCreationsPerFrame then
			coroutine.yield()
			count = 0
		end

		local startIndex
		for i in ipairs(meshed) do
			if InstancedMeshIDs[i] then continue end
			startIndex = i
			break
		end

		local visitedOriginals, visitedMeshed, pathStack = {}, { [startIndex] = true }, {startIndex}

		while #pathStack > 0 do
			local mi = table.remove(pathStack)
			local meshedInfo = meshed[mi]

			for _, io in ipairs(meshedInfo.Contributed) do
				if visitedOriginals[io] then continue end
				visitedOriginals[io] = true

				local partInfo = OriginalPartsInfo[io]

				for _, im in ipairs(partInfo.Contributed) do
					if visitedMeshed[im] then continue end
					visitedMeshed[im] = true

					table.insert(pathStack, im)
				end
			end
		end

		for meshedID in pairs(visitedMeshed) do
			InstancedMeshIDs[meshedID] = true
			numInstanced += 1

			local meshedInfo = meshed[meshedID]

			local newStatic = PartFromTemplate(Original)
			newStatic.CFrame = meshedInfo.CFrame
			newStatic.Size = meshedInfo.Size
			newStatic.Parent = DirtyParent

			count += 1
		end

		for originalID in pairs(visitedOriginals) do
			OriginalPartsInfo[originalID].Part:Destroy()
		end
	end
end


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
local function OverlapParamsOfTagged(tags : { string }) : OverlapParams
	local arr

	if #tags == 1 then
		arr = CollectionService:GetTagged(tags[1])
	else
		arr = {}
		for _, tag in ipairs(tags) do
			local taggedArray = CollectionService:GetTagged(tag)
			table.move(taggedArray, 1, #taggedArray, #arr + 1, arr)
		end
	end

	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = arr

	return overlapParams
end




--I wonder if anyone has done this before.
--
-- Voxelizes a part (or imaginary part) completely according to the GridSize supplied. Returns an array of imaginary box parts.
-- Very efficient, as opposed to the previous recursive logic. The returned table is created with proper allocation size using `table.create`.
local function ImaginaryVoxelize(part, GridSize)

	GridSize = GridSize or Settings.DefaultGridSize

	local O, _, S, lsx, lsy, lsz, NVX, NVY, NVZ = GridInfo(part.CFrame:Orthonormalize(), part.Size, GridSize)

	local imaginaryParts, index = table.create(NVX*NVY*NVZ), 0

	for X = 0, NVX - 1 do
		local dx = X*lsx
		for Y = 0, NVY - 1 do
			local dy = Y*lsy
			for Z = 0, NVZ - 1 do
				index += 1
				imaginaryParts[index] = {
					CFrame = O + dx + dy + Z*lsz,
					Size = S
				}
			end
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
		found = i;
		break
	end
	if found then table.remove(ShatterQueue, found) end

	for _, dirtied in ipairs(intersectedDirties) do
		local DirtyParent = dirtied.model
		if GreedyWorkers[DirtyParent] then
			GreedyWorkersTerminationFlags[DirtyParent] = true
			while GreedyWorkers[DirtyParent] do RunService.Heartbeat:Wait() end
		end
		local restored = dirtied.Part:Clone()
		restored.Parent = DirtyParent.Parent
		DirtyParent:Destroy()
	end

	--[[
	local processed = {}
	while #ImaginaryCreateQueue > 0 do
		local v = table.remove(ImaginaryCreateQueue)
		if v.DestructionID == ID then
			continue
		end
		table.insert(processed, v)
	end
	ImaginaryCreateQueue = processed
	--]]

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


local function FlagDirty(ID, GridSize : number, dirtyParent : Model)
	if not dirtyParent then return end

	GridSize = GridSize or dirtyParent:GetAttribute("GridSize") or Settings.DefaultGridSize

	if GreedyWorkers[dirtyParent] then
		GreedyWorkersTerminationFlags[dirtyParent] = true
	end

	for _, dirtied in pairs(FlaggedDirty) do
		local found
		for i, v in ipairs(dirtied) do
			if v.DirtyParent == dirtyParent then
				found = table.remove(dirtied, i)
				GridSize = math.min(GridSize, v.GridSize)
				break
			end
		end
		if found then break end
	end

	if FlaggedDirty[ID] then
		table.insert(FlaggedDirty[ID], {GridSize = GridSize, DirtyParent = dirtyParent})
	else
		FlaggedDirty[ID] = { {GridSize = GridSize, DirtyParent = dirtyParent} }
	end
end


local function MarkDirty(ID, GridSize : number, Part : Part)

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
			model = model,
			GridSize = GridSize
		})

		return true
	end

	if Settings.UseGreedyMeshing then
		FlagDirty(ID, GridSize, Part.Parent)
	end

	return false
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


local function GetDestructibleParts(ID, cuttingPart, GridSize, filterTagged, replicated)
	local partsInPart = {}

	local op =
		if filterTagged then
			OverlapParamsOfTagged(filterTagged)
		else
			defaultOverlapParams

	IntersectingPart.CFrame = cuttingPart.CFrame
	IntersectingPart.Size = cuttingPart.Size
	IntersectingPart.Shape = cuttingPart.Shape

	for _, part in ipairs( workspace:GetPartsInPart(IntersectingPart, op) ) do

		if replicated and not part:IsDescendantOf(clientMapFolder) then continue end

		if ShouldSkipInstance(part) then continue end

		-- adds this part to the smooth cleanup for this destruction, if it's not already destroyed by something else
		MarkDirty(ID, GridSize, part)

		table.insert(partsInPart, part)
	end

	return partsInPart
end

--[[
local function GetImaginaryDestructibleParts(cuttingPart, verts, normals) -- I am simply goated
	local iBa, iC = cuttingPart.Shape.Name == "Ball", cuttingPart.Shape.Name == "Cylinder"

	local processed = {}
	local destructibles = {}

	while #ImaginaryCreateQueue > 0 do
		local ivox = table.remove(ImaginaryCreateQueue)
		local intersected

		if iBa then
			intersected = VertexMath.BallIntersectsBlock(cuttingPart.CFrame, cuttingPart.Size, ivox.CFrame, ivox.Size)
		elseif iC then
			intersected = VertexMath.CylinderIntersectsBlock(cuttingPart.CFrame, cuttingPart.Size, verts, normals, ivox.CFrame, ivox.Size, BlockVerts(ivox.CFrame, ivox.Size), BlockNormals(ivox.CFrame))
		else
			intersected = PartContainsAVert(cuttingPart, verts) or VertexMath.SAT(verts, normals, BlockVerts(ivox.CFrame, ivox.Size), BlockNormals(ivox.CFrame))
		end

		table.insert(intersected and destructibles or processed, ivox)
	end

	ImaginaryCreateQueue = processed

	return destructibles
end
--]]


local function ImaginaryVoxels(params, frameLimit, toDestroy)
	local voxelCount = 0
	local voxels = setmetatable({}, { __len = function() return voxelCount end }) :: {Types.ImaginaryVoxel}

	toDestroy = toDestroy or GetDestructibleParts(params.ID, params.CuttingPart, params.GridSize, params.FilterTagged, params.replicated)

	if #toDestroy == 0 then return voxels end

	local partsInPart = table.create(#toDestroy)
	for i, part in ipairs(toDestroy) do
		part.CanQuery = false
		partsInPart[i] = {
			CFrame = part.CFrame,
			Size = part.Size,

			Original = Shatterbox.GetOriginalPart(part.Parent),
			DestructionID = params.ID,

			DirtyParent = part.Parent,
			GridSize = params.GridSize or part:GetAttribute("GridSize") or part.Parent:GetAttribute("GridSize") or Settings.DefaultGridSize
		}
	end

	local cuttingPart = params.CuttingPart
	local cpcf, cps, cpsh = cuttingPart.CFrame, cuttingPart.Size, cuttingPart.Shape.Name
	local iBl, iBa, iC = cpsh == "Block", cpsh == "Ball", cpsh == "Cylinder"

	local intersectingVerts, intersectingNormals
	if iBl or iC then
		intersectingVerts = BlockVerts(cpcf, cps)
		intersectingNormals = BlockNormals(cpcf)
	elseif not iBa then
		intersectingVerts = GetVerts[cpsh](cpcf, cps)
		intersectingNormals = GetNormals[cpsh](cpcf, cps)
	end

	--[[
	local imaginaryDestructibles = GetImaginaryDestructibleParts(cuttingPart, intersectingVerts, intersectingNormals)
	if #imaginaryDestructibles > 0 then
		table.move(imaginaryDestructibles, 1, #imaginaryDestructibles, #partsInPart + 1, partsInPart)
	end
	--]]

	local dividing = partsInPart :: {Types.ImaginaryBox}
	partsInPart = nil

	local creating = {}

	-- imaginary division step
	while #dividing > 0 do

		if frameLimit and frameDivs > Settings.MaxDivisionsPerFrame then
			table.move(dividing, 1, #dividing, #creating + 1, creating)
			break
		end

		local toDivide = table.remove(dividing)
		local verts = BlockVerts(toDivide.CFrame, toDivide.Size)

		local intersected = PartContainsAVert(cuttingPart, verts)

		if not intersected then
			if iBa then
				intersected = VertexMath.BallIntersectsBlock(cpcf, cps, toDivide.CFrame, toDivide.Size)
			elseif iC then
				intersected = VertexMath.CylinderIntersectsBlock(cpcf, cps, intersectingVerts, intersectingNormals, toDivide.CFrame, toDivide.Size, verts, BlockNormals(toDivide.CFrame))
			else
				intersected = VertexMath.SAT(intersectingVerts, intersectingNormals, verts, BlockNormals(toDivide.CFrame))
			end
		else
			table.remove(verts, intersected)
		end

		if intersected then
			local s, o, gridSize, dirtyParent, destructionID = toDivide.Size, toDivide.Original, toDivide.GridSize, toDivide.DirtyParent, toDivide.DestructionID

			if PartContainsAllVerts(cuttingPart, verts or BlockVerts(toDivide.CFrame, toDivide.Size)) then
				if params.SkipEncapsulatedVoxels then
					local voxelCountAxis = toDivide.Size // gridSize
					voxelCount += voxelCountAxis.X*voxelCountAxis.Y*voxelCountAxis.Z
				else
					local createdParts = ImaginaryVoxelize(toDivide, gridSize)
					voxelCount += #createdParts
					for _, created in ipairs(createdParts) do
						created.Original = o
						created.GridSize = gridSize
						created.DirtyParent = dirtyParent
						created.DestructionID = destructionID
					end
					table.move(createdParts, 1, #createdParts, #voxels + 1, voxels)
				end
				continue
			end

			toDivide.isEdge = true

			local sx,sy,sz = s.X, s.Y, s.Z
			if sx <= gridSize and sy <= gridSize and sz <= gridSize then
				voxelCount += 1
				table.insert(voxels, toDivide)
				continue
			end

			local minsize, maxsize = math.min(sx, sy, sz), math.max(sx, sy, sz)
			local Subdivide = SubdivideFunctions[(maxsize > 2 * minsize) and "KD" or "MOT"]

			if frameLimit then frameDivs += 1 end

			local createdParts = Subdivide(toDivide, gridSize)
			if createdParts then
				for _, created in ipairs(createdParts) do
					if PartContainsAllVerts(cuttingPart, BlockVerts(created.CFrame, created.Size)) then
						if params.SkipEncapsulatedVoxels then
							local voxelCountAxis = created.Size // gridSize
							voxelCount += voxelCountAxis.X*voxelCountAxis.Y*voxelCountAxis.Z
						else
							local newVoxels = ImaginaryVoxelize(toDivide, gridSize)
							voxelCount += #newVoxels
							for _, v in ipairs(newVoxels) do
								v.Original = o
								v.GridSize = gridSize
								v.DirtyParent = dirtyParent
								v.DestructionID = destructionID
							end
							table.move(newVoxels, 1, #newVoxels, #voxels + 1, voxels)
						end
					else
						created.Original = o
						created.GridSize = gridSize
						created.DirtyParent = dirtyParent
						created.DestructionID = destructionID
						table.insert(dividing, created)
					end
				end
			else
				voxelCount += 1
				table.insert(voxels, toDivide)
			end
		else
			table.insert(creating, toDivide)
		end
	end

	--[[
	if #creating > 0 then
		table.move(creating, 1, #creating, #ImaginaryCreateQueue + 1, ImaginaryCreateQueue)
	end

	if #toDestroy > 0 then
		--table.move(toDestroy, 1, #toDestroy, #ImaginaryDestroyQueue + 1, ImaginaryDestroyQueue)
	end
	--]]

	-- create new static parts
	--
	for _, ibox in ipairs(creating) do
		local newStatic = PartFromTemplate(ibox.Original)
		newStatic.CFrame = ibox.CFrame
		newStatic.Size = ibox.Size
		newStatic.Parent = ibox.DirtyParent
	end
	--]]

	-- destroy original parts
	for _, part in ipairs(toDestroy) do
		part:Destroy()
	end

	return voxels :: {Types.ImaginaryVoxel}
end


-- pops an element from the ShatterQueue, removing the completed operations that it might find before finding one to complete.
local function PopShatterQueue()
	local popped, shatterPart, partsInPart
	local v = table.remove(ShatterQueue)

	while v and not popped do

		shatterPart, partsInPart = v.CuttingPart, {}

		for _, part in ipairs( GetDestructibleParts(v.ID, shatterPart, v.GridSize, v.FilterTagged, v.replicated) ) do

			if part:HasTag("ShatterboxDebris") then
				HandleVoxelDestruction(v.OnVoxelDestruct, part, part.Parent, shatterPart, not Shatterbox.PartEncapsulatesBlockPart(shatterPart, part), unpack(v.DestructParameters))
				continue
			end

			table.insert(partsInPart, part)
		end

		if #partsInPart == 0 then
			if v.OnDestructCompleted then v.OnDestructCompleted() end
			v = table.remove(ShatterQueue)
		else
			popped = v
			table.insert(ShatterQueue, Settings.UsePriorityQueue and math.max(1, #ShatterQueue + 1 - Settings.PrioritizeRecentN) or 1, popped)
		end
	end

	return popped, partsInPart
end


-- processes one of the operations in the ShatterQueue, removing it if the operation is finished. It queues all divisions for this step of the operation.
-- returns true if an operation step was procesed.
local function ShatterWorker()

	local popped, partsInPart = PopShatterQueue()
	if not popped then return false end

	local OnVoxelDestruct, CuttingPart, DestructParameters = popped.OnVoxelDestruct, popped.CuttingPart, popped.DestructParameters

	local ivoxels = ImaginaryVoxels(popped, true, partsInPart)
	for _, ivoxel in ipairs(ivoxels) do
		local voxel = ivoxel.Original:Clone()
		voxel.CFrame = ivoxel.CFrame
		voxel.Size = ivoxel.Size
		HandleVoxelDestruction(OnVoxelDestruct, voxel, ivoxel.DirtyParent, CuttingPart, ivoxel.isEdge, unpack(DestructParameters))
	end

	return true
end


local function ValidateDestructionParams(intersectingPart : Part | Model | Types.Hitbox | Types.DestructionParams | Types.ImaginaryDestructionParams, FilterTagged : (string | {string})?, CleanupDelay : number?, OnVoxelDestruct : string?, GridSize : number?, SkipEncapsulatedVoxels : boolean?, OnDestructCompleted : (() -> ())?, ... : any)

	local CuttingPart = {} :: Types.Hitbox
	local params = {} :: Types.InternalDestructionParams | Types.InternalImaginaryParams
	local tbl = {} :: Types.DestructionParams | Types.ImaginaryDestructionParams

	if typeof(intersectingPart) == "table" then
		tbl = intersectingPart
		if tbl.CuttingPart then
			local cp = tbl.CuttingPart
			if typeof(cp) == "table" or (typeof(cp) == "Instance" and cp:IsA("Part")) then
				assert(cp.CFrame and cp.Size and cp.Shape, "You must provide a CFrame, Size, and Shape for the '{ CuttingPart : { CFrame : CFrame, Size : Vector3, Shape : Enum.PartType } }' syntax.")
				CuttingPart.CFrame = cp.CFrame
				CuttingPart.Size = cp.Size
				CuttingPart.Shape = cp.Shape
			end
		else
			assert(tbl.CFrame and tbl.Size and tbl.Shape, "You must provide a CFrame, Size, and Shape for the '{ CFrame : CFrame, Size : Vector3, Shape : Enum.PartType }' syntax.")
			CuttingPart.CFrame = tbl.CFrame
			CuttingPart.Size = tbl.Size
			CuttingPart.Shape = tbl.Shape
		end
	elseif intersectingPart:IsA("Part") then
		CuttingPart.CFrame = intersectingPart.CFrame
		CuttingPart.Size = intersectingPart.Size
		CuttingPart.Shape = intersectingPart.Shape
	end

	local filterTagged = tbl.FilterTagged or FilterTagged
	if filterTagged then
		if typeof(filterTagged) == "table" then
			for _, k in pairs(filterTagged) do
				assert(typeof(k) == "string", "FilterTagged must be an array of strings only")
			end
		else
			assert(typeof(filterTagged) == "string", "FilterTagged must be a string or an array of strings")
			filterTagged = { filterTagged }
		end
	end

			   params.CuttingPart = CuttingPart
			  params.FilterTagged = filterTagged
			  params.CleanupDelay = tbl.CleanupDelay		   or CleanupDelay   		 or Settings.DefaultSmoothCleanupDelay
		   params.OnVoxelDestruct = tbl.OnVoxelDestruct 	   or OnVoxelDestruct
				  params.GridSize = tbl.GridSize 			   or GridSize
	params.SkipEncapsulatedVoxels = tbl.SkipEncapsulatedVoxels or SkipEncapsulatedVoxels
	   params.OnDestructCompleted = tbl.OnDestructCompleted    or OnDestructCompleted
		params.DestructParameters = tbl.DestructParameters     or { ... }
		       params.finalOpTick = tbl.finalOpTick
		                params.ID = tbl.ID

	assert(typeof(params.CleanupDelay) == "number", "CleanupDelay must be a number.")
	assert(not params.OnVoxelDestruct or typeof(params.OnVoxelDestruct) == "string", "OnVoxelDestruct must be a string indicating the name of the OnVoxelDestruct callback.")
	assert(not params.GridSize or typeof(params.GridSize) == "number", "GridSize must be a number.")
	assert(not params.SkipEncapsulatedVoxels or typeof(params.SkipEncapsulatedVoxels) == "boolean", "SkipEncapsulatedVoxels must be a boolean.")
	assert(not params.OnDestructCompleted or typeof(params.OnDestructCompleted) == "function", "OnDestructCompleted must be a function.")
	assert(typeof(params.DestructParameters) == "table", "DestructParameters must be an ARRAY (ordered by increasing number index).")

	return params :: (Types.InternalImaginaryParams | Types.InternalDestructionParams)
end


local function HeartbeatWorker(deltaTime)
	--[[
	local frameCreated = 0

	while #ImaginaryCreateQueue > 0 and frameCreated < Settings.ImaginaryCreatedStaticPartsPerFrame do
		local ibox = table.remove(ImaginaryCreateQueue)
		local P = ibox.Original

		local newStatic = Instance.new("Part")
		newStatic.Material = P.Material
		newStatic.Transparency = P.Transparency
		newStatic.Reflectance = P.Reflectance
		newStatic.Color = P.Color
		newStatic.Anchored = P.Anchored
		newStatic.CFrame = ibox.CFrame
		newStatic.Size = ibox.Size
		newStatic.Parent = ibox.DirtyParent

		frameCreated += 1
	end

	--if #ImaginaryCreateQueue == 0 then
		local frameDestroyed = 0
		while #ImaginaryDestroyQueue > 0 and frameDestroyed < Settings.ImaginaryDestroyedStaticsPartsPerFrame do
			local v = table.remove(ImaginaryDestroyQueue)
			v:Destroy()

			frameDestroyed += 1
		end
	--end
	--]]

	--
	if Settings.UseGreedyMeshing and ActiveGMWorkerCount < Settings.GMWorkerCount then

		local AvailableDirtyGroups = {}

		for DestructionID, dirties in pairs(FlaggedDirty) do
			local found = false
			for _, info in ipairs(ShatterQueue) do
				if info.ID == DestructionID then
					found = true
					break
				end
			end
			if found then continue end

			found = false
			for _, dirty in ipairs(dirties) do
				if GreedyWorkers[dirty.DirtyParent] then
					found = true
					break
				end
			end
			if found then continue end

			AvailableDirtyGroups[DestructionID] = dirties
		end

		local DestructionID, Dirties = next(AvailableDirtyGroups)

		while DestructionID and ActiveGMWorkerCount < Settings.GMWorkerCount do

			if #Dirties == 0 then
				FlaggedDirty[DestructionID] = nil
				DestructionID, Dirties = next(AvailableDirtyGroups, DestructionID)
				continue
			end

			local dirtyInfo = table.remove(Dirties)
			local DirtyParent = dirtyInfo.DirtyParent

			if #DirtyParent:GetChildren() == 0 then continue end

			local thr = coroutine.create(GreedyMeshWorker)

			GreedyWorkers[DirtyParent] = thr
			ActiveGMWorkerCount += 1

			coroutine.resume(thr, DirtyParent, dirtyInfo.GridSize)
		end
	end

	if Settings.UseGreedyMeshing then
		for DirtyParent, worker in pairs(GreedyWorkers) do
			local status = coroutine.status(worker)

			if status == "dead" or (status == "suspended" and GreedyWorkersTerminationFlags[DirtyParent]) then
				GreedyWorkersTerminationFlags[DirtyParent] = nil
				GreedyWorkers[DirtyParent] = nil
				ActiveGMWorkerCount -= 1

			elseif status == "suspended" then
				coroutine.resume(worker)
			end
		end
	end
	--]]


	frameDivs = 0

	while #ShatterQueue > 0 and frameDivs < Settings.MaxDivisionsPerFrame do
		ShatterWorker()
	end


	if isClient then return end

	local PQL = #CreatePuppetQueue
	if PQL > 0 then
		local toReplicate = {}
		for _ = 1, math.min(PQL, Settings.PuppetReplicationFrameLimit) do
			local info = table.remove(CreatePuppetQueue)
			local serial = SerializedPartInstance(info[2])
			serial.GUID = info[1]
			table.insert(toReplicate, serial)
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





local function SerializedCuttingPart(p)
	return {
		CFrame = p.CFrame,
		Size = p.Size,
		Shape = p.Shape.Value
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
		local Part = PartFromTemplate(serialPart)
		Part.Size = serialPart.Size
		Part.CFrame = serialPart.CFrame
		Part.Parent = clientMapFolder

		if ID then MarkDirty(ID, serialPart.GridSize, Part) end
	end
end


local function ReplicateDestructionToClients(destructionParams : Types.DestructionParams, event)
	destructionParams = table.clone(destructionParams)
	destructionParams.CuttingPart = SerializedCuttingPart(destructionParams.CuttingPart)

	event.FireAll(destructionParams, GetMapParts(destructionParams.ID))
end


local function ReplicateDestructionFromServer(params, mapParts)
	params.CuttingPart.Shape = Enum.PartType:FromValue(params.CuttingPart.Shape)

	local dParams = ValidateDestructionParams(params)

 	CreateReplicatedMapParts(dParams.ID, mapParts)

	dParams.replicated = true

	table.insert(ShatterQueue, dParams)
end

local function ReplicateImaginaryFromServer(params, mapParts)
	params.CuttingPart.Shape = Enum.PartType:FromValue(params.CuttingPart.Shape)
	params.SkipEncapsulatedVoxels = true

	local dParams = ValidateDestructionParams(params)

	CreateReplicatedMapParts(dParams.ID, mapParts)

	dParams.replicated = true

	RunService.Heartbeat:Wait()

	ImaginaryVoxels(dParams)
end



local function CreatePuppets(puppets)
	for _, puppet in ipairs(puppets) do
		local Part = PartFromTemplate(puppet)
		Part:AddTag(IndestructibleTag)
		Part.Size = puppet.Size
		Part.CFrame = puppet.CFrame
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
			local serialDirtied = SerializedPartInstance(p, true)
			serialDirtied.OriginalPart = { CFrame = p.CFrame, Size = p.Size }
			serialDirtied.Children = serialChildren
			serialDirtied.GridSize = dirty.GridSize

			table.insert(serialDirties, serialDirtied)
		end
		table.insert(replicatedDirties, {
			ID = ID,
			Dirties = serialDirties
		})
	end

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

		local ID = serialOpDirty.ID

		for _, serialDirtied in ipairs(serialOpDirty.Dirties) do

			local replicatedOriginal = PartFromTemplate(serialDirtied)
			replicatedOriginal.CFrame = serialDirtied.OriginalPart.CFrame
			replicatedOriginal.Size = serialDirtied.OriginalPart.Size

			local model = Instance.new("Model")
			model:AddTag("ShatterboxInstance")
			model:SetAttribute("GridSize", serialDirtied.Attributes.GridSize)
			for _, tag in ipairs(serialDirtied.Tags) do
				model:AddTag(tag)
			end

			for _, serialChild in ipairs(serialDirtied.Children) do
				local Part = PartFromTemplate(serialDirtied)
				Part.Size = serialChild.Size
				Part.CFrame = serialChild.CFrame
				Part.Parent = model
			end

			if Settings.UseGreedyMeshing then
				FlagDirty(ID, serialDirtied.GridSize, model)
			end

			model.Parent = clientMapFolder
			table.insert(dirtied, { model = model, Part = replicatedOriginal })
		end

		opDirties[ID] = dirtied
	end

	CreateReplicatedMapParts(nil, mapParts)
end


local function ModelQueueBehavior(funcToUse, intersectingPart, FilterTagged, CleanupDelay, OnVoxelDestruct, GridSize, SkipEncapsulatedVoxels, OnDestructCompleted, ...)
	local cuttingPart = if typeof(intersectingPart) == "table" then intersectingPart.CuttingPart else intersectingPart
	local ret = {}
	if cuttingPart and typeof(cuttingPart) == "Instance" and cuttingPart:IsA("Model") then
		for _, desc in ipairs(cuttingPart:GetDescendants()) do
			if not desc:IsA("Part") then continue end
			local r = funcToUse(desc, FilterTagged, CleanupDelay, OnVoxelDestruct, GridSize, SkipEncapsulatedVoxels, OnDestructCompleted, ...)
			if typeof(r) == "table" then
				table.move(r, 1, #r, #ret + 1, ret)
			end
		end
		return true, ret
	end
	return false, ret
end





Shatterbox.Settings = Settings


function Shatterbox.Puppeteer(voxel : Part)
	assert(isServer, "This function can only be called from the server")

	voxel:AddTag(IndestructibleTag)
	voxel.Parent = workspace.CurrentCamera
	if not voxel.Anchored then voxel:SetNetworkOwner(nil) end

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

	if ModelQueueBehavior(Shatterbox.Destroy, intersectingPart, FilterTagged, CleanupDelay, OnVoxelDestruct, GridSize, SkipEncapsulatedVoxels, OnDestructCompleted, ...) then
		return
	end

	local params = ValidateDestructionParams(intersectingPart, FilterTagged, CleanupDelay, OnVoxelDestruct, GridSize, SkipEncapsulatedVoxels, OnDestructCompleted, ...)

	task.defer(function()

		if params.CleanupDelay < 0 then return end

		params.ID = params.ID or HttpService:GenerateGUID(false)

		if #GetDestructibleParts(params.ID, params.CuttingPart, params.GridSize, params.FilterTagged) == 0 then
			return
		end

		-- starts the smooth cleanup counter
		if params.CleanupDelay > 0 and Settings.UseSmoothCleanup then task.delay(params.CleanupDelay, UndoDirtyOp, params.ID) end

		if USE_CLIENT_SERVER and isServer then
			ReplicateDestructionToClients(params, ServerEvents.ReplicateDestruction)
		end

		table.insert(ShatterQueue, params)
	end)
end


--*Yields until the NEXT Heartbeat to perform instant destruction.* <br>
--
--Performs voxel destruction around 'intersectingPart', skipping as many intermediate parts as possible. <br>
--
-- Returns an array of imaginary voxels for you to optionally create as debris.
function Shatterbox.ImaginaryVoxels(intersectingPart : Part | Model | Types.ImaginaryDestructionParams, FilterTagged : (string | {string})?, CleanupDelay : number?, GridSize : number?, SkipEncapsulatedVoxels : boolean?) : {Types.ImaginaryVoxel}

	local did, voxels = ModelQueueBehavior(Shatterbox.ImaginaryVoxels, intersectingPart, FilterTagged, CleanupDelay, nil, GridSize, SkipEncapsulatedVoxels, nil)
	if did then
		return voxels
	end

	local params = ValidateDestructionParams(intersectingPart, FilterTagged, CleanupDelay, nil, GridSize, SkipEncapsulatedVoxels)

	if params.CleanupDelay < 0 then return {} end

	voxels = voxels :: {Types.ImaginaryVoxel}

	params.ID = params.ID or HttpService:GenerateGUID(false)

	if #GetDestructibleParts(params.ID, params.CuttingPart, params.GridSize, params.FilterTagged) == 0 then
		return voxels
	end

	if USE_CLIENT_SERVER and isServer then
		ReplicateDestructionToClients(params, ServerEvents.ReplicateImaginary)
	end

	RunService.Heartbeat:Wait()

	-- starts the smooth cleanup counter
	if params.CleanupDelay > 0 and Settings.UseSmoothCleanup then task.delay(params.CleanupDelay, UndoDirtyOp, params.ID) end

	return ImaginaryVoxels(params)
end


-- resets all modified parts to where they originally were (turning the map back to normal)
function Shatterbox.Reset()
	ShatterQueue = {}

	for dirtyParent in pairs(GreedyWorkers) do
		GreedyWorkersTerminationFlags[dirtyParent] = true
	end
	while ActiveGMWorkerCount > 0 do RunService.Heartbeat:Wait() end

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
		ServerEvents.ClientInitComplete.On(ReplicateMapToNewPlayer)
	end
elseif isClient then
	if USE_CLIENT_SERVER then
		ClientEvents.SignalUndo.On(function(ID : string) UndoDirtyOp(ID, true) end)
		ClientEvents.SignalClearQueue.On(Shatterbox.ClearQueue)
		ClientEvents.SignalReset.On(Shatterbox.Reset)

		ClientEvents.ReplicateMap.On(ReplicateMapFromServer)
		ClientEvents.ReplicateDestruction.On(ReplicateDestructionFromServer)
		ClientEvents.ReplicateImaginary.On(ReplicateImaginaryFromServer)

		ClientEvents.ClientInitComplete.Fire()
	end
	ClientEvents.CreatePuppets.On(CreatePuppets)
	ClientEvents.ReplicatePuppetStates.On(ReplicatePuppetStates)
	ClientEvents.DestroyPuppet.On(DestroyPuppet)
end



RunService.Heartbeat:Connect(HeartbeatWorker)

return Shatterbox
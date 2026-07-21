--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)

local RunService = game:GetService("RunService")

local isClient = RunService:IsClient()

local components = script.Parent
local core = components.Parent
local src = core.Parent
local lib = core:WaitForChild("lib")

local Settings = require(src:WaitForChild("Settings"))
local Types = require(src:WaitForChild("Types"))

local SubdivideFunctions = require(lib:WaitForChild("SubdivideFunctions"))
local VertexMath = require(lib:WaitForChild("VertexMath"))
local GetVerts, GetNormals = VertexMath.GetVerts, VertexMath.GetNormals

local DeferredInstantiationLogic = require(components:WaitForChild("DeferredInstantiationLogic"))
local DirtyGroupLogic = require(components:WaitForChild("DirtyGroupLogic"))

local State = require(components.Parent:WaitForChild("State"))


local EPSILON_VECTOR = Vector3.one * 1e-3
local axisNames = {"X", "Y", "Z"}


local function FindHumanoidAsAncestorChild(i : Instance)
	while i do
		local hum = i:FindFirstChildWhichIsA("Humanoid")
		if hum then return hum end
		i = i.Parent
	end
	return nil
end
-- Returns true if an instance should NOT be considered for voxel destruction
local function ShouldSkipInstance(i : Instance)
	-- skip anything that passed the SkipInstanceCheck
	if Settings.SkipInstanceCheck(i) then return true end
	-- skip anything that isnt a block part
	if isClient and (not i:IsA("Part") or i.Shape ~= Enum.PartType.Block) then return true end
	-- skip anything with the "Indestructible" tag
	if i:HasTag(Settings.INDESTRUCTIBLE_TAG) then return true end
	-- skip anything which has a Humanoid child, or if any of its ancestors have a Humanoid child.
	if FindHumanoidAsAncestorChild(i) then return true end

	return false
end


local ShatterQueueLogic = {}


-- What happens when a model is passed in as the `CuttingPart`
local function ModelQueueBehavior(funcToUse, params)
	local cuttingPart = params.CuttingPart or params
	local retA, retB = {}, {}
	if cuttingPart and typeof(cuttingPart) == "Instance" and cuttingPart:IsA("Model") then
		for _, desc in ipairs(cuttingPart:GetDescendants()) do
			if not desc:IsA("Part") then continue end
			params.CuttingPart = desc
			local rA, rB = funcToUse(desc, params)
			if rA then
				table.move(rA, 1, #rA, #retA + 1, retA)
			end
			if rB then
				table.move(rB, 1, #rB, #retB + 1, retB)
			end
		end
		return true, retA, retB
	end
	return false, retA, retB
end
ShatterQueueLogic.ModelQueueBehavior = ModelQueueBehavior



--[[ Does 2 things:

	* If `Part` does not have an associated dirty group, one is created for it.
	  * With client server enabled, this is where the hierarchy is managed (server side parts go into the camera, client side parts go into the client map folder)

	* Begins the smooth cleanup counter if CleanupDelay is supplied
]]
local function MarkDirty(Part : Part, destructionParams : Types.InternalImaginaryParams | Types.InternalDestructionParams)

	local CreatedDirtyGroups = {}

	if Part:HasTag(Settings.DEBRIS_TAG) then return CreatedDirtyGroups end

	local PartDirtyGroupID = Part:GetAttribute(Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME)

	local PartIsDivisible = Part:IsA("Part") and Part.Shape == Enum.PartType.Block
	local NonDivisibleInteraction = Settings.NonDivisibleInteraction

	local CleanupDelay = destructionParams.CleanupDelay
	--[[

	local FallingGroupID, CreatedFallingGroupID = Part:GetAttribute(FallingGroupIDAttribute), nil
	local fallingGroupContainer = FindFirstAncestorGroupWithTag(Part, FallingGroupTag)
	if not FallingGroupID and fallingGroupContainer then
		CreatedFallingGroupID = GetCondensedGUID()
		FallingGroupID = CreatedFallingGroupID

		local fallingGroupMembers = {}
		FallingGroupMembers[CreatedFallingGroupID] = fallingGroupMembers

		for _, part in ipairs(fallingGroupContainer:GetDescendants()) do
			if not part:IsA("BasePart") then continue end

			local DirtyGroupID = DirtyGroupLogic.PopulateDirtyGroup(part, nil)
			part:SetAttribute(FallingGroupIDAttribute, CreatedFallingGroupID)

			if part:IsA("Part") and part.Shape == Enum.PartType.Block then CreatedDirtyGroups[DirtyGroupID] = true end

			part.Parent = nil

			DirtyGroupLogic.InstantiatePart(DirtyGroupID, part.CFrame, part.Size)

			fallingGroupMembers[DirtyGroupID] = true
		end
	end

	if FallingGroupID then
		if Settings.UseSmoothCleanup and CleanupDelay > 0 then
			for DirtyGroupID in pairs(FallingGroupMembers[FallingGroupID]) do
				local prev = State.SmoothCleanupQueue[DirtyGroupID]
				State.SmoothCleanupQueue[DirtyGroupID] = prev and math.max(prev, CleanupDelay) or CleanupDelay
			end
		end

		return CreatedDirtyGroups, CreatedFallingGroupID
	end
	--]]


	if not PartDirtyGroupID and (PartIsDivisible or NonDivisibleInteraction ~= "NONE") then
		PartDirtyGroupID = DirtyGroupLogic.PopulateDirtyGroup(Part)

		if PartIsDivisible then
            CreatedDirtyGroups[PartDirtyGroupID] = true
        end
	end

	if PartDirtyGroupID then
		if not PartIsDivisible and NonDivisibleInteraction ~= "NONE" and not next(State.DirtyGroupMembers[PartDirtyGroupID]) then
			Part.Parent = nil
			if NonDivisibleInteraction == "FALL" then
				local cloned = DirtyGroupLogic.InstantiatePart(PartDirtyGroupID, Part.CFrame, Part.Size)
				cloned.Anchored = false
			end
		end
	end

	if Settings.UseSmoothCleanup and CleanupDelay > 0 then
		local prev = State.SmoothCleanupQueue[PartDirtyGroupID]
		State.SmoothCleanupQueue[PartDirtyGroupID] = prev and math.max(prev, CleanupDelay) or CleanupDelay
	end

	return CreatedDirtyGroups
end
ShatterQueueLogic.MarkDirty = MarkDirty



-- Returns all of the destructible parts that intersect the cuttingPart, calling MarkDirty on them
local function GetDestructibleParts(destructionParams : Types.InternalImaginaryParams | Types.InternalDestructionParams)
	local cuttingPart, replicated = destructionParams.CuttingPart, destructionParams.replicated

	local skipFloors, skipWalls = destructionParams.SkipFloors, destructionParams.SkipWalls
	local skipFloorsOrWalls = skipFloors or skipWalls

	local partsInPart, createdDirtyGroups, createdFallingGroups = {}, {}, {}

	local IntersectingPart = State.PreAllocated.IntersectingPart
	IntersectingPart.CFrame = cuttingPart.CFrame
	IntersectingPart.Size = cuttingPart.Size
	IntersectingPart.Shape = cuttingPart.Shape

	local AffectedDirtyGroups = {}

	--debug.profilebegin("GetPartsInPart nil Parent")
	local FoundPartsInPart = workspace:GetPartsInPart(IntersectingPart, destructionParams.FilterTagged and State.OverlapParamsOfTagged(destructionParams.FilterTagged))
	--debug.profileend()

	for _, part in ipairs( FoundPartsInPart ) do
		if State.ImaginaryDestroyQueue[part] then continue end

		if (replicated and not part:IsDescendantOf(State.MapContainer)) or ShouldSkipInstance(part) then continue end

		if part:HasTag(Settings.DEBRIS_TAG) then
			table.insert(partsInPart, part)
			continue
		end

		if skipFloorsOrWalls then
			State.PreAllocated.RaycastParams.FilterDescendantsInstances = { part }
			local res = workspace:Raycast(cuttingPart.CFrame.Position, part.Position - cuttingPart.CFrame.Position, State.PreAllocated.RaycastParams)
			if res then
				local isFloor = res.Normal:FuzzyEq(Vector3.yAxis, 0.001)
				if (skipFloors and isFloor) or (skipWalls and not isFloor) then continue end
			end
		end

		local dirtyGroups = MarkDirty(part, destructionParams)
		for DirtyGroupID in pairs(dirtyGroups) do
			createdDirtyGroups[DirtyGroupID] = true
		end

		if part:IsA("Part") and part.Shape == Enum.PartType.Block then
			table.insert(partsInPart, part)

			local DirtyGroupID = part:GetAttribute(Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME)

			AffectedDirtyGroups[DirtyGroupID] = true
		end
	end

	return partsInPart, createdDirtyGroups, createdFallingGroups, AffectedDirtyGroups
end
ShatterQueueLogic.GetDestructibleParts = GetDestructibleParts



--Performs voxel destruction according to the parameters, returning an array of un-created voxels as well as any existing debris as a second returned array.
local function ImaginaryVoxels(params, destructibleParts, dirtyGroups)
	local toDestroy, AffectedDirtyGroups
	if destructibleParts then
		toDestroy, AffectedDirtyGroups = destructibleParts, dirtyGroups
	else
		toDestroy, _, _, AffectedDirtyGroups = GetDestructibleParts(params)
	end

	local voxels, existingDebris = {} :: {Types.ImaginaryVoxel}, {} :: {BasePart}
	local voxelCount = 0

	--debug.profilebegin("FindDestructibleParts")
	local partsInPart = {}
	for _, part in ipairs(toDestroy) do
		if part:HasTag(Settings.DEBRIS_TAG) then
			table.insert(existingDebris, part)
			continue
		end

		State.ImaginaryDestroyQueue[part] = true

		table.insert(partsInPart, {
			CFrame = part.CFrame,
			Size = part.Size,

			DirtyGroupID = part:GetAttribute(Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME),
		})
	end

	local cuttingPart = params.CuttingPart
	local cpcf, cps, cpsh = cuttingPart.CFrame, cuttingPart.Size, cuttingPart.Shape.Name
	local iBl, iBa, iC = cpsh == "Block", cpsh == "Ball", cpsh == "Cylinder"

	local intersectingVerts, intersectingNormals
	if iBl or iC then
		intersectingVerts = GetVerts.Block(cpcf, cps)
		intersectingNormals = GetNormals.Block(cpcf)
	elseif not iBa then
		intersectingVerts = GetVerts[cpsh](cpcf, cps)
		intersectingNormals = GetNormals[cpsh](cpcf, cps)
	end

	if #State.ImaginaryCreateQueue > 0 then
		local ImaginaryDestructibleParts = DeferredInstantiationLogic.GetImaginaryDestructibleParts(params.CuttingPart, params.FilterTagged, intersectingVerts, intersectingNormals, AffectedDirtyGroups)
		if #ImaginaryDestructibleParts > 0 then
            table.move(ImaginaryDestructibleParts, 1, #ImaginaryDestructibleParts, #partsInPart + 1, partsInPart)
        end
	end

	--debug.profileend()

	if #partsInPart == 0 then return nil, existingDebris, AffectedDirtyGroups end

	local toUseVoxelSize : { [string] : Vector3 }
	-- Handle active VoxelSize switching for the affected dirty groups
	local desiredGridSize = params.GridSize
	if desiredGridSize then
		toUseVoxelSize = {}
		for DirtyGroupID in pairs(AffectedDirtyGroups) do
			local dirtyGroupData = State.DirtyGroupData[DirtyGroupID]
			local OriginalPartSize = dirtyGroupData.OriginalPart.Size
			local roundedGridLength = DirtyGroupLogic.RoundAxisNearestPowerOf2(Vector3.one:Max(OriginalPartSize // desiredGridSize))

			dirtyGroupData.MaxGridLength = roundedGridLength:Max(dirtyGroupData.MaxGridLength)

			toUseVoxelSize[DirtyGroupID] = OriginalPartSize/roundedGridLength
		end
	end

	local dividing = partsInPart :: {Types.ImaginaryBox}
	partsInPart = nil

	local creating = {} :: {Types.ImaginaryBox}

	while #dividing > 0 do
		local toDivide = dividing[#dividing]
		dividing[#dividing] = nil

		local verts = toDivide.Verts or GetVerts.Block(toDivide.CFrame, toDivide.Size)

		local s : Vector3, DirtyGroupID : string = toDivide.Size, toDivide.DirtyGroupID
		local dirtyGroupData = State.DirtyGroupData[DirtyGroupID]
		local VoxelSize = toUseVoxelSize and toUseVoxelSize[DirtyGroupID] or dirtyGroupData.VoxelSize

		local partGridLength = (s/VoxelSize + EPSILON_VECTOR):Floor():Max(Vector3.one)
		local toDivideVoxelContributions = partGridLength.X*partGridLength.Y*partGridLength.Z

		local encapsulated, intersected = VertexMath.PartContainsAllVerts(cuttingPart, verts)
		-- if toDivide is encapsulated within CuttingPart, there is no need to run expensive division algorithm (just voxelize directly or destroy it)
		if encapsulated then
			voxelCount += toDivideVoxelContributions
			if params.SkipEncapsulatedVoxels then continue end

			if toDivideVoxelContributions == 1 then
				table.insert(voxels, toDivide)
				continue
			end

			local newVoxels = SubdivideFunctions.ImaginaryVoxelize(toDivide, VoxelSize, partGridLength)
			for _, created in ipairs(newVoxels) do
                created.DirtyGroupID = DirtyGroupID
            end
			table.move(newVoxels, 1, #newVoxels, #voxels + 1, voxels)

			continue
		end

		if not intersected then
			if iBa then
				intersected = VertexMath.BallIntersectsBlock(cpcf, cps, toDivide.CFrame, toDivide.Size)
			elseif iC then
				intersected = VertexMath.CylinderIntersectsBlock(cpcf, cps, intersectingVerts, intersectingNormals, toDivide.CFrame, toDivide.Size, verts, GetNormals.Block(toDivide.CFrame))
			else
				intersected = VertexMath.SAT(intersectingVerts, intersectingNormals, verts, GetNormals.Block(toDivide.CFrame))
			end
		end

		if intersected then
			-- if toDivide is literally only a single voxel large, add it as a voxel
			if toDivideVoxelContributions == 1 then
				voxelCount += toDivideVoxelContributions
				toDivide.isEdge = true
				table.insert(voxels, toDivide)
				continue
			end

			local maxSize, secondMax = -1, -1
			for _, axis in ipairs(axisNames) do
				local gridLength = partGridLength[axis]
				if gridLength > maxSize then
					secondMax = maxSize
					maxSize = gridLength
				elseif gridLength > secondMax then
					secondMax = gridLength
				end
			end

			local OriginalPart = dirtyGroupData.OriginalPart

            local SubdivideFunc = (maxSize < 2*secondMax) and SubdivideFunctions.Octree or SubdivideFunctions.KD

			local createdParts = SubdivideFunc(toDivide, partGridLength, VoxelSize, OriginalPart.CFrame:PointToWorldSpace(-OriginalPart.Size*0.5), DirtyGroupID)
			table.move(createdParts, 1, #createdParts, #dividing + 1, dividing)
		else
			-- if the toDivide part is not intersecting the CuttingPart, it is a static part
			table.insert(creating, toDivide)
		end
	end


	if #creating > 0 then
        table.move(creating, 1, #creating, #State.ImaginaryCreateQueue + 1, State.ImaginaryCreateQueue)
    end

	return
        setmetatable(voxels, {
            __len = function() return voxelCount end
        }) :: {Types.ImaginaryVoxel},

        existingDebris :: {BasePart},

        AffectedDirtyGroups :: {[string] : boolean}
end
ShatterQueueLogic.ImaginaryVoxels = ImaginaryVoxels



local function InstantiateImaginaryVoxel(ImaginaryVoxel : Types.ImaginaryVoxel | BasePart, doNotGiveDebrisTag : boolean?) : Part
	if typeof(ImaginaryVoxel) ~= "table" then return ImaginaryVoxel end

	local DirtyGroupID = ImaginaryVoxel.DirtyGroupID

	local voxel = DirtyGroupLogic.InstantiatePart(DirtyGroupID, ImaginaryVoxel.CFrame, ImaginaryVoxel.Size, true)

	if not doNotGiveDebrisTag then
        voxel:AddTag(Settings.DEBRIS_TAG)
    end

	voxel.Destroying:Once(function()
		local members = State.DirtyGroupMembers[DirtyGroupID]
		if not members then return end
		members[voxel] = nil
	end)

	voxel.Parent = State.DirtyGroupData[DirtyGroupID].OriginalParent

	return voxel
end
ShatterQueueLogic.InstantiateImaginaryVoxel = InstantiateImaginaryVoxel



-- Uses the given callback from the OnVoxelDestruct registry to destroy the given voxel
local function HandleOnVoxelDestruct(callbackName : string?, voxel : Part, info : Types.DestroyedVoxelInfo?)
	if not info then
        info = {}
    end

	local s, e = pcall(State.OnVoxelDestructRegistry[callbackName], voxel, info)

	if not s then
        warn("Voxel destruction failed: " .. e)
    end

	if not (info.IsAlreadyDebris or typeof(voxel) == "table") then
        voxel:AddTag(Settings.DEBRIS_TAG)
    end
end
ShatterQueueLogic.HandleOnVoxelDestruct = HandleOnVoxelDestruct



local function HandleOnDestructCompleted(name : string, voxelCount : number, affectedIDs : {[string] : boolean}, destructionParameters : Types.DestructionParams)
	local callback = State.OnDestructCompletedRegistry[name]
	if callback then
		local s, res = pcall(callback, voxelCount, affectedIDs, destructionParameters)
		if not s then
			warn("OnDestructCompleted failed: ", res)
		else
			return res
		end
	end
end
ShatterQueueLogic.HandleOnDestructCompleted = HandleOnDestructCompleted



function ShatterQueueLogic.Heartbeat()
	if #State.ShatterQueue == 0 then return end
	repeat
		local popped = table.remove(State.ShatterQueue) :: Types.DestructionParams
		local OnVoxelDestruct, OnDestructCompleted = popped.OnVoxelDestruct, popped.OnDestructCompleted
		local ManualVoxelInstantiation = popped.ManualVoxelInstantiation
		local CuttingPart, UserData = popped.CuttingPart, popped.UserData

		local ivoxels, existingDebris, affectedIDs = ImaginaryVoxels(popped)

		if ivoxels then
			if State.OnVoxelDestructRegistry[OnVoxelDestruct] then
				for _, ivoxel in ipairs(ivoxels) do
					local voxel = ManualVoxelInstantiation and ivoxel or InstantiateImaginaryVoxel(ivoxel, true)
					HandleOnVoxelDestruct(OnVoxelDestruct, voxel, {
						DirtyGroupID = ivoxel.DirtyGroupID,
						CuttingPart = CuttingPart,
						IsEdge = ivoxel.isEdge,
						IsAlreadyDebris = false,
						UserData = UserData
					})
				end
			end
		end

		if #existingDebris > 0 then
			if State.OnVoxelDestructRegistry[OnVoxelDestruct] then
				for _, debris in ipairs(existingDebris) do
					HandleOnVoxelDestruct(OnVoxelDestruct, debris, {
						DirtyGroupID = debris:GetAttribute(Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME),
						CuttingPart = CuttingPart,
						IsEdge = not VertexMath.PartEncapsulatesBlockPart(CuttingPart, debris.CFrame, debris.Size),
						IsAlreadyDebris = true,
						UserData = UserData
					})
				end
			else
				for _, debris in ipairs(existingDebris) do
                    DirtyGroupLogic.DestroyPart(debris)
                end
			end
		end

		if OnDestructCompleted then
			if typeof(OnDestructCompleted) == "string" then
				HandleOnDestructCompleted(OnDestructCompleted, ivoxels and #ivoxels or 0, affectedIDs, popped)
			else
				local s, res = pcall(OnDestructCompleted, ivoxels and #ivoxels or 0, affectedIDs, popped)
				if not s then
					warn("OnDestructCompleted failed: ", res)
				end
			end
		end

	until #State.ShatterQueue == 0
end



return ShatterQueueLogic
--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)
--#selene: allow(unused_variable)

local components = script.Parent
local core = components.Parent
local src = core.Parent
local lib = core:WaitForChild("lib")

local Settings = require(src:WaitForChild("Settings"))

local DirtyGroupLogic = require(components:WaitForChild("DirtyGroupLogic"))
local InstantiatePart = DirtyGroupLogic.InstantiatePart
local DestroyPart = DirtyGroupLogic.DestroyPart

local GreedyMeshLogic = require(components:WaitForChild("GreedyMeshLogic"))
local GreedyMeshBehavior = GreedyMeshLogic.GreedyMesh

local VertexMath = require(lib:WaitForChild("VertexMath"))
local PartContainsAVert = VertexMath.PartContainsAVert
local GetVerts = VertexMath.GetVerts
local BlockVerts = GetVerts.Block
local GetNormals = VertexMath.GetNormals
local BlockNormals = GetNormals.Block

local State = require(components.Parent:WaitForChild("State"))

local CachedParts = State.CachedParts

local DirtyGroupMembers = State.DirtyGroupMembers

local ImaginaryCreateQueue = State.ImaginaryCreateQueue
local ImaginaryDestroyQueue = State.ImaginaryDestroyQueue
local GreedyMeshedImaginaryParts = State.GreedyMeshedImaginaryParts


local DeferredInstantiationLogic = {}


-- Returns all of the imaginary destructible parts that intersect the cuttingPart, removing them from the ImaginaryCreateQueue when that happens.
local function GetImaginaryDestructibleParts(cuttingPart, filterTagged, verts, normals, affectedIDs)
	local iBa, iC = cuttingPart.Shape.Name == "Ball", cuttingPart.Shape.Name == "Cylinder"

	local processed = {}
	local destructibles = {}

	while #ImaginaryCreateQueue > 0 do
		local ivox = table.remove(ImaginaryCreateQueue)
		--[[
		if filterTagged then
			local OriginalPart = Shatterbox.GetOriginalPart(ivox.DirtyGroupID)
			local shouldSkip = true
			for _, tag in ipairs(filterTagged) do
				if OriginalPart:HasTag(tag) then
					shouldSkip = false
					break
				end
			end
			if shouldSkip then continue end
		end
		--]]

		local voxVerts = BlockVerts(ivox.CFrame, ivox.Size)

		local intersected = PartContainsAVert(cuttingPart, voxVerts)
		if not intersected then
			if iBa then
				intersected = VertexMath.BallIntersectsBlock(cuttingPart.CFrame, cuttingPart.Size, ivox.CFrame, ivox.Size)
			elseif iC then
				intersected = VertexMath.CylinderIntersectsBlock(cuttingPart.CFrame, cuttingPart.Size, verts, normals, ivox.CFrame, ivox.Size, BlockVerts(ivox.CFrame, ivox.Size), BlockNormals(ivox.CFrame))
			else
				intersected = VertexMath.SAT(verts, normals, voxVerts, BlockNormals(ivox.CFrame))
			end
		end

		if intersected then
			affectedIDs[ivox.DirtyGroupID] = true
			table.insert(destructibles, ivox)
			continue
		end
		table.insert(processed, ivox)
	end

	ImaginaryCreateQueue = table.move(processed, 1, #processed, #ImaginaryCreateQueue + 1, ImaginaryCreateQueue)
	return destructibles
end
DeferredInstantiationLogic.GetImaginaryDestructibleParts = GetImaginaryDestructibleParts



function DeferredInstantiationLogic.DeferredInstantiationHeartbeatBehavior()
	if #ImaginaryCreateQueue > 0 then
		if Settings.UseGreedyMeshing then
			local DirtyGroupImaginaryParts = {}

			for _, toCreate in ipairs(ImaginaryCreateQueue) do
				local DirtyGroupID = toCreate.DirtyGroupID
				local ImaginaryParts = DirtyGroupImaginaryParts[DirtyGroupID]
				if not ImaginaryParts then
					ImaginaryParts = {}
					DirtyGroupImaginaryParts[DirtyGroupID] = ImaginaryParts
				end

				table.insert(ImaginaryParts, toCreate)
			end

			for DirtyGroupID, ImaginaryParts in pairs(DirtyGroupImaginaryParts) do
				local countMembers = #ImaginaryParts
				for _ in pairs(DirtyGroupMembers[DirtyGroupID]) do
					countMembers += 1
					if countMembers > 1 then break end
				end
				if countMembers <= 1 then
					table.move(ImaginaryParts, 1, #ImaginaryParts, #GreedyMeshedImaginaryParts + 1, GreedyMeshedImaginaryParts)
					continue
				end
				GreedyMeshBehavior(DirtyGroupID, ImaginaryParts)
			end

			for _, toCreate in ipairs(GreedyMeshedImaginaryParts) do
				InstantiatePart(toCreate.DirtyGroupID, toCreate.CFrame, toCreate.Size)
			end

			table.clear(GreedyMeshedImaginaryParts)
		else
			for _, toCreate in ipairs(ImaginaryCreateQueue) do
				InstantiatePart(toCreate.DirtyGroupID, toCreate.CFrame, toCreate.Size)
			end
		end

		table.clear(ImaginaryCreateQueue)
	end

	if next(ImaginaryDestroyQueue) then
		for toDestroy in pairs(ImaginaryDestroyQueue) do
			DestroyPart(toDestroy)
		end
		table.clear(ImaginaryDestroyQueue)
	end

	if State.ScheduledUpdate then
		State.ScheduledUpdate = false
		CachedParts:Update()
	end
end




return DeferredInstantiationLogic
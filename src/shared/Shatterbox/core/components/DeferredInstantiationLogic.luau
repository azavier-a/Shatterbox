--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)
--#selene: allow(unused_variable)

local components = script.Parent
local core = components.Parent
local src = core.Parent
local lib = core:WaitForChild("lib")

local Settings = require(src:WaitForChild("Settings"))

local VertexMath = require(lib:WaitForChild("VertexMath"))
local GetVerts, GetNormals = VertexMath.GetVerts, VertexMath.GetNormals

local DirtyGroupLogic = require(components:WaitForChild("DirtyGroupLogic"))
local GreedyMeshLogic = require(components:WaitForChild("GreedyMeshLogic"))

local State = require(components.Parent:WaitForChild("State"))


local DeferredInstantiationLogic = {}


-- Returns all of the imaginary destructible parts that intersect the cuttingPart, removing them from the State.ImaginaryCreateQueue when that happens.
local function GetImaginaryDestructibleParts(cuttingPart, filterTagged, verts, normals, affectedIDs)
	local iBa, iC = cuttingPart.Shape.Name == "Ball", cuttingPart.Shape.Name == "Cylinder"

	local processed = {}
	local destructibles = {}

	while #State.ImaginaryCreateQueue > 0 do
		local ivox = table.remove(State.ImaginaryCreateQueue)
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

		local voxVerts = GetVerts.Block(ivox.CFrame, ivox.Size)

		local intersected = VertexMath.PartContainsAVert(cuttingPart, voxVerts)
		if not intersected then
			if iBa then
				intersected = VertexMath.BallIntersectsBlock(cuttingPart.CFrame, cuttingPart.Size, ivox.CFrame, ivox.Size)
			elseif iC then
				intersected = VertexMath.CylinderIntersectsBlock(cuttingPart.CFrame, cuttingPart.Size, verts, normals, ivox.CFrame, ivox.Size, GetVerts.Block(ivox.CFrame, ivox.Size), GetNormals.Block(ivox.CFrame))
			else
				intersected = VertexMath.SAT(verts, normals, voxVerts, GetNormals.Block(ivox.CFrame))
			end
		end

		if intersected then
			affectedIDs[ivox.DirtyGroupID] = true
			table.insert(destructibles, ivox)
			continue
		end
		table.insert(processed, ivox)
	end

	State.ImaginaryCreateQueue = table.move(processed, 1, #processed, #State.ImaginaryCreateQueue + 1, State.ImaginaryCreateQueue)
	return destructibles
end
DeferredInstantiationLogic.GetImaginaryDestructibleParts = GetImaginaryDestructibleParts



function DeferredInstantiationLogic.Heartbeat()
	if #State.ImaginaryCreateQueue > 0 then
		if Settings.UseGreedyMeshing then
			local DirtyGroupImaginaryParts = {}

			for _, toCreate in ipairs(State.ImaginaryCreateQueue) do
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
				for _ in pairs(State.DirtyGroupMembers[DirtyGroupID]) do
					countMembers += 1
					if countMembers > 1 then break end
				end
				if countMembers <= 1 then
					table.move(ImaginaryParts, 1, #ImaginaryParts, #State.GreedyMeshedImaginaryParts + 1, State.GreedyMeshedImaginaryParts)
					continue
				end
				GreedyMeshLogic.GreedyMeshDirtyGroup(DirtyGroupID, ImaginaryParts)
			end

			for _, toCreate in ipairs(State.GreedyMeshedImaginaryParts) do
				DirtyGroupLogic.InstantiatePart(toCreate.DirtyGroupID, toCreate.CFrame, toCreate.Size, toCreate.FallingGroupSectionID)
			end

			table.clear(State.GreedyMeshedImaginaryParts)
		else
			for _, toCreate in ipairs(State.ImaginaryCreateQueue) do
				DirtyGroupLogic.InstantiatePart(toCreate.DirtyGroupID, toCreate.CFrame, toCreate.Size, toCreate.FallingGroupSectionID)
			end
		end

		table.clear(State.ImaginaryCreateQueue)
	end

	if next(State.ImaginaryDestroyQueue) then
		for toDestroy in pairs(State.ImaginaryDestroyQueue) do
			DirtyGroupLogic.DestroyPart(toDestroy)
		end
		table.clear(State.ImaginaryDestroyQueue)
	end

	if State.ScheduledUpdate then
		State.ScheduledUpdate = false
		State.CachedParts:Update()
	end
end




return DeferredInstantiationLogic
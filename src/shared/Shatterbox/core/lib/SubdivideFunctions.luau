--!native
--!optimize 2

--#selene: allow(unused_variable)

local Types = require(script.Parent.Parent.Parent:WaitForChild("Types"))

local EPSILON = 1e-3
local splitInHalfVectors = { X = Vector3.new(0.5,1,1), Y = Vector3.new(1,0.5,1), Z = Vector3.new(1,1,0.5) }
local axisNameArray = { "X", "Y", "Z" }


local SubdivideFunctions = {}


--[[
    Returns all of the relevant information to construct a grid of voxels using the specified parameters
]]
local function ExtentInfo(PartCFrame : CFrame, VoxelSize : Vector3, GridLength : Vector3)
	local lsx, lsy, lsz = PartCFrame.XVector*VoxelSize.X, PartCFrame.YVector*VoxelSize.Y, PartCFrame.ZVector*VoxelSize.Z

	local ExtentOffset = 0.5*( lsx*(GridLength.X - 1) + lsy*(GridLength.Y - 1) + lsz*(GridLength.Z - 1) )

	return (PartCFrame - ExtentOffset)--[[:Orthonormalize()]], -- minimum voxel CFrame
		   (PartCFrame + ExtentOffset)--[[:Orthonormalize()]], -- maximum voxel CFrame
		   lsx, lsy, lsz -- local axis vectors scaled by the size of the voxel
end
SubdivideFunctions.ExtentInfo = ExtentInfo


--[[
	Does not mutate the supplied Part reference.

    Voxelizes a part (or imaginary part) completely according to the VoxelSize and GridLength supplied. Returns an array of imaginary box parts.
]]
function SubdivideFunctions.ImaginaryVoxelize(Part : Types.WorldInfo, VoxelSize : Vector3, GridLength : Vector3) : {Types.WorldInfo}
	local lenX, lenY, lenZ = GridLength.X, GridLength.Y, GridLength.Z

	local O, _, lsx, lsy, lsz = ExtentInfo(Part.CFrame, VoxelSize, GridLength)

	local imaginaryParts, index = table.create(lenX*lenY*lenZ), 0

	for X = 0, lenX - 1 do
		local xPos = O + X*lsx
		for Y = 0, lenY - 1 do
			local yPos = xPos + Y*lsy
			for Z = 0, lenZ - 1 do
				index += 1
				imaginaryParts[index] = {
					CFrame = (yPos + Z*lsz)--[[:Orthonormalize()--]],
					Size = VoxelSize
				}
			end
		end
	end

	return imaginaryParts
end



--[[ Modified Octree Subdivide

    Does not mutate the supplied Part reference, which is meant to be an object with the structure {Size : Vector3, CFrame : CFrame}

    Returns an array with the structure { {Size : Vector3, CFrame : CFrame} }

    Calculates the division of a part into 2, 4, or 8 pieces along its longest axis in voxel coordinates.

    Maintains grid structure according to the VoxelSize and GroupMinimumCorner supplied.
]]
function SubdivideFunctions.Octree(Part : Types.WorldInfo, PartGridLength : Vector3, VoxelSize : Vector3, GroupMinimumCornerPosition : Vector3)
	local Axis, i = table.create(3), 1
	for _, axis in ipairs(axisNameArray) do
		if PartGridLength[axis] == 1 then continue end
		Axis[i] = axis
		i += 1
	end

	local PartCFrame = Part.CFrame

	local createdParts = { { CFrame = PartCFrame, Size = Part.Size } }
	local tmpParts = {}

	for _, axis in ipairs(Axis) do
		local ax, ay = axis == "X", axis == "Y"

		local worldAxisVector = (ax and PartCFrame.XVector) or (ay and PartCFrame.YVector) or PartCFrame.ZVector

		for _, part in ipairs(createdParts) do
			local size = part.Size
            local hs, cframe = size[axis] * 0.5, part.CFrame

			local centerOnAxis = worldAxisVector:Dot(cframe.Position - GroupMinimumCornerPosition)

			local gridStep : number = VoxelSize[axis]
			local toSplitPoint = gridStep*math.round(centerOnAxis/gridStep) - centerOnAxis

			if math.abs(toSplitPoint) < EPSILON then
				local newSize = size*splitInHalfVectors[axis]
				local off = worldAxisVector*newSize[axis]*0.5
				table.insert(tmpParts, {
					CFrame = cframe - off,
					Size = newSize,
					DirtyGroupID = Part.DirtyGroupID,
					FallingGroupSectionID = Part.FallingGroupSectionID,
					Verts = false,
					isEdge = false
				})
				table.insert(tmpParts, {
					CFrame = cframe + off,
					Size = newSize,
					DirtyGroupID = Part.DirtyGroupID,
					FallingGroupSectionID = Part.FallingGroupSectionID,
					Verts = false,
					isEdge = false
				})
				continue
			end

			local minSize = hs + toSplitPoint
			local maxSize = hs - toSplitPoint

			local splitPointCF = cframe + worldAxisVector*toSplitPoint
			local splitWorldAxisVector = worldAxisVector*0.5

			local minSizeVec, maxSizeVec
			if ax then
				local ySize, zSize = size.Y, size.Z
				minSizeVec = Vector3.new(minSize, ySize, zSize)
				maxSizeVec = Vector3.new(maxSize, ySize, zSize)
			elseif ay then
				local xSize, zSize = size.X, size.Z
				minSizeVec = Vector3.new(xSize, minSize, zSize)
				maxSizeVec = Vector3.new(xSize, maxSize, zSize)
			else
				local xSize, ySize = size.X, size.Y
				minSizeVec = Vector3.new(xSize, ySize, minSize)
				maxSizeVec = Vector3.new(xSize, ySize, maxSize)
			end
			table.insert(tmpParts, {
				CFrame = splitPointCF - splitWorldAxisVector*minSize,
				Size = minSizeVec,
				DirtyGroupID = Part.DirtyGroupID,
				FallingGroupSectionID = Part.FallingGroupSectionID,
				Verts = false,
				isEdge = false
			})
			table.insert(tmpParts, {
				CFrame = splitPointCF + splitWorldAxisVector*maxSize,
				Size = maxSizeVec,
				DirtyGroupID = Part.DirtyGroupID,
				FallingGroupSectionID = Part.FallingGroupSectionID,
				Verts = false,
				isEdge = false
			})
		end

		createdParts = tmpParts
		tmpParts = {}
	end

	return createdParts
end



--[[ Modified KD-tree Subdivide

    Does not mutate the supplied Part reference, which is meant to be an object with the structure {Size : Vector3, CFrame : CFrame}

    Returns an array with the structure { {Size : Vector3, CFrame : CFrame} }

    Calculates the division of a part into 2 pieces along its longest axis in voxel coordinates.

    Maintains grid structure according to the VoxelSize and GroupMinimumCorner supplied.
]]
function SubdivideFunctions.KD(Part : Types.WorldInfo, PartGridLength : Vector3, VoxelSize : Vector3, GroupMinimumCornerPosition : Vector3)
	local lenX, lenY, lenZ = PartGridLength.X, PartGridLength.Y, PartGridLength.Z
	local maxSize = math.max(lenX, lenY, lenZ)
	local axis = (lenX == maxSize and "X") or (lenY == maxSize and "Y") or "Z"
	local PartSize = Part.Size

	local PartCFrame = Part.CFrame
	local worldAxisVector = (axis == "X" and PartCFrame.XVector) or (axis == "Y" and PartCFrame.YVector) or PartCFrame.ZVector

	local centerOnAxis = worldAxisVector:Dot(PartCFrame.Position - GroupMinimumCornerPosition)

	local gridStep : number = VoxelSize[axis]
	local toSplitPoint = gridStep*math.round(centerOnAxis/gridStep) - centerOnAxis

	local createdParts = table.create(2)

	if math.abs(toSplitPoint) < EPSILON then
		local newSize = PartSize*splitInHalfVectors[axis]
		local off = worldAxisVector*newSize[axis]*0.5
		createdParts[1] = {
			CFrame = PartCFrame - off,
			Size = newSize,
			DirtyGroupID = Part.DirtyGroupID,
			FallingGroupSectionID = Part.FallingGroupSectionID,
			Verts = false,
			isEdge = false
		}
		createdParts[2] = {
			CFrame = PartCFrame + off,
			Size = newSize,
			DirtyGroupID = Part.DirtyGroupID,
			FallingGroupSectionID = Part.FallingGroupSectionID,
			Verts = false,
			isEdge = false
		}
		return createdParts
	end
	maxSize = PartSize[axis] * 0.5

	local minSize = maxSize + toSplitPoint
	maxSize -= toSplitPoint

	local splitPointCF = PartCFrame + worldAxisVector*toSplitPoint
	local splitWorldAxisVector = worldAxisVector*0.5

	local minSizeVec, maxSizeVec
	if axis == "X" then
		local ySize, zSize = PartSize.Y, PartSize.Z
		minSizeVec = Vector3.new(minSize, ySize, zSize)
		maxSizeVec = Vector3.new(maxSize, ySize, zSize)
	elseif axis == "Y" then
		local xSize, zSize = PartSize.X, PartSize.Z
		minSizeVec = Vector3.new(xSize, minSize, zSize)
		maxSizeVec = Vector3.new(xSize, maxSize, zSize)
	else
		local xSize, ySize = PartSize.X, PartSize.Y
		minSizeVec = Vector3.new(xSize, ySize, minSize)
		maxSizeVec = Vector3.new(xSize, ySize, maxSize)
	end
	createdParts[1] = {
		CFrame = splitPointCF - splitWorldAxisVector*minSize,
		Size = minSizeVec,
		DirtyGroupID = Part.DirtyGroupID,
		FallingGroupSectionID = Part.FallingGroupSectionID,
		Verts = false,
		isEdge = false
	}
	createdParts[2] = {
		CFrame = splitPointCF + splitWorldAxisVector*maxSize,
		Size = maxSizeVec,
		DirtyGroupID = Part.DirtyGroupID,
		FallingGroupSectionID = Part.FallingGroupSectionID,
		Verts = false,
		isEdge = false
	}
	return createdParts
end



return SubdivideFunctions
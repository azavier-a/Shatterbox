--!native
--!optimize 2

local PartTypeContainsPoint = {}

PartTypeContainsPoint.Ball = function(cframe : CFrame, size : Vector3, p : Vector3)

	local dp = p - cframe.Position
	local dx, dy, dz = dp.X, dp.Y, dp.Z
	local minSize = math.min(size.X, size.Y, size.Z) * 0.5

	return dx*dx + dy*dy + dz*dz <= minSize*minSize
end

PartTypeContainsPoint.Cylinder = function(cframe : CFrame, size : Vector3, p : Vector3)

	local localPoint = cframe:PointToObjectSpace(p):Abs()

	if localPoint.X > size.X * 0.5 then return false end
	
	local dy, dz = localPoint.Y, localPoint.Z
	local minSize = math.min(size.Y, size.Z) * 0.5

	return dy*dy + dz*dz <= minSize*minSize
end

PartTypeContainsPoint.Block = function(cframe : CFrame, size : Vector3, p : Vector3)

	local localPoint = cframe:PointToObjectSpace(p):Abs()

	return (localPoint.X <= size.X * 0.5) and (localPoint.Y <= size.Y * 0.5) and (localPoint.Z <= size.Z * 0.5)
end

PartTypeContainsPoint.Wedge = function(cframe : CFrame, size : Vector3, p : Vector3)

	local localPoint = cframe:PointToObjectSpace(p)
	local absPoint = localPoint:Abs()
	local wsy, wsz = size.Y, size.Z

	return (absPoint.X <= size.X * 0.5) and (absPoint.Y <= wsy * 0.5) and (absPoint.Z <= wsz * 0.5) and (localPoint.Y * wsz <= localPoint.Z * wsy)
end

PartTypeContainsPoint.CornerWedge = function(cframe : CFrame, size : Vector3, p : Vector3)

	local localPoint = cframe:PointToObjectSpace(p)
	local absPoint = localPoint:Abs()
	local wsx, wsy, wsz = size.X, size.Y, size.Z

	return (absPoint.X <= wsx * 0.5) and (absPoint.Y <= wsy * 0.5) and (absPoint.Z <= wsz * 0.5) and (localPoint.Y * wsz <= localPoint.Z * -wsy) and (localPoint.Y * wsx <= localPoint.X * wsy)
end

local unit_cube_verts = {}

for X = -0.5, 0.5  do
    for Y = -0.5, 0.5 do
        for Z = -0.5, 0.5 do
            table.insert(unit_cube_verts, Vector3.new(X, Y, Z))
        end
    end
end

local function GetBlockPartVertices(cframe : CFrame, size : Vector3)

	local vertices = {}

	for _, vert in ipairs(unit_cube_verts) do
        table.insert(vertices, vert*size)
    end

	return table.pack(cframe:PointToWorldSpace(unpack(vertices)))
end


local function PartEncapsulatesBlockPart(part : Part, blockCFrame : CFrame, blockSize : Vector3)

	local PartContainsPoint = PartTypeContainsPoint[part.Shape.Name]
	local partSize = part.Size
	local partCFrame = part.CFrame

	for _, vert in ipairs(GetBlockPartVertices(blockCFrame, blockSize)) do

		if PartContainsPoint(partCFrame, partSize, vert) then continue end

		return false
	end

	return true
end



local function PartContainsAllVerts(part : Part, verts : {Vector3})

	local PartContainsPoint = PartTypeContainsPoint[part.Shape.Name]
	local partSize = part.Size
	local partCFrame = part.CFrame

	for _, vert in ipairs(verts) do

		if PartContainsPoint(partCFrame, partSize, vert) then continue end

		return false
	end

	return true
end


local function PartContainsAVert(part : Part, verts : {Vector3})

	local PartContainsPoint = PartTypeContainsPoint[part.Shape.Name]
	local partSize = part.Size
	local partCFrame = part.CFrame

	for i, vert in ipairs(verts) do

		if PartContainsPoint(partCFrame, partSize, vert) then return i end
	end

	return false
end


local localAxisVectors = { X = "RightVector", Y = "UpVector", Z = "ZVector" }

type PartType = {CFrame : CFrame, Size : Vector3}


local function MOTS(Part : PartType, GridSize : number)
	local PartSize = Part.Size
	local Axis = {}

	for axis in pairs(localAxisVectors) do
		if PartSize[axis] * 0.5 < GridSize then continue end
		table.insert(Axis, axis)
	end

	if #Axis == 0 then return nil end

	local createdParts = { { CFrame = Part.CFrame, Size = PartSize } }
	local tmpParts = {}

	local ax,ay,az, la, size, hs, cframe, hla, ps
	for _, axis in pairs(Axis) do
		ax, ay, az = axis == "X", axis == "Y", axis == "Z"
		la = localAxisVectors[axis]

		for _, part in pairs(createdParts) do
			size = part.Size
			hs = size[axis] * 0.5
			cframe = part.CFrame
			hla = cframe[la] * 0.5 * hs
			ps = Vector3.new( (ax and hs or size.X) , (ay and hs or size.Y) , (az and hs or size.Z) )

			table.insert(tmpParts, { CFrame = cframe + hla, Size = ps })
			table.insert(tmpParts, { CFrame = cframe - hla, Size = ps }) 
		end

		createdParts = tmpParts
		tmpParts = {}
	end

	return createdParts
end


local function KDS(Part : PartType, GridSize : number)
	local PartSize = Part.Size
	local axis, maxSize

	for a in pairs(localAxisVectors) do
		local PartSizeAxis = PartSize[a]
		if PartSizeAxis * 0.5 < GridSize then continue end
		if axis and maxSize > PartSizeAxis then continue end
		axis, maxSize = a, PartSizeAxis
	end

	if not axis then return nil end

	local hs = PartSize[axis] * 0.5
	local cframe = Part.CFrame
	local hla = cframe[localAxisVectors[axis]] * 0.5 * hs

	local ps = Vector3.new(
		axis == "X" and hs or PartSize.X,
		axis == "Y" and hs or PartSize.Y,
		axis == "Z" and hs or PartSize.Z
	)

	return { { CFrame = cframe + hla, Size = ps }, { CFrame = cframe - hla, Size = ps } }
end




local VertexMath = {}

VertexMath.PartEncapsulatesBlockPart = PartEncapsulatesBlockPart

VertexMath.GetBlockPartVertices = GetBlockPartVertices

VertexMath.PartContainsAllVerts = PartContainsAllVerts

VertexMath.PartContainsAVert = PartContainsAVert

VertexMath.MOTS = MOTS

VertexMath.KDS = KDS

return VertexMath
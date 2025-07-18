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

local unit_cube_edges = { {1,2}, {1,3}, {1,5}, {2,4}, {2,6}, {3,4}, {3,7}, {4,8}, {5,6}, {5,7}, {6,8}, {7,8} }


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



local axisID = {"X", "Y", "Z"}
local function SegmentIntersectsOBB(p0: Vector3, p1: Vector3, boxCFrame : CFrame, boxSize : Vector3): boolean
    local halfSize = boxSize * 0.5
    local lP0 = boxCFrame:PointToObjectSpace(p0)
    local dir = boxCFrame:PointToObjectSpace(p1) - lP0

    for _, axis in ipairs(axisID) do
        local min = -halfSize[axis]
        local max = halfSize[axis]
        local p0a = lP0[axis]
        local da = dir[axis]

        if math.abs(da) < 1e-8 and (p0a < min or p0a > max) then
            return false
		end

		da = 1 / da
		local t1 = (min - p0a) * da
		local t2 = (max - p0a) * da
		local tmin = math.max(0, math.min(t1, t2))
		local tmax = math.min(1, math.max(t1, t2))
		if tmin > tmax then return false end
    end

    return true
end



local function SegmentIntersectsCylinder(L1, L2, C1, C2, radius)
    local EPSILON = 1e-6

    local Ca = C2 - C1 -- cylinder axis
    local d = L2 - L1 -- segment direction
    local m = L1 - C1
    local n = Ca.Unit

    -- Components perpendicular to the cylinder axis
    local md = m - n * m:Dot(n)
    local dd = d - n * d:Dot(n)

    local a = dd:Dot(dd)
    local b = 2 * dd:Dot(md)
    local c = md:Dot(md) - radius * radius

    local discriminant = b * b - 4 * a * c
    if discriminant < 0 then
        return false -- No real roots; no intersection with infinite cylinder
    end

    -- Solve quadratic for t values (along segment)
    local sqrtDisc = math.sqrt(discriminant)
    local t1 = (-b - sqrtDisc) / (2 * a)
    local t2 = (-b + sqrtDisc) / (2 * a)

    -- Clamp t1 and t2 to [0,1] range
    local function isInsideSegment(t)
        return t >= 0 - EPSILON and t <= 1 + EPSILON
    end

    for _, t in ipairs({t1, t2}) do
        if isInsideSegment(t) then
            local point = L1 + d * t
            local projLength = (point - C1):Dot(n)
            local axisLength = Ca.Magnitude
            if projLength >= 0 - EPSILON and projLength <= axisLength + EPSILON then
                return true -- Intersects within the finite cylinder
            end
        end
    end

    return false -- No valid intersection found
end


local function PlaneIntersectsCylinder(P: Vector3, S: Vector2, U: Vector3, V: Vector3, C0: Vector3, C1: Vector3, radius: number): boolean
    local N = U:Cross(V).Unit
    local Vcyl = C1 - C0
    local lenCyl = Vcyl.Magnitude
    if lenCyl < 1e-8 then return false end
    local VcylUnit = Vcyl.Unit

    local d0 = N:Dot(C0 - P)
    local d1 = N:Dot(C1 - P)

    if d0 > radius and d1 > radius then return false end
    if d0 < -radius and d1 < -radius then return false end

    local denom = N:Dot(VcylUnit)
    local t: number
    if math.abs(denom) < 1e-8 then
        t = 0.5 * lenCyl
    else
        t = -N:Dot(C0 - P) / denom
    end

    if t < 0 or t > lenCyl then return false end

    local P_axis = C0 + VcylUnit * t
    local d = P_axis - P
    local u = d:Dot(U)
    local v = d:Dot(V)

    return math.abs(u) <= S.X + radius and math.abs(v) <= S.Y + radius
end




local localAxisVectors = { X = "RightVector", Y = "UpVector", Z = "ZVector" }




local PartTypeIntersectsOBB = {}

PartTypeIntersectsOBB.Ball = function(sphere: Part, boxCFrame : CFrame, boxSize : Vector3): boolean
    local radius = math.min(sphere.Size.X, sphere.Size.Y, sphere.Size.Z) * 0.5
    local localCenter = boxCFrame:Inverse() * sphere.Position
    local halfSize = boxSize * 0.5

    local clamped = Vector3.new(
        math.clamp(localCenter.X, -halfSize.X, halfSize.X),
        math.clamp(localCenter.Y, -halfSize.Y, halfSize.Y),
        math.clamp(localCenter.Z, -halfSize.Z, halfSize.Z)
    )

    return (localCenter - clamped).Magnitude <= radius
end


PartTypeIntersectsOBB.Cylinder = function(cylinder: Part, boxCFrame : CFrame, boxSize : Vector3, vertices): boolean
	local cf = cylinder.CFrame
	local hsa = cf.RightVector * cylinder.Size.X * 0.5
	local p = cf.Position
	local bp = boxCFrame.Position
	local c0, c1 = p + hsa, p - hsa
	local radius = math.min(cylinder.Size.Y, cylinder.Size.Z)

	for _, seg in ipairs(unit_cube_edges) do
		if SegmentIntersectsCylinder(vertices[seg[1]], vertices[seg[2]], c0, c1, radius) then return true end
	end

	for i, a in ipairs(axisID) do
		local la = localAxisVectors[a]
		local sf = table.clone(axisID)
		table.remove(sf, i)

		local UA, VA = sf[1], sf[2]
		local ULA, VLA = localAxisVectors[UA], localAxisVectors[VA]
		local S = Vector2.new(boxSize[UA], boxSize[VA]) * 0.5

		local CLA = cf[la]
		local lcf = boxCFrame[la] * boxSize[a] * 0.5

		if PlaneIntersectsCylinder(bp + lcf, S, CLA, c0, c1, radius) then return true end
		if PlaneIntersectsCylinder(bp - lcf, S, CLA, c0, c1, radius) then return true end
	end

	return false
end


local function PartIntersectsOBB(Part : Part, obbCFrame : CFrame, obbSize : Vector3)

	return PartTypeIntersectsOBB[Part.Shape.Name](Part, obbCFrame, obbSize, GetBlockPartVertices(obbCFrame, obbSize))
end






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

VertexMath.PartIntersectsOBB = PartIntersectsOBB


VertexMath.MOTS = MOTS

VertexMath.KDS = KDS



return VertexMath
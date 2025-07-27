--!native
--!optimize 2

local EPSILON = 1e-6

local localAxisVectors = { X = "RightVector", Y = "UpVector", Z = "ZVector" }

local axisID = {"X", "Y", "Z"}



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



local GetVerts = {}

GetVerts.Block = function(cframe : CFrame, size : Vector3)
    local lx, ly, lz = cframe.XVector*size.X, cframe.YVector*size.Y, cframe.ZVector*size.Z
    local ny, nz = -ly, -lz
    local pnx, plx = cframe.Position - lx, cframe.Position + lx
    local pnxny, pnxly, plxny, plxly = pnx + ny, pnx + ly, plx + ny, plx + ly
    return {
        pnxny + nz,
        pnxny + lz,
        pnxly + nz,
        pnxly + lz,
        plxny + nz,
        plxny + lz,
        plxly + nz,
        plxly + lz
    }
end
local block_edges = { {1,2}, {1,3}, {1,5}, {2,4}, {2,6}, {3,4}, {3,7}, {4,8}, {5,6}, {5,7}, {6,8}, {7,8} }

GetVerts.Wedge = function(cframe : CFrame, size : Vector3)
    local lx, ly, lz = cframe.XVector*size.X, cframe.YVector*size.Y, cframe.ZVector*size.Z
    local ny, nz = -ly, -lz
    local pnx, plx = cframe.Position - lx, cframe.Position + lx
    local pnxny, plxny = pnx + ny, plx + ny
    return {
        pnxny + nz,
        pnxny + lz,
        plxny + nz,
        plxny + lz,
        pnx + ly + lz,
        plx + ly + lz
    }
end
local wedge_edges = { {1,2}, {2,4}, {4,3}, {3,1}, {2,5}, {4,6}, {5,6}, {1,3}, {1,5}, {3,6} }

GetVerts.CornerWedge = function(cframe : CFrame, size : Vector3)
    local lx, ly, lz = cframe.XVector*size.X, cframe.YVector*size.Y, cframe.ZVector*size.Z
    local ny, nz = -ly, -lz
    local pnx, plx = cframe.Position - lx, cframe.Position + lx
    local pnxny, plxny = pnx + ny, plx + ny
    return {
        pnxny + nz,
        pnxny + lz,
        plxny + nz,
        plxny + lz,
        plx + ly + nz
    }
end
local corner_wedge_edges = { {1,2}, {2,4}, {4,3}, {3,1}, {3,5}, {1,5}, {4,5} }



local GetNormals = {}

GetNormals.Block = function(cframe : CFrame)
    local lx, ly, lz = cframe.XVector, cframe.YVector, cframe.ZVector
    return {
        -lx, lx,
        -ly, ly,
        -lz, lz
    }
end

GetNormals.Wedge = function(cframe : CFrame, size : Vector3)
    local lx, ly, lz = cframe.XVector, cframe.YVector, cframe.ZVector
    return {
        -cframe.YVector,
        (lz*size.Y - ly*size.Z).Unit,
        -lz,
        -lx, lx
    }
end

GetNormals.CornerWedge = function(cframe : CFrame, size : Vector3)
    local lx, ly, lz = cframe.XVector, cframe.YVector, cframe.ZVector
    return {
        -ly,
        (lz*size.Y - lx*size.X).Unit,
        (ly*size.Z + lz*size.Y).Unit,
        -lz,
        lx
    }
end



local function ProjectExtent(verts: {Vector3}, axis: Vector3)
	local min, max = nil, nil
    local ax, ay, az = axis.X, axis.Y, axis.Z
	for _, v in verts do
		local d = v.X*ax + v.Y*ay + v.Z*az
        if min then
            min, max = math.min(min, d), math.max(max, d)
        else
            min, max = d, d
        end
	end
	return min, max
end

local function SAT(VA, NA, VB, NB)
    -- Create candidate axis array and indexer
    local candidates, n = table.create(#NA + #NB + #NA*#NB), 0

    -- Populate candidate axis
    for _, a in ipairs(NA) do
        n += 1
		candidates[n] = a

        local ax, ay, az = a.X, a.Y, a.Z
        for _, b in ipairs(NB) do
            n += 1
            candidates[n] = b

            local bx, by, bz = b.X, b.Y, b.Z
            local cross = Vector3.new(
                ay*bz - az*by,
                az*bx - ax*bz,
                ax*by - ay*bx
            )
            if cross.Magnitude > EPSILON then
                n += 1
                candidates[n] = cross.Unit
            end
        end
    end

    -- SAT test on all candidate axes
    for _, axis in candidates do
        local min1, max1 = ProjectExtent(VA, axis)
        local min2, max2 = ProjectExtent(VB, axis)

        if max1 < min2 or max2 < min1 then
            return false -- Separating axis found
        end
    end

    return true -- No separating axis found
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

local function PartEncapsulatesBlockPart(part : Part, blockCFrame : CFrame, blockSize : Vector3)

	return PartContainsAllVerts(part, GetVerts.Block(blockCFrame, blockSize))
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

local function BallIntersectsBlock(sphereCFrame, sphereSize, boxCFrame : CFrame, boxSize : Vector3)
	local radius = math.min(sphereSize.X, sphereSize.Y, sphereSize.Z) * 0.5
    local localCenter = boxCFrame:Inverse() * sphereCFrame.Position
    local halfSize = boxSize * 0.5

    local clamped = Vector3.new(
        math.clamp(localCenter.X, -halfSize.X, halfSize.X),
        math.clamp(localCenter.Y, -halfSize.Y, halfSize.Y),
        math.clamp(localCenter.Z, -halfSize.Z, halfSize.Z)
    )

    return (localCenter - clamped).Magnitude <= radius
end

local function SegmentIntersectsCylinder(L1, L2, C1, C2, radius)

    local Ca = C2 - C1
    if Ca.Magnitude < EPSILON then return false end
    local n = Ca.Unit

    local d = L2 - L1
    local m = L1 - C1

    local md = m - n * m:Dot(n)
    local dd = d - n * d:Dot(n)

    local a = dd:Dot(dd)
    local b = 2 * dd:Dot(md)
    local c = md:Dot(md) - radius * radius

    if math.abs(a) < EPSILON then
        -- d parallel to cylinder axis or nearly so
        local projL1 = (L1 - C1):Dot(n)
        local radialL1 = (L1 - C1 - n * projL1).Magnitude
        local projL2 = (L2 - C1):Dot(n)
        local radialL2 = (L2 - C1 - n * projL2).Magnitude

        local axisLen = Ca.Magnitude

        if projL1 >= -EPSILON and projL1 <= axisLen + EPSILON and radialL1 <= radius + EPSILON then return true end
        if projL2 >= -EPSILON and projL2 <= axisLen + EPSILON and radialL2 <= radius + EPSILON then return true end

        return false
    end

    local discriminant = b * b - 4 * a * c
    if discriminant < 0 then return false end

    local sqrtDisc = math.sqrt(discriminant)
    local t1 = (-b - sqrtDisc) / (2 * a)
    local t2 = (-b + sqrtDisc) / (2 * a)

    if t1 >= 0 - EPSILON and t1 <= 1 + EPSILON then
        local point = L1 + d * t1
        local projLength = (point - C1):Dot(n)
        local axisLength = Ca.Magnitude
        if projLength >= 0 - EPSILON and projLength <= axisLength + EPSILON then
            return true
        end
    end

    if t2 >= 0 - EPSILON and t2 <= 1 + EPSILON then
        local point = L1 + d * t2
        local projLength = (point - C1):Dot(n)
        local axisLength = Ca.Magnitude
        if projLength >= 0 - EPSILON and projLength <= axisLength + EPSILON then
            return true
        end
    end

    return false
end

local function PlaneIntersectsCylinder(P, S, U, V, C0, C1, radius)
    local N = U:Cross(V).Unit
    local Ca = C1 - C0
    local axisLen = Ca.Magnitude
    if axisLen < 1e-6 then return false end

    local CaUnit = Ca / axisLen
    local d0 = (C0 - P):Dot(N)
    local d1 = (C1 - P):Dot(N)

    if d0 > radius and d1 > radius then return false end
    if d0 < -radius and d1 < -radius then return false end

    local function ProjectOntoPlane(Q)
        local toQ = Q - P
        return Vector2.new(toQ:Dot(U), toQ:Dot(V))
    end

    local q0 = ProjectOntoPlane(C0)
    local q1 = ProjectOntoPlane(C1)
    local axis2D = q1 - q0
    local center = (q0 + q1) * 0.5

    local dir = axis2D.Unit
    local halfLen = (axis2D.Magnitude * 0.5)

    -- radius projects orthogonal to Ca axis in the plane only
    local orthogonalU = (U - CaUnit * U:Dot(CaUnit)).Unit
    local orthogonalV = (V - CaUnit * V:Dot(CaUnit)).Unit

    local radiusU = radius * orthogonalU.Magnitude
    local radiusV = radius * orthogonalV.Magnitude

    local px = math.abs(center.X)
    local py = math.abs(center.Y)
    local dx = math.abs(dir.X) * halfLen + radiusU
    local dy = math.abs(dir.Y) * halfLen + radiusV

    return px <= S.X + dx and py <= S.Y + dy
end

local function CylinderIntersectsBlock(cylinderCFrame, cylinderSize, cylinderBoxVerts, cylinderBoxNormals, boxCFrame, boxSize, boxVerts, boxNormals)

    local halfAxis = cylinderCFrame.RightVector * (cylinderSize.X * 0.5)
    local p = cylinderCFrame.Position
    local c0, c1 = p - halfAxis, p + halfAxis
    local radius = 0.5 * math.min(cylinderSize.Y, cylinderSize.Z)

    for _, seg in ipairs(block_edges) do
        if SegmentIntersectsCylinder(boxVerts[seg[1]], boxVerts[seg[2]], c0, c1, radius) then return true end
    end

	if not SAT(cylinderBoxVerts, cylinderBoxNormals, boxVerts, boxNormals) then return false end

    for i, a in ipairs(axisID) do
        local la = localAxisVectors[a]
        local lcf = boxCFrame[la] * boxSize[a] * 0.5

        local sf = table.clone(axisID)
        table.remove(sf, i)

        local UA, VA = sf[1], sf[2]
        local S = Vector2.new(boxSize[UA], boxSize[VA]) * 0.5

        local U, V = boxCFrame[localAxisVectors[UA]], boxCFrame[localAxisVectors[VA]]

        if PlaneIntersectsCylinder(boxCFrame.Position + lcf, S, U, V, c0, c1, radius) then return true end
        if PlaneIntersectsCylinder(boxCFrame.Position - lcf, S, U, V, c0, c1, radius) then return true end
    end

    return false
end


-- subdivision functions

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

VertexMath.GetVerts = GetVerts

VertexMath.GetNormals = GetNormals

VertexMath.SAT = SAT

VertexMath.PartEncapsulatesBlockPart = PartEncapsulatesBlockPart

VertexMath.PartContainsAllVerts = PartContainsAllVerts

VertexMath.PartContainsAVert = PartContainsAVert

VertexMath.BallIntersectsBlock = BallIntersectsBlock

VertexMath.CylinderIntersectsBlock = CylinderIntersectsBlock

VertexMath.MOTS = MOTS

VertexMath.KDS = KDS

return VertexMath
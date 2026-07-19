--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)

local core = script.Parent.Parent
local src = core.Parent
local lib = core:WaitForChild("lib")

local Types = require(src:WaitForChild("Types"))

local Settings = require(src:WaitForChild("Settings"))
local DebrisTag = Settings.DEBRIS_TAG

local SubdivideFunctions = require(lib:WaitForChild("SubdivideFunctions"))
local ExtentInfo = SubdivideFunctions.ExtentInfo

local State = require(core:WaitForChild("State"))

local DirtyGroupData = State.DirtyGroupData
local DirtyGroupMembers = State.DirtyGroupMembers

local ImaginaryDestroyQueue = State.ImaginaryDestroyQueue
local GreedyMeshedImaginaryParts = State.GreedyMeshedImaginaryParts


local EPSILON_VECTOR = Vector3.one * 1e-3
local MAXU32 = 0xFFFFFFFF


local GreedyMeshLogic = {}


local function InitGreedyState(part, VoxelSize, groupMinCornerCFrame, GMState, DIMYSTATEDIMZ, STATEDIMZ)
	local partSize = part.Size
	local partGridLength = (partSize/VoxelSize + EPSILON_VECTOR):Floor():Max(Vector3.one)
	local lenX, lenY, lenZ = partGridLength.X, partGridLength.Y, partGridLength.Z

	local partMinCornerPosition = part.CFrame:PointToWorldSpace(-partSize*0.5)

	local Offset = groupMinCornerCFrame:PointToObjectSpace(partMinCornerPosition) / VoxelSize
	local DX, DY, DZ = math.round(Offset.X), math.round(Offset.Y), math.round(Offset.Z)

	local ZBitOffset = DZ % 32
	local ZLayerOffset = DZ // 32

	local InitialWriteWidth = math.min(32 - ZBitOffset, lenZ)
	local CountLeftAfterInitial = lenZ - InitialWriteWidth

	local FullLayerSpanCount = CountLeftAfterInitial // 32
	local FinalWriteWidth = CountLeftAfterInitial % 32

	-- Initialize the 3d state volume.   index = (X - 1)*DIMY*STATE_DIMZ + (Y - 1)*STATE_DIMZ + STATE_Z
	for X = 1, lenX do
		local dixz = (X + DX - 1)*DIMYSTATEDIMZ
		for Y = 1, lenY do
			local di = dixz + (Y + DY - 1)*STATEDIMZ + ZLayerOffset + 1

			if InitialWriteWidth > 0 then
				GMState[di] = bit32.bor(GMState[di], bit32.lshift(bit32.lshift(1, InitialWriteWidth) - 1, ZBitOffset))
			end

			for i = 1, FullLayerSpanCount do
				GMState[di + i] = MAXU32
			end

			if FinalWriteWidth > 0 then
				GMState[di + FullLayerSpanCount + 1] = bit32.bor(GMState[di + FullLayerSpanCount + 1], bit32.lshift(1, FinalWriteWidth) - 1)
			end
		end
	end

	return lenX*lenY*lenZ
end



function GreedyMeshLogic.GreedyMesh(DirtyGroupID : string, ImaginaryParts : { Types.ImaginaryBox })
	local dirtyGroupData = DirtyGroupData[DirtyGroupID]
	local dirtyGroupMembers = DirtyGroupMembers[DirtyGroupID]

	local Original = dirtyGroupData.OriginalPart

	local GridLength = dirtyGroupData.MaxGridLength
	local DIMX, DIMY, DIMZ = GridLength.X, GridLength.Y, GridLength.Z

	local VoxelSize = Original.Size / GridLength

	-- The bounding area of Greedy Meshing, defined by the original part before it was ever destroyed
	local OriginalCFrame = Original.CFrame
	local groupMin = ExtentInfo(OriginalCFrame, VoxelSize, GridLength)
	local halfSize = Original.Size * 0.5
	local groupMinCornerCFrame = OriginalCFrame - (OriginalCFrame.XVector*halfSize.X) - (OriginalCFrame.YVector*halfSize.Y) - (OriginalCFrame.ZVector*halfSize.Z)
	local STATEDIMZ = math.ceil(DIMZ / 32)
	local DIMYSTATEDIMZ = DIMY*STATEDIMZ
	local VSX, VSY, VSZ = VoxelSize.X, VoxelSize.Y, VoxelSize.Z

	-- local stateBitCount = DIMX*DIMYDIMZ

	-- flat 3d state array : index = (X - 1)*DIMY*STATE_DIMZ + (Y - 1)*STATE_DIMZ + STATE_Z
	local GMState = table.create(DIMX*DIMYSTATEDIMZ, 0)

	-- information about the original parts, used for smoothly displaying the output of greedy meshing
	local OriginalParts = {} :: { Part }

	-- the total number of voxels in the GMState array
	local count = 0

	for member in pairs(dirtyGroupMembers) do
		if member:HasTag(DebrisTag) then continue end

		table.insert(OriginalParts, member)

		if ImaginaryDestroyQueue[member] then continue end

		local n = InitGreedyState(member, VoxelSize, groupMinCornerCFrame, GMState, DIMYSTATEDIMZ, STATEDIMZ)
		if n then
			count += n
			ImaginaryDestroyQueue[member] = true
		end
	end

	for _, imaginaryMember in ipairs(ImaginaryParts) do
		local n = InitGreedyState(imaginaryMember, VoxelSize, groupMinCornerCFrame, GMState, DIMYSTATEDIMZ, STATEDIMZ)
		if n then
			count += n
		end
	end

	if count == 0 then
		table.move(ImaginaryParts, 1, #ImaginaryParts, #GreedyMeshedImaginaryParts + 1, GreedyMeshedImaginaryParts)
		return
	end

	local meshed = {}

	local searchIndex = 1
	local StateSize = #GMState

	while count > 0 do
		while searchIndex <= StateSize and GMState[searchIndex] == 0 do
			searchIndex += 1
		end
		if searchIndex > StateSize then break end

		local state = GMState[searchIndex]

		local startBit = bit32.countrz(state)
		local shifted = bit32.rshift(state, startBit)

		local run = bit32.countrz(bit32.bnot(shifted))
		if run > (32 - startBit) then
			run = 32 - startBit
		end

		local firstMask = bit32.lshift(bit32.lshift(1, run) - 1, startBit)

		local StartX, rem = ((searchIndex - 1) // DIMYSTATEDIMZ) + 1, (searchIndex - 1) % DIMYSTATEDIMZ
		local StartY, StartLayerZ = (rem // STATEDIMZ) + 1, (rem % STATEDIMZ) + 1
		local StartZ = 32*(StartLayerZ - 1) + startBit + 1

		local EndLayerZ = StartLayerZ
		local EndBit = startBit + run - 1
		local layerIndex = searchIndex
		local lastMask

		while EndBit == 31 and EndLayerZ < STATEDIMZ do
			local nextIndex = layerIndex + 1
			local nextLayer = GMState[nextIndex]
			if not nextLayer or nextLayer == 0 then break end

			if nextLayer == MAXU32 then
				layerIndex = nextIndex
				EndLayerZ += 1
				EndBit = 31
				run += 32
			else
				local r = bit32.countrz(bit32.bnot(nextLayer))
				if r == 0 then break end

				layerIndex = nextIndex
				EndLayerZ += 1
				EndBit = r - 1
				run += r
				lastMask = bit32.lshift(1, r) - 1
				break
			end
		end

		local EndLayerOffset = EndLayerZ - StartLayerZ

		local masks = {}
		for layer = 0, EndLayerOffset do
			if layer == 0 then
				masks[layer] = firstMask
			elseif layer == EndLayerOffset then
				masks[layer] = lastMask or MAXU32
			else
				masks[layer] = MAXU32
			end
		end

		local EndY = StartY
		while EndY < DIMY do
			local nextY = EndY + 1
			local valid = true
			for layer = 0, EndLayerOffset do
				local idx = (StartX - 1)*DIMYSTATEDIMZ + (nextY - 1)*STATEDIMZ + StartLayerZ + layer
				local mask = GMState[idx]
				local req = masks[layer]
				if not mask or bit32.band(mask, req) ~= req then
					valid = false
					break
				end
			end
			if not valid then break end
			EndY += 1
		end

		local EndX = StartX
		while EndX < DIMX do
			local nextX = EndX + 1
			local valid = true
			for Y = StartY, EndY do
				for layer = 0, EndLayerOffset do
					local idx = (nextX - 1)*DIMYSTATEDIMZ + (Y - 1)*STATEDIMZ + StartLayerZ + layer
					local mask = GMState[idx]
					local req = masks[layer]
					if not mask or bit32.band(mask, req) ~= req then
						valid = false
						break
					end
				end
				if not valid then break end
			end
			if not valid then break end
			EndX += 1
		end

		for X = StartX, EndX do
			for Y = StartY, EndY do
				local I = (X - 1)*DIMYSTATEDIMZ + (Y - 1)*STATEDIMZ + StartLayerZ
				local EndLayerIndex = I + EndLayerOffset

				GMState[I] = bit32.band(GMState[I], bit32.bnot(firstMask))
				for i = 1, EndLayerOffset - 1 do
					GMState[I + i] = 0
				end
				if lastMask then
					GMState[EndLayerIndex] = bit32.band(GMState[EndLayerIndex], bit32.bnot(lastMask))
				elseif EndLayerOffset > 0 then
					GMState[EndLayerIndex] = 0
				end
			end
		end

		local EndZ = 32*(EndLayerZ - 1) + EndBit + 1

		local NX = EndX - StartX + 1
		local NY = EndY - StartY + 1
		local NZ = EndZ - StartZ + 1

		count -= NX * NY * NZ

		table.insert(meshed, {
			DirtyGroupID = DirtyGroupID,
			CFrame = groupMin + groupMin.XVector * VSX * ((StartX + EndX)*0.5 - 1) + groupMin.YVector * VSY * ((StartY + EndY)*0.5 - 1) + groupMin.ZVector * VSZ * ((StartZ + EndZ)*0.5 - 1),
			Size = VoxelSize * Vector3.new(NX, NY, NZ)
		})
	end


	for _, meshedInfo in ipairs(meshed) do
		local index, found = nil, nil
		for i, original in ipairs(OriginalParts) do
			if original.CFrame:FuzzyEq(meshedInfo.CFrame, 0.001) and original.Size:FuzzyEq(meshedInfo.Size, 0.001) then
				index, found = i, original
				break
			end
		end
		if index then
			table.remove(OriginalParts, index)
			ImaginaryDestroyQueue[found] = nil
		else
			table.insert(GreedyMeshedImaginaryParts, meshedInfo)
		end
	end
	--table.move(meshed, 1, #meshed, #GreedyMeshedImaginaryParts + 1, GreedyMeshedImaginaryParts)
end



return GreedyMeshLogic
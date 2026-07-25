--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)

local core = script.Parent.Parent
local src = core.Parent

local Settings = require(src:WaitForChild("Settings"))
local Types = require(src:WaitForChild("Types"))

local State = require(core:WaitForChild("State"))


local EPSILON = 1e-3
local EPSILON_VECTOR = Vector3.one * EPSILON
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



local function BinaryGreedyMesh(GMState, count, DirtyGroupID, groupMinCornerCFrame, FallingGroupSectionID)

	local dirtyGroupData = State.DirtyGroupData[DirtyGroupID]

	local VoxelSize = dirtyGroupData.VoxelSize
	local GridLength = dirtyGroupData.MaxGridLength
	local DIMX, DIMY, DIMZ = GridLength.X, GridLength.Y, GridLength.Z

	local groupMinVoxelCFrame = groupMinCornerCFrame:ToWorldSpace(CFrame.new(VoxelSize*0.5))
	local STATEDIMZ = math.ceil(DIMZ / 32)
	local DIMYSTATEDIMZ = DIMY*STATEDIMZ
	local VSX, VSY, VSZ = VoxelSize.X, VoxelSize.Y, VoxelSize.Z

	local searchIndex = 1
	local StateSize = #GMState

	local meshed = {}

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
			FallingGroupSectionID = FallingGroupSectionID,
			CFrame = groupMinVoxelCFrame + groupMinVoxelCFrame.XVector * VSX * ((StartX + EndX)*0.5 - 1) + groupMinVoxelCFrame.YVector * VSY * ((StartY + EndY)*0.5 - 1) + groupMinVoxelCFrame.ZVector * VSZ * ((StartZ + EndZ)*0.5 - 1),
			Size = VoxelSize * Vector3.new(NX, NY, NZ)
		})
	end

	return meshed
end


local function GreedyMeshRelativeTo(ExistingParts, ImaginaryParts, groupMinCornerCFrame, DirtyGroupID, FallingGroupSectionID)
	local dirtyGroupData = State.DirtyGroupData[DirtyGroupID]
	local VoxelSize = dirtyGroupData.VoxelSize

	-- The bounding area of Greedy Meshing, defined by the original part before it was ever destroyed
	local STATEDIMZ = math.ceil(dirtyGroupData.MaxGridLength.Z/32)
	local DIMYSTATEDIMZ = dirtyGroupData.MaxGridLength.Y*STATEDIMZ

	-- flat 3d state array : index = (X - 1)*DIMY*STATE_DIMZ + (Y - 1)*STATE_DIMZ + STATE_Z
	local GMState = table.create(dirtyGroupData.MaxGridLength.X*DIMYSTATEDIMZ, 0)

	-- information about the original parts, used for smoothly displaying the output of greedy meshing
	local OriginalParts = {} :: { Part }

	-- the total number of voxels in the GMState array
	local count = 0

	for member in pairs(ExistingParts) do
		if member:HasTag(Settings.DEBRIS_TAG) then continue end

		table.insert(OriginalParts, member)

		if State.ImaginaryDestroyQueue[member] then continue end

		local n = InitGreedyState(member, VoxelSize, groupMinCornerCFrame, GMState, DIMYSTATEDIMZ, STATEDIMZ)
		if n then
			count += n
			State.ImaginaryDestroyQueue[member] = true
		end
	end

	for _, imaginaryMember in ipairs(ImaginaryParts) do
		local n = InitGreedyState(imaginaryMember, VoxelSize, groupMinCornerCFrame, GMState, DIMYSTATEDIMZ, STATEDIMZ)
		if n then
			count += n
		end
	end

	if count == 0 then
		table.move(ImaginaryParts, 1, #ImaginaryParts, #State.GreedyMeshedImaginaryParts + 1, State.GreedyMeshedImaginaryParts)
		return
	end

	for _, MeshedSpan in ipairs(BinaryGreedyMesh(GMState, count, DirtyGroupID, groupMinCornerCFrame, FallingGroupSectionID)) do
		local index, found = nil, nil
		for i, original in ipairs(OriginalParts) do
			if not original.CFrame:FuzzyEq(MeshedSpan.CFrame, EPSILON) or not original.Size:FuzzyEq(MeshedSpan.Size, EPSILON) then continue end
			index, found = i, original
		end
		if not index then
			table.insert(State.GreedyMeshedImaginaryParts, MeshedSpan)
			continue
		end

		OriginalParts[index] = OriginalParts[#OriginalParts]
		OriginalParts[#OriginalParts] = nil
		State.ImaginaryDestroyQueue[found] = nil
	end
end



function GreedyMeshLogic.GreedyMeshDirtyGroup(DirtyGroupID : string, ImaginaryParts : { Types.ImaginaryBox })
	local Original = State.DirtyGroupData[DirtyGroupID].OriginalPart

	local FallingGroupID = Original:GetAttribute(Settings.FALLING_GROUP_ID_ATTRIBUTE_NAME)
	if not FallingGroupID then
		GreedyMeshRelativeTo(State.DirtyGroupMembers[DirtyGroupID], ImaginaryParts, Original.CFrame:ToWorldSpace(CFrame.new(-Original.Size*0.5)), DirtyGroupID)
		return
	end

	-- { [BasePart] : boolean }, {ImaginaryBox}
	local StaticMembers, StaticImaginaryParts = {}, {}
	-- { [FallingGroupSectionID] : { [BasePart] : boolean } }, { [FallingGroupSectionID] : {ImaginaryBox} }
	local FallingGroupSectionMembers, FallingGroupSectionImaginaryParts = {}, {}
	for member in pairs(State.DirtyGroupMembers[DirtyGroupID]) do
		local FallingGroupSectionID = member:GetAttribute(Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME)
		if not FallingGroupSectionID then
			StaticMembers[member] = true
		elseif State.ChangedFallingGroupSections[FallingGroupSectionID] then
			local SectionMembers = FallingGroupSectionMembers[FallingGroupSectionID]
			if not SectionMembers then
				SectionMembers = {}
				FallingGroupSectionMembers[FallingGroupSectionID] = SectionMembers
			end
			if not FallingGroupSectionImaginaryParts[FallingGroupSectionID] then
				FallingGroupSectionImaginaryParts[FallingGroupSectionID] = {}
			end
			SectionMembers[member] = true
		end
	end
	for _, imaginaryMember in ipairs(ImaginaryParts) do
		local FallingGroupSectionID = imaginaryMember.FallingGroupSectionID
		if not FallingGroupSectionID then
			table.insert(StaticImaginaryParts, imaginaryMember)
		elseif State.ChangedFallingGroupSections[FallingGroupSectionID] then
			local SectionImaginaryMembers = FallingGroupSectionImaginaryParts[FallingGroupSectionID]
			if not SectionImaginaryMembers then
				SectionImaginaryMembers = {}
				FallingGroupSectionImaginaryParts[FallingGroupSectionID] = SectionImaginaryMembers
			end
			if not FallingGroupSectionMembers[FallingGroupSectionID] then
				FallingGroupSectionMembers[FallingGroupSectionID] = {}
			end
			table.insert(SectionImaginaryMembers, imaginaryMember)
		end
	end

	if next(StaticMembers) or #StaticImaginaryParts > 0 then
		GreedyMeshRelativeTo(StaticMembers, StaticImaginaryParts, Original.CFrame:ToWorldSpace(CFrame.new(-Original.Size*0.5)), DirtyGroupID)
	end

	for FallingGroupSectionID, SectionMembers in pairs(FallingGroupSectionMembers) do
		local SectionAnchor = State.FallingGroupSectionAnchors[FallingGroupID][FallingGroupSectionID]
		GreedyMeshRelativeTo(SectionMembers, FallingGroupSectionImaginaryParts[FallingGroupSectionID], SectionAnchor.CFrame:ToWorldSpace(State.FallingDirtyGroupMinCornerLocalToAnchor[DirtyGroupID]), DirtyGroupID, FallingGroupSectionID)
	end
end



return GreedyMeshLogic
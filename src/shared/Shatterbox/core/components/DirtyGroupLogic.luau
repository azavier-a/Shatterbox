--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local isServer = RunService:IsServer()

local core = script.Parent.Parent
local lib = core:WaitForChild("lib")
local src = core.Parent

--local Types = require(src:WaitForChild("Types"))

local Settings = require(src:WaitForChild("Settings"))

local VertexMath = require(lib:WaitForChild("VertexMath"))
local PartOperations = require(lib:WaitForChild("PartOperations"))
local Serializer = require(lib:WaitForChild("Serializer"))

local State = require(core:WaitForChild("State"))


local function RoundToNearestPowerOf2(x : number)
	local _, ceilLogged = math.frexp(x)
	local l, h = math.ldexp(1, ceilLogged - 1), math.ldexp(1, ceilLogged)
	return x - l < h - x and l or h
end

-- Returns the first occurance of an ancestor Group Instance (Folder/Model).
local function FindFirstAncestorGroup(i : Instance) : (Folder|Model)?
	local Ancestor = i.Parent

	while Ancestor and not (Ancestor:IsA("Folder") or Ancestor:IsA("Model")) do
        Ancestor = Ancestor.Parent
    end

	return Ancestor
end

-- Returns all of the tags of every ancestor Group Instance (Folder/Model) as an array
local function AncestorGroupTags(i : Instance) : {string}
	local tags = {}

	local Ancestor = FindFirstAncestorGroup(i)
	while Ancestor do
		local t = Ancestor:GetTags()

		if #t > 0 then
			table.move(t, 1, #t, #tags + 1, tags)
		end
		Ancestor = FindFirstAncestorGroup(Ancestor)
	end

	return tags
end

-- If the given Instance or any of its ancestor Group Instances (Folder/Model) has the given tag, returns the Instance with the tag.
local function GroupHasTag(i : Instance, tag : string) : Instance?
	if i:HasTag(tag) then
		return i
	end
	local Ancestor = FindFirstAncestorGroup(i)
	while Ancestor do
		if Ancestor:HasTag(tag) then
			return Ancestor
		end
		Ancestor = FindFirstAncestorGroup(Ancestor)
	end
	return nil
end



local DirtyGroupLogic = {}
DirtyGroupLogic.GroupHasTag = GroupHasTag

local function RoundAxisNearestPowerOf2(v : Vector3)
    return Vector3.new(RoundToNearestPowerOf2(v.X), RoundToNearestPowerOf2(v.Y), RoundToNearestPowerOf2(v.Z))
end
DirtyGroupLogic.RoundAxisNearestPowerOf2 = RoundAxisNearestPowerOf2


local textUVMap = {
	[0] = Vector3.new( 0,  1,  1),
	[1] = Vector3.new( 1,  0,  1),
	[2] = Vector3.new(-1,  1,  0),
	[3] = Vector3.new( 0,  1, -1),
	[4] = Vector3.new(-1,  0,  1),
	[5] = Vector3.new( 1,  1,  0)
}
local axisUVMap = {
	[0] = { "Z", "Y" },
	[1] = { "X", "Z" },
	[2] = { "X", "Y" },
	[3] = { "Z", "Y" },
	[4] = { "X", "Z" },
	[5] = { "X", "Y" }
}
--Instantiates a new member of a dirty group using the group ID and a given CFrame and Size
local function InstantiatePart(DirtyGroupID, cframe, size, FallingGroupSectionID, doNotUseObjectCache)
	--debug.profilebegin("InstantiatePart")
	local dirtyGroupData, dirtyGroupMembers = State.DirtyGroupData[DirtyGroupID], State.DirtyGroupMembers[DirtyGroupID]

	local part = PartOperations.PartFromTemplate(dirtyGroupData.OriginalPart, cframe, not doNotUseObjectCache and State.CachedParts)
	if FallingGroupSectionID then
		part:SetAttribute(Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME, FallingGroupSectionID)

		local FallingGroupID = part:GetAttribute(Settings.FALLING_GROUP_ID_ATTRIBUTE_NAME)
		State.FallingGroupSectionMembers[FallingGroupID][FallingGroupSectionID][part] = true
	end
	part.Size = size

	local partIsDivisible = part:IsA("Part") and part.Shape == Enum.PartType.Block

	if not partIsDivisible or not Settings.USE_CLIENT_SERVER or part:HasTag(Settings.BLOCK_CLIENT_SERVER_TAG) then
		part.Parent = dirtyGroupData.OriginalParent
	else
		part.Parent = State.MapContainer
	end

	if partIsDivisible and part:FindFirstChildWhichIsA("Texture") then
		local OriginalPart = dirtyGroupData.OriginalPart
		local HalfSizeOriginal = OriginalPart.Size * 0.5
		local HalfSizePart = part.Size * 0.5

		for _, texture in ipairs(part:GetChildren()) do
			if not texture:IsA("Texture") then continue end
			local Face = texture.Face.Value
			local TowardOrigin = textUVMap[Face]

			local GroupOrigin = OriginalPart.CFrame + OriginalPart.CFrame:VectorToWorldSpace(TowardOrigin * HalfSizeOriginal)
			local partOrigin = cframe + cframe:VectorToWorldSpace(TowardOrigin * HalfSizePart)

			local Offset = partOrigin:VectorToObjectSpace(GroupOrigin.Position - partOrigin.Position):Abs()

			texture.OffsetStudsU += Offset[axisUVMap[Face][1]]
			texture.OffsetStudsV += Offset[axisUVMap[Face][2]]
		end
	end

	dirtyGroupMembers[part] = true

	if Settings.USE_OBJECT_CACHE and not doNotUseObjectCache then
		State.ScheduledUpdate = true
	end
	--debug.profileend()
	return part
end
DirtyGroupLogic.InstantiatePart = InstantiatePart



--Destroys a member of a dirty group using the part itself
local function DestroyPart(part : BasePart)
	--debug.profilebegin("DestroyPart")
	local DirtyGroupID = part:GetAttribute(Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME)
	if not DirtyGroupID then return end

	local dirtyGroupData, dirtyGroupMembers = State.DirtyGroupData[DirtyGroupID], State.DirtyGroupMembers[DirtyGroupID]

	local FallingGroupSectionID = part:GetAttribute(Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME)
	if FallingGroupSectionID then
		local FallingGroupID = part:GetAttribute(Settings.FALLING_GROUP_ID_ATTRIBUTE_NAME)
		if State.FallingGroupSectionMembers[FallingGroupID] and State.FallingGroupSectionMembers[FallingGroupID][FallingGroupSectionID] then
			State.FallingGroupSectionMembers[FallingGroupID][FallingGroupSectionID][part] = nil
		end
		if State.FallingGroupPartWeldMap[part] then
			State.FallingGroupPartWeldMap[part]:Destroy()
			State.FallingGroupPartWeldMap[part] = nil
		end
		if dirtyGroupData and part == dirtyGroupData.OriginalPart then
			part:SetAttribute(Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME)
		end
	end

	if dirtyGroupData and part == dirtyGroupData.OriginalPart then
		part.Parent = nil
	else
		if dirtyGroupMembers then
			dirtyGroupMembers[part] = nil
		end

		local puppetID = State.IsPuppet(part)

		if Settings.USE_OBJECT_CACHE and State.CachedParts:IsInUse(part) then
			if not part.Anchored then
				part.Anchored = true
			end

			if puppetID and isServer then
				State.Puppets[puppetID][2]()
			end

			part:ClearAllChildren()

			for _, tag in ipairs(part:GetTags()) do
				part:RemoveTag(tag)
			end

			for k in pairs(part:GetAttributes()) do
				if k:sub(1, 3) == "RBX" then continue end
				part:SetAttribute(k)
			end

			part.CanCollide = false
			State.CachedParts:ReturnPart(part)

			State.ScheduledUpdate = true
		else
			part:Destroy()
		end
	end

	--debug.profileend()
end
DirtyGroupLogic.DestroyPart = DestroyPart



local function PopulateDirtyGroup(Part : Part, DirtyGroupID : string?)
	-- populate the initial dirty group information if there is no group associated with this part
	DirtyGroupID = DirtyGroupID or Serializer.GetCondensedGUID()
	Part:SetAttribute(Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME, DirtyGroupID)

	local GridSize = Part:GetAttribute("GridSize") or Settings.DefaultGridSize

	local roundedGridLength = Vector3.one:Max(Part.Size // GridSize)
	if Settings.StrictGrid then
		roundedGridLength = RoundAxisNearestPowerOf2(roundedGridLength)
	end

	State.DirtyGroupData[DirtyGroupID] = {
		OriginalPart = Part,
		OriginalParent = Part.Parent,

		GridLength = roundedGridLength,
		MaxGridLength = roundedGridLength,
		VoxelSize = Part.Size / roundedGridLength
	}
	State.DirtyGroupMembers[DirtyGroupID] = {}

	if Settings.USE_CLIENT_SERVER and Part:IsA("Part") and Part.Shape == Enum.PartType.Block then
		if GroupHasTag(Part, Settings.BLOCK_CLIENT_SERVER_TAG) then
			Part:AddTag(Settings.BLOCK_CLIENT_SERVER_TAG)
		else
			-- Inheritance of ancestor tags (hierarchy only changes with client server enabled)
			for _, tag in ipairs(AncestorGroupTags(Part)) do
				Part:AddTag(tag)
			end
			-- Put the part into the State.MapContainer (client side is "ClientMap" folder, server side is `workspace.CurrentCamera`)
			Part.Parent = State.MapContainer
		end
	end

	return DirtyGroupID
end
DirtyGroupLogic.PopulateDirtyGroup = PopulateDirtyGroup



local function UndoDirtyGroup(DirtyGroupID : string)
	-- Restore the original part and delete all current members
	local groupData = State.DirtyGroupData[DirtyGroupID]
	local groupMembers = State.DirtyGroupMembers[DirtyGroupID]

	groupData.MaxGridLength = groupData.GridLength

	local OriginalPart = groupData.OriginalPart
	if not Settings.USE_CLIENT_SERVER or not OriginalPart:IsA("Part") or OriginalPart.Shape ~= Enum.PartType.Block or OriginalPart:HasTag(Settings.BLOCK_CLIENT_SERVER_TAG) then
		OriginalPart.Parent = groupData.OriginalParent
	else
		OriginalPart.Parent = State.MapContainer
	end

	local FallingGroupID = OriginalPart:GetAttribute(Settings.FALLING_GROUP_ID_ATTRIBUTE_NAME)
	if FallingGroupID then
		OriginalPart.CFrame = State.FallingDirtyGroupOriginalCFrames[DirtyGroupID]
		OriginalPart:SetAttribute(Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME)
		OriginalPart.Anchored = true
	end

	for member in pairs(groupMembers) do
        DestroyPart(member)
    end
	table.clear(groupMembers)

	State.SmoothCleanupQueue[DirtyGroupID] = nil
end
DirtyGroupLogic.UndoDirtyGroup = UndoDirtyGroup



-- Reset the dirty group to its original state before Shatterbox touched it. Replicated is true only if the client is receiving a message from the server to perform this reset.
local function ResetDirtyGroup(DirtyGroupID : string, replicated : boolean?)
	local groupData = State.DirtyGroupData[DirtyGroupID]
	if not groupData then return end

	local OriginalPart = groupData.OriginalPart
	if replicated then
		OriginalPart:Destroy()
	else
		OriginalPart:SetAttribute(Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME)
		OriginalPart.Parent = groupData.OriginalParent
	end

	for member in pairs(State.DirtyGroupMembers[DirtyGroupID]) do
		DirtyGroupLogic.DestroyPart(member)
	end

	State.DirtyGroupData[DirtyGroupID] = nil
	State.DirtyGroupMembers[DirtyGroupID] = nil
	State.SmoothCleanupQueue[DirtyGroupID] = nil
end
DirtyGroupLogic.ResetDirtyGroup = ResetDirtyGroup



function DirtyGroupLogic.SmoothCleanupHeartbeat(deltaTime : number)
	local toReset = {}

	for DirtyGroupID, countdown in pairs(State.SmoothCleanupQueue) do
		countdown -= deltaTime
		if countdown > 0 then
			State.SmoothCleanupQueue[DirtyGroupID] = countdown
		else
			toReset[DirtyGroupID] = true
		end
	end

	for DirtyGroupID in pairs(toReset) do
		if Settings.BlockCleanupWhileCharacterInside then
            local dirtyGroupData = State.DirtyGroupData[DirtyGroupID]
			local OriginalPart = dirtyGroupData.OriginalPart
			local shouldSkip = false
			for _, plr in ipairs(Players:GetPlayers()) do
				local chr = plr.Character
				if not chr then continue end
				local hrp = chr:FindFirstChild("HumanoidRootPart")
				if not hrp then continue end
				if VertexMath.PartTypeContainsPoint.Block(OriginalPart.CFrame, OriginalPart.Size, hrp.Position) then
					shouldSkip = true
					break
				end
			end
			if shouldSkip then continue end
		end
		UndoDirtyGroup(DirtyGroupID)
	end

	table.clear(toReset)

	for FallingGroupID, countdown in pairs(State.SmoothCleanupFallingQueue) do
		countdown -= deltaTime
		if countdown > 0 then
			State.SmoothCleanupFallingQueue[FallingGroupID] = countdown
		else
			toReset[FallingGroupID] = true
		end
	end

	for FallingGroupID in pairs(toReset) do
		for _, SectionAnchor in pairs(State.FallingGroupSectionAnchors[FallingGroupID]) do
			SectionAnchor:Destroy()
		end
		for DirtyGroupID in pairs(State.FallingGroupDirtyGroups[FallingGroupID]) do
			UndoDirtyGroup(DirtyGroupID)
		end
		table.clear(State.FallingGroupSectionAnchors[FallingGroupID])
		table.clear(State.FallingGroupSectionMembers[FallingGroupID])
	end
end



function DirtyGroupLogic.Heartbeat(deltaTime : number)
	local toDestroy = {}
	for part, countdown in pairs(State.DelayedCleanupQueue) do
		countdown -= deltaTime
		if countdown > 0 then
			State.DelayedCleanupQueue[part] = countdown
		else
			toDestroy[part] = true
		end
	end

	for part in pairs(toDestroy) do
		DestroyPart(part)
		State.DelayedCleanupQueue[part] = nil
	end

	if Settings.UseSmoothCleanup then
		DirtyGroupLogic.SmoothCleanupHeartbeat(deltaTime)
	end
end



return DirtyGroupLogic
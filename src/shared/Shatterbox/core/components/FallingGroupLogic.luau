--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)
--#selene: allow(unused_variable)

local components = script.Parent
local core = components.Parent
local src = core.Parent
local lib = core:WaitForChild("lib")

local Settings = require(src:WaitForChild("Settings"))
local Types = require(src:WaitForChild("Types"))

local Serializer = require(lib:WaitForChild("Serializer"))

local ShatterQueueLogic = require(components:WaitForChild("ShatterQueueLogic"))
local DirtyGroupLogic = require(components:WaitForChild("DirtyGroupLogic"))

local State = require(components.Parent:WaitForChild("State"))


local EPSILON = 1e-3
local SearchSizeOffsets = {
	Vector3.new(1 + EPSILON, 1 - EPSILON, 1 - EPSILON),
	Vector3.new(1 - EPSILON, 1 + EPSILON, 1 - EPSILON),
	Vector3.new(1 - EPSILON, 1 - EPSILON, 1 + EPSILON)
}


local FallingGroupLogic = {}


--[[ Returns the touching parts in a falling chunk or based on the following rules while removing elements from a queue when it runs into them:
	 1. If the startingPoint does not have a FallingGroupSectionID and it has a path to the 'ground', returns parts that have the same FallingGroupID and true
	 2. If the startingPoint does not have a FallingGroupSectionID and it does not have a path to the 'ground', returns parts that have the same FallingGroupID and false
	 3. If the startingPoint has a FallingGroupSectionID, returns parts that have the same FallingGroupSectionID and false
]]
local function FindChunkParts(ToProcessMap : { [BasePart] : boolean }, StartingPart : BasePart, FallingGroupID : string, FallingGroupSectionID : string?) : {BasePart}?

	local SectionMembers, i = {}, 1

	local visited, pathStack = { [StartingPart] = true }, {StartingPart}

	local hasPathToGround = false

	while #pathStack > 0 do
		local currentPart = table.remove(pathStack)
		local c, s = currentPart.CFrame, currentPart.Size

		SectionMembers[i] = currentPart
		i += 1

		for _, SizeOffset in ipairs(SearchSizeOffsets) do
			for _, inAxis in ipairs(workspace:GetPartBoundsInBox(c, s + SizeOffset)) do
				if visited[inAxis] or inAxis == currentPart then continue end
				visited[inAxis] = true
				if ShatterQueueLogic.FindHumanoidAsAncestorChild(inAxis) then continue end

				local inAxisFallingGroupSectionID = inAxis:GetAttribute(Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME)
				local inAxisFallingGroupID = inAxis:GetAttribute(Settings.FALLING_GROUP_ID_ATTRIBUTE_NAME)
				if not FallingGroupSectionID and inAxisFallingGroupSectionID then continue end
				if FallingGroupSectionID and inAxisFallingGroupSectionID ~= FallingGroupSectionID then continue end
				local inAxisIsAFallingGroup = inAxisFallingGroupID or DirtyGroupLogic.GroupHasTag(inAxis, Settings.FALLING_GROUP_TAG)
				if inAxisIsAFallingGroup and inAxisFallingGroupID ~= FallingGroupID then continue end

				ToProcessMap[inAxis] = nil
				if inAxis:HasTag(Settings.DEBRIS_TAG) then continue end

				if not inAxisIsAFallingGroup and not FallingGroupSectionID then
					hasPathToGround = true
					continue
				end

				table.insert(pathStack, inAxis)
			end
		end
	end

	return SectionMembers, hasPathToGround
end



local function PopulateFallingGroupSection(SectionMembers : {BasePart}, FallingGroupID : string, ParentFallingGroupSectionID : string?) : (Part, string)
	local newSectionAnchor = Instance.new("Part")
	newSectionAnchor.Size = Vector3.one
	newSectionAnchor.Transparency = 1
	newSectionAnchor.CanCollide = false
	newSectionAnchor.CanQuery = false
	newSectionAnchor.Massless = true

	if ParentFallingGroupSectionID then
		local PrevSectionAnchor = State.FallingGroupSectionAnchors[FallingGroupID][ParentFallingGroupSectionID]
		newSectionAnchor.AssemblyLinearVelocity = PrevSectionAnchor.AssemblyLinearVelocity
		newSectionAnchor.AssemblyAngularVelocity = PrevSectionAnchor.AssemblyAngularVelocity
		newSectionAnchor.CFrame = PrevSectionAnchor.CFrame
	else
		newSectionAnchor.CFrame = State.FallingGroupOriginalAnchorCFrames[FallingGroupID]
	end

	local newSectionMembersMap =  {}
	local newSectionID = Serializer.GetCondensedGUID()
	State.FallingGroupSectionMembers[FallingGroupID][newSectionID] = newSectionMembersMap

	for _, Part in ipairs(SectionMembers) do
		local weld = Instance.new("Weld")
		weld.C0 = newSectionAnchor.CFrame:Inverse()
		weld.C1 = Part.CFrame:Inverse()
		weld.Part0 = newSectionAnchor
		weld.Part1 = Part
		weld.Parent = newSectionAnchor

		newSectionMembersMap[Part] = true
		Part:SetAttribute(Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME, newSectionID)

		if State.FallingGroupPartWeldMap[Part] then
			State.FallingGroupPartWeldMap[Part]:Destroy()
		end
		State.FallingGroupPartWeldMap[Part] = weld

		Part.Anchored = false
	end

	State.FallingGroupSectionAnchors[FallingGroupID][newSectionID] = newSectionAnchor

	newSectionAnchor.Parent = workspace
	return newSectionAnchor, newSectionID
end



function FallingGroupLogic.Heartbeat()
	if not next(State.ChangedDirtyGroups) then return end

	-- [FallingGroupID] : {BasePart}
	local FallingGroupMembersToProcess = {} :: { [string] : { [BasePart] : boolean } }

	for DirtyGroupID in pairs(State.ChangedDirtyGroups) do
		local OriginalPart = State.DirtyGroupData[DirtyGroupID].OriginalPart
		local FallingGroupID = OriginalPart:GetAttribute(Settings.FALLING_GROUP_ID_ATTRIBUTE_NAME)
		if not FallingGroupID then continue end

		local ToProcess = FallingGroupMembersToProcess[FallingGroupID]
		if not ToProcess then
			ToProcess = {}
			FallingGroupMembersToProcess[FallingGroupID] = ToProcess
		end

		for member in pairs(State.DirtyGroupMembers[DirtyGroupID]) do
			local FallingGroupSectionID = member:GetAttribute(Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME)
			if FallingGroupSectionID then
				for sectionMember in pairs(State.FallingGroupSectionMembers[FallingGroupID][FallingGroupSectionID]) do
					ToProcess[sectionMember] = true
				end
			else
				ToProcess[member] = true
			end
		end
	end

	table.clear(State.ChangedFallingGroupSections)

	if not next(FallingGroupMembersToProcess) then return end

	for FallingGroupID, ToProcess in pairs(FallingGroupMembersToProcess) do
		-- [FallingGroupSectionID] : { {BasePart} }     -- Represents a section becoming modified, either by splitting into multiple new sections, having parts added/removed from it, or both.
		local UpdatedSections = {} :: { [string] : { {BasePart} } }
		local NewSections = {} :: { {BasePart} }

		if not next(ToProcess) then continue end

		while next(ToProcess) do
			local StartingPart = next(ToProcess)
			ToProcess[StartingPart] = nil
			local FallingGroupSectionID = StartingPart:GetAttribute(Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME)

			local SectionMembers, hasPathToGround = FindChunkParts(ToProcess, StartingPart, FallingGroupID, FallingGroupSectionID)
			if hasPathToGround then continue end

			local tbl = NewSections
			if FallingGroupSectionID then
				local UpdateArray = UpdatedSections[FallingGroupSectionID]
				if not UpdateArray then
					UpdateArray = {}
					UpdatedSections[FallingGroupSectionID] = UpdateArray
				end
				tbl = UpdateArray
			end
			table.insert(tbl, SectionMembers)
		end

		for FallingGroupSectionID, UpdateArray in pairs(UpdatedSections) do
			local maxIndex, maxMemberCount = 1, 0
			for i, SectionMembers in ipairs(UpdateArray) do
				if #SectionMembers <= maxMemberCount then continue end
				maxIndex, maxMemberCount = i, #SectionMembers
			end
			for i, SectionMembers in ipairs(UpdateArray) do
				if i == maxIndex then continue end
				PopulateFallingGroupSection(SectionMembers, FallingGroupID, FallingGroupSectionID)
			end

			local SectionMembers = UpdateArray[maxIndex]
			local toRemove = {}
			for member in pairs(State.FallingGroupSectionMembers[FallingGroupID][FallingGroupSectionID]) do
				if table.find(SectionMembers, member) then continue end
				toRemove[member] = true
			end
			for member in pairs(toRemove) do
				State.FallingGroupSectionMembers[FallingGroupID][FallingGroupSectionID][member] = nil
			end

			for _, member in ipairs(SectionMembers) do
				if State.FallingGroupPartWeldMap[member] then continue end

				local SectionAnchor = State.FallingGroupSectionAnchors[FallingGroupID][FallingGroupSectionID]
				local weld = Instance.new("Weld")
				weld.C0 = SectionAnchor.CFrame:Inverse()
				weld.C1 = member.CFrame:Inverse()
				weld.Part0 = SectionAnchor
				weld.Part1 = member
				weld.Parent = SectionAnchor

				State.FallingGroupPartWeldMap[member] = weld

				member.Anchored = false
			end
		end

		for _, SectionMembers in ipairs(NewSections) do
			PopulateFallingGroupSection(SectionMembers, FallingGroupID)
		end
	end
end



return FallingGroupLogic
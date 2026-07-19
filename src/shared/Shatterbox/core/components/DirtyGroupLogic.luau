--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local isServer = RunService:IsServer()

local core = script.Parent.Parent
local lib = core:WaitForChild("lib")
local src = core.Parent

--local Types = require(src:WaitForChild("Types"))

local Settings = require(src:WaitForChild("Settings"))
local USE_CLIENT_SERVER = Settings.USE_CLIENT_SERVER
local USE_OBJECT_CACHE = Settings.USE_OBJECT_CACHE

local DirtyGroupIDAttribute = Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME

local VertexMath = require(lib:WaitForChild("VertexMath"))
local BlockContainsPoint = VertexMath.PartTypeContainsPoint.Block

local PartOperations = require(lib:WaitForChild("PartOperations"))
local PartFromTemplate = PartOperations.PartFromTemplate

local State = require(core:WaitForChild("State"))
local IsPuppet = State.IsPuppet

local CachedParts = State.CachedParts

local mapContainer = State.MapContainer

local DirtyGroupData = State.DirtyGroupData
local DirtyGroupMembers = State.DirtyGroupMembers

local SmoothCleanupQueue = State.SmoothCleanupQueue

local Puppets = State.Puppets




local function GetCondensedGUID()
	return string.gsub(HttpService:GenerateGUID(false), '-', '')
end

local function RoundToNearestPowerOf2(x : number)
	local _, ceilLogged = math.frexp(x)
	local l, h = math.ldexp(1, ceilLogged - 1), math.ldexp(1, ceilLogged)
	return x - l < h - x and l or h
end

-- Returns the first occurance of an ancestor that is a Folder or a Model
local function FindFirstAncestorGroup(i : Instance) : (Folder|Model)?
	local Ancestor = i.Parent

	while Ancestor and not (Ancestor:IsA("Folder") or Ancestor:IsA("Model")) do
        Ancestor = Ancestor.Parent
    end

	return Ancestor
end

-- Returns all of the tags of every ancestor group instance (folder/model) as an array
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



local DirtyGroupLogic = {}

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
local function InstantiatePart(DirtyGroupID, cframe, size, doNotUseObjectCache)
	--debug.profilebegin("InstantiatePart")
	local dirtyGroupData, dirtyGroupMembers = DirtyGroupData[DirtyGroupID], DirtyGroupMembers[DirtyGroupID]

	local part = PartFromTemplate(dirtyGroupData.OriginalPart, cframe, not doNotUseObjectCache and CachedParts)
	part.Size = size

	local partIsDivisible = part:IsA("Part") and part.Shape == Enum.PartType.Block

	if not USE_CLIENT_SERVER or not partIsDivisible then
		part.Parent = dirtyGroupData.OriginalParent
	else
		part.Parent = mapContainer
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

	if USE_OBJECT_CACHE then
		State.ScheduledUpdate = true
	end
	--debug.profileend()
	return part
end
DirtyGroupLogic.InstantiatePart = InstantiatePart



--Destroys a member of a dirty group using the part itself
local function DestroyPart(part : BasePart)
	--debug.profilebegin("DestroyPart")
	local DirtyGroupID = part:GetAttribute(DirtyGroupIDAttribute)
	if not DirtyGroupID then return end

	local dirtyGroupData, dirtyGroupMembers = DirtyGroupData[DirtyGroupID], DirtyGroupMembers[DirtyGroupID]

	if dirtyGroupData and part == dirtyGroupData.OriginalPart then
		part.Parent = nil
	else
		if dirtyGroupMembers then
			dirtyGroupMembers[part] = nil
		end

		local puppetID = IsPuppet(part)

		if USE_OBJECT_CACHE and CachedParts:IsInUse(part) then
			if not part.Anchored then
				part.Anchored = true
			end

			if puppetID and isServer then
				Puppets[puppetID][2]()
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
			CachedParts:ReturnPart(part)

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
	DirtyGroupID = DirtyGroupID or GetCondensedGUID()
	Part:SetAttribute(DirtyGroupIDAttribute, DirtyGroupID)

	local GridSize = Part:GetAttribute("GridSize") or Settings.DefaultGridSize

	local roundedGridLength = RoundAxisNearestPowerOf2(Vector3.one:Max(Part.Size // GridSize))

	DirtyGroupData[DirtyGroupID] = {
		OriginalPart = Part,
		OriginalParent = Part.Parent,

		GridLength = roundedGridLength,
		MaxGridLength = roundedGridLength,
		VoxelSize = Part.Size / roundedGridLength
	}
	DirtyGroupMembers[DirtyGroupID] = {}

	if USE_CLIENT_SERVER and Part:IsA("Part") and Part.Shape == Enum.PartType.Block then
		-- Inheritance of ancestor tags (hierarchy only changes with client server enabled)
		for _, tag in ipairs(AncestorGroupTags(Part)) do
            Part:AddTag(tag)
        end
		-- Put the part into the mapContainer (client side is "ClientMap" folder, server side is `workspace.CurrentCamera`)
		Part.Parent = mapContainer
	end

	return DirtyGroupID
end
DirtyGroupLogic.PopulateDirtyGroup = PopulateDirtyGroup



-- Undoes the given destruction identified by it's DestructionID. `replicated` is true only if the server is telling a client to undo a destruction
local function UndoDirtyGroup(DirtyGroupID : string)
	-- Restore the original part and delete all current members
	local groupData = DirtyGroupData[DirtyGroupID]
	local groupMembers = DirtyGroupMembers[DirtyGroupID]

	groupData.MaxGridLength = groupData.GridLength

	local OriginalPart = groupData.OriginalPart
	if not USE_CLIENT_SERVER or not OriginalPart:IsA("Part") or OriginalPart.Shape ~= Enum.PartType.Block then
		OriginalPart.Parent = groupData.OriginalParent
	else
		OriginalPart.Parent = mapContainer
	end

	for member in pairs(groupMembers) do
        DestroyPart(member)
    end
	table.clear(groupMembers)

	SmoothCleanupQueue[DirtyGroupID] = nil
end
DirtyGroupLogic.UndoDirtyGroup = UndoDirtyGroup



function DirtyGroupLogic.SmoothCleanupHeartbeatBehavior(deltaTime : number)
	local toReset = {}

	for DirtyGroupID, countdown in pairs(SmoothCleanupQueue) do
		countdown -= deltaTime
		if countdown > 0 then
			SmoothCleanupQueue[DirtyGroupID] = countdown
		else
			toReset[DirtyGroupID] = true
		end
	end

	for DirtyGroupID in pairs(toReset) do
		if Settings.BlockCleanupWhileCharacterInside then
            local dirtyGroupData = DirtyGroupData[DirtyGroupID]
			local OriginalPart = dirtyGroupData.OriginalPart
			local shouldSkip = false
			for _, plr in ipairs(Players:GetPlayers()) do
				local chr = plr.Character
				if not chr then continue end
				local hrp = chr:FindFirstChild("HumanoidRootPart")
				if not hrp then continue end
				if BlockContainsPoint(OriginalPart.CFrame, OriginalPart.Size, hrp.Position) then
					shouldSkip = true
					break
				end
			end
			if shouldSkip then continue end
		end
		UndoDirtyGroup(DirtyGroupID)
	end
end



return DirtyGroupLogic
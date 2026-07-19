--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)
--#selene: allow(unused_variable)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local components = script.Parent
local core = components.Parent
local src = core.Parent
local lib = core:WaitForChild("lib")

local Types = require(src:WaitForChild("Types"))

local Settings = require(src:WaitForChild("Settings"))
local DebrisTag = Settings.DEBRIS_TAG

local DirtyGroupLogic = require(components:WaitForChild("DirtyGroupLogic"))
local PopulateDirtyGroup = DirtyGroupLogic.PopulateDirtyGroup

local ShatterQueueLogic = require(components:WaitForChild("ShatterQueueLogic"))
local ImaginaryVoxels = ShatterQueueLogic.ImaginaryVoxels

local PuppeteerLogic = require(components:WaitForChild("PuppeteerLogic"))
local DeserializedPuppet = PuppeteerLogic.DeserializedPuppet

local PartOperations = require(lib:WaitForChild("PartOperations"))
local SerializedPartInstance = PartOperations.SerializedPartInstance
local DeserializedPartInstance = PartOperations.DeserializedPartInstance
local PartFromTemplate = PartOperations.PartFromTemplate

local Serializer = require(lib:WaitForChild("Serializer"))
local SerializedDestructionParams = Serializer.SerializedDestructionParams
local DeserializedDestructionParams = Serializer.DeserializedDestructionParams

local State = require(components.Parent:WaitForChild("State"))
local mapContainer = State.MapContainer

local CachedParts = State.CachedParts

local Blink = State.Blink
local StepReplication = Blink.StepReplication

local DirtyGroupData = State.DirtyGroupData
local DirtyGroupMembers = State.DirtyGroupMembers

local ShatterQueue = State.ShatterQueue

local SmoothCleanupQueue = State.SmoothCleanupQueue

local Puppets = State.Puppets

local NewPlayerStateReplicationQueue = State.NewPlayerStateReplicationQueue


type DestructionTypes = ("IMAGINARY"|"DEFAULT")


local ClientServerLogic = {}


-- Creates all of the original map parts associated with a destruction for the clients.
-- This allows the clients to process their own destructions alongside the server.
local function CreateSerialDirtyGroups(SerialDirtyGroups)
	for DirtyGroupID, serialDirtyGroupData in pairs(SerialDirtyGroups) do
		local serialOriginal = serialDirtyGroupData.OriginalPart
		local newPart = DeserializedPartInstance(serialOriginal)
		newPart.Parent = mapContainer

		local GridLength = serialDirtyGroupData.GridLength

		DirtyGroupData[DirtyGroupID] = {
			OriginalPart = newPart,
			OriginalParent = mapContainer,
			GridLength = GridLength,
			MaxGridLength = serialDirtyGroupData.MaxGridLength,
			VoxelSize = serialOriginal.Size / GridLength,
		}
		DirtyGroupMembers[DirtyGroupID] = {}
	end
end
ClientServerLogic.CreateSerialDirtyGroups = CreateSerialDirtyGroups



-- Creates dirty groups for the server and every player except "plr"
local function CreateDirtyGroupsFromClient(plr, DirtyGroups)
	local SerialDirtyGroups = {}
	for DirtyGroupID, part in pairs(DirtyGroups) do
		PopulateDirtyGroup(part, DirtyGroupID)
		SerialDirtyGroups[DirtyGroupID] = SerializedPartInstance(part)
	end

	Blink.CreateDirtyGroupsFromServer.FireExcept(plr, SerialDirtyGroups)
end
ClientServerLogic.CreateDirtyGroupsFromClient = CreateDirtyGroupsFromClient

local function SendDirtyGroupsToServer(DirtyGroups)
	if not next(DirtyGroups) then return end

	local ToSendToServer = {}
	for DirtyGroupID in pairs(DirtyGroups) do
		local groupData = DirtyGroupData[DirtyGroupID]
		local PartToSend = groupData.OriginalPart
		local newClientPart = PartFromTemplate(PartToSend, PartToSend.CFrame)
		groupData.OriginalPart = newClientPart
		PartToSend.Parent = nil
		newClientPart.Parent = mapContainer
		ToSendToServer[DirtyGroupID] = PartToSend
	end
	Blink.CreateDirtyGroupsFromClient.Fire(ToSendToServer)
	StepReplication()
end
ClientServerLogic.SendDirtyGroupsToServer = SendDirtyGroupsToServer



local function ReplicateDestructionToClients(destructionType : DestructionTypes, destructionParams : Types.DestructionParams, createdDirtyGroups : { [string] : boolean }, skipClientWaiting : boolean?)

	local serialNewDirtyGroups = {}
	for DirtyGroupID in pairs(createdDirtyGroups) do
		local dirtyGroupData = DirtyGroupData[DirtyGroupID]
		serialNewDirtyGroups[DirtyGroupID] = {
			OriginalPart = SerializedPartInstance(DirtyGroupData[DirtyGroupID].OriginalPart),
			GridLength = dirtyGroupData.GridLength,
			MaxGridLength = dirtyGroupData.MaxGridLength
		}
	end

	local PlayerList = Players:GetPlayers()
	local exclusions = destructionParams.ExcludePlayersReplication
	if #exclusions > 0 then
		for _, plr in ipairs(exclusions) do
			local found = table.find(PlayerList, plr)
			if found then
				table.remove(PlayerList, found)
			end
		end

		if #PlayerList == 0 then return end

		Blink.ReplicateDestruction.FireList(PlayerList, destructionType, SerializedDestructionParams(destructionParams), serialNewDirtyGroups)
	else
		Blink.ReplicateDestruction.FireAll(destructionType, SerializedDestructionParams(destructionParams), serialNewDirtyGroups)
	end

	if not destructionParams.WaitForClientTimeout or destructionType == "IMAGINARY" then return end

	local disconnect
	disconnect = Blink.ClientRecievedMapParts.On(function(fromPlr, DestructionID)
		if destructionParams.ID ~= DestructionID then return end
		local found = table.find(PlayerList, fromPlr)
		if found then
			table.remove(PlayerList, found)
		end
	end)
	local elapsed = 0
	local waitingOnPlayersConnection
	waitingOnPlayersConnection = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed >= destructionParams.WaitForClientTimeout or #PlayerList == 0 then
			waitingOnPlayersConnection:Disconnect()
			waitingOnPlayersConnection = nil
			disconnect()
		end
	end)
	while waitingOnPlayersConnection do
		RunService.Heartbeat:Wait()
	end
end
ClientServerLogic.ReplicateDestructionToClients = ReplicateDestructionToClients

local function ReplicateDestructionFromServer(destructionType, serialParams, serialNewDirtyGroups)

	local destructionParams = DeserializedDestructionParams(serialParams)

	CreateSerialDirtyGroups(serialNewDirtyGroups)

	if destructionType == "IMAGINARY" then
		destructionParams.SkipEncapsulatedVoxels = true
		RunService.Heartbeat:Wait()
		ImaginaryVoxels(destructionParams)

	elseif destructionType == "DEFAULT" then
		if destructionParams.WaitForClientTimeout and destructionParams.WaitForClientTimeout > 0 then
			Blink.ClientRecievedMapParts.Fire(destructionParams.ID)
		end

		table.insert(ShatterQueue, destructionParams)
	end
end
ClientServerLogic.ReplicateDestructionFromServer = ReplicateDestructionFromServer



local function ReplicateStateToPlayer(plr)

	local serialDirtyGroupData = {}
	for DirtyGroupID, groupData in pairs(DirtyGroupData) do
		local OriginalPart = groupData.OriginalPart

		if OriginalPart:IsA("Part") and OriginalPart.Shape == Enum.PartType.Block then
			-- only send the original part because OriginalParent doesn't matter in this case and GridSize can be derived
			serialDirtyGroupData[DirtyGroupID] = {
				OriginalPart = SerializedPartInstance(OriginalPart),
				GridLength = groupData.GridLength,
				MaxGridLength = groupData.MaxGridLength
			}
		end
	end

	local serialDirtyGroupMembers, destroyedDirtyGroups = {}, {}
	for DirtyGroupID in pairs(serialDirtyGroupData) do
		local groupMembers = DirtyGroupMembers[DirtyGroupID]

		local OriginalPart = DirtyGroupData[DirtyGroupID].OriginalPart

		local serialMembers = {}
		serialDirtyGroupMembers[DirtyGroupID] = serialMembers

		if next(groupMembers) then
			for member in pairs(groupMembers) do
				if member:HasTag(DebrisTag) then
					local found = false
					for _, puppetData in pairs(Puppets) do
						if puppetData[1] == member then
							found = true
							break
						end
					end
					if found then continue end
				end
				table.insert(serialMembers, SerializedPartInstance(member))
			end
		elseif not OriginalPart.Parent then
			destroyedDirtyGroups[DirtyGroupID] = true
		end
	end

	local serialPuppets = {}
	for puppetID, puppetData in pairs(Puppets) do
		serialPuppets[puppetID] = SerializedPartInstance(puppetData[1])
	end

	Blink.ReplicateState.Fire(plr,
		serialDirtyGroupData,
		serialDirtyGroupMembers,
		destroyedDirtyGroups,

		SmoothCleanupQueue,

		serialPuppets,
		State.PuppetNextIndex
	)
end
ClientServerLogic.ReplicateStateToPlayer = ReplicateStateToPlayer

local function ReplicateStateFromServer(serialDirtyGroupData, serialDirtyGroupMembers, destroyedDirtyGroups, serverSmoothCleanupQueue, serialPuppets, serverPuppetsNextIndex)

	for DirtyGroupID, serializedData in pairs(serialDirtyGroupData) do
		local serialOriginal = serializedData.OriginalPart
		local GridLength = serializedData.GridLength
		DirtyGroupData[DirtyGroupID] = {
			OriginalPart = DeserializedPartInstance(serialOriginal),
			OriginalParent = mapContainer,
			GridLength = GridLength,
			VoxelSize = serialOriginal.Size / GridLength,
			MaxGridLength = serializedData.MaxGridLength
		}
	end

	for DirtyGroupID, serialGroupMembers in pairs(serialDirtyGroupMembers) do
		local groupMembers = {}
		DirtyGroupMembers[DirtyGroupID] = groupMembers

		if destroyedDirtyGroups[DirtyGroupID] then continue end

		if #serialGroupMembers == 0 then
			DirtyGroupData[DirtyGroupID].OriginalPart.Parent = mapContainer
			continue
		end

		for _, serialMember in ipairs(serialGroupMembers) do
			local part = DeserializedPartInstance(serialMember, CachedParts)
			if not part.Parent then
				part.Parent = mapContainer
			end
			groupMembers[part] = true
		end
	end

	for DirtyGroupID, cleanupTime in pairs(serverSmoothCleanupQueue) do
		SmoothCleanupQueue[DirtyGroupID] = cleanupTime
	end

	State.PuppetNextIndex = serverPuppetsNextIndex
	for puppetID, serialPuppet in pairs(serialPuppets) do
		Puppets[puppetID] = { DeserializedPuppet(serialPuppet) }
	end

	State.ClientInitComplete = true
end
ClientServerLogic.ReplicateStateFromServer = ReplicateStateFromServer



local function QueueNewPlayerStateReplication(plr)
	table.insert(NewPlayerStateReplicationQueue, plr)
end
ClientServerLogic.QueueNewPlayerStateReplication = QueueNewPlayerStateReplication



return ClientServerLogic
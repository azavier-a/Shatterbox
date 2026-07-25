--!native
--!optimize 2

local core = script.Parent
local lib = core:WaitForChild("lib")
local src = core.Parent

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local isServer, isClient = RunService:IsServer(), RunService:IsClient()

local Settings = require(src:WaitForChild("Settings"))
local Types = require(src:WaitForChild("Types"))


local Blink, mapContainer, effectsModuleCallbacks
if isServer then
	Blink = require(core.Blink.Server)

	mapContainer = workspace.CurrentCamera

	effectsModuleCallbacks = require(src.effects.Server)
elseif isClient then
	Blink = require(core:WaitForChild("Blink"):WaitForChild("Client"))

	mapContainer = workspace:FindFirstChild("ClientMap")
	if not mapContainer then
		mapContainer = Instance.new("Folder")
		mapContainer.Parent = workspace
		mapContainer.Name = "ClientMap"
	end

	effectsModuleCallbacks = require(src:WaitForChild("effects"):WaitForChild("Client"))
end



local LoweredDictMT = {}
LoweredDictMT.__index = function(tbl, k)
	return (k and rawget(tbl, k:lower()))
end
LoweredDictMT.__newindex = function(tbl, k, v)
	rawset(tbl, k:lower(), v)
end

local OnVoxelDestructRegistry = setmetatable({}, LoweredDictMT) :: { [string] : Types.OnVoxelDestruct }
for name, func in pairs(effectsModuleCallbacks.OnVoxelDestruct) do
	OnVoxelDestructRegistry[name:lower()] = func
end

local OnDestructCompletedRegistry = setmetatable({}, LoweredDictMT) :: { [string] : Types.OnDestructCompleted }
for name, func in pairs(effectsModuleCallbacks.OnDestructCompleted) do
	OnDestructCompletedRegistry[name:lower()] = func
end



local ObjectCache, CachedParts
if Settings.USE_OBJECT_CACHE then

	local TemplatePart = Instance.new("Part")
	TemplatePart.Anchored = true
	TemplatePart.CanCollide = false

	ObjectCache = require(lib:WaitForChild("ObjectCache"))

	local cacheContainer = mapContainer

	CachedParts = ObjectCache.new(TemplatePart, Settings.CACHE_INITIAL_SIZE, cacheContainer)
end



local State = {}

State.Blink = Blink

State.EffectsModuleCallbacks = effectsModuleCallbacks
State.OnVoxelDestructRegistry = OnVoxelDestructRegistry
State.OnDestructCompletedRegistry = OnDestructCompletedRegistry

State.MapContainer = mapContainer

State.CachedParts = CachedParts


--[[ Contains information about each dirty group, indexed with DirtyGroupID:
	 * OriginalPart is the original part before any destruction took place. This part is never destroyed, just has its parent set to `nil`
	 * OriginalParent is the original parent of the OriginalPart before any destruction took place. This is used in the client-server algorithm
	 * GridSize is the GridSize attribute of the OriginalPart if it has one supplied
]]
State.DirtyGroupData = {} :: {
	[string] : {
		OriginalPart : Part,
		OriginalParent : Instance,
		GridSize : number
	}
}

-- Contains dynamic maps of dirty group members indexed with DirtyGroupID
State.DirtyGroupMembers = {} :: { [string] : { [Part] : boolean } }

-- Smooth cleanup map [DirtyGroupID] : secondsUntilCleanup
State.SmoothCleanupQueue = {} :: { [string] : number }

-- Smooth clenaup map for falling groups [FallingGroupID] : secondsUntilCleanup
State.SmoothCleanupFallingQueue = {} :: { [string] : number }

-- Delayed cleanup map [Part] : secondsUntilCleanup
State.DelayedCleanupQueue = {}


State.GreedyMeshedImaginaryParts = {} :: { Types.ImaginaryBox }
State.ImaginaryCreateQueue = {} :: { Types.ImaginaryBox }
State.ImaginaryDestroyQueue = {} :: { [Part] : boolean }


-- Ongoing operations array
State.ShatterQueue = {} :: { Types.DestructionParams }


-- Elements of the Puppets array are of the form {Part, boolean} where the Part is the puppet master/slave (server side master, client side slave) and the boolean is whether or not that puppet is getting interpolated.
local Puppets = {}
State.Puppets = Puppets
-- A queue of parts waiting to replicate to each client as Puppets.
local CreatePuppetQueue = {}
State.CreatePuppetQueue = CreatePuppetQueue
-- Index that increments every time a puppet is created if the Puppets array is full, and loops back to 1 when the maximum puppet count is reached.
-- When this happens, the oldest puppets are destroyed as new ones spawn in
State.PuppetNextIndex = 1
-- Stores the interpolation start/end for the corresponding element of the Puppets array. On the server side this is the state replication queue
local PuppetsLerpData = {}
State.PuppetsLerpData = PuppetsLerpData
-- How many replication steps the client thinks it will take for a single puppet to recieve its next update.
State.ClientPuppetStepDelta = 1
-- Which puppet is next in line to recieve a CFrame update.
State.PuppetNextReplicationIndex = 1
-- accumulation variable to manage the puppeteer loop
State.PuppetTimeAccumulation = 0
-- WIP Fake client puppets
State.FakePuppetOverrideIndex = 1


-- [DirtyGroupID] : boolean
State.ChangedDirtyGroups = {} :: { [string] : boolean }

-- [FallingGroupSectionID] : boolean
State.ChangedFallingGroupSections = {} :: { [string] : boolean }

-- [DirtyGroupID] : CFrame
State.FallingDirtyGroupOriginalCFrames = {} :: { [string] : CFrame }

-- [FallingGroupID] : CFrame
State.FallingGroupOriginalAnchorCFrames = {} :: { [string] : CFrame }

-- [DirtyGroupID] : CFrame
State.FallingDirtyGroupMinCornerLocalToAnchor = {} :: { [string] : CFrame }

-- [FallingGroupID] : { [FallingGroupSectionID] : Part }
State.FallingGroupSectionAnchors = {} :: { [string] : { [string] : Part } }

-- [FallingGroupID] : { [FallingGroupSectionID] : { [BasePart] : boolean } }
State.FallingGroupSectionMembers = {} :: { [string] : { [string] : { [BasePart] : boolean } } }

-- [FallingGroupID] : { [DirtyGroupID] : boolean }
State.FallingGroupDirtyGroups = {} :: { [string] : { [string] : boolean } }

State.FallingGroupPartWeldMap = {} :: { [BasePart] : Weld }


local PreAllocated = {}
State.PreAllocated = PreAllocated
-- Pre-allocated OverlapParams used when FilterTagged is supplied
local overlapParams = OverlapParams.new()
PreAllocated.OverlapParams = overlapParams
-- Pre-allocated RaycastParams when SkipWalls or SkipFloors is enabled
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
PreAllocated.RaycastParams = raycastParams
-- pre-allocated part instance which is used to get the parts whenever `GetPartsInPart` is needed
PreAllocated.IntersectingPart = Instance.new("Part")


State.NewPlayerStateReplicationQueue = {} :: {Player}


-- flag used to pause replicating events until the server has replicated it's state
State.ClientInitComplete = false


-- boolean used to determine whether or not to update the cache (I have modified ObjectCache to manually do these calls)
State.ScheduledUpdate = false

-- boolean used to ensure a new ShatterboxHeartbeatCycle doesn't start before an old one can finish
State.IsProcessing = false



function State.IsPuppet(instance : Instance) : number?
	local found
	for i, puppetData in pairs(Puppets) do
		if puppetData[1] == instance then
			found = i
			break
		end
	end
	return found
end



-- returns OverlapParams including all instances with the given tags.
function State.OverlapParamsOfTagged(tags : { string }) : OverlapParams
	local arr

	if #tags == 1 then
		arr = CollectionService:GetTagged(tags[1])
	else
		arr = {}
		for _, tag in ipairs(tags) do
			local taggedArray = CollectionService:GetTagged(tag)
			table.move(taggedArray, 1, #taggedArray, #arr + 1, arr)
		end
	end

	overlapParams.IncludeInstances = arr

	return overlapParams
end



return State
--!native
--!optimize 2

--#selene: allow(unused_variable)

--[=[
	@class Settings

	Contains all configurable module settings.

	:::warning
	Settings that have all-caps names cannot be changed at runtime.
	:::
]=]
local Settings = {}


Settings.INDESTRUCTIBLE_TAG = "Indestructible"

Settings.DEBRIS_TAG = "ShatterboxDebris"

Settings.FALLING_GROUP_TAG = "FallingGroup"

Settings.BLOCK_CLIENT_SERVER_TAG = "BlockClientServer"


Settings.DIRTY_GROUP_ID_ATTRIBUTE_NAME = "DirtyGroupID"

Settings.FALLING_GROUP_ID_ATTRIBUTE_NAME = "FallingGroupID"

Settings.FALLING_GROUP_SECTION_ID_ATTRIBUTE_NAME = "FallingGroupSectionID"
--Settings.ROOT_TAG = "Root"


--[=[
	Set this to false if you don't want to use client-server functionality (false = fully server side destructions).

	@prop USE_CLIENT_SERVER boolean
	@within Settings
	@readonly
]=]
Settings.USE_CLIENT_SERVER = true


--[=[
	Set this to false if you don't want to use ObjectCache.

	:::danger
	If you have ObjectCache enabled, you **must** use [Shatterbox.Cleanup] to destroy map parts and voxels created by this library.
	:::
	@prop USE_OBJECT_CACHE boolean
	@within Settings
	@readonly
]=]
Settings.USE_OBJECT_CACHE = false
	--[=[
		The initial size of the ObjectCache.

		@prop CACHE_INITIAL_SIZE number
		@within Settings
		@readonly
	]=]
	Settings.CACHE_INITIAL_SIZE = 5000


--[=[
	A function that you can use to skip instances with code. Return true to skip the instance "i".

	@tag PartDivision
]=]
function Settings.SkipInstanceCheck(i : Instance) : boolean

	-- return true if you want to skip the instance "i"

	return false
end

--[=[
	The default GridSize to use if none is provided through a GridSize number attribute.

	:::tip
	It is reccomended to set the GridSize property on parts according to their size so that your performance is the most consistent.

	Larger parts should have larger GridSize, especially when using Greedy Meshing.
	:::
	@prop DefaultGridSize number
	@within Settings
	@tag PartDivision
]=]
Settings.DefaultGridSize = 1

--[=[
	Whether or not to use [Greedy Meshing](https://devforum.roblox.com/t/consume-everything-how-greedy-meshing-works/452717).

	:::note
	Keep in mind that Greedy Meshing is an O(n^3) algorithm, so designing your map for voxel destruction is critical.
	:::
	@prop UseGreedyMeshing boolean
	@within Settings
	@tag PartDivision
]=]
Settings.UseGreedyMeshing = true

--[=[
	Whether or not to enforce a strict grid for destructible parts. This is required for Greedy Meshing to work alongside a changing [DestructionParams.GridSize].

	If true, all destructible parts are forced to have a Total Grid Length snapped to the nearest power of 2.

	For example, a destructible part may be 1 voxel long, 2 voxels long, 4 voxels long, 8 voxels long, ect.

	We are not talking about the size of the voxels themselves, but the number of voxels that fit along the length of the part.

	This means the size of voxels on an axis is restricted to the original part size on that axis divided by a power of 2.

	:::danger
	This setting MUST be true if you want Greedy Meshing to work with dynamic grid sizes.

	If you want to use Greedy Meshing without a strict grid, you cannot use [DestructionParams.GridSize] and you must make sure each part only has a single grid size applied to it (either by using GridSize number attribute or by using the DefaultGridSize setting).
	:::
	@prop StrictGrid boolean
	@within Settings
	@tag PartDivision
]=]
Settings.StrictGrid = true

--[=[
	What happens to destructible parts that cannot be divided by Shatterbox.

	@prop NonDivisibleInteraction "FALL"|"DESTROY"|"NONE"
	@within Settings
	@tag PartDivision
]=]
Settings.NonDivisibleInteraction = "FALL" :: "FALL"|"DESTROY"|"NONE" -- What happens to destructible parts that cannot be divided by Shatterbox






--[=[
	If false, the CleanupDelay will be ignored and no smooth cleanups will happen at all.

	@prop UseSmoothCleanup boolean
	@within Settings
	@tag SmoothCleanup
]=]
Settings.UseSmoothCleanup = true

--[=[
	If true, the smooth cleanup of a part will be blocked while the HumanoidRootPart of any Player is inside of the part.

	@prop BlockCleanupWhileCharacterInside boolean
	@within Settings
	@tag SmoothCleanup
]=]
Settings.BlockCleanupWhileCharacterInside = true

--[=[
	The default smooth cleanup delay if none is provided.

	:::tip
	Setting the CleanupDelay to 0 or a negative number disables smooth cleanup for that destruction.

	So you can set this to 0 to make smooth cleanups opt-in per destruction.
	:::
	@prop DefaultSmoothCleanupDelay number
	@within Settings
	@tag SmoothCleanup
]=]
Settings.DefaultSmoothCleanupDelay = 60




-- Puppet voxel settings
--[=[
	The maximum number of puppets allowed in existence before old ones start getting replaced by new ones.

	:::danger
	This setting has a hard cap of 8191.
	:::
	@prop PuppetMaxCount number
	@within Settings
	@tag Puppeteer
]=]
Settings.PuppetMaxCount = 8191

--[=[
	How slow a puppet has to be moving to not get replicated (and eventually become anchored)

	@prop PuppetSleepVelocity number
	@within Settings
	@tag Puppeteer
]=]
Settings.PuppetSleepVelocity = 0.2

--[=[
	How long a puppet moving slower than PuppetSleepVelocity has before becoming anchored (seconds)

	@prop PuppetAnchorTimeout number
	@within Settings
	@tag Puppeteer
]=]
Settings.PuppetAnchorTimeout = 0.3

--[=[
	How frequently puppet CFrames are sent to each client (default 20 fps target replication frequency)

	:::tip
	This setting effectively limits the maximum Recv of Puppets.

	You can consider this setting to be the target in kilobytes/second (20KB/s max by default)
	:::
	@prop PuppetReplicationFrequency number
	@within Settings
	@tag Puppeteer
]=]
Settings.PuppetReplicationFrequency = 20

--[=[
	If true, the client will tween between puppet CFrame replications (Client-side only setting)

	@prop ClientTweenPuppets boolean
	@within Settings
	@tag Puppeteer
	@client
]=]
Settings.ClientTweenPuppets = true

--[=[
	Whether to use [Motor6D.Transform] or [WorldRoot:BulkMoveTo] for interpolating the client side puppets.

	@prop PUPPET_TWEEN_MODE "TRANSFORM"|"BULKMOVETO"
	@within Settings
	@tag Puppeteer
	@client
]=]
Settings.PUPPET_TWEEN_MODE = "BULKMOVETO" :: "TRANSFORM"|"BULKMOVETO"

--[=[
	Voxels farther than this many studs away don't get interpolated (Client-side only setting)

	@prop ClientTweenDistanceLimit number
	@within Settings
	@tag Puppeteer
	@client
]=]
Settings.ClientTweenDistanceLimit = 300



return Settings
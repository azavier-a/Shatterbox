--!native
--!optimize 2

--[=[
	A function that defines behavior to happen after a destruction is finished processing.

	### voxelCount

	A number that dictates how many voxels this destruction destroyed. This number is identical whether or not [DestructionParameters.SkipEncapsulatedVoxels] is true.

	### affectedIDs

	An array that contains every DirtyGroupID encountered during this destruction.

	Use this to obtain information such as the materials this destruction encountered.

	```lua
	hb.OnDestructCompleted = function(count, affectedIDs, destructionParameters)
		local materials = {}

		for DirtyGroupID in pairs(affectedIDs) do
			local original = Shatterbox.GetOriginalPart(DirtyGroupID)
			materials[original.Material] = true
		end

		for material in pairs(materials) do
			-- do something once for every material the destruction encountered
		end
	end
	```

	@type OnDestructCompletedType (voxelCount : number, affectedIDs : { [string] : boolean }, destructionParameters : DestructionParameters) -> ()
	@within Shatterbox
]=]


--[=[
	A function that is run for every voxel the destruction encounters.

	see [DestructionParameters.OnVoxelDestruct] for a brief explanation on how to use it.

	@type OnVoxelDestructType (voxel : Part | ImaginaryVoxel, info : VoxelInfo) -> ()
	@within Shatterbox
]=]


--[=[
	@interface VoxelInfo

	A table that contains information about the destroyed voxel

	### DirtyGroupID

	The ID of the dirty group this voxel is a part of.

	A dirty group is a group of parts that all originated from the same part.

	### CuttingPart

	The state of the hitbox as it was when the destruction was queued.

	### IsEdge

	Whether or not this voxel lies along the edge of the destruction.

	### IsAlreadyDebris

	Whether or not this voxel was already debris before this destruction destroyed it again.

	### UserData

	User supplied information to use in the OnVoxelDestruct effect.

	Equivalent to [DestructionParameters.UserData].

	.DirtyGroupID string
	.CuttingPart ImaginaryPart
	.IsEdge boolean
	.IsAlreadyDebris boolean
	.UserData {any}

	@within Shatterbox
]=]


--[=[
	@interface ImaginaryPart

	A table that represents a physical object

	.CFrame CFrame
	.Size Vector3
	.Shape PartType

	@within Shatterbox
]=]


--[=[
	@interface ImaginaryVoxel

	Represents a voxel that might be created.

	These are to be instantiated using [Shatterbox.InstantiateImaginaryVoxel]

	See [Shatterbox.VoxelInfo] for an explanation on these properties.

	.CFrame CFrame
	.Size Vector3
	.Shape PartType

	.DirtyGroupID string
	.IsEdge boolean
	.UserData {any}

	@within Shatterbox
]=]


local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Parent:WaitForChild("Types"))

local Shatterbox


--[=[
	@class DestructionParameters

	A table that specifies information needed for destruction to happen, as well as all of the optional per-destruction parameters.

	:::warning
	If you do not supply `params.CuttingPart` then you must assign `params.CFrame`, `params.Size`, and `params.Shape` (and vice-versa).
	:::
]=]
local DestructionParamsMT = {}
DestructionParamsMT.__index = DestructionParamsMT

--[=[
	The virtual/physical hitbox that the destruction will use.

	If this is not provided, [CFrame](#CFrame), [Size](#Size), and [Shape](#Shape), will be used. *You must provide one or the other.*

	If this is a Model, a destruction will be queued for every Part descendant of that Model

	@prop CuttingPart (ImaginaryPart|Part|Model)?
	@within DestructionParameters
]=]
DestructionParamsMT.CuttingPart = nil :: (Types.WorldInfo | Part | Model)?

--[=[
	@prop CFrame CFrame?
	@within DestructionParameters
]=]
DestructionParamsMT.CFrame = CFrame.identity :: CFrame?

--[=[
	@prop Size Vector3?
	@within DestructionParameters
]=]
DestructionParamsMT.Size = Vector3.zero :: Vector3?

--[=[
	@prop Shape PartType?
	@within DestructionParameters
]=]
DestructionParamsMT.Shape = Enum.PartType.Ball :: Enum.PartType?

--[=[
	Only instances with the given tag(s) are considered for voxel destruction.

	If this is not passed, every BasePart without the `"Indestructible"` tag is considered.

	@prop FilterTagged (string | {string})?
	@within DestructionParameters
]=]
DestructionParamsMT.FilterTagged = nil :: (string | {string})?

--[=[
	The amount of time in seconds before this destruction is cleaned up.

	:::note
	Set this to 0 to disable cleanups per-destruction
	:::

	:::note
	New destructions can reset the cleanup timer of existing dirty groups, *only if the new reset time would extend the time until cleanup.*

	#### Example

	You destroy with a `CleanupDelay` of 10, wait 4 seconds, and then with a `CleanupDelay` of 2 in the same spot. You will have to wait 6 seconds for it to come back because 6 is greater than 2.

	If you instead waited 9 seconds, the time until cleanup would get extended to 2 seconds because 1 is less than 2.
	:::

	@prop CleanupDelay number?
	@within DestructionParameters
]=]
DestructionParamsMT.CleanupDelay = nil :: number?

--[=[
	What GridSize this hitbox will divide parts down to.

	This can cause issues with greedy meshing if you destroy a part using multiple grid sizes.

	You should instead give parts a GridSize number attribute so each Part only has one GridSize.

	@prop GridSize number?
	@within DestructionParameters
	@deprecated Release 7
]=]
DestructionParamsMT.GridSize = nil :: number?

--[=[
	If set to true, the voxels passed to OnVoxelDestruct are not instantiated by the library, and you must do it manually with [Shatterbox.InstantiateImaginaryVoxel].

	@prop ManualVoxelInstantiation boolean?
	@within DestructionParameters
]=]
DestructionParamsMT.ManualVoxelInstantiation = nil :: boolean?

--[=[
	*This makes larger destructions an entire **order of magnitude** faster.*

	Whether or not to intelligently skip voxels fully contained by the hitbox.

	If this is false, these fully contained parts are Voxelized entirely using math.

	Otherwise, they are directly deleted.

	:::note
	If you use this parameter you will only recieve "edge" voxels.
	:::

	@prop SkipEncapsulatedVoxels boolean?
	@within DestructionParameters
]=]
DestructionParamsMT.SkipEncapsulatedVoxels = nil :: boolean?

--[=[
	@prop SkipFloors boolean?
	@within DestructionParameters
]=]
DestructionParamsMT.SkipFloors = nil :: boolean?

--[=[
	@prop SkipWalls boolean?
	@within DestructionParameters
]=]
DestructionParamsMT.SkipWalls = nil :: boolean?

--[=[
	The name of the OnVoxelDestruct effect you want to use for this destruction.

	You can register these effects either with [Shatterbox.RegisterOnVoxelDestruct] or by making an entry in the desired `Shatterbox/effects` module.

	Client side effects should be registered on the client side, while server side effects should be registered on the server side. Client side effects only work with Client-Server enabled.

	*You should register any given effect only once in a static context, which you are then free to use anywhere else - even in other scripts.*

	```lua
	Shatterbox.RegisterOnVoxelDestruct("SomeName", function(voxel, info)

		voxel.Anchored = false

		return
	end)

	-- later or in another script
	hb.OnVoxelDestruct = "SomeName"
	```

	@prop OnVoxelDestruct string?
	@within DestructionParameters
]=]
DestructionParamsMT.OnVoxelDestruct = nil :: string?

--[=[
	A callback that runs when the destruction is finished processing. Can be either a string or a function.

	You can register these callbacks either with [Shatterbox.RegisterOnDestructCompleted] or by making an entry in the desired `Shatterbox/effects` module.

	Client side callbacks should be registered on the client side, while server side callbacks should be registered on the server side. Client side callbacks only work with Client-Server enabled.

	:::warning
	This only works with `Shatterbox.Destroy` or `hitbox:Destroy()`.

	For ImaginaryVoxels, you can use the array of imaginary voxels to obtain the same information.
	:::
	@prop OnDestructCompleted (string | OnDestructCompleted)?
	@within DestructionParameters
]=]
DestructionParamsMT.OnDestructCompleted = nil :: (string | Types.OnDestructCompleted)?

--[=[
	A table that is passed to the OnVoxelDestruct effect as `info.UserData`.

	You can put variables in this table that are to be used in your effect.

	@prop UserData {any}?
	@within DestructionParameters
]=]
DestructionParamsMT.UserData = nil :: {any}?

--[=[
	If set, how many seconds the server will wait at max for each client to recieve their static map parts.

	This only works with Client-Server enabled.

	Use this if you see the ground flashing due to the size of your destruction.

	:::danger
	If you use it, be sure to keep this set to a low value like 0.1 or 0.2, as exploiters/laggy players can force every destruction to take this maximum amount of time.
	:::
	@prop WaitForClientTimeout number?
	@within DestructionParameters
]=]
DestructionParamsMT.WaitForClientTimeout = nil :: number?

--[=[
	A player or a list of players that will not recieve the destruction.

	This only works with Client-Server enabled.

	Use this on the server side if you have a client-initiated destruction, so the originating player doesn't recieve the same destruction they started.

	Server:
	```lua
	SomeEvent.OnServerEvent:Connect(function(plr, destructionCFrame)
		-- make sure you add sanity checks so you don't get hacked.

		hitbox.CFrame = destructionCFrame

		-- do not replicate the destruction back to "plr"
		hitbox.ExcludePlayersReplication = plr

		-- make sure the server side hitbox and the client side hitbox are identical when you do this. Otherwise the destructon won't be synchronized.
		hitbox:Destroy()
	end)
	```

	Client:
	```lua
	hitbox:Destroy()
	SomeEvent:FireServer(hitbox.CFrame)
	```

	@prop ExcludePlayersReplication (Player | {Player})?
	@within DestructionParameters
	@server
]=]
DestructionParamsMT.ExcludePlayersReplication = nil :: (Player | {Player})?


export type ShatterboxDestructionParameters = typeof(DestructionParamsMT)






--[=[
	@class Hitbox

	Helper class which represents a virtual hitbox. Contains all [destruction parameters](/api/DestructionParameters) as well as some unique parameters.
]=]
local HitboxMT = setmetatable({}, DestructionParamsMT)
HitboxMT.__index = HitboxMT

--[=[
	The delay in seconds between destructions when using [Hitbox:Start]

	@prop DestructDelay number?
	@within Hitbox
]=]
HitboxMT.DestructDelay = nil :: number?

--[=[
	Determines what kind of destruction is performed while using [Hitbox:Start].

	If set to "IMAGINARY", then [Hitbox.ImaginaryCallback] is used to give you the imaginary voxels and existing debris.

	@prop DestructionType "DEFAULT"|"IMAGINARY"
	@within Hitbox
]=]
HitboxMT.DestructionType = "DEFAULT" :: ("DEFAULT"|"IMAGINARY")

--[=[
	A callback that runs if [Hitbox.DestructionType] is set to `"IMAGINARY"` while using [Hitbox:Start].

	It supplies you the imaginary voxels and any existing debris.

	@prop ImaginaryCallback ( (imaginaryVoxels : {ImaginaryVoxel}, existingDebris : {BasePart}) -> () )?
	@within Hitbox
]=]
HitboxMT.ImaginaryCallback = nil :: ( (imaginaryVoxels : {Types.ImaginaryVoxel}, existingDebris : {BasePart}) -> () )?

--[=[
	Polling event for [Hitbox:Start].

	@prop StartConnectionEvent RBXScriptSignal
	@within Hitbox
]=]
HitboxMT.StartConnectionEvent = RunService.Heartbeat :: RBXScriptSignal-- the event that the hitbox connects to when using Start(), needs to have a deltaTime parameter

--[=[
	Polling event for [Hitbox:WeldTo].

	@prop WeldConnectionEvent RBXScriptSignal
	@within Hitbox
]=]
HitboxMT.WeldConnectionEvent = RunService.PostSimulation :: RBXScriptSignal -- the event that the hitbox connects to when using WeldTo()

--[=[
	The local offset from [DestructionParameters.CFrame] when using [Hitbox:WeldTo].

	@prop WeldOffset CFrame?
	@within Hitbox
]=]
HitboxMT.WeldOffset = nil :: CFrame?

--[=[
	Whether or not to predict the velocity of the part the hitbox is welded to.

	Only works if the hitbox is welded to a BasePart using [Hitbox:WeldTo].

	@prop VelocityPrediction boolean
	@within Hitbox
]=]
HitboxMT.VelocityPrediction = false :: boolean

--[=[
	How many frames ahead to predict when using [Hitbox.VelocityPrediction].

	@prop VelocityBias number
	@within Hitbox
]=]
HitboxMT.VelocityBias = 1 :: number

--[=[
	Equivalent to [Shatterbox.Destroy(Hitbox)](/api/Shatterbox#Destroy).

	Clears [Hitbox.ExcludePlayersReplication](/api/DestructionParameters#ExcludePlayersReplication).

	@within Hitbox
]=]
function HitboxMT:Destroy()
	Shatterbox.Destroy(self)
	self.ExcludePlayersReplication = {} -- QOL automatically clear the exlcusion after the destruction is performed
end

--[=[
	Equivalent to [Shatterbox.ImaginaryVoxels(Hitbox)](/api/Shatterbox#ImaginaryVoxels).

	Clears [Hitbox.ExcludePlayersReplication](/api/DestructionParameters#ExcludePlayersReplication).

	@return {ImaginaryVoxel}
	@return {BasePart}
	@return number

	@within Hitbox
]=]
function HitboxMT:ImaginaryVoxels() : ({Types.ImaginaryVoxel}, {BasePart}, number)
	local voxels, existingDebris, countVoxelsDestroyed = Shatterbox.ImaginaryVoxels(self)
	self.ExcludePlayersReplication = {} -- QOL automatically clear the exlcusion after the destruction is performed
	return voxels, existingDebris, countVoxelsDestroyed
end

--[=[
	Will "weld" the hitbox to the given part, setting `Hitbox.CFrame` to be equal to `Part.CFrame` whenever [Hitbox.WeldConnectionEvent] fires.

	If `Part` is destroyed using `Instance:Destroy()`, the hitbox will automatically call [Hitbox:DestroyHitbox]

	If `workspace.PlayerCharacterDestroyBehavior` is false, the hitbox *will not* be automatically stopped when that Player respawns if you have welded to their root part.

	@within Hitbox
]=]
function HitboxMT:WeldTo(Part : BasePart|Player)
	if self.wcon then
		self.wcon:Disconnect()
	end
	if self.dcon then
		self.dcon:Disconnect()
	end

	local isPlayer = Part:IsA("Player")
	local chr, weldedTo
	if isPlayer then
		chr = Part.Character or Part.CharacterAdded:Wait()
		weldedTo = chr:WaitForChild("HumanoidRootPart")
	else
		weldedTo = Part
	end

	local cf = weldedTo.CFrame
	if self.WeldOffset then
		cf *= self.WeldOffset
	end
	self.CFrame = cf

	self.wcon = self.WeldConnectionEvent:Connect(function(deltaTime)
		local newCFrame = weldedTo.CFrame
		local pingBias = isPlayer and Part:GetNetworkPing() * 0.5 or 1
		if self.WeldOffset then
			newCFrame *= self.WeldOffset
		end
		if self.VelocityPrediction then
			newCFrame += weldedTo.AssemblyLinearVelocity * self.VelocityBias * pingBias * deltaTime
		end
		self.CFrame = newCFrame
	end)

	self.dcon = weldedTo.Destroying:Once(self.DestroyHitbox)
end

--[=[
	Will "unweld" the hitbox if it has been welded after using [Hitbox:WeldTo].

	@within Hitbox
]=]
function HitboxMT:Unweld()
	if self.wcon then
		self.wcon:Disconnect()
	end
	if self.dcon then
		self.dcon:Disconnect()
	end
	self.wcon, self.dcon = nil, nil
end

--[=[
	Will start to cut around the hitbox every [Hitbox.DestructDelay] seconds, which defaults to 0 (every frame).

	The hitbox updates every time the [Hitbox.StartConnectionEvent] fires, which is expected to supply a `deltaTime` parameter.

	If [Hitbox.DestructionType] is set to `"IMAGINARY"`, then [Hitbox.ImaginaryCallback] is used to give you the imaginary voxels and existing debris.

	@within Hitbox
]=]
function HitboxMT:Start()
	if self.ccon then return end
	self.ccon = self.StartConnectionEvent:Connect(function()
		if self.DestructDelay then
			local t = time()
			if self.lastCut and t - self.lastCut < self.DestructDelay then return end
			self.lastCut = t
		end

		if self.DestructionType == "DEFAULT" then
			self:Destroy()
		else
			local voxels, existingDebris = self:ImaginaryVoxels()
			if self.ImaginaryCallback then
				self.ImaginaryCallback(voxels, existingDebris)
			end
		end
	end)
end

--[=[
	Will stop cutting around the hitbox if the hitbox is active after using [Hitbox:Start].

	@within Hitbox
]=]
function HitboxMT:Stop()
	if self.ccon then
		self.ccon:Disconnect()
	end
	self.ccon = nil
end

--[=[
	Will call [Hitbox:Unweld] and then [Hitbox:Stop].

	Calling each individually is equivalent to calling this function.

	@within Hitbox
]=]
function HitboxMT:DestroyHitbox()
	self:Unweld()
	self:Stop()
end


export type ShatterboxHitbox = typeof(HitboxMT)






local Metatables = {}

Metatables.DestructionParamsMT = DestructionParamsMT

Metatables.HitboxMT = HitboxMT

function Metatables:SetReference(shatterbox)
    Shatterbox = shatterbox
    Metatables.SetReference = nil
end

return Metatables
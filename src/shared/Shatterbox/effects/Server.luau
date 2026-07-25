--!native
--!optimize 2

--#selene: allow(unused_variable)
--#selene: allow(multiple_statements)
--#selene: allow(incorrect_standard_library_use)

local Shatterbox
local Types = require(script.Parent.Parent:WaitForChild("Types"))

local ServerEffects = {} :: { [string] : Types.OnVoxelDestruct }
local DestructCompleted = {} :: { [string] : Types.OnDestructCompleted }



-- define your server side effects here. Defining the same effect name on both sides causes the effect to do different things on server and client sides.
--[[

ServerEffects.EffectName = function(voxel, info)


end

]]



-- Maps one numeric range onto another
local function map(x, a_0, a_1, b_0, b_1) return b_0 + (b_1 - b_0)*(x - a_0)/(a_1 - a_0) end


-- This effect assumes a spherical hitbox (Shape "Ball").
-- This is an example show you how to use voxel space to perform calculations that are consistent regardless of the gridsize or orientation of voxels.
-- The inner 33% of voxels are removed.
-- Starting at the point where voxels are no longer removed, voxels are black. There is a gradient until around the edges, where the voxels should be their original color.
ServerEffects.MappingVoxelSpace = function(voxel, info)

    if info.IsAlreadyDebris then return end

    -- the radius of the spherical hitbox
    local R = info.CuttingPart.Size * 0.5

    -- from the center of the sphere, how many voxels away the edge of the sphere is on each axis (in local space)
    local MaxVoxelDist = Shatterbox.VoxelCountVector(voxel, math.min(R.X, R.Y, R.Z)*Vector3.one)

    -- from the center of the current voxel, how many voxels away the center of the sphere is on each axis (in local space)
    local VoxelDist = Shatterbox.VoxelDistanceVector(voxel, info.CuttingPart.CFrame.Position):Min(MaxVoxelDist)

    -- The magnitude of this vector is guaranteed to be in the range 0 to close to 1 because spheres hold a consistent magnitude
    local NormalDist = (VoxelDist / MaxVoxelDist).Magnitude

    -- destroy voxels close to the center (inner 33% by default)
    local NormalDistThreshold = 0.33

    if NormalDist < NormalDistThreshold then
        Shatterbox.Cleanup(voxel)
        return
    end

    -- map and clamp the range [NormalDistThreshold, 1] to the range [1, 0]
    -- So where the voxels begin to appear, they start at black, and where the voxels end, they should be their original color.
    local Shade = math.clamp(map(NormalDist, NormalDistThreshold,1, 1,0), 0, 1)

    voxel.Color = voxel.Color:Lerp(Color3.new(), Shade)
end





-- An example effect that attempts to re-create the M1 destructions from JJS.
-- Debris is tweened by clients, having the CFrames replicateed from the server.
-- Only non-floors turn into debris (a floor has a vertical normal when casting toward it from the cuttingPart).
-- Floors have a separate effect that makes them appear "broken".
-- the check cast for floors originates from `UserData.CastOrigin`, if that value is not provided then `CuttingPart.CFrame.Position` is used instead

-- Pre-allocated RaycastParams instance
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include

ServerEffects.BumpyFloorBreakWalls = function(voxel, info : Types.DestroyedVoxelInfo)
    if info.IsAlreadyDebris then return end

    local O = info.UserData.CastOrigin or info.CuttingPart.CFrame.Position
    local toVoxel = voxel.Position - O
    -- retrieves the untouched original part, to check if the voxel should be considered a floor
    local castTo = Shatterbox.GetOriginalPart(info.DirtyGroupID)

    raycastParams.FilterDescendantsInstances = { castTo }

    castTo.Parent = workspace
    local hitResult = workspace:Raycast(O - toVoxel * 0.01, toVoxel * 1.01, raycastParams)
    castTo.Parent = nil

    if hitResult and hitResult.Normal:FuzzyEq(Vector3.yAxis, 0.01) then -- if the normal is facing up, it is a floor

        voxel.Position += Vector3.yAxis * (math.random() - 0.5) -- add some random vertical offset to floor voxels

    else -- everything else becomes a falling voxel using puppeteer

        Shatterbox.Puppeteer(voxel) -- start controlled replication of "voxel" to clients (tween between replication of CFrames)

        voxel.AssemblyLinearVelocity = toVoxel.Unit * (math.random() * 25 + 50)
    end
end







-- Also define your server side OnDestructCompleted callbacks here. This works the same way as OnVoxelDestruct.
--[[

DestructCompleted.CompletedName = function(voxelCount, affectedIDs, destructionParameters)


end

]]


-- An example OnDestructCompleted callback that returns all of the materials this destruction encountered as a map {[Enum.Material] : boolean}
DestructCompleted.GetMaterialsMap = function(voxelCount : number, affectedIDs : {[string] : boolean}, destructionParameters : Types.DestructionParams)
    local materialsMap = {}
    for DirtyGroupID in pairs(affectedIDs) do
        local OriginalPart = Shatterbox.GetOriginalPart(DirtyGroupID)
        materialsMap[OriginalPart.Material] = true
    end
    return materialsMap
end



-- An example OnDestructCompleted callback that prints out the names of every material this destruction encountered. It uses Shatterbox.OnVoxelDestruct to extend the existing callback "GetMaterialsMap"
DestructCompleted.ExtendingACallback = function(voxelCount, affectedIDs, destructionParams)
	local destroyedMaterials = Shatterbox.OnDestructCompleted("GetMaterialsMap", voxelCount, affectedIDs, destructionParams)
	for material in pairs(destroyedMaterials) do
		print(material.Name)
	end
end









local ServerSideCallbacks = {}

-- Do not use this function, it just lets you use the Shatterbox functions in this module (avoiding a cyclic dependancy)
function ServerSideCallbacks:SetReference(shatterbox) Shatterbox = shatterbox; ServerSideCallbacks.SetReference = nil end

ServerSideCallbacks.OnVoxelDestruct = ServerEffects
ServerSideCallbacks.OnDestructCompleted = DestructCompleted

return ServerSideCallbacks
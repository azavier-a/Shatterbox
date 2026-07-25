--!native
--!optimize 2

--#selene: allow(unused_variable)
--#selene: allow(multiple_statements)

local Shatterbox
local Types = require(script.Parent.Parent:WaitForChild("Types"))


local ClientEffects = {} :: { [string] : Types.OnVoxelDestruct }
local DestructCompleted = {} :: { [string] : Types.OnDestructCompleted }




-- define your client side effects here. Defining the same effect name on both sides causes the effect to do different things on server and client sides.
--[[

ClientEffects.EffectName = function(voxel, info)


end

]]



-- An example effect that leaves rough edges around the destruction that are cleaned on smooth cleanup
ClientEffects.Rough = function(voxel, info : Types.DestroyedVoxelInfo)

    if info.IsAlreadyDebris then -- the voxel is already debris
        if not info.IsEdge then Shatterbox.Cleanup(voxel) end -- fully contained debris is destroyed
        return
    end

    local roll = math.random()

    if info.IsEdge and roll < 0.8 then -- 80% of edge voxels become "edge debris"
        voxel.CFrame *= CFrame.Angles(math.random() * 2 * math.pi, math.random() * 2 * math.pi, math.random() * 2 * math.pi)
        voxel.Size *= math.random() + 1
        return
    end

    if roll > 0.05 then Shatterbox.Cleanup(voxel) return end -- a small percentage of voxels are destroyed

    -- all other voxels are flying debris

    voxel.Anchored = false
    voxel.CanCollide = false
    voxel.AssemblyLinearVelocity = (Vector3.new(math.random(), math.random(), math.random()) - Vector3.one * 0.5) * 80
    voxel.AssemblyAngularVelocity = (Vector3.new(math.random(), math.random(), math.random()) - Vector3.one * 0.5) * 20

    -- remember to destroy the voxel
    Shatterbox.DelayedCleanup(3, voxel)
end










-- Also define your client side OnDestructCompleted callbacks here. This works the same way as OnVoxelDestruct.
--[[

DestructCompleted.CompletedName = function(voxelCount, affectedIDs)


end

]]
















local ClientSideCallbacks = {}

-- Do not use this function, it just lets you use the Shatterbox functions in this module (avoiding a cyclic dependancy)
function ClientSideCallbacks:SetReference(shatterbox) Shatterbox = shatterbox; ClientSideCallbacks.SetReference = nil end

ClientSideCallbacks.OnVoxelDestruct = ClientEffects
ClientSideCallbacks.OnDestructCompleted = DestructCompleted

return ClientSideCallbacks
--#selene: allow(unused_variable)
--#selene: allow(multiple_statements)

local Shatterbox
local Types = require(script.Parent.Parent:WaitForChild("Types"))

local ClientEffects = {} :: { [string] : Types.OnVoxelDestruct }

-- Do not use this function, it just lets you use the Shatterbox functions in this module (avoiding a cyclic dependancy)
function ClientEffects:SetReference(shatterbox) Shatterbox = shatterbox end










-- define your client side effects here. Defining the same effect name on both sides causes the effect to do different things on server and client sides.
--[[

ClientEffects.EffectName = function(voxel, dirtyParent, cuttingPart, isEdge)


end

]]












-- The default client behavior (for when an OnVoxelDestruct callback does not exist)
ClientEffects.Default = function(voxel) voxel:Destroy() end







-- An example effect that leaves rough destructible edges around the destruction that are cleaned on smooth cleanup
ClientEffects.Rough = function(voxel, dirtyParent, cuttingPart, isEdge)

    if voxel:HasTag("StaticDebris") then
        voxel.Parent = dirtyParent -- makes the debris destructible again
        if Shatterbox.PartEncapsulatesBlockPart(cuttingPart, voxel) then voxel:Destroy() end -- fully contained debris is destroyed
        return
    end

    local roll = math.random()

    if isEdge and roll < 0.8 then
        voxel.CFrame *= CFrame.Angles(math.random() * 2 * math.pi, math.random() * 2 * math.pi, math.random() * 2 * math.pi)
        voxel.Size *= math.random() + 1
        voxel.Parent = dirtyParent -- makes the debris destructible again
        voxel:AddTag("StaticDebris")
        return
    end

    if roll > 0.05 then voxel:Destroy() return end

    voxel.Anchored = false
    voxel.CanCollide = false
    voxel.AssemblyLinearVelocity = (Vector3.new(math.random(), math.random(), math.random()) - Vector3.one * 0.5) * 80
    voxel.AssemblyAngularVelocity = (Vector3.new(math.random(), math.random(), math.random()) - Vector3.one * 0.5) * 20

    -- remember to destroy the part
    game.Debris:AddItem(voxel, 3)
end










return ClientEffects
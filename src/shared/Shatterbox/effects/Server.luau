--#selene: allow(unused_variable)
--#selene: allow(multiple_statements)

local Shatterbox
local Types = require(script.Parent.Parent:WaitForChild("Types"))

local ServerEffects = {} :: { [string] : Types.OnVoxelDestruct }

-- Do not use this function, it just lets you use the Shatterbox functions in this module (avoiding a cyclic dependancy)
function ServerEffects:SetReference(shatterbox) Shatterbox = shatterbox end




-- define your server side effects here. Defining the same effect name on both sides causes the effect to do different things on server and client sides.
--[[

ServerEffects.EffectName = function(voxel, dirtyParent, cuttingPart, isEdge)


end

]]








-- The default client behavior (for when an OnVoxelDestruct callback does not exist)
ServerEffects.Default = function(voxel) voxel:Destroy() end







-- An example effect that attempts to re-create the M1 destructions from JJS.
-- Debris is tweened by clients, having the CFrames replicateed from the server.
-- Only non-floors turn into debris (a floor has a vertical normal when casting toward it from the cuttingPart).
-- Floors have a separate effect that makes them appear "broken".
ServerEffects.BumpyFloorBreakWalls = function(voxel, dirtyParent, cuttingPart, isEdge)

    -- retrieves a clone of the untouched original part, to check if the voxel should be considered a floor
    local castTo = Shatterbox.GetOriginalPart(dirtyParent)
    castTo.Parent = workspace

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = { castTo }

    local hitResult = workspace:Raycast(cuttingPart.Position, voxel.Position - cuttingPart.Position, raycastParams)

    castTo.Parent = nil -- the return value of GetOriginalPart is cached and automatically deleted after 5 seconds

    -- if the normal is facing up, it is a floor
    if hitResult and hitResult.Normal:FuzzyEq(Vector3.yAxis, 0.01) then

        local randomYoffset = math.random() - 0.5

        voxel.Position += hitResult.Normal * randomYoffset

        dirtyParent.Destroying:Once(function() -- the server-side dirtyParent does not replicate to clients, so we can't just parent the voxel (it wouldn't replicate)
            voxel:Destroy()
        end)
    else
        voxel.Anchored = false

        Shatterbox.Puppeteer(voxel) -- start controlled replication of "voxel" to clients (tween between replication of CFrames)

        voxel.Parent = dirtyParent -- makes debris work with smooth cleanup and makes debris destructible again (the server side debris isn't replicated for clients when puppeteering)
    end
end





return ServerEffects
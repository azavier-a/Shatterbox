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






return ServerEffects
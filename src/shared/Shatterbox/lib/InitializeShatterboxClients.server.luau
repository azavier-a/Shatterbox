--#selene: allow(unused_variable)

local Shatterbox = require(script.Parent.Parent:WaitForChild("Main"))

-- you can use this area as a place to define client-only effects for your own usage if you want to
--[[example:

Shatterbox.RegisterOnVoxelDestruct("SomeName",
	function(voxel: Part, originalPart: Part, dirtyParent: Model, cuttingPart: BasePart, isEdge : boolean)
		-- client code
		game.Debris:AddItem(voxel, 3) -- remember to destroy the debris
	end)

--]]
--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)

local lib = script.Parent
local core = lib.Parent
local src = core.Parent

local HttpService = game:GetService("HttpService")

local Settings = require(src:WaitForChild("Settings"))
local Types = require(src:WaitForChild("Types"))


local WHITE = Color3.new(1, 1, 1)


local function GetCondensedGUID()
	return string.gsub(HttpService:GenerateGUID(false), '-', '')
end


local Serializer = {}


-- Validates destruction parameters
local function ValidateDestructionParams(Parameters : Types.DestructionParams | Types.ImaginaryDestructionParams)

	local CuttingPart = {} :: Types.Hitbox
	local params = {} :: Types.InternalDestructionParams | Types.InternalImaginaryParams
	local tbl = {} :: Types.DestructionParams | Types.ImaginaryDestructionParams

	assert(typeof(Parameters) == "table" or (typeof(Parameters) == "Instance" and Parameters:IsA("Part")), "Parameters must be a table or a Part")
	if typeof(Parameters) == "table" then
		tbl = Parameters
		if tbl.CuttingPart then
			local cp = tbl.CuttingPart
			assert(typeof(cp) == "table" or (typeof(cp) == "Instance" and cp:IsA("Part")), "Parameters.CuttingPart must be a table or a Part.")
			assert(cp.CFrame and cp.Size and cp.Shape, "You must provide a CFrame, Size, and Shape for the 'Parameters.CuttingPart : { CFrame : CFrame, Size : Vector3, Shape : Enum.PartType }' syntax.")
			CuttingPart.CFrame = cp.CFrame
			CuttingPart.Size = cp.Size
			CuttingPart.Shape = cp.Shape
		else
			assert(tbl.CFrame and tbl.Size and tbl.Shape, "You must provide a CFrame, Size, and Shape for the 'Parameters.CFrame : CFrame, Parameters.Size : Vector3, Parameters.Shape : Enum.PartType' syntax.")
			CuttingPart.CFrame = tbl.CFrame
			CuttingPart.Size = tbl.Size
			CuttingPart.Shape = tbl.Shape
		end
	elseif Parameters:IsA("Part") then
		CuttingPart.CFrame = Parameters.CFrame
		CuttingPart.Size = Parameters.Size
		CuttingPart.Shape = Parameters.Shape
	end

	local filterTagged = tbl.FilterTagged
	if filterTagged then
		if typeof(filterTagged) == "table" then
			for _, k in pairs(filterTagged) do
				assert(typeof(k) == "string", "FilterTagged must be an array of strings only")
			end
		else
			assert(typeof(filterTagged) == "string", "FilterTagged must be a string or an array of strings")
			filterTagged = { filterTagged }
		end
	end

	local playerExclusions = tbl.ExcludePlayersReplication
	if playerExclusions then
		if typeof(playerExclusions) == "table" then
			for _, plr in ipairs(playerExclusions) do
				assert(typeof(plr) == "Instance" and plr:IsA("Player"), "If ExcludePlayersReplication is an array, it must only contain Players.")
			end
		else
			assert(typeof(playerExclusions) == "Instance" and playerExclusions:IsA("Player"), "If ExcludePlayersReplication is not an array, it must be a Player.")
			playerExclusions = { playerExclusions }
		end
	end

				  params.CuttingPart = CuttingPart
				 params.FilterTagged = filterTagged
				 params.CleanupDelay = tbl.CleanupDelay		         or Settings.DefaultSmoothCleanupDelay
			  params.OnVoxelDestruct = tbl.OnVoxelDestruct
	 params.ManualVoxelInstantiation = tbl.ManualVoxelInstantiation
					 params.GridSize = tbl.GridSize
	   params.SkipEncapsulatedVoxels = tbl.SkipEncapsulatedVoxels
				   params.SkipFloors = tbl.SkipFloors
				    params.SkipWalls = tbl.SkipWalls
		  params.OnDestructCompleted = tbl.OnDestructCompleted
					 params.UserData = tbl.UserData    		         or {}
		 params.WaitForClientTimeout = tbl.WaitForClientTimeout
	params.ExcludePlayersReplication = playerExclusions 			 or {}
		                   params.ID = tbl.ID 					     or GetCondensedGUID()
	assert(not params.ManualVoxelInstantiation or typeof(params.ManualVoxelInstantiation) == "boolean", "ManualVoxelInstantiation must be a boolean if it is set.")
	assert(not params.CleanupDelay or typeof(params.CleanupDelay) == "number", "CleanupDelay must be a number if it is set.")
	assert(not params.OnVoxelDestruct or typeof(params.OnVoxelDestruct) == "string", "OnVoxelDestruct must be a string indicating the name of the OnVoxelDestruct callback.")
	assert(not params.GridSize or typeof(params.GridSize) == "number", "GridSize must be a number.")
	assert(not params.SkipEncapsulatedVoxels or typeof(params.SkipEncapsulatedVoxels) == "boolean", "SkipEncapsulatedVoxels must be a boolean.")
	assert(not params.OnDestructCompleted or typeof(params.OnDestructCompleted) == "string" or typeof(params.OnDestructCompleted) == "function", "OnDestructCompleted must be a string or a function.")

	return params :: (Types.InternalImaginaryParams | Types.InternalDestructionParams)
end
Serializer.ValidateDestructionParams = ValidateDestructionParams

function Serializer.SerializedDestructionParams(destructionParams)
	destructionParams = table.clone(destructionParams)
    local CuttingPart = destructionParams.CuttingPart
	destructionParams.CuttingPart = {
		CFrame = CuttingPart.CFrame,
		Size = CuttingPart.Size,
		Shape = CuttingPart.Shape.Value
	}
	local OnDestructCompleted = destructionParams.OnDestructCompleted
	if OnDestructCompleted and typeof(OnDestructCompleted) == "function" then
		destructionParams.OnDestructCompleted = nil
	end
	return destructionParams
end

function Serializer.DeserializedDestructionParams(serialDestructionParams)
	serialDestructionParams.CuttingPart.Shape = Enum.PartType:FromValue(serialDestructionParams.CuttingPart.Shape)
	local destructionParams = ValidateDestructionParams(serialDestructionParams)
	destructionParams.replicated = true
	return destructionParams
end



function Serializer.SerializedDecalInstance(decal : Decal)
	local serialDecal = {}

	local prop = decal.Color3
	if prop ~= WHITE then
        serialDecal.Color3 = prop
    end

	prop = #decal.ColorMap > 0 and decal.ColorMap or decal.Texture
	if #prop > 0 then
        serialDecal.ColorMap = prop
    end

	prop = decal.Transparency
	if prop ~= 0 then
        serialDecal.Transparency = prop
    end

	prop = decal.UVOffset
	if prop ~= Vector2.zero then
        serialDecal.UVOffset = prop
    end
	prop = decal.UVScale
	if prop ~= Vector2.one then
        serialDecal.UVScale = prop
    end

	prop = decal.ZIndex
	if prop ~= 1 then
        serialDecal.ZIndex = prop
    end

	prop = decal.Face.Value
	if prop ~= 5 then
        serialDecal.Face = prop
    end

	return serialDecal
end

function Serializer.DeserializedDecalInstance(serialDecal, ClassName : string) : Decal | Texture

	local decal = Instance.new(ClassName)

	local prop = serialDecal.Color3
	if prop then
        decal.Color3 = prop
    end

	prop = serialDecal.ColorMap
	if prop then
        decal.ColorMap = prop
    end

	prop = serialDecal.Transparency
	if prop then
        decal.Transparency = prop
    end

	prop = serialDecal.UVOffset
	if prop then
        decal.UVOffset = prop
    end
	prop = serialDecal.UVScale
	if prop then
        decal.UVScale = prop
    end

	prop = serialDecal.ZIndex
	if prop then
        decal.ZIndex = prop
    end

	prop = serialDecal.Face
	if prop then
        decal.Face = Enum.NormalId:FromValue(prop)
    end

	return decal
end



return Serializer
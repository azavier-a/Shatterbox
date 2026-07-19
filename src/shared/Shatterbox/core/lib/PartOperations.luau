--!native
--!optimize 2

--#selene: allow(incorrect_standard_library_use)
--#selene: allow(multiple_statements)
--#selene: allow(unused_variable)

local lib = script.Parent
local core = lib.Parent
local src = core.Parent

local Types = require(src:WaitForChild("Types"))

local Serializer = require(lib:WaitForChild("Serializer"))
local SerializedDecalInstance = Serializer.SerializedDecalInstance
local DeserializedDecalInstance = Serializer.DeserializedDecalInstance


local WHITE = Color3.new(1, 1, 1)


local PartOperations = {}


--[[
    Creates a new part using the supplied `template`, which is either a Part instance or a serialized Part instance

    A CFrame can be supplied which is where the part will be placed.
]]
function PartOperations.PartFromTemplate(template : BasePart, cframe : CFrame, CachedParts) : BasePart

	if not template:IsA("Part") or template.Shape ~= Enum.PartType.Block then
		local cloned = template:Clone()
		if cframe then cloned.CFrame = cframe end
		return cloned
	end

	local part

	--debug.profilebegin("create part")

	if CachedParts then
		part = CachedParts:GetPart(cframe)
		part.CanCollide = true
	else
		part = Instance.new("Part")
		if cframe then part.CFrame = cframe end
	end

	-- Set properties if they are not their defaults
	local prop

    if not part.Anchored then part.Anchored = true end

	prop = template.Size
    if prop ~= part.Size then part.Size = prop end

	--
	--part.Color = Color3.fromHSV(math.random(), 1, 1)
	prop = template.Color
    if prop ~= part.Color then part.Color = prop end
	prop = template.Transparency
    if prop ~= part.Transparency then part.Transparency = prop end
	prop = template.Reflectance
    if prop ~= part.Reflectance then part.Reflectance = prop end

	prop = template.Material
    if prop ~= part.Material then part.Material = prop end
	prop = template.MaterialVariant
    if prop ~= part.MaterialVariant then part.MaterialVariant = prop end

	prop = template.CollisionGroup
    if prop ~= part.CollisionGroup then part.CollisionGroup = prop end
	prop = template.CanCollide
    if prop ~= part.CanCollide then part.CanCollide = prop end

	-- copy surface property values
	prop = template.RightSurface
    if prop ~= part.RightSurface then part.RightSurface = prop end
	prop = template.LeftSurface
    if prop ~= part.LeftSurface then part.LeftSurface = prop end
	prop = template.FrontSurface
    if prop ~= part.FrontSurface then part.FrontSurface = prop end
	prop = template.BackSurface
    if prop ~= part.BackSurface then part.BackSurface = prop end
	prop = template.TopSurface
    if prop ~= part.TopSurface then part.TopSurface = prop end
	prop = template.BottomSurface
    if prop ~= part.BottomSurface then part.BottomSurface = prop end
	--]]

	-- copy tags
	for _, tag in ipairs(template:GetTags()) do part:AddTag(tag) end

	-- copy attributes
	for k, v in pairs(template:GetAttributes()) do
		if k:sub(1, 3) == "RBX" then continue end
		part:SetAttribute(k, v)
	end

	--
	-- copy textures
	for _, child in ipairs(template:GetChildren()) do
		if child:IsA("Texture") then child:Clone().Parent = part end
	end
	--]]

	--debug.profileend()

	return part
end



--[[
    Deserializes the given serialized part instance `p`
]]
function PartOperations.DeserializedPartInstance(p, CachedParts) : Part

	local part

	if CachedParts then
		part = CachedParts:GetPart(p.CFrame)
		part.CanCollide = true
	else
		part = Instance.new("Part")
		if p.CFrame then part.CFrame = p.CFrame end
	end

	if not part.Anchored then part.Anchored = true end

	-- deserialize properties
	local prop

	prop = p.Size
	if prop and part.Size ~= prop then part.Size = prop end

	--
	--part.Color = Color3.fromHSV(math.random(), 1, 1)
	prop = p.Color
    if prop and part.Color ~= prop then part.Color = prop end
	prop = p.Transparency
    if prop and part.Transparency ~= prop then part.Transparency = prop end
	prop = p.Reflectance
    if prop and part.Reflectance ~= prop then part.Reflectance = prop end
	prop = p.Material
    if prop and part.Material.Value ~= prop then part.Material = Enum.Material:FromValue(prop) end
	prop = p.MaterialVariant
    if prop and part.MaterialVariant ~= prop then part.MaterialVariant = prop end
	prop = p.CollisionGroup
    if prop and part.CollisionGroup ~= prop then part.CollisionGroup = prop end
	prop = p.CanCollide
    if part.CanCollide ~= prop then part.CanCollide = prop end

	-- deserialize surface property values
	prop = p.RightSurface
    if prop and part.RightSurface.Value ~= prop then part.RightSurface = Enum.SurfaceType:FromValue(prop) end
	prop = p.LeftSurface
    if prop and part.LeftSurface.Value ~= prop then part.LeftSurface = Enum.SurfaceType:FromValue(prop) end
	prop = p.FrontSurface
    if prop and part.FrontSurface.Value ~= prop then part.FrontSurface = Enum.SurfaceType:FromValue(prop) end
	prop = p.BackSurface
    if prop and part.BackSurface.Value ~= prop then part.BackSurface = Enum.SurfaceType:FromValue(prop) end
	prop = p.TopSurface
    if prop and part.TopSurface.Value ~= prop then part.TopSurface = Enum.SurfaceType:FromValue(prop) end
	prop = p.BottomSurface
    if prop and part.BottomSurface.Value ~= prop then part.BottomSurface = Enum.SurfaceType:FromValue(prop) end
	--]]

	-- deserialize tags
	for _, tag in ipairs(p.Tags) do part:AddTag(tag) end

	-- deserialize attributes
	for k, v in pairs(p.Attributes) do part:SetAttribute(k, v) end

	--
	-- deserialize decals
	if p.Decals then
		for _, serialDecal in ipairs(p.Decals) do
			local instancedDecal = DeserializedDecalInstance(serialDecal, "Decal")
			instancedDecal.Parent = part
		end
	end

	-- deserialize textures
	if p.Textures then
		for _, serialTexture in ipairs(p.Textures) do
			local instancedTexture = DeserializedDecalInstance(serialTexture, "Texture")
			prop = serialTexture.OffsetStudsU
			if prop then instancedTexture.OffsetStudsU = prop end
			prop = serialTexture.OffsetStudsV
			if prop then instancedTexture.OffsetStudsV = prop end
			prop = serialTexture.StudsPerTileU
			if prop then instancedTexture.StudsPerTileU = prop end
			prop = serialTexture.StudsPerTileV
			if prop then instancedTexture.StudsPerTileV = prop end

			instancedTexture.Parent = part
		end
	end

	-- deserialize lights
	if p.Lights then
		for _, serialLight in ipairs(p.Lights) do
			local light = Instance.new(serialLight.ClassName)

			if serialLight.Shadows then light.Shadows = true end
			prop = serialLight.Brightness
			if prop then light.Brightness = prop end
			prop = serialLight.Color
			if prop then light.Color = prop end
			prop = serialLight.Range
			if prop then light.Range = prop end

			if serialLight.ClassName ~= "PointLight" then
				prop = serialLight.Angle
				if prop then light.Angle = prop end
				prop = serialLight.Face
				if prop then light.Face = Enum.NormalId:FromValue(prop) end
			end

			light.Parent = part
		end
	end
	--]]

	return part
end



--[[
    Serializes the given part instance `p`
]]
function PartOperations.SerializedPartInstance(p : Part, ignoreWorldState : boolean)
	local serial = {
		Tags = p:GetTags()
	}

	local Attributes = {}
	for k, v in pairs(p:GetAttributes()) do
		if k:sub(1, 3) == "RBX" then continue end -- seriously Roblox why do I have to check for this? Become better.
		Attributes[k] = v
	end
	serial.Attributes = Attributes

	serial.Color = p.Color
	serial.Transparency = p.Transparency
	serial.Reflectance = p.Reflectance
	serial.Material = p.Material.Value
	serial.MaterialVariant = p.MaterialVariant
	serial.CollisionGroup = p.CollisionGroup
	serial.CanCollide = p.CanCollide

	serial.RightSurface = p.RightSurface.Value
	serial.LeftSurface = p.LeftSurface.Value
	serial.FrontSurface = p.FrontSurface.Value
	serial.BackSurface = p.BackSurface.Value
	serial.TopSurface = p.TopSurface.Value
	serial.BottomSurface = p.BottomSurface.Value

	-- serialize decals, textures, and lights
	local decals, textures, lights = {}, {}, {}
	for _, child in ipairs(p:GetChildren()) do
		local prop = nil
		if child:IsA("Texture") then
			local serialTexture = SerializedDecalInstance(child)
			prop = child.OffsetStudsU
			if prop ~= 0 then serialTexture.OffsetStudsU = prop end
			prop = child.OffsetStudsV
			if prop ~= 0 then serialTexture.OffsetStudsV = prop end
			prop = child.StudsPerTileU
			if prop ~= 2 then serialTexture.StudsPerTileU = prop end
			prop = child.StudsPerTileV
			if prop ~= 2 then serialTexture.StudsPerTileV = prop end

			table.insert(textures, serialTexture)
		elseif child:IsA("Decal") then
			table.insert(decals, SerializedDecalInstance(child))
		elseif child:IsA("Light") then
			local className = child.ClassName
			local isAPointLight = className == "PointLight"

			local serialLight = { ClassName = className }

			if child.Shadows then serialLight.Shadows = true end
			prop = child.Brightness
			if prop ~= 1 then serialLight.Brightness = prop end
			prop = child.Color
			if prop ~= WHITE then serialLight.Color = prop end
			prop = child.Range
			if (isAPointLight and prop ~= 8) or (not isAPointLight and prop ~= 16) then serialLight.Range = prop end

			if not isAPointLight then
				prop = child.Angle
				if prop ~= 90 then serialLight.Angle = prop end
				prop = child.Face.Value
				if prop ~= 5 then serialLight.Face = prop end
			end

			table.insert(lights, serialLight)
		end
	end
	if #decals > 0 then serial.Decals = decals end
	if #textures > 0 then serial.Textures = textures end
	if #lights > 0 then serial.Lights = lights end

	if ignoreWorldState then return serial end

	serial.CFrame = p.CFrame
	serial.Size = p.Size

	return serial
end



return PartOperations
--!strict
--!native
--!optimize 2

local FAR_AWAY_CFRAME = CFrame.new(2^24, 2^24, 2^24)
local EXPAND_BY_AMOUNT = 50

local MovingParts = table.create(10_000)
local MovingCFrames = table.create(10_000)

local UpdateMap = {} :: { [Part] : CFrame }

--[[
local WorldAnchor = Instance.new("Part")
WorldAnchor.Anchored = true
WorldAnchor.CanCollide = false
WorldAnchor.CanTouch = false
WorldAnchor.CanQuery = false
WorldAnchor.Transparency = 1
WorldAnchor.CFrame = CFrame.identity
WorldAnchor.Parent = workspace
--]]


local function UpdateMovement()
	--
	local i = 1
	for MovingPart, MovingCFrame in pairs(UpdateMap) do
		MovingParts[i] = MovingPart
		MovingCFrames[i] = MovingCFrame
		i += 1
	end

	workspace:BulkMoveTo(MovingParts, MovingCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	--]]
	--[[
	for part, cframe in pairs(UpdateMap) do
		local Motor6D = part:FindFirstChildWhichIsA("Motor6D")
		if Motor6D then
			Motor6D.Transform = cframe
			part.Anchored = (cframe == FAR_AWAY_CFRAME)
		end
	end
	--]]

	table.clear(UpdateMap)
	table.clear(MovingParts)
	table.clear(MovingCFrames)
end

local Cache = {}
Cache.__index = Cache

function Cache:_GetNew(Amount: number, Warn: boolean)
	if Warn then
		warn(`ObjectCache: Cache retrieval exceeded preallocated amount! expanding by {Amount}...`)
	end

	local FreeObjectsContainer = self._FreeObjects
	local InitialLength = #self._FreeObjects
	local CacheHolder = self.CacheHolder

	local IsTemplateModel = self._IsTemplateModel
	local Template: Model | BasePart = self._Template

	local TargetParts = table.create(Amount)
	local TargetCFrames = table.create(Amount)
	local AddedObjects = table.create(Amount)
	for Index = InitialLength + 1, InitialLength + Amount do
		local Object = Template:Clone()
		local ObjectRoot: BasePart = if IsTemplateModel then (Object:: Model).PrimaryPart:: BasePart else Object:: BasePart

		--[[
		ObjectRoot.CFrame = FAR_AWAY_CFRAME

		local Motor6D = Instance.new("Motor6D")
		Motor6D.Transform = FAR_AWAY_CFRAME
		Motor6D.Part0 = WorldAnchor
		Motor6D.Part1 = ObjectRoot;
		Motor6D.Parent = ObjectRoot;
		--]]

		FreeObjectsContainer[Index] = ObjectRoot

		local OffsetIndex = Index - InitialLength
		TargetParts[OffsetIndex] = ObjectRoot
		TargetCFrames[OffsetIndex] = FAR_AWAY_CFRAME
		AddedObjects[OffsetIndex] = Object
	end

	workspace:BulkMoveTo(TargetParts, TargetCFrames, Enum.BulkMoveMode.FireCFrameChanged)

	for _, Object in AddedObjects do
		(Object:: Instance).Parent = CacheHolder
	end

	return table.remove(FreeObjectsContainer)
end

function Cache:GetPart(PartCFrame: CFrame?): BasePart
	local Part = table.remove(self._FreeObjects) or self:_GetNew(self._ExpandAmount, true)

	self._Objects[Part] = nil
	if PartCFrame then
		UpdateMap[Part] = PartCFrame
	end

	return Part
end
function Cache:ReturnPart(Part: BasePart)
	if self._Objects[Part] then
		return
	end

	self._Objects[Part] = true

	table.insert(self._FreeObjects, Part)

	UpdateMap[Part] = FAR_AWAY_CFRAME
end

function Cache:Update()
	UpdateMovement()
end

function Cache:ExpandCache(Amount: number)
	assert(typeof(Amount) ~= "number" or Amount >= 0, `Invalid argument #1 to 'ObjectCache:ExpandCache' (positive number expected, got {typeof(Amount)})`)
	self:_GetNew(Amount, false)
end
function Cache:SetExpandAmount(Amount: number)
	assert(typeof(Amount) ~= "number" or Amount > 0, `Invalid argument #1 to 'ObjectCache:SetExpandAmount' (positive number expected, got {typeof(Amount)})`)
	self._ExpandAmount = Amount
end

function Cache:IsInUse(Object: BasePart): boolean
	return self._Objects[Object] == nil
end

function Cache:Destroy()
	self.CacheHolder:Destroy()
end

local function GetCacheContainer()
	local CacheHolder = Instance.new("Folder")
	CacheHolder.Name = "ObjectCache"

	return CacheHolder
end

local Constructor = {}
function Constructor.new(Template: BasePart | Model, CacheSize: number?, CachesContainer: Instance?)
	local TemplateType = typeof(Template)
	assert(TemplateType == "Instance", `Invalid argument #1 to 'ObjectCache.new' (BasePart expected, got {TemplateType})`)

	assert(Template:IsA("BasePart") or Template:IsA("Model"), `Invalid argument #1 to 'ObjectCache.new' (BasePart or Model expected, got {Template.ClassName})`)
	assert(Template.Archivable, `ObjectCache: Cannot use template object provided, as it has Archivable set to false.`)
	if Template:IsA("Model") then
		assert(Template.PrimaryPart ~= nil, `Invalid Template provided to 'ObjectCache.new': Model has no PrimaryPart set!`)
	end

	local CacheSizeType = typeof(CacheSize)
	assert(CacheSize == nil or CacheSizeType == "number", `Invalid argument #2 to 'ObjectCache.new' (number expected, got {CacheSizeType})`)
	assert(CacheSize == nil or CacheSize >= 0, `Invalid argument #2 to 'ObjectCache.new' (positive number expected, got {CacheSize})`)

	local ContainerType = typeof(CachesContainer)
	assert(CachesContainer == nil or ContainerType == "Instance", `Invalid argument #3 to 'ObjectCache.new' (Instance expected, got {ContainerType})`)

	local PreallocAmount = CacheSize or 10
	local CacheParent = GetCacheContainer()

	local Objects: {[BasePart]: boolean} = {}
	local FreeObjects: {BasePart | Model} = table.create(PreallocAmount)

	local TargetParts = table.create(PreallocAmount)

	local IsTemplateModel = Template:IsA("Model")
	for Index = 1, PreallocAmount do
		local Object = Template:Clone()
		local ObjectRoot: BasePart = if IsTemplateModel then (Object:: Model).PrimaryPart:: BasePart else Object:: BasePart

		FreeObjects[Index] = Object
		TargetParts[Index] = ObjectRoot

		ObjectRoot.CFrame = FAR_AWAY_CFRAME;

		--[[
		local Motor6D = Instance.new("Motor6D")

		Motor6D.Transform = FAR_AWAY_CFRAME
		Motor6D.Part0 = WorldAnchor
		Motor6D.Part1 = ObjectRoot;
		Motor6D.Parent = ObjectRoot;
		--]]

		(Object:: Instance).Parent = CacheParent
	end

	CacheParent.Parent = CachesContainer or workspace

	return setmetatable({
		CacheHolder = CacheParent,
		_ExpandAmount = EXPAND_BY_AMOUNT,
		_Template = Template,
		_FreeObjects = TargetParts,
		_Objects = Objects,
		_IsTemplateModel = IsTemplateModel,
		_PreallocatedAmount = PreallocAmount,
	}, Cache)
end

return Constructor
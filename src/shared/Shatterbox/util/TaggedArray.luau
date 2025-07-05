--!strict
--!native
--!optimize 2

--#selene: allow(shadowing)

--[[ USAGE:

	Call the module with the tag you want. Example: TaggedArray("Destructibles") returns a continuously updating array of destructibles.

	Call TaggedArray.Destroy(tag) to stop the continous updates associated with the array.

	Caching is used, so separate calls requesting the same tagged array will recieve the same tagged array (instead of new arrays and connections each time)
]]


local CollectionService = game:GetService("CollectionService")

type TaggedArrayInternal = {
	Array : {Instance},
	Connections : {
		Added : RBXScriptConnection, 
		Removed : RBXScriptConnection
	}
}

local TaggedArrays = {} :: { [string] : TaggedArrayInternal }

local function GetTaggedArray(_, tag : string) : {Instance}
	local found = TaggedArrays[tag]
	if found then return found.Array end

	local taggedArray = CollectionService:GetTagged(tag)

	TaggedArrays[tag] = { 
		Array = taggedArray,

		Connections = {
			Added =
			      CollectionService:GetInstanceAddedSignal(tag):Connect(function(i : Instance)
		 	             table.insert(taggedArray, i)
			      end),
			Removed =
			      CollectionService:GetInstanceRemovedSignal(tag):Connect(function(i : Instance)
					local found = table.find(taggedArray, i)
					if not found then return end
					table.remove(taggedArray, found)
			      end)
		}
	}

	return taggedArray
end

local TaggedArray = setmetatable({}, { __call = GetTaggedArray })

function TaggedArray.Destroy(tag : string)
	local found = TaggedArrays[tag]
	if not found then return end
	local connections = found.Connections
	connections.Added:Disconnect()
	connections.Removed:Disconnect()
	TaggedArrays[tag] = nil
end

return TaggedArray
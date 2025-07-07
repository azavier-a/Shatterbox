--[[ How to use:

	Place Shatterbox anywhere as a descendant of ReplicatedStorage (or in the "shared" directory if you are using Rojo)

	Require the Shatterbox.Main module at initalization on the server side. (You can use client-only features afterward if you want)

	This library assumes STATIC objects (i.e, buildings, the ground, walls). Not yet fully supporting moving objects.

	Giving a part the GridSize attribute will override the default GridSize.
	| the GridSize passed to destruction functions will override this attribute.

	To create your own debris effects, use Shatterbox.RegisterOnVoxelDestruct(name, func)
	| if you need one effect to do different things on server side and client side
	| you have to register it in this scipt using the local function RegisterOnVoxelDestruct(name, clientFunc, serverFunc)
	| see below (around line 120) for an example.

	Using a debris effect requires you to set OnVoxelDestruct = name

	CreateHitbox() will create a hitbox object very similar to a VoxBreaker Hitbox.
	I suggest you use this to get a feel for the module, it is very user-friendly.

	OnVoxelDestruct parameters explained (anything past the 3rd is supplied via DestructParams, examples are above):

		- voxel is the part that is to be destroyed

		- dirtyParent is the source model which is affected by smooth cleanup. See "Rough" for an example on the usage.

		- cuttingPart is the cloned hitbox which destroyed "voxel" in the state that it was in when it queued the operation. See "Rough" for an example on the usage.

		- isEdge is true if the voxel is along the edge of the intersection.

		- any parameters past isEdge are defined by the DestructParams array.
]]
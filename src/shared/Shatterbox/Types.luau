export type Hitbox = {
	CFrame : CFrame,
	Size : Vector3,
	Shape : Enum.PartType
}

export type OnDestructCompleted = () -> ()

export type OnVoxelDestruct = (voxel : Part, dirtyParent : Model, cuttingPart : Hitbox, isEdge : boolean, any...) -> ()

export type ImaginaryBox = {

	CFrame : CFrame, -- the CFrame of the box
	Size : Vector3, -- the Size of the box

	Original : Part, -- the original part before this iteration of Imaginary touched it

	DirtyParent : Model, -- the target of smooth cleanup for this box
	GridSize : number -- the GridSize that was applied to this box
}

export type ImaginaryVoxel = ImaginaryBox & {

	isEdge : boolean -- whether or not this box lies along the edge of the intersection
}

type SharedDestructionParams = {

	FilterTagged : (string | {string})?,
	GridSize : number?,
	CleanupDelay : number?,
	SkipEncapsulatedVoxels : boolean?
}

type UsesOnVoxelDestruct = {
	OnVoxelDestruct : string?,
	DestructParameters : { any },

	OnDestructCompleted : OnDestructCompleted?
}

export type InternalImaginaryParams = SharedDestructionParams & { CuttingPart : Hitbox }
export type ImaginaryDestructionParams = SharedDestructionParams & {

	CuttingPart : ((Part?) | (Model?) | (Hitbox?))?,

	CFrame : CFrame?,
	Size : Vector3?,
	Shape : Enum.PartType?
}

export type InternalDestructionParams = InternalImaginaryParams & UsesOnVoxelDestruct
export type DestructionParams = ImaginaryDestructionParams & UsesOnVoxelDestruct

return {}
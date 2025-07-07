export type OnVoxelDestruct = (voxel : Part, dirtyParent : Model, cuttingPart : BasePart, isEdge : boolean, any...) -> ()

export type OnDestructCompleted = () -> ()


export type ImaginaryBox = {CFrame : CFrame, Size : Vector3, Original : Part, DirtyParent : Model, GridSize : number}

export type ImaginaryVoxel = ImaginaryBox & {isEdge : boolean}


export type DestructionParams = {

	CuttingPart : (Part | Model)?,

	CFrame : CFrame?,
	Size : Vector3?,
	Shape : Enum.PartType?,

	FilterTagged : (string | {string})?,
	GridSize : number?,
	CleanupDelay : number?,
	SkipEncapsulatedVoxels : boolean?,

	OnVoxelDestruct : string?,
	DestructParameters : { any },

	OnDestructCompleted : OnDestructCompleted?
}


return {}
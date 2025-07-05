--!strict
--!native
--!optimize 2
--#selene: allow(multiple_statements)

--[[ USAGE


	local visualizer = HitboxVisualizer.Create(hitbox)

	-- set properties (visualizer.property = someValue)


	-- shows the hitbox once
	visualizer:ShowOnce(dur, useFade)

	-- shows the hitbox constantly
	visualizer:StartShowing()

	-- stops showing the hitbox constantly
	visualizer:StopShowing()
]]

local ShatterboxTemporary = workspace:FindFirstChild("ShatterboxTemporary")

assert(ShatterboxTemporary, "You must require the Shatterbox.Main module before using this one.")

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local FadeParams = { Transparency = 1 }

local HitboxVisualizer = {}

type HitboxType = { CFrame : CFrame, Size : Vector3, Shape : Enum.PartType }

function HitboxVisualizer.Create(hitbox : HitboxType)

	local visualizer = {}
	visualizer.Transparency = 0.5 :: number
	visualizer.Color = Color3.new(1) :: Color3

	visualizer.DefualtOnceDuration = 2
	visualizer.DefaultFade = true

	local vPart = Instance.new("Part")
	vPart.Material = Enum.Material.SmoothPlastic
	vPart.Anchored = true
	vPart.CanCollide = false
	vPart.CanTouch = false
	vPart.CanQuery = false
	vPart.Name = "VisualizedHitbox"

	function visualizer:ShowOnce(duration : number?, useFade : boolean?)
		if not duration then duration = visualizer.DefualtOnceDuration end
		if useFade == nil then useFade = visualizer.DefaultFade end

		local v = vPart:Clone()
		v.Color = visualizer.Color
		v.Transparency = visualizer.Transparency
		v.Shape = hitbox.Shape
		v.Size = hitbox.Size
		v.CFrame = hitbox.CFrame
		v.Parent = ShatterboxTemporary

		if not useFade then return end

		local tween = TweenService:Create(v, TweenInfo.new(duration, Enum.EasingStyle.Linear), FadeParams)

		tween.Completed:Connect(function() v:Destroy(); end)

		tween:Play()
	end


	local ccon : RBXScriptConnection


	function visualizer:StartShowing()
		if ccon then return end
		vPart.Parent = ShatterboxTemporary
		ccon = RunService.PreSimulation:Connect(function()
			vPart.Color = visualizer.Color
			vPart.Transparency = visualizer.Transparency
			vPart.Shape = hitbox.Shape
			vPart.Size = hitbox.Size
			vPart.CFrame = hitbox.CFrame
		end)
	end


	function visualizer:StopShowing()
		if not ccon then return end
		ccon:Disconnect()
		ccon = nil
		vPart.Parent = nil
	end


	return visualizer
end




return HitboxVisualizer
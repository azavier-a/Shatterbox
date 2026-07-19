--#selene: allow(unused_variable)
--#selene: allow(multiple_statements)

-- This Script instance has a RunContext of "Client", so when any client loads it for the first time (it's in ReplicatedStorage), this script runs.

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

repeat RunService.Heartbeat:Wait() until ReplicatedStorage:FindFirstChild("SHATTERBOX_BLINK_RELIABLE_REMOTE")

local Shatterbox = require(script.Parent.Parent.Parent:WaitForChild("Main"))
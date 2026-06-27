--[[
	EffectsSystem
	-------------
	Death visuals: a dust puff, a flop into ragdoll, and a fade-out. The model
	itself is destroyed by UnitManager after Config.CorpseLifetime — this just
	makes that corpse look good on the way out.
]]

local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local EffectsSystem = {}

-- Burst of dust at the body.
local function dustPuff(root)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Config.Death.PuffColor)
	emitter.Size = NumberSequence.new(1.5)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(3, 7)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(Config.Death.PuffAmount)
end

-- Convert the rig's rigid joints into loose sockets so it flops over.
local function ragdoll(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0

			local a1 = Instance.new("Attachment")
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.Parent = motor.Part0

			motor:Destroy()
		end
	end
end

-- Fade every part to invisible over the corpse's lifetime.
local function fadeOut(model)
	local info = TweenInfo.new(Config.CorpseLifetime, Enum.EasingStyle.Linear)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			TweenService:Create(part, info, { Transparency = 1 }):Play()
		elseif part:IsA("Decal") then
			TweenService:Create(part, info, { Transparency = 1 }):Play()
		end
	end
end

function EffectsSystem.PlayDeath(unit)
	local model = unit.Model
	if not model or not model.Parent then
		return
	end

	if unit.Root then
		dustPuff(unit.Root)
	end
	if Config.Death.Ragdoll then
		ragdoll(model)
	end
	fadeOut(model)
end

return EffectsSystem

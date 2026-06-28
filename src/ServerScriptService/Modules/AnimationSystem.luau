--[[
	AnimationSystem
	---------------
	Server-driven animation for the NPC soldiers (R6).
	  • Walk/idle: loads the default R6 animation tracks on each unit's Animator
	    and switches between them based on Humanoid.Running (event-driven, no
	    per-tick cost). Server-played tracks replicate to every client.
	  • Attack: a quick procedural arm swing (rotating the Right Shoulder joint)
	    so we don't need a custom uploaded animation.
]]

local AnimationSystem = {}

-- Roblox's default R6 animations (free to load).
local WALK_ID = "rbxassetid://180426354"
local IDLE_ID = "rbxassetid://180435571"

local function loadTrack(animator, id)
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	return ok and track or nil
end

function AnimationSystem.Setup(unit)
	local humanoid = unit.Humanoid
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local walk = loadTrack(animator, WALK_ID)
	local idle = loadTrack(animator, IDLE_ID)
	if walk then
		walk.Looped = true
	end
	if idle then
		idle.Looped = true
		idle:Play(0.2)
	end

	-- Running fires with the current movement speed whenever it changes.
	humanoid.Running:Connect(function(speed)
		if not unit.Alive then
			return
		end
		if speed > 0.5 then
			if walk and not walk.IsPlaying then
				walk:Play(0.15)
			end
			if idle then
				idle:Stop(0.15)
			end
		else
			if idle and not idle.IsPlaying then
				idle:Play(0.15)
			end
			if walk then
				walk:Stop(0.15)
			end
		end
	end)
end

-- A quick chop with the right arm (procedural, no uploaded asset needed).
function AnimationSystem.PlayAttack(unit)
	if unit._swinging then
		return
	end
	local model = unit.Model
	local torso = model and model:FindFirstChild("Torso")
	local shoulder = torso and torso:FindFirstChild("Right Shoulder")
	if not shoulder then
		return
	end
	unit._swinging = true
	local base = shoulder.C0
	shoulder.C0 = base * CFrame.Angles(math.rad(-80), 0, 0)
	task.delay(0.18, function()
		if shoulder and shoulder.Parent then
			shoulder.C0 = base
		end
		unit._swinging = false
	end)
end

return AnimationSystem

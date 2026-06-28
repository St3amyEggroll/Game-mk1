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
	if not ok then
		warn("[AnimationSystem] Failed to load animation", id, track)
	end
	return ok and track or nil
end

function AnimationSystem.Setup(unit)
	local humanoid = unit.Humanoid
	if not humanoid then
		return
	end
	-- Animator must be created server-side to replicate NPC animations.
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

	unit.Anim = { walk = walk, idle = idle, state = "idle" }
end

-- Called each tick: pick walk vs idle from the humanoid's actual movement. This
-- is deterministic (no reliance on the Running event, which can miss switches
-- around MoveTo timeouts / rapid start-stop).
function AnimationSystem.Update(unit)
	local anim = unit.Anim
	if not anim then
		return
	end
	local humanoid = unit.Humanoid
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	if moving then
		if anim.state ~= "walk" then
			anim.state = "walk"
			if anim.walk then
				anim.walk:Play(0.15)
			end
			if anim.idle then
				anim.idle:Stop(0.15)
			end
		end
		-- Scale the cycle to the unit's speed, so faster units read as running.
		if anim.walk then
			anim.walk:AdjustSpeed(math.clamp(humanoid.WalkSpeed / 14, 0.7, 2.4))
		end
	elseif anim.state ~= "idle" then
		anim.state = "idle"
		if anim.idle then
			anim.idle:Play(0.15)
		end
		if anim.walk then
			anim.walk:Stop(0.15)
		end
	end
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

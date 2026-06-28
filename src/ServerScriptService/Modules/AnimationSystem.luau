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

-- Roblox's default animations (free to load). The IDs differ by rig type, so we
-- pick the set that matches each NPC's Humanoid.RigType (R6 vs R15) -- using the
-- wrong set is the usual reason "animations don't play".
local SETS = {
	[Enum.HumanoidRigType.R6] = {
		walk = "rbxassetid://180426354",
		idle = "rbxassetid://180435571",
	},
	[Enum.HumanoidRigType.R15] = {
		walk = "rbxassetid://507777826",
		idle = "rbxassetid://507766666",
	},
}

local logged = false

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

	local set = SETS[humanoid.RigType] or SETS[Enum.HumanoidRigType.R6]
	local walk = loadTrack(animator, set.walk)
	local idle = loadTrack(animator, set.idle)
	if walk then
		walk.Looped = true
	end
	if idle then
		idle.Looped = true
		idle:Play(0.2)
	end

	unit.Anim = { walk = walk, idle = idle, state = "idle" }

	-- One-time diagnostic so you can confirm in Output what's happening.
	if not logged then
		logged = true
		print(("[AnimationSystem] rig=%s  walkLoaded=%s  idleLoaded=%s"):format(
			tostring(humanoid.RigType),
			tostring(walk ~= nil),
			tostring(idle ~= nil)
		))
	end
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

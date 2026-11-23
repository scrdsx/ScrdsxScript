-- Maybach suspension: air suspension that moves the body of the car you drive smoothly up and down, like the lift and the
-- Magic Body Control of a real Maybach. It eases every SpringConstraint's rest length (FreeLength) toward a target each frame.
-- Modes:
--   Float      the whole body rises and sinks slowly (one smooth breath every Period seconds)
--   Wave       the corners rise one after another, so the body rolls round in a slow wave
--   Comfort    raised when slow (kerbs, parking), lowers itself smoothly as you speed up
--   Lift only  stays put; the lift key raises / lowers the body
-- Level body (all modes): leans into turns and keeps the nose up when braking, the tail up when accelerating.
-- The driver owns the car's physics, so the height change is real physics (others see the car move too).
-- UNTESTED in game: assumes the car's suspension is SpringConstraints (the VW Golf probe showed 4: Free 2, Max 5).
local RunService = game:GetService("RunService")
local Vehicle = __import("vehicle/vehicle")

local Maybach = {
	Enabled = false, Mode = "Float", Lift = 1.5, Period = 4, Smooth = 3, Level = true, LevelAmount = 0.6,
	Lifted = false, Info = "off",
}
Maybach.Modes = { "Float", "Wave", "Comfort", "Lift only" }

local springs = {} -- { sp, free, min, max, cur, fx (+1 front / -1 rear), sx (+1 right / -1 left) }
local car
local conn
local t0 = os.clock()
local lastVel, latS, lonS = nil, 0, 0
local infoAt = 0

local function release()
	for _, o in ipairs(springs) do
		local sp = o.sp
		if sp.Parent then pcall(function() sp.MinLength = o.min; sp.MaxLength = o.max; sp.FreeLength = o.free end) end
	end
	springs = {}
	Vehicle.SpringsBusy = false
end

local function sign(x) return x >= 0 and 1 or -1 end

local function scan(m, seat)
	release()
	car = m
	lastVel, latS, lonS = nil, 0, 0
	if not m or not seat then return end
	local cf = seat.CFrame
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("SpringConstraint") then
			local sv = Vehicle.SavedFree and Vehicle.SavedFree(d)
			local o = {
				sp = d, cur = 0,
				free = sv and sv[1] or d.FreeLength, min = sv and sv[2] or d.MinLength, max = sv and sv[3] or d.MaxLength,
			}
			-- which corner: from the spring's position in the seat's frame (LookVector = -Z = front)
			local a0, a1 = d.Attachment0, d.Attachment1
			local pos = (a0 and a1) and (a0.WorldPosition + a1.WorldPosition) / 2 or (a0 or a1) and (a0 or a1).WorldPosition or cf.Position
			local lp = cf:PointToObjectSpace(pos)
			o.fx, o.sx = sign(-lp.Z), sign(lp.X)
			springs[#springs + 1] = o
		end
	end
	Vehicle.SpringsBusy = #springs > 0
end

local function step(dt)
	if not Maybach.Enabled then return end
	local m, seat = Vehicle.CurrentCar()
	if m ~= car then scan(m, seat) end
	local now = os.clock()
	if not m or #springs == 0 then
		if now - infoAt > 0.5 then infoAt = now; Maybach.Info = m and "no springs on this car" or "sit in a car" end
		return
	end
	if dt <= 0 then return end

	-- the car's motion in its own frame, smoothed (accelerations are noisy frame to frame)
	local vel = seat.AssemblyLinearVelocity
	local cf = seat.CFrame
	if lastVel then
		local a = (vel - lastVel) / dt
		local ka = 1 - math.exp(-dt * 5)
		latS = latS + (a:Dot(cf.RightVector) - latS) * ka
		lonS = lonS + (a:Dot(cf.LookVector) - lonS) * ka
	end
	lastVel = vel
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	local H, mode = Maybach.Lift, Maybach.Mode
	local t = now - t0
	local w = 2 * math.pi / math.max(Maybach.Period, 0.5)
	local common = (Maybach.Lifted and H or 0) + ((Vehicle.Enabled and Vehicle.UseSprings) and Vehicle.Height or 0)
	if mode == "Float" then
		common = common + H * (0.5 - 0.5 * math.cos(w * t))
	elseif mode == "Comfort" then
		common = common + H * (1 - math.clamp(speed / 70, 0, 1))
	end
	local L = Maybach.Level and Maybach.LevelAmount or 0
	local roll = L * math.clamp(latS / 40, -1, 1)  -- + = turning right
	local pitch = L * 0.7 * math.clamp(lonS / 40, -1, 1) -- + = accelerating, - = braking
	local k = 1 - math.exp(-dt * Maybach.Smooth)

	local sum = 0
	for _, o in ipairs(springs) do
		local target = common
		if mode == "Wave" then
			local ph = (o.fx > 0 and 0 or math.pi) + (o.sx > 0 and math.pi / 2 or 0)
			target = target + H * (0.5 - 0.5 * math.cos(w * t + ph))
		end
		-- lean in: drop the inside of the turn, lift the outside; keep the nose up when braking, the tail up when accelerating
		target = target - roll * o.sx - pitch * o.fx
		target = math.max(target, o.min - o.free + 0.1)
		o.cur = o.cur + (target - o.cur) * k
		sum = sum + o.cur
		local sp = o.sp
		if sp.Parent then
			local fl = o.free + o.cur
			if math.abs(sp.FreeLength - fl) > 0.004 then
				local room = fl + (o.max - o.free)
				if sp.MaxLength < room then sp.MaxLength = room end
				sp.FreeLength = fl
			end
		end
	end
	if now - infoAt > 0.5 then
		infoAt = now
		Maybach.Info = ("%s  ·  %d springs  ·  %+.1f st%s"):format(m.Name, #springs, sum / #springs, Maybach.Lifted and "  ·  lifted" or "")
	end
end

function Maybach.SetEnabled(v)
	Maybach.Enabled = v
	if not v then
		release(); car = nil
		Maybach.Info = "off"
	end
end

function Maybach.ToggleLift()
	Maybach.Lifted = not Maybach.Lifted
	return Maybach.Lifted
end

function Maybach.Start()
	if conn then return end
	conn = RunService.Heartbeat:Connect(function(dt) step(dt) end)
end

function Maybach.Destroy()
	if conn then conn:Disconnect(); conn = nil end
	release(); car = nil
end

return Maybach

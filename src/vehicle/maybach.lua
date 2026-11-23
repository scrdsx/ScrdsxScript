-- Maybach suspension: air suspension that moves the body of the car you drive, like the lift / Magic Body Control of a real
-- Maybach. It sets every SpringConstraint's rest length (FreeLength) each frame.
--
-- Movement is a cycle: rise (eased) -> hold at the top -> drop (0 s = instant, the body just falls) -> hold at the bottom.
-- The cycle is drawn exactly (no smoothing lag), so a drop really is instant. Only the slow parts (comfort height, the lift
-- key, leaning into turns) are smoothed.
-- Modes:
--   Pulse          rise, then drop (instant by default), repeat
--   Float          rise and sink at the same speed
--   Hop            short hydraulic hops
--   Wave           the corners go one after another, the body rolls round
--   Side to side   left and right take turns
--   Rock           front and rear take turns
--   Three wheel    one corner up and held (lowrider pose)
--   Comfort        raised when slow, lowers itself as you speed up
--   Lift only      nothing moves until the lift key
-- The driver owns the car's physics, so others see the body move too.
-- UNTESTED in game: assumes the car's suspension is SpringConstraints (the VW Golf probe showed 4: Free 2, Max 5).
local RunService = game:GetService("RunService")
local Vehicle = __import("vehicle/vehicle")

local Maybach = {
	Enabled = false, Mode = "Pulse", Lift = 1.5,
	Rise = 0.9, HoldTop = 0, Drop = 0, HoldBottom = 0.6, -- seconds
	Corners = "All", Corner = "Front left", StillOnly = false, Stance = 0,
	Smooth = 4, Level = true, LevelAmount = 0.6,
	Lifted = false, Info = "off",
}
Maybach.Modes = { "Pulse", "Float", "Hop", "Wave", "Side to side", "Rock", "Three wheel", "Comfort", "Lift only" }
Maybach.CornerSets = { "All", "Front", "Rear", "Left", "Right" }
Maybach.CornerNames = { "Front left", "Front right", "Rear left", "Rear right" }

local springs = {} -- { sp, free, min, max, slow, fx (+1 front / -1 rear), sx (+1 right / -1 left) }
local car
local conn
local t0 = os.clock()
local lastVel, latS, lonS = nil, 0, 0
local env = 1 -- 0..1: fades the cycle out while driving when "only when standing still" is on
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
				sp = d, slow = 0,
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

local function ease(x) return 0.5 - 0.5 * math.cos(math.pi * math.clamp(x, 0, 1)) end

-- one cycle, 0..1 height at time tau (seconds into the cycle)
local function profile(tau, rise, top, drop, bottom)
	local total = rise + top + drop + bottom
	if total <= 0.01 then return 0 end
	tau = tau % total
	if tau < rise then return ease(tau / rise) end
	tau = tau - rise
	if tau < top then return 1 end
	tau = tau - top
	if tau < drop then return 1 - ease(tau / drop) end
	return 0
end

local function cycleTiming(mode)
	local M = Maybach
	if mode == "Hop" then return 0.12, 0.04, 0, 0.35 end
	-- Float and the moving-corner modes go down as smoothly as they come up
	if mode == "Float" or mode == "Wave" or mode == "Side to side" or mode == "Rock" then return M.Rise, M.HoldTop, M.Rise, M.HoldBottom end
	return M.Rise, M.HoldTop, M.Drop, M.HoldBottom -- Pulse
end

local function inSet(o, set)
	if set == "Front" then return o.fx > 0 end
	if set == "Rear" then return o.fx < 0 end
	if set == "Left" then return o.sx < 0 end
	if set == "Right" then return o.sx > 0 end
	return true
end

local function isCorner(o, name)
	local f = name:find("Front") and 1 or -1
	local s = name:find("right") and 1 or -1
	return o.fx == f and o.sx == s
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

	local M = Maybach
	local H, mode = M.Lift, M.Mode
	local t = now - t0
	local k = 1 - math.exp(-dt * M.Smooth)
	local envTarget = (M.StillOnly and speed > 4) and 0 or 1
	env = env + (envTarget - env) * (1 - math.exp(-dt * 4))

	-- slow part (smoothed): stance, lift key, comfort height, the Suspension module's own raise
	local slowCommon = -M.Stance + ((Vehicle.Enabled and Vehicle.UseSprings) and Vehicle.Height or 0)
	if mode == "Comfort" then slowCommon = slowCommon + H * (1 - math.clamp(speed / 70, 0, 1)) end
	local L = M.Level and M.LevelAmount or 0
	local roll = L * math.clamp(latS / 40, -1, 1)          -- + = turning right
	local pitch = L * 0.7 * math.clamp(lonS / 40, -1, 1)   -- + = accelerating, - = braking

	local rise, top, drop, bottom = cycleTiming(mode)
	local total = rise + top + drop + bottom
	local cycling = mode == "Pulse" or mode == "Float" or mode == "Hop" or mode == "Wave" or mode == "Side to side" or mode == "Rock"
	local hopH = mode == "Hop" and H * 0.7 or H

	local sum = 0
	for _, o in ipairs(springs) do
		local slow = slowCommon - roll * o.sx - pitch * o.fx
		if M.Lifted and inSet(o, M.Corners) then slow = slow + H end
		if mode == "Three wheel" and isCorner(o, M.Corner) then slow = slow + H * 1.6 end
		o.slow = o.slow + (slow - o.slow) * k

		-- fast part (exact): the cycle
		local cyc = 0
		if cycling then
			local shift = 0
			if mode == "Wave" then
				shift = ((o.fx > 0 and 0 or 0.5) + (o.sx > 0 and 0.25 or 0)) * total
			elseif mode == "Side to side" then
				shift = (o.sx > 0 and 0.5 or 0) * total
			elseif mode == "Rock" then
				shift = (o.fx > 0 and 0 or 0.5) * total
			end
			local useSet = mode == "Pulse" or mode == "Float" or mode == "Hop"
			if not useSet or inSet(o, M.Corners) then
				cyc = hopH * env * profile(t + shift, rise, top, drop, bottom)
			end
		end

		local off = math.max(o.slow + cyc, o.min - o.free + 0.1)
		sum = sum + off
		local sp = o.sp
		if sp.Parent then
			local fl = o.free + off
			if math.abs(sp.FreeLength - fl) > 0.004 then
				local room = fl + (o.max - o.free)
				if sp.MaxLength < room then sp.MaxLength = room end
				sp.FreeLength = fl
			end
		end
	end
	if now - infoAt > 0.5 then
		infoAt = now
		M.Info = ("%s  ·  %d springs  ·  %+.1f st%s%s"):format(m.Name, #springs, sum / #springs, M.Lifted and "  ·  lifted" or "",
			(M.StillOnly and env < 0.5 and cycling) and "  ·  paused (driving)" or "")
	end
end

function Maybach.SetEnabled(v)
	Maybach.Enabled = v
	if not v then
		release(); car = nil
		Maybach.Info = "off"
	else
		t0 = os.clock() -- start every cycle from the bottom
	end
end

function Maybach.SetLifted(v) Maybach.Lifted = v; return v end
function Maybach.ToggleLift() return Maybach.SetLifted(not Maybach.Lifted) end
function Maybach.Restart() t0 = os.clock() end

function Maybach.Start()
	if conn then return end
	conn = RunService.Heartbeat:Connect(function(dt) step(dt) end)
end

function Maybach.Destroy()
	if conn then conn:Disconnect(); conn = nil end
	release(); car = nil
end

return Maybach

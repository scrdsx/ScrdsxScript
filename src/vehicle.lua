-- Vehicle mods. Suspension: raises every SpringConstraint on the car you are sitting in by `height` studs.
-- UNTESTED: assumes the car uses SpringConstraints. Run tools/car_probe.lua in a car to confirm the real setup.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Vehicle = { Height = 0, MaxHeight = 20, Info = "no car" }
local lp = Players.LocalPlayer
local model, saved = nil, {} -- saved[spring] = { FreeLength, MinLength, MaxLength }
local conn, acc = nil, 0

local function currentCar()
	local c = lp.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local s = h and h.SeatPart
	if not s then return nil end
	local m = s:FindFirstAncestorOfClass("Model")
	while m and m.Parent and m.Parent:IsA("Model") do m = m.Parent end
	return m
end

local function restore()
	for sp, o in pairs(saved) do
		if sp.Parent then pcall(function() sp.MinLength = o[2]; sp.MaxLength = o[3]; sp.FreeLength = o[1] end) end
	end
	saved = {}
end

local function apply()
	local m = currentCar()
	if m ~= model then restore(); model = m end
	if not m then Vehicle.Info = "no car (sit in one)"; return end
	local n = 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("SpringConstraint") then
			n += 1
			local o = saved[d]
			if not o then o = { d.FreeLength, d.MinLength, d.MaxLength }; saved[d] = o end
			-- widen the limits first so the new length is never clamped away
			d.MaxLength = math.max(o[3], o[1] + Vehicle.Height + (o[3] - o[1]))
			d.MinLength = o[2]
			d.FreeLength = o[1] + Vehicle.Height
		end
	end
	Vehicle.Info = n > 0 and (m.Name .. ": " .. n .. " springs") or (m.Name .. ": no SpringConstraints")
end

function Vehicle.SetHeight(v) Vehicle.Height = math.clamp(v, 0, Vehicle.MaxHeight); apply() end

function Vehicle.Start()
	conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then return end
		acc = 0
		apply() -- re-applied so a respawned or swapped car is picked up
		if Vehicle.Changed then Vehicle.Changed() end
	end)
end

function Vehicle.Destroy()
	if conn then conn:Disconnect(); conn = nil end
	restore()
end

return Vehicle

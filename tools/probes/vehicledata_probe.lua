-- VehicleData / VehicleDrive probe. Run it SITTING IN YOUR CAR on a long straight road.
--  1) finds the game's live VehicleData + VehicleDrive objects for your car (heap scan) and dumps their fields
--  2) tests whether setting engineLevel=6 (locally) changes their acceleration values
--  3) two timed runs FROM A STANDSTILL: A = normal, B = with direct overrides (acceleration x3, maxSpeed x2)
-- It will tell you when to hold W. Report goes to the clipboard. getgenv().ProbeSeconds = 8 (seconds per run).
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local PHASE = tonumber((getgenv and getgenv().ProbeSeconds) or 8)
local out = {}
local function log(s) out[#out + 1] = s end
local function short(v)
	local t = typeof(v)
	if t == "Instance" then return v:GetFullName() end
	if t == "table" then
		local parts, n = {}, 0
		for k, x in pairs(v) do
			n = n + 1
			if n <= 8 and (type(x) == "number" or type(x) == "string" or type(x) == "boolean") then parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
		end
		return "table{" .. table.concat(parts, ", ") .. (n > 8 and ", ..." or "") .. "}"
	end
	if t == "function" then return "function" end
	local s = tostring(v)
	return #s > 60 and s:sub(1, 60) .. "..." or s
end
print("[vd] started")

local char = lp.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
local seat = hum and hum.SeatPart
local car
if seat then
	car = seat:FindFirstAncestorOfClass("Model")
	while car and car.Parent and car.Parent:IsA("Model") do car = car.Parent end
end
if not car then print("[vd] sit in your car first") return end
log("car: " .. car:GetFullName() .. "  Config=" .. tostring(car:GetAttribute("Config")))
log(("levels: engine=%s brakes=%s armor=%s"):format(tostring(car:GetAttribute("engineLevel")), tostring(car:GetAttribute("brakesLevel")), tostring(car:GetAttribute("armorLevel"))))

-- 1. heap scan
print("[vd] scanning heap...")
local vds, drives = {}, {}
local function refersToCar(t)
	for k, v in pairs(t) do
		if v == car then return true end
		if typeof(v) == "Instance" and (v == seat or v:IsDescendantOf(car)) then return true end
	end
	return false
end
local okgc, heap = pcall(getgc, true)
local iter = 0
for _, t in ipairs(okgc and heap or {}) do
	iter = iter + 1
	if iter % 3000 == 0 then task.wait() end
	if type(t) == "table" then
		local acc = rawget(t, "acceleration")
		if type(acc) == "number" then
			if rawget(t, "damageMultiplier") ~= nil and #vds < 8 then vds[#vds + 1] = t
			elseif rawget(t, "bodyMass") ~= nil and #drives < 8 then drives[#drives + 1] = t end
		end
	end
end
local function dump(label, t)
	log(("%s  (refersToCar=%s)"):format(label, tostring(refersToCar(t))))
	local n = 0
	for k, v in pairs(t) do
		n = n + 1
		if n > 45 then log("    ...") break end
		log(("    %s = %s (%s)"):format(short(k), short(v), typeof(v)))
	end
end
log(("-- found %d VehicleData-like and %d VehicleDrive-like tables --"):format(#vds, #drives))
for i, t in ipairs(vds) do dump("VehicleData #" .. i, t) end
for i, t in ipairs(drives) do dump("VehicleDrive #" .. i, t) end

local function mine(list)
	local r = {}
	for _, t in ipairs(list) do if refersToCar(t) then r[#r + 1] = t end end
	return r
end
local myVd, myDrive = mine(vds), mine(drives)
log(("mine: %d VehicleData, %d VehicleDrive"):format(#myVd, #myDrive))

-- 2. does setting the level attribute change the numbers?
local function snap()
	local s = {}
	for i, t in ipairs(myVd) do s["vd" .. i] = { t.acceleration, t.brake, t.damageMultiplier } end
	for i, t in ipairs(myDrive) do s["drive" .. i] = { t.acceleration, t.brake } end
	return s
end
local before = snap()
local orig = { engineLevel = car:GetAttribute("engineLevel"), brakesLevel = car:GetAttribute("brakesLevel"), armorLevel = car:GetAttribute("armorLevel") }
for a in pairs(orig) do car:SetAttribute(a, 6) end
task.wait(1.5)
local after = snap()
for k, b in pairs(before) do
	local a = after[k]
	log(("level test %s: accel %s -> %s | brake %s -> %s%s"):format(k, tostring(b[1]), tostring(a[1]), tostring(b[2]), tostring(a[2]),
		b[3] ~= nil and (" | dmgMult %s -> %s"):format(tostring(b[3]), tostring(a[3])) or ""))
end
for a, v in pairs(orig) do car:SetAttribute(a, v) end
task.wait(1)

-- 3. timed runs
local function speedOf() return (seat.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude end
local function waitStopped()
	local t = os.clock()
	if speedOf() > 1.5 then print("[vd] let the car come to a full stop (brake / release W)...") end
	while speedOf() > 1.5 and os.clock() - t < 30 do task.wait(0.2) end
end
local function run(label)
	waitStopped()
	task.wait(1)
	print(("[vd] RUN %s: HOLD W NOW for %ds"):format(label, PHASE))
	local t0, top = os.clock(), 0
	local marks, hit = { 20, 40, 60, 80 }, {}
	while os.clock() - t0 < PHASE do
		local sp = speedOf()
		top = math.max(top, sp)
		for _, m in ipairs(marks) do if sp >= m and not hit[m] then hit[m] = os.clock() - t0 end end
		task.wait(0.05)
	end
	local parts = {}
	for _, m in ipairs(marks) do parts[#parts + 1] = ("%d: %s"):format(m, hit[m] and ("%.1fs"):format(hit[m]) or "never") end
	log(("RUN %s: top=%.1f st/s | time to %s"):format(label, top, table.concat(parts, ", ")))
	print("[vd] release W")
	return top, hit
end
log("== MEASURED RUNS ==")
local topA, hitA = run("A normal")

-- overrides
local saved = {}
local function setf(t, k, v)
	if type(t[k]) == "number" then saved[#saved + 1] = { t, k, t[k] }; t[k] = v end
end
local cfgs = {}
for _, t in ipairs(myVd) do setf(t, "acceleration", t.acceleration * 3); if type(t.config) == "table" then cfgs[t.config] = true end end
for _, t in ipairs(myDrive) do setf(t, "acceleration", t.acceleration * 3); if type(t.config) == "table" then cfgs[t.config] = true end end
for c in pairs(cfgs) do
	if setreadonly then pcall(setreadonly, c, false) end
	setf(c, "maxSpeed", (c.maxSpeed or 0) * 2); setf(c, "acceleration", (c.acceleration or 0) * 3)
end
log(("applied overrides to %d fields (acceleration x3, maxSpeed x2)"):format(#saved))
local topB, hitB = run("B overrides")
for _, s in ipairs(saved) do s[1][s[2]] = s[3] end
log("overrides restored")

local faster = hitB[40] and hitA[40] and hitB[40] < hitA[40] * 0.85 or (topB > topA * 1.1)
log(("RESULT: A top=%.1f, B top=%.1f -> %s"):format(topA, topB, faster and "DIRECT OVERRIDES WORK" or "overrides had no clear effect"))

local report = table.concat(out, "\n")
if setclipboard then setclipboard(report) end
print(report)
print(("[vd] done: %d chars%s"):format(#report, setclipboard and ", copied to clipboard" or ""))

-- Tuning probe (engine / brakes / armor levels, speed, acceleration). Run it SITTING IN YOUR CAR on a long straight road.
--  1) static: car tuning attributes, the game's vehicle modules (vehicleDrive, vehicleGearbox...), stat tables on the heap
--  2) run A: when told, HOLD W for PHASE seconds -> measures top speed + time to 30/60/90 studs/s
--  3) it then sets engineLevel/brakesLevel/armorLevel = 5 LOCALLY (restored afterwards) and asks for run B
--  Compare A vs B: if run B is faster, the client reads those attributes and a Speed module can just set them.
-- Report goes to the clipboard. Optional: getgenv().ProbeSeconds = 12 (seconds per run, default 10).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer
local PHASE = tonumber((getgenv and getgenv().ProbeSeconds) or 10)
local out, seen = {}, {}
local function log(s) out[#out + 1] = s end
local function short(v)
	local t = typeof(v)
	if t == "Instance" then return v:GetFullName() end
	if t == "table" then return "table" end
	if t == "function" then return "function" end
	local s = tostring(v)
	return #s > 70 and s:sub(1, 70) .. "..." or s
end
local function attrs(i)
	local t = {}
	for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. short(v) end
	table.sort(t)
	return "[" .. table.concat(t, ", ") .. "]"
end
local KEYS = { "speed", "torque", "power", "accel", "engine", "horse", "rpm", "gear", "ratio", "brake", "armor", "armour", "level", "upgrade", "tuning", "handling", "boost", "multiplier", "drag", "grip", "friction" }
local function interesting(n)
	n = tostring(n):lower()
	for _, k in ipairs(KEYS) do if n:find(k, 1, true) then return true end end
	return false
end
print("[tune] started")

local char = lp.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
local seat = hum and hum.SeatPart
local car
if seat then
	car = seat:FindFirstAncestorOfClass("Model")
	while car and car.Parent and car.Parent:IsA("Model") do car = car.Parent end
end
if not car then print("[tune] sit in your car first") return end

log("== SNAPSHOT ==")
log("car: " .. car:GetFullName())
log("car attrs: " .. attrs(car))
log("player attrs: " .. attrs(lp))
log(("seat: %s mass(assembly)=%.1f"):format(seat:GetFullName(), (seat.AssemblyRootPart or seat).AssemblyMass))
local baseLevels = { engineLevel = car:GetAttribute("engineLevel"), brakesLevel = car:GetAttribute("brakesLevel"), armorLevel = car:GetAttribute("armorLevel") }

-- 1a. client modules about vehicles / tuning
local getUp = getupvalues or (debug and debug.getupvalues)
local getConst = getconstants or (debug and debug.getconstants)
local function dumpTable(t, depth, prefix, budget)
	if seen[t] or depth > 3 or budget.n <= 0 then return end
	seen[t] = true
	for k, v in pairs(t) do
		if budget.n <= 0 then return end
		local tv = typeof(v)
		if tv == "number" or tv == "string" or tv == "boolean" or tv == "Vector3" or tv == "EnumItem" then
			if interesting(k) or depth == 0 then budget.n = budget.n - 1; log(("%s%s = %s"):format(prefix, short(k), short(v))) end
		elseif tv == "table" then
			if interesting(k) or depth < 2 then dumpTable(v, depth + 1, prefix .. short(k) .. ".", budget) end
		elseif tv == "function" then
			budget.n = budget.n - 1
			local line = prefix .. short(k) .. "()"
			if getConst then
				local ok, cs = pcall(getConst, v)
				if ok and type(cs) == "table" then
					local parts = {}
					for _, c in pairs(cs) do
						if (type(c) == "string" and #c < 40 and c:find("%a")) or type(c) == "number" then parts[#parts + 1] = tostring(c) end
					end
					line = line .. "  consts: " .. table.concat(parts, ", "):sub(1, 500)
				end
			end
			log(line)
		end
	end
end
local function requireWithTimeout(inst)
	local done, ok, mod = false, false, nil
	task.spawn(function() ok, mod = pcall(require, inst); done = true end)
	local t = os.clock()
	while not done and os.clock() - t < 4 do task.wait(0.1) end
	return done and ok, mod
end
log("-- vehicle client modules --")
local scripts = lp:FindFirstChild("PlayerScripts")
local want = { vehicleDrive = true, vehicleGearbox = true, vehicleHit = true, vehicleWheelEffects = true, vehicleDestructibleController = true }
for _, d in ipairs(scripts and scripts:GetDescendants() or {}) do
	if d:IsA("ModuleScript") and (want[d.Name] or d.Name:lower():find("tuning") or d.Name:lower():find("garage") or d.Name:lower():find("upgrade")) then
		log("MODULE " .. d:GetFullName())
		local ok, mod = requireWithTimeout(d)
		log("  require: " .. tostring(ok) .. " -> " .. typeof(mod))
		if ok and type(mod) == "table" then dumpTable(mod, 0, "  ", { n = 70 }) end
	end
end

-- 1b. shared config modules (vehicle stats usually live here)
log("-- ReplicatedStorage modules that look like vehicle/tuning config --")
for _, d in ipairs(RS:GetDescendants()) do
	if d:IsA("ModuleScript") and (interesting(d.Name) or d.Name:lower():find("vehicle") or d.Name:lower():find("car") or d.Name:lower():find("config")) then
		log("MODULE " .. d:GetFullName())
		local ok, mod = requireWithTimeout(d)
		if ok and type(mod) == "table" then dumpTable(mod, 0, "  ", { n = 50 }) end
	end
end

-- 1c. heap tables with speed/torque-looking numbers
log("-- heap tables with tuning-looking numeric fields --")
local cands = {}
if getgc then
	local okgc, heap = pcall(getgc, true)
	local found, iter = 0, 0
	for _, t in ipairs(okgc and heap or {}) do
		iter = iter + 1
		if iter % 3000 == 0 then task.wait() end
		if type(t) == "table" and found < 25 and not seen[t] then
			local hit, count = nil, 0
			for k, v in pairs(t) do
				count = count + 1
				if count > 40 then hit = nil break end
				if type(k) == "string" and type(v) == "number" and interesting(k) and k ~= "timestamp" then hit = k end
			end
			if hit then
				found = found + 1
				seen[t] = true
				log("table with '" .. hit .. "':")
				for k, v in pairs(t) do
					log(("    %s = %s (%s)"):format(short(k), short(v), typeof(v)))
					if type(v) == "number" then cands[#cands + 1] = { found .. "." .. short(k), t, k } end
				end
			end
		end
	end
end

-- 2. measured runs ---------------------------------------------------------
local function speedOf() return (seat.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude end
local function run(label)
	print(("[tune] RUN %s: HOLD W NOW for %ds (straight road)"):format(label, PHASE))
	local t0, top = os.clock(), 0
	local marks, hit = { 30, 60, 90, 120 }, {}
	local sampleLast = 0
	local before = {}
	for i, c in ipairs(cands) do before[i] = c[2][c[3]] end
	while os.clock() - t0 < PHASE do
		local sp = speedOf()
		top = math.max(top, sp)
		local el = os.clock() - t0
		for _, m in ipairs(marks) do
			if sp >= m and not hit[m] then hit[m] = el end
		end
		if el - sampleLast >= 1 then sampleLast = el; log(("  [%s %4.1fs] speed=%.1f"):format(label, el, sp)) end
		task.wait(0.05)
	end
	local parts = {}
	for _, m in ipairs(marks) do parts[#parts + 1] = ("%d st/s at %s"):format(m, hit[m] and ("%.1fs"):format(hit[m]) or "never") end
	log(("RUN %s: top=%.1f st/s | %s | levels: engine=%s brakes=%s armor=%s"):format(label, top, table.concat(parts, ", "),
		tostring(car:GetAttribute("engineLevel")), tostring(car:GetAttribute("brakesLevel")), tostring(car:GetAttribute("armorLevel"))))
	for i, c in ipairs(cands) do
		if c[2][c[3]] ~= before[i] then log(("  field changed during %s: %s %s -> %s"):format(label, c[1], short(before[i]), short(c[2][c[3]]))) end
	end
	return top
end

log("== MEASURED RUNS ==")
task.wait(1)
local topA = run("A (current levels)")
print("[tune] release W. Setting engine/brakes/armor = 5 locally in 3s...")
task.wait(3)
for _, a in ipairs({ "engineLevel", "brakesLevel", "armorLevel" }) do pcall(function() car:SetAttribute(a, 5) end) end
log("set engineLevel/brakesLevel/armorLevel = 5 locally; waiting 2s for the game to react")
task.wait(2)
local topB = run("B (levels set to 5)")
for a, v in pairs(baseLevels) do pcall(function() car:SetAttribute(a, v) end) end
log(("RESULT: top speed A=%.1f B=%.1f -> %s"):format(topA, topB, topB > topA * 1.08 and "CLIENT READS THE LEVELS (attribute change speeds the car up)" or "no clear change (server/physics ignores local attribute)"))
log("levels restored")

local report = table.concat(out, "\n")
if setclipboard then setclipboard(report) end
print(report)
print(("[tune] done: %d chars%s"):format(#report, setclipboard and ", copied to clipboard" or ""))

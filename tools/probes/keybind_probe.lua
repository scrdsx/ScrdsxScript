-- keybind_probe.lua : UNIVERSAL "what keys does this vehicle use" finder (works in any game, made for jets / planes / helis).
-- 1. Sit in the jet (pilot seat), then run this.
-- 2. Press keys one at a time, about a second apart: W A S D Q E R F G H T Y Z X C V B Space Shift Ctrl, 1-9, arrows...
--    Each press is logged with what it changed on the vehicle (speed, height, turn, attributes, values, remotes it fired).
-- 3. Press Right Ctrl to stop. Report -> clipboard + workspace/keybind_report.txt
-- It also lists, before you press anything: the game's ContextActionService binds, every key the vehicle's own scripts mention
-- (KeyCode names in their code), and the scripts listening to keyboard input.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
if env.KeybindProbe then pcall(env.KeybindProbe.Stop) end

local T0 = os.clock()
local out, active, conns = {}, true, {}
local function log(s) out[#out + 1] = s end
local function full(i) local ok, r = pcall(game.GetFullName, i); return ok and r or tostring(i) end
local function v3(v) return ("(%.1f, %.1f, %.1f)"):format(v.X, v.Y, v.Z) end
local function short(v)
	local t = typeof(v)
	if t == "Instance" then return "<" .. v.ClassName .. " " .. v.Name .. ">" end
	if t == "Vector3" then return v3(v) end
	if t == "CFrame" then return "CF" .. v3(v.Position) end
	if t == "number" then return ("%.3g"):format(v) end
	if t == "string" then return ("%q"):format(v:sub(1, 60)) end
	if t == "table" then return "{table}" end
	return tostring(v)
end

-- every KeyCode name, to spot them in script constants
local KEYNAMES = {}
for _, k in ipairs(Enum.KeyCode:GetEnumItems()) do KEYNAMES[k.Name] = true end
for _, n in ipairs({ "Unknown", "World0", "World1" }) do KEYNAMES[n] = nil end
local INPUTNAMES = { MouseButton1 = true, MouseButton2 = true, MouseButton3 = true, MouseWheel = true, Touch = true }

-- THE VEHICLE ---------------------------------------------------------------------------------------------------------------------
local char = lp.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
local seat = hum and hum.SeatPart
local vehicle = seat
while vehicle and vehicle.Parent and vehicle.Parent ~= workspace and not (vehicle.Parent:IsA("Folder") or vehicle.Parent:IsA("WorldModel")) do vehicle = vehicle.Parent end
if vehicle and not vehicle:IsA("Model") then vehicle = seat and seat:FindFirstAncestorOfClass("Model") end

log("=== KEYBIND PROBE  place " .. tostring(game.PlaceId) .. "  " .. os.date("%Y-%m-%d %H:%M"))
if not seat then
	log("!! you are not sitting in anything. Sit in the jet's pilot seat first, then run this again (the script lists still work).")
else
	log(("seat: %s  [%s]"):format(full(seat), seat.ClassName))
	if seat:IsA("VehicleSeat") then
		log(("  VehicleSeat: MaxSpeed=%s Torque=%s TurnSpeed=%s  (a VehicleSeat itself uses W/S = throttle, A/D = steer, or arrow keys)"):format(
			tostring(seat.MaxSpeed), tostring(seat.Torque), tostring(seat.TurnSpeed)))
	end
	log("vehicle: " .. (vehicle and full(vehicle) or "?"))
end

local function attrs(i)
	local p = {}
	local ok, a = pcall(i.GetAttributes, i)
	if ok then for k, v in pairs(a) do p[#p + 1] = k .. "=" .. short(v) end end
	table.sort(p)
	return table.concat(p, "  ")
end
if vehicle then
	log("vehicle attributes: " .. attrs(vehicle))
	if seat then log("seat attributes: " .. attrs(seat)) end
	local scripts, values, movers = {}, {}, {}
	for _, d in ipairs(vehicle:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then scripts[#scripts + 1] = ("%s [%s]"):format(d:GetFullName():sub(#vehicle:GetFullName() + 2), d.ClassName)
		elseif d:IsA("ValueBase") then values[#values + 1] = d.Name .. "=" .. short(d.Value)
		elseif d:IsA("Constraint") or d:IsA("BodyMover") then movers[#movers + 1] = d.ClassName .. ":" .. d.Name end
	end
	log("scripts inside the vehicle: " .. (#scripts > 0 and table.concat(scripts, ", ") or "none"))
	log("values inside: " .. table.concat(values, "  "))
	log("forces / constraints: " .. table.concat(movers, ", "))
end

-- CONTEXT ACTION BINDS (the game's own named actions + their keys) -----------------------------------------------------------------
log("")
log("=== ContextActionService binds")
pcall(function()
	for name, info in pairs(CAS:GetAllBoundActionInfo()) do
		local keys = {}
		for _, it in ipairs(info.inputTypes or {}) do keys[#keys + 1] = typeof(it) == "EnumItem" and it.Name or tostring(it) end
		log(("  %-28s  keys: %s%s"):format(name, table.concat(keys, ", "), info.title and info.title ~= "" and ("   title=" .. info.title) or ""))
	end
end)

-- KEYS MENTIONED IN SCRIPT CODE ----------------------------------------------------------------------------------------------------
-- Enum.KeyCode.X compiles to the string constant "X", so the KeyCode names among a function's constants are the keys it checks.
local getc = (debug and debug.getconstants) or getconstants
local function keysIn(fn, seen, acc, depth)
	if seen[fn] or depth > 4 then return end
	seen[fn] = true
	local ok, consts = pcall(getc, fn)
	if ok and consts then
		for _, c in pairs(consts) do
			if type(c) == "string" and (KEYNAMES[c] or INPUTNAMES[c]) then acc[c] = true
			elseif type(c) == "function" then keysIn(c, seen, acc, depth + 1) end
		end
	end
	local okp, protos = pcall(function() return debug.getprotos and debug.getprotos(fn) end)
	if okp and protos then for _, p in ipairs(protos) do keysIn(p, seen, acc, depth + 1) end end
end
local function keyList(acc)
	local l = {}
	for k in pairs(acc) do l[#l + 1] = k end
	table.sort(l)
	return table.concat(l, " ")
end
local function scriptOf(fn)
	local ok, e = pcall(getfenv, fn)
	local s = ok and type(e) == "table" and rawget(e, "script")
	if typeof(s) == "Instance" then return s end
	local oks, src = pcall(debug.info, fn, "s")
	return oks and src or nil
end

log("")
log("=== scripts listening to the keyboard (InputBegan / InputEnded / InputChanged)")
if getconnections and getc then
	for _, sig in ipairs({ "InputBegan", "InputEnded", "InputChanged" }) do
		local ok, cs = pcall(getconnections, UIS[sig])
		for _, c in ipairs(ok and cs or {}) do
			local fn = c.Function
			if type(fn) == "function" then
				local acc = {}
				keysIn(fn, {}, acc, 0)
				local s = scriptOf(fn)
				local k = keyList(acc)
				if k ~= "" then log(("  %s  %s  keys: %s"):format(sig, typeof(s) == "Instance" and full(s) or tostring(s), k)) end
			end
		end
	end
else
	log("  (your executor has no getconnections / debug.getconstants)")
end

log("")
log("=== keys in vehicle / flight related code (scripts whose path mentions jet, plane, aircraft, heli, fly, flight, pilot, vehicle, seat, drive)")
local WORDS = { "jet", "plane", "aircraft", "heli", "fly", "flight", "pilot", "vehicle", "seat", "drive", "car", "boat" }
if getgc and getc then
	local per = {}
	local ok, gc = pcall(getgc, false)
	for _, fn in ipairs(ok and gc or {}) do
		if type(fn) == "function" and (not iscclosure or not iscclosure(fn)) then
			local s = scriptOf(fn)
			local name = typeof(s) == "Instance" and full(s) or tostring(s or "")
			local low = name:lower()
			local hit = vehicle and typeof(s) == "Instance" and s:IsDescendantOf(vehicle)
			if not hit then for _, w in ipairs(WORDS) do if low:find(w, 1, true) then hit = true; break end end end
			if hit then
				per[name] = per[name] or {}
				keysIn(fn, {}, per[name], 3) -- this function only (depth 3 = no deep recursion: getgc already lists the inner ones)
			end
		end
	end
	local names = {}
	for n in pairs(per) do names[#names + 1] = n end
	table.sort(names)
	for _, n in ipairs(names) do
		local k = keyList(per[n])
		if k ~= "" then log(("  %s\n      keys: %s"):format(n, k)) end
	end
	if #names == 0 then log("  none found") end
else
	log("  (your executor has no getgc / debug.getconstants)")
end

-- LIVE: what each key press changes -------------------------------------------------------------------------------------------------
log("")
log("=== live key test (press keys one at a time while sitting in the jet)")
local root = vehicle and (vehicle.PrimaryPart or seat) or seat
local function snapshot()
	local s = { attrs = {}, vals = {} }
	if root and root.Parent then
		s.pos, s.vel, s.look = root.Position, root.AssemblyLinearVelocity, root.CFrame.LookVector
		s.rot = root.AssemblyAngularVelocity
	end
	if vehicle then
		pcall(function() for k, v in pairs(vehicle:GetAttributes()) do s.attrs["vehicle." .. k] = v end end)
		if seat then pcall(function() for k, v in pairs(seat:GetAttributes()) do s.attrs["seat." .. k] = v end end) end
		for _, d in ipairs(vehicle:GetDescendants()) do
			if d:IsA("ValueBase") then s.vals[d] = d.Value end
		end
	end
	if seat and seat:IsA("VehicleSeat") then s.throttle, s.steer = seat.Throttle, seat.Steer end
	return s
end

-- remotes fired right after a key press
local recent = {}
pcall(function()
	local old
	old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local m = getnamecallmethod()
		if active and (m == "FireServer" or m == "InvokeServer") and not checkcaller() then
			recent[#recent + 1] = { t = os.clock(), name = self.Name, args = table.pack(...) }
			if #recent > 60 then table.remove(recent, 1) end
		end
		setnamecallmethod(m)
		return old(self, ...)
	end))
end)

local function diff(a, b, key, t0)
	local p = {}
	if a.vel and b.vel then
		local fa, fb = a.vel:Dot(a.look), b.vel:Dot(b.look)
		if math.abs(fb - fa) > 2 then p[#p + 1] = ("forward speed %+.0f"):format(fb - fa) end
		if math.abs(b.vel.Y - a.vel.Y) > 2 or math.abs(b.pos.Y - a.pos.Y) > 1.5 then p[#p + 1] = ("height %+.1f (climb %+.0f)"):format(b.pos.Y - a.pos.Y, b.vel.Y - a.vel.Y) end
		local ya = math.deg(math.atan2(-a.look.X, -a.look.Z)); local yb = math.deg(math.atan2(-b.look.X, -b.look.Z))
		local dy = (yb - ya + 540) % 360 - 180
		if math.abs(dy) > 3 then p[#p + 1] = ("turned %s %.0f°"):format(dy > 0 and "left" or "right", math.abs(dy)) end
		local pa, pb = math.deg(math.asin(math.clamp(a.look.Y, -1, 1))), math.deg(math.asin(math.clamp(b.look.Y, -1, 1)))
		if math.abs(pb - pa) > 3 then p[#p + 1] = ("nose %s %.0f°"):format(pb > pa and "up" or "down", math.abs(pb - pa)) end
		if b.rot and a.rot and (b.rot - a.rot).Magnitude > 0.5 then p[#p + 1] = "spin " .. v3(b.rot - a.rot) end
	end
	if a.throttle ~= b.throttle then p[#p + 1] = ("seat Throttle %s->%s"):format(tostring(a.throttle), tostring(b.throttle)) end
	if a.steer ~= b.steer then p[#p + 1] = ("seat Steer %s->%s"):format(tostring(a.steer), tostring(b.steer)) end
	for k, v in pairs(b.attrs) do if a.attrs[k] ~= v then p[#p + 1] = ("%s: %s -> %s"):format(k, short(a.attrs[k]), short(v)) end end
	for inst, v in pairs(b.vals) do if a.vals[inst] ~= v then p[#p + 1] = ("%s: %s -> %s"):format(inst.Name, short(a.vals[inst]), short(v)) end end
	for _, r in ipairs(recent) do
		if r.t >= t0 and r.t <= t0 + 0.6 then
			local args = {}
			for i = 1, math.min(r.args.n, 5) do args[i] = short(r.args[i]) end
			p[#p + 1] = ("fired remote %s(%s)"):format(r.name, table.concat(args, ", "))
		end
	end
	return p
end

local busy = 0
conns[#conns + 1] = UIS.InputBegan:Connect(function(i, gp)
	if not active then return end
	if i.KeyCode == Enum.KeyCode.RightControl then return end
	local key = i.KeyCode ~= Enum.KeyCode.Unknown and i.KeyCode.Name or i.UserInputType.Name
	if i.UserInputType == Enum.UserInputType.MouseMovement then return end
	local t0 = os.clock()
	local a = snapshot()
	busy = busy + 1
	task.delay(0.6, function()
		busy = busy - 1
		if not active then return end
		local b = snapshot()
		local p = diff(a, b, key, t0)
		log(("  [+%5.1fs] %-12s %s%s"):format(t0 - T0, key, gp and "(game used it) " or "", #p > 0 and table.concat(p, "  |  ") or "nothing changed"))
	end)
end)

local function stop()
	if not active then return end
	active = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	local txt = table.concat(out, "\n")
	pcall(function() writefile("keybind_report.txt", txt) end)
	local ok = pcall(function() setclipboard(txt) end)
	print("[keybind probe] done, " .. #out .. " lines" .. (ok and " (copied to clipboard)" or "") .. " -> workspace/keybind_report.txt")
end
env.KeybindProbe = { Stop = stop }
conns[#conns + 1] = UIS.InputBegan:Connect(function(i) if i.KeyCode == Enum.KeyCode.RightControl then stop() end end)
print("[keybind probe] running: press keys one at a time in the jet (about 1 s apart), then Right Ctrl")

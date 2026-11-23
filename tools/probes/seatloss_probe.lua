-- seatloss_probe.lua : finds out WHY you get thrown out of the car during a teleport ("Cancelled (left the car)").
-- Run it, then do a normal teleport with the script. It records everything that touches your seat/humanoid, every
-- remote the server sends you, every remote the client fires, and a 10Hz timeline. ~6s after you are thrown out
-- it copies the report to your clipboard (also saved to workspace/seatloss_report.txt). Max 2 minutes.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
print("[seatloss] started - run your teleport now")

local env = (getgenv and getgenv()) or _G
if env.SeatLossProbe then pcall(env.SeatLossProbe.Stop) end

local T0 = os.clock()
local out, ring, conns, attached = {}, {}, {}, {}
local active, finished = true, false

local function log(s) out[#out + 1] = ("[+%7.3f] %s"):format(os.clock() - T0, s) end
local function full(i)
	local ok, r = pcall(game.GetFullName, i)
	return ok and r or tostring(i)
end
local function fmt(v, d)
	d = d or 0
	local t = typeof(v)
	if t == "Instance" then return "<" .. v.ClassName .. " " .. full(v) .. ">"
	elseif t == "string" then return '"' .. v:sub(1, 60) .. '"'
	elseif t == "table" then
		if d > 1 then return "{...}" end
		local p, n = {}, 0
		for k, x in pairs(v) do
			n = n + 1
			if n > 6 then p[#p + 1] = "..."; break end
			p[#p + 1] = tostring(k) .. "=" .. fmt(x, d + 1)
		end
		return "{" .. table.concat(p, ", ") .. "}"
	end
	return tostring(v)
end
local function fmtArgs(pk)
	local p = {}
	for i = 1, math.min(pk.n, 6) do p[#p + 1] = fmt(pk[i]) end
	return table.concat(p, ", ")
end
local function conn(c) conns[#conns + 1] = c end

local function finish(why)
	if finished then return end
	finished = true
	active = false
	log("FINISH: " .. tostring(why))
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	local txt = table.concat(out, "\n")
	local ok = pcall(function() setclipboard(txt) end)
	pcall(function() writefile("seatloss_report.txt", txt) end)
	print("[seatloss] report " .. (ok and "copied to clipboard" or "NOT copied (see workspace/seatloss_report.txt)") .. " (" .. #out .. " lines)")
end
env.SeatLossProbe = { Stop = function() active = false; for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end end, Finish = finish }

-- 1) everything the client fires at the server (queued inside the hook, formatted outside it) ----------------------
local queue = {}
pcall(function()
	local old
	old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local m = getnamecallmethod()
		if active and (m == "FireServer" or m == "InvokeServer") then
			local cs, tb
			if getcallingscript then local ok, r = pcall(getcallingscript); if ok then cs = r end end
			local ok2, t2 = pcall(debug.traceback, "", 2)
			if ok2 then tb = t2 end
			queue[#queue + 1] = { os.clock(), self, m, table.pack(...), cs, tb }
		end
		setnamecallmethod(m)
		return old(self, ...)
	end))
end)
task.spawn(function()
	while active do
		task.wait(0.1)
		while #queue > 0 do
			local q = table.remove(queue, 1)
			log(("CLIENT>SERVER %s %s (%s) caller=%s"):format(q[3], full(q[2]), fmtArgs(q[4]), q[5] and full(q[5]) or "?"))
			if q[6] and q[4][3] == "cancel" then log("traceback: " .. tostring(q[6]):gsub("\n", " | ")) end
		end
	end
end)

-- 2) everything the server sends us ---------------------------------------------------------------------------------
local function hookRemote(r)
	if attached[r] then return end
	if r:IsA("RemoteEvent") then
		attached[r] = true
		conn(r.OnClientEvent:Connect(function(...)
			if active then log(("SERVER>CLIENT %s (%s)"):format(full(r), fmtArgs(table.pack(...)))) end
		end))
	end
end
for _, d in ipairs(RS:GetDescendants()) do hookRemote(d) end
conn(RS.DescendantAdded:Connect(hookRemote))

-- 3) watchers on character / humanoid / seat / car ---------------------------------------------------------------
local function watchAttrs(inst, label)
	if attached[inst] then return end
	attached[inst] = true
	conn(inst.AttributeChanged:Connect(function(n)
		if active then log(("ATTR %s.%s = %s"):format(label, n, fmt(inst:GetAttribute(n)))) end
	end))
end
local function watchProp(inst, label, prop)
	conn(inst:GetPropertyChangedSignal(prop):Connect(function()
		if active then log(("PROP %s.%s = %s"):format(label, prop, fmt(inst[prop]))) end
	end))
end

local lostAt
local function snapshot(tag)
	local c = lp.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local car = workspace:FindFirstChild("Vehicles") and workspace.Vehicles:FindFirstChild(lp.Name)
	local seat = car and car:FindFirstChild("DriveSeat")
	log("---- SNAPSHOT " .. tag .. " ----")
	if hum then
		log(("hum: state=%s sit=%s seatPart=%s platformStand=%s health=%.0f walkSpeed=%.0f"):format(
			tostring(hum:GetState()), tostring(hum.Sit), tostring(hum.SeatPart), tostring(hum.PlatformStand), hum.Health, hum.WalkSpeed))
	end
	if hrp then
		log(("hrp: pos=%s anchored=%s canCollide=%s canTouch=%s parent=%s"):format(
			tostring(hrp.Position), tostring(hrp.Anchored), tostring(hrp.CanCollide), tostring(hrp.CanTouch), tostring(hrp.Parent)))
		local kids = {}
		for _, k in ipairs(hrp:GetChildren()) do kids[#kids + 1] = k.ClassName .. ":" .. k.Name end
		log("hrp children: " .. table.concat(kids, ", "))
	end
	if seat then
		local kids = {}
		for _, k in ipairs(seat:GetChildren()) do kids[#kids + 1] = k.ClassName .. ":" .. k.Name end
		log(("seat: %s class=%s occupant=%s disabled=%s pos=%s"):format(
			full(seat), seat.ClassName, tostring(seat.Occupant), tostring(seat.Disabled), tostring(seat.Position)))
		log("seat children: " .. table.concat(kids, ", "))
		local at = {}
		for k, v in pairs(seat:GetAttributes()) do at[#at + 1] = k .. "=" .. tostring(v) end
		log("seat attrs: " .. table.concat(at, ", "))
	else
		log("seat: none (car missing)")
	end
	if car then
		local at = {}
		for k, v in pairs(car:GetAttributes()) do at[#at + 1] = k .. "=" .. tostring(v) end
		log("car attrs: " .. table.concat(at, ", "))
	end
	if hum then
		local at = {}
		for k, v in pairs(hum:GetAttributes()) do at[#at + 1] = k .. "=" .. tostring(v) end
		for k, v in pairs(c:GetAttributes()) do at[#at + 1] = "char." .. k .. "=" .. tostring(v) end
		log("hum/char attrs: " .. table.concat(at, ", "))
	end
end

local function onLost()
	if lostAt then return end
	lostAt = os.clock()
	log("######## SEAT LOST ########")
	log("---- last timeline samples before this ----")
	for _, s in ipairs(ring) do out[#out + 1] = s end
	snapshot("at loss")
	task.delay(6, function() snapshot("6s after loss"); finish("seat lost") end)
end

local function watchChar(c)
	if not c or attached[c] then return end
	attached[c] = true
	watchAttrs(c, "char")
	log("watching character " .. c.Name)
	local hum = c:WaitForChild("Humanoid", 5)
	if not hum then return end
	watchAttrs(hum, "hum")
	for _, p in ipairs({ "SeatPart", "Sit", "Health", "PlatformStand", "WalkSpeed", "JumpPower", "JumpHeight" }) do watchProp(hum, "hum", p) end
	conn(hum.StateChanged:Connect(function(o, n) if active then log(("STATE %s -> %s"):format(tostring(o), tostring(n))) end end))
	conn(hum.Seated:Connect(function(a, s) if active then log(("Seated(%s, %s)"):format(tostring(a), tostring(s))) end end))
	conn(hum.Died:Connect(function() if active then log("DIED") end end))
	conn(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		if active and hum.SeatPart == nil then onLost() end
	end))
	conn(c.DescendantRemoving:Connect(function(d)
		if active and (d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") or d:IsA("Constraint") or d.Name == "SeatWeld") then
			log(("REMOVING %s %s"):format(d.ClassName, full(d)))
		end
	end))
end

local function watchCar()
	local v = workspace:FindFirstChild("Vehicles")
	local car = v and v:FindFirstChild(lp.Name)
	if not car or attached[car] then return end
	attached[car] = true
	watchAttrs(car, "car")
	local seat = car:FindFirstChild("DriveSeat")
	log("watching car " .. full(car))
	if seat then
		watchAttrs(seat, "seat")
		conn(seat.ChildAdded:Connect(function(k) if active then log(("SEAT +child %s:%s"):format(k.ClassName, k.Name)) end end))
		conn(seat.ChildRemoved:Connect(function(k) if active then log(("SEAT -child %s:%s"):format(k.ClassName, k.Name)) end end))
		pcall(function() watchProp(seat, "seat", "Occupant") end)
		pcall(function() watchProp(seat, "seat", "Disabled") end)
		conn(seat.Destroying:Connect(function() if active then log("SEAT DESTROYING") end end))
	end
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			log(("PROMPT %s action=%q hold=%s dist=%s enabled=%s"):format(full(d), d.ActionText, tostring(d.HoldDuration), tostring(d.MaxActivationDistance), tostring(d.Enabled)))
			for _, ev in ipairs({ "Triggered", "TriggerEnded", "PromptButtonHoldBegan", "PromptButtonHoldEnded" }) do
				conn(d[ev]:Connect(function() if active then log(("PROMPT EVENT %s %s"):format(ev, full(d))) end end))
			end
		end
	end
	conn(car.Destroying:Connect(function() if active then log("CAR DESTROYING") end end))
end

watchAttrs(lp, "player")
conn(lp.CharacterAdded:Connect(function(c) log("CharacterAdded"); watchChar(c) end))
conn(lp.CharacterRemoving:Connect(function() if active then log("CharacterRemoving") end end))
watchChar(lp.Character)
snapshot("start")

-- 4) 10Hz timeline + frame-gap detector, keeps the last 4s --------------------------------------------------------
local acc = 0
conn(RunService.Heartbeat:Connect(function(dt)
	if not active then return end
	if dt > 0.15 then log(("FRAME GAP %.2fs"):format(dt)) end
	if os.clock() - T0 > 120 then finish("timeout (nothing happened in 2 min)"); return end
	acc = acc + dt
	if acc < 0.1 then return end
	acc = 0
	watchCar()
	local c = lp.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local car = workspace:FindFirstChild("Vehicles") and workspace.Vehicles:FindFirstChild(lp.Name)
	local seat = car and car:FindFirstChild("DriveSeat")
	local dist = (hrp and seat) and (hrp.Position - seat.Position).Magnitude or -1
	local owner = "?"
	if seat and isnetworkowner then
		local ok, r = pcall(isnetworkowner, seat)
		owner = ok and tostring(r) or "err"
	end
	local line = ("[+%7.3f] seatPart=%s state=%s hp=%.0f hrpToSeat=%.1f seatSpeed=%.0f hrpSpeed=%.0f hrpCollide=%s netOwner=%s"):format(
		os.clock() - T0,
		hum and tostring(hum.SeatPart and hum.SeatPart.Name) or "-",
		hum and tostring(hum:GetState()) or "-",
		hum and hum.Health or -1,
		dist,
		seat and seat.AssemblyLinearVelocity.Magnitude or -1,
		hrp and hrp.AssemblyLinearVelocity.Magnitude or -1,
		hrp and tostring(hrp.CanCollide) or "-",
		owner)
	ring[#ring + 1] = line
	if #ring > 40 then table.remove(ring, 1) end
end))

print("[seatloss] watching. Now teleport; the report copies itself ~6s after you get thrown out.")

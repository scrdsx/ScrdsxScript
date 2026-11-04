-- farm_record.lua : RECORDER for the AutoFarm tab. Run it, then do ONE full robbery by hand while it records:
--   everything you send to the server (buy bomb, place bomb, rob register, collect money...), what the server sends back,
--   robbery state changes, inventory changes. Press ;  (semicolon) before each step to put a labelled MARK in the log
--   (it also lists the interactables around you), press End when you are done. Auto-stops after 15 minutes.
-- Report -> clipboard + workspace/farm_record.txt
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
if env.FarmRecord then pcall(env.FarmRecord.Stop) end

local T0 = os.clock()
local out, conns, active, finished = {}, {}, true, false
local marks = 0
local function log(s) out[#out + 1] = ("[+%7.2f] %s"):format(os.clock() - T0, s) end
local function conn(c) conns[#conns + 1] = c end
local function full(i) local ok, r = pcall(game.GetFullName, i); return ok and r or tostring(i) end
local function v3(v) return ("(%.0f,%.0f,%.0f)"):format(v.X, v.Y, v.Z) end
local function fmt(v, d)
	d = d or 0
	local t = typeof(v)
	if t == "Instance" then return "<" .. v.ClassName .. " " .. full(v) .. ">"
	elseif t == "string" then return '"' .. v:sub(1, 70) .. '"'
	elseif t == "table" then
		if d > 2 then return "{...}" end
		local p, n = {}, 0
		for k, x in pairs(v) do
			n = n + 1
			if n > 8 then p[#p + 1] = "..."; break end
			p[#p + 1] = tostring(k) .. "=" .. fmt(x, d + 1)
		end
		return "{" .. table.concat(p, ", ") .. "}"
	end
	return tostring(v)
end
local function fmtArgs(pk)
	local p = {}
	for i = 1, math.min(pk.n, 8) do p[#p + 1] = fmt(pk[i]) end
	return table.concat(p, ", ")
end
local function myPos()
	local c = lp.Character
	local h = c and c:FindFirstChild("HumanoidRootPart")
	return h and h.Position
end

local function finish(why)
	if finished then return end
	finished, active = true, false
	log("FINISH: " .. tostring(why))
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	local txt = table.concat(out, "\n")
	local ok = pcall(function() setclipboard(txt) end)
	pcall(function() writefile("farm_record.txt", txt) end)
	print("[record] " .. #out .. " lines " .. (ok and "copied to clipboard" or "(clipboard failed)") .. " + workspace/farm_record.txt")
end
env.FarmRecord = { Stop = function() active = false end, Finish = finish }

-- rate limiter: a remote that spams (position updates, wanted level...) is logged a few times, then only counted
local rate = {}
local function allowed(key)
	local now = os.clock()
	local r = rate[key]
	if not r or now - r.t > 5 then r = { t = now, n = 0, muted = r and r.muted }; rate[key] = r end
	r.n = r.n + 1
	if r.n <= 6 then return true end
	if r.n == 7 then log("(" .. key .. " is spamming - throttled)") end
	return r.n % 40 == 0
end

-- client -> server
local queue = {}
pcall(function()
	local old
	old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local m = getnamecallmethod()
		if active and (m == "FireServer" or m == "InvokeServer") then
			local cs
			if getcallingscript then local ok, r = pcall(getcallingscript); if ok then cs = r end end
			queue[#queue + 1] = { self, m, table.pack(...), cs, myPos() }
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
			local key = "C>S " .. full(q[1])
			local a1 = q[3][1]
			-- calls whose first argument is an Instance / with string phases are the interesting ones: always keep those
			local keep = typeof(a1) == "Instance" or type(q[3][2]) == "string"
			if keep or allowed(key) then
				log(("CLIENT>SERVER %s %s (%s)  caller=%s  at %s"):format(q[2], full(q[1]), fmtArgs(q[3]), q[4] and full(q[4]) or "?", q[5] and v3(q[5]) or "?"))
			end
		end
	end
end)

-- server -> client
local seen = {}
local function hookRemote(r)
	if seen[r] or not r:IsA("RemoteEvent") then return end
	seen[r] = true
	conn(r.OnClientEvent:Connect(function(...)
		if not active then return end
		local key = "S>C " .. full(r)
		local pk = table.pack(...)
		local a1, a2 = pk[1], pk[2]
		local keep = typeof(a1) == "Instance" and type(a2) == "string" -- (target, interaction id, phase, player): broadcasts of other players' actions
		if keep then
			-- other players' interactions are noise unless it is you; still show a short one
			if allowed(key .. "|" .. tostring(a2)) then log(("SERVER>CLIENT %s (%s)"):format(full(r), fmtArgs(pk))) end
		elseif allowed(key) then
			log(("SERVER>CLIENT %s (%s)"):format(full(r), fmtArgs(pk)))
		end
	end))
end
for _, d in ipairs(RS:GetDescendants()) do hookRemote(d) end
conn(RS.DescendantAdded:Connect(hookRemote))

-- robbery state / inventory changes
local watched = {}
local function watch(inst, label)
	if watched[inst] then return end
	watched[inst] = true
	conn(inst.AttributeChanged:Connect(function(n)
		if active and n ~= "PreviousTransparency" and not (n == "Enabled" and inst:GetAttribute(n) == false) then
			log(("ATTR %s.%s = %s"):format(label or full(inst), n, fmt(inst:GetAttribute(n))))
		end
	end))
	if inst:IsA("ValueBase") then
		conn(inst.Changed:Connect(function(v) if active then log(("VALUE %s = %s"):format(full(inst), fmt(v))) end end))
	end
end
local rob = workspace:FindFirstChild("Robberies")
if rob then
	local n = 0
	for _, d in ipairs(rob:GetDescendants()) do
		n = n + 1
		if n > 4000 then break end
		watch(d)
	end
	watch(rob)
	conn(rob.DescendantAdded:Connect(function(d) watch(d) end)) -- (adds/removes are mostly map streaming, not logged)
end
watch(lp, "player")
local ls = lp:FindFirstChild("leaderstats")
if ls then for _, v in ipairs(ls:GetChildren()) do watch(v) end end
local function watchHolder(h, name)
	if not h then return end
	conn(h.ChildAdded:Connect(function(c) if active then log(name .. " +" .. c.Name .. " (" .. c.ClassName .. ")"); watch(c) end end))
	conn(h.ChildRemoved:Connect(function(c) if active then log(name .. " -" .. c.Name) end end))
	for _, c in ipairs(h:GetChildren()) do watch(c) end
end
watchHolder(lp:FindFirstChild("Backpack"), "BACKPACK")
local function watchChar(c)
	if not c then return end
	watch(c, "char")
	watchHolder(c, "CHARACTER")
end
watchChar(lp.Character)
conn(lp.CharacterAdded:Connect(function(c) if active then log("CharacterAdded") end watchChar(c) end))

-- marks
local function mark()
	marks = marks + 1
	local p = myPos()
	log(("======== MARK %d ======== you at %s"):format(marks, p and v3(p) or "?"))
	if p then
		local near = {}
		local inter = workspace:FindFirstChild("Interactables")
		local function consider(d)
			if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
				local part = d.Parent
				if part and part:IsA("BasePart") then
					local dist = (part.Position - p).Magnitude
					if dist < 30 then near[#near + 1] = ("%s (%.0f st)%s"):format(full(d), dist, d:IsA("ProximityPrompt") and (" '" .. d.ActionText .. "'") or "") end
				end
			end
		end
		for _, root in ipairs({ inter, rob }) do
			if root then
				for _, d in ipairs(root:GetDescendants()) do consider(d) end
			end
		end
		-- parts with a tag / name near you that the game uses as targets
		for _, d in ipairs(workspace:GetPartBoundsInRadius(p, 12)) do
			local fp = full(d)
			if not fp:find("Workspace." .. lp.Name, 1, true) and not fp:find("Vehicles", 1, true) and #near < 14 then near[#near + 1] = "part: " .. fp end
		end
		for i = 1, math.min(#near, 14) do log("   near: " .. near[i]) end
	end
end
conn(UIS.InputBegan:Connect(function(i, gp)
	if not active then return end
	-- End works even when the game swallowed the key; ; and Backspace-less marks only when not typing
	if i.KeyCode == Enum.KeyCode.End then finish("End pressed")
	elseif i.KeyCode == Enum.KeyCode.Semicolon and not gp then mark() end
end))

task.delay(900, function() if active then finish("15 minute timeout") end end)
log("recording. ; = mark   End = stop")
print("[record] recording - do the robbery by hand. Press ; before each step, End when finished.")

-- Flat TRIGGER probe: finds what pops the tires. Run SITTING IN YOUR CAR with Anti Flat Tires OFF, then drive into
-- a police blockade / spike strip so a tire pops. It logs every part your car's wheels/body touch (with tags,
-- attributes, class), the PoliceBlockades structure, and the exact parts touched in the second before each flat.
-- Report goes to the clipboard. getgenv().ProbeSeconds = 30 (default 30).
local Players = game:GetService("Players")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer
local WATCH = tonumber((getgenv and getgenv().ProbeSeconds) or 30)
local out, conns, active, t0, counts = {}, {}, true, os.clock(), {}
local function log(s) out[#out + 1] = s end
local function stamp() return ("[%5.1fs] "):format(os.clock() - t0) end
local function attrs(i)
	local t = {}
	for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. tostring(v):sub(1, 40) end
	table.sort(t)
	return #t > 0 and ("[" .. table.concat(t, ", ") .. "]") or ""
end
local function tags(i)
	local ok, t = pcall(CS.GetTags, CS, i)
	return ok and #t > 0 and ("tags{" .. table.concat(t, ",") .. "}") or ""
end
local function describe(p)
	local extra = p:IsA("BasePart") and (" size=%s canTouch=%s canCollide=%s anchored=%s"):format(tostring(p.Size), tostring(p.CanTouch), tostring(p.CanCollide), tostring(p.Anchored)) or ""
	return ("%s (%s)%s %s %s"):format(p:GetFullName(), p.ClassName, extra, attrs(p), tags(p))
end
print("[flat] started")

local char = lp.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
local seat = hum and hum.SeatPart
local car
if seat then
	car = seat:FindFirstAncestorOfClass("Model")
	while car and car.Parent and car.Parent:IsA("Model") do car = car.Parent end
end
if not car then print("[flat] sit in your car first") return end

log("== SNAPSHOT ==")
log("car: " .. car:GetFullName() .. " " .. attrs(car))
log("-- Workspace.PoliceBlockades structure (first 150) --")
local pb = workspace:FindFirstChild("PoliceBlockades")
if pb then
	local n = 0
	for _, d in ipairs(pb:GetDescendants()) do
		if n < 150 then log("  " .. describe(d)); n = n + 1 end
	end
else
	log("  (no PoliceBlockades folder spawned right now)")
end
log("-- parts anywhere named spike/stinger/strip/tire/nail/tack (first 40) --")
local n = 0
for _, d in ipairs(workspace:GetDescendants()) do
	local nm = d.Name:lower()
	if n < 40 and d:IsA("BasePart") and not d:IsDescendantOf(car) and (nm:find("spike") or nm:find("stinger") or nm:find("strip") or nm:find("nail") or nm:find("tack")) then
		log("  " .. describe(d)); n = n + 1
	end
end
log("-- tagged hazards (CollectionService tags containing spike/hazard/damage/flat/blockade/trap) --")
for _, tag in ipairs(CS:GetAllTags()) do
	local l = tag:lower()
	if l:find("spike") or l:find("hazard") or l:find("damage") or l:find("flat") or l:find("blockade") or l:find("trap") or l:find("tire") then
		local list = CS:GetTagged(tag)
		log(("  tag '%s': %d instances, e.g. %s"):format(tag, #list, list[1] and list[1]:GetFullName() or "-"))
	end
end

-- live ---------------------------------------------------------------------
local recent = {} -- { time, part }
local seenPart = {}
local function onTouch(wheel, other)
	if not active or not other or other:IsDescendantOf(car) or other:IsDescendantOf(char) then return end
	recent[#recent + 1] = { os.clock(), other, wheel.Name }
	if #recent > 30 then table.remove(recent, 1) end
	if not seenPart[other] then
		seenPart[other] = true
		if (counts.touch or 0) < 40 then
			counts.touch = (counts.touch or 0) + 1
			log(stamp() .. ("TOUCH by %s: %s"):format(wheel.Name, describe(other)))
		end
	end
end
local watched = 0
for _, d in ipairs(car:GetDescendants()) do
	if d:IsA("BasePart") and watched < 80 then
		watched = watched + 1
		table.insert(conns, d.Touched:Connect(function(o) onTouch(d, o) end))
	end
end
log(("(Touched listeners on %d car parts)"):format(watched))

table.insert(conns, car:GetAttributeChangedSignal("flatTires"):Connect(function()
	if not active then return end
	log(stamp() .. "FLAT! car.flatTires = '" .. tostring(car:GetAttribute("flatTires")) .. "'  health=" .. tostring(car:GetAttribute("currentHealth")))
	local now = os.clock()
	local shown = {}
	for i = #recent, 1, -1 do
		local r = recent[i]
		if now - r[1] < 1.5 and not shown[r[2]] then
			shown[r[2]] = true
			log(("    suspect (%.2fs before, wheel %s): %s"):format(now - r[1], r[3], describe(r[2])))
		end
	end
	-- who is near the car right now (spikes may be a separate object in a different place)
	local pos = seat.Position
	local near = workspace:GetPartBoundsInRadius(pos, 12)
	local k = 0
	for _, p in ipairs(near) do
		if not p:IsDescendantOf(car) and not p:IsDescendantOf(char) and p.Name ~= "Baseplate" and k < 14 and p ~= workspace.Terrain then
			k = k + 1
			log("    nearby: " .. describe(p))
		end
	end
end))
table.insert(conns, car.DescendantRemoving:Connect(function(d)
	if active and d.Name == "Tire" then log(stamp() .. "tire model removed: " .. d:GetFullName()) end
end))

-- remotes your client sends (hook is namecall-safe: only properties and plain calls)
local hooked = false
if hookmetamethod and getnamecallmethod then
	hooked = pcall(function()
		local old
		old = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
			local m = getnamecallmethod()
			if active and (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance" then
				local args = table.pack(...)
				local parts = {}
				for i = 1, math.min(args.n, 5) do
					local v = args[i]
					parts[#parts + 1] = typeof(v) == "Instance" and v.Name or tostring(v):sub(1, 40)
				end
				local key = "o" .. self.Name
				counts[key] = (counts[key] or 0) + 1
				if counts[key] <= 5 then log(stamp() .. "TO SERVER " .. self.Name .. "(" .. table.concat(parts, ", ") .. ")") end
			end
			if setnamecallmethod then setnamecallmethod(m) end
			return old(self, ...)
		end))
	end)
end
log("remote hook: " .. tostring(hooked))

print(("[flat] watching %ds: DRIVE INTO A BLOCKADE / SPIKES NOW so a tire pops (Anti Flat Tires must be OFF)"):format(WATCH))
task.wait(WATCH)
active = false
for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
local report = table.concat(out, "\n")
if setclipboard then setclipboard(report) end
print(report)
print(("[flat] done: %d chars%s"):format(#report, setclipboard and ", copied to clipboard" or ""))

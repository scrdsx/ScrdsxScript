-- Flat tire probe. Run it while SITTING IN YOUR CAR, then GET A FLAT TIRE during the watch (whatever pops tires in this game).
-- Snapshot: car attributes (flatTires...), wheel/tire tree, tire-looking instances, tire/puncture remotes.
-- Live (WATCH seconds): attribute/property changes on the car and wheels, instances added/removed, remotes your
-- client SENDS and remotes the SERVER sends to you (OnClientEvent). Report is copied to the clipboard.
-- Optional: getgenv().ProbeSeconds = 90 before running.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer
local WATCH = tonumber((getgenv and getgenv().ProbeSeconds) or 60)
local out, conns, active, t0, counts = {}, {}, true, os.clock(), {}
local function log(s) out[#out + 1] = s end
local function stamp() return ("[%5.1fs] "):format(os.clock() - t0) end
local function short(v)
	local t = typeof(v)
	if t == "Instance" then return v:GetFullName() end
	if t == "table" then
		local parts, n = {}, 0
		for k, x in pairs(v) do
			n = n + 1
			if n <= 6 then parts[#parts + 1] = tostring(k) .. "=" .. (typeof(x) == "table" and "{..}" or tostring(x)) end
		end
		return "{" .. table.concat(parts, ", ") .. (n > 6 and ", ...+" .. (n - 6) or "") .. "}"
	end
	local s = tostring(v)
	return #s > 70 and s:sub(1, 70) .. "..." or s
end
local function attrs(i)
	local t = {}
	for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. short(v) end
	table.sort(t)
	return #t > 0 and ("[" .. table.concat(t, ", ") .. "]") or ""
end
local function capped(key, limit)
	counts[key] = (counts[key] or 0) + 1
	return counts[key] <= (limit or 10)
end
local KEYS = { "tire", "tyre", "flat", "wheel", "punct", "spike", "stinger", "rim", "air", "pressure", "rubber" }
local function interesting(n)
	n = tostring(n):lower()
	for _, k in ipairs(KEYS) do if n:find(k, 1, true) then return true end end
	return false
end
print("[tire] started")

local char = lp.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
local seat = hum and hum.SeatPart
local car
if seat then
	car = seat:FindFirstAncestorOfClass("Model")
	while car and car.Parent and car.Parent:IsA("Model") do car = car.Parent end
end
if not car then
	print("[tire] sit in your car first")
	return
end

-- snapshot -----------------------------------------------------------------
log("== SNAPSHOT ==")
log("car: " .. car:GetFullName())
log("car attrs: " .. attrs(car))
log("seat attrs: " .. attrs(seat))
log("-- wheel/tire-looking instances in the car --")
local n = 0
for _, d in ipairs(car:GetDescendants()) do
	local a = attrs(d)
	if (interesting(d.Name) or (a ~= "" and interesting(a))) and n < 120 then
		local extra = ""
		if d:IsA("BasePart") then extra = (" size=%s transp=%s canCollide=%s"):format(tostring(d.Size), tostring(d.Transparency), tostring(d.CanCollide))
		elseif d:IsA("ValueBase") then extra = " = " .. short(d.Value)
		elseif d:IsA("PrismaticConstraint") then extra = (" limits=%s..%s"):format(tostring(d.LowerLimit), tostring(d.UpperLimit))
		elseif d:IsA("SpringConstraint") then extra = (" free=%s stiff=%s"):format(tostring(d.FreeLength), tostring(d.Stiffness)) end
		log(("  %s (%s)%s %s"):format(d:GetFullName(), d.ClassName, extra, a))
		n = n + 1
	end
end
log("-- scripts in/near the car and tire-named client modules --")
n = 0
for _, root in ipairs({ car, lp:FindFirstChild("PlayerScripts") }) do
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("LuaSourceContainer")) and (root == car or interesting(d.Name) or d:GetFullName():lower():find("vehicle", 1, true)) and n < 80 then
				log("  " .. d.ClassName .. " " .. d:GetFullName())
				n = n + 1
			end
		end
	end
end

-- live watch ---------------------------------------------------------------
local function watchAttrs(inst, label)
	table.insert(conns, inst.AttributeChanged:Connect(function(name)
		if not active or not capped(label .. name, 12) then return end
		log(stamp() .. "ATTR " .. label .. "." .. name .. " = " .. short(inst:GetAttribute(name)))
	end))
end
watchAttrs(car, "car")
watchAttrs(seat, "seat")
watchAttrs(lp, "player")
if char then watchAttrs(char, "char") end

local wheelWatch = 0
for _, d in ipairs(car:GetDescendants()) do
	if (d:IsA("BasePart") or d:IsA("Constraint")) and interesting(d:GetFullName()) and wheelWatch < 40 then
		wheelWatch = wheelWatch + 1
		watchAttrs(d, d.Name)
		for _, prop in ipairs({ "Size", "Transparency", "CanCollide", "Enabled", "Stiffness", "FreeLength", "UpperLimit", "LowerLimit" }) do
			pcall(function()
				table.insert(conns, d:GetPropertyChangedSignal(prop):Connect(function()
					if active and capped("p" .. d:GetFullName() .. prop, 6) then log(stamp() .. "PROP " .. d:GetFullName() .. "." .. prop .. " = " .. short(d[prop])) end
				end))
			end)
		end
	end
end
log(("(watching %d wheel/tire parts)"):format(wheelWatch))

table.insert(conns, car.DescendantAdded:Connect(function(d)
	if active and capped("add" .. d.Name, 4) then log(stamp() .. "ADDED " .. d:GetFullName() .. " (" .. d.ClassName .. ")") end
end))
table.insert(conns, car.DescendantRemoving:Connect(function(d)
	if active and capped("rem" .. d.Name, 4) then log(stamp() .. "REMOVED " .. d:GetFullName() .. " (" .. d.ClassName .. ")") end
end))

-- remotes the SERVER sends to you
local incoming = 0
for _, d in ipairs(RS:GetDescendants()) do
	if d:IsA("RemoteEvent") then
		incoming = incoming + 1
		table.insert(conns, d.OnClientEvent:Connect(function(...)
			if not active then return end
			local args = table.pack(...)
			local parts = {}
			for i = 1, math.min(args.n, 5) do parts[#parts + 1] = short(args[i]) end
			if capped("in" .. d.Name, 5) then
				log(stamp() .. "FROM SERVER " .. d:GetFullName() .. "(" .. table.concat(parts, ", ") .. ")")
			end
		end))
	end
end
log(("(listening to %d server->client remotes)"):format(incoming))

-- remotes your client SENDS
local hooked = false
if hookmetamethod and getnamecallmethod then
	hooked = pcall(function()
		local old
		old = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
			if active then
				local m = getnamecallmethod()
				if m == "FireServer" or m == "InvokeServer" then
					local args = table.pack(...)
					local parts = {}
					for i = 1, math.min(args.n, 6) do parts[#parts + 1] = short(args[i]) end
					if capped("out" .. tostring(self.Name) .. m, 6) then
						log(stamp() .. "TO SERVER " .. m .. " " .. self:GetFullName() .. "(" .. table.concat(parts, ", ") .. ")")
					end
				end
			end
			return old(self, ...)
		end))
	end)
end
log("remote hook: " .. (hooked and "on" or "UNAVAILABLE"))

print(("[tire] watching %ds: GET A FLAT TIRE NOW (and fix it/leave it, whatever the game allows)"):format(WATCH))
task.wait(WATCH)
active = false
for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
log("-- noisy counts --")
for k, v in pairs(counts) do if v > 12 then log(("  %s x%d"):format(k, v)) end end
local report = table.concat(out, "\n")
if setclipboard then setclipboard(report) end
print(report)
print(("[tire] done: %d chars%s"):format(#report, setclipboard and ", copied to clipboard" or ""))

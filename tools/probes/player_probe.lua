-- Player + vehicle probe (stamina, crash damage). Run it while SITTING IN YOUR CAR (or on foot), then:
--   1) sprint on foot until the stamina bar drops, and/or 2) crash your car into something.
-- It snapshots the setup, then watches live for WATCH seconds (attribute/value/GUI changes + remotes fired),
-- copies a report to the clipboard and prints it. Optional: getgenv().ProbeSeconds = 60 before running.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer
local WATCH = tonumber((getgenv and getgenv().ProbeSeconds) or 45)
local out, conns, active, t0 = {}, {}, true, os.clock()
local counts = {}

local function log(s) out[#out + 1] = s end
local function stamp() return ("[%5.1fs] "):format(os.clock() - t0) end
local function short(v)
	local t = typeof(v)
	if t == "Instance" then return v:GetFullName() end
	if t == "table" then
		local n = 0
		for _ in pairs(v) do n += 1 end
		return "table(" .. n .. ")"
	end
	local s = tostring(v)
	return #s > 60 and s:sub(1, 60) .. "..." or s
end
local function attrs(i)
	local t = {}
	for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. short(v) end
	table.sort(t)
	return #t > 0 and ("[" .. table.concat(t, ", ") .. "]") or ""
end
local KEYS = { "stamina", "stam", "energy", "sprint", "run", "crash", "damage", "dmg", "health", "hurt", "collision", "impact", "fuel", "fatigue", "tired" }
local function interesting(n)
	n = n:lower()
	for _, k in ipairs(KEYS) do if n:find(k, 1, true) then return true end end
	return false
end
local function capped(key, limit)
	counts[key] = (counts[key] or 0) + 1
	return counts[key] <= (limit or 10)
end

local char = lp.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
local seat = hum and hum.SeatPart
local car
if seat then
	car = seat:FindFirstAncestorOfClass("Model")
	while car and car.Parent and car.Parent:IsA("Model") do car = car.Parent end
end

-- 1. snapshot ---------------------------------------------------------------
log("== SNAPSHOT ==")
log("player attrs: " .. attrs(lp))
log("char: " .. (char and char:GetFullName() or "none") .. " " .. (char and attrs(char) or ""))
if hum then
	log(("humanoid: Health=%s/%s WalkSpeed=%s JumpPower=%s JumpHeight=%s UseJumpPower=%s %s"):format(
		hum.Health, hum.MaxHealth, hum.WalkSpeed, hum.JumpPower, hum.JumpHeight, tostring(hum.UseJumpPower), attrs(hum)))
end
log("car: " .. (car and car:GetFullName() or "none (not seated)") .. " " .. (car and attrs(car) or ""))
if seat then log("seat: " .. seat:GetFullName() .. " " .. attrs(seat)) end

local function scan(root, label, cap)
	if not root then return end
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if n >= cap then log("  (" .. label .. ": more omitted)") break end
		local hit = interesting(d.Name)
		local a = attrs(d)
		if hit or (a ~= "" and interesting(a)) then
			local extra = ""
			if d:IsA("ValueBase") then extra = " = " .. short(d.Value)
			elseif d:IsA("GuiObject") then extra = (" size=%s vis=%s"):format(tostring(d.Size), tostring(d.Visible))
				if d:IsA("TextLabel") then extra = extra .. " text=" .. short(d.Text) end
			end
			log(("  %s: %s (%s)%s %s"):format(label, d:GetFullName(), d.ClassName, extra, a))
			n += 1
		end
	end
end
log("-- stamina/damage-looking instances --")
scan(char, "char", 60)
scan(lp, "player", 60)
scan(lp:FindFirstChildOfClass("PlayerGui"), "gui", 80)
scan(car, "car", 80)

log("-- scripts near you --")
local n = 0
for _, root in ipairs({ lp:FindFirstChild("PlayerScripts"), char, lp:FindFirstChildOfClass("PlayerGui"), car }) do
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("LocalScript") or d:IsA("ModuleScript")) and n < 60 then
				log("  " .. d.ClassName .. " " .. d:GetFullName())
				n += 1
			end
		end
	end
end

log("-- remotes (ReplicatedStorage) --")
n = 0
for _, d in ipairs(RS:GetDescendants()) do
	if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent")) and n < 150 then
		log(("  %s %s%s"):format(interesting(d.Name) and "**" or "  ", d.ClassName .. " " .. d:GetFullName(), ""))
		n += 1
	end
end

-- 2. live watch ----------------------------------------------------------------
local function watchAttrs(inst, label)
	if not inst then return end
	table.insert(conns, inst.AttributeChanged:Connect(function(name)
		if not active or not capped(label .. name, 12) then return end
		log(stamp() .. "ATTR " .. label .. "." .. name .. " = " .. short(inst:GetAttribute(name)))
	end))
end
watchAttrs(lp, "player")
watchAttrs(char, "char")
watchAttrs(hum, "humanoid")
watchAttrs(car, "car")
watchAttrs(seat, "seat")

local function watchValues(root, label)
	if not root then return end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ValueBase") then
			table.insert(conns, d.Changed:Connect(function(v)
				if not active or not capped("v" .. d:GetFullName(), 12) then return end
				log(stamp() .. "VALUE " .. d:GetFullName() .. " = " .. short(v))
			end))
		end
	end
end
watchValues(char, "char")
watchValues(lp, "player")
watchValues(car, "car")

if hum then
	table.insert(conns, hum.HealthChanged:Connect(function(h)
		if active and capped("hp", 20) then log(stamp() .. ("HUMANOID Health = %.1f"):format(h)) end
	end))
	table.insert(conns, hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if active and capped("ws", 20) then log(stamp() .. "HUMANOID WalkSpeed = " .. hum.WalkSpeed) end
	end))
end

-- stamina-ish GUI bars/labels changing
local pg = lp:FindFirstChildOfClass("PlayerGui")
if pg then
	for _, d in ipairs(pg:GetDescendants()) do
		if d:IsA("GuiObject") and interesting(d.Name) then
			table.insert(conns, d:GetPropertyChangedSignal("Size"):Connect(function()
				if active and capped("g" .. d:GetFullName(), 15) then log(stamp() .. "GUI " .. d:GetFullName() .. " size = " .. tostring(d.Size)) end
			end))
			if d:IsA("TextLabel") then
				table.insert(conns, d:GetPropertyChangedSignal("Text"):Connect(function()
					if active and capped("t" .. d:GetFullName(), 15) then log(stamp() .. "GUI " .. d:GetFullName() .. " text = " .. short(d.Text)) end
				end))
			end
		end
	end
end

-- remotes the client fires (needs hookmetamethod)
local hooked = false
if hookmetamethod and getnamecallmethod then
	local ok = pcall(function()
		local old
		old = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
			local m = getnamecallmethod()
			if active and (m == "FireServer" or m == "InvokeServer") then
				local args = table.pack(...)
				local parts = {}
				for i = 1, math.min(args.n, 6) do parts[#parts + 1] = short(args[i]) end
				local key = "r" .. tostring(self.Name) .. m
				if capped(key, 6) then
					log(stamp() .. "REMOTE " .. m .. " " .. self:GetFullName() .. "(" .. table.concat(parts, ", ") .. ")")
				end
			end
			return old(self, ...)
		end))
		hooked = true
	end)
	if not ok then hooked = false end
end
log("remote hook: " .. (hooked and "on" or "UNAVAILABLE (executor has no hookmetamethod)"))

print(("[probe] watching %ds: SPRINT until your stamina bar drops, and/or CRASH your car into something now."):format(WATCH))
task.wait(WATCH)
active = false
for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end

-- remote call totals
log("-- repeat counts (noisy names) --")
for k, v in pairs(counts) do
	if v > 12 then log(("  %s fired/changed %d times"):format(k, v)) end
end

local report = table.concat(out, "\n")
if setclipboard then setclipboard(report) end
print(report)
print(("[probe] done: %d chars%s"):format(#report, setclipboard and ", copied to clipboard" or ""))

-- traffic_probe.lua : find out how a traffic light shows its colour, so the autopilot can stop at red lights reliably.
-- Stand within ~60 studs of a traffic light (at an intersection), run this, wait 30 seconds. The result goes to the clipboard and to
-- workspace/traffic_probe.txt. Send it to me.
local lines = {}
local function log(s) lines[#lines + 1] = s end
local lp = game:GetService("Players").LocalPlayer
local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
local roads = workspace:FindFirstChild("Roads")
local tl = roads and roads:FindFirstChild("Traffic Lights")
if not (hrp and tl) then warn("no Traffic Lights folder / character") return end
-- the lamp groups nearest to me
local reds = {}
for _, d in ipairs(tl:GetDescendants()) do
	if d:IsA("BasePart") and d.Name == "Red" and d.Parent and d.Parent.Name == "Red" then
		reds[#reds + 1] = { part = d, dist = (d.Position - hrp.Position).Magnitude }
	end
end
table.sort(reds, function(a, b) return a.dist < b.dist end)
log("lamp groups loaded: " .. #reds)
local function describe(p)
	if not p then return "-" end
	local kids = {}
	for _, c in ipairs(p:GetDescendants()) do
		local extra = ""
		if c:IsA("Light") then extra = (" Enabled=%s Brightness=%s Color=%s"):format(tostring(c.Enabled), tostring(c.Brightness), tostring(c.Color)) end
		if c:IsA("Decal") or c:IsA("Texture") then extra = (" Transparency=%.2f Color3=%s"):format(c.Transparency, tostring(c.Color3)) end
		kids[#kids + 1] = c.ClassName .. ":" .. c.Name .. extra
	end
	local attrs = {}
	for k, v in pairs(p:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. tostring(v) end
	return ("%s Material=%s Transparency=%.2f Color=%s Size=%s children=[%s] attrs=[%s]"):format(p.ClassName, tostring(p.Material), p.Transparency, tostring(p.Color), tostring(p.Size), table.concat(kids, "; "), table.concat(attrs, ", "))
end
for i = 1, math.min(3, #reds) do
	local r = reds[i].part
	local holder = r.Parent.Parent
	log(("--- group %d at (%.0f,%.0f,%.0f), %.0f studs away, path %s"):format(i, r.Position.X, r.Position.Y, r.Position.Z, reds[i].dist, r:GetFullName()))
	local model = r
	while model and model ~= tl and model:GetAttribute("on") == nil do model = model.Parent end
	if model and model ~= tl then
		local at = {}
		for k, v in pairs(model:GetAttributes()) do at[#at + 1] = k .. "=" .. tostring(v) end
		log("model " .. model:GetFullName() .. " attrs: " .. table.concat(at, ", "))
	end
end
-- watch the nearest group for 30 s
local g = reds[1] and reds[1].part
if g then
	local holder = g.Parent.Parent
	local o = holder:FindFirstChild("Orange") and (holder.Orange:FindFirstChild("Orange") or holder.Orange)
	local gr = holder:FindFirstChild("Green") and (holder.Green:FindFirstChild("Green") or holder.Green)
	local prev = ""
	local t0 = os.clock()
	while os.clock() - t0 < 30 do
		local cur = "RED   " .. describe(g) .. "\nORANGE " .. describe(o) .. "\nGREEN " .. describe(gr)
		if cur ~= prev then
			log(("[+%4.1f] state changed:\n%s"):format(os.clock() - t0, cur))
			prev = cur
		end
		task.wait(0.25)
	end
end
-- speed cameras and zones
local CS = game:GetService("CollectionService")
for _, c in ipairs(CS:GetTagged("Speed Camera")) do
	local p = c:IsA("BasePart") and c or c:FindFirstChildWhichIsA("BasePart", true)
	log("speed camera " .. c:GetFullName() .. (p and (" at " .. tostring(p.Position)) or ""))
end
for _, z in ipairs(CS:GetTagged("Speed Zone")) do
	log(("speed zone %s at %s size %s Speed=%s"):format(z:GetFullName(), tostring(z.Position), tostring(z.Size), tostring(z:GetAttribute("Speed"))))
end
local txt = table.concat(lines, "\n")
pcall(function() setclipboard(txt) end)
pcall(function() writefile("traffic_probe.txt", txt) end)
print("[traffic_probe] done: " .. #lines .. " lines (clipboard + traffic_probe.txt)")

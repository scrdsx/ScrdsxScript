-- Robbery / shop location probe (for the Teleports tab). Run it anywhere (car not needed), takes a few seconds.
-- Dumps: Workspace.Robberies children (positions, sizes, prompts), every map marker (NavigationName attribute),
-- shop/bank/jeweller-looking models in Workspace.Buildings, your car + its seat height, and the drivable road material.
-- Report goes to the clipboard.
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local out = {}
local function log(s) out[#out + 1] = s end
local function v3(v) return ("(%.0f, %.0f, %.0f)"):format(v.X, v.Y, v.Z) end
local function attrs(i)
	local t = {}
	for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. tostring(v):sub(1, 40) end
	table.sort(t)
	return #t > 0 and ("[" .. table.concat(t, ", ") .. "]") or ""
end
local function where(inst)
	if inst:IsA("BasePart") then return inst.Position, inst.Size end
	if inst:IsA("Model") then
		local ok, cf, size = pcall(function() return inst:GetBoundingBox() end)
		if ok then return cf.Position, size end
	end
	local sum, n = Vector3.zero, 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then sum = sum + d.Position; n = n + 1 end
	end
	if n > 0 then return sum / n, nil end
end
local function prompts(inst, cap)
	local r = {}
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("ProximityPrompt") and #r < cap then
			local part = d.Parent
			r[#r + 1] = ("%s '%s'/'%s' @ %s"):format(d.Parent and d.Parent.Name or "?", d.ObjectText, d.ActionText, part and part:IsA("BasePart") and v3(part.Position) or "?")
		end
	end
	return r
end
print("[rob] started")

log("== Workspace top-level children ==")
local names = {}
for _, c in ipairs(workspace:GetChildren()) do names[#names + 1] = c.Name .. "(" .. c.ClassName .. ")" end
log(table.concat(names, ", "):sub(1, 1500))

log("== Workspace.Robberies ==")
local rob = workspace:FindFirstChild("Robberies")
if rob then
	for _, c in ipairs(rob:GetChildren()) do
		local pos, size = where(c)
		log(("%s (%s) pos=%s size=%s %s"):format(c.Name, c.ClassName, pos and v3(pos) or "?", size and v3(size) or "?", attrs(c)))
		local kids = {}
		for _, k in ipairs(c:GetChildren()) do kids[#kids + 1] = k.Name .. "(" .. k.ClassName .. ")" end
		log("    children: " .. table.concat(kids, ", "):sub(1, 400))
		for _, p in ipairs(prompts(c, 6)) do log("    prompt: " .. p) end
	end
else
	log("(no Robberies folder)")
end

log("== map markers (NavigationName attribute) ==")
local count, iter = 0, 0
for _, d in ipairs(workspace:GetDescendants()) do
	iter = iter + 1
	if iter % 4000 == 0 then task.wait() end
	local nm = d:GetAttribute("NavigationName")
	if type(nm) == "string" and nm ~= "" and nm ~= "Vehicle" and count < 120 then
		local pos = where(d)
		count = count + 1
		log(("%s -> %s (%s) pos=%s %s"):format(nm, d.Name, d.ClassName, pos and v3(pos) or "?", d:GetFullName():sub(1, 90)))
	end
end
log(count .. " markers")

log("== shop-looking buildings ==")
local KEYS = { "bank", "jewel", "tool", "cloth", "shop", "store", "market", "gas", "station", "pawn", "gun", "atm", "casino", "mall" }
local shown = 0
for _, d in ipairs(workspace:GetDescendants()) do
	if shown < 60 and (d:IsA("Model") or d:IsA("Folder")) then
		local l = d.Name:lower()
		for _, k in ipairs(KEYS) do
			if l:find(k, 1, true) then
				local pos = where(d)
				shown = shown + 1
				log(("%s (%s) pos=%s"):format(d:GetFullName():sub(1, 100), d.ClassName, pos and v3(pos) or "?"))
				break
			end
		end
	end
end

log("== your car + road ==")
local car = workspace:FindFirstChild("Vehicles") and workspace.Vehicles:FindFirstChild(lp.Name)
log("Workspace.Vehicles." .. lp.Name .. ": " .. (car and "found" or "NOT FOUND"))
if car then
	local seat = car:FindFirstChild("DriveSeat")
	log("DriveSeat: " .. (seat and (seat.ClassName .. " " .. v3(seat.Position)) or "missing"))
	if seat then
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { car, lp.Character }
		local hit = workspace:Raycast(seat.Position, Vector3.new(0, -50, 0), rp)
		log(hit and ("seat height above ground: %.2f, ground material=%s, instance=%s"):format(seat.Position.Y - hit.Position.Y, tostring(hit.Material), hit.Instance:GetFullName():sub(1, 80)) or "no ground under the seat")
	end
end

local report = table.concat(out, "\n")
if setclipboard then setclipboard(report) end
print(report)
print(("[rob] done: %d chars%s"):format(#report, setclipboard and ", copied to clipboard" or ""))

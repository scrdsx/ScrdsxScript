-- Teleports: put you in your own car, then glide the car to a spot on the road in front of a location.
--  1) locations are scanned at runtime: Workspace.Robberies children + map markers (attribute NavigationName)
--  2) "get in": teleports you next to your car (Workspace.Vehicles.<your name>), sits you in DriveSeat
--  3) travel: lifts the car, glides over at high speed with an ease in/out, then settles on asphalt facing the location
-- UNTESTED in game. The server may rubber-band very fast moves: lower Speed if it snaps you back.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Tele = {
	Speed = 700,     -- studs/s along the whole path
	Height = 70,     -- how far above the higher end the car cruises (clears buildings)
	GetIn = true,    -- teleport into your car first
	Face = true,     -- end facing the location
	Busy = false,
	Locations = {},  -- { name, pos }
	Info = "ready",
}
local lp = Players.LocalPlayer

local function say(msg)
	Tele.Info = msg
	if Tele.Notify then Tele.Notify(msg) end
	if Tele.Changed then Tele.Changed() end
end

local function posOf(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetBoundingBox() end)
		if ok then return cf.Position end
	end
	local sum, n = Vector3.zero, 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then sum = sum + d.Position; n = n + 1 end
	end
	return n > 0 and sum / n or nil
end

-- scan locations (runs in a task: the workspace is big) ---------------------------------
function Tele.Scan(done)
	task.spawn(function()
		local list, names = {}, {}
		local function add(name, pos)
			if not pos then return end
			local final, i = name, 2
			while names[final] do final = name .. " " .. i; i = i + 1 end
			names[final] = true
			list[#list + 1] = { name = final, pos = pos }
		end
		local rob = workspace:FindFirstChild("Robberies")
		if rob then
			for _, c in ipairs(rob:GetChildren()) do add(c.Name, posOf(c)) end
		end
		local iter = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			iter = iter + 1
			if iter % 4000 == 0 then task.wait() end
			local nm = d:GetAttribute("NavigationName")
			if type(nm) == "string" and nm ~= "" and nm ~= "Vehicle" and #list < 80
				and not (d.Parent and d.Parent.Name == lp.Name) and not d:IsDescendantOf(workspace:FindFirstChild("Vehicles") or workspace.Terrain) then
				local p = posOf(d)
				local dup = false
				for _, e in ipairs(list) do
					if p and (e.pos - p).Magnitude < 8 then dup = true break end
				end
				if not dup then add(nm, p) end
			end
		end
		table.sort(list, function(a, b) return a.name < b.name end)
		Tele.Locations = list
		if done then done(list) end
	end)
end

-- helpers --------------------------------------------------------------------------------
local function myCar()
	local v = workspace:FindFirstChild("Vehicles")
	local car = v and v:FindFirstChild(lp.Name)
	local seat = car and car:FindFirstChild("DriveSeat")
	return car, seat
end

local function ensureSeated(car, seat)
	local c = lp.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) or hum.Health <= 0 then return false end
	if hum.SeatPart == seat then return true end
	hrp.CFrame = seat.CFrame * CFrame.new(0, 3, 0)
	task.wait(0.15)
	pcall(function() seat:Sit(hum) end)
	local t, lastPrompt = os.clock(), 0
	while hum.SeatPart ~= seat and os.clock() - t < 3 do
		if fireproximityprompt and os.clock() - lastPrompt > 0.8 then
			lastPrompt = os.clock()
			for _, d in ipairs(car:GetDescendants()) do
				if d:IsA("ProximityPrompt") then pcall(fireproximityprompt, d) end
			end
		end
		task.wait(0.15)
	end
	return hum.SeatPart == seat
end

local function groundRay(x, z, fromY, ignore)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	return workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -700, 0), rp)
end

-- nearest asphalt around the location (rings of 16 directions), nearest to where we start
local function approachPoint(pos, from, ignore)
	local top = pos.Y + 120
	for _, radius in ipairs({ 14, 24, 36, 50, 68, 90 }) do
		local best, bestD
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			local r = groundRay(pos.X + math.cos(a) * radius, pos.Z + math.sin(a) * radius, top, ignore)
			if r and r.Material == Enum.Material.Asphalt and math.abs(r.Position.Y - pos.Y) < 40 then
				local d = (r.Position - from).Magnitude
				if not bestD or d < bestD then best, bestD = r.Position, d end
			end
		end
		if best then return best end
	end
	local r = groundRay(pos.X + 25, pos.Z, top, ignore)
	return r and r.Position or pos
end

local function smooth(p) return p * p * (3 - 2 * p) end

-- polyline helper: point at distance d along pts
local function along(pts, lens, d)
	for i = 1, #lens do
		if d <= lens[i] or i == #lens then
			local a, b = pts[i], pts[i + 1]
			return a:Lerp(b, lens[i] > 0 and math.clamp(d / lens[i], 0, 1) or 1)
		end
		d = d - lens[i]
	end
	return pts[#pts]
end

function Tele.GoToCar()
	if Tele.Busy then return end
	local car, seat = myCar()
	if not car or not seat then say("Spawn your car first"); return end
	Tele.Busy = true
	task.spawn(function()
		local ok = ensureSeated(car, seat)
		Tele.Busy = false
		say(ok and "In your car" or "Could not sit in the car")
	end)
end

function Tele.GoTo(loc)
	if Tele.Busy then return end
	local car, seat = myCar()
	if not car or not seat then say("Spawn your car first"); return end
	Tele.Busy = true
	task.spawn(function()
		local okRun, err = pcall(function()
			local c = lp.Character
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			if Tele.GetIn and not ensureSeated(car, seat) then say("Could not sit in the car"); return end
			if not (hum and hum.SeatPart == seat) then say("Sit in your car first (or turn Get in on)"); return end

			local root = seat.AssemblyRootPart or seat
			local ignore = { car, c }
			-- how high the seat rides above the ground, so the car lands level
			local g = groundRay(seat.Position.X, seat.Position.Z, seat.Position.Y + 2, ignore)
			local seatH = g and math.clamp(seat.Position.Y - g.Position.Y, 1.5, 8) or 4

			local startCF = seat.CFrame
			local dest = approachPoint(loc.pos, startCF.Position, ignore)
			local destPos = dest + Vector3.new(0, seatH, 0)
			local finalCF
			if Tele.Face then
				local lookAt = Vector3.new(loc.pos.X, destPos.Y, loc.pos.Z)
				finalCF = (lookAt - destPos).Magnitude > 1 and CFrame.lookAt(destPos, lookAt) or startCF.Rotation + destPos
			else
				finalCF = startCF.Rotation + destPos
			end

			local cruise = math.max(startCF.Position.Y, destPos.Y) + Tele.Height
			local pts = {
				startCF.Position,
				Vector3.new(startCF.Position.X, cruise, startCF.Position.Z),
				Vector3.new(destPos.X, cruise, destPos.Z),
				destPos,
			}
			local lens, total = {}, 0
			for i = 1, #pts - 1 do lens[i] = (pts[i + 1] - pts[i]).Magnitude; total = total + lens[i] end
			local T = math.clamp(total / math.max(Tele.Speed, 50), 0.5, 5)
			local startRot = startCF.Rotation
			local finalRot = finalCF.Rotation

			say(("Going to %s (%.1fs)"):format(loc.name, T))
			local t0 = os.clock()
			while true do
				local dt = RunService.Heartbeat:Wait()
				if not seat.Parent or hum.SeatPart ~= seat then say("Cancelled (left the car)"); return end
				local p = math.clamp((os.clock() - t0) / T, 0, 1)
				local e = smooth(p)
				local pos = along(pts, lens, e * total)
				local rot = startRot:Lerp(finalRot, smooth(math.clamp(p * 1.3, 0, 1)))
				local desired = rot + pos
				root.CFrame = (desired * seat.CFrame:Inverse()) * root.CFrame
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				if p >= 1 then break end
			end
			task.wait(0.05)
			root.AssemblyLinearVelocity = Vector3.zero
			say("Arrived: " .. loc.name)
		end)
		Tele.Busy = false
		if not okRun then say("Teleport error: " .. tostring(err):sub(1, 80)) end
	end)
end

return Tele

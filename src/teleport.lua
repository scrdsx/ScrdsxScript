-- Teleports: seat you in your own car, then glide the car to a clear spot on the road IN FRONT of a place.
--  * locations: the game's GPS list (ReplicatedStorage.DefaultNavigationTargets), robbery folders, fallbacks, saved spots
--  * travel: the car (and you) turn non-solid for the trip so nothing crashes, ragdolls or kills you, then solidify on arrival
--  * landing: only asphalt that is at the shop's ground level, open to the sky and with room for the car (never a roof)
--  * stealth: optionally throttles your outgoing network updates for the trip so other players keep seeing you at the
--    old spot, then releases them on arrival (needs NetworkClient:SetOutgoingKBPSLimit in your executor)
-- UNTESTED in game. The server may still rubber-band very fast moves: lower Speed if it snaps you back.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local NetworkClient = game:GetService("NetworkClient")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")

local Tele = {
	Speed = 900,      -- top studs/s along the whole path (it ramps up gently: a hard launch tears you out of the seat)
	Accel = 300,      -- studs/s gained per second while ramping up
	LegLen = 800,     -- longer trips are split into legs of at most this many studs: land, rest, go on (non-stop 1500+ stud flights make the server lose the car)
	LegRest = 3,      -- seconds resting on the ground between legs
	Chain = false,
	GroundFollow = false, -- fly like a car: stay a couple of studs above the road / terrain the whole way (the server ejects you from a car that flies 10+ studs up)
	SitInteract = true, -- get into the seat with the game's own seat interaction when close (false = the old direct way)
	HopLen = 700,     -- the velocity flight goes in hops of at most this many studs and rests between them (the server drops you out of the car on very long non-stop trips)
	HopPause = 1.0,   -- seconds hovering between hops
	FlyMaxSpeed = 500, -- the velocity flight never goes faster than this (very high speeds froze / crashed the game)
	FlyMinLift = 150, -- the velocity flight always cruises at least this high above the higher end (over the buildings)
	Height = 25,      -- how far above the higher end the car cruises (it is non-solid, so this can stay low)
	GetIn = true,     -- put you in your car first
	Face = true,      -- end facing the location
	Stealth = false,  -- others keep seeing you at the start until you arrive (can make the server think you are still there)
	Mode = "Fly",     -- "Fly": drive the car along the path with velocity (what Vehicle Fly does, the server accepts it); "Glide": move it with CFrames
	Ghost = true,     -- non-solid while travelling so nothing crashes / ragdolls you
	Busy = false,
	Cancel = false,
	Locations = {},   -- { name, pos }
	Info = "ready",
}
local lp = Players.LocalPlayer

-- fallbacks (coordinates read by tools/robbery_probe.lua)
local KNOWN = {
	["Bank"] = Vector3.new(-1239, 10, 3120),
	["JewelleryStore"] = Vector3.new(-412, 12, 3582),
	["Gas-N-Go Fuel Station"] = Vector3.new(-1541, 9, 3771),
	["Club"] = Vector3.new(-1744, 11, 3009),
}

-- your own saved spots, kept in the executor workspace if it has file functions
local SAVE_FILE = "ScrdsxScript_spots.json"
Tele.Saved = {}
local function loadSaved()
	if not (isfile and readfile and isfile(SAVE_FILE)) then return end
	local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(SAVE_FILE)) end)
	if ok and type(data) == "table" then
		for _, s in ipairs(data) do
			if type(s.name) == "string" and type(s.x) == "number" then
				Tele.Saved[#Tele.Saved + 1] = { name = s.name, pos = Vector3.new(s.x, s.y, s.z) }
			end
		end
	end
end
local function persistSaved()
	if not writefile then return end
	local data = {}
	for _, s in ipairs(Tele.Saved) do data[#data + 1] = { name = s.name, x = s.pos.X, y = s.pos.Y, z = s.pos.Z } end
	pcall(function() writefile(SAVE_FILE, game:GetService("HttpService"):JSONEncode(data)) end)
end
loadSaved()

local function say(msg)
	Tele.Info = msg
	if Tele.Notify then Tele.Notify(msg) end
	if Tele.Changed then Tele.Changed() end
end

-- locations -------------------------------------------------------------------------------
local function posOf(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Attachment") then return inst.WorldPosition end
	if inst:IsA("ObjectValue") and inst.Value and inst.Value ~= inst then return posOf(inst.Value) end
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetBoundingBox() end)
		if ok then return cf.Position end
	end
	local sum, n = Vector3.zero, 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then sum = sum + d.Position; n = n + 1
		elseif d:IsA("Attachment") then sum = sum + d.WorldPosition; n = n + 1 end
	end
	return n > 0 and sum / n or nil
end

function Tele.Scan(done)
	task.spawn(function()
		local list = {}
		local function nearExisting(pos)
			for _, e in ipairs(list) do
				if (e.pos - pos).Magnitude < 60 then return true end
			end
			return false
		end
		-- same place under another name ("Bank" / "BankRobbery", "Jeweler" / "JewelleryStore", "... Fuel Station"): list it once
		local function key(name)
			local k = name:lower():gsub("[^%a]", ""):gsub("robbery$", ""):gsub("fuelstation$", "fuel"):gsub("store$", ""):gsub("jewellery", "jeweler")
			return k
		end
		local function add(name, pos, force)
			if not pos then return end
			if not force then
				if nearExisting(pos) then return end
				local k = key(name)
				for _, e in ipairs(list) do if key(e.name) == k then return end end
			end
			local final, i = name, 2
			local function taken(n) for _, e in ipairs(list) do if e.name == n then return true end end return false end
			while taken(final) do final = name .. " " .. i; i = i + 1 end
			list[#list + 1] = { name = final, pos = pos }
		end
		Tele.Missing = {}

		local RS = game:GetService("ReplicatedStorage")
		local assets = RS:FindFirstChild("Code") and RS.Code:FindFirstChild("assets")
		local mod = assets and assets:FindFirstChild("defaultNavigationTargets")
		local okm, data = false, nil
		if mod then okm, data = pcall(require, mod) end
		if okm and type(data) == "table" and type(data.default) == "table" then
			for _, t in ipairs(data.default) do
				if type(t) == "table" and typeof(t.instance) == "Instance" then
					local p = posOf(t.instance)
					if p then add(t.name or t.instance.Name, p) else Tele.Missing[#Tele.Missing + 1] = t.name or t.instance.Name end
				end
			end
		else
			local folder = RS:FindFirstChild("DefaultNavigationTargets")
			for _, c in ipairs(folder and folder:GetChildren() or {}) do
				add((c.Name:gsub("(%l)(%u)", "%1 %2")), posOf(c))
			end
		end

		local rob = workspace:FindFirstChild("Robberies")
		if rob then
			for _, c in ipairs(rob:GetChildren()) do
				local nm = (c.Name:gsub(" Robbery$", ""):gsub("Robbery$", ""))
				local p = posOf(c)
				if p then add(nm, p) end
			end
		end
		for nm, p in pairs(KNOWN) do add(nm, p) end
		for _, s in ipairs(Tele.Saved) do add(s.name, s.pos, true) end

		table.sort(list, function(a, b) return a.name < b.name end)
		Tele.Locations = list
		if done then done(list) end
	end)
end

function Tele.SaveHere()
	local c = lp.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	if not hrp then say("No character"); return nil end
	local n = 1
	while true do
		local taken = false
		for _, s in ipairs(Tele.Saved) do if s.name == "Spot " .. n then taken = true break end end
		if not taken then break end
		n = n + 1
	end
	local loc = { name = "Spot " .. n, pos = hrp.Position }
	Tele.Saved[#Tele.Saved + 1] = loc
	persistSaved()
	table.insert(Tele.Locations, loc)
	say("Saved " .. loc.name)
	return loc
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
	if hum.SeatPart == seat and (hrp.Position - seat.Position).Magnitude < 12 then return true end -- (seated on paper but left behind = not seated)
	-- the game's own way in (the server seats you when you stand within 10 studs of the seat)
	local mb = game:GetService("ReplicatedStorage"):FindFirstChild("mBd")
	local interact = mb and mb:FindFirstChild("e3256932-2913-480f-93e8-9cda8c896b14")
	if Tele.SitInteract ~= false and interact and (hrp.Position - seat.Position).Magnitude < 9 then
		pcall(function() interact:FireServer(seat, "B6W", "stop") end)
		local t0 = os.clock()
		while hum.SeatPart ~= seat and os.clock() - t0 < 2 do task.wait(0.1) end
		if hum.SeatPart == seat then return true end
	end
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

local function params(ignore)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	return rp
end

local function boxFree(cf, size, ignore)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = ignore
	for _, p in ipairs(workspace:GetPartBoundsInBox(cf, size, op)) do
		if p.CanCollide and p.Transparency < 1 then return false end
	end
	return true
end

-- a spot ON THE GROUND at the location's own level (never a roof), open to the sky, with room for the car
local function findDestination(pos, from, ignore)
	local rp = params(ignore)
	local why = { noGround = 0, wrongHeight = 0, notAsphalt = 0, steep = 0, roof = 0, blocked = 0 }
	-- pass 1: asphalt, strict; pass 2: any clear ground; pass 3: relaxed heights / no sky test / smaller box
	local function candidate(x, z, pass)
		local relaxed = pass == 3
		local r = workspace:Raycast(Vector3.new(x, pos.Y + (relaxed and 30 or 12), z), Vector3.new(0, relaxed and -90 or -40, 0), rp)
		if not r then why.noGround = why.noGround + 1; return nil end
		if pass == 1 and r.Material ~= Enum.Material.Asphalt then why.notAsphalt = why.notAsphalt + 1; return nil end
		if r.Normal.Y < (relaxed and 0.8 or 0.9) then why.steep = why.steep + 1; return nil end
		local lo, hi = relaxed and -30 or -12, relaxed and 25 or 8
		if r.Position.Y < pos.Y + lo or r.Position.Y > pos.Y + hi then why.wrongHeight = why.wrongHeight + 1; return nil end
		if not relaxed and workspace:Raycast(r.Position + Vector3.new(0, 2, 0), Vector3.new(0, 25, 0), rp) then
			why.roof = why.roof + 1; return nil -- under a roof/bridge
		end
		local face = Vector3.new(pos.X, r.Position.Y + 3, pos.Z)
		local at = r.Position + Vector3.new(0, 3, 0)
		local cf = (face - at).Magnitude > 1 and CFrame.lookAt(at, face) or CFrame.new(at)
		local size = relaxed and Vector3.new(7, 3, 12) or Vector3.new(9, 4, 17)
		if not boxFree(cf, size, ignore) then why.blocked = why.blocked + 1; return nil end
		return r.Position
	end
	for pass = 1, 3 do
		for _, radius in ipairs({ 10, 16, 24, 34, 46, 60, 80, 110 }) do
			local best, bestD
			for i = 0, 23 do
				local a = i / 24 * math.pi * 2
				local p = candidate(pos.X + math.cos(a) * radius, pos.Z + math.sin(a) * radius, pass)
				if p then
					local d = (p - from).Magnitude
					if not bestD or d < bestD then best, bestD = p, d end
				end
			end
			if best then return best, pass == 1 end
		end
	end
	local parts = {}
	for k, v in pairs(why) do if v > 0 then parts[#parts + 1] = k .. " " .. v end end
	table.sort(parts)
	return nil, table.concat(parts, ", ")
end

local function smooth(p) return p * p * (3 - 2 * p) end

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

-- height of the road / terrain under (x, z): roofs, trees and fences are looked through
local function roadY(x, y, z, ignore)
	local roads = workspace:FindFirstChild("Roads")
	local list = {}
	for _, i in ipairs(ignore) do list[#list + 1] = i end
	local origin = Vector3.new(x, y + 60, z)
	for _ = 1, 6 do
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = list
		local hit = workspace:Raycast(origin, Vector3.new(0, -400, 0), rp)
		if not hit then return nil end
		local inst = hit.Instance
		if inst == workspace.Terrain or (roads and inst:IsDescendantOf(roads)) then return hit.Position.Y end
		list[#list + 1] = inst
		origin = hit.Position - Vector3.new(0, 0.1, 0)
	end
	return nil
end

-- non-solid for the trip (and restored afterwards, whatever happens)
local function ghost(car, char, on, store)
	if on then
		for _, root in ipairs({ car, char }) do
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BasePart") then
					store[d] = { d.CanCollide, d.CanTouch }
					-- CanCollide only: CanTouch=false makes the game's own client send "cancel" and the server unseats you
					d.CanCollide = false
				end
			end
		end
	else
		for p, o in pairs(store) do
			if p.Parent then pcall(function() p.CanCollide = o[1]; p.CanTouch = o[2] end) end
		end
		table.clear(store)
	end
end

local lagOn = false
local function setLag(on)
	local ok
	if on then
		ok = pcall(function() NetworkClient:SetOutgoingKBPSLimit(1) end)
		if ok then lagOn = true end
	else
		-- release with a big finite limit first (an infinite one is not accepted everywhere), then the unlimited value
		ok = pcall(function() NetworkClient:SetOutgoingKBPSLimit(1e7) end)
		pcall(function() NetworkClient:SetOutgoingKBPSLimit(math.huge) end)
		lagOn = false
	end
	return ok
end

function Tele.Stop() Tele.Cancel = true end

-- short trip log (also printed): what the car really did, for debugging
Tele.Trace = {}
local function trace(msg)
	Tele.Trace[#Tele.Trace + 1] = msg
	if #Tele.Trace > 60 then table.remove(Tele.Trace, 1) end
	print("[teleport] " .. msg)
	if Tele.OnTrace then pcall(Tele.OnTrace, msg) end
end
local function v3s(v) return ("(%.0f,%.0f,%.0f)"):format(v.X, v.Y, v.Z) end
-- the car stopped moving: list what is around it so the blocker can be identified
local function dumpNearby(pos, toward, ignore)
	local function full(i) local ok, r = pcall(game.GetFullName, i); return ok and r or tostring(i) end
	local ok, list = pcall(function() return workspace:GetPartBoundsInRadius(pos, 45) end)
	local n = 0
	for _, p in ipairs(ok and list or {}) do
		local skip = false
		for _, ig in ipairs(ignore) do if p:IsDescendantOf(ig) then skip = true; break end end
		if not skip and n < 25 then
			n = n + 1
			trace(("  near: %s [%s] collide=%s anchored=%s size=%s"):format(full(p), p.ClassName, tostring(p.CanCollide), tostring(p.Anchored), v3s(p.Size)))
		end
	end
	if toward then
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(pos, toward.Unit * 300, rp)
		trace(hit and ("  ray ahead hits %s at %.0f studs (collide=%s)"):format(full(hit.Instance), hit.Distance, tostring(hit.Instance.CanCollide)) or "  ray ahead (300 studs): nothing")
	end
	for _, name in ipairs({ "MapBarriers", "VehicleDeleteZones", "Gates", "SpeedZones" }) do
		local f = workspace:FindFirstChild(name)
		for _, d in ipairs(f and f:GetDescendants() or {}) do
			if d:IsA("BasePart") and (d.Position - pos).Magnitude < 200 + d.Size.Magnitude then
				trace(("  zone: %s size=%s dist=%.0f"):format(full(d), v3s(d.Size), (d.Position - pos).Magnitude))
			end
		end
	end
end

-- Seat guard. Seating ourselves skips the game's normal "interact" flow; its interaction UI then unmounts and the game's
-- own client sends FireServer(seat, <id>, "cancel"), and the server throws you out of the seat (seen in tools/seatloss_probe.lua,
-- caller Code.layout.guis.interactionSystem -> interactable.interactCancel). We drop that one message for our own seat.
-- NEVER use obj:Method() inside the hook (nested namecalls corrupt the original call): properties + plain functions only.
local GuardSeat, guardUntil, guardHooked = nil, 0, false
Tele.Blocked = 0
local function installGuard()
	if guardHooked then return true end
	if not (hookmetamethod and getnamecallmethod) then return false end
	local ok = pcall(function()
		local old
		old = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
			local m = getnamecallmethod()
			if m == "FireServer" and GuardSeat and os.clock() < guardUntil and typeof(self) == "Instance" and self.ClassName == "RemoteEvent" then
				local a, _, c3 = ...
				if a == GuardSeat and c3 == "cancel" then
					Tele.Blocked = Tele.Blocked + 1
					return nil
				end
			end
			if setnamecallmethod then setnamecallmethod(m) end
			return old(self, ...)
		end))
	end)
	guardHooked = ok
	return ok
end
local function guard(seat, seconds)
	installGuard()
	GuardSeat = seat
	guardUntil = os.clock() + seconds
end

function Tele.GoToCar()
	if Tele.Busy then return end
	local car, seat = myCar()
	if not car or not seat then say("Spawn your car first"); return end
	Tele.Busy = true
	guard(seat, 1e9)
	task.spawn(function()
		local ok = ensureSeated(car, seat)
		guard(seat, 4)
		Tele.Busy = false
		say(ok and "In your car" or "Could not sit in the car")
	end)
end

local function tripInner(loc)
	if Tele.Busy then return end
	local car, seat = myCar()
	if not car or not seat then say("Spawn your car first"); return end
	Tele.Busy, Tele.Cancel = true, false
	Tele.LastResult = nil -- becomes "ok" only when the car really arrived
	Tele.Trace = {}
	guard(seat, 1e9) -- from before we sit until a few seconds after we arrive
	task.spawn(function()
		local store = {}
		local undo = {} -- things to put back after the trip, whatever happens
		local c = lp.Character
		local okRun, err = pcall(function()
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			local hrp = c and c:FindFirstChild("HumanoidRootPart")
			if Tele.GetIn and not ensureSeated(car, seat) then say("Could not sit in the car"); return end
			if not (hum and hum.SeatPart == seat) then say("Sit in your car first (or turn Get in on)"); return end
			task.wait(0.5) -- let the seat weld settle (and register on the server) before moving

			local root = seat.AssemblyRootPart or seat
			local ignore = { car, c }
			local g = workspace:Raycast(seat.Position, Vector3.new(0, -30, 0), params(ignore))
			local seatH = (g and math.clamp(seat.Position.Y - g.Position.Y, 0.8, 8) or 3) + 0.3

			local startCF = seat.CFrame
			-- the map streams in around you: ask for the destination area first, or the road there does not exist yet
			say("Loading the area near " .. loc.name .. "...")
			pcall(function() lp:RequestStreamAroundAsync(loc.pos, 8) end)
			local ground, onRoad
			for attempt = 1, 3 do
				ground, onRoad = findDestination(loc.pos, startCF.Position, ignore)
				if ground then break end
				pcall(function() lp:RequestStreamAroundAsync(loc.pos, 5) end)
				task.wait(0.6)
			end
			if not ground then
				print("[teleport] no spot near " .. loc.name .. " (" .. tostring(onRoad) .. ")")
				say("No spot near " .. loc.name .. ": " .. tostring(onRoad))
				return
			end
			local destPos = ground + Vector3.new(0, seatH, 0)
			local finalRot = startCF.Rotation
			if Tele.Face then
				-- yaw-only turn toward the location: keeps the car's own pitch/roll (the seat's axes may not match the body's)
				local f = Vector3.new(startCF.LookVector.X, 0, startCF.LookVector.Z)
				local w = Vector3.new(loc.pos.X - destPos.X, 0, loc.pos.Z - destPos.Z)
				if f.Magnitude > 0.05 and w.Magnitude > 1 then
					local delta = CFrame.lookAt(Vector3.zero, w.Unit) * CFrame.lookAt(Vector3.zero, f.Unit):Inverse()
					finalRot = delta * startCF.Rotation
				end
			end

			local flyMode = Tele.Mode == "Fly"
			local lift = Tele.Height
			if flyMode then lift = math.max(lift, Tele.FlyMinLift) end -- fly OVER the buildings, not through them
			local cruise = math.max(startCF.Position.Y, destPos.Y) + lift
			local pts = {
				startCF.Position,
				Vector3.new(startCF.Position.X, cruise, startCF.Position.Z),
			}
			local pausePts = {}
			if flyMode then
				local flatD = Vector3.new(destPos.X - startCF.Position.X, 0, destPos.Z - startCF.Position.Z).Magnitude
				local hops = math.ceil(flatD / math.max(Tele.HopLen, 200))
				for k = 1, hops - 1 do
					local f = k / hops
					pts[#pts + 1] = Vector3.new(startCF.Position.X + (destPos.X - startCF.Position.X) * f, cruise, startCF.Position.Z + (destPos.Z - startCF.Position.Z) * f)
					pausePts[#pts] = true
				end
			end
			pts[#pts + 1] = Vector3.new(destPos.X, cruise, destPos.Z)
			pts[#pts + 1] = destPos + Vector3.new(0, 0.6, 0) -- arrive just above the road, then settle
			local lens, total = {}, 0
			for i = 1, #pts - 1 do lens[i] = (pts[i + 1] - pts[i]).Magnitude; total = total + lens[i] end
			local T = math.clamp(total / math.max(Tele.Speed, 50), 0.45, 5)
			local startRot = startCF.Rotation

			-- The wheels hang off the body on constraints (separate physics assemblies), so the WHOLE car model is moved
			-- as one rigid piece with PivotTo; moving only the seat's assembly would yank the wheels off.
			local rel = seat.CFrame:Inverse() * car:GetPivot()
			local roots, seenRoot = {}, {}
			for _, holder in ipairs({ car, c }) do
				for _, d in ipairs(holder:GetDescendants()) do
					if d:IsA("BasePart") then
						local r = d.AssemblyRootPart
						if r and not seenRoot[r] then seenRoot[r] = true; roots[#roots + 1] = r end
					end
				end
			end
			local function zero()
				for _, r in ipairs(roots) do
					r.AssemblyLinearVelocity = Vector3.zero
					r.AssemblyAngularVelocity = Vector3.zero
				end
			end

			local ghostOn = false
			if Tele.Ghost then ghost(car, c, true, store); ghostOn = true end -- nothing can crash, ragdoll or kill you on the way
			local stealth = false
			if Tele.Stealth then stealth = setLag(true) end
			task.delay(T + 8, function() if lagOn then setLag(false) end end) -- watchdog: never leave the network throttled

			-- Nothing may make you leave the seat during the trip: no jumping out, no get-up state, sit forced every frame,
			-- and Space is swallowed so a stray key press cannot eject you.
			pcall(function()
				local jumpWas = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
				local upWas = hum:GetStateEnabled(Enum.HumanoidStateType.GettingUp)
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
				hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
				undo[#undo + 1] = function()
					hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, jumpWas)
					hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, upWas)
				end
			end)
			local hold = RunService.Stepped:Connect(function()
				pcall(function()
					hum.Jump = false
					if hum.SeatPart == seat then hum.Sit = true end
					-- the Humanoid switches your body collision back on every physics step; a solid body in a ghost car
					-- hits the buildings and drags the whole car to a stop (or tears you out of the seat), so keep it off
					if ghostOn then
						for part in pairs(store) do if part.Parent then part.CanCollide = false end end
					end
				end)
			end)
			undo[#undo + 1] = function() hold:Disconnect() end
			pcall(function()
				CAS:BindActionAtPriority("ScrdsxTeleNoJump", function() return Enum.ContextActionResult.Sink end, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
				undo[#undo + 1] = function() CAS:UnbindAction("ScrdsxTeleNoJump") end
			end)

			say(("%s %s (%.1fs%s)"):format(onRoad and "Going to" or "Going near", loc.name, T, stealth and ", hidden" or ""))
			local t0, lostSince, finished = os.clock(), nil, false
			local idx = 1
			local lostAccum = 0
			local lastReseat
			local assist, slow, sampleT, samplePos = false, 0, os.clock(), seat.Position
			local traceT = 0
			local stallPos, stallT = seat.Position, os.clock()
			local pauseUntil, pauseDone = 0, {}
			local lastY
			local dh0 = Vector3.new(destPos.X - seat.Position.X, 0, destPos.Z - seat.Position.Z).Magnitude
			trace(("start seat=%s dest=%s loc=%s total=%.0f speed=%d mode=%s ghost=%s"):format(v3s(seat.Position), v3s(destPos), v3s(loc.pos), total, Tele.Speed, tostring(Tele.Mode), tostring(Tele.Ghost)))
			while true do
				local dt = RunService.Heartbeat:Wait()
				if Tele.Cancel then say("Cancelled"); break end
				if not seat.Parent then say("Car disappeared"); break end
				-- "seated" = the SERVER says so too (seat.Occupant is the server's word; hum.SeatPart can be faked by the client)
				local serverOcc = seat.Occupant == hum
				local seated = hum.SeatPart == seat and (serverOcc or Tele.SitInteract == false)
				if os.clock() - traceT >= 0.5 then
					traceT = os.clock()
					local okn, own = pcall(function() return isnetworkowner and isnetworkowner(seat) end)
					trace(("t=%.1f seat=%s idx=%d seated=%s srv=%s assist=%s owner=%s hrp=%s"):format(os.clock() - t0, v3s(seat.Position), idx, tostring(seated), tostring(serverOcc), tostring(assist), okn and tostring(own) or "?", hrp and v3s(hrp.Position) or "-"))
				end
				if not seated then
					if not lostSince then
						lostSince = os.clock()
						-- tell me WHAT was pressed when it happened (no key = the game / server did it)
						local keys = {}
						pcall(function() for _, k in ipairs(UIS:GetKeysPressed()) do keys[#keys + 1] = k.KeyCode.Name end end)
						Tele.LastLoss = (#keys > 0) and table.concat(keys, "+") or "no key"
						print(("[teleport] thrown out of the seat at %.2fs, keys down: %s"):format(os.clock() - t0, Tele.LastLoss))
					end
					-- the car waits, you are put back in the seat; give up only after 2s
					if os.clock() - lostSince > 2 then say("Cancelled (left the car, keys: " .. tostring(Tele.LastLoss) .. ")"); break end
					if Tele.SitInteract ~= false then
						-- the server unseated you: ask it to seat you again (the game's own interaction), do NOT fake it on the client
						if os.clock() - (lastReseat or 0) > 0.5 then
							lastReseat = os.clock()
							trace("server says you are not in the seat (occupant gone): asking it to seat you again")
							local mb = game:GetService("ReplicatedStorage"):FindFirstChild("mBd")
							local inter = mb and mb:FindFirstChild("e3256932-2913-480f-93e8-9cda8c896b14")
							if inter then pcall(function() inter:FireServer(seat, "B6W", "stop") end) end
						end
					else
						pcall(function()
							hrp.CFrame = seat.CFrame * CFrame.new(0, 2, 0)
							hrp.AssemblyLinearVelocity = Vector3.zero
						end)
						pcall(function() seat:Sit(hum) end)
					end
				else
					lostSince = nil
				end
				if not seated then
					lostAccum = lostAccum + dt
					zero() -- hover while we get you back in
				elseif flyMode and Tele.GroundFollow then
					-- road-hugging flight: horizontal speed toward the destination, height follows the road under the car
					local sp = seat.Position
					local hvec = Vector3.new(destPos.X - sp.X, 0, destPos.Z - sp.Z)
					local dh = hvec.Magnitude
					if hrp and (hrp.Position - sp).Magnitude > 40 then
						trace(("SETBACK: hrp=%s seat=%s"):format(v3s(hrp.Position), v3s(sp)))
						say("The server moved you out of the car (setback)")
						pcall(function() hrp.Anchored = true; hrp.AssemblyLinearVelocity = Vector3.zero end)
						break
					end
					if dh < 3 then
						zero()
						if Tele.Face then pcall(function() car:PivotTo((finalRot + seat.Position) * rel) end) end
						task.wait(0.05)
						zero()
						say("Arrived: " .. loc.name)
						finished = true
						Tele.LastResult = "ok"
						break
					end
					if os.clock() - t0 - lostAccum > dh0 / math.max(math.min(Tele.Speed, Tele.FlyMaxSpeed), 40) + 14 then say("Took too long, stopped"); break end
					local dir = hvec.Unit
					local speed = math.min(Tele.Speed, Tele.FlyMaxSpeed, 30 + (os.clock() - t0 - lostAccum) * Tele.Accel, math.sqrt(2 * 300 * dh) + 6, dh / math.max(dt, 0.008))
					local gy = roadY(sp.X + dir.X * 10, sp.Y, sp.Z + dir.Z * 10, ignore)
					local tY = gy and (gy + seatH + 0.3) or lastY or sp.Y
					lastY = tY
					local vy = math.clamp((tY - sp.Y) * 6, -40, 40)
					local v = dir * speed + Vector3.new(0, vy, 0)
					for _, r in ipairs(roots) do
						r.AssemblyLinearVelocity = v
						r.AssemblyAngularVelocity = Vector3.zero
					end
				elseif flyMode then
					-- velocity flight: set the speed of every physics piece of the car, like Vehicle Fly does
					local sp = seat.Position
					while idx < #pts - 1 and (pts[idx + 1] - sp).Magnitude < 8 do idx = idx + 1 end
					if pausePts[idx] and not pauseDone[idx] then
						pauseDone[idx] = true
						pauseUntil = os.clock() + Tele.HopPause -- rest here so the server catches up with the car
					end
					local holdNow = os.clock() < pauseUntil
					if holdNow then stallPos, stallT = sp, os.clock() end
					-- the server put you back (your body is far from the seat although the game still says you sit): stop here
					if hrp and (hrp.Position - sp).Magnitude > 40 then
						trace(("SETBACK: hrp=%s seat=%s"):format(v3s(hrp.Position), v3s(sp)))
						say("The server moved you out of the car (setback)")
						pcall(function() hrp.Anchored = true; hrp.AssemblyLinearVelocity = Vector3.zero end) -- hold still, do not fall
						break
					end
					local to = pts[idx + 1] - sp
					local d = to.Magnitude
					local remaining = d
					for i = idx + 1, #lens do remaining = remaining + lens[i] end
					if idx == #pts - 1 and d < 1.5 then
						zero()
						if Tele.Face then pcall(function() car:PivotTo((finalRot + seat.Position) * rel) end) end
						task.wait(0.05)
						zero()
						say("Arrived: " .. loc.name)
						finished = true
						Tele.LastResult = "ok"
						break
					end
					-- not moving although it should: find out what is in the way, then give up early
					if (seat.Position - stallPos).Magnitude > 4 or d < 20 then
						stallPos, stallT = seat.Position, os.clock()
					elseif os.clock() - stallT > 2 then
						trace("STUCK at " .. v3s(seat.Position) .. " heading " .. v3s(pts[idx + 1]))
						dumpNearby(seat.Position, pts[idx + 1] - seat.Position, ignore)
						say("Stuck at " .. v3s(seat.Position))
						break
					end
					if os.clock() - t0 - lostAccum > total / math.max(math.min(Tele.Speed, Tele.FlyMaxSpeed, 400), 50) + math.min(Tele.Speed, Tele.FlyMaxSpeed) / math.max(Tele.Accel, 50) + 8 + #pts * Tele.HopPause then say("Took too long, stopped"); break end
					local speed = math.min(Tele.Speed, Tele.FlyMaxSpeed, 50 + (os.clock() - t0 - lostAccum) * Tele.Accel, math.sqrt(2 * 500 * remaining) + 10, d / math.max(dt, 0.008))
					if holdNow then speed = 0 end
					if assist then
						-- the car's physics would not go that fast: move the whole car in small steps instead
						local step = math.min(d, speed * math.min(dt, 0.1))
						pcall(function() car:PivotTo(car:GetPivot() + to.Unit * step) end)
						zero()
					else
						local v = d > 0.01 and to.Unit * speed or Vector3.zero
						for _, r in ipairs(roots) do
							r.AssemblyLinearVelocity = v
							r.AssemblyAngularVelocity = Vector3.zero
						end
						-- is the car really going that fast? (the game / physics can cap it)
						if os.clock() - sampleT >= 0.5 then
							local actual = (seat.Position - samplePos).Magnitude / (os.clock() - sampleT)
							sampleT, samplePos = os.clock(), seat.Position
							if speed > 150 and actual < speed * 0.4 then slow = slow + 1 else slow = 0 end
							if slow >= 2 then
								assist = true
								print(("[teleport] car only reached %.0f st/s of %.0f, switching to stepping"):format(actual, speed))
							end
						end
					end
				else
					local p = math.clamp((os.clock() - t0) / T, 0, 1)
					local pos = along(pts, lens, smooth(p) * total)
					local rot = startRot:Lerp(finalRot, smooth(math.clamp(p * 1.3, 0, 1)))
					car:PivotTo((rot + pos) * rel)
					zero()
					if p >= 1 then
						task.wait(0.05)
						zero()
						say("Arrived: " .. loc.name)
						finished = true
						Tele.LastResult = "ok"
						break
					end
				end
			end
			if not finished and seat.Parent then
				-- aborted mid-air: put the car on the ground right below instead of dropping it from cruise height
				local below = workspace:Raycast(seat.Position, Vector3.new(0, -600, 0), params(ignore))
				if below then
					local want = CFrame.new(below.Position + Vector3.new(0, seatH + 0.6, 0)) * seat.CFrame.Rotation
					car:PivotTo(want * rel)
					if hum.SeatPart ~= seat then
						-- thrown out mid-flight: stand next to the car instead of falling from cruise height
						pcall(function() c:PivotTo(CFrame.new(below.Position + Vector3.new(0, 4, 0)) * CFrame.new(seat.CFrame.RightVector * -7)) end)
					end
				end
			end
			if hrp and hrp.Anchored then
				-- setback: put the body on the ground below it (falling from 100+ studs kills you)
				local gr = workspace:Raycast(hrp.Position, Vector3.new(0, -800, 0), params(ignore))
				pcall(function() hrp.CFrame = CFrame.new((gr and gr.Position or seat.Position) + Vector3.new(0, 3.5, 0)) end)
			end
			trace(("end finished=%s seat=%s hrp=%s seated=%s"):format(tostring(finished), v3s(seat.Position), hrp and v3s(hrp.Position) or "-", tostring(hum.SeatPart == seat)))
			zero()
			ghostOn = false
			ghost(car, c, false, store)       -- solid again
			pcall(function() if hrp and hrp.Anchored then task.wait(0.2); hrp.Anchored = false end end) -- (hovering 0.6 above the road: it just settles)
			zero()
			task.wait(0.25)                   -- let the wheels touch down before others get your position
			if lagOn then setLag(false) end
			if stealth then task.wait(1.5) end -- let the server catch up with where the car now is before you can get out
			if finished then
				-- did the server move us back? (anti-teleport): tell the user instead of leaving them guessing
				task.spawn(function()
					task.wait(2.5)
					if seat.Parent and (seat.Position - destPos).Magnitude > 60 and (seat.Position - startCF.Position).Magnitude < 60 then
						say("The server put you back at the start. Try Stealth off and a lower travel speed.")
					end
				end)
			end
		end)
		if next(store) then ghost(car, c, false, store) end
		for _, u in ipairs(undo) do pcall(u) end
		if lagOn then setLag(false) end
		guard(seat, 4)
		Tele.Busy = false
		if not okRun then say("Teleport error: " .. tostring(err):sub(1, 80)) end
	end)
end

-- public entry: short trips go straight, long ones are chained legs with a rest on the ground between them
function Tele.GoTo(loc)
	if Tele.Busy or Tele.Chain then return end
	local car, seat = myCar()
	if not (car and seat) then return tripInner(loc) end
	local from = seat.Position
	local flat = Vector3.new(loc.pos.X - from.X, 0, loc.pos.Z - from.Z)
	if flat.Magnitude <= Tele.LegLen * 1.15 then return tripInner(loc) end
	Tele.Chain = true
	Tele.LastResult = nil
	task.spawn(function()
		local n = math.ceil(flat.Magnitude / Tele.LegLen)
		local ok = true
		for k = 1, n do
			local f = k / n
			local target = (k == n) and loc.pos or Vector3.new(from.X + flat.X * f, loc.pos.Y, from.Z + flat.Z * f)
			tripInner({ name = (k == n) and loc.name or ("%s (leg %d/%d)"):format(loc.name, k, n), pos = target })
			task.wait(0.3)
			while Tele.Busy do task.wait(0.2) end
			if Tele.LastResult ~= "ok" or Tele.Cancel then ok = false; break end
			if k < n then
				say(("Resting %ds before the next leg (%d/%d)..."):format(Tele.LegRest, k, n))
				task.wait(Tele.LegRest)
			end
		end
		Tele.Chain = false
		if not ok then Tele.LastResult = nil end
	end)
end

return Tele

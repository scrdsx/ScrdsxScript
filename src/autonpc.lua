-- Auto Drive: the car drives itself like an NPC, on the real roads (same autopilot as the farm, so it follows the road surface, goes round
-- roundabouts, uses turn signals and goes around stopped cars).
--   Roam   : picks random destinations on the map, one after the other.
--   Follow : follows a player (the nearest one, or one you name) and keeps driving after them as they move.
--   Park   : "Park straight": look at a parking space, press the park key; the car drives up to it, lines up with the space and rolls in straight.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Drive = __import("autodrive")
local Data = __import("roaddata")
local lp = Players.LocalPlayer
local V3 = Vector3.new

local NPC = { Enabled = false, Follow = false, FollowName = "", Cruise = 45, Info = "off", Changed = nil, Stopped = nil }
local runId = 0

local function say(s)
	if NPC.Info ~= s then NPC.Info = s; if NPC.Changed then task.defer(NPC.Changed) end end
end

local function log(m) if Drive.Log then Drive.Log("npc: " .. m) end end

-- One trip with the same retry rules as the farm: after a crash / stuck spot the autopilot plans AGAIN but remembers the blocked spot
-- (the replan / reroute counters). Without them every retry started from scratch and drove into the same obstacle again.
local function driveTo(dest, name, extra)
	local replans, reroutes, tries = 0, 0, 0
	while NPC.Enabled and tries < 7 do
		local opts = { arrive = 30, name = name, replans = replans, reroutes = reroutes, strict = true }
		for k, v in pairs(extra or {}) do opts[k] = v end
		local ok, why = Drive.To(dest, opts)
		log(("%s: %s (%s)"):format(name, tostring(ok), tostring(why)))
		if ok or why == "cancelled" or why == "retarget" or why == "left the car" or why == "sit in your car first" then return ok, why end
		tries = tries + 1
		if why == "replan" then replans = math.min(replans + 1, 4)
		elseif why == "reroute" then reroutes = reroutes + 1
		else return false, why end
		task.wait(0.3)
	end
	return false, "gave up after " .. tries .. " tries"
end

local function carAndSeat()
	local car = workspace:FindFirstChild("Vehicles") and workspace.Vehicles:FindFirstChild(lp.Name)
	local seat = car and car:FindFirstChild("DriveSeat")
	local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
	return car, seat, (car and seat and hum and hum.SeatPart == seat) and true or false
end

local function flat(a, b) return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude end

-- a random road point 250..1400 studs away on about the same level
local lastDest
local function pickDest(me)
	local q = Data.quads
	local n = #q // 9
	if n == 0 then return nil end
	for _ = 1, 80 do
		local k = math.random(0, n - 1) * 9 + 1
		local x = (q[k] + q[k + 2] + q[k + 4] + q[k + 6]) / 4
		local z = (q[k + 1] + q[k + 3] + q[k + 5] + q[k + 7]) / 4
		local y = q[k + 8]
		local d = math.sqrt((x - me.X) ^ 2 + (z - me.Z) ^ 2)
		if d > 250 and d < 1400 and math.abs(y - me.Y) < 8 and (not lastDest or math.sqrt((x - lastDest.X) ^ 2 + (z - lastDest.Z) ^ 2) > 200) then
			lastDest = V3(x, y, z)
			return lastDest
		end
	end
	return nil
end

local function targetPlayer(me)
	local want = NPC.FollowName ~= "" and NPC.FollowName:lower() or nil
	local best, bd
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lp then
			local h = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if h and (not want or p.Name:lower():find(want, 1, true) or p.DisplayName:lower():find(want, 1, true)) then
				local d = (h.Position - me).Magnitude
				if not bd or d < bd then best, bd = p, d end
			end
		end
	end
	return best
end

local function loop(id)
	while NPC.Enabled and id == runId do
		local car, seat, seated = carAndSeat()
		if not seated then
			say("sit in your car first")
			task.wait(1)
		else
			Drive.MaxSpeed = NPC.Cruise
			if NPC.Follow then
				local t = targetPlayer(seat.Position)
				local hrp = t and t.Character and t.Character:FindFirstChild("HumanoidRootPart")
				if not hrp then
					say(NPC.FollowName ~= "" and ("can't find \"" .. NPC.FollowName .. "\"") or "nobody to follow")
					task.wait(1)
				elseif flat(hrp.Position, seat.Position) < 24 then
					say("following " .. t.DisplayName .. " (close behind)")
					task.wait(0.5)
				else
					say("following " .. t.DisplayName)
					local ok, why = driveTo(hrp.Position, "following " .. t.Name, {
						arrive = 18,
						follow = function() local h = t.Character and t.Character:FindFirstChild("HumanoidRootPart"); return h and h.Position end,
					})
					if not ok and why ~= "retarget" and why ~= "cancelled" then task.wait(1) end
				end
			else
				local dest = pickDest(seat.Position)
				if not dest then
					say("no road to drive to")
					task.wait(1)
				else
					say(("roaming: driving %d studs"):format(flat(dest, seat.Position)))
					local ok, why = driveTo(dest, "roaming")
					if not ok and why ~= "cancelled" then
						say("roaming: " .. tostring(why) .. ", picking another place")
						task.wait(1)
					end
				end
			end
		end
		task.wait(0.1)
	end
	if id == runId then say("off") end
end

function NPC.SetEnabled(v)
	NPC.Enabled = v
	runId = runId + 1
	if v then
		say("starting")
		task.spawn(loop, runId)
	else
		Drive.Stop()
		say("off")
	end
end

-- Park straight at the spot under the crosshair / cursor. The car faces the way you are looking, snapped to the direction of the road
-- under the spot (so it is square to the bay, not at a random angle).
function NPC.ParkAtCrosshair()
	local car, seat, seated = carAndSeat()
	if not seated then say("sit in your car first"); return false, "sit in your car first" end
	local cam = workspace.CurrentCamera
	local vs = cam.ViewportSize
	local m = (UIS.MouseBehavior == Enum.MouseBehavior.LockCenter) and V3(vs.X / 2, vs.Y / 2, 0) or UIS:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { lp.Character, car }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 600, rp)
	if not hit or hit.Normal.Y < 0.7 then say("look at the ground where the car should park"); return false, "no ground under the crosshair" end
	local look = cam.CFrame.LookVector
	local dir = V3(look.X, 0, look.Z)
	if dir.Magnitude < 0.05 then return false, "look more horizontally" end
	dir = dir.Unit
	-- snap to the axes of the road piece under the spot
	local q = Data.quads
	for k = 1, #q, 9 do
		local x1, z1, x2, z2, x3, z3, x4, z4 = q[k], q[k + 1], q[k + 2], q[k + 3], q[k + 4], q[k + 5], q[k + 6], q[k + 7]
		local px, pz = hit.Position.X, hit.Position.Z
		local s1 = (x2 - x1) * (pz - z1) - (z2 - z1) * (px - x1)
		local s2 = (x3 - x2) * (pz - z2) - (z3 - z2) * (px - x2)
		local s3 = (x4 - x3) * (pz - z3) - (z4 - z3) * (px - x3)
		local s4 = (x1 - x4) * (pz - z4) - (z1 - z4) * (px - x4)
		if (s1 >= 0 and s2 >= 0 and s3 >= 0 and s4 >= 0) or (s1 <= 0 and s2 <= 0 and s3 <= 0 and s4 <= 0) then
			local a, b = V3(x2 - x1, 0, z2 - z1), V3(x4 - x1, 0, z4 - z1)
			if a.Magnitude > 1 and b.Magnitude > 1 then
				a, b = a.Unit, b.Unit
				local best, bd
				for _, c in ipairs({ a, -a, b, -b }) do
					local d = c:Dot(dir)
					if not bd or d > bd then best, bd = c, d end
				end
				dir = best
			end
			break
		end
	end
	local spot = V3(hit.Position.X, seat.Position.Y, hit.Position.Z)
	-- stop whatever the autopilot is doing, then park
	NPC.Enabled = false
	runId = runId + 1
	if NPC.Stopped then task.defer(NPC.Stopped) end
	task.spawn(function()
		if Drive.Busy then
			Drive.Stop()
			local t = os.clock()
			while Drive.Busy and os.clock() - t < 4 do task.wait(0.1) end
		end
		say("parking: driving up to the space")
		Drive.MaxSpeed = NPC.Cruise
		local ok, why = Drive.ParkAt(spot, dir)
		say(ok and "parked" or ("parking failed: " .. tostring(why)))
	end)
	return true
end

function NPC.Destroy()
	NPC.Enabled = false
	runId = runId + 1
	NPC.Changed, NPC.Stopped = nil, nil
	Drive.Stop()
end

return NPC

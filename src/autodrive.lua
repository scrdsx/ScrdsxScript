-- AutoDrive: an autopilot that DRIVES your car for real (throttle + steering), along the game's own road graph.
-- Why: the server only accepts a car that is driven. A car moved by script (CFrame / velocity) is ignored after ~1 s and the server
-- later puts you back where the car was parked. The game itself steers with exactly these two things (see vehicleControls):
--     car attribute Throttle (-1..1) + FireServer(car, value) on  e805d6ad...
--     car attribute Steering (-1..1) + FireServer(car, value) on  b02cf2cb...
-- Roads: ReplicatedStorage.NavigationModules.Roads (renamed NavigationMap by the game) = road pieces with "Road" attachments at their ends;
-- two pieces are connected when attachments are within 5 studs (navigationController.lua builds its GPS graph the same way).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local V3 = Vector3.new

local REM = {
	THROTTLE = "e805d6ad-9279-4c0d-8a9d-c12d7342cb1b",
	STEER = "b02cf2cb-6f36-42fb-ba25-0554007dabe3",
	IGNITION = "de7910a1-5108-423c-bb43-bb8dbe2dcf8a",
}

local Drive = { Cancel = false, Busy = false, Info = "idle", MaxSpeed = 70, Log = nil, State = nil } -- State: live data for the HUD map
local function log(s) if Drive.Log then Drive.Log(s) else print("[drive] " .. s) end end

local remotes = {}
local function remote(id)
	local r = remotes[id]
	if r and r.Parent then return r end
	local mb = RS:FindFirstChild("mBd")
	r = mb and mb:FindFirstChild(id)
	remotes[id] = r
	return r
end

-- road graph ----------------------------------------------------------------------------------------------------
local graph
local function flat(a, b) return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude end

local function fullName(i) local ok, r = pcall(game.GetFullName, i); return ok and r or tostring(i) end
-- The game keeps the road map as a model named NavigationMap (it renames NavigationModules at start-up) and moves it into the
-- minimap's viewport, so it can be in ReplicatedStorage OR inside your PlayerGui. Look in both, take the biggest "Roads" folder.
local function findRoads()
	local best, bestN = nil, 0
	local candidates = {}
	for _, root in ipairs({ RS, lp:FindFirstChild("PlayerGui"), workspace }) do
		if root then
			local okd, descendants = pcall(function() return root:GetDescendants() end)
			for _, d in ipairs(okd and descendants or {}) do
				if d.Name == "Roads" and not d:IsDescendantOf(workspace.Terrain) then
					local n = #d:GetChildren()
					candidates[#candidates + 1] = ("%s (%d children)"):format(fullName(d), n)
					local pn = d.Parent and d.Parent.Name or ""
					local mapLike = pn == "NavigationMap" or pn == "NavigationModules"
					if n > bestN and (mapLike or n > 40) and not (root == workspace and not mapLike) then best, bestN = d, n end
				end
			end
		end
	end
	if best then log("road map found: " .. fullName(best) .. " (" .. bestN .. " pieces)") else
		log("road map NOT found. Roads folders seen: " .. (#candidates > 0 and table.concat(candidates, "; ") or "none"))
	end
	return best
end

local function build()
	local roads = findRoads()
	if not roads then return nil, "road map not found in ReplicatedStorage" end
	local mods, count, acount = {}, 0, 0
	for _, m in ipairs(roads:GetChildren()) do
		if m:IsA("PVInstance") then
			local atts = {}
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("Attachment") and d.Parent and d.Parent.Name == "Road" then atts[#atts + 1] = d end
			end
			mods[m] = { inst = m, pos = m:GetPivot().Position, atts = atts, edges = {} }
			count = count + 1
			acount = acount + #atts
		end
	end
	local cell, grid = 10, {}
	for _, mod in pairs(mods) do
		for _, a in ipairs(mod.atts) do
			local p = a.WorldPosition
			local k = math.floor(p.X / cell) .. "," .. math.floor(p.Z / cell)
			grid[k] = grid[k] or {}
			table.insert(grid[k], { mod = mod, p = p })
		end
	end
	local edges = 0
	for _, mod in pairs(mods) do
		for _, a in ipairs(mod.atts) do
			if not a.Name:find("Enter", 1, true) then -- "Enter" ends are one-way inlets
				local p = a.WorldPosition
				local cx, cz = math.floor(p.X / cell), math.floor(p.Z / cell)
				for dx = -1, 1 do
					for dz = -1, 1 do
						local bucket = grid[(cx + dx) .. "," .. (cz + dz)]
						for _, o in ipairs(bucket or {}) do
							if o.mod ~= mod and (o.p - p).Magnitude <= 5 then
								local cost = flat(mod.pos, o.mod.pos)
								local e = mod.edges[o.mod]
								if not e then edges = edges + 1 end
								if not e or cost < e.cost then mod.edges[o.mod] = { cost = cost, via = p } end
							end
						end
					end
				end
			end
		end
	end
	log(("road graph: %d pieces, %d attachments, %d connections"):format(count, acount, edges))
	return { mods = mods }
end

local function nearestMod(g, pos)
	local best, bd
	for _, mod in pairs(g.mods) do
		local d = V3(mod.pos.X - pos.X, (mod.pos.Y - pos.Y) * 10, mod.pos.Z - pos.Z).Magnitude
		if not bd or d < bd then best, bd = mod, d end
	end
	return best, bd
end

-- Dijkstra with a small binary heap
local function route(g, fromPos, toPos)
	local s, sd = nearestMod(g, fromPos)
	local t, td = nearestMod(g, toPos)
	if not (s and t) then return nil, "no road pieces" end
	log(("route: start piece %.0f studs from the car, end piece %.0f studs from the target"):format(sd, td))
	local dist, prev, done = { [s] = 0 }, {}, {}
	local heap = { { s, 0 } }
	local function push(n, d)
		heap[#heap + 1] = { n, d }
		local i = #heap
		while i > 1 do
			local p = math.floor(i / 2)
			if heap[p][2] <= heap[i][2] then break end
			heap[p], heap[i] = heap[i], heap[p]
			i = p
		end
	end
	local function pop()
		local top = heap[1]
		local last = table.remove(heap)
		if #heap > 0 then
			heap[1] = last
			local i = 1
			while true do
				local l, r, m = i * 2, i * 2 + 1, i
				if l <= #heap and heap[l][2] < heap[m][2] then m = l end
				if r <= #heap and heap[r][2] < heap[m][2] then m = r end
				if m == i then break end
				heap[m], heap[i] = heap[i], heap[m]
				i = m
			end
		end
		return top
	end
	while #heap > 0 do
		local top = pop()
		local n, d = top[1], top[2]
		if n == t then break end
		if not done[n] then
			done[n] = true
			for o, e in pairs(n.edges) do
				local nd = d + e.cost
				if nd < (dist[o] or math.huge) then dist[o] = nd; prev[o] = n; push(o, nd) end
			end
		end
	end
	if t ~= s and not prev[t] then return nil, "no road connection between here and there" end
	local path, cur = {}, t
	while cur do table.insert(path, 1, cur); cur = prev[cur] end
	-- waypoints: the connection points between pieces, plus a piece centre where the road bends
	local wps = {}
	local last = fromPos
	for i = 1, #path - 1 do
		local m, n = path[i], path[i + 1]
		local via = m.edges[n].via
		-- distance of the piece centre from the straight line last -> via
		local ab = V3(via.X - last.X, 0, via.Z - last.Z)
		if ab.Magnitude > 1 then
			local ap = V3(m.pos.X - last.X, 0, m.pos.Z - last.Z)
			local proj = math.clamp(ap:Dot(ab.Unit), 0, ab.Magnitude)
			local lateral = (ap - ab.Unit * proj).Magnitude
			if lateral > 4 then wps[#wps + 1] = m.pos end
		end
		wps[#wps + 1] = via
		last = via
	end
	wps[#wps + 1] = path[#path].pos
	return wps, path[#path].pos
end

-- driving -------------------------------------------------------------------------------------------------------
local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
local function yawOf(v) return math.atan2(v.X, v.Z) end

function Drive.To(targetPos, opts)
	opts = opts or {}
	if Drive.Busy then return false, "busy" end
	Drive.Busy, Drive.Cancel = true, false
	local ok, res, why = pcall(function()
		local car = workspace:FindFirstChild("Vehicles") and workspace.Vehicles:FindFirstChild(lp.Name)
		local seat = car and car:FindFirstChild("DriveSeat")
		local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
		if not (car and seat and hum and hum.SeatPart == seat) then return false, "sit in your car first" end

		local gerr
		if not graph then graph, gerr = build() end
		if not graph then return false, "road graph missing: " .. tostring(gerr) end
		local wps, endPos = route(graph, seat.Position, targetPos)
		if not wps then return false, endPos end
		log(("route: %d waypoints, ends at (%.0f,%.0f,%.0f)"):format(#wps, endPos.X, endPos.Y, endPos.Z))

		-- controls: set the local attribute (the car's drive code reads it) AND tell the server, exactly like the game's own client
		local cur = { Throttle = 0, Steering = 0 }
		local lastSent = { Throttle = 0, Steering = 0 }
		local lastSteerT = 0
		local function setCtl(name, value, force)
			value = math.clamp(value, -1, 1)
			if name == "Steering" then value = math.floor(value * 10 + 0.5) / 10 end
			if value == cur[name] and not force then return end
			if name == "Steering" and not force and os.clock() - lastSteerT < 0.05 then return end
			cur[name] = value
			if name == "Steering" then lastSteerT = os.clock() end
			pcall(function() car:SetAttribute(name, value) end)
			local r = remote(name == "Throttle" and REM.THROTTLE or REM.STEER)
			if r then pcall(function() r:FireServer(car, value) end) end
		end
		local function release() setCtl("Throttle", 0, true); setCtl("Steering", 0, true) end

		if car:GetAttribute("IsOn") ~= true then
			local r = remote(REM.IGNITION)
			if r then pcall(function() r:FireServer(car, true) end) end
			task.wait(0.6)
		end
		if car:GetAttribute("ParkingBrake") == true then pcall(function() car:SetAttribute("ParkingBrake", false) end) end

		local function speedFlat() local v = seat.AssemblyLinearVelocity; return V3(v.X, 0, v.Z).Magnitude end

		-- calibration 1: which way is "forward" for the seat? push the throttle and look where the car goes
		setCtl("Throttle", 1)
		local t0 = os.clock()
		while os.clock() - t0 < 3 and speedFlat() < 4 and not Drive.Cancel do task.wait(0.05) end
		if speedFlat() < 3 then release(); return false, "the car does not move (engine off / parking brake / no road under it?)" end
		local v0 = seat.AssemblyLinearVelocity
		local fwdLocal = seat.CFrame:VectorToObjectSpace(V3(v0.X, 0, v0.Z).Unit)
		local axis = { V3(1, 0, 0), V3(0, 0, 1) }
		local best, bv = nil, 0
		for _, ax in ipairs(axis) do
			local d = fwdLocal:Dot(ax)
			if math.abs(d) > math.abs(bv) then best, bv = ax, d end
		end
		fwdLocal = best * (bv >= 0 and 1 or -1)
		local function forward() local f = seat.CFrame:VectorToWorldSpace(fwdLocal); return V3(f.X, 0, f.Z).Unit end
		log(("forward axis in seat space: (%.0f,%.0f,%.0f), speed %.1f"):format(fwdLocal.X, fwdLocal.Y, fwdLocal.Z, speedFlat()))

		-- calibration 2: does a positive Steering raise or lower the heading angle?
		local steerSign = 1
		do
			local y0 = yawOf(forward())
			setCtl("Steering", 0.8)
			task.wait(0.9)
			local dy = wrap(yawOf(forward()) - y0)
			setCtl("Steering", 0)
			steerSign = dy >= 0 and 1 or -1
			log(("steering: +0.8 for 0.9 s changed the heading by %.2f rad -> sign %d"):format(dy, steerSign))
		end

		local idx, stuckSince, recoveries = 1, nil, 0
		Drive.State = { name = opts.name or "destination", wps = wps, idx = 1, spd = 0, remain = 0, err = 0 }
		local startT = os.clock()
		local totalD = 0
		do local p = seat.Position; for _, w in ipairs(wps) do totalD = totalD + flat(p, w); p = w end end
		local limit = totalD / math.max(Drive.MaxSpeed * 0.35, 8) + 60
		local arrive = opts.arrive or 22
		local lastLog = 0
		while not Drive.Cancel and os.clock() - startT < limit do
			RunService.Heartbeat:Wait()
			if hum.SeatPart ~= seat then release(); return false, "left the car" end
			local pos = seat.Position
			local spd = speedFlat()
			local fwd = forward()
			while idx < #wps and flat(pos, wps[idx]) < 12 do idx = idx + 1 end
			local final = (idx == #wps)
			local remain = flat(pos, wps[idx])
			if final and remain < arrive then
				setCtl("Throttle", -1); setCtl("Steering", 0)
				local tb = os.clock()
				while speedFlat() > 2.5 and os.clock() - tb < 4 do task.wait(0.05) end
				release()
				return true, "arrived"
			end
			-- aim at a point a little ahead on the route
			local look = math.clamp(spd * 0.45, 14, 40)
			local ti = idx
			local acc = flat(pos, wps[idx])
			while ti < #wps and acc < look do acc = acc + flat(wps[ti], wps[ti + 1]); ti = ti + 1 end
			local aim = wps[ti]
			local dirv = V3(aim.X - pos.X, 0, aim.Z - pos.Z)
			if dirv.Magnitude < 0.5 then dirv = fwd end
			local e = wrap(yawOf(dirv) - yawOf(fwd))
			setCtl("Steering", math.clamp(e * 1.8, -1, 1) * steerSign)
			-- speed: slower in corners and when the end is near
			local totalRemain = remain
			for i = idx, #wps - 1 do totalRemain = totalRemain + flat(wps[i], wps[i + 1]) end
			do
				local st = Drive.State
				if st then st.idx, st.spd, st.remain, st.err, st.fwd = idx, spd, totalRemain, e, fwd end
			end
			local corner = 1 - math.clamp(math.abs(e) / 0.9, 0, 0.7)
			local target = math.min(Drive.MaxSpeed * corner, math.sqrt(2 * 9 * math.max(totalRemain - arrive, 0)) + 10)
			if spd < target - 4 then setCtl("Throttle", 1)
			elseif spd > target + 10 then setCtl("Throttle", -1)
			elseif spd > target then setCtl("Throttle", 0) end
			-- stuck? back up a bit, then try again
			if spd < 1.5 and cur.Throttle ~= 0 and os.clock() - startT > 3 then
				stuckSince = stuckSince or os.clock()
				if os.clock() - stuckSince > 2.5 then
					recoveries = recoveries + 1
					log(("stuck at (%.0f,%.0f,%.0f), backing up (%d)"):format(pos.X, pos.Y, pos.Z, recoveries))
					if recoveries > 6 then release(); return false, "stuck" end
					setCtl("Throttle", -1); setCtl("Steering", -math.clamp(e, -1, 1) * steerSign)
					task.wait(1.6)
					setCtl("Steering", 0)
					stuckSince = nil
				end
			else
				stuckSince = nil
			end
			if os.clock() - lastLog > 3 then
				lastLog = os.clock()
				log(("drive: %.0f studs left, speed %.0f, waypoint %d/%d, heading error %.2f"):format(totalRemain, spd, idx, #wps, e))
			end
		end
		release()
		return false, Drive.Cancel and "cancelled" or "took too long"
	end)
	Drive.Busy = false
	Drive.State = nil
	if not ok then log("drive error: " .. tostring(res)); return false, tostring(res) end
	return res, why or res
end

function Drive.Stop() Drive.Cancel = true end
function Drive.GetGraph() return graph end
function Drive.Prepare() if not graph then local g = build(); graph = g end return graph end

return Drive

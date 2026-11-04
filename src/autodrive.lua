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
local RoadPlan = __import("roadplan")

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
local PIECES = {} -- road piece -> { m = speed multiplier, n = times driven, s = times stuck }
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

-- head (optional): the direction the car faces. Pieces behind the car count as farther away, so the route starts forwards instead of
-- sending the car into a U-turn when a piece ahead is only a little further.
local function nearestMod(g, pos, head)
	local best, bd, bscore
	for _, mod in pairs(g.mods) do
		local dx, dz = mod.pos.X - pos.X, mod.pos.Z - pos.Z
		local d = V3(dx, (mod.pos.Y - pos.Y) * 0.3, dz).Magnitude
		local score = d
		if head then
			local fl = math.sqrt(dx * dx + dz * dz)
			if fl > 6 then
				local dotp = (dx * head.X + dz * head.Z) / fl
				if dotp < 0 then score = score + 110 * -dotp end
			end
		end
		if not bscore or score < bscore then best, bd, bscore = mod, d, score end
	end
	return best, bd
end

-- places where the road is blocked (bollards, gates, walls...): TRIP_BLOCK = found during this destination, PERM_BLOCK = remembered between
-- sessions (counted; a spot that blocked the car in 2 different trips is avoided for good)
local TRIP_BLOCK, PERM_BLOCK = {}, {}
local function nearSpot(b, x, z) local dx, dz = b.x - x, b.z - z; return math.sqrt(dx * dx + dz * dz) end
local function isBlocked(p)
	for _, b in ipairs(TRIP_BLOCK) do if nearSpot(b, p.X, p.Z) < 16 then return true end end
	for _, b in ipairs(PERM_BLOCK) do if (b.n or 0) >= 2 and nearSpot(b, p.X, p.Z) < 16 then return true end end
	return false
end
local function blockedXZ(x, z)
	for _, b in ipairs(TRIP_BLOCK) do if nearSpot(b, x, z) < 16 then return true end end
	for _, b in ipairs(PERM_BLOCK) do if (b.n or 0) >= 2 and nearSpot(b, x, z) < 16 then return true end end
	return false
end
local function addBlock(x, z, why)
	for _, b in ipairs(TRIP_BLOCK) do if nearSpot(b, x, z) < 12 then return end end
	TRIP_BLOCK[#TRIP_BLOCK + 1] = { x = x, z = z }
	local found = false
	for _, b in ipairs(PERM_BLOCK) do
		if nearSpot(b, x, z) < 12 then b.n = (b.n or 0) + 1; found = true; break end
	end
	if not found then PERM_BLOCK[#PERM_BLOCK + 1] = { x = math.floor(x), z = math.floor(z), n = 1 } end
	log(("blocked spot at (%.0f, %.0f): %s"):format(x, z, tostring(why)))
end

local function ignorable(inst)
	local n = inst.Name
	return inst == workspace.Terrain or inst:FindFirstAncestor("Traffic Lights") ~= nil or n:find("Road", 1, true) ~= nil or n == "Curb" or n == "Sidewalk" or n:find("Marking", 1, true) ~= nil
end

local function scanParams(car)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	pcall(function() params.RespectCanCollide = true end)
	local ex = { lp.Character, car }
	local vf = workspace:FindFirstChild("Vehicles")
	if vf then ex[#ex + 1] = vf end
	params.FilterDescendantsInstances = ex
	return params
end

-- The REAL road surface: the parts called "Road" inside Workspace.Roads (the game's own navigation texture lives on them too).
-- The minimap graph only says roughly where roads are; these helpers put the route onto the actual asphalt and tell whether the car is on it.
local roadsKnown = false
local ROAD_PARAMS
local function roadParams()
	if not ROAD_PARAMS then
		ROAD_PARAMS = RaycastParams.new()
		ROAD_PARAMS.FilterType = Enum.RaycastFilterType.Include
		local r = workspace:FindFirstChild("Roads")
		ROAD_PARAMS.FilterDescendantsInstances = r and { r } or {}
	end
	return ROAD_PARAMS
end
local function roadAt(x, z, y)
	local res = workspace:Raycast(V3(x, (y or 10) + 40, z), V3(0, -160, 0), roadParams())
	if res and res.Instance.Name:find("Road", 1, true) then return res.Position end
	return nil
end
local function snapRoad(x, z, y)
	local p = roadAt(x, z, y)
	if p then return p, 0 end
	for r = 3, 45, 3 do
		for k = 0, 11 do
			local a = k * math.pi / 6
			local q = roadAt(x + math.cos(a) * r, z + math.sin(a) * r, y)
			if q then return q, r end
		end
	end
	return nil
end

-- A* over a grid of road cells. passable(x, z) says whether a point is on clear road. Returns a list of {x, z} from near (ax,az) to near (bx,bz),
-- shortened by line-of-sight, or nil. This is what takes the car around a roundabout island instead of across it.
local function gridPath(passable, ax, az, bx, bz, cell, pad)
	local minX, maxX = math.min(ax, bx) - pad, math.max(ax, bx) + pad
	local minZ, maxZ = math.min(az, bz) - pad, math.max(az, bz) + pad
	local nx, nz = math.ceil((maxX - minX) / cell), math.ceil((maxZ - minZ) / cell)
	if nx * nz > 9000 then return nil end
	local function cellOf(x, z)
		return math.clamp(math.floor((x - minX) / cell), 0, nx - 1), math.clamp(math.floor((z - minZ) / cell), 0, nz - 1)
	end
	local function centre(ix, iz) return minX + (ix + 0.5) * cell, minZ + (iz + 0.5) * cell end
	local memo = {}
	local function ok(ix, iz)
		if ix < 0 or iz < 0 or ix >= nx or iz >= nz then return false end
		local k = iz * nx + ix
		local v = memo[k]
		if v == nil then
			local cx, cz = centre(ix, iz)
			v = passable(cx, cz) and true or false
			memo[k] = v
		end
		return v
	end
	local function snapCell(x, z)
		local ix, iz = cellOf(x, z)
		if ok(ix, iz) then return ix, iz end
		for r = 1, 6 do
			local best, bd
			for dx = -r, r do
				for dz = -r, r do
					if math.max(math.abs(dx), math.abs(dz)) == r and ok(ix + dx, iz + dz) then
						local d = dx * dx + dz * dz
						if not bd or d < bd then best, bd = { ix + dx, iz + dz }, d end
					end
				end
			end
			if best then return best[1], best[2] end
		end
		return nil
	end
	local sx, sz = snapCell(ax, az)
	local gx, gz = snapCell(bx, bz)
	if not (sx and gx) then return nil end
	local startK, goalK = sz * nx + sx, gz * nx + gx
	local g, parent, closed = { [startK] = 0 }, {}, {}
	local heap = {}
	local function push(k, f)
		heap[#heap + 1] = { k, f }
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
	local function h(ix, iz) local dx, dz = ix - gx, iz - gz; return math.sqrt(dx * dx + dz * dz) end
	push(startK, h(sx, sz))
	local expanded = 0
	local found = false
	local dirs = { { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 }, { 1, 1, 1.4142 }, { 1, -1, 1.4142 }, { -1, 1, 1.4142 }, { -1, -1, 1.4142 } }
	while #heap > 0 do
		local top = pop()
		local k = top[1]
		if k == goalK then found = true; break end
		if not closed[k] then
			closed[k] = true
			expanded = expanded + 1
			if expanded > 5000 then return nil end
			local ix, iz = k % nx, math.floor(k / nx)
			for _, d in ipairs(dirs) do
				local jx, jz = ix + d[1], iz + d[2]
				if ok(jx, jz) and (d[3] == 1 or (ok(ix + d[1], iz) and ok(ix, iz + d[2]))) then
					local nk = jz * nx + jx
					local ng = g[k] + d[3]
					if ng < (g[nk] or math.huge) then
						g[nk], parent[nk] = ng, k
						push(nk, ng + h(jx, jz))
					end
				end
			end
		end
	end
	if not found then return nil end
	local cells, cur = {}, goalK
	while cur do
		table.insert(cells, 1, { centre(cur % nx, math.floor(cur / nx)) })
		cur = parent[cur]
	end
	-- string pulling: drop cells while the straight line stays on road
	local function lineOk(x1, z1, x2, z2)
		local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
		local steps = math.max(1, math.ceil(len / (cell * 0.5)))
		for s = 1, steps - 1 do
			local t = s / steps
			local ix, iz = cellOf(x1 + (x2 - x1) * t, z1 + (z2 - z1) * t)
			if not ok(ix, iz) then return false end
		end
		return true
	end
	local out = { cells[1] }
	local i = 1
	while i < #cells do
		local j = #cells
		while j > i + 1 and not lineOk(cells[i][1], cells[i][2], cells[j][1], cells[j][2]) do j = j - 1 end
		out[#out + 1] = cells[j]
		i = j
	end
	return out
end

local CLEAR, rayCount = {}, 0
-- is (x, z) clear road: asphalt here and 3.5 studs to every side (so the car does not scrape the edge)? remembered between trips
local function clearAt(x, z)
	local k = math.floor(x / 4) .. "," .. math.floor(z / 4)
	local v = CLEAR[k]
	if v ~= nil then return v end
	rayCount = rayCount + 1
	if rayCount % 250 == 0 then task.wait() end
	v = (roadAt(x, z, 5) and roadAt(x + 3.5, z, 5) and roadAt(x - 3.5, z, 5) and roadAt(x, z + 3.5, 5) and roadAt(x, z - 3.5, 5)) and true or false
	CLEAR[k] = v
	return v
end
local function lineClear(ax, az, bx, bz)
	local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local steps = math.max(1, math.ceil(len / 5))
	for i = 0, steps do
		local t = i / steps
		if not clearAt(ax + (bx - ax) * t, az + (bz - az) * t) then return false end
	end
	return true
end

-- the route as a dense polyline (a point every ~10-12 studs) lying on the real road surface
local function densify(wps, keys, fromPos)
	local dense, dkeys = {}, {}
	local nStraight, nGrid, nFail, nOnRoad = 0, 0, 0, 0
	local function add(x, z, y, key)
		dense[#dense + 1] = V3(x, y, z)
		dkeys[#dense] = key
	end
	local function sample(ax, ay, az, bx, by, bz, key, step)
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local n = math.max(1, math.floor(len / step + 0.5))
		for k = 1, n do
			local t = k / n
			add(ax + (bx - ax) * t, az + (bz - az) * t, ay + (by - ay) * t, key)
		end
	end
	local px, py, pz = fromPos.X, fromPos.Y, fromPos.Z
	for i, w in ipairs(wps) do
		local key = keys and keys[i] or false
		if lineClear(px, pz, w.X, w.Z) then
			nStraight = nStraight + 1
			sample(px, py, pz, w.X, w.Y, w.Z, key, 12)
			px, py, pz = w.X, w.Y, w.Z
		else
			local pts = gridPath(clearAt, px, pz, w.X, w.Z, 6, 45)
			if pts then
				nGrid = nGrid + 1
				local lx, ly, lz = px, py, pz
				for j, q in ipairs(pts) do
					local hit = roadAt(q[1], q[2], 5)
					local qy = hit and hit.Y or w.Y
					sample(lx, ly, lz, q[1], qy, q[2], key, 10)
					lx, ly, lz = q[1], qy, q[2]
				end
				px, py, pz = lx, ly, lz
			else
				-- no road path found (or the road has another name): straight line, each point moved onto the nearest road surface
				nFail = nFail + 1
				local len = math.sqrt((w.X - px) ^ 2 + (w.Z - pz) ^ 2)
				local n = math.max(1, math.floor(len / 12 + 0.5))
				for k = 1, n do
					local t = k / n
					local x, z, y = px + (w.X - px) * t, pz + (w.Z - pz) * t, py + (w.Y - py) * t
					local sp = snapRoad(x, z, y)
					if sp then add(sp.X, sp.Z, sp.Y, key) else add(x, z, y, key) end
				end
				px, py, pz = w.X, w.Y, w.Z
			end
		end
		if #dense % 30 == 0 then task.wait() end
	end
	for _, v in pairs(CLEAR) do if v then nOnRoad = nOnRoad + 1; break end end
	if nOnRoad > 0 then roadsKnown = true end
	log(("route: %d points: %d straight stretches, %d planned around obstacles on the road, %d without a road path"):format(#dense, nStraight, nGrid, nFail))
	return dense, dkeys
end

-- drive a box the size of the car along every route segment: anything solid and upright in the way (bollards, gates, walls) is a block.
-- Floors / ramps / curbs do not count (their surfaces face up).
local function scanRoute(wps, fromPos, car)
	local params = scanParams(car)
	local useBlock = true
	local hits = {}
	local prev = fromPos
	for i, w in ipairs(wps) do
		local a = prev
		prev = w
		local d = V3(w.X - a.X, 0, w.Z - a.Z)
		local len = d.Magnitude
		local skip = (i == 1) and 10 or 0
		if len > skip + 6 then
			local dir = d.Unit
			local origin = V3(a.X, a.Y + 3, a.Z) + dir * skip
			local vec = dir * (len - skip)
			local res
			if useBlock then
				local okb, r = pcall(function() return workspace:Blockcast(CFrame.lookAt(origin, origin + dir), V3(6.5, 3, 1), vec, params) end)
				if okb then res = r else useBlock = false end
			end
			if not useBlock then res = workspace:Raycast(origin, vec, params) end
			if res and math.abs(res.Normal.Y) < 0.5 and not ignorable(res.Instance) then
				local m = res.Instance:FindFirstAncestorOfClass("Model")
				if not (m and m:FindFirstChildOfClass("Humanoid")) then
					hits[#hits + 1] = { pos = res.Position, name = res.Instance:GetFullName(), seg = i }
				end
			end
		end
	end
	return hits
end

-- Dijkstra with a small binary heap
local function route(g, fromPos, toPos, relax, head)
	local s, sd = nearestMod(g, fromPos, head)
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
				if relax or not (isBlocked(e.via) or isBlocked(o.pos)) then
					local pr = PIECES[math.floor(o.pos.X / 10) .. "," .. math.floor(o.pos.Z / 10)]
					local nd = d + e.cost * (1 + 3 * math.min((pr and pr.s) or 0, 3))
					if nd < (dist[o] or math.huge) then dist[o] = nd; prev[o] = n; push(o, nd) end
				end
			end
		end
	end
	if t ~= s and not prev[t] then return nil, "no road connection between here and there" end
	local path, cur = {}, t
	while cur do table.insert(path, 1, cur); cur = prev[cur] end
	-- waypoints: the connection points between pieces, plus a piece centre where the road bends
	local wps, keys = {}, {}
	local function keyOf(m) return math.floor(m.pos.X / 10) .. "," .. math.floor(m.pos.Z / 10) end
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
			-- (piece centres are no longer added: in a roundabout that is the island. densify() plans along the real road.)
		end
		wps[#wps + 1] = via
		keys[#wps] = keyOf(m)
		last = via
	end
	wps[#wps + 1] = path[#path].pos
	keys[#wps] = keyOf(path[#path])
	return wps, path[#path].pos, keys
end

-- "training": the driving parameters are re-tried with small random changes on every trip; a change that drives better (closer to the
-- route, fewer stuck / turn-around moments, quicker) is kept. Saved in ScrdsxScript/drivetune.json so it keeps improving between sessions.
local TUNE_FILE = "ScrdsxScript/drivetune.json"
local RANGE = { kp = { 1.0, 5.0 }, kd = { 0.03, 0.5 }, lookBase = { 6, 28 }, lookGain = { 0.1, 0.9 }, bendDiv = { 0.9, 2.0 }, speedMul = { 0.6, 1.3 }, latAcc = { 15, 80 } }
local best = { p = { kp = 4.0, kd = 0.08, lookBase = 22.5, lookGain = 0.21, bendDiv = 1.4, speedMul = 0.95, latAcc = 38.6 }, cost = nil, trips = 0, pieces = {} }
local loaded = false
local function loadTune()
	if loaded then return end
	loaded = true
	pcall(function()
		if isfile and readfile and isfile(TUNE_FILE) then
			local d = game:GetService("HttpService"):JSONDecode(readfile(TUNE_FILE))
			if type(d) == "table" and type(d.p) == "table" then
				for k, r in pairs(RANGE) do
					if tonumber(d.p[k]) then best.p[k] = math.clamp(d.p[k], r[1], r[2]) end
				end
				best.cost, best.trips = tonumber(d.cost), tonumber(d.trips) or 0
				if type(d.pieces) == 'table' then PIECES = d.pieces end
				if type(d.blocked) == 'table' then PERM_BLOCK = d.blocked end
			end
		end
	end)
end
function Drive.PieceCount() local n = 0 for _ in pairs(PIECES) do n = n + 1 end return n end
local function saveTune()
	best.pieces = PIECES
	best.blocked = PERM_BLOCK
	pcall(function()
		if writefile then
			pcall(function() if makefolder then makefolder("ScrdsxScript") end end)
			writefile(TUNE_FILE, game:GetService("HttpService"):JSONEncode(best))
		end
	end)
end
-- what the car learned about one road piece (a corner / junction): a speed multiplier that goes down where it got stuck, had to back
-- up or wandered off the road, and slowly up where it drove cleanly
local function learnPiece(key, stat)
	if not key or not stat then return end
	local rec = PIECES[key] or { m = 1, n = 0, s = 0 }
	if stat.stuck then rec.s = (rec.s or 0) + 1 end
	if stat.stuck or stat.rev then rec.m = math.max(0.4, rec.m * 0.72)
	elseif stat.maxOff > 14 or stat.maxErr > 1.1 then rec.m = math.max(0.4, rec.m * 0.9)
	else rec.m = math.min(1.45, rec.m * 1.05) end
	rec.n = (rec.n or 0) + 1
	PIECES[key] = rec
end
local function pieceMul(key)
	local rec = key and PIECES[key]
	return rec and rec.m or 1
end

function Drive.NextParams()
	loadTune()
	local explore = best.cost ~= nil and math.random() < 0.7
	local p = {}
	for k, v in pairs(best.p) do
		local r = RANGE[k]
		p[k] = explore and math.clamp(v * (1 + (math.random() - 0.5) * 0.3), r[1], r[2]) or v
	end
	return p, explore
end
function Drive.Report(p, explore, cost)
	-- (piece memory is saved together with the settings)
	best.trips = best.trips + 1
	if best.cost == nil or (explore and cost < best.cost) then
		best.p, best.cost = p, cost
		log(("training: new best settings, cost %.1f (kp %.2f kd %.2f look %.1f+%.2f*v bend %.2f speed x%.2f)"):format(cost, p.kp, p.kd, p.lookBase, p.lookGain, p.bendDiv, p.speedMul))
	else
		if not explore then best.cost = best.cost * 0.6 + cost * 0.4 end -- the settings in use again: refresh their score
		log(("training: this trip cost %.1f (best %.1f), %s"):format(cost, best.cost, explore and "variation rejected" or "best settings"))
	end
	saveTune()
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

		loadTune()
		if (opts.replans or 0) == 0 then TRIP_BLOCK = {} end
		local wps, endPos, wpKeys
		local head0
		do
			local lv = Drive.cal and seat.CFrame:VectorToWorldSpace(Drive.cal.fwdLocal) or seat.CFrame.LookVector
			head0 = V3(lv.X, 0, lv.Z)
			head0 = head0.Magnitude > 0.1 and head0.Unit or nil
		end

		-- 1) planner on the REAL road surface (src/roadplan.lua, data from the map export): follows the actual asphalt, goes round islands,
		--    keeps to the middle of the road, never touches a cell with something solid on it
		RoadPlan.Yield = function() task.wait() end
		for attempt = 1, 3 do
			local t0 = os.clock()
			local pts, why = RoadPlan.Route(seat.Position.X, seat.Position.Z, targetPos.X, targetPos.Z, {
				head = head0 and { x = head0.X, z = head0.Z } or nil, ay = seat.Position.Y, by = targetPos.Y, blocked = blockedXZ,
			})
			if not pts then
				log("road-surface planner: " .. tostring(why) .. " (using the minimap graph instead)")
				wps = nil
				break
			end
			local w, k, len = {}, {}, 0
			for i, q in ipairs(pts) do
				w[i] = V3(q.x, q.y, q.z)
				k[i] = math.floor(q.x / 10) .. "," .. math.floor(q.z / 10)
				if i > 1 then len = len + flat(w[i], w[i - 1]) end
			end
			wps, wpKeys, endPos = w, k, w[#w]
			log(("route (road surface): %d points, %.0f studs, planned in %.2f s, ends %.0f studs from the target"):format(#w, len, os.clock() - t0, flat(endPos, targetPos)))
			local hits = {}
			for _, h in ipairs(scanRoute(wps, seat.Position, car)) do
				if flat(h.pos, endPos) > 90 then hits[#hits + 1] = h end
			end
			if #hits == 0 then break end
			for i, h in ipairs(hits) do
				if i > 3 then break end
				addBlock(h.pos.X, h.pos.Z, "solid " .. h.name .. " on the route")
			end
			if attempt == 3 then log("no clear route found, driving the best one") end
		end

		-- 2) fallback: the minimap's road graph
		if not wps then
			local gerr
			if not graph then graph, gerr = build() end
			if not graph then return false, "no road route: " .. tostring(gerr) end
			for attempt = 1, 3 do
				wps, endPos, wpKeys = route(graph, seat.Position, targetPos, false, head0)
				if not wps and (#TRIP_BLOCK > 0 or #PERM_BLOCK > 0) then
					log("every route is blocked somewhere, ignoring the blocked spots")
					wps, endPos, wpKeys = route(graph, seat.Position, targetPos, true, head0)
					if wps then wps, wpKeys = densify(wps, wpKeys, seat.Position) end
					break
				end
				if not wps then return false, endPos end
				local dw, dk = densify(wps, wpKeys, seat.Position)
				wps, wpKeys = dw, dk
				local hits = {}
				for _, h in ipairs(scanRoute(wps, seat.Position, car)) do
					if flat(h.pos, endPos) > 90 then hits[#hits + 1] = h end -- the last stretch next to the destination always has fences / walls around it
				end
				if #hits == 0 then
					if attempt > 1 then log(("route %d is clear"):format(attempt)) end
					break
				end
				for i, h in ipairs(hits) do
					if i > 3 then break end
					addBlock(h.pos.X, h.pos.Z, "solid " .. h.name .. " on the route")
				end
				if attempt == 3 then log("no clear route found, driving the best one") end
			end
			if not wps then return false, endPos end
		end
		if not wps then return false, endPos end
		saveTune()
		log(("route: %d waypoints, ends at (%.0f,%.0f,%.0f)"):format(#wps, endPos.X, endPos.Y, endPos.Z))

		-- Controls. Default = the real keys (W/S throttle, A/D steering, N ignition) pressed through the input system, so the game's own
		-- code does everything a player's input does (sets Throttle/Steering, tells the server). Steering is on/off per key, so it is
		-- pulse-width modulated to get in-between values. Fallback = write the attributes + send the remotes ourselves.
		local VIM = game:GetService("VirtualInputManager")
		local useKeys = Drive.UseKeys ~= false
		local cur = { Throttle = 0, Steering = 0 }
		local down = {}
		local function key(code, on)
			if (down[code] or false) == on then return end
			down[code] = on
			pcall(function() VIM:SendKeyEvent(on, code, false, game) end)
		end
		local wheel = 0 -- modelled steering wheel position (same -1..1 space as the Steering attribute)
		local pwmConn
		local function pwmStep(dt)
			dt = math.min(dt, 1 / 20)
			local want = cur.Steering
			local bestK, bestErr, bestNext = 0, math.huge, wheel
			for _, a in ipairs({ 0, 1, -1 }) do
				local rate = ((wheel * a) <= 0) and 4.5 or 1.5
				local nxt = wheel + math.clamp(a - wheel, -rate * dt, rate * dt)
				local err = math.abs(nxt - want)
				if err < bestErr - 1e-6 then bestK, bestErr, bestNext = a, err, nxt end
			end
			wheel = bestNext
			key(Enum.KeyCode.D, bestK > 0)
			key(Enum.KeyCode.A, bestK < 0)
		end
		local function setCtl(name, value, force)
			value = math.clamp(value, -1, 1)
			if name == "Steering" then value = math.floor(value * 50 + 0.5) / 50 end
			if value == cur[name] and not force then return end
			cur[name] = value
			if useKeys then
				if name == "Throttle" then
					key(Enum.KeyCode.W, value > 0)
					key(Enum.KeyCode.S, value < 0)
				end
			else
				pcall(function() car:SetAttribute(name, value) end)
				local r = remote(name == "Throttle" and REM.THROTTLE or REM.STEER)
				if r then pcall(function() r:FireServer(car, value) end) end
			end
		end
		if useKeys then pwmConn = RunService.Heartbeat:Connect(pwmStep) end
		local function release()
			setCtl("Throttle", 0, true)
			setCtl("Steering", 0, true)
			if pwmConn then pwmConn:Disconnect(); pwmConn = nil end
			for _, code in ipairs({ Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.A, Enum.KeyCode.D }) do key(code, false) end
		end

		log(("car state: IsOn=%s ParkingBrake=%s fuel=%s health=%s Throttle=%s"):format(tostring(car:GetAttribute("IsOn")), tostring(car:GetAttribute("ParkingBrake")),
			tostring(car:GetAttribute("currentFuel")), tostring(car:GetAttribute("currentHealth")), tostring(car:GetAttribute("Throttle"))))
		-- engine: press N like a player, then wait until the server says it is on
		for attempt = 1, 3 do
			if car:GetAttribute("IsOn") == true then break end
			if attempt == 1 or not useKeys then
				key(Enum.KeyCode.N, true); task.wait(0.08); key(Enum.KeyCode.N, false)
			end
			local r = remote(REM.IGNITION)
			if attempt > 1 and r then pcall(function() r:FireServer(car, true) end) end
			local t = os.clock()
			while os.clock() - t < 1.6 and car:GetAttribute("IsOn") ~= true do task.wait(0.1) end
		end
		log("engine IsOn = " .. tostring(car:GetAttribute("IsOn")))
		if car:GetAttribute("ParkingBrake") == true then
			key(Enum.KeyCode.P, true); task.wait(0.08); key(Enum.KeyCode.P, false)
			task.wait(0.3)
			log("parking brake = " .. tostring(car:GetAttribute("ParkingBrake")))
		end

		local function speedFlat() local v = seat.AssemblyLinearVelocity; return V3(v.X, 0, v.Z).Magnitude end

		local fwdLocal, steerSign
		local function forward() local f = seat.CFrame:VectorToWorldSpace(fwdLocal); return V3(f.X, 0, f.Z).Unit end
		if Drive.cal then
			-- same car, same keys: no need to drive it around again to find out which way is forward / which way steers
			fwdLocal, steerSign = Drive.cal.fwdLocal, Drive.cal.steerSign
			if Drive.cal.useKeys == false and useKeys then
				useKeys = false
				if pwmConn then pwmConn:Disconnect(); pwmConn = nil end
				for _, code in ipairs({ Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.A, Enum.KeyCode.D }) do key(code, false) end
			end
			log(("calibration remembered: forward axis (%.0f,%.0f,%.0f), steering sign %d"):format(fwdLocal.X, fwdLocal.Y, fwdLocal.Z, steerSign))
		else
			-- calibration 1: which way is "forward" for the seat? push the throttle and look where the car goes
			setCtl("Throttle", 1)
			local t0 = os.clock()
			while os.clock() - t0 < 3 and speedFlat() < 4 and not Drive.Cancel do task.wait(0.05) end
			if speedFlat() < 3 and useKeys then
				log("the keys did not move the car, trying the attribute + remote way")
				setCtl("Throttle", 0, true)
				useKeys = false
				if pwmConn then pwmConn:Disconnect(); pwmConn = nil end
				for _, code in ipairs({ Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.A, Enum.KeyCode.D }) do key(code, false) end
				cur.Throttle = 0
				setCtl("Throttle", 1)
				t0 = os.clock()
				while os.clock() - t0 < 3 and speedFlat() < 4 and not Drive.Cancel do task.wait(0.05) end
			end
			if speedFlat() < 3 then
				log(("no movement: IsOn=%s ParkingBrake=%s Throttle attr=%s Occupant=%s"):format(tostring(car:GetAttribute("IsOn")), tostring(car:GetAttribute("ParkingBrake")),
					tostring(car:GetAttribute("Throttle")), tostring(seat.Occupant)))
				release()
				return false, "the car does not move (engine off / parking brake / no road under it?)"
			end
			local v0 = seat.AssemblyLinearVelocity
			fwdLocal = seat.CFrame:VectorToObjectSpace(V3(v0.X, 0, v0.Z).Unit)
			local axis = { V3(1, 0, 0), V3(0, 0, 1) }
			local bestAx, bv = nil, 0
			for _, ax in ipairs(axis) do
				local d = fwdLocal:Dot(ax)
				if math.abs(d) > math.abs(bv) then bestAx, bv = ax, d end
			end
			fwdLocal = bestAx * (bv >= 0 and 1 or -1)
			log(("forward axis in seat space: (%.0f,%.0f,%.0f), speed %.1f"):format(fwdLocal.X, fwdLocal.Y, fwdLocal.Z, speedFlat()))

			-- calibration 2: does a positive Steering raise or lower the heading angle?
			steerSign = 1
			do
				local y0 = yawOf(forward())
				setCtl("Steering", 0.8)
				task.wait(0.9)
				local dy = wrap(yawOf(forward()) - y0)
				setCtl("Steering", 0)
				if math.abs(dy) > 0.3 then steerSign = dy >= 0 and 1 or -1 else steerSign = -1 end
				log(("steering: +0.8 for 0.9 s changed the heading by %.2f rad -> sign %d%s"):format(dy, steerSign, math.abs(dy) > 0.3 and "" or " (too small to trust, using the default)"))
			end
			Drive.cal = { fwdLocal = fwdLocal, steerSign = steerSign, useKeys = useKeys }

		end

		-- Pure pursuit: project the car on the route, aim at a point a little way ahead ON the route, steer by the angle to it
		-- (with a damping term on the turn rate so it does not weave), slow down for bends coming up.
		local path = { seat.Position }
		for _, w in ipairs(wps) do path[#path + 1] = w end
		local seglen = {}
		for i = 1, #path - 1 do seglen[i] = flat(path[i], path[i + 1]) end
		local function remainingFrom(i, t)
			local r = seglen[i] * (1 - t)
			for k = i + 1, #path - 1 do r = r + seglen[k] end
			return r
		end
		local function pointAhead(i, t, dist)
			local a, b = path[i], path[i + 1]
			local pos = a + (b - a) * t
			local left = seglen[i] * (1 - t)
			local cur = i
			while dist > left and cur < #path - 1 do
				dist = dist - left
				cur = cur + 1
				pos = path[cur]
				left = seglen[cur]
			end
			if cur >= #path - 1 and dist > left then return path[#path], cur end
			local a2, b2 = path[cur], path[cur + 1]
			if seglen[cur] < 0.01 then return b2, cur end
			return pos + (b2 - a2).Unit * math.min(dist, left), cur
		end
		local P, explore = Drive.NextParams()
		local pathKey = { false }
		for i = 1, #wps do pathKey[i + 1] = wpKeys and wpKeys[i] or false end
		local curKey, pStat = nil, nil
		local learned = 0
		local function closePiece()
			if curKey and pStat then learnPiece(curKey, pStat); learned = learned + 1 end
			curKey, pStat = nil, nil
		end
		local offSum, offN, reverses = 0, 0, 0
		local segIdx, stuckSince, recoveries = 1, nil, 0
		local reversing, revT, revCool = false, 0, 0
		local scanPar = scanParams(car)
		local lastScan, danger, dangerStopT, lastDangerLog = 0, nil, nil, 0
		local lastRoadChk, offRoadSince, roadPt = 0, nil, nil
		local lastHp, hp0, slowUntil = 0, car:GetAttribute("currentHealth"), 0
		local tuneT, tuneFlips, tuneCte, tuneN, lastSteerSign = os.clock(), 0, 0, 0, 0
		local farSince = nil
		Drive.State = { name = opts.name or "destination", wps = wps, idx = 1, spd = 0, remain = 0, err = 0 }
		local startT = os.clock()
		local startPos = seat.Position
		local totalD = remainingFrom(1, 0)
		local limit = totalD / math.max(Drive.MaxSpeed * 0.3, 8) + 70
		local arrive = opts.arrive or 22
		local lastLog, lastYaw, yawRate = 0, yawOf(forward()), 0
		local lastT = os.clock()
		while not Drive.Cancel and os.clock() - startT < limit do
			RunService.Heartbeat:Wait()
			local nowT = os.clock()
			local dt = math.max(nowT - lastT, 1 / 120)
			lastT = nowT
			if hum.SeatPart ~= seat then
				local up = seat.CFrame.UpVector
				log(("left the car at (%.0f,%.0f,%.0f): speed %.0f, car up-vector Y=%.2f (low = on its side), car health %s, occupant=%s"):format(
					seat.Position.X, seat.Position.Y, seat.Position.Z, speedFlat(), up.Y, tostring(car:GetAttribute("currentHealth")), tostring(seat.Occupant)))
				release()
				if pStat then pStat.stuck = true end
				closePiece()
				saveTune()
				return false, "left the car"
			end
			local pos = seat.Position
			local spd = speedFlat()
			local fwd = forward()
			local yaw = yawOf(fwd)
			yawRate = yawRate * 0.6 + wrap(yaw - lastYaw) / dt * 0.4
			lastYaw = yaw

			-- where am I on the route? (never go backwards along it)
			local bestD, bestI, bestT = math.huge, segIdx, 0
			for i = math.max(segIdx - 1, 1), math.min(#path - 1, segIdx + 6) do
				local a, b = path[i], path[i + 1]
				local ab = V3(b.X - a.X, 0, b.Z - a.Z)
				local l2 = ab:Dot(ab)
				local t = l2 > 0.01 and math.clamp(V3(pos.X - a.X, 0, pos.Z - a.Z):Dot(ab) / l2, 0, 1) or 0
				local d = flat(pos, a + (b - a) * t)
				if d < bestD then bestD, bestI, bestT = d, i, t end
			end
			segIdx = math.max(segIdx, bestI)
			offSum, offN = offSum + bestD, offN + 1
			do
				local key = pathKey[math.min(bestI + 1, #pathKey)]
				if key ~= curKey then
					closePiece()
					curKey, pStat = key, { maxOff = 0, maxErr = 0, stuck = false, rev = false }
				end
				if pStat then pStat.maxOff = math.max(pStat.maxOff, bestD) end
			end
			local remainRoute = remainingFrom(bestI, bestT)
			if remainRoute < arrive or (segIdx >= #path - 1 and flat(pos, path[#path]) < arrive) then
				setCtl("Throttle", -1); setCtl("Steering", 0)
				local tb = os.clock()
				while speedFlat() > 2.5 and os.clock() - tb < 4 do task.wait(0.05) end
				release()
				closePiece()
				log(("training: learned from %d road pieces on this trip (%d pieces known)"):format(learned, Drive.PieceCount()))
				if totalD > 250 and offN > 20 then
					local dur = os.clock() - startT
					local cost = (offSum / offN) * 1.5 + recoveries * 30 + reverses * 15 + (dur / (totalD / 100)) * 0.8
					Drive.Report(P, explore, cost)
				end
				return true, "arrived"
			end

			-- real road check (5 Hz): over asphalt? if not for a moment, aim for the nearest road surface
			if roadsKnown and nowT - lastRoadChk > 0.2 then
				lastRoadChk = nowT
				if roadAt(pos.X, pos.Z, pos.Y) then offRoadSince, roadPt = nil, nil
				else
					offRoadSince = offRoadSince or nowT
					if nowT - offRoadSince > 0.8 then roadPt = snapRoad(pos.X, pos.Z, pos.Y) end
				end
			end
			local offRoad = offRoadSince ~= nil and nowT - offRoadSince > 0.8

			-- damage watch: the car lost health -> we hit something. Slow down and plan around that spot.
			if nowT - lastHp > 0.4 then
				lastHp = nowT
				local hp = car:GetAttribute("currentHealth")
				if type(hp) == "number" then
					if hp0 and hp < hp0 - 10 then
						log(("car damaged: health %.0f -> %.0f at (%.0f,%.0f), speed %.0f"):format(hp0, hp, pos.X, pos.Z, spd))
						slowUntil = nowT + 2.5
						if flat(pos, startPos) > 30 and (opts.replans or 0) < 5 then
							addBlock(pos.X + fwd.X * 6, pos.Z + fwd.Z * 6, "hit something here")
							release(); closePiece(); saveTune()
							return false, "replan"
						end
					end
					hp0 = hp
					if hp <= 0 then log("the car is destroyed"); release(); closePiece(); saveTune(); return false, "car destroyed" end
				end
			end

			-- far from the route although on a road: the car took another way. Plan again from here (no blocking, no penalty).
			if bestD > 32 and not offRoad and spd > 4 then
				farSince = farSince or nowT
				if nowT - farSince > 2.5 and (opts.reroutes or 0) < 6 then
					log(("%.0f studs from the route: planning a new route from here"):format(bestD))
					release(); closePiece(); saveTune()
					return false, "reroute"
				end
			else
				farSince = nil
			end

			-- aim point on the route, further ahead when faster
			local look = math.clamp(P.lookBase + spd * P.lookGain, 12, 50)
			local aim = pointAhead(bestI, bestT, look)
			if offRoad and roadPt then aim = roadPt end
			local dirv = V3(aim.X - pos.X, 0, aim.Z - pos.Z)
			if dirv.Magnitude < 0.5 then dirv = fwd end
			local e = wrap(yawOf(dirv) - yaw)
			if pStat then pStat.maxErr = math.max(pStat.maxErr, math.abs(e)) end

			-- steering: proportional (less at speed) minus damping on the turn rate
			local kp = P.kp / (1 + spd / 40)
			local steerCmd = math.clamp(e * kp - yawRate * P.kd, -1, 1) * steerSign

			-- online tuning: every 2.5 s look at how the steering behaved. Zig-zagging -> softer gain, more damping.
			-- Lazy (far from the line on a straight bit) -> more gain. The values are kept in P, which is saved when the trip is scored.
			do
				local sg = steerCmd > 0.15 and 1 or (steerCmd < -0.15 and -1 or 0)
				if sg ~= 0 and lastSteerSign ~= 0 and sg ~= lastSteerSign then tuneFlips = tuneFlips + 1 end
				if sg ~= 0 then lastSteerSign = sg end
				tuneCte, tuneN = tuneCte + bestD, tuneN + 1
				if nowT - tuneT > 2.5 then
					local rate, mean = tuneFlips / (nowT - tuneT), tuneCte / math.max(tuneN, 1)
					local kp0, kd0 = P.kp, P.kd
					if rate > 1.6 and spd > 12 then
						P.kp = math.clamp(P.kp * 0.92, RANGE.kp[1], RANGE.kp[2]); P.kd = math.clamp(P.kd * 1.06, RANGE.kd[1], RANGE.kd[2])
					elseif mean > 6 and rate < 0.6 and math.abs(e) < 0.4 and spd > 15 then
						P.kp = math.clamp(P.kp * 1.07, RANGE.kp[1], RANGE.kp[2])
					end
					if P.kp ~= kp0 or P.kd ~= kd0 then
						log(("online tuning: %.1f steering flips/s, %.1f studs average off the line -> kp %.2f, kd %.2f"):format(rate, mean, P.kp, P.kd))
					end
					tuneT, tuneFlips, tuneCte, tuneN = nowT, 0, 0, 0
				end
			end

			-- speed: from the curvature of the route ahead (radius -> comfortable speed) and how far away each bend is (braking distance)
			local ahead1 = pointAhead(bestI, bestT, 8)
			local ahead2 = pointAhead(bestI, bestT, 60)
			local bend = math.abs(wrap(yawOf(V3(ahead2.X - ahead1.X, 0, ahead2.Z - ahead1.Z)) - yaw))
			local allowed = math.min(Drive.MaxSpeed, 80) * P.speedMul
			do
				local prevPt, prevH = pointAhead(bestI, bestT, 4), nil
				for k = 1, 8 do
					local d = 4 + k * 14
					local pt = pointAhead(bestI, bestT, d)
					local h = yawOf(V3(pt.X - prevPt.X, 0, pt.Z - prevPt.Z))
					if prevH then
						local kappa = math.abs(wrap(h - prevH)) / 14
						local vk = math.sqrt(P.latAcc / math.max(kappa, 0.0004))
						allowed = math.min(allowed, math.sqrt(vk * vk + 2 * 14 * math.max(d - 14, 0)))
					end
					prevPt, prevH = pt, h
				end
			end
			local corner = 1 - math.clamp(math.abs(e) / 1.5, 0, 0.5)
			local pm = pieceMul(curKey)
			local target = math.min(allowed * corner * pm, math.sqrt(2 * 10 * math.max(remainRoute - arrive, 0)) + 8)
			target = math.max(target, 14)
			if offRoad then target = math.min(target, 18) end
			if nowT < slowUntil then target = math.min(target, 22) end
			local thrCmd = cur.Throttle
			if spd < target - 3 then thrCmd = 1
			elseif spd > target + 8 then thrCmd = -1
			elseif spd > target + 2 then thrCmd = 0 end

			-- safety brake: a car-sized box ahead; anything solid and upright inside the stopping distance means brake NOW
			if nowT - lastScan > 0.1 and not reversing then
				lastScan = nowT
				local L = math.clamp(spd * 0.9 + 8, 10, 70)
				local origin = V3(pos.X, pos.Y - 0.5, pos.Z) + fwd * 3
				local okb, r = pcall(function() return workspace:Blockcast(CFrame.lookAt(origin, origin + fwd), V3(6, 3, 1), fwd * L, scanPar) end)
				danger = nil
				if okb and r and math.abs(r.Normal.Y) < 0.5 and not ignorable(r.Instance) then
					local m = r.Instance:FindFirstAncestorOfClass("Model")
					if not (m and m:FindFirstChildOfClass("Humanoid")) then danger = { dist = r.Distance, pos = r.Position, name = r.Instance:GetFullName() } end
				end
			end
			if danger and not reversing and danger.dist < spd * spd / 36 + spd * 0.3 + 5 then
				thrCmd = spd > 4 and -1 or 0
				if nowT - lastDangerLog > 2 then
					lastDangerLog = nowT
					log(("braking: %s is %.0f studs ahead, speed %.0f"):format(danger.name, danger.dist, spd))
				end
				if spd < 3 then
					dangerStopT = dangerStopT or nowT
					if nowT - dangerStopT > 1.3 then
						dangerStopT = nil
						if (flat(pos, startPos) > 30 or nowT - startT > 8) and (opts.replans or 0) < 5 then
							addBlock(danger.pos.X, danger.pos.Z, "solid " .. danger.name .. " in front of the car")
							release(); closePiece(); saveTune()
							return false, "replan"
						end
						reversing, revT = true, nowT -- near the start: back out of it
						reverses = reverses + 1
					end
				else
					dangerStopT = nil
				end
			else
				dangerStopT = nil
			end

			-- the aim point is behind us: do not circle, back up while steering the other way until we point roughly at it
			if not reversing and math.abs(e) > 2.1 and spd < 18 and nowT - revCool > 2 then
				reversing, revT = true, nowT
				reverses = reverses + 1
				if pStat then pStat.rev = true end
				log(("target is behind (error %.2f): backing up to turn around"):format(e))
			end
			if reversing then
				if math.abs(e) < 1.2 or nowT - revT > 3.5 then
					reversing, revCool = false, nowT
				else
					thrCmd = -1
					steerCmd = -steerCmd
				end
			end
			setCtl("Steering", steerCmd)
			setCtl("Throttle", thrCmd)

			do
				local st = Drive.State
				if st then
					st.idx = math.min(#wps, math.max(1, segIdx))
					st.spd, st.remain, st.err, st.fwd = spd, remainRoute, e, fwd
				end
			end

			-- stuck? back up a bit, then try again
			if spd < 1.5 and cur.Throttle > 0 and nowT - startT > 2 and not reversing then
				stuckSince = stuckSince or nowT
				if nowT - stuckSince > 1.6 then
					recoveries = recoveries + 1
					if pStat then pStat.stuck = true; pStat.stuckN = (pStat.stuckN or 0) + 1 end
					log(("stuck at (%.0f,%.0f,%.0f), backing up (%d)"):format(pos.X, pos.Y, pos.Z, recoveries))
					if recoveries > 8 then release(); closePiece(); saveTune(); return false, "stuck" end
					if (flat(pos, startPos) > 30 or nowT - startT > 8) and (opts.replans or 0) < 5 then
						addBlock(pos.X + fwd.X * 6, pos.Z + fwd.Z * 6, "the car got stuck here")
						log("stuck: planning another route around this spot")
						release(); closePiece(); saveTune()
						return false, "replan"
					end
					setCtl("Throttle", -1); setCtl("Steering", -steerCmd)
					task.wait(1.5)
					setCtl("Steering", 0)
					stuckSince = nil
				end
			else
				stuckSince = nil
			end
			if nowT - lastLog > 3 then
				lastLog = nowT
				log(("drive: %.0f studs left, speed %.0f (target %.0f, piece x%.2f), segment %d/%d, aim error %.2f, bend %.2f, off route %.1f, %s"):format(remainRoute, spd, target, pm, segIdx, #path - 1, e, bend, bestD, offRoad and "OFF ROAD" or "on road"))
			end
		end
		release()
		saveTune()
		return false, Drive.Cancel and "cancelled" or "took too long"
	end)
	Drive.Busy = false
	Drive.State = nil
	if not ok then log("drive error: " .. tostring(res)); return false, tostring(res) end
	return res, why or res
end

function Drive.Stop() Drive.Cancel = true end
function Drive.GetGraph() return graph end
-- writes the road map to ScrdsxScript/roadgraph.json so tools/train_driver.py can train the driving offline
function Drive.ExportMap()
	if not graph then local g = build(); graph = g end
	if not graph then return false, "road map not found" end
	local ids, list = {}, {}
	for _, m in pairs(graph.mods) do list[#list + 1] = m; ids[m] = #list end
	local out = { pieces = {} }
	for i, m in ipairs(list) do
		local e = {}
		for o, ed in pairs(m.edges) do e[#e + 1] = { to = ids[o], vx = math.floor(ed.via.X * 10) / 10, vz = math.floor(ed.via.Z * 10) / 10 } end
		out.pieces[i] = { k = math.floor(m.pos.X / 10) .. "," .. math.floor(m.pos.Z / 10), x = math.floor(m.pos.X * 10) / 10, y = math.floor(m.pos.Y * 10) / 10, z = math.floor(m.pos.Z * 10) / 10, e = e }
	end
	local ok = pcall(function()
		pcall(function() if makefolder then makefolder("ScrdsxScript") end end)
		writefile("ScrdsxScript/roadgraph.json", game:GetService("HttpService"):JSONEncode(out))
	end)
	return ok, #list .. " road pieces"
end
function Drive.Prepare() if not graph then local g = build(); graph = g end return graph end

return Drive

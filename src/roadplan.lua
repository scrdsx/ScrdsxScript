-- Route planner on the REAL road surface. src/roaddata.lua holds the footprint of every Road part of the map (taken with tools/map_export.lua);
-- here they are rasterised into 4-stud cells and routes are planned with A*, preferring the middle of the road and never touching a cell that
-- has something solid on it. Pure Lua (no Roblox API) so tools/roadnet.py can test the very same logic offline.
--   Plan.Route(ax, az, bx, bz, opts) -> list of { x, y, z } about every 10 studs, or nil, reason
--   opts: minEdge (default 2 = keep 8 studs from the road edge), head = { x, z } direction the car faces (the first stretch behind the car costs extra), blocked = function(x, z) -> bool,
--         snapRadius (studs, default 220), ay / by = heights (to pick the right level on bridges / tunnels)
local Data = __import("roaddata")

local Plan = { Yield = nil }
local CELL = 4
local WANT = 6      -- cells (24 studs) from the road edge are free of penalty; closer to the edge costs more
local floor, sqrt, abs, max, min = math.floor, math.sqrt, math.abs, math.max, math.min

local cells, edge, levels, ringDir, blockedSet
local built = false

local function K(i, j, l) return ((l + 16) * 1024 + (i + 640)) * 2048 + (j + 640) end
local function unK(k)
	local j = k % 2048 - 640
	local r = (k - (j + 640)) / 2048
	local i = r % 1024 - 640
	local l = floor(r / 1024) - 16
	return i, j, l
end
local function find(i, j, l)
	local k = K(i, j, l)
	if cells[k] then return k, l end
	k = K(i, j, l - 1)
	if cells[k] then return k, l - 1 end
	k = K(i, j, l + 1)
	if cells[k] then return k, l + 1 end
	return nil
end
-- planning works in slices of ~4 ms: the game keeps its frame rate while a long route is planned (it used to freeze for whole frames at a time)
local lastYield = 0
local function yield(n)
	if Plan.Yield and n % 128 == 0 then
		local t = os.clock()
		if t - lastYield > 0.004 then Plan.Yield(); lastYield = os.clock() end
	end
end

local function build()
	if built then return end
	cells, edge, levels = {}, {}, {}
	local q = Data.quads
	local n = 0
	for p = 1, #q, 9 do
		local x1, z1, x2, z2, x3, z3, x4, z4, y = q[p], q[p + 1], q[p + 2], q[p + 3], q[p + 4], q[p + 5], q[p + 6], q[p + 7], q[p + 8]
		local minx, maxx = min(x1, x2, x3, x4), max(x1, x2, x3, x4)
		local minz, maxz = min(z1, z2, z3, z4), max(z1, z2, z3, z4)
		local lvl = floor(y / 6 + 0.5)
		levels[lvl] = true
		for i = floor(minx / CELL), floor(maxx / CELL) do
			for j = floor(minz / CELL), floor(maxz / CELL) do
				local cx, cz = i * CELL + CELL / 2, j * CELL + CELL / 2
				-- inside the quad? (all cross products have the same sign)
				local s1 = (x2 - x1) * (cz - z1) - (z2 - z1) * (cx - x1)
				local s2 = (x3 - x2) * (cz - z2) - (z3 - z2) * (cx - x2)
				local s3 = (x4 - x3) * (cz - z3) - (z4 - z3) * (cx - x3)
				local s4 = (x1 - x4) * (cz - z4) - (z1 - z4) * (cx - x4)
				if (s1 >= 0 and s2 >= 0 and s3 >= 0 and s4 >= 0) or (s1 <= 0 and s2 <= 0 and s3 <= 0 and s4 <= 0) then
					cells[K(i, j, lvl)] = y
				end
				n = n + 1
				yield(n)
			end
		end
	end
	blockedSet = {}
	for _, k in ipairs(Data.blocked) do blockedSet[k] = true; cells[k] = nil end
	-- distance to the road edge (cells), multi-source BFS from the boundary
	local queue, head = {}, 1
	for k in pairs(cells) do
		local i, j, l = unK(k)
		if not find(i + 1, j, l) or not find(i - 1, j, l) or not find(i, j + 1, l) or not find(i, j - 1, l) then
			edge[k] = 0
			queue[#queue + 1] = k
		end
		n = n + 1
		yield(n)
	end
	while head <= #queue do
		local k = queue[head]; head = head + 1
		local i, j, l = unK(k)
		local d = edge[k] + 1
		for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local nk = find(i + o[1], j + o[2], l)
			if nk and edge[nk] == nil then
				edge[nk] = d
				queue[#queue + 1] = nk
			end
		end
		n = n + 1
		yield(n)
	end
	-- roundabout rings: each cell in the ring remembers the direction of travel (counter-clockwise seen from above, right-hand traffic);
	-- going the other way costs extra, so routes circle the island the way real traffic does
	ringDir = {}
	local rg = Data.rings
	if rg then
		for p = 1, #rg, 4 do
			local cx, cz, r0, r1 = rg[p], rg[p + 1], rg[p + 2], rg[p + 3]
			for i = floor((cx - r1) / CELL), floor((cx + r1) / CELL) do
				for j = floor((cz - r1) / CELL), floor((cz + r1) / CELL) do
					local x, z = i * CELL + CELL / 2, j * CELL + CELL / 2
					local rx, rz = x - cx, z - cz
					local d = sqrt(rx * rx + rz * rz)
					if d > r0 and d < r1 then
						for lvl in pairs(levels) do
							local k = K(i, j, lvl)
							if cells[k] then ringDir[k] = { rz / d, -rx / d } end
						end
					end
				end
			end
		end
	end
	built = true
end

-- nearest usable road cell (>= 1 cell from the edge) around a point, searching outwards in rings
local function snap(x, z, y, radius)
	local i0, j0 = floor(x / CELL), floor(z / CELL)
	local maxr = floor(radius / CELL)
	local bestk, bestd
	for r = 0, maxr do
		for di = -r, r do
			for dj = -r, r do
				if max(abs(di), abs(dj)) == r then
					for lvl in pairs(levels) do
						local k = K(i0 + di, j0 + dj, lvl)
						if cells[k] and (edge[k] or 0) >= 1 then
							-- the level (height) matters a lot: a dealer on the street must not snap to the road in the garage below it
							local d = di * di + dj * dj + (y and ((cells[k] - y) / CELL) ^ 2 * 2.0 or 0)
							if not bestd or d < bestd then bestk, bestd = k, d end
						end
					end
				end
			end
		end
		if bestk and r * r >= bestd then break end -- nothing in a bigger ring can be closer
	end
	return bestk
end

-- Live roads: road parts that exist in the game right now but are not in the baked map data (new modules, places the map export missed).
-- q = flat list, 9 numbers per quad (same as Data.quads). New cells join the grid and the edge distances around them are recomputed.
function Plan.Extend(q)
	build()
	local newKeys = {}
	for p = 1, #q, 9 do
		local x1, z1, x2, z2, x3, z3, x4, z4, y = q[p], q[p + 1], q[p + 2], q[p + 3], q[p + 4], q[p + 5], q[p + 6], q[p + 7], q[p + 8]
		local lvl = floor(y / 6 + 0.5)
		levels[lvl] = true
		for i = floor(min(x1, x2, x3, x4) / CELL), floor(max(x1, x2, x3, x4) / CELL) do
			for j = floor(min(z1, z2, z3, z4) / CELL), floor(max(z1, z2, z3, z4) / CELL) do
				local cx, cz = i * CELL + CELL / 2, j * CELL + CELL / 2
				local s1 = (x2 - x1) * (cz - z1) - (z2 - z1) * (cx - x1)
				local s2 = (x3 - x2) * (cz - z2) - (z3 - z2) * (cx - x2)
				local s3 = (x4 - x3) * (cz - z3) - (z4 - z3) * (cx - x3)
				local s4 = (x1 - x4) * (cz - z4) - (z1 - z4) * (cx - x4)
				if (s1 >= 0 and s2 >= 0 and s3 >= 0 and s4 >= 0) or (s1 <= 0 and s2 <= 0 and s3 <= 0 and s4 <= 0) then
					local k = K(i, j, lvl)
					if not cells[k] and not blockedSet[k] then cells[k] = y; newKeys[#newKeys + 1] = k end
				end
			end
		end
	end
	if #newKeys == 0 then return 0 end
	-- recompute the edge distance in a 8-cell ring round the new cells (old cells next to them may no longer be at the edge)
	local region, list, n = {}, {}, 0
	for _, k in ipairs(newKeys) do
		local i, j, l = unK(k)
		for di = -8, 8 do
			for dj = -8, 8 do
				local nk = find(i + di, j + dj, l)
				if nk and not region[nk] then region[nk] = true; list[#list + 1] = nk end
			end
		end
		n = n + 1
		yield(n * 40)
	end
	local INF = 1e9
	for _, k in ipairs(list) do edge[k] = INF end
	for _, k in ipairs(list) do
		local i, j, l = unK(k)
		if not find(i + 1, j, l) or not find(i - 1, j, l) or not find(i, j + 1, l) or not find(i, j - 1, l) then edge[k] = 0 end
	end
	local changed, passes = true, 0
	while changed and passes < 40 do
		changed, passes = false, passes + 1
		for idx, k in ipairs(list) do
			local i, j, l = unK(k)
			local best = edge[k]
			for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local nk = find(i + o[1], j + o[2], l)
				if nk then
					local v = (edge[nk] or INF) + 1
					if v < best then best = v end
				end
			end
			if best < edge[k] then edge[k] = best; changed = true end
			yield(idx + passes * 7)
		end
	end
	return #newKeys
end

function Plan.Ready() return built end
function Plan.Build() build() end

function Plan.Route(ax, az, bx, bz, opts)
	opts = opts or {}
	build()
	local radius = opts.snapRadius or 220
	local s = snap(ax, az, opts.ay, radius)
	local g = snap(bx, bz, opts.by, radius)
	if not s then return nil, "no road near the start" end
	if not g then return nil, "no road near the destination" end
	local sx_, sz_ = (function() local i, j = unK(s); return i * CELL + CELL / 2, j * CELL + CELL / 2 end)()
	local gi, gj = unK(g)
	local gx, gz = gi * CELL + CELL / 2, gj * CELL + CELL / 2
	local head, blocked = opts.head, opts.blocked
	local minEdge = opts.minEdge or 2 -- cells (4 studs each) the path keeps away from the road edge (poles, lamps and signs stand there)

	-- binary heap of { key, f }
	local heap = {}
	local function push(k, f)
		heap[#heap + 1] = { k, f }
		local i = #heap
		while i > 1 do
			local p = floor(i / 2)
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

	local gs, parent, closed = { [s] = 0 }, {}, {}
	push(s, 0)
	local expanded = 0
	local found = (s == g)
	local nearK, nearD -- the cell closest to the destination that the search reached (used when the destination cannot be reached)
	while #heap > 0 and not found do
		local top = pop()
		local k = top[1]
		if not closed[k] then
			closed[k] = true
			if k == g then found = true; break end
			do
				local ki, kj = unK(k)
				local dxx, dzz = ki * CELL + CELL / 2 - gx, kj * CELL + CELL / 2 - gz
				local dd = dxx * dxx + dzz * dzz
				if not nearD or dd < nearD then nearK, nearD = k, dd end
			end
			expanded = expanded + 1
			yield(expanded)
			if expanded > 150000 then break end -- searched the whole network: take the closest point reached
			local i, j, l = unK(k)
			local gk = gs[k]
			for di = -1, 1 do
				for dj = -1, 1 do
					if di ~= 0 or dj ~= 0 then
						local nk, nl = find(i + di, j + dj, l)
						if nk and not closed[nk] then
							local e = edge[nk] or 0
							if e >= minEdge or nk == g or (e >= 1 and ringDir and ringDir[nk]) then
								local ok = true
								if di ~= 0 and dj ~= 0 then
									ok = find(i + di, j, l) ~= nil and find(i, j + dj, l) ~= nil
								end
								local cx, cz = (i + di) * CELL + CELL / 2, (j + dj) * CELL + CELL / 2
								if ok and blocked and blocked(cx, cz) then ok = false end
								if ok then
									local step = (di ~= 0 and dj ~= 0) and 1.4142 or 1
									local pen = 1 + 0.35 * max(0, WANT - e)
									local rd = ringDir and ringDir[nk]
									if rd then pen = 1 end -- the roundabout lane is narrow by nature: no edge penalty, so it beats detours through side streets
									if rd and (rd[1] * di + rd[2] * dj) < -0.3 then pen = pen * 1.8 end -- against the roundabout's direction
									-- the first stretch behind the car costs extra: leave in the direction the car faces if the road allows it
									if head then
										local ddx, ddz = cx - sx_, cz - sz_
										if ddx * ddx + ddz * ddz < 3600 and ddx * head.x + ddz * head.z < 0 then pen = pen * 2.5 end
									end
									local ng = gk + step * pen
									if ng < (gs[nk] or math.huge) then
										gs[nk], parent[nk] = ng, k
										local hx, hz = cx - gx, cz - gz
										push(nk, ng + 1.5 * sqrt(hx * hx + hz * hz) / CELL) -- weighted A*: far fewer cells to look at, still a good route
									end
								end
							end
						end
					end
				end
			end
		end
	end
	local partial = false
	if not found then
		-- the destination is cut off (barrier, enclosed area): drive to the closest point the road network allows instead
		if not nearK then return nil, "no road connection" end
		g, partial = nearK, true
	end

	local path, cur = {}, g
	while cur do
		local i, j = unK(cur)
		table.insert(path, 1, { i * CELL + CELL / 2, j * CELL + CELL / 2, cells[cur], (select(3, unK(cur))) })
		cur = parent[cur]
	end

	-- string pulling: drop cells while the straight line stays at least 2 cells from the road edge
	-- string pulling must keep further from the road edge than the path itself, else it cuts corners (the car then turns in early)
	local pullEdge = math.min(3, minEdge + 1)
	local function lineOk(a, b)
		local len = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local steps = max(1, floor(len / (CELL * 0.5)))
		for t = 1, steps - 1 do
			local x, z = a[1] + (b[1] - a[1]) * t / steps, a[2] + (b[2] - a[2]) * t / steps
			local k = find(floor(x / CELL), floor(z / CELL), a[4])
			if not k or (edge[k] or 0) < pullEdge then return false end
			if blocked and blocked(x, z) then return false end
		end
		return true
	end
	-- a shortcut may only replace the lane path when it stays within ~5 studs of it: otherwise the route cuts across the road (it used to drift
	-- over to the road edge on long chords and to turn in far too early at corners)
	local function corridorOk(i, j)
		local a, b = path[i], path[j]
		local abx, abz = b[1] - a[1], b[2] - a[2]
		local l2 = abx * abx + abz * abz
		if l2 < 1 then return true end
		for m = i + 1, j - 1 do
			local px, pz = path[m][1] - a[1], path[m][2] - a[2]
			local t = max(0, min(1, (px * abx + pz * abz) / l2))
			local dx, dz = px - abx * t, pz - abz * t
			if dx * dx + dz * dz > 30 then return false end
		end
		return true
	end
	local keep = { path[1] }
	local i = 1
	while i < #path do
		local j = min(#path, i + 30)
		while j > i + 1 and not (corridorOk(i, j) and lineOk(path[i], path[j])) do j = j - 1 end
		keep[#keep + 1] = path[j]
		i = j
	end
	-- resample every ~10 studs
	local out = { { keep[1][1], keep[1][3], keep[1][2] } }
	for n = 1, #keep - 1 do
		local a, b = keep[n], keep[n + 1]
		local len = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local steps = max(1, floor(len / 10 + 0.5))
		for t = 1, steps do
			local f = t / steps
			out[#out + 1] = { a[1] + (b[1] - a[1]) * f, a[3] + (b[3] - a[3]) * f, a[2] + (b[2] - a[2]) * f }
		end
	end
	-- keep to the right-hand side of wide roads (right-hand traffic): shift the line sideways by up to 8 studs, more on wider roads, smoothly,
	-- never in roundabouts and never into something blocked / off the road
	if opts.lane ~= false and #out > 2 then
		local lv, sh = {}, {}
		for n, pt in ipairs(out) do
			lv[n] = floor(pt[2] / 6 + 0.5)
			local k = find(floor(pt[1] / CELL), floor(pt[3] / CELL), lv[n])
			if k and not (ringDir and ringDir[k]) then sh[n] = max(0, min(8, (edge[k] or 0) * CELL - 7)) else sh[n] = 0 end
		end
		for _ = 1, 2 do
			local nxt = {}
			for n = 1, #out do
				nxt[n] = (n > 1 and n < #out) and (sh[n - 1] + sh[n] * 2 + sh[n + 1]) / 4 or 0
			end
			sh = nxt
		end
		local moved = {}
		for n = 2, #out - 1 do
			local a, b = out[n - 1], out[n + 1]
			local dx, dz = b[1] - a[1], b[3] - a[3]
			local l = sqrt(dx * dx + dz * dz)
			local x, z = out[n][1], out[n][3]
			if l > 0.5 and sh[n] > 0.3 then
				local rx, rz = -dz / l, dx / l
				local s2 = sh[n]
				for _ = 1, 4 do
					local nx, nz = x + rx * s2, z + rz * s2
					local k = find(floor(nx / CELL), floor(nz / CELL), lv[n])
					if k and (edge[k] or 0) >= 1 and not (blocked and blocked(nx, nz)) then x, z = nx, nz; break end
					s2 = s2 / 2
				end
			end
			moved[n] = { x, z }
		end
		for n = 2, #out - 1 do out[n][1], out[n][3] = moved[n][1], moved[n][2] end
	end
	-- each point as { x, y, z }
	local res = {}
	for n, p in ipairs(out) do res[n] = { x = p[1], y = p[2], z = p[3] } end
	return res, partial and "partial" or "ok"
end

return Plan

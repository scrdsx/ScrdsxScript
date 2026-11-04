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

local cells, edge, levels
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
local function yield(n)
	if Plan.Yield and n % 4000 == 0 then Plan.Yield() end
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
	for _, k in ipairs(Data.blocked) do cells[k] = nil end
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
							local d = di * di + dj * dj + (y and ((cells[k] - y) / CELL) ^ 2 * 0.2 or 0)
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
	while #heap > 0 and not found do
		local top = pop()
		local k = top[1]
		if not closed[k] then
			closed[k] = true
			if k == g then found = true; break end
			expanded = expanded + 1
			yield(expanded)
			if expanded > 120000 then return nil, "search too large" end
			local i, j, l = unK(k)
			local gk = gs[k]
			for di = -1, 1 do
				for dj = -1, 1 do
					if di ~= 0 or dj ~= 0 then
						local nk, nl = find(i + di, j + dj, l)
						if nk and not closed[nk] then
							local e = edge[nk] or 0
							if e >= minEdge or nk == g then
								local ok = true
								if di ~= 0 and dj ~= 0 then
									ok = find(i + di, j, l) ~= nil and find(i, j + dj, l) ~= nil
								end
								local cx, cz = (i + di) * CELL + CELL / 2, (j + dj) * CELL + CELL / 2
								if ok and blocked and blocked(cx, cz) then ok = false end
								if ok then
									local step = (di ~= 0 and dj ~= 0) and 1.4142 or 1
									local pen = 1 + 0.35 * max(0, WANT - e)
									-- the first stretch behind the car costs extra: leave in the direction the car faces if the road allows it
									if head then
										local ddx, ddz = cx - sx_, cz - sz_
										if ddx * ddx + ddz * ddz < 3600 and ddx * head.x + ddz * head.z < 0 then pen = pen * 2.5 end
									end
									local ng = gk + step * pen
									if ng < (gs[nk] or math.huge) then
										gs[nk], parent[nk] = ng, k
										local hx, hz = cx - gx, cz - gz
										push(nk, ng + sqrt(hx * hx + hz * hz) / CELL)
									end
								end
							end
						end
					end
				end
			end
		end
	end
	if not found then return nil, "no road connection" end

	local path, cur = {}, g
	while cur do
		local i, j = unK(cur)
		table.insert(path, 1, { i * CELL + CELL / 2, j * CELL + CELL / 2, cells[cur], (select(3, unK(cur))) })
		cur = parent[cur]
	end

	-- string pulling: drop cells while the straight line stays at least 2 cells from the road edge
	local function lineOk(a, b)
		local len = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local steps = max(1, floor(len / (CELL * 0.5)))
		for t = 1, steps - 1 do
			local x, z = a[1] + (b[1] - a[1]) * t / steps, a[2] + (b[2] - a[2]) * t / steps
			local k = find(floor(x / CELL), floor(z / CELL), a[4])
			if not k or (edge[k] or 0) < 2 then return false end
			if blocked and blocked(x, z) then return false end
		end
		return true
	end
	local keep = { path[1] }
	local i = 1
	while i < #path do
		local j = #path
		while j > i + 1 and not lineOk(path[i], path[j]) do j = j - 1 end
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
	-- each point as { x, y, z }
	local res = {}
	for n, p in ipairs(out) do res[n] = { x = p[1], y = p[2], z = p[3] } end
	return res, "ok"
end

return Plan

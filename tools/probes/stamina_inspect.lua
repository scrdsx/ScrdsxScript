-- Stamina inspector. Run it on foot, then SPRINT until the stamina bar drops (it watches for WATCH seconds).
-- It requires the game's characterStaminaController module, dumps its table / upvalues / constants, finds the
-- numeric fields that look like stamina and logs how they change while you sprint. Report goes to the clipboard.
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local WATCH = tonumber((getgenv and getgenv().ProbeSeconds) or 25)
local out = {}
local function log(s) out[#out + 1] = s end
print("[stamina] started")
local function short(v)
	local t = typeof(v)
	if t == "Instance" then return v:GetFullName() end
	if t == "table" then return "table" end
	if t == "function" then return "function" end
	local s = tostring(v)
	return #s > 70 and s:sub(1, 70) .. "..." or s
end
local getUp = getupvalues or (debug and debug.getupvalues)
local getConst = getconstants or (debug and debug.getconstants)
log(("api: getupvalues=%s getconstants=%s getgc=%s require=%s"):format(tostring(getUp ~= nil), tostring(getConst ~= nil), tostring(getgc ~= nil), tostring(require ~= nil)))

-- find the module
local inst
for _, d in ipairs(lp:GetDescendants()) do
	if d:IsA("ModuleScript") and d.Name == "characterStaminaController" then inst = d break end
end
if not inst then log("characterStaminaController NOT FOUND") end

local candidates = {} -- { label, tbl, key }
local seen = {}
local KEYS = { "stamina", "energy", "sprint", "stam", "fatigue", "tired", "run", "maxstamina", "regen", "drain", "cooldown", "exhaust" }
local function interesting(n)
	n = tostring(n):lower()
	for _, k in ipairs(KEYS) do if n:find(k, 1, true) then return true end end
	return false
end

local function dumpTable(t, depth, prefix)
	if seen[t] or depth > 3 then return end
	seen[t] = true
	local n = 0
	for k, v in pairs(t) do
		n += 1
		if n > 60 then log(prefix .. "  ... more") break end
		local tv = typeof(v)
		log(("%s%s = %s (%s)"):format(prefix, short(k), short(v), tv))
		if tv == "number" and (interesting(k) or true) then
			candidates[#candidates + 1] = { prefix .. short(k), t, k }
		elseif tv == "table" then
			dumpTable(v, depth + 1, prefix .. short(k) .. ".")
		elseif tv == "function" and getUp then
			local ok, ups = pcall(getUp, v)
			if ok and type(ups) == "table" then
				for i, u in pairs(ups) do
					log(("%s  up[%s] = %s (%s)"):format(prefix .. short(k), tostring(i), short(u), typeof(u)))
					if typeof(u) == "table" then dumpTable(u, depth + 1, prefix .. short(k) .. ".up" .. tostring(i) .. ".") end
				end
			end
			if getConst then
				local okc, cs = pcall(getConst, v)
				if okc and type(cs) == "table" then
					local parts = {}
					for i, c in pairs(cs) do if type(c) == "string" or type(c) == "number" then parts[#parts + 1] = tostring(c) end end
					log(prefix .. short(k) .. "  consts: " .. table.concat(parts, ", "):sub(1, 400))
				end
			end
		end
	end
end

if inst then
	print("[stamina] requiring module...")
	local done, ok, mod = false, false, nil
	task.spawn(function() ok, mod = pcall(require, inst); done = true end)
	local tw = os.clock()
	while not done and os.clock() - tw < 6 do task.wait(0.1) end
	if not done then log("require TIMED OUT after 6s (module yields or is blocked)") end
	log("require: " .. tostring(ok) .. " -> " .. typeof(mod))
	print("[stamina] require done: " .. tostring(ok))
	if ok and type(mod) == "table" then
		local okd, err = pcall(dumpTable, mod, 0, "mod.")
		if not okd then log("dump error: " .. tostring(err)) end
	elseif ok and type(mod) == "function" then
		log("module returned a function")
		dumpTable({ fn = mod }, 0, "mod.")
	end
end

-- heap scan: small tables with a stamina-looking numeric field (the live state is usually one of these)
if getgc then
	print("[stamina] scanning heap...")
	local found, iter = 0, 0
	local okgc, heap = pcall(getgc, true)
	for _, t in ipairs(okgc and heap or {}) do
		iter = iter + 1
		if iter % 3000 == 0 then task.wait() end
		if type(t) == "table" and found < 25 and not seen[t] then
			local hit
			local count = 0
			for k, v in pairs(t) do
				count += 1
				if count > 40 then hit = nil break end
				if type(k) == "string" and type(v) == "number" and interesting(k) then hit = k end
			end
			if hit then
				found += 1
				seen[t] = true
				log("gc table with '" .. hit .. "':")
				for k, v in pairs(t) do
					log(("    %s = %s (%s)"):format(short(k), short(v), typeof(v)))
					if type(v) == "number" then candidates[#candidates + 1] = { "gc#" .. found .. "." .. short(k), t, k } end
				end
			end
		end
	end
end

-- live sampling while you sprint
log(("-- LIVE: sampling %d numeric fields for %ds. SPRINT now --"):format(#candidates, WATCH))
print(("[stamina] SPRINT NOW for %ds (%d fields tracked)"):format(WATCH, #candidates))
local last, changes, t0 = {}, {}, os.clock()
for i, c in ipairs(candidates) do last[i] = c[2][c[3]] end
while os.clock() - t0 < WATCH do
	for i, c in ipairs(candidates) do
		local v = c[2][c[3]]
		if v ~= last[i] then
			changes[i] = (changes[i] or 0) + 1
			if changes[i] <= 8 then log(("[%5.1fs] %s: %s -> %s"):format(os.clock() - t0, c[1], short(last[i]), short(v))) end
			last[i] = v
		end
	end
	task.wait(0.1)
end
log("-- fields that changed --")
for i, n in pairs(changes) do log(("  %s changed %d times"):format(candidates[i][1], n)) end

local report = table.concat(out, "\n")
if setclipboard then setclipboard(report) end
print(report)
print(("[stamina] done: %d chars%s"):format(#report, setclipboard and ", copied to clipboard" or ""))

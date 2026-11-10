-- Travel: the teleport system. Every move is CHECKED (the server may put you back) and falls back to the next way:
--   1. instant      : one jump to the target.
--   2. hops         : many short jumps in a row (the server tolerates short steps better); the hop length shrinks when a hop is refused.
--   3. walk         : the farm's door-aware path walking (real walking: always accepted).
--   4. car          : your car drives you (the autopilot) - only when "Allow the car" is on.
-- Travel.To(pos, opts) runs in the background, Travel.ToSync(pos, opts) waits and returns ok, method.
-- opts: name, waitAlive (wait for a respawn first, default true), method (override), allowCar, face (Vector3 to look at)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer
local V3 = Vector3.new
local Farm = __import("farm")

local FILE = "ScrdsxScript/travel.json"
local Travel = {
	Method = "auto",       -- "auto" | "instant" | "hops" | "walk" | "car"
	AllowCar = false,
	Ghost = true,          -- non-solid while hopping, so nothing snags you
	HopLen = 120,
	HopDelay = 0.11,
	History = {},          -- positions you left (for Back)
	Busy = false, Cancel = false, Info = "ready", LastMethod = nil,
	Notify = nil, Changed = nil, Log = nil,
	instantFails = 0, instantSkipUntil = 0,
}

local function log(m) if Travel.Log then Travel.Log(m) end end
local function say(s)
	Travel.Info = s
	log(s)
	if Travel.Changed then task.defer(Travel.Changed) end
end

-- remembered between sessions: the longest hop that worked, and whether instant jumps ever worked
local function load()
	pcall(function()
		if isfile and readfile and isfile(FILE) then
			local d = HttpService:JSONDecode(readfile(FILE))
			if type(d) == "table" then
				if type(d.hop) == "number" then Travel.HopLen = math.clamp(d.hop, 20, 400) end
				if type(d.instantFails) == "number" then Travel.instantFails = d.instantFails end
			end
		end
	end)
end
local function save()
	pcall(function()
		if writefile then
			pcall(function() if makefolder then makefolder("ScrdsxScript") end end)
			writefile(FILE, HttpService:JSONEncode({ hop = Travel.HopLen, instantFails = Travel.instantFails }))
		end
	end)
end
load()

local function parts()
	local c = lp.Character
	return c, c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end

local function alive()
	local _, h, r = parts()
	return h ~= nil and r ~= nil and h.Health > 0
end

-- a standing spot at/near pos: the floor under it, or the ground below if pos is in the air
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Exclude
local function standAt(pos)
	local car = workspace:FindFirstChild("Vehicles") and workspace.Vehicles:FindFirstChild(lp.Name)
	rp.FilterDescendantsInstances = { lp.Character, car }
	local r = workspace:Raycast(pos + V3(0, 6, 0), V3(0, -40, 0), rp)
	if r and r.Normal.Y > 0.5 then return V3(pos.X, r.Position.Y + 3.2, pos.Z), true end
	r = workspace:Raycast(V3(pos.X, pos.Y + 160, pos.Z), V3(0, -420, 0), rp)
	if r then return V3(pos.X, r.Position.Y + 3.2, pos.Z), true end
	return pos + V3(0, 3, 0), false -- nothing loaded there yet
end

-- ask the game to load the map around the target (streaming), wait a little
local function stream(pos)
	local done = false
	task.spawn(function()
		pcall(function() lp:RequestStreamAroundAsync(pos, 3) end)
		done = true
	end)
	local t = os.clock()
	while not done and os.clock() - t < 3 and not Travel.Cancel do task.wait(0.1) end
end

local function setGhost(on, store)
	local c = lp.Character
	if not c then return end
	if on then
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide then store[#store + 1] = d; d.CanCollide = false end
		end
	else
		for _, d in ipairs(store) do pcall(function() d.CanCollide = true end) end
		table.clear(store)
	end
end

local function near(pos, target, r) return (pos - target).Magnitude <= r end

-- 1) instant: one jump, then check twice that the server did not put us back
local function tryInstant(target)
	local _, hum, hrp = parts()
	if not (hum and hrp) then return false end
	if hum.SeatPart then hum.Sit = false; task.wait(0.35) end
	hrp.CFrame = CFrame.new(target) * hrp.CFrame.Rotation
	hrp.AssemblyLinearVelocity = V3()
	task.wait(0.5)
	if not near(hrp.Position, target, 16) then return false, "put back to " .. math.floor((hrp.Position - target).Magnitude) .. " studs away" end
	task.wait(0.7)
	if not near(hrp.Position, target, 16) then return false, "put back after a moment" end
	return true
end

-- 2) hops: short jumps in a row; a refused hop halves the hop length and the trip goes on from where we are
local function tryHops(target)
	local _, hum, hrp = parts()
	if not (hum and hrp) then return false end
	if hum.SeatPart then hum.Sit = false; task.wait(0.35) end
	local store = {}
	if Travel.Ghost then setGhost(true, store) end
	local hop = Travel.HopLen
	local result, why = false, "no luck"
	for round = 1, 4 do
		local start = hrp.Position
		local dist = (target - start).Magnitude
		if dist < 8 then result = true; break end
		local steps = math.max(1, math.ceil(dist / hop))
		local refused = false
		for i = 1, steps do
			if Travel.Cancel then why = "cancelled"; break end
			local p = start:Lerp(target, i / steps)
			hrp.CFrame = CFrame.new(p) * hrp.CFrame.Rotation
			hrp.AssemblyLinearVelocity = V3()
			task.wait(Travel.HopDelay)
			if not near(hrp.Position, p, 22) then
				refused = true
				why = ("hop %d/%d refused at hop length %d"):format(i, steps, hop)
				break
			end
		end
		if Travel.Cancel then break end
		if not refused then
			task.wait(0.6)
			if near(hrp.Position, target, 18) then result = true; Travel.HopLen = hop; save(); break end
			why = "put back after the last hop"
		end
		hop = math.max(20, math.floor(hop / 2))
		if hop <= 20 and refused and round >= 3 then break end
	end
	setGhost(false, store)
	return result, why
end

-- 4) the whole move
function Travel.ToSync(pos, opts)
	opts = opts or {}
	if Travel.Busy then return false, "busy" end
	Travel.Busy, Travel.Cancel = true, false
	local name = opts.name or "the target"
	local okRun, ok, how = pcall(function()
		if opts.waitAlive ~= false then
			say("waiting for a living character")
			local t0 = os.clock()
			while not alive() and os.clock() - t0 < 40 and not Travel.Cancel do task.wait(0.4) end
			task.wait(0.5)
		end
		if not alive() then return false, "not alive" end
		local _, hum, hrp = parts()
		if not opts.noHistory then
			table.insert(Travel.History, hrp.Position)
			if #Travel.History > 12 then table.remove(Travel.History, 1) end
		end

		say("loading the area around " .. name)
		stream(pos)
		local target, grounded = standAt(pos)
		local method = opts.method or Travel.Method
		local order
		if method == "auto" then
			order = { "instant", "hops", "walk" }
			if opts.allowCar or Travel.AllowCar then order[#order + 1] = "car" end
			if os.clock() < Travel.instantSkipUntil then table.remove(order, 1) end -- instant was refused twice in a row: skip it for a while
		else
			order = { method }
		end
		for _, m in ipairs(order) do
			if Travel.Cancel then return false, "cancelled" end
			_, hum, hrp = parts()
			if not (hum and hrp and hum.Health > 0) then return false, "died on the way" end
			if (hrp.Position - target).Magnitude < 10 then return true, m end
			say(("%s: %s"):format(name, m))
			local ok2, why2 = false, nil
			if m == "instant" then
				ok2, why2 = tryInstant(target)
				if ok2 then Travel.instantFails = 0; save()
				else
					Travel.instantFails = Travel.instantFails + 1
					if Travel.instantFails >= 2 then Travel.instantSkipUntil = os.clock() + 600 end
					save()
				end
			elseif m == "hops" then
				ok2, why2 = tryHops(target)
			elseif m == "walk" then
				ok2 = Farm.WalkTo and Farm.WalkTo(target, nil, 4) or false
				if not ok2 then why2 = "no path / did not arrive" end
			elseif m == "car" then
				ok2 = Farm.GoNear and Farm.GoNear(target, name) or false
				if not ok2 then why2 = "the car could not get there" end
			end
			log(("%s -> %s: %s%s"):format(name, m, ok2 and "OK" or "failed", why2 and (" (" .. tostring(why2) .. ")") or ""))
			if ok2 then
				-- if the spot was unloaded when we picked it, put us on the real floor now
				if not grounded then
					local _, _, h2 = parts()
					if h2 then
						local t2, g2 = standAt(h2.Position)
						if g2 then h2.CFrame = CFrame.new(t2) * h2.CFrame.Rotation end
					end
				end
				return true, m
			end
		end
		return false, "every method failed"
	end)
	if not okRun then ok, how = false, tostring(ok) end
	Travel.Busy = false
	Travel.LastMethod = ok and how or nil
	say(ok and (("arrived at %s (%s)"):format(name, tostring(how))) or (("could not reach %s: %s"):format(name, tostring(how))))
	if opts.face and ok then
		local _, _, hrp = parts()
		if hrp then
			local d = opts.face - hrp.Position
			d = V3(d.X, 0, d.Z)
			if d.Magnitude > 0.5 then hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + d) end
		end
	end
	if Travel.Notify then Travel.Notify(ok and (("Arrived: %s (%s)"):format(name, tostring(how))) or (("Travel failed: %s"):format(tostring(how)))) end
	return ok, how
end

function Travel.To(pos, opts)
	if Travel.Busy then return false, "busy" end
	task.spawn(Travel.ToSync, pos, opts)
	return true
end

function Travel.ToPlayer(plr)
	local h = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if not h then return false, "that player has no character" end
	return Travel.To(h.Position + h.CFrame.LookVector * -4, { name = plr.DisplayName })
end

function Travel.Back()
	local p = table.remove(Travel.History)
	if not p then return false, "no place to go back to" end
	return Travel.To(p, { name = "your last place", noHistory = true })
end

function Travel.Stop() Travel.Cancel = true end

return Travel

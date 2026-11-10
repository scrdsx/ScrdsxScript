-- Escape: get away from the police. Uses the Travel system (instant jump, hops, walking), not your car.
--   * Hideouts: your own saved hideouts first, else a road point far from every police player / police car (picked fresh each time).
--   * Lay low: after the jump it stays put until you are no longer wanted; when police show up again it jumps to a new hideout (up to 4 times).
--   * Auto: runs by itself when you are wanted and police (a player, or a police car with its lights on) come within a set distance.
--   * Panic key: runs it right now.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local V3 = Vector3.new
local Travel = __import("travel")
local ESP = __import("esp")
local Tele = __import("teleport")
local Data = __import("roaddata")

local Escape = {
	Auto = false, Dist = 140, LayLow = 90, OnCuff = false, SavedFirst = true,
	Busy = false, Info = "off", Notify = nil, Changed = nil, Log = nil, Escapes = 0,
}

local function log(m) if Escape.Log then Escape.Log("escape: " .. m) end end
local function say(s)
	Escape.Info = s
	log(s)
	if Escape.Changed then task.defer(Escape.Changed) end
end
local function note(m, sec) if Escape.Notify then Escape.Notify(m, sec) end end

local function me()
	local c = lp.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return c, h, r
end

local function wanted()
	local _, _, r = me()
	return r ~= nil and r:GetAttribute("IsWanted") == true
end

local function nearestPoliceDist(origin, activeOnly)
	local best
	for _, p in ipairs(ESP.PolicePositions(activeOnly)) do
		local d = (p - origin).Magnitude
		if not best or d < best then best = d end
	end
	return best
end

-- where to go: saved hideouts far enough from the police, else the best of 60 random road points
local function pickHideout(origin)
	local police = ESP.PolicePositions(false)
	local function policeDist(p)
		local b = 1e9
		for _, q in ipairs(police) do
			local d = math.sqrt((q.X - p.X) ^ 2 + (q.Z - p.Z) ^ 2)
			if d < b then b = d end
		end
		return b
	end
	local best, bestScore, bestName
	if Escape.SavedFirst then
		for _, s in ipairs(Tele.Saved or {}) do
			if s.name:find("^Hideout") then
				local d = policeDist(s.pos)
				local away = (s.pos - origin).Magnitude
				if d > 250 and away > 60 and (not bestScore or d > bestScore) then best, bestScore, bestName = s.pos, d, s.name end
			end
		end
		if best then return best, bestName end
	end
	local q = Data.quads
	local n = #q // 9
	for _ = 1, 60 do
		local k = math.random(0, n - 1) * 9 + 1
		local x = (q[k] + q[k + 2] + q[k + 4] + q[k + 6]) / 4
		local z = (q[k + 1] + q[k + 3] + q[k + 5] + q[k + 7]) / 4
		local y = q[k + 8]
		local away = math.sqrt((x - origin.X) ^ 2 + (z - origin.Z) ^ 2)
		if away > 450 and away < 2200 and y > -20 and y < 60 then
			local score = math.min(policeDist(V3(x, y, z)), 1500) + math.min(away, 1000) * 0.3 + math.random() * 80
			if not bestScore or score > bestScore then best, bestScore, bestName = V3(x, y + 2, z), score, "a quiet road" end
		end
	end
	return best, bestName
end

function Escape.Run(reason)
	if Escape.Busy then return false, "already escaping" end
	if Travel.Busy then return false, "travelling" end
	Escape.Busy = true
	task.spawn(function()
		local ok, err = pcall(function()
			for round = 1, 4 do
				if not Escape.Busy then break end
				local _, hum, hrp = me()
				if not (hum and hrp and hum.Health > 0) then say("not alive"); return end
				local spot, name = pickHideout(hrp.Position)
				if not spot then say("no hideout found"); return end
				say(("escaping (%s): jumping to %s, %.0f studs away"):format(reason or "?", name, (spot - hrp.Position).Magnitude))
				note(("Escaping (%s) to %s"):format(reason or "?", name), 3)
				local moved, how = Travel.ToSync(spot, { name = name, waitAlive = false })
				if not moved then say("could not move: " .. tostring(how)); note("Escape failed: " .. tostring(how), 4); return end
				Escape.Escapes = Escape.Escapes + 1
				-- lay low
				local t0 = os.clock()
				local again = false
				while Escape.Busy and os.clock() - t0 < Escape.LayLow do
					if not wanted() then say("you are not wanted any more"); note("Escape done: not wanted any more", 4); return end
					local _, _, r2 = me()
					local d = r2 and nearestPoliceDist(r2.Position, false)
					if d and d < 90 then say(("police found you again (%.0f studs): moving on"):format(d)); again = true; break end
					say(("laying low: %d s left"):format(math.max(0, math.floor(Escape.LayLow - (os.clock() - t0)))))
					task.wait(1)
				end
				if not again then
					if not wanted() then say("you are not wanted any more"); note("Escape done", 3); return end
					break
				end
			end
			say("done (still wanted: stay hidden or press the panic key again)")
		end)
		if not ok then log("error: " .. tostring(err)) end
		Escape.Busy = false
		if Escape.Changed then task.defer(Escape.Changed) end
	end)
	return true
end

function Escape.Stop()
	Escape.Busy = false
	Travel.Stop()
end

-- Auto: 4 times a second
local conn
local lastCheck = 0
function Escape.Start()
	if conn then return end
	conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastCheck < 0.25 then return end
		lastCheck = now
		if not Escape.Auto or Escape.Busy or Travel.Busy then return end
		local c, hum, hrp = me()
		if not (hum and hrp and hum.Health > 0) then return end
		if Escape.OnCuff and c:GetAttribute("IsCuffed") == true then
			Escape.Run("cuffed: trying to break away")
			return
		end
		if wanted() then
			local d = nearestPoliceDist(hrp.Position, true)
			if d and d <= Escape.Dist then Escape.Run(("police %d studs away"):format(math.floor(d))) end
		end
	end)
end

function Escape.Destroy()
	Escape.Auto = false
	Escape.Busy = false
	if conn then conn:Disconnect(); conn = nil end
	Escape.Changed, Escape.Notify = nil, nil
end

return Escape

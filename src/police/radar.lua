-- Radar Farm (police): fines every player driving past you over the speed limit, using the game's own radar gun.
--
-- From the dump (ReplicatedStorage.Code.components.tools.radarGunTool):
--   client: FireServer on mBd["7946e262-..."] with (radarGunTool, origin, lookDirection)
--   server: origin is clamped to 10 studs from your Head, raycasts 500 studs along the direction (ignores Roads, Drops,
--           ladders, placeables, tapes, throwables, destroyed objects and every character), takes the first car it hits,
--           and fines its driver if  DriveSeat speed (studs/s) > speed limit at the car  and  radarGunService:canMeasure(you, them).
--           It then sends you the "Radar Control" notification (we count fines from that).
-- So we skip the aiming: for each speeding car in range we find an origin near your head with a clear line to it and fire at it.
-- Several cars per sweep is fine (one call = one car). The tool has to be the one in your hand (equipped).
-- UNTESTED in game: canMeasure's rules (cooldown per driver? on duty?) are server side, so the per-driver wait is a guess.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer
local Drive = __import("drive/autodrive")

local MEASURE = "7946e262-f35b-41ea-b37c-fc806ef522e4"
local TOOL_TAG = "Radar Gun Tool"
local HEAD_TOL = 9.5 -- the server allows 10

local Radar = {
	Enabled = false, Range = 350, Over = 2, PerSweep = 4, Interval = 0.4, Wait = 20,
	AutoEquip = true, SkipPolice = true, Mark = true,
	Fines = 0, Total = 0, Info = "off",
}

local conn, notifyConn
local watchFines
local cooldown = {} -- player -> os.clock() when they may be fined again
local marks = {}    -- car model -> Highlight
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
params.RespectCanCollide = true

-- The game renames its remotes folder and re-rolls every remote id on updates (mBd/7946e262 in the dump, neE/665ea796 on
-- 2026-11-23). So the id is read from the game's own radar code: the GUID string constant in RadarGunTool.onMeasureInput.
-- Fallbacks: an id learned from you measuring once by hand (namecall hook), then the last known ids.
local GUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
local KNOWN = { "665ea796-71e1-40ca-ab66-1de4e226345a", MEASURE }
local measureRemote, learned
local function byName(id)
	for _, f in ipairs(RS:GetChildren()) do
		local r = f:FindFirstChild(id)
		if r and r:IsA("RemoteEvent") then return r end
	end
end
local function idFromCode()
	local getc = (debug and debug.getconstants) or getconstants
	if not getc then return end
	local ok, mod = pcall(function()
		return require(RS.Code.components.tools.radarGunTool)
	end)
	local cls = ok and type(mod) == "table" and mod.RadarGunTool
	local fn = cls and rawget(cls, "onMeasureInput")
	if type(fn) ~= "function" then return end
	local okc, consts = pcall(getc, fn)
	if not okc then return end
	for _, c in pairs(consts) do
		if type(c) == "string" and c:match(GUID) and byName(c) then return c end
	end
end
-- learn it from a real measurement (you click with the radar gun once). Installed only while Radar Farm is on and the id
-- could not be read from the code, and removed again once learned / on unload: a namecall hook slows every method call in the game.
local hookOld, hookFn, hookLive = nil, nil, false
local function unhook()
	hookLive = false -- from now on the hook (if it stays) only passes calls through
	if not hookOld then return end
	-- put the old one back only if ours is still the outermost hook (another module may have hooked on top of it since)
	local ok, top = pcall(function() return getrawmetatable(game).__namecall end)
	if ok and top == hookFn then
		pcall(function() hookmetamethod(game, "__namecall", hookOld) end)
		hookOld, hookFn = nil, nil
	end
end
local function installLearnHook()
	if learned or not (hookmetamethod and getnamecallmethod and newcclosure) then return end
	hookLive = true
	if hookOld then return end
	pcall(function()
		local old
		hookFn = newcclosure(function(self, ...)
			if not hookLive then return old(self, ...) end
			-- no method calls in here (they would overwrite the namecall method of the call we pass on): properties only
			local m = getnamecallmethod()
			if m == "FireServer" and not learned then
				local a = ...
				if typeof(a) == "Instance" and a.ClassName == "Tool" and typeof(self) == "Instance" and self.ClassName == "RemoteEvent" then
					local n = a.Name
					if type(n) == "string" and n:lower():find("radar") then learned = self end
				end
			end
			setnamecallmethod(m)
			return old(self, ...)
		end)
		old = hookmetamethod(game, "__namecall", hookFn)
		hookOld = old
	end)
end

local nextLookup = 0
local function getMeasureRemote()
	if measureRemote and measureRemote.Parent then return measureRemote end
	if learned and learned.Parent then measureRemote = learned; unhook(); return learned end
	local now = os.clock()
	if now < nextLookup then return nil end -- reading the game's code is not free: at most every 10 s
	nextLookup = now + 10
	local id = idFromCode()
	measureRemote = id and byName(id)
	if not measureRemote then
		for _, k in ipairs(KNOWN) do measureRemote = byName(k); if measureRemote then break end end
	end
	if measureRemote then unhook() else installLearnHook() end
	return measureRemote
end

local function findTool()
	local char = lp.Character
	for _, root in ipairs({ char, lp:FindFirstChildOfClass("Backpack") }) do
		if root then
			for _, t in ipairs(root:GetChildren()) do
				if t:IsA("Tool") and CS:HasTag(t, TOOL_TAG) then return t end
			end
		end
	end
	-- fallback by name, in case the tag is only on the server copy
	for _, root in ipairs({ char, lp:FindFirstChildOfClass("Backpack") }) do
		if root then
			for _, t in ipairs(root:GetChildren()) do
				if t:IsA("Tool") and t.Name:lower():find("radar") then return t end
			end
		end
	end
end

-- the same things the server's ray ignores
local function filterList()
	local list = {}
	local function add(i) if i then list[#list + 1] = i end end
	add(workspace:FindFirstChild("Roads")); add(workspace:FindFirstChild("Drops")); add(workspace:FindFirstChild("DestroyedObjects"))
	local obj = workspace:FindFirstChild("Objects")
	if obj then for _, n in ipairs({ "Ladders", "Placeables", "Tapes", "Throwables" }) do add(obj:FindFirstChild(n)) end end
	for _, c in ipairs(CS:GetTagged("Character")) do add(c) end
	add(lp.Character)
	return list
end

-- the car a hit part belongs to (the model that holds the DriveSeat), like the game's getVehicle
local function carOf(part)
	local m = part and part.Parent
	while m and m ~= game do
		if m:FindFirstChild("DriveSeat") then return m end
		m = m.Parent
	end
end

-- a point within HEAD_TOL of the head that has a clear line to the car (straight, over the top, or round the side)
local function clearShot(head, car, aimAt)
	local tries = { Vector3.zero, Vector3.new(0, HEAD_TOL * 0.55, 0), Vector3.new(0, HEAD_TOL, 0) }
	local flat = Vector3.new(aimAt.X - head.X, 0, aimAt.Z - head.Z)
	if flat.Magnitude > 0.1 then
		local side = Vector3.new(-flat.Z, 0, flat.X).Unit
		tries[#tries + 1] = side * HEAD_TOL
		tries[#tries + 1] = -side * HEAD_TOL
		tries[#tries + 1] = (side * 0.7 + Vector3.yAxis * 0.7) * HEAD_TOL
		tries[#tries + 1] = (-side * 0.7 + Vector3.yAxis * 0.7) * HEAD_TOL
	end
	for _, off in ipairs(tries) do
		local o = head + off
		local d = aimAt - o
		if d.Magnitude < 495 then
			local hit = workspace:Raycast(o, d.Unit * 500, params)
			if hit and carOf(hit.Instance) == car then return o, d.Unit end
		end
	end
end

local function setMark(car, on)
	local h = marks[car]
	if on and Radar.Mark then
		if not h or not h.Parent then
			h = Instance.new("Highlight")
			h.FillColor = Color3.fromRGB(255, 70, 70); h.OutlineColor = Color3.fromRGB(255, 200, 200)
			h.FillTransparency = 0.75; h.OutlineTransparency = 0.2
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Adornee = car; h.Parent = car
			marks[car] = h
		end
	elseif h then
		pcall(function() h:Destroy() end)
		marks[car] = nil
	end
end

local function clearMarks()
	for car in pairs(marks) do setMark(car, false) end
end

local last = 0
local function sweep()
	local now = os.clock()
	if now - last < Radar.Interval then return end
	last = now

	local char = lp.Character
	local head = char and char:FindFirstChild("Head")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not head or not hum then Radar.Info = "no character"; return end
	if lp.Team and lp.Team.Name ~= "Police" then Radar.Info = "join the Police team"; clearMarks(); return end

	local tool = findTool()
	if not tool then Radar.Info = "no radar gun (get one from the police station)"; clearMarks(); return end
	if tool.Parent ~= char then
		if Radar.AutoEquip then pcall(function() hum:EquipTool(tool) end); Radar.Info = "equipping the radar gun" else Radar.Info = "hold the radar gun" end
		return
	end

	local r = getMeasureRemote()
	if not r then Radar.Info = "radar remote not found: measure one car by hand once"; return end
	if not notifyConn then watchFines() end

	-- every car in range with a driver going over the limit
	local hp = head.Position
	local list, seen, inRange = {}, {}, 0
	local myCar = carOf(hum.SeatPart)
	for _, car in ipairs(CS:GetTagged("Vehicle")) do
		local ds = car:FindFirstChild("DriveSeat")
		local occ
		if ds then pcall(function() occ = ds.Occupant end) end
		local plr = occ and Players:GetPlayerFromCharacter(occ.Parent)
		if plr and plr ~= lp and car ~= myCar then
			local dist = (ds.Position - hp).Magnitude
			if dist <= Radar.Range then
				inRange = inRange + 1
				local speed = ds.AssemblyLinearVelocity.Magnitude
				local limit = Drive.SpeedLimitAt(ds.Position)
				local over = speed - limit
				local skip = car:GetAttribute("IsBeingTowed") == true or (Radar.SkipPolice and plr.Team and (plr.Team.Name == "Police" or plr.Team.Name == "FireDepartment"))
				if over > Radar.Over and not skip then
					seen[car] = true
					if (cooldown[plr] or 0) <= now then list[#list + 1] = { car = car, ds = ds, plr = plr, over = over, dist = dist } end
				end
			end
		end
	end
	for car in pairs(marks) do if not seen[car] then setMark(car, false) end end
	for car in pairs(seen) do setMark(car, true) end

	-- most over the limit first (biggest fine), then nearest
	table.sort(list, function(a, b) if math.abs(a.over - b.over) > 3 then return a.over > b.over end return a.dist < b.dist end)
	params.FilterDescendantsInstances = filterList()
	local fired = 0
	for _, e in ipairs(list) do
		if fired >= Radar.PerSweep then break end
		local aim = e.ds.Position + Vector3.new(0, 1, 0)
		local o, dir = clearShot(hp, e.car, aim)
		if not o then o, dir = clearShot(hp, e.car, e.car:GetPivot().Position) end
		if o then
			local ok = pcall(function() r:FireServer(tool, o, dir) end)
			if ok then
				fired = fired + 1
				Radar.Total = Radar.Total + 1
				cooldown[e.plr] = now + Radar.Wait
			end
		end
	end
	Radar.Info = ("%d cars near  ·  %d speeding  ·  %d fined%s"):format(inRange, #list, Radar.Fines, fired > 0 and ("  ·  radared " .. fired) or "")
end

-- fines: the "Radar Control" notification. Its remote id changes with updates too, so listen on every remote in the folder.
local notifyConns = {}
local function onNotify(...)
	for _, a in ipairs({ ... }) do
		if type(a) == "table" and a.title == "Radar Control" then
			Radar.Fines = Radar.Fines + 1
			if Radar.OnFine then
				local args = type(a.arguments) == "table" and a.arguments or {}
				local who = type(args.playerName) == "table" and args.playerName.value
				local over = type(args.overSpeeding) == "table" and args.overSpeeding.value
				pcall(Radar.OnFine, who, over)
			end
			return
		end
	end
end
watchFines = function()
	local r = getMeasureRemote()
	local folder = r and r.Parent
	if not folder then return end
	for _, c in ipairs(notifyConns) do pcall(function() c:Disconnect() end) end
	notifyConns = {}
	for _, e in ipairs(folder:GetChildren()) do
		if e:IsA("RemoteEvent") and e ~= r then notifyConns[#notifyConns + 1] = e.OnClientEvent:Connect(onNotify) end
	end
	notifyConn = true
end

function Radar.SetEnabled(v)
	Radar.Enabled = v
	if v then
		watchFines()
	else
		unhook()
		clearMarks()
		Radar.Info = "off"
	end
end

function Radar.Start()
	if conn then return end
	pcall(function() getgenv().ScrdsxRadarInfo = function() return ("%s  |  sent %d, fined %d"):format(Radar.Info, Radar.Total, Radar.Fines) end end)
	conn = RunService.Heartbeat:Connect(function()
		if not Radar.Enabled then return end
		local ok, err = pcall(sweep)
		if not ok then Radar.Info = "error: " .. tostring(err) end
	end)
end

function Radar.Destroy()
	unhook()
	if conn then conn:Disconnect(); conn = nil end
	for _, c in ipairs(notifyConns) do pcall(function() c:Disconnect() end) end
	notifyConns = {}; notifyConn = nil
	clearMarks()
	Radar.Enabled = false
end

return Radar

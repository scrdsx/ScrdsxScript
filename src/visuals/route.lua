-- Money route: a glowing line on the road from you to the best robbery that is READY right now, planned along the real roads
-- (drive/roadplan.lua, the same planner Auto Drive uses), plus a light pillar on the target and a small HUD pill (name, distance, ETA).
--   pick:   READY places only (status from visuals/shops.lua), high-risk ones skipped if you want (police close by or an alarm going).
--           "Best money" ranks by rough value per minute: value of the place / (travel time + time the robbery takes).
--           The values are estimates (bank > jewellery > club safe > register), not read from the game.
--   draw:   Beams between Attachments in Terrain (drawn by the engine, nothing per frame in Lua apart from a 5 Hz progress check);
--           the part of the line behind you disappears as you go.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shops = __import("visuals/shops")
local Plan = __import("drive/roadplan")
local lp = Players.LocalPlayer

local Route = {
	Enabled = false, Mode = "Best money", SkipRisky = true, Pillar = true, Hud = true, Width = 1.2,
	Color = Color3.fromRGB(124, 131, 255), EndColor = Color3.fromRGB(70, 215, 120),
	Info = "off", Notify = nil,
}
Route.Modes = { "Best money", "Nearest ready", "Bank + jewellery only" }

local VALUE = { bank = 10, jewel = 8, safe = 4, register = 1 }   -- rough relative payout
local ROBTIME = { bank = 90, jewel = 70, safe = 30, register = 12 } -- rough seconds the robbery itself takes
local UP = Vector3.new(0, 1.6, 0)

local conn, gui, pill, pillText, folder
local target, targetKey
local path, pathVer, drawnVer, prog = nil, 0, -1, 1
local planning, plannedAt = false, -99
local lastPick, lastTick = -99, 0
local atts, beams, glows = {}, {}, {}
local pillarA, pillarB, pillarBeam

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end

-- where "you" are: your car if you sit in one, else your character
local function myPos()
	local ch = lp.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat then return seat.Position, seat.AssemblyLinearVelocity.Magnitude end
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then return hrp.Position, hrp.AssemblyLinearVelocity.Magnitude end
	return nil, 0
end

local function score(c, d)
	if Route.Mode == "Nearest ready" then return -d end
	return (VALUE[c.kind] or 1) / (d / 45 + (ROBTIME[c.kind] or 20))
end

-- best READY place; the current one is kept unless another one is clearly better (no flip-flopping between two)
local function pick(origin)
	local best, bestS, cur, curS
	for _, c in ipairs(Shops.Candidates()) do
		local ok = c.ready and not (Route.SkipRisky and c.risk == "HIGH")
		if Route.Mode == "Bank + jewellery only" and c.kind ~= "bank" and c.kind ~= "jewel" then ok = false end
		if ok then
			local s = score(c, (c.pos - origin).Magnitude)
			if not bestS or s > bestS then best, bestS = c, s end
			if c.key == targetKey then cur, curS = c, s end
		end
	end
	if cur and best ~= cur and bestS < curS + math.abs(curS) * 0.25 then return cur end
	return best
end

-- POOL OF BEAMS -------------------------------------------------------------------------------------------------------------------
local function att(i)
	local a = atts[i]
	if not a then
		a = Instance.new("Attachment")
		a.Name = tostring(math.random(1e6, 9e6))
		a.Parent = workspace.Terrain
		atts[i] = a
	end
	return a
end

local function newBeam(a0, a1, glow)
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.FaceCamera = true
	b.Segments = 1
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Width0, b.Width1 = glow and Route.Width * 3.2 or Route.Width, glow and Route.Width * 3.2 or Route.Width
	b.Transparency = NumberSequence.new(glow and 0.86 or 0.12)
	b.Enabled = false
	b.Parent = folder
	return b
end

local function beamAt(i)
	if not beams[i] then
		beams[i] = newBeam(att(i), att(i + 1), false)
		glows[i] = newBeam(att(i), att(i + 1), true)
	end
	return beams[i], glows[i]
end

local function hideFrom(n)
	for i = n, #beams do
		if beams[i].Enabled then beams[i].Enabled = false; glows[i].Enabled = false end
	end
end

local function setPillar(pos)
	if not Route.Pillar or not pos then
		if pillarBeam then pillarBeam.Enabled = false end
		return
	end
	if not pillarBeam then
		pillarA, pillarB = Instance.new("Attachment"), Instance.new("Attachment")
		pillarA.Parent, pillarB.Parent = workspace.Terrain, workspace.Terrain
		pillarBeam = Instance.new("Beam")
		pillarBeam.Attachment0, pillarBeam.Attachment1 = pillarA, pillarB
		pillarBeam.FaceCamera = true
		pillarBeam.LightEmission = 1
		pillarBeam.LightInfluence = 0
		pillarBeam.Width0, pillarBeam.Width1 = 3, 3
		pillarBeam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
		pillarBeam.Parent = folder
	end
	pillarA.WorldPosition = pos
	pillarB.WorldPosition = pos + Vector3.new(0, 90, 0)
	pillarBeam.Color = ColorSequence.new(Route.EndColor)
	pillarBeam.Enabled = true
end

-- (re)draw the whole path: only when a new path arrives or a colour / width setting changes
local function drawPath()
	drawnVer = pathVer
	if not path then hideFrom(1); return end
	local n = #path
	for i = 1, n do att(i).WorldPosition = path[i] + UP end
	for i = 1, n - 1 do
		local b, g = beamAt(i)
		local t0, t1 = (i - 1) / math.max(n - 1, 1), i / math.max(n - 1, 1)
		local cs = ColorSequence.new(Route.Color:Lerp(Route.EndColor, t0), Route.Color:Lerp(Route.EndColor, t1))
		b.Color, g.Color = cs, cs
		b.Width0, b.Width1 = Route.Width, Route.Width
		g.Width0, g.Width1 = Route.Width * 3.2, Route.Width * 3.2
	end
	hideFrom(n)
	prog = 1
end

function Route.Restyle() drawnVer = -1 end

-- PLANNING (in the background; the planner yields so the game keeps its frame rate) -----------------------------------------------
local function replan(origin, tpos)
	if planning then return end
	planning = true
	plannedAt = os.clock()
	local forKey = targetKey
	task.spawn(function()
		if not Plan.Yield then Plan.Yield = function() task.wait() end end
		local ok, pts = pcall(function() return Plan.Route(origin.X, origin.Z, tpos.X, tpos.Z, { ay = origin.Y, by = tpos.Y, minEdge = 1 }) end)
		local list = {}
		if ok and type(pts) == "table" and #pts > 0 then
			list[1] = origin
			for _, p in ipairs(pts) do list[#list + 1] = Vector3.new(p.x or p[1], p.y or p[2] or origin.Y, p.z or p[3]) end
			-- the last stretch from the road to the door, in 10-stud steps
			local last = list[#list]
			local gap = (tpos - last).Magnitude
			for k = 1, math.floor(gap / 10) do list[#list + 1] = last:Lerp(tpos, k * 10 / gap) end
			list[#list + 1] = tpos
			Route.Info = "road route"
		else
			-- no road route (off the road map): a straight line in 10-stud steps
			local gap = (tpos - origin).Magnitude
			list[1] = origin
			for k = 1, math.floor(gap / 10) do list[#list + 1] = origin:Lerp(tpos, k * 10 / gap) end
			list[#list + 1] = tpos
			Route.Info = "straight line (no road route)"
		end
		if Route.Enabled and forKey == targetKey then
			path = list
			pathVer = pathVer + 1
		end
		planning = false
	end)
end

-- HUD ---------------------------------------------------------------------------------------------------------------------------------
local function buildHud()
	gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 4
	gui.Parent = guiParent()
	pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(.5, 0); pill.Position = UDim2.new(.5, 0, 0, 114); pill.Size = UDim2.fromOffset(0, 32); pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = Color3.fromRGB(15, 15, 19); pill.BackgroundTransparency = 0.08; pill.BorderSizePixel = 0; pill.Visible = false; pill.Parent = gui
	Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 9)
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(38, 38, 46); st.Parent = pill
	local pd = Instance.new("UIPadding"); pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = pill
	pillText = Instance.new("TextLabel")
	pillText.BackgroundTransparency = 1; pillText.Size = UDim2.fromOffset(0, 32); pillText.AutomaticSize = Enum.AutomaticSize.X
	pillText.RichText = true; pillText.Font = Enum.Font.BuilderSansMedium; pillText.TextSize = 13; pillText.TextColor3 = Color3.fromRGB(200, 203, 212)
	pillText.Text = ""; pillText.Parent = pill
end

local function hex(c) return ("#%02x%02x%02x"):format(math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end

-- STEP (5 times a second) ----------------------------------------------------------------------------------------------------------
local function step()
	if not Route.Enabled then return end
	local origin, speed = myPos()
	if not origin then return end
	local now = os.clock()

	if now - lastPick > 2 then
		lastPick = now
		local best = pick(origin)
		if not best then
			if target then target, targetKey, path = nil, nil, nil; pathVer = pathVer + 1 end
			Route.Info = "nothing ready right now"
		elseif best.key ~= targetKey then
			target, targetKey = best, best.key
			path = nil; pathVer = pathVer + 1
			replan(origin, best.pos)
			if Route.Notify then Route.Notify(("Route: %s (%d st)"):format(best.name, math.floor((best.pos - origin).Magnitude))) end
		else
			target = best -- fresh status / risk
		end
	end

	if target and not planning then
		-- off the line by more than 35 studs, or the route is old: plan again from here
		local off = true
		if path then
			for i = prog, math.min(prog + 6, #path) do
				if (path[i] - origin).Magnitude < 35 then off = false; break end
			end
		end
		if off and now - plannedAt > 1.5 then replan(origin, target.pos)
		elseif now - plannedAt > 20 then replan(origin, target.pos) end
	end

	if drawnVer ~= pathVer then drawPath() end
	setPillar(target and target.pos)

	-- progress: the line behind you disappears
	local remaining = 0
	if path then
		local bestI, bestD = prog, math.huge
		for i = prog, math.min(prog + 25, #path) do
			local d = (path[i] - origin).Magnitude
			if d < bestD then bestI, bestD = i, d end
		end
		if bestI ~= prog then
			for i = prog, bestI - 1 do if beams[i] then beams[i].Enabled = false; glows[i].Enabled = false end end
			prog = bestI
		end
		for i = prog, #path - 1 do
			local b = beams[i]
			if b and not b.Enabled then b.Enabled = true; glows[i].Enabled = true end
		end
		remaining = (path[prog] - origin).Magnitude
		for i = prog, #path - 1 do remaining = remaining + (path[i + 1] - path[i]).Magnitude end
		if target and (target.pos - origin).Magnitude < 18 and Route.Notify and not target.arrived then
			target.arrived = true
			Route.Notify(("Arrived: %s"):format(target.name))
		end
	end

	if pill then
		pill.Visible = Route.Hud and target ~= nil
		if target then
			local v = math.max(speed, 16)
			local eta = remaining > 0 and remaining / v or 0
			local riskCol = target.risk == "HIGH" and "#ff5a5a" or (target.risk == "MEDIUM" and "#f5b43c" or "#46d778")
			pillText.Text = ("<font color=\"%s\"><b>➜  %s</b></font>   <b>%d</b> st   ~%d s   <font color=\"%s\">%s risk</font>"):format(
				hex(Route.EndColor), target.name, math.floor(remaining), math.floor(eta + 0.5), riskCol, (target.risk or "?"):lower())
		end
	end
end

function Route.SetEnabled(v)
	Route.Enabled = v
	if v then
		lastPick, plannedAt = -99, -99
		Route.Info = "looking for a ready place"
	else
		target, targetKey, path = nil, nil, nil
		pathVer = pathVer + 1
		hideFrom(1)
		setPillar(nil)
		if pill then pill.Visible = false end
		Route.Info = "off"
	end
end

-- current target in words (for the module's status label)
function Route.TargetText()
	if not Route.Enabled then return "off" end
	if not target then return Route.Info end
	return ("%s (%s)"):format(target.name, target.status or "?")
end

function Route.Start()
	if conn then return end
	folder = Instance.new("Folder")
	folder.Name = tostring(math.random(1e6, 9e6))
	folder.Parent = workspace.Terrain
	buildHud()
	conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastTick < 0.2 then return end
		lastTick = now
		local ok, err = pcall(step)
		if not ok and Route.Info ~= "error" then Route.Info = "error"; warn("[route] " .. tostring(err)) end
	end)
end

function Route.Destroy()
	if conn then conn:Disconnect(); conn = nil end
	Route.Enabled = false
	pcall(function() folder:Destroy() end)
	for _, a in ipairs(atts) do pcall(function() a:Destroy() end) end
	pcall(function() pillarA:Destroy(); pillarB:Destroy() end)
	pcall(function() gui:Destroy() end)
	atts, beams, glows = {}, {}, {}
	pillarA, pillarB, pillarBeam, gui, pill = nil, nil, nil, nil, nil
end

return Route

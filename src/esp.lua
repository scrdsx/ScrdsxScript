-- ESP v2: other players with box (corners or full, dark outline, optional gradient fill), side health bar, name + role, a detail line
-- (distance, wanted stars / timer, car health, held item), skeleton, outlined tracers, a hover card and the police radar pill.
-- Plain GUI instances (works on every executor). Speed: body parts are looked up once per character, every element remembers what it
-- last showed and is only written when that changes by half a pixel or more (property writes are what costs frames, not the maths),
-- and nothing is touched for players that stay hidden.
-- Roles come from the game's own Teams: Police = blue, FireDepartment = red, Prisoner = grey, Citizen = white, other jobs use the team colour.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local V3 = Vector3.new

local ESP = {
	Enabled = false, Boxes = true, CornerBox = true, Fill = true, Outline = true, Skeleton = false, Names = true, Health = true, Distance = true, Tool = true,
	Tracers = false, TracerFrom = "Bottom", TracerTo = "Feet", TracerThickness = 1.4, Wanted = true, Hover = true,
	Fade = true, Radar = true, MaxDist = 900, RadarDist = 350, TextSize = 13,
	Stars = true, CarInfo = true, Spots = false, SpotDist = 220, SpotsWantedOnly = false,
	Teams = { Police = true, FireDepartment = true, Citizen = true, Other = true },
	OnPolice = nil, Info = "off",
}

local COL = {
	Police = Color3.fromRGB(64, 156, 255), FireDepartment = Color3.fromRGB(240, 86, 70),
	Prisoner = Color3.fromRGB(160, 160, 170), Citizen = Color3.fromRGB(236, 237, 242),
}
local RED = Color3.fromRGB(255, 72, 72)
local TAG = { Police = "POLICE", FireDepartment = "FIRE", Prisoner = "PRISONER" }
local BG, STROKE = Color3.fromRGB(15, 15, 19), Color3.fromRGB(38, 38, 46)
local BLACK = Color3.new(0, 0, 0)
local HP_LO, HP_MID, HP_HI = Color3.fromRGB(240, 70, 60), Color3.fromRGB(245, 200, 60), Color3.fromRGB(70, 215, 120)

local BONES_R15 = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local BONES_R6 = {
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" }, { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function hex(c) return ("#%02x%02x%02x"):format(math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end

local function roleOf(plr)
	local t = plr.Team
	local n = t and t.Name or "Citizen"
	local col = COL[n] or (t and t.TeamColor.Color) or COL.Citizen
	local group = (n == "Police" or n == "FireDepartment" or n == "Citizen") and n or "Other"
	return n, col, group
end
ESP.RoleOf = roleOf

-- The game's attribute names are not documented, so what the scans find is written to scrdsx_esp_log.txt (send it if a number looks wrong).
local logLines, logSeen = {}, {}
local function note(key, text)
	if logSeen[key] then return end
	logSeen[key] = true
	logLines[#logLines + 1] = text
	pcall(function() if writefile then writefile("scrdsx_esp_log.txt", table.concat(logLines, "\n")) end end)
end
local function dumpAttrs(tag, inst)
	local ok, at = pcall(inst.GetAttributes, inst)
	if not ok then return end
	local names, parts = {}, {}
	for k, v in pairs(at) do names[#names + 1] = k; parts[#parts + 1] = k .. "=" .. tostring(v) end
	table.sort(names); table.sort(parts)
	note(tag .. ":" .. table.concat(names, ","), ("%s [%s] %s"):format(tag, inst.ClassName, table.concat(parts, ", ")))
end
local function hasKey(l, list)
	for _, s in ipairs(list) do if l:find(s, 1, true) then return true end end
	return false
end

-- WANTED STARS: any numeric attribute / leaderstat with star, wanted or heat in its name (on the root part, character, player)
local function scanWanted(plr, ch, hrp)
	local stars, bounty
	local function eat(k, v)
		if type(v) ~= "number" then return end
		local l = k:lower()
		if l:find("bounty", 1, true) then bounty = math.max(bounty or 0, v)
		elseif l:find("star", 1, true) or l:find("wanted", 1, true) or l:find("heat", 1, true) then stars = math.max(stars or 0, v) end
	end
	for _, inst in ipairs({ hrp, ch, plr }) do
		local ok, at = pcall(inst.GetAttributes, inst)
		if ok then for k, v in pairs(at) do eat(k, v) end end
	end
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		for _, c in ipairs(ls:GetChildren()) do
			if c:IsA("ValueBase") then eat(c.Name, c.Value) end
		end
	end
	return stars, bounty
end
local function starText(stars)
	if stars > 5 then return tostring(math.floor(stars)) end
	local n = math.clamp(math.floor(stars + 0.5), 0, 5)
	return ("★"):rep(n) .. ("☆"):rep(5 - n)
end

-- VEHICLE DAMAGE: a numeric health/condition attribute on the car model; if there is none, the share of body parts still attached (estimate)
local HEALTH_KEYS = { "health", "hp", "condition", "durab", "integrity" }
local function carModel(plr)
	local vf = workspace:FindFirstChild("Vehicles")
	return vf and vf:FindFirstChild(plr.Name)
end
local function scanCar(e, car)
	local frac, real
	local ok, at = pcall(car.GetAttributes, car)
	if ok then
		local maxv
		for k, v in pairs(at) do
			local l = k:lower()
			if type(v) == "number" and l:find("max", 1, true) and hasKey(l, HEALTH_KEYS) then maxv = v end
		end
		for k, v in pairs(at) do
			local l = k:lower()
			if type(v) == "number" and not l:find("max", 1, true) and hasKey(l, HEALTH_KEYS) then
				e.carPeak = math.max(e.carPeak or 0, v)
				local m = maxv or (v <= 100 and 100) or e.carPeak
				frac, real = math.clamp(v / math.max(m, 1), 0, 1), true
			end
		end
	end
	if not frac then
		if e.carRef ~= car then e.carRef, e.carN0 = car, nil end
		local n = 0
		for _, d in ipairs(car:GetDescendants()) do if d:IsA("BasePart") then n = n + 1 end end
		e.carN0 = math.max(e.carN0 or 0, n)
		frac, real = n / math.max(e.carN0, 1), false
	end
	return frac, real
end

local gui, conn, addConn, remConn
local entries = {}
local hover, hoverLabel, radar, radarArrow, radarText, radarStroke

local function hpColor(f)
	if f > 0.5 then return HP_MID:Lerp(HP_HI, (f - 0.5) * 2) end
	return HP_LO:Lerp(HP_MID, f * 2)
end

-- write-on-change helpers: every element keeps what it last showed in e.c
local function vis(e, f, v)
	if e.c[f] ~= v then e.c[f] = v; f.Visible = v end
end
local function rect(e, f, x, y, w, h)
	local c = e.r[f]
	if not c then c = {}; e.r[f] = c end
	if not c[1] or math.abs(c[1] - x) > .5 or math.abs(c[2] - y) > .5 or math.abs(c[3] - w) > .5 or math.abs(c[4] - h) > .5 then
		c[1], c[2], c[3], c[4] = x, y, w, h
		f.Position = UDim2.fromOffset(x, y); f.Size = UDim2.fromOffset(w, h)
	end
end
local function at(e, f, x, y)
	local c = e.r[f]
	if not c then c = {}; e.r[f] = c end
	if not c[1] or math.abs(c[1] - x) > .5 or math.abs(c[2] - y) > .5 then
		c[1], c[2] = x, y
		f.Position = UDim2.fromOffset(x, y)
	end
end
local function prop(e, key, f, p, v)
	if e.p[key] ~= v then e.p[key] = v; f[p] = v end
end
-- a thin rotated frame on the segment (x1,y1)-(x2,y2)
local function seg(e, f, x1, y1, x2, y2, th)
	local c = e.r[f]
	if not c then c = {}; e.r[f] = c end
	if not c[1] or math.abs(c[1] - x1) > .5 or math.abs(c[2] - y1) > .5 or math.abs(c[3] - x2) > .5 or math.abs(c[4] - y2) > .5 or c[5] ~= th then
		c[1], c[2], c[3], c[4], c[5] = x1, y1, x2, y2, th
		local dx, dy = x2 - x1, y2 - y1
		f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), th)
		f.Position = UDim2.fromOffset(x1 + dx / 2, y1 + dy / 2)
		f.Rotation = math.deg(math.atan2(dy, dx))
	end
end

local function line(z)
	return mk("Frame", { AnchorPoint = Vector2.new(.5, .5), BorderSizePixel = 0, BackgroundColor3 = COL.Citizen, Visible = false, ZIndex = z or 2 }, gui)
end
local function txt(size, z, ay)
	return mk("TextLabel", {
		AnchorPoint = Vector2.new(.5, ay), Size = UDim2.fromOffset(260, size + 4), BackgroundTransparency = 1, Font = Enum.Font.BuilderSansBold, TextSize = size,
		TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = BLACK, TextStrokeTransparency = 0.3, RichText = true, Text = "", Visible = false, ZIndex = z or 4,
	}, gui)
end

local PARTS = { "boxO", "box", "fill", "hpBg", "name", "info", "lineO", "line" }

local function newEntry(plr)
	local e = { plr = plr, c = {}, r = {}, p = {}, bones = {}, corners = {}, cornersO = {} }
	-- full box: dark outline behind, colour line on top, soft gradient fill inside
	e.boxO = mk("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 1 }, gui)
	mk("UIStroke", { Thickness = 3, Color = BLACK, Transparency = 0.5 }, e.boxO)
	e.box = mk("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 2 }, gui)
	e.boxS = mk("UIStroke", { Thickness = 1, Color = COL.Citizen }, e.box)
	e.fill = mk("Frame", { BackgroundColor3 = COL.Citizen, BorderSizePixel = 0, Visible = false, ZIndex = 1 }, gui)
	mk("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.96), NumberSequenceKeypoint.new(1, 0.76) }) }, e.fill)
	for i = 1, 8 do
		e.cornersO[i] = mk("Frame", { BorderSizePixel = 0, BackgroundColor3 = BLACK, BackgroundTransparency = 0.5, Visible = false, ZIndex = 1 }, gui)
		e.corners[i] = mk("Frame", { BorderSizePixel = 0, BackgroundColor3 = COL.Citizen, Visible = false, ZIndex = 2 }, gui)
	end
	-- health: a thin bar along the left side of the box
	e.hpBg = mk("Frame", { BackgroundColor3 = BLACK, BackgroundTransparency = 0.3, BorderSizePixel = 0, Visible = false, ZIndex = 2 }, gui)
	e.hp = mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 1, 1, -1), Size = UDim2.new(1, -2, 1, -2), BorderSizePixel = 0, BackgroundColor3 = HP_HI, ZIndex = 3 }, e.hpBg)
	e.name = txt(ESP.TextSize, 4, 1)
	e.info = txt(ESP.TextSize - 2, 4, 0)
	e.info.Font = Enum.Font.BuilderSansMedium
	e.info.TextColor3 = Color3.fromRGB(210, 213, 222)
	e.lineO = line(1); e.lineO.BackgroundColor3 = BLACK; e.lineO.BackgroundTransparency = 0.55
	e.line = line(2)
	for i = 1, #BONES_R15 do e.bones[i] = line(2) end
	entries[plr] = e
	return e
end

local function hide(e)
	if e.hidden then return end
	e.hidden = true
	for _, k in ipairs(PARTS) do e[k].Visible = false end
	for i = 1, 8 do e.corners[i].Visible = false; e.cornersO[i].Visible = false end
	for _, b in ipairs(e.bones) do b.Visible = false end
	e.c, e.r = {}, {}
end

local function dropEntry(plr)
	local e = entries[plr]
	if not e then return end
	entries[plr] = nil
	for _, k in ipairs(PARTS) do pcall(function() e[k]:Destroy() end) end
	for i = 1, 8 do pcall(function() e.corners[i]:Destroy(); e.cornersO[i]:Destroy() end) end
	for _, b in ipairs(e.bones) do pcall(function() b:Destroy() end) end
end

local function buildGui()
	gui = mk("ScreenGui", { Name = tostring(math.random(1e6, 9e6)), ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, guiParent())
	hover = mk("Frame", { BackgroundColor3 = BG, BackgroundTransparency = 0.06, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Visible = false, ZIndex = 8 }, gui)
	mk("UISizeConstraint", { MinSize = Vector2.new(200, 0) }, hover)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, hover)
	mk("UIStroke", { Color = STROKE, Thickness = 1 }, hover)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, hover)
	hoverLabel = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Font = Enum.Font.BuilderSansMedium, TextSize = 13,
		TextColor3 = Color3.fromRGB(196, 199, 209), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, RichText = true, LineHeight = 1.15, ZIndex = 9 }, hover)
	radar = mk("Frame", { AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 74), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = BG, BackgroundTransparency = 0.08, BorderSizePixel = 0, Visible = false }, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 9) }, radar)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 14) }, radar)
	radarStroke = mk("UIStroke", { Color = COL.Police, Thickness = 1.2, Transparency = 0.2 }, radar)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8) }, radar)
	radarArrow = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 20), Text = "▲", TextSize = 15, Font = Enum.Font.BuilderSansBold, TextColor3 = COL.Police }, radar)
	radarText = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 13, Font = Enum.Font.BuilderSansBold,
		TextColor3 = Color3.new(1, 1, 1), RichText = true }, radar)
end

-- nearest police player or police car with its lights on
local function nearestPolice(origin)
	local best, bpos
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp and plr.Team and plr.Team.Name == "Police" then
			local h = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if h then
				local d = (h.Position - origin).Magnitude
				if not best or d < best then best, bpos = d, h.Position end
			end
		end
	end
	local vf = workspace:FindFirstChild("Vehicles")
	for _, m in ipairs(vf and vf:GetChildren() or {}) do
		if m.Name ~= lp.Name and m:GetAttribute("EmergencyLights") == true and tostring(m:GetAttribute("Config") or ""):lower():find("police") then
			local ok, p = pcall(function() return m:GetPivot().Position end)
			if ok then
				local d = (p - origin).Magnitude
				if not best or d < best then best, bpos = d, p end
			end
		end
	end
	return best, bpos
end

-- every police player / police car position (activeOnly: only cars with their lights on)
function ESP.PolicePositions(activeOnly, playersOnly)
	local out = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp and plr.Team and plr.Team.Name == "Police" then
			local h = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if h then out[#out + 1] = h.Position end
		end
	end
	if playersOnly then return out end
	local vf = workspace:FindFirstChild("Vehicles")
	for _, m in ipairs(vf and vf:GetChildren() or {}) do
		if m.Name ~= lp.Name and tostring(m:GetAttribute("Config") or ""):lower():find("police") and (not activeOnly or m:GetAttribute("EmergencyLights") == true) then
			local ok, p = pcall(function() return m:GetPivot().Position end)
			if ok then out[#out + 1] = p end
		end
	end
	return out
end

local lastRadar, lastNotify = 0, -99
local function updateRadar(cam, origin)
	local now = os.clock()
	if now - lastRadar > 0.25 then
		lastRadar = now
		ESP._pd, ESP._pp = nearestPolice(origin)
	end
	local d, p = ESP._pd, ESP._pp
	if not (ESP.Radar and d and d <= ESP.RadarDist and p) then radar.Visible = false; return end
	radar.Visible = true
	local look = cam.CFrame.LookVector
	local f = V3(look.X, 0, look.Z)
	local dir = V3(p.X - origin.X, 0, p.Z - origin.Z)
	if f.Magnitude > 0.01 and dir.Magnitude > 0.01 then
		f, dir = f.Unit, dir.Unit
		radarArrow.Rotation = math.deg(math.atan2(f.X * dir.Z - f.Z * dir.X, f.X * dir.X + f.Z * dir.Z))
	end
	local blink = d < 120 and (math.floor(now * 4) % 2 == 0)
	local c = blink and COL.FireDepartment or COL.Police
	radarStroke.Color = c; radarArrow.TextColor3 = c
	radarText.Text = ("POLICE  <font color=\"%s\">%d st</font>"):format(hex(c), math.floor(d))
	if now - lastNotify > 25 and ESP.OnPolice then
		lastNotify = now
		task.spawn(ESP.OnPolice, d)
	end
end

local function hoverInfo(e, hum, role, col, d, wanted)
	local plr = e.plr
	local lines = { ("<b><font color=\"%s\">%s</font></b>  <font color=\"#a0a8b2\">@%s</font>"):format(hex(col), plr.DisplayName, plr.Name) }
	lines[#lines + 1] = ("Team  <b>%s</b>"):format(role)
	lines[#lines + 1] = ("Health  <b>%d / %d</b>"):format(math.floor(hum.Health + .5), math.floor(hum.MaxHealth + .5))
	lines[#lines + 1] = ("Distance  <b>%d st</b>"):format(math.floor(d))
	local tool = plr.Character and plr.Character:FindFirstChildOfClass("Tool")
	if tool then lines[#lines + 1] = ("Holding  <b>%s</b>"):format(tool.Name) end
	if hum.SeatPart then
		local car = e.car or carModel(plr)
		lines[#lines + 1] = ("Driving  <b>%s</b>"):format(tostring(car and car:GetAttribute("Config") or "a vehicle"))
		if e.carFrac then
			lines[#lines + 1] = ("%s  <b>%d%%</b>"):format(e.carReal and "Car health" or "Car body (estimate)", math.floor(e.carFrac * 100 + .5))
		end
		if car then
			local ft = tostring(car:GetAttribute("flatTires") or "")
			lines[#lines + 1] = ft ~= "" and ("Flat tyres  <b><font color=\"#e74c3c\">%s</font></b>"):format(ft) or "Flat tyres  <b>none</b>"
			local fuel = tonumber(car:GetAttribute("currentFuel"))
			if fuel then lines[#lines + 1] = ("Fuel  <b>%d</b>"):format(math.floor(fuel)) end
			lines[#lines + 1] = ("Armor level  <b>%s</b>"):format(tostring(car:GetAttribute("armorLevel") or "?"))
		end
	end
	if wanted then
		local s = e.stars and ("  " .. starText(e.stars)) or ""
		local since = tonumber(e.plr.Character and e.plr.Character:FindFirstChild("HumanoidRootPart") and e.plr.Character.HumanoidRootPart:GetAttribute("StartTime"))
		if since then
			local sec = math.max(0, math.floor(workspace:GetServerTimeNow() - since))
			s = s .. ("  %d:%02d"):format(math.floor(sec / 60), sec % 60)
		end
		lines[#lines + 1] = "<b><font color=\"#e74c3c\">WANTED" .. s .. "</font></b>"
		if e.bounty then lines[#lines + 1] = ("Bounty  <b>%d</b>"):format(math.floor(e.bounty)) end
	end
	return table.concat(lines, "\n")
end

local function hideAll()
	for _, e in pairs(entries) do hide(e) end
	if hover then hover.Visible = false end
end

-- body parts of a character, looked up once (and again only when the character changes or a part goes missing)
local function charRef(e, plr, now)
	local ch = plr.Character
	if ch ~= e.ch or (e.hrp and e.hrp.Parent ~= ch) or (not e.hrp and now - (e.retry or 0) > 0.5) then
		e.ch, e.retry = ch, now
		e.hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		e.hum = ch and ch:FindFirstChildOfClass("Humanoid")
		e.head = ch and ch:FindFirstChild("Head")
		e.bl = nil
		e.foot = 3
		if e.hrp and e.hum then
			local r6 = e.hum.RigType == Enum.HumanoidRigType.R6
			e.foot = e.hrp.Size.Y / 2 + (r6 and 2 or math.max(e.hum.HipHeight, 1.2))
		end
	end
	return ch, e.hrp, e.hum
end

local function update()
	if not gui then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local myChar = lp.Character
	local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local origin = myHrp and myHrp.Position or cam.CFrame.Position
	if ESP.Radar then updateRadar(cam, origin) elseif radar.Visible then radar.Visible = false end
	local now = os.clock()
	ESP.SpotStep(cam, origin, now)
	if not ESP.Enabled then hideAll(); return end

	local vs = cam.ViewportSize
	local mouse = (ESP.Hover or ESP.TracerFrom == "Cursor") and UIS:GetMouseLocation() or nil
	local hoverBest, hoverD, hoverText
	for plr, e in pairs(entries) do
		local shown = false
		local ch, hrp, hum = charRef(e, plr, now)
		if hrp and hum and hum.Health > 0 then
			local role, col, group = roleOf(plr)
			local pos = hrp.Position
			local d = (pos - origin).Magnitude
			if ESP.Teams[group] and d <= ESP.MaxDist then
				local head = e.head
				local topW = (head and head.Parent) and (head.Position + V3(0, head.Size.Y * 0.62, 0)) or (pos + V3(0, 2.6, 0))
				local top = cam:WorldToViewportPoint(topW)
				local bot = cam:WorldToViewportPoint(pos - V3(0, e.foot or 3, 0))
				if top.Z > 0 and bot.Z > 0 and bot.Y > -50 and top.Y < vs.Y + 50 then
					shown = true
					e.hidden = false
					local wanted = hrp:GetAttribute("IsWanted") == true
					-- slow data (stars, car damage, held item, text): a few times a second, spread over different frames
					if now - (e.slow or 0) > 0.5 then
						e.jit = e.jit or (math.random() * 0.3)
						e.slow = now + e.jit
						if ESP.Stars and (wanted or e.stars) then
							e.stars, e.bounty = scanWanted(plr, ch, hrp)
							if wanted and not e.dumpW then
								e.dumpW = true
								dumpAttrs("wanted hrp", hrp); dumpAttrs("wanted character", ch); dumpAttrs("wanted player", plr)
							end
						elseif not wanted then
							e.stars, e.bounty = nil, nil
						end
						if ESP.CarInfo and hum.SeatPart then
							local car = carModel(plr)
							e.car = car
							if car then
								e.carFrac, e.carReal = scanCar(e, car)
								if not e.dumpC then e.dumpC = true; dumpAttrs("car", car) end
							else
								e.carFrac = nil
							end
						else
							e.car, e.carFrac = nil, nil
						end
						local tool = ESP.Tool and ch:FindFirstChildOfClass("Tool")
						e.toolName = tool and tool.Name or nil
						-- name line
						local tag = TAG[role] and ("  <font size=\"%d\" color=\"%s\">%s</font>"):format(ESP.TextSize - 3, hex(col), TAG[role]) or ""
						local nm = (wanted and ESP.Wanted) and ("<font color=\"%s\">%s</font>"):format(hex(RED), plr.DisplayName) or plr.DisplayName
						e.nameText = nm .. tag
						-- detail line (distance is added per frame below)
						local bits = {}
						if wanted and ESP.Wanted then
							local since = tonumber(hrp:GetAttribute("StartTime"))
							if ESP.Stars and e.stars then bits[#bits + 1] = ("<font color=\"#ff5a5a\"><b>%s</b></font>"):format(starText(e.stars))
							elseif since then
								local s = math.max(0, math.floor(workspace:GetServerTimeNow() - since))
								bits[#bits + 1] = ("<font color=\"#ff5a5a\"><b>WANTED %d:%02d</b></font>"):format(math.floor(s / 60), s % 60)
							else bits[#bits + 1] = "<font color=\"#ff5a5a\"><b>WANTED</b></font>" end
						end
						if ESP.CarInfo and e.carFrac and (e.carReal or e.carFrac < 0.995) then
							bits[#bits + 1] = ("<font color=\"%s\"><b>CAR %d%%</b></font>"):format(hex(hpColor(e.carFrac)), math.floor(e.carFrac * 100 + .5))
						end
						if ESP.CarInfo and e.car and tostring(e.car:GetAttribute("flatTires") or "") ~= "" then bits[#bits + 1] = "<font color=\"#ff5a5a\"><b>FLAT</b></font>" end
						if e.toolName then bits[#bits + 1] = ("<font color=\"#c9b6ff\">%s</font>"):format(e.toolName) end
						e.infoBits = table.concat(bits, "  ")
					end

					local c = (wanted and ESP.Wanted) and RED or col
					local h = math.max(bot.Y - top.Y, 6)
					local w = math.max(h * 0.58, 4)
					local cx = (top.X + bot.X) / 2
					local x0, y0 = cx - w / 2, top.Y
					local fade = ESP.Fade and math.clamp(1 - (d - ESP.MaxDist * 0.6) / (ESP.MaxDist * 0.4), 0.2, 1) or 1
					local tr = 1 - fade
					local trQ = math.floor(tr * 20 + .5) / 20 -- transparency in 5% steps: fewer writes while walking away

					-- box
					local full = ESP.Boxes and not ESP.CornerBox
					vis(e, e.box, full)
					vis(e, e.boxO, full and ESP.Outline)
					if full then
						rect(e, e.box, x0, y0, w, h)
						prop(e, "bc", e.boxS, "Color", c); prop(e, "bt", e.boxS, "Transparency", trQ)
						if ESP.Outline then rect(e, e.boxO, x0, y0, w, h) end
					end
					local corn = ESP.Boxes and ESP.CornerBox
					if corn then
						local l, t = math.max(math.min(w, h) * 0.26, 4), (d < 150 and 2 or 1.5)
						local P = {
							{ x0, y0, l, t }, { x0, y0, t, l }, { x0 + w - l, y0, l, t }, { x0 + w - t, y0, t, l },
							{ x0, y0 + h - t, l, t }, { x0, y0 + h - l, t, l }, { x0 + w - l, y0 + h - t, l, t }, { x0 + w - t, y0 + h - l, t, l },
						}
						for i = 1, 8 do
							local p, cf, co = P[i], e.corners[i], e.cornersO[i]
							vis(e, cf, true)
							rect(e, cf, p[1], p[2], p[3], p[4])
							vis(e, co, ESP.Outline)
							if ESP.Outline then rect(e, co, p[1] - 1, p[2] - 1, p[3] + 2, p[4] + 2) end
						end
						if e.p.cc ~= c or e.p.ct ~= trQ then
							e.p.cc, e.p.ct = c, trQ
							for i = 1, 8 do e.corners[i].BackgroundColor3 = c; e.corners[i].BackgroundTransparency = trQ; e.cornersO[i].BackgroundTransparency = 0.5 + trQ * 0.5 end
						end
					else
						for i = 1, 8 do vis(e, e.corners[i], false); vis(e, e.cornersO[i], false) end
					end
					local fill = ESP.Boxes and ESP.Fill
					vis(e, e.fill, fill)
					if fill then rect(e, e.fill, x0, y0, w, h); prop(e, "fc", e.fill, "BackgroundColor3", c) end

					-- health bar (left side)
					vis(e, e.hpBg, ESP.Health)
					if ESP.Health then
						local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
						local fq = math.floor(frac * 50 + .5) / 50
						rect(e, e.hpBg, x0 - 6, y0 - 1, 4, h + 2)
						if e.p.hf ~= fq then
							e.p.hf = fq
							e.hp.Size = UDim2.new(1, -2, fq, -2 * fq)
							e.hp.BackgroundColor3 = hpColor(fq)
						end
						prop(e, "ht", e.hpBg, "BackgroundTransparency", 0.3 + trQ * 0.7)
					end

					-- name over the box, detail line under it
					vis(e, e.name, ESP.Names)
					if ESP.Names then
						at(e, e.name, cx, y0 - 2)
						prop(e, "nt", e.name, "Text", e.nameText or plr.DisplayName)
						prop(e, "ntr", e.name, "TextTransparency", trQ)
						prop(e, "nst", e.name, "TextStrokeTransparency", 0.3 + trQ * 0.7)
					end
					local dq = d < 100 and math.floor(d) or math.floor(d / 5) * 5
					local info = ESP.Distance and (("<b>%d</b> st"):format(dq)) or ""
					if e.infoBits and e.infoBits ~= "" then info = info ~= "" and (info .. "  " .. e.infoBits) or e.infoBits end
					vis(e, e.info, info ~= "")
					if info ~= "" then
						at(e, e.info, cx, y0 + h + 3)
						prop(e, "it", e.info, "Text", info)
						prop(e, "itr", e.info, "TextTransparency", trQ)
						prop(e, "ist", e.info, "TextStrokeTransparency", 0.3 + trQ * 0.7)
					end

					-- skeleton (close players only)
					if ESP.Skeleton and d < 260 then
						local rig = hum.RigType == Enum.HumanoidRigType.R15 and BONES_R15 or BONES_R6
						if not e.bl or (e.bmiss and now - (e.bt or 0) > 1) then
							e.bt, e.bmiss, e.bl = now, false, {}
							for i, b in ipairs(rig) do
								local q1, q2 = ch:FindFirstChild(b[1]), ch:FindFirstChild(b[2])
								e.bl[i] = { q1, q2 }
								if not (q1 and q2) then e.bmiss = true end
							end
						end
						local proj = {}
						local function pt(p)
							local v = proj[p]
							if not v then v = cam:WorldToViewportPoint(p.Position); proj[p] = v end
							return v
						end
						for i, bf in ipairs(e.bones) do
							local pair = e.bl[i]
							local used = false
							if pair and pair[1] and pair[2] then
								local a, z = pt(pair[1]), pt(pair[2])
								if a.Z > 0 and z.Z > 0 then
									seg(e, bf, a.X, a.Y, z.X, z.Y, 1.4)
									used = true
								end
							end
							vis(e, bf, used)
						end
						if e.p.sc ~= c or e.p.st ~= trQ then
							e.p.sc, e.p.st = c, trQ
							for _, bf in ipairs(e.bones) do bf.BackgroundColor3 = c; bf.BackgroundTransparency = trQ end
						end
					elseif e.bones[1] then
						for _, bf in ipairs(e.bones) do vis(e, bf, false) end
					end

					-- tracer (from the bottom / centre / cursor to the feet, body or head), dark outline under it
					vis(e, e.line, ESP.Tracers)
					vis(e, e.lineO, ESP.Tracers and ESP.Outline)
					if ESP.Tracers then
						local ox, oy = vs.X / 2, vs.Y - 2
						if ESP.TracerFrom == "Centre" then oy = vs.Y / 2 elseif ESP.TracerFrom == "Cursor" and mouse then ox, oy = mouse.X, mouse.Y end
						local ty = y0 + h
						if ESP.TracerTo == "Head" then ty = y0 elseif ESP.TracerTo == "Body" then ty = y0 + h / 2 end
						local th = ESP.TracerThickness * (wanted and 1.5 or 1)
						seg(e, e.line, ox, oy, cx, ty, th)
						if ESP.Outline then seg(e, e.lineO, ox, oy, cx, ty, th + 2) end
						prop(e, "lc", e.line, "BackgroundColor3", c)
						prop(e, "lt", e.line, "BackgroundTransparency", 0.15 + trQ * 0.85)
						prop(e, "lot", e.lineO, "BackgroundTransparency", 0.55 + trQ * 0.45)
					end

					if ESP.Hover and mouse and mouse.X > x0 - 10 and mouse.X < x0 + w + 10 and mouse.Y > y0 - 10 and mouse.Y < y0 + h + 10 and (not hoverD or d < hoverD) then
						hoverBest, hoverD = e, d
						hoverText = hoverInfo(e, hum, role, col, d, wanted)
					end
				end
			end
		end
		if not shown then hide(e) end
	end
	if hoverBest then
		if hoverLabel.Text ~= hoverText then hoverLabel.Text = hoverText end
		hover.Visible = true
		local hs = hover.AbsoluteSize
		local hx = mouse.X + 18
		if hx + hs.X > vs.X - 6 then hx = mouse.X - 18 - hs.X end -- no room on the right: open to the left of the cursor
		hover.Position = UDim2.fromOffset(math.max(hx, 6), math.clamp(mouse.Y + 18, 6, math.max(vs.Y - hs.Y - 6, 6)))
	elseif hover.Visible then
		hover.Visible = false
	end
end

-- WEAK SPOTS: where to hit a car to stop it. Tyres (found by the wheel parts' names, else the four corners), the engine at the front, the fuel tank at the rear.
-- Which end is the front comes from the direction the car is travelling; a parked car uses the model's facing (a guess, so the engine mark can be on the wrong end).
local SPOT = {
	TIRE = { Color3.fromRGB(231, 76, 60), "TIRE" },
	ENGINE = { Color3.fromRGB(243, 156, 18), "ENGINE" },
	TANK = { Color3.fromRGB(241, 196, 15), "TANK" },
}
local spotPool, spotCars, spotInfo, lastSpotScan = {}, {}, setmetatable({}, { __mode = "k" }), 0

local function newSpot()
	local dot = mk("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 0.2, BorderSizePixel = 0, Visible = false }, gui)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
	mk("UIStroke", { Thickness = 1.5, Color = Color3.new(1, 1, 1) }, dot)
	local lb = mk("TextLabel", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(1, 5, .5, 0), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1, Font = Enum.Font.BuilderSansBold, TextSize = 11, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4, Text = "" }, dot)
	return { dot = dot, lb = lb, kind = "" }
end

local function buildSpots(car, info, now)
	local ok, bb, size = pcall(car.GetBoundingBox, car)
	if not ok or not bb then return end
	local pivot = car:GetPivot()
	local xLong = size.X > size.Z
	local axis = xLong and bb.XVector or bb.ZVector
	local len, wid = (xLong and size.X or size.Z) / 2, (xLong and size.Z or size.X) / 2
	local pr = car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart", true)
	local vel = pr and pr.AssemblyLinearVelocity or Vector3.zero
	if vel.Magnitude > 15 then info.sign = axis:Dot(vel) >= 0 and 1 or -1
	elseif not info.sign then info.sign = axis:Dot(pivot.LookVector) >= 0 and 1 or -1 end
	local function loc(l, w, y)
		local v = xLong and Vector3.new(l * info.sign, y, w) or Vector3.new(w, y, l * info.sign)
		return pivot:PointToObjectSpace(bb:PointToWorldSpace(v))
	end
	-- wheels: scanned every few seconds
	if not info.wheels or now - (info.wt or 0) > 6 then
		info.wt = now
		local found = {}
		for _, d in ipairs(car:GetDescendants()) do
			if d:IsA("BasePart") then
				local l = d.Name:lower()
				if (l:find("wheel", 1, true) or l:find("tire", 1, true) or l:find("tyre", 1, true)) and not l:find("arch", 1, true) and not l:find("well", 1, true) then
					local p = d.Position
					local dup = false
					for _, q in ipairs(found) do if (q - p).Magnitude < 1.5 then dup = true; break end end
					if not dup then found[#found + 1] = p end
					if #found >= 6 then break end
				end
			end
		end
		info.wheels = found
	end
	local out = {}
	if #info.wheels >= 2 then
		for _, p in ipairs(info.wheels) do out[#out + 1] = { "TIRE", pivot:PointToObjectSpace(p) } end
	else
		for _, l in ipairs({ 0.62, -0.62 }) do
			for _, w in ipairs({ 0.9, -0.9 }) do out[#out + 1] = { "TIRE", loc(len * l, wid * w, -size.Y * 0.3) } end
		end
	end
	out[#out + 1] = { "ENGINE", loc(len * 0.7, 0, size.Y * 0.05) }
	out[#out + 1] = { "TANK", loc(-len * 0.55, 0, -size.Y * 0.1) }
	info.spots = out
end

local function hideSpots(from)
	for i = from or 1, #spotPool do spotPool[i].dot.Visible = false end
end

function ESP.SpotStep(cam, origin, now)
	if not ESP.Spots then
		if #spotCars > 0 then spotCars = {}; hideSpots() end
		return
	end
	if now - lastSpotScan > 0.5 then
		lastSpotScan = now
		local list = {}
		local vf = workspace:FindFirstChild("Vehicles")
		for _, m in ipairs(vf and vf:GetChildren() or {}) do
			if m:IsA("Model") and m.Name ~= lp.Name then
				local ok, p = pcall(function() return m:GetPivot().Position end)
				local d = ok and (p - origin).Magnitude
				if d and d <= ESP.SpotDist then
					local keep = true
					if ESP.SpotsWantedOnly then
						local owner = Players:FindFirstChild(m.Name)
						local h = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
						keep = h ~= nil and h:GetAttribute("IsWanted") == true
					end
					if keep then list[#list + 1] = { car = m, d = d } end
				end
			end
		end
		table.sort(list, function(a, b) return a.d < b.d end)
		spotCars = {}
		for i = 1, math.min(#list, 3) do
			local car = list[i].car
			local info = spotInfo[car]
			if not info then info = {}; spotInfo[car] = info end
			pcall(buildSpots, car, info, now)
			spotCars[#spotCars + 1] = { car = car, info = info }
		end
	end
	local n = 0
	for _, sc in ipairs(spotCars) do
		local car, spots = sc.car, sc.info.spots
		if spots and car.Parent then
			local pivot = car:GetPivot()
			for _, s in ipairs(spots) do
				local sp = cam:WorldToViewportPoint(pivot:PointToWorldSpace(s[2]))
				if sp.Z > 0 then
					n = n + 1
					local e = spotPool[n]
					if not e then e = newSpot(); spotPool[n] = e end
					local kind = SPOT[s[1]]
					e.dot.Position = UDim2.fromOffset(sp.X, sp.Y)
					e.dot.Visible = true
					if e.kind ~= s[1] then
						e.kind = s[1]
						e.dot.BackgroundColor3 = kind[1]
						e.lb.Text = kind[2]
						e.lb.TextColor3 = kind[1]
					end
				end
			end
		end
	end
	hideSpots(n + 1)
end

function ESP.SetEnabled(v)
	ESP.Enabled = v
	ESP.Info = v and "on" or "off"
	if not v and gui then hideAll() end
end

-- text size changes rebuild the labels' size (only when it really changed)
function ESP.SetTextSize(n)
	ESP.TextSize = n
	for _, e in pairs(entries) do
		e.name.TextSize = n; e.name.Size = UDim2.fromOffset(260, n + 4)
		e.info.TextSize = n - 2; e.info.Size = UDim2.fromOffset(260, n + 2)
		e.slow = 0
	end
end

function ESP.Start()
	if gui then return end
	buildGui()
	for _, p in ipairs(Players:GetPlayers()) do if p ~= lp then newEntry(p) end end
	addConn = Players.PlayerAdded:Connect(function(p) if p ~= lp then newEntry(p) end end)
	remConn = Players.PlayerRemoving:Connect(dropEntry)
	conn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(update)
		if not ok and ESP.Info ~= "error" then ESP.Info = "error"; warn("[esp] " .. tostring(err)) end
	end)
end

function ESP.Destroy()
	for _, c in ipairs({ conn, addConn, remConn }) do if c then pcall(function() c:Disconnect() end) end end
	conn, addConn, remConn = nil, nil, nil
	if gui then pcall(function() gui:Destroy() end) end
	gui, hover, hoverLabel, radar = nil, nil, nil, nil
	entries = {}
	spotPool, spotCars = {}, {}
end

return ESP

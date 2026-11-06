-- ESP: other players with box, name + role, health bar, distance, tracer, WANTED tag and a hover card, plus a police radar pill.
-- Plain GUI instances only (no Drawing library), so it works on every executor. Roles come from the game's own Teams:
-- Police = blue, FireDepartment = red, Prisoner = grey, Citizen = white, everything else uses the team colour.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local V3 = Vector3.new

local ESP = {
	Enabled = false, Names = true, Health = true, Distance = true, Boxes = true, Tracers = false, Wanted = true, Hover = true,
	Radar = true, MaxDist = 900, RadarDist = 350,
	Teams = { Police = true, FireDepartment = true, Citizen = true, Other = true },
	OnPolice = nil, Info = "off",
}

local COL = {
	Police = Color3.fromRGB(64, 132, 255), FireDepartment = Color3.fromRGB(255, 82, 82),
	Prisoner = Color3.fromRGB(150, 150, 160), Citizen = Color3.fromRGB(235, 235, 240),
}
local TAG = { Police = "POLICE", FireDepartment = "FIRE", Prisoner = "PRISONER" }
local BG, STROKE = Color3.fromRGB(12, 12, 14), Color3.fromRGB(40, 40, 46)

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

local gui, conn, addConn, remConn
local entries = {}
local hover, hoverLabel, radar, radarArrow, radarText, radarStroke

local function label(parent, size, bold)
	local l = mk("TextLabel", {
		BackgroundColor3 = BG, BackgroundTransparency = 0.3, BorderSizePixel = 0, Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium,
		TextSize = size, TextColor3 = Color3.new(1, 1, 1), RichText = true, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Visible = false,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 4) }, l)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) }, l)
	return l
end

local function newEntry(plr)
	local e = { plr = plr }
	e.box = mk("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false }, gui)
	e.stroke = mk("UIStroke", { Thickness = 1.5, Color = COL.Citizen }, e.box)
	e.hpBg = mk("Frame", { BackgroundColor3 = Color3.fromRGB(10, 10, 12), BackgroundTransparency = 0.15, BorderSizePixel = 0, Visible = false }, gui)
	e.hp = mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(80, 220, 120) }, e.hpBg)
	e.name = label(gui, 12, true); e.name.AnchorPoint = Vector2.new(.5, 1)
	e.dist = label(gui, 11, false); e.dist.AnchorPoint = Vector2.new(.5, 0); e.dist.TextColor3 = Color3.fromRGB(190, 190, 196)
	e.line = mk("Frame", { AnchorPoint = Vector2.new(.5, .5), BorderSizePixel = 0, BackgroundColor3 = COL.Citizen, BackgroundTransparency = 0.25, Visible = false }, gui)
	entries[plr] = e
	return e
end

local function hide(e)
	e.box.Visible = false; e.hpBg.Visible = false; e.name.Visible = false; e.dist.Visible = false; e.line.Visible = false
end

local function dropEntry(plr)
	local e = entries[plr]
	if not e then return end
	entries[plr] = nil
	for _, k in ipairs({ "box", "hpBg", "name", "dist", "line" }) do pcall(function() e[k]:Destroy() end) end
end

local function buildGui()
	gui = mk("ScreenGui", { Name = tostring(math.random(1e6, 9e6)), ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, guiParent())
	-- hover card
	hover = mk("Frame", { BackgroundColor3 = BG, BackgroundTransparency = 0.08, BorderSizePixel = 0, Size = UDim2.fromOffset(190, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 5 }, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, hover)
	mk("UIStroke", { Color = STROKE, Thickness = 1 }, hover)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, hover)
	hoverLabel = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Font = Enum.Font.GothamMedium, TextSize = 12,
		TextColor3 = Color3.fromRGB(215, 215, 220), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, RichText = true, ZIndex = 6 }, hover)
	-- police radar pill
	radar = mk("Frame", { AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 74), Size = UDim2.fromOffset(176, 32), BackgroundColor3 = BG, BackgroundTransparency = 0.1, BorderSizePixel = 0, Visible = false }, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 16) }, radar)
	radarStroke = mk("UIStroke", { Color = COL.Police, Thickness = 1.5 }, radar)
	radarArrow = mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(24, 24), Text = "▲", TextSize = 18, Font = Enum.Font.GothamBold, TextColor3 = COL.Police }, radar)
	radarText = mk("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -46, 1, 0), Text = "", TextSize = 13, Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, RichText = true }, radar)
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
	local near = d < 120
	local blink = near and (math.floor(now * 4) % 2 == 0)
	local c = blink and COL.FireDepartment or COL.Police
	radarStroke.Color = c; radarArrow.TextColor3 = c
	radarText.Text = ("POLICE  <font color=\"%s\">%d st</font>"):format(hex(c), math.floor(d))
	if now - lastNotify > 25 and ESP.OnPolice then
		lastNotify = now
		task.spawn(ESP.OnPolice, d)
	end
end

local function hoverInfo(e, hum, hrp, role, col, d, wanted)
	local plr = e.plr
	local lines = { ("<b><font color=\"%s\">%s</font></b>  <font color=\"#8a8a92\">@%s</font>"):format(hex(col), plr.DisplayName, plr.Name) }
	lines[#lines + 1] = ("Team  <b>%s</b>"):format(role)
	lines[#lines + 1] = ("Health  <b>%d / %d</b>"):format(math.floor(hum.Health + .5), math.floor(hum.MaxHealth + .5))
	lines[#lines + 1] = ("Distance  <b>%d st</b>"):format(math.floor(d))
	local tool = plr.Character and plr.Character:FindFirstChildOfClass("Tool")
	if tool then lines[#lines + 1] = ("Holding  <b>%s</b>"):format(tool.Name) end
	if hum.SeatPart then
		local car = workspace:FindFirstChild("Vehicles") and workspace.Vehicles:FindFirstChild(plr.Name)
		lines[#lines + 1] = ("Driving  <b>%s</b>"):format(tostring(car and car:GetAttribute("Config") or "a vehicle"))
	end
	if wanted then lines[#lines + 1] = "<b><font color=\"#ff5252\">WANTED</font></b>" end
	return table.concat(lines, "\n")
end

local function update()
	if not gui then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local myChar = lp.Character
	local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local origin = myHrp and myHrp.Position or cam.CFrame.Position
	if ESP.Radar then updateRadar(cam, origin) elseif radar.Visible then radar.Visible = false end
	if not ESP.Enabled then
		for _, e in pairs(entries) do hide(e) end
		hover.Visible = false
		return
	end
	local vs = cam.ViewportSize
	local mouse = UIS:GetMouseLocation()
	local hoverBest, hoverD, hoverText
	for plr, e in pairs(entries) do
		local ch = plr.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local shown = false
		if hrp and hum and hum.Health > 0 then
			local role, col, group = roleOf(plr)
			local d = (hrp.Position - origin).Magnitude
			if ESP.Teams[group] and d <= ESP.MaxDist then
				local top = cam:WorldToViewportPoint(hrp.Position + V3(0, 3, 0))
				local bot = cam:WorldToViewportPoint(hrp.Position - V3(0, 3.2, 0))
				if top.Z > 0 and bot.Z > 0 then
					shown = true
					local h = math.max(bot.Y - top.Y, 8)
					local w = h * 0.55
					local cx, x0 = top.X, top.X - w / 2
					local wanted = hrp:GetAttribute("IsWanted") == true
					e.box.Visible = ESP.Boxes
					e.box.Position = UDim2.fromOffset(x0, top.Y); e.box.Size = UDim2.fromOffset(w, h)
					e.stroke.Color = wanted and Color3.fromRGB(255, 82, 82) or col
					if ESP.Health then
						e.hpBg.Visible = true
						e.hpBg.Position = UDim2.fromOffset(x0 - 7, top.Y); e.hpBg.Size = UDim2.fromOffset(4, h)
						local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
						e.hp.Size = UDim2.fromScale(1, frac)
						e.hp.BackgroundColor3 = Color3.fromRGB(235, 70, 70):Lerp(Color3.fromRGB(80, 220, 120), frac)
					else
						e.hpBg.Visible = false
					end
					if ESP.Names then
						e.name.Visible = true
						e.name.Position = UDim2.fromOffset(cx, top.Y - 4)
						local tag = TAG[role] and ("  <font color=\"%s\">%s</font>"):format(hex(col), TAG[role]) or ""
						local wt = (wanted and ESP.Wanted) and "  <font color=\"#ff5252\">WANTED</font>" or ""
						e.name.Text = plr.DisplayName .. tag .. wt
					else
						e.name.Visible = false
					end
					if ESP.Distance then
						e.dist.Visible = true
						e.dist.Position = UDim2.fromOffset(cx, bot.Y + 3)
						e.dist.Text = math.floor(d) .. " st"
					else
						e.dist.Visible = false
					end
					if ESP.Tracers then
						local sx, sy = vs.X / 2, vs.Y
						local dx, dy = cx - sx, bot.Y - sy
						e.line.Visible = true
						e.line.BackgroundColor3 = wanted and Color3.fromRGB(255, 82, 82) or col
						e.line.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), 1.5)
						e.line.Position = UDim2.fromOffset(sx + dx / 2, sy + dy / 2)
						e.line.Rotation = math.deg(math.atan2(dy, dx))
					else
						e.line.Visible = false
					end
					if ESP.Hover and mouse.X > x0 - 10 and mouse.X < x0 + w + 10 and mouse.Y > top.Y - 10 and mouse.Y < bot.Y + 10 and (not hoverD or d < hoverD) then
						hoverBest, hoverD = e, d
						hoverText = hoverInfo(e, hum, hrp, role, col, d, wanted)
					end
				end
			end
		end
		if not shown then hide(e) end
	end
	if hoverBest then
		hoverLabel.Text = hoverText
		hover.Visible = true
		hover.Position = UDim2.fromOffset(math.min(mouse.X + 18, vs.X - 200), math.min(mouse.Y + 18, vs.Y - 150))
	else
		hover.Visible = false
	end
end

function ESP.SetEnabled(v)
	ESP.Enabled = v
	ESP.Info = v and "on" or "off"
	if not v and gui then
		for _, e in pairs(entries) do hide(e) end
		hover.Visible = false
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
	gui = nil
	entries = {}
end

return ESP

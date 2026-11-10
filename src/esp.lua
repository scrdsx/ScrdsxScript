-- ESP: other players with box (full or corner style), skeleton, name + role, health bar, distance, tracer, WANTED tag and a hover card,
-- plus a police radar pill. Plain GUI instances only (no Drawing library), so it works on every executor. It fades out with distance.
-- Roles come from the game's own Teams: Police = blue, FireDepartment = red, Prisoner = grey, Citizen = white, other jobs use the team colour.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local V3 = Vector3.new

local ESP = {
	Enabled = false, Boxes = true, CornerBox = true, Skeleton = true, Names = true, Health = true, Distance = true, Tracers = false, Wanted = true, Hover = true,
	Fade = true, Radar = true, MaxDist = 900, RadarDist = 350,
	Teams = { Police = true, FireDepartment = true, Citizen = true, Other = true },
	OnPolice = nil, Info = "off",
}

local COL = {
	Police = Color3.fromRGB(64, 132, 255), FireDepartment = Color3.fromRGB(255, 82, 82),
	Prisoner = Color3.fromRGB(150, 150, 160), Citizen = Color3.fromRGB(235, 235, 240),
}
local RED = Color3.fromRGB(255, 82, 82)
local TAG = { Police = "POLICE", FireDepartment = "FIRE", Prisoner = "PRISONER" }
local BG, STROKE = Color3.fromRGB(12, 12, 14), Color3.fromRGB(40, 40, 46)

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

local function lineFrame(parent)
	return mk("Frame", { AnchorPoint = Vector2.new(.5, .5), BorderSizePixel = 0, BackgroundColor3 = COL.Citizen, Visible = false }, parent)
end

-- put a thin frame on the segment (x1,y1)-(x2,y2)
local function seg(f, x1, y1, x2, y2, th)
	local dx, dy = x2 - x1, y2 - y1
	f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), th)
	f.Position = UDim2.fromOffset(x1 + dx / 2, y1 + dy / 2)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.Visible = true
end

local function newEntry(plr)
	local e = { plr = plr, init = false, bones = {}, corners = {} }
	e.box = mk("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false }, gui)
	e.stroke = mk("UIStroke", { Thickness = 1.5, Color = COL.Citizen }, e.box)
	for i = 1, 8 do
		local c = mk("Frame", { BorderSizePixel = 0, BackgroundColor3 = COL.Citizen, Visible = false }, gui)
		e.corners[i] = c
	end
	e.hpBg = mk("Frame", { BackgroundColor3 = Color3.fromRGB(10, 10, 12), BackgroundTransparency = 0.15, BorderSizePixel = 0, Visible = false }, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 2) }, e.hpBg)
	e.hp = mk("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(80, 220, 120) }, e.hpBg)
	mk("UICorner", { CornerRadius = UDim.new(0, 2) }, e.hp)
	e.name = label(gui, 12, true); e.name.AnchorPoint = Vector2.new(.5, 1)
	e.dist = label(gui, 11, false); e.dist.AnchorPoint = Vector2.new(.5, 0); e.dist.TextColor3 = Color3.fromRGB(190, 190, 196)
	e.line = lineFrame(gui)
	for i = 1, #BONES_R15 do e.bones[i] = lineFrame(gui) end
	entries[plr] = e
	return e
end

local function hide(e)
	e.box.Visible = false; e.hpBg.Visible = false; e.name.Visible = false; e.dist.Visible = false; e.line.Visible = false
	for _, c in ipairs(e.corners) do c.Visible = false end
	for _, b in ipairs(e.bones) do b.Visible = false end
	e.init = false
end

local function dropEntry(plr)
	local e = entries[plr]
	if not e then return end
	entries[plr] = nil
	pcall(function() e.box:Destroy(); e.hpBg:Destroy(); e.name:Destroy(); e.dist:Destroy(); e.line:Destroy() end)
	for _, c in ipairs(e.corners) do pcall(function() c:Destroy() end) end
	for _, b in ipairs(e.bones) do pcall(function() b:Destroy() end) end
end

local function buildGui()
	gui = mk("ScreenGui", { Name = tostring(math.random(1e6, 9e6)), ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, guiParent())
	hover = mk("Frame", { BackgroundColor3 = BG, BackgroundTransparency = 0.08, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Visible = false, ZIndex = 5 }, gui)
	mk("UISizeConstraint", { MinSize = Vector2.new(190, 0) }, hover)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, hover)
	mk("UIStroke", { Color = STROKE, Thickness = 1 }, hover)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, hover)
	hoverLabel = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Font = Enum.Font.GothamMedium, TextSize = 12,
		TextColor3 = Color3.fromRGB(215, 215, 220), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, RichText = true, ZIndex = 6 }, hover)
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

-- every police player / police car position (activeOnly: only cars with their lights on)
function ESP.PolicePositions(activeOnly)
	local out = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp and plr.Team and plr.Team.Name == "Police" then
			local h = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if h then out[#out + 1] = h.Position end
		end
	end
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

local function hideAll()
	for _, e in pairs(entries) do hide(e) end
	if hover then hover.Visible = false end
end

local function update(dt)
	if not gui then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local myChar = lp.Character
	local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
	local origin = myHrp and myHrp.Position or cam.CFrame.Position
	if ESP.Radar then updateRadar(cam, origin) elseif radar.Visible then radar.Visible = false end
	if not ESP.Enabled then hideAll(); return end

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
					local wanted = hrp:GetAttribute("IsWanted") == true
					local c = (wanted and ESP.Wanted) and RED or col
					-- no easing on the screen position: it lagged behind the player whenever the camera turned. Exact every frame.
					local h = math.max(bot.Y - top.Y, 8)
					local w = h * 0.55
					local x0, y0 = top.X - w / 2, top.Y
					local cx = x0 + w / 2
					-- fade with distance (the last 40% of the range)
					local fade = ESP.Fade and math.clamp(1 - (d - ESP.MaxDist * 0.6) / (ESP.MaxDist * 0.4), 0.25, 1) or 1
					local tr = 1 - fade

					-- box: full outline or corners only
					if ESP.Boxes and not ESP.CornerBox then
						e.box.Visible = true
						e.box.Position = UDim2.fromOffset(x0, y0); e.box.Size = UDim2.fromOffset(w, h)
						e.stroke.Color = c; e.stroke.Transparency = tr
					else
						e.box.Visible = false
					end
					if ESP.Boxes and ESP.CornerBox then
						local l, t = math.max(math.min(w, h) * 0.28, 5), 1.5
						local P = {
							{ x0, y0, l, t }, { x0, y0, t, l }, { x0 + w - l, y0, l, t }, { x0 + w - t, y0, t, l },
							{ x0, y0 + h - t, l, t }, { x0, y0 + h - l, t, l }, { x0 + w - l, y0 + h - t, l, t }, { x0 + w - t, y0 + h - l, t, l },
						}
						for i, cf in ipairs(e.corners) do
							local p = P[i]
							cf.Position = UDim2.fromOffset(p[1], p[2]); cf.Size = UDim2.fromOffset(p[3], p[4])
							cf.BackgroundColor3 = c; cf.BackgroundTransparency = tr; cf.Visible = true
						end
					else
						for _, cf in ipairs(e.corners) do cf.Visible = false end
					end

					-- health bar (left of the box)
					if ESP.Health then
						e.hpBg.Visible = true
						e.hpBg.Position = UDim2.fromOffset(x0 - 7, y0); e.hpBg.Size = UDim2.fromOffset(3, h)
						local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
						e.hp.Size = UDim2.fromScale(1, frac)
						e.hp.BackgroundColor3 = Color3.fromRGB(235, 70, 70):Lerp(Color3.fromRGB(80, 220, 120), frac)
						e.hp.BackgroundTransparency = tr
					else
						e.hpBg.Visible = false
					end

					-- name + role + wanted
					if ESP.Names then
						e.name.Visible = true
						-- keep the tag fully on screen (it used to stick out at the screen edge)
						local nsz = e.name.AbsoluteSize
						e.name.Position = UDim2.fromOffset(math.clamp(cx, nsz.X / 2 + 4, math.max(vs.X - nsz.X / 2 - 4, nsz.X / 2 + 4)), math.max(y0 - 4, nsz.Y + 4))
						local tag = TAG[role] and ("  <font color=\"%s\">%s</font>"):format(hex(col), TAG[role]) or ""
						local wt = (wanted and ESP.Wanted) and "  <font color=\"#ff5252\">WANTED</font>" or ""
						e.name.Text = plr.DisplayName .. tag .. wt
						e.name.TextTransparency = tr; e.name.BackgroundTransparency = 0.3 + tr * 0.7
					else
						e.name.Visible = false
					end
					if ESP.Distance then
						e.dist.Visible = true
						local dsz = e.dist.AbsoluteSize
						e.dist.Position = UDim2.fromOffset(math.clamp(cx, dsz.X / 2 + 4, math.max(vs.X - dsz.X / 2 - 4, dsz.X / 2 + 4)), math.min(y0 + h + 3, vs.Y - dsz.Y - 4))
						e.dist.Text = math.floor(d) .. " st"
						e.dist.TextTransparency = tr; e.dist.BackgroundTransparency = 0.3 + tr * 0.7
					else
						e.dist.Visible = false
					end

					-- skeleton
					if ESP.Skeleton and d < 450 then
						local bones = hum.RigType == Enum.HumanoidRigType.R15 and BONES_R15 or BONES_R6
						for i, bf in ipairs(e.bones) do
							local b = bones[i]
							local used = false
							if b then
								local p1, p2 = ch:FindFirstChild(b[1]), ch:FindFirstChild(b[2])
								if p1 and p2 then
									local a = cam:WorldToViewportPoint(p1.Position)
									local z = cam:WorldToViewportPoint(p2.Position)
									if a.Z > 0 and z.Z > 0 then
										seg(bf, a.X, a.Y, z.X, z.Y, 1.3)
										bf.BackgroundColor3 = c; bf.BackgroundTransparency = tr
										used = true
									end
								end
							end
							if not used then bf.Visible = false end
						end
					else
						for _, bf in ipairs(e.bones) do bf.Visible = false end
					end

					-- tracer (feet to the bottom centre of the screen)
					if ESP.Tracers then
						seg(e.line, vs.X / 2, vs.Y, cx, y0 + h, 1.4)
						e.line.BackgroundColor3 = c; e.line.BackgroundTransparency = 0.2 + tr * 0.8
					else
						e.line.Visible = false
					end

					if ESP.Hover and mouse.X > x0 - 10 and mouse.X < x0 + w + 10 and mouse.Y > y0 - 10 and mouse.Y < y0 + h + 10 and (not hoverD or d < hoverD) then
						hoverBest, hoverD = e, d
						hoverText = hoverInfo(e, hum, role, col, d, wanted)
					end
				end
			end
		end
		if not shown then hide(e) end
	end
	if hoverBest then
		hoverLabel.Text = hoverText
		hover.Visible = true
		local hs = hover.AbsoluteSize
		local hx = mouse.X + 18
		if hx + hs.X > vs.X - 6 then hx = mouse.X - 18 - hs.X end -- no room on the right: open to the left of the cursor
		hover.Position = UDim2.fromOffset(math.max(hx, 6), math.clamp(mouse.Y + 18, 6, math.max(vs.Y - hs.Y - 6, 6)))
	else
		hover.Visible = false
	end
end

function ESP.SetEnabled(v)
	ESP.Enabled = v
	ESP.Info = v and "on" or "off"
	if not v and gui then hideAll() end
end

function ESP.Start()
	if gui then return end
	buildGui()
	for _, p in ipairs(Players:GetPlayers()) do if p ~= lp then newEntry(p) end end
	addConn = Players.PlayerAdded:Connect(function(p) if p ~= lp then newEntry(p) end end)
	remConn = Players.PlayerRemoving:Connect(dropEntry)
	conn = RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(update, dt)
		if not ok and ESP.Info ~= "error" then ESP.Info = "error"; warn("[esp] " .. tostring(err)) end
	end)
end

function ESP.Destroy()
	for _, c in ipairs({ conn, addConn, remConn }) do if c then pcall(function() c:Disconnect() end) end end
	conn, addConn, remConn = nil, nil, nil
	if gui then pcall(function() gui:Destroy() end) end
	gui, hover, hoverLabel, radar = nil, nil, nil, nil
	entries = {}
end

return ESP

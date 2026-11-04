-- HUD: small always-on widgets (watermark, vehicle, info, active modules) that you can drag around.
--   HUD.new({ Version = "0.1", GetModules = function() return { "Vehicle Fly", ... } end, GetLocations = function() return Tele.Locations end })
--   hud:SetEdit(true)  -> widgets get an outline and can be dragged (main.lua binds "/" to this); positions are saved.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local Stats = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer

local T = {
	bg = Color3.fromRGB(10, 10, 10), stroke = Color3.fromRGB(44, 44, 44), text = Color3.fromRGB(235, 235, 235),
	sub = Color3.fromRGB(130, 130, 130), accent = Color3.fromRGB(255, 255, 255),
	good = Color3.fromRGB(120, 220, 140), warn = Color3.fromRGB(240, 190, 90), bad = Color3.fromRGB(240, 100, 100),
	font = Enum.Font.GothamMedium, bold = Enum.Font.GothamBold,
}

local SAVE_FILE = "ScrdsxScript_hud.json"
local DEFAULTS = {
	watermark = { x = 0.010, y = 0.015 },
	info = { x = 0.010, y = 0.090 },
	vehicle = { x = 0.010, y = 0.600 },
	modules = { x = 0.880, y = 0.015 },
	farm = { x = 0.760, y = 0.300 },
}

local function new(class, props, children)
	local i = Instance.new(class)
	for k, v in pairs(props or {}) do i[k] = v end
	for _, c in ipairs(children or {}) do c.Parent = i end
	return i
end
local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end
local function tween(o, t, p) TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), p):Play() end

local HUD = {}
HUD.__index = HUD

function HUD.new(opts)
	opts = opts or {}
	local self = setmetatable({ widgets = {}, order = {}, conns = {}, editing = false, scale = 1, opts = opts }, HUD)

	local gui = new("ScreenGui", { Name = tostring(math.random(1e6, 9e6)), ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 990 })
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
	gui.Parent = guiParent()
	self.gui = gui

	-- saved layout
	self.saved = { pos = {}, on = {}, scale = 1 }
	pcall(function()
		if isfile and readfile and isfile(SAVE_FILE) then
			local d = HttpService:JSONDecode(readfile(SAVE_FILE))
			if type(d) == "table" then
				self.saved.pos = type(d.pos) == "table" and d.pos or {}
				self.saved.on = type(d.on) == "table" and d.on or {}
				self.saved.scale = tonumber(d.scale) or 1
			end
		end
	end)
	self.scale = math.clamp(self.saved.scale, 0.6, 1.6)

	-- edit-mode banner
	local banner = new("TextLabel", {
		AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 18), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = T.bg, BackgroundTransparency = .1, BorderSizePixel = 0, Text = "  HUD EDIT MODE   drag the widgets   press / when done  ",
		TextColor3 = T.text, Font = T.bold, TextSize = 13, Visible = false, ZIndex = 50, Parent = gui,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 8) }), new("UIStroke", { Color = T.accent, Thickness = 1 }) })
	self.banner = banner

	-- one widget = a card with an optional title and a list of rows
	local function widget(id, title)
		local f = new("Frame", {
			Name = id, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = T.bg, BackgroundTransparency = .18,
			BorderSizePixel = 0, Active = false, Parent = gui,
		})
		new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = f })
		local st = new("UIStroke", { Color = T.stroke, Thickness = 1, Parent = f })
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7), Parent = f })
		local sc = new("UIScale", { Scale = self.scale, Parent = f })
		new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
		local w = { id = id, frame = f, stroke = st, scale = sc, rows = {}, title = title }
		if title then
			local tl = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, Text = title:upper(),
				TextColor3 = T.sub, Font = T.bold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0, Parent = f })
			w.titleLabel = tl
		end
		-- position (stored as a fraction of the screen so it survives resolution changes)
		local p = self.saved.pos[id] or DEFAULTS[id] or { x = 0.1, y = 0.1 }
		f.Position = UDim2.fromScale(math.clamp(tonumber(p.x) or 0.1, 0, 0.98), math.clamp(tonumber(p.y) or 0.1, 0, 0.98))
		w.enabled = self.saved.on[id] ~= false
		f.Visible = w.enabled
		self.widgets[id] = w
		self.order[#self.order + 1] = id

		-- dragging (only does anything in edit mode: Active is false otherwise, so the game still gets the click)
		local dragging, startMouse, startPos
		table.insert(self.conns, f.InputBegan:Connect(function(i)
			if not self.editing then return end
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				-- InputObject.Position is a Vector3; mixing it with the Vector2 AbsolutePosition throws, so use Vector2s
				dragging, startMouse, startPos = true, Vector2.new(i.Position.X, i.Position.Y), f.AbsolutePosition
			end
		end))
		table.insert(self.conns, UIS.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local screen = gui.AbsoluteSize
				local np = startPos + (Vector2.new(i.Position.X, i.Position.Y) - startMouse)
				local x = math.clamp(np.X / math.max(screen.X, 1), 0, 0.98)
				local y = math.clamp(np.Y / math.max(screen.Y, 1), 0, 0.98)
				f.Position = UDim2.fromScale(x, y)
			end
		end))
		table.insert(self.conns, UIS.InputEnded:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
				dragging = false
				self.saved.pos[id] = { x = f.Position.X.Scale, y = f.Position.Y.Scale }
				self:Save()
			end
		end))
		return w
	end

	-- rows: { key, value, color } ; creates / reuses TextLabels
	local function setRows(w, list)
		for i, r in ipairs(list) do
			local row = w.rows[i]
			if not row then
				local line = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = w.frame })
				new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center, Parent = line })
				local k = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, TextColor3 = T.sub,
					Font = T.font, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = line })
				local v = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, TextColor3 = T.text,
					Font = T.bold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Parent = line })
				row = { line = line, k = k, v = v }
				w.rows[i] = row
			end
			local ts = r.ts or 12 -- text size (the speed readout is big)
			row.line.Size = UDim2.fromOffset(0, ts + 2)
			row.k.Size = UDim2.fromOffset(0, ts + 2); row.v.Size = UDim2.fromOffset(0, ts + 2); row.v.TextSize = ts
			local key = r[1] or ""
			if row.k.Text ~= key then row.k.Text = key end
			row.k.Visible = key ~= ""
			local val = tostring(r[2] or "")
			if row.v.Text ~= val then row.v.Text = val end
			row.v.TextColor3 = r[3] or T.text
			row.line.Visible = true
		end
		for i = #list + 1, #w.rows do w.rows[i].line.Visible = false end
	end

	local wm = widget("watermark", nil)
	local info = widget("info", "Player")
	local veh = widget("vehicle", "Vehicle")
	local mods = widget("modules", "Active")
	local farm = widget("farm", "AutoFarm")

	-- AutoFarm mini-map in the style of the game's own map: you in the middle, shops / dealers as round icons, the route as a line,
	-- and an info bar underneath (green: earned, blue: car / autopilot state)
	local MAP_W, MAP_H = 200, 140
	local PX, PY = MAP_W / 2, MAP_H * 0.62 -- where you are on the map
	local mapFrame = new("Frame", { Size = UDim2.fromOffset(MAP_W, MAP_H), BackgroundColor3 = Color3.fromRGB(34, 36, 40), BorderSizePixel = 0,
		ClipsDescendants = true, LayoutOrder = 100, Parent = farm.frame })
	new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = mapFrame })
	new("UIStroke", { Color = T.stroke, Thickness = 1, Parent = mapFrame })
	for _, rr in ipairs({ 0.33, 0.66, 1 }) do
		local ring = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(PX, PY), Size = UDim2.fromOffset(MAP_H * rr * 1.25, MAP_H * rr * 1.25),
			BackgroundTransparency = 1, BorderSizePixel = 0, Parent = mapFrame })
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
		new("UIStroke", { Color = Color3.fromRGB(70, 74, 82), Thickness = 1, Transparency = 0.55, Parent = ring })
	end
	local segs = {}
	for i = 1, 60 do
		segs[i] = new("Frame", { AnchorPoint = Vector2.new(.5, .5), BackgroundColor3 = Color3.fromRGB(110, 190, 255), BorderSizePixel = 0,
			Size = UDim2.fromOffset(10, 3), Visible = false, ZIndex = 2, Parent = mapFrame })
	end
	local pois = {}
	for i = 1, 24 do
		local d = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = T.good, BorderSizePixel = 0,
			Visible = false, ZIndex = 4, Parent = mapFrame })
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = d })
		new("UIStroke", { Color = Color3.fromRGB(20, 20, 22), Thickness = 2, Parent = d })
		local t = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "", TextColor3 = Color3.new(1, 1, 1),
			Font = T.bold, TextSize = 11, ZIndex = 5, Parent = d })
		pois[i] = { f = d, t = t }
	end
	local me = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromOffset(PX, PY), Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Color3.fromRGB(24, 26, 30), BorderSizePixel = 0, ZIndex = 6, Parent = mapFrame })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = me })
	new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "^", TextColor3 = Color3.new(1, 1, 1), Font = T.bold, TextSize = 16, ZIndex = 7, Parent = me })
	local destRing = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, BorderSizePixel = 0,
		Visible = false, ZIndex = 5, Parent = mapFrame })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = destRing })
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = destRing })
	local bar = new("Frame", { Size = UDim2.fromOffset(MAP_W, 22), BackgroundColor3 = Color3.fromRGB(20, 62, 92), BorderSizePixel = 0, LayoutOrder = 101, Parent = farm.frame })
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = bar })
	local barGreen = new("Frame", { Size = UDim2.new(0.62, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(40, 170, 90), BorderSizePixel = 0, Parent = bar })
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = barGreen })
	local barEarn = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "+", TextColor3 = Color3.new(1, 1, 1), Font = T.bold, TextSize = 12,
		ZIndex = 2, Parent = barGreen })
	local barCar = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0.62, 0, 0, 0), Size = UDim2.new(0.38, 0, 1, 0), Text = "IDLE",
		TextColor3 = Color3.new(1, 1, 1), Font = T.bold, TextSize = 11, ZIndex = 2, Parent = bar })

	local function drawMap(fd, pos, camLook)
		local f = Vector3.new(camLook.X, 0, camLook.Z)
		f = f.Magnitude > 0.1 and f.Unit or Vector3.new(0, 0, -1)
		local r = Vector3.new(-f.Z, 0, f.X)
		local st = fd.drive
		local R = 260
		if st and st.wps and #st.wps > 0 then
			R = 90
			for i = st.idx, math.min(#st.wps, st.idx + 10) do
				local d = st.wps[i] - pos
				R = math.max(R, math.sqrt(d.X * d.X + d.Z * d.Z) * 1.15)
			end
			R = math.min(R, 600)
		end
		local sc = (MAP_H * 0.55) / R
		local function toMap(p)
			local d = p - pos
			return Vector2.new(PX + d:Dot(r) * sc, PY - d:Dot(f) * sc)
		end
		local n = 0
		for _, p in ipairs(fd.pois or {}) do
			n = n + 1
			local slot = pois[n]
			if not slot then break end
			local m = toMap(p.pos)
			local inside = m.X > 8 and m.X < MAP_W - 8 and m.Y > 8 and m.Y < MAP_H - 8
			slot.f.Visible = true
			slot.f.Position = UDim2.fromOffset(math.clamp(m.X, 9, MAP_W - 9), math.clamp(m.Y, 9, MAP_H - 9))
			slot.f.BackgroundColor3 = p.dim and Color3.fromRGB(95, 95, 100) or p.color
			slot.f.BackgroundTransparency = inside and 0 or 0.45
			slot.f.Size = UDim2.fromOffset(inside and 18 or 12, inside and 18 or 12)
			slot.t.Text = inside and p.tag or ""
		end
		for i = n + 1, #pois do pois[i].f.Visible = false end
		local k = 0
		if st and st.wps and #st.wps > 0 then
			local prev = Vector2.new(PX, PY)
			for i = st.idx, #st.wps do
				if k >= #segs then break end
				local cur = toMap(st.wps[i])
				local dv = cur - prev
				local len = dv.Magnitude
				if len > 1 then
					k = k + 1
					local sgm = segs[k]
					sgm.Visible = true
					sgm.Size = UDim2.fromOffset(len, 3)
					sgm.Position = UDim2.fromOffset((prev.X + cur.X) / 2, (prev.Y + cur.Y) / 2)
					sgm.Rotation = math.deg(math.atan2(dv.Y, dv.X))
				end
				prev = cur
				if cur.X < -300 or cur.X > MAP_W + 300 or cur.Y < -300 or cur.Y > MAP_H + 300 then break end
			end
			local dp = toMap(st.wps[#st.wps])
			destRing.Position = UDim2.fromOffset(math.clamp(dp.X, 13, MAP_W - 13), math.clamp(dp.Y, 13, MAP_H - 13))
			destRing.Visible = true
		else
			destRing.Visible = false
		end
		for i = k + 1, #segs do segs[i].Visible = false end
	end

	self.lastFps = 60

	-- data ----------------------------------------------------------------------------------------------------
	local function ping()
		local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
		return ok and math.floor(v + .5) or nil
	end
	local function myCar()
		local v = workspace:FindFirstChild("Vehicles")
		local car = v and v:FindFirstChild(lp.Name)
		return car, car and car:FindFirstChild("DriveSeat")
	end
	local function hpColor(f) return f > .6 and T.good or (f > .3 and T.warn or T.bad) end

	local function refresh()
		local char = lp.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")

		if wm.enabled then
			local p = ping()
			setRows(wm, { { (opts.Title or "Scrdsx Solutions"), ("v%s   %d fps%s   %s"):format(tostring(opts.Version or "?"), math.floor(self.lastFps + .5),
				p and ("   " .. p .. " ms") or "", os.date("%H:%M")), nil } })
		end

		if info.enabled then
			local rows = {}
			if hum then
				local f = hum.MaxHealth > 0 and hum.Health / hum.MaxHealth or 0
				rows[#rows + 1] = { "Health", ("%d / %d"):format(math.floor(hum.Health + .5), math.floor(hum.MaxHealth + .5)), hpColor(f) }
			end
			if hrp then
				local pos = hrp.Position
				rows[#rows + 1] = { "Position", ("%d, %d, %d"):format(pos.X, pos.Y, pos.Z) }
				local best, bd
				for _, loc in ipairs(opts.GetLocations and opts.GetLocations() or {}) do
					local d = (loc.pos - pos).Magnitude
					if not bd or d < bd then best, bd = loc, d end
				end
				if best then rows[#rows + 1] = { "Nearest", ("%s  %d st"):format(best.name, bd) } end
				local np, nd
				for _, pl in ipairs(Players:GetPlayers()) do
					local oc = pl ~= lp and pl.Character
					local oh = oc and oc:FindFirstChild("HumanoidRootPart")
					if oh then
						local d = (oh.Position - pos).Magnitude
						if not nd or d < nd then np, nd = pl, d end
					end
				end
				rows[#rows + 1] = { "Players", ("%d%s"):format(#Players:GetPlayers(), np and ("   closest " .. np.Name .. " " .. math.floor(nd) .. " st") or "") }
			end
			setRows(info, rows)
		end

		if veh.enabled then
			local car, seat = myCar()
			if not car or not seat then
				setRows(veh, { { "", "no car spawned", T.sub } })
			else
				local kmh = seat.AssemblyLinearVelocity.Magnitude * 1.008
				local fuel = car:GetAttribute("currentFuel")
				local hp = car:GetAttribute("currentHealth")
				local flats = car:GetAttribute("flatTires")
				local lvl = ("%s / %s / %s"):format(tostring(car:GetAttribute("engineLevel") or 0), tostring(car:GetAttribute("brakesLevel") or 0), tostring(car:GetAttribute("armorLevel") or 0))
				local seated = hum and hum.SeatPart == seat
				local rows = { { "", ("%d km/h"):format(kmh), T.text, ts = 22 } }
				rows[#rows + 1] = { "Fuel", type(fuel) == "number" and ("%.1f"):format(fuel) or "-" }
				rows[#rows + 1] = { "Car health", type(hp) == "number" and ("%d"):format(hp) or "-" }
				rows[#rows + 1] = { "Tires", (type(flats) == "string" and flats ~= "") and ("flat: " .. flats) or "ok", (type(flats) == "string" and flats ~= "") and T.bad or T.good }
				rows[#rows + 1] = { "Eng / Brk / Arm", lvl }
				rows[#rows + 1] = { "Seat", seated and "in car" or "out", seated and T.good or T.sub }
				setRows(veh, rows)
			end
		end

		if farm.enabled then
			local fd = opts.GetFarm and opts.GetFarm() or {}
			local st = fd.drive
			local cam = workspace.CurrentCamera
			local camLook = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
			if st and st.fwd then camLook = st.fwd end
			if hrp then pcall(drawMap, fd, hrp.Position, camLook) end
			local earned = fd.earned
			barEarn.Text = earned and ("+" .. tostring(math.floor(earned)) .. " EUR") or "AutoFarm"
			barCar.Text = (st and (tostring(math.floor((st.spd or 0) * 1.008)) .. " km/h")) or (fd.busy and "WORKING" or "IDLE")
			local rows = { { "", fd.info or "idle", T.text } }
			if fd.stats then rows[#rows + 1] = { "Done", fd.stats, T.sub } end
			if st and st.wps and #st.wps > 0 then
				rows[#rows + 1] = { "To", tostring(st.name), T.text }
				rows[#rows + 1] = { "Left", ("%d st   (%d / %d)"):format(st.remain or 0, st.idx or 0, #st.wps), T.text }
				local err = math.abs(st.err or 0)
				rows[#rows + 1] = { "Steering", err < 0.15 and "straight" or (err < 0.6 and "turning" or "sharp turn"), err < 0.6 and T.good or T.warn }
			end
			setRows(farm, rows)
		end

		if mods.enabled then
			local list = opts.GetModules and opts.GetModules() or {}
			table.sort(list, function(a, b) return #a > #b end)
			local rows = {}
			for _, n in ipairs(list) do rows[#rows + 1] = { "", n, T.text } end
			if #rows == 0 then rows[1] = { "", "none on", T.sub } end
			setRows(mods, rows)
		end
	end

	local acc = 0
	table.insert(self.conns, RunService.RenderStepped:Connect(function(dt)
		if dt > 0 then self.lastFps = self.lastFps + (1 / dt - self.lastFps) * 0.08 end
		acc = acc + dt
		if acc >= 0.15 then acc = 0; pcall(refresh) end
	end))
	pcall(refresh)
	return self
end

function HUD:Save()
	local d = { pos = self.saved.pos, on = self.saved.on, scale = self.scale }
	pcall(function() if writefile then writefile(SAVE_FILE, HttpService:JSONEncode(d)) end end)
end

-- positions of all widgets as fractions of the screen (for configs)
function HUD:GetLayout()
	local out = {}
	for id, w in pairs(self.widgets) do
		out[id] = { x = math.floor(w.frame.Position.X.Scale * 10000) / 10000, y = math.floor(w.frame.Position.Y.Scale * 10000) / 10000 }
	end
	return out
end

function HUD:SetLayout(map)
	if type(map) ~= "table" then return end
	for id, p in pairs(map) do
		local w = self.widgets[id]
		if w and type(p) == "table" and tonumber(p.x) and tonumber(p.y) then
			w.frame.Position = UDim2.fromScale(math.clamp(p.x, 0, 0.98), math.clamp(p.y, 0, 0.98))
			self.saved.pos[id] = { x = p.x, y = p.y }
		end
	end
	self:Save()
end

function HUD:SetWidget(id, on)
	local w = self.widgets[id]
	if not w then return end
	w.enabled = on
	w.frame.Visible = on
	self.saved.on[id] = on
	self:Save()
end

function HUD:IsOn(id) return self.widgets[id] and self.widgets[id].enabled end

function HUD:SetScale(s)
	self.scale = s
	for _, w in pairs(self.widgets) do w.scale.Scale = s end
	self:Save()
end

function HUD:ResetPositions()
	for id, w in pairs(self.widgets) do
		local p = DEFAULTS[id] or { x = 0.1, y = 0.1 }
		w.frame.Position = UDim2.fromScale(p.x, p.y)
	end
	self.saved.pos = {}
	self:Save()
end

function HUD:SetEdit(v)
	if v == self.editing then return end
	self.editing = v
	self.banner.Visible = v
	for _, w in pairs(self.widgets) do
		w.frame.Active = v
		w.frame.Visible = w.enabled
		tween(w.stroke, .2, { Color = v and T.accent or T.stroke })
		tween(w.frame, .2, { BackgroundTransparency = v and .05 or .18 })
	end
	if v then
		-- swallow "/" so it does not open the chat while you are moving things
		pcall(function()
			CAS:BindActionAtPriority("ScrdsxHudSlash", function() return Enum.ContextActionResult.Sink end, false, 3000, Enum.KeyCode.Slash)
		end)
	else
		pcall(function() CAS:UnbindAction("ScrdsxHudSlash") end)
		self:Save()
	end
	-- if "/" still opened the chat bar, let go of it again
	task.defer(function()
		pcall(function()
			local tcs = game:GetService("TextChatService")
			local bar = tcs:FindFirstChildOfClass("ChatInputBarConfiguration")
			if bar and bar.TextBox then bar.TextBox:ReleaseFocus() end
		end)
	end)
	if self.EditChanged then task.defer(self.EditChanged, v) end
end

function HUD:ToggleEdit() self:SetEdit(not self.editing) end

function HUD:Destroy()
	pcall(function() CAS:UnbindAction("ScrdsxHudSlash") end)
	for _, c in ipairs(self.conns) do pcall(function() c:Disconnect() end) end
	self.gui:Destroy()
end

return HUD

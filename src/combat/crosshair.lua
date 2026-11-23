-- Custom crosshair: many styles, colour, size, gap, thickness, outline, centre dot, spin, movement spread, turns red over a player.
-- Built from plain Frames (no Drawing library), drawn over the game; can follow the mouse cursor or stay in the screen centre.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local Crosshair = {
	Enabled = false, Style = "Cross", Size = 10, Gap = 4, Thickness = 2, Alpha = 1,
	Color = Color3.fromRGB(255, 255, 255), TargetColor = Color3.fromRGB(255, 70, 70), Outline = true, CenterDot = false,
	Spin = false, SpinSpeed = 90, Dynamic = false, Rainbow = false, ColorOnTarget = true, FollowMouse = false, HideCursor = false,
	Info = "off",
}
Crosshair.Styles = { "Cross", "Dot", "Ring", "Dot + Ring", "T", "X", "Chevron", "Square", "Star of David", "Israel flag", "Diamond", "Triangle", "Pentagram" }

local gui, holder, bar
local parts = {}
local conn
local oldIcon
local spreadNow = 0
local BIND = "ScrdsxCrosshair"

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end

local function clear()
	for _, p in ipairs(parts) do pcall(function() p.f:Destroy() end) end
	parts = {}
end

-- one bar / dot; ox, oy are the centre offset (before spread), dx, dy the direction it moves with the spread
local function piece(w, h, ox, oy, dx, dy, rot, round, color)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(.5, .5)
	f.BackgroundColor3 = color or Crosshair.Color
	f.BackgroundTransparency = 1 - Crosshair.Alpha
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = rot or 0
	f.Parent = holder
	if round then Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0) end
	if Crosshair.Outline then
		local s = Instance.new("UIStroke")
		s.Color = Color3.new(0, 0, 0); s.Thickness = 1; s.Transparency = 1 - Crosshair.Alpha * 0.9
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
	end
	local p = { f = f, ox = ox, oy = oy, dx = dx, dy = dy, fill = true, fixed = color ~= nil }
	parts[#parts + 1] = p
	return p
end

local function ring(diam)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(.5, .5)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(diam, diam)
	f.Parent = holder
	Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
	local s = Instance.new("UIStroke")
	s.Color = Crosshair.Color; s.Thickness = Crosshair.Thickness; s.Transparency = 1 - Crosshair.Alpha
	s.Parent = f
	local p = { f = f, ox = 0, oy = 0, dx = 0, dy = 0, stroke = s, ring = true, diam = diam }
	parts[#parts + 1] = p
	if Crosshair.Outline then
		-- a second, slightly larger dark ring behind gives the outline
		local o = Instance.new("Frame")
		o.AnchorPoint = Vector2.new(.5, .5); o.BackgroundTransparency = 1; o.BorderSizePixel = 0
		o.Size = UDim2.fromOffset(diam + 2, diam + 2); o.ZIndex = 0; o.Parent = holder
		Instance.new("UICorner", o).CornerRadius = UDim.new(1, 0)
		local os_ = Instance.new("UIStroke"); os_.Color = Color3.new(0, 0, 0); os_.Thickness = Crosshair.Thickness + 2; os_.Transparency = 1 - Crosshair.Alpha * 0.6; os_.Parent = o
		parts[#parts + 1] = { f = o, ox = 0, oy = 0, dx = 0, dy = 0, ringOutline = true, diam = diam + 2 }
	end
	return p
end

-- a straight line between two points (relative to the centre), drawn as a rotated bar; it spreads outwards with the movement spread
local function seg(x1, y1, x2, y2, thick, color)
	local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
	local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
	local m = math.max(math.sqrt(mx * mx + my * my), 1e-3)
	return piece(len + thick * 0.6, thick, mx, my, mx / m, my / m, math.deg(math.atan2(y2 - y1, x2 - x1)), false, color)
end
local function polar(r, deg) local a = math.rad(deg); return r * math.cos(a), r * math.sin(a) end
-- hexagram = two triangles; pentagram = every second point of five
local function hexagram(r, thick, color)
	local v = {}
	for i = 0, 5 do local x, y = polar(r, -90 + i * 60); v[i] = { x, y } end
	for i = 0, 5 do
		local a, b = v[i], v[(i + 2) % 6]
		seg(a[1], a[2], b[1], b[2], thick, color)
	end
end

function Crosshair.Rebuild()
	if not holder then return end
	clear()
	local s, g, t = Crosshair.Size, Crosshair.Gap, Crosshair.Thickness
	local st = Crosshair.Style
	if st == "Cross" or st == "T" then
		piece(t, s, 0, -(g + s / 2), 0, -1)       -- up
		piece(t, s, 0, g + s / 2, 0, 1)           -- down
		piece(s, t, -(g + s / 2), 0, -1, 0)       -- left
		piece(s, t, g + s / 2, 0, 1, 0)           -- right
		if st == "T" then local top = table.remove(parts, 1); top.f:Destroy() end
	elseif st == "X" then
		local d = (g + s / 2) * 0.7071
		piece(t, s, -d, -d, -.7071, -.7071, 45)
		piece(t, s, d, -d, .7071, -.7071, -45)
		piece(t, s, -d, d, -.7071, .7071, -45)
		piece(t, s, d, d, .7071, .7071, 45)
	elseif st == "Chevron" then
		piece(t, s, -s * 0.28, g + s * 0.1, -.5, .5, 55)
		piece(t, s, s * 0.28, g + s * 0.1, .5, .5, -55)
	elseif st == "Dot" then
		piece(math.max(t + 1, 3), math.max(t + 1, 3), 0, 0, 0, 0, 0, true)
	elseif st == "Ring" then
		ring(s * 2 + g)
	elseif st == "Dot + Ring" then
		ring(s * 2 + g)
		piece(3, 3, 0, 0, 0, 0, 0, true)
	elseif st == "Square" then
		local d = s + g
		piece(d * 2, t, 0, -d, 0, -1); piece(d * 2, t, 0, d, 0, 1)
		piece(t, d * 2, -d, 0, -1, 0); piece(t, d * 2, d, 0, 1, 0)
	elseif st == "Star of David" then
		hexagram(s * 1.2 + g, t)
	elseif st == "Israel flag" then
		-- white flag, two blue stripes, blue star (colours stay fixed)
		local W = s * 2.6 + g
		local H = W * 0.7273
		local BLUE = Color3.fromRGB(0, 56, 184)
		piece(W, H, 0, 0, 0, 0, 0, false, Color3.fromRGB(255, 255, 255))
		piece(W, H * 0.11, 0, -H * 0.31, 0, 0, 0, false, BLUE)
		piece(W, H * 0.11, 0, H * 0.31, 0, 0, 0, false, BLUE)
		hexagram(H * 0.2, 1, BLUE)
	elseif st == "Diamond" then
		local r = s * 1.1 + g
		seg(0, -r, r, 0, t); seg(r, 0, 0, r, t); seg(0, r, -r, 0, t); seg(-r, 0, 0, -r, t)
	elseif st == "Triangle" then
		local r = s * 1.2 + g
		local v = {}
		for i = 0, 2 do local x, y = polar(r, -90 + i * 120); v[i] = { x, y } end
		for i = 0, 2 do local a, b = v[i], v[(i + 1) % 3]; seg(a[1], a[2], b[1], b[2], t) end
	elseif st == "Pentagram" then
		local r = s * 1.2 + g
		local v = {}
		for i = 0, 4 do local x, y = polar(r, -90 + i * 72); v[i] = { x, y } end
		for i = 0, 4 do local a, b = v[i], v[(i + 2) % 5]; seg(a[1], a[2], b[1], b[2], t) end
	end
	if Crosshair.CenterDot and st ~= "Dot" and st ~= "Dot + Ring" then piece(2, 2, 0, 0, 0, 0, 0, true) end
end

local function overEnemy()
	local mouse = lp:GetMouse()
	local tgt = mouse and mouse.Target
	if not tgt then return false end
	local model = tgt:FindFirstAncestorOfClass("Model")
	local plr = model and Players:GetPlayerFromCharacter(model)
	if not plr and tgt.Parent then
		local m2 = tgt.Parent:FindFirstAncestorOfClass("Model")
		plr = m2 and Players:GetPlayerFromCharacter(m2)
	end
	return plr ~= nil and plr ~= lp
end

local function step(dt)
	if not holder then return end
	local cam = workspace.CurrentCamera
	local vs = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local c
	if Crosshair.FollowMouse and UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter then c = UIS:GetMouseLocation() else c = Vector2.new(vs.X / 2, vs.Y / 2) end
	holder.Position = UDim2.fromOffset(c.X, c.Y)
	if Crosshair.Spin then holder.Rotation = (holder.Rotation + Crosshair.SpinSpeed * dt) % 360 else holder.Rotation = 0 end
	-- colour: rainbow, red over a player, or the picked colour
	local col = Crosshair.Color
	if Crosshair.Rainbow then col = Color3.fromHSV((os.clock() * 0.25) % 1, 0.85, 1)
	elseif Crosshair.ColorOnTarget and overEnemy() then col = Crosshair.TargetColor end
	-- spread: grows while you move, eases back
	local want = 0
	if Crosshair.Dynamic then
		local ch = lp.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp then want = math.clamp(hrp.AssemblyLinearVelocity.Magnitude / 16, 0, 2.5) * 4 end
	end
	spreadNow = spreadNow + (want - spreadNow) * math.clamp(dt * 10, 0, 1)
	for _, p in ipairs(parts) do
		if p.ring or p.ringOutline then
			local d = p.diam + spreadNow * 2
			p.f.Size = UDim2.fromOffset(d, d)
			if p.stroke then p.stroke.Color = col end
		else
			p.f.Position = UDim2.new(.5, p.ox + p.dx * spreadNow, .5, p.oy + p.dy * spreadNow)
			if not p.fixed then p.f.BackgroundColor3 = col end
		end
	end
end

function Crosshair.SetEnabled(v)
	Crosshair.Enabled = v
	Crosshair.Info = v and Crosshair.Style or "off"
	if holder then holder.Visible = v end
	if v then
		Crosshair.Rebuild()
		if Crosshair.HideCursor then pcall(function() oldIcon = UIS.MouseIconEnabled; UIS.MouseIconEnabled = false end) end
	else
		pcall(function() if oldIcon ~= nil then UIS.MouseIconEnabled = oldIcon; oldIcon = nil end end)
	end
	if Crosshair.Changed then Crosshair.Changed() end
end

function Crosshair.SetHideCursor(v)
	Crosshair.HideCursor = v
	if Crosshair.Enabled then
		pcall(function()
			if v then oldIcon = oldIcon == nil and UIS.MouseIconEnabled or oldIcon; UIS.MouseIconEnabled = false
			elseif oldIcon ~= nil then UIS.MouseIconEnabled = oldIcon; oldIcon = nil end
		end)
	end
end

function Crosshair.Start()
	if gui then return end
	gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 4
	gui.Parent = guiParent()
	holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(.5, .5); holder.Size = UDim2.fromOffset(0, 0); holder.BackgroundTransparency = 1; holder.BorderSizePixel = 0
	holder.Visible = false; holder.Parent = gui
	pcall(function()
		RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 2, function(dt)
			local ok, err = pcall(step, dt)
			if not ok and Crosshair.Info ~= "error" then Crosshair.Info = "error"; warn("[crosshair] " .. tostring(err)) end
		end)
	end)
end

function Crosshair.Destroy()
	pcall(function() RunService:UnbindFromRenderStep(BIND) end)
	pcall(function() if oldIcon ~= nil then UIS.MouseIconEnabled = oldIcon end end)
	if gui then pcall(function() gui:Destroy() end) end
	gui, holder, parts = nil, nil, {}
	Crosshair.Enabled = false
end

return Crosshair

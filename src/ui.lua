-- Scrdsx UI library v4. Same API as v3 (tabs, modules, toggles, sliders, choices, keybinds, colours, configs), new look and layout:
--   sidebar  = brand, search, grouped tabs (active tab gets an accent bar), you
--   header   = page title + "n modules, n on", live fps / ping, close
--   content  = modules as cards in two columns; the settings of a module open INSIDE its card (no side drawer)
--   HUD      = module list (top right, like a client arraylist) + toasts (bottom right)
-- Nothing in here runs per frame: the only loop is the 1 s stats refresh. Plain Frames only (a CanvasGroup under UIScale makes text soft).
-- Every themed colour is a binding (win.binds), so a theme change recolours everything at once.
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Stats = game:GetService("Stats")
local Logo = __import("logo")
local Icons = __import("icons")
local Sfx = __import("sfx")

local function pickFont(n, fb) local ok, f = pcall(function() return Enum.Font[n] end); return (ok and f) or fb end
local T = {
	bg = Color3.fromRGB(12, 12, 15),
	side = Color3.fromRGB(15, 15, 19),
	panel = Color3.fromRGB(19, 19, 24),
	elem = Color3.fromRGB(27, 27, 33),
	hover = Color3.fromRGB(34, 34, 41),
	stroke = Color3.fromRGB(33, 33, 41),
	text = Color3.fromRGB(236, 237, 242),
	sub = Color3.fromRGB(138, 141, 153),
	dim = Color3.fromRGB(92, 95, 107),
	accent = Color3.fromRGB(124, 131, 255),
	accentDim = Color3.fromRGB(30, 31, 52),
	off = Color3.fromRGB(52, 52, 62),
	chip = Color3.fromRGB(176, 181, 255),
	gradA = Color3.fromRGB(99, 105, 204),
	gradB = Color3.fromRGB(157, 162, 255),
	strokeOn = Color3.fromRGB(68, 72, 135),
	font = pickFont("BuilderSansMedium", Enum.Font.Gotham),
	bold = pickFont("BuilderSansBold", Enum.Font.GothamBold),
	semi = pickFont("BuilderSansBold", Enum.Font.GothamBold),
}

local W, H = 980, 640
local SIDE_W, TOP_H = 212, 66
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

local function tween(o, t, p, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), p)
	tw:Play()
	return tw
end

local function new(class, props, children)
	local i = Instance.new(class)
	for k, v in pairs(props or {}) do i[k] = v end
	for _, c in ipairs(children or {}) do c.Parent = i end
	return i
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function pad(l, r, t, b) return new("UIPadding", { PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or l or 0), PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or t or 0) }) end

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local UI = {}
UI.__index = UI

-- bind(win, instance, "Property", "tokenName" | function() return value end): set now, and again whenever the theme changes
local function bind(win, inst, prop, f)
	local fn = type(f) == "string" and function() return T[f] end or f
	inst[prop] = fn()
	win.binds[#win.binds + 1] = { inst, prop, fn }
	return inst
end

local function mkStroke(win, key, transparency)
	local s = new("UIStroke", { Thickness = 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	bind(win, s, "Color", key or "stroke")
	return s
end

local function text(win, str, size, key, font, align)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = str, TextSize = size or 13, Font = font or T.font, TextXAlignment = align or Enum.TextXAlignment.Left,
		TextWrapped = true, TextTruncate = Enum.TextTruncate.None, RichText = false,
	})
	bind(win, l, "TextColor3", key or "text")
	return l
end

-- small switch: off = dark track + grey knob, on = accent track + white knob
local function makeSwitch(win, parent, anchor, pos, getState)
	local sw = new("Frame", { AnchorPoint = anchor, Position = pos, Size = UDim2.fromOffset(34, 18), BorderSizePixel = 0, Parent = parent }, { corner(9) })
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 3, .5, 0), Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0, Parent = sw }, { corner(6) })
	local function trackColor() return getState() and T.accent or T.off end
	local function knobColor() return getState() and WHITE or Color3.fromRGB(150, 152, 162) end
	bind(win, sw, "BackgroundColor3", trackColor)
	bind(win, knob, "BackgroundColor3", knobColor)
	local function set(v, animate)
		local p = UDim2.new(0, v and 19 or 3, .5, 0)
		if animate then
			tween(sw, .16, { BackgroundColor3 = trackColor() }); tween(knob, .18, { BackgroundColor3 = knobColor(), Position = p })
		else
			sw.BackgroundColor3 = trackColor(); knob.BackgroundColor3 = knobColor(); knob.Position = p
		end
	end
	return sw, set
end

function UI.new(opts)
	opts = opts or {}
	local self = setmetatable({
		tabs = {}, rows = {}, sections = {}, conns = {}, flags = {}, binds = {}, modules = {}, active = nil, visible = true,
		baseScale = 1, autoScale = 1, navOrder = 0, blurSize = 0, arrayOn = true,
	}, UI)

	local gui = new("ScreenGui", {
		Name = tostring(math.random(1e6, 9e6)), ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
	})
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
	gui.Parent = guiParent()
	self.gui = gui

	local holder = new("Frame", { Name = "Root", Size = UDim2.fromOffset(W, H), AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = gui })
	-- soft drop shadow: three stacked rounded frames, very transparent (no image, so nothing can render as a box)
	for i = 3, 1, -1 do
		new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, 4), Size = UDim2.new(1, i * 10, 1, i * 10), BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.82 + i * 0.05, BorderSizePixel = 0, ZIndex = 0, Parent = holder }, { corner(14 + i * 5) })
	end
	local root = new("Frame", { Name = "Window", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ClipsDescendants = true, Parent = holder }, { corner(14) })
	bind(self, root, "BackgroundColor3", "bg")
	mkStroke(self, "stroke", 0).Parent = root
	self.root = holder
	self.window = root

	pcall(function()
		local b = Instance.new("BlurEffect")
		b.Name = "ScrdsxGlass"; b.Size = 0; b.Parent = Lighting
		self.blur = b
	end)
	self.scale = new("UIScale", { Scale = .95, Parent = holder })
	do
		local cam = workspace.CurrentCamera
		local vh = cam and cam.ViewportSize.Y or 800
		self.autoScale = math.clamp(vh / 860, 0.85, 1.35)
		self.baseScale = self.autoScale
	end

	-- SIDEBAR ---------------------------------------------------------------------------------------------------------------
	local side = new("Frame", { Name = "Side", Size = UDim2.new(0, SIDE_W, 1, 0), BorderSizePixel = 0, Parent = root }, { corner(14) })
	bind(self, side, "BackgroundColor3", "side")
	-- square off the right edge of the rounded sidebar
	local sideFill = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 16, 1, 0), BorderSizePixel = 0, Parent = side })
	bind(self, sideFill, "BackgroundColor3", "side")
	local vline = new("Frame", { Position = UDim2.fromOffset(SIDE_W, 0), Size = UDim2.new(0, 1, 1, 0), BorderSizePixel = 0, Parent = root })
	bind(self, vline, "BackgroundColor3", "stroke")

	local brand = new("Frame", { Size = UDim2.new(1, 0, 0, TOP_H), BackgroundTransparency = 1, Parent = side })
	Logo.Make(brand, 30, UDim2.fromOffset(18, 18))
	local title = text(self, opts.Title or "Window", 16, "text", T.bold); title.Position = UDim2.fromOffset(58, 16); title.Size = UDim2.new(1, -64, 0, 18); title.TextWrapped = false; title.Parent = brand
	local sub = text(self, opts.Subtitle or "", 11, "sub"); sub.Position = UDim2.fromOffset(58, 35); sub.Size = UDim2.new(1, -64, 0, 14); sub.TextWrapped = false; sub.TextTruncate = Enum.TextTruncate.AtEnd; sub.Parent = brand

	-- search (sidebar, under the brand)
	local sb = new("Frame", { Position = UDim2.fromOffset(14, TOP_H + 2), Size = UDim2.new(1, -28, 0, 32), BorderSizePixel = 0, Parent = side }, { corner(8) })
	bind(self, sb, "BackgroundColor3", "elem")
	local sbStroke = mkStroke(self, "stroke", 0); sbStroke.Parent = sb
	local glass = text(self, "⌕", 15, "dim", T.bold, Enum.TextXAlignment.Center); glass.Position = UDim2.fromOffset(6, 0); glass.Size = UDim2.fromOffset(22, 32); glass.TextWrapped = false; glass.Parent = sb
	local box = new("TextBox", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -62, 1, 0), Position = UDim2.fromOffset(30, 0), Text = "", PlaceholderText = "Search", ClearTextOnFocus = false,
		Font = T.font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = sb,
	})
	bind(self, box, "TextColor3", "text"); bind(self, box, "PlaceholderColor3", "dim")
	local hintBg = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -7, .5, 0), Size = UDim2.fromOffset(20, 18), BorderSizePixel = 0, Parent = sb }, { corner(5) })
	bind(self, hintBg, "BackgroundColor3", "hover")
	local hint = text(self, "/", 11, "sub", T.bold, Enum.TextXAlignment.Center); hint.Size = UDim2.fromScale(1, 1); hint.TextWrapped = false; hint.Parent = hintBg
	self.searchBox = box
	box.Focused:Connect(function() tween(sbStroke, .15, { Color = T.strokeOn }); tween(hintBg, .15, { BackgroundTransparency = 1 }); tween(hint, .15, { TextTransparency = 1 }) end)
	box.FocusLost:Connect(function()
		tween(sbStroke, .15, { Color = T.stroke })
		if box.Text == "" then tween(hintBg, .15, { BackgroundTransparency = 0 }); tween(hint, .15, { TextTransparency = 0 }) end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function() self:_search(box.Text) end)

	local NAV_Y = TOP_H + 44
	local nav = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, NAV_Y), Size = UDim2.new(1, 0, 1, -NAV_Y - 62), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y, Parent = side,
	})
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav })
	pad(12, 12, 0, 8).Parent = nav
	self.nav = nav

	local lp = Players.LocalPlayer
	local meLine = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -60), Size = UDim2.new(1, -28, 0, 1), BorderSizePixel = 0, Parent = side })
	bind(self, meLine, "BackgroundColor3", "stroke")
	local me = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -12), Size = UDim2.new(1, -28, 0, 38), BackgroundTransparency = 1, Parent = side })
	local av = new("ImageLabel", { Position = UDim2.fromOffset(0, 3), Size = UDim2.fromOffset(32, 32), BorderSizePixel = 0, Image = "", Parent = me }, { corner(16) })
	bind(self, av, "BackgroundColor3", "elem")
	local avRing = mkStroke(self, "strokeOn", 0); avRing.Parent = av
	task.spawn(function() pcall(function() av.Image = Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) end) end)
	local pn = text(self, lp.DisplayName, 13, "text", T.bold); pn.Position = UDim2.fromOffset(42, 3); pn.Size = UDim2.new(1, -44, 0, 16); pn.TextWrapped = false; pn.TextTruncate = Enum.TextTruncate.AtEnd; pn.Parent = me
	local ph = text(self, "Right Shift to hide", 11, "dim"); ph.Position = UDim2.fromOffset(42, 20); ph.Size = UDim2.new(1, -44, 0, 14); ph.TextWrapped = false; ph.Parent = me

	-- HEADER ----------------------------------------------------------------------------------------------------------------
	local top = new("Frame", { Position = UDim2.fromOffset(SIDE_W + 1, 0), Size = UDim2.new(1, -(SIDE_W + 1), 0, TOP_H), BackgroundTransparency = 1, Parent = root })
	self.pageTitle = text(self, "", 20, "text", T.bold); self.pageTitle.Position = UDim2.fromOffset(26, 14); self.pageTitle.Size = UDim2.new(.6, 0, 0, 24); self.pageTitle.TextWrapped = false; self.pageTitle.Parent = top
	self.pageSub = text(self, "", 12, "sub"); self.pageSub.Position = UDim2.fromOffset(27, 39); self.pageSub.Size = UDim2.new(.6, 0, 0, 14); self.pageSub.TextWrapped = false; self.pageSub.Parent = top
	local hline = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, Parent = top })
	bind(self, hline, "BackgroundColor3", "stroke")

	local close = new("TextButton", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -18, .5, 0), Size = UDim2.fromOffset(30, 30), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = top }, { corner(8) })
	bind(self, close, "BackgroundColor3", "elem")
	local cx = text(self, "×", 18, "sub", T.bold, Enum.TextXAlignment.Center); cx.Size = UDim2.fromScale(1, 1); cx.TextWrapped = false; cx.Parent = close
	close.MouseEnter:Connect(function() tween(close, .12, { BackgroundColor3 = Color3.fromRGB(190, 60, 60) }); tween(cx, .12, { TextColor3 = WHITE }) end)
	close.MouseLeave:Connect(function() tween(close, .12, { BackgroundColor3 = T.elem }); tween(cx, .12, { TextColor3 = T.sub }) end)
	close.MouseButton1Click:Connect(function() Sfx.Play("click"); self:SetVisible(false) end)

	-- live stats chip (fps / ping), refreshed once a second
	local stat = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -56, .5, 0), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, Parent = top }, { corner(8), pad(12, 12, 0, 0) })
	bind(self, stat, "BackgroundColor3", "elem")
	local dot = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(70, 200, 120), Parent = stat }, { corner(3) })
	local statL = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = "-- fps", RichText = true,
		Font = T.semi, TextSize = 12, Parent = stat })
	bind(self, statL, "TextColor3", "sub")
	do
		local frames = 0
		table.insert(self.conns, RunService.Heartbeat:Connect(function() frames = frames + 1 end))
		task.spawn(function()
			local last = os.clock()
			while self.gui and self.gui.Parent do
				task.wait(1)
				local now = os.clock()
				local fps = math.floor(frames / math.max(now - last, 1e-3) + .5)
				frames, last = 0, now
				self.fps = fps
				if self.visible then
					local ping
					pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + .5) end)
					statL.Text = ("<b>%d</b> fps%s"):format(fps, ping and ("   <b>%d</b> ms"):format(ping) or "")
					dot.BackgroundColor3 = fps >= 50 and Color3.fromRGB(70, 200, 120) or (fps >= 30 and Color3.fromRGB(240, 180, 60) or Color3.fromRGB(235, 80, 80))
				end
			end
		end)
	end

	-- drag by the header and the brand
	do
		local dragging, start, origin
		local function begin(i, avoid)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				for _, g in ipairs(avoid or {}) do
					local p, a, z = i.Position, g.AbsolutePosition, g.AbsoluteSize
					if p.X >= a.X and p.X <= a.X + z.X and p.Y >= a.Y and p.Y <= a.Y + z.Y then return end
				end
				dragging, start, origin = true, i.Position, holder.Position
			end
		end
		top.InputBegan:Connect(function(i) begin(i, { close, stat }) end)
		brand.InputBegan:Connect(function(i) begin(i) end)
		table.insert(self.conns, UIS.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				local d = i.Position - start
				holder.Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X, origin.Y.Scale, origin.Y.Offset + d.Y)
			end
		end))
		table.insert(self.conns, UIS.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
		end))
	end

	-- CONTENT ---------------------------------------------------------------------------------------------------------------
	local content = new("ScrollingFrame", {
		Position = UDim2.fromOffset(SIDE_W + 1, TOP_H), Size = UDim2.new(1, -(SIDE_W + 1), 1, -TOP_H), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = root,
	})
	bind(self, content, "ScrollBarImageColor3", "off")
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	pad(22, 22, 16, 24).Parent = content
	self.content = content
	self.panel = { mod = nil } -- v3 compatibility (the drawer is gone; settings open inside the card)

	-- OVERLAY (dropdown lists, colour popups) ----------------------------------------------------------------------------
	self.overlay = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 50, Parent = gui })

	-- TOASTS + MODULE LIST (HUD) ---------------------------------------------------------------------------------------------
	self.toasts = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.fromOffset(320, 460), BackgroundTransparency = 1, Parent = gui })
	new("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = self.toasts })
	self.array = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(320, 600), BackgroundTransparency = 1, Parent = gui })
	new("UIListLayout", { Padding = UDim.new(0, 0), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.array })

	tween(self.scale, .35, { Scale = self.baseScale }, Enum.EasingStyle.Quint)
	Sfx.Preload()
	task.delay(.1, function() Sfx.Play("open") end)
	if self.blur and self.blurSize > 0 then tween(self.blur, .4, { Size = self.blurSize }) end
	return self
end

-- TABS ----------------------------------------------------------------------------------------------------------------------
-- opts: { Icon = n, Section = "Combat" }. Tabs with the same Section sit together under one small heading.
function UI:Tab(name, opts)
	opts = opts or {}
	local idx = #self.tabs + 1
	self.navOrder = self.navOrder + 1
	if opts.Section and opts.Section ~= self.lastNavSection then
		self.lastNavSection = opts.Section
		local h = text(self, opts.Section:upper(), 10, "dim", T.bold)
		h.Size = UDim2.new(1, 0, 0, 26); h.LayoutOrder = self.navOrder; h.TextWrapped = false; h.TextYAlignment = Enum.TextYAlignment.Bottom
		h.Parent = self.nav
		pad(10, 0, 0, 6).Parent = h
		self.navOrder = self.navOrder + 1
	end
	local btn = new("TextButton", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", LayoutOrder = self.navOrder, BorderSizePixel = 0, Parent = self.nav }, { corner(8) })
	bind(self, btn, "BackgroundColor3", "elem")
	local bar = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(3, 16), BorderSizePixel = 0, BackgroundTransparency = 1, Parent = btn }, { corner(2) })
	bind(self, bar, "BackgroundColor3", "accent")
	local ico = opts.Icon and Icons.Make(btn, opts.Icon, 16, UDim2.new(0, 14, .5, -8))
	if ico then bind(self, ico, "ImageColor3", "sub") end
	local baseX = ico and 40 or 16
	local txt = text(self, name, 13, "sub", T.semi); txt.Position = UDim2.fromOffset(baseX, 0); txt.Size = UDim2.new(1, -baseX - 34, 1, 0); txt.TextWrapped = false; txt.TextTruncate = Enum.TextTruncate.AtEnd; txt.Parent = btn
	-- how many modules of this tab are on
	local badge = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0), Size = UDim2.fromOffset(18, 16), BorderSizePixel = 0, Visible = false, Parent = btn }, { corner(8) })
	bind(self, badge, "BackgroundColor3", "accentDim")
	local badgeT = text(self, "", 10, "chip", T.bold, Enum.TextXAlignment.Center); badgeT.Size = UDim2.fromScale(1, 1); badgeT.TextWrapped = false; badgeT.Parent = badge

	local page = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = idx, Visible = false, Parent = self.content })
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	local header = text(self, name, 12, "sub", T.bold)
	header.Size = UDim2.new(1, 0, 0, 18); header.LayoutOrder = -1; header.Visible = false; header.TextWrapped = false; header.Parent = page

	local tab = { name = name, btn = btn, txt = txt, ico = ico, bar = bar, page = page, header = header, win = self, index = idx, iconIdx = opts.Icon, modCount = 0, onCount = 0 }
	tab.refreshBadge = function()
		badge.Visible = tab.onCount > 0
		badgeT.Text = tostring(tab.onCount)
		if self.active == tab then self:_pageSub(tab) end
	end
	setmetatable(tab, { __index = UI.TabMethods })
	table.insert(self.tabs, tab)

	btn.MouseEnter:Connect(function()
		if self.active ~= tab then tween(btn, .12, { BackgroundTransparency = .4 }); tween(txt, .12, { TextColor3 = T.text }) end
	end)
	btn.MouseLeave:Connect(function()
		if self.active ~= tab then tween(btn, .12, { BackgroundTransparency = 1 }); tween(txt, .12, { TextColor3 = T.sub }) end
	end)
	btn.MouseButton1Click:Connect(function()
		if self.searchBox.Text ~= "" then self.searchBox.Text = "" end
		if self.active ~= tab then Sfx.Play("tab") end
		self:Select(tab)
	end)
	if not self.active then self:Select(tab) end
	return tab
end

function UI:_pageSub(tab)
	local parts = {}
	if tab.modCount > 0 then parts[#parts + 1] = tab.modCount .. (tab.modCount == 1 and " module" or " modules") end
	if tab.onCount > 0 then parts[#parts + 1] = tab.onCount .. " on" end
	self.pageSub.Text = table.concat(parts, "  ·  ")
end

function UI:Select(tab)
	self.active = tab
	self:_closePopup()
	for _, t in ipairs(self.tabs) do
		local on = t == tab
		tween(t.btn, .15, { BackgroundTransparency = on and 0 or 1 })
		tween(t.bar, .15, { BackgroundTransparency = on and 0 or 1 })
		tween(t.txt, .15, { TextColor3 = on and T.text or T.sub })
		if t.ico then tween(t.ico, .15, { ImageColor3 = on and T.accent or T.sub }) end
		if not on then t.page.Visible = false end
	end
	self.pageTitle.Text = tab.name
	self:_pageSub(tab)
	tab.page.Visible = true
	self.content.CanvasPosition = Vector2.zero
end

-- v3 compatibility: "panels" are the settings inside a module card now
function UI:OpenPanel(mod) if mod and mod.setOpen then mod.setOpen(true) end end
function UI:ClosePanel() end

-- SEARCH ----------------------------------------------------------------------------------------------------------------------
function UI:_search(q)
	q = q:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if q == "" then
		for _, t in ipairs(self.tabs) do t.header.Visible = false; t.page.Visible = t == self.active end
		for _, r in ipairs(self.rows) do r.frame.Visible = true end
		for _, sec in ipairs(self.sections) do
			if sec.collapsed then for _, fr in ipairs(sec.rows) do fr.Visible = false end end
		end
		if self.active then self.pageTitle.Text = self.active.name; self:_pageSub(self.active) end
		return
	end
	self:_closePopup()
	local hits, n = {}, 0
	for _, r in ipairs(self.rows) do
		if r.keep then
			r.frame.Visible = true
		else
			local m = r.name:find(q, 1, true) ~= nil or r.tab.name:lower():find(q, 1, true) ~= nil
			r.frame.Visible = m
			if m then hits[r.tab] = true; n = n + 1 end
		end
	end
	for _, t in ipairs(self.tabs) do
		local has = hits[t] == true
		t.header.Visible = has
		t.page.Visible = has
	end
	self.pageTitle.Text = "Search"
	self.pageSub.Text = n .. (n == 1 and " result" or " results") .. " for \"" .. q .. "\""
	self.content.CanvasPosition = Vector2.zero
end

-- TOASTS ----------------------------------------------------------------------------------------------------------------------
local KINDS = {
	info = { color = Color3.fromRGB(124, 131, 255), sound = "notify", title = "Info" },
	success = { color = Color3.fromRGB(70, 200, 120), sound = "success", title = "Done" },
	warn = { color = Color3.fromRGB(240, 96, 84), sound = "warn", title = "Heads up" },
}
local function guessKind(textv)
	local l = textv:lower()
	if l:find("not found", 1, true) or l:find("failed", 1, true) or l:find("error", 1, true) or l:find("nothing", 1, true) or l:find("no pickup", 1, true)
		or l:find("changed its", 1, true) or l:find("missing", 1, true) or l:find("can't", 1, true) or l:find("cannot", 1, true) or l:find("no item", 1, true)
		or l:find("police nearby", 1, true) then return "warn" end
	if l:find("learned", 1, true) or l:find("picked up", 1, true) or l:find("loaded", 1, true) or l:find("restored", 1, true) or l:find("applied", 1, true)
		or l:find("saved", 1, true) or l:find(" on", 1, true) or l:find("normal", 1, true) then return "success" end
	return "info"
end

function UI:Notify(str, seconds, kind)
	str = tostring(str)
	kind = KINDS[kind or ""] and kind or guessKind(str)
	local K = KINDS[kind]
	seconds = seconds or 3
	Sfx.Play(K.sound, .7)
	local slot = new("Frame", { Size = UDim2.fromOffset(310, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = self.toasts })
	local card = new("Frame", { Position = UDim2.fromOffset(340, 0), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, ClipsDescendants = true, Parent = slot }, { corner(10) })
	bind(self, card, "BackgroundColor3", "panel")
	mkStroke(self, "stroke", 0).Parent = card
	new("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = K.color, BorderSizePixel = 0, Parent = card })
	local body = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = card }, { pad(16, 14, 10, 13) })
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	local head = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 15), Text = K.title:upper(), Font = T.bold, TextSize = 10, TextColor3 = K.color,
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = body })
	local l = text(self, str, 13, "text"); l.Size = UDim2.new(1, 0, 0, 0); l.AutomaticSize = Enum.AutomaticSize.Y; l.LayoutOrder = 2; l.Parent = body
	local track = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = card })
	local bar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.color, BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = track })
	tween(card, .35, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	tween(bar, seconds, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	task.delay(seconds, function()
		if not slot.Parent then return end
		tween(card, .28, { Position = UDim2.fromOffset(340, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.wait(.3)
		pcall(function() slot:Destroy() end)
	end)
	return head
end

-- MODULE LIST (HUD) -----------------------------------------------------------------------------------------------------------
-- every module that is on, longest name first, top right of the screen. Rebuilt only when a module changes (never per frame).
function UI:_refreshArray()
	local arr = self.array
	if not arr then return end
	for _, c in ipairs(arr:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	if not self.arrayOn then return end
	local list = {}
	for _, m in ipairs(self.modules) do
		if m.get() and not m.hidden then
			local w = 0
			pcall(function() w = TextService:GetTextSize(m.name, 14, T.semi, Vector2.new(1000, 40)).X end)
			list[#list + 1] = { name = m.name, w = w }
		end
	end
	table.sort(list, function(a, b) return a.w > b.w end)
	for i, e in ipairs(list) do
		local row = new("Frame", { Size = UDim2.fromOffset(e.w + 24, 22), BackgroundColor3 = T.bg, BackgroundTransparency = 0.25, BorderSizePixel = 0, LayoutOrder = i, Parent = arr })
		new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = T.accent:Lerp(T.chip, (i - 1) / math.max(#list - 1, 1)), BorderSizePixel = 0, Parent = row })
		new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -16, 1, 0), Text = e.name, Font = T.semi, TextSize = 14,
			TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
	end
end
function UI:SetArrayList(v) self.arrayOn = v; self:_refreshArray() end

-- WINDOW STATE -----------------------------------------------------------------------------------------------------------------
function UI:_closePopup()
	if self.openPopup then pcall(self.openPopup); self.openPopup = nil end
end

function UI:SetVisible(v)
	self.visible = v
	if not v then
		if self.openPicker then pcall(function() self.openPicker:Close() end) end
		self:_closePopup()
	end
	if v then
		self.root.Visible = true
		Sfx.Play("open")
		if self.blur and self.blurSize > 0 then tween(self.blur, .3, { Size = self.blurSize }) end
		tween(self.scale, .28, { Scale = self.baseScale }, Enum.EasingStyle.Quint)
	else
		pcall(function() self.searchBox:ReleaseFocus() end)
		Sfx.Play("close")
		if self.blur then tween(self.blur, .2, { Size = 0 }) end
		tween(self.scale, .16, { Scale = self.baseScale * .96 })
		task.delay(.18, function() if not self.visible then self.root.Visible = false end end)
	end
end
function UI:Toggle() self:SetVisible(not self.visible) end

function UI:SetScale(s)
	self.baseScale = (self.autoScale or 1) * s
	tween(self.scale, .2, { Scale = self.baseScale })
end

function UI:SetBlur(size)
	self.blurSize = size
	if self.blur and self.visible then tween(self.blur, .3, { Size = size }) end
end

function UI:Destroy()
	pcall(function() if self.blur then self.blur:Destroy() end end)
	for _, c in ipairs(self.conns) do pcall(function() c:Disconnect() end) end
	self.gui:Destroy()
end

-- COMPONENTS ------------------------------------------------------------------------------------------------------------------
local M = {}
UI.TabMethods = M

-- settings registry: every Toggle / Slider / Keybind is remembered under "Tab/Module/Name" so a whole config can be saved and applied
local function register(self, o, kind, obj)
	if o.NoSave then return end
	local win = self.win
	local id = (self.realTab or self).name .. "/" .. (self.modName and (self.modName .. "/") or "") .. o.Name
	if win.flags[id] then
		local n = 2
		while win.flags[id .. "#" .. n] do n = n + 1 end
		id = id .. "#" .. n
	end
	win.flags[id] = { kind = kind, obj = obj }
end

local function colorHex(c) return string.format("#%02X%02X%02X", math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end
local function hexColor(t)
	t = tostring(t or ""):gsub("[#%s]", "")
	if #t ~= 6 or not t:match("^%x+$") then return nil end
	return Color3.fromRGB(tonumber(t:sub(1, 2), 16), tonumber(t:sub(3, 4), 16), tonumber(t:sub(5, 6), 16))
end

-- every saved setting: toggles, sliders, keybinds, colours, text boxes and choices
function UI:GetConfig()
	local out = {}
	for id, f in pairs(self.flags) do
		local ok, v = pcall(function() return f.obj:Get() end)
		if ok and v ~= nil then
			if f.kind == "key" then v = v and v.Name or ""
			elseif f.kind == "color" then v = colorHex(v) end
			out[id] = v
		end
	end
	return out
end

-- sliders and keybinds first, toggles last: a module reads its sliders when it turns on
function UI:ApplyConfig(cfg)
	for pass = 1, 2 do
		for id, f in pairs(self.flags) do
			local v = cfg[id]
			if v ~= nil and ((f.kind == "toggle") == (pass == 2)) then
				pcall(function()
					if f.kind == "key" then
						f.obj:Set(v ~= "" and Enum.KeyCode[v] or nil)
					elseif f.kind == "color" then
						local c = hexColor(v)
						if c and colorHex(f.obj:Get()) ~= colorHex(c) then f.obj:Set(c) end
					elseif f.obj:Get() ~= v then
						f.obj:Set(v)
					end
				end)
			end
		end
	end
end

-- a settings row. Inside a module card it is a flat line (no box); on a page it is a rounded card of its own.
local function row(tab, name, minH, fixed)
	local win = tab.win
	local compact = tab.inModule == true
	local f
	if compact then
		f = new("Frame", { Size = UDim2.new(1, 0, 0, minH and math.max(minH - 10, 34) or 36), AutomaticSize = fixed and Enum.AutomaticSize.None or Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = tab.page }, { corner(7) })
		bind(win, f, "BackgroundColor3", "elem")
		f.MouseEnter:Connect(function() tween(f, .12, { BackgroundTransparency = 0.5 }) end)
		f.MouseLeave:Connect(function() tween(f, .15, { BackgroundTransparency = 1 }) end)
		return f, nil, true
	end
	tab.grid = nil
	f = new("Frame", { Size = UDim2.new(1, 0, 0, minH or 46), AutomaticSize = fixed and Enum.AutomaticSize.None or Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = tab.page }, { corner(10) })
	bind(win, f, "BackgroundColor3", "panel")
	local st = mkStroke(win, "stroke", 0); st.Parent = f
	f.MouseEnter:Connect(function() tween(f, .12, { BackgroundColor3 = T.elem }) end)
	f.MouseLeave:Connect(function() tween(f, .15, { BackgroundColor3 = T.panel }) end)
	table.insert(win.rows, { frame = f, name = name:lower(), tab = tab.realTab or tab })
	local cs = tab.curSection
	if cs then
		table.insert(cs.rows, f)
		if cs.collapsed then f.Visible = false end
		if cs.count then cs.count() end
	end
	return f, st, false
end

local function rowLabel(win, f, str, rightRoom, compact)
	local l = text(win, str, 13, compact and "sub" or "text")
	l.Position = UDim2.fromOffset(compact and 10 or 16, compact and 9 or 13); l.Size = UDim2.new(1, -(rightRoom + (compact and 20 or 30)), 0, 0); l.AutomaticSize = Enum.AutomaticSize.Y; l.Parent = f
	new("UISizeConstraint", { MinSize = Vector2.new(0, compact and 18 or 20), Parent = l })
	-- bottom padding so a wrapped label still leaves room under it
	pad(0, 0, 0, compact and 9 or 13).Parent = l
	return l
end

function M:Section(o)
	local name = type(o) == "table" and o.Name or tostring(o)
	local win = self.win
	if self.inModule then
		local f = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = self.page })
		local l = text(win, name:upper(), 10, "dim", T.bold); l.Position = UDim2.fromOffset(10, 0); l.Size = UDim2.new(1, -20, 1, -4); l.TextWrapped = false; l.TextYAlignment = Enum.TextYAlignment.Bottom; l.Parent = f
		return { frame = f, Section = {} }
	end
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Parent = self.page })
	self.grid = nil
	local l = text(win, name:upper(), 11, "dim", T.bold); l.Position = UDim2.fromOffset(4, 6); l.Size = UDim2.new(1, -70, 1, -6); l.TextWrapped = false; l.TextYAlignment = Enum.TextYAlignment.Bottom; l.Parent = f
	local chev = text(win, "", 11, "dim", T.bold, Enum.TextXAlignment.Right); chev.AnchorPoint = Vector2.new(1, 1); chev.Position = UDim2.new(1, -4, 1, 0); chev.Size = UDim2.fromOffset(60, 16); chev.TextWrapped = false; chev.Parent = f
	local sec = { rows = {}, collapsed = type(o) == "table" and o.Collapsed == true }
	local function refreshHead() chev.Text = sec.collapsed and (#sec.rows .. " hidden  ›") or "" end
	sec.count = refreshHead
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = f })
	hit.MouseEnter:Connect(function() tween(l, .12, { TextColor3 = T.text }) end)
	hit.MouseLeave:Connect(function() tween(l, .12, { TextColor3 = T.dim }) end)
	hit.MouseButton1Click:Connect(function()
		sec.collapsed = not sec.collapsed
		for _, r in ipairs(sec.rows) do r.Visible = not sec.collapsed end
		refreshHead()
	end)
	self.curSection = sec
	table.insert(win.sections, sec)
	table.insert(win.rows, { frame = f, name = "\0", tab = self.realTab or self })
	return { frame = f, Section = sec }
end

function M:Label(o)
	local win = self.win
	local f, _, compact = row(self, o.Name, 42)
	local n = text(win, o.Name, 13, "sub"); n.Position = UDim2.fromOffset(compact and 10 or 16, compact and 9 or 12); n.Size = UDim2.new(.5, -16, 0, 0); n.AutomaticSize = Enum.AutomaticSize.Y; n.Parent = f
	pad(0, 0, 0, compact and 9 or 12).Parent = n
	local v = text(win, tostring(o.Value or "-"), 13, "text", T.semi, Enum.TextXAlignment.Right)
	v.Position = UDim2.new(.5, 0, 0, compact and 9 or 12); v.Size = UDim2.new(.5, compact and -10 or -16, 0, 0); v.AutomaticSize = Enum.AutomaticSize.Y; v.Parent = f
	return { Set = function(_, x) local s = tostring(x); if v.Text ~= s then v.Text = s end end, frame = f }
end

function M:Button(o)
	local win = self.win
	local b, t
	if self.inModule then
		b = new("TextButton", { Size = UDim2.new(1, 0, 0, 32), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = self.page }, { corner(7) })
		bind(win, b, "BackgroundColor3", "elem")
		t = text(win, o.Name, 13, "text", T.semi, Enum.TextXAlignment.Center); t.Size = UDim2.new(1, -16, 1, 0); t.Position = UDim2.fromOffset(8, 0); t.TextWrapped = false; t.TextTruncate = Enum.TextTruncate.AtEnd; t.Parent = b
	else
		self.grid = nil
		b = new("TextButton", { Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = self.page }, { corner(8), pad(16, 16, 0, 0) })
		bind(win, b, "BackgroundColor3", "elem")
		mkStroke(win, "stroke", 0).Parent = b
		t = text(win, o.Name, 13, "text", T.semi, Enum.TextXAlignment.Center); t.Size = UDim2.fromOffset(0, 34); t.AutomaticSize = Enum.AutomaticSize.X; t.TextWrapped = false; t.Parent = b
	end
	if o.Order then b.LayoutOrder = o.Order end
	b.MouseEnter:Connect(function() tween(b, .12, { BackgroundColor3 = T.hover }) end)
	b.MouseLeave:Connect(function() tween(b, .15, { BackgroundColor3 = T.elem }) end)
	b.MouseButton1Click:Connect(function()
		Sfx.Play("click")
		b.BackgroundColor3 = T.strokeOn; tween(b, .3, { BackgroundColor3 = T.hover })
		if o.Callback then task.spawn(o.Callback) end
	end)
	if not self.inModule then
		table.insert(win.rows, { frame = b, name = o.Name:lower(), tab = self.realTab or self })
		local cs = self.curSection
		if cs then
			table.insert(cs.rows, b)
			if cs.collapsed then b.Visible = false end
			if cs.count then cs.count() end
		end
	end
	return {
		frame = b,
		SetText = function(_, s) t.Text = s end,
		Destroy = function()
			for i, r in ipairs(win.rows) do if r.frame == b then table.remove(win.rows, i); break end end
			b:Destroy()
		end,
	}
end

function M:TextBox(o)
	local win = self.win
	local f, _, compact = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 150, compact)
	local bg = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, compact and -6 or -12, 0, compact and 4 or 9), Size = UDim2.fromOffset(140, 28), BorderSizePixel = 0, Parent = f }, { corner(7) })
	bind(win, bg, "BackgroundColor3", compact and "hover" or "elem")
	local st = mkStroke(win, "stroke", 0); st.Parent = bg
	local box = new("TextBox", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), Text = o.Default or "", PlaceholderText = o.Placeholder or "",
		Font = T.font, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ClipsDescendants = true, Parent = bg })
	bind(win, box, "TextColor3", "text"); bind(win, box, "PlaceholderColor3", "dim")
	box.Focused:Connect(function() tween(st, .12, { Color = T.accent }) end)
	box.FocusLost:Connect(function()
		tween(st, .15, { Color = T.stroke })
		if o.Callback then task.spawn(o.Callback, box.Text) end
	end)
	local obj = { frame = f }
	function obj:Get() return box.Text end
	function obj:Set(t, silent) box.Text = tostring(t); if not silent and o.Callback then task.spawn(o.Callback, box.Text) end end
	register(self, o, "text", obj)
	return obj
end

-- Choice: a dropdown. Click opens the list; right-click steps back one option. Saved with the config.
function M:Choice(o)
	local win = self.win
	local f, _, compact = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 160, compact)
	local opts_ = o.Options
	local idx = 1
	for i, v in ipairs(opts_) do if v == o.Default then idx = i end end
	local btn = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, compact and -6 or -12, 0, compact and 4 or 9), Size = UDim2.fromOffset(150, 28), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = f }, { corner(7) })
	bind(win, btn, "BackgroundColor3", compact and "hover" or "elem")
	local bst = mkStroke(win, "stroke", 0); bst.Parent = btn
	local txt = text(win, "", 12, "text", T.semi); txt.Size = UDim2.new(1, -34, 1, 0); txt.Position = UDim2.fromOffset(10, 0); txt.TextWrapped = false; txt.TextTruncate = Enum.TextTruncate.AtEnd; txt.Parent = btn
	local arrow = text(win, "▾", 12, "sub", T.bold, Enum.TextXAlignment.Center); arrow.AnchorPoint = Vector2.new(1, 0); arrow.Position = UDim2.new(1, -4, 0, 0); arrow.Size = UDim2.fromOffset(22, 28); arrow.TextWrapped = false; arrow.Parent = btn
	local obj = { frame = f }
	local function show() txt.Text = tostring(opts_[idx]) end
	local function pickIdx(i, silent)
		idx = i
		show()
		if not silent then
			Sfx.Play("click", .5)
			if o.Callback then task.spawn(o.Callback, opts_[idx]) end
		end
	end
	function obj:Get() return opts_[idx] end
	function obj:Set(v, silent) for i, x in ipairs(opts_) do if x == v then pickIdx(i, silent); return end end end

	local function openList()
		win:_closePopup()
		local ov = win.overlay
		local catcher = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 50, Parent = ov })
		local itemH = 28
		local hgt = math.min(#opts_ * itemH + 8, 260)
		local ap, as = btn.AbsolutePosition, btn.AbsoluteSize
		local vs = win.gui.AbsoluteSize
		local wdt = math.max(as.X, 170)
		local y = ap.Y + as.Y + 4
		if y + hgt > vs.Y - 8 then y = ap.Y - hgt - 4 end
		local list = new("ScrollingFrame", { Position = UDim2.fromOffset(math.clamp(ap.X + as.X - wdt, 8, vs.X - wdt - 8), y), Size = UDim2.fromOffset(wdt, hgt), BorderSizePixel = 0,
			BackgroundColor3 = T.panel, ScrollBarImageColor3 = T.off, ScrollBarThickness = 2, CanvasSize = UDim2.fromOffset(0, #opts_ * itemH + 8), ZIndex = 51, Parent = ov }, { corner(8), pad(4, 4, 4, 4) })
		new("UIStroke", { Color = T.stroke, Thickness = 1, Parent = list })
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		for i, v in ipairs(opts_) do
			local cur = i == idx
			local it = new("TextButton", { Size = UDim2.new(1, 0, 0, itemH), BackgroundColor3 = T.accentDim, BackgroundTransparency = cur and 0 or 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = i, ZIndex = 52, Parent = list }, { corner(6) })
			local il = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -30, 1, 0), Text = tostring(v), TextSize = 12, Font = cur and T.semi or T.font,
				TextColor3 = cur and T.text or T.sub, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 53, Parent = it })
			if cur then
				new("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 0), Size = UDim2.fromOffset(22, itemH), Text = "✓", TextSize = 12, Font = T.bold, TextColor3 = T.accent, ZIndex = 53, Parent = it })
			end
			it.MouseEnter:Connect(function() if not cur then it.BackgroundColor3 = T.hover; it.BackgroundTransparency = 0 end; il.TextColor3 = T.text end)
			it.MouseLeave:Connect(function() if not cur then it.BackgroundTransparency = 1; il.TextColor3 = T.sub end end)
			it.MouseButton1Click:Connect(function() win:_closePopup(); pickIdx(i) end)
		end
		list.CanvasPosition = Vector2.new(0, math.max(0, (idx - 4) * itemH))
		tween(arrow, .15, { Rotation = 180 })
		tween(bst, .12, { Color = T.accent })
		catcher.MouseButton1Click:Connect(function() win:_closePopup() end)
		catcher.MouseButton2Click:Connect(function() win:_closePopup() end)
		win.openPopup = function()
			pcall(function() catcher:Destroy(); list:Destroy() end)
			tween(arrow, .15, { Rotation = 0 }); tween(bst, .15, { Color = T.stroke })
		end
	end
	btn.MouseButton1Click:Connect(function() Sfx.Play("click", .4); openList() end)
	btn.MouseButton2Click:Connect(function() pickIdx((idx - 2) % #opts_ + 1) end)
	btn.MouseEnter:Connect(function() tween(btn, .12, { BackgroundColor3 = T.hover:Lerp(T.text, .04) }) end)
	btn.MouseLeave:Connect(function() tween(btn, .15, { BackgroundColor3 = compact and T.hover or T.elem }) end)
	show()
	register(self, o, "choice", obj)
	return obj
end

function M:Toggle(o)
	local win = self.win
	local f, _, compact = row(self, o.Name, 48)
	local lbl = rowLabel(win, f, o.Name, 50, compact)
	local state = false
	local sw, setSwitch = makeSwitch(win, f, Vector2.new(1, 0), UDim2.new(1, compact and -10 or -16, 0, compact and 9 or 14), function() return state end)
	local obj = {}
	local function apply(v, silent)
		state = v
		setSwitch(v, not silent)
		if compact then tween(lbl, .15, { TextColor3 = v and T.text or T.sub }) end
		if not silent then
			Sfx.Play(v and "on" or "off")
			if o.Callback then task.spawn(o.Callback, v) end
		end
	end
	function obj:Set(v, silent) apply(v, silent) end
	function obj:Get() return state end
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = f })
	hit.MouseButton1Click:Connect(function() apply(not state) end)
	apply(o.Default == true, true)
	if compact then bind(win, lbl, "TextColor3", function() return state and T.text or T.sub end) end
	obj.frame, obj.hit = f, hit
	register(self, o, "toggle", obj)
	return obj
end

-- MODULE CARD -----------------------------------------------------------------------------------------------------------------
-- A card in a two-column grid: name, a status line, an expand arrow (when it has settings) and a switch.
-- Click the card to switch it on / off; click the arrow (or right-click the card) to open its settings inside the card.
-- local m = tab:Module({ Name = "Suspension", Default = false, Callback = function(on) end })
-- m:Slider({...}) / m:Toggle({...}) / m:Keybind({...}) / m:Button({...}) / m:Label({...}) / m:Choice({...}) add settings to it.
local function gridFor(tab)
	if tab.grid and tab.grid.Parent then return tab.grid end
	local win = tab.win
	local g = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = tab.page })
	local cols = {}
	for i = 1, 2 do
		local c = new("Frame", { Position = UDim2.new((i - 1) * .5, i == 2 and 5 or 0, 0, 0), Size = UDim2.new(.5, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = g })
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = c })
		cols[i] = { frame = c, n = 0 }
	end
	tab.grid, tab.gridCols = g, cols
	table.insert(win.rows, { frame = g, name = "\0grid", tab = tab.realTab or tab, keep = true })
	return g
end

function M:Module(o)
	local win = self.win
	local realTab = self.realTab or self
	realTab.modCount = realTab.modCount + 1
	gridFor(self)
	local cols = self.gridCols
	local col = cols[1].n <= cols[2].n and cols[1] or cols[2]
	col.n = col.n + 1

	local card = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, LayoutOrder = col.n, Parent = col.frame }, { corner(10) })
	local cstroke = new("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })

	local state, count, open = false, 0, false
	local obj = {}
	bind(win, card, "BackgroundColor3", "panel")
	bind(win, cstroke, "Color", function() return state and T.strokeOn or T.stroke end)

	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, LayoutOrder = 1, Parent = card })
	local edge = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(3, 22), BorderSizePixel = 0, Parent = head }, { corner(2) })
	bind(win, edge, "BackgroundColor3", "accent")
	edge.BackgroundTransparency = 1
	local nameL = text(win, o.Name, 14, "text", T.semi); nameL.Position = UDim2.fromOffset(16, 10); nameL.Size = UDim2.new(1, -110, 0, 18); nameL.TextWrapped = false; nameL.TextTruncate = Enum.TextTruncate.AtEnd; nameL.Parent = head
	local statL = text(win, "", 12, "dim"); statL.Position = UDim2.fromOffset(16, 29); statL.Size = UDim2.new(1, -110, 0, 15); statL.TextWrapped = false; statL.TextTruncate = Enum.TextTruncate.AtEnd; statL.Parent = head
	local sw, setSwitch = makeSwitch(win, head, Vector2.new(1, .5), UDim2.new(1, -16, .5, 0), function() return state end)

	local body = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, LayoutOrder = 2, Parent = card })
	local sep = new("Frame", { Size = UDim2.new(1, -24, 0, 1), Position = UDim2.fromOffset(12, 0), BorderSizePixel = 0, Parent = body })
	bind(win, sep, "BackgroundColor3", "stroke")
	local inner = new("Frame", { Position = UDim2.fromOffset(0, 1), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = body }, { pad(8, 8, 6, 10) })
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })

	local function status()
		if count > 0 then
			statL.Text = (state and "Enabled" or "Disabled") .. "  ·  " .. count .. (count == 1 and " setting" or " settings")
		else
			statL.Text = state and "Enabled" or "Disabled"
		end
	end
	local function paint(animate)
		local c = state and T.strokeOn or T.stroke
		if animate then
			tween(cstroke, .15, { Color = c }); tween(edge, .18, { BackgroundTransparency = state and 0 or 1 })
		else
			cstroke.Color = c; edge.BackgroundTransparency = state and 0 or 1
		end
	end
	local function apply(v, silent)
		local changed = v ~= state
		state = v
		setSwitch(v, not silent); paint(not silent); status()
		if changed then
			realTab.onCount = math.max(0, realTab.onCount + (v and 1 or -1))
			realTab.refreshBadge()
			win:_refreshArray()
		end
		if not silent then
			Sfx.Play(v and "on" or "off")
			if o.Callback then task.spawn(o.Callback, v) end
		end
	end
	function obj:Set(v, silent) apply(v, silent) end
	function obj:Get() return state end
	obj.frame = card

	-- expand arrow, left of the switch (only when the module has settings)
	local exp = new("TextButton", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -58, .5, 0), Size = UDim2.fromOffset(28, 28), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 3, Parent = head }, { corner(7) })
	exp.BackgroundTransparency = 1
	bind(win, exp, "BackgroundColor3", "hover")
	local chev = text(win, "›", 18, "sub", T.bold, Enum.TextXAlignment.Center); chev.Size = UDim2.fromScale(1, 1); chev.TextWrapped = false; chev.ZIndex = 4; chev.Parent = exp
	local function setOpen(v)
		if count == 0 then v = false end
		open = v
		body.Visible = v
		tween(chev, .18, { Rotation = v and 90 or 0 })
		tween(chev, .18, { TextColor3 = v and T.text or T.sub })
	end
	function obj:SetOpen(v) setOpen(v) end
	exp.MouseButton1Click:Connect(function() Sfx.Play("click", .5); setOpen(not open) end)
	exp.MouseEnter:Connect(function() tween(exp, .12, { BackgroundTransparency = 0 }) end)
	exp.MouseLeave:Connect(function() tween(exp, .15, { BackgroundTransparency = 1 }) end)

	local hit = new("TextButton", { Size = UDim2.new(1, -96, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = head })
	local swHit = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 50, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = head })
	hit.MouseButton1Click:Connect(function() apply(not state) end)
	swHit.MouseButton1Click:Connect(function() apply(not state) end)
	hit.MouseButton2Click:Connect(function() setOpen(not open) end)
	hit.MouseEnter:Connect(function() tween(card, .12, { BackgroundColor3 = T.elem }) end)
	hit.MouseLeave:Connect(function() tween(card, .15, { BackgroundColor3 = T.panel }) end)

	local sub = { page = inner, win = win, realTab = realTab, modName = o.Name, inModule = true }
	setmetatable(sub, { __index = M })
	local ent = { frame = card, name = o.Name:lower(), tab = realTab }
	table.insert(win.rows, ent)
	local mod = { name = o.Name, get = function() return state end, setOpen = setOpen, hidden = o.Hidden == true }
	table.insert(win.modules, mod)
	for _, k in ipairs({ "Toggle", "Slider", "Keybind", "Button", "Label", "TextBox", "ColorPicker", "Choice", "Section" }) do
		obj[k] = function(_, opts)
			if k ~= "Section" then
				count = count + 1
				exp.Visible = true; status()
				if opts and opts.Name then ent.name = ent.name .. " " .. tostring(opts.Name):lower() end
			end
			return M[k](sub, opts)
		end
	end
	apply(o.Default == true, true)
	register({ win = win, realTab = realTab }, o, "toggle", obj)
	return obj
end

-- SLIDER ----------------------------------------------------------------------------------------------------------------------
function M:Slider(o)
	local win = self.win
	local f, _, compact = row(self, o.Name, 58)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
	if compact then pad(10, 10, 8, 10).Parent = f else pad(16, 16, 12, 14).Parent = f end
	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, Parent = f })
	local n = text(win, o.Name, 13, compact and "sub" or "text"); n.Size = UDim2.new(1, -74, 0, 0); n.AutomaticSize = Enum.AutomaticSize.Y; n.Parent = head
	new("UISizeConstraint", { MinSize = Vector2.new(0, 18), Parent = n })
	local valBg = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, Parent = head }, { corner(5), pad(6, 6, 0, 0) })
	bind(win, valBg, "BackgroundColor3", compact and "hover" or "elem")
	local val = text(win, "", 12, "text", T.semi, Enum.TextXAlignment.Center); val.Size = UDim2.fromOffset(0, 18); val.AutomaticSize = Enum.AutomaticSize.X; val.TextWrapped = false; val.Parent = valBg
	local zone = new("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, LayoutOrder = 2, Parent = f })
	local track = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.new(1, 0, 0, 4), BorderSizePixel = 0, Parent = zone }, { corner(2) })
	bind(win, track, "BackgroundColor3", "off")
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = track }, { corner(2) })
	bind(win, fill, "BackgroundColor3", "accent")
	local knob = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = track }, { corner(6) })
	local kst = new("UIStroke", { Thickness = 2, Parent = knob })
	bind(win, kst, "Color", "accent")
	local min, max, step = o.Min, o.Max, o.Step or 1
	local value
	local obj = {}
	local function fmt(v)
		local s
		if step < 1 then
			local dec = step < 0.1 and 2 or 1
			s = string.format("%." .. dec .. "f", v)
		else
			s = tostring(math.floor(v + 0.5))
		end
		return s .. (o.Suffix or "")
	end
	local function set(v, silent)
		v = math.clamp(math.floor((v - min) / step + .5) * step + min, min, max)
		value = v
		local p = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(p, 1); knob.Position = UDim2.fromScale(p, .5)
		val.Text = fmt(v)
		if not silent and o.Callback then task.spawn(o.Callback, v) end
	end
	function obj:Set(v, silent) set(v, silent) end
	function obj:Get() return value end
	local dragging = false
	local function fromInput(i) set(min + math.clamp((i.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1) * (max - min)) end
	local hit = new("TextButton", { Size = UDim2.new(1, 0, 1, 10), Position = UDim2.fromOffset(0, -5), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = zone })
	hit.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true; tween(knob, .1, { Size = UDim2.fromOffset(15, 15) }); fromInput(i)
		end
	end)
	table.insert(win.conns, UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromInput(i) end
	end))
	table.insert(win.conns, UIS.InputEnded:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			dragging = false; tween(knob, .1, { Size = UDim2.fromOffset(12, 12) }); Sfx.Play("click", .35)
		end
	end))
	set(o.Default or min, true)
	obj.frame = f
	register(self, o, "slider", obj)
	return obj
end

-- KEYBIND ---------------------------------------------------------------------------------------------------------------------
-- click, then press a key to bind it (Escape clears). Callback(key) gets an Enum.KeyCode or nil.
function M:Keybind(o)
	local win = self.win
	local f, _, compact = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 110, compact)
	local btn = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, compact and -6 or -12, 0, compact and 4 or 9), Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = f }, { corner(7), pad(12, 12, 0, 0) })
	bind(win, btn, "BackgroundColor3", compact and "hover" or "elem")
	local bst = mkStroke(win, "stroke", 0); bst.Parent = btn
	local txt = text(win, "", 12, "text", T.bold, Enum.TextXAlignment.Center); txt.Size = UDim2.fromOffset(0, 28); txt.AutomaticSize = Enum.AutomaticSize.X; txt.TextWrapped = false; txt.Parent = btn
	new("UISizeConstraint", { MinSize = Vector2.new(30, 0), Parent = txt })
	local key, listening, conn = o.Default, false, nil
	local obj = {}
	local function show()
		txt.Text = listening and "press a key…" or (key and key.Name or "none")
		tween(txt, .12, { TextColor3 = listening and T.accent or T.text })
		tween(bst, .12, { Color = listening and T.accent or T.stroke })
	end
	function obj:Get() return key end
	-- still "listening" for a moment after a bind, so the key you just chose does not also fire its action
	function obj:IsListening() return listening or os.clock() - (obj.boundAt or 0) < 0.25 end
	function obj:Set(k, silent) key = k; show(); if not silent and o.Callback then task.spawn(o.Callback, key) end end
	btn.MouseButton1Click:Connect(function()
		if listening then return end
		listening = true
		show()
		conn = UIS.InputBegan:Connect(function(i)
			if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
			conn:Disconnect()
			key = (i.KeyCode ~= Enum.KeyCode.Escape) and i.KeyCode or nil
			listening = false
			obj.boundAt = os.clock()
			show()
			if o.Callback then task.spawn(o.Callback, key) end
		end)
		table.insert(win.conns, conn)
	end)
	show()
	obj.frame = f
	register(self, o, "key", obj)
	return obj
end

-- COLOUR PICKER ---------------------------------------------------------------------------------------------------------------
-- A swatch that opens a popup with a saturation/brightness square and a hue bar. Drag to choose; Callback(color, final)
-- runs while dragging (throttled, final=false) and once more on release / close (final=true).
function M:ColorPicker(o)
	local win = self.win
	local f, _, compact = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 60, compact)
	local color = o.Default or T.accent
	local h, s, v = color:ToHSV()
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = f })
	local sw = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, compact and -10 or -16, 0, compact and 7 or 12), Size = UDim2.fromOffset(38, 22), BackgroundColor3 = color, BorderSizePixel = 0, Parent = f }, { corner(6) })
	new("UIStroke", { Color = WHITE, Thickness = 1, Transparency = .82, Parent = sw })

	local obj = {}
	local pop, svBox, svCur, hueCur, hexBox, prev, hueBar
	local lastFire = 0
	local function hex() return string.format("#%02X%02X%02X", math.floor(color.R * 255 + .5), math.floor(color.G * 255 + .5), math.floor(color.B * 255 + .5)) end
	local function fire(final)
		if not o.Callback then return end
		if final or os.clock() - lastFire > 0.08 then
			lastFire = os.clock()
			task.spawn(o.Callback, color, final == true)
		end
	end
	local function refresh()
		color = Color3.fromHSV(h, s, v)
		sw.BackgroundColor3 = color
		if pop then
			svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svCur.Position = UDim2.fromScale(s, 1 - v)
			hueCur.Position = UDim2.fromScale(h, .5)
			if not hexBox:IsFocused() then hexBox.Text = hex() end
			prev.BackgroundColor3 = color
		end
	end
	function obj:Get() return color end
	function obj:Set(c, silent) h, s, v = c:ToHSV(); refresh(); if not silent then fire(true) end end

	local function build()
		pop = new("Frame", { Size = UDim2.fromOffset(236, 262), BackgroundColor3 = T.panel, BorderSizePixel = 0, ZIndex = 60, Visible = false, Parent = win.gui }, { corner(10) })
		new("UIStroke", { Color = T.stroke, Thickness = 1, Parent = pop })
		new("TextLabel", { BackgroundTransparency = 1, Text = o.Name, TextSize = 13, Font = T.bold, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -46, 0, 20), ZIndex = 61, Parent = pop })
		local x = new("TextButton", { Position = UDim2.new(1, -30, 0, 6), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = T.elem, BorderSizePixel = 0, AutoButtonColor = false, Text = "×", TextSize = 16, Font = T.bold, TextColor3 = T.sub, ZIndex = 61, Parent = pop }, { corner(6) })
		x.MouseButton1Click:Connect(function() obj:Close() end)

		svBox = new("Frame", { Position = UDim2.fromOffset(12, 36), Size = UDim2.fromOffset(212, 140), BackgroundColor3 = Color3.fromHSV(h, 1, 1), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 61, Parent = pop }, { corner(7) })
		local white = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 61, Parent = svBox })
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = white })
		local black = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 61, Parent = svBox })
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }), Parent = black })
		svCur = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 62, Parent = svBox }, { corner(6) })
		new("UIStroke", { Color = WHITE, Thickness = 2, Parent = svCur })

		hueBar = new("Frame", { Position = UDim2.fromOffset(12, 186), Size = UDim2.fromOffset(212, 12), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 61, Parent = pop }, { corner(6) })
		new("UIGradient", { Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)), ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)), ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)), ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)) }), Parent = hueBar })
		hueCur = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(6, 18), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 62, Parent = hueBar }, { corner(3) })
		new("UIStroke", { Color = BLACK, Thickness = 1, Transparency = .3, Parent = hueCur })

		prev = new("Frame", { Position = UDim2.fromOffset(12, 212), Size = UDim2.fromOffset(34, 30), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 61, Parent = pop }, { corner(7) })
		local hexBg = new("Frame", { Position = UDim2.fromOffset(54, 212), Size = UDim2.fromOffset(94, 30), BackgroundColor3 = T.elem, BorderSizePixel = 0, ZIndex = 61, Parent = pop }, { corner(7) })
		hexBox = new("TextBox", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = hex(), TextSize = 12, Font = T.bold, TextColor3 = T.text, ClearTextOnFocus = false, ZIndex = 62, Parent = hexBg })
		hexBox.FocusLost:Connect(function()
			local c = hexColor(hexBox.Text)
			if c then h, s, v = c:ToHSV(); refresh(); fire(true) else hexBox.Text = hex() end
		end)
		local rs = new("TextButton", { Position = UDim2.fromOffset(156, 212), Size = UDim2.fromOffset(68, 30), BackgroundColor3 = T.elem, BorderSizePixel = 0, AutoButtonColor = false, Text = "Reset", TextColor3 = T.text, Font = T.semi, TextSize = 12, ZIndex = 61, Parent = pop }, { corner(7) })
		rs.MouseButton1Click:Connect(function()
			if o.Default then h, s, v = o.Default:ToHSV(); refresh(); fire(true) end
		end)

		-- dragging (GetMouseLocation matches the ScreenGui's coordinates, which ignore the top bar inset)
		local mode
		local function mousePos(i)
			if i.UserInputType == Enum.UserInputType.Touch then return Vector2.new(i.Position.X, i.Position.Y + GuiService:GetGuiInset().Y) end
			return UIS:GetMouseLocation()
		end
		local function pick(i)
			local m = mousePos(i)
			if mode == "sv" then
				s = math.clamp((m.X - svBox.AbsolutePosition.X) / math.max(svBox.AbsoluteSize.X, 1), 0, 1)
				v = 1 - math.clamp((m.Y - svBox.AbsolutePosition.Y) / math.max(svBox.AbsoluteSize.Y, 1), 0, 1)
			elseif mode == "hue" then
				h = math.clamp((m.X - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 0.999)
			end
			refresh(); fire(false)
		end
		local function grab(target, name)
			local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 63, Parent = target })
			b.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then mode = name; pick(i) end
			end)
		end
		grab(svBox, "sv"); grab(hueBar, "hue")
		table.insert(win.conns, UIS.InputChanged:Connect(function(i)
			if mode and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then pick(i) end
		end))
		table.insert(win.conns, UIS.InputEnded:Connect(function(i)
			if mode and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then mode = nil; fire(true) end
		end))
		refresh()
	end

	function obj:Close()
		if pop and pop.Visible then
			pop.Visible = false
			fire(true)
		end
		if win.openPicker == obj then win.openPicker = nil end
	end
	local function open()
		if win.openPicker and win.openPicker ~= obj then win.openPicker:Close() end
		if not pop then build() end
		local sp, ss = sw.AbsolutePosition, win.gui.AbsoluteSize
		pop.Position = UDim2.fromOffset(math.clamp(sp.X + sw.AbsoluteSize.X - 236, 8, math.max(ss.X - 244, 8)), math.clamp(sp.Y + sw.AbsoluteSize.Y + 8, 8, math.max(ss.Y - 270, 8)))
		pop.Visible = true
		refresh()
		win.openPicker = obj
	end
	hit.MouseButton1Click:Connect(function() if pop and pop.Visible then obj:Close() else open() end end)
	obj.frame = f
	register(self, o, "color", obj)
	return obj
end

-- THEME -----------------------------------------------------------------------------------------------------------------------
local PALETTE_KEYS = { "accent", "accentDim", "chip", "gradA", "gradB", "strokeOn", "bg", "side", "panel", "elem", "hover", "stroke", "off", "dim" }
local function lift(c, d) return Color3.fromRGB(math.clamp(c.R * 255 + d, 0, 255), math.clamp(c.G * 255 + d, 0, 255), math.clamp(c.B * 255 + d, 0, 255)) end
local DEFAULT_P = {}
for _, k in ipairs(PALETTE_KEYS) do DEFAULT_P[k] = T[k] end
local curP = {}
for k, v in pairs(DEFAULT_P) do curP[k] = v end

-- every colour of the theme derived from two picked colours
function UI.Palette(accent, bg)
	if not accent and not bg then return DEFAULT_P end
	accent, bg = accent or DEFAULT_P.accent, bg or DEFAULT_P.bg
	return {
		accent = accent, accentDim = bg:Lerp(accent, .18), chip = accent:Lerp(WHITE, .4), gradA = accent:Lerp(BLACK, .2),
		gradB = accent:Lerp(WHITE, .25), strokeOn = bg:Lerp(accent, .45),
		bg = bg, side = lift(bg, 3), panel = lift(bg, 7), elem = lift(bg, 15), hover = lift(bg, 22), stroke = lift(bg, 21), off = lift(bg, 40), dim = lift(bg, 80),
	}
end

local function ckey(c) return math.floor(c.R * 255 + .5) .. "," .. math.floor(c.G * 255 + .5) .. "," .. math.floor(c.B * 255 + .5) end

-- recolour everything under root whose colour is a key of map (key -> new Color3); used for the HUD pieces outside the window
function UI.Remap(root, map)
	local function fix(c) return map[ckey(c)] end
	local function visit(o)
		pcall(function()
			if o:IsA("GuiObject") then
				local n = fix(o.BackgroundColor3); if n then o.BackgroundColor3 = n end
				if o:IsA("ImageLabel") or o:IsA("ImageButton") then local ic = fix(o.ImageColor3); if ic then o.ImageColor3 = ic end end
				if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then local t = fix(o.TextColor3); if t then o.TextColor3 = t end end
			elseif o:IsA("UIStroke") then
				local n = fix(o.Color); if n then o.Color = n end
			end
		end)
	end
	visit(root)
	for _, o in ipairs(root:GetDescendants()) do visit(o) end
end

function UI.PaletteMap(old, new_)
	local map = {}
	for _, k in ipairs(PALETTE_KEYS) do
		if old[k] and new_[k] and ckey(old[k]) ~= ckey(new_[k]) then map[ckey(old[k])] = new_[k] end
	end
	return map
end

-- applies a palette: every bound colour is recomputed; returns the colour map so the HUD can follow
function UI:ApplyPalette(P)
	local map = UI.PaletteMap(curP, P)
	for _, k in ipairs(PALETTE_KEYS) do if P[k] then T[k] = P[k]; curP[k] = P[k] end end
	for _, b in ipairs(self.binds) do
		pcall(function() b[1][b[2]] = b[3]() end)
	end
	self:_refreshArray()
	return map
end

UI.Theme = T
return UI

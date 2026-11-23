-- UI window (v5): the window itself (floating sidebar with brand, tabs and a profile card; header with title, search, fps / ping and close; the scrolling
-- content), tabs, search, toasts, the module list HUD, show / hide / scale / blur, config get / apply and theme switching.
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Stats = game:GetService("Stats")
local Logo = __import("core/logo")
local Icons = __import("core/icons")
local Sfx = __import("core/sfx")
local Theme = __import("ui/theme")
local B = __import("ui/base")
local T = B.T
local tween, new, corner, pad, bind, mkStroke, text, makeSwitch = B.tween, B.new, B.corner, B.pad, B.bind, B.mkStroke, B.text, B.makeSwitch
local row, rowLabel, register = B.row, B.rowLabel, B.register
local WHITE, BLACK = B.WHITE, B.BLACK
local guiParent, colorHex, hexColor = B.guiParent, B.colorHex, B.hexColor

local W, H = 1000, 640
local SIDE_W, TOP_H = 228, 74 -- SIDE_W includes the 10 px margin round the floating sidebar

local UI = {}
UI.__index = UI

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
	-- soft drop shadow: stacked rounded frames, very transparent
	for i = 4, 1, -1 do
		new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, 6), Size = UDim2.new(1, i * 9, 1, i * 9), BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.8 + i * 0.045, BorderSizePixel = 0, ZIndex = 0, Parent = holder }, { corner(18 + i * 4) })
	end
	local root = new("Frame", { Name = "Window", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ClipsDescendants = true, Parent = holder }, { corner(18) })
	bind(self, root, "BackgroundColor3", "bg")
	mkStroke(self, "stroke", 0).Parent = root
	self.root = holder
	self.window = root

	pcall(function()
		local b = Instance.new("BlurEffect")
		b.Name = "ScrdsxGlass"; b.Size = 0; b.Parent = Lighting
		self.blur = b
	end)
	self.scale = new("UIScale", { Scale = .94, Parent = holder })
	do
		local cam = workspace.CurrentCamera
		local vh = cam and cam.ViewportSize.Y or 800
		self.autoScale = math.clamp(vh / 860, 0.85, 1.35)
		self.baseScale = self.autoScale
	end

	-- SIDEBAR (a floating panel inside the window) ------------------------------------------------------------------------------
	local side = new("Frame", { Name = "Side", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(0, SIDE_W - 10, 1, -20), BorderSizePixel = 0, Parent = root }, { corner(14) })
	bind(self, side, "BackgroundColor3", "side")
	mkStroke(self, "stroke", 0).Parent = side

	local brand = new("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Parent = side })
	Logo.Make(brand, 30, UDim2.fromOffset(16, 17))
	local title = text(self, opts.Title or "Window", 17, "text", T.bold); title.Position = UDim2.fromOffset(56, 15); title.Size = UDim2.new(1, -62, 0, 18); title.TextWrapped = false; title.Parent = brand
	local sub = text(self, opts.Subtitle or "", 11, "dim"); sub.Position = UDim2.fromOffset(56, 34); sub.Size = UDim2.new(1, -62, 0, 14); sub.TextWrapped = false; sub.TextTruncate = Enum.TextTruncate.AtEnd; sub.Parent = brand
	local brandLine = new("Frame", { Position = UDim2.new(0, 14, 0, 63), Size = UDim2.new(1, -28, 0, 1), BorderSizePixel = 0, Parent = side })
	bind(self, brandLine, "BackgroundColor3", "stroke")

	local NAV_Y = 70
	local nav = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, NAV_Y), Size = UDim2.new(1, 0, 1, -NAV_Y - 70), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y, Parent = side,
	})
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav })
	pad(10, 10, 2, 8).Parent = nav
	self.nav = nav

	-- you: a small profile card at the bottom of the sidebar
	local lp = Players.LocalPlayer
	local me = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.new(1, -20, 0, 52), BorderSizePixel = 0, Parent = side }, { corner(11) })
	bind(self, me, "BackgroundColor3", "panel")
	mkStroke(self, "stroke", 0).Parent = me
	local av = new("ImageLabel", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 10, .5, 0), Size = UDim2.fromOffset(32, 32), BorderSizePixel = 0, Image = "", Parent = me }, { corner(16) })
	bind(self, av, "BackgroundColor3", "elem")
	local online = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(10, 10), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(70, 210, 130), ZIndex = 2, Parent = av }, { corner(5) })
	local onStroke = new("UIStroke", { Thickness = 2, Parent = online }); bind(self, onStroke, "Color", "panel")
	task.spawn(function() pcall(function() av.Image = Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) end) end)
	local pn = text(self, lp.DisplayName, 13, "text", T.bold); pn.Position = UDim2.fromOffset(52, 9); pn.Size = UDim2.new(1, -60, 0, 16); pn.TextWrapped = false; pn.TextTruncate = Enum.TextTruncate.AtEnd; pn.Parent = me
	local ph = text(self, "@" .. lp.Name, 11, "dim"); ph.Position = UDim2.fromOffset(52, 26); ph.Size = UDim2.new(1, -60, 0, 14); ph.TextWrapped = false; ph.TextTruncate = Enum.TextTruncate.AtEnd; ph.Parent = me

	-- HEADER ----------------------------------------------------------------------------------------------------------------
	local top = new("Frame", { Position = UDim2.fromOffset(SIDE_W, 0), Size = UDim2.new(1, -SIDE_W, 0, TOP_H), BackgroundTransparency = 1, Parent = root })
	self.pageTitle = text(self, "", 22, "text", T.bold); self.pageTitle.Position = UDim2.fromOffset(18, 17); self.pageTitle.Size = UDim2.new(.5, 0, 0, 26); self.pageTitle.TextWrapped = false; self.pageTitle.Parent = top
	self.pageSub = text(self, "", 12, "dim"); self.pageSub.Position = UDim2.fromOffset(19, 44); self.pageSub.Size = UDim2.new(.5, 0, 0, 14); self.pageSub.TextWrapped = false; self.pageSub.Parent = top

	-- right side of the header: search, live stats, close (one row, right-aligned)
	local bar = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -18, .5, 0), Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = top })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })

	local sb = new("Frame", { Size = UDim2.fromOffset(230, 36), BorderSizePixel = 0, LayoutOrder = 1, Parent = bar }, { corner(10) })
	bind(self, sb, "BackgroundColor3", "panel")
	local sbStroke = mkStroke(self, "stroke", 0); sbStroke.Parent = sb
	local glass = text(self, "⌕", 16, "dim", T.bold, Enum.TextXAlignment.Center); glass.Position = UDim2.fromOffset(6, 0); glass.Size = UDim2.fromOffset(24, 36); glass.TextWrapped = false; glass.Parent = sb
	local box = new("TextBox", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -66, 1, 0), Position = UDim2.fromOffset(32, 0), Text = "", PlaceholderText = "Search modules", ClearTextOnFocus = false,
		Font = T.font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = sb,
	})
	bind(self, box, "TextColor3", "text"); bind(self, box, "PlaceholderColor3", "dim")
	local hintBg = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0), Size = UDim2.fromOffset(22, 20), BorderSizePixel = 0, Parent = sb }, { corner(6) })
	bind(self, hintBg, "BackgroundColor3", "elem")
	local hint = text(self, "/", 11, "sub", T.bold, Enum.TextXAlignment.Center); hint.Size = UDim2.fromScale(1, 1); hint.TextWrapped = false; hint.Parent = hintBg
	self.searchBox = box
	box.Focused:Connect(function() tween(sbStroke, .15, { Color = T.accent }); tween(glass, .15, { TextColor3 = T.accent }); tween(hintBg, .15, { BackgroundTransparency = 1 }); tween(hint, .15, { TextTransparency = 1 }) end)
	box.FocusLost:Connect(function()
		tween(sbStroke, .15, { Color = T.stroke }); tween(glass, .15, { TextColor3 = T.dim })
		if box.Text == "" then tween(hintBg, .15, { BackgroundTransparency = 0 }); tween(hint, .15, { TextTransparency = 0 }) end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function() self:_search(box.Text) end)

	-- live stats chip (fps / ping), refreshed once a second
	local stat = new("Frame", { Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, LayoutOrder = 2, Parent = bar }, { corner(10), pad(12, 12, 0, 0) })
	bind(self, stat, "BackgroundColor3", "panel")
	mkStroke(self, "stroke", 0).Parent = stat
	local dot = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(7, 7), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(70, 210, 130), Parent = stat }, { corner(4) })
	local statL = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(15, 0), Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Text = "-- fps", RichText = true,
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
					statL.Text = ("<b>%d</b> fps%s"):format(fps, ping and ("  ·  <b>%d</b> ms"):format(ping) or "")
					dot.BackgroundColor3 = fps >= 50 and Color3.fromRGB(70, 210, 130) or (fps >= 30 and Color3.fromRGB(240, 180, 60) or Color3.fromRGB(235, 80, 80))
				end
			end
		end)
	end

	local close = new("TextButton", { Size = UDim2.fromOffset(36, 36), BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = 3, Parent = bar }, { corner(10) })
	bind(self, close, "BackgroundColor3", "panel")
	mkStroke(self, "stroke", 0).Parent = close
	local cx = text(self, "×", 19, "sub", T.bold, Enum.TextXAlignment.Center); cx.Size = UDim2.fromScale(1, 1); cx.TextWrapped = false; cx.Parent = close
	close.MouseEnter:Connect(function() tween(close, .12, { BackgroundColor3 = Color3.fromRGB(200, 64, 64) }); tween(cx, .12, { TextColor3 = WHITE }) end)
	close.MouseLeave:Connect(function() tween(close, .12, { BackgroundColor3 = T.panel }); tween(cx, .12, { TextColor3 = T.sub }) end)
	close.MouseButton1Click:Connect(function() Sfx.Play("click"); self:SetVisible(false) end)

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
		top.InputBegan:Connect(function(i) begin(i, { bar }) end)
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
		Position = UDim2.fromOffset(SIDE_W, TOP_H), Size = UDim2.new(1, -SIDE_W, 1, -TOP_H), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = root,
	})
	bind(self, content, "ScrollBarImageColor3", "off")
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	pad(18, 20, 2, 22).Parent = content
	self.content = content
	self.panel = { mod = nil } -- v3 compatibility (the drawer is gone; settings open inside the card)

	-- OVERLAY (dropdown lists, colour popups) ----------------------------------------------------------------------------
	self.overlay = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 50, Parent = gui })

	-- TOASTS (bottom centre) + MODULE LIST (top right) ------------------------------------------------------------------------
	self.toasts = new("Frame", { AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -96), Size = UDim2.fromOffset(380, 420), BackgroundTransparency = 1, Parent = gui })
	new("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = self.toasts })
	self.array = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(320, 600), BackgroundTransparency = 1, Parent = gui })
	new("UIListLayout", { Padding = UDim.new(0, 3), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.array })

	tween(self.scale, .4, { Scale = self.baseScale }, Enum.EasingStyle.Quint)
	Sfx.Preload()
	task.delay(.1, function() Sfx.Play("open") end)
	if self.blur and self.blurSize > 0 then tween(self.blur, .4, { Size = self.blurSize }) end
	return self
end

-- TABS ----------------------------------------------------------------------------------------------------------------------
-- opts: { Icon = n, Section = "Combat" }. Tabs with the same Section sit together under one small heading.
-- A tab is a pill: a small icon tile, the name and a count of modules that are on. The open tab is tinted with the accent.
function UI:Tab(name, opts)
	opts = opts or {}
	local idx = #self.tabs + 1
	self.navOrder = self.navOrder + 1
	if opts.Section and opts.Section ~= self.lastNavSection then
		self.lastNavSection = opts.Section
		local h = text(self, opts.Section:upper(), 10, "dim", T.bold)
		h.Size = UDim2.new(1, 0, 0, self.navOrder == 1 and 22 or 30); h.LayoutOrder = self.navOrder; h.TextWrapped = false; h.TextYAlignment = Enum.TextYAlignment.Bottom
		h.Parent = self.nav
		pad(8, 0, 0, 6).Parent = h
		self.navOrder = self.navOrder + 1
	end
	local tab
	local function isOn() return self.active == tab end
	local btn = new("TextButton", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", LayoutOrder = self.navOrder, BorderSizePixel = 0, Parent = self.nav }, { corner(10) })
	bind(self, btn, "BackgroundColor3", function() return isOn() and T.accentDim or T.elem end)
	local tile = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 6, .5, 0), Size = UDim2.fromOffset(26, 26), BorderSizePixel = 0, Parent = btn }, { corner(8) })
	bind(self, tile, "BackgroundColor3", function() return isOn() and T.accent or T.elem end)
	local ico = opts.Icon and Icons.Make(tile, opts.Icon, 15, UDim2.new(.5, -7.5, .5, -7.5))
	if ico then
		bind(self, ico, "ImageColor3", function() return isOn() and T.bg or T.sub end)
	else
		ico = nil
		local letter = text(self, name:sub(1, 1):upper(), 12, "sub", T.bold, Enum.TextXAlignment.Center); letter.Size = UDim2.fromScale(1, 1); letter.TextWrapped = false; letter.Parent = tile
		bind(self, letter, "TextColor3", function() return isOn() and T.bg or T.sub end)
	end
	local txt = text(self, name, 13, "sub", T.semi); txt.Position = UDim2.fromOffset(42, 0); txt.Size = UDim2.new(1, -42 - 32, 1, 0); txt.TextWrapped = false; txt.TextTruncate = Enum.TextTruncate.AtEnd; txt.Parent = btn
	bind(self, txt, "TextColor3", function() return isOn() and T.text or T.sub end)
	-- how many modules of this tab are on
	local badge = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0), Size = UDim2.fromOffset(20, 18), BorderSizePixel = 0, Visible = false, Parent = btn }, { corner(9) })
	bind(self, badge, "BackgroundColor3", function() return isOn() and T.bg or T.accentDim end)
	local badgeT = text(self, "", 10, "chip", T.bold, Enum.TextXAlignment.Center); badgeT.Size = UDim2.fromScale(1, 1); badgeT.TextWrapped = false; badgeT.Parent = badge

	local page = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = idx, Visible = false, Parent = self.content })
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	local header = text(self, name:upper(), 11, "dim", T.bold)
	header.Size = UDim2.new(1, 0, 0, 22); header.LayoutOrder = -1; header.Visible = false; header.TextWrapped = false; header.TextYAlignment = Enum.TextYAlignment.Bottom; header.Parent = page

	tab = { name = name, btn = btn, txt = txt, ico = ico, tile = tile, badge = badge, page = page, header = header, win = self, index = idx, iconIdx = opts.Icon, modCount = 0, onCount = 0 }
	tab.refreshBadge = function()
		badge.Visible = tab.onCount > 0
		badgeT.Text = tostring(tab.onCount)
		if self.active == tab then self:_pageSub(tab) end
	end
	setmetatable(tab, { __index = UI.TabMethods })
	table.insert(self.tabs, tab)

	btn.MouseEnter:Connect(function()
		if self.active ~= tab then tween(btn, .12, { BackgroundTransparency = .35 }); tween(txt, .12, { TextColor3 = T.text }) end
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
	if tab.onCount > 0 then parts[#parts + 1] = tab.onCount .. " active" end
	self.pageSub.Text = #parts > 0 and table.concat(parts, "  ·  ") or "Settings"
end

function UI:Select(tab)
	self.active = tab
	self:_closePopup()
	for _, t in ipairs(self.tabs) do
		local on = t == tab
		t.btn.BackgroundColor3 = on and T.accentDim or T.elem
		tween(t.btn, .18, { BackgroundTransparency = on and 0 or 1 })
		tween(t.tile, .18, { BackgroundColor3 = on and T.accent or T.elem })
		tween(t.txt, .18, { TextColor3 = on and T.text or T.sub })
		if t.ico then tween(t.ico, .18, { ImageColor3 = on and T.bg or T.sub }) end
		for _, c in ipairs(t.tile:GetChildren()) do
			if c:IsA("TextLabel") then tween(c, .18, { TextColor3 = on and T.bg or T.sub }) end
		end
		t.badge.BackgroundColor3 = on and T.bg or T.accentDim
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
	info = { color = Color3.fromRGB(110, 190, 255), sound = "notify", title = "Info", glyph = "i" },
	success = { color = Color3.fromRGB(72, 214, 140), sound = "success", title = "Done", glyph = "✓" },
	warn = { color = Color3.fromRGB(245, 110, 90), sound = "warn", title = "Heads up", glyph = "!" },
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
	-- a card at the bottom centre: round icon in the kind's colour, the message, a thin timer line. Rises in, fades out.
	local slot = new("Frame", { Size = UDim2.fromOffset(360, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = self.toasts })
	local card = new("CanvasGroup", { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, GroupTransparency = 1, Parent = slot }, { corner(14) })
	bind(self, card, "BackgroundColor3", "panel")
	mkStroke(self, "stroke", 0).Parent = card
	local icon = new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = K.color, BackgroundTransparency = 0.82, BorderSizePixel = 0, Parent = card }, { corner(13) })
	new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = K.glyph, Font = T.bold, TextSize = 13, TextColor3 = K.color, Parent = icon })
	local body = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = card }, { pad(48, 14, 10, 13) })
	new("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	local head = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 15), Text = K.title, Font = T.bold, TextSize = 12, TextColor3 = K.color,
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = body })
	local l = text(self, str, 13, "text"); l.Size = UDim2.new(1, 0, 0, 0); l.AutomaticSize = Enum.AutomaticSize.Y; l.LayoutOrder = 2; l.Parent = body
	local track = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -1), Size = UDim2.new(1, -28, 0, 2), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = card })
	local bar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.color, BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = track }, { corner(1) })
	tween(card, .35, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, Enum.EasingStyle.Quint)
	tween(bar, seconds, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	task.delay(seconds, function()
		if not slot.Parent then return end
		tween(card, .25, { Position = UDim2.fromOffset(0, 10), GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.wait(.27)
		pcall(function() slot:Destroy() end)
	end)
	return head
end

-- MODULE LIST (HUD) -----------------------------------------------------------------------------------------------------------
-- every module that is on, longest name first, top right of the screen. Rebuilt only when a module changes (never per frame).
-- Each entry is a small rounded chip with an accent dot; the dots run from the accent to its light tint down the list.
function UI:_refreshArray()
	local arr = self.array
	if not arr then return end
	for _, c in ipairs(arr:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	if not self.arrayOn then return end
	local list = {}
	for _, m in ipairs(self.modules) do
		if m.get() and not m.hidden then
			local w = 0
			pcall(function() w = TextService:GetTextSize(m.name, 13, T.semi, Vector2.new(1000, 40)).X end)
			list[#list + 1] = { name = m.name, w = w }
		end
	end
	table.sort(list, function(a, b) return a.w > b.w end)
	for i, e in ipairs(list) do
		local row = new("Frame", { Size = UDim2.fromOffset(e.w + 34, 24), BackgroundColor3 = T.bg, BackgroundTransparency = 0.18, BorderSizePixel = 0, LayoutOrder = i, Parent = arr }, { corner(7) })
		new("UIStroke", { Color = WHITE, Transparency = 0.93, Thickness = 1, Parent = row })
		new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 10, .5, 0), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = T.accent:Lerp(T.chip, (i - 1) / math.max(#list - 1, 1)), BorderSizePixel = 0, Parent = row }, { corner(3) })
		new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -28, 1, 0), Text = e.name, Font = T.semi, TextSize = 13,
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

-- THEME -----------------------------------------------------------------------------------------------------------------------
UI.Palette, UI.Remap, UI.PaletteMap = Theme.Palette, Theme.Remap, Theme.PaletteMap
-- applies a palette: every bound colour is recomputed; returns the colour map so the HUD can follow
function UI:ApplyPalette(P)
	local map = Theme.PaletteMap(Theme.cur, P)
	for _, k in ipairs(Theme.KEYS) do if P[k] then T[k] = P[k]; Theme.cur[k] = P[k] end end
	for _, b in ipairs(self.binds) do
		pcall(function() b[1][b[2]] = b[3]() end)
	end
	self:_refreshArray()
	return map
end

UI.Theme = T
return UI

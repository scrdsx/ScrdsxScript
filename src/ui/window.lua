-- UI window (v6 "Mocha"): top bar (logo, search, fps / ping, close), a horizontal tab strip with a sliding cream pill, page title, the
-- scrolling page; plus search, toasts, the module list HUD, show / hide / scale / blur, config get / apply and theme switching.
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

local W, H = 920, 600
local TOP_H, STRIP_H, HEAD_H = 60, 48, 58 -- brand bar, tab strip, page title row

local UI = {}
UI.__index = UI

-- v6 "Mocha" layout: no sidebar. A top bar (logo + name, search, fps / ping, close), under it one horizontal strip of tab pills with
-- a cream pill that slides to the open tab, then the page title and the scrolling page.
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
	-- one soft shadow (two frames, cheap)
	for i = 2, 1, -1 do
		new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(.5, 0, .5, 8), Size = UDim2.new(1, i * 16, 1, i * 16), BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.78 + i * 0.08, BorderSizePixel = 0, ZIndex = 0, Parent = holder }, { corner(16 + i * 8) })
	end
	local root = new("Frame", { Name = "Window", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ClipsDescendants = true, Parent = holder }, { corner(16) })
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
		self.autoScale = math.clamp(vh / 840, 0.85, 1.35)
		self.baseScale = self.autoScale
	end

	-- TOP BAR ------------------------------------------------------------------------------------------------------------------
	local top = new("Frame", { Size = UDim2.new(1, 0, 0, TOP_H), BackgroundTransparency = 1, Parent = root })
	Logo.Make(top, 28, UDim2.fromOffset(20, 16))
	local title = text(self, opts.Title or "Window", 17, "text", T.bold); title.Position = UDim2.fromOffset(58, 13); title.Size = UDim2.fromOffset(220, 18); title.TextWrapped = false; title.Parent = top
	local sub = text(self, opts.Subtitle or "", 11, "dim"); sub.Position = UDim2.fromOffset(58, 32); sub.Size = UDim2.fromOffset(260, 14); sub.TextWrapped = false; sub.TextTruncate = Enum.TextTruncate.AtEnd; sub.Parent = top

	local bar = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -16, .5, 0), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = top })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })

	local sb = new("Frame", { Size = UDim2.fromOffset(210, 34), BorderSizePixel = 0, LayoutOrder = 1, Parent = bar }, { corner(17) })
	bind(self, sb, "BackgroundColor3", "panel")
	local sbStroke = mkStroke(self, "stroke", 0); sbStroke.Parent = sb
	local glass = text(self, "⌕", 15, "dim", T.bold, Enum.TextXAlignment.Center); glass.Position = UDim2.fromOffset(8, 0); glass.Size = UDim2.fromOffset(22, 34); glass.TextWrapped = false; glass.Parent = sb
	local box = new("TextBox", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -62, 1, 0), Position = UDim2.fromOffset(32, 0), Text = "", PlaceholderText = "Search", ClearTextOnFocus = false,
		Font = T.font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = sb,
	})
	bind(self, box, "TextColor3", "text"); bind(self, box, "PlaceholderColor3", "dim")
	local hint = text(self, "/", 11, "dim", T.bold, Enum.TextXAlignment.Center); hint.AnchorPoint = Vector2.new(1, .5); hint.Position = UDim2.new(1, -12, .5, 0); hint.Size = UDim2.fromOffset(14, 14); hint.TextWrapped = false; hint.Parent = sb
	self.searchBox = box
	box.Focused:Connect(function() tween(sbStroke, .15, { Color = T.strokeOn }); tween(glass, .15, { TextColor3 = T.accent }); tween(hint, .15, { TextTransparency = 1 }) end)
	box.FocusLost:Connect(function()
		tween(sbStroke, .15, { Color = T.stroke }); tween(glass, .15, { TextColor3 = T.dim })
		if box.Text == "" then tween(hint, .15, { TextTransparency = 0 }) end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function() self:_search(box.Text) end)

	-- fps / ping, once a second, only written while the window is open
	local stat = new("Frame", { Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, LayoutOrder = 2, Parent = bar }, { corner(17), pad(14, 14, 0, 0) })
	bind(self, stat, "BackgroundColor3", "panel")
	mkStroke(self, "stroke", 0).Parent = stat
	local dot = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(150, 214, 140), Parent = stat }, { corner(3) })
	local statL = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(13, 0), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, Text = "-- fps",
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
					statL.Text = ping and ("%d fps  ·  %d ms"):format(fps, ping) or ("%d fps"):format(fps)
					dot.BackgroundColor3 = fps >= 50 and Color3.fromRGB(150, 214, 140) or (fps >= 30 and Color3.fromRGB(236, 190, 100) or Color3.fromRGB(230, 110, 96))
				end
			end
		end)
	end

	local close = new("TextButton", { Size = UDim2.fromOffset(34, 34), BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = 3, Parent = bar }, { corner(17) })
	bind(self, close, "BackgroundColor3", "panel")
	mkStroke(self, "stroke", 0).Parent = close
	local cx = text(self, "×", 18, "sub", T.bold, Enum.TextXAlignment.Center); cx.Size = UDim2.fromScale(1, 1); cx.TextWrapped = false; cx.Parent = close
	close.MouseEnter:Connect(function() tween(close, .12, { BackgroundColor3 = Color3.fromRGB(190, 82, 70) }); tween(cx, .12, { TextColor3 = WHITE }) end)
	close.MouseLeave:Connect(function() tween(close, .12, { BackgroundColor3 = T.panel }); tween(cx, .12, { TextColor3 = T.sub }) end)
	close.MouseButton1Click:Connect(function() Sfx.Play("click"); self:SetVisible(false) end)

	-- TAB STRIP --------------------------------------------------------------------------------------------------------------
	local strip = new("Frame", { Position = UDim2.fromOffset(12, TOP_H), Size = UDim2.new(1, -24, 0, STRIP_H), BorderSizePixel = 0, Parent = root }, { corner(14) })
	bind(self, strip, "BackgroundColor3", "side")
	mkStroke(self, "stroke", 0).Parent = strip
	local nav = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0, AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.X, Parent = strip,
	})
	-- the sliding cream pill behind the open tab (ZIndex 1, the pills sit on 2)
	local pill = new("Frame", { Position = UDim2.fromOffset(6, 7), Size = UDim2.fromOffset(0, STRIP_H - 14), BorderSizePixel = 0, ZIndex = 1, Parent = nav }, { corner(10) })
	bind(self, pill, "BackgroundColor3", "accent")
	self.pill = pill
	local list = new("Frame", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 2, Parent = nav })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	pad(6, 6, 0, 0).Parent = list
	self.nav, self.navList = nav, list

	-- drag by the top bar
	do
		local dragging, start, origin
		top.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				local p, a, z = i.Position, bar.AbsolutePosition, bar.AbsoluteSize
				if p.X >= a.X and p.X <= a.X + z.X and p.Y >= a.Y and p.Y <= a.Y + z.Y then return end
				dragging, start, origin = true, i.Position, holder.Position
			end
		end)
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

	-- PAGE TITLE + CONTENT ------------------------------------------------------------------------------------------------------
	local y0 = TOP_H + STRIP_H
	local head = new("Frame", { Position = UDim2.fromOffset(0, y0), Size = UDim2.new(1, 0, 0, HEAD_H), BackgroundTransparency = 1, Parent = root })
	self.pageTitle = text(self, "", 20, "text", T.bold); self.pageTitle.Position = UDim2.fromOffset(24, 16); self.pageTitle.Size = UDim2.new(.6, 0, 0, 24); self.pageTitle.TextWrapped = false; self.pageTitle.Parent = head
	self.pageSub = text(self, "", 12, "dim"); self.pageSub.AnchorPoint = Vector2.new(1, 0); self.pageSub.Position = UDim2.new(1, -24, 0, 22); self.pageSub.Size = UDim2.new(.4, 0, 0, 14)
	self.pageSub.TextXAlignment = Enum.TextXAlignment.Right; self.pageSub.TextWrapped = false; self.pageSub.Parent = head

	local content = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, y0 + HEAD_H), Size = UDim2.new(1, 0, 1, -(y0 + HEAD_H)), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = root,
	})
	bind(self, content, "ScrollBarImageColor3", "off")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	pad(20, 22, 0, 20).Parent = content
	self.content = content
	self.panel = { mod = nil }

	-- OVERLAY (dropdown lists, colour popups) ----------------------------------------------------------------------------
	self.overlay = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 50, Parent = gui })

	-- TOASTS (top centre, drop down) + MODULE LIST (top right) ------------------------------------------------------------------
	self.toasts = new("Frame", { AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 18), Size = UDim2.fromOffset(380, 420), BackgroundTransparency = 1, Parent = gui })
	new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.toasts })
	self.toastN = 0
	self.array = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(320, 600), BackgroundTransparency = 1, Parent = gui })
	new("UIListLayout", { Padding = UDim.new(0, 0), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.array })

	tween(self.scale, .4, { Scale = self.baseScale }, Enum.EasingStyle.Quint)
	Sfx.Preload()
	task.delay(.1, function() Sfx.Play("open") end)
	if self.blur and self.blurSize > 0 then tween(self.blur, .4, { Size = self.blurSize }) end
	return self
end

-- TABS ----------------------------------------------------------------------------------------------------------------------
-- opts: { Icon = n, Section = "Combat" }. A tab is a pill in the strip (icon + name + a small count when modules are on); a thin
-- divider separates sections. The open tab sits on the sliding cream pill (dark text on cream).
function UI:Tab(name, opts)
	opts = opts or {}
	local idx = #self.tabs + 1
	if opts.Section and opts.Section ~= self.lastNavSection then
		if self.lastNavSection then
			local function gap(w) self.navOrder = self.navOrder + 1; return new("Frame", { Size = UDim2.fromOffset(w, 1), BackgroundTransparency = 1, LayoutOrder = self.navOrder, Parent = self.navList }) end
			gap(5)
			self.navOrder = self.navOrder + 1
			local div = new("Frame", { Size = UDim2.fromOffset(1, 18), BorderSizePixel = 0, LayoutOrder = self.navOrder, Parent = self.navList })
			bind(self, div, "BackgroundColor3", "stroke")
			gap(5)
		end
		self.lastNavSection = opts.Section
	end
	self.navOrder = self.navOrder + 1
	local tab
	local btn = new("TextButton", { Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", LayoutOrder = self.navOrder, BorderSizePixel = 0, ZIndex = 2, Parent = self.navList }, { corner(10) })
	pad(12, 12, 0, 0).Parent = btn
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder, Parent = btn })
	local ico = opts.Icon and Icons.Make(btn, opts.Icon, 14, UDim2.new())
	local function onCol() return self.active == tab and T.bg or T.sub end
	if ico then ico.LayoutOrder = 1; ico.ZIndex = 3; bind(self, ico, "ImageColor3", onCol) end
	local txt = text(self, name, 13, "sub", T.semi); txt.Size = UDim2.fromOffset(0, 34); txt.AutomaticSize = Enum.AutomaticSize.X; txt.TextWrapped = false; txt.LayoutOrder = 2; txt.ZIndex = 3; txt.Parent = btn
	bind(self, txt, "TextColor3", onCol)
	local badge = text(self, "", 11, "dim", T.bold); badge.Size = UDim2.fromOffset(0, 34); badge.AutomaticSize = Enum.AutomaticSize.X; badge.TextWrapped = false; badge.LayoutOrder = 3; badge.ZIndex = 3; badge.Visible = false; badge.Parent = btn

	local page = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = idx, Visible = false, Parent = self.content })
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	local header = text(self, name:upper(), 11, "dim", T.bold)
	header.Size = UDim2.new(1, 0, 0, 22); header.LayoutOrder = -1; header.Visible = false; header.TextWrapped = false; header.TextYAlignment = Enum.TextYAlignment.Bottom; header.Parent = page

	tab = { name = name, btn = btn, txt = txt, ico = ico, badge = badge, page = page, header = header, win = self, index = idx, iconIdx = opts.Icon, modCount = 0, onCount = 0 }
	tab.refreshBadge = function()
		badge.Visible = tab.onCount > 0
		badge.Text = tostring(tab.onCount)
		if self.active == tab then self:_pageSub(tab) end
	end
	setmetatable(tab, { __index = UI.TabMethods })
	table.insert(self.tabs, tab)

	btn.MouseEnter:Connect(function()
		if self.active ~= tab then tween(txt, .12, { TextColor3 = T.text }); if ico then tween(ico, .12, { ImageColor3 = T.text }) end end
	end)
	btn.MouseLeave:Connect(function()
		if self.active ~= tab then tween(txt, .12, { TextColor3 = T.sub }); if ico then tween(ico, .12, { ImageColor3 = T.sub }) end end
	end)
	btn.MouseButton1Click:Connect(function()
		if self.searchBox.Text ~= "" then self.searchBox.Text = "" end
		if self.active ~= tab then Sfx.Play("tab") end
		self:Select(tab)
	end)
	-- the pill follows the open button whenever the strip lays out again (first open, more tabs added, font load)
	btn:GetPropertyChangedSignal("AbsolutePosition"):Connect(function() if self.active == tab then self:_movePill(false) end end)
	btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if self.active == tab then self:_movePill(false) end end)
	if not self.active then self:Select(tab) end
	return tab
end

-- pill position in the strip's own (unscaled) pixels
function UI:_movePill(animate)
	local tab = self.active
	if not (tab and self.pill) then return end
	local b, l = tab.btn, self.navList
	local s = self.scale and self.scale.Scale or 1
	if s <= 0 then return end
	local x = (b.AbsolutePosition.X - l.AbsolutePosition.X) / s
	local w = b.AbsoluteSize.X / s
	if w < 1 then return end
	local goal = { Position = UDim2.fromOffset(x, 7), Size = UDim2.fromOffset(w, STRIP_H - 14) }
	if animate then tween(self.pill, .32, goal, Enum.EasingStyle.Quart) else self.pill.Position = goal.Position; self.pill.Size = goal.Size end
end

function UI:_pageSub(tab)
	local parts = {}
	if tab.modCount > 0 then parts[#parts + 1] = tab.modCount .. (tab.modCount == 1 and " module" or " modules") end
	if tab.onCount > 0 then parts[#parts + 1] = tab.onCount .. " on" end
	self.pageSub.Text = #parts > 0 and table.concat(parts, "  ·  ") or ""
end

function UI:Select(tab)
	local animate = self.active ~= nil
	self.active = tab
	self:_closePopup()
	for _, t in ipairs(self.tabs) do
		local on = t == tab
		tween(t.txt, .2, { TextColor3 = on and T.bg or T.sub })
		if t.ico then tween(t.ico, .2, { ImageColor3 = on and T.bg or T.sub }) end
		t.badge.TextColor3 = on and T.accentDim or T.dim
		if not on then t.page.Visible = false end
	end
	self:_movePill(animate)
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
	info = { color = Color3.fromRGB(236, 211, 172), sound = "notify", title = "Info", glyph = "i" },
	success = { color = Color3.fromRGB(150, 214, 140), sound = "success", title = "Done", glyph = "✓" },
	warn = { color = Color3.fromRGB(236, 120, 96), sound = "warn", title = "Heads up", glyph = "!" },
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
	-- a slim espresso pill at the top centre: a coloured dot, the message, a hairline timer along the bottom. Drops in, fades out.
	self.toastN = (self.toastN or 0) + 1
	local slot = new("Frame", { Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = -self.toastN, Parent = self.toasts })
	local card = new("CanvasGroup", { Position = UDim2.fromOffset(0, -14), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, GroupTransparency = 1, Parent = slot }, { corner(20), pad(16, 18, 0, 0) })
	bind(self, card, "BackgroundColor3", "panel")
	mkStroke(self, "stroke", 0).Parent = card
	new("UISizeConstraint", { MaxSize = Vector2.new(520, 40), Parent = card })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
	new("Frame", { Size = UDim2.fromOffset(8, 8), BackgroundColor3 = K.color, BorderSizePixel = 0, LayoutOrder = 1, Parent = card }, { corner(4) })
	local l = text(self, str, 13, "text"); l.Size = UDim2.fromOffset(0, 40); l.AutomaticSize = Enum.AutomaticSize.X; l.TextWrapped = false; l.TextTruncate = Enum.TextTruncate.AtEnd; l.LayoutOrder = 2; l.Parent = card
	new("UISizeConstraint", { MaxSize = Vector2.new(470, 40), Parent = l })
	local bar = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -16, 1, 0), Size = UDim2.new(1, 34, 0, 2), BackgroundColor3 = K.color, BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = card })
	bar.Parent = slot; bar.Position = UDim2.new(0, 14, 1, -1); bar.Size = UDim2.new(1, -28, 0, 1); bar.ZIndex = 3
	tween(card, .32, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, Enum.EasingStyle.Quart)
	tween(bar, seconds, { Size = UDim2.new(0, 0, 0, 1) }, Enum.EasingStyle.Linear)
	task.delay(seconds, function()
		if not slot.Parent then return end
		tween(card, .22, { Position = UDim2.fromOffset(0, -8), GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		bar.Visible = false
		task.wait(.24)
		pcall(function() slot:Destroy() end)
	end)
	return l
end

-- MODULE LIST (HUD) -----------------------------------------------------------------------------------------------------------
-- every module that is on, longest name first, top right. Rebuilt only when a module changes (never per frame).
-- Plain right-aligned cream text on a soft dark strip with a thin cream bar on the right; the strips touch, so it reads as one block.
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
		local row = new("Frame", { Size = UDim2.fromOffset(e.w + 24, 22), BackgroundColor3 = T.bg, BackgroundTransparency = 0.3, BorderSizePixel = 0, LayoutOrder = i, Parent = arr })
		new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = T.accent:Lerp(T.gradA, (i - 1) / math.max(#list - 1, 1)), BorderSizePixel = 0, Parent = row })
		new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -17, 1, 0), Text = e.name, Font = T.semi, TextSize = 13,
			TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
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

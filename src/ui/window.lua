-- UI window: the window itself (sidebar with brand, search, tabs and you; header with title, fps / ping and close; the scrolling
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

local W, H = 980, 640
local SIDE_W, TOP_H = 212, 66

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

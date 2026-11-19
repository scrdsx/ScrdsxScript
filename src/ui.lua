-- Scrdsx UI library v2 (ground-up rewrite). Floating window: inset rail on the left (brand, grouped tabs, you), top bar (page title, search, close),
-- module cards in a grid, settings drawer that slides in from the right. Plain Frames only (a CanvasGroup under UIScale makes text soft).
-- Every themed colour is registered as a binding (win.binds) so changing the theme recolours everything, including elements that are mid-state.
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Logo = __import("logo")
local Icons = __import("icons")
local Sfx = __import("sfx")

local function pickFont(n, fb) local ok, f = pcall(function() return Enum.Font[n] end); return (ok and f) or fb end
local T = {
	bg = Color3.fromRGB(10, 10, 21),
	panel = Color3.fromRGB(17, 16, 33),
	elem = Color3.fromRGB(25, 24, 46),
	hover = Color3.fromRGB(38, 36, 68),
	stroke = Color3.fromRGB(56, 54, 96),
	text = Color3.fromRGB(242, 242, 252),
	sub = Color3.fromRGB(152, 152, 194),
	accent = Color3.fromRGB(139, 92, 246),
	accentDim = Color3.fromRGB(46, 34, 94),
	off = Color3.fromRGB(62, 60, 100),
	chip = Color3.fromRGB(200, 185, 255),
	gradA = Color3.fromRGB(124, 58, 237),
	gradB = Color3.fromRGB(56, 189, 248),
	strokeOn = Color3.fromRGB(112, 84, 210),
	font = pickFont("GothamMedium", Enum.Font.SourceSans),
	bold = pickFont("GothamBold", Enum.Font.SourceSansBold),
	semi = pickFont("GothamSemibold", Enum.Font.SourceSansBold),
}

local RAIL_W, TOP_H = 214, 82
local RADIUS = 16
local DRAWER_W = 372

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

-- themed values -------------------------------------------------------------------------------------------------------
-- bind(win, instance, "Property", "tokenName" | function() return value end): set now, and again whenever the theme changes
local function bind(win, inst, prop, f)
	local fn = type(f) == "string" and function() return T[f] end or f
	inst[prop] = fn()
	win.binds[#win.binds + 1] = { inst, prop, fn }
	return inst
end

local function gradBind(win, parent, rotation)
	local g = new("UIGradient", { Rotation = rotation or 0, Parent = parent })
	bind(win, g, "Color", function() return ColorSequence.new(T.gradA, T.gradB) end)
	return g
end

local function mkStroke(win, key, transparency, thickness)
	local s = new("UIStroke", { Thickness = thickness or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	bind(win, s, "Color", key or "stroke")
	return s
end

-- text label: Gotham, themed colour, wraps instead of cutting words off with "..."
local function text(win, str, size, key, font, align)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Text = str, TextSize = size or 13, Font = font or T.font, TextXAlignment = align or Enum.TextXAlignment.Left,
		TextWrapped = true, TextTruncate = Enum.TextTruncate.None, RichText = false,
	})
	bind(win, l, "TextColor3", key or "text")
	return l
end

function UI.new(opts)
	opts = opts or {}
	local self = setmetatable({ tabs = {}, rows = {}, sections = {}, conns = {}, flags = {}, binds = {}, active = nil, visible = true, baseScale = 1, autoScale = 1, navOrder = 0 }, UI)

	local gui = new("ScreenGui", {
		Name = tostring(math.random(1e6, 9e6)), ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
	})
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
	gui.Parent = guiParent()
	self.gui = gui

	local holder = new("Frame", { Name = "Root", Size = UDim2.fromOffset(1060, 660), AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = gui })
	local root = new("Frame", { Name = "Window", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 1, Parent = holder }, { corner(RADIUS) })
	bind(self, root, "BackgroundColor3", "bg"); root.BackgroundTransparency = 0.04
	local rstroke = new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = root })
	gradBind(self, rstroke, 45)
	new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(176, 180, 192)), Rotation = 125, Parent = root })
	self.root = holder
	self.window = root

	pcall(function()
		local b = Instance.new("BlurEffect")
		b.Name = "ScrdsxGlass"; b.Size = 0; b.Parent = Lighting
		self.blur = b
	end)
	self.scale = new("UIScale", { Scale = .92, Parent = holder })
	do
		local cam = workspace.CurrentCamera
		local vh = cam and cam.ViewportSize.Y or 800
		self.autoScale = math.clamp(vh / 800, 1, 1.6)
		self.baseScale = self.autoScale
	end

	-- RAIL ------------------------------------------------------------------------------------------------------------
	local rail = new("Frame", { Name = "Rail", Position = UDim2.fromOffset(12, 12), Size = UDim2.new(0, RAIL_W - 12, 1, -24), BorderSizePixel = 0, Parent = root }, { corner(12) })
	bind(self, rail, "BackgroundColor3", "panel"); rail.BackgroundTransparency = .1
	mkStroke(self, "stroke", .55).Parent = rail

	local brand = new("Frame", { Size = UDim2.new(1, 0, 0, 74), BackgroundTransparency = 1, Parent = rail })
	Logo.Make(brand, 38, UDim2.fromOffset(16, 18))
	local title = text(self, opts.Title or "Window", 16, "text", T.bold); title.Position = UDim2.fromOffset(64, 17); title.Size = UDim2.new(1, -72, 0, 20); title.TextWrapped = false; title.Parent = brand
	local sub = text(self, opts.Subtitle or "", 11, "sub"); sub.Position = UDim2.fromOffset(64, 38); sub.Size = UDim2.new(1, -72, 0, 14); sub.TextWrapped = false; sub.Parent = brand
	local railLine = new("Frame", { Position = UDim2.fromOffset(16, 74), Size = UDim2.new(1, -32, 0, 1), BorderSizePixel = 0, Parent = rail })
	bind(self, railLine, "BackgroundColor3", "stroke"); railLine.BackgroundTransparency = .5

	local nav = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, 0, 1, -82 - 66), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y, Parent = rail,
	})
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav })
	pad(10, 10, 2, 8).Parent = nav
	self.nav = nav

	-- you: avatar + name, bottom of the rail
	local lp = Players.LocalPlayer
	local me = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.new(1, -20, 0, 48), BorderSizePixel = 0, Parent = rail }, { corner(10) })
	bind(self, me, "BackgroundColor3", "elem"); me.BackgroundTransparency = .25
	local av = new("ImageLabel", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(32, 32), BorderSizePixel = 0, Image = "", Parent = me }, { corner(16) })
	bind(self, av, "BackgroundColor3", "hover")
	task.spawn(function() pcall(function() av.Image = Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) end) end)
	local pn = text(self, lp.DisplayName, 13, "text", T.semi); pn.Position = UDim2.fromOffset(48, 7); pn.Size = UDim2.new(1, -54, 0, 18); pn.TextWrapped = false; pn.TextTruncate = Enum.TextTruncate.AtEnd; pn.Parent = me
	local ph = text(self, "Right Shift: hide", 10, "sub"); ph.Position = UDim2.fromOffset(48, 25); ph.Size = UDim2.new(1, -54, 0, 14); ph.TextWrapped = false; ph.Parent = me

	-- TOP BAR ---------------------------------------------------------------------------------------------------------
	local top = new("Frame", { Position = UDim2.fromOffset(RAIL_W, 0), Size = UDim2.new(1, -RAIL_W, 0, TOP_H), BackgroundTransparency = 1, Parent = root })
	self.pageTitle = text(self, "", 26, "text", T.bold); self.pageTitle.TextColor3 = Color3.new(1, 1, 1); self.pageTitle.Position = UDim2.fromOffset(18, 17); self.pageTitle.Size = UDim2.new(.5, 0, 0, 30); self.pageTitle.TextWrapped = false; self.pageTitle.Parent = top
	do
		local tg = new("UIGradient", { Rotation = 0, Parent = self.pageTitle })
		bind(self, tg, "Color", function() return ColorSequence.new(Color3.new(1, 1, 1), T.chip) end)
	end
	self.pageSub = text(self, "", 12, "sub"); self.pageSub.Position = UDim2.fromOffset(19, 49); self.pageSub.Size = UDim2.new(.6, 0, 0, 16); self.pageSub.TextWrapped = false; self.pageSub.Parent = top

	local close = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 20), Size = UDim2.fromOffset(38, 38), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = top }, { corner(19) })
	bind(self, close, "BackgroundColor3", "elem"); close.BackgroundTransparency = .2
	local cx = text(self, "×", 22, "sub", T.bold, Enum.TextXAlignment.Center); cx.Size = UDim2.fromScale(1, 1); cx.TextWrapped = false; cx.Parent = close
	close.MouseEnter:Connect(function() tween(close, .15, { BackgroundColor3 = Color3.fromRGB(200, 62, 74), BackgroundTransparency = 0 }); tween(cx, .15, { TextColor3 = Color3.new(1, 1, 1) }) end)
	close.MouseLeave:Connect(function() tween(close, .15, { BackgroundColor3 = T.elem, BackgroundTransparency = .2 }); tween(cx, .15, { TextColor3 = T.sub }) end)
	close.MouseButton1Click:Connect(function() Sfx.Play("click"); self:SetVisible(false) end)

	local sb = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -66, 0, 20), Size = UDim2.fromOffset(250, 38), BorderSizePixel = 0, Parent = top }, { corner(19) })
	bind(self, sb, "BackgroundColor3", "elem"); sb.BackgroundTransparency = .2
	local sbStroke = mkStroke(self, "stroke", .5); sbStroke.Parent = sb
	local box = new("TextBox", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -56, 1, 0), Position = UDim2.fromOffset(18, 0), Text = "", PlaceholderText = "Search", ClearTextOnFocus = false,
		Font = T.font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = sb,
	})
	bind(self, box, "TextColor3", "text"); bind(self, box, "PlaceholderColor3", "sub")
	local hint = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), Size = UDim2.fromOffset(22, 22), BorderSizePixel = 0, Parent = sb }, { corner(11) })
	bind(self, hint, "BackgroundColor3", "hover")
	local hintTxt = text(self, "/", 12, "sub", T.bold, Enum.TextXAlignment.Center); hintTxt.Size = UDim2.fromScale(1, 1); hintTxt.TextWrapped = false; hintTxt.Parent = hint
	self.searchBox = box
	box.Focused:Connect(function()
		tween(sb, .25, { Size = UDim2.fromOffset(310, 38), BackgroundTransparency = 0 })
		tween(sbStroke, .2, { Color = T.accent, Transparency = .1 })
		tween(hint, .2, { BackgroundTransparency = 1 }); tween(hintTxt, .2, { TextTransparency = 1 })
	end)
	box.FocusLost:Connect(function()
		tween(sbStroke, .2, { Color = T.stroke, Transparency = .5 })
		if box.Text == "" then
			tween(sb, .25, { Size = UDim2.fromOffset(250, 38), BackgroundTransparency = .2 })
			tween(hint, .2, { BackgroundTransparency = 0 }); tween(hintTxt, .2, { TextTransparency = 0 })
		end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function() self:_search(box.Text) end)

	-- drag by the top bar and the brand
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
		top.InputBegan:Connect(function(i) begin(i, { sb, close }) end)
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

	-- CONTENT ---------------------------------------------------------------------------------------------------------
	local content = new("ScrollingFrame", {
		Position = UDim2.fromOffset(RAIL_W, TOP_H), Size = UDim2.new(1, -RAIL_W, 1, -TOP_H), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = root,
	})
	bind(self, content, "ScrollBarImageColor3", "off")
	new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	pad(18, 22, 4, 24).Parent = content
	self.content = content

	-- DRAWER (settings of one module) ------------------------------------------------------------------------------
	local drawer = new("Frame", {
		Name = "Drawer", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, DRAWER_W + 40, 0, 12), Size = UDim2.new(0, DRAWER_W, 1, -24), BorderSizePixel = 0, Visible = false, ZIndex = 5, Parent = root,
	}, { corner(14) })
	bind(self, drawer, "BackgroundColor3", "panel"); drawer.BackgroundTransparency = .02
	mkStroke(self, "stroke", .3).Parent = drawer
	local dtitle = text(self, "", 17, "text", T.bold); dtitle.Position = UDim2.fromOffset(20, 16); dtitle.Size = UDim2.new(1, -76, 0, 22); dtitle.TextWrapped = false; dtitle.TextTruncate = Enum.TextTruncate.AtEnd; dtitle.ZIndex = 6; dtitle.Parent = drawer
	local dsub = text(self, "", 12, "sub"); dsub.Position = UDim2.fromOffset(20, 41); dsub.Size = UDim2.new(1, -76, 0, 16); dsub.TextWrapped = false; dsub.ZIndex = 6; dsub.Parent = drawer
	local dclose = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(32, 32), BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 6, Parent = drawer }, { corner(16) })
	bind(self, dclose, "BackgroundColor3", "elem")
	local dcx = text(self, "×", 20, "sub", T.bold, Enum.TextXAlignment.Center); dcx.Size = UDim2.fromScale(1, 1); dcx.TextWrapped = false; dcx.ZIndex = 7; dcx.Parent = dclose
	dclose.MouseButton1Click:Connect(function() Sfx.Play("click"); self:ClosePanel() end)
	local dline = new("Frame", { Position = UDim2.fromOffset(16, 66), Size = UDim2.new(1, -32, 0, 1), BorderSizePixel = 0, ZIndex = 6, Parent = drawer })
	bind(self, dline, "BackgroundColor3", "stroke"); dline.BackgroundTransparency = .4
	local dbody = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 1, -74), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ZIndex = 6, Parent = drawer,
	})
	bind(self, dbody, "ScrollBarImageColor3", "off")
	pad(14, 16, 0, 16).Parent = dbody
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = dbody })
	self.panel = { frame = drawer, title = dtitle, sub = dsub, body = dbody, mod = nil, w = DRAWER_W }

	-- toasts
	self.toasts = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.fromOffset(340, 460), BackgroundTransparency = 1, Parent = gui })
	new("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = self.toasts })

	tween(self.scale, .5, { Scale = self.baseScale }, Enum.EasingStyle.Back)
	Sfx.Preload()
	task.delay(.1, function() Sfx.Play("open") end)
	if self.blur then tween(self.blur, .5, { Size = 14 }) end
	return self
end

-- TABS ----------------------------------------------------------------------------------------------------------------------
-- opts: { Icon = n, Section = "Combat" }. Tabs with the same Section sit together under one small heading in the rail.
function UI:Tab(name, opts)
	opts = opts or {}
	local idx = #self.tabs + 1
	self.navOrder = self.navOrder + 1
	if opts.Section and opts.Section ~= self.lastNavSection then
		self.lastNavSection = opts.Section
		local h = text(self, opts.Section:upper(), 10, "sub", T.bold)
		h.Size = UDim2.new(1, 0, 0, 24); h.LayoutOrder = self.navOrder; h.TextWrapped = false; h.TextTransparency = .15
		h.Parent = self.nav
		pad(10, 0, 10, 0).Parent = h
		self.navOrder = self.navOrder + 1
	end
	local btn = new("TextButton", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", LayoutOrder = self.navOrder, BorderSizePixel = 0, Parent = self.nav }, { corner(10) })
	bind(self, btn, "BackgroundColor3", "accentDim")
	local ico = opts.Icon and Icons.Make(btn, opts.Icon, 19, UDim2.new(0, 14, .5, -9.5))
	if ico then bind(self, ico, "ImageColor3", "sub") end
	local baseX = ico and 46 or 18
	local txt = text(self, name, 13.5, "sub"); txt.Position = UDim2.fromOffset(baseX, 0); txt.Size = UDim2.new(1, -baseX - 8, 1, 0); txt.TextWrapped = false; txt.Parent = btn
	local bar = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(3, 0), BorderSizePixel = 0, Parent = btn }, { corner(2) })
	bar.BackgroundColor3 = Color3.new(1, 1, 1); gradBind(self, bar, 90)

	local page = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = idx, Visible = false, Parent = self.content })
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	new("UIPadding", { Name = "SlidePad", Parent = page })
	local header = text(self, name:upper(), 11, "sub", T.bold)
	header.Size = UDim2.new(1, 0, 0, 18); header.LayoutOrder = -1; header.Visible = false; header.TextWrapped = false; header.Parent = page

	local tab = { name = name, btn = btn, txt = txt, ico = ico, bar = bar, page = page, header = header, win = self, index = idx, iconIdx = opts.Icon, modCount = 0 }
	setmetatable(tab, { __index = UI.TabMethods })
	table.insert(self.tabs, tab)

	btn.MouseEnter:Connect(function()
		if self.active ~= tab then tween(btn, .15, { BackgroundTransparency = .8, BackgroundColor3 = T.hover }); tween(txt, .15, { TextColor3 = T.text }) end
		Sfx.Play("hover", .4)
	end)
	btn.MouseLeave:Connect(function()
		if self.active ~= tab then tween(btn, .15, { BackgroundTransparency = 1 }); tween(txt, .15, { TextColor3 = T.sub }) end
	end)
	btn.MouseButton1Click:Connect(function()
		if self.searchBox.Text ~= "" then self.searchBox.Text = "" end
		if self.active ~= tab then Sfx.Play("tab") end
		self:Select(tab)
	end)
	if not self.active then self:Select(tab) end
	return tab
end

function UI:Select(tab)
	self.active = tab
	self:ClosePanel(true)
	for _, t in ipairs(self.tabs) do
		local on = t == tab
		tween(t.btn, .22, { BackgroundTransparency = on and .15 or 1, BackgroundColor3 = T.accentDim })
		tween(t.txt, .22, { TextColor3 = on and T.text or T.sub })
		if t.ico then tween(t.ico, .22, { ImageColor3 = on and T.accent or T.sub }) end
		tween(t.bar, .3, { Size = UDim2.fromOffset(3, on and 20 or 0) }, Enum.EasingStyle.Back)
		if not on then t.page.Visible = false end
	end
	self.pageTitle.Text = tab.name
	self.pageSub.Text = tab.modCount > 0 and (tab.modCount .. (tab.modCount == 1 and " module" or " modules")) or ""
	tab.page.Visible = true
	local pad_ = tab.page:FindFirstChild("SlidePad")
	if pad_ then pad_.PaddingTop = UDim.new(0, 16); tween(pad_, .4, { PaddingTop = UDim.new(0, 0) }, Enum.EasingStyle.Quint) end
	self.content.CanvasPosition = Vector2.zero
end

-- DRAWER ----------------------------------------------------------------------------------------------------------------------
function UI:OpenPanel(mod)
	local P = self.panel
	if P.mod and P.mod ~= mod then P.mod.sf.Visible = false; if P.mod.card then P.mod.card.setActive(false) end end
	P.mod = mod
	P.title.Text = mod.name
	local n = mod.count()
	P.sub.Text = (mod.tab and (mod.tab.name .. "  -  ") or "") .. n .. (n == 1 and " setting" or " settings")
	mod.sf.Visible = true
	if mod.card then mod.card.setActive(true) end
	P.body.CanvasPosition = Vector2.zero
	P.frame.Visible = true
	tween(P.frame, .34, { Position = UDim2.new(1, -12, 0, 12) }, Enum.EasingStyle.Quint)
	tween(self.content, .34, { Size = UDim2.new(1, -(RAIL_W + P.w + 24), 1, -TOP_H) }, Enum.EasingStyle.Quint)
	Sfx.Play("open", .45, 1.4)
end

function UI:ClosePanel(instant)
	local P = self.panel
	if not P or not P.mod then return end
	local mod = P.mod
	P.mod = nil
	if mod.card then mod.card.setActive(false) end
	local d = instant and .01 or .28
	tween(self.content, d, { Size = UDim2.new(1, -RAIL_W, 1, -TOP_H) }, Enum.EasingStyle.Quint)
	tween(P.frame, d, { Position = UDim2.new(1, P.w + 40, 0, 12) }, Enum.EasingStyle.Quint)
	task.delay(instant and .02 or .3, function()
		if P.mod == nil then P.frame.Visible = false end
		if P.mod ~= mod then mod.sf.Visible = false end
	end)
end

-- SEARCH ----------------------------------------------------------------------------------------------------------------------
function UI:_search(q)
	q = q:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if q == "" then
		for _, t in ipairs(self.tabs) do t.header.Visible = false; t.page.Visible = t == self.active end
		for _, r in ipairs(self.rows) do r.frame.Visible = true end
		for _, sec in ipairs(self.sections) do
			if sec.collapsed then for _, fr in ipairs(sec.rows) do fr.Visible = false end end
		end
		return
	end
	self:ClosePanel(true)
	local hits = {}
	for _, r in ipairs(self.rows) do
		local m = r.name:find(q, 1, true) ~= nil or r.tab.name:lower():find(q, 1, true) ~= nil
		r.frame.Visible = m
		if m then hits[r.tab] = true end
	end
	for _, t in ipairs(self.tabs) do
		local has = hits[t] == true
		t.header.Visible = has
		t.page.Visible = has
	end
	self.content.CanvasPosition = Vector2.zero
end

-- TOASTS ----------------------------------------------------------------------------------------------------------------------
local KINDS = {
	info = { color = Color3.fromRGB(243, 156, 18), glyph = "i", sound = "notify" },
	success = { color = Color3.fromRGB(46, 190, 110), glyph = "✓", sound = "success" },
	warn = { color = Color3.fromRGB(236, 82, 66), glyph = "!", sound = "warn" },
}
local function guessKind(textv)
	local l = textv:lower()
	if l:find("not found", 1, true) or l:find("failed", 1, true) or l:find("error", 1, true) or l:find("nothing", 1, true) or l:find("no pickup", 1, true)
		or l:find("changed its", 1, true) or l:find("missing", 1, true) or l:find("can't", 1, true) or l:find("cannot", 1, true) or l:find("no item", 1, true) then return "warn" end
	if l:find("learned", 1, true) or l:find("picked up", 1, true) or l:find("loaded", 1, true) or l:find("restored", 1, true) or l:find("applied", 1, true)
		or l:find("saved", 1, true) or l:find(" on", 1, true) or l:find("normal", 1, true) then return "success" end
	return "info"
end

function UI:Notify(str, seconds, kind)
	str = tostring(str)
	kind = KINDS[kind or ""] and kind or guessKind(str)
	local K = KINDS[kind]
	seconds = seconds or 3
	Sfx.Play(K.sound, .8)
	local slot = new("Frame", { Size = UDim2.fromOffset(330, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = self.toasts })
	local card = new("Frame", {
		Position = UDim2.fromOffset(360, 0), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.06, BorderSizePixel = 0, ClipsDescendants = true, Parent = slot,
	}, { corner(14) })
	bind(self, card, "BackgroundColor3", "panel")
	new("UIStroke", { Color = K.color, Thickness = 1, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })
	new("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = K.color, BorderSizePixel = 0, Parent = card })
	local body = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = card }, { pad(18, 14, 12, 15) })
	local badge = new("Frame", { Size = UDim2.fromOffset(28, 28), BackgroundColor3 = K.color, BackgroundTransparency = 0.8, BorderSizePixel = 0, Parent = body }, { corner(14) })
	new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = K.glyph, TextSize = 15, Font = T.bold, TextColor3 = K.color, Parent = badge })
	local l = text(self, str, 13, "text"); l.Position = UDim2.fromOffset(40, 0); l.Size = UDim2.new(1, -40, 0, 0); l.AutomaticSize = Enum.AutomaticSize.Y; l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = body
	new("UISizeConstraint", { MinSize = Vector2.new(0, 28), Parent = l })
	local track = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = K.color, BackgroundTransparency = 0.85, BorderSizePixel = 0, Parent = card })
	local bar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.color, BorderSizePixel = 0, Parent = track })
	tween(card, .5, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	tween(bar, seconds, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	task.delay(seconds, function()
		if not slot.Parent then return end
		tween(card, .35, { Position = UDim2.fromOffset(360, 0) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.wait(.38)
		pcall(function() slot:Destroy() end)
	end)
end

-- WINDOW STATE -----------------------------------------------------------------------------------------------------------------
function UI:SetVisible(v)
	self.visible = v
	if not v and self.openPicker then pcall(function() self.openPicker:Close() end) end
	if v then
		self.root.Visible = true
		Sfx.Play("open")
		if self.blur then tween(self.blur, .35, { Size = self.blurSize or 14 }) end
		tween(self.scale, .38, { Scale = self.baseScale }, Enum.EasingStyle.Back)
	else
		pcall(function() self.searchBox:ReleaseFocus() end)
		Sfx.Play("close")
		if self.blur then tween(self.blur, .25, { Size = 0 }) end
		tween(self.scale, .2, { Scale = self.baseScale * .94 })
		task.delay(.22, function() if not self.visible then self.root.Visible = false end end)
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

function UI:GetConfig()
	local out = {}
	for id, f in pairs(self.flags) do
		local v = f.obj:Get()
		if f.kind == "key" then v = v and v.Name or "" end
		out[id] = v
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
					elseif f.obj:Get() ~= v then
						f.obj:Set(v)
					end
				end)
			end
		end
	end
end

-- a settings row: rounded, translucent, grows with its label (long names wrap instead of being cut off)
local function row(tab, name, minH)
	tab.grid = nil -- a plain row ends the current card grid
	local win = tab.win
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, minH or 46), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, Parent = tab.page }, { corner(12) })
	bind(win, f, "BackgroundColor3", "elem"); f.BackgroundTransparency = .25
	local st = mkStroke(win, "stroke", .75); st.Parent = f
	f.MouseEnter:Connect(function() tween(f, .16, { BackgroundColor3 = T.hover, BackgroundTransparency = .1 }) end)
	f.MouseLeave:Connect(function() tween(f, .2, { BackgroundColor3 = T.elem, BackgroundTransparency = .25 }) end)
	table.insert(win.rows, { frame = f, name = name:lower(), tab = tab.realTab or tab })
	local cs = tab.curSection
	if cs then
		table.insert(cs.rows, f)
		if cs.collapsed then f.Visible = false end
		if cs.count then cs.count() end
	end
	return f, st
end

-- label inside a row: left side, wraps, leaves room for the control on the right
local function rowLabel(win, f, str, rightRoom)
	local l = text(win, str, 13, "text")
	l.Position = UDim2.fromOffset(16, 13); l.Size = UDim2.new(1, -(rightRoom + 28), 0, 0); l.AutomaticSize = Enum.AutomaticSize.Y; l.Parent = f
	new("UISizeConstraint", { MinSize = Vector2.new(0, 20), Parent = l })
	return l
end

function M:Section(o)
	local name = type(o) == "table" and o.Name or tostring(o)
	local win = self.win
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = self.page })
	self.grid = nil
	local dot = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 2, .5, 3), Size = UDim2.fromOffset(4, 12), BorderSizePixel = 0, Parent = f }, { corner(2) })
	bind(win, dot, "BackgroundColor3", "accent")
	local l = text(win, name:upper(), 11, "sub", T.bold); l.Position = UDim2.fromOffset(14, 4); l.Size = UDim2.new(1, -70, 1, 0); l.TextWrapped = false; l.Parent = f
	local chev = text(win, "v", 12, "sub", T.bold, Enum.TextXAlignment.Right); chev.AnchorPoint = Vector2.new(1, .5); chev.Position = UDim2.new(1, -4, .5, 3); chev.Size = UDim2.fromOffset(50, 16); chev.TextWrapped = false; chev.Parent = f
	local sec = { rows = {}, collapsed = type(o) == "table" and o.Collapsed == true }
	local function refreshHead() chev.Text = sec.collapsed and (#sec.rows .. "  >") or "v" end
	sec.count = refreshHead
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = f })
	hit.MouseEnter:Connect(function() tween(l, .15, { TextColor3 = T.text }) end)
	hit.MouseLeave:Connect(function() tween(l, .15, { TextColor3 = T.sub }) end)
	hit.MouseButton1Click:Connect(function()
		sec.collapsed = not sec.collapsed
		for _, r in ipairs(sec.rows) do r.Visible = not sec.collapsed end
		refreshHead()
	end)
	self.curSection = sec
	table.insert(win.sections, sec)
	table.insert(win.rows, { frame = f, name = "\0", tab = self.realTab or self }) -- hidden while searching
	return { frame = f, Section = sec }
end

function M:Label(o)
	local win = self.win
	local f = row(self, o.Name, 40)
	local n = text(win, o.Name, 13, "sub"); n.Position = UDim2.fromOffset(16, 11); n.Size = UDim2.new(.5, -16, 0, 0); n.AutomaticSize = Enum.AutomaticSize.Y; n.Parent = f
	local v = text(win, tostring(o.Value or "-"), 13, "text", T.semi, Enum.TextXAlignment.Right)
	v.Position = UDim2.new(.5, 0, 0, 11); v.Size = UDim2.new(.5, -16, 0, 0); v.AutomaticSize = Enum.AutomaticSize.Y; v.Parent = f
	return { Set = function(_, x) v.Text = tostring(x) end, frame = f }
end

function M:Button(o)
	local win = self.win
	local f = row(self, o.Name, 44)
	if o.Order then f.LayoutOrder = o.Order end
	local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = f })
	local t = text(win, o.Name, 13, "text", T.semi, Enum.TextXAlignment.Center); t.Position = UDim2.fromOffset(14, 0); t.Size = UDim2.new(1, -28, 1, 0); t.Parent = b
	local mark = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(3, 18), BorderSizePixel = 0, Parent = f }, { corner(2) })
	bind(win, mark, "BackgroundColor3", "accent")
	b.MouseButton1Click:Connect(function()
		Sfx.Play("click")
		tween(f, .08, { BackgroundColor3 = T.accentDim, BackgroundTransparency = 0 })
		task.delay(.1, function() tween(f, .3, { BackgroundColor3 = T.elem, BackgroundTransparency = .25 }) end)
		if o.Callback then task.spawn(o.Callback) end
	end)
	return {
		frame = f,
		SetText = function(_, s) t.Text = s end,
		Destroy = function()
			for i, r in ipairs(win.rows) do if r.frame == f then table.remove(win.rows, i); break end end
			f:Destroy()
		end,
	}
end

function M:TextBox(o)
	local win = self.win
	local f = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 160)
	local bg = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -12, .5, 0), Size = UDim2.fromOffset(150, 30), BorderSizePixel = 0, Parent = f }, { corner(8) })
	bind(win, bg, "BackgroundColor3", "hover")
	mkStroke(win, "stroke", .5).Parent = bg
	local box = new("TextBox", { BackgroundTransparency = 1, Size = UDim2.new(1, -18, 1, 0), Position = UDim2.fromOffset(9, 0), Text = o.Default or "", PlaceholderText = o.Placeholder or "",
		Font = T.font, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = bg })
	bind(win, box, "TextColor3", "text"); bind(win, box, "PlaceholderColor3", "sub")
	box.FocusLost:Connect(function() if o.Callback then task.spawn(o.Callback, box.Text) end end)
	return { Get = function() return box.Text end, Set = function(_, t) box.Text = t end, frame = f }
end

-- on/off switch drawn into `parent`; returns the pieces so cards and rows can share it
local function makeSwitch(parent, anchor, pos, w, h)
	local sw = new("Frame", { AnchorPoint = anchor, Position = pos, Size = UDim2.fromOffset(w, h), BorderSizePixel = 0, Parent = parent }, { corner(h / 2) })
	local k = h - 6
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 3, .5, 0), Size = UDim2.fromOffset(k, k), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = sw }, { corner(k / 2) })
	return sw, knob, w - k - 3, k
end

function M:Toggle(o)
	local win = self.win
	local f, rowStroke = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 56)
	local state = false
	local sw, knob, knobX, kd = makeSwitch(f, Vector2.new(1, .5), UDim2.new(1, -14, .5, 0), 40, 22)
	local bar = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 0, .5, 0), Size = UDim2.fromOffset(3, 0), BorderSizePixel = 0, Parent = f }, { corner(2) })
	bind(win, bar, "BackgroundColor3", "accent")
	local function swColor() return state and Color3.new(1, 1, 1) or T.off end
	bind(win, sw, "BackgroundColor3", swColor)
	local sgrad = gradBind(win, sw, 0); sgrad.Enabled = false
	bind(win, rowStroke, "Color", function() return state and T.strokeOn or T.stroke end)
	local obj = {}
	local function apply(v, silent)
		state = v
		tween(bar, .25, { Size = UDim2.fromOffset(3, v and 22 or 0) }, Enum.EasingStyle.Back)
		tween(rowStroke, .22, { Color = v and T.strokeOn or T.stroke, Transparency = v and .35 or .75 })
		sgrad.Enabled = v
		tween(sw, .22, { BackgroundColor3 = swColor() })
		tween(knob, .25, { Position = UDim2.new(0, v and knobX or 3, .5, 0) }, Enum.EasingStyle.Back)
		if not silent then
			Sfx.Play(v and "on" or "off")
			knob.Size = UDim2.fromOffset(kd + 6, kd); tween(knob, .3, { Size = UDim2.fromOffset(kd, kd) })
			if o.Callback then task.spawn(o.Callback, v) end
		end
	end
	function obj:Set(v, silent) apply(v, silent) end
	function obj:Get() return state end
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = f })
	hit.MouseButton1Click:Connect(function() apply(not state) end)
	apply(o.Default == true, true)
	obj.frame, obj.hit = f, hit
	register(self, o, "toggle", obj)
	return obj
end

-- MODULE CARD -----------------------------------------------------------------------------------------------------------------
-- A module is a card in a two-column grid. Click the card to switch it on / off; the gear (or right-click) opens its settings in the drawer.
-- local m = tab:Module({ Name = "Suspension", Default = false, Callback = function(on) end })
-- m:Slider({...}) / m:Toggle({...}) / m:Keybind({...}) / m:Button({...}) / m:Label({...}) add rows to its drawer.
function M:Module(o)
	local win = self.win
	local realTab = self.realTab or self
	realTab.modCount = realTab.modCount + 1
	if not self.grid or not self.grid.Parent then
		self.grid = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = self.page })
		new("UIGridLayout", { CellSize = UDim2.new(.5, -6, 0, 110), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.grid })
	end
	local card = new("Frame", { BorderSizePixel = 0, ClipsDescendants = true, Parent = self.grid }, { corner(14) })
	card.BackgroundTransparency = .2
	local cstroke = new("UIStroke", { Thickness = 1, Transparency = .7, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })

	-- icon badge: the tab's icon (or the first letter)
	local badge = new("Frame", { Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(38, 38), BorderSizePixel = 0, Parent = card }, { corner(11) })
	bind(win, badge, "BackgroundColor3", "accentDim")
	local bico = realTab.iconIdx and Icons.Make(badge, realTab.iconIdx, 20, UDim2.new(.5, -10, .5, -10))
	if bico then bind(win, bico, "ImageColor3", "accent")
	else
		local ch = text(win, o.Name:sub(1, 1):upper(), 16, "accent", T.bold, Enum.TextXAlignment.Center); ch.Size = UDim2.fromScale(1, 1); ch.Parent = badge
	end
	local nameL = text(win, o.Name, 14, "text", T.semi); nameL.Position = UDim2.fromOffset(62, 13); nameL.Size = UDim2.new(1, -62 - 46, 0, 40); nameL.TextYAlignment = Enum.TextYAlignment.Top; nameL.Parent = card
	local statL = text(win, "OFF", 12, "sub"); statL.Position = UDim2.fromOffset(16, 78); statL.Size = UDim2.new(1, -90, 0, 18); statL.TextWrapped = false; statL.Parent = card
	local glow = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(0, 0, 0, 4), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = card })
	gradBind(win, glow, 0)
	-- soft colour wash across the whole card while it is on
	local wash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1, Parent = card })
	gradBind(win, wash, 35)
	local sw, knob, knobX, kd = makeSwitch(card, Vector2.new(1, 1), UDim2.new(1, -14, 1, -14), 42, 24)

	local state, count, active = false, 0, false
	local obj = {}
	local function swColor() return state and Color3.new(1, 1, 1) or T.off end
	bind(win, sw, "BackgroundColor3", swColor)
	local sgrad = gradBind(win, sw, 0); sgrad.Enabled = false
	bind(win, cstroke, "Color", function() return (state or active) and T.strokeOn or T.stroke end)
	bind(win, card, "BackgroundColor3", function() return state and T.accentDim or T.elem end)
	local function paint()
		local on = state
		tween(card, .22, { BackgroundColor3 = on and T.accentDim or T.elem, BackgroundTransparency = on and .35 or .2 })
		tween(cstroke, .22, { Color = (on or active) and T.strokeOn or T.stroke, Transparency = (on or active) and .2 or .7 })
		tween(glow, .35, { Size = UDim2.new(on and 1 or 0, 0, 0, 4) }, Enum.EasingStyle.Quint)
		tween(wash, .3, { BackgroundTransparency = on and .82 or 1 })
		sgrad.Enabled = on
		tween(sw, .22, { BackgroundColor3 = swColor() })
		tween(knob, .25, { Position = UDim2.new(0, on and knobX or 3, .5, 0) }, Enum.EasingStyle.Back)
	end
	local function status()
		statL.Text = (state and "ON" or "OFF") .. (count > 0 and ("   -   " .. count .. (count == 1 and " setting" or " settings")) or "")
		tween(statL, .2, { TextColor3 = state and T.accent or T.sub })
	end
	local function apply(v, silent)
		state = v
		paint(); status()
		if not silent then
			Sfx.Play(v and "on" or "off")
			knob.Size = UDim2.fromOffset(kd + 6, kd); tween(knob, .3, { Size = UDim2.fromOffset(kd, kd) })
			if o.Callback then task.spawn(o.Callback, v) end
		end
	end
	function obj:Set(v, silent) apply(v, silent) end
	function obj:Get() return state end
	obj.frame = card

	local sf = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Parent = win.panel.body })
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sf })
	local sub = { page = sf, win = win, realTab = realTab, modName = o.Name }
	setmetatable(sub, { __index = M })
	local mod = { name = o.Name, sf = sf, tab = realTab, count = function() return count end, card = { setActive = function(v) active = v; paint() end } }
	local function togglePanel()
		if count == 0 then return end
		if win.panel.mod == mod then win:ClosePanel() else win:OpenPanel(mod) end
	end
	function obj:SetOpen(v) if v then win:OpenPanel(mod) elseif win.panel.mod == mod then win:ClosePanel() end end

	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = card })
	hit.MouseButton1Click:Connect(function() apply(not state) end)
	hit.MouseButton2Click:Connect(togglePanel)
	hit.MouseEnter:Connect(function() if not state then tween(card, .15, { BackgroundColor3 = T.hover, BackgroundTransparency = .05 }) end; Sfx.Play("hover", .35) end)
	hit.MouseLeave:Connect(function() if not state then tween(card, .2, { BackgroundColor3 = T.elem, BackgroundTransparency = .2 }) end end)
	local gear = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(30, 30), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 3, Parent = card }, { corner(15) })
	bind(win, gear, "BackgroundColor3", "hover"); gear.BackgroundTransparency = .5
	local gi = Icons.Make(gear, 9, 16, UDim2.new(.5, -8, .5, -8)); if gi then bind(win, gi, "ImageColor3", "sub"); gi.ZIndex = 4 end
	gear.MouseButton1Click:Connect(function() Sfx.Play("click"); togglePanel() end)
	gear.MouseEnter:Connect(function() tween(gear, .15, { BackgroundTransparency = .05 }); if gi then tween(gi, .15, { ImageColor3 = T.accent }) end end)
	gear.MouseLeave:Connect(function() tween(gear, .15, { BackgroundTransparency = .5 }); if gi then tween(gi, .15, { ImageColor3 = T.sub }) end end)

	local ent = { frame = card, name = o.Name:lower(), tab = realTab }
	table.insert(win.rows, ent)
	for _, k in ipairs({ "Toggle", "Slider", "Keybind", "Button", "Label", "TextBox", "ColorPicker", "Section" }) do
		obj[k] = function(_, opts)
			if k ~= "Section" then
				count = count + 1
				gear.Visible = true; status()
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
	local f = row(self, o.Name, 64)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
	pad(16, 16, 13, 14).Parent = f
	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, Parent = f })
	local n = text(win, o.Name, 13, "text"); n.Size = UDim2.new(1, -86, 0, 0); n.AutomaticSize = Enum.AutomaticSize.Y; n.Parent = head
	new("UISizeConstraint", { MinSize = Vector2.new(0, 22), Parent = n })
	local chip = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, Parent = head }, { corner(8), pad(9, 9, 0, 0) })
	bind(win, chip, "BackgroundColor3", "accentDim")
	local val = text(win, "", 12, "chip", T.bold, Enum.TextXAlignment.Center); val.Size = UDim2.fromOffset(0, 24); val.AutomaticSize = Enum.AutomaticSize.X; val.TextWrapped = false; val.Parent = chip
	local zone = new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 2, Parent = f })
	local track = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.new(1, 0, 0, 6), BorderSizePixel = 0, Parent = zone }, { corner(3) })
	bind(win, track, "BackgroundColor3", "off")
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = track }, { corner(3) })
	gradBind(win, fill, 0)
	local knob = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = track }, { corner(8) })
	local ks = mkStroke(win, "accent", 0, 2); ks.Parent = knob
	local min, max, step = o.Min, o.Max, o.Step or 1
	local value
	local obj = {}
	local function set(v, silent)
		v = math.clamp(math.floor((v - min) / step + .5) * step + min, min, max)
		value = v
		local p = (v - min) / (max - min)
		tween(fill, .1, { Size = UDim2.fromScale(p, 1) }); tween(knob, .1, { Position = UDim2.fromScale(p, .5) })
		val.Text = (step < 1 and string.format("%.2f", v) or tostring(v)) .. (o.Suffix or "")
		if not silent and o.Callback then task.spawn(o.Callback, v) end
	end
	function obj:Set(v, silent) set(v, silent) end
	function obj:Get() return value end
	local dragging = false
	local function fromInput(i) set(min + math.clamp((i.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1) * (max - min)) end
	local hit = new("TextButton", { Size = UDim2.new(1, 0, 1, 10), Position = UDim2.fromOffset(0, -5), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = zone })
	hit.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true; tween(knob, .15, { Size = UDim2.fromOffset(20, 20) }); fromInput(i)
		end
	end)
	table.insert(win.conns, UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromInput(i) end
	end))
	table.insert(win.conns, UIS.InputEnded:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			dragging = false; tween(knob, .15, { Size = UDim2.fromOffset(16, 16) }); Sfx.Play("click", .45)
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
	local f = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 130)
	local btn = new("TextButton", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -12, .5, 0), Size = UDim2.fromOffset(112, 30), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = f }, { corner(8) })
	bind(win, btn, "BackgroundColor3", "hover")
	local bstroke = mkStroke(win, "stroke", .45); bstroke.Parent = btn
	local txt = text(win, "", 12, "text", T.semi, Enum.TextXAlignment.Center); txt.Size = UDim2.fromScale(1, 1); txt.TextWrapped = false; txt.Parent = btn
	local key, listening, conn = o.Default, false, nil
	local obj = {}
	local function show()
		txt.Text = listening and "Press a key..." or (key and key.Name or "None")
		tween(txt, .15, { TextColor3 = listening and T.accent or T.text })
		tween(bstroke, .15, { Color = listening and T.accent or T.stroke })
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
	local f = row(self, o.Name, 48)
	rowLabel(win, f, o.Name, 74)
	local color = o.Default or T.accent
	local h, s, v = color:ToHSV()
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = f })
	local sw = new("Frame", { AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -14, .5, 0), Size = UDim2.fromOffset(56, 28), BackgroundColor3 = color, BorderSizePixel = 0, Parent = f }, { corner(9) })
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Transparency = .75, Parent = sw })

	local obj = {}
	local pop, svBox, svCur, hueCur, hexLbl, prev, hueBar
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
			hexLbl.Text = hex()
			prev.BackgroundColor3 = color
		end
	end
	function obj:Get() return color end
	function obj:Set(c, silent) h, s, v = c:ToHSV(); refresh(); if not silent then fire(true) end end

	local function build()
		pop = new("Frame", { Size = UDim2.fromOffset(240, 270), BackgroundColor3 = T.panel, BorderSizePixel = 0, ZIndex = 30, Visible = false, Parent = win.gui }, { corner(14) })
		new("UIStroke", { Color = T.stroke, Thickness = 1, Transparency = .2, Parent = pop })
		new("TextLabel", { BackgroundTransparency = 1, Text = o.Name, TextSize = 13, Font = T.bold, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -50, 0, 18), Parent = pop })
		local x = new("TextButton", { Position = UDim2.new(1, -32, 0, 6), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = T.hover, BorderSizePixel = 0, AutoButtonColor = false, Text = "×", TextSize = 18, Font = T.bold, TextColor3 = T.sub, Parent = pop }, { corner(8) })
		x.MouseButton1Click:Connect(function() obj:Close() end)

		svBox = new("Frame", { Position = UDim2.fromOffset(12, 38), Size = UDim2.fromOffset(216, 142), BackgroundColor3 = Color3.fromHSV(h, 1, 1), BorderSizePixel = 0, ClipsDescendants = true, Parent = pop }, { corner(8) })
		local white = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = svBox })
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = white })
		local black = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = svBox })
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }), Parent = black })
		svCur = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = svBox }, { corner(7) })
		new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = svCur })

		hueBar = new("Frame", { Position = UDim2.fromOffset(12, 192), Size = UDim2.fromOffset(216, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = pop }, { corner(7) })
		new("UIGradient", { Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)), ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)), ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)), ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)) }), Parent = hueBar })
		hueCur = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(8, 22), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = hueBar }, { corner(4) })
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = hueCur })

		prev = new("Frame", { Position = UDim2.fromOffset(12, 222), Size = UDim2.fromOffset(36, 32), BackgroundColor3 = color, BorderSizePixel = 0, Parent = pop }, { corner(8) })
		hexLbl = new("TextLabel", { BackgroundTransparency = 1, Text = hex(), TextSize = 13, Font = T.bold, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(58, 222), Size = UDim2.fromOffset(90, 32), Parent = pop })
		local rs = new("TextButton", { Position = UDim2.fromOffset(154, 222), Size = UDim2.fromOffset(74, 32), BackgroundColor3 = T.hover, BorderSizePixel = 0, AutoButtonColor = false, Text = "Reset", TextColor3 = T.text, Font = T.font, TextSize = 12, Parent = pop }, { corner(8) })
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
			local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 3, Parent = target })
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
		pop.Position = UDim2.fromOffset(math.clamp(sp.X + sw.AbsoluteSize.X - 240, 8, math.max(ss.X - 248, 8)), math.clamp(sp.Y + sw.AbsoluteSize.Y + 8, 8, math.max(ss.Y - 278, 8)))
		pop.Visible = true
		refresh()
		win.openPicker = obj
	end
	hit.MouseButton1Click:Connect(function() if pop and pop.Visible then obj:Close() else open() end end)
	obj.frame = f
	return obj
end

-- THEME -----------------------------------------------------------------------------------------------------------------------
local PALETTE_KEYS = { "accent", "accentDim", "chip", "gradA", "gradB", "strokeOn", "bg", "panel", "elem", "hover", "stroke", "off" }
local function lift(c, d) return Color3.fromRGB(math.clamp(c.R * 255 + d, 0, 255), math.clamp(c.G * 255 + d, 0, 255), math.clamp(c.B * 255 + d, 0, 255)) end
local DEFAULT_P = {}
for _, k in ipairs(PALETTE_KEYS) do DEFAULT_P[k] = T[k] end
local curP = {}
for k, v in pairs(DEFAULT_P) do curP[k] = v end

-- every colour of the theme derived from two picked colours
function UI.Palette(accent, bg)
	if not accent and not bg then return DEFAULT_P end
	accent, bg = accent or DEFAULT_P.accent, bg or DEFAULT_P.bg
	local white, black = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
	return {
		accent = accent, accentDim = bg:Lerp(accent, .22), chip = accent:Lerp(white, .35), gradA = accent:Lerp(black, .2),
		gradB = accent:Lerp(white, .25), strokeOn = bg:Lerp(accent, .5),
		bg = bg, panel = lift(bg, 5), elem = lift(bg, 11), hover = lift(bg, 21), stroke = lift(bg, 33), off = lift(bg, 45),
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

function UI.PaletteMap(old, new)
	local map = {}
	for _, k in ipairs(PALETTE_KEYS) do
		if ckey(old[k]) ~= ckey(new[k]) then map[ckey(old[k])] = new[k] end
	end
	return map
end

-- applies a palette: every bound colour is recomputed; returns the colour map so the HUD can follow
function UI:ApplyPalette(P)
	local map = UI.PaletteMap(curP, P)
	for _, k in ipairs(PALETTE_KEYS) do T[k] = P[k]; curP[k] = P[k] end
	for _, b in ipairs(self.binds) do
		pcall(function() b[1][b[2]] = b[3]() end)
	end
	return map
end

UI.Theme = T
return UI

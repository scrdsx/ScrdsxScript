-- UI controls: Section, Label, Button, TextBox, Choice (dropdown), Toggle, Slider, Keybind. Each works on a page (a rounded card of
-- its own) and inside a module card (a flat line). Module cards are in ui/module.lua, the colour picker in ui/colorpicker.lua.
local UIS = game:GetService("UserInputService")
local Sfx = __import("core/sfx")
local B = __import("ui/base")
local T = B.T
local tween, new, corner, pad, bind, mkStroke, text, makeSwitch = B.tween, B.new, B.corner, B.pad, B.bind, B.mkStroke, B.text, B.makeSwitch
local row, rowLabel, register = B.row, B.rowLabel, B.register
local WHITE, BLACK = B.WHITE, B.BLACK

local M = {}

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
	local btn = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, compact and -6 or -12, 0, compact and 4 or 9), Size = UDim2.fromOffset(150, 28), BorderSizePixel = 0, AutoButtonColor = false, Text = "", Parent = f }, { corner(9) })
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
			BackgroundColor3 = T.panel, ScrollBarImageColor3 = T.off, ScrollBarThickness = 2, CanvasSize = UDim2.fromOffset(0, #opts_ * itemH + 8), ZIndex = 51, Parent = ov }, { corner(10), pad(4, 4, 4, 4) })
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

-- SLIDER ----------------------------------------------------------------------------------------------------------------------
function M:Slider(o)
	local win = self.win
	local f, _, compact = row(self, o.Name, 58)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
	if compact then pad(10, 10, 8, 10).Parent = f else pad(16, 16, 12, 14).Parent = f end
	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, Parent = f })
	local n = text(win, o.Name, 13, compact and "sub" or "text"); n.Size = UDim2.new(1, -74, 0, 0); n.AutomaticSize = Enum.AutomaticSize.Y; n.Parent = head
	new("UISizeConstraint", { MinSize = Vector2.new(0, 18), Parent = n })
	local valBg = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0, Parent = head }, { corner(9), pad(8, 8, 0, 0) })
	bind(win, valBg, "BackgroundColor3", "accentDim")
	local val = text(win, "", 12, "chip", T.bold, Enum.TextXAlignment.Center); val.Size = UDim2.fromOffset(0, 18); val.AutomaticSize = Enum.AutomaticSize.X; val.TextWrapped = false; val.Parent = valBg
	local zone = new("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 2, Parent = f })
	local track = new("Frame", { AnchorPoint = Vector2.new(0, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.new(1, 0, 0, 6), BorderSizePixel = 0, Parent = zone }, { corner(3) })
	bind(win, track, "BackgroundColor3", "off")
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, BackgroundColor3 = WHITE, Parent = track }, { corner(3) })
	local fgrad = new("UIGradient", { Parent = fill })
	bind(win, fgrad, "Color", function() return ColorSequence.new(T.gradA, T.gradB) end)
	local knob = new("Frame", { AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = track }, { corner(7) })
	local kst = new("UIStroke", { Thickness = 3, Transparency = 0.55, Parent = knob })
	bind(win, kst, "Color", "bg")
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
			dragging = true; tween(knob, .1, { Size = UDim2.fromOffset(17, 17) }); fromInput(i)
		end
	end)
	table.insert(win.conns, UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromInput(i) end
	end))
	table.insert(win.conns, UIS.InputEnded:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			dragging = false; tween(knob, .1, { Size = UDim2.fromOffset(14, 14) }); Sfx.Play("click", .35)
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

return M

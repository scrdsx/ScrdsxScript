-- UI colour picker: a swatch that opens a popup (saturation / brightness square, hue bar, hex box, reset).
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local B = __import("ui/base")
local T = B.T
local tween, new, corner, pad, bind, mkStroke, text, makeSwitch = B.tween, B.new, B.corner, B.pad, B.bind, B.mkStroke, B.text, B.makeSwitch
local row, rowLabel, register = B.row, B.rowLabel, B.register
local WHITE, BLACK = B.WHITE, B.BLACK
local hexColor = B.hexColor

return function(M)
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
end

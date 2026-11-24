-- Loading screen (v6 "Mocha"): no black screen. The game stays visible behind a light dim; a small espresso card rises in the middle with
-- the logo, the name + version, what it is waiting for, and a cream progress bar with a percentage. Driven by real readiness checks
-- (about 1.2 s when the game is ready), then the card sinks away.
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Logo = __import("core/logo")

local Loading = {}

local function tween(o, t, p, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), p)
	tw:Play()
	return tw
end

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- wait for cond() up to timeout seconds; returns whether it became true
local function waitFor(cond, timeout)
	local t = os.clock()
	while not cond() do
		if os.clock() - t > timeout then return false end
		task.wait(.05)
	end
	return true
end

local C = {
	dim = Color3.fromRGB(8, 7, 6), card = Color3.fromRGB(22, 19, 17), stroke = Color3.fromRGB(46, 41, 36),
	text = Color3.fromRGB(245, 239, 229), sub = Color3.fromRGB(150, 141, 130), track = Color3.fromRGB(40, 36, 32),
	a = Color3.fromRGB(214, 176, 128), b = Color3.fromRGB(247, 230, 202),
}

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1; l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

function Loading.run(title, subtitle, extraSteps)
	local gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = guiParent()

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1); dim.BackgroundColor3 = C.dim; dim.BackgroundTransparency = 1; dim.BorderSizePixel = 0; dim.Parent = gui
	tween(dim, .3, { BackgroundTransparency = .45 })

	local card = Instance.new("CanvasGroup")
	card.AnchorPoint = Vector2.new(.5, .5); card.Position = UDim2.new(.5, 0, .5, 18); card.Size = UDim2.fromOffset(360, 112)
	card.BackgroundColor3 = C.card; card.BorderSizePixel = 0; card.GroupTransparency = 1; card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)
	local st = Instance.new("UIStroke"); st.Color = C.stroke; st.Thickness = 1; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = card
	local cam = workspace.CurrentCamera
	local sc = Instance.new("UIScale"); sc.Scale = math.clamp((cam and cam.ViewportSize.Y or 800) / 840, .85, 1.35); sc.Parent = card
	tween(card, .45, { Position = UDim2.fromScale(.5, .5), GroupTransparency = 0 }, Enum.EasingStyle.Quart)

	Logo.Make(card, 44, UDim2.fromOffset(22, 22))
	label(card, { Position = UDim2.fromOffset(80, 22), Size = UDim2.fromOffset(170, 22), Text = title, Font = Enum.Font.BuilderSansBold, TextSize = 20, TextColor3 = C.text })
	label(card, { Position = UDim2.fromOffset(80, 45), Size = UDim2.fromOffset(250, 16), Text = subtitle or "", Font = Enum.Font.BuilderSansMedium, TextSize = 12, TextColor3 = C.sub })
	local pct = label(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 24), Size = UDim2.fromOffset(60, 18), Text = "0%",
		Font = Enum.Font.BuilderSansBold, TextSize = 14, TextColor3 = C.b, TextXAlignment = Enum.TextXAlignment.Right })

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(22, 80); track.Size = UDim2.new(1, -44, 0, 4); track.BackgroundColor3 = C.track; track.BorderSizePixel = 0; track.Parent = card
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1); fill.BackgroundColor3 = Color3.new(1, 1, 1); fill.BorderSizePixel = 0; fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(C.a, C.b); g.Parent = fill
	local status = label(card, { Position = UDim2.fromOffset(22, 90), Size = UDim2.new(1, -44, 0, 14), Text = "", Font = Enum.Font.BuilderSansMedium, TextSize = 11, TextColor3 = C.sub })

	local shown, target = 0, 0
	task.spawn(function() -- the % counts up smoothly instead of jumping
		while gui.Parent do
			if shown < target then shown = math.min(target, shown + 3); pct.Text = shown .. "%" end
			task.wait(.015)
		end
	end)
	local function progress(f)
		tween(fill, .22, { Size = UDim2.fromScale(f, 1) }, Enum.EasingStyle.Quart)
		target = math.floor(f * 100 + .5)
	end

	task.wait(.3)
	local lp = Players.LocalPlayer
	local steps = {
		{ "Waiting for the game", function() return game:IsLoaded() end, 15 },
		{ "Finding your character", function() return lp.Character ~= nil end, 10 },
		{ "Loading interface", function() return lp:FindFirstChild("PlayerGui") ~= nil end, 10 },
	}
	for _, s in ipairs(extraSteps or {}) do table.insert(steps, s) end -- game-specific readiness checks: { "Label", cond, timeout }
	for i, s in ipairs(steps) do
		status.Text = s[1]
		waitFor(s[2], s[3])
		progress(i / (#steps + 1))
		task.wait(.05)
	end
	status.Text = "Ready"
	progress(1)
	task.wait(.4)

	tween(card, .3, { Position = UDim2.new(.5, 0, .5, 14), GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(dim, .35, { BackgroundTransparency = 1 })
	task.delay(.4, function() gui:Destroy() end)
end

return Loading

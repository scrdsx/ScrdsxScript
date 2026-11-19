-- Loading screen: short and quiet. Flat dark backdrop, logo pops in, title, one thin progress bar driven by real readiness checks (about 1.5 s when the game is ready).
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Logo = __import("logo")

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

local BG, TEXT, SUB, TRACK = Color3.fromRGB(16, 16, 18), Color3.fromRGB(240, 240, 245), Color3.fromRGB(135, 135, 146), Color3.fromRGB(40, 40, 46)

function Loading.run(title, subtitle, extraSteps)
	local gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = guiParent()

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1); bg.BackgroundColor3 = BG; bg.BackgroundTransparency = 1; bg.BorderSizePixel = 0; bg.Parent = gui
	tween(bg, .25, { BackgroundTransparency = 0 })

	-- everything sits in one centred column so it scales as a block
	local col = Instance.new("Frame")
	col.AnchorPoint = Vector2.new(.5, .5); col.Position = UDim2.fromScale(.5, .5); col.Size = UDim2.fromOffset(300, 190); col.BackgroundTransparency = 1; col.Parent = bg
	local sc = Instance.new("UIScale"); sc.Scale = .9; sc.Parent = col
	tween(sc, .5, { Scale = 1 }, Enum.EasingStyle.Back)

	local logo = Logo.Make(col, 56, UDim2.new(.5, -28, 0, 0))
	if logo:IsA("ImageLabel") then logo.ImageTransparency = 1; tween(logo, .35, { ImageTransparency = 0 })
	else logo.BackgroundTransparency = 1; tween(logo, .35, { BackgroundTransparency = 0 }) end

	local ttl = Instance.new("TextLabel")
	ttl.BackgroundTransparency = 1; ttl.AnchorPoint = Vector2.new(.5, 0); ttl.Position = UDim2.new(.5, 0, 0, 74); ttl.Size = UDim2.fromOffset(300, 34)
	ttl.Text = title; ttl.Font = Enum.Font.BuilderSansBold; ttl.TextSize = 28; ttl.TextColor3 = TEXT; ttl.TextTransparency = 1; ttl.Parent = col
	tween(ttl, .4, { TextTransparency = 0 })

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1; sub.AnchorPoint = Vector2.new(.5, 0); sub.Position = UDim2.new(.5, 0, 0, 108); sub.Size = UDim2.fromOffset(300, 16)
	sub.Text = subtitle or ""; sub.Font = Enum.Font.BuilderSansMedium; sub.TextSize = 12; sub.TextColor3 = SUB; sub.TextTransparency = 1; sub.Parent = col
	tween(sub, .5, { TextTransparency = 0 })

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(.5, 0); track.Position = UDim2.new(.5, 0, 0, 142); track.Size = UDim2.fromOffset(220, 3)
	track.BackgroundColor3 = TRACK; track.BorderSizePixel = 0; track.Parent = col
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1); fill.BackgroundColor3 = TEXT; fill.BorderSizePixel = 0; fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1; status.AnchorPoint = Vector2.new(.5, 0); status.Position = UDim2.new(.5, 0, 0, 156); status.Size = UDim2.fromOffset(300, 14)
	status.Text = ""; status.Font = Enum.Font.BuilderSansMedium; status.TextSize = 11; status.TextColor3 = SUB; status.Parent = col

	task.wait(.35) -- just enough for the pop-in

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
		tween(fill, .18, { Size = UDim2.fromScale(i / (#steps + 1), 1) })
		task.wait(.06)
	end
	status.Text = "Ready"
	tween(fill, .2, { Size = UDim2.fromScale(1, 1) })
	task.wait(.3)

	-- one clean fade out
	tween(sc, .35, { Scale = 1.04 })
	for _, o in ipairs({ ttl, sub, status }) do tween(o, .3, { TextTransparency = 1 }) end
	if logo:IsA("ImageLabel") then tween(logo, .3, { ImageTransparency = 1 }) else tween(logo, .3, { BackgroundTransparency = 1 }) end
	tween(fill, .3, { BackgroundTransparency = 1 }); tween(track, .3, { BackgroundTransparency = 1 })
	task.wait(.2)
	tween(bg, .3, { BackgroundTransparency = 1 })
	task.delay(.35, function() gui:Destroy() end)
end

return Loading

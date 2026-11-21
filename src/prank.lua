-- A harmless one-time joke for one friend: for about a minute the window sways like it has had a few, the accent colour cycles, and silly questions pop up.
-- It happens once (a marker file is written the moment it starts); after that the menu is normal. Nothing is collected or sent anywhere.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local lp = Players.LocalPlayer

local Prank = {}
local TARGET_ID = 2386753762
local MARK = "ScrdsxScript/.hic"
local SECONDS = 60

local QUESTIONS = {
	{ "Did you drink water today? Be honest.", "Yes", "Define water", "Water is a vibe. Respect." },
	{ "Are you the main character or an NPC?", "Main character", "NPC (loading...)", "The narrator has been informed." },
	{ "How many fingers am I holding up?", "Three", "Banana", "Wrong. It was a banana." },
	{ "Is a hot dog a sandwich?", "Yes", "Absolutely not", "The council will review this." },
	{ "Why is the floor moving?", "It is not", "Because of you", "Floor says sorry." },
	{ "Cereal first or milk first?", "Cereal", "Milk", "Illegal either way. Arrested." },
	{ "Quick: what is 7 times 8?", "56", "Purple", "Close enough, genius." },
	{ "Are you sure you are not a cat?", "100% sure", "meow", "I knew it. Treats incoming." },
	{ "Rate your balance from 1 to wobble.", "Wobble", "Double wobble", "Hic. Same." },
	{ "Do you trust this menu?", "Yes", "It is spinning...", "It is not spinning. You are." },
	{ "Final question: who let you cook?", "Nobody", "Me", "Fair. Carry on." },
}

local function seen()
	if type(isfile) ~= "function" then return false end
	local ok, v = pcall(isfile, MARK)
	return ok and v == true
end

local function mark()
	if type(writefile) ~= "function" then return end
	pcall(function()
		if makefolder then pcall(makefolder, "ScrdsxScript") end
		writefile(MARK, "1")
	end)
end

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end

-- win = the UI window, UI = the ui module, restore = function that puts the normal theme back
function Prank.Run(win, UI, restore)
	if lp.UserId ~= TARGET_ID then return end
	local env = getgenv and getgenv() or _G
	if env.__ScrdsxHic or seen() then return end
	env.__ScrdsxHic = true
	mark() -- once, even if the script is closed in the middle of it

	task.spawn(function()
		task.wait(3.5) -- let the normal loading finish first
		local holder, scale = win.root, win.scale
		local baseScale = win.baseScale or 1
		local alive = true

		-- the question card
		local gui = Instance.new("ScreenGui")
		gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 1001; gui.Parent = guiParent()
		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(.5, 1); card.Position = UDim2.new(.5, 0, 1, 120); card.Size = UDim2.fromOffset(420, 0); card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = Color3.fromRGB(24, 24, 27); card.BorderSizePixel = 0; card.Parent = gui
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
		local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(70, 70, 78); st.Parent = card
		local pd = Instance.new("UIPadding"); pd.PaddingLeft = UDim.new(0, 18); pd.PaddingRight = UDim.new(0, 18); pd.PaddingTop = UDim.new(0, 14); pd.PaddingBottom = UDim.new(0, 16); pd.Parent = card
		local lay = Instance.new("UIListLayout"); lay.Padding = UDim.new(0, 10); lay.Parent = card
		local qLabel = Instance.new("TextLabel")
		qLabel.BackgroundTransparency = 1; qLabel.Size = UDim2.new(1, 0, 0, 0); qLabel.AutomaticSize = Enum.AutomaticSize.Y; qLabel.TextWrapped = true
		qLabel.Font = Enum.Font.BuilderSansBold; qLabel.TextSize = 18; qLabel.TextColor3 = Color3.fromRGB(240, 240, 245); qLabel.TextXAlignment = Enum.TextXAlignment.Left
		qLabel.LayoutOrder = 1; qLabel.Parent = card
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1; row.Size = UDim2.new(1, 0, 0, 36); row.LayoutOrder = 2; row.Parent = card
		local rl = Instance.new("UIListLayout"); rl.FillDirection = Enum.FillDirection.Horizontal; rl.Padding = UDim.new(0, 10); rl.Parent = row
		local function btn(order)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(.5, -5, 1, 0); b.BackgroundColor3 = Color3.fromRGB(42, 42, 48); b.BorderSizePixel = 0; b.AutoButtonColor = true
			b.Font = Enum.Font.BuilderSansBold; b.TextSize = 14; b.TextColor3 = Color3.fromRGB(240, 240, 245); b.Text = ""; b.LayoutOrder = order; b.Parent = row
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
			return b
		end
		local b1, b2 = btn(1), btn(2)
		TweenService:Create(card, TweenInfo.new(.5, Enum.EasingStyle.Back), { Position = UDim2.new(.5, 0, 1, -40) }):Play()

		local idx = 0
		local function showQuestion()
			idx = idx % #QUESTIONS + 1
			local q = QUESTIONS[idx]
			qLabel.Text = q[1]; b1.Text = q[2]; b2.Text = q[3]
			card:SetAttribute("reply", q[4])
		end
		local function answered()
			win:Notify(card:GetAttribute("reply") or "...", 3)
			showQuestion()
		end
		b1.MouseButton1Click:Connect(answered)
		b2.MouseButton1Click:Connect(answered)
		showQuestion()

		win:Notify("...is it me or is the menu a little wobbly?", 4)

		-- the sway: rotation + scale pulse every frame, accent colour every half second, a new question every 7 seconds
		local t0, lastHue, lastQ = os.clock(), 0, os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			if t >= SECONDS or not alive then return end
			pcall(function()
				holder.Rotation = math.sin(t * 1.7) * 3.2 + math.sin(t * 4.1) * 0.8
				scale.Scale = baseScale * (1 + 0.025 * math.sin(t * 2.3))
			end)
			if os.clock() - lastHue > 0.5 then
				lastHue = os.clock()
				pcall(function() win:ApplyPalette(UI.Palette(Color3.fromHSV((t * 0.12) % 1, 0.7, 1))) end)
			end
			if os.clock() - lastQ > 7 then lastQ = os.clock(); showQuestion() end
		end)

		task.wait(SECONDS)
		alive = false
		if conn then conn:Disconnect() end
		pcall(function()
			holder.Rotation = 0
			scale.Scale = win.baseScale or baseScale
			if restore then restore() end
		end)
		qLabel.Text = "...ok that is enough. Back to normal. You did not see anything."
		b1.Text = "Okay"; b2.Text = "Hic"
		b1.MouseButton1Click:Connect(function() gui:Destroy() end)
		b2.MouseButton1Click:Connect(function() gui:Destroy() end)
		task.wait(5)
		pcall(function() gui:Destroy() end)
	end)
end

return Prank

-- A harmless one-time joke for one friend: for two minutes the menu sways like it has had a few, the accent colour cycles, and a pile of silly things happens
-- (a hundred-odd questions, toasts, aliens, UFOs, flying words, flips and colour flashes). It happens once (a marker file is written the moment it starts);
-- after that the menu is normal. Nothing is collected or sent anywhere, and nothing on screen blocks the game.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local lp = Players.LocalPlayer

local Prank = {}
local TARGET_ID = 2386753762
local MARK = "ScrdsxScript/.hic2"
local SECONDS = 120

-- question, answer 1, answer 2, reply
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
	{ "Who let you cook?", "Nobody", "Me", "Fair. Carry on." },
	{ "Is Feyzi in the room right now?", "Yes", "Check under the desk", "He says hi. He is also lost." },
	{ "Would you fight Feyzi for the last chicken nugget?", "Yes", "I would share", "Liar. Nobody shares nuggets." },
	{ "Is Feyzi a real person or a rumour?", "Real", "Rumour", "Feyzi has been notified of your opinion." },
	{ "Did an alien just walk past your window?", "Yes", "Define alien", "He waved. Wave back." },
	{ "Do you think aliens play Roblox?", "Obviously", "Only on Tuesdays", "Their ping is terrible, though." },
	{ "If an alien asks you for directions, you...", "Help him", "Run", "He was only looking for snacks." },
	{ "Are you taller than your own ping?", "Yes", "Sadly no", "Ping says hi." },
	{ "What is the airspeed of an unladen seagull?", "African or European?", "Yes", "Wrong movie, right energy." },
	{ "Is water wet?", "Yes", "No", "Water refuses to comment." },
	{ "Do you ever blink on purpose?", "Now I do", "No", "You blinked. I saw it." },
	{ "How is your tab count?", "Healthy", "Seventeen", "Seventeen is a lifestyle." },
	{ "Would you rather fight one horse-sized duck or a hundred duck-sized horses?", "The duck", "The horses", "Bold. Ducks are watching." },
	{ "Are you left-handed or just confused?", "Left", "Confused", "Both are valid." },
	{ "Do chairs miss us when we stand up?", "Yes", "Chairs feel nothing", "The chair just heard that." },
	{ "Is a straw one hole or two?", "One", "Two", "Do not google this." },
	{ "Which came first: the chicken or the egg?", "Chicken", "Egg", "The rooster says both." },
	{ "What colour is Tuesday?", "Blue", "Loud", "Correct. Tuesday agrees." },
	{ "Can you hear the colour green?", "Yes", "No", "Green is humming. Listen closer." },
	{ "Do you believe in love at first sprint?", "Yes", "Only after stamina", "Cardio is love." },
	{ "Is mayonnaise an instrument?", "Yes", "No, Patrick", "Squidward approves." },
	{ "Why do we park in driveways and drive on parkways?", "No idea", "Chaos", "Chaos is the answer to most things." },
	{ "Would you survive a zombie apocalypse?", "Easily", "I would be the zombie", "Brains were never your strength." },
	{ "How many hours of sleep did you really get?", "Eight", "A rumour of sleep", "We all know. We all know." },
	{ "Is it a bug or a feature?", "Feature", "Bug", "Marketing says feature." },
	{ "What does the fox say?", "Ring-ding-ding", "Hatee-hatee-ho", "The fox is disappointed in both." },
	{ "Can you spell 'banana' without looking?", "Yes", "Bananana", "You did not stop. Nobody stopped." },
	{ "Does your phone have more brain cells than you?", "Yes", "We are tied", "Tied at zero. Respect." },
	{ "Where do aliens get their wifi?", "Mars", "Neighbours", "Password is ALIENS123. Obviously." },
	{ "Is it normal that the walls are breathing?", "Yes", "Please stop", "The walls say thank you." },
	{ "Be honest: did you read the terms and conditions?", "Every word", "lol", "The terms read you instead." },
	{ "Who is your favourite alien?", "The green one", "The shy one", "He is blushing. Look away." },
	{ "Would you eat a pizza made of pizzas?", "Yes", "Yes, twice", "Recursion tastes great." },
	{ "What is the meaning of life?", "42", "Snacks", "Snacks. It was always snacks." },
	{ "Are you sure you are the one playing the game?", "Yes", "The game plays me", "Plot twist accepted." },
	{ "If you were a vegetable, which one?", "Potato", "Spicy potato", "Spicy potato is the best potato." },
	{ "Do you talk to yourself?", "Never", "Only in meetings", "I heard you. You said 'hic'." },
	{ "What would your cat say about you?", "Great human", "Feed me", "Cats are never wrong." },
	{ "Is the moon following you?", "Yes", "I follow it", "It is a mutual stalking." },
	{ "Pineapple on pizza?", "Yes", "Never", "Both answers have been sent to Italy." },
	{ "Do you ever just stare at nothing?", "Constantly", "Right now", "The nothing stares back." },
	{ "Which finger is your favourite?", "The pointer", "The shy one", "He heard you. He is crying." },
	{ "Can you do a handstand?", "Yes", "Define stand", "Gravity is undefeated." },
	{ "How many alien invasions have you survived?", "Zero", "Three", "Four, if you count this one." },
	{ "Do spoons have feelings?", "Yes", "Only soup spoons", "A soup spoon just sighed." },
	{ "What is the speed of dark?", "Slow", "Spooky", "Light is jealous." },
	{ "Why is the sky not green?", "Budget", "Pollen", "The sky filed a complaint." },
	{ "Would you rather be a fridge or a toaster?", "Fridge", "Toaster", "Toasters are hotter. Fridges are cooler." },
	{ "Do you stretch before you click?", "Always", "Never", "Your index finger says ouch." },
	{ "Is it a wobble or a vibe?", "Wobble", "Vibe", "Vibe wobble. Next question." },
	{ "Who is the best at this game?", "Me", "Not me", "Nobody believes you." },
	{ "Is your chair spinning?", "Yes", "Not yet", "Give it a second." },
	{ "Would you high-five an alien?", "Yes", "Fist bump only", "He prefers the elbow touch." },
	{ "Is Feyzi secretly an alien?", "Yes", "Probably", "He has been spotted near a UFO." },
	{ "Do you owe Feyzi a snack?", "Yes", "Never", "He remembers. He always remembers." },
	{ "Would Feyzi win in a staring contest?", "Yes", "I blink first", "He did not blink once. Scary." },
	{ "If Feyzi was a Pokemon, what type?", "Chaos", "Sleepy", "Sleepy-chaos. Super effective." },
	{ "What do you do when nobody is watching?", "Dance", "Hic", "The camera is on. Hic." },
	{ "Is a bagel a donut with a career?", "Yes", "No", "A bagel works nine to five." },
	{ "Why does time feel weird right now?", "It is Tuesday", "Hic", "Time hiccuped." },
	{ "Can you tell the future?", "Yes", "Only snack time", "Snack time: soon." },
	{ "Last question, really: how many questions did you answer?", "Lost count", "Seventy", "Eighty-three. I counted. Liar." },
}

local TOASTS = {
	"Update: you are now a potato.", "Feyzi called. He wants his seat back.", "Your uncle says hi (he is a UFO).", "Warning: floor has been replaced with soup.",
	"Achievement unlocked: Wobbling.", "Hic.", "A wild alien appeared!", "Please do not feed the menu.", "Feyzi has joined the party (he did not).",
	"System: your balance is loading...", "Reminder: drink water. Or juice. Or soup.", "The menu would like a word.", "Aliens requested a refund.",
	"Breaking news: you are doing great.", "Battery at 7%: your own.", "Error 404: sobriety not found.", "New message from the moon: hi.",
	"Your mouse is pointing at the future.", "Somebody ate your sandwich. It was a gull.", "Tip: gravity works better when you stand.",
	"Feyzi approved this message.", "The UFO is circling. Stay calm.", "A seagull stole your keys.", "Your alter ego is on line one.",
	"Fun fact: this toast is also tipsy.", "Weather report: raining potatoes.", "Please hold: the aliens are parking.", "You have been upgraded to Premium Wobble.",
	"Reminder: Feyzi owes you nothing. Collect anyway.", "Update installed: 14 percent more hic.", "The walls say hi back.", "Your shadow asked for a day off.",
	"Alert: seventeen browser tabs detected.", "Meeting in five minutes: you vs. gravity.", "Somebody typed 'banana' in the sky.", "The cursor misses you.",
	"Tonight on TV: a man stares at a menu.", "The alien said 'nice menu'.", "Feyzi is typing...", "Feyzi stopped typing.", "Your future self says 'drink water'.",
	"Free hug (from a floating alien).", "Look left. Now right. You are fine.", "Alert: snack levels critical.", "Congratulations, you read this toast.",
}

local ALIENS = {
	"Take me to your leader.", "Do you have snacks?", "Is this Earth? Wrong planet again.", "Nice menu, Earthling.", "We come in peace and also hungry.",
	"Have you seen my UFO keys?", "Greetings. Please wobble.", "Your planet has great wifi.", "I am not an alien. I am Feyzi's cousin.", "Beep boop. Hic.",
	"Quick, hide the snacks!", "We saw your ping. We are sorry.", "I like your hat. Is it a hat?", "Please do not blink. Blinking is rude.", "Wobble levels: perfect.",
	"Do you accept cookies? We do.",
}

local WORDS = {
	"hic", "wobble", "Feyzi?", "UFO!", "blorp", "snack", "oops", "beep", "boop", "potato", "zzz", "wheee", "uh oh", "alien", "spin", "moon", "banana", "nope",
	"yes?", "maybe", "glorp", "vibe", "tuesday", "cat", "hmm",
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

local function rnd(a, b) return a + math.random() * (b - a) end
local function pick(t) return t[math.random(#t)] end

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
		local flipping = false

		local gui = Instance.new("ScreenGui")
		gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 1001; gui.Parent = guiParent()
		local function tween(o, t, p, style, dir) local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), p); tw:Play(); return tw end

		-- the question card (the only thing that takes clicks)
		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(.5, 1); card.Position = UDim2.new(.5, 0, 1, 160); card.Size = UDim2.fromOffset(440, 0); card.AutomaticSize = Enum.AutomaticSize.Y
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
		tween(card, .5, { Position = UDim2.new(.5, 0, 1, -40) }, Enum.EasingStyle.Back)

		-- questions come in a shuffled order so nothing repeats before all of them were shown
		local order, oi = {}, 0
		for i = 1, #QUESTIONS do order[i] = i end
		for i = #order, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
		local reply = ""
		local function showQuestion()
			oi = oi % #order + 1
			local q = QUESTIONS[order[oi]]
			qLabel.Text = q[1]; b1.Text = q[2]; b2.Text = q[3]; reply = q[4]
		end
		local function answered()
			win:Notify(reply, 3)
			showQuestion()
		end
		b1.MouseButton1Click:Connect(answered)
		b2.MouseButton1Click:Connect(answered)
		showQuestion()

		-- things that drift over the screen (none of them take clicks)
		local function floater(text, size, startX, startY, endX, endY, secs, spin)
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1; l.Active = false; l.Size = UDim2.fromOffset(size * 3, size * 1.4); l.AnchorPoint = Vector2.new(.5, .5)
			l.Position = UDim2.fromScale(startX, startY); l.Text = text; l.TextSize = size; l.Font = Enum.Font.BuilderSansBold
			l.TextColor3 = Color3.fromHSV(math.random(), 0.5, 1); l.TextStrokeTransparency = 0.5; l.Rotation = rnd(-15, 15); l.Parent = gui
			tween(l, secs, { Position = UDim2.fromScale(endX, endY), Rotation = l.Rotation + (spin or 0), TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Sine)
			task.delay(secs + 0.1, function() pcall(function() l:Destroy() end) end)
			return l
		end

		local EVENTS = {}
		-- a toast
		EVENTS[#EVENTS + 1] = function() win:Notify(pick(TOASTS), 2.6) end
		EVENTS[#EVENTS + 1] = function() win:Notify(pick(TOASTS), 2.6) end
		-- an alien walks across the screen and says something
		EVENTS[#EVENTS + 1] = function()
			local fromLeft = math.random() < 0.5
			local y = rnd(0.2, 0.8)
			floater("\u{1F47D}", 64, fromLeft and -0.05 or 1.05, y, fromLeft and 1.05 or -0.05, y + rnd(-0.15, 0.15), rnd(4, 6), rnd(-90, 90))
			win:Notify("Alien: " .. pick(ALIENS), 3)
		end
		-- a UFO flies over
		EVENTS[#EVENTS + 1] = function()
			local fromLeft = math.random() < 0.5
			local y = rnd(0.08, 0.3)
			floater("\u{1F6F8}", 72, fromLeft and -0.1 or 1.1, y, fromLeft and 1.1 or -0.1, y + rnd(-0.05, 0.1), rnd(3, 5), 0)
		end
		-- words floating up
		EVENTS[#EVENTS + 1] = function()
			for _ = 1, math.random(3, 6) do
				local x = rnd(0.1, 0.9)
				floater(pick(WORDS), math.random(22, 40), x, rnd(0.6, 1.0), x + rnd(-0.15, 0.15), rnd(0.0, 0.3), rnd(2.5, 4), rnd(-40, 40))
			end
		end
		-- colour flash
		EVENTS[#EVENTS + 1] = function()
			local f = Instance.new("Frame")
			f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = Color3.fromHSV(math.random(), 0.8, 1); f.BackgroundTransparency = 0.82; f.BorderSizePixel = 0; f.Active = false; f.Parent = gui
			tween(f, 0.9, { BackgroundTransparency = 1 })
			task.delay(1, function() pcall(function() f:Destroy() end) end)
		end
		-- the menu does a full spin
		EVENTS[#EVENTS + 1] = function()
			if flipping then return end
			flipping = true
			holder.Rotation = 0
			local tw = tween(holder, 1.4, { Rotation = 360 }, Enum.EasingStyle.Back, Enum.EasingDirection.InOut)
			tw.Completed:Connect(function() holder.Rotation = 0; flipping = false end)
		end
		-- a burst of shaking
		EVENTS[#EVENTS + 1] = function()
			task.spawn(function()
				local t = os.clock()
				while os.clock() - t < 1.2 and alive do
					pcall(function() holder.Position = holder.Position + UDim2.fromOffset(rnd(-6, 6), rnd(-6, 6)) end)
					task.wait(0.03)
				end
			end)
		end
		-- a fake "drunk level" bar
		EVENTS[#EVENTS + 1] = function() win:Notify(("Drunk level: %d%%  (the menu, not you)"):format(math.random(40, 99)), 2.6) end
		-- the menu goes small, then big
		EVENTS[#EVENTS + 1] = function()
			task.spawn(function()
				baseScale = (win.baseScale or 1) * 0.7
				task.wait(1.2)
				baseScale = (win.baseScale or 1) * 1.15
				task.wait(1.2)
				baseScale = win.baseScale or 1
			end)
		end

		win:Notify("...is it me or is the menu a little wobbly?", 4)

		-- the sway every frame, the accent colour twice a second
		local t0, lastHue = os.clock(), 0
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			if t >= SECONDS or not alive then return end
			pcall(function()
				if not flipping then holder.Rotation = math.sin(t * 1.7) * 3.2 + math.sin(t * 4.1) * 0.8 end
				scale.Scale = baseScale * (1 + 0.025 * math.sin(t * 2.3))
			end)
			if os.clock() - lastHue > 0.5 then
				lastHue = os.clock()
				pcall(function() win:ApplyPalette(UI.Palette(Color3.fromHSV((t * 0.12) % 1, 0.7, 1))) end)
			end
		end)

		-- the schedule: an event every 1 to 2.2 seconds, a new question every 7 seconds
		local lastQ = os.clock()
		while os.clock() - t0 < SECONDS and alive do
			EVENTS[math.random(#EVENTS)]()
			if os.clock() - lastQ > 7 then lastQ = os.clock(); showQuestion() end
			task.wait(rnd(1, 2.2))
		end

		alive = false
		if conn then conn:Disconnect() end
		pcall(function()
			holder.Rotation = 0
			scale.Scale = win.baseScale or baseScale
			if restore then restore() end
		end)
		qLabel.Text = "...ok that is enough. Back to normal. You did not see anything. (Feyzi did.)"
		b1.Text = "Okay"; b2.Text = "Hic"
		b1.MouseButton1Click:Connect(function() gui:Destroy() end)
		b2.MouseButton1Click:Connect(function() gui:Destroy() end)
		task.wait(6)
		pcall(function() gui:Destroy() end)
	end)
end

return Prank

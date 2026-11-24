-- Aim modules: Camlock (hold / toggle, snaps the camera onto the best target), Aim Assist (a soft pull while you hold a mouse button) and Triggerbot
-- (clicks when your crosshair is on a player). Customisable: body part, field of view, smoothness, range, wall check, prediction, target priority,
-- teams, wanted only, target line and a styled field-of-view circle.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local Aim = {
	Enabled = false, Hold = true, Part = "Head", FOV = 180, Smooth = 0.3, MaxDist = 400, WallCheck = true, Prediction = 0.06,
	Sticky = true, WantedOnly = false, ShowFOV = true, MouseLock = false, Priority = "Crosshair", ShowLine = false,
	FovColor = Color3.fromRGB(235, 235, 240), FovThick = 1.2, FovFilled = false, LineColor = Color3.fromRGB(231, 76, 60),
	AssistEnabled = false, AssistFOV = 140, AssistStrength = 0.16, AssistButton = "Right",
	Trigger = false, TriggerDelay = 0.09, TriggerRange = 300, TriggerKey = nil, TriggerHold = false,
	Teams = { Police = true, FireDepartment = true, Citizen = true, Other = true },
	Active = false, Target = nil, Info = "off", Shots = 0,
}
local PARTS = { "Head", "Torso", "Root" }
Aim.PartList = PARTS
Aim.Priorities = { "Crosshair", "Distance", "Health" }
Aim.AssistButtons = { "Right", "Left", "Always" }

local gui, circle, circleStroke, line, rp
local lastT
local lockedMouse, prevMouse = false, nil
local lastShot = 0

local function releaseMouse()
	if lockedMouse then
		lockedMouse = false
		pcall(function() UIS.MouseBehavior = prevMouse or Enum.MouseBehavior.Default end)
	end
end
local BIND = "ScrdsxCamlock"

local function guiParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	ok, h = pcall(function() return game:GetService("CoreGui") end)
	if ok and h then return h end
	return lp:WaitForChild("PlayerGui")
end

local function groupOf(plr)
	local n = plr.Team and plr.Team.Name or "Citizen"
	return (n == "Police" or n == "FireDepartment" or n == "Citizen") and n or "Other"
end

local function partOf(ch)
	if Aim.Part == "Head" then return ch:FindFirstChild("Head") end
	if Aim.Part == "Torso" then return ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso") or ch:FindFirstChild("HumanoidRootPart") end
	return ch:FindFirstChild("HumanoidRootPart")
end

local function usable(plr, cam, origin, range)
	if plr == lp or not Aim.Teams[groupOf(plr)] then return nil end
	local ch = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	local part = ch and partOf(ch)
	if not (hum and hrp and part and hum.Health > 0) then return nil end
	if Aim.WantedOnly and hrp:GetAttribute("IsWanted") ~= true then return nil end
	if (hrp.Position - origin).Magnitude > (range or Aim.MaxDist) then return nil end
	local pos = part.Position + part.AssemblyLinearVelocity * Aim.Prediction
	if Aim.WallCheck then
		rp.FilterDescendantsInstances = { lp.Character }
		local res = workspace:Raycast(cam.CFrame.Position, pos - cam.CFrame.Position, rp)
		if res and not res.Instance:IsDescendantOf(ch) then return nil end
	end
	return pos, ch, hum
end

-- the best player inside `fov` pixels of `center`, by the chosen priority (closest to the crosshair, nearest, or weakest)
local function pickTarget(cam, origin, center, fov)
	local best, bestScore, bestPos
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		local part = ch and partOf(ch)
		if part then
			local sp, on = cam:WorldToViewportPoint(part.Position)
			if on then
				local dpx = (Vector2.new(sp.X, sp.Y) - center).Magnitude
				if dpx <= fov then
					local pos, _, hum = usable(plr, cam, origin)
					if pos then
						local score = dpx
						if Aim.Priority == "Distance" then score = (part.Position - origin).Magnitude
						elseif Aim.Priority == "Health" then score = hum.Health end
						if not bestScore or score < bestScore then best, bestScore, bestPos = plr, score, pos end
					end
				end
			end
		end
	end
	return best, bestPos
end

local function pull(cam, aimPos, smooth, dt)
	local want = CFrame.lookAt(cam.CFrame.Position, aimPos)
	-- frame-rate independent smoothing: 1 = snap, small = slow glide
	local a = 1 - (1 - math.clamp(smooth, 0.02, 1)) ^ ((dt or 0.016) * 60)
	cam.CFrame = cam.CFrame:Lerp(want, a)
end

local function click()
	local ok = pcall(function()
		if mouse1click then mouse1click() else
			local vim = game:GetService("VirtualInputManager")
			local m = UIS:GetMouseLocation()
			vim:SendMouseButtonEvent(m.X, m.Y, 0, true, game, 0)
			task.delay(0.02, function() vim:SendMouseButtonEvent(m.X, m.Y, 0, false, game, 0) end)
		end
	end)
	return ok
end

local function triggerStep(cam, origin)
	if not Aim.Trigger then return end
	if os.clock() - lastShot < Aim.TriggerDelay then return end
	if Aim.TriggerHold and not (Aim.TriggerKey and UIS:IsKeyDown(Aim.TriggerKey)) then return end
	if UIS:GetFocusedTextBox() then return end
	local mouse = lp:GetMouse()
	local tgt = mouse and mouse.Target
	if not tgt then return end
	local model = tgt:FindFirstAncestorOfClass("Model")
	local plr = model and Players:GetPlayerFromCharacter(model)
	if not plr then return end
	local pos = usable(plr, cam, origin, Aim.TriggerRange)
	if not pos then return end
	lastShot = os.clock()
	if click() then Aim.Shots = Aim.Shots + 1 end
end

local fc = {} -- what the FOV circle shows now
local function step(dt)
	if not gui then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vs = cam.ViewportSize
	local center = (UIS.MouseBehavior == Enum.MouseBehavior.LockCenter) and Vector2.new(vs.X / 2, vs.Y / 2) or UIS:GetMouseLocation()
	local origin = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	origin = origin and origin.Position or cam.CFrame.Position

	-- field of view circle (colour, thickness, optional fill)
	-- every property is only written when it changed (writes are what costs frames)
	local show = (Aim.Enabled or Aim.AssistEnabled) and Aim.ShowFOV
	if circle.Visible ~= show then circle.Visible = show end
	if show then
		local fov = (Aim.Enabled and Aim.FOV) or Aim.AssistFOV
		local cx, cy = math.floor(center.X + .5), math.floor(center.Y + .5)
		local key = fov .. ":" .. cx .. ":" .. cy
		if fc.key ~= key then fc.key = key; circle.Size = UDim2.fromOffset(fov * 2, fov * 2); circle.Position = UDim2.fromOffset(cx, cy) end
		local bt = Aim.FovFilled and 0.9 or 1
		if fc.bt ~= bt then fc.bt = bt; circle.BackgroundTransparency = bt end
		if fc.bc ~= Aim.FovColor then fc.bc = Aim.FovColor; circle.BackgroundColor3 = Aim.FovColor end
		if fc.th ~= Aim.FovThick then fc.th = Aim.FovThick; circleStroke.Thickness = Aim.FovThick end
		local sc = Aim.Active and Color3.fromRGB(236, 190, 120) or Aim.FovColor
		if fc.sc ~= sc then fc.sc = sc; circleStroke.Color = sc end
		local st = Aim.Active and 0.1 or 0.5
		if fc.st ~= st then fc.st = st; circleStroke.Transparency = st end
	end
	-- mouse lock: while aiming the cursor sits in the screen centre (like shift lock); let go again afterwards
	if Aim.Enabled and Aim.Active and Aim.MouseLock then
		if UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			if not lockedMouse then prevMouse = UIS.MouseBehavior end
			lockedMouse = true
			UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
	else
		releaseMouse()
	end

	triggerStep(cam, origin)

	local aimPos
	if Aim.Enabled and Aim.Active then
		-- keep the current target while the key is held (sticky), otherwise pick by priority inside the FOV
		if Aim.Sticky and Aim.Target then
			local pos = usable(Aim.Target, cam, origin)
			if pos then aimPos = pos else Aim.Target = nil end
		end
		if not aimPos then Aim.Target, aimPos = pickTarget(cam, origin, center, Aim.FOV) end
		-- tell the UI when the lock changes (a new player, or the target was lost)
		if Aim.Target ~= lastT then
			lastT = Aim.Target
			if Aim.OnTarget then task.spawn(Aim.OnTarget, Aim.Target) end
		end
		if aimPos then pull(cam, aimPos, Aim.Smooth, dt) end
	else
		Aim.Target, lastT = nil, nil
		-- aim assist: a gentle pull towards the nearest player to the crosshair while the chosen mouse button is held
		if Aim.AssistEnabled then
			local held = Aim.AssistButton == "Always"
				or (Aim.AssistButton == "Right" and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
				or (Aim.AssistButton == "Left" and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
			if held then
				local plr, pos = pickTarget(cam, origin, center, Aim.AssistFOV)
				if pos then aimPos = pos; pull(cam, pos, Aim.AssistStrength, dt) end
			end
		end
	end

	-- line from the crosshair to the target
	local showLine = Aim.ShowLine and aimPos ~= nil
	line.Visible = showLine
	if showLine then
		local sp = cam:WorldToViewportPoint(aimPos)
		local a, b = center, Vector2.new(sp.X, sp.Y)
		local d = b - a
		line.Size = UDim2.fromOffset(d.Magnitude, 1.6)
		line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
		line.Rotation = math.deg(math.atan2(d.Y, d.X))
		line.BackgroundColor3 = Aim.LineColor
	end
end

-- key down / up from the keybind (hold mode follows the key, toggle mode flips on press)
function Aim.KeyEvent(down)
	if not Aim.Enabled then return end
	if Aim.Hold then Aim.Active = down
	elseif down then Aim.Active = not Aim.Active end
	if not Aim.Active then Aim.Target = nil end
	Aim.Info = Aim.Active and "aiming" or "ready"
	if Aim.Changed then Aim.Changed() end
end

function Aim.SetEnabled(v)
	Aim.Enabled = v
	if not v then Aim.Active, Aim.Target = false, nil; releaseMouse() end
	Aim.Info = v and "ready" or "off"
	if Aim.Changed then Aim.Changed() end
end

function Aim.Start()
	if gui then return end
	rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 3
	gui.Parent = guiParent()
	circle = Instance.new("Frame")
	circle.AnchorPoint = Vector2.new(.5, .5); circle.BackgroundTransparency = 1; circle.BorderSizePixel = 0; circle.Visible = false; circle.Parent = gui
	Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)
	circleStroke = Instance.new("UIStroke"); circleStroke.Thickness = 1.2; circleStroke.Color = Color3.fromRGB(235, 235, 240); circleStroke.Parent = circle
	line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(.5, .5); line.BorderSizePixel = 0; line.BackgroundColor3 = Aim.LineColor; line.Visible = false; line.Parent = gui
	pcall(function()
		RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
			local ok, err = pcall(step, dt)
			if not ok and Aim.Info ~= "error" then Aim.Info = "error"; warn("[aim] " .. tostring(err)) end
		end)
	end)
end

function Aim.Destroy()
	releaseMouse()
	Aim.OnTarget = nil
	pcall(function() RunService:UnbindFromRenderStep(BIND) end)
	if gui then pcall(function() gui:Destroy() end) end
	gui, circle, circleStroke, line = nil, nil, nil, nil
	Aim.Enabled, Aim.Active, Aim.Target = false, false, nil
	Aim.AssistEnabled, Aim.Trigger = false, false
end

return Aim

-- Camlock: turns the camera towards the best player while you hold (or toggle) the key. Customisable: which body part, field of view,
-- smoothness, range, wall check, movement prediction, which teams, wanted players only. Draws the field-of-view circle.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local Aim = {
	Enabled = false, Hold = true, Part = "Head", FOV = 180, Smooth = 0.3, MaxDist = 400, WallCheck = true, Prediction = 0.06,
	Sticky = true, WantedOnly = false, ShowFOV = true,
	Teams = { Police = true, FireDepartment = true, Citizen = true, Other = true },
	Active = false, Target = nil, Info = "off",
}
local PARTS = { "Head", "Torso", "Root" }
Aim.PartList = PARTS

local gui, circle, circleStroke, rp
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

local function usable(plr, cam, origin)
	if plr == lp or not Aim.Teams[groupOf(plr)] then return nil end
	local ch = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	local part = ch and partOf(ch)
	if not (hum and hrp and part and hum.Health > 0) then return nil end
	if Aim.WantedOnly and hrp:GetAttribute("IsWanted") ~= true then return nil end
	if (hrp.Position - origin).Magnitude > Aim.MaxDist then return nil end
	local pos = part.Position + part.AssemblyLinearVelocity * Aim.Prediction
	if Aim.WallCheck then
		rp.FilterDescendantsInstances = { lp.Character }
		local res = workspace:Raycast(cam.CFrame.Position, pos - cam.CFrame.Position, rp)
		if res and not res.Instance:IsDescendantOf(ch) then return nil end
	end
	return pos, ch
end

local function step(dt)
	if not gui then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vs = cam.ViewportSize
	local center = (UIS.MouseBehavior == Enum.MouseBehavior.LockCenter) and Vector2.new(vs.X / 2, vs.Y / 2) or UIS:GetMouseLocation()
	circle.Visible = Aim.Enabled and Aim.ShowFOV
	if circle.Visible then
		circle.Size = UDim2.fromOffset(Aim.FOV * 2, Aim.FOV * 2)
		circle.Position = UDim2.fromOffset(center.X, center.Y)
		circleStroke.Color = Aim.Active and Color3.fromRGB(255, 82, 82) or Color3.fromRGB(235, 235, 240)
		circleStroke.Transparency = Aim.Active and 0.1 or 0.55
	end
	if not (Aim.Enabled and Aim.Active) then Aim.Target = nil; return end

	local origin = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	origin = origin and origin.Position or cam.CFrame.Position

	-- keep the current target while the key is held (sticky), otherwise pick the one closest to the crosshair inside the FOV
	local aimPos
	if Aim.Sticky and Aim.Target then
		local plr = Aim.Target
		local pos = usable(plr, cam, origin)
		if pos then aimPos = pos else Aim.Target = nil end
	end
	if not aimPos then
		local best, bestD, bestPos
		for _, plr in ipairs(Players:GetPlayers()) do
			local ch = plr.Character
			local part = ch and partOf(ch)
			if part then
				local sp, on = cam:WorldToViewportPoint(part.Position)
				if on then
					local dpx = (Vector2.new(sp.X, sp.Y) - center).Magnitude
					if dpx <= Aim.FOV and (not bestD or dpx < bestD) then
						local pos = usable(plr, cam, origin)
						if pos then best, bestD, bestPos = plr, dpx, pos end
					end
				end
			end
		end
		Aim.Target, aimPos = best, bestPos
	end
	if not aimPos then return end

	local want = CFrame.lookAt(cam.CFrame.Position, aimPos)
	-- frame-rate independent smoothing: Smooth 1 = snap, small = slow glide
	local a = 1 - (1 - math.clamp(Aim.Smooth, 0.02, 1)) ^ ((dt or 0.016) * 60)
	cam.CFrame = cam.CFrame:Lerp(want, a)
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
	if not v then Aim.Active, Aim.Target = false, nil end
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
	pcall(function()
		RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
			local ok, err = pcall(step, dt)
			if not ok and Aim.Info ~= "error" then Aim.Info = "error"; warn("[aim] " .. tostring(err)) end
		end)
	end)
end

function Aim.Destroy()
	pcall(function() RunService:UnbindFromRenderStep(BIND) end)
	if gui then pcall(function() gui:Destroy() end) end
	gui, circle, circleStroke = nil, nil, nil
	Aim.Enabled, Aim.Active, Aim.Target = false, false, nil
end

return Aim

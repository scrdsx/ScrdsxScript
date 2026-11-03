-- Vehicle fly: while seated in a car, the whole car flies where the camera points.
-- W/S forward/back along the camera, A/D strafe, Space up, LeftControl down. Releasing everything hovers.
-- UNTESTED: sets the car's assembly velocity every frame (you own its physics while driving).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local Fly = {
	Enabled = false,
	Speed = 80,        -- studs/s along the camera
	VSpeed = 50,       -- studs/s for Space / LeftControl
	Accel = 0.25,      -- 0.05 (floaty) .. 1 (instant)
	Stabilize = true,  -- kill spin so the car does not tumble
	Boost = 2,         -- speed multiplier while LeftShift is held
	SteerMode = true,  -- A/D turn the car and W/S follow its heading (off: camera flight, A/D strafe)
	TurnSpeed = 2.5,   -- rad/s while A or D is held
	ReverseHeading = false, -- flip if W flies the car backwards
}
local lp = Players.LocalPlayer
local conn, vel

local function seat()
	local c = lp.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h and h.SeatPart
end

function Fly.SetEnabled(v)
	Fly.Enabled = v
	vel = nil
end

function Fly.Start()
	conn = RunService.Heartbeat:Connect(function(dt)
		if not Fly.Enabled then return end
		local s = seat()
		local cam = workspace.CurrentCamera
		if not s or not cam then vel = nil; return end
		local root = s.AssemblyRootPart or s
		vel = vel or root.AssemblyLinearVelocity

		local want, turn = Vector3.zero, 0
		if not UIS:GetFocusedTextBox() then
			local f = (UIS:IsKeyDown(Enum.KeyCode.W) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
			local r = (UIS:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
			local u = (UIS:IsKeyDown(Enum.KeyCode.Space) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.LeftControl) and 1 or 0)
			local horiz
			if Fly.SteerMode then
				-- A/D turn the car; W/S go along its heading
				turn = -r * Fly.TurnSpeed
				local fwd = s.CFrame.LookVector * (Fly.ReverseHeading and -1 or 1)
				fwd = Vector3.new(fwd.X, 0, fwd.Z)
				horiz = fwd.Magnitude > 0.01 and fwd.Unit * f or Vector3.zero
			else
				-- camera mode: W/S along the camera, A/D strafe
				horiz = cam.CFrame.LookVector * f + cam.CFrame.RightVector * r
			end
			if horiz.Magnitude > 0 then want = horiz.Unit * Fly.Speed end
			want += Vector3.new(0, u * Fly.VSpeed, 0)
			if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then want *= Fly.Boost end
		end

		local a = 1 - (1 - math.clamp(Fly.Accel, 0.01, 1)) ^ (dt * 60)
		vel = vel:Lerp(want, a)
		root.AssemblyLinearVelocity = vel -- includes cancelling gravity: no input = hover
		if turn ~= 0 then
			local av = root.AssemblyAngularVelocity
			root.AssemblyAngularVelocity = Fly.Stabilize and Vector3.new(0, turn, 0) or Vector3.new(av.X, turn, av.Z)
		elseif Fly.Stabilize then
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

function Fly.Destroy()
	Fly.Enabled = false
	if conn then conn:Disconnect(); conn = nil end
end

return Fly

-- punch_probe.lua : captures EVERYTHING about your character at the moment you punch, so the AutoFarm can copy it.
-- Run it, walk to a cash register that is not on cooldown (Tool Shop / gas station / clothing store / farm shop), punch it by hand
-- until it breaks (or at least 4-5 punches), then press End. Report -> clipboard + workspace/punch_report.txt
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
if env.PunchProbe then pcall(env.PunchProbe.Stop) end

local PUNCH_ID = "cc21144d-23ac-4754-8144-1a3f985e016a"
local T0 = os.clock()
local out, active, conns = {}, true, {}
local function log(s) out[#out + 1] = ("[+%6.2f] %s"):format(os.clock() - T0, s) end
local function full(i) local ok, r = pcall(game.GetFullName, i); return ok and r or tostring(i) end
local function v3(v) return ("(%.1f,%.1f,%.1f)"):format(v.X, v.Y, v.Z) end

local function snapshot(tag)
	local c = lp.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then log(tag .. ": no character"); return end
	log(("%s: hrp=%s look=%s vel=%.1f"):format(tag, v3(hrp.Position), v3(hrp.CFrame.LookVector), hrp.AssemblyLinearVelocity.Magnitude))
	log(("   hum: state=%s walkSpeed=%.1f jump=%s autoRotate=%s platformStand=%s sit=%s moveDir=%s floor=%s health=%.0f"):format(
		tostring(hum:GetState()), hum.WalkSpeed, tostring(hum.Jump), tostring(hum.AutoRotate), tostring(hum.PlatformStand), tostring(hum.Sit),
		v3(hum.MoveDirection), tostring(hum.FloorMaterial), hum.Health))
	local tools = {}
	for _, ch in ipairs(c:GetChildren()) do if ch:IsA("Tool") then tools[#tools + 1] = ch.Name end end
	log("   tools in hand: [" .. table.concat(tools, ",") .. "]   backpack: " .. tostring(#(lp:FindFirstChild("Backpack") and lp.Backpack:GetChildren() or {})))
	local tracks = {}
	pcall(function()
		for _, t in ipairs(hum:FindFirstChildOfClass("Animator"):GetPlayingAnimationTracks()) do
			tracks[#tracks + 1] = ("%s(%s, w=%.2f, t=%.2f)"):format(t.Name, tostring(t.Animation and t.Animation.AnimationId), t.WeightCurrent, t.TimePosition)
		end
	end)
	log("   animations playing: " .. table.concat(tracks, " | "))
	local at = {}
	for k, v in pairs(c:GetAttributes()) do at[#at + 1] = k .. "=" .. tostring(v):sub(1, 24) end
	for k, v in pairs(hrp:GetAttributes()) do at[#at + 1] = "hrp." .. k .. "=" .. tostring(v):sub(1, 24) end
	table.sort(at)
	log("   char attrs: " .. table.concat(at, ", "))
	local cam = workspace.CurrentCamera
	if cam then log(("   camera: pos=%s look=%s type=%s fov=%.0f"):format(v3(cam.CFrame.Position), v3(cam.CFrame.LookVector), tostring(cam.CameraType), cam.FieldOfView)) end
	local mouse = lp:GetMouse()
	log(("   mouse: target=%s hit=%s behavior=%s"):format(mouse.Target and full(mouse.Target) or "nil", mouse.Hit and v3(mouse.Hit.Position) or "-", tostring(UIS.MouseBehavior)))
	-- nearest register
	local best, bd
	for _, m in ipairs(CS:GetTagged("Cash Register")) do
		local p = m:IsA("Model") and m:GetPivot().Position or (m:IsA("BasePart") and m.Position)
		if p then
			local d = (p - hrp.Position).Magnitude
			if not bd or d < bd then best, bd = m, d end
		end
	end
	if best then
		local p = best:GetPivot().Position
		local flat = Vector3.new(p.X - hrp.Position.X, 0, p.Z - hrp.Position.Z)
		log(("   nearest register: %s dist=%.1f facing=%.2f health=%s timedOut=%s"):format(full(best), bd, flat.Magnitude > 0.1 and hrp.CFrame.LookVector:Dot(flat.Unit) or 0,
			tostring(best:GetAttribute("Health")), tostring(best:GetAttribute("TimedOut"))))
		return best
	end
end

local queue = {}
pcall(function()
	local old
	old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local m = getnamecallmethod()
		if active and m == "FireServer" and typeof(self) == "Instance" and self.Name == PUNCH_ID then
			queue[#queue + 1] = os.clock()
		end
		setnamecallmethod(m)
		return old(self, ...)
	end))
end)

local punches = 0
task.spawn(function()
	while active do
		task.wait(0.05)
		while #queue > 0 do
			local t = table.remove(queue, 1)
			punches = punches + 1
			log(("========== PUNCH %d (sent %.2fs ago) =========="):format(punches, os.clock() - t))
			local reg = snapshot("at punch")
			if reg then
				local h = reg:GetAttribute("Health")
				task.delay(0.5, function() log(("   0.5s later: register health %s -> %s"):format(tostring(h), tostring(reg:GetAttribute("Health")))) end)
			end
		end
	end
end)

local function finish()
	if not active then return end
	active = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	local txt = table.concat(out, "
")
	local ok = pcall(function() setclipboard(txt) end)
	pcall(function() writefile("punch_report.txt", txt) end)
	print("[punch] " .. #out .. " lines " .. (ok and "copied to clipboard" or "(clipboard failed)") .. " + workspace/punch_report.txt")
end

-- everything else your input does around the punch (clicks, keys)
table.insert(conns, UIS.InputBegan:Connect(function(i, gp)
	if not active then return end
	if i.KeyCode == Enum.KeyCode.End then
		finish()
	elseif i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		log(("input: left click gameProcessed=%s"):format(tostring(gp)))
	elseif i.UserInputType == Enum.UserInputType.Keyboard then
		log(("input: key %s gameProcessed=%s"):format(i.KeyCode.Name, tostring(gp)))
	end
end))
env.PunchProbe = { Stop = function() active = false end, Finish = finish }
log("recording; punch a register, then press End (or run getgenv().PunchProbe.Finish())")
print("[punch] recording - punch a cash register by hand, then press End (or run getgenv().PunchProbe.Finish())")

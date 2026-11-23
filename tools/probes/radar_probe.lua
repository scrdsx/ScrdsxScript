-- radar_probe.lua : records a REAL radar gun measurement so Radar Farm can copy it exactly.
-- Run it (Radar Farm OFF), be Police, hold the radar gun, aim (right mouse) at a car going over the limit and click to measure.
-- Do 2-3 measurements (one that fines, if you can), then press End. Report -> clipboard + workspace/radar_report.txt
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
if env.RadarProbe then pcall(env.RadarProbe.Stop) end

local T0 = os.clock()
local out, active, conns = {}, true, {}
local function log(s) out[#out + 1] = ("[+%6.2f] %s"):format(os.clock() - T0, s) end
local function full(i) local ok, r = pcall(game.GetFullName, i); return ok and r or tostring(i) end
local function v3(v) return ("(%.2f,%.2f,%.2f)"):format(v.X, v.Y, v.Z) end
local function fmt(v, depth)
	depth = depth or 0
	local t = typeof(v)
	if t == "Instance" then
		local tags = {}
		pcall(function() tags = CS:GetTags(v) end)
		return ("<%s %s tags=[%s]>"):format(v.ClassName, full(v), table.concat(tags, ","))
	elseif t == "Vector3" then return "V3" .. v3(v)
	elseif t == "CFrame" then return "CF" .. v3(v.Position) .. " look" .. v3(v.LookVector)
	elseif t == "table" then
		if depth > 3 then return "{...}" end
		local p = {}
		for k, x in pairs(v) do p[#p + 1] = tostring(k) .. "=" .. fmt(x, depth + 1) end
		return "{" .. table.concat(p, ", ") .. "}"
	elseif t == "string" then return ("%q"):format(v:sub(1, 120))
	end
	return t .. ":" .. tostring(v)
end
local function fmtArgs(p) local r = {} for i = 1, p.n do r[i] = fmt(p[i]) end return table.concat(r, "  ,  ") end

-- state
local function state(tag)
	log("== " .. tag)
	log("team=" .. tostring(lp.Team and lp.Team.Name))
	local at = {}
	for k, v in pairs(lp:GetAttributes()) do at[#at + 1] = k .. "=" .. tostring(v):sub(1, 30) end
	log("player attributes: " .. table.concat(at, "  "))
	local c = lp.Character
	if c then
		local ca = {}
		for k, v in pairs(c:GetAttributes()) do ca[#ca + 1] = k .. "=" .. tostring(v):sub(1, 30) end
		log("character attributes: " .. table.concat(ca, "  "))
	end
	for _, root in ipairs({ c, lp:FindFirstChildOfClass("Backpack") }) do
		if root then
			for _, t in ipairs(root:GetChildren()) do
				if t:IsA("Tool") then
					local ta = {}
					for k, v in pairs(t:GetAttributes()) do ta[#ta + 1] = k .. "=" .. tostring(v):sub(1, 30) end
					log(("tool %s  in=%s  %s  attrs: %s"):format(t.Name, root.Name, fmt(t), table.concat(ta, " ")))
				end
			end
		end
	end
	if env.ScrdsxRadarInfo then log("Radar Farm: " .. tostring(env.ScrdsxRadarInfo())) end
end
state("start")

-- client -> server (everything with an Instance or Vector3 argument, plus any mBd call)
local queue = {}
pcall(function()
	local old
	old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local m = getnamecallmethod()
		if active and (m == "FireServer" or m == "InvokeServer") then
			queue[#queue + 1] = { self, m, table.pack(...), debug.traceback and "" }
		end
		setnamecallmethod(m)
		return old(self, ...)
	end))
end)
local count = {}
task.spawn(function()
	while active do
		task.wait(0.05)
		while #queue > 0 do
			local q = table.remove(queue, 1)
			local key = full(q[1])
			count[key] = (count[key] or 0) + 1
			local interesting = false
			for i = 1, q[3].n do local t = typeof(q[3][i]); if t == "Instance" or t == "Vector3" then interesting = true end end
			if interesting and count[key] <= 25 then
				log(("C>S %s %s (%s)"):format(q[2], key, fmtArgs(q[3])))
			end
		end
	end
end)

-- server -> client: notifications and anything that looks like one
local mb = RS:FindFirstChild("mBd")
if mb then
	for _, r in ipairs(mb:GetChildren()) do
		if r:IsA("RemoteEvent") then
			conns[#conns + 1] = r.OnClientEvent:Connect(function(...)
				if not active then return end
				local p = table.pack(...)
				for i = 1, p.n do
					if type(p[i]) == "table" and (p[i].title or p[i].message) then
						log(("S>C %s (%s)"):format(r.Name, fmtArgs(p)))
						return
					end
				end
			end)
		end
	end
else
	log("no ReplicatedStorage.mBd folder!")
end

-- what the game's radar display shows (speed, measuring)
conns[#conns + 1] = UIS.InputBegan:Connect(function(i, gp)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		local c = lp.Character
		local tool = c and c:FindFirstChildOfClass("Tool")
		local head = c and c:FindFirstChild("Head")
		local cam = workspace.CurrentCamera
		if tool and head then
			log(("click: tool=%s head=%s cam=%s look=%s"):format(tool.Name, v3(head.Position), v3(cam.CFrame.Position), v3(cam.CFrame.LookVector)))
		end
	end
end)

local function stop()
	if not active then return end
	state("end")
	active = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	local txt = table.concat(out, "\n")
	pcall(function() writefile("radar_report.txt", txt) end)
	local ok = pcall(function() setclipboard(txt) end)
	print("[radar probe] done, " .. #out .. " lines" .. (ok and " (copied)" or ""))
end
env.RadarProbe = { Stop = stop }
conns[#conns + 1] = UIS.InputBegan:Connect(function(i) if i.KeyCode == Enum.KeyCode.End then stop() end end)
print("[radar probe] running: measure a speeding car with the radar gun 2-3 times, then press End")

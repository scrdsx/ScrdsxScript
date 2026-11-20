-- Ragdoll Soccer helpers (built from the dump of the game, 2026-11-20). Only loaded in the soccer places.
--  * Speed: your player moves through a ControllerManager; its BaseMoveSpeed is multiplied (the game can still change it, the boost follows).
--  * Aim at goal ("Ronaldini Banini"): when you shoot roughly towards the opponent's goal, the shot is turned to a corner of that goal. The kick plan (KickPlan.dir) and
--    the release velocity / spin (DribbleRelease) are rotated together so they still agree with each other.
--  * Perfect accuracy: the game's own random miss on kicks is set to 0 (Kick.Rules.Miss).
--  * Sticky ball: the reach of the game's pickup rules (Dribble.Rules.Pickup) is widened, so the ball is taken and kept from further away.
-- What the server accepts is not guaranteed: every part can be switched off on its own.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer

local Soccer = {
	Speed = false, SpeedMult = 1.25,
	Aim = false, Cone = 70, MaxDist = 90, Corner = "Far from keeper", Notify = nil,
	Accurate = false,
	Sticky = false, StickyMult = 1.5,
	Info = "off", Shots = 0,
}
Soccer.Corners = { "Far from keeper", "Left post", "Right post", "Centre" }

local conn
local oldNC
local hooked = false

-- SPEED -----------------------------------------------------------------------------------------------------------------------
local lastSet = setmetatable({}, { __mode = "k" }) -- controller manager -> the value we wrote
local function speedStep()
	if not Soccer.Speed then return end
	local ch = lp.Character
	local cm = ch and ch:FindFirstChildOfClass("ControllerManager")
	if not cm then return end
	local cur = cm.BaseMoveSpeed
	local mine = lastSet[cm]
	if mine == nil or math.abs(cur - mine) > 1e-3 then
		-- the game wrote its own value: boost that one
		local want = cur * Soccer.SpeedMult
		lastSet[cm] = want
		cm.BaseMoveSpeed = want
	end
end

function Soccer.SetSpeed(on)
	Soccer.Speed = on
	if not on then
		local ch = lp.Character
		local cm = ch and ch:FindFirstChildOfClass("ControllerManager")
		if cm and lastSet[cm] and Soccer.SpeedMult ~= 0 then
			pcall(function() cm.BaseMoveSpeed = cm.BaseMoveSpeed / Soccer.SpeedMult end)
			lastSet[cm] = nil
		end
	end
end
function Soccer.SetSpeedMult(v)
	-- re-base: undo the old boost, the next frame applies the new one
	local ch = lp.Character
	local cm = ch and ch:FindFirstChildOfClass("ControllerManager")
	if Soccer.Speed and cm and lastSet[cm] and Soccer.SpeedMult ~= 0 then
		pcall(function() cm.BaseMoveSpeed = cm.BaseMoveSpeed / Soccer.SpeedMult end)
		lastSet[cm] = nil
	end
	Soccer.SpeedMult = v
end

-- GOAL AIM --------------------------------------------------------------------------------------------------------------------
local function goals()
	local list = {}
	for _, inst in ipairs(CS:GetTagged("SoccerGoalFrame")) do
		local pos, size
		if inst:IsA("Model") then
			local ok, cf, sz = pcall(function() return inst:GetBoundingBox() end)
			if ok then pos, size = cf.Position, sz end
		elseif inst:IsA("BasePart") then
			pos, size = inst.Position, inst.Size
		end
		if pos then list[#list + 1] = { pos = pos, size = size } end
	end
	return list
end

-- where to shoot: a corner of the goal the player's team attacks
local function targetFor(ballPos)
	local ch = lp.Character
	local team = ch and ch:GetAttribute("Team")
	if team ~= "Blue" and team ~= "Red" then return nil end
	local g = goals()
	if #g < 2 then return nil end
	local cx = 0
	for _, x in ipairs(g) do cx = cx + x.pos.X end
	cx = cx / #g
	local side = workspace:GetAttribute("BlueSide") == 1 and 1 or -1
	local own = team == "Blue" and side or -side -- our own goal is on this side of the pitch (sign of x)
	local goal
	for _, x in ipairs(g) do
		if (x.pos.X - cx) * own < 0 then goal = x end -- the goal on the other side
	end
	if not goal then return nil end
	-- the goal mouth runs along Z; stay inside the posts
	local half = math.max(goal.size.Z, goal.size.X) / 2
	local off = math.max(half * 0.62, 1)
	local gz = goal.pos.Z
	local zs
	if Soccer.Corner == "Left post" then zs = -1
	elseif Soccer.Corner == "Right post" then zs = 1
	elseif Soccer.Corner == "Centre" then zs = 0
	else
		-- far from the keeper: find the opposing keeper and shoot to the other side of the goal
		local keeperZ
		for _, p in ipairs(Players:GetPlayers()) do
			local c = p.Character
			if c and p ~= lp and c:GetAttribute("Role") == "Goalkeeper" and c:GetAttribute("Team") ~= team then
				local r = c:FindFirstChild("Root")
				if r then keeperZ = r.Position.Z end
			end
		end
		if keeperZ then zs = keeperZ >= gz and -1 or 1 else zs = ballPos.Z >= gz and -1 or 1 end
	end
	return Vector3.new(goal.pos.X, ballPos.Y, gz + zs * off), goal
end

local function horiz(v) return Vector3.new(v.X, 0, v.Z) end

-- the last aim change, so the DribbleRelease that follows the KickPlan can be rotated by the same amount
local lastAim = { rot = nil, t = -99 }

local function note(msg) if Soccer.Notify then Soccer.Notify(msg, 2) end end

local function onKickPlan(args)
	local plan = args[1]
	if type(plan) ~= "table" or typeof(plan.dir) ~= "Vector3" or typeof(plan.ball) ~= "Vector3" then return nil end
	local target = targetFor(plan.ball)
	if not target then return nil end
	local toGoal = horiz(target - plan.ball)
	if toGoal.Magnitude < 1 or toGoal.Magnitude > Soccer.MaxDist then return nil end
	local oldDir = horiz(plan.dir)
	if oldDir.Magnitude < 0.01 then return nil end
	local newDir = toGoal.Unit
	oldDir = oldDir.Unit
	local cos = math.clamp(oldDir:Dot(newDir), -1, 1)
	if math.deg(math.acos(cos)) > Soccer.Cone then return nil end -- not a shot at goal: leave passes etc. alone
	local np = table.clone(plan)
	np.dir = newDir
	lastAim.rot = CFrame.lookAt(Vector3.zero, newDir) * CFrame.lookAt(Vector3.zero, oldDir):Inverse()
	lastAim.t = os.clock()
	Soccer.Shots = Soccer.Shots + 1
	note(("Aimed at the %s (%d studs)"):format(Soccer.Corner == "Far from keeper" and "far corner" or "goal", math.floor(toGoal.Magnitude)))
	local out = table.clone(args)
	out[1] = np
	return out
end

local function onRelease(args)
	-- DribbleRelease(pid, kind, ballPos, vel, t, nil, spin, family)
	if not lastAim.rot or os.clock() - lastAim.t > 1.5 then return nil end
	local vel = args[4]
	if typeof(vel) ~= "Vector3" then return nil end
	local out = table.clone(args)
	out[4] = lastAim.rot * vel
	if typeof(args[7]) == "Vector3" then out[7] = lastAim.rot * args[7] end
	lastAim.rot = nil
	return out
end

local function nc(self, ...)
	if Soccer.Aim and typeof(self) == "Instance" then
		local m = getnamecallmethod()
		if m == "FireServer" then
			local n = self.Name
			local handler = (n:find("KickPlan", 1, true) and not n:find("Relay", 1, true) and onKickPlan) or (n:find("DribbleRelease", 1, true) and onRelease) or nil
			if handler then
				local packed = table.pack(...)
				local ok, res = pcall(handler, packed)
				if ok and res then return oldNC(self, table.unpack(res, 1, packed.n)) end
			end
		end
	end
	return oldNC(self, ...)
end

local function installHook()
	if hooked then return end
	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then Soccer.Info = "no hookmetamethod: aim cannot work"; return end
	local ok, err = pcall(function() oldNC = hookmetamethod(game, "__namecall", newcclosure and newcclosure(nc) or nc) end)
	hooked = ok
	if not ok then Soccer.Info = "hook failed: " .. tostring(err) end
end

-- ACCURACY and STICKY BALL: the game's own rule tables, shared between its scripts and ours ----------------------------------------
local saved = {}
local function rulesTable(path)
	local ok, t = pcall(function()
		local m = RS
		for _, part in ipairs(path) do m = m:WaitForChild(part, 3) end
		return require(m)
	end)
	return ok and type(t) == "table" and t or nil
end

function Soccer.SetAccurate(on)
	Soccer.Accurate = on
	local R = rulesTable({ "Shared", "Game", "Kick", "Rules" })
	local miss = R and R.Miss
	if type(miss) ~= "table" then Soccer.Info = "kick rules not found"; return end
	pcall(function()
		if on then
			saved.miss = saved.miss or { Scale = miss.Scale, WeakFoot = miss.WeakFoot, Across = miss.Across }
			miss.Scale = 0; miss.WeakFoot = 1; miss.Across = 0
		elseif saved.miss then
			miss.Scale, miss.WeakFoot, miss.Across = saved.miss.Scale, saved.miss.WeakFoot, saved.miss.Across
		end
	end)
end

local PICK = { "FootReach", "BodyReach", "CushionReach", "MaxCarry", "KeepOut" }
function Soccer.SetSticky(on, mult)
	Soccer.Sticky = on
	if mult then Soccer.StickyMult = mult end
	local R = rulesTable({ "Shared", "Game", "Dribble", "Rules" })
	local pickup = R and R.Pickup
	if type(pickup) ~= "table" then Soccer.Info = "dribble rules not found"; return end
	pcall(function()
		saved.pick = saved.pick or {}
		for _, k in ipairs(PICK) do
			if type(pickup[k]) == "number" then
				if saved.pick[k] == nil then saved.pick[k] = pickup[k] end
				pickup[k] = on and saved.pick[k] * Soccer.StickyMult or saved.pick[k]
			end
		end
	end)
end

function Soccer.Start()
	if conn then return end
	installHook()
	conn = RunService.Heartbeat:Connect(function()
		local ok = pcall(speedStep)
		if not ok then Soccer.Info = "speed error" end
	end)
	Soccer.Info = hooked and "ready" or Soccer.Info
end

function Soccer.Destroy()
	Soccer.Aim = false
	if conn then conn:Disconnect(); conn = nil end
	Soccer.SetSpeed(false)
	if Soccer.Accurate then Soccer.SetAccurate(false) end
	if Soccer.Sticky then Soccer.SetSticky(false) end
end

return Soccer

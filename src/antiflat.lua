-- Anti Flat Tires (best effort). From tools/tire_probe.lua: flats are applied by the SERVER (car.flatTires + tire models
-- removed, -50 car health each). Police blockades are the source; the client reports hits on their parts with
--   FireServer(<vehicle model>, <part under Workspace.PoliceBlockades>)
-- Layers (each toggleable):
--   1) drop those hit reports before they reach the server
--   2) CanTouch = false on blockade parts, and no collision on spike-looking parts, so nothing triggers
-- UNTESTED: if the server detects spikes itself, this may not stop it. Needs hookmetamethod for layer 1.
local Anti = {
	Enabled = false, BlockReports = true, NoTouch = true, GhostSpikes = true,
	Blocked = 0, Parts = 0, Info = "off", Hooked = false,
}
local saved = {} -- [part] = { CanTouch, CanCollide }
local addConn

local function folder() return workspace:FindFirstChild("PoliceBlockades") end
local function notify() if Anti.Changed then task.defer(Anti.Changed) end end

local function spikey(name)
	name = name:lower()
	for _, k in ipairs({ "spike", "stinger", "strip", "nail", "tack", "tire" }) do
		if name:find(k, 1, true) then return true end
	end
	return false
end

local function neutralize(p)
	if not p:IsA("BasePart") then return end
	local isSpike = spikey(p.Name) or (p.Parent and spikey(p.Parent.Name))
	if not (Anti.NoTouch or (Anti.GhostSpikes and isSpike)) then return end
	if not saved[p] then saved[p] = { p.CanTouch, p.CanCollide }; Anti.Parts = Anti.Parts + 1 end
	if Anti.NoTouch or isSpike then p.CanTouch = false end
	if Anti.GhostSpikes and isSpike then p.CanCollide = false end
end

local function restore()
	for p, o in pairs(saved) do
		if p.Parent then pcall(function() p.CanTouch = o[1]; p.CanCollide = o[2] end) end
	end
	saved, Anti.Parts = {}, 0
end

function Anti.Refresh() -- re-apply after toggling an option
	restore()
	local f = folder()
	if Anti.Enabled and f then
		for _, d in ipairs(f:GetDescendants()) do neutralize(d) end
	end
	Anti.Info = Anti.Enabled and (f and ("on, " .. Anti.Parts .. " blockade parts neutralised") or "on (no blockades spawned yet)") or "off"
	notify()
end

local function install()
	if Anti.Hooked then return true end
	if not (hookmetamethod and getnamecallmethod) then return false end
	local ok = pcall(function()
		local old
		old = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
			if Anti.Enabled and Anti.BlockReports and getnamecallmethod() == "FireServer"
				and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
				local a, b = ...
				local f = folder()
				if f and typeof(a) == "Instance" and a:IsA("Model") and a:GetAttribute("currentHealth") ~= nil
					and typeof(b) == "Instance" and b:IsDescendantOf(f) then
					Anti.Blocked = Anti.Blocked + 1
					notify()
					return nil
				end
			end
			return old(self, ...)
		end))
	end)
	Anti.Hooked = ok
	return ok
end

function Anti.SetEnabled(v)
	Anti.Enabled = v
	if v then
		if Anti.BlockReports and not install() then Anti.BlockReports = false end
		local f = folder()
		if addConn then addConn:Disconnect(); addConn = nil end
		-- blockades spawn during police chases: neutralise new parts as they appear
		addConn = workspace.DescendantAdded:Connect(function(d)
			if Anti.Enabled and d:IsA("BasePart") and folder() and d:IsDescendantOf(folder()) then neutralize(d); notify() end
		end)
	else
		if addConn then addConn:Disconnect(); addConn = nil end
	end
	Anti.Refresh()
end

function Anti.Destroy()
	Anti.Enabled = false
	if addConn then addConn:Disconnect(); addConn = nil end
	restore()
	Anti.Changed = nil
end

return Anti

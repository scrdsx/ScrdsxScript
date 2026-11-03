-- Anti Crash Damage. The client reports crashes to the server with a RemoteEvent call shaped like
--   FireServer(<vehicle model>, <impact number>)        (seen in tools/player_probe.lua: (car, 4469.49))
-- while throttle/steering use the same (car, -1|0|1) shape. We drop the call when the number is above MinImpact.
-- UNTESTED: only works if the server takes damage from this report. Needs an executor with hookmetamethod.
local Anti = { Enabled = false, MinImpact = 5, Blocked = 0, Last = "-", Hooked = false, Info = "off" }

local function notify()
	if Anti.Changed then task.defer(Anti.Changed) end
end

local function install()
	if Anti.Hooked then return true end
	if not (hookmetamethod and getnamecallmethod) then Anti.Info = "needs hookmetamethod (executor)"; return false end
	local ok = pcall(function()
		local old
		old = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
			if Anti.Enabled and getnamecallmethod() == "FireServer" and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
				local a, b = ...
				if typeof(a) == "Instance" and a:IsA("Model") and a:GetAttribute("currentHealth") ~= nil
					and type(b) == "number" and math.abs(b) > Anti.MinImpact then
					Anti.Blocked = Anti.Blocked + 1
					Anti.Last = ("%.0f"):format(b)
					notify()
					return nil -- crash report never reaches the server
				end
			end
			return old(self, ...)
		end))
	end)
	Anti.Hooked = ok
	if not ok then Anti.Info = "hook failed" end
	return ok
end

function Anti.SetEnabled(v)
	if v and not install() then Anti.Enabled = false; notify(); return false end
	Anti.Enabled = v
	Anti.Info = v and "on" or "off"
	notify()
	return true
end

function Anti.Destroy()
	Anti.Enabled = false
	Anti.Changed = nil
end

return Anti

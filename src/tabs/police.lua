-- Police tab: Radar Farm (auto radar control on every speeding driver near you).
local Radar = __import("police/radar")

return function(ctx)
	local win, safe = ctx.win, ctx.safe
	local tPol = win:Tab("Police", { Section = "Game", Icon = 15 })

	local mRadar = tPol:Module({ Name = "Radar Farm", Default = false, Callback = function(on)
		Radar.SetEnabled(on)
		if on then win:Notify("Radar Farm on: be Police with the radar gun, stand by a road", 4, "success") end
	end })
	local lRadar = mRadar:Label({ Name = "Status", Value = Radar.Info })
	mRadar:Label({ Name = "How it works", Value = "fines every driver over the limit near you, no aiming needed" })
	mRadar:Slider({ Name = "Range", Min = 50, Max = 490, Step = 10, Default = Radar.Range, Suffix = " st", Callback = function(v) Radar.Range = v end })
	mRadar:Slider({ Name = "Only fine when over the limit by", Min = 0, Max = 30, Step = 1, Default = Radar.Over, Suffix = " km/h", Callback = function(v) Radar.Over = v end })
	mRadar:Slider({ Name = "Cars at once (per sweep)", Min = 1, Max = 10, Step = 1, Default = Radar.PerSweep, Callback = function(v) Radar.PerSweep = v end })
	mRadar:Slider({ Name = "Time between sweeps", Min = 0.1, Max = 3, Step = 0.05, Default = Radar.Interval, Suffix = " s", Callback = function(v) Radar.Interval = v end })
	mRadar:Slider({ Name = "Wait before fining the same driver again", Min = 2, Max = 120, Step = 1, Default = Radar.Wait, Suffix = " s", Callback = function(v) Radar.Wait = v end })
	mRadar:Toggle({ Name = "Equip the radar gun automatically", Default = Radar.AutoEquip, Callback = function(v) Radar.AutoEquip = v end })
	mRadar:Toggle({ Name = "Skip police and fire department", Default = Radar.SkipPolice, Callback = function(v) Radar.SkipPolice = v end })
	mRadar:Toggle({ Name = "Highlight speeding cars", Default = Radar.Mark, Callback = function(v) Radar.Mark = v end })
	mRadar:Toggle({ Name = "Notify on every fine", Default = false, Callback = function(v)
		Radar.OnFine = v and function(who, over) win:Notify(("Fined %s  (+%s too fast)"):format(tostring(who or "?"), tostring(over or "?")), 2.5, "success") end or nil
	end })
	mRadar:Button({ Name = "Reset fine counter", NoSave = true, Callback = function() Radar.Fines = 0; Radar.Total = 0 end })
	safe("radar", Radar.Start)

	task.spawn(function()
		while ctx.alive() do
			task.wait(0.4)
			pcall(function() lRadar:Set(Radar.Info) end)
		end
	end)
end

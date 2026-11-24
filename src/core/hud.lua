-- HUD style (v6 "Mocha"): one look for every on-screen tag and pill outside the menu (route pill, robbery tags, loot tags,
-- ESP radar / hover card). Flat espresso, a faint cream hairline, cream text. No gradients (cheaper to draw, cleaner to read).
local Theme = __import("ui/theme")

local Hud = {
	BG = Color3.fromRGB(20, 17, 15),
	BG_T = 0.1,
	TEXT = Color3.fromRGB(245, 239, 229),
	SUB = Color3.fromRGB(165, 155, 143),
	OFF = Color3.fromRGB(62, 56, 50),
	EDGE = Color3.fromRGB(236, 211, 172),
	FONT = Enum.Font.BuilderSansMedium,
	BOLD = Enum.Font.BuilderSansBold,
}

function Hud.Accent() return Theme.T.accent end

-- makes a frame a HUD card: corner (pill when no radius), a faint cream hairline. Returns the UIStroke (tint it for state).
-- noGradient is kept for old callers; there is no gradient any more.
function Hud.Glass(f, radius, _noGradient)
	f.BackgroundColor3 = Hud.BG
	f.BackgroundTransparency = Hud.BG_T
	f.BorderSizePixel = 0
	local c = Instance.new("UICorner"); c.CornerRadius = radius and UDim.new(0, radius) or UDim.new(1, 0); c.Parent = f
	local st = Instance.new("UIStroke"); st.Color = Hud.EDGE; st.Transparency = 0.84; st.Thickness = 1; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = f
	return st
end

return Hud

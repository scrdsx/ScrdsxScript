-- HUD style (v5 "Frost"): one look for every on-screen tag and pill outside the menu (route pill, robbery tags, loot tags,
-- ESP radar / hover card). Graphite glass, a hairline light edge, a faint top-lit gradient, the menu's accent.
local Theme = __import("ui/theme")

local Hud = {
	BG = Color3.fromRGB(12, 13, 16),
	BG_T = 0.12,
	TEXT = Color3.fromRGB(241, 243, 247),
	SUB = Color3.fromRGB(150, 156, 170),
	OFF = Color3.fromRGB(52, 56, 66),
	FONT = Enum.Font.BuilderSansMedium,
	BOLD = Enum.Font.BuilderSansBold,
}

function Hud.Accent() return Theme.T.accent end

-- makes a frame a glass card: corner, light hairline edge, top-lit gradient. Returns the UIStroke (tint it for state).
function Hud.Glass(f, radius, noGradient)
	f.BackgroundColor3 = Hud.BG
	f.BackgroundTransparency = Hud.BG_T
	f.BorderSizePixel = 0
	local c = Instance.new("UICorner"); c.CornerRadius = radius and UDim.new(0, radius) or UDim.new(1, 0); c.Parent = f
	local st = Instance.new("UIStroke"); st.Color = Color3.new(1, 1, 1); st.Transparency = 0.9; st.Thickness = 1; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = f
	if not noGradient then
		local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 198, 204)); g.Parent = f
	end
	return st
end

return Hud

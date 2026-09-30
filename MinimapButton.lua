local addonName, ns = ...
local L = ns.L

-- The addon's icon on the minimap's edge: left-click opens the main window, right-click the
-- messages. It shows the number of unread messages and glows while an important one is unread.
local MinimapButton = {}
ns.MinimapButton = MinimapButton

local SIZE = 31
local DEFAULT_ANGLE = 200 -- degrees, counter-clockwise from the right: left, a bit below the middle
local EDGE_PADDING = 5    -- the icon's centre sits this far outside the minimap's edge
local MAX_BADGE = 99

local ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
local BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background"
local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TOOLTIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local GOLD = { 1, 0.82, 0 }
local FRAME_BORDER = { 0.85, 0.68, 0.2, 1 }
local BADGE_BACKGROUND = { 0.6, 0.08, 0.08, 1 }

local atan2 = math.atan2 or math.atan
local button

-- Not every texture of the retail client is guaranteed to ship with WoW Forever.
local function FileExists(path)
	return GetFileIDFromPath == nil or GetFileIDFromPath(path) ~= nil
end

-- Cuts a texture to a circle so it fits the round button.
local function MakeRound(b, texture)
	if FileExists(CIRCLE_MASK) then
		local mask = b:CreateMaskTexture()
		mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(texture)
		texture:AddMaskTexture(mask)
	end
end

local function Angle()
	return tonumber(ns.db.minimap.angle) or DEFAULT_ANGLE
end

-- Places the icon on the minimap's edge at the saved angle.
local function UpdatePosition(b)
	local radians = math.rad(Angle())
	local radiusX = Minimap:GetWidth() / 2 + EDGE_PADDING
	local radiusY = Minimap:GetHeight() / 2 + EDGE_PADDING
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radiusX, math.sin(radians) * radiusY)
end

-- While dragging: the icon follows the mouse around the minimap's centre.
local function FollowMouse(self)
	local centerX, centerY = Minimap:GetCenter()
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.db.minimap.angle = math.deg(atan2(cursorY / scale - centerY, cursorX / scale - centerX)) % 360
	UpdatePosition(self)
end

local function Create()
	local b = CreateFrame("Button", addonName .. "MinimapButton", Minimap, "BackdropTemplate")
	b:SetSize(SIZE, SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")

	-- The usual round minimap button; a gold frame if the minimap art is missing.
	if FileExists(BACKGROUND) then
		local background = b:CreateTexture(nil, "BACKGROUND")
		background:SetSize(24, 24)
		background:SetPoint("CENTER", 0, 0)
		background:SetTexture(BACKGROUND)
	end
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(18, 18)
	b.icon:SetPoint("CENTER", 0, 0)
	b.icon:SetTexture(ICON)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	MakeRound(b, b.icon)
	if FileExists(BORDER) then
		local border = b:CreateTexture(nil, "OVERLAY")
		border:SetSize(50, 50)
		border:SetPoint("TOPLEFT", 0, 0)
		border:SetTexture(BORDER)
	else
		b:SetBackdrop({ edgeFile = TOOLTIP_BORDER, edgeSize = 12 })
		b:SetBackdropBorderColor(FRAME_BORDER[1], FRAME_BORDER[2], FRAME_BORDER[3], FRAME_BORDER[4])
	end
	if FileExists(HIGHLIGHT) then
		b:SetHighlightTexture(HIGHLIGHT, "ADD")
	end

	b.glow = b:CreateTexture(nil, "OVERLAY", nil, 1)
	b.glow:SetTexture(WHITE)
	b.glow:SetPoint("TOPLEFT", 4, -4)
	b.glow:SetPoint("BOTTOMRIGHT", -4, 4)
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
	MakeRound(b, b.glow)
	b.glow:Hide()
	b.pulse = b.glow:CreateAnimationGroup()
	b.pulse:SetLooping("BOUNCE")
	local fade = b.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.15)
	fade:SetToAlpha(0.8)
	fade:SetDuration(0.9)

	b.badge = CreateFrame("Frame", nil, b, "BackdropTemplate")
	b.badge:SetSize(22, 16)
	b.badge:SetPoint("TOPRIGHT", 8, 4)
	b.badge:SetBackdrop({ bgFile = WHITE, edgeFile = TOOLTIP_BORDER, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
	b.badge:SetBackdropColor(BADGE_BACKGROUND[1], BADGE_BACKGROUND[2], BADGE_BACKGROUND[3], BADGE_BACKGROUND[4])
	b.badge:SetBackdropBorderColor(FRAME_BORDER[1], FRAME_BORDER[2], FRAME_BORDER[3], FRAME_BORDER[4])
	b.count = b.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.count:SetPoint("CENTER", 0, 0)

	b:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			ns.MessageWindow.Toggle()
		else
			ns.UI.Toggle()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		self:SetScript("OnUpdate", FollowMouse)
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(ns.title, 1, 1, 1)
		GameTooltip:AddLine(L.MSG_UNREAD:format(ns.Messages.CountUnread()), GOLD[1], GOLD[2], GOLD[3])
		GameTooltip:AddLine(L.MINIMAP_TIP, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	if ns.db then
		UpdatePosition(b)
	end
	return b
end

-- The hint of the message window anchors here, also while the icon is switched off.
function MinimapButton.GetFrame()
	button = button or Create()
	return button
end

function MinimapButton.Update()
	if not (ns.db and ns.char) then
		return
	end
	local b = MinimapButton.GetFrame()
	UpdatePosition(b)
	b:SetShown(ns.db.minimap.show and true or false)
	local unread = ns.Messages.CountUnread()
	b.badge:SetShown(unread > 0)
	b.count:SetText(unread > MAX_BADGE and (MAX_BADGE .. "+") or tostring(unread))
	local important = ns.Messages.HasImportantUnread()
	b.glow:SetShown(important)
	if important then
		if not b.pulse:IsPlaying() then
			b.pulse:Play()
		end
	else
		b.pulse:Stop()
	end
end

-- Registered after MessageWindow.lua's handler, which marks new messages read while the window is open.
ns.RegisterCallback("MESSAGES_UPDATED", MinimapButton.Update)
ns.RegisterCallback("LOGIN", MinimapButton.Update)
ns.RegisterCallback("SETTINGS_CHANGED", MinimapButton.Update)

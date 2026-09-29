local addonName, ns = ...
local L = ns.L

local GuildMap = {}
ns.GuildMap = GuildMap

local SEND_CHECK_SECONDS = 5
local HEARTBEAT_SECONDS = 30
local EXPIRE_SECONDS = 90
local MOVE_THRESHOLD = 0.003 -- in map coordinates
local REFRESH_DELAY = 0.5
local TEST_OFFSET = 0.03

local PIN_TEMPLATE = addonName .. "MapPinTemplate"
local PIN_SIZE = 16
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CLASS_ICONS = "Interface\\WorldStateFrame\\Icons-Classes"

local positions = {} -- sender -> { mapID, x, y, level, class, time, continent, world }
local lastSent       -- { mapID, x, y, time } of our last shared position
local provider
local refreshPending = false

local function FileExists(path)
	return GetFileIDFromPath == nil or GetFileIDFromPath(path) ~= nil
end

-- mapID, x, y of the player, or nil (instances have no position).
local function GetOwnPosition()
	local mapID = C_Map.GetBestMapForUnit("player")
	if ns.IsSecret(mapID) or not mapID then
		return nil
	end
	local position = C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return nil
	end
	local x, y = position:GetXY()
	if ns.IsSecret(x) or ns.IsSecret(y) or not x or not y or (x == 0 and y == 0) then
		return nil
	end
	return mapID, x, y
end

---------------------------------------------------------------------------
-- Sending: "POS <mapID> <x*10000> <y*10000> <level> <class>", "POSHIDE" when leaving the map
---------------------------------------------------------------------------

local function Hide()
	if lastSent then
		ns.Comm.Send("POSHIDE", "GUILD")
		lastSent = nil
	end
end

-- The guild map is always on for guild members running the addon.
local function SendPosition()
	if not ns.IsActive() then
		Hide()
		return
	end
	local mapID, x, y = GetOwnPosition()
	if not mapID then
		Hide()
		return
	end
	local now = GetTime()
	local moved = not lastSent or lastSent.mapID ~= mapID
		or math.abs(lastSent.x - x) >= MOVE_THRESHOLD or math.abs(lastSent.y - y) >= MOVE_THRESHOLD
	if not moved and now - lastSent.time < HEARTBEAT_SECONDS then
		return
	end
	local message = ("POS\t%d\t%d\t%d\t%d\t%s"):format(mapID, math.floor(x * 10000), math.floor(y * 10000),
		UnitLevel("player"), UnitClassBase("player") or "")
	if ns.Comm.Send(message, "GUILD") then
		lastSent = { mapID = mapID, x = x, y = y, time = now }
	end
end

---------------------------------------------------------------------------
-- Positions of other members
---------------------------------------------------------------------------

local function RemoveExpired()
	local now = GetTime()
	for name, entry in pairs(positions) do
		if now - entry.time > EXPIRE_SECONDS then
			positions[name] = nil
		end
	end
end

-- Position of a member on the given map, or nil if they are not on it. Positions on another map
-- of the same continent (zone -> continent map, neighbouring zones) are converted via world coordinates.
local function PositionOnMap(entry, mapID)
	if entry.mapID == mapID then
		return entry.x, entry.y
	end
	if not entry.world then
		local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, entry.mapID, CreateVector2D(entry.x, entry.y))
		if not ok or not continent or not world then
			return nil
		end
		entry.continent, entry.world = continent, world
	end
	local ok, mapContinent = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0.5, 0.5))
	if not ok or mapContinent ~= entry.continent then
		return nil
	end
	local converted, _, mapPosition = pcall(C_Map.GetMapPosFromWorldPos, entry.continent, entry.world, mapID)
	if not converted or not mapPosition then
		return nil
	end
	local x, y = mapPosition:GetXY()
	if x < 0 or x > 1 or y < 0 or y > 1 then
		return nil
	end
	return x, y
end

local function Refresh()
	refreshPending = false
	RemoveExpired()
	if provider and WorldMapFrame and WorldMapFrame:IsShown() then
		provider:RefreshAllData()
	end
end

local function ScheduleRefresh()
	if refreshPending then
		return
	end
	refreshPending = true
	C_Timer.After(REFRESH_DELAY, Refresh)
end

ns.Comm.RegisterHandler("POS", function(sender, channel, payload)
	if channel ~= "GUILD" or not payload then
		return
	end
	local mapID, x, y, level, class = strsplit("\t", payload, 5)
	mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
	if not (mapID and x and y) then
		return
	end
	positions[sender] = {
		mapID = mapID,
		x = x / 10000,
		y = y / 10000,
		level = tonumber(level) or 0,
		class = (class and class ~= "") and class or nil,
		time = GetTime(),
	}
	ScheduleRefresh()
end)

ns.Comm.RegisterHandler("POSHIDE", function(sender)
	if positions[sender] then
		positions[sender] = nil
		ScheduleRefresh()
	end
end)

-- A pin next to the player for 90 seconds, to check the looks without a second player.
function GuildMap.ShowTestPin()
	local mapID, x, y = GetOwnPosition()
	if not mapID then
		ns.Print("system", L.MAP_TEST_NO_POSITION)
		return
	end
	positions[L.MAP_TEST_NAME] = {
		mapID = mapID,
		x = math.min(x + TEST_OFFSET, 1),
		y = y,
		level = UnitLevel("player"),
		class = UnitClassBase("player"),
		time = GetTime(),
	}
	ns.Print("system", L.MAP_TEST_ADDED)
	Refresh()
end

---------------------------------------------------------------------------
-- World map: data provider and pins (template in MapPin.xml)
---------------------------------------------------------------------------

local function CreatePinMixin()
	local Pin = CreateFromMixins(MapCanvasPinMixin)
	local hasCircleMask = FileExists(CIRCLE_MASK)
	local hasClassIcons = FileExists(CLASS_ICONS) and CLASS_ICON_TCOORDS ~= nil

	local function AddCircleMask(pin, texture)
		if hasCircleMask then
			local mask = pin:CreateMaskTexture()
			mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(texture)
			texture:AddMaskTexture(mask)
		end
	end

	function Pin:OnLoad()
		self:SetSize(PIN_SIZE, PIN_SIZE)
		pcall(self.SetScalingLimits, self, 1, 1, 1.3)
		pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_GROUP_MEMBER")
		-- Tooltip on hover, but clicks go through to the map.
		if self.SetMouseMotionEnabled then
			self:SetMouseMotionEnabled(true)
			self:SetMouseClickEnabled(false)
		else
			self:EnableMouse(true)
		end
		self.ring = self:CreateTexture(nil, "BACKGROUND")
		self.ring:SetTexture(WHITE)
		self.ring:SetPoint("CENTER")
		self.ring:SetSize(PIN_SIZE + 4, PIN_SIZE + 4)
		AddCircleMask(self, self.ring)
		self.icon = self:CreateTexture(nil, "ARTWORK")
		self.icon:SetAllPoints()
		AddCircleMask(self, self.icon)
	end

	function Pin:OnAcquired(name, entry, x, y)
		self.name, self.entry = name, entry
		self:SetPosition(x, y)
		local color = entry.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class]
		local r, g, b = 0.3, 0.75, 1
		if color then
			r, g, b = color.r, color.g, color.b
		end
		self.ring:SetVertexColor(r, g, b)
		local coords = hasClassIcons and entry.class and CLASS_ICON_TCOORDS[entry.class]
		if coords then
			self.icon:SetTexture(CLASS_ICONS)
			self.icon:SetTexCoord(unpack(coords))
			self.icon:SetVertexColor(1, 1, 1)
		else
			self.icon:SetTexture(WHITE)
			self.icon:SetTexCoord(0, 1, 0, 1)
			self.icon:SetVertexColor(r, g, b)
		end
	end

	function Pin:OnMouseEnter()
		local entry = self.entry
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(ns.Announce.ClassColored(Ambiguate(self.name, "guild"), entry.class))
		local className = entry.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[entry.class] or ""
		GameTooltip:AddLine(L.MAP_TOOLTIP_LEVEL:format(entry.level, className), 1, 1, 1)
		local info = C_Map.GetMapInfo(entry.mapID)
		if info and info.name then
			GameTooltip:AddLine(info.name, 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine(L.MAP_AGE:format(math.floor(GetTime() - entry.time)), 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end

	function Pin:OnMouseLeave()
		GameTooltip:Hide()
	end

	return Pin
end

local function CreateProvider()
	if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin) then
		return
	end
	-- The XML template refers to this global mixin by name.
	_G[addonName .. "MapPinMixin"] = CreatePinMixin()

	provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
	end
	function provider:RefreshAllData()
		self:RemoveAllData()
		if not ns.IsActive() then
			return
		end
		local map = self:GetMap()
		local mapID = map:GetMapID()
		if not mapID then
			return
		end
		RemoveExpired()
		for name, entry in pairs(positions) do
			local x, y = PositionOnMap(entry, mapID)
			if x then
				map:AcquirePin(PIN_TEMPLATE, name, entry, x, y)
			end
		end
	end
	WorldMapFrame:AddDataProvider(provider)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns.RegisterCallback("LOGIN", function()
	CreateProvider()
	C_Timer.NewTicker(SEND_CHECK_SECONDS, function()
		SendPosition()
		RemoveExpired()
	end)
end)

-- In case the world map is loaded on demand.
ns.On("ADDON_LOADED", function(_, name)
	if name == "Blizzard_WorldMap" then
		CreateProvider()
	end
end)

-- Joining or leaving a guild starts or stops the map.
ns.RegisterCallback("ROSTER_UPDATED", function()
	SendPosition()
	ScheduleRefresh()
end)

ns.On("PLAYER_ENTERING_WORLD", SendPosition)
ns.On("ZONE_CHANGED_NEW_AREA", SendPosition)

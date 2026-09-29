local _, ns = ...
local L = ns.L

local function CloseAuctionHouseWindow()
	if C_AuctionHouse and C_AuctionHouse.CloseAuctionHouse then
		C_AuctionHouse.CloseAuctionHouse()
	elseif CloseAuctionHouse then
		CloseAuctionHouse()
	end
	local frame = AuctionHouseFrame or AuctionFrame
	if frame and frame:IsShown() then
		HideUIPanel(frame)
	end
end

ns.On("AUCTION_HOUSE_SHOW", function()
	if not ns.IsActive() or not ns.Rules.Get("blockAuctionHouse") then
		return
	end
	CloseAuctionHouseWindow()
	-- The auction house UI may open after our handler ran; close it again on the next frame.
	C_Timer.After(0, CloseAuctionHouseWindow)
	ns.Warn("blocked", L.AH_BLOCKED)
	ns.Log("ah", L.LOG_AH)
end)

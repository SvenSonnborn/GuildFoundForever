local _, ns = ...
local L = ns.L

local ENCHANT_SLOT = TRADE_ENCHANT_SLOT or 7 -- "Will not be traded" slot, used for enchanting and lockpicking
local CONSUMABLE = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
local QUEST_ITEM = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12
local FOOD_AND_DRINK = Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Fooddrink or 5

local SIDES = {
	{ isPlayer = true, getLink = GetTradePlayerItemLink, tooltip = "GetTradePlayerItem" },
	{ isPlayer = false, getLink = GetTradeTargetItemLink, tooltip = "GetTradeTargetItem" },
}

local trade = {
	open = false,
	partner = nil,
	external = false,
	blocked = false,
	problems = {},
	reportedProblems = "",
}

local tradeButton
local buttonWanted = true -- enabled state Blizzard asked for while we keep the button disabled
local ownButtonCall = false
local notice

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------

local function AllowedText()
	local parts = {}
	if ns.Rules.Get("tradeConjured") then
		parts[#parts + 1] = L.TRADE_ALLOWED_CONJURED
	end
	if ns.Rules.Get("tradeHealthstones") then
		parts[#parts + 1] = L.TRADE_ALLOWED_HEALTHSTONES
	end
	if ns.Rules.Get("tradeQuestItems") then
		parts[#parts + 1] = L.TRADE_ALLOWED_QUESTITEMS
	end
	if ns.Rules.Get("tradeGold") then
		parts[#parts + 1] = L.TRADE_ALLOWED_GOLD
	end
	if ns.Rules.Get("servicesOutgoing") then
		parts[#parts + 1] = L.TRADE_ALLOWED_SERVICES
	end
	if ns.Rules.Get("lockpickIncoming") then
		parts[#parts + 1] = L.TRADE_ALLOWED_LOCKPICK
	end
	return #parts > 0 and table.concat(parts, ", ") or L.TRADE_ALLOWED_NOTHING
end

local function GetTooltipData(side, slot)
	local getter = C_TooltipInfo and C_TooltipInfo[side.tooltip]
	return getter and getter(slot)
end

local function TooltipHasLine(tooltipData, text)
	if not (text and tooltipData and tooltipData.lines) then
		return false
	end
	for _, line in ipairs(tooltipData.lines) do
		local left = line.leftText
		if not ns.IsSecret(left) and left == text then
			return true
		end
	end
	return false
end

-- Slot 7 holds an item that gets enchanted or unlocked but stays with its owner.
local function CheckServiceSlot(side, link, problems)
	if not side.isPlayer then
		-- Their item: we enchant it or pick its lock for them.
		if not ns.Rules.Get("servicesOutgoing") then
			problems[#problems + 1] = L.TRADE_PROBLEM_SERVICE_OUT:format(link)
		end
	elseif TooltipHasLine(GetTooltipData(side, ENCHANT_SLOT), LOCKED) then
		if not ns.Rules.Get("lockpickIncoming") then
			problems[#problems + 1] = L.TRADE_PROBLEM_LOCKPICK_IN:format(link)
		end
	else
		problems[#problems + 1] = L.TRADE_PROBLEM_ENCHANT_IN:format(link)
	end
end

local function IsAllowedItem(side, slot, itemID)
	if ns.Rules.Get("tradeHealthstones") and ns.Data.healthstones[itemID] then
		return true
	end
	local isKnownConjured = ns.Data.conjuredFood[itemID] or ns.Data.conjuredWater[itemID]
	if ns.Rules.Get("tradeConjured") and isKnownConjured then
		return true
	end
	if not (C_Item and C_Item.GetItemInfoInstant) then
		return false
	end
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if ns.Rules.Get("tradeQuestItems") and classID == QUEST_ITEM then
		return true
	end
	-- Item IDs we do not know (e.g. new ranks): accept food and drink that the tooltip marks as conjured.
	return ns.Rules.Get("tradeConjured") and classID == CONSUMABLE and subClassID == FOOD_AND_DRINK
		and TooltipHasLine(GetTooltipData(side, slot), ITEM_CONJURED)
end

local function CheckSlot(side, slot, problems)
	local link = side.getLink(slot)
	if not link then
		return
	end
	if slot == ENCHANT_SLOT then
		CheckServiceSlot(side, link, problems)
		return
	end
	local itemID = tonumber(link:match("item:(%d+)"))
	if not (itemID and IsAllowedItem(side, slot, itemID)) then
		problems[#problems + 1] = L.TRADE_PROBLEM_ITEM:format(link, itemID or 0)
	end
end

local function CollectProblems()
	local problems = trade.problems
	wipe(problems)
	if not trade.open or not trade.external or not ns.IsActive() then
		return
	end
	for _, side in ipairs(SIDES) do
		for slot = 1, ENCHANT_SLOT do
			CheckSlot(side, slot, problems)
		end
	end
	if not ns.Rules.Get("tradeGold") then
		if (GetPlayerTradeMoney() or 0) > 0 then
			problems[#problems + 1] = L.TRADE_PROBLEM_GOLD_GIVE
		end
		if (GetTargetTradeMoney() or 0) > 0 then
			problems[#problems + 1] = L.TRADE_PROBLEM_GOLD_GET
		end
	end
end

---------------------------------------------------------------------------
-- Trade window: disabled trade button and a notice below the window
---------------------------------------------------------------------------

local function SetTradeButtonEnabled(enabled)
	ownButtonCall = true
	if enabled then
		tradeButton:Enable()
	else
		tradeButton:Disable()
	end
	ownButtonCall = false
end

-- Blizzard enables the trade button on its own; keep it disabled while the trade is blocked.
local function HookTradeButton()
	if tradeButton or not TradeFrameTradeButton then
		return
	end
	tradeButton = TradeFrameTradeButton
	hooksecurefunc(tradeButton, "Enable", function()
		if ownButtonCall then
			return
		end
		buttonWanted = true
		if trade.blocked then
			SetTradeButtonEnabled(false)
		end
	end)
	hooksecurefunc(tradeButton, "Disable", function()
		if not ownButtonCall then
			buttonWanted = false
		end
	end)
	hooksecurefunc(tradeButton, "SetEnabled", function(_, enabled)
		if ownButtonCall then
			return
		end
		buttonWanted = enabled and true or false
		if enabled and trade.blocked then
			SetTradeButtonEnabled(false)
		end
	end)
end

local function CreateNotice()
	if notice or not TradeFrame then
		return
	end
	local holder = CreateFrame("Frame", nil, TradeFrame)
	holder:SetPoint("TOPLEFT", TradeFrame, "BOTTOMLEFT", 0, -2)
	holder:SetPoint("TOPRIGHT", TradeFrame, "BOTTOMRIGHT", 0, -2)
	holder:Hide()
	local background = holder:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.8)
	notice = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	notice:SetPoint("TOPLEFT", 8, -6)
	notice:SetPoint("TOPRIGHT", -8, -6)
	notice:SetJustifyH("LEFT")
	notice.holder = holder
end

local function UpdateNotice()
	if not notice then
		return
	end
	if not trade.open or not trade.external or not ns.IsActive() then
		notice.holder:Hide()
		return
	end
	if #trade.problems > 0 then
		notice:SetText("|cffff5555" .. L.TRADE_NOTICE_BLOCKED .. "|r\n" .. table.concat(trade.problems, "\n"))
	else
		notice:SetText(L.TRADE_NOTICE_OK:format(AllowedText()))
	end
	notice.holder:SetHeight(notice:GetStringHeight() + 12)
	notice.holder:Show()
end

local function Update()
	if not trade.open then
		return
	end
	CollectProblems()
	local blocked = #trade.problems > 0
	if blocked ~= trade.blocked then
		trade.blocked = blocked
		if tradeButton then
			if blocked then
				SetTradeButtonEnabled(false)
			elseif buttonWanted then
				SetTradeButtonEnabled(true)
			end
		end
	end
	local problemText = table.concat(trade.problems, "; ")
	if problemText ~= trade.reportedProblems then
		trade.reportedProblems = problemText
		if blocked then
			ns.Warn("blocked", L.TRADE_BLOCKED, trade.problems[1])
			ns.Log("trade", L.LOG_TRADE:format(trade.partner, problemText))
		end
	end
	UpdateNotice()
end

local updatePending = false

-- Item links are not always available in the event itself; evaluate once on the next frame.
local function ScheduleUpdate()
	if updatePending then
		return
	end
	updatePending = true
	C_Timer.After(0, function()
		updatePending = false
		Update()
	end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns.On("TRADE_SHOW", function()
	HookTradeButton()
	CreateNotice()
	local isAllowed, displayName = ns.Guild.IsAllowedUnit("NPC")
	trade.open = true
	trade.partner = displayName or (TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText()) or "?"
	-- If the partner cannot be identified, treat them as non-guild.
	trade.external = ns.IsActive() and not isAllowed
	trade.blocked = false
	trade.reportedProblems = ""
	if tradeButton then
		buttonWanted = tradeButton:IsEnabled() and true or false
	end
	if trade.external then
		ns.Print("blocked", L.TRADE_EXTERNAL, trade.partner, AllowedText())
	end
	Update()
end)

ns.On("TRADE_CLOSED", function()
	if not trade.open then
		return
	end
	trade.open = false
	if trade.blocked and tradeButton and buttonWanted then
		SetTradeButtonEnabled(true)
	end
	trade.blocked = false
	wipe(trade.problems)
	UpdateNotice()
end)

for _, event in ipairs({ "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED", "PLAYER_TRADE_MONEY", "TRADE_UPDATE" }) do
	ns.On(event, ScheduleUpdate)
end

-- Last line of defence: if the trade was accepted anyway while blocked, cancel it.
ns.On("TRADE_ACCEPT_UPDATE", function(_, playerAccepted)
	Update()
	if trade.blocked and (playerAccepted == 1 or playerAccepted == true) then
		CancelTrade()
		ns.Warn("blocked", L.TRADE_CANCELLED)
	end
end)

ns.RegisterCallback("RULES_CHANGED", Update)

local _, ns = ...
local L = ns.L

local function RuleActive()
	return ns.IsActive() and ns.Rules.Get("blockMail")
end

-- Returns true if the items and gold of inbox mail #index may be taken, otherwise false and the sender.
-- Mail that cannot be replied to (NPCs, auction house), GM mail and mail returned to us is always fine.
local function IsInboxMailAllowed(index)
	local _, _, sender, _, _, _, _, _, _, wasReturned, _, canReply, isGM = GetInboxHeaderInfo(index)
	if not sender or isGM or wasReturned or not canReply then
		return true
	end
	return ns.Guild.IsAllowedName(sender), sender
end

local function ReportBlockedMail(sender)
	ns.Warn("blocked", L.MAIL_TAKE_BLOCKED, sender)
	ns.Log("mail", L.LOG_MAIL_TAKE:format(sender))
end

---------------------------------------------------------------------------
-- Inbox: taking items or gold from non-guild mail
---------------------------------------------------------------------------

for _, functionName in ipairs({ "TakeInboxItem", "TakeInboxMoney", "AutoLootMailItem" }) do
	local original = _G[functionName]
	if type(original) == "function" then
		_G[functionName] = function(index, ...)
			if RuleActive() then
				local allowed, sender = IsInboxMailAllowed(index)
				if not allowed then
					ReportBlockedMail(sender)
					return
				end
			end
			ns.Fire("INBOX_TAKE", functionName, index, ...)
			return original(index, ...)
		end
	end
end

-- "Open All" retries the current mail until it is empty, so skip blocked mail instead of looping on it.
local function PatchOpenAllButton()
	local button = OpenAllMail
	if not (button and button.ProcessNextItem and button.AdvanceAndProcessNextItem and button.StopOpening) then
		return
	end
	local original = button.ProcessNextItem
	button.ProcessNextItem = function(self, ...)
		if RuleActive() and self.mailIndex then
			local allowed, sender = IsInboxMailAllowed(self.mailIndex)
			if not allowed then
				ReportBlockedMail(sender)
				self.mailIndex = self.mailIndex + 1
				self.attachmentIndex = ATTACHMENTS_MAX_RECEIVE or 16
				if self.mailIndex > GetInboxNumItems() then
					self:StopOpening()
					return
				end
				return self:AdvanceAndProcessNextItem()
			end
		end
		return original(self, ...)
	end
end

---------------------------------------------------------------------------
-- Sending mail to non-guild players
---------------------------------------------------------------------------

local originalSendMail = SendMail
if type(originalSendMail) == "function" then
	SendMail = function(recipient, ...)
		if RuleActive() and not ns.Guild.IsAllowedName(recipient) then
			local name = type(recipient) == "string" and recipient or "?"
			ns.Warn("blocked", L.MAIL_SEND_BLOCKED, name)
			ns.Log("mail", L.LOG_MAIL_SEND:format(name))
			-- Let the send frame refresh its button for a corrected recipient.
			if SendMailFrame_Update then
				C_Timer.After(0, SendMailFrame_Update)
			end
			return
		end
		ns.Fire("MAIL_SENDING", recipient)
		return originalSendMail(recipient, ...)
	end
end

-- Small hint above the recipient box: guild member or not.
local recipientHint

local function UpdateRecipientHint()
	if not recipientHint then
		return
	end
	local name = SendMailNameEditBox:GetText()
	if not RuleActive() or not name or name == "" then
		recipientHint:SetText("")
	elseif ns.Guild.IsMemberName(name) then
		recipientHint:SetText("|cff55ff55" .. L.MAIL_HINT_GUILD .. "|r")
	elseif ns.Guild.IsPartnerName(name) then
		recipientHint:SetText("|cff55ff55" .. L.MAIL_HINT_PARTNER .. "|r")
	else
		recipientHint:SetText("|cffff5555" .. L.MAIL_HINT_EXTERNAL .. "|r")
	end
end

local function CreateRecipientHint()
	if recipientHint or not (SendMailFrame and SendMailNameEditBox) then
		return
	end
	recipientHint = SendMailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	recipientHint:SetPoint("BOTTOMRIGHT", SendMailNameEditBox, "TOPRIGHT", 0, 1)
	SendMailNameEditBox:HookScript("OnTextChanged", UpdateRecipientHint)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ns.RegisterCallback("LOGIN", function()
	PatchOpenAllButton()
	CreateRecipientHint()
end)

ns.On("MAIL_SHOW", function()
	ns.Guild.RequestRoster()
	UpdateRecipientHint()
end)

ns.RegisterCallback("ROSTER_UPDATED", UpdateRecipientHint)
ns.RegisterCallback("RULES_CHANGED", UpdateRecipientHint)

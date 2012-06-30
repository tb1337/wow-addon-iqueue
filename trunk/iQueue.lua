-----------------------------------
-- Setting up scope and libs
-----------------------------------

local AddonName = select(1, ...);
iQueue = LibStub("AceAddon-3.0"):NewAddon(AddonName, "AceEvent-3.0");

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);

local LibQTip = LibStub("LibQTip-1.0");

local _G = _G;

-----------------------------------------
-- Variables, functions and colors
-----------------------------------------

local COLOR_RED  = "|cffff0000%s|r";
local COLOR_GREEN= "|cff00ff00%s|r";
local COLOR_YELLOW= "|cffffff00%s|r";
local COLOR_GREY = "|cffaaaaaa%s|r";

local ICON_LFG_ON = "Interface\\Addons\\iQueue\\Images\\LFG-On";
local ICON_LFG_OFF = "Interface\\Addons\\iQueue\\Images\\LFG-Off";

local STATUS_NONE = 0;
local STATUS_AVAIL = 1;
local STATUS_QUEUED = 2;
local STATUS_PROPOSAL = 3;
local STATUS_ACTIVE = 4;

local QUEUE_LFG 		= _G.LE_LFG_CATEGORY_LFD;
local QUEUE_RF  		= _G.LE_LFG_CATEGORY_RF;
local QUEUE_SCE 		= _G.LE_LFG_CATEGORY_SCENARIO;
local QUEUE_LFR 		= _G.LE_LFG_CATEGORY_LFR;
local QUEUE_PVP 		= _G.NUM_LE_LFG_CATEGORYS +1;
local QUEUE_WG			= QUEUE_PVP +1;
local QUEUE_TB			= QUEUE_PVP +2;

local Queues = {
	[QUEUE_LFG] = STATUS_NONE,
	[QUEUE_RF]  = STATUS_NONE,
	[QUEUE_SCE] = STATUS_NONE,
	[QUEUE_LFR] = STATUS_NONE,
	[QUEUE_PVP] = STATUS_NONE,
	[QUEUE_WG]  = STATUS_NONE,
	[QUEUE_TB]	= STATUS_NONE,
};
local NUM_QUEUES = #Queues;
iQueue.Q = Queues;

-----------------------------
-- Setting up the feed
-----------------------------

iQueue.Feed = LibStub("LibDataBroker-1.1"):NewDataObject(AddonName, {
	type = "data source",
	text = "",
});

iQueue.Feed.OnClick = function(anchor, button)
	if( button == "LeftButton" ) then
		if( _G.IsModifierKeyDown() ) then
			if( _G.IsShiftKeyDown() ) then
				_G.ToggleLFDParentFrame();
			end
		else
			if( not iQueue:IsQueued() ) then
				return;
			end
			
			iQueue.Feed.OnLeave(anchor);
			
			_G.QueueStatusDropDown_Show(_G.QueueStatusMinimapButton.DropDown, anchor:GetName());
			
			if( not _G["DropDownList1"]:IsVisible() ) then
				iQueue.Feed.OnEnter(anchor);
			end
		end
	elseif( button == "RightButton" ) then
		if( _G.IsModifierKeyDown() ) then
			if( _G.IsShiftKeyDown() ) then
				_G.TogglePVPFrame();
			end
		else
			iQueue:OpenOptions();
		end
	end
end

iQueue.Feed.OnEnter = function(anchor)
	if( not iQueue:IsQueued() or _G["DropDownList1"]:IsVisible() ) then
		return;
	end
	
	-- LibQTip has the power to show one or more tooltips, but on a broker bar, where more than one QTips are present, this is really disturbing.
	-- So we release the tooltips of the i-Addons here.
	for k, v in LibQTip:IterateTooltips() do
		if( type(k) == "string" and strsub(k, 1, 6) == "iSuite" ) then
			v:Release(k);
		end
	end
	
	if( _G.QueueStatusFrame:GetParent() ~= anchor ) then
		_G.QueueStatusFrame:ClearAllPoints();
		_G.QueueStatusFrame:SetParent(anchor);
		_G.QueueStatusFrame:SetClampedToScreen(true);
		_G.QueueStatusFrame:SetPoint("TOP", anchor, "TOP", 14, -anchor:GetHeight());
	end
	
	_G.QueueStatusFrame:Show();
end

iQueue.Feed.OnLeave = function(anchor)
	_G.QueueStatusFrame:Hide();
end

------------------------------------------
-- OnInitialize and Reset
------------------------------------------

function iQueue:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("iQueueDB", self:CreateDB(), "Default").profile;

	self:UpdateBroker();
	
	-- All
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "EventHandler"); -- initial check if the player is in a queue
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "EventHandler"); -- when leaving a battlefield, no event is fired. So we check the group.
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "EventHandler"); -- need for loot rolling detection and world pvp areas
	self:RegisterEvent("ZONE_CHANGED", "EventHandler"); -- need for loot rolling detection and world pvp areas
	
	-- PvE
	self:RegisterEvent("LFG_UPDATE", "EventHandler");
	self:RegisterEvent("LFG_PROPOSAL_UPDATE", "EventHandler");
	self:RegisterEvent("LFG_PROPOSAL_FAILED", "EventHandler");
	self:RegisterEvent("LFG_PROPOSAL_SUCCEEDED", "EventHandler");
	self:RegisterEvent("LFG_PROPOSAL_SHOW", "EventHandler");
	self:RegisterEvent("LFG_QUEUE_STATUS_UPDATE", "EventHandler");
	
	self:DungeonComplete();
	
	-- PvP
	self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", "EventHandler");
	
	-- World PvP
	self:WatchWorldPvP();
end

function iQueue:DungeonComplete()
	if( self.db.LeaveDungeonWhenFinished ) then
		self:RegisterEvent("LFG_COMPLETION_REWARD", "_DungeonComplete");
	else
		self:UnregisterEvent("LFG_COMPLETION_REWARD");
	end
end

function iQueue:_DungeonComplete(event, ...)
	if( event == "LFG_COMPLETION_REWARD") then
		self:RegisterEvent("START_LOOT_ROLL", "_DungeonComplete");
	elseif( event == "START_LOOT_ROLL" ) then
		self.WatchLootRoll = select(1, ...);
		self:RegisterEvent("CHAT_MSG_LOOT", "_DungeonComplete");
	elseif( event == "CHAT_MSG_LOOT") then
		local looting;
		for i = 1, self.WatchLootRoll do
			if( _G.GetLootRollItemInfo(i) ) then
				looting = 1;
			end
		end
		
		if( not looting ) then
			self:UnregisterEvent("CHAT_MSG_LOOT");
			self:UnregisterEvent("START_LOOT_ROLL");
			self.WatchLootRoll = nil;
			
			if( self.db.LeaveDungeonAction == 1 ) then
				_G.StaticPopup_Show("IQUEUE_DUNGEONEND");
			else
				_G.LeaveParty();
			end
		end
	end
	
	
	local lootInProgress = false
	for i = 1, lootMaxID do
		if GetLootRollItemInfo(i) then
			lootInProgress = true
			break
		end
	end
	if lootInProgress == false then
		EQ:UnregisterEvent("CHAT_MSG_LOOT")
		EQ:UnregisterEvent("START_LOOT_ROLL")		
		if EQ.db.profile.LeavePrompt then
			StaticPopup_Show ("LEAVEAFTER")
		else
			if EQ.db.profile.FarewellEnabled then 
				SendChatMessage(EQ.db.profile.FarewellText ,"PARTY") 
				Sleep(1.0, function() LeaveParty() end)
			else
				LeaveParty()
			end
		end
		lfgLeavingParty = false
	end
end

function iQueue:WatchWorldPvP()
	if( self.db.WatchWorldPvP ) then
		if( not self.WorldPvPEventsRegistered ) then
			self:RegisterEvent("BATTLEFIELD_MGR_QUEUE_REQUEST_RESPONSE", "EventHandler");
			self:RegisterEvent("BATTLEFIELD_MGR_EJECT_PENDING", "EventHandler");
			self:RegisterEvent("BATTLEFIELD_MGR_EJECTED", "EventHandler");
			self:RegisterEvent("BATTLEFIELD_MGR_QUEUE_INVITE", "EventHandler");
			self:RegisterEvent("BATTLEFIELD_MGR_ENTRY_INVITE", "EventHandler");
			self:RegisterEvent("BATTLEFIELD_MGR_ENTERED", "EventHandler");
			
			self.WorldPvPEventsRegistered = 1;
		end
		
		if( self.db.WorldPvPTimer and not self.WorldPvPTimer ) then
			self:CheckWorldPvPStatus();
			self.WorldPvPTimer = LibStub("AceTimer-3.0"):ScheduleRepeatingTimer(iQueue.CheckWorldPvPStatus, 30);
		end
	else
		if( self.WorldPvPEventsRegistered ) then
			self:UnregisterEvent("BATTLEFIELD_MGR_QUEUE_REQUEST_RESPONSE");
			self:UnregisterEvent("BATTLEFIELD_MGR_EJECT_PENDING");
			self:UnregisterEvent("BATTLEFIELD_MGR_EJECTED");
			self:UnregisterEvent("BATTLEFIELD_MGR_QUEUE_INVITE");
			self:UnregisterEvent("BATTLEFIELD_MGR_ENTRY_INVITE");
			self:UnregisterEvent("BATTLEFIELD_MGR_ENTERED");
			
			self.WorldPvPEventsRegistered = nil;
		end
		
		if( self.WorldPvPTimer ) then
			LibStub("AceTimer-3.0"):CancelTimer(self.WorldPvPTimer);
			self.WorldPvPTimer = nil;
		end
		
		for i = QUEUE_PVP, #Queues do
			Queues[i] = STATUS_NONE;
		end
	end
	
	self:EventHandler("SELF_DUMP");
end

function iQueue:CheckWorldPvPStatus()
	local self = iQueue; -- didn't want to add AceTimer to my iQueue object, tho I must do shitty stuff like that
	
	if( self.db.WorldPvPPopup == 2 or self.db.WorldPvPPopup == 3 ) then
		self:CheckWorldPvPAlert(1); -- Wintergrasp
	end
	
	if( self.db.WorldPvPPopup == 2 or self.db.WorldPvPPopup == 4 ) then
		self:CheckWorldPvPAlert(2); -- Tol Barad
	end
end

function iQueue:CheckWorldPvPAlert(index)
	local pvpID, locName, isActive, canQueue, startTime, canEnter = _G.GetWorldPVPAreaInfo(index);
	
	if( canEnter ) then		
		if( isActive or canQueue or startTime <= 900 ) then
			--Queues[QUEUE_PVP + index] = STATUS_AVAIL;
			self["WorldPvP"..locName] = 1;
			
			if( (time() - self.db.WorldPvPLastAlert[index]) >= 3600 ) then
				_G.StaticPopup_Show("IQUEUE_WORLDPVPALARM");
				self.db.WorldPvPLastAlert[index] = time();
			end
		else
			self["WorldPvP"..locName] = nil;
		end
	end
end

---------------------------
-- Event Handlers
---------------------------

function iQueue:EventHandler(event)	
	-- check PvE queues
	for i = 1, _G.NUM_LE_LFG_CATEGORYS do
		local mode, submode = _G.GetLFGMode(i);
		
		if( not mode or mode == "abandonedInDungeon" ) then
			Queues[i] = STATUS_NONE;
		else			
			if( mode == "lfgparty" ) then
				Queues[i] = STATUS_ACTIVE;
			elseif( mode == "proposal" ) then
				Queues[i] = STATUS_PROPOSAL;
			elseif( mode == "queued" ) then
				Queues[i] = STATUS_QUEUED;
			end
		end
	end
	
	-- check PvP queues
	Queues[QUEUE_PVP] = STATUS_NONE;
	
	for i = 1, _G.GetMaxBattlefieldID() do
		--local status, mapName, instanceID, levelRangeMin, levelRangeMax, teamSize, registeredMatch, eligibleInQueue, waitingOnOtherActivity = GetBattlefieldStatus(i);
		local status = _G.GetBattlefieldStatus(i);
		
		if( status and status ~= "none" and status ~= "error" ) then
			if( status == "active" ) then
				status = STATUS_ACTIVE;
			elseif( status == "confirm" ) then
				status = STATUS_PROPOSAL;
			elseif( status == "queued" ) then
				status = STATUS_QUEUED;
			end
			
			Queues[QUEUE_PVP] = status > Queues[QUEUE_PVP] and status or Queues[QUEUE_PVP];
		end
	end
	
	-- check World PvP queues
	if( self.db.WatchWorldPvP ) then
		for i = 1, _G.MAX_WORLD_PVP_QUEUES do
			--local status, mapName, queueID = GetWorldPVPQueueStatus(i);
			local status, mapName = _G.GetWorldPVPQueueStatus(i);
			local newStatus;
			
			local area = 0;
			for j = 1, 2 do
				if( select(2, _G.GetWorldPVPAreaInfo(j)) == mapName ) then
					area = j;
				end
			end
			
			if( area ~= 0 ) then
				if( self["WorldPvP"..mapName] ) then
					newStatus = STATUS_AVAIL;
				else
					newStatus = STATUS_NONE;
				end
				
				if( _G.GetRealZoneText() == mapName ) then
					newStatus = STATUS_ACTIVE;
				elseif( status == "confirm" ) then
					newStatus = STATUS_PROPOSAL;
				elseif( status == "queued" ) then
					newStatus = STATUS_QUEUED;
				end
				
				Queues[QUEUE_PVP +area] = newStatus;
			end
		end
	end
		
	self:UpdateBroker();
end

----------------------
-- UpdateBroker
----------------------

function iQueue:IsQueued()
	for i, v in ipairs(Queues) do
		if( v ~= STATUS_NONE ) then
			return 1;
		end
	end
	
	return;
end

function iQueue:UpdateBroker()
	local text = "";
	local icon = ICON_LFG_OFF;
	
	if( self:IsQueued() ) then
		local name;
		local color;
		
		for q, v in ipairs(Queues) do
			if( v ~= STATUS_NONE ) then
				if( q == QUEUE_LFG ) then
					name = "LFG";
				elseif( q == QUEUE_RF ) then
					name = "RF";
				elseif( q == QUEUE_SCE ) then
					name = "SCE";
				elseif( q == QUEUE_LFR ) then
					name = "LFR";
				elseif( q == QUEUE_PVP ) then
					name = "PvP";
				elseif( q > QUEUE_PVP ) then
					if( (q - QUEUE_PVP) == 1 ) then
						name = "WG";
					elseif( (q - QUEUE_PVP) == 2 ) then
						name = "TB";
					end
				else
					name = _G.UNKNOWN;
				end
				
				if( v == STATUS_QUEUED ) then
					color = COLOR_RED;
				elseif( v == STATUS_PROPOSAL ) then
					color = COLOR_YELLOW;
				elseif( v == STATUS_ACTIVE ) then
					color = COLOR_GREEN;
				elseif( v == STATUS_AVAIL ) then
					color = COLOR_GREY;
				end
				
				text = text.." "..(color):format(name);
			end
		end
		
		icon = ICON_LFG_ON;
	end
	
	self.Feed.text = text;
	self.Feed.icon = icon;
end

---------------------
-- Final stuff
---------------------

_G.StaticPopupDialogs["IQUEUE_WORLDPVPALARM"] = {
	preferredIndex = 3, -- apparently avoids some UI taint
	text = "A World PvP Area is ready to be queued!",
	button1 = "Enter",
	button2 = "Cancel",
	timeout = 900,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(self)
		_G.TogglePVPFrame();
	end,
};

_G.StaticPopupDialogs["IQUEUE_DUNGEONEND"] = {
	preferredIndex = 3, -- apparently avoids some UI taint
	text = "The dungeon is cleared and loot is assigned to players. Leave group?",
	button1 = "Yes",
	button2 = "No",
	timeout = 900,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(self)
		_G.LeaveParty();
	end,
};
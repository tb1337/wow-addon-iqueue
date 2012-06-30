-----------------------------------
-- Setting up scope and libs
-----------------------------------

local AddonName = select(1, ...);
iQueue = LibStub("AceAddon-3.0"):NewAddon(AddonName, "AceEvent-3.0");

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);

local LibQTip = LibStub("LibQTip-1.0");

local _G = _G; -- I always use _G.func on global functions

-----------------------------------------
-- Variables, functions and colors
-----------------------------------------

local COLOR_RED  = "|cffff0000%s|r";
local COLOR_GREEN= "|cff00ff00%s|r";
local COLOR_YELLOW= "|cffffff00%s|r";
local COLOR_GREY = "|cffaaaaaa%s|r";

local ICON_LFG_ON = "Interface\\Addons\\iQueue\\Images\\LFG-On";
local ICON_LFG_OFF = "Interface\\Addons\\iQueue\\Images\\LFG-Off";

local STATUS_NONE = 0; -- set if queue isn't active
local STATUS_AVAIL = 1; -- only WG/TB: queue is available
local STATUS_QUEUED = 2; -- set if queued
local STATUS_PROPOSAL = 3; -- set if invite is pending
local STATUS_ACTIVE = 4; -- set if in assembled group

local QUEUE_LFG 		= _G.LE_LFG_CATEGORY_LFD; -- ID for lfg dungeons used by Blizzard
local QUEUE_RF  		= _G.LE_LFG_CATEGORY_RF; -- ID for raid finder used by Blizzard
local QUEUE_SCE 		= _G.LE_LFG_CATEGORY_SCENARIO; -- ID for scenarios used by Blizzard
local QUEUE_LFR 		= _G.LE_LFG_CATEGORY_LFR; -- ID for LFR used by Blizzard
local QUEUE_PVP 		= _G.NUM_LE_LFG_CATEGORYS +1; -- virtual queue ID for PvP queues, set by me (should be 5)
local QUEUE_WG			= QUEUE_PVP +1; -- queue ID for Wintergrasp (should be 6)
local QUEUE_TB			= QUEUE_PVP +2; -- queue ID for Tol Barad (should be 7)

local Queues = { -- Stores a status for each queue category, defaults to STATUS_NONE
	[QUEUE_LFG] = STATUS_NONE,
	[QUEUE_RF]  = STATUS_NONE,
	[QUEUE_SCE] = STATUS_NONE,
	[QUEUE_LFR] = STATUS_NONE,
	[QUEUE_PVP] = STATUS_NONE,
	[QUEUE_WG]  = STATUS_NONE,
	[QUEUE_TB]	= STATUS_NONE,
};
iQueue.Q = Queues; -- for debugging purposes

-----------------------------
-- Setting up the feed
-----------------------------

iQueue.Feed = LibStub("LibDataBroker-1.1"):NewDataObject(AddonName, {
	type = "data source",
	text = "",
});

iQueue.Feed.OnClick = function(anchor, button)
	-- left click
	if( button == "LeftButton" ) then
		-- on CTRL/ALT/Shift pressed
		if( _G.IsModifierKeyDown() ) then
			-- Shift + Left opens LFD frame
			if( _G.IsShiftKeyDown() ) then
				_G.ToggleLFDParentFrame();
			end
		else
			-- no modifier pressed, but if not queued, no action is done
			if( not iQueue:IsQueued() ) then
				return;
			end
			
			iQueue.Feed.OnLeave(anchor); -- hides the mouseover tooltip
			_G.QueueStatusDropDown_Show(_G.QueueStatusMinimapButton.DropDown, anchor:GetName()); -- shows Blizzard tooltip for leaving instead
			
			if( not _G["DropDownList1"]:IsVisible() ) then
				iQueue.Feed.OnEnter(anchor); -- re-shows the mouseover tooltip and hides Blizzard tooltip if clicked again
			end
		end
	-- right click
	elseif( button == "RightButton" ) then
		-- on CTRL/ALT/Shift pressed
		if( _G.IsModifierKeyDown() ) then
			-- Shift + Right opens PVP frame
			if( _G.IsShiftKeyDown() ) then
				_G.TogglePVPFrame();
			end
		else
			-- no modifier pressed, open options
			iQueue:OpenOptions();
		end
	end
end

iQueue.Feed.OnEnter = function(anchor)
	-- does not show mouseover tooltip when not queued or if Blizzard tooltip is visible
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
	
	-- the mouse over tooltip (Blizzard UI element) needs to be attached to Broker plugin
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

	self:UpdateBroker(); -- initially shows no queues and a grey icon
	
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
	
	self:DungeonComplete(); -- toggles LFG_COMPLETION_REWARD event, depending on the LeaveDungeon option
	
	-- PvP
	self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", "EventHandler");
	
	-- World PvP
	self:WatchWorldPvP(); -- toggles World PvP Area events, depending on the World PvP options
end

function iQueue:DungeonComplete()
	if( self.db.LeaveDungeonWhenFinished ) then
		self:RegisterEvent("LFG_COMPLETION_REWARD", "_DungeonComplete");
	else
		self:UnregisterEvent("LFG_COMPLETION_REWARD");
	end
end

function iQueue:_DungeonComplete(event, ...)
	-- the dungeon is cleared and the loot roll starts soon
	if( event == "LFG_COMPLETION_REWARD") then
		self:RegisterEvent("START_LOOT_ROLL", "_DungeonComplete");
	-- the loot roll takes place, we store the number of maximum items dropped by the boss
	elseif( event == "START_LOOT_ROLL" ) then
		self.WatchLootRoll = select(1, ...);
		self:RegisterEvent("CHAT_MSG_LOOT", "_DungeonComplete");
	-- loot gets assigned to players
	elseif( event == "CHAT_MSG_LOOT") then
		local looting;
		for i = 1, self.WatchLootRoll do
			if( _G.GetLootRollItemInfo(i) ) then
				looting = 1; -- one or more items are still rolled
			end
		end
		
		-- when rolling has finished, we fire a message to the player or auto-leave him, depending on the options
		if( not looting ) then
			self:_DungeonComplete("reset");
			
			if( self.db.LeaveDungeonAction == 1 ) then
				_G.StaticPopup_Show("IQUEUE_DUNGEONEND");
			else
				_G.LeaveParty();
			end
		end
	-- simply refactoring of code by using a dummy event: we need this snippet twice
	elseif( event == "reset" ) then
		self:UnregisterEvent("CHAT_MSG_LOOT");
		self:UnregisterEvent("START_LOOT_ROLL");
		self.WatchLootRoll = nil;
	end
end

function iQueue:WatchWorldPvP()
	-- if World PvP Areas should be watched, we need to register some events...
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
		
		-- ...and if iQueue shall tell the player when to queue for WG/TB, we need to register a timer
		if( self.db.WorldPvPTimer and not self.WorldPvPTimer ) then
			self:CheckWorldPvPStatus();
			self.WorldPvPTimer = LibStub("AceTimer-3.0"):ScheduleRepeatingTimer(iQueue.CheckWorldPvPStatus, 30);
		end
	-- ...if watching isn't enabled, we check if we need to unregister the events
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
		
		-- ...and the timer
		if( self.WorldPvPTimer ) then
			LibStub("AceTimer-3.0"):CancelTimer(self.WorldPvPTimer);
			self.WorldPvPTimer = nil;
		end
		
		-- finally, all World PvP Areas queues are set to STATUS_NONE
		for i = QUEUE_PVP, #Queues do
			Queues[i] = STATUS_NONE;
		end
	end
	
	self:EventHandler("SELF_DUMP"); -- run the EventHandler to clear out remaining data
end

function iQueue:CheckWorldPvPStatus()
	local self = iQueue; -- didn't want to add AceTimer to my iQueue object, tho I must do shitty stuff like that
	
	if( self.db.WorldPvPPopup == 2 or self.db.WorldPvPPopup == 3 ) then
		self:CheckWorldPvPAlert(1); -- Wintergrasp
	end
	
	if( self.db.WorldPvPPopup == 2 or self.db.WorldPvPPopup == 4 ) then
		self:CheckWorldPvPAlert(2); -- Tol Barad
	end
	
	self:EventHandler("SELF_DUMP"); -- run the EventHandler to modify the queue display
end

function iQueue:CheckWorldPvPAlert(index)
	local pvpID, locName, isActive, canQueue, startTime, canEnter = _G.GetWorldPVPAreaInfo(index);
	
	if( canEnter ) then -- if the player cannot enter the World PvP Area, we don't check it
		if( isActive or canQueue or startTime <= 900 ) then
			self["WorldPvP"..locName] = 1; -- I don't wanna set the queue status here, so we set a transporter variable
			
			-- remembers the player to queue for the World PvP Area
			if( (time() - self.db.WorldPvPLastAlert[index]) >= 3600 ) then
				_G.StaticPopup_Show("IQUEUE_WORLDPVPALARM");
				self.db.WorldPvPLastAlert[index] = time(); -- we just want this popup once
			end
		else
			self["WorldPvP"..locName] = nil; -- if the queue isn't active (anymore), the transporter variable is cleared
		end
	end
end

---------------------------
-- Event Handler
---------------------------

function iQueue:EventHandler(event)
	-- see _DungeonComplete function. If the player leaves the group before the loot roll has ended, we need to reset it manually
	-- We determine leaving the group by a simple zone change :)
	if( event == "ZONE_CHANGED" and self.WatchLootRoll ) then
		self:_DungeonComplete("reset");
	end

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
	
	-- There are one or two PvP queues available.
	-- 1 queue if queueing for random BGs, 2 queues if queueing for specified BGs
	-- We simply reset the PvP queue status and run our checks. This is a really clean way without declaring 1-2 helper vars.
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
			
			-- Because of 2 queues possible and just 1 PvP display, we store the "higher" queue status
			Queues[QUEUE_PVP] = status > Queues[QUEUE_PVP] and status or Queues[QUEUE_PVP];
		end
	end
	
	-- check World PvP queues
	if( self.db.WatchWorldPvP ) then
		for i = 1, _G.MAX_WORLD_PVP_QUEUES do
			--local status, mapName, queueID = GetWorldPVPQueueStatus(i);
			local status, mapName = _G.GetWorldPVPQueueStatus(i);
			local newStatus;
			
			-- The only way to identify a queued World PvP Area is to check its localized map name (e.g. Tol Barad)
			-- Why? Well, I hardcoded WG/TB queue IDs (6 and 7), but GetWorldPVPQueueStatus() may also return TB as ID 1 (= 6 in iQueue, which is WG!)			
			local area = 0;
			for j = 1, 2 do
				local _, locName = _G.GetWorldPVPAreaInfo(j);
				if( locName == mapName ) then
					area = j;
				end
			end
			
			-- if we identified the queue, we store the queue status for it.
			if( area ~= 0 ) then
				-- this is our transporter variable. If it is set, the queue is active!
				if( self["WorldPvP"..mapName] ) then
					newStatus = STATUS_AVAIL;
				else
					newStatus = STATUS_NONE; -- otherwise STATUS_NONE is set.
				end
				
				if( _G.GetRealZoneText() == mapName ) then -- World PvP Areas have no "active" state in the Blizzard API, so we emulate it.
					newStatus = STATUS_ACTIVE; -- iQueue assumes that you are playing a World PvP Area, if you are in the area.
				elseif( status == "confirm" ) then
					newStatus = STATUS_PROPOSAL;
				elseif( status == "queued" ) then
					newStatus = STATUS_QUEUED;
				end
				
				Queues[QUEUE_PVP +area] = newStatus;
			end
		end
	end
		
	self:UpdateBroker(); -- simply display our changes
end

----------------------
-- UpdateBroker
----------------------

function iQueue:IsQueued() -- returns 1 if queued somewhere, nil otherwise
	for i, v in ipairs(Queues) do
		if( v ~= STATUS_NONE ) then
			return 1;
		end
	end
	
	return;
end

function iQueue:UpdateBroker()
	-- by default, iQueue assumes that no queues are active
	local text = "";
	local icon = ICON_LFG_OFF;
	
	-- if at least one queue is active, we loop thru our Queues table
	if( self:IsQueued() ) then
		local name;
		local color;
		
		for q, v in ipairs(Queues) do
			-- the queue status must be ~= STATUS_NONE in order to display a queue
			if( v ~= STATUS_NONE ) then
				-- simply gets an abbreviation for the queue (e.g. Looking for Dungeon = LFG)
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
				elseif( q > QUEUE_PVP ) then -- uhhh... hard coding sucks -.-
					if( (q - QUEUE_PVP) == 1 ) then
						name = "WG";
					elseif( (q - QUEUE_PVP) == 2 ) then
						name = "TB";
					end
				else
					name = _G.UNKNOWN; -- should NEVER happen!
				end
				
				-- colorizing the queue name abbreviation
				if( v == STATUS_QUEUED ) then
					color = COLOR_RED;
				elseif( v == STATUS_PROPOSAL ) then
					color = COLOR_YELLOW;
				elseif( v == STATUS_ACTIVE ) then
					color = COLOR_GREEN;
				elseif( v == STATUS_AVAIL ) then
					color = COLOR_GREY;
				end
				
				-- finally displaying it
				text = text.." "..(color):format(name);
			end
		end
		
		icon = ICON_LFG_ON; -- if queued, the icon shall be green
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
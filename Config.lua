-----------------------------
-- Get the addon table
-----------------------------

local AddonName, iQueue = ...;

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);

local _G = _G;

--------------------------
-- The option table
--------------------------

function iQueue:CreateDB()
	iQueue.CreateDB = nil;
	
	return { profile = {
		LeaveDungeonWhenFinished = true,
		LeaveDungeonAction = 1,
		WatchWorldPvP = false,
		WorldPvPTimer = false,
		WorldPvPPopup = 2,
		WorldPvPLastAlert = { 0, 0 }, -- we save last alert times for both WG and TB
	}};
end

---------------------------------
-- The configuration table
---------------------------------

local function CreateConfig()
	CreateConfig = nil; -- we just need this function once, thus removing it from memory.

	local db = {
		type = "group",
		name = AddonName,
		order = 1,
		childGroups = "tab",
		args = {
			GroupGeneral = {
				type = "group",
				name = "General",
				order = 10,
				args = {
					LeaveDungeonWhenFinished = {
						type = "toggle",
						name = "Do something when a dungeon is cleared",
						order = 10,
						width = "double",
						get = function()
							return iQueue.db.LeaveDungeonWhenFinished;
						end,
						set = function(info, value)
							iQueue.db.LeaveDungeonWhenFinished = value;
							iQueue:DungeonComplete();
						end,
					},
					LeaveDungeonAction = {
						type = "select",
						name = "Action:",
						order = 11,
						get = function()
							return iQueue.db.LeaveDungeonAction;
						end,
						set = function(info, value)
							iQueue.db.LeaveDungeonAction = value;
						end,
						values = {
							[1] = "Show Popup",
							[2] = "Auto Leave",
						},
					},
				},
			},
			GroupWorldPvP = {
				type = "group",
				name = "World PvP",
				order = 20,
				args = {
					Description1 = {
						type = "description",
						name = "As of Mists of Pandaria, World PvP Areas are deprecated. If you would like to farm achievements or something else, you may enable World PvP handling in iQueue.".."\n",
						fontSize = "medium",
						order = 10,
					},
					WatchWorldPvP = {
						type = "toggle",
						name = "Enable handling for World PvP Areas",
						order = 20,
						width = "full",
						get = function()
							return iQueue.db.WatchWorldPvP;
						end,
						set = function(info, value)
							iQueue.db.WatchWorldPvP = value;
							iQueue:WatchWorldPvP();
						end,
					},
					EmptyLine1 = {
						type = "header",
						name = "",
						order = 30,
					},
					WorldPvPTimer = {
						type = "toggle",
						name = "Alert when the queue for a World PvP Area recently opened.",
						order = 40,
						width = "full",
						get = function()
							return iQueue.db.WorldPvPTimer;
						end,
						set = function(info, value)
							iQueue.db.WorldPvPTimer = value;
							iQueue:WatchWorldPvP();
						end,
					},
					WorldPvPPopup = {
						type = "select",
						name = "Popup message for:",
						order = 41,
						get = function()
							return iQueue.db.WorldPvPPopup;
						end,
						set = function(info, value)
							iQueue.db.WorldPvPPopup = value;
						end,
						values = {
							[1] = "None",
							[2] = "All",
							[3] = "Wintergrasp",
							[4] = "Tol Barad",
						},
					},
				},
			},
		},
	};
	
	return db;
end

function iQueue:OpenOptions()
	_G.InterfaceOptionsFrame_OpenToCategory(AddonName);
end

LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName, CreateConfig);
LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName);
_G.SlashCmdList["IQUEUE"] = iQueue.OpenOptions;
_G["SLASH_IQUEUE1"] = "/iqueue";
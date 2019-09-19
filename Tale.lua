-- ********************************************************
-- **                      Tale                       **
-- ********************************************************
--
-- This addon is written and copyrighted by:
--    * Mîzukichan @ EU-Antonidas (2010-2019)
--    * Albin Johansson (2019)
--
-- Contributors:
--    * Softea_Lethon (Show played time on screenshot, Classic support) (2019) 
--
--    This file is part of Tale, a fork of Memoria.
--
--    Tale is free software: you can redistribute it and/or 
--    modify it under the terms of the GNU General Public License as 
--    published by the Free Software Foundation, either version 3 of the 
--    License, or (at your option) any later version.
--
--    Tale is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with Tale.  
--    If not, see <http://www.gnu.org/licenses/>.
--

-- Check for addon table
if (not Tale) then Tale = {}; end
local Tale = Tale;


----------------------------
--  Variables and Locals  --
----------------------------
Tale.ADDONNAME = "Tale"
Tale.ADDONVERSION = GetAddOnMetadata(Tale.ADDONNAME, "Version");
Tale.BattlefieldScreenshotAlreadyTaken = false
Tale.Debug = nil
Tale.WaitForTimePlayed = false
Tale.ChatSettings = {}
Tale.PlayerLevel = 1
Tale.IsRetail = tonumber(string.sub(GetBuildInfo(), 1, 1)) > 1
local deformat = LibStub("LibDeformat-3.0")


------------------------
--  Addon FSM States  --
------------------------
local STATE_IDLE           = 0
local STATE_SHOT_SCHEDULED = 1
local STATE_SHOT_DELAY     = 2
local STATE_SCREENSHOT     = 3
local STATE_RESTORE_DELAY  = 4


-----------------------
--  Default Options  --
-----------------------
Tale.DefaultOptions = {
    battlegroundEnding = false,
    battlegroundEndingOnlyWins = false,
    bosskills = true,
    bosskillsFirstkill = false,
    reputationChange = true,
    reputationChangeOnlyExalted = false,
    levelUp = true,
    levelUpShowPlayed = false,
    resizeChat = false,
    version = 1,
    logInterval = 10,
    pvpKills = false,
    pvpKillsLog = true,
    death = death,
    deathLog = true,
    battlegroundEndingLog = true,
    levelUpLog = true,
    bosskillsLog = true,
    questTurnInLog = true,
    killsLog = true,
    groupLog = true,
}

Tale.EntryIDs = {
    std = 101,
    fly = 102,
    ghost = 103,
    login = 191,
    death = 201,
    lvl = 301,
    boss = 411,
    pvpk = 501,
    bgend = 511,
    quest = 311,
    kill = 401,
    groupchange = 601,
    groupleft = 603,
}

----------------------------
--  Declare EventHandler  --
----------------------------
function Tale:EventHandler(frame, event, ...)
    if (event == "ADDON_LOADED") then
        local addonName = ...
        if (addonName == Tale.ADDONNAME) then
            Tale:ADDON_LOADED_Handler(frame)
        end
    
        
    
    elseif (event == "CHAT_MSG_SYSTEM") then
        Tale:DebugMsg("CHAT_MSG_SYSTEM_Handler() called...")
        Tale:CHAT_MSG_SYSTEM_Handler(...)
    
    elseif (event == "PLAYER_LEVEL_UP") then
        Tale:PLAYER_LEVEL_UP_Handler(...)
    
    elseif (event == "TIME_PLAYED_MSG") then
        if (Tale.WaitForTimePlayed) then
            Tale:PLAYER_LEVEL_UP_SHOW_PLAYED_Handler(...)
        end
        
    elseif (event == "UPDATE_BATTLEFIELD_STATUS") then
        Tale:UPDATE_BATTLEFIELD_STATUS_Handler()

    elseif (event == "COMBAT_LOG_EVENT_UNFILTERED") then
	Tale:COMBAT_LOG_Handler(...)

    elseif (event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST") then
	Tale:RESS_Handler(...)

    elseif (event == "PLAYER_DEAD") then
	Tale:PLAYER_DEAD_Handler(...)

    elseif (event == "PLAYER_CONTROL_LOST") then
	Tale:PLAYER_CONTROL_LOST_Handler(...)

    elseif (event == "PLAYER_CONTROL_GAINED") then
	Tale:PLAYER_CONTROL_GAINED_Handler(...)

    elseif (event == "QUEST_TURNED_IN") then
	Tale:QUEST_TURNED_IN_Handler(...)

    elseif (event == "GROUP_ROSTER_UPDATE") then
        Tale:GROUP_Handler(...)

    end

end

function Tale:GROUP_Handler(category, partyID)
    if (not Tale_Options.groupLog) then return; end
    local members = GetHomePartyInfo()
    if GetNumGroupMembers() == Tale.partyMembers then return; end
    Tale.partyMembers = GetNumGroupMembers()
    if members == nil then
        Tale:SaveCurrentState(Tale.EntryIDs.groupleft)
        return
    end
    local names = nil
    for k,v in pairs(members) do
        if names == nil then 
            names = v 
        else 
            names = format("%s, %s", names, v)
        end
    end
    Tale:SaveCurrentState(format("%d, %s", Tale.EntryIDs.groupchange, names))
    
end

function Tale:ADDON_LOADED_Handler(frame)
    Tale:Initialize(frame)
    Tale:RegisterEvents(frame)
    TaleFrame:SetScript("OnUpdate", Tale.OnUpdate)
    Tale:SaveCurrentState(Tale.EntryIDs.login)
end

function Tale:CHAT_MSG_SYSTEM_Handler(...)
    if (not Tale_Options.reputationChange) then return; end
    local chatmsg = ...
    local repLevel, faction = deformat(chatmsg, FACTION_STANDING_CHANGED)
    if (not repLevel or not faction) then return; end
    if (not Tale_Options.reputationChangeOnlyExalted) then
        Tale:AddScheduledScreenshot(1)
        Tale:DebugMsg("Reputation level changed - Added screenshot to queue")
    else
        if (repLevel == FACTION_STANDING_LABEL8 or repLevel == FACTION_STANDING_LABEL8_FEMALE) then
            Tale:AddScheduledScreenshot(1)
            Tale:DebugMsg("Reputation level reached exalted - Added screenshot to queue")
        end
    end
end

function Tale:PLAYER_CONTROL_LOST_Handler(...)
    Tale:StandardStateSave()
end

function Tale:PLAYER_CONTROL_GAINED_Handler(...)
    Tale:StandardStateSave()
end

function Tale:BossKill_Handler(id, name)
    if (Tale_Options.bosskillsLog) then 
            local s = format("%d, %s, %s", Tale.EntryIDs.boss, name, id)
            Tale:SaveCurrentState(s)
    end
    if (not Tale_Options.bosskills) then return; end
    -- check if boss was a known kill, if "only after first kill" is enabled
    if (not Tale_CharBossKillDB) then Tale_CharBossKillDB = {}; end
    if (Tale_Options.bosskillsFirstkill and Tale_CharBossKillDB[id]) then return; end
    Tale:AddScheduledScreenshot(1)
    Tale:DebugMsg("Encounter successful - Added screenshot to queue")
    Tale_CharBossKillDB[id] = true
end

function Tale:PLAYER_DEAD_Handler(...)
    Tale:DebugMsg("PLAYER_DEAD_Handler() called...")
    if (Tale_Options.deathLog) then Tale:SaveCurrentState(format("%d, %s", Tale.EntryIDs.death, Tale.LastAttack)); end
    if (Tale_Options.death) then Tale:AddScheduledScreenshot(1); end
end

function Tale:PLAYER_KILLS_UNIT_Check(subevent, sourceName, destGUID, destName)
    if (subevent == "PARTY_KILL") then
        local tokens = Tale:Tokenize_GUID(destGUID)
        if tokens[1] == "Player" then
            Tale:PLAYER_PVP_KILLS_CHANGED_Handler(destName)
        elseif Tale.bosses[tonumber(tokens[6])] ~= nil then
            Tale:BossKill_Handler(tokens[6], destName)
        elseif (Tale_Options.killsLog) then 
            Tale:SaveCurrentState(format("%d, %s, %d", Tale.EntryIDs.kill, destName, tokens[6]))
        end
    end
end

function Tale:PLAYER_TAKES_DAMAGE_Check(subevent, sourceName, prefixParam1)
    if (subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "RANGE_DAMAGE") then -- and (suffixParam2 > 0 or UnitIsDeadOrGhost("player")) then
	Tale.LastAttack = sourceName
    elseif subevent == "SWING_DAMAGE" then --and (prefixParam2 > 0 or UnitIsDeadOrGhost("player")) then
	Tale.LastAttack = sourceName
    elseif subevent == "ENVIRONMENTAL_DAMAGE" then
	Tale.LastAttack = prefixParam1
    end
end

function Tale:Tokenize_GUID(GUID)
    local tokens = {}
    for v in string.gmatch(GUID, "[^-]+") do
        table.insert(tokens, v)
    end
    return tokens
end

function Tale:COMBAT_LOG_Handler(...)
    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, prefixParam1, prefixParam2, _, suffixParam1, suffixParam2  = CombatLogGetCurrentEventInfo()
    if not (destName == UnitName("player")) then 
        Tale:PLAYER_KILLS_UNIT_Check(subevent, sourceName, destGUID, destName)
    else
	if (Tale_Options.deathLog) then Tale:PLAYER_TAKES_DAMAGE_Check(subevent, sourceName, prefixParam1); end
    end
end

function Tale:PLAYER_PVP_KILLS_CHANGED_Handler(unitTarget)
    Tale:DebugMsg("PLAYER_PVP_KILLS_CHANGED_Handler() called...")
    if (Tale_Options.pvpKillsLog) then Tale:SaveCurrentState(format("%d, %s", Tale.EntryIDs.pvpk, unitTarget)); end
    if (Tale_Options.pvpKills) then Tale:AddScheduledScreenshot(1); end
end

function Tale:PLAYER_LEVEL_UP_Handler(level, ...)
    Tale:DebugMsg("PLAYER_LEVEL_UP_Handler() called...")
    Tale.PlayerLevel = level
    if not Tale_CharLevelTimes[Tale.PlayerLevel] then
        Tale_CharLevelTimes[Tale.PlayerLevel] = 0
    end
    if (Tale_Options.levelUpLog) then Tale:SaveCurrentState(Tale.EntryIDs.lvl); end
    if (not Tale_Options.levelUp) then return; end
    if (Tale_Options.levelUpShowPlayed) then
        Tale.WaitForTimePlayed = true
        RequestTimePlayed()
        return
    end
    Tale:AddScheduledScreenshot(1)
    Tale:DebugMsg("Level up - Added screenshot to queue")
end

function Tale:PLAYER_LEVEL_UP_SHOW_PLAYED_Handler(...)
    Tale:DebugMsg("PLAYER_LEVEL_UP_SHOW_PLAYED_Handler() called...")
    if (not Tale_Options.levelUp) then return; end
    if (not Tale_Options.levelUpShowPlayed) then return; end
    if (not Tale.WaitForTimePlayed) then return; end
    Tale.WaitForTimePlayed = false
    Tale:ShowPrevious()
    Tale:AddScheduledScreenshot(0)
    Tale:DebugMsg("Level up show played - Added screenshot to queue")
end

function Tale:QUEST_TURNED_IN_Handler(...)
    Tale:DebugMsg("QUEST_TURNED_IN_Handler() called...")
    local id, xp, money = ...
    Tale:SaveCurrentState(format("%d, %s", Tale.EntryIDs.quest, id))
end

function Tale:RESS_Handler(...)
    Tale:DebugMsg("RESS_Handler() called...")
    Tale:StandardStateSave()
end

function Tale:UPDATE_BATTLEFIELD_STATUS_Handler()
    Tale:DebugMsg("UPDATE_BATTLEFIELD_STATUS_Handler() called...")
    -- if not activated, return
    if (not Tale_Options.battlegroundEnding and not Tale_Options.battlegroundEndingLog) then return; end
    -- if not ended, return
    local winner = GetBattlefieldWinner()                                                                             -- possible values: nil (no winner yet), 0 (Horde / green Team), 1 (Alliance / gold Team)
    if (winner == nil) then 
        Tale.BattlefieldScreenshotAlreadyTaken = false
        return
    end
    -- if screenshot of this battlefield already taken, then return
    if (Tale.BattlefieldScreenshotAlreadyTaken) then return; end
    -- if we are here, we have a freshly finished battleground
    local playerFaction = UnitFactionGroup("player")
    local win = (playerFaction == "Alliance" and winner == 1) or (playerFaction == "Horde" and winner == 0) 
    local stateString = "lost"	
    if (win) then
	stateString = "won"
    end
    -- playerFaction is either "Alliance" or "Horde"
    if (not Tale_Options.battlegroundEndingOnlyWins or win) then
	if (Tale_Options.battlegroundEndingLog) then Tale:SaveCurrentState(format("%d, %s", Tale.EntryIDs.bgend, stateString)); end
	if (Tale_Options.battlegroundEnding) then
	    Tale:AddScheduledScreenshot(1)
	    Tale.BattlefieldScreenshotAlreadyTaken = true
	    Tale:DebugMsg("Battleground won - Added screenshot to queue")
	end
    end
end

function Tale:SaveCurrentState(trigger)
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = nil
    if not (mapID == nil) then
        pos = C_Map.GetPlayerMapPosition(mapID, "player")
    end
    local x, y = -1, -1
    if (pos == nil) then
	x, y = -1, -1
    else
        x, y = pos:GetXY()
    end
    if (mapID == nil) then
	mapID = -1
    end
    table.insert(Tale_LogData, format("%f, %f, %d, %d, %d, %s", x, y, mapID, time(), Tale.PlayerLevel, trigger))
end

function Tale:StandardStateSave()
    if UnitIsGhost("player") then
	Tale:SaveCurrentState(Tale.EntryIDs.ghost)
    elseif UnitOnTaxi("player") then
	Tale:SaveCurrentState(Tale.EntryIDs.fly)
    else
	Tale:SaveCurrentState(Tale.EntryIDs.std)
    end
end

function Tale:OnUpdate(elapsed)
    Tale_CharLevelTimes[Tale.PlayerLevel] = Tale_CharLevelTimes[Tale.PlayerLevel] + elapsed
    Tale:ScreenshotHandler(elapsed)
    self.sinceLastUpdate = (self.sinceLastUpdate or Tale_Options['logInterval']) + elapsed;
    if ( self.sinceLastUpdate >= Tale_Options['logInterval'] ) then -- in seconds
	self.sinceLastUpdate = 0;
	Tale:StandardStateSave()
    end
end


function Tale:TableLength(tab)
    local count = 0
    for _ in pairs(tab) do count = count + 1 end
    return count
end

function Tale:SaveVersion(version, position)
    table.insert(Tale_VersionData, format(version..", %d", position))
end

----------------------------------------------
--  Update saved data and initialize addon  --
----------------------------------------------
function Tale:Initialize(frame)
    if (not Tale_Options) then
        Tale_Options = {}
    end
    for key, val in pairs(Tale.DefaultOptions) do
        if not Tale_Options[key] then Tale_Options[key] = val; end
    end
    if (not Tale_LogData) then
	Tale_LogData = {}
    end
    if (not Tale_VersionData) then
	Tale_VersionData = {}
	local len = Tale:TableLength(Tale_LogData)
	if (len > 0) then
	    Tale:SaveVersion("1.0", 1)
	end
    end
    if (not Tale_CharBossKillDB) then
        Tale_CharBossKillDB = {}
    end
    if (not Tale_CharLevelTimes) then
        Tale_CharLevelTimes = {}
    end
    Tale.PlayerLevel = UnitLevel("PLAYER")
    if not Tale_CharLevelTimes[Tale.PlayerLevel] then
        Tale_CharLevelTimes[Tale.PlayerLevel] = 0
    end
    local versionlen = Tale:TableLength(Tale_VersionData)
    if (versionlen == 0 or not string.match(Tale_VersionData[versionlen], Tale.ADDONVERSION)) then
        local loglen = Tale:TableLength(Tale_LogData)
        Tale:SaveVersion(Tale.ADDONVERSION, loglen+1)
    end
    Tale.queue = {}
    Tale.mobHitCache = {}
    Tale.state = STATE_IDLE
    Tale.groupMembers = 0
    Tale:OptionsInitialize()
end


-------------------------------------------------
--  Set registered Event according to options  --
-------------------------------------------------
function Tale:RegisterEvents(frame)
    frame:UnregisterAllEvents()
    if (Tale_Options.reputationChange) then frame:RegisterEvent("CHAT_MSG_SYSTEM"); end
    if (Tale_Options.levelUp or Tale_Options.levelUpLog) then frame:RegisterEvent("PLAYER_LEVEL_UP"); end
    if (Tale_Options.levelUpShowPlayed) then frame:RegisterEvent("TIME_PLAYED_MSG"); end
    if (Tale_Options.battlegroundEnding or Tale_Options.battlegroundEndingLog) then frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS"); end
    if (Tale_Options.deathLog or Tale_Options.killsLog) then 
	frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
    frame:RegisterEvent("PLAYER_ALIVE")
    frame:RegisterEvent("PLAYER_UNGHOST")
    if (Tale_Options.death or Tale_Options.deathLog) then frame:RegisterEvent("PLAYER_DEAD"); end
    frame:RegisterEvent("PLAYER_CONTROL_LOST")
    frame:RegisterEvent("PLAYER_CONTROL_GAINED")
    if (Tale_Options.questTurnInLog) then frame:RegisterEvent("QUEST_TURNED_IN"); end
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
end


--------------------------------------------------------
--  Create Frame for Events and ScreenshotScheduling  --
--------------------------------------------------------
TaleFrame = CreateFrame("Frame", "TaleFrame", UIParent, nil)
TaleFrame:SetScript("OnEvent", function (...) Tale:EventHandler(...) end)
TaleFrame:RegisterEvent("ADDON_LOADED")


-----------------------------------------
--  Functions for screenshot handling  --
-----------------------------------------
function Tale:ScreenshotHandler(elapsed)
    if Tale.state == STATE_IDLE then
        return
    elseif Tale.state == STATE_SHOT_SCHEDULED then
        local rmList = {}
        for i, delay in ipairs(Tale.queue) do
            if (delay > 0) then
                Tale.queue[i] = delay - elapsed
            else
                tinsert(rmList, i, 1)
                if Tale_Options.levelUpShowPlayed and Tale_Options.resizeChat then
                    Tale.state = STATE_SHOT_DELAY
                else
                    Tale.state = STATE_SCREENSHOT
                end
            end
        end
        for i, index in ipairs(rmList) do
            tremove(Tale.queue, index)
        end
    elseif Tale.state == STATE_SHOT_DELAY then
        -- Ensure chat window is big enough, need 1 frame setup before screenshot
        -- No matter resolution or UI scale, max size is 608x400
        DEFAULT_CHAT_FRAME:SetHeight(608)
        DEFAULT_CHAT_FRAME:SetWidth(400)
        Tale.state = STATE_SCREENSHOT
    elseif Tale.state == STATE_SCREENSHOT then
        Screenshot()
        if Tale_Options.levelUpShowPlayed and Tale_Options.resizeChat then
            -- Wait a frame to reset the chat, screenshot happens after frame ends
            Tale.state = STATE_RESTORE_DELAY
        else
            if (#Tale.queue == 0) then
                Tale.state = STATE_IDLE
            else
                Tale.state = STATE_SHOT_SCHEDULED
            end
        end
    elseif Tale.state == STATE_RESTORE_DELAY then
        DEFAULT_CHAT_FRAME:SetHeight(Tale.ChatSettings["height"])
        DEFAULT_CHAT_FRAME:SetWidth(Tale.ChatSettings["width"])
        if (#Tale.queue == 0) then
            Tale.state = STATE_IDLE
        else
            Tale.state = STATE_SHOT_SCHEDULED
        end
    end
end

function Tale:AddScheduledScreenshot(delay)
    tinsert(Tale.queue, delay);
    Tale.state = STATE_SHOT_SCHEDULED
    Tale.ChatSettings["height"] = DEFAULT_CHAT_FRAME:GetHeight()
    Tale.ChatSettings["width"] = DEFAULT_CHAT_FRAME:GetWidth()
end


-------------------------
--  Support functions  --
-------------------------
function Tale:GetPlayerTeam()
    local numBattlefieldScores = GetNumBattlefieldScores()
    local playerName = UnitName("player")
    for i = 1, numBattlefieldScores do
        local name, _, _, _, _, team = GetBattlefieldScore(i)
        if (playerName == team) then
            return team
        end
    end
end

function Tale:DebugMsg(text)
    if (Tale.Debug) then
        DEFAULT_CHAT_FRAME:AddMessage("Tale v."..Tale.ADDONVERSION.." Debug: "..text, 1, 0.5, 0);
    end
end

function Tale:ShowPrevious()
    local timePlayedPreviousLevel = Tale_CharLevelTimes[Tale.PlayerLevel - 1]
    if timePlayedPreviousLevel then
        local days, remainder  = Tale:DivMod(timePlayedPreviousLevel, 86400)
        local hours, remainder = Tale:DivMod(remainder, 3600)
        local minutes, seconds = Tale:DivMod(remainder, 60)
        local systemSettings = ChatTypeInfo["SYSTEM"]
        -- \124c Color Sequence Introducer then ARGB
        -- \124r Reset
        local red = bit.lshift(systemSettings.r * 255, 16)
        local green = bit.lshift(systemSettings.g * 255, 8)
        local color = bit.bor(red, green)
        color = bit.bor(color, systemSettings.b * 255)
        color = string.format("%x", color)
        DEFAULT_CHAT_FRAME:AddMessage("\124cFF"..color..Tale.L["time played"].." "..(Tale.PlayerLevel - 1)..": "..days.." "..Tale.L["days"]..", "..hours.." "..Tale.L["hours"]..", "..minutes.." "..Tale.L["minutes"]..", "..seconds.." "..Tale.L["seconds"])
    end
end

function Tale:DivMod(a, b)
    if (b == 0) then return 0, 0 end
    local div = math.floor(a / b)
    local mod = math.floor(math.fmod(a, b))
    return div, mod
end

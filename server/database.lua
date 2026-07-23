-- ====================================================================================
--  DATABASE MODULE: Table creation, stats queries, leaderboard, match history
-- ====================================================================================

-- 1. AUTO-CREATE TABLE ON STARTUP
CreateThread(function()
    -- We use pcall to safely try creating the table, just in case
    local success, result = pcall(function()
       -- MySQL.query.await([[DROP TABLE rts_player_stats]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS rts_player_stats (
                citizenid VARCHAR(50) NOT NULL,
                name VARCHAR(100), -- Added this line
                wins INT DEFAULT 0,
                losses INT DEFAULT 0,
                kills INT DEFAULT 0,
                units_destroyed INT DEFAULT 0,
                matches INT DEFAULT 0,
                total_damage BIGINT DEFAULT 0,
                score INT DEFAULT 0,
                PRIMARY KEY (citizenid)
            )
        ]])
        -- Add this inside the existing CreateThread function in server.lua
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS rts_match_history (
                id INT AUTO_INCREMENT PRIMARY KEY,
                match_uuid VARCHAR(50),
                citizenid VARCHAR(50),
                map_name VARCHAR(50),
                result VARCHAR(20), -- 'WIN' or 'LOSS'
                opponent_name VARCHAR(100),
                kills INT DEFAULT 0,
                score INT DEFAULT 0,
                date_played DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ]])
    end)
    
    if success then
        DebugPrint("^2[RTS DATABASE] Verified database tables.^7")
    else
        DebugPrint("^1[RTS DATABASE ERROR] Failed to connect to DB: " .. tostring(result) .. "^7")
    end
end)

-- [[ LIGHTWEIGHT LIVE STATS (Runs every 5s, no DB queries) ]] --
QBCore.Functions.CreateCallback('rts:getLiveMenuStats', function(source, cb)
    local ab = 0 
    for _ in pairs(Matches) do ab = ab + 1 end
    
    cb({ 
        onlineCount = GetNumPlayerIndices(), 
        activeBattles = ab, 
        ping = GetPlayerPing(source),
        estimatedWait = GetEstimatedWaitTime()
    })
end)
-- Add this near the bottom of server.lua
QBCore.Functions.CreateCallback('rts:getGlobalStats', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    
    -- 1. Default Data Structure (Safe Fallback)
    local defaultStats = {
        wins = 0,
        losses = 0,
        kills = 0,
        matches = 0,
        score = 0,
        name = GetPlayerName(source) or "Commander",
        levelData = { level = 1, currentXP = 0, requiredXP = 3000, percent = 0 }
    }

    if not Player then 
        print("^3[RTS] Stats: Player object not found, returning defaults.^7")
        return cb({ 
            onlineCount = GetNumPlayerIndices(), 
            activeBattles = 0, 
            myStats = defaultStats, 
            ping = GetPlayerPing(source) ,
            estimatedWait = GetEstimatedWaitTime() -- <--- ADD THIS LINE
        }) 
    end
    
    local citId = Player.PlayerData.citizenid
    
    -- 2. Database Fetch
    local success, dbStats = pcall(function()
        return MySQL.single.await('SELECT * FROM rts_player_stats WHERE citizenid = ?', {citId})
    end)

    -- 3. Merge DB Data
    if success and dbStats then
        defaultStats.wins = dbStats.wins or 0
        defaultStats.losses = dbStats.losses or 0
        defaultStats.kills = dbStats.kills or 0
        defaultStats.matches = dbStats.matches or 0
        defaultStats.score = dbStats.score or 0
        defaultStats.name = dbStats.name or Player.PlayerData.charinfo.firstname
    end
    
    -- 4. Calculate Level (Always run this to ensure levelData exists)
    local lvlInfo = CalculateLevel(defaultStats.score)
    defaultStats.levelData = lvlInfo 
    
    -- 5. Active Battles Count
    local activeBattles = 0
    if Matches then
        for _ in pairs(Matches) do activeBattles = activeBattles + 1 end
    end
    
    -- 6. Return Final Data
    cb({ 
        onlineCount = GetNumPlayerIndices(), 
        activeBattles = activeBattles, 
        myStats = defaultStats, -- Guaranteed to be populated
        ping = GetPlayerPing(source)
    })
end)

-- 1. LEADERBOARD CALLBACK
QBCore.Functions.CreateCallback('rts:getLeaderboard', function(source, cb)
    local result = MySQL.query.await('SELECT name, wins, kills, score FROM rts_player_stats ORDER BY score DESC LIMIT 10')
    
    -- Process levels for each row
    for _, row in ipairs(result) do
        local lvl = CalculateLevel(row.score)
        row.level = lvl.level
    end
    
    cb(result)
end)

-- 2. MATCH HISTORY CALLBACK
QBCore.Functions.CreateCallback('rts:getMatchHistory', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    
    local history = MySQL.query.await([[
        SELECT map_name, result, opponent_name, kills, score, date_played 
        FROM rts_match_history 
        WHERE citizenid = ? 
        ORDER BY date_played DESC 
        LIMIT 20
    ]], {Player.PlayerData.citizenid})
    
    cb(history)
end)

-- Level Calculator (Score -> Level Info)
function CalculateLevel(totalScore)
    local score = math.floor(totalScore or 0)
    local level = 1

    -- TARGETS:
    -- Level 1 -> 2 = 3000 XP
    -- Level 60 at ~1,000,000 total XP
    local xpForNext = 3000
    local xpCurve = 1.048

    while true do
        if score < xpForNext then
            return {
                level = level,
                currentXP = score,
                requiredXP = xpForNext,
                percent = math.floor((score / xpForNext) * 100)
            }
        end

        score = score - xpForNext
        level = level + 1
        xpForNext = math.floor(xpForNext * xpCurve)
    end
end

-- =============================================================================
--  DATABASE MODULE - Handles all MySQL operations
-- =============================================================================

local DB = {}

function DB.Initialize()
    local ok1 = pcall(MySQL.query.await, [[
        CREATE TABLE IF NOT EXISTS rts_player_stats (
            citizenid VARCHAR(50) NOT NULL,
            name VARCHAR(100),
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

    local ok2 = pcall(MySQL.query.await, [[
        CREATE TABLE IF NOT EXISTS rts_match_history (
            id INT AUTO_INCREMENT PRIMARY KEY,
            match_uuid VARCHAR(50),
            citizenid VARCHAR(50),
            map_name VARCHAR(50),
            result VARCHAR(20),
            opponent_name VARCHAR(100),
            kills INT DEFAULT 0,
            score INT DEFAULT 0,
            date_played DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ]])

    if ok1 and ok2 then
        print("^2[RTS DATABASE] Tables verified.^7")
    else
        print("^1[RTS DATABASE ERROR] Failed to create tables.^7")
    end
end

function DB.GetPlayerStats(citizenId)
    return MySQL.single.await('SELECT * FROM rts_player_stats WHERE citizenid = ?', { citizenId })
end

function DB.SavePlayerStats(citizenId, name, wins, losses, kills, matches, score)
    MySQL.query([[
        INSERT INTO rts_player_stats (citizenid, name, wins, losses, kills, units_destroyed, matches, score)
        VALUES (?, ?, ?, ?, ?, ?, 1, ?)
        ON DUPLICATE KEY UPDATE
            name = VALUES(name),
            wins = wins + VALUES(wins),
            losses = losses + VALUES(losses),
            kills = kills + VALUES(kills),
            matches = matches + 1,
            score = ?
    ]], { citizenId, name, wins, losses, kills, kills, score, score })
end

function DB.GetLeaderboard()
    return MySQL.query.await('SELECT name, wins, kills, score FROM rts_player_stats ORDER BY score DESC LIMIT 10')
end

function DB.GetMatchHistory(citizenId)
    return MySQL.query.await([[
        SELECT map_name, result, opponent_name, kills, score, date_played
        FROM rts_match_history
        WHERE citizenid = ?
        ORDER BY date_played DESC
        LIMIT 20
    ]], { citizenId })
end

function DB.SaveMatchHistory(matchId, citizenId, mapName, result, opponentName, kills, score)
    MySQL.insert([[
        INSERT INTO rts_match_history (match_uuid, citizenid, map_name, result, opponent_name, kills, score)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { matchId, citizenId, mapName, result, opponentName, kills, score })
end

CreateThread(function()
    DB.Initialize()
end)

return DB

-- =============================================================================
--  OBJECTIVES MODULE - Capture, victory conditions
-- =============================================================================

function StartObjectiveTick(matchId)
    CreateThread(function()
        local match = Matches[matchId]
        if not match then return end

        while match.active do
            Wait(1000)
            UpdateObjectives(matchId)

            local victoryResult = CheckVictoryConditions(matchId)
            if victoryResult then
                EndMatch(matchId, victoryResult)
                break
            end
        end
    end)
end

function UpdateObjectives(matchId)
    local match = Matches[matchId]
    if not match then return end

    local dirty = false

    for objName, obj in pairs(match.objectives) do
        local counts = { [1] = 0, [2] = 0 }

        for _, unit in pairs(match.units) do
            if unit.health > 0 then
                local dist = #(vector2(unit.position.x, unit.position.y) - vector2(obj.position.x, obj.position.y))
                if dist < obj.radius then
                    counts[unit.team] = counts[unit.team] + 1
                end
            end
        end

        local dominantTeam = 0
        if counts[1] > counts[2] then dominantTeam = 1
        elseif counts[2] > counts[1] then dominantTeam = 2
        end

        local capRate = obj.captureRate or 5.0
        local oldProgress = obj.progress
        local oldOwner = obj.controllingTeam
        local oldCapper = obj.capturingTeam

        if dominantTeam > 0 then
            if obj.controllingTeam == 0 then
                if obj.capturingTeam == 0 or obj.capturingTeam == dominantTeam then
                    obj.capturingTeam = dominantTeam
                    obj.progress = math.min(100, obj.progress + capRate)
                else
                    obj.progress = math.max(0, obj.progress - capRate)
                    if obj.progress == 0 then obj.capturingTeam = 0 end
                end

                if obj.progress >= 100 and obj.capturingTeam == dominantTeam then
                    obj.controllingTeam = dominantTeam
                        TriggerClientEvent('rts:objectiveCaptured', -1, { name = objName, team = dominantTeam, type = obj.type })
                        TriggerEvent('rts:objectiveCaptured', { matchId = matchId, objectiveName = objName, team = dominantTeam, type = obj.type })
                end
            elseif obj.controllingTeam == dominantTeam then
                obj.progress = math.min(100, obj.progress + capRate)
            else
                obj.progress = math.max(0, obj.progress - capRate)
                if obj.progress <= 0 then
                    obj.controllingTeam = 0
                    obj.capturingTeam = 0
                end
            end
        else
            if obj.controllingTeam == 0 and obj.progress > 0 then
                obj.progress = math.max(0, obj.progress - (capRate * 0.5))
                if obj.progress == 0 then obj.capturingTeam = 0 end
            end
        end

        if math.floor(oldProgress) ~= math.floor(obj.progress) or
            oldOwner ~= obj.controllingTeam or
            oldCapper ~= obj.capturingTeam then
            dirty = true
        end
    end

    if dirty then
        for playerId in pairs(match.players) do
            TriggerClientEvent('rts:updateObjectives', playerId, match.objectives)
        end
    end
end

function CheckVictoryConditions(matchId)
    local match = Matches[matchId]
    if not match then return nil end

    -- Grace period
    if (os.time() - match.startTime) < 60 then return nil end

    -- Capture win
    for _, obj in pairs(match.objectives) do
        if obj.type == "victory" and obj.progress >= 100 then
            return { type = "capture", winner = obj.controllingTeam }
        end
    end

    -- Elimination win (opt-in)
    if Config.MatchSettings.WinOnEliminations then
        local units = { [1] = 0, [2] = 0 }
        for _, u in pairs(match.units) do
            if u.health > 0 then
                units[u.team] = units[u.team] + 1
            end
        end

        if units[1] == 0 and units[2] > 0 then return { type = "elimination", winner = 2 } end
        if units[2] == 0 and units[1] > 0 then return { type = "elimination", winner = 1 } end
    end

    return nil
end

-- =============================================================================
--  NUI BRIDGE MODULE - All NUI callbacks connecting JS frontend to Lua backend
-- =============================================================================

-- Handler for server-to-client NUI notifications
RegisterNetEvent('rts:nuiNotify', function(data)
    SendNUIMessage({
        action = 'showNotification',
        message = data.message,
        type = data.type or 'info'
    })
end)

RegisterNUICallback('initialize', function(data, cb)
    SendNUIMessage({
        action = 'setUnitConfig',
        units = Config.Units,
        categories = Config.UnitCategories,
        maps = Config.Maps,
        keys = Config.Keys
    })
    cb({ success = true })
end)

RegisterNUICallback('requestLiveStats', function(data, cb)
    TriggerServerCallback('rts:getLiveMenuStats', function(stats)
        cb(stats)
    end)
end)

RegisterNUICallback('createLobby', function(data, cb)
    local mapName = data.map or "grapeseed"
    TriggerServerCallback('rts:createLobby', function(result)
        if result.success then
            GameState.isInLobby = true
            GameState.isHost = true
            GameState.lobbyCode = result.code
            local myName = GetPlayerName(PlayerId())
            local initialPlayers = { { name = myName, isReady = false, isHost = true } }
            SendNUIMessage({
                action = 'lobbyCreated',
                code = result.code,
                hostName = myName,
                map = mapName,
                weight = Config.Platoon.MaxWeight,
                isHost = true,
                playersData = initialPlayers
            })
        end
        cb(result)
    end, mapName)
end)

RegisterNUICallback('joinLobby', function(data, cb)
    local code = data.code:upper():gsub("%s+", "")
    TriggerServerCallback('rts:joinLobby', function(result)
        if result.success then
            GameState.isInLobby = true
            GameState.isHost = result.isHost
            GameState.lobbyCode = code
        end
        cb(result)
    end, code)
end)

RegisterNUICallback('leaveLobby', function(data, cb)
    TriggerServerEvent('rts:leaveLobby')
    GameState.isInLobby = false
    GameState.playerReady = false
    SendNUIMessage({ action = 'returnToMenu' })
    cb({ success = true })
end)

RegisterNUICallback('readyToggle', function(data, cb)
    GameState.playerReady = data.ready
    TriggerServerEvent('rts:setReady', GameState.playerReady)
    SendNUIMessage({ action = 'updateReadyStatus', ready = GameState.playerReady })
    cb({ success = true })
end)

RegisterNUICallback('savePlatoons', function(data, cb)
    if data.platoons then
        GameState.platoons = data.platoons
        TriggerServerEvent('rts:savePlatoons', GameState.platoons)
    end
    cb({ success = true })
end)

RegisterNUICallback('spawnPlatoon', function(data, cb)
    if not GameState.isInMatch then
        cb({ success = false, message = "Not in match" })
        return
    end

    local status, worldPos = pcall(ScreenToWorldPosition, data.x, data.y)
    if not status then
        cb({ success = false })
        return
    end

    if worldPos then
        TriggerServerEvent('rts:spawnPlatoon', data.platoonIndex, worldPos)
        cb({ success = true })
    else
        cb({ success = false, message = "Invalid location" })
    end
end)

RegisterNUICallback('surrenderMatch', function(data, cb)
    TriggerServerEvent('rts:surrenderMatch')
    cb({ success = true })
end)

RegisterNUICallback('selectUnit', function(data, cb)
    if data.unitId then
        DeselectAllUnits()
        table.insert(GameState.selectedUnits, data.unitId)
        UpdateSelectionUI()
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
    cb({ success = true })
end)

RegisterNUICallback('selectUnits', function(data, cb)
    local screenW, screenH = GetActiveScreenResolution()
    DeselectAllUnits()

    local selMinX = math.min(data.x1, data.x2) * screenW
    local selMaxX = math.max(data.x1, data.x2) * screenW
    local selMinY = math.min(data.y1, data.y2) * screenH
    local selMaxY = math.max(data.y1, data.y2) * screenH

    for unitId, unit in pairs(GameState.units) do
        if unit and unit.entity and DoesEntityExist(unit.entity) and GetEntityHealth(unit.entity) > 0 then
            local pos = GetEntityCoords(unit.entity)
            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
            if onScreen then
                local unitPixelX = screenX * screenW
                local unitPixelY = screenY * screenH
                local pixelRadius = 35

                if IsEntityAVehicle(unit.entity) then
                    local minDim, maxDim = GetModelDimensions(GetEntityModel(unit.entity))
                    local size = math.max(math.abs(maxDim.x - minDim.x), math.abs(maxDim.y - minDim.y))
                    local _, edgeX = GetScreenCoordFromWorldCoord(pos.x + (size * 0.6), pos.y, pos.z)
                    pixelRadius = math.abs((edgeX * screenW) - unitPixelX)
                end
                if pixelRadius < 35 then pixelRadius = 35 end

                local isOverlapping = (selMinX < (unitPixelX + pixelRadius)) and (selMaxX > (unitPixelX - pixelRadius))
                    and (selMinY < (unitPixelY + pixelRadius)) and (selMaxY > (unitPixelY - pixelRadius))

                if isOverlapping then
                    table.insert(GameState.selectedUnits, unitId)
                end
            end
        end
    end

    UpdateSelectionUI()
    cb({ success = true, count = #GameState.selectedUnits })
end)

RegisterNUICallback('issueCommand', function(data, cb)
    cb({ success = true })

    -- AIRSTRIKE PRIORITY INTERCEPT
    if GameState.pendingAirstrikes and #GameState.pendingAirstrikes > 0 then
        if data.type == 'attack' then
            local targetEntity = nil
            if GameState.enemyUnits[data.targetId] then
                targetEntity = GameState.enemyUnits[data.targetId].entity
            elseif GameState.units[data.targetId] then
                targetEntity = GameState.units[data.targetId].entity
            end

            if targetEntity then
                for _, jetData in pairs(GameState.pendingAirstrikes) do
                    if jetData.active and DoesEntityExist(jetData.entity) then
                        SetEntityInvincible(jetData.entity, true)
                        SetEntityCollision(jetData.entity, true, true)
                        ExecuteLazarStrike(jetData.entity, targetEntity)
                    end
                end
                GameState.pendingAirstrikes = {}
                SendNUIMessage({ action = 'stopAirstrikeTimer' })
                return
            end
        end
    end

    if #GameState.selectedUnits == 0 then return end

    if data.type == 'move' then
        local targetPos = GetWorldCoordFromScreen(data.x, data.y)
        if targetPos then
            PlaySoundFrontend(-1, Config.Sounds.CommandMove, 0, true)
            DrawTargetMarker(targetPos)
            lastOrderTime = 0
            for _, unitId in ipairs(GameState.selectedUnits) do
                local unit = GameState.units[unitId]
                if unit and DoesEntityExist(unit.entity) then
                    if IsEntityAVehicle(unit.entity) then
                        local vehicle = unit.entity
                        local driver = GetPedInVehicleSeat(vehicle, -1)
                        FixEngineAndSecurePed(vehicle, driver)
                        if driver and DoesEntityExist(driver) and not IsPedDeadOrDying(driver, true) then
                            ClearPedTasks(driver)
                            SetVehicleEngineOn(vehicle, true, true, false)
                            PlayObeyMove(driver)
                            TaskVehicleDriveToCoord(driver, vehicle, targetPos.x, targetPos.y, targetPos.z, 30.0, 0, GetEntityModel(vehicle), 4981292, 5.0, true)
                        end
                    else
                        ClearPedTasks(unit.entity)
                        PlayObeyMove(unit.entity)
                        CommandPedToMarch(unit.entity, targetPos.x, targetPos.y, targetPos.z)
                    end
                end
            end
        end

    elseif data.type == 'attack' then
        local targetId = data.targetId
        local targetEntity = nil
        if GameState.units[targetId] then targetEntity = GameState.units[targetId].entity end
        if GameState.enemyUnits[targetId] then targetEntity = GameState.enemyUnits[targetId].entity end

        if targetEntity and DoesEntityExist(targetEntity) then
            PlaySoundFrontend(-1, Config.Sounds.CommandAttack, 0, true)

            if IsEntityAVehicle(targetEntity) then
                local enemyDriver = GetPedInVehicleSeat(targetEntity, -1)
                if enemyDriver ~= 0 and not IsPedDeadOrDying(enemyDriver, true) then
                    targetEntity = enemyDriver
                end
            end

            for _, unitId in ipairs(GameState.selectedUnits) do
                local unit = GameState.units[unitId]
                if unit and DoesEntityExist(unit.entity) then
                    if IsEntityAVehicle(unit.entity) then
                        local vehicle = unit.entity
                        local driver = GetPedInVehicleSeat(vehicle, -1)
                        FixEngineAndSecurePed(vehicle, driver)
                        if driver and DoesEntityExist(driver) then
                            ForceGroundCombat(unit.entity)
                            PlayObeyAttack(driver)
                            TaskCombatPed(driver, targetEntity, 0, 16)
                        end

                        local seats = GetVehicleMaxNumberOfPassengers(unit.entity)
                        for i = 0, seats - 1 do
                            local p = GetPedInVehicleSeat(unit.entity, i)
                            if p and DoesEntityExist(p) then
                                TaskCombatPed(p, targetEntity, 0, 16)
                            end
                        end
                    else
                        PlayObeyAttack(unit.entity)
                        TaskCombatPed(unit.entity, targetEntity, 0, 16)
                    end
                end
            end
        end
    end
end)

RegisterNUICallback('cameraZoom', function(data, cb)
    if GameState.isInMatch then
        if data.direction == 'in' then
            GameState.cameraHeight = math.max(Config.MatchSettings.CameraMinHeight, GameState.cameraHeight - 5.0)
        else
            GameState.cameraHeight = math.min(Config.MatchSettings.CameraMaxHeight, GameState.cameraHeight + 5.0)
        end
    end
    cb({ success = true })
end)

RegisterNUICallback('selectPlatoonGroup', function(data, cb)
    DeselectAllUnits()
    if data.uuid then
        for unitId, unit in pairs(GameState.units) do
            if unit.uuid == data.uuid and unit.entity and DoesEntityExist(unit.entity) then
                table.insert(GameState.selectedUnits, unitId)
            end
        end
        UpdateSelectionUI()
    end
    cb({ success = true })
end)

-- =============================================================================
--  LEADERBOARD / HISTORY CALLBACKS
-- =============================================================================

RegisterNUICallback('getLeaderboard', function(data, cb)
    TriggerServerCallback('rts:getLeaderboard', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('getHistory', function(data, cb)
    TriggerServerCallback('rts:getMatchHistory', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('getServerPlayerCount', function(data, cb)
    TriggerServerCallback('rts:getServerPlayerCount', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('getGlobalStats', function(data, cb)
    TriggerServerCallback('rts:getGlobalStats', function(result)
        cb(result)
    end)
end)

-- =============================================================================
--  MATCHMAKING CALLBACKS
-- =============================================================================

RegisterNUICallback('joinMatchmaking', function(data, cb)
    TriggerServerEvent('rts:joinMatchmaking')
    cb({ success = true })
end)

RegisterNUICallback('leaveMatchmaking', function(data, cb)
    TriggerServerEvent('rts:leaveMatchmaking')
    cb({ success = true })
end)

RegisterNUICallback('startAiMatch', function(data, cb)
    TriggerServerEvent('rts:startAiMatchFromQueue')
    cb({ success = true })
end)

RegisterNUICallback('disconnectPlayer', function(data, cb)
    TriggerServerEvent('rts:disconnectPlayer')
    cb({ success = true })
end)

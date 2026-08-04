RegisterNetEvent('rts:nuiNotify', function(data)
    SendNUIMessage({ action = 'showNotification', message = data.message, type = data.type or 'info' })
end)

RegisterNUICallback('requestLiveStats', function(data, cb)
    RTS.TriggerCallback('rts:getLiveMenuStats', function(stats)
        cb(stats)
    end)
end)


-- Init
RegisterNUICallback('initialize', function(data, cb)
    NUIReady = true
    DebugPrint("NUI Initialized")
    
    SendNUIMessage({
        action = 'setUnitConfig',
        units = Config.Units,
        categories = Config.UnitCategories,
        maps = Config.Maps,
        keys = Config.Keys 
    })

    cb({ success = true, version = Config.Version })
end)

RegisterNUICallback('createLobby', function(data, cb)
    local mapName = data.map or "grapeseed"
    
    RTS.TriggerCallback('rts:createLobby', function(result)
        if result.success then
            GameState.isInLobby = true
            GameState.isHost = true
            GameState.lobbyCode = result.code
            
            local myName = result.hostName or GetPlayerName(PlayerId())
            local initialPlayers = {
                { name = myName, isReady = false, isHost = true }
            }

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
    
    RTS.TriggerCallback('rts:joinLobby', function(result)
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
    SendNUIMessage({action = 'showNotification', message = "Left lobby", type = "info"})
    cb({ success = true })
end)

RegisterNUICallback('readyToggle', function(data, cb) 
    
    GameState.playerReady = data.ready
    
    TriggerServerEvent('rts:setReady', GameState.playerReady) 
    SendNUIMessage({ action = 'updateReadyStatus', ready = GameState.playerReady }) 
    cb({ success = true }) 
end)

RegisterNetEvent('rts:abortCountdown', function()
    
    SendNUIMessage({ action = 'abortCountdown' })
end)

RegisterNUICallback('savePlatoons', function(data, cb)
    if data.platoons then
        GameState.platoons = data.platoons
        TriggerServerEvent('rts:savePlatoons', GameState.platoons)
        SendNUIMessage({action = 'showNotification', message = "Platoons saved", type = "success"})
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
        DebugPrint("^1[RTS ERROR]^7 Math Calculation Failed: " .. tostring(worldPos))
        cb({ success = false })
        return
    end
    
    DebugPrint("Spawning platoon " .. tostring(data.platoonIndex) .. " at " .. tostring(worldPos))

    if worldPos then
        TriggerServerEvent('rts:spawnPlatoon', data.platoonIndex, worldPos)
        cb({ success = true })
    else
        cb({ success = false, message = "Invalid location" })
    end
end)

RegisterNUICallback('issueCommand', function(data, cb)
    cb({ success = true })
    
    if GameState.pendingAirstrikes and #GameState.pendingAirstrikes > 0 then
        if data.type == 'attack' then
            local targetEntity = nil
            
            if GameState.enemyUnits[data.targetId] then 
                targetEntity = GameState.enemyUnits[data.targetId].entity 
            elseif GameState.units[data.targetId] then
                targetEntity = GameState.units[data.targetId].entity
            end
            
            if targetEntity then
                
                for id1, jetData1 in pairs(GameState.pendingAirstrikes) do
                    if jetData1.active and DoesEntityExist(jetData1.entity) then
                        SetEntityInvincible(jetData1.entity, true)
                         SetEntityCollision(jetData1.entity, true, true) 

                        for id2, jetData2 in pairs(GameState.pendingAirstrikes) do
                            
                            if id1 ~= id2 and jetData2.active and DoesEntityExist(jetData2.entity) then
                                
                                SetEntityNoCollisionEntity(jetData1.entity, jetData2.entity, true)
                            end
                        end
                    
                        ExecuteLazarStrike(jetData1.entity, targetEntity)
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
            DebugPrint("^3[RTS MOVE] Ordering " .. #GameState.selectedUnits .. " units to: " .. targetPos.x .. ", " .. targetPos.y .. "^7")
            lastOrderTime = 0
            for _, unitId in ipairs(GameState.selectedUnits) do
                local unit = GameState.units[unitId]
                if unit and DoesEntityExist(unit.entity) then

                    if IsEntityAVehicle(unit.entity) then
                        local vehicle = unit.entity
                        local driver = GetPedInVehicleSeat(vehicle, -1)
                        
                        if GetEntityModel(vehicle) == GetHashKey("chernobog") then

                            SetTrailerLegsRaised(vehicle)
                            
                            SetVehicleLandingGear(vehicle, 1) 
                            
                            SetVehicleHandbrake(vehicle, false)
                            
                            Wait(100)
                        end
                        FixEngineAndSecurePed(vehicle, driver)
                        if driver and DoesEntityExist(driver) and not IsPedDeadOrDying(driver, true) then
                            ClearPedTasks(driver)
                            SetVehicleEngineOn(vehicle, true, true, false)
                            PlayObeyMove(driver)
                            
                            DisablePedReactions(driver, 5000)
                            TaskVehicleDriveToCoord(driver, vehicle, targetPos.x, targetPos.y, targetPos.z, 30.0, 0, GetEntityModel(vehicle), 4981292, 5.0, true)
                        end
                    
                    else
                        ClearPedTasks(unit.entity)
                        DisablePedReactions(unit.entity, 5000)
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
                        local driver = GetPedInVehicleSeat(unit.entity, -1)
                        FixEngineAndSecurePed(unit.entity, driver)
                        
                        if GetEntityModel(vehicle) == GetHashKey("chernobog") then
                            SetTrailerLegsLowered(vehicle)

                            SetVehicleLandingGear(vehicle, 0)
                            
                            TaskVehicleTempAction(driver, vehicle, 27, -1) 
                            SetVehicleHandbrake(vehicle, true)
                            
                        else
                            
                            if driver and DoesEntityExist(driver) then
                                ForceGroundCombat(unit.entity)
                                Wait(0)
                                PlayObeyAttack(driver)
                                TaskCombatPed(driver, targetEntity, 0, 16)
                               
                            end 
                        end
                        
                        local seats = GetVehicleMaxNumberOfPassengers(unit.entity)
                        for i = 0, seats - 1 do
                            local p = GetPedInVehicleSeat(unit.entity, i)
                            if p and DoesEntityExist(p) then
                                TaskCombatPed(p, targetEntity, 0, 16)
                            end
                        end
                        if carTrailer and carTrailer[unit.entity] then
                          
                            local trailerGuy = GetPedInVehicleSeat(carTrailer[unit.entity], -1)
                            TaskCombatPed(trailerGuy, targetEntity, 0, 16)
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

RegisterNUICallback('selectUnits', function(data, cb)
    
    local screenW, screenH = GetActiveScreenResolution()
    local selectedCount = 0
    
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
                
                local worldRadius = 1.2 
                if IsEntityAVehicle(unit.entity) then
                    local min, max = GetModelDimensions(GetEntityModel(unit.entity))
                    
                    local size = math.max(math.abs(max.x - min.x), math.abs(max.y - min.y))
                    worldRadius = size * 0.6
                end

                local _, edgeX, edgeY = GetScreenCoordFromWorldCoord(pos.x + worldRadius, pos.y, pos.z)
                local edgePixelX = edgeX * screenW
                local edgePixelY = edgeY * screenH
                
                local pixelRadius = math.sqrt((unitPixelX - edgePixelX)^2 + (unitPixelY - edgePixelY)^2)
                
                if pixelRadius < 35 then pixelRadius = 35 end

                local unitMinX = unitPixelX - pixelRadius
                local unitMaxX = unitPixelX + pixelRadius
                local unitMinY = unitPixelY - pixelRadius
                local unitMaxY = unitPixelY + pixelRadius

                local isOverlapping = (selMinX < unitMaxX) and (selMaxX > unitMinX) and
                                      (selMinY < unitMaxY) and (selMaxY > unitMinY)

                if isOverlapping then
                    table.insert(GameState.selectedUnits, unitId)
                    selectedCount = selectedCount + 1
                end
            end
        end
    end
    if selectedCount > 0 then
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
    
    UpdateSelectionUI()
    cb({ success = true, count = selectedCount })
end)

RegisterNUICallback('selectUnit', function(data, cb)
    cb({ success = true }) 

    local unitId = data.unitId
    if unitId and GameState.units[unitId] then
        
        if not IsDisabledControlPressed(0, 21) then 
            DeselectAllUnits()
        end
        
        table.insert(GameState.selectedUnits, unitId)
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        UpdateSelectionUI()
    end
end)

RegisterNUICallback('cameraZoom', function(data, cb)
    if not GameState.camera then return cb('ok') end
    
    local zoomStep = 10.0 
    
    if data.direction == 'in' then
        GameState.cameraHeight = GameState.cameraHeight - zoomStep
    else
        GameState.cameraHeight = GameState.cameraHeight + zoomStep
    end
    
    cb('ok')
end)

RegisterNUICallback('selectPlatoonGroup', function(data, cb)
    local uuid = tonumber(data.uuid) 
    
    DebugPrint("[RTS DEBUG] Selecting Platoon Group ID: " .. tostring(uuid))

    DeselectAllUnits()
    
    local found = false
    if GameState.deployedPlatoons then
        for _, p in ipairs(GameState.deployedPlatoons) do
            if p.id == uuid then
                found = true
                for _, uid in ipairs(p.unitIds) do
                    local u = GameState.units[uid]
                    
                    if u and DoesEntityExist(u.entity) and not IsEntityDead(u.entity) then
                        table.insert(GameState.selectedUnits, uid)
                    end
                end
                break
            end
        end
    end
    
    UpdateSelectionUI()
    
    if found then
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    else
        DebugPrint("[RTS DEBUG] Platoon ID not found in local gamestate")
    end

    cb('ok')
end)

RegisterNUICallback('surrenderMatch', function(data, cb)
    TriggerServerEvent('rts:surrenderMatch')
    cb({ success = true })
end)

RegisterNUICallback('close', function(data, cb)
    TriggerServerEvent('rts:disconnectPlayer')
    cb('ok')
end)

RegisterNUICallback('getLeaderboard', function(data, cb)
    RTS.TriggerCallback('rts:getLeaderboard', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('getHistory', function(data, cb)
    RTS.TriggerCallback('rts:getMatchHistory', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('getServerPlayerCount', function(data, cb)
    RTS.TriggerCallback('rts:getServerPlayerCount', function(count)
        cb({ count = count })
    end)
end)

RegisterNUICallback('getGlobalStats', function(data, cb)
    RTS.TriggerCallback('rts:getGlobalStats', function(stats)
        cb(stats)
    end)
end)

RegisterNUICallback('joinQueue', function(data, cb)
    RTS.TriggerCallback('rts:getServerPlayerCount', function(count)
        TriggerServerEvent('rts:joinMatchmaking')
        
        cb({ success = true, playerCount = count })
    end)
end)

RegisterNUICallback('startAiMatchFromQueue', function(data, cb)
    TriggerServerEvent('rts:startAiMatchFromQueue')
    cb({ success = true })
end)

RegisterNUICallback('leaveQueue', function(data, cb)
    TriggerServerEvent('rts:leaveMatchmaking')
    cb({ success = true })
end)

RegisterNUICallback('joinMatchmaking', function(data, cb)
    TriggerServerEvent('rts:joinMatchmaking')
    cb({ success = true })
end)

RegisterNUICallback('leaveMatchmaking', function(data, cb)
    TriggerServerEvent('rts:leaveMatchmaking')
    cb({ success = true })
end)

RegisterNUICallback('disconnectPlayer', function(data, cb)
    TriggerServerEvent('rts:disconnectPlayer')
    cb('ok')
end)

RegisterNUICallback('adminConfirmForceStart', function(data, cb)
    TriggerServerEvent('rts:server:executeForceStart')
    cb('ok')
end)

RegisterNUICallback('toggleAdminMode', function(data, cb)
    cb('ok')
end)

RegisterNUICallback('addBot', function(data, cb) TriggerServerEvent('rts:server:toggleBot', 'add'); cb('ok') end)
RegisterNUICallback('kickBot', function(data, cb) TriggerServerEvent('rts:server:toggleBot', 'kick'); cb('ok') end)


-- Chat
RegisterNUICallback('chatTyping', function(data, cb)
    if GameState and GameState.isInMatch then
        SetNuiFocusKeepInput(not data.typing)
    end
    cb('ok')
end)

RegisterNUICallback('sendChatMessage', function(data, cb)
    if data.message and data.message ~= "" then
        TriggerServerEvent('rts:server:sendChatMessage', data.message)
    end
    cb('ok')
end)


-- Events
RegisterNetEvent('rts:updateLobby')
AddEventHandler('rts:updateLobby', function(data)
    SendNUIMessage({
        action = 'updateLobby',
        lobbyCode = data.lobbyCode,
        playersData = data.playersData, 
        
        players = data.players,
        playerNames = data.playerNames,
        hostName = data.hostName,
        map = data.map,
        status = data.status
    })
end)

RegisterNetEvent('rts:playerLeft')
AddEventHandler('rts:playerLeft', function(playerName)
    SendNUIMessage({
        action = 'playerLeft',
        playerName = playerName
    })
end)

RegisterNetEvent('rts:playerReadyUpdate')
AddEventHandler('rts:playerReadyUpdate', function(data)
    SendNUIMessage({
        action = 'playerReadyUpdate',
        playerId = data.playerId,
        ready = data.ready,
        playerName = data.playerName
    })
end)

RegisterNetEvent('rts:startCountdown')
AddEventHandler('rts:startCountdown', function(duration)
    SendNUIMessage({
        action = 'startCountdown',
        duration = duration
    })
end)

RegisterNetEvent('rts:startMatch', function(data)
    DebugPrint("^2[RTS DEBUG] === START MATCH EVENT RECEIVED ===^7")
    
    if not data then 
        DebugPrint("^1[RTS ERROR] No data received in startMatch!^7")
        return 
    end
    DebugPrint("^2[RTS DEBUG] Team: " .. tostring(data.team) .. " | Map: " .. tostring(data.map) .. "^7")

    local map = Config.Maps[data.map]
    if not map then
        DebugPrint("^1[RTS ERROR] Map Config missing for: " .. tostring(data.map) .. "^7")
        
        map = { name = "Unknown", center = vector3(0,0,0), range = 500.0 }
    end

    GameState.currentMap = data.map
    if not Config.Maps[GameState.currentMap] then
        DebugPrint("^1[RTS ERROR] Invalid Map Name: " .. tostring(GameState.currentMap) .. "^7")
        
        GameState.currentMap = "grapeseed" 
    end

    GameState.isInMatch = true
    GameState.matchId = data.matchId
    GameState.team = data.team
    GameState.commandPoints = Config.MatchSettings.CommandPointsStart or 1500
    GameState.platoons = data.platoons or {}
    GameState.units = {} 
    GameState.cameraHeight = (Config.MatchSettings.CameraDefaultHeight + Config.Maps[GameState.currentMap].center.z) or  40.0 
    
    DebugPrint("^2[RTS DEBUG] Starting Hitbox Tracker...^7")
    StartHitboxTracker()
   
    local ped = PlayerPedId()
    local pos = data.spawnPos
    if type(pos) == 'table' then pos = vector3(pos.x, pos.y, pos.z) end
    
    SetEntityCoords(ped, pos.x, pos.y, pos.z + 10.0, false, false, false, false)
 
    DebugPrint("^2[RTS DEBUG] Initializing Camera...^7")
    InitializeCamera(pos)
    
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    
    SendNUIMessage({
        action = 'startMatch',
        team = data.team,
        music  = map.music or "main_theme.mp3",
        commandPoints = GameState.commandPoints,
        platoons = GameState.platoons
    })
    
    StartMatchLoop()
    
    DebugPrint("^2[RTS DEBUG] Match Initialization Complete.^7")
    Citizen.CreateThread(function()
        while GameState.isInMatch do
            Wait(0)  
            DisplayRadar(true)
        end
    end)
    
    pcall(function()
        PlaySoundFrontend(-1, "Beep_Green", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
        SendNUIMessage({action = 'showNotification', message = "Match Started!", type = "success"})
        StartSelectionRenderer()
        StartObjectiveSystem()
        StartFogOfWarSystem()
        SpawnMapDecorations(GameState.currentMap)
        if GetResourceState('rts-weapons') == 'started' then
            exports['rts-weapons']:ApplyWeaponModifiers()
        end
   
        WreckScanner(map.center, map.range)
        ApplyMapEnvironment()
        
        if data.isCpuMatch then StartCpuBotBrain(data.platoons, data.botId, data.playerLevel) else CpuBot = { active = false, commandPoints = 1500, cooldowns = {0,0,0,0,0}, platoons = {}, lastThink = 0, targetPlatoon = nil }
 end
    end)
end)

RegisterNetEvent('rts:spawnUnit')
AddEventHandler('rts:spawnUnit', function(data)
    SpawnUnit(data)
    
    SendNUIMessage({
        action = 'unitSpawned',
        unitId = data.unitId,
        unitType = data.unitType
    })
end)

RegisterNetEvent('rts:spawnEnemyUnit')
AddEventHandler('rts:spawnEnemyUnit', function(data)
    
    local entity = nil
    local timeout = 0
    
    CreateThread(function()
        while not NetworkDoesEntityExistWithNetworkId(data.netId) and timeout < 50 do
            Wait(100)
            SetFocusPosAndVel(data.position.x, data.position.y, data.position.z, 0.0, 0.0, 0.0)
            timeout = timeout + 1
        end
        
        if NetworkDoesEntityExistWithNetworkId(data.netId) then
            entity = NetworkGetEntityFromNetworkId(data.netId)
            
            GameState.enemyUnits[data.unitId] = {
                id = data.unitId,
                team = data.team,
                type = data.type,
                entity = entity, 
                netId = data.netId,
                blip = CreateUnitBlip(entity, data.team, Config.Units[data.type].category, Config.Units[data.type].blip or nil, true)
            }
            if IsEntityAPed(entity) then
                SetEntityMaxHealth(entity, data.health or 1000)
                SetEntityHealth(entity, data.health or 1000)
            else
                SetEntityMaxHealth(entity, data.health or 1000)
                SetEntityHealth(entity, data.health or 1000)
                SetVehicleBodyHealth(entity, data.health + 0.0)
            end
            local newPos = GetEntityCoords(entity)
            SetFocusPosAndVel(newPos.x, newPos.y, newPos.z, 0.0, 0.0, 0.0)
            DebugPrint("Registered Enemy Unit: " .. data.unitId .. " (NetID: " .. data.netId .. ")")
        end
    end)
end)

RegisterNetEvent('rts:spawnEnemyUnitDriver')
AddEventHandler('rts:spawnEnemyUnitDriver', function(data)
    
    local entity = nil
    local timeout = 0
    
    CreateThread(function()
        while not NetworkDoesEntityExistWithNetworkId(data.netId) and timeout < 50 do
            Wait(100)
            timeout = timeout + 1
        end
        
        if NetworkDoesEntityExistWithNetworkId(data.netId) then
            entity = NetworkGetEntityFromNetworkId(data.netId)
            local newPos = GetEntityCoords(entity)
            SetFocusPosAndVel(newPos.x, newPos.y, newPos.z, 0.0, 0.0, 0.0)

            DebugPrint("Registered Enemy Unit Driver: " .. data.unitId .. " (NetID: " .. data.netId .. ")")
        end
    end)
end)

RegisterNetEvent('rts:unitDestroyed')
AddEventHandler('rts:unitDestroyed', function(unitId)
    local unit = GameState.units[unitId]
    if unit then
        if unit.entity and DoesEntityExist(unit.entity) then
            
            local pos = GetEntityCoords(unit.entity)
            if IsEntityAVehicle(unit.entity) then
            AddExplosion(pos.x, pos.y, pos.z, 1, 1.0, true, false, 1.0)
            end
           
            PlaySoundFrontend(-1, Config.Sounds.UnitDestroyed, "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
        end
        
        for i, selectedId in ipairs(GameState.selectedUnits) do
            if selectedId == unitId then
                table.remove(GameState.selectedUnits, i)
                break
            end
        end
        
        GameState.units[unitId] = nil
        GameState.unitCount = GameState.unitCount - 1
        
        UpdateSelectionUI()
    end
end)

RegisterNetEvent('rts:unitDestroyed', function(unitId)
    local unit = GameState.units[unitId]
    if unit then
        
        if unit.blip and DoesBlipExist(unit.blip) then
            RemoveBlip(unit.blip)
        end
        
        for i, selectedId in ipairs(GameState.selectedUnits) do
            if selectedId == unitId then
                table.remove(GameState.selectedUnits, i)
                UpdateSelectionUI()
                break
            end
        end
        
        GameState.units[unitId] = nil
        
        DebugPrint("^1[RTS] Friendly Unit " .. unitId .. " Removed.^7")
    end
end)

RegisterNetEvent('rts:enemyUnitDestroyed', function(unitId)
    local unit = GameState.enemyUnits[unitId]
    if unit then
        
        if unit.blip and DoesBlipExist(unit.blip) then
            RemoveBlip(unit.blip)
        end
        
        GameState.enemyUnits[unitId] = nil
        
        DebugPrint("^1[RTS] Enemy Unit " .. unitId .. " Removed.^7")
    end
end)

RegisterNetEvent('rts:updateResources')
AddEventHandler('rts:updateResources', function(data)
    GameState.commandPoints = data.commandPoints
    GameState.incomeRate = data.incomeRate
    UpdateResourcesUI()
end)

RegisterNetEvent('rts:updatePlatoonCooldown')
AddEventHandler('rts:updatePlatoonCooldown', function(platoonIndex, cooldown)
    GameState.platoonCooldowns[platoonIndex] = cooldown
    SendNUIMessage({
        action = 'updatePlatoonCooldown',
        index = platoonIndex,
        cooldown = cooldown
    })
end)

RegisterNetEvent('rts:updateCaptureProgress')
AddEventHandler('rts:updateCaptureProgress', function(data)
    
    GameState.captureProgress = data.progress
    GameState.capturingTeam = data.capturingTeam
    GameState.controllingTeam = data.controllingTeam
    
    if data.objective and GameState.objectives and GameState.objectives[data.objective] then
        local obj = GameState.objectives[data.objective]
        
        obj.progress = data.progress
        obj.capturingTeam = data.capturingTeam
        obj.controllingTeam = data.controllingTeam

        if data.progress <= 0 then
             obj.capturingTeam = 0
        end
        
        UpdateObjectiveBlips()
    end
    
    SendNUIMessage({
        action = 'updateCapture',
        progress = data.progress,
        capturingTeam = data.capturingTeam,
        controllingTeam = data.controllingTeam,
        objective = data.objective
    })
end)

RegisterNetEvent('rts:objectiveCaptured')
AddEventHandler('rts:objectiveCaptured', function(data)
    SendNUIMessage({
        action = 'objectiveCaptured',
        name = data.name,
        team = data.team,
        type = data.type
    })
    
    if GameState.objectives and GameState.objectives[data.name] then
        GameState.objectives[data.name].controllingTeam = data.team
        GameState.objectives[data.name].capturingTeam = 0 
        GameState.objectives[data.name].progress = 0
        
        UpdateObjectiveBlips()
    end
    
    if CpuBot and CpuBot.active and data.type ~= "victory" then
        if data.team == 2 then
            TriggerBotChat(CpuBot.botId, CpuBot.botName, "obj_win")
        elseif data.team == 1 then
            TriggerBotChat(CpuBot.botId, CpuBot.botName, "obj_lose")
        end
    end

    if data.team == GameState.team then
        SendNUIMessage({action = 'showNotification', message = "Objective captured: " .. data.name, type = "success"})
    else
        SendNUIMessage({action = 'showNotification', message = "Objective lost: " .. data.name, type = "error"})
    end
end)

RegisterNetEvent('rts:updateMatchTimer')
AddEventHandler('rts:updateMatchTimer', function(timeLeft)
    GameState.matchTime = Config.MatchSettings.MatchDuration - timeLeft
    UpdateTimerUI()
end)

RegisterNetEvent('rts:endMatch')
AddEventHandler('rts:endMatch', function(result)
    CleanupMatch()
    
    local k = result.stats and result.stats.kills or 0
    DebugPrint("^2[RTS DEBUG] END MATCH RECEIVED. KILLS: " .. tostring(k) .. "^7")
    
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false) 

    SendNUIMessage({
        action = 'endMatch',
        victory = result.victory,
        reason = result.reason,
        score = result.score,
        showCash = result.cashRewards,
        cashAmount = result.cashAmount,
        rewards = result.rewards,
        stats = result.stats,
        matchData = result.matchData,
        
        levelData = result.levelData 
    })
    
    PlaySoundFrontend(-1, Config.Sounds.MatchEnd, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    
    if result.victory then
        SendNUIMessage({action = 'showNotification', message = "VICTORY! " .. (result.reason or ""):upper(), type = "success"})
    else
        SendNUIMessage({action = 'showNotification', message = "DEFEAT! " .. (result.reason or ""):upper(), type = "error"})
    end

    if result.cashRewards then
        local amount = result.cashAmount
        TriggerServerEvent("enyo-rts:giveMoney", amount)
    end

    if GameState and GameState.objectiveBlips then
        for name, blip in pairs(GameState.objectiveBlips) do
            
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end
    end
    GameState.objectiveBlips = {} 
    
     FullPlayerReset()

end)

RegisterNetEvent('rts:resetUI')
AddEventHandler('rts:resetUI', function()
    GameState.isInLobby = false
    GameState.playerReady = false
    GameState.isInMatch = false 
    
    RTS.TriggerCallback('rts:getGlobalStats', function(stats)
        SendNUIMessage({ 
            action = 'resetUI', 
            serverStats = stats 
        })
    end)
end)

RegisterNetEvent('rts:forceJoinLobby', function(data)
    
    GameState.isInLobby = true
    GameState.isHost = data.isHost
    GameState.lobbyCode = data.code
    DebugPrint("joining forced lobby ")
    
    SendNUIMessage({
        action = 'lobbyJoined', 
        code = data.code,
        hostName = data.hostName,
        lobbyData = data.lobbyData,
        weight = Config.Platoon.MaxWeight,
        isHost = data.isHost
    })
    
    PlaySoundFrontend(-1, "Menu_Accept", "Phone_SoundSet_Default", true)
    SendNUIMessage({action = 'showNotification', message = "Match Found! Map: " .. (data.lobbyData.map or "Unknown"), type = "success"})
end)

RegisterNetEvent('rts:updateObjectives', function(data)
  
    GameState.objectives = data
end)

RegisterNetEvent('rts:platoonDeployed')
AddEventHandler('rts:platoonDeployed', function(data)
    
    DebugPrint("^2[RTS EVENT] RECEIVED 'rts:platoonDeployed'^7")
    if not data then 
        DebugPrint("^1[RTS EVENT ERROR] Data is NIL!^7")
        return 
    end
    DebugPrint("^2[RTS EVENT] Data Content: Name=" .. tostring(data.name) .. " | Units=" .. json.encode(data.units) .. "^7")
    
    local isAircraft = false
    if data.category == 'aircraft' then
        isAircraft = true
    end

    if not isAircraft then
        
        if not GameState.deployedPlatoons then 
            DebugPrint("^3[RTS EVENT] Initializing GameState.deployedPlatoons table...^7")
            GameState.deployedPlatoons = {} 
        end

        local newPlatoon = {
            id = math.random(10000, 99999),
            name = data.name or "UNKNOWN",
            icon = data.icon or "X",
            color = data.color or "#ffffff",
            unitIds = data.units or {}, 
            maxUnits = (data.units and #data.units) or 0,
            spawnTime = GetGameTimer() 
        }

        table.insert(GameState.deployedPlatoons, newPlatoon)

    if not isAircraft then
        local mapData = Config.Maps[GameState.currentMap]
        local teamKey = (GameState.team == 1) and "team1" or "team2"
        local targetPos = nil

        local isBoat = false
        
        if Config.Platoon and Config.Platoon.PlatoonSlots then
            
            local pSlot = Config.Platoon.PlatoonSlots[data.type] or Config.Platoon.PlatoonSlots[tonumber(data.type)]
            
            if pSlot and pSlot.units then
                for _, uData in pairs(pSlot.units) do
                    local uConf = Config.Units[uData.type]
                    if uConf and uConf.model then
                        local modelHash = GetHashKey(uConf.model)
                        
                        if not HasModelLoaded(modelHash) and IsModelInCdimage(modelHash) then
                            RequestModel(modelHash)
                            
                            local t = 0
                            while not HasModelLoaded(modelHash) and t < 5 do 
                                Wait(0) 
                                t = t + 1 
                            end
                        end

                        if IsThisModelABoat(modelHash) then
                            isBoat = true
                            DebugPrint("Identified BOAT Model: " .. uConf.model)
                            break
                        end
                    end
                end
            end
        end
        
        if isBoat and mapData.waterSpawns and mapData.waterSpawns[teamKey] then
            targetPos = mapData.waterSpawns[teamKey]
        elseif mapData.spawns and mapData.spawns[teamKey] then
            targetPos = mapData.spawns[teamKey]
        end

        if targetPos then
            
            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(targetPos.x, targetPos.y, targetPos.z)
            
            if not onScreen then
                SlideCameraTo(targetPos)
            else
                
            end
        end
    end
        
        DebugPrint("^2[RTS EVENT] SUCCESS! Added Platoon to GameState. Total Platoons: " .. #GameState.deployedPlatoons .. "^7")
    else
        DebugPrint("^3[RTS EVENT] Ignored aircraft platoon (Logic correct).^7")
    end
end)

RegisterNetEvent('rts:openMenu')
AddEventHandler('rts:openMenu', function()
    OpenRTSCentral()
end)

RegisterNetEvent('rts:client:adminForceStart', function()
    SendNUIMessage({ action = 'adminForceStart' })
end)

RegisterNUICallback('resetUI', function(_, cb) cb({}) end)

RegisterNUICallback('toggleAdmin', function(data, cb)
    TriggerServerEvent('rts-admin:togglePanel')
    cb({})
end)
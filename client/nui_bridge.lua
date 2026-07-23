-- [[ NEW: LIVE STATS POLLER ]] --
RegisterNUICallback('requestLiveStats', function(data, cb)
    QBCore.Functions.TriggerCallback('rts:getLiveMenuStats', function(stats)
        cb(stats)
    end)
end)

RegisterNUICallback('initialize', function(data, cb)
    NUIReady = true
    DebugPrint("NUI Initialized")
    
    SendNUIMessage({
        action = 'setUnitConfig',
        units = Config.Units,
        categories = Config.UnitCategories,
        maps = Config.Maps,
        keys = Config.Keys -- NEW: Send Keybinds
    })

    cb({ success = true, version = Config.Version })
end)

RegisterNUICallback('createLobby', function(data, cb)
    local mapName = data.map or "grapeseed"
    
    QBCore.Functions.TriggerCallback('rts:createLobby', function(result)
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
                playersData = initialPlayers -- Fixes the 0/2 issue
            })
        end
        cb(result)
    end, mapName)
end)

RegisterNUICallback('joinLobby', function(data, cb)
    local code = data.code:upper():gsub("%s+", "")
    
    QBCore.Functions.TriggerCallback('rts:joinLobby', function(result)
        if result.success then
            GameState.isInLobby = true
            GameState.isHost = result.isHost
            GameState.lobbyCode = code
            -- The JS app.js will handle the UI screen switch safely when it receives the 'result'
        end
        cb(result)
    end, code)
end)

RegisterNUICallback('leaveLobby', function(data, cb)
    TriggerServerEvent('rts:leaveLobby')
    GameState.isInLobby = false
    GameState.playerReady = false
    SendNUIMessage({ action = 'returnToMenu' })
    QBCore.Functions.Notify("Left lobby", Config.Notifications.Info)
    cb({ success = true })
end)

RegisterNUICallback('readyToggle', function(data, cb) 
    -- THE FIX: Don't flip it blindly! Use the EXACT state the UI sends.
    GameState.playerReady = data.ready
    
    TriggerServerEvent('rts:setReady', GameState.playerReady) 
    SendNUIMessage({ action = 'updateReadyStatus', ready = GameState.playerReady }) 
    cb({ success = true }) 
end)

RegisterNetEvent('rts:abortCountdown', function()
    -- Tells the Javascript UI to instantly kill the launch sequence
    SendNUIMessage({ action = 'abortCountdown' })
end)

RegisterNUICallback('savePlatoons', function(data, cb)
    if data.platoons then
        GameState.platoons = data.platoons
        TriggerServerEvent('rts:savePlatoons', GameState.platoons)
        QBCore.Functions.Notify("Platoons saved", Config.Notifications.Success)
    end
    cb({ success = true })
end)

RegisterNUICallback('spawnPlatoon', function(data, cb)
    if not GameState.isInMatch then 
        cb({ success = false, message = "Not in match" }) 
        return 
    end
    
    -- FIX: Use Protected Call to prevent UI crashes if math fails
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
    -- [[ START PRIORITY INTERCEPT (MULTIPLE JETS FIX) ]] --
    -- Check if we have ANY pending airstrikes in the list
    if GameState.pendingAirstrikes and #GameState.pendingAirstrikes > 0 then
        if data.type == 'attack' then
            local targetEntity = nil
            
            -- Resolve Target
            if GameState.enemyUnits[data.targetId] then 
                targetEntity = GameState.enemyUnits[data.targetId].entity 
            elseif GameState.units[data.targetId] then
                targetEntity = GameState.units[data.targetId].entity
            end
            
            -- Send ALL waiting jets to attack
            if targetEntity then
                -- Loop through all jets
                for id1, jetData1 in pairs(GameState.pendingAirstrikes) do
                    if jetData1.active and DoesEntityExist(jetData1.entity) then
                        SetEntityInvincible(jetData1.entity, true)
                         SetEntityCollision(jetData1.entity, true, true) 

                        
                        -- INNER LOOP: Check against every other jet to disable collision
                        for id2, jetData2 in pairs(GameState.pendingAirstrikes) do
                            -- Ensure we aren't checking the jet against itself (id1 ~= id2)
                            if id1 ~= id2 and jetData2.active and DoesEntityExist(jetData2.entity) then
                                -- This makes jet1 pass through jet2
                                SetEntityNoCollisionEntity(jetData1.entity, jetData2.entity, true)
                            end
                        end
                    
                        -- Resume your normal logic
                        ExecuteLazarStrike(jetData1.entity, targetEntity)
                    end
                end
                
                -- Clear the list so normal RTS controls resume
                GameState.pendingAirstrikes = {} 
                SendNUIMessage({ action = 'stopAirstrikeTimer' }) -- Hide UI timer
                return -- STOP HERE. Don't let other units move.
            end
        end
    end
    -- [[ END PRIORITY INTERCEPT ]] --
    if #GameState.selectedUnits == 0 then return end

    -- =========================================================
    -- 1. MOVE ORDER
    -- =========================================================
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

                    -- A. VEHICLE MOVE LOGIC
                    if IsEntityAVehicle(unit.entity) then
                        local vehicle = unit.entity
                        local driver = GetPedInVehicleSeat(vehicle, -1)
                        -- [[ CHERNOBOG SPECIAL CASE: UNLOCK ]] --
                        if GetEntityModel(vehicle) == GetHashKey("chernobog") then

                            SetTrailerLegsRaised(vehicle)
                            -- Retract legs (State 1 = Closing/Retracted)
                            SetVehicleLandingGear(vehicle, 1) 
                            -- Release Handbrake so it can move
                            SetVehicleHandbrake(vehicle, false)
                            -- Wait a split second for game state to update (optional, but safer)
                            Wait(100)
                        end
                        FixEngineAndSecurePed(vehicle, driver)
                        if driver and DoesEntityExist(driver) and not IsPedDeadOrDying(driver, true) then
                            ClearPedTasks(driver)
                            SetVehicleEngineOn(vehicle, true, true, false)
                            PlayObeyMove(driver)
                            -- IMPORTANT: Using Driving Style 4981292 (Aggressive/Rush) from our test script
                            DisablePedReactions(driver, 5000)
                            TaskVehicleDriveToCoord(driver, vehicle, targetPos.x, targetPos.y, targetPos.z, 30.0, 0, GetEntityModel(vehicle), 4981292, 5.0, true)
                        end
                    
                    -- B. INFANTRY MOVE LOGIC
                    else
                        ClearPedTasks(unit.entity)
                        DisablePedReactions(unit.entity, 5000)
                        PlayObeyMove(unit.entity)
                        CommandPedToMarch(unit.entity, targetPos.x, targetPos.y, targetPos.z)
                    end
                end
            end
        end

    -- =========================================================
    -- 2. ATTACK ORDER
    -- =========================================================
    elseif data.type == 'attack' then
        local targetId = data.targetId
        local targetEntity = nil

        -- Resolve Target ID to an Entity (Check Friendly list, then Enemy list)
        if GameState.units[targetId] then targetEntity = GameState.units[targetId].entity end
        if GameState.enemyUnits[targetId] then targetEntity = GameState.enemyUnits[targetId].entity end

        if targetEntity and DoesEntityExist(targetEntity) then
            PlaySoundFrontend(-1, Config.Sounds.CommandAttack, 0, true)
            -- [CRITICAL FIX] Convert Vehicle Target -> Driver Target
            -- AI struggles to attack "Cars". They attack "Drivers" much better.
            if IsEntityAVehicle(targetEntity) then
                local enemyDriver = GetPedInVehicleSeat(targetEntity, -1)
                if enemyDriver ~= 0 and not IsPedDeadOrDying(enemyDriver, true) then
                    targetEntity = enemyDriver
                end
            end

            for _, unitId in ipairs(GameState.selectedUnits) do
                local unit = GameState.units[unitId]
                if unit and DoesEntityExist(unit.entity) then

                    -- A. VEHICLE ATTACK LOGIC
                    if IsEntityAVehicle(unit.entity) then
                        local driver = GetPedInVehicleSeat(unit.entity, -1)
                        FixEngineAndSecurePed(unit.entity, driver)
                        -- [[ CHERNOBOG SPECIAL CASE: LOCKDOWN ]] --
                        if GetEntityModel(vehicle) == GetHashKey("chernobog") then
                            SetTrailerLegsLowered(vehicle)

                            -- 1. Deploy Legs (State 0 = Deployed)
                            SetVehicleLandingGear(vehicle, 0)
                            -- 2. Force Stop & Handbrake (Crucial so it doesn't try to chase)
                            TaskVehicleTempAction(driver, vehicle, 27, -1) -- 27 = Stop
                            SetVehicleHandbrake(vehicle, true)
                            
                            -- Chernobog drivers don't chase; only passengers shoot. 
                            -- We stop here for the driver logic.
                        else
                            -- NORMAL VEHICLE: Chase & Attack
                            if driver and DoesEntityExist(driver) then
                                ForceGroundCombat(unit.entity)
                                Wait(0)
                                PlayObeyAttack(driver)
                                TaskCombatPed(driver, targetEntity, 0, 16)
                               -- TaskVehicleMissionPedTarget(driver, unit.entity, targetEntity, 6, 40.0, 4981292, 15.0, 0.0, true)
                               -- SetPedKeepTask(driver, true)
                            end 
                        end
                        -- [[ END CHERNOBOG ]] --
                        ---- 1. Order Driver to CHASE/RAM (Mission 6)
                        --if driver and DoesEntityExist(driver) then
                        --    -- Mission 6 = Attack/Chase. 
                        --    -- We use targetEntity (which is now likely a Ped)
                        --    TaskVehicleMissionPedTarget(driver, unit.entity, targetEntity, 6, 40.0, 4981292, 15.0, 0.0, true)
                        --    SetPedKeepTask(driver, true)
                        --end 

                        -- 2. Order PASSENGERS to SHOOT (TaskCombatPed)
                        local seats = GetVehicleMaxNumberOfPassengers(unit.entity)
                        for i = 0, seats - 1 do
                            local p = GetPedInVehicleSeat(unit.entity, i)
                            if p and DoesEntityExist(p) then
                                TaskCombatPed(p, targetEntity, 0, 16)
                            end
                        end
                        if carTrailer and carTrailer[unit.entity] then
                          --  ForceGroundCombat(carTrailer[unit.entity])
                            local trailerGuy = GetPedInVehicleSeat(carTrailer[unit.entity], -1)
                            TaskCombatPed(trailerGuy, targetEntity, 0, 16)
                        end

                    -- B. INFANTRY ATTACK LOGIC
                    else
                        -- Changed from TaskShootAtEntity to TaskCombatPed
                        -- TaskCombatPed allows them to run, take cover, and chase. 
                        -- TaskShootAtEntity makes them stand still like statues.
                        PlayObeyAttack(unit.entity)
                        TaskCombatPed(unit.entity, targetEntity, 0, 16)
                    end
                end
            end
        end
    end
end)

-- FIX: This prevents the Rectangle Selection Crash
RegisterNUICallback('selectUnits', function(data, cb)
    -- 1. Get Game Resolution
    local screenW, screenH = GetActiveScreenResolution()
    local selectedCount = 0
    
    DeselectAllUnits()
    
    -- 2. Convert Incoming Normalized Coordinates (0.0-1.0) to Game Pixels
    -- We assume the JS sends x1, y1, x2, y2 as 0.0 to 1.0
    local selMinX = math.min(data.x1, data.x2) * screenW
    local selMaxX = math.max(data.x1, data.x2) * screenW
    local selMinY = math.min(data.y1, data.y2) * screenH
    local selMaxY = math.max(data.y1, data.y2) * screenH

    for unitId, unit in pairs(GameState.units) do
        if unit and unit.entity and DoesEntityExist(unit.entity) and GetEntityHealth(unit.entity) > 0 then
            local pos = GetEntityCoords(unit.entity)
            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
            
            if onScreen then
                -- Convert Unit Position to Pixels
                local unitPixelX = screenX * screenW
                local unitPixelY = screenY * screenH
                
                -- 3. Calculate Dynamic Hitbox Size (Radius in Pixels)
                local worldRadius = 1.2 -- Default Radius (Infantry)
                if IsEntityAVehicle(unit.entity) then
                    local min, max = GetModelDimensions(GetEntityModel(unit.entity))
                    -- Use max dimension for forgiving selection
                    local size = math.max(math.abs(max.x - min.x), math.abs(max.y - min.y))
                    worldRadius = size * 0.6
                end

                -- Project a point slightly to the right to measure pixel size on screen
                local _, edgeX, edgeY = GetScreenCoordFromWorldCoord(pos.x + worldRadius, pos.y, pos.z)
                local edgePixelX = edgeX * screenW
                local edgePixelY = edgeY * screenH
                
                -- Calculate radius in pixels
                local pixelRadius = math.sqrt((unitPixelX - edgePixelX)^2 + (unitPixelY - edgePixelY)^2)
                
                -- Minimum size clamp (makes units clickable from high orbit)
                if pixelRadius < 35 then pixelRadius = 35 end

                -- 4. Create Unit Bounding Box
                local unitMinX = unitPixelX - pixelRadius
                local unitMaxX = unitPixelX + pixelRadius
                local unitMinY = unitPixelY - pixelRadius
                local unitMaxY = unitPixelY + pixelRadius

                -- 5. Check Intersection (AABB)
                -- Does the Selection Box overlap with the Unit Box?
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
    cb({ success = true }) -- Reply first

    local unitId = data.unitId
    if unitId and GameState.units[unitId] then
        -- Logic: Handle Shift key for multi-select
        if not IsDisabledControlPressed(0, 21) then 
            DeselectAllUnits()
        end
        
        -- Just add to table. The Loop in step 1 will see this and draw the marker automatically.
        table.insert(GameState.selectedUnits, unitId)
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        UpdateSelectionUI()
    end
end)

RegisterNUICallback('cameraZoom', function(data, cb)
    if not GameState.camera then return cb('ok') end
    
    local zoomStep = 10.0 -- Bigger step feels better with smoothing
    
    if data.direction == 'in' then
        GameState.cameraHeight = GameState.cameraHeight - zoomStep
    else
        GameState.cameraHeight = GameState.cameraHeight + zoomStep
    end
    
    -- Note: We don't clamp here anymore because UpdateCamera handles it every frame
    cb('ok')
end)

RegisterNUICallback('selectPlatoonGroup', function(data, cb)
    local uuid = tonumber(data.uuid) -- Force number conversion
    
    DebugPrint("[RTS DEBUG] Selecting Platoon Group ID: " .. tostring(uuid))

    DeselectAllUnits()
    
    local found = false
    if GameState.deployedPlatoons then
        for _, p in ipairs(GameState.deployedPlatoons) do
            if p.id == uuid then
                found = true
                for _, uid in ipairs(p.unitIds) do
                    local u = GameState.units[uid]
                    -- Logic: Check if unit exists locally AND is alive
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
    if Config.DedicatedServerMode then
        -- If in Dedicated Mode, 'Close' means 'Disconnect'
        TriggerServerEvent('rts:disconnectPlayer')
    else
        -- Standard Mode: Just hide UI
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'hideUI' })
    end
    cb('ok')
end)

RegisterNUICallback('getLeaderboard', function(data, cb)
    QBCore.Functions.TriggerCallback('rts:getLeaderboard', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('getHistory', function(data, cb)
    QBCore.Functions.TriggerCallback('rts:getMatchHistory', function(result)
        cb(result)
    end)
end)

RegisterNUICallback('getServerPlayerCount', function(data, cb)
    QBCore.Functions.TriggerCallback('rts:getServerPlayerCount', function(count)
        cb({ count = count })
    end)
end)

RegisterNUICallback('getGlobalStats', function(data, cb)
    QBCore.Functions.TriggerCallback('rts:getGlobalStats', function(stats)
        cb(stats)
    end)
end)

RegisterNUICallback('joinQueue', function(data, cb)
    QBCore.Functions.TriggerCallback('rts:getServerPlayerCount', function(count)
        TriggerServerEvent('rts:joinMatchmaking')
        -- Send the total server player count back to JavaScript
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

RegisterNUICallback('editorAction', function(data, cb)
    if not MapEditor.active then return cb('ok') end
    
    local action = data.action

    -- Placement & Clicks
    if action == 'CLICK_LEFT' then
        if MapEditor.currentPreview then ConfirmPlacement() end
    elseif action == 'CLICK_RIGHT' then
        if MapEditor.currentPreview then 
            DeleteEntity(MapEditor.currentPreview)
            MapEditor.currentPreview = nil
            MapEditor.pickedUpIndex = nil
        end

    -- Shift State (For Vertical Movement)
    elseif action == 'SHIFT_DOWN' then shiftPressed = true
    elseif action == 'SHIFT_UP' then shiftPressed = false

    -- Rotation
    elseif action == 'ROTATE_LEFT' and MapEditor.currentPreview then
        SetEntityHeading(MapEditor.currentPreview, GetEntityHeading(MapEditor.currentPreview) + 5.0)
    elseif action == 'ROTATE_RIGHT' and MapEditor.currentPreview then
        SetEntityHeading(MapEditor.currentPreview, GetEntityHeading(MapEditor.currentPreview) - 5.0)

    -- Zooming
    elseif action == 'ZOOM_IN' then GameState.cameraHeight = GameState.cameraHeight - 5.0
    elseif action == 'ZOOM_OUT' then GameState.cameraHeight = GameState.cameraHeight + 5.0
    
    -- Tools
    elseif action == 'RESET_HEIGHT' then MapEditor.currentVerticalOffset = 0.0
    elseif action == 'DELETE' then
        local sw, sh = GetActiveScreenResolution()
        local mx, my = GetNuiCursorPosition()
        local worldPos = GetWorldCoordFromScreen(mx/sw, my/sh)
        local searchPos = worldPos or GetCamCoord(GameState.camera)
        local idx = GetClosestPlacedObjectIndex(searchPos, 15.0)

        if idx then
            if DoesEntityExist(MapEditor.placedObjects[idx].handle) then
                DeleteEntity(MapEditor.placedObjects[idx].handle)
            end
            table.remove(MapEditor.placedObjects, idx)
            PlaySoundFrontend(-1, "DELETE", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
        end
    elseif action == 'EXIT' then ExitAndPrintMap()
    
    -- Object Selection (Pick Up / Clone)
    elseif action == 'PICKUP' or action == 'CLONE' then
        local mx, my = GetNuiCursorPosition()
        local sw, sh = GetActiveScreenResolution()
        local worldPos = GetWorldCoordFromScreen(mx/sw, my/sh)
        local idx = GetClosestPlacedObjectIndex(worldPos or GetCamCoord(GameState.camera), 10.0)
        
        if idx and not MapEditor.currentPreview then
            local targetData = MapEditor.placedObjects[idx]
            
            if action == 'PICKUP' then
                MapEditor.pickedUpIndex = idx
                MapEditor.currentPreview = targetData.handle
                MapEditor.currentModelName = targetData.model
                
                -- Sync positioning variables immediately to stop jitter
                MapEditor.currentBasePos = targetData.pos
                MapEditor.currentVerticalOffset = 0.0
                
                SetEntityAlpha(targetData.handle, 150, false)
                SetEntityCollision(targetData.handle, false, false)
            else 
                -- CLONE LOGIC
                MapEditor.currentModelName = targetData.model
                local hash = GetHashKey(targetData.model)
                RequestModel(hash)
                while not HasModelLoaded(hash) do Wait(0) end
                
                -- 1. Create the new entity
                local newEnt = IsModelAVehicle(hash) and 
                    CreateVehicle(hash, targetData.pos.x, targetData.pos.y, targetData.pos.z, targetData.heading, true, true) or 
                    CreateObject(hash, targetData.pos.x, targetData.pos.y, targetData.pos.z, true, true, false)
                
                -- 2. COPY THE HEADING IMMEDIATELY
                SetEntityHeading(newEnt, targetData.heading)
                
                -- 3. Set preview state
                MapEditor.currentPreview = newEnt
                
                -- 4. CRITICAL: Sync these to the target's current position so it doesn't jump to camera
                MapEditor.currentBasePos = targetData.pos
                MapEditor.currentVerticalOffset = 0.0
                
                SetEntityAlpha(newEnt, 150, false)
                SetEntityCollision(newEnt, false, false)
                FreezeEntityPosition(newEnt, true)
            end
        end
    end
    cb('ok')
end)

RegisterNUICallback('editorKey', function(data, cb)
    cb('ok')
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

-- NETWORK EVENTS THAT FORWARD TO NUI

RegisterNetEvent('rts:updateLobby')
AddEventHandler('rts:updateLobby', function(data)
    SendNUIMessage({
        action = 'updateLobby',
        lobbyCode = data.lobbyCode,
        
        -- [[ THIS WAS MISSING - IT CARRIES THE READY STATUS ]] --
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
     -- Save the location BEFORE any camera or teleport logic starts
    if not PreMatchLocation then
        PreMatchLocation = GetEntityCoords(PlayerPedId())
        DebugPrint("Saved PreMatchLocation: " .. tostring(PreMatchLocation))
    end
    -- 1. Validate Data
    if not data then 
        DebugPrint("^1[RTS ERROR] No data received in startMatch!^7")
        return 
    end
    DebugPrint("^2[RTS DEBUG] Team: " .. tostring(data.team) .. " | Map: " .. tostring(data.map) .. "^7")

    -- 2. Validate Map
    local map = Config.Maps[data.map]
    if not map then
        DebugPrint("^1[RTS ERROR] Map Config missing for: " .. tostring(data.map) .. "^7")
        -- Fallback to prevent crash, but warn user
        map = { name = "Unknown", center = vector3(0,0,0), range = 500.0 }
    end

    -- Validate Map Data exists to prevent future crashes
    GameState.currentMap = data.map
    if not Config.Maps[GameState.currentMap] then
        DebugPrint("^1[RTS ERROR] Invalid Map Name: " .. tostring(GameState.currentMap) .. "^7")
        -- Fallback to prevent crash
        GameState.currentMap = "grapeseed" 
    end



    -- 3. Set Game State (CRITICAL)
    GameState.isInMatch = true
    GameState.matchId = data.matchId
    GameState.team = data.team
    GameState.commandPoints = Config.MatchSettings.CommandPointsStart or 1500
    GameState.platoons = data.platoons or {}
    GameState.units = {} -- Clear old units
    GameState.cameraHeight = (Config.MatchSettings.CameraDefaultHeight + Config.Maps[GameState.currentMap].center.z) or  40.0 -- Default starting height
    
    -- 4. START THE TRACKER IMMEDIATELY (Moved to top)
    DebugPrint("^2[RTS DEBUG] Starting Hitbox Tracker...^7")
    StartHitboxTracker()
   
    -- 5. Setup Player Ped
    local ped = PlayerPedId()
    local pos = data.spawnPos
    if type(pos) == 'table' then pos = vector3(pos.x, pos.y, pos.z) end
    
    -- Teleport & Freeze
    SetEntityCoords(ped, pos.x, pos.y, pos.z + 10.0, false, false, false, false)
 --  FreezeEntityPosition(ped, true)
 --  SetEntityVisible(ped, false, false)
 --  SetEntityInvincible(ped, true)
 --  SetEntityCollision(ped, false, false)
    
    -- 6. Setup Camera
    DebugPrint("^2[RTS DEBUG] Initializing Camera...^7")
    InitializeCamera(pos)
    
    -- 7. Setup NUI
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    
    SendNUIMessage({
        action = 'startMatch',
        team = data.team,
        music  = map.music or "main_theme.mp3",
        commandPoints = GameState.commandPoints,
        platoons = GameState.platoons
    })
    
    -- 8. Start Loops
    StartMatchLoop()
    
    DebugPrint("^2[RTS DEBUG] Match Initialization Complete.^7")
    Citizen.CreateThread(function()
        while GameState.isInMatch do
            Wait(0)  -- Run every frame
            DisplayRadar(true)
        end
    end)
    -- 9. Notifications (Wrapped in pcall to prevent crashes if Config is broken)
    pcall(function()
        PlaySoundFrontend(-1, "Beep_Green", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
        QBCore.Functions.Notify("Match Started!", "success")
        StartSelectionRenderer()
        StartObjectiveSystem()
        StartFogOfWarSystem() -- <--- ADD THIS
        SpawnMapDecorations(GameState.currentMap)
        BoostGuns()
   --     TempChangeMap()
        WreckScanner(map.center, map.range)
        StartEnvironmentLock()
        
        -- AI BOT HOOK
        if data.isCpuMatch then StartCpuBotBrain(data.platoons) else CpuBot = { active = false, commandPoints = 1500, cooldowns = {0,0,0,0,0}, platoons = {}, lastThink = 0, targetPlatoon = nil }
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
    -- 1. Wait for entity to exist locally
    local entity = nil
    local timeout = 0
    
    -- Wait loop (async) to let the engine sync the entity
    CreateThread(function()
        while not NetworkDoesEntityExistWithNetworkId(data.netId) and timeout < 50 do
            Wait(100)
            SetFocusPosAndVel(data.position.x, data.position.y, data.position.z, 0.0, 0.0, 0.0)
            timeout = timeout + 1
        end
        
        if NetworkDoesEntityExistWithNetworkId(data.netId) then
            entity = NetworkGetEntityFromNetworkId(data.netId)
            
            -- 2. Store in Enemy Table
            GameState.enemyUnits[data.unitId] = {
                id = data.unitId,
                team = data.team,
                type = data.type,
                entity = entity, -- Now we have the handle!
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
    -- 1. Wait for entity to exist locally
    local entity = nil
    local timeout = 0
    
    -- Wait loop (async) to let the engine sync the entity
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
            -- Create explosion effect
            local pos = GetEntityCoords(unit.entity)
            if IsEntityAVehicle(unit.entity) then
            AddExplosion(pos.x, pos.y, pos.z, 1, 1.0, true, false, 1.0)
            end
           -- DeleteEntity(unit.entity)
            PlaySoundFrontend(-1, Config.Sounds.UnitDestroyed, "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
        end
        
        -- Remove from selected units
        for i, selectedId in ipairs(GameState.selectedUnits) do
            if selectedId == unitId then
                table.remove(GameState.selectedUnits, i)
                break
            end
        end
        
        -- Remove from units table
        GameState.units[unitId] = nil
        GameState.unitCount = GameState.unitCount - 1
        
        UpdateSelectionUI()
    end
end)

-- 1. Friendly Unit Destroyed
RegisterNetEvent('rts:unitDestroyed', function(unitId)
    local unit = GameState.units[unitId]
    if unit then
        -- Remove Blip
        if unit.blip and DoesBlipExist(unit.blip) then
            RemoveBlip(unit.blip)
        end
        
        -- Remove from Selection
        for i, selectedId in ipairs(GameState.selectedUnits) do
            if selectedId == unitId then
                table.remove(GameState.selectedUnits, i)
                UpdateSelectionUI()
                break
            end
        end
        
        -- Remove from GameState (Stops the hitbox tracker from seeing it)
        GameState.units[unitId] = nil
        
        DebugPrint("^1[RTS] Friendly Unit " .. unitId .. " Removed.^7")
    end
end)

-- 2. Enemy Unit Destroyed
RegisterNetEvent('rts:enemyUnitDestroyed', function(unitId)
    local unit = GameState.enemyUnits[unitId]
    if unit then
        -- Remove Blip
        if unit.blip and DoesBlipExist(unit.blip) then
            RemoveBlip(unit.blip)
        end
        
        -- Remove from GameState
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
    -- 1. Update Globals (For the main UI bar)
    GameState.captureProgress = data.progress
    GameState.capturingTeam = data.capturingTeam
    GameState.controllingTeam = data.controllingTeam
    
    -- [[ FIX START: Update the specific objective in GameState immediately ]] --
    if data.objective and GameState.objectives and GameState.objectives[data.objective] then
        local obj = GameState.objectives[data.objective]
        
        -- Update local values
        obj.progress = data.progress
        obj.capturingTeam = data.capturingTeam
        obj.controllingTeam = data.controllingTeam

        -- LOGIC: If progress drops to 0, reset capturing state completely
        -- This ensures the blip logic sees "No one is capturing, No one controls it" -> WHITE BLIP
        if data.progress <= 0 then
             obj.capturingTeam = 0
        end
        
        -- Refresh Blips Immediately
        UpdateObjectiveBlips()
    end
    -- [[ FIX END ]] --

    -- 2. Update UI
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
    
    -- [[ FIX START: Immediately update local state so blip changes color ]] --
    if GameState.objectives and GameState.objectives[data.name] then
        GameState.objectives[data.name].controllingTeam = data.team
        GameState.objectives[data.name].capturingTeam = 0 -- No longer being capped
        GameState.objectives[data.name].progress = 0
        
        -- Force a blip update immediately
        UpdateObjectiveBlips()
    end
    -- [[ FIX END ]] --

    if data.team == GameState.team then
        QBCore.Functions.Notify("Objective captured: " .. data.name, Config.Notifications.Success)
    else
        QBCore.Functions.Notify("Objective lost: " .. data.name, Config.Notifications.Error)
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
    
    -- [[ DEBUG PRINT ]] --
    local k = result.stats and result.stats.kills or 0
    DebugPrint("^2[RTS DEBUG] END MATCH RECEIVED. KILLS: " .. tostring(k) .. "^7")
    
    -- FIX: Re-enable focus immediately so we can click buttons
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
        
        -- [[ THIS WAS MISSING ]] --
        levelData = result.levelData 
    })
    
    PlaySoundFrontend(-1, Config.Sounds.MatchEnd, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    
    if result.victory then
        QBCore.Functions.Notify("VICTORY! " .. (result.reason or ""):upper(), "success", 10000)
    else
        QBCore.Functions.Notify("DEFEAT! " .. (result.reason or ""):upper(), "error", 10000)
    end

    if result.cashRewards then
        local amount = result.cashAmount
        TriggerServerEvent("enyo-rts:giveMoney", amount)
    end

    -- [[ FIX: Robust Blip Removal ]] --
    if GameState and GameState.objectiveBlips then
        for name, blip in pairs(GameState.objectiveBlips) do
            -- Always try to remove, DoesBlipExist check is good safety
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end
    end
    GameState.objectiveBlips = {} -- Clear the table
    -- [[ END FIX ]] --
     FullPlayerReset()

end)

RegisterNetEvent('rts:resetUI')
AddEventHandler('rts:resetUI', function()
    GameState.isInLobby = false
    GameState.playerReady = false
    GameState.isInMatch = false 
    
    -- [[ FIX: Fetch fresh stats before opening the menu ]] --
    QBCore.Functions.TriggerCallback('rts:getGlobalStats', function(stats)
        SendNUIMessage({ 
            action = 'resetUI', -- We send the reset action...
            serverStats = stats -- ...WITH the new data attached!
        })
    end)
end)

RegisterNetEvent('rts:forceJoinLobby', function(data)
    -- 1. Update Local State
    GameState.isInLobby = true
    GameState.isHost = data.isHost
    GameState.lobbyCode = data.code
    DebugPrint("joining forced lobby ")
    -- 2. Force NUI to switch screens
    -- We use 'lobbyJoined' because app.js already has logic to switch screens for this action
    SendNUIMessage({
        action = 'lobbyJoined', 
        code = data.code,
        hostName = data.hostName,
        lobbyData = data.lobbyData,
        weight = Config.Platoon.MaxWeight,
        isHost = data.isHost
    })
    
    -- 3. Audio/Visual Feedback
    PlaySoundFrontend(-1, "Menu_Accept", "Phone_SoundSet_Default", true)
    QBCore.Functions.Notify("Match Found! Map: " .. (data.lobbyData.map or "Unknown"), "success")
end)

RegisterNetEvent('rts:updateObjectives', function(data)
  --  DebugPrint("[RTS] Received " .. (data and "Valid" or "Nil") .. " Objectives Data") -- Debug Print
    GameState.objectives = data
end)

RegisterNetEvent('rts:platoonDeployed')
AddEventHandler('rts:platoonDeployed', function(data)
    -- DEBUG 1: Raw Data Receipt
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
        -- Initialize table if nil (Paranoia check)
        if not GameState.deployedPlatoons then 
            DebugPrint("^3[RTS EVENT] Initializing GameState.deployedPlatoons table...^7")
            GameState.deployedPlatoons = {} 
        end

        local newPlatoon = {
            id = math.random(10000, 99999),
            name = data.name or "UNKNOWN",
            icon = data.icon or "X",
            color = data.color or "#ffffff",
            unitIds = data.units or {}, -- Critical safety fallback
            maxUnits = (data.units and #data.units) or 0,
            spawnTime = GetGameTimer() 
        }

        table.insert(GameState.deployedPlatoons, newPlatoon)

        -- 2. NEW: Camera Slide Logic
        -- Only slide if it's NOT aircraft (User Request)
        -- 2. Camera Slide Logic (Smart)
    if not isAircraft then
        local mapData = Config.Maps[GameState.currentMap]
        local teamKey = (GameState.team == 1) and "team1" or "team2"
        local targetPos = nil

        -- A. Check if this platoon contains a BOAT
        -- [[ FIX START: FORCE MODEL CHECK ]] --
        local isBoat = false
        
        if Config.Platoon and Config.Platoon.PlatoonSlots then
            -- Handle key as String or Number (Safety)
            local pSlot = Config.Platoon.PlatoonSlots[data.type] or Config.Platoon.PlatoonSlots[tonumber(data.type)]
            
            if pSlot and pSlot.units then
                for _, uData in pairs(pSlot.units) do
                    local uConf = Config.Units[uData.type]
                    if uConf and uConf.model then
                        local modelHash = GetHashKey(uConf.model)
                        
                        -- CRITICAL: Request model briefly so IsThisModelABoat returns TRUE
                        if not HasModelLoaded(modelHash) and IsModelInCdimage(modelHash) then
                            RequestModel(modelHash)
                            -- Wait a tiny bit (up to 5 frames) for metadata to load
                            local t = 0
                            while not HasModelLoaded(modelHash) and t < 5 do 
                                Wait(0) 
                                t = t + 1 
                            end
                        end

                        -- Now the native will correctly identify the boat
                        if IsThisModelABoat(modelHash) then
                            isBoat = true
                            DebugPrint("Identified BOAT Model: " .. uConf.model)
                            break
                        end
                    end
                end
            end
        end
        -- [[ FIX END ]] --
        -- B. Determine Coordinates (Water vs Land)
        if isBoat and mapData.waterSpawns and mapData.waterSpawns[teamKey] then
            targetPos = mapData.waterSpawns[teamKey]
        elseif mapData.spawns and mapData.spawns[teamKey] then
            targetPos = mapData.spawns[teamKey]
        end

        -- C. Execute Slide (Smart Check)
        if targetPos then
            -- [NEW] Check if the target is already on screen
            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(targetPos.x, targetPos.y, targetPos.z)
            
            -- Only slide if it is NOT on screen (onScreen is a boolean/int)
            if not onScreen then
                SlideCameraTo(targetPos)
            else
                -- Optional: Debug print
                -- DebugPrint("Spawn location already visible - skipping camera slide")
            end
        end
    end
        -- DEBUG 2: Confirmation
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

-- =======================================================================
-- CPU BOT BRAIN & SPAWNER (Dynamic Priority AI)
-- =======================================================================
-- =======================================================================
-- CPU BOT BRAIN V3.0 (Army Splitting & Anti-Clumping Formations)
-- =======================================================================
function StartCpuBotBrain(mirroredPlatoons)
    DebugPrint("^5[CPU BRAIN] Booting up AI Commander V3.0...^7")
    CpuBot.active = true
    CpuBot.commandPoints = Config.MatchSettings.CommandPointsStart or 1500
    CpuBot.cooldowns = {0,0,0,0,0}
    CpuBot.targetPlatoon = nil

    -- [[ THE FIX: SANITIZE NO-AI UNITS ]] --
    -- The bot scans the human's platoons and deletes anything it shouldn't use.
    CpuBot.platoons = {}
    for slotStr, pData in pairs(mirroredPlatoons or {}) do
        local validUnits = {}
        local aiCost = 0
        local aiCount = 0
        
        for _, uData in ipairs(pData.units or {}) do
            local uConf = Config.Units[uData.type]
            -- Only keep the unit if it exists and DOES NOT have the 'noai' flag
            if uConf and not uConf.noai then
                table.insert(validUnits, uData)
                aiCost = aiCost + (uConf.cost * (uData.count or 1))
                aiCount = aiCount + (uData.count or 1)
            end
        end
        
        -- Only save the platoon to the bot's memory if there's actually something left to spawn
        if #validUnits > 0 then
            CpuBot.platoons[slotStr] = {
                units = validUnits,
                totalCost = aiCost,
                unitCount = aiCount
            }
        end
    end

    local mapConfig = Config.Maps[GameState.currentMap]

    CreateThread(function()
        while GameState.isInMatch and CpuBot.active do
            Wait(1000) 
            
            -- [ECONOMY TICKS]
            CpuBot.commandPoints = CpuBot.commandPoints + ((Config.MatchSettings.CommandPointsPerMinute or 150) / 60)
            for i = 1, 5 do if CpuBot.cooldowns[i] > 0 then CpuBot.cooldowns[i] = CpuBot.cooldowns[i] - 1 end end
            
            local now = GetGameTimer()
            
            -- ==========================================
            -- TACTICAL THINKING CYCLE (Every 3 seconds)
            -- ==========================================
            if now - CpuBot.lastThink > 3000 then 
                CpuBot.lastThink = now
                
                -- PHASE A: DYNAMIC ECONOMY (Buying Units)
                if not CpuBot.targetPlatoon or CpuBot.cooldowns[CpuBot.targetPlatoon] > 0 then
                    local availableSlots = {}
                    for i = 1, 5 do
                        local pStr = tostring(i)
                        if CpuBot.cooldowns[i] <= 0 and CpuBot.platoons[pStr] and CpuBot.platoons[pStr].units and #CpuBot.platoons[pStr].units > 0 then 
                            table.insert(availableSlots, i) 
                        end
                    end

                    if #availableSlots > 0 then
                        table.sort(availableSlots, function(a, b) 
                            return (CpuBot.platoons[tostring(a)].totalCost or 0) > (CpuBot.platoons[tostring(b)].totalCost or 0)
                        end)
                        -- 70% chance to save for Heavy unit, 30% chance for random unit
                        CpuBot.targetPlatoon = (math.random(1, 100) <= 70) and availableSlots[1] or availableSlots[math.random(1, #availableSlots)]
                    end
                end

                if CpuBot.targetPlatoon then
                    -- Get the data safely using both key types
                    local pData = CpuBot.platoons[tostring(CpuBot.targetPlatoon)] or CpuBot.platoons[tonumber(CpuBot.targetPlatoon)]
                    local pCost = pData.totalCost or 0
                    local pCount = pData.unitCount or 1
                    
                    if CpuBot.commandPoints >= pCost then
                        -- [NEW] Count how many units the bot currently has alive
                        local currentCpuPop = 0
                        if GameState.enemyUnits then
                            for _, _ in pairs(GameState.enemyUnits) do currentCpuPop = currentCpuPop + 1 end
                        end
                        
                        local maxPop = Config.MatchSettings.MaxUnits or 20
                        
                        -- Only spawn if it won't break the population cap
                        if currentCpuPop + pCount <= maxPop then
                            CpuBot.commandPoints = CpuBot.commandPoints - pCost
                            CpuBot.cooldowns[CpuBot.targetPlatoon] = Config.MatchSettings.RespawnCooldown or 30
                            TriggerServerEvent('rts:server:cpuSpawnPlatoon', GameState.matchId, CpuBot.targetPlatoon)
                            CpuBot.targetPlatoon = nil 
                        else
                            DebugPrint("^5[CPU BRAIN] Waiting for population cap space... ("..currentCpuPop.."/"..maxPop..")^7")
                        end
                    end
                end

                -- ==========================================
                -- PHASE B: TACTICAL ROUTING (The Smart Split)
                -- ==========================================
                -- 1. Analyze the Map Objectives
                local mainObjPos = nil
                local sideObjs = {}
                local unownedSideObjs = {}

                if GameState.objectives then
                    for _, obj in pairs(GameState.objectives) do
                        local pos = vector3(obj.position.x, obj.position.y, obj.position.z)
                        if obj.type == "victory" then
                            mainObjPos = pos
                        else
                            table.insert(sideObjs, pos)
                            if obj.controllingTeam ~= 2 then table.insert(unownedSideObjs, pos) end
                        end
                    end
                end
                
                -- Fallback if no main objective exists
                local fallbackBase = vector3(mapConfig.spawns.team1.x, mapConfig.spawns.team1.y, mapConfig.spawns.team1.z)
                if not mainObjPos then mainObjPos = fallbackBase end

                -- 2. Dispatch the Army
                if GameState.enemyUnits then
                    for uIdStr, eUnit in pairs(GameState.enemyUnits) do
                        if DoesEntityExist(eUnit.entity) and GetEntityHealth(eUnit.entity) > 0 then
                            local myPos = GetEntityCoords(eUnit.entity)
                            local numId = tonumber(uIdStr) or math.random(1,100)
                            
                            -- Step 1: Scan for immediate threats (Player Units)
                            local closestEnemyDist, closestEnemyEnt = 80.0, nil
                            for _, pUnit in pairs(GameState.units) do
                                if DoesEntityExist(pUnit.entity) and GetEntityHealth(pUnit.entity) > 0 then
                                    local dist = #(myPos - GetEntityCoords(pUnit.entity))
                                    if dist < closestEnemyDist then 
                                        closestEnemyDist = dist
                                        closestEnemyEnt = pUnit.entity 
                                    end
                                end
                            end
                            
                            -- Step 2: Make Decision
                            -- Step 2: Make Decision
                            if closestEnemyEnt then
                                -- THREAT DETECTED: Engage!
                                
                                -- [CRITICAL FIX] Convert Vehicle Target -> Driver Target
                                -- GTA AI struggles to shoot at "Cars". They shoot "Drivers" much better.
                                local combatTarget = closestEnemyEnt
                                if IsEntityAVehicle(combatTarget) then
                                    local tDriver = GetPedInVehicleSeat(combatTarget, -1)
                                    if tDriver ~= 0 and not IsPedDeadOrDying(tDriver, true) then
                                        combatTarget = tDriver
                                    end
                                end

                                if IsEntityAVehicle(eUnit.entity) then
                                    local driver = GetPedInVehicleSeat(eUnit.entity, -1)
                                    if driver ~= 0 then 
                                        -- Tell the driver to ATTACK (Uses Tank Turrets, Ramming, or Drive-bys)
                                        TaskCombatPed(driver, combatTarget, 0, 16) 
                                    end
                                    
                                    -- Tell ALL passengers to lean out the windows and shoot
                                    local maxSeats = GetVehicleMaxNumberOfPassengers(eUnit.entity)
                                    for seat = 0, maxSeats - 1 do
                                        local passenger = GetPedInVehicleSeat(eUnit.entity, seat)
                                        if passenger ~= 0 then
                                            TaskCombatPed(passenger, combatTarget, 0, 16)
                                        end
                                    end
                                else
                                    -- Infantry Attack
                                    TaskCombatPed(eUnit.entity, combatTarget, 0, 16)
                                end
                            else
                                -- NO THREAT: Advance on Objectives
                                local targetBasePos = mainObjPos

                                -- ARMY SPLIT LOGIC: Every 3rd unit (33%) becomes a Flanker to secure side resources
                                if numId % 3 == 0 and #sideObjs > 0 then
                                    if #unownedSideObjs > 0 then
                                        targetBasePos = unownedSideObjs[(numId % #unownedSideObjs) + 1]
                                    else
                                        targetBasePos = sideObjs[(numId % #sideObjs) + 1] -- Patrol existing side nodes
                                    end
                                end

                                -- ANTI-CLUMPING LOGIC (The Golden Ratio Spread)
                                -- Calculates a unique defensive ring position based on the Unit's ID
                                local angle = numId * 137.5 
                                local radius = 3.0 + ((numId % 6) * 3.0) -- Creates expanding rings from 3m to 18m
                                if IsEntityAVehicle(eUnit.entity) then radius = radius * 1.5 end -- Vehicles get wider berths
                                
                                local offsetX = math.cos(math.rad(angle)) * radius
                                local offsetY = math.sin(math.rad(angle)) * radius
                                local finalTargetPos = vector3(targetBasePos.x + offsetX, targetBasePos.y + offsetY, targetBasePos.z)

                                -- Dispatch to the unique spot
                                if IsEntityAVehicle(eUnit.entity) then
                                    local driver = GetPedInVehicleSeat(eUnit.entity, -1)
                                    if driver ~= 0 then 
                                        TaskVehicleDriveToCoord(driver, eUnit.entity, finalTargetPos.x, finalTargetPos.y, finalTargetPos.z, 30.0, 1, GetEntityModel(eUnit.entity), 4981292, 5.0, true) 
                                    end
                                else
                                    -- Uses the Bot's unit ID modulo to stagger the nav calculations
                                    CommandPedToMoveSafely(eUnit.entity, finalTargetPos, numId % 40)
                                    --TaskGoToCoordAnyMeans(eUnit.entity, finalTargetPos.x, finalTargetPos.y, finalTargetPos.z, 2.0, 0, false, 4981292, 0.0)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

RegisterNetEvent('rts:client:cpuDoSpawn', function(unitData)
    local uConf = Config.Units[unitData.type]
    if not uConf then return end
    
    local teamKey, modelName = "team2", uConf.model or "s_m_y_marine_01"
    if uConf.category == "infantry" and uConf.teamModels and uConf.teamModels[teamKey] then modelName = uConf.teamModels[teamKey] end

    local modelHash = GetHashKey(modelName)
    RequestModel(modelHash) while not HasModelLoaded(modelHash) do Wait(10) end

    local entity = nil
    
    -- ==========================================
    -- 1. VEHICLE & AIRCRAFT SPAWN LOGIC
    -- ==========================================
    if uConf.category == "vehicles" or uConf.category == "helicopters" or uConf.category == "aircraft" then
        entity = CreateVehicle(modelHash, unitData.position.x, unitData.position.y, unitData.position.z + 1.0, 0.0, true, true)
        
        -- [NEW] APPLY TEAM COLORS
        local teamKey = "team2" -- CPU is always Team 2
        if uConf.teamColors and uConf.teamColors[teamKey] then
            local colors = uConf.teamColors[teamKey]
            SetVehicleColours(entity, colors[1], colors[2])
        end
        -- [END NEW]
        
        -- Apply Core Vehicle Buffs (Identical to Player)
        SetVehicleEngineCanDegrade(entity, false)
        SetDisableVehicleEngineFires(entity, false)
        SetEntityAsMissionEntity(entity, true, true)
        SetVehicleStrong(entity, true)
        SetVehicleEngineOn(entity, true, true, false)
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)
        SetVehicleOnGroundProperly(entity)

        -- Apply Team Colors
        if uConf.teamColors and uConf.teamColors[teamKey] then
            local colors = uConf.teamColors[teamKey]
            SetVehicleColours(entity, colors[1], colors[2])
        end

        -- TRAILER LOGIC
        local trailer = nil
        local trailerEntity = 0
        if uConf.trailer then
            local tHash = GetHashKey(uConf.trailer)
            RequestModel(tHash) while not HasModelLoaded(tHash) do Wait(10) end
            
            local spawnPos = GetEntityCoords(entity)
            trailer = CreateVehicle(tHash, spawnPos.x, spawnPos.y - 5.0, spawnPos.z, GetEntityHeading(entity), true, true)
            trailerEntity = trailer
            
            if uConf.teamColors and uConf.teamColors[teamKey] then
                local colors = uConf.teamColors[teamKey]
                SetVehicleColours(trailer, colors[1], colors[2])
            end
            
            AttachVehicleToTrailer(entity, trailerEntity, 1.1)
            SetEntityMaxHealth(trailer, uConf.health or 1000)
            SetEntityHealth(trailer, uConf.health or 1000)
            SetVehicleBodyHealth(trailer, uConf.health + 0.0)
            SetEntityAsMissionEntity(trailer, true, true)
            SetVehicleStrong(trailer, true)
            SetEntityProofs(trailer, false, true, false, true, false, false, false, false)
            SetModelAsNoLongerNeeded(tHash)
        end

        -- FULL CREW LOGIC (Driver + Passengers + Gunners)
        local pedModel = GetHashKey(uConf.teamDrivers and uConf.teamDrivers[teamKey] or "s_m_y_marine_01")
        RequestModel(pedModel) while not HasModelLoaded(pedModel) do Wait(10) end
        
        local seatCount = GetVehicleMaxNumberOfPassengers(entity)
        local maxi = 2
        if maxi > seatCount - 1 then maxi = seatCount - 1 end
        if trailer then maxi = maxi + 1 end
        
        for seat = -1, maxi do
            local anyseat = true
            if IsTurretSeat(entity, seat) or seat == -1 or anyseat then
                local occ = CreatePed(4, pedModel, unitData.position.x, unitData.position.y, unitData.position.z, 0.0, true, true)
                
                -- Apply Exact Player Occupant Buffs
                SetEntityAsMissionEntity(occ, true, true)
                SetEntityProofs(occ, true, true, true, true, true, true, true, true)
                SetEntityInvincible(occ, true)
                SetPedSuffersCriticalHits(occ, false)
                SetPedCanRagdollFromPlayerImpact(occ, false)
                SetRagdollBlockingFlags(occ, 1)
                SetPedCombatAttributes(occ, 46, true)
                SetPedCombatAttributes(occ, 3, false)
                SetPedFiringPattern(occ, GetHashKey("FIRING_PATTERN_FULL_AUTO"))
                
                if uConf.weapons then 
                    for i, wpn in ipairs(uConf.weapons) do 
                        local wh = GetHashKey(wpn)
                        GiveWeaponToPed(occ, wh, 9999, false, true)
                        if i == 1 then SetCurrentPedWeapon(occ, wh, true) end 
                    end 
                end
                
                MakeAgressive(occ, 100, 2, 40.0)
                SetPedRelationshipGroupHash(occ, GetHashKey("RTS_TEAM_2"))
                
                -- Seat Assignment
                if trailer and seat == maxi then 
                    SetPedIntoVehicle(occ, trailerEntity, -1)
                else
                    if seat > -1 then TaskEnterVehicle(occ, entity, 10, seat, 1.0, 16, 0) end
                    Wait(10)
                    if seat > -1 and not IsPedInAnyVehicle(occ) then SetPedIntoVehicle(occ, entity, seat) end
                    if seat == -1 then
                        SetPedIntoVehicle(occ, entity, -1)
                        TaskVehicleTempAction(occ, entity, 27, -1)
                    end
                end
                
                Wait(10)
                WatchPedVehicle(occ)
            end
        end

        -- ARMOR & MODKITS
        SetVehicleModKit(entity, 0)
        SetVehicleMod(entity, 16, 4, false)
        SetVehicleTyresCanBurst(entity, false)
        SetVehicleWheelsCanBreak(entity, false)
        SetVehicleHasStrongAxles(entity, true)
        SetVehicleExplodesOnHighExplosionDamage(entity, false)
        
        SetVehicleMod(entity, 11, 3, false) 
        SetVehicleMod(entity, 12, 2, false) 
        SetVehicleMod(entity, 13, 2, false) 
        if uConf.ModKit10 then SetVehicleMod(entity, 10, uConf.ModKit10, false) end

        Wait(250)
        WatchVehicle(entity)

        -- Trailer Armor
        if trailerEntity ~= 0 then 
            SetVehicleModKit(trailerEntity, 0)
            SetVehicleMod(trailerEntity, 16, 4, false)
            SetVehicleTyresCanBurst(trailerEntity, false)
            SetVehicleWheelsCanBreak(trailerEntity, false)
            SetVehicleHasStrongAxles(trailerEntity, true)
            SetVehicleExplodesOnHighExplosionDamage(trailerEntity, false)
            SetVehicleMod(trailerEntity, 10, uConf.TrailerModKit10, false)
            
            Wait(250)
            StartTrailerWatch(entity, trailerEntity, uConf.health)
            RestrictToAntiAir(trailerEntity)
            StartAntiAirAutoCombat(trailerEntity)
        end

        -- Tank AI Logic
        if uConf.model == 'rhino' or uConf.model == 'khanjali' then
            StartTankHullLogic(entity)
            RestrictToGround(entity)
        end

    -- ==========================================
    -- 2. INFANTRY SPAWN LOGIC
    -- ==========================================
    else
        entity = CreatePed(4, modelHash, unitData.position.x, unitData.position.y, unitData.position.z + 1.0, 0.0, true, true)
        SetEntityAsMissionEntity(entity, true, true)
        
        -- Exact Player Infantry Buffs
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)
        SetPedSuffersCriticalHits(entity, false)
        SetPedCanRagdollFromPlayerImpact(entity, false)
        SetRagdollBlockingFlags(entity, 1)
        SetBlockingOfNonTemporaryEvents(entity, true)
        SetPedCombatAttributes(entity, 46, true)
        SetPedFleeAttributes(entity, 0, false)
        SetPedDiesInWater(entity, true)
        SetPedDiesInstantlyInWater(entity, true)
        
        MakeAgressive(entity, 100, 2, 40.0)
        SetPedRelationshipGroupHash(entity, GetHashKey("RTS_TEAM_2"))
        
        if uConf.weapons then 
            for i, wpn in ipairs(uConf.weapons) do 
                local wh = GetHashKey(wpn)
                GiveWeaponToPed(entity, wh, 9999, false, true)
                if i == 1 then SetCurrentPedWeapon(entity, wh, true) end 
            end 
            SetPedFiringPattern(entity, GetHashKey("FIRING_PATTERN_FULL_AUTO"))
            WatchPedonFoot(entity)
        end
    end

    -- ==========================================
    -- 3. FINAL HEALTH SYNC & REGISTRATION
    -- ==========================================
    if DoesEntityExist(entity) then
        if uConf.health then
            SetEntityMaxHealth(entity, uConf.health)
            SetEntityHealth(entity, uConf.health)
            SetPedArmour(entity, 0)
            
            -- THE FIX: Sync true body health so they don't explode early
            if IsEntityAVehicle(entity) then
                SetVehicleBodyHealth(entity, uConf.health + 0.0)
            end
        end
        
        local blip = CreateUnitBlip(entity, 2, uConf.category, uConf.blip or nil, false)
        GameState.enemyUnits[unitData.unitId] = { id = unitData.unitId, team = 2, type = unitData.type, entity = entity, blip = blip }
    end
    
    SetModelAsNoLongerNeeded(modelHash)
end)

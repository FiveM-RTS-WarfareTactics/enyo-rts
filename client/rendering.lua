function StartHitboxTracker()
    CreateThread(function()
        while GameState.isInMatch do
            Wait(30) -- 30ms = ~33 FPS for smoother UI tracking
            
            local onScreenUnits = {}
            local sightRange = Config.MatchSettings and Config.MatchSettings.UnitSightRange or 65.0
            if GameState.pendingAirstrikes and #GameState.pendingAirstrikes > 0 then sightRange = 5000.0 end
            
            local camPos = GetCamCoord(GameState.camera) -- Get RTS Cam (or gameplay cam)

            -- 1. Helper: Robust Liveness Check
            local function IsUnitAlive(entity)
                if not entity or not DoesEntityExist(entity) then return false end
                if IsEntityAVehicle(entity) then
                    if IsEntityDead(entity) then return false end
                    if GetVehicleBodyHealth(entity) <= 0 then return false end
                else
                    if IsPedDeadOrDying(entity, true) then return false end
                end
                return true
            end

            -- 2. Helper: DYNAMIC HEIGHT CALCULATION
            local function GetHitboxPosition(entity)
                local pos = GetEntityCoords(entity)
                if pos.x == 0.0 and pos.y == 0.0 then return nil end

                -- A. Get Exact Model Height (Bounding Box)
                local min, max = GetModelDimensions(GetEntityModel(entity))
                local height = (max.z - min.z)

                -- B. Calculate Distance to Camera
                local dist = #(camPos - pos)

                -- C. Dynamic Offset Logic
                -- When CLOSE (Zoom In): We add extra height so it doesn't clip into the head/feet.
                -- When FAR (Zoom Out): We reduce the relative offset so it stays visually attached.
                
                local zOffset = max.z + 0.2 -- Base: Just above the highest point of the model
                
                if dist < 20.0 then
                    zOffset = zOffset + 0.5 -- Push UP when close
                elseif dist > 80.0 then
                    zOffset = zOffset - 0.2 -- Pull DOWN slightly when far (visual perspective fix)
                end

                return vector3(pos.x, pos.y, pos.z + zOffset)
            end

            -- 3. Cache Friendly Positions
            local friendlyPositions = {}
            for _, unit in pairs(GameState.units) do
                if IsUnitAlive(unit.entity) then
                    table.insert(friendlyPositions, GetEntityCoords(unit.entity))
                end
            end

            -- 4. Process Friendly Units
            for unitId, unit in pairs(GameState.units) do
                if IsUnitAlive(unit.entity) then
                    local hitboxPos = GetHitboxPosition(unit.entity)
                    
                    if hitboxPos then
                        local onScreen, x, y = GetScreenCoordFromWorldCoord(hitboxPos.x, hitboxPos.y, hitboxPos.z)
                        
                        if onScreen then
                            local curHp, maxHp, healthPct = 0, 100, 0
                            
                            if IsEntityAVehicle(unit.entity) then
                                curHp = math.floor(GetVehicleBodyHealth(unit.entity))
                                maxHp = (Config.Units[unit.type] and Config.Units[unit.type].health) or 1000.0
                            else
                                curHp = GetEntityHealth(unit.entity)
                                maxHp = GetEntityMaxHealth(unit.entity)
                            end

                            if maxHp <= 0 then maxHp = 1 end
                            healthPct = math.floor((curHp / maxHp) * 100)
                            if healthPct > 100 then healthPct = 100 end
                            if healthPct < 0 then healthPct = 0 end

                            table.insert(onScreenUnits, {
                                id = unitId,
                                x = x, y = y,
                                team = unit.team,
                                health = healthPct,
                                cur = curHp,
                                max = maxHp,
                                type = unit.type
                            })
                        end
                    end
                end
            end

            -- 5. Process Enemy Units
            for unitId, unit in pairs(GameState.enemyUnits) do
                -- A. Linker
                if not unit.entity or not DoesEntityExist(unit.entity) then
                    if unit.position then
                        local searchRadius = 15.0 
                        local pool = (Config.Units[unit.type] and Config.Units[unit.type].category == "vehicles") 
                                     and GetGamePool('CVehicle') or GetGamePool('CPed')
                        
                        local closestEnt = nil
                        local minDst = searchRadius
                        
                        for _, ent in ipairs(pool) do
                            local pPos = GetEntityCoords(ent)
                            local dist = #(pPos - unit.position)
                            if dist < minDst and IsUnitAlive(ent) and ent ~= PlayerPedId() then
                                local isMine = false
                                for _, myUnit in pairs(GameState.units) do
                                    if myUnit.entity == ent then isMine = true break end
                                end
                                if not isMine then
                                    closestEnt = ent
                                    minDst = dist
                                end
                            end
                        end
                        if closestEnt then unit.entity = closestEnt end
                    end
                end

                -- B. Rendering
                if IsUnitAlive(unit.entity) then
                    local enemyPos = GetEntityCoords(unit.entity)
                    
                    if enemyPos.x ~= 0.0 then 
                        unit.position = enemyPos 
                        
                        local isVisible = false
                        for _, friendPos in ipairs(friendlyPositions) do
                            local dist2D = #(vector2(enemyPos.x, enemyPos.y) - vector2(friendPos.x, friendPos.y))
                            if dist2D < sightRange then isVisible = true break end
                        end
                        
                        if isVisible then
                            local hitboxPos = GetHitboxPosition(unit.entity)
                            if hitboxPos then
                                local onScreen, x, y = GetScreenCoordFromWorldCoord(hitboxPos.x, hitboxPos.y, hitboxPos.z)
                                
                                if onScreen then
                                    local curHp, maxHp, healthPct = 0, 100, 0

                                    if IsEntityAVehicle(unit.entity) then
                                        curHp = math.floor(GetVehicleBodyHealth(unit.entity))
                                        maxHp = (Config.Units[unit.type] and Config.Units[unit.type].health) or math.floor(GetVehicleBodyHealth(unit.entity)) or 1000.0
                                    else
                                        curHp = GetEntityHealth(unit.entity)
                                        maxHp = GetEntityMaxHealth(unit.entity)
                                    end

                                    if maxHp <= 0 then maxHp = 1 end
                                    healthPct = math.floor((curHp / maxHp) * 100)
                                    if healthPct > 100 then healthPct = 100 end
                                    if healthPct < 0 then healthPct = 0 end

                                    table.insert(onScreenUnits, {
                                        id = unitId,
                                        x = x, y = y,
                                        team = unit.team,
                                        health = healthPct,
                                        cur = curHp,
                                        max = maxHp,
                                        type = unit.type
                                    })
                                end
                            end
                        end
                    end
                end
            end
            
            SendNUIMessage({ action = 'updateUnitPositions', units = onScreenUnits })
        end
    end)
end

function ResetGameWorldInRange(centerCoords, range)
    -- =========================
    -- Reset Lua RNG
    -- =========================
    math.randomseed(GetGameTimer())

    -- =========================
    -- Delete vehicles in range
    -- =========================
    local vehicles = GetGamePool("CVehicle")

    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) then
            local vehCoords = GetEntityCoords(vehicle)
            local distance = #(vehCoords - centerCoords)

            if distance <= range then
                SetEntityAsMissionEntity(vehicle, true, true)
                SetEntityCollision(vehicle, false, false)
                SetEntityAlpha(vehicle, 0, false)

                DeleteVehicle(vehicle)
                DeleteEntity(vehicle)
            end
        end
    end

    -- =========================
    -- Delete HUMAN peds in range
    -- =========================
    local peds = GetGamePool("CPed")

    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) then
            if not IsPedAPlayer(ped) and IsPedHuman(ped) then
                local pedCoords = GetEntityCoords(ped)
                local distance = #(pedCoords - centerCoords)

                if distance <= range then
                    SetEntityAsMissionEntity(ped, true, true)
                    ClearPedTasksImmediately(ped)
                    SetEntityCollision(ped, false, false)
                    SetEntityAlpha(ped, 0, false)

                    DeletePed(ped)
                    DeleteEntity(ped)
                end
            end
        end
    end

    DebugPrint(("^2World reset in %.1f range complete^7"):format(range))
end

function StartMatch(data)
    local ped = PlayerPedId()
    
    -- Save the location BEFORE any camera or teleport logic starts
    if not PreMatchLocation then
        PreMatchLocation = GetEntityCoords(ped)
        DebugPrint("Saved PreMatchLocation: " .. tostring(PreMatchLocation))
    end

    -- The rest of your StartMatch code...
    CleanupMatch(true)
    -- Set Player to a Neutral or Friendly Group so AI ignores them
    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    
    -- Make armies ignore the spectator
    SetRelationshipBetweenGroups(1, GetHashKey("RTS_TEAM_1"), playerGroup) -- Respect
    SetRelationshipBetweenGroups(1, GetHashKey("RTS_TEAM_2"), playerGroup) -- Respect
    SetRelationshipBetweenGroups(1, playerGroup, GetHashKey("RTS_TEAM_1"))
    SetRelationshipBetweenGroups(1, playerGroup, GetHashKey("RTS_TEAM_2"))

    GameState.isInMatch = true
    GameState.matchId = data.matchId
    GameState.team = data.team
    GameState.currentMap = data.map
    GameState.commandPoints = Config.MatchSettings.CommandPointsStart
    GameState.incomeRate = Config.MatchSettings.CommandPointsPerMinute / 60
    GameState.platoons = data.platoons or {}
    
    -- Get map data
    local map = Config.Maps[data.map]
    if not map then
        DebugPrint("Invalid map: " .. data.map)
        return
    end
    
    -- Store map bounds
    GameState.mapBounds = {
        minX = map.center.x - map.range,
        maxX = map.center.x + map.range,
        minY = map.center.y - map.range,
        maxY = map.center.y + map.range,
        centerZ = map.center.z
    }
    ResetGameWorldInRange(map.center, map.range)
    
    -- Initialize camera at spawn position
    -- (We also added a fallback here in case spawnPos is missing)
    local spawnPos = data.spawnPos or vector3(map.spawns.team1.x, map.spawns.team1.y, map.spawns.team1.z)
    InitializeCamera(spawnPos)
    
    -- Set NUI focus for mouse control
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    
    -- Disable controls
    DisableControlAction(0, 1, true) -- LookLeftRight
    DisableControlAction(0, 2, true) -- LookUpDown
    DisableControlAction(0, 24, true) -- Attack
    DisableControlAction(0, 25, true) -- Aim
    DisableControlAction(0, 263, true) -- MeleeAttack1
    
    -- Show game UI
    SendNUIMessage({
        action = 'startMatch',
        team = data.team,
        teamColor = Config.UI.TeamColors["team" .. data.team],
        mapName = map.name,
        music  = map.music or "main_theme.mp3",
        mapDescription = map.description,
        commandPoints = GameState.commandPoints,
        platoons = GameState.platoons
    })
    
    -- Start match loop
    StartMatchLoop()
    
    -- Play match start sound
    PlaySoundFrontend(-1, Config.Sounds.MatchStart, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    
    SendNUIMessage({action = 'showNotification', message = "Match started! Good luck, Commander!", type = "success"})
    DebugPrint("Match started - Team: " .. data.team .. ", Map: " .. map.name)
    StartHitboxTracker()
    StartSelectionRenderer()
end

function StartMatchLoop()
    if matchLoopRunning then return end
    matchLoopRunning = true
    
    CreateThread(function()
        local syncTimer = 0 
        local lastUpdateTime = 0
        -- Debug timer to prevent console flooding (prints every 2s instead of 1s)
        local debugPrintTimer = 0 
        
        while GameState.isInMatch do
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableAllControlActions(0)
            
            local currentTime = GetGameTimer()
            
            -- Runs every 1 second (1000ms)
            if currentTime - lastUpdateTime >= 1000 then
                GameState.matchTime = GameState.matchTime + 1
                lastUpdateTime = currentTime

                -- Resource Logic
                GameState.commandPoints = GameState.commandPoints + (GameState.incomeRate / 60)
                if GameState.commandPoints > 100000 then GameState.commandPoints = 100000 end
                UpdateTimerUI()
                UpdateResourcesUI()

                -- [NEW] POPULATION TRACKER
                local alivePop = 0
                for k, v in pairs(GameState.units) do
                    if v.entity and DoesEntityExist(v.entity) then
                        if IsEntityAVehicle(v.entity) then
                            if GetVehicleBodyHealth(v.entity) > 0 and not IsEntityDead(v.entity) then alivePop = alivePop + 1 end
                        else
                            if not IsPedDeadOrDying(v.entity, true) then alivePop = alivePop + 1 end
                        end
                    end
                end
                
                SendNUIMessage({
                    action = 'updatePopulation',
                    current = alivePop,
                    max = Config.MatchSettings.MaxUnits or 20
                })

                -- [[ UI UPDATE LOGIC ]] --
                local status, err = pcall(function()
                    local platoonData = {}
                    local shouldPrintDebug = (currentTime - debugPrintTimer > 10000)
                    
                    if shouldPrintDebug then 
                        debugPrintTimer = currentTime
                        -- DEBUG 1: Check if the table even exists
                    --    DebugPrint("^3[RTS LOOP] Checking Platoons... Count: " .. (GameState.deployedPlatoons and #GameState.deployedPlatoons or "NIL") .. "^7")
                    end

                    if GameState.deployedPlatoons then
                        for i = #GameState.deployedPlatoons, 1, -1 do
                            local p = GameState.deployedPlatoons[i]
                            
                            if p and p.unitIds then
                                local aliveCount = 0
                                local totalPercentAccumulator = 0
                                local totalUnitsCount = #p.unitIds
                                if totalUnitsCount == 0 then totalUnitsCount = 1 end

                                for _, uid in ipairs(p.unitIds) do
                                    local u = GameState.units[uid]
                                    if u and u.entity and DoesEntityExist(u.entity) then
                                        local isAlive = false
                                        if IsEntityAVehicle(u.entity) then 
                                            isAlive = not IsEntityDead(u.entity) and GetVehicleBodyHealth(u.entity) > 0
                                        else 
                                            isAlive = not IsPedDeadOrDying(u.entity, true) 
                                        end

                                        if isAlive then
                                            aliveCount = aliveCount + 1
                                            local currentUnitPct = 0
                                            
                                            if IsEntityAVehicle(u.entity) then
                                                local max = (Config.Units[u.type] and Config.Units[u.type].health) or 1000.0
                                                currentUnitPct = math.floor((GetVehicleBodyHealth(u.entity) / max) * 100)
                                            else
                                                local max = GetEntityMaxHealth(u.entity)
                                                if max <= 0 then max = 100 end
                                                currentUnitPct = math.floor((GetEntityHealth(u.entity) / max) * 100)
                                            end
                                            
                                            if currentUnitPct > 100 then currentUnitPct = 100 end
                                            if currentUnitPct < 0 then currentUnitPct = 0 end
                                            totalPercentAccumulator = totalPercentAccumulator + currentUnitPct
                                        end
                                    end
                                end

                                -- [[ SAFETY & DEBUG LOGIC ]] --
                                local sTime = p.spawnTime or GetGameTimer()
                                local age = GetGameTimer() - sTime
                                
                                if shouldPrintDebug then
                                --    DebugPrint("^3[RTS LOOP] Platoon " .. p.name .. " (ID: "..p.id..") | Alive: " .. aliveCount .. "/" .. totalUnitsCount .. " | Age: " .. math.floor(age/1000) .. "s^7")
                                end

                                -- 45 Second timeout for slow loading
                                if aliveCount == 0 and (age > 45000) then
                                    if shouldPrintDebug then DebugPrint("^1[RTS LOOP] REMOVING Platoon " .. p.name .. " (Timed Out)^7") end
                                    table.remove(GameState.deployedPlatoons, i)
                                else
                                    local displayHealth = (aliveCount == 0) and 100 or math.floor(totalPercentAccumulator / totalUnitsCount)
                                    
                                    table.insert(platoonData, {
                                        uuid = p.id or 0,
                                        name = p.name or "SQUAD",
                                        icon = p.icon or "X",
                                        color = p.color or "#fff",
                                        health = displayHealth,
                                        aliveCount = (aliveCount == 0) and p.maxUnits or aliveCount,
                                        maxCount = p.maxUnits or 1
                                    })
                                end
                            else
                                if shouldPrintDebug then DebugPrint("^1[RTS LOOP] Found INVALID Platoon Data at index " .. i .. "^7") end
                            end
                        end
                    end

                    if shouldPrintDebug then
                     --   DebugPrint("^2[RTS LOOP] Sending NUI Update with " .. #platoonData .. " platoons.^7")
                    end

                    SendNUIMessage({
                        action = 'updateDeployedPlatoons',
                        platoons = platoonData
                    })
                end)

                if not status then DebugPrint("^1[RTS ERROR] UI Loop CRASHED: " .. tostring(err) .. "^7") end
            end

            -- Sync Position
            if currentTime - syncTimer >= 500 then
                local updates = {}
                local count = 0
                
                if GameState.units then
                    for unitId, unit in pairs(GameState.units) do
                        if unit.entity and DoesEntityExist(unit.entity) then
                            local pos = GetEntityCoords(unit.entity)
                            updates[unitId] = {x = pos.x, y = pos.y, z = pos.z}
                            count = count + 1
                        end
                    end
                end
                
                -- [[ Sync CPU Units to the Server so they can capture! ]] --
                if CpuBot and CpuBot.active and GameState.enemyUnits then
                    for unitId, unit in pairs(GameState.enemyUnits) do
                        if unit.entity and DoesEntityExist(unit.entity) then
                            local pos = GetEntityCoords(unit.entity)
                            updates[unitId] = {x = pos.x, y = pos.y, z = pos.z}
                            count = count + 1
                        end
                    end
                end
                
                if count > 0 then TriggerServerEvent('rts:syncUnitPositions', updates) end
                syncTimer = currentTime 
            end
            
            UpdateCamera()
            Wait(0)
        end
        matchLoopRunning = false
    end)
end

function CleanupMatch(preservePlayer)
    GameState.isInMatch = false
    GameState.matchId = nil
    GameState.team = 0
    GameState.commandPoints = 0
    GameState.matchTime = 0
    GameState.captureProgress = 0
    GameState.selectedUnits = {}
    GameState.mapBounds = nil
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
   -- RestoreMap()
   -- Robust Blip Removal --
    if GameState.objectiveBlips then
        for name, blip in pairs(GameState.objectiveBlips) do
            -- Always try to remove, DoesBlipExist check is good safety
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end
    end
    GameState.objectiveBlips = {} -- Clear the table

    -- Delete all units
    for unitId, unit in pairs(GameState.units) do
        if unit.entity and DoesEntityExist(unit.entity) then
            DeleteEntity(unit.entity)
        end
    end
    GameState.units = {}
    GameState.unitCount = 0
    
    -- Delete enemy units
    for unitId, unit in pairs(GameState.enemyUnits) do
        if unit.entity and DoesEntityExist(unit.entity) then
            DeleteEntity(unit.entity)
        end
    end
    GameState.enemyUnits = {}
    
    -- Reset camera
    if GameState.camera then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(GameState.camera, false)
        GameState.camera = nil
    end
     -- Clean up Decorative Objects
    if GameState.decorativeObjects then
        for _, obj in ipairs(GameState.decorativeObjects) do
            if DoesEntityExist(obj) then
                DeleteEntity(obj)
            end
        end
    end
    -- Reset the table
    GameState.decorativeObjects = {}
    -- Reset NUI focus
   -- SetNuiFocus(false, false)
   -- SetNuiFocusKeepInput(false)
    
    -- Re-enable controls
    EnableControlAction(0, 1, true)
    EnableControlAction(0, 2, true)
    EnableControlAction(0, 24, true)
    EnableControlAction(0, 25, true)
    EnableControlAction(0, 263, true)
    
    DebugPrint("Match cleaned up")
  --  if not preservePlayer then FullPlayerReset() end
end

function UpdateResourcesUI()
    SendNUIMessage({
        action = 'updateResources',
        commandPoints = math.floor(GameState.commandPoints),
        incomeRate = GameState.incomeRate
    })
end

function UpdateTimerUI()
    local minutes = math.floor(GameState.matchTime / 60)
    local seconds = GameState.matchTime % 60
    
    SendNUIMessage({
        action = 'updateTimer',
        time = string.format("%02d:%02d", minutes, seconds),
        captureProgress = GameState.captureProgress,
        capturingTeam = GameState.capturingTeam,
        controllingTeam = GameState.controllingTeam
    })
end

function UpdateObjectiveBlips()
    -- Add isInMatch Check
    if not GameState.isInMatch then return end 
    if not GameState.objectives then return end

    -- Initialize table if nil
    if not GameState.objectiveBlips then GameState.objectiveBlips = {} end

    for name, obj in pairs(GameState.objectives) do
        -- A. Create Blip if it doesn't exist
        if not GameState.objectiveBlips[name] or not DoesBlipExist(GameState.objectiveBlips[name]) then
            local x = obj.position.x or obj.position[1]
            local y = obj.position.y or obj.position[2]
            local z = obj.position.z or obj.position[3]

            local blip = AddBlipForCoord(x, y, z)
            SetBlipSprite(blip, 438) -- Target/Flag icon
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(name)
            EndTextCommandSetBlipName(blip)
            
            GameState.objectiveBlips[name] = blip
        end

        -- B. Update Color Logic
        local blip = GameState.objectiveBlips[name]
        
        -- [[ COLOR LOGIC ]] --
        local color = 0 -- Default 0 = White (Neutral)

        if obj.controllingTeam ~= 0 then
            -- Owned by someone
            if obj.controllingTeam == GameState.team then
                color = 3 -- Blue (My Team)
            else
                color = 1 -- Red (Enemy)
            end
        elseif obj.capturingTeam ~= 0 and obj.progress > 0 then
            -- Currently Contested/Capturing (Yellow/Orange)
            color = 46 
        else
            -- Not Controlled AND Not capturing (Progress 0)
            color = 0 -- White
        end
        
        SetBlipColour(blip, color)
    end
end

function StartFogOfWarSystem()
    CreateThread(function()
        DebugPrint("^2[RTS] Fog of War System Started^7")
        
        while GameState.isInMatch do
            -- 1. Run check 2 times per second (Optimization)
            Wait(500) 

            local sightRange = Config.MatchSettings.UnitSightRange or 120.0
             
            -- 2. Iterate through all ENEMIES
            for id, enemy in pairs(GameState.enemyUnits) do
                -- Only process if the enemy has a blip and the entity exists locally
                if enemy.blip and DoesBlipExist(enemy.blip) and enemy.entity and DoesEntityExist(enemy.entity) then
                    
                    local isVisible = false
                    local enemyPos = GetEntityCoords(enemy.entity)
                    
                    -- 3. Check against all FRIENDLY units
                    for _, friendly in pairs(GameState.units) do
                        if friendly.entity and DoesEntityExist(friendly.entity) then
                            -- Calculate distance
                            local dist = #(GetEntityCoords(friendly.entity) - enemyPos)
                            
                            -- If *ANY* friendly unit is close enough, reveal the enemy
                            if dist < sightRange then
                                isVisible = true
                                break -- We found a spotter, stop checking other friendlies for this enemy
                            end
                        end
                    end
                    
                    -- 4. Apply Visibility State
                    -- We check the current alpha to avoid spamming the native if it's already set
                    local currentAlpha = GetBlipAlpha(enemy.blip)
                    
                    if isVisible then
                        if currentAlpha == 0 then
                            SetBlipAlpha(enemy.blip, 255)
                            SetBlipDisplay(enemy.blip, 2) -- Show on Map & Minimap
                        end
                    else
                        if currentAlpha == 255 then
                            SetBlipAlpha(enemy.blip, 0)
                            SetBlipDisplay(enemy.blip, 0) -- Hide completely
                        end
                    end
                end
            end
        end
    end)
end

-- =======================================================================
-- SMART DEATH TRACKER
-- =======================================================================
CreateThread(function()
    while true do
        Wait(500) -- Check 2 times a second (Very efficient)
        
        if GameState.isInMatch then
            for unitId, unit in pairs(GameState.units) do
                local reportDeath = false
                local shouldRemove = false

                -- CASE 1: Unit completely vanished (Deleted/Despawned)
                if not DoesEntityExist(unit.entity) then
                    -- EXCEPTION: Jets/Lazars are allowed to vanish (they fly back to base)
                    if  unit.category == 'aircraft' then
                        shouldRemove = true -- Just remove from local list, NO kill reported
                    else
                        -- Everyone else: Vanishing counts as a death/loss
                        reportDeath = true
                    end
                else
                    -- CASE 2: Unit exists but is dead (Health 0)
                    local isDead = false
                    if IsEntityAVehicle(unit.entity) then
                        if GetEntityHealth(unit.entity) <= 0 or IsEntityDead(unit.entity) then isDead = true end
                    else
                        if IsPedDeadOrDying(unit.entity, true) then isDead = true end
                    end

                    if isDead then
                        reportDeath = true
                    end
                end

                -- ACTION: Report to Server
                if reportDeath then
                    -- Remove Blip Before Deleting Data
                    if unit.blip and DoesBlipExist(unit.blip) then
                        RemoveBlip(unit.blip)
                    end

                    TriggerServerEvent('rts:reportUnitDeath', unitId)
                    shouldRemove = true
                end

                -- Stop tracking this unit locally
                if shouldRemove then
                    GameState.units[unitId] = nil
                end
            end
            -- 2. CHECK ENEMY UNITS (Visual Cleanup & CPU Kill Reporting)
            for unitId, enemy in pairs(GameState.enemyUnits) do
                if enemy.entity and DoesEntityExist(enemy.entity) then
                    if IsEntityDead(enemy.entity) or GetEntityHealth(enemy.entity) <= 0 then
                        
                        -- Remove Blip Immediately
                        if enemy.blip and DoesBlipExist(enemy.blip) then
                            RemoveBlip(enemy.blip)
                            enemy.blip = nil -- Prevent trying to remove it again
                        end
                        
                        -- If we are playing against the CPU, the CPU has no client to report its own deaths.
                        -- YOUR client must tell the server to grant you the kill and the score!
                        if CpuBot and CpuBot.active then
                            TriggerServerEvent('rts:reportUnitDeath', unitId)
                            GameState.enemyUnits[unitId] = nil -- Remove locally so we don't spam the server
                        end
                        
                        -- (If it's a normal PvP match, we do nothing here and wait for the enemy 
                        -- player's client to trigger 'rts:enemyUnitDestroyed' via the server).
                    end
                end
            end
        else
            Wait(1000)
        end
    end
end)

-- =======================================================================
-- SMART NAVIGATION & ANTI-CRASH QUEUE (Replaces TaskGoToCoordAnyMeans)
-- =======================================================================
SmartNav = {
    targets = {}, -- Stores the ultimate destination for each ped
    tickets = {}  -- NEW: Stores an order ID to cancel out spammed clicks!
}

function CommandPedToMoveSafely(ped, targetPos, staggerIndex)
    if not DoesEntityExist(ped) then return end
    
    -- 1. Store their ultimate destination
    SmartNav.targets[ped] = targetPos
    
    -- 2. Generate a unique ticket for this exact order
    local currentTicket = GetGameTimer()
    SmartNav.tickets[ped] = currentTicket
    
    -- 3. Stagger logic (25ms per unit)
    local delay = (staggerIndex or 1) * 25 
    
    SetTimeout(delay, function()
        -- 4. THE SPAM SHIELD: Check if the ticket still matches! 
        -- If the player clicked again during this delay, the ticket changed, so we safely ignore this old command!
        if SmartNav.tickets[ped] == currentTicket then
            if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                local myPos = GetEntityCoords(ped)
                local dist = #(targetPos - myPos)
                local nextWaypoint = targetPos
                
                -- CHUNKING LOGIC
                if dist > 50.0 then
                    local dir = (targetPos - myPos) / dist
                    nextWaypoint = myPos + (dir * 50.0)
                end
                
                ClearPedTasks(ped)
                TaskGoToCoordAnyMeans(ped, nextWaypoint.x, nextWaypoint.y, nextWaypoint.z, 2.0, 0, false, 4981292, 0.0)
            end
        end
    end)
end

CreateThread(function()
    while true do
        Wait(2500) -- Sweep the battlefield every 2.5 seconds
        
        if GameState and GameState.isInMatch then
            local staggerCounter = 0
            
            for ped, finalPos in pairs(SmartNav.targets) do
                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                    local myPos = GetEntityCoords(ped)
                    local dist = #(finalPos - myPos)
                    
                    if dist < 4.0 then
                        -- They reached the final destination! Stop tracking them.
                        SmartNav.targets[ped] = nil
                        ClearPedTasks(ped)
                    else
                        -- If their speed is low, they either finished their 50m chunk or got stuck.
                        -- Give them the next 50m waypoint.
                        if GetEntitySpeed(ped) < 0.5 then
                            staggerCounter = staggerCounter + 1
                            CommandPedToMoveSafely(ped, finalPos, staggerCounter)
                        end
                    end
                else
                    -- Cleanup dead or deleted peds from memory
                    SmartNav.targets[ped] = nil 
                end
            end
        else
            Wait(2000)
        end
    end
end)

function FullPlayerReset()
    -- Fixed indentation for FullPlayerReset
    local ped = PlayerPedId()
    DebugPrint("Starting Full Player Reset...")

    -- Random distance (using sqrt for even distribution inside the circle) and random angle
    local dist = 300.0 * math.sqrt(math.random())
    local angle = math.random() * (2 * math.pi)

    -- Calculate new X and Y based on the center point (-247.76, 6331.23)
    local newX = -247.76 + (dist * math.cos(angle))
    local newY = 6331.23 + (dist * math.sin(angle))

    -- Teleport instantly to the new coords at Z = 1000.0
    SetEntityCoords(ped, newX, newY, 1000.0, false, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityHasGravity(ped, false)
    SetEntityInvincible(ped, true)
    
    PreMatchLocation = nil 
    DebugPrint("^2[RTS] Dedicated Player returned to the Void.^7")

    -- Camera & Focus Cleanup
    RenderScriptCams(false, false, 0, true, true)
    if GameState.camera then
        DestroyCam(GameState.camera, false)
        GameState.camera = nil
    end
    ClearFocus()
end

-- Objective System Thread
function StartObjectiveSystem()
    CreateThread(function()
        DebugPrint("[RTS] Objective System Started") 
        
        while GameState.isInMatch do
            Wait(0) 
            
            if GameState.objectives then
                local uiData = {}
                
                for name, obj in pairs(GameState.objectives) do
                    local x = obj.position.x or obj.position[1]
                    local y = obj.position.y or obj.position[2]
                    local z = obj.position.z or obj.position[3]
                    
                    if x and y and z then
                        local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, z + 100.0, 0)
                        local drawZ = foundGround and groundZ or z
                        drawZ = z
                        -- [[ NEW PERSPECTIVE COLOR LOGIC ]] --
                        -- Default Neutral (White)
                        local r, g, b = 255, 255, 255 
                        
                        -- Check Owner relative to ME
                        if obj.controllingTeam ~= 0 then
                            if obj.controllingTeam == GameState.team then
                                r, g, b = 0, 168, 255 -- Ally Blue (#00a8ff)
                            else
                                r, g, b = 255, 71, 87 -- Enemy Red (#ff4757)
                            end
                        -- Check Capper relative to ME (if currently contested)
                        elseif obj.capturingTeam ~= 0 then
                            if obj.capturingTeam == GameState.team then
                                r, g, b = 0, 168, 255 -- Ally Blue
                            else
                                r, g, b = 255, 71, 87 -- Enemy Red
                            end
                        end

                        -- Draw Markers
                        local dist = #(GetGameplayCamCoord() - vector3(x, y, drawZ))
                      --  if dist < 300.0 then
                            DrawMarker(1, x, y, drawZ, 
                                0,0,0, 0,0,0, 
                                (obj.radius or 10.0) * 2.0, (obj.radius or 10.0) * 2.0, 1.0, 
                                r, g, b, 100, false, false, 2, false, nil, nil, false
                            )
                        --    DrawMarker(0, x, y, drawZ + 2.5,
                        --        0,0,0, 0,0,0,
                        --        1.0, 1.0, 1.0,
                        --        r, g, b, 200, true, true, 2, false, nil, nil, false
                        --    )
                     --   end

                        local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(x, y, drawZ + 4.0)
                        
                        table.insert(uiData, {
                            name = name,
                            x = screenX, 
                            y = screenY,
                            isOnScreen = onScreen,
                            progress = obj.progress or 0,
                            owner = obj.controllingTeam or 0,
                            capper = obj.capturingTeam or 0,
                            type = obj.type,
                            isContested = (obj.progress > 0 and obj.progress < 100)
                        })
                    end
                end
                
              --  if GetGameTimer() % 50 == 0 then
                    SendNUIMessage({ action = 'updateObjectiveUI', objectives = uiData })
             --   end
                --if GetGameTimer() % 50 == 0 then
                   UpdateObjectiveBlips()
               -- end
            end
        end
    end)
end

function WreckScanner(center, scanRadius)
CreateThread(function()
    while GameState.isInMatch do
        Wait(10000) -- Scan every 10 seconds

        local playerPed = PlayerPedId()
        local playerCoords = center
        
        -- Get all vehicles
        local vehicles = GetGamePool('CVehicle')

        for _, veh in ipairs(vehicles) do
            local vehCoords = GetEntityCoords(veh)
            local dist = #(playerCoords - vehCoords)

            if dist < scanRadius then
                -- 1. DESTRUCTION CHECKS (Is it a wreck?)
                local isDead = IsEntityDead(veh)
                local bodyHealth = GetVehicleBodyHealth(veh)
                
                local isDestroyed = (isDead or bodyHealth <= 0.0 )

                -- 2. VELOCITY CHECK (Is it stopped?)
                -- We get the speed of the entity. 
                -- If it is moving faster than 0.1 m/s, it is still rolling/flying.
                local speed = GetEntitySpeed(veh)
                local isStopped = (speed < 0.1)

                -- ONLY proceed if it is BOTH destroyed AND stopped
                if isDestroyed and isStopped then
                    
                    -- 3. FREEZE & GHOST (Decor Mode)
                    if not IsEntityStatic(veh) then
                        FreezeEntityPosition(veh, true)
                        SetEntityCollision(veh, false, false) -- Ghost mode
                        
                        -- Optional: Turn off engine/lights to really sell the "dead" look
                        SetVehicleEngineOn(veh, false, true, true) 
                        SetVehicleLights(veh, 1) -- 1 = Off
                    end

                    -- 4. REMOVE STUCK PEDS
                    -- Loop all seats to clear bodies
                    for seat = -1, 6 do
                        local occupant = GetPedInVehicleSeat(veh, seat)
                        if DoesEntityExist(occupant) and not IsPedAPlayer(occupant) then
                            DeleteEntity(occupant)
                        end
                    end
                    
                end
            end
        end
    end
end)
end

function StartCpuBotBrain(mirroredPlatoons, botId, playerLevel)
    
    local saveChance = 70   
    local aggroRange = 80.0 
    local bName = "A.I. COMMANDER" 
    
    if Config.Bots then
        for _, b in ipairs(Config.Bots) do
            if b.id == botId then
                saveChance = b.saveChance or 70
                aggroRange = b.aggroRange or 80.0
                bName = b.name or "A.I. COMMANDER" 
                break
            end
        end
    end

    local safeLevel = playerLevel or 1
    local cooldownMultiplier = 1.0
    
    if safeLevel == 1 then
        cooldownMultiplier = 2.0 
    end

    DebugPrint("^5[CPU BRAIN] Commander " .. tostring(botId) .. " ("..bName..") online. Economy: " .. saveChance .. "% | Aggro: " .. aggroRange .. "m^7")

    CpuBot.active = true
    CpuBot.commandPoints = Config.MatchSettings.CommandPointsStart or 1500
    CpuBot.cooldowns = {0,0,0,0,0}
    CpuBot.targetPlatoon = nil

    CpuBot.botId = botId
    CpuBot.botName = bName
    CpuBot.chatFlags = { start = false, timeWarning = false, nearWin = false, nearLose = false }

    CreateThread(function()
        Wait(3000)
        TriggerBotChat(CpuBot.botId, CpuBot.botName, "start")
    end)

    CpuBot.platoons = {}
    for slotStr, pData in pairs(mirroredPlatoons or {}) do
        local validUnits = {}
        local aiCost = 0
        local aiCount = 0
        
        for _, uData in ipairs(pData.units or {}) do
            local uConf = Config.Units[uData.type]
            if uConf and not uConf.noai then
                table.insert(validUnits, uData)
                aiCost = aiCost + (uConf.cost * (uData.count or 1))
                aiCount = aiCount + (uData.count or 1)
            end
        end
        
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
            
            CpuBot.commandPoints = CpuBot.commandPoints + ((Config.MatchSettings.CommandPointsPerMinute or 150) / 60)
            for i = 1, 5 do if CpuBot.cooldowns[i] > 0 then CpuBot.cooldowns[i] = CpuBot.cooldowns[i] - 1 end end
            
            if not CpuBot.chatFlags.timeWarning then
                local timeLeft = (Config.MatchSettings.MatchDuration or 600) - GameState.matchTime
                if timeLeft <= 60 and timeLeft > 0 then
                    CpuBot.chatFlags.timeWarning = true
                    TriggerBotChat(CpuBot.botId, CpuBot.botName, "timeWarning")
                end
            end

            if GameState.objectives then
                for _, obj in pairs(GameState.objectives) do
                    if obj.type == "victory" and obj.progress >= 85 then
                        if obj.capturingTeam == 2 and not CpuBot.chatFlags.nearWin then
                            CpuBot.chatFlags.nearWin = true
                            TriggerBotChat(CpuBot.botId, CpuBot.botName, "nearWin")
                        elseif obj.capturingTeam == 1 and not CpuBot.chatFlags.nearLose then
                            CpuBot.chatFlags.nearLose = true
                            TriggerBotChat(CpuBot.botId, CpuBot.botName, "nearLose")
                        end
                    end
                end
            end

            local now = GetGameTimer()
            
            if now - CpuBot.lastThink > 3000 then 
                CpuBot.lastThink = now
                
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
                        
                        CpuBot.targetPlatoon = (math.random(1, 100) <= saveChance) and availableSlots[1] or availableSlots[math.random(1, #availableSlots)]
                    end
                end

                if CpuBot.targetPlatoon then
                    local pData = CpuBot.platoons[tostring(CpuBot.targetPlatoon)] or CpuBot.platoons[tonumber(CpuBot.targetPlatoon)]
                    local pCost = pData.totalCost or 0
                    local pCount = pData.unitCount or 1
                    
                    if CpuBot.commandPoints >= pCost then
                        local currentCpuPop = 0
                        if GameState.enemyUnits then
                            for _, _ in pairs(GameState.enemyUnits) do currentCpuPop = currentCpuPop + 1 end
                        end
                        
                        local maxPop = Config.MatchSettings.MaxUnits or 20
                        
                        if currentCpuPop + pCount <= maxPop then
                            CpuBot.commandPoints = CpuBot.commandPoints - pCost
                            local baseCooldown = Config.MatchSettings.RespawnCooldown or 30
                            CpuBot.cooldowns[CpuBot.targetPlatoon] = math.floor(baseCooldown * cooldownMultiplier)
                            TriggerServerEvent('rts:server:cpuSpawnPlatoon', GameState.matchId, CpuBot.targetPlatoon)
                            CpuBot.targetPlatoon = nil 
                        end
                    end
                end

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
                
                local fallbackBase = vector3(mapConfig.spawns.team1.x, mapConfig.spawns.team1.y, mapConfig.spawns.team1.z)
                if not mainObjPos then mainObjPos = fallbackBase end

                if GameState.enemyUnits then
                    for uIdStr, eUnit in pairs(GameState.enemyUnits) do
                        if DoesEntityExist(eUnit.entity) and GetEntityHealth(eUnit.entity) > 0 then
                            local myPos = GetEntityCoords(eUnit.entity)
                            local numId = tonumber(uIdStr) or math.random(1,100)
                            
                            local closestEnemyDist, closestEnemyEnt = aggroRange, nil
                            for _, pUnit in pairs(GameState.units) do
                                if DoesEntityExist(pUnit.entity) and GetEntityHealth(pUnit.entity) > 0 then
                                    local dist = #(myPos - GetEntityCoords(pUnit.entity))
                                    if dist < closestEnemyDist then 
                                        closestEnemyDist = dist
                                        closestEnemyEnt = pUnit.entity 
                                    end
                                end
                            end
                            
                            if closestEnemyEnt then
                                
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
                                        ForceGroundCombat(eUnit.entity)
                                        Wait(0)
                                        TaskCombatPed(driver, combatTarget, 0, 16) 
                                    end
                                    
                                    local maxSeats = GetVehicleMaxNumberOfPassengers(eUnit.entity)
                                    for seat = 0, maxSeats - 1 do
                                        local passenger = GetPedInVehicleSeat(eUnit.entity, seat)
                                        if passenger ~= 0 then
                                            TaskCombatPed(passenger, combatTarget, 0, 16)
                                        end
                                    end
                                else
                                    TaskCombatPed(eUnit.entity, combatTarget, 0, 16)
                                end
                            else
                                
                                local targetBasePos = mainObjPos

                                if numId % 3 == 0 and #sideObjs > 0 then
                                    if #unownedSideObjs > 0 then
                                        targetBasePos = unownedSideObjs[(numId % #unownedSideObjs) + 1]
                                    else
                                        targetBasePos = sideObjs[(numId % #sideObjs) + 1]
                                    end
                                end

                                local angle = numId * 137.5 
                                local radius = 3.0 + ((numId % 6) * 3.0) 
                                if IsEntityAVehicle(eUnit.entity) then radius = radius * 1.5 end 
                                
                                local offsetX = math.cos(math.rad(angle)) * radius
                                local offsetY = math.sin(math.rad(angle)) * radius
                                local finalTargetPos = vector3(targetBasePos.x + offsetX, targetBasePos.y + offsetY, targetBasePos.z)

                                if IsEntityAVehicle(eUnit.entity) then
                                    local driver = GetPedInVehicleSeat(eUnit.entity, -1)
                                    if driver ~= 0 then 
                                        FixEngineAndSecurePed(eUnit.entity, driver)
                                        ClearPedTasks(driver)
                                        SetVehicleEngineOn(eUnit.entity, true, true, false)
                                        DisablePedReactions(driver, 5000)
                                        TaskVehicleDriveToCoord(driver, eUnit.entity, finalTargetPos.x, finalTargetPos.y, finalTargetPos.z, 30.0, 0, GetEntityModel(eUnit.entity), 4981292, 5.0, true) 
                                    end
                                else
                                    CommandPedToMoveSafely(eUnit.entity, finalTargetPos, numId % 40)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

function TriggerBotChat(botId, botName, triggerType)
    local persona = Config.BotChatter[botId] or Config.BotChatter["default"]
    local lines = persona[triggerType] or Config.BotChatter["default"][triggerType]
    
    if lines and #lines > 0 then
        local message = lines[math.random(1, #lines)]
        local typeDelay = math.random(1500, 4000)
        
        SetTimeout(typeDelay, function()
            if GameState and GameState.isInMatch then
                if CpuBot and CpuBot.active then
                    TriggerServerEvent('rts:server:botChatMessage', GameState.matchId, botName, message)
                end
            end
        end)
    end
end

RegisterNetEvent('rts:client:receiveChatMessage')
AddEventHandler('rts:client:receiveChatMessage', function(senderName, message, channelType)
    SendNUIMessage({
        action = 'addChatMessage',
        sender = senderName,
        message = message,
        channel = channelType or "match"
    })
    PlaySoundFrontend(-1, "Click", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
end)

RegisterNetEvent('rts:client:cpuDoSpawn', function(unitData)
    local uConf = Config.Units[unitData.type]
    if not uConf then return end
    
    local teamKey, modelName = "team2", uConf.model or "s_m_y_marine_01"
    if uConf.category == "infantry" and uConf.teamModels and uConf.teamModels[teamKey] then modelName = uConf.teamModels[teamKey] end

    local modelHash = GetHashKey(modelName)
    RequestModel(modelHash) while not HasModelLoaded(modelHash) do Wait(10) end

    local entity = nil
    
    if uConf.category == "vehicles" or uConf.category == "helicopters" or uConf.category == "aircraft" then
        entity = CreateVehicle(modelHash, unitData.position.x, unitData.position.y, unitData.position.z + 1.0, 0.0, true, true)
        
        local teamKey = "team2" 
        if uConf.teamColors and uConf.teamColors[teamKey] then
            local colors = uConf.teamColors[teamKey]
            SetVehicleColours(entity, colors[1], colors[2])
        end
        
        SetVehicleEngineCanDegrade(entity, false)
        SetDisableVehicleEngineFires(entity, false)
        SetEntityAsMissionEntity(entity, true, true)
        SetVehicleStrong(entity, true)
        SetVehicleEngineOn(entity, true, true, false)
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)
        SetVehicleOnGroundProperly(entity)

        if uConf.teamColors and uConf.teamColors[teamKey] then
            local colors = uConf.teamColors[teamKey]
            SetVehicleColours(entity, colors[1], colors[2])
        end

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

        if uConf.model == 'rhino' or uConf.model == 'khanjali' then
            StartTankHullLogic(entity)
            RestrictToGround(entity)
        end

    else
        entity = CreatePed(4, modelHash, unitData.position.x, unitData.position.y, unitData.position.z + 1.0, 0.0, true, true)
        SetEntityAsMissionEntity(entity, true, true)
        
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

    if DoesEntityExist(entity) then
        if uConf.health then
            SetEntityMaxHealth(entity, uConf.health)
            SetEntityHealth(entity, uConf.health)
            SetPedArmour(entity, 0)
            
            if IsEntityAVehicle(entity) then
                SetVehicleBodyHealth(entity, uConf.health + 0.0)
            end
        end
        
        local blip = CreateUnitBlip(entity, 2, uConf.category, uConf.blip or nil, false)
        GameState.enemyUnits[unitData.unitId] = { id = unitData.unitId, team = 2, type = unitData.type, entity = entity, blip = blip }
    end
    
    SetModelAsNoLongerNeeded(modelHash)
end)
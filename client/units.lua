local RESET_TIME = 3000    
local PEDS_PER_LINE = 5
local GAP_SIDE = 1.5
local GAP_BACK = 2.0

carTrailer = {}

lastOrderTime = 0
formationIndex = 0
anchorPos = nil      
anchorHeading = 0.0  

LazarFormation = {
    lastTime = 0,
    index = 0
}

V_OFFSETS = {
    [0] = vector2(0.0,  -50.0),   
    [1] = vector2(18.0, -62.0),   
    [2] = vector2(-18.0, -62.0),  
    [3] = vector2(36.0, -74.0),   
    [4] = vector2(-36.0, -74.0),  
}

function CommandPedToMarch(ped, targetX, targetY, targetZ)
    local currentTime = GetGameTimer()
    local isNewGroup = (currentTime - lastOrderTime) > RESET_TIME

    if isNewGroup then
        
        formationIndex = 1
        
        anchorPos = vector3(targetX, targetY, targetZ)
        
        local pedPos = GetEntityCoords(ped)
        local dx = targetX - pedPos.x
        local dy = targetY - pedPos.y
        anchorHeading = GetHeadingFromVector_2d(dx, dy)
    else
        
        formationIndex = formationIndex + 1
    end

    lastOrderTime = currentTime

    local rad = math.rad(anchorHeading)
    local forwardX = -math.sin(rad)
    local forwardY =  math.cos(rad)
    local rightX   =  math.cos(rad)
    local rightY   =  math.sin(rad)

    local colIndex = (formationIndex - 1) % PEDS_PER_LINE
    local rowIndex = math.floor((formationIndex - 1) / PEDS_PER_LINE)

    local sideOffset = (colIndex - ((PEDS_PER_LINE - 1) / 2)) * GAP_SIDE
    local backOffset = -(rowIndex * GAP_BACK)

    local finalX = anchorPos.x + (rightX * sideOffset) + (forwardX * backOffset)
    local finalY = anchorPos.y + (rightY * sideOffset) + (forwardY * backOffset)

    local targetVector = vector3(finalX, finalY, targetZ)
    
    CommandPedToMoveSafely(ped, targetVector, formationIndex)
end

function SetupRelationshipGroups()
    
    local team1Hash = GetHashKey("RTS_TEAM_1")
    local team2Hash = GetHashKey("RTS_TEAM_2")
    
    AddRelationshipGroup("RTS_TEAM_1", team1Hash)
    AddRelationshipGroup("RTS_TEAM_2", team2Hash)

    SetRelationshipBetweenGroups(0, team1Hash, team1Hash) 
    SetRelationshipBetweenGroups(255, team1Hash, team2Hash) 

    SetRelationshipBetweenGroups(0, team2Hash, team2Hash) 
    SetRelationshipBetweenGroups(255, team2Hash, team1Hash) 
    
    DebugPrint("^2[RTS] Groups Configured: TEAM 1 vs TEAM 2^7")
end

function CreateUnitBlip(entity, team, category, customSprite, isHidden)
    local blip = AddBlipForEntity(entity)
    
    local sprite = 1 
    if category == "vehicles" then sprite = 421 
    elseif category == "helicopters" then sprite = 43 
    elseif category == "aircraft" then sprite = 16 
    elseif category == "infantry" then sprite = 1 
    end
    
    if customSprite then sprite = customSprite end
    SetBlipSprite(blip, sprite)
    
    local color = (team == GameState.team) and 3 or 1
    SetBlipColour(blip, color)
    
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, true) 

    if isHidden then
        SetBlipAlpha(blip, 0)       
        SetBlipDisplay(blip, 0)     
    else
        SetBlipAlpha(blip, 255)     
        SetBlipDisplay(blip, 2)     
    end
    
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Unit")
    EndTextCommandSetBlipName(blip)
    
    return blip
end

function SpawnMapDecorations(mapName)
    local mapData = Config.Maps[mapName]
    
    if not mapData or not mapData.decorativeObjects then return end

    DebugPrint("^2[RTS] Spawning decorative entities for " .. mapName .. "^7")

    for _, objData in ipairs(mapData.decorativeObjects) do
            if objData.net == nil or objData.net == false or (objData.net == true and GameState.isHost) then            local modelHash = type(objData.model) == "string" and GetHashKey(objData.model) or objData.model
            
            RequestModel(modelHash)
            local timeout = 0
            while not HasModelLoaded(modelHash) and timeout < 1000 do 
                Wait(10)
                RequestModel(modelHash)
                timeout = timeout + 1
            end

            if HasModelLoaded(modelHash) then
                local entity

                if IsModelAVehicle(modelHash) then
                    
                    entity = CreateVehicle(modelHash, objData.x, objData.y, objData.z, objData.h or 0.0, objData.net or false, objData.net or false)

                    SetVehicleDoorsLocked(entity, 2) 
                    SetVehicleDoorsLockedForAllPlayers(entity, true)
                    SetVehicleEngineOn(entity, false, true, true)
                    SetVehicleDirtLevel(entity, 0.0)
                else
                    
                    entity = CreateObject(modelHash, objData.x, objData.y, objData.z, objData.net or false, objData.net or false, false)
                    SetEntityHeading(entity, objData.h or 0.0)
                end

                SetEntityCoordsNoOffset(entity, objData.x, objData.y, objData.z, true, true, true)
                SetEntityHeading(entity, objData.h or 0.0)

                FreezeEntityPosition(entity, true)  
                SetEntityInvincible(entity, true)    
                SetEntityCanBeDamaged(entity, false) 
                SetEntityCollision(entity, true, true) 

                SetEntityAsMissionEntity(entity, true, true)

                table.insert(GameState.decorativeObjects, entity)

                SetModelAsNoLongerNeeded(modelHash)
            else
                DebugPrint("^1[RTS ERROR] Failed to load model: " .. tostring(objData.model) .. "^7")
            end
        end
    end
end

local isHeliInFlight = false
local reachedDropPoint = false

function CreateArcadeDrop(targetCoords, mapCenter, team)
    
    if isHeliInFlight then
        while not reachedDropPoint do
            Wait(100) 
        end
        return 
    end

    isHeliInFlight = true
    reachedDropPoint = false

    local directionFromCenter = (targetCoords - mapCenter)
    local normalizedDir = directionFromCenter / #directionFromCenter
    local spawnDistance = 70.0 
    local spawnCoords = targetCoords + (normalizedDir * spawnDistance)
    local flightHeight = 30.0
    
    local currentPos = vector3(spawnCoords.x, spawnCoords.y, targetCoords.z + flightHeight)
    local targetPos = vector3(targetCoords.x, targetCoords.y, targetCoords.z + flightHeight)

    local model = `cargobob2`
    if team == 1 or team == "1" then 
        local model = `cargobob`
    end
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    local heli = CreateVehicle(model, currentPos.x, currentPos.y, currentPos.z, 0.0, false, false)
    SetEntityInvincible(heli, true)
    FreezeEntityPosition(heli, true)
    SetEntityCollision(heli, false, false)
    SetVehicleEngineOn(heli, true, true, false)
    SetHeliBladesFullSpeed(heli)
    
    local heading = GetHeadingFromVector_2d(targetPos.x - currentPos.x, targetPos.y - currentPos.y)
    SetEntityHeading(heli, heading)

    local steps = 150 
    for i = 0, steps do
        local lerpPct = i / steps
        local newCoords = currentPos + (targetPos - currentPos) * lerpPct
        SetEntityCoordsNoOffset(heli, newCoords.x, newCoords.y, newCoords.z, true, false, false)
        SetHeliBladesFullSpeed(heli)
        Wait(1)
    end

    local dropHeight = targetCoords.z + 5.0
    while (GetEntityCoords(heli).z - dropHeight) > 0.5 do
        local c = GetEntityCoords(heli)
        SetEntityCoordsNoOffset(heli, c.x, c.y, c.z - 0.5, true, false, false)
        SetHeliBladesFullSpeed(heli)
        Wait(3)
    end

    reachedDropPoint = true 
    isHeliInFlight = false
    
    Wait(500) 

    CreateThread(function()
        local startHeading = GetEntityHeading(heli)
        local targetHeading = startHeading + 180.0
        local climbRate = 0.2
        local turnRate = 0.8
        local moveRate = 0.5

        for i = 1, 500 do 
            local currentCoords = GetEntityCoords(heli)
            local currentHeading = GetEntityHeading(heli)
            
            SetHeliBladesFullSpeed(heli)
            
            if math.abs(currentHeading - targetHeading) > 0.5 then
                SetEntityHeading(heli, currentHeading + turnRate)
            end

            local newForward = GetEntityForwardVector(heli)
            local nextPos = currentCoords + (newForward * moveRate) + vector3(0.0, 0.0, climbRate)
            SetEntityCoordsNoOffset(heli, nextPos.x, nextPos.y, nextPos.z, true, false, false)
            
            moveRate = moveRate + 0.002
            Wait(1)
        end

        DeleteEntity(heli)
        SetModelAsNoLongerNeeded(model)
        
        isHeliInFlight = false
        reachedDropPoint = false
    end)

    return 
end

function PlayObeyAttack(ped)
    if not DoesEntityExist(ped) then return end
    if isProxyBusy then return end 

    local playerCoords = GetEntityCoords(PlayerPedId())
    local pedCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - pedCoords)

    if distance < 50.0 then
        
        local normalAttackLines = {
            "FIGHT",
        }
        local randomLine = normalAttackLines[math.random(1, #normalAttackLines)]
        PlayAmbientSpeech1(ped, randomLine, "SPEECH_PARAMS_FORCE_SHOUTED")
    else
        
        PlayProxySpeech("ATTACK")
    end
end

function PlayObeyMove(ped)
    if not DoesEntityExist(ped) then return end
    if isProxyBusy then return end 

    local playerCoords = GetEntityCoords(PlayerPedId())
    local pedCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - pedCoords)

    if distance < 50.0 then
        
        local normalMoveLines = {
            "CHALLENGE_ACCEPTED_GENERIC"
        }
        local randomLine = normalMoveLines[math.random(1, #normalMoveLines)]
        PlayAmbientSpeech1(ped, randomLine, "SPEECH_PARAMS_FORCE_SHOUTED_CLEAR")
    else
        
        PlayProxySpeech("MOVE")
    end
end

function WatchPedVehicle(ped)
    if not DoesEntityExist(ped) then return end
    
    CreateThread(function()
        
        Wait(1000) 

        while DoesEntityExist(ped) do
            Wait(1000) 

            local veh = GetVehiclePedIsIn(ped, false)

            if not veh or veh == 0 or not DoesEntityExist(veh) then
                DeleteEntity(ped)
                break
            end

            local isDead = IsEntityDead(veh) 
            local bodyHealth = GetVehicleBodyHealth(veh)

            if isDead then
                DeleteEntity(ped)
                break
            end

            if bodyHealth <= 0.0 then
                DeleteEntity(ped)
                break
            end

            local driver = GetPedInVehicleSeat(veh, -1)
            if not driver or driver == 0 or IsPedDeadOrDying(driver, true) then
                if driver ~= ped then
                    DeleteEntity(ped)
                    break
                end
            end
        end
    end)
end

function WatchPedonFoot(ped)
    if not DoesEntityExist(ped) then return end

    local _, originalWeaponHash = GetCurrentPedWeapon(ped, true)
    CreateThread(function()
        while DoesEntityExist(ped) do
            Wait(3000) 

            local _, currentWeaponHash = GetCurrentPedWeapon(ped, true)
            local unarmedHash = GetHashKey("WEAPON_UNARMED") 

            if currentWeaponHash == unarmedHash then
                
                GiveWeaponToPed(ped, originalWeaponHash, 5000, false, true)
                MakeAgressive(ped)
                ClearPedTasks(ped)
                
                local bestWeaponHash = GetBestPedWeapon(ped, false)

                SetCurrentPedWeapon(ped, bestWeaponHash, true)
            end

        end
    end)
end

function ClearNPCsFromVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return end

    for seat = -1, 14 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if DoesEntityExist(ped) then
            
            if not IsPedAPlayer(ped) then
                Wait(100)
                
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
            end
        end
    end
end

function WatchVehicle(veh)
    if not DoesEntityExist(veh) then return end

    CreateThread(function()
        local model = GetEntityModel(veh)
        local isHeli = IsThisModelAHeli(model)
        local hasTakenOff = false 
        
        local cachedOccupants = {} 
        for i = -1, 14 do
            local ped = GetPedInVehicleSeat(veh, i)
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                table.insert(cachedOccupants, ped)
            end
        end

        while DoesEntityExist(veh) and not IsEntityDead(veh) do
            Wait(500) 

            if DoesEntityExist(veh) then
                
                SetVehicleHandlingFloat(veh, 'CHandlingData', 'fWeaponDamageMult', 0.3)
                
                SetVehicleHandlingFloat(veh, 'CHandlingData', 'fCollisionDamageMult', 0.0)

                if GetVehicleMod(veh, 16) ~= -1 then
                    SetVehicleMod(veh, 16, -1, false)
                end

                SetVehicleDamageModifier(veh, 0.3)
                
                local currentBody = GetVehicleBodyHealth(veh)
                local currentEngine = GetVehicleEngineHealth(veh)
                local height = GetEntityHeightAboveGround(veh) 
                local shouldDestroy = false

                if isHeli then
                    if not hasTakenOff then
                        if height > 4.0 then hasTakenOff = true end
                    else
                        if GetHeliMainRotorHealth(veh) < 1.0 or GetHeliTailRotorHealth(veh) < 1.0 then 
                            shouldDestroy = true 
                        end
                        if currentEngine <= 0 then shouldDestroy = true end
                        if height < 1.5 then shouldDestroy = true end
                    end
                end

                if currentBody <= 100.0 then shouldDestroy = true end

                if shouldDestroy then
                    SetEntityProofs(veh, false, false, false, false, false, false, false, false)
                    local coords = GetEntityCoords(veh)
                    
                    for _, ped in ipairs(cachedOccupants) do
                        if DoesEntityExist(ped) then
                            SetEntityAsMissionEntity(ped, true, true)
                            DeleteEntity(ped)
                        end
                    end

                    AddExplosion(coords.x, coords.y, coords.z, 9, 100.0, true, false, 1.0) 
                    SetVehicleEngineHealth(veh, -4000.0)
                    SetVehicleBodyHealth(veh, -4000.0)
                    SetVehicleExplodesOnHighExplosionDamage(veh, true)
                    ExplodeVehicle(veh, true, false)
                    
                    print('exploded debug 1 (Unit Destroyed)')
                    break 
                
                else
                    if currentEngine < 800.0 then SetVehicleEngineHealth(veh, 1000.0) end
                    if GetVehiclePetrolTankHealth(veh) < 800.0 then SetVehiclePetrolTankHealth(veh, 1000.0) end
                    for i = 0, 7 do 
                        if IsVehicleTyreBurst(veh, i, false) then SetVehicleTyreFixed(veh, i) end 
                    end
                    if not GetIsVehicleEngineRunning(veh) then
                        SetVehicleEngineOn(veh, true, true, true)
                        SetVehicleUndriveable(veh, false)
                    end
                end

                local driver = GetPedInVehicleSeat(veh, -1)
                if not DoesEntityExist(driver) or IsPedDeadOrDying(driver, true) then
                     local coords = GetEntityCoords(veh)
                     
                     for _, ped in ipairs(cachedOccupants) do
                        if DoesEntityExist(ped) then
                            SetEntityAsMissionEntity(ped, true, true)
                            DeleteEntity(ped)
                        end
                     end
                     SetEntityProofs(veh, false, false, false, false, false, false, false, false)
                     AddExplosion(coords.x, coords.y, coords.z, 9, 100.0, true, false, 1.0)
                     SetVehicleEngineHealth(veh, -4000.0)
                     SetVehicleBodyHealth(veh, -4000.0)
                     ExplodeVehicle(veh, true, false)
                     print('exploded debug 2 (Driver Gone)')
                     break
                end
            end
        end
        
        if not DoesEntityExist(veh) or IsEntityDead(veh) then
            for _, ped in ipairs(cachedOccupants) do
                if DoesEntityExist(ped) then
                    SetEntityAsMissionEntity(ped, true, true)
                    DeleteEntity(ped)
                end
            end
        end
    end)
end

function StartTrailerWatch(vehicle, trailer, maxHealth)
    Citizen.CreateThread(function()
 
        while true do
            Wait(2000) 
            
            local destroyAll = false

            if not DoesEntityExist(vehicle) then
                destroyAll = true
                DebugPrint("^1[RTS] Main Vehicle of the trailer Missing -> Destroying^7")
            elseif trailer and not DoesEntityExist(trailer) then
                
            else
                
                local trailerBody = GetVehicleBodyHealth(trailer)

                    if trailerBody < maxHealth then
                    
                    local damageAmount = maxHealth - trailerBody
                    
                    local currentCarHealth = GetVehicleBodyHealth(vehicle)
                    local newCarHealth = currentCarHealth - damageAmount

                    SetVehicleBodyHealth(vehicle, newCarHealth)

                    SetVehicleBodyHealth(trailer, maxHealth)
                    SetVehicleEngineHealth(trailer, maxHealth) 
                    
                    DebugPrint(string.format("^3[RTS] Transferred %.1f damage from Trailer to Car. Car Health: %.1f^7", damageAmount, newCarHealth))
                end

                if GetVehicleBodyHealth(vehicle) <= 100 then
                    destroyAll = true
                    DebugPrint("^1[RTS] Main Vehicle Health Critical -> Destroying Both^7")
                end
            end

            if destroyAll then
                SetEntityProofs(target, false, false, false, false, false, false, false, false)
                 
                 local function Nuke(target)
                    if DoesEntityExist(target) then
                        local coords = GetEntityCoords(target)
                        ClearNPCsFromVehicle(target)
                        AddExplosion(coords.x, coords.y, coords.z, 9, 100.0, true, false, 1.0)
                        
                        SetVehicleEngineHealth(target, -4000.0)
                        SetVehicleBodyHealth(target, -4000.0)
                        SetVehicleExplodesOnHighExplosionDamage(target, true)
                        ExplodeVehicle(target, true, false)
                    end
                 end

                 Nuke(vehicle)
                 if trailer then Nuke(trailer) end
                 
                 DebugPrint('exploded debug 5')
                 break 
            end
        end
    end)
end

function StartAntiAirAutoCombat(antiAirTrailer)
    DebugPrint("[AA] StartAntiAirAutoCombat called:", antiAirTrailer)

    Citizen.CreateThread(function()
        while DoesEntityExist(antiAirTrailer) and GetVehicleBodyHealth(antiAirTrailer) > 100 do
            Citizen.Wait(1000)

            local driverPed = GetPedInVehicleSeat(antiAirTrailer, -1)
            if driverPed == 0 or not DoesEntityExist(driverPed) then
                DebugPrint("[AA] No valid driver ped, stopping thread")
                break
            end

            local driverGroup = GetPedRelationshipGroupHash(driverPed)

            if IsPedInCombat(driverPed, 0) then
                goto continue
            end

            local trailerCoords = GetEntityCoords(antiAirTrailer)
            local bestTarget = nil
            local bestDistance = 50.0 
            local bestPriority = 99 

            for _, vehicle in ipairs(GetGamePool("CVehicle")) do
                if DoesEntityExist(vehicle) and vehicle ~= antiAirTrailer then
                    local model = GetEntityModel(vehicle)
                    local isPlane = IsThisModelAPlane(model)
                    local isHeli = IsThisModelAHeli(model)

                    if isPlane or isHeli then
                        
                        local targetPilot = GetPedInVehicleSeat(vehicle, -1)
                        
                        if targetPilot ~= 0 and DoesEntityExist(targetPilot) then
                            local pilotGroup = GetPedRelationshipGroupHash(targetPilot)
                            
                            if pilotGroup ~= driverGroup then
                                local vehCoords = GetEntityCoords(vehicle)
                                local dist = #(vector3(trailerCoords.x, trailerCoords.y, trailerCoords.z) - vehCoords)

                                if dist <= 50.0 then
                                    local priority = isPlane and 1 or 2

                                    if priority < bestPriority or (priority == bestPriority and dist < bestDistance) then
                                        bestPriority = priority
                                        bestDistance = dist
                                        bestTarget = vehicle
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if bestTarget then
                local targetPed = GetPedInVehicleSeat(bestTarget, -1)
                DebugPrint("[AA] Engaging enemy aircraft:", bestTarget)
                TaskCombatPed(driverPed, targetPed, 0, 16)
            end

            ::continue::
        end
        DebugPrint("[AA] Anti-air thread ended")
    end)
end

function GetNearestHatedEntity(referencePed, ignoreVehicle)
    local myGroup = GetPedRelationshipGroupHash(referencePed)
    local peds = GetGamePool('CPed')
    local closestEntity = nil
    local closestDist = 30.0 

    local myCoords = GetEntityCoords(referencePed)

    for _, ped in ipairs(peds) do
        
        if ped ~= referencePed and GetVehiclePedIsIn(ped, false) ~= ignoreVehicle then
            local otherGroup = GetPedRelationshipGroupHash(ped)
            
            if GetRelationshipBetweenGroups(myGroup, otherGroup) == 5 then
                local dist = #(myCoords - GetEntityCoords(ped))
                if dist < closestDist then
                    closestDist = dist
                    closestEntity = ped
                end
            end
        end
    end

    local vehicles = GetGamePool('CVehicle')
    for _, veh in ipairs(vehicles) do
        if veh ~= ignoreVehicle then
            local driver = GetPedInVehicleSeat(veh, -1)
            if DoesEntityExist(driver) then
                local otherGroup = GetPedRelationshipGroupHash(driver)
                
                if GetRelationshipBetweenGroups(myGroup, otherGroup) == 5 then
                    local dist = #(myCoords - GetEntityCoords(veh))
                    if dist < closestDist then
                        closestDist = dist
                        closestEntity = veh 
                    end
                end
            end
        end
    end

    return closestEntity
end

function StartTankHullLogic(vehicle)
    CreateThread(function()
        while DoesEntityExist(vehicle) and GetEntityHealth(vehicle) > 0 do
            
            local speed = GetEntitySpeed(vehicle)
            if speed < 2.0 then 
                local driver = GetPedInVehicleSeat(vehicle, -1)
                
                if DoesEntityExist(driver)  then
                    local target = GetPedTaskCombatTarget(driver)
                    
                    if DoesEntityExist(target) then
                        
                        local vehPos = GetEntityCoords(vehicle)
                        local targetPos = GetEntityCoords(target)
                        
                        local dx = targetPos.x - vehPos.x
                        local dy = targetPos.y - vehPos.y
                        local desiredHeading = GetHeadingFromVector_2d(dx, dy)
                        local currentHeading = GetEntityHeading(vehicle)
                        
                        local diff = desiredHeading - currentHeading
                        while diff < -180 do diff = diff + 360 end
                        while diff > 180 do diff = diff - 360 end
                        
                        if math.abs(diff) > 5.0 then
                            
                            local turnStep = 1.5
                            if diff < 0 then turnStep = -turnStep end
                            
                            local newHeading = currentHeading + turnStep
                            SetEntityHeading(vehicle, newHeading)
                            
                            SetVehicleSteerBias(vehicle, 0.0) 
                        else
                            
                            TaskVehicleShootAtPed(driver, target, 50.0)
                        end
                    end
                end
            end
            Wait(1) 

        end
    end)
end

function FixEngineAndSecurePed(vehicle, ped)
    if DoesEntityExist(vehicle) and DoesEntityExist(ped) then
        
        SetVehicleEngineHealth(vehicle, 1000.0)
        
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        
        SetVehicleEngineOn(vehicle, true, true, true)
        SetVehicleUndriveable(vehicle, false)

        SetPedFleeAttributes(ped, 0, 0)
        
        SetPedCanBeDraggedOut(ped, false)
        
        SetPedStayInVehicleWhenJacked(ped, true)
        
        SetPedConfigFlag(ped, 32, false)
        
        SetPedCombatAttributes(ped, 17, true)

    end
end

function ForceGroundCombat(v)
    ClearPedTasks(npcPed)
    if not DoesEntityExist(v) then return end
    local npcPed = GetPedInVehicleSeat(v, -1)
    SetPedCombatAttributes(npcPed, 53, true)
    ClearPedTasks(npcPed)
    npcPed = GetPedInVehicleSeat(v, 0)
    SetPedCombatAttributes(npcPed, 53, true)
   
end

local VehicleWeaponHashes = {
    1945616459, 
    2971687502, 
    1259576109, 
    4026335563, 
    1186503822, 
    2669318622, 
    3473446624, 
    328167896,  
    1151689097, 
    190244068,  
    GetHashKey("VEHICLE_WEAPON_TURRET_INSURGENT"),
    GetHashKey("VEHICLE_WEAPON_PLAYER_SAVAGE"),
    GetHashKey("VEHICLE_WEAPON_TURRET_TECHNICAL"),
    GetHashKey("VEHICLE_WEAPON_NOSE_TURRET_VALKYRIE"),
    GetHashKey("VEHICLE_WEAPON_TURRET_VALKYRIE"),
    GetHashKey("VEHICLE_WEAPON_RUINER_ROCKET"),
    GetHashKey("VEHICLE_WEAPON_HUNTER_MG"),
    GetHashKey("VEHICLE_WEAPON_HUNTER_MISSILE"),
    GetHashKey("VEHICLE_WEAPON_HUNTER_CANNON"),
    GetHashKey("VEHICLE_WEAPON_KHANJALI_CANNON"),
    GetHashKey("VEHICLE_WEAPON_KHANJALI_CANNON_HEAVY"),
    GetHashKey("VEHICLE_WEAPON_KHANJALI_MG"),
    GetHashKey("VEHICLE_WEAPON_KHANJALI_GL"),
    GetHashKey("VEHICLE_WEAPON_TM_02_DUAL50CAL"),
    GetHashKey("VEHICLE_WEAPON_WATER_CANNON")
}

function GetTargetVehicleClass(targetEntity)
    if IsEntityAVehicle(targetEntity) then
        return GetVehicleClass(targetEntity)
    elseif IsEntityAPed(targetEntity) and IsPedInAnyVehicle(targetEntity, false) then
        local targetVeh = GetVehiclePedIsUsing(targetEntity)
        return GetVehicleClass(targetVeh)
    end
    return -1 
end

function RestrictToGround(vehicleEntity)
    local driver = GetPedInVehicleSeat(vehicleEntity, -1)
    
    if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
        SetPedCombatAttributes(driver, 87, true) 
        SetPedCombatAttributes(driver, 56, true) 
    end

    Citizen.CreateThread(function()
        DebugPrint("[DEBUG] Enforcing Ground Restrictions for Rhino: " .. vehicleEntity)
        
        while DoesEntityExist(vehicleEntity) do
            Citizen.Wait(0) 

            local currentDriver = GetPedInVehicleSeat(vehicleEntity, -1)

            if DoesEntityExist(currentDriver) and not IsPedAPlayer(currentDriver) then
                local isAirTarget = false
                
                local target = GetPedTaskCombatTarget(currentDriver)
                if DoesEntityExist(target) then
                    local targetClass = -1
                    if IsEntityAVehicle(target) then
                        targetClass = GetVehicleClass(target)
                    elseif IsEntityAPed(target) and IsPedInAnyVehicle(target, false) then
                        targetClass = GetVehicleClass(GetVehiclePedIsUsing(target))
                    end

                    if targetClass == 15 or targetClass == 16 then
                        isAirTarget = true
                    end
                end

                if isAirTarget then
                    
                    SetPedCombatAttributes(currentDriver, 53, false)

                    local tankCoords = GetEntityCoords(vehicleEntity)
                    local forward = GetEntityForwardVector(vehicleEntity)
                    local groundTarget = tankCoords + (forward * 5.0)
                    
                    TaskVehicleAimAtCoord(currentDriver, groundTarget.x, groundTarget.y, tankCoords.z - 2.0)
                    
                else
                    
                    SetPedCombatAttributes(currentDriver, 53, true)
                end
            end
        end
    end)
end

function RestrictToAntiAir(vehicleEntity)
    local driver = GetPedInVehicleSeat(vehicleEntity, -1)

    if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
        
        SetPedCombatAttributes(driver, 87, false) 
        
        SetPedCombatAttributes(driver, 56, false) 
    end

    Citizen.CreateThread(function()
        DebugPrint("[DEBUG] Enforcing Anti-Air Restrictions for Vehicle: " .. vehicleEntity)

        while DoesEntityExist(vehicleEntity) do
            Citizen.Wait(0) 

            local currentDriver = GetPedInVehicleSeat(vehicleEntity, -1)

            if DoesEntityExist(currentDriver) and not IsPedAPlayer(currentDriver) then
                local isGroundTarget = false
                local hasTarget = false

                local target = GetPedTaskCombatTarget(currentDriver)
                
                if DoesEntityExist(target) then
                    hasTarget = true
                    local targetClass = -1
                    
                    if IsEntityAVehicle(target) then
                        targetClass = GetVehicleClass(target)
                    elseif IsEntityAPed(target) and IsPedInAnyVehicle(target, false) then
                        targetClass = GetVehicleClass(GetVehiclePedIsUsing(target))
                    else
                        
                        isGroundTarget = true
                    end

                    if targetClass ~= -1 and targetClass ~= 15 and targetClass ~= 16 then
                        isGroundTarget = true
                    end
                end

                if hasTarget and isGroundTarget then
                    
                    SetPedCombatAttributes(currentDriver, 53, false)

                    local tankCoords = GetEntityCoords(vehicleEntity)
                    
                    TaskVehicleAimAtCoord(currentDriver, tankCoords.x, tankCoords.y, tankCoords.z + 50.0)
                    
                else
                    
                    SetPedCombatAttributes(currentDriver, 53, true)
                    
                end
            end
        end
    end)
end

function StartLazarFailSafe(unitId, entity)
    CreateThread(function()
        local startTime = GetGameTimer()
        local isActive = true
        
        while DoesEntityExist(entity) and (GetGameTimer() - startTime < 10000) do
            
            local foundInList = false
            if GameState.pendingAirstrikes then
                for _, jetData in ipairs(GameState.pendingAirstrikes) do
                    if jetData.unitId == unitId then
                        foundInList = true
                        break
                    end
                end
            end

            if not foundInList then
                isActive = false
                return 
            end

            Wait(200)
        end
        
        if isActive and DoesEntityExist(entity) then
            DebugPrint("^3[RTS] Failsafe triggered for Jet " .. unitId .. "^7")
            local target = GetNearestEnemyToObjective() 
            ExecuteLazarStrike(entity, target)
        end
    end)
end

function GetNearestEnemyToObjective()
    local bestTarget = nil
    local closestDist = 500.0
    local center = vector3(0,0,0) 
    
    if GameState.mapBounds then 
        center = vector3((GameState.mapBounds.minX+GameState.mapBounds.maxX)/2, (GameState.mapBounds.minY+GameState.mapBounds.maxY)/2, 0)
    end
    
    for _, enemy in pairs(GameState.enemyUnits) do
        if enemy.entity and DoesEntityExist(enemy.entity) then
            local dist = #(GetEntityCoords(enemy.entity) - center)
            if dist < closestDist then
                closestDist = dist
                bestTarget = enemy.entity
            end
        end
    end
    return bestTarget
end

function ExecuteLazarStrike(vehicle, targetEntity)
    CreateThread(function()
        if not DoesEntityExist(vehicle) then return end
        
        if GameState.pendingAirstrikes then
            for i, jetData in ipairs(GameState.pendingAirstrikes) do
                if jetData.entity == vehicle then
                    table.remove(GameState.pendingAirstrikes, i)
                    break
                end
            end
        end
        
        local driver = GetPedInVehicleSeat(vehicle, -1)
        FreezeEntityPosition(vehicle, false)
       
        SetTimeout(2000, function() 
            if DoesEntityExist(vehicle) then SetEntityInvincible(vehicle, false) end 
        end)
        SetVehicleEngineOn(vehicle, true, true, false)
        SetVehicleForwardSpeed(vehicle, 50.0) 
        SetVehicleEngineOn(vehicle, true, true, false)
        SetVehicleLandingGear(vehicle, 1)

        if targetEntity and DoesEntityExist(targetEntity) then
             local h = PointEntityAtEntity(vehicle, targetEntity)
             
             TaskPlaneMission(driver, vehicle, IsEntityAVehicle(targetEntity) and targetEntity or 0, IsEntityAPed(targetEntity) and targetEntity or 0, 0, 0, 0, 6, 50.0, 0, h, 2000.0, -1000.0)
             
             CreateThread(function()
                local start = GetGameTimer()
                while DoesEntityExist(targetEntity) and not IsEntityDead(targetEntity) do
                    if GetGameTimer() - start > 8000 then break end
                    Wait(500)
                end
                FlyAwayAndDelete(vehicle, driver)
             end)
        else
             
             FlyAwayAndDelete(vehicle, driver)
        end
        
        if GameState.pendingAirstrikes and #GameState.pendingAirstrikes == 0 then
            SendNUIMessage({ action = 'stopAirstrikeTimer' })
        end
    end)
end

function FlyAwayAndDelete(vehicle, driver)
    CreateThread(function()
    if not DoesEntityExist(vehicle) then return end
    
    local currentPos = GetEntityCoords(vehicle)
    local forwardVector = GetEntityForwardVector(driver)
    
    local targetPos = currentPos + (forwardVector * 500.0)
    targetPos = vector3(targetPos.x, targetPos.y, targetPos.z + 70.0)

    TaskPlaneMission(driver, vehicle, 0, 0, targetPos.x, targetPos.y, targetPos.z, 4, 50.0, 0, 0.0, 3000.0, 1000.0)
    
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleForwardSpeed(vehicle, 45.0)
    SetVehicleLandingGear(vehicle, 1) 

    SetTimeout(5000, function() 
        if DoesEntityExist(vehicle) then 
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteEntity(vehicle) 
        end
        ClearNPCsFromVehicle(vehicle)
        if DoesEntityExist(driver) then 
            SetEntityAsMissionEntity(driver, true, true)
            DeleteEntity(driver) 
        end
    end)
    end)
end

PROXY_MODEL_LOCAL = "s_m_y_marine_01" 
isProxyBusy = false

local proxyAttackLines = {
    "FIGHT", 
    "CHALLENGE_ACCEPTED_GENERIC" 
}

local proxyMoveLines = {
    "GENERIC_CHEER", 
    "FALL_BACK" 
}

function PlayProxySpeech(speechType)
    
    isProxyBusy = true

    Citizen.CreateThread(function()
        local modelHash = GetHashKey(PROXY_MODEL_LOCAL)
        RequestModel(modelHash)
        
        local loadTimeout = 0
        while not HasModelLoaded(modelHash) and loadTimeout < 1000 do
            Wait(10)
            loadTimeout = loadTimeout + 10
        end

        if HasModelLoaded(modelHash) then
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)

            local proxyPed = CreatePed(0, modelHash, playerCoords.x, playerCoords.y, playerCoords.z - 20.0, 0.0, false, false)

            FreezeEntityPosition(proxyPed, true)
            SetEntityCollision(proxyPed, false, false)
            SetEntityVisible(proxyPed, false) 

            local lineToSay = ""
            if speechType == "ATTACK" then
                lineToSay = proxyAttackLines[math.random(1, #proxyAttackLines)]
            elseif speechType == "MOVE" then
                lineToSay = proxyMoveLines[math.random(1, #proxyMoveLines)]
            end

            PlayAmbientSpeech1(proxyPed, lineToSay, "SPEECH_PARAMS_FORCE_SHOUTED_CLEAR")

            Wait(250) 
            local safetyCounter = 0
            while IsAmbientSpeechPlaying(proxyPed) and safetyCounter < 100 do
                Wait(100)
                safetyCounter = safetyCounter + 1
            end

            DeleteEntity(proxyPed)
            SetModelAsNoLongerNeeded(modelHash)
        end

        isProxyBusy = false
    end)
end

function DisablePedReactions(ped, time)
    Citizen.CreateThread(function()
        if not DoesEntityExist(ped) then return end

        SetBlockingOfNonTemporaryEvents(ped, true)
      
        Citizen.Wait(time)

        SetBlockingOfNonTemporaryEvents(ped, false)
        
    end)
end

function MakeAgressive(ped, accuracy, range, distance)
    if not DoesEntityExist(ped) then return end

    local isVehiclePed = IsPedInAnyVehicle(ped, false)
    SetPedConfigFlag(ped, 342, true) 
    
    SetPedCombatAbility(ped, 2)              
    SetPedCombatRange(ped, range or 2)       
    SetPedCombatMovement(ped, 2)             
    SetPedAccuracy(ped, accuracy or 100)
    SetPedAlertness(ped, 3)
    SetPedSeeingRange(ped, distance or 100.0)
    SetPedHearingRange(ped, distance or 100.0)

    SetPedDiesWhenInjured(ped, false)
    
    SetPedFleeAttributes(ped, 0, false)      
    SetPedCombatAttributes(ped, 46, true)    
    SetPedCombatAttributes(ped, 17, false)   
    SetPedCombatAttributes(ped, 5, true)     
    SetPedCombatAttributes(ped, 0, false)  
    SetPedCombatAttributes(ped, 4, false)  
   
    setCombatFloat(ped)
    
    SetPedConfigFlag(ped, 26, true) 

    SetPedConfigFlag(ped, 398, true)

    SetPedConfigFlag(ped, 342, true)

    SetPedConfigFlag(ped, 127, false)

    if isVehiclePed then
        
        SetPedCombatAttributes(ped, 3, false) 

        SetPedCombatAttributes(ped, 1, true)  
       
        SetDriverAbility(ped, 1.0)
        SetDriverAggressiveness(ped, 1.0)

        SetPedCombatAttributes(ped, 40, false)

        SetPedCombatAttributes(ped, 74, true)  
        SetPedCombatAttributes(ped, 60, true)  

    SetPedCanBeDraggedOut(ped, false)
    SetPedConfigFlag(ped, 184, true)
    
    SetPedStayInVehicleWhenJacked(ped, true)
    DebugPrint("agressive ped in car")

    else
        
    end
end

function setCombatFloat(ped)
    if not DoesEntityExist(ped) then return end
    
    SetCombatFloat(ped, 0, 0.1)    
    SetCombatFloat(ped, 1, 2.0)    
    SetCombatFloat(ped, 3, 1.25)   
    SetCombatFloat(ped, 4, 10.0)   
    SetCombatFloat(ped, 5, 0.0)    
    SetCombatFloat(ped, 8, 0.0)    
    SetCombatFloat(ped, 11, 55.0)  
    SetCombatFloat(ped, 12, 9.0)   
    SetCombatFloat(ped, 16, 21.0)  
    
    SetCombatFloat(ped, 2, -1.0)   
    SetCombatFloat(ped, 6, 0.6)    
    SetCombatFloat(ped, 7, 0.0)    
    SetCombatFloat(ped, 9, 1.0)    
    SetCombatFloat(ped, 10, 150.0) 
    SetCombatFloat(ped, 13, 7.0)   
    SetCombatFloat(ped, 14, 10.0)  
    SetCombatFloat(ped, 15, 0.15)  
    SetCombatFloat(ped, 17, 1.0)   
    SetCombatFloat(ped, 18, 40.0)  
    SetCombatFloat(ped, 19, 6.0)   
    SetCombatFloat(ped, 20, 2.25)  
    SetCombatFloat(ped, 21, -1.0)  
    SetCombatFloat(ped, 22, 3.0)   
    SetCombatFloat(ped, 23, 0.2)   
    SetCombatFloat(ped, 24, 0.6)   
    SetCombatFloat(ped, 25, 20.0)  
    SetCombatFloat(ped, 26, 1.0)   
    SetCombatFloat(ped, 27, -1.0)  
    SetCombatFloat(ped, 28, -1.0)  
end

function SpawnUnit(unitData)
    Wait(10)
    local unitConfig = Config.Units[unitData.unitType]
    if not unitConfig then 
        DebugPrint("^1[RTS ERROR] Unit config not found: " .. tostring(unitData.unitType) .. "^7")
        return 
    end

    local teamKey = "team" .. unitData.team 
    local modelName = unitConfig.model or "s_m_y_marine_01"
    unitConfig.model = modelName

    if unitConfig.category == "infantry" and unitConfig.teamModels and unitConfig.teamModels[teamKey] then
        modelName = unitConfig.teamModels[teamKey]
    end

    local position = unitData.position
    local modelHash = GetHashKey(modelName)

    if IsThisModelABoat(modelHash) then
        local mapName = unitData.mapName or GameState.currentMap
        if mapName and Config.Maps[mapName] and Config.Maps[mapName].waterSpawns then
            local wSpawn = (unitData.team == 1) and Config.Maps[mapName].waterSpawns.team1 or Config.Maps[mapName].waterSpawns.team2
            if wSpawn then
                local rX = math.random(-10, 10) * 1.0
                local rY = math.random(-10, 10) * 1.0
                position = vector3(wSpawn.x + rX, wSpawn.y + rY, wSpawn.z)
            end
        end
    end

    local isLazar = unitConfig.model == 'lazar' or unitConfig.category == "aircraft"

    if isLazar then
        local now = GetGameTimer()
        if now - LazarFormation.lastTime > 2000 then
            LazarFormation.index = 0 
            GameState.pendingAirstrikes = {} 
        end
        LazarFormation.lastTime = now

        local mySlot = LazarFormation.index % 5 
        local myLayer = math.floor(LazarFormation.index / 5) 
        local relOffset = V_OFFSETS[mySlot]
        
        local mapCenter = Config.Maps[GameState.currentMap].center
        local dirVector = mapCenter - position
        local dist = #(dirVector)
        local forwardX = dirVector.x / dist
        local forwardY = dirVector.y / dist
        local rightX = forwardY
        local rightY = -forwardX

        local finalX = position.x + (rightX * relOffset.x) + (forwardX * relOffset.y)
        local finalY = position.y + (rightY * relOffset.x) + (forwardY * relOffset.y)
        local finalZ = position.z + (myLayer * 20.0)

        position = vector3(finalX, finalY, finalZ)
        LazarFormation.index = LazarFormation.index + 1
    end

    RequestModel(modelHash)
    local retries = 0
    while not HasModelLoaded(modelHash) and retries < 1000 do 
        Wait(10)
        retries = retries + 1 
    end
    if not HasModelLoaded(modelHash) then 
        DebugPrint("^1[RTS ERROR] Model load timed out: " .. modelName .. "^7")
        return 
    end

    if not isLazar then
        local foundGround, zPos = GetGroundZFor_3dCoord(position.x, position.y, position.z + 40.0, 0)
        if foundGround then position = vector3(position.x, position.y, zPos) end
    end

    local entity = nil
    local trailer = nil
    local trailerEntity = 0
    
    if unitConfig.category == "vehicles" or unitConfig.category == "aircraft" or unitConfig.category == "helicopters" then
        local spawnZ = isLazar and (position.z + 55.0) or (position.z + 1.0)
        local fixedPos = GetSmartSpawnCoords(modelHash, vector3(position.x, position.y, spawnZ))
        local spawnZ = isLazar and (fixedPos.z + 55.0) or (fixedPos.z + 1.0)
        if not isLazar then
            CreateArcadeDrop(fixedPos, Config.Maps[GameState.currentMap].center,unitData.team)
        end
        entity = CreateVehicle(modelHash, fixedPos.x, fixedPos.y, spawnZ, 0.0, true, true)
        
        if isLazar then SetEntityCollision(entity, false, false) end
        
        local entWait = 0
        while not DoesEntityExist(entity) and entWait < 100 do Wait(0); entWait = entWait + 1 end
        if not DoesEntityExist(entity) then return end 
        SetVehicleEngineCanDegrade(entity,false)
        SetDisableVehicleEngineFires(entity,false)
        SetEntityAsMissionEntity(entity, true, true)
        SetVehicleStrong(entity, true)
        SetVehicleEngineOn(entity, true, true, false)
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)
        
        if unitConfig.teamColors and unitConfig.teamColors[teamKey] then
            local colors = unitConfig.teamColors[teamKey]
            SetVehicleColours(entity, colors[1], colors[2])
        end

        if isLazar then
            SetEntityCollision(entity, false, false)
            PointEntityAtCoords(entity, Config.Maps[GameState.currentMap].center)
            SetVehicleLandingGear(entity, 1) 
            Wait(10) 
            FreezeEntityPosition(entity, true) 
            SendNUIMessage({ action = 'startAirstrikeTimer', duration= 10 })
            
            if not GameState.pendingAirstrikes then GameState.pendingAirstrikes = {} end
            table.insert(GameState.pendingAirstrikes, {
                unitId = unitData.unitId,
                entity = entity,
                team = unitData.team,
                active = true
            })
            StartLazarFailSafe(unitData.unitId, entity)
        else
            SetVehicleOnGroundProperly(entity)
        end

        local netTries = 0
        while not NetworkGetEntityIsNetworked(entity) and netTries < 50 do 
            NetworkRegisterEntityAsNetworked(entity)
            netTries = netTries + 1
            Wait(0) 
        end

        if NetworkGetEntityIsNetworked(entity) then
            local netId = NetworkGetNetworkIdFromEntity(entity)
            SetNetworkIdCanMigrate(netId, true)
            SetNetworkIdExistsOnAllMachines(netId, true)
            
            if unitData.matchId then
                TriggerServerEvent('rts:registerUnitEntity', unitData.matchId, unitData.unitId, netId)
            end
        end

        if unitConfig.trailer then
            local modelHash =  GetHashKey(unitConfig.trailer)
            RequestModel(modelHash)
            local retries = 0
            while not HasModelLoaded(modelHash) and retries < 1000 do 
                Wait(10)
                retries = retries + 1 
            end
            if not HasModelLoaded(modelHash) then 
                DebugPrint("^1[RTS ERROR] Model load timed out: " .. modelName .. "^7")
                return 
            end
            
            while not DoesEntityExist(entity) do Wait(100) end
            local spawnPos = GetEntityCoords(entity)
            trailer = CreateVehicle(modelHash, spawnPos.x, spawnPos.y - 5.0, spawnPos.z, GetEntityHeading(entity), true, true)
            trailerEntity = trailer
            if unitConfig.teamColors and unitConfig.teamColors[teamKey] then
                local colors = unitConfig.teamColors[teamKey]
                SetVehicleColours(trailer, colors[1], colors[2])
            end
            carTrailer[entity] = trailerEntity
            
            AttachVehicleToTrailer(entity, trailerEntity, 1.1)
            
            SetEntityMaxHealth(trailer, unitData.health or 1000)
            SetEntityHealth(trailer, unitData.health or 1000)
            SetVehicleBodyHealth(trailer, unitConfig.health + 0.0)
            SetEntityAsMissionEntity(trailer, true, true)
            SetVehicleStrong(trailer, true)
            SetEntityProofs(trailer, false, true, false, true, false, false, false, false)
            local netTries = 0
            while not NetworkGetEntityIsNetworked(trailerEntity) and netTries < 50 do 
                NetworkRegisterEntityAsNetworked(trailerEntity)
                netTries = netTries + 1
                Wait(0) 
            end

            if NetworkGetEntityIsNetworked(trailerEntity) then
                local netId = NetworkGetNetworkIdFromEntity(trailerEntity)
                SetNetworkIdCanMigrate(netId, true)
                SetNetworkIdExistsOnAllMachines(netId, true)

            end
        end
        
        local pedModelName = "s_m_y_marine_01"
        if unitConfig.teamDrivers and unitConfig.teamDrivers[teamKey] then
            pedModelName = unitConfig.teamDrivers[teamKey]
        elseif unitConfig.pedModel then
            pedModelName = unitConfig.pedModel
        end

        local pedModel = GetHashKey(pedModelName)
        RequestModel(pedModel)
        local pedWait = 0
        while not HasModelLoaded(pedModel) and pedWait < 1000 do Wait(10); pedWait = pedWait + 1 end

        local seatCount = GetVehicleMaxNumberOfPassengers(entity)
        local maxi = 2
        if maxi > seatCount - 1 then maxi = seatCount - 1 end
        if trailer then maxi = maxi + 1 end
        for seat = -1, maxi do
            local anyseat = true 
            if IsTurretSeat(entity, seat) or seat == -1 or anyseat then
                local ped = CreatePed(4, pedModel, position.x, position.y, position.z, 0.0, true, true)
                
                SetEntityAsMissionEntity(ped, true, true)
                SetEntityProofs(ped, true, true, true, true, true, true, true, true)
                SetEntityInvincible(ped, true)
                SetPedSuffersCriticalHits(ped, false)
                SetPedCanRagdollFromPlayerImpact(ped, false)
                SetRagdollBlockingFlags(ped, 1)
                SetPedCombatAttributes(ped, 46, true)
                SetPedCombatAttributes(ped, 3, false)
                SetPedFiringPattern(ped, GetHashKey("FIRING_PATTERN_FULL_AUTO"))
                
                if unitConfig.weapons then
                    for _, weaponName in ipairs(unitConfig.weapons) do
                        GiveWeaponToPed(ped, GetHashKey(weaponName), 9999, false, true)
                    end
                end

                MakeAgressive(ped, 100, 2, 30.0)
                
                local groupHash = (unitData.team == 1) and GetHashKey("RTS_TEAM_1") or GetHashKey("RTS_TEAM_2")
                SetPedRelationshipGroupHash(ped, groupHash)
                if trailer and seat == maxi then 
                    SetPedIntoVehicle(ped, trailerEntity, -1)

                else
                    
                    if seat > -1 and (IsTurretSeat(entity,seat) or anyseat) then 
                        TaskEnterVehicle(ped, entity, 10, seat, 1.0, 16, 0)
                    end
                    Wait(10)
                    if seat > -1 and (IsTurretSeat(entity,seat) or anyseat) and not IsPedInAnyVehicle(ped) then 
                        SetPedIntoVehicle(ped, entity, seat)
                    end
                    if seat == -1 and GetPedInVehicleSeat(entity, -1) ~= ped then
                        SetPedIntoVehicle(ped, entity, -1)
                        TaskVehicleTempAction(ped, entity, 27, -1)
                    end
                end
                Wait(10)
                WatchPedVehicle(ped)
                
                if seat == -1 and unitData.matchId and NetworkGetEntityIsNetworked(ped) then
                     local driverNetId = NetworkGetNetworkIdFromEntity(ped)
                     TriggerServerEvent('rts:registerUnitEntityDriver', unitData.matchId, unitData.unitId, driverNetId)
                end
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

   if unitConfig.ModKit10 then
            SetVehicleMod(entity, 10, unitConfig.ModKit10, false)
        end
        
        Wait(250)
        WatchVehicle(entity)

        if trailerEntity ~= 0 then 
            SetVehicleModKit(trailerEntity, 0) 
            SetVehicleMod(trailerEntity, 16, 4, false) 
            
            SetVehicleTyresCanBurst(trailerEntity, false)       
            SetVehicleWheelsCanBreak(trailerEntity, false)      
            SetVehicleHasStrongAxles(trailerEntity, true)       
            SetVehicleExplodesOnHighExplosionDamage(trailerEntity, false) 
            
            SetVehicleMod(trailerEntity, 10, unitConfig.TrailerModKit10, false)
            
            Wait(250)
            StartTrailerWatch(entity, trailerEntity, unitConfig.health)
            RestrictToAntiAir(trailerEntity)
            StartAntiAirAutoCombat(trailerEntity)
        end
        if unitConfig.model == 'rhino' or unitConfig.model == 'khanjali' then
            StartTankHullLogic(entity)
            
        end

    else
        CreateArcadeDrop(position, Config.Maps[GameState.currentMap].center,unitData.team)
        entity = CreatePed(4, modelHash, position.x, position.y, position.z + 1.0, 0.0, true, true)
        
        local entWait = 0
        while not DoesEntityExist(entity) and entWait < 100 do Wait(0); entWait = entWait + 1 end
        if not DoesEntityExist(entity) then return end

        local netTries = 0
        while not NetworkGetEntityIsNetworked(entity) and netTries < 50 do 
            NetworkRegisterEntityAsNetworked(entity)
            netTries = netTries + 1
            Wait(0) 
        end

        if NetworkGetEntityIsNetworked(entity) then
            local netId = NetworkGetNetworkIdFromEntity(entity)
            SetNetworkIdCanMigrate(netId, true)
            SetNetworkIdExistsOnAllMachines(netId, true)
            
            if unitData.matchId then
                TriggerServerEvent('rts:registerUnitEntity', unitData.matchId, unitData.unitId, netId)
            end
        end

        SetPedCombatAttributes(entity, 46, true)
        SetPedFleeAttributes(entity, 0, false)
        SetPedCombatRange(entity, 0)
        SetPedSuffersCriticalHits(entity, false)
        SetPedCanRagdollFromPlayerImpact(entity, false)
        SetRagdollBlockingFlags(entity, 1)
        
        local groupHash = (unitData.team == 1) and GetHashKey("RTS_TEAM_1") or GetHashKey("RTS_TEAM_2")
        SetPedRelationshipGroupHash(entity, groupHash)
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)
        SetPedDiesInWater(entity, true)
        SetPedDiesInstantlyInWater(entity, true)
        
        if unitConfig.weapons then
            for i, weaponName in ipairs(unitConfig.weapons) do
                local weaponHash = GetHashKey(weaponName)
                GiveWeaponToPed(entity, weaponHash, 9999, false, true)
                if i == 1 then SetCurrentPedWeapon(entity, weaponHash, true) end
                
                    SetPedFiringPattern(ped, GetHashKey("FIRING_PATTERN_FULL_AUTO"))
              
            end
            WatchPedonFoot(entity)
        end

    end

    if DoesEntityExist(entity) then
        if unitConfig.health then
            SetEntityMaxHealth(entity, unitConfig.health)
            SetEntityHealth(entity, unitConfig.health)
            SetPedArmour(entity, 0)
            if IsEntityAVehicle(entity) then
                SetVehicleBodyHealth(entity, unitConfig.health + 0.0)
            end
        end

        local acc = (unitConfig and unitConfig.accuracy) or 50.0
        local rng = (unitConfig and unitConfig.range) and 2 or 2
        local dist = (unitConfig and unitConfig.sight) or 40.0
        
        MakeAgressive(entity, acc, rng, dist)
        SetEntityAsMissionEntity(entity, true, true)
        SetModelAsNoLongerNeeded(modelHash)
        Wait(1)
        if unitConfig.model == 'rhino' or unitConfig.model == 'khanjali' then
           RestrictToGround(entity)
            
        end
        
        local blip = CreateUnitBlip(entity, unitData.team, unitConfig.category, unitConfig.blip)

        GameState.units[unitData.unitId] = {
            id = unitData.unitId,
            entity = entity,
            team = unitData.team,
            type = unitData.unitType,
            blip = blip
        }
        
        DebugPrint("^2[RTS] Spawned " .. unitConfig.model .. " (ID: "..unitData.unitId..")^7")
    end
end
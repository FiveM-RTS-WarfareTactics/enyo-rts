-- =============================================================================
--  COMMANDS MODULE - Move, attack, lazar strike, vehicle handling
-- =============================================================================

function PlayObeyMove(ped)
    if DoesEntityExist(ped) then
        PlayAmbientSpeech1(ped, "GENERIC_HI", "SPEECH_PARAMS_FORCE_NORMAL")
    end
end

function PlayObeyAttack(ped)
    if DoesEntityExist(ped) then
        PlayAmbientSpeech1(ped, "GENERIC_CURSE_MED", "SPEECH_PARAMS_FORCE_NORMAL")
    end
end

function FixEngineAndSecurePed(vehicle, driver)
    if DoesEntityExist(vehicle) then
        SetVehicleEngineOn(vehicle, true, true, false)
        SetVehicleEngineCanDegrade(vehicle, false)
    end
    if driver and DoesEntityExist(driver) then
        SetPedConfigFlag(driver, 32, false)
    end
end

function ForceGroundCombat(vehicle)
    local model = GetEntityModel(vehicle)
    if IsThisModelAHeli(model) then
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleFlightNozzlePosition(vehicle, 0.0)
    end
    if IsThisModelAPlane(model) then return end
end

function ExecuteLazarStrike(jetEntity, targetEntity)
    SetEntityCollision(jetEntity, false, false)
    SetEntityInvincible(jetEntity, false)
    FreezeEntityPosition(jetEntity, false)

    local driver = GetPedInVehicleSeat(jetEntity, -1)
    if driver and DoesEntityExist(driver) then
        TaskCombatPed(driver, targetEntity, 0, 16)
        SetPedKeepTask(driver, true)
    end
end

function StartLazarFailSafe(unitId, entity)
    CreateThread(function()
        local startTime = GetGameTimer()
        while GetGameTimer() - startTime < 15000 do
            Wait(1000)
            if GameState.pendingAirstrikes then
                local stillActive = false
                for _, strike in ipairs(GameState.pendingAirstrikes) do
                    if strike.unitId == unitId then stillActive = true break end
                end
                if not stillActive then return end
            end
        end
        -- Timeout: auto-attack nearest enemy
        if DoesEntityExist(entity) then
            local nearestEnemy = GetNearestHatedEntity(entity, entity)
            if nearestEnemy then
                ExecuteLazarStrike(entity, nearestEnemy)
            end
        end
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
                if DoesEntityExist(driver) then
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
                            local turnStep = diff > 0 and 1.5 or -1.5
                            SetEntityHeading(vehicle, currentHeading + turnStep)
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

function RestrictToAntiAir(vehicle)
    CreateThread(function()
        while DoesEntityExist(vehicle) do
            Wait(500)
            local driver = GetPedInVehicleSeat(vehicle, -1)
            if driver ~= 0 then
                local target = GetPedTaskCombatTarget(driver)
                if DoesEntityExist(target) and IsEntityAPed(target) then
                    local veh = GetVehiclePedIsIn(target, false)
                    if veh ~= 0 then
                        local model = GetEntityModel(veh)
                        if not IsThisModelAPlane(model) and not IsThisModelAHeli(model) then
                            ClearPedTasks(driver)
                        end
                    else
                        ClearPedTasks(driver)
                    end
                end
            end
        end
    end)
end

function RestrictToGround(vehicle)
    CreateThread(function()
        while DoesEntityExist(vehicle) do
            Wait(500)
            local driver = GetPedInVehicleSeat(vehicle, -1)
            local gunner = GetPedInVehicleSeat(vehicle, 0)
            if driver ~= 0 then
                TaskVehicleTempAction(driver, vehicle, 27, -1)
            end
            if gunner ~= 0 then
                local target = GetPedTaskCombatTarget(gunner)
                if DoesEntityExist(target) and IsEntityAPed(target) then
                    local veh = GetVehiclePedIsIn(target, false)
                    if veh ~= 0 then
                        local model = GetEntityModel(veh)
                        if IsThisModelAPlane(model) or IsThisModelAHeli(model) then
                            ClearPedTasks(gunner)
                        end
                    end
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
            elseif trailer and DoesEntityExist(trailer) then
                local trailerBody = GetVehicleBodyHealth(trailer)
                if trailerBody < maxHealth then
                    local damageAmount = maxHealth - trailerBody
                    local currentCarHealth = GetVehicleBodyHealth(vehicle)
                    local newCarHealth = currentCarHealth - damageAmount
                    SetVehicleBodyHealth(vehicle, newCarHealth)
                    SetVehicleBodyHealth(trailer, maxHealth)
                    SetVehicleEngineHealth(trailer, maxHealth)
                end

                if GetVehicleBodyHealth(vehicle) <= 100 then
                    destroyAll = true
                end
            end

            if destroyAll then
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
                break
            end
        end
    end)
end

function StartAntiAirAutoCombat(antiAirTrailer)
    Citizen.CreateThread(function()
        while DoesEntityExist(antiAirTrailer) and GetVehicleBodyHealth(antiAirTrailer) > 100 do
            Citizen.Wait(1000)
            local driverPed = GetPedInVehicleSeat(antiAirTrailer, -1)
            if driverPed == 0 or not DoesEntityExist(driverPed) then break end

            if IsPedInCombat(driverPed, 0) then goto continue end

            local driverGroup = GetPedRelationshipGroupHash(driverPed)
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
                                local dist = #(trailerCoords - vehCoords)
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
                TaskCombatPed(driverPed, targetPed, 0, 16)
            end

            ::continue::
        end
    end)
end

function WatchVehicle(entity)
    CreateThread(function()
        while DoesEntityExist(entity) do
            Wait(500)
            local health = GetVehicleBodyHealth(entity)
            if health <= 99 then
                SetEntityAsMissionEntity(entity, true, true)
                break
            end
        end
    end)
end

function WatchPedVehicle(ped)
    CreateThread(function()
        while DoesEntityExist(ped) do
            Wait(1000)
            if not IsPedInAnyVehicle(ped, false) then
                SetPedIntoVehicle(ped, GetVehiclePedIsIn(ped, false), -1)
            end
        end
    end)
end

function WatchPedonFoot(ped)
    CreateThread(function()
        while DoesEntityExist(ped) do
            Wait(5000)
            if IsPedDeadOrDying(ped, true) then break end
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and not IsThisModelABoat(GetEntityModel(veh)) then
                TaskLeaveVehicle(ped, veh, 16)
            end
        end
    end)
end

function CreateArcadeDrop(position, mapCenter, team)
    -- Visual feedback for unit deployment
    if position and DoesCamExist(GameState.camera) then
        local color = team == 1 and { r = 0, g = 100, b = 255 } or { r = 255, g = 50, b = 50 }
        DrawMarker(28, position.x, position.y, position.z + 3.0, 0, 0, 0, 0, 0, 0,
            1.0, 1.0, 3.0, color.r, color.g, color.b, 200, false, false, 2, false, nil, nil, false)
    end
end

function CommandPedToMoveSafely(ped, targetPos, staggerIndex)
    ClearPedTasks(ped)
    TaskGoToCoordAnyMeans(ped, targetPos.x, targetPos.y, targetPos.z, 2.0, 0, 0, 4981292, 0.0)
end

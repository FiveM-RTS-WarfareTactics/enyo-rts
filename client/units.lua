-- =============================================================================
--  UNITS MODULE - Spawning, vehicles, infantry, formations, death monitoring
-- =============================================================================

local carTrailer = {}

-- Formation state
local lastOrderTime = 0
local formationIndex = 0
local anchorPos = nil
local anchorHeading = 0.0
local RESET_TIME = 3000
local PEDS_PER_LINE = 5
local GAP_SIDE = 1.5
local GAP_BACK = 2.0

-- Lazar formation
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

function SetupRelationshipGroups()
    local team1Hash = GetHashKey("RTS_TEAM_1")
    local team2Hash = GetHashKey("RTS_TEAM_2")

    AddRelationshipGroup("RTS_TEAM_1", team1Hash)
    AddRelationshipGroup("RTS_TEAM_2", team2Hash)

    SetRelationshipBetweenGroups(0, team1Hash, team1Hash)
    SetRelationshipBetweenGroups(255, team1Hash, team2Hash)

    SetRelationshipBetweenGroups(0, team2Hash, team2Hash)
    SetRelationshipBetweenGroups(255, team2Hash, team1Hash)
end

function SpawnUnit(unitData)
    Wait(10)
    local unitConfig = Config.Units[unitData.unitType]
    if not unitConfig then return end

    local teamKey = "team" .. unitData.team
    local modelName = unitConfig.model or "s_m_y_marine_01"
    unitConfig.model = modelName

    if unitConfig.category == "infantry" and unitConfig.teamModels and unitConfig.teamModels[teamKey] then
        modelName = unitConfig.teamModels[teamKey]
    end

    local position = unitData.position
    local modelHash = GetHashKey(modelName)

    -- Boat logic
    if IsThisModelABoat(modelHash) then
        local mapName = unitData.mapName or GameState.currentMap
        if mapName and Config.Maps[mapName] and Config.Maps[mapName].waterSpawns then
            local wSpawn = (unitData.team == 1) and Config.Maps[mapName].waterSpawns.team1 or Config.Maps[mapName].waterSpawns.team2
            if wSpawn then
                position = vector3(wSpawn.x + math.random(-10, 10) * 1.0, wSpawn.y + math.random(-10, 10) * 1.0, wSpawn.z)
            end
        end
    end

    local isLazar = unitConfig.model == 'lazar' or unitConfig.category == "aircraft"

    -- Lazar Formation Logic
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

    -- Load model
    RequestModel(modelHash)
    local retries = 0
    while not HasModelLoaded(modelHash) and retries < 1000 do Wait(10); retries = retries + 1 end
    if not HasModelLoaded(modelHash) then return end

    -- Ground snap
    if not isLazar then
        local foundGround, zPos = GetGroundZFor_3dCoord(position.x, position.y, position.z + 40.0, 0)
        if foundGround then position = vector3(position.x, position.y, zPos) end
    end

    local entity = nil
    local trailerEntity = 0

    -- === VEHICLE SPAWN ===
    if unitConfig.category == "vehicles" or unitConfig.category == "aircraft" or unitConfig.category == "helicopters" then
        local spawnZ = isLazar and (position.z + 55.0) or (position.z + 1.0)
        local fixedPos = GetSmartSpawnCoords(modelHash, vector3(position.x, position.y, spawnZ))
        spawnZ = isLazar and (fixedPos.z + 55.0) or (fixedPos.z + 1.0)

        if not isLazar then
            CreateArcadeDrop(fixedPos, Config.Maps[GameState.currentMap].center, unitData.team)
        end

        entity = CreateVehicle(modelHash, fixedPos.x, fixedPos.y, spawnZ, 0.0, true, true)

        if isLazar then SetEntityCollision(entity, false, false) end

        local entWait = 0
        while not DoesEntityExist(entity) and entWait < 100 do Wait(0); entWait = entWait + 1 end
        if not DoesEntityExist(entity) then return end

        SetVehicleEngineCanDegrade(entity, false)
        SetDisableVehicleEngineFires(entity, false)
        SetEntityAsMissionEntity(entity, true, true)
        SetVehicleStrong(entity, true)
        SetVehicleEngineOn(entity, true, true, false)
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)

        -- Team colors
        if unitConfig.teamColors and unitConfig.teamColors[teamKey] then
            local colors = unitConfig.teamColors[teamKey]
            SetVehicleColours(entity, colors[1], colors[2])
        end

        -- Lazar setup
        if isLazar then
            SetEntityCollision(entity, false, false)
            PointEntityAtCoords(entity, Config.Maps[GameState.currentMap].center)
            SetVehicleLandingGear(entity, 1)
            FreezeEntityPosition(entity, true)
            SendNUIMessage({ action = 'startAirstrikeTimer', duration = 10 })

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

        -- Networking
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

        -- Trailer
        if unitConfig.trailer then
            local trailerModel = GetHashKey(unitConfig.trailer)
            RequestModel(trailerModel)
            local tr = 0
            while not HasModelLoaded(trailerModel) and tr < 1000 do Wait(10); tr = tr + 1 end
            if HasModelLoaded(trailerModel) then
                local spawnPos = GetEntityCoords(entity)
                trailerEntity = CreateVehicle(trailerModel, spawnPos.x, spawnPos.y - 5.0, spawnPos.z, GetEntityHeading(entity), true, true)

                if unitConfig.teamColors and unitConfig.teamColors[teamKey] then
                    local colors = unitConfig.teamColors[teamKey]
                    SetVehicleColours(trailerEntity, colors[1], colors[2])
                end
                carTrailer[entity] = trailerEntity
                AttachVehicleToTrailer(entity, trailerEntity, 1.1)
                SetEntityMaxHealth(trailerEntity, unitData.health or 1000)
                SetEntityHealth(trailerEntity, unitData.health or 1000)
                SetVehicleBodyHealth(trailerEntity, unitConfig.health + 0.0)
                SetEntityAsMissionEntity(trailerEntity, true, true)
                SetVehicleStrong(trailerEntity, true)
                SetEntityProofs(trailerEntity, false, true, false, true, false, false, false, false)
            end
        end

        -- Crew logic
        local pedModelName = "s_m_y_marine_01"
        if unitConfig.teamDrivers and unitConfig.teamDrivers[teamKey] then
            pedModelName = unitConfig.teamDrivers[teamKey]
        end
        local pedModel = GetHashKey(pedModelName)
        RequestModel(pedModel)
        local pw = 0
        while not HasModelLoaded(pedModel) and pw < 1000 do Wait(10); pw = pw + 1 end

        local seatCount = GetVehicleMaxNumberOfPassengers(entity)
        local maxi = math.min(2, seatCount - 1)
        if trailerEntity ~= 0 then maxi = maxi + 1 end
        for seat = -1, maxi do
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

            if trailerEntity ~= 0 and seat == maxi then
                SetPedIntoVehicle(ped, trailerEntity, -1)
            else
                if seat > -1 then
                    TaskEnterVehicle(ped, entity, 10, seat, 1.0, 16, 0)
                    Wait(10)
                    if not IsPedInAnyVehicle(ped) then
                        SetPedIntoVehicle(ped, entity, seat)
                    end
                end
                if seat == -1 and GetPedInVehicleSeat(entity, -1) ~= ped then
                    SetPedIntoVehicle(ped, entity, -1)
                    TaskVehicleTempAction(ped, entity, 27, -1)
                end
            end
            Wait(10)
            WatchPedVehicle(ped)
        end

        -- Vehicle upgrades
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
            if unitConfig.TrailerModKit10 then
                SetVehicleMod(trailerEntity, 10, unitConfig.TrailerModKit10, false)
            end
            Wait(250)
            StartTrailerWatch(entity, trailerEntity, unitConfig.health)
            RestrictToAntiAir(trailerEntity)
            StartAntiAirAutoCombat(trailerEntity)
        end

        if unitConfig.model == 'rhino' or unitConfig.model == 'khanjali' then
            StartTankHullLogic(entity)
        end

    -- === INFANTRY SPAWN ===
    else
        CreateArcadeDrop(position, Config.Maps[GameState.currentMap].center, unitData.team)
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
                SetPedFiringPattern(entity, GetHashKey("FIRING_PATTERN_FULL_AUTO"))
            end
            WatchPedonFoot(entity)
        end
    end

    -- Final setup
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
        local rng = 2
        local dist = 40.0
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
            blip = blip,
            blipHidden = false,
            category = unitConfig.category
        }
    end
end

-- =============================================================================
--  FORMATION MARCH LOGIC
-- =============================================================================

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
    local forwardY = math.cos(rad)
    local rightX = math.cos(rad)
    local rightY = math.sin(rad)

    local colIndex = (formationIndex - 1) % PEDS_PER_LINE
    local rowIndex = math.floor((formationIndex - 1) / PEDS_PER_LINE)

    local sideOffset = (colIndex - ((PEDS_PER_LINE - 1) / 2)) * GAP_SIDE
    local backOffset = -(rowIndex * GAP_BACK)

    local finalX = anchorPos.x + (rightX * sideOffset) + (forwardX * backOffset)
    local finalY = anchorPos.y + (rightY * sideOffset) + (forwardY * backOffset)

    local targetVector = vector3(finalX, finalY, targetZ)
    CommandPedToMoveSafely(ped, targetVector, formationIndex)
end

-- =============================================================================
--  MAP DECORATIONS
-- =============================================================================

function SpawnMapDecorations(mapName)
    local mapData = Config.Maps[mapName]
    if not mapData or not mapData.decorativeObjects then return end

    for _, objData in ipairs(mapData.decorativeObjects) do
        if objData.net == nil or objData.net == false or (objData.net == true and GameState.isHost) then
            local modelHash = type(objData.model) == "string" and GetHashKey(objData.model) or objData.model

            RequestModel(modelHash)
            local timeout = 0
            while not HasModelLoaded(modelHash) and timeout < 1000 do
                Wait(10); RequestModel(modelHash); timeout = timeout + 1
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
            end
        end
    end
end

-- =============================================================================
--  BLIP SYSTEM
-- =============================================================================

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

-- =============================================================================
--  SPAWN HELPER: SMART COORDINATES
-- =============================================================================

function GetSmartSpawnCoords(modelHash, centerCoords)
    local hash = type(modelHash) == "number" and modelHash or GetHashKey(modelHash)
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        local t = 0
        while not HasModelLoaded(hash) and t < 100 do Wait(0) t = t + 1 end
    end

    local isBoat = IsThisModelABoat(hash)
    local min, max = GetModelDimensions(hash)
    local width = (max.x - min.x) * 0.8
    local length = (max.y - min.y) * 0.8
    local radius = ((width > length and width or length) / 2) + 1.5

    for i = 0, 150 do
        local angle = i * 137.5
        local distance = math.sqrt(i) * (radius * 1.1)
        local rad = math.rad(angle)
        local testPos = vector3(
            centerCoords.x + (math.cos(rad) * distance),
            centerCoords.y + (math.sin(rad) * distance),
            centerCoords.z
        )

        local finalPos = nil
        if isBoat then
            local retval, waterHeight = GetWaterHeight(testPos.x, testPos.y, testPos.z)
            if retval then finalPos = vector3(testPos.x, testPos.y, waterHeight) end
        else
            local success, navPos = GetSafeCoordForPed(testPos.x, testPos.y, testPos.z, false, 16)
            if success then finalPos = navPos end
        end

        if finalPos then
            if not IsPositionOccupied(finalPos.x, finalPos.y, finalPos.z, radius, false, true, true, false, false, 0, false) then
                return finalPos
            end
        end
        if i % 30 == 0 then Wait(0) end
    end
    return centerCoords + vector3(0, 0, 3.0)
end

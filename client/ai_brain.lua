-- =============================================================================
--  AI BRAIN MODULE - CPU opponent behavior (V3.0)
-- =============================================================================

local CPUBrain = {
    active = false,
    matchId = nil,
    lastThinkTime = 0,
    thinkInterval = 3000, -- Think every 3 seconds
    deployedUnits = {},
    objectiveWeights = {},
    currentStrategy = "balanced",
}

function StartCPUBrain(matchId)
    CPUBrain.active = true
    CPUBrain.matchId = matchId
    CPUBrain.deployedUnits = {}
    CPUBrain.lastThinkTime = GetGameTimer()

    CreateThread(function()
        while CPUBrain.active and GameState.isInMatch do
            Wait(CPUBrain.thinkInterval)

            if not CPUBrain.active then break end

            CPUBrain.DecideActions()
        end
    end)
end

function StopCPUBrain()
    CPUBrain.active = false
end

function CPUBrain.DecideActions()
    if not GameState.isInMatch then return end

    -- 1. Analyze battlefield
    local friendlyCount = 0
    local enemyCount = 0

    for _, unit in pairs(GameState.units) do
        if unit and unit.entity and DoesEntityExist(unit.entity) then
            if unit.team == GameState.team then
                enemyCount = enemyCount + 1
            end
        end
    end

    for _, unit in pairs(GameState.enemyUnits) do
        if unit and unit.entity and DoesEntityExist(unit.entity) then
            friendlyCount = friendlyCount + 1
        end
    end

    -- 2. Adjust strategy based on situation
    if friendlyCount > enemyCount * 1.5 then
        CPUBrain.currentStrategy = "aggressive"
    elseif enemyCount > friendlyCount * 1.5 then
        CPUBrain.currentStrategy = "defensive"
    else
        CPUBrain.currentStrategy = "balanced"
    end

    -- 3. Deploy units if affordable
    CPUBrain.SpawnUnits()
end

function CPUBrain.SpawnUnits()
    -- Try to spawn a platoon slot if we have resources
    for slot = 1, 5 do
        local platoon = GameState.platoons and GameState.platoons[tostring(slot)]
        if platoon and platoon.totalCost and GameState.commandPoints >= platoon.totalCost then
            -- Find a good spawn location near objectives
            local spawnX = Config.Maps[GameState.currentMap].spawns.team2.x
            local spawnY = Config.Maps[GameState.currentMap].spawns.team2.y
            local spawnZ = Config.Maps[GameState.currentMap].spawns.team2.z

            -- Trigger CPU spawn via server
            TriggerServerEvent('rts:server:cpuSpawnPlatoon', CPUBrain.matchId or GameState.matchId, slot)
            break
        end
    end
end

-- =============================================================================
--  NETWORK EVENT HANDLERS FOR CPU
-- =============================================================================

RegisterNetEvent('rts:client:cpuDoSpawn', function(data)
    if not data then return end

    local unitConfig = Config.Units[data.type]
    if not unitConfig then return end

    local teamKey = "team" .. data.team
    local modelName = unitConfig.model or "s_m_y_marine_01"

    if unitConfig.category == "infantry" and unitConfig.teamModels and unitConfig.teamModels[teamKey] then
        modelName = unitConfig.teamModels[teamKey]
    end

    local modelHash = GetHashKey(modelName)
    local position = data.position

    RequestModel(modelHash)
    local retries = 0
    while not HasModelLoaded(modelHash) and retries < 1000 do Wait(10); retries = retries + 1 end
    if not HasModelLoaded(modelHash) then return end

    local entity = nil

    if unitConfig.category == "vehicles" or unitConfig.category == "aircraft" or unitConfig.category == "helicopters" then
        local spawnPos = GetSmartSpawnCoords(modelHash, position)
        entity = CreateVehicle(modelHash, spawnPos.x, spawnPos.y, spawnPos.z + 1.0, 0.0, true, true)
        SetVehicleEngineCanDegrade(entity, false)
        SetVehicleEngineOn(entity, true, true, false)
        SetEntityAsMissionEntity(entity, true, true)
        SetVehicleStrong(entity, true)
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)

        if unitConfig.teamColors and unitConfig.teamColors[teamKey] then
            local colors = unitConfig.teamColors[teamKey]
            SetVehicleColours(entity, colors[1], colors[2])
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

        -- Driver
        local pedModelName = "s_m_y_blackops_01"
        if unitConfig.teamDrivers and unitConfig.teamDrivers[teamKey] then
            pedModelName = unitConfig.teamDrivers[teamKey]
        end
        local pedModel = GetHashKey(pedModelName)
        RequestModel(pedModel)
        local pw = 0
        while not HasModelLoaded(pedModel) and pw < 1000 do Wait(10); pw = pw + 1 end

        local driver = CreatePed(4, pedModel, position.x, position.y, position.z, 0.0, true, true)
        SetPedIntoVehicle(driver, entity, -1)
        SetEntityProofs(driver, true, true, true, true, true, true, true, true)
        SetEntityInvincible(driver, true)
        SetPedCombatAttributes(driver, 46, true)
        SetPedCombatAttributes(driver, 3, false)
        SetPedFiringPattern(driver, GetHashKey("FIRING_PATTERN_FULL_AUTO"))

        if unitConfig.weapons then
            for _, weaponName in ipairs(unitConfig.weapons) do
                GiveWeaponToPed(driver, GetHashKey(weaponName), 9999, false, true)
            end
        end

        local groupHash = GetHashKey("RTS_TEAM_2")
        SetPedRelationshipGroupHash(driver, groupHash)

        MakeAgressive(driver, 100, 2, 30.0)
        WatchVehicle(entity)
    else
        entity = CreatePed(4, modelHash, position.x, position.y, position.z + 1.0, 0.0, true, true)

        SetPedCombatAttributes(entity, 46, true)
        SetPedFleeAttributes(entity, 0, false)
        SetPedCombatRange(entity, 0)
        SetPedSuffersCriticalHits(entity, false)
        SetPedCanRagdollFromPlayerImpact(entity, false)
        SetRagdollBlockingFlags(entity, 1)
        SetEntityProofs(entity, false, true, false, true, false, false, false, false)
        SetPedDiesInWater(entity, true)
        SetPedDiesInstantlyInWater(entity, true)

        local groupHash = GetHashKey("RTS_TEAM_2")
        SetPedRelationshipGroupHash(entity, groupHash)

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

    if DoesEntityExist(entity) then
        if unitConfig.health then
            SetEntityMaxHealth(entity, unitConfig.health)
            SetEntityHealth(entity, unitConfig.health)
            if IsEntityAVehicle(entity) then
                SetVehicleBodyHealth(entity, unitConfig.health + 0.0)
            end
        end

        MakeAgressive(entity, unitConfig.accuracy or 50.0, 2, 40.0)
        SetEntityAsMissionEntity(entity, true, true)
        SetModelAsNoLongerNeeded(modelHash)

        -- Register as enemy unit
        GameState.enemyUnits[data.unitId] = {
            id = data.unitId,
            entity = entity,
            team = data.team,
            type = data.type,
            position = data.position,
            blip = CreateUnitBlip(entity, data.team, unitConfig.category, unitConfig.blip, true)
        }
    end
end)

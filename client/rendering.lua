-- =============================================================================
--  RENDERING MODULE - Hitbox tracker, objective markers, health bars
-- =============================================================================

function StartHitboxTracker()
    CreateThread(function()
        while GameState.isInMatch do
            Wait(30)

            local onScreenUnits = {}
            local sightRange = Config.MatchSettings.UnitSightRange or 65.0
            if GameState.pendingAirstrikes and #GameState.pendingAirstrikes > 0 then sightRange = 5000.0 end

            local camPos = GetCamCoord(GameState.camera)

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

            local function GetHitboxPosition(entity)
                local pos = GetEntityCoords(entity)
                if pos.x == 0.0 and pos.y == 0.0 then return nil end
                local min, max = GetModelDimensions(GetEntityModel(entity))
                local dist = #(camPos - pos)
                local zOffset = max.z + 0.2
                if dist < 20.0 then zOffset = zOffset + 0.5
                elseif dist > 80.0 then zOffset = zOffset - 0.2 end
                return vector3(pos.x, pos.y, pos.z + zOffset)
            end

            local friendlyPositions = {}
            for _, unit in pairs(GameState.units) do
                if IsUnitAlive(unit.entity) then
                    table.insert(friendlyPositions, GetEntityCoords(unit.entity))
                end
            end

            -- Process friendly units
            for unitId, unit in pairs(GameState.units) do
                if IsUnitAlive(unit.entity) then
                    local hitboxPos = GetHitboxPosition(unit.entity)
                    if hitboxPos then
                        local onScreen, x, y = GetScreenCoordFromWorldCoord(hitboxPos.x, hitboxPos.y, hitboxPos.z)
                        if onScreen then
                            local curHp, maxHp = 0, 100
                            if IsEntityAVehicle(unit.entity) then
                                curHp = math.floor(GetVehicleBodyHealth(unit.entity))
                                maxHp = (Config.Units[unit.type] and Config.Units[unit.type].health) or 1000.0
                            else
                                curHp = GetEntityHealth(unit.entity)
                                maxHp = GetEntityMaxHealth(unit.entity)
                            end
                            if maxHp <= 0 then maxHp = 1 end
                            local healthPct = math.floor((curHp / maxHp) * 100)
                            healthPct = math.max(0, math.min(100, healthPct))

                            table.insert(onScreenUnits, {
                                id = unitId, x = x, y = y,
                                team = unit.team, health = healthPct,
                                cur = curHp, max = maxHp, type = unit.type
                            })
                        end
                    end
                end
            end

            -- Process enemy units
            for unitId, unit in pairs(GameState.enemyUnits) do
                if not unit.entity or not DoesEntityExist(unit.entity) then
                    if unit.position then
                        local pool = (Config.Units[unit.type] and Config.Units[unit.type].category == "vehicles")
                            and GetGamePool('CVehicle') or GetGamePool('CPed')
                        local closestEnt = nil
                        local minDst = 15.0
                        for _, ent in ipairs(pool) do
                            local pPos = GetEntityCoords(ent)
                            local dist = #(pPos - unit.position)
                            if dist < minDst and IsUnitAlive(ent) and ent ~= PlayerPedId() then
                                local isMine = false
                                for _, myUnit in pairs(GameState.units) do
                                    if myUnit.entity == ent then isMine = true break end
                                end
                                if not isMine then closestEnt = ent; minDst = dist end
                            end
                        end
                        if closestEnt then unit.entity = closestEnt end
                    end
                end

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
                                    local curHp, maxHp = 0, 100
                                    if IsEntityAVehicle(unit.entity) then
                                        curHp = math.floor(GetVehicleBodyHealth(unit.entity))
                                        maxHp = (Config.Units[unit.type] and Config.Units[unit.type].health) or curHp or 1000.0
                                    else
                                        curHp = GetEntityHealth(unit.entity)
                                        maxHp = GetEntityMaxHealth(unit.entity)
                                    end
                                    if maxHp <= 0 then maxHp = 1 end
                                    local healthPct = math.floor((curHp / maxHp) * 100)
                                    healthPct = math.max(0, math.min(100, healthPct))

                                    table.insert(onScreenUnits, {
                                        id = unitId, x = x, y = y,
                                        team = unit.team, health = healthPct,
                                        cur = curHp, max = maxHp, type = unit.type
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
    math.randomseed(GetGameTimer())

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
end

function StartMatch(data)
    CleanupMatch(true)

    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    SetRelationshipBetweenGroups(1, GetHashKey("RTS_TEAM_1"), playerGroup)
    SetRelationshipBetweenGroups(1, GetHashKey("RTS_TEAM_2"), playerGroup)
    SetRelationshipBetweenGroups(1, playerGroup, GetHashKey("RTS_TEAM_1"))
    SetRelationshipBetweenGroups(1, playerGroup, GetHashKey("RTS_TEAM_2"))

    GameState.isInMatch = true
    GameState.matchId = data.matchId
    GameState.team = data.team
    GameState.currentMap = data.map
    GameState.commandPoints = Config.MatchSettings.CommandPointsStart
    GameState.incomeRate = Config.MatchSettings.CommandPointsPerMinute / 60
    GameState.platoons = data.platoons or {}

    local map = Config.Maps[data.map]
    if not map then return end

    GameState.mapBounds = {
        minX = map.center.x - map.range,
        maxX = map.center.x + map.range,
        minY = map.center.y - map.range,
        maxY = map.center.y + map.range,
        centerZ = map.center.z
    }

    ResetGameWorldInRange(map.center, map.range)

    local spawnPos = data.spawnPos or vector3(map.spawns.team1.x, map.spawns.team1.y, map.spawns.team1.z)
    InitializeCamera(spawnPos)

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)

    DisableControlAction(0, 1, true)
    DisableControlAction(0, 2, true)
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    DisableControlAction(0, 263, true)

    SendNUIMessage({
        action = 'startMatch',
        team = data.team,
        teamColor = Config.UI.TeamColors["team" .. data.team],
        mapName = map.name,
        music = map.music or "main_theme.mp3",
        mapDescription = map.description,
    })

    -- Apply environment
    NetworkOverrideClockTime(map.time.h, map.time.m, 0)
    SetWeatherTypeNowPersist(map.weather)
    SetWeatherTypeNow(map.weather)

    SpawnMapDecorations(data.map)

    StartHitboxTracker()
    StartSelectionUpdater()
end

function CleanupMatch(fullReset)
    GameState.isInMatch = false
    GameState.selectedUnits = {}
    GameState.units = {}
    GameState.enemyUnits = {}
    GameState.deployedPlatoons = {}
    GameState.pendingAirstrikes = {}

    for _, blip in pairs(GameState.objectiveBlips) do
        RemoveBlip(blip)
    end
    GameState.objectiveBlips = {}

    for _, obj in pairs(GameState.decorativeObjects or {}) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    GameState.decorativeObjects = {}

    for _, unit in pairs(GameState.units) do
        if unit.blip then RemoveBlip(unit.blip) end
        if unit.entity and DoesEntityExist(unit.entity) then
            if IsEntityAVehicle(unit.entity) then
                DeleteVehicle(unit.entity)
            else
                DeletePed(unit.entity)
            end
        end
    end

    if fullReset then
        if GameState.camera then
            RenderScriptCams(false, true, 1000, true, true)
            DestroyCam(GameState.camera, false)
            GameState.camera = nil
        end
        -- NUI focus is never released in dedicated game mode.
        -- The anticheat heartbeat re-validates it continuously.
    end
end

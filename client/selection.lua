-- =============================================================================
--  SELECTION MODULE - Unit selection box, category selection
-- =============================================================================

function SelectAllUnits()
    DeselectAllUnits()
    for unitId, unit in pairs(GameState.units) do
        if unit.entity and DoesEntityExist(unit.entity) then
            table.insert(GameState.selectedUnits, unitId)
        end
    end
    UpdateSelectionUI()
    if #GameState.selectedUnits > 0 then
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end

function SelectUnitsByCategory(category)
    DeselectAllUnits()
    for unitId, unit in pairs(GameState.units) do
        if unit.entity and DoesEntityExist(unit.entity) and unit.category == category then
            table.insert(GameState.selectedUnits, unitId)
        end
    end
    UpdateSelectionUI()
    if #GameState.selectedUnits > 0 then
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end

function DeselectAllUnits()
    GameState.selectedUnits = {}
    UpdateSelectionUI()
end

function UpdateSelectionUI()
    local count = #GameState.selectedUnits
    local healthPercent = 0

    if count > 0 then
        local totalHealthSum = 0
        local validUnits = 0

        for _, unitId in ipairs(GameState.selectedUnits) do
            local unit = GameState.units[unitId]
            if unit and unit.entity and DoesEntityExist(unit.entity) then
                local pct = 0
                if IsEntityAVehicle(unit.entity) then
                    local currentBody = GetVehicleBodyHealth(unit.entity)
                    local maxBody = (Config.Units[unit.type] and Config.Units[unit.type].health) or 1000.0
                    pct = (currentBody / maxBody) * 100
                else
                    local hp = GetEntityHealth(unit.entity)
                    local max = GetEntityMaxHealth(unit.entity)
                    pct = (hp / max) * 100
                end
                if pct > 100 then pct = 100 end
                if pct < 0 then pct = 0 end
                totalHealthSum = totalHealthSum + pct
                validUnits = validUnits + 1
            end
        end

        if validUnits > 0 then
            healthPercent = math.floor(totalHealthSum / validUnits)
        end
    end

    SendNUIMessage({
        action = 'updateSelection',
        count = count,
        health = healthPercent
    })
end

function StartSelectionUpdater()
    CreateThread(function()
        while GameState.isInMatch do
            Wait(200)
            if #GameState.selectedUnits > 0 then
                for i = #GameState.selectedUnits, 1, -1 do
                    local unitId = GameState.selectedUnits[i]
                    local unit = GameState.units[unitId]
                    local isDead = false
                    if not unit or not unit.entity or not DoesEntityExist(unit.entity) then
                        isDead = true
                    elseif IsEntityAVehicle(unit.entity) then
                        if GetVehicleBodyHealth(unit.entity) <= 99 or IsEntityDead(unit.entity) then isDead = true end
                    else
                        if IsPedDeadOrDying(unit.entity, true) then isDead = true end
                    end
                    if isDead then table.remove(GameState.selectedUnits, i) end
                end
                UpdateSelectionUI()
            elseif #GameState.selectedUnits == 0 then
                UpdateSelectionUI()
            end
        end
    end)
end

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
    for _, unitId in ipairs(GameState.selectedUnits) do
        local unit = GameState.units[unitId]
        if unit and unit.entity and DoesEntityExist(unit.entity) then
        end
    end
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
                local needsUpdate = false
                
                for i = #GameState.selectedUnits, 1, -1 do
                    local unitId = GameState.selectedUnits[i]
                    local unit = GameState.units[unitId]
                    
                    local isDead = false
                    
                    if not unit or not unit.entity or not DoesEntityExist(unit.entity) then
                        isDead = true
                    else
                        
                        if IsEntityAVehicle(unit.entity) then
                            if GetVehicleBodyHealth(unit.entity) <= 99 or IsEntityDead(unit.entity) then
                                isDead = true
                            end
                        else
                            if IsPedDeadOrDying(unit.entity, true) then
                                isDead = true
                            end
                        end
                    end
                    
                    if isDead then
                        table.remove(GameState.selectedUnits, i)
                        needsUpdate = true
                    end
                end
                
                UpdateSelectionUI()
                
            elseif #GameState.selectedUnits == 0 then
                 
                 UpdateSelectionUI()
            end
        end
    end)
end

function StartSelectionRenderer()
    CreateThread(function()
        while GameState.isInMatch do
            Wait(0) 
            
            for _, unitId in ipairs(GameState.selectedUnits) do
                local unit = GameState.units[unitId]
                
                if unit and unit.entity and DoesEntityExist(unit.entity) and GetEntityHealth(unit.entity) > 0 then
                    local pos = GetEntityCoords(unit.entity)
                    local markerZ = pos.z
                    local markerScale = 0.5
                    
                    if IsEntityAVehicle(unit.entity) then
                        local min, max = GetModelDimensions(GetEntityModel(unit.entity))
                        local height = max.z - min.z
                        local width = max.x - min.x
                        
                        markerZ = pos.z + max.z + 1.5 
                        markerScale = width * 0.5 
                    else
                        
                        markerZ = pos.z + 1.3
                    end
                    
                    DrawMarker(
                        0,                  
                        pos.x, pos.y, markerZ + 0.3, 
                        0.0, 0.0, 0.0,      
                        0.0, 0.0, 0.0,      
                        markerScale, markerScale, markerScale, 
                        0, 255, 0, 200,     
                        true, true, 2, false, nil, nil, false
                    )
                    
                    DrawMarker(25, pos.x, pos.y, pos.z - 0.5, 0,0,0, 0,0,0, markerScale*2, markerScale*2, 1.0, 0,255,0,150, false, false, 2, false, nil, nil, false)
                end
            end
        end
    end)
end

function SelectUnitsInRectangle(rect)
    DeselectAllUnits()
    
    local screenW, screenH = GetActiveScreenResolution()
    local selectedCount = 0
    
    local minX = math.min(rect.x1, rect.x2)
    local maxX = math.max(rect.x1, rect.x2)
    local minY = math.min(rect.y1, rect.y2)
    local maxY = math.max(rect.y1, rect.y2)
    
    for unitId, unit in pairs(GameState.units) do
        if unit.entity and DoesEntityExist(unit.entity) then
            local unitPos = GetEntityCoords(unit.entity)
            local onScreen, normX, normY = ProjectWorldToScreen(unitPos.x, unitPos.y, unitPos.z)
            
            if onScreen then
                
                local pixelX = normX * screenW
                local pixelY = normY * screenH
                
                if pixelX >= minX and pixelX <= maxX and pixelY >= minY and pixelY <= maxY then
                    table.insert(GameState.selectedUnits, unitId)
                    
                    selectedCount = selectedCount + 1
                end
            end
        end
    end
    
    UpdateSelectionUI()
    
    if selectedCount > 0 then
        PlaySoundFrontend(-1, Config.Sounds.UnitSelection, "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end

function GetUnitAtScreenPosition(cursorX, cursorY)
    local screenW, screenH = GetActiveScreenResolution()
    local closestUnit = nil
    local closestDist = 100.0 

    for unitId, unit in pairs(GameState.units) do
        if unit.entity and DoesEntityExist(unit.entity) then
            local unitPos = GetEntityCoords(unit.entity)
            
            local onScreen, normX, normY = ProjectWorldToScreen(unitPos.x, unitPos.y, unitPos.z)
            
            if onScreen then
                
                local pixelX = normX * screenW
                local pixelY = normY * screenH
                
                local dist = math.sqrt((cursorX - pixelX)^2 + (cursorY - pixelY)^2)
                
                if dist < closestDist then
                    closestDist = dist
                    closestUnit = unitId
                end
            end
        end
    end
    
    return closestUnit
end
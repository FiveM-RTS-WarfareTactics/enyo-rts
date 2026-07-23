-- Weapon modifiers are handled by rts-weapons resource (auto-applies on start)

function AdminEmergencyBreakState()
    DebugPrint("^1[RTS ADMIN] Executing hard local state purge...^7")
    
    RenderScriptCams(false, false, 0, true, true)
    if GameState.camera then DestroyCam(GameState.camera, false); GameState.camera = nil end
    ClearFocus()
    
    -- DROP UI HOOKS
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'hideUI' })
    SendNUIMessage({ action = 'stopAirstrikeTimer' })

    -- RESTORE CONTROLS (This fixes the stuck mouse/keyboard)
    EnableAllControlActions(0)
    EnableControlAction(0, 1, true)
    EnableControlAction(0, 2, true)
    EnableControlAction(0, 24, true)
    EnableControlAction(0, 25, true)

    GameState.isInMatch = false; GameState.isInLobby = false
    GameState.playerReady = false; GameState.selectedUnits = {}
    matchLoopRunning = false
    
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    SetEntityCollision(ped, true, true)
    SetEntityHasGravity(ped, true)
    SetEntityInvincible(ped, false)
    
    local coords = GetEntityCoords(ped)
    if coords.z > 500.0 then
        SetEntityCoords(ped, 0.0, 0.0, 70.0, false, false, false, false)
    end
    
    DisplayRadar(true); DisplayHud(true)
    StopAudioScene("CHARACTER_CHANGE_IN_SKY_SCENE")
    SendNUIMessage({action = 'showNotification', message = "RTS client engine state has been forcibly reset.", type = "success"})
end

exports('ForceClientReset', AdminEmergencyBreakState)

-- Environment Lock System
local OriginalEnvironment = {
    saved = false,
    hour = nil,
    minute = nil,
    weather = nil
}

environmentThreadRunning = false

function StartEnvironmentLock()
    if environmentThreadRunning then return end
    environmentThreadRunning = true
    StopAudioScene("CHARACTER_CHANGE_IN_SKY_SCENE")
    CreateThread(function()
        local mapData = Config.Maps[GameState.currentMap]
        if not mapData then 
            environmentThreadRunning = false
            return 
        end

        -- =============================
        -- SAVE ORIGINAL ENVIRONMENT
        -- =============================
        if not OriginalEnvironment.saved then
            local h = GetClockHours()
            local m = GetClockMinutes()
            local w = GetPrevWeatherTypeHashName()

            OriginalEnvironment.hour = h
            OriginalEnvironment.minute = m
            OriginalEnvironment.weather = w
            OriginalEnvironment.saved = true

            DebugPrint("[RTS] Saved environment:", h, m, w)
        end

        local targetH = mapData.time?.h or 12
        local targetM = mapData.time?.m or 0
        local targetWeather = mapData.weather or "EXTRASUNNY"

        DebugPrint("[RTS] Locking Environment:", targetH, targetM, targetWeather)

        -- =============================
        -- DISABLE EXTERNAL SYNC
        -- =============================
        TriggerEvent('qb-weathersync:client:DisableSync')
        TriggerEvent('cd_easytime:PauseSync', true)

        -- =============================
        -- FORCE INITIAL STATE
        -- =============================
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        SetWeatherTypeOvertimePersist(targetWeather, 0.0)
        SetWeatherTypePersist(targetWeather)
        SetWeatherTypeNowPersist(targetWeather)
        SetWeatherTypeNow(targetWeather)

        -- =============================
        -- ENFORCEMENT LOOP
        -- =============================
        while GameState.isInMatch do
            NetworkOverrideClockTime(targetH, targetM, 0)
            SetClockTime(targetH, targetM, 0)

            SetWeatherTypeNowPersist(targetWeather)
            SetWeatherTypeNow(targetWeather)

            if targetWeather == "EXTRASUNNY" or targetWeather == "CLEAR" then
                SetRainLevel(0.0)
                SetWind(0.0)
            end

            Wait(0)
        end

        -- =============================
        -- RESTORE ENVIRONMENT
        -- =============================
        RestoreEnvironment()
        environmentThreadRunning = false
    end)
end

function RestoreEnvironment()
    if not OriginalEnvironment.saved then return end

    DebugPrint("[RTS] Restoring environment")

    -- Clear overrides
    NetworkClearClockTimeOverride()
    ClearWeatherTypePersist()
    ClearOverrideWeather()

    -- Restore time
    SetClockTime(
        OriginalEnvironment.hour,
        OriginalEnvironment.minute,
        0
    )

    -- Restore weather
    SetWeatherTypeOvertimePersist(OriginalEnvironment.weather, 5.0)

    -- Re-enable sync scripts
    TriggerEvent('qb-weathersync:client:EnableSync')
    TriggerEvent('cd_easytime:PauseSync', false)

    -- Force immediate server sync
    TriggerServerEvent('qb-weathersync:server:RequestStateSync')

    -- Reset saved state
    OriginalEnvironment.saved = false
end

function ManageEnvironment()
    if environmentThreadRunning then return end
  --  environmentThreadRunning = true

    CreateThread(function()
        while true do
            if GameState.isInMatch then
                -- MATCH MODE: Let StartEnvironmentLock() handle map-specific settings
                -- We break the void loop so your match logic takes over
             --   environmentThreadRunning = false
                break
            else
                -- LOBBY/MENU MODE: Freeze to Midnight/Clear
                NetworkOverrideClockTime(0, 0, 0)
                SetWeatherTypePersist("CLEAR")
                SetWeatherTypeNowPersist("CLEAR")
                SetOverrideWeather("CLEAR")
                
                -- Kill ambient sounds
                StartAudioScene("CHARACTER_CHANGE_IN_SKY_SCENE") 
                
                -- Hide stuff if it somehow appears
                DisplayRadar(false)
                DisplayHud(false)
            end
            Wait(1000)
        end
    end)
end



-- Weapon modifiers are handled by rts-weapons resource (auto-applies on start)

function ForceClientReset()
    if GameState.camera then DestroyCam(GameState.camera, false); GameState.camera = nil end
    RenderScriptCams(false, true, 500, true, true)

    GameState.isInMatch = false
    GameState.isInLobby = false
    GameState.selectedUnits = {}

    local ped = PlayerPedId()
    SetEntityCoords(ped, 0.0, 0.0, 1000.0)
    SetEntityVisible(ped, false)
    SetEntityCollision(ped, false)
    SetEntityHasGravity(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)

    SendNUIMessage({ action = 'returnToMenu' })
    OpenRTSCentral()
end

exports('ForceClientReset', ForceClientReset)

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



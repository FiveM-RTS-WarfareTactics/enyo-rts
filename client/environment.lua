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

function ApplyMapEnvironment()
    local map = Config.Maps[GameState.currentMap]
    if not map then return end

    local h = map.time and map.time.h or 12
    local m = map.time and map.time.m or 0
    local weather = map.weather or "EXTRASUNNY"

    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetWeatherTypeOvertimePersist(weather, 0.0)
    SetWeatherTypeNowPersist(weather)

    CreateThread(function()
        while GameState.isInMatch do
            NetworkOverrideClockTime(h, m, 0)
            SetWeatherTypeNowPersist(weather)

            if weather == "EXTRASUNNY" or weather == "CLEAR" then
                SetRainLevel(0.0)
            end

            Wait(5000)
        end
    end)
end

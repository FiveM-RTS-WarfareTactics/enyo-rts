if Config.DedicatedServerMode then
    local hasGameStarted = false

    local function SafeStartDedicated()
        if hasGameStarted then return end
        hasGameStarted = true

        CreateThread(function()
            -- Give the HTML/JS 500ms to boot up on script restart
            Wait(2500)

            -- 1. Hide World Immediately
            local ped = PlayerPedId()
            while not DoesEntityExist(ped) do Wait(0) ped = PlayerPedId() end
            
            -- Random distance (using sqrt for even distribution inside the circle) and random angle
local dist = 300.0 * math.sqrt(math.random())
local angle = math.random() * (2 * math.pi)

-- Calculate new X and Y based on the center point (-247.76, 6331.23)
local newX = -247.76 + (dist * math.cos(angle))
local newY = 6331.23 + (dist * math.sin(angle))

-- Teleport instantly to the new coords at Z = 1000.0
SetEntityCoords(ped, newX, newY, 1000.0, false, false, false, false)
            FreezeEntityPosition(ped, true)
            SetEntityVisible(ped, false, false)
            SetEntityCollision(ped, false, false)
            SetEntityHasGravity(ped, false) -- Stops initial falling sound
            
            DisplayRadar(false)
            DisplayHud(false)

            -- 2. Wait for native loading screens to end
            while GetIsLoadingScreenActive() do Wait(100) end
            while IsPlayerSwitchInProgress() do Wait(100) end

            -- 3. Open UI
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            
            -- Force the menu open
            OpenRTSCentral()
        end)
    end

    AddEventHandler('onResourceStart', function(res) if GetCurrentResourceName() == res then SafeStartDedicated() end end)
    AddEventHandler('playerSpawned', function() SafeStartDedicated() end)
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() SafeStartDedicated() end)
    RegisterNetEvent('esx:playerLoaded', function() SafeStartDedicated() end)
end

RegisterCommand('rts', function()
    if not GameState.isInMatch then
        if Config.DedicatedServerMode then
            local ped = PlayerPedId()
            SetEntityCoords(ped, 0.0, 0.0, 1000.0, false, false, false, false)
            FreezeEntityPosition(ped, true)
            SetEntityVisible(ped, false, false)
            SetEntityCollision(ped, false, false)
            SetEntityHasGravity(ped, false)
            SetEntityInvincible(ped, true)
        end
        
        SendNUIMessage({ action = 'unhideUI' }) -- Force HTML back to visible
        OpenRTSCentral() -- Populate everything
    else
        QBCore.Functions.Notify("You are already in an active match!", "error")
    end
end, false)

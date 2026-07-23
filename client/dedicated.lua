-- =============================================================================
--  DEDICATED GAME MODE - Auto-initialize RTS on player spawn
--  This is a standalone game mode. Players see the RTS menu on connect.
--  No toggle command exists. Exit = disconnect via NUI callback.
-- =============================================================================

CreateThread(function()
    Wait(2000)

    local ped = PlayerPedId()
    SetEntityCoords(ped, 0.0, 0.0, 1000.0)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)

    SendNUIMessage({ action = 'openMenu' })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
end)

-- =============================================================================
--  ANTICHEAT: UI integrity heartbeat
--  Responds to server pings to prove NUI is still active.
-- =============================================================================

RegisterNetEvent('rts:anticheat:requestHeartbeat')
AddEventHandler('rts:anticheat:requestHeartbeat', function()
    -- Verify NUI focus is still held (cheater can't call SetNuiFocus(false))
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    TriggerServerEvent('rts:anticheat:heartbeat')
end)

-- =============================================================================
--  ADMIN COMMAND: Force-reopen the menu (ACE-gated, for stuck players)
-- =============================================================================

RegisterCommand('rts', function(source)
    if source > 0 then
        local hasPerms = IsPlayerAceAllowed(source, "command") or IsPlayerAceAllowed(source, "command.rtsadmin")
        if not hasPerms then return end
    end
    SendNUIMessage({ action = 'openMenu' })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
end, false)

-- =============================================================================
--  SCREENSHOT HANDLER
-- =============================================================================

RegisterNetEvent('enyo-rts:client:takeScreenshot', function(webhookUrl)
    if GetResourceState('screenshot-basic') == 'started' then
        exports['screenshot-basic']:requestScreenshotUpload(webhookUrl, 'files[]', {
            encoding = 'webp',
            quality = 0.1
        }, function(data) end)
    end
end)


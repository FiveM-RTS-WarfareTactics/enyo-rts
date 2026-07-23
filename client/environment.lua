-- =============================================================================
--  ENVIRONMENT MODULE - Game mode lifecycle helpers
-- =============================================================================

function ForceClientReset()
    CleanupMatch(true)
    SendNUIMessage({ action = 'returnToMenu' })
    GameState.isInLobby = false
    GameState.playerReady = false
    GameState.isInMatch = false
end

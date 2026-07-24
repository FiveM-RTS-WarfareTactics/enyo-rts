-- =============================================================================
--  SHARED UTILITY FUNCTIONS (Standalone - No Framework Dependencies)
-- =============================================================================

function DebugPrint(msg)
    if Config.DebugMode then
        print("^3[RTS]^7 " .. msg)
    end
end

function GetTableSize(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

-- =============================================================================
--  NOTIFICATION SYSTEM (NUI-based for standalone game mode)
-- =============================================================================

--- Server-side: sends a notification to a player via NUI
--- @param source number Player server ID
--- @param message string
--- @param notifType string "success"|"error"|"info"|"warning"
function NotifyPlayer(source, message, notifType)
    TriggerClientEvent('rts:nuiNotify', source, {
        message = message,
        type = notifType or "info"
    })
end

--- Client-side notification using TheFeed (fallback)
function ClientNotify(text)
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, true)
end

-- =============================================================================
--  SERVER CALLBACK SYSTEM (Standalone)
-- =============================================================================
ServerCallbacks = {}

--- Registers a server callback
--- @param name string
--- @param cb function
function RegisterServerCallback(name, cb)
    ServerCallbacks[name] = cb
end

--- Triggers a server callback from client side
--- Must be paired with client-side callback handler
ClientCallbacks = ClientCallbacks or {}

function TriggerServerCallback(name, cb, ...)
    local requestId = GetGameTimer() -- Simple unique-ish ID
    ClientCallbacks[requestId] = cb
    TriggerServerEvent('rts:standalone:triggerCallback', name, requestId, ...)
end

-- =============================================================================
--  PLAYER IDENTITY HELPERS
-- =============================================================================

--- Get a safe identifier for a player (license preferred, falls back to name)
--- @param source number
--- @return string
function GetPlayerIdentifier(source)
    local license = GetPlayerIdentifierByType(source, 'license')
    if license then return license end
    return "rts_local_" .. GetPlayerName(source)
end

--- Get player display name
--- @param source number
--- @return string
function GetRTSName(source)
    return GetPlayerName(source)
end

-- =============================================================================
--  MATCH LEVEL CALCULATOR
-- =============================================================================

function CalculateLevel(totalScore)
    local score = math.floor(totalScore or 0)
    local level = 1
    local xpForNext = 3000
    local xpCurve = 1.048

    while true do
        if score < xpForNext then
            return {
                level = level,
                currentXP = score,
                requiredXP = xpForNext,
                percent = math.floor((score / xpForNext) * 100)
            }
        end
        score = score - xpForNext
        level = level + 1
        xpForNext = math.floor(xpForNext * xpCurve)
    end
end

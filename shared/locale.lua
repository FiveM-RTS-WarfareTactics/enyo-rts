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

function NotifyPlayer(source, message, notifType)
    TriggerClientEvent('rts:nuiNotify', source, {
        message = message,
        type = notifType or "info"
    })
end

function ClientNotify(text)
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, true)
end

ServerCallbacks = {}

function RegisterServerCallback(name, cb)
    ServerCallbacks[name] = cb
end

ClientCallbacks = ClientCallbacks or {}

function TriggerServerCallback(name, cb, ...)
    local requestId = GetGameTimer() 
    ClientCallbacks[requestId] = cb
    TriggerServerEvent('rts:standalone:triggerCallback', name, requestId, ...)
end

function GetPlayerIdentifier(source)
    local license = GetPlayerIdentifierByType(source, 'license')
    if license then return license end
    return "rts_local_" .. GetPlayerName(source)
end

function GetRTSName(source)
    return GetPlayerName(source)
end

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
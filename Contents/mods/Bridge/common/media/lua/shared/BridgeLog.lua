



BridgeLog = {}

function BridgeLog.on()
    if BridgeBuild ~= nil and BridgeBuild.test == true then return true end
    if Bridge ~= nil and Bridge.verbose == true then return true end
    if BridgeServer ~= nil and BridgeServer.verbose == true then return true end
    return false
end

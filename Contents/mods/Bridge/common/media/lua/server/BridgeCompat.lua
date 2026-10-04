BridgeCompat = BridgeCompat or {}
BridgeCompat.wrapped = nil
BridgeCompat.ticks = 0

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeCompat] " .. tostring(text)) end end
local function warn(text) print("[BridgeCompat] " .. tostring(text)) end

local function modActive(id)
    local on = false
    pcall(function()
        local mods = getActivatedMods()
        on = mods ~= nil and (mods:contains(id) or mods:contains("\\" .. id))
    end)
    return on
end

function BridgeCompat.isOurBody(z)
    local ours = false
    if BridgeServer ~= nil and type(BridgeServer.isCompanionBody) == "function" then
        pcall(function() ours = BridgeServer.isCompanionBody(z) end)
    end
    return ours
end

function BridgeCompat.install()
    local pzm = rawget(_G, "PZTheMutants")
    local fo = pzm ~= nil and pzm.ForeignOwnership or nil
    if fo == nil or type(fo.isClaimed) ~= "function" then return false end
    if fo.isClaimed == BridgeCompat.wrapped then return true end
    local original = fo.isClaimed
    local wrapper
    wrapper = function(zombie, outfitName)
        local claimed, owner, reason = original(zombie, outfitName)
        if claimed then return claimed, owner, reason end
        if BridgeCompat.isOurBody(zombie) then return true, "Bridge", "companion-marker" end
        return claimed, owner, reason
    end
    BridgeCompat.wrapped = wrapper
    fo.isClaimed = wrapper
    log("PZTheMutants compat guard installed")
    return true
end

function BridgeCompat.tick()
    if not modActive("PZTheMutants") then return end
    BridgeCompat.ticks = BridgeCompat.ticks + 1
    if BridgeCompat.ticks > 1 and BridgeCompat.ticks % 60 ~= 0 then return end
    BridgeCompat.install()
end

Events.OnTick.Add(function() pcall(BridgeCompat.tick) end)
Events.OnGameStart.Add(function() BridgeCompat.ticks = 0 pcall(BridgeCompat.install) end)
Events.OnServerStarted.Add(function() BridgeCompat.ticks = 0 pcall(BridgeCompat.install) end)

BridgeCompat = BridgeCompat or {}
BridgeCompat.wrapped = nil
BridgeCompat.wrappedVariant = nil
BridgeCompat.ticks = 0
BridgeCompat.missingLogged = false

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

function BridgeCompat.isOurId(pid)
    local ours = false
    if BridgeServer ~= nil and type(BridgeServer.isCompanionId) == "function" then
        pcall(function() ours = BridgeServer.isCompanionId(pid) end)
    end
    return ours
end

function BridgeCompat.install()
    local pzm = rawget(_G, "PZTheMutants")
    local installed = false

    local fo = pzm ~= nil and pzm.ForeignOwnership or nil
    if fo ~= nil and type(fo.isClaimed) == "function" then
        if fo.isClaimed ~= BridgeCompat.wrapped then
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
        end
        installed = true
    end

    local identity = pzm ~= nil and pzm.Identity or nil
    if identity ~= nil and type(identity.getPersistentVariant) == "function" then
        if identity.getPersistentVariant ~= BridgeCompat.wrappedVariant then
            local originalVariant = identity.getPersistentVariant
            local wrapperVariant = function(persistentOutfitID)
                if BridgeCompat.isOurId(persistentOutfitID) then return nil end
                return originalVariant(persistentOutfitID)
            end
            BridgeCompat.wrappedVariant = wrapperVariant
            identity.getPersistentVariant = wrapperVariant
            log("PZTheMutants variant guard installed")
        end
        installed = true
    end

    if installed then
        BridgeCompat.missingLogged = false
        return true
    end

    if not BridgeCompat.missingLogged then
        BridgeCompat.missingLogged = true
        warn("PZTheMutants gate not found; compat guard will keep retrying")
    end
    return false
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

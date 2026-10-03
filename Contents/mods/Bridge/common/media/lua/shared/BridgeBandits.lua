


























BridgeBandits = BridgeBandits or {}

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeBandits] " .. tostring(text)) end end
local function warn(text) print("[BridgeBandits] " .. tostring(text)) end

local BODY_VAR = "NotAloneBody"


function BridgeBandits.hers(z)
    if z == nil then return false end
    if Bridge ~= nil and Bridge.body == z then return true end
    if z:getVariableBoolean(BODY_VAR) == true then return true end


    if z:hasModData() and z:getModData().notAloneBody == true then return true end




    local B = Bridge
    if B == nil or not B.mp or B.bodyIndex == nil or B.world == nil or B.world.players == nil then return false end
    local yes = false
    pcall(function()
        local pid = z:getPersistentOutfitID()
        local who = B.bodyIndex[pid]
        local rec = who ~= nil and B.world.players[who] or nil
        yes = rec ~= nil and rec.bodyId == pid and (rec.onlineId == nil or rec.onlineId == z:getOnlineID())
    end)
    return yes
end



function BridgeBandits.windowClose(z)
    local near = false
    pcall(function()
        local bx, by, bz = math.floor(z:getX()), math.floor(z:getY()), z:getZ()
        local cell = getCell()
        for x = -1, 1 do
            for y = -1, 1 do
                local sq = cell:getGridSquare(bx + x, by + y, bz)
                if sq ~= nil and not near then
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        local o = objects:get(i)
                        if o ~= nil and (instanceof(o, "IsoWindow") or instanceof(o, "IsoWindowFrame") or instanceof(o, "IsoThumpable"))
                            and o:canClimbThrough(z) then
                            near = true
                            break
                        end
                    end
                end
            end
        end
    end)
    return near
end

local function active(id)
    local on = false
    pcall(function()
        local mods = getActivatedMods()
        on = mods:contains(id) or mods:contains("\\" .. id)
    end)
    return on
end



function BridgeBandits.install()
    if type(BanditCompatibility) ~= "table" or type(BanditCompatibility.IsReanimatedForGrappleOnly) ~= "function" then
        return false
    end
    if BanditCompatibility.IsReanimatedForGrappleOnly == BridgeBandits.skip then return true end
    local original = BanditCompatibility.IsReanimatedForGrappleOnly
    BridgeBandits.skip = function(zombie)
        if BridgeBandits.hers(zombie) then return true end
        return original(zombie)
    end
    BanditCompatibility.IsReanimatedForGrappleOnly = BridgeBandits.skip
    BanditCompatibility.bridgeSkip = true
    log("Bandits: her body is skipped (IsReanimatedForGrappleOnly)")
    return true
end

if BridgeBandits.wanted == nil then BridgeBandits.wanted = active("Bandits2") end
if BridgeBandits.wanted then
    pcall(function() require "BanditCompatibility" end)
    if not BridgeBandits.install() then log("Bandits active, but BanditCompatibility.IsReanimatedForGrappleOnly not found") end
end








function BridgeBandits.wrapHit()
    if type(BanditUtils) ~= "table" or type(BanditUtils.Hit) ~= "function" or BanditUtils.Hit == BridgeBandits.hit then return end
    local hit = BanditUtils.Hit
    local last = nil
    BridgeBandits.hit = function(shooter, item, victim, ...)
        if BridgeBandits.hers(victim) then
            local now = getTimestampMs()
            if last ~= nil and last.shooter == shooter and now - last.t <= 1 then return last.landed end
            return false
        end
        local landed = hit(shooter, item, victim, ...)
        last = { shooter = shooter, landed = landed, t = getTimestampMs() }
        return landed
    end
    BanditUtils.Hit = BridgeBandits.hit
    log("Bandits: stray bullets pass through her")
end



function BridgeBandits.check()
    if Bridge == nil or Bridge.body == nil or type(BanditZombie) ~= "table" or type(BanditZombie.Cache) ~= "table"
        or type(BanditUtils) ~= "table" or type(BanditUtils.GetZombieID) ~= "function" then return nil end
    local seen = false
    pcall(function() seen = BanditZombie.Cache[BanditUtils.GetZombieID(Bridge.body)] == Bridge.body end)
    if seen and not BridgeBandits.warned then
        BridgeBandits.warned = true
        log("Bandits still sees her body: skip does not work (Bandits updated?)")
    elseif not seen then
        BridgeBandits.warned = nil
    end

    if BanditCompatibility ~= nil and BanditCompatibility.IsReanimatedForGrappleOnly ~= BridgeBandits.skip then
        BridgeBandits.install()
    end
    return seen
end









BridgeBandits.corpses = BridgeBandits.corpses or {}

function BridgeBandits.forgetCorpse(x, y, z)
    if type(BWOScheduler) ~= "table" then return false end
    BridgeBandits.corpses[#BridgeBandits.corpses + 1] = { x = x, y = y, z = z }
    return true
end


function BridgeBandits.corpseTick()
    if #BridgeBandits.corpses == 0 then return end
    local list = BridgeBandits.corpses
    BridgeBandits.corpses = {}
    for _, c in ipairs(list) do


        local real = false
        pcall(function()
            local sq = getCell():getGridSquare(math.floor(c.x), math.floor(c.y), math.floor(c.z))
            real = sq ~= nil and sq:getDeadBody() ~= nil
        end)
        if real then
            log("Week One: a real corpse lies where she died, its record kept")
        else
            local ok, err = pcall(function() sendClientCommand(getSpecificPlayer(0), "Commands", "DeadBodyRemove", c) end)
            if ok then
                log(string.format("Week One: her corpse record removed at %.1f,%.1f,%.1f", c.x, c.y, c.z))
            else
                warn("Week One: her corpse record not removed: " .. tostring(err))
            end
        end
    end
end

if BridgeBandits.wanted and not BridgeBandits.eventsAdded and Events ~= nil then
    BridgeBandits.eventsAdded = true
    Events.OnGameStart.Add(function() pcall(BridgeBandits.wrapHit) end)
    if Events.EveryOneMinute ~= nil then
        Events.EveryOneMinute.Add(function()
            if not isServer() then pcall(BridgeBandits.check) end
        end)
    end
end

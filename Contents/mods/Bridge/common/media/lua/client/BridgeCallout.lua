BridgeCallout = BridgeCallout or {}

BridgeCallout.MIN_GAP = 240
BridgeCallout.AMBIENT_GAP = 600
BridgeCallout.HORDE_COUNT = 10
BridgeCallout.BEHIND_DIST = 6
BridgeCallout.SPOT_DIST = 15
BridgeCallout.LULL_DIST = 8
BridgeCallout.FLANK_DIST = 8
BridgeCallout.CRAWLER_DIST = 3
BridgeCallout.BREACH_DIST = 5
BridgeCallout.MELEE_DIST = 6
BridgeCallout.PLAYER_KILL_DIST = 10
BridgeCallout.COMBAT_GRACE = 240
BridgeCallout.FINISH_HP = 0.5
BridgeCallout.PLAYER_HIT_DROP = 1.0
BridgeCallout.STRIKE_MEMORY = 600

BridgeCallout.lastAny = -99999
BridgeCallout.deferred = {}
BridgeCallout.fightingAt = -99999
BridgeCallout.wasFighting = false
BridgeCallout.pendingKill = nil
BridgeCallout.strikes = {}
BridgeCallout.lastHealth = nil
BridgeCallout.finisherTarget = nil
BridgeCallout.info = "none"

--Callout cooldowns
BridgeCallout.EVENTS = {
    EvBehind     = { slot = "Behind",     cooldown = 45 * 60 },
    EvEngage     = { slot = "Engage",     cooldown = 25 * 60 },
    EvKill       = { slot = "Kill",       cooldown = 20 * 60 },
    EvHorde      = { slot = "Horde",      cooldown = 75 * 60 },
    EvBreakOff   = { slot = "BreakOff",   cooldown = 30 * 60 },
    EvSpot       = { slot = "Spot",       cooldown = 120 * 60 },
    EvLull       = { slot = "Lull",       cooldown = 150 * 60 },
    EvPlayerKill = { slot = "PlayerKill", cooldown = 20 * 60 },
    EvPlayerHit  = { slot = "PlayerHit",  cooldown = 30 * 60 },
    EvFlank      = { slot = "Flank",      cooldown = 45 * 60 },
    EvFinisher   = { slot = "Finisher",   cooldown = 30 * 60 },
    EvCrawler    = { slot = "Crawler",    cooldown = 60 * 60 },
    EvBreach     = { slot = "Breach",     cooldown = 90 * 60 },
    EvLostTarget = { slot = "LostTarget", cooldown = 60 * 60 },
    EvChatter    = { slot = "Chatter",    cooldown = 100 * 60, ambient = true },
    EvEncourage  = { slot = "Encourage",  cooldown = 120 * 60, ambient = true },
    EvTaunt      = { slot = "Taunt",      cooldown = 150 * 60, ambient = true },
}

BridgeCallout.AMBIENT = { "EvChatter", "EvEncourage", "EvTaunt" }

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeCallout] " .. tostring(text)) end end

local function isBodyZ(z)
    local ok, v = pcall(function() return z:getVariableBoolean("NotAloneBody") end)
    return ok and v
end

local function remoteZ(z)
    if not isClient() then return false end
    local ok, v = pcall(function() return z:isRemoteZombie() end)
    return ok and v
end

local function deadZ(z)
    local dead = false
    pcall(function() dead = (not z:isAlive()) or z:isDead() or z:getHealth() <= 0 end)
    return dead == true
end

local function proneZ(z)
    local prone = false
    pcall(function()
        local asn = z:getActionStateName()
        prone = z:isProne() or z:isCrawling() or asn == "onground" or asn == "sitonground"
    end)
    return prone == true
end

local function threatZ(z, body)
    local alive = false
    pcall(function() alive = z:isAlive() and z:getHealth() > 0 end)
    return z ~= nil and z ~= body and alive and not isBodyZ(z) and not remoteZ(z) and not BridgeData.harmless(z)
end

local function target()
    local t = nil
    pcall(function() if BridgeFight ~= nil then t = BridgeFight.target end end)
    return t
end

local function nearTarget(body)
    local t = target()
    if t == nil then return false end
    local d = 99
    pcall(function() d = math.sqrt((t:getX() - body:getX()) ^ 2 + (t:getY() - body:getY()) ^ 2) end)
    return d <= BridgeCallout.MELEE_DIST
end

local DEFER = { EvKill = true }

local function trySay(event)
    local e = BridgeCallout.EVENTS[event]
    if e == nil then return false end
    local gap = e.ambient and BridgeCallout.AMBIENT_GAP or BridgeCallout.MIN_GAP
    if Bridge.time - BridgeCallout.lastAny < gap then return false end
    local said = false
    pcall(function() said = BridgeMoments.say(event, e.cooldown, true, e.slot) == true end)
    if said then
        BridgeCallout.lastAny = Bridge.time
        BridgeCallout.info = event
        log(event)
    else
        BridgeCallout.info = "blocked " .. event
    end
    return said
end

function BridgeCallout.defer(event)
    local q = BridgeCallout.deferred
    for _, item in ipairs(q) do if item == event then return false end end
    if #q >= 4 then table.remove(q, 1) end
    q[#q + 1] = event
    return true
end

local function say(event)
    if trySay(event) then return true end
    if DEFER[event] then BridgeCallout.defer(event) end
    return false
end

local function flush()
    local q = BridgeCallout.deferred
    local i = 1
    while i <= #q do
        local ev = q[i]
        if trySay(ev) then
            table.remove(q, i)
            return true
        end
        i = i + 1
    end
    return false
end

local function countNear(body, radius)
    local n = 0
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if threatZ(z, body) then
                local dx, dy = z:getX() - body:getX(), z:getY() - body:getY()
                if dx * dx + dy * dy < radius * radius and math.abs(z:getZ() - body:getZ()) < 0.8 then
                    n = n + 1
                end
            end
        end
    end)
    return n
end

local function scanBehind(body, red)
    local found = false
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if threatZ(z, body) and z ~= target() and math.abs(z:getZ() - red:getZ()) < 1 then
                local dx, dy = z:getX() - red:getX(), z:getY() - red:getY()
                if dx * dx + dy * dy < BridgeCallout.BEHIND_DIST * BridgeCallout.BEHIND_DIST then
                    local seeBody, seeRed = false, false
                    pcall(function() seeBody = body:CanSee(z) end)
                    pcall(function() seeRed = red:CanSee(z) end)
                    if seeBody and not seeRed then found = true break end
                end
            end
        end
    end)
    return found
end

local function scanFlank(body, red)
    local found = false
    local fx, fy = 0, 0
    pcall(function()
        local f = red:getForwardDirection()
        fx, fy = f:getX(), f:getY()
    end)
    local fl = math.sqrt(fx * fx + fy * fy)
    if fl < 0.01 then return false end
    fx, fy = fx / fl, fy / fl
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if threatZ(z, body) and z ~= target() and math.abs(z:getZ() - red:getZ()) < 1 then
                local dx, dy = z:getX() - red:getX(), z:getY() - red:getY()
                local d2 = dx * dx + dy * dy
                if d2 > 2.25 and d2 < BridgeCallout.FLANK_DIST * BridgeCallout.FLANK_DIST then
                    local d = math.sqrt(d2)
                    local cross = fx * (dy / d) - fy * (dx / d)
                    if math.abs(cross) >= 0.7 then
                        local seen = false
                        pcall(function() seen = red:CanSee(z) end)
                        if seen then found = true break end
                    end
                end
            end
        end
    end)
    return found
end

local function scanCrawler(body, red)
    local found = false
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if threatZ(z, body) and proneZ(z) then
                local d = math.min(math.sqrt((z:getX() - body:getX()) ^ 2 + (z:getY() - body:getY()) ^ 2),
                    math.sqrt((z:getX() - red:getX()) ^ 2 + (z:getY() - red:getY()) ^ 2))
                if d < BridgeCallout.CRAWLER_DIST then
                    local seen = false
                    pcall(function() seen = red:CanSee(z) or body:CanSee(z) end)
                    if seen then found = true break end
                end
            end
        end
    end)
    return found
end

local function scanBreach(body, red)
    local found = false
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if threatZ(z, body) and tostring(z:getActionStateName()) == "thump" then
                local d = math.min(math.sqrt((z:getX() - body:getX()) ^ 2 + (z:getY() - body:getY()) ^ 2),
                    math.sqrt((z:getX() - red:getX()) ^ 2 + (z:getY() - red:getY()) ^ 2))
                if d < BridgeCallout.BREACH_DIST then
                    local seen = false
                    pcall(function() seen = red:CanSee(z) or body:CanSee(z) end)
                    if seen then found = true break end
                end
            end
        end
    end)
    return found
end

local function scanSpot(red)
    local found = false
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if threatZ(z, Bridge.body) and math.abs(z:getZ() - red:getZ()) < 1 then
                local dx, dy = z:getX() - red:getX(), z:getY() - red:getY()
                if dx * dx + dy * dy < BridgeCallout.SPOT_DIST * BridgeCallout.SPOT_DIST then
                    local seen = false
                    pcall(function() seen = BridgeFight.visible(z, red) end)
                    if seen then found = true break end
                end
            end
        end
    end)
    return found
end

local function scanFinisher()
    local t = target()
    if t == nil then return false end
    if t == BridgeCallout.finisherTarget then return false end
    local hp, low = 1, false
    pcall(function() hp = t:getHealth() low = hp <= BridgeCallout.FINISH_HP end)
    if low then BridgeCallout.finisherTarget = t return true end
    return false
end

function BridgeCallout.engage(z)
    if z == nil then return false end
    return say("EvEngage")
end

function BridgeCallout.kill(z)
    if z == nil then return false end
    if deadZ(z) then return say("EvKill") end
    BridgeCallout.pendingKill = z
    return false
end

function BridgeCallout.breakOff()
    return say("EvBreakOff")
end

function BridgeCallout.lostTarget()
    return say("EvLostTarget")
end

function BridgeCallout.playerStrike(z)
    if z == nil or z == Bridge.body then return false end
    if isBodyZ(z) or remoteZ(z) or BridgeData.harmless(z) then return false end
    local rec = { z = z, t = Bridge.time }
    pcall(function()
        local red = BridgeData.owner()
        if red ~= nil then
            rec.d = math.sqrt((z:getX() - red:getX()) ^ 2 + (z:getY() - red:getY()) ^ 2)
        end
    end)
    BridgeCallout.strikes[#BridgeCallout.strikes + 1] = rec
    return true
end

function BridgeCallout.behind()
    return say("EvBehind")
end

function BridgeCallout.horde(n)
    if n ~= nil and n < BridgeCallout.HORDE_COUNT then return false end
    return say("EvHorde")
end

function BridgeCallout.spot()
    return say("EvSpot")
end

function BridgeCallout.lull()
    return say("EvLull")
end

function BridgeCallout.update(body)
    if body == nil then return end
    if not Bridge.every(15) then return end
    if not Bridge.alive() then return end
    local red = BridgeData.owner()
    if red == nil then return end

    if flush() then return end

    local fighting = false
    pcall(function() if BridgeFight ~= nil then fighting = BridgeFight.state ~= "idle" end end)
    if fighting then
        BridgeCallout.wasFighting = true
        BridgeCallout.fightingAt = Bridge.time
    end
    if not fighting then BridgeCallout.finisherTarget = nil end
    local engaged = fighting or (Bridge.time - BridgeCallout.fightingAt < BridgeCallout.COMBAT_GRACE)

    local pk = BridgeCallout.pendingKill
    if pk ~= nil then
        BridgeCallout.pendingKill = nil
        if deadZ(pk) then say("EvKill") end
    end

    local strikes = BridgeCallout.strikes
    if #strikes > 0 then
        local keep = {}
        for _, s in ipairs(strikes) do
            if deadZ(s.z) then
                if engaged and (s.d or 99) <= BridgeCallout.PLAYER_KILL_DIST then say("EvPlayerKill") end
            elseif Bridge.time - s.t < BridgeCallout.STRIKE_MEMORY then
                keep[#keep + 1] = s
            end
        end
        BridgeCallout.strikes = keep
    end

    local health = nil
    pcall(function() health = red:getBodyDamage():getOverallBodyHealth() end)
    if health ~= nil then
        if fighting and BridgeCallout.lastHealth ~= nil
            and BridgeCallout.lastHealth - health >= BridgeCallout.PLAYER_HIT_DROP then
            say("EvPlayerHit")
        end
        BridgeCallout.lastHealth = health
    end

    if scanBreach(body, red) and say("EvBreach") then return end

    if fighting then
        if scanBehind(body, red) and say("EvBehind") then return end
        if scanFlank(body, red) and say("EvFlank") then return end
        if countNear(body, 4) >= BridgeCallout.HORDE_COUNT and say("EvHorde") then return end
        if scanCrawler(body, red) and say("EvCrawler") then return end
        if scanFinisher() and say("EvFinisher") then return end
        if nearTarget(body) then
            local start = 1 + ZombRand(#BridgeCallout.AMBIENT)
            for i = 0, #BridgeCallout.AMBIENT - 1 do
                if say(BridgeCallout.AMBIENT[1 + ((start - 1 + i) % #BridgeCallout.AMBIENT)]) then return end
            end
        end
        return
    end

    if BridgeCallout.wasFighting then
        BridgeCallout.wasFighting = false
        if not countNear(body, BridgeCallout.LULL_DIST) and say("EvLull") then return end
        return
    end

    local guard = false
    pcall(function() if BridgeFight ~= nil then guard = BridgeFight.guardOnly end end)
    if not guard and scanSpot(red) then say("EvSpot") end
end

log("loaded")
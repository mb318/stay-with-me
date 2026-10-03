








BridgeMoments = BridgeMoments or {}
BridgeMoments.cool = {}
BridgeMoments.known = nil
BridgeMoments.lastLine = -99999
BridgeMoments.lastCheck = 0
BridgeMoments.pending = {}
BridgeMoments.info = "none"

local GAP = 14400
local MINUTE = 3600


local HEALTH_STEPS = { 50, 30, 15 }
local HEALTH_EVENTS = { "EvHealthHalf", "EvDying", "EvDyingLast" }
local HEALTH_BACK = 10
BridgeMoments.healthStep = 0

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeMoments] " .. tostring(text)) end end
local function warn(text) print("[BridgeMoments] " .. tostring(text)) end


function BridgeMoments.group()
    local r = BridgeData.relOf(Bridge.store)
    if r == nil then return "Far" end
    if r.r >= 40 or r.f >= 75 then return "Close" end
    if r.f >= 20 then return "Near" end
    return "Far"
end

BridgeMoments.poolSize = {}
local function count(pool)
    local n = BridgeMoments.poolSize[pool]
    if n ~= nil then return n end
    n = 0
    for i = 1, 20 do
        local key = "IGUI_NotAlone_Soc_" .. pool .. "_" .. i
        local text = nil

        pcall(function() text = getTextOrNull(key, "", "") end)
        if text == nil or text == key or text == "" then break end
        n = i
    end
    BridgeMoments.poolSize[pool] = n
    return n
end


function BridgeMoments.line(event, a, b)
    local group = BridgeMoments.group()
    local pool = event .. "_" .. group
    if count(pool) == 0 then pool = event .. "_Near" end
    local n = count(pool)
    if n == 0 then return nil end
    local index = 1 + ZombRand(n)
    pcall(function() index = BridgeSocial.pick(pool, n) end)
    local key = "IGUI_NotAlone_Soc_" .. pool .. "_" .. index
    local text = nil
    pcall(function()
        if b ~= nil then text = getText(key, a, b)
        elseif a ~= nil then text = getText(key, a)
        else text = getText(key) end
    end)
    return text
end



function BridgeMoments.ready(slot, urgent)
    if Bridge.time < (BridgeMoments.cool[slot] or 0) then return false end
    if urgent then return true end
    if Bridge.time - BridgeMoments.lastLine < GAP then return false end

    local social = -99999
    pcall(function() social = BridgeSocial.lastRemark or -99999 end)
    return Bridge.time - social >= 3600
end


function BridgeMoments.say(event, cooldown, urgent, slot)
    slot = slot or event
    if not BridgeMoments.ready(slot, urgent) then return false end
    local text = BridgeMoments.line(event)
    if text == nil then return false end
    BridgeMoments.cool[slot] = Bridge.time + cooldown
    BridgeMoments.lastLine = Bridge.time

    local quiet = false
    pcall(function() quiet = Bridge.quiet() end)
    if quiet then
        pcall(function() Bridge.bridgeEvent(event, text) end)
        BridgeMoments.info = event .. " quiet"
        log(event .. " quiet")
        return true
    end
    Bridge.speakText(text)
    BridgeMoments.info = event
    log(event .. " " .. BridgeMoments.group())
    return true
end


function BridgeMoments.recent(ticks)
    return Bridge.time - BridgeMoments.lastLine < (ticks or MINUTE)
end



local HUNDRED = { PAIN = true, PANIC = true, UNHAPPINESS = true, WETNESS = true, FOOD_SICKNESS = true }
local function stat(red, name)
    local v = 0
    pcall(function() v = red:getStats():get(CharacterStat[name]) end)
    v = v or 0
    if HUNDRED[name] then v = v / 100 end
    return v
end

local function hasItem(body, red, types)
    local found = false
    local function look(inv)
        pcall(function()
            for _, t in ipairs(types) do
                if inv:getFirstTypeRecurse(t) ~= nil then found = true return end
            end
        end)
    end
    if body ~= nil then look(body:getInventory()) end
    if not found and red ~= nil then look(red:getInventory()) end
    return found
end

local function zombiesNear(red, dist)
    local near = false
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z ~= Bridge.body then
                local dx, dy = z:getX() - red:getX(), z:getY() - red:getY()
                if dx * dx + dy * dy < dist * dist and math.abs(z:getZ() - red:getZ()) < 1
                    and z:isAlive() and not z:getVariableBoolean(Bridge.BODY_VAR) and not BridgeData.harmless(z) then

                    local seen = true
                    pcall(function() seen = red:CanSee(z) end)
                    if seen then near = true break end
                end
            end
        end
    end)
    return near
end






local FLAGS = { "bite", "bullet", "glass", "deep", "fracture", "burn", "cut", "scratch", "bleed" }
local function flagsOf(w)
    return { bite = w.bitten, bullet = w.bullet, glass = w.glass, deep = w.deep and not w.stitched,
             fracture = w.fracture, burn = w.burn, cut = w.cut, scratch = w.scratched, bleed = w.bleeding }
end

function BridgeMoments.freshWounds(wounds)
    local first = BridgeMoments.known == nil
    local known = BridgeMoments.known or {}
    BridgeMoments.known = known
    local fresh = {}
    local present = {}
    for _, w in ipairs(wounds) do
        local key = tostring(w.key)
        present[key] = true
        local k = known[key] or {}
        known[key] = k
        local f = flagsOf(w)
        local covered = w.bandaged or w.splint
        for _, name in ipairs(FLAGS) do
            if f[name] then

                if not k[name] and not first and not k.covered then fresh[name] = true end
                k[name] = true
            elseif not covered then
                k[name] = nil
            end
        end

        if covered then k.covered = true else k.covered = nil end
    end
    for key, _ in pairs(known) do
        if not present[key] then known[key] = nil end
    end
    return fresh
end


function BridgeMoments.update(body)
    if Bridge.time - BridgeMoments.lastCheck < 30 then return end
    BridgeMoments.lastCheck = Bridge.time
    local red = BridgeData.owner()
    if red == nil then return end
    local near = false
    pcall(function()
        local dx, dy = red:getX() - body:getX(), red:getY() - body:getY()
        near = dx * dx + dy * dy < 144 and math.abs(red:getZ() - body:getZ()) < 1
    end)
    if not near then return end
    local asleep = false
    pcall(function() asleep = red:isAsleep() end)
    if asleep then return end




    local wounds = {}
    pcall(function() wounds = BridgeHeal.scan(red) end)
    local fresh = BridgeMoments.freshWounds(wounds)
    local names = {}
    for k, _ in pairs(fresh) do
        names[#names + 1] = k
        BridgeMoments.pending[k] = Bridge.time
    end
    if #names > 0 then
        table.sort(names)
        log("new wounds: " .. table.concat(names, ","))
        BridgeMoments.info = "new " .. table.concat(names, ",")
    end
    for k, at in pairs(BridgeMoments.pending) do
        if Bridge.time - at > 3 * MINUTE then BridgeMoments.pending[k] = nil end
    end
    local present = {}
    for _, w in ipairs(wounds) do
        for name, on in pairs(flagsOf(w)) do
            if on and not (w.bandaged or w.splint) then present[name] = true end
        end
    end

    local danger = zombiesNear(red, 10)
    local busy = false
    pcall(function() busy = BridgeFight.state ~= "idle" or BridgeHeal.active end)
    local fightNow = false
    pcall(function() fightNow = BridgeFight.state ~= "idle" end)


    local health = 100
    pcall(function() health = red:getBodyDamage():getOverallBodyHealth() end)
    health = tonumber(health) or 100
    while BridgeMoments.healthStep > 0 and health >= HEALTH_STEPS[BridgeMoments.healthStep] + HEALTH_BACK do
        BridgeMoments.healthStep = BridgeMoments.healthStep - 1
    end
    local step = 0
    for i, limit in ipairs(HEALTH_STEPS) do
        if health < limit then step = i end
    end
    if step > BridgeMoments.healthStep then
        BridgeMoments.healthStep = step



        local event = HEALTH_EVENTS[step]
        if not (danger or fightNow) then event = event .. "Quiet" end
        if BridgeMoments.say(event, 0, true, "Health" .. step) then return end
    end
    if danger or fightNow then


        if fresh.bite then
            if BridgeMoments.say("EvFightBite", 20 * 60, true) then return end
        end
        if fresh.deep or fresh.glass or fresh.bullet or fresh.bleed then
            BridgeMoments.say("EvFightHurt", 15 * 60, true)
        end
        return
    end

    local function has(kind)
        local yes = true
        pcall(function() yes = BridgeHeal.hasFor(body, red, kind) end)
        return yes
    end



    local autoHeal = true
    pcall(function() autoHeal = BridgeData.optionOf(Bridge.store, "autoHeal") end)
    local function wound(name, slot, cooldown, lackKind, withLack)
        local at = BridgeMoments.pending[name]
        if at == nil then return false end

        if not BridgeMoments.ready(slot, true) then BridgeMoments.pending[name] = nil return false end


        if not present[name] and Bridge.time - at > 30 * 60 then return false end
        local event = slot
        if lackKind ~= nil and not has(lackKind) then event = withLack end
        if not autoHeal then event = "EvHurtAsk" end

        if event == false then return false end
        if BridgeMoments.say(event, cooldown, true, slot) then

            BridgeMoments.pending = {}
            return true
        end
        return false
    end

    if wound("bite", "EvBite", 30 * MINUTE) then return end
    if wound("bullet", "EvBullet", 2 * MINUTE, "bullet", "EvBulletNoTools") then return end
    if wound("glass", "EvGlass", 2 * MINUTE, "glass", "EvGlassNoTweezers") then return end
    if wound("deep", "EvDeep", 2 * MINUTE, "suture", "EvDeepNoSuture") then return end
    if wound("fracture", "EvFracture", 5 * MINUTE, "splint", "EvFractureNoSplint") then return end


    if wound("burn", "EvBurn", 3 * MINUTE, "burn", false) then return end

    if wound("cut", "EvCut", 2 * MINUTE, "bandage", "EvBleedNoBandage") then return end
    if wound("scratch", "EvScratch", 3 * MINUTE) then return end
    if wound("bleed", "EvBleed", 2 * MINUTE, "bandage", "EvBleedNoBandage") then return end



    if stat(red, "PANIC") > 0.5 then
        if BridgeMoments.say("EvPanic", 5 * MINUTE, true) then return end
    end
    if busy then return end
    if stat(red, "PAIN") > 0.45 then
        local pills = hasItem(body, red, { "Base.Pills" })
        if BridgeMoments.say(pills and "EvPain" or "EvPainNoPills", 15 * MINUTE, false, "Pain") then return end
    end
    if stat(red, "SICKNESS") > 0.3 or stat(red, "FOOD_SICKNESS") > 0.3 then
        if BridgeMoments.say("EvSick", 20 * MINUTE) then return end
    end
    if stat(red, "UNHAPPINESS") > 0.4 or stat(red, "STRESS") > 0.55 then
        if BridgeMoments.say("EvSad", 25 * MINUTE) then return end
    end
    if stat(red, "THIRST") > 0.35 then
        if BridgeMoments.say("EvThirsty", 20 * MINUTE) then return end
    end
    if stat(red, "HUNGER") > 0.35 then
        if BridgeMoments.say("EvHungry", 20 * MINUTE) then return end
    end
    if stat(red, "FATIGUE") > 0.6 then
        if BridgeMoments.say("EvTired", 20 * MINUTE) then return end
    end
    if stat(red, "WETNESS") > 0.6 then
        if BridgeMoments.say("EvCold", 20 * MINUTE) then return end
    end
end

log("loaded")

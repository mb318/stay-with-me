




























BridgeMood = BridgeMood or {}


BridgeMood.TIERS = {
    Far = { bored = 0.25, unhappy = 0, stress = 0, anger = 0 },
    Near = { bored = 0.5, unhappy = 0.5, stress = 0.5, anger = 0.5 },
    Close = { bored = 1, unhappy = 1, stress = 1, anger = 1 },
}



BridgeMood.TALK = {
    Chat = { bored = { 10, 20 } },
    Joke = { bored = { 10, 20 }, unhappy = { 5, 10 } },
    Compliment = { unhappy = { 5, 10 } },
    Comfort = { unhappy = { 10, 20 }, stress = { 0.05, 0.15 } },
    Flirt = { unhappy = { 5, 15 }, bored = { 5, 10 } },
    Hug = { stress = { 0.15, 0.35 }, unhappy = { 15, 35 }, pain = { 15, 35 }, bored = { 15, 35 } },
}
BridgeMood.TALK_HOURS = 1



BridgeMood.STATS = {
    bored = { stat = "BOREDOM", mask = 2, max = 100, halo = "IGUI_HaloNote_Boredom" },
    unhappy = { stat = "UNHAPPINESS", mask = 1048576, max = 100, halo = "IGUI_HaloNote_Unhappiness" },
    stress = { stat = "STRESS", mask = 131072, max = 1, halo = "IGUI_HaloNote_Stress" },
    anger = { stat = "ANGER", mask = 1, max = 1, halo = "IGUI_HaloNote_Anger" },
    pain = { stat = "PAIN", mask = 4096, max = 100, halo = "IGUI_HaloNote_Pain" },
}
BridgeMood.ORDER = { "bored", "unhappy", "stress", "anger", "pain" }





BridgeMood.PRESENCE_MAX = { bored = 5, unhappy = 1, stress = 0.05, anger = 0.2 }

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeMood] " .. tostring(text)) end end


local FALLBACK = { BoredomDecrease = 0.0385, UnhappinessIncrease = 0.0005, StressDecrease = 0.00003,
    AngerDecrease = 0.0001 }


function BridgeMood.global(name)
    local g = ZomboidGlobals
    local v = nil
    if type(g) == "table" then v = g[name] end
    if type(v) ~= "number" then v = FALLBACK[name] end
    return v
end

local function hours()
    local h = 0
    pcall(function() h = getGameTime():getWorldAgeHours() end)
    return tonumber(h) or 0
end


function BridgeMood.tier(rel)
    if rel == nil then return nil end
    local f, r = tonumber(rel.f) or 0, tonumber(rel.r) or 0
    if f < 0 then return nil end
    if r >= 40 or f >= 75 then return "Close" end
    if f >= 20 then return "Near" end
    return "Far"
end



function BridgeMood.apply(player, deltas)
    local done, mask = {}, 0
    if player == nil or type(deltas) ~= "table" then return done, mask end
    for _, key in ipairs(BridgeMood.ORDER) do
        local s = BridgeMood.STATS[key]
        local d = tonumber(deltas[key])
        if d ~= nil and d == d and d > 0 then
            if d > s.max then d = s.max end
            local before, after = nil, nil
            pcall(function()
                local stats = player:getStats()
                local stat = CharacterStat[s.stat]
                before = stats:get(stat)
                stats:remove(stat, d)
                after = stats:get(stat)
            end)
            if type(before) == "number" and type(after) == "number" and before - after > 0 then
                done[key] = before - after
                mask = mask + s.mask
            end
        end
    end
    return done, mask
end


function BridgeMood.roll(id)
    local t = BridgeMood.TALK[id]
    if t == nil then return nil end
    local out = {}
    for key, range in pairs(t) do
        local v = range[1]
        pcall(function() v = ZombRandFloat(range[1], range[2]) end)
        if type(v) ~= "number" or v < range[1] or v > range[2] then v = range[1] end
        out[key] = v
    end
    return out
end


function BridgeMood.cleanPresence(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for key, max in pairs(BridgeMood.PRESENCE_MAX) do
        local v = tonumber(t[key])
        if v ~= nil and v == v and v > 0 then out[key] = math.min(v, max) end
    end
    return out
end


function BridgeMood.describe(t)
    local parts = {}
    for _, key in ipairs(BridgeMood.ORDER) do
        local v = t and tonumber(t[key])
        if v ~= nil and v > 0 then
            local fmt = BridgeMood.STATS[key].max > 1 and "%s=%.2f" or "%s=%.4f"
            parts[#parts + 1] = string.format(fmt, key, v)
        end
    end
    if #parts == 0 then return "nothing" end
    return table.concat(parts, " ")
end



BridgeMood.acc = { bored = 0, unhappy = 0, stress = 0, anger = 0 }
BridgeMood.state = nil
BridgeMood.checkedAt = -999999
BridgeMood.flushedAt = 0
BridgeMood.talkAt = {}
BridgeMood.hour = { from = nil, sum = {} }
BridgeMood.info = "none"

local CHECK = 30
local FLUSH = 300
local NEAR = 10
local DANGER = 10
local IDLE_SQUARE = 1800



local function companion(z)
    if Bridge.isCompanion ~= nil then return Bridge.isCompanion(z) end
    return z:getVariableBoolean(Bridge.BODY_VAR)
end

local function zombiesSeen(red, body)
    local near = false
    pcall(function()
        local list = getCell():getZombieList()
        local rx, ry, rz = red:getX(), red:getY(), red:getZ()
        for i = 0, list:size() - 1 do
            local z = list:get(i)

            if z ~= nil and z ~= body then
                local dx, dy = z:getX() - rx, z:getY() - ry
                if dx * dx + dy * dy < DANGER * DANGER and math.abs(z:getZ() - rz) < 1 and z:isAlive()
                    and not companion(z) and not BridgeData.harmless(z) and red:CanSee(z) then
                    near = true
                    break
                end
            end
        end
    end)
    return near
end


local function inCarWith(red)
    return BridgeCar ~= nil and BridgeCar.withRed ~= nil and BridgeCar.withRed(red) == true
end



function BridgeMood.blocked(red)
    if not BridgeData.optionOf(Bridge.store, "mood") then return "option off" end
    local together = inCarWith(red)
    if not together and (not Bridge.alive() or Bridge.body == nil) then return "no body" end
    if red:isDead() or Bridge.mourning ~= nil then return "player dead" end
    if red:isAsleep() then return "asleep" end
    if red:getVehicle() ~= nil and not together then return "in car" end
    return nil
end


function BridgeMood.check(red)
    local st = { tier = nil, near = false, calm = false, room = false, why = "ok" }
    local blocked = BridgeMood.blocked(red)
    if blocked ~= nil then st.why = blocked return st end
    local body = Bridge.body
    st.tier = BridgeMood.tier(BridgeData.relOf(Bridge.store))
    if st.tier == nil then st.why = "cold" return st end


    if inCarWith(red) then
        st.near = true
        pcall(function()
            local sq = red:getCurrentSquare()
            st.room = (sq ~= nil and sq:isInARoom()) or (red:getIdleSquareTime() or 0) >= IDLE_SQUARE
        end)
        st.calm = not zombiesSeen(red, nil)
        st.why = st.calm and "in car" or "in car, not calm"
        return st
    end
    pcall(function()
        local dx, dy = body:getX() - red:getX(), body:getY() - red:getY()
        if dx * dx + dy * dy > NEAR * NEAR or math.abs(body:getZ() - red:getZ()) >= 1 then return end
        local rs, bs = red:getCurrentSquare(), body:getCurrentSquare()
        local sameRoom = rs ~= nil and bs ~= nil and rs:getRoom() ~= nil and rs:getRoom() == bs:getRoom()
        st.near = sameRoom or red:CanSee(body)
    end)
    if not st.near then st.why = "not near" return st end

    pcall(function()
        local sq = red:getCurrentSquare()
        st.room = (sq ~= nil and sq:isInARoom()) or (red:getIdleSquareTime() or 0) >= IDLE_SQUARE
    end)
    local fighting = false
    pcall(function() fighting = BridgeFight.state ~= "idle" or BridgeFight.target ~= nil end)
    st.calm = not fighting and not zombiesSeen(red, body)
    if not st.calm then st.why = "not calm" end
    return st
end



local function tally(done)
    local h = BridgeMood.hour
    local now = hours()
    if h.from == nil or now < h.from then h.from, h.sum = now, {} end
    for key, v in pairs(done) do h.sum[key] = (h.sum[key] or 0) + v end
    if now - h.from >= 1 then
        log(string.format("hour %.1f%s: %s", h.from, Bridge.mp and " (sent to server)" or "", BridgeMood.describe(h.sum)))
        h.from, h.sum = now, {}
    end
end


function BridgeMood.flush(red)
    local acc = BridgeMood.acc
    local deltas = {
        bored = acc.bored * BridgeMood.global("BoredomDecrease") * 0.1,
        unhappy = acc.unhappy * BridgeMood.global("UnhappinessIncrease"),
        stress = acc.stress * BridgeMood.global("StressDecrease"),
        anger = acc.anger * BridgeMood.global("AngerDecrease"),
    }
    BridgeMood.acc = { bored = 0, unhappy = 0, stress = 0, anger = 0 }
    local any = false
    for _, v in pairs(deltas) do if v > 0 then any = true end end
    if not any then return nil end
    if Bridge.mp then
        pcall(function() sendClientCommand(red, "Bridge", "mood", { presence = deltas }) end)
        tally(deltas)
        return deltas
    end
    local done = BridgeMood.apply(red, deltas)
    tally(done)
    return done
end


function BridgeMood.frame(red)
    if red == nil then return end


    local blocked = BridgeMood.blocked(red)
    if blocked ~= nil then
        BridgeMood.acc = { bored = 0, unhappy = 0, stress = 0, anger = 0 }
        if BridgeMood.state == nil or BridgeMood.state.why ~= blocked then
            log("presence none: " .. blocked)
            BridgeMood.state = { tier = nil, near = false, calm = false, room = false, why = blocked }
            BridgeMood.info = "none " .. blocked
        end

        BridgeMood.checkedAt = -999999
        return
    end
    if Bridge.time - BridgeMood.checkedAt >= CHECK or Bridge.time < BridgeMood.checkedAt then
        BridgeMood.checkedAt = Bridge.time
        local st = BridgeMood.check(red)
        local was = BridgeMood.state
        if was == nil or was.why ~= st.why or was.tier ~= st.tier or was.room ~= st.room then
            log(string.format("presence %s: %s%s", tostring(st.tier or "none"), st.why, st.room and ", boredom counts" or ""))
        end
        BridgeMood.state = st
        BridgeMood.info = string.format("%s %s%s", tostring(st.tier or "none"), st.why, st.room and " room" or "")
    end
    local st = BridgeMood.state
    if st ~= nil and st.near and st.tier ~= nil then
        local k = BridgeMood.TIERS[st.tier]
        local mult, dmpd = 0, 0
        pcall(function()
            mult = getGameTime():getMultiplier()
            dmpd = getGameTime():getDeltaMinutesPerDay()
        end)
        if type(mult) == "number" and mult > 0 and mult == mult then
            local acc = BridgeMood.acc
            if st.room then acc.bored = acc.bored + mult * k.bored end
            if st.calm then
                acc.unhappy = acc.unhappy + mult * k.unhappy
                if type(dmpd) == "number" and dmpd > 0 then
                    acc.stress = acc.stress + mult * dmpd * k.stress
                    acc.anger = acc.anger + mult * dmpd * k.anger
                end
            end
        end
    end
    if Bridge.time - BridgeMood.flushedAt >= FLUSH or Bridge.time < BridgeMood.flushedAt then
        BridgeMood.flushedAt = Bridge.time
        BridgeMood.flush(red)
    end
end


function BridgeMood.halo(red, done)
    for _, key in ipairs(BridgeMood.ORDER) do
        if done[key] ~= nil and done[key] > 0 then
            pcall(function()
                HaloTextHelper.addTextWithArrow(red, getText(BridgeMood.STATS[key].halo), "[br/]", false,
                    HaloTextHelper.getGoodColor())
            end)
        end
    end
end


function BridgeMood.talked(id)
    local red = BridgeData.owner()
    if red == nil or BridgeMood.TALK[id] == nil then return "no effect" end
    if not BridgeData.optionOf(Bridge.store, "mood") then return "option off" end

    if BridgeMood.tier(BridgeData.relOf(Bridge.store)) == nil then return "cold" end
    local now = hours()


    local book = BridgeMood.talkAt
    if not Bridge.mp and Bridge.store ~= nil then
        if type(Bridge.store.moodTalk) ~= "table" then Bridge.store.moodTalk = {} end
        book = Bridge.store.moodTalk
    end
    local at = book[id]
    if at ~= nil and now >= at and now < at + BridgeMood.TALK_HOURS then
        log(id .. ": within the hour")
        return "within the hour"
    end
    book[id] = now
    if Bridge.mp then
        pcall(function() sendClientCommand(red, "Bridge", "mood", { talk = id }) end)
        log(id .. ": asked the server")
        return "asked"
    end
    local done = BridgeMood.apply(red, BridgeMood.roll(id))
    BridgeMood.halo(red, done)
    tally(done)
    local text = id .. ": " .. BridgeMood.describe(done)
    log(text)
    return text
end


function BridgeMood.onApplied(args)
    if type(args) ~= "table" or type(args.done) ~= "table" then return end
    local done = {}
    for _, key in ipairs(BridgeMood.ORDER) do
        local v = tonumber(args.done[key])
        if v ~= nil and v > 0 then done[key] = v end
    end
    local red = BridgeData.owner()
    if red ~= nil then BridgeMood.halo(red, done) end
    tally(done)
    log(tostring(args.talk) .. " (server): " .. BridgeMood.describe(done))
end

log("loaded")

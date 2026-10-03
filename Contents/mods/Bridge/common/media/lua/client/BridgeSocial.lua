










BridgeSocial = BridgeSocial or {}
BridgeSocial.last = {}
BridgeSocial.nagged = {}
BridgeSocial.nextRemark = nil
BridgeSocial.lastCheck = 0
BridgeSocial.sentAt = -9999
BridgeSocial.info = "none"

local CAP_F = 6
local CAP_R = 3
local REPEAT_SEC = { Chat = 30, Thanks = 45, Joke = 90, Compliment = 180, Comfort = 180, Flirt = 300, Hug = 300 }

local BUSY_DIST = 8
local AFTER_FIGHT = 1200
local DAY_HOURS = 3

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeSocial] " .. tostring(text)) end end
local function warn(text) print("[BridgeSocial] " .. tostring(text)) end

local function hours()
    local h = 0
    pcall(function() h = getGameTime():getWorldAgeHours() end)
    return h
end



local function rel()
    local r = BridgeData.relOf(Bridge.store)
    if Bridge.mp and r ~= nil then Bridge.localRel = r end
    return r
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end


BridgeSocial.poolSize = {}
local function lineCount(pool)
    local n = BridgeSocial.poolSize[pool]
    if n ~= nil then return n end
    n = 0
    for i = 1, 30 do
        local key = "IGUI_NotAlone_Soc_" .. pool .. "_" .. i
        local text = nil

        pcall(function() text = getTextOrNull(key, "", "") end)
        if text == nil or text == key or text == "" then break end
        n = i
    end
    BridgeSocial.poolSize[pool] = n
    return n
end



BridgeSocial.recent = {}
function BridgeSocial.pick(pool, n)
    local recent = BridgeSocial.recent[pool] or {}
    BridgeSocial.recent[pool] = recent
    local keep = math.min(n - 1, math.floor(n * 0.6))
    local free = {}
    for i = 1, n do
        local used = false
        for _, j in ipairs(recent) do if j == i then used = true end end
        if not used then free[#free + 1] = i end
    end
    if #free == 0 then free = { 1 + ZombRand(n) } end
    local i = free[1 + ZombRand(#free)]
    recent[#recent + 1] = i
    while #recent > keep do table.remove(recent, 1) end
    return i
end

function BridgeSocial.line(pool)
    local n = lineCount(pool)
    if n == 0 then return nil end
    local i = BridgeSocial.pick(pool, n)
    local text = nil
    pcall(function() text = getText("IGUI_NotAlone_Soc_" .. pool .. "_" .. i, BridgeData.owner():getDisplayName()) end)
    return text
end

local function say(pool)
    local text = BridgeSocial.line(pool)
    if text ~= nil then Bridge.speakText(text) end
    return text
end


local function gesture(anim)
    if anim == nil or not Bridge.drivable() then return end
    local body = Bridge.body
    if BridgeMove.onPath() or Bridge.pose ~= nil then return end

    if BridgeFastForward ~= nil and BridgeFastForward.active() then return end

    local busy = false
    pcall(function() busy = BridgeHeal.active or BridgeWash.state ~= "idle" or BridgeWeapon.isOut(body) end)

    pcall(function() if #BridgeInventory.gestures > 0 or BridgeWeapon.busy() then busy = true end end)

    pcall(function() if BridgeCar ~= nil and BridgeCar.holdsBody() then busy = true end end)
    if busy then return end
    pcall(function()
        local red = BridgeData.owner()
        body:faceLocationF(red:getX(), red:getY())
        body:setBumpType("Emote" .. anim)
    end)
end




BridgeSocial.sentSign = nil
local function sign(r)
    return string.format("%d|%d|%d|%d|%d|%d|%.1f|%.1f|%.1f", r.f, r.r, r.days, r.day, r.gainF, r.gainR,
        r.giftAt, r.askAt, r.healAt or 0)
end
function BridgeSocial.save(now)
    if not Bridge.mp then return end
    local r = rel()
    if r == nil then return end
    local sg = sign(r)
    local important = sg ~= BridgeSocial.sentSign
    if not important and (Bridge.time - BridgeSocial.sentAt) < 18000 then return end
    BridgeSocial.sentSign = sg
    BridgeSocial.sentAt = Bridge.time
    pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { rel = BridgeData.cleanRel(r) }) end)
end


local function rollDay(r)
    local day = math.floor(hours() / 24)
    if r.day == day then return end
    if r.seen > 0 and r.hours >= DAY_HOURS then
        r.days = r.days + 1
        r.f = clamp(r.f + 1, -100, 100)
    end
    r.day = day
    r.hours = 0
    r.gainF = 0
    r.gainR = 0
    r.dressF = 0
    r.dressR = 0
    BridgeSocial.save(true)
end


local function gain(r, df, dr)
    rollDay(r)
    if df > 0 then
        local room = CAP_F - r.gainF
        if room <= 0 then df = 0 elseif df > room then df = room end
        r.gainF = r.gainF + df
    end
    if dr > 0 then
        local room = CAP_R - r.gainR
        if room <= 0 then dr = 0 elseif dr > room then dr = room end
        r.gainR = r.gainR + dr
    end
    r.f = clamp(r.f + df, -100, 100)
    r.r = clamp(r.r + dr, 0, 100)

    BridgeSocial.save(true)
end


function BridgeSocial.deed(kind)
    local r = rel()
    if r == nil then return end
    if kind == "heal" then

        local now = hours()
        if now < (r.healAt or 0) then return end
        r.healAt = now + 6
        r.f = clamp(r.f + 2, -100, 100)
    elseif kind == "hit" then
        r.f = clamp(r.f - 8, -100, 100)
        r.r = clamp(r.r - 5, 0, 100)
    end
    BridgeSocial.save(true)
end



function BridgeSocial.romanceOpen(r)
    return r ~= nil and r.f >= 30 and r.days >= 2
end










BridgeSocial.DRESS = {
    jewel = { f = 3, r = 1, pool = "DressJewel" },
    cloth = { f = 1, r = 0, pool = "DressCloth" },
}
local DRESS_CAP_F = 4
local DRESS_CAP_R = 1
local JEWEL_PLACES = { "RIGHT_MIDDLE_FINGER", "LEFT_MIDDLE_FINGER", "LEFT_RING_FINGER", "RIGHT_RING_FINGER",
                       "EARS", "EAR_TOP", "NOSE", "NECKLACE", "NECKLACE_LONG", "LEFT_WRIST", "RIGHT_WRIST",
                       "BELLY_BUTTON" }




local function isJewel(item)
    local loc, cat = nil, nil
    pcall(function() loc = item:getBodyLocation() end)
    pcall(function() cat = item:getDisplayCategory() end)
    if loc == nil or ItemBodyLocation == nil or cat ~= "Accessory" then return false end
    for _, name in ipairs(JEWEL_PLACES) do
        if ItemBodyLocation[name] ~= nil and loc == ItemBodyLocation[name] then return true end
    end
    return false
end



local function presentable(item)
    local ok = true
    pcall(function() if item:isBroken() then ok = false end end)
    if ok and item.isBloody ~= nil then pcall(function() if item:isBloody() then ok = false end end) end
    if ok and item.isDirty ~= nil then pcall(function() if item:isDirty() then ok = false end end) end
    if ok and item.getHolesNumber ~= nil then pcall(function() if item:getHolesNumber() > 0 then ok = false end end) end
    return ok
end


function BridgeSocial.markGiven(item)
    pcall(function() item:getModData().bridgeGiven = true end)
end


function BridgeSocial.dressed(item)
    local r = rel()
    if r == nil or item == nil then return "no rel" end
    local given = false
    pcall(function() given = item:getModData().bridgeGiven == true end)
    if given then return "already given" end

    BridgeSocial.markGiven(item)
    if not presentable(item) then return "not presentable" end
    rollDay(r)
    local kind = isJewel(item) and BridgeSocial.DRESS.jewel or BridgeSocial.DRESS.cloth
    local df = math.max(0, math.min(kind.f, DRESS_CAP_F - (r.dressF or 0)))
    local dr = 0
    if kind.r > 0 and BridgeSocial.romanceOpen(r) then dr = math.max(0, math.min(kind.r, DRESS_CAP_R - (r.dressR or 0))) end
    if df == 0 and dr == 0 then
        log("dressed: daily cap")
        return "daily cap"
    end
    r.dressF = (r.dressF or 0) + df
    r.dressR = (r.dressR or 0) + dr
    r.f = clamp(r.f + df, -100, 100)
    r.r = clamp(r.r + dr, 0, 100)
    BridgeSocial.save(true)

    local fight = false
    pcall(function() fight = BridgeFight ~= nil and (BridgeFight.target ~= nil or BridgeFight.state == "swing") end)
    local now = 0
    pcall(function() now = getTimestampMs() end)
    if not fight and now - (BridgeSocial.dressSaidAt or -100000) > 3000 then
        BridgeSocial.dressSaidAt = now
        say(kind.pool)
    end
    BridgeSocial.info = string.format("dressed %s +%d/+%d f=%d r=%d", kind.pool, df, dr, r.f, r.r)
    log(BridgeSocial.info)
    return BridgeSocial.info
end


local function zombiesNear(dist)
    local near = false
    pcall(function()
        local red = BridgeData.owner()
        local body = Bridge.body
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z ~= body and not z:getVariableBoolean(Bridge.BODY_VAR) and z:isAlive()
                and not BridgeData.harmless(z) then
                local close = false
                for _, who in ipairs({ red, body }) do
                    if who ~= nil then
                        local dx, dy = z:getX() - who:getX(), z:getY() - who:getY()
                        if dx * dx + dy * dy < dist * dist and math.abs(z:getZ() - who:getZ()) < 1 then close = true end
                    end
                end
                if close then
                    local seen = true
                    pcall(function() seen = red:CanSee(z) end)
                    if seen then near = true break end
                end
            end
        end
    end)
    return near
end

local function recentFight()
    local last = -9999
    pcall(function() last = BridgeWeapon.lastFight end)

    return (Bridge.time - last) < AFTER_FIGHT
end



BridgeSocial.ACTIONS = {
    { id = "Chat", gate = function(r) return true end,
      chance = function(r) return 0.75 + r.f / 400 end, good = { 2, 0 }, bad = { 0, 0 }, anim = { "Yes", "Shrug" } },
    { id = "Joke", gate = function(r) return true end,
      chance = function(r) return 0.45 + r.f / 200 end, good = { 3, 0 }, bad = { -1, 0 }, anim = { "Clap", "Undecided" } },
    { id = "Compliment", gate = function(r) return r.f >= 10 end,
      chance = function(r) return 0.55 + r.f / 250 end, good = { 2, 1 }, bad = { -1, 0 }, anim = { "ThankYou", "NoThankYou" } },
    { id = "Thanks", gate = function(r) return true end,
      chance = function(r) return 0.9 end, good = { 1, 0 }, bad = { 0, 0 }, anim = { "Yes", "Shrug" } },
    { id = "Comfort", gate = function(r) return r.f >= 20 end,
      chance = function(r) return 0.5 + r.f / 200 end, good = { 3, 0 }, bad = { -1, 0 }, anim = { "Yes", "No" } },
    { id = "Flirt", gate = function(r) return BridgeSocial.romanceOpen(r) end, romantic = true,
      chance = function(r) return 0.2 + (r.f - 30) / 150 + r.r / 150 end, good = { 1, 3 }, bad = { -1, -2 }, anim = { "WaveHi", "No" } },
    { id = "Hug", gate = function(r) return r.f >= 45 and r.r >= 15 and r.days >= 4 end, romantic = true,
      chance = function(r) return 0.3 + r.r / 120 end, good = { 2, 3 }, bad = { -2, -3 }, anim = { "ComeHere", "No" } },
}

local function actionById(id)
    for _, a in ipairs(BridgeSocial.ACTIONS) do
        if a.id == id then return a end
    end
    return nil
end


function BridgeSocial.talk(id)
    local a = actionById(id)
    local r = rel()
    if a == nil or r == nil then return "unknown action" end

    local inCar = BridgeCar ~= nil and BridgeCar.withRed(BridgeData.owner())
    if not Bridge.alive() and not Bridge.drivable() and not inCar then return "no companion" end
    rollDay(r)
    if not a.gate(r) then return "locked" end
    if zombiesNear(BUSY_DIST) then
        say("Busy")
        gesture("No")
        log(id .. " refused: zombies near")
        return "busy"
    end
    if a.romantic and recentFight() then
        say("AfterFight")
        gesture("Shrug")
        log(id .. " refused: after fight")
        return "after fight"
    end



    local since = Bridge.time - (BridgeSocial.last[id] or -999999)
    if since < (REPEAT_SEC[id] or 60) * 60 then



        local fast = since < 10 * 60
        if fast and (Bridge.time - (BridgeSocial.naggedAt or -999999)) >= 10 * 3600 then
            BridgeSocial.naggedAt = Bridge.time
            say("Repeat")
            gesture("Undecided")
            log(id .. " repeat: nagged")
            return "repeat"
        end
        say(id .. "_Good")
        gesture(actionById(id).anim[1])
        log(id .. " repeat: answered without gain")
        return "repeat without gain"
    end
    BridgeSocial.last[id] = Bridge.time
    BridgeSocial.nagged[id] = nil
    local chance = clamp(a.chance(r), 0.05, 0.95)
    local roll = ZombRand(1000) / 1000
    local ok = roll < chance
    local shift = ok and a.good or a.bad
    gain(r, shift[1], shift[2])
    say(id .. (ok and "_Good" or "_Bad"))
    gesture(ok and a.anim[1] or a.anim[2])

    if ok and BridgeMood ~= nil then
        local okMood, mood = pcall(BridgeMood.talked, id)
        log(id .. " mood: " .. tostring(okMood and mood or ("error " .. tostring(mood))))
    end
    BridgeSocial.info = string.format("%s %s f=%d r=%d", id, ok and "good" or "bad", r.f, r.r)
    log(BridgeSocial.info)
    return BridgeSocial.info
end



local SNACKS = { "Base.GranolaBar", "Base.Crisps", "Base.BeefJerky", "Base.Chocolate_Candy" }


function BridgeSocial.pickGift(red)
    local thirst, hunger, nicotine, smoker = 0, 0, 0, false
    pcall(function() thirst = red:getStats():get(CharacterStat.THIRST) end)
    pcall(function() hunger = red:getStats():get(CharacterStat.HUNGER) end)
    pcall(function() nicotine = red:getStats():get(CharacterStat.NICOTINE_WITHDRAWAL) end)
    pcall(function() smoker = red:hasTrait(CharacterTrait.SMOKER) end)
    if thirst > 0.2 then return "Base.WaterBottle" end
    if smoker and nicotine > 0.2 then return "Base.CigarettePack" end
    if hunger > 0.2 then return SNACKS[1 + ZombRand(#SNACKS)] end
    local pool = { "Base.WaterBottle", "Base.LighterDisposable", "Base.Gum", SNACKS[1 + ZombRand(#SNACKS)] }
    if smoker then pool[#pool + 1] = "Base.CigarettePack" end
    return pool[1 + ZombRand(#pool)]
end

local function giftDone(item)
    local key = ({ ["Base.WaterBottle"] = "GiftWater", ["Base.CigarettePack"] = "GiftSmokes",
        ["Base.LighterDisposable"] = "GiftLighter" })[item] or "GiftFood"
    say(key)
    gesture("Yes")
    log("gift " .. tostring(item))
end



function BridgeSocial.give(item, fromAsk)
    local r = rel()
    if r == nil then return "no store" end
    local now = hours()
    if now < r.giftAt then return "gift not ready" end
    if Bridge.mp then
        if BridgeSocial.pendingGift ~= nil and Bridge.time - BridgeSocial.pendingGift.tick < 600 then return "gift pending" end
        BridgeSocial.pendingGift = { item = item, tick = Bridge.time, fromAsk = fromAsk }
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "gift", { item = item }) end)
        return "gift asked"
    end
    local ok = false
    pcall(function() ok = BridgeData.owner():getInventory():AddItem(item) ~= nil end)
    if not ok then return "gift failed" end
    r.giftAt = now + 36 + ZombRand(24)
    giftDone(item)
    return "gift " .. item
end


function BridgeSocial.onGifted(args)
    local pending = BridgeSocial.pendingGift
    BridgeSocial.pendingGift = nil
    local r = rel()
    if args and tonumber(args.giftAt) ~= nil and r ~= nil then r.giftAt = math.max(r.giftAt, tonumber(args.giftAt)) end
    if args and args.ok then
        giftDone(args.item or (pending and pending.item))
    elseif pending ~= nil and pending.fromAsk then
        say("AskNothing")
    end
    BridgeSocial.save(true)
end



function BridgeSocial.ask()
    local r = rel()
    if r == nil or r.f < 20 then return "locked" end
    if zombiesNear(BUSY_DIST) then
        say("Busy")
        return "busy"
    end
    local now = hours()
    if now < r.askAt then
        say("AskAgain")
        gesture("No")
        return "asked recently"
    end
    r.askAt = now + 6
    BridgeSocial.save(true)
    if r.f >= 35 and now >= r.giftAt then
        return BridgeSocial.give(BridgeSocial.pickGift(BridgeData.owner()), true)
    end
    say("AskNothing")
    gesture("Shrug")
    return "nothing to give"
end



local function remarkPool(r, red)
    local hurt = false
    pcall(function() hurt = red:getBodyDamage():getNumPartsBleeding() > 0 end)

    local recent = false
    pcall(function() recent = BridgeMoments.recent(4 * 3600) end)
    if hurt and not recent then return "RemarkHurt" end
    if recentFight() then return "RemarkAfterFight" end
    local hour = 12
    pcall(function() hour = getGameTime():getHour() end)
    if (hour >= 22 or hour < 5) and ZombRand(3) == 0 then return "RemarkNight" end
    if r.r >= 50 and ZombRand(2) == 0 then return "RemarkLove" end
    return "Remark" .. BridgeData.relTier(r)
end


function BridgeSocial.update(body)
    if Bridge.time - BridgeSocial.lastCheck < 60 then return end
    BridgeSocial.lastCheck = Bridge.time
    local r = rel()
    local red = BridgeData.owner()
    if r == nil or red == nil then return end
    rollDay(r)
    local together = false
    pcall(function()
        local dx, dy = red:getX() - body:getX(), red:getY() - body:getY()
        together = dx * dx + dy * dy < 100 and math.abs(red:getZ() - body:getZ()) < 1
    end)
    local now = hours()
    if together then

        if r.seen > 0 and now - r.seen > 72 then
            local lost = math.floor((now - r.seen - 72) / 24) + 1
            r.f = math.max(math.min(r.f, 0), r.f - lost)
            r.r = math.max(0, r.r - lost)
            log("apart " .. string.format("%.0f", now - r.seen) .. "h, cooled by " .. lost)
        end


        local step = now - r.seen
        if r.seen > 0 and step > 0 and step <= 0.25 then r.hours = math.min(24, r.hours + step) end
        if now > r.seen then r.seen = now end
    end
    BridgeSocial.save()
    if not together or Bridge.mode == "rest" then return end
    local asleep = false
    pcall(function() asleep = red:isAsleep() end)
    if asleep then return end

    local calm = BridgeFight.state == "idle" and BridgeFight.target == nil and BridgeWash.state == "idle"
        and not BridgeHeal.active and not zombiesNear(12)


    if BridgeSocial.nextRemark == nil then BridgeSocial.nextRemark = Bridge.time + 7200 + ZombRand(7200) end
    local justSpoke = false
    pcall(function() justSpoke = BridgeMoments.recent(3600) end)
    local quiet = false
    pcall(function() quiet = Bridge.quiet() end)
    if calm and not justSpoke and Bridge.time >= BridgeSocial.nextRemark then
        BridgeSocial.nextRemark = Bridge.time + 5400 + ZombRand(9000)

        if not quiet then
            local pool = remarkPool(r, red)
            if say(pool) == nil then say("Remark" .. BridgeData.relTier(r)) end
            BridgeSocial.lastRemark = Bridge.time
        end
    end



    if calm and not quiet and r.f >= 35 and now >= r.giftAt and BridgeData.optionOf(Bridge.store, "gifts")
        and ZombRand(900) == 0 then
        BridgeSocial.give(BridgeSocial.pickGift(red), false)
    end
end


function BridgeSocial.label()
    local r = rel()
    if r == nil then return "" end
    local text = ""
    pcall(function()
        text = getText("IGUI_NotAlone_Rel_" .. BridgeData.relTier(r))
        if r.r >= 50 then text = getText("IGUI_NotAlone_Rel_Love")
        elseif r.r >= 25 then text = text .. ", " .. getText("IGUI_NotAlone_Rel_Crush") end
    end)
    return text
end


function BridgeSocial.fillMenu(context, tr)
    local r = rel()
    if r == nil then return end
    rollDay(r)
    local option = context:addOption(tr("Talk"))
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(option, sub)
    local romantic = nil
    for _, a in ipairs(BridgeSocial.ACTIONS) do
        if a.gate(r) then
            local target = sub
            if a.romantic then
                if romantic == nil then
                    local ro = sub:addOption(tr("Romance"))
                    romantic = ISContextMenu:getNew(sub)
                    sub:addSubMenu(ro, romantic)
                end
                target = romantic
            end
            target:addOption(tr("Talk_" .. a.id), a.id, BridgeSocial.talk)
        end
    end
    if r.f >= 20 then sub:addOption(tr("Talk_Ask"), nil, BridgeSocial.ask) end
end

log("loaded")

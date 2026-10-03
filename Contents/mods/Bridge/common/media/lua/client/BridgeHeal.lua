







BridgeHeal = BridgeHeal or {}

local REACH = 1.3
local STEP_FRAMES = 120
local GAP_FRAMES = 15
local GIVEUP_DIST = 4.0
local REQUEST_REACH = 45
local IMMINENT = 3.0
local THREAT_SEEN = 8
local THREAT_TOUCH = 1.6
local THREAT_FAR = 10
local QUIET_URGENT = 60
local QUIET = 300
local CHECK_EVERY = 15
local RETRY_EMPTY = 1800
local SENT_HOLD = 180

BridgeHeal.queue = {}
BridgeHeal.current = nil
BridgeHeal.state = "idle"
BridgeHeal.info = "none"
BridgeHeal.quietSince = nil
BridgeHeal.lastAuto = -99999
BridgeHeal.emptySig = nil
BridgeHeal.emptyUntil = 0
BridgeHeal.byRequest = false
BridgeHeal.sent = {}
BridgeHeal.active = false
BridgeHeal.nextAt = 0
BridgeHeal.missing = {}
BridgeHeal.done = 0
BridgeHeal.pass = 0

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeHeal] " .. tostring(text)) end end
local function warn(text) print("[BridgeHeal] " .. tostring(text)) end

local function dist(a, b)
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    return math.sqrt(dx * dx + dy * dy)
end




local PART_ANIM = {
    Head = "TreatHigh", Neck = "TreatHigh", Torso_Upper = "TreatMid",
    Torso_Lower = "TreatMid", Groin = "TreatMid",
    UpperArm_L = "TreatMid", ForeArm_L = "TreatMid", Hand_L = "TreatMid",
    UpperArm_R = "TreatMid", ForeArm_R = "TreatMid", Hand_R = "TreatMid",
    UpperLeg_L = "TreatLow", LowerLeg_L = "TreatLow", Foot_L = "TreatLow",
    UpperLeg_R = "TreatLow", LowerLeg_R = "TreatLow", Foot_R = "TreatLow",
}


local function partName(part)
    local key, name = "?", nil
    pcall(function() key = tostring(BodyPartType.ToString(part:getType())) end)
    pcall(function() name = BodyPartType.getDisplayName(part:getType()) end)
    return key, name or key
end


local function tr(key, a, b)
    local text = key
    pcall(function()
        if b ~= nil then text = getText("IGUI_NotAlone_" .. key, a, b)
        elseif a ~= nil then text = getText("IGUI_NotAlone_" .. key, a)
        else text = getText("IGUI_NotAlone_" .. key) end
    end)
    return text
end


function BridgeHeal.scan(red)
    local out = {}
    pcall(function()
        local parts = red:getBodyDamage():getBodyParts()
        for i = 0, parts:size() - 1 do
            local p = parts:get(i)
            local key, name = partName(p)
            local w = { part = p, key = key, name = name }
            local function flag(f, fn) pcall(function() w[f] = fn() end) end
            flag("injury", function() return p:HasInjury() end)
            flag("bleeding", function() return p:bleeding() end)
            flag("scratched", function() return p:scratched() end)
            flag("cut", function() return p:isCut() end)
            flag("deep", function() return p:isDeepWounded() end)
            flag("bitten", function() return p:bitten() end)
            flag("glass", function() return p:haveGlass() end)
            flag("bullet", function() return p:haveBullet() end)
            flag("fracture", function() return p:getFractureTime() > 0 and p:getSplintFactor() == 0 end)
            flag("splint", function() return p:getSplintFactor() > 0 end)
            flag("infected", function() return p:isInfectedWound() end)
            flag("burn", function() return p:getBurnTime() > 0 end)
            flag("burnWash", function() return p:isNeedBurnWash() end)
            flag("bandaged", function() return p:bandaged() end)
            flag("dirty", function() return p:isBandageDirty() end)
            flag("stitched", function() return p:stitched() end)
            flag("alcohol", function() return p:getAlcoholLevel() > 0 end)
            local any = w.injury or w.bandaged or w.stitched or w.splint or w.fracture
            if any then out[#out + 1] = w end
        end
    end)
    return out
end


function BridgeHeal.describe(wounds)
    if #wounds == 0 then return "clean" end
    local parts = {}
    for _, w in ipairs(wounds) do
        local f = {}
        if w.bitten then f[#f + 1] = "bite" end
        if w.deep then f[#f + 1] = "deep" end
        if w.cut then f[#f + 1] = "cut" end
        if w.scratched then f[#f + 1] = "scratch" end
        if w.bleeding then f[#f + 1] = "bleeding" end
        if w.glass then f[#f + 1] = "glass" end
        if w.bullet then f[#f + 1] = "bullet" end
        if w.fracture then f[#f + 1] = "fracture" end
        if w.burn then f[#f + 1] = "burn" end
        if w.infected then f[#f + 1] = "infected" end

        if w.alcohol then f[#f + 1] = "alcohol" end
        if w.stitched then f[#f + 1] = "stitched" end
        if w.splint then f[#f + 1] = "splint" end
        if w.bandaged then f[#f + 1] = w.dirty and "dirty-bandage" or "bandaged" end
        parts[#parts + 1] = w.key .. ":" .. table.concat(f, "+")
    end
    return table.concat(parts, " ")
end





local function eachItem(body, red, fn)
    local function walk(inv, depth)
        if inv == nil or depth > 2 then return end
        local items = inv:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it ~= nil then
                if fn(it) then return true end
                local isBag = false
                pcall(function() isBag = it:IsInventoryContainer() end)
                if isBag then
                    local sub = nil
                    pcall(function() sub = it:getInventory() end)
                    if walk(sub, depth + 1) then return true end
                end
            end
        end
        return false
    end
    if walk(body:getInventory(), 0) then return end


    local useRed = BridgeData.optionOf(Bridge.store, "redKit")
    if BridgeHeal.active and BridgeHeal.kitLock ~= nil then useRed = BridgeHeal.kitLock end
    if red ~= nil and useRed then walk(red:getInventory(), 0) end
end



local function reserve(used, it, uses)
    if used == nil then return true end
    local left = used[it]
    if left == nil then
        left = 1
        if BridgeCare.fluidAlcohol(it) ~= nil then
            left = BridgeCare.fluidUses(it)
        else
            pcall(function() if it:IsDrainable() then left = it:getCurrentUses() end end)
        end
    end
    if left <= 0 then return false end
    used[it] = left - 1
    return true
end

local function findItem(body, red, used, test)
    local found = nil
    eachItem(body, red, function(it)
        local ok, yes = pcall(test, it)
        if ok and yes and (used == nil or (used[it] == nil or used[it] > 0)) then found = it return true end
        return false
    end)
    if found ~= nil and used ~= nil then reserve(used, found) end
    return found
end


local function hasTag(it, tag)
    local yes = false
    pcall(function() yes = ItemTag ~= nil and ItemTag[tag] ~= nil and it:hasTag(ItemTag[tag]) end)
    return yes == true
end


local function bestBandage(body, red, used, minPower)
    local best, power = nil, (minPower or 0.0001) - 0.0001
    eachItem(body, red, function(it)
        local ok, p = pcall(function() return it:getBandagePower() end)
        if ok and p ~= nil and p > power and not string.find(tostring(it:getType()), "Dirty", 1, true)
            and (used == nil or used[it] == nil or used[it] > 0) then
            best, power = it, p
        end
        return false
    end)
    if best ~= nil and used ~= nil then reserve(used, best) end
    return best
end

local function burnBandage(body, red, used) return bestBandage(body, red, used, 2) end




local function dirtyBandage(body, red, used)
    local best, power = nil, -1
    eachItem(body, red, function(it)
        local ok, p = pcall(function() return it:getBandagePower() end)
        if ok and p ~= nil and p > power and string.find(tostring(it:getType()), "Dirty", 1, true)
            and (used == nil or used[it] == nil or used[it] > 0) then
            best, power = it, p
        end
        return false
    end)
    if best ~= nil and used ~= nil then reserve(used, best) end
    return best
end



local function findDisinfectant(body, red, used)
    return findItem(body, red, used, function(it)
        local fluid = BridgeCare.fluidAlcohol(it)
        if fluid ~= nil then return fluid > 0 end
        return it:IsDrainable() and it:getAlcoholPower() == 4.0 and it:getCurrentUses() > 0
    end)
end



local function findGlassTool(body, red)
    return findItem(body, red, nil, function(it)
        local t = it:getType()
        return t == "Tweezers" or t == "SutureNeedleHolder" or hasTag(it, "REMOVE_GLASS")
    end)
end

local function findBulletTool(body, red)
    return findItem(body, red, nil, function(it)
        local t = it:getType()
        return t == "Tweezers" or t == "SutureNeedleHolder" or hasTag(it, "REMOVE_BULLET")
    end)
end


local function findSuture(body, red, used)
    local suture = findItem(body, red, used, function(it) return it:getType() == "SutureNeedle" end)
    if suture ~= nil then return suture, nil end
    local needle = findItem(body, red, nil, function(it) return it:getType() == "Needle" or hasTag(it, "SEWING_NEEDLE") end)
    local thread = findItem(body, red, used, function(it)
        return (it:getType() == "Thread" or hasTag(it, "THREAD")) and it:getCurrentUsesFloat() > 0
    end)
    if needle ~= nil and thread ~= nil then return needle, thread end
    return nil, nil
end

local function findSplint(body, red, used)
    local splint = findItem(body, red, used, function(it) return it:getType() == "Splint" end)
    if splint ~= nil then return splint, nil end
    local plank = findItem(body, red, used, function(it)
        local t = it:getType()
        return t == "Plank" or t == "TreeBranch" or t == "TreeBranch2" or t == "WoodenStick" or t == "WoodenStick2"
    end)
    local sheet = findItem(body, red, used, function(it) return it:getType() == "RippedSheets" end)
    if plank ~= nil and sheet ~= nil then return plank, sheet end
    return nil, nil
end



function BridgeHeal.hasFor(body, red, kind)
    if kind == "bandage" then return bestBandage(body, red, nil) ~= nil end
    if kind == "suture" then return (findSuture(body, red, nil)) ~= nil end
    if kind == "glass" then return findGlassTool(body, red) ~= nil end
    if kind == "bullet" then return findBulletTool(body, red) ~= nil end
    if kind == "splint" then return (findSplint(body, red, nil)) ~= nil end
    if kind == "disinfect" then return findDisinfectant(body, red, nil) ~= nil end
    return false
end


local FINDERS = {
    glass = findGlassTool, bullet = findBulletTool, burn = burnBandage, stitch = findSuture,
    disinfect = findDisinfectant, splint = findSplint, bandage = bestBandage,
}





function BridgeHeal.plan(body, red)
    local wounds = BridgeHeal.scan(red)
    local rawQueue, missing, used = {}, {}, {}
    local queue = rawQueue
    local lacking = {}
    local function need(what, w)
        missing[#missing + 1] = tr("Need_" .. what, w.name)
        lacking[what] = true
    end
    for _, w in ipairs(wounds) do




        local needsCare = w.injury or w.stitched or w.infected
        local open = needsCare and not w.bandaged
        local wantBandage = open




        local spare = nil
        if w.bandaged and w.dirty then
            spare = bestBandage(body, red, used)
            if spare ~= nil then
                queue[#queue + 1] = { kind = "unbandage", w = w }
                open = w.injury
                wantBandage = true
            else
                need("Bandage", w)
            end
        end






        local reuse = false
        if w.bandaged and not w.dirty and w.deep and not w.stitched and not w.glass then
            local a, b = findSuture(body, red, used)
            if a ~= nil then
                spare = bestBandage(body, red, used)
                if spare == nil then reuse = true end
                queue[#queue + 1] = { kind = "unbandage", w = w }
                queue[#queue + 1] = { kind = "stitch", w = w, item = a, item2 = b }
                open = true
                wantBandage = true
            else

                need("Suture", w)
            end
        end








        if w.bandaged and not w.dirty and w.infected and not w.alcohol and open ~= true then
            local d = findDisinfectant(body, red, nil)
            if d == nil then
                need("Disinfectant", w)
            else
                spare = bestBandage(body, red, used)
                if spare == nil then reuse = true end
                queue[#queue + 1] = { kind = "unbandage", w = w }
                open = true
                wantBandage = true
            end
        end
        if open and w.glass then
            queue[#queue + 1] = { kind = "glass", w = w, item = findGlassTool(body, red) }


            if w.deep and not w.stitched then
                local a = findSuture(body, red, nil)
                if a ~= nil then wantBandage = false end
            end
        end



        local bulletOut = false
        if open and w.bullet then
            local tw = findBulletTool(body, red)
            if tw ~= nil then
                queue[#queue + 1] = { kind = "bullet", w = w, item = tw }
                bulletOut = true
            else need("Tweezers", w) end
        end
        local deep = w.deep or bulletOut
        if open and w.burn and w.burnWash then
            local b = burnBandage(body, red, used)
            if b ~= nil then queue[#queue + 1] = { kind = "burn", w = w, item = b }
            else need("BurnBandage", w) end
        end
        if open and deep and not w.stitched and not w.glass and not w.bandaged then
            local a, b = findSuture(body, red, used)
            if a ~= nil then queue[#queue + 1] = { kind = "stitch", w = w, item = a, item2 = b }
            else need("Suture", w) end
        end
        if open and (w.scratched or w.cut or deep or w.bitten or w.infected or w.stitched) and not w.alcohol then
            local d = findDisinfectant(body, red, used)
            if d ~= nil then queue[#queue + 1] = { kind = "disinfect", w = w, item = d }
            else need("Disinfectant", w) end
        end
        if w.fracture and not w.splint and w.key ~= "Head" and w.key ~= "Torso_Upper" and w.key ~= "Torso_Lower" then
            local a, b = findSplint(body, red, used)
            if a ~= nil then queue[#queue + 1] = { kind = "splint", w = w, item = a, item2 = b }
            else need("Splint", w) end
        end
        if wantBandage then
            local b = spare or bestBandage(body, red, used)
            if b == nil and reuse then

                queue[#queue + 1] = { kind = "bandage", w = w, reuse = true }
            elseif b ~= nil then
                queue[#queue + 1] = { kind = "bandage", w = w, item = b }
            elseif w.bleeding and not w.bandaged then
                local d = dirtyBandage(body, red, used)
                if d ~= nil then queue[#queue + 1] = { kind = "bandage", w = w, item = d, dirty = true }
                else need("Bandage", w) end
            else
                need("Bandage", w)
            end
        end
    end


    queue = {}
    for _, st in ipairs(rawQueue) do
        local at = BridgeHeal.sent[tostring(st.w.key) .. ":" .. st.kind]
        if at == nil or Bridge.time - at > SENT_HOLD then queue[#queue + 1] = st end
    end
    return queue, missing, wounds, lacking
end



local function doctorLevel(body) return 2 end



local SOUND = {
    bandage = "FirstAidApplyBandage", unbandage = "FirstAidApplyBandage", disinfect = "FirstAidApplyAlcohol",
    stitch = "FirstAidApplyStitch", glass = "FirstAidRemoveFromWound", bullet = "FirstAidRemoveFromWound",
    burn = "FirstAidCleanBurn", splint = "FirstAidApplySplint",
}

local function stopSounds(body, red, step)
    if step == nil then return end
    if step.soundId ~= nil and body ~= nil then
        pcall(function() body:getEmitter():stopOrTriggerSound(step.soundId) end)
    end
    if step.voiceId ~= nil and red ~= nil then
        pcall(function() red:stopOrTriggerSound(step.voiceId) end)
    end
    step.soundId, step.voiceId = nil, nil
end

local function startSounds(body, red, step)
    local name = SOUND[step.kind]
    pcall(function()
        if step.kind == "disinfect" and step.item ~= nil and step.item:getFullType() == "Base.AlcoholWipes" then
            name = "FirstAidApplyAlcoholWipes"
        end
    end)
    if name ~= nil then
        pcall(function() step.soundId = BridgeSound.sfx(body, name) end)
    end
    if step.kind == "bandage" or (step.kind == "unbandage" and step.w.injury) then
        pcall(function() step.voiceId = red:playerVoiceSound("ApplyBandage") end)
    end
end


local function spent(step)
    local k = step.kind
    if k == "burn" or k == "disinfect" or k == "bandage" then return { step.item } end
    if k == "stitch" then return { step.item2 or step.item } end
    if k == "splint" then return { step.item, step.item2 } end
    return {}
end






local function apply(body, red, step)
    local p = step.w.part
    local lvl = doctorLevel(body)
    local finder = FINDERS[step.kind]
    if step.kind == "bandage" and step.dirty then finder = dirtyBandage end
    if finder ~= nil then
        local a, b = finder(body, red, nil)

        if a == nil and step.kind ~= "glass" then return "item gone for " .. step.kind end
        step.item, step.item2 = a, b
    end
    local change = { kind = step.kind, part = p:getIndex() }

    if step.kind == "unbandage" then
        local bag = nil
        pcall(function() bag = body:getInventory() end)
        BridgeCare.returnBandage(bag, p)
    end
    if step.kind == "bullet" then
        change.level = lvl
    elseif step.kind == "stitch" then
        change.stitchTime = ((1 + lvl) / 2) * ZombRandFloat(2.0, 5.0)
    elseif step.kind == "disinfect" then
        change.alcohol = BridgeCare.fluidAlcohol(step.item)
        if change.alcohol == nil then change.alcohol = step.item:getAlcoholPower() end
    elseif step.kind == "splint" then
        change.factor = (lvl + 1) / 2
        pcall(function() change.splintItem = step.item:getModule() .. "." .. step.item:getType() end)
    elseif step.kind == "bandage" then
        change.life = ZombRandFloat((lvl + 1) * 0.5, (lvl + 1) * 1.0) + step.item:getBandagePower()

        if string.find(tostring(step.item:getType()), "Dirty", 1, true) then change.life = 0 end
        pcall(function() change.alcoholic = step.item:isAlcoholic() == true end)
        pcall(function() change.infected = step.item:isInfected() == true end)
        change.bandageType = step.item:getModule() .. "." .. step.item:getType()
    end
    if isClient() then
        local redItems = {}
        for _, it in ipairs(spent(step)) do
            local mine = false
            pcall(function() mine = red:getInventory():containsRecursive(it) end)
            if mine then redItems[#redItems + 1] = it:getID() else BridgeCare.consume(it, false) end
        end
        sendClientCommand(red, "Bridge", "care", { change = change, items = redItems })
        BridgeHeal.sent[tostring(step.w.key) .. ":" .. step.kind] = Bridge.time
        return nil
    end
    local part, why = BridgeCare.apply(red, change)
    if part == nil then return why end
    for _, it in ipairs(spent(step)) do BridgeCare.consume(it, false) end
    return nil
end


local function say(key, a, b)
    if Bridge ~= nil and Bridge.speakText ~= nil then

        local text = nil
        pcall(function() text = BridgeMoments.line(string.gsub(key, "_", ""), a, b) end)
        text = text or tr("Say_" .. key, a, b)



        local quiet = false
        pcall(function() quiet = Bridge.quiet() end)
        if quiet then
            pcall(function() Bridge.bridgeEvent(key, text) end)
            return
        end
        pcall(function() Bridge.speakText(text) end)
    end
end



function BridgeHeal.needs(wounds)
    local urgent, any = false, false
    for _, w in ipairs(wounds) do
        local open = (w.injury or w.stitched or w.infected) and not w.bandaged


        if open and (w.bleeding or w.bitten or w.deep or w.glass or w.bullet or w.burn) then urgent = true end

        local festering = w.bandaged and not w.dirty and w.infected and not w.alcohol
        if open or (w.bandaged and w.dirty) or w.fracture or festering then any = true end
    end
    return urgent, any
end


function BridgeHeal.start(body, red, byRequest)
    local queue, missing, wounds = BridgeHeal.plan(body, red)
    BridgeHeal.missing = missing
    BridgeHeal.lastAuto = Bridge.time
    if #wounds == 0 then
        if byRequest then say("Heal_NoWounds") end
        BridgeHeal.info = "clean"
        return "clean"
    end
    if #queue == 0 then

        if byRequest then
            if #missing == 0 then say("Heal_NoWounds") else say("Heal_Nothing", table.concat(missing, ", ")) end
        end
        BridgeHeal.info = "nothing to do: " .. table.concat(missing, ", ")
        return BridgeHeal.info
    end
    BridgeHeal.queue = queue
    BridgeHeal.current = nil
    BridgeHeal.state = "walk"
    BridgeHeal.active = true
    BridgeHeal.kitLock = BridgeData.optionOf(Bridge.store, "redKit")
    BridgeHeal.byRequest = byRequest == true
    BridgeHeal.walkSince = Bridge.time
    BridgeHeal.done = 0
    BridgeHeal.pass = 0
    BridgeHeal.info = "started " .. tostring(#queue) .. (byRequest and " by request" or " by herself")
    log(BridgeHeal.info .. ": " .. BridgeHeal.describe(wounds))
    local bites = {}
    for _, w in ipairs(wounds) do if w.bitten then bites[#bites + 1] = w.name end end
    if #bites > 0 then
        say("Heal_Bite", table.concat(bites, ", "))
    end
    return BridgeHeal.info
end


function BridgeHeal.request()
    local red = BridgeData.owner()
    if red == nil or Bridge == nil or not Bridge.alive() then return "no body" end
    if BridgeHeal.active then return "already" end
    local res = BridgeHeal.start(Bridge.body, red, true)


    if BridgeHeal.active and Bridge.mode ~= nil and Bridge.mode ~= "follow" and Bridge.setMode ~= nil then
        pcall(function() Bridge.setMode("follow") end)
        res = res .. ", follow"
    end
    return res
end

function BridgeHeal.stop(reason)
    pcall(function() stopSounds(Bridge.body, BridgeData.owner(), BridgeHeal.current) end)
    BridgeHeal.queue = {}
    BridgeHeal.current = nil
    BridgeHeal.state = "idle"
    BridgeHeal.active = false
    BridgeHeal.kitLock = nil
    BridgeHeal.byRequest = false
    BridgeHeal.info = "stopped: " .. tostring(reason)
    if reason ~= "done" then log(BridgeHeal.info) end
end

local function finish(body, red)

    if BridgeHeal.pass < 2 then
        BridgeHeal.pass = BridgeHeal.pass + 1
        local queue, missing = BridgeHeal.plan(body, red)
        if #queue > 0 then
            BridgeHeal.queue = queue
            BridgeHeal.missing = missing
            BridgeHeal.info = "pass " .. tostring(BridgeHeal.pass + 1) .. " " .. tostring(#queue)
            return
        end
    end
    if #BridgeHeal.missing > 0 then
        say("Heal_DoneMissing", tostring(BridgeHeal.done), table.concat(BridgeHeal.missing, ", "))
    else
        say("Heal_Done", tostring(BridgeHeal.done))
        pcall(function() BridgeSocial.deed("heal") end)
    end
    BridgeHeal.stop("done")
    BridgeHeal.info = "done " .. tostring(BridgeHeal.done)
    log(BridgeHeal.info)

    pcall(function() if Bridge.saveOutfit ~= nil then Bridge.saveOutfit() end end)
end





function BridgeHeal.isThreat(z, body, red)
    if z == nil or z == body then return false end
    local alive = false
    pcall(function() alive = z:isAlive() end)
    if not alive then return false end
    local companion = false
    pcall(function() companion = Bridge.BODY_VAR ~= nil and z:getVariableBoolean(Bridge.BODY_VAR) end)
    if companion then return false end
    if math.abs(z:getZ() - red:getZ()) >= 0.8 then return false end

    if BridgeData.harmless(z) then return false end
    local d = dist(z, red)
    if body ~= nil then d = math.min(d, dist(z, body)) end
    if d > THREAT_FAR then return false end
    if d < THREAT_TOUCH then return true end
    local target = nil
    pcall(function() target = z:getTarget() end)
    if target ~= nil and (target == red or (body ~= nil and target == body)) then return true end
    local seen = false
    pcall(function() seen = red:CanSee(z) end)
    return seen and d < THREAT_SEEN
end






function BridgeHeal.isImminent(z, body, red, running)
    if not BridgeHeal.isThreat(z, body, red) then return false end
    local d = dist(z, red)
    if body ~= nil and not running then d = math.min(d, dist(z, body)) end
    if d < THREAT_TOUCH then return true end
    local target = nil
    pcall(function() target = z:getTarget() end)
    return d < IMMINENT and target ~= nil and (target == red or (body ~= nil and target == body))
end

function BridgeHeal.threatNear(body, red, imminentOnly, running)
    local found = false
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            local hit = false
            if imminentOnly then hit = BridgeHeal.isImminent(z, body, red, running) else hit = BridgeHeal.isThreat(z, body, red) end
            if hit then found = true return end
        end
    end)
    return found
end




BridgeHeal.redPrev = nil

local AFTER_FIRE = 600

local function calmNow(body, red)
    local justBurned = BridgeHeal.firedAt ~= nil and (Bridge.time - BridgeHeal.firedAt) < AFTER_FIRE
    local moved = false
    pcall(function()
        local px, py = red:getX(), red:getY()
        if BridgeHeal.redPrev ~= nil then
            local dx, dy = px - BridgeHeal.redPrev.x, py - BridgeHeal.redPrev.y
            moved = (dx * dx + dy * dy) > 0.15 * 0.15
        end
        BridgeHeal.redPrev = { x = px, y = py }
    end)
    if moved and not justBurned then return false, "player moving" end
    if BridgeFight ~= nil and BridgeFight.target ~= nil then return false, "fight" end
    if BridgeHeal.threatNear(body, red) then return false, "zombie" end
    return true, nil
end


function BridgeHeal.autoCheck(body, red)

    if not BridgeData.optionOf(Bridge.store, "autoHeal") then
        BridgeHeal.quietSince = nil
        BridgeHeal.waitWhy = "auto heal off"
        return
    end
    local calm, why = calmNow(body, red)
    if not calm then
        BridgeHeal.quietSince = nil
        BridgeHeal.waitWhy = why
        return
    end
    if BridgeHeal.quietSince == nil then BridgeHeal.quietSince = Bridge.time end
    if dist(body, red) > GIVEUP_DIST then BridgeHeal.waitWhy = "far" return end
    local wounds = BridgeHeal.scan(red)
    local urgent, any = BridgeHeal.needs(wounds)
    if not any then BridgeHeal.waitWhy = nil return end


    local seated = false
    pcall(function() seated = BridgeMove.seatZones(red) ~= nil end)
    if seated and not urgent then BridgeHeal.waitWhy = "player sitting" return end
    if Bridge.time - BridgeHeal.quietSince < (urgent and QUIET_URGENT or QUIET) then
        BridgeHeal.waitWhy = "quiet"
        return
    end
    local sig = BridgeHeal.describe(wounds)
    if sig == BridgeHeal.emptySig and Bridge.time < BridgeHeal.emptyUntil then
        BridgeHeal.waitWhy = "nothing to treat with"
        return
    end
    BridgeHeal.start(body, red, false)
    if BridgeHeal.active then
        BridgeHeal.emptySig = nil
        BridgeHeal.waitWhy = nil
    else
        BridgeHeal.emptySig = sig
        BridgeHeal.emptyUntil = Bridge.time + RETRY_EMPTY
    end
end





local FIRE_REACH = 1.8
local DOUSE_FRAMES = 150

local NOTICE_FRAMES = 60
local FIRE_SEARCH = 2

BridgeHeal.fireState = "none"
BridgeHeal.fireSince = nil
BridgeHeal.fireSaid = 0


local function waterUses(item)
    local n = 0
    pcall(function()
        if item:hasComponent(ComponentType.FluidContainer) then
            local fc = item:getFluidContainer()
            local fluid = fc:getPrimaryFluid()
            if fluid == nil then return end
            local name = fluid:getFluidTypeString()
            if name ~= "Water" and name ~= "TaintedWater" then return end
            local per = 250
            pcall(function()
                local v = ZomboidGlobals.fireFightingFluidContainerMillilitresPerUse
                if type(v) == "number" and v > 0 then per = v end
            end)
            n = math.floor(fc:getAmount() * 1000 / per)
        elseif item:IsDrainable() and item:isWaterSource() then
            n = item:getCurrentUses()
        end
    end)
    return n
end



local function extinguisherUses(item)
    local t = "?"
    pcall(function() t = item:getType() end)
    if t == "Extinguisher" or t == "Sandbag" or t == "Gravelbag" or t == "Dirtbag" then return 1 end
    return 10
end

local function isExtinguisher(item)
    if item == nil then return false end
    local t = "?"
    pcall(function() t = item:getType() end)
    if t == "Extinguisher" or t == "Sandbag" or t == "Gravelbag" or t == "Dirtbag" then
        local uses = 0
        pcall(function() uses = item:getCurrentUses() end)
        return uses >= 1
    end
    local water = false
    pcall(function() water = item:isWaterSource() end)
    return water and waterUses(item) >= 10
end



function BridgeHeal.fireTool(body, red)
    local found = nil
    local function scan(container)
        if found ~= nil or container == nil then return end
        pcall(function()
            local items = container:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if isExtinguisher(it) then found = it return end
            end
        end)
    end
    pcall(function() scan(body:getInventory()) end)
    if found == nil then pcall(function() scan(red:getInventory()) end) end
    if found ~= nil then return found end

    pcall(function()
        local bx, by, bz = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())
        for dx = -FIRE_SEARCH, FIRE_SEARCH do
            for dy = -FIRE_SEARCH, FIRE_SEARCH do
                local sq = getCell():getGridSquare(bx + dx, by + dy, bz)
                if sq ~= nil then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        pcall(function()
                            if instanceof(obj, "IsoWorldInventoryObject") then
                                local it = obj:getItem()
                                if isExtinguisher(it) then found = it end
                            else
                                local c = obj:getContainer()
                                if c ~= nil then scan(c) end
                            end
                        end)
                        if found ~= nil then return end
                    end
                end
            end
        end
    end)
    return found
end


local function useFireTool(item)
    local per = 250
    pcall(function()
        local v = ZomboidGlobals.fireFightingFluidContainerMillilitresPerUse
        if type(v) == "number" and v > 0 then per = v end
    end)
    local n = extinguisherUses(item)
    for _ = 1, n do
        local stop = false
        pcall(function()
            if instanceof(item, "DrainableComboItem") then
                item:Use()
            elseif item:hasComponent(ComponentType.FluidContainer) then
                local fc = item:getFluidContainer()
                local left = fc:getAmount() - per / 1000
                if left < 0 then left = 0 end
                fc:adjustAmount(left)
            else
                stop = true
            end
        end)
        if stop then break end
    end
end



local function douseGround(body, red, burning, meBurning)
    local n = 0
    local function ring(who)
        if who == nil then return end
        pcall(function()
            local cx, cy, cz = math.floor(who:getX()), math.floor(who:getY()), math.floor(who:getZ())
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local sq = getCell():getGridSquare(cx + dx, cy + dy, cz)
                    if sq ~= nil and sq:has(IsoFlagType.burning) then
                        pcall(function() sq:stopFire() end)
                        n = n + 1
                    end
                end
            end
        end)
    end
    if burning then ring(red) end
    if meBurning or burning then ring(body) end
    return n
end


function BridgeHeal.fireUpdate(body, red)
    local burning, meBurning = false, false
    pcall(function() burning = red:isOnFire() end)
    pcall(function() meBurning = body:isOnFire() end)
    if not burning and not meBurning then
        if BridgeHeal.fireState ~= "none" then
            BridgeHeal.fireState = "none"
            BridgeHeal.fireSince = nil
            BridgeHeal.douseSince = nil
        end
        return false
    end

    if BridgeHeal.fireSince == nil then
        BridgeHeal.fireSince = Bridge.time
        BridgeHeal.fireSaid = 0
    end

    if Bridge.time - BridgeHeal.fireSince < NOTICE_FRAMES then
        BridgeHeal.fireState = "notice"
        BridgeHeal.info = "fire: noticing"
        return false
    end

    local tool = BridgeHeal.fireTool(body, red)
    if tool == nil then
        if BridgeHeal.fireSaid == 0 then
            BridgeHeal.fireSaid = 1
            say("Fire_NoWater")
        end
        BridgeHeal.fireState = "nowater"
        BridgeHeal.info = "fire: nothing to douse with"
        return false
    end


    if burning then
        local d = dist(body, red)
        if d > FIRE_REACH then
            if BridgeHeal.fireSaid < 2 then
                BridgeHeal.fireSaid = 2
                say("Fire_Coming")
            end
            BridgeHeal.fireState = "walk"
            BridgeHeal.info = "fire: running to player"
            BridgeMove.walkType = "Run"
            pcall(function() BridgeMove.goToward(body, red:getX(), red:getY(), red:getZ(), true) end)
            return true
        end
        if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        pcall(function() body:faceLocationF(red:getX(), red:getY()) end)
    end



    if BridgeHeal.douseSince == nil then
        BridgeHeal.douseSince = Bridge.time
        BridgeHeal.fireState = "douse"
        BridgeHeal.info = "fire: dousing"
        if BridgeHeal.fireSaid < 3 then
            BridgeHeal.fireSaid = 3
            say("Fire_Coming")
        end
    end
    pcall(function() if body:getBumpType() ~= "TreatLow" then body:setBumpType("TreatLow") end end)
    if Bridge.time - BridgeHeal.douseSince < DOUSE_FRAMES then return true end
    BridgeHeal.douseSince = nil

    useFireTool(tool)
    if burning then pcall(function() red:StopBurning() end) end
    if meBurning then pcall(function() body:StopBurning() end) end


    local squares = douseGround(body, red, burning, meBurning)
    BridgeHeal.fireState = "done"
    BridgeHeal.firedAt = Bridge.time
    BridgeHeal.fireSince = nil
    BridgeHeal.fireSaid = 0
    BridgeHeal.info = "fire: doused"
    log("fire doused player=" .. tostring(burning) .. " me=" .. tostring(meBurning) ..
        " squares=" .. tostring(squares))
    say(burning and "Fire_Done" or "Fire_DoneSelf")
    return true
end


function BridgeHeal.update(body)
    local red = BridgeData.owner()
    if red == nil then return false end


    local okFire, busyFire = pcall(function() return BridgeHeal.fireUpdate(body, red) end)
    if okFire and busyFire then
        if BridgeHeal.active then BridgeHeal.stop("fire") end
        return true
    end


    local redInCar = false
    pcall(function() redInCar = red:getVehicle() ~= nil end)
    if redInCar then
        if BridgeHeal.active then BridgeHeal.stop("player in car") end
        return false
    end

    if not BridgeHeal.active then
        if Bridge.every(CHECK_EVERY) then BridgeHeal.autoCheck(body, red) end
        return BridgeHeal.active
    end



    local limit = BridgeHeal.byRequest and REQUEST_REACH or GIVEUP_DIST
    if BridgeHeal.state == "work" then limit = GIVEUP_DIST end
    if dist(body, red) > limit then say("Heal_Left") BridgeHeal.stop("player far") return false end
    if Bridge.every(10) and BridgeHeal.threatNear(body, red, BridgeHeal.byRequest, BridgeHeal.state == "walk") then
        say("Heal_Zombie")
        BridgeHeal.stop("zombie")
        BridgeHeal.quietSince = nil
        return false
    end

    if BridgeHeal.current == nil then
        if Bridge.time < BridgeHeal.nextAt then return true end
        local step = table.remove(BridgeHeal.queue, 1)
        if step == nil then finish(body, red) return false end
        step.startTick = nil
        BridgeHeal.current = step
        BridgeHeal.state = "walk"
        BridgeHeal.walkSince = Bridge.time
        BridgeHeal.bestDist = nil
    end
    local step = BridgeHeal.current



    local d = dist(body, red)
    if d > REACH then
        if BridgeHeal.state ~= "walk" then
            BridgeHeal.walkSince = Bridge.time
            BridgeHeal.bestDist = nil
        end
        BridgeHeal.state = "walk"
        if BridgeHeal.bestDist == nil or d < BridgeHeal.bestDist - 0.5 then
            BridgeHeal.bestDist = d
            BridgeHeal.walkSince = Bridge.time
        end
        if (Bridge.time - (BridgeHeal.walkSince or Bridge.time)) > 300 then
            say("Heal_Reach")
            BridgeHeal.stop("cannot reach")
            return false
        end
        BridgeMove.walkType = d > 4 and "Run" or "Walk"

        pcall(function() BridgeMove.goToward(body, red:getX(), red:getY(), red:getZ(), d > 3) end)
        return true
    end
    if BridgeMove.onPath() then BridgeMove.stopPath(body) end
    pcall(function() body:faceLocationF(red:getX(), red:getY()) end)


    if step.startTick == nil then
        step.startTick = Bridge.time
        BridgeHeal.state = "work"
        BridgeHeal.info = step.kind .. " " .. step.w.key

        local stepKey = step.kind
        if step.kind == "unbandage" and not step.w.dirty then stepKey = "unbandage_clean" end
        say("Heal_Step", tr("Heal_" .. stepKey), step.w.name)
        startSounds(body, red, step)
    end
    local anim = PART_ANIM[step.w.key] or "TreatMid"
    pcall(function() if body:getBumpType() ~= anim then body:setBumpType(anim) end end)
    if (Bridge.time - step.startTick) >= STEP_FRAMES then
        stopSounds(body, red, step)
        local ok, err = pcall(function() return apply(body, red, step) end)
        if ok and err ~= nil then ok = false end
        if not ok then
            warn("apply failed: " .. tostring(err))
            BridgeHeal.info = "apply error: " .. tostring(err)
        else
            BridgeHeal.done = BridgeHeal.done + 1
            if step.dirty then say("Heal_DirtyBandage") end
        end
        BridgeHeal.current = nil
        BridgeHeal.nextAt = Bridge.time + GAP_FRAMES
        pcall(function() body:setBumpType("") end)
    end
    return true
end

log("loaded")

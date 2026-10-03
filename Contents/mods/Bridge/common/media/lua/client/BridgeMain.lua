
















if BridgeLog ~= nil and BridgeLog.on() then print("[Bridge] main loaded v225") end


local START_AXE = { condition = 10, head = 10, sharpness = 0.6 }

Bridge = Bridge or {}
Bridge.body = nil
Bridge.kind = nil
Bridge.follow = false
Bridge.mode = "follow"
Bridge.pose = nil
Bridge.target = nil
Bridge.ack = 0
Bridge.tick = 0





Bridge.time = 0
Bridge.prevTime = 0
Bridge.dt = 1
Bridge.lastPath = 0
Bridge.manualUpdate = false
Bridge.result = "loaded"
Bridge.skipped = false
Bridge.zombieTicks = 0
Bridge.idleSince = 0
Bridge.checked = {}
Bridge.stash = nil
Bridge.stashAt = 0
Bridge.walkSpy = nil
Bridge.walk60 = 0
Bridge.red60 = 0
Bridge.stuckCount = 0
Bridge.wornSeen = nil
Bridge.itemsSeen = nil
Bridge.enginePos = nil
Bridge.engineAcc = 0
Bridge.engineWalk = 0
Bridge.holdPos = nil
Bridge.nextIdleAnim = 0
Bridge.scareStopped = 0
Bridge.hiddenSince = nil
Bridge.parked = false
Bridge.mp = false
Bridge.spawnAsked = nil
Bridge.askedId = nil
Bridge.askedNext = nil
Bridge.lostId = nil
Bridge.lostSince = nil
Bridge.lostNext = nil
Bridge.lostTries = 0
Bridge.lostCall = nil
Bridge.panicSaved = nil
Bridge.seenIds = {}
Bridge.lastScare = -9999
Bridge.scareCount = 0
Bridge.othersNear = 0
Bridge.bodySeen = false
Bridge.respawnAt = nil
Bridge.touched = {}
Bridge.released = nil
Bridge.releasedTick = 0
Bridge.releasedByCommand = false
Bridge.groundTicks = 0
Bridge.lastAsn = ""
Bridge.hitRestore = nil



Bridge.mortal = false
Bridge.hitClean = nil
Bridge.copyHit = {}
Bridge.wornTypes = nil
Bridge.world = nil
Bridge.seen = {}
Bridge.looks = {}
Bridge.bridgeOn = false
Bridge.bridgeCheckTick = -9999
Bridge.startTick = nil
Bridge.homeParked = false
Bridge.sleepParked = nil
Bridge.claimParked = nil
Bridge.gotData = false
Bridge.leaveAt = nil

local IN_FILE = "bridge/in.txt"
local OUT_FILE = "bridge/out.txt"

local APPEAR_DELAY = 180


local GONE_SOON = 600
local BACKOFF_FIRST = 300
local BACKOFF_MAX = 1800
local BACKOFF_RESET = 1200
local HOME_NEAR = 35
local HOME_FAR = 45
local READ_EVERY = 10
local WRITE_EVERY = 30
local PATH_EVERY = 30
local FOLLOW_DIST = 2.5
local BODY_VAR = "NotAloneBody"
Bridge.BODY_VAR = BODY_VAR

local function log(text)
    if BridgeLog ~= nil and BridgeLog.on() then print("[Bridge] " .. tostring(text)) end
end
local function warn(text) print("[Bridge] " .. tostring(text)) end





local VERBOSE_FILE = "bridge/verbose.txt"
Bridge.verbose = false
Bridge.verboseCheckTick = -9999
local function vlog(text)
    if Bridge.verbose then log(text) end
end

local function split(text)
    local parts = {}
    for word in string.gmatch(text, "%S+") do
        parts[#parts + 1] = word
    end
    return parts
end


local function tail(text, skip)
    local count, pos = 0, 1
    while count < skip do
        local s, e = string.find(text, "%S+", pos)
        if not s then return "" end
        pos = e + 1
        count = count + 1
    end
    return (string.gsub(string.sub(text, pos), "^%s+", ""))
end

local function decode(text)
    if string.sub(text, 1, 4) == "hex:" and BridgeChat ~= nil then
        return BridgeChat.fromHex(string.sub(text, 5))
    end
    return text
end

local function dist2d(a, b)
    local dx = a:getX() - b:getX()
    local dy = a:getY() - b:getY()
    return math.sqrt(dx * dx + dy * dy)
end



function Bridge.alive()
    if Bridge.body == nil then return false end
    local ok, dead = pcall(function() return Bridge.body:isDead() end)



    if ok and dead and not Bridge.mp and not Bridge.mortal and Bridge.kind == "zombie" then
        local killed = true
        pcall(function() killed = Bridge.body:isOnKillDone() or Bridge.body:isOnDeathDone() end)
        if not killed then
            pcall(function() Bridge.body:setHealth(1) end)

            pcall(function() local bd = Bridge.body:getBodyDamage() if bd ~= nil and bd:getOverallBodyHealth() <= 0 then bd:RestoreToFullHealth() end end)
            pcall(function() dead = Bridge.body:isDead() end)
            if not dead and Bridge.time - (Bridge.hpLogAt or -99999) >= 60 then
                Bridge.hpLogAt = Bridge.time
                log("health 0 without a kill (set by something else): back to 1, same body")
            end
        end
    end
    if not ok or dead then return false end

    local okVar, marked = pcall(function() return Bridge.body:getVariableBoolean(BODY_VAR) end)
    if okVar and not marked and Bridge.kind == "zombie" then


        if Bridge.time - (Bridge.markLostLogAt or -99999) >= 60 then
            Bridge.markLostLogAt = Bridge.time
            log("body mark gone: the object is not hers any more (reused by the game or reset)")
        end
        return false
    end
    if Bridge.mp and Bridge.kind == "zombie" then
        local md = Bridge.store
        local okPid, pid = pcall(function() return Bridge.body:getPersistentOutfitID() end)
        if md == nil or md.bodyId == nil or not okPid or pid ~= md.bodyId then return false end
    end
    return true
end


function Bridge.drivable()
    if not Bridge.alive() or Bridge.kind ~= "zombie" then return false end
    if not Bridge.mp then return true end
    local remote = true
    pcall(function() remote = Bridge.body:isRemoteZombie() end)
    return not remote
end



function Bridge.isOwner()
    return Bridge.store ~= nil and BridgeData.me() ~= nil
end

function Bridge.ownerPlayer()
    return BridgeData.owner()
end


function Bridge.companionName()
    return BridgeData.nameOf(Bridge.store)
end



function Bridge.weaponVar(z)
    local v = ""
    pcall(function()
        local item = z:getPrimaryHandItem()
        if item ~= nil and instanceof(item, "HandWeapon") and (item:isTwoHandWeapon() or item:isRequiresEquippedBothHands()) then
            v = "2h"
        end
    end)
    pcall(function()
        if z:getVariableString("NotAloneWeapon") ~= v then z:setVariable("NotAloneWeapon", v) end
    end)
end



function Bridge.clearHitMarks(body)
    pcall(function()
        body:setKnockedDown(false)
        body:setStaggerBack(false)
        body:setOnFloor(false)
        body:setHitReaction("")
        body:setHitForce(0)
        body:setVariable("hitreaction", "")
        body:setVariable("bKnockedDown", false)
    end)
    pcall(function()
        local visual = body:getHumanVisual()
        for i = 1, BloodBodyPartType.MAX:index() do
            local part = BloodBodyPartType.FromIndex(i - 1)
            if visual:getBlood(part) > 0 then visual:setBlood(part, 0) end
        end
    end)
    pcall(function()
        local worn = body:getWornItems()
        for i = 0, worn:size() - 1 do
            local item = worn:getItemByIndex(i)
            if item ~= nil and instanceof(item, "Clothing") then
                local parts = BloodClothingType.getCoveredParts(item:getBloodClothingType())
                if parts ~= nil then
                    for j = 0, parts:size() - 1 do item:setBlood(parts:get(j), 0) end
                end
                pcall(function() item:setBloodLevel(0) end)
            end
        end
    end)
end



Bridge.POSE_DRIFT = 0.3
Bridge.POSE_DRIFT_SEAT = 0.12
Bridge.POSE_TOUCH = 1.0




function Bridge.poseNudged(body)
    local pose = Bridge.pose
    if pose == nil then return false end
    local near = nil
    local function test(p)
        if near ~= nil or p == nil or p == body then return end
        local ok, close = pcall(function()
            if p:isDead() or math.abs(p:getZ() - body:getZ()) > 0.5 then return false end
            local dx, dy = p:getX() - body:getX(), p:getY() - body:getY()
            return dx * dx + dy * dy < Bridge.POSE_TOUCH * Bridge.POSE_TOUCH
        end)
        if ok and close then near = p end
    end
    pcall(function() test(BridgeData.owner()) end)
    if near == nil and Bridge.mp then
        pcall(function()
            local list = getOnlinePlayers()
            for i = 0, list:size() - 1 do test(list:get(i)) end
        end)
    end
    if pose.origin == nil then
        local h = Bridge.holdPos
        pose.origin = h ~= nil and { h[1], h[2] } or { body:getX(), body:getY() }
    end
    local was = pose.nudged == true
    pose.nudged = near ~= nil
    if was ~= pose.nudged then
        local d = 0
        pcall(function()

            local h = Bridge.holdPos or { body:getX(), body:getY() }
            local ox, oy = h[1] - pose.origin[1], h[2] - pose.origin[2]
            d = math.sqrt(ox * ox + oy * oy)
        end)
        local who = "?"
        pcall(function() who = tostring(near and near:getUsername() or "") end)
        log(string.format("pose %s: %s, moved %.2f from seat (cap %.2f)", tostring(pose.anim),
            pose.nudged and ("someone close, " .. who) or "alone again, held here", d,
            pose.seat and Bridge.POSE_DRIFT_SEAT or Bridge.POSE_DRIFT))
    end
    return pose.nudged
end



function Bridge.sneakVar(z, on)
    pcall(function()
        if z:getVariableBoolean("NotAloneSneak") ~= on then z:setVariable("NotAloneSneak", on) end
    end)
end




Bridge.sneakSeen = nil
Bridge.sneakWatch = nil
function Bridge.sneakTrace(body, red, on)
    if not Bridge.verbose then Bridge.sneakSeen, Bridge.sneakWatch = on, nil return end
    local function snap()
        local d = -1
        if red ~= nil then
            local dx, dy = body:getX() - red:getX(), body:getY() - red:getY()
            d = math.sqrt(dx * dx + dy * dy)
        end
        return string.format("d=%.2f bump=%s asn=%s weapon=%s pathing=%s moving=%s walk=%s", d,
            tostring(body:getBumpType()), tostring(body:getActionStateName()),
            tostring(body:getVariableString("NotAloneWeapon")), tostring(BridgeMove.pathing),
            tostring(BridgeMove.moving), tostring(BridgeMove.walkType))
    end
    if Bridge.sneakSeen ~= nil and Bridge.sneakSeen ~= on then
        log("sneak " .. (on and "on" or "off") .. ": " .. snap())
        Bridge.sneakWatch = { start = Bridge.tick, last = nil }
    end
    Bridge.sneakSeen = on
    local w = Bridge.sneakWatch
    if w == nil then return end
    if Bridge.tick - w.start > 40 then Bridge.sneakWatch = nil return end
    local key = tostring(body:getBumpType()) .. "|" .. tostring(body:getActionStateName())
    if w.last ~= nil and key ~= w.last then log("sneak +" .. tostring(Bridge.tick - w.start) .. ": " .. snap()) end
    w.last = key
end






function Bridge.hideBody(z, hide)
    if z == nil then return end
    pcall(function() z:setInvisible(hide == true, true) end)



    Bridge.hiddenObjs = Bridge.hiddenObjs or {}
    Bridge.hiddenObjs[z] = hide == true or nil







    pcall(function() for i = 0, 3 do z:setAlphaAndTarget(i, hide and 0 or 1) end end)
end


function Bridge.keepHidden(body, where)
    if Bridge.hiddenSince == nil and not (BridgeCar ~= nil and BridgeCar.holdHidden()) then return end

    if Bridge.mp and not Bridge.drivable() then return end
    Bridge.hiddenLogN = (Bridge.hiddenLogN or 0) + 1
    if Bridge.verbose and where ~= nil and Bridge.hiddenLogN % 30 == 0 then
        local a, t, r = -1, -1, "?"
        pcall(function() a, t = body:getAlpha(0), body:getTargetAlpha(0) end)
        pcall(function() r = tostring(body:getDoRender()) end)
        vlog(string.format("hidden body at %s: alpha %.2f target %.2f render %s", tostring(where), a, t, r))
    end
    pcall(function() for i = 0, 3 do body:setAlphaAndTarget(i, 0) end end)
end

local function humanize(body)
    body:setVariable(BODY_VAR, true)

    pcall(function() BridgeInventory.bodyArrived() end)


    pcall(function() body:setReanimatedForGrappleOnly(false) end)



    body:setVariable("SurvivorNPC", true)
    pcall(function() Bridge.touched[body] = body:getPersistentOutfitID() end)
    pcall(function() body:getModData().notAloneBody = true end)






    pcall(function() body:getModData().bScroungerorIncomprehensiveRolled = true end)

    pcall(function() BridgeInventory.gestureReset() end)
    body:setNoTeeth(true)


    pcall(function() body:getModData().ST_Ignore = true end)
    body:setVariable("LimpSpeed", 0.80)
    body:setVariable("RunSpeed", 0.65)
    body:setVariable("WalkSpeed", 1.0)

    body:setVariable("WalkInjury", 0.0)
    body:setVariable("NotAloneAnimOld", false)
    body:setWalkType("Walk")

    body:setVariable("ZombieHitReaction", "Chainsaw")
    body:setVariable("NoLungeTarget", true)
    pcall(function() body:getEmitter():stopAll() end)
    pcall(function() body:getDescriptor():setVoicePrefix("VoiceFemale") end)
    body:setTurnAlertedValues(-5, 5)
    pcall(function() body:setSceneCulled(false) end)

    pcall(function() body:setDressInRandomOutfit(false) end)
    body:setUseless(true)
    body:setTarget(nil)
    body:clearAggroList()




    pcall(function() body:setShootable(false) end)
    pcall(function() body:setInvulnerable(true) end)
    pcall(function() body:setGodMod(true, true) end)
    pcall(function() body:getInventory():setCapacity(15) end)
    pcall(function() body:getInventory():setExplored(true) end)
end











function Bridge.unhumanize(z, pooled)


    pcall(function() BridgeInventory.forgetBody(z) end)
    for _, name in ipairs({ "WalkSpeed", "RunSpeed", "LimpSpeed", "ZombieHitReaction", "NoLungeTarget", "NotAloneWeapon",
                            "NotAloneStride", "WalkInjury", "NotAloneAnimOld", "NotAloneSneak", "SurvivorNPC" }) do
        pcall(function() z:clearVariable(name) end)
    end
    pcall(function() z:setVariable(BODY_VAR, false) end)
    pcall(function() if z:hasModData() then z:getModData().ST_Ignore = nil end end)

    pcall(function() BridgeWeapon.release(z) end)
    pcall(function() z:clearAttachedItems() end)
    pcall(function() z:setPrimaryHandItem(nil) end)
    pcall(function() z:setSecondaryHandItem(nil) end)
    pcall(function() z:getWornItems():clear() end)
    pcall(function() z:getInventory():clear() end)
    pcall(function() z:setUseless(false) end)
    pcall(function() z:setShootable(true) end)
    pcall(function() z:setInvulnerable(false) end)
    pcall(function() z:setGodMod(false, true) end)
    Bridge.hideBody(z, false)


    pcall(function() z:setReanimatedForGrappleOnly(false) end)
    pcall(function() if BridgeFastForward ~= nil and BridgeFastForward.flagged == z then BridgeFastForward.flagged = nil end end)


    pcall(function() if z:isSittingOnFurniture() then z:setSittingOnFurniture(false) end end)
    pcall(function() z:setCollidable(true) end)
    pcall(function() z:setDressInRandomOutfit(true) end)


    if pooled then pcall(function() z:getItemVisuals():clear() end) end
    if not pooled then



        pcall(function()
            local pid = z:getPersistentOutfitID()
            if pid == nil or pid == 0 then
                z:dressInRandomOutfit()
            else
                z:dressInPersistentOutfitID(pid)
            end
        end)
        pcall(function() z:resetModelNextFrame() end)
    end
    Bridge.touched[z] = nil
end














function Bridge.releaseForeign(z)
    for _, name in ipairs({ "NotAloneWeapon", "NotAloneStride", "NotAloneAnimOld", "NotAloneSneak" }) do
        pcall(function() z:clearVariable(name) end)
    end
    local npc, brain = BridgeData.banditBrain(z, true)
    if npc then
        pcall(function() z:getInventory():clear() end)
        if brain ~= nil and type(Bandit) == "table" and type(Bandit.UpdateItemsToSpawnAtDeath) == "function" then
            pcall(Bandit.UpdateItemsToSpawnAtDeath, z, brain)
        end
    end
    pcall(function() z:setVariable(BODY_VAR, false) end)

    pcall(function()
        if z:hasModData() then
            z:getModData().ST_Ignore = nil
            z:getModData().notAloneBody = nil
        end
    end)
    pcall(function() BridgeWeapon.release(z) end)
    pcall(function() z:setShootable(true) end)
    pcall(function() z:setInvulnerable(false) end)
    pcall(function() z:setGodMod(false, true) end)
    Bridge.hideBody(z, false)
    pcall(function() z:setReanimatedForGrappleOnly(false) end)
    pcall(function() if BridgeFastForward ~= nil and BridgeFastForward.flagged == z then BridgeFastForward.flagged = nil end end)
    pcall(function() if z:isSittingOnFurniture() then z:setSittingOnFurniture(false) end end)
    pcall(function() z:setCollidable(true) end)
    Bridge.touched[z] = nil
    log("old body object went to another mod's NPC: only own flags cleared")
end


local function release(z, pooled)
    if BridgeData.foreign(z) then Bridge.releaseForeign(z) else Bridge.unhumanize(z, pooled) end
end


local function reusedBody(z)
    local was = Bridge.touched[z]
    if was == nil then return false end
    local now = nil
    pcall(function() now = z:getPersistentOutfitID() end)
    return now ~= was
end






Bridge.store = nil



function Bridge.refreshStore()
    local w = Bridge.world
    if w == nil then return end
    if w.players == nil then w.players = {} end
    local me = BridgeData.me()
    if me == nil then
        Bridge.store = Bridge.store or {}
        return
    end
    if w.players[me] == nil then w.players[me] = {} end
    Bridge.store = w.players[me]


    if Bridge.mp then
        local incoming = Bridge.store.rel
        if Bridge.localRel ~= nil and incoming ~= Bridge.localRel then
            if type(incoming) == "table" and tonumber(incoming.giftAt) ~= nil
                and incoming.giftAt > (Bridge.localRel.giftAt or 0) then
                Bridge.localRel.giftAt = incoming.giftAt
            end
            Bridge.store.rel = Bridge.localRel
        elseif Bridge.localRel == nil and type(incoming) == "table" then
            Bridge.localRel = incoming
        end
    end
end

function Bridge.initStore()
    Bridge.mp = isClient()

    if Bridge.mp and Bridge.gotData and Bridge.world ~= nil then
        Bridge.refreshStore()
        return
    end
    local ok, md = pcall(function() return BridgeData.world(BridgeData.LOCAL) end)

    if ok and not Bridge.mp and BridgeBackup ~= nil then pcall(BridgeBackup.check, md) end
    if ok then
        Bridge.world = md
        if not Bridge.mp then Bridge.gotData = true end
        Bridge.refreshStore()
        log("store ready, mp=" .. tostring(Bridge.mp))
    else
        warn("store failed: " .. tostring(md))
    end
    if Bridge.mp then pcall(function() ModData.request(BridgeData.KEY) end) end
end


function Bridge.onReceiveGlobalModData(key, data)
    if key ~= BridgeData.KEY or type(data) ~= "table" then return end
    Bridge.world = data
    Bridge.gotData = true
    Bridge.refreshStore()
    Bridge.indexBodies()



    if Bridge.iseq == nil and Bridge.store ~= nil and type(Bridge.store.iseq) == "number" then Bridge.iseq = Bridge.store.iseq end
    local id = Bridge.store and Bridge.store.bodyId
    if Bridge.released ~= nil and id ~= Bridge.released then Bridge.released = nil end
    log("store from server: bodyId=" .. tostring(id) .. " saved=" .. tostring(Bridge.store and Bridge.store.saved))
end

local function outfitStore()
    if Bridge.store ~= nil and Bridge.world ~= nil then return Bridge.store end
    Bridge.initStore()
    return Bridge.store
end



function Bridge.saveOutfit(encoded)
    if not Bridge.alive() or Bridge.kind ~= "zombie" then return false end
    local md = outfitStore()
    if md == nil then return false end

    if Bridge.redressedByGame(Bridge.body) then
        log("snapshot skipped: body re-dressed by the game")
        return false
    end
    local ok = pcall(function()
        if encoded == nil then encoded = BridgeInventory.encode(BridgeInventory.snapshot(Bridge.body)) end
        md.items = encoded
        md.saved = 1


        if Bridge.mp then sendClientCommand(BridgeData.owner(), "Bridge", "outfit", { items = encoded, iseq = Bridge.iseq }) end
    end)
    if ok then
        Bridge.itemsSeen = encoded
        Bridge.itemsSavedTick = Bridge.time
        pcall(function() Bridge.itemsSign = BridgeItems.signature(BridgeItems.decode(encoded)) end)
        pcall(function() Bridge.noteWorn(encoded) end)
        if not Bridge.mp and BridgeBackup ~= nil then pcall(BridgeBackup.noteItems, Bridge.body, encoded) end
    end
    return ok
end




function Bridge.noteWorn(encoded)
    local now, list = {}, BridgeItems.decode(encoded or "")
    for _, r in ipairs(list) do
        if r.p == nil and r.w then now[#now + 1] = r.t end
    end
    table.sort(now)
    local was = Bridge.wornTypes
    Bridge.wornTypes = now
    if was == nil then return end
    local have = {}
    for _, t in ipairs(now) do have[t] = (have[t] or 0) + 1 end
    local lost = {}
    for _, t in ipairs(was) do
        if (have[t] or 0) > 0 then have[t] = have[t] - 1 else lost[#lost + 1] = t end
    end
    if #lost > 0 then
        log("worn lost: " .. table.concat(lost, ",") .. " now=" .. table.concat(now, ",")
            .. " last=" .. tostring(Bridge.lastItemAction) .. " result=" .. tostring(Bridge.result))

        if #lost >= 2 then
            local b, info = Bridge.body, "?"
            pcall(function()
                info = string.format("init=%s random=%s pid=%s outfit=%s touched=%s state=%s z=%.1f car=%s visuals=%s",
                    tostring(b:isPersistentOutfitInit()), tostring(b:shouldDressInRandomOutfit()),
                    tostring(b:getPersistentOutfitID()), tostring(b:getOutfitName()), tostring(Bridge.touched[b]),
                    tostring(b:getActionStateName()), b:getZ(), tostring(b:getVehicle() ~= nil),
                    tostring(b:getItemVisuals():size()))
            end)
            log("worn lost at once: " .. info)
        end
    end
end









local HER_SKIN = "FemaleBody01"
Bridge.wornKeep = nil
Bridge.wornKeepBody = nil
Bridge.wornKeepSkin = false
Bridge.dressedWorn = nil
Bridge.engineRedress = 0

local function skinOf(b)
    local skin = nil
    pcall(function() skin = b:getHumanVisual():getSkinTexture() end)
    return skin
end

local function wornNow(b)
    local list = {}
    pcall(function()
        local worn = b:getWornItems()
        for i = 0, worn:size() - 1 do
            local item = worn:getItemByIndex(i)
            if item ~= nil then list[#list + 1] = item end
        end
    end)
    return list
end


function Bridge.keepWorn(b)
    Bridge.wornKeep = wornNow(b)
    Bridge.wornKeepBody = b
    Bridge.wornKeepSkin = skinOf(b) == HER_SKIN
    Bridge.wornKeepVisuals = 0
    pcall(function() Bridge.wornKeepVisuals = b:getItemVisuals():size() end)
end



function Bridge.redressedByGame(b)
    if b == nil or Bridge.wornKeepBody ~= b then return false end
    local skin, now = skinOf(b), wornNow(b)
    return Bridge.wornKeepSkin and skin ~= HER_SKIN and #now < #(Bridge.wornKeep or {}), now, skin
end


function Bridge.guardOutfit(b)
    if b == nil then return false end
    if Bridge.wornKeepBody ~= b then
        Bridge.keepWorn(b)
        return false
    end
    local hit, now, skin = Bridge.redressedByGame(b)
    if not hit then
        local visuals = -1
        pcall(function() visuals = b:getItemVisuals():size() end)

        if Bridge.wornKeepSkin and skin ~= HER_SKIN and visuals == 0 and (Bridge.wornKeepVisuals or 0) > 0 and #now >= 1 then
            pcall(function() BridgeInventory.skin(b, outfitStore()) end)
            pcall(function() BridgeInventory.redress(b, true) end)
            Bridge.engineRedress = (Bridge.engineRedress or 0) + 1
            log(string.format("body look wiped by the game (skin %s): worn %d kept, look back", tostring(skin), #now))
            Bridge.keepWorn(b)
            return true
        end
        Bridge.wornKeep = now
        Bridge.wornKeepSkin = skin == HER_SKIN
        Bridge.wornKeepVisuals = visuals
        return false
    end
    local keep = Bridge.wornKeep or {}
    local inv = b:getInventory()
    local back = 0
    for _, item in ipairs(keep) do
        pcall(function()
            if item:getContainer() == inv and not b:isEquippedClothing(item) and BridgeInventory.putOn(b, item) then
                back = back + 1
            end
        end)
    end
    pcall(function() BridgeInventory.skin(b, outfitStore()) end)
    pcall(function() BridgeInventory.redress(b, true) end)
    Bridge.engineRedress = (Bridge.engineRedress or 0) + 1
    log(string.format("body re-dressed by the game (skin %s): worn %d -> %d, put back %d",
        tostring(skin), #keep, #now, back))
    Bridge.keepWorn(b)
    return true
end




function Bridge.showReady(b)
    local worn, visuals = 0, 0
    pcall(function() worn = b:getWornItems():size() end)
    pcall(function() visuals = b:getItemVisuals():size() end)
    local want = Bridge.dressedWorn
    local dressed
    if want == nil then
        dressed = worn > 0 and visuals >= worn
    else
        dressed = worn >= want and visuals >= worn
    end
    local skinOk = skinOf(b) == HER_SKIN
    local age = Bridge.tick - (Bridge.hiddenSince or Bridge.tick)
    if dressed and skinOk and (Bridge.zombieTicks - (Bridge.hiddenTicks or 0)) >= 20 then return true, "dressed" end
    if age < 90 then return false, "waiting" end
    if not skinOk and age < 120 then
        pcall(function() BridgeInventory.skin(b, outfitStore()) end)
        pcall(function() b:resetModelNextFrame() end)
        return false, "skin"
    end
    return true, string.format("timeout: worn %d of %s, visuals %d, skin %s", worn, tostring(want), visuals, tostring(skinOk))
end



local function wearSaved(body)
    local md = outfitStore()

    if md ~= nil and BridgeBackup ~= nil then pcall(BridgeBackup.dedupe, md) end
    if md == nil or md.saved ~= 1 or md.items == nil then return nil end
    if md.items == "" then





        return "0 worn 0 hands 0 bag (empty save)"
    end
    local list = BridgeInventory.decode(md.items)
    if #list == 0 then return nil end
    local worn, hands, bag = BridgeInventory.restore(body, list)
    return string.format("%d worn %d hands %d bag", worn, hands, bag)
end

Bridge.wearSaved = wearSaved





local function migrateLook(body, st)
    if st == nil then return "" end
    local flags, out = {}, ""
    if not st.beltGiven then
        pcall(function()
            local inv = body:getInventory()
            local belt = inv:AddItem("Base.Belt2")
            if belt == nil then return end
            local loc = belt:getBodyLocation()
            local busy = false
            local worn = body:getWornItems()
            for i = 0, worn:size() - 1 do
                local w = worn:getItemByIndex(i)
                if w ~= nil and w:getBodyLocation() == loc then busy = true end
            end
            if busy then inv:Remove(belt) return end
            body:setWornItem(loc, belt)
            out = out .. " +belt"
        end)
        st.beltGiven = true
        flags.beltGiven = true
    end
    if not st.armsSet then
        if BridgeWeapon.assignedId == nil then
            local pick, best = nil, -1
            pcall(function()
                local hand = body:getPrimaryHandItem()
                if BridgeWeapon.isMelee(hand) then pick = hand return end
                local items = body:getInventory():getItems()
                for i = 0, items:size() - 1 do
                    local it = items:get(i)
                    if BridgeWeapon.isMelee(it) then
                        local dmg = 0
                        pcall(function() dmg = it:getMaxDamage() or 0 end)
                        if dmg > best then pick, best = it, dmg end
                    end
                end
            end)
            if pick ~= nil then
                BridgeWeapon.assignedId = pick:getID()
                out = out .. " +assigned " .. tostring(pick:getType())
            end
        end
        st.armsSet = true
        flags.armsSet = true
    end


    local anyFlag = false
    for _ in pairs(flags) do anyFlag = true break end
    if Bridge.mp and anyFlag then
        local okS, errS = pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", flags) end)
        if not okS then warn("migrateLook state failed: " .. tostring(errS)) end
    end
    return out
end



local function dressBody(body)
    if not BridgeInventory.skin(body, outfitStore()) then return "no HumanVisual" end

    body:getItemVisuals():clear()
    body:getWornItems():clear()

    local inv = body:getInventory()


    local restored = wearSaved(body)
    if restored ~= nil then
        local extra = migrateLook(body, outfitStore())


        if BridgeSocial ~= nil and BridgeSocial.markGiven ~= nil then
            pcall(function()
                local worn = body:getWornItems()
                for i = 0, worn:size() - 1 do BridgeSocial.markGiven(worn:getItemByIndex(i)) end
            end)
        end
        pcall(function() BridgeInventory.redress(body) end)
        return "dressed from save: " .. restored .. extra
    end
    BridgeWeapon.assignedId = nil








    local st = outfitStore()
    local first = st == nil or not st.outfitGiven


    local outfit = {
        { t = "Base.Tshirt_WhiteTINT", tint = { 0.13, 0.10, 0.11 } },
        { t = "Base.Trousers_Denim", tc = 1 },
        { t = "Base.Shoes_CowboyBoots_Black" },

        { t = "Base.Belt2" },
    }
    if first then
        outfit[#outfit + 1] = { t = "Base.Jacket_SheepSkin_Navy", alt = "Base.Jacket_PaddedDOWN", altTint = { 0.10, 0.13, 0.25 } }
    end
    local worn = 0
    for i = 1, #outfit do
        pcall(function()
            local item = inv:AddItem(outfit[i].t)
            local tint = outfit[i].tint
            if item == nil and outfit[i].alt ~= nil then
                item = inv:AddItem(outfit[i].alt)
                tint = outfit[i].altTint
            end
            if item == nil then return end
            if outfit[i].tc ~= nil then
                pcall(function() item:getVisual():setTextureChoice(outfit[i].tc) end)
            end
            if tint ~= nil then
                pcall(function() item:getVisual():setTint(ImmutableColor.new(tint[1], tint[2], tint[3], 1)) end)
            end
            body:setWornItem(item:getBodyLocation(), item)

            if BridgeSocial ~= nil and BridgeSocial.markGiven ~= nil then BridgeSocial.markGiven(item) end
            worn = worn + 1
        end)
    end
    if first then
        pcall(function()
            local axe = inv:AddItem("Base.WoodAxe")
            if axe ~= nil then




                pcall(function() axe:setCondition(START_AXE.condition) end)
                pcall(function() if axe.setHeadCondition ~= nil then axe:setHeadCondition(START_AXE.head) end end)
                pcall(function() if axe.setSharpness ~= nil then axe:setSharpness(START_AXE.sharpness) end end)
                body:setPrimaryHandItem(axe)
                body:setSecondaryHandItem(axe)
                BridgeWeapon.assignedId = axe:getID()
            end
        end)
        if st ~= nil then st.outfitGiven = true end
        if Bridge.mp then
            pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { outfitGiven = true }) end)
        end
    end

    if st ~= nil then
        st.beltGiven = true
        st.armsSet = true
        if Bridge.mp then
            pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { beltGiven = true, armsSet = true }) end)
        end
    end
    pcall(function() BridgeInventory.redress(body) end)
    return "dressed " .. tostring(worn)
end


local function dress(body)
    Bridge.dressedWorn = nil
    local res = dressBody(body)
    pcall(function()
        Bridge.keepWorn(body)
        Bridge.dressedWorn = #Bridge.wornKeep
    end)
    return res
end








local SCARE_RADIUS = 10





local SCARE_CLOSE = 5
local SCARE_SEE = 7
local SCARE_QUIET = 600
local SCARE_EVERY = 600
local SEEN_EVERY = 5





local function stopGameScare(red)
    pcall(function()
        local emitter = red:getEmitter()
        if emitter:isPlaying("ZombieSurprisedPlayer") then
            emitter:stopSoundByName("ZombieSurprisedPlayer")
            Bridge.scareStopped = Bridge.scareStopped + 1
        end
    end)
end

local function scareVolume()
    local v = 10
    pcall(function() v = getCore():getOptionJumpScareVolume() end)
    if v == nil then return 1 end
    if v > 10 then return v / 100 end
    return v / 10
end

local function restorePanic(red)
    if Bridge.panicSaved == nil then return end
    local v = Bridge.panicSaved
    Bridge.panicSaved = nil
    pcall(function() red:getBodyDamage():setPanicIncreaseValue(v) end)
end


function Bridge.restoreRed()
    pcall(function() restorePanic(BridgeData.owner()) end)
end






function Bridge.isCompanion(z)
    local yes = false
    pcall(function()
        if z:getVariableBoolean(BODY_VAR) then yes = true return end
        if not Bridge.mp then return end
        local pid = z:getPersistentOutfitID()
        if Bridge.bodyIndex[pid] ~= nil or (Bridge.store ~= nil and Bridge.store.bodyId == pid) then yes = true return end
        if BridgeRemnant ~= nil and BridgeRemnant.hasMark(pid) and z:isFemale() and z:getOutfitName() == "Naked" then yes = true end
    end)
    return yes
end





local function watchOthers(red, body, around)
    local pn = 0
    pcall(function() pn = red:getPlayerNum() end)
    local seen, count, newClose, gameSeen = {}, 0, nil, 0
    local redRoom = nil
    pcall(function()
        local sq = red:getCurrentSquare()
        if sq ~= nil then redRoom = sq:getRoom() end
    end)
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)


            if z ~= nil and z ~= body and z:isAlive() and not Bridge.isCompanion(z)
                and math.abs(z:getZ() - red:getZ()) < 0.8 and not BridgeData.harmless(z) then
                local d = dist2d(z, red)
                if d < SCARE_RADIUS then
                    local sq = z:getCurrentSquare()
                    if sq ~= nil and sq:isCanSee(pn) then

                        seen[z] = true
                        count = count + 1
                        if d < SCARE_SEE and sq:getRoom() == redRoom then gameSeen = gameSeen + 1 end
                        if not Bridge.seenIds[z] and d < SCARE_CLOSE then newClose = z end
                    end
                end
            end
        end
    end)
    Bridge.seenIds = seen
    Bridge.othersNear = count
    local quietFor = Bridge.time - (Bridge.othersSeenAt or -99999)
    if gameSeen > 0 then Bridge.othersSeenAt = Bridge.time end
    if body ~= nil then
        pcall(function()
            local sq = body:getCurrentSquare()
            Bridge.bodySeen = sq ~= nil and sq:isCanSee(pn)
        end)
    end
    local vol = scareVolume()

    if vol <= 0 and not Bridge.scareMuteLogged then
        Bridge.scareMuteLogged = true
        log("scare: jump scare volume is 0 in the game settings, no scare sound at all")
    end

    local asleep = false
    pcall(function() asleep = red:isAsleep() == true end)
    if BridgeSleep ~= nil and BridgeSleep.pending ~= nil then asleep = true end
    local play = around == true and not asleep and newClose ~= nil and quietFor >= SCARE_QUIET
        and (Bridge.time - Bridge.lastScare) > SCARE_EVERY and vol > 0
    if around == true and newClose ~= nil and not play and Bridge.verbose then

        pcall(function()
            log(string.format("scare skipped: zombie at %.1f, quiet %.1f s, since last %.1f s, volume %.2f, seen %d",
                dist2d(newClose, red), math.min(quietFor, 99999) / 60, math.min(Bridge.time - Bridge.lastScare, 99999) / 60, vol, gameSeen))
        end)
    end
    if play then
        Bridge.lastScare = Bridge.time
        Bridge.scareCount = Bridge.scareCount + 1
        if Bridge.verbose then
            pcall(function()
                log(string.format("scare played: zombie id=%s at %.1f", tostring(newClose:getPersistentOutfitID()), dist2d(newClose, red)))
            end)
        end
        pcall(function()
            local emitter = red:getEmitter()
            local id = emitter:playSound("ZombieSurprisedPlayer")
            emitter:setVolume(id, vol)
        end)
    end
end




function Bridge.anyBody()
    if Bridge.alive() and Bridge.kind == "zombie" then return Bridge.body end
    if not Bridge.mp then return nil end
    for z in pairs(Bridge.bodiesSeen()) do return z end
    return nil
end




function Bridge.bodiesSeen()
    local out = {}
    for z, info in pairs(Bridge.seen) do
        local live = false
        pcall(function()
            live = (Bridge.time - info.tick) <= 60 and not z:isDead()
                and info.rec ~= nil and info.rec.bodyId ~= nil and z:getPersistentOutfitID() == info.rec.bodyId
        end)
        if live then out[z] = info else Bridge.seen[z] = nil end
    end
    return out
end




local function companionAround()
    if Bridge.alive() and Bridge.kind == "zombie" then return true end
    if Bridge.spawnAsked ~= nil or Bridge.respawnAt ~= nil or Bridge.lostCall then return true end
    if Bridge.mp and Bridge.store ~= nil and Bridge.store.bodyId ~= nil then return true end
    for _, info in pairs(Bridge.seen or {}) do
        if Bridge.time - (info.tick or -99999) <= 300 then return true end
    end
    local near, old = false, nil
    for z, s in pairs(Bridge.strays or {}) do
        if Bridge.time - (s.seenAt or s.since or -99999) <= 300 then near = true
        else old = old or {} old[#old + 1] = z end
    end
    if old ~= nil then for _, z in ipairs(old) do Bridge.unstray(z) end end
    return near
end
Bridge.companionAround = companionAround

function Bridge.onPlayerUpdate(red)
    if red == nil or red ~= BridgeData.owner() then return end
    Bridge.protectBodies()




    local around = companionAround()
    if around then pcall(function() red:setTimeSinceLastStab(0) end) end
    local body = Bridge.anyBody()


    if Bridge.every(SEEN_EVERY) then watchOthers(red, body, around) end

    if BridgeMood ~= nil then pcall(BridgeMood.frame, red) end
    if body == nil then Bridge.restoreRed() return end

    if (Bridge.time - Bridge.lastScare) > 150 then stopGameScare(red) end


    if Bridge.mp then return end
    if Bridge.othersNear > 0 then restorePanic(red) return end



    pcall(function()
        local bd = red:getBodyDamage()
        if Bridge.panicSaved == nil then
            Bridge.panicSaved = bd:getPanicIncreaseValue()
            bd:setPanicIncreaseValue(0)
        end
    end)
end




function Bridge.adoptServerBody(zombie)
    pcall(function() humanize(zombie) end)
    pcall(function() BridgeWash.stop("new body") end)
    pcall(function() BridgeWeapon.reset() end)
    Bridge.body = zombie
    Bridge.kind = "zombie"
    Bridge.target = nil
    Bridge.spawnAsked = nil
    if (Bridge.lostTries or 0) > 0 then log("body received after " .. tostring(Bridge.lostTries) .. " respawn asks") end
    Bridge.lostTries = 0
    Bridge.lostId, Bridge.lostSince, Bridge.lostNext, Bridge.lostCall = nil, nil, nil, nil
    BridgeMove.reset(nil)
    BridgeFight.reset(nil)
    Bridge.applyStoredMode()

    Bridge.hideBody(zombie, true)
    Bridge.hiddenSince = Bridge.tick
    Bridge.hiddenTicks = Bridge.zombieTicks
    local okDress, dressRes = pcall(function() return dress(zombie) end)
    Bridge.result = "adopted server body: " .. tostring(okDress and dressRes or dressRes)
    log(Bridge.result)
    return true
end






local function standSquareOk(sq, from)
    if sq == nil then return false end
    local ok = false
    pcall(function() ok = sq:isFree(false) and not sq:isVehicleIntersecting() and not sq:isWaterSquare() end)
    if ok and from ~= nil and from ~= sq then
        pcall(function()
            if math.abs(from:getX() - sq:getX()) <= 1 and math.abs(from:getY() - sq:getY()) <= 1 and from:isBlockedTo(sq) then
                ok = false
            end
        end)
    end
    return ok
end
Bridge.standSquareOk = standSquareOk




function Bridge.spawnSpot(cx, cy, z, aroundPlayer)
    local cell = getCell()
    if cell == nil then return nil end
    local from = nil
    pcall(function() from = cell:getGridSquare(cx, cy, z) end)

    if aroundPlayer then
        local spot, sz = nil, nil
        pcall(function()
            local red = BridgeData.owner()
            local zones = BridgeMove.seatZones(red)
            if zones ~= nil and zones.z == z then
                spot = BridgeMove.seatSpot(red, zones, cx + 0.5, cy + 0.5, nil, nil)
                sz = zones.z
            end
        end)
        if spot ~= nil then return spot.x, spot.y, sz end
    end
    local tries = { aroundPlayer and { 1, 1 } or { 0, 0 } }
    for r = 1, 3 do
        local ring = {}
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then ring[#ring + 1] = { dx, dy } end
            end
        end
        table.sort(ring, function(a, b) return a[1] * a[1] + a[2] * a[2] < b[1] * b[1] + b[2] * b[2] end)
        for _, d in ipairs(ring) do tries[#tries + 1] = d end
    end
    for _, d in ipairs(tries) do
        local sq = nil
        pcall(function() sq = cell:getGridSquare(cx + d[1], cy + d[2], z) end)
        if standSquareOk(sq, from) then return cx + d[1], cy + d[2], z end
    end
    return nil
end

function Bridge.spawnZombie(px, py, pz)
    local red = BridgeData.owner()
    if red == nil then return "no player" end




    if Bridge.redDead(red) then return "owner dead" end
    if Bridge.alive() then return "already alive" end

    local x = math.floor(px or red:getX())
    local y = math.floor(py or red:getY())
    local z = math.floor(pz or red:getZ())
    local sx, sy, sz = Bridge.spawnSpot(x, y, z, px == nil)
    if sx ~= nil then
        x, y, z = sx, sy, sz
    elseif px == nil then
        x, y = x + 1, y + 1
    end

    if Bridge.mp then
        Bridge.spawnAsked = Bridge.time
        Bridge.askedNext = true
        sendClientCommand(red, "Bridge", "spawn", { x = x, y = y, z = z, newLife = Bridge.newLifePending == true or nil })
        return "spawn asked from server"
    end

    local failed = nil
    local ok, err = pcall(function()

        local list = addZombiesInOutfit(x, y, z, 1, "Naked", 100, false, false, false, false, false, false, 1)
        if list == nil or list:size() == 0 then failed = "addZombiesInOutfit returned nothing" return end
        local body = list:get(0)


        local bodySq = nil
        pcall(function() bodySq = body:getCurrentSquare() end)
        if bodySq == nil then
            pcall(function() body:removeFromWorld() end)
            failed = "new body has no square yet, removed; will try again"
            return
        end



        if BridgeRemnant ~= nil then pcall(function() BridgeRemnant.mark(body) end) end
        humanize(body)


        Bridge.hideBody(body, true)
        Bridge.hiddenSince = Bridge.tick
        Bridge.hiddenTicks = Bridge.zombieTicks
        Bridge.createdTime = Bridge.time
        Bridge.body = body
        Bridge.kind = "zombie"
        Bridge.target = nil
        BridgeMove.reset(nil)
        BridgeFight.reset(nil)


        if not Bridge.parked and Bridge.sleepParked == nil and Bridge.claimParked == nil then BridgeFight.resetFatigue() end
        Bridge.applyStoredMode()
    end)
    if not ok or failed ~= nil then return "spawn zombie failed: " .. tostring(failed or err) end

    local okDress, dressRes = pcall(function() return dress(Bridge.body) end)
    if not okDress then dressRes = "dress failed: " .. tostring(dressRes) end

    return string.format("spawned zombie at %d %d %d, %s", x, y, z, tostring(dressRes))
end


function Bridge.spawnPlayer()
    local red = BridgeData.owner()
    if red == nil then return "no player" end
    if Bridge.alive() then return "already alive" end

    local cell = getCell()
    if cell == nil then return "no cell" end

    local x = red:getX() + 1
    local y = red:getY() + 1
    local z = red:getZ()

    local ok, err = pcall(function()
        local desc = SurvivorFactory.CreateSurvivor()
        local body = IsoPlayer.new(cell, desc, x, y, z)
        body:setUsername(Bridge.companionName())
        body:setSceneCulled(false)
        pcall(function() body:setNpc(true) end)

        local square = cell:getGridSquare(x, y, z)
        if square ~= nil then
            body:setCurrent(square)
        else
            body:setCurrentSquareFromPosition()
        end

        pcall(function() cell:addMovingObject(body) end)
        pcall(function() cell:addToProcessIsoObject(body) end)

        Bridge.body = body
        Bridge.kind = "player"
    end)

    if not ok then return "spawn player failed: " .. tostring(err) end
    return string.format("spawned player at %.1f %.1f %.0f", x, y, z)
end

function Bridge.despawn()
    pcall(function() BridgeWash.stop("despawn") end)
    if Bridge.mp then
        Bridge.restoreRed()
        local id = Bridge.store and Bridge.store.bodyId or nil
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "despawn", { byCommand = Bridge.despawnByCommand == true, id = id }) end)


        Bridge.released = Bridge.store and Bridge.store.bodyId or nil
        Bridge.releasedTick = Bridge.time
        Bridge.releasedByCommand = Bridge.despawnByCommand == true
        if Bridge.body ~= nil then Bridge.seen[Bridge.body] = nil end





        local mine = Bridge.body
        if mine ~= nil then
            pcall(function() Bridge.unhumanize(mine) end)
            pcall(function() mine:removeFromSquare() end)
            pcall(function() mine:removeFromWorld() end)
            log("own body object removed on client")
        end
        Bridge.body = nil
        Bridge.kind = nil
        Bridge.hiddenSince = nil
        Bridge.holdPos = nil
        Bridge.follow = false
        BridgeMove.reset(nil)
        BridgeFight.reset(nil)


        if not Bridge.parked and Bridge.sleepParked == nil and Bridge.claimParked == nil then BridgeFight.resetFatigue() end
        return "despawn asked from server"
    end
    if Bridge.body == nil then return "no body" end
    Bridge.restoreRed()
    local dying = Bridge.body






    local wasId = Bridge.touched[dying]
    local taken = reusedBody(dying)



    if taken then
        local still = false
        pcall(function() still = dying:getVariableBoolean(BODY_VAR) == true end)
        if still then
            taken = false
            log("despawn: outfit id changed by someone else, the object is still hers: removed as usual")
        end
    end
    local ok, err = pcall(function()
        if taken then
            local nowId = nil
            pcall(function() nowId = dying:getPersistentOutfitID() end)


            release(dying, nowId == 0)
            log(string.format("body was already taken by the game (population): id=%s now=%s at %.1f %.1f %.0f",
                tostring(wasId), tostring(nowId), dying:getX(), dying:getY(), dying:getZ()))
            return
        end
        pcall(function() if dying:getVehicle() ~= nil then BridgeMove.exitCar(dying) end end)

        Bridge.unhumanize(dying)
        dying:removeFromSquare()
        dying:removeFromWorld()
    end)
    Bridge.body = nil
    Bridge.kind = nil
    Bridge.hiddenSince = nil
    Bridge.holdPos = nil
    Bridge.walkTypeSet = nil
    Bridge.follow = false
    Bridge.mode = "follow"
    if Bridge.despawnByCommand then Bridge.parked = false end
    Bridge.pose = nil
    Bridge.target = nil
    BridgeMove.reset(nil)
    BridgeFight.reset(nil)
    if not ok then return "despawn with errors: " .. tostring(err) end
    return "despawned"
end





function Bridge.goneCheck()
    if not Bridge.alive() or Bridge.kind ~= "zombie" or Bridge.mp then
        Bridge.goneChecks = nil
        return "not driven"
    end
    if Bridge.goneBody ~= Bridge.body then
        Bridge.goneBody = Bridge.body
        Bridge.goneChecks = nil
        Bridge.goneFarLogged = nil
    end
    local inList, square = true, nil
    pcall(function() inList = getCell():getZombieList():contains(Bridge.body) end)
    pcall(function() square = Bridge.body:getCurrentSquare() end)
    if inList then
        Bridge.goneChecks = nil
        if square == nil then log("body in cell list without a square") end

        if Bridge.spawnBackoff ~= nil and Bridge.createdTime ~= nil and Bridge.time - Bridge.createdTime > BACKOFF_RESET then
            Bridge.spawnBackoff = nil
        end
        return "in world"
    end
    log(string.format("body not in world: inCellList=false square=%s", tostring(square ~= nil)))
    Bridge.goneChecks = (Bridge.goneChecks or 0) + 1




    if Bridge.goneChecks >= 2 and (Bridge.hiddenSince == nil or Bridge.tick - Bridge.hiddenSince > 180) then
        return Bridge.bodyGone()
    end
    return "not in list"
end






function Bridge.bodyGone()
    local gone = Bridge.body
    if gone == nil then return "no body" end
    local near = false
    pcall(function()
        local red = BridgeData.owner()
        if red == nil or red:getVehicle() ~= nil then return end
        local dx, dy = gone:getX() - red:getX(), gone:getY() - red:getY()
        near = dx * dx + dy * dy <= 30 * 30
    end)
    if not near then
        if not Bridge.goneFarLogged then
            Bridge.goneFarLogged = true
            log("body not in world, player far or in a vehicle: left to the population path")
        end
        Bridge.goneChecks = nil
        return "far"
    end




    local fresh = nil
    pcall(function() fresh = BridgeInventory.encode(BridgeInventory.snapshot(gone)) end)
    local saved = nil
    pcall(function() saved = outfitStore().items end)
    if fresh ~= nil and fresh == "" and saved ~= nil and saved ~= "" then
        log("body was stripped before removal: keeping the last saved outfit")
    else
        pcall(function() Bridge.saveOutfit(fresh) end)
    end

    pcall(function() BridgeHeal.stop("body gone") end)
    pcall(function() BridgeWash.stop("body gone") end)
    pcall(function() Bridge.restoreRed() end)

    pcall(function() Bridge.unhumanize(gone, true) end)
    Bridge.body = nil
    Bridge.kind = nil
    Bridge.hiddenSince = nil
    Bridge.holdPos = nil
    Bridge.walkTypeSet = nil
    Bridge.pose = nil
    Bridge.target = nil
    Bridge.goneChecks = nil
    pcall(function() BridgeMove.reset(nil) end)
    pcall(function() BridgeFight.reset(nil) end)


    local age = Bridge.createdTime ~= nil and (Bridge.time - Bridge.createdTime) or nil
    Bridge.createdTime = nil
    if age ~= nil and age < GONE_SOON then
        Bridge.spawnBackoff = math.min((Bridge.spawnBackoff or (BACKOFF_FIRST / 2)) * 2, BACKOFF_MAX)
        Bridge.startTick = Bridge.time
        log(string.format("body removed %.1f s after creation: something clears zombies here, next attempt in %d s",
            age / 60, math.floor((APPEAR_DELAY + Bridge.spawnBackoff) / 60)))
    end
    log("body removed by another mod: she comes back from the saved outfit")
    return "gone"
end




function Bridge.teleportToRed(prefer)
    local red = BridgeData.owner()
    if red == nil then return "no player" end
    if not Bridge.drivable() then return "no body or driven by another client" end
    Bridge.pose = nil



    local square = nil
    if prefer ~= nil and standSquareOk(prefer) then square = prefer end
    if square == nil then pcall(function()
        local cell = getCell()
        local rx, ry, rz = math.floor(red:getX()), math.floor(red:getY()), math.floor(red:getZ())
        local redSq = cell:getGridSquare(rx, ry, rz)

        pcall(function()
            local zones = BridgeMove.seatZones(red)
            if zones == nil then return end
            local spot = BridgeMove.seatSpot(red, zones, red:getX(), red:getY(), nil, nil)
            if spot ~= nil then
                square = cell:getGridSquare(spot.x, spot.y, zones.z)
                log(string.format("teleport: player %s, to %d,%d (ring %d)", zones.why, spot.x, spot.y, spot.ring))
            end
        end)
        local spots = { {1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {1, -1}, {-1, 1} }
        for i = 1, square == nil and #spots or 0 do
            local sq = cell:getGridSquare(rx + spots[i][1], ry + spots[i][2], rz)

            if standSquareOk(sq, redSq) then square = sq break end
        end
        if square == nil then square = cell:getGridSquare(rx, ry, rz) end
    end) end
    if square == nil then return "teleport failed: no square near player" end

    local x, y = square:getX() + 0.5, square:getY() + 0.5
    local moved = pcall(function()
        Bridge.body:setX(x)
        Bridge.body:setY(y)
        Bridge.body:setZ(square:getZ())
    end)
    pcall(function() Bridge.body:setLastX(x) end)
    pcall(function() Bridge.body:setLastY(y) end)
    local attached = pcall(function() Bridge.body:setCurrent(square) end)
    if not attached then
        pcall(function() Bridge.body:setCurrentSquareFromPosition() end)
    end


    BridgeMove.reset(Bridge.body)
    BridgeFight.reset(Bridge.body)
    Bridge.holdPos = nil

    if not moved then return "teleport failed: cannot set position" end
    Bridge.result = "teleported to player"
    log("teleported to player")
    return "teleported"
end




function Bridge.setMode(mode)
    if mode == "waitcar" then mode = "wait" end
    if not BridgeData.MODES[mode] then return "unknown mode " .. tostring(mode) end

    Bridge.newLifePending = nil
    Bridge.mode = mode
    Bridge.follow = (mode == "follow")
    Bridge.target = nil
    BridgeMove.moving = false
    BridgeFight.guardOnly = (mode ~= "follow")
    if Bridge.alive() then BridgeMove.stopPath(Bridge.body) end
    local wx, wy, wz = nil, nil, nil

    local seated = Bridge.pose ~= nil and Bridge.pose.seat == true
    if mode == "follow" then

        if not seated then Bridge.pose = nil end
    else
        local b = Bridge.alive() and Bridge.body or BridgeData.owner()
        if b ~= nil then wx, wy, wz = b:getX(), b:getY(), b:getZ() end


        pcall(function()
            local c = BridgeMove.seat and BridgeMove.seat.chair
            if seated and c ~= nil then wx, wy = c.ax, c.ay end
        end)
        Bridge.pose = (mode == "rest") and { anim = "Sit" } or nil
    end
    local st = Bridge.store


    local wasLeft = st ~= nil and st.left == true
    if st ~= nil then
        st.mode = mode
        st.waitX, st.waitY, st.waitZ = wx, wy, wz
        st.left = nil
    end
    if BridgeCar ~= nil then BridgeCar.leftLocal = nil end
    if Bridge.mp then
        pcall(function()
            local args = { mode = mode }
            if wx ~= nil then args.waitX, args.waitY, args.waitZ = wx, wy, wz else args.clearWait = true end
            if wasLeft then args.left = false end
            sendClientCommand(BridgeData.owner(), "Bridge", "state", args)
        end)
    end
    return "mode=" .. mode
end



function Bridge.setKeep(side)
    if not BridgeData.keepAllowed(side) then return "unknown side " .. tostring(side) end
    local st = Bridge.store
    if st ~= nil then st.keep = side end
    pcall(function() BridgeMove.spotReset() end)
    if Bridge.mp then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { keep = side }) end)
    end
    return "keep=" .. side
end


function Bridge.setFar(far)
    far = far == true
    local st = Bridge.store
    if st ~= nil then st.far = far end
    pcall(function() BridgeMove.spotReset() end)
    if Bridge.mp then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { far = far }) end)
    end
    return "far=" .. tostring(far)
end


function Bridge.applyStoredMode()
    local mode = BridgeData.modeOf(Bridge.store)
    Bridge.mode = mode
    Bridge.follow = (mode == "follow")
    BridgeFight.guardOnly = (mode ~= "follow")
    Bridge.pose = (mode == "rest") and { anim = "Sit" } or nil
end



function Bridge.speak(key, a, b)
    local text = key
    pcall(function()
        if b ~= nil then text = getText("IGUI_NotAlone_Say_" .. key, a, b)
        elseif a ~= nil then text = getText("IGUI_NotAlone_Say_" .. key, a)
        else text = getText("IGUI_NotAlone_Say_" .. key) end
    end)
    return Bridge.speakText(text)
end





local EVENTS_FILE = "bridge/events.txt"
Bridge.muteLines = false
Bridge.quietLines = false

function Bridge.quiet()
    return Bridge.muteLines == true or Bridge.quietLines == true
end


function Bridge.bridgeEvent(kind, text)
    if not Bridge.bridgeOn then return end
    pcall(function()
        local w = getFileWriter(EVENTS_FILE, true, true)
        w:write(string.format("%d %s %s\r\n", Bridge.tick, tostring(kind), BridgeChat.toHex(tostring(text or ""))))
        w:close()
    end)
end




function Bridge.carLine(text)
    local red = BridgeData.owner()
    if BridgeCar == nil or red == nil or not BridgeCar.withRed(red) then return false end
    local name = tostring(Bridge.companionName())
    if not BridgeData.overheadOk(name) then name = BridgeData.DEFAULT_NAME end
    local line = name .. ": " .. tostring(text)
    if not BridgeData.overheadOk(line) then return false end
    return (pcall(function() red:addLineChatElement(line, 0.95, 0.55, 0.75) end))
end


function Bridge.speakText(text)


    pcall(function() log("line hex:" .. BridgeChat.toHex(tostring(text))) end)


    local inCar = BridgeCar ~= nil and BridgeCar.withRed(BridgeData.owner())
        and (not Bridge.alive() or BridgeCar.holdHidden())
    if inCar then
        Bridge.carLine(text)
    elseif Bridge.alive() and BridgeData.overheadOk(text) then
        pcall(function() Bridge.body:addLineChatElement(text, 0.95, 0.55, 0.75) end)
        if BridgeName ~= nil then BridgeName.spoke(Bridge.body) end
    end
    if Bridge.mp then

        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "say", { text = text, chat = false, car = inCar or nil }) end)
    end
    return text
end


function Bridge.setName(text)
    local name = BridgeData.cleanName(text)
    if Bridge.store ~= nil then Bridge.store.name = name end
    if Bridge.mp then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { name = name or "" }) end)
    end
    return "name=" .. tostring(BridgeData.nameOf(Bridge.store))
end


function Bridge.setOption(key, value)
    if BridgeData.OPTIONS[key] == nil then return "no such option: " .. tostring(key) end
    value = value == true
    if Bridge.store ~= nil then Bridge.store[key] = value end
    if Bridge.mp then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { [key] = value }) end)
    end

    if key == "redKit" and BridgeHeal ~= nil then BridgeHeal.emptySig = nil end
    log("option " .. tostring(key) .. "=" .. tostring(value))
    return tostring(key) .. "=" .. tostring(value)
end


function Bridge.setHair(style)
    local hair = BridgeData.cleanHair(style)
    if hair == nil then return "bad hair: " .. tostring(style) end
    if Bridge.store ~= nil then Bridge.store.hair = hair end
    if Bridge.mp then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { hair = hair }) end)
    end
    if Bridge.alive() and Bridge.kind == "zombie" then
        pcall(function()
            BridgeInventory.skin(Bridge.body, Bridge.store)
            Bridge.body:resetModelNextFrame()
            Bridge.body:resetModel()
        end)
    end
    log("hair=" .. hair)
    return "hair=" .. hair
end

local function setWant(want)
    if Bridge.store ~= nil then Bridge.store.want = want end
    if Bridge.mp then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { want = want }) end)
    end
end


function Bridge.call()
    log("call: " .. (Bridge.alive() and "already here" or "spawning"))
    setWant(true)
    Bridge.leaveAt = nil
    Bridge.homeParked = false
    Bridge.respawnAt = nil
    Bridge.setMode("follow")
    if Bridge.alive() then return "already here" end


    local inCar = false
    pcall(function() inCar = BridgeData.owner():getVehicle() ~= nil end)
    if inCar then
        Bridge.greetOnReveal = nil
        local okIn, marked = pcall(function() return BridgeCar.markInside(BridgeData.owner(), "called from the car") end)
        if okIn and marked then return "in his car" end
    end
    return Bridge.spawnZombie()
end



function Bridge.goodbye()
    log("goodbye: " .. (Bridge.alive() and "leaving" or "not here"))
    setWant(false)
    Bridge.respawnAt = nil
    Bridge.homeParked = false
    if not Bridge.alive() then return "not here" end
    Bridge.speak("Goodbye")
    Bridge.leaveAt = Bridge.time + 120
    return "leaving"
end


function Bridge.setPose(anim, seconds)
    if anim == nil then
        Bridge.pose = nil
        return "pose=none"
    end
    Bridge.pose = { anim = anim, untilTick = seconds and (Bridge.time + seconds * 60) or nil }
    if Bridge.alive() then
        BridgeMove.stopPath(Bridge.body)
        pcall(function() Bridge.body:setBumpType(anim) end)
    end
    return "pose=" .. anim .. (seconds and (" for " .. tostring(seconds) .. "s") or "")
end

function Bridge.say(text)
    local said = "none"
    if BridgeCar ~= nil and BridgeCar.holdHidden() and Bridge.carLine(text) then

        said = "car"
    elseif Bridge.alive() and not BridgeData.overheadOk(text) then

        said = "chat only"
    elseif Bridge.alive() then
        local ok = pcall(function() Bridge.body:addLineChatElement(text, 0.95, 0.55, 0.75) end)
        if BridgeName ~= nil then BridgeName.spoke(Bridge.body) end
        if ok then
            said = "line"
        else
            local ok2 = pcall(function() Bridge.body:Say(text) end)
            said = ok2 and "say" or "failed"
        end
    elseif Bridge.carLine(text) then
        said = "car"
    end
    local inChat = false
    if BridgeChat ~= nil and BridgeChat.sayCompanion ~= nil then
        inChat = BridgeChat.sayCompanion(text)
    end
    return "say body=" .. said .. " chat=" .. tostring(inChat)
end








function Bridge.alife(parts)
    local red = BridgeData.owner()
    if red == nil then return "alife: no player" end

    if type(ProjectALife) ~= "table" then return "alife: Project A-Life not active" end
    local kind = parts[3]
    local x, y, z = math.floor(red:getX()), math.floor(red:getY()), math.floor(red:getZ())
    local function stanceArgs(args, stance)
        if stance ~= nil and stance ~= "" then
            args.playerStance = stance
            if stance == "friendly" or stance == "hostile" then args.hostileOverride = stance end
        end
        return args
    end
    local function send(command, args)


        if type(ProjectALife.MenuRules) == "table" and type(ProjectALife.MenuRules.apply) == "function" then
            pcall(function() ProjectALife.MenuRules.apply(red) end)
        end
        pcall(function()
            local service = ProjectALife.DebugService
            if service ~= nil and type(service.setDiagnostics) == "function" and not isClient() then
                service.setDiagnostics(red, true)
            end
        end)


        sendClientCommand(red, "ProjectALife", command, args)
        log("alife " .. command .. " " .. tostring(kind) .. " at " .. x .. "," .. y)
        return "alife " .. command .. " sent"
    end
    if kind == "squad" then
        local d = tonumber(parts[6]) or 4
        return send("debugSpawn", stanceArgs({ mode = "roam", animation = "normal", placementMode = "here",
            arrival = "foot", count = tonumber(parts[5]) or 2, x = x + d, y = y, z = z,
            requestId = "swm" .. tostring(parts[1]) }, parts[4]))
    elseif kind == "encounter" then
        return send("debugSpawnCatalog", stanceArgs({ encounterId = parts[4], animation = "normal",
            placementMode = "here", arrival = "foot", count = tonumber(parts[6]) or 0,
            x = x + 4, y = y, z = z, requestId = "swm" .. tostring(parts[1]) }, parts[5]))
    elseif kind == "outpost" then

        local args = stanceArgs({ presetId = parts[4], persistent = false, mode = "guard",
            animation = "normal", placementMode = "here", arrival = "foot", x = x, y = y, z = z,
            requestId = "swm" .. tostring(parts[1]) }, parts[5])
        if parts[6] ~= nil and parts[6] ~= "" then args.factionId = parts[6] end
        return send("debugBuildOutpost", args)
    elseif kind == "clear" then
        return send("debugPurgeActors", { radius = tonumber(parts[4]) or 40, x = x, y = y })
    end
    return "alife: squad|encounter|outpost|clear"
end


Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "ProjectALife" or type(command) ~= "string" then return end
    if string.find(command, "Result", 1, true) == nil then return end
    pcall(function()
        local parts = {}
        for k, v in pairs(type(args) == "table" and args or {}) do
            if type(v) ~= "table" then parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
        end
        table.sort(parts)
        log("alife reply " .. command .. ": " .. table.concat(parts, " "))
    end)
end)















local ZOMBIE_VOICES = {
    "FemaleZombieVoiceA", "FemaleZombieVoiceB", "FemaleZombieVoiceC",
    "MaleZombieVoiceA", "MaleZombieVoiceB", "MaleZombieVoiceC",
}


local function muteZombieVoice(body)
    local emitter = body:getEmitter()
    if emitter == nil then return end
    for i = 1, #ZOMBIE_VOICES do
        emitter:stopSoundByName(ZOMBIE_VOICES[i])
    end
end


function Bridge.voice(name)
    if not Bridge.alive() then return "no body" end
    return BridgeSound.voice(Bridge.body, name, 20)
end




Bridge.swingSpy = nil
function Bridge.spySwing(owner, weapon)
    if not Bridge.verbose or owner == nil or owner ~= BridgeData.owner() then return end
    local b = Bridge.body
    if b == nil then return end
    local d = 99
    pcall(function() d = math.sqrt((b:getX() - owner:getX()) ^ 2 + (b:getY() - owner:getY()) ^ 2) end)
    if d > 3 then return end
    local w = "hands"
    pcall(function() if weapon ~= nil then w = weapon:getType() end end)
    Bridge.swingSpy = { t = Bridge.time, dHer = d, weapon = w, hits = {}, her = false }
end

function Bridge.spyHit(zombie, attacker, isBody)
    local spy = Bridge.swingSpy
    if spy == nil or attacker ~= BridgeData.owner() then return end
    if isBody then spy.her = true return end
    local rec = { z = zombie, hp = nil, d = 99 }
    pcall(function() rec.hp = zombie:getHealth() end)
    pcall(function()
        local b = Bridge.body
        rec.d = math.sqrt((zombie:getX() - b:getX()) ^ 2 + (zombie:getY() - b:getY()) ^ 2)
    end)
    spy.hits[#spy.hits + 1] = rec
end


function Bridge.spyTick()
    local spy = Bridge.swingSpy
    if spy == nil or Bridge.time - spy.t < 30 then return end
    Bridge.swingSpy = nil
    local parts = {}
    for _, h in ipairs(spy.hits) do
        local now = nil
        pcall(function() now = h.z:getHealth() end)
        parts[#parts + 1] = string.format("zombie %.1f from her hp %.2f->%s", h.d, h.hp or -1,
            now and string.format("%.2f", now) or "?")
    end
    local her = "?"
    pcall(function() her = tostring(Bridge.body and Bridge.body:isShootable()) end)
    vlog(string.format("player swing %s, her %.1f away: %s%s (her shootable now %s)", spy.weapon, spy.dHer,
        #parts > 0 and table.concat(parts, "; ") or "no zombie hit",
        spy.her and ", HER BODY HIT" or "", her))
end






function Bridge.onHitZombie(zombie, attacker, bodyPart, weapon)
    local ok, isBody = pcall(function() return zombie:getVariableBoolean(BODY_VAR) end)
    if ok then pcall(function() Bridge.spyHit(zombie, attacker, isBody and not reusedBody(zombie)) end) end
    if not ok or not isBody or reusedBody(zombie) then return end
    pcall(function() zombie:setAvoidDamage(true) end)
    if instanceof(attacker, "IsoPlayer") then
        local hp = nil
        pcall(function() hp = zombie:getHealth() end)
        if hp ~= nil then Bridge.hitRestore = { z = zombie, hp = hp, tick = Bridge.tick } end
        pcall(function()
            local w = attacker:getPrimaryHandItem()
            local ranged = w ~= nil and w:isRanged()
            log("hit: ranged=" .. tostring(ranged) .. " shootable=" .. tostring(zombie:isShootable()))
        end)




        if not Bridge.mortal then

            if zombie == Bridge.body then Bridge.hitClean = { tick = Bridge.tick } else Bridge.copyHit[zombie] = Bridge.time end
        end
        log("body hit by player " .. tostring(attacker:getUsername()))


        if zombie == Bridge.body and attacker == BridgeData.owner() and BridgeData.optionOf(Bridge.store, "hitMatters")
            and (Bridge.time - (Bridge.hitDeedTick or -999)) > 60 then
            Bridge.hitDeedTick = Bridge.time
            pcall(function() BridgeSocial.deed("hit") end)
        end
        return
    end

    if zombie == Bridge.body then Bridge.voice("PainFromHitBlunt") end
end






function Bridge.protectBodies()
    local b = Bridge.body
    if b ~= nil and Bridge.kind == "zombie" then pcall(function() b:setShootable(false) end) end
    for z in pairs(Bridge.seen) do
        if z ~= b then pcall(function() z:setShootable(false) end) end
    end
end


function Bridge.keepHealth(body)
    local hp, dead = nil, false
    pcall(function() hp = body:getHealth() end)
    pcall(function() dead = body:isDead() or body:isOnKillDone() end)
    if hp == nil or dead or hp >= 1 then return false end
    pcall(function() body:setHealth(1) end)
    if hp <= 0 or Bridge.time - (Bridge.hpLogAt or -99999) >= 600 then
        Bridge.hpLogAt = Bridge.time
        log(string.format("health %.2f set by something else, back to 1", hp))
    end
    return true
end



Bridge.corpseWatch = nil
function Bridge.corpseSweep()
    local w = Bridge.corpseWatch
    if w == nil then return end
    if Bridge.time > w.untilT then Bridge.corpseWatch = nil return end
    local cell = getCell()
    if cell == nil then return end
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = cell:getGridSquare(w.x + dx, w.y + dy, w.z)
            if sq ~= nil then
                local list = sq:getDeadBodys()
                for i = (list and list:size() or 0) - 1, 0, -1 do
                    local c = list:get(i)
                    local hers = false
                    pcall(function()
                        hers = c:isZombie() and c:isFemale() and c:getHumanVisual():getSkinTexture() == "FemaleBody01"
                            and tostring(c:getOutfitName()) == "Naked"
                    end)
                    if hers then
                        pcall(function() sq:removeCorpse(c, false) end)
                        log(string.format("her corpse removed at %d,%d", w.x + dx, w.y + dy))
                    end
                end
            end
        end
    end
end











function Bridge.onZombieDead(zombie)
    local ok, isBody = pcall(function() return zombie:getVariableBoolean(BODY_VAR) end)
    if not ok or not isBody or reusedBody(zombie) then return end


    pcall(function()
        local by = zombie:getAttackedBy()
        local who = "nil"
        if by ~= nil then
            who = instanceof(by, "IsoPlayer") and "player" or (instanceof(by, "IsoZombie") and "zombie" or "other")
        end
        local uid = nil


        if by ~= nil then pcall(function() uid = by:getModData().ProjectALifeUID end) end
        log(string.format("body killed: attacker=%s alife=%s health=%.2f", who, tostring(uid), zombie:getHealth()))
    end)

    pcall(function() if zombie:isSittingOnFurniture() then zombie:setSittingOnFurniture(false) end end)
    if zombie == Bridge.body then BridgeMove.seatFlag = false end
    pcall(function() zombie:getEmitter():playSound("VoiceFemaleDeathAlone") end)
    if Bridge.mp then
        pcall(function() zombie:setPrimaryHandItem(nil) end)
        pcall(function() zombie:setSecondaryHandItem(nil) end)
        pcall(function() zombie:clearItemsToSpawnAtDeath() end)
        pcall(function()
            local inv = zombie:getInventory()
            local items = inv:getItems()
            for i = items:size() - 1, 0, -1 do
                local item = items:get(i)
                if item ~= nil and not zombie:isEquippedClothing(item) then inv:Remove(item) end
            end
        end)
    elseif zombie == Bridge.body then





        local n = 0
        pcall(function() n = #BridgeInventory.decode(Bridge.store.items or "") end)
        log("body died: snapshot kept, " .. tostring(n) .. " items come back with her")
        Bridge.wornTypes = nil


        pcall(function() zombie:setPrimaryHandItem(nil) end)
        pcall(function() zombie:setSecondaryHandItem(nil) end)
        pcall(function() zombie:getWornItems():clear() end)
        pcall(function() zombie:getItemVisuals():clear() end)
        pcall(function() zombie:clearAttachedItems() end)
        pcall(function() zombie:clearItemsToSpawnAtDeath() end)
        pcall(function() zombie:getInventory():clear() end)
        pcall(function()
            Bridge.corpseWatch = { x = math.floor(zombie:getX()), y = math.floor(zombie:getY()), z = math.floor(zombie:getZ()),
                                   untilT = Bridge.time + 300 }
        end)
    end
    Bridge.seen[zombie] = nil
    local id = nil
    pcall(function() id = zombie:getPersistentOutfitID() end)
    if Bridge.mp then


        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "died", { id = id }) end)
    end
    local mine = (zombie == Bridge.body) or (Bridge.mp and Bridge.store ~= nil and id ~= nil and id == Bridge.store.bodyId)
    if not mine then return end
    Bridge.restoreRed()
    pcall(function() BridgeHeal.stop("body died") end)
    pcall(function() BridgeWash.stop("body died") end)
    Bridge.body = nil
    Bridge.kind = nil
    Bridge.hiddenSince = nil
    Bridge.holdPos = nil
    Bridge.walkTypeSet = nil
    Bridge.pose = nil
    Bridge.target = nil
    BridgeMove.reset(nil)
    BridgeFight.reset(nil)
    Bridge.groundTicks = 0
    Bridge.hitRestore = nil
    Bridge.respawnAt = Bridge.time + 600
    Bridge.result = "body died, back in 10 s"

    pcall(function() BridgeBandits.forgetCorpse(zombie:getX(), zombie:getY(), zombie:getZ()) end)

    pcall(function() BridgeInventory.forgetBody(zombie) end)


    pcall(function()
        zombie:removeFromWorld()
        zombie:removeFromSquare()
    end)
    log("body died, corpse removed")
end






local ENGINE_STATES = { "climbfence", "climbwindow", "getup", "onground", "staggerback", "hitreaction", "falldown",
                        "knockeddown", "falling", "sitting" }
local function engineState(asn)
    if asn == nil then return false end
    for _, name in ipairs(ENGINE_STATES) do
        if string.sub(asn, 1, #name) == name then return true end
    end
    return false
end




local function traceState(body)
    if Bridge.tick >= BridgeMove.traceUntil then return end
    local asn, bump, alerted, flag, bumped = "?", "?", "?", "?", "?"
    pcall(function() asn = tostring(body:getActionStateName()) end)
    pcall(function() bump = tostring(body:getBumpType()) end)

    pcall(function() alerted = tostring(body:getVariableBoolean("alerted")) end)
    pcall(function() bumped = tostring(body:getVariableBoolean("bumped")) end)
    pcall(function() flag = tostring(body:isReanimatedForGrappleOnly()) end)
    local fin, moving, pf = "?", "?", "?"
    pcall(function() fin = tostring(body:getVariableBoolean("BumpAnimFinished")) end)
    pcall(function() moving = tostring(body:getVariableBoolean("bMoving")) end)
    pcall(function() pf = tostring(body:getVariableBoolean("bPathfind")) end)
    log(string.format("state t=%d asn=%s bump=%s bumped=%s fin=%s moving=%s pathfind=%s alerted=%s flag=%s hidden=%s x=%.2f y=%.2f",
        Bridge.tick, asn, bump, bumped, fin, moving, pf, alerted, flag, tostring(Bridge.hiddenSince ~= nil), body:getX(), body:getY()))
end




local function handProbe(body, where)
    if not Bridge.verbose then return end
    pcall(function()
        local now = body:getPrimaryHandItem()
        local was = Bridge.handSeen
        if now ~= was then
            if Bridge.handSeenSet then
                local keys = {}
                local data = body:getModData()
                if type(data) == "table" then
                    for k, _ in pairs(data) do
                        if string.find(tostring(k), "ALife", 1, true) ~= nil then keys[#keys + 1] = tostring(k) end
                    end
                end
                table.sort(keys)
                vlog(string.format("hand changed at %s: %s -> %s state=%s bump=%s fight=%s alife=[%s]", where,
                    was and tostring(was:getType()) or "nil", now and tostring(now:getType()) or "nil",
                    tostring(body:getActionStateName()), tostring(body:getBumpType()),
                    tostring(BridgeFight.state), table.concat(keys, ",")))
            end
            Bridge.handSeen = now
        end
        Bridge.handSeenSet = true
    end)
end





local LOOK_ONCE = {}
for _, n in ipairs({ "BandageHead", "BandageLeftArm", "BandageLeftLeg", "BandageLowerBody", "BandageRightArm",
    "BandageRightLeg", "BandageUpperBody", "ChewNails", "EmoteClap", "EmoteComeHere", "EmoteNo", "EmoteNoThankYou",
    "EmoteShrug", "EmoteThankYou", "EmoteUndecided", "EmoteWaveHi", "EmoteYes", "PainHead", "PullAtCollar",
    "ShiftWeight", "TreatHigh", "TreatLow", "TreatMid", "WeaponAttachBack", "WeaponAttachBeltLeft",
    "WeaponAttachBeltRight", "WeaponDetachBack", "WeaponDetachBeltLeft", "WeaponDetachBeltRight", "WipeBrow",
    "WipeHead", "WindowOpen" }) do LOOK_ONCE[n] = true end
function Bridge.isLookOnce(name) return type(name) == "string" and LOOK_ONCE[name] == true end


local function lookShare(body)
    if not Bridge.mp then return end
    local b = ""
    pcall(function() b = tostring(body:getBumpType()) end)
    if b == Bridge.lookSent then return end
    Bridge.lookSent = b
    if LOOK_ONCE[b] then pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "look", { a = b }) end) end
end
Bridge.lookShare = lookShare

local function updateZombieBody(body)
    Bridge.zombieTicks = Bridge.zombieTicks + 1
    Bridge.keepHidden(body)

    local okGuard, errGuard = pcall(Bridge.guardOutfit, body)
    if not okGuard then warn("guardOutfit failed: " .. tostring(errGuard)) end


    if not Bridge.mp and not Bridge.mortal then pcall(Bridge.keepHealth, body) end
    lookShare(body)


    pcall(function() BridgeInventory.gestureGuard(body) end)
    handProbe(body, "frame start")

    if Bridge.verbose and Bridge.every(60, 40) then
        pcall(function()
            local keys = {}
            local data = body:getModData()
            if type(data) == "table" then
                for k, _ in pairs(data) do
                    if string.find(tostring(k), "ALife", 1, true) ~= nil then keys[#keys + 1] = tostring(k) end
                end
            end
            table.sort(keys)
            local text = table.concat(keys, ",")
            if text ~= (Bridge.alifeMarks or "") then
                vlog("alife marks on body: [" .. text .. "] state=" .. tostring(body:getActionStateName()))
                Bridge.alifeMarks = text
            end
        end)
    end
    traceState(body)

    pcall(function() body:setShootable(false) end)


    pcall(function()
        if body:isBecomeCrawler() then body:setBecomeCrawler(false) end
        if body:isCrawling() then
            body:setCrawler(false)
            body:setCanWalk(true)
        end
        if body:isFakeDead() then body:setFakeDead(false) end
    end)
    local hr = Bridge.hitRestore
    if hr ~= nil then
        Bridge.hitRestore = nil
        if hr.z == body and (Bridge.tick - hr.tick) <= 3 then
            pcall(function()
                if not body:isOnKillDone() and not body:isDead() and body:getHealth() < hr.hp then
                    body:setHealth(hr.hp)
                    log("body health restored after player hit")
                end
            end)
        end
    end
    body:setUseless(true)



    pcall(function() if not body:isNoTeeth() then body:setNoTeeth(true) end end)




    pcall(function()
        local fixed = nil
        if not body:isPersistentOutfitInit() then
            body:setPersistentOutfitID(body:getPersistentOutfitID(), true)
            fixed = "outfit init"
        end
        if body:shouldDressInRandomOutfit() then
            body:setDressInRandomOutfit(false)
            fixed = (fixed and (fixed .. ", ") or "") .. "random outfit"
        end
        if fixed ~= nil and Bridge.time - (Bridge.outfitFixLogAt or -99999) >= 600 then
            Bridge.outfitFixLogAt = Bridge.time
            log("her body was set to be re-dressed (" .. fixed .. "), kept hers: another mod?")
        end
    end)
    body:setTarget(nil)




    pcall(function()
        body:setBodyToEat(nil)
        if body:getEatBodyTarget() ~= nil then body:setEatBodyTarget(nil, false) end
    end)

    if not Bridge.mortal then pcall(function() body:setAvoidDamage(true) end) end
    Bridge.noFire(body)


    if Bridge.hitClean ~= nil and not Bridge.mortal then
        local age = Bridge.tick - Bridge.hitClean.tick


        if age <= 60 then
            Bridge.clearHitMarks(body)
            if age == 3 or age == 20 or age == 60 then
                pcall(function() body:resetModelNextFrame() end)
                pcall(function() BridgeInventory.redress(body) end)
            end
        else
            Bridge.hitClean = nil
        end
    end



    pcall(function()
        if body:getEatBodyTarget() ~= nil then body:setEatBodyTarget(nil, false) end
        if body:isFakeDead() then body:setFakeDead(false) end
        if body:isForceFakeDead() then body:setForceFakeDead(false) end
        if body:isBecomeCrawler() then body:setBecomeCrawler(false) end
        if body:isCrawling() then body:setCrawler(false) end
    end)
    if Bridge.zombieTicks % 15 == 0 then Bridge.weaponVar(body) end
    do
        local red, sneak = BridgeData.owner(), false
        pcall(function() sneak = Bridge.follow == true and red ~= nil and red:isSneaking() end)
        Bridge.sneakVar(body, sneak == true)
        pcall(function() Bridge.sneakTrace(body, red, sneak == true) end)
    end
    body:setWalkType(BridgeMove.walkType)
    if BridgeMove.walkType ~= Bridge.walkTypeSet then


        Bridge.walkTypeSet = BridgeMove.walkType
        pcall(function() body:setSpeedTypeFromWalkType() end)
        pcall(function() body:setVariable("WalkSpeed", (BridgeMove.walkType == "SlowWalk") and 0.75 or 1.0) end)
    end
    body:setSpeedMod((BridgeMove.moving and Bridge.follow) and BridgeMove.speed or 1)


    if BridgeMove.tallFence then
        local bump, asn0 = "", ""
        pcall(function() bump = tostring(body:getBumpType()) end)
        pcall(function() asn0 = tostring(body:getActionStateName()) end)
        if bump ~= "ClimbFenceTall" and asn0 ~= "climbfence" then
            pcall(function() body:setCollidable(true) end)
            BridgeMove.tallFence = false
        end
    end




    if Bridge.hiddenSince ~= nil and not (BridgeCar ~= nil and BridgeCar.holdHidden()) then
        local age = Bridge.tick - Bridge.hiddenSince
        local okReady, ready, why = pcall(Bridge.showReady, body)
        if not okReady then ready, why = age >= 90, "showReady failed: " .. tostring(ready) end
        if ready then
            Bridge.hideBody(body, false)
            Bridge.hiddenSince = nil
            log("body revealed after " .. tostring(age) .. " ticks, " .. tostring(why))
            if Bridge.greetOnReveal then
                Bridge.greetOnReveal = nil
                Bridge.speak("Hello")
            end
        end
    end
    pcall(function() body:setAnimatingBackwards(false) end)
    pcall(function() muteZombieVoice(body) end)



    do
        local fewer = false
        pcall(function() fewer = body:getItemVisuals():size() < body:getWornItems():size() end)
        if fewer then
            local okFell, fell = pcall(function() return BridgeInventory.dropFallen(body) end)
            if okFell and fell ~= nil and #fell > 0 then
                Bridge.wornSeen = nil
            elseif not okFell then
                warn("dropFallen failed: " .. tostring(fell))
            end
        end
    end




    local modelBusy = false
    pcall(function() modelBusy = BridgeInventory.modelBusy(body) end)
    if Bridge.time < BridgeInventory.redressUntil and Bridge.zombieTicks % 30 == 0 and not modelBusy then
        pcall(function()
            BridgeInventory.applyWorn(body)
            body:resetModelNextFrame()
            body:resetModel()
        end)
    end




    if Bridge.zombieTicks % 30 == 15 then
        local ok, now = pcall(function() return BridgeInventory.wornList(body) end)


        local lost = false
        pcall(function() lost = body:getItemVisuals():size() < body:getWornItems():size() end)
        if lost and not modelBusy then Bridge.wornSeen = nil end
        if ok and now ~= Bridge.wornSeen and not modelBusy then
            Bridge.wornSeen = now
            pcall(function()
                BridgeInventory.applyWorn(body)
                body:resetModelNextFrame()
                body:resetModel()
            end)
        end


        handProbe(body, "before dropGone")
        local okGone, gone = pcall(function() return BridgeInventory.dropGone(body) end)
        handProbe(body, "dropGone")
        if okGone and gone and not modelBusy then
            pcall(function()
                BridgeInventory.applyWorn(body)
                body:resetModelNextFrame()
                body:resetModel()
            end)
        end





        local okSnap, list = pcall(function() return BridgeInventory.snapshot(body) end)
        if okSnap then
            local sign = BridgeItems.signature(list)
            if sign ~= Bridge.itemsSign then
                Bridge.itemsSign = sign
                Bridge.saveOutfit(BridgeInventory.encode(list))




            elseif (Bridge.time - (Bridge.itemsSavedTick or 0)) > (Bridge.mp and 3600 or 300) then
                local full = BridgeInventory.encode(list)
                if full ~= Bridge.itemsSeen then Bridge.saveOutfit(full) end
            end
        end
    end



    do
        local px, py = body:getX(), body:getY()
        if Bridge.enginePos ~= nil then
            local dx = px - Bridge.enginePos[1]
            local dy = py - Bridge.enginePos[2]
            local step = math.sqrt(dx * dx + dy * dy)
            if step < 1 and not BridgeMove.pathing and not BridgeMove.moving then
                Bridge.engineAcc = Bridge.engineAcc + step
            end
        end
        Bridge.enginePos = { px, py }
    end




    if body:getVehicle() ~= nil then
        Bridge.holdPos = nil
        BridgeMove.pathing = false
        BridgeMove.moving = false
        pcall(function()
            local pf = body:getPathFindBehavior2()
            pf:cancel()
            pf:reset()
            body:setPath2(nil)
        end)
        pcall(function()
            local st = body:getActionStateName()
            if st == "walktoward" or st == "pathfind" then body:changeState(ZombieIdleState.instance()) end
        end)
        body:clearAggroList()



        BridgeMove.obstacle = "car: " .. tostring(BridgeMove.exitCar(body))
        return
    end

    local asn = body:getActionStateName()
    if asn == "turnalerted" or asn == "lunge" or asn == "lunge-network" or asn == "attack" or asn == "attack-network"
        or asn == "thump" or asn == "face-target" or asn == "eatbody" or asn == "getdown" or asn == "fakedead" then




        Bridge.quenched = (Bridge.quenched or 0) + 1
        if Bridge.verbose and Bridge.time - (Bridge.quenchLog or -9999) >= 120 then
            pcall(function()
                local r = BridgeData.owner()
                local dx, dy = body:getX() - r:getX(), body:getY() - r:getY()
                log(string.format("engine state quenched: %s x%d d=%.2f bump=%s", tostring(asn), Bridge.quenched,
                    math.sqrt(dx * dx + dy * dy), tostring(body:getBumpType())))
            end)
            Bridge.quenched = 0
            Bridge.quenchLog = Bridge.time
        end
        pcall(function() body:changeState(ZombieIdleState.instance()) end)
        body:clearAggroList()
        return
    end

    local fallen = asn ~= nil and (string.sub(asn, 1, 8) == "onground" or string.sub(asn, 1, 8) == "falldown"
        or string.sub(asn, 1, 11) == "staggerback" or string.sub(asn, 1, 11) == "hitreaction"
        or string.sub(asn, 1, 11) == "knockeddown" or string.sub(asn, 1, 5) == "getup")
    if asn ~= Bridge.lastAsn and fallen then
        log("body state " .. tostring(asn) .. " after " .. tostring(Bridge.lastAsn))
    end
    Bridge.lastAsn = asn
    if asn ~= nil and (string.sub(asn, 1, 8) == "onground" or string.find(asn, "ragdoll", 1, true) ~= nil) then




        local groundWas = Bridge.groundTicks
        Bridge.groundTicks = Bridge.groundTicks + (Bridge.dt or 1)
        if Bridge.groundTicks >= 90 and math.floor(Bridge.groundTicks / 30) > math.floor(groundWas / 30) then
            pcall(function() body:setReanimateTimer(0) end)
        end
        if Bridge.groundTicks >= 180 and groundWas < 180 then
            local stepped = nil
            pcall(function() stepped = body:isBeingSteppedOn() end)
            log("body on ground 180 ticks, steppedOn=" .. tostring(stepped) .. ", getting up")
            pcall(function() body:changeState(ZombieGetUpState.instance()) end)
        end
    else
        Bridge.groundTicks = 0
    end

    if asn == "climbwindow" or asn == "climbfence" then
        BridgeMove.pendingClimb = nil
        BridgeMove.climbUntil = Bridge.time + 30

        if BridgeMove.cross ~= nil then BridgeMove.cross.started = true end

        if Bridge.climbSoundAsn ~= asn then
            Bridge.climbSoundAsn = asn
            if asn == "climbfence" then
                pcall(function() BridgeSound.fence(body, "ClimbOverFenceLow", false) end)
                pcall(function() BridgeSound.voice(body, "JumpLow", 30) end)
            else
                pcall(function() BridgeSound.voice(body, "ClimbWindow", 30) end)
            end
        end
    else
        Bridge.climbSoundAsn = nil
    end

    local knocked = string.sub(asn or "", 1, 11) == "staggerback"
    if knocked and not Bridge.wasKnocked then
        pcall(function() BridgeSound.voice(body, "PainFromFallLow", 120) end)
    end
    Bridge.wasKnocked = knocked


    if Bridge.zombieTicks % 30 == 0 and Bridge.hiddenSince == nil then
        local skin = nil
        pcall(function() skin = body:getHumanVisual():getSkinTexture() end)
        if skin ~= nil and skin ~= "FemaleBody01" then
            pcall(function() BridgeInventory.skin(body, Bridge.store) end)
            pcall(function() body:resetModelNextFrame() end)
            log("skin restored, was " .. tostring(skin))
        end
    end

    if engineState(asn) then return end


    if Bridge.zombieTicks % 5 == 0 then
        local okDoor, errDoor = pcall(function() BridgeMove.closeBehind(body) end)
        if not okDoor then BridgeMove.doorLast = "error: " .. tostring(errDoor) end
    end


    local ownerDead = Bridge.mourning ~= nil or Bridge.redDead(BridgeData.owner())
    if not ownerDead then
        handProbe(body, "before weapon")
        pcall(function() BridgeWeapon.update(body) end)
        handProbe(body, "weapon")

        local okSoc, errSoc = pcall(function() BridgeSocial.update(body) end)
        if not okSoc and BridgeSocial ~= nil then BridgeSocial.info = "error: " .. tostring(errSoc) end

        local okMom, errMom = pcall(function() BridgeMoments.update(body) end)
        if not okMom and BridgeMoments ~= nil then BridgeMoments.info = "error: " .. tostring(errMom) end
    end


    pcall(function() BridgeWeapon.animStep(body) end)


    pcall(function() BridgeMove.passTick(body, BridgeData.owner()) end)

    if not ownerDead then pcall(function() BridgeMove.runGuard(body, BridgeData.owner()) end) end

    if (not Bridge.follow or Bridge.pose ~= nil) and not ownerDead then
        pcall(function() BridgeMove.pushCheck(body, BridgeData.owner()) end)
    end






    local bump = ""
    pcall(function() bump = tostring(body:getBumpType()) end)
    local climbing = (bump == "ClimbFenceEnd" or bump == "ClimbFenceTall" or bump == "ClimbWindow"
        or bump == "Scramble") or Bridge.time < (BridgeMove.climbUntil or 0)
    local engineDriven = climbing or engineState(asn)
    if not BridgeMove.pathing and not BridgeMove.moving and not engineDriven then
        if Bridge.holdPos == nil then
            Bridge.holdPos = { body:getX(), body:getY(), body:getZ() }
        end
        if bump == "" or bump == "nil" then

            pcall(function() body:setBumpType("Stand") end)
        end
        local hx, hy = Bridge.holdPos[1], Bridge.holdPos[2]
        local dx, dy = body:getX() - hx, body:getY() - hy


        local limit = (Bridge.pose ~= nil) and 0.0025 or 0.16



        local shoved = bump == "left" or bump == "right"
        if not shoved and Bridge.pose == nil then
            pcall(function()
                local r = BridgeData.owner()
                local rx, ry = r:getX() - body:getX(), r:getY() - body:getY()
                local d2 = rx * rx + ry * ry
                shoved = d2 < 1.3 * 1.3 and (r:isRunning() or r:isSprinting())



                if not shoved and d2 < 0.9 * 0.9 then
                    local goes = false
                    pcall(function() goes = r:isPlayerMoving() end)
                    if goes then shoved = true end
                end
            end)
        end
        if Bridge.pose ~= nil and Bridge.pose.move then


            Bridge.holdPos = { body:getX(), body:getY(), body:getZ() }
        elseif shoved and Bridge.pose == nil then
            Bridge.holdPos = { body:getX(), body:getY(), body:getZ() }
        elseif Bridge.pose ~= nil and Bridge.poseNudged(body) then




            local o = Bridge.pose.origin
            local cap = Bridge.pose.seat and Bridge.POSE_DRIFT_SEAT or Bridge.POSE_DRIFT
            local ox, oy = body:getX() - o[1], body:getY() - o[2]
            local d = math.sqrt(ox * ox + oy * oy)
            if d > cap then
                local nx, ny = o[1] + ox * cap / d, o[2] + oy * cap / d
                pcall(function()
                    body:setX(nx)
                    body:setY(ny)
                    body:setLastX(nx)
                    body:setLastY(ny)
                end)
            end
            Bridge.holdPos = { body:getX(), body:getY(), body:getZ() }
        elseif (dx * dx + dy * dy) > limit then
            pcall(function()
                body:setX(hx)
                body:setY(hy)
                body:setLastX(hx)
                body:setLastY(hy)
            end)
        end
    else
        Bridge.holdPos = nil
    end

    local red = BridgeData.owner()
    local redCar = red and red:getVehicle() or nil




    if ownerDead then
        if Bridge.mourning ~= nil or Bridge.mournAware(body, red) then
            if not Bridge.mournFrame(body, red) then BridgeMove.update(body) end
            return
        end
        pcall(function() BridgeHeal.stop("player died far away") end)
        Bridge.mournVanish("player died far away")
        return
    end





    do
        local okCar, carBusy = pcall(function() return BridgeCar.update(body) end)
        if not okCar then
            warn("car failed: " .. tostring(carBusy))

            if redCar ~= nil and Bridge.mode == "follow" then
                Bridge.saveOutfit()
                Bridge.parked = true
                Bridge.hideBody(body, true)
                Bridge.despawn()
                Bridge.result = "body parked: player in car"
                return
            end
        elseif carBusy then
            Bridge.pose = nil
            pcall(function() BridgeMove.seatGuard(body) end)
            return
        end
    end





    local asleep = false
    pcall(function() asleep = red ~= nil and red:isAsleep() end)
    if asleep and Bridge.sleepParked == nil then
        local near = false
        pcall(function()
            local dx, dy = body:getX() - red:getX(), body:getY() - red:getY()
            near = dx * dx + dy * dy < 20 * 20 and math.abs(body:getZ() - red:getZ()) < 2
        end)
        if near then
            Bridge.sleepPark(body, "player asleep")
            return
        end
    end



    pcall(function() BridgeMove.seatGuard(body) end)

    local okWash, washing = pcall(function() return BridgeWash.update(body) end)
    if not okWash then BridgeWash.info = "error: " .. tostring(washing) end
    if okWash and washing then
        Bridge.pose = nil
        return
    end



    local okHeal, healing = true, false
    if not ownerDead then okHeal, healing = pcall(function() return BridgeHeal.update(body) end) end
    if not okHeal then BridgeHeal.info = "error: " .. tostring(healing) end
    if okHeal and healing then
        Bridge.pose = nil
        return
    end

    handProbe(body, "before fight")
    local okFight, fighting = pcall(function() return BridgeFight.update(body) end)
    handProbe(body, "fight")
    if not okFight then BridgeFight.info = "error: " .. tostring(fighting) end
    if okFight and fighting then
        Bridge.pose = nil
        return
    end


    local okGesture, gesturing = pcall(function() return BridgeInventory.gestureTick(body) end)
    if okGesture and gesturing then return end




    local okMove, moving = pcall(function() return BridgeWeapon.busy() end)
    if okMove and moving then
        local leave = false
        pcall(function() leave = Bridge.follow and dist2d(body, red) > 10 end)
        if not leave then return end
        pcall(function() BridgeWeapon.cancelMove(body) end)
    end


    if Bridge.mode ~= "follow" and Bridge.target == nil and Bridge.zombieTicks % 60 == 0
        and Bridge.time >= (Bridge.waitRetryAt or 0) then
        local st = Bridge.store
        if st ~= nil and st.waitX ~= nil and math.abs(body:getZ() - (st.waitZ or 0)) < 0.5 then
            local dx, dy = body:getX() - st.waitX, body:getY() - st.waitY

            local blocked = false
            pcall(function() blocked = BridgeMove.seatBlocks(st.waitX, st.waitY, st.waitZ or 0) end)
            if dx * dx + dy * dy > 4 and not blocked then
                Bridge.target = { x = st.waitX, y = st.waitY, z = st.waitZ or 0 }
                Bridge.targetSince = Bridge.time


                Bridge.pose = nil
            end
        end
    end


    if Bridge.mode ~= "follow" and Bridge.target == nil then
        pcall(function() BridgeMove.seatAside(body) end)
    end

    if Bridge.follow then
        local okSeat, errSeat = pcall(function() BridgeMove.seatPose(body) end)
        if not okSeat then BridgeMove.seatInfo = "error: " .. tostring(errSeat) end
    end

    if Bridge.pose == nil and Bridge.mode == "rest" and Bridge.target == nil then Bridge.pose = { anim = "Sit" } end

    if Bridge.pose ~= nil then
        local pose = Bridge.pose
        if pose.untilTick ~= nil and Bridge.time > pose.untilTick then
            Bridge.pose = nil
        else
            if BridgeMove.onPath() then BridgeMove.stopPath(body) end


            local cur = tostring(body:getBumpType())
            local alt = BridgeFastForward ~= nil and BridgeFastForward.POSE_ALT ~= nil and BridgeFastForward.POSE_ALT[pose.anim] or nil
            if cur ~= pose.anim and (alt == nil or cur ~= alt) then
                pcall(function() body:setBumpType(pose.anim) end)
            end
            return
        end
    end





    if not BridgeMove.pathing and not BridgeMove.steering then
        pcall(function()
            local pf = body:getPathFindBehavior2()
            pf:cancel()
            pf:reset()
            body:setPath2(nil)
        end)
        body:clearAggroList()
        pcall(function() body:setTargetSeenTime(0) end)
        if asn == "walktoward" or asn == "pathfind" then
            pcall(function() body:changeState(ZombieIdleState.instance()) end)
        end
    end



    if BridgeMove.pathing or BridgeMove.moving or BridgeMove.steering or BridgeMove.redMoving then
        Bridge.idleSince = Bridge.time
    elseif Bridge.pose == nil and (asn == "idle" or bump == "Stand") and (Bridge.time - Bridge.idleSince) > 600
        and Bridge.time >= Bridge.nextIdleAnim

        and not (BridgeFastForward ~= nil and BridgeFastForward.active()) then
        local out = false
        pcall(function() out = BridgeWeapon.isOut(body) end)
        if not out then
            local anims = { "ShiftWeight", "ChewNails", "WipeBrow", "PullAtCollar", "WipeHead" }
            pcall(function() body:setBumpType(anims[1 + ZombRand(#anims)]) end)
        end
        Bridge.nextIdleAnim = Bridge.time + 900 + ZombRand(900)
    end

    if Bridge.mode ~= "follow" and Bridge.target == nil then

        if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        if red ~= nil and Bridge.zombieTicks % 30 == 0 and dist2d(body, red) < 6 then
            pcall(function() body:faceLocationF(red:getX(), red:getY()) end)
        end
        return
    end

    BridgeMove.update(body)
    handProbe(body, "frame end")
end



function Bridge.sleepPark(body, why)
    Bridge.saveOutfit()
    Bridge.sleepParked = { x = body:getX(), y = body:getY(), z = body:getZ(), mode = Bridge.mode }
    Bridge.despawn()
    Bridge.result = "body parked: " .. tostring(why)
    log("body parked: " .. tostring(why))
end



function Bridge.sleepParkNow()
    if not Bridge.alive() or Bridge.kind ~= "zombie" or Bridge.sleepParked ~= nil then return false end
    Bridge.sleepPark(Bridge.body, "before sleep")
    return true
end









local function lookOf(z)
    local l = Bridge.looks[z]
    if l == nil then
        l = { tick = -9999, speed = 0, pathTick = -9999 }
        Bridge.looks[z] = l
    end
    return l
end







local LOOK_RUN_ON, LOOK_RUN_OFF = 0.046, 0.041
local LOOK_GAP_RUN, LOOK_GAP_WALK = 3.5, 2.5
local LOOK_GAIT_HOLD = 24


local COPY_FALL = { "hitreaction", "staggerback", "falldown", "knockeddown", "onground", "getup" }
local COPY_AGGRO = { ["lunge-network"] = true, ["attack-network"] = true, ["face-target"] = true, lunge = true,
    attack = true, turnalerted = true }
local function copyFallen(st)
    for _, p in ipairs(COPY_FALL) do if string.sub(st, 1, #p) == p then return true end end
    return false
end

local function applyLook(z, visuals, rec, who)
    z:setVariable(BODY_VAR, true)




    pcall(function()
        if not z:getVariableBoolean("SurvivorNPC") then z:setVariable("SurvivorNPC", true) end
        local md = z:getModData()
        if md.ST_Ignore ~= true then md.ST_Ignore = true end
        if md.notAloneBody ~= true then md.notAloneBody = true end
    end)
    pcall(function() Bridge.touched[z] = z:getPersistentOutfitID() end)
    pcall(function() z:setNoTeeth(true) end)
    pcall(function() z:setVariable("ZombieHitReaction", "Chainsaw") end)
    pcall(function() z:setVariable("NoLungeTarget", true) end)

    pcall(function()
        z:setVariable("WalkInjury", 0.0)
        z:setVariable("NotAloneAnimOld", false)
    end)


    local hitAt = Bridge.copyHit[z]
    if hitAt ~= nil then
        if Bridge.time - hitAt <= 60 then
            Bridge.clearHitMarks(z)
            pcall(function() if copyFallen(tostring(z:getActionStateName())) then z:changeState(ZombieIdleState.instance()) end end)
        else
            Bridge.copyHit[z] = nil
        end
    end

    pcall(function()
        if z:isRemoteZombie() then
            if z:getTarget() ~= nil then z:setTarget(nil) end
            if COPY_AGGRO[tostring(z:getActionStateName())] then z:changeState(ZombieIdleState.instance()) end
        end
    end)
    pcall(function() z:setDressInRandomOutfit(false) end)




    local hide = false
    pcall(function() hide = BridgeSleep ~= nil and BridgeSleep.hidingCopies() == true end)



    if type(rec) == "table" and type(rec.car) == "table" and rec.car.inside == true then hide = true end




    local now = nil
    pcall(function() now = z:isInvisible() end)
    if now ~= hide then Bridge.hideBody(z, hide) end
    pcall(function() z:setShootable(false) end)
    pcall(function() z:setInvulnerable(true) end)
    pcall(function() if not z:isGodMod() then z:setGodMod(true, true) end end)






    pcall(function()
        local d = z:getDescriptor()
        if d ~= nil and d:getVoicePrefix() ~= "VoiceFemale" then d:setVoicePrefix("VoiceFemale") end
    end)
    pcall(function() muteZombieVoice(z) end)

    local l = lookOf(z)
    local px, py = z:getX(), z:getY()
    if l.x ~= nil then
        local dx, dy = px - l.x, py - l.y
        local step = math.sqrt(dx * dx + dy * dy)

        local dt = math.max(Bridge.dt or 1, 0.05)
        if step < 1 then
            local a = 1 - 0.85 ^ dt
            l.speed = l.speed * (1 - a) + (step / dt) * a
        end
    end
    l.x, l.y = px, py
    local owner = nil
    if who ~= nil then
        pcall(function() owner = who == BridgeData.me() and BridgeData.owner() or getPlayerFromUsername(who) end)
    end
    local follow = false
    pcall(function()
        follow = owner ~= nil and not owner:isDead() and BridgeData.modeOf(rec) == "follow"
            and math.abs(owner:getZ() - z:getZ()) < 1
    end)
    local ws = 1.0
    if follow then
        local ownerRuns, ownerWs = false, nil
        pcall(function() ownerRuns = owner:isRunning() or owner:isSprinting() end)
        pcall(function() ownerWs = owner:getVariableFloat("WalkSpeed", 1.0) end)
        local gap = dist2d(z, owner)
        local want = ownerRuns or gap > LOOK_GAP_RUN or (l.run == true and gap > LOOK_GAP_WALK)
        if want ~= (l.run == true) and Bridge.time - (l.gaitAt or -9999) >= LOOK_GAIT_HOLD then
            l.run, l.gaitAt = want, Bridge.time
        end

        if ownerRuns and type(ownerWs) == "number" and ownerWs >= 0.3 then l.runBlend = ownerWs end
        if l.run then
            ws = (ownerRuns and ownerWs) or l.runBlend or 1.0
        else
            ws = ((not ownerRuns) and ownerWs) or 1.0
        end
        if type(ws) ~= "number" or ws < 0.3 then ws = 1.0 end
    else
        if l.speed > LOOK_RUN_ON then l.run = true elseif l.speed < LOOK_RUN_OFF then l.run = false end
    end
    pcall(function() z:setVariable("WalkSpeed", ws) end)
    pcall(function() z:setWalkType(l.run and "Run" or "Walk") end)
    Bridge.weaponVar(z)


    if who ~= nil then
        local sneak = false
        pcall(function() sneak = follow and owner:isSneaking() end)
        Bridge.sneakVar(z, sneak == true)
    end

    if BridgeData.modeOf(rec) == "rest" and l.speed < 0.01 then
        pcall(function() if z:getBumpType() ~= "Sit" then z:setBumpType("Sit") end end)
    end


    local sit = rec and rec.sit or nil
    if sit == "chair" and l.speed < 0.02 then
        pcall(function() z:setCollidable(false) end)
        pcall(function() if z:getBumpType() ~= "SitChair" then z:setBumpType("SitChair") end end)
    else
        pcall(function() if z:isSittingOnFurniture() then z:setSittingOnFurniture(false) end end)
        if sit == "floor" and l.speed < 0.01 then
            pcall(function() if z:getBumpType() ~= "Sit" then z:setBumpType("Sit") end end)
        elseif sit == nil and BridgeData.modeOf(rec) ~= "rest" then

            pcall(function()
                local b = tostring(z:getBumpType())
                if b == "SitChair" or b == "Sit" then z:setBumpType("") end
            end)
        end
    end

    if not visuals then return end
    local items = (rec and rec.items) or ""


    if items ~= l.raw then
        l.raw = items
        l.key = BridgeItems.lookKey(BridgeItems.decode(items))
    end

    local hair = BridgeData.hairOf(rec)
    if hair ~= l.hair then
        l.hair = hair
        l.applied = nil
    end
    local skin = nil
    pcall(function() skin = z:getHumanVisual():getSkinTexture() end)
    local stale = l.applied ~= l.key or skin ~= "FemaleBody01"
    if stale and (Bridge.time - l.tick) >= 30 then
        l.tick = Bridge.time
        l.applied = l.key
        BridgeInventory.dressVisual(z, items, rec)
        pcall(function() l.hands = { p = z:getPrimaryHandItem(), s = z:getSecondaryHandItem() } end)
    elseif l.hands ~= nil and l.applied == l.key then


        pcall(function()
            if l.hands.p ~= nil and z:getPrimaryHandItem() ~= l.hands.p then z:setPrimaryHandItem(l.hands.p) end
            if l.hands.s ~= nil and z:getSecondaryHandItem() ~= l.hands.s then z:setSecondaryHandItem(l.hands.s) end
        end)
    end
end





local function guestDrive(z, who, rec)
    applyLook(z, true, rec, who)
    z:setUseless(true)
    z:setTarget(nil)
    z:clearAggroList()



    pcall(function()
        z:setBodyToEat(nil)
        if z:getEatBodyTarget() ~= nil then z:setEatBodyTarget(nil, false) end
        if z:isFakeDead() then z:setFakeDead(false) end
        if z:isForceFakeDead() then z:setForceFakeDead(false) end
        if z:isBecomeCrawler() then z:setBecomeCrawler(false) end
        if z:isCrawling() then z:setCrawler(false) end
    end)
    local asn = z:getActionStateName()
    if asn == "turnalerted" or asn == "lunge" or asn == "walktoward" or asn == "attack" or asn == "thump" or asn == "face-target"
        or asn == "eatbody" or asn == "getdown" or asn == "fakedead" then
        pcall(function() z:changeState(ZombieIdleState.instance()) end)
    end
    local pf = z:getPathFindBehavior2()
    local owner = nil
    pcall(function() owner = getPlayerFromUsername(who) end)


    local ownerDead = false
    pcall(function() ownerDead = owner ~= nil and owner:isDead() end)
    if ownerDead then owner = nil end

    local sneak = false
    pcall(function() sneak = owner ~= nil and BridgeData.modeOf(rec) == "follow" and owner:isSneaking() end)
    Bridge.sneakVar(z, sneak == true)
    if BridgeData.modeOf(rec) ~= "follow" or owner == nil or math.abs(owner:getZ() - z:getZ()) >= 1 then
        pcall(function() pf:cancel() pf:reset() z:setPath2(nil) end)
        return
    end
    local l = lookOf(z)
    local d = dist2d(z, owner)
    if d > 2.5 then
        local walk = d > 5 and "Run" or "Walk"
        z:setWalkType(walk)
        pcall(function() z:setSpeedTypeFromWalkType() end)

        if (Bridge.time - l.pathTick) >= 30 then
            l.pathTick = Bridge.time
            pf:pathToLocationF(owner:getX(), owner:getY(), owner:getZ())
        end
        pf:update()
    else
        pcall(function() pf:cancel() pf:reset() z:setPath2(nil) end)
    end
end



Bridge.copySwing = {}
function Bridge.lookSwing(args)
    if not Bridge.mp or args == nil or BridgeFight == nil then return false end
    if not BridgeFight.isAttackNode(args.a) and not Bridge.isLookOnce(args.a) then return false end
    for z, e in pairs(Bridge.seen) do
        if e.who == args.owner then
            local ok = false
            pcall(function() ok = z:getPersistentOutfitID() == args.id and z:isRemoteZombie() and not z:isDead() end)
            if ok then
                pcall(function()
                    z:setVariable("BumpAnimFinished", false)
                    z:setBumpType(args.a)
                end)
                Bridge.copySwing[z] = { a = args.a, at = Bridge.time }
                return true
            end
        end
    end
    return false
end



function Bridge.copyStaleEnd()
    for z, s in pairs(Bridge.copySwing) do
        if Bridge.time - s.at > 14 then
            Bridge.copySwing[z] = nil
        else
            pcall(function()
                if z:getVariableBoolean("BumpAnimFinished") and tostring(z:getActionStateName()) == "bumped"
                    and tostring(z:getBumpType()) == s.a then
                    z:setVariable("BumpAnimFinished", false)
                end
            end)
        end
    end
end
Events.OnTickEvenPaused.Add(function() pcall(Bridge.copyStaleEnd) end)








Bridge.strays = {}




function Bridge.unstray(z)
    if Bridge.strays[z] == nil then return end
    Bridge.strays[z] = nil
    Bridge.hideBody(z, false)
end

function Bridge.strayCheck(z, pid, oid)
    local sign = false
    if BridgeRemnant ~= nil and BridgeRemnant.hasMark(pid) then
        pcall(function() sign = z:isFemale() and z:getOutfitName() == "Naked" and not z:isDead() end)
    end
    if not sign then
        Bridge.unstray(z)
        return false
    end

    if Bridge.staleIds ~= nil and Bridge.staleIds[pid] ~= nil then
        Bridge.strays[z] = nil

        if z == Bridge.body then Bridge.body, Bridge.kind = nil, nil end
        pcall(function() Bridge.unhumanize(z, true) end)
        pcall(function() z:removeFromSquare() end)
        pcall(function() z:removeFromWorld() end)
        log("stale companion body id=" .. tostring(pid) .. " arrived late, removed")
        return true
    end
    Bridge.hideBody(z, true)
    local s = Bridge.strays[z]
    if s == nil or s.pid ~= pid then
        s = { pid = pid, since = Bridge.time }
        Bridge.strays[z] = s
    end
    s.seenAt = Bridge.time
    if Bridge.time - s.since >= 600 and Bridge.time - (Bridge.strayAskAt or -99999) >= 3600 then
        Bridge.strayAskAt = Bridge.time
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "stray", { id = pid, oid = oid }) end)
        log("companion body without record id=" .. tostring(pid) .. " hidden, reported to server")
    end
    return true
end



Bridge.bodyIndex = {}

function Bridge.indexBodies()
    local idx = {}
    local w = Bridge.world
    if w ~= nil and w.players ~= nil then
        for who, rec in pairs(w.players) do
            if rec.bodyId ~= nil then idx[rec.bodyId] = who end
        end
    end
    Bridge.bodyIndex = idx
end







Bridge.guestWatch = {}
function Bridge.watchGuest(z, who, remote)
    if not Bridge.verbose then return end
    local w = Bridge.guestWatch[z]
    local x, y = z:getX(), z:getY()
    local asn = tostring(z:getActionStateName())
    if w == nil then
        w = { x = x, y = y, asn = asn, jumps = 0, far = 0, since = Bridge.time }
        Bridge.guestWatch[z] = w
        return
    end
    local dx, dy = x - w.x, y - w.y
    local step = math.sqrt(dx * dx + dy * dy)
    if step > 0.5 then
        w.jumps = w.jumps + 1
        if step > w.far then w.far = step end
    end
    w.x, w.y = x, y
    if asn ~= w.asn then
        local fallen = string.sub(asn, 1, 8) == "onground" or string.sub(asn, 1, 8) == "falldown"
            or string.sub(asn, 1, 11) == "staggerback" or string.sub(asn, 1, 11) == "hitreaction"
            or string.sub(asn, 1, 11) == "knockeddown" or string.sub(asn, 1, 5) == "getup"
        if fallen then
            log(string.format("guest body of %s: state %s after %s, bump=%s remote=%s at %.1f %.1f", tostring(who), asn,
                tostring(w.asn), tostring(z:getBumpType()), tostring(remote), x, y))
        end
        w.asn = asn
    end
    if Bridge.time - w.since >= 120 then
        if w.jumps > 0 then
            local red = BridgeData.owner()
            local d = -1
            if red ~= nil then d = math.sqrt((x - red:getX()) ^ 2 + (y - red:getY()) ^ 2) end
            log(string.format("guest body of %s: %d position jumps in 2 s, longest %.2f, state=%s bump=%s remote=%s, %.1f tiles from me",
                tostring(who), w.jumps, w.far, asn, tostring(z:getBumpType()), tostring(remote), d))
        end
        w.jumps, w.far, w.since = 0, 0, Bridge.time
    end
end

function Bridge.onZombieUpdate(zombie)
    local ok, isBody = pcall(function() return zombie:getVariableBoolean(BODY_VAR) end)
    if not ok then return end

    if not isBody and Bridge.hiddenObjs ~= nil and Bridge.hiddenObjs[zombie] then Bridge.hideBody(zombie, false) end



    if isBody and zombie == Bridge.body and BridgeSleep ~= nil and BridgeSleep.speedKeepEnabled then
        pcall(function() BridgeSleep.keepSpeed("body") end)
    end
    if reusedBody(zombie) then

        release(zombie)
        if Bridge.body == zombie then Bridge.body = nil Bridge.kind = nil end
        Bridge.seen[zombie] = nil
        Bridge.looks[zombie] = nil
        Bridge.guestWatch[zombie] = nil
        return
    end
    if Bridge.mp then

        local pid = nil
        pcall(function() pid = zombie:getPersistentOutfitID() end)
        if pid == nil then return end
        local st = Bridge.store


        local oid = nil
        pcall(function() oid = zombie:getOnlineID() end)
        local function same(rec)
            return rec ~= nil and rec.bodyId == pid and (rec.onlineId == nil or rec.onlineId == oid)
        end
        local mine = st ~= nil and st.bodyId ~= nil and same(st)
        local who, rec = nil, nil
        if mine then
            who, rec = BridgeData.me(), st
        else
            who = Bridge.bodyIndex[pid]





            if who == nil or Bridge.world == nil or Bridge.world.players == nil then
                Bridge.strayCheck(zombie, pid, oid)
                return
            end
            rec = Bridge.world.players[who]
            if not same(rec) then
                Bridge.strayCheck(zombie, pid, oid)
                return
            end
        end


        Bridge.unstray(zombie)
        local okDead, dead = pcall(function() return zombie:isDead() end)
        if not okDead or dead then return end

        if mine and pid == Bridge.released then return end
        Bridge.seen[zombie] = { who = who, rec = rec, tick = Bridge.time }
        local remote = true
        pcall(function() remote = zombie:isRemoteZombie() end)
        if mine then
            if remote then






                if Bridge.hiddenSince ~= nil and Bridge.body == zombie then
                    Bridge.hideBody(zombie, false)
                    Bridge.hiddenSince = nil
                end
                pcall(function() applyLook(zombie, Bridge.body ~= zombie, rec, who) end)

                Bridge.walkTypeSet = nil
                return
            end
            if Bridge.body ~= zombie then Bridge.adoptServerBody(zombie) end
            local okUpd, err = pcall(function() updateZombieBody(zombie) end)
            if not okUpd then BridgeMove.pathResult = "update error: " .. tostring(err) end
            return
        end
        pcall(function() Bridge.watchGuest(zombie, who, remote) end)
        if remote then
            pcall(function() applyLook(zombie, true, rec, who) end)
        else
            local okG, errG = pcall(function() guestDrive(zombie, who, rec) end)
            if not okG then Bridge.result = "guest error: " .. tostring(errG) end
        end
        return
    end
    if not isBody then



        local pid = nil
        pcall(function() pid = zombie:getPersistentOutfitID() end)
        if Bridge.checked[zombie] == pid then return end
        Bridge.checked[zombie] = pid
        if not BridgeInventory.isMarked(zombie) then return end

        if BridgeData.foreign(zombie) then return end
        if Bridge.body ~= nil and Bridge.alive() then

            pcall(function() zombie:removeFromSquare() end)
            pcall(function() zombie:removeFromWorld() end)
            log("removed duplicate body from save")
            return
        end
        pcall(function() humanize(zombie) end)
        Bridge.hideBody(zombie, false)
        Bridge.body = zombie
        Bridge.kind = "zombie"
        Bridge.follow = true
        Bridge.mode = "follow"
        Bridge.pose = nil
        BridgeMove.reset(nil)
        BridgeFight.reset(nil)


        if not Bridge.parked and Bridge.sleepParked == nil and Bridge.claimParked == nil then BridgeFight.resetFatigue() end
        BridgeFight.guardOnly = false
        pcall(function() BridgeInventory.redress(zombie) end)
        Bridge.result = "restored body from save"
        log("restored body from save")
        return
    end
    local killed = false
    pcall(function() killed = zombie:isDead() end)
    pcall(function() killed = killed or zombie:isOnKillDone() end)
    if killed then return end
    if Bridge.body == nil then

        Bridge.body = zombie
        Bridge.kind = "zombie"
        Bridge.follow = true
        Bridge.hideBody(zombie, false)
        log("adopted existing body")
    end
    local okUpd, err = pcall(function() updateZombieBody(zombie) end)
    if not okUpd then BridgeMove.pathResult = "update error: " .. tostring(err) end
end


local function updatePlayerBody()
    if Bridge.manualUpdate then
        pcall(function() Bridge.body:update() end)
    end
    if Bridge.follow and (Bridge.tick - Bridge.lastPath) >= PATH_EVERY then
        Bridge.lastPath = Bridge.tick
        local red = BridgeData.owner()
        if red ~= nil and dist2d(Bridge.body, red) > FOLLOW_DIST then
            pcall(function() Bridge.body:pathToCharacter(red) end)
        end
    end
    if Bridge.target and (Bridge.tick - Bridge.lastPath) >= PATH_EVERY then
        Bridge.lastPath = Bridge.tick
        local t = Bridge.target
        pcall(function() Bridge.body:pathToLocationF(t.x, t.y, t.z) end)
    end
end











local SAFE_COMMANDS = { say = true, voice = true, quiet = true, come = true, follow = true, go = true, wait = true,
    rest = true, stop = true, mode = true, sit = true, stand = true, sleep = true, anim = true, walk = true,
    keep = true, far = true, ["goto"] = true, trace = true, sq = true, doors = true, status = true,
    items = true, wounds = true, heal = true, wash = true, name = true, call = true, goodbye = true, menu = true,
    lose = true, despawn = true }



local DEV_MP_COMMANDS = { mood = true, rel = true, car = true }

function Bridge.run(line)
    local parts = split(line)
    local cmd = parts[2]
    if cmd == nil then return "empty" end
    local dev = BridgeBuild ~= nil and BridgeBuild.test == true
    local devMp = dev and Bridge.mp and DEV_MP_COMMANDS[cmd] == true
    if not devMp and (Bridge.mp or not dev) and (not SAFE_COMMANDS[cmd] or (cmd == "call" and parts[3] ~= nil)) then
        return cmd .. (dev and ": not in multiplayer" or ": test build only")
    end

    if cmd == "spawn" or cmd == "call" then
        if parts[3] == "player" then return Bridge.spawnPlayer() end
        return Bridge.call()
    end
    if cmd == "goodbye" then return Bridge.goodbye() end
    if cmd == "despawn" then
        pcall(function() Bridge.saveOutfit() end)
        setWant(false)
        Bridge.respawnAt = nil
        Bridge.leaveAt = nil
        Bridge.despawnByCommand = true
        local r = Bridge.despawn()
        Bridge.despawnByCommand = false
        return r
    end
    if cmd == "rest" then return Bridge.setMode("rest") end
    if cmd == "mode" then return Bridge.setMode(parts[3] or "follow") end
    if cmd == "name" then return Bridge.setName(decode(tail(line, 2))) end
    if cmd == "wash" then return BridgeWash.start("command") end

    if cmd == "talk" then return BridgeSocial.talk(parts[3] or "Chat") end
    if cmd == "ask" then return BridgeSocial.ask() end







































    if cmd == "stop" then
        Bridge.follow = false
        Bridge.target = nil
        if Bridge.alive() then
            BridgeMove.reset(Bridge.body)
            BridgeFight.reset(Bridge.body)
            pcall(function() Bridge.body:StopAllActionQueueWalking() end)
        end
        return "stopped"
    end
    if cmd == "follow" then
        if parts[3] == "on" then return Bridge.setMode("follow") end
        return Bridge.setMode("wait")
    end
    if cmd == "go" then return Bridge.setMode("follow") end
    if cmd == "wait" then
        if parts[3] == "car" then return "car disabled: crash in engine with body inside" end
        return Bridge.setMode("wait")
    end
    if cmd == "car" then
        if parts[3] == "out" then
            if not Bridge.alive() then return "no body" end
            return BridgeMove.exitCar(Bridge.body)
        end


        local red = BridgeData.owner()
        local car = nil
        pcall(function() car = red:getVehicle() end)
        if car == nil then


            pcall(function()
                local cell, best = getCell(), 10
                local rx, ry, rz = math.floor(red:getX()), math.floor(red:getY()), math.floor(red:getZ())
                for dx = -10, 10 do
                    for dy = -10, 10 do
                        local sq = cell:getGridSquare(rx + dx, ry + dy, rz)
                        local v = sq and sq:getVehicleContainer() or nil
                        if v ~= nil then
                            local d = dist2d(v, red)
                            if d < best then car, best = v, d end
                        end
                    end
                end
            end)
        end
        if car == nil then return "no car within 10 tiles; " .. BridgeCar.describe() end
        if parts[3] == "lock" or parts[3] == "unlock" then
            local lock = parts[3] == "lock"
            if Bridge.mp then
                pcall(function() sendClientCommand(red, "Bridge", "testCar", { v = car:getId(), lock = lock }) end)
                return "asked server to " .. parts[3] .. " passenger doors"
            end
            local n = 0
            pcall(function()
                for i = 1, car:getMaxPassengers() - 1 do
                    local p = car:getPassengerDoor(i)
                    if p ~= nil and p:getDoor() ~= nil then
                        p:getDoor():setLocked(lock)
                        n = n + 1
                    end
                end
            end)
            return parts[3] .. "ed " .. n .. " passenger doors"
        end
        local seats = {}
        pcall(function()
            for _, s in ipairs(BridgeCar.layout(car, nil, nil)) do
                local p = nil
                pcall(function() p = car:getPassengerDoor(s.i) end)
                local lock = false
                pcall(function() lock = p ~= nil and p:getDoor() ~= nil and p:getDoor():isLocked() end)
                seats[#seats + 1] = string.format("%d:%s%s%s%s%s%s", s.i, s.id or "?", s.person and " person" or "",
                    s.items and " items" or "", s.blocked and " wall" or "", s.reserved and " taken" or "", lock and " locked" or "")
            end
        end)
        return string.format("car %s seats [%s]; %s", tostring(car:getId()), table.concat(seats, ", "), BridgeCar.describe())
    end
    if cmd == "sit" then return Bridge.setPose("Sit", nil) end
    if cmd == "sleep" then return Bridge.setPose("Sleep", nil) end
    if cmd == "stand" then return Bridge.setPose(nil) end
    if cmd == "anim" then
        if parts[3] == nil then return "anim needs a name" end
        return Bridge.setPose(parts[3], tonumber(parts[4]) or 4)
    end
    if cmd == "fight" then

        if parts[3] == "tired" then
            BridgeFight.fatigue = math.max(0, math.min(1, tonumber(parts[4]) or 1))
            return "fatigue=" .. tostring(BridgeFight.fatigue)
        end
        BridgeFight.enabled = (parts[3] ~= "off")
        if not BridgeFight.enabled then BridgeFight.reset(Bridge.body) end
        return "fight=" .. tostring(BridgeFight.enabled)
    end
    if cmd == "update" then
        Bridge.manualUpdate = (parts[3] == "on")
        return "manualUpdate=" .. tostring(Bridge.manualUpdate)
    end
    if cmd == "goto" then
        local x, y, z = tonumber(parts[3]), tonumber(parts[4]), tonumber(parts[5])
        if x == nil or y == nil then return "goto needs x y z" end
        if not Bridge.alive() then return "no body" end
        Bridge.follow = false
        Bridge.target = { x = x, y = y, z = z or 0 }
        BridgeMove.pathing = false
        Bridge.holdPos = nil
        return "going"
    end
    if cmd == "walk" then
        if parts[3] == nil or parts[3] == "auto" then
            BridgeMove.forcedWalk = nil
            return "walkType=auto"
        end
        BridgeMove.forcedWalk = parts[3]
        BridgeMove.walkType = parts[3]
        return "walkType=" .. BridgeMove.walkType
    end
    if cmd == "say" then return Bridge.say(decode(tail(line, 2))) end
    if cmd == "voice" then return Bridge.voice(parts[3] or "ShoutHey") end



    if cmd == "alife" then return Bridge.alife(parts) end
    if cmd == "clean" then
        local killed = 0
        local ok, err = pcall(function()
            local list = getCell():getZombieList()
            local doomed = {}
            for i = 0, list:size() - 1 do
                local z = list:get(i)
                if z ~= Bridge.body and BridgeInventory.isMarked(z) and not BridgeData.foreign(z) then doomed[#doomed + 1] = z end
            end
            for i = 1, #doomed do
                pcall(function()
                    doomed[i]:removeFromSquare()
                    doomed[i]:removeFromWorld()
                    killed = killed + 1
                end)
            end
        end)
        if not ok then return "clean failed: " .. tostring(err) end
        return "cleaned " .. tostring(killed)
    end



    if cmd == "lose" then
        if not Bridge.mp then return "lose: multiplayer only" end
        local b = Bridge.body
        if b == nil then return "lose: no body" end
        Bridge.body = nil
        Bridge.kind = nil
        pcall(function() Bridge.unhumanize(b) end)
        pcall(function() b:removeFromSquare() end)
        pcall(function() b:removeFromWorld() end)
        log("body object dropped on client only (lose)")
        return "lose: body object removed on client, server keeps id " .. tostring(Bridge.store and Bridge.store.bodyId)
    end
    if cmd == "come" then return Bridge.teleportToRed() end

    if cmd == "keep" then return Bridge.setKeep(parts[3]) end
    if cmd == "far" then return Bridge.setFar(parts[3] == "on") end
    if cmd == "set" then return BridgeMove.set(parts[3], parts[4]) end
    if cmd == "heal" then
        if not Bridge.alive() or Bridge.kind ~= "zombie" then return "no body" end
        if parts[3] == "stop" then BridgeHeal.stop("command") return "heal stopped" end
        if not Bridge.drivable() then return "body driven by another client, heal later" end
        local red = BridgeData.owner()
        if red == nil then return "no player" end
        return "heal: " .. tostring(BridgeHeal.start(Bridge.body, red, true))
    end
    if cmd == "wounds" then
        local red = BridgeData.owner()
        if red == nil then return "no player" end
        return BridgeHeal.describe(BridgeHeal.scan(red))
    end

    if cmd == "quiet" then
        Bridge.quietLines = parts[3] ~= "off"
        return "quiet " .. tostring(Bridge.quietLines)
    end

    if cmd == "doors" then
        local red = BridgeData.owner()
        if red == nil then return "doors: no player" end
        local ok, res = pcall(function() return BridgeMove.doorsNear(red, math.min(60, tonumber(parts[3]) or 30), parts[4]) end)
        return ok and res or ("doors failed: " .. tostring(res))
    end
    if cmd == "trace" then
        BridgeMove.traceUntil = Bridge.tick + (tonumber(parts[3]) or 300)
        return "tracing " .. tostring(BridgeMove.traceUntil - Bridge.tick) .. " ticks"
    end






























    if cmd == "drive" then return Bridge.driveStart(parts[3], parts[4]) end
    if cmd == "status" then return "ok" end

    if cmd == "mortal" then
        Bridge.mortal = parts[3] == "on"
        return "mortal " .. tostring(Bridge.mortal)
    end

    if cmd == "sq" then
        local x, y = tonumber(parts[3]), tonumber(parts[4])
        local z = tonumber(parts[5]) or math.floor(BridgeData.owner():getZ())
        if x == nil or y == nil then return "sq X Y [Z]" end
        local cell = getCell()
        local s0 = cell:getGridSquare(math.floor(x), math.floor(y), z)
        if s0 == nil then return "no square" end
        local out = { string.format("sq %d,%d free=%s solid=%s", s0:getX(), s0:getY(), tostring(s0:isFree(false)), tostring(s0:isSolid())) }
        local objs = s0:getObjects()
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            local name = "?"
            pcall(function() name = tostring(o:getSprite():getName()) end)
            out[#out + 1] = tostring(o:getObjectName()) .. ":" .. name
        end
        for _, d in ipairs({ { "N", 0, -1 }, { "S", 0, 1 }, { "W", -1, 0 }, { "E", 1, 0 } }) do
            local n = cell:getGridSquare(s0:getX() + d[2], s0:getY() + d[3], z)
            if n ~= nil then
                out[#out + 1] = string.format("%s blocked=%s wall=%s door=%s free=%s", d[1], tostring(s0:isBlockedTo(n)),
                    tostring(s0:isWallTo(n)), tostring(s0:isDoorTo(n)), tostring(n:isFree(false)))
            end
        end
        return table.concat(out, " | ")
    end






    if cmd == "mt" then
        local b = Bridge.body
        if b == nil then return "mt: no body" end
        local sv = SandboxVars ~= nil and SandboxVars.MoreTraits or nil
        if parts[3] == "chance" then
            if sv == nil then return "mt: no More Traits sandbox" end
            sv.ScroungerItemChance = tonumber(parts[4]) or 10
        elseif parts[3] == "flag" then
            b:getModData().bScroungerorIncomprehensiveRolled = (parts[4] == "on") or nil
        elseif parts[3] == "refresh" then
            local loot = getPlayerLoot(0)
            if loot ~= nil then pcall(function() loot:refreshBackpacks() end) end
        elseif parts[3] == "trait" then

            if type(ToadTraitsRegistries) ~= "table" then return "mt: More Traits not active" end
            local ok, err = pcall(function() BridgeData.owner():getCharacterTraits():add(ToadTraitsRegistries.scrounger) end)
            if not ok then return "mt trait failed: " .. tostring(err) end
        end
        local trait, parent = "no More Traits", "?"


        if type(ToadTraitsRegistries) == "table" then
            pcall(function() trait = tostring(BridgeData.owner():hasTrait(ToadTraitsRegistries.scrounger)) end)
        end
        pcall(function() parent = tostring(b:getInventory():getParent() == b) end)
        local counts, list = {}, {}
        local items = b:getInventory():getItems()
        for i = 0, items:size() - 1 do
            local t = items:get(i):getFullType()
            counts[t] = (counts[t] or 0) + 1
        end
        for t, n in pairs(counts) do list[#list + 1] = t .. "=" .. n end
        table.sort(list)
        return string.format("mt scrounger=%s chance=%s flag=%s parentIsBody=%s items=%d [%s]", trait,
            tostring(sv and sv.ScroungerItemChance), tostring(b:getModData().bScroungerorIncomprehensiveRolled), parent,
            items:size(), table.concat(list, " "))
    end


    if cmd == "items" then
        local b = Bridge.body
        if b == nil then return "items: no body" end
        local counts, list, total = {}, {}, 0
        local function walk(inv, prefix, depth)
            local items = inv:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                local t = prefix .. tostring(it:getFullType())
                counts[t] = (counts[t] or 0) + 1
                total = total + 1
                if depth < 3 and instanceof(it, "InventoryContainer") then
                    walk(it:getInventory(), tostring(it:getType()) .. "/", depth + 1)
                end
            end
        end
        local ok, err = pcall(function() walk(b:getInventory(), "", 0) end)
        if not ok then return "items failed: " .. tostring(err) end
        for t, n in pairs(counts) do list[#list + 1] = t .. "=" .. n end
        table.sort(list)
        return "items " .. total .. ": " .. table.concat(list, " ")
    end


    if cmd == "menu" then
        getCore():exitToMenu()
        return "exit to menu"
    end

    return "unknown command: " .. tostring(cmd)
end













































































































































































































































































































































































function Bridge.noFire(body)
    if Bridge.mortal or body == nil then return end
    pcall(function()
        if not body:isOnFire() then return end
        body:StopBurning()
        body:setOnFire(false)
        Bridge.fireOut = (Bridge.fireOut or 0) + 1
    end)
end







local function noShootTick()
    Bridge.preTicks = (Bridge.preTicks or 0) + 1

    for z, e in pairs(Bridge.seen) do
        if z ~= Bridge.body and Bridge.time - (e.tick or -9999) <= 120 then
            pcall(function()
                z:setShootable(false)
                if z:getBallisticsTarget() ~= nil then z:releaseBallisticsTarget() end
            end)
        end
    end
    if Bridge.mortal or not (Bridge.alive() and Bridge.kind == "zombie") then return end
    pcall(function()
        if Bridge.body:isShootable() then Bridge.preWas = (Bridge.preWas or 0) + 1 end
        Bridge.body:setShootable(false)
    end)




    pcall(function()
        if Bridge.body:getBallisticsTarget() ~= nil then
            Bridge.body:releaseBallisticsTarget()
            Bridge.btOff = (Bridge.btOff or 0) + 1
        end
    end)
end
Bridge.noShootTick = noShootTick
Events.OnTickEvenPaused.Add(noShootTick)

local function noFireTick()
    if not (Bridge.alive() and Bridge.kind == "zombie") then return end
    local body = Bridge.body
    if not Bridge.mortal then pcall(function() body:setShootable(false) end) end
    Bridge.noFire(body)
end
Events.OnTick.Add(noFireTick)




















Events.OnTick.Add(function()
    if Bridge.kind ~= "zombie" or Bridge.body == nil then return end
    Bridge.keepHidden(Bridge.body, "tick")
end)


local function eachCommand(handler)
    local reader = getFileReader(IN_FILE, false)
    if reader == nil then return end
    while true do
        local line = reader:readLine()
        if line == nil then reader:close() return end
        line = string.gsub(line, "^%s+", "")
        if line ~= "" then
            local num = tonumber(string.match(line, "^(%d+)"))
            if num ~= nil then handler(num, line) end
        end
    end
end



function Bridge.skipOldCommands()
    local skipped = 0
    local ok, err = pcall(function()
        eachCommand(function(num)
            if num > Bridge.ack then Bridge.ack = num end
            skipped = skipped + 1
        end)
    end)
    if not ok then
        Bridge.result = "skip failed, will retry: " .. tostring(err)
        return
    end
    Bridge.skipped = true
    Bridge.result = "loaded, skipped " .. tostring(skipped) .. " old commands, ack=" .. tostring(Bridge.ack)
    log(Bridge.result)
end

function Bridge.readCommands()

    if not Bridge.skipped then Bridge.skipOldCommands() return end
    local ok, err = pcall(function()
        eachCommand(function(num, line)
            if num > Bridge.ack then
                Bridge.ack = num
                local okRun, res = pcall(function() return Bridge.run(line) end)
                if not okRun then res = "error: " .. tostring(res) end
                Bridge.result = tostring(num) .. ": " .. tostring(res)
                log("cmd " .. tostring(num) .. " -> " .. tostring(res))
            end
        end)
    end)
    if not ok then Bridge.result = "read failed: " .. tostring(err) end
end



function Bridge.writeState()

    if not Bridge.bridgeOn then return end
    pcall(function()
        local lines = {}
        local function add(k, v) lines[#lines + 1] = tostring(k) .. "=" .. tostring(v) end

        add("tick", Bridge.tick)
        add("ack", Bridge.ack)
        add("result", Bridge.result)
        add("follow", tostring(Bridge.follow))
        add("mode", Bridge.mode)
        pcall(function()
            local r = BridgeData.relOf(Bridge.store)
            add("rel", string.format("f=%d r=%d days=%d hours=%.1f gain=%d/%d", r.f, r.r, r.days, r.hours, r.gainF, r.gainR))
            add("social", BridgeSocial.info)
            add("moments", BridgeMoments.info)
            add("mood", BridgeMood.info)
        end)
        add("pose", Bridge.pose and Bridge.pose.anim or "none")
        add("target", Bridge.target and string.format("%.1f %.1f %.0f", Bridge.target.x, Bridge.target.y, Bridge.target.z) or "none")

        pcall(function() add("car", BridgeCar.describe() .. (Bridge.store and Bridge.store.left and " left=1" or "")) end)

        add("outfit_guard", string.format("redressed=%d dressed_worn=%s", Bridge.engineRedress or 0, tostring(Bridge.dressedWorn)))

        local red = BridgeData.owner()
        if red ~= nil then
            pcall(function() add("red_wounds", BridgeHeal.describe(BridgeHeal.scan(red))) end)
            add("red_x", string.format("%.2f", red:getX()))
            add("red_y", string.format("%.2f", red:getY()))
            add("red_z", string.format("%.0f", red:getZ()))
            pcall(function() add("red_health", string.format("%.1f", red:getBodyDamage():getOverallBodyHealth())) end)
            pcall(function()
                local s = red:getStats()
                add("red_mood", string.format("bored=%.1f unhappy=%.1f stress=%.3f anger=%.3f pain=%.1f panic=%.1f",
                    s:get(CharacterStat.BOREDOM), s:get(CharacterStat.UNHAPPINESS), s:get(CharacterStat.STRESS),
                    s:get(CharacterStat.ANGER), s:get(CharacterStat.PAIN), s:get(CharacterStat.PANIC)))
            end)
            pcall(function() add("red_running", tostring(red:isRunning() or red:isSprinting())) end)
        else
            add("red_x", "none")
        end

        if Bridge.alive() then
            add("body_alive", 1)
            add("body_kind", tostring(Bridge.kind))
            add("body_x", string.format("%.2f", Bridge.body:getX()))
            add("body_y", string.format("%.2f", Bridge.body:getY()))
            add("body_z", string.format("%.0f", Bridge.body:getZ()))
            pcall(function() add("body_state", tostring(Bridge.body:getActionStateName())) end)
            pcall(function() add("body_bump", tostring(Bridge.body:getBumpType())) end)
            pcall(function() add("body_has_path", tostring(Bridge.body:hasPath())) end)
            pcall(function() add("body_useless", tostring(Bridge.body:isUseless())) end)
            pcall(function() add("body_health", string.format("%.2f", Bridge.body:getHealth())) end)
            pcall(function() add("body_shootable", tostring(Bridge.body:isShootable())) end)
            pcall(function() add("body_hands", tostring(Bridge.body:getPrimaryHandItem() and Bridge.body:getPrimaryHandItem():getFullType() or "none")) end)
            pcall(function()
                local s2 = Bridge.body:getSecondaryHandItem()
                add("body_hand2", tostring(s2 and s2:getFullType() or "none"))
            end)
            pcall(function()
                local names = {}
                local at = Bridge.body:getAttachedItems()
                for i = 0, at:size() - 1 do
                    local it = at:getItemByIndex(i)
                    names[#names + 1] = tostring(it and at:getLocation(it)) .. "=" .. tostring(it and it:getFullType())
                end
                add("body_attached", #names > 0 and table.concat(names, ",") or "none")
            end)
            pcall(function() add("body_car", tostring(Bridge.body:getVehicle() ~= nil)) end)
            pcall(function() add("red_car", tostring(red ~= nil and red:getVehicle() ~= nil)) end)
            pcall(function() add("body_items", Bridge.body:getInventory():getItems():size()) end)
            pcall(function() add("body_worn", BridgeInventory.wornList(Bridge.body)) end)
            pcall(function() add("body_invisible", tostring(Bridge.body:isInvisible())) end)
            pcall(function() add("body_outfit", tostring(Bridge.body:getOutfitName())) end)
            pcall(function() add("body_square_ok", tostring(Bridge.body:getSquare() ~= nil)) end)
            pcall(function() add("body_visuals", tostring(Bridge.body:getItemVisuals():size()) .. "/" .. tostring(BridgeInventory.visualCount)) end)
            add("body_walk", BridgeMove.walkType .. " x" .. tostring(BridgeMove.speed) .. " red_moving=" .. tostring(BridgeMove.redMoving) .. " restarts=" .. tostring(BridgeMove.restarts))
            add("body_pathing", tostring(BridgeMove.pathing))
            add("body_moving", tostring(BridgeMove.moving))
            add("path_result", BridgeMove.pathResult)
            add("obstacle", BridgeMove.obstacle)
            pcall(function() add("doors", BridgeMove.doorInfo()) end)
            add("fight", tostring(BridgeFight.enabled) .. " " .. BridgeFight.state .. " " .. BridgeFight.info)
            add("fight_target", BridgeFight.targetInfo)
            add("fight_fatigue", string.format("%.2f miss=%.0f crowd=%d", BridgeFight.fatigue or 0, BridgeFight.lastMiss or 0, BridgeFight.crowd or 0))
            pcall(function() add("fight_near", BridgeFight.nearestInfo(Bridge.body)) end)

            pcall(function() add("heal_wait", tostring(BridgeHeal.waitWhy)) end)
            pcall(function() add("opt_redKit", tostring(BridgeData.optionOf(Bridge.store, "redKit"))) end)
            pcall(function() add("transfer_pending", tostring(BridgeInventory.pendingLogged) .. " " .. tostring(BridgeInventory.pendingWhy)) end)
            add("heal", BridgeHeal.state .. " " .. BridgeHeal.info)
            add("fire_out", tostring(Bridge.fireOut or 0))
            pcall(function() add("body_shoot", tostring(Bridge.body:isShootable())) end)
            add("pre_ticks", tostring(Bridge.preTicks or 0) .. "/" .. tostring(Bridge.preWas or 0))
            add("others_seen", tostring(Bridge.othersNear))
            add("body_seen", tostring(Bridge.bodySeen))
            add("panic_muted", tostring(Bridge.panicSaved ~= nil))
            add("scare", "stopped=" .. tostring(Bridge.scareStopped) .. " played=" .. tostring(Bridge.scareCount) .. " vol=" .. tostring(scareVolume()))
            pcall(function() add("red_visible_z", tostring(red:getStats():getNumVisibleZombies())) end)
            add("zombie_ticks", Bridge.zombieTicks)
            add("walk_60", string.format("%.2f", Bridge.walk60))
            add("red_60", string.format("%.2f", Bridge.red60))
            add("stuck", Bridge.stuckCount)
            add("engine_walk", string.format("%.2f", Bridge.engineWalk))
            add("held", tostring(Bridge.holdPos ~= nil))
            add("seat", BridgeMove.seatInfo or BridgeMove.seatText())
            pcall(function()
                local md = Bridge.store
                if md == nil then add("saved_items", "no store")
                else add("saved_items", tostring(md.items or "")) end
            end)
            if red ~= nil then
                add("dist", string.format("%.2f", dist2d(Bridge.body, red)))
            end
        else
            add("body_alive", 0)
        end

        pcall(function()
            local list = getCell():getZombieList()
            local near, mine = 0, 0
            if red ~= nil then
                for i = 0, list:size() - 1 do
                    local z = list:get(i)
                    local dx, dy = z:getX() - red:getX(), z:getY() - red:getY()
                    if math.sqrt(dx * dx + dy * dy) < 15 then
                        near = near + 1
                        if z:getVariableBoolean(BODY_VAR) then mine = mine + 1 end
                    end
                end
            end
            add("zombies_near", near)
            add("zombies_mine", mine)
            add("zombies_total", list:size())
        end)
        pcall(function() add("world", getWorld():getWorld()) end)

        if Bridge.mp then
            pcall(function()
                local md = Bridge.store
                local info = "no id"
                if md ~= nil and md.bodyId ~= nil then
                    info = "id=" .. tostring(md.bodyId) .. " not in client list, respawn asks=" .. tostring(Bridge.lostTries or 0)
                    local list = getCell():getZombieList()
                    for i = 0, list:size() - 1 do
                        local z = list:get(i)
                        if z ~= nil and z:getPersistentOutfitID() == md.bodyId then
                            local d = red and dist2d(z, red) or -1
                            info = string.format("found d=%.1f remote=%s marked=%s alive=%s", d,
                                tostring(z:isRemoteZombie()), tostring(z:getVariableBoolean(BODY_VAR)), tostring(z:isAlive()))
                            break
                        end
                    end
                end
                add("mp_body", info)
            end)
        end
        pcall(function() add("game_time", getGameTime():getTimeOfDay()) end)
        pcall(function() add("chat_ready", tostring(BridgeChat ~= nil and BridgeChat.ready)) end)
        pcall(function() add("chat_seq", tostring(BridgeChat and BridgeChat.seq or 0)) end)

        local writer = getFileWriter(OUT_FILE, true, false)
        for i = 1, #lines do writer:write(lines[i] .. "\r\n") end
        writer:close()
    end)
end





function Bridge.dropLostBody()
    local old = Bridge.body
    if old == nil or Bridge.mp then return false end
    local ours, inWorld = false, false
    pcall(function() ours = old:getVariableBoolean(BODY_VAR) end)
    pcall(function() inWorld = old:isExistInTheWorld() end)
    if not ours or not inWorld then return false end
    pcall(function() old:setPrimaryHandItem(nil) end)
    pcall(function() old:setSecondaryHandItem(nil) end)
    pcall(function() old:getWornItems():clear() end)
    pcall(function() old:getItemVisuals():clear() end)
    pcall(function() old:clearAttachedItems() end)
    pcall(function() old:clearItemsToSpawnAtDeath() end)
    pcall(function() old:getInventory():clear() end)
    pcall(function() BridgeInventory.forgetBody(old) end)
    pcall(function()
        old:removeFromWorld()
        old:removeFromSquare()
    end)
    Bridge.seen[old] = nil
    Bridge.body, Bridge.kind = nil, nil
    log("lost body still in the world: stripped and removed before a new one")
    return true
end





function Bridge.nowMs()
    local ms = nil
    pcall(function() ms = getTimestampMs() end)
    if type(ms) ~= "number" then ms = math.floor(Bridge.time * 1000 / 60) end
    return ms
end


function Bridge.spawnSelectorStagingAt(x, y)
    local ss = SpawnSelector
    if type(ss) ~= "table" or type(ss.STAGING_X) ~= "number" or type(ss.STAGING_Y) ~= "number" then return false end
    return math.floor(x) == ss.STAGING_X and math.floor(y) == ss.STAGING_Y
end


function Bridge.spawnSelectorStaging(red)
    local at = false
    pcall(function()
        if red:getModData().SpawnSelectorComplete == true then return end
        at = Bridge.spawnSelectorStagingAt(red:getX(), red:getY())
    end)
    return at
end



function Bridge.arrivalHoldStart(why)
    local grace = 15000
    pcall(function() if type(SpawnSelector.ARRIVAL_GRACE_MS) == "number" then grace = SpawnSelector.ARRIVAL_GRACE_MS end end)
    Bridge.arrivalHold = Bridge.nowMs() + grace + 500
    log(string.format("%s: Spawn Selector removes zombies around the arrival point for %.1f s, companion waits",
        tostring(why), grace / 1000))
end

function Bridge.ensurePresent()
    local red = BridgeData.owner()
    if red == nil then return end
    local okDead, deadRed = pcall(function() return red:isDead() end)
    if not okDead or deadRed then return end


    local complete = nil
    pcall(function() complete = red:getModData().SpawnSelectorComplete end)
    if Bridge.spawnSelectorStaging(red) then
        Bridge.ssComplete = complete
        Bridge.startTick = Bridge.time
        if Bridge.every(120) then log("companion waits: Spawn Selector staging area, zombies are removed there") end
        return
    end

    if complete == true and Bridge.ssComplete == false then Bridge.arrivalHoldStart("spawn point confirmed") end
    Bridge.ssComplete = complete
    if Bridge.arrivalHold ~= nil then
        local left = Bridge.arrivalHold - Bridge.nowMs()
        if left > 0 then
            Bridge.startTick = Bridge.time
            if Bridge.every(120) then
                log(string.format("companion waits: Spawn Selector removes zombies around the arrival point, %.1f s left", left / 1000))
            end
            return
        end
        Bridge.arrivalHold = nil

        Bridge.startTick = Bridge.time - APPEAR_DELAY
        log("Spawn Selector arrival safety is over: companion appears now")
    end


    local sqNow, sx, sy, sz = nil, -1, -1, -1
    pcall(function() sqNow = red:getCurrentSquare() end)
    if sqNow ~= nil then
        pcall(function() sx, sy, sz = sqNow:getX(), sqNow:getY(), sqNow:getZ() end)
        local w = Bridge.squareWatch
        if w == nil or w.sq ~= sqNow then
            local same = w ~= nil and w.x == sx and w.y == sy and w.z == sz
            Bridge.squareWatch = { sq = sqNow, x = sx, y = sy, z = sz, since = Bridge.time }
            if same then
                Bridge.startTick = Bridge.time
                if Bridge.every(120) then log("companion waits: the world under the player is being rebuilt") end
                return
            end
        end
    end
    if Bridge.startTick == nil then Bridge.startTick = Bridge.time return end

    if (Bridge.time - Bridge.startTick) < APPEAR_DELAY + (Bridge.spawnBackoff or 0) then return end



    local sq = nil
    pcall(function() sq = red:getCurrentSquare() end)
    if sq == nil then
        Bridge.startTick = Bridge.time
        if Bridge.every(120) then log("companion waits: player has no square yet") end
        return
    end

    local paused = false
    pcall(function() paused = UIManager.getSpeedControls():getCurrentGameSpeed() == 0 end)
    if paused then
        Bridge.startTick = Bridge.time
        if Bridge.every(120) then log("companion waits: game is paused") end
        return
    end


    local st = Bridge.store
    if st == nil or BridgeData.me() == nil or not BridgeData.wants(st) then return end
    if Bridge.alive() or Bridge.parked or Bridge.sleepParked ~= nil or Bridge.claimParked ~= nil or Bridge.respawnAt ~= nil
        or Bridge.spawnAsked ~= nil or Bridge.leaveAt ~= nil or Bridge.stash ~= nil then return end

    if Bridge.mp and (not Bridge.gotData or st.bodyId ~= nil or Bridge.released ~= nil) then return end



    if BridgeData.modeOf(st) ~= "follow" and st.waitX ~= nil then
        local dx, dy = red:getX() - st.waitX, red:getY() - st.waitY
        if math.sqrt(dx * dx + dy * dy) > HOME_NEAR or math.abs(red:getZ() - (st.waitZ or 0)) > 3 then return end
        Bridge.homeParked = false
        pcall(Bridge.dropLostBody)
        local res = Bridge.spawnZombie(st.waitX, st.waitY, st.waitZ)
        log("companion back at waiting place: " .. tostring(res))
        return
    end

    if red:getVehicle() ~= nil then
        if Bridge.mode == "follow" then pcall(function() BridgeCar.markInside(red, "appears in his car") end) end
        return
    end
    Bridge.greetOnReveal = true
    pcall(Bridge.dropLostBody)
    local res = Bridge.spawnZombie()
    log("companion appears: " .. tostring(res))
end








local LOST_AFTER = 180
local LOST_EXISTED = 600
local LOST_RETRY = { 180, 300, 600 }





function Bridge.dropStale(id)
    local n = 0
    if id == nil then return 0 end
    pcall(function()
        local list = getCell():getZombieList()
        local found = {}
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z ~= Bridge.body and z:getPersistentOutfitID() == id then found[#found + 1] = z end
        end
        for _, z in ipairs(found) do
            pcall(function() Bridge.unhumanize(z, true) end)
            pcall(function() z:removeFromSquare() end)
            pcall(function() z:removeFromWorld() end)
            n = n + 1
        end
    end)
    return n
end

function Bridge.bodyInClientList(id)
    if id == nil then return false end
    local found = false
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z:getPersistentOutfitID() == id then found = true break end
        end
    end)
    return found
end

local function lostReset()
    Bridge.lostId, Bridge.lostSince, Bridge.lostCall = nil, nil, nil
end

function Bridge.lostBodyCheck()
    local st = Bridge.store
    if not Bridge.mp or not Bridge.gotData or st == nil or st.bodyId == nil or not BridgeData.wants(st) then lostReset() return end

    if Bridge.alive() or Bridge.parked or Bridge.sleepParked ~= nil or Bridge.claimParked ~= nil or Bridge.leaveAt ~= nil
        or Bridge.released ~= nil or Bridge.respawnAt ~= nil or Bridge.stash ~= nil then lostReset() return end
    local red = BridgeData.owner()
    if red == nil then lostReset() return end
    local away = true
    pcall(function() away = red:isDead() or red:getVehicle() ~= nil or red:isAsleep() end)
    if away then lostReset() return end
    local waiting = BridgeData.modeOf(st) ~= "follow" and st.waitX ~= nil
    if waiting then

        local dx, dy = red:getX() - st.waitX, red:getY() - st.waitY
        if math.sqrt(dx * dx + dy * dy) > HOME_NEAR or math.abs(red:getZ() - (st.waitZ or 0)) > 3 then lostReset() return end
    end
    if Bridge.bodyInClientList(st.bodyId) then lostReset() return end
    if Bridge.lostId ~= st.bodyId then
        Bridge.lostId = st.bodyId
        Bridge.lostSince = Bridge.time

        if Bridge.askedNext then Bridge.askedId, Bridge.askedNext = st.bodyId, nil end



        local asked = Bridge.askedId ~= nil and Bridge.askedId == st.bodyId
        local after = (asked or Bridge.newLifePending == true) and LOST_AFTER or LOST_EXISTED
        Bridge.lostNext = math.max(Bridge.lostNext or 0, Bridge.time + after)
    end



    if Bridge.lostCall then
        Bridge.lostCall = nil
        Bridge.lostNext = math.max(Bridge.time, (Bridge.lostSince or Bridge.time) + LOST_AFTER)
    end
    if Bridge.time < Bridge.lostNext then return end
    Bridge.lostTries = (Bridge.lostTries or 0) + 1
    Bridge.lostNext = Bridge.time + LOST_RETRY[math.min(Bridge.lostTries, #LOST_RETRY)]
    local x, y, z
    if waiting then
        x, y, z = math.floor(st.waitX), math.floor(st.waitY), math.floor(st.waitZ or 0)
    else
        local rx, ry, rz = math.floor(red:getX()), math.floor(red:getY()), math.floor(red:getZ())
        x, y, z = Bridge.spawnSpot(rx, ry, rz, true)
        if x == nil then x, y, z = rx + 1, ry + 1, rz end
    end
    local loaded = false
    pcall(function() loaded = getCell():getGridSquare(x, y, z) ~= nil end)
    log(string.format("body id=%s not in client list for %.1f s, respawn ask %d at %d %d %d (square loaded=%s)",
        tostring(st.bodyId), (Bridge.time - Bridge.lostSince) / 60, Bridge.lostTries, x, y, z, tostring(loaded)))
    Bridge.spawnAsked = Bridge.time
    Bridge.askedNext = true

    Bridge.staleIds = Bridge.staleIds or {}
    Bridge.staleIds[st.bodyId] = Bridge.time

    pcall(function() sendClientCommand(red, "Bridge", "respawn", { id = st.bodyId, x = x, y = y, z = z, n = Bridge.lostTries,
        newLife = Bridge.newLifePending == true or nil }) end)
end








local TELEPORT_JUMP = 100
local TELEPORT_FAR = 150

function Bridge.pullOnTeleport()
    local red = BridgeData.owner()
    if red == nil then
        Bridge.redAt = nil
        return
    end
    local x, y = red:getX(), red:getY()
    local at = Bridge.redAt
    Bridge.redAt = { x = x, y = y }
    if at == nil then return end
    local dx, dy = x - at.x, y - at.y
    local d2 = dx * dx + dy * dy

    if d2 >= TELEPORT_JUMP * TELEPORT_JUMP and Bridge.spawnSelectorStagingAt(at.x, at.y) then
        Bridge.arrivalHoldStart("teleport from the Spawn Selector staging area")
    end
    if not Bridge.alive() or Bridge.kind ~= "zombie" then return end


    local far = false
    pcall(function()
        local bx, by = Bridge.body:getX() - x, Bridge.body:getY() - y
        far = bx * bx + by * by > TELEPORT_FAR * TELEPORT_FAR
    end)
    if d2 < TELEPORT_JUMP * TELEPORT_JUMP and not far then return end


    if Bridge.mode ~= "follow" then
        Bridge.parkAtHome()
        return
    end
    pcall(function() Bridge.saveOutfit() end)
    Bridge.despawn()
    Bridge.startTick = Bridge.time
    Bridge.result = "player jumped, body pulled"
    log(string.format("teleport: player jumped %.0f tiles (far=%s), body pulled", math.sqrt(d2), tostring(far)))
end



function Bridge.parkAtHome()
    if not Bridge.alive() or Bridge.kind ~= "zombie" or Bridge.mode == "follow" then return end
    local red = BridgeData.owner()
    if red == nil or dist2d(Bridge.body, red) <= HOME_FAR then return end
    local st = Bridge.store
    if st ~= nil and st.waitX == nil then
        st.waitX, st.waitY, st.waitZ = Bridge.body:getX(), Bridge.body:getY(), Bridge.body:getZ()
    end
    Bridge.saveOutfit()
    Bridge.homeParked = true
    Bridge.despawn()
    Bridge.result = "companion waits, player far"
    log(Bridge.result)
end







Bridge.drive = nil
local DRIVE_ROUTES = {
    line = { { 0, -15 }, { pause = 90 } },
    startstop = { { 0, -5 }, { pause = 40 }, { 0, -10 }, { pause = 40 }, { 0, -15 }, { pause = 90 } },
    zigzag = { { 3, -3 }, { -3, -6 }, { 3, -9 }, { -3, -12 }, { pause = 90 } },
    uturn = { { 0, -8 }, { pause = 20 }, { 0, 0 }, { pause = 90 } },
}
DRIVE_ROUTES.circle = (function()
    local t = {}
    for i = 1, 16 do
        local a = i / 16 * 2 * math.pi
        t[#t + 1] = { 4 * math.sin(a), -4 + 4 * math.cos(a) }
    end
    t[#t + 1] = { pause = 90 }
    return t
end)()

function Bridge.driveStart(route, gait)
    local red = BridgeData.owner()
    if red == nil then return "no player" end
    if route == "stop" then
        Bridge.drive = nil
        pcall(function() ISTimedActionQueue.clear(red) end)
        pcall(function() red:setRunning(false) red:setSneaking(false) end)
        return "drive stopped"
    end
    local items = DRIVE_ROUTES[route or ""]
    if route == "room" then


        local sq = red:getCurrentSquare()
        local building = sq and sq:getBuilding()
        if building == nil then return "drive room: stand inside a building" end
        local cell, z = getCell(), math.floor(red:getZ())
        local free = {}
        for dx = -8, 8 do
            for dy = -8, 8 do
                local s2 = cell:getGridSquare(math.floor(red:getX()) + dx, math.floor(red:getY()) + dy, z)
                if s2 ~= nil and s2:getBuilding() == building and s2:isFree(false) then
                    free[#free + 1] = { s2:getX() + 0.5 - red:getX(), s2:getY() + 0.5 - red:getY() }
                end
            end
        end
        if #free < 6 then return "drive room: too few free squares " .. #free end
        items = {}
        local px, py = 0, 0
        for i = 1, 10 do
            local pick = nil
            for try = 1, 40 do
                local c = free[ZombRand(#free) + 1]
                if (c[1] - px) ^ 2 + (c[2] - py) ^ 2 >= 9 then pick = c break end
            end
            if pick == nil then break end
            items[#items + 1] = { pick[1], pick[2] }
            px, py = pick[1], pick[2]
        end
        items[#items + 1] = { pause = 90 }
    end
    if items == nil then return "drive line|startstop|zigzag|circle|uturn|room walk|run|sneak | drive stop" end
    gait = gait or "walk"
    Bridge.drive = { items = items, idx = 1, gait = gait, ox = red:getX(), oy = red:getY(), oz = red:getZ(),
                     started = false, wait = 0, startTick = Bridge.tick }
    log("drive " .. route .. " " .. gait .. " from " .. string.format("%.1f %.1f", red:getX(), red:getY()))
    return "drive " .. route .. " " .. gait
end

function Bridge.driveStep()
    local dr = Bridge.drive
    if dr == nil then return end
    local red = BridgeData.owner()
    if red == nil then Bridge.drive = nil return end
    local item = dr.items[dr.idx]
    if item == nil then
        pcall(function() red:setRunning(false) red:setSneaking(false) end)
        log("drive done in " .. tostring(Bridge.tick - dr.startTick) .. " ticks")
        Bridge.drive = nil
        return
    end
    pcall(function()
        red:setSneaking(dr.gait == "sneak")
        red:setRunning(dr.gait == "run" and item.pause == nil)
    end)
    if item.pause ~= nil then
        dr.wait = dr.wait + 1
        if dr.wait >= item.pause then dr.idx, dr.wait, dr.started = dr.idx + 1, 0, false end
        return
    end
    if not dr.started then
        local ok, err = pcall(function()
            ISTimedActionQueue.add(ISPathFindAction:pathToLocationF(red, dr.ox + item[1], dr.oy + item[2], dr.oz))
        end)
        if not ok then warn("drive failed: " .. tostring(err)) Bridge.drive = nil return end
        dr.started, dr.wait = true, 0
        return
    end
    dr.wait = dr.wait + 1
    local busy = true
    pcall(function() busy = ISTimedActionQueue.isPlayerDoingAction(red) end)

    if (not busy and dr.wait > 5) or dr.wait > 1200 then
        dr.idx, dr.wait, dr.started = dr.idx + 1, 0, false
    end
end






local function carTick()
    if BridgeCar == nil then return end
    local ok, err = pcall(BridgeCar.tick)
    if not ok and Bridge.every(600) then warn("car tick failed: " .. tostring(err)) end
end




function Bridge.every(n, phase)
    phase = phase or 0
    return math.floor((Bridge.time - phase) / n) > math.floor((Bridge.prevTime - phase) / n)
end

function Bridge.onTick()
    Bridge.tick = Bridge.tick + 1
    local dt = 1
    pcall(function() dt = getGameTime():getRealworldSecondsSinceLastUpdate() * 60 end)
    if type(dt) ~= "number" or dt ~= dt or dt <= 0 then dt = 1 end
    if dt > 5 then dt = 5 end
    Bridge.dt = dt
    Bridge.prevTime = Bridge.time
    Bridge.time = Bridge.time + dt
    if BridgeBackup ~= nil then pcall(BridgeBackup.tick) end
    pcall(Bridge.mournTick)
    if Bridge.corpseWatch ~= nil then pcall(Bridge.corpseSweep) end
    pcall(Bridge.newLifeTick)
    if Bridge.swingSpy ~= nil then pcall(Bridge.spyTick) end

    Bridge.clockFrames = (Bridge.clockFrames or 0) + 1
    if Bridge.every(600) then
        local span = Bridge.time - (Bridge.clockFrom or 0)
        vlog(string.format("clock: frames=%d time=%.1f dt=%.3f fps=%.0f", Bridge.clockFrames, span,
            span / Bridge.clockFrames, 60 * Bridge.clockFrames / math.max(span, 1)))
        Bridge.clockFrames, Bridge.clockFrom = 0, Bridge.time
    end
    pcall(Bridge.driveStep)
    pcall(Bridge.pullOnTeleport)
    carTick()




    if Bridge.drivable() then
        local red = BridgeData.owner()
        if red ~= nil then
            local spy = Bridge.walkSpy
            if spy == nil or (Bridge.tick - spy.tick) >= 60 then
                if spy ~= nil then
                    local bdx = Bridge.body:getX() - spy.bx
                    local bdy = Bridge.body:getY() - spy.by
                    local rdx = red:getX() - spy.rx
                    local rdy = red:getY() - spy.ry
                    Bridge.walk60 = math.sqrt(bdx * bdx + bdy * bdy)
                    Bridge.red60 = math.sqrt(rdx * rdx + rdy * rdy)
                    Bridge.engineWalk = Bridge.engineAcc
                    Bridge.engineAcc = 0



                    local far = math.sqrt((Bridge.body:getX() - red:getX()) ^ 2
                                        + (Bridge.body:getY() - red:getY()) ^ 2) > 3
                    local trying = BridgeMove.pathing or BridgeMove.moving



                    local climbingNow = BridgeMove.cross ~= nil or Bridge.time < (BridgeMove.climbUntil or 0)
                    pcall(function()
                        if engineState(tostring(Bridge.body:getActionStateName())) then climbingNow = true end
                    end)
                    if climbingNow then Bridge.stuckCount = 0 end



                    local fightingNow = false
                    pcall(function() fightingNow = BridgeFight.target ~= nil or BridgeFight.state == "swing" end)
                    if fightingNow then Bridge.stuckCount = 0 end


                    if BridgeCar ~= nil and BridgeCar.busy() then
                        fightingNow = true
                        Bridge.stuckCount = 0
                    end
                    if far and trying and not climbingNow and not fightingNow and Bridge.walk60 < 0.3 then
                        Bridge.stuckCount = Bridge.stuckCount + 1
                        if Bridge.stuckCount >= 3 and Bridge.follow and Bridge.mode == "follow" then
                            Bridge.stuckCount = 0
                            pcall(function()
                                log(string.format("stuck, teleporting: st=%s bump=%s obstacle=%s path=%s",
                                    tostring(Bridge.body:getActionStateName()), tostring(Bridge.body:getBumpType()),
                                    tostring(BridgeMove.obstacle), tostring(BridgeMove.pathResult)))
                            end)
                            Bridge.teleportToRed()
                        end
                    else
                        Bridge.stuckCount = 0
                    end
                end
                Bridge.walkSpy = { tick = Bridge.tick, bx = Bridge.body:getX(), by = Bridge.body:getY(),
                                   rx = red:getX(), ry = red:getY() }
            end
        end
    end



    if Bridge.follow and Bridge.mode == "follow" and Bridge.tick % 60 == 0 and Bridge.drivable()
        and not (BridgeCar ~= nil and BridgeCar.busy()) then
        local red = BridgeData.owner()
        if red ~= nil then
            local dx = Bridge.body:getX() - red:getX()
            local dy = Bridge.body:getY() - red:getY()
            if math.sqrt(dx * dx + dy * dy) > 20 then Bridge.teleportToRed() end
        end
    end

    if Bridge.every(60) then Bridge.ensurePresent() end


    if Bridge.every(60, 10) then pcall(Bridge.goneCheck) end
    if Bridge.mp and Bridge.every(30, 15) then pcall(Bridge.lostBodyCheck) end

    if Bridge.target ~= nil and Bridge.targetSince ~= nil and (Bridge.time - Bridge.targetSince) > 900 then
        Bridge.target = nil
        Bridge.targetSince = nil
        Bridge.waitRetryAt = Bridge.time + 3600
        log("waiting place not reachable")
    end
    if Bridge.every(60, 30) then
        Bridge.bodiesSeen()
        Bridge.parkAtHome()
    end

    if Bridge.leaveAt ~= nil and Bridge.time >= Bridge.leaveAt then
        Bridge.leaveAt = nil
        log("left after goodbye")

        pcall(function() Bridge.saveOutfit() end)
        Bridge.despawnByCommand = true
        Bridge.despawn()
        Bridge.despawnByCommand = false
    end
    if Bridge.spawnAsked ~= nil and (Bridge.time - Bridge.spawnAsked) > 600 then Bridge.spawnAsked = nil end

    if Bridge.mp and Bridge.released ~= nil and (Bridge.time - Bridge.releasedTick) > 300 then
        if Bridge.store ~= nil and Bridge.store.bodyId == Bridge.released and Bridge.isOwner() then
            Bridge.releasedTick = Bridge.time
            pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "despawn", { byCommand = Bridge.releasedByCommand, id = Bridge.released }) end)
            log("despawn repeated: server still has body " .. tostring(Bridge.released))
        else
            Bridge.released = nil
        end
    end


    if BridgeBandits ~= nil and BridgeBandits.corpseTick ~= nil then pcall(BridgeBandits.corpseTick) end






    if Bridge.respawnAt ~= nil and Bridge.time >= Bridge.respawnAt then
        Bridge.respawnAt = nil
        Bridge.result = "body back after death"
    end




    if Bridge.sleepParked ~= nil and Bridge.every(30) and not (BridgeSleep ~= nil and BridgeSleep.pending ~= nil) then
        local red = BridgeData.owner()
        local awake = false
        pcall(function() awake = red ~= nil and not red:isAsleep() end)
        if awake and not Bridge.alive() then
            local at = Bridge.sleepParked
            Bridge.sleepParked = nil
            local res
            if at.mode == "follow" then
                res = Bridge.spawnZombie()
            else
                res = Bridge.spawnZombie(at.x, at.y, at.z)
            end
            Bridge.result = "body back after sleep: " .. tostring(res)
            log("body back after sleep")
        elseif awake then
            Bridge.sleepParked = nil
        end
    end


    if Bridge.claimParked ~= nil and Bridge.every(15) then pcall(Bridge.claimTick) end



    if Bridge.parked and Bridge.every(30) and not (BridgeCar ~= nil and BridgeCar.busy()) then
        local red = BridgeData.owner()
        if red ~= nil and red:getVehicle() == nil and not Bridge.alive() then
            Bridge.parked = false
            local res = Bridge.spawnZombie()
            Bridge.result = "body back after car: " .. tostring(res)
            log("body back after car")
        end
    end


    if Bridge.stash ~= nil and (Bridge.time - Bridge.stashAt) > 60 then
        Bridge.onPostSave()
    end


    if (Bridge.time - Bridge.verboseCheckTick) >= 300 then
        Bridge.verboseCheckTick = Bridge.time
        local on = false
        pcall(function()
            local reader = getFileReader(VERBOSE_FILE, false)
            if reader ~= nil then
                on = true
                reader:close()
            end
        end)
        if on ~= Bridge.verbose then
            Bridge.verbose = on
            log("verbose log " .. (on and "on" or "off"))
        end
    end

    if (Bridge.time - Bridge.bridgeCheckTick) >= 300 then
        Bridge.bridgeCheckTick = Bridge.time
        local on = false
        pcall(function()
            local reader = getFileReader(IN_FILE, false)
            if reader ~= nil then
                on = true
                reader:close()
            end
        end)
        if on ~= Bridge.bridgeOn then
            Bridge.bridgeOn = on
            log("bridge " .. (on and "on" or "off"))
        end
    end
    if Bridge.bridgeOn then
        if Bridge.every(READ_EVERY) then Bridge.readCommands() end
        if Bridge.every(WRITE_EVERY) then Bridge.writeState() end
    end

    if Bridge.kind == "player" and Bridge.alive() then
        updatePlayerBody()
    end
end







function Bridge.onSave()
    if Bridge.mp then return end
    if not Bridge.alive() or Bridge.kind ~= "zombie" then return end

    if Bridge.mourning ~= nil then
        Bridge.mournEnd("save")
        return
    end

    pcall(Bridge.guardOutfit, Bridge.body)
    Bridge.saveOutfit()
    Bridge.stash = { items = BridgeInventory.snapshot(Bridge.body), mode = Bridge.mode,
                     x = Bridge.body:getX(), y = Bridge.body:getY(), z = Bridge.body:getZ(),
                     follow = Bridge.follow, pose = Bridge.pose, fight = BridgeFight.enabled,
                     guardOnly = BridgeFight.guardOnly, target = Bridge.target }
    Bridge.stashAt = Bridge.time
    Bridge.despawn()
    Bridge.result = "body hidden for save"
    log("body hidden for save")
end





function Bridge.onPostSave()
    if Bridge.stash == nil then return end
    if Bridge.alive() then Bridge.stash = nil return end
    local stash = Bridge.stash
    Bridge.stash = nil

    local res = Bridge.spawnZombie(stash.x, stash.y, stash.z)
    if Bridge.alive() then
        pcall(function() BridgeInventory.restore(Bridge.body, stash.items) end)

        Bridge.applyStoredMode()
        if stash.follow == false then Bridge.follow = false end
        Bridge.target = stash.target
        if stash.pose ~= nil then Bridge.pose = stash.pose end
        if stash.fight ~= nil then BridgeFight.enabled = stash.fight end
        if stash.guardOnly ~= nil then BridgeFight.guardOnly = stash.guardOnly end
    end
    Bridge.result = "body back after save: " .. tostring(res)
    log("body back after save")
end

Bridge.skipOldCommands()











local CLAIM_WAIT = 180



local function claimRect(square)
    local def = nil
    pcall(function() def = square:getBuilding():getDef() end)
    if def == nil then return nil end
    return def:getX() - 2, def:getY() - 2, def:getX2() + 2, def:getY2() + 2
end





function Bridge.claimBlockers(square, playerObj)
    local x1, y1, x2, y2 = claimRect(square)
    if x1 == nil then return nil, 0, 0, {} end
    local function inside(o)
        local x, y = o:getX(), o:getY()
        return x >= x1 and x < x2 and y >= y1 and y < y2
    end
    local mine, others, companions, strays = false, 0, 0, {}
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and inside(z) then
                local own = z == Bridge.body
                if not own and Bridge.store ~= nil and Bridge.store.bodyId ~= nil then
                    pcall(function() own = z:getPersistentOutfitID() == Bridge.store.bodyId end)
                end
                if own then mine = true
                elseif Bridge.isCompanion(z) then
                    companions = companions + 1
                    local s = Bridge.strays[z]
                    if s ~= nil and #strays < 20 then strays[#strays + 1] = s.pid end
                else others = others + 1 end
            end
        end
    end)
    pcall(function()
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p ~= nil and p ~= playerObj and inside(p) then others = others + 1 end
        end
    end)
    return mine, others, companions, strays
end

local function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end


function Bridge.claimMenuFix(playerNum, context, worldobjects, test)
    if test or not Bridge.mp or Bridge.claimParked ~= nil then return end
    local opt = context:getOptionFromName(getText("ContextMenu_SafehouseClaim"))
    if opt == nil or not opt.notAvailable or opt.toolTip == nil then return end

    if trim(opt.toolTip.description) ~= trim(getText("IGUI_Safehouse_SomeoneInside")) then return end
    local mine, others, companions = Bridge.claimBlockers(opt.param1, getSpecificPlayer(opt.param2))
    mine = mine == true and Bridge.alive()
    if others > 0 or not (mine or (companions or 0) > 0) then
        log(string.format("claim: building busy, her=%s others=%d companions=%d, left to the game", tostring(mine), others,
            companions or 0))
        return
    end
    opt.notAvailable = false
    opt.toolTip = nil
    opt.onSelect = Bridge.claimSafehouse
    log(string.format("claim: only companions in the building (hers=%s, others' %d), claim option enabled", tostring(mine),
        companions or 0))
end


function Bridge.claimSafehouse(worldobjects, square, player)
    local body = Bridge.body
    if not Bridge.mp or Bridge.claimParked ~= nil then
        return ISWorldObjectContextMenu.onTakeSafeHouse(worldobjects, square, player)
    end


    local x1, y1, x2, y2 = claimRect(square)
    local mine, _, companions, strays = Bridge.claimBlockers(square, getSpecificPlayer(player))

    local own = mine == true and Bridge.alive() and body ~= nil
    if not own and (companions or 0) == 0 then
        return ISWorldObjectContextMenu.onTakeSafeHouse(worldobjects, square, player)
    end
    Bridge.claimParked = { square = square, player = player, since = Bridge.time, own = own,
        wait = (own and 1 or 0) + ((companions or 0) > 0 and 1 or 0) }
    if (companions or 0) > 0 and x1 ~= nil then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "claimClear", { x1 = x1, y1 = y1, x2 = x2, y2 = y2, strays = strays }) end)
        log(string.format("claim: asked the server to take away %d other companions for the claim", companions))
    end
    if own then
        Bridge.saveOutfit()
        local c = Bridge.claimParked
        c.x, c.y, c.z, c.mode = body:getX(), body:getY(), body:getZ(), Bridge.mode
        log(string.format("claim: hiding her at %.2f %.2f for the claim", body:getX(), body:getY()))
        Bridge.despawn()
    end
    Bridge.result = "claim: companions hidden, waiting for the server"
end



function Bridge.claimAnswer()
    local c = Bridge.claimParked
    if c == nil then return end
    c.wait = (c.wait or 1) - 1
    if c.wait <= 0 then Bridge.claimSend() end
end


function Bridge.claimSend()
    local c = Bridge.claimParked
    if c == nil or c.sent ~= nil then return end
    c.sent = Bridge.time
    local playerObj = getSpecificPlayer(c.player)
    local ok, err = pcall(function() sendSafehouseClaim(c.square, playerObj, playerObj:getUsername()) end)
    log("claim: sent " .. (ok and "" or ("failed: " .. tostring(err))))
end



function Bridge.claimReturn(why)
    local at = Bridge.claimParked
    if at == nil then return end
    local res = "already here"
    if at.own == false then
        res = "no own body"
    elseif not Bridge.alive() then
        if at.mode == "follow" then res = Bridge.spawnZombie() else res = Bridge.spawnZombie(at.x, at.y, at.z) end
    end
    Bridge.claimParked = nil
    log("claim: " .. tostring(why) .. ", body back: " .. tostring(res))
    Bridge.result = "claim: " .. tostring(why)
end



function Bridge.claimTick()
    local c = Bridge.claimParked
    if c == nil then return end
    if c.sent == nil then
        if Bridge.time - c.since > CLAIM_WAIT then Bridge.claimReturn("no reply from the server, claim not sent") end
        return
    end
    local done = false
    pcall(function() done = SafeHouse.getSafeHouse(c.square) ~= nil end)
    if done then
        Bridge.claimReturn("building claimed")
    elseif Bridge.time - c.sent > CLAIM_WAIT then
        Bridge.claimReturn("claim not confirmed in 3 s")
    end
end

function Bridge.onServerCommand(module, command, args)
    if module ~= "Bridge" then return end
    args = args or {}
    if command == "spawned" then

        if type(args.iseq) == "number" then Bridge.iseq = args.iseq end

        if args.newLife then Bridge.newLifePending = nil end
        Bridge.result = "server spawned body id=" .. tostring(args.id) .. (args.existed and " (existed)" or "")
        log(Bridge.result)

        if args.existed and not Bridge.alive() and not Bridge.bodyInClientList(args.id) then Bridge.lostCall = true end


        if not args.existed and args.id ~= nil then Bridge.askedId, Bridge.askedNext = args.id, nil end
        if args.existed then Bridge.askedNext = nil end
    elseif command == "stale" then

        if args.id ~= nil then
            Bridge.staleIds = Bridge.staleIds or {}
            Bridge.staleIds[args.id] = Bridge.time
            local n = Bridge.dropStale(args.id)
            Bridge.result = "server dropped body id=" .. tostring(args.id) .. ", removed here: " .. tostring(n)
            log(Bridge.result)
        end
    elseif command == "despawned" then
        Bridge.result = "server despawned body, found=" .. tostring(args.found)
        if Bridge.claimParked ~= nil then Bridge.claimAnswer() end
    elseif command == "claimCleared" then
        Bridge.result = "server took away " .. tostring(args.n) .. " companions for the claim"
        log(Bridge.result)
        if Bridge.claimParked ~= nil then Bridge.claimAnswer() end
    elseif command == "error" then
        Bridge.result = "server: " .. tostring(args.text)
        log(Bridge.result)
    elseif command == "gave" then
        local ok, res = pcall(function() return BridgeInventory.receive(args) end)
        Bridge.result = "gave: " .. tostring(ok and res or ("error " .. tostring(res)))
        log(Bridge.result)
    elseif command == "took" then
        pcall(function() BridgeInventory.took(args) end)
        Bridge.result = "took: " .. tostring(args.ok) .. " " .. tostring(args.why or "")
    elseif command == "look" then
        pcall(function() Bridge.lookSwing(args) end)
    elseif command == "carSeat" then
        pcall(function() BridgeCar.onSeat(args) end)
    elseif command == "gifted" then
        pcall(function() BridgeSocial.onGifted(args) end)
    elseif command == "mood" then
        pcall(function() BridgeMood.onApplied(args) end)
    elseif command == "giveFailed" then
        pcall(function() BridgeInventory.giveFailed(args) end)
        Bridge.result = "give failed: " .. tostring(args.why)
    elseif command == "say" and args.text ~= nil then
        local name = args.name or BridgeData.DEFAULT_NAME
        if args.chat ~= false then
            pcall(function() BridgeChat.addLine(name, args.text, 0.95, 0.55, 0.75) end)
        elseif args.owner ~= BridgeData.me() then

            local shown = false
            for z, info in pairs(Bridge.bodiesSeen()) do
                local hidden = false
                pcall(function() hidden = z:isInvisible() end)
                if info.who == args.owner and not hidden and BridgeData.overheadOk(args.text) then
                    pcall(function() z:addLineChatElement(args.text, 0.95, 0.55, 0.75) end)
                    if BridgeName ~= nil then BridgeName.spoke(z) end
                    shown = true
                end
            end

            if not shown and args.car then
                if not BridgeData.overheadOk(name) then name = BridgeData.DEFAULT_NAME end
                local line = tostring(name) .. ": " .. tostring(args.text)
                local p = nil
                pcall(function() p = getPlayerFromUsername(args.owner) end)
                if p ~= nil and BridgeData.overheadOk(line) then
                    pcall(function() p:addLineChatElement(line, 0.95, 0.55, 0.75) end)
                end
            end
        end
    end
end

Events.OnServerCommand.Add(Bridge.onServerCommand)
Events.OnReceiveGlobalModData.Add(Bridge.onReceiveGlobalModData)
Events.OnInitGlobalModData.Add(Bridge.initStore)
Events.OnGameStart.Add(Bridge.initStore)
Events.OnSave.Add(Bridge.onSave)
Events.OnTick.Add(Bridge.onTick)
Events.OnPlayerUpdate.Add(Bridge.onPlayerUpdate)
Events.OnZombieUpdate.Add(Bridge.onZombieUpdate)


Events.OnGameStart.Add(function()
    pcall(function()
        Events.OnZombieUpdate.Remove(Bridge.onZombieUpdate)
        Events.OnZombieUpdate.Add(Bridge.onZombieUpdate)
    end)
end)








Events.OnHitZombie.Add(Bridge.onHitZombie)
Events.OnWeaponSwing.Add(function(owner, weapon)
    Bridge.protectBodies()
    pcall(function() Bridge.spySwing(owner, weapon) end)
end)
Events.OnWeaponSwingHitPoint.Add(function() Bridge.protectBodies() end)
Events.OnZombieDead.Add(Bridge.onZombieDead)





















Bridge.MOURN_SEE = 20
Bridge.MOURN_REACT = 90
Bridge.MOURN_NEAR = 1.6
Bridge.MOURN_WALK_MAX = 480

Bridge.MOURN_LEAVE_MAX = 120
Bridge.MOURN_HIDE = 15
Bridge.MOURN_STALL = 45
Bridge.MOURN_THREAT = 6
Bridge.MOURN_THREAT_CLOSE = 2.5

function Bridge.redDead(red)
    if red == nil then return false end
    local dead = false
    pcall(function() dead = red:isDead() end)
    return dead == true
end


function Bridge.mournAware(body, red)
    if red == nil or body == nil then return false end
    if Bridge.follow or Bridge.mode == "follow" then return true end
    local near = false
    pcall(function()
        local dx, dy = body:getX() - red:getX(), body:getY() - red:getY()
        near = dx * dx + dy * dy <= Bridge.MOURN_SEE * Bridge.MOURN_SEE and math.abs(body:getZ() - red:getZ()) < 1
    end)
    return near
end


function Bridge.ownerZombie(red)
    local m = Bridge.mourning
    if m == nil then return nil end
    if m.risen ~= nil then
        local alive = false
        pcall(function() alive = m.risen:isAlive() end)
        if alive then return m.risen end
        m.risen = nil
    end
    if not Bridge.every(30) then return nil end
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z:isAlive() and BridgeFight.ownerRisen(z, red) then m.risen = z break end
        end
    end)
    if m.risen ~= nil and not m.risenLogged then
        m.risenLogged = true
        log("player rose as a zombie: she runs, does not fight him")
    end
    return m.risen
end




function Bridge.mournThreat(body, red)
    local m = Bridge.mourning
    if m == nil then return nil end
    if not Bridge.every(15) then return m.threat end
    local pn = 0
    pcall(function() pn = red:getPlayerNum() end)
    local found = nil
    pcall(function()
        local bx, by, bz = body:getX(), body:getY(), body:getZ()
        local rx, ry = red:getX(), red:getY()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z ~= body and z:isAlive() and not z:getVariableBoolean(BODY_VAR)
                and not BridgeData.harmless(z) and math.abs(z:getZ() - bz) < 1 then
                local zx, zy = z:getX(), z:getY()
                local dHer = math.sqrt((zx - bx) ^ 2 + (zy - by) ^ 2)
                local dHim = math.sqrt((zx - rx) ^ 2 + (zy - ry) ^ 2)
                if dHer < Bridge.MOURN_THREAT_CLOSE then found = z break end
                if dHer < Bridge.MOURN_THREAT or dHim < Bridge.MOURN_THREAT then
                    local seen = true
                    local sq = z:getCurrentSquare()
                    if sq ~= nil then seen = sq:isCanSee(pn) end
                    if seen then found = z break end
                end
            end
        end
    end)
    m.threat = found
    return found
end





function Bridge.mournHidden(body, red)
    local pn = 0
    pcall(function() pn = red:getPlayerNum() end)
    local sq = nil
    pcall(function() sq = body:getCurrentSquare() end)
    if sq == nil then return false end
    local seen = true
    pcall(function() seen = sq:isCanSee(pn) end)
    if not seen then return true end
    if isoToScreenX == nil or getPlayerScreenLeft == nil then return false end
    local off = false
    pcall(function()
        local x, y, z = body:getX(), body:getY(), body:getZ()
        local sx, sy = isoToScreenX(pn, x, y, z), isoToScreenY(pn, x, y, z)
        local l, t = getPlayerScreenLeft(pn), getPlayerScreenTop(pn)
        local w, h = getPlayerScreenWidth(pn), getPlayerScreenHeight(pn)

        off = sx < l - 60 or sx > l + w + 60 or sy < t - 10 or sy > t + h + 200
    end)
    return off
end










local LEAVE_DIST = { 1.5, 2, 2.5, 3, 4, 5, 6, 8 }
local LEAVE_RING = { 2, 3, 4, 5, 6, 8 }
local function leavePoint(body, red, m, fx, fy, bad)
    local bx, by, bz = body:getX(), body:getY(), body:getZ()
    local ax, ay = bx - fx, by - fy
    local al = math.sqrt(ax * ax + ay * ay)
    if al < 0.05 then ax, ay, al = 1, 0, 1 end
    ax, ay = ax / al, ay / al
    local pn = 0
    pcall(function() pn = red:getPlayerNum() end)
    local cell = getCell()
    local function pick(dists, straight)
        local best, bestScore = nil, nil
        for k = 0, 15 do
            local a = k * math.pi / 8
            local ux, uy = math.cos(a), math.sin(a)
            local away = ux * ax + uy * ay

            if away > -0.2 then
                for _, dist in ipairs(dists) do
                    local tx, ty = bx + ux * dist, by + uy * dist
                    local skip = false
                    for _, b in ipairs(bad or {}) do
                        if (tx - b.x) ^ 2 + (ty - b.y) ^ 2 < 2.25 then skip = true break end
                    end
                    local sq = nil
                    if not skip then pcall(function() sq = cell:getGridSquare(math.floor(tx), math.floor(ty), math.floor(bz)) end) end
                    local free = false
                    if sq ~= nil then pcall(function() free = sq:isFree(false) end) end
                    local ok = free
                    if ok and straight then
                        ok = BridgeMove.lineClear(body, tx, ty, bz)
                        if ok and m.spot ~= nil then
                            local crosses = false
                            pcall(function() crosses = BridgeMove.mournCrosses(m.spot, bx, by, tx, ty) end)
                            ok = not crosses
                        end
                    end
                    if ok then
                        local hidden = false
                        pcall(function() hidden = not sq:isCanSee(pn) end)
                        local fromHim = math.sqrt((tx - red:getX()) ^ 2 + (ty - red:getY()) ^ 2)
                        local score = (hidden and 100 or 0) + 10 * away + fromHim + 0.5 * dist
                        if bestScore == nil or score > bestScore then
                            best, bestScore = { x = tx, y = ty, z = bz, hidden = hidden, path = not straight }, score
                        end
                    end
                end
            end
        end
        return best
    end
    return pick(LEAVE_DIST, true) or pick(LEAVE_RING, false)
end

function Bridge.mournStart(body, red)
    Bridge.mourning = { since = Bridge.time, said = false, phase = "react", follow = Bridge.follow }
    pcall(function() BridgeHeal.stop("player died") end)
    pcall(function() BridgeWash.stop("player died") end)
    pcall(function() BridgeMove.stopPath(body) end)

    Bridge.pose = nil
    pcall(function() BridgeMove.seatGuard(body) end)

    Bridge.follow = false
    Bridge.target = nil
    Bridge.result = "player died: mourning"
    local d = -1
    pcall(function() d = math.sqrt((body:getX() - red:getX()) ^ 2 + (body:getY() - red:getY()) ^ 2) end)
    log(string.format("player died: mourning, %.1f from him, mode %s", d, tostring(Bridge.mode)))
end



function Bridge.mournGo(body, red, m, how, fx, fy, why)
    pcall(function() BridgeMove.stopPath(body) end)
    Bridge.pose = nil
    m.phase = how
    m.leaveSince = m.leaveSince or Bridge.time
    m.fromX, m.fromY = fx, fy
    m.hiddenSince = nil
    Bridge.holdPos = nil
    BridgeMove.forcedWalk = (how == "run") and "Run" or "Walk"
    m.bad = m.bad or {}
    Bridge.target = leavePoint(body, red, m, fx, fy, m.bad)
    m.progX, m.progY, m.progAt = body:getX(), body:getY(), Bridge.time
    local t = Bridge.target
    log(string.format("mourning: %s (%s), to %s", how, tostring(why),
        t and string.format("%.1f,%.1f %.1f away%s%s", t.x, t.y, math.sqrt((t.x - body:getX()) ^ 2 + (t.y - body:getY()) ^ 2),
            t.hidden and ", out of his sight" or "", t.path and ", engine path" or ", straight") or "nowhere, vanishes"))
end



function Bridge.mournLeave(body, red, m)

    if m.phase == "leave" then
        local t = Bridge.ownerZombie(red) or Bridge.mournThreat(body, red)
        if t ~= nil then
            local tx, ty = red:getX(), red:getY()
            pcall(function() tx, ty = t:getX(), t:getY() end)
            Bridge.mournGo(body, red, m, "run", tx, ty, "zombie while leaving")
        end
    end
    if Bridge.time - m.leaveSince >= Bridge.MOURN_LEAVE_MAX then
        Bridge.mournVanish(string.format("left for %.0f s", Bridge.MOURN_LEAVE_MAX / 60))
        return true
    end
    if Bridge.every(5) then
        if Bridge.mournHidden(body, red) then
            m.hiddenSince = m.hiddenSince or Bridge.time
            if Bridge.time - m.hiddenSince >= Bridge.MOURN_HIDE then
                Bridge.mournVanish(string.format("out of sight after %.1f s", (Bridge.time - m.leaveSince) / 60))
                return true
            end
        else
            m.hiddenSince = nil
        end
    end


    if Bridge.target ~= nil and Bridge.time - (m.progAt or Bridge.time) >= Bridge.MOURN_STALL then
        local moved = math.sqrt((body:getX() - m.progX) ^ 2 + (body:getY() - m.progY) ^ 2)
        if moved < 0.3 then


            log(string.format("mourning: stuck on the way out at %.1f,%.1f", body:getX(), body:getY()))
            Bridge.mournVanish("stuck on the way out")
            return true
        end
        m.progX, m.progY, m.progAt = body:getX(), body:getY(), Bridge.time
    end
    if Bridge.target == nil then

        Bridge.target = leavePoint(body, red, m, m.fromX, m.fromY, m.bad)
        m.progX, m.progY, m.progAt = body:getX(), body:getY(), Bridge.time
        if Bridge.target == nil then
            Bridge.mournVanish("nowhere to go")
            return true
        end
    end
    return false
end




function Bridge.mournVanish(why)
    Bridge.mourning = nil
    BridgeMove.forcedWalk = nil
    Bridge.target = nil
    Bridge.pose = nil
    Bridge.follow = (Bridge.mode == "follow")
    if Bridge.alive() and Bridge.kind == "zombie" then
        Bridge.saveOutfit()
        Bridge.despawn()
        Bridge.result = "body hidden: player died"
        log("body hidden: player died (" .. tostring(why) .. ")")
    end
end



function Bridge.mournFrame(body, red)
    if Bridge.mourning == nil then Bridge.mournStart(body, red) end
    local m = Bridge.mourning

    if not m.said and Bridge.time - m.since >= 20 then
        m.said = true
        local text = nil
        pcall(function() text = BridgeMoments.line("EvRedDied") end)
        if text ~= nil and text ~= "" then pcall(function() Bridge.speakText(text) end) end
    end
    if m.phase == "leave" or m.phase == "run" then return Bridge.mournLeave(body, red, m) end

    local oz = Bridge.ownerZombie(red)
    local threat = oz or Bridge.mournThreat(body, red)
    if threat ~= nil then
        local tx, ty = red:getX(), red:getY()
        pcall(function() tx, ty = threat:getX(), threat:getY() end)
        Bridge.mournGo(body, red, m, "run", tx, ty, oz and "his zombie" or "zombies")
        return Bridge.mournLeave(body, red, m)
    end







    if m.phase == "react" and Bridge.time - m.since < Bridge.MOURN_REACT then
        if BridgeMove.onPath() then pcall(function() BridgeMove.stopPath(body) end) end
        BridgeMove.moving = false
        BridgeMove.pivotToward(body, red:getX(), red:getY(), BridgeMove.MOURN_PIVOT_DEG)
        return true
    end


    if m.phase ~= "walk" and m.phase ~= "turn" and m.phase ~= "stand" then
        m.phase = "walk"
        m.walkSince = Bridge.time
        m.spot = nil
        pcall(function() m.spot = BridgeMove.corpseLine(red) end)
        Bridge.target = nil
        local d = math.sqrt((body:getX() - red:getX()) ^ 2 + (body:getY() - red:getY()) ^ 2)
        local onD = -1
        if m.spot ~= nil then onD = BridgeMove.mournBodyDist(m.spot, body:getX(), body:getY()) end
        log(string.format("mourning: %.2f from his point, %.2f from his body, %s", d, onD,
            m.spot and (m.spot.front and "face down" or "on his back") or "no corpse line"))
    end
    if m.phase == "walk" then
        local how = Bridge.mournApproach(body, red, m)
        if how == "engine" then return false end
        if how == "own" then return true end

        Bridge.target = nil
        pcall(function() BridgeMove.stopPath(body) end)
        BridgeMove.moving = false
        m.phase = "turn"
        m.turnSince = Bridge.time
    end

    local fx, fy = red:getX(), red:getY()
    if m.spot ~= nil then fx, fy = m.spot.cx, m.spot.cy end
    if m.phase == "turn" then
        local left = BridgeMove.pivotToward(body, fx, fy, BridgeMove.MOURN_PIVOT_DEG)
        if left ~= nil and left > math.rad(4) and Bridge.time - m.turnSince < 45 then return true end
        m.phase = "stand"
        m.standSince = Bridge.time




        if not m.gestured then
            m.gestured = true
            pcall(function() body:setBumpType("PainHead") end)
        end
        local d = 0
        pcall(function() d = math.sqrt((body:getX() - red:getX()) ^ 2 + (body:getY() - red:getY()) ^ 2) end)
        local onD = -1
        if m.spot ~= nil then onD = BridgeMove.mournBodyDist(m.spot, body:getX(), body:getY()) end
        log(string.format("mourning: stands by him, %.2f from his point, %.2f from his body, moved %.2f, turn %s deg left, hand to her head, %.1f s after his death",
            d, onD, m.moved or 0, tostring(BridgeMove.facingOff(body, fx, fy)), (Bridge.time - m.since) / 60))
        Bridge.mournCorpseLog(red)
    end
    if BridgeMove.onPath() then pcall(function() BridgeMove.stopPath(body) end) end
    BridgeMove.moving = false
    return true
end



function Bridge.mournCorpseLog(red)
    local found = false
    pcall(function()
        local cell = getCell()
        local cx, cy, z = math.floor(red:getX()), math.floor(red:getY()), math.floor(red:getZ())
        for dx = -1, 1 do
            for dy = -1, 1 do
                local sq = cell:getGridSquare(cx + dx, cy + dy, z)
                local list = sq and sq:getDeadBodys() or nil
                if list ~= nil then
                    for i = 0, list:size() - 1 do
                        local b = list:get(i)
                        if b ~= nil and b:isPlayer() then
                            found = true
                            log(string.format("his corpse at %.2f,%.2f angle %.2f front %s; his point %.2f,%.2f angle %.2f front %s",
                                b:getX(), b:getY(), b:getAngle(), tostring(b:isFallOnFront()), red:getX(), red:getY(),
                                red:getAnimAngleRadians(), tostring(red:isFallOnFront())))
                        end
                    end
                end
            end
        end
    end)
    if not found then log("his corpse: not found near his point") end
end








function Bridge.mournApproach(body, red, m)
    local bx, by = body:getX(), body:getY()
    m.startX = m.startX or bx
    m.startY = m.startY or by
    m.moved = math.sqrt((bx - m.startX) ^ 2 + (by - m.startY) ^ 2)
    if Bridge.time - m.walkSince >= Bridge.MOURN_WALK_MAX then
        log(string.format("mourning: could not reach him in %.0f s, stands where she is", Bridge.MOURN_WALK_MAX / 60))
        return "arrived"
    end
    if m.spot ~= nil then
        local okS, res = pcall(function() return BridgeMove.mournStepOff(body, m.spot) end)
        if okS and res == "step" then
            if m.walking then m.walking = false Bridge.target = nil end
            m.steppedOff = true
            return "own"
        end
        if okS and res == "stuck" then
            log("mourning: on him, no room to step off, stands")
            return "arrived"
        end
    end
    local rx, ry, rz = red:getX(), red:getY(), red:getZ()
    local d = math.sqrt((bx - rx) ^ 2 + (by - ry) ^ 2)



    local sameFloor = math.abs(body:getZ() - rz) < 0.5
    if sameFloor and (d <= 1.0 or (m.steppedOff and d <= Bridge.MOURN_NEAR)
        or (d <= Bridge.MOURN_NEAR and BridgeMove.lineClear(body, rx, ry, rz))) then
        if m.walking then log(string.format("mourning: came to him, %.2f from his point", d)) end
        return "arrived"
    end
    if not m.walking then
        m.walking = true
        log(string.format("mourning: %.2f from him%s, goes to him", d,
            d <= Bridge.MOURN_NEAR and " behind a wall" or ""))
    end
    Bridge.target = { x = rx, y = ry, z = rz }
    return "engine"
end



function Bridge.mournEnd(why)
    Bridge.mournVanish(why)
end



function Bridge.mournTick()
    if Bridge.mourning == nil or not Bridge.mp then return end
    if not Bridge.redDead(BridgeData.owner()) then Bridge.mournEnd("owner alive") end
end







function Bridge.markDeath()
    Bridge.redDied = true
    if not Bridge.mp and Bridge.store ~= nil then Bridge.store.redDied = true end
end







function Bridge.newLifeTick()
    local st = Bridge.store
    if Bridge.newLifePending and Bridge.mp and st ~= nil
        and (BridgeData.modeOf(st) ~= "follow" or st.waitX ~= nil) then

        st.mode, st.waitX, st.waitY, st.waitZ = "follow", nil, nil, nil
        Bridge.applyStoredMode()
    end
    if not Bridge.redDied and not (st ~= nil and st.redDied) then return end
    local red = BridgeData.owner()
    if red == nil or Bridge.redDead(red) then return end
    Bridge.redDied = nil
    if st ~= nil then st.redDied = nil end
    local was = BridgeData.modeOf(st)

    Bridge.sleepParked, Bridge.claimParked, Bridge.homeParked = nil, nil, false
    Bridge.setMode("follow")
    if Bridge.mp then Bridge.newLifePending = true end
    log("new character after death: she comes to him (was " .. tostring(was) .. ")")
end





function Bridge.onPlayerDeath(player)
    if player ~= nil and player ~= BridgeData.owner() then return end
    Bridge.markDeath()
    if Bridge.mp then return end
    if not Bridge.alive() or Bridge.kind ~= "zombie" then return end
    Bridge.saveOutfit()
    if Bridge.mourning == nil and not Bridge.mournAware(Bridge.body, player or BridgeData.owner()) then
        Bridge.despawn()
        Bridge.result = "body hidden: player died far away"
        log("body hidden: player died far away")
        return
    end
    if Bridge.mourning == nil then
        local ok = pcall(function() Bridge.mournStart(Bridge.body, player or BridgeData.owner()) end)
        if not ok then Bridge.mournEnd("start failed") end
    end
end

Events.OnPlayerDeath.Add(Bridge.onPlayerDeath)
Events.OnCreatePlayer.Add(function(playerIndex)


    if playerIndex ~= nil and playerIndex ~= 0 then return end



    Bridge.checked = {}
    Bridge.holdPos = nil
    Bridge.walkTypeSet = nil

    if Bridge.mourning ~= nil then pcall(function() Bridge.mournEnd("new player") end) end
    Bridge.mourning = nil
    if Bridge.body ~= nil then
        pcall(function() Bridge.body:setVariable(BODY_VAR, false) end)
        Bridge.body = nil
        Bridge.kind = nil
        log("dropped stale body reference")
    end
    Bridge.stash = nil
    Bridge.startTick = nil
    Bridge.hiddenObjs = nil
    Bridge.arrivalHold = nil
    Bridge.ssComplete = nil
    Bridge.spawnBackoff = nil
    Bridge.createdTime = nil
    Bridge.seen = {}
    Bridge.looks = {}
    if Bridge.world ~= nil then Bridge.refreshStore() end
    BridgeMove.reset(nil)
    BridgeFight.reset(nil)
    pcall(function() BridgeHeal.stop("new player") end)
    pcall(function() BridgeWash.stop("new player") end)
    log("player created, bridge ready, ack=" .. tostring(Bridge.ack))
    Bridge.writeState()
end)

log("subscribed")

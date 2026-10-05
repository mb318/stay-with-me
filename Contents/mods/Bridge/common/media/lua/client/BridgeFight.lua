



BridgeFight = BridgeFight or {}

local PRONE_WEIGHT = 2.0


local TIRED_SAY = 0.5
local RESTED_SAY = 0.2

local ATTACK_TIME = 28
local SWING_LEN = 60
local SWING_MIN = 35
local SWING_MAX = 120




local SWING_BY_ANIM = { Stab = 40, Bat = 55, Heavy = 75, Spear = 60, Shove = 45 }




local HIT_REACTION = {
    Attack2H1 = "HeadLeft", Attack2H2 = "HeadTop", Attack2H3 = "Uppercut", Attack2H4 = "HeadLeft", Attack2HFloor = "Floor",
    Attack1H1 = "HeadLeft", Attack1H2 = "HeadTop", Attack1H3 = "Uppercut", Attack1H4 = "HeadLeft", Attack1H5 = "HeadTop",
    Attack1HFloor = "Floor", AttackS1 = "HeadRight", AttackS2 = "HeadRight", AttackS1Floor = "Floor",
    AttackKnife = "Uppercut", AttackKnifeFloor = "Floor", AttackStomp = "Floor",

    AttackKnifeB = "Uppercut", AttackKnifeFloorB = "Floor", AttackStompB = "Floor", Attack1HFloorB = "Floor",
    Attack2HFloorB = "Floor", AttackS1FloorB = "Floor", AttackS1B = "HeadRight", AttackS2B = "HeadRight",
}

-- Reactions applied when the swing is a critical hit (a melee "head shot"). The base
-- game swaps to a *Crit animation and fires these lethal reactions; the mod already
-- ships the matching zombie animsets (falldown-speardeath1/2, falldown-knifedeath).
local CRIT_REACTION = {
    AttackS1 = "HitSpearDeath1", AttackS2 = "HitSpearDeath1",
    AttackS1B = "HitSpearDeath1", AttackS2B = "HitSpearDeath1",
    AttackKnife = "KnifeDeath", AttackKnifeB = "KnifeDeath",
}

local SECOND_NODE = { AttackKnife = true, AttackKnifeFloor = true, AttackStomp = true, Attack1HFloor = true,
    Attack2HFloor = true, AttackS1Floor = true, AttackS1 = true, AttackS2 = true }
local HIT_VAR = "NotAloneHitNow"


local ATTACK_NODES = {}
for _, n in ipairs({ "Attack2H1", "Attack2H2", "Attack2H3", "Attack2H4", "Attack2HFloor", "Attack2HFloorB",
    "Attack1H1", "Attack1H2", "Attack1H3", "Attack1H4", "Attack1H5", "Attack1HFloor", "Attack1HFloorB",
    "AttackS1", "AttackS2", "AttackS1B", "AttackS2B", "AttackS1Floor", "AttackS1FloorB", "AttackKnife", "AttackKnifeB", "AttackKnifeFloor",
    "AttackKnifeFloorB", "AttackStomp", "AttackStompB", "AttackBareHands1", "AttackBareHands2", "AttackBareHands3",
    "AttackBareHands4", "AttackBareHands5", "AttackBareHands6" }) do ATTACK_NODES[n] = true end
function BridgeFight.isAttackNode(name) return type(name) == "string" and ATTACK_NODES[name] == true end

local BARRIER_STATE = { thump = true, climbfence = true, climbwindow = true }
local SWING_DEFAULT = 55


local STALE_END_MAX = 40

















local SKILL_LEVEL = 0
local CRIT_PER_LEVEL = 3
local TIRED_CRIT = 20
local MISS_CHANCE = 15
local CROWD_RADIUS = 2.0
local CROWD_MISS = 0
local CROWD_MISS_MAX = 0







local END_BASE_SCALE = 0.28
local END_WEIGHT_MOD = 0.3
local END_FINAL = 0.04
local FATIGUE_MULT = 1.0
local END_TWOHAND_DIV = 1.5
local END_TWOHAND_SCALE = 10
local END_CLOSE_KILL = 0.2
local FATIGUE_REST = 1 / 10800
local FATIGUE_REST_SIT = 2
local FATIGUE_REST_BUSY = 0.5
local TIRED_SWING = 0.5
local TIRED_MISS = 15
local TIRED_DAMAGE = 0.25
local PICK_EVERY = 10
local APPROACH_MAX = 150
local BLACKLIST_TICKS = 900

--=============================================================================
-- feature toggles (1 = on, 0 = off)
--=============================================================================
local MULTIHIT_ON       = 1 -- let her melee cleave when the world "Weapon Multi Hit" option is on
local HEAD_TARGET_ON    = 1 -- aim for the head on downed zombies (fatigue + rng)
local NO_CLIMB_ON       = 1 -- never commit to a target she can only reach by vaulting or opening a door
local COMBATTEXT_ON     = 1 -- feed her hits to the Combat Text mod, when it is loaded (soft support)
local CRIT_KNOCKDOWN_ON = 1 -- critical hits knock the zombie down, like vanilla
local GROUND_BONUS_ON   = 1 -- vanilla ground-attack damage bonus when hitting a downed zombie

-- Multi-hit safety cap, head-aim and audio tuning.
local CRIT_SOUND_VOL       = 2.0 -- instance volume multiplier for the crit head foley
local MULTIHIT_MAX         = 4   -- never cleave more than this many zombies in one swing
local HEAD_STOMP_BASE      = 70  -- unarmed stomp head chance %, fully rested
local HEAD_FLOOR_BASE      = 40  -- armed floor-attack head chance %, fully rested
local HEAD_FATIGUE_PENALTY = 45  -- max percentage points lost at full fatigue
local HEAD_MIN             = 5   -- head chance floor
local REACH_TTL            = 120 -- ticks a reachability result is reused
local REACH_NODES          = 240 -- flood-fill budget for the no-climb reachability test
local STUCK_TICKS          = 60  -- approach ticks with no movement before giving up
local STUCK_MOVE           = 0.4 -- tiles of movement that count as progress
local REACH_CACHE_MAX      = 400 -- hard cap on cached reachability results
local reachCache = setmetatable({}, { __mode = "k" })
local reachCacheN = 0

BridgeFight.enabled = true
BridgeFight.guardOnly = false
BridgeFight.target = nil
BridgeFight.state = "idle"
BridgeFight.swingStart = 0
BridgeFight.hit = false
BridgeFight.lastPick = 0
BridgeFight.info = "none"
BridgeFight.approachStart = 0



BridgeFight.blacklist = {}

local function numberBan(z, b)
    if type(b) ~= "number" then return false end
    if b > (Bridge.tick or 0) then return true end
    BridgeFight.blacklist[z] = nil
    return false
end
BridgeFight.targetInfo = "none"
BridgeFight.fatigue = 0
BridgeFight.crowd = 0
BridgeFight.lastMiss = MISS_CHANCE
BridgeFight.saidTired = false

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeFight] " .. tostring(text)) end end
local function warn(text) print("[BridgeFight] " .. tostring(text)) end


local function vlog(text) if Bridge ~= nil and Bridge.verbose then log(text) end end

local function dist(a, b)
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    return math.sqrt(dx * dx + dy * dy)
end

local function isBody(z)
    local ok, v = pcall(function() return z:getVariableBoolean("NotAloneBody") end)
    return ok and v
end



local function remoteZombie(z)
    if not isClient() then return false end
    local ok, v = pcall(function() return z:isRemoteZombie() end)
    return ok and v
end


local function weapon(body)
    local item = body:getPrimaryHandItem()



    local thrown = false
    pcall(function() thrown = item ~= nil and item:getSwingAnim() == "Throw" end)
    if item ~= nil and instanceof(item, "HandWeapon") and not item:isRanged() and not thrown then return item end
    if BridgeFight.bareHands == nil then
        BridgeFight.bareHands = instanceItem("Base.BareHands")
    end
    return BridgeFight.bareHands
end

local function attackAnims(item, prone, crit)
    local kind = WeaponType.getWeaponType(item)
    if item:getFullType() == "Base.BareHands" or kind == WeaponType.UNARMED then
        if prone then return { "AttackStomp" }, "AttackStomp" end
        return { "AttackBareHands1", "AttackBareHands2", "AttackBareHands3",
                 "AttackBareHands4", "AttackBareHands5", "AttackBareHands6" }, item:getSwingSound()
    elseif kind == WeaponType.TWO_HANDED or kind == WeaponType.HEAVY then
        if prone then return { "Attack2HFloor" }, item:getSwingSound() end
        return { "Attack2H1", "Attack2H2", "Attack2H3", "Attack2H4" }, item:getSwingSound()
    elseif kind == WeaponType.ONE_HANDED then
        if prone then return { "Attack1HFloor" }, item:getSwingSound() end
        return { "Attack1H1", "Attack1H2", "Attack1H3", "Attack1H4", "Attack1H5" }, item:getSwingSound()
    elseif kind == WeaponType.SPEAR then
        if prone then return { "AttackS1Floor" }, item:getSwingSound() end
        -- AttackS2 is Bob_AttackSpear01_CritHit, the same animation the base game's
        -- SpearStab / SpearOverheadCrit uses. Reserve it for real critical hits.
        if crit then return { "AttackS2" }, item:getSwingSound() end
        return { "AttackS1" }, item:getSwingSound()
    elseif kind == WeaponType.KNIFE then
        if prone then return { "AttackKnifeFloor" }, item:getSwingSound() end
        return { "AttackKnife" }, item:getSwingSound()
    end
    if prone then return { "Attack2HFloor" }, item:getSwingSound() end
    return { "Attack2H1", "Attack2H2", "Attack2H3", "Attack2H4" }, item:getSwingSound()
end

local function isProne(z)
    local asn = z:getActionStateName()
    -- Crawlers (broken legs) count as floor targets too, so she stomps/floor-stabs
    -- them and can aim for the head instead of swinging at them standing.
    local crawl = false
    pcall(function() crawl = z:isCrawling() end)
    return z:isProne() or crawl or asn == "onground" or asn == "sitonground"
end



local function wallBetween(a, b)
    local blocked = false
    pcall(function()
        local sa, sb = a:getCurrentSquare(), b:getCurrentSquare()
        if sa == nil or sb == nil then return end
        if sa:getZ() ~= sb:getZ() then blocked = true return end
        local dx, dy = sb:getX() - sa:getX(), sb:getY() - sa:getY()
        if dx == 0 and dy == 0 then return end
        if math.abs(dx) > 1 or math.abs(dy) > 1 then return end
        blocked = sa:isBlockedTo(sb)
    end)
    return blocked
end
BridgeFight.wallBetween = wallBetween





local function swingFrames(item)
    local t = nil
    pcall(function() t = item:getSwingTime() end)
    local kind = "?"
    pcall(function() kind = item:getType() end)
    if BridgeFight.swingLogged ~= kind then
        BridgeFight.swingLogged = kind
        local mn = nil
        pcall(function() mn = item:getMinimumSwingTime() end)
        vlog("weapon " .. tostring(kind) .. " swingTime=" .. tostring(t) ..
            " minSwing=" .. tostring(mn) .. " dmg=" .. tostring(item:getMinDamage()) ..
            ".." .. tostring(item:getMaxDamage()))
    end
    local anim, speed = nil, 1.0
    pcall(function() anim = item:getSwingAnim() end)
    pcall(function() speed = item:getBaseSpeed() end)
    if type(speed) ~= "number" or speed <= 0 then speed = 1.0 end
    local len = math.floor((SWING_BY_ANIM[anim] or SWING_DEFAULT) / speed + 0.5)
    if len < SWING_MIN then len = SWING_MIN end
    if len > SWING_MAX then len = SWING_MAX end

    len = math.floor(len * (1 + TIRED_SWING * BridgeFight.fatigue) + 0.5)
    return len, math.floor(len * 0.45 + 0.5)
end



local function crowdAround(body, radius)
    radius = radius or CROWD_RADIUS
    local n = 0
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z ~= body and not isBody(z) and z:isAlive() and z:getHealth() > 0
                and math.abs(z:getZ() - body:getZ()) < 0.8 and dist(z, body) < radius
                and not BridgeData.harmless(z) then
                n = n + 1
            end
        end
    end)
    return n
end
BridgeFight.crowdAround = crowdAround


local function missChance(body)
    local crowd = crowdAround(body)
    BridgeFight.crowd = crowd
    local fromCrowd = math.min(CROWD_MISS_MAX, CROWD_MISS * math.max(0, crowd - 1))
    local chance = MISS_CHANCE + TIRED_MISS * BridgeFight.fatigue + fromCrowd
    BridgeFight.lastMiss = chance
    return math.min(90, chance)
end



local function sayFatigue()
    if BridgeMoments == nil then return end


    if not BridgeFight.saidTired and BridgeFight.fatigue >= TIRED_SAY then
        local said = false
        pcall(function() said = BridgeMoments.say("EvWinded", 2 * 3600, true) == true end)
        if said then BridgeFight.saidTired = true end
    elseif BridgeFight.saidTired and BridgeFight.fatigue <= RESTED_SAY then


        local said = false
        pcall(function() said = BridgeMoments.say("EvRested", 2 * 3600, true) == true end)
        if said then BridgeFight.saidTired = false end
    end
end



local function tire(item, dealt, hp, prone, body)
    local w, fat, endu, maxD = 1.0, 1.0, 1.0, 1.0
    pcall(function() w = item:getWeight() end)


    pcall(function() fat = item:getFatigueMod(body) end)
    pcall(function() endu = item:getEnduranceMod() end)
    pcall(function() maxD = item:getMaxDamage() end)
    if type(w) ~= "number" then w = 1.0 end
    if type(fat) ~= "number" or fat <= 0 then fat = 1.0 end
    if type(endu) ~= "number" or endu <= 0 then endu = 1.0 end
    if type(maxD) ~= "number" or maxD <= 0 then maxD = 1.0 end
    local two = false
    pcall(function() two = item:isTwoHandWeapon() end)

    local oneHand = 0
    if two and BridgeFight.oneHanded then oneHand = w / END_TWOHAND_DIV / END_TWOHAND_SCALE end
    local cost = (w * END_BASE_SCALE * fat * endu * END_WEIGHT_MOD + oneHand) * END_FINAL
    local scale = 1
    if prone then
        scale = END_CLOSE_KILL
    elseif dealt ~= nil and dealt > 0 then
        scale = math.min(math.min(dealt, hp or dealt) / maxD, 1)
    end
    BridgeFight.lastTire = cost * scale * FATIGUE_MULT
    BridgeFight.fatigue = math.min(1, BridgeFight.fatigue + cost * scale * FATIGUE_MULT)
    sayFatigue()
end


local function rest(busy)
    if BridgeFight.fatigue <= 0 then return end
    local r = FATIGUE_REST * (busy and FATIGUE_REST_BUSY or 1)

    if Bridge.pose ~= nil then r = r * FATIGUE_REST_SIT end

    r = r * (Bridge.dt or 1)
    BridgeFight.fatigue = math.max(0, BridgeFight.fatigue - r)
    sayFatigue()
end

-- Critical-hit roll. Done once at swing start so the animation and the reaction can
-- both follow it, then reused by hitTarget (and any multi-hit extras of that swing).
local function critRoll(item)
    local critChance, critMult = 0, 1
    pcall(function() critChance = item:getCriticalChance() end)
    pcall(function() critMult = item:getCriticalDamageMultiplier() end)
    if type(critChance) ~= "number" then critChance = 0 end
    if type(critMult) ~= "number" or critMult <= 0 then critMult = 1 end
    critChance = math.max(0, math.min(90, critChance + CRIT_PER_LEVEL * SKILL_LEVEL - TIRED_CRIT * BridgeFight.fatigue))
    return ZombRand(100) < critChance, critChance, critMult
end

-- The zombie head-hit foley the base game plays on a critical / head hit. The engine
-- picks it by damage type: blunt crunches (HeadSmash), stabs squelch (HeadStab),
-- blades slice (HeadSlice). Spears and knives count as stabs. These names are defined
-- in sounds_staywithme.txt and reuse the vanilla FMOD events with a wider range/volume.
local function critSound(item)
    local kind = nil
    pcall(function() kind = WeaponType.getWeaponType(item) end)
    if kind == WeaponType.SPEAR or kind == WeaponType.KNIFE then return "NA_HeadStab" end
    local cat = nil
    pcall(function() cat = item:getDamageCategory() end)
    if cat == "Blunt" then return "NA_HeadSmash" end
    if cat == "Slash" or cat == "Stab" then return "NA_HeadSlice" end
    return "NA_HeadSmash"
end

-- Soft Combat Text support: push her hits into Combat Text's own tracking list so its
-- managers draw the damage number and zombie health bar, exactly as they do for the
-- player. No-ops unless the Combat Text mod is loaded (its global cache is present).
-- Called BEFORE the damage lands, so Combat Text sees the pre-hit HP and shows a delta.
local function combatTextHit(victim, item, crit)
    if COMBATTEXT_ON ~= 1 then return end
    if CombatTextCache == nil or CombatTextCache.TrackingList == nil then return end
    pcall(function()
        local uid = victim:getUID()
        local hp = victim:getHealth() * 100.0
        local tick = getGameTime():getCalender():getTimeInMillis()
        local itm = CombatTextCache.TrackingList[uid]
        if itm == nil then
            CombatTextCache.TrackingList[uid] = { fullHp = hp, hp = hp, isDead = victim:isDead(),
                entity = victim, isOnFire = false, isBleeding = false, weapon = item, isCrit = crit, tick = tick }
            CombatTextCache.TrackingListCount = (CombatTextCache.TrackingListCount or 0) + 1
            itm = CombatTextCache.TrackingList[uid]
        else
            itm.weapon = item
            itm.isCrit = crit
            itm.tick = tick
        end
        if CombatTextCache.HealthBarManagers ~= nil then
            for _, m in pairs(CombatTextCache.HealthBarManagers) do
                if m ~= nil then pcall(function() m:onHit(uid, item, crit, itm) end) end
            end
        end
    end)
end

local function hitTarget(body, item, victim, noMiss)
    local fake = getCell():getFakeZombieForHit()
    local range = item:getMaxRange()
    local d = dist(body, victim)

    if d >= range + 0.3 then return string.format("miss range d=%.2f r=%.2f", d, range) end
    if victim:isOnKillDone() then return "miss killdone" end
    if wallBetween(body, victim) then return "miss wall" end

    -- noMiss: secondary targets of a multi-hit swing ride the primary target's hit
    -- roll, so they skip the per-target miss check (and its crowd scan).
    local miss = 0
    if not noMiss then
        miss = missChance(body)
        if ZombRand(100) >= 100 - miss then
            pcall(function() victim:setHitFromBehind(false) end)
            return string.format("miss roll (%.0f%% f=%.2f crowd=%d)", miss, BridgeFight.fatigue, BridgeFight.crowd)
        end
    end
    local behind = body:isBehind(victim)
    victim:setHitFromBehind(behind)
    victim:setAttackedBy(fake)

    local dmgMin, dmgMax = 0.3, 1.0
    pcall(function() dmgMin = item:getMinDamage() end)
    pcall(function() dmgMax = item:getMaxDamage() end)
    local dmg = dmgMin + (dmgMax - dmgMin) * ZombRandFloat(0, 1)
    local rawDmg = dmg

    -- Crit was rolled at swing start so the animation could follow it; reuse it here.
    local crit, critChance, critMult
    if BridgeFight.swingCrit ~= nil then
        crit = BridgeFight.swingCrit
        critChance = BridgeFight.swingCritChance or 0
        critMult = BridgeFight.swingCritMult or 1
    else
        crit, critChance, critMult = critRoll(item)
    end
    if crit then dmg = dmg * critMult end

    dmg = dmg * (0.3 + 0.1 * SKILL_LEVEL) / 0.3

    dmg = dmg * (1 - TIRED_DAMAGE * BridgeFight.fatigue)
    -- Vanilla ground-attack bonus: hitting a downed zomboid multiplies damage by the
    -- weapon's critical multiplier or 5, whichever is greater (and it stacks with a
    -- crit, so a crit on the floor applies the multiplier twice).
    if GROUND_BONUS_ON == 1 and isProne(victim) then
        dmg = dmg * math.max(critMult, 5)
    end
    local hpBefore = 0
    pcall(function() hpBefore = victim:getHealth() end)
    victim:setPlayerAttackPosition(victim:testDotSide(body))
    -- Head aim on a downed zombie: an unarmed stomp goes for the head far more often
    -- than an armed floor swing, and the chance falls as she tires. The engine reads
    -- these flags in processHitDamage/hitConsequences.
    local headFloor = false
    if HEAD_TARGET_ON == 1 and isProne(victim) then
        local bare = false
        pcall(function()
            bare = item:getFullType() == "Base.BareHands" or WeaponType.getWeaponType(item) == WeaponType.UNARMED
        end)
        local base = bare and HEAD_STOMP_BASE or HEAD_FLOOR_BASE
        local chance = base - HEAD_FATIGUE_PENALTY * BridgeFight.fatigue
        if chance < HEAD_MIN then chance = HEAD_MIN end
        headFloor = ZombRand(100) < chance
    end
    BridgeFight.lastHead = headFloor
    pcall(function() victim:setHitHeadWhileOnFloor(headFloor and 1 or 0) end)
    pcall(function() victim:setHitLegsWhileOnFloor(false) end)


    local reaction = HIT_REACTION[BridgeFight.anim or ""] or ""
    -- A crit swaps in the lethal head reaction (spear / knife), matching the base game.
    if crit then
        local cr = CRIT_REACTION[BridgeFight.anim or ""]
        if cr ~= nil then reaction = cr end
    end
    pcall(function()
        if victim:getEatBodyTarget() ~= nil then reaction = victim:getVariableBoolean("onknees") and "OnKnees" or "Eating" end
    end)
    if reaction ~= "" then
        pcall(function() victim:setHitReaction(reaction) end)
    else
        pcall(function()
            victim:setStaggerBack(true)
            victim:setHitReaction("")
        end)
    end
    BridgeFight.lastReaction = reaction
    -- Tell Combat Text about the hit before the damage lands so it can show the delta.
    combatTextHit(victim, item, crit)
    -- Critical hits play the zombie head-hit foley (the base game's crit "crunch").
    -- Play it before the blow so the victim still exists to carry the sound.
    BridgeFight.lastCritSound = nil
    if crit then
        local cs = critSound(item)
        if cs ~= nil then
            pcall(function()
                local em = victim:getEmitter()
                if em ~= nil then
                    local id = em:playSound(cs)
                    -- Vanilla-range event, boosted so the impact still cuts through.
                    if id ~= nil and id ~= 0 then em:setVolume(id, CRIT_SOUND_VOL) end
                end
            end)
            BridgeFight.lastCritSound = cs
        end
    end
    -- NOTE: we deliberately do NOT set the crit flag on the (fake) wielder. The engine's
    -- processHitDamage would then apply the weapon's crit multiplier a second time on
    -- top of the manual one above. Crit knockdown is applied explicitly below instead.
    victim:Hit(item, fake, dmg, false, 1, false)

    pcall(function() BridgeCallout.kill(victim) end)

    -- Vanilla crits knock the target down, when it survives the blow.
    if crit and CRIT_KNOCKDOWN_ON == 1 then
        pcall(function()
            if not victim:isDead() and victim:getHealth() > 0 then victim:setKnockedDown(true) end
        end)
    end

    local hitPart = "?"
    pcall(function() hitPart = tostring(victim:getLastHitPart()) end)
    BridgeFight.lastHitPart = hitPart

    tire(item, rawDmg, hpBefore, isProne(victim), body)
    pcall(function() victim:playSound(item:getZombieHitSound()) end)

    pcall(function()
        vlog(string.format("hit %s dmg=%.2f%s hp=%.2f->%.2f f=%.3f (+%.4f) miss=%.0f%% crit=%.0f%% crowd=%d head=%s part=%s reaction=%s snd=%s", tostring(item:getType()),
            dmg, crit and " CRIT" or "", hpBefore, victim:getHealth(), BridgeFight.fatigue, BridgeFight.lastTire or 0, miss, critChance, BridgeFight.crowd,
            tostring(headFloor), tostring(BridgeFight.lastHitPart or "?"), BridgeFight.lastReaction ~= "" and tostring(BridgeFight.lastReaction) or "stagger",
            tostring(BridgeFight.lastCritSound or "-")))
    end)



    pcall(function()
        if body:DistToSquared(victim) < 2 and math.abs(body:getZ() - victim:getZ()) < 0.5 then
            body:addBlood(nil, false, false, false)
        end
    end)
    return "hit"
end




local function visible(z, red)
    local seen = true

    local viewer = red
    pcall(function() if red:isDead() and Bridge.body ~= nil then viewer = Bridge.body end end)
    pcall(function() seen = viewer:CanSee(z) end)
    return seen
end
BridgeFight.visible = visible


-- Can she WALK to this target without vaulting a fence/window or opening a door?
-- Cheap straight-line test first; only when that fails do a bounded flood-fill that
-- treats climb edges and doors as walls. Cached per target so a pick does not redo it.
function BridgeFight.reachable(body, z)
    local ok = true
    pcall(function()
        local bsq, zsq = body:getCurrentSquare(), z:getCurrentSquare()
        if bsq == nil or zsq == nil then return end
        local bkey = bsq:getX() .. "," .. bsq:getY() .. "," .. bsq:getZ()
        local zkey = zsq:getX() .. "," .. zsq:getY() .. "," .. zsq:getZ()
        local rec = reachCache[z]
        if rec ~= nil and rec.b == bkey and rec.z == zkey and (Bridge.time - rec.tick) < REACH_TTL then
            ok = rec.reach
            return
        end
        local reach = false
        if BridgeMove ~= nil and BridgeMove.lineClear ~= nil then
            reach = BridgeMove.lineClear(body, z:getX(), z:getY(), z:getZ()) == true
            if not reach and BridgeMove.walkReach ~= nil then
                reach = BridgeMove.walkReach(body, z:getX(), z:getY(), z:getZ(), REACH_NODES) == true
            end
        end
        reachCache[z] = { b = bkey, z = zkey, tick = Bridge.time, reach = reach }
        reachCacheN = reachCacheN + 1
        if reachCacheN > REACH_CACHE_MAX then
            reachCache = setmetatable({}, { __mode = "k" })
            reachCacheN = 0
        end
        ok = reach
    end)
    return ok
end




function BridgeFight.mode()
    if BridgeFight.guardOnly then return BridgeData.COMBAT.bodyguard end
    return BridgeData.COMBAT[BridgeData.combatOf(Bridge.store)] or BridgeData.COMBAT.bodyguard
end


function BridgeFight.threat(z, body, red, mode)
    mode = mode or BridgeFight.mode()
    local bySelf = BridgeFight.guardOnly or mode.rank == "self"
    local d = bySelf and dist(z, body) or dist(z, red)
    local prone = false
    pcall(function() prone = isProne(z) or z:isCrawling() end)
    return d + (prone and PRONE_WEIGHT or 0)
end




local function barrierSide(z, body)
    local clear = false
    pcall(function() clear = BridgeMove.lineClear(body, z:getX(), z:getY(), z:getZ()) end)
    return not clear
end


local function pickTarget(body, red, mode)
    mode = mode or BridgeFight.mode()
    local list = getCell():getZombieList()
    local best, bestD = nil, math.huge
    for i = 0, list:size() - 1 do
        local z = list:get(i)



        local banned = false
        pcall(function()
            local b = BridgeFight.blacklist[z]
            if b == nil then return end


            if type(b) == "number" then banned = numberBan(z, b) return end
            local st = tostring(z:getActionStateName())



            local broke = BARRIER_STATE[b.st] and not BARRIER_STATE[st]
            local came = (z:getX() - b.x) ^ 2 + (z:getY() - b.y) ^ 2 > 1.0 and dist(z, red) < mode.engageRed
                and not wallBetween(body, z)
            if b.untilT <= Bridge.time or broke or came then
                BridgeFight.blacklist[z] = nil
                if b.untilT > Bridge.time then
                    vlog(string.format("target unbanned: %s", broke and ("stopped " .. b.st .. ", now " .. st) or "came to player"))
                end
            else
                banned = true
            end
        end)

        local busy = false
        pcall(function()
            local st = z:getActionStateName()
            busy = (st == "climbfence" or st == "climbwindow" or st == "pathfind")
                or (st == "thump" and barrierSide(z, body))
        end)



        if z ~= nil and not banned and not busy and not isBody(z) and not remoteZombie(z) and z:isAlive() and z:getHealth() > 0
            and not BridgeFight.ownerRisen(z, red)
            and math.abs(z:getZ() - red:getZ()) < 0.8 and not BridgeData.harmless(z) and visible(z, red) then
            local dRed = dist(z, red)
            local dSelf = dist(z, body)
            local near = dSelf < mode.engageSelf or (not BridgeFight.guardOnly and dRed < mode.engageRed)
            if near then
                local score = BridgeFight.threat(z, body, red, mode)
                -- Only run the (possibly costly) reachability test for a candidate that
                -- would actually become the new best, and only when the guard is on.
                if score < bestD and (NO_CLIMB_ON == 0 or BridgeFight.reachable(body, z)) then
                    best, bestD = z, score
                end
            end
        end
    end
    return best
end




function BridgeFight.ownerRisen(z, red)
    if z == nil or red == nil then return false end
    local risen = false
    pcall(function() risen = z:isReanimatedPlayer() and z:getReanimatedPlayer() == red end)
    return risen == true
end

local function validTarget(z, body, red, mode)
    mode = mode or BridgeFight.mode()
    if z == nil then return false end
    if BridgeFight.ownerRisen(z, red) then return false end
    local ok, alive = pcall(function() return z:isAlive() and z:getHealth() > 0 and not z:isOnKillDone() end)
    if not ok or not alive or remoteZombie(z) or BridgeData.harmless(z) then return false end




    local thumping = false
    pcall(function() thumping = tostring(z:getActionStateName()) == "thump" end)
    if thumping and barrierSide(z, body) then
        BridgeFight.info = "target behind a barrier (thump)"
        return false
    end

    if visible(z, red) then
        BridgeFight.unseenSince = nil
    else
        BridgeFight.unseenSince = BridgeFight.unseenSince or Bridge.time
        if Bridge.time - BridgeFight.unseenSince > 60 then
            BridgeFight.unseenSince = nil
            BridgeFight.info = "target out of sight"
            pcall(function() BridgeCallout.lostTarget() end)
            return false
        end
    end
    if BridgeFight.guardOnly then
        if dist(z, body) > BridgeData.COMBAT.bodyguard.targetMax then return false end
    else
        local d = mode.rank == "self" and dist(z, body) or dist(z, red)
        if d > mode.targetMax then return false end
    end
    return true
end


function BridgeFight.nearestInfo(body)
    local red = BridgeData.owner()
    if red == nil then return "no player" end
    local best, bestD, text = nil, math.huge, "none"
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and not isBody(z) and not BridgeData.harmless(z) then
                local d = math.min(dist(z, red), dist(z, body))
                if d < bestD then best, bestD = z, d end
            end
        end
        if best ~= nil then
            local banned = false
            local b = BridgeFight.blacklist[best]
            if type(b) == "number" then banned = numberBan(best, b)
            elseif b ~= nil and b.untilT > Bridge.time then banned = true end
            local see = false
            pcall(function() see = body:CanSee(best) end)
            text = string.format("dred=%.1f dself=%.1f st=%s hp=%.2f banned=%s see=%s", dist(best, red),
                dist(best, body), tostring(best:getActionStateName()), best:getHealth(),
                tostring(banned), tostring(see))
        end
    end)
    return text
end



function BridgeFight.resetFatigue()
    BridgeFight.fatigue = 0
    BridgeFight.saidTired = false
end

function BridgeFight.reset(body)
    BridgeFight.target = nil
    BridgeFight.state = "idle"
    BridgeFight.hit = false
    BridgeFight.info = "none"
    BridgeFight.targetInfo = "none"
end




local function watchCrawlers(body, red)
    if not (Bridge.verbose and Bridge.every(60, 20)) then return end
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z ~= body and z:isCrawling() and z:isAlive() and dist(z, body) < 4 then
                vlog(string.format("crawler d=%.2f dred=%.2f state=%s seen=%s target=%s fight=%s info=%s",
                    dist(z, body), dist(z, red), tostring(z:getActionStateName()), tostring(visible(z, red)),
                    tostring(BridgeFight.target == z), tostring(BridgeFight.state), tostring(BridgeFight.info)))
            end
        end
    end)
end


--=============================================================================
-- multi-hit
--=============================================================================
-- Cap for a weapon, read once per weapon type. getMaxHitCount() is the script's
-- MaxHitcount (1 = single target, 2-3 for cleaving melee, 9 on shotguns which she
-- never uses). Clamped for safety so a modded weapon cannot sweep the whole horde.
local hitCapCache = {}
local function hitCap(item)
    local key = nil
    pcall(function() key = item:getFullType() end)
    if key ~= nil and hitCapCache[key] ~= nil then return hitCapCache[key] end
    local cap = 1
    pcall(function() cap = item:getMaxHitCount() end)
    if type(cap) ~= "number" or cap < 1 then cap = 1 end
    if cap > MULTIHIT_MAX then cap = MULTIHIT_MAX end
    if key ~= nil then hitCapCache[key] = cap end
    return cap
end
BridgeFight.hitCap = hitCap

-- Every zombie the swing could also reach: in range, inside the weapon's facing
-- cone, no wall between, and never the player or another companion.
local function extraTargets(body, item, primary, want)
    local out = {}
    if want <= 0 then return out end
    local range, minAngle, fx, fy = 1.0, 0, 0, 0
    pcall(function() range = item:getMaxRange() end)
    pcall(function() minAngle = item:getMinAngle() end)
    pcall(function() fx, fy = body:getForwardDirectionX(), body:getForwardDirectionY() end)
    local red = BridgeData.owner()
    local cands = {}
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z ~= primary and z ~= body and z:isAlive() and z:getHealth() > 0
                and not instanceof(z, "IsoPlayer") and (red == nil or z ~= red)
                and not isBody(z) and not remoteZombie(z) and not BridgeData.harmless(z)
                and not BridgeFight.ownerRisen(z, red)
                and math.abs(z:getZ() - body:getZ()) < 0.8 then
                local d = dist(body, z)
                if d <= range + 0.3 then
                    local dx, dy = z:getX() - body:getX(), z:getY() - body:getY()
                    local len = math.sqrt(dx * dx + dy * dy)
                    local dot = (len > 0.001) and ((fx * dx + fy * dy) / len) or 1
                    if dot >= minAngle then
                        local clear = false
                        pcall(function() clear = BridgeMove.lineClear(body, z:getX(), z:getY(), z:getZ()) end)
                        if clear then cands[#cands + 1] = { z = z, d = d } end
                    end
                end
            end
        end
    end)
    table.sort(cands, function(a, b) return a.d < b.d end)
    for i = 1, math.min(#cands, want) do out[i] = cands[i].z end
    return out
end

-- Resolve the rest of a multi-hit swing. Runs ONCE per swing, at the same hit
-- moment as the primary, and only when the world "Weapon Multi Hit" option is on
-- and the weapon can actually cleave. Prone (stomp/floor) targets stay single.
function BridgeFight.multiHit(body, item, primary)
    if MULTIHIT_ON ~= 1 then return end
    if not (SandboxVars and SandboxVars.MultiHitZombies) then return end
    if isProne(primary) then return end
    local cap = hitCap(item)
    if cap <= 1 then return end
    local extras = extraTargets(body, item, primary, cap - 1)
    for i = 1, #extras do
        pcall(function() hitTarget(body, item, extras[i], true) end)
    end
    if #extras > 0 then
        vlog(string.format("multi-hit: %d extra target(s) (cap %d)", #extras, cap))
    end
end


function BridgeFight.update(body)
    if not BridgeFight.enabled then rest(false) return false end
    local red = BridgeData.owner()
    if red == nil then return false end
    local mode = BridgeFight.mode()
    watchCrawlers(body, red)





    if BridgeFight.target == nil and BridgeFight.state ~= "swing" then rest(false) end


    if not BridgeFight.guardOnly and dist(body, red) > mode.leash and BridgeFight.state ~= "swing" then
        if BridgeFight.target ~= nil then
            BridgeFight.info = "gave up: player far"
            pcall(function() BridgeCallout.breakOff() end)
        end
        BridgeFight.target = nil
        BridgeFight.state = "idle"
        return false
    end

    if BridgeFight.state == "swing" then
        BridgeWeapon.lastFight = Bridge.time
        local t = BridgeFight.target
        if t ~= nil then pcall(function() body:faceLocationF(t:getX(), t:getY()) end) end
        local age = Bridge.time - BridgeFight.swingStart
        local swingLen = BridgeFight.swingLen or SWING_LEN
        local attackAt = BridgeFight.attackAt or ATTACK_TIME



        local mark = false
        pcall(function() mark = body:getVariableBoolean(HIT_VAR) end)


        if not BridgeFight.hit and not mark and age >= attackAt then
            local playing = false
            pcall(function() playing = body:getActionStateName() == "bumped" and tostring(body:getBumpType()) == BridgeFight.anim end)
            if not playing then
                local st = "?"
                pcall(function() st = tostring(body:getActionStateName()) .. "/" .. tostring(body:getBumpType()) end)
                vlog("swing without animation (" .. st .. "), swinging again")
                BridgeFight.state = "idle"
                return true
            end
        end
        if not BridgeFight.hit and (mark or age >= attackAt) then
            BridgeFight.hit = true
            pcall(function() body:setVariable(HIT_VAR, false) end)
            vlog(string.format("hit moment: %s at %.2f s of the swing", mark and "animation mark" or "time (no mark)", age / 60))
            if validTarget(t, body, red, mode) then
                local w = weapon(body)
                local ok, res = pcall(function() return hitTarget(body, w, t) end)
                BridgeFight.info = ok and ("swing " .. tostring(res)) or ("hit error: " .. tostring(res))
                if not ok or res ~= "hit" then
                    local st, crawl = "?", false
                    pcall(function() st = tostring(t:getActionStateName()) crawl = t:isCrawling() end)
                    vlog("swing " .. BridgeFight.info .. " target state=" .. st .. " crawling=" .. tostring(crawl))
                else
                    -- primary connected: let the swing carry into any extra targets
                    pcall(function() BridgeFight.multiHit(body, w, t) end)
                end
            else
                vlog("swing lost target before the hit")
            end
        end

        if BridgeFight.hit and not BridgeFight.guardOnly and dist(body, red) > mode.leash then
            BridgeFight.target = nil
            BridgeFight.state = "idle"
            BridgeFight.info = "gave up mid-swing: player far"
            pcall(function() BridgeCallout.breakOff() end)
            return false
        end
        if age >= swingLen then
            BridgeFight.state = "idle"
        end
        return true
    end



    if BridgeFight.target ~= nil and (Bridge.time - BridgeFight.lastPick) >= PICK_EVERY
        and validTarget(BridgeFight.target, body, red, mode) then
        BridgeFight.lastPick = Bridge.time
        local okP, z = pcall(function() return pickTarget(body, red, mode) end)
        local cur = BridgeFight.target
        if okP and z ~= nil and z ~= cur
            and BridgeFight.threat(z, body, red, mode) + 0.5 < BridgeFight.threat(cur, body, red, mode) then
            vlog(string.format("target switched: threat %.1f -> %.1f (dred %.1f -> %.1f)", BridgeFight.threat(cur, body, red, mode),
                BridgeFight.threat(z, body, red, mode), dist(cur, red), dist(z, red)))
            BridgeFight.target = z
            BridgeFight.state = "idle"
        end
    end
    if not validTarget(BridgeFight.target, body, red, mode) then
        BridgeFight.target = nil




        BridgeFight.state = "idle"
        if (Bridge.time - BridgeFight.lastPick) < PICK_EVERY then return false end
        BridgeFight.lastPick = Bridge.time
        local ok, z = pcall(function() return pickTarget(body, red, mode) end)
        if not ok then BridgeFight.info = "pick error: " .. tostring(z); return false end
        BridgeFight.target = z
        if z == nil then return false end
        BridgeFight.info = "target picked"
        pcall(function() BridgeCallout.engage(z) end)




        pcall(function()
            local foreign = BridgeData.foreign(z)
            local banditNpc, banditHostile = BridgeData.bandit(z)
            local line = string.format("target picked: hp=%.2f d=%.1f dred=%.1f state=%s foreign=%s hostile=%s",
                z:getHealth(), dist(z, body), dist(z, red), tostring(z:getActionStateName()), tostring(foreign),
                banditNpc and ("bandit " .. tostring(banditHostile)) or tostring(foreign and BridgeData.alifeHostile(z) or "-"))
            if foreign then log(line) else vlog(line) end
        end)
    end

    local t = BridgeFight.target

    pcall(function() BridgeWeapon.fight(body) end)

    local drawing = false
    pcall(function() drawing = BridgeWeapon.busy() end)
    if drawing then
        pcall(function() body:faceLocationF(t:getX(), t:getY()) end)
        BridgeFight.info = "drawing weapon"
        return true
    end
    local item = weapon(body)
    local range = item:getMaxRange()
    local d = dist(body, t)
    if d > mode.approach then

        BridgeFight.target = nil
        BridgeFight.state = "idle"
        BridgeFight.info = "target too far, waiting"
        return false
    end

    local walled = d <= range + 0.1 and wallBetween(body, t)
    if d > range + 0.1 or walled then
        if walled then BridgeFight.info = "target behind wall" end
        if BridgeFight.state ~= "approach" then
            BridgeFight.state = "approach"
            BridgeFight.approachStart = Bridge.time
            BridgeFight.approachX, BridgeFight.approachY = body:getX(), body:getY()
            BridgeFight.approachStuck = 0
        elseif (Bridge.time - BridgeFight.approachStart) > APPROACH_MAX then


            BridgeFight.blacklist[t] = { untilT = Bridge.time + BLACKLIST_TICKS, x = t:getX(), y = t:getY(),
                                         st = tostring(t:getActionStateName()) }
            BridgeFight.info = "approach timeout, blacklisted"
            log(string.format("approach timeout: d=%.2f st=%s bump=%s path=%s", d,
                tostring(t:getActionStateName()), tostring(body:getBumpType()), BridgeMove.pathResult))
            BridgeFight.target = nil
            BridgeFight.state = "idle"
            BridgeMove.stopPath(body)
            return false
        end

        -- Bail out early if she is grinding against a wall/fence instead of pathing
        -- around it. Resets whenever she actually makes progress.
        local adx = body:getX() - (BridgeFight.approachX or body:getX())
        local ady = body:getY() - (BridgeFight.approachY or body:getY())
        if math.sqrt(adx * adx + ady * ady) < STUCK_MOVE then
            BridgeFight.approachStuck = (BridgeFight.approachStuck or 0) + 1
        else
            BridgeFight.approachStuck = 0
            BridgeFight.approachX, BridgeFight.approachY = body:getX(), body:getY()
        end
        if (BridgeFight.approachStuck or 0) >= STUCK_TICKS then
            BridgeFight.blacklist[t] = { untilT = Bridge.time + BLACKLIST_TICKS, x = t:getX(), y = t:getY(),
                                         st = tostring(t:getActionStateName()) }
            BridgeFight.info = "stuck approaching, blacklisted"
            log(string.format("approach stuck: d=%.2f st=%s bump=%s path=%s", d,
                tostring(t:getActionStateName()), tostring(body:getBumpType()), BridgeMove.pathResult))
            BridgeFight.target = nil
            BridgeFight.state = "idle"
            BridgeMove.stopPath(body)
            return false
        end
        BridgeFight.targetInfo = string.format("d=%.1f hp=%.2f st=%s", d, t:getHealth(), tostring(t:getActionStateName()))
        BridgeMove.walkType = (d > 3) and "Run" or "Walk"




        pcall(function() BridgeMove.endFollowBump(body, "") end)
        pcall(function() BridgeMove.setCollide(body, true) end)
        pcall(function() BridgeMove.goToward(body, t:getX(), t:getY(), t:getZ()) end)
        return true
    end


    BridgeMove.stopPath(body)


    pcall(function()
        local st = body:getActionStateName()
        if st ~= "bumped" and st ~= "idle" then
            vlog("swing from state " .. tostring(st) .. ": to idle first")
            body:changeState(ZombieIdleState.instance())
        end
    end)
    pcall(function() body:faceLocationF(t:getX(), t:getY()) end)
    -- Roll the crit now so the swing can pick the crit animation, and so hitTarget
    -- uses the same roll for damage, reaction and sound.
    local crit, critChance, critMult = critRoll(item)
    BridgeFight.swingCrit, BridgeFight.swingCritChance, BridgeFight.swingCritMult = crit, critChance, critMult
    local anims, swingSound = attackAnims(item, isProne(t), crit)
    local anim = anims[1 + ZombRand(#anims)]





    local cur = nil
    pcall(function() if tostring(body:getActionStateName()) == "bumped" then cur = tostring(body:getBumpType()) end end)
    if cur ~= nil and (cur == anim or cur == anim .. "B") then
        if #anims > 1 then
            local others = {}
            for _, a in ipairs(anims) do if a ~= cur then others[#others + 1] = a end end
            anim = others[1 + ZombRand(#others)]
        elseif SECOND_NODE[anim] and cur == anim then
            anim = anim .. "B"
        end
    end
    pcall(function() if swingSound then body:playSound(swingSound) end end)
    pcall(function() BridgeSound.voice(body, "MeleeAttack", 40) end)
    pcall(function() body:setVariable(HIT_VAR, false) end)




    pcall(function() body:setVariable("BumpAnimFinished", false) end)
    body:setBumpType(anim)


    if Bridge.mp then pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "look", { a = anim }) end) end
    BridgeFight.anim = anim
    BridgeFight.state = "swing"
    BridgeFight.swingStart = Bridge.time
    BridgeFight.swingLen, BridgeFight.attackAt = swingFrames(item)
    BridgeFight.hit = false
    BridgeFight.info = "swing " .. anim .. " " .. tostring(BridgeFight.swingLen) .. "f"

    vlog(string.format("swing start %s len=%d gap=%.2fs dt=%.3f", tostring(anim), BridgeFight.swingLen,
        BridgeFight.lastSwingAt and (Bridge.time - BridgeFight.lastSwingAt) / 60 or -1, Bridge.dt or 1))
    BridgeFight.lastSwingAt = Bridge.time
    return true
end










function BridgeFight.staleEnd(body)
    if body == nil or body ~= Bridge.body or BridgeFight.state ~= "swing" or BridgeFight.hit then return false end
    if Bridge.time - (BridgeFight.swingStart or 0) > STALE_END_MAX then return false end
    local fin, st, bump = false, "?", ""
    pcall(function() fin = body:getVariableBoolean("BumpAnimFinished") == true end)
    if not fin then return false end
    pcall(function() st = tostring(body:getActionStateName()) bump = tostring(body:getBumpType()) end)
    if st ~= "bumped" or bump ~= BridgeFight.anim then return false end
    local ok = pcall(function() body:setVariable("BumpAnimFinished", false) end)
    if ok then
        vlog(string.format("old clip end during the swing ignored: %s at %.2f s", tostring(bump),
            (Bridge.time - (BridgeFight.swingStart or 0)) / 60))
    end
    return ok
end

Events.OnTickEvenPaused.Add(function() pcall(BridgeFight.staleEnd, Bridge ~= nil and Bridge.body or nil) end)

log("loaded")












































































BridgeFastForward = BridgeFastForward or {}
BridgeFastForward.enabled = true
BridgeFastForward.flagged = nil
BridgeFastForward.reason = nil
BridgeFastForward.ANIMAL_R = 12
BridgeFastForward.ANIMAL_FAR = 45
BridgeFastForward.ANIMAL_EVERY = 15











BridgeFastForward.SCARE_R = 10
BridgeFastForward.CALM_SECOND = 15
BridgeFastForward.CALM_WINDOW = 180
BridgeFastForward.ZOMBIE_NEAR = 10
BridgeFastForward.stress = {}
BridgeFastForward.scared = {}













BridgeFastForward.MOVE_HOLD = 10


local HOLD_SKIP = { [""] = true, ["nil"] = true, Stand = true, StandSneak = true, Stand2h = true, StandSneak2h = true,
    FollowWalk = true, FollowRun = true, FollowWalkSneak = true, FollowRunSneak = true, FollowWalk2h = true,
    FollowRun2h = true, FollowWalkSneak2h = true, FollowRunSneak2h = true, StartMove = true, StartMove2h = true,
    StartMoveSneak = true, StartMoveSneak2h = true,
    ClimbFenceEnd = true, ClimbFenceTall = true, ClimbFenceTallStart = true, ClimbWindow = true, Scramble = true }








local SAFE = { bumped = true, walktoward = true, pathfind = true, turnalerted = true, climbfence = true, climbwindow = true }

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeFastForward] " .. tostring(text)) end end
local function warn(text) print("[BridgeFastForward] " .. tostring(text)) end
local logged = {}
local function logOnce(text)
    if logged[text] then return end
    logged[text] = true
    log(text)
end
local function warnOnce(text)
    if logged[text] then return end
    logged[text] = true
    warn(text)
end

local function herBody()
    if Bridge == nil or Bridge.alive == nil or not Bridge.alive() or Bridge.kind ~= "zombie" then return nil end
    return Bridge.body
end



local function yes(b, method)
    local m = b[method]
    if m == nil then return false end
    local v = false
    pcall(function() v = m(b) == true end)
    return v
end

BridgeFastForward.NEAR = 8

local function player()
    local p = nil
    pcall(function() p = getSpecificPlayer(0) end)
    return p
end



function BridgeFastForward.unsafe(b, near, anyFloor)
    near = near or BridgeFastForward.NEAR
    local asn = "?"
    pcall(function() asn = tostring(b:getActionStateName()) end)
    if not SAFE[asn] then return "state " .. asn end
    if yes(b, "isDead") then return "dead" end
    if yes(b, "isOnFloor") then return "on the floor" end
    if yes(b, "isKnockedDown") then return "knocked down" end
    if yes(b, "isBumpFall") then return "tripping" end
    if yes(b, "isBeingGrappled") then return "grappled" end
    local sq = nil
    pcall(function() sq = b:getCurrentSquare() end)
    if sq == nil then return "no square" end
    local car = nil
    pcall(function() car = b:getVehicle() end)
    if car ~= nil then return "in a vehicle" end
    local fight = false
    pcall(function() fight = BridgeFight ~= nil and (BridgeFight.target ~= nil or BridgeFight.state == "swing") end)
    if fight then return "fight" end
    local p = player()
    if p == nil then return "no player" end
    local far = true
    pcall(function()
        local dx, dy = b:getX() - p:getX(), b:getY() - p:getY()
        far = (not anyFloor and math.floor(b:getZ()) ~= math.floor(p:getZ())) or dx * dx + dy * dy >= near * near
    end)
    if far then return "far" end
    return nil
end


local function fastForward(speed)
    if speed >= 2 then return true end
    local mult = 1
    pcall(function() mult = getGameTime():getTrueMultiplier() end)
    return speed == 1 and mult > 1.01
end

local function setFlag(b, on)
    if b == nil or b.setReanimatedForGrappleOnly == nil then return false end
    local ok = pcall(function() b:setReanimatedForGrappleOnly(on) end)
    return ok
end








function BridgeFastForward.animalsNear(b, every)
    local now = 0
    pcall(function() now = Bridge.time or 0 end)
    local at = BridgeFastForward.animalsAt
    if at ~= nil and now >= at and now - at < (every or BridgeFastForward.ANIMAL_EVERY) then return BridgeFastForward.animals == true end
    BridgeFastForward.animalsAt = now
    local found = false
    local total, nearest, scanned = 0, nil, false
    pcall(function()
        local cell = getCell ~= nil and getCell() or nil
        if cell == nil then return end
        local bx, by, bz = b:getX(), b:getY(), b:getZ()
        local r = BridgeFastForward.ANIMAL_R
        local it = cell:getAnimals():iterator()
        while it:hasNext() do
            local o = it:next()
            if not o:isDead() then
                total = total + 1
                local dx, dy = o:getX() - bx, o:getY() - by
                local d = math.sqrt(dx * dx + dy * dy)
                if nearest == nil or d < nearest then nearest = d end
                if d <= r and math.abs(o:getZ() - bz) <= 1 then
                    found = true

                    if BridgeFastForward.flagged ~= nil and not BridgeFastForward.recentlyExposed(now) then
                        BridgeFastForward.stress[o] = o:getStress()
                    end
                end
            end
        end
        scanned = true
    end)

    if Bridge ~= nil and Bridge.verbose and (total > 0 or not scanned)
        and now - (BridgeFastForward.scanLogAt or -9999) >= 600 then
        BridgeFastForward.scanLogAt = now
        log(string.format("animal scan: %s, %d animals in the cell, nearest %s", scanned and "ok" or "FAILED", total,
            nearest and string.format("%.1f", nearest) or "none"))
    end


    if found ~= (BridgeFastForward.animals == true) and now - (BridgeFastForward.nearLogAt or -9999) >= 60 then
        BridgeFastForward.nearLogAt = now
        log(found and "animals near her" or "no animals near her")
    end
    BridgeFastForward.animals = found
    if not found then
        BridgeFastForward.stress = {}
        BridgeFastForward.scared = {}
    end
    return found
end


function BridgeFastForward.recentlyExposed(now)
    local at = BridgeFastForward.exposedAt
    return at ~= nil and now >= at and now - at <= BridgeFastForward.CALM_WINDOW
end



local function hasAny(t)
    for _ in pairs(t) do return true end
    return false
end



local function companionAnimal(a)
    local cd = false
    pcall(function() cd = a:hasModData() and a:getModData().CompanionDogs ~= nil end)
    return cd
end


local function leashed(a)
    local on = false
    pcall(function() on = a:getData():getAttachedPlayer() ~= nil end)
    return on
end
BridgeFastForward.FLEE_R = 6.5









function BridgeFastForward.noteScared(b, now)
    pcall(function()
        local cell = getCell ~= nil and getCell() or nil
        if cell == nil then return end
        local bx, by, bz = b:getX(), b:getY(), b:getZ()
        local r2 = BridgeFastForward.SCARE_R * BridgeFastForward.SCARE_R
        local f2 = BridgeFastForward.FLEE_R * BridgeFastForward.FLEE_R
        local it = cell:getAnimals():iterator()
        while it:hasNext() do
            local a = it:next()
            if not a:isDead() then
                local dx, dy = a:getX() - bx, a:getY() - by
                local d2 = dx * dx + dy * dy
                if d2 <= r2 and math.abs(a:getZ() - bz) <= 1 and not companionAnimal(a) then
                    local rec = BridgeFastForward.scared[a]
                    if rec == nil then
                        local base = BridgeFastForward.stress[a]
                        if base == nil then base = a:getStress() end
                        rec = { base = base, alerted = a:isAlerted(), flee = false, leash = leashed(a) }
                        BridgeFastForward.scared[a] = rec
                    end
                    rec.at = now
                    if not rec.flee and d2 <= f2 and not a:isAnimalMoving() then rec.flee = true end
                end
            end
        end
    end)
    BridgeFastForward.scaredAt = now
    BridgeFastForward.calmPass = 0
end


function BridgeFastForward.calm(b, now)
    BridgeFastForward.calmAt = now
    BridgeFastForward.calmPass = (BridgeFastForward.calmPass or 0) + 1
    local n = 0
    pcall(function()
        if not hasAny(BridgeFastForward.scared) then return end
        local cell = getCell ~= nil and getCell() or nil
        if cell == nil then return end
        local bx, by = b:getX(), b:getY()


        local fresh, far = {}, 0
        for a, rec in pairs(BridgeFastForward.scared) do
            if rec.at ~= nil and now - rec.at <= BridgeFastForward.CALM_WINDOW and not a:isDead() then
                fresh[a] = rec
                local d = math.sqrt((a:getX() - bx) ^ 2 + (a:getY() - by) ^ 2)
                if d > far then far = d end
            end
        end
        if not hasAny(fresh) then return end


        local zombies = {}
        local keep = far + BridgeFastForward.ZOMBIE_NEAR
        local zl = cell:getZombieList()
        for i = 0, zl:size() - 1 do
            local z = zl:get(i)
            if z ~= b then
                local zx, zy = z:getX() - bx, z:getY() - by
                if zx * zx + zy * zy <= keep * keep and not z:isDead() then zombies[#zombies + 1] = z end
            end
        end
        local near2 = BridgeFastForward.ZOMBIE_NEAR * BridgeFastForward.ZOMBIE_NEAR
        for a, rec in pairs(fresh) do
            local ax, ay, az = a:getX(), a:getY(), a:getZ()
            local threat = false
            for _, z in ipairs(zombies) do
                local zx, zy = z:getX() - ax, z:getY() - ay
                if zx * zx + zy * zy <= near2 and math.abs(z:getZ() - az) <= 1 then threat = true break end
            end
            if not threat then
                local did = false






                if rec.flee and not rec.leash and a:isAnimalMoving() then a:stopAllMovementNow() did = true end
                if not rec.alerted and a:isAlerted() then a:setIsAlerted(false) did = true end
                if rec.base ~= nil and a:getStress() > rec.base then a:setDebugStress(rec.base) did = true end
                if did then n = n + 1 end
            end
        end
    end)
    if n > 0 and now - (BridgeFastForward.calmLogAt or -9999) >= 60 then
        BridgeFastForward.calmLogAt = now
        log(string.format("animals calmed after she was visible to them: %d", n))
    end

    if BridgeFastForward.calmPass >= 2 then BridgeFastForward.scared = {} end
    return n
end





local POSE_ALT = { Sit = "SitB", SitB = "Sit", Sleep = "SleepB", SleepB = "Sleep",
    SitRubHands = "SitRubHandsB", SitRubHandsB = "SitRubHands" }
BridgeFastForward.POSE_ALT = POSE_ALT



function BridgeFastForward.holdStand(b)
    local asn, bump, fin = "?", "", false
    pcall(function() asn = tostring(b:getActionStateName()) end)
    if asn ~= "bumped" then return false end
    pcall(function() bump = tostring(b:getBumpType()) end)
    local pose = Bridge ~= nil and Bridge.pose or nil
    if pose ~= nil then

        local alt = POSE_ALT[bump]
        if alt == nil or (pose.anim ~= bump and pose.anim ~= alt) then return false end
        pcall(function() fin = b:getVariableBoolean("BumpAnimFinished") == true end)
        if not fin then return false end
        return pcall(function()
            b:setVariable("BumpAnimFinished", false)
            b:setBumpType(alt)
        end)
    end
    if HOLD_SKIP[bump] or string.sub(bump, 1, 5) == "Climb" then return false end



    local seating = false
    pcall(function() seating = BridgeMove ~= nil and BridgeMove.seat ~= nil end)
    if seating and string.sub(bump, 1, 3) == "Sit" then return false end




    local owned = false
    pcall(function()
        owned = (BridgeHeal ~= nil and (BridgeHeal.active or BridgeHeal.current ~= nil))
            or (BridgeWash ~= nil and BridgeWash.state ~= "idle")
            or (BridgeInventory ~= nil and BridgeInventory.gestures ~= nil and BridgeInventory.gestures[1] ~= nil
                and BridgeInventory.gestures[1].anim == bump)



            or (BridgeWeapon ~= nil and BridgeWeapon.move ~= nil and BridgeWeapon.move.anim == bump
                and not BridgeWeapon.move.connected)
    end)
    if owned then return false end
    local climbing = false
    pcall(function() climbing = BridgeMove ~= nil and (Bridge.time < (BridgeMove.climbUntil or 0) or BridgeMove.seatFlag == true) end)
    if climbing then return false end
    pcall(function() fin = b:getVariableBoolean("BumpAnimFinished") == true end)
    if not fin then return false end
    local ok = pcall(function()
        b:setVariable("BumpAnimFinished", false)
        b:setBumpType("Stand")
    end)
    if ok and Bridge ~= nil and Bridge.verbose then
        local now = Bridge.time or 0
        if now - (BridgeFastForward.holdLogAt or -9999) >= 60 then
            BridgeFastForward.holdLogAt = now
            log("clip end held in stand (no idle frame): " .. bump)
        end
    end
    return ok
end




function BridgeFastForward.keepMoving(body)
    if body == nil or BridgeFastForward.flagged ~= body then return end
    local asn = "?"
    pcall(function() asn = tostring(body:getActionStateName()) end)
    if asn ~= "pathfind" and asn ~= "walktoward" then return end





    pcall(function() body:changeState(ZombieIdleState.instance()) end)
    pcall(function()
        local bump = tostring(body:getBumpType())
        if bump == "" or bump == "nil" then body:setBumpType("Stand") end
        body:setMoving(true)
    end)
    BridgeFastForward.forcedMove = BridgeFastForward.forcedMove or ((Bridge and Bridge.time) or 0)
end


function BridgeFastForward.active()
    return BridgeFastForward.flagged ~= nil
end


function BridgeFastForward.clear(why)
    local f = BridgeFastForward.flagged
    if f == nil then return end
    BridgeFastForward.flagged = nil
    setFlag(f, false)
    log(tostring(BridgeFastForward.reason or "fast-forward") .. " flag off: " .. tostring(why))
    BridgeFastForward.reason = nil
end


function BridgeFastForward.tick()
    if not BridgeFastForward.enabled then return end
    local mp = false
    pcall(function() mp = isClient() or isServer() end)
    if mp then
        if BridgeFastForward.flagged ~= nil then BridgeFastForward.clear("multiplayer") end


        local b = Bridge ~= nil and Bridge.body or nil
        if b ~= nil and Bridge.kind == "zombie" then
            local set = false
            pcall(function() set = b:isReanimatedForGrappleOnly() end)
            if set then
                pcall(function() b:setReanimatedForGrappleOnly(false) end)
                logOnce("multiplayer: flag found on her body, taken off")
            end
        end
        return
    end
    local speed = 1
    pcall(function() speed = UIManager.getSpeedControls():getCurrentGameSpeed() end)



    if speed == 0 then
        local fp = BridgeFastForward.flagged
        if fp ~= nil then
            local w = BridgeFastForward.unsafe(fp, math.huge, true)
            if w ~= nil then BridgeFastForward.clear("paused, " .. tostring(w)) end
        end
        return
    end
    local b = herBody()
    local ff = fastForward(speed)
    local why, reason = nil, nil
    if b == nil then
        why = "no body"
    else
        if ff then reason, why = "fast-forward", BridgeFastForward.unsafe(b) end

        if (reason == nil or why ~= nil) and BridgeFastForward.animalsNear(b, ff and 1 or nil) then
            local w2 = BridgeFastForward.unsafe(b, BridgeFastForward.ANIMAL_FAR, true)
            if reason == nil or w2 == nil then reason, why = "animals", w2 end
        end
        if reason == nil then why = "normal speed, no animals" end
    end


    if Bridge ~= nil and Bridge.verbose then
        local now = Bridge.time or 0
        if now - (BridgeFastForward.beatAt or -9999) >= 600 or now < (BridgeFastForward.beatAt or 0) then
            BridgeFastForward.beatAt = now
            log(string.format("tick: body %s, speed %s, fast-forward %s, reason %s, why %s, flagged %s", tostring(b ~= nil),
                tostring(speed), tostring(ff), tostring(reason), tostring(why), tostring(BridgeFastForward.flagged ~= nil)))
        end
    end
    local f = BridgeFastForward.flagged
    if f ~= nil and (why ~= nil or f ~= b) then
        BridgeFastForward.clear(why or "new body")
        f = nil
    end

    if why == nil and f == b then
        local still = false
        pcall(function() still = b:isReanimatedForGrappleOnly() == true end)
        if not still then
            setFlag(b, true)
            logOnce("fast-forward: flag was taken off by someone else, set again")
        end
    end
    if why == nil and reason ~= BridgeFastForward.reason and f ~= nil then
        log("flag stays, now for " .. tostring(reason))
    end
    if why == nil then BridgeFastForward.reason = reason end


    if BridgeFastForward.forcedMove ~= nil then
        local asnF, nowF, pathing = "?", (Bridge and Bridge.time) or 0, false
        if b ~= nil then pcall(function() asnF = tostring(b:getActionStateName()) end) end
        pcall(function() pathing = BridgeMove ~= nil and BridgeMove.pathing == true end)
        if b == nil or asnF == "bumped" or nowF - BridgeFastForward.forcedMove > BridgeFastForward.MOVE_HOLD then
            if b ~= nil and not pathing and asnF ~= "pathfind" then pcall(function() b:setMoving(false) end) end
            BridgeFastForward.forcedMove = nil
        end
    end

    if why == nil and b ~= nil then BridgeFastForward.holdStand(b) end


    local now0 = 0
    pcall(function() now0 = Bridge.time or 0 end)


    local shown = b ~= nil and why ~= nil and BridgeFastForward.animals == true
    if shown and Bridge ~= nil and Bridge.verbose
        and string.sub(tostring(why), 1, 6) == "state " and now0 - (BridgeFastForward.traceAt or -9999) >= 600 then
        BridgeFastForward.traceAt = now0
        pcall(function()
            if BridgeMove ~= nil and Bridge.tick ~= nil then BridgeMove.traceUntil = Bridge.tick + 60 end
        end)
    end

    if shown then
        BridgeFastForward.exposedAt = now0
        BridgeFastForward.noteScared(b, now0)
    end
    if why == nil and f == nil then
        if setFlag(b, true) then
            BridgeFastForward.flagged = b

            if hasAny(BridgeFastForward.scared) then BridgeFastForward.calm(b, now0) end
            if reason == "animals" then
                log("animals near: her body out of the animals' check")
            else
                log("fast-forward x" .. tostring(speed) .. ": her body out of the zombie check")
            end
        else
            warnOnce("fast-forward: setReanimatedForGrappleOnly failed")
        end
    elseif why == nil and f ~= nil then


        if hasAny(BridgeFastForward.scared) then
            local pass = BridgeFastForward.calmPass or 0
            if pass == 0 or (pass == 1 and now0 - (BridgeFastForward.calmAt or now0) >= BridgeFastForward.CALM_SECOND) then
                BridgeFastForward.calm(b, now0)
            end
        end
    elseif why ~= nil and reason == "animals" then


        local now = Bridge.time or 0
        if now - (BridgeFastForward.whyLogAt or -9999) >= 600 then
            BridgeFastForward.whyLogAt = now
            log("animals near: she stays in their check: " .. tostring(why))
        end
    elseif why ~= nil and why ~= "far" and ff and b ~= nil then


        logOnce("fast-forward: she stays in the zombie check: " .. why)
    end
end



function BridgeFastForward.sight()
    local b = BridgeFastForward.flagged
    if b == nil then return end
    local p = player()
    if p == nil then return end
    local seen = true
    pcall(function()
        local pn = p:getPlayerNum()
        local sq = b:getCurrentSquare()
        seen = sq ~= nil and (sq:isCanSee(pn) or sq:isCouldSee(pn))
        b:setAlphaAndTarget(pn, seen and 1 or 0)
    end)
end


Events.OnTickEvenPaused.Add(function()
    local ok, err = pcall(BridgeFastForward.tick)
    if not ok then warnOnce("tick error: " .. tostring(err)) end
end)
Events.OnTick.Add(function() pcall(BridgeFastForward.sight) end)
Events.OnSave.Add(function() pcall(BridgeFastForward.clear, "saving") end)

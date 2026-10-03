








BridgeSleep = BridgeSleep or {}






BridgeSleep.CLOSE = 3
BridgeSleep.SEEN = 7

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeSleep] " .. tostring(text)) end end
local function warn(text) print("[BridgeSleep] " .. tostring(text)) end


function BridgeSleep.blocks(playerObj, z)
    local dx, dy = z:getX() - playerObj:getX(), z:getY() - playerObj:getY()
    local d2 = dx * dx + dy * dy
    local sameFloor = math.abs(z:getZ() - playerObj:getZ()) < 1
    local chasing = false
    pcall(function() chasing = z:getTarget() == playerObj end)
    if chasing then return true, "chasing" end
    if sameFloor and d2 < BridgeSleep.CLOSE * BridgeSleep.CLOSE then return true, "very close" end
    if sameFloor and d2 < BridgeSleep.SEEN * BridgeSleep.SEEN then
        local seen, sameRoom = false, false
        pcall(function() seen = playerObj:CanSee(z) end)
        pcall(function()
            local a, b = z:getCurrentSquare(), playerObj:getCurrentSquare()
            sameRoom = a ~= nil and b ~= nil and a:getRoom() == b:getRoom()
        end)
        if seen and sameRoom then return true, "seen" end
    end
    return false, nil
end



function BridgeSleep.onlyCompanions(playerObj)
    if playerObj == nil then return false end
    local stats = playerObj:getStats()
    local counted = stats:getNumVisibleZombies() > 0 or stats:getNumChasingZombies() > 0
        or stats:getNumVeryCloseZombies() > 0
    if not counted then return false end
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local z = list:get(i)

        if z ~= nil and z:isAlive() and not Bridge.isCompanion(z) and not BridgeData.dragged(z) then
            local block, why = BridgeSleep.blocks(playerObj, z)
            if block then
                local d = 0
                pcall(function() d = math.sqrt((z:getX() - playerObj:getX()) ^ 2 + (z:getY() - playerObj:getY()) ^ 2) end)
                log(string.format("zombie %s at %.1f: game check decides", why, d))
                return false
            end
        end
    end
    return true
end








BridgeSleep.pending = nil
BridgeSleep.WAIT_MIN = 2
BridgeSleep.WAIT_MAX = 60

local function countersClear(playerObj)
    local clear = false
    pcall(function()
        local st = playerObj:getStats()
        clear = st:getNumVisibleZombies() == 0 and st:getNumChasingZombies() == 0 and st:getNumVeryCloseZombies() == 0
    end)
    return clear
end







function BridgeSleep.hidingCopies()
    if Bridge == nil or not Bridge.mp then return false end
    return BridgeSleep.pending ~= nil
end

function BridgeSleep.sleepAfterPark(player, bed, original)
    local parked = false
    pcall(function() parked = Bridge.sleepParkNow() end)
    BridgeSleep.pending = { player = player, bed = bed, original = original, since = Bridge.time }
    log("only companions near: " .. (parked and "body parked" or "no own body in the world") .. ", waiting for the game to recount")
end

function BridgeSleep.tickPending()
    local p = BridgeSleep.pending
    if p == nil then return end
    local waited = Bridge.time - p.since
    if waited < BridgeSleep.WAIT_MIN then return end
    local clear = countersClear(getSpecificPlayer(p.player))
    if not clear and waited < BridgeSleep.WAIT_MAX then return end
    BridgeSleep.pending = nil
    log(clear and "counters clear: going to sleep the game's way" or "counters still set after 1 s: the game decides")
    local ok, err = pcall(p.original, p.player, p.bed)
    if not ok then warn("sleep call failed: " .. tostring(err)) end
end

if Events ~= nil and Events.OnTick ~= nil then
    Events.OnTick.Add(function() pcall(BridgeSleep.tickPending) end)
end






function BridgeSleep.wrap(when)
    if ISWorldObjectContextMenu == nil or ISWorldObjectContextMenu.onSleepWalkToComplete == nil then return end
    local current = ISWorldObjectContextMenu.onSleepWalkToComplete
    if current == BridgeSleep.wrapper then return end
    local original = current
    BridgeSleep.wrapper = function(player, bed)
        local ok, only = pcall(function() return BridgeSleep.onlyCompanions(getSpecificPlayer(player)) end)
        if ok and only then
            return BridgeSleep.sleepAfterPark(player, bed, original)
        end
        return original(player, bed)
    end
    ISWorldObjectContextMenu.onSleepWalkToComplete = BridgeSleep.wrapper
    ISWorldObjectContextMenu.bridgeSleepWrapped = true
    if when ~= "load" then log("sleep check was replaced after us (" .. tostring(when) .. "), wrapped again") end
end










BridgeSleep.SLEEP_OPTIONS = { "ContextMenu_Sleep", "ContextMenu_SleepOnGround", "ContextMenu_SleepOnGroundPillow" }

local function isSleepOption(o)
    if o == nil then return false end
    if ISWorldObjectContextMenu ~= nil and o.onSelect ~= nil and o.onSelect == ISWorldObjectContextMenu.onSleep then return true end
    for _, key in ipairs(BridgeSleep.SLEEP_OPTIONS) do
        if o.name == getText(key) then return true end
    end
    return false
end



function BridgeSleep.allOptions(context)
    local out, seen = {}, {}
    local function walk(menu, depth)
        if menu == nil or menu.options == nil or seen[menu] or depth > 4 then return end
        seen[menu] = true
        for _, o in ipairs(menu.options) do
            out[#out + 1] = o
            if o.subOption ~= nil then
                local sub = nil
                pcall(function() sub = context:getSubMenu(o.subOption) end)
                walk(sub, depth + 1)
            end
        end
    end
    walk(context, 1)
    return out
end

function BridgeSleep.fixSleepOption(playerNum, context, worldobjects, test)
    if test or context == nil or context.options == nil then return end
    local playerObj = getSpecificPlayer(playerNum)
    if playerObj == nil then return end
    local notSafe = getText("IGUI_Sleep_NotSafe")
    for _, o in ipairs(BridgeSleep.allOptions(context)) do
        local tip = o.toolTip
        local desc = tip ~= nil and tip.description or nil
        if isSleepOption(o) and o.notAvailable and type(desc) == "string" and string.find(desc, notSafe, 1, true) ~= nil then
            local ok, only = pcall(function() return BridgeSleep.onlyCompanions(playerObj) end)
            if ok and only then

                local needed = true
                pcall(function() if isClient() then needed = getServerOptions():getBoolean("SleepNeeded") end end)
                local tired = true
                pcall(function() tired = playerObj:getStats():get(CharacterStat.FATIGUE) > 0.3 end)
                local rest = desc:gsub(notSafe:gsub("%p", "%%%0") .. " <BR> ", "", 1)
                if needed and not tired then
                    tip.description = (rest == desc) and getText("IGUI_Sleep_NotTiredEnough")
                        or (getText("IGUI_Sleep_NotTiredEnough") .. " <BR> " .. rest)
                    log("sleep option: only companions near, but not tired")
                else
                    o.notAvailable = false
                    if rest == desc then o.toolTip = nil else tip.description = rest end
                    log("sleep option: only companions near, enabled")
                end
            end
        end
    end
end

BridgeSleep.wrap("load")
if Events ~= nil and Events.OnFillWorldObjectContextMenu ~= nil then
    Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
        pcall(BridgeSleep.fixSleepOption, playerNum, context, worldobjects, test)
    end)
end
if Events ~= nil and Events.OnGameStart ~= nil then
    Events.OnGameStart.Add(function() pcall(BridgeSleep.wrap, "game start") end)
end












BridgeSleep.SEARCH_CLOSE = 3
BridgeSleep.SEARCH_SEEN = 7
BridgeSleep.SEARCH_CACHE_MS = 250


function BridgeSleep.searchZombieBlock(playerObj)
    local stats = playerObj:getStats()
    local veryClose = stats:getNumVeryCloseZombies()
    local visible = stats:getNumVisibleZombies()
    local chasing = stats:getNumChasingZombies()
    if veryClose <= 0 and not (visible >= 3 and chasing >= 3) then return false end
    local px, py, pz = playerObj:getX(), playerObj:getY(), playerObj:getZ()
    local close2 = BridgeSleep.SEARCH_CLOSE * BridgeSleep.SEARCH_CLOSE
    local seen2 = BridgeSleep.SEARCH_SEEN * BridgeSleep.SEARCH_SEEN
    local ownClose, ownSeen, ownChasing = 0, 0, 0
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z ~= nil and z:isAlive() and not BridgeData.dragged(z) then
            local dx, dy = z:getX() - px, z:getY() - py
            local d2 = dx * dx + dy * dy
            local floor = math.abs(z:getZ() - pz) < 1
            if z:getVariableBoolean(Bridge.BODY_VAR) then
                if d2 < close2 then ownClose = ownClose + 1 end
                if d2 < seen2 then ownSeen = ownSeen + 1 end
                if z:getTarget() == playerObj then ownChasing = ownChasing + 1 end
            elseif floor and d2 < close2 then
                return true
            end
        end
    end
    if veryClose > ownClose then return true end
    return (visible - ownSeen) >= 3 and (chasing - ownChasing) >= 3
end


function BridgeSleep.searchOtherBlock(manager)
    local c = manager.character
    if (c:isRunning() or c:isSprinting() and c:isJustMoved()) then return true end
    if manager.searchMode:isOverrideSearchManager(manager.player) then return true end
    if isClient() then
        if not SafeHouse.isSafehouseAllowLoot(manager.square, c) then return true end
    end
    return false
end


BridgeSleep.searchCache = {}
function BridgeSleep.searchZombieBlockCached(playerObj)
    local now = getTimestampMs()
    local c = BridgeSleep.searchCache[playerObj]
    if c ~= nil and now - c.at < BridgeSleep.SEARCH_CACHE_MS then return c.block end
    local block = BridgeSleep.searchZombieBlock(playerObj)
    BridgeSleep.searchCache[playerObj] = { at = now, block = block }
    return block
end

if ISSearchManager ~= nil and ISSearchManager.checkShouldDisable ~= nil
    and not ISSearchManager.bridgeSearchWrapped then
    local original = ISSearchManager.checkShouldDisable
    ISSearchManager.checkShouldDisable = function(self, ...)
        if ISSearchManager.showDebug or self == nil or self.character == nil then
            return original(self, ...)
        end
        local ok, zombies = pcall(BridgeSleep.searchZombieBlockCached, self.character)
        if not ok then return original(self, ...) end
        if zombies then return true end
        return BridgeSleep.searchOtherBlock(self)
    end
    ISSearchManager.bridgeSearchWrapped = true
end























local SPEED_MULT = { [2] = 5.0, [3] = 20.0, [4] = 40.0 }
BridgeSleep.wantedSpeed = 1
BridgeSleep.restored = 0
BridgeSleep.blockedWhy = nil
BridgeSleep.traceLeft = 0
BridgeSleep.rateAt = nil

local function speedTrace(src, c)
    if BridgeSleep.traceLeft <= 0 then return end
    local mult, hours = -1, -1
    pcall(function() mult = getGameTime():getTrueMultiplier() end)
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    pcall(function()
        log(string.format("speedtrace t=%s %s speed=%s mult=%s want=%s hours=%s", tostring(Bridge.tick), tostring(src),
            tostring(c and c:getCurrentGameSpeed()), tostring(mult), tostring(BridgeSleep.wantedSpeed), tostring(hours)))
    end)
end

local function controls()
    local c = nil
    pcall(function() c = UIManager.getSpeedControls() end)
    return c
end




function BridgeSleep.speedBlocker(playerObj)
    if playerObj == nil then return "no player" end
    if Bridge == nil or not Bridge.alive() then return "no companion" end
    local body = Bridge.body
    local dx, dy = body:getX() - playerObj:getX(), body:getY() - playerObj:getY()
    if dx * dx + dy * dy > 8 * 8 then return "companion far" end
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local z = list:get(i)

        if z ~= nil and z:isAlive() and not Bridge.isCompanion(z) and not BridgeData.dragged(z) then
            local zx, zy = z:getX() - playerObj:getX(), z:getY() - playerObj:getY()
            local d2 = zx * zx + zy * zy
            if d2 < 4 * 4 then return "zombie within 4" end
            if d2 < 20 * 20 then
                local seen = false
                pcall(function() seen = playerObj:CanSee(z) end)
                if seen then return "zombie in sight" end
            end
            local chasing = false
            pcall(function() chasing = z:getTarget() == playerObj end)
            if chasing then return "zombie chasing" end
        end
    end
    return nil
end


function BridgeSleep.movementKeyDown()
    local down = false
    pcall(function()
        for _, name in ipairs({ "Forward", "Backward", "Left", "Right" }) do
            if GameKeyboard.isKeyDown(name) then down = true return end
        end
    end)
    return down
end


function BridgeSleep.onTickEvenPaused()
    if isClient() then return end
    local c = controls()
    if c == nil then return end
    local before = BridgeSleep.wantedSpeed
    BridgeSleep.wantedSpeed = c:getCurrentGameSpeed()




    if SPEED_MULT[BridgeSleep.wantedSpeed] ~= nil and BridgeSleep.movementKeyDown() then
        c:SetCurrentGameSpeed(1)
        BridgeSleep.wantedSpeed = 1
        log("movement key: fast forward stopped before the step")
    end
    if SPEED_MULT[BridgeSleep.wantedSpeed] ~= nil and BridgeSleep.wantedSpeed ~= before then
        BridgeSleep.traceLeft = 120
        BridgeSleep.rateAt = nil
    end
    speedTrace("evenPaused", c)
    if BridgeSleep.traceLeft > 0 then BridgeSleep.traceLeft = BridgeSleep.traceLeft - 1 end

    if SPEED_MULT[BridgeSleep.wantedSpeed] ~= nil then
        pcall(function()
            local hours = getGameTime():getWorldAgeHours()
            local now = getTimestampMs()
            local r = BridgeSleep.rateAt
            if r == nil then
                BridgeSleep.rateAt = { hours = hours, ms = now }
            elseif now - r.ms >= 5000 then
                log(string.format("speed rate x%d: %.3f game hours in %.1f s", BridgeSleep.wantedSpeed,
                    hours - r.hours, (now - r.ms) / 1000))
                BridgeSleep.rateAt = { hours = hours, ms = now }
            end
        end)
    end
end


function BridgeSleep.onPlayerUpdate(playerObj)
    if isClient() or playerObj ~= BridgeData.owner() then return end
    local c = controls()
    speedTrace("playerUpdate", c)
    if c ~= nil and c:getCurrentGameSpeed() == 1 then BridgeSleep.wantedSpeed = 1 end
end



function BridgeSleep.keepSpeed(src)
    if isClient() then return end
    local want = BridgeSleep.wantedSpeed
    local mult = SPEED_MULT[want]
    if mult == nil then return end
    local c = controls()
    if c == nil then return end
    speedTrace(tostring(src or "tick"), c)
    if c:getCurrentGameSpeed() ~= 1 then

        local tm = 0
        pcall(function() tm = getGameTime():getTrueMultiplier() end)
        if c:getCurrentGameSpeed() == want and (tm or 0) < mult then
            getGameTime():setMultiplier(mult)
            pcall(function() c:SetCorrectIconStates() end)
        end
        return
    end
    local ok, why = pcall(function() return BridgeSleep.speedBlocker(BridgeData.owner()) end)
    if not ok then why = "error: " .. tostring(why) end
    if why ~= nil then
        if BridgeSleep.blockedWhy ~= why then
            BridgeSleep.blockedWhy = why
            log("speed not kept: " .. tostring(why))
        end
        BridgeSleep.wantedSpeed = 1
        return
    end
    BridgeSleep.blockedWhy = nil
    c:SetCurrentGameSpeed(want)
    getGameTime():setMultiplier(mult)

    pcall(function() c:SetCorrectIconStates() end)
    BridgeSleep.restored = BridgeSleep.restored + 1
    if BridgeSleep.restored == 1 or BridgeSleep.restored % 3600 == 0 then
        log("speed kept near companion: x" .. tostring(want) .. " times=" .. tostring(BridgeSleep.restored))
    end
end





BridgeSleep.speedKeepEnabled = false
if BridgeSleep.speedKeepEnabled then
    Events.OnTickEvenPaused.Add(BridgeSleep.onTickEvenPaused)
    Events.OnPlayerUpdate.Add(BridgeSleep.onPlayerUpdate)
    Events.OnTick.Add(function() BridgeSleep.keepSpeed("tick") end)
    Events.OnPreUIDraw.Add(function() BridgeSleep.keepSpeed("ui") end)
end

log("loaded")

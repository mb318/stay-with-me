



BridgeMove = BridgeMove or {}

local FOLLOW_START = 2.0
local FOLLOW_STOP = 0.9
local FOLLOW_GAP = 1.2
local RUN_DIST = 3.5
local RUN_STOP = 2.0

BridgeMove.moving = false
BridgeMove.pathing = false
BridgeMove.goal = nil
BridgeMove.lastPath = 0
BridgeMove.walkType = "Walk"
BridgeMove.pathResult = "none"
BridgeMove.obstacle = "none"
BridgeMove.window = nil
BridgeMove.redAt = nil
BridgeMove.redPrev = nil







local ASIDE_AHEAD = 0.7
local ASIDE_PUSH = 20
local PUSH_GRACE = 12
local ASIDE_PATH = 0.55
local ASIDE_STEP = 0.5
local ASIDE_MAX = 45
local ASIDE_QUIET = 90


local RUN_AHEAD = 2.5
local RUN_PATH = 0.7
local COMING_COS = 0.5
BridgeMove.redStep = 0
BridgeMove.redHist = nil
local RED_WIN = 5
BridgeMove.redMoving = false
BridgeMove.speed = 1.0
BridgeMove.wasWalking = false
BridgeMove.restarts = 0

BridgeMove.replanDist = 0.6
BridgeMove.pathEvery = 15
BridgeMove.speedMode = "fixed"
BridgeMove.fixedSpeed = 1.0
BridgeMove.startBump = "off"
BridgeMove.traceUntil = 0
BridgeMove.climbUntil = 0
BridgeMove.stepTick = -9999
BridgeMove.stepPos = nil
BridgeMove.stride = false

BridgeMove.blendOverride = nil
BridgeMove.speedModOverride = nil
BridgeMove.animOld = false
BridgeMove.walkSpeedVar = 1.0
BridgeMove.runBlend = 0.65
BridgeMove.runReplan = 1.8
BridgeMove.runEvery = 30
BridgeMove.lastRestart = -9999
BridgeMove.steerMode = true
BridgeMove.steering = false
BridgeMove.trail = {}
BridgeMove.redSpeed = 0
BridgeMove.stepPerMul = 0.07
BridgeMove.walkFrames = 0
BridgeMove.follow = {kind = "none", s = 0, want = 0, gap = 0}
BridgeMove.noCollide = false
BridgeMove.collideOff = false
BridgeMove.bumpMove = "face"
BridgeMove.followWs = nil
BridgeMove.turnLimit = nil
BridgeMove.doorGhost = true




BridgeMove.speedModel = {
    Walk = { a = 0.024, b = 0.015 }, Run = { a = 0.030, b = 0.057 },
    WalkSneak = { a = 0.024, b = 0.007 }, RunSneak = { a = 0.028, b = 0.034 },
}






BridgeMove.catchUp = true
BridgeMove.aheadPivot = false
BridgeMove.speedScale = 1.0
BridgeMove.speedScaleN = 0


local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeMove] " .. tostring(text)) end end
local function warn(text) print("[BridgeMove] " .. tostring(text)) end




local rawFormat = string.format
local function sformat(f, ...)
    local args = { ... }
    local n = select("#", ...)
    local i = 0
    for spec in string.gmatch(f, "%%[-+ #0]*%d*%.?%d*([%a%%])") do
        if spec ~= "%" then
            i = i + 1
            local v = args[i]
            if (spec == "d" or spec == "i") and type(v) == "number" and v ~= math.floor(v) then
                args[i] = math.floor(v + 0.5)
            end
        end
    end
    return rawFormat(f, (table.unpack or unpack)(args, 1, n))
end







local function frameDt()
    local dt = Bridge.dt
    if type(dt) ~= "number" or dt ~= dt or dt <= 0 then return 1 end
    return dt
end
BridgeMove.frameDt = frameDt





local function wrapPi(a)
    return a - 2 * math.pi * math.floor((a + math.pi) / (2 * math.pi))
end
BridgeMove.wrapPi = wrapPi

local function dist2d(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end



local function setStride(body, on)
    if on == BridgeMove.stride then return end
    BridgeMove.stride = on
    pcall(function() body:setVariable("NotAloneStride", on) end)
end

local function trackStep(body)
    local px, py = body:getX(), body:getY()
    local prev = BridgeMove.stepPos
    if prev ~= nil then
        local dx, dy = px - prev.x, py - prev.y
        if dx * dx + dy * dy > 0.0001 then BridgeMove.stepTick = Bridge.time end
    end
    BridgeMove.stepPos = { x = px, y = py }
    setStride(body, BridgeMove.pathing and (Bridge.time - BridgeMove.stepTick) < 20)
end







function BridgeMove.setCollide(body, on)


    if on then
        if not BridgeMove.collideOff then return end
        BridgeMove.collideOff = false
        pcall(function() body:setCollidable(true) end)
        return
    end
    BridgeMove.collideOff = true
    pcall(function() body:setCollidable(false) end)
end



local function isFollowBump(bump)
    return bump == "FollowWalk" or bump == "FollowRun"
end





function BridgeMove.turnToward(body, px, py, maxDeg)
    if BridgeMove.turnLimit == nil then
        pcall(function() body:faceLocationF(px, py) end)
        return
    end
    maxDeg = BridgeMove.turnLimit
    pcall(function()
        local bx, by = body:getX(), body:getY()
        local tx, ty = px - bx, py - by
        local tl = math.sqrt(tx * tx + ty * ty)
        if tl < 0.01 then return end
        local fwd = body:getForwardDirection()
        local fx, fy = fwd:getX(), fwd:getY()
        local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
        local cur = atan2(fy, fx)
        local want = atan2(ty, tx)
        local diff = wrapPi(want - cur)
        local lim = math.rad((maxDeg or 18) * frameDt())
        if diff > lim then diff = lim elseif diff < -lim then diff = -lim end
        local a = cur + diff
        body:faceLocationF(bx + math.cos(a), by + math.sin(a))
    end)
end







local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
function BridgeMove.pivotToward(body, px, py, maxDeg)
    local ok, left = pcall(function()
        local tx, ty = px - body:getX(), py - body:getY()
        if tx * tx + ty * ty < 0.0001 then return 0 end
        local cur = body:getAnimAngleRadians()
        local diff = wrapPi(atan2(ty, tx) - cur)

        local lim = math.rad(maxDeg * frameDt())
        local step = diff
        if step > lim then step = lim elseif step < -lim then step = -lim end
        body:setTargetAndCurrentDirection(math.cos(cur + step), math.sin(cur + step))
        return math.abs(diff - step)
    end)
    if ok then return left end

    if not BridgeMove.pivotFailed then
        BridgeMove.pivotFailed = true
        warn("seat: pivot failed, turning as before: " .. tostring(left))
    end
    return nil
end



function BridgeMove.facingOff(body, px, py)
    local ok, deg = pcall(function()
        local cur = body:getAnimAngleRadians()
        local diff = wrapPi(atan2(py - body:getY(), px - body:getX()) - cur)
        return math.floor(math.abs(math.deg(diff)) + 0.5)
    end)
    if ok then return deg end
    return nil
end

function BridgeMove.followBump(body, walk)
    local want = walk == "Run" and "FollowRun" or "FollowWalk"
    pcall(function()
        body:setVariable("bPathfind", false)
        body:setMoving(false)
        if tostring(body:getBumpType()) ~= want then
            body:setVariable("BumpAnimFinished", false)
            body:setBumpType(want)
        end
    end)

    if BridgeFastForward ~= nil then pcall(BridgeFastForward.keepMoving, body) end
end


function BridgeMove.endFollowBump(body, to)
    pcall(function()
        if isFollowBump(tostring(body:getBumpType())) then
            if to == "" then



                local flagged = BridgeFastForward ~= nil and BridgeFastForward.flagged == body
                    and tostring(body:getActionStateName()) == "bumped"
                if flagged then BridgeMove.startKick(body) else BridgeMove.releaseBump(body) end
            else
                body:setBumpType(to)
            end
        end
    end)
end






function BridgeMove.releaseBump(body)
    pcall(function()
        if tostring(body:getActionStateName()) == "bumped" then body:setVariable("BumpAnimFinished", true) end
        body:setBumpType("")
    end)
end









local KICK = "StartMove"
local KICK_MAX = 50
BridgeMove.KICK = KICK

function BridgeMove.startKick(body)



    pcall(function()
        local asn = tostring(body:getActionStateName())
        if asn ~= "walktoward" and asn ~= "pathfind" then body:setMoving(false) end
    end)
    pcall(function()
        body:setVariable("BumpAnimFinished", false)
        body:setBumpType(KICK)
    end)
    BridgeMove.kickAt = Bridge.time
    BridgeMove.kickIn = false
end





function BridgeMove.kickStep(body, pf)
    if BridgeMove.kickAt == nil then return end
    local bump, asn = "", ""
    pcall(function()
        bump = tostring(body:getBumpType())
        asn = tostring(body:getActionStateName())
    end)
    if bump ~= KICK then BridgeMove.kickAt = nil return end
    if asn == "bumped" then BridgeMove.kickIn = true end
    local found = false


    local forced = BridgeFastForward ~= nil and BridgeFastForward.forcedMove ~= nil
    pcall(function() found = pf:hasStartedMoving() or (body:isMoving() and not forced) end)
    local ready = found and BridgeMove.kickIn
    if ready or Bridge.time - BridgeMove.kickAt >= KICK_MAX then
        BridgeMove.releaseBump(body)
        if Bridge.verbose then
            log(string.format("start from standing: %s after %.2f s", ready and "path ready, moving"
                or (found and ("path ready, never in the stance (state " .. asn .. "), released")
                or "no path yet, released"), (Bridge.time - BridgeMove.kickAt) / 60))
        end
        BridgeMove.kickAt = nil
    end
end




function BridgeMove.onPath()
    return BridgeMove.pathing or BridgeMove.steering or BridgeMove.kickAt ~= nil
end

function BridgeMove.stopPath(body)
    BridgeMove.setCollide(body, true)
    if BridgeMove.steering then BridgeMove.endFollowBump(body, "Stand") end

    if BridgeMove.kickAt ~= nil then
        pcall(function() if tostring(body:getBumpType()) == KICK then body:setBumpType("Stand") end end)
        BridgeMove.kickAt = nil
    end
    pcall(function()
        local pf = body:getPathFindBehavior2()
        pf:cancel()
        pf:reset()
        body:setPath2(nil)
    end)
    if BridgeMove.steering then
        pcall(function() body:setMoving(false) end)
        BridgeMove.steering = false
    end
    BridgeMove.pathing = false
    BridgeMove.goal = nil
    BridgeMove.redAt = nil
    BridgeMove.wasWalking = false
    setStride(body, false)

    if BridgeFastForward ~= nil then pcall(BridgeFastForward.keepMoving, body) end
end













local nearCache = nil
local function nearRed(red, body)
    local rx, ry = math.floor(red:getX()), math.floor(red:getY())
    local rz = red:getZ()
    local bx, by = body:getX(), body:getY()
    local key = rx .. "," .. ry .. "," .. math.floor(rz) .. ">" .. math.floor(bx) .. "," .. math.floor(by)
    if nearCache ~= nil and nearCache.key == key and Bridge.time - nearCache.tick < 30 then
        return nearCache.x, nearCache.y, rz
    end
    local dx, dy = bx - red:getX(), by - red:getY()
    local first
    if math.abs(dx) >= math.abs(dy) then
        first = { (dx >= 0) and 1 or -1, 0 }
    else
        first = { 0, (dy >= 0) and 1 or -1 }
    end
    local sides = { first }
    local rest = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    table.sort(rest, function(a, b)
        return dist2d(bx, by, rx + a[1] + 0.5, ry + a[2] + 0.5) < dist2d(bx, by, rx + b[1] + 0.5, ry + b[2] + 0.5)
    end)
    for _, s in ipairs(rest) do
        if s[1] ~= first[1] or s[2] ~= first[2] then sides[#sides + 1] = s end
    end
    local cell = getCell()
    local z = math.floor(rz)
    local rsq = cell and cell:getGridSquare(rx, ry, z)
    for _, s in ipairs(sides) do
        local open = true
        if rsq ~= nil then
            open = false
            pcall(function()
                local n = cell:getGridSquare(rx + s[1], ry + s[2], z)
                open = n ~= nil and not rsq:isBlockedTo(n) and BridgeMove.edgeBetween(body, rsq, n) == nil
                    and n:isFree(false)
            end)
        end
        if open then

            local x, y = rx + s[1] + 0.5 - s[1] * 0.3, ry + s[2] + 0.5 - s[2] * 0.3
            nearCache = { key = key, tick = Bridge.time, x = x, y = y }
            return x, y, rz
        end
    end
    local x, y = rx + first[1] + 0.5 - first[1] * 0.3, ry + first[2] + 0.5 - first[2] * 0.3
    nearCache = { key = key, tick = Bridge.time, x = x, y = y }
    return x, y, rz
end
BridgeMove.nearRed = nearRed
BridgeMove.nearReset = function() nearCache = nil end






function BridgeMove.applyAnimVars(body)
    local ws = BridgeMove.blendOverride
    if ws == nil and BridgeMove.steering and BridgeMove.followWs ~= nil then ws = BridgeMove.followWs end
    if ws == nil and not (BridgeMove.steering and BridgeMove.followWs ~= nil) then
        local red = BridgeData.owner()
        local redWs, redRuns = nil, false
        if red ~= nil then
            pcall(function() redWs = red:getVariableFloat("WalkSpeed", 1.0) end)
            pcall(function() redRuns = red:isRunning() or red:isSprinting() end)
        end

        if redRuns and redWs ~= nil and redWs >= 0.3 then BridgeMove.runBlend = redWs end
        if BridgeMove.walkType == "Run" then


            ws = redRuns and redWs or BridgeMove.runBlend
        else

            ws = (not redRuns) and redWs or 1.0
        end
        if ws == nil or ws < 0.3 then ws = 1.0 end
    end
    BridgeMove.walkSpeedVar = ws
    pcall(function()
        body:setVariable("WalkSpeed", ws)
        body:setVariable("WalkInjury", 0.0)
        body:setVariable("NotAloneAnimOld", BridgeMove.animOld == true)
    end)
    if BridgeMove.speedModOverride ~= nil then
        pcall(function() body:setSpeedMod(BridgeMove.speedModOverride) end)
    end
end














local TRAIL_STEP = 0.5
local TRAIL_MAX = 60
local GAP_WALK = 1.4
local GAP_RUN = 1.9
local STOP_GAP = 1.3
local START_DIST = 2.2
local START_GOING = 0.85
local SEE_FAR = 14
local SLOW_RED = 1.15
local SLOW_FRAMES = 45
local SLOW_GO = 0.45
local CATCH_FROM = 1.0
local CATCH_FULL = 2.5
local NO_LINE_FRAMES = 20
local AHEAD_PIVOT_DEG = 45
local STUCK_LEAVE = 1.5
local STUCK_LEAVE_AGAIN = 3.0
local DOORWAY_STOP = 1.0
local DOORWAY_ROOM = 1.2
local DOORWAY_CLEAR = 0.3

function BridgeMove.addTrail(red)
    local t = BridgeMove.trail
    local x, y, z = red:getX(), red:getY(), red:getZ()
    local last = t[#t]
    if last ~= nil and (math.abs(last.z - z) > 0.5 or dist2d(last.x, last.y, x, y) > 3) then

        BridgeMove.trail = {}
        t = BridgeMove.trail
        last = nil
    end
    if last == nil or dist2d(last.x, last.y, x, y) >= TRAIL_STEP then
        t[#t + 1] = { x = x, y = y, z = z }
        if #t > TRAIL_MAX then table.remove(t, 1) end
    end
end



function BridgeMove.followTarget(body, red)
    local rx, ry, rz = red:getX(), red:getY(), red:getZ()
    local bx, by = body:getX(), body:getY()
    local d = dist2d(bx, by, rx, ry)
    if d > SEE_FAR then return nil end
    if BridgeMove.lineClear(body, rx, ry, rz) then return rx, ry, rz, "player", d end
    local t = BridgeMove.trail
    local tail = 0
    local prevx, prevy = rx, ry
    for i = #t, math.max(1, #t - 25), -1 do
        local c = t[i]
        tail = tail + dist2d(prevx, prevy, c.x, c.y)
        prevx, prevy = c.x, c.y


        if tail > 9 then break end
        if dist2d(bx, by, c.x, c.y) <= SEE_FAR and BridgeMove.lineClear(body, c.x, c.y, c.z) then
            return c.x, c.y, c.z, "trail", dist2d(bx, by, c.x, c.y) + tail
        end
    end
    return nil
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end


function BridgeMove.trailPoint(red, gap)
    local t = BridgeMove.trail
    local px, py = red:getX(), red:getY()
    local acc = 0
    for i = #t, 1, -1 do
        local c = t[i]
        local seg = dist2d(px, py, c.x, c.y)
        if seg > 0.001 and acc + seg >= gap then
            local k = (gap - acc) / seg
            return px + (c.x - px) * k, py + (c.y - py) * k
        end
        acc = acc + seg
        px, py = c.x, c.y
    end
    return px, py
end



local function blockedAhead(body)
    local blocked = false
    pcall(function()
        local a = body:getAnimAngleRadians()
        local bx, by = body:getX(), body:getY()
        local cx, cy = math.floor(bx), math.floor(by)
        local nx, ny = math.floor(bx + math.cos(a) * 0.45), math.floor(by + math.sin(a) * 0.45)
        if cx == nx and cy == ny then return end
        local cell = getCell()
        local z = math.floor(body:getZ())
        local me, sq = cell:getGridSquare(cx, cy, z), cell:getGridSquare(nx, ny, z)
        if me == nil or sq == nil then return end
        local function shut(from, to)
            return to == nil or from:isBlockedTo(to) or BridgeMove.engineBlocked(from, to)
        end
        if cx ~= nx and cy ~= ny then
            blocked = shut(me, cell:getGridSquare(nx, cy, z)) or shut(me, cell:getGridSquare(cx, ny, z)) or not sq:isFree(false)
        else
            blocked = shut(me, sq) or not sq:isFree(false)
        end
    end)
    return blocked
end


function BridgeMove.aheadText(body, px, py)
    local text = "?"
    pcall(function()
        local bx, by = body:getX(), body:getY()
        local dist = dist2d(bx, by, px, py)
        if dist < 0.01 then text = "goal reached" return end
        local cell = getCell()
        local z = math.floor(body:getZ())
        local me = cell:getGridSquare(math.floor(bx), math.floor(by), z)
        local ax, ay = bx + (px - bx) / dist * 0.7, by + (py - by) / dist * 0.7
        local sq = cell:getGridSquare(math.floor(ax), math.floor(ay), z)
        if me == nil or sq == nil then text = "no square ahead" return end
        local parts = { sformat("ahead %d,%d", sq:getX(), sq:getY()) }
        if sq == me then parts[#parts + 1] = "same square" end
        if not sq:isFree(false) then parts[#parts + 1] = "occupied" end
        if sq.HasStairs ~= nil then
            if sq:HasStairs() then parts[#parts + 1] = "stairs" end
            if me:HasStairs() then parts[#parts + 1] = "on stairs" end
        end
        if sq:isVehicleIntersecting() then parts[#parts + 1] = "vehicle" end
        if sq ~= me and math.abs(sq:getX() - me:getX()) + math.abs(sq:getY() - me:getY()) == 1 then
            if me:isBlockedTo(sq) then parts[#parts + 1] = "wall" end
            if BridgeMove.engineBlocked(me, sq) then parts[#parts + 1] = "engine blocks the step" end
        end
        local movers = sq:getMovingObjects()
        if movers ~= nil and movers:size() > 0 then parts[#parts + 1] = "movers " .. movers:size() end
        parts[#parts + 1] = sformat("z %.2f", body:getZ())
        text = table.concat(parts, ", ")
    end)
    return text
end

local GAIT_HOLD = 24




local function drive(body, red, F, pf, bx, by, px, py, want, kind, running, d, err)
    local s = clamp(want / math.max(0.02, BridgeMove.stepPerMul), 0.15, 1.6)

    local st = ""
    pcall(function() st = body:getActionStateName() end)
    BridgeMove.walkFrames = (st == "walktoward" or st == "bumped") and (BridgeMove.walkFrames + frameDt()) or 0
    local free = dist2d(bx, by, px, py)


    if F.frame == Bridge.tick - 1 and F.px ~= nil then

        local el = (F.time ~= nil and Bridge.time - F.time > 0) and (Bridge.time - F.time) or frameDt()
        F.lastStep = dist2d(F.px, F.py, bx, by) / el
    else
        F.lastStep = nil
    end
    if BridgeMove.walkFrames > 25 and F.s and F.s > 0.3 and F.lastStep and F.lastStep > 0.01
        and F.lastFree and F.lastFree > F.lastStep + 0.05 then
        BridgeMove.stepPerMul = clamp(BridgeMove.stepPerMul * 0.9 + (F.lastStep / F.s) * 0.1, 0.02, 0.15)
    end

    if F.lastStep ~= nil and (F.s or 0) >= 0.3 and (F.lastFree or 0) > 0.3 and F.lastStep < 0.004 then
        F.stuck = (F.stuck or 0) + frameDt()
    else
        F.stuck = 0
    end



    if F.frame ~= Bridge.tick - 1 then F.netFrame = nil end
    if F.netFrame == nil or Bridge.time - F.netFrame >= 40 then
        if F.netFrame ~= nil and F.netX ~= nil and dist2d(F.netX, F.netY, bx, by) < 0.25 and want > 0.015 then
            F.stuck = 20
        end
        F.netFrame, F.netX, F.netY = Bridge.time, bx, by
    end
    if F.stuck >= 12 then
        F.stuck = 0





        local at = F.stuckAt
        local again = at ~= nil and Bridge.time - at.tick < 600 and dist2d(at.x, at.y, bx, by) < 1.5
        F.stuckAt = { x = bx, y = by, tick = Bridge.time, leave = again and STUCK_LEAVE_AGAIN or STUCK_LEAVE }
        BridgeMove.stuckCount = (BridgeMove.stuckCount or 0) + 1
        F.pathMin = Bridge.time + 60
        F.pathUntil = Bridge.time + (again and 480 or 240)
        BridgeMove.steering = false
        BridgeMove.setCollide(body, true)
        BridgeMove.endFollowBump(body, "")
        log(sformat("follow stuck at %.2f %.2f going to %.2f %.2f (%s)%s, path until %.1f cells away: %s", bx, by, px, py,
            tostring(kind), again and ", again here" or "", F.stuckAt.leave, BridgeMove.aheadText(body, px, py)))
        return false
    end


    local ghost = BridgeMove.doorGhost and F.cross ~= nil and F.cross.door == true
    BridgeMove.setCollide(body, not (BridgeMove.noCollide or ghost))
    if BridgeMove.bumpMove == "face" then

        local M = BridgeMove.speedModel
        local sneaking = false
        pcall(function() sneaking = red:isSneaking() end)
        local nameWalk = sneaking and "WalkSneak" or "Walk"
        local nameRun = sneaking and "RunSneak" or "Run"



        local cal = F.cal
        if cal ~= nil and cal.bump == tostring(body:getBumpType()) and BridgeMove.walkFrames > 25 and (F.stuck or 0) == 0 then
            local ticks = Bridge.time - cal.tick
            if ticks >= 1 and ticks <= 3 and cal.free > 0.6 then
                local step = dist2d(cal.x, cal.y, bx, by) / ticks
                local pred = cal.pred
                if pred > 0.01 and step >= 0.5 * pred * BridgeMove.speedScale and step <= 3.5 * pred then
                    local ratio = clamp(step / pred, 0.6, 3.0)
                    local k = BridgeMove.speedScaleN < 40 and 0.10 or 0.02
                    BridgeMove.speedScale = BridgeMove.speedScale * (1 - k) + ratio * k
                    BridgeMove.speedScaleN = BridgeMove.speedScaleN + 1
                end
            end
        end
        local scale = BridgeMove.speedScale
        local wantT = want / scale
        local walkMax = M[nameWalk].a + M[nameWalk].b





        local gait = F.gait or BridgeMove.walkType



        local mayChange = F.gaitAt == nil or Bridge.time - F.gaitAt >= GAIT_HOLD
        if mayChange then



            if gait == "Run" then
                if wantT <= walkMax and not running then gait = "Walk" end
            elseif wantT > walkMax + 0.012 or running then
                gait = "Run"
            end
        end
        local prevGait = F.gait
        if prevGait ~= nil and prevGait ~= gait then F.gaitAt = Bridge.time end
        F.gait = gait
        BridgeMove.walkType = gait
        local m = M[gait == "Run" and nameRun or nameWalk]
        local prevWs = BridgeMove.followWs
        BridgeMove.followWs = clamp((wantT - m.a) / m.b, 0, 1)


        if Bridge.verbose and prevGait ~= gait then
            log(sformat("gait %s -> %s: want %.3f (table %.3f), mix %.2f -> %.2f, player %.3f, d %.2f, err %.2f",
                tostring(prevGait), gait, want, wantT, prevWs or -1, BridgeMove.followWs, BridgeMove.redSpeed, d, err or 0))
        end
        F.cal = { tick = Bridge.time, x = bx, y = by, free = free, bump = gait == "Run" and "FollowRun" or "FollowWalk",
                  pred = m.a + m.b * BridgeMove.followWs }
        BridgeMove.applyAnimVars(body)
        BridgeMove.followBump(body, gait)
        local pivotDeg = nil
        if kind == "seat" or kind == "aside" then pivotDeg = BridgeMove.SEAT_PIVOT_DEG
        elseif kind == "mourn" then pivotDeg = BridgeMove.MOURN_PIVOT_DEG end
        if pivotDeg ~= nil and BridgeMove.pivotToward(body, px, py, pivotDeg) ~= nil then

        else




            local off = BridgeMove.facingOff(body, px, py)
            if BridgeMove.aheadPivot and off ~= nil and off > 30 and blockedAhead(body) then
                BridgeMove.pivotToward(body, px, py, AHEAD_PIVOT_DEG)
                F.pivots = (F.pivots or 0) + 1
            end
            BridgeMove.turnToward(body, px, py, 18)
        end
    else
        BridgeMove.followBump(body, BridgeMove.walkType)
        pcall(function() pf:moveToPoint(px, py, s) end)
    end
    F.ws = BridgeMove.followWs or -1
    F.px, F.py, F.frame, F.time = bx, by, Bridge.tick, Bridge.time
    F.lastFree = free
    F.kind, F.s, F.want, F.gap = kind, s, want, err
    F.tx, F.ty = px, py

    BridgeMove.goal = { x = red:getX(), y = red:getY() }
    BridgeMove.pathResult = "follow-" .. kind
    BridgeMove.wasWalking = true
    trackStep(body)
    setStride(body, true)
    BridgeMove.traceFrame(body, d, false, false)
    return true
end










local SPOT_SIDE = 1.3
local SPOT_BACK = 0.35
local SPOT_FAR = 1.0
local CORPSE_EXTRA = 1.0
local SPOT_REACH = 6
local SPOT_TURN = math.cos(math.rad(50))
local SPOT_ENTER = 8
local SPOT_LEAVE = 4
local SPOT_ARRIVE = 0.35
local SPOT_START = 0.7

function BridgeMove.keepSide()
    local side = "behind"
    pcall(function() side = BridgeData.keepOf(Bridge.store) end)
    return side
end

function BridgeMove.keepFar()
    local far = false
    pcall(function() far = BridgeData.farOf(Bridge.store) end)
    return far
end



function BridgeMove.redDragsCorpse()
    local red = BridgeData.owner()
    local drag = false
    if red ~= nil then
        pcall(function()
            if red.isDraggingCorpse ~= nil then drag = red:isDraggingCorpse() == true end
        end)
    end
    return drag
end




local function keepExtra()
    if BridgeMove.keepFar() then return SPOT_FAR end
    return BridgeMove.redDragsCorpse() and CORPSE_EXTRA or 0
end

function BridgeMove.spotReset()
    local F = BridgeMove.follow
    F.spotHx, F.spotHy, F.spotOk, F.spotBad, F.inSpot, F.spotStand = nil, nil, 0, 0, false, false
end


function BridgeMove.spotPoint(red, keep, far, F, redGoes)
    local vx, vy = BridgeMove.redVx or 0, BridgeMove.redVy or 0
    local vl = math.sqrt(vx * vx + vy * vy)
    if redGoes and vl > 0.01 then
        F.spotHx, F.spotHy = vx / vl, vy / vl
    else
        local fx, fy = nil, nil
        pcall(function()
            local fwd = red:getForwardDirection()
            fx, fy = fwd:getX(), fwd:getY()
        end)
        if fx ~= nil then
            local fl = math.sqrt(fx * fx + fy * fy)
            if fl > 0.001 then
                fx, fy = fx / fl, fy / fl
                if F.spotHx == nil or (F.spotHx * fx + F.spotHy * fy) < SPOT_TURN then F.spotHx, F.spotHy = fx, fy end
            end
        end
    end
    local hx, hy = F.spotHx, F.spotHy
    if hx == nil then return nil end
    local extra = far and SPOT_FAR or 0
    local rx, ry = red:getX(), red:getY()

    local sgn = (keep == "right") and 1 or -1
    local side = SPOT_SIDE + extra
    return rx - hy * side * sgn - hx * SPOT_BACK, ry + hx * side * sgn - hy * SPOT_BACK, hx, hy
end



function BridgeMove.spotFree(body, red, px, py)
    local z = red:getZ()
    if math.abs(body:getZ() - z) >= 0.5 then return false, "other floor" end
    if not BridgeMove.lineClear(red, px, py, z) then return false, "player does not see the spot" end
    local free = false
    pcall(function()
        local sq = getCell():getGridSquare(math.floor(px), math.floor(py), math.floor(z))
        free = sq ~= nil and sq:isFree(false)
    end)
    if not free then return false, "square busy" end
    if not BridgeMove.lineClear(body, px, py, z) then return false, "she does not see the spot" end
    return true, "ok"
end




local function keepLog(F, keep, what, why, toSpot, d, redGoes)
    if Bridge == nil or not Bridge.verbose then return end
    local key = tostring(what) .. "|" .. tostring(why)
    if F.keepKey == key and F.keepSide == keep then return end
    F.keepKey, F.keepSide = key, keep
    log(sformat("keep %s%s: %s (%s) spot=%.2f player=%.2f redGoes=%s t=%d", tostring(keep),
        BridgeMove.keepFar() and " far" or "", tostring(what), tostring(why), toSpot or -1, d or -1,
        tostring(redGoes), Bridge.time))
end





local DETOUR_CLOSE = 0.9
local DETOUR_R = 1.2
local function detour(rx, ry, hx, hy, bx, by, px, py, goes)
    local ax, ay = bx - rx, by - ry
    local tx, ty = px - rx, py - ry
    local sx, sy = tx - ax, ty - ay
    local l2 = sx * sx + sy * sy
    local u = 0
    if l2 > 1e-6 then u = clamp(-(ax * sx + ay * sy) / l2, 0, 1) end
    local cx, cy = ax + sx * u, ay + sy * u


    if u <= 0.05 or cx * cx + cy * cy >= DETOUR_CLOSE * DETOUR_CLOSE then return px, py end
    local ra = math.sqrt(ax * ax + ay * ay)
    if ra < 0.05 then return px, py end
    local r = math.max(ra, DETOUR_R)
    local ux, uy = ax / ra, ay / ra
    local function turn(a)
        return ux * math.cos(a) - uy * math.sin(a), ux * math.sin(a) + uy * math.cos(a)
    end

    local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
    local function ang(vx, vy) return atan2(hx * vy - hy * vx, hx * vx + hy * vy) end
    local tb, tt = ang(ax, ay), ang(tx, ty)
    local dlt = tt - tb
    while dlt > math.pi do dlt = dlt - 2 * math.pi end
    while dlt <= -math.pi do dlt = dlt + 2 * math.pi end
    local dir = (dlt >= 0) and 1 or -1



    if goes then
        local a1 = tb + dlt
        if (tb < 0 and a1 > 0) or (tb > 0 and a1 < 0) then dir = -dir end
    end
    local wx, wy = turn(dir * math.rad(60))
    return rx + wx * r, ry + wy * r
end



local function followSpot(body, red, F, pf, d, redGoes, running, keep)
    local px, py, hx, hy = BridgeMove.spotPoint(red, keep, BridgeMove.keepFar(), F, redGoes)
    if px == nil then return nil end
    local bx, by = body:getX(), body:getY()
    local toSpot = dist2d(bx, by, px, py)
    local free, why = false, "too far from the spot"
    if toSpot <= SPOT_REACH then free, why = BridgeMove.spotFree(body, red, px, py) end
    local ok = free == true
    if ok then
        F.spotOk, F.spotBad = (F.spotOk or 0) + frameDt(), 0
    else
        F.spotOk, F.spotBad = 0, (F.spotBad or 0) + frameDt()
    end
    if F.inSpot then
        if (F.spotBad or 0) >= SPOT_LEAVE then F.inSpot = false end
    elseif (F.spotOk or 0) >= SPOT_ENTER then
        F.inSpot = true
    end
    if not F.inSpot then
        keepLog(F, keep, "behind on the trail", why, toSpot, d, redGoes)
        return nil
    end

    if not ok and F.spotX ~= nil then px, py = F.spotX, F.spotY end
    F.spotX, F.spotY = px, py
    local dx, dy = px - bx, py - by
    local along = dx * hx + dy * hy

    if redGoes then
        F.spotStand = false
    elseif F.spotStand then
        if toSpot > SPOT_START then F.spotStand = false end
    elseif toSpot <= SPOT_ARRIVE then
        F.spotStand = true
    end
    if F.spotStand then
        if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        BridgeMove.moving = false
        F.kind, F.s, F.want = "spot-stand", 0, 0

        if Bridge.zombieTicks % 30 == 0 then
            pcall(function() body:faceLocationF(px + hx * 3, py + hy * 3) end)
        end
        keepLog(F, keep, "stands on the spot", "arrived", toSpot, d, redGoes)
        BridgeMove.goal = { x = red:getX(), y = red:getY() }
        BridgeMove.pathResult = "follow-spot-stand"
        trackStep(body)
        BridgeMove.traceFrame(body, d, false, false)
        return true
    end
    BridgeMove.moving = true
    Bridge.holdPos = nil
    if BridgeMove.pathing then
        pcall(function() pf:cancel() pf:reset() body:setPath2(nil) end)
        BridgeMove.pathing = false
    end
    BridgeMove.steering = true
    local want, tx, ty
    if redGoes then


        want = BridgeMove.redSpeed * clamp(1 + 0.9 * along, 0.3, 1.8) + 0.02 * math.max(0, toSpot - 0.6)
        if toSpot < 1.5 then tx, ty = px + hx * 0.8, py + hy * 0.8 else tx, ty = px, py end
    else

        want = 0.036 * clamp(0.4 + 0.6 * toSpot, 0.35, 0.9)
        tx, ty = px, py
    end


    local doing, doingWhy = "goes to the spot", ok and "free" or ("held last spot: " .. tostring(why))
    if redGoes then
        local rx0, ry0 = bx - red:getX(), by - red:getY()
        local lon = rx0 * hx + ry0 * hy
        local lat = rx0 * (-hy) + ry0 * hx
        if lon > -0.3 and lon < 2.0 and math.abs(lat) < 0.9 then
            want = math.max(want, BridgeMove.redSpeed * 1.3, 0.035)
            doing, doingWhy = "gets out of his way", sformat("ahead %.2f side %.2f", lon, lat)
        end
    end

    local ox, oy = detour(red:getX(), red:getY(), hx, hy, bx, by, tx, ty, redGoes)
    if ox ~= tx or oy ~= ty then
        if BridgeMove.lineClear(body, ox, oy, red:getZ()) then
            tx, ty = ox, oy
            want = math.max(want, BridgeMove.redSpeed * 1.3, 0.03)
            doing, doingWhy = "detour around him", "spot on his other side"
        end
    end
    keepLog(F, keep, doing, doingWhy, toSpot, d, redGoes)

    if F.aimFrame == Bridge.tick - 1 and F.aimX ~= nil and dist2d(F.aimX, F.aimY, tx, ty) < 1.5 then
        tx = F.aimX * 0.7 + tx * 0.3
        ty = F.aimY * 0.7 + ty * 0.3
    end
    F.aimX, F.aimY, F.aimFrame = tx, ty, Bridge.tick
    return drive(body, red, F, pf, bx, by, tx, ty, want, "spot-" .. keep, running, d, toSpot)
end
















local SEAT_STAY = 4





BridgeMove.SIT_WITH_RED = false
local SEAT_RING_MAX = 4
local SEAT_ARRIVE = 0.3
local SEAT_NEAR = 0.7
local SEAT_GAP = 0.25
local SEAT_EDGE = 0.15

BridgeMove.SEAT_PIVOT_DEG = 15
local SEAT_GIVE_UP = 360
local SEAT_DOWN_MAX = 180
local SEAT_NEAR_GOAL = 2.5
BridgeMove.seat = nil

local function cellOf(x, y) return math.floor(x), math.floor(y) end


local function pointAt(x, y, z)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return z end }
end










function BridgeMove.seatZones(red)
    if red == nil then return nil end
    local sitting, furniture, tx, ty, why = false, nil, nil, nil, nil
    pcall(function() sitting = red:isSittingOnFurniture() == true end)
    pcall(function() furniture = red:getSitOnFurnitureObject() end)
    if furniture == nil or sitting then BridgeMove.sitDownSince = nil end
    if sitting then
        why = "sits"
    elseif furniture ~= nil then



        BridgeMove.sitDownSince = BridgeMove.sitDownSince or Bridge.time
        if Bridge.time - BridgeMove.sitDownSince > SEAT_DOWN_MAX then return nil end
        why = "sitting down"
    else
        pcall(function()
            local q = ISTimedActionQueue.queues[red]
            local first = q and q.queue and q.queue[1]
            if first == nil then return end
            if first.Type == "ISPathFindAction" and type(first.goal) == "table" and first.goal[1] == "SitOnFurniture" then

                local pf = red:getPathFindBehavior2()
                if not pf:isGoalSitOnFurniture() then return end
                local gx, gy = pf:getTargetX(), pf:getTargetY()
                if gx == nil or gx <= 0 or dist2d(red:getX(), red:getY(), gx, gy) > SEAT_NEAR_GOAL then return end

                pcall(function() furniture = pf:getGoalSitOnFurnitureObject() end)
                if furniture == nil then furniture = first.goal[2] end
                tx, ty, why = gx, gy, "going to sit"
            else

                for _, a in ipairs(q.queue) do
                    if a.Type == "ISRestAction" and a.bed ~= nil then
                        furniture, why = a.bed, "about to sit"
                        break
                    end
                end
            end
        end)
        if why == nil then return nil end
    end
    local rx, ry = cellOf(red:getX(), red:getY())


    local zones = { { x = rx, y = ry }, z = math.floor(red:getZ() + 0.5), why = why, cx = rx, cy = ry }
    if tx ~= nil and tx > 0 and ty ~= nil and ty > 0 then
        local gx, gy = cellOf(tx, ty)
        zones[#zones + 1] = { x = gx, y = gy }
        zones.cx, zones.cy = gx, gy
    end
    if furniture ~= nil then
        local sq = nil
        pcall(function() sq = furniture:getSquare() end)
        if sq ~= nil then zones[#zones + 1] = { x = sq:getX(), y = sq:getY() } end
    end
    return zones
end

function BridgeMove.inSeatZone(zones, cx, cy)
    for _, c in ipairs(zones) do
        if math.abs(cx - c.x) <= 1 and math.abs(cy - c.y) <= 1 then return true end
    end
    return false
end



function BridgeMove.zoneGap(zones, x, y)
    local best = nil
    for _, c in ipairs(zones) do
        local dx = math.max(c.x - 1 - x, 0, x - (c.x + 2))
        local dy = math.max(c.y - 1 - y, 0, y - (c.y + 2))
        local g = math.sqrt(dx * dx + dy * dy)
        if best == nil or g < best then best = g end
    end
    return best or 99
end


function BridgeMove.seatBlocks(x, y, z)
    local zones = BridgeMove.seatZones(BridgeData.owner())
    if zones == nil or math.floor(z or 0) ~= zones.z then return false end
    local cx, cy = cellOf(x, y)
    return BridgeMove.inSeatZone(zones, cx, cy)
end


local function seatCellOk(x, y, z)
    local ok = false
    pcall(function()
        local sq = getCell():getGridSquare(x, y, z)
        if sq == nil or not sq:isFree(false) then return end
        ok = true
        pcall(function() if sq:isVehicleIntersecting() or sq:isWaterSquare() then ok = false end end)
    end)
    return ok
end



local ZONE_MARGIN = 0.25
local function zoneFree(zones, ax, ay, bx, by)
    local len = dist2d(ax, ay, bx, by)
    local steps = math.max(1, math.ceil(len / 0.1))
    local nx, ny = 0, 0
    if len > 1e-6 then nx, ny = -(by - ay) / len * ZONE_MARGIN, (bx - ax) / len * ZONE_MARGIN end
    for i = 0, steps do
        local t = i / steps
        local px, py = ax + (bx - ax) * t, ay + (by - ay) * t


        local ends = t * len < 0.8 or (1 - t) * len < 0.8
        for _, k in ipairs(ends and { 0 } or { 0, 1, -1 }) do
            local cx, cy = cellOf(px + nx * k, py + ny * k)
            if BridgeMove.inSeatZone(zones, cx, cy) then return false end
        end
    end
    return true
end
BridgeMove.zoneFree = zoneFree




local function zoneDetour(zones, body, bx, by, gx, gy)
    local best, bestLen = nil, nil
    for r = 2, 4 do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local x, y = zones.cx + dx, zones.cy + dy
                    if not BridgeMove.inSeatZone(zones, x, y) and seatCellOk(x, y, zones.z) then
                        local px, py = x + 0.5, y + 0.5
                        if zoneFree(zones, bx, by, px, py) and zoneFree(zones, px, py, gx, gy)
                            and BridgeMove.lineClear(body, px, py, zones.z)
                            and BridgeMove.lineClear(pointAt(px, py, zones.z), gx, gy, zones.z) then
                            local len = dist2d(bx, by, px, py) + dist2d(px, py, gx, gy)
                            if bestLen == nil or len < bestLen then best, bestLen = { x = px, y = py }, len end
                        end
                    end
                end
            end
        end
    end
    return best
end


local function seatFrom(red, zones)
    if zones.why == "going to sit" then return pointAt(zones.cx + 0.5, zones.cy + 0.5, zones.z) end
    return red
end


local function segDist(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay
    local l2 = vx * vx + vy * vy
    local t = 0
    if l2 > 1e-9 then t = clamp(((px - ax) * vx + (py - ay) * vy) / l2, 0, 1) end
    return dist2d(px, py, ax + vx * t, ay + vy * t)
end







function BridgeMove.seatSpot(red, zones, bx, by, body, bad)
    local from = seatFrom(red, zones)
    local rx, ry = red:getX(), red:getY()
    local best, bestCost, checked = nil, nil, 0
    for r = 2, SEAT_RING_MAX do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local x, y = zones.cx + dx, zones.cy + dy
                    if not BridgeMove.inSeatZone(zones, x, y) and not (bad and bad[x .. "," .. y]) then
                        checked = checked + 1
                        local px, py = x + 0.5, y + 0.5
                        local redSees = BridgeMove.lineClear(from, px, py, zones.z)
                        local sheSees = body == nil or BridgeMove.lineClear(body, px, py, zones.z)



                        if seatCellOk(x, y, zones.z) and (redSees or sheSees) then
                            local cost = dist2d(bx, by, px, py) + (r - 2) * 2.5
                            if not redSees then cost = cost + 4 end
                            if not sheSees then cost = cost + 3 end
                            if segDist(rx, ry, bx, by, px, py) < 1.0 then cost = cost + 5 end
                            if not zoneFree(zones, bx, by, px, py) then cost = cost + 6 end
                            if bestCost == nil or cost < bestCost then
                                best, bestCost = { x = x, y = y, ring = r }, cost
                            end
                        end
                    end
                end
            end
        end
    end
    return best, checked
end



local function freshDrive(F)
    if F.frame ~= Bridge.tick - 1 then F.netFrame, F.stuck = nil, 0 end
end





local AWAY_STEP = 0.6
local function awayPoint(body, red, z, tx, ty)
    local bx, by = body:getX(), body:getY()
    local dx, dy = bx - red:getX(), by - red:getY()
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 0.05 then dx, dy, l = 1, 0, 1 end
    dx, dy = dx / l, dy / l
    local gx, gy = (tx or bx + dx) - bx, (ty or by + dy) - by
    local gl = math.sqrt(gx * gx + gy * gy)
    if gl < 1e-6 then gx, gy, gl = dx, dy, 1 end
    gx, gy = gx / gl, gy / gl
    local bestX, bestY, bestDot = nil, nil, nil
    for _, a in ipairs({ 0, 45, -45, 90, -90 }) do
        local r = math.rad(a)
        local ux, uy = dx * math.cos(r) - dy * math.sin(r), dx * math.sin(r) + dy * math.cos(r)
        local px, py = bx + ux * AWAY_STEP, by + uy * AWAY_STEP
        local dot = ux * gx + uy * gy
        if (bestDot == nil or dot > bestDot + 1e-6) and BridgeMove.lineClear(body, px, py, z) then
            bestX, bestY, bestDot = px, py, dot
        end
    end
    return bestX, bestY
end



local function routeAround(S, body, red, z, tx, ty, d)
    local bx, by = body:getX(), body:getY()
    if S.away ~= nil then
        if dist2d(bx, by, S.away.x, S.away.y) <= 0.2 then
            S.away, S.awayDone = nil, true
        else
            return S.away.x, S.away.y, true
        end
    end





    if not S.awayDone and (d < 0.45 or segDist(red:getX(), red:getY(), bx, by, tx, ty) < math.min(d, 0.7) - 0.05) then
        local ax, ay = awayPoint(body, red, z, tx, ty)
        if ax ~= nil then
            S.away = { x = ax, y = ay }
            log(sformat("seat: right at him (d=%.2f), first a step away to %.2f,%.2f, then %.2f,%.2f", d, ax, ay, tx, ty))
            return ax, ay, true
        end
    end
    return tx, ty, false
end


local function seatStand(body, red, d)
    if BridgeMove.onPath() then BridgeMove.stopPath(body) end
    BridgeMove.moving = false
    local F = BridgeMove.follow
    F.kind, F.s, F.want = "seat-stand", 0, 0
    if Bridge.zombieTicks % 30 == 0 then
        pcall(function() body:faceLocationF(red:getX(), red:getY()) end)
    end
    BridgeMove.goal = { x = red:getX(), y = red:getY() }
    BridgeMove.pathResult = "follow-seat-stand"
    trackStep(body)
    BridgeMove.traceFrame(body, d, false, false)
    return true
end


function BridgeMove.seatText()
    local S = BridgeMove.seat
    if S == nil then return "none" end
    local text = tostring(S.why)
    if S.phase ~= nil then text = text .. " phase=" .. S.phase end
    if S.chair ~= nil then text = text .. sformat(" chair=%d,%d", S.chair.x, S.chair.y) end
    if S.spot ~= nil then text = text .. sformat(" spot=%d,%d%s", S.spot.x, S.spot.y, S.path and " path" or "") end
    if S.noSpot then text = text .. " no-spot" end
    return text
end













local CHAIR_RING_MAX = 3
local CHAIR_ARRIVE = 0.2
local CHAIR_ANIM_MAX = 240
local SIT_DIRS = { "N", "S", "W", "E" }
BridgeMove.CHAIR_POSES = { SitChairDown = true, SitChair = true, SitChairUp = true }
BridgeMove.seatFlag = false






function BridgeMove.findChair(red, zones, body, bad)
    local sm, v = nil, nil
    pcall(function() sm = SeatingManager.getInstance() end)
    pcall(function() v = Vector3f.new() end)
    if sm == nil or v == nil then return nil, 0 end
    local rcx, rcy = zones[1].x, zones[1].y
    local bx, by = body:getX(), body:getY()
    local cell = getCell()
    local best, bestCost, seats = nil, nil, 0
    for dx = -CHAIR_RING_MAX, CHAIR_RING_MAX do
        for dy = -CHAIR_RING_MAX, CHAIR_RING_MAX do
            local ring = math.max(math.abs(dx), math.abs(dy))
            local x, y = rcx + dx, rcy + dy
            if ring >= 2 and not BridgeMove.inSeatZone(zones, x, y) and not (bad and bad[x .. "," .. y]) then



                local sq = cell:getGridSquare(x, y, zones.z)
                local objects = sq ~= nil and sq:getObjects() or nil
                local n = objects ~= nil and objects:size() or 0
                for i = 0, n - 1 do
                    local o = objects:get(i)



                    local sprite, sittable = nil, false
                    pcall(function()
                        sprite = o:getSprite()
                        local props = sprite ~= nil and sprite:getProperties() or nil
                        sittable = props ~= nil and props:has(IsoFlagType.bed) == true
                    end)
                    local places, taken = 0, false
                    if sittable then
                        pcall(function() places = sm:getTilePositionCount(o) end)
                        pcall(function() taken = o:isFurnitureOccupied(body) == true end)
                    end
                    if sittable and places > 0 and not taken then
                        seats = seats + 1
                        for _, dir in ipairs(SIT_DIRS) do





                            local ok = false
                            pcall(function() ok = sm:getAdjacentPosition(red, o, dir, "Front", "sitonfurniture", "SitOnFurnitureFront", v) == true end)
                            if ok then
                                local ax, ay = v:x(), v:y()
                                local acx, acy = cellOf(ax, ay)
                                if not BridgeMove.inSeatZone(zones, acx, acy) and seatCellOk(acx, acy, zones.z)
                                    and BridgeMove.lineClear(red, ax, ay, zones.z) then
                                    local cost = dist2d(bx, by, ax, ay) + (ring - 2)
                                    if not BridgeMove.lineClear(body, ax, ay, zones.z) then cost = cost + 3 end
                                    if not zoneFree(zones, bx, by, ax, ay) then cost = cost + 6 end
                                    if bestCost == nil or cost < bestCost then
                                        local name = "?"
                                        pcall(function() name = tostring(sprite:getName()) end)
                                        best, bestCost = { obj = o, x = x, y = y, ax = ax, ay = ay, dir = dir, ring = ring, name = name }, cost
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best, seats
end



function BridgeMove.sendSit(value)
    local st = Bridge.store
    if st == nil or st.sit == value then return end
    st.sit = value
    if Bridge.mp then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { sit = value or false }) end)
    end
end


local function chairFlags(body)
    pcall(function() body:setCollidable(false) end)
    if not BridgeMove.seatFlag then
        pcall(function() body:setSittingOnFurniture(true) end)
        BridgeMove.seatFlag = true
    end
end

local function chairFlagsOff(body)
    if not BridgeMove.seatFlag then return end
    BridgeMove.seatFlag = false
    pcall(function() body:setSittingOnFurniture(false) end)
    pcall(function() body:setCollidable(true) end)
end




local function animDone(body, S)
    local bump, fin = "", false
    pcall(function() bump = tostring(body:getBumpType()) end)
    pcall(function() fin = body:getVariableBoolean("BumpAnimFinished") end)
    if bump == S.anim then S.animSeen = true end
    if S.animSeen and (fin or bump ~= S.anim) then return true end
    return Bridge.time - S.phaseSince > CHAIR_ANIM_MAX
end

local function startPose(body, S, anim, move)
    pcall(function() body:setVariable("BumpAnimFinished", false) end)
    Bridge.pose = { anim = anim, move = move, seat = true }
    S.anim, S.animSeen = anim, false
end






local function chairLeave(body, S, why)
    local c = S and S.chair
    if c ~= nil then
        pcall(function()
            body:setX(c.ax)
            body:setY(c.ay)
            body:setLastX(c.ax)
            body:setLastY(c.ay)
        end)
        local sq = getCell():getGridSquare(math.floor(c.ax), math.floor(c.ay), math.floor(body:getZ()))
        if sq ~= nil then pcall(function() body:setCurrent(sq) end) end
    end
    pcall(function()
        if BridgeMove.CHAIR_POSES[tostring(body:getBumpType())] then BridgeMove.releaseBump(body) end
    end)
    Bridge.holdPos = nil
    chairFlagsOff(body)
    log(sformat("seat: off %s without stand-up (%s)%s", c and (c.x .. "," .. c.y) or "the seat", why,
        c and sformat(", put at %.2f,%.2f", c.ax, c.ay) or ""))
end



function BridgeMove.seatPose(body)
    local S = BridgeMove.seat
    if S == nil or S.phase == nil or S.phase == "go" then return false end
    local red = BridgeData.owner()
    local zones = BridgeMove.seatZones(red)
    local up = zones == nil or zones.why ~= "sits"
    if S.phase == "down" then
        chairFlags(body)
        if animDone(body, S) then
            S.phase, S.phaseSince = "sit", Bridge.time
            startPose(body, S, "SitChair", false)
            BridgeMove.sendSit("chair")
            log(sformat("seat: on %d,%d after %d ticks, at %.2f,%.2f, %d cells from player", S.chair.x, S.chair.y,
                Bridge.time - S.since, body:getX(), body:getY(),
                math.max(math.abs(math.floor(body:getX()) - math.floor(red:getX())), math.abs(math.floor(body:getY()) - math.floor(red:getY())))))
        end
    elseif S.phase == "sit" then
        chairFlags(body)
        if up then
            S.phase, S.phaseSince = "up", Bridge.time
            startPose(body, S, "SitChairUp", true)
            BridgeMove.sendSit(nil)
            log(sformat("seat: player is up, standing up from %d,%d", S.chair.x, S.chair.y))
        end
    elseif S.phase == "up" then
        chairFlags(body)
        if animDone(body, S) then
            Bridge.pose = nil
            chairFlagsOff(body)
            BridgeMove.sendSit(nil)
            log(sformat("seat: up after %d ticks at %.2f,%.2f, following again", Bridge.time - S.phaseSince, body:getX(), body:getY()))
            BridgeMove.seat = nil
        end
    elseif S.phase == "floor" then
        if up then
            Bridge.pose = nil
            BridgeMove.sendSit(nil)
            log(sformat("seat: player is up, up from the floor after %d ticks, following again", Bridge.time - S.phaseSince))
            BridgeMove.seat = nil
        end
    end
    return true
end



function BridgeMove.seatGuard(body)
    local pose = Bridge.pose
    local chairPose = pose ~= nil and BridgeMove.CHAIR_POSES[pose.anim] == true
    local S = BridgeMove.seat
    local phase = S and S.phase
    local onChair = phase == "down" or phase == "sit" or phase == "up"
    if onChair or phase == "floor" then
        local ours = (phase == "floor" and pose ~= nil and pose.anim == "Sit") or chairPose
        if not ours or not Bridge.follow then
            local why = sformat("pose %s, mode %s", pose and tostring(pose.anim) or "none", tostring(Bridge.mode))
            if onChair then chairLeave(body, S, why)
            else log("seat: up from the floor (" .. why .. ")") end
            BridgeMove.sendSit(nil)
            BridgeMove.seat = nil
        end
    elseif pose ~= nil and pose.seat then

        if chairPose then chairLeave(body, nil, "pose without sitting") end
        Bridge.pose = nil
        BridgeMove.sendSit(nil)
    end
    if BridgeMove.seatFlag and not chairPose then chairFlagsOff(body) end
end



function BridgeMove.sitDownNear(body, red, zones, S, d, inside)
    local bx, by = body:getX(), body:getY()
    local sameZ = math.abs(body:getZ() - zones.z) < 0.5
    S.bad = S.bad or {}
    if S.phase == nil and Bridge.time < (S.retryAt or 0) then return seatStand(body, red, d) end
    if S.phase == nil then
        local chair, seats = BridgeMove.findChair(red, zones, body, S.bad)
        if chair ~= nil then
            S.phase, S.goal, S.chair, S.phaseSince, S.path, S.via, S.gate = "go", { x = chair.ax, y = chair.ay }, chair, Bridge.time, false, nil, nil
            S.away, S.awayDone = nil, false
            log(sformat("seat: player sits, going to sit on %s at %d,%d facing %s (ring %d, %d seats checked), from %.2f,%.2f to %.2f,%.2f",
                tostring(chair.name), chair.x, chair.y, chair.dir, chair.ring, seats, bx, by, chair.ax, chair.ay))
        else
            local spot, checked = BridgeMove.seatSpot(red, zones, bx, by, body, S.bad)
            if spot == nil then
                if not S.noSpot then
                    S.noSpot = true
                    log(sformat("seat: player sits, no seat 2-%d cells (%d seats), no floor spot (%d cells), staying%s",
                        CHAIR_RING_MAX, seats, checked, inside and " in the way" or ""))
                end
                S.retryAt = Bridge.time + 60
                return seatStand(body, red, d)
            end
            S.noSpot = false
            S.phase, S.goal, S.chair, S.phaseSince, S.path, S.via, S.gate = "go", { x = spot.x + 0.5, y = spot.y + 0.5, floor = true }, nil, Bridge.time, false, nil, nil
            S.away, S.awayDone = nil, false
            log(sformat("seat: player sits, no seat 2-%d cells (%d seats checked), floor at %d,%d (ring %d)",
                CHAIR_RING_MAX, seats, spot.x, spot.y, spot.ring))
        end
    end
    local gx, gy = S.goal.x, S.goal.y
    local toGoal = dist2d(bx, by, gx, gy)

    local arrive = S.goal.floor and SEAT_ARRIVE or (S.path and 0.6 or CHAIR_ARRIVE)
    if sameZ and toGoal <= arrive then
        if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        BridgeMove.moving = false
        Bridge.holdPos = nil
        if S.goal.floor then
            pcall(function() body:faceLocationF(red:getX(), red:getY()) end)
            S.phase, S.phaseSince = "floor", Bridge.time
            startPose(body, S, "Sit", false)
            BridgeMove.sendSit("floor")
            log(sformat("seat: sitting on the floor at %.2f,%.2f after %d ticks", bx, by, Bridge.time - S.since))
        else

            pcall(function()
                body:setX(gx)
                body:setY(gy)
                body:setLastX(gx)
                body:setLastY(gy)
            end)
            local sq = getCell():getGridSquare(math.floor(gx), math.floor(gy), zones.z)
            if sq ~= nil then pcall(function() body:setCurrent(sq) end) end
            pcall(function() body:faceDirection(IsoDirections.fromString(S.chair.dir)) end)
            S.phase, S.phaseSince = "down", Bridge.time
            chairFlags(body)
            startPose(body, S, "SitChairDown", true)
            log(sformat("seat: sitting down on %d,%d facing %s from %.2f,%.2f (snapped %.2f)",
                S.chair.x, S.chair.y, S.chair.dir, gx, gy, toGoal))
        end
        return true
    end
    local key = S.chair and (S.chair.x .. "," .. S.chair.y) or (math.floor(gx) .. "," .. math.floor(gy))

    if S.giveUpAt == nil or S.goalSince ~= S.phaseSince then
        S.goalSince = S.phaseSince
        S.giveUpAt = S.phaseSince + SEAT_GIVE_UP + math.floor(60 * dist2d(bx, by, gx, gy))
    end
    if Bridge.time > S.giveUpAt then
        S.bad[key] = true
        log(sformat("seat: %s not reached in %d ticks, choosing again", key, Bridge.time - S.phaseSince))
        S.phase, S.goal, S.chair = nil, nil, nil
        return seatStand(body, red, d)
    end

    local ax, ay, stepping = routeAround(S, body, red, zones.z, gx, gy, d)
    if stepping then
        local F = BridgeMove.follow
        local pf = body:getPathFindBehavior2()
        if BridgeMove.pathing then
            pcall(function() pf:cancel() pf:reset() body:setPath2(nil) end)
            BridgeMove.pathing = false
            BridgeMove.goal = nil
        end
        Bridge.holdPos = nil
        BridgeMove.moving = true
        BridgeMove.steering = true
        freshDrive(F)
        if drive(body, red, F, pf, bx, by, ax, ay, 0.04, "seat", false, d, toGoal) then return true end
        S.away, S.awayDone = nil, true
    end


    if S.via ~= nil and dist2d(bx, by, S.via.x, S.via.y) <= 0.4 then S.via = nil end
    if S.via == nil and sameZ and not zoneFree(zones, bx, by, gx, gy) then
        if inside then
            local out = BridgeMove.seatSpot(red, zones, bx, by, body, nil)
            if out ~= nil then S.via = { x = out.x + 0.5, y = out.y + 0.5 } end
        else
            S.via = zoneDetour(zones, body, bx, by, gx, gy)
        end
        if S.via == nil then
            S.bad[key] = true
            log(sformat("seat: way to %.2f,%.2f crosses his cells and no way round, choosing again", gx, gy))
            S.phase, S.goal, S.chair = nil, nil, nil
            return seatStand(body, red, d)
        end
        log(sformat("seat: way to %.2f,%.2f crosses his cells, via %.1f,%.1f", gx, gy, S.via.x, S.via.y))
    end
    local tx, ty = gx, gy
    if S.via ~= nil then tx, ty = S.via.x, S.via.y end



    local seesTarget = BridgeMove.lineClear(body, tx, ty, zones.z)
    if S.gate ~= nil and (seesTarget or dist2d(bx, by, S.gate.x, S.gate.y) <= 0.15) then S.gate = nil end
    if S.gate == nil and not seesTarget then
        local t = BridgeMove.trail
        local seen, any = nil, nil
        for i = #t, 1, -1 do
            local p = t[i]
            local pcx, pcy = cellOf(p.x, p.y)
            if math.floor(p.z) == zones.z and not BridgeMove.inSeatZone(zones, pcx, pcy) and dist2d(bx, by, p.x, p.y) > 0.3
                and zoneFree(zones, p.x, p.y, tx, ty) and BridgeMove.lineClear(pointAt(p.x, p.y, zones.z), tx, ty, zones.z) then
                any = any or p
                if BridgeMove.lineClear(body, p.x, p.y, zones.z) and zoneFree(zones, bx, by, p.x, p.y) then seen = p break end
            end
        end
        local p = seen or any
        if p ~= nil then
            S.gate = { x = p.x, y = p.y }
            if S.gateLogged == nil or dist2d(S.gateLogged.x, S.gateLogged.y, p.x, p.y) > 0.5 then
                S.gateLogged = S.gate
                log(sformat("seat: %.2f,%.2f not in sight, first to his trail at %.2f,%.2f%s", tx, ty, p.x, p.y,
                    seen and "" or " (not in sight either, engine path)"))
            end
        end
    end
    if S.gate ~= nil then tx, ty = S.gate.x, S.gate.y end
    local toNext = dist2d(bx, by, tx, ty)

    local F = BridgeMove.follow
    local pf = body:getPathFindBehavior2()
    Bridge.holdPos = nil
    BridgeMove.moving = true
    if not S.path and sameZ and BridgeMove.lineClear(body, tx, ty, zones.z) then
        if BridgeMove.pathing then
            pcall(function() pf:cancel() pf:reset() body:setPath2(nil) end)
            BridgeMove.pathing = false
            BridgeMove.goal = nil
        end
        BridgeMove.steering = true
        local want = 0.036 * clamp(0.4 + 0.6 * toNext, 0.3, 0.9)
        if inside or S.via ~= nil then want = math.max(want, 0.05) end
        freshDrive(F)
        if drive(body, red, F, pf, bx, by, tx, ty, want, "seat", false, d, toGoal) then return true end


        S.stuck = (S.stuck or 0) + 1
        if S.gate == nil and not inside and S.stuck < 3 then
            S.bad[key] = true
            log(sformat("seat: stuck on the way to %.2f,%.2f, choosing again", tx, ty))
            S.phase, S.goal, S.chair, S.via = nil, nil, nil, nil
            return seatStand(body, red, d)
        end
        S.path = true
        log(sformat("seat: stuck on the way to his trail %.2f,%.2f, engine path", tx, ty))
    end
    if BridgeMove.steering then
        BridgeMove.endFollowBump(body, "")
        BridgeMove.steering = false
    end
    BridgeMove.setCollide(body, true)
    BridgeMove.walkType = "Walk"
    BridgeMove.applyAnimVars(body)
    BridgeMove.goToward(body, tx, ty, zones.z, true)
    if BridgeMove.lastFailed == Bridge.tick then
        S.bad[key] = true
        log(sformat("seat: path to %.2f,%.2f failed (%s) from %.2f,%.2f, d=%.2f, choosing again", tx, ty,
            tostring(BridgeMove.pathResult), bx, by, d))
        S.phase, S.goal, S.chair = nil, nil, nil
    end
    return true
end



function BridgeMove.seatStep(body)
    local red = BridgeData.owner()
    local zones = BridgeMove.seatZones(red)
    local S = BridgeMove.seat


    if Bridge.store ~= nil and Bridge.store.sit ~= nil then BridgeMove.sendSit(nil) end
    if zones == nil then
        if S ~= nil then
            log(sformat("seat: player is up, following again after %d ticks", Bridge.time - S.since))
            BridgeMove.seat = nil
        end
        return false
    end
    local bx, by = body:getX(), body:getY()
    local d = dist2d(bx, by, red:getX(), red:getY())



    local sameZ = math.abs(body:getZ() - zones.z) < 0.5
    local bcx, bcy = cellOf(bx, by)
    local inside = sameZ and BridgeMove.inSeatZone(zones, bcx, bcy)
    local rcx, rcy = cellOf(red:getX(), red:getY())

    local cells = math.max(math.abs(bcx - zones.cx), math.abs(bcy - zones.cy))
    if S == nil or S.why ~= zones.why then
        local where = {}
        for i, c in ipairs(zones) do where[i] = c.x .. "," .. c.y end
        log(sformat("seat: player %s, keep out of 3x3 around %s; me %d cells away (d=%.2f)%s",
            zones.why, table.concat(where, " "), cells, d, inside and ", in the way" or ""))
        if S == nil then
            S = { since = Bridge.time, bad = {} }
            BridgeMove.seat = S
        end
        S.why = zones.why
    end

    if zones.why == "sits" and BridgeMove.SIT_WITH_RED then return BridgeMove.sitDownNear(body, red, zones, S, d, inside) end
    if S.phase ~= nil then S.phase, S.goal, S.chair = nil, nil, nil end



    if not inside and (not sameZ or cells > SEAT_STAY) then
        if Bridge.time >= (S.freedLog or 0) then
            S.freedLog = Bridge.time + 60
            log(sformat("seat: following, %s (her z=%.2f, floor %d, %d cells)%s", sameZ and "far" or "other floor",
                body:getZ(), zones.z, cells, S.spot ~= nil and sformat(", spot %d,%d dropped", S.spot.x, S.spot.y) or ""))
        end
        if S.spot ~= nil then S.spot, S.path = nil, false end
        return false
    end





    if S.spot == nil and not inside then
        if S.placed then return seatStand(body, red, d) end
        S.placed = true
        if BridgeMove.lineClear(seatFrom(red, zones), bx, by, zones.z) then
            local gap = BridgeMove.zoneGap(zones, bx, by)
            if gap >= SEAT_EDGE then return seatStand(body, red, d) end

            S.spot, S.path, S.spotSince, S.away, S.awayDone = { x = bcx, y = bcy, ring = cells }, false, Bridge.time, nil, true
            S.spotGiveUp = Bridge.time + 120
            log(sformat("seat: at the edge of his zone (gap %.2f), stepping into %d,%d", gap, bcx, bcy))
        else
            local spot, checked = BridgeMove.seatSpot(red, zones, bx, by, body, S.bad)
            if spot == nil or (spot.x == bcx and spot.y == bcy) then
                log(sformat("seat: out of his sight at %d,%d, %s, staying", bcx, bcy,
                    spot == nil and ("no spot (" .. checked .. " cells checked)") or "no better spot"))
                return seatStand(body, red, d)
            end
            S.spot, S.path, S.spotSince, S.away, S.awayDone = spot, false, Bridge.time, nil, false
            spot.forSight = true
            S.spotGiveUp = Bridge.time + SEAT_GIVE_UP + math.floor(60 * dist2d(bx, by, spot.x + 0.5, spot.y + 0.5))
            log(sformat("seat: out of his sight, %d cells, going once to %d,%d (ring %d, %d cells checked, d=%.2f)",
                cells, spot.x, spot.y, spot.ring, checked, d))
        end
    end

    if S.spot ~= nil and (BridgeMove.inSeatZone(zones, S.spot.x, S.spot.y) or not seatCellOk(S.spot.x, S.spot.y, zones.z)) then
        log(sformat("seat: spot %d,%d no longer fits (player %s)", S.spot.x, S.spot.y, zones.why))
        S.spot, S.path = nil, false
    end
    if S.spot == nil and Bridge.time < (S.retryAt or 0) then return seatStand(body, red, d) end
    if S.spot == nil then
        local spot, checked = BridgeMove.seatSpot(red, zones, bx, by, body, S.bad)
        if spot == nil then
            S.retryAt = Bridge.time + 60
            if not S.noSpot then
                S.noSpot = true
                log(sformat("seat: no free spot 2-%d cells from player (%d cells checked), staying%s",
                    SEAT_RING_MAX, checked, inside and " in the way" or ""))
            end
            return seatStand(body, red, d)
        end
        S.noSpot = false
        S.placed = true
        S.spot, S.path, S.spotSince, S.away, S.awayDone = spot, false, Bridge.time, nil, false
        S.spotGiveUp = Bridge.time + SEAT_GIVE_UP + math.floor(60 * dist2d(bx, by, spot.x + 0.5, spot.y + 0.5))
        log(sformat("seat: in the way, going to %d,%d (ring %d, %d cells checked, d=%.2f, turn %s deg)",
            spot.x, spot.y, spot.ring, checked, d, tostring(BridgeMove.facingOff(body, spot.x + 0.5, spot.y + 0.5))))
    end
    local px, py = S.spot.x + 0.5, S.spot.y + 0.5
    local toSpot = dist2d(bx, by, px, py)



    local nearOk = not inside and toSpot <= SEAT_NEAR and BridgeMove.zoneGap(zones, bx, by) >= SEAT_GAP
    if nearOk and S.spot.forSight and not BridgeMove.lineClear(seatFrom(red, zones), bx, by, zones.z) then nearOk = false end
    if sameZ and (toSpot <= SEAT_ARRIVE or nearOk) then
        log(sformat("seat: at %d,%d after %d ticks, %d cells from player", S.spot.x, S.spot.y,
            Bridge.time - S.spotSince, math.max(math.abs(S.spot.x - rcx), math.abs(S.spot.y - rcy))))
        S.spot, S.path = nil, false
        return seatStand(body, red, d)
    end
    if Bridge.time > (S.spotGiveUp or (S.spotSince + SEAT_GIVE_UP)) then
        S.bad[S.spot.x .. "," .. S.spot.y] = true
        log(sformat("seat: %d,%d not reached in %d ticks, another spot", S.spot.x, S.spot.y, Bridge.time - S.spotSince))
        S.spot, S.path = nil, false
        return seatStand(body, red, d)
    end
    local F = BridgeMove.follow
    local pf = body:getPathFindBehavior2()
    Bridge.holdPos = nil
    BridgeMove.moving = true
    local wx, wy, stepping = routeAround(S, body, red, zones.z, px, py, d)
    if stepping or (not S.path and sameZ and BridgeMove.lineClear(body, px, py, zones.z)) then

        if BridgeMove.pathing then
            pcall(function() pf:cancel() pf:reset() body:setPath2(nil) end)
            BridgeMove.pathing = false
            BridgeMove.goal = nil
        end
        BridgeMove.steering = true
        local toNext = dist2d(bx, by, wx, wy)
        local want = 0.036 * clamp(0.4 + 0.6 * toNext, 0.35, 0.9)


        local off = BridgeMove.facingOff(body, wx, wy)
        if inside and (off == nil or off < 90) then want = math.max(want, 0.05) end
        freshDrive(F)
        if drive(body, red, F, pf, bx, by, wx, wy, want, "seat", false, d, toSpot) then return true end
        if stepping then S.away, S.awayDone = nil, true end
        S.path = true
        log(sformat("seat: stuck on the way to %.2f,%.2f, engine path", wx, wy))
    end

    if BridgeMove.steering then
        BridgeMove.endFollowBump(body, "")
        BridgeMove.steering = false
    end
    BridgeMove.setCollide(body, true)
    BridgeMove.walkType = "Walk"
    BridgeMove.applyAnimVars(body)
    BridgeMove.goToward(body, px, py, zones.z, true)
    if BridgeMove.lastFailed == Bridge.tick then
        log(sformat("seat: path to %d,%d failed (%s) from %.2f,%.2f, d=%.2f", S.spot.x, S.spot.y,
            tostring(BridgeMove.pathResult), bx, by, d))
        S.bad[S.spot.x .. "," .. S.spot.y] = true
        log(sformat("seat: no path to %d,%d, another spot", S.spot.x, S.spot.y))
        S.spot, S.path = nil, false
    end
    return true
end




function BridgeMove.asideStep(body)
    local t = Bridge.target
    local red = BridgeData.owner()
    if t == nil or t.cellX == nil or red == nil then return false end
    local bx, by = body:getX(), body:getY()
    local toSpot = dist2d(bx, by, t.x, t.y)
    local d = dist2d(bx, by, red:getX(), red:getY())
    if math.abs(body:getZ() - math.floor(t.z or 0)) >= 0.5 then return false end
    local zones = BridgeMove.seatZones(red)
    local clear = zones ~= nil and toSpot <= SEAT_NEAR and BridgeMove.zoneGap(zones, bx, by) >= SEAT_GAP
    if toSpot <= SEAT_ARRIVE or clear then
        if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        BridgeMove.moving = false
        Bridge.target = nil
        log(sformat("seat: waiting at %d,%d now, %d cells from player", t.cellX, t.cellY,
            math.max(math.abs(t.cellX - math.floor(red:getX())), math.abs(t.cellY - math.floor(red:getY())))))
        return true
    end
    if t.path or not BridgeMove.lineClear(body, t.x, t.y, t.z or 0) then return false end
    local pf = body:getPathFindBehavior2()
    if BridgeMove.pathing then
        pcall(function() pf:cancel() pf:reset() body:setPath2(nil) end)
        BridgeMove.pathing = false
        BridgeMove.goal = nil
    end
    Bridge.holdPos = nil
    BridgeMove.moving = true
    BridgeMove.steering = true
    local want = 0.036 * clamp(0.4 + 0.6 * toSpot, 0.35, 0.9)

    local off = BridgeMove.facingOff(body, t.x, t.y)
    if off == nil or off < 90 then want = math.max(0.05, want) end
    freshDrive(BridgeMove.follow)
    if drive(body, red, BridgeMove.follow, pf, bx, by, t.x, t.y, want, "aside", false, d, toSpot) then return true end
    t.path = true
    log(sformat("seat: stuck stepping aside to %d,%d, engine path", t.cellX, t.cellY))
    BridgeMove.steering = false
    return false
end





local STRAIGHT_TURN_DEG = 25
local STRAIGHT_PIVOT_DEG = 60
local STRAIGHT_TURN_MAX = 8
function BridgeMove.goStraight(body, x, y, z, run, clear)
    local red = BridgeData.owner()
    if red == nil then return false end
    local F = BridgeMove.follow

    if F.pathUntil ~= nil and Bridge.time < F.pathUntil then return false end

    if clear ~= nil then
        if not clear(body, x, y, z or 0) then return false end
    elseif not BridgeMove.lineClear(body, x, y, z or 0) then
        return false
    end
    local pf = body:getPathFindBehavior2()
    if BridgeMove.pathing then
        pcall(function() pf:cancel() pf:reset() body:setPath2(nil) end)
        BridgeMove.pathing = false
        BridgeMove.goal = nil
    end

    if BridgeMove.kickAt ~= nil then
        pcall(function() if tostring(body:getBumpType()) == KICK then body:setBumpType("") end end)
        BridgeMove.kickAt = nil
    end
    Bridge.holdPos = nil
    BridgeMove.moving = true
    BridgeMove.steering = true
    local bx, by = body:getX(), body:getY()
    local toGoal = dist2d(bx, by, x, y)
    local d = dist2d(bx, by, red:getX(), red:getY())






    local kind = run and "straight-run" or "straight"
    local starting = (F.frame ~= Bridge.tick - 1 and F.pivotTick ~= Bridge.tick - 1) or F.kind ~= kind
    if starting then F.pivotFrames = 0 end
    local off = BridgeMove.facingOff(body, x, y)
    if off ~= nil and off > STRAIGHT_TURN_DEG and (F.pivotFrames or 0) < STRAIGHT_TURN_MAX then
        F.pivotFrames = (F.pivotFrames or 0) + 1

        pcall(function() if isFollowBump(tostring(body:getBumpType())) then BridgeMove.endFollowBump(body, "Stand") end end)
        local left = BridgeMove.pivotToward(body, x, y, STRAIGHT_PIVOT_DEG)
        F.pivotTick, F.kind = Bridge.tick, kind

        if left ~= nil then return true end
    end
    local M = BridgeMove.speedModel
    local want = run and (M.Run.a + M.Run.b * 0.8) or (M.Walk.a + M.Walk.b * 0.8)

    want = want * clamp(0.4 + 0.6 * toGoal, 0.5, 1.0)
    BridgeMove.walkType = run and "Run" or "Walk"
    freshDrive(F)
    if drive(body, red, F, pf, bx, by, x, y, want, run and "straight-run" or "straight", run == true, d, toGoal) then
        return true
    end
    BridgeMove.steering = false
    return false
end













BridgeMove.MOURN_PIVOT_DEG = 8
local MOURN_CHEST_BACK = 0.38
local MOURN_CHEST_FRONT = 0.25
local MOURN_HEAD_BACK = 0.7
local MOURN_HEAD_FRONT = 0.5
local MOURN_FEET_BACK = 0.6
local MOURN_FEET_FRONT = 0.75
local MOURN_CLEAR = 0.45
local MOURN_OFF_OUT = 0.12
BridgeMove.MOURN_CLEAR = MOURN_CLEAR



function BridgeMove.corpseLine(red)
    local rx, ry, z = red:getX(), red:getY(), red:getZ()
    local a = nil
    pcall(function() a = red:getAnimAngleRadians() end)
    if a == nil then
        pcall(function()
            local f = red:getForwardDirection()
            a = atan2(f:getY(), f:getX())
        end)
    end
    if a == nil then return nil end
    local front = false
    pcall(function() front = red:isFallOnFront() == true end)
    local hx, hy = math.cos(a), math.sin(a)
    if not front then hx, hy = -hx, -hy end
    local chest = front and MOURN_CHEST_FRONT or MOURN_CHEST_BACK
    local head = front and MOURN_HEAD_FRONT or MOURN_HEAD_BACK
    local feet = front and MOURN_FEET_FRONT or MOURN_FEET_BACK
    return { ex1 = rx + hx * head, ey1 = ry + hy * head, ex2 = rx - hx * feet, ey2 = ry - hy * feet,
             hx = hx, hy = hy, cx = rx + hx * chest, cy = ry + hy * chest, z = z, front = front }
end



function BridgeMove.mournBodyDist(s, px, py)
    local vx, vy = s.ex2 - s.ex1, s.ey2 - s.ey1
    local l2 = vx * vx + vy * vy
    local t = 0
    if l2 > 1e-9 then t = clamp(((px - s.ex1) * vx + (py - s.ey1) * vy) / l2, 0, 1) end
    local qx, qy = s.ex1 + vx * t, s.ey1 + vy * t
    return dist2d(px, py, qx, qy), qx, qy
end



function BridgeMove.mournCrosses(s, ax, ay, bx, by, clear)
    clear = clear or MOURN_CLEAR
    for i = 1, 8 do
        local t = i / 8
        local px, py = ax + (bx - ax) * t, ay + (by - ay) * t
        if segDist(px, py, s.ex1, s.ey1, s.ex2, s.ey2) < clear then return true end
    end
    return false
end






function BridgeMove.mournStepOff(body, s)
    local red = BridgeData.owner()
    if red == nil then return "stuck" end
    local bx, by = body:getX(), body:getY()
    local onD, qx, qy = BridgeMove.mournBodyDist(s, bx, by)
    if not (onD < MOURN_CLEAR or (s.offing and onD < MOURN_CLEAR + MOURN_OFF_OUT)) then
        s.offing = false
        return "off"
    end
    s.offing = true
    local ux, uy = bx - qx, by - qy
    local l = math.sqrt(ux * ux + uy * uy)
    if l < 0.05 then

        ux, uy, l = -s.hy, s.hx, 1
    end
    local out = MOURN_CLEAR + MOURN_OFF_OUT + 0.05
    local tx, ty = qx + ux / l * out, qy + uy / l * out
    if s.logged ~= "off" then
        s.logged = "off"
        log(sformat("mourning: on him (%.2f), one step off to %.2f,%.2f", onD, tx, ty))
    end
    if not BridgeMove.lineClear(body, tx, ty, s.z) then return "stuck" end
    local pf = body:getPathFindBehavior2()
    if BridgeMove.pathing then
        pcall(function() pf:cancel() pf:reset() body:setPath2(nil) end)
        BridgeMove.pathing = false
        BridgeMove.goal = nil
    end
    Bridge.holdPos = nil
    BridgeMove.moving = true
    BridgeMove.steering = true
    freshDrive(BridgeMove.follow)
    local d = dist2d(bx, by, red:getX(), red:getY())
    if drive(body, red, BridgeMove.follow, pf, bx, by, tx, ty, 0.02, "mourn", false, d, dist2d(bx, by, tx, ty)) then return "step" end
    BridgeMove.steering = false
    return "stuck"
end



function BridgeMove.seatAside(body)
    local red = BridgeData.owner()
    local zones = BridgeMove.seatZones(red)
    if zones == nil or math.abs(body:getZ() - zones.z) >= 0.5 then return false end
    local bcx, bcy = cellOf(body:getX(), body:getY())
    if not BridgeMove.inSeatZone(zones, bcx, bcy) then return false end
    local spot, checked = BridgeMove.seatSpot(red, zones, body:getX(), body:getY(), body, nil)
    if spot == nil then
        if Bridge.time >= (BridgeMove.seatAsideQuiet or 0) then
            BridgeMove.seatAsideQuiet = Bridge.time + 600
            log(sformat("seat: player %s next to waiting me, no free spot (%d cells checked)", zones.why, checked))
        end
        return false
    end
    Bridge.target = { x = spot.x + 0.5, y = spot.y + 0.5, z = zones.z, cellX = spot.x, cellY = spot.y }
    Bridge.targetSince = Bridge.time
    Bridge.pose = nil
    log(sformat("seat: player %s next to waiting me (%s), stepping aside to %d,%d (ring %d)",
        zones.why, tostring(Bridge.mode), spot.x, spot.y, spot.ring))
    return true
end



function BridgeMove.holdEnginePath(body)
    local F = BridgeMove.follow
    if F.engineHold == nil then
        F.engineHold = { tick = Bridge.time, x = body:getX(), y = body:getY(), checkAt = Bridge.time + 120 }
    end
end





function BridgeMove.onHisPath(bx, by, rx, ry, vx, vy)
    local vl = math.sqrt(vx * vx + vy * vy)
    if vl <= 0.01 then return nil end
    local ux, uy = vx / vl, vy / vl
    local ox, oy = bx - rx, by - ry
    local ahead = ux * ox + uy * oy
    local side = -uy * ox + ux * oy
    if ahead <= 0 or ahead >= ASIDE_AHEAD or math.abs(side) >= ASIDE_PATH then return nil end
    return ahead, side, ux, uy
end






local PASS_KEEP = 20
function BridgeMove.passThrough(body, on, why)
    local F = BridgeMove.follow
    if on then F.passUntil = Bridge.time + PASS_KEEP end
    if (F.passing == true) == on then return end
    local ok = pcall(function() body:setSolid(not on) end)
    F.passing = on and ok or nil
    if ok then log(on and ("lets player pass through: " .. tostring(why)) or ("solid again: " .. tostring(why))) end
end




function BridgeMove.pushCheck(body, red)
    local F = BridgeMove.follow
    if F == nil or red == nil then return end
    local pushing, fx, fy = false, 0, 0
    pcall(function()
        pushing = red:isPlayerMoving() == true
        if pushing then
            local fwd = red:getForwardDirection()
            fx, fy = fwd:getX(), fwd:getY()
        end
    end)
    local ahead = nil
    if pushing then
        pcall(function() ahead = BridgeMove.onHisPath(body:getX(), body:getY(), red:getX(), red:getY(), fx, fy) end)
    end

    if ahead == nil then
        if F.pushSeenIdle == nil or Bridge.time - F.pushSeenIdle > PUSH_GRACE then F.pushSinceIdle = nil end
        return
    end
    F.pushSeenIdle = Bridge.time
    F.pushSinceIdle = F.pushSinceIdle or Bridge.time
    if Bridge.time - F.pushSinceIdle >= ASIDE_PUSH then
        BridgeMove.passThrough(body, true, sformat("player keeps pushing while she %s (%.2f ahead)",
            Bridge.pose ~= nil and "sits" or "waits", ahead))
    end
end


function BridgeMove.passTick(body, red)
    local F = BridgeMove.follow
    if F == nil or not F.passing then return end
    local close, pushing = false, false
    pcall(function()
        local dx, dy = body:getX() - red:getX(), body:getY() - red:getY()
        close = dx * dx + dy * dy < 1.0
        pushing = red:isPlayerMoving() == true
    end)
    if close and pushing then F.passUntil = Bridge.time + PASS_KEEP return end
    if Bridge.time >= (F.passUntil or 0) then BridgeMove.passThrough(body, false, close and "player stopped" or "player passed") end
end



function BridgeMove.onRunLine(bx, by, rx, ry, fx, fy)
    local vl = math.sqrt(fx * fx + fy * fy)
    if vl <= 0.01 then return nil end
    local ux, uy = fx / vl, fy / vl
    local ox, oy = bx - rx, by - ry
    local ahead = ux * ox + uy * oy
    local side = -uy * ox + ux * oy
    if ahead <= -0.2 or ahead >= RUN_AHEAD or math.abs(side) >= RUN_PATH then return nil end
    return ahead, side, ux, uy
end









function BridgeMove.runGuard(body, red)
    if body == nil or red == nil then return end
    local running = false
    pcall(function() running = red:isRunning() == true or red:isSprinting() == true end)
    if not running then return end
    local ahead, side = nil, nil
    pcall(function()
        if math.abs(body:getZ() - red:getZ()) > 0.3 then return end
        local f = red:getForwardDirection()
        ahead, side = BridgeMove.onRunLine(body:getX(), body:getY(), red:getX(), red:getY(), f:getX(), f:getY())
    end)
    if ahead == nil then return end
    BridgeMove.passThrough(body, true, sformat("player runs at her (%.2f ahead, %.2f aside)", ahead, side))
end


local function stepAside(body, F, A, d)
    BridgeMove.walkType = "Walk"
    BridgeMove.applyAnimVars(body)
    BridgeMove.steering = true
    BridgeMove.followWs = 1.0
    BridgeMove.followBump(body, "Walk")
    if BridgeMove.bumpMove == "face" then
        BridgeMove.turnToward(body, A.x, A.y, 180)
    else
        pcall(function() body:getPathFindBehavior2():moveToPoint(A.x, A.y, 1.0) end)
    end
    BridgeMove.moving = true
    F.kind, F.s, F.want = "aside", 1.0, 0
    BridgeMove.pathResult = "follow-aside"
    trackStep(body)
    BridgeMove.traceFrame(body, d, false, false)
    return true
end

local function followTrailStep(body)
    local red = BridgeData.owner()
    if red == nil or Bridge.target ~= nil then
        BridgeMove.setCollide(body, true)
        BridgeMove.endFollowBump(body, "")
        return false
    end
    local F = BridgeMove.follow


    if F.pathUntil ~= nil and Bridge.time < F.pathUntil then
        local at = F.stuckAt
        local left = at ~= nil and Bridge.time >= (F.pathMin or 0)
            and dist2d(at.x, at.y, body:getX(), body:getY()) >= at.leave

        if not left and at ~= nil and Bridge.time >= (F.pathMin or 0) and Bridge.every(10)
            and dist2d(body:getX(), body:getY(), red:getX(), red:getY()) <= 2.0
            and BridgeMove.lineClear(body, red:getX(), red:getY(), red:getZ()) then
            left = true
        end
        if not left then
            F.kind = "stuck-path"
            BridgeMove.setCollide(body, true)
            BridgeMove.endFollowBump(body, "")
            return false
        end
        F.pathUntil = nil
        BridgeMove.holdEnginePath(body)
        if Bridge.verbose then
            log(sformat("stuck path done after %d ticks at %.2f %.2f", Bridge.time - at.tick, body:getX(), body:getY()))
        end
    end






    local stairs = false
    pcall(function()
        if math.abs(body:getZ() - red:getZ()) > 0.3 then stairs = true return end
        local a, b = body:getCurrentSquare(), red:getCurrentSquare()
        if a ~= nil and a.HasStairs ~= nil and (a:HasStairs() or (b ~= nil and b:HasStairs())) then stairs = true end
    end)
    if stairs then F.stairsUntil = Bridge.time + 30 end
    if Bridge.time < (F.stairsUntil or 0) then
        if F.kind ~= "path-stairs" and Bridge.verbose then
            log(sformat("stairs: engine path (her z %.2f, his z %.2f)", body:getZ(), red:getZ()))
        end
        F.kind = "path-stairs"
        BridgeMove.setCollide(body, true)
        BridgeMove.endFollowBump(body, "")
        if BridgeMove.steering then
            BridgeMove.steering = false
            BridgeMove.pathing = false
        end
        return false
    end


    if Bridge.time < (F.awayUntil or 0) then
        F.kind = "path-away"
        return false
    end

    local tx, ty, tz, kind, along
    local cache = F.cache
    if cache ~= nil and (Bridge.time - cache.tick) < 4 and cache.body == body then
        tx, ty, tz, kind = cache.x, cache.y, cache.z, cache.kind
        if tx ~= nil then
            local rx, ry = red:getX(), red:getY()
            if kind == "player" then tx, ty = rx, ry end
            along = dist2d(body:getX(), body:getY(), tx, ty) + (kind == "player" and 0 or cache.tail)
        end
    else
        tx, ty, tz, kind, along = BridgeMove.followTarget(body, red)
        local tail = 0
        if tx ~= nil and kind ~= "player" then tail = along - dist2d(body:getX(), body:getY(), tx, ty) end
        F.cache = { tick = Bridge.time, body = body, x = tx, y = ty, z = tz, kind = kind, tail = tail }
    end






    if F.engineHold ~= nil then
        local H = F.engineHold
        local hx, hy = body:getX(), body:getY()
        local keep = kind ~= "player"
        local why = "sees player"
        if keep and Bridge.time >= H.checkAt then
            if dist2d(H.x, H.y, hx, hy) < 1.0 then keep, why = false, "no progress" end
            H.x, H.y, H.checkAt = hx, hy, Bridge.time + 120
        end
        if keep then
            F.kind = "path-hold"
            BridgeMove.setCollide(body, true)
            BridgeMove.endFollowBump(body, "")
            if BridgeMove.steering then
                BridgeMove.steering = false
                BridgeMove.pathing = false
            end
            return false
        end
        if Bridge.verbose then
            log(sformat("engine path released after %d ticks: %s", Bridge.time - H.tick, why))
        end
        F.engineHold = nil
    end
    if tx == nil then
        F.kind = "path"
        BridgeMove.holdEnginePath(body)
        BridgeMove.setCollide(body, true)
        BridgeMove.endFollowBump(body, "")
        if BridgeMove.steering then
            BridgeMove.steering = false
            BridgeMove.pathing = false
        end
        return false
    end
    local pf = body:getPathFindBehavior2()
    local d = dist2d(body:getX(), body:getY(), red:getX(), red:getY())
    local redGoes = BridgeMove.redMoving or BridgeMove.redSpeed > 0.012
    local running = false
    pcall(function() running = red:isRunning() or red:isSprinting() end)

    local walk = (running or along > 4) and "Run" or "Walk"
    if BridgeMove.walkType == "Run" and not running and along > 2.5 then walk = "Run" end
    BridgeMove.walkType = walk

    local extra = keepExtra()
    local gap = (walk == "Run" and GAP_RUN or GAP_WALK) + extra



    if Bridge.verbose and redGoes then
        F.gapSum, F.gapWant, F.gapN = (F.gapSum or 0) + d, (F.gapWant or 0) + gap, (F.gapN or 0) + 1
        if d < gap - 0.5 then F.gapClose = (F.gapClose or 0) + 1 end


        if kind ~= "player" then F.gapNoLine = (F.gapNoLine or 0) + 1 end
        if F.gapKind ~= nil and F.gapKind ~= F.kind then F.gapSwitch = (F.gapSwitch or 0) + 1 end
        F.gapKind = F.kind
        if Bridge.time - (F.gapLog or 0) >= 300 and F.gapN >= 120 then
            log(sformat("gap %s %s: walked at %.2f, asked %.2f, closer than asked by 0.5+ in %d%% of %d frames, speed scale %.2f (%d samples), no line %d%%, kind switches %d",
                BridgeMove.keepFar() and "far" or "near", walk, F.gapSum / F.gapN, F.gapWant / F.gapN,
                math.floor(100 * (F.gapClose or 0) / F.gapN + 0.5), F.gapN, BridgeMove.speedScale, BridgeMove.speedScaleN,
                math.floor(100 * (F.gapNoLine or 0) / F.gapN + 0.5), F.gapSwitch or 0))
            F.gapSum, F.gapWant, F.gapN, F.gapClose, F.gapLog = 0, 0, 0, 0, Bridge.time
            F.gapNoLine, F.gapSwitch = 0, 0
        end
    end

    local keep = BridgeMove.keepSide()
    if keep ~= "behind" then
        local done = followSpot(body, red, F, pf, d, redGoes, running, keep)
        if done ~= nil then return done end
    elseif F.inSpot then
        BridgeMove.spotReset()
    end








    local bx, by = body:getX(), body:getY()
    local A = F.asideTo
    if A ~= nil then
        if Bridge.time < A.untilT and dist2d(bx, by, A.x, A.y) > 0.25 and F.cross == nil then
            return stepAside(body, F, A, d)
        end
        F.asideTo = nil
        F.asideQuiet = Bridge.time + ASIDE_QUIET

        BridgeMove.moving = false
        if Bridge.verbose then log(sformat("aside done at %.2f %.2f, %.2f from player", bx, by, d)) end
    end




    local pushing, fx, fy = false, 0, 0
    pcall(function()
        pushing = red:isPlayerMoving() == true
        if pushing then
            local fwd = red:getForwardDirection()
            fx, fy = fwd:getX(), fwd:getY()
        end
    end)
    if not pushing and redGoes then fx, fy, pushing = BridgeMove.redVx or 0, BridgeMove.redVy or 0, true end



    local coming = false
    if pushing and d > 0.01 then
        local vl = math.sqrt(fx * fx + fy * fy)
        if vl > 0.001 then
            coming = (fx * (bx - red:getX()) + fy * (by - red:getY())) / (vl * d) > COMING_COS
        end
    end



    if running and kind == "player" and F.asideTo == nil and Bridge.time > (F.asideQuiet or 0) then
        local ra, rs, rux, ruy = BridgeMove.onRunLine(bx, by, red:getX(), red:getY(), fx, fy)
        if ra ~= nil and ra > 0 then
            local nx, ny = -ruy, rux
            if rs < 0 then nx, ny = -nx, -ny end
            local tries = { { bx + nx * ASIDE_STEP, by + ny * ASIDE_STEP, "side" },
                            { bx - nx * ASIDE_STEP, by - ny * ASIDE_STEP, "other side" } }
            for _, t in ipairs(tries) do
                if BridgeMove.lineClear(body, t[1], t[2], tz) then
                    F.asideTo = { x = t[1], y = t[2], untilT = Bridge.time + ASIDE_MAX }
                    F.cross = nil
                    if Bridge.verbose then
                        log(sformat("aside %s: player runs at her, %.2f ahead, %.2f off his line", t[3], ra, rs))
                    end
                    return stepAside(body, F, F.asideTo, d)
                end
            end
        end
    end

    local canPush = pushing and kind == "player" and d < ASIDE_AHEAD + ASIDE_PATH and F.cross == nil
    local ahead, side, ux, uy = nil, nil, nil, nil
    if canPush then ahead, side, ux, uy = BridgeMove.onHisPath(bx, by, red:getX(), red:getY(), fx, fy) end





    if ahead ~= nil then
        F.pushSeen = Bridge.time
    elseif F.pushSeen == nil or Bridge.time - F.pushSeen > PUSH_GRACE then
        F.pushSince = nil
    end


    if Bridge.verbose and d < ASIDE_AHEAD + ASIDE_PATH then
        local why
        if ahead ~= nil then why = "pushing"
        elseif not pushing then why = "not pressing"
        elseif kind ~= "player" then why = "no line to him (" .. tostring(kind) .. ")"
        elseif F.cross ~= nil then why = "crossing"
        else
            local vl = math.sqrt(fx * fx + fy * fy)
            local al, sd = 0, 0
            if vl > 0.01 then
                local ox, oy = bx - red:getX(), by - red:getY()
                al, sd = (fx * ox + fy * oy) / vl, (-fy * ox + fx * oy) / vl
            end
            why = sformat("off his path (%.2f ahead, %.2f aside)", al, sd)
        end
        local cat = why:match("^[%a ]+")
        if cat ~= F.pushWhy then
            F.pushWhy = cat
            log(sformat("push check at %.2f: %s", d, why))
        end
    elseif F.pushWhy ~= nil then
        F.pushWhy = nil
    end
    if ahead ~= nil then
        F.pushSince = F.pushSince or Bridge.time

        if Bridge.time - F.pushSince >= ASIDE_PUSH then
            F.pushSince = nil


            if Bridge.time > (F.asideQuiet or 0) then
                local nx, ny = -uy, ux
                if side < 0 then nx, ny = -nx, -ny end
                local tries = { { bx + nx * ASIDE_STEP, by + ny * ASIDE_STEP, "side" },
                                { bx - nx * ASIDE_STEP, by - ny * ASIDE_STEP, "other side" } }
                for _, t in ipairs(tries) do
                    if BridgeMove.lineClear(body, t[1], t[2], tz) then
                        F.asideTo = { x = t[1], y = t[2], untilT = Bridge.time + ASIDE_MAX }
                        if Bridge.verbose then
                            log(sformat("aside %s: player walks into her, %.2f ahead, %.2f off his line", t[3], ahead, side))
                        end
                        return stepAside(body, F, F.asideTo, d)
                    end
                end
            end



            BridgeMove.passThrough(body, true, sformat("player keeps pushing, %s (%.2f ahead)",
                Bridge.time > (F.asideQuiet or 0) and "no room aside" or "just stepped aside", ahead))
        end
    end






    local sees = kind == "player"
    local stopAt = STOP_GAP + extra
    local why = nil
    if not redGoes then
        if not sees and extra > 0 then stopAt, why = STOP_GAP, "no line to player" end
        if along > DOORWAY_STOP and BridgeMove.inDoorway(body) then


            local room = true
            if sees and d > 0.001 then
                local k = DOORWAY_ROOM / d
                local qx, qy = red:getX() + (body:getX() - red:getX()) * k, red:getY() + (body:getY() - red:getY()) * k
                room = not BridgeMove.doorwayCell(math.floor(qx), math.floor(qy), math.floor(body:getZ()))
            end
            if room then stopAt, why = DOORWAY_STOP, "in a doorway" end
        end
    end
    if why ~= F.stopWhy then
        F.stopWhy = why
        if Bridge.verbose and why ~= nil then
            log(sformat("stand rule: %s, stops at %.2f instead of %.2f (d %.2f, along %.2f)", why, stopAt, STOP_GAP + extra, d, along))
        end
    end

    if not BridgeMove.moving then



        if coming then
            if d > START_DIST + extra then
                BridgeMove.moving = true
                Bridge.holdPos = nil
            end
        elseif along > START_DIST + extra or (redGoes and along > START_GOING + extra) then
            BridgeMove.moving = true
            Bridge.holdPos = nil
        elseif why ~= nil and along > stopAt + 0.3 then

            BridgeMove.moving = true
            Bridge.holdPos = nil
        end
    elseif not redGoes and along <= stopAt + 0.05 then
        BridgeMove.moving = false
    elseif coming and d <= START_DIST + extra then

        BridgeMove.moving = false
        if Bridge.verbose then log(sformat("stands: player comes at her, d %.2f", d)) end
    end
    BridgeMove.applyAnimVars(body)
    if not BridgeMove.moving then
        if BridgeMove.onPath() then BridgeMove.stopPath(body) end



        F.cross = nil
        F.kind, F.s, F.want = "stand", 0, 0
        if Bridge.zombieTicks % 30 == 0 then
            pcall(function() body:faceLocationF(red:getX(), red:getY()) end)
        end
        trackStep(body)
        BridgeMove.traceFrame(body, d, false, false)
        return true
    end






    local function quenchPath()
        if BridgeMove.pathing then
            pcall(function() pf:cancel() pf:reset() body:setPath2(nil) end)
            BridgeMove.pathing = false
            BridgeMove.goal = nil
        end
    end
    BridgeMove.steering = true
    local bx, by = body:getX(), body:getY()
    local px, py = tx, ty
    local err, want
    if redGoes then






        if kind == "player" and along - d < 0.4 then
            px, py = red:getX(), red:getY()
        else
            local qx, qy = BridgeMove.trailPoint(red, gap)
            if BridgeMove.lineClear(body, qx, qy, tz) then
                px, py = qx, qy
                kind = kind == "player" and "rope" or kind
            end
        end
        err = (d < gap) and (d - gap) or (along - gap)









        if sees then F.noLine = 0 else F.noLine = (F.noLine or 0) + frameDt() end
        if (sees or F.noLine < NO_LINE_FRAMES) and (px - bx) * (red:getX() - bx) + (py - by) * (red:getY() - by) <= 0 then
            px, py = red:getX(), red:getY()
        end
        want = BridgeMove.redSpeed * clamp(1 + 0.7 * err, 0.3, 1.7)





        if BridgeMove.catchUp and err > CATCH_FROM then
            local run = BridgeMove.speedModel.Run
            local runStep = (run.a + run.b * 0.65) * BridgeMove.speedScale
            want = math.max(want, runStep * clamp((err - CATCH_FROM) / (CATCH_FULL - CATCH_FROM), 0, 1))
        end




        local stepNow = BridgeMove.redStep or 0
        if stepNow < 0.35 * BridgeMove.redSpeed and err < 0.4 then
            want = math.min(want, math.max(stepNow, 0.25 * want))
        end
    else

        if kind == "player" then
            local k = d > 0.001 and math.max(0, d - stopAt) / d or 0
            px, py = bx + (tx - bx) * k, by + (ty - by) * k
        end
        err = along - stopAt


        local base = BridgeMove.bumpMove == "face" and 0.036 * BridgeMove.speedScale or BridgeMove.stepPerMul
        want = base * clamp(0.4 + 0.5 * err, 0.25, 0.9)
    end



    if redGoes and sees and d < 0.75 then
        quenchPath()
        BridgeMove.endFollowBump(body, "Stand")
        BridgeMove.setCollide(body, true)
        BridgeMove.steering = false
        F.cross = nil
        F.kind, F.s, F.want = "yield", 0, 0
        trackStep(body)
        BridgeMove.traceFrame(body, d, false, false)
        return true
    end





    do
        local minStep = BridgeMove.speedModel.Walk.a * BridgeMove.speedScale


        if redGoes and BridgeMove.redSpeed < minStep * SLOW_RED then
            F.slowFrames = (F.slowFrames or 0) + frameDt()
        else
            F.slowFrames = 0
        end
        local slowRed = F.slowFrames >= SLOW_FRAMES
        if not slowRed then
            F.slowWait = nil
        elseif F.slowWait then
            if err > SLOW_GO then F.slowWait = nil end
        elseif err <= 0 then
            F.slowWait = true
        end
        if F.slowWait then
            quenchPath()
            BridgeMove.endFollowBump(body, "Stand")
            BridgeMove.setCollide(body, true)
            BridgeMove.steering = false
            F.kind, F.s, F.want = "slow-wait", 0, 0
            trackStep(body)
            BridgeMove.traceFrame(body, d, false, false)
            return true
        end
    end







    if redGoes and err <= 0 and (BridgeMove.redStep or 0) < 0.35 * BridgeMove.redSpeed
        and want < 0.5 * BridgeMove.speedModel.Walk.a * BridgeMove.speedScale then
        quenchPath()
        BridgeMove.endFollowBump(body, "Stand")
        BridgeMove.setCollide(body, true)
        BridgeMove.steering = false
        F.kind, F.s, F.want = "hold", 0, 0
        trackStep(body)
        BridgeMove.traceFrame(body, d, false, false)
        return true
    end



    local rx0, ry0 = red:getX(), red:getY()
    if dist2d(px, py, rx0, ry0) > d + 0.6 then
        if BridgeMove.lineClear(body, rx0, ry0, tz) then
            px, py, kind = rx0, ry0, "player"
        else
            if F.kind ~= "path-away" and Bridge.verbose then
                log(sformat("path-away: goal %.2f %.2f is farther from player than she is (d %.2f), no line to player, engine path", px, py, d))
            end
            F.kind = "path-away"
            F.awayUntil = Bridge.time + 30
            BridgeMove.holdEnginePath(body)
            BridgeMove.endFollowBump(body, "")
            BridgeMove.steering = false
            BridgeMove.setCollide(body, true)
            return false
        end
    end
    quenchPath()

    if F.aimFrame == Bridge.tick - 1 and F.aimX ~= nil and dist2d(F.aimX, F.aimY, px, py) < 1.5 then
        px = F.aimX * 0.7 + px * 0.3
        py = F.aimY * 0.7 + py * 0.3
    end
    F.aimX, F.aimY, F.aimFrame = px, py, Bridge.tick

    local nx, ny, narrow = BridgeMove.throughNarrow(body, px, py)
    if narrow then
        px, py = nx, ny
        kind = kind .. "-narrow"
    end
    return drive(body, red, F, pf, bx, by, px, py, want, kind, running, d, err)
end


local function kindGroup(kind)
    kind = tostring(kind)
    if kind == "player" or kind == "rope" or kind == "player-narrow" or kind == "rope-narrow" then return "to player" end
    if kind == "trail" or kind == "trail-narrow" then return "trail" end
    if kind:sub(1, 4) == "path" or kind == "stuck-path" then return "engine " .. kind end
    return kind
end





function BridgeMove.followTrail(body)
    local done = followTrailStep(body)
    if Bridge.verbose then
        local F = BridgeMove.follow
        local group = kindGroup(F.kind)
        if group ~= F.loggedGroup then
            if Bridge.time - (F.loggedAt or 0) >= 6 then
                local red = BridgeData.owner()
                local line = "?"
                if red ~= nil then
                    line = BridgeMove.lineClear(body, red:getX(), red:getY(), red:getZ()) and "yes" or "no"
                    log(sformat("follow: %s -> %s, d %.2f, line to player %s, her %.1f %.1f, his %.1f %.1f, engine path %s%s",
                        tostring(F.loggedGroup), group, dist2d(body:getX(), body:getY(), red:getX(), red:getY()), line,
                        body:getX(), body:getY(), red:getX(), red:getY(), tostring(BridgeMove.pathResult),
                        (F.skippedKinds or 0) > 0 and sformat(", %d switches not logged", F.skippedKinds) or ""))
                end
                F.loggedGroup, F.loggedAt, F.skippedKinds = group, Bridge.time, 0
            else
                F.skippedKinds = (F.skippedKinds or 0) + 1
            end
        end
    end
    return done
end






local function postAt(cell, ax, ay, bx, by, z)
    local a = cell:getGridSquare(ax, ay, z)
    local b = cell:getGridSquare(bx, by, z)
    if a == nil or b == nil then return true end
    return a:isBlockedTo(b) or not a:isFree(false) or not b:isFree(false)
end






local function narrowEdge(cell, from, to, z)
    if from:isDoorTo(to) then return true, true end
    local fx, fy, tx, ty = from:getX(), from:getY(), to:getX(), to:getY()
    local function side(dx, dy)
        return postAt(cell, fx + dx, fy + dy, tx + dx, ty + dy, z)
            or from:isBlockedTo(cell:getGridSquare(fx + dx, fy + dy, z) or from)
            or to:isBlockedTo(cell:getGridSquare(tx + dx, ty + dy, z) or to)
    end
    if fx ~= tx then return side(0, -1) and side(0, 1), false end
    return side(-1, 0) and side(1, 0), false
end





function BridgeMove.doorwayCell(cx, cy, z)
    local F = BridgeMove.follow
    local key = cx .. "," .. cy .. "," .. z
    if F.doorCells == nil or (F.doorCellsN or 0) > 200 then F.doorCells, F.doorCellsN = {}, 0 end
    local c = F.doorCells[key]
    if c ~= nil and Bridge.time - c.tick < 100 then return c.value end
    local value = false
    pcall(function()
        local cell = getCell()
        local me = cell:getGridSquare(cx, cy, z)
        if me == nil then return end
        local function open(a, b)
            if a == nil or b == nil or a:isBlockedTo(b) then return false end
            local climb = false
            pcall(function() climb = a:getWindowTo(b) ~= nil or a:getWindowFrameTo(b) ~= nil or a:isHoppableTo(b) end)
            return not climb
        end
        for _, s in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nb = cell:getGridSquare(cx + s[1], cy + s[2], z)
            if open(me, nb) then
                local narrow, door = narrowEdge(cell, me, nb, z)
                if door then value = true return end
                if narrow then
                    local nxt = cell:getGridSquare(cx + 2 * s[1], cy + 2 * s[2], z)
                    local prv = cell:getGridSquare(cx - s[1], cy - s[2], z)
                    local nextNarrow = open(nb, nxt) and (narrowEdge(cell, nb, nxt, z)) == true
                    local prevNarrow = open(prv, me) and (narrowEdge(cell, prv, me, z)) == true
                    if not (nextNarrow and prevNarrow) then value = true return end
                end
            end
        end
    end)
    if c == nil then F.doorCellsN = (F.doorCellsN or 0) + 1 end
    F.doorCells[key] = { tick = Bridge.time, value = value }
    return value
end




function BridgeMove.inDoorway(body)
    local F = BridgeMove.follow
    local bx, by = body:getX(), body:getY()
    if BridgeMove.doorwayCell(math.floor(bx), math.floor(by), math.floor(body:getZ())) then
        F.doorAt = { x = bx, y = by, tick = Bridge.time }
        return true
    end
    local a = F.doorAt
    if a ~= nil then
        if Bridge.time - a.tick < 90 and dist2d(a.x, a.y, bx, by) < DOORWAY_CLEAR then return true end
        F.doorAt = nil
    end
    return false
end





function BridgeMove.throughNarrow(body, px, py)
    local rx, ry, used = px, py, false
    local F = BridgeMove.follow
    local c = F.cross
    if c ~= nil then
        local bx, by = body:getX(), body:getY()
        local past = (c.axis == "x") and ((bx - c.edge) * c.dir > 0.25) or ((by - c.edge) * c.dir > 0.25)
        local away = dist2d(bx, by, c.tx, c.ty) > 3.5





        local closed = false
        if c.door and c.fx ~= nil then
            pcall(function()
                local cell = getCell()
                local a = cell:getGridSquare(c.fx, c.fy, c.z)
                local b = cell:getGridSquare(c.bx2, c.by2, c.z)
                closed = a ~= nil and b ~= nil and a:isBlockedTo(b)
            end)
        end
        if closed then
            F.cross = nil
            F.pathUntil = Bridge.time + 60
            F.stuckAt = nil
            log("cross dropped: door on the edge closed")
            return px, py, false
        end
        if past or away or Bridge.time > c.until_ then
            F.cross = nil
        else
            return c.tx, c.ty, true
        end
    end
    pcall(function()
        local cell = getCell()
        local z = math.floor(body:getZ())
        local bx, by = body:getX(), body:getY()
        local dist = math.sqrt((px - bx) ^ 2 + (py - by) ^ 2)
        if dist < 0.05 then return end
        local steps = math.max(1, math.ceil(math.min(dist, 1.2) / 0.1))
        local sx0, sy0 = math.floor(bx), math.floor(by)
        for i = 1, steps do
            local t = i * 0.1 / dist
            if t > 1 then t = 1 end
            local sx, sy = math.floor(bx + (px - bx) * t), math.floor(by + (py - by) * t)
            if sx ~= sx0 or sy ~= sy0 then
                if sx ~= sx0 and sy ~= sy0 then return end
                local from = cell:getGridSquare(sx0, sy0, z)
                local to = cell:getGridSquare(sx, sy, z)
                if from == nil or to == nil then return end
                local isNarrow, isDoor = narrowEdge(cell, from, to, z)
                if not isNarrow then return end


                if sx ~= sx0 then
                    local dir = sx > sx0 and 1 or -1
                    local ex, cy = math.max(sx, sx0), sy0 + 0.5
                    rx, ry = ex + dir * 0.6, cy
                    F.cross = { axis = "x", edge = ex, dir = dir, tx = rx, ty = ry, door = isDoor, until_ = Bridge.time + 150,
                        fx = sx0, fy = sy0, bx2 = sx, by2 = sy, z = z }
                else
                    local dir = sy > sy0 and 1 or -1
                    local ey, cx = math.max(sy, sy0), sx0 + 0.5
                    rx, ry = cx, ey + dir * 0.6
                    F.cross = { axis = "y", edge = ey, dir = dir, tx = rx, ty = ry, door = isDoor, until_ = Bridge.time + 150,
                        fx = sx0, fy = sy0, bx2 = sx, by2 = sy, z = z }
                end
                used = true
                return
            end
        end
    end)
    return rx, ry, used
end







local function stepNeedsClimb(a, b)
    local yes = false
    pcall(function()
        yes = a:getWindowTo(b) ~= nil or a:getWindowFrameTo(b) ~= nil or a:isHoppableTo(b)
    end)
    return yes
end










local function engineBlocked(a, b)
    if BridgeMove.engineTest == nil then
        local has = false
        pcall(function() has = a.testCollideAdjacentAdvanced ~= nil end)
        BridgeMove.engineTest = has
        log("engine collide test " .. (has and "available" or "missing: line check as before"))
    end
    if not BridgeMove.engineTest then return false end




    local blocked = false
    pcall(function()
        if not (a:HasStairs() or b:HasStairs()) then return end
        blocked = a:testCollideAdjacentAdvanced(b:getX() - a:getX(), b:getY() - a:getY(), 0, false) == true
    end)
    return blocked
end
BridgeMove.engineBlocked = engineBlocked


local function underCar(sq)
    local F = BridgeMove.follow
    if F.carCells == nil or (F.carCellsN or 0) > 300 then F.carCells, F.carCellsN = {}, 0 end
    local key = sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
    local c = F.carCells[key]
    if c ~= nil and Bridge.time - c.tick < 30 then return c.value end
    local value = false
    pcall(function() value = sq:isVehicleIntersecting() == true end)
    if c == nil then F.carCellsN = (F.carCellsN or 0) + 1 end
    F.carCells[key] = { tick = Bridge.time, value = value }
    return value
end






function BridgeMove.lineClear(body, gx, gy, gz)
    local ok = false
    pcall(function()
        if math.abs(body:getZ() - gz) >= 0.5 then return end
        local cell = getCell()
        local bx, by = body:getX(), body:getY()
        local z = math.floor(gz)
        local dist = math.sqrt((gx - bx) ^ 2 + (gy - by) ^ 2)
        local steps = math.max(1, math.ceil(dist / 0.4))
        local prev = cell:getGridSquare(math.floor(bx), math.floor(by), z)
        if prev == nil then return end




        local cars = true
        for i = 1, steps do
            local t = i / steps
            local sx, sy = math.floor(bx + (gx - bx) * t), math.floor(by + (gy - by) * t)
            if sx ~= prev:getX() or sy ~= prev:getY() then
                local sq = cell:getGridSquare(sx, sy, z)
                if sq == nil then return end
                if sx ~= prev:getX() and sy ~= prev:getY() then
                    local a = cell:getGridSquare(sx, prev:getY(), z)
                    local b = cell:getGridSquare(prev:getX(), sy, z)
                    if a == nil or b == nil or prev:isBlockedTo(a) or a:isBlockedTo(sq) or prev:isBlockedTo(b) or b:isBlockedTo(sq) then return end
                    if stepNeedsClimb(prev, a) or stepNeedsClimb(a, sq) or stepNeedsClimb(prev, b) or stepNeedsClimb(b, sq) then return end
                    if not a:isFree(false) or not b:isFree(false) then return end
                    if engineBlocked(prev, a) or engineBlocked(a, sq) or engineBlocked(prev, b) or engineBlocked(b, sq) then return end
                    if cars and (underCar(a) or underCar(b)) then return end
                elseif prev:isBlockedTo(sq) or stepNeedsClimb(prev, sq) or engineBlocked(prev, sq) then
                    return
                end
                if i < steps and not sq:isFree(false) then return end

                if i < steps and cars and underCar(sq) then return end
                prev = sq
            end
        end
        ok = true
    end)
    return ok
end

function BridgeMove.walkReach(body, tx, ty, tz, maxNodes)
    local ok = false
    pcall(function()
        local cell = getCell()
        local bz = math.floor(body:getZ())
        if math.floor(tz) ~= bz then return end
        local bx, by = math.floor(body:getX()), math.floor(body:getY())
        tx, ty = math.floor(tx), math.floor(ty)
        if bx == tx and by == ty then ok = true return end
        local start = cell:getGridSquare(bx, by, bz)
        if start == nil then return end
        local budget = maxNodes or 240
        local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
        local seen = { [bx .. "," .. by] = true }
        local queue, head = { start }, 1
        local visited = 0
        while head <= #queue and visited < budget do
            local cur = queue[head]
            head = head + 1
            visited = visited + 1
            local cx, cy = cur:getX(), cur:getY()
            for i = 1, 4 do
                local nx, ny = cx + dirs[i][1], cy + dirs[i][2]
                local key = nx .. "," .. ny
                if not seen[key] then
                    local nb = cell:getGridSquare(nx, ny, bz)
                    if nb ~= nil and not cur:isBlockedTo(nb) and nb:isFree(false)
                        and not stepNeedsClimb(cur, nb) and not cur:isDoorTo(nb) and not underCar(nb) then
                        if nx == tx and ny == ty then ok = true return end
                        seen[key] = true
                        queue[#queue + 1] = nb
                    end
                end
            end
        end
    end)
    return ok
end


function BridgeMove.traceFrame(body, d, needPath, stalled)
    if Bridge.tick < BridgeMove.traceUntil then
        pcall(function()
            local red = BridgeData.owner()
            local bx, by, rx, ry = body:getX(), body:getY(), red:getX(), red:getY()

            local last = BridgeMove.traceLast
            local frames = last and math.max(1, Bridge.tick - last.t) or 1
            local bstep = last and dist2d(last.bx, last.by, bx, by) / frames or 0
            local rstep = last and dist2d(last.rx, last.ry, rx, ry) / frames or 0
            BridgeMove.traceLast = { t = Bridge.tick, bx = bx, by = by, rx = rx, ry = ry }
            local mode = (red:isSprinting() and "S" or "") .. (red:isRunning() and "R" or "") .. (red:isSneaking() and "K" or "")
            local stype, wt, smod = -1, "?", -1
            pcall(function() smod = body:getSpeedMod() end)
            pcall(function() stype = body:getSpeedType() end)
            pcall(function() wt = tostring(body:getWalkType()) end)
            log(sformat("trace t=%d st=%s bump=%s %s wt=%s stype=%d d=%.2f bstep=%.3f rstep=%.3f player=%s path=%s need=%s stall=%s res=%s restarts=%d ws=%.2f smod=%.3f anim=%s fk=%s fs=%.2f ferr=%.2f fk1=%.3f tx=%.2f ty=%.2f bx=%.2f by=%.2f rx=%.2f ry=%.2f",
                Bridge.tick, tostring(body:getActionStateName()), tostring(body:getBumpType()),
                BridgeMove.walkType, wt, stype, d, bstep, rstep, mode ~= "" and mode or "-", tostring(BridgeMove.pathing),
                tostring(needPath), tostring(stalled), BridgeMove.pathResult, BridgeMove.restarts, BridgeMove.walkSpeedVar, smod, BridgeMove.animOld and "old" or "new",
                tostring(BridgeMove.follow.kind), BridgeMove.follow.s or 0, BridgeMove.follow.gap or 0, BridgeMove.stepPerMul or 0,
                BridgeMove.follow.tx or 0, BridgeMove.follow.ty or 0, bx, by, rx, ry))
        end)
    end
end

function BridgeMove.currentGoal(body)
    if Bridge.follow then
        local red = BridgeData.owner()
        if red == nil then return nil end




        local pend = false
        pcall(function() pend = BridgeInventory ~= nil and BridgeInventory.transferPending(body) end)
        if pend then
            BridgeMove.moving = false
            return nil
        end
        local d = dist2d(body:getX(), body:getY(), red:getX(), red:getY())
        if BridgeMove.moving then


            if d <= FOLLOW_STOP and not BridgeMove.redMoving then BridgeMove.moving = false end
        else
            if d > FOLLOW_START then
                BridgeMove.moving = true


                Bridge.holdPos = nil
            end
        end
        if not BridgeMove.moving then return nil end
        local gx, gy, gz = nearRed(red, body)
        return gx, gy, gz, d
    end
    if Bridge.target then
        local t = Bridge.target
        return t.x, t.y, t.z, dist2d(body:getX(), body:getY(), t.x, t.y)
    end
    return nil
end






BridgeMove.slowDist = 1.6
local function pickWalkType(d)
    if BridgeMove.forcedWalk ~= nil then return BridgeMove.forcedWalk end
    local red = BridgeData.owner()
    local running = false
    if red ~= nil then
        pcall(function() running = red:isRunning() or red:isSprinting() end)
    end
    if running or d > RUN_DIST then return "Run" end

    if BridgeMove.walkType == "Run" and d > RUN_STOP then return "Run" end
    if BridgeMove.slowDist > 0 and BridgeMove.redMoving and d < BridgeMove.slowDist then return "SlowWalk" end
    return "Walk"
end




local function squareAhead(body)
    local dir = body:getDirectionAngle()
    local bx, by, bz = math.floor(body:getX()), math.floor(body:getY()), body:getZ()
    local sx, sy
    if (dir >= -180 and dir < -45) or (dir >= 135 and dir <= 180) then
        sx, sy = bx, by
    elseif dir >= -45 and dir < 45 then
        sx, sy = bx + 1, by
    elseif dir >= 45 and dir < 135 then
        sx, sy = bx, by + 1
    end
    if sx == nil then return nil end
    return getCell():getGridSquare(sx, sy, bz)
end











local function isDoor(object)
    local door = false
    pcall(function() door = instanceof(object, "IsoDoor") or (instanceof(object, "IsoThumpable") and object:isDoor()) end)
    return door
end



local function doorKind(door)
    local kind = "single"
    pcall(function()
        if IsoDoor.getDoubleDoorIndex(door) ~= -1 then
            kind = "double"
        elseif instanceof(door, "IsoDoor") and IsoDoor.getGarageDoorIndex(door) ~= -1 then
            kind = "garage"
        end
    end)
    return kind
end


local function doorParts(door, kind)
    local parts = {}
    pcall(function()
        if kind == "double" then
            for i = 1, 4 do
                local p = IsoDoor.getDoubleDoorObject(door, i)
                if p ~= nil then parts[#parts + 1] = p end
            end
        elseif kind == "garage" then
            parts[1] = door
            local p = IsoDoor.getGarageDoorPrev(door)
            while p ~= nil and #parts < 12 do parts[#parts + 1] = p p = IsoDoor.getGarageDoorPrev(p) end
            p = IsoDoor.getGarageDoorNext(door)
            while p ~= nil and #parts < 24 do parts[#parts + 1] = p p = IsoDoor.getGarageDoorNext(p) end
        end
    end)
    if #parts == 0 then parts = { door } end
    return parts
end






local function doorAnchor(door, kind)
    if kind ~= "double" then return door end
    local anchor = nil
    pcall(function() anchor = IsoDoor.getDoubleDoorObject(door, 1) or IsoDoor.getDoubleDoorObject(door, 4) end)
    return anchor or door
end




local function doorCells(door, kind)
    local cells = {}
    local north = false
    pcall(function() north = door:getNorth() end)
    for _, p in ipairs(doorParts(door, kind)) do
        local sq = p:getSquare()
        if sq ~= nil then
            local x, y = sq:getX(), sq:getY()
            cells[#cells + 1] = { x = x, y = y, z = sq:getZ(), ox = north and x or x - 1, oy = north and y - 1 or y }
        end
    end
    return cells, north
end



local function carInDoorway(cells)
    local cell = getCell()
    for _, c in ipairs(cells) do
        for _, xy in ipairs({ { c.x, c.y }, { c.ox, c.oy } }) do
            local sq = cell:getGridSquare(xy[1], xy[2], c.z)
            local car = nil
            if sq ~= nil then pcall(function() car = sq:getVehicleContainer() end) end
            if car ~= nil then return true end
        end
    end
    return false
end


function BridgeMove.toggleDoor(body, door, kind)
    kind = kind or doorKind(door)
    local wasOpen = door:IsOpen()
    local byGame = false
    if kind == "double" then
        local blocked = true
        pcall(function() blocked = IsoDoor.isDoubleDoorObstructed(door) end)
        if blocked then return false end
        IsoDoor.toggleDoubleDoor(door, true)
    elseif kind == "garage" then
        if wasOpen and carInDoorway(doorCells(door, kind)) then return false end
        IsoDoor.toggleGarageDoor(door, true)
    else









        local actor = BridgeData.owner()
        if actor ~= nil then
            pcall(function() door:ToggleDoor(actor) end)
            byGame = door:IsOpen() ~= wasOpen
        end
        if not byGame then
            local square = door:getSquare()
            door:DirtySlice()
            IsoGridSquare.RecalcLightTime = -1.0
            square:InvalidateSpecialObjectPaths()
            door:ToggleDoorSilent()
            square:RecalcProperties()
            pcall(function() door:syncIsoObject(false, 1, nil, nil) end)
            pcall(function() LuaEventManager.triggerEvent("OnContainerUpdate") end)
            pcall(function() door:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY) end)
        end
    end
    local open = door:IsOpen()
    if open == wasOpen then return false end
    if byGame then return true end

    local prefix = "WoodDoor"
    pcall(function() prefix = door:getSoundPrefix() or "WoodDoor" end)
    pcall(function() body:playSound(prefix .. (open and "Open" or "Close")) end)
    return true
end




BridgeMove.opened = {}
BridgeMove.doorLast = "none"
local DOOR_FORGET = 1800
local DOOR_BACK = 180




local DOOR_PASSED = 0.5
local DOOR_EDGE = 0.4
local DOOR_REACH = 2.0
local DOOR_BACK_OFF = 1.2
local OWN_BEHIND = 4.0
local OWN_AT_DOOR = 3.0


local function doorSide(rec, x, y)
    local v = rec.north and y or x
    return (v < rec.edge) and -1 or 1, math.abs(v - rec.edge)
end

function BridgeMove.rememberDoor(body, door, kind, cells, north)
    if #cells == 0 then return end
    local rec = { door = door, kind = kind, cells = cells, north = north, tick = Bridge.time }
    rec.edge = north and cells[1].y or cells[1].x
    rec.side = doorSide(rec, body:getX(), body:getY())

    local sx, sy = 0, 0
    for _, c in ipairs(cells) do sx, sy = sx + c.x + 0.5, sy + c.y + 0.5 end
    rec.cx, rec.cy = sx / #cells, sy / #cells
    if north then rec.cy = rec.edge else rec.cx = rec.edge end
    local list = BridgeMove.opened
    for i = #list, 1, -1 do
        if list[i].door == door then table.remove(list, i) end
    end
    list[#list + 1] = rec
    if #list > 4 then table.remove(list, 1) end
    log(sformat("door opened: %s at %d,%d, %d parts", kind, cells[1].x, cells[1].y, #cells))
end


local function doorReach(rec, x, y)
    local best = math.huge
    for _, c in ipairs(rec.cells) do
        best = math.min(best, dist2d(x, y, c.x + 0.5, c.y + 0.5), dist2d(x, y, c.ox + 0.5, c.oy + 0.5))
    end
    return best
end








local function ownNear(rec, body, side, radius)
    local cell = getCell()
    local mark = (Bridge ~= nil and Bridge.BODY_VAR) or "NotAloneBody"
    local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
    for _, c in ipairs(rec.cells) do
        minx, maxx = math.min(minx, c.x, c.ox), math.max(maxx, c.x, c.ox)
        miny, maxy = math.min(miny, c.y, c.oy), math.max(maxy, c.y, c.oy)
    end
    local r = math.ceil(radius)
    local z = rec.cells[1].z
    for x = minx - r, maxx + r do
        for y = miny - r, maxy + r do
            local sq = cell:getGridSquare(x, y, z)
            local who = nil
            if sq ~= nil then
                pcall(function()
                    local list = sq:getMovingObjects()
                    for i = 0, list:size() - 1 do
                        local o = list:get(i)
                        local kind = nil
                        if o ~= body then
                            if instanceof(o, "IsoAnimal") then
                                kind = nil
                            elseif instanceof(o, "IsoPlayer") then
                                if not o:isDead() then kind = "player" end
                            elseif instanceof(o, "IsoZombie") and o:getVariableBoolean(mark) then
                                kind = "companion"
                            end
                        end
                        if kind ~= nil then
                            local ox, oy = o:getX(), o:getY()
                            if (side == nil or doorSide(rec, ox, oy) == side) and doorReach(rec, ox, oy) <= radius then
                                who = kind
                            end
                        end
                    end
                end)
            end
            if who ~= nil then return who end
        end
    end
    return nil
end



local function doorwayBusy(rec, body)
    local cell = getCell()
    for _, c in ipairs(rec.cells) do
        for _, xy in ipairs({ { c.x, c.y }, { c.ox, c.oy } }) do
            local sq = cell:getGridSquare(xy[1], xy[2], c.z)
            local busy = false
            if sq ~= nil then
                pcall(function()
                    local list = sq:getMovingObjects()
                    for i = 0, list:size() - 1 do
                        local o = list:get(i)
                        if o ~= body then
                            local _, off = doorSide(rec, o:getX(), o:getY())
                            if off < DOOR_EDGE then busy = true end
                        end
                    end
                end)
            end
            if busy then return true end
        end
    end
    return false
end













local function closeWait(rec, body, passed)
    local red = BridgeData.owner()
    local wait = nil
    if red ~= nil and math.abs(red:getZ() - rec.cells[1].z) < 0.5 then
        local rside = doorSide(rec, red:getX(), red:getY())
        local rd = dist2d(red:getX(), red:getY(), rec.cx, rec.cy)
        if passed and rside == rec.side and rd < 4 then
            wait = "player behind"
        elseif not passed and rd < 3 then
            wait = "player at door"
        end
    end
    if wait == nil then
        local who = nil
        if passed then
            who = ownNear(rec, body, rec.side, OWN_BEHIND)
            if who ~= nil then wait = who .. " behind" end
        else
            who = ownNear(rec, body, nil, OWN_AT_DOOR)
            if who ~= nil then wait = who .. " at door" end
        end
    end
    if wait == nil and doorwayBusy(rec, body) then wait = "doorway busy" end
    return wait
end

function BridgeMove.closeBehind(body)
    local list = BridgeMove.opened
    if #list == 0 then return end
    local bx, by, bz = body:getX(), body:getY(), body:getZ()
    for i = #list, 1, -1 do
        local rec = list[i]
        local why = nil
        local open = false
        pcall(function() open = rec.door:getObjectIndex() ~= -1 and rec.door:IsOpen() end)
        if not open then
            why = "closed by someone else"
        elseif Bridge.time - rec.tick > DOOR_FORGET then
            why = "left open: timeout"
        elseif math.abs(bz - rec.cells[1].z) >= 0.5 then
            why = "left open: other floor"
        elseif doorReach(rec, bx, by) > DOOR_REACH then
            why = "left open: walked away"
        else
            local side, off = doorSide(rec, bx, by)
            local passed = side ~= rec.side and off >= DOOR_PASSED
            local back = side == rec.side and off >= DOOR_BACK_OFF and (Bridge.time - rec.tick) >= DOOR_BACK
            if (passed or back) and BridgeMove.doorAct == nil and Bridge.time >= (rec.retryAt or 0) then
                local wait = closeWait(rec, body, passed)
                if wait ~= nil then
                    if wait ~= rec.wait then log("door close waits: " .. wait) end
                    rec.wait = wait
                else

                    BridgeMove.startDoorAct(body, "close", rec.door, rec, rec.cx, rec.cy, passed)
                end
            end
        end
        if why ~= nil then
            table.remove(list, i)
            BridgeMove.doorLast = sformat("%s: %s at %d,%d", why, rec.kind, rec.cells[1].x, rec.cells[1].y)
            log("door " .. BridgeMove.doorLast)
        end
    end
end




function BridgeMove.closeNow(body, rec, passed)
    local list = BridgeMove.opened
    local idx = nil
    for i, r in ipairs(list) do if r == rec then idx = i end end
    if idx == nil then return nil end
    local why = nil
    local open = false
    pcall(function() open = rec.door:getObjectIndex() ~= -1 and rec.door:IsOpen() end)
    if not open then
        why = "closed by someone else"
    else
        local wait = closeWait(rec, body, passed)
        if wait ~= nil then
            if wait ~= rec.wait then log("door close waits: " .. wait) end
            rec.wait = wait
            return wait
        end
        local ok, done = pcall(function()
            if rec.kind == "single" and rec.door:isObstructed() then return false end
            return BridgeMove.toggleDoor(body, rec.door, rec.kind)
        end)
        if ok and done then
            why = passed and "closed behind" or "closed, did not go through"
        else
            why = "left open: " .. (ok and "blocked" or tostring(done))
        end
    end
    table.remove(list, idx)
    BridgeMove.doorLast = sformat("%s: %s at %d,%d", why, rec.kind, rec.cells[1].x, rec.cells[1].y)
    log("door " .. BridgeMove.doorLast)
    return nil
end





function BridgeMove.doorsNear(red, radius, only)
    local cell = getCell()
    local rx, ry, rz = math.floor(red:getX()), math.floor(red:getY()), math.floor(red:getZ())
    local seen, found = {}, {}
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(rx + dx, ry + dy, rz)
            if sq ~= nil then
                local objects = sq:getObjects()
                for i = 0, objects:size() - 1 do
                    local o = objects:get(i)
                    if isDoor(o) and not seen[o] then
                        local kind = doorKind(o)
                        local parts = doorParts(o, kind)
                        local open = 0
                        for _, p in ipairs(parts) do
                            seen[p] = true
                            if p:IsOpen() then open = open + 1 end
                        end
                        local psq = parts[1]:getSquare() or sq
                        local north, gate, locked = false, false, false
                        pcall(function() north = o:getNorth() end)
                        pcall(function() gate = o:isHoppable() end)
                        pcall(function() locked = o:isLocked() or o:isLockedByKey() end)
                        local wanted = only == nil or only == kind or (only == "gate" and gate)
                        if wanted then found[#found + 1] = {
                            d = dist2d(rx, ry, psq:getX(), psq:getY()),
                            text = sformat("%s %d,%d %s %d/%d open%s%s", kind, psq:getX(), psq:getY(),
                                north and "N" or "W", open, #parts, gate and " gate" or "", locked and " locked" or ""),
                        } end
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.d < b.d end)
    local out = {}
    for i = 1, math.min(15, #found) do out[#out + 1] = found[i].text end
    return sformat("doors %d: %s", #found, table.concat(out, "; "))
end



function BridgeMove.doorInfo()
    local list = BridgeMove.opened
    local last = list[#list]
    return sformat("open=%d wait=%s last=%s", #list, last and tostring(last.wait) or "none", BridgeMove.doorLast)
end



local function usableDoor(object)
    local ok = false
    pcall(function()
        if object:isBarricaded() or object:isObstructed() then return end
        if object:IsOpen() then ok = true return end
        local locked = false
        pcall(function() locked = object:isLocked() or object:isLockedByKey() end)
        ok = not locked
    end)
    return ok
end

local function buildingOf(square)
    local b = nil
    pcall(function() b = square:getBuilding() end)
    return b
end


local function edgeSquares(object)
    local sq = object:getSquare()
    local other = nil
    pcall(function()
        local north = object:getNorth()
        other = getCell():getGridSquare(sq:getX() - (north and 0 or 1), sq:getY() - (north and 1 or 0), sq:getZ())
    end)
    return sq, other
end







BridgeMove.doorWay = nil
BridgeMove.noDoorUntil = 0
function BridgeMove.viaDoor(body, gx, gy, gz)
    if Bridge.time < BridgeMove.noDoorUntil then return nil end
    local bsq = body:getCurrentSquare()
    local cell = getCell()
    local tsq = cell:getGridSquare(math.floor(gx), math.floor(gy), math.floor(gz))
    if bsq == nil or tsq == nil or math.floor(body:getZ()) ~= math.floor(gz) then
        BridgeMove.doorWay = nil
        return nil
    end
    local bb, tb = buildingOf(bsq), buildingOf(tsq)
    if bb == tb then
        BridgeMove.doorWay = nil
        return nil
    end
    local way = BridgeMove.doorWay
    if way ~= nil then
        local d = dist2d(body:getX(), body:getY(), way.x, way.y)
        if d < way.best - 0.3 then way.best, way.bestAt = d, Bridge.time end
        if d <= 0.7 then

            way.reached = true
            return nil
        end
        if way.reached then

            if d > 3 then
                BridgeMove.doorWay = nil
                BridgeMove.noDoorUntil = Bridge.time + 600
            end
            return nil
        end

        if BridgeMove.walkType == "Run"
            and d + dist2d(way.x, way.y, gx, gy) > dist2d(body:getX(), body:getY(), gx, gy) + 3 then
            BridgeMove.doorWay = nil
            return nil
        end
        if Bridge.time - way.bestAt > 180 then
            log("door waypoint: no progress, going direct")
            BridgeMove.doorWay = nil
            BridgeMove.noDoorUntil = Bridge.time + 1800
            return nil
        end
        return way.x, way.y, way.z
    end
    local house = bb or tb
    local bx, by, bz = math.floor(body:getX()), math.floor(body:getY()), math.floor(body:getZ())


    local doorDetour = (BridgeMove.walkType == "Run") and 3 or 8
    local direct = dist2d(body:getX(), body:getY(), gx, gy)
    local best, bestCost = nil, math.huge
    for dx = -10, 10 do
        for dy = -10, 10 do
            local sq = cell:getGridSquare(bx + dx, by + dy, bz)
            if sq ~= nil then
                local objects = sq:getObjects()
                for i = 0, objects:size() - 1 do
                    local o = objects:get(i)
                    if isDoor(o) and usableDoor(o) then
                        local a, c = edgeSquares(o)
                        local ab, cb = buildingOf(a), c and buildingOf(c)
                        if c ~= nil and (ab == house or cb == house) and ab ~= cb then

                            local near = (ab == bb) and a or c
                            local nx, ny = near:getX() + 0.5, near:getY() + 0.5
                            local cost = dist2d(body:getX(), body:getY(), nx, ny) + dist2d(nx, ny, gx, gy)
                            if cost < bestCost and cost <= direct + doorDetour then
                                best, bestCost = { x = nx, y = ny, z = bz }, cost
                            end
                        end
                    end
                end
            end
        end
    end
    if best == nil then return nil end
    best.best = math.huge
    best.bestAt = Bridge.time
    BridgeMove.doorWay = best
    return best.x, best.y, best.z
end





BridgeMove.pendingClimb = nil

local function cardinal(body)
    local a = body:getDirectionAngle()
    if a >= -45 and a < 45 then return IsoDirections.E end
    if a >= 45 and a < 135 then return IsoDirections.S end
    if a >= -135 and a < -45 then return IsoDirections.N end
    return IsoDirections.W
end

function BridgeMove.askClimb(body, kind, object)
    BridgeMove.pendingClimb = { kind = kind, object = object, tick = Bridge.time, asked = -9999 }
    if kind == "fence" then pcall(function() BridgeMove.pendingClimb.dir = cardinal(body) end) end
    BridgeMove.climbUntil = Bridge.time + 60
end


function BridgeMove.climbStep(body)
    local c = BridgeMove.pendingClimb
    if c == nil then return false end
    local asn = ""
    pcall(function() asn = tostring(body:getActionStateName()) end)
    if asn == "climbwindow" or asn == "climbfence" then
        BridgeMove.pendingClimb = nil
        BridgeMove.climbUntil = Bridge.time + 150
        return true
    end
    if Bridge.time - c.tick > 45 then
        BridgeMove.pendingClimb = nil
        BridgeMove.climbUntil = 0
        BridgeMove.obstacle = "climb not started: " .. asn
        return false
    end
    if asn == "idle" or asn == "pathfind" then


        if isClient() and body:getPrimaryHandItem() ~= nil then
            local ok = false
            pcall(function() ok = BridgeWeapon.putAway(body) end)
            if not ok and body:getPrimaryHandItem() ~= nil then
                BridgeMove.pendingClimb = nil
                BridgeMove.climbUntil = 0
                BridgeMove.obstacle = "climb skipped: item in hands"
                return false
            end
        end
        if Bridge.time - c.asked >= 5 then
            c.asked = Bridge.time
            local ok, err = pcall(function()
                if c.kind == "window" then
                    body:climbThroughWindow(c.object)
                elseif c.kind == "frame" then
                    body:climbThroughWindowFrame(c.object)
                else
                    body:climbOverFence(c.dir)
                end
            end)
            if not ok then
                BridgeMove.pendingClimb = nil
                BridgeMove.climbUntil = 0
                BridgeMove.obstacle = "climb failed: " .. tostring(err)
                return false
            end
        end
        return true
    end

    if BridgeMove.onPath() then BridgeMove.stopPath(body) end
    pcall(function()
        if asn == "bumped" then body:setVariable("BumpAnimFinished", true) end
        body:setBumpType("")
    end)
    return true
end

















BridgeMove.cross = nil
BridgeMove.noCrossUntil = 0
BridgeMove.crossInfo = "none"

local CROSS_LOOK = 0.9
local CROSS_CALL = 0.55
local CROSS_WAIT = 90
local TALL_GRAB_MS = 640
local TALL_OVER_MS = 1830

local function nowMs()
    local ms = nil
    pcall(function() ms = getTimestampMs() end)
    return ms or (Bridge.time * 1000 / 60)
end

local function sameSquare(a, b)
    return a ~= nil and b ~= nil and a:getX() == b:getX() and a:getY() == b:getY() and a:getZ() == b:getZ()
end

local function stepDir(a, b)
    if b:getX() > a:getX() then return IsoDirections.E end
    if b:getX() < a:getX() then return IsoDirections.W end
    if b:getY() > a:getY() then return IsoDirections.S end
    return IsoDirections.N
end


local function edgeDist(body, a, b)
    local x, y = body:getX(), body:getY()
    if b:getX() > a:getX() then return (a:getX() + 1) - x end
    if b:getX() < a:getX() then return x - a:getX() end
    if b:getY() > a:getY() then return (a:getY() + 1) - y end
    return y - a:getY()
end


local function beyondEdge(a, b, x, y, margin)
    if x == nil or y == nil then return false end
    local m = margin or 0
    if b:getX() > a:getX() then return x >= a:getX() + 1 + m end
    if b:getX() < a:getX() then return x < a:getX() - m end
    if b:getY() > a:getY() then return y >= a:getY() + 1 + m end
    return y < a:getY() - m
end
BridgeMove.beyondEdge = beyondEdge




local CROSS_MARGIN = 0.3









local BACK_BLOCK = 120
local BACK_SPAN = 2
BridgeMove.lastCross = nil



local function lineOf(from, to)
    if from:getX() ~= to:getX() then
        return "x", math.max(from:getX(), to:getX()), from:getY(), (to:getX() > from:getX()) and 1 or -1
    end
    return "y", math.max(from:getY(), to:getY()), from:getX(), (to:getY() > from:getY()) and 1 or -1
end



local function sideOf(axis, edge, x, y, margin)
    local v = (axis == "x") and x or y
    if v >= edge + margin then return 1 end
    if v < edge - margin then return -1 end
    return 0
end



local function backBlocked(from, to)
    local lc = BridgeMove.lastCross
    if lc == nil or Bridge.time - lc.tick >= BACK_BLOCK then return nil end
    local axis, edge, along, dir = lineOf(from, to)
    if axis ~= lc.axis or edge ~= lc.edge or dir ~= -lc.dir or math.abs(along - lc.along) > BACK_SPAN then return nil end
    local red = BridgeData.owner()
    local now = 0
    if red ~= nil then now = sideOf(axis, edge, red:getX(), red:getY(), CROSS_MARGIN) end
    if lc.redSide == lc.dir and now == dir then return nil end
    return sformat("crossed here %d ticks ago, player side %d then, %d now", Bridge.time - lc.tick, lc.redSide, now)
end
BridgeMove.backBlocked = backBlocked






function BridgeMove.edgeBetween(body, a, b)
    if a == nil or b == nil or a:getZ() ~= b:getZ() then return nil end
    local w = nil
    pcall(function() w = a:getWindowTo(b) end)
    if w ~= nil then
        local ok = false
        pcall(function() ok = not w:isBarricaded() and (w:IsOpen() or w:isSmashed()) and w:canClimbThrough(body) end)
        if ok then return "window", w end
        return nil
    end
    local f = nil
    pcall(function() f = a:getWindowFrameTo(b) end)
    if f ~= nil then
        local ok = false
        pcall(function() ok = f:canClimbThrough(body) end)
        if ok then return "frame", f end
        return nil
    end


    local door = nil
    pcall(function() door = a:getDoorTo(b) end)
    if door ~= nil then
        local barricaded = false
        pcall(function() barricaded = door:isBarricaded() end)
        if not barricaded then return nil end
    end
    local low = false
    pcall(function() low = a:isHoppableTo(b) end)
    if low then return "fence", nil end

    local owner, north
    if a:getX() ~= b:getX() then
        owner, north = (a:getX() > b:getX()) and a or b, false
    else
        owner, north = (a:getY() > b:getY()) and a or b, true
    end
    local tall = nil
    pcall(function()
        local objects = owner:getObjects()
        for i = 0, objects:size() - 1 do
            local o = objects:get(i)
            if o ~= nil and o:isTallHoppable() then
                local props = o:getProperties()
                local n = props:has(IsoFlagType.TallHoppableN)
                local wf = props:has(IsoFlagType.TallHoppableW)
                if (north and n) or (not north and wf) then tall = o break end
            end
        end
    end)
    if tall ~= nil then return "tall", tall end
    return nil
end



local function farSideJoined(body, to, sb)
    local dx, dy = sb:getX() - to:getX(), sb:getY() - to:getY()
    if (dx ~= 0 and dy ~= 0) or sb:getZ() ~= to:getZ() then return false end
    local ux = (dx > 0 and 1) or (dx < 0 and -1) or 0
    local uy = (dy > 0 and 1) or (dy < 0 and -1) or 0
    local cell = getCell()
    local prev = to
    for k = 1, math.abs(dx) + math.abs(dy) do
        local nxt = cell:getGridSquare(to:getX() + ux * k, to:getY() + uy * k, to:getZ())
        if nxt == nil then return false end
        local open = false
        pcall(function() open = not prev:isBlockedTo(nxt) and BridgeMove.edgeBetween(body, prev, nxt) == nil end)
        if not open then return false end
        prev = nxt
    end
    return true
end













function BridgeMove.trailCrosses(body, from, to)
    local t = BridgeMove.trail
    local fx, fy, tx, ty = from:getX(), from:getY(), to:getX(), to:getY()
    local z = from:getZ()
    local byY = (fx == tx)
    local edge = byY and math.max(fy, ty) or math.max(fx, tx)
    local toSide = byY and ((ty > fy) and 1 or -1) or ((tx > fx) and 1 or -1)
    local along = byY and fx or fy
    local cell = getCell()
    for i = #t, math.max(2, #t - 40), -1 do
        local a, b = t[i - 1], t[i]
        local av, bv = byY and a.y or a.x, byY and b.y or b.x
        local aSide = (av < edge) and -1 or 1
        local bSide = (bv < edge) and -1 or 1
        if aSide ~= toSide and bSide == toSide and bv ~= av then
            local k = (edge - av) / (bv - av)
            local c = math.floor(byY and (a.x + (b.x - a.x) * k) or (a.y + (b.y - a.y) * k))
            local off = math.abs(c - along)
            if off <= 8 then
                local sa, sb
                if byY then
                    sa, sb = cell:getGridSquare(c, fy, z), cell:getGridSquare(c, ty, z)
                else
                    sa, sb = cell:getGridSquare(fx, c, z), cell:getGridSquare(tx, c, z)
                end
                local over = false
                pcall(function() over = sa ~= nil and sb ~= nil and BridgeMove.edgeBetween(body, sa, sb) ~= nil end)
                if not over then
                    if off == 0 then return false, "player went through a passage here" end
                    return false, sformat("player went through a passage %d away", off)
                end
                if off == 0 then return true, "player crossed here" end
                if farSideJoined(body, to, sb) then return true, sformat("player climbed %d away", off) end
                return false, sformat("player climbed %d away, other side not joined", off)
            end
        end
    end
    return false, "player did not cross near"
end





BridgeMove.passWhy = ""
function BridgeMove.passNear(body, from, to, radius)
    local cell = getCell()
    local z = from:getZ()
    local ux, uy = 0, 0
    if from:getX() == to:getX() then ux = 1 else uy = 1 end
    local why = {}
    for _, dir in ipairs({ 1, -1 }) do
        local prev = from
        local stop = "radius"
        for k = 1, radius do
            local a = cell:getGridSquare(from:getX() + ux * dir * k, from:getY() + uy * dir * k, z)
            local b = cell:getGridSquare(to:getX() + ux * dir * k, to:getY() + uy * dir * k, z)
            if a == nil or b == nil then stop = "no square at " .. k break end
            local walk, how = false, "?"
            pcall(function()
                if prev:isBlockedTo(a) then how = "wall"
                elseif BridgeMove.edgeBetween(body, prev, a) ~= nil then how = "fence"
                elseif not a:isFree(false) then how = "busy"
                else walk = true end
            end)
            if not walk then stop = how .. " at " .. k break end
            local pass = false
            pcall(function()
                local door = a:getDoorTo(b)
                if door ~= nil then
                    pass = usableDoor(door)
                else
                    pass = not a:isBlockedTo(b) and BridgeMove.edgeBetween(body, a, b) == nil and b:isFree(false)
                end
            end)
            if pass then return a, b end
            prev = a
        end
        why[#why + 1] = (dir == 1 and "+" or "-") .. stop
    end
    BridgeMove.passWhy = table.concat(why, " ")
    return nil
end








local CLIMB_SEC = { tall = 2.6, fence = 2.0, window = 2.0, frame = 2.0 }
local function climbCost(kind)
    local speed = (BridgeMove.walkType == "Run") and 4.2 or 2.2
    return (CLIMB_SEC[kind] or 1.5) * speed
end




local function squareFloor(sq)
    if sq == nil then return nil end
    local known = nil
    pcall(function() known = sq:TreatAsSolidFloor() end)
    if known == nil then pcall(function() known = sq:hasFloor() end) end
    return known
end


function BridgeMove.vaultSafe(body, from, to)
    if from == nil or to == nil then return true end
    local offStairs = false
    pcall(function()
        if from.HasStairs ~= nil and from:HasStairs() and to.isSameStaircase ~= nil then
            offStairs = not from:isSameStaircase(to:getX(), to:getY(), to:getZ())
        end
    end)
    if offStairs then return false, "vaults off the staircase" end
    if math.floor(from:getZ()) <= 0 then return true end
    if squareFloor(to) ~= true then return false, "far side is open air" end
    return true
end












function BridgeMove.shouldCross(body, kind, from, to)
    local safe, blockedWhy = BridgeMove.vaultSafe(body, from, to)
    if not safe then return false, blockedWhy end
    if BridgeMove.steering then
        local yes, why = BridgeMove.trailCrosses(body, from, to)
        return yes, why
    end
    local g = BridgeMove.goal
    if g == nil then return true, "no goal" end
    local bx, by = body:getX(), body:getY()
    local ex = (from:getX() + to:getX()) / 2 + 0.5
    local ey = (from:getY() + to:getY()) / 2 + 0.5
    local over = dist2d(bx, by, ex, ey) + dist2d(ex, ey, g.x, g.y) + climbCost(kind)

    local radius = math.max(1, math.floor(climbCost(kind) / 2) + 1)
    local a, b = BridgeMove.passNear(body, from, to, radius)
    if a ~= nil then
        local around = dist2d(bx, by, a:getX() + 0.5, a:getY() + 0.5) + 1 + dist2d(b:getX() + 0.5, b:getY() + 0.5, g.x, g.y)
        if around <= over then
            return false, sformat("pass near %.1f <= climb %.1f", around, over), a, b
        end
        return true, sformat("climb %.1f < pass %.1f", over, around)
    end
    return true, "no pass near: " .. tostring(BridgeMove.passWhy)
end




BridgeMove.gapWay = nil
BridgeMove.noGapUntil = 0
function BridgeMove.setGapWay(a, b)
    BridgeMove.gapWay = { ax = a:getX() + 0.5, ay = a:getY() + 0.5, bx = b:getX() + 0.5, by = b:getY() + 0.5,
        z = a:getZ(), stage = 1, best = math.huge, bestAt = Bridge.time, tick = Bridge.tick }
    log(sformat("pass instead of climbing: via %d,%d > %d,%d", a:getX(), a:getY(), b:getX(), b:getY()))
end


function BridgeMove.gapGoal(body)
    local g = BridgeMove.gapWay
    if g == nil then return nil end
    if math.abs(body:getZ() - g.z) >= 0.5 then BridgeMove.gapWay = nil return nil end
    local tx, ty = g.ax, g.ay
    if g.stage == 2 then tx, ty = g.bx, g.by end
    local d = dist2d(body:getX(), body:getY(), tx, ty)
    if d < g.best - 0.2 then g.best, g.bestAt = d, Bridge.time end
    if d <= 0.5 then
        if g.stage == 1 then
            g.stage, g.best, g.bestAt = 2, math.huge, Bridge.time
            return g.bx, g.by, g.z
        end
        BridgeMove.gapWay = nil
        log("pass done")
        return nil
    end
    if Bridge.time - g.bestAt > 180 then
        BridgeMove.gapWay = nil
        BridgeMove.noGapUntil = Bridge.time + 600
        log("pass: no progress, climbing")
        return nil
    end
    return tx, ty, g.z
end


local function edgeAhead(body)
    local cur = body:getCurrentSquare()
    if cur == nil then return nil end
    local x, y = body:getX(), body:getY()
    local dx, dy = 0, 0
    local prev = BridgeMove.stepPos
    if prev ~= nil then dx, dy = x - prev.x, y - prev.y end
    if dx * dx + dy * dy < 0.00005 and BridgeMove.goal ~= nil then
        dx, dy = BridgeMove.goal.x - x, BridgeMove.goal.y - y
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.0001 then return nil end
    dx, dy = dx / len, dy / len
    local cell = getCell()
    for _, s in ipairs({ 0.35, 0.65, CROSS_LOOK }) do
        local nx, ny = math.floor(x + dx * s), math.floor(y + dy * s)
        if nx ~= cur:getX() or ny ~= cur:getY() then
            local candidates = {}
            if nx ~= cur:getX() and ny ~= cur:getY() then
                candidates = { cell:getGridSquare(nx, cur:getY(), cur:getZ()), cell:getGridSquare(cur:getX(), ny, cur:getZ()) }
            else
                candidates = { cell:getGridSquare(nx, ny, cur:getZ()) }
            end
            for _, b in ipairs(candidates) do
                if b ~= nil then
                    local kind, object = BridgeMove.edgeBetween(body, cur, b)
                    if kind ~= nil then return kind, object, cur, b end
                end
            end
            return nil
        end
    end
    return nil
end

local function crossEnd(body, why)
    local c = BridgeMove.cross
    BridgeMove.cross = nil
    BridgeMove.crossInfo = tostring(why)
    pcall(function() body:setVariable("bPathfind", false) end)
    if c ~= nil and c.kind == "tall" then
        pcall(function()
            local bump = body:getBumpType()
            if bump == "ClimbFenceTall" or bump == "ClimbFenceTallStart" then

                BridgeMove.releaseBump(body)
            end
        end)
    end


    BridgeMove.pathing = false
    BridgeMove.goal = nil
    BridgeMove.climbUntil = Bridge.time + 20
    BridgeMove.unPathfindUntil = Bridge.time + 30
    if why == "done" then



        BridgeMove.noCrossUntil = 0
        if c ~= nil and c.from ~= nil and c.to ~= nil then
            local axis, edge, along, dir = lineOf(c.from, c.to)
            local redSide = c.redSide
            if redSide == nil then
                local red = BridgeData.owner()
                redSide = red ~= nil and sideOf(axis, edge, red:getX(), red:getY(), CROSS_MARGIN) or 0
            end
            BridgeMove.lastCross = { axis = axis, edge = edge, along = along, dir = dir, tick = Bridge.time, redSide = redSide }
        end
    elseif why == "left the edge" then


        BridgeMove.noCrossUntil = Bridge.time + 20
    else
        BridgeMove.noCrossUntil = Bridge.time + ((why == "goal on this side") and 20 or 90)
    end
    log("cross " .. tostring(c and c.kind) .. " ended: " .. tostring(why))
end
BridgeMove.crossEnd = crossEnd






local function shiftCross(body, c, cur)
    if cur == nil or c.from == nil or c.to == nil or cur:getZ() ~= c.from:getZ() then return false end
    local dx, dy = c.to:getX() - c.from:getX(), c.to:getY() - c.from:getY()
    local sx, sy = cur:getX() - c.from:getX(), cur:getY() - c.from:getY()
    if dx ~= 0 then
        if sx ~= 0 or math.abs(sy) ~= 1 then return false end
    elseif sy ~= 0 or math.abs(sx) ~= 1 then
        return false
    end
    local to = getCell():getGridSquare(cur:getX() + dx, cur:getY() + dy, cur:getZ())
    if to == nil then return false end
    local kind, object = BridgeMove.edgeBetween(body, cur, to)
    if kind == nil or (kind == "tall") ~= (c.kind == "tall") then return false end
    if not BridgeMove.vaultSafe(body, cur, to) then return false end
    if not farSideJoined(body, c.to, to) then return false end
    log(sformat("cross %s shifted: from %d,%d to %d,%d", kind, cur:getX(), cur:getY(), to:getX(), to:getY()))
    c.from, c.to, c.kind, c.object = cur, to, kind, object
    pcall(function() c.dir = stepDir(cur, to) end)
    return true
end
BridgeMove.shiftCross = shiftCross

local function inPathFindState(body)
    local yes = false
    pcall(function() yes = body:isCurrentState(PathFindState.instance()) end)
    if yes then return true end
    local s = ""
    pcall(function() s = tostring(body:getCurrentState()) end)
    return string.find(s, "PathFindState", 1, true) ~= nil
end


function BridgeMove.crossStep(body)
    local c = BridgeMove.cross

    if c ~= nil and not c.started and Bridge.time - (c.lastFrame or c.tick) > 10 then
        crossEnd(body, "stale")
        c = nil
    end
    if c == nil then



        if not (BridgeMove.pathing or BridgeMove.steering) then
            BridgeMove.edgeSeen = nil
            return false
        end
        local kind, object, from, to = edgeAhead(body)
        if kind == nil then
            BridgeMove.edgeSeen = nil
            return false
        end
        local key = kind .. from:getX() .. "," .. from:getY() .. ">" .. to:getX() .. "," .. to:getY()


        local seen = BridgeMove.edgeSeen
        if seen == nil or seen.key ~= key or Bridge.time - seen.last > 10 then
            seen = { key = key, first = Bridge.time }
            BridgeMove.edgeSeen = seen
        end
        seen.last = Bridge.time
        if Bridge.time < BridgeMove.noCrossUntil then
            if BridgeMove.edgeLogged ~= "wait" .. key then
                BridgeMove.edgeLogged = "wait" .. key
                log(sformat("edge %s ahead, not climbing %d ticks more after: %s", kind,
                    BridgeMove.noCrossUntil - Bridge.time, tostring(BridgeMove.crossInfo)))
            end
            return false
        end


        local goal = BridgeMove.goal
        if goal == nil or not beyondEdge(from, to, goal.x, goal.y, CROSS_MARGIN) then
            if BridgeMove.edgeLogged ~= key then
                BridgeMove.edgeLogged = key
                log("edge " .. kind .. " ahead, goal on this side")
            end
            return false
        end

        local back = backBlocked(from, to)
        if back ~= nil then
            if BridgeMove.edgeLogged ~= "back" .. key then
                BridgeMove.edgeLogged = "back" .. key
                log("edge " .. kind .. " ahead, not climbing back: " .. back)
            end
            return false
        end

        local go, why, pa, pb = BridgeMove.shouldCross(body, kind, from, to)
        if not go then
            if pa ~= nil and BridgeMove.gapWay == nil and Bridge.time >= BridgeMove.noGapUntil then
                BridgeMove.setGapWay(pa, pb)
            end

            local key = (string.match(why, "^[%a ]+") or why) .. kind .. from:getX() .. "," .. from:getY() .. ">" .. to:getX() .. "," .. to:getY()
            if BridgeMove.edgeLogged ~= key then
                BridgeMove.edgeLogged = key
                log("edge " .. kind .. " ahead, not climbing: " .. why)
            end
            return false
        end
        local red0 = BridgeData.owner()
        log(sformat("cross %s start: from %d,%d to %d,%d (%s, %s) player=%.1f,%.1f goal=%.1f,%.1f seen=%d", kind,
            from:getX(), from:getY(), to:getX(), to:getY(), BridgeMove.steering and "trail" or "path", tostring(why),
            red0 and red0:getX() or 0, red0 and red0:getY() or 0, goal.x, goal.y, Bridge.time - seen.first))
        c = { kind = kind, object = object, from = from, to = to, tick = Bridge.time, started = false }
        pcall(function() c.dir = stepDir(from, to) end)



        if red0 ~= nil then
            local axis, edge = lineOf(from, to)
            c.redSide = sideOf(axis, edge, red0:getX(), red0:getY(), CROSS_MARGIN)
        end
        BridgeMove.cross = c
        BridgeMove.crossInfo = "cross " .. kind
        Bridge.holdPos = nil
        pcall(function() body:setBumpType("") end)
        if kind == "tall" then
            c.waitEdge = true

        else
            pcall(function()
                body:setVariable("bPathfind", true)
                body:setVariable("bMoving", false)
            end)
        end
    end
    c.lastFrame = Bridge.time
    BridgeMove.climbUntil = Bridge.time + 30
    local asn = ""
    pcall(function() asn = tostring(body:getActionStateName()) end)

    if c.kind == "tall" then
        if c.waitEdge then


            if BridgeMove.steering then
                local dist = edgeDist(body, c.from, c.to)
                if dist > 1.6 then crossEnd(body, "left the edge") return false end
                if dist > 0.45 then
                    local ex = c.from:getX() + 0.5 + (c.to:getX() - c.from:getX()) * 0.5
                    local ey = c.from:getY() + 0.5 + (c.to:getY() - c.from:getY()) * 0.5


                    BridgeMove.setCollide(body, false)
                    BridgeMove.walkType = "Walk"
                    BridgeMove.followWs = 0.4
                    BridgeMove.applyAnimVars(body)
                    BridgeMove.followBump(body, "Walk")
                    BridgeMove.turnToward(body, ex, ey, 180)
                    if Bridge.time - c.tick > CROSS_WAIT then crossEnd(body, "tall fence not reached") return false end
                    return true
                end
                BridgeMove.steering = false
                BridgeMove.endFollowBump(body, "")
                BridgeMove.setCollide(body, true)



                local curT = body:getCurrentSquare()
                if not sameSquare(curT, c.from) and not sameSquare(curT, c.to) and not shiftCross(body, c, curT) then
                    crossEnd(body, "left the edge") return false
                end
            elseif not sameSquare(body:getCurrentSquare(), c.from) and not shiftCross(body, c, body:getCurrentSquare()) then
                crossEnd(body, "left the edge") return false
            end
            if edgeDist(body, c.from, c.to) > 0.45 then
                if Bridge.time - c.tick > CROSS_WAIT then crossEnd(body, "tall fence not reached") return false end
                return false
            end
            BridgeMove.steering = false
            c.waitEdge = false
            c.t0 = nowMs()
            local x, y = body:getX(), body:getY()
            local tx, ty = x, y
            if c.to:getX() > c.from:getX() then tx = c.to:getX() + 0.45
            elseif c.to:getX() < c.from:getX() then tx = c.to:getX() + 0.55
            elseif c.to:getY() > c.from:getY() then ty = c.to:getY() + 0.45
            else ty = c.to:getY() + 0.55 end
            c.x0, c.y0, c.x1, c.y1 = x, y, tx, ty
            if BridgeMove.onPath() then BridgeMove.stopPath(body) end
            pcall(function()
                body:setDir(c.dir)
                body:setVariable("BumpAnimFinished", false)
                body:setBumpType("ClimbFenceTallStart")
            end)

            pcall(function() BridgeSound.fence(body, "ClimbOverFenceHighStart", true) end)
            pcall(function() BridgeSound.voice(body, "JumpHigh", 30) end)
            c.phase = "grab"
            log("cross tall fence")
        end


        pcall(function() body:setCollidable(false) end)
        local elapsed = nowMs() - c.t0
        if c.phase == "grab" then

            local g = math.min(1, elapsed / TALL_GRAB_MS)
            pcall(function()
                local nx, ny = c.x0 + (c.x1 - c.x0) * 0.12 * g, c.y0 + (c.y1 - c.y0) * 0.12 * g
                body:setX(nx) body:setY(ny) body:setLastX(nx) body:setLastY(ny)
            end)
            if elapsed < TALL_GRAB_MS then return true end
            c.phase = "over"
            pcall(function() body:setBumpType("ClimbFenceTall") end)
            pcall(function() BridgeSound.fence(body, "ClimbOverFenceHighSuccess", true) end)
        end
        local t = math.min(1, (elapsed - TALL_GRAB_MS) / TALL_OVER_MS)
        local k = 0.12 + 0.88 * (t * t * (3 - 2 * t))
        pcall(function()
            local nx, ny = c.x0 + (c.x1 - c.x0) * k, c.y0 + (c.y1 - c.y0) * k
            body:setX(nx) body:setY(ny) body:setLastX(nx) body:setLastY(ny)
        end)
        if t >= 1 then crossEnd(body, "done") end
        return true
    end

    if c.started then

        crossEnd(body, "done")
        return true
    end
    if Bridge.time - c.tick > CROSS_WAIT then
        crossEnd(body, "not started in " .. asn)
        return true
    end
    local goal = BridgeMove.goal
    if goal ~= nil and not beyondEdge(c.from, c.to, goal.x, goal.y) then
        crossEnd(body, "goal on this side")
        return true
    end



    if BridgeMove.steering and c.kind ~= "tall" then
        local cur0 = body:getCurrentSquare()
        if not sameSquare(cur0, c.from) then
            if sameSquare(cur0, c.to) then crossEnd(body, "done") return true end
            if not shiftCross(body, c, cur0) then crossEnd(body, "left the edge") return true end
        end
        local ex = c.from:getX() + 0.5 + (c.to:getX() - c.from:getX()) * 0.5
        local ey = c.from:getY() + 0.5 + (c.to:getY() - c.from:getY()) * 0.5
        BridgeMove.walkType = "Walk"
        BridgeMove.followWs = 0.4
        BridgeMove.applyAnimVars(body)
        BridgeMove.followBump(body, "Walk")
        BridgeMove.turnToward(body, ex, ey, 180)
        if edgeDist(body, c.from, c.to) <= CROSS_CALL and Bridge.time - (c.asked or -99) >= 3 then
            c.asked = Bridge.time
            BridgeMove.steering = false
            BridgeMove.endFollowBump(body, "")
            BridgeMove.setCollide(body, true)




            if isClient() then
                pcall(function()
                    if body:getPrimaryHandItem() ~= nil then BridgeWeapon.putAway(body) end
                end)
            end
            local ok, err = pcall(function()
                if c.kind == "fence" then
                    body:climbOverFence(c.dir)
                elseif c.kind == "window" then
                    body:faceThisObject(c.object)
                    body:climbThroughWindow(c.object)
                else
                    body:faceThisObject(c.object)
                    body:climbThroughWindowFrame(c.object)
                end
            end)
            if not ok then crossEnd(body, "climb error: " .. tostring(err)) end
        end
        return true
    end
    if asn == "bumped" then
        pcall(function() body:setBumpType("") body:setVariable("BumpAnimFinished", true) end)



        BridgeMove.kickAt = nil
        return true
    end
    pcall(function()
        body:setVariable("bPathfind", true)
        if asn == "walktoward" then body:setVariable("bMoving", false) end
    end)
    if asn ~= "pathfind" then return true end

    if not inPathFindState(body) then
        pcall(function() body:getPathFindBehavior2():update() end)
    end
    local cur = body:getCurrentSquare()
    if not sameSquare(cur, c.from) then

        if sameSquare(cur, c.to) then crossEnd(body, "done") return true end
        if not shiftCross(body, c, cur) then crossEnd(body, "left the edge") return true end
    end


    if isClient() and c.kind ~= "fence"
        and (body:getPrimaryHandItem() ~= nil or body:getSecondaryHandItem() ~= nil) then
        pcall(function() BridgeWeapon.putAway(body) end)
        if body:getPrimaryHandItem() ~= nil or body:getSecondaryHandItem() ~= nil then
            crossEnd(body, "item in hands")
            return true
        end
    end
    if edgeDist(body, c.from, c.to) <= CROSS_CALL and Bridge.time - (c.asked or -99) >= 3 then
        c.asked = Bridge.time
        local ok, err = pcall(function()
            if c.kind == "fence" then
                body:climbOverFence(c.dir)
            elseif c.kind == "window" then
                body:faceThisObject(c.object)
                body:climbThroughWindow(c.object)
            else
                body:faceThisObject(c.object)
                body:climbThroughWindowFrame(c.object)
            end
        end)
        if not ok then crossEnd(body, "climb error: " .. tostring(err)) return true end
    end
    return true
end


local function redWentThrough(cells)
    local t = BridgeMove.trail
    for i = #t, math.max(2, #t - 40), -1 do
        local a, b = t[i], t[i - 1]
        local ax, ay, bx, by = math.floor(a.x), math.floor(a.y), math.floor(b.x), math.floor(b.y)
        for _, c in ipairs(cells) do
            if math.abs(a.z - c.z) < 0.5 and ((ax == c.x and ay == c.y and bx == c.ox and by == c.oy)
                or (ax == c.ox and ay == c.oy and bx == c.x and by == c.y)) then
                return true
            end
        end
    end
    return false
end






function BridgeMove.openDoor(body, object)
    if object:isBarricaded() then
        BridgeMove.obstacle = "door barricaded"
        BridgeMove.doorWay = nil
        BridgeMove.noDoorUntil = Bridge.time + 1800
        return false
    end
    local locked = false
    pcall(function() locked = object:isLocked() or object:isLockedByKey() end)
    local inRoom = false
    pcall(function() inRoom = body:getCurrentSquare():getRoom() ~= nil end)




    local behindRed = false
    if locked and not inRoom then
        pcall(function() behindRed = redWentThrough(doorCells(object, doorKind(object))) end)
        if behindRed then log("door locked, but player just went through it: opening") end
    end
    if (locked and not inRoom and not behindRed) or object:isObstructed() then
        BridgeMove.obstacle = "door locked"
        BridgeMove.doorWay = nil
        BridgeMove.noDoorUntil = Bridge.time + 1800
        return false
    end
    if not object:IsOpen() then
        local kind = doorKind(object)


        local cells, north = doorCells(object, kind)
        local anchor = doorAnchor(object, kind)



        if locked and instanceof(object, "IsoDoor") then
            pcall(function()
                object:setLocked(false)
                object:setLockedByKey(false)
            end)
        end
        if not BridgeMove.toggleDoor(body, object, kind) then
            BridgeMove.obstacle = "door blocked"
            BridgeMove.doorWay = nil
            BridgeMove.noDoorUntil = Bridge.time + 1800
            return false
        end
        BridgeMove.rememberDoor(body, anchor, kind, cells, north)
        BridgeMove.obstacle = "door opened"
    end
    return true
end





function BridgeMove.openAhead(body)


    local goal = BridgeMove.goal
    if goal == nil then return false end
    local cur = body:getCurrentSquare()
    if cur == nil then return false end
    local x, y = body:getX(), body:getY()
    local dx, dy = 0, 0
    local prev = BridgeMove.stepPos
    if prev ~= nil then dx, dy = x - prev.x, y - prev.y end

    if dx * dx + dy * dy < 0.00005 then dx, dy = goal.x - x, goal.y - y end
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.0001 then return false end
    dx, dy = dx / len, dy / len
    local cell = getCell()
    for _, s in ipairs({ 0.35, 0.65 }) do
        local nx, ny = math.floor(x + dx * s), math.floor(y + dy * s)
        if nx ~= cur:getX() or ny ~= cur:getY() then
            local candidates
            if nx ~= cur:getX() and ny ~= cur:getY() then
                candidates = { cell:getGridSquare(nx, cur:getY(), cur:getZ()), cell:getGridSquare(cur:getX(), ny, cur:getZ()) }
            else
                candidates = { cell:getGridSquare(nx, ny, cur:getZ()) }
            end
            for _, b in ipairs(candidates) do
                local door = nil
                if b ~= nil then pcall(function() door = cur:getDoorTo(b) end) end
                if door ~= nil and isDoor(door) and not door:IsOpen() and beyondEdge(cur, b, goal.x, goal.y) then

                    if not BridgeMove.doorOpenable(body, door) then return BridgeMove.openDoor(body, door) end
                    local fx = (cur:getX() + b:getX()) / 2 + 0.5
                    local fy = (cur:getY() + b:getY()) / 2 + 0.5
                    return BridgeMove.startDoorAct(body, "open", door, nil, fx, fy)
                end
            end
            return false
        end
    end
    return false
end




function BridgeMove.doorOpenable(body, object)
    local ok = true
    pcall(function()
        if object:isBarricaded() then ok = false return end
        local locked = false
        pcall(function() locked = object:isLocked() or object:isLockedByKey() end)
        local inRoom = false
        pcall(function() inRoom = body:getCurrentSquare():getRoom() ~= nil end)
        if (locked and not inRoom) or object:isObstructed() then ok = false return end
        if doorKind(object) == "double" then
            local blocked = true
            pcall(function() blocked = IsoDoor.isDoubleDoorObstructed(object) end)
            if blocked then ok = false end
        end
    end)
    return ok
end









BridgeMove.doorAct = nil


local DOOR_HAND = { open = 10, close = 4 }
local DOOR_HAND_BIG = { open = 16, close = 8 }
local DOOR_AFTER = { open = 6, close = 4 }
local DOOR_ACT_MAX = 150

function BridgeMove.startDoorAct(body, want, door, rec, fx, fy, passed)
    if BridgeMove.doorAct ~= nil or door == nil then return false end

    if BridgeFight ~= nil and BridgeFight.target ~= nil then return false end
    local kind = rec ~= nil and rec.kind or doorKind(door)
    BridgeMove.doorAct = { want = want, door = door, kind = kind, rec = rec, fx = fx, fy = fy,
        passed = passed, t0 = Bridge.time, lastFrame = Bridge.time }
    return true
end


function BridgeMove.doorStep(body)
    local a = BridgeMove.doorAct
    if a == nil then return false end

    if Bridge.time - a.lastFrame > 10 or Bridge.time - a.t0 > DOOR_ACT_MAX then
        BridgeMove.doorAct = nil
        return false
    end
    a.lastFrame = Bridge.time

    if BridgeMove.onPath() then BridgeMove.stopPath(body) end
    pcall(function()
        local bump = tostring(body:getBumpType())
        if bump ~= "Stand" then body:setBumpType("Stand") end
    end)
    pcall(function()
        if a.fx ~= nil then body:faceLocationF(a.fx, a.fy) else body:faceThisObject(a.door) end
    end)
    if a.doneAt == nil then
        local hand = ((a.kind == "double" or a.kind == "garage") and DOOR_HAND_BIG or DOOR_HAND)[a.want] or 10
        if Bridge.time - a.t0 < hand then return true end
        a.doneAt = Bridge.time
        if a.want == "open" then
            local ok = false
            pcall(function() ok = BridgeMove.openDoor(body, a.door) end)
            if not ok then
                BridgeMove.doorAct = nil
                return false
            end
            log(sformat("door opened by hand after %d ticks", a.doneAt - a.t0))
        else
            local wait = BridgeMove.closeNow(body, a.rec, a.passed)
            if wait ~= nil then


                if a.rec ~= nil then a.rec.retryAt = Bridge.time + 30 end
                BridgeMove.doorAct = nil
                return false
            end
        end
        return true
    end
    if Bridge.time - a.doneAt < (DOOR_AFTER[a.want] or 6) then return true end
    BridgeMove.doorAct = nil
    return false
end




local function passInstead(body, kind)
    if BridgeMove.gapWay ~= nil then return "active" end
    if Bridge.time < BridgeMove.noGapUntil then return nil end
    local found = nil
    pcall(function()
        local cur = body:getCurrentSquare()
        local dir = cardinal(body)
        local dx, dy = 0, 0
        if dir == IsoDirections.E then dx = 1 elseif dir == IsoDirections.W then dx = -1
        elseif dir == IsoDirections.S then dy = 1 else dy = -1 end
        local to = getCell():getGridSquare(cur:getX() + dx, cur:getY() + dy, cur:getZ())
        if to == nil then return end
        local go, why, a, b = BridgeMove.shouldCross(body, kind, cur, to)
        if not go then
            if a ~= nil then
                BridgeMove.setGapWay(a, b)
                found = "new"
            else
                found = "around"
            end
        end
    end)
    return found
end


function BridgeMove.handleObstacle(body)

    if BridgeMove.window then
        local w = BridgeMove.window
        body:faceLocationF(w.x, w.y)
        local square = getCell():getGridSquare(w.x, w.y, w.z)
        local window = square and square:getWindow()
        if window == nil or window:IsOpen() or window:isSmashed() or (Bridge.time - w.tick) > 40 then
            if window ~= nil and not window:IsOpen() and not window:isSmashed() then
                pcall(function() window:ToggleWindow(body) end)
                pcall(function() body:playSound("OpenWindow") end)
            end
            BridgeMove.window = nil
            BridgeMove.obstacle = "window opened"
            return false
        end
        return true
    end

    local collided = body:isCollidedWithDoor() or body:isCollidedThisFrame() or body:isCollided()
    if not collided then return false end

    local square = squareAhead(body)
    if square == nil then return false end

    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local properties = object and object:getProperties()
        if properties then




            local gate = isDoor(object)

            if not gate and (properties:get("FenceTypeLow") or object:isHoppable()) then
                if body:isFacingObject(object, 0.5) then
                    local pass = passInstead(body, "fence")
                    if pass ~= nil then
                        BridgeMove.obstacle = "low fence: " .. pass
                        return pass == "new"
                    end
                    BridgeMove.askClimb(body, "fence", object)
                    BridgeMove.obstacle = "low fence"
                else
                    body:faceThisObject(object)
                end
                return true
            end

            if not gate and (properties:get("FenceTypeHigh") or object:isTallHoppable()) then


                BridgeMove.obstacle = "tall fence"
                BridgeMove.noCrossUntil = 0
                return false
            end

            local frame = false
            pcall(function() frame = instanceof(object, "IsoWindowFrame") end)

            if frame and square:getWindow() == nil then
                local can = false
                pcall(function() can = object:canClimbThrough(body) end)
                if not can then
                    BridgeMove.obstacle = "window frame blocked"
                    return false
                end
                if body:isFacingObject(object, 0.5) then
                    local pass = passInstead(body, "frame")
                    if pass ~= nil then
                        BridgeMove.obstacle = "window frame: " .. pass
                        return pass == "new"
                    end
                    BridgeMove.askClimb(body, "frame", object)
                    BridgeMove.obstacle = "window frame climb"
                else
                    body:faceThisObject(object)
                end
                return true
            end
            if instanceof(object, "IsoWindow") then
                if body:isFacingObject(object, 0.5) then
                    if object:isBarricaded() then
                        BridgeMove.obstacle = "window barricaded"
                        return false
                    elseif passInstead(body, "window") ~= nil then
                        BridgeMove.obstacle = "window: going around"
                        return BridgeMove.gapWay ~= nil and BridgeMove.gapWay.tick == Bridge.tick
                    elseif not object:IsOpen() and not object:isSmashed() then
                        if not object:isPermaLocked() then
                            local sq = object:getSquare()
                            BridgeMove.window = { x = sq:getX(), y = sq:getY(), z = sq:getZ(), tick = Bridge.time }
                            body:setBumpType("WindowOpen")
                            BridgeMove.obstacle = "window opening"
                            return true
                        end
                        BridgeMove.obstacle = "window locked"
                        return false
                    elseif object:canClimbThrough(body) then
                        BridgeMove.askClimb(body, "window", object)
                        BridgeMove.obstacle = "window climb"
                        return true
                    end
                else
                    body:faceThisObject(object)
                    return true
                end
            end

            if instanceof(object, "IsoDoor") or (instanceof(object, "IsoThumpable") and object:isDoor()) then
                if body:isFacingObject(object, 0.5) then

                    if object:IsOpen() or not BridgeMove.doorOpenable(body, object) then
                        return BridgeMove.openDoor(body, object)
                    end
                    return BridgeMove.startDoorAct(body, "open", object)
                else
                    body:faceThisObject(object)
                    return true
                end
            end
        end
    end
    return false
end








local function pickSpeed(d)
    if BridgeMove.speedMode == "fixed" then return BridgeMove.fixedSpeed end
    if not BridgeMove.redMoving then return 1.0 end
    if d < 1.3 then return 0.8 end
    if d < 1.7 then return 0.88 end
    if d < 2.1 then return 1.1 end
    return 1.25
end

function BridgeMove.update(body)
    do
        local red = BridgeData.owner()
        if red ~= nil then
            local px, py = red:getX(), red:getY()

            local el = frameDt()
            if BridgeMove.redPrev ~= nil then
                if BridgeMove.redPrev.t ~= nil and Bridge.time - BridgeMove.redPrev.t > 0 then
                    el = Bridge.time - BridgeMove.redPrev.t
                end
            end




            local hist = BridgeMove.redHist
            local lastH = hist and hist[#hist] or nil
            local raw = lastH ~= nil and dist2d(lastH.x, lastH.y, px, py) / el or 0
            if hist == nil or raw >= 0.5 then


                hist = {}
                BridgeMove.redHist = hist
                BridgeMove.redStep = raw
            end
            hist[#hist + 1] = { t = Bridge.time, x = px, y = py }
            while #hist > 2 and hist[2].t <= Bridge.time - RED_WIN do table.remove(hist, 1) end
            local h0 = hist[1]
            if Bridge.time - h0.t > 0 then
                BridgeMove.redStep = dist2d(h0.x, h0.y, px, py) / (Bridge.time - h0.t)
            end
            BridgeMove.redPrev = { x = px, y = py, t = Bridge.time }
            BridgeMove.redMoving = BridgeMove.redStep > 0.015

            if BridgeMove.redStep < 0.5 then

                local a = 1 - 0.8 ^ el
                BridgeMove.redSpeed = BridgeMove.redSpeed + (BridgeMove.redStep - BridgeMove.redSpeed) * a
                local prev = BridgeMove.redPrevPos
                if prev ~= nil then
                    local b = 1 - 0.7 ^ el
                    BridgeMove.redVx = (BridgeMove.redVx or 0) + ((px - prev.x) / el - (BridgeMove.redVx or 0)) * b
                    BridgeMove.redVy = (BridgeMove.redVy or 0) + ((py - prev.y) / el - (BridgeMove.redVy or 0)) * b
                end
            end
            BridgeMove.redPrevPos = { x = px, y = py }
            BridgeMove.addTrail(red)
        end
    end
    if Bridge.time < (BridgeMove.unPathfindUntil or 0) and BridgeMove.cross == nil then
        pcall(function() body:setVariable("bPathfind", false) end)
    end
    if BridgeMove.climbStep(body) then return end
    local okCross, crossing = pcall(function() return BridgeMove.crossStep(body) end)
    if not okCross then
        BridgeMove.crossInfo = "error: " .. tostring(crossing)
        BridgeMove.cross = nil
        pcall(function() body:setVariable("bPathfind", false) end)
    elseif crossing then
        trackStep(body)
        return
    end

    local okDoor, atDoor = pcall(function() return BridgeMove.doorStep(body) end)
    if not okDoor then
        BridgeMove.doorLast = "error: " .. tostring(atDoor)
        BridgeMove.doorAct = nil
    elseif atDoor then
        trackStep(body)
        return
    end

    if BridgeAim ~= nil and BridgeAim.step(body, BridgeData.owner()) then
        trackStep(body)
        return
    end

    if BridgeMove.steering or BridgeMove.pathing then
        pcall(function() BridgeMove.openAhead(body) end)
        if BridgeMove.doorAct ~= nil then
            trackStep(body)
            return
        end
    end

    if Bridge.follow then
        local okSeat, seated = pcall(function() return BridgeMove.seatStep(body) end)
        if not okSeat then
            BridgeMove.seatInfo = "error: " .. tostring(seated)
            BridgeMove.seat = nil
        else
            BridgeMove.seatInfo = nil
            if seated then return end
        end
    end

    if not Bridge.follow and Bridge.target ~= nil and Bridge.target.cellX ~= nil then
        local okAside, going = pcall(function() return BridgeMove.asideStep(body) end)
        if not okAside then BridgeMove.seatInfo = "error: " .. tostring(going)
        elseif going then return end
    end



    local pendHere = false
    if Bridge.follow then
        pcall(function() pendHere = BridgeInventory ~= nil and BridgeInventory.transferPending(body) end)
    end
    if BridgeMove.steerMode and Bridge.follow and not pendHere and BridgeMove.followTrail(body) then return end

    BridgeMove.setCollide(body, true)
    if BridgeMove.steering then
        BridgeMove.endFollowBump(body, "")
        BridgeMove.steering = false
        BridgeMove.pathing = false
        BridgeMove.wasWalking = false
    end
    local gx, gy, gz, d = BridgeMove.currentGoal(body)
    if gx ~= nil then
        local wx, wy, wz = nil, nil, nil
        pcall(function() wx, wy, wz = BridgeMove.viaDoor(body, gx, gy, gz) end)
        if wx ~= nil then gx, gy, gz = wx, wy, wz end

        local px, py, pz = nil, nil, nil
        pcall(function() px, py, pz = BridgeMove.gapGoal(body) end)
        if px ~= nil then gx, gy, gz = px, py, pz end
    end
    if gx == nil then
        BridgeMove.wasWalking = false
        if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        if Bridge.follow and Bridge.zombieTicks % 30 == 0 then
            local red = BridgeData.owner()
            if red ~= nil then pcall(function() body:faceLocationF(red:getX(), red:getY()) end) end
        end
        return
    end

    local arrived = d <= 0.8


    local t = Bridge.target
    if t ~= nil and t.cellX ~= nil then
        arrived = d <= 0.7 and math.floor(body:getX()) == t.cellX and math.floor(body:getY()) == t.cellY
    end
    if not Bridge.follow and arrived and math.abs(gz - body:getZ()) < 1 then
        if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        Bridge.target = nil
        return
    end

    BridgeMove.walkType = pickWalkType(d)
    if Bridge.follow then
        BridgeMove.speed = pickSpeed(d)
    end
    BridgeMove.applyAnimVars(body)

    if BridgeMove.pathing then
        local okObs, busy = pcall(function() return BridgeMove.handleObstacle(body) end)
        if not okObs then BridgeMove.obstacle = "error: " .. tostring(busy) end
        if okObs and busy then return end
    end

    local pf = body:getPathFindBehavior2()

    local replan = true
    if Bridge.follow then
        local red = BridgeData.owner()
        if BridgeMove.redAt ~= nil and red ~= nil then


            local far = BridgeMove.walkType == "Run" and BridgeMove.runReplan or BridgeMove.replanDist
            replan = dist2d(BridgeMove.redAt.x, BridgeMove.redAt.y, red:getX(), red:getY()) > far
        end

        if BridgeMove.goal ~= nil and dist2d(BridgeMove.goal.x, BridgeMove.goal.y, gx, gy) > 2 then replan = true end
    elseif BridgeMove.goal ~= nil then
        replan = dist2d(BridgeMove.goal.x, BridgeMove.goal.y, gx, gy) > BridgeMove.replanDist
    end
    local function startPath()
        BridgeMove.lastPath = Bridge.time




        local bump = ""
        pcall(function() bump = tostring(body:getBumpType()) end)





        local asnNow = ""
        pcall(function() asnNow = tostring(body:getActionStateName()) end)






        local ramp = bump == KICK
        local onTheMove = (Bridge.time - BridgeMove.stepTick) < 10
        if not ramp and not onTheMove and (bump == "Stand" or asnNow == "idle" or asnNow == "bumped"
            or (not BridgeMove.pathing and (not BridgeMove.wasWalking or BridgeMove.startBump == "on"))) then
            BridgeMove.startKick(body)
        end
        pf:pathToLocationF(gx, gy, gz)
        BridgeMove.goal = { x = gx, y = gy }
        local red = BridgeData.owner()
        if red ~= nil then BridgeMove.redAt = { x = red:getX(), y = red:getY() } end
        BridgeMove.pathing = true
    end




    local stalled = false
    if BridgeMove.redMoving and Bridge.follow and BridgeMove.pathing
        and (Bridge.time - BridgeMove.lastPath) >= 12 then
        pcall(function() stalled = (body:getActionStateName() == "idle") end)
    end

    local failedRecently = BridgeMove.lastFailed ~= nil and (Bridge.time - (BridgeMove.lastFailedAt or -9999)) < BridgeMove.pathEvery
    local every = BridgeMove.walkType == "Run" and BridgeMove.runEvery or BridgeMove.pathEvery
    local needPath = (not BridgeMove.pathing and not failedRecently) or stalled
        or (replan and (Bridge.time - BridgeMove.lastPath) >= every)
    if needPath then startPath() end
    local res = pf:update()
    BridgeMove.kickStep(body, pf)
    BridgeMove.pathResult = tostring(res)
    if res == BehaviorResult.Succeeded or res == BehaviorResult.Failed then


        BridgeMove.pathing = false
        if res == BehaviorResult.Failed then BridgeMove.lastFailed = Bridge.tick BridgeMove.lastFailedAt = Bridge.time end
        if Bridge.follow and BridgeMove.redMoving and res == BehaviorResult.Succeeded then


            BridgeMove.restarts = BridgeMove.restarts + 1
            BridgeMove.lastRestart = Bridge.time
            startPath()
            pcall(function() pf:update() end)
        elseif Bridge.follow then
            BridgeMove.moving = false
        end
    end
    BridgeMove.wasWalking = BridgeMove.pathing
    trackStep(body)
    BridgeMove.traceFrame(body, d, needPath, stalled)
end



function BridgeMove.set(name, value)
    if name == "anim" then
        BridgeMove.animOld = value == "old"
        return "anim " .. (BridgeMove.animOld and "old" or "new")
    elseif name == "blend" then
        BridgeMove.blendOverride = (value ~= "auto") and tonumber(value) or nil
        return "blend " .. tostring(BridgeMove.blendOverride or "auto")
    elseif name == "doorghost" then
        BridgeMove.doorGhost = value ~= "off"
        return "doorghost " .. (BridgeMove.doorGhost and "on" or "off")
    elseif name == "turn" then
        BridgeMove.turnLimit = (value ~= "off") and tonumber(value) or nil
        return "turn " .. tostring(BridgeMove.turnLimit or "off")
    elseif name == "bumpmove" then
        BridgeMove.bumpMove = value == "face" and "face" or "move"
        return "bumpmove " .. BridgeMove.bumpMove
    elseif name == "nocollide" then
        BridgeMove.noCollide = value ~= "off"
        return "nocollide " .. (BridgeMove.noCollide and "on" or "off")
    elseif name == "steer" then
        BridgeMove.steerMode = value ~= "off"
        return "steer " .. (BridgeMove.steerMode and "on" or "off")
    elseif name == "runreplan" then
        BridgeMove.runReplan = tonumber(value) or BridgeMove.runReplan
        return "runreplan " .. tostring(BridgeMove.runReplan)
    elseif name == "runevery" then
        BridgeMove.runEvery = tonumber(value) or BridgeMove.runEvery
        return "runevery " .. tostring(BridgeMove.runEvery)
    elseif name == "speedmod" then
        BridgeMove.speedModOverride = (value ~= "auto") and tonumber(value) or nil
        return "speedmod " .. tostring(BridgeMove.speedModOverride or "auto")
    end
    if name == "replan" then BridgeMove.replanDist = tonumber(value) or BridgeMove.replanDist
    elseif name == "every" then BridgeMove.pathEvery = tonumber(value) or BridgeMove.pathEvery
    elseif name == "speed" then BridgeMove.speedMode = value or BridgeMove.speedMode
    elseif name == "fixed" then BridgeMove.fixedSpeed = tonumber(value) or BridgeMove.fixedSpeed
    elseif name == "bump" then BridgeMove.startBump = value or BridgeMove.startBump
    elseif name == "slow" then BridgeMove.slowDist = tonumber(value) or BridgeMove.slowDist
    else return "unknown param: " .. tostring(name) end
    return sformat("replan=%.2f every=%d speed=%s fixed=%.2f bump=%s slow=%.2f", BridgeMove.replanDist,
        BridgeMove.pathEvery, BridgeMove.speedMode, BridgeMove.fixedSpeed, BridgeMove.startBump, BridgeMove.slowDist)
end




function BridgeMove.goToward(body, x, y, z, way)

    if BridgeMove.cross ~= nil then crossEnd(body, "other move") end
    local pf = body:getPathFindBehavior2()
    if way then
        if BridgeMove.climbStep(body) then return end
        local okDoor, atDoor = pcall(function() return BridgeMove.doorStep(body) end)
        if okDoor and atDoor then return end
        if BridgeMove.pathing then
            local okObs, busy = pcall(function() return BridgeMove.handleObstacle(body) end)
            if not okObs then BridgeMove.obstacle = "error: " .. tostring(busy) end
            if okObs and busy then return end
        end
        local wx, wy, wz = nil, nil, nil
        pcall(function() wx, wy, wz = BridgeMove.viaDoor(body, x, y, z) end)
        if wx ~= nil then x, y, z = wx, wy, wz end
        local px, py, pz = nil, nil, nil
        pcall(function() px, py, pz = BridgeMove.gapGoal(body) end)
        if px ~= nil then x, y, z = px, py, pz end
    end
    local goalMoved = true
    if BridgeMove.goal ~= nil then
        goalMoved = dist2d(BridgeMove.goal.x, BridgeMove.goal.y, x, y) > 0.5
    end
    if not BridgeMove.pathing or (goalMoved and (Bridge.time - BridgeMove.lastPath) >= 10) then
        BridgeMove.lastPath = Bridge.time
        local bump = ""
        pcall(function() bump = tostring(body:getBumpType()) end)
        if not BridgeMove.pathing or bump == "Stand" then







            local asn = ""
            pcall(function() asn = tostring(body:getActionStateName()) end)
            local onTheMove = (Bridge.time - BridgeMove.stepTick) < 10
                and (isFollowBump(bump) or asn == "walktoward" or asn == "pathfind")
            if onTheMove and bump ~= KICK then
                if isFollowBump(bump) then BridgeMove.endFollowBump(body, "") end
                BridgeMove.steering = false
            elseif bump ~= KICK then
                BridgeMove.startKick(body)
            end
            Bridge.holdPos = nil
        end
        pf:pathToLocationF(x, y, z)
        BridgeMove.goal = { x = x, y = y }
        BridgeMove.pathing = true
    end
    local res = pf:update()
    BridgeMove.kickStep(body, pf)
    BridgeMove.pathResult = tostring(res)
    if res == BehaviorResult.Succeeded or res == BehaviorResult.Failed then
        BridgeMove.pathing = false
        BridgeMove.lastPath = Bridge.time
        if res == BehaviorResult.Failed then BridgeMove.lastFailed = Bridge.time end
    end
    trackStep(body)
end

function BridgeMove.reset(body)
    if body ~= nil then
        BridgeMove.setCollide(body, true)
        BridgeMove.endFollowBump(body, "")

        if BridgeMove.follow ~= nil and BridgeMove.follow.passing then pcall(function() body:setSolid(true) end) end
    end
    BridgeMove.collideOff = false
    BridgeMove.trail = {}
    BridgeMove.follow.cross = nil
    BridgeMove.redVx, BridgeMove.redVy, BridgeMove.redPrevPos = 0, 0, nil
    BridgeMove.steering = false
    BridgeMove.walkFrames = 0
    if body ~= nil then BridgeMove.stopPath(body) end
    BridgeMove.pathing = false
    BridgeMove.goal = nil
    BridgeMove.redAt = nil
    BridgeMove.wasWalking = false
    BridgeMove.moving = false
    BridgeMove.window = nil
    BridgeMove.walkType = "Walk"
    BridgeMove.redPrev = nil
    BridgeMove.redHist = nil
    BridgeMove.redMoving = false
    BridgeMove.stepPos = nil
    BridgeMove.climbUntil = 0
    BridgeMove.pendingClimb = nil
    if BridgeMove.cross ~= nil and body ~= nil then
        pcall(function()
            body:setVariable("bPathfind", false)
            local bump = body:getBumpType()
            if bump == "ClimbFenceTall" or bump == "ClimbFenceTallStart" then BridgeMove.releaseBump(body) end
        end)
    end
    BridgeMove.cross = nil
    BridgeMove.noCrossUntil = 0
    BridgeMove.lastCross = nil
    BridgeMove.edgeSeen = nil
    BridgeMove.doorAct = nil
    BridgeMove.doorWay = nil

    BridgeMove.opened = {}
    BridgeMove.gapWay = nil
    BridgeMove.seat = nil
    if BridgeMove.seatFlag and body ~= nil then
        pcall(function() body:setSittingOnFurniture(false) end)
    end
    BridgeMove.seatFlag = false
    BridgeMove.nearReset()

    BridgeMove.stride = nil
    if body ~= nil then setStride(body, false) end
end

log("loaded")




local function freeSeat(vehicle)
    local n = vehicle:getMaxPassengers()
    for seat = 1, n - 1 do
        if vehicle:isSeatInstalled(seat) and not vehicle:isSeatOccupied(seat) then
            return seat
        end
    end
    return nil
end


function BridgeMove.enterCar(body, vehicle)
    local seat = freeSeat(vehicle)
    if seat == nil then return "no free seat" end
    BridgeMove.stopPath(body)
    local ok, err = pcall(function()
        if not vehicle:enter(seat, body) then return "enter returned false" end
        vehicle:setCharacterPosition(body, seat, "inside")
        pcall(function() vehicle:playPassengerAnim(seat, "idle") end)
    end)
    if ok and err ~= nil then ok = false end
    if not ok then

        local ok2, err2 = pcall(function()
            local fd = body:getForwardDirection()
            body:enterVehicle(vehicle, seat, Vector3f.new(fd:getX(), fd:getY(), 0))
        end)
        if not ok2 then return "enter failed: " .. tostring(err) .. " / " .. tostring(err2) end
    end
    pcall(function() body:playSound("VehicleDoorClose") end)
    return "seat " .. tostring(seat)
end

function BridgeMove.exitCar(body)
    local vehicle = body:getVehicle()
    if vehicle == nil then return "not in car" end
    local ok, err = pcall(function()
        local seat = vehicle:getSeat(body)
        vehicle:exit(body)
        vehicle:setCharacterPosition(body, seat, "outside")
    end)
    if not ok then return "exit failed: " .. tostring(err) end
    pcall(function() body:playSound("VehicleDoorOpen") end)
    BridgeMove.reset(body)
    return "exited"
end


function BridgeMove.toCar(body, vehicle)
    local d = dist2d(body:getX(), body:getY(), vehicle:getX(), vehicle:getY())
    if d > 2.4 then
        BridgeMove.walkType = (d > RUN_DIST) and "Run" or "Walk"
        BridgeMove.goToward(body, vehicle:getX(), vehicle:getY(), vehicle:getZ())
        return true
    end
    local res = BridgeMove.enterCar(body, vehicle)
    BridgeMove.obstacle = "car: " .. tostring(res)
    return true
end


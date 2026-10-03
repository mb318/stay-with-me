













BridgeCar = BridgeCar or {}
BridgeCar.state = "idle"
BridgeCar.phase = nil
BridgeCar.car = nil
BridgeCar.seat = nil
BridgeCar.lap = false
BridgeCar.tried = {}
BridgeCar.opened = nil
BridgeCar.closeAt = nil
BridgeCar.exit = nil
BridgeCar.info = "none"

local LEAVE = 10
local RETURN = 20
local FOOT = 30


local ARRIVE = 0.55
local STALL = 300
local OPEN_TICKS = 12

local OUT_TICKS = 20
local REMIND = 1200
local CLOSE_AFTER = 10
local SPAWN_WAIT = 600
local CANCEL = 30

local LAP_STEP = 0.8
local MOVING_KMH = 0.5
local ARRIVE_PATH = 1.0

local AFTER_HIM = 60


local LEFT_LINE_GAP = 3600
local DRIVE_OFF_KMH = 3
local TOWARD_COS = 0.7


local DODGE_HALF_W = 1.0
local DODGE_MARGIN = 0.2
local DODGE_END = 30
local DODGE_BACK = 3.0
local DODGE_AHEAD = 3.0
local DODGE_SECONDS = 1.5
local DODGE_SIDE = 1.4
local DODGE_ARRIVE = 0.4
local DODGE_BODY = 0.15

local DODGE_RETARGET = 30
local DODGE_KMH = 2
local DODGE_FRONT = 1.5
local DODGE_CREEP_KMH = 0.8
local DODGE_BAD_MAX = 4
local BACK_MAX = 600
local PIVOT_DEG = 8

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeCar] " .. tostring(text)) end end
local function warn(text) print("[BridgeCar] " .. tostring(text)) end
local sformat = string.format


local function movesReset()
    BridgeCar.dodging, BridgeCar.dodgeTo, BridgeCar.dodgeBad, BridgeCar.dodgeStuck, BridgeCar.dodgeBadN = nil, nil, nil, nil, nil
    BridgeCar.aside, BridgeCar.dodgeAt, BridgeCar.detour = nil, nil, nil

    if BridgeMove.follow ~= nil then BridgeMove.follow.pathUntil, BridgeMove.follow.stuckAt = nil, nil end
    BridgeCar.backToDoor, BridgeCar.backGaveUp = nil, nil
end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end


local function trace(body, tag, gx, gy)
    if not Bridge.verbose then return end

    local age = Bridge.time - (BridgeCar.since or 0)
    if age >= 40 and not Bridge.every(10) then return end
    local bx, by, bump, asn, moving, started = nil, nil, "", "", "?", "?"
    pcall(function() bx, by = body:getX(), body:getY() end)
    pcall(function() bump = tostring(body:getBumpType()) end)
    pcall(function() asn = tostring(body:getActionStateName()) end)
    pcall(function() moving = tostring(body:isMoving()) end)
    pcall(function() started = tostring(body:getPathFindBehavior2():hasStartedMoving()) end)
    if bx == nil then return end
    local last = BridgeCar.traceLast
    local step = (last ~= nil) and math.sqrt((bx - last[1]) ^ 2 + (by - last[2]) ^ 2) or 0
    BridgeCar.traceLast = { bx, by }
    log(sformat("%s: at %.2f %.2f, step %.2f, to goal %.2f, bump %s, state %s, %s, path %s, moving %s, started %s, kick %s",
        tag, bx, by, step, (gx ~= nil and gy ~= nil) and math.sqrt((gx - bx) ^ 2 + (gy - by) ^ 2) or -1, bump, asn,
        tostring(BridgeMove.walkType), tostring(BridgeMove.pathing), moving, started, tostring(BridgeMove.kickAt ~= nil)))
end

local function distTo(o, x, y)
    local d = math.huge
    pcall(function() d = dist(o:getX(), o:getY(), x, y) end)
    return d
end


local function distToCar(o, car)
    local d = math.huge
    pcall(function() d = dist(o:getX(), o:getY(), car:getX(), car:getY()) end)
    return d
end

local function carId(car)
    local id = nil
    pcall(function() id = car:getId() end)
    return id
end




function BridgeCar.drivesAway(car, body)
    local speed, vx, vy, hx, hy = 0, nil, nil, nil, nil
    pcall(function() speed = math.abs(car:getCurrentSpeedKmHour()) end)
    if speed < DRIVE_OFF_KMH then return false end
    pcall(function()
        local v = car:getLinearVelocity(Vector3f.new())
        vx, vy = v:x(), v:z()
    end)
    pcall(function() hx, hy = body:getX() - car:getX(), body:getY() - car:getY() end)
    if vx == nil or hx == nil then return false end
    local vl, hl = math.sqrt(vx * vx + vy * vy), math.sqrt(hx * hx + hy * hy)
    if vl < 1e-3 then return false end
    if hl < 1e-3 then return true end
    return (vx * hx + vy * hy) / (vl * hl) < TOWARD_COS
end



local OUTSIDE = "-1"
local function roomOf(sq)
    local id = OUTSIDE
    pcall(function() id = tostring(sq:getRoomIDString()) end)
    return id
end


local function lineClear(x1, y1, x2, y2, z)
    local cell = getCell()
    if cell == nil then return false end
    local d = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    local n = math.max(1, math.ceil(d / 0.5))
    local prev = nil
    for i = 0, n do
        local sq = cell:getGridSquare(math.floor(x1 + (x2 - x1) * i / n), math.floor(y1 + (y2 - y1) * i / n), z)
        if sq == nil then return false end
        if prev ~= nil and sq ~= prev then
            local blocked = true
            pcall(function() blocked = prev:isBlockedTo(sq) end)
            if blocked then return false end
        end
        prev = sq
    end
    return true
end




function BridgeCar.frame(car)
    local cx, cy, fx, fy, w, l = nil, nil, nil, nil, nil, nil
    pcall(function()
        cx, cy = car:getX(), car:getY()
        local e = car:getScript():getExtents()
        w, l = e:x(), e:z()
    end)
    fx, fy = BridgeCar.forward(car)
    if cx == nil or fx == nil or type(w) ~= "number" or type(l) ~= "number" then return nil end
    local fl = math.sqrt(fx * fx + fy * fy)
    if fl < 1e-3 then return nil end
    return { cx = cx, cy = cy, fx = fx / fl, fy = fy / fl, hw = w / 2, hl = l / 2 }
end

local function segmentHitsCar(car, x1, y1, x2, y2)
    local C = BridgeCar.frame(car)
    if C == nil then return false end
    local cx, cy, fx, fy, hw, hl = C.cx, C.cy, C.fx, C.fy, C.hw, C.hl

    local function toCar(x, y)
        local rx, ry = x - cx, y - cy
        return rx * fx + ry * fy, ry * fx - rx * fy
    end
    local a1, s1 = toCar(x1, y1)
    local a2, s2 = toCar(x2, y2)

    local t0, t1 = 0, 1
    local function clip(p, q)
        if math.abs(p) < 1e-9 then return q >= 0 end
        local r = q / p
        if p < 0 then if r > t1 then return false end if r > t0 then t0 = r end
        else if r < t0 then return false end if r < t1 then t1 = r end end
        return true
    end
    local da, ds = a2 - a1, s2 - s1
    if not clip(-da, a1 + hl) or not clip(da, hl - a1) or not clip(-ds, s1 + hw) or not clip(ds, hw - s1) then return false end
    return t0 <= t1
end



function BridgeCar.straightClear(body, x, y, z, car)
    local bx, by = nil, nil
    pcall(function() bx, by = body:getX(), body:getY() end)
    if bx == nil then return false end
    if not lineClear(bx, by, x, y, math.floor((z or 0) + 0.01)) then return false end
    car = car or BridgeCar.car
    if car ~= nil and segmentHitsCar(car, bx, by, x, y) then return false end
    return true
end



function BridgeCar.halfWidth(car)
    local w = nil
    pcall(function() w = car:getScript():getExtents():x() end)
    if type(w) ~= "number" or w ~= w or w < 0.5 or w > 6 then return DODGE_HALF_W end
    return w / 2 + DODGE_MARGIN
end





function BridgeCar.lane(car, body)
    local speed, vx, vy, cx, cy, bx, by = 0, nil, nil, nil, nil, nil, nil
    pcall(function() speed = math.abs(car:getCurrentSpeedKmHour()) end)
    if speed < MOVING_KMH then return nil end
    local creep = speed >= DODGE_CREEP_KMH
    pcall(function()
        local v = car:getLinearVelocity(Vector3f.new())
        vx, vy = v:x(), v:z()
        cx, cy = car:getX(), car:getY()
        bx, by = body:getX(), body:getY()
    end)
    if vx == nil or bx == nil then return nil end
    local vl = math.sqrt(vx * vx + vy * vy)
    if vl < 0.05 then return nil end
    local ux, uy = vx / vl, vy / vl
    local rx, ry = bx - cx, by - cy
    local along = rx * ux + ry * uy
    local side = ry * ux - rx * uy
    local dodging = BridgeCar.dodging == true
    if not dodging and speed < DODGE_KMH and not (creep and along >= DODGE_FRONT and along <= DODGE_AHEAD) then return nil end
    local halfW = dodging and (BridgeCar.halfWidth(car) + DODGE_SIDE + 0.2) or (BridgeCar.halfWidth(car) + DODGE_BODY)


    if not dodging and speed < DODGE_KMH then halfW = BridgeCar.halfWidth(car) - DODGE_MARGIN end
    local reach = DODGE_AHEAD + (dodging and math.max(vl, 3) or vl) * DODGE_SECONDS
    if along < -DODGE_BACK or along > reach or math.abs(side) > halfW then return nil end
    return { cx = cx, cy = cy, ux = ux, uy = uy, along = along, side = side }
end



local function dodgeTarget(body, L, car)
    local bz = 0
    pcall(function() bz = body:getZ() end)
    local hers, bx, by = nil, nil, nil
    pcall(function() hers = body:getCurrentSquare() end)
    pcall(function() bx, by = body:getX(), body:getY() end)
    local herRoom = hers ~= nil and roomOf(hers) or OUTSIDE
    local bad = BridgeCar.dodgeBad or {}
    local first = L.side >= 0 and 1 or -1
    local side = BridgeCar.halfWidth(car) + DODGE_SIDE
    local tries = { { first, side }, { -first, side }, { first, side + 1.5 }, { -first, side + 1.5 } }
    for _, t in ipairs(tries) do
        local tx = L.cx + L.ux * L.along - L.uy * t[1] * t[2]
        local ty = L.cy + L.uy * L.along + L.ux * t[1] * t[2]
        local key = math.floor(tx) .. "," .. math.floor(ty)
        local ok = false
        pcall(function()
            local sq = getCell():getGridSquare(math.floor(tx), math.floor(ty), math.floor(bz + 0.01))
            local room = sq ~= nil and roomOf(sq) or OUTSIDE
            ok = not bad[key] and Bridge.standSquareOk(sq) and (room == herRoom or room == OUTSIDE)
                and bx ~= nil and lineClear(bx, by, tx, ty, math.floor(bz + 0.01))
        end)
        if ok then return { x = tx, y = ty, z = bz, key = key } end
    end
    return nil
end







local ASIDE_GAP = 1.2
local ASIDE_NEAR = 0.6


local DETOUR_GAP = 0.9
function BridgeCar.detourPoint(body, car, tx, ty, z)
    local C = car ~= nil and BridgeCar.frame(car) or nil
    local bx, by = nil, nil
    pcall(function() bx, by = body:getX(), body:getY() end)
    if C == nil or bx == nil then return nil end
    if not segmentHitsCar(car, bx, by, tx, ty) then return nil end
    local best, bd = nil, math.huge
    for _, sa in ipairs({ 1, -1 }) do
        for _, ss in ipairs({ 1, -1 }) do
            local a, sd = sa * (C.hl + DETOUR_GAP), ss * (C.hw + DETOUR_GAP)
            local px = C.cx + C.fx * a - C.fy * sd
            local py = C.cy + C.fy * a + C.fx * sd
            local d = distTo(body, px, py) + math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2)
            if d < bd and not segmentHitsCar(car, bx, by, px, py) and not segmentHitsCar(car, px, py, tx, ty)
                and lineClear(bx, by, px, py, math.floor((z or 0) + 0.01)) then
                best, bd = { x = px, y = py }, d
            end
        end
    end
    return best
end


function BridgeCar.goToDoor(body, car, x, y, z, run)
    local d = BridgeCar.detour


    if d ~= nil then
        local bx, by = nil, nil
        pcall(function() bx, by = body:getX(), body:getY() end)
        if math.abs(d.tx - x) > 0.1 or math.abs(d.ty - y) > 0.1 or distTo(body, d.x, d.y) <= 0.5
            or (bx ~= nil and car ~= nil and not segmentHitsCar(car, bx, by, x, y)) then
            BridgeCar.detour, d = nil, nil
        end
    end
    if d == nil and car ~= nil then
        local p = BridgeCar.detourPoint(body, car, x, y, z)
        if p ~= nil then
            d = { x = p.x, y = p.y, tx = x, ty = y }
            BridgeCar.detour = d
            local last = BridgeCar.detourLogged
            if last == nil or math.abs(last.x - p.x) > 0.3 or math.abs(last.y - p.y) > 0.3 then
                BridgeCar.detourLogged = { x = p.x, y = p.y }
                log(sformat("to the door around the car: via %.1f %.1f", p.x, p.y))
            end
        end
    end
    local gx, gy = x, y
    if d ~= nil then gx, gy = d.x, d.y end
    if BridgeMove.goStraight(body, gx, gy, z, run, BridgeCar.straightClear) then return true end
    BridgeCar.detour = nil
    return false
end

function BridgeCar.sideStep(body, car)
    local a = BridgeCar.aside
    if a == nil then
        local C = car ~= nil and BridgeCar.frame(car) or nil
        local bx, by = nil, nil
        pcall(function() bx, by = body:getX(), body:getY() end)
        if C == nil or bx == nil then return false end
        local rx, ry = bx - C.cx, by - C.cy
        local along = rx * C.fx + ry * C.fy
        local side = ry * C.fx - rx * C.fy


        if math.abs(along) > C.hl + 0.5 or math.abs(side) > C.hw + ASIDE_NEAR or math.abs(side) < C.hw + 0.05 then
            BridgeCar.aside = { done = true }
            return false
        end
        local sign = side >= 0 and 1 or -1
        local ts = sign * (C.hw + ASIDE_GAP)
        local tx = C.cx + C.fx * along - C.fy * ts
        local ty = C.cy + C.fy * along + C.fx * ts
        local ok = false
        pcall(function() ok = Bridge.standSquareOk(getCell():getGridSquare(math.floor(tx), math.floor(ty), math.floor(body:getZ() + 0.01))) end)
        if not ok then
            BridgeCar.aside = { done = true }
            return false
        end
        a = { x = tx, y = ty, z = body:getZ(), done = false }
        BridgeCar.aside = a
        log(sformat("car moves: a step away from the side to %.1f %.1f", tx, ty))
    end
    if a.done then return false end
    if distTo(body, a.x, a.y) <= 0.3 then
        a.done = true
        if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        BridgeMove.moving = false
        pcall(function() BridgeMove.pivotToward(body, car:getX(), car:getY(), PIVOT_DEG) end)
        return false
    end
    if not BridgeMove.goStraight(body, a.x, a.y, a.z, false, function(b, x, y, z) return BridgeCar.straightClear(b, x, y, z, car) end) then
        a.done = true
        return false
    end
    return true
end

function BridgeCar.dodge(body, car)
    local L = car ~= nil and BridgeCar.lane(car, body) or nil
    if L == nil then
        if not BridgeCar.dodging then return false end


        BridgeCar.dodgeEnd = BridgeCar.dodgeEnd or (BridgeCar.gt or 0)
        if (BridgeCar.gt or 0) - BridgeCar.dodgeEnd < DODGE_END then
            local t = BridgeCar.dodgeTo
            if t == nil then return false end
            if distTo(body, t.x, t.y) <= DODGE_ARRIVE then
                if BridgeMove.onPath() then BridgeMove.stopPath(body) end
                BridgeMove.moving = false
                return true
            end
            BridgeMove.walkType = "Run"
            trace(body, "dodge", t.x, t.y)
            if not BridgeMove.goStraight(body, t.x, t.y, t.z, true, function(b, x, y, z) return BridgeCar.straightClear(b, x, y, z, car) end) then
                pcall(function() BridgeMove.goToward(body, t.x, t.y, t.z, false) end)
            end
            return true
        end
        pcall(function() BridgeMove.stopPath(body) end)
        BridgeMove.moving = false
        log("car passed her: stops")
        BridgeCar.dodging, BridgeCar.dodgeTo, BridgeCar.dodgeBad, BridgeCar.dodgeStuck, BridgeCar.dodgeBadN = nil, nil, nil, nil, nil
        BridgeCar.dodgeEnd, BridgeCar.dodgeAt = nil, nil
        return false
    end
    BridgeCar.dodgeEnd = nil
    local t = BridgeCar.dodgeTo
    if t ~= nil then
        if not BridgeMove.pathing and BridgeMove.pathResult == tostring(BehaviorResult.Failed) then
            BridgeCar.dodgeBad = BridgeCar.dodgeBad or {}
            BridgeCar.dodgeBad[t.key] = true
            BridgeCar.dodgeBadN = (BridgeCar.dodgeBadN or 0) + 1
            log("step aside: no path to " .. t.key .. ", another spot")
            t = nil
        elseif math.abs((t.y - L.cy) * L.ux - (t.x - L.cx) * L.uy) < BridgeCar.halfWidth(car) + DODGE_BODY
            and math.abs(L.side) < BridgeCar.halfWidth(car) + DODGE_BODY
            and (BridgeCar.dodgeAt == nil or (BridgeCar.gt or 0) - BridgeCar.dodgeAt >= DODGE_RETARGET) then


            t = nil
        end
    end

    if t ~= nil and BridgeMove.follow ~= nil and BridgeMove.follow.pathUntil ~= nil and Bridge.time < BridgeMove.follow.pathUntil then
        BridgeCar.dodgeBad = BridgeCar.dodgeBad or {}
        BridgeCar.dodgeBad[t.key] = true
        BridgeCar.dodgeBadN = (BridgeCar.dodgeBadN or 0) + 1
        BridgeMove.follow.pathUntil, BridgeMove.follow.stuckAt = nil, nil
        log("step aside: stuck on the way to " .. t.key .. ", another spot")
        t = nil
    end
    if t == nil and not BridgeCar.dodgeStuck then
        if (BridgeCar.dodgeBadN or 0) < DODGE_BAD_MAX then t = dodgeTarget(body, L, car) end
        BridgeCar.dodgeTo = t
        BridgeCar.dodgeAt = BridgeCar.gt or 0



        local kept = BridgeCar.dodging and (BridgeMove.pathing or BridgeMove.steering)
        if (BridgeCar.dodgeTo ~= nil or BridgeCar.dodging) and not kept then
            pcall(function() BridgeMove.stopPath(body) end)
        end
        BridgeMove.pathResult = "none"
        if BridgeCar.dodging and t ~= nil then
            log(sformat("car turned at her: new spot %.1f %.1f, path %s", t.x, t.y, kept and "kept" or "reset"))
        end
    end
    if not BridgeCar.dodging then
        BridgeCar.dodging = true
        log(sformat("car comes at her: steps aside%s, d=%.1f", t and sformat(" to %.1f %.1f", t.x, t.y) or "", distToCar(body, car)))
    end
    if t == nil then

        if not BridgeCar.dodgeStuck then
            BridgeCar.dodgeStuck = true
            log("car comes at her: no spot to step aside, stays")
        end
        return false
    end
    BridgeCar.dodgeStuck = nil
    if distTo(body, t.x, t.y) <= DODGE_ARRIVE then
        if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        BridgeMove.moving = false

        pcall(function() BridgeMove.pivotToward(body, car:getX(), car:getY(), PIVOT_DEG) end)
        return true
    end
    BridgeMove.walkType = "Run"
    trace(body, "dodge", t.x, t.y)
    if not BridgeMove.goStraight(body, t.x, t.y, t.z, true, function(b, x, y, z) return BridgeCar.straightClear(b, x, y, z, car) end) then
        pcall(function() BridgeMove.goToward(body, t.x, t.y, t.z, false) end)
    end
    return true
end

function BridgeCar.moving(car)
    if car == nil then return false end
    local m = false


    pcall(function()
        m = math.abs(car:getCurrentSpeedKmHour()) > MOVING_KMH or (car:getController() ~= nil and not car:isStopped())
    end)
    return m
end



function BridgeCar.rolling(car, body)
    if car == nil then return false end
    if BridgeCar.dodging then return true end
    local speed = 0
    pcall(function() speed = math.abs(car:getCurrentSpeedKmHour()) end)
    if speed >= DODGE_KMH then return true end
    return body ~= nil and BridgeCar.lane(car, body) ~= nil
end




local function seatMeta(car, i)
    local id = ""
    pcall(function() id = tostring(car:getScript():getPassenger(i):getId()) end)
    local row = "Rear"
    if string.find(id, "Front", 1, true) then row = "Front"
    elseif string.find(id, "Middle", 1, true) then row = "Middle" end
    local side = string.find(id, "Left", 1, true) and "L" or (string.find(id, "Right", 1, true) and "R" or "?")
    return id, row, side
end



function BridgeCar.doorPoint(car, i)
    local x, y, z = nil, nil, nil
    pcall(function()
        local pos = car:getPassengerPosition(i, "outside")
        if pos == nil then return end
        local w = Vector3f.new()
        car:getWorldPos(pos:getOffset(), w)
        x, y, z = w:x(), w:y(), car:getZ()
    end)
    return x, y, z
end



function BridgeCar.walkPoint(car, i)
    local x, y = nil, nil
    pcall(function()
        local area = car:getScript():getAreaById(car:getPassengerArea(i))
        if area == nil then return end
        local v = car:areaPositionWorld4PlayerInteract(area)
        if v ~= nil then x, y = v:getX(), v:getY() end
    end)
    if x == nil then
        local dx, dy = BridgeCar.doorPoint(car, i)
        return dx, dy
    end
    return x, y
end



function BridgeCar.forward(car)
    local fx, fy = nil, nil
    pcall(function()
        local f = car:getForwardVector(Vector3f.new())
        fx, fy = f:x(), f:z()
    end)
    return fx, fy
end



local function othersSeats(car)
    local set = {}
    if not Bridge.mp then return set end
    local vid = carId(car)
    if vid == nil then return set end
    pcall(function()

        local md = Bridge.world or BridgeData.world(nil)
        local me = BridgeData.me()
        for who, rec in pairs(md.players) do
            local c = type(rec) == "table" and rec.car or nil
            if who ~= me and type(c) == "table" and c.v == vid and not c.lap and type(c.s) == "number" then
                local p = nil
                pcall(function() p = getPlayerFromUsername(who) end)
                local here = false
                pcall(function() here = p ~= nil and (p:getVehicle() == car or distToCar(p, car) < 20) end)
                if here then set[c.s] = true end
            end
        end
    end)
    return set
end



local function switchSeatOf(red)
    local to = nil
    pcall(function()
        local q = ISTimedActionQueue.queues[red]
        if q == nil or q.queue == nil then return end
        for idx, a in ipairs(q.queue) do
            if idx > 6 then break end
            if a.Type == "ISSwitchVehicleSeat" and type(a.seatTo) == "number" then to = a.seatTo return end
        end
    end)
    return to
end


function BridgeCar.layout(car, bx, by)
    local seats = {}
    local n = 0
    pcall(function() n = car:getMaxPassengers() end)
    local taken = othersSeats(car)
    for i = 0, n - 1 do
        local s = { i = i, driver = (i == 0) }
        s.id, s.row, s.side = seatMeta(car, i)
        pcall(function() s.installed = car:isSeatInstalled(i) end)
        pcall(function()
            local ch = car:getCharacter(i)
            s.person = ch ~= nil

            if ch ~= nil and ch == BridgeData.owner() then
                local to = switchSeatOf(ch)
                if to ~= nil and to ~= i then s.person, s.leaving = false, true end
            end
        end)
        local occupied = false
        pcall(function() occupied = car:isSeatOccupied(i) end)
        s.items = occupied and not s.person and not s.leaving
        pcall(function() s.blocked = car:isExitBlocked(i) end)
        s.reserved = taken[i] == true
        local dx, dy = BridgeCar.doorPoint(car, i)
        s.nodoor = dx == nil
        s.d = (dx ~= nil and bx ~= nil) and dist(bx, by, dx, dy) or 0
        seats[#seats + 1] = s
    end
    return seats
end



function BridgeCar.choose(seats, his, tried)
    tried = tried or {}
    local byI = {}
    for _, s in ipairs(seats) do byI[s.i] = s end
    local mine = byI[his or 0]
    local hisRow = (mine ~= nil and mine.row) or "Front"
    local hisSide = mine ~= nil and mine.side or "L"
    local driver = his == nil or his == 0
    local function nearFirst(list)
        table.sort(list, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.i < b.i end)
        return list
    end
    local groups = {}
    if driver then
        local front, rest = {}, {}
        for _, s in ipairs(seats) do
            if not s.driver then
                if s.row == "Front" then front[#front + 1] = s else rest[#rest + 1] = s end
            end
        end
        groups = { nearFirst(front), nearFirst(rest) }
    elseif hisRow == "Front" then

        local rest = {}
        for _, s in ipairs(seats) do if s.row ~= "Front" then rest[#rest + 1] = s end end
        groups = { nearFirst(rest) }
    else
        local row, rest = {}, {}
        for _, s in ipairs(seats) do
            if not s.driver and s.i ~= his then
                if s.row == hisRow and s.side ~= hisSide then row[#row + 1] = s else rest[#rest + 1] = s end
            end
        end
        groups = { nearFirst(row), nearFirst(rest) }
    end
    local function ok(s, items)
        return not s.driver and s.i ~= his and s.installed and not s.person and not s.reserved and not s.blocked
            and not s.nodoor and not tried[s.i] and (items or not s.items)
    end

    for _, items in ipairs({ false, true }) do
        for _, g in ipairs(groups) do
            for _, s in ipairs(g) do
                if ok(s, items) then return s.i, false end
            end
        end
    end
    return his or 0, true
end


local function pick(car, his, bx, by)
    local seat, lap = BridgeCar.choose(BridgeCar.layout(car, bx, by), his, BridgeCar.tried)
    return seat, lap
end


function BridgeCar.reserve(inside)
    local car = BridgeCar.car
    local c = { v = carId(car), s = BridgeCar.seat, lap = BridgeCar.lap or nil, inside = inside or nil }
    local st = Bridge.store
    if st ~= nil then st.car = c end
    BridgeCar.reserved = true
    if Bridge.mp then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "carSeat", c) end)
    end
end



function BridgeCar.release()
    local st = Bridge.store
    local had = BridgeCar.reserved or (st ~= nil and st.car ~= nil)
    if st ~= nil then st.car = nil end
    BridgeCar.reserved = false
    if Bridge.mp and had then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "carSeat", { clear = true }) end)
    end
end


function BridgeCar.onSeat(args)
    if type(args) ~= "table" or args.ok ~= false then return end
    if BridgeCar.state ~= "going" and BridgeCar.state ~= "inside" then return end
    if args.s ~= BridgeCar.seat then return end
    BridgeCar.closeDoor("seat taken")

    if Bridge.alive() and BridgeCar.state == "going" then
        pcall(function() BridgeMove.setCollide(Bridge.body, true) end)
    end
    BridgeCar.tried[args.s] = true
    local red = BridgeData.owner()
    local bx, by = nil, nil
    if Bridge.alive() then bx, by = Bridge.body:getX(), Bridge.body:getY() end
    local his = BridgeCar.his
    pcall(function() if red:getVehicle() == BridgeCar.car then his = BridgeCar.car:getSeat(red) end end)
    BridgeCar.seat, BridgeCar.lap = pick(BridgeCar.car, his, bx, by)
    if BridgeCar.state == "going" then BridgeCar.phase = "walk" end
    BridgeCar.reserve(BridgeCar.state == "inside")
    log(sformat("seat %s taken by another companion, now %s%s", tostring(args.s), tostring(BridgeCar.seat),
        BridgeCar.lap and " (lap)" or ""))
end



local function doorOf(car, i)
    local p = nil
    pcall(function() p = car:getPassengerDoor(i) end)
    if p == nil then return nil end
    local ok = false
    pcall(function() ok = p:getDoor() ~= nil and p:getInventoryItem() ~= nil end)
    return ok and p or nil
end

local function locked(p)
    local l = false
    pcall(function() l = p:getDoor():isLocked() end)
    return l
end

local function isOpen(p)
    local o = false
    pcall(function() o = p:getDoor():isOpen() end)
    return o
end



local function setDoor(car, p, open)
    local red = BridgeData.owner()
    pcall(function() car:playPartAnim(p, open and "Open" or "Close") end)
    pcall(function() car:playPartSound(p, red, open and "Open" or "Close") end)
    if Bridge.mp then
        pcall(function() sendClientCommand(red, "Bridge", "carDoor", { v = car:getId(), part = p:getId(), open = open }) end)
    else
        pcall(function() p:getDoor():setOpen(open) end)
        pcall(function() car:transmitPartDoor(p) end)
    end
end


function BridgeCar.closeDoor(why)
    local o = BridgeCar.opened
    BridgeCar.opened, BridgeCar.closeAt = nil, nil
    if o == nil then return end
    if isOpen(o.part) or Bridge.mp then setDoor(o.car, o.part, false) end
    log("door closed: " .. tostring(why))
end

local function openDoor(car, seat)
    local p = doorOf(car, seat)

    if BridgeCar.opened ~= nil and BridgeCar.opened.part ~= p then BridgeCar.closeDoor("another door") end
    if p == nil or isOpen(p) then return false end
    setDoor(car, p, true)
    BridgeCar.opened = { car = car, part = p }
    return true
end






local function switchTo(red, seat)
    local to = switchSeatOf(red)
    if to ~= nil then return to end
    return seat
end

function BridgeCar.intent(red)
    local car = nil
    pcall(function() car = red:getVehicle() end)
    if car ~= nil then
        local his = nil
        pcall(function() his = car:getSeat(red) end)
        return car, switchTo(red, his), true
    end
    local found, seat = nil, nil
    pcall(function()
        local q = ISTimedActionQueue.queues[red]
        if q == nil or q.queue == nil then return end
        for idx, a in ipairs(q.queue) do
            if idx > 4 then break end
            if a.Type == "ISPathFindAction" and type(a.goal) == "table" and a.goal[1] == "VehicleSeat" then
                found, seat = a.goal[2], a.goal[3]
                return
            end
            if a.Type == "ISEnterVehicle" and a.vehicle ~= nil then
                found, seat = a.vehicle, a.seat
                return
            end
        end
    end)
    if found ~= nil then seat = switchTo(red, seat) end
    return found, seat, false
end


local function redExiting(red)
    local yes = false
    pcall(function() yes = red:getVariableBoolean("bExitingVehicle") end)
    if yes then return true end
    pcall(function()
        local q = ISTimedActionQueue.queues[red]
        if q == nil or q.queue == nil then return end
        for idx, a in ipairs(q.queue) do
            if idx > 4 then break end
            if a.Type == "ISExitVehicle" then yes = true return end
        end
    end)
    return yes
end


local function redSwitching(red)
    local yes = false
    pcall(function()
        local q = ISTimedActionQueue.queues[red]
        if q == nil or q.queue == nil then return end
        for idx, a in ipairs(q.queue) do
            if idx > 4 then break end
            if a.Type == "ISSwitchVehicleSeat" then yes = true return end
        end
    end)
    return yes
end



local function redEntering(red)
    local yes = false
    pcall(function() yes = red:getVariableBoolean("bEnteringVehicle") end)
    if yes then return true end
    pcall(function()
        local q = ISTimedActionQueue.queues[red]
        if q == nil or q.queue == nil then return end
        for idx, a in ipairs(q.queue) do
            if idx > 4 then break end
            if a.Type == "ISEnterVehicle" or a.Type == "ISOpenVehicleDoor" or a.Type == "ISCloseVehicleDoor" then
                yes = true
                return
            end
        end
    end)
    return yes
end



function BridgeCar.busy() return BridgeCar.state ~= "idle" end
function BridgeCar.isInside() return BridgeCar.state == "inside" end




function BridgeCar.inCarForMenu()
    return BridgeCar.state == "inside" or BridgeCar.state == "exiting"
end

function BridgeCar.holdHidden() return BridgeCar.state == "exiting" end

function BridgeCar.holdsBody()
    return BridgeCar.state == "exiting" or BridgeCar.state == "standing"
        or (BridgeCar.state == "going" and BridgeCar.phase == "opening")
end


function BridgeCar.withRed(red)
    if (BridgeCar.state ~= "inside" and BridgeCar.state ~= "exiting") or red == nil then return false end
    local v = nil
    pcall(function() v = red:getVehicle() end)
    return v ~= nil and v == BridgeCar.car
end

function BridgeCar.describe()
    return sformat("%s%s seat=%s%s %s", BridgeCar.state, BridgeCar.phase and ("/" .. BridgeCar.phase) or "",
        tostring(BridgeCar.seat), BridgeCar.lap and " lap" or "", tostring(BridgeCar.info))
end

local function standUp(body)
    pcall(function() BridgeMove.setCollide(body, true) end)
end


function BridgeCar.stop(why)
    if BridgeCar.state == "idle" then return end
    if Bridge.alive() and (BridgeCar.state == "going" or BridgeCar.state == "standing" or BridgeCar.state == "exiting") then
        pcall(function() BridgeMove.stopPath(Bridge.body) end)
        standUp(Bridge.body)
    end
    BridgeCar.closeDoor("stop")
    BridgeCar.release()
    BridgeCar.state, BridgeCar.phase = "idle", nil
    BridgeCar.car, BridgeCar.seat, BridgeCar.lap, BridgeCar.exit = nil, nil, false, nil
    BridgeCar.tried = {}
    movesReset()
    BridgeCar.info = "stopped: " .. tostring(why)
    log("stop: " .. tostring(why))
end


local function setInside(car, why)
    movesReset()
    BridgeCar.state, BridgeCar.phase = "inside", nil
    BridgeCar.car = car
    BridgeCar.exit = nil
    Bridge.parked = true
    BridgeCar.reserve(true)
    BridgeCar.info = "inside: " .. tostring(why)
    log(sformat("inside seat=%s%s: %s", tostring(BridgeCar.seat), BridgeCar.lap and " (lap)" or "", tostring(why)))
end


local function goInside(body, why)
    pcall(function() Bridge.saveOutfit() end)
    Bridge.hideBody(body, true)
    standUp(body)
    local car = BridgeCar.car
    setInside(car, why)
    if BridgeCar.opened ~= nil then BridgeCar.closeAt = Bridge.time + CLOSE_AFTER end
    pcall(function() Bridge.despawn() end)
    Bridge.result = "body parked: in car (" .. tostring(why) .. ")"
end


function BridgeCar.markInside(red, why)
    local car = nil
    pcall(function() car = red:getVehicle() end)
    if car == nil then return false end
    local his = nil
    pcall(function() his = car:getSeat(red) end)
    BridgeCar.tried = {}
    BridgeCar.car, BridgeCar.his = car, his
    local hx, hy = BridgeCar.doorPoint(car, his or 0)
    BridgeCar.seat, BridgeCar.lap = pick(car, his, hx, hy)
    setInside(car, why)
    return true
end


local function turnTo(body, x, y)
    pcall(function() BridgeMove.pivotToward(body, x, y, PIVOT_DEG) end)
end

local function say(pool)
    local text = nil
    pcall(function() text = BridgeMoments.line(pool) end)
    if text ~= nil and text ~= "" then pcall(function() Bridge.speakText(text) end) end
end


local function leave(body, why)
    movesReset()
    pcall(function() BridgeMove.stopPath(body) end)
    standUp(body)
    BridgeCar.closeDoor("left behind")
    BridgeCar.release()
    BridgeCar.state, BridgeCar.phase = "idle", nil
    BridgeCar.car, BridgeCar.seat, BridgeCar.lap = nil, nil, false
    BridgeCar.tried = {}
    Bridge.setMode("wait")
    local st = Bridge.store
    if st ~= nil then st.left = true end


    BridgeCar.leftLocal = true
    if Bridge.mp then
        pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "state", { left = true }) end)
    end
    BridgeCar.info = "left behind: " .. tostring(why)
    log("left behind: " .. tostring(why))
end


local function start(body, red, car, his)

    BridgeCar.closeDoor("another car")
    BridgeCar.state, BridgeCar.phase = "going", "walk"
    BridgeCar.lockTold = false
    BridgeCar.run, BridgeCar.at, BridgeCar.leftSaid = false, nil, nil
    movesReset()


    BridgeMove.moving = false
    BridgeCar.car, BridgeCar.his = car, his
    BridgeCar.tried = {}
    BridgeCar.since = Bridge.time
    BridgeCar.best, BridgeCar.progressAt, BridgeCar.fails = math.huge, Bridge.time, 0
    BridgeCar.reminded = false
    BridgeCar.seat, BridgeCar.lap = pick(car, his, body:getX(), body:getY())
    BridgeCar.reserve(false)
    pcall(function() BridgeFight.reset(body) end)
    pcall(function() BridgeHeal.stop("car") end)
    pcall(function() BridgeWash.stop("car") end)
    pcall(function() BridgeQueue.clear("car") end)
    Bridge.pose = nil
    Bridge.target = nil
    BridgeCar.info = "going"


    local C, wx, wy = BridgeCar.frame(car), BridgeCar.walkPoint(car, BridgeCar.seat)
    local side = -1
    if C ~= nil and wx ~= nil then side = math.abs((wy - C.cy) * C.fx - (wx - C.cx) * C.fy) end
    log(sformat("going to car %s: his seat %s, hers %s%s, d=%.1f, body half-width %.2f, door point %.2f from the axis",
        tostring(carId(car)), tostring(his), tostring(BridgeCar.seat), BridgeCar.lap and " (lap)" or "", distToCar(body, car),
        C ~= nil and C.hw or -1, side))
end


local function holdAt(body, x, y, z, fx, fy)
    pcall(function()
        body:setX(x)
        body:setY(y)
        body:setLastX(x)
        body:setLastY(y)
        local sq = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z + 0.01))
        if sq ~= nil and body:getCurrentSquare() ~= sq then body:setCurrent(sq) end
    end)
    Bridge.holdPos = { x, y, z }
    if fx ~= nil then pcall(function() body:faceLocationF(x + fx, y + fy) end) end
    pcall(function() BridgeMove.setCollide(body, false) end)
end


local function seatLost(car, red)
    if BridgeCar.lap then return false end
    local seat = BridgeCar.seat
    local occupant = nil
    pcall(function() occupant = car:getCharacter(seat) end)
    local _, his = BridgeCar.intent(red)
    if occupant ~= nil then

        if occupant == red and his ~= seat and redSwitching(red) then return false end
        return true
    end
    return his == seat
end


local function repick(body, car, why)
    movesReset()
    local was = BridgeCar.seat
    if not BridgeCar.lap then BridgeCar.tried[was] = true end
    BridgeCar.closeDoor(why)
    standUp(body)
    local _, his = BridgeCar.intent(BridgeData.owner())
    BridgeCar.his = his
    BridgeCar.seat, BridgeCar.lap = pick(car, his, body:getX(), body:getY())
    BridgeCar.phase = "walk"
    BridgeCar.best, BridgeCar.progressAt, BridgeCar.fails = math.huge, Bridge.time, 0
    BridgeCar.reserve(false)
    log(sformat("seat %s: %s, now %s%s", tostring(was), tostring(why), tostring(BridgeCar.seat), BridgeCar.lap and " (lap)" or ""))
end


local function phaseAge()
    return (BridgeCar.gt or 0) - (BridgeCar.phaseGt or 0)
end

local function setPhase(phase)
    BridgeCar.phase, BridgeCar.phaseSince, BridgeCar.phaseGt = phase, Bridge.time, BridgeCar.gt or 0
end


local function goingFrame(body, red, car, inCar)
    local seat = BridgeCar.seat
    local wx, wy = BridgeCar.walkPoint(car, seat)
    local dx, dy, dz = BridgeCar.doorPoint(car, seat)
    if wx == nil or dx == nil then


        if BridgeCar.lap then
            if inCar then goInside(body, "no door points at this car") end
            return true
        end
        BridgeCar.tried[seat] = true
        BridgeCar.seat, BridgeCar.lap = pick(car, BridgeCar.his, body:getX(), body:getY())
        return true
    end

    local mv = inCar and BridgeCar.moving(car)

    if mv and BridgeCar.phase == "opening" then
        goInside(body, "car moved while getting in")
        return true
    end


    if (mv and BridgeCar.rolling(car, body)) or BridgeCar.dodging then
        if BridgeCar.phase ~= "clear" then
            log(sformat("car moves: she stands aside, d=%.1f", distToCar(body, car)))
            BridgeCar.leftSaid = nil
        end
        BridgeCar.phase = "clear"


        if not BridgeCar.leftSaid and BridgeCar.drivesAway(car, body) then
            BridgeCar.leftSaid = true
            if BridgeCar.leftSaidAt == nil or Bridge.time - BridgeCar.leftSaidAt >= LEFT_LINE_GAP then
                BridgeCar.leftSaidAt = Bridge.time
                say("CarLeft")
                log(sformat("car drives off without her: said so, d=%.1f", distToCar(body, car)))
            end
        end

        if BridgeCar.sideStep(body, car) then
            BridgeCar.dodgeEnd = nil
        elseif not BridgeCar.dodge(body, car) then
            if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        end

        if distToCar(body, car) > LEAVE and not BridgeCar.dodging and BridgeCar.drivesAway(car, body) then
            leave(body, "car drove off")
        end
        return true
    end
    if BridgeCar.phase == "clear" then
        BridgeCar.phase = "walk"
        BridgeCar.best, BridgeCar.progressAt = math.huge, Bridge.time
        movesReset()
    end

    if seatLost(car, red) then
        repick(body, car, "seat taken by someone")
        return true
    end



    local ready = inCar and not redEntering(red) and not redExiting(red) and not redSwitching(red)
    local fx, fy = BridgeCar.forward(car)
    if BridgeCar.phase == "walk" then
        local d = math.min(distTo(body, wx, wy), distTo(body, dx, dy))

        if BridgeCar.lap and not ready and distTo(body, wx, wy) < 1.5 then
            if BridgeMove.onPath() then BridgeMove.stopPath(body) end
            turnTo(body, dx, dy)
            BridgeCar.progressAt = Bridge.time
            return true
        end


        local pathDone = not BridgeMove.pathing and BridgeMove.pathResult == tostring(BehaviorResult.Succeeded)
        if d <= ARRIVE or (pathDone and d <= ARRIVE_PATH) then
            if BridgeMove.onPath() then BridgeMove.stopPath(body) end
            BridgeCar.progressAt = Bridge.time
            if not ready then

                turnTo(body, dx, dy)
                return true
            end
            local p = doorOf(car, seat)
            if p ~= nil and locked(p) then
                setPhase("locked")


                if not BridgeCar.lockTold then
                    BridgeCar.lockTold = true
                    pcall(function() car:playPartSound(p, red, "IsLocked") end)
                    say("CarLocked")
                end
                turnTo(body, dx, dy)
                log("door locked: she waits")
                return true
            end


            if Bridge.mp then BridgeCar.reserve(false) end

            pcall(function() if BridgeWeapon.busy() then BridgeWeapon.cancelMove(body) end end)


            BridgeCar.at = { x = body:getX(), y = body:getY(), z = body:getZ() }
            holdAt(body, BridgeCar.at.x, BridgeCar.at.y, BridgeCar.at.z, nil, nil)
            openDoor(car, seat)
            setPhase("opening")
            log(sformat("at the door of seat %s, opening", tostring(seat)))
            return true
        end

        if d < (BridgeCar.best or math.huge) - 0.3 then BridgeCar.best, BridgeCar.progressAt = d, Bridge.time end
        if BridgeMove.pathResult == tostring(BehaviorResult.Failed) and not BridgeMove.pathing then
            BridgeCar.fails = (BridgeCar.fails or 0) + 1
            BridgeMove.pathResult = "none"
        end
        if Bridge.time - BridgeCar.progressAt > STALL or (BridgeCar.fails or 0) >= 2 then
            BridgeMove.stopPath(body)
            if BridgeCar.lap then

                BridgeCar.tried = {}
                repick(body, car, "cannot reach his door either")
            else
                repick(body, car, "cannot reach the door")
            end
            return true
        end


        if inCar and d > 2 then BridgeCar.run = true end
        BridgeMove.walkType = BridgeCar.run and "Run" or "Walk"
        trace(body, "to door", wx, wy)
        if not BridgeCar.goToDoor(body, car, wx, wy, dz, BridgeCar.run == true) then pcall(function() BridgeMove.goToward(body, wx, wy, dz, true) end) end
        return true
    end
    if BridgeCar.phase == "locked" then
        local p = doorOf(car, seat)
        if p == nil or not locked(p) then
            BridgeCar.phase = "walk"

            BridgeCar.best, BridgeCar.progressAt, BridgeCar.fails = math.huge, Bridge.time, 0
            movesReset()
            log("door unlocked")
            return true
        end



        local away = math.min(distTo(body, wx, wy), distTo(body, dx, dy))
        local g = BridgeCar.backGaveUp
        if away > ARRIVE_PATH + 0.5 and BridgeCar.backToDoor == nil and (g == nil or distTo(body, g.x, g.y) > 1.0) then
            BridgeCar.backToDoor = { since = Bridge.time }
            BridgeCar.backGaveUp = nil
            pcall(function() BridgeMove.stopPath(body) end)
            BridgeMove.pathResult = "none"
        end
        local b = BridgeCar.backToDoor
        if b ~= nil then
            local res = BridgeMove.pathResult
            local done = not BridgeMove.pathing and (res == tostring(BehaviorResult.Succeeded) or res == tostring(BehaviorResult.Failed))

            if done and res == tostring(BehaviorResult.Succeeded) and (BridgeMove.doorWay ~= nil or BridgeMove.gapWay ~= nil) then
                done = false
            end
            local arrived = away <= ARRIVE or (not BridgeMove.pathing and res == tostring(BehaviorResult.Succeeded) and away <= ARRIVE_PATH)
            if arrived or done or Bridge.time - b.since > BACK_MAX then
                BridgeCar.backToDoor = nil
                if not arrived then
                    pcall(function() BridgeCar.backGaveUp = { x = body:getX(), y = body:getY() } end)
                    log(sformat("back to the locked door: stays %.1f away (%s)", away, tostring(res)))
                end
            else
                BridgeMove.walkType = "Walk"
                trace(body, "to door", wx, wy)
                if not BridgeCar.goToDoor(body, car, wx, wy, dz, false) then pcall(function() BridgeMove.goToward(body, wx, wy, dz, true) end) end
                BridgeCar.progressAt = Bridge.time
                return true
            end
        end
        if BridgeMove.onPath() then BridgeMove.stopPath(body) end
        turnTo(body, dx, dy)
        if not BridgeCar.reminded and Bridge.time - BridgeCar.phaseSince > REMIND then
            BridgeCar.reminded = true
            say("CarLockedAgain")
        end
        return true
    end
    if BridgeCar.phase == "opening" then

        local at = BridgeCar.at or { x = body:getX(), y = body:getY(), z = body:getZ() }
        holdAt(body, at.x, at.y, at.z, nil, nil)
        if phaseAge() >= OPEN_TICKS then goInside(body, "got in") end
        return true
    end
    return true
end





local function exitSeat(car, red)
    local his = nil
    pcall(function() his = car:getSeat(red) end)
    local seats = BridgeCar.layout(car, BridgeCar.doorPoint(car, his or 0))
    local byI = {}
    for _, s in ipairs(seats) do byI[s.i] = s end
    local function free(s)
        return s ~= nil and not s.driver and s.i ~= his and s.installed and not s.person and not s.blocked and not s.nodoor
    end
    if not BridgeCar.lap and free(byI[BridgeCar.seat]) then return BridgeCar.seat, false, his end
    table.sort(seats, function(a, b) return a.d < b.d end)
    for _, s in ipairs(seats) do
        if free(s) and not s.reserved then return s.i, false, his end
    end
    return his or 0, true, his
end

local function beginExit(red, car, why)
    local seat, lap, his = exitSeat(car, red)
    local x, y, z = BridgeCar.doorPoint(car, seat)
    local fx, fy = BridgeCar.forward(car)
    if x == nil then

        BridgeCar.stop("no door point")
        Bridge.parked = false
        if BridgeData.wants(Bridge.store) then pcall(function() Bridge.spawnZombie() end) end
        return
    end
    BridgeCar.state, BridgeCar.phase = "exiting", lap and "lap" or "spawn"
    BridgeCar.seat, BridgeCar.lap = seat, lap
    BridgeCar.exit = { car = car, seat = seat, lap = lap, his = his, x = x, y = y, z = z, fx = fx, fy = fy,
                       since = Bridge.time, gt = BridgeCar.gt or 0, asked = false }
    BridgeCar.info = "exiting: " .. tostring(why)
    log(sformat("exit via seat %s%s: %s", tostring(seat), lap and " (lap, after him)" or "", tostring(why)))
end




local function besideHim(car, red, z)
    local cx, cy, x, y = nil, nil, nil, nil
    pcall(function() cx, cy, x, y = car:getX(), car:getY(), red:getX(), red:getY() end)
    local fx, fy = BridgeCar.forward(car)
    if cx == nil or x == nil or fx == nil then return nil end
    local ox, oy = x - cx, y - cy
    local ol = math.sqrt(ox * ox + oy * oy)
    if ol < 1e-3 then return nil end
    ox, oy = ox / ol, oy / ol
    for _, d in ipairs({ { ox, oy }, { -fx, -fy }, { fx, fy } }) do
        local tx, ty = x + d[1] * 1.0, y + d[2] * 1.0
        local ok = false
        pcall(function() ok = Bridge.standSquareOk(getCell():getGridSquare(math.floor(tx), math.floor(ty), math.floor(z + 0.01))) end)
        if ok then return tx, ty end
    end
    return nil
end



function BridgeCar.doorSquare(car, seat)
    local wx, wy = BridgeCar.walkPoint(car, seat)
    if wx == nil or wy == nil then return nil end
    local cx, cy, z = nil, nil, 0
    pcall(function() cx, cy, z = car:getX(), car:getY(), car:getZ() end)
    if cx == nil then return nil end
    local ox, oy = wx - cx, wy - cy
    local ol = math.sqrt(ox * ox + oy * oy)
    if ol > 1e-3 then ox, oy = ox / ol, oy / ol else ox, oy = 0, 0 end

    local base = nil
    pcall(function() base = getCell():getGridSquare(math.floor(wx), math.floor(wy), math.floor(z + 0.01)) end)
    if base == nil then return nil end
    local baseRoom, prev = roomOf(base), base
    for _, k in ipairs({ 0, 1.0, 1.5, 2.0 }) do
        local sq = nil
        pcall(function() sq = getCell():getGridSquare(math.floor(wx + ox * k), math.floor(wy + oy * k), math.floor(z + 0.01)) end)
        if sq == nil or roomOf(sq) ~= baseRoom then return nil end
        if Bridge.standSquareOk(sq, sq ~= prev and prev or nil) then return sq end
        if sq ~= prev then
            local blocked = false
            pcall(function() blocked = prev:isBlockedTo(sq) end)
            if blocked then return nil end
        end
        prev = sq
    end
    return nil
end

local function exitSpawn(red)
    local e = BridgeCar.exit
    if e == nil or e.asked then return end

    if not BridgeData.wants(Bridge.store) then
        BridgeCar.stop("she said goodbye")
        Bridge.parked = false
        return
    end



    if not Bridge.mp and not e.lap then
        local inCar = true
        pcall(function() inCar = red:getVehicle() ~= nil end)
        if inCar then return end
    end
    if e.lap then
        local inCar = true
        pcall(function() inCar = red:getVehicle() ~= nil end)
        if inCar or redEntering(red) then return end
        e.outAt = e.outAt or Bridge.time
        if distTo(red, e.x, e.y) < LAP_STEP then
            if Bridge.time - e.outAt < 60 then return end

            local bx, by = besideHim(e.car, red, e.z)
            if bx ~= nil then e.x, e.y = bx, by end
        end
    end
    e.asked = true
    e.askedAt = Bridge.time


    local res = "?"
    pcall(function() res = Bridge.spawnZombie(e.x, e.y, e.z) end)
    Bridge.parked = false
    log("body asked at the door: " .. tostring(res))
end



local function exitFrame(body, red)
    local e = BridgeCar.exit
    if e == nil then BridgeCar.stop("exit lost") return false end
    if BridgeCar.state == "exiting" then
        holdAt(body, e.x, e.y, e.z, e.fx, e.fy)
        if not e.bumpAt then


            local out = true
            pcall(function() out = red:getVehicle() == nil end)
            if not out then
                e.redOutGt = nil
                return true
            end
            if e.redOutGt == nil then
                e.redOutGt = BridgeCar.gt or 0
                log(sformat("he is out of the car: %.0f game ticks after his exit began", e.redOutGt - (e.gt or 0)))
            end
            if (BridgeCar.gt or 0) - e.redOutGt < AFTER_HIM then return true end

            local ready, why = true, "shown"
            if Bridge.hiddenSince ~= nil then
                local okReady, r, w = pcall(Bridge.showReady, body)
                if okReady then
                    ready, why = r, w
                else
                    ready, why = Bridge.tick - Bridge.hiddenSince >= 90, "showReady failed: " .. tostring(r)
                end
            end
            if not ready then return true end
            openDoor(e.car, e.seat)
            Bridge.hideBody(body, false)
            Bridge.hiddenSince = nil
            Bridge.greetOnReveal = nil
            e.bumpAt = Bridge.time


            BridgeCar.reserve(false)
            BridgeCar.state = "standing"
            setPhase("standing")
            log(sformat("got out at the door: %s, %.0f game ticks after him", tostring(why), (BridgeCar.gt or 0) - (e.redOutGt or 0)))
        end
        return true
    end

    holdAt(body, e.x, e.y, e.z, nil, nil)
    if phaseAge() >= OUT_TICKS then
        standUp(body)
        Bridge.holdPos = nil

        BridgeCar.closeDoor("got out")
        BridgeCar.release()
        BridgeCar.state, BridgeCar.phase = "idle", nil
        BridgeCar.car, BridgeCar.exit = nil, nil
        BridgeCar.tried = {}
        BridgeCar.info = "got out"
        movesReset()
        log("got out")
        return false
    end
    return true
end





function BridgeCar.update(body)
    local red = BridgeData.owner()
    if red == nil then return false end
    if BridgeCar.state == "exiting" or BridgeCar.state == "standing" then return exitFrame(body, red) end
    if BridgeCar.state == "inside" then
        local v = nil
        pcall(function() v = red:getVehicle() end)
        if v ~= nil and v == BridgeCar.car then


            Bridge.hideBody(body, true)
            pcall(function() Bridge.despawn() end)
            log("body came while she is in the car: removed")
            return true
        end

        BridgeCar.stop("body back while inside")
        Bridge.parked = false
        return false
    end
    if Bridge.mode ~= "follow" then
        if BridgeCar.state ~= "idle" then BridgeCar.stop("mode " .. tostring(Bridge.mode)) end

        local v = nil
        pcall(function() v = red:getVehicle() end)
        if BridgeCar.dodge(body, v) then return true end
        return false
    end
    local car, his, inCar = BridgeCar.intent(red)
    if car == nil then
        if BridgeCar.state ~= "idle" then BridgeCar.stop("he is not getting into a car") end
        return false
    end

    if Bridge.leaveAt ~= nil or not BridgeData.wants(Bridge.store) then
        if BridgeCar.state ~= "idle" then BridgeCar.stop("she is leaving") end
        return false
    end
    if BridgeCar.state ~= "going" or car ~= BridgeCar.car then start(body, red, car, his) end

    if his ~= BridgeCar.his then
        BridgeCar.his = his
        if BridgeCar.phase == "walk" then
            BridgeCar.seat, BridgeCar.lap = pick(car, his, body:getX(), body:getY())
            BridgeCar.reserve(false)
        end
    end


    local waiting = BridgeCar.phase == "locked" or (BridgeCar.phase == "walk" and (not inCar or redEntering(red)))
    if waiting then
        local okF, fighting = pcall(function() return BridgeFight.update(body) end)
        if okF and fighting then
            BridgeCar.progressAt = Bridge.time
            BridgeCar.backToDoor, BridgeCar.backGaveUp = nil, nil
            return true
        end
    elseif BridgeFight.target ~= nil or BridgeFight.state == "swing" then

        pcall(function() BridgeFight.reset(body) end)
        log("he is in the car: fight dropped, to the door")
    end
    local ok, res = pcall(goingFrame, body, red, car, inCar)
    if not ok then
        warn("going failed: " .. tostring(res))
        BridgeCar.stop("error")
        return false
    end
    return res == true
end


function BridgeCar.tick()
    local mult = 1
    pcall(function() mult = getGameTime():getTrueMultiplier() end)
    if type(mult) ~= "number" or mult ~= mult or mult < 1 then mult = 1 end
    if mult > 60 then mult = 60 end
    BridgeCar.gt = (BridgeCar.gt or 0) + (Bridge.dt or 1) * mult
    if BridgeCar.closeAt ~= nil and Bridge.time >= BridgeCar.closeAt then BridgeCar.closeDoor("done") end
    local red = BridgeData.owner()
    if red == nil then return end
    local dead = false
    pcall(function() dead = red:isDead() end)
    if dead then
        if BridgeCar.state ~= "idle" then BridgeCar.stop("he died") end
        return
    end
    if BridgeCar.state == "inside" then
        local v = nil
        pcall(function() v = red:getVehicle() end)
        if v == nil then


            if BridgeCar.car ~= nil and distToCar(red, BridgeCar.car) < 12 then
                beginExit(red, BridgeCar.car, "he is out")
                exitSpawn(red)
            else
                BridgeCar.stop("he is out far from the car")
                Bridge.parked = false
                if BridgeData.wants(Bridge.store) then pcall(function() Bridge.spawnZombie() end) end
            end
            return
        end
        if v ~= BridgeCar.car then
            BridgeCar.markInside(red, "other car")
            return
        end




        if redExiting(red) and not BridgeCar.moving(v) and not redSwitching(red) then
            beginExit(red, v, "he gets out")
            exitSpawn(red)
        end
        return
    end
    if BridgeCar.state == "exiting" then
        local e = BridgeCar.exit
        if e == nil then BridgeCar.stop("exit lost") return end
        exitSpawn(red)

        if BridgeCar.state ~= "exiting" then return end



        if Bridge.alive() and not Bridge.drivable() then
            Bridge.hideBody(Bridge.body, false)
            Bridge.hiddenSince = nil
            BridgeCar.stop("body driven by another client")
            return
        end

        local v = nil
        pcall(function() v = red:getVehicle() end)


        if v ~= nil and v ~= e.car then
            BridgeCar.closeDoor("he is in another car")
            if Bridge.alive() then
                Bridge.hideBody(Bridge.body, true)
                pcall(function() Bridge.despawn() end)
            end
            BridgeCar.markInside(red, "he is in another car before she showed")
            return
        end
        if v == e.car and not redExiting(red) and not redSwitching(red) and Bridge.time - e.since > CANCEL then

            BridgeCar.closeDoor("he stayed")
            setInside(e.car, "he stayed in the car")
            if Bridge.alive() then
                Bridge.hideBody(Bridge.body, true)
                pcall(function() Bridge.despawn() end)
            end

            return
        end
        if e.askedAt ~= nil and not Bridge.alive() and Bridge.time - e.askedAt > SPAWN_WAIT then
            BridgeCar.stop("body did not come")
        end
        return
    end


    if BridgeCar.state == "standing" and not Bridge.alive() then
        BridgeCar.stop("body gone while standing at the door")
        return
    end
    if BridgeCar.state == "standing" and not Bridge.drivable() then
        BridgeCar.stop("body driven by another client at the door")
        return
    end


    if Bridge.mp and (BridgeCar.state == "idle" or BridgeCar.state == "going") and Bridge.mode == "follow"
        and Bridge.alive() and not Bridge.drivable() and Bridge.leaveAt == nil and BridgeData.wants(Bridge.store) then
        local v = nil
        pcall(function() v = red:getVehicle() end)
        if v ~= nil and not redEntering(red) and not redSwitching(red) and not redExiting(red) then
            pcall(function() Bridge.saveOutfit() end)
            Bridge.parked = true
            Bridge.hideBody(Bridge.body, true)
            pcall(function() Bridge.despawn() end)
            BridgeCar.markInside(red, "body driven by another client")
            return
        end
    end


    if BridgeCar.state == "idle" and Bridge.store ~= nil and Bridge.store.car ~= nil and Bridge.every(60, 13) then
        local v = nil
        pcall(function() v = red:getVehicle() end)
        if v == nil then
            log("stale car seat record cleared")
            BridgeCar.release()
        end
    end
    if BridgeCar.state == "going" and not Bridge.alive() then
        BridgeCar.lostAt = BridgeCar.lostAt or Bridge.time

        local other = Bridge.stash ~= nil or Bridge.leaveAt ~= nil or Bridge.sleepParked ~= nil
            or Bridge.claimParked ~= nil or not BridgeData.wants(Bridge.store)
        if other then
            BridgeCar.stop("body taken away otherwise")
            BridgeCar.lostAt = nil
        elseif BridgeCar.phase == "opening" then
            setInside(BridgeCar.car, "body gone at the door")
            if BridgeCar.opened ~= nil then BridgeCar.closeAt = Bridge.time + CLOSE_AFTER end
            BridgeCar.lostAt = nil
        elseif Bridge.time - BridgeCar.lostAt > 300 then
            BridgeCar.stop("no body")
            BridgeCar.lostAt = nil
        end
        return
    end
    BridgeCar.lostAt = nil



    if BridgeCar.state == "going" and Bridge.drivable() and Bridge.every(60, 21)
        and distToCar(Bridge.body, BridgeCar.car) > 20 and not BridgeCar.moving(BridgeCar.car) then
        log("far from the car, brought to him")


        local sq = BridgeCar.doorSquare(BridgeCar.car, BridgeCar.seat)
        if sq == nil then
            local n = 0
            pcall(function() n = BridgeCar.car:getMaxPassengers() end)
            for i = 0, n - 1 do
                if sq == nil and i ~= BridgeCar.seat then sq = BridgeCar.doorSquare(BridgeCar.car, i) end
            end
        end
        if sq ~= nil then
            pcall(function() Bridge.teleportToRed(sq) end)
        else
            log("far from the car: no square by its doors, not brought")
        end
        BridgeCar.progressAt = Bridge.time
    end

    local st = Bridge.store
    if st ~= nil and (st.left or BridgeCar.leftLocal) and Bridge.mode == "wait" and Bridge.drivable() and Bridge.every(30, 7) then
        local body = Bridge.body
        local v = nil
        pcall(function() v = red:getVehicle() end)
        local back = false
        if v ~= nil then
            back = not BridgeCar.moving(v) and distToCar(body, v) <= RETURN
        else
            back = distToCar(body, red) <= FOOT
        end
        if back then
            log(v ~= nil and "he came back by car" or "he came back on foot")
            BridgeCar.leftLocal = nil
            Bridge.setMode("follow")
        end
    end
end

if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeCar] loaded") end

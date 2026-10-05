





BridgeAim = BridgeAim or {}

local AIM_ASIDE_ON = 0

local AIM_BEHIND         = 2.0
local AIM_PAST           = 0.8
local AIM_TRIGGER_W      = 2.5
local AIM_RANGE          = 12
local AIM_Z_TOL          = 0.5
local AIM_QUIET          = 90
local AIM_TARGET_PENALTY = 30

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeAim] " .. tostring(text)) end end
local function vlog(text) if Bridge ~= nil and Bridge.verbose then log(text) end end
local function dist2d(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

BridgeAim.tempVec2 = nil
BridgeAim.zone = { tick = -1, on = false, red = nil, px = 0, py = 0, pz = 0,
    vx = 0, vy = 0, range = AIM_RANGE, half = AIM_TRIGGER_W }
BridgeAim.wasIn = false
BridgeAim.relocating = false
BridgeAim.staySpot = nil
BridgeAim.quietUntil = 0
BridgeAim.info = "none"
BridgeAim.TARGET_PENALTY = AIM_TARGET_PENALTY

local function isBodyZ(z)
    local marked = false
    pcall(function() marked = z.getVariableBoolean ~= nil and z:getVariableBoolean("NotAloneBody") == true end)
    return marked
end
BridgeAim.isBodyZ = isBodyZ

local function aimingGun(red)
    if red.isAiming == nil then return false end
    local aiming = false
    pcall(function() aiming = red:isAiming() == true end)
    if not aiming then return false end
    local item = nil
    if red.getPrimaryHandItem ~= nil then
        pcall(function() item = red:getPrimaryHandItem() end)
    end
    if item == nil and red.getSecondaryHandItem ~= nil then
        pcall(function() item = red:getSecondaryHandItem() end)
    end
    if item == nil then return false end
    local ranged = false
    pcall(function() ranged = instanceof(item, "HandWeapon") and item:isRanged() == true end)
    return ranged
end

function BridgeAim.refresh(red)
    local Z = BridgeAim.zone
    if Bridge == nil or Bridge.tick == Z.tick then return Z end
    Z.tick = Bridge.tick
    Z.on = false
    Z.red = nil
    if AIM_ASIDE_ON == 0 or red == nil then return Z end
    if Bridge.alive ~= nil and not Bridge.alive() then return Z end
    local inCar = false
    pcall(function() inCar = red:getVehicle() ~= nil end)
    if inCar then return Z end
    if not aimingGun(red) then return Z end
    if BridgeAim.tempVec2 == nil then
        if Vector2 == nil or Vector2.new == nil then return Z end
        BridgeAim.tempVec2 = Vector2.new()
    end
    if red.getAimVector == nil then return Z end
    local v = nil
    pcall(function() v = red:getAimVector(BridgeAim.tempVec2) end)
    if v == nil then return Z end
    local vx, vy = 0, 0
    pcall(function() vx, vy = v:getX(), v:getY() end)
    local vl = math.sqrt(vx * vx + vy * vy)
    if vl < 0.01 then return Z end
    Z.on = true
    Z.red = red
    Z.px, Z.py, Z.pz = red:getX(), red:getY(), red:getZ()
    Z.vx, Z.vy = vx / vl, vy / vl
    Z.range, Z.half = AIM_RANGE, AIM_TRIGGER_W
    return Z
end

function BridgeAim.inCone(x, y, z)
    local Z = BridgeAim.zone
    if not Z.on then return false end
    if math.abs(z - Z.pz) > AIM_Z_TOL then return false end
    local ox, oy = x - Z.px, y - Z.py
    local ahead = Z.vx * ox + Z.vy * oy
    local side = -Z.vy * ox + Z.vx * oy
    if ahead <= 0 or ahead >= Z.range then return false end
    return math.abs(side) < Z.half
end

function BridgeAim.needsBehind(x, y, z)
    local Z = BridgeAim.zone
    if not Z.on or Z.red == nil then return false end
    if math.abs(z - Z.pz) > AIM_Z_TOL then return false end
    local ox, oy = x - Z.px, y - Z.py
    local ahead = Z.vx * ox + Z.vy * oy
    local side = -Z.vy * ox + Z.vx * oy
    if ahead <= -AIM_PAST then return false end
    if ahead >= Z.range then return false end
    if not BridgeAim.relocating and math.abs(side) >= Z.half then return false end
    return true
end

function BridgeAim.beyond(body)
    local Z = BridgeAim.zone
    if not Z.on or body == nil then return false end
    local ha = nil
    pcall(function()
        local ox, oy = body:getX() - Z.px, body:getY() - Z.py
        ha = Z.vx * ox + Z.vy * oy
    end)
    if ha == nil then return false end
    local found = false
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z ~= body and not isBodyZ(z) then
                local alive = false
                pcall(function() alive = z:isAlive() and z:getHealth() > 0 end)
                if alive and not BridgeData.harmless(z) then
                    local ox, oy = z:getX() - Z.px, z:getY() - Z.py
                    local a = Z.vx * ox + Z.vy * oy
                    local side = -Z.vy * ox + Z.vx * oy
                    if a > ha + 0.5 and a < Z.range and math.abs(side) < Z.half then
                        found = true
                        return
                    end
                end
            end
        end
    end)
    return found
end

function BridgeAim.pointClear(body, x, y, z)
    local ok = false
    pcall(function()
        local sq = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z))
        ok = sq ~= nil and sq:isFree(false)
    end)
    return ok
end

local function findBehind(body, Z, bz, sgn)
    local cands = {
        { 2.0, 1.8 * sgn }, { 2.0, 0.0 }, { 2.0, -1.8 * sgn },
        { 3.0, 1.8 * sgn }, { 3.0, 0.0 },
        { 1.6, 1.4 * sgn }, { 1.6, 0.0 },
    }
    for i = 1, #cands do
        local d, s = cands[i][1], cands[i][2]
        local tx = Z.px - Z.vx * d - Z.vy * s
        local ty = Z.py - Z.vy * d + Z.vx * s
        if BridgeAim.pointClear(body, tx, ty, bz) then return tx, ty end
    end
    return nil
end

function BridgeAim.step(body, red)
    if AIM_ASIDE_ON == 0 or body == nil or red == nil then return false end
    local Z = BridgeAim.refresh(red)
    if Bridge.mourning ~= nil or Bridge.hiddenSince ~= nil then return false end

    if not Z.on then
        local s = BridgeAim.staySpot
        if s == nil or (Bridge ~= nil and Bridge.mode == "follow") then
            BridgeAim.staySpot = nil
            BridgeAim.wasIn = false
            return false
        end
        local sx, sy = body:getX() - s.x, body:getY() - s.y
        if (sx * sx + sy * sy) <= 0.49 then
            BridgeAim.staySpot = nil
            BridgeAim.wasIn = false
            BridgeMove.moving = false
            return false
        end
        if Bridge.target ~= nil then Bridge.target = nil end
        local moved = false
        pcall(function()
            BridgeMove.walkType = "Walk"
            BridgeMove.applyAnimVars(body)
            BridgeMove.steering = true
            BridgeMove.followWs = 1.0
            BridgeMove.followBump(body, "Walk")
            BridgeMove.goToward(body, s.x, s.y, s.z)
            moved = true
        end)
        BridgeMove.moving = true
        BridgeAim.info = "returning"
        return moved
    end

    local bx, by, bz = body:getX(), body:getY(), body:getZ()
    if not BridgeAim.needsBehind(bx, by, bz) then
        BridgeAim.relocating = false
        BridgeAim.wasIn = false
        if Z.on and Bridge ~= nil and Bridge.mode ~= nil and Bridge.mode ~= "follow" then
            if BridgeMove.onPath ~= nil and BridgeMove.onPath() then
                pcall(function() BridgeMove.stopPath(body) end)
            end
            BridgeMove.moving = false
            BridgeAim.info = "holding"
            return true
        end
        return false
    end
    BridgeAim.relocating = true

    if not BridgeAim.wasIn then
        BridgeAim.wasIn = true
        if Bridge ~= nil and Bridge.mode ~= nil and Bridge.mode ~= "follow" then
            BridgeAim.staySpot = { x = bx, y = by, z = bz }
        end
        if BridgeCallout ~= nil then BridgeCallout.pendingKill = nil end
        if Bridge.time >= BridgeAim.quietUntil then
            BridgeAim.quietUntil = Bridge.time + AIM_QUIET
            local onMe = not BridgeAim.beyond(body)
            if BridgeCallout ~= nil and BridgeCallout.aimClear ~= nil then
                pcall(function() BridgeCallout.aimClear(onMe) end)
            end
            vlog("aim: in the line, getting behind " .. (onMe and "(on me)" or ""))
        end
    end

    local ox, oy = bx - Z.px, by - Z.py
    local sgn = (-Z.vy * ox + Z.vx * oy < 0) and -1 or 1
    local tx, ty = findBehind(body, Z, bz, sgn)
    if tx == nil then
        BridgeAim.info = "nowhere behind"
        return false
    end

    local moved = false
    local d = dist2d(bx, by, Z.px, Z.py)
    local walk = (d > 3.5) and "Run" or "Walk"
    pcall(function()
        BridgeMove.walkType = walk
        BridgeMove.applyAnimVars(body)
        BridgeMove.steering = true
        BridgeMove.followWs = 1.0
        BridgeMove.followBump(body, walk)
        BridgeMove.goToward(body, tx, ty, bz)
        moved = true
    end)
    BridgeMove.moving = true
    BridgeMove.pathResult = "aim-behind"
    BridgeAim.info = moved and "behind" or "move failed"
    if Bridge.time - (BridgeAim.dbgAt or -99999) >= 120 then
        BridgeAim.dbgAt = Bridge.time
        local ox2, oy2 = bx - Z.px, by - Z.py
            log(string.format("in line ahead=%.2f side=%.2f -> behind %.2f,%.2f (%.2f tiles) %s",
            Z.vx * ox2 + Z.vy * oy2, -Z.vy * ox2 + Z.vx * oy2, tx, ty, dist2d(bx, by, tx, ty), BridgeAim.info))
    end
    return moved
end

log("loaded")

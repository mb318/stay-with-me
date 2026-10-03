


BridgeGun = BridgeGun or {}
BridgeGun.enabled = true
BridgeGun.installed = false
BridgeGun.ticks = 0
BridgeGun.metrics = { installs = 0, damage = 0, kill = 0, targets = 0, blasts = 0, blastRepair = 0, blastFail = 0 }

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeGun] " .. tostring(text)) end end
local function warn(text) print("[BridgeGun] " .. tostring(text)) end
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

local function ours(z)
    if z == nil then return false end
    if Bridge ~= nil and Bridge.body ~= nil and z == Bridge.body then return true end
    local marked = false
    pcall(function() marked = z.getVariableBoolean ~= nil and z:getVariableBoolean("NotAloneBody") == true end)
    if marked then return true end
    local md = false
    pcall(function() md = z.getModData ~= nil and z:getModData().ST_Ignore == true end)
    return md
end
BridgeGun.ours = ours

local function core()
    local ok, module = pcall(require, "Advanced_trajectory_core")
    if ok and type(module) == "table" and type(module.damageZombie) == "function" then return module end
    return nil
end

function BridgeGun.nearBlast(body, sq, info)
    local near = false
    pcall(function()
        if body == nil or sq == nil then return end
        if math.abs(math.floor(body:getZ()) - math.floor(sq:getZ())) > 1 then return end
        local range = 10
        local r = tonumber(info and info[3])
        if r ~= nil and r > 0 then range = math.max(range, r + 2) end
        local dx, dy = body:getX() - sq:getX(), body:getY() - sq:getY()
        near = dx * dx + dy * dy <= range * range
    end)
    return near
end

function BridgeGun.shieldBlast(body, boom, sq, info)
    local list, removed = nil, false
    pcall(function()
        local square = body:getCurrentSquare()
        if square == nil then return end
        list = square:getMovingObjects()
        if list == nil then return end
        local index = list:indexOf(body)
        if index ~= nil and index >= 0 then
            list:remove(body)
            removed = true
        end
    end)
    local ok, err = pcall(boom, sq, info)
    if removed then
        pcall(function()
            if list:indexOf(body) < 0 then list:add(body) end
        end)
        local back = false
        pcall(function() back = list:indexOf(body) >= 0 end)
        if not back then
            BridgeGun.metrics.blastRepair = BridgeGun.metrics.blastRepair + 1
            pcall(function() body:addToWorld() end)
        end
    end
    if not ok then
        BridgeGun.metrics.blastFail = BridgeGun.metrics.blastFail + 1
        warnOnce("blast guard failed: " .. tostring(err))
    else
        BridgeGun.metrics.blasts = BridgeGun.metrics.blasts + 1
    end
    return ok
end

function BridgeGun.install()
    if BridgeGun.installed then return true end
    local t = core()
    if t == nil then return false end
    if type(t.damageZombie) ~= "function" or type(t.killZombie) ~= "function" then return false end
    local damage, kill = t.damageZombie, t.killZombie
    t.damageZombie = function(zombie, ...)
        if ours(zombie) then
            BridgeGun.metrics.damage = BridgeGun.metrics.damage + 1
            return
        end
        return damage(zombie, ...)
    end
    t.killZombie = function(zombie, ...)
        if ours(zombie) then
            BridgeGun.metrics.kill = BridgeGun.metrics.kill + 1
            return
        end
        return kill(zombie, ...)
    end
    if type(t.searchTargetNearBullet) == "function" then
        local search = t.searchTargetNearBullet
        t.searchTargetNearBullet = function(bulletTable, playerTable, missedShot)
            local target, kind = search(bulletTable, playerTable, missedShot)
            if ours(target) then
                BridgeGun.metrics.targets = BridgeGun.metrics.targets + 1
                return nil, nil
            end
            return target, kind
        end
    end
    if type(t.Boom) == "function" then
        local boom = t.Boom
        t.Boom = function(sq, info)
            local body = Bridge ~= nil and Bridge.body or nil
            if body == nil or not BridgeGun.nearBlast(body, sq, info) then return boom(sq, info) end
            return BridgeGun.shieldBlast(body, boom, sq, info)
        end
    end
    BridgeGun.installed = true
    BridgeGun.metrics.installs = BridgeGun.metrics.installs + 1
    log("Advanced Trajectory found: companion bullets and blasts handled")
    return true
end

function BridgeGun.tick()
    if not BridgeGun.enabled or BridgeGun.installed then return end
    BridgeGun.ticks = BridgeGun.ticks + 1
    if BridgeGun.ticks > 1 and BridgeGun.ticks % 60 ~= 0 then return end
    BridgeGun.install()
end

Events.OnTick.Add(function() pcall(BridgeGun.tick) end)
Events.OnGameStart.Add(function()
    BridgeGun.ticks = 0
    pcall(BridgeGun.tick)
end)

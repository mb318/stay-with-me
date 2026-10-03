




























BridgeRemnant = BridgeRemnant or {}

local MARK = 32768
local KEY = "NotAloneIssued"
local MAX = 1000
local HELD_MAX = 40

BridgeRemnant.created = {}
BridgeRemnant.held = {}
BridgeRemnant.nakedIdx = nil
BridgeRemnant.removed = 0

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeRemnant] " .. tostring(text)) end end
local function warn(text) print("[BridgeRemnant] " .. tostring(text)) end

local function unsigned(id)
    if id < 0 then return id + 4294967296 end
    return id
end


function BridgeRemnant.hasMark(id)
    if type(id) ~= "number" then return false end
    return math.floor(unsigned(id) / MARK) % 2 == 1
end


function BridgeRemnant.markId(id)
    if type(id) ~= "number" or id == 0 then return nil end
    if BridgeRemnant.hasMark(id) then return id end
    return id + MARK
end


function BridgeRemnant.outfitIdx(id)
    if type(id) ~= "number" then return nil end
    return math.floor(unsigned(id) / 65536) % 32768
end

local function store()
    local s = ModData.getOrCreate(KEY)
    if type(s.ids) ~= "table" then s.ids = {} end
    return s
end

local function issuedMap()
    local s = store()
    if BridgeRemnant.mapOf == s and BridgeRemnant.map ~= nil then return BridgeRemnant.map end
    local map = {}
    for _, e in ipairs(s.ids) do
        if type(e) == "table" and e.id ~= nil then map[e.id] = e end
    end
    BridgeRemnant.map, BridgeRemnant.mapOf = map, s
    return map
end

local function issue(id)
    local s = store()
    local map = issuedMap()
    local e = map[id]
    if e == nil then
        e = { id = id }
        table.insert(s.ids, e)
        map[id] = e
        while #s.ids > MAX do
            local old = table.remove(s.ids, 1)
            if old ~= nil and old.id ~= nil then map[old.id] = nil end
        end
    end
    e.who = BridgeData ~= nil and BridgeData.LOCAL or "local"
    pcall(function() e.t = getGameTime():getWorldAgeHours() end)
end


local function modsKey()
    local key = nil
    pcall(function()
        local mods = getActivatedMods()
        local parts = {}
        for i = 0, mods:size() - 1 do parts[#parts + 1] = tostring(mods:get(i)) end
        key = table.concat(parts, ";")
    end)
    return key
end



local function nakedIdxNow()
    if BridgeRemnant.nakedIdx ~= nil then return BridgeRemnant.nakedIdx end
    local s = store()
    local key = modsKey()
    if s.nakedIdx ~= nil and key ~= nil and s.mods == key then return s.nakedIdx end
    return nil
end

local function listed(z)
    local found = false
    pcall(function() found = getCell():getZombieList():contains(z) end)
    return found
end

local function where(z)
    local text = ""
    pcall(function() text = string.format(" at %.1f %.1f %.0f", z:getX(), z:getY(), z:getZ()) end)
    return text
end


local function judge(p, idx)
    local z, pid = p.z, p.pid
    local at = where(z)



    if Bridge ~= nil and z == Bridge.body then
        log("id=" .. tostring(pid) .. " came on the object of the current body: body reference dropped" .. at)
        Bridge.body = nil
        Bridge.kind = nil
    end
    local now = nil
    pcall(function() now = z:getPersistentOutfitID() end)
    if now ~= pid then
        log("id=" .. tostring(pid) .. " object already reused (now " .. tostring(now) .. "), left" .. at)
        return false
    end
    local dead = false
    pcall(function() dead = z:isDead() end)
    if dead then
        log("id=" .. tostring(pid) .. " is dead, left" .. at)
        return false
    end


    if not listed(z) then
        log("id=" .. tostring(pid) .. " not in zombie list, left" .. at)
        return false
    end

    if BridgeData ~= nil and BridgeData.foreign(z) then
        log("id=" .. tostring(pid) .. " is a body of another NPC mod, left" .. at)
        return false
    end
    if BridgeRemnant.outfitIdx(pid) ~= idx then
        log(string.format("id=%s outfit place %s, Naked is at %s now: outfit list changed, left%s",
            tostring(pid), tostring(BridgeRemnant.outfitIdx(pid)), tostring(idx), at))
        return false
    end


    if Bridge ~= nil and Bridge.touched ~= nil and Bridge.touched[z] ~= nil then
        pcall(function() Bridge.unhumanize(z, true) end)
    end
    pcall(function() z:removeFromSquare() end)
    pcall(function() z:removeFromWorld() end)
    BridgeRemnant.removed = BridgeRemnant.removed + 1
    log(string.format("removed remnant body id=%s%s tick=%s total=%d",
        tostring(pid), at, tostring(Bridge ~= nil and Bridge.tick or "?"), BridgeRemnant.removed))
    return true
end



function BridgeRemnant.mark(body)
    if body == nil or (Bridge ~= nil and Bridge.mp) then return nil end
    local pid, init = nil, true
    pcall(function() pid = body:getPersistentOutfitID() end)


    pcall(function() init = body:isPersistentOutfitInit() end)
    local marked = BridgeRemnant.markId(pid)
    if marked == nil then
        log("body not marked: outfit id " .. tostring(pid))
        return nil
    end
    pcall(function() body:setPersistentOutfitID(marked, init) end)
    local now = nil
    pcall(function() now = body:getPersistentOutfitID() end)
    if now ~= marked then
        log("body not marked: id stayed " .. tostring(now) .. ", wanted " .. tostring(marked))
        return nil
    end
    issue(marked)
    local s = store()
    BridgeRemnant.nakedIdx = BridgeRemnant.outfitIdx(marked)
    s.nakedIdx = BridgeRemnant.nakedIdx
    s.mods = modsKey()
    log("body id=" .. tostring(marked) .. " issued, Naked place " .. tostring(BridgeRemnant.nakedIdx))

    local held = BridgeRemnant.held
    BridgeRemnant.held = {}
    for _, p in ipairs(held) do

        if p.z ~= body then judge(p, BridgeRemnant.nakedIdx) end
    end
    return marked
end




function BridgeRemnant.onZombieCreate(z)
    if z == nil or (Bridge ~= nil and Bridge.mp) then return end
    local pid = nil
    pcall(function() pid = z:getPersistentOutfitID() end)
    if not BridgeRemnant.hasMark(pid) then return end
    local ok, known = pcall(function() return issuedMap()[pid] ~= nil end)
    if not ok or not known then return end
    BridgeRemnant.created[#BridgeRemnant.created + 1] = { z = z, pid = pid }
end


function BridgeRemnant.sweep()
    local list = BridgeRemnant.created
    if #list == 0 then return end
    BridgeRemnant.created = {}
    if Bridge ~= nil and Bridge.mp then return end
    local idx = nakedIdxNow()
    for _, p in ipairs(list) do
        if idx ~= nil then
            judge(p, idx)
        else

            local held = BridgeRemnant.held
            held[#held + 1] = p
            while #held > HELD_MAX do table.remove(held, 1) end
            log("id=" .. tostring(p.pid) .. " held: Naked place unknown until the body appears" .. where(p.z))
        end
    end
end

Events.OnZombieCreate.Add(function(z) pcall(BridgeRemnant.onZombieCreate, z) end)
Events.OnTick.Add(function() pcall(BridgeRemnant.sweep) end)



























if not isServer() then return end

BridgeServer = BridgeServer or {}
BridgeServer.version = 36
BridgeServer.bodies = {}
BridgeServer.missing = {}
BridgeServer.offline = {}
BridgeServer.diedCheck = {}
BridgeServer.deadFor = {}
BridgeServer.undriven = {}
BridgeServer.online = {}
BridgeServer.panicSaved = {}
BridgeServer.panicKeep = {}
BridgeServer.panicWatch = {}
BridgeServer.verbose = false
BridgeServer.touched = {}
BridgeServer.lost = {}
BridgeServer.issued = nil
BridgeServer.tick = 0




local MISSING_MS = 5000
local OFFLINE_MS = 1000




local DEAD_MS = 30000




local UNDRIVEN_MS = 3000
local DIED_RECHECK_MS = 2000
local HOME_FAR = 45
local MARK = 32768
local ISSUED_KEY = "NotAloneIssued"
local ISSUED_MAX = 1000
local PANIC_RADIUS = 10
local PANIC_BODY_RADIUS = 12
local PANIC_EVERY = 5

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeServer] " .. tostring(text)) end end
local function warn(text) print("[BridgeServer] " .. tostring(text)) end
local function nowMs()
    local t = 0
    pcall(function() t = getTimestampMs() end)
    return t
end

local function world() return BridgeData.world(nil) end

local function transmit()
    pcall(function() ModData.transmit(BridgeData.KEY) end)
end

local function record(who)
    local md = world()
    if md.players[who] == nil then md.players[who] = {} end
    return md.players[who]
end




local function findBody(id, onlineId)
    if id == nil then return nil end
    local found = nil
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z:getPersistentOutfitID() == id and not z:isDead()
                and (onlineId == nil or z:getOnlineID() == onlineId) then found = z break end
        end
    end)
    return found
end



function BridgeServer.hasMark(id)
    if type(id) ~= "number" then return false end
    local u = id
    if u < 0 then u = u + 4294967296 end
    return math.floor(u / MARK) % 2 == 1
end


function BridgeServer.markId(id)
    if type(id) ~= "number" or id == 0 then return nil end
    if BridgeServer.hasMark(id) then return id end
    return id + MARK
end



local function issuedStore()
    local s = ModData.getOrCreate(ISSUED_KEY)
    if type(s.ids) ~= "table" then s.ids = {} end
    return s
end

BridgeServer.lookAt = BridgeServer.lookAt or {}
local LOOK_RECLAIM_MS = 60000
local function issuedMap()
    if BridgeServer.issued ~= nil then return BridgeServer.issued end
    local map = {}
    local ok = pcall(function()
        for _, e in ipairs(issuedStore().ids) do
            if type(e) == "table" and e.id ~= nil then map[e.id] = e end
        end
    end)
    if ok then BridgeServer.issued = map end
    return map
end

local function issue(id, who)
    local s = issuedStore()
    local map = issuedMap()
    local e = map[id]
    if e == nil then
        e = { id = id }
        table.insert(s.ids, e)
        map[id] = e
        while #s.ids > ISSUED_MAX do
            local old = table.remove(s.ids, 1)
            if old ~= nil and old.id ~= nil then map[old.id] = nil end
        end
    end
    e.who = who
    pcall(function() e.t = getGameTime():getWorldAgeHours() end)
end



function BridgeServer.isCompanionBody(z)
    if z == nil then return false end
    local ours = false
    pcall(function()
        local md = z:getModData()
        ours = md ~= nil and md.notAloneBody == true
    end)
    if ours then return true end
    pcall(function() ours = z:getVariableBoolean("NotAloneBody") == true end)
    if ours then return true end
    local pid = nil
    pcall(function() pid = z:getPersistentOutfitID() end)
    if pid == nil or not BridgeServer.hasMark(pid) then return false end
    pcall(function()
        for _, rec in pairs(world().players) do
            if rec.bodyId == pid then ours = true return end
        end
    end)
    return ours
end

function BridgeServer.isCompanionId(pid)
    if type(pid) ~= "number" or pid == 0 then return false end
    if not BridgeServer.hasMark(pid) then return false end
    local ours = false
    pcall(function()
        for _, rec in pairs(world().players) do
            if rec.bodyId == pid then ours = true return end
        end
    end)
    return ours
end


local function outfitIdTaken(body, pid)
    local md = world()
    for _, rec in pairs(md.players) do
        if rec.bodyId == pid then return true end
    end
    local taken = false
    pcall(function()
        local list = getCell():getZombieList()
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z ~= nil and z ~= body and not z:isDead() and z:getPersistentOutfitID() == pid then taken = true break end
        end
    end)
    return taken
end











local TRIP_IGNORE = 1000000000
local trippingOn = nil

local function tripModOn()
    if trippingOn == nil then
        trippingOn = false
        pcall(function()
            local mods = getActivatedMods()
            trippingOn = mods:contains("TrippingZombies") or mods:contains("\\TrippingZombies")
        end)
        if trippingOn then log("Tripping Zombies detected: companion trip suppression on") end
    end
    return trippingOn
end

local function markHuman(body)
    pcall(function() body:setVariable("SurvivorNPC", true) end)
    pcall(function() body:setVariable("NotAloneBody", true) end)
    pcall(function() body:getModData().notAloneBody = true end)


    pcall(function() body:getModData().ST_Ignore = true end)

    pcall(function() body:getModData().RandomZedsExcluded = true end)
    pcall(function() body:getModData().tzCooldown = TRIP_IGNORE end)
end

local function unmarkHuman(body)
    pcall(function() body:clearVariable("SurvivorNPC") end)
    pcall(function() body:clearVariable("NotAloneBody") end)
    pcall(function() body:getModData().notAloneBody = nil end)
    pcall(function() body:getModData().ST_Ignore = nil end)
    pcall(function() body:getModData().RandomZedsExcluded = nil end)
    pcall(function() body:getModData().tzCooldown = nil end)
end






local function companionFlags(body)
    pcall(function() body:setNoTeeth(true) end)
    pcall(function() body:setUseless(true) end)
    pcall(function() body:setInvulnerable(true) end)
    pcall(function() body:setGodMod(true, true) end)
    markHuman(body)
end

local function releaseBody(body)
    if body == nil then return end
    unmarkHuman(body)
    pcall(function() body:setInvulnerable(false) end)
    pcall(function() body:setGodMod(false, true) end)
    pcall(function() body:setUseless(false) end)
    pcall(function() body:setNoTeeth(false) end)
    pcall(function() body:setTarget(nil) end)
end


local function stillBody(body, pid)
    if body == nil or pid == nil then return false end
    local same = false
    pcall(function() same = body:getPersistentOutfitID() == pid end)
    return same
end



local function currentBody(who, rec)
    if rec.bodyId == nil then BridgeServer.bodies[who] = nil return nil end
    local b = BridgeServer.bodies[who]
    local ok = false
    if b ~= nil then


        pcall(function() ok = b:getPersistentOutfitID() == rec.bodyId and not b:isDead() and b:isExistInTheWorld() end)
    end
    if not ok then
        if b ~= nil then
            local alive, inWorld, ours, pidNow = false, false, false, nil
            pcall(function()
                alive = not b:isDead()
                inWorld = b:isExistInTheWorld()
                pidNow = b:getPersistentOutfitID()
            end)
            pcall(function() ours = BridgeServer.isCompanionBody(b) end)


            local looked = false
            pcall(function()
                local t = BridgeServer.lookAt[who]
                looked = t ~= nil and getTimestampMs() - t <= LOOK_RECLAIM_MS
            end)
            if alive and inWorld and ours and looked and pidNow ~= nil and pidNow ~= rec.bodyId then
                local pid = nil
                pcall(function() pid = BridgeServer.markId(pidNow) end)
                if pid ~= nil and not outfitIdTaken(b, pid) then
                    pcall(function() b:setPersistentOutfitID(pid, b:isPersistentOutfitInit()) end)
                    companionFlags(b)
                    rec.bodyId = b:getPersistentOutfitID()
                    rec.onlineId = nil
                    pcall(function() rec.onlineId = b:getOnlineID() end)
                    issue(rec.bodyId, who)
                    BridgeServer.touched[b] = rec.bodyId
                    BridgeServer.bodies[who] = b
                    transmit()
                    log("body of " .. tostring(who) .. " reclaimed after outfit change")
                    return b
                end
            end
        end


        local deadHere = false
        pcall(function() deadHere = b ~= nil and b:isDead() end)
        if deadHere and stillBody(b, rec.bodyId) then releaseBody(b) end
        local old = b
        b = findBody(rec.bodyId, rec.onlineId)
        BridgeServer.bodies[who] = b

        if b ~= nil and b ~= old then
            companionFlags(b)
            log("body of " .. tostring(who) .. " found again, companion flags restored")
        end
    end
    return b
end

local function forget(who, rec, why)
    local b = BridgeServer.bodies[who]
    if stillBody(b, rec.bodyId) then releaseBody(b) end
    if b ~= nil and not stillBody(b, rec.bodyId) then
        pcall(function() if b:hasModData() then b:getModData().RandomZedsExcluded = nil end end)
    end

    if b ~= nil then BridgeServer.touched[b] = nil end
    rec.bodyId = nil
    rec.onlineId = nil
    BridgeServer.bodies[who] = nil
    BridgeServer.missing[who] = nil
    BridgeServer.diedCheck[who] = nil
    BridgeServer.deadFor[who], BridgeServer.undriven[who] = nil, nil
    transmit()
    log("body of " .. tostring(who) .. " forgotten: " .. tostring(why))
end

local function removeBody(who, rec)
    local body = currentBody(who, rec)
    if body ~= nil then
        releaseBody(body)
        pcall(function() body:removeFromSquare() end)
        pcall(function() body:removeFromWorld() end)
    end
    return body ~= nil
end

local function refreshOnline()
    local now = {}
    pcall(function()
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p ~= nil then now[p:getUsername()] = p end
        end
    end)


    for who in pairs(BridgeServer.panicSaved) do
        if now[who] == nil then BridgeServer.panicSaved[who] = nil BridgeServer.panicKeep[who] = nil end
    end
    BridgeServer.online = now
end

local function dist(a, x, y)
    local dx, dy = a:getX() - x, a:getY() - y
    return math.sqrt(dx * dx + dy * dy)
end

BridgeServer.Commands = {}


local function createBody(x, y, z)
    local body, failed = nil, nil
    for attempt = 1, 8 do
        BridgeServer.creating = true
        local okSpawn, list = pcall(addZombiesInOutfit, x, y, z, 1, "Naked", 100, false, false, false, false, false, false, 1)
        BridgeServer.creating = false
        if not okSpawn then return nil, "addZombiesInOutfit failed: " .. tostring(list) end
        if list == nil or list:size() == 0 then return nil, "addZombiesInOutfit returned nothing" end
        local candidate = list:get(0)


        local pid = nil
        pcall(function() pid = BridgeServer.markId(candidate:getPersistentOutfitID()) end)
        local marked = false
        if pid ~= nil and not outfitIdTaken(candidate, pid) then
            pcall(function() candidate:setPersistentOutfitID(pid, candidate:isPersistentOutfitInit()) end)
            pcall(function() marked = candidate:getPersistentOutfitID() == pid end)
            if not marked then
                pcall(function() candidate:setPersistentOutfitID(pid) end)
                pcall(function() marked = candidate:getPersistentOutfitID() == pid end)
            end
        end
        if marked then





            pcall(function()
                local oc, op = candidate:getOwner(), candidate:getOwnerPlayer()
                if oc ~= nil or op ~= nil then
                    local was = "connection"
                    pcall(function() if op ~= nil then was = op:getUsername() end end)
                    candidate:setOwner(nil)
                    candidate:setOwnerPlayer(nil)
                    log("new body object came with an owner (" .. tostring(was) .. "), cleared")
                end
            end)
            return candidate, nil
        end



        unmarkHuman(candidate)
        if not BridgeData.foreign(candidate) then
            pcall(function() candidate:removeFromSquare() end)
            pcall(function() candidate:removeFromWorld() end)
        end
    end
    return nil, "no unique marked outfit id"
end


BridgeServer.Commands.spawn = function(player, args)
    local who = player:getUsername()
    local rec = record(who)



    local newLife = args.newLife == true
    if newLife then
        rec.mode, rec.waitX, rec.waitY, rec.waitZ = "follow", nil, nil, nil
        log("new life for " .. tostring(who) .. ": follow, waiting place dropped")
    end
    if rec.bodyId ~= nil and currentBody(who, rec) ~= nil then
        if newLife then transmit() end
        sendServerCommand(player, "Bridge", "spawned", { id = rec.bodyId, existed = true, iseq = rec.iseq, newLife = newLife or nil })
        return
    end
    local x, y, z = math.floor(args.x or player:getX()), math.floor(args.y or player:getY()), math.floor(args.z or player:getZ())

    if dist(player, x, y) > 60 then
        x, y, z = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    end
    local failed = nil
    local ok, err = pcall(function()
        local body, why = createBody(x, y, z)
        if body == nil then failed = why return end
        pcall(function() body:setTarget(player) end)
        companionFlags(body)
        rec.bodyId = body:getPersistentOutfitID()
        issue(rec.bodyId, who)
        BridgeServer.touched[body] = rec.bodyId
        rec.onlineId = nil
        pcall(function() rec.onlineId = body:getOnlineID() end)
        rec.want = true
        rec.saved = rec.saved or 0
        BridgeServer.bodies[who] = body
        BridgeServer.missing[who] = nil
        BridgeServer.offline[who] = nil
        pcall(BridgeServer.suppressPanic, who, player, body)
        transmit()
        log("spawned body id=" .. tostring(rec.bodyId) .. " online=" .. tostring(rec.onlineId) .. " for " .. tostring(who) .. " at " .. x .. " " .. y .. " " .. z)
        sendServerCommand(player, "Bridge", "spawned", { id = rec.bodyId, iseq = rec.iseq, newLife = newLife or nil })
    end)
    if not ok or failed ~= nil then
        warn("spawn failed: " .. tostring(failed or err))
        sendServerCommand(player, "Bridge", "error", { text = "spawn failed: " .. tostring(failed or err) })
    end
end



BridgeServer.Commands.despawn = function(player, args)
    local who = player:getUsername()
    local rec = record(who)
    if args.byCommand then rec.want = false end

    if args.id ~= nil and rec.bodyId ~= nil and args.id ~= rec.bodyId then
        if args.byCommand then transmit() end
        sendServerCommand(player, "Bridge", "despawned", { found = false })
        return
    end
    if rec.bodyId == nil then

        if args.byCommand then transmit() end
        sendServerCommand(player, "Bridge", "despawned", { found = false })
        return
    end
    local id = rec.bodyId
    local found = removeBody(who, rec)


    if not found then
        local n = -1
        pcall(function() n = getCell():getZombieList():size() end)
        log("despawn: body id=" .. tostring(id) .. " not found, zombies=" .. tostring(n) .. ", left to lost body check")
    end
    forget(who, rec, "despawn by owner")
    sendServerCommand(player, "Bridge", "despawned", { found = found })
end







BridgeServer.Commands.respawn = function(player, args)
    local who = player:getUsername()
    local rec = record(who)
    if args.id ~= nil and rec.bodyId ~= nil and args.id ~= rec.bodyId then return end
    if rec.bodyId ~= nil then
        local body = currentBody(who, rec)
        local online, owner = "?", "?"
        if body ~= nil then
            pcall(function() online = tostring(body:getOnlineID()) end)
            pcall(function()
                local op = body:getOwnerPlayer()
                owner = op ~= nil and tostring(op:getUsername()) or "none"
            end)
        end
        log("respawn for " .. tostring(who) .. ": client did not receive body id=" .. tostring(rec.bodyId)
            .. " online=" .. online .. " owner=" .. owner .. " found=" .. tostring(body ~= nil) .. " ask=" .. tostring(args.n))
        local oldId = rec.bodyId
        removeBody(who, rec)
        forget(who, rec, "respawn: client did not receive it")




        sendServerCommand("Bridge", "stale", { id = oldId })
    end
    BridgeServer.Commands.spawn(player, args)
end



BridgeServer.Commands.died = function(player, args)
    local who, rec = BridgeData.ownerOf(world(), args.id)
    if who == nil then return end
    if currentBody(who, rec) == nil then
        forget(who, rec, "died, reported by " .. tostring(player:getUsername()))
    else
        BridgeServer.diedCheck[who] = nowMs() + DIED_RECHECK_MS
    end
end





BridgeServer.Commands.care = function(player, args)
    local change = args.change
    if type(change) ~= "table" then return end
    local part, why = BridgeCare.apply(player, change)
    if part == nil then
        log("care " .. tostring(change.kind) .. " failed: " .. tostring(why))
        return
    end
    pcall(function() syncBodyPart(part, BridgeCare.SYNC[change.kind]) end)
    if type(args.items) == "table" then
        for i, id in ipairs(args.items) do
            if i > 2 then break end
            local item = nil
            pcall(function() item = player:getInventory():getItemWithIDRecursiv(math.floor(tonumber(id) or -1)) end)
            if item ~= nil then BridgeCare.consume(item, true) end
        end
    end
    log("care " .. tostring(change.kind) .. " part " .. tostring(change.part) .. " for " .. tostring(player:getUsername()))
end









local SNAP_SKIP = { p = true, h = true, w = true, as = true }

local STABLE_SKIP = { p = true, h = true, w = true, as = true, a = true, u = true, fa = true, md = true, bl = true, di = true }
local NEST_MAX = 16



local function snapMd(md)
    if type(md) ~= "table" then return nil end
    local out, any = {}, false
    for k, v in pairs(md) do
        if k ~= "Tooltip" then
            out[k] = v
            any = true
        end
    end
    if not any then return nil end
    local packed = BridgeItems.packTable(out)
    if packed == nil or #BridgeItems.esc(packed) > BridgeItems.MD_MAX then return nil end
    return out
end


local function flatten(r, parent, out)
    local copy = {}
    for k, v in pairs(r) do
        if k ~= "in" and k ~= "p" then copy[k] = v end
    end
    copy.md = snapMd(r.md)
    copy.p = parent
    out[#out + 1] = copy
    local me = #out
    if type(r["in"]) == "table" then
        for _, child in ipairs(r["in"]) do flatten(child, me, out) end
    end
end


local function subtree(list, idx)
    local function build(i, depth)
        local copy = {}
        for k, v in pairs(list[i]) do
            if k ~= "p" then copy[k] = v end
        end
        if depth < NEST_MAX then
            local kids = nil
            for j, x in ipairs(list) do
                if j ~= i and x.p == i then
                    kids = kids or {}
                    kids[#kids + 1] = build(j, depth + 1)
                end
            end
            copy["in"] = kids
        end
        return copy
    end
    return build(idx, 0)
end


local function removeSubtree(list, idx)
    local gone = { [idx] = true }
    local changed = true
    while changed do
        changed = false
        for j, x in ipairs(list) do
            if not gone[j] and x.p ~= nil and gone[x.p] then
                gone[j] = true
                changed = true
            end
        end
    end
    local map, out = {}, {}
    for j, x in ipairs(list) do
        if not gone[j] then
            out[#out + 1] = x
            map[j] = #out
        end
    end
    for _, x in ipairs(out) do
        if x.p ~= nil then x.p = map[x.p] end
    end
    return out
end


local function fieldsKey(x, skip)
    local copy = {}
    for k, v in pairs(x) do
        if k ~= "in" then copy[k] = v end
    end
    if type(copy.md) == "table" then copy.md = snapMd(copy.md) end
    return BridgeItems.encode({ copy }, skip)
end


local function kidsKey(types)
    table.sort(types)
    return table.concat(types, ",")
end
local function nestedKids(r, out, depth)
    out = out or {}
    depth = depth or 0
    if type(r["in"]) == "table" and depth < NEST_MAX then
        for _, c in ipairs(r["in"]) do
            out[#out + 1] = tostring(c.t)
            nestedKids(c, out, depth + 1)
        end
    end
    return out
end
local function flatKids(list, idx)
    local inside, out = { [idx] = true }, {}

    for j = idx + 1, #list do
        local x = list[j]
        if x.p ~= nil and inside[x.p] then
            inside[j] = true
            out[#out + 1] = tostring(x.t)
        end
    end
    return out
end




local function matchRecord(list, r, flags)
    local stable, full = fieldsKey(r, STABLE_SKIP), fieldsKey(r, SNAP_SKIP)
    local kids = kidsKey(nestedKids(r))
    local best, bestScore = nil, -1
    for i, x in ipairs(list) do
        if x.t == r.t then
            local score = 0
            if kidsKey(flatKids(list, i)) == kids then score = score + 8 end
            if fieldsKey(x, STABLE_SKIP) == stable then score = score + 4 end
            if fieldsKey(x, SNAP_SKIP) == full then score = score + 2 end
            if type(flags) == "table" then
                if (x.w == true) == (flags.w == true) then score = score + 1 end
                if (tonumber(x.h) or 0) == (tonumber(flags.h) or 0) then score = score + 1 end
                if (x.p == nil) == (flags.top == true) then score = score + 1 end
            end
            if score > bestScore then best, bestScore = i, score end
        end
    end
    return best
end
BridgeServer.snap = { flatten = flatten, subtree = subtree, removeSubtree = removeSubtree, match = matchRecord }












local JOURNAL_KEEP = 20000
local JOURNAL_KEY = "NotAloneJournal"
BridgeServer.journal = { epoch = nil, pending = {}, reconciled = {} }

local function journalStore()
    local s = ModData.getOrCreate(JOURNAL_KEY)
    if type(s.pending) ~= "table" then s.pending = {} end
    return s
end


local function jesc(who)
    return (string.gsub(BridgeItems.esc(who), "[ \t]", function(ch) return ch == " " and "%20" or "%09" end))
end
local function junesc(text)
    local plain = string.gsub(text, "%%(%x%x)", function(hex)
        if hex == "20" then return " " end
        if hex == "09" then return "\t" end
        return "%" .. hex
    end)
    return BridgeItems.unesc(plain)
end

local function journalFile()
    local key = "world"
    pcall(function() key = tostring(getWorld():getWorld()) end)
    return "bridge/server_journal_" .. string.gsub(key, "[^%w%-_]", "_") .. ".txt"
end

local function journalWrite(lines, append)
    local ok, err = pcall(function()
        local w = getFileWriter(journalFile(), true, append == true)
        w:write(table.concat(lines, "\n") .. "\n")
        w:close()
    end)
    if not ok then warn("journal write failed: " .. tostring(err)) end
    return ok
end


local function journalNote(kind, who, rec, itemId, list)
    local epoch = BridgeServer.journal.epoch
    if epoch == nil then return end
    journalWrite({ string.format("%s %s %s %s %s %s", kind, tostring(epoch), jesc(who), tostring(rec.iseq or 0),
        tostring(itemId), BridgeItems.encode(list)) }, true)
end

local function journalRead()
    local lines = {}
    pcall(function()
        local r = getFileReader(journalFile(), false)
        if r == nil then return end
        while true do
            local line = r:readLine()
            if line == nil then break end
            if line ~= "" then lines[#lines + 1] = line end
        end
        r:close()
    end)
    return lines
end





local function journalStart(md)
    local J = BridgeServer.journal
    local store = journalStore()
    local prev = md.journalEpoch
    local pending = {}
    for who, list in pairs(store.pending) do
        if type(list) == "table" and #list > 0 then pending[who] = list end
    end
    local keep, seen = {}, false
    if prev ~= nil then
        for _, line in ipairs(journalRead()) do
            local mark = string.match(line, "^R (%S+)$")
            if mark ~= nil then
                if mark == tostring(prev) then seen = true end
                if seen then keep[#keep + 1] = line end
            elseif seen then
                local kind, ep, whoEsc, iseq, id, items = string.match(line, "^([GT]) (%S+) (%S+) (%S+) (%S+) ?(.*)$")
                if kind ~= nil and tonumber(id) ~= nil then
                    local who = junesc(whoEsc)
                    local rec = md.players[who]
                    local saved = (rec ~= nil and type(rec.iseq) == "number") and rec.iseq or 0
                    if ep ~= tostring(prev) or (tonumber(iseq) or 0) > saved then
                        keep[#keep + 1] = line
                        pending[who] = pending[who] or {}
                        pending[who][#pending[who] + 1] = { kind = kind, id = tonumber(id), items = items }
                    end
                end
            end
        end
    end
    if #keep > JOURNAL_KEEP then
        local cut = {}
        for i = #keep - JOURNAL_KEEP + 1, #keep do cut[#cut + 1] = keep[i] end
        keep = cut
    end
    J.epoch = nil
    pcall(function() J.epoch = getTimestampMs() end)
    if J.epoch == nil or J.epoch == 0 then J.epoch = 1 end

    if type(prev) == "number" and J.epoch <= prev then J.epoch = prev + 1 end
    keep[#keep + 1] = "R " .. tostring(J.epoch)
    journalWrite(keep, false)
    md.journalEpoch = J.epoch
    store.pending = pending
    J.pending, J.reconciled = pending, {}
    local n = 0
    for _, list in pairs(pending) do n = n + #list end
    if n > 0 then log("journal: " .. tostring(n) .. " transfers after the last world save wait for their players") end
end




local function journalReconcile(who, player)
    local J = BridgeServer.journal
    if J.reconciled[who] then return end
    J.reconciled[who] = true
    local list = J.pending[who]
    J.pending[who] = nil
    pcall(function() journalStore().pending[who] = nil end)
    if list == nil or #list == 0 then return end
    local rec = record(who)
    local items = BridgeItems.decode(rec.items or "")
    local added, removed, took = 0, 0, {}
    for _, e in ipairs(list) do
        local has = false
        if e.id ~= nil then
            pcall(function() has = player:getInventory():getItemWithIDRecursiv(e.id) ~= nil end)
        end
        local recs = BridgeItems.decode(e.items or "")
        if e.kind == "T" and e.id ~= nil then took[e.id] = true end
        if e.kind == "G" and not has and not took[e.id] and #recs > 0 then

            local base = #items
            for _, x in ipairs(recs) do
                if x.p ~= nil then x.p = x.p + base end
                items[#items + 1] = x
            end
            added = added + 1
        elseif e.kind == "T" and has and #recs > 0 then

            local idx = matchRecord(items, subtree(recs, 1), nil)
            if idx ~= nil then
                items = removeSubtree(items, idx)
                removed = removed + 1
            end
        end
    end
    if added + removed > 0 then
        local text = BridgeItems.encode(items)
        local fit = #BridgeItems.decode(text)
        if fit < #items then log("journal: " .. tostring(who) .. " snapshot full, " .. tostring(#items - fit) .. " records cut") end
        rec.items = text
        rec.saved = 1
        rec.iseq = (rec.iseq or 0) + 1
        transmit()
        log(string.format("journal: %s after server stop: %d given back to her, %d taken removed from her", tostring(who), added, removed))
    end
end
BridgeServer.journalStart, BridgeServer.journalReconcile = journalStart, journalReconcile


BridgeServer.Commands.outfit = function(player, args)
    local rec = record(player:getUsername())


    if type(args.items) ~= "string" or #args.items > 60000 then return end


    if type(args.iseq) == "number" and type(rec.iseq) == "number" and args.iseq < rec.iseq then return end
    if args.items ~= rec.items then
        rec.items = args.items
        rec.saved = 1
        transmit()
    end
end


BridgeServer.Commands.state = function(player, args)
    local rec = record(player:getUsername())
    local changed = false
    if args.mode ~= nil and BridgeData.MODES[args.mode] and rec.mode ~= args.mode then
        rec.mode = args.mode
        changed = true
    end
    if args.waitX ~= nil then
        rec.waitX, rec.waitY, rec.waitZ = tonumber(args.waitX), tonumber(args.waitY), tonumber(args.waitZ) or 0
        changed = true
    elseif args.clearWait then
        rec.waitX, rec.waitY, rec.waitZ = nil, nil, nil
        changed = true
    end
    if args.want ~= nil and rec.want ~= (args.want == true) then
        rec.want = args.want == true
        changed = true
    end
    if args.name ~= nil then
        rec.name = BridgeData.cleanName(args.name)
        changed = true
    end

    for key in pairs(BridgeData.OPTIONS) do
        if args[key] ~= nil and rec[key] ~= (args[key] == true) then
            rec[key] = args[key] == true
            changed = true
        end
    end

    if args.hair ~= nil or args.skin ~= nil or args.hairColor ~= nil or args.face ~= nil or args.details ~= nil
        or args.muscle ~= nil or args.makeup ~= nil then
        pcall(function() BridgeServer.lookAt[player:getUsername()] = getTimestampMs() end)
    end
    if args.hair ~= nil then
        local hair = BridgeData.cleanHair(args.hair)
        if hair ~= nil and rec.hair ~= hair then
            rec.hair = hair
            changed = true
        end
    end
    if args.skin ~= nil then
        local skin = BridgeData.cleanSkin(args.skin)
        if skin ~= nil and rec.skin ~= skin then
            rec.skin = skin
            changed = true
        end
    end
    if args.hairColor ~= nil then
        local color = BridgeData.cleanHairColor(args.hairColor)
        if color ~= nil then
            local old = rec.hairColor
            local same = type(old) == "table"
                and math.abs((old.r or 0) - color.r) < 0.01
                and math.abs((old.g or 0) - color.g) < 0.01
                and math.abs((old.b or 0) - color.b) < 0.01
            if not same then
                rec.hairColor = color
                changed = true
            end
        end
    end
    if args.face ~= nil then
        local face = BridgeData.cleanFace(args.face)
        if (rec.face or nil) ~= face then
            rec.face = face
            changed = true
        end
    end
    if args.details ~= nil then
        local details = BridgeData.cleanDetails(args.details)
        if details ~= nil then
            local old = rec.details or {}
            local same = (#old == #details)
            if same then
                for i = 1, #old do
                    if old[i] ~= details[i] then same = false break end
                end
            end
            if not same then
                rec.details = details
                changed = true
            end
        end
    end
    if args.muscle ~= nil then
        local m = tonumber(args.muscle)
        if m ~= nil and m == m and m >= 0 and m <= BridgeData.MUSCLE_MAX then
            m = math.floor(m)
            if m ~= BridgeData.muscleOf(rec) then
                rec.muscle = m
                changed = true
            end
        end
    end
    if args.makeup ~= nil then
        local makeup = BridgeData.cleanMakeup(args.makeup)
        if makeup ~= nil then
            local old = rec.makeup or {}
            local same = (#old == #makeup)
            if same then
                for i = 1, #old do
                    if old[i] ~= makeup[i] then same = false break end
                end
            end
            if not same then
                rec.makeup = makeup
                changed = true
            end
        end
    end


    if args.keep ~= nil and BridgeData.keepAllowed(args.keep) and rec.keep ~= args.keep then
        rec.keep = args.keep
        changed = true
    end
    if args.far ~= nil and rec.far ~= (args.far == true) then
        rec.far = args.far == true
        changed = true
    end

    if args.combat ~= nil and BridgeData.COMBAT_MODES[args.combat] and rec.combat ~= args.combat then
        rec.combat = args.combat
        changed = true
    end

    if args.left ~= nil then
        local left = args.left == true or nil
        if rec.left ~= left then
            rec.left = left
            changed = true
        end
    end

    if args.sit ~= nil then
        local sit = (args.sit == "chair" or args.sit == "floor") and args.sit or nil
        if rec.sit ~= sit then
            rec.sit = sit
            changed = true
        end
    end
    if args.outfitGiven and not rec.outfitGiven then
        rec.outfitGiven = true
        changed = true
    end

    for _, flag in ipairs({ "beltGiven", "armsSet" }) do
        if args[flag] and not rec[flag] then
            rec[flag] = true
            changed = true
        end
    end
    if args.rel ~= nil then
        local rel = BridgeData.cleanRel(args.rel)
        if rel ~= nil then

            local old = BridgeData.relOf(rec)
            rel.giftAt = math.max(rel.giftAt or 0, old.giftAt or 0)
            rec.rel = rel


        end
    end
    if changed then transmit() end
end



BridgeServer.GIFTS = { ["Base.WaterBottle"] = true, ["Base.GranolaBar"] = true, ["Base.Crisps"] = true,
    ["Base.BeefJerky"] = true, ["Base.Chocolate_Candy"] = true, ["Base.Gum"] = true,
    ["Base.LighterDisposable"] = true, ["Base.CigarettePack"] = true }

local function inCarWith(player, rec)
    local c = rec and rec.car
    if type(c) ~= "table" or not c.inside then return false end
    local yes = false
    pcall(function()
        local v = player:getVehicle()
        yes = v ~= nil and v:getId() == c.v
    end)
    return yes
end

BridgeServer.Commands.gift = function(player, args)
    local who = player:getUsername()
    local rec = record(who)
    local rel = BridgeData.relOf(rec)
    local item = args and args.item
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)

    if not BridgeServer.GIFTS[item] or (rec.bodyId == nil and not inCarWith(player, rec)) or (rel.f or 0) < 35 then
        sendServerCommand(player, "Bridge", "gifted", { ok = false })
        return
    end
    if hours < (rel.giftAt or 0) then
        sendServerCommand(player, "Bridge", "gifted", { ok = false, wait = true, giftAt = rel.giftAt })
        return
    end
    local given = nil
    pcall(function()
        local inv = player:getInventory()
        given = inv:AddItem(item)
        if given ~= nil then sendAddItemToContainer(inv, given) end
    end)
    if given == nil then
        sendServerCommand(player, "Bridge", "gifted", { ok = false })
        return
    end
    rel.giftAt = hours + 36 + ZombRand(24)
    transmit()
    log("gift " .. tostring(item) .. " to " .. tostring(who))
    sendServerCommand(player, "Bridge", "gifted", { ok = true, item = item, giftAt = rel.giftAt })
end





BridgeServer.moodTalkAt = {}
BridgeServer.moodAt = {}
local MOOD_GAP_MS = 2000
BridgeServer.Commands.mood = function(player, args)
    local who = player:getUsername()
    local rec = record(who)
    if not BridgeData.optionOf(rec, "mood") then return end

    if rec.bodyId == nil and not inCarWith(player, rec) then return end
    local deltas = nil
    if args.talk ~= nil then
        local id = tostring(args.talk)
        if BridgeMood.TALK[id] == nil then return end

        if BridgeMood.tier(BridgeData.relOf(rec)) == nil then
            sendServerCommand(player, "Bridge", "mood", { talk = id, done = {} })
            return
        end
        local hours = 0
        pcall(function() hours = getGameTime():getWorldAgeHours() end)

        if type(rec.moodTalk) ~= "table" then rec.moodTalk = {} end
        local mine = rec.moodTalk
        local at = mine[id]
        if at ~= nil and hours >= at and hours < at + BridgeMood.TALK_HOURS then
            sendServerCommand(player, "Bridge", "mood", { talk = id, done = {} })
            return
        end
        mine[id] = hours
        deltas = BridgeMood.roll(id)
    else
        local now = nowMs()
        if now - (BridgeServer.moodAt[who] or 0) < MOOD_GAP_MS then return end
        BridgeServer.moodAt[who] = now
        deltas = BridgeMood.cleanPresence(args.presence)
    end
    local done, mask = BridgeMood.apply(player, deltas)
    if mask > 0 then pcall(function() syncPlayerStats(player, mask) end) end
    if args.talk ~= nil then
        sendServerCommand(player, "Bridge", "mood", { talk = tostring(args.talk), done = done })
        log("mood " .. tostring(args.talk) .. " for " .. tostring(who) .. ": " .. BridgeMood.describe(done))
    end
end



















































BridgeServer.Commands.say = function(player, args)
    if args.text == nil then return end
    local who = player:getUsername()
    local rec = record(who)
    local text = tostring(args.text)
    if #text > 300 then text = string.sub(text, 1, 300) end

    sendServerCommand("Bridge", "say", { text = text, owner = who, id = rec.bodyId,
        name = BridgeData.nameOf(rec), chat = args.chat ~= false,
        car = (args.car == true and inCarWith(player, rec)) or nil })
end





local claimAt = {}
BridgeServer.Commands.claimClear = function(player, args)
    local who = player:getUsername()
    local x1, y1, x2, y2 = tonumber(args.x1), tonumber(args.y1), tonumber(args.x2), tonumber(args.y2)
    local function answer(n) sendServerCommand(player, "Bridge", "claimCleared", { n = n }) end
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil or x2 <= x1 or y2 <= y1 or x2 - x1 > 120 or y2 - y1 > 120 then
        return answer(0)
    end
    local px, py = player:getX(), player:getY()
    if px < x1 - 20 or px > x2 + 20 or py < y1 - 20 or py > y2 + 20 then return answer(0) end
    local now = nowMs()
    if claimAt[who] ~= nil and now - claimAt[who] < 10000 then return answer(0) end
    claimAt[who] = now
    local n = 0
    for other, rec in pairs(world().players) do
        if other ~= who and rec.bodyId ~= nil then

            local body = currentBody(other, rec)
            local x, y = nil, nil
            if body ~= nil then pcall(function() x, y = body:getX(), body:getY() end) end
            if x ~= nil and x >= x1 and x < x2 and y >= y1 and y < y2 then
                removeBody(other, rec)
                forget(other, rec, "safehouse claim by " .. tostring(who))
                n = n + 1
            end
        end
    end


    if type(args.strays) == "table" then
        for i, id in ipairs(args.strays) do
            if i > 20 then break end
            if BridgeServer.removeStray(tonumber(id), who, x1, y1, x2, y2) then n = n + 1 end
        end
    end
    answer(n)
end




function BridgeServer.removeStray(id, by, x1, y1, x2, y2)
    if id == nil or not BridgeServer.hasMark(id) or issuedMap()[id] == nil then return false end
    for _, rec in pairs(world().players) do
        if rec.bodyId == id then return false end
    end
    local z = findBody(id, nil)
    if z == nil or BridgeData.foreign(z) then return false end
    if x1 ~= nil then
        local x, y = nil, nil
        pcall(function() x, y = z:getX(), z:getY() end)
        if x == nil or x < x1 or x >= x2 or y < y1 or y >= y2 then return false end
    end
    releaseBody(z)
    pcall(function() z:removeFromSquare() end)
    pcall(function() z:removeFromWorld() end)
    BridgeServer.touched[z] = nil
    log("stray body id=" .. tostring(id) .. " removed, reported by " .. tostring(by))
    return true
end
BridgeServer.Commands.stray = function(player, args)
    BridgeServer.removeStray(args and tonumber(args.id), player:getUsername())
end





local LOOK_NEAR = 60
BridgeServer.Commands.look = function(player, args)
    local a = args and args.a
    if type(a) ~= "string" or #a > 32 or string.match(a, "^%a%w*$") == nil then return end
    local who = player:getUsername()
    local rec = record(who)
    if rec.bodyId == nil then return end
    local x, y = nil, nil
    pcall(function()
        local body = BridgeServer.bodies[who]
        if body ~= nil then x, y = body:getX(), body:getY() end
    end)
    if x == nil then pcall(function() x, y = player:getX(), player:getY() end) end
    if x == nil then return end
    for _, p in pairs(BridgeServer.online) do
        if p ~= player and dist(p, x, y) <= LOOK_NEAR then
            sendServerCommand(p, "Bridge", "look", { owner = who, id = rec.bodyId, a = a })
        end
    end
end





BridgeServer.Commands.carSeat = function(player, args)
    local who = player:getUsername()
    local rec = record(who)
    if args.clear then
        if rec.car ~= nil then
            rec.car = nil
            transmit()
        end
        return
    end
    local v, s = tonumber(args.v), tonumber(args.s)
    if v == nil or s == nil or s ~= math.floor(s) then return end
    local vehicle = nil
    pcall(function() vehicle = getVehicleById(v) end)
    if vehicle == nil then return end
    local n = 0
    pcall(function() n = vehicle:getMaxPassengers() end)
    if s < 0 or s >= n or dist(player, vehicle:getX(), vehicle:getY()) > 30 then return end
    local lap = args.lap == true


    local had = rec.car
    if args.inside ~= true and type(had) == "table" and had.v == v and had.s == s and (had.lap == true) == lap then
        if had.inside then
            had.inside = nil
            transmit()
        end
        return
    end
    if not lap then
        for other, orec in pairs(world().players) do
            local c = type(orec) == "table" and orec.car or nil
            if other ~= who and type(c) == "table" and c.v == v and c.s == s and not c.lap then
                local p = BridgeServer.online[other]
                local here = false
                pcall(function() here = p ~= nil and (p:getVehicle() == vehicle or dist(p, vehicle:getX(), vehicle:getY()) < 20) end)
                if here then
                    sendServerCommand(player, "Bridge", "carSeat", { ok = false, s = s })
                    log("car seat " .. tostring(s) .. " for " .. tostring(who) .. ": taken by " .. tostring(other))
                    return
                end
            end
        end
    end
    local c = { v = v, s = s, lap = lap or nil, inside = args.inside == true or nil }
    local was = rec.car
    if type(was) ~= "table" or was.v ~= c.v or was.s ~= c.s or was.lap ~= c.lap or was.inside ~= c.inside then
        rec.car = c
        transmit()
    end
end




BridgeServer.Commands.carDoor = function(player, args)
    local who = player:getUsername()
    local rec = record(who)
    local v = tonumber(args.v)
    if v == nil or type(args.part) ~= "string" or #args.part > 40 then return end
    if type(rec.car) ~= "table" or rec.car.v ~= v then return end
    local vehicle = nil
    pcall(function() vehicle = getVehicleById(v) end)
    if vehicle == nil or dist(player, vehicle:getX(), vehicle:getY()) > 12 then return end
    pcall(function()
        local part = vehicle:getPartById(args.part)
        if part == nil or part:getDoor() == nil or part:getInventoryItem() == nil then return end
        local seatDoor = false
        for i = 0, vehicle:getMaxPassengers() - 1 do
            if vehicle:getPassengerDoor(i) == part then seatDoor = true break end
        end
        if not seatDoor then return end
        local open = args.open == true
        if open and part:getDoor():isLocked() then return end
        if part:getDoor():isOpen() == open then return end
        part:getDoor():setOpen(open)
        vehicle:transmitPartDoor(part)
        log("car door " .. tostring(args.part) .. (open and " opened" or " closed") .. " for " .. tostring(who))
    end)
end



BridgeServer.Commands.water = function(player, args)
    local x, y, z, amount = tonumber(args.x), tonumber(args.y), tonumber(args.z), tonumber(args.amount)
    if x == nil or y == nil or z == nil or amount == nil or amount <= 0 then return end
    if dist(player, x + 0.5, y + 0.5) > 20 then return end
    if amount > 60 then amount = 60 end
    pcall(function()
        local sq = getCell():getGridSquare(x, y, z)
        if sq == nil then return end
        local objects = sq:getObjects()
        for i = 0, objects:size() - 1 do
            local o = objects:get(i)
            local wet = false
            pcall(function() wet = o:hasWater() and o:getFluidAmount() > 0 end)
            if wet then
                if o:useFluid(math.min(amount, o:getFluidAmount())) > 0 then
                    pcall(function() o:transmitModData() end)
                end
                return
            end
        end
    end)
end


BridgeServer.Commands.sync = function(player, args)
    transmit()
end





BridgeServer.Commands.give = function(player, args)
    local function fail(why)
        sendServerCommand(player, "Bridge", "giveFailed", { id = args.id, token = args.token, why = why })
    end
    local rec = record(player:getUsername())
    if rec.bodyId == nil then return fail("no body") end
    local item = nil
    pcall(function() item = player:getInventory():getItemWithIDRecursiv(args.id) end)
    if item == nil then return fail("not in inventory") end
    local equipped = false
    pcall(function()
        equipped = player:isEquipped(item) or player:getPrimaryHandItem() == item or player:getSecondaryHandItem() == item
    end)
    if equipped then return fail("equipped") end
    local r = BridgeItems.record(item, true)

    local list = BridgeItems.decode(rec.items or "")
    flatten(r, nil, list)
    local items = BridgeItems.encode(list)
    if #BridgeItems.decode(items) ~= #list then return fail("snapshot full") end
    local ok, err = pcall(function()
        pcall(function() player:removeAttachedItem(item) end)
        local container = item:getContainer()
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    end)
    if not ok then return fail("remove failed: " .. tostring(err)) end
    rec.items = items
    rec.saved = 1
    rec.iseq = (rec.iseq or 0) + 1
    local added = {}
    flatten(r, nil, added)
    journalNote("G", player:getUsername(), rec, args.id, added)
    transmit()
    sendServerCommand(player, "Bridge", "gave", { id = args.id, token = args.token, rec = r, iseq = rec.iseq })
    log("give " .. r.t .. " from " .. tostring(player:getUsername()))
end



BridgeServer.Commands.take = function(player, args)
    local who = player:getUsername()
    local rec = record(who)
    local r = args and args.rec
    local function answer(ok, id, why)
        if args.token ~= nil then
            sendServerCommand(player, "Bridge", "took", { token = args.token, ok = ok, id = id, why = why, iseq = rec.iseq })
        end
    end
    if type(r) ~= "table" or type(r.t) ~= "string" then return answer(false, nil, "no record") end
    if rec.bodyId == nil and args.returnId == nil then return answer(false, nil, "no body") end
    local list = BridgeItems.decode(rec.items or "")
    local flags = { w = args.w == true, h = tonumber(args.h), top = args.top == true }
    local idx = matchRecord(list, r, args.returnId == nil and flags or nil)
    if idx == nil then return answer(false, nil, "not in body snapshot") end
    local item = nil
    local ok, err = pcall(function()
        local inv = player:getInventory()
        if args.dest ~= nil then
            pcall(function()
                local bag = player:getInventory():getItemWithIDRecursiv(args.dest)
                if bag ~= nil and bag:IsInventoryContainer() then inv = bag:getInventory() end
            end)
        end
        item = BridgeItems.make(inv, r)
        if item == nil then return end
        sendAddItemToContainer(inv, item)
        pcall(function() sendItemStats(item) end)
    end)
    if not ok or item == nil then
        local why = ok and "AddItem returned nil" or tostring(err)
        log("take failed: " .. why)
        return answer(false, nil, why)
    end
    rec.items = BridgeItems.encode(removeSubtree(list, idx))
    rec.saved = 1
    rec.iseq = (rec.iseq or 0) + 1
    local gone = {}
    flatten(r, nil, gone)
    journalNote("T", who, rec, item:getID(), gone)
    transmit()
    answer(true, item:getID(), nil)
    log("take " .. tostring(r.t) .. " to " .. tostring(who))
end

local function onClientCommand(module, command, player, args)
    if module ~= "Bridge" then return end
    local handler = BridgeServer.Commands[command]
    if handler == nil then return end

    pcall(function() journalReconcile(player:getUsername(), player) end)
    local ok, err = pcall(handler, player, args or {})
    if not ok then warn("command " .. tostring(command) .. " failed: " .. tostring(err)) end
end








local function onZombieCreate(z)
    if z == nil then return end


    if BridgeServer.touched[z] ~= nil then
        BridgeServer.touched[z] = nil
        unmarkHuman(z)
        pcall(function() z:setUseless(false) end)
        pcall(function() z:setGodMod(false, true) end)
        pcall(function() z:setInvulnerable(false) end)
        pcall(function() z:setNoTeeth(false) end)
    end
    if BridgeServer.creating then markHuman(z) end
    local pid = nil
    pcall(function() pid = z:getPersistentOutfitID() end)

    if not BridgeServer.hasMark(pid) or issuedMap()[pid] == nil then return end
    BridgeServer.lost[#BridgeServer.lost + 1] = { z = z, pid = pid }
end





local function removeLost()
    local list = BridgeServer.lost
    BridgeServer.lost = {}
    local md = world()
    for _, p in ipairs(list) do
        local z, pid = p.z, p.pid



        local listed = false
        pcall(function() listed = getCell():getZombieList():contains(z) end)
        local where = ""
        pcall(function() where = string.format(" at %.1f %.1f %.0f", z:getX(), z:getY(), z:getZ()) end)
        local e = issuedMap()[pid]
        local owner = e and e.who or nil
        if BridgeData.foreign(z) then
            log("lost body id=" .. tostring(pid) .. " is a body of another NPC mod now, left" .. where)
        elseif stillBody(z, pid) and listed then
            releaseBody(z)
            pcall(function() z:removeFromSquare() end)
            pcall(function() z:removeFromWorld() end)
            BridgeServer.touched[z] = nil
            log("removed lost body id=" .. tostring(pid) .. " of " .. tostring(owner) .. where)
            for who, rec in pairs(md.players) do
                if rec.bodyId == pid then
                    local b = BridgeServer.bodies[who]
                    local alive = false
                    pcall(function()
                        alive = b ~= nil and b ~= z and b:isExistInTheWorld() and not b:isDead() and b:getPersistentOutfitID() == pid
                    end)
                    if not alive then forget(who, rec, "lost body came back from population") end
                end
            end
        else
            log("lost body id=" .. tostring(pid) .. " of " .. tostring(owner) .. " not in zombie list at tick, left" .. where)
        end
    end
end

local function tickPlayer(who, rec)


    if rec.car ~= nil and not rec.testGuest and BridgeServer.online[who] == nil then
        rec.car = nil
        transmit()
        log("car seat of " .. tostring(who) .. " cleared: owner offline")
    end
    if rec.bodyId == nil then return end


    if rec.testGuest then
        currentBody(who, rec)
        return
    end
    local owner = BridgeServer.online[who]
    local body = currentBody(who, rec)
    local now = nowMs()
    local check = BridgeServer.diedCheck[who]
    if check ~= nil and now >= check then
        BridgeServer.diedCheck[who] = nil
        local dead = body == nil
        local seenDead = false
        pcall(function() seenDead = body ~= nil and body:isDead() end)
        if dead or seenDead then
            forget(who, rec, "died, confirmed")
            return
        end
    end
    if body == nil then

        if owner ~= nil then
            BridgeServer.missing[who] = BridgeServer.missing[who] or now
            if now - BridgeServer.missing[who] >= MISSING_MS then
                BridgeServer.missing[who] = nil
                forget(who, rec, "missing while owner online")
            end
        end
        return
    end
    BridgeServer.missing[who] = nil
    if BridgeServer.newSecond then
        pcall(function() rec.lastX, rec.lastY, rec.lastZ = body:getX(), body:getY(), body:getZ() end)
    end
    if owner == nil then

        BridgeServer.offline[who] = BridgeServer.offline[who] or now
        if now - BridgeServer.offline[who] >= OFFLINE_MS then
            BridgeServer.offline[who] = nil
            removeBody(who, rec)
            forget(who, rec, "owner offline")
        end
        return
    end
    BridgeServer.offline[who] = nil
    local ownerDead = false
    pcall(function() ownerDead = owner:isDead() end)
    if ownerDead then
        BridgeServer.deadFor[who] = BridgeServer.deadFor[who] or now
        if now - BridgeServer.deadFor[who] >= DEAD_MS then
            BridgeServer.deadFor[who], BridgeServer.undriven[who] = nil, nil
            removeBody(who, rec)
            forget(who, rec, "owner dead for 30 s")
            return
        end
        local driver = nil
        pcall(function() driver = body:getOwnerPlayer() end)
        if driver ~= owner then
            BridgeServer.undriven[who] = BridgeServer.undriven[who] or now
            if now - BridgeServer.undriven[who] >= UNDRIVEN_MS then
                BridgeServer.deadFor[who], BridgeServer.undriven[who] = nil, nil
                removeBody(who, rec)
                forget(who, rec, "owner dead, body driven by another client")
                return
            end
        else
            BridgeServer.undriven[who] = nil
        end
    else
        BridgeServer.deadFor[who], BridgeServer.undriven[who] = nil, nil
    end


    if BridgeData.modeOf(rec) == "follow" and BridgeServer.newSecond
        and dist(owner, body:getX(), body:getY()) > HOME_FAR * 2 then
        removeBody(who, rec)
        forget(who, rec, "owner far from following companion")
        return
    end
    if BridgeData.modeOf(rec) ~= "follow" and BridgeServer.newSecond then


        if dist(owner, body:getX(), body:getY()) > HOME_FAR then
            if rec.waitX == nil then rec.waitX, rec.waitY, rec.waitZ = body:getX(), body:getY(), body:getZ() end
            removeBody(who, rec)
            forget(who, rec, "owner far from waiting companion")
            return
        end
    end
    pcall(function()
        if body:getTarget() ~= owner then body:setTarget(owner) end
    end)
end










local function restorePanic(who, p)
    local v = BridgeServer.panicSaved[who]
    if v == nil then return end
    BridgeServer.panicSaved[who] = nil
    if p == nil then return end
    pcall(function() p:getBodyDamage():setPanicIncreaseValue(v) end)
end

local function bodyNear(p, bodies)
    for b in pairs(bodies) do
        local near = false
        pcall(function()
            near = math.abs(b:getZ() - p:getZ()) < 0.8 and dist(p, b:getX(), b:getY()) < PANIC_BODY_RADIUS
        end)
        if near then return true end
    end
    return false
end

local function othersNear(p, bodies)
    local found = false
    pcall(function()
        local list = getCell():getZombieList()
        local px, py, pz = p:getX(), p:getY(), p:getZ()
        for i = 0, list:size() - 1 do
            local z = list:get(i)

            if z ~= nil and not bodies[z] and z:isAlive() and math.abs(z:getZ() - pz) < 0.8
                and not BridgeData.harmless(z) then
                local dx, dy = z:getX() - px, z:getY() - py
                if dx * dx + dy * dy < PANIC_RADIUS * PANIC_RADIUS then found = true return end
            end
        end
    end)
    return found
end










function BridgeServer.suppressPanic(who, p, body)
    if p == nil or body == nil then return end
    local bodies = {}
    for _, b in pairs(BridgeServer.bodies) do bodies[b] = true end
    bodies[body] = true
    local near = bodyNear(p, { [body] = true })
    local others = othersNear(p, bodies)
    local keep = (not near) or others
    BridgeServer.panicKeep[who] = keep
    local level = "?"
    pcall(function() level = string.format("%.1f", p:getStats():get(CharacterStat.PANIC)) end)
    if keep then

        local why = others and "others" or "far"
        if not near then pcall(function() why = why .. string.format(" d=%.1f", dist(p, body:getX(), body:getY())) end) end
        log("panic at spawn for " .. tostring(who) .. ": kept as in game (" .. why .. "), level=" .. level)
    else
        pcall(function()
            local bd = p:getBodyDamage()
            if BridgeServer.panicSaved[who] == nil then
                BridgeServer.panicSaved[who] = bd:getPanicIncreaseValue()
                bd:setPanicIncreaseValue(0)
            end
        end)
        log("panic at spawn for " .. tostring(who) .. ": increase off, level=" .. level)
    end

    local now = nil
    pcall(function() now = getTimestampMs() end)
    if now ~= nil and BridgeServer.verbose then BridgeServer.panicWatch[who] = { untilMs = now + 5000, nextMs = now + 500 } end





    for other, op in pairs(BridgeServer.online) do
        if other ~= who and op ~= nil and op ~= p then
            local okN, errN = pcall(function()
                if not bodyNear(op, { [body] = true }) then return end
                local othersN = othersNear(op, bodies)
                BridgeServer.panicKeep[other] = othersN
                local levelN = "?"
                pcall(function() levelN = string.format("%.1f", op:getStats():get(CharacterStat.PANIC)) end)
                if othersN then
                    log("panic at spawn for " .. tostring(who) .. ": neighbour " .. tostring(other) .. " kept as in game (others), level=" .. levelN)
                    return
                end
                local bd = op:getBodyDamage()
                if BridgeServer.panicSaved[other] == nil then
                    BridgeServer.panicSaved[other] = bd:getPanicIncreaseValue()
                    bd:setPanicIncreaseValue(0)
                end
                log("panic at spawn for " .. tostring(who) .. ": neighbour " .. tostring(other) .. " increase off, level=" .. levelN)
                if now ~= nil and BridgeServer.verbose then BridgeServer.panicWatch[other] = { untilMs = now + 5000, nextMs = now + 500 } end
            end)
            if not okN then warn("panic at spawn: neighbour " .. tostring(other) .. " failed: " .. tostring(errN)) end
        end
    end
end

local function watchPanic(who, p)
    local w = BridgeServer.panicWatch[who]
    if w == nil then return end
    if not BridgeServer.verbose then BridgeServer.panicWatch[who] = nil return end
    local now = nil
    pcall(function() now = getTimestampMs() end)
    if now == nil or now > w.untilMs then BridgeServer.panicWatch[who] = nil return end
    if now < w.nextMs then return end
    w.nextMs = now + 500
    local level, inc = "?", "?"
    pcall(function() level = string.format("%.1f", p:getStats():get(CharacterStat.PANIC)) end)
    pcall(function() inc = tostring(p:getBodyDamage():getPanicIncreaseValue()) end)
    log("panic watch " .. tostring(who) .. ": level=" .. level .. " increase=" .. inc .. " keep=" .. tostring(BridgeServer.panicKeep[who]))
end

local function tickPanic(who, p, bodies)
    pcall(watchPanic, who, p)
    if BridgeServer.panicKeep[who] == nil or BridgeServer.tick % PANIC_EVERY == 0 then
        BridgeServer.panicKeep[who] = (not bodyNear(p, bodies)) or othersNear(p, bodies)
    end
    if BridgeServer.panicKeep[who] then restorePanic(who, p) return end


    pcall(function()
        local bd = p:getBodyDamage()
        if BridgeServer.panicSaved[who] == nil then
            BridgeServer.panicSaved[who] = bd:getPanicIncreaseValue()
            bd:setPanicIncreaseValue(0)
        end
    end)
end










local ANIMAL_NEAR = 12
BridgeServer.animalFlag = {}

local function animalFlagOff()
    for b in pairs(BridgeServer.animalFlag) do
        pcall(function() b:setReanimatedForGrappleOnly(false) end)
    end
    BridgeServer.animalFlag = {}
end
BridgeServer.animalFlagOff = animalFlagOff

local function animalFlagOn()

    animalFlagOff()
    local online = 0
    pcall(function() online = getOnlinePlayers():size() end)
    if online == 0 then return end
    local animals = {}
    pcall(function()
        local it = getCell():getAnimals():iterator()
        while it:hasNext() do
            local a = it:next()
            if a ~= nil and not a:isDead() then animals[#animals + 1] = { x = a:getX(), y = a:getY(), z = a:getZ() } end
        end
    end)
    if #animals == 0 then return end
    for who, rec in pairs(world().players) do
        local b = BridgeServer.bodies[who]
        local ok, bx, by, bz = false, 0, 0, 0
        pcall(function()
            ok = b ~= nil and rec.bodyId ~= nil and not b:isDead() and b:getCurrentSquare() ~= nil
                and b:getPersistentOutfitID() == rec.bodyId and not b:isReanimatedForGrappleOnly()
            if ok then bx, by, bz = b:getX(), b:getY(), b:getZ() end
        end)
        if ok then
            for _, a in ipairs(animals) do
                local dx, dy = a.x - bx, a.y - by
                if math.abs(a.z - bz) <= 1 and dx * dx + dy * dy <= ANIMAL_NEAR * ANIMAL_NEAR then
                    local set = pcall(function() b:setReanimatedForGrappleOnly(true) end)
                    if set then BridgeServer.animalFlag[b] = true end
                    break
                end
            end
        end
    end
end
BridgeServer.animalFlagOn = animalFlagOn









local GUEST = "test.guest"
BridgeServer.GUEST = GUEST
local function guestWanted()
    local want = nil
    pcall(function()
        local r = getFileReader("bridge/test_guest.txt", false)
        if r == nil then return end
        for _ = 1, 5 do
            local line = r:readLine()
            if line == nil then break end

            if string.byte(line, 1) == 65279 then line = string.sub(line, 2) end
            line = string.gsub(line, "^\239\187\191", "")
            line = string.gsub(line, "^%s+", "")
            line = string.gsub(line, "%s+$", "")
            if line ~= "" then
                want = line
                break
            end
        end
        r:close()
    end)
    return want
end

local GUEST_SPOTS = { { 2, 0 }, { 0, 2 }, { -2, 0 }, { 0, -2 }, { 2, 1 }, { 1, 2 }, { -1, 2 }, { -2, 1 },
    { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function guestSpot(x, y, z)
    local cell = getCell()
    local own = cell:getGridSquare(x, y, z)
    if own == nil then return x, y end
    local room = own:getRoom()
    for _, d in ipairs(GUEST_SPOTS) do
        local sq = cell:getGridSquare(x + d[1], y + d[2], z)
        if sq ~= nil and sq:getRoom() == room and sq:isFree(false) then return x + d[1], y + d[2] end
    end
    return x, y
end
BridgeServer.guestSpot = guestSpot
local function guestTick()
    if BridgeBuild == nil or BridgeBuild.test ~= true then return end
    local want = guestWanted()
    local md = world()
    local rec = md.players[GUEST]
    if rec ~= nil and not rec.testGuest then
        if not BridgeServer.guestClash then
            BridgeServer.guestClash = true
            log("test guest: record " .. GUEST .. " is not a guest, left alone")
        end
        return
    end
    local function off(why)
        if rec == nil then return end
        if rec.bodyId ~= nil then removeBody(GUEST, rec) end
        forget(GUEST, rec, why)
        md.players[GUEST] = nil
        transmit()
        log("test guest removed")
    end
    if want == nil then return off("test guest off") end

    if rec ~= nil and rec.guestOf ~= want then off("test guest moves to " .. tostring(want)) rec = nil end
    if rec ~= nil and rec.bodyId ~= nil and currentBody(GUEST, rec) ~= nil then return end
    local p = BridgeServer.online[want]
    if p == nil then
        if BridgeServer.guestAbsent ~= want then
            BridgeServer.guestAbsent = want
            log("test guest: player " .. tostring(want) .. " is not online")
        end
        return
    end
    BridgeServer.guestAbsent = nil
    local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())

    local gx, gy = x + 2, y
    pcall(function() gx, gy = guestSpot(x, y, z) end)
    local body, why = createBody(gx, gy, z)
    if body == nil then body, why = createBody(x, y, z) end
    if body == nil then
        log("test guest failed: " .. tostring(why))
        return
    end
    rec = record(GUEST)
    rec.testGuest = true
    rec.guestOf = want
    companionFlags(body)
    rec.bodyId = body:getPersistentOutfitID()
    issue(rec.bodyId, GUEST)
    BridgeServer.touched[body] = rec.bodyId
    rec.onlineId = nil
    pcall(function() rec.onlineId = body:getOnlineID() end)
    rec.want = true
    BridgeServer.bodies[GUEST] = body

    for w in pairs(BridgeServer.online) do BridgeServer.panicKeep[w] = nil end
    transmit()
    log("test guest body id=" .. tostring(rec.bodyId) .. " near " .. tostring(want) .. " at " .. tostring(x) .. " " .. tostring(y) .. " " .. tostring(z)
        .. ", guest at " .. tostring(gx) .. " " .. tostring(gy))
end
BridgeServer.guestTick = guestTick

local function onTick()

    pcall(animalFlagOff)
    BridgeServer.tick = BridgeServer.tick + 1

    local sec = math.floor(nowMs() / 1000)
    BridgeServer.newSecond = sec ~= BridgeServer.lastSecond
    BridgeServer.lastSecond = sec


    if #BridgeServer.lost > 0 then
        local ok, err = pcall(removeLost)
        if not ok then warn("remove lost failed: " .. tostring(err)) end
    end

    if BridgeServer.newSecond and sec % 10 == 0 then
        local on = false
        pcall(function()
            local reader = getFileReader("bridge/verbose.txt", false)
            if reader ~= nil then
                on = true
                reader:close()
            end
        end)
        if on ~= BridgeServer.verbose then
            BridgeServer.verbose = on
            log("verbose log " .. (on and "on" or "off"))
        end
    end

    if BridgeServer.newSecond and sec % 10 == 0 and tripModOn() then
        for _, b in pairs(BridgeServer.bodies) do
            pcall(function() b:getModData().tzCooldown = TRIP_IGNORE end)
        end
    end


    local count = nil
    pcall(function() count = getOnlinePlayers():size() end)
    if BridgeServer.tick % 10 == 0 or (count ~= nil and count ~= BridgeServer.onlineCount) then
        if count ~= nil and BridgeServer.onlineCount ~= nil and count ~= BridgeServer.onlineCount then
            log("players online " .. tostring(BridgeServer.onlineCount) .. " -> " .. tostring(count) .. ", list refreshed at once")
        end
        BridgeServer.onlineCount = count
        refreshOnline()
    end
    if BridgeServer.newSecond and sec % 10 == 0 then
        for _, b in pairs(BridgeServer.bodies) do
            pcall(function() b:getModData().RandomZedsExcluded = true end)
        end
        if BridgeCompat ~= nil then pcall(BridgeCompat.install) end
    end

    if BridgeServer.newSecond and sec % 10 == 0 then
        local okG, errG = pcall(guestTick)
        if not okG then warn("test guest failed: " .. tostring(errG)) end
    end
    local md = world()
    local bodies = {}
    for who, rec in pairs(md.players) do
        local ok, err = pcall(tickPlayer, who, rec)
        if not ok and BridgeServer.tick % 600 == 0 then warn("tick " .. tostring(who) .. " failed: " .. tostring(err)) end
        local b = BridgeServer.bodies[who]
        if b ~= nil and rec.bodyId ~= nil then bodies[b] = true end
    end
    for who, p in pairs(BridgeServer.online) do
        local ok, err = pcall(tickPanic, who, p, bodies)
        if not ok and BridgeServer.tick % 600 == 0 then warn("panic " .. tostring(who) .. " failed: " .. tostring(err)) end
    end
end

local function onInit()
    local md = world()
    BridgeServer.issued = nil

    local guests = {}
    for who, rec in pairs(md.players) do
        if rec.testGuest then guests[#guests + 1] = who end
    end
    for _, who in ipairs(guests) do md.players[who] = nil end
    local n = 0



    for who, rec in pairs(md.players) do
        n = n + 1
        rec.bodyId = nil
        rec.onlineId = nil
        rec.oldBodyId = nil

        rec.car = nil


        rec.oldIds = nil
    end
    local ids = 0
    pcall(function() ids = #issuedStore().ids end)
    log("store ready, players=" .. tostring(n) .. ", issued body ids=" .. tostring(ids))

    local okJ, errJ = pcall(journalStart, md)
    if not okJ then warn("journal start failed: " .. tostring(errJ)) end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnInitGlobalModData.Add(onInit)
Events.OnTick.Add(onTick)
Events.OnTickEvenPaused.Add(function()
    local ok, err = pcall(animalFlagOn)
    if not ok then warn("animals flag failed: " .. tostring(err)) end
end)
Events.OnZombieCreate.Add(onZombieCreate)
log("loaded v" .. tostring(BridgeServer.version))

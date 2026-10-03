
























BridgeBackup = BridgeBackup or {}

local VERSION = "SWMBK1"
local HOLD = 1200
local CHECK_EVERY = 60
local WRITE_GAP = 30
local FLUSH_EVERY = 3600
local ISSUED_KEY = "NotAloneIssued"

BridgeBackup.key = nil
BridgeBackup.seq = 0
BridgeBackup.base = 0
BridgeBackup.slot = 1
BridgeBackup.dirty = false
BridgeBackup.lastWrite = -99999
BridgeBackup.sig = nil
BridgeBackup.items = {}
BridgeBackup.held = {}
BridgeBackup.writes = 0
BridgeBackup.restored = nil

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeBackup] " .. tostring(text)) end end
local function warn(text) print("[BridgeBackup] " .. tostring(text)) end

local function active()
    if BridgeBackup.off then return false end
    local mp = false
    pcall(function() mp = isClient() or isServer() end)
    return not mp
end


local function worldKey()
    local key = nil
    pcall(function()
        local w = getWorld()
        key = tostring(w:getGameMode()) .. "_" .. tostring(w:getWorld())
    end)
    if key == nil then return nil end
    return (string.gsub(key, "[^%w%-_]", "_"))
end

local function fileName(key, slot)
    return "bridge/backup_" .. key .. "_" .. tostring(slot) .. ".txt"
end


local function escWho(who)
    return (string.gsub(BridgeItems.esc(tostring(who)), " ", "%%20"))
end

local function unescWho(text)
    return BridgeItems.unesc((string.gsub(text, "%%20", " ")))
end

local function joinIds(ids, n)
    local out = {}
    for i = 1, n or #ids do out[i] = tostring(ids[i] or 0) end
    return table.concat(out, ".")
end

local function splitIds(text)
    local out = {}
    for v in string.gmatch(text or "", "[^%.]+") do out[#out + 1] = tonumber(v) or 0 end
    return out
end


local function countRecords(enc)
    if enc == nil or enc == "" then return 0 end
    local _, commas = string.gsub(enc, ",", ",")
    return commas + 1
end



function BridgeBackup.idsOf(body)
    local out = {}
    pcall(function()
        local function walk(container)
            local items = container:getItems()
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item ~= nil then
                    out[#out + 1] = item:getID()
                    local isBag = false
                    pcall(function() isBag = item:IsInventoryContainer() end)
                    if isBag then walk(item:getInventory()) end
                end
            end
        end
        walk(body:getInventory())
    end)
    return out
end


local function playerIds(red)
    local set = {}
    pcall(function()
        local function walk(container)
            local items = container:getItems()
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item ~= nil then
                    set[item:getID()] = tostring(item:getType())
                    local isBag = false
                    pcall(function() isBag = item:IsInventoryContainer() end)
                    if isBag then walk(item:getInventory()) end
                end
            end
        end
        walk(red:getInventory())
    end)
    return set
end





local TAKEN_KEY = "NotAloneTaken"
local function markTaken(red, id, on)
    if red == nil or id == nil or id == 0 then return end
    pcall(function()
        local md = red:getModData()
        local t = md[TAKEN_KEY]
        if on then
            if type(t) ~= "table" then t = {} md[TAKEN_KEY] = t end
            t[tostring(id)] = true
        elseif type(t) == "table" then
            t[tostring(id)] = nil
        end
    end)
end
BridgeBackup.markTaken = markTaken

local function inPlayer(red, id)
    local found = false
    pcall(function() found = red:getInventory():getItemWithIDRecursiv(id) ~= nil end)
    return found
end



local function subtree(list, ids, i)
    local map, recs, rids = { [i] = 1 }, {}, {}
    local function copy(rec)
        local c = {}
        for k, v in pairs(rec) do c[k] = v end
        return c
    end
    local root = copy(list[i])
    root.p = nil
    recs[1], rids[1] = root, ids[i]
    for j = i + 1, #list do
        local p = list[j].p
        if p ~= nil and map[p] ~= nil then
            local c = copy(list[j])
            c.p = map[p]
            recs[#recs + 1] = c
            rids[#rids + 1] = ids[j]
            map[j] = #recs
        end
    end
    return recs, rids, map
end


local function holdTaken(who, prev, ids)
    if prev == nil or prev.enc == nil or prev.ids == nil then return end
    local red = BridgeData.owner()
    if red == nil then return end
    local now = {}
    for _, id in ipairs(ids) do now[id] = true end
    local list, covered = nil, {}
    local n = math.min(#prev.ids, countRecords(prev.enc))
    for i = 1, n do
        local id = prev.ids[i]
        if id ~= nil and id ~= 0 and not now[id] and not covered[i] and inPlayer(red, id) then
            list = list or BridgeItems.decode(prev.enc)
            if list[i] ~= nil then
                local recs, rids, map = subtree(list, prev.ids, i)
                for j in pairs(map) do covered[j] = true end
                BridgeBackup.held[who] = BridgeBackup.held[who] or {}
                table.insert(BridgeBackup.held[who], { recs = recs, ids = rids, untilT = Bridge.time + HOLD, t = list[i].t })


                for _, rid in ipairs(rids) do markTaken(red, rid, true) end
                log("hold taken " .. tostring(list[i].t) .. " id=" .. tostring(id) .. " with " .. tostring(#recs - 1) .. " inside")
            end
        end
    end
end



function BridgeBackup.noteItems(body, encoded)
    if not active() or BridgeBackup.key == nil or body == nil then return end
    local who = BridgeData.me()
    if who == nil then return end
    local ids = BridgeBackup.idsOf(body)


    local sig = nil
    pcall(function() sig = BridgeItems.signature(BridgeItems.decode(encoded)) end)
    local prev = BridgeBackup.items[who]
    if prev ~= nil and sig ~= nil and prev.sig == sig and joinIds(prev.ids) == joinIds(ids) then
        prev.enc = encoded
        return
    end
    holdTaken(who, prev, ids)

    local groups = BridgeBackup.held[who]
    if groups ~= nil then
        local have = {}
        for _, id in ipairs(ids) do have[id] = true end
        local red0 = BridgeData.owner()
        for g = #groups, 1, -1 do

            for _, rid in ipairs(groups[g].ids) do
                if have[rid] then markTaken(red0, rid, false) end
            end
            if have[groups[g].ids[1]] then table.remove(groups, g) end
        end
    end
    BridgeBackup.items[who] = { enc = encoded, ids = ids, sig = sig }
    BridgeBackup.dirty = true
end

local function issuedStore()
    local s = nil
    pcall(function() s = ModData.getOrCreate(ISSUED_KEY) end)
    return s
end




local function fields(rec, without)
    local t = {}
    for k, v in pairs(rec) do
        if k ~= "items" and not (without and (k == "lastX" or k == "lastY" or k == "lastZ")) then t[k] = v end
    end
    if without and type(rec.rel) == "table" then
        local r = {}
        for k, v in pairs(rec.rel) do if k ~= "seen" and k ~= "hours" then r[k] = v end end
        t.rel = r
    end
    return BridgeItems.packTable(t) or ""
end


local function issuedSig(s)
    if s == nil or type(s.ids) ~= "table" then return "" end
    local last = s.ids[#s.ids]
    return tostring(#s.ids) .. ":" .. tostring(type(last) == "table" and last.id or "") ..
        ":" .. tostring(s.nakedIdx) .. ":" .. tostring(s.mods)
end



local function issuedLines(s)
    local sig = issuedSig(s)
    if BridgeBackup.issuedCache ~= nil and BridgeBackup.issuedCache.sig == sig then return BridgeBackup.issuedCache.lines end
    local lines = {}
    if s ~= nil then
        local rest = {}
        for k, v in pairs(s) do if k ~= "ids" then rest[k] = v end end
        lines[#lines + 1] = "Q " .. (BridgeItems.packTable(rest) or "")
        if type(s.ids) == "table" then
            for _, e in ipairs(s.ids) do
                if type(e) == "table" then lines[#lines + 1] = "E " .. (BridgeItems.packTable(e) or "") end
            end
        end
    end
    BridgeBackup.issuedCache = { sig = sig, lines = table.concat(lines, "\n") }
    return BridgeBackup.issuedCache.lines
end

local function sortedWho(players)
    local out = {}
    for who in pairs(players) do
        if type(who) == "string" then out[#out + 1] = who end
    end
    table.sort(out)
    return out
end

local function signature(md)
    local parts = {}
    for _, who in ipairs(sortedWho(md.players)) do
        local rec = md.players[who]
        if type(rec) == "table" then


            local cur = BridgeBackup.items[who]
            local items = tostring(rec.items or "")
            if cur ~= nil and cur.enc == rec.items and cur.sig ~= nil then items = cur.sig .. "\n" .. joinIds(cur.ids) end
            parts[#parts + 1] = who .. "\n" .. fields(rec, true) .. "\n" .. items
            for _, g in ipairs(BridgeBackup.held[who] or {}) do parts[#parts + 1] = "h" .. tostring(g.ids[1]) end
        end
    end
    parts[#parts + 1] = "q" .. issuedSig(issuedStore())
    return table.concat(parts, "\n")
end


function BridgeBackup.fullState(md)
    local parts = {}
    for _, who in ipairs(sortedWho(md.players)) do
        local rec = md.players[who]
        if type(rec) == "table" then parts[#parts + 1] = fields(rec, false) .. "\n" .. tostring(rec.items or "") end
    end
    return table.concat(parts, "\n")
end



function BridgeBackup.write(md, sig)
    local key = BridgeBackup.key
    if key == nil or md == nil or md.players == nil then return false end
    local seq = BridgeBackup.seq + 1
    local lines = { VERSION, "seq " .. tostring(seq), "base " .. tostring(BridgeBackup.base), "world " .. key }
    pcall(function() lines[#lines + 1] = "age " .. string.format("%.3f", getGameTime():getWorldAgeHours()) end)
    for _, who in ipairs(sortedWho(md.players)) do
        local rec = md.players[who]
        if type(rec) == "table" then
            local w = escWho(who)
            lines[#lines + 1] = "P " .. w .. " " .. fields(rec, false)
            if rec.items ~= nil and rec.items ~= "" then
                lines[#lines + 1] = "I " .. w .. " " .. tostring(rec.items)
                local cur = BridgeBackup.items[who]
                if cur ~= nil and cur.enc == rec.items and cur.ids ~= nil then
                    lines[#lines + 1] = "D " .. w .. " " .. joinIds(cur.ids, math.min(#cur.ids, countRecords(rec.items)))
                elseif rec.bkIds ~= nil then


                    lines[#lines + 1] = "D " .. w .. " " .. tostring(rec.bkIds)
                end
            end
            for _, g in ipairs(BridgeBackup.held[who] or {}) do
                lines[#lines + 1] = "H " .. w .. " " .. joinIds(g.ids) .. " " .. BridgeItems.encode(g.recs)
            end
        end
    end
    local issued = issuedLines(issuedStore())
    if issued ~= "" then lines[#lines + 1] = issued end
    lines[#lines + 1] = "END " .. tostring(seq)
    local ok, err = pcall(function()
        local writer = getFileWriter(fileName(key, BridgeBackup.slot), true, false)
        writer:write(table.concat(lines, "\n") .. "\n")
        writer:close()
    end)
    if not ok then
        warn("write failed: " .. tostring(err))
        return false
    end
    BridgeBackup.seq = seq
    BridgeBackup.slot = (BridgeBackup.slot == 1) and 2 or 1
    BridgeBackup.sig = sig
    BridgeBackup.dirty = false
    BridgeBackup.lastWrite = Bridge.time
    BridgeBackup.writes = BridgeBackup.writes + 1
    BridgeBackup.flushed = BridgeBackup.fullState(md)
    if Bridge.verbose then log("written seq=" .. tostring(seq) .. " base=" .. tostring(BridgeBackup.base) .. " lines=" .. tostring(#lines)) end
    return true
end


local function readFile(key, slot)
    local lines = {}
    local ok = pcall(function()
        local reader = getFileReader(fileName(key, slot), false)
        if reader == nil then return end
        while true do
            local line = reader:readLine()
            if line == nil then break end
            lines[#lines + 1] = line
        end
        reader:close()
    end)
    if not ok or #lines < 3 or lines[1] ~= VERSION then return nil end
    local f = { players = {}, issued = nil, entries = {} }
    for i = 2, #lines do
        local line = lines[i]
        local kind, rest = string.match(line, "^(%a+) ?(.*)$")
        if kind == "seq" then f.seq = tonumber(rest)
        elseif kind == "base" then f.base = tonumber(rest)
        elseif kind == "world" then f.world = rest
        elseif kind == "age" then f.age = tonumber(rest)
        elseif kind == "END" then f.done = tonumber(rest)
        elseif kind == "Q" then f.issued = BridgeItems.unpackTable(rest)
        elseif kind == "E" then f.entries[#f.entries + 1] = BridgeItems.unpackTable(rest)
        elseif kind == "P" or kind == "I" or kind == "D" or kind == "H" then
            local w, body = string.match(rest, "^(%S+) ?(.*)$")
            if w ~= nil then
                local who = unescWho(w)
                local p = f.players[who]
                if p == nil then p = { held = {} } f.players[who] = p end
                if kind == "P" then p.rec = BridgeItems.unpackTable(body)
                elseif kind == "I" then p.items = body
                elseif kind == "D" then p.ids = splitIds(body)
                else
                    local ids, enc = string.match(body, "^(%S+) (.*)$")
                    if ids ~= nil then p.held[#p.held + 1] = { ids = splitIds(ids), enc = enc } end
                end
            end
        end
    end
    if f.seq == nil or f.done ~= f.seq or f.base == nil or f.world ~= key then return nil end
    return f
end



function BridgeBackup.check(md)
    if not active() or md == nil then return end
    local key = worldKey()
    if key == nil or BridgeBackup.key == key then return end
    BridgeBackup.key = key
    local mdSeq = tonumber(md.backupSeq) or 0
    BridgeBackup.base = mdSeq
    BridgeBackup.seq = mdSeq
    BridgeBackup.items, BridgeBackup.held, BridgeBackup.sig = {}, {}, nil
    BridgeBackup.dirty, BridgeBackup.lastWrite, BridgeBackup.restored = false, -99999, nil
    local best, bestSlot, top = nil, nil, mdSeq
    for slot = 1, 2 do
        local f = readFile(key, slot)
        if f ~= nil then
            if f.seq > top then top = f.seq end
            if best == nil or f.seq > best.seq then best, bestSlot = f, slot end
        end
    end


    BridgeBackup.seq = top
    if bestSlot ~= nil then BridgeBackup.slot = (bestSlot == 1) and 2 or 1 end



    BridgeBackup.clearTakenPending = true
    if best == nil then
        log("no backup for " .. key .. ", world seq " .. tostring(mdSeq))
        return
    end
    if best.seq <= mdSeq then
        log("clean: backup seq " .. tostring(best.seq) .. ", world seq " .. tostring(mdSeq))
        return
    end
    if best.base ~= mdSeq then
        log("backup ignored: base " .. tostring(best.base) .. " is not world seq " .. tostring(mdSeq) .. " (older copy of the save?)")
        return
    end

    BridgeBackup.clearTakenPending = nil
    if md.players == nil then md.players = {} end
    local summary = {}
    for who, p in pairs(best.players) do
        if type(p.rec) == "table" then
            local rec = p.rec
            local list = BridgeItems.decode(p.items or "")
            local ids = {}
            for i = 1, #list do ids[i] = (p.ids and p.ids[i]) or 0 end
            BridgeBackup.dedupePending = true
            local base, back = #list, 0
            for _, g in ipairs(p.held) do
                local recs = BridgeItems.decode(g.enc or "")
                local start = #list
                for j, r in ipairs(recs) do
                    if r.p ~= nil then r.p = r.p + start end
                    list[#list + 1] = r
                    ids[#list] = g.ids[j] or 0
                end
                back = back + #recs
            end
            if #list > 0 then
                rec.items = BridgeItems.encode(list)
                rec.saved = 1


                rec.bkIds = joinIds(ids)
            elseif rec.saved == 1 then


                rec.items = ""
            else
                rec.items = nil
            end
            md.players[who] = rec
            summary[#summary + 1] = who .. ": " .. tostring(base) .. " items, " .. tostring(back) .. " taken back to check"
        end
    end
    local s = issuedStore()
    if s ~= nil then
        if type(s.ids) ~= "table" then s.ids = {} end
        local known = {}
        for _, e in ipairs(s.ids) do if type(e) == "table" and e.id ~= nil then known[e.id] = true end end
        local added = 0
        for _, e in ipairs(best.entries) do
            if e.id ~= nil and not known[e.id] then
                table.insert(s.ids, e)
                known[e.id] = true
                added = added + 1
            end
        end
        if type(best.issued) == "table" then
            for k, v in pairs(best.issued) do s[k] = v end
        end
        if BridgeRemnant ~= nil then BridgeRemnant.map = nil end
        summary[#summary + 1] = "issued +" .. tostring(added)
    end
    BridgeBackup.restored = { seq = best.seq, base = mdSeq, age = best.age, text = table.concat(summary, "; ") }
    log("restored after crash: backup seq " .. tostring(best.seq) .. " over world seq " .. tostring(mdSeq) ..
        ", age " .. tostring(best.age) .. "; " .. table.concat(summary, "; "))
end



function BridgeBackup.dedupe(rec)
    if not active() or type(rec) ~= "table" or rec.bkIds == nil then return end
    local red = BridgeData.owner()
    if red == nil then return end
    local ids = splitIds(rec.bkIds)
    rec.bkIds = nil
    local list = BridgeItems.decode(rec.items or "")
    if #list == 0 then return end
    local have = playerIds(red)
    local taken = nil
    pcall(function() taken = red:getModData()[TAKEN_KEY] end)
    if type(taken) ~= "table" then taken = {} end
    local drop, seen = {}, {}
    local mine, twice, inside, freed = {}, 0, 0, 0
    for i = 1, #list do
        local id = ids[i]
        local p = list[i].p
        local atPlayer = id ~= nil and id ~= 0 and (have[id] ~= nil or taken[tostring(id)] == true)
        if p ~= nil and drop[p] and (atPlayer or id == nil or id == 0) then
            drop[i] = true
            inside = inside + 1
        elseif p ~= nil and drop[p] and seen[id] then

            drop[i] = true
            twice = twice + 1
        elseif p ~= nil and drop[p] then


            freed = freed + 1
        elseif atPlayer then
            drop[i] = true
            mine[#mine + 1] = tostring(list[i].t) .. "#" .. tostring(id)
        elseif id ~= nil and id ~= 0 and seen[id] then
            drop[i] = true
            twice = twice + 1
        end
        if id ~= nil and id ~= 0 then seen[id] = true end
    end
    local out, map = {}, {}
    for i = 1, #list do
        if not drop[i] then
            local r = list[i]
            if r.p ~= nil then r.p = map[r.p] end
            out[#out + 1] = r
            map[i] = #out
        end
    end
    rec.items = BridgeItems.encode(out)
    rec.saved = 1
    pcall(function() red:getModData()[TAKEN_KEY] = nil end)
    if freed > 0 then log("checked with player: " .. tostring(freed) .. " of her items were in a bag he holds, back to her") end
    log("checked with player: kept " .. tostring(#out) .. " of " .. tostring(#list) ..
        ", player has " .. tostring(#mine) .. (#mine > 0 and (" (" .. table.concat(mine, ",") .. ")") or "") ..
        ", inside those " .. tostring(inside) .. ", repeated " .. tostring(twice))
end


function BridgeBackup.tick()
    if not active() or BridgeBackup.key == nil then return end
    local md = Bridge.world
    if md == nil or md.players == nil then return end
    for who, groups in pairs(BridgeBackup.held) do
        for g = #groups, 1, -1 do
            if groups[g].untilT <= Bridge.time then
                for _, rid in ipairs(groups[g].ids) do markTaken(BridgeData.owner(), rid, false) end
                table.remove(groups, g)
                BridgeBackup.dirty = true
            end
        end
    end



    if BridgeBackup.clearTakenPending then
        local red = BridgeData.owner()
        if red ~= nil then
            BridgeBackup.clearTakenPending = nil
            pcall(function() red:getModData()[TAKEN_KEY] = nil end)
        end
    end
    if BridgeBackup.dedupePending then
        local who = BridgeData.me()
        local rec = who and md.players[who]
        if BridgeData.owner() ~= nil then
            BridgeBackup.dedupePending = nil
            if type(rec) == "table" and rec.bkIds ~= nil then pcall(BridgeBackup.dedupe, rec) end
        end
    end
    if Bridge.every(CHECK_EVERY) then

        if Bridge.alive() and Bridge.kind == "zombie" then
            local who = BridgeData.me()
            local rec = who and md.players[who]
            local cur = who and BridgeBackup.items[who]
            if type(rec) == "table" and rec.items ~= nil and (cur == nil or cur.enc == rec.items) then
                local ids = BridgeBackup.idsOf(Bridge.body)
                if #ids == countRecords(rec.items) and (cur == nil or joinIds(ids) ~= joinIds(cur.ids)) then
                    if cur ~= nil then holdTaken(who, cur, ids) end
                    local sig = cur and cur.sig or nil
                    if sig == nil then pcall(function() sig = BridgeItems.signature(BridgeItems.decode(rec.items)) end) end
                    BridgeBackup.items[who] = { enc = rec.items, ids = ids, sig = sig }
                end
            end
        end
        local sig = signature(md)
        if sig ~= BridgeBackup.sig then BridgeBackup.dirty = true end
    end

    if Bridge.every(FLUSH_EVERY, 30) and BridgeBackup.flushed ~= BridgeBackup.fullState(md) then
        BridgeBackup.dirty = true
    end
    if BridgeBackup.dirty and Bridge.time - BridgeBackup.lastWrite >= WRITE_GAP then
        BridgeBackup.write(md, signature(md))
    end
end




function BridgeBackup.flushNow()
    if not active() or BridgeBackup.key == nil or not BridgeBackup.dirty then return false end


    if Bridge.time - BridgeBackup.lastWrite < 5 then return false end
    local md = Bridge ~= nil and Bridge.world or nil
    if md == nil or md.players == nil then return false end
    BridgeBackup.write(md, signature(md))
    return true
end



function BridgeBackup.onSave()
    if not active() or BridgeBackup.key == nil then return end
    local md = Bridge ~= nil and Bridge.world or nil
    if md == nil then return end
    md.backupSeq = BridgeBackup.seq
    BridgeBackup.base = BridgeBackup.seq
end

Events.OnSave.Add(BridgeBackup.onSave)
log("loaded")

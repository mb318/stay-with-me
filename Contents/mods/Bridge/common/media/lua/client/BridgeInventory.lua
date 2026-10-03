




BridgeInventory = BridgeInventory or {}
BridgeInventory.reach = 2.0
BridgeInventory.keep = 4.5
BridgeInventory.keepOpen = 8.0
BridgeInventory.shown = false
BridgeInventory.capacity = 15

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeInventory] " .. tostring(text)) end end
local function warn(text) print("[BridgeInventory] " .. tostring(text)) end


local function note(text)
    if Bridge ~= nil then Bridge.lastItemAction = tostring(text) .. "@" .. tostring(Bridge.tick) end
end


local function codes(...)
    local t = { ... }
    local out = {}
    for i = 1, #t do out[i] = string.char(t[i]) end
    return table.concat(out)
end


local function companionName()
    local name = BridgeData.DEFAULT_NAME
    pcall(function() name = Bridge.companionName() end)
    return name
end

local function label(key)
    local name = companionName()
    local text = name
    pcall(function() text = getText("IGUI_NotAlone_" .. key, name) end)
    return text
end

local function body()
    if Bridge == nil or not Bridge.alive() or Bridge.kind ~= "zombie" then return nil end
    return Bridge.body
end



function BridgeInventory.skin(b, rec)
    b:setFemaleEtc(true)
    local hv = b:getHumanVisual()
    if hv == nil then return false end
    hv:removeDirt()
    hv:removeBlood()




    pcall(function() hv:getBodyVisuals():clear() end)




    pcall(function()
        local own = BridgeWeapon.attached
        local keep = (own ~= nil and BridgeWeapon.body == b) and own.item or nil
        local at = b:getAttachedItems()
        for i = at:size() - 1, 0, -1 do
            local it = at:getItemByIndex(i)
            if it ~= nil and it ~= keep then b:removeAttachedItem(it) end
        end
    end)
    hv:setSkinTextureName("FemaleBody01")
    hv:setHairModel(BridgeData.hairOf(rec))
    hv:setHairColor(ImmutableColor.new(0.55, 0.12, 0.12))
    return true
end

local function refreshPanels()



    local inv, loot = getPlayerInventory(0), getPlayerLoot(0)
    if inv == nil or loot == nil then return end
    pcall(function()
        inv:refreshBackpacks()
        loot:refreshBackpacks()
        ISInventoryPage.renderDirty = true
    end)
end






function BridgeInventory.applyWorn(b)
    local ok, err = pcall(function()
        local visuals = b:getItemVisuals()
        local frozen = BridgeInventory.frozen
        if frozen ~= nil and BridgeInventory.gestureBody == b then

            visuals:clear()
            for _, v in ipairs(frozen) do visuals:add(v) end
        else
            b:getWornItems():getItemVisuals(visuals)
        end
        BridgeInventory.visualCount = visuals:size()
    end)
    if not ok then warn("applyWorn failed: " .. tostring(err)) end

    local shown = {}
    pcall(function()
        local visuals = b:getItemVisuals()
        local worn = b:getWornItems()
        for i = 0, worn:size() - 1 do
            local item = worn:getItemByIndex(i)
            if item ~= nil and item:getVisual() ~= nil and visuals:contains(item:getVisual()) then
                shown[item:getID()] = true
            end
        end
    end)
    BridgeInventory.shownIds = shown
end

BridgeInventory.shownIds = {}










function BridgeInventory.dropFallen(b)
    local fell = {}
    local visuals = b:getItemVisuals()
    local worn = b:getWornItems()
    local inv = b:getInventory()
    for i = worn:size() - 1, 0, -1 do
        local item = worn:getItemByIndex(i)
        local id, vis, chance = nil, nil, 0
        if item ~= nil then
            id, vis = item:getID(), item:getVisual()
            if item:IsClothing() then chance = item:getChanceToFall() end
        end
        if id ~= nil and BridgeInventory.shownIds[id] and vis ~= nil and (chance or 0) > 0
            and not visuals:contains(vis) then
            b:removeWornItem(item)
            inv:Remove(item)
            BridgeInventory.shownIds[id] = nil
            fell[#fell + 1] = tostring(item:getType())
        end
    end
    if #fell > 0 then
        log("dropFallen: fell off, removed from body: " .. table.concat(fell, ","))
        note("fell " .. table.concat(fell, ","))
        refreshPanels()
        pcall(function() BridgeInventory.refreeze(b) end)
    end
    return fell
end


function BridgeInventory.wornList(b)
    local names = {}
    pcall(function()
        local worn = b:getWornItems()
        for i = 0, worn:size() - 1 do
            local item = worn:getItemByIndex(i)
            if item ~= nil then names[#names + 1] = item:getType() end
        end
    end)
    return table.concat(names, ",")
end





function BridgeInventory.dropGone(b)
    local inv = b:getInventory()
    local changed = false
    local dropped = {}



    local function inBody(item)
        return item:getContainer() == inv
    end
    local worn = b:getWornItems()
    for i = worn:size() - 1, 0, -1 do
        local item = worn:getItemByIndex(i)
        if item ~= nil and not inBody(item) then
            b:removeWornItem(item)
            changed = true
            dropped[#dropped + 1] = tostring(item:getType())
        end
    end
    local p, s = b:getPrimaryHandItem(), b:getSecondaryHandItem()
    if p ~= nil and not inBody(p) then b:setPrimaryHandItem(nil) changed = true end
    if s ~= nil and not inBody(s) then b:setSecondaryHandItem(nil) changed = true end
    if #dropped > 0 then
        log("dropGone: worn item not in body inventory: " .. table.concat(dropped, ","))
        note("dropGone " .. table.concat(dropped, ","))
    end
    if changed then pcall(function() BridgeInventory.refreeze(b) end) end
    return changed
end




BridgeInventory.markSuffix = codes(0x20, 0x28, 0x0420, 0x0438, 0x043D, 0x29)

function BridgeInventory.mark(item)
    pcall(function()
        local name = item:getName()
        if name ~= nil and string.sub(name, -#BridgeInventory.markSuffix) ~= BridgeInventory.markSuffix then
            item:setName(name .. BridgeInventory.markSuffix)
        end
    end)
end

function BridgeInventory.markWorn(b)
    pcall(function()
        local worn = b:getWornItems()
        for i = 0, worn:size() - 1 do
            local item = worn:getItemByIndex(i)
            if item ~= nil then BridgeInventory.mark(item) end
        end
        local p = b:getPrimaryHandItem()
        if p ~= nil then BridgeInventory.mark(p) end
    end)
end




function BridgeInventory.isMarked(z)
    local found = false
    pcall(function()
        local worn = z:getWornItems()
        local have = {}
        for i = 0, worn:size() - 1 do
            local item = worn:getItemByIndex(i)
            if item ~= nil then
                local name = item:getName()
                if name ~= nil and string.sub(name, -#BridgeInventory.markSuffix) == BridgeInventory.markSuffix then
                    found = true
                    return
                end
                have[item:getType()] = true
            end
        end
    end)
    return found
end



BridgeInventory.redressUntil = 0

function BridgeInventory.redress(b, force)


    if not force and BridgeInventory.modelBusy(b) then return end
    BridgeInventory.applyWorn(b)
    pcall(function() b:resetModelNextFrame() end)
    pcall(function() b:resetModel() end)
    BridgeInventory.redressUntil = Bridge.time + 300
end


function BridgeInventory.modelBusy(b)
    return b ~= nil and BridgeInventory.frozen ~= nil and BridgeInventory.gestureBody == b
        and #BridgeInventory.gestures > 0
end

local function redress(b)
    BridgeInventory.redress(b)
end




























local GESTURE_ANIM = { Face = "BandageHead", Jacket = "BandageUpperBody", Pullover = "BandageUpperBody",
                       Waist = "BandageLowerBody", Legs = "BandageLeftLeg", Feet = "BandageLeftLeg" }
local GESTURE_DEFAULT = "TreatMid"
local GESTURE_TIME = { BandageLeftLeg = 96 }
local GESTURE_TIME_DEFAULT = 72
local GESTURE_NEAR = 4
local GESTURE_LEAVE = 5






local LOOT_ANIM = "LootLow"
local LOOT_BY_POS = { Low = "LootLow", High = "LootHigh" }
local LOOT_MID = "LootMid"
local function isLootAnim(a) return a == "LootLow" or a == "LootMid" or a == "LootHigh" end


local LOOT_MIN, LOOT_MAX = 36, 3600


local LOOT_NEXT = 12
local GESTURE_IDLE_BUMPS = { [""] = true, ["nil"] = true, Stand = true, ShiftWeight = true, ChewNails = true,
                             WipeBrow = true, PullAtCollar = true, WipeHead = true }
local GESTURE_WAIT_MAX = 5400
local GESTURE_SETTLE = 20
local GESTURE_WAIT_FAR = 15

local GESTURE_NO_WAIT = { fight = true, pose = true, mourning = true, ["check failed"] = true }

local GESTURE_WAIT_CUT = { pose = true, mourning = true, ["check failed"] = true }


BridgeInventory.gestures = BridgeInventory.gestures or {}
BridgeInventory.frozen = BridgeInventory.frozen
BridgeInventory.gestureBody = BridgeInventory.gestureBody
BridgeInventory.gestureAt = BridgeInventory.gestureAt
BridgeInventory.gestureSeen = BridgeInventory.gestureSeen
BridgeInventory.gestureWaitSince = BridgeInventory.gestureWaitSince
BridgeInventory.gestureWaitWhy = BridgeInventory.gestureWaitWhy

local function gestureAnimFor(item)
    local group = nil
    pcall(function()
        local loc = nil
        if item:IsClothing() then loc = item:getBodyLocation() end
        if loc == nil or loc == "" then loc = item:canBeEquipped() end
        if loc ~= nil and loc ~= "" and WearClothingAnimations ~= nil then group = WearClothingAnimations[loc] end
    end)
    return GESTURE_ANIM[group or ""] or GESTURE_DEFAULT
end
BridgeInventory.gestureAnimFor = gestureAnimFor

local function isGestureAnim(bump)
    if bump == GESTURE_DEFAULT or isLootAnim(bump) then return true end
    for _, a in pairs(GESTURE_ANIM) do if a == bump then return true end end
    return false
end


local function modelVisuals(b)
    local out = {}
    pcall(function()
        local v = b:getItemVisuals()
        for i = 0, v:size() - 1 do out[#out + 1] = v:get(i) end
    end)
    return out
end

local function wornVisuals(b)
    local out = {}
    pcall(function()
        local worn = b:getWornItems()
        for i = 0, worn:size() - 1 do
            local item = worn:getItemByIndex(i)
            if item ~= nil and item:getVisual() ~= nil then
                local v = item:getVisual()

                pcall(function() v:setInventoryItem(item) end)
                out[#out + 1] = v
            end
        end
    end)
    return out
end

local function playerNear(b, limit)
    local near = false
    pcall(function()
        local red = BridgeData.owner()
        if red == nil or red:getVehicle() ~= nil then return end
        local dx, dy = b:getX() - red:getX(), b:getY() - red:getY()
        near = dx * dx + dy * dy <= limit * limit and math.abs(b:getZ() - red:getZ()) < 1
    end)
    return near
end



local function startBlocker(b, stuck)
    local why = "check failed"
    pcall(function()


        if BridgeFight ~= nil and (BridgeFight.target ~= nil or BridgeFight.state == "swing") then why = "fight" return end
        if Bridge.mourning ~= nil then why = "mourning" return end
        if Bridge.pose ~= nil then why = "pose" return end
        if not stuck and BridgeMove ~= nil and (BridgeMove.pathing or BridgeMove.moving or BridgeMove.steering) then why = "moving" return end

        if BridgeWeapon ~= nil and BridgeWeapon.redWalking ~= nil and BridgeWeapon.redWalking() then why = "player walking" return end
        if BridgeHeal ~= nil and (BridgeHeal.active or BridgeHeal.current ~= nil) then why = "healing" return end
        if BridgeWash ~= nil and BridgeWash.state ~= "idle" then why = "washing" return end
        if BridgeWeapon ~= nil and BridgeWeapon.busy ~= nil and BridgeWeapon.busy() then why = "weapon move" return end
        local asn = tostring(b:getActionStateName())
        local walking = asn == "walktoward" or asn == "pathfind"
        if walking and not stuck then why = "moving" return end
        if asn ~= "idle" and asn ~= "bumped" and not walking then why = "state " .. asn return end
        local bump = tostring(b:getBumpType())
        if BridgeWeapon ~= nil and BridgeWeapon.isWalkBump ~= nil and BridgeWeapon.isWalkBump(bump) then

            why = (not stuck) and "moving" or nil
            return
        end

        if not GESTURE_IDLE_BUMPS[bump] and not isGestureAnim(bump) then why = "bump " .. bump return end
        why = nil
    end)
    return why
end






local function nearFor(act)
    if act ~= nil and act.bridgeOwn then return GESTURE_LEAVE end
    return GESTURE_NEAR
end




function BridgeInventory.canGesture(b, act)
    if b == nil or Bridge.kind ~= "zombie" then return false, "no body", false end
    if Bridge.hiddenSince ~= nil then return false, "body hidden", false end



    local remote = false
    if Bridge.mp then pcall(function() remote = b:isRemoteZombie() end) end
    if remote then return false, "remote body", false end
    if BridgeInventory.gestureBody == b and #BridgeInventory.gestures > 0 then return true end
    local why = startBlocker(b)
    if why ~= nil then return false, why, not GESTURE_NO_WAIT[why] end
    if not playerNear(b, nearFor(act)) then return false, "player far", false end
    return true
end


function BridgeInventory.gestureRunning()
    return #BridgeInventory.gestures > 0 and BridgeInventory.gestureAt ~= nil
end


local function waitGesture(b, why)
    BridgeInventory.gestureAt = nil
    BridgeInventory.gestureSeen = Bridge.zombieTicks
    BridgeInventory.gestureWaitSince = Bridge.time
    BridgeInventory.gestureWaitWhy = why
    local g = BridgeInventory.gestures[1]
    log(string.format("gesture waits: %s for %s", tostring(why), tostring(g and g.what)))
end

local function startGesture(b)
    local g = BridgeInventory.gestures[1]
    if g == nil then return end
    BridgeInventory.gestureAt = Bridge.time
    BridgeInventory.gestureSeen = Bridge.zombieTicks
    pcall(function() if BridgeMove ~= nil and BridgeMove.onPath() then BridgeMove.stopPath(b) end end)
    pcall(function() b:setBumpType(g.anim) end)
end


function BridgeInventory.gestureFlush(b, why)
    local had = #BridgeInventory.gestures > 0 or BridgeInventory.frozen ~= nil
    local body0 = BridgeInventory.gestureBody
    for _, g in ipairs(BridgeInventory.gestures) do
        if g.item ~= nil and g.action == nil then pcall(function() g.item:setJobDelta(0) end) end
    end
    BridgeInventory.gestures = {}
    BridgeInventory.frozen = nil
    BridgeInventory.gestureAt = nil
    BridgeInventory.gestureWaitSince = nil
    BridgeInventory.gestureWaitWhy = nil
    BridgeInventory.gestureMovingSince = nil
    BridgeInventory.gestureFreeSince = nil
    if not had then return end
    if why ~= nil then log("gesture cut: " .. tostring(why)) end
    BridgeInventory.gestureLog = nil
    local target = b or body0
    if target ~= nil and target == body0 then
        pcall(function() if isGestureAnim(tostring(target:getBumpType())) then target:setBumpType("") end end)
        pcall(function() BridgeInventory.dropGone(target) end)
        BridgeInventory.redress(target, true)
    end
end



function BridgeInventory.gestureWaitingFor(act)
    for i, g in ipairs(BridgeInventory.gestures) do

        if g.action == act then return i > 1 or BridgeInventory.gestureAt == nil end
    end
    return false
end


function BridgeInventory.gestureReset()
    if BridgeQueue ~= nil then pcall(BridgeQueue.clear, "new body") end
    BridgeInventory.gestures = {}
    BridgeInventory.frozen = nil
    BridgeInventory.gestureAt = nil
    BridgeInventory.gestureBody = nil
    BridgeInventory.gestureWaitSince = nil
    BridgeInventory.gestureWaitWhy = nil
    BridgeInventory.gestureMovingSince = nil
    BridgeInventory.gestureFreeSince = nil
end






local function keepable(b, list)
    local out = {}
    for _, v in ipairs(list or {}) do
        local keep = true
        pcall(function()
            local item = v:getInventoryItem()
            if item == nil or b:isEquippedClothing(item) then return end
            if item:IsClothing() and (item:getChanceToFall() or 0) > 0 then keep = false end
        end)
        if keep then out[#out + 1] = v end
    end
    return out
end




function BridgeInventory.refreeze(b)
    if BridgeInventory.frozen == nil or BridgeInventory.gestureBody ~= b then return end
    local before = #BridgeInventory.frozen
    BridgeInventory.frozen = keepable(b, BridgeInventory.frozen)
    for _, g in ipairs(BridgeInventory.gestures) do
        if g.after ~= nil then g.after = keepable(b, g.after) end
    end
    if #BridgeInventory.frozen ~= before then BridgeInventory.rebuild(b) end
end






function BridgeInventory.afterChange(b, item, pre, kind)
    local can, why, wait = BridgeInventory.canGesture(b)
    if not can and not wait then
        if #BridgeInventory.gestures > 0 then BridgeInventory.gestureFlush(b, "cannot gesture now") end
        pcall(function() log("gesture skipped for " .. item:getType() .. ": " .. tostring(why)) end)
        redress(b)
        return false
    end
    local fresh = BridgeInventory.frozen == nil
    if fresh then BridgeInventory.frozen = pre or modelVisuals(b) end
    BridgeInventory.gestureBody = b
    local anim = gestureAnimFor(item)
    local job = nil
    pcall(function()
        job = getText(kind == "unwear" and "ContextMenu_Unequip" or "ContextMenu_Wear") .. " " .. item:getName()
    end)
    table.insert(BridgeInventory.gestures, { anim = anim, dur = GESTURE_TIME[anim] or GESTURE_TIME_DEFAULT, after = wornVisuals(b),
                                             what = tostring(item:getType()), item = item, job = job })

    local before = #BridgeInventory.frozen
    BridgeInventory.frozen = keepable(b, BridgeInventory.frozen)
    for _, g in ipairs(BridgeInventory.gestures) do g.after = keepable(b, g.after) end
    log(string.format("gesture queued: %s for %s (%d in queue)", anim, tostring(item:getType()), #BridgeInventory.gestures))
    if #BridgeInventory.gestures == 1 then
        if can then startGesture(b) else waitGesture(b, why) end
    end

    if #BridgeInventory.frozen ~= before then BridgeInventory.rebuild(b) end
    return true
end


function BridgeInventory.rebuild(b)
    BridgeInventory.applyWorn(b)
    pcall(function() b:resetModelNextFrame() end)
    pcall(function() b:resetModel() end)
end


function BridgeInventory.queuedActions()
    local out = {}
    pcall(function()
        local q = ISTimedActionQueue.getTimedActionQueue(getSpecificPlayer(0))
        for _, a in ipairs(q.queue or {}) do out[#out + 1] = a end
    end)
    if BridgeQueue ~= nil then
        for _, a in ipairs(BridgeQueue.jobs or {}) do out[#out + 1] = a end
    end
    return out
end


function BridgeInventory.actionQueued(act)
    for _, a in ipairs(BridgeInventory.queuedActions()) do
        if a == act then return true end
    end
    return false
end






function BridgeInventory.floorToHer(act)
    return BridgeInventory.herAnimFor(act) ~= nil
end



function BridgeInventory.lootAnimFor(cont)
    local pos = nil
    pcall(function() pos = cont:getContainerPosition() end)
    pcall(function() if cont:getType() == "freezer" and cont:getFreezerPosition() then pos = cont:getFreezerPosition() end end)
    pcall(function() if cont:getType() == "floor" or instanceof(cont:getParent(), "IsoDeadBody") then pos = "Low" end end)
    pcall(function()
        local holder = cont:getContainingItem()
        if holder ~= nil and holder:getWorldItem() ~= nil then pos = "Low" end
    end)
    return LOOT_BY_POS[tostring(pos)] or LOOT_MID
end


local function isWorld(c, red)
    if c == nil or BridgeInventory.inBody(c) then return false end
    local his = false
    pcall(function() his = red ~= nil and c:getOutermostContainer() == red:getInventory() end)
    return not his
end











function BridgeInventory.herAnimFor(act)
    if act == nil or act.srcContainer == nil then return nil end

    if act.bridgeHerLoot then return type(act.bridgeHerLoot) == "string" and act.bridgeHerLoot or LOOT_ANIM end
    local red = act.character
    if isWorld(act.srcContainer, red) then
        if act.bridgeRelay ~= nil or BridgeInventory.inBody(act.destContainer) then
            return BridgeInventory.lootAnimFor(act.srcContainer)
        end
        return nil
    end
    if not BridgeInventory.inBody(act.srcContainer) then return nil end
    local b = body()
    local worn = false
    pcall(function() worn = b ~= nil and b:isEquippedClothing(act.item) end)
    if worn then return gestureAnimFor(act.item) end

    if isWorld(act.finalDest, red) then return BridgeInventory.lootAnimFor(act.finalDest) end
    if isWorld(act.destContainer, red) then return BridgeInventory.lootAnimFor(act.destContainer) end
    if BridgeInventory.inBody(act.destContainer) then return LOOT_MID end
    return nil
end




local function lootSpot(act, b)
    local spot = nil
    pcall(function()
        local wi = act.item:getWorldItem()
        if wi ~= nil then
            local sq = wi:getSquare()
            spot = { sq:getX() + 0.5, sq:getY() + 0.5 }
        end
    end)
    if spot ~= nil then return spot end
    local red = act.character
    local c = nil


    local list = { act.srcContainer, act.finalDest, act.destContainer }
    for i = 1, 3 do
        if c == nil and list[i] ~= nil and isWorld(list[i], red) then c = list[i] end
    end
    if c == nil then return nil end
    pcall(function()
        if c:getType() == "floor" then


            if isClient() then spot = { red:getX(), red:getY() } end
            return
        end
        local p = c:getParent()
        if p ~= nil then
            spot = { p:getX() + ((instanceof(p, "IsoObject") and not instanceof(p, "IsoMovingObject")) and 0.5 or 0),
                     p:getY() + ((instanceof(p, "IsoObject") and not instanceof(p, "IsoMovingObject")) and 0.5 or 0) }



            pcall(function()
                local v = Vector2.new()
                if instanceof(p, "BaseVehicle") then
                    if b == nil then return end
                    p:getFacingPosition(b, v)
                else
                    local o = p
                    if b ~= nil and o:hasSpriteGrid() then o = o:getClosestSpriteGridObject(b:getX(), b:getY()) or o end
                    o:getFacingPosition(v)
                end
                spot = { v:getX(), v:getY() }
            end)
            return
        end
        local sq = c:getSourceGrid()
        if sq ~= nil then spot = { sq:getX() + 0.5, sq:getY() + 0.5 } end
    end)
    return spot
end



function BridgeInventory.lootFor(act, anim)
    local b = body()
    if b == nil then return false end
    anim = anim or LOOT_ANIM
    for _, g in ipairs(BridgeInventory.gestures) do

        if g.action == act then return true end
    end






    local last = BridgeInventory.gestures[1]
    if #BridgeInventory.gestures == 1 and last.action ~= nil and last.anim == anim and isLootAnim(anim)
        and BridgeInventory.gestureAt ~= nil and BridgeInventory.gestureBody == b
        and not BridgeInventory.actionQueued(last.action) then
        local what = "?"
        pcall(function() what = tostring(act.item:getType()) end)
        last.action = act
        last.what = "transfer " .. what
        last.after = wornVisuals(b)
        last.goneAt = nil
        local face = lootSpot(act, b)
        if face ~= nil then
            last.face = face
            pcall(function() b:faceLocationF(face[1], face[2]) end)
        end

        BridgeInventory.gestureAt = Bridge.time - LOOT_MIN
        log(string.format("gesture goes on: %s for transfer %s", anim, what))
        return true
    end
    local can, why, wait = BridgeInventory.canGesture(b, act)
    if not can and not wait then
        log("loot gesture skipped: " .. tostring(why))
        return false
    end
    if BridgeInventory.frozen == nil then BridgeInventory.frozen = modelVisuals(b) end
    BridgeInventory.gestureBody = b
    local face, what = nil, "?"
    pcall(function() what = tostring(act.item:getType()) end)

    if isLootAnim(anim) then face = lootSpot(act, b) end
    table.insert(BridgeInventory.gestures, { anim = anim, dur = LOOT_MAX, action = act, after = wornVisuals(b),
                                             what = "transfer " .. what, face = face })
    log(string.format("gesture queued: %s for transfer %s (%d in queue)", anim, what, #BridgeInventory.gestures))
    if #BridgeInventory.gestures == 1 then
        if can then
            startGesture(b)
            if face ~= nil then pcall(function() b:faceLocationF(face[1], face[2]) end) end
        else
            waitGesture(b, why)
        end
    end
    return true
end



function BridgeInventory.gestureGuard(body)
    if #BridgeInventory.gestures == 0 and BridgeInventory.frozen == nil then return end
    if body ~= BridgeInventory.gestureBody then
        BridgeInventory.gestureFlush(body, "new body")
        BridgeInventory.gestureReset()
        return
    end
    if (BridgeInventory.gestureSeen or -1) < Bridge.zombieTicks - 1 then


        if BridgeInventory.gestureAt == nil and #BridgeInventory.gestures > 0 and Bridge.hiddenSince == nil
            and Bridge.time - (BridgeInventory.gestureWaitSince or Bridge.time) < GESTURE_WAIT_MAX then
            return
        end
        BridgeInventory.gestureFlush(body, "taken over")
    end
end


local function waitTick(body, g)


    if g.action ~= nil and not isLootAnim(g.anim) and not BridgeInventory.actionQueued(g.action) then
        g.action = nil
        g.dur = GESTURE_TIME[g.anim] or GESTURE_TIME_DEFAULT
        log("transfer ended before she stopped, gesture stays timed: " .. tostring(g.what))
    end

    if g.action ~= nil and not BridgeInventory.actionQueued(g.action) then
        table.remove(BridgeInventory.gestures, 1)
        log("gesture dropped, transfer ended before she stopped: " .. tostring(g.what))
        if #BridgeInventory.gestures == 0 then
            BridgeInventory.gestureFlush(body, nil)
            return false
        end

        local changed = #g.after ~= #(BridgeInventory.frozen or {})
        BridgeInventory.frozen = g.after
        if changed then BridgeInventory.rebuild(body) end
        g = BridgeInventory.gestures[1]
    end
    local why = startBlocker(body)

    if why == "moving" then
        BridgeInventory.gestureMovingSince = BridgeInventory.gestureMovingSince or Bridge.time
    else
        BridgeInventory.gestureMovingSince = nil
    end
    if why == "moving" and BridgeWeapon ~= nil and BridgeWeapon.stuckWalking ~= nil
        and BridgeWeapon.stuckWalking(body, BridgeInventory.gestureMovingSince) then
        why = startBlocker(body, true)
        if why == nil then log("walking flags, but standing still: gesture anyway") end
    end
    if why == nil and not playerNear(body, nearFor(g.action)) then why = "player far" end
    if why ~= nil then
        if GESTURE_WAIT_CUT[why] then
            BridgeInventory.gestureFlush(body, "wait: " .. why)
            return false
        end
        if Bridge.time - (BridgeInventory.gestureWaitSince or Bridge.time) >= GESTURE_WAIT_MAX then
            BridgeInventory.gestureFlush(body, "waited too long: " .. why)
            return false
        end
        if why ~= BridgeInventory.gestureWaitWhy then
            BridgeInventory.gestureWaitWhy = why
            log("gesture waits: " .. why .. " for " .. tostring(g.what))
        end
        BridgeInventory.gestureFreeSince = nil
        return false
    end


    BridgeInventory.gestureFreeSince = BridgeInventory.gestureFreeSince or Bridge.time
    if Bridge.time - BridgeInventory.gestureFreeSince < GESTURE_SETTLE then return false end
    log(string.format("gesture starts after %.1f s wait: %s for %s", (Bridge.time - (BridgeInventory.gestureWaitSince or Bridge.time)) / 60,
        g.anim, tostring(g.what)))
    BridgeInventory.gestureWaitSince = nil
    BridgeInventory.gestureWaitWhy = nil
    BridgeInventory.gestureMovingSince = nil
    BridgeInventory.gestureFreeSince = nil
    startGesture(body)
    if g.face ~= nil then pcall(function() body:faceLocationF(g.face[1], g.face[2]) end) end
    return true
end


function BridgeInventory.gestureTick(body)
    local g = BridgeInventory.gestures[1]
    if g == nil then return false end
    if body ~= BridgeInventory.gestureBody then
        BridgeInventory.gestureFlush(body, "new body")
        return false
    end
    if BridgeInventory.gestureAt ~= nil then
        if not playerNear(body, GESTURE_LEAVE) then
            BridgeInventory.gestureFlush(body, "player left")
            return false
        end
    else


        local reach = false
        pcall(function()
            local red = BridgeData.owner()
            if red == nil or red:getVehicle() ~= nil then return end
            local dx, dy = body:getX() - red:getX(), body:getY() - red:getY()
            reach = dx * dx + dy * dy <= GESTURE_WAIT_FAR * GESTURE_WAIT_FAR
        end)
        if not reach then
            BridgeInventory.gestureFlush(body, "player left")
            return false
        end
    end
    BridgeInventory.gestureSeen = Bridge.zombieTicks

    if BridgeInventory.gestureAt == nil then
        if not waitTick(body, g) then return false end
        g = BridgeInventory.gestures[1]
    end
    pcall(function() if BridgeMove ~= nil and BridgeMove.onPath() then BridgeMove.stopPath(body) end end)
    if g.face ~= nil and Bridge.zombieTicks % 10 == 0 then
        pcall(function() body:faceLocationF(g.face[1], g.face[2]) end)
    end
    pcall(function() if tostring(body:getBumpType()) ~= g.anim then body:setBumpType(g.anim) end end)
    local age = Bridge.time - (BridgeInventory.gestureAt or Bridge.time)

    if BridgeInventory.gestureLog == nil and age >= (g.action ~= nil and LOOT_MIN or g.dur) / 2 then
        BridgeInventory.gestureLog = {}
        pcall(function()
            BridgeInventory.gestureLog.asn = tostring(body:getActionStateName())
            BridgeInventory.gestureLog.bump = tostring(body:getBumpType())
        end)
    end
    local done
    if g.action ~= nil then
        local queued = BridgeInventory.actionQueued(g.action)
        if queued then g.goneAt = nil elseif g.goneAt == nil then g.goneAt = Bridge.time end


        local nextSoon = false
        if not queued and isLootAnim(g.anim) and #BridgeInventory.gestures == 1 and BridgeQueue ~= nil then
            local n = BridgeQueue.jobs[1]
            nextSoon = n ~= nil and not (type(n.action) == "table" and n.action.started == true)
                and Bridge.time - g.goneAt < LOOT_NEXT
        end
        done = age >= LOOT_MAX or (age >= LOOT_MIN and not queued and not nextSoon)
    else
        done = age >= g.dur

        if g.item ~= nil and not done then
            pcall(function()
                if g.job ~= nil then g.item:setJobType(g.job) end
                g.item:setJobDelta(math.max(0.01, math.min(1, age / g.dur)))
            end)
        end
    end
    if not done then return true end
    if g.item ~= nil and g.action == nil then pcall(function() g.item:setJobDelta(0) end) end
    table.remove(BridgeInventory.gestures, 1)
    if BridgeInventory.gestureLog then
        log(string.format("gesture done: %s for %s, state %s bump %s", g.anim, tostring(g.what), tostring(BridgeInventory.gestureLog.asn),
            tostring(BridgeInventory.gestureLog.bump)))
    end
    BridgeInventory.gestureLog = nil
    if #BridgeInventory.gestures > 0 then

        BridgeInventory.frozen = g.after

        local why = startBlocker(body)
        if why == nil and not playerNear(body, nearFor(BridgeInventory.gestures[1].action)) then why = "player far" end
        if why ~= nil and not GESTURE_WAIT_CUT[why] then
            BridgeInventory.rebuild(body)
            pcall(function() if isGestureAnim(tostring(body:getBumpType())) then body:setBumpType("") end end)
            waitGesture(body, why)
            return false
        end
        startGesture(body)
        BridgeInventory.rebuild(body)
        return true
    end
    BridgeInventory.frozen = nil
    BridgeInventory.gestureAt = nil


    pcall(function() BridgeInventory.dropGone(body) end)
    BridgeInventory.redress(body, true)
    pcall(function() body:setBumpType("") end)
    return false
end



BridgeInventory.lastLog = ""
BridgeInventory.added = 0


local function logOnce(text)
    if text ~= BridgeInventory.lastLog then
        BridgeInventory.lastLog = text
        log(text)
    end
end
local function warnOnce(text)
    if text ~= BridgeInventory.lastWarn then
        BridgeInventory.lastWarn = text
        warn(text)
    end
end


function BridgeInventory.wornBags(b)
    local bags = {}
    pcall(function()
        local items = b:getInventory():getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item ~= nil and item:IsInventoryContainer() and b:isEquippedClothing(item) then
                bags[#bags + 1] = item
            end
        end
    end)
    return bags
end




function BridgeInventory.addButton(page)
    if page == nil or page.onCharacter then return end

    if page.player ~= nil and page.player ~= 0 then return end
    local b = body()
    if b == nil then BridgeInventory.shown = false logOnce("no body") return end
    local red = getSpecificPlayer(page.player or 0)
    if red == nil then logOnce("no player"); return end
    local dx, dy = b:getX() - red:getX(), b:getY() - red:getY()
    local d = math.sqrt(dx * dx + dy * dy)



    local open = false
    pcall(function()
        local inv = b:getInventory()
        if page.inventory == inv then open = true end
        for _, bag in ipairs(BridgeInventory.wornBags(b)) do
            if page.inventory == bag:getInventory() then open = true end
        end
    end)
    local limit = BridgeInventory.reach
    if BridgeInventory.shown then limit = open and BridgeInventory.keepOpen or BridgeInventory.keep end
    if d > limit or math.abs(b:getZ() - red:getZ()) >= 1 then
        BridgeInventory.shown = false


        if Bridge ~= nil and Bridge.verbose then logOnce(string.format("too far: %.1f", d)) else logOnce("too far") end
        return
    end
    BridgeInventory.shown = true
    local function has(container)
        for _, btn in ipairs(page.backpacks or {}) do
            if btn.inventory == container then return true end
        end
        return false
    end
    local ok, err = pcall(function()
        local inv = b:getInventory()
        if not has(inv) then
            inv:setExplored(true)
            local icon = getTexture("media/ui/Icon_InventoryBasic.png")
            local button = page:addContainerButton(inv, icon, companionName(), companionName())
            button.capacity = BridgeInventory.capacity
        end
        for _, bag in ipairs(BridgeInventory.wornBags(b)) do
            local bagInv = bag:getInventory()
            if not has(bagInv) then
                bagInv:setExplored(true)
                local button = page:addContainerButton(bagInv, bag:getTex(), bag:getName(), bag:getName())
                pcall(function()
                    local tint = bag:getVisual():getTint(bag:getClothingItem())
                    button:setTextureRGBA(tint:getRedFloat(), tint:getGreenFloat(), tint:getBlueFloat(), 1.0)
                end)
            end
        end
    end)
    if ok then
        BridgeInventory.added = BridgeInventory.added + 1
        logOnce("button added")
    else
        warnOnce("addContainerButton failed: " .. tostring(err))
    end
end

function BridgeInventory.onRefresh(page, stage)
    if stage ~= "buttonsAdded" then return end
    BridgeInventory.addButton(page)
end







function BridgeInventory.withoutHers(list)
    if list == nil then return list end
    local out = ArrayList.new()
    local dropped = 0
    for i = 0, list:size() - 1 do
        local c = list:get(i)
        if BridgeInventory.isHers(c) then dropped = dropped + 1 else out:add(c) end
    end
    if dropped > 0 then BridgeInventory.craftDropped = (BridgeInventory.craftDropped or 0) + dropped end
    return out
end

if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.getContainers ~= nil and not ISInventoryPaneContextMenu.bridgeWrapped then
    local originalGetContainers = ISInventoryPaneContextMenu.getContainers
    ISInventoryPaneContextMenu.getContainers = function(character, ...)
        local list = originalGetContainers(character, ...)
        local ok, res = pcall(BridgeInventory.withoutHers, list)
        if ok and res ~= nil then return res end
        return list
    end
    ISInventoryPaneContextMenu.bridgeWrapped = true
    log("getContainers wrapped: her containers stay out of crafting")
end


if ISInventoryPage ~= nil and ISInventoryPage.refreshBackpacks ~= nil and not ISInventoryPage.bridgeWrapped then
    local original = ISInventoryPage.refreshBackpacks
    ISInventoryPage.refreshBackpacks = function(self, ...)
        original(self, ...)
        pcall(function() BridgeInventory.addButton(self) end)
    end
    ISInventoryPage.bridgeWrapped = true
    log("refreshBackpacks wrapped")
end


function BridgeInventory.isHers(container)
    local b = body()
    if b == nil or container == nil then return false end
    if container == b:getInventory() then return true end
    for _, bag in ipairs(BridgeInventory.wornBags(b)) do
        if container == bag:getInventory() then return true end
    end
    return false
end








local function proximityActive()
    local on = false
    pcall(function()
        local mods = getActivatedMods()
        for i = 0, mods:size() - 1 do

            if string.sub(tostring(mods:get(i)), -18) == "ProximityInventory" then on = true end
        end
    end)
    return on
end

function BridgeInventory.wrapProximity()
    if not proximityActive() then return end
    local ok, PI = pcall(require, "ProximityInventory/ProximityInventory")
    if not ok or type(PI) ~= "table" or type(PI.CanBeAdded) ~= "function" then
        log("Proximity Inventory: module not found")
        return
    end
    if PI.bridgeWrapped then return end
    local canBeAdded = PI.CanBeAdded
    PI.CanBeAdded = function(container, playerObj)
        if BridgeInventory.isHers(container) then return false end
        return canBeAdded(container, playerObj)
    end
    PI.bridgeWrapped = true
    if ISInventoryPage ~= nil and ISInventoryPage.update ~= nil and not ISInventoryPage.bridgeProxWrapped then
        local update = ISInventoryPage.update
        ISInventoryPage.update = function(self, ...)
            update(self, ...)
            if self.onCharacter or self.inventory == nil then return end
            pcall(function()
                if self.inventory:getType() ~= "proxInv" then return end
                local b = body()
                if b == nil then return end
                b:setHighlighted(self.player, false)
                b:setOutlineHighlight(self.player, false)
            end)
        end
        ISInventoryPage.bridgeProxWrapped = true
    end
    log("Proximity Inventory wrapped: her containers stay out of it")
end

Events.OnGameStart.Add(function() pcall(BridgeInventory.wrapProximity) end)













function BridgeInventory.wornBagWeight(b)
    local w = 0
    for _, bag in ipairs(BridgeInventory.wornBags(b)) do
        pcall(function()
            local x = bag:getEquippedWeight()
            if type(x) == "number" then w = w + x end
        end)
    end
    return w
end


function BridgeInventory.mainLoad(b)
    local total = 0
    pcall(function() total = b:getInventory():getCapacityWeight() end)
    if type(total) ~= "number" then total = 0 end
    return math.max(0, total)
end





BridgeInventory.toWear = BridgeInventory.toWear or {}
local WEAR_WAIT = 3600




local variantLoc = {}
local function wearLocation(item, variant)
    local function of(src)
        local loc = nil
        pcall(function()
            if src:IsClothing() then loc = src:getBodyLocation() end
            if loc == nil or loc == "" then loc = src:canBeEquipped() end
        end)
        if loc == "" then loc = nil end
        return loc
    end
    if variant == nil then return of(item) end
    local cached = variantLoc[variant]
    if cached == nil then
        local sample = nil
        pcall(function() sample = instanceItem(variant) end)
        cached = { loc = sample ~= nil and of(sample) or nil }
        variantLoc[variant] = cached
    end
    return cached.loc
end







function BridgeInventory.loadAfterWear(b, item, variant)
    local load = BridgeInventory.mainLoad(b)
    local inv = b:getInventory()
    pcall(function()
        if item:getContainer() == inv and not b:isEquipped(item) then load = load - item:getUnequippedWeight() end
    end)
    pcall(function() if not b:isEquippedClothing(item) then load = load + item:getEquippedWeight() end end)
    local loc = wearLocation(item, variant)
    if loc ~= nil then
        pcall(function()
            local worn = b:getWornItems()
            local group = nil
            pcall(function() group = worn:getBodyLocationGroup() end)
            for i = 0, worn:size() - 1 do
                local w = worn:get(i)
                local old, wloc = w:getItem(), w:getLocation()
                local out = wloc == loc
                if not out and group ~= nil then pcall(function() out = group:isExclusive(loc, wloc) == true end) end
                if out and old ~= nil and old ~= item then load = load - old:getEquippedWeight() end
            end
        end)
    end
    return load
end


function BridgeInventory.wearFits(b, item, variant, chr)
    local cap = BridgeInventory.capacity
    pcall(function() cap = b:getInventory():getEffectiveCapacity(chr or getSpecificPlayer(0)) end)
    if type(cap) ~= "number" then cap = BridgeInventory.capacity end
    local after = BridgeInventory.loadAfterWear(b, item, variant)
    pcall(function() after = ItemContainer.floatingPointCorrection(after) end)
    if after <= cap then return true end


    return after <= BridgeInventory.mainLoad(b) + 0.001
end





local function wearQueued(id)
    local found = false
    for _, a in ipairs(BridgeInventory.queuedActions()) do
        pcall(function()
            if type(a) ~= "table" then return end
            local args = a.onCompleteArgs
            if a.onCompleteFunc == BridgeInventory.finishWear and type(args) == "table" and args[1] == id then found = true end
            local r = a.bridgeRelay
            if type(r) == "table" and r.id == id and r.after ~= nil then found = true end
        end)
        if found then return true end
    end
    return false
end



function BridgeInventory.pendingWear(item)
    local id = nil
    pcall(function() id = item:getID() end)
    local w = id ~= nil and BridgeInventory.toWear[id] or nil
    if w == nil then return nil end
    if wearQueued(id) then return w end

    if (Bridge.time - (w.t or 0)) > WEAR_WAIT then BridgeInventory.toWear[id] = nil end
    return nil
end





function BridgeInventory.roomVerdict(container, a, b2)
    local b = body()
    if b == nil or container == nil or container ~= b:getInventory() then return nil end
    local chr, item, w = nil, nil, nil
    if instanceof(a, "InventoryItem") then
        item = a
    else
        chr = a
        if instanceof(b2, "InventoryItem") then item = b2
        elseif type(b2) == "number" then w = b2 end
    end
    if item == nil and w == nil then return nil end
    if item ~= nil then
        if not container:isItemAllowed(item) then return false end
        local heavy = false
        pcall(function() heavy = chr ~= nil and chr:getVehicle() ~= nil and item:hasTag(ItemTag.HEAVY_ITEM) end)
        if heavy then return false end
        local pending = BridgeInventory.pendingWear(item)
        if pending ~= nil then return BridgeInventory.wearFits(b, item, pending.v, chr) end
        w = item:getUnequippedWeight()
    end
    local cap = BridgeInventory.capacity
    pcall(function() cap = container:getEffectiveCapacity(chr or getSpecificPlayer(0)) end)
    if type(cap) ~= "number" then cap = BridgeInventory.capacity end
    local load = BridgeInventory.mainLoad(b)
    pcall(function() load = ItemContainer.floatingPointCorrection(load) end)
    local fits = load + w <= cap
    if not fits and item ~= nil then

        pcall(function()
            logOnce(string.format("no room for %s: her main %.2f + %.2f > %d (worn bags %.2f)", item:getFullType(), load, w, cap,
                BridgeInventory.wornBagWeight(b)))
        end)
    end
    return fits
end









BridgeInventory.marking = nil


function BridgeInventory.paneMarks(pane)
    if pane == nil or pane.inventory == nil then return nil end
    if pane.parent ~= nil and pane.parent.onCharacter then return nil end
    if pane.player ~= nil and pane.player ~= 0 then return nil end
    local b = body()
    if b == nil or pane.inventory ~= b:getInventory() then return nil end
    local eq, hot, keys = {}, {}, {}
    local items = pane.inventory:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it ~= nil then
            if b:isEquipped(it) then
                eq[it] = true
                keys[#keys + 1] = "e" .. tostring(it:getID())
            elseif BridgeWeapon.isAssigned(b, it) then
                hot[it] = true
                keys[#keys + 1] = "h" .. tostring(it:getID())
            end
        end
    end
    return { eq = eq, hot = hot, key = table.concat(keys, ",") }
end







function BridgeInventory.regroupPane(pane, marks, selected)
    local list = pane.itemslist
    if type(list) ~= "table" then return false end
    local out, changed = {}, false


    local function fill(g, items, header)
        g.items = {}
        if header then g.items[1] = items[1] end
        g.weight = 0
        for _, it in ipairs(items) do
            g.items[#g.items + 1] = it
            pcall(function() g.weight = g.weight + it:getUnequippedWeight() end)
        end
        g.count = #items + 1
        return g
    end
    for _, v in ipairs(list) do
        local eq, hot, rest = {}, {}, {}
        local header = false
        if type(v) == "table" and type(v.items) == "table" then
            header = v.items[1] ~= nil and v.items[1] == v.items[2]
            for i = header and 2 or 1, #v.items do
                local it = v.items[i]
                if marks.eq[it] then eq[#eq + 1] = it
                elseif marks.hot[it] then hot[#hot + 1] = it
                else rest[#rest + 1] = it end
            end
        end
        if #eq == 0 and #hot == 0 then
            out[#out + 1] = v
        else
            changed = true
            local function add(items, prefix, equipped, inHotbar)
                local name = prefix .. tostring(v.name)
                local g = fill({ invPanel = pane, name = name, cat = v.cat, equipped = equipped, inHotbar = inHotbar }, items, header)
                if type(pane.collapsed) == "table" and pane.collapsed[name] == nil then pane.collapsed[name] = true end
                if type(pane.itemindex) == "table" then pane.itemindex[name] = g end
                out[#out + 1] = g
            end
            if #eq > 0 then add(eq, "equipped:", true, false) end
            if #hot > 0 then add(hot, "hotbar:", false, true) end
            if #rest > 0 then
                fill(v, rest, header)
                out[#out + 1] = v
            elseif type(pane.itemindex) == "table" then
                pane.itemindex[v.name] = nil
            end
        end
    end
    if not changed then return false end
    if selected == nil then pcall(function() selected = pane:saveSelection({}) end) end
    if selected == nil then selected = {} end
    if pane.itemSortFunc ~= nil then pcall(function() table.sort(out, pane.itemSortFunc) end) end
    pane.itemslist = out
    if type(pane.selected) == "table" then
        for k in pairs(pane.selected) do pane.selected[k] = nil end
        pcall(function() pane:restoreSelection(selected) end)
    end
    return true
end


local function javaIndex(cls)
    local idx = nil
    pcall(function()
        local mts = __classmetatables
        if mts ~= nil and cls ~= nil then
            local mt = mts[cls]
            if mt ~= nil then idx = mt.__index end
        end
    end)
    if type(idx) ~= "table" then return nil end
    return idx
end



function BridgeInventory.wrapGear()
    local done = {}
    local room = javaIndex(ItemContainer ~= nil and ItemContainer.class or nil)
    if room ~= nil and room.hasRoomFor ~= nil then
        if not rawget(room, "bridgeRoomWrapped") then
            local hasRoomFor = room.hasRoomFor
            room.hasRoomFor = function(self, ...)
                local verdict = nil
                local a, b2 = ...
                pcall(function() verdict = BridgeInventory.roomVerdict(self, a, b2) end)
                if verdict ~= nil then return verdict end
                return hasRoomFor(self, ...)
            end
            room.bridgeRoomWrapped = true
        end
        done[#done + 1] = "room"
    end
    local who = javaIndex(IsoPlayer ~= nil and IsoPlayer.class or nil)
    if who ~= nil and who.isEquipped ~= nil then
        if not rawget(who, "bridgeEquippedWrapped") then
            local isEquipped = who.isEquipped
            who.isEquipped = function(self, item, ...)
                local m = BridgeInventory.marking
                if m ~= nil and item ~= nil and m.eq[item] then return true end
                return isEquipped(self, item, ...)
            end
            who.bridgeEquippedWrapped = true
        end
        done[#done + 1] = "dot"
    end
    if ISHotbar ~= nil and ISHotbar.isInHotbar ~= nil and not ISHotbar.bridgeGearWrapped then
        local isInHotbar = ISHotbar.isInHotbar
        ISHotbar.isInHotbar = function(self, item, ...)
            local m = BridgeInventory.marking
            if m ~= nil and item ~= nil and m.hot[item] then return true end
            return isInHotbar(self, item, ...)
        end
        ISHotbar.bridgeGearWrapped = true
    end
    if ISInventoryPane ~= nil and ISInventoryPane.refreshContainer ~= nil and not ISInventoryPane.bridgeGearWrapped then
        local refreshContainer = ISInventoryPane.refreshContainer
        ISInventoryPane.refreshContainer = function(self, ...)
            local selected = nil
            pcall(function()
                if BridgeInventory.paneMarks(self) ~= nil and type(self.selected) == "table" then
                    selected = self:saveSelection({})
                end
            end)
            local r = refreshContainer(self, ...)
            self.bridgeMarkKey = nil
            pcall(function()
                local marks = BridgeInventory.paneMarks(self)
                if marks == nil then return end

                self.bridgeMarkKey = marks.key
                BridgeInventory.regroupPane(self, marks, selected)
            end)
            return r
        end
        local renderdetails = ISInventoryPane.renderdetails
        ISInventoryPane.renderdetails = function(self, ...)
            local marks = nil
            pcall(function() marks = BridgeInventory.paneMarks(self) end)
            if marks == nil then return renderdetails(self, ...) end

            if self.bridgeMarkKey ~= marks.key then pcall(function() self:refreshContainer() end) end
            BridgeInventory.marking = marks
            local ok, err = pcall(renderdetails, self, ...)
            BridgeInventory.marking = nil
            if not ok then warnOnce("her pane render failed: " .. tostring(err)) end
        end
        ISInventoryPane.bridgeGearWrapped = true
        done[#done + 1] = "pane"
    end
    if ISInventoryPage ~= nil and ISInventoryPage.loadWeight ~= nil and not ISInventoryPage.bridgeLoadWrapped then
        local loadWeight = ISInventoryPage.loadWeight
        ISInventoryPage.loadWeight = function(inv, ...)
            local b = body()
            if b ~= nil and inv ~= nil and inv == b:getInventory() then
                local ok, w = pcall(BridgeInventory.mainLoad, b)
                if ok and type(w) == "number" then return w end
            end
            return loadWeight(inv, ...)
        end
        ISInventoryPage.bridgeLoadWrapped = true
        done[#done + 1] = "load"
    end
    log("gear wrapped: " .. table.concat(done, ","))
end

Events.OnGameStart.Add(function() pcall(BridgeInventory.wrapGear) end)






function BridgeInventory.putOn(b, item)
    local loc = nil
    pcall(function() if item:IsClothing() then loc = item:getBodyLocation() end end)
    if loc == nil then pcall(function() loc = item:canBeEquipped() end) end
    if loc == nil then return false end
    local old = nil
    pcall(function() old = b:getWornItems():getItem(loc) end)
    pcall(function() b:removeFromHands(item) end)
    b:setWornItem(loc, item)
    if old ~= nil and old ~= item then BridgeInventory.dropIfNoRoom(b, old) end
    return true
end






function BridgeInventory.dropIfNoRoom(b, item)
    if Bridge.mp or item == nil then return false end
    local inv = b:getInventory()
    local here = false
    pcall(function() here = inv:contains(item) and not b:isEquipped(item) end)
    if not here then return false end



    local cap = BridgeInventory.capacity
    pcall(function() cap = inv:getEffectiveCapacity(b) end)
    if type(cap) ~= "number" then cap = BridgeInventory.capacity end
    local load = BridgeInventory.mainLoad(b)
    pcall(function() load = ItemContainer.floatingPointCorrection(load) end)
    if load <= cap then return false end
    local sq = nil
    pcall(function() sq = b:getCurrentSquare() end)
    if sq == nil then return false end
    local ok, err = pcall(function()
        local x, y = ZombRandFloat(0.1, 0.9), ZombRandFloat(0.1, 0.9)
        local z = sq:getApparentZ(x, y) - sq:getZ()
        inv:Remove(item)
        sq:AddWorldInventoryItem(item, x, y, z)
    end)
    if not ok then
        warn("drop failed: " .. tostring(err))
        pcall(function() if not inv:contains(item) then inv:AddItem(item) end end)
        return false
    end
    pcall(function() note("dropped " .. item:getType() .. ": no room") end)
    pcall(function() log("no room for " .. item:getType() .. " after the change: dropped at her feet, as for the player") end)
    return true
end



function BridgeInventory.wear(b, item, keepHoods)

    local here = false
    pcall(function() here = item:getContainer() == b:getInventory() end)
    if not here then
        log("wear skipped: item is not in her inventory")
        return
    end
    pcall(function() note("wear " .. item:getType()) end)

    local pre = BridgeInventory.frozen == nil and modelVisuals(b) or nil
    if not keepHoods then pcall(function() BridgeInventory.hoodsDown(b, item) end) end
    local ok, err = pcall(function() BridgeInventory.putOn(b, item) end)
    if not ok then warn("wear failed: " .. tostring(err)) end
    if ok then BridgeInventory.afterChange(b, item, pre, "wear") else redress(b) end
    refreshPanels()
end







local function dotted(module, t)
    t = tostring(t)
    if string.find(t, ".", 1, true) ~= nil then return t end
    local out = t
    pcall(function() out = moduleDotType(module, t) end)
    if out == t and module ~= nil then out = tostring(module) .. "." .. t end
    return out
end

function BridgeInventory.variants(item)
    local out = { list = {} }
    pcall(function()
        local opts = item:getClothingItemExtraOption()
        local types = item:getClothingItemExtra()
        if opts == nil or types == nil then return end
        for i = 0, opts:size() - 1 do
            local t = nil
            pcall(function() t = types:get(i) end)
            if t ~= nil then
                out.list[#out.list + 1] = { text = getText("ContextMenu_" .. tostring(opts:get(i))), t = dotted(item:getModule(), t),
                                            option = tostring(opts:get(i)) }
            end
        end


        if (item:IsClothing() or item:IsInventoryContainer()) and item.getClothingExtraSubmenu ~= nil then
            local sub = item:getClothingExtraSubmenu()
            if sub ~= nil and sub ~= "" then out.submenu = getText("ContextMenu_" .. tostring(sub)) end
        end
    end)
    return out
end




function BridgeInventory.hoodsDown(b, item)
    local hat = false
    pcall(function()
        local loc = item:getBodyLocation()
        hat = loc ~= nil and (loc == ItemBodyLocation.HAT or loc == ItemBodyLocation.FULL_HAT)
    end)
    if not hat then return end
    local hoods = {}
    pcall(function()
        local worn = b:getWornItems()
        for i = 0, worn:size() - 1 do
            local wi = worn:get(i)
            local loc = wi:getLocation()
            if loc == ItemBodyLocation.SWEATER_HAT or loc == ItemBodyLocation.JACKET_HAT then
                for _, v in ipairs(BridgeInventory.variants(wi:getItem()).list) do
                    if v.option == "DownHoodie" then hoods[#hoods + 1] = { item = wi:getItem(), t = v.t } end
                end
            end
        end
    end)
    for _, h in ipairs(hoods) do BridgeInventory.wearVariant(b, h.item, h.t, true) end
end


local function queueHolds(value)
    local found = false
    local function scan(t, depth)
        if found or type(t) ~= "table" or depth > 3 then return end
        for k, v in pairs(t) do
            if v == value then found = true return end


            if type(v) == "table" and getmetatable(v) == nil and k ~= "character" and k ~= "action" then scan(v, depth + 1) end
        end
    end
    for _, a in ipairs(BridgeInventory.queuedActions()) do pcall(scan, a, 1) end
    return found
end
BridgeInventory.queueHolds = queueHolds











function BridgeInventory.wearVariant(b, item, extraType, quiet, arriving, keepHoods)
    local inv = b:getInventory()
    local here = false
    pcall(function() here = inv:contains(item) and not item:isBroken() end)
    if not here then
        log("variant skipped: item is not hers any more")
        return false
    end
    if BridgeInventory.taking[item] ~= nil or (not arriving and queueHolds(item)) then
        log("variant skipped: item is being moved")
        return false
    end
    pcall(function() note("variant " .. item:getType() .. " -> " .. tostring(extraType)) end)
    local pre = nil
    if not quiet and BridgeInventory.frozen == nil then pre = modelVisuals(b) end
    local newItem = nil
    pcall(function() newItem = instanceItem(extraType) end)
    if newItem == nil or wearLocation(newItem, nil) == nil then
        log("variant failed: no wearable item " .. tostring(extraType))
        return false
    end
    local wasWorn = false
    pcall(function() wasWorn = b:isEquippedClothing(item) end)

    local function giveBack()
        pcall(function()
            if newItem:IsInventoryContainer() and item:IsInventoryContainer()
                and not newItem:getItemContainer():getItems():isEmpty() then
                item:getItemContainer():takeItemsFrom(newItem:getItemContainer())
            end
        end)
    end
    local ok, err = pcall(function()
        if ISClothingExtraAction ~= nil and ISClothingExtraAction.createItemNew ~= nil then
            ISClothingExtraAction:createItemNew(item, newItem)
        else
            copyClothingItem(item, newItem)
        end
    end)
    if not ok then
        warn("variant failed: copy: " .. tostring(err))
        giveBack()
        return false
    end
    local put = false
    ok, err = pcall(function()


        if not keepHoods then pcall(function() BridgeInventory.hoodsDown(b, item) end) end
        pcall(function() b:removeFromHands(item) end)
        if b:isEquippedClothing(item) then b:removeWornItem(item) end
        inv:Remove(item)
        inv:AddItem(newItem)
        put = BridgeInventory.putOn(b, newItem)
    end)
    if not ok or not put then
        log("variant failed: " .. tostring(err or "not worn") .. ", rolled back")
        pcall(function()
            if b:isEquippedClothing(newItem) then b:removeWornItem(newItem) end
            if inv:contains(newItem) then inv:Remove(newItem) end
            if not inv:contains(item) then inv:AddItem(item) end
        end)
        giveBack()
        if wasWorn then pcall(function() BridgeInventory.putOn(b, item) end) end
    else

        pcall(function()
            if item:IsInventoryContainer() and newItem:IsInventoryContainer() then
                BridgeInventory.swapInQueue(getSpecificPlayer(0), item:getItemContainer(), newItem:getItemContainer(), nil)
            end
        end)
    end
    if not quiet then
        if ok and put then BridgeInventory.afterChange(b, newItem, pre, "wear") else redress(b) end
        refreshPanels()
        pcall(function() Bridge.saveOutfit() end)
    end
    return ok and put, newItem
end






function BridgeInventory.canWearOnHer(player, item)
    if player == nil or item == nil then return false end
    local ok = false
    pcall(function()
        local c = item:getContainer()
        if c == nil then return end
        local wearable = (BridgeInventory.canWear(item) or #BridgeInventory.variants(item).list > 0)
            and not BridgeInventory.handsGear(item)
        if not wearable or item:isBroken() then return end




        if item:isFavorite() then return end
        ok = true
    end)
    return ok
end




function BridgeInventory.gifted(b, item)
    if item == nil or BridgeSocial == nil or BridgeSocial.dressed == nil then return end
    local worn = false
    pcall(function() worn = b:isEquippedClothing(item) end)
    if worn then pcall(BridgeSocial.dressed, item) end
end

function BridgeInventory.wearOnHer(player, item, variant)
    local b = body()
    if b == nil or item == nil then return end
    local inv = b:getInventory()
    local id = item:getID()
    if item:getContainer() == inv then
        BridgeInventory.finishWear(id, variant)
        return
    end
    pcall(function() note("wear on her " .. item:getType()) end)
    BridgeInventory.toWear[id] = { t = Bridge.time, v = variant }
    local ok, err = pcall(function()
        local act = ISInventoryTransferAction:new(player, item, item:getContainer(), inv)
        if act.bridgeRelay ~= nil then

            act.bridgeRelay.after = { f = BridgeInventory.finishWear, a = id, b = variant }
        else
            act:setOnComplete(BridgeInventory.finishWear, id, variant)
        end
        ISTimedActionQueue.add(act)
    end)
    if not ok then
        BridgeInventory.toWear[id] = nil
        warn("wear on her failed: " .. tostring(err))
    end
end



function BridgeInventory.finishWear(id, variant)
    BridgeInventory.toWear[id] = nil
    local b = body()
    if b == nil then return end
    local item = nil
    pcall(function()
        local items = b:getInventory():getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it ~= nil and it:getID() == id then item = it break end
        end
    end)
    if item == nil then
        log("wear on her: item " .. tostring(id) .. " did not arrive")
        return
    end

    if variant ~= nil then
        local _, newItem = BridgeInventory.wearVariant(b, item, variant, false, true, true)
        BridgeInventory.gifted(b, newItem)
    else
        BridgeInventory.wear(b, item, true)
        BridgeInventory.gifted(b, item)
    end
end



local function viaPlayerFits(player, item)
    if not Bridge.mp then return true end
    local via = false
    pcall(function()
        local c = item:getContainer()
        via = c ~= nil and c:getOutermostContainer() ~= player:getInventory() and not BridgeInventory.inBody(c)
    end)
    if not via then return true end
    local room = true
    pcall(function() room = player:getInventory():hasRoomFor(player, item) ~= false end)
    return room
end








function BridgeInventory.assignOnHer(player, item)
    local b = body()
    if b == nil or item == nil then return end
    local inv = b:getInventory()
    local id = item:getID()
    if item:getContainer() == inv then
        BridgeInventory.hands(b, item)
        return
    end
    pcall(function() note("assign on her " .. item:getType()) end)
    local ok, err = pcall(function()
        local act = ISInventoryTransferAction:new(player, item, item:getContainer(), inv)
        if act.bridgeRelay ~= nil then
            act.bridgeRelay.after = { f = BridgeInventory.finishAssign, a = id }
        else
            act:setOnComplete(BridgeInventory.finishAssign, id)
        end
        ISTimedActionQueue.add(act)
    end)
    if not ok then warn("assign on her failed: " .. tostring(err)) end
end



function BridgeInventory.finishAssign(id)
    local b = body()
    if b == nil then return end
    local item = nil
    pcall(function()
        local items = b:getInventory():getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it ~= nil and it:getID() == id then item = it break end
        end
    end)
    if item == nil then
        log("assign on her: item " .. tostring(id) .. " did not arrive")
        return
    end
    BridgeInventory.hands(b, item)
end

function BridgeInventory.unwear(b, item)
    pcall(function() note("unwear " .. item:getType()) end)
    local pre = BridgeInventory.frozen == nil and modelVisuals(b) or nil
    local worn = false
    pcall(function() worn = b:isEquippedClothing(item) end)
    local ok, err = pcall(function()
        b:removeWornItem(item)
        if b:getPrimaryHandItem() == item then b:setPrimaryHandItem(nil) end
        if b:getSecondaryHandItem() == item then b:setSecondaryHandItem(nil) end
    end)
    if not ok then warn("unwear failed: " .. tostring(err)) end

    if ok and worn then pcall(BridgeInventory.dropIfNoRoom, b, item) end
    if ok and worn then BridgeInventory.afterChange(b, item, pre, "unwear") else redress(b) end
    refreshPanels()
end


function BridgeInventory.isGun(item)
    local gun = false
    pcall(function() gun = instanceof(item, "HandWeapon") and item:isRanged() end)
    return gun
end





local handsGearOf = {}
function BridgeInventory.handsGear(item)
    if item == nil or ItemTag == nil or ItemTag.REPLACE_PRIMARY == nil then return false end
    local ft = nil
    pcall(function() ft = item:getFullType() end)
    if ft ~= nil and handsGearOf[ft] ~= nil then return handsGearOf[ft] end
    local yes = false
    pcall(function() yes = item:hasTag(ItemTag.REPLACE_PRIMARY) == true end)
    if not yes then
        pcall(function()
            local types = item:getClothingItemExtra()
            if types == nil then return end
            for i = 0, types:size() - 1 do
                local sample = instanceItem(dotted(item:getModule(), types:get(i)))
                if sample ~= nil and sample:hasTag(ItemTag.REPLACE_PRIMARY) then yes = true return end
            end
        end)
    end
    if ft ~= nil then handsGearOf[ft] = yes end
    return yes
end



function BridgeInventory.canWear(item)
    if BridgeInventory.handsGear(item) then return false end
    local ok = false
    pcall(function()
        if item:IsClothing() and item:getBodyLocation() ~= nil and tostring(item:getBodyLocation()) ~= "" then ok = not item:isBroken() end
    end)
    if ok then return true end
    pcall(function()
        ok = (instanceof(item, "InventoryContainer") or item:hasTag(ItemTag.WEARABLE)) and item:canBeEquipped() ~= nil
    end)
    return ok == true
end



function BridgeInventory.hands(b, item)
    if BridgeInventory.isGun(item) then
        pcall(function() Bridge.speak("NoGuns") end)
        return false
    end
    if not BridgeWeapon.isMelee(item) then return false end
    pcall(function() note("assign " .. item:getType()) end)
    local ok, err = pcall(function()
        if b:isEquippedClothing(item) then b:removeWornItem(item) end
        return BridgeWeapon.assign(b, item)
    end)
    if not ok then warn("assign failed: " .. tostring(err)) ok = false end
    if ok == nil then ok = false end
    redress(b)
    refreshPanels()
    return ok
end


function BridgeInventory.drop(b, item)
    pcall(function() note("unassign " .. item:getType()) end)
    local ok, err = pcall(function() BridgeWeapon.unassign(b, item) end)
    if not ok then warn("unassign failed: " .. tostring(err)) end
    redress(b)
    refreshPanels()
end




function BridgeInventory.keepOnHer(b, item)
    local keep = false
    pcall(function()
        keep = b:isEquipped(item) or item:isFavorite() or (BridgeWeapon ~= nil and BridgeWeapon.isAssigned(b, item))
    end)
    return keep == true
end

local function flatten(items)
    local out = {}
    for _, v in ipairs(items) do
        if instanceof(v, "InventoryItem") then
            out[#out + 1] = v
        elseif type(v) == "table" and v.items then
            for i, it in ipairs(v.items) do
                if i > 1 or #v.items == 1 then out[#out + 1] = it end
            end
        end
    end
    return out
end



local function rowItems(items)
    local out = {}
    for _, v in ipairs(items) do
        if instanceof(v, "InventoryItem") then
            out[#out + 1] = v
        elseif type(v) == "table" and v.items and v.items[1] ~= nil then
            out[#out + 1] = v.items[1]
        end
    end
    return out
end



function BridgeInventory.unwearAll(b, items)
    for _, it in ipairs(items) do
        local worn = false
        pcall(function() worn = b:isEquippedClothing(it) end)
        if worn then BridgeInventory.unwear(b, it) end
    end
end



local function actualItems(items)
    if ISInventoryPane ~= nil and ISInventoryPane.getActualItems ~= nil then
        local ok, out = pcall(ISInventoryPane.getActualItems, items)
        if ok and type(out) == "table" then return out end
    end
    return flatten(items)
end

local function isBroken(item)
    local yes = false
    pcall(function() yes = item:isBroken() end)
    return yes
end




local function extraSubmenu(item)
    if item == nil or item.getClothingExtraSubmenu == nil then return nil end
    local s = nil
    pcall(function() s = item:getClothingExtraSubmenu() end)
    if s == "" then s = nil end
    return s
end









function BridgeInventory.wearTests(b, items)
    local t, c = {}, 0
    for _, top in ipairs(rowItems(items)) do
        pcall(function()
            if top:getClothingItemExtraOption() ~= nil then t.extra = top end
            if top:getCategory() == "Clothing" then t.clothing = top end
            if top:hasTag(ItemTag.WEARABLE) then t.other = top end
            if b:isEquipped(top) then t.unequip = top end
            if instanceof(top, "InventoryContainer") and top:canBeEquipped() ~= nil and not b:isEquippedClothing(top)
                and extraSubmenu(top) == nil then t.container = top end
        end)
        c = c + 1
        if c > 1 then t.unequip, t.container = nil, nil end
    end
    t.rows = c
    return t
end

local function isHat(item)
    local hat = false
    pcall(function()
        local loc = item:getBodyLocation()
        hat = loc ~= nil and (loc == ItemBodyLocation.HAT or loc == ItemBodyLocation.FULL_HAT)
    end)
    return hat
end



local function reachable(player, item)
    local ok = false
    pcall(function()
        local c = item:getContainer()
        if c == nil then return end
        if item:isFavorite() and player ~= nil and c:getOutermostContainer() == player:getInventory() then return end
        ok = true
    end)
    return ok
end









function BridgeInventory.wearAllList(b, player, actual)
    local out, done, hat = {}, {}, nil
    local inv = b:getInventory()
    for _, k in ipairs(actual) do
        local a, c = nil, nil
        pcall(function() a = k:getBodyLocation() end)
        pcall(function() c = k:canBeEquipped() end)
        if a == "" then a = nil end
        if c == "" then c = nil end
        if not ((a ~= nil and done[a]) or (c ~= nil and done[c])) then
            if hat == nil and isHat(k) then hat = k end
            local mine = k:getContainer() == inv
            local move = not mine and reachable(player, k)
            local wear = false
            pcall(function() wear = BridgeInventory.canWear(k) and not k:isBroken() and not b:isEquippedClothing(k) end)
            if wear and not mine and not move then wear = false end
            if wear or move then out[#out + 1] = { item = k, wear = wear, move = move } end
            if a ~= nil then done[a] = true end
            if c ~= nil then done[c] = true end
        end
    end
    return { entries = out, hat = hat }
end



function BridgeInventory.wearList(player, plan)
    local b = body()
    if b == nil or type(plan) ~= "table" then return end
    if plan.hat ~= nil then pcall(function() BridgeInventory.hoodsDown(b, plan.hat) end) end
    local inv = b:getInventory()
    for _, e in ipairs(plan.entries or {}) do
        local k = e.item
        if k:getContainer() == inv then
            if e.wear then
                BridgeInventory.wear(b, k, true)
                BridgeInventory.gifted(b, k)
            end
        elseif e.wear then
            BridgeInventory.wearOnHer(player, k, nil)
        elseif e.move then
            pcall(function() ISTimedActionQueue.add(ISInventoryTransferAction:new(player, k, k:getContainer(), inv)) end)
        end
    end
end



local function wornInLocation(b, location)
    local found = nil
    pcall(function()
        local worn = b:getWornItems()
        local group = worn:getBodyLocationGroup()
        for i = 0, worn:size() - 1 do
            local w = worn:get(i)
            if w:getLocation() == location or group:isExclusive(w:getLocation(), location) then
                found = w:getItem()
                return
            end
        end
    end)
    return found
end



local function wearTooltip(b, option, newItem, current)
    if ISInventoryPaneContextMenu == nil or ISInventoryPaneContextMenu.doWearClothingTooltip == nil or newItem == nil then return end
    pcall(ISInventoryPaneContextMenu.doWearClothingTooltip, b, newItem, current, option)
end


local function markFull(option, fits)
    if fits ~= false then return end
    option.notAvailable = true
    pcall(function()
        local tip = ISInventoryPaneContextMenu.addToolTip()
        tip.description = getText("ContextMenu_FullInventory")
        option.toolTip = tip
    end)
end





local function iconOf(option, item, withColor)
    pcall(function() option.iconTexture = item:getTex():splitIcon() end)
    if withColor then
        pcall(function()
            local c = item:getColor()
            option.color = { r = c:getR(), g = c:getG(), b = c:getB() }
        end)
    end
end

local function extraMenu(context, b, item, pick, fits)
    local parent = context:addOption(label("InvWear"))
    iconOf(parent, item, false)
    local sub = context:getNew(context)
    context:addSubMenu(parent, sub)
    local own = extraSubmenu(item)
    local kind = false
    pcall(function() kind = item:IsClothing() or item:IsInventoryContainer() end)
    if kind and own ~= nil then
        local location = nil
        pcall(function()
            if item:IsClothing() then location = item:getBodyLocation() end
            if location == nil then location = item:canBeEquipped() end
        end)
        if wornInLocation(b, location) ~= item then
            local o = sub:addOption(getText("ContextMenu_" .. tostring(own)), nil, function() pick(nil) end)
            wearTooltip(b, o, item, item)
            markFull(o, fits(nil))
        end
    end
    for _, x in ipairs(BridgeInventory.variants(item).list) do
        local t = x.t
        local o = sub:addOption(x.text, nil, function() pick(t) end)
        local sample = nil
        pcall(function() sample = ISInventoryPaneContextMenu.getItemInstance(t) end)
        wearTooltip(b, o, sample, item)
        markFull(o, fits(t))
    end
end





function BridgeInventory.wearOptions(context, b, player, items, list)
    local inv = b:getInventory()
    local t = BridgeInventory.wearTests(b, items)
    local target = t.clothing or t.container or t.other
    local plain = ((t.clothing ~= nil and not isBroken(t.clothing)) or t.container ~= nil or t.other ~= nil) and t.unequip == nil
    local outside = false
    for _, it in ipairs(list) do if it:getContainer() ~= inv then outside = true end end
    local plan = plain and BridgeInventory.wearAllList(b, player, list) or { entries = {} }


    if plain and outside and #plan.entries == 0 then plain = false end
    if plain and extraSubmenu(target) == nil then
        local o = context:addOption(label("InvWear"), player, BridgeInventory.wearList, plan)
        if list[1] ~= nil then iconOf(o, list[1], true) end
        wearTooltip(b, o, target, target)
        local wearing = {}
        for _, e in ipairs(plan.entries) do if e.wear then wearing[#wearing + 1] = e.item end end
        if #wearing == 1 and wearing[1]:getContainer() ~= inv then
            local it = wearing[1]
            local fits = BridgeInventory.wearFits(b, it, nil, player)
            if fits then fits = viaPlayerFits(player, it) end
            markFull(o, fits)
        end
    end
    if t.extra ~= nil and not isBroken(t.extra) and not BridgeInventory.handsGear(t.extra) then
        local item = t.extra
        local mine = item:getContainer() == inv
        if mine or BridgeInventory.canWearOnHer(player, item) then
            extraMenu(context, b, item, function(variant)

                if isHat(item) then pcall(function() BridgeInventory.hoodsDown(b, item) end) end
                if not mine then BridgeInventory.wearOnHer(player, item, variant)
                elseif variant ~= nil then
                    local _, newItem = BridgeInventory.wearVariant(b, item, variant, false, false, true)
                    BridgeInventory.gifted(b, newItem)
                else
                    BridgeInventory.wear(b, item, true)
                    BridgeInventory.gifted(b, item)
                end
            end, function(variant)
                if mine then return true end
                if not BridgeInventory.wearFits(b, item, variant, player) then return false end
                return viaPlayerFits(player, item)
            end)
        end
    end

    if t.unequip ~= nil and b:isEquippedClothing(t.unequip) then
        context:addOption(label("InvUnwear"), b, BridgeInventory.unwearAll, list)
    end
end

function BridgeInventory.onFill(playerNum, context, items)

    if playerNum ~= nil and playerNum ~= 0 then return end
    local b = body()
    if b == nil then return end
    local inv = b:getInventory()
    local list = actualItems(items)
    if #list == 0 then return end
    local inMain = true
    for _, it in ipairs(list) do
        if it:getContainer() ~= inv then inMain = false end
    end
    local player = getSpecificPlayer(playerNum or 0)



    if inMain or BridgeInventory.shown then
        local ok, err = pcall(BridgeInventory.wearOptions, context, b, player, items, list)
        if not ok then warnOnce("wear menu failed: " .. tostring(err)) end
    end
    if not inMain then



        local weapon = nil
        for _, it in ipairs(list) do
            local fav = false
            pcall(function() fav = it:isFavorite() end)
            if BridgeWeapon.isMelee(it) and not fav then weapon = it break end
        end
        if BridgeInventory.shown and weapon ~= nil then
            pcall(function()
                local opt = context:addOption(label("InvAssign"), player, BridgeInventory.assignOnHer, weapon)

                local fits = viaPlayerFits(player, weapon)
                if fits then pcall(function() fits = inv:hasRoomFor(player, weapon) ~= false end) end
                if not fits then
                    opt.notAvailable = true
                    local tip = ISInventoryPaneContextMenu.addToolTip()
                    tip.description = getText("ContextMenu_FullInventory")
                    opt.toolTip = tip
                end
            end)
        end
        return
    end


    local item = list[1]
    if BridgeWeapon.isMelee(item) then
        if BridgeWeapon.isAssigned(b, item) then
            context:addOption(label("InvUnassign"), b, BridgeInventory.drop, item)
        else
            context:addOption(label("InvAssign"), b, BridgeInventory.hands, item)
        end
    end
end



if Fishing ~= nil and Fishing.Handler ~= nil and Fishing.Handler.onEquipPrimary ~= nil
    and not Fishing.Handler.bridgeWrapped then
    local original = Fishing.Handler.onEquipPrimary
    Events.OnEquipPrimary.Remove(original)
    Fishing.Handler.onEquipPrimary = function(player, item)
        if not instanceof(player, "IsoPlayer") then return end
        return original(player, item)
    end
    Events.OnEquipPrimary.Add(Fishing.Handler.onEquipPrimary)
    Fishing.Handler.bridgeWrapped = true
    log("fishing handler wrapped")
end










local function containersOf(b)
    local out = {}
    pcall(function()
        local function walk(c, depth)
            out[#out + 1] = c
            if depth >= 3 then return end
            local items = c:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if it ~= nil and instanceof(it, "InventoryContainer") then walk(it:getInventory(), depth + 1) end
            end
        end
        walk(b:getInventory(), 0)
    end)
    return out
end





BridgeInventory.goneContainers = {}
local GONE_HOLD = 600
BridgeInventory.herContainers = nil
BridgeInventory.herContainersOf = nil

function BridgeInventory.forgetBody(b)
    if b == nil then return end
    local list = containersOf(b)
    if BridgeInventory.herContainersOf == b then
        for _, c in ipairs(BridgeInventory.herContainers or {}) do list[#list + 1] = c end
    end
    local main = nil
    pcall(function() main = b:getInventory() end)




    local hers = {}
    for _, c in ipairs(list) do
        local ok = c == main
        if not ok then
            pcall(function()
                local bag = c:getContainingItem()
                local where = bag ~= nil and bag:getContainer() or nil
                ok = bag ~= nil and bag:getWorldItem() == nil
                    and (where == nil or where == main or where:getOutermostContainer() == main)
            end)
        end
        if ok then hers[#hers + 1] = c end
    end
    list = hers



    local untilT = Bridge.time + GONE_HOLD
    for _, c in ipairs(list) do BridgeInventory.goneContainers[c] = untilT end


    for _, c in ipairs(list) do
        if c ~= main then pcall(function() c:clear() end) end
    end
    BridgeInventory.herContainers, BridgeInventory.herContainersOf = nil, nil
    refreshPanels()
    log("body left: " .. tostring(#list) .. " containers closed")
end


function BridgeInventory.goneAction(act)
    local g = BridgeInventory.goneContainers
    local now = Bridge.time or 0
    local gone = false
    pcall(function()
        local a = act.srcContainer ~= nil and g[act.srcContainer] or nil
        local d = act.destContainer ~= nil and g[act.destContainer] or nil
        gone = (a ~= nil and a > now) or (d ~= nil and d > now)
    end)
    return gone
end



function BridgeInventory.bodyArrived()
    local now = Bridge.time or 0
    local keep = {}
    for c, t in pairs(BridgeInventory.goneContainers) do
        if type(t) == "number" and t > now then keep[c] = t end
    end
    BridgeInventory.goneContainers = keep
end

function BridgeInventory.snapshot(b)
    BridgeInventory.herContainers = containersOf(b)
    BridgeInventory.herContainersOf = b
    local out = {}
    pcall(function()
        local primary, secondary = b:getPrimaryHandItem(), b:getSecondaryHandItem()
        local function walk(container, parent)
            local items = container:getItems()
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item ~= nil then
                    local rec = BridgeItems.record(item, false)
                    if parent == nil then
                        pcall(function() rec.w = b:isEquippedClothing(item) end)
                        if BridgeWeapon.isAssigned(b, item) then rec.as = true end
                        local h = 0
                        if primary ~= nil and item == primary then h = h + 1 end
                        if secondary ~= nil and item == secondary then h = h + 2 end
                        if h > 0 then rec.h = h end
                    else
                        rec.p = parent
                    end
                    out[#out + 1] = rec
                    local index = #out
                    local isBag = false
                    pcall(function() isBag = item:IsInventoryContainer() end)
                    if isBag then walk(item:getInventory(), index) end
                end
            end
        end
        walk(b:getInventory(), nil)
    end)
    return out
end

function BridgeInventory.encode(list) return BridgeItems.encode(list) end
function BridgeInventory.decode(text) return BridgeItems.decode(text) end
function BridgeInventory.applyRecord(item, rec) BridgeItems.apply(item, rec) end


function BridgeInventory.restore(b, list)
    note("restore " .. tostring(#list))
    local worn, hands, bag = 0, 0, 0
    local inv = b:getInventory()
    pcall(function() b:setPrimaryHandItem(nil) end)
    pcall(function() b:setSecondaryHandItem(nil) end)
    pcall(function() b:getWornItems():clear() end)
    pcall(function() inv:clear() end)

    BridgeWeapon.assignedId = nil
    local made = {}
    for i, rec in ipairs(list) do
        pcall(function()
            local container = inv
            if rec.p ~= nil then
                local parent = made[rec.p]
                if parent ~= nil and parent:IsInventoryContainer() then container = parent:getInventory() end
            end
            local item = BridgeItems.make(container, rec)
            made[i] = item
            if item == nil then return end
            if container == inv and rec.as and BridgeWeapon.isMelee(item) then
                BridgeWeapon.assignedId = item:getID()
            end
            if container ~= inv then
                bag = bag + 1
            elseif rec.w then
                if BridgeInventory.putOn(b, item) then worn = worn + 1 else bag = bag + 1 end
            elseif (rec.h or 0) > 0 and BridgeWeapon.isMelee(item) then
                if rec.h == 1 or rec.h == 3 then


                    pcall(function()
                        if BridgeWeapon.body ~= b then
                            local keepId = BridgeWeapon.assignedId
                            BridgeWeapon.reset()
                            BridgeWeapon.assignedId = keepId
                            BridgeWeapon.body = b
                        end
                    end)
                    b:setPrimaryHandItem(item)


                    pcall(function()
                        BridgeWeapon.heldId = item:getID()
                        BridgeWeapon.heldAt = Bridge.time
                    end)
                end
                if rec.h == 2 or rec.h == 3 then b:setSecondaryHandItem(item) end
                hands = hands + 1
            else
                bag = bag + 1
            end
        end)
    end
    redress(b)
    return worn, hands, bag
end





function BridgeInventory.dressVisual(b, encoded, rec)
    local list = BridgeItems.decode(encoded or "")
    pcall(function() BridgeInventory.skin(b, rec) end)
    local primary, secondary = nil, nil
    pcall(function()
        local visuals = b:getItemVisuals()
        visuals:clear()
        for _, rec in ipairs(list) do
            if rec.p == nil then
                if rec.w then
                    visuals:add(BridgeItems.visual(rec))
                elseif rec.h == 1 or rec.h == 3 then
                    primary = rec
                elseif rec.h == 2 then
                    secondary = rec
                end
            end
        end
    end)
    local function same(item, rec)
        return item ~= nil and rec ~= nil and item:getFullType() == rec.t
    end
    pcall(function()
        local cur = b:getPrimaryHandItem()
        if primary == nil then
            if cur ~= nil then b:setPrimaryHandItem(nil) end
        elseif not same(cur, primary) then
            cur = instanceItem(primary.t)
            b:setPrimaryHandItem(cur)
        end
        if primary ~= nil and primary.h == 3 then
            b:setSecondaryHandItem(cur)
        elseif secondary == nil then
            if b:getSecondaryHandItem() ~= nil then b:setSecondaryHandItem(nil) end
        elseif not same(b:getSecondaryHandItem(), secondary) then
            b:setSecondaryHandItem(instanceItem(secondary.t))
        end
    end)

    pcall(function() BridgeWeapon.dressGuest(b, list) end)
    pcall(function() b:resetModelNextFrame() end)
    pcall(function() b:resetModel() end)
end





















BridgeInventory.pending = BridgeInventory.pending or {}
BridgeInventory.takes = BridgeInventory.takes or {}
BridgeInventory.taking = BridgeInventory.taking or {}
BridgeInventory.answers = BridgeInventory.answers or {}
BridgeInventory.token = BridgeInventory.token or 0
local WAIT_TICKS = 300
local LATE_TICKS = 3600


function BridgeInventory.inBody(container)
    local b = body()
    if b == nil or container == nil then return false end
    local inv = b:getInventory()
    if container == inv then return true end
    local outer = nil
    pcall(function() outer = container:getOutermostContainer() end)
    return outer == inv
end


function BridgeInventory.receive(args)
    if type(args.iseq) == "number" then Bridge.iseq = args.iseq end
    local p = nil
    if args.id ~= nil then
        p = BridgeInventory.pending[args.id]
        BridgeInventory.pending[args.id] = nil
    end
    local function answer(ok, why)
        if args.token ~= nil then BridgeInventory.answers[args.token] = { ok = ok, why = why } end
    end
    local b = body()
    if b == nil then

        if args.rec ~= nil then
            pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "take", { rec = args.rec, token = -1, returnId = args.id }) end)
        end
        answer(false, "no body")
        return "no body, returned"
    end
    local failed = nil
    local ok, err = pcall(function()
        local dest = b:getInventory()
        if p ~= nil and p.dest ~= nil and BridgeInventory.inBody(p.dest) then dest = p.dest end
        local obj = p and p.item or nil
        if obj ~= nil then
            local old = obj:getContainer()
            if old ~= nil then old:Remove(obj) end
            dest:AddItem(obj)
        elseif args.rec ~= nil then
            BridgeItems.make(dest, args.rec)
        else
            failed = "nothing to put"
        end
    end)
    if failed ~= nil then ok, err = false, failed end
    note("receive " .. tostring(args.rec and args.rec.t))
    if not ok then
        if args.rec ~= nil then
            pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "take", { rec = args.rec, token = -1, returnId = args.id }) end)
        end
        answer(false, tostring(err))
        return "receive failed, returned: " .. tostring(err)
    end
    answer(true)

    if BridgeHeal ~= nil then BridgeHeal.emptySig = nil end
    refreshPanels()
    pcall(function() Bridge.saveOutfit() end)
    return "received " .. tostring(args.rec and args.rec.t)
end



function BridgeInventory.relayGive(h)
    if h == nil or h.character == nil or body() == nil then return end
    local inv = h.character:getInventory()
    local it = h.item
    pcall(function()
        local found = inv:getItemWithIDRecursiv(h.id)
        if found ~= nil then it = found end
    end)
    local dest = h.dest
    if not BridgeInventory.inBody(dest) then dest = body():getInventory() end

    local act = ISInventoryTransferAction:new(h.character, it, inv, dest)
    if act.bridgeDir ~= "give" then return end
    act.relayId = h.id

    if h.herLoot ~= nil then act.bridgeHerLoot = h.herLoot
    elseif h.fromFloor then act.bridgeHerLoot = LOOT_ANIM end


    BridgeInventory.markHers(act)

    if h.after ~= nil then act:setOnComplete(h.after.f, h.after.a, h.after.b) end
    note("relay give " .. tostring(h.id))
    ISTimedActionQueue.addAfter(h.action, act)
end





function BridgeInventory.giveDirect(item, why)
    local b = body()
    local red = BridgeData.owner()
    if not Bridge.mp or b == nil or red == nil or item == nil then return false end
    local id = nil
    pcall(function()
        local found = red:getInventory():getItemWithIDRecursiv(item:getID())
        if found ~= nil then item, id = found, found:getID() end
    end)
    if id == nil or BridgeInventory.pending[id] ~= nil then return false end
    local room = true
    pcall(function() room = b:getInventory():hasRoomFor(red, item) ~= false end)
    if not room then
        log("her transfer broke off (" .. tostring(why) .. "): no room with her, " .. tostring(item:getType()) .. " stays with the player")
        return false
    end
    BridgeInventory.pending[id] = { item = item, dest = b:getInventory() }
    local ok = pcall(function() sendClientCommand(red, "Bridge", "give", { id = id }) end)
    log("her transfer broke off (" .. tostring(why) .. "): " .. tostring(item:getType()) .. " given back to her")
    return ok
end

function BridgeInventory.giveFailed(args)
    if args.id ~= nil then BridgeInventory.pending[args.id] = nil end
    if args.token ~= nil then BridgeInventory.answers[args.token] = { ok = false, why = args.why } end
    log("give failed: " .. tostring(args.why))
end



function BridgeInventory.took(args)
    if type(args.iseq) == "number" then Bridge.iseq = args.iseq end
    local t = nil
    if args.token ~= nil then
        t = BridgeInventory.takes[args.token]
        BridgeInventory.takes[args.token] = nil
    end
    if t ~= nil and t.item ~= nil then BridgeInventory.taking[t.item] = nil end
    if args.ok and t ~= nil and t.item ~= nil then
        pcall(function() note("took " .. t.item:getType()) end)
        local b = body()
        pcall(function()
            local item = t.item
            if b ~= nil then
                if b:getPrimaryHandItem() == item then b:setPrimaryHandItem(nil) end
                if b:getSecondaryHandItem() == item then b:setSecondaryHandItem(nil) end
                if b:isEquippedClothing(item) then b:removeWornItem(item) end
            end
            local c = item:getContainer()
            if c ~= nil then c:Remove(item) end
        end)
        if b ~= nil then redress(b) end
        refreshPanels()
        pcall(function() Bridge.saveOutfit() end)
    end
    local late = t ~= nil and t.lateSince ~= nil
    if late then

        log("late answer to take: " .. tostring(args.ok) .. ", item " .. (args.ok and "removed from her" or "stays with her"))
    elseif args.token ~= nil and args.token >= 0 then
        BridgeInventory.answers[args.token] = { ok = args.ok == true, id = args.id, why = args.why }
    end
    if not args.ok then log("take failed: " .. tostring(args.why)) end
end




function BridgeInventory.swapInQueue(character, old, new, current)
    local function swap(t, depth)
        if type(t) ~= "table" or depth > 2 then return end
        for k, v in pairs(t) do
            if v == old then
                t[k] = new
            elseif type(v) == "table" and k ~= "character" and k ~= "action" then
                swap(v, depth + 1)
            end
        end
    end
    pcall(function()
        local q = ISTimedActionQueue.getTimedActionQueue(character)
        for _, a in ipairs(q.queue or {}) do
            if a ~= current and type(a) == "table" then swap(a, 1) end
        end
    end)
    for _, a in ipairs(BridgeQueue ~= nil and BridgeQueue.jobs or {}) do
        if a ~= current and type(a) == "table" then pcall(swap, a, 1) end
    end


    for _, p in pairs(BridgeInventory.pending or {}) do
        if p.dest == old then p.dest = new end
    end
end

if ISInventoryTransferAction ~= nil and not ISInventoryTransferAction.bridgeWrapped then
    BridgeTransferAction = ISInventoryTransferAction:derive("BridgeTransferAction")
    BridgeTransferAction.__index = BridgeTransferAction



    function BridgeTransferAction:findRelay()
        if self.relayId == nil then return end
        local inv = self.character:getInventory()
        local here = false
        pcall(function() here = self.srcContainer:contains(self.item) and self.srcContainer:getOutermostContainer() == inv end)
        if here then return end
        pcall(function()
            local it = inv:getItemWithIDRecursiv(self.relayId)
            if it ~= nil then
                self.item = it
                self.srcContainer = it:getContainer()
            end
        end)
    end

    function BridgeTransferAction:isValid()
        if self.item == nil or self.srcContainer == nil or self.destContainer == nil then return false end

        if self.sent then return true end
        if self.relayId ~= nil and not self.started then
            self:findRelay()
            if not self.srcContainer:contains(self.item) then return (self.relayWait or 0) < WAIT_TICKS end
        end
        if not self.srcContainer:contains(self.item) then


            return self.allowMissingItems == true
        end
        local inv = self.character:getInventory()

        if body() == nil then return false end




        local function room()
            if self.started then return true end
            local ok = true
            pcall(function() ok = self.destContainer:hasRoomFor(self.character, self.item) ~= false end)
            return ok
        end
        if self.bridgeDir == "give" then
            if BridgeInventory.pending[self.item:getID()] ~= nil then return false end
            return self.srcContainer:getOutermostContainer() == inv and room()
        elseif self.bridgeDir == "take" then

            local token = BridgeInventory.taking[self.item]
            if token ~= nil then
                local t = BridgeInventory.takes[token]
                local lost = t == nil or (t.lateSince ~= nil and (Bridge.time - t.lateSince) > LATE_TICKS)
                if not lost then return false end

                BridgeInventory.taking[self.item] = nil
                BridgeInventory.takes[token] = nil
            end
            return self.destContainer:getOutermostContainer() == inv
        end
        return room()
    end

    function BridgeTransferAction:waitToStart()
        if BridgeInventory.holdWhileWalking(self) then return true end
        if self.relayId == nil then return false end
        self:findRelay()
        if self.srcContainer ~= nil and self.srcContainer:contains(self.item) then return false end
        self.relayWait = (self.relayWait or 0) + (Bridge.dt or 1)
        return self.relayWait < WAIT_TICKS
    end
    function BridgeTransferAction:canMergeAction(action) return false end

    function BridgeTransferAction:start()
        self.action:setTime(self.maxTime)
        pcall(function() self:startActionAnim() end)
        self.started = true
        if self.bridgeDir == "inner" then return end
        if not self.srcContainer:contains(self.item) then

            self.missing = true
            self.action:setTime(0)
            return
        end
        BridgeInventory.token = BridgeInventory.token + 1
        self.token = BridgeInventory.token
        self.sentTick = Bridge.time
        if self.bridgeDir == "give" then
            local id = self.item:getID()
            BridgeInventory.pending[id] = { item = self.item, dest = self.destContainer }
            sendClientCommand(self.character, "Bridge", "give", { id = id, token = self.token })
        else
            BridgeInventory.takes[self.token] = { item = self.item }
            BridgeInventory.taking[self.item] = self.token

            local destId = nil
            pcall(function()
                local holder = self.destContainer:getContainingItem()
                if holder ~= nil then destId = holder:getID() end
            end)


            local w, h, top = false, nil, false
            pcall(function()
                local b = body()
                if b == nil then return end
                top = self.item:getContainer() == b:getInventory()
                w = b:isEquippedClothing(self.item) == true
                local hands = 0
                if b:getPrimaryHandItem() == self.item then hands = hands + 1 end
                if b:getSecondaryHandItem() == self.item then hands = hands + 2 end
                if hands > 0 then h = hands end
            end)
            sendClientCommand(self.character, "Bridge", "take",
                { rec = BridgeItems.record(self.item, true), token = self.token, dest = destId, w = w, h = h, top = top })
        end
        self.sent = true
        pcall(function() self.action:setWaitForFinished(true) end)
    end

    function BridgeTransferAction:update()
        if BridgeInventory.staysGuard(self) then return end
        pcall(function() self.item:setJobDelta(self.action:getJobDelta()) end)

        if self.bridgeHers and BridgeProgress ~= nil then pcall(function() BridgeProgress.show(self.action:getJobDelta()) end) end
        if not self.sent then return end
        local a = BridgeInventory.answers[self.token]
        if a == nil then
            if (Bridge.time - self.sentTick) > WAIT_TICKS then
                log("no answer from server: " .. tostring(self.bridgeDir))

                pcall(function() BridgeInventory.pending[self.item:getID()] = nil end)





                local t = BridgeInventory.takes[self.token]
                if t ~= nil then t.lateSince = Bridge.time end
                pcall(function() self.action:forceStop() end)
            end
            return
        end
        if not a.ok then
            BridgeInventory.answers[self.token] = nil
            pcall(function() self.action:forceStop() end)
            return
        end
        if self.bridgeDir == "take" and self.newItem == nil then

            pcall(function() self.newItem = self.character:getInventory():getItemWithIDRecursiv(a.id) end)
            if self.newItem == nil and (Bridge.time - self.sentTick) < WAIT_TICKS then return end
        end
        BridgeInventory.answers[self.token] = nil
        pcall(function() self.action:forceComplete() end)
    end

    function BridgeTransferAction:stop()
        pcall(function() self.item:setJobDelta(0) end)
        pcall(function() self.action:stopTimedActionAnim() end)
        pcall(function() self.action:setLoopedAction(false) end)
        ISBaseTimedAction.stop(self)
    end

    function BridgeTransferAction:perform()
        pcall(function() self.item:setJobDelta(0) end)
        if self.missing then
            pcall(function() self.action:stopTimedActionAnim() end)
            pcall(function() self.action:setLoopedAction(false) end)
            ISBaseTimedAction.perform(self)
            return
        end
        if self.bridgeDir == "inner" then
            local b = body()
            pcall(function() note("inner " .. self.item:getType()) end)
            pcall(function()
                if b ~= nil then
                    if b:getPrimaryHandItem() == self.item then b:setPrimaryHandItem(nil) end
                    if b:getSecondaryHandItem() == self.item then b:setSecondaryHandItem(nil) end
                    if b:isEquippedClothing(self.item) then b:removeWornItem(self.item) end
                end
                self.srcContainer:Remove(self.item)
                self.destContainer:AddItem(self.item)
            end)
            if b ~= nil then redress(b) end
            refreshPanels()
            pcall(function() Bridge.saveOutfit() end)
        end
        local item = self.item
        if self.bridgeDir == "take" and self.newItem ~= nil then
            BridgeInventory.swapInQueue(self.character, self.item, self.newItem, self)
            item = self.newItem
            if self.finalDest ~= nil then

                local newItem, finalDest, character = self.newItem, self.finalDest, self.character
                local herLoot = nil
                pcall(function() herLoot = BridgeInventory.lootAnimFor(finalDest) end)
                pcall(function()
                    local nextAct = ISInventoryTransferAction:new(character, newItem, newItem:getContainer(), finalDest)

                    nextAct.bridgeReturn = true

                    if herLoot ~= nil then nextAct.bridgeHerLoot = herLoot end
                    BridgeInventory.markHers(nextAct)
                    ISTimedActionQueue.addAfter(self, nextAct)
                end)
            end
        end
        pcall(function() self.action:stopTimedActionAnim() end)
        pcall(function() self.action:setLoopedAction(false) end)
        pcall(function() self.action:setWaitForFinished(false) end)
        if self.onCompleteFunc ~= nil then
            local args = self.onCompleteArgs or {}
            for i = 1, 8 do if args[i] == self.item then args[i] = item end end
            self.onCompleteArgs = args
            pcall(self.onCompleteFunc, args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8])
        end
        ISBaseTimedAction.perform(self)
    end

    local originalNew = ISInventoryTransferAction.new
    ISInventoryTransferAction.new = function(self, character, item, srcContainer, destContainer, time)
        local o = originalNew(self, character, item, srcContainer, destContainer, time)

        BridgeInventory.markHers(o)
        if not isClient() or self ~= ISInventoryTransferAction or item == nil then return o end
        local fromBody = BridgeInventory.inBody(srcContainer)
        local toBody = BridgeInventory.inBody(destContainer)
        local dir = nil
        if fromBody and toBody then dir = "inner"
        elseif toBody then dir = "give"
        elseif fromBody then dir = "take" end
        if dir == nil then return o end
        local inv = character:getInventory()
        local function carried(c)
            local outer = nil
            pcall(function() outer = c:getOutermostContainer() end)
            return outer == inv
        end
        local room = true
        pcall(function() room = inv:hasRoomFor(character, item) ~= false end)
        if dir == "give" and not carried(srcContainer) and room then




            local first = originalNew(self, character, item, srcContainer, inv, time)
            local fromFloor = false
            pcall(function() fromFloor = srcContainer:getType() == "floor" end)
            local herLoot = nil
            pcall(function() herLoot = BridgeInventory.lootAnimFor(srcContainer) end)
            local relay = { character = character, item = item, id = item:getID(), dest = destContainer, action = first,
                            fromFloor = fromFloor, herLoot = herLoot }
            first:setOnComplete(BridgeInventory.relayGive, relay)
            first.bridgeRelay = relay
            BridgeInventory.markHers(first)
            return first
        end
        setmetatable(o, BridgeTransferAction)
        o.bridgeDir = dir
        o.maxTime = 25
        o.loopedAction = false




        if dir == "give" then
            local equipped, heavy = false, false
            pcall(function() equipped = character:isEquipped(item) end)
            pcall(function() heavy = isForceDropHeavyItem ~= nil and isForceDropHeavyItem(item) end)
            if equipped and not heavy and ISUnequipAction ~= nil then
                pcall(function()
                    local un = ISUnequipAction:new(character, item, 50)




                    local valid = un.isValid
                    un.isValid = function(self)
                        local fits = true
                        pcall(function() fits = destContainer:hasRoomFor(character, item) ~= false end)
                        if not fits then
                            log("unequip before give skipped: no room for " .. tostring(item:getType()))
                            return false
                        end
                        return valid(self)
                    end
                    ISTimedActionQueue.add(un)
                end)
                o.unequipFirst = true
            end
        end
        if dir == "take" and not carried(destContainer) then
            o.finalDest = destContainer
            o.destContainer = inv
        end
        return o
    end
    ISInventoryTransferAction.bridgeWrapped = true
    log("transfer wrapped for multiplayer")
end





















local function toFloor(act)
    local yes = false
    pcall(function()
        if act.destContainer ~= nil and act.destContainer:getType() == "floor" then yes = true end
        if act.finalDest ~= nil and act.finalDest:getType() == "floor" then yes = true end
    end)
    return yes
end

BridgeInventory.toFloor = toFloor

function BridgeInventory.markHers(act)
    pcall(function()
        if type(act) == "table" and act.item ~= nil and not (isClient() and toFloor(act))
            and BridgeInventory.herAnimFor(act) ~= nil then
            act.stopOnWalk = false
            act.bridgeStays = true
        end
    end)
    return act
end


function BridgeInventory.staysGuard(act)
    if not act.bridgeStays then return false end

    if act.sent then return false end
    local stop, why = false, nil
    pcall(function()
        local chr = act.character
        if not act.bridgeHers then
            if chr:isPlayerMoving() then stop, why = true, "player animates and walks" end
            return
        end
        local b = body()
        if b == nil or Bridge.hiddenSince ~= nil then stop, why = true, "no body" return end

        if not playerNear(b, GESTURE_LEAVE) then stop, why = true, "player went away" return end


        if BridgeFight ~= nil and (BridgeFight.target ~= nil or BridgeFight.state == "swing") then stop, why = true, "fight" return end
        if Bridge.mourning ~= nil then stop, why = true, "mourning" return end
        if Bridge.pose ~= nil then stop, why = true, "pose" return end

        local asn = tostring(b:getActionStateName())
        if asn ~= "idle" and asn ~= "bumped" and asn ~= "walktoward" and asn ~= "pathfind" then
            stop, why = true, "state " .. asn
        end
    end)
    if stop then
        act.bridgeStays = false
        pcall(function() log("her transfer stopped: " .. tostring(why)) end)
        pcall(function() act:forceStop() end)
    end
    return stop
end







function BridgeInventory.holdWhileWalking(act)
    local hold = false
    pcall(function()
        if not act.bridgeStays or BridgeInventory.herAnimFor(act) == nil then return end
        for _, g in ipairs(BridgeInventory.gestures) do
            if g.action == act then return end
        end
        local b = body()
        if b == nil or Bridge.hiddenSince ~= nil or not playerNear(b, GESTURE_LEAVE) then return end
        if BridgeWeapon == nil or BridgeWeapon.redWalking == nil or not BridgeWeapon.redWalking() then return end
        act.bridgeHeldSince = act.bridgeHeldSince or Bridge.time
        hold = Bridge.time - act.bridgeHeldSince < GESTURE_WAIT_MAX
    end)
    if hold and not act.bridgeHeldLogged then
        act.bridgeHeldLogged = true
        pcall(function() log("her transfer waits: player walking") end)
    end
    return hold
end






function BridgeInventory.keepFloorItem(act)
    pcall(function()
        local src = act.srcContainer
        if src == nil or src:getType() ~= "floor" or src:contains(act.item) then return end
        local wi = act.item:getWorldItem()
        if wi == nil or wi:getSquare() == nil then return end
        src:AddItem(act.item)
    end)
end

if ISInventoryTransferAction ~= nil and not ISInventoryTransferAction.bridgeStaysWrapped then
    local waitToStart = ISInventoryTransferAction.waitToStart
    if waitToStart ~= nil then
        ISInventoryTransferAction.waitToStart = function(self, ...)
            if BridgeInventory.holdWhileWalking(self) then return true end
            return waitToStart(self, ...)
        end
    end
    local isValid = ISInventoryTransferAction.isValid
    if isValid ~= nil then
        ISInventoryTransferAction.isValid = function(self, ...)
            if BridgeInventory.goneAction(self) then return false end
            if self.bridgeStays then BridgeInventory.keepFloorItem(self) end
            return isValid(self, ...)
        end
    end


    local canMerge = ISInventoryTransferAction.canMergeAction
    if canMerge ~= nil then
        ISInventoryTransferAction.canMergeAction = function(self, action)
            if not canMerge(self, action) then return false end
            local mine, other = false, false
            pcall(function() mine = BridgeInventory.herAnimFor(self) ~= nil end)
            pcall(function() other = BridgeInventory.herAnimFor(action) ~= nil end)
            return mine == other
        end
    end
    ISInventoryTransferAction.bridgeStaysWrapped = true
end




function BridgeInventory.herFloorSquare(act, item)
    local b = body()
    if b == nil then return nil end
    local found = nil
    pcall(function()
        local cur = b:getCurrentSquare()
        if cur == nil then return end
        local function ok(sq)
            if sq == nil or not sq:TreatAsSolidFloor() or sq:isSolid() or sq:isSolidTrans() then return false end
            if sq ~= cur then
                if cur:isBlockedTo(sq) or cur:isWindowTo(sq) then return false end
                if cur:HasStairs() ~= sq:HasStairs() then return false end
                if cur:HasStairs() and not cur:isSameStaircase(sq:getX(), sq:getY(), sq:getZ()) then return false end
            end
            return act:floorHasRoomFor(sq, item)
        end
        if ok(cur) then found = cur return end
        local x, y, z = cur:getX(), cur:getY(), cur:getZ()
        for dy = -1, 1 do
            for dx = -1, 1 do
                if (dx ~= 0 or dy ~= 0) and found == nil then
                    local sq = getCell():getGridSquare(x + dx, y + dy, z)
                    if ok(sq) then found = sq end
                end
            end
        end
    end)
    return found
end

if ISInventoryTransferAction ~= nil and ISInventoryTransferAction.getNotFullFloorSquare ~= nil
    and not ISInventoryTransferAction.bridgeFloorSquareWrapped then
    local getNotFull = ISInventoryTransferAction.getNotFullFloorSquare
    ISInventoryTransferAction.getNotFullFloorSquare = function(self, item, ...)

        if self.bridgeStays and self.bridgeHers ~= false and not isClient() and toFloor(self) then
            local sq = BridgeInventory.herFloorSquare(self, item)
            if sq ~= nil then return sq end
        end
        return getNotFull(self, item, ...)
    end
    ISInventoryTransferAction.bridgeFloorSquareWrapped = true
end






function BridgeInventory.transferPending(b)
    local pending, why = false, "?"
    if b == nil then why = "no body"
    elseif Bridge.hiddenSince ~= nil then why = "hidden"
    elseif not playerNear(b, GESTURE_LEAVE) then why = "player far"
    else
        why = "check failed"
        pcall(function()
            local red = BridgeData.owner()

            local a = BridgeQueue ~= nil and BridgeQueue.jobs[1] or nil
            local n = BridgeQueue ~= nil and #BridgeQueue.jobs or 0
            local q = nil
            if a == nil then
                q = ISTimedActionQueue.getTimedActionQueue(red)
                a = q ~= nil and q.queue ~= nil and q.queue[1] or nil
                n = q ~= nil and q.queue ~= nil and #q.queue or 0
            end
            if a == nil then why = "queue empty" return end
            local anim = BridgeInventory.herAnimFor(a)
            why = string.format("first %s own=%s stays=%s hers=%s anim=%s n=%d", tostring(a.Type), tostring(a.bridgeOwn),
                tostring(a.bridgeStays), tostring(a.bridgeHers), tostring(anim), n)
            if a.bridgeStays and a.bridgeHers ~= false and anim ~= nil then pending = true end
        end)
    end

    if pending ~= BridgeInventory.pendingLogged then
        BridgeInventory.pendingLogged = pending
        log("transfer pending " .. tostring(pending) .. ": " .. tostring(why))
    end
    BridgeInventory.pendingWhy = why
    return pending
end


if ISInventoryTransferAction ~= nil and ISInventoryTransferAction.startActionAnim ~= nil
    and not ISInventoryTransferAction.bridgeLootWrapped then
    local startActionAnim = ISInventoryTransferAction.startActionAnim
    ISInventoryTransferAction.startActionAnim = function(self, ...)
        local hers = false
        pcall(function()
            local anim = BridgeInventory.herAnimFor(self)
            hers = anim ~= nil and BridgeInventory.lootFor(self, anim)
        end)
        if not hers and self.bridgeOwn then

            self.bridgeHers = false
            pcall(function() self:forceStop() end)
            return
        end
        if not hers then

            if self.bridgeHers then
                self.bridgeHers = false
                pcall(function() self.action:setUseProgressBar(true) end)
                self.useProgressBar = true
            end
            return startActionAnim(self, ...)
        end
        self.bridgeHers = true

        if BridgeProgress ~= nil then pcall(function() BridgeProgress.takeOver(self) end) end

        pcall(function()
            self.item:setJobType(getText("IGUI_MovingToContainer"))
            self.jobType = self.item:getJobType() .. ": " .. self.item:getName()
        end)



        pcall(function()
            local chr, src, dst = self.character, self.srcContainer, self.destContainer
            if src == chr:getInventory() then
                if not dst:isInCharacterInventory(chr) then self.bridgeSelect = dst end
            elseif src:isInCharacterInventory(chr) then
                if dst ~= chr:getInventory() then self.bridgeSelect = dst end
            elseif dst:isInCharacterInventory(chr) then
                self.bridgeSelect = src
            end
        end)
    end
    ISInventoryTransferAction.bridgeLootWrapped = true
end

















BridgeInventory.bwoMarks = BridgeInventory.bwoMarks or {}

function BridgeInventory.notStolen(act)
    if type(BWOScheduler) ~= "table" then return end
    pcall(function()
        if not BridgeInventory.inBody(act.srcContainer) then return end
        local function mark(it)
            if it == nil or BridgeInventory.bwoMarks[it] ~= nil then return end
            local md = it:getModData()
            BridgeInventory.bwoMarks[it] = { had = md.BWO ~= nil, bought = md.BWO ~= nil and md.BWO.bought or nil }
            if md.BWO == nil then md.BWO = { stolen = false } end
            md.BWO.bought = true
        end
        mark(act.item)
        for _, q in ipairs(act.queueList or {}) do
            for _, it in ipairs(q.items or {}) do mark(it) end
        end
        for _, a in ipairs(BridgeInventory.queuedActions()) do
            if a ~= act and a.srcContainer == act.srcContainer and a.destContainer == act.destContainer then
                mark(a.item)
                for _, q in ipairs(a.queueList or {}) do
                    for _, it in ipairs(q.items or {}) do mark(it) end
                end
            end
        end
    end)
end


function BridgeInventory.restoreBought()
    for it, prev in pairs(BridgeInventory.bwoMarks) do
        local gone = true
        pcall(function() gone = not BridgeInventory.inBody(it:getContainer()) end)
        if gone then
            pcall(function()
                local md = it:getModData()
                if not prev.had then md.BWO = nil elseif md.BWO ~= nil then md.BWO.bought = prev.bought end
            end)
            BridgeInventory.bwoMarks[it] = nil
        end
    end
end


if Events ~= nil and Events.OnGameStart ~= nil and not BridgeInventory.bwoHooked then
    BridgeInventory.bwoHooked = true
    Events.OnGameStart.Add(function()
        if Events.OnInventoryTransferActionPerform ~= nil then
            Events.OnInventoryTransferActionPerform.Add(function() pcall(BridgeInventory.restoreBought) end)
        end
    end)
end


local function reselect(act)
    if act.bridgeSelect == nil then return end
    local loot = nil
    pcall(function() loot = getPlayerLoot(act.character:getPlayerNum()) end)
    if loot == nil then return end
    pcall(function() loot:selectButtonForContainer(act.bridgeSelect) end)
end
if ISInventoryTransferAction ~= nil and ISInventoryTransferAction.perform ~= nil
    and not ISInventoryTransferAction.bridgeSelectWrapped then
    local perform = ISInventoryTransferAction.perform
    ISInventoryTransferAction.perform = function(self, ...)
        BridgeInventory.notStolen(self)

        local hers = false
        pcall(function()
            hers = BridgeInventory.inBody(self.srcContainer) or BridgeInventory.inBody(self.destContainer)
        end)
        local r = perform(self, ...)
        reselect(self)



        if hers and Bridge ~= nil and not Bridge.mp then
            pcall(function() Bridge.saveOutfit() end)
            pcall(function() if BridgeBackup ~= nil and BridgeBackup.flushNow ~= nil then BridgeBackup.flushNow() end end)
        end

        if BridgeHeal ~= nil and BridgeInventory.inBody(self.destContainer) then BridgeHeal.emptySig = nil end
        return r
    end
    ISInventoryTransferAction.bridgeSelectWrapped = true
end






if ISInventoryTransferAction ~= nil and ISInventoryTransferAction.update ~= nil
    and not ISInventoryTransferAction.bridgeMoodWrapped then
    local update = ISInventoryTransferAction.update
    ISInventoryTransferAction.update = function(self, ...)


        if BridgeInventory.goneAction(self) then
            pcall(function() self:forceStop() end)
            return
        end
        if BridgeInventory.staysGuard(self) then return end
        local stats, u0, s0 = nil, nil, nil
        if self.bridgeHers then
            pcall(function()
                stats = self.character:getStats()
                u0 = stats:get(CharacterStat.UNHAPPINESS)
                s0 = stats:get(CharacterStat.STRESS)
            end)
        end
        local r = update(self, ...)
        reselect(self)
        if self.bridgeHers and BridgeProgress ~= nil then pcall(function() BridgeProgress.show(self.action:getJobDelta()) end) end
        if stats ~= nil and u0 ~= nil then
            pcall(function()
                local du = stats:get(CharacterStat.UNHAPPINESS) - u0
                if du > 0 then stats:add(CharacterStat.UNHAPPINESS, -du) end
                local ds = stats:get(CharacterStat.STRESS) - s0
                if ds > 0 then stats:add(CharacterStat.STRESS, -ds) end
            end)
        end
        return r
    end
    ISInventoryTransferAction.bridgeMoodWrapped = true
end





local function isHerMain(container)
    local b = body()
    local yes = false
    pcall(function() yes = b ~= nil and container ~= nil and container == b:getInventory() end)
    return yes, b
end

function BridgeInventory.wrapLootControls()
    if ISInventoryPane ~= nil and ISInventoryPane.lootAll ~= nil and not ISInventoryPane.bridgeLootAllWrapped then
        local lootAll = ISInventoryPane.lootAll
        ISInventoryPane.lootAll = function(self, ...)
            local hers, b = isHerMain(self.inventory)
            if not hers then return lootAll(self, ...) end
            local playerObj = getSpecificPlayer(self.player)
            local playerInv = getPlayerInventory(self.player).inventory
            local items = {}
            if luautils.walkToContainer(self.inventory, self.player) then
                local it = self.inventory:getItems()
                for i = 0, it:size() - 1 do
                    local item = it:get(i)
                    local heavy = false
                    pcall(function() heavy = isForceDropHeavyItem(item) end)
                    if not item:isUnwanted(playerObj) and not heavy and not BridgeInventory.keepOnHer(b, item) then
                        items[#items + 1] = item
                    end
                end
                if #items > 0 then self:transferItemsByWeight(items, playerInv) end
            end
            self.selected = {}
            pcall(function() getPlayerLoot(self.player).inventoryPane.selected = {} end)
            pcall(function() getPlayerInventory(self.player).inventoryPane.selected = {} end)
        end
        ISInventoryPane.bridgeLootAllWrapped = true
    end
    local toFloor = ISLootWindowObjectControlHandler_MoveToFloor
    if toFloor ~= nil and toFloor.perform ~= nil and not toFloor.bridgeWrapped then
        local perform = toFloor.perform
        toFloor.perform = function(self, ...)
            local hers, b = isHerMain(self.container)
            if not hers then return perform(self, ...) end
            if isGamePaused() then return end
            local items = {}
            local list = self.container:getItems()
            for i = 1, list:size() do
                local item = list:get(i - 1)
                if not BridgeInventory.keepOnHer(b, item) then items[#items + 1] = item end
            end
            if #items > 0 then
                ISInventoryPaneContextMenu.onMoveItemsTo(items, ISInventoryPage.GetFloorContainer(self.playerNum), self.playerNum)
            end
        end
        toFloor.bridgeWrapped = true
    end
    local same = ISLootWindowObjectControlHandler_TakeSameType
    if same ~= nil and same.getItemsToTransfer ~= nil and not same.bridgeWrapped then
        local getItems = same.getItemsToTransfer
        same.getItemsToTransfer = function(self, ...)
            local list, map = getItems(self, ...)
            local hers, b = isHerMain(self.container)
            if not hers then return list, map end
            local outList, outMap = {}, {}
            for _, item in ipairs(list or {}) do
                if not BridgeInventory.keepOnHer(b, item) then
                    outList[#outList + 1] = item
                    outMap[item] = true
                end
            end
            return outList, outMap
        end
        same.bridgeWrapped = true
    end



    local menu = ISInventoryPaneContextMenu
    if menu ~= nil and menu.onInspectClothing ~= nil and menu.onInspectClothingUI ~= nil and not menu.bridgeInspectWrapped then
        local inspect = menu.onInspectClothing
        menu.onInspectClothing = function(playerObj, clothing, ...)
            local hers = false
            pcall(function() hers = BridgeInventory.inBody(clothing:getContainer()) end)
            if hers then return menu.onInspectClothingUI(playerObj, clothing) end
            return inspect(playerObj, clothing, ...)
        end
        menu.bridgeInspectWrapped = true
    end





    if ISGarmentUI ~= nil and ISGarmentUI.update ~= nil and not ISGarmentUI.bridgeWrapped then
        local update = ISGarmentUI.update
        ISGarmentUI.update = function(self, ...)
            local hers = false
            pcall(function()
                hers = self.clothing ~= nil and BridgeInventory.shown == true and BridgeInventory.inBody(self.clothing:getContainer())
            end)
            if hers and ISCollapsableWindow ~= nil and ISCollapsableWindow.update ~= nil then
                return ISCollapsableWindow.update(self, ...)
            end
            return update(self, ...)
        end
        ISGarmentUI.bridgeWrapped = true
    end
end
BridgeInventory.wrapLootControls()
Events.OnGameStart.Add(BridgeInventory.wrapLootControls)

Events.OnRefreshInventoryWindowContainers.Add(BridgeInventory.onRefresh)
Events.OnFillInventoryObjectContextMenu.Add(BridgeInventory.onFill)
log("loaded v9")

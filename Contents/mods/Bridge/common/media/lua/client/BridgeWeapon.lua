








BridgeWeapon = BridgeWeapon or {}
BridgeWeapon.want = nil
BridgeWeapon.changeAt = nil
BridgeWeapon.assignedId = nil
BridgeWeapon.attached = nil
BridgeWeapon.lastFight = -9999
BridgeWeapon.body = nil
BridgeWeapon.info = "none"
BridgeWeapon.waitWhy = nil
BridgeWeapon.attachFailed = nil
BridgeWeapon.heldId = nil
BridgeWeapon.lost = nil

local DELAY = 20
local AFTER_FIGHT = 300
local NEAR = 15



local LOST_COUNT, LOST_PAUSE = 3, 3600
local LOST_PAUSE_MAX = 36000
local LOST_KEEP = 3600

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeWeapon] " .. tostring(text)) end end
local function warn(text) print("[BridgeWeapon] " .. tostring(text)) end



local SLOT_ANIM = { back = "Back", ["belt left"] = "BeltLeft", ["belt right"] = "BeltRight",
                    ["holster left"] = "BeltLeft", ["holster right"] = "BeltRight" }
local HAND_ANIM = "TreatMid"

local function isWeapon(item)
    local yes = false
    pcall(function()
        yes = item ~= nil and instanceof(item, "HandWeapon") and item:getFullType() ~= "Base.BareHands"
    end)
    return yes
end

local function inBody(body, item)
    local ok = false
    pcall(function()
        local inv = body:getInventory()
        local c = item:getContainer()
        ok = c == inv or (c ~= nil and c:getOutermostContainer() == inv)
    end)
    return ok
end



function BridgeWeapon.redDrawn(red)
    local item = nil
    pcall(function() item = red:getPrimaryHandItem() end)
    if not isWeapon(item) then return false end
    local rod = false
    pcall(function() rod = ItemTag ~= nil and ItemTag.FISHING_ROD ~= nil and item:hasTag(ItemTag.FISHING_ROD) end)
    return not rod
end



local HAND_PREP = { ISInventoryTransferAction = true, ISEquipWeaponAction = true, ISUnequipAction = true,
                    ISAttachItemHotbar = true, ISDetachItemHotbar = true }











function BridgeWeapon.redIntent(red)
    local intent = nil
    pcall(function()
        local inHand = red:getPrimaryHandItem()
        local q = ISTimedActionQueue.getTimedActionQueue(red)
        for _, a in ipairs(q and q.queue or {}) do
            if type(a) ~= "table" or not HAND_PREP[a.Type] then break end
            if isWeapon(a.item) then
                if a.Type == "ISEquipWeaponAction" then
                    if a.primary ~= false then intent = true end
                elseif (a.Type == "ISUnequipAction" or a.Type == "ISAttachItemHotbar") and a.item == inHand then
                    intent = false
                end
            end
        end
    end)
    return intent
end



function BridgeWeapon.isMelee(item)
    if not isWeapon(item) then return false end
    local ok = false
    pcall(function() ok = not item:isRanged() and item:getCondition() > 0 end)
    return ok
end

function BridgeWeapon.isAssigned(body, item)
    if item == nil or BridgeWeapon.assignedId == nil then return false end
    local yes = false
    pcall(function() yes = item:getID() == BridgeWeapon.assignedId end)
    return yes
end



function BridgeWeapon.assigned(body)
    local id = BridgeWeapon.assignedId
    if id == nil then return nil end
    local found = nil
    pcall(function()
        local items = body:getInventory():getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item ~= nil and item:getID() == id then found = item break end
        end
    end)




    if found == nil and BridgeWeapon.assignedItem ~= nil then
        local held = false
        pcall(function() held = BridgeInventory.queueHolds(BridgeWeapon.assignedItem) end)
        if held then return nil end
    end
    if found == nil or not BridgeWeapon.isMelee(found) then
        BridgeWeapon.assignedId = nil
        log("assignment cleared: " .. (found == nil and "item gone" or "not usable"))
        return nil
    end
    BridgeWeapon.assignedItem = found
    return found
end






function BridgeWeapon.slotFor(body, item)
    local worn = {}
    pcall(function()
        local list = body:getWornItems()
        for i = 0, list:size() - 1 do
            local w = list:getItemByIndex(i)
            if w ~= nil then worn[#worn + 1] = w end
        end
    end)
    return BridgeWeapon.slotIn(worn, item)
end



function BridgeWeapon.slotIn(worn, item)
    local slot, set = nil, nil
    pcall(function()
        local kind = item:getAttachmentType()
        if kind == nil or ISHotbarAttachDefinition == nil then return end
        local defs = {}
        for _, def in ipairs(ISHotbarAttachDefinition) do defs[def.type] = def end
        local types = { "Back" }
        local replacements = {}
        for _, w in ipairs(worn) do
            do
                local provided = nil
                pcall(function() provided = w:getAttachmentsProvided() end)
                if provided ~= nil then
                    for j = 0, provided:size() - 1 do types[#types + 1] = provided:get(j) end
                end
                local rep = nil
                pcall(function() rep = w:getAttachmentReplacement() end)
                if rep ~= nil then
                    for _, rdef in ipairs(ISHotbarAttachDefinition.replacements or {}) do
                        if rdef.type == rep and rdef.replacement ~= nil then
                            for k, v in pairs(rdef.replacement) do replacements[k] = v end
                        end
                    end
                end
            end
        end
        for _, t in ipairs(types) do
            local def = defs[t]
            if def ~= nil and def.attachments ~= nil and def.attachments[kind] ~= nil then
                local s = def.attachments[kind]
                if def.name == "Back" and replacements[kind] ~= nil then s = replacements[kind] end
                if s ~= "null" then slot, set = s, def.animset return end
            end
        end
    end)

    return slot, set
end

local function detach(body)
    local a = BridgeWeapon.attached
    if a == nil then return false end
    pcall(function() body:removeAttachedItem(a.item) end)
    BridgeWeapon.attached = nil
    return true
end


local function attach(body, item)
    local slot, set = BridgeWeapon.slotFor(body, item)
    if slot == nil then return detach(body) end
    local a = BridgeWeapon.attached
    if a ~= nil and a.item == item and a.slot == slot then return false end
    detach(body)
    local ok = pcall(function() body:setAttachedItem(slot, item) end)
    if ok then BridgeWeapon.attached = { slot = slot, item = item, set = set } end
    return true
end

local function refresh(body)
    pcall(function() Bridge.weaponVar(body) end)


    local gesture = false
    pcall(function() gesture = BridgeInventory.gestureRunning() end)
    if gesture then return end
    pcall(function() body:resetModelNextFrame() end)
    pcall(function() BridgeInventory.redress(body) end)
end



local function syncModel(body)
    local item = BridgeWeapon.assigned(body)
    local hand = nil
    pcall(function() hand = body:getPrimaryHandItem() end)
    if item == nil or hand == item then return detach(body) end
    return attach(body, item)
end

local function clearHands(body)
    BridgeWeapon.heldId = nil
    pcall(function()
        local p = body:getPrimaryHandItem()
        body:setPrimaryHandItem(nil)
        if body:getSecondaryHandItem() == p then body:setSecondaryHandItem(nil) end
    end)
end


function BridgeWeapon.draw(body)
    BridgeWeapon.cancelMove(body)
    local item = BridgeWeapon.assigned(body)
    if item == nil then return false end

    if BridgeWeapon.drawPaused(item) then return false end
    local hand = body:getPrimaryHandItem()
    if hand == item then return false end
    if hand ~= nil then clearHands(body) end
    detach(body)
    pcall(function()
        body:setPrimaryHandItem(item)
        if item:isTwoHandWeapon() or item:isRequiresEquippedBothHands() then body:setSecondaryHandItem(item) end
        BridgeWeapon.heldId = item:getID()
        BridgeWeapon.heldAt = Bridge.time
    end)
    BridgeWeapon.info = "drawn " .. tostring(item:getType())
    refresh(body)
    return true
end




function BridgeWeapon.putAway(body)
    BridgeWeapon.cancelMove(body)
    local hand = body:getPrimaryHandItem()
    local changed = false
    if hand ~= nil and isWeapon(hand) then
        clearHands(body)
        BridgeWeapon.info = "put away " .. tostring(hand:getType())
        changed = true
    end
    if syncModel(body) then changed = true end
    if changed then refresh(body) end
    return changed
end








local OWN_KEY = "bridgeOwnPick"
local function ownPick(item)
    local own = false
    pcall(function() own = item:hasModData() and item:getModData()[OWN_KEY] == true end)
    return own
end
local function strength(item)
    local s = 0
    pcall(function() s = (item:getMinDamage() + item:getMaxDamage()) / 2 end)
    return s
end
BridgeWeapon.OWN_KEY = OWN_KEY





local FIST = 0.3
local function ownable(it)
    if not BridgeWeapon.isMelee(it) or strength(it) <= FIST then return false end
    local bad = false
    pcall(function()
        bad = it:getSwingAnim() == "Throw" or it:getMaxRange() > 3 or it:isFavorite()
            or (ItemTag ~= nil and ItemTag.FISHING_ROD ~= nil and it:hasTag(ItemTag.FISHING_ROD))
    end)
    if bad then return false end


    local busy = false
    pcall(function()
        busy = (BridgeInventory.taking ~= nil and BridgeInventory.taking[it] ~= nil)
            or (BridgeInventory.pending ~= nil and BridgeInventory.pending[it:getID()] ~= nil)
            or (BridgeInventory.queueHolds ~= nil and BridgeInventory.queueHolds(it))
    end)
    return not busy
end



function BridgeWeapon.bestOwn(body, mainOnly)
    local best, bestS, bestC = nil, -1, -1
    pcall(function()
        local function walk(c, depth)
            local items = c:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if it ~= nil then
                    if ownable(it) then
                        local st, cond = strength(it), 0
                        pcall(function() cond = it:getCondition() end)
                        if st > bestS or (st == bestS and cond > bestC) then best, bestS, bestC = it, st, cond end
                    end
                    if not mainOnly and depth < 2 and instanceof(it, "InventoryContainer") then walk(it:getInventory(), depth + 1) end
                end
            end
        end
        walk(body:getInventory(), 0)
    end)
    return best
end



function BridgeWeapon.ownChoice(body)


    if Bridge.mp and not Bridge.drivable() then return nil end
    local cur = BridgeWeapon.assigned(body)


    if cur == nil and BridgeWeapon.assignedId ~= nil then return nil end
    if cur ~= nil and not ownPick(cur) then return cur end
    local best = BridgeWeapon.bestOwn(body)


    if best ~= nil then
        local inv0 = body:getInventory()
        local fits, top0 = true, false
        pcall(function() top0 = best:getContainer() == inv0 end)
        if not top0 then pcall(function() fits = inv0:hasRoomFor(BridgeData.owner(), best) ~= false end) end
        if not fits then best = BridgeWeapon.bestOwn(body, true) end
    end
    if best == nil or best == cur then return cur end
    if cur ~= nil and strength(best) <= strength(cur) then return cur end
    local inv = body:getInventory()
    local top = false
    pcall(function() top = best:getContainer() == inv end)
    if not top then
        pcall(function()
            best:getContainer():Remove(best)
            inv:AddItem(best)
        end)
        pcall(function() top = best:getContainer() == inv end)
        if not top then return cur end
    end
    if cur ~= nil then pcall(function() cur:getModData()[OWN_KEY] = nil end) end
    pcall(function() best:getModData()[OWN_KEY] = true end)
    BridgeWeapon.assignedId = best:getID()
    BridgeWeapon.assignedItem = best
    BridgeWeapon.attachFailed = nil
    BridgeWeapon.info = "own choice " .. tostring(best:getType())
    log("her own weapon for the fight (nothing assigned by the player): " .. tostring(best:getType()))
    return best
end


function BridgeWeapon.fight(body)


    local fresh = Bridge.time - (BridgeWeapon.lastFight or -99999) >= AFTER_FIGHT
    if fresh or (BridgeWeapon.assignedId == nil and Bridge.time - (BridgeWeapon.ownTriedAt or -99999) >= 60) then
        BridgeWeapon.ownTriedAt = Bridge.time
        pcall(BridgeWeapon.ownChoice, body)
    end
    BridgeWeapon.lastFight = Bridge.time
    if BridgeWeapon.want ~= true then
        BridgeWeapon.want = true
        BridgeWeapon.changeAt = nil
    end

    local m = BridgeWeapon.move
    if m ~= nil and (m.kind == "away" or m.kind == "stow") then
        if m.connected then
            BridgeWeapon.cancelMove(body)
        else
            BridgeWeapon.move = nil
            pcall(function() if tostring(body:getBumpType()) == m.anim then body:setBumpType("") end end)
        end
    end



    pcall(function()
        if BridgeInventory ~= nil and BridgeInventory.gestureRunning() then BridgeInventory.gestureFlush(body, "fight") end
    end)


    local item = BridgeWeapon.assigned(body)
    if item ~= nil and BridgeWeapon.drawPaused(item) then
        if body:getPrimaryHandItem() ~= item and syncModel(body) then refresh(body) end
        return
    end


    BridgeWeapon.drawMoved(body, true)
end


function BridgeWeapon.isOut(body)
    return isWeapon(body:getPrimaryHandItem())
end




function BridgeWeapon.assign(body, item)
    if not BridgeWeapon.isMelee(item) then return false end

    pcall(function() if item:hasModData() then item:getModData()[OWN_KEY] = nil end end)


    BridgeWeapon.dropOrCancel(body)

    local top = false
    pcall(function() top = item:getContainer() == body:getInventory() end)
    if not top then return false end
    if BridgeWeapon.isAssigned(body, item) then return true end
    local can0, why0 = BridgeWeapon.canMove(body, false)
    if not can0 and not BridgeWeapon.never(why0) then



        BridgeWeapon.assignedId = item:getID()
        BridgeWeapon.attachFailed = nil
        BridgeWeapon.changeAt = Bridge.time
        BridgeWeapon.waitWhy = why0
        BridgeWeapon.info = "assigned " .. tostring(item:getType())
        log("assign waits: " .. tostring(why0))
        return true
    end
    local hand = body:getPrimaryHandItem()


    if hand ~= nil and isWeapon(hand) and BridgeWeapon.want ~= true then clearHands(body) end
    detach(body)
    BridgeWeapon.assignedId = item:getID()
    BridgeWeapon.attachFailed = nil
    BridgeWeapon.changeAt = nil

    local waitWhy = nil
    if BridgeWeapon.want == true then
        local _, why = BridgeWeapon.drawMoved(body, false)
        waitWhy = why
    else

        local slot, set = BridgeWeapon.slotFor(body, item)
        local can, why = BridgeWeapon.canMove(body, false)
        if slot ~= nil and can then
            BridgeWeapon.startMove(body, "attach", item, "WeaponAttach" .. (SLOT_ANIM[set] or "Back"))
        elseif slot ~= nil and not BridgeWeapon.never(why) then
            waitWhy = why
        else
            syncModel(body)
        end
    end
    if waitWhy ~= nil then
        BridgeWeapon.changeAt = Bridge.time
        BridgeWeapon.waitWhy = waitWhy
        log("assign waits: " .. tostring(waitWhy))
    end
    BridgeWeapon.info = "assigned " .. tostring(item:getType())
    refresh(body)
    return true
end


function BridgeWeapon.unassign(body, item)
    if not BridgeWeapon.isAssigned(body, item) then return false end
    BridgeWeapon.dropOrCancel(body)
    BridgeWeapon.assignedId = nil
    BridgeWeapon.changeAt = nil

    local can, why = BridgeWeapon.canMove(body, false)
    if not can and not BridgeWeapon.never(why) then

        BridgeWeapon.changeAt = Bridge.time
        BridgeWeapon.waitWhy = why
        BridgeWeapon.info = "unassigned " .. tostring(item:getType())
        log("unassign waits: " .. tostring(why))
        return true
    end
    if can then
        local inHand = false
        pcall(function() inHand = body:getPrimaryHandItem() == item end)
        local a = BridgeWeapon.attached
        if inHand then
            BridgeWeapon.startMove(body, "stow", item, HAND_ANIM)
            BridgeWeapon.info = "unassigned " .. tostring(item:getType())
            return true
        elseif a ~= nil and a.item == item then
            BridgeWeapon.startMove(body, "detach", item, "WeaponDetach" .. (SLOT_ANIM[a.set] or "Back"))
            BridgeWeapon.info = "unassigned " .. tostring(item:getType())
            return true
        end
    end
    BridgeWeapon.heldId = nil
    pcall(function()
        if body:getPrimaryHandItem() == item then body:setPrimaryHandItem(nil) end
        if body:getSecondaryHandItem() == item then body:setSecondaryHandItem(nil) end
    end)
    detach(body)
    BridgeWeapon.info = "unassigned " .. tostring(item:getType())
    refresh(body)
    return true
end






function BridgeWeapon.dressGuest(b, list)
    local assigned, worn = nil, {}
    for _, rec in ipairs(list) do
        if rec.p == nil then
            if rec.w then
                pcall(function()
                    local it = instanceItem(rec.t)
                    if it ~= nil then worn[#worn + 1] = it end
                end)
            end
            if rec.as and (rec.h or 0) == 0 then assigned = rec end
        end
    end
    if assigned == nil then return nil end
    local item = nil
    pcall(function() item = instanceItem(assigned.t) end)
    if item == nil then return nil end
    local slot = BridgeWeapon.slotIn(worn, item)
    if slot == nil then return nil end
    local ok = pcall(function() b:setAttachedItem(slot, item) end)
    return ok and slot or nil
end


local function cleanAttached(body)
    local a = BridgeWeapon.attached
    if a == nil then return end


    local main = false
    pcall(function() main = a.item:getContainer() == body:getInventory() end)
    if not main or body:getPrimaryHandItem() == a.item then detach(body) refresh(body) end
end


function BridgeWeapon.release(body)
    local a = BridgeWeapon.attached
    local b = body or BridgeWeapon.body
    if a ~= nil and b ~= nil then
        pcall(function() b:removeAttachedItem(a.item) end)
    end
    BridgeWeapon.attached = nil
end


function BridgeWeapon.reset()
    BridgeWeapon.release(nil)
    BridgeWeapon.move = nil
    BridgeWeapon.want = nil
    BridgeWeapon.changeAt = nil
    BridgeWeapon.waitWhy = nil
    BridgeWeapon.walkSince = nil
    BridgeWeapon.freeSince = nil
    BridgeWeapon.attachFailed = nil
    BridgeWeapon.heldId = nil
    BridgeWeapon.lost = nil
    BridgeWeapon.body = nil
end








function BridgeWeapon.checkLost(body)
    local id = BridgeWeapon.heldId
    if id == nil then return end

    local m = BridgeWeapon.move
    if m ~= nil and not m.connected then return end
    local still = false
    pcall(function()
        local hand = body:getPrimaryHandItem()
        still = hand ~= nil and hand:getID() == id
    end)
    if still then return end
    BridgeWeapon.heldId = nil

    local mine = false
    pcall(function() mine = body:getInventory():getItemWithID(id) ~= nil end)
    if not mine then return end




    if Bridge.mp and BridgeBandits ~= nil and BridgeBandits.wanted and BridgeBandits.windowClose(body) then
        local back = false
        pcall(function()
            local item = body:getInventory():getItemWithID(id)
            body:setPrimaryHandItem(item)
            if item:isTwoHandWeapon() or item:isRequiresEquippedBothHands() then body:setSecondaryHandItem(item) end
            back = body:getPrimaryHandItem() == item
        end)
        if back then
            BridgeWeapon.heldId = id
            refresh(body)
            return
        end
    end



    local heldFor = Bridge.time - (BridgeWeapon.heldAt or Bridge.time)
    if BridgeWeapon.lost ~= nil and BridgeWeapon.lost.id == id and heldFor >= LOST_KEEP then BridgeWeapon.lost = nil end
    local l = BridgeWeapon.lost
    if l == nil or l.id ~= id then
        l = { id = id, times = {} }
        BridgeWeapon.lost = l
    end
    local keep = l.times
    keep[#keep + 1] = Bridge.time
    if #keep >= LOST_COUNT and (l.pauseUntil == nil or Bridge.time >= l.pauseUntil) then


        l.pauses = (l.pauses or 0) + 1
        local pause = math.min(LOST_PAUSE * 2 ^ (l.pauses - 1), LOST_PAUSE_MAX)
        l.pauseUntil = Bridge.time + pause
        l.times = {}
        log(string.format("her hands keep being emptied by something else (another mod?): %d times in a row, not drawing for %d s",
            #keep, pause / 60))
    end
end


function BridgeWeapon.drawPaused(item)
    local l = BridgeWeapon.lost
    if l == nil or l.pauseUntil == nil or Bridge.time >= l.pauseUntil then return false end
    local same = false
    pcall(function() same = item ~= nil and item:getID() == l.id end)
    return same
end





















local MOVE_TIME, MOVE_CONNECT = 30, 15
local HAND_TIME, HAND_CONNECT = 42, 21
local CONNECT_VAR = "NotAloneWeaponConnect"
local FREE_BUMPS = { [""] = true, ["nil"] = true, Stand = true, ShiftWeight = true, ChewNails = true, WipeBrow = true,
                     PullAtCollar = true, WipeHead = true }
BridgeWeapon.move = nil

function BridgeWeapon.busy() return BridgeWeapon.move ~= nil end





function BridgeWeapon.canMove(body, inFight, stuck)
    local why = "check failed"
    pcall(function()
        if Bridge.kind ~= "zombie" or Bridge.hiddenSince ~= nil then why = "body" return end
        if Bridge.mp and body:isRemoteZombie() then why = "body" return end
        if not inFight then
            if not stuck and BridgeMove ~= nil and (BridgeMove.pathing or BridgeMove.moving or BridgeMove.steering) then why = "walking" return end


            if BridgeWeapon.redWalking() then why = "player walking" return end
        end
        if BridgeHeal ~= nil and BridgeHeal.active then why = "healing" return end
        if BridgeWash ~= nil and BridgeWash.state ~= "idle" then why = "washing" return end
        if Bridge.pose ~= nil then why = "pose" return end
        if Bridge.mourning ~= nil then why = "mourning" return end

        if BridgeCar ~= nil and BridgeCar.holdsBody() then why = "car" return end


        if BridgeInventory ~= nil and BridgeInventory.gestures ~= nil and #BridgeInventory.gestures > 0
            and (not inFight or BridgeInventory.gestureRunning()) then why = "gesture" return end
        local asn = tostring(body:getActionStateName())
        local walking = asn == "walktoward" or asn == "pathfind"
        if walking and not inFight and not stuck then why = "walking" return end
        if asn ~= "idle" and asn ~= "bumped" and not walking then why = "state " .. asn return end
        local bump = tostring(body:getBumpType())
        if not FREE_BUMPS[bump] then
            if not BridgeWeapon.isWalkBump(bump) then why = "bump " .. bump return end
            if not inFight and not stuck then why = "walking" return end
        end
        why = nil
    end)
    return why == nil, why
end






function BridgeWeapon.redWalking()
    if not Bridge.follow then return false end
    if BridgeMove ~= nil and BridgeMove.redMoving == true then return true end
    local moving = false
    pcall(function()
        local red = BridgeData.owner()
        moving = red ~= nil and red:isPlayerMoving() == true
    end)
    return moving
end



function BridgeWeapon.isWalkBump(bump)
    return string.sub(bump, 1, 6) == "Follow" or bump == "StartMove" or bump == "IdleToWalk" or bump == "IdleToRun"
end


function BridgeWeapon.never(why)
    return why == "body" or why == "check failed"
end




BridgeWeapon.still = BridgeWeapon.still
function BridgeWeapon.stillFor(body)
    local x, y = 0, 0
    pcall(function() x, y = body:getX(), body:getY() end)
    local st = BridgeWeapon.still
    if st == nil or st.body ~= body or math.abs(x - st.x) + math.abs(y - st.y) > 0.05 then
        BridgeWeapon.still = { body = body, x = x, y = y, since = Bridge.time }
        return 0
    end
    return Bridge.time - st.since
end
local STUCK = 120




function BridgeWeapon.stuckWalking(body, since)

    local still = BridgeWeapon.stillFor(body)
    if since == nil or Bridge.time - since < STUCK or still < STUCK then return false end
    return not BridgeWeapon.redWalking()
end

function BridgeWeapon.startMove(body, kind, item, anim)


    BridgeWeapon.body = body
    BridgeWeapon.move = { kind = kind, item = item, anim = anim, start = Bridge.time, connected = false,
                          dur = (anim == HAND_ANIM) and HAND_TIME or MOVE_TIME,
                          connect = (anim == HAND_ANIM) and HAND_CONNECT or MOVE_CONNECT }
    pcall(function() body:setVariable(CONNECT_VAR, false) end)
    pcall(function() if BridgeMove ~= nil and BridgeMove.onPath() then BridgeMove.stopPath(body) end end)
    pcall(function() body:setBumpType(anim) end)
    log("move " .. kind .. " " .. tostring(item:getType()) .. ", " .. anim)
end


local function connectMove(body, m)
    m.connected = true
    pcall(function() body:setVariable(CONNECT_VAR, false) end)
    local item = m.item
    if m.kind == "draw" then

        if BridgeWeapon.assigned(body) == item then


            clearHands(body)
            detach(body)
            pcall(function()
                body:setPrimaryHandItem(item)
                if item:isTwoHandWeapon() or item:isRequiresEquippedBothHands() then body:setSecondaryHandItem(item) end
                BridgeWeapon.heldId = item:getID()
                BridgeWeapon.heldAt = Bridge.time
            end)
            BridgeWeapon.info = "drawn " .. tostring(item:getType())
        end
    elseif m.kind == "away" then
        clearHands(body)
        syncModel(body)
        BridgeWeapon.info = "put away " .. tostring(item:getType())
    elseif m.kind == "attach" then
        syncModel(body)

        local a = BridgeWeapon.attached
        if a == nil or a.item ~= item then
            pcall(function() BridgeWeapon.attachFailed = item:getID() end)
            log("attach failed: " .. tostring(item:getType()))
        end
    elseif m.kind == "detach" then

        local a = BridgeWeapon.attached
        if a ~= nil and a.item == item then detach(body) end
    elseif m.kind == "stow" then
        BridgeWeapon.heldId = nil
        pcall(function()
            if body:getPrimaryHandItem() == item then body:setPrimaryHandItem(nil) end
            if body:getSecondaryHandItem() == item then body:setSecondaryHandItem(nil) end
        end)
    end
    refresh(body)
end




function BridgeWeapon.dropOrCancel(body)
    local m = BridgeWeapon.move
    if m ~= nil and m.kind == "draw" and not m.connected then
        BridgeWeapon.move = nil
        pcall(function() if tostring(body:getBumpType()) == m.anim then body:setBumpType("") end end)
        return
    end
    BridgeWeapon.cancelMove(body)
end


function BridgeWeapon.cancelMove(body)
    local m = BridgeWeapon.move
    if m == nil then return end
    BridgeWeapon.move = nil
    if body ~= nil and not m.connected then connectMove(body, m) end
    pcall(function() if body ~= nil and tostring(body:getBumpType()) == m.anim then body:setBumpType("") end end)
end







function BridgeWeapon.foreignInHands(body)
    if Bridge.mp then return false end
    local hand = nil
    pcall(function() hand = body:getPrimaryHandItem() end)
    if hand == nil then return false end
    local mine = false
    pcall(function() mine = hand:getContainer() == body:getInventory() end)
    if mine then return false end
    local m = BridgeWeapon.move
    if m ~= nil and m.item == hand then
        BridgeWeapon.move = nil
        pcall(function() if tostring(body:getBumpType()) == m.anim then body:setBumpType("") end end)
    end
    clearHands(body)
    syncModel(body)
    refresh(body)
    log("item in her hands is not in her inventory: hands emptied")
    return true
end

function BridgeWeapon.animStep(body)
    if body == BridgeWeapon.body then
        BridgeWeapon.checkLost(body)
        BridgeWeapon.foreignInHands(body)
    end
    local m = BridgeWeapon.move
    if m == nil then return end
    if body ~= BridgeWeapon.body then BridgeWeapon.move = nil return end

    local cut = false
    pcall(function()
        local asn = tostring(body:getActionStateName())
        cut = (BridgeHeal ~= nil and BridgeHeal.active) or (BridgeWash ~= nil and BridgeWash.state ~= "idle")
            or Bridge.pose ~= nil or Bridge.mourning ~= nil
            or (asn ~= "idle" and asn ~= "bumped" and asn ~= "walktoward" and asn ~= "pathfind")
    end)
    if cut then
        log("move cut: " .. m.kind)
        BridgeWeapon.cancelMove(body)
        return
    end
    local age = Bridge.time - m.start
    if not m.connected then
        local mark = false
        pcall(function() mark = body:getVariableBoolean(CONNECT_VAR) end)
        if mark or age >= m.connect then connectMove(body, m) end
    end



    local bump = nil
    pcall(function() bump = tostring(body:getBumpType()) end)
    if age >= m.dur or (m.connected and bump ~= m.anim) then
        BridgeWeapon.move = nil
        pcall(function() if tostring(body:getBumpType()) == m.anim then body:setBumpType("") end end)
        return
    end
    pcall(function() if BridgeMove ~= nil and BridgeMove.onPath() then BridgeMove.stopPath(body) end end)
    pcall(function() if bump ~= m.anim then body:setBumpType(m.anim) end end)
end



function BridgeWeapon.drawMoved(body, inFight, stuck)
    if BridgeWeapon.move ~= nil then return true end
    local item = BridgeWeapon.assigned(body)
    if item == nil then return false end
    if BridgeWeapon.drawPaused(item) then return false, "paused" end
    local hand = nil
    pcall(function() hand = body:getPrimaryHandItem() end)
    if hand == item then return false end
    local can, why = BridgeWeapon.canMove(body, inFight, stuck)
    if not can then
        if inFight or BridgeWeapon.never(why) then return BridgeWeapon.draw(body) end
        return false, why
    end

    local a = BridgeWeapon.attached
    local anim = HAND_ANIM
    if a ~= nil and a.item == item then anim = "WeaponDetach" .. (SLOT_ANIM[a.set] or "Back") end
    BridgeWeapon.startMove(body, "draw", item, anim)
    return true
end



function BridgeWeapon.putAwayMoved(body, stuck)
    if BridgeWeapon.move ~= nil then return true end
    local hand = nil
    pcall(function() hand = body:getPrimaryHandItem() end)
    if hand == nil or not isWeapon(hand) then return BridgeWeapon.putAway(body) end
    local can, why = BridgeWeapon.canMove(body, false, stuck)
    if not can then
        if BridgeWeapon.never(why) then return BridgeWeapon.putAway(body) end
        return false, why
    end
    local anim = HAND_ANIM
    if BridgeWeapon.isAssigned(body, hand) then
        local slot, set = BridgeWeapon.slotFor(body, hand)
        if slot ~= nil then anim = "WeaponAttach" .. (SLOT_ANIM[set] or "Back") end
    end
    BridgeWeapon.startMove(body, "away", hand, anim)
    return true
end






function BridgeWeapon.need(body, want)
    local item = BridgeWeapon.assigned(body)
    local hand = nil
    pcall(function() hand = body:getPrimaryHandItem() end)
    if hand ~= nil and isWeapon(hand) and (hand ~= item or not want) then return "away" end
    local a = BridgeWeapon.attached
    if a ~= nil and a.item ~= item and a.item ~= hand then return "detach" end
    if item == nil then return nil end
    if want then
        if hand ~= item and not BridgeWeapon.drawPaused(item) then return "draw" end
        if hand == item then return nil end


    end
    if (a == nil or a.item ~= item) and hand ~= item then
        local failed = false
        pcall(function() failed = BridgeWeapon.attachFailed == item:getID() end)
        if not failed and BridgeWeapon.slotFor(body, item) ~= nil then return "attach" end
    end
    return nil
end




local function settle(body, want, instant)
    local n = BridgeWeapon.need(body, want)
    if n == nil then return nil end
    if not instant then


        local fighting = false
        pcall(function() fighting = BridgeFight ~= nil and (BridgeFight.target ~= nil or BridgeFight.state == "swing") end)
        if fighting then return "fight" end




        if n == "away" then
            local handsBusy = false
            pcall(function()
                handsBusy = Bridge.pose ~= nil or (BridgeHeal ~= nil and BridgeHeal.active)
                    or (BridgeWash ~= nil and BridgeWash.state ~= "idle")
            end)
            if handsBusy then
                BridgeWeapon.freeSince = nil
                BridgeWeapon.putAway(body)
                return nil
            end
        end
    end
    local can, why = true, nil
    if not instant then can, why = BridgeWeapon.canMove(body, false) end

    local stuck = false
    if not can and why == "walking" then
        BridgeWeapon.walkSince = BridgeWeapon.walkSince or Bridge.time
    else
        BridgeWeapon.walkSince = nil
    end
    if not can and why == "walking" and BridgeWeapon.stuckWalking(body, BridgeWeapon.walkSince) then
        can, why = BridgeWeapon.canMove(body, false, true)
        stuck = can
        if can then log("walking flags, but standing still: moving anyway") end
    end
    if not can and not BridgeWeapon.never(why) then
        BridgeWeapon.freeSince = nil
        return why
    end


    if can and not instant and BridgeWeapon.waitWhy ~= nil then
        BridgeWeapon.freeSince = BridgeWeapon.freeSince or Bridge.time
        if Bridge.time - BridgeWeapon.freeSince < DELAY then return "settling" end
    end
    BridgeWeapon.freeSince = nil
    if instant or not can then
        if n == "draw" then BridgeWeapon.draw(body)
        elseif n == "away" then BridgeWeapon.putAway(body)
        elseif syncModel(body) then refresh(body) end
        return nil
    end
    if n == "draw" then
        BridgeWeapon.drawMoved(body, false, stuck)
    elseif n == "away" then
        BridgeWeapon.putAwayMoved(body, stuck)
    elseif n == "detach" then
        local a = BridgeWeapon.attached
        BridgeWeapon.startMove(body, "detach", a.item, "WeaponDetach" .. (SLOT_ANIM[a.set] or "Back"))
    elseif n == "attach" then
        local item = BridgeWeapon.assigned(body)
        local _, set = BridgeWeapon.slotFor(body, item)
        BridgeWeapon.startMove(body, "attach", item, "WeaponAttach" .. (SLOT_ANIM[set] or "Back"))
    end
    return nil
end



function BridgeWeapon.wantNow(body, red)
    local fighting = (Bridge.time - BridgeWeapon.lastFight) < AFTER_FIGHT
    local near = false
    pcall(function()
        local dx, dy = red:getX() - body:getX(), red:getY() - body:getY()

        local r = (BridgeWeapon.want == true) and NEAR or (NEAR - 2)
        near = dx * dx + dy * dy < r * r
    end)
    local holds = BridgeWeapon.redDrawn(red)
    local drawn = holds
    local intent = BridgeWeapon.redIntent(red)
    if intent ~= nil then drawn = intent end


    BridgeWeapon.wantWhy = "player " .. (holds and "holds a weapon" or "empty-handed")
        .. (intent == true and ", draws one" or (intent == false and ", puts his away" or ""))
        .. (near and "" or ", far") .. (fighting and ", after a fight" or "")
        .. (Bridge.mode == "rest" and ", resting" or "")
    return fighting or (near and Bridge.mode ~= "rest" and drawn)
end


function BridgeWeapon.update(body)
    if Bridge.zombieTicks % 10 ~= 0 then return end
    if BridgeWeapon.body ~= body then
        BridgeWeapon.reset()
        BridgeWeapon.body = body
    end

    BridgeWeapon.stillFor(body)




    local m = BridgeWeapon.move
    if m ~= nil then
        local red0 = BridgeData.owner()
        if red0 == nil or m.connected then return end
        local want0 = BridgeWeapon.wantNow(body, red0)
        local drop = (m.kind == "away" and want0 and BridgeWeapon.isAssigned(body, m.item)) or (m.kind == "draw" and not want0)
        if not drop then return end
        BridgeWeapon.move = nil
        pcall(function() if tostring(body:getBumpType()) == m.anim then body:setBumpType("") end end)
        log("move dropped before the middle: " .. m.kind .. ", player changed his mind")
    end

    if BridgeWeapon.attached == nil and Bridge.zombieTicks % 300 == 0 then
        pcall(function()
            local hand = body:getPrimaryHandItem()
            if hand ~= nil and body:isAttachedItem(hand) then body:removeAttachedItem(hand) end
        end)
    end
    local red = BridgeData.owner()
    if red == nil then return end
    cleanAttached(body)
    BridgeWeapon.checkLost(body)
    local item = BridgeWeapon.assigned(body)
    local hand = body:getPrimaryHandItem()
    local want = BridgeWeapon.wantNow(body, red)


    local first = false
    if want ~= BridgeWeapon.want then
        first = BridgeWeapon.want == nil
        if not first then log("decision " .. (want and "draw" or "away") .. ": " .. tostring(BridgeWeapon.wantWhy)) end
        BridgeWeapon.want = want
        BridgeWeapon.changeAt = first and Bridge.time or (Bridge.time + DELAY)
    elseif BridgeWeapon.changeAt == nil and BridgeWeapon.need(body, want) ~= nil then


        BridgeWeapon.changeAt = Bridge.time + DELAY
    end
    if BridgeWeapon.changeAt ~= nil and Bridge.time >= BridgeWeapon.changeAt then
        local ok, why = pcall(settle, body, want, first)
        if not ok then
            log("change failed: " .. tostring(why))
            BridgeWeapon.changeAt = nil
        elseif why == "settling" then

            BridgeWeapon.changeAt = Bridge.time + 10
        elseif why ~= nil then


            if why ~= BridgeWeapon.waitWhy then
                log("waits: " .. tostring(why) .. " (" .. tostring(BridgeWeapon.need(body, want)) .. ")")
            end
            BridgeWeapon.waitWhy = why
            BridgeWeapon.changeAt = Bridge.time + DELAY
        else
            if BridgeWeapon.waitWhy ~= nil then
                log("wait over: " .. (BridgeWeapon.move ~= nil and ("move " .. BridgeWeapon.move.kind) or "nothing to do"))
            end
            BridgeWeapon.waitWhy = nil
            BridgeWeapon.walkSince = nil
            BridgeWeapon.freeSince = nil
            BridgeWeapon.changeAt = nil
        end
    end
    if BridgeWeapon.move == nil then


        local a = BridgeWeapon.attached
        if a ~= nil and item ~= nil and a.item == item and hand ~= item then
            if syncModel(body) then refresh(body) end
        end
    end
end

log("loaded")

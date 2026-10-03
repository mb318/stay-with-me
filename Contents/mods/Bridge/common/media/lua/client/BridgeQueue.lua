























BridgeQueue = BridgeQueue or {}
BridgeQueue.jobs = BridgeQueue.jobs or {}
BridgeQueue.chain = BridgeQueue.chain or 0

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeQueue] " .. tostring(text)) end end
local function warn(text) print("[BridgeQueue] " .. tostring(text)) end






BridgeQueue.Fake = BridgeQueue.Fake or {}
local Fake = BridgeQueue.Fake
Fake.__index = Fake


function BridgeQueue.fake(maxTime, lua)
    return setmetatable({ currentTime = 0, maxTime = maxTime or 0, delta = 0, started = false, fComplete = false,
                          fStop = false, waitFinished = false, loop = false, lua = lua }, Fake)
end
function Fake:getJobDelta() return self.delta end
function Fake:setJobDelta(d) self.currentTime = (self.maxTime or 0) * d self.delta = d end
function Fake:resetJobDelta() self.delta = 0 self.currentTime = 0 end
function Fake:setTime(t) self.maxTime = t end
function Fake:getTime() return self.maxTime end
function Fake:setCurrentTime(t) self.currentTime = t end
function Fake:getCurrentTime() return self.currentTime end
function Fake:reset() self.currentTime = 0 self.fComplete = false self.fStop = false end
function Fake:forceComplete() self.fComplete = true end
function Fake:forceStop() self.fStop = true end
function Fake:isForceComplete() return self.fComplete end
function Fake:isStarted() return self.started end
function Fake:setWaitForFinished(v) self.waitFinished = v == true end
function Fake:setLoopedAction(v) self.loop = v == true end
function Fake:finished() return not self.waitFinished and self.maxTime ~= -1 and self.currentTime >= self.maxTime end

function Fake:stopTimedActionAnim() end
function Fake:setUseProgressBar() end
function Fake:setActionAnim() end
function Fake:setAnimVariable() end
function Fake:setOverrideHandModels() end
function Fake:setOverrideHandModelsObject() end
function Fake:setOverrideHandModelsString() end
function Fake:overrideWeaponType() end
function Fake:restoreWeaponType() end
function Fake:setBlockMovementEtc() end
function Fake:setAllowedWhileDraggingCorpses() end
function Fake:setCustomRemoteTimedActionSync() end


function Fake:getMetaType()
    local mt = type(self.lua) == "table" and getmetatable(self.lua) or nil
    return (type(mt) == "table" and type(mt.Type) == "string") and mt.Type or ""
end
function Fake:getTable() return self.lua end

function Fake:hasStalled() return false end
function Fake:isPathfinding() return false end
function Fake:setPathfinding() end
function Fake:isAllowedWhileDraggingCorpses() return true end
function Fake:setOverrideAnimation() end
function Fake:PlayLoopedSoundTillComplete() end
function Fake:interruptWaitToStart() end
function Fake:OnAnimEvent() end
function Fake:getDeltaModifiers() end
function Fake:getPrimaryHandMdl() return nil end
function Fake:getSecondaryHandMdl() return nil end
function Fake:getPrimaryHandItem() return nil end
function Fake:getSecondaryHandItem() return nil end


function Fake:advance(mult)
    self.currentTime = self.currentTime + (mult or 1)
    if self.currentTime < 0 then self.currentTime = 0 end
    if self.maxTime == -1 then return end
    if self.maxTime == 0 then self.delta = 0 return end
    self.delta = math.min(1, self.currentTime / self.maxTime)
end




function BridgeQueue.wants(action)
    if BridgeQueue.chain > 0 or type(action) ~= "table" or action.ignoreAction or action.bridgeBack then return false end
    if action.Type ~= "ISInventoryTransferAction" and action.Type ~= "BridgeTransferAction" then return false end
    if action.item == nil or action.srcContainer == nil or action.destContainer == nil then return false end
    if Bridge == nil or Bridge.body == nil or Bridge.kind ~= "zombie" or Bridge.hiddenSince ~= nil then return false end
    local mine = false
    pcall(function() mine = action.character ~= nil and action.character == BridgeData.owner() end)
    if not mine then return false end


    local floorMp = false
    pcall(function() floorMp = isClient() and BridgeInventory.toFloor(action) end)
    if floorMp then return false end
    local anim = nil
    pcall(function() anim = BridgeInventory.herAnimFor(action) end)
    if anim == nil then return false end


    local can, wait = true, true
    pcall(function()
        local c, _, w = BridgeInventory.canGesture(Bridge.body)
        can, wait = c == true, w == true
    end)
    return can or wait
end

local function indexOf(action)
    for i, a in ipairs(BridgeQueue.jobs) do
        if a == action then return i end
    end
    return nil
end
BridgeQueue.indexOf = indexOf


function BridgeQueue.push(action, after)
    action.bridgeOwn = true
    action.bridgeStays = true
    local at = after ~= nil and indexOf(after) or nil
    if at ~= nil then
        table.insert(BridgeQueue.jobs, at + 1, action)
    else
        BridgeQueue.jobs[#BridgeQueue.jobs + 1] = action
    end
    local what = "?"
    pcall(function() what = tostring(action.item:getType()) end)
    log(string.format("queued %s (%d in her queue)", what, #BridgeQueue.jobs))
    return action
end


function BridgeQueue.has(action)
    return indexOf(action) ~= nil
end







local function dropped(a, why)
    if Bridge == nil or not Bridge.mp or BridgeInventory == nil or BridgeInventory.giveDirect == nil then return end
    local item = nil
    pcall(function()
        if a.relayId ~= nil then
            if why == "cancel key" then return end
            item = BridgeData.owner():getInventory():getItemWithIDRecursiv(a.relayId)
        elseif a.bridgeReturn then
            item = a.item
        end
    end)
    if item ~= nil then pcall(BridgeInventory.giveDirect, item, why) end
end
BridgeQueue.dropped = dropped

function BridgeQueue.clear(why)
    local jobs = BridgeQueue.jobs
    if #jobs == 0 then return end
    BridgeQueue.jobs = {}
    for _, a in ipairs(jobs) do
        local started = a.action ~= nil and getmetatable(a.action) == Fake and a.action.started
        if started then
            pcall(function() a:stop() end)
        else
            pcall(function() a:forceCancel() end)
        end
        pcall(function() a.item:setJobDelta(0) end)
        dropped(a, why)
    end
    log("her queue cleared: " .. tostring(why) .. " (" .. #jobs .. ")")
end


function BridgeQueue.tick()
    local a = BridgeQueue.jobs[1]
    if a == nil then return end

    if Bridge == nil or Bridge.body == nil or Bridge.kind ~= "zombie" or Bridge.hiddenSince ~= nil then
        BridgeQueue.clear("no body")
        return
    end
    local f = a.action
    if f == nil or getmetatable(f) ~= Fake then

        local okStart, validStart = pcall(function() return a:isValidStart() end)
        if okStart and validStart == false then
            table.remove(BridgeQueue.jobs, 1)
            log("dropped: not valid to start")
            dropped(a, "not valid to start")
            return
        end
        if a.bridgeRawMax == nil then a.bridgeRawMax = a.maxTime end
        pcall(function() a.maxTime = a:adjustMaxTime(a.maxTime) end)
        a.action = BridgeQueue.fake(a.maxTime, a)
        f = a.action
    end
    local valid = false
    pcall(function() valid = a:isValid() == true end)
    if valid and not f.started then
        local okW, wait = pcall(function() return a:waitToStart() end)
        if not okW then
            valid = false
        elseif wait ~= true then
            f.started = true
            local okS = pcall(function() a:start() end)
            if not okS then valid = false end
        end
    elseif valid and not f:finished() and not f.fComplete and not f.fStop then
        local mult = 1
        pcall(function() mult = getGameTime():getMultiplier() end)

        local waiting = false
        pcall(function() waiting = BridgeInventory.gestureWaitingFor(a) end)
        if waiting then mult = 0 end
        f:advance(mult)
        local okU = pcall(function() a:update() end)
        if not okU then valid = false end
    end
    if not valid or f:finished() or f.fComplete or f.fStop then
        local performed = false
        if f:finished() or f.fComplete then
            pcall(function() a:perform() end)
            performed = true
        end
        local keep = (f:finished() or f.fComplete) and f.loop and not f.fStop and performed
        if not keep then
            if f.started and (f.fStop or not performed) then pcall(function() a:stop() end) end
            local i = indexOf(a)
            if i ~= nil then table.remove(BridgeQueue.jobs, i) end
            if not performed then dropped(a, "stopped") end
        end
        f.fComplete = false
    end
end














local function walkFirst(action)
    local w = BridgeQueue.walk
    if w == nil then return true end
    local mine = false
    pcall(function() mine = action.character ~= nil and action.character == BridgeData.owner() end)
    if not mine then return true end
    if w.failed then return false end
    BridgeQueue.walk = nil
    local ok, r = pcall(BridgeQueue.walkTo, w.container, w.playerNum)
    if ok and r == false then
        BridgeQueue.walk = { failed = true }
        return false
    end
    return true
end

if luautils ~= nil and luautils.walkToContainer ~= nil and not luautils.bridgeWalkWrapped then
    BridgeQueue.walkTo = luautils.walkToContainer
    luautils.walkToContainer = function(container, playerNum, ...)
        local hers = false
        pcall(function()
            hers = Bridge ~= nil and Bridge.body ~= nil and Bridge.kind == "zombie" and Bridge.hiddenSince == nil
                and getSpecificPlayer(playerNum) == BridgeData.owner() and BridgeInventory.inBody(container)
        end)
        if not hers then return BridgeQueue.walkTo(container, playerNum, ...) end
        BridgeQueue.walk = { container = container, playerNum = playerNum }
        return true
    end
    luautils.bridgeWalkWrapped = true
end




local function refers(action, item)
    local found = false
    local function scan(t, depth)
        if found or type(t) ~= "table" or depth > 3 then return end
        for k, v in pairs(t) do
            if v == item then found = true return end
            if type(v) == "table" and getmetatable(v) == nil and k ~= "character" and k ~= "action" then scan(v, depth + 1) end
        end
    end
    pcall(scan, action, 1)
    return found
end









local function pullBack(action, previous)
    if #BridgeQueue.jobs == 0 or type(action) ~= "table" then return end
    local mine = false
    pcall(function() mine = action.character ~= nil and action.character == BridgeData.owner() end)
    if not mine then return end
    local back = {}
    for _, a in ipairs(BridgeQueue.jobs) do
        local started = a.action ~= nil and getmetatable(a.action) == Fake and a.action.started
        if not started and (a == previous or refers(action, a.item)) then back[#back + 1] = a end
    end
    for _, a in ipairs(back) do
        local i = indexOf(a)
        if i ~= nil then table.remove(BridgeQueue.jobs, i) end
        a.bridgeOwn = nil
        a.bridgeBack = true
        if a.bridgeRawMax ~= nil then a.maxTime = a.bridgeRawMax end
        a.action = nil
        local what = "?"
        pcall(function() what = tostring(a.item:getType()) end)
        log("back to player's queue: " .. what .. " (his next action needs it)")
        ISTimedActionQueue.add(a)
    end
end

local function isTransfer(action)
    return type(action) == "table" and (action.Type == "ISInventoryTransferAction" or action.Type == "BridgeTransferAction")
end

if ISTimedActionQueue ~= nil and not ISTimedActionQueue.bridgeQueueWrapped then
    local add = ISTimedActionQueue.add
    ISTimedActionQueue.add = function(action, ...)
        if BridgeQueue.wants(action) then
            BridgeQueue.push(action)
            return ISTimedActionQueue.getTimedActionQueue(action.character)
        end
        if type(action) == "table" then
            pullBack(action)
            if not walkFirst(action) then return ISTimedActionQueue.getTimedActionQueue(action.character) end
        end
        return add(action, ...)
    end
    local addAfter = ISTimedActionQueue.addAfter
    if addAfter ~= nil then
        ISTimedActionQueue.addAfter = function(previousAction, action, ...)
            if BridgeQueue.wants(action) then
                BridgeQueue.push(action, previousAction)
                return ISTimedActionQueue.getTimedActionQueue(action.character), action
            end
            if type(action) == "table" then
                pullBack(action, previousAction)
                if not walkFirst(action) then return ISTimedActionQueue.getTimedActionQueue(action.character), action end
                if BridgeQueue.has(previousAction) then





                    if isTransfer(action) and not action.bridgeBack then
                        BridgeQueue.push(action, previousAction)
                        return ISTimedActionQueue.getTimedActionQueue(action.character), action
                    end
                    return ISTimedActionQueue.add(action), action
                end
            end
            return addAfter(previousAction, action, ...)
        end
    end

    local getUp = ISTimedActionQueue.addGetUpAndThen
    if getUp ~= nil then
        ISTimedActionQueue.addGetUpAndThen = function(character, action, ...)
            if BridgeQueue.wants(action) then return BridgeQueue.push(action) end
            if type(action) == "table" then
                pullBack(action)
                if not walkFirst(action) then return end
            end
            return getUp(character, action, ...)
        end
    end
    ISTimedActionQueue.bridgeQueueWrapped = true
end


if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.transferIfNeeded ~= nil
    and not ISInventoryPaneContextMenu.bridgeChainWrapped then
    local transferIfNeeded = ISInventoryPaneContextMenu.transferIfNeeded
    ISInventoryPaneContextMenu.transferIfNeeded = function(...)
        BridgeQueue.chain = BridgeQueue.chain + 1
        local ok, r1, r2 = pcall(transferIfNeeded, ...)
        BridgeQueue.chain = math.max(0, BridgeQueue.chain - 1)
        if not ok then error(r1) end
        return r1, r2
    end
    ISInventoryPaneContextMenu.bridgeChainWrapped = true
end


if ISBaseTimedAction ~= nil and not ISBaseTimedAction.bridgeQueueWrapped then
    local perform = ISBaseTimedAction.perform
    ISBaseTimedAction.perform = function(self, ...)
        if type(self) == "table" and self.bridgeOwn then
            pcall(function() self.character:setIsFarming(false) end)
            return
        end
        return perform(self, ...)
    end
    local stop = ISBaseTimedAction.stop
    ISBaseTimedAction.stop = function(self, ...)
        if type(self) == "table" and self.bridgeOwn then
            pcall(function() self.character:setIsFarming(false) end)

            local i = indexOf(self)
            if i ~= nil then table.remove(BridgeQueue.jobs, i) end
            BridgeQueue.clear("stopped")
            return
        end
        return stop(self, ...)
    end
    ISBaseTimedAction.bridgeQueueWrapped = true
end






if Events ~= nil and Events.OnKeyStartPressed ~= nil and not BridgeQueue.cancelAdded then
    BridgeQueue.cancelAdded = true
    Events.OnKeyStartPressed.Add(function(key)
        if #BridgeQueue.jobs == 0 then return end
        pcall(function()
            if not getCore():isKey("CancelAction", key) then return end
            if MainScreen == nil or MainScreen.instance == nil or not MainScreen.instance.inGame then return end
            if MainScreen.instance:getIsVisible() then return end
            if getCell() ~= nil and getCell():getDrag(0) ~= nil then return end
            BridgeQueue.clear("cancel key")
            GameKeyboard.eatKeyPress(key)
        end)
    end)
end

if Events ~= nil and Events.OnTick ~= nil and not BridgeQueue.ticking then
    BridgeQueue.ticking = true
    Events.OnTick.Add(function()

        BridgeQueue.walk = nil
        if #BridgeQueue.jobs == 0 then return end
        local paused = false
        if isGamePaused ~= nil then pcall(function() paused = isGamePaused() end) end
        if paused then return end
        local ok, err = pcall(BridgeQueue.tick)
        if not ok then
            warn("tick error: " .. tostring(err))
            BridgeQueue.clear("error")
        end
    end)
end

log("loaded")

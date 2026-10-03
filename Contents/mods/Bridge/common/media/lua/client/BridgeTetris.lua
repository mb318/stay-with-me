
































BridgeTetris = BridgeTetris or {}

local KEY = "StayWithMeCompanion"
BridgeTetris.KEY = KEY
BridgeTetris.GRID_W = 8
BridgeTetris.GRID_H = 6

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeTetris] " .. tostring(text)) end end
local function warn(text) print("[BridgeTetris] " .. tostring(text)) end
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

local function logKey(key, make)
    if logged[key] then return end
    logged[key] = true
    local ok, text = pcall(make)
    log(ok and text or key)
end

local function herBody()
    if Bridge == nil or Bridge.alive == nil or not Bridge.alive() or Bridge.kind ~= "zombie" then return nil end
    return Bridge.body
end



local cache = { tick = nil, body = nil, alive = nil, inv = nil }
local function refresh()
    local tick = Bridge ~= nil and Bridge.tick or nil
    local b0 = Bridge ~= nil and Bridge.body or nil
    if tick == nil or tick ~= cache.tick or b0 ~= cache.body then
        cache.tick, cache.body, cache.alive, cache.inv = tick, b0, nil, nil
        local b = herBody()
        if b ~= nil then
            cache.alive = b
            pcall(function() cache.inv = b:getInventory() end)
        end
    end
end
local function herInv()
    refresh()
    return cache.inv
end
local function herCachedBody()
    refresh()
    return cache.alive
end


function BridgeTetris.isHerMain(container)
    if container == nil then return false end
    local inv = herInv()
    return inv ~= nil and container == inv
end


function BridgeTetris.isHerOwn(container)
    if container == nil then return false end
    local inv = herInv()
    if inv == nil then return false end
    if container == inv then return true end
    local yes = false
    pcall(function() yes = container:getOutermostContainer() == inv end)
    return yes
end


local function isWornBag(item)
    local b = herCachedBody()
    if b == nil or item == nil then return false end
    local yes = false
    pcall(function() yes = item:IsInventoryContainer() and b:isEquippedClothing(item) end)
    return yes
end


function BridgeTetris.definition()
    return {
        gridDefinitions = { {
            size = { width = BridgeTetris.GRID_W, height = BridgeTetris.GRID_H },
            position = { x = 0, y = 0 },
        } },
        isFragile = true,
    }
end

local function tetrisLoaded()
    return TetrisContainerData ~= nil and TetrisEvents ~= nil
end

local function wrapKey()
    local compat = require("InventoryTetris/TetrisModCompatibility")
    if type(compat) ~= "table" or compat.getModContainerKey == nil then return false end
    if compat.bridgeWrapped then return true end
    local getKey = compat.getModContainerKey
    compat.getModContainerKey = function(container, ...)
        if BridgeTetris.isHerMain(container) then
            logKey("key", function() return "her grid key served: " .. KEY end)
            return KEY
        end
        return getKey(container, ...)
    end
    compat.bridgeWrapped = true
    return true
end

local function registerDefinition()
    local data = TetrisContainerData
    if data == nil or data.registerContainerDefinitions == nil then return false end
    data.registerContainerDefinitions({ [KEY] = BridgeTetris.definition() })


    if type(data._containerDefinitions) == "table" and data._containerDefinitions[KEY] == nil then
        data._containerDefinitions[KEY] = BridgeTetris.definition()
    end
    return true
end

local function wrapContainerGrid()
    local ICG = require("InventoryTetris/Model/ItemContainerGrid")
    if type(ICG) ~= "table" or ICG.bridgeWrapped then return type(ICG) == "table" end

    local isItemValid = ICG._isItemValid
    if isItemValid ~= nil then
        ICG._isItemValid = function(self, item, ...)
            if BridgeTetris.isHerMain(self.inventory) and isWornBag(item) then
                logKey("wornbag", function() return "worn bag not in her grid: " .. item:getFullType() end)
                return false
            end
            return isItemValid(self, item, ...)
        end
    end

    local canAddItem = ICG.canAddItem
    if canAddItem ~= nil then
        ICG.canAddItem = function(self, item, ...)
            if not BridgeTetris.isHerMain(self.inventory) then return canAddItem(self, item, ...) end
            local allowed = self:isItemAllowed(item)
            if allowed and not logged["overflow"] and not canAddItem(self, item, ...) then
                logKey("overflow", function() return "no free cell in her grid for " .. item:getFullType() .. ": goes to the overflow list" end)
            end
            return allowed
        end
    end


    local validate = ICG.validateCapacityRestrictions
    if validate ~= nil then
        ICG.validateCapacityRestrictions = function(self, item, container, playerObj, ...)
            if BridgeTetris.isHerMain(container) and BridgeInventory ~= nil and BridgeInventory.roomVerdict ~= nil then
                local inside = false
                pcall(function() inside = item:getContainer() == container end)
                local strict = false
                pcall(function() strict = SandboxVars.InventoryTetris.EnforceCarryWeight or isClient() end)
                if not inside and strict then
                    local verdict = nil
                    pcall(function() verdict = BridgeInventory.roomVerdict(container, playerObj, item) end)
                    if verdict ~= nil then
                        if not verdict then logKey("room", function() return "room check: no room for " .. item:getFullType() end) end
                        return verdict
                    end
                end
            end
            return validate(self, item, container, playerObj, ...)
        end
    end
    ICG.bridgeWrapped = true
    return true
end

local function wrapSearch()
    local IG = require("InventoryTetris/Model/ItemGrid")
    if type(IG) ~= "table" or IG.isUnsearched == nil then return false end
    if IG.bridgeWrapped then return true end
    local isUnsearched = IG.isUnsearched
    IG.isUnsearched = function(self, ...)
        if not isUnsearched(self, ...) then return false end
        return not BridgeTetris.isHerOwn(self.inventory)
    end
    IG.bridgeWrapped = true
    return true
end

local BASIC_INV_TEXTURE = nil

local function wrapTitle()
    local UI = require("InventoryTetris/UI/Container/ItemGridContainerUI")
    if type(UI) ~= "table" or UI.getInventoryName == nil then return false end
    if rawget(UI, "bridgeWrapped") then return true end
    local getInventoryName = UI.getInventoryName
    UI.getInventoryName = function(self, inventory, ...)
        if BridgeTetris.isHerMain(inventory) then
            local name = nil
            pcall(function() name = Bridge.companionName() end)
            if name ~= nil and name ~= "" then return name end
        end
        return getInventoryName(self, inventory, ...)
    end
    local updateContainerTexture = UI.updateContainerTexture
    if updateContainerTexture ~= nil then


        UI.updateContainerTexture = function(self, container, ...)
            if BridgeTetris.isHerMain(container) then
                BASIC_INV_TEXTURE = BASIC_INV_TEXTURE or getTexture("media/ui/Icon_InventoryBasic.png")
                if BASIC_INV_TEXTURE ~= nil then
                    self.invTexture = BASIC_INV_TEXTURE
                    return
                end
            end
            return updateContainerTexture(self, container, ...)
        end
    end
    UI.bridgeWrapped = true
    return true
end





local function wrapWeight()
    local GCI = require("InventoryTetris/UI/Container/GridContainerInfo")
    if type(GCI) ~= "table" or GCI.prerender == nil then return false end
    if rawget(GCI, "bridgeWrapped") then return true end
    local prerender = GCI.prerender
    GCI.prerender = function(self, ...)
        pcall(function()
            local ui = self.containerUi
            if ui == nil or not BridgeTetris.isHerMain(ui.inventory) then return end
            local b = herBody()
            local theirs = round(ui.inventory:getCapacityWeight(), 1)
            local ours = round(BridgeInventory.mainLoad(b), 1)



            local cap = BridgeInventory.capacity or 15
            pcall(function() cap = ui.inventory:getEffectiveCapacity(ui.player) end)
            self.lastWeight = theirs
            self.weightText = ours .. " / " .. cap
        end)
        return prerender(self, ...)
    end
    GCI.bridgeWrapped = true
    return true
end




local markTex = nil
local hotTex = nil
BridgeTetris.marksDrawn = 0
local Marks = {}
function Marks.call(eventData, drawingContext, renderInstructions, instructionCount, playerObj)
    if drawingContext == nil then return end

    local inv = drawingContext.grid ~= nil and drawingContext.grid.inventory or drawingContext.inventory
    if inv == nil or not BridgeTetris.isHerMain(inv) then return end
    local b = herCachedBody()
    local jo = drawingContext.javaObject
    if b == nil or jo == nil then return end
    markTex = markTex or getTexture("media/ui/icon.png")
    hotTex = hotTex or getTexture("media/ui/iconInHotbar.png")
    for r = 1, instructionCount do
        local ins = renderInstructions[r]
        if ins ~= nil and not ins[9] then
            local item = ins[2]
            local tex = nil
            if item ~= nil then
                if b:isEquipped(item) then
                    tex = markTex
                elseif BridgeWeapon ~= nil and BridgeWeapon.isAssigned(b, item) then
                    tex = hotTex
                end
            end
            if tex ~= nil then
                jo:DrawTexture(tex, ins[3] + 2, ins[4] + 2, 1)
                BridgeTetris.marksDrawn = BridgeTetris.marksDrawn + 1
            end
        end
    end
end
BridgeTetris.Marks = Marks

local function addMarks()
    if TetrisEvents == nil or TetrisEvents.OnPostRenderGrid == nil then return false end
    if BridgeTetris.marksAdded then return true end
    TetrisEvents.OnPostRenderGrid:add({ call = function(...)
        local ok, err = pcall(Marks.call, ...)
        if not ok then warnOnce("marks failed: " .. tostring(err)) end
    end })
    BridgeTetris.marksAdded = true
    return true
end





local function wrapRelayTarget()
    local A = ISInventoryTransferAction
    if A == nil or A.setTetrisTarget == nil then return false end
    if A.bridgeTargetWrapped then return true end
    local setTetrisTarget = A.setTetrisTarget
    A.setTetrisTarget = function(self, ...)
        if self.bridgeRelay ~= nil or self.finalDest ~= nil or self.bridgeDir ~= nil then
            logOnce("grid cell not used for her relayed transfer: placed automatically")
            return
        end
        return setTetrisTarget(self, ...)
    end
    A.bridgeTargetWrapped = true
    return true
end







local function wrapRelayRules()
    local A = ISInventoryTransferAction
    if A == nil or A.validateTetrisRules == nil then return false end
    if rawget(A, "bridgeRulesWrapped") then return true end
    local validateTetrisRules = A.validateTetrisRules
    A.validateTetrisRules = function(self, ...)
        local relay = self.bridgeRelay
        if relay ~= nil and relay.dest ~= nil then
            local fits = true
            pcall(function() fits = relay.dest:hasRoomFor(self.character, self.item) ~= false end)
            if not fits then logKey("relayroom", function() return "relay to her: no room at her for " .. self.item:getFullType() end) end
            return fits
        end
        return validateTetrisRules(self, ...)
    end
    A.bridgeRulesWrapped = true
    return true
end





local function wrapTakeRules()
    local T = BridgeTransferAction
    if T == nil or T.isValid == nil then return false end
    if rawget(T, "bridgeTetrisWrapped") then return true end
    local isValid = T.isValid
    T.isValid = function(self, ...)
        local ok = isValid(self, ...)
        if ok and self.bridgeDir == "take" and self.enforceTetrisRules and not self.started and not self.sent
            and self.validateTetrisRules ~= nil then
            local fits = true
            pcall(function() fits = self:validateTetrisRules() ~= false end)
            if not fits then
                logKey("takeroom", function() return "take from her: no free cell in player's grid for " .. self.item:getFullType() end)
                return false
            end
        end
        return ok
    end
    T.bridgeTetrisWrapped = true
    return true
end



function BridgeTetris.install()
    if BridgeTetris.installed then return true end
    if not tetrisLoaded() then
        logOnce("Inventory Tetris not active")
        return false
    end
    local done, failed = {}, {}

    for _, step in ipairs({ { "definition", registerDefinition }, { "key", wrapKey }, { "grid", wrapContainerGrid },
                            { "search", wrapSearch }, { "title", wrapTitle }, { "weight", wrapWeight },
                            { "marks", addMarks }, { "relay", wrapRelayTarget },
                            { "relayrules", wrapRelayRules }, { "take", wrapTakeRules } }) do
        local ok, res = pcall(step[2])
        if ok and res then done[#done + 1] = step[1] else failed[#failed + 1] = step[1] .. (ok and "" or (": " .. tostring(res))) end
    end
    BridgeTetris.installed = true
    log(string.format("Inventory Tetris: her grid %dx%d (%s), hooks: %s%s", BridgeTetris.GRID_W, BridgeTetris.GRID_H, KEY,
        table.concat(done, ","), #failed > 0 and ("; failed: " .. table.concat(failed, ", ")) or ""))
    return true
end

Events.OnGameStart.Add(function() pcall(BridgeTetris.install) end)

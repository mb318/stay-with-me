








BridgeCare = BridgeCare or {}


BridgeCare.SYNC = {
    bandage = 0xc001966b8e, unbandage = 0xc001966b8e, stitch = 0x00570188, disinfect = 0x00608200,
    glass = 0x00480000, bullet = 0x40460108, burn = 0x380400000, splint = 0x430000000,
}

BridgeCare.PARTS = 17
BridgeCare.USE = 0.15

local function clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end


local function itemType(s)
    if type(s) ~= "string" or #s > 64 then return nil end
    if string.match(s, "^[%w_]+%.[%w_]+$") == nil then return nil end
    return s
end





local SPLINTS = { ["Base.Splint"] = true, ["Base.Plank"] = true, ["Base.TreeBranch"] = true, ["Base.TreeBranch2"] = true,
    ["Base.WoodenStick"] = true, ["Base.WoodenStick2"] = true }
function BridgeCare.bandageType(t)
    t = itemType(t)
    if t == nil then return nil end
    local ok = false
    pcall(function()
        local si = ScriptManager.instance:getItem(t)
        ok = si ~= nil and si:isCanBandage() == true
    end)
    return ok and t or nil
end
function BridgeCare.splintType(t)
    t = itemType(t)
    if t == nil or not SPLINTS[t] then return nil end
    return t
end


function BridgeCare.part(player, index)
    local found = nil
    pcall(function()
        local parts = player:getBodyDamage():getBodyParts()
        local p = parts:get(index)
        if p ~= nil and p:getIndex() == index then found = p return end
        for i = 0, parts:size() - 1 do
            local q = parts:get(i)
            if q:getIndex() == index then found = q return end
        end
    end)
    return found
end




function BridgeCare.apply(player, change)
    if type(change) ~= "table" then return nil, "no change" end
    local kind = change.kind
    if BridgeCare.SYNC[kind] == nil then return nil, "unknown kind" end
    local index = math.floor(clamp(change.part, -1, BridgeCare.PARTS))
    if index < 0 or index >= BridgeCare.PARTS then return nil, "bad part" end
    local p = BridgeCare.part(player, index)
    if p == nil then return nil, "no part" end
    local bd = player:getBodyDamage()
    if kind == "unbandage" then
        bd:SetBandaged(index, false, 0, false, nil)
    elseif kind == "glass" then
        p:setHaveGlass(false)
    elseif kind == "bullet" then
        p:setHaveBullet(false, math.floor(clamp(change.level, 0, 10)))
    elseif kind == "burn" then
        p:setNeedBurnWash(false)
    elseif kind == "stitch" then
        p:setStitched(true)
        p:setStitchTime(clamp(change.stitchTime, 0, 30))
    elseif kind == "disinfect" then
        p:setAlcoholLevel(p:getAlcoholLevel() + clamp(change.alcohol, 0, 10))
    elseif kind == "splint" then
        p:setSplint(true, clamp(change.factor, 0, 5))
        local t = BridgeCare.splintType(change.splintItem)
        if t ~= nil then p:setSplintItem(t) end
    elseif kind == "bandage" then
        local t = BridgeCare.bandageType(change.bandageType)
        if t == nil then return nil, "bad bandage type" end
        bd:SetBandaged(index, true, clamp(change.life, 0, 30), change.alcoholic == true, t)

        if change.infected == true then pcall(function() p:SetInfected(true) end) end
    end
    return p, nil
end









function BridgeCare.returnBandage(inv, p)
    local item = nil
    pcall(function()
        local t = p:getBandageType()
        if t == nil or t == "" or inv == nil then return end
        item = instanceItem(t)
        if item == nil then return end
        inv:AddItem(item)
        local reusable = false
        pcall(function() reusable = ItemTag ~= nil and item:hasTag(ItemTag.REUSABLE_BANDAGE) end)
        if p:getBandageLife() <= 0 and not reusable then item:Use() end
    end)
    return item
end



function BridgeCare.fluidAlcohol(item)
    local power = nil
    pcall(function()
        if ComponentType == nil or not item:hasComponent(ComponentType.FluidContainer) then return end
        power = 0
        local fc = item:getFluidContainer()
        local amount = fc:getAmount()
        if amount <= BridgeCare.USE then return end
        local alcohol = fc:getProperties():getAlcohol()
        if alcohol / amount + 0.001 >= 0.4 then power = 4 * alcohol / amount end
    end)
    return power
end


function BridgeCare.fluidUses(item)
    local n = 0
    pcall(function()
        local amount = item:getFluidContainer():getAmount()
        if amount > BridgeCare.USE then n = math.ceil((amount - BridgeCare.USE) / BridgeCare.USE - 0.000001) end
    end)
    return n
end




function BridgeCare.consume(item, sync)
    if item == nil then return false end
    local done = false
    pcall(function()
        if BridgeCare.fluidAlcohol(item) ~= nil then
            local fc = item:getFluidContainer()
            fc:adjustAmount(math.max(0, fc:getAmount() - BridgeCare.USE))
            if sync then pcall(function() sendItemStats(item) end) end
            done = true
            return
        end
        local drain = false
        pcall(function() drain = item:IsDrainable() end)
        if drain then
            if sync then item:UseAndSync() else item:Use() end
            done = true
            return
        end
        local c = item:getContainer()
        if c ~= nil then
            c:Remove(item)
            if sync then pcall(function() sendRemoveItemFromContainer(c, item) end) end
            done = true
        end
    end)
    return done
end

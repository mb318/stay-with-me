








BridgeFarm = BridgeFarm or {}
BridgeFarm.saved = 0

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeFarm] " .. tostring(text)) end end

local function companion(z)
    local ours = false
    pcall(function()
        local md = z:getModData()
        ours = md ~= nil and md.notAloneBody == true
    end)
    if ours then return true end
    pcall(function() ours = z:getVariableBoolean("NotAloneBody") == true end)
    if ours then return true end
    pcall(function() ours = BridgeServer ~= nil and BridgeServer.isCompanionBody ~= nil and BridgeServer.isCompanionBody(z) end)
    return ours == true
end



function BridgeFarm.onlyCompanion(x, y, z)
    local cell = getCell()
    if cell == nil then return false end
    local sq = cell:getGridSquare(x, y, z)
    if sq == nil then return false end
    local car = false
    pcall(function() car = sq:isVehicleIntersectingCrops() end)
    if car then return false end
    local hers, other = false, false
    for dx = -1, 1 do
        for dy = -1, 1 do
            local s = cell:getGridSquare(x + dx, y + dy, z)
            local list = nil
            if s ~= nil then pcall(function() list = s:getMovingObjects() end) end
            if list ~= nil then
                for i = 0, list:size() - 1 do
                    local o = list:get(i)
                    if instanceof(o, "IsoZombie") then
                        if companion(o) then hers = true
                        elseif dx == 0 and dy == 0 then other = true end
                    end
                end
            end
        end
    end
    return hers and not other
end

function BridgeFarm.install()
    local cmds = SFarmingSystemCommands
    if cmds == nil or type(cmds.destroy) ~= "function" then return false end
    if cmds.destroy == BridgeFarm.wrapped then return true end
    local original = cmds.destroy
    BridgeFarm.wrapped = function(player, args)
        local skip = false
        pcall(function()
            skip = args ~= nil and BridgeFarm.onlyCompanion(tonumber(args.x), tonumber(args.y), tonumber(args.z))
        end)
        if skip then
            BridgeFarm.saved = BridgeFarm.saved + 1
            log(string.format("crop kept under companion at %s,%s,%s", tostring(args.x), tostring(args.y), tostring(args.z)))
            return
        end
        return original(player, args)
    end
    cmds.destroy = BridgeFarm.wrapped
    return true
end

pcall(BridgeFarm.install)
Events.OnGameStart.Add(function() pcall(BridgeFarm.install) end)
Events.OnServerStarted.Add(function() pcall(BridgeFarm.install) end)

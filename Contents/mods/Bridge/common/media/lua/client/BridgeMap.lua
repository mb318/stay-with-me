











BridgeMap = BridgeMap or {}
BridgeMap.COLOR = { 0.95, 0.45, 0.70 }


function BridgeMap.where()
    if Bridge == nil or BridgeData == nil then return nil end
    if Bridge.kind == "zombie" and Bridge.body ~= nil and Bridge.alive() then
        local x, y = nil, nil
        pcall(function() x, y = Bridge.body:getX(), Bridge.body:getY() end)
        if x ~= nil then return x, y end
    end
    local st = Bridge.store
    if st ~= nil and BridgeData.wants(st) and BridgeData.modeOf(st) ~= "follow"
        and tonumber(st.waitX) ~= nil and tonumber(st.waitY) ~= nil then
        return tonumber(st.waitX), tonumber(st.waitY)
    end
    return nil
end


function BridgeMap.draw(ui)
    if ui == nil or ui.mapAPI == nil then return end
    local x, y = BridgeMap.where()
    if x == nil then return end
    local api = ui.mapAPI
    local players = true
    pcall(function() players = api:getBoolean("Players") end)
    if players == false then return end
    local sx, sy = nil, nil
    pcall(function() sx, sy = api:worldToUIX(x, y), api:worldToUIY(x, y) end)
    if sx == nil or sy == nil then return end
    sx, sy = math.floor(sx), math.floor(sy)

    if sx < 0 or sy < 0 or sx > ui:getWidth() or sy > ui:getHeight() then return end
    local c = BridgeMap.COLOR
    ui:drawRect(sx - 3, sy - 3, 6, 6, 1, c[1], c[2], c[3])
    local name = BridgeData.nameOf(Bridge.store)

    if not BridgeData.overheadOk(name) then name = BridgeData.DEFAULT_NAME end
    local tm = getTextManager()
    local tw, fh = 0, 14
    pcall(function() tw = tm:MeasureStringX(UIFont.Small, name) end)
    pcall(function() fh = tm:getFontHeight(UIFont.Small) end)
    local w, h = tw + 16, math.ceil(fh * 1.25)
    ui:drawRect(sx - w / 2, sy + 4, w, h, 0.5, 0.5, 0.5, 0.5)
    ui:drawTextCentre(name, sx, sy + 4 + (h - fh) / 2, c[1], c[2], c[3], 1, UIFont.Small)
end



local function wrap(class, method)
    if class == nil or type(class[method]) ~= "function" then return false end
    local flag = "bridgeMapWrapped_" .. method
    if rawget(class, flag) then return true end
    local orig = class[method]
    class[method] = function(self, ...)
        local r = orig(self, ...)
        pcall(BridgeMap.draw, self)
        return r
    end
    class[flag] = true
    return true
end

function BridgeMap.install()
    local a = wrap(ISWorldMap, "prerender")
    local b = wrap(ISMiniMapInner, "prerender")
    return a, b
end

local worldOk, miniOk = BridgeMap.install()
Events.OnGameStart.Add(function() BridgeMap.install() end)
if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeMap] loaded, world map " .. tostring(worldOk) .. ", minimap " .. tostring(miniOk)) end

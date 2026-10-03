







BridgeName = BridgeName or {}
BridgeName.enabled = true

BridgeName.saidAt = BridgeName.saidAt or {}

local SPEECH_MS = 5000




function BridgeName.spoke(z)
    if z ~= nil then BridgeName.saidAt[z] = getTimestampMs() end
end

local function drawOne(tm, pn, z, text)
    if z:isInvisible() then return end

    if z:getAlpha(pn) < 0.1 then return end


    local said = BridgeName.saidAt[z]
    if said ~= nil then
        if getTimestampMs() - said < SPEECH_MS then return end
        BridgeName.saidAt[z] = nil
    end
    local core = getCore()
    local zoom = core:getZoom(pn)
    local lift = 128 * Core.getTileScale() / 2 / zoom
    local x = isoToScreenX(pn, z:getX(), z:getY(), z:getZ())
    local y = isoToScreenY(pn, z:getX(), z:getY(), z:getZ()) - lift - tm:getFontHeight(UIFont.Small)

    tm:DrawStringCentre(UIFont.Small, x - 1, y, text, 0, 0, 0, 0.8)
    tm:DrawStringCentre(UIFont.Small, x + 1, y, text, 0, 0, 0, 0.8)
    tm:DrawStringCentre(UIFont.Small, x, y - 1, text, 0, 0, 0, 0.8)
    tm:DrawStringCentre(UIFont.Small, x, y + 1, text, 0, 0, 0, 0.8)
    tm:DrawStringCentre(UIFont.Small, x, y, text, 1, 1, 1, 1)
end

local function draw()
    if not BridgeName.enabled or not isClient() or Bridge == nil or Bridge.bodiesSeen == nil then return end
    local player = BridgeData.owner()
    if player == nil then return end
    local pn = player:getPlayerNum()
    local tm = getTextManager()
    local mine = Bridge.body
    for z, info in pairs(Bridge.bodiesSeen()) do

        if not (z == mine and Bridge.hiddenSince ~= nil) then
            pcall(drawOne, tm, pn, z, BridgeData.nameOf(info.rec))
        end
    end
end

Events.OnPreUIDraw.Add(draw)
if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeName] loaded") end

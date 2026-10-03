
















BridgeProgress = BridgeProgress or {}
BridgeProgress.value = 0
BridgeProgress.seenAt = nil
BridgeProgress.HOLD_MS = 200

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeProgress] " .. tostring(text)) end end
local function warn(text) print("[BridgeProgress] " .. tostring(text)) end
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

local bar = nil
local bg, fg = nil, nil

local function body()
    if Bridge == nil or Bridge.alive == nil or not Bridge.alive() then return nil end
    return Bridge.body
end

local function now()
    local t = 0
    pcall(function() t = getTimestampMs() end)
    return t
end

local function visibleNow()
    if BridgeProgress.seenAt == nil or now() - BridgeProgress.seenAt > BridgeProgress.HOLD_MS then return false end
    local on = true
    pcall(function() on = getCore():isOptionProgressBar() end)
    return on and body() ~= nil
end

local function create()
    if bar ~= nil or ISUIElement == nil then return bar end
    bg = bg or getTexture("BuildBar_Bkg")
    fg = fg or getTexture("BuildBar_Bar")
    if bg == nil or fg == nil then
        logOnce("progress textures not found")
        return nil
    end
    bar = ISUIElement:new(0, 0, bg:getWidth(), bg:getHeight())
    bar:initialise()
    bar.anchorLeft, bar.anchorTop = true, true
    bar.onMouseDown = function() return false end
    bar.onMouseUp = function() return false end
    bar.onRightMouseDown = function() return false end
    bar.onRightMouseUp = function() return false end
    bar.prerender = function(self)
        if not visibleNow() then
            self:setVisible(false)
            return
        end
        local b = body()
        local scale = 1
        pcall(function() scale = getCore():getOptionActionProgressBarSize() end)
        local w, h = bg:getWidth() * scale, bg:getHeight() * scale
        local ok, sx, sy = pcall(function()
            local x = isoToScreenX(0, b:getX(), b:getY(), b:getZ())
            local y = isoToScreenY(0, b:getX(), b:getY(), b:getZ())
            local zoom = getCore():getZoom(0)

            local tile = Core.getTileScale()
            y = y - (128 / math.floor(2 / tile)) / zoom
            return x - w / 2, y - h
        end)
        if not ok then return end
        self.barScale = scale
        self:setX(sx)
        self:setY(sy)
        self:setWidth(w)
        self:setHeight(h)
    end
    bar.render = function(self)
        local jo = self.javaObject
        if jo == nil then return end
        local s = self.barScale or 1
        local v = BridgeProgress.value or 0
        if v < 0 then v = 0 elseif v > 1 then v = 1 end


        jo:DrawTexturePercentage(bg, 1, bg:getOffsetX(), bg:getOffsetY(), bg:getWidth() * s, bg:getHeight() * s, 1, 1, 1, 1)
        if v > 0 then
            jo:DrawTexturePercentage(fg, v, 3 * s + fg:getOffsetX(), fg:getOffsetY() * s,
                (fg:getWidth() + 1) * s, (fg:getHeight() + 1) * s, 1, 1, 1, 1)
        end
    end
    bar:addToUIManager()



    if bar.javaObject ~= nil and bar.javaObject.setConsumeMouseEvents ~= nil then
        bar.javaObject:setConsumeMouseEvents(false)
    end
    bar:setVisible(false)
    log("progress bar over her created")
    return bar
end


function BridgeProgress.show(value)
    BridgeProgress.value = tonumber(value) or 0
    BridgeProgress.seenAt = now()
    local b = create()
    if b ~= nil and not b:isVisible() then
        b:setVisible(true)
        pcall(function() b:bringToTop() end)
    end
end


function BridgeProgress.takeOver(action)
    if action == nil then return end
    local ok = pcall(function() action.action:setUseProgressBar(false) end)
    if ok then action.useProgressBar = false end
    if not ok then warnOnce("setUseProgressBar failed") end
end

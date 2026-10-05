











require "ISUI/ISCollapsableWindow"
require "ISUI/ISTabPanel"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTickBox"
require "ISUI/ISUI3DModel"

BridgeWindow = BridgeWindow or {}

local PAD = 10
local AVATAR_BORDER = 2
local AVATAR_W, AVATAR_H = 128, 256


local FONT_S, FONT_M, BTN_H = 0, 0, 0
local function refreshFonts()
    FONT_S = getTextManager():getFontHeight(UIFont.Small)
    FONT_M = getTextManager():getFontHeight(UIFont.Medium)
    BTN_H = FONT_S + 6
end
refreshFonts()

local function textW(font, text)
    local w = 0
    pcall(function() w = getTextManager():MeasureStringX(font, tostring(text or "")) end)
    return w or 0
end



local function fitText(font, text, maxW)
    text = tostring(text or "")
    if maxW <= 0 or textW(font, text) <= maxW then return text end
    local n = string.len(text)
    while n > 1 and textW(font, string.sub(text, 1, n) .. "...") > maxW do n = n - 1 end
    return string.sub(text, 1, n) .. "..."
end

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeWindow] " .. tostring(text)) end end
local function warn(text) print("[BridgeWindow] " .. tostring(text)) end

local function tr(key, a)
    local text = key
    pcall(function()
        if a ~= nil then text = getText("IGUI_NotAlone_" .. key, a) else text = getText("IGUI_NotAlone_" .. key) end
    end)
    return text
end

local function name() return Bridge.companionName() end




function BridgeWindow.wornRecords(encoded)
    local out = {}
    for _, rec in ipairs(BridgeItems.decode(encoded or "")) do
        if rec.p == nil and rec.w then out[#out + 1] = rec end
    end
    return out
end


function BridgeWindow.lookKey(st)
    local items = (st ~= nil and st.items) or ""
    local hc = BridgeData.hairColorOf(st)
    return BridgeData.skinOf(st) .. "|" .. BridgeData.hairOf(st) .. "|"
        .. tostring(hc.r) .. "," .. tostring(hc.g) .. "," .. tostring(hc.b) .. "|"
        .. tostring(st ~= nil and st.face or "") .. "|" .. table.concat(BridgeData.cleanDetails(st ~= nil and st.details or nil) or {}, ",") .. "|"
        .. tostring(BridgeData.muscleOf(st)) .. "|" .. table.concat(BridgeData.makeupOf(st), ",") .. "|"
        .. BridgeItems.lookKey(BridgeItems.decode(items))
end



function BridgeWindow.makeDesc(st)
    local desc = SurvivorFactory.CreateSurvivor()
    desc:setFemale(true)
    pcall(function() desc:getWornItems():clear() end)
    local hv = desc:getHumanVisual()
    pcall(function() hv:clear() end)
    pcall(function() hv:setSkinTextureName(BridgeData.skinOf(st)) end)
    pcall(function() hv:setHairModel(BridgeData.hairOf(st)) end)
    local hc = BridgeData.hairColorOf(st)
    pcall(function() hv:setHairColor(ImmutableColor.new(hc.r, hc.g, hc.b)) end)
    pcall(function() hv:setBeardModel("") end)
    for _, rec in ipairs(BridgeWindow.wornRecords(st ~= nil and st.items or "")) do
        pcall(function()
            local item = instanceItem(rec.t)
            if item == nil then return end
            BridgeItems.apply(item, rec)
            local loc = nil
            if item:IsClothing() then loc = item:getBodyLocation() end
            if loc == nil then loc = item:canBeEquipped() end
            if loc ~= nil then desc:setWornItem(loc, item) end
        end)
    end
    BridgeWindow.addCustomDesc(desc, st)
    return desc
end


function BridgeWindow.addCustomDesc(desc, st)
    if desc == nil then return end
    BridgeWindow.missingCustom = BridgeWindow.missingCustom or {}
    local idx = BridgeData.skinIndex(st)
    local function add(id, texture)
        if type(id) ~= "string" or id == "" then return end
        pcall(function()
            local item = instanceItem(id)
            if item == nil then
                if not BridgeWindow.missingCustom[id] then
                    BridgeWindow.missingCustom[id] = true
                    warn("custom item type not found: " .. tostring(id))
                end
                return
            end
            local v = item:getVisual()
            if v ~= nil and texture ~= nil then v:setBaseTexture(texture) v:setTextureChoice(texture) end
            desc:setWornItem(item:getBodyLocation(), item)
        end)
    end
    if BridgeData.spnccOn() then
        local face = BridgeData.faceEntry(st)
        if face ~= nil then add(face.id, BridgeData.spnccTexture(face, idx)) end
        for _, d in ipairs(BridgeData.detailEntries(st)) do
            add(d.id, BridgeData.spnccTexture(d, idx))
        end
        local m = BridgeData.muscleOf(st)
        if m > 0 then
            local mid = BridgeData.spnccMuscle()
            if mid ~= nil then add(mid, idx + (m == 2 and 5 or 0)) end
        end
    end
    for _, type in ipairs(BridgeData.makeupOf(st)) do
        add(type, nil)
    end
end



BridgeWindowInfo = ISPanel:derive("BridgeWindowInfo")

function BridgeWindowInfo:createChildren()
    ISPanel.createChildren(self)
    self.avatarX = PAD + 1 + AVATAR_BORDER
    self.avatarY = PAD + 1 + AVATAR_BORDER
    self.avatar = ISUI3DModel:new(self.avatarX, self.avatarY, AVATAR_W, AVATAR_H)
    self.avatar:initialise()
    self.avatar:instantiate()
    self:addChild(self.avatar)
    pcall(function() self.avatar:setState("idle") end)
    pcall(function() self.avatar:setDirection(IsoDirections.S) end)
    pcall(function() self.avatar:setIsometric(false) end)
    self.avatarBack = getTexture("media/ui/avatarBackgroundWhite.png")

    local x = self.avatarX + AVATAR_W + AVATAR_BORDER + PAD
    self.textX = x
    local w = self.width - x - PAD
    self.callBtn = ISButton:new(x, 0, w, BTN_H, "", self, BridgeWindowInfo.onCall)
    self.callBtn:initialise()
    self.callBtn:instantiate()
    self.callBtn.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
    self:addChild(self.callBtn)

    local change = getText("IGUI_PlayerStats_Change")
    local bw = getTextManager():MeasureStringX(UIFont.Small, change) + PAD * 2
    self.appearBtn = ISButton:new(self.width - PAD - bw, 0, bw, BTN_H, change, self, BridgeWindowInfo.onAppearance)
    self.appearBtn:initialise()
    self.appearBtn:instantiate()
    self.appearBtn.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
    self:addChild(self.appearBtn)
end


function BridgeWindowInfo:refreshAvatar()
    local st = Bridge.store
    local key = BridgeWindow.lookKey(st)
    if key == self.avatarKey then return end
    self.avatarKey = key
    local ok, err = pcall(function() self.avatar:setSurvivorDesc(BridgeWindow.makeDesc(st)) end)
    if not ok then warn("avatar failed: " .. tostring(err)) end
end

function BridgeWindowInfo:prerender()
    ISPanel.prerender(self)
    if Bridge == nil or Bridge.store == nil then return end
    self:refreshAvatar()
    self:drawRectBorder(self.avatarX - 2, self.avatarY - 2, AVATAR_W + 4, AVATAR_H + 4, 1, 0.3, 0.3, 0.3)
    self:drawTextureScaled(self.avatarBack, self.avatarX, self.avatarY, AVATAR_W, AVATAR_H, 1, 0.4, 0.4, 0.4)
end


function BridgeWindow.hairLabel(style)
    local text = nil
    pcall(function() text = getTextOrNull("IGUI_Hair_" .. tostring(style)) end)
    return text or tostring(style)
end




BridgeWindow.REL_TICKS = { 20, 45, 75 }
BridgeWindow.REL_BAR_H = 8
BridgeWindow.REL_COLORS = {
    Cold = { 0.38, 0.42, 0.50 },
    Known = { 0.50, 0.58, 0.68 },
    Pal = { 0.42, 0.62, 0.80 },
    Friend = { 0.62, 0.52, 0.82 },
    Close = { 0.86, 0.46, 0.64 },
}

function BridgeWindow.relBar(rel)
    local f = rel ~= nil and tonumber(rel.f) or 0
    if f == nil or f ~= f then f = 0 end
    local fill = f / 100
    if fill < 0 then fill = 0 elseif fill > 1 then fill = 1 end
    local c = BridgeWindow.REL_COLORS[BridgeData.relTier(rel)] or BridgeWindow.REL_COLORS.Known
    return fill, c[1], c[2], c[3]
end

function BridgeWindowInfo:drawRelBar(x, y, w)
    local fill, cr, cg, cb = BridgeWindow.relBar(BridgeData.relOf(Bridge.store))
    local h = BridgeWindow.REL_BAR_H
    self:drawRect(x, y, w, h, 1, 0.12, 0.12, 0.12)
    local fillW = math.floor(w * fill)
    if fillW > 0 then self:drawRect(x, y, fillW, h, 1, cr, cg, cb) end
    for _, t in ipairs(BridgeWindow.REL_TICKS) do
        self:drawRect(x + math.floor(w * t / 100), y, 1, h, 1, 0.05, 0.05, 0.05)
    end
    self:drawRectBorder(x, y, w, h, 1, 0.35, 0.35, 0.35)
end

function BridgeWindowInfo:render()
    if Bridge == nil or Bridge.store == nil then return end
    local x, y = self.textX, PAD
    local colW = self.width - x - PAD
    self:drawText(fitText(UIFont.Medium, name(), colW), x, y, 1, 1, 1, 1, UIFont.Medium)
    y = y + FONT_M + 2
    self:drawRect(x, y, colW, 1, 1, 0.4, 0.4, 0.4)
    y = y + PAD
    self:drawText(fitText(UIFont.Small, BridgeMenu.status(true), colW), x, y, 0.75, 0.75, 0.75, 1, UIFont.Small)
    y = y + FONT_S + 4
    self:drawRelBar(x, y, colW)
    y = y + BridgeWindow.REL_BAR_H + PAD

    local present = BridgeMenu.isPresent()


    local inCar = BridgeCar ~= nil and BridgeCar.inCarForMenu()
    self.callBtn:setTitle((present or inCar) and tr("Goodbye") or tr("Call", name()))
    self.callBtn:setEnable(not inCar)
    self.callBtn:setY(y)
    y = y + BTN_H + PAD * 2

    self:drawText(tr("WindowAppearance"), x, y, 1, 1, 1, 1, UIFont.Small)
    local shown = tr("LookDefault")
    if BridgeLooks ~= nil and type(BridgeLooks.shown) == "function" then
        local n = BridgeLooks.shown(Bridge.store)
        if type(n) == "string" and n ~= "" then shown = n end
    end
    local lookX = x + textW(UIFont.Small, tr("WindowAppearance")) + PAD
    local appear = self.appearBtn
    local room = colW - (lookX - x)
    if type(appear) == "table" or type(appear) == "userdata" then
        if appear.getX ~= nil then room = appear:getX() - PAD - lookX end
        appear:setY(y - (BTN_H - FONT_S) / 2)
    end
    self:drawText(fitText(UIFont.Small, shown, room), lookX, y, 0.6, 0.6, 0.6, 1, UIFont.Small)


end

function BridgeWindowInfo:onCall()
    if BridgeCar ~= nil and BridgeCar.inCarForMenu() then return end
    if BridgeMenu.isPresent() then BridgeMenu.onGoodbye() else BridgeMenu.onCall() end
end


function BridgeWindow.hairStyles()
    local out = {}
    pcall(function()
        local all = getHairStylesInstance():getAllFemaleStyles()
        for i = 0, all:size() - 1 do
            local style = all:get(i)
            local id = style:getName()
            if id ~= nil and id ~= "" and not style:isNoChoose() and BridgeData.cleanHair(id) ~= nil then
                out[#out + 1] = { id = id, label = BridgeWindow.hairLabel(id) }
            end
        end
    end)



    local count = {}
    for _, e in ipairs(out) do count[e.label] = (count[e.label] or 0) + 1 end
    for _, e in ipairs(out) do
        if count[e.label] > 1 then e.label = e.label .. " (" .. e.id .. ")" end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

function BridgeWindowInfo:onAppearance()
    if BridgeAppearance ~= nil then BridgeAppearance.open("body") end
end

function BridgeWindowInfo:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end



BridgeWindowSettings = ISPanel:derive("BridgeWindowSettings")


BridgeWindow.TICKS = {
    { key = "autoHeal", label = "OptAutoHeal", tip = "OptAutoHealTip" },

    { key = "redKit", label = "OptRedKit", tip = "OptRedKitTip" },
    { key = "hitMatters", label = "OptHitMatters", tip = "OptHitMattersTip" },
    { key = "gifts", label = "OptGifts", tip = "OptGiftsTip" },
    { key = "mood", label = "OptMood", tip = "OptMoodTip" },
}

function BridgeWindowSettings:createChildren()
    ISPanel.createChildren(self)
    local y = PAD
    self.ticks = {}
    for i, entry in ipairs(BridgeWindow.TICKS) do
        local tick = ISTickBox:new(PAD, y, self.width - PAD * 2, BTN_H, "", self, BridgeWindowSettings.onTick, entry.key)
        tick:initialise()
        tick:instantiate()
        tick:addOption(tr(entry.label))
        tick.tooltip = tr(entry.tip)
        self:addChild(tick)
        self.ticks[i] = tick
        y = y + math.max(BTN_H, tick:getHeight()) + PAD
    end
    y = y + PAD
    self.nameY = y
    local label = tr("Rename")
    local bw = getTextManager():MeasureStringX(UIFont.Small, label) + PAD * 2
    self.renameBtn = ISButton:new(PAD, y + FONT_S + PAD / 2, bw, BTN_H, label, self, BridgeWindowSettings.onRename)
    self.renameBtn:initialise()
    self.renameBtn:instantiate()
    self.renameBtn.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
    self:addChild(self.renameBtn)
end

function BridgeWindowSettings:prerender()
    ISPanel.prerender(self)
    if Bridge == nil or Bridge.store == nil then return end

    for i, entry in ipairs(BridgeWindow.TICKS) do
        local want = BridgeData.optionOf(Bridge.store, entry.key)
        if self.ticks[i]:isSelected(1) ~= want then self.ticks[i]:setSelected(1, want) end
    end
end

function BridgeWindowSettings:render()
    if Bridge == nil or Bridge.store == nil then return end
    self:drawText(tr("WindowName") .. " " .. name(), PAD, self.nameY, 1, 1, 1, 1, UIFont.Small)
end

function BridgeWindowSettings:onTick(index, selected, key)
    Bridge.setOption(key, selected == true)
end

function BridgeWindowSettings:onRename()
    BridgeMenu.onRename(0)
end

function BridgeWindowSettings:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end



BridgeWindowMain = ISCollapsableWindow:derive("BridgeWindowMain")

function BridgeWindowMain:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    self.panel = ISTabPanel:new(0, th, self.width, self.height - th - rh)
    self.panel:initialise()
    self.panel.tabPadX = PAD
    self.panel.equalTabWidth = false
    self:addChild(self.panel)
    local inner = self.height - th - rh - self.panel.tabHeight
    self.info = BridgeWindowInfo:new(0, 8, self.width, inner)
    self.info:initialise()
    self.panel:addView(tr("WindowInfo"), self.info)
    self.settings = BridgeWindowSettings:new(0, 8, self.width, inner)
    self.settings:initialise()
    self.panel:addView(tr("WindowSettings"), self.settings)
end

function BridgeWindowMain:prerender()

    self.title = ""
    ISCollapsableWindow.prerender(self)
end

function BridgeWindowMain:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    BridgeWindow.instance = nil
end

function BridgeWindowMain:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor.a = 0.9
    o:setResizable(false)
    o.title = ""
    return o
end

BridgeWindow.WIDTH = 420
BridgeWindow.HEIGHT = 340



function BridgeWindow.neededSize()
    refreshFonts()
    local textX = PAD + 1 + AVATAR_BORDER + AVATAR_W + AVATAR_BORDER + PAD
    local status = ""
    pcall(function() status = BridgeMenu.status(true) end)

    local lookLabel = tr("LookDefault")
    local colW = math.max(
        textW(UIFont.Medium, name()),
        textW(UIFont.Small, status),
        textW(UIFont.Small, tr("Goodbye")) + PAD * 2,
        textW(UIFont.Small, tr("Call", name())) + PAD * 2,
        textW(UIFont.Small, tr("WindowAppearance")) + PAD + textW(UIFont.Small, lookLabel) + PAD + textW(UIFont.Small, getText("IGUI_PlayerStats_Change")) + PAD * 2)
    local w = textX + colW + PAD

    local gap = UI_BORDER_SPACING or 10
    for _, entry in ipairs(BridgeWindow.TICKS) do
        w = math.max(w, PAD * 2 + BTN_H + gap + textW(UIFont.Small, tr(entry.label)) + PAD)
    end
    w = math.max(w, PAD * 2 + textW(UIFont.Small, tr("WindowName") .. " " .. name()))
    local tickH = math.max(BTN_H, FONT_S) + gap
    local infoH = math.max(PAD * 2 + 2 + AVATAR_H + AVATAR_BORDER * 2,
        PAD + FONT_M + 2 + PAD + FONT_S + 4 + BridgeWindow.REL_BAR_H + PAD + BTN_H + PAD * 2 + BTN_H + PAD)
    local setH = PAD + #BridgeWindow.TICKS * (tickH + PAD) + PAD + FONT_S + PAD / 2 + BTN_H + PAD
    return math.max(BridgeWindow.WIDTH, math.ceil(w)), math.ceil(math.max(infoH, setH))
end


function BridgeWindow.toggle(x, y)
    if Bridge == nil or Bridge.store == nil then return nil end
    if BridgeWindow.instance ~= nil then
        BridgeWindow.instance:close()
        return nil
    end
    refreshFonts()
    local width, contentH = BridgeWindow.WIDTH, 0
    local ok, err = pcall(function() width, contentH = BridgeWindow.neededSize() end)
    if not ok then warn("size failed: " .. tostring(err)) end
    local w = BridgeWindowMain:new(x or 100, y or 100, width, BridgeWindow.HEIGHT)


    pcall(function()
        local h = w:titleBarHeight() + FONT_S + 6 + 8 + contentH + w:resizeWidgetHeight()
        w:setHeight(math.max(BridgeWindow.HEIGHT, math.ceil(h)))
    end)

    pcall(function()
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        w:setX(math.max(0, math.min(w:getX(), sw - w:getWidth() - PAD)))
        w:setY(math.max(0, math.min(w:getY(), sh - w:getHeight() - PAD)))
    end)
    if Bridge.verbose then
        log(string.format("window %dx%d, font small %d medium %d", w:getWidth(), w:getHeight(), FONT_S, FONT_M))
    end
    w:initialise()
    w:addToUIManager()
    w:setVisible(true)
    BridgeWindow.instance = w
    return w
end

log("loaded")

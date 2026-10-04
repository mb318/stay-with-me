
require "ISUI/ISCollapsableWindow"
require "ISUI/ISTabPanel"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISUI3DModel"
require "ISUI/ISColorPickerHSB"

BridgeAppearance = BridgeAppearance or {}

local PAD = 10
local PREVIEW_W, PREVIEW_H = 170, 300

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

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeAppearance] " .. tostring(text)) end end
local function warn(text) print("[BridgeAppearance] " .. tostring(text)) end

local function tr(key, a)
    local text = key
    pcall(function()
        if a ~= nil then text = getText("IGUI_NotAlone_" .. key, a) else text = getText("IGUI_NotAlone_" .. key) end
    end)
    return text
end

local function gameText(key, fallback)
    local text = nil
    pcall(function() text = getTextOrNull(key) end)
    if text == nil or text == "" then return fallback end
    return text
end

local function copyColor(c)
    return { r = c.r, g = c.g, b = c.b }
end

local function sameColor(a, b)
    if a == nil or b == nil then return false end
    return math.abs(a.r - b.r) < 0.01 and math.abs(a.g - b.g) < 0.01 and math.abs(a.b - b.b) < 0.01
end

local function mark(btn, on)
    if on then
        btn.borderColor = { r = 1, g = 0.85, b = 0.2, a = 1 }
    else
        btn.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
    end
end



BridgeAppearance.Catalog = BridgeAppearance.Catalog or {}

function BridgeAppearance.Catalog.bodyEntries()
    local out = {}
    for i, id in ipairs(BridgeData.SKINS) do
        out[#out + 1] = { id = id, label = tr("SkinTone", i) }
    end
    return out
end

function BridgeAppearance.Catalog.hairEntries()
    local out = {}
    local styles = (BridgeWindow ~= nil and BridgeWindow.hairStyles ~= nil) and BridgeWindow.hairStyles() or {}
    for _, s in ipairs(styles) do
        out[#out + 1] = { name = s.id, label = s.label }
    end
    return out
end

function BridgeAppearance.Catalog.faceEntries()
    local out = { { name = "", label = tr("AppearanceDefaultFace") } }
    for _, e in ipairs(BridgeData.spnccFaces() or {}) do
        local label = gameText("IGUI_Face_" .. tostring(e.display or e.name), tostring(e.display or e.name))
        out[#out + 1] = { name = e.name, label = label }
    end
    return out
end

function BridgeAppearance.Catalog.detailEntries()
    local out = {}
    for _, e in ipairs(BridgeData.spnccDetails() or {}) do
        local label = gameText("IGUI_Detail_" .. tostring(e.display or e.name), tostring(e.display or e.name))
        out[#out + 1] = { name = e.name, label = label }
    end
    return out
end

function BridgeAppearance.Catalog.hairColorPresets()
    local out = {}
    pcall(function()
        local desc = SurvivorFactory.CreateSurvivor()
        local list = desc:getCommonHairColor()
        if list == nil then return end
        for i = 0, list:size() - 1 do
            local c = list:get(i)
            out[#out + 1] = { r = c:getRedFloat(), g = c:getGreenFloat(), b = c:getBlueFloat() }
        end
    end)
    if #out == 0 then
        out = {
            { r = 0.05, g = 0.03, b = 0.02 },
            { r = 0.16, g = 0.09, b = 0.05 },
            { r = 0.35, g = 0.18, b = 0.08 },
            { r = 0.55, g = 0.12, b = 0.12 },
            { r = 0.72, g = 0.50, b = 0.18 },
            { r = 0.90, g = 0.80, b = 0.55 },
            { r = 0.62, g = 0.62, b = 0.62 },
            { r = 0.92, g = 0.92, b = 0.92 },
        }
    end
    return out
end



BridgeAppearance.candidate = { skin = nil, hair = nil, hairColor = nil, face = nil, details = {}, muscle = 0 }

function BridgeAppearance.makePreviewDesc()
    local st = Bridge.store or {}
    local c = BridgeAppearance.candidate
    local tmp = { skin = c.skin, hair = c.hair, hairColor = c.hairColor, items = st.items,
                  face = c.face, details = c.details, muscle = c.muscle }
    return BridgeWindow.makeDesc(tmp)
end

function BridgeAppearance.refreshPreview()
    local w = BridgeAppearance.instance
    if w == nil or w.preview == nil then return end
    local ok, err = pcall(function() w.preview:setSurvivorDesc(BridgeAppearance.makePreviewDesc()) end)
    if not ok then warn("preview failed: " .. tostring(err)) end
end

function BridgeAppearance.refreshViews()
    local w = BridgeAppearance.instance
    if w == nil then return end
    pcall(function() w:refresh() end)
end

function BridgeAppearance.setSkin(id)
    local skin = BridgeData.cleanSkin(id)
    if skin == nil then return end
    BridgeAppearance.candidate.skin = skin
    BridgeAppearance.refreshPreview()
    BridgeAppearance.refreshViews()
end

function BridgeAppearance.setHair(id)
    local hair = BridgeData.cleanHair(id)
    if hair == nil then return end
    BridgeAppearance.candidate.hair = hair
    BridgeAppearance.refreshPreview()
    BridgeAppearance.refreshViews()
end

function BridgeAppearance.setColor(c)
    local color = BridgeData.cleanHairColor(c)
    if color == nil then return end
    BridgeAppearance.candidate.hairColor = color
    BridgeAppearance.refreshPreview()
    BridgeAppearance.refreshViews()
end

function BridgeAppearance.setFace(name)
    if name == nil or name == "" then
        BridgeAppearance.candidate.face = nil
    else
        BridgeAppearance.candidate.face = BridgeData.cleanFace(name)
    end
    BridgeAppearance.refreshPreview()
    BridgeAppearance.refreshViews()
end

function BridgeAppearance.hasDetail(name)
    for _, n in ipairs(BridgeAppearance.candidate.details) do
        if n == name then return true end
    end
    return false
end

function BridgeAppearance.toggleDetail(name)
    local valid = false
    for _, e in ipairs(BridgeData.spnccDetails() or {}) do
        if e.name == name then valid = true break end
    end
    if not valid then return end
    local out, removed = {}, false
    for _, n in ipairs(BridgeAppearance.candidate.details) do
        if n == name then removed = true else out[#out + 1] = n end
    end
    if not removed then out[#out + 1] = name end
    BridgeAppearance.candidate.details = out
    BridgeAppearance.refreshPreview()
    BridgeAppearance.refreshViews()
end

function BridgeAppearance.setMuscle(level)
    local m = tonumber(level)
    if m == nil or m ~= m then return end
    m = math.floor(m)
    if m < 0 then m = 0 end
    if m > BridgeData.MUSCLE_MAX then m = BridgeData.MUSCLE_MAX end
    BridgeAppearance.candidate.muscle = m
    BridgeAppearance.refreshPreview()
    BridgeAppearance.refreshViews()
end

function BridgeAppearance.openColorPicker(button)
    local cur = BridgeAppearance.candidate.hairColor or BridgeData.DEFAULT_HAIR_COLOR
    local picker = nil
    local ok, err = pcall(function()
        picker = ISColorPickerHSB:new(0, 0, ColorInfo.new(cur.r, cur.g, cur.b, 1))
        picker:initialise()
        picker.keepOnScreen = true
        picker.pickedTarget = BridgeAppearance
        picker.resetFocusTo = BridgeAppearance.instance
        picker:setPickedFunc(BridgeAppearance.onCustomColor)
        picker:setInitialColor(ColorInfo.new(cur.r, cur.g, cur.b, 1))
        if button ~= nil then
            picker:setX(button:getAbsoluteX())
            picker:setY(button:getAbsoluteY() + button:getHeight())
        end
        picker:addToUIManager()
        picker:setCapture(false)
    end)
    if not ok then warn("color picker failed: " .. tostring(err)) end
    BridgeAppearance.picker = picker
    return picker
end

function BridgeAppearance.onCustomColor(target, color, mouseUp)
    if color ~= nil then
        BridgeAppearance.setColor({ r = color.r, g = color.g, b = color.b })
    end
    local picker = BridgeAppearance.picker
    BridgeAppearance.picker = nil
    if picker ~= nil then pcall(function() picker:removeSelf() end) end
end



BridgeAppearanceBody = ISPanel:derive("BridgeAppearanceBody")

function BridgeAppearanceBody:createChildren()
    ISPanel.createChildren(self)
    local y = PAD
    self.skinLabelY = y
    y = y + FONT_S + 4
    local cw = math.min(260, self.width - PAD * 2)
    self.skinCombo = ISComboBox:new(PAD, y, cw, BTN_H, self, BridgeAppearanceBody.onSkin)
    self.skinCombo:initialise()
    for i, id in ipairs(BridgeData.SKINS) do
        self.skinCombo:addOptionWithData(tr("SkinTone", i), id)
    end
    self:addChild(self.skinCombo)
    y = y + BTN_H + PAD

    self.muscleLabelY = nil
    self.muscleCombo = nil
    if BridgeData.spnccMuscle() ~= nil then
        self.muscleLabelY = y
        y = y + FONT_S + 4
        self.muscleCombo = ISComboBox:new(PAD, y, cw, BTN_H, self, BridgeAppearanceBody.onMuscle)
        self.muscleCombo:initialise()
        self.muscleCombo:addOptionWithData(tr("Muscle_0"), 0)
        self.muscleCombo:addOptionWithData(tr("Muscle_1"), 1)
        self.muscleCombo:addOptionWithData(tr("Muscle_2"), 2)
        self:addChild(self.muscleCombo)
    end
end

function BridgeAppearanceBody:render()
    self:drawText(tr("AppearanceSkin"), PAD, self.skinLabelY, 1, 1, 1, 1, UIFont.Small)
    if self.muscleLabelY ~= nil then
        self:drawText(tr("AppearanceBody"), PAD, self.muscleLabelY, 1, 1, 1, 1, UIFont.Small)
    end
end

function BridgeAppearanceBody:onSkin(combo)
    BridgeAppearance.setSkin(combo:getSelectedData())
end

function BridgeAppearanceBody:onMuscle(combo)
    BridgeAppearance.setMuscle(combo:getSelectedData())
end

function BridgeAppearanceBody:refresh()
    self.skinCombo:selectData(BridgeAppearance.candidate.skin)
    if self.muscleCombo ~= nil then
        self.muscleCombo:selectData(BridgeAppearance.candidate.muscle)
    end
end

function BridgeAppearanceBody:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end



local function gridButton(view, i, cols, onClick)
    local bw = math.floor((view.width - PAD * (cols + 1)) / cols)
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local b = ISButton:new(PAD + col * (bw + PAD), PAD + FONT_S + PAD + row * (BTN_H + 6), bw, BTN_H + 2,
        "", view, onClick)
    b:initialise()
    b:instantiate()
    mark(b, false)
    view:addChild(b)
    return b
end

local function addPager(view, rows, onPrev, onNext)
    view.pageY = PAD + FONT_S + PAD + rows * (BTN_H + 6)
    local pw = BTN_H + 20
    view.prevBtn = ISButton:new(PAD, view.pageY, pw, BTN_H, "<", view, onPrev)
    view.prevBtn:initialise()
    view.prevBtn:instantiate()
    view:addChild(view.prevBtn)
    view.nextBtn = ISButton:new(PAD + pw + PAD, view.pageY, pw, BTN_H, ">", view, onNext)
    view.nextBtn:initialise()
    view.nextBtn:instantiate()
    view:addChild(view.nextBtn)
end

local function pagerRefresh(view, selectedName, isSelected)
    local pages = math.max(1, math.ceil(#view.entries / view.per))
    if view.page > pages then view.page = pages end
    if view.page < 1 then view.page = 1 end
    local start = (view.page - 1) * view.per
    for i, b in ipairs(view.btns) do
        local e = view.entries[start + i]
        if e ~= nil then
            b:setTitle(e.label)
            b:setEnable(true)
            b.entryName = e.name or e.id
            mark(b, isSelected(b.entryName))
        else
            b:setTitle("")
            b:setEnable(false)
            b.entryName = nil
            mark(b, false)
        end
    end
    view.pageText = view.page .. " / " .. pages
    view.prevBtn:setEnable(view.page > 1)
    view.nextBtn:setEnable(view.page < pages)
end



BridgeAppearanceFace = ISPanel:derive("BridgeAppearanceFace")

function BridgeAppearanceFace:createChildren()
    ISPanel.createChildren(self)
    self.entries = BridgeAppearance.Catalog.faceEntries()
    self.cols, self.rows = 3, 4
    self.per = self.cols * self.rows
    self.page = 1
    self.pageText = "1 / 1"
    self.btns = {}
    for i = 1, self.per do
        self.btns[i] = gridButton(self, i, self.cols, BridgeAppearanceFace.onPick)
    end
    addPager(self, self.rows, BridgeAppearanceFace.onPrev, BridgeAppearanceFace.onNext)
end

function BridgeAppearanceFace:render()
    self:drawText(tr("AppearanceFace"), PAD, PAD, 1, 1, 1, 1, UIFont.Small)
    self:drawText(self.pageText, self.nextBtn:getRight() + PAD, self.pageY + 3, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function BridgeAppearanceFace:onPick(button)
    if button.entryName ~= nil then BridgeAppearance.setFace(button.entryName) end
end

function BridgeAppearanceFace:onPrev() self.page = self.page - 1 self:refresh() end
function BridgeAppearanceFace:onNext() self.page = self.page + 1 self:refresh() end

function BridgeAppearanceFace:refresh()
    pagerRefresh(self, nil, function(name) return (BridgeAppearance.candidate.face or "") == name end)
end

function BridgeAppearanceFace:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end



BridgeAppearanceDetails = ISPanel:derive("BridgeAppearanceDetails")

function BridgeAppearanceDetails:createChildren()
    ISPanel.createChildren(self)
    self.entries = BridgeAppearance.Catalog.detailEntries()
    self.cols, self.rows = 3, 4
    self.per = self.cols * self.rows
    self.page = 1
    self.pageText = "1 / 1"
    self.btns = {}
    for i = 1, self.per do
        self.btns[i] = gridButton(self, i, self.cols, BridgeAppearanceDetails.onToggle)
    end
    addPager(self, self.rows, BridgeAppearanceDetails.onPrev, BridgeAppearanceDetails.onNext)
    self.clearBtn = ISButton:new(PAD, self.pageY + BTN_H + PAD, self.width - PAD * 2, BTN_H,
        tr("AppearanceClearDetails"), self, BridgeAppearanceDetails.onClear)
    self.clearBtn:initialise()
    self.clearBtn:instantiate()
    self:addChild(self.clearBtn)
end

function BridgeAppearanceDetails:render()
    self:drawText(tr("AppearanceDetails"), PAD, PAD, 1, 1, 1, 1, UIFont.Small)
    self:drawText(self.pageText, self.nextBtn:getRight() + PAD, self.pageY + 3, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function BridgeAppearanceDetails:onToggle(button)
    if button.entryName ~= nil then BridgeAppearance.toggleDetail(button.entryName) end
end

function BridgeAppearanceDetails:onClear()
    BridgeAppearance.candidate.details = {}
    BridgeAppearance.refreshPreview()
    BridgeAppearance.refreshViews()
end

function BridgeAppearanceDetails:onPrev() self.page = self.page - 1 self:refresh() end
function BridgeAppearanceDetails:onNext() self.page = self.page + 1 self:refresh() end

function BridgeAppearanceDetails:refresh()
    pagerRefresh(self, nil, function(name) return BridgeAppearance.hasDetail(name) end)
end

function BridgeAppearanceDetails:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end



BridgeAppearanceHair = ISPanel:derive("BridgeAppearanceHair")

function BridgeAppearanceHair:createChildren()
    ISPanel.createChildren(self)
    self.entries = BridgeAppearance.Catalog.hairEntries()
    self.cols, self.rows = 3, 4
    self.per = self.cols * self.rows
    self.page = 1
    self.pageText = "1 / 1"
    self.btns = {}
    for i = 1, self.per do
        self.btns[i] = gridButton(self, i, self.cols, BridgeAppearanceHair.onStyle)
    end
    addPager(self, self.rows, BridgeAppearanceHair.onPrev, BridgeAppearanceHair.onNext)

    self.colorY = self.pageY + BTN_H + PAD + FONT_S + PAD
    self.swatches = {}
    local presets = BridgeAppearance.Catalog.hairColorPresets()
    local sw = 24
    local sx = PAD
    for _, c in ipairs(presets) do
        if sx + sw > self.width - PAD then break end
        local b = ISButton:new(sx, self.colorY, sw, sw, "", self, BridgeAppearanceHair.onColor)
        b:initialise()
        b:instantiate()
        b.backgroundColor = { r = c.r, g = c.g, b = c.b, a = 1 }
        b.colorValue = c
        mark(b, false)
        self:addChild(b)
        self.swatches[#self.swatches + 1] = b
        sx = sx + sw + 4
    end
    self.customBtn = ISButton:new(PAD, self.colorY + sw + PAD, self.width - PAD * 2, BTN_H,
        tr("AppearanceCustomColor"), self, BridgeAppearanceHair.onCustom)
    self.customBtn:initialise()
    self.customBtn:instantiate()
    self:addChild(self.customBtn)
end

function BridgeAppearanceHair:render()
    self:drawText(tr("AppearanceHair"), PAD, PAD, 1, 1, 1, 1, UIFont.Small)
    self:drawText(self.pageText, self.nextBtn:getRight() + PAD, self.pageY + 3, 0.8, 0.8, 0.8, 1, UIFont.Small)
    self:drawText(tr("AppearanceColor"), PAD, self.pageY + BTN_H + PAD, 1, 1, 1, 1, UIFont.Small)
end

function BridgeAppearanceHair:onStyle(button)
    if button.entryName ~= nil then BridgeAppearance.setHair(button.entryName) end
end

function BridgeAppearanceHair:onColor(button)
    if button.colorValue ~= nil then BridgeAppearance.setColor(button.colorValue) end
end

function BridgeAppearanceHair:onCustom(button)
    BridgeAppearance.openColorPicker(button)
end

function BridgeAppearanceHair:onPrev() self.page = self.page - 1 self:refresh() end
function BridgeAppearanceHair:onNext() self.page = self.page + 1 self:refresh() end

function BridgeAppearanceHair:refresh()
    pagerRefresh(self, nil, function(name) return BridgeAppearance.candidate.hair == name end)
    local cur = BridgeAppearance.candidate.hairColor
    for _, b in ipairs(self.swatches) do
        mark(b, sameColor(b.colorValue, cur))
    end
end

function BridgeAppearanceHair:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end



BridgeAppearance.Window = ISCollapsableWindow:derive("BridgeAppearanceWindow")

function BridgeAppearance.Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()

    self.preview = ISUI3DModel:new(PAD, th + PAD, PREVIEW_W, PREVIEW_H)
    self.preview:initialise()
    self.preview:instantiate()
    self:addChild(self.preview)
    pcall(function() self.preview:setState("idle") end)
    pcall(function() self.preview:setDirection(IsoDirections.S) end)
    pcall(function() self.preview:setIsometric(false) end)
    self.previewBack = getTexture("media/ui/avatarBackgroundWhite.png")

    local tabX = PAD + PREVIEW_W + PAD
    local tabW = self.width - tabX - PAD
    local footerH = BTN_H + PAD * 2
    local tabY = th + PAD
    local tabH = self.height - tabY - rh - footerH - PAD
    self.panel = ISTabPanel:new(tabX, tabY, tabW, tabH)
    self.panel:initialise()
    self.panel.tabPadX = PAD
    self.panel.equalTabWidth = false
    self:addChild(self.panel)

    local innerH = tabH - self.panel.tabHeight
    self.bodyView = BridgeAppearanceBody:new(0, 0, tabW, innerH)
    self.bodyView:initialise()
    self.panel:addView(tr("AppearanceBody"), self.bodyView)

    self.faceView = nil
    if BridgeData.spnccFaces() ~= nil then
        self.faceView = BridgeAppearanceFace:new(0, 0, tabW, innerH)
        self.faceView:initialise()
        self.panel:addView(tr("AppearanceFace"), self.faceView)
    end

    self.hairView = BridgeAppearanceHair:new(0, 0, tabW, innerH)
    self.hairView:initialise()
    self.panel:addView(tr("AppearanceHair"), self.hairView)

    self.detailView = nil
    if BridgeData.spnccDetails() ~= nil then
        self.detailView = BridgeAppearanceDetails:new(0, 0, tabW, innerH)
        self.detailView:initialise()
        self.panel:addView(tr("AppearanceDetails"), self.detailView)
    end

    local by = self.height - rh - footerH + PAD
    local applyW = textW(UIFont.Small, tr("AppearanceApply")) + PAD * 3
    local closeW = textW(UIFont.Small, tr("Close")) + PAD * 3
    self.applyBtn = ISButton:new(self.width - PAD - applyW - PAD - closeW, by, applyW, BTN_H,
        tr("AppearanceApply"), self, BridgeAppearance.Window.onApply)
    self.applyBtn:initialise()
    self.applyBtn:instantiate()
    self:addChild(self.applyBtn)
    self.closeBtn = ISButton:new(self.width - PAD - closeW, by, closeW, BTN_H,
        tr("Close"), self, BridgeAppearance.Window.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self:addChild(self.closeBtn)
end

function BridgeAppearance.Window:prerender()
    ISCollapsableWindow.prerender(self)
    if self.preview ~= nil then
        local py = self:titleBarHeight() + PAD
        self:drawRectBorder(PAD - 2, py - 2, PREVIEW_W + 4, PREVIEW_H + 4, 1, 0.3, 0.3, 0.3)
        self:drawTextureScaled(self.previewBack, PAD, py, PREVIEW_W, PREVIEW_H, 1, 0.4, 0.4, 0.4)
    end
end

function BridgeAppearance.Window:refresh()
    if self.bodyView ~= nil then self.bodyView:refresh() end
    if self.faceView ~= nil then self.faceView:refresh() end
    if self.hairView ~= nil then self.hairView:refresh() end
    if self.detailView ~= nil then self.detailView:refresh() end
end

function BridgeAppearance.Window:tabName(which)
    if which == "body" then return tr("AppearanceBody") end
    if which == "face" then return tr("AppearanceFace") end
    if which == "details" then return tr("AppearanceDetails") end
    return tr("AppearanceHair")
end

function BridgeAppearance.Window:selectTab(which)
    local name = self:tabName(which)
    pcall(function() self.panel:activateView(name) end)
end

function BridgeAppearance.Window:onApply()
    local c = BridgeAppearance.candidate
    if c.skin ~= nil then pcall(function() Bridge.setSkin(c.skin) end) end
    if c.hair ~= nil then pcall(function() Bridge.setHair(c.hair) end) end
    if c.hairColor ~= nil then
        pcall(function() Bridge.setHairColor(c.hairColor.r, c.hairColor.g, c.hairColor.b) end)
    end
    if BridgeData.spnccFaces() ~= nil then
        pcall(function() Bridge.setFace(c.face) end)
    end
    if BridgeData.spnccMuscle() ~= nil then
        pcall(function() Bridge.setMuscle(c.muscle) end)
    end
    if BridgeData.spnccDetails() ~= nil then
        pcall(function() Bridge.setDetails(c.details) end)
    end
end

function BridgeAppearance.Window:onClose()
    self:close()
end

function BridgeAppearance.Window:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if BridgeAppearance.instance == self then BridgeAppearance.instance = nil end
end

function BridgeAppearance.Window:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor.a = 0.9
    o:setResizable(false)
    o.title = tr("WindowAppearance")
    return o
end



BridgeAppearance.WIDTH = 620
BridgeAppearance.HEIGHT = 440

function BridgeAppearance.open(tab)
    if Bridge == nil or Bridge.store == nil then return nil end
    if BridgeAppearance.instance ~= nil then
        BridgeAppearance.instance:selectTab(tab)
        return BridgeAppearance.instance
    end
    refreshFonts()
    local c = BridgeAppearance.candidate
    c.skin = BridgeData.skinOf(Bridge.store)
    c.hair = BridgeData.hairOf(Bridge.store)
    c.hairColor = copyColor(BridgeData.hairColorOf(Bridge.store))
    c.face = BridgeData.cleanFace(Bridge.store.face)
    c.details = BridgeData.cleanDetails(Bridge.store.details) or {}
    c.muscle = BridgeData.muscleOf(Bridge.store)
    local w = BridgeAppearance.Window:new(100, 100, BridgeAppearance.WIDTH, BridgeAppearance.HEIGHT)
    pcall(function()
        local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
        w:setX(math.max(0, math.min(w:getX(), sw - w:getWidth() - PAD)))
        w:setY(math.max(0, math.min(w:getY(), sh - w:getHeight() - PAD)))
    end)
    w:initialise()
    w:addToUIManager()
    w:setVisible(true)
    BridgeAppearance.instance = w
    w:refresh()
    BridgeAppearance.refreshPreview()
    w:selectTab(tab)
    log("opened")
    return w
end

log("loaded")

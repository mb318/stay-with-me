








BridgeMenu = BridgeMenu or {}

local UI_BORDER_SPACING = 10

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeMenu] " .. tostring(text)) end end
local function warn(text) print("[BridgeMenu] " .. tostring(text)) end

local function tr(key, a)
    local text = key
    pcall(function()
        if a ~= nil then text = getText("IGUI_NotAlone_" .. key, a) else text = getText("IGUI_NotAlone_" .. key) end
    end)
    return text
end

local function name() return Bridge.companionName() end



BridgeMenu.TALK_RANGE = 12


local function present()
    if Bridge.alive() then return true end

    if Bridge.mp and Bridge.store ~= nil and Bridge.store.bodyId ~= nil then
        for _, info in pairs(Bridge.bodiesSeen()) do
            if info.who == BridgeData.me() then return true end
        end
    end
    return false
end

function BridgeMenu.isPresent() return present() end



function BridgeMenu.inCarWithRed()
    return BridgeCar ~= nil and BridgeCar.withRed(BridgeData.owner())
end



function BridgeMenu.lit()
    return (present() and BridgeMenu.inTalkRange()) or BridgeMenu.inCarWithRed()
end



function BridgeMenu.inTalkRange()
    local red = BridgeData.owner()
    if red == nil then return false end
    local function close(z)
        local yes = false
        pcall(function()
            local dx, dy = z:getX() - red:getX(), z:getY() - red:getY()
            yes = dx * dx + dy * dy <= BridgeMenu.TALK_RANGE * BridgeMenu.TALK_RANGE
                and math.abs(z:getZ() - red:getZ()) < 1.5
        end)
        return yes
    end
    if Bridge.alive() then return close(Bridge.body) end
    for z, info in pairs(Bridge.bodiesSeen()) do
        if info.who == BridgeData.me() and close(z) then return true end
    end
    return false
end



function BridgeMenu.status(short)
    local st = Bridge.store
    local mode = BridgeData.modeOf(st)
    local function line(key)
        if short then return tr(key .. "Short") end
        return tr(key, name())
    end
    local function suffix()
        local label = ""
        pcall(function() label = BridgeSocial.label() end)
        return (label ~= nil and label ~= "") and (" (" .. label .. ")") or ""
    end
    if BridgeCar ~= nil and BridgeCar.inCarForMenu() then
        if BridgeMenu.inCarWithRed() then return line("StatusInCar") .. suffix() end
        return line("StatusInCar")
    end
    if present() then
        local suffix = suffix()
        if mode == "rest" then return line("StatusResting") .. suffix end
        if mode == "wait" then return line("StatusWaiting") .. suffix end
        return line("StatusHere") .. suffix
    end
    if BridgeData.wants(st) and mode ~= "follow" and st ~= nil and st.waitX ~= nil then
        return line("StatusWaiting")
    end
    return line("StatusAway")
end



function BridgeMenu.onCall()
    if not present() then Bridge.greetOnReveal = true end
    Bridge.call()
end

function BridgeMenu.onFollow()
    Bridge.setMode("follow")
    Bridge.speak("Follow")
end

function BridgeMenu.onWait()
    Bridge.setMode("wait")
    Bridge.speak("Wait")
end

function BridgeMenu.onRest()
    Bridge.setMode("rest")
    Bridge.speak("Rest")
end

function BridgeMenu.onHeal()
    local res = BridgeHeal.request()
    log("heal from menu: " .. tostring(res))
end

function BridgeMenu.onWash()
    BridgeWash.start("menu")
end

function BridgeMenu.onGoodbye()
    Bridge.goodbye()
end


function BridgeMenu.onKeepSide(side)
    Bridge.setKeep(side)
    if present() then Bridge.speak("Keep_" .. tostring(side)) end
end


function BridgeMenu.onKeepDistance(which)
    local far = which == "far"
    Bridge.setFar(far)
    if present() then Bridge.speak(far and "KeepFarther" or "KeepCloser") end
end


function BridgeMenu.onCombat(mode)
    Bridge.setCombat(mode)
    if present() then Bridge.speak("Combat_" .. tostring(mode)) end
end

function BridgeMenu.onRenameDone(target, button, playerNum)
    if button == nil or button.internal ~= "OK" then return end
    local text = nil
    pcall(function() text = button.parent.entry:getText() end)
    Bridge.setName(text)
    if present() then Bridge.speak("Renamed", name()) end
end

function BridgeMenu.onRename(playerNum)
    local modal = ISTextBox:new(0, 0, 280, 180, tr("NamePrompt"), name(), nil, BridgeMenu.onRenameDone, playerNum or 0)
    modal:initialise()
    modal:addToUIManager()
    pcall(function() modal.entry:setMaxTextLength(BridgeData.NAME_MAX) end)
end





function BridgeMenu.fill(context, playerNum, fromIcon)
    if Bridge == nil or Bridge.store == nil then return end
    local st = Bridge.store
    local mode = BridgeData.modeOf(st)
    if fromIcon then
        local status = context:addOption(BridgeMenu.status(true))
        status.isDisabled = true
    end
    local function actionsMenu()
        local option = context:addOption(tr("Actions"))
        local sub = ISContextMenu:getNew(context)
        context:addSubMenu(option, sub)
        return sub
    end




    if BridgeCar ~= nil and BridgeCar.inCarForMenu() then
        if not fromIcon then
            local status = context:addOption(BridgeMenu.status(false))
            status.isDisabled = true
        end
        if BridgeMenu.inCarWithRed() then
            pcall(function() BridgeSocial.fillMenu(context, tr) end)
        end
        return
    end
    if not present() then



        context:addOption(fromIcon and tr("CallShort") or tr("Call", name()), nil, BridgeMenu.onCall)
        return
    end
    local inRange = BridgeMenu.inTalkRange()
    if inRange then

        pcall(function() BridgeSocial.fillMenu(context, tr) end)

        local heal = context:addOption(tr("HealMe"), nil, BridgeMenu.onHeal)
        if not Bridge.drivable() or not Bridge.alive() then
            heal.notAvailable = true
        elseif BridgeHeal.active then
            heal.notAvailable = true
        end
    end
    if mode == "follow" then
        context:addOption(tr("WaitHere"), nil, BridgeMenu.onWait)
    else
        context:addOption(tr("ComeWithMe"), nil, BridgeMenu.onFollow)
    end
    local actions = actionsMenu()
    if mode == "rest" then
        actions:addOption(tr("WaitHere"), nil, BridgeMenu.onWait)
    elseif inRange then
        actions:addOption(tr("Rest"), nil, BridgeMenu.onRest)
    end

    if inRange then
        local wash = actions:addOption(tr("Wash"), nil, BridgeMenu.onWash)
        if not Bridge.drivable() then

            wash.notAvailable = true
        end
    end
    actions:addOption(tr("Goodbye"), nil, BridgeMenu.onGoodbye)

    local combatOption = context:addOption(tr("Combat"))
    local guard = false
    pcall(function() if BridgeFight ~= nil then guard = BridgeFight.guardOnly end end)
    if guard then
        combatOption.isDisabled = true
    else
        local combat = ISContextMenu:getNew(context)
        context:addSubMenu(combatOption, combat)
        local combatMode = BridgeData.combatOf(st)
        for _, entry in ipairs({ { "bodyguard", "CombatBodyguard" }, { "escort", "CombatEscort" },
            { "aggressive", "CombatAggressive" } }) do
            local o = combat:addOption(tr(entry[2]), entry[1], BridgeMenu.onCombat)
            if combatMode == entry[1] then o.isDisabled = true end
        end
    end

    if not BridgeData.KEEP_ON then return end

    local keepOption = context:addOption(tr("Keep"))
    local keep = ISContextMenu:getNew(context)
    context:addSubMenu(keepOption, keep)
    local far = BridgeData.farOf(st)
    local side = BridgeData.keepOf(st)
    local closer = keep:addOption(tr("KeepCloser"), "near", BridgeMenu.onKeepDistance)
    if not far then closer.isDisabled = true end
    local farther = keep:addOption(tr("KeepFarther"), "far", BridgeMenu.onKeepDistance)
    if far then farther.isDisabled = true end

    if BridgeData.KEEP_SIDES_ON then
        for _, entry in ipairs({ { "behind", "KeepBehind" }, { "left", "KeepLeft" }, { "right", "KeepRight" } }) do
            local o = keep:addOption(tr(entry[2]), entry[1], BridgeMenu.onKeepSide)
            if side == entry[1] then o.isDisabled = true end
        end
    end
end



local function iconSize(btn)
    local w = 48
    pcall(function() w = btn:getWidth() end)
    for _, size in ipairs({ 128, 96, 80, 64, 48 }) do
        if w >= size then return size end
    end
    return 48
end



local SIDEBAR_FIRST = 5
local SIDEBAR_STABLE = 30

BridgeMenu.VANILLA_BTNS = { "invBtn", "healthBtn", "craftingBtn", "buildBtn", "movableBtn",
    "zoneBtn", "mapBtn", "searchBtn", "safetyBtn", "adminBtn", "debugBtn", "clientBtn",
    "arfBtn", "warManagerBtn" }





function BridgeMenu.sidebarTarget(panel, btn, screenH)
    local bottom, last = 0, nil


    for _, key in ipairs(BridgeMenu.VANILLA_BTNS) do
        local child = panel[key]
        if child ~= nil and child ~= btn and child:isVisible() and child:getBottom() > bottom then
            bottom, last = child:getBottom(), child
        end
    end
    if last == nil then return nil end
    local x, y = 0, bottom + UI_BORDER_SPACING + 5
    if screenH ~= nil and screenH > 0 and panel:getAbsoluteY() + y + btn:getHeight() > screenH then
        x, y = last:getRight() + UI_BORDER_SPACING, last:getY()
    end
    return x, y
end









function BridgeMenu.sidebarStep(panel, btn, screenH)
    local x, y = BridgeMenu.sidebarTarget(panel, btn, screenH)
    if x == nil then return false end
    local S = panel.notAlonePlace
    if S == nil then S = {} panel.notAlonePlace = S end
    if S.x == x and S.y == y then S.n = (S.n or 0) + 1 else S.x, S.y, S.n = x, y, 1 end
    local need = S.shown and SIDEBAR_STABLE or SIDEBAR_FIRST
    if S.n < need then return false end
    local moved = false
    if btn:getX() ~= x or btn:getY() ~= y then
        btn:setX(x)
        btn:setY(y)
        moved = true
    end
    if panel:getHeight() < btn:getBottom() then panel:setHeight(btn:getBottom()) end
    if panel:getWidth() < btn:getRight() then panel:setWidth(btn:getRight()) end
    if not S.shown then
        S.shown = true
        btn:setVisible(true)
        moved = true
    end
    return moved
end


function BridgeMenu.onButton(panel, button)
    if Bridge == nil or Bridge.store == nil or BridgeWindow == nil then return end
    local x = panel:getAbsoluteX() + button:getRight() + 4
    local y = panel:getAbsoluteY() + button:getY()

    pcall(function()
        local screenH = getCore():getScreenHeight()
        if y + BridgeWindow.HEIGHT > screenH then y = math.max(0, screenH - BridgeWindow.HEIGHT) end
    end)
    BridgeWindow.toggle(x, y)
end


function BridgeMenu.onButtonMenu(panel, button)
    if Bridge == nil or Bridge.store == nil then return end
    local playerNum = 0
    pcall(function() playerNum = panel.chr:getPlayerNum() end)
    local x = panel:getAbsoluteX() + button:getRight() + 4
    local y = panel:getAbsoluteY() + button:getY()
    local context = ISContextMenu.get(playerNum, x, y)
    BridgeMenu.fill(context, playerNum, true)
end


if ISEquippedItem ~= nil and not ISEquippedItem.notAloneWrapped then
    local originalInit = ISEquippedItem.initialise
    ISEquippedItem.initialise = function(self, ...)
        originalInit(self, ...)
        pcall(function()
            if self.chr == nil or self.chr:getPlayerNum() ~= 0 or self.invBtn == nil then return end
            local w, h = self.invBtn:getWidth(), self.invBtn:getHeight()
            local size = iconSize(self.invBtn)
            self.notAloneOff = getTexture("media/ui/Sidebar/NotAlone_Off_" .. size .. ".png")
            self.notAloneOn = getTexture("media/ui/Sidebar/NotAlone_On_" .. size .. ".png")
            local y = self:getHeight() + UI_BORDER_SPACING + 5
            local btn = ISButton:new(0, y, w, h, "", self, BridgeMenu.onButton)
            btn:setImage(self.notAloneOff)
            btn.internal = "NOTALONE"
            btn:initialise()
            btn:instantiate()
            btn:setDisplayBackground(false)
            btn:ignoreWidthChange()
            btn:ignoreHeightChange()
            local panel = self
            btn.onRightMouseUp = function(_, x, y) BridgeMenu.onButtonMenu(panel, btn) end
            self:addChild(btn)


            btn:setVisible(false)
            self.notAloneBtn = btn
            self.notAloneLit = false
            self:addMouseOverToolTipItem(btn, tr("Companion"))
            self:setHeight(btn:getBottom())
        end)
    end

    local originalPrerender = ISEquippedItem.prerender
    ISEquippedItem.prerender = function(self, ...)
        originalPrerender(self, ...)
        local btn = self.notAloneBtn
        if btn == nil or Bridge == nil then return end
        pcall(function()
            local lit = BridgeMenu.lit()
            if lit ~= self.notAloneLit then
                self.notAloneLit = lit
                btn:setImage(lit and self.notAloneOn or self.notAloneOff)
            end

            local screenH = nil
            pcall(function() screenH = getCore():getScreenHeight() end)
            BridgeMenu.sidebarStep(self, btn, screenH)

            if Bridge.every(30) then
                for _, item in ipairs(self.mouseOverList or {}) do
                    if item.object == btn then item.displayString = BridgeMenu.status() end
                end
            end
        end)
    end
    ISEquippedItem.notAloneWrapped = true
    log("sidebar button wrapped")
end





local function underMouse(z, playerNum)
    local hit = false
    pcall(function()
        local core = getCore()
        local zoom = core:getZoom(playerNum)
        local height = 128 * Core.getTileScale() / 2 / zoom
        local half = height * 0.3
        local sx = isoToScreenX(playerNum, z:getX(), z:getY(), z:getZ())
        local sy = isoToScreenY(playerNum, z:getX(), z:getY(), z:getZ())
        local mx, my = getMouseX(), getMouseY()
        hit = mx >= sx - half and mx <= sx + half and my <= sy + height * 0.1 and my >= sy - height
    end)
    return hit
end




local function bodyNear(worldobjects, playerNum)
    local pn = playerNum or 0
    local me = BridgeData.me()
    local mine, others = {}, {}
    if Bridge.alive() then mine[Bridge.body] = true end
    for z, info in pairs(Bridge.bodiesSeen()) do
        if info.who == me then mine[z] = true else others[z] = true end
    end
    for z in pairs(mine) do if underMouse(z, pn) then return true end end
    for z in pairs(others) do if underMouse(z, pn) then return false end end
    local sq = nil
    for _, o in ipairs(worldobjects or {}) do
        pcall(function() sq = o:getSquare() end)
        if sq ~= nil then break end
    end
    if sq == nil then return false end
    local function dist2(z)
        local d = nil
        pcall(function()
            if math.abs(z:getZ() - sq:getZ()) >= 1 then return end
            local dx, dy = z:getX() - (sq:getX() + 0.5), z:getY() - (sq:getY() + 0.5)
            d = dx * dx + dy * dy
        end)
        return d
    end
    local best, bestMine = 2.25, false
    local found = false
    for z in pairs(mine) do
        local d = dist2(z)
        if d ~= nil and d <= best then best, bestMine, found = d, true, true end
    end
    for z in pairs(others) do
        local d = dist2(z)
        if d ~= nil and d < best then best, bestMine, found = d, false, true end
    end
    return found and bestMine
end

function BridgeMenu.onWorldMenu(playerNum, context, worldobjects, test)
    if test or Bridge == nil or Bridge.store == nil then return end

    if playerNum ~= nil and playerNum ~= 0 then return end
    local ok, yes = pcall(bodyNear, worldobjects, playerNum)
    if not ok or not yes then return end
    local option = context:addOptionOnTop(name())
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(option, sub)
    BridgeMenu.fill(sub, playerNum)
end

Events.OnFillWorldObjectContextMenu.Add(BridgeMenu.onWorldMenu)

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if Bridge ~= nil and Bridge.claimMenuFix ~= nil then pcall(Bridge.claimMenuFix, playerNum, context, worldobjects, test) end
end)
log("loaded")

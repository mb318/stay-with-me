






BridgeChat = BridgeChat or {}
BridgeChat.file = "bridge/chat.txt"
BridgeChat.seq = 0
BridgeChat.ready = false

local function log(text) if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeChat] " .. tostring(text)) end end
local function warn(text) print("[BridgeChat] " .. tostring(text)) end


function BridgeChat.fromCodes(...)
    local t = { ... }
    local out = {}
    for i = 1, #t do out[i] = string.char(t[i]) end
    return table.concat(out)
end


function BridgeChat.companionName()
    if Bridge ~= nil and Bridge.companionName ~= nil then return Bridge.companionName() end
    return BridgeData.DEFAULT_NAME
end


function BridgeChat.toHex(text)
    local out = {}
    for i = 1, #text do
        local c = string.byte(text, i)
        if c < 0x80 then
            out[#out + 1] = string.format("%02x", c)
        elseif c < 0x800 then
            out[#out + 1] = string.format("%02x%02x", 0xC0 + math.floor(c / 64), 0x80 + c % 64)
        else
            out[#out + 1] = string.format("%02x%02x%02x", 0xE0 + math.floor(c / 4096),
                0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
        end
    end
    return table.concat(out)
end


function BridgeChat.fromHex(hex)
    local bytes = {}
    for i = 1, #hex - 1, 2 do
        local b = tonumber(string.sub(hex, i, i + 1), 16)
        if b then bytes[#bytes + 1] = b end
    end
    local out, i = {}, 1
    while i <= #bytes do
        local b = bytes[i]
        local cp, n
        if b < 0x80 then cp, n = b, 1
        elseif b >= 0xF0 then cp, n = 0x3F, 4
        elseif b >= 0xE0 then cp, n = (b - 0xE0) * 4096 + ((bytes[i + 1] or 0x80) - 0x80) * 64 + ((bytes[i + 2] or 0x80) - 0x80), 3
        elseif b >= 0xC0 then cp, n = (b - 0xC0) * 64 + ((bytes[i + 1] or 0x80) - 0x80), 2
        else cp, n = 0x3F, 1 end
        out[#out + 1] = string.char(cp)
        i = i + n
    end
    return table.concat(out)
end



local function timestamp()
    local ok, text = pcall(function()
        local gt = getGameTime()
        return string.format("%02d:%02d", gt:getHour(), gt:getMinutes())
    end)
    return ok and text or "--:--"
end


function BridgeChat.addLine(author, text, r, g, b)
    if not BridgeChat.ready or ISChat.instance == nil then return false end
    local prefix = string.format("<RGB:0.55,0.55,0.55>[%s] <RGB:%.2f,%.2f,%.2f>%s: <RGB:1,1,1>",
        timestamp(), r, g, b, tostring(author))
    local message = {
        getTextWithPrefix = function() return prefix .. tostring(text) end,
        getAuthor = function() return tostring(author) end,
        setText = function() end,
    }
    local ok, err = pcall(function() ISChat.addLineInChat(message, 0) end)
    if not ok then warn("addLine failed: " .. tostring(err)) end
    return ok
end



function BridgeChat.sayCompanion(text)
    if isClient() then
        local ok = pcall(function() sendClientCommand(BridgeData.owner(), "Bridge", "say", { text = text }) end)
        return ok
    end
    return BridgeChat.addLine(BridgeChat.companionName(), text, 0.95, 0.55, 0.75)
end



function BridgeChat.bridgeOn()
    local on = false
    pcall(function()
        local reader = getFileReader("bridge/in.txt", false)
        if reader ~= nil then
            on = true
            reader:close()
        end
    end)
    return on
end



function BridgeChat.onAddMessage(message, tabID)
    if not isClient() then return end
    if Bridge == nil or not Bridge.bridgeOn then return end
    local author, text = nil, nil
    pcall(function() author = message:getAuthor() end)
    pcall(function() text = message:getText() end)
    if author == nil or text == nil or text == "" then return end
    if tostring(author) == BridgeChat.companionName() then return end
    BridgeChat.seq = BridgeChat.seq + 1
    pcall(function()
        local writer = getFileWriter(BridgeChat.file, true, true)
        writer:write(string.format("%d %s %s\r\n", BridgeChat.seq, BridgeChat.toHex(tostring(author)), BridgeChat.toHex(tostring(text))))
        writer:close()
    end)
end


function BridgeChat.onCommandEntered()
    local chat = ISChat.instance
    if chat == nil then return end
    local text = chat.textEntry:getText()
    chat:unfocus()
    if text == nil then return end
    text = string.gsub(text, "[\n\r]", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    text = string.gsub(text, "^/say%s+", "")
    text = string.gsub(text, "^/s%s+", "")
    if text == "" then return end

    pcall(function() chat:logChatCommand(text) end)

    local red = BridgeData.owner()
    local name = "Player"
    pcall(function() name = red:getDisplayName() end)
    BridgeChat.addLine(name, text, 0.75, 0.85, 1.0)
    if BridgeData.overheadOk(text) then pcall(function() red:Say(text) end) end

    BridgeChat.seq = BridgeChat.seq + 1
    local ok, err = pcall(function()
        local writer = getFileWriter(BridgeChat.file, true, true)
        writer:write(string.format("%d %s %s\r\n", BridgeChat.seq, BridgeChat.toHex(name), BridgeChat.toHex(text)))
        writer:close()
    end)
    if not ok then warn("write failed: " .. tostring(err)) end

    pcall(function() doKeyPress(false) end)
    chat.timerTextEntry = 20
end

function BridgeChat.create()
    if isClient() then
        BridgeChat.ready = true
        Events.OnAddMessage.Add(BridgeChat.onAddMessage)
        log("multiplayer: native chat, listening to messages")
        return
    end
    if ISChat.instance ~= nil then
        log("native chat present, not creating")
        return
    end
    if not BridgeChat.bridgeOn() then
        log("single player without the bridge: no chat window")
        return
    end
    local ok, err = pcall(function()
        ISChat.chat = ISChat:new(15, getCore():getScreenHeight() - 400, 500, 200)
        ISChat.chat:initialise()
        ISChat.chat:addToUIManager()
        ISChat.chat:bringToTop()
        ISLayoutManager.RegisterWindow('chat', ISChat, ISChat.chat)

        Events.OnMouseDown.Add(ISChat.unfocusEvent)
        Events.OnKeyPressed.Add(ISChat.onToggleChatBox)
        Events.OnKeyKeepPressed.Add(ISChat.onKeyKeepPressed)

        ISChat.onTabAdded("General", 0)
        ISChat.instance.textEntry.onCommandEntered = BridgeChat.onCommandEntered



        ISChat.chat:setVisible(false)


        local original = ISChat.onActivateView
        ISChat.onActivateView = function(...)
            local args = { ... }
            pcall(function() original(unpack(args)) end)
        end
    end)
    if not ok then
        warn("create failed: " .. tostring(err))
        return
    end
    BridgeChat.ready = true
    log("chat window created")
end

Events.OnGameStart.Add(BridgeChat.create)
log("loaded")

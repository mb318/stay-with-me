BridgeLooks = BridgeLooks or {}

BridgeLooks.FILE = "stay_with_me_looks.txt"
BridgeLooks.VERSION = 1
BridgeLooks.NAME_MAX = 40
BridgeLooks.MAX_LOOKS = 100

local READ_CAP = 500
local KEYS = { "skin", "hair", "color", "face", "details", "muscle", "makeup" }
local ESCAPE = {
    ["%"] = "%25", [";"] = "%3B", ["="] = "%3D", ["|"] = "%7C",
    ["\n"] = "%0A", ["\r"] = "%0D", ["\t"] = "%09",
}

local function esc(s)
    return (string.gsub(tostring(s or ""), "[%%;=|\n\r\t]", function(ch) return ESCAPE[ch] or ch end))
end

local function unesc(s)
    if type(s) ~= "string" then return nil end
    local out, i = {}, 1
    while i <= #s do
        local ch = string.sub(s, i, i)
        if ch == "%" then
            local hex = string.sub(s, i + 1, i + 2)
            if string.match(hex, "^%x%x$") == nil then return nil end
            local b = string.char(tonumber(hex, 16))
            if b == "\0" then return nil end
            out[#out + 1] = b
            i = i + 3
        else
            out[#out + 1] = ch
            i = i + 1
        end
    end
    return table.concat(out)
end




local function cut(text, maxChars)
    for k = 1, #text do
        if string.byte(text, k) > 255 then return string.sub(text, 1, maxChars) end
    end
    local n, i, last = 0, 1, 0
    while i <= #text do
        local b = string.byte(text, i)
        local len = 1
        if b >= 240 then len = 4 elseif b >= 224 then len = 3 elseif b >= 192 then len = 2 end
        if i + len - 1 > #text then break end
        n = n + 1
        last = i + len - 1
        i = i + len
        if n >= maxChars then return string.sub(text, 1, last) end
    end
    if last == 0 then return "" end
    return string.sub(text, 1, last)
end

function BridgeLooks.cleanName(text)
    if text == nil then return nil end
    text = tostring(text)
    if string.find(text, "\0", 1, true) ~= nil then text = string.gsub(text, "%z", "") end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then return nil end
    text = cut(text, BridgeLooks.NAME_MAX)
    text = string.gsub(text, "%s+$", "")
    if text == "" then return nil end
    return text
end

local function textOr(key, fallback)
    if type(getTextOrNull) ~= "function" then return fallback end
    local t = getTextOrNull("IGUI_NotAlone_" .. key)
    if type(t) ~= "string" or t == "" or t == "IGUI_NotAlone_" .. key then return fallback end
    return t
end

function BridgeLooks.defaultName()
    return textOr("LookDefault", "As I found her")
end

local function dec4(v)
    local n = tonumber(v)
    if n == nil or n ~= n then n = 0 end
    if n < 0 then n = 0 end
    if n > 1 then n = 1 end
    local scaled = math.floor(n * 10000 + 0.5)
    if scaled > 10000 then scaled = 10000 end
    local whole = math.floor(scaled / 10000)
    local frac = scaled - whole * 10000
    local s = tostring(frac)
    while #s < 4 do s = "0" .. s end
    return tostring(whole) .. "." .. s
end

local function splitComma(s)
    local out = {}
    if type(s) ~= "string" or s == "" then return out end
    local start = 1
    while start <= #s do
        local comma = string.find(s, ",", start, true)
        local part
        if comma == nil then
            part = string.sub(s, start)
            start = #s + 1
        else
            part = string.sub(s, start, comma - 1)
            start = comma + 1
        end
        if part ~= "" then out[#out + 1] = part end
    end
    return out
end

local function copyList(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for i = 1, #list do out[i] = list[i] end
    return out
end

local function listEq(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function colorFrom(text)
    if type(text) ~= "string" then return nil end
    local r, g, b = string.match(text, "^([^,]*),([^,]*),([^,]*)$")
    if r == nil then return nil end
    return BridgeData.cleanHairColor({ r = tonumber(r), g = tonumber(g), b = tonumber(b) })
end

local function colorClose(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return math.abs((a.r or 0) - (b.r or 0)) < 0.01
        and math.abs((a.g or 0) - (b.g or 0)) < 0.01
        and math.abs((a.b or 0) - (b.b or 0)) < 0.01
end

local function rawOf(look)
    if type(look) == "table" and type(look.raw) == "table" then return look.raw end
    return {}
end

local function faceToken(raw)
    if type(raw) ~= "string" or raw == "" then return "" end
    local cleaned = BridgeData.cleanFace(raw)
    if type(cleaned) ~= "string" or cleaned == "" then return raw end
    return cleaned
end

local function faceOfRec(rec)
    local raw = ""
    if type(rec) == "table" and type(rec.face) == "string" then raw = rec.face end
    return faceToken(raw)
end

local function detailsToken(raw)
    local items = splitComma(raw or "")
    local cleaned = BridgeData.cleanDetails(items) or {}
    if #items > 0 and #cleaned == 0 then return items end
    return cleaned
end

local function detailsOfRec(rec)
    if type(rec) ~= "table" or rec.details == nil then return detailsToken("") end
    if type(rec.details) == "string" then return detailsToken(rec.details) end
    if type(rec.details) == "table" then return detailsToken(table.concat(rec.details, ",")) end
    return {}
end

local function makeupToken(raw)
    local items = splitComma(raw or "")
    local cleaned = BridgeData.cleanMakeup(items) or {}
    if #items > 0 and #cleaned == 0 then return items end
    return cleaned
end

local function makeupOfRec(rec)
    if type(rec) ~= "table" or rec.makeup == nil then return makeupToken("") end
    if type(rec.makeup) == "string" then return makeupToken(rec.makeup) end
    if type(rec.makeup) == "table" then return makeupToken(table.concat(rec.makeup, ",")) end
    return {}
end

local function encode(look)
    if type(look) ~= "table" or type(look.name) ~= "string" or type(look.has) ~= "table" then return nil end
    local raw = rawOf(look)
    local parts = {}
    for i = 1, #KEYS do
        local k = KEYS[i]
        if look.has[k] == true and raw[k] ~= nil then
            parts[#parts + 1] = k .. "=" .. esc(raw[k])
        end
    end
    return esc(look.name) .. "\t" .. (look.builtin == true and "1" or "0") .. "\t" .. table.concat(parts, ";")
end

function BridgeLooks.parse(line)
    if type(line) ~= "string" or line == "" or #line > 8000 then return nil end
    if string.sub(line, -1) == "\r" then line = string.sub(line, 1, -2) end
    local nameEsc, flag, payload = string.match(line, "^([^\t]*)\t([01])\t(.*)$")
    if nameEsc == nil then return nil end
    local name = unesc(nameEsc)
    if name == nil then return nil end
    name = BridgeLooks.cleanName(name)
    if name == nil then return nil end
    local look = { name = name, builtin = flag == "1", has = {}, raw = {} }
    local text, start = payload or "", 1
    while start <= #text do
        local semi = string.find(text, ";", start, true)
        local part
        if semi == nil then
            part = string.sub(text, start)
            start = #text + 1
        else
            part = string.sub(text, start, semi - 1)
            start = semi + 1
        end
        if part ~= "" then
            local eq = string.find(part, "=", 1, true)
            if eq ~= nil and eq > 1 then
                local key = string.sub(part, 1, eq - 1)
                local value = unesc(string.sub(part, eq + 1))
                local known = false
                for i = 1, #KEYS do
                    if KEYS[i] == key then known = true break end
                end
                if known and value ~= nil then
                    look.has[key] = true
                    look.raw[key] = value
                end
            end
        end
    end
    if not (look.has.skin or look.has.hair or look.has.color) then return nil end
    return look
end

local function readLines()
    if type(getFileReader) ~= "function" then return nil end
    local reader = getFileReader(BridgeLooks.FILE, false)
    if reader == nil then return nil end
    if type(reader.readLine) ~= "function" then
        if type(reader.close) == "function" then reader:close() end
        return {}
    end
    local lines, guard = {}, 0
    while guard < 4000 do
        guard = guard + 1
        local line = reader:readLine()
        if line == nil or type(line) ~= "string" then break end
        if string.sub(line, -1) == "\r" then line = string.sub(line, 1, -2) end
        if line ~= "" then lines[#lines + 1] = line end
    end
    if type(reader.close) == "function" then reader:close() end
    return lines
end

local function builtin()
    local color = BridgeData.DEFAULT_HAIR_COLOR
    local look = {
        name = BridgeLooks.defaultName(),
        builtin = true,
        has = { skin = true, hair = true, color = true, face = true, details = true, muscle = true, makeup = true },
        raw = {
            skin = BridgeData.DEFAULT_SKIN,
            hair = BridgeData.DEFAULT_HAIR,
            color = dec4(color.r) .. "," .. dec4(color.g) .. "," .. dec4(color.b),
            face = "",
            details = "",
            muscle = "0",
            makeup = "",
        },
    }
    return look
end

local function readLooks()
    if BridgeLooks._cache ~= nil then return BridgeLooks._cache end
    local lines = readLines()
    if lines == nil then
        BridgeLooks._cache = { builtin() }
        BridgeLooks._virtual = true
        BridgeLooks._readonly = false
        return BridgeLooks._cache
    end
    local mode, foreign, truncated = "seek", false, false
    local list, seen = {}, {}
    for i = 1, #lines do
        local line = lines[i]
        if #line > 8000 then
            line = ""
        end
        local ver = string.match(line, "^VERSION=(%d+)%s*$")
        if ver ~= nil then
            if tonumber(ver) ~= 1 then
                foreign = true
                mode = "stop"
            elseif mode == "seek" then
                mode = "read"
            end
        elseif mode == "read" then
            if #list >= READ_CAP then
                truncated = true
                mode = "stop"
            else
                local look = BridgeLooks.parse(line)
                if look ~= nil and seen[look.name] ~= true then
                    seen[look.name] = true
                    list[#list + 1] = look
                end
            end
        end
    end
    local sawBuiltin = false
    for i = 1, #list do
        if list[i].builtin == true then
            if sawBuiltin then list[i].builtin = false else sawBuiltin = true end
        end
    end
    BridgeLooks._readonly = foreign or truncated
    BridgeLooks._virtual = #list == 0

    local default = BridgeLooks.defaultName()
    local at = nil
    for i = 1, #list do
        if list[i].builtin == true then at = i break end
    end
    if at == nil then
        for i = 1, #list do
            if list[i].name == default then list[i].builtin = true at = i break end
        end
    end
    if at == nil then
        table.insert(list, 1, builtin())
    else
        local b = table.remove(list, at)
        local taken = false
        for i = 1, #list do
            if list[i].name == default then taken = true break end
        end
        if not taken then b.name = default end
        table.insert(list, 1, b)
    end
    BridgeLooks._cache = list
    return list
end

local function store(list)
    if BridgeLooks._readonly then return false end
    if type(list) ~= "table" or #list < 1 then return false end
    if type(getFileWriter) ~= "function" then return false end
    local lines = { "VERSION=1" }
    for i = 1, #list do
        local line = encode(list[i])
        if line == nil then return false end
        lines[#lines + 1] = line
    end
    local writer = getFileWriter(BridgeLooks.FILE, true, false)
    if writer == nil or type(writer.write) ~= "function" then return false end
    writer:write(table.concat(lines, "\n") .. "\n")
    if type(writer.close) == "function" then writer:close() end
    BridgeLooks._cache = list
    BridgeLooks._virtual = false
    return true
end

function BridgeLooks.forget()
    BridgeLooks._cache = nil
    BridgeLooks._virtual = nil
    BridgeLooks._readonly = nil
end

function BridgeLooks.locked()
    readLooks()
    return BridgeLooks._readonly == true
end

function BridgeLooks.all()
    local src = readLooks()
    local out = {}
    for i = 1, #src do out[i] = src[i] end
    return out
end

function BridgeLooks.find(name)
    local clean = BridgeLooks.cleanName(name)
    if clean == nil then return nil end
    local list = readLooks()
    for i = 1, #list do
        if list[i].name == clean then return list[i] end
    end
    return nil
end

local function rawFrom(fields)
    local color = fields.color
    local details, makeup = fields.details or {}, fields.makeup or {}
    return {
        skin = fields.skin,
        hair = fields.hair,
        color = dec4(color.r) .. "," .. dec4(color.g) .. "," .. dec4(color.b),
        face = fields.face or "",
        details = table.concat(details, ","),
        muscle = tostring(fields.muscle),
        makeup = table.concat(makeup, ","),
    }
end

function BridgeLooks.capture(c)
    if type(c) ~= "table" then c = {} end
    local color = BridgeData.cleanHairColor(c.hairColor) or BridgeData.hairColorOf(c)
    local details = copyList(BridgeData.cleanDetails(c.details) or {})
    local makeup = copyList(BridgeData.cleanMakeup(c.makeup) or {})
    local fields = {
        skin = BridgeData.cleanSkin(c.skin) or BridgeData.skinOf(c),
        hair = BridgeData.cleanHair(c.hair) or BridgeData.hairOf(c),
        color = { r = color.r, g = color.g, b = color.b },
        face = BridgeData.cleanFace(c.face) or "",
        details = details,
        muscle = BridgeData.muscleOf(c),
        makeup = makeup,
    }
    return {
        has = { skin = true, hair = true, color = true, face = true, details = true, muscle = true, makeup = true },
        raw = rawFrom(fields),
    }
end

function BridgeLooks.save(name, c)
    readLooks()
    if BridgeLooks._readonly then return nil end
    local clean = BridgeLooks.cleanName(name)
    if clean == nil then return nil end
    local snap = BridgeLooks.capture(c)
    snap.name = clean
    local list = BridgeLooks.all()
    local replaced = false
    for i = 1, #list do
        if list[i].name == clean then
            if list[i].builtin == true then return nil end
            snap.builtin = false
            list[i] = snap
            replaced = true
            break
        end
    end
    if not replaced then
        if #list >= BridgeLooks.MAX_LOOKS then return nil end
        snap.builtin = false
        list[#list + 1] = snap
    end
    if not store(list) then return nil end
    return snap
end

function BridgeLooks.canDelete(name)
    readLooks()
    if BridgeLooks._readonly then return false end
    if type(name) ~= "string" then return false end
    local list = readLooks()
    for i = 1, #list do
        if list[i].name == name then return list[i].builtin ~= true end
    end
    return false
end

function BridgeLooks.isBuiltin(name)
    local look = BridgeLooks.find(name)
    return look ~= nil and look.builtin == true
end

function BridgeLooks.delete(name)
    if not BridgeLooks.canDelete(name) then return false end
    local list, out = BridgeLooks.all(), {}
    for i = 1, #list do
        if list[i].name ~= name then out[#out + 1] = list[i] end
    end
    if #out < 1 then return false end
    return store(out)
end

function BridgeLooks.same(look, rec)
    if type(look) ~= "table" or type(look.has) ~= "table" or type(rec) ~= "table" then return false end
    local raw, any = rawOf(look), false
    if look.has.skin then
        any = true
        local skin = BridgeData.cleanSkin(raw.skin)
        if skin == nil or BridgeData.skinOf(rec) ~= skin then return false end
    elseif BridgeData.skinOf(rec) ~= BridgeData.DEFAULT_SKIN then
        return false
    end
    if look.has.hair then
        any = true
        local hair = BridgeData.cleanHair(raw.hair)
        if hair == nil or BridgeData.hairOf(rec) ~= hair then return false end
    elseif BridgeData.hairOf(rec) ~= BridgeData.DEFAULT_HAIR then
        return false
    end
    if look.has.color then
        any = true
        local col = colorFrom(raw.color)
        if col == nil or not colorClose(BridgeData.hairColorOf(rec), col) then return false end
    elseif not colorClose(BridgeData.hairColorOf(rec), BridgeData.DEFAULT_HAIR_COLOR) then
        return false
    end
    if look.has.face then
        any = true
        if faceToken(raw.face) ~= faceOfRec(rec) then return false end
    elseif faceOfRec(rec) ~= "" then
        return false
    end
    if look.has.details then
        any = true
        if not listEq(detailsToken(raw.details), detailsOfRec(rec)) then return false end
    elseif #detailsOfRec(rec) > 0 then
        return false
    end
    if look.has.muscle then
        any = true
        local n = tonumber(raw.muscle)
        if n == nil or BridgeData.muscleOf(rec) ~= BridgeData.muscleOf({ muscle = n }) then return false end
    elseif BridgeData.muscleOf(rec) ~= 0 then
        return false
    end
    if look.has.makeup then
        any = true
        if not listEq(makeupToken(raw.makeup), makeupOfRec(rec)) then return false end
    elseif #makeupOfRec(rec) > 0 then
        return false
    end
    return any
end

function BridgeLooks.matchName(rec)
    if type(rec) ~= "table" then return nil end
    local list = readLooks()
    for i = 1, #list do
        if BridgeLooks.same(list[i], rec) then return list[i].name end
    end
    return nil
end


local MOD_KEY = "StayWithMeLook"

local function ownerData()
    local data = nil
    pcall(function()
        local p = nil
        if type(getSpecificPlayer) == "function" then p = getSpecificPlayer(0) end
        if p == nil and type(getPlayer) == "function" then p = getPlayer() end
        if p ~= nil then data = p:getModData() end
    end)
    return data
end

function BridgeLooks.remember(name)
    local data = ownerData()
    if data == nil then return end
    if type(name) == "string" and name ~= "" then data[MOD_KEY] = name else data[MOD_KEY] = nil end
end

function BridgeLooks.remembered()
    local data = ownerData()
    if data == nil or type(data[MOD_KEY]) ~= "string" then return nil end
    return data[MOD_KEY]
end


function BridgeLooks.current(rec)
    local look = BridgeLooks.find(BridgeLooks.remembered())
    if look ~= nil then return look.name end
    local name = BridgeLooks.matchName(rec)
    if name ~= nil then return name end
    return readLooks()[1].name
end

function BridgeLooks.shown(rec)
    return BridgeLooks.current(rec)
end

function BridgeLooks.applyTo(look, c)
    if type(look) ~= "table" or type(c) ~= "table" or type(look.has) ~= "table" then return false end
    local raw = rawOf(look)
    if look.has.skin then
        local skin = BridgeData.cleanSkin(raw.skin)
        if skin ~= nil then c.skin = skin end
    end
    if look.has.hair then
        local hair = BridgeData.cleanHair(raw.hair)
        if hair ~= nil then c.hair = hair end
    end
    if look.has.color then
        local col = colorFrom(raw.color)
        if col ~= nil then c.hairColor = { r = col.r, g = col.g, b = col.b } end
    end
    if look.has.face and BridgeData.spnccFaces() ~= nil then
        local face = raw.face or ""
        if face == "" then c.face = nil
        else
            local cleaned = BridgeData.cleanFace(face)
            if cleaned ~= nil then c.face = cleaned end
        end
    end
    if look.has.details and BridgeData.spnccDetails() ~= nil then
        local text = raw.details or ""
        local items = splitComma(text)
        local cleaned = BridgeData.cleanDetails(items) or {}
        if text == "" or #cleaned > 0 or #items == 0 then c.details = copyList(cleaned) end
    end
    if look.has.muscle and BridgeData.spnccMuscle() ~= nil then
        local n = tonumber(raw.muscle)
        if n ~= nil and n == n then c.muscle = BridgeData.muscleOf({ muscle = n }) end
    end
    if look.has.makeup and BridgeData.makeupList() ~= nil then
        local text = raw.makeup or ""
        local items = splitComma(text)
        local cleaned = BridgeData.cleanMakeup(items) or {}
        if text == "" or #cleaned > 0 or #items == 0 then c.makeup = copyList(cleaned) end
    end
    return true
end

if BridgeLog ~= nil and type(BridgeLog.on) == "function" and BridgeLog.on() then print("[BridgeLooks] loaded") end

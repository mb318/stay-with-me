

























BridgeItems = BridgeItems or {}

local function try(f) pcall(f) end







local ESCAPED = { ["%"] = "%25", [";"] = "%3B", [","] = "%2C", ["="] = "%3D", ["|"] = "%7C", ["~"] = "%7E",
                  ["\n"] = "%0A", ["\r"] = "%0D" }
local UNESCAPED = {}
for ch, code in pairs(ESCAPED) do UNESCAPED[string.sub(code, 2)] = ch end



function BridgeItems.esc(s)
    return (string.gsub(tostring(s), "[%%;,=|~\n\r]", function(ch) return ESCAPED[ch] or ch end))
end

function BridgeItems.unesc(s)
    return (string.gsub(tostring(s), "%%(%x%x)", function(hex) return UNESCAPED[string.upper(hex)] or ("%" .. hex) end))
end




function BridgeItems.packTable(t, depth)
    depth = depth or 1
    if type(t) ~= "table" or depth > 3 then return nil end
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
    end

    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = t[k]
        local key = (type(k) == "number") and ("#" .. tostring(k)) or BridgeItems.esc(k)
        local vt = type(v)
        if vt == "string" then parts[#parts + 1] = key .. "~s~" .. BridgeItems.esc(v)
        elseif vt == "number" then parts[#parts + 1] = key .. "~n~" .. tostring(v)
        elseif vt == "boolean" then parts[#parts + 1] = key .. "~b~" .. (v and "1" or "0")
        elseif vt == "table" then
            local sub = BridgeItems.packTable(v, depth + 1)
            if sub ~= nil then parts[#parts + 1] = key .. "~t~" .. BridgeItems.esc(sub) end
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "|")
end

function BridgeItems.unpackTable(text, depth)
    depth = depth or 1
    local out = {}
    if type(text) ~= "string" or text == "" or depth > 3 then return out end
    for part in string.gmatch(text, "[^|]+") do
        local key, kind, value = string.match(part, "^([^~]*)~(%a)~(.*)$")
        if key ~= nil then
            local k = nil
            if string.sub(key, 1, 1) == "#" then k = tonumber(string.sub(key, 2)) else k = BridgeItems.unesc(key) end
            if k ~= nil then
                if kind == "s" then out[k] = BridgeItems.unesc(value)
                elseif kind == "n" then out[k] = tonumber(value)
                elseif kind == "b" then out[k] = (value == "1")
                elseif kind == "t" then out[k] = BridgeItems.unpackTable(BridgeItems.unesc(value), depth + 1) end
            end
        end
    end
    return out
end



BridgeItems.MD_MAX = 800
BridgeItems.PAGES_MAX = 1500

local function warn(text) print("[BridgeItems] " .. tostring(text)) end
local warned = {}
local function warnOnce(key, text)
    if warned[key] then return end
    warned[key] = true
    warn(text)
end



local function plainCopy(t, depth)
    if depth > 3 then return nil end
    local out, n = {}, 0
    for k, v in pairs(t) do
        local kt, vt = type(k), type(v)
        if kt == "string" or kt == "number" then
            if vt == "string" or vt == "number" or vt == "boolean" then
                out[k] = v n = n + 1
            elseif vt == "table" then
                local sub = plainCopy(v, depth + 1)
                if sub ~= nil then out[k] = sub n = n + 1 end
            end
        end
    end
    if n == 0 then return nil end
    return out
end


function BridgeItems.record(item, deep)
    local rec = { t = item:getFullType() }

    try(function()
        local c = item:getCondition()
        local max = nil
        pcall(function() max = item:getConditionMax() end)
        if max == nil or c ~= max then rec.c = c end
    end)



    try(function()
        if item.hasSharpness ~= nil and item:hasSharpness() then
            local sh, max = item:getSharpness(), 1.0
            pcall(function() max = item:getMaxSharpness() end)
            if sh < max - 0.0005 then rec.sh = sh end
        end
    end)
    try(function()
        if item.hasHeadCondition ~= nil and item:hasHeadCondition() then
            local hc = item:getHeadCondition()
            if hc ~= item:getHeadConditionMax() then rec.hc = hc end
        end
    end)
    try(function()
        local fc = item:getFluidContainer()
        if fc == nil then return end
        if fc:isEmpty() then
            rec.fe = true
        else
            rec.fl = fc:getPrimaryFluid():getFluidTypeString()
            rec.fa = fc:getAmount()
        end
    end)
    try(function()
        if item:IsWeapon() then
            local parts = item:getAllWeaponParts()
            if parts ~= nil and parts:size() > 0 then
                local names = {}
                for i = 0, parts:size() - 1 do names[#names + 1] = parts:get(i):getFullType() end
                rec.wp = table.concat(names, "+")
            end
        end
    end)
    try(function() if item:IsDrainable() then rec.u = item:getCurrentUsesFloat() end end)
    try(function() if item:IsFood() then rec.a = item:getAge() end end)
    try(function() if item:isCooked() then rec.ck = true end end)
    try(function() if item:isBurnt() then rec.bu = true end end)
    try(function() if item:isFavorite() then rec.f = true end end)
    try(function()
        local k = item:getKeyId()
        if k ~= nil and k ~= -1 then rec.k = k end
    end)


    try(function()
        if not item:IsWeapon() and item:getMaxAmmo() > 0 then
            local n = item:getCurrentAmmoCount()
            if n ~= nil and n > 0 then rec.am = n end
        end
    end)
    try(function()
        if item:IsWeapon() then
            local n = item:getCurrentAmmoCount()
            if n ~= nil and n > 0 then rec.am = n end
            if item:isContainsClip() then rec.cl = true end
            if item:isRoundChambered() then rec.ch = true end
        end
    end)
    try(function()

        local ci = item:getClothingItem()
        local v = item:getVisual()
        if ci == nil or v == nil then return end
        local tint = v:getTint()
        if tint ~= nil then rec.r, rec.g, rec.b = tint:getRedFloat(), tint:getGreenFloat(), tint:getBlueFloat() end
        local tc, bt = v:getTextureChoice(), v:getBaseTexture()
        if tc ~= nil and tc >= 0 then rec.tc = tc end
        if bt ~= nil and bt >= 0 then rec.bt = bt end
        local hue = v:getHue()
        if hue ~= nil and hue ~= 0 then rec.hue = hue end
        local dec = v:getDecal(ci)
        if dec ~= nil and dec ~= "" then rec.dec = dec end
    end)



    try(function()
        if not instanceof(item, "Clothing") then return end
        local v = item:getVisual()
        local parts = BloodClothingType.getCoveredParts(item:getBloodClothingType())
        if v == nil or parts == nil then return end
        local ho, pa, bl, di = {}, {}, {}, {}
        for j = 0, parts:size() - 1 do
            local part = parts:get(j)
            local i = part:index()
            if v:getHole(part) > 0 then ho[#ho + 1] = tostring(i) end
            local fab, lvl = 0, 0
            if v:getBasicPatch(part) > 0 then fab = 1
            elseif v:getDenimPatch(part) > 0 then fab = 2
            elseif v:getLeatherPatch(part) > 0 then fab = 3 end
            local patch = item:getPatchType(part)
            if patch ~= nil then
                fab = patch:getFabricType()
                lvl = BridgeItems.tailorLevel(fab, patch:getScratchDefense(), patch:getBiteDefense())
            end
            if fab > 0 then pa[#pa + 1] = i .. ":" .. fab .. ":" .. lvl end
            local b, d = v:getBlood(part), v:getDirt(part)
            if b >= 0.05 then bl[#bl + 1] = i .. ":" .. string.format("%.1f", b) end
            if d >= 0.05 then di[#di + 1] = i .. ":" .. string.format("%.1f", d) end
        end
        if #ho > 0 then rec.ho = table.concat(ho, "/") end
        if #pa > 0 then rec.pa = table.concat(pa, "/") end
        if #bl > 0 then rec.bl = table.concat(bl, "/") end
        if #di > 0 then rec.di = table.concat(di, "/") end
    end)


    try(function()
        if item.isRecordedMedia ~= nil and item:isRecordedMedia() == true then
            local mi = item:getRecordedMediaIndex()
            if type(mi) == "number" and mi >= 0 then rec.mi = mi end
        end
    end)


    try(function()
        if item.hasModData ~= nil and item:hasModData() == true then
            local md = plainCopy(item:getModData(), 1)



            if md ~= nil and not deep then
                md.Tooltip = nil
                local any = false
                for _ in pairs(md) do any = true break end
                if not any then md = nil end
            end
            if md ~= nil then
                local packed = BridgeItems.packTable(md)

                if deep or (packed ~= nil and #BridgeItems.esc(packed) <= BridgeItems.MD_MAX) then
                    rec.md = md
                elseif packed ~= nil then
                    warnOnce("md:" .. tostring(rec.t), "item data of " .. tostring(rec.t) .. " is too big for the snapshot, skipped")
                end
            end
        end
    end)

    local isBook = false
    try(function() isBook = item.IsLiterature ~= nil and item:IsLiterature() == true end)
    if isBook then
        try(function()
            local pg = item:getAlreadyReadPages()
            if type(pg) == "number" and pg > 0 then rec.pg = pg end
        end)
        try(function()
            local lk = item:getLockedBy()
            if type(lk) == "string" and lk ~= "" then rec.lk = lk end
        end)
        try(function()
            if item:canBeWrite() ~= true then return end
            local pages = item:getNumberOfPages()
            if type(pages) ~= "number" or pages <= 0 then return end
            local list, total, any = {}, 0, false
            for i = 1, pages do
                local text = item:seePage(i)
                if type(text) == "string" and text ~= "" then
                    list[i] = text
                    total = total + #text
                    any = true
                end
            end
            if not any then return end
            if total <= BridgeItems.PAGES_MAX then
                rec.cp = list
            else
                warnOnce("cp:" .. tostring(rec.t), "notes in " .. tostring(rec.t) .. " are too long for the snapshot, skipped")
            end
        end)
    end



    try(function()
        if rec.mi ~= nil then return end
        local custom = item.isCustomName ~= nil and item:isCustomName() == true
        local food = false
        pcall(function() food = item:IsFood() == true end)
        if food or not (custom or isBook) then return end
        local name = item:getName()
        if type(name) ~= "string" or name == "" then return end
        local base = nil
        pcall(function() base = item:getScriptItem():getDisplayName() end)
        if custom or (base ~= nil and name ~= base) then
            rec.n = name
            if custom then rec.cn = true end
        end
    end)
    if deep then
        try(function()
            if item:IsInventoryContainer() then
                local items = item:getInventory():getItems()
                if items:size() > 0 then
                    rec["in"] = {}
                    for i = 0, items:size() - 1 do
                        rec["in"][#rec["in"] + 1] = BridgeItems.record(items:get(i), true)
                    end
                end
            end
        end)
    end
    return rec
end






local FABRIC = { [1] = { 5, 0 }, [2] = { 10, 5 }, [3] = { 20, 10 } }
function BridgeItems.tailorLevel(fab, scratch, bite)
    local f = FABRIC[fab]
    if f == nil then return 1 end
    local best, bestErr = 1, nil
    for lvl = 1, 10 do
        local s = math.floor(math.max(1, f[1] * lvl / 10))
        local b = f[2] > 0 and math.floor(math.max(1, f[2] * lvl / 10)) or 0
        local err = math.abs(s - (scratch or 0)) + math.abs(b - (bite or 0))
        if bestErr == nil or err < bestErr then best, bestErr = lvl, err end
    end
    return best
end

local function eachPart(text, fn)
    for entry in string.gmatch(tostring(text or ""), "[^/]+") do
        local fields = {}
        for x in string.gmatch(entry, "[^:]+") do fields[#fields + 1] = x end
        local i = tonumber(fields[1])
        local part = nil

        local max = 0
        pcall(function() max = BloodBodyPartType.MAX:index() end)
        if i ~= nil and i >= 0 and i < max and i == math.floor(i) then
            pcall(function() part = BloodBodyPartType.FromIndex(i) end)
        end
        if part ~= nil then fn(part, i, fields) end
    end
end





function BridgeItems.applyWear(v, rec, item)
    eachPart(rec.ho, function(part) v:setHole(part) end)
    eachPart(rec.pa, function(part, i, f)
        local fab, lvl = tonumber(f[2]) or 0, tonumber(f[3]) or 0
        if fab == 1 then v:setBasicPatch(part) elseif fab == 2 then v:setDenimPatch(part)
        elseif fab == 3 then v:setLeatherPatch(part) end

        if item ~= nil and fab >= 1 and fab <= 3 and lvl >= 1 and lvl <= 10 then
            item:addPatchForSync(i, math.floor(lvl), math.floor(fab), true)
        end
    end)
    eachPart(rec.bl, function(part, i, f) v:setBlood(part, tonumber(f[2]) or 0) end)
    eachPart(rec.di, function(part, i, f) v:setDirt(part, tonumber(f[2]) or 0) end)
end


function BridgeItems.apply(item, rec)
    if rec.c ~= nil then try(function() item:setCondition(rec.c) end) end
    if rec.hc ~= nil then try(function() if item.setHeadCondition ~= nil then item:setHeadCondition(rec.hc) end end) end
    if rec.sh ~= nil then try(function() if item.setSharpness ~= nil then item:setSharpness(rec.sh) end end) end
    if rec.u ~= nil then try(function() item:setCurrentUsesFloat(rec.u) end) end
    if rec.a ~= nil then try(function() item:setAge(rec.a) end) end
    if rec.ck then try(function() item:setCooked(true) end) end
    if rec.bu then try(function() item:setBurnt(true) end) end
    if rec.f then try(function() item:setFavorite(true) end) end
    if rec.k ~= nil then try(function() item:setKeyId(rec.k) end) end
    if rec.am ~= nil then try(function() item:setCurrentAmmoCount(rec.am) end) end
    if rec.cl then try(function() item:setContainsClip(true) end) end
    if rec.ch then try(function() item:setRoundChambered(true) end) end
    if rec.fl ~= nil and rec.fa ~= nil then
        try(function()
            local fc = item:getFluidContainer()
            fc:Empty()
            fc:addFluid(rec.fl, rec.fa)
        end)
    elseif rec.fe then

        try(function()
            local fc = item:getFluidContainer()
            if fc ~= nil and not fc:isEmpty() then fc:Empty() end
        end)
    end
    if rec.wp ~= nil then
        try(function()
            for name in string.gmatch(rec.wp, "[^+]+") do
                local part = instanceItem(name)
                if part ~= nil then item:attachWeaponPart(part) end
            end
        end)
    end



    if rec.mi ~= nil then try(function() if item.setRecordedMediaIndexInteger ~= nil then item:setRecordedMediaIndexInteger(rec.mi) end end) end


    if type(rec.md) == "table" then
        try(function()
            local data = item:getModData()
            for k, v in pairs(rec.md) do data[k] = v end
        end)
    end
    if rec.pg ~= nil then try(function() if item.setAlreadyReadPages ~= nil then item:setAlreadyReadPages(rec.pg) end end) end
    if rec.lk ~= nil then try(function() if item.setLockedBy ~= nil then item:setLockedBy(rec.lk) end end) end
    if type(rec.cp) == "table" then
        try(function()
            if item.addPage == nil then return end
            for page, text in pairs(rec.cp) do
                if type(page) == "number" and type(text) == "string" then item:addPage(page, text) end
            end
        end)
    end
    if rec.n ~= nil and rec.mi == nil then
        try(function()
            item:setName(rec.n)
            if rec.cn and item.setCustomName ~= nil then item:setCustomName(true) end
        end)
    end
    try(function()
        local v = item:getVisual()
        if v == nil then return end
        if rec.r ~= nil then v:setTint(ImmutableColor.new(rec.r, rec.g, rec.b)) end
        if rec.tc ~= nil then v:setTextureChoice(rec.tc) end
        if rec.bt ~= nil then v:setBaseTexture(rec.bt) end
        if rec.hue ~= nil then v:setHue(rec.hue) end
        if rec.dec ~= nil then v:setDecal(rec.dec) end
        if rec.ho ~= nil or rec.pa ~= nil or rec.bl ~= nil or rec.di ~= nil then
            pcall(function() BridgeItems.applyWear(v, rec, item) end)
        end
        pcall(function() item:synchWithVisual() end)
    end)
end


function BridgeItems.make(container, rec)
    local item = container:AddItem(rec.t)
    if item == nil then return nil end
    BridgeItems.apply(item, rec)
    if rec["in"] ~= nil then
        try(function()
            local inner = item:getInventory()
            for _, child in ipairs(rec["in"]) do BridgeItems.make(inner, child) end
        end)
    end
    return item
end


function BridgeItems.visual(rec)
    local iv = ItemVisual.new()
    iv:setItemType(rec.t)
    iv:setClothingItemName(rec.t)
    if rec.r ~= nil then try(function() iv:setTint(ImmutableColor.new(rec.r, rec.g, rec.b)) end) end
    if rec.tc ~= nil then try(function() iv:setTextureChoice(rec.tc) end) end
    if rec.bt ~= nil then try(function() iv:setBaseTexture(rec.bt) end) end
    if rec.hue ~= nil then try(function() iv:setHue(rec.hue) end) end
    if rec.dec ~= nil then try(function() iv:setDecal(rec.dec) end) end

    try(function() BridgeItems.applyWear(iv, rec, nil) end)
    return iv
end






local NUM = { h = true, p = true, c = true, u = true, a = true, r = true, g = true, b = true,
              tc = true, bt = true, hue = true, k = true, am = true, fa = true, sh = true, hc = true,
              mi = true, pg = true }
local BOOL = { w = true, ck = true, bu = true, f = true, cl = true, ch = true, fe = true, as = true, cn = true }

local TEXT = { n = true, lk = true }
local PACKED = { md = true, cp = true }
local ORDER = { "t", "w", "h", "p", "c", "hc", "sh", "u", "a", "r", "g", "b", "tc", "bt", "hue", "dec", "ho", "pa", "bl", "di", "k", "f", "ck", "bu",
                "am", "cl", "ch", "fl", "fa", "fe", "wp", "as", "mi", "n", "cn", "pg", "lk", "md", "cp" }
local FLOAT = { r = "%.4f", g = "%.4f", b = "%.4f", hue = "%.4f", u = "%.4f", a = "%.4f", fa = "%.3f", sh = "%.3f" }
BridgeItems.MAX_LENGTH = 30000

local function clean(s)
    return (string.gsub(tostring(s), "[;,=]", "_"))
end


function BridgeItems.encode(list, skip)
    local parts = {}
    local length = 0
    for _, rec in ipairs(list) do
        local fields = {}
        for _, key in ipairs(ORDER) do
            local v = rec[key]




            if v ~= nil and v ~= false and not (key == "h" and v == 0) and not (skip ~= nil and skip[key]) then
                if BOOL[key] then
                    fields[#fields + 1] = key .. "=1"
                elseif PACKED[key] then
                    local packed = (type(v) == "table") and BridgeItems.packTable(v) or nil
                    if packed ~= nil then fields[#fields + 1] = key .. "=" .. BridgeItems.esc(packed) end
                elseif TEXT[key] then
                    fields[#fields + 1] = key .. "=" .. BridgeItems.esc(v)
                elseif FLOAT[key] then
                    fields[#fields + 1] = key .. "=" .. string.format(FLOAT[key], v)
                elseif NUM[key] then
                    fields[#fields + 1] = key .. "=" .. tostring(v)
                else
                    fields[#fields + 1] = key .. "=" .. clean(v)
                end
            end
        end
        local part = table.concat(fields, ";")
        length = length + #part + 1
        if length > BridgeItems.MAX_LENGTH then
            warn("snapshot truncated at " .. tostring(#parts) .. " of " .. tostring(#list) .. " records")
            break
        end
        parts[#parts + 1] = part
    end
    return table.concat(parts, ",")
end









local VOLATILE = { a = true, u = true, fa = true, md = true, bl = true, di = true }
function BridgeItems.signature(list)
    return BridgeItems.encode(list, VOLATILE)
end




function BridgeItems.lookKey(list)
    local out = {}
    for _, rec in ipairs(list) do
        if rec.p == nil and (rec.w or (rec.h or 0) > 0 or rec.as) then
            out[#out + 1] = table.concat({ rec.t, rec.w and "1" or "0", tostring(rec.h or 0), rec.as and "a" or "", tostring(rec.tc or ""),
                tostring(rec.bt or ""), tostring(rec.hue or ""), tostring(rec.dec or ""), tostring(rec.ho or ""), tostring(rec.pa or ""),
                rec.r and string.format("%.2f%.2f%.2f", rec.r, rec.g, rec.b) or "" }, ":")
        end
    end
    return table.concat(out, "|")
end

local function decodeOld(f)
    local rec = { t = f[1], w = (f[2] == "1"), h = tonumber(f[3]) or 0, c = tonumber(f[4]) }
    if f[5] ~= nil and f[5] ~= "" then
        rec.r, rec.g, rec.b = tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
    end
    rec.u = tonumber(f[8] or "")
    rec.a = tonumber(f[9] or "")
    return rec
end

function BridgeItems.decode(text)
    local list = {}
    if text == nil or text == "" then return list end
    for part in string.gmatch(tostring(text), "[^,]+") do
        local f = {}
        for v in string.gmatch(part .. ";", "([^;]*);") do f[#f + 1] = v end
        if f[1] ~= nil and f[1] ~= "" then
            if string.find(f[1], "=", 1, true) == nil then
                list[#list + 1] = decodeOld(f)
            else
                local rec = { h = 0, w = false }
                for _, kv in ipairs(f) do
                    local k, v = string.match(kv, "^([%a]+)=(.*)$")
                    if k ~= nil then
                        if BOOL[k] then rec[k] = (v == "1")
                        elseif NUM[k] then rec[k] = tonumber(v)
                        elseif PACKED[k] then rec[k] = BridgeItems.unpackTable(BridgeItems.unesc(v))
                        elseif TEXT[k] then rec[k] = BridgeItems.unesc(v)
                        else rec[k] = v end
                    end
                end
                if rec.t ~= nil then list[#list + 1] = rec end
            end
        end
    end
    return list
end

if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeItems] loaded") end

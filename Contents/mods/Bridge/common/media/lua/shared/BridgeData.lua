













BridgeData = BridgeData or {}
BridgeData.KEY = "NotAlone"
BridgeData.OLD_KEY = "BridgeRin"
BridgeData.LOCAL = "local"
BridgeData.DEFAULT_NAME = "Rin"
BridgeData.NAME_MAX = 20
BridgeData.MODES = { follow = true, wait = true, rest = true }





function BridgeData.overheadOk(text)
    if text == nil then return false end
    text = tostring(text)
    local plain = true
    for i = 1, #text do
        if string.byte(text, i) > 127 then plain = false break end
    end
    if plain then return true end
    local ok = false
    pcall(function() ok = getTextOrNull("IGUI_NotAlone_OverheadCyrillic") == "1" end)
    return ok
end






function BridgeData.owner()
    local p = nil
    if getSpecificPlayer ~= nil then p = getSpecificPlayer(0) end
    if p == nil then p = getPlayer() end
    return p
end









function BridgeData.dragged(z)
    local yes = false
    pcall(function() yes = z:isReanimatedForGrappleOnly() == true end)
    return yes
end








BridgeData.FRIENDLY_VARS = BridgeData.FRIENDLY_VARS or { "RNPCFriendly" }

function BridgeData.friendlyNpc(z)
    local yes = false
    pcall(function()
        local vars = BridgeData.FRIENDLY_VARS
        for i = 1, #vars do
            if z:getVariableBoolean(vars[i]) then yes = true return end
        end
    end)
    return yes
end








BridgeData.FOREIGN_MODDATA = BridgeData.FOREIGN_MODDATA or { "ProjectALifeOwned", "ProjectALifeActor" }

local function markedForeign(z)
    local yes = false
    pcall(function()
        local data = z:getModData()
        if data == nil then return end
        local keys = BridgeData.FOREIGN_MODDATA
        for i = 1, #keys do
            if data[keys[i]] == true then yes = true return end
        end
    end)
    return yes
end











function BridgeData.banditBrain(z, deep)
    if type(BanditBrain) ~= "table" or type(BanditBrain.Get) ~= "function" then return false, nil end
    local npc, brain = false, nil
    pcall(function()
        if z:getVariableBoolean("Bandit") then
            npc = true
            brain = BanditBrain.Get(z)
        end
        if type(brain) ~= "table" and (deep or isServer()) and type(GetBanditClusterData) == "function"
            and type(BanditUtils) == "table" and type(BanditUtils.GetZombieID) == "function" then
            local id = BanditUtils.GetZombieID(z)
            local gmd = GetBanditClusterData(id)
            if type(gmd) == "table" and type(gmd[id]) == "table" then
                npc = true
                brain = gmd[id]
            end
        end
    end)
    if type(brain) ~= "table" then brain = nil end
    return npc, brain
end




function BridgeData.bandit(z, deep)
    local npc, brain = BridgeData.banditBrain(z, deep)
    local hostile = nil
    if brain ~= nil then hostile = brain.hostile == true or brain.hostileP == true end
    return npc, hostile
end



function BridgeData.foreign(z)
    if markedForeign(z) then return true end
    local npc = BridgeData.banditBrain(z, true)
    return npc
end









function BridgeData.alifeHostile(z)
    local answer = nil
    pcall(function()
        local mod = ProjectALife
        if type(mod) ~= "table" then return end
        local player = BridgeData.owner()
        local data = z:getModData()
        local uid = data ~= nil and data.ProjectALifeUID or nil
        if type(uid) == "string" and type(mod.ActorRegistry) == "table" and type(mod.Relations) == "table"
            and type(mod.Relations.hostileToPlayer) == "function" then
            local read = mod.ActorRegistry.peek or mod.ActorRegistry.read
            local actor = type(read) == "function" and read(uid) or nil
            if type(actor) == "table" then
                answer = mod.Relations.hostileToPlayer(actor, player) == true
                return
            end
        end
        if type(mod.Reputation) == "table" and type(mod.Reputation.statusFor) == "function" then
            local status = mod.Reputation.statusFor(player, z)
            if type(status) == "string" then answer = status == "hostile" end
        end
    end)
    return answer
end







function BridgeData.foreignPeaceful(z)
    local npc, hostile = BridgeData.bandit(z)
    if npc then return hostile ~= true end
    if not markedForeign(z) then return false end
    return BridgeData.alifeHostile(z) ~= true
end





function BridgeData.harmless(z)
    return BridgeData.dragged(z) or BridgeData.friendlyNpc(z) or BridgeData.foreignPeaceful(z)
end


function BridgeData.me()
    if isClient() then
        local p = BridgeData.owner()
        if p == nil then return nil end
        return p:getUsername()
    end
    return BridgeData.LOCAL
end



function BridgeData.cleanName(text)
    if text == nil then return nil end
    text = tostring(text)
    local out = {}
    for i = 1, #text do
        local c = string.byte(text, i)
        if c >= 32 and c ~= 127 then out[#out + 1] = string.sub(text, i, i) end
    end
    text = table.concat(out)
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if #text > BridgeData.NAME_MAX then text = string.sub(text, 1, BridgeData.NAME_MAX) end
    if text == "" then return nil end
    return text
end

function BridgeData.nameOf(rec)
    if rec ~= nil and rec.name ~= nil and rec.name ~= "" then return rec.name end
    return BridgeData.DEFAULT_NAME
end

function BridgeData.modeOf(rec)
    if rec ~= nil and BridgeData.MODES[rec.mode] then return rec.mode end
    return "follow"
end





BridgeData.KEEP_SIDES = { behind = true, left = true, right = true }











BridgeData.KEEP_SIDES_ON = false






BridgeData.KEEP_ON = true

function BridgeData.keepAllowed(side)
    if side == "behind" then return true end
    return BridgeData.KEEP_SIDES_ON == true and BridgeData.KEEP_SIDES[side] == true
end

function BridgeData.keepOf(rec)
    if BridgeData.KEEP_ON and rec ~= nil and BridgeData.keepAllowed(rec.keep) then return rec.keep end
    return "behind"
end

function BridgeData.farOf(rec)
    return BridgeData.KEEP_ON == true and rec ~= nil and rec.far == true
end


BridgeData.COMBAT_MODES = { bodyguard = true, escort = true, aggressive = true }
BridgeData.DEFAULT_COMBAT = "bodyguard"


BridgeData.COMBAT = {
    bodyguard = { rank = "player", engageSelf = 2.5, engageRed = 3.0, targetMax = 6.0, approach = 4.5, leash = 4.0 },
    escort = { rank = "self", engageSelf = 3.0, engageRed = 5.5, targetMax = 9.0, approach = 7.0, leash = 7.0 },
    aggressive = { rank = "self", engageSelf = 4.5, engageRed = 11.0, targetMax = 13.0, approach = 12.0, leash = 12.0 },
}

function BridgeData.combatOf(rec)
    if rec ~= nil and BridgeData.COMBAT_MODES[rec.combat] then return rec.combat end
    return BridgeData.DEFAULT_COMBAT
end

















BridgeData.OPTIONS = { autoHeal = true, hitMatters = false, gifts = true, redKit = true, mood = true }
BridgeData.DEFAULT_HAIR = "Grungey02"
BridgeData.HAIR_MAX = 40

function BridgeData.optionOf(rec, key)
    if BridgeData.OPTIONS[key] == nil then return false end
    if rec ~= nil and rec[key] ~= nil then return rec[key] == true end
    return BridgeData.OPTIONS[key]
end


function BridgeData.cleanHair(text)
    if type(text) ~= "string" or text == "" or #text > BridgeData.HAIR_MAX then return nil end
    if string.find(text, "[^%w_]") ~= nil then return nil end
    return text
end

function BridgeData.hairOf(rec)
    local hair = rec ~= nil and BridgeData.cleanHair(rec.hair) or nil
    return hair or BridgeData.DEFAULT_HAIR
end

BridgeData.DEFAULT_SKIN = "FemaleBody01"
BridgeData.SKINS = { "FemaleBody01", "FemaleBody02", "FemaleBody03", "FemaleBody04", "FemaleBody05" }
BridgeData.DEFAULT_HAIR_COLOR = { r = 0.55, g = 0.12, b = 0.12 }


function BridgeData.cleanSkin(text)
    if type(text) ~= "string" then return nil end
    for i = 1, #BridgeData.SKINS do
        if BridgeData.SKINS[i] == text then return text end
    end
    return nil
end

function BridgeData.skinOf(rec)
    local skin = rec ~= nil and BridgeData.cleanSkin(rec.skin) or nil
    return skin or BridgeData.DEFAULT_SKIN
end

function BridgeData.cleanHairColor(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for _, k in ipairs({ "r", "g", "b" }) do
        local v = tonumber(t[k])
        if v == nil or v ~= v then return nil end
        if v < 0 then v = 0 end
        if v > 1 then v = 1 end
        out[k] = v
    end
    return out
end

function BridgeData.hairColorOf(rec)
    local color = rec ~= nil and BridgeData.cleanHairColor(rec.hairColor) or nil
    return color or BridgeData.DEFAULT_HAIR_COLOR
end



BridgeData.MUSCLE_MAX = 2


local function spnccData()
    if BridgeData._spnccData ~= nil then return BridgeData._spnccData or nil end
    local ok, mod = pcall(require, "CharacterCustomisation/SPNCC_Data")
    BridgeData._spnccData = (ok and type(mod) == "table") and mod or false
    return BridgeData._spnccData or nil
end


function BridgeData.skinIndex(rec)
    local n = tonumber(string.match(BridgeData.skinOf(rec), "(%d+)$")) or 1
    return n - 1
end


function BridgeData.spnccFaces()
    if BridgeData._faces ~= nil then return BridgeData._faces or nil end
    local d = spnccData()
    if d == nil or type(d.FemaleFaces) ~= "table" then
        BridgeData._faces = false
        return nil
    end
    local out = {}
    for _, v in pairs(d.FemaleFaces) do
        if type(v) == "table" and type(v.name) == "string" and v.name ~= "" then out[#out + 1] = v end
    end
    if #out == 0 then
        BridgeData._faces = false
        return nil
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    BridgeData._faces = out
    return out
end


function BridgeData.spnccDetails()
    if BridgeData._details ~= nil then return BridgeData._details or nil end
    local d = spnccData()
    if d == nil or type(d.BodyDetails) ~= "table" then
        BridgeData._details = false
        return nil
    end
    local out = {}
    for _, v in pairs(d.BodyDetails) do
        if type(v) == "table" and type(v.name) == "string" and v.name ~= "" and v.female ~= false then
            out[#out + 1] = v
        end
    end
    if #out == 0 then
        BridgeData._details = false
        return nil
    end
    table.sort(out, function(a, b) return (a.sort or "b") .. a.name < (b.sort or "b") .. b.name end)
    BridgeData._details = out
    return out
end


function BridgeData.spnccMuscle()
    local d = spnccData()
    if d == nil or type(d.Muscle) ~= "table" then return nil end
    return d.Muscle[2]
end


function BridgeData.spnccMuscleTypes()
    local d = spnccData()
    if d == nil or type(d.Muscle) ~= "table" then return nil end
    return d.Muscle
end


function BridgeData.spnccOn()
    return BridgeData.spnccFaces() ~= nil or BridgeData.spnccDetails() ~= nil
end


function BridgeData.makeupList()
    if BridgeData._makeup ~= nil then return BridgeData._makeup or nil end
    local defs = rawget(_G, "MakeUpDefinitions")
    if defs == nil or type(defs.makeup) ~= "table" then
        BridgeData._makeup = false
        return nil
    end
    local out = {}
    for _, m in ipairs(defs.makeup) do
        if type(m.item) == "string" and m.item ~= "" then
            out[#out + 1] = { item = m.item, category = m.category or "FullFace", name = m.name }
        end
    end
    if #out == 0 then
        BridgeData._makeup = false
        return nil
    end
    BridgeData._makeup = out
    return out
end


function BridgeData.makeupMeta(itemType)
    for _, m in ipairs(BridgeData.makeupList() or {}) do
        if m.item == itemType then return m end
    end
    return nil
end


local function asList(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    local n = #t
    if n > 0 then
        for i = 1, n do out[i] = t[i] end
        return out
    end
    local i = 1
    while true do
        local v = t[i]
        if v == nil then v = t[tostring(i)] end
        if v == nil then break end
        out[i] = v
        i = i + 1
    end
    return out
end


local function tokenOk(name)
    return type(name) == "string" and name ~= "" and #name <= 64 and string.find(name, "[^%w_]") == nil
end


function BridgeData.cleanMakeup(list)
    list = asList(list)
    if list == nil then return nil end
    local out, seen = {}, {}
    if BridgeData.makeupList() == nil then
        for _, itemType in ipairs(list) do
            if type(itemType) == "string" and string.find(itemType, "^[%w_]+%.[%w_]+$") ~= nil and not seen[itemType] then
                seen[itemType] = true
                out[#out + 1] = itemType
            end
        end
        return out
    end
    for _, itemType in ipairs(list) do
        local m = BridgeData.makeupMeta(itemType)
        if m ~= nil and not seen[m.category] then
            seen[m.category] = true
            out[#out + 1] = itemType
        end
    end
    return out
end


function BridgeData.makeupOf(rec)
    return BridgeData.cleanMakeup(rec ~= nil and rec.makeup or nil) or {}
end


function BridgeData.spnccTexture(entry, skinIndex)
    if type(entry) ~= "table" then return skinIndex or 0 end
    if type(entry.textures) == "table" then
        if #entry.textures == 1 then return entry.textures[1] end
        if #entry.textures >= 5 then return entry.textures[(skinIndex or 0) + 1] end
    end
    local off = tonumber(entry.textureOffset) or 0
    if off < 0 then off = 0 end
    return (skinIndex or 0) + off
end


function BridgeData.faceEntry(rec)
    local name = rec ~= nil and rec.face or nil
    if type(name) ~= "string" or name == "" then return nil end
    for _, e in ipairs(BridgeData.spnccFaces() or {}) do
        if e.name == name then return e end
    end
    return nil
end


function BridgeData.detailEntries(rec)
    local out = {}
    local wanted = asList(rec ~= nil and rec.details or nil) or {}
    for _, e in ipairs(BridgeData.spnccDetails() or {}) do
        for _, n in ipairs(wanted) do
            if n == e.name then out[#out + 1] = e break end
        end
    end
    return out
end


function BridgeData.cleanFace(name)
    if name == nil or name == "" then return nil end
    if type(name) ~= "string" then return nil end
    local faces = BridgeData.spnccFaces()
    if faces == nil then
        if tokenOk(name) then return name end
        return nil
    end
    for _, e in ipairs(faces) do
        if e.name == name then return name end
    end
    return nil
end


function BridgeData.cleanDetails(list)
    list = asList(list)
    if list == nil then return nil end
    local catalog = BridgeData.spnccDetails()
    local seen, out = {}, {}
    if catalog == nil then
        for _, n in ipairs(list) do
            if tokenOk(n) and not seen[n] then
                seen[n] = true
                out[#out + 1] = n
            end
        end
        return out
    end
    local ok = {}
    for _, e in ipairs(catalog) do ok[e.name] = true end
    for _, n in ipairs(list) do
        if type(n) == "string" and ok[n] and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
        end
    end
    return out
end


function BridgeData.muscleOf(rec)
    local n = rec ~= nil and tonumber(rec.muscle) or 0
    if n == nil or n ~= n or n < 0 then n = 0 end
    if n > BridgeData.MUSCLE_MAX then n = BridgeData.MUSCLE_MAX end
    return math.floor(n)
end




function BridgeData.wants(rec)
    return rec ~= nil and rec.want ~= false
end



function BridgeData.world(owner)
    local md = ModData.getOrCreate(BridgeData.KEY)
    if md.players == nil then md.players = {} end

    if not md.migrated and not isClient() then
        md.migrated = true
        pcall(function()
            if not ModData.exists(BridgeData.OLD_KEY) then return end
            local old = ModData.get(BridgeData.OLD_KEY)
            if old == nil then return end
            local who = old.owner or owner
            if who == nil then return end
            local rec = md.players[who] or {}
            if rec.items == nil and old.items ~= nil then
                rec.items = old.items
                rec.saved = old.saved
            end
            if rec.want == nil and old.want ~= nil then rec.want = old.want end
            rec.lastX, rec.lastY, rec.lastZ = old.lastX, old.lastY, old.lastZ

            rec.oldBodyId = old.bodyId
            md.players[who] = rec
        end)
    end
    return md
end


function BridgeData.ownerOf(md, pid)
    if md == nil or md.players == nil or pid == nil then return nil, nil end
    for who, rec in pairs(md.players) do
        if rec.bodyId == pid then return who, rec end
    end
    return nil, nil
end










BridgeData.REL_KEYS = { f = { -100, 100 }, r = { 0, 100 }, days = { 0, 100000 }, hours = { 0, 24 },
    day = { 0, 1000000 }, gainF = { -100, 100 }, gainR = { -100, 100 }, giftAt = { 0, 100000000 },
    seen = { 0, 100000000 }, askAt = { 0, 100000000 }, healAt = { 0, 100000000 },
    dressF = { 0, 100 }, dressR = { 0, 100 } }


function BridgeData.relOf(rec)
    if rec == nil then return nil end
    if type(rec.rel) ~= "table" then rec.rel = {} end
    local rel = rec.rel
    for k, _ in pairs(BridgeData.REL_KEYS) do
        if type(rel[k]) ~= "number" then rel[k] = 0 end
    end
    return rel
end



function BridgeData.cleanRel(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for k, range in pairs(BridgeData.REL_KEYS) do
        local v = tonumber(t[k])
        if v ~= nil and v == v then
            if v < range[1] then v = range[1] end
            if v > range[2] then v = range[2] end
            out[k] = v
        else
            out[k] = 0
        end
    end
    return out
end


function BridgeData.relTier(rel)
    local f = rel and rel.f or 0
    if f < 0 then return "Cold" end
    if f < 20 then return "Known" end
    if f < 45 then return "Pal" end
    if f < 75 then return "Friend" end
    return "Close"
end

if BridgeLog ~= nil and BridgeLog.on() then print("[BridgeData] loaded") end

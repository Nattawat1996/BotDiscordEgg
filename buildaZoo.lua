-- === CONFIG ===
local WEBHOOK_URL = "https://discord.com/api/webhooks/1409193879626059967/pm25mdnnluBUlIdWye-EHCkA4rSnpNVZYpZ67j6PBWnCcfnT8eERfCz62MqSU9_2nPku" -- ใส่ของคุณเอง

-- === SERVICES ===
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

-- === request wrapper (รองรับหลาย executor) ===
local _request = (syn and syn.request) or (http and http.request) or request
assert(_request, "ไม่พบฟังก์ชัน request (syn.request/http.request/request)")

local function SendMessage(msg)
    local body = HttpService:JSONEncode({ content = msg })
    _request({
        Url = WEBHOOK_URL,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = body
    })
end

-- === หา Data แบบกันพัง ===
local Data =
    Player:FindFirstChild("Data") or
    (Player:FindFirstChild("PlayerGui") and Player.PlayerGui:FindFirstChild("Data")) or
    (Player:WaitForChild("PlayerGui",60):WaitForChild("Data",60))
assert(Data, "หา Data ไม่เจอใต้ Player/PlayerGui")

-- NOTE: ในเกมนี้โครงสร้างคือ Data:WaitForChild("Pets"/"Egg"/"Asset")
local OwnedPetData  = Data:WaitForChild("Pets", 30)
local OwnedEggData  = Data:WaitForChild("Egg", 30)
local InventoryData = Data:WaitForChild("Asset", 30)

-- === Helper: ดึงจาก Attribute หรือ ValueObject ลูก
local function getAttrOrChildValue(inst, attrName, childNameFallback)
    local v = inst and inst:GetAttribute(attrName)
    if v ~= nil then return v end
    if not inst then return nil end
    local c = inst:FindFirstChild(childNameFallback or attrName)
    if c and c:IsA("ValueBase") then return c.Value end
    return nil
end

-- ===== Helpers for config lookup (เก็บไว้เป็น fallback เผื่อจำเป็น) =====
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:FindFirstChild("Config")

local function safe_require(folder, name)
    if not folder then return nil end
    local m = folder:FindFirstChild(name)
    if not m then return nil end
    local ok, res = pcall(require, m)
    if ok then return res end
    return nil
end
-- ใส่ไว้ช่วงบนๆ ของไฟล์ (หลังประกาศ Services ก็ได้)
local SHOW_UID = false
local function formatPetLine(pType, muta, ps, uid)
    if SHOW_UID and uid then
        return string.format("%s | %s — %s / sec (UID: %s)", tostring(pType), tostring(muta), tostring(ps or 0), tostring(uid))
    else
        return string.format("%s | %s — %s / sec", tostring(pType), tostring(muta), tostring(ps or 0))
    end
end


local ResPet    = safe_require(Config, "ResPet")     -- ควรมี __index[Type]
local ResMutate = safe_require(Config, "ResMutate")  -- ควรมี __index[Mutate]

local function first_number_by_keys(row, keys)
    if type(row) ~= "table" then return nil end
    for _, k in ipairs(keys) do
        local v = row[k]
        if type(v) == "number" then return v end
    end
    return nil
end

local function base_ps_from_type(pType)
    if not (ResPet and ResPet.__index and pType) then return nil end
    local row = ResPet.__index[pType]
    if type(row) ~= "table" then return nil end
    return first_number_by_keys(row, {"ProduceSpeed","ProdSpeed","PS","produceSpeed","speed","rate"})
end

local function multiplier_from_mutate(muta)
    if not (ResMutate and ResMutate.__index and muta) then return 1 end
    local row = ResMutate.__index[muta]
    if type(row) ~= "table" then return 1 end
    local mul = first_number_by_keys(row, {"Multiplier","Multiply","Rate","PSMul","ProduceMul","x","mul"})
    if type(mul) == "number" and mul > 0 then return mul end
    return 1
end

-- ===== NEW #1: ดึง "เงินต่อวิ" ของสัตว์ใน inventory จาก GUI =====
-- พาธ: PlayerGui.ScreenStorage.Frame.ContentPet.ScrollingFrame[uid].BTN.Stat.Price.Value
-- ===== REPLACE THIS FUNCTION =====
local function get_ps_from_inventory_gui(uid, opts)
    opts = opts or {}
    local TIMEOUT = opts.timeout or 3     -- วินาทีที่รอ GUI
    local DEBUG   = (opts.debug == true)

    local function dprint(...)
        if DEBUG then warn("[INV-PS]", ...) end
    end

    if not uid then dprint("no uid"); return nil end

    -- 1) รอ PlayerGui + โหนดหลัก ๆ ให้ครบก่อน
    local pg = Player:FindFirstChild("PlayerGui") or Player:WaitForChild("PlayerGui", TIMEOUT)
    if not pg then dprint("no PlayerGui"); return nil end

    local screenStorage = pg:FindFirstChild("ScreenStorage") or pg:WaitForChild("ScreenStorage", TIMEOUT)
    if not screenStorage then dprint("no ScreenStorage"); return nil end

    local frame = screenStorage:FindFirstChild("Frame") or screenStorage:WaitForChild("Frame", TIMEOUT)
    if not frame then dprint("no Frame"); return nil end

    local contentPet = frame:FindFirstChild("ContentPet") or frame:WaitForChild("ContentPet", TIMEOUT)
    if not contentPet then dprint("no ContentPet"); return nil end

    local sf = contentPet:FindFirstChild("ScrollingFrame") or contentPet:WaitForChild("ScrollingFrame", TIMEOUT)
    if not sf then dprint("no ScrollingFrame"); return nil end

    -- 2) หา item โดยชื่อ uid ก่อน (ทางตรง)
    local item = sf:FindFirstChild(uid)

    -- 2.1) ถ้าไม่เจอ ให้ไล่ค้นทั้ง descendant หาโหนดที่ Name == uid (บางเกม wrap หลายชั้น)
    if not item then
        for _, desc in ipairs(sf:GetDescendants()) do
            if desc.Name == uid then
                item = desc
                break
            end
        end
    end
    if not item then dprint("item not found for uid", uid); return nil end

    -- 3) ดึง Price จาก path ที่คาดหวัง: BTN -> Stat -> Price
    local btn   = item:FindFirstChild("BTN")
    local stat  = btn and btn:FindFirstChild("Stat") or nil
    local price = stat and stat:FindFirstChild("Price") or nil

    -- 3.1) ถ้าไม่เจอ ลองหาอะไรที่ชื่อ "Price" ที่อยู่ใต้ item ทั้งหมด
    if not price then
        for _, desc in ipairs(item:GetDescendants()) do
            if desc.Name == "Price" then
                price = desc
                break
            end
        end
    end
    if not price then dprint("Price node not found"); return nil end

    -- 4) แปลงค่า price -> number (รองรับ ValueBase / TextLabel / Attribute)
    local raw

    -- ValueBase (NumberValue/IntValue/StringValue ฯลฯ)
    if price:IsA("ValueBase") then
        raw = price.Value
    else
        -- Attribute “Value”
        if price:GetAttribute("Value") ~= nil then
            raw = price:GetAttribute("Value")
        end
        -- TextLabel/TextButton.Text
        if (raw == nil) and (price:IsA("TextLabel") or price:IsA("TextButton")) then
            raw = price.Text
        end
        -- เผื่อมีลูกชื่อ Value (บาง UI ใส่ Value ไว้ข้างใน)
        if raw == nil then
            local vchild = price:FindFirstChild("Value")
            if vchild and vchild:IsA("ValueBase") then
                raw = vchild.Value
            elseif vchild and (vchild:IsA("TextLabel") or vchild:IsA("TextButton")) then
                raw = vchild.Text
            end
        end
    end

    if raw == nil then dprint("Price raw nil"); return nil end

    -- 5) ทำความสะอาดข้อความให้กลายเป็นตัวเลข (ลบ , ช่องว่าง หน่วย /s ฯลฯ)
    local function to_number(v)
        if type(v) == "number" then return v end
        if type(v) ~= "string" then return nil end
        -- เอาเฉพาะตัวเลขกับจุด (รองรับทศนิยม) เช่น "467,550 / sec" -> "467550"
        local cleaned = v:gsub(",", ""):gsub("[^%d%.%-]", "")
        -- ป้องกันหลายจุด เช่น "12.3.4" -> "12.3"
        cleaned = cleaned:match("^%-?%d+%.?%d*") or cleaned
        return tonumber(cleaned)
    end

    local num = to_number(raw)
    if not num then dprint("Price not a number:", raw) end
    return num
end
-- ===== END REPLACE =====


-- ===== NEW #2: map Type/Mutate จาก OwnedEggData ด้วย uid =====
local function map_type_muta_from_eggs(uid, fallbackNode)
    local eggNode = (OwnedEggData and OwnedEggData:FindFirstChild(uid)) or nil
    local t = getAttrOrChildValue(eggNode, "T")
    local m = getAttrOrChildValue(eggNode, "M")

    -- ถ้า egg ไม่มี ให้ fallback (เผื่อบาง uid ไม่มีใน Egg)
    if t == nil then t = getAttrOrChildValue(fallbackNode, "T") end
    if m == nil then m = getAttrOrChildValue(fallbackNode, "M") end

    return tostring(t or "Unknown"), tostring(m or "None")
end

-- คำนวณ ProduceSpeed สำหรับ node ใน Data.Pets (เฉพาะ "ยังไม่วาง")
-- ลำดับใหม่: UI (จำเพาะที่สั่ง) -> fallback config -> BPV/FT
-- แต่ Type/Mutate จะมาจาก OwnedEggData mapping ตาม uid
local function compute_ps_for_inventory_node(node)
    local uid = node and node.Name or nil

    -- เงินต่อวิ: จาก GUI ก่อน
    local ui_ps = get_ps_from_inventory_gui(uid)

    -- Type/Mutate: จาก OwnedEggData (mapping ตาม uid)
    local pType, muta = map_type_muta_from_eggs(uid, node)

    -- ถ้า UI มีค่าแล้ว ใช้อันนี้ได้เลย
    if type(ui_ps) == "number" then
        return ui_ps, pType, muta
    end

    -- ถ้า UI ไม่มี/หาไม่เจอ → fallback เดิม
    local ps = base_ps_from_type(pType)
    if ps then
        ps = ps * (multiplier_from_mutate(muta) or 1)
        return ps, pType, muta
    end

    local BPV = tonumber(getAttrOrChildValue(node, "BPV"))
    local FT  = tonumber(getAttrOrChildValue(node, "FT"))
    if BPV and FT and FT ~= 0 then
        return (BPV / FT), pType, muta
    end

    return 0, pType, muta
end

-- === Collectors ===
-- placed: อ่านจาก RootPart โดยตรง
-- inventory: เงินต่อวิจาก GUI (ใหม่) และ T/M จาก OwnedEggData
local function collectPets()
    local placed, inv = {}, {}

    -- ทำแผนที่ UID -> model ของสัตว์ที่ "วางอยู่"
    local modelsByUID = {}
    local petsFolder = workspace:FindFirstChild("Pets")
    if petsFolder then
        for _, model in ipairs(petsFolder:GetChildren()) do
            if model:GetAttribute("UserId") == Player.UserId then
                modelsByUID[tostring(model)] = model
                local root = model:FindFirstChild("RootPart") or model.PrimaryPart
                if root then
                    local petType = root:GetAttribute("Type")    or getAttrOrChildValue(root, "Type")    or "Unknown"
                    local muta    = root:GetAttribute("Mutate")  or getAttrOrChildValue(root, "Mutate")  or "None"
                    local ps      = root:GetAttribute("ProduceSpeed") or getAttrOrChildValue(root,"ProduceSpeed") or 0
                    table.insert(placed, formatPetLine(petType, muta, ps, tostring(model)))
                end
            end
        end
    end

    -- เดิน Data.Pets → ถ้าไม่มี model อยู่ในโลก ถือว่าเป็น inventory
    if OwnedPetData then
        for _, node in ipairs(OwnedPetData:GetChildren()) do
            local uid = node.Name
            if not modelsByUID[uid] then
                local ps, pType, muta = compute_ps_for_inventory_node(node)
                table.insert(inv, formatPetLine(pType, muta, ps, uid))
            end
        end
    end

    table.sort(placed, function(a,b) return a:lower() < b:lower() end)
    table.sort(inv,    function(a,b) return a:lower() < b:lower() end)
    return placed, inv
end

-- แปลง counter -> รายการบรรทัด และเรียงชื่อ
local function counterToLines(counter)
    local items = {}
    for key, n in pairs(counter) do
        table.insert(items, string.format("%s — x%d", key, n))
    end
    table.sort(items, function(a,b) return a:lower() < b:lower() end)
    return items
end

-- นับจำนวนสัตว์แยกเป็น 2 กลุ่ม: วางอยู่ / อยู่ในคลัง
-- inventory ใช้ mapping T/M จาก OwnedEggData ตาม requirement
local function collectPetCountsSplit()
    local placedCounter   = {}
    local inventoryCounter= {}

    -- map UID ของที่วางอยู่
    local modelsByUID = {}
    local petsFolder = workspace:FindFirstChild("Pets")
    if petsFolder then
        for _, model in ipairs(petsFolder:GetChildren()) do
            if model:GetAttribute("UserId") == Player.UserId then
                modelsByUID[tostring(model)] = model
            end
        end
    end

    if OwnedPetData then
        for _, node in ipairs(OwnedPetData:GetChildren()) do
            local uid = node.Name
            if modelsByUID[uid] then
                -- วางอยู่: ใช้ T/M จากตัว model/ข้อมูลเดิมก็ได้
                local t = getAttrOrChildValue(node, "T") or "Unknown"
                local m = getAttrOrChildValue(node, "M") or "None"
                local key = string.format("%s | %s", tostring(t), tostring(m))
                placedCounter[key] = (placedCounter[key] or 0) + 1
            else
                -- inventory: map จาก egg
                local t, m = map_type_muta_from_eggs(uid, node)
                local key = string.format("%s | %s", tostring(t), tostring(m))
                inventoryCounter[key] = (inventoryCounter[key] or 0) + 1
            end
        end
    end

    return counterToLines(placedCounter), counterToLines(inventoryCounter)
end

-- นับจำนวนรวม (Type | Mutate) - inventory ใช้ egg mapping
local function collectPetCounts()
    local counter = {}
    if OwnedPetData then
        -- สร้างชุด uid ที่วางอยู่
        local placedUID = {}
        local petsFolder = workspace:FindFirstChild("Pets")
        if petsFolder then
            for _, model in ipairs(petsFolder:GetChildren()) do
                if model:GetAttribute("UserId") == Player.UserId then
                    placedUID[tostring(model)] = true
                end
            end
        end

        for _, node in ipairs(OwnedPetData:GetChildren()) do
            local uid = node.Name
            local t, m
            if placedUID[uid] then
                t = getAttrOrChildValue(node, "T") or "Unknown"
                m = getAttrOrChildValue(node, "M") or "None"
            else
                t, m = map_type_muta_from_eggs(uid, node)
            end
            local key = string.format("%s | %s", tostring(t), tostring(m))
            counter[key] = (counter[key] or 0) + 1
        end
    end

    local items = {}
    for key, n in pairs(counter) do
        table.insert(items, string.format("%s — x%d", key, n))
    end
    table.sort(items, function(a,b) return a:lower() < b:lower() end)
    return items
end

-- Eggs / Foods เหมือนเดิม
local function collectEggs()
    local counter = {}
    if OwnedEggData then
        for _, egg in ipairs(OwnedEggData:GetChildren()) do
            if egg and not egg:FindFirstChild("DI") then
                local eggType   = getAttrOrChildValue(egg, "T") or "Unknown"
                local mutation  = getAttrOrChildValue(egg, "M") or "None"
                local key = string.format("%s | %s", tostring(eggType), tostring(mutation))
                counter[key] = (counter[key] or 0) + 1
            end
        end
    end
    local items = {}
    for key, count in pairs(counter) do
        table.insert(items, string.format("%s — x%d", key, count))
    end
    table.sort(items)
    return items
end

local function collectFoods()
    local attrs = InventoryData and InventoryData:GetAttributes() or {}
    local items = {}
    for k, v in pairs(attrs) do
        table.insert(items, string.format("%s x%s", tostring(k), tostring(v)))
    end
    table.sort(items)
    return items
end

-- === ส่งเป็น 3 ข้อความ แยกส่วนชัดเจน ===
local function sendAll()
    local header = ("📦 Inventory ของ **%s**"):format(Player.Name)
    SendMessage(header)

    local placed, inv = collectPets()
    local eggs  = collectEggs()
    local foods = collectFoods()
    local placedCounts, invCounts = collectPetCountsSplit()

    local function sendLong(prefix, linesTable)
        local body = (#linesTable > 0) and table.concat(linesTable, "\n") or "ไม่มี"
        local MAX = 1900
        if #body <= MAX then
            SendMessage(prefix .. "\n" .. body)
        else
            SendMessage(prefix)
            local acc, len = {}, 0
            for _, line in ipairs(linesTable) do
                local piece = (len == 0) and line or ("\n" .. line)
                if len + #piece > MAX then
                    SendMessage(table.concat(acc))
                    acc, len = {line}, #line
                else
                    table.insert(acc, piece); len = len + #piece
                end
            end
            if #acc > 0 then SendMessage(table.concat(acc)) end
        end
    end

    sendLong("🐾 **Pets (สัตว์ที่วางอยู่: ประเภท | กลายพันธ์ุ | เงินที่ได้ต่อวินาที)**", placed)
    sendLong("📦 **Pets (สัตว์ในกระเป๋า: ประเภท | กลายพันธ์ุ | เงินที่ได้ต่อวินาที)**", inv)

    sendLong("🔢 **Pet Counts — สัตว์ที่วางอยู่ (Type | Mutate)**",   placedCounts)
    sendLong("🔢 **Pet Counts — สัตว์ในกระเป๋า (Type | Mutate)**", invCounts)

    sendLong("🥚 **Eggs (ประเภท | กลายพันธ์ุ)**", eggs)
    sendLong("🍖 **Foods**", foods)
end

-- เรียกครั้งเดียว
sendAll()

-- // ถ้าต้องการอัปเดตเรื่อย ๆ
-- task.spawn(function()
--     while true do
--         sendAll()
--         task.wait(30)
--     end
-- end)

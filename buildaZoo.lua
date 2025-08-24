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
    local v = inst:GetAttribute(attrName)
    if v ~= nil then return v end
    local c = inst:FindFirstChild(childNameFallback or attrName)
    if c and c:IsA("ValueBase") then return c.Value end
    return nil
end

-- ===== Helpers for config lookup (ใช้คำนวณ speed ของสัตว์ใน inventory) =====
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

-- ดึง base speed ต่อชนิดสัตว์ (ปรับชื่อคีย์ตามเกมจริงได้)
local function base_ps_from_type(pType)
    if not (ResPet and ResPet.__index and pType) then return nil end
    local row = ResPet.__index[pType]
    if type(row) ~= "table" then return nil end
    return first_number_by_keys(row, {"ProduceSpeed","ProdSpeed","PS","produceSpeed","speed","rate"})
end

-- ดึงตัวคูณจาก mutation (ถ้ามีใน config)
local function multiplier_from_mutate(muta)
    if not (ResMutate and ResMutate.__index and muta) then return 1 end
    local row = ResMutate.__index[muta]
    if type(row) ~= "table" then return 1 end
    local mul = first_number_by_keys(row, {"Multiplier","Multiply","Rate","PSMul","ProduceMul","x","mul"})
    if type(mul) == "number" and mul > 0 then return mul end
    return 1
end

-- คำนวณ ProduceSpeed สำหรับ node ใน Data.Pets (ใช้เมื่อ "ยังไม่วาง")
local function compute_ps_for_node(node)
    local pType = getAttrOrChildValue(node, "T") or "Unknown"
    local muta  = getAttrOrChildValue(node, "M") or "None"

    local ps = base_ps_from_type(pType)
    if ps then
        ps = ps * (multiplier_from_mutate(muta) or 1)
        return ps, pType, muta
    end

    -- fallback กันพัง ถ้า config ไม่มีจริง ๆ
    local BPV = tonumber(getAttrOrChildValue(node, "BPV"))
    local FT  = tonumber(getAttrOrChildValue(node, "FT"))
    if BPV and FT and FT ~= 0 then
        return (BPV / FT), pType, muta
    end

    return 0, pType, muta
end

-- === Collectors ===
-- คืนค่าเป็น 2 ตาราง: placedItems, inventoryItems
-- placed: อ่าน ProduceSpeed จาก RootPart
-- inventory: คิดจาก Config ตาม T/M (หรือ fallback BPV/FT)
local function collectPets()
    local placed, inv = {}, {}

    -- 1) เก็บ Model ที่ "วางอยู่" ของผู้เล่น
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
                    table.insert(placed, string.format(
                        "%s | %s — %s / sec (UID: %s)",
                        tostring(petType), tostring(muta), tostring(ps), tostring(model)
                    ))
                end
            end
        end
    end

    -- 2) เดิน Data.Pets ทั้งหมด → ถ้า "ไม่มี model อยู่ในโลก" ให้ถือว่าเป็น inventory
    if OwnedPetData then
        for _, node in ipairs(OwnedPetData:GetChildren()) do
            local uid = node.Name
            if not modelsByUID[uid] then
                local ps, pType, muta = compute_ps_for_node(node)
                table.insert(inv, string.format(
                    "%s | %s — %s / sec (UID: %s)",
                    tostring(pType), tostring(muta), tostring(ps or 0), uid
                ))
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
local function collectPetCountsSplit()
    local placedCounter   = {}  -- ["Panther | Dino"] = #
    local inventoryCounter= {}

    -- ทำแผนที่ UID -> model ของสัตว์ที่ "วางอยู่"
    local modelsByUID = {}
    local petsFolder = workspace:FindFirstChild("Pets")
    if petsFolder then
        for _, model in ipairs(petsFolder:GetChildren()) do
            if model:GetAttribute("UserId") == Player.UserId then
                modelsByUID[tostring(model)] = model
            end
        end
    end

    -- เดิน Data.Pets ทั้งหมด แล้วจัดเข้ากลุ่มตามว่ามี model อยู่ในโลกหรือไม่
    if OwnedPetData then
        for _, node in ipairs(OwnedPetData:GetChildren()) do
            local t = getAttrOrChildValue(node, "T") or "Unknown"
            local m = getAttrOrChildValue(node, "M") or "None"
            local key = string.format("%s | %s", tostring(t), tostring(m))

            if modelsByUID[node.Name] then
                placedCounter[key] = (placedCounter[key] or 0) + 1
            else
                inventoryCounter[key] = (inventoryCounter[key] or 0) + 1
            end
        end
    end

    return counterToLines(placedCounter), counterToLines(inventoryCounter)
end

-- นับจำนวนสัตว์ตามคู่ (Type | Mutate)
local function collectPetCounts()
    local counter = {}   -- counter["Panther | Dino"] = 3
    if OwnedPetData then
        for _, node in ipairs(OwnedPetData:GetChildren()) do
            local t = getAttrOrChildValue(node, "T") or "Unknown"
            local m = getAttrOrChildValue(node, "M") or "None"
            local key = string.format("%s | %s", tostring(t), tostring(m))
            counter[key] = (counter[key] or 0) + 1
        end
    end

    -- แปลงเป็นบรรทัดข้อความ และเรียงให้อ่านง่าย
    local items = {}
    for key, n in pairs(counter) do
        table.insert(items, string.format("%s — x%d", key, n))
    end
    table.sort(items, function(a,b) return a:lower() < b:lower() end)
    return items
end



local function collectEggs()
    local counter = {} -- [ "Type | Mutate" ] = count
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
    local placedCounts, invCounts = collectPetCountsSplit()  -- << เพิ่ม

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

    sendLong("🐾 **Pets (Placed: Type | Mutate | ProduceSpeed)**", placed)
    sendLong("📦 **Pets (Inventory: Type | Mutate | ProduceSpeed)**", inv)

    -- << ใหม่: สรุปจำนวนแบบแยก
    sendLong("🔢 **Pet Counts — Placed (Type | Mutate)**",   placedCounts)
    sendLong("🔢 **Pet Counts — Inventory (Type | Mutate)**", invCounts)

    sendLong("🥚 **Eggs (Type | Mutate)**", eggs)
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

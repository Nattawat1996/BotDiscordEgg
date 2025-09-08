--==============================================================
-- Build A Zoo (PlaceId 105555311806207)
-- Cleaned: removed duplicate vars, single reservation system, proper ordering
--==============================================================
if game.PlaceId ~= 105555311806207 then return end

--== Guard re-run
if MeowyBuildAZoo then MeowyBuildAZoo:Destroy() end
repeat task.wait(1) until game:IsLoaded()

--== Libs
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

--== Services / Globals
local RunningEnvirontments = true
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local PlayerUserID = Player.UserId
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GameName = (MarketplaceService:GetProductInfo(game.PlaceId)["Name"]) or "None"

local Data = Player:WaitForChild("PlayerGui",60):WaitForChild("Data",60)
local ServerTime = ReplicatedStorage:WaitForChild("Time")
local InGameConfig = ReplicatedStorage:WaitForChild("Config")
local ServerReplicatedDict = ReplicatedStorage:WaitForChild("ServerDictReplicated")
local GameRemoteEvents = ReplicatedStorage:WaitForChild("Remote",30)

local Pet_Folder = workspace:WaitForChild("Pets")
local BlockFolder = workspace:WaitForChild("PlayerBuiltBlocks")
local IslandName = Player:GetAttribute("AssignedIslandName")
local Island = workspace:WaitForChild("Art"):WaitForChild(IslandName)

local Egg_Belt_Folder = ReplicatedStorage:WaitForChild("Eggs"):WaitForChild(IslandName)
local OwnedPetData = Data:WaitForChild("Pets")
local OwnedEggData = Data:WaitForChild("Egg")
local InventoryData = Data:WaitForChild("Asset",30)

local EnvirontmentConnections = {}
local Players_InGame = {}

--== Game Res tables
local Eggs_InGame       = require(InGameConfig:WaitForChild("ResEgg"))["__index"]
local Mutations_InGame  = require(InGameConfig:WaitForChild("ResMutate"))["__index"]
local PetFoods_InGame   = require(InGameConfig:WaitForChild("ResPetFood"))["__index"]
local Pets_InGame       = require(InGameConfig:WaitForChild("ResPet"))["__index"]

--== Remotes
local PetRE        = GameRemoteEvents:WaitForChild("PetRE", 30)
local CharacterRE  = GameRemoteEvents:WaitForChild("CharacterRE", 30)

--==============================================================
--                          HELPERS
--==============================================================

-- Emoji / order for mutation summary
local MUTA_EMOJI = setmetatable({
    ["None"]     = "🥚",
    ["Fire"]     = "🔥",
    ["Electirc"] = "⚡",
    ["Diamond"]  = "💎",
    ["Golden"]   = "🪙",
    ["Dino"]     = "🦖",
}, { __index = function() return "🔹" end })
local MUTA_ORDER = { "None","Fire","Electirc","Diamond","Golden","Dino" }
local ORDER_SET = {}; for _,k in ipairs(MUTA_ORDER) do ORDER_SET[k]=true end

-- Count unplaced eggs grouped by Type→Mutation
local function CountEggsByTypeMuta()
    local map = {}
    for _, egg in ipairs(OwnedEggData:GetChildren()) do
        if egg and not egg:FindFirstChild("DI") then
            local t = egg:GetAttribute("T") or "BasicEgg"
            local m = egg:GetAttribute("M") or "None"
            map[t] = map[t] or {}
            map[t][m] = (map[t][m] or 0) + 1
        end
    end
    return map
end

-- Island cell name helpers
local function isWaterName(s) return s and s:find("WaterFarm") ~= nil end
local function isLandName(s)  return s and (s:find("Farm") ~= nil) and not isWaterName(s) end

-- Key helpers
local function _key_from_coord(v) return v and (tostring(v.X)..","..tostring(v.Z)) or nil end
local function _key_from_pos(v)   return ("POS:%d,%d"):format(math.floor(v.X+0.5), math.floor(v.Z+0.5)) end

-- Anchor finder (Model/BasePart)
local function anchorOf(inst: Instance)
    if inst:IsA("Model") then
        return inst.PrimaryPart
            or inst:FindFirstChild("RootPart")
            or inst:FindFirstChildWhichIsA("BasePart")
    elseif inst:IsA("BasePart") then
        return inst
    else
        return inst:FindFirstChildWhichIsA("BasePart")
    end
end

-- Proximity occupancy check
local function IsOccupiedAtPosition(pos: Vector3, radius: number?)
    local R = radius or 5
    for _, P in ipairs(Pet_Folder:GetChildren()) do
        local rp = anchorOf(P)
        if rp and (rp.Position - pos).Magnitude <= R then return true end
    end
    for _, child in ipairs(BlockFolder:GetChildren()) do
        local rp = anchorOf(child)
        if rp and (rp.Position - pos).Magnitude <= R then return true end
    end
    for _, E in ipairs(OwnedEggData:GetChildren()) do
        local di = E:FindFirstChild("DI")
        if di then
            local v = Vector3.new(di:GetAttribute("X") or 0, 0, di:GetAttribute("Z") or 0)
            if (Vector3.new(v.X,0,v.Z) - Vector3.new(pos.X,0,pos.Z)).Magnitude <= R then return true end
        end
    end
    return false
end

-- Build unique grid list (dedupe + sorted) and area sets
local GridByArea = { Any = {}, Land = {}, Water = {} }
local LandCoordKeySet, WaterCoordKeySet = {}, {}
do
    local seen = {}
    local function push(area, key, pos, coord)
        if not seen[key] then
            seen[key] = true
            local item = { key = key, pos = pos, coord = coord, area = area }
            table.insert(GridByArea.Any, item)
            table.insert(GridByArea[area], item)
            -- เก็บเฉพาะช่องที่มี coord สำหรับตรวจชนิดพื้นที่จาก GridCoord
            if coord then
                local ck = _key_from_coord(coord)
                if area == "Land"  then LandCoordKeySet[ck]  = true end
                if area == "Water" then WaterCoordKeySet[ck] = true end
            end
        end
    end

    for _, grid in ipairs(Island:GetDescendants()) do
        if grid:IsA("BasePart") then
            local name = tostring(grid.Name or "")
            local area = isWaterName(name) and "Water" or (isLandName(name) and "Land" or nil)
            if area then
                local coord = grid:GetAttribute("IslandCoord")
                local pos   = grid.Position
                local key   = coord and _key_from_coord(coord) or _key_from_pos(pos)
                push(area, key, pos, coord)
            end
        end
    end

    local function sort2D(t)
        table.sort(t, function(a,b)
            if a.pos.Z == b.pos.Z then return a.pos.X < b.pos.X end
            return a.pos.Z < b.pos.Z
        end)
    end
    sort2D(GridByArea.Any);  sort2D(GridByArea.Land);  sort2D(GridByArea.Water)
end

-- World-accurate occupied map
local function _occupied_world()
    local occ = {}
    for _, P in ipairs(Pet_Folder:GetChildren()) do
        local rp = anchorOf(P)
        if rp then occ[_key_from_pos(rp.Position)] = true end
    end
    for _, B in ipairs(BlockFolder:GetChildren()) do
        local rp = anchorOf(B)
        if rp then occ[_key_from_pos(rp.Position)] = true end
    end
    for _, E in ipairs(OwnedEggData:GetChildren()) do
        local di = E:FindFirstChild("DI")
        if di then
            local v = Vector3.new(di:GetAttribute("X") or 0, 0, di:GetAttribute("Z") or 0)
            occ[_key_from_pos(v)] = true
        end
    end
    return occ
end

-- Reservation (avoid double use before server confirms)
local _reserve, _placingBusy = {}, false  -- << single source of truth
local function _reservePrune()
    local now = os.clock()
    for k,exp in pairs(_reserve) do
        if exp <= now then _reserve[k] = nil end
    end
end
local function _reserveAdd(key, ttl) _reserve[key] = os.clock() + (ttl or 4.0) end
local function _reserveDel(key) _reserve[key] = nil end

-- Per-area cursor so we continue to next cell
local NextIdx = { Any = 1, Land = 1, Water = 1 }
local function _listFor(area)
    if area == "Land" then return GridByArea.Land, "Land"
    elseif area == "Water" then return GridByArea.Water, "Water"
    else return GridByArea.Any, "Any" end
end

-- Iterator-style next free grid (returns pos,key,idx,canonArea)
local function GetNextFreeGrid(area)
    _reservePrune()
    local list, canonArea = _listFor(area)
    if #list == 0 then return nil end

    local occ   = _occupied_world()
    local start = NextIdx[canonArea] or 1

    for i = 0, #list - 1 do
        local idx = ((start - 1 + i) % #list) + 1
        local g   = list[idx]
        local key = g.key
        if not _reserve[key] and not occ[key] and not IsOccupiedAtPosition(g.pos, 5) then
            _reserveAdd(key, 4.0)
            NextIdx[canonArea] = ((idx) % #list) + 1
            return g.pos, key, idx, canonArea
        end
    end
    return nil
end

-- Small vector factory (kept for network args signature)
local vector = { create = function(x,y,z) return Vector3.new(x,y,z) end }

-- White overlay fallback for perf when 3D is disabled
local function _toggleWhiteOverlay(show)
    local pg = Player:FindFirstChild("PlayerGui")
    if not pg then return end
    local gui = pg:FindFirstChild("PerfWhite") or Instance.new("ScreenGui")
    if not gui.Parent then
        gui.Name = "PerfWhite"
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 1e9
        gui.ResetOnSpawn = false
        gui.Parent = pg
        local f = Instance.new("Frame")
        f.Name = "F"
        f.Size = UDim2.fromScale(1,1)
        f.BackgroundColor3 = Color3.new(1,1,1)
        f.BackgroundTransparency = 0
        f.Parent = gui
    end
    local frame = gui:FindFirstChild("F")
    if frame then frame.BackgroundTransparency = show and 0 or 1 end
    gui.Enabled = show
end

-- Toggle 3D rendering (with fallback)
local function Perf_Set3DEnabled(enable3D)
    local ok = pcall(function() RunService:Set3dRenderingEnabled(enable3D) end)
    if ok then _toggleWhiteOverlay(false) else _toggleWhiteOverlay(not enable3D) end
end

-- Read “income/sec” of an inventory pet by UID from PlayerGui
local function GetInventoryIncomePerSecByUID(uid: string)
    if not uid or uid == "" then return nil end
    local pg = Player:FindFirstChild("PlayerGui"); if not pg then return nil end
    local screenStorage = pg:FindFirstChild("ScreenStorage"); if not screenStorage then return nil end
    local frame = screenStorage:FindFirstChild("Frame"); if not frame then return nil end
    local contentPet = frame:FindFirstChild("ContentPet"); if not contentPet then return nil end
    local scrolling = contentPet:FindFirstChild("ScrollingFrame"); if not scrolling then return nil end

    local item = scrolling:FindFirstChild(uid)
    if not item then
        for _, ch in ipairs(scrolling:GetChildren()) do
            if ch.Name == uid then item = ch break end
        end
    end
    if not item then return nil end

    local btn  = item:FindFirstChild("BTN") or item:FindFirstChildWhichIsA("Frame")
    if not btn then return nil end
    local stat = btn:FindFirstChild("Stat") or btn:FindFirstChildWhichIsA("Frame")
    if not stat then return nil end
    local price = stat:FindFirstChild("Price") or stat:FindFirstChildWhichIsA("Frame")
    if not price then return nil end

    local valueObj = price:FindFirstChild("Value")
    if valueObj then
        if valueObj:IsA("NumberValue") or valueObj:IsA("IntValue") then
            return tonumber(valueObj.Value)
        elseif valueObj:IsA("StringValue") then
            local s = tostring(valueObj.Value or "")
            local n = tonumber((s:gsub("[^%d%.]", "")))
            return n
        end
    end

    local function readText(inst)
        local ok, txt = pcall(function() return inst.Text end)
        if ok and txt then
            local n = tonumber((tostring(txt):gsub("[^%d%.]", "")))
            if n then return n end
        end
        return nil
    end
    local n = readText(price); if n then return n end
    local textLike = price:FindFirstChildWhichIsA("TextLabel") or price:FindFirstChildWhichIsA("TextButton")
    if textLike then n = readText(textLike); if n then return n end end
    for _, d in ipairs(price:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            n = readText(d); if n then return n end
        end
    end
    return nil
end

-- Read $ text to number
local function GetCash(TXT)
    if not TXT then return 0 end
    local cash = string.gsub(TXT,"[$,]","")
    return tonumber(cash) or 0
end

-- Area of gridcoord
local function areaOfCoord(v3)
    if not v3 then return "Any" end
    local k = _key_from_coord(v3)
    if WaterCoordKeySet[k] then return "Water" end
    if LandCoordKeySet[k]  then return "Land"  end
    return "Any"
end

-- Determine pet/egg area
local OwnedPets = {} -- forward
local function petArea(uid: string)
    local diFolder = OwnedPetData and OwnedPetData:FindFirstChild(uid)
    local di = diFolder and diFolder:FindFirstChild("DI")
    if not di then
        local P = OwnedPets and OwnedPets[uid]
        return P and areaOfCoord(P.GridCoord) or "Any"
    end
    local v = Vector3.new(di:GetAttribute("X") or 0, di:GetAttribute("Y") or 0, di:GetAttribute("Z") or 0)
    return areaOfCoord(v)
end
local function eggArea(eggInst: Instance)
    if not eggInst then return "Any" end
    local di = eggInst:FindFirstChild("DI"); if not di then return "Any" end
    local v = Vector3.new(di:GetAttribute("X") or 0, di:GetAttribute("Y") or 0, di:GetAttribute("Z") or 0)
    return areaOfCoord(v)
end

-- Sell helpers
local function SellEgg(uid: string)
    if not uid or uid == "" then return false, "no uid" end
    CharacterRE:FireServer("Focus", uid) task.wait(0.1)
    local ok, err = pcall(function() PetRE:FireServer("Sell", uid, true) end)
    CharacterRE:FireServer("Focus")
    return ok, err
end
local function SellPet(uid: string)
    if not uid or uid == "" then return false, "no uid" end
    CharacterRE:FireServer("Focus", uid) task.wait(0.1)
    local ok, err = pcall(function() PetRE:FireServer("Sell", uid) end)
    CharacterRE:FireServer("Focus")
    return ok, err
end

-- Snap to surface (raycast) for place DST
local function GroundAtGrid(gridPos)
    local origin = gridPos + Vector3.new(0, 200, 0)
    local dir = Vector3.new(0, -1000, 0)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = {Player.Character}
    local hit = workspace:Raycast(origin, dir, rp)
    if hit then return hit.Position + Vector3.new(0, 1.5, 0) end
    return gridPos + Vector3.new(0, 6, 0)
end

-- Teleport near destination if too far
local function ensureNear(position, maxDist)
    local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if (hrp.Position - position).Magnitude > (maxDist or 12) then
        hrp.CFrame = CFrame.new(position + Vector3.new(0, 3.5, 0))
        task.wait(0.4)
    end
end

-- Wait confirmations
local function waitEggPlaced(eggCfg, timeout)
    local t0 = tick()
    while tick() - t0 < (timeout or 2.5) do
        if eggCfg:FindFirstChild("DI") then return true end
        task.wait(0.1)
    end
    return false
end
local function waitPetPlaced(uid, timeout)
    local t0 = tick()
    while tick() - t0 < (timeout or 2.5) do
        if OwnedPets and OwnedPets[uid] ~= nil then return true end
        task.wait(0.1)
    end
    return false
end

-- Pick first selected food that still has stock (for SelectFood mode)
local function pickFoodSelect(invAttrs)
    for _, name in ipairs(PetFoods_InGame) do
        if Configuration.Pet.AutoFeed_Foods[name] then
            local have = tonumber(invAttrs[name] or 0) or 0
            if have > 0 then return name end
        end
    end
    return nil
end

--==============================================================
--              DYNAMIC STATE (OwnedPets, Egg_Belt, etc.)
--==============================================================
local Players_List_Updated = Instance.new("BindableEvent")
table.insert(EnvirontmentConnections,Players.PlayerRemoving:Connect(function(plr)
    local idx = table.find(Players_InGame,plr.Name)
    if idx then table.remove(Players_InGame,idx) end
    Players_List_Updated:Fire(Players_InGame)
end))
table.insert(EnvirontmentConnections,Players.PlayerAdded:Connect(function(plr)
    table.insert(Players_InGame,plr.Name)
    Players_List_Updated:Fire(Players_InGame)
end))
for _,plr in pairs(Players:GetPlayers()) do table.insert(Players_InGame,plr.Name) end

local Egg_Belt = {}

table.insert(EnvirontmentConnections,Egg_Belt_Folder.ChildRemoved:Connect(function(egg)
    task.wait(0.1); local eggUID = tostring(egg) or "None"
    if egg and Egg_Belt[eggUID] then Egg_Belt[eggUID] = nil end
end))
table.insert(EnvirontmentConnections,Egg_Belt_Folder.ChildAdded:Connect(function(egg)
    task.wait(0.1); local eggUID = tostring(egg) or "None"
    if egg then
        Egg_Belt[eggUID] = {
            UID = eggUID,
            Mutate = (egg:GetAttribute("M") or "None"),
            Type = (egg:GetAttribute("T") or "BasicEgg")
        }
    end
end))
for _,egg in pairs(Egg_Belt_Folder:GetChildren()) do
    task.spawn(pcall,function()
        local eggUID = tostring(egg) or "None"
        if egg then
            Egg_Belt[eggUID] = {
                UID = eggUID,
                Mutate = (egg:GetAttribute("M") or "None"),
                Type = (egg:GetAttribute("T") or "BasicEgg")
            }
        end
    end)
end

table.insert(EnvirontmentConnections,Pet_Folder.ChildRemoved:Connect(function(pet)
    task.wait(0.1)
    local petUID = tostring(pet) or "None"
    if pet and OwnedPets[petUID] then OwnedPets[petUID] = nil end
end))

table.insert(EnvirontmentConnections,Pet_Folder.ChildAdded:Connect(function(pet)
    task.wait(0.1)
    local petUID = tostring(pet) or "None"
    local IsOwned = pet:GetAttribute("UserId") == PlayerUserID
    if not IsOwned then return end
    local petPrimaryPart = pet and (pet.PrimaryPart or pet:FindFirstChild("RootPart") or pet:WaitForChild("RootPart"))
    local CashBillboard = petPrimaryPart and (petPrimaryPart:FindFirstChild("GUI/IdleGUI") or petPrimaryPart:WaitForChild("GUI/IdleGUI"))
    local CashFrame = CashBillboard and (CashBillboard:FindFirstChild("CashF") or CashBillboard:WaitForChild("CashF"))
    local CashTXT = CashFrame and (CashFrame:FindFirstChild("TXT") or CashFrame:WaitForChild("TXT"))
    local GridCoord = OwnedPetData and OwnedPetData:WaitForChild(petUID):WaitForChild("DI")
    GridCoord = GridCoord and Vector3.new(GridCoord:GetAttribute("X"),GridCoord:GetAttribute("Y"),GridCoord:GetAttribute("Z")) or nil
    if pet and IsOwned then
        OwnedPets[petUID] = setmetatable({
            GridCoord = GridCoord, UID = petUID,
            Type = (petPrimaryPart:GetAttribute("Type")),
            Mutate = (petPrimaryPart:GetAttribute("Mutate")),
            Model = pet, RootPart = petPrimaryPart,
            RE = (petPrimaryPart and petPrimaryPart:FindFirstChild("RE",true)),
            IsBig = (petPrimaryPart and (petPrimaryPart:GetAttribute("BigValue") ~= nil))
        },{
            __index = (function(tb, ind)
                if ind == "Coin" then
                    return (CashTXT and GetCash(CashTXT.Text))
                elseif ind == "ProduceSpeed" or ind == "PS" then
                    return (petPrimaryPart and petPrimaryPart:GetAttribute("ProduceSpeed")) or 0
                end
                return rawget(tb, ind)
            end)
        })
    end
end))

for _,pet in pairs(Pet_Folder:GetChildren()) do
    task.spawn(pcall,function()
        local petUID = tostring(pet) or "None"
        local IsOwned = pet:GetAttribute("UserId") == PlayerUserID
        if not IsOwned then return end
        local petPrimaryPart = pet and (pet.PrimaryPart or pet:FindFirstChild("RootPart") or pet:WaitForChild("RootPart"))
        local CashBillboard = petPrimaryPart and (petPrimaryPart:FindFirstChild("GUI/IdleGUI") or petPrimaryPart:WaitForChild("GUI/IdleGUI"))
        local CashFrame = CashBillboard and (CashBillboard:FindFirstChild("CashF") or CashBillboard:WaitForChild("CashF"))
        local CashTXT = CashFrame and (CashFrame:FindFirstChild("TXT") or CashFrame:WaitForChild("TXT"))
        local GridCoord = OwnedPetData and OwnedPetData:WaitForChild(petUID):WaitForChild("DI")
        GridCoord = GridCoord and Vector3.new(GridCoord:GetAttribute("X"),GridCoord:GetAttribute("Y"),GridCoord:GetAttribute("Z")) or nil
        OwnedPets[petUID] = setmetatable({
            GridCoord = GridCoord, UID = petUID,
            Type = (petPrimaryPart:GetAttribute("Type")),
            Mutate = (petPrimaryPart:GetAttribute("Mutate")),
            Model = pet, RootPart = petPrimaryPart,
            RE = (petPrimaryPart and petPrimaryPart:FindFirstChild("RE",true)),
            IsBig = (petPrimaryPart and (petPrimaryPart:GetAttribute("BigValue") ~= nil))
        },{
            __index = (function(tb, ind)
                if ind == "Coin" then
                    return (CashTXT and GetCash(CashTXT.Text))
                elseif ind == "ProduceSpeed" or ind == "PS" then
                    return (petPrimaryPart and petPrimaryPart:GetAttribute("ProduceSpeed")) or 0
                end
                return rawget(tb, ind)
            end)
        })
    end)
end

--==============================================================
--                      CONFIG / UI
--==============================================================
local Configuration = {
    Main = { AutoCollect=false, Collect_Delay=30, Collect_Type="Delay", Collect_Between={Min=100000,Max=1000000}, },
    Pet  = {
        AutoFeed=false, AutoFeed_Foods={}, AutoPlacePet=false, AutoFeed_Delay=3, AutoFeed_Type="",
        CollectPet_Type="All", CollectPet_Auto=false, CollectPet_Mutations={}, CollectPet_Pets={},
        CollectPet_Delay=5, CollectPet_Between={Min=100000,Max=1000000}, CollectPet_Area="Any",
        PlacePet_Mode="All", PlacePet_Types={}, PlacePet_Mutations={}, AutoPlacePet_Delay=1.0,
        PlacePet_Between={Min=0,Max=1000000}, PlaceArea="Any",
    },
    Egg = {
        AutoHatch=false, Hatch_Delay=15, AutoBuyEgg=false, AutoBuyEgg_Delay=1,
        AutoPlaceEgg=false, AutoPlaceEgg_Delay=1.0, Mutations={}, Types={},
        CheckMinCoin=false, MinCoin=0, PlaceArea="Any", HatchArea="Any",
    },
    Shop = { Food = { AutoBuy=false, AutoBuy_Delay=1, Foods={} } },
    Players = {
        SelectPlayer="", SelectType="", SendPet_Type="All", Pet_Type={}, Pet_Mutations={},
        Food_Selected={}, Food_Amounts={}, Food_AmountPick="",
        Egg_Types={}, Egg_Mutations={}, GiftPet_Between={Min=0,Max=1000000}, Gift_Limit="",
    },
    Sell = {
        Mode="", Egg_Types={}, Egg_Mutations={}, Pet_Income_Threshold=0,
    },
    Perf = { Disable3D=false },
    Lottery = { Auto=false, Delay=1800, Count=1 },
    Event = { AutoClaim=false, AutoClaim_Delay=3, AutoLottery=false, AutoLottery_Delay=60 },
    AntiAFK=false, Waiting=false,
}

--== Event data
local EventTaskData; local ResEvent; local EventName="None";
for _,Data_Folder in pairs(Data:GetChildren()) do
    local IsEventTaskData = (tostring(Data_Folder):match("^(.*)EventTaskData$"))
    if IsEventTaskData then EventTaskData = Data_Folder break end
end
for _,v in pairs(ReplicatedStorage:GetChildren()) do
    local IsEventData = (tostring(v):match("^(.*)Event$"))
    if IsEventData then ResEvent = v EventName = IsEventData break end
end

--== Window / Tabs
local Window = Fluent:CreateWindow({
    Title = GameName, SubTitle = "by DemiGodz", TabWidth = 160,
    Size = UDim2.fromOffset(522, 414), Acrylic = true, Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})
local Tabs = {
    About = Window:AddTab({ Title = "About" }),
    Main = Window:AddTab({ Title = "Main Features" }),
    Pet = Window:AddTab({ Title = "Pet Features" }),
    Egg = Window:AddTab({ Title = "Egg Features" }),
    Shop = Window:AddTab({ Title = "Shop Features" }),
    Event = Window:AddTab({ Title = "Event Feature" }),
    Players = Window:AddTab({ Title = "Players Features" }),
    Sell = Window:AddTab({ Title = "Sell Features" }),
    Inv = Window:AddTab({ Title = "Inventory" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}
local Options = Fluent.Options

--============================== Main ==============================
Tabs.Main:AddSection("Main")
Tabs.Main:AddToggle("AutoCollect",{ Title = "Auto Collect", Default = false, Callback = function(v) Configuration.Main.AutoCollect = v end })
Tabs.Main:AddSection("Settings")
Tabs.Main:AddSlider("AutoCollect Delay",{ Title = "Collect Delay", Default = 5, Min = 30, Max = 180, Rounding = 0, Callback = function(v) Configuration.Main.Collect_Delay = v end })
Tabs.Main:AddDropdown("CollectCash Type",{ Title = "Select Type", Values = {"Delay","Between"}, Multi = false, Default = "Delay", Callback = function(v) Configuration.Main.Collect_Type = v end })
Tabs.Main:AddInput("CollectCash_Num1",{ Title = "Min Coin", Default = 100000, Numeric = true, Finished = false, Callback = function(v) Configuration.Main.Collect_Between.Min = tonumber(v) end })
Tabs.Main:AddInput("CollectCash_Num2",{ Title = "Max Coin", Default = 1000000, Numeric = true, Finished = false, Callback = function(v) Configuration.Main.Collect_Between.Max = tonumber(v) end })

--============================== Pet ===============================
Tabs.Pet:AddSection("Main")
Tabs.Pet:AddToggle("Auto Feed",{ Title = "Auto Feed", Default = false, Callback = function(v) Configuration.Pet.AutoFeed = v end })
Tabs.Pet:AddToggle("Auto Collect Pet",{ Title = "Auto Collect Pet", Default = false, Callback = function(v) Configuration.Pet.CollectPet_Auto = v end })
Tabs.Pet:AddToggle("Auto Place Pet",{ Title = "Auto Place Pet", Default = false, Callback = function(v) Configuration.Pet.AutoPlacePet = v end })

Tabs.Pet:AddButton({
    Title = "Collect Pet",
    Description = "Collect Pets with Collect Pet Type (no BIG pet)",
    Callback = function()
        Window:Dialog({
            Title = "Collect Pet Alert", Content = "Are you sure?",
            Buttons = {
                { Title = "Yes", Callback = function()
                    local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE")
                    local CollectType = Configuration.Pet.CollectPet_Type
                    local areaWant = Configuration.Pet.CollectPet_Area
                    local function passArea(uid)
                        if areaWant == "Any" then return true end
                        return petArea(uid) == areaWant
                    end

                    if CollectType == "All" then
                        for UID, PetData in pairs(OwnedPets) do
                            if PetData and not PetData.IsBig and passArea(UID) then
                                if PetData.RE then PetData.RE:FireServer("Claim") end
                                CharacterRE:FireServer("Del", UID)
                            end
                        end

                    elseif CollectType == "Match Pet" then
                        for UID, PetData in pairs(OwnedPets) do
                            if PetData and not PetData.IsBig and passArea(UID)
                               and Configuration.Pet.CollectPet_Pets[PetData.Type] then
                                if PetData.RE then PetData.RE:FireServer("Claim") end
                                CharacterRE:FireServer("Del", UID)
                            end
                        end

                    elseif CollectType == "Match Mutation" then
                        for UID, PetData in pairs(OwnedPets) do
                            if PetData and not PetData.IsBig and passArea(UID)
                               and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                                if PetData.RE then PetData.RE:FireServer("Claim") end
                                CharacterRE:FireServer("Del", UID)
                            end
                        end

                    elseif CollectType == "Match Pet&Mutation" then
                        for UID, PetData in pairs(OwnedPets) do
                            if PetData and not PetData.IsBig and passArea(UID)
                               and Configuration.Pet.CollectPet_Pets[PetData.Type]
                               and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                                if PetData.RE then PetData.RE:FireServer("Claim") end
                                CharacterRE:FireServer("Del", UID)
                            end
                        end

                    elseif CollectType == "Range" then
                        local minV = tonumber(Configuration.Pet.CollectPet_Between.Min) or 0
                        local maxV = tonumber(Configuration.Pet.CollectPet_Between.Max) or math.huge
                        for UID, PetData in pairs(OwnedPets) do
                            if PetData and not PetData.IsBig and passArea(UID) then
                                local ps = tonumber(PetData.ProduceSpeed) or 0
                                if ps >= minV and ps <= maxV then
                                    if PetData.RE then PetData.RE:FireServer("Claim") end
                                    CharacterRE:FireServer("Del", UID)
                                end
                            end
                        end
                    end
                end },
                { Title = "No", Callback = function() end }
            }
        })
    end
})

Tabs.Pet:AddSection("Settings")
Tabs.Pet:AddSlider("AutoFeed Delay",{ Title = "Feed Delay", Default = 3, Min = 3, Max = 30, Rounding = 0, Callback = function(v) Configuration.Pet.AutoFeed_Delay = v end })
Tabs.Pet:AddSlider("AutoCollectPet Delay",{ Title = "Auto Collect Pet Delay", Default = 5, Min = 5, Max = 60, Rounding = 0, Callback = function(v) Configuration.Pet.CollectPet_Delay = v end })
Tabs.Pet:AddDropdown("Pet Feed_Type",{ Title = "Select Type", Values = {"BestFood","SelectFood"}, Multi = false, Default = "", Callback = function(v) Configuration.Pet.AutoFeed_Type = v end })
Tabs.Pet:AddDropdown("Pet Feed_Food",{ Title = "Select Foods", Values = PetFoods_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.AutoFeed_Foods = v end })
Tabs.Pet:AddDropdown("CollectPet Type",{ Title = "Collect Pet Type", Values = {"All","Match Pet","Match Mutation","Match Pet&Mutation","Range"}, Multi = false, Default = "All", Callback = function(v) Configuration.Pet.CollectPet_Type = v end })
Tabs.Pet:AddDropdown("CollectPet Area",{ Title = "Collect Pet Area", Values = {"Any","Land","Water"}, Multi = false, Default = "Any", Callback = function(v) Configuration.Pet.CollectPet_Area = v end })
Tabs.Pet:AddDropdown("CollectPet Pets",{ Title = "Collect Pets", Values = Pets_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.CollectPet_Pets = v end })
Tabs.Pet:AddDropdown("CollectPet Mutations",{ Title = "Collect Mutations", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.CollectPet_Mutations = v end })
Tabs.Pet:AddInput("CollectCash_Num1",{ Title = "Min Coin", Default = 100000, Numeric = true, Finished = false, Callback = function(v) Configuration.Pet.CollectPet_Between.Min = tonumber(v) end })
Tabs.Pet:AddInput("CollectCash_Num2",{ Title = "Max Coin", Default = 1000000, Numeric = true, Finished = false, Callback = function(v) Configuration.Pet.CollectPet_Between.Max = tonumber(v) end })

-- ====== Pet > Auto Place Pet UI ======
Tabs.Pet:AddSection("Auto Place Pet Settings")
Tabs.Pet:AddDropdown("PlacePet Area", {
    Title = "Place Area (Pet)",
    Values = {"Any","Land","Water"},
    Multi = false,
    Default = "Any",
    Callback = function(v) Configuration.Pet.PlaceArea = v end
})
Tabs.Pet:AddDropdown("PlacePet Mode", {
    Title = "Place Mode",
    Values = {"All","Match","Range"},
    Multi = false,
    Default = "All",
    Callback = function(v) Configuration.Pet.PlacePet_Mode = v end
})
Tabs.Pet:AddDropdown("PlacePet Types", {
    Title = "Place Types (Match)",
    Values = Pets_InGame, Multi = true, Default = {},
    Callback = function(v) Configuration.Pet.PlacePet_Types = v end
})
Tabs.Pet:AddDropdown("PlacePet Mutations", {
    Title = "Place Mutations (Match)",
    Values = Mutations_InGame, Multi = true, Default = {},
    Callback = function(v) Configuration.Pet.PlacePet_Mutations = v end
})
Tabs.Pet:AddSlider("AutoPlacePet Delay", {
    Title = "Auto Place Pet Delay", Description = "ดีเลย์การพยายามวางสัตว์ในแต่ละครั้ง (วิ)",
    Default = 1, Min = 0.1, Max = 5, Rounding = 1,
    Callback = function(v) Configuration.Pet.AutoPlacePet_Delay = v end
})
Tabs.Pet:AddInput("PlacePet_MinIncome", {
    Title = "Min income/s (Range)",
    Default = tostring(Configuration.Pet.PlacePet_Between.Min or 0),
    Numeric = true, Finished = true,
    Callback = function(v) Configuration.Pet.PlacePet_Between.Min = tonumber(v) or 0 end
})
Tabs.Pet:AddInput("PlacePet_MaxIncome", {
    Title = "Max income/s (Range)",
    Default = tostring(Configuration.Pet.PlacePet_Between.Max or 1000000),
    Numeric = true, Finished = true,
    Callback = function(v) Configuration.Pet.PlacePet_Between.Max = tonumber(v) or math.huge end
})

--============================== Egg ==============================
Tabs.Egg:AddSection("Main")
Tabs.Egg:AddToggle("Auto Hatch",{ Title = "Auto Hatch", Default = false, Callback = function(v) Configuration.Egg.AutoHatch = v end })
Tabs.Egg:AddToggle("Auto Egg",{ Title = "Auto Buy Egg", Default = false, Callback = function(v) Configuration.Egg.AutoBuyEgg = v end })
Tabs.Egg:AddToggle("Auto Place Egg",{ Title = "Auto Place Egg", Default = false, Callback = function(v) Configuration.Egg.AutoPlaceEgg = v end })
Tabs.Egg:AddToggle("CheckMinCoin",{ Title = "Check Min Coin", Default = false, Callback = function(v) Configuration.Egg.CheckMinCoin = v end })

Tabs.Egg:AddSection("Settings")
Tabs.Egg:AddDropdown("Hatch Area",{ Title = "Hatch Area", Values = {"Any","Land","Water"}, Multi = false, Default = "Any", Callback = function(v) Configuration.Egg.HatchArea = v end })
Tabs.Egg:AddSlider("AutoHatch Delay",{ Title = "Hatch Delay", Default = 15, Min = 15, Max = 60, Rounding = 0, Callback = function(v) Configuration.Egg.Hatch_Delay = v end })
Tabs.Egg:AddSlider("AutoBuyEgg Delay",{ Title = "Auto Buy Egg Delay", Default = 1, Min = 0.1, Max = 3, Rounding = 1, Callback = function(v) Configuration.Egg.AutoBuyEgg_Delay = v end })
Tabs.Egg:AddSlider("AutoPlaceEgg Delay",{ Title = "Auto Place Egg Delay", Default = 1, Min = 0.1, Max = 5, Rounding = 1, Callback = function(v) Configuration.Egg.AutoPlaceEgg_Delay = v end })
Tabs.Egg:AddDropdown("PlaceEgg Area", { Title = "Place Area (Egg)", Values = {"Any","Land","Water"}, Multi = false, Default = "Any", Callback = function(v) Configuration.Egg.PlaceArea = v end })
Tabs.Egg:AddDropdown("Egg Type",{ Title = "Types", Values = Eggs_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Egg.Types = v end })
Tabs.Egg:AddDropdown("Egg Mutations",{ Title = "Mutations", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Egg.Mutations = v end })
Tabs.Egg:AddInput("Min Coin to Buy", {
    Title = "Min Coin", Default = tostring(Configuration.Egg.MinCoin or 0),
    Numeric = true, Finished = true,
    Callback = function(v) Configuration.Egg.MinCoin = tonumber(v) or 0 end
})

--============================== Shop =============================
Tabs.Shop:AddSection("Main")
Tabs.Shop:AddToggle("Auto BuyFood",{ Title = "Auto Buy Food", Default = false, Callback = function(v) Configuration.Shop.Food.AutoBuy = v end })
Tabs.Shop:AddSection("Settings")
Tabs.Shop:AddSlider("AutoBuyFood Delay",{ Title = "Auto Buy Food Delay", Default = 1, Min = 0.1, Max = 3, Rounding = 1, Callback = function(v) Configuration.Shop.Food.AutoBuy_Delay = v end })
Tabs.Shop:AddDropdown("Foods Dropdown",{ Title = "Foods", Values = PetFoods_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Shop.Food.Foods = v end })

--============================== Event ============================
Tabs.Event:AddParagraph({ Title = "Event Information", Content = string.format("Current Event : %s",EventName) })
Tabs.Event:AddSection("Main")
Tabs.Event:AddToggle("Auto Claim Event Quest",{ Title = "Auto Claim", Default = false, Callback = function(v) Configuration.Event.AutoClaim = v end })
Tabs.Event:AddSection("Settings")
Tabs.Event:AddSlider("Event_AutoClaim Delay",{ Title = "Auto Claim Delay", Default = 3, Min = 3, Max = 30, Rounding = 0, Callback = function(v) Configuration.Event.AutoClaim_Delay = v end })

-- ===== Lottery (Auto Buy Ticket) =====
Tabs.Event:AddSection("Lottery")
Tabs.Event:AddToggle("Auto Lottery Ticket", { Title = "Auto Lottery Ticket", Default = false, Callback = function(v) Configuration.Event.AutoLottery = v end })
Tabs.Event:AddSlider("Lottery_Delay", { Title = "Buy Ticket Delay (sec)", Default = 60, Min = 60, Max = 7200, Rounding = 0, Callback = function(v) Configuration.Event.AutoLottery_Delay = v end })

--============================== Players ==========================
Tabs.Players:AddSection("Main")
Tabs.Players:AddButton({
    Title = "Send Gift", Description = "Send Gift",
    Callback = function()
        Window:Dialog({
            Title = "Send Gift Alert", Content = "Are you sure?",
            Buttons = {
                { Title = "Yes", Callback = function()
                    local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE")
                    local GiftRE = GameRemoteEvents:WaitForChild("GiftRE")
                    local GiftType = Configuration.Players.SelectType
                    local GiftPlayer = Players:FindFirstChild(Configuration.Players.SelectPlayer)
                    if not GiftPlayer then return end

                    local function _limit()
                        local n = tonumber(Configuration.Players.Gift_Limit)
                        return (n and n > 0) and n or math.huge
                    end
                    local LIMIT = _limit()
                    local sent = 0
                    local function sentOne()
                        sent = sent + 1
                        return sent >= LIMIT
                    end

                    Configuration.Waiting = true

                    if GiftType == "All_Pets" then
                        for _, PetData in pairs(OwnedPetData:GetChildren()) do
                            if PetData and not PetData:GetAttribute("D") then
                                CharacterRE:FireServer("Focus", PetData.Name) task.wait(0.75)
                                GiftRE:FireServer(GiftPlayer) task.wait(0.75)
                                if sentOne() then break end
                            end
                        end

                    elseif GiftType == "Range_Pets" then
                        local minV = tonumber(Configuration.Players.GiftPet_Between.Min) or 0
                        local maxV = tonumber(Configuration.Players.GiftPet_Between.Max) or math.huge

                        for _, PetData in pairs(OwnedPetData:GetChildren()) do
                            if PetData and not PetData:GetAttribute("D") then
                                local uid = PetData.Name
                                if not OwnedPets[uid] then
                                    local inc = GetInventoryIncomePerSecByUID(uid)
                                    if inc and inc >= minV and inc <= maxV then
                                        CharacterRE:FireServer("Focus", uid) task.wait(0.75)
                                        GiftRE:FireServer(GiftPlayer)      task.wait(0.75)
                                        if sentOne() then break end
                                    end
                                end
                            end
                        end

                    elseif GiftType == "Match Pet" then
                        for _, PetData in pairs(OwnedPetData:GetChildren()) do
                            if PetData then
                                local petType = PetData:GetAttribute("T")
                                if petType and Configuration.Players.Pet_Type[petType] then
                                    CharacterRE:FireServer("Focus", PetData.Name) task.wait(0.75)
                                    GiftRE:FireServer(GiftPlayer)                   task.wait(0.75)
                                    if sentOne() then break end
                                end
                            end
                        end

                    elseif GiftType == "Match Pet&Mutation" then
                        for _, PetData in pairs(OwnedPetData:GetChildren()) do
                            if PetData then
                                local t = PetData:GetAttribute("T")
                                local m = PetData:GetAttribute("M") or "None"
                                if t and m and Configuration.Players.Pet_Type[t] and Configuration.Players.Pet_Mutations[m] then
                                    CharacterRE:FireServer("Focus", PetData.Name) task.wait(0.75)
                                    GiftRE:FireServer(GiftPlayer)                   task.wait(0.75)
                                    if sentOne() then break end
                                end
                            end
                        end

                    elseif GiftType == "All_Eggs_And_Foods" then
                        if not InventoryData then InventoryData = Data:FindFirstChild("Asset") end
                        local invAttrs = (InventoryData and InventoryData:GetAttributes()) or {}

                        local LIMIT = _limit()
                        local sent  = 0
                        local function trySendFocus(name: string)
                            CharacterRE:FireServer("Focus", name) task.wait(0.75)
                            GiftRE:FireServer(GiftPlayer)         task.wait(0.75)
                            CharacterRE:FireServer("Focus")
                            sent = sent + 1
                            return (sent >= LIMIT)
                        end

                        for _, Egg in ipairs(OwnedEggData:GetChildren()) do
                            if Egg and not Egg:FindFirstChild("DI") then
                                if trySendFocus(Egg.Name) then break end
                            end
                        end
                        if sent < LIMIT then
                            for foodName, amount in pairs(invAttrs) do
                                if table.find(PetFoods_InGame, foodName) and (tonumber(amount) or 0) > 0 then
                                    local canSend = math.max(0, math.min(tonumber(amount) or 0, LIMIT - sent))
                                    for i = 1, canSend do
                                        if trySendFocus(foodName) then break end
                                    end
                                    if sent >= LIMIT then break end
                                end
                            end
                        end

                    elseif GiftType == "All_Foods" then
                        if not InventoryData then InventoryData = Data:FindFirstChild("Asset") end
                        for FoodName,FoodAmount in pairs(InventoryData:GetAttributes()) do
                            if FoodName and table.find(PetFoods_InGame, FoodName) then
                                for i = 1, FoodAmount do
                                    CharacterRE:FireServer("Focus", FoodName) task.wait(0.75)
                                    GiftRE:FireServer(GiftPlayer)              task.wait(0.75)
                                    if sentOne() then break end
                                end
                                if sent >= LIMIT then break end
                            end
                        end

                    elseif GiftType == "Select_Foods" then
                        if not InventoryData then InventoryData = Data:FindFirstChild("Asset") end
                        local inv = InventoryData and InventoryData:GetAttributes() or {}
                        local selected = Configuration.Players.Food_Selected or {}
                        local amounts  = Configuration.Players.Food_Amounts  or {}

                        for foodName, picked in pairs(selected) do
                            if picked and table.find(PetFoods_InGame, foodName) then
                                local have = tonumber(inv[foodName] or 0)
                                local want = tonumber(amounts[foodName] or 1)
                                local canSend = math.max(0, math.min(have, want, LIMIT - sent))
                                for i = 1, canSend do
                                    CharacterRE:FireServer("Focus", foodName) task.wait(0.75)
                                    GiftRE:FireServer(GiftPlayer)              task.wait(0.75)
                                    if sentOne() then break end
                                end
                                if sent >= LIMIT then break end
                            end
                        end

                    elseif GiftType == "All_Eggs" then
                        for _, Egg in pairs(OwnedEggData:GetChildren()) do
                            if Egg and not Egg:FindFirstChild("DI") then
                                CharacterRE:FireServer("Focus", Egg.Name) task.wait(0.75)
                                GiftRE:FireServer(GiftPlayer)             task.wait(0.75)
                                if sentOne() then break end
                            end
                        end

                    elseif GiftType == "Match_Eggs" then
                        local typeOn = next(Configuration.Players.Egg_Types) ~= nil
                        local mutOn  = next(Configuration.Players.Egg_Mutations) ~= nil

                        for _, Egg in pairs(OwnedEggData:GetChildren()) do
                            if Egg and not Egg:FindFirstChild("DI") then
                                local t = Egg:GetAttribute("T") or "BasicEgg"
                                local m = Egg:GetAttribute("M") or "None"
                                local okT = (not typeOn) or Configuration.Players.Egg_Types[t]
                                local okM = mutOn and (Configuration.Players.Egg_Mutations[m] == true) or (m == "None")
                                if okT and okM then
                                    CharacterRE:FireServer("Focus", Egg.Name) task.wait(0.75)
                                    GiftRE:FireServer(GiftPlayer)             task.wait(0.75)
                                    if sentOne() then break end
                                end
                            end
                        end
                    end

                    Configuration.Waiting = false
                end },
                { Title = "No", Callback = function() end }
            }
        })
    end
})
Tabs.Players:AddSection("Settings")
local Players_Dropdown = Tabs.Players:AddDropdown("Players Dropdown",{ Title = "Select Player", Values = Players_InGame, Multi = false, Default = "", Callback = function(v) Configuration.Players.SelectPlayer = v end })
Tabs.Players:AddDropdown("GiftType Dropdown",{ Title = "Gift Type", Values = {"All_Pets","Range_Pets","Match Pet","Match Pet&Mutation","All_Eggs_And_Foods","All_Foods","Select_Foods","Match_Eggs","All_Eggs"}, Multi = false, Default = "", Callback = function(v) Configuration.Players.SelectType = v end })
Tabs.Players:AddInput("Gift Count Limit", { Title = "จำนวนที่จะส่ง (เว้นว่าง=ทั้งหมด)", Default = "", Numeric = true, Finished = true, Callback = function(v) Configuration.Players.Gift_Limit = v end })
Tabs.Players:AddInput("GiftPet_MinIncome", { Title = "Min income/s (for Range_Pets)", Default = tostring(Configuration.Players.GiftPet_Between.Min or 0), Numeric = true, Finished = true, Callback = function(v) Configuration.Players.GiftPet_Between.Min = tonumber(v) or 0 end })
Tabs.Players:AddInput("GiftPet_MaxIncome", { Title = "Max income/s (for Range_Pets)", Default = tostring(Configuration.Players.GiftPet_Between.Max or 1000000), Numeric = true, Finished = true, Callback = function(v) Configuration.Players.GiftPet_Between.Max = tonumber(v) or 1000000 end })

Tabs.Players.AddDropdown = Tabs.Players.AddDropdown or Tabs.Players.AddDropdown -- guard (in case)
Tabs.Players:AddDropdown("Gift Foods", {
    Title = "Foods to Gift (Select)",
    Description = "เลือกชนิดอาหารที่จะส่ง (ใช้เมื่อ Gift Type = Select_Foods)",
    Values = PetFoods_InGame, Multi = true, Default = {},
    Callback = function(v) Configuration.Players.Food_Selected = v end,
})
local PickFoodDD = Tabs.Players:AddDropdown("Pick Food Amount", {
    Title = "Pick Food to set amount",
    Values = PetFoods_InGame, Multi = false, Default = "",
    Callback = function(v) Configuration.Players.Food_AmountPick = v end,
})
Tabs.Players:AddInput("Set Food Amount", {
    Title = "Set Amount for picked food",
    Default = 1, Placeholder = "จำนวนสำหรับชนิดที่เลือก",
    Numeric = true, Finished = true,
    Callback = function(v)
        local food = Configuration.Players.Food_AmountPick
        if food and food ~= "" then
            local n = math.max(1, math.floor(tonumber(v) or 1))
            Configuration.Players.Food_Amounts[food] = n
        end
    end,
})
Tabs.Players:AddButton({
    Title = "Init amounts for selected foods",
    Description = "ตั้งจำนวนเริ่มต้น = 1 ให้ทุกชนิดที่เลือก (ถ้ายังไม่เคยตั้ง)",
    Callback = function()
        for food, on in pairs(Configuration.Players.Food_Selected or {}) do
            if on and not Configuration.Players.Food_Amounts[food] then
                Configuration.Players.Food_Amounts[food] = 1
            end
        end
    end
})
Tabs.Players:AddDropdown("Gift Egg Types", { Title = "Egg Types to Gift (Match_Eggs)", Values = Eggs_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Players.Egg_Types = v end })
Tabs.Players:AddDropdown("Gift Egg Mutations", { Title = "Egg Mutations to Gift (Match_Eggs)", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Players.Egg_Mutations = v end })
Tabs.Players:AddDropdown("Pet Type",{ Title = "Select Pet Type", Values = Pets_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Players.Pet_Type = v end })
Tabs.Players:AddDropdown("Pet Mutations",{ Title = "Select Mutations", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Players.Pet_Mutations = v end })
table.insert(EnvirontmentConnections,Players_List_Updated.Event:Connect(function(newList) Players_Dropdown:SetValues(newList) end))

--============================== Sell =============================
Tabs.Sell:AddSection("Main")
Tabs.Sell:AddDropdown("Sell Mode", { Title = "Sell Mode", Values = { "All_Unplaced_Pets", "All_Unplaced_Eggs", "Filter_Eggs", "Pets_Below_Income" }, Multi = false, Default = "", Callback = function(v) Configuration.Sell.Mode = v end })
Tabs.Sell:AddDropdown("Sell Egg Types", { Title = "Egg Types (for Filter_Eggs)", Values = Eggs_InGame, Multi  = true, Default = {}, Callback = function(v) Configuration.Sell.Egg_Types = v end })
Tabs.Sell:AddDropdown("Sell Egg Mutations", { Title = "Egg Mutations (for Filter_Eggs)", Values = Mutations_InGame, Multi  = true, Default = {}, Callback = function(v) Configuration.Sell.Egg_Mutations = v end })
Tabs.Sell:AddInput("Pet Income Threshold", {
    Title = "รายได้ต่อวิ (ขายสัตว์ที่ \"น้อยกว่า\" ค่านี้)",
    Default = tostring(Configuration.Sell.Pet_Income_Threshold or 0),
    Numeric = true, Finished = true,
    Callback = function(v) Configuration.Sell.Pet_Income_Threshold = tonumber(v) or 0 end
})
Tabs.Sell:AddButton({
    Title = "Sell Now",
    Description = "ขายตามโหมดและตัวกรองที่ตั้งไว้",
    Callback = function()
        local mode = Configuration.Sell.Mode or ""
        if mode == "" then
            Fluent:Notify({ Title = "Sell", Content = "กรุณาเลือก Sell Mode ก่อน", Duration = 5 })
            return
        end

        Window:Dialog({
            Title = "Confirm Sell",
            Content = "แน่ใจหรือไม่ที่จะขายตามเงื่อนไขที่ตั้งไว้?",
            Buttons = {
                { Title = "Yes", Callback = function()
                    local okCnt, failCnt, total = 0, 0, 0

                    if mode == "All_Unplaced_Pets" then
                        for _, petCfg in ipairs(OwnedPetData:GetChildren()) do
                            local uid = petCfg.Name
                            if not OwnedPets[uid] then
                                total += 1
                                local ok = select(1, SellPet(uid))
                                if ok then okCnt += 1 else failCnt += 1 end
                                task.wait(0.15)
                            end
                        end

                    elseif mode == "All_Unplaced_Eggs" then
                        for _, egg in ipairs(OwnedEggData:GetChildren()) do
                            if egg and not egg:FindFirstChild("DI") then
                                total += 1
                                local ok = select(1, SellEgg(egg.Name))
                                if ok then okCnt += 1 else failCnt += 1 end
                                task.wait(0.15)
                            end
                        end

                    elseif mode == "Filter_Eggs" then
                        local typeOn = next(Configuration.Sell.Egg_Types)     ~= nil
                        local mutOn  = next(Configuration.Sell.Egg_Mutations) ~= nil

                        for _, egg in ipairs(OwnedEggData:GetChildren()) do
                            if egg and not egg:FindFirstChild("DI") then
                                local t = egg:GetAttribute("T") or "BasicEgg"
                                local m = egg:GetAttribute("M") or "None"
                                local okT = (not typeOn) or Configuration.Sell.Egg_Types[t]
                                local okM = mutOn and (Configuration.Sell.Egg_Mutations[m] == true) or (m == "None")

                                if okT and okM then
                                    total += 1
                                    local ok = select(1, SellEgg(egg.Name))
                                    if ok then okCnt += 1 else failCnt += 1 end
                                    task.wait(0.15)
                                end
                            end
                        end

                    elseif mode == "Pets_Below_Income" then
                        local th = tonumber(Configuration.Sell.Pet_Income_Threshold) or 0
                        for _, petCfg in ipairs(OwnedPetData:GetChildren()) do
                            local uid = petCfg.Name
                            if not OwnedPets[uid] then
                                local inc = tonumber(GetInventoryIncomePerSecByUID(uid) or 0) or 0
                                if inc < th then
                                    total += 1
                                    local ok = select(1, SellPet(uid))
                                    if ok then okCnt += 1 else failCnt += 1 end
                                    task.wait(0.15)
                                end
                            end
                        end
                    end

                    Fluent:Notify({
                        Title = "Sell Summary",
                        Content = ("รวม %d | สำเร็จ %d | ล้มเหลว %d"):format(total, okCnt, failCnt),
                        Duration = 7
                    })
                end},
                { Title = "No" }
            }
        })
    end
})

--============================== Inventory =================
Tabs.Inv:AddParagraph({
    Title   = "Eggs",
    Content = "Your Egg Collection  •  View all eggs in your inventory",
})
local ResultPara = Tabs.Inv:AddParagraph({
    Title   = "Summary",
    Content = "กดปุ่ม Refresh เพื่อดึงข้อมูลล่าสุด…",
})
local function renderSummary()
    local map = CountEggsByTypeMuta()
    local lines, shown = {}, {}

    local function lineFor(typeName, mutaCounts)
        table.insert(lines, ("\n• %s"):format(typeName))
        for _, key in ipairs(MUTA_ORDER) do
            local n = tonumber(mutaCounts[key] or 0) or 0
            if n > 0 then
                table.insert(lines, ("    - %s %s: %d"):format(MUTA_EMOJI[key], key, n))
            end
        end
        for m, n in pairs(mutaCounts) do
            if not ORDER_SET[m] and (tonumber(n) or 0) > 0 then
                table.insert(lines, ("    - %s %s: %d"):format(MUTA_EMOJI[m], m, n))
            end
        end
    end

    for _, t in ipairs(Eggs_InGame) do
        if map[t] then lineFor(t, map[t]); shown[t]=true end
    end
    for t, counts in pairs(map) do
        if not shown[t] then lineFor(t, counts) end
    end

    if #lines == 0 then
        return "ไม่มีไข่ในกระเป๋า (ที่ยังไม่ถูกวาง) ในตอนนี้"
    else
        return table.concat(lines, "\n")
    end
end
Tabs.Inv:AddButton({
    Title = "Refresh",
    Description = "ดึงรายการไข่ในกระเป๋าแยกตาม Type/Mutation",
    Callback = function()
        ResultPara:SetDesc(renderSummary())
        Fluent:Notify({ Title = "Inventory", Content = "อัพเดตรายการสำเร็จ", Duration = 4 })
    end
})
task.defer(function() ResultPara:SetDesc(renderSummary()) end)

--============================== About / Settings =================
Tabs.About:AddParagraph({ Title = "Credit", Content = "Script create by DemiGodz" })
Tabs.Settings:AddToggle("AntiAFK",{ Title = "Anti AFK", Default = false, Callback = function(v)
    ServerReplicatedDict:SetAttribute("AFK_THRESHOLD",(v == false and 1080 or v == true and 99999999999))
    Configuration.AntiAFK = v
end })
Tabs.Settings:AddToggle("Disable3DOnly", {
    Title = "Disable 3D Rendering (GUI only)",
    Default = false,
    Callback = function(v)
        Configuration.Perf.Disable3D = v
        Perf_Set3DEnabled(not v)
    end
})

--==============================================================
--                INIT / THEME / NOTIFY / PERF
--==============================================================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/"..game.PlaceId)
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
Fluent:Notify({ Title = "Fluent", Content = "The script has been loaded.", Duration = 8 })
Perf_Set3DEnabled(not (Configuration.Perf.Disable3D == true))

--==============================================================
--                    TASK LOOPS
--==============================================================

-- ===== Anti AFK
task.defer(function()
    local VirtualUser = game:GetService("VirtualUser")
    table.insert(EnvirontmentConnections,ServerReplicatedDict:GetAttributeChangedSignal("AFK_THRESHOLD"):Connect(function()
        ServerReplicatedDict:SetAttribute("AFK_THRESHOLD",(Configuration.AntiAFK == false and 1080 or Configuration.AntiAFK == true and 99999999999))
    end))
    while true and RunningEnvirontments do
        if Configuration.AntiAFK then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end
        task.wait(30)
    end
end)

-- ===== Auto Collect coin from pets
task.defer(function()
    local PetRE = GameRemoteEvents:WaitForChild("PetRE")
    while true and RunningEnvirontments do
        if Configuration.Main.AutoCollect then
            for _,pet in pairs(OwnedPets) do
                local RE = pet.RE
                local Coin = tonumber(pet.Coin)
                if Configuration.Main.Collect_Type == "Delay" then
                    if RE then RE:FireServer("Claim") end
                elseif Configuration.Main.Collect_Type == "Between" and (Configuration.Main.Collect_Between.Min < Coin and Coin < Configuration.Main.Collect_Between.Max) then
                    if RE then RE:FireServer("Claim") end
                end
            end
        end
        task.wait(Configuration.Main.Collect_Delay)
    end
end)

-- ===== Auto Feed Pet (เฉพาะ Big)
task.defer(function()
    local Data_OwnedPets = Data:WaitForChild("Pets",30)
    local PetRE = GameRemoteEvents:WaitForChild("PetRE")
    local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE")

    while true and RunningEnvirontments do
        if Configuration.Pet.AutoFeed and not Configuration.Waiting and Configuration.Pet.AutoFeed_Type ~= "" then
            if not InventoryData then InventoryData = Data:FindFirstChild("Asset") end
            local Data_Inventory = InventoryData:GetAttributes()

            for _, petCfg in ipairs(Data_OwnedPets:GetChildren()) do
                local petModel = OwnedPets[petCfg.Name]
                if not (petModel and petModel.IsBig) then continue end
                if petCfg and not petCfg:GetAttribute("Feed") then
                    local Food = nil

                    if Configuration.Pet.AutoFeed_Type == "BestFood" then
                        for _, name in ipairs(PetFoods_InGame) do
                            local have = tonumber(Data_Inventory[name] or 0) or 0
                            if have > 0 then Food = name break end
                        end
                    elseif Configuration.Pet.AutoFeed_Type == "SelectFood" then
                        Food = pickFoodSelect(Data_Inventory)
                    end

                    if Food and Food ~= "" then
                        CharacterRE:FireServer("Focus", Food) task.wait(0.5)
                        PetRE:FireServer("Feed", petModel.UID) task.wait(0.5)
                        CharacterRE:FireServer("Focus")
                        Data_Inventory[Food] = math.max(0, (tonumber(Data_Inventory[Food] or 0) or 0) - 1)
                    end
                end
            end
        end
        task.wait(Configuration.Pet.AutoFeed_Delay)
    end
end)

-- ===== Auto Collect Pet (with Area + ALL support)
task.defer(function()
    local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE",30)

    local function passArea(uid)
        local want = Configuration.Pet.CollectPet_Area or "Any"
        if want == "Any" then return true end
        return petArea(uid) == want
    end

    while true and RunningEnvirontments do
        if Configuration.Pet.CollectPet_Auto and not Configuration.Waiting then
            local CollectType = Configuration.Pet.CollectPet_Type or "All"

            if CollectType == "All" then
                for UID, PetData in pairs(OwnedPets) do
                    if PetData and not PetData.IsBig and passArea(UID) then
                        if PetData.RE then PetData.RE:FireServer("Claim") end
                        CharacterRE:FireServer("Del", UID)
                    end
                end

            elseif CollectType == "Match Pet" then
                for UID,PetData in pairs(OwnedPets) do
                    if PetData and not PetData.IsBig and passArea(UID)
                    and Configuration.Pet.CollectPet_Pets[PetData.Type] then
                        if PetData.RE then PetData.RE:FireServer("Claim") end
                        CharacterRE:FireServer("Del",UID)
                    end
                end

            elseif CollectType == "Match Mutation" then
                for UID,PetData in pairs(OwnedPets) do
                    if PetData and not PetData.IsBig and passArea(UID)
                    and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                        if PetData.RE then PetData.RE:FireServer("Claim") end
                        CharacterRE:FireServer("Del",UID)
                    end
                end

            elseif CollectType == "Match Pet&Mutation" then
                for UID,PetData in pairs(OwnedPets) do
                    if PetData and not PetData.IsBig and passArea(UID)
                    and Configuration.Pet.CollectPet_Pets[PetData.Type]
                    and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                        if PetData.RE then PetData.RE:FireServer("Claim") end
                        CharacterRE:FireServer("Del",UID)
                    end
                end

            elseif CollectType == "Range" then
                local minV = tonumber(Configuration.Pet.CollectPet_Between.Min) or 0
                local maxV = tonumber(Configuration.Pet.CollectPet_Between.Max) or math.huge
                for UID,PetData in pairs(OwnedPets) do
                    if PetData and not PetData.IsBig and passArea(UID) then
                        local ps = tonumber(PetData.ProduceSpeed) or 0
                        if ps >= minV and ps <= maxV then
                            if PetData.RE then PetData.RE:FireServer("Claim") end
                            CharacterRE:FireServer("Del",UID)
                        end
                    end
                end
            end
        end
        task.wait(Configuration.Pet.CollectPet_Delay)
    end
end)

-- ===== Auto Hatch (with area filter)
task.defer(function()
    local OwnedEggs = Data:WaitForChild("Egg")
    while true and RunningEnvirontments do
        if Configuration.Egg.AutoHatch then
            local wantArea = Configuration.Egg.HatchArea
            for _,egg in pairs(OwnedEggs:GetChildren()) do
                local di = egg:FindFirstChild("DI")
                local hatchable = di and egg:GetAttribute("D") and (ServerTime.Value >= egg:GetAttribute("D"))
                if hatchable then
                    local a = eggArea(egg)
                    if (wantArea == "Any") or (a == wantArea) then
                        local EggModel = BlockFolder:FindFirstChild(egg.Name)
                        local RootPart = EggModel and (EggModel.PrimaryPart or EggModel:FindFirstChild("RootPart"))
                        local RF = RootPart and RootPart:FindFirstChild("RF")
                        if RF then task.spawn(function() RF:InvokeServer("Hatch") end) end
                    end
                end
            end
        end
        task.wait(Configuration.Egg.Hatch_Delay)
    end
end)

-- ===== Auto Claim Event Quests
task.defer(function()
    local Tasks; local EventRE = ResEvent and GameRemoteEvents:WaitForChild(tostring(ResEvent).."RE")
    if EventTaskData then Tasks = EventTaskData:WaitForChild("Tasks") end
    while true and RunningEnvirontments do
        if Tasks and EventRE and Configuration.Event.AutoClaim then
            for _,Quest in pairs(Tasks:GetChildren()) do
                EventRE:FireServer({event = "claimreward",id = Quest:GetAttribute("Id")})
            end
        end
        task.wait(Configuration.Event.AutoClaim_Delay)
    end
end)

-- ===== Auto Buy Egg
task.defer(function()
    local RE = GameRemoteEvents:WaitForChild("CharacterRE",30)
    local function currentCoin()
        local asset = InventoryData or Data:FindChild("Asset")
        if not asset then return 0 end
        return tonumber(asset:GetAttribute("Coin") or 0) or 0
    end

    while true and RunningEnvirontments do
        if Configuration.Egg.AutoBuyEgg and not Configuration.Waiting then
            local coinOk = (not Configuration.Egg.CheckMinCoin)
                or (currentCoin() >= (tonumber(Configuration.Egg.MinCoin) or 0))

            if coinOk then
                for _,egg in pairs(Egg_Belt) do
                    local EggType = egg.Type
                    local EggMutation = egg.Mutate
                    if (Configuration.Egg.Types[EggType]) and (Configuration.Egg.Mutations[EggMutation]) then
                        if RE then RE:FireServer("BuyEgg", egg.UID) end
                    end
                end
            end
        end
        task.wait(Configuration.Egg.AutoBuyEgg_Delay)
    end
end)

-- ===== Auto Place Egg
task.defer(function()
    local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE", 30)
    while true and RunningEnvirontments do
        if Configuration.Egg.AutoPlaceEgg and not Configuration.Waiting and not _placingBusy then
            local chosenEgg
            local typeOn = next(Configuration.Egg.Types) ~= nil
            local mutOn  = next(Configuration.Egg.Mutations) ~= nil
            for _, egg in ipairs(OwnedEggData:GetChildren()) do
                if egg and not egg:FindFirstChild("DI") then
                    local t = egg:GetAttribute("T") or "BasicEgg"
                    local m = egg:GetAttribute("M") or "None"
                    local okT = (not typeOn) or Configuration.Egg.Types[t]
                    local okM = mutOn and Configuration.Egg.Mutations[m] or (m == "None")
                    if okT and okM then chosenEgg = egg break end
                end
            end

            if chosenEgg then
                local grid, gkey, gidx, garea = GetNextFreeGrid(Configuration.Egg.PlaceArea)
                if grid then
                    _placingBusy = true
                    local dst = GroundAtGrid(grid)
                    ensureNear(dst, 12)

                    CharacterRE:FireServer("Focus", chosenEgg.Name)
                    task.wait(0.45)
                    CharacterRE:FireServer("Place", { DST = vector.create(dst.X, dst.Y, dst.Z), ID = chosenEgg.Name })
                    task.wait(0.2)
                    CharacterRE:FireServer("Focus")

                    if not waitEggPlaced(chosenEgg, 3) then
                        _reserveDel(gkey)
                        if gidx and garea then NextIdx[garea] = gidx end
                        warn("[AutoPlaceEgg] not confirmed; release reservation.")
                    end
                    _placingBusy = false
                end
            end
        end
        task.wait(Configuration.Egg.AutoPlaceEgg_Delay or 1.0)
    end
end)

-- ===== Auto Place Pet
task.defer(function()
    local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE", 30)

    local function incomeOf(uid) return tonumber(GetInventoryIncomePerSecByUID(uid) or 0) or 0 end
    local function pickPet()
        local mode   = Configuration.Pet.PlacePet_Mode
        local typeOn = (mode == "Match") and (next(Configuration.Pet.PlacePet_Types)     ~= nil)
        local mutOn  = (mode == "Match") and (next(Configuration.Pet.PlacePet_Mutations) ~= nil)
        local minV, maxV = 0, math.huge
        if mode == "Range" then
            minV = tonumber(Configuration.Pet.PlacePet_Between.Min) or 0
            maxV = tonumber(Configuration.Pet.PlacePet_Between.Max) or math.huge
        end
        local candidates = {}
        for _, petCfg in ipairs(OwnedPetData:GetChildren()) do
            local uid = petCfg.Name
            if not OwnedPets[uid] then
                local pass = (mode == "All")
                if mode == "Match" then
                    local t = petCfg:GetAttribute("T")
                    local m = petCfg:GetAttribute("M") or "None"
                    local okT = (not typeOn) or Configuration.Pet.PlacePet_Types[t]
                    local okM = mutOn and Configuration.Pet.PlacePet_Mutations[m] or (m == "None")
                    pass = (okT and okM)
                elseif mode == "Range" then
                    local inc = incomeOf(uid)
                    pass = (inc >= minV and inc <= maxV)
                end
                if pass then table.insert(candidates, { cfg = petCfg, inc = incomeOf(uid) }) end
            end
        end
        if #candidates == 0 then return nil end
        table.sort(candidates, function(a,b) return (a.inc or 0) > (b.inc or 0) end)
        return candidates[1].cfg
    end

    while true and RunningEnvirontments do
        if Configuration.Pet.AutoPlacePet and not Configuration.Waiting and not _placingBusy then
            local petCfg = pickPet()
            if petCfg then
                local grid, gkey, gidx, garea = GetNextFreeGrid(Configuration.Pet.PlaceArea)
                if grid then
                    _placingBusy = true
                    local dst = GroundAtGrid(grid)
                    ensureNear(dst, 12)

                    CharacterRE:FireServer("Focus", petCfg.Name)
                    task.wait(0.45)
                    CharacterRE:FireServer("Place", { DST = vector.create(dst.X, dst.Y, dst.Z), ID = petCfg.Name })
                    task.wait(0.2)
                    CharacterRE:FireServer("Focus")

                    if not waitPetPlaced(petCfg.Name, 3) then
                        _reserveDel(gkey)
                        if gidx and garea then NextIdx[garea] = gidx end
                        warn("[AutoPlacePet] not confirmed; release reservation.")
                    end
                    _placingBusy = false
                end
            end
        end
        task.wait(Configuration.Pet.AutoPlacePet_Delay or 1.0)
    end
end)

-- ===== Auto Buy Food
task.defer(function()
    local FoodList = Data:WaitForChild("FoodStore",30):WaitForChild("LST",30)
    local RE = GameRemoteEvents:WaitForChild("FoodStoreRE")
    while true and RunningEnvirontments do
        if Configuration.Shop.Food.AutoBuy and not Configuration.Waiting then
            for foodName,stockAmount in pairs(FoodList:GetAttributes()) do
                if stockAmount > 0 and Configuration.Shop.Food.Foods[foodName] then
                    if RE then RE:FireServer(foodName) end
                end
            end
        end
        task.wait(Configuration.Shop.Food.AutoBuy_Delay)
    end
end)

-- ===== Lottery Auto
task.defer(function()
    local LotteryRE = GameRemoteEvents:WaitForChild("LotteryRE",30)
    while true and RunningEnvirontments do
        if Configuration.Event.AutoLottery then
            local args = { event = "lottery", count = 1 }
            LotteryRE:FireServer(args)
        end
        task.wait(Configuration.Event.AutoLottery_Delay or 60)
    end
end)

--==============================================================
--                        CLEANUP
--==============================================================
Window.Root.Destroying:Once(function()
    RunningEnvirontments = false
    for _,connection in pairs(EnvirontmentConnections) do
        if connection then pcall(function() connection:Disconnect() end) end
    end
    Perf_Set3DEnabled(true)
end)

SaveManager:LoadAutoloadConfig()
getgenv().MeowyBuildAZoo = Window

-- Build A Zoo (PlaceId 105555311806207)
--V2.1 Smartpet
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
local OwnedPets = {}
local Egg_Belt = {}
local Configuration
local Options
-- ==== DEBUG flags ====
local G = getgenv()
G.MEOWY_DBG = G.MEOWY_DBG or { on = true, toast = false }

local function _tos(v)
    local ok, t = pcall(function() return typeof(v) end)
    t = ok and t or type(v)
    if t == "Vector3" then return string.format("(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z) end
    if t == "Instance" then return string.format("<%s:%s>", v.ClassName, v.Name) end
    return tostring(v)
end
local function dprint(...)
    if not (G.MEOWY_DBG and G.MEOWY_DBG.on) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = _tos(select(i, ...)) end
    local msg = table.concat(parts, " ")
    print("[DEBUG] " .. msg)
    if G.MEOWY_DBG.toast then
        pcall(function() Fluent:Notify({ Title = "Debug", Content = string.sub(msg, 1, 190), Duration = 4 }) end)
    end
end

--==============================================================
--                      OPTIMIZATION BLOCKS
--   (kept for area detection used by other features)
--==============================================================

-- ========= Plot index cache + Occupied-ish map (only area map kept) =========
local PlotIndex = {}              -- "x,z" -> {part=..., area=..}
local SortedPlots = { Any={}, Land={}, Water={} }
do
    for _,p in ipairs(Island:GetDescendants()) do
        if p:IsA("BasePart") and (p.Name:match("^Farm_split_") or p.Name:match("^WaterFarm_split_")) then
            local ic = p:GetAttribute("IslandCoord")
            if ic then
                local k = ("%d,%d"):format(ic.X, ic.Z)
                local area = p.Name:match("^Water") and "Water" or "Land"
                PlotIndex[k] = { part=p, area=area }
                table.insert(SortedPlots[area], p)
                table.insert(SortedPlots.Any, p)
            end
        end
    end
    for _,arr in pairs(SortedPlots) do
        table.sort(arr, function(a,b)
            if a.Position.Z ~= b.Position.Z then return a.Position.Z < b.Position.Z end
            return a.Position.X < b.Position.X
        end)
    end
    dprint("Plot counts -> Any=", #SortedPlots.Any, "Land=", #SortedPlots.Land, "Water=", #SortedPlots.Water)
end

local function _keyXZ(x,z)
    return ("%d,%d"):format(math.floor((x or 0)+0.5), math.floor((z or 0)+0.5))
end
local function _areaFromXZ(x, z)
    local n = PlotIndex[_keyXZ(x,z)]
    return n and n.area or "Any"
end

--==============================================================
--                      HELPERS
--==============================================================
-- ==== Income Cache (drop-in) ====
local IncomeCache = { map = {}, built = false, last = 0 }
local function _buildIncomeIndex()
    local pg = Player:FindFirstChild("PlayerGui"); if not pg then return end
    local s = pg:FindFirstChild("ScreenStorage"); if not s then return end
    local f = s:FindFirstChild("Frame"); if not f then return end
    local cp = f:FindFirstChild("ContentPet"); if not cp then return end
    local sc = cp:FindFirstChild("ScrollingFrame"); if not sc then return end
    IncomeCache.map = {}
    for _, item in ipairs(sc:GetChildren()) do
        local uid = item.Name
        local btn  = item:FindFirstChild("BTN") or item:FindFirstChildWhichIsA("Frame")
        local stat = btn and (btn:FindFirstChild("Stat") or btn:FindFirstChildWhichIsA("Frame"))
        local price= stat and (stat:FindFirstChild("Price") or stat:FindFirstChildWhichIsA("Frame"))
        local valueObj = price and price:FindFirstChild("Value")
        local val
        if valueObj then
            if valueObj:IsA("NumberValue") or valueObj:IsA("IntValue") then
                val = tonumber(valueObj.Value)
            elseif valueObj:IsA("StringValue") then
                local s = tostring(valueObj.Value or "")
                val = tonumber((s:gsub("[^%d%.]","")))
            end
        end
        if not val and price then
            local function readText(inst)
                local ok, txt = pcall(function() return inst.Text end)
                if ok and txt then
                    local n = tonumber((tostring(txt):gsub("[^%d%.]",""))); if n then return n end
                end
            end
            val = readText(price) or (price:FindFirstChildWhichIsA("TextLabel") and readText(price:FindFirstChildWhichIsA("TextLabel")))
            if not val then
                for _, d in ipairs(price:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextButton") then val = readText(d); if val then break end end
                end
            end
        end
        IncomeCache.map[uid] = tonumber(val or 0) or 0
    end
    IncomeCache.last = os.clock()
    IncomeCache.built = true
end

local function GetIncomeFast(uid)
    if not IncomeCache.built or (os.clock() - IncomeCache.last > 5) then
        pcall(_buildIncomeIndex)
    end
    local v = IncomeCache.map[uid]
    if v == nil then
        v = GetInventoryIncomePerSecByUID(uid)
        IncomeCache.map[uid] = v or 0
    end
    return v or 0
end

--==============================================================
--  MY PETS (workspace.Pets ของเราเท่านั้น)
--==============================================================
local MyPets = {}
local MyPets_List = {}

local function _isOwnedPetModel(model)
    if not (model and model:IsA("Model")) then return false end
    local uid = model:GetAttribute("UserId")
    if uid == PlayerUserID then return true end
    local root = model.PrimaryPart or model:FindFirstChild("RootPart")
    if root and root:GetAttribute("UserId") == PlayerUserID then return true end
    return false
end

local function _rebuildMyPetsList()
    table.clear(MyPets_List)
    for m in pairs(MyPets) do
        if m.Parent == workspace.Pets then
            table.insert(MyPets_List, m)
        else
            MyPets[m] = nil
        end
    end
end

local function _addMyPet(m)
    if _isOwnedPetModel(m) then
        MyPets[m] = true
        _rebuildMyPetsList()
    end
end

local function _removeMyPet(m)
    if MyPets[m] then
        MyPets[m] = nil
        _rebuildMyPetsList()
    end
end

for _,m in ipairs(workspace.Pets:GetChildren()) do _addMyPet(m) end
workspace.Pets.ChildAdded:Connect(function(m) task.defer(_addMyPet, m) end)
workspace.Pets.ChildRemoved:Connect(function(m) task.defer(_removeMyPet, m) end)


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

local function Perf_Set3DEnabled(enable3D)
    local ok = pcall(function() RunService:Set3dRenderingEnabled(enable3D) end)
    if ok then _toggleWhiteOverlay(false) else _toggleWhiteOverlay(not enable3D) end
end

local function GetCash(TXT)
    if not TXT then return 0 end
    local cash = string.gsub(TXT,"[$,]","")
    return tonumber(cash) or 0
end

local function SellEgg(uid)
    if not uid or uid == "" then return false, "no uid" end
    CharacterRE:FireServer("Focus", uid) task.wait(0.1)
    local ok, err = pcall(function() PetRE:FireServer("Sell", uid, true) end)
    CharacterRE:FireServer("Focus")
    return ok, err
end
local function SellPet(uid)
    if not uid or uid == "" then return false, "no uid" end
    CharacterRE:FireServer("Focus", uid) task.wait(0.1)
    local ok, err = pcall(function() PetRE:FireServer("Sell", uid) end)
    CharacterRE:FireServer("Focus")
    return ok, err
end

--=========== Grid / Area helpers ===========
local function eggArea(eggInst)
    if not eggInst then return "Any" end
    local di = eggInst:FindFirstChild("DI")
    if not di then return "Any" end
    return _areaFromXZ(di:GetAttribute("X") or 0, di:GetAttribute("Z") or 0)
end

local function petArea(uid)
    if not uid or uid == "" then return "Any" end
    local petNode = OwnedPetData:FindFirstChild(uid)
    if petNode then
        local di = petNode:FindFirstChild("DI")
        if di then return _areaFromXZ(di:GetAttribute("X") or 0, di:GetAttribute("Z") or 0) end
    end
    local P = OwnedPets[uid]; local gc = P and P.GridCoord
    if gc then return _areaFromXZ(gc.X or 0, gc.Z or 0) end
    return "Any"
end

local function _cloneFoodMap(t)
    local m = {}
    if type(t) == "table" then
        if rawget(t, 1) ~= nil then
            for _, v in ipairs(t) do m[tostring(v)] = true end
        else
            for k, v in pairs(t) do if v then m[tostring(k)] = true end end
        end
    end
    return m
end

local function pickFoodPerPet(uid, invAttrs)
    local per = Configuration.Pet.AutoFeed_PetFoods and Configuration.Pet.AutoFeed_PetFoods[uid]
    if type(per) ~= "table" then return nil end
    local allow = {}
    if rawget(per, 1) ~= nil then
        for _, v in ipairs(per) do allow[tostring(v)] = true end
    else
        for k, on in pairs(per) do if on then allow[tostring(k)] = true end end
    end
    for _, name in ipairs(PetFoods_InGame) do
        local have = tonumber(invAttrs[name] or 0) or 0
        if allow[name] and have > 0 then return name end
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
    task.spawn(function()
        pcall(function()
            local eggUID = tostring(egg) or "None"
            if egg then
                Egg_Belt[eggUID] = {
                    UID = eggUID,
                    Mutate = (egg:GetAttribute("M") or "None"),
                    Type = (egg:GetAttribute("T") or "BasicEgg")
                }
            end
        end)
    end)
end

table.insert(EnvirontmentConnections,Pet_Folder.ChildRemoved:Connect(function(pet)
    task.wait(0.1)
    local petUID = tostring(pet) or "None"
    if pet and OwnedPets[petUID] then OwnedPets[petUID] = nil end
end))

-- ===== SAFE pet reader =====
local function _buildOwnedPetEntry(pet, petUID)
    local IsOwned = pet:GetAttribute("UserId") == PlayerUserID
    if not IsOwned then return end
    local root = pet and (pet.PrimaryPart or pet:FindFirstChild("RootPart"))
    local _cashTxtRef = nil
    local function _getCashTxt()
        if _cashTxtRef and _cashTxtRef.Parent then return _cashTxtRef end
        if not root then return nil end
        local gui = root:FindFirstChild("GUI") or root:FindFirstChildWhichIsA("BillboardGui", true)
        local idle = gui and (gui:FindFirstChild("IdleGUI") or gui:FindFirstChildWhichIsA("Frame", true))
        local cf   = idle and (cf or idle:FindFirstChild("CashF") or idle:FindFirstChildWhichIsA("Frame", true))
        local txt  = cf and (cf:FindFirstChild("TXT")   or cf:FindFirstChildWhichIsA("TextLabel", true))
        _cashTxtRef = txt
        return txt
    end
    local diNode = OwnedPetData:FindFirstChild(petUID)
    diNode = diNode and diNode:FindFirstChild("DI")
    local GridCoord = diNode and Vector3.new(diNode:GetAttribute("X"), diNode:GetAttribute("Y"), diNode:GetAttribute("Z")) or nil

    OwnedPets[petUID] = setmetatable({
        GridCoord = GridCoord, UID = petUID,
        Type = root and root:GetAttribute("Type"),
        Mutate = root and root:GetAttribute("Mutate"),
        Model = pet, RootPart = root,
        RE = root and root:FindFirstChild("RE",true),
        IsBig = root and (root:GetAttribute("BigValue") ~= nil),
        _getCashTxt = _getCashTxt
    },{
        __index = function(tb, ind)
            if ind == "Coin" then
                local t = tb._getCashTxt()
                if t and t.Text then
                    local n = tonumber((t.Text:gsub("[^%d%.]","")))
                    return n or 0
                end
                return 0
            elseif ind == "ProduceSpeed" or ind == "PS" then
                local rp = rawget(tb, "RootPart")
                local model = rawget(tb, "Model")
                local base = (rp and rp:GetAttribute("ProduceSpeed")) or (model and model:GetAttribute("ProduceSpeed")) or 0
                return base
            end
            return rawget(tb, ind)
        end
    })
end

table.insert(EnvirontmentConnections, Pet_Folder.ChildAdded:Connect(function(pet)
    task.delay(0.1, function()
        local uid = tostring(pet)
        if pet and uid then _buildOwnedPetEntry(pet, uid) end
    end)
end))

for _,pet in pairs(Pet_Folder:GetChildren()) do
    task.spawn(function()
        local uid = tostring(pet)
        if pet and uid then _buildOwnedPetEntry(pet, uid) end
    end)
end

--==============================================================
--                      CONFIG / UI
--==============================================================
Configuration = {
    Main = { AutoCollect=false, Collect_Delay=3, Collect_Type="Delay", Collect_Between={Min=100000,Max=1000000}, },
    Pet  = {
        AutoFeed=false, AutoFeed_Foods={}, AutoPlacePet=false, AutoFeed_Delay=10, AutoFeed_Type="",AutoFeed_Pets = {}, AutoFeed_PetFoods = {}, 
        AutoFeed_UsePerPet = true,
        CollectPet_Type="All", CollectPet_Auto=false, CollectPet_Mutations={}, CollectPet_Pets={},
        CollectPet_Delay=5, CollectPet_Between={Min=100000,Max=1000000}, CollectPet_Area="Any",
        PlacePet_Mode="All", PlacePet_Types={}, PlacePet_Mutations={}, AutoPlacePet_Delay=1.0,
        PlacePet_Between={Min=0,Max=1000000}, PlaceArea="Any",SmartPet = false,
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
    Perf = {
        Disable3D=false,
        FPSLock=false, FPSValue=60,
        HidePets=false, HideEggs=false, HideEffects=false, HideGameUI=false
    },
    Lottery = { Auto=false, Delay=1800, Count=1 },
    Event = { AutoClaim=false, AutoClaim_Delay=3, AutoLottery=false, AutoLottery_Delay=60 },
    AntiAFK=false, Waiting=false,
}
Configuration.Pet.AutoFeed_Pets      = Configuration.Pet.AutoFeed_Pets      or {}
Configuration.Pet.AutoFeed_PetFoods  = Configuration.Pet.AutoFeed_PetFoods  or {}
Configuration.Pet.AutoFeed_UsePerPet = (Configuration.Pet.AutoFeed_UsePerPet ~= false)

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

--==============================================================
--           FPS LOCK & HIDE (helpers + state)
--==============================================================
local function _pick_fps_setter()
    local cands = {
        rawget(getgenv() or {}, "setfpscap"),
        rawget(getgenv() or {}, "set_fps_cap"),
        rawget(_G or {},       "setfpscap"),
        rawget(_G or {},       "set_fps_cap"),
        (syn and syn.set_fps_cap),
        (syn and syn.setfpscap),
        (setfpscap),
        (set_fps_cap),
    }
    for _,fn in ipairs(cands) do
        if type(fn) == "function" then return fn end
    end
    return nil
end
local _setFPSCap = _pick_fps_setter()

local G2 = getgenv()
G2.MEOWY_FPS = G2.MEOWY_FPS or { locked = false, cap = 60 }
local function _notify(t, m)
    pcall(function() Fluent:Notify({ Title = t, Content = m, Duration = 5 }) end)
    print("[Perf] "..t..": "..m)
end
local function ApplyFPSLock()
    if not _setFPSCap then
        _notify("FPS", "Executor ไม่รองรับ setfpscap"); return
    end
    if Configuration.Perf.FPSLock then
        local cap = math.max(5, math.floor(tonumber(Configuration.Perf.FPSValue) or 60))
        G2.MEOWY_FPS.locked = true; G2.MEOWY_FPS.cap = cap
        _setFPSCap(cap); _notify("FPS Locked", tostring(cap))
    else
        G2.MEOWY_FPS.locked = false
        _setFPSCap(1000); _notify("FPS", "Unlock")
    end
end

--== Hide caches
local _partPrev, _particlePrev, _togglePrev, _uiPrev =
    setmetatable({}, { __mode="k" }),
    setmetatable({}, { __mode="k" }),
    setmetatable({}, { __mode="k" }),
    setmetatable({}, { __mode="k" })
local _effectsConn, _petsConn, _eggsConn, _uiConn

local function _setPartVisible(part, visible)
    if visible then
        local prev = _partPrev[part]
        if prev ~= nil then part.LocalTransparencyModifier = prev; _partPrev[part] = nil
        else part.LocalTransparencyModifier = 0 end
    else
        if _partPrev[part] == nil then _partPrev[part] = part.LocalTransparencyModifier end
        part.LocalTransparencyModifier = 1
    end
end
local function _applyModelVisible(model, visible)
    for _,d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            _setPartVisible(d, visible)
            d.CastShadow = visible and d.CastShadow or false
        elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
            if _togglePrev[d] == nil then _togglePrev[d] = d.Enabled end
            d.Enabled = visible and (_togglePrev[d] ~= false)
        end
    end
end
local function ApplyHidePets(on)
    for _,m in ipairs(Pet_Folder:GetChildren()) do _applyModelVisible(m, not on) end
    if _petsConn then _petsConn:Disconnect(); _petsConn = nil end
    if on then
        _petsConn = Pet_Folder.ChildAdded:Connect(function(m) task.wait() _applyModelVisible(m, false) end)
        table.insert(EnvirontmentConnections, _petsConn)
    end
end
local function _isEggModel(m) return OwnedEggData:FindFirstChild(m.Name) ~= nil end
local function ApplyHideEggs(on)
    for _,m in ipairs(BlockFolder:GetChildren()) do if _isEggModel(m) then _applyModelVisible(m, not on) end end
    if _eggsConn then _eggsConn:Disconnect(); _eggsConn = nil end
    if on then
        _eggsConn = BlockFolder.ChildAdded:Connect(function(m) task.wait(); if _isEggModel(m) then _applyModelVisible(m, false) end end)
        table.insert(EnvirontmentConnections, _eggsConn)
    end
end

local function _applyEffectInst(inst, enable)
    if inst:IsA("ParticleEmitter") then
        if enable then
            local prev = _particlePrev[inst]
            if prev ~= nil then inst.Rate = prev; _particlePrev[inst] = nil
            else inst.Rate = inst.Rate end
        else
            if _particlePrev[inst] == nil then _particlePrev[inst] = inst.Rate end
            inst.Rate = 0
        end
    elseif inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("Highlight") then
        if enable then
            if _togglePrev[inst] ~= nil then inst.Enabled = _togglePrev[inst]; _togglePrev[inst] = nil end
        else
            if _togglePrev[inst] == nil then _togglePrev[inst] = inst.Enabled end
            inst.Enabled = false
        end
    elseif inst:IsA("Explosion") then
        pcall(function() inst.Visible = enable end)
    end
end

local function _applyEffectInst_batch(list, enable)
    local batch, n = 300, #list
    local i = 1
    while i <= n do
        local j = math.min(i + batch - 1, n)
        for k = i, j do _applyEffectInst(list[k], enable) end
        i = j + 1
        task.wait()
    end
end

local function ApplyHideEffects(on)
    if _effectsConn then _effectsConn:Disconnect(); _effectsConn = nil end
    local all = {}
    for _,d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Highlight") or d:IsA("Explosion") then
            table.insert(all, d)
        end
    end
    _applyEffectInst_batch(all, not on)

    if on then
        _effectsConn = workspace.DescendantAdded:Connect(function(d) _applyEffectInst(d, false) end)
        table.insert(EnvirontmentConnections, _effectsConn)
    end
end

local function ApplyHideGameUI(on)
    local pg = Player:FindFirstChild("PlayerGui"); if not pg then return end
    local fluentGui = (Fluent and Fluent.GuiObject) or (Fluent and Fluent.ScreenGui) or (Fluent and Fluent.Root) or nil
    local windowRoot = nil; pcall(function() windowRoot = _G.Fluent and _G.Fluent.ScreenGui end)
    local myGui = windowRoot or (fluentGui and fluentGui:FindFirstAncestorOfClass("ScreenGui")) or pg:FindFirstChildOfClass("ScreenGui")
    local whitelistNames = { PerfWhite = true }
    local whitelistInst  = {}; if myGui then whitelistInst[myGui] = true end
    for _,ch in ipairs(pg:GetChildren()) do
        if ch:IsA("ScreenGui") and not (whitelistInst[ch] or whitelistNames[ch.Name]) then
            if on then if _uiPrev[ch] == nil then _uiPrev[ch] = ch.Enabled end; ch.Enabled = false
            else if _uiPrev[ch] ~= nil then ch.Enabled = _uiPrev[ch]; _uiPrev[ch] = nil end end
        end
    end
    if _uiConn then _uiConn:Disconnect(); _uiConn = nil end
    if on then
        _uiConn = pg.ChildAdded:Connect(function(ch)
            task.wait()
            if ch:IsA("ScreenGui") and not (whitelistInst[ch] or whitelistNames[ch.Name]) and Configuration.Perf.HideGameUI then
                if _uiPrev[ch] == nil then _uiPrev[ch] = ch.Enabled end
                ch.Enabled = false
            end
        end)
        table.insert(EnvirontmentConnections, _uiConn)
    end
end

--==============================================================
--                    TASKS (THREAD-BASED)
--==============================================================
local TaskMgr = {}
do
    local registry = {}
        function TaskMgr.start(name, runnerFn)
            TaskMgr.stop(name)
            local token = { alive = true, name = name }
            local co = task.spawn(function()
                local ok, err = pcall(function() runnerFn(token) end)
                if not ok then warn(("[Task:%s] crashed: %s"):format(name, tostring(err))) end
            end)
            registry[name] = { token = token, co = co }
            dprint("Task start:", name)
        end
        function TaskMgr.stop(name)
            local h = registry[name]
            if h then if h.token then h.token.alive = false end; registry[name] = nil; dprint("Task stop:", name) end
        end
    function TaskMgr.isRunning(name) return registry[name] ~= nil end
    function TaskMgr.stopAll()
        for _,h in pairs(registry) do if h.token then h.token.alive = false end end
        registry = {}; dprint("Task stopAll()")
    end
    TaskMgr._ = registry
end
local function _waitAlive(tok, sec)
    local t = tonumber(sec) or 0
    if t <= 0 then task.wait() return tok.alive end
    local deadline = os.clock() + t
    while tok.alive and os.clock() < deadline do task.wait() end
    return tok.alive
end

--==============================================================
--            AUTO PLACE PET (GridCenterPos-based)
--==============================================================
local function __tileCenterPos(tilePart)
    local p = tilePart
    local cx = math.floor(p.Position.X + 0.5)
    local cz = math.floor(p.Position.Z + 0.5)
    local cy = p.Position.Y + (p.Size.Y * 0.5)
    return Vector3.new(cx, cy, cz)
end
local function __round(n) return math.floor((tonumber(n) or 0) + 0.5) end
local function __keyXZ(x,z) return string.format("%d,%d", __round(x), __round(z)) end
local function __getAttrs(inst) local ok, a = pcall(function() return inst:GetAttributes() end); return ok and a or {} end
local function __parseGCP(v)
    if typeof(v) == "Vector3" then return v end
    if type(v) == "table" then
        local x = v.X or v.x or v[1] or 0
        local y = v.Y or v.y or v[2] or 0
        local z = v.Z or v.z or v[3] or 0
        return Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    end
    if type(v) == "string" then
        local x,y,z = v:match("%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*")
        return Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    end
    return nil
end

local function _dist2(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return dx*dx + dy*dy + dz*dz
end

local function __occupiedKeysFromPets_fast()
    local keys = {}
    for _, m in ipairs(MyPets_List) do
        local root = m.PrimaryPart or m:FindFirstChild("RootPart")
        local gcp = root and root:GetAttribute("GridCenterPos") or m:GetAttribute("GridCenterPos")
        if gcp then
            local v = typeof(gcp)=="Vector3" and gcp or Vector3.new(
                gcp.X or gcp.x or gcp[1] or 0,
                gcp.Y or gcp.y or gcp[2] or 0,
                gcp.Z or gcp.z or gcp[3] or 0
            )
            keys[_keyXZ(v.X, v.Z)] = true
        end
    end
    return keys
end

local function __buildFreeList(area)
    local occ = __occupiedKeysFromPets_fast()
    local pool = (area == "Land" or area == "Water") and SortedPlots[area] or SortedPlots.Any
    local free = {}
    for i = 1, #pool do
        local part = pool[i]
        local k = _keyXZ(part.Position.X, part.Position.Z)
        if not occ[k] then
            free[#free+1] = { part = part, pos = part.Position, key = k }
        end
    end
    return free
end

local function __pickIndexFromFreeList(freeList, mode, hrpPos)
    if #freeList == 0 then return nil, nil end
    if mode == "first" or not hrpPos then return 1, freeList[1] end
    local bestIdx, bestD2
    for i = 1, #freeList do
        local d2 = _dist2(freeList[i].pos, hrpPos)
        if not bestD2 or d2 < bestD2 then bestIdx, bestD2 = i, d2 end
    end
    return bestIdx or 1, freeList[bestIdx or 1]
end

local function __getUnplacedPetUIDs()
    local uids = {}
    for _, petNode in ipairs(OwnedPetData:GetChildren()) do
        if not Pet_Folder:FindFirstChild(petNode.Name) then
            table.insert(uids, petNode.Name)
        end
    end
    return uids
end

local function __filterPetsForPlacing(list, inc_map)
    local mode = Configuration.Pet.PlacePet_Mode or "All"
    if mode == "All" then return list end

    local out = {}
    for _, uid in ipairs(list) do
        local petNode = OwnedPetData:FindFirstChild(uid)
        if petNode then
            if mode == "Match" then
                local t = petNode:GetAttribute("T")
                local m = petNode:GetAttribute("M") or "None"
                if (Configuration.Pet.PlacePet_Types[t]) and (Configuration.Pet.PlacePet_Mutations[m]) then
                    out[#out+1] = uid
                end
            elseif mode == "Range" then
                local inc = inc_map and inc_map[uid]
                if inc == nil then inc = GetInventoryIncomePerSecByUID(uid) end
                local mn = tonumber(Configuration.Pet.PlacePet_Between.Min) or 0
                local mx = tonumber(Configuration.Pet.PlacePet_Between.Max) or math.huge
                if inc >= mn and inc <= mx then
                    out[#out+1] = uid
                end
            end
        end
    end
    return out
end

local function __placeOnePetToPos(uid, worldPos)
    task.wait(0.2)
    CharacterRE:FireServer("Focus", uid)
    task.wait(0.25)
    CharacterRE:FireServer("Place", { DST = Vector3.new(worldPos.X, worldPos.Y, worldPos.Z), ID = uid })
    task.wait(1)
    CharacterRE:FireServer("Focus")
    local ok = Pet_Folder:WaitForChild(uid, 3) ~= nil
    return ok
end

local function placePetOnFreeTile(uid, area)
    if not uid or uid == "" then return false, "no uid" end
    local pool = (area == "Land" or area == "Water") and SortedPlots[area] or SortedPlots.Any
    local occ  = __occupiedKeysFromPets_fast()
    local part
    for i = 1, #pool do
        local k = _keyXZ(pool[i].Position.X, pool[i].Position.Z)
        if not occ[k] then part = pool[i]; break end
    end
    if not part then return false, "no free tile" end
    local dst = __tileCenterPos(part)
    local ok  = __placeOnePetToPos(uid, dst)
    return ok, ok and "placed" or "no confirm"
end

local function __getFilteredInventoryUidsSortedDesc()
    local uids = {}
    for _, node in ipairs(OwnedPetData:GetChildren()) do
        local uid = node.Name
        if not Pet_Folder:FindFirstChild(uid) then
            table.insert(uids, uid)
        end
    end
    if #uids == 0 then return {} end

    local inc = {}
    for i = 1, #uids, 1 do
        local uid = uids[i]
        inc[uid] = GetIncomeFast(uid) or 0
    end

    uids = __filterPetsForPlacing(uids, inc)

    table.sort(uids, function(a, b) return (inc[a] or 0) > (inc[b] or 0) end)
    return uids, inc
end

local function __findWorstPlacedPetInArea(areaWant)
    local worstUid, worstInc, worstTileKey, worstTilePart
    for uid, P in pairs(OwnedPets) do
        if P and not P.IsBig then
            local okArea = (areaWant == "Any") or (petArea(uid) == areaWant)
            if okArea then
                local incPlaced = tonumber(P.ProduceSpeed) or 0
                local gc = P.GridCoord
                local key
                if gc then
                    key = _keyXZ(gc.X or 0, gc.Z or 0)
                else
                    local rp = P.RootPart
                    local pos = rp and rp.Position or Vector3.new()
                    key = _keyXZ(pos.X, pos.Z)
                end
                local node = PlotIndex[key]
                if node then
                    if (worstInc == nil) or (incPlaced < worstInc) then
                        worstInc, worstUid, worstTileKey, worstTilePart = incPlaced, uid, key, node.part
                    end
                end
            end
        end
    end
    return worstUid, worstInc or 0, worstTileKey, worstTilePart
end

local function __replacePetAtTile(oldUid, newUid, tilePart)
    local Pold = OwnedPets[oldUid]
    if Pold and Pold.IsBig then
        return false, "skip-big"
    end
    if not tilePart then return false, "no tile" end
    local dst = __tileCenterPos(tilePart)

    if Pold and Pold.RE then pcall(function() Pold.RE:FireServer("Claim") end) end
    CharacterRE:FireServer("Del", oldUid)
    task.wait(0.4)

    CharacterRE:FireServer("Focus", newUid); task.wait(0.25)
    CharacterRE:FireServer("Place", { DST = dst, ID = newUid })
    task.wait(0.7)
    CharacterRE:FireServer("Focus")

    local ok = Pet_Folder:WaitForChild(newUid, 3) ~= nil
    return ok, ok and "replaced" or "place-failed"
end


local function runAutoPlacePet(tok)
    while tok.alive do
        local area = Configuration.Pet.PlaceArea or "Any"
        local function __smartPassOnce(limitReplace)
            if not Configuration.Pet.SmartPet then return end
            local area = Configuration.Pet.PlaceArea or "Any"
            local invUids, incMap = __getFilteredInventoryUidsSortedDesc()
            if not invUids or #invUids == 0 then return end
            local tries = 0
            while tries < (limitReplace or 3) do
                local worstUid, worstInc, _, worstTilePart = __findWorstPlacedPetInArea(area)
                if not worstUid then break end
                local bestUid = invUids[1]
                local bestInc = (bestUid and incMap and incMap[bestUid]) or (bestUid and GetIncomeFast(bestUid)) or 0
                if not bestUid or (bestInc <= (worstInc or 0)) then break end
                local ok = false
                if worstTilePart then
                    ok = select(1, __replacePetAtTile(worstUid, bestUid, worstTilePart))
                end
                table.remove(invUids, 1)
                tries = tries + 1
                if #invUids == 0 then break end
                task.wait(0.1)
            end
        end
        __smartPassOnce(1)
        local freeList = (function()
            local keys = __occupiedKeysFromPets_fast()
            local pool = (area == "Land" or area == "Water") and SortedPlots[area] or SortedPlots.Any
            local free = {}
            for i = 1, #pool do
                local part = pool[i]
                local k = _keyXZ(part.Position.X, part.Position.Z)
                if not keys[k] then
                    free[#free+1] = { part = part, pos = part.Position, key = k }
                end
            end
            return free
        end)()

        if #freeList == 0 then
            if not Configuration.Pet.SmartPet then
                Fluent:Notify({ Title = "Auto Place Pet", Content = "ไม่มีพื้นที่ว่างให้วางสัตว์แล้ว • ปิด Auto Place ให้", Duration = 5 })
                pcall(function() Options["Auto Place Pet"]:SetValue(false) end)
                TaskMgr.stop("AutoPlacePet")
                break
            else
                if not _waitAlive(tok, tonumber(Configuration.Pet.AutoPlacePet_Delay) or 1) then break end
            end
        else
            local uids = {}
            for _, petNode in ipairs(OwnedPetData:GetChildren()) do
                local uid = petNode.Name
                if not Pet_Folder:FindFirstChild(uid) then
                    uids[#uids+1] = uid
                end
            end
            if #uids > 0 then
                local inc_by_uid = {}
                for i = 1, #uids do
                    local uid = uids[i]
                    inc_by_uid[uid] = GetIncomeFast(uid)
                end
                table.sort(uids, function(a,b)
                    return (inc_by_uid[a] or 0) > (inc_by_uid[b] or 0)
                end)
                uids = (function(list, inc_map)
                    local mode = Configuration.Pet.PlacePet_Mode or "All"
                    if mode == "All" then return list end
                    local out = {}
                    for _, uid in ipairs(list) do
                        local petNode = OwnedPetData:FindFirstChild(uid)
                        if petNode then
                            if mode == "Match" then
                                local t = petNode:GetAttribute("T")
                                local m = petNode:GetAttribute("M") or "None"
                                if (Configuration.Pet.PlacePet_Types[t]) and (Configuration.Pet.PlacePet_Mutations[m]) then
                                    out[#out+1] = uid
                                end
                            elseif mode == "Range" then
                                local inc = inc_map and inc_map[uid]
                                if inc == nil then inc = GetInventoryIncomePerSecByUID(uid) end
                                local mn = tonumber(Configuration.Pet.PlacePet_Between.Min) or 0
                                local mx = tonumber(Configuration.Pet.PlacePet_Between.Max) or math.huge
                                if inc >= mn and inc <= mx then
                                    out[#out+1] = uid
                                end
                            end
                        end
                    end
                    return out
                end)(uids, inc_by_uid)
                for _, uid in ipairs(uids) do
                    if not tok.alive then break end
                    if #freeList == 0 then
                        Fluent:Notify({ Title = "Auto Place Pet", Content = "พื้นที่ว่างหมดระหว่างการวาง • ปิด Auto Place ให้", Duration = 5 })
                        pcall(function() Options["Auto Place Pet"]:SetValue(false) end)
                        TaskMgr.stop("AutoPlacePet")
                        tok.alive = false
                        break
                    end
                    local idx, node = 1, freeList[1]
                    task.wait(0.15)
                    CharacterRE:FireServer("Focus", uid)
                    task.wait(0.25)
                    local dst = __tileCenterPos(node.part)
                    CharacterRE:FireServer("Place", { DST = dst, ID = uid })
                    task.wait(0.75)
                    CharacterRE:FireServer("Focus")
                    local ok = Pet_Folder:WaitForChild(uid, 2) ~= nil
                    dprint("[AutoPlacePet]", uid, ok and "OK" or "FAIL")
                    if ok then table.remove(freeList, idx) end
                    task.wait(0.1)
                end
            end
        end
        if not _waitAlive(tok, tonumber(Configuration.Pet.AutoPlacePet_Delay) or 1) then break end        
    end
end

local function runAutoPlaceEgg(tok)
    dprint("[AutoPlaceEgg] temporarily disabled (stub).")
    while tok.alive do
        if not _waitAlive(tok, tonumber(Configuration.Egg.AutoPlaceEgg_Delay) or 1) then break end
        break
    end
end

--==============================================================
--                    OTHER RUNNERS
--==============================================================
local function runAntiAFK(tok)
    local VirtualUser = game:GetService("VirtualUser")
    while tok.alive do
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        if not _waitAlive(tok, 30) then break end
    end
end

local function runAutoCollect(tok)
    -- ไม่จำเป็นต้องใช้ COOLDOWN_BETWEEN_BATCH แล้ว
    while tok.alive do
        for _, pet in pairs(OwnedPets) do
            if not tok.alive then break end -- ออกจากลูปทันทีถ้าปิดฟังก์ชัน

            local RE = pet and pet.RE
            if RE then
                pcall(function() RE:FireServer("Claim") end)
                task.wait(0.1) -- << เพิ่มการหน่วงเวลาตรงนี้!
            else
                task.wait() -- พักเล็กน้อยถ้าไม่เจอ RE
            end
        end

        -- รอดีเลย์หลักตามที่ตั้งค่าไว้ใน UI
        local d = tonumber(Configuration.Main.Collect_Delay) or 3
        if not _waitAlive(tok, d) then break end
    end
end

function GetInventoryIncomePerSecByUID(uid)
    if not uid or uid == "" then return 0 end
    local pg = Player:FindFirstChild("PlayerGui"); if not pg then return 0 end
    local screenStorage = pg:FindFirstChild("ScreenStorage"); if not screenStorage then return 0 end
    local frame = screenStorage:FindFirstChild("Frame"); if not frame then return 0 end
    local contentPet = frame:FindFirstChild("ContentPet"); if not contentPet then return 0 end
    local scrolling = contentPet:FindFirstChild("ScrollingFrame"); if not scrolling then return 0 end

    local item = scrolling:FindFirstChild(uid)
    if not item then
        for _, ch in ipairs(scrolling:GetChildren()) do
            if ch.Name == uid then item = ch break end
        end
    end
    if not item then return 0 end

    local btn  = item:FindFirstChild("BTN") or item:FindFirstChildWhichIsA("Frame")
    if not btn then return 0 end
    local stat = btn:FindFirstChild("Stat") or btn:FindFirstChildWhichIsA("Frame")
    if not stat then return 0 end
    local price = stat:FindFirstChild("Price") or stat:FindFirstChildWhichIsA("Frame")
    if not price then return 0 end

    local valueObj = price:FindFirstChild("Value")
    if valueObj then
        if valueObj:IsA("NumberValue") or valueObj:IsA("IntValue") then
            return tonumber(valueObj.Value) or 0
        elseif valueObj:IsA("StringValue") then
            local s = tostring(valueObj.Value or "")
            local n = tonumber((s:gsub("[^%d%.]", "")))
            return n or 0
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
    return 0
end

local function runAutoFeed(tok)
    local Data_OwnedPets = Data:WaitForChild("Pets",30)
    while tok.alive do
        if not InventoryData then InventoryData = Data:FindFirstChild("Asset") end
        local Data_Inventory = (InventoryData and InventoryData:GetAttributes()) or {}
        for _, petCfg in ipairs(Data_OwnedPets:GetChildren()) do
            if not tok.alive then break end
            local uid = petCfg.Name
            local petModel = OwnedPets[uid]
            if petModel and petModel.IsBig and (not petCfg:GetAttribute("Feed")) then
                local Food = pickFoodPerPet(uid, Data_Inventory)
                if Food and Food ~= "" then
                    CharacterRE:FireServer("Focus", Food) task.wait(0.3)
                    PetRE:FireServer("Feed", petModel.UID) task.wait(0.3)
                    CharacterRE:FireServer("Focus")
                    Data_Inventory[Food] = math.max(0, (tonumber(Data_Inventory[Food] or 0) or 0) - 1)
                end
            end
        end
        if not _waitAlive(tok, tonumber(Configuration.Pet.AutoFeed_Delay) or 10) then break end
    end
end

local function runAutoCollectPet(tok)
    local function passArea(uid)
        local want = Configuration.Pet.CollectPet_Area or "Any"
        if want == "Any" then return true end
        return petArea(uid) == want
    end
    while tok.alive do
        local CollectType = Configuration.Pet.CollectPet_Type or "All"
        local function claimDel(UID, PetData)
            if PetData.RE then PetData.RE:FireServer("Claim") end
            CharacterRE:FireServer("Del", UID)
        end
        if CollectType == "All" then
            for UID, PetData in pairs(OwnedPets) do
                if not tok.alive then break end
                if PetData and not PetData.IsBig and passArea(UID) then claimDel(UID, PetData) end
            end
        elseif CollectType == "Match Pet" then
            for UID, PetData in pairs(OwnedPets) do
                if not tok.alive then break end
                if PetData and not PetData.IsBig and passArea(UID)
                and Configuration.Pet.CollectPet_Pets[PetData.Type] then claimDel(UID, PetData) end
            end
        elseif CollectType == "Match Mutation" then
            for UID, PetData in pairs(OwnedPets) do
                if not tok.alive then break end
                if PetData and not PetData.IsBig and passArea(UID)
                and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then claimDel(UID, PetData) end
            end
        elseif CollectType == "Match Pet&Mutation" then
            for UID, PetData in pairs(OwnedPets) do
                if not tok.alive then break end
                if PetData and not PetData.IsBig and passArea(UID)
                and Configuration.Pet.CollectPet_Pets[PetData.Type]
                and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then claimDel(UID, PetData) end
            end
        elseif CollectType == "Range" then
            local minV = tonumber(Configuration.Pet.CollectPet_Between.Min) or 0
            local maxV = tonumber(Configuration.Pet.CollectPet_Between.Max) or math.huge
            for UID, PetData in pairs(OwnedPets) do
                if not tok.alive then break end
                if PetData and not PetData.IsBig and passArea(UID) then
                    local ps = tonumber(PetData.ProduceSpeed) or 0
                    if ps >= minV and ps <= maxV then claimDel(UID, PetData) end
                end
            end
        end
        if not _waitAlive(tok, tonumber(Configuration.Pet.CollectPet_Delay) or 5) then break end
    end
end

local function runAutoHatch(tok)
    while tok.alive do
        local wantArea = Configuration.Egg.HatchArea or "Any"
        for _,egg in pairs(OwnedEggData:GetChildren()) do
            if not tok.alive then break end
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
        if not _waitAlive(tok, tonumber(Configuration.Egg.Hatch_Delay) or 15) then break end
    end
end

local function runAutoClaim(tok)
    local Tasks; local EventRE = ResEvent and GameRemoteEvents:WaitForChild(tostring(ResEvent).."RE")
    if EventTaskData then Tasks = EventTaskData:WaitForChild("Tasks") end
    while tok.alive do
        if Tasks and EventRE then
            for _,Quest in pairs(Tasks:GetChildren()) do
                if not tok.alive then break end
                EventRE:FireServer({event = "claimreward",id = Quest:GetAttribute("Id")})
                task.wait(0.5) -- << เพิ่มการหน่วงเวลาตรงนี้!
            end
        end
        if not _waitAlive(tok, tonumber(Configuration.Event.AutoClaim_Delay) or 3) then break end
    end
end

local function runAutoBuyEgg(tok)
    local RE = GameRemoteEvents:WaitForChild("CharacterRE",30)
    local function currentCoin()
        local asset = InventoryData or Data:FindFirstChild("Asset")
        return asset and (tonumber(asset:GetAttribute("Coin") or 0) or 0) or 0
    end
    while tok.alive do
        if (not Configuration.Egg.CheckMinCoin) or (currentCoin() >= (tonumber(Configuration.Egg.MinCoin) or 0)) then
            for _,egg in pairs(Egg_Belt) do
                if not tok.alive then break end
                local okType = Configuration.Egg.Types[egg.Type]
                local okMut  = Configuration.Egg.Mutations[egg.Mutate]
                if okType and okMut then
                    pcall(function() RE:FireServer("BuyEgg", egg.UID) end)
                    task.wait(0.15 + math.random() * 0.15)
                end
            end
        end
        if not _waitAlive(tok, (tonumber(Configuration.Egg.AutoBuyEgg_Delay) or 1) + math.random()*0.4) then break end
    end
end

local function runAutoBuyFood(tok)
    local FoodList = Data:WaitForChild("FoodStore",30):WaitForChild("LST",30)
    local RE = GameRemoteEvents:WaitForChild("FoodStoreRE")
    while tok.alive do
        for foodName,stockAmount in pairs(FoodList:GetAttributes()) do
            if not tok.alive then break end
            if stockAmount > 0 and Configuration.Shop.Food.Foods[foodName] then
                pcall(function() RE:FireServer(foodName) end)
                task.wait(0.12 + math.random()*0.12)
            end
        end
        if not _waitAlive(tok, (tonumber(Configuration.Shop.Food.AutoBuy_Delay) or 1) + math.random()*0.35) then break end
    end
end

local function runAutoLottery(tok)
    local LotteryRE = GameRemoteEvents:WaitForChild("LotteryRE",30)
    while tok.alive do
        local args = { event = "lottery", count = 1 }
        LotteryRE:FireServer(args)
        if not _waitAlive(tok, tonumber(Configuration.Event.AutoLottery_Delay) or 60) then break end
    end
end

--==============================================================
--                      UI
--==============================================================
local Window = Fluent:CreateWindow({
    Title = GameName, SubTitle = "by DemiGodz", TabWidth = 160,
    Size = UDim2.fromOffset(522, 414), Acrylic = true, Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})
-- วาง Home เป็นแท็บแรก (จะขึ้นบนสุด)
local Home = Window:AddTab({ Title = "Home", Icon = "home" })
local Tabs = {
    Main = Window:AddTab({ Title = "Main Features", Icon = "monitor-check" }),
    Pet = Window:AddTab({ Title = "Pet Features", Icon = "paw-print" }),
    Egg = Window:AddTab({ Title = "Egg Features", Icon = "egg" }),
    Shop = Window:AddTab({ Title = "Shop Features", Icon = "shopping-cart" }),
    Event = Window:AddTab({ Title = "Event Feature", Icon = "bookmark-check" }),
    Players = Window:AddTab({ Title = "Players Features", Icon = "shield-user" }),
    Sell = Window:AddTab({ Title = "Sell Features", Icon = "badge-dollar-sign" }),
    Inv = Window:AddTab({ Title = "Inventory", Icon = "archive" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
    About = Window:AddTab({ Title = "badge-info" }),
}
    Options = Fluent.Options

--============================== Main ==============================
Tabs.Main:AddSection("Main")
Tabs.Main:AddToggle("AutoCollect",{ Title="Auto Collect", Default=false, Callback=function(v)
    Configuration.Main.AutoCollect = v
    if v then TaskMgr.start("AutoCollect", runAutoCollect) else TaskMgr.stop("AutoCollect") end
end })
Tabs.Main:AddSection("Settings")
Tabs.Main:AddSlider("AutoCollect Delay",{ Title = "Collect Delay", Default = 3, Min = 3, Max = 180, Rounding = 0, Callback = function(v) Configuration.Main.Collect_Delay = v end })

--===================== Performance =====================
Tabs.Main:AddSection("Performance")
Tabs.Main:AddToggle("FPS_Lock", { Title = "Lock FPS", Default = false, Callback = function(v)
    Configuration.Perf.FPSLock = v; ApplyFPSLock()
end })
Tabs.Main:AddInput("FPS_Value", { Title = "FPS Cap", Default = tostring(Configuration.Perf.FPSValue), Numeric = true, Finished = true, Callback = function(v)
    Configuration.Perf.FPSValue = tonumber(v) or 60; if Configuration.Perf.FPSLock then ApplyFPSLock() end
end })
Tabs.Main:AddToggle("Hide Pets", { Title = "Disable Pets Model", Default = false, Callback = function(v)
    Configuration.Perf.HidePets = v; ApplyHidePets(v)
end })
Tabs.Main:AddToggle("Hide Eggs", { Title = "Disable Eggs Model", Default = false, Callback = function(v)
    Configuration.Perf.HideEggs = v; ApplyHideEggs(v)
end })
Tabs.Main:AddToggle("Hide Effects", { Title = "Disable Effects", Default = false, Callback = function(v)
    Configuration.Perf.HideEffects = v; ApplyHideEffects(v)
end })
Tabs.Main:AddToggle("Hide Game UI", { Title = "Hide UI", Default = false, Callback = function(v)
    Configuration.Perf.HideGameUI = v; ApplyHideGameUI(v)
end })

--============================== Pet ===============================
Tabs.Pet:AddSection("Main")
Tabs.Pet:AddToggle("Auto Feed",{ Title="Auto Feed", Default=false, Callback=function(v)
    Configuration.Pet.AutoFeed = v
    if v then TaskMgr.start("AutoFeed", runAutoFeed) else TaskMgr.stop("AutoFeed") end
end })
Tabs.Pet:AddToggle("Auto Collect Pet",{ Title="Auto Collect Pet", Default=false, Callback=function(v)
    Configuration.Pet.CollectPet_Auto = v
    if v then TaskMgr.start("AutoCollectPet", runAutoCollectPet) else TaskMgr.stop("AutoCollectPet") end
end })

Tabs.Pet:AddToggle("Auto Place Pet",{
    Title="Auto Place Pet", Default=false,
    Callback=function(v)
        Configuration.Pet.AutoPlacePet = v
        if v then TaskMgr.start("AutoPlacePet", runAutoPlacePet)
        else TaskMgr.stop("AutoPlacePet") end
    end
})

Tabs.Pet:AddToggle("SmartPet", {
    Title = "SmartPet",
    Default = false,
    Callback = function(v) Configuration.Pet.SmartPet = v end
})

Tabs.Pet:AddButton({
    Title = "Collect Pet",
    Description = "Collect Pets with Collect Pet Type (no BIG pet)",
    Callback = function()
        Window:Dialog({
            Title = "Collect Pet Alert", Content = "Are you sure?",
            Buttons = {
                { Title = "Yes", Callback = function()
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
Tabs.Pet:AddSlider("AutoFeed Delay",{ Title = "Feed Delay", Default = 10, Min = 10, Max = 30, Rounding = 0, Callback = function(v) Configuration.Pet.AutoFeed_Delay = v end })
Tabs.Pet:AddSlider("AutoCollectPet Delay",{ Title = "Auto Collect Pet Delay", Default = 5, Min = 5, Max = 60, Rounding = 0, Callback = function(v) Configuration.Pet.CollectPet_Delay = v end })

local BigPetUIDLabels = {}
local function labelForBigPet(uid, P)
    return string.format("[%s|%s] %s",
        tostring(P and P.Type or "?"),
        tostring(P and P.Mutate or "None"),
        tostring(uid))
end
local function labelToUID(v)
    if type(v) ~= "string" then return v end
    if BigPetUIDLabels and BigPetUIDLabels[v] then
        return BigPetUIDLabels[v]
    end
    local uid = v:match("%]%s+(.+)$")
    return uid or v
end

PickPetForFoodDD = Tabs.Pet:AddDropdown("PickPet ForFood", {
    Title = "Pick Big Pet",
    Values = {}, Multi = false, Default = "",
    Callback = function(label)
        Configuration.Pet._PickPetForFood = labelToUID(label or "")
    end
})

local function _cloneFoodMap_ext(t) return _cloneFoodMap(t) end

local PickFoodsForPetDD = Tabs.Pet:AddDropdown("PickFoods ForOnePet", {
    Title = "Select Food",
    Description = "เลือกชนิดอาหารที่จะอนุญาตให้สัตว์ตัวนี้กิน",
    Values = PetFoods_InGame, Multi = true, Default = {},
    Callback = function(v) Configuration.Pet._PickFoodsDraft = v end
})
Tabs.Pet:AddButton({
    Title = "Save foods to this pet",
    Description = "บันทึกชุดอาหารให้กับ Big Pet ที่เลือก",
    Callback = function()
        local uid   = Configuration.Pet._PickPetForFood
        local draft = Configuration.Pet._PickFoodsDraft
        if not uid or uid == "" then
            Fluent:Notify({ Title="Per-Pet Food", Content="กรุณาเลือก Big Pet ก่อน", Duration=4 })
            return
        end
        if type(draft) ~= "table" or next(draft) == nil then
            Fluent:Notify({ Title="Per-Pet Food", Content="ยังไม่ได้เลือกชนิดอาหาร", Duration=4 })
            return
        end
        Configuration.Pet.AutoFeed_PetFoods[uid] = _cloneFoodMap(draft)
        Configuration.Pet._PickFoodsDraft = {}
        Fluent:Notify({ Title="Per-Pet Food", Content=("บันทึกอาหารให้ UID: %s แล้ว"):format(uid), Duration=4 })
    end
})
Tabs.Pet:AddButton({
    Title = "Clear foods for this pet",
    Description = "ล้างรายการอาหารของ Big Pet ตัวที่เลือก",
    Callback = function()
        local uid = Configuration.Pet._PickPetForFood
        if uid and Configuration.Pet.AutoFeed_PetFoods[uid] then
            Configuration.Pet.AutoFeed_PetFoods[uid] = nil
            Fluent:Notify({ Title="Per-Pet Food", Content=("ล้างรายการของ UID: %s แล้ว"):format(uid), Duration=4 })
        end
    end
})
Tabs.Pet:AddToggle("Use Per-Pet Foods", {
    Title = "Use per-pet foods first",
    Default = true,
    Callback = function(v) Configuration.Pet.AutoFeed_UsePerPet = v end
})

local function updateBigPetUIDDropdowns()
    local labels = {}
    BigPetUIDLabels = {}
    for uid, P in pairs(OwnedPets) do
        if P and P.IsBig then
            local label = labelForBigPet(uid, P)
            BigPetUIDLabels[label] = uid
            table.insert(labels, label)
        end
    end
    pcall(function() Options["Pet Feed_Targets"]:SetValues(labels) end)
    if PickPetForFoodDD then
        pcall(function() PickPetForFoodDD:SetValues(labels) end)
    end
end
table.insert(EnvirontmentConnections, Pet_Folder.ChildAdded:Connect(function()
    task.delay(0.2, updateBigPetUIDDropdowns)
end))
table.insert(EnvirontmentConnections, Pet_Folder.ChildRemoved:Connect(function()
    task.delay(0.2, updateBigPetUIDDropdowns)
end))
task.defer(updateBigPetUIDDropdowns)

local FeedTargetsDD = Tabs.Pet:AddDropdown("Pet Feed_Targets", {
    Title = "Select Big Pets to Feed",
    Description = "เลือกเฉพาะ Big Pets ที่จะให้อาหาร (เว้นว่าง = ให้อาหาร Big ทุกตัว)",
    Values = {}, Multi = true, Default = {},
    Callback = function(selected)
        local uidSet = {}
        if type(selected) == "table" then
            for k, on in pairs(selected) do
                if on then
                    local uid = labelToUID(k)
                    uidSet[uid] = true
                end
            end
        elseif type(selected) == "string" and selected ~= "" then
            uidSet[labelToUID(selected)] = true
        end
        Configuration.Pet.AutoFeed_Pets = uidSet
    end
})

Tabs.Pet:AddDropdown("CollectPet Type",{ Title = "Collect Pet Type", Values = {"All","Match Pet","Match Mutation","Match Pet&Mutation","Range"}, Multi = false, Default = "All", Callback = function(v) Configuration.Pet.CollectPet_Type = v end })
Tabs.Pet:AddDropdown("CollectPet Area",{ Title = "Collect Pet Area", Values = {"Any","Land","Water"}, Multi = false, Default = "Any", Callback = function(v) Configuration.Pet.CollectPet_Area = v end })
Tabs.Pet:AddDropdown("CollectPet Pets",{ Title = "Collect Pets", Values = Pets_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.CollectPet_Pets = v end })
Tabs.Pet:AddDropdown("CollectPet Mutations",{ Title = "Collect Mutations", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.CollectPet_Mutations = v end })
Tabs.Pet:AddInput("CollectCash_Num1",{ Title = "Min Coin", Default = 100000, Numeric = true, Finished = false, Callback = function(v) Configuration.Pet.CollectPet_Between.Min = tonumber(v) end })
Tabs.Pet:AddInput("CollectCash_Num2",{ Title = "Max Coin", Default = 1000000, Numeric = true, Finished = false, Callback = function(v) Configuration.Pet.CollectPet_Between.Max = tonumber(v) end })

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
Tabs.Egg:AddToggle("Auto Hatch",{ Title="Auto Hatch", Default=false, Callback=function(v)
    Configuration.Egg.AutoHatch = v
    if v then TaskMgr.start("AutoHatch", runAutoHatch) else TaskMgr.stop("AutoHatch") end
end })
Tabs.Egg:AddToggle("Auto Egg",{ Title="Auto Buy Egg", Default=false, Callback=function(v)
    Configuration.Egg.AutoBuyEgg = v
    if v then TaskMgr.start("AutoBuyEgg", runAutoBuyEgg) else TaskMgr.stop("AutoBuyEgg") end
end })
Tabs.Egg:AddToggle("Auto Place Egg",{ Title="Auto Place Egg", Default=false, Callback=function(v)
    Configuration.Egg.AutoPlaceEgg = v
    if v then
        Fluent:Notify({ Title = "Auto Place Egg", Content = "This feature is temporarily disabled (stub).", Duration = 4 })
        TaskMgr.start("AutoPlaceEgg", runAutoPlaceEgg)
    else
        TaskMgr.stop("AutoPlaceEgg")
    end
end })
Tabs.Egg:AddToggle("CheckMinCoin",{ Title = "Check Min Coin", Default = false, Callback = function(v) Configuration.Egg.CheckMinCoin = v end })

Tabs.Egg:AddSection("Settings")
Tabs.Egg:AddDropdown("Hatch Area",{ Title = "Hatch Area", Values = {"Any","Land","Water"}, Multi = false, Default = "Any", Callback = function(v) Configuration.Egg.HatchArea = v end })
Tabs.Egg:AddSlider("AutoHatch Delay",{ Title = "Hatch Delay", Default = 15, Min = 15, Max = 60, Rounding = 0, Callback = function(v) Configuration.Egg.Hatch_Delay = v end })
Tabs.Egg:AddSlider("AutoBuyEgg Delay",{ Title = "Auto Buy Egg Delay", Default = 1, Min = 0.1, Max = 3, Rounding = 1, Callback = function(v) Configuration.Egg.AutoBuyEgg_Delay = v end })
Tabs.Egg:AddSlider("AutoPlaceEgg Delay",{ Title = "Auto Place Egg Delay", Default = 1, Min = 0.1, Max = 5, Rounding = 1, Callback = function(v) Configuration.Egg.AutoPlaceEgg_Delay = v end })
Tabs.Egg:AddDropdown("PlaceEgg Area", { Title = "Place Area (Egg)", Values = {"Any","Land","Water"}, Multi = false, Default = "Any", Callback = function(v) Configuration.Egg.PlaceArea = v end })
Tabs.Egg:AddDropdown("Egg Type", {
    Title = "Types",
    Values = Eggs_InGame, Multi = true, Default = {},
    Callback = function(v) Configuration.Egg.Types = v end
})
Tabs.Egg:AddDropdown("Egg Mutations", {
    Title = "Mutations",
    Values = Mutations_InGame, Multi = true, Default = {},
    Callback = function(v) Configuration.Egg.Mutations = v end
})
Tabs.Egg:AddInput("Min Coin to Buy", {
    Title = "Min Coin", Default = tostring(Configuration.Egg.MinCoin or 0),
    Numeric = true, Finished = true,
    Callback = function(v) Configuration.Egg.MinCoin = tonumber(v) or 0 end
})

--============================== Shop =============================
Tabs.Shop:AddSection("Main")
Tabs.Shop:AddToggle("Auto BuyFood",{ Title="Auto Buy Food", Default=false, Callback=function(v)
    Configuration.Shop.Food.AutoBuy = v
    if v then TaskMgr.start("AutoBuyFood", runAutoBuyFood) else TaskMgr.stop("AutoBuyFood") end
end })
Tabs.Shop:AddSection("Settings")
Tabs.Shop:AddSlider("AutoBuyFood Delay",{ Title = "Auto Buy Food Delay", Default = 1, Min = 0.1, Max = 3, Rounding = 1, Callback = function(v) Configuration.Shop.Food.AutoBuy_Delay = v end })
Tabs.Shop:AddDropdown("Foods Dropdown",{ Title = "Foods", Values = PetFoods_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Shop.Food.Foods = v end })

--============================== Event ============================
Tabs.Event:AddParagraph({ Title = "Event Information", Content = string.format("Current Event : %s",EventName) })
Tabs.Event:AddSection("Main")
Tabs.Event:AddToggle("Auto Claim Event Quest",{ Title="Auto Claim", Default=false, Callback=function(v)
    Configuration.Event.AutoClaim = v
    if v then TaskMgr.start("AutoClaim", runAutoClaim) else TaskMgr.stop("AutoClaim") end
end })
Tabs.Event:AddSection("Settings")
Tabs.Event:AddSlider("Event_AutoClaim Delay",{ Title = "Auto Claim Delay", Default = 3, Min = 3, Max = 30, Rounding = 0, Callback = function(v) Configuration.Event.AutoClaim_Delay = v end })

Tabs.Event:AddSection("Lottery")
Tabs.Event:AddToggle("Auto Lottery Ticket",{ Title="Auto Lottery Ticket", Default=false, Callback=function(v)
    Configuration.Event.AutoLottery = v
    if v then TaskMgr.start("AutoLottery", runAutoLottery) else TaskMgr.stop("AutoLottery") end
end })
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
                        local function trySendFocus(name)
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
                                    for _ = 1, canSend do
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
                                for _ = 1, FoodAmount do
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
                                for _ = 1, canSend do
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
                        local function isPicked(tbl, key)
                            if type(tbl) ~= "table" then return false end
                            if tbl[key] == true then return true end
                            for _, v in ipairs(tbl) do if v == key then return true end end
                            return false
                        end
                        local typeOn = next(Configuration.Players.Egg_Types)     ~= nil
                        local mutOn  = next(Configuration.Players.Egg_Mutations) ~= nil
                        local buckets = {}
                        for _, Egg in ipairs(OwnedEggData:GetChildren()) do
                            if Egg and not Egg:FindFirstChild("DI") then
                                local t = Egg:GetAttribute("T") or "BasicEgg"
                                local m = Egg:GetAttribute("M") or "None"
                                local okT = (not typeOn) or isPicked(Configuration.Players.Egg_Types, t)
                                local okM = (mutOn and isPicked(Configuration.Players.Egg_Mutations, m))
                                         or ((not mutOn) and (m == "None"))
                                if okT and okM then
                                    buckets[m] = buckets[m] or {}
                                    table.insert(buckets[m], Egg.Name)
                                end
                            end
                        end
                        local function perMutationLimit()
                            local n = tonumber(Configuration.Players.Gift_Limit)
                            if not n or n <= 0 then return math.huge end
                            return math.floor(n)
                        end
                        local PER_LIMIT = perMutationLimit()
                        local order = {}
                        if mutOn then
                            if type(Configuration.Players.Egg_Mutations) == "table" and #Configuration.Players.Egg_Mutations > 0 then
                                for _, m in ipairs(Configuration.Players.Egg_Mutations) do table.insert(order, m) end
                            else
                                for m, on in pairs(Configuration.Players.Egg_Mutations) do if on then table.insert(order, m) end end
                            end
                        else
                            order = { "None" }
                        end
                        local totalSent = 0
                        for _, m in ipairs(order) do
                            local list = buckets[m] or {}
                            local count = math.min(PER_LIMIT, #list)
                            for i = 1, count do
                                local uid = list[i]
                                CharacterRE:FireServer("Focus", uid) task.wait(0.75)
                                GiftRE:FireServer(GiftPlayer)         task.wait(0.75)
                                CharacterRE:FireServer("Focus")
                                totalSent = totalSent + 1
                            end
                        end
                        if totalSent == 0 then
                            Fluent:Notify({ Title = "Match_Eggs", Content = "ไม่พบไข่ที่ตรงเงื่อนไข (หรือถูกวางไว้แล้ว)", Duration = 4 })
                        end
                    end
                    Configuration.Waiting = false
                end },
                { Title = "No" }
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

--============================== Inventory =============================
local MUTA_EMOJI = setmetatable({
    ["None"]    = "🥚",
    ["Fire"]    = "🔥",
    ["Electirc"]= "⚡",
    ["Diamond"] = "💎",
    ["Golden"]  = "🪙",
    ["Dino"]    = "🦖",
}, { __index = function() return "🔹" end })
local MUTA_ORDER = { "None","Fire","Electirc","Diamond","Golden","Dino" }
local ORDER_SET = {}; for _,k in ipairs(MUTA_ORDER) do ORDER_SET[k]=true end

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

Tabs.Inv:AddParagraph({ Title = "Eggs", Content = "Your Egg Collection  •  View all eggs in your inventory" })
local ResultPara = Tabs.Inv:AddParagraph({ Title = "Summary", Content = "กดปุ่ม Refresh เพื่อดึงข้อมูลล่าสุด…" })

local function renderSummary()
    local map = CountEggsByTypeMuta()
    local lines, shown = {}, {}
    local function lineFor(typeName, mutaCounts)
        table.insert(lines, string.format("\n• %s", tostring(typeName)))
        for _, key in ipairs(MUTA_ORDER) do
            local n = tonumber(mutaCounts[key] or 0) or 0
            if n > 0 then
                table.insert(lines, string.format("    - %s %s: %d", MUTA_EMOJI[key], key, n))
            end
        end
        for m, n in pairs(mutaCounts) do
            if not ORDER_SET[m] and (tonumber(n) or 0) > 0 then
                table.insert(lines, string.format("    - %s %s: %d", MUTA_EMOJI[m], m, n))
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
                                total = total + 1
                                local ok = select(1, SellPet(uid))
                                if ok then okCnt += 1 else failCnt += 1 end
                                task.wait(0.15)
                            end
                        end
                    elseif mode == "All_Unplaced_Eggs" then
                        for _, egg in ipairs(OwnedEggData:GetChildren()) do
                            if egg and not egg:FindFirstChild("DI") then
                                total = total + 1
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
                                local okM = (mutOn and (Configuration.Sell.Egg_Mutations[m] == true)) or ((not mutOn) and (m == "None"))
                                if okT and okM then
                                    total = total + 1
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
                                    total = total + 1
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

--============================== About / Settings =================
Tabs.About:AddParagraph({ Title = "Credit", Content = "Script create by DemiGodz" })
Tabs.Settings:AddToggle("AntiAFK",{ Title="Anti AFK", Default=false, Callback=function(v)
    ServerReplicatedDict:SetAttribute("AFK_THRESHOLD",(v == false and 1080 or v == true and 99999999999))
    Configuration.AntiAFK = v
    if v then TaskMgr.start("AntiAFK", runAntiAFK) else TaskMgr.stop("AntiAFK") end
end })
Tabs.Settings:AddToggle("Disable3DOnly", {
    Title = "Disable 3D Rendering (GUI only)",
    Default = false,
    Callback = function(v)
        Configuration.Perf.Disable3D = v
        Perf_Set3DEnabled(not v)
    end
})
Tabs.Settings:AddSection("Debug")
Tabs.Settings:AddToggle("DebugOn", {
    Title = "Enable Debug Log",
    Default = (G.MEOWY_DBG and G.MEOWY_DBG.on) or true,
    Callback = function(v) G.MEOWY_DBG = G.MEOWY_DBG or {}; G.MEOWY_DBG.on = v end
})
Tabs.Settings:AddToggle("DebugToast", {
    Title = "Show Debug as Toast",
    Default = (G.MEOWY_DBG and G.MEOWY_DBG.toast) or false,
    Callback = function(v) G.MEOWY_DBG = G.MEOWY_DBG or {}; G.MEOWY_DBG.toast = v end
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

-----------------------------------------------------------------
-- ===== UX/UI (Home at top • No Profiles/Logs/SearchPlayer) =====
-----------------------------------------------------------------



local StatusPara = Home:AddParagraph({
  Title = "Status",
  Content = "กำลังอ่านสถานะ..."
})

local function taskMark(name)
  return TaskMgr.isRunning(name) and "🟢" or "⚪"
end

local function refreshStatus()
  local lines = {
    string.format("%s AutoCollect",    taskMark("AutoCollect")),
    string.format("%s AutoFeed",       taskMark("AutoFeed")),
    string.format("%s AutoPlacePet",   taskMark("AutoPlacePet")),
    string.format("%s AutoCollectPet", taskMark("AutoCollectPet")),
    string.format("%s AutoHatch",      taskMark("AutoHatch")),
    string.format("%s AutoBuyEgg",     taskMark("AutoBuyEgg")),
    string.format("%s AutoBuyFood",    taskMark("AutoBuyFood")),
    string.format("%s AutoClaim",      taskMark("AutoClaim")),
    string.format("%s AutoLottery",    taskMark("AutoLottery")),
    string.format("%s AntiAFK",        taskMark("AntiAFK")),
  }
  StatusPara:SetDesc(table.concat(lines, "\n"))
end

Home:AddSection("Quick Actions")
Home:AddButton({
  Title = "เริ่ม Auto Collect",
  Description = "เปิดฟีเจอร์เก็บเงินสัตว์อัตโนมัติทันที",
  Callback = function()
    Options["AutoCollect"]:SetValue(true)
    Fluent:Notify({ Title = "Quick", Content = "เริ่ม Auto Collect", Duration = 3 })
  end
})
Home:AddButton({
  Title = "หยุดทุกงาน",
  Description = "หยุด Auto ทั้งหมดในคลิกเดียว",
  Callback = function()
    TaskMgr.stopAll()
    for _, key in ipairs({
      "AutoCollect","Auto Feed","Auto Place Pet","Auto Collect Pet",
      "Auto Hatch","Auto Egg","Auto Place Egg",
      "Auto BuyFood","Auto Claim Event Quest","Auto Lottery Ticket","AntiAFK"
    }) do pcall(function() Options[key]:SetValue(false) end) end
    refreshStatus()
    Fluent:Notify({ Title = "Quick", Content = "หยุดทุกงานแล้ว", Duration = 3 })
  end
})

Home:AddSection("Performance Presets")
Home:AddButton({
  Title = "Safe Mode (แนะนำสำหรับแช่)",
  Description = "ซ่อนโมเดล/เอฟเฟกต์ ปิด 3D และล็อก FPS เพื่อลื่น",
  Callback = function()
    Options["Hide Pets"]:SetValue(true)
    Options["Hide Eggs"]:SetValue(true)
    Options["Hide Effects"]:SetValue(true)
    Options["Disable3DOnly"]:SetValue(true)
    Options["FPS_Lock"]:SetValue(true)
    Options["FPS_Value"]:SetValue(30)
    Fluent:Notify({ Title = "Preset", Content = "เปิด Safe Mode เรียบร้อย", Duration = 4 })
  end
})

Home:AddButton({
  Title = "Visual Mode (ดูสวย เหมาะสกรีนช็อต)",
  Description = "เปิด 3D/แสดงทุกอย่าง ปลดล็อก FPS",
  Callback = function()
    Options["Hide Pets"]:SetValue(false)
    Options["Hide Eggs"]:SetValue(false)
    Options["Hide Effects"]:SetValue(false)
    Options["Disable3DOnly"]:SetValue(false)
    Options["FPS_Lock"]:SetValue(false)
    Fluent:Notify({ Title = "Preset", Content = "เปิด Visual Mode เรียบร้อย", Duration = 4 })
  end
})

-- ลบ Profiles ออก: (ProfileName / Save Profile / Load Profile) — ถูกถอดออก
-- ลบ Logs ออกทั้งหมด
-- ลบ Search Player ออกทั้งหมด

-- Helper: ล็อก input ของ Auto Place Pet (คงไว้)
local function SetInputsEnabled(ids, enabled)
  for _, id in ipairs(ids) do
    pcall(function()
      local opt = Options[id]
      if opt and opt.Instance and opt.Instance.SetLocked then
        opt.Instance:SetLocked(not enabled)
      end
    end)
  end
end
local placeSettingIds = {
  "PlacePet Area","PlacePet Mode","PlacePet Types",
  "PlacePet Mutations","AutoPlacePet Delay",
  "PlacePet_MinIncome","PlacePet_MaxIncome"
}
local function syncPlaceSettingsLock()
  local enabled = Configuration.Pet.AutoPlacePet == true
  SetInputsEnabled(placeSettingIds, enabled)
end
task.defer(syncPlaceSettingsLock)
task.spawn(function()
  local last = nil
  while RunningEnvirontments do
    if last ~= Configuration.Pet.AutoPlacePet then
      last = Configuration.Pet.AutoPlacePet
      syncPlaceSettingsLock()
    end
    task.wait(0.5)
  end
end)

-- Progress helper (ตัดการเขียน log ออก)
local function withProgress(title, runner)
  local ok, err = pcall(function()
    Fluent:Notify({ Title = title, Content = "เริ่มทำงาน…", Duration = 2 })
    runner(function(step, total)
      Fluent:Notify({ Title = title, Content = string.format("กำลังทำงาน %d/%d", step, total), Duration = 2 })
    end)
    Fluent:Notify({ Title = title, Content = "เสร็จสิ้น", Duration = 3 })
  end)
  if not ok then
    Fluent:Notify({ Title = title, Content = "ล้มเหลว: "..tostring(err), Duration = 5 })
  end
end

-- วนรีเฟรชสถานะไว้หน้า Home
task.spawn(function()
  while RunningEnvirontments do
    refreshStatus()
    task.wait(4)  -- เดิม 1.5 → 4 เพื่อลดโหลด UI
  end
end)

-- เปิด Home เป็นแท็บเริ่มต้น


-----------------------------------------------------------------
-- ================== END UX/UI (Simplified) =====================
-----------------------------------------------------------------


Window:SelectTab(Home)
Fluent:Notify({ Title = "Fluent", Content = "The script has been loaded.", Duration = 8 })
Perf_Set3DEnabled(not (Configuration.Perf.Disable3D == true))

SaveManager:LoadAutoloadConfig()
if Configuration.Perf.FPSLock or (getgenv().MEOWY_FPS and getgenv().MEOWY_FPS.locked) then
    if getgenv().MEOWY_FPS and getgenv().MEOWY_FPS.cap then
        Configuration.Perf.FPSValue = getgenv().MEOWY_FPS.cap
    end
    ApplyFPSLock()
end

getgenv().MeowyBuildAZoo = Window

--==============================================================
--              AUTO-START AFTER LOADAUTOCONFIG
--==============================================================
local function _autostart()
    if Configuration.AntiAFK then TaskMgr.start("AntiAFK", runAntiAFK) end
    if Configuration.Main.AutoCollect then TaskMgr.start("AutoCollect", runAutoCollect) end
    if Configuration.Pet.AutoFeed then TaskMgr.start("AutoFeed", runAutoFeed) end
    if Configuration.Pet.CollectPet_Auto then TaskMgr.start("AutoCollectPet", runAutoCollectPet) end
    if Configuration.Pet.AutoPlacePet then TaskMgr.start("AutoPlacePet", runAutoPlacePet) end
    if Configuration.Egg.AutoHatch then TaskMgr.start("AutoHatch", runAutoHatch) end
    if Configuration.Egg.AutoBuyEgg then TaskMgr.start("AutoBuyEgg", runAutoBuyEgg) end
    if Configuration.Egg.AutoPlaceEgg then TaskMgr.start("AutoPlaceEgg", runAutoPlaceEgg) end
    if Configuration.Shop.Food.AutoBuy then TaskMgr.start("AutoBuyFood", runAutoBuyFood) end
    if Configuration.Event.AutoClaim then TaskMgr.start("AutoClaim", runAutoClaim) end
    if Configuration.Event.AutoLottery then TaskMgr.start("AutoLottery", runAutoLottery) end
end
_autostart()

--==============================================================
--                        CLEANUP
--==============================================================
Window.Root.Destroying:Once(function()
    RunningEnvirontments = false
    TaskMgr.stopAll()
    ApplyHidePets(false); ApplyHideEggs(false); ApplyHideEffects(false); ApplyHideGameUI(false)
    if _setFPSCap and not (getgenv().MEOWY_FPS and getgenv().MEOWY_FPS.locked) then
        _setFPSCap(1000)
    end
    for _,connection in pairs(EnvirontmentConnections) do
        if connection then pcall(function() connection:Disconnect() end) end
    end
    Perf_Set3DEnabled(true)
end)

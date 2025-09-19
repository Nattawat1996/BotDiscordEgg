--==============================================================
-- Build A Zoo (PlaceId 105555311806207)
-- Reorganized + Optimized version (legacy-friendly place logic)
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
--==============================================================

-- ========= 1) Plot index cache + Occupied set (base index) =========
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

-- ======== helpers for plot key/area ========
local function _keyXZ(x,z) return ("%d,%d"):format(math.floor((x or 0)+0.5), math.floor((z or 0)+0.5)) end
local function _areaFromXZ(x, z) local n = PlotIndex[_keyXZ(x,z)]; return n and n.area or "Any" end

--==============================================================
--            FAST OCCUPANCY & UNLOCKED PLOTS (NEW)
--==============================================================
local OCC = { byKey = {}, count = 0 }  -- ["x,z"] -> true
local function _occ_set_xz(x, z, val)
    local k = _keyXZ(x, z)
    local had = OCC.byKey[k]
    if val then
        if not had then OCC.byKey[k] = true; OCC.count += 1 end
    else
        if had then OCC.byKey[k] = nil; OCC.count -= 1 end
    end
end
local function _occ_byDI(di, val)
    if not di then return end
    _occ_set_xz(di:GetAttribute("X") or 0, di:GetAttribute("Z") or 0, val)
end
local function RebuildOccupancy()
    OCC.byKey, OCC.count = {}, 0
    for _, petNode in ipairs(OwnedPetData:GetChildren()) do local di = petNode:FindFirstChild("DI"); if di then _occ_byDI(di, true) end end
    for _, eggNode in ipairs(OwnedEggData:GetChildren()) do local di = eggNode:FindFirstChild("DI"); if di then _occ_byDI(di, true) end end
end
RebuildOccupancy()

local function _watchDIUnder(node)
    if not node or not node:IsA("Folder") then return end
    table.insert(EnvirontmentConnections, node.ChildAdded:Connect(function(ch) if ch.Name == "DI" then _occ_byDI(ch, true) end end))
    table.insert(EnvirontmentConnections, node.ChildRemoved:Connect(function(ch) if ch.Name == "DI" then _occ_byDI(ch, false) end end))
    local di = node:FindFirstChild("DI"); if di then _occ_byDI(di, true) end
end
for _, n in ipairs(OwnedPetData:GetChildren()) do _watchDIUnder(n) end
for _, n in ipairs(OwnedEggData:GetChildren()) do _watchDIUnder(n) end
table.insert(EnvirontmentConnections, OwnedPetData.ChildAdded:Connect(_watchDIUnder))
table.insert(EnvirontmentConnections, OwnedEggData.ChildAdded:Connect(_watchDIUnder))

-- -------- Unlocked plots cache --------
local UnlockedPlots = { Any = {}, Land = {}, Water = {} }
local function _farmLockedRects()
    local rects = {}
    local ENV = Island:FindFirstChild("ENV")
    local Locks = ENV and ENV:FindFirstChild("Locks")
    if not Locks then return rects end
    for _, lockModel in ipairs(Locks:GetChildren()) do
        local farm = lockModel:FindFirstChild("Farm")
        if farm and farm:IsA("BasePart") and farm.Transparency == 0 then
            table.insert(rects, { cf = farm.CFrame, sz = farm.Size })
        end
    end
    return rects
end
local function _posInsideRect(cf, sz, worldPos)
    local rel = cf:PointToObjectSpace(worldPos)
    return (math.abs(rel.X) <= sz.X*0.5) and (math.abs(rel.Z) <= sz.Z*0.5)
end
local function RebuildUnlockedPlots()
    local rects = _farmLockedRects()
    local function isLocked(part)
        for _, r in ipairs(rects) do if _posInsideRect(r.cf, r.sz, part.Position) then return true end end
        return false
    end
    UnlockedPlots.Any, UnlockedPlots.Land, UnlockedPlots.Water = {}, {}, {}
    for _, p in ipairs(SortedPlots.Any) do
        if not isLocked(p) then
            table.insert(UnlockedPlots.Any, p)
            local area = (p.Name:match("^Water") and "Water") or "Land"
            table.insert(UnlockedPlots[area], p)
        end
    end
end
RebuildUnlockedPlots()
local locks = Island:FindFirstChild("ENV") and Island.ENV:FindFirstChild("Locks")
if locks then
    table.insert(EnvirontmentConnections, locks.ChildAdded:Connect(function() task.defer(RebuildUnlockedPlots) end))
    table.insert(EnvirontmentConnections, locks.ChildRemoved:Connect(function() task.defer(RebuildUnlockedPlots) end))
end

-- แทนที่ฟังก์ชัน GetFreeFarmParts เดิมทั้งหมด
local function GetFreeFarmParts(area)
    -- รายการหลัก: ใช้รายการปลดล็อกก่อน
    local list = (area == "Land" and UnlockedPlots.Land)
              or (area == "Water" and UnlockedPlots.Water)
              or UnlockedPlots.Any

    -- Fallback: ถ้า Land/Water ว่าง ให้ใช้รายการดิบทั้งหมด (ไม่สนล็อกชั่วคราว)
    if (area == "Land" or area == "Water") and (#list == 0) then
        dprint("GetFreeFarmParts: unlocked list empty for", area, "-> fallback to SortedPlots")
        list = (area == "Land" and SortedPlots.Land)
            or (area == "Water" and SortedPlots.Water)
            or SortedPlots.Any
    end

    -- กรองเฉพาะช่องที่ยังไม่ถูกจับจอง (ใช้ OCC เป็นหลัก)
    local res = {}
    for _, part in ipairs(list) do
        local ic = part:GetAttribute("IslandCoord")
        local k = ic and _keyXZ(ic.X, ic.Z)
        if not (k and OCC.byKey[k]) then
            res[#res+1] = part
        end
    end
    dprint("GetFreeFarmParts:", area, "free =", #res)
    return res
end


--==============================================================
--                      HELPERS
--==============================================================
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

-- Proximity fallback (ยังคงไว้ใช้ระยะจำเป็น)
local function IsOccupiedAtPosition(pos: Vector3, radius: number?)
    local R = radius or 5
    for _, P in ipairs(Pet_Folder:GetChildren()) do
        local rp = anchorOf(P); if rp and (rp.Position - pos).Magnitude <= R then return true end
    end
    for _, child in ipairs(BlockFolder:GetChildren()) do
        local rp = anchorOf(child); if rp and (rp.Position - pos).Magnitude <= R then return true end
    end
    for _, E in ipairs(OwnedEggData:GetChildren()) do
        local di = E:FindFirstChild("DI")
        if di then
            local v = Vector3.new(di:GetAttribute("X") or 0, di:GetAttribute("Y") or 0, di:GetAttribute("Z") or 0)
            if (v - pos).Magnitude <= R then return true end
        end
    end
    return false
end

-- ensureNear (OP: วาร์ปเฉพาะไกลจริง)
local PLACE_WARP_THRESHOLD = 35
local function ensureNear(position)
    local char = Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if (root.Position - position).Magnitude > PLACE_WARP_THRESHOLD then
        dprint("Teleporting (distance too far) ->", _tos(position))
        root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
        task.wait(0.12)
    end
end

local function _toggleWhiteOverlay(show)
    local pg = Player:FindFirstChild("PlayerGui")
    if not pg then return end
    local gui = pg:FindFirstChild("PerfWhite") or Instance.new("ScreenGui")
    if not gui.Parent then
        gui.Name = "PerfWhite"; gui.IgnoreGuiInset = true; gui.DisplayOrder = 1e9; gui.ResetOnSpawn = false; gui.Parent = pg
        local f = Instance.new("Frame"); f.Name = "F"; f.Size = UDim2.fromScale(1,1); f.BackgroundColor3 = Color3.new(1,1,1); f.BackgroundTransparency = 0; f.Parent = gui
    end
    local frame = gui:FindFirstChild("F")
    if frame then frame.BackgroundTransparency = show and 0 or 1 end
    gui.Enabled = show
end

local function Perf_Set3DEnabled(enable3D)
    local ok = pcall(function() RunService:Set3dRenderingEnabled(enable3D) end)
    if ok then _toggleWhiteOverlay(false) else _toggleWhiteOverlay(not enable3D) end
end

local function GetCash(TXT) if not TXT then return 0 end local cash = string.gsub(TXT,"[$,]","") return tonumber(cash) or 0 end
local function SellEgg(uid) if not uid or uid == "" then return false, "no uid" end CharacterRE:FireServer("Focus", uid) task.wait(0.1) local ok, err = pcall(function() PetRE:FireServer("Sell", uid, true) end) CharacterRE:FireServer("Focus") return ok, err end
local function SellPet(uid) if not uid or uid == "" then return false, "no uid" end CharacterRE:FireServer("Focus", uid) task.wait(0.1) local ok, err = pcall(function() PetRE:FireServer("Sell", uid) end) CharacterRE:FireServer("Focus") return ok, err end

-- Occupancy check (ใช้ OCC ก่อน, ตกเหลือค่อย proximity)
local function isFarmTileOccupied(farmPart, minDistance)
    local ic = farmPart:GetAttribute("IslandCoord")
    if ic then
        local k = _keyXZ(ic.X, ic.Z)
        if OCC.byKey[k] then return true end
    end
    return IsOccupiedAtPosition(farmPart.Position, (minDistance or 4) + 0.1)
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
        Egg_Belt[eggUID] = { UID = eggUID, Mutate = (egg:GetAttribute("M") or "None"), Type = (egg:GetAttribute("T") or "BasicEgg") }
    end
end))
for _,egg in pairs(Egg_Belt_Folder:GetChildren()) do
    task.spawn(pcall,function()
        local eggUID = tostring(egg) or "None"
        if egg then
            Egg_Belt[eggUID] = { UID = eggUID, Mutate = (egg:GetAttribute("M") or "None"), Type = (egg:GetAttribute("T") or "BasicEgg") }
        end
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
        local cf   = idle and (idle:FindFirstChild("CashF") or idle:FindFirstChildWhichIsA("Frame", true))
        local txt  = cf and (cf:FindFirstChild("TXT")   or cf:FindFirstChildWhichIsA("TextLabel", true))
        _cashTxtRef = txt
        return txt
    end
    local diNode = OwnedPetData:FindFirstChild(petUID); diNode = diNode and diNode:FindFirstChild("DI")
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
                return (root and root:GetAttribute("ProduceSpeed")) or 0
            end
            return rawget(tb, ind)
        end
    })
end
table.insert(EnvirontmentConnections, Pet_Folder.ChildAdded:Connect(function(pet)
    task.delay(0.1, function() local uid = tostring(pet); if pet and uid then _buildOwnedPetEntry(pet, uid) end end)
end))
for _,pet in pairs(Pet_Folder:GetChildren()) do
    task.spawn(function() local uid = tostring(pet); if pet and uid then _buildOwnedPetEntry(pet, uid) end end)
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
    for _,fn in ipairs(cands) do if type(fn) == "function" then return fn end end
    return nil
end
local _setFPSCap = _pick_fps_setter()

local G2 = getgenv()
G2.MEOWY_FPS = G2.MEOWY_FPS or { locked = false, cap = 60 }
local function _notify(t, m) pcall(function() Fluent:Notify({ Title = t, Content = m, Duration = 5 }) end); print("[Perf] "..t..": "..m) end
local function ApplyFPSLock()
    if not _setFPSCap then _notify("FPS", "Executor ไม่รองรับ setfpscap"); return end
    if Configuration.Perf.FPSLock then
        local cap = math.max(5, math.floor(tonumber(Configuration.Perf.FPSValue) or 60))
        G2.MEOWY_FPS.locked = true; G2.MEOWY_FPS.cap = cap
        _setFPSCap(cap); _notify("FPS Locked", tostring(cap))
    else
        G2.MEOWY_FPS.locked = false
        _setFPSCap(1000); _notify("FPS", "Unlock")
    end
end

--== Hide caches & toggles (เหมือนเดิม)
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
            _setPartVisible(d, visible); d.CastShadow = visible and d.CastShadow or false
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
            local prev = _particlePrev[inst]; if prev ~= nil then inst.Rate = prev; _particlePrev[inst] = nil end
        else
            if _particlePrev[inst] == nil then _particlePrev[inst] = inst.Rate end
            inst.Rate = 0
        end
    elseif inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("Highlight") then
        if enable then if _togglePrev[inst] ~= nil then inst.Enabled = _togglePrev[inst]; _togglePrev[inst] = nil end
        else if _togglePrev[inst] == nil then _togglePrev[inst] = inst.Enabled end; inst.Enabled = false end
    elseif inst:IsA("Explosion") then pcall(function() inst.Visible = enable end)
    end
end
local function ApplyHideEffects(on)
    for _,d in ipairs(workspace:GetDescendants()) do _applyEffectInst(d, not on) end
    if _effectsConn then _effectsConn:Disconnect(); _effectsConn = nil end
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

----------------------------------------------------------------
-- ============ AUTOPLACE CORE (Filters + Place) ===============
----------------------------------------------------------------
local CollectionService = game:GetService("CollectionService")

local function getIslandNumberFromName(islandName)
    if not islandName then return nil end
    local match = islandName:match("Island_(%d+)")
    if match then return tonumber(match) end
    match = islandName:match("(%d+)")
    if match then return tonumber(match) end
    return nil
end

local function isEggLikeModel(model)
    if not model or not model:IsA("Model") then return false end
    if model:FindFirstChild("RF", true) then return true end
    if OwnedEggData:FindFirstChild(model.Name) then return true end
    if model:GetAttribute("T") and not model:FindFirstChildOfClass("Humanoid") then return true end
    local n = string.lower(model.Name or "")
    if n:find("egg") or n:find("hatch") then return true end
    return false
end

local function isPetLikeModel(model)
    if not model or not model:IsA("Model") then return false end
    if model:FindFirstChildOfClass("Humanoid") then return true end
    if model:FindFirstChild("AnimationController") then return true end
    if model:GetAttribute("IsPet") or model:GetAttribute("PetType") or model:GetAttribute("T") then return true end
    local lowerName = string.lower(model.Name)
    if string.find(lowerName, "pet") or string.find(lowerName, "egg") then return true end
    if CollectionService and (CollectionService:HasTag(model, "Pet") or CollectionService:HasTag(model, "IdleBigPet")) then return true end
    return false
end

local function getPlayerRootPosition()
    return Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") and Player.Character.HumanoidRootPart.Position
end

local function findAvailableFarmPartNearPosition(farmParts, minDistance, targetPosition)
    if not farmParts or #farmParts == 0 then return nil end
    if not targetPosition then
        for _, part in ipairs(farmParts) do
            if not isFarmTileOccupied(part, minDistance) then return part end
        end
        return nil
    end
    local best, bestDist = nil, math.huge
    for _, part in ipairs(farmParts) do
        if not isFarmTileOccupied(part, minDistance) then
            local d = (part.Position - targetPosition).Magnitude
            if d < bestDist then best, bestDist = part, d end
        end
    end
    return best
end

local function getUnplacedEggUIDs()
    local uids = {}
    for _, eggNode in ipairs(OwnedEggData:GetChildren()) do
        if not eggNode:FindFirstChild("DI") then table.insert(uids, eggNode.Name) end
    end
    return uids
end

local function getUnplacedPetUIDs()
    local uids = {}
    local petsInWorkspace = workspace:FindFirstChild("Pets"); if not petsInWorkspace then return uids end
    for _, petNode in ipairs(OwnedPetData:GetChildren()) do
        if not petsInWorkspace:FindFirstChild(petNode.Name) then table.insert(uids, petNode.Name) end
    end
    return uids
end

-- ==== Income cache (OP) ====
local _INV_CACHE = { v = {}, t = {} }
local _INV_TTL = 15
function GetInventoryIncomePerSecByUID(uid)
    if not uid or uid == "" then return 0 end
    local now = os.clock()
    local last = _INV_CACHE.t[uid] or 0
    if now - last < _INV_TTL then return _INV_CACHE.v[uid] or 0 end

    local pg = Player:FindFirstChild("PlayerGui"); if not pg then return 0 end
    local screenStorage = pg:FindFirstChild("ScreenStorage"); if not screenStorage then return 0 end
    local frame = screenStorage:FindFirstChild("Frame"); if not frame then return 0 end
    local contentPet = frame:FindFirstChild("ContentPet"); if not contentPet then return 0 end
    local scrolling = contentPet:FindFirstChild("ScrollingFrame"); if not scrolling then return 0 end

    local item = scrolling:FindFirstChild(uid)
    if not item then for _, ch in ipairs(scrolling:GetChildren()) do if ch.Name == uid then item = ch break end end end
    if not item then _INV_CACHE.t[uid] = now; _INV_CACHE.v[uid] = 0; return 0 end

    local btn  = item:FindFirstChild("BTN") or item:FindFirstChildWhichIsA("Frame")
    if not btn then _INV_CACHE.t[uid] = now; _INV_CACHE.v[uid] = 0; return 0 end
    local stat = btn:FindFirstChild("Stat") or btn:FindFirstChildWhichIsA("Frame")
    if not stat then _INV_CACHE.t[uid] = now; _INV_CACHE.v[uid] = 0; return 0 end
    local price = stat:FindFirstChild("Price") or stat:FindFirstChildWhichIsA("Frame")
    if not price then _INV_CACHE.t[uid] = now; _INV_CACHE.v[uid] = 0; return 0 end

    local val = 0
    local valueObj = price:FindFirstChild("Value")
    if valueObj then
        if valueObj:IsA("NumberValue") or valueObj:IsA("IntValue") then
            val = tonumber(valueObj.Value) or 0
        elseif valueObj:IsA("StringValue") then
            local s = tostring(valueObj.Value or ""); val = tonumber((s:gsub("[^%d%.]", ""))) or 0
        end
    end
    local function readNumberFrom(inst)
        local ok, txt = pcall(function() return inst.Text end)
        if ok and txt then
            local n = tonumber((tostring(txt):gsub("[^%d%.]",""))); if n then return n end
        end
        return nil
    end
    if val == 0 then
        local textLike = price:FindFirstChildWhichIsA("TextLabel") or price:FindFirstChildWhichIsA("TextButton")
        if textLike then val = readNumberFrom(textLike) or 0 end
        if val == 0 then
            for _, d in ipairs(price:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("TextButton") then val = readNumberFrom(d) or 0; if val > 0 then break end end
            end
        end
    end
    _INV_CACHE.t[uid] = now; _INV_CACHE.v[uid] = val
    return val
end

-- (Core) filters
local function filterEggs(eggUIDs)
    local filtered = {}
    local types = Configuration.Egg.Types or {}
    local mutations = Configuration.Egg.Mutations or {}
    for _, uid in ipairs(eggUIDs) do
        local eggNode = OwnedEggData:FindFirstChild(uid)
        if eggNode then
            local eggType = eggNode:GetAttribute("T") or "BasicEgg"
            local eggMuta = eggNode:GetAttribute("M") or "None"
            if types[eggType] and mutations[eggMuta] then table.insert(filtered, uid) end
        end
    end
    return filtered
end
local function filterPets(petUIDs)
    local filtered = {}
    local mode = Configuration.Pet.PlacePet_Mode or "All"
    if mode == "All" then return petUIDs end
    for _, uid in ipairs(petUIDs) do
        local petNode = OwnedPetData:FindFirstChild(uid)
        if petNode then
            if mode == "Match" then
                local pType = petNode:GetAttribute("T")
                local pMuta = petNode:GetAttribute("M") or "None"
                if Configuration.Pet.PlacePet_Types[pType] and Configuration.Pet.PlacePet_Mutations[pMuta] then
                    table.insert(filtered, uid)
                end
            elseif mode == "Range" then
                local income = GetInventoryIncomePerSecByUID(uid)
                local minInc = Configuration.Pet.PlacePet_Between.Min or 0
                local maxInc = Configuration.Pet.PlacePet_Between.Max or math.huge
                if income >= minInc and income <= maxInc then table.insert(filtered, uid) end
            end
        end
    end
    return filtered
end

-- placeItem (ใช้อัตโนมัติวาร์ปแบบฉลาด)
local function placeItem(uid, tilePart)
    if not uid or not tilePart then return false end
    local dst = tilePart.Position
    ensureNear(dst)
    CharacterRE:FireServer("Focus", uid); task.wait(0.5)
    dprint("Attempting to place", uid, "at", dst)
    CharacterRE:FireServer("Place", { DST = Vector3.new(dst.X, dst.Y, dst.Z), ID = uid })
    task.wait(0.2)
    CharacterRE:FireServer("Focus")
    return true
end

--============================== RUNNERS (บางส่วน) ==============================
local function runAntiAFK(tok)
    local VirtualUser = game:GetService("VirtualUser")
    while tok.alive do
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        if not _waitAlive(tok, 30) then break end
    end
end

local function runAutoCollect(tok)
    while tok.alive do
        local claimed = 0
        for _, pet in pairs(OwnedPets) do
            if not tok.alive then break end
            local RE = pet and pet.RE
            if RE then
                RE:FireServer("Claim"); claimed += 1
                if claimed % 10 == 0 then task.wait() end
            end
        end
        if not _waitAlive(tok, tonumber(Configuration.Main.Collect_Delay) or 3) then break end
    end
end

-- === Feed helper ===
local function _cloneFoodMap(t)
    local m = {}
    if type(t) == "table" then
        if rawget(t, 1) ~= nil then for _, v in ipairs(t) do m[tostring(v)] = true end
        else for k, v in pairs(t) do if v then m[tostring(k)] = true end end end
    end
    return m
end
local function pickFoodPerPet(uid, invAttrs)
    local per = Configuration.Pet.AutoFeed_PetFoods and Configuration.Pet.AutoFeed_PetFoods[uid]
    if type(per) ~= "table" then return nil end
    local allow = {}
    if rawget(per, 1) ~= nil then for _, v in ipairs(per) do allow[tostring(v)] = true end
    else for k, on in pairs(per) do if on then allow[tostring(k)] = true end end end
    for _, name in ipairs(PetFoods_InGame) do
        local have = tonumber(invAttrs[name] or 0) or 0
        if allow[name] and have > 0 then return name end
    end
    return nil
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

local function eggArea(eggInst)
    if not eggInst then return "Any" end
    local di = eggInst:FindFirstChild("DI")
    if not di then return "Any" end
    return _areaFromXZ(di:GetAttribute("X") or 0, di:GetAttribute("Z") or 0)
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

-- ===== AutoPlace (ใช้ GetFreeFarmParts + OCC lock ทันที) =====
local function runAutoPlaceEgg(tok)
    while tok.alive do
        local uidsToPlace = getUnplacedEggUIDs()
        local filteredUIDs = filterEggs(uidsToPlace)

        if #filteredUIDs > 0 then
            local area = Configuration.Egg.PlaceArea or "Any"
            local availableFarmParts = GetFreeFarmParts(area)

            for _, uid in ipairs(filteredUIDs) do
                if not tok.alive or #availableFarmParts == 0 then break end
                local partToTry = findAvailableFarmPartNearPosition(availableFarmParts, 4, getPlayerRootPosition())
                if partToTry then
                    local ic = partToTry:GetAttribute("IslandCoord")
                    local lockKey = ic and _keyXZ(ic.X, ic.Z)
                    if lockKey then OCC.byKey[lockKey] = true end
                    placeItem(uid, partToTry)

                    local idx = table.find(availableFarmParts, partToTry)
                    if idx then table.remove(availableFarmParts, idx) end

                    dprint("Waiting for egg data confirmation for:", uid)
                    local eggNode = OwnedEggData:FindFirstChild(uid)
                    local ok = false
                    if eggNode then ok = eggNode:WaitForChild("DI", 2) ~= nil end
                    if not ok and lockKey then OCC.byKey[lockKey] = nil end
                    task.wait(0.2)
                else
                    dprint("AutoPlaceEgg: No more available parts found.")
                    break
                end
            end
        end

        if not _waitAlive(tok, tonumber(Configuration.Egg.AutoPlaceEgg_Delay) or 1) then break end
    end
end

local function runAutoPlacePet(tok)
    while tok.alive do
        local uidsToPlace = getUnplacedPetUIDs()
        local filteredUIDs = filterPets(uidsToPlace)
        dprint("AutoPlacePet: candidates=", #uidsToPlace, "after filter=", #filteredUIDs)
        if #filteredUIDs > 1 then
            table.sort(filteredUIDs, function(a,b)
                return (GetInventoryIncomePerSecByUID(a) or 0) > (GetInventoryIncomePerSecByUID(b) or 0)
            end)
        end

        if #filteredUIDs > 0 then
            local area = Configuration.Pet.PlaceArea or "Any"
            local availableFarmParts = GetFreeFarmParts(area)
            if #availableFarmParts == 0 then
                dprint("AutoPlacePet: no free tiles → rebuilding unlocks")
                RebuildUnlockedPlots()
                availableFarmParts = GetFreeFarmParts(area)
            end
            for _, uid in ipairs(filteredUIDs) do
                if not tok.alive or #availableFarmParts == 0 then break end
                local partToTry = findAvailableFarmPartNearPosition(availableFarmParts, 4, getPlayerRootPosition())
                if partToTry then
                    local ic = partToTry:GetAttribute("IslandCoord")
                    local lockKey = ic and _keyXZ(ic.X, ic.Z)
                    if lockKey then OCC.byKey[lockKey] = true end
                    placeItem(uid, partToTry)

                    local idx = table.find(availableFarmParts, partToTry)
                    if idx then table.remove(availableFarmParts, idx) end

                    dprint("Waiting for pet model confirmation for:", uid)
                    local petModel = Pet_Folder:WaitForChild(uid, 3)
                    if not petModel and lockKey then OCC.byKey[lockKey] = nil 
                    else dprint("Placed:", uid) end
                    task.wait(0.2)
                else
                    dprint("AutoPlacePet: No more available parts found.")
                    break
                end
            end
        end

        if not _waitAlive(tok, tonumber(Configuration.Pet.AutoPlacePet_Delay) or 1) then break end
    end
end

--============================== UI ==============================
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
Tabs.Main:AddInput("FPS_Value", { Title = "FPS Cap (ใส่ตัวเลขแล้วกด Enter)", Default = tostring(Configuration.Perf.FPSValue), Numeric = true, Finished = true, Callback = function(v)
    Configuration.Perf.FPSValue = tonumber(v) or 60; if Configuration.Perf.FPSLock then ApplyFPSLock() end
end })
Tabs.Main:AddToggle("Hide Pets", { Title = "ซ่อนโมเดลสัตว์ทั้งหมด", Default = false, Callback = function(v)
    Configuration.Perf.HidePets = v; ApplyHidePets(v)
end })
Tabs.Main:AddToggle("Hide Eggs", { Title = "ซ่อนโมเดลไข่ (ของตนเอง)", Default = false, Callback = function(v)
    Configuration.Perf.HideEggs = v; ApplyHideEggs(v)
end })
Tabs.Main:AddToggle("Hide Effects", { Title = "ปิด Effects (Particle/Beam/Trail/Highlight)", Default = false, Callback = function(v)
    Configuration.Perf.HideEffects = v; ApplyHideEffects(v)
end })
Tabs.Main:AddToggle("Hide Game UI", { Title = "ซ่อน UI ของเกม (เว้นแผงนี้)", Default = false, Callback = function(v)
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
Tabs.Pet:AddToggle("Auto Place Pet",{ Title="Auto Place Pet", Default=false, Callback=function(v)
    Configuration.Pet.AutoPlacePet = v
    if v then TaskMgr.start("AutoPlacePet", runAutoPlacePet) else TaskMgr.stop("AutoPlacePet") end
end })

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
                    local function passArea(uid) if areaWant == "Any" then return true end return petArea(uid) == areaWant end
                    if CollectType == "All" then
                        for UID, PetData in pairs(OwnedPets) do
                            if PetData and not PetData.IsBig and passArea(UID) then if PetData.RE then PetData.RE:FireServer("Claim") end; CharacterRE:FireServer("Del", UID) end
                        end
                    elseif CollectType == "Match Pet" then
                        for UID, PetData in pairs(OwnedPets) do
                            if PetData and not PetData.IsBig and passArea(UID) and Configuration.Pet.CollectPet_Pets[PetData.Type] then
                                if PetData.RE then PetData.RE:FireServer("Claim") end; CharacterRE:FireServer("Del", UID)
                            end
                        end
                    elseif CollectType == "Match Mutation" then
                        for UID, PetData in pairs(OwnedPets) do
                            if PetData and not PetData.IsBig and passArea(UID) and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                                if PetData.RE then PetData.RE:FireServer("Claim") end; CharacterRE:FireServer("Del", UID)
                            end
                        end
                    elseif CollectType == "Match Pet&Mutation" then
                        for UID, PetData in pairs(OwnedPets) do
                            if PetData and not PetData.IsBig and passArea(UID)
                               and Configuration.Pet.CollectPet_Pets[PetData.Type]
                               and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                                if PetData.RE then PetData.RE:FireServer("Claim") end; CharacterRE:FireServer("Del", UID)
                            end
                        end
                    elseif CollectType == "Range" then
                        local minV = tonumber(Configuration.Pet.CollectPet_Between.Min) or 0
                        local maxV = tonumber(Configuration.Pet.CollectPet_Between.Max) or math.huge
                        for UID, PetData in pairs(OwnedPets) do
                            if PetData and not PetData.IsBig and passArea(UID) then
                                local ps = tonumber(PetData.ProduceSpeed) or 0
                                if ps >= minV and ps <= maxV then if PetData.RE then PetData.RE:FireServer("Claim") end; CharacterRE:FireServer("Del", UID) end
                            end
                        end
                    end
                end },
                { Title = "No", Callback = function() end }
            }
        })
    end
})

--==== Per-pet foods UI (เหมือนเดิม) ====
local BigPetUIDLabels = {}
local function labelForBigPet(uid, P) return string.format("[%s|%s] %s", tostring(P and P.Type or "?"), tostring(P and P.Mutate or "None"), tostring(uid)) end
local function labelToUID(v) if type(v) ~= "string" then return v end if BigPetUIDLabels and BigPetUIDLabels[v] then return BigPetUIDLabels[v] end local uid = v:match("%]%s+(.+)$"); return uid or v end

PickPetForFoodDD = Tabs.Pet:AddDropdown("PickPet ForFood", {
    Title = "Pick Big Pet (set foods for this pet)",
    Values = {}, Multi = false, Default = "",
    Callback = function(label) Configuration.Pet._PickPetForFood = labelToUID(label or "") end
})
local PickFoodsForPetDD = Tabs.Pet:AddDropdown("PickFoods ForOnePet", {
    Title = "Foods allowed for selected pet",
    Description = "เลือกชนิดอาหารที่จะอนุญาตให้สัตว์ตัวนี้กิน (จะพยายามใช้ตามสต็อก)",
    Values = PetFoods_InGame, Multi = true, Default = {},
    Callback = function(v) Configuration.Pet._PickFoodsDraft = v end
})
Tabs.Pet:AddButton({
    Title = "Save foods to this pet",
    Description = "บันทึกชุดอาหารให้กับ Big Pet ที่เลือก (UID)",
    Callback = function()
        local uid   = Configuration.Pet._PickPetForFood
        local draft = Configuration.Pet._PickFoodsDraft
        if not uid or uid == "" then Fluent:Notify({ Title="Per-Pet Food", Content="กรุณาเลือก Big Pet ก่อน", Duration=4 }); return end
        if type(draft) ~= "table" or next(draft) == nil then Fluent:Notify({ Title="Per-Pet Food", Content="ยังไม่ได้เลือกชนิดอาหาร", Duration=4 }); return end
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
Tabs.Pet:AddToggle("Use Per-Pet Foods", { Title = "Use per-pet foods first", Default = true, Callback = function(v) Configuration.Pet.AutoFeed_UsePerPet = v end })

local function updateBigPetUIDDropdowns()
    local labels = {}; BigPetUIDLabels = {}
    for uid, P in pairs(OwnedPets) do
        if P and P.IsBig then local label = labelForBigPet(uid, P); BigPetUIDLabels[label] = uid; table.insert(labels, label) end
    end
    pcall(function() Options["Pet Feed_Targets"]:SetValues(labels) end)
    if PickPetForFoodDD then pcall(function() PickPetForFoodDD:SetValues(labels) end) end
end
table.insert(EnvirontmentConnections, Pet_Folder.ChildAdded:Connect(function() task.delay(0.2, updateBigPetUIDDropdowns) end))
table.insert(EnvirontmentConnections, Pet_Folder.ChildRemoved:Connect(function() task.delay(0.2, updateBigPetUIDDropdowns) end))
task.defer(updateBigPetUIDDropdowns)

local FeedTargetsDD = Tabs.Pet:AddDropdown("Pet Feed_Targets", {
    Title = "Select Big Pets to Feed",
    Description = "เลือกเฉพาะ Big Pets ที่จะให้อาหาร (เว้นว่าง = ให้อาหาร Big ทุกตัว)",
    Values = {}, Multi = true, Default = {},
    Callback = function(selected)
        local uidSet = {}
        if type(selected) == "table" then
            for k, on in pairs(selected) do if on then uidSet[labelToUID(k)] = true end end
        elseif type(selected) == "string" and selected ~= "" then uidSet[labelToUID(selected)] = true end
        Configuration.Pet.AutoFeed_Pets = uidSet
    end
})

Tabs.Pet:AddDropdown("CollectPet Type",{ Title = "Collect Pet Type", Values = {"All","Match Pet","Match Mutation","Match Pet&Mutation","Range"}, Multi = false, Default = "All", Callback = function(v) Configuration.Pet.CollectPet_Type = v end })
Tabs.Pet:AddDropdown("CollectPet Area",{ Title = "Collect Pet Area", Values = {"Any","Land","Water"}, Multi = false, Default = "Any", Callback = function(v) Configuration.Pet.CollectPet_Area = v end })
Tabs.Pet:AddDropdown("CollectPet Pets",{ Title = "Collect Pets", Values = Pets_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.CollectPet_Pets = v end })
Tabs.Pet:AddDropdown("CollectPet Mutations",{ Title = "Collect Mutations", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.CollectPet_Mutations = v end })
Tabs.Pet:AddInput("CollectCash_Num1",{ Title = "Min Coin", Default = 100000, Numeric = true, Finished = false, Callback = function(v) Configuration.Pet.CollectPet_Between.Min = tonumber(v) end })
Tabs.Pet:AddInput("CollectCash_Num2",{ Title = "Max Coin", Default = 1000000, Numeric = true, Finished = false, Callback = function(v) Configuration.Pet.CollectPet_Between.Max = tonumber(v) end })

-- ====== Pet > Auto Place Pet Settings ======
Tabs.Pet:AddSection("Auto Place Pet Settings")
Tabs.Pet:AddDropdown("PlacePet Area", { Title = "Place Area (Pet)", Values = {"Any","Land","Water"}, Multi = false, Default = "Any", Callback = function(v) Configuration.Pet.PlaceArea = v end })
Tabs.Pet:AddDropdown("PlacePet Mode", { Title = "Place Mode", Values = {"All","Match","Range"}, Multi = false, Default = "All", Callback = function(v) Configuration.Pet.PlacePet_Mode = v end })
Tabs.Pet:AddDropdown("PlacePet Types", { Title = "Place Types (Match)", Values = Pets_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.PlacePet_Types = v end })
Tabs.Pet:AddDropdown("PlacePet Mutations", { Title = "Place Mutations (Match)", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.PlacePet_Mutations = v end })
Tabs.Pet:AddSlider("AutoPlacePet Delay", { Title = "Auto Place Pet Delay", Description = "ดีเลย์การพยายามวางสัตว์ในแต่ละครั้ง (วิ)", Default = 1, Min = 0.1, Max = 5, Rounding = 1, Callback = function(v) Configuration.Pet.AutoPlacePet_Delay = v end })
Tabs.Pet:AddInput("PlacePet_MinIncome", { Title = "Min income/s (Range)", Default = tostring(Configuration.Pet.PlacePet_Between.Min or 0), Numeric = true, Finished = true, Callback = function(v) Configuration.Pet.PlacePet_Between.Min = tonumber(v) or 0 end })
Tabs.Pet:AddInput("PlacePet_MaxIncome", { Title = "Max income/s (Range)", Default = tostring(Configuration.Pet.PlacePet_Between.Max or 1000000), Numeric = true, Finished = true, Callback = function(v) Configuration.Pet.PlacePet_Between.Max = tonumber(v) or math.huge end })
--============================== Egg ==============================
Tabs.Egg:AddSection("Main")
Tabs.Egg:AddToggle("Auto Hatch",{ Title="Auto Hatch", Default=false, Callback=function(v)
    Configuration.Egg.AutoHatch = v
    if v then TaskMgr.start("AutoHatch", function(tok)
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
    end) else TaskMgr.stop("AutoHatch") end
end })
Tabs.Egg:AddToggle("Auto Egg",{ Title="Auto Buy Egg", Default=false, Callback=function(v)
    Configuration.Egg.AutoBuyEgg = v
    if v then TaskMgr.start("AutoBuyEgg", function(tok)
        local RE = GameRemoteEvents:WaitForChild("CharacterRE",30)
        local function currentCoin()
            local asset = InventoryData or Data:FindFirstChild("Asset")
            if not asset then return 0 end
            return tonumber(asset:GetAttribute("Coin") or 0) or 0
        end
        while tok.alive do
            local coinOk = (not Configuration.Egg.CheckMinCoin)
                or (currentCoin() >= (tonumber(Configuration.Egg.MinCoin) or 0))
            if coinOk then
                for _,egg in pairs(Egg_Belt) do
                    if not tok.alive then break end
                    local EggType = egg.Type
                    local EggMutation = egg.Mutate
                    if (Configuration.Egg.Types[EggType]) and (Configuration.Egg.Mutations[EggMutation]) then
                        if RE then RE:FireServer("BuyEgg", egg.UID) end
                    end
                end
            end
            if not _waitAlive(tok, tonumber(Configuration.Egg.AutoBuyEgg_Delay) or 1) then break end
        end
    end) else TaskMgr.stop("AutoBuyEgg") end
end })
Tabs.Egg:AddToggle("Auto Place Egg",{ Title="Auto Place Egg", Default=false, Callback=function(v)
    Configuration.Egg.AutoPlaceEgg = v
    if v then TaskMgr.start("AutoPlaceEgg", runAutoPlaceEgg) else TaskMgr.stop("AutoPlaceEgg") end
end })
Tabs.Egg:AddToggle("CheckMinCoin",{ Title = "Check Min Coin", Default = false, Callback = function(v) Configuration.Egg.CheckMinCoin = v end })

Tabs.Egg:AddSection("Settings")
Tabs.Egg:AddDropdown("Hatch Area",{ Title = "Hatch Area", Values = {"Any","Land","Water"}, Multi = false, Default = "Any", Callback = function(v) Configuration.Egg.HatchArea = v end })
Tabs.Egg:AddSlider("AutoHatch Delay",{ Title = "Hatch Delay", Default = 15, Min = 15, Max = 60, Rounding = 0, Callback = function(v) Configuration.Egg.Hatch_Delay = v end })
Tabs.Egg:AddSlider("AutoBuyEgg Delay",{ Title = "Auto Buy Egg Delay", Default = 1, Min = 0.1, Max = 3, Rounding = 1, Callback = function(v) Configuration.Egg.AutoBuyEgg_Delay = v end })
Tabs.Egg:AddSlider("AutoPlaceEgg Delay",{ Title = "Auto Place Egg Delay", Default = 1, Min = 0.1, Max = 5, Rounding = 1, Callback = function(v) Configuration.Egg.AutoPlaceEgg_Delay = v end })
Tabs.Egg:AddDropdown("PlaceEgg Area", { Title = "Place Area (Egg)", Values = {"Any","Land","Water"}, Multi = false, Default = "Any", Callback = function(v) Configuration.Egg.PlaceArea = v end })
Tabs.Egg:AddDropdown("Egg Type", { Title = "Types", Values = Eggs_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Egg.Types = v end })
Tabs.Egg:AddDropdown("Egg Mutations", { Title = "Mutations", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Egg.Mutations = v end })
Tabs.Egg:AddInput("Min Coin to Buy", { Title = "Min Coin", Default = tostring(Configuration.Egg.MinCoin or 0), Numeric = true, Finished = true, Callback = function(v) Configuration.Egg.MinCoin = tonumber(v) or 0 end })

--============================== Shop =============================
Tabs.Shop:AddSection("Main")
Tabs.Shop:AddToggle("Auto BuyFood",{ Title="Auto Buy Food", Default=false, Callback=function(v)
    Configuration.Shop.Food.AutoBuy = v
    if v then TaskMgr.start("AutoBuyFood", function(tok)
        local FoodList = Data:WaitForChild("FoodStore",30):WaitForChild("LST",30)
        local RE = GameRemoteEvents:WaitForChild("FoodStoreRE")
        while tok.alive do
            for foodName,stockAmount in pairs(FoodList:GetAttributes()) do
                if not tok.alive then break end
                if stockAmount > 0 and Configuration.Shop.Food.Foods[foodName] then
                    if RE then RE:FireServer(foodName) end
                end
            end
            if not _waitAlive(tok, tonumber(Configuration.Shop.Food.AutoBuy_Delay) or 1) then break end
        end
    end) else TaskMgr.stop("AutoBuyFood") end
end })
Tabs.Shop:AddSection("Settings")
Tabs.Shop:AddSlider("AutoBuyFood Delay",{ Title = "Auto Buy Food Delay", Default = 1, Min = 0.1, Max = 3, Rounding = 1, Callback = function(v) Configuration.Shop.Food.AutoBuy_Delay = v end })
Tabs.Shop:AddDropdown("Foods Dropdown",{ Title = "Foods", Values = PetFoods_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Shop.Food.Foods = v end })

--============================== Event ============================
Tabs.Event:AddParagraph({ Title = "Event Information", Content = string.format("Current Event : %s",EventName) })
Tabs.Event:AddSection("Main")
Tabs.Event:AddToggle("Auto Claim Event Quest",{ Title="Auto Claim", Default=false, Callback=function(v)
    Configuration.Event.AutoClaim = v
    if v then TaskMgr.start("AutoClaim", function(tok)
        local Tasks; local EventRE = ResEvent and GameRemoteEvents:WaitForChild(tostring(ResEvent).."RE")
        if EventTaskData then Tasks = EventTaskData:WaitForChild("Tasks") end
        while tok.alive do
            if Tasks and EventRE then
                for _,Quest in pairs(Tasks:GetChildren()) do
                    if not tok.alive then break end
                    EventRE:FireServer({event = "claimreward",id = Quest:GetAttribute("Id")})
                end
            end
            if not _waitAlive(tok, tonumber(Configuration.Event.AutoClaim_Delay) or 3) then break end
        end
    end) else TaskMgr.stop("AutoClaim") end
end })
Tabs.Event:AddSection("Settings")
Tabs.Event:AddSlider("Event_AutoClaim Delay",{ Title = "Auto Claim Delay", Default = 3, Min = 3, Max = 30, Rounding = 0, Callback = function(v) Configuration.Event.AutoClaim_Delay = v end })
Tabs.Event:AddSection("Lottery")
Tabs.Event:AddToggle("Auto Lottery Ticket",{ Title="Auto Lottery Ticket", Default=false, Callback=function(v)
    Configuration.Event.AutoLottery = v
    if v then TaskMgr.start("AutoLottery", function(tok)
        local LotteryRE = GameRemoteEvents:WaitForChild("LotteryRE",30)
        while tok.alive do
            LotteryRE:FireServer({ event = "lottery", count = 1 })
            if not _waitAlive(tok, tonumber(Configuration.Event.AutoLottery_Delay) or 60) then break end
        end
    end) else TaskMgr.stop("AutoLottery") end
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
                                totalSent += 1
                            end
                        end
                        if totalSent == 0 then
                            Fluent:Notify({ Title = "Match_Eggs", Content = "ไม่พบไข่ที่ตรงเงื่อนไข (หรือถูกวางไว้แล้ว)", Duration = 4 })
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
Tabs.Players:AddDropdown("Gift Foods", { Title = "Foods to Gift (Select)", Description = "เลือกชนิดอาหารที่จะส่ง (ใช้เมื่อ Gift Type = Select_Foods)", Values = PetFoods_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Players.Food_Selected = v end })
local PickFoodDD = Tabs.Players:AddDropdown("Pick Food Amount", { Title = "Pick Food to set amount", Values = PetFoods_InGame, Multi = false, Default = "", Callback = function(v) Configuration.Players.Food_AmountPick = v end })
Tabs.Players:AddInput("Set Food Amount", { Title = "Set Amount for picked food", Default = 1, Placeholder = "จำนวนสำหรับชนิดที่เลือก", Numeric = true, Finished = true, Callback = function(v)
    local food = Configuration.Players.Food_AmountPick
    if food and food ~= "" then
        local n = math.max(1, math.floor(tonumber(v) or 1))
        Configuration.Players.Food_Amounts[food] = n
    end
end })
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
            if n > 0 then table.insert(lines, string.format("    - %s %s: %d", MUTA_EMOJI[key], key, n)) end
        end
        for m, n in pairs(mutaCounts) do
            if not ORDER_SET[m] and (tonumber(n) or 0) > 0 then
                table.insert(lines, string.format("    - %s %s: %d", MUTA_EMOJI[m], m, n))
            end
        end
    end
    for _, t in ipairs(Eggs_InGame) do if map[t] then lineFor(t, map[t]); shown[t]=true end end
    for t, counts in pairs(map) do if not shown[t] then lineFor(t, counts) end end
    if #lines == 0 then return "ไม่มีไข่ในกระเป๋า (ที่ยังไม่ถูกวาง) ในตอนนี้" else return table.concat(lines, "\n") end
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
Tabs.Sell:AddInput("Pet Income Threshold", { Title = "รายได้ต่อวิ (ขายสัตว์ที่ \"น้อยกว่า\" ค่านี้)", Default = tostring(Configuration.Sell.Pet_Income_Threshold or 0), Numeric = true, Finished = true, Callback = function(v) Configuration.Sell.Pet_Income_Threshold = tonumber(v) or 0 end })
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
                                local okM = (mutOn and (Configuration.Sell.Egg_Mutations[m] == true)) or ((not mutOn) and (m == "None"))
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
                    Fluent:Notify({ Title = "Sell Summary", Content = ("รวม %d | สำเร็จ %d | ล้มเหลว %d"):format(total, okCnt, failCnt), Duration = 7 })
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
Tabs.Settings:AddToggle("Disable3DOnly", { Title = "Disable 3D Rendering (GUI only)", Default = false, Callback = function(v)
    Configuration.Perf.Disable3D = v
    Perf_Set3DEnabled(not v)
end })
Tabs.Settings:AddSection("Debug")
Tabs.Settings:AddToggle("DebugOn", { Title = "Enable Debug Log", Default = (G.MEOWY_DBG and G.MEOWY_DBG.on) or true, Callback = function(v) G.MEOWY_DBG = G.MEOWY_DBG or {}; G.MEOWY_DBG.on = v end })
Tabs.Settings:AddToggle("DebugToast", { Title = "Show Debug as Toast", Default = (G.MEOWY_DBG and G.MEOWY_DBG.toast) or false, Callback = function(v) G.MEOWY_DBG = G.MEOWY_DBG or {}; G.MEOWY_DBG.toast = v end })

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

-- Load config + re-apply FPS lock if needed
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
    if Configuration.Egg.AutoHatch then TaskMgr.start("AutoHatch", function(tok)
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
    end) end
    if Configuration.Egg.AutoBuyEgg then TaskMgr.start("AutoBuyEgg", function(tok)
        local RE = GameRemoteEvents:WaitForChild("CharacterRE",30)
        local function currentCoin()
            local asset = InventoryData or Data:FindFirstChild("Asset")
            if not asset then return 0 end
            return tonumber(asset:GetAttribute("Coin") or 0) or 0
        end
        while tok.alive do
            local coinOk = (not Configuration.Egg.CheckMinCoin)
                or (currentCoin() >= (tonumber(Configuration.Egg.MinCoin) or 0))
            if coinOk then
                for _,egg in pairs(Egg_Belt) do
                    if not tok.alive then break end
                    if (Configuration.Egg.Types[egg.Type]) and (Configuration.Egg.Mutations[egg.Mutate]) then
                        if RE then RE:FireServer("BuyEgg", egg.UID) end
                    end
                end
            end
            if not _waitAlive(tok, tonumber(Configuration.Egg.AutoBuyEgg_Delay) or 1) then break end
        end
    end) end
    if Configuration.Egg.AutoPlaceEgg then TaskMgr.start("AutoPlaceEgg", runAutoPlaceEgg) end
    if Configuration.Shop.Food.AutoBuy then TaskMgr.start("AutoBuyFood", function(tok)
        local FoodList = Data:WaitForChild("FoodStore",30):WaitForChild("LST",30)
        local RE = GameRemoteEvents:WaitForChild("FoodStoreRE")
        while tok.alive do
            for foodName,stockAmount in pairs(FoodList:GetAttributes()) do
                if not tok.alive then break end
                if stockAmount > 0 and Configuration.Shop.Food.Foods[foodName] then
                    if RE then RE:FireServer(foodName) end
                end
            end
            if not _waitAlive(tok, tonumber(Configuration.Shop.Food.AutoBuy_Delay) or 1) then break end
        end
    end) end
    if Configuration.Event.AutoClaim then TaskMgr.start("AutoClaim", function(tok)
        local Tasks; local EventRE = ResEvent and GameRemoteEvents:WaitForChild(tostring(ResEvent).."RE")
        if EventTaskData then Tasks = EventTaskData:WaitForChild("Tasks") end
        while tok.alive do
            if Tasks and EventRE then
                for _,Quest in pairs(Tasks:GetChildren()) do
                    if not tok.alive then break end
                    EventRE:FireServer({event = "claimreward",id = Quest:GetAttribute("Id")})
                end
            end
            if not _waitAlive(tok, tonumber(Configuration.Event.AutoClaim_Delay) or 3) then break end
        end
    end) end
    if Configuration.Event.AutoLottery then TaskMgr.start("AutoLottery", function(tok)
        local LotteryRE = GameRemoteEvents:WaitForChild("LotteryRE",30)
        while tok.alive do
            LotteryRE:FireServer({ event = "lottery", count = 1 })
            if not _waitAlive(tok, tonumber(Configuration.Event.AutoLottery_Delay) or 60) then break end
        end
    end) end
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

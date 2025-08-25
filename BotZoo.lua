--// Meowy Build A Zoo – Safe/Patched Full Script
--// NOTE: ใช้เฉพาะเพื่อการทดสอบ/การใช้งานส่วนตัวในเกมที่คุณมีสิทธิ์เท่านั้น

if game.PlaceId ~= 105555311806207 then return end

local function safeNotify(title, content, dur)
    pcall(function()
        if typeof(Fluent) == "table" and Fluent.Notify then
            Fluent:Notify({Title = title, Content = content, Duration = dur or 6})
        else
            print(string.format("[%-10s] %s", title, content))
        end
    end)
end

local function httpget(url)
    local ok, res = pcall(game.HttpGet, game, url)
    if not ok then
        ok, res = pcall(function()
            local HttpService = game:GetService("HttpService")
            return (syn and syn.request or http and http.request or request)({
                Url = url, Method = "GET"
            }).Body
        end)
    end
    return ok and res or nil
end

-- NOTE: กัน run ซ้ำ
pcall(function() if getgenv().MeowyBuildAZoo then getgenv().MeowyBuildAZoo:Destroy() end end)
repeat task.wait(0.5) until game:IsLoaded()

-- NOTE: โหลด Fluent ด้วย 2 แหล่ง (release -> raw) กันล่ม
local FluentSrc =
    httpget("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua")
    or httpget("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/main.lua")
assert(FluentSrc, "โหลด Fluent ไม่ได้")
local Fluent = loadstring(FluentSrc)()

local SaveManagerSrc = httpget("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua")
assert(SaveManagerSrc, "โหลด SaveManager ไม่ได้")
local SaveManager = loadstring(SaveManagerSrc)()

local InterfaceManagerSrc = httpget("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua")
assert(InterfaceManagerSrc, "โหลด InterfaceManager ไม่ได้")
local InterfaceManager = loadstring(InterfaceManagerSrc)()

-- === Services & Roots ===
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Player = Players.LocalPlayer
assert(Player, "ไม่พบ Players.LocalPlayer")

-- NOTE: Data อยู่ใน PlayerGui? ทำให้ robust: ลองหลายที่
local PlayerGui = Player:WaitForChild("PlayerGui", 60)
assert(PlayerGui, "ไม่พบ PlayerGui")

local Data = PlayerGui:FindFirstChild("Data")
if not Data then
    -- เผื่อเกมย้าย Data ไปที่อื่น
    Data = Player:FindFirstChild("Data") or ReplicatedStorage:FindFirstChild("Data")
end
assert(Data, "ไม่พบโหนด Data ของผู้เล่น")

local RemoteRoot = ReplicatedStorage:WaitForChild("Remote", 30)
assert(RemoteRoot, "ไม่พบ ReplicatedStorage.Remote")

local GameRemoteEvents = RemoteRoot
local GameName = (MarketplaceService:GetProductInfo(game.PlaceId) and MarketplaceService:GetProductInfo(game.PlaceId).Name) or "None"

-- World deps
local Pet_Folder = workspace:FindFirstChild("Pets") or workspace:WaitForChild("Pets", 30)
assert(Pet_Folder, "ไม่พบ workspace.Pets")

-- NOTE: บางเซิร์ฟเวอร์อาจยังไม่ได้เซ็ต Attribute นี้
local IslandName = Player:GetAttribute("AssignedIslandName")
if not IslandName then
    -- fallback: เดาเกาะจาก workspace.Art ตัวแรกที่เป็น Model
    local Art = workspace:FindFirstChild("Art")
    if Art then
        for _, obj in ipairs(Art:GetChildren()) do
            if obj:IsA("Model") then IslandName = obj.Name break end
        end
    end
end
assert(IslandName, "ไม่พบ IslandName")

local Art = workspace:WaitForChild("Art", 30)
local Island = Art:FindFirstChild(IslandName) or Art:WaitForChild(IslandName, 30)
assert(Island, "ไม่พบ Island: "..tostring(IslandName))

local BlockFolder = workspace:FindFirstChild("PlayerBuiltBlocks") or workspace:WaitForChild("PlayerBuiltBlocks", 30)
local ServerTime = ReplicatedStorage:WaitForChild("Time", 30)
local InGameConfig = ReplicatedStorage:WaitForChild("Config", 30)
assert(BlockFolder and ServerTime and InGameConfig, "ไม่ครบ World/Config")

local EggsRoot = ReplicatedStorage:WaitForChild("Eggs", 30)
assert(EggsRoot, "ไม่พบ ReplicatedStorage.Eggs")
local Egg_Belt_Folder = EggsRoot:FindFirstChild(IslandName) or EggsRoot:WaitForChild(IslandName, 30)
assert(Egg_Belt_Folder, "ไม่พบ Egg Belt Folder ("..tostring(IslandName)..")")

local ServerReplicatedDict = ReplicatedStorage:WaitForChild("ServerDictReplicated", 30)
assert(ServerReplicatedDict, "ไม่พบ ServerDictReplicated")

local OwnedPetData = Data:WaitForChild("Pets", 30)
assert(OwnedPetData, "ไม่พบ Data.Pets")
local OwnedEggData = Data:WaitForChild("Egg", 30)
assert(OwnedEggData, "ไม่พบ Data.Egg")

-- === Require Resources (กัน error) ===
local function safeRequire(m)
    local ok, r = pcall(require, m)
    return ok and r or {}
end

local Eggs_InGame = safeRequire(InGameConfig:WaitForChild("ResEgg", 30)).__index or {}
local Mutations_InGame = safeRequire(InGameConfig:WaitForChild("ResMutate", 30)).__index or {}
local PetFoods_InGame = safeRequire(InGameConfig:WaitForChild("ResPetFood", 30)).__index or {}
local Pets_InGame = safeRequire(InGameConfig:WaitForChild("ResPet", 30)).__index or {}

-- === Build Grids (กันพังหากไม่มี attr) ===
local Grids = {}
for _, grid in ipairs(Island:GetChildren()) do
    if grid:IsA("BasePart") and string.find(grid.Name, "Farm") then
        local coord = grid:GetAttribute("IslandCoord")
        table.insert(Grids, { GridCoord = coord, GridPos = grid.CFrame.Position })
    end
end

-- === Event Data (optional) ===
local EventTaskData, ResEvent, EventName = nil, nil, "None"
for _, df in ipairs(Data:GetChildren()) do
    local prefix = tostring(df):match("^(.*)EventTaskData$")
    if prefix then EventTaskData = df break end
end
for _, v in ipairs(ReplicatedStorage:GetChildren()) do
    local prefix = tostring(v):match("^(.*)Event$")
    if prefix then ResEvent = v EventName = prefix break end
end

-- === Helpers ===
local function GetCash(TXT)
    if TXT then
        local cash = string.gsub(TXT, "[$,]", "")
        return tonumber(cash) or 0
    end
    return 0
end

-- NOTE: เอาฟังก์ชันที่ใช้ตัวแปรไม่ได้ประกาศออก (GetFreeGrid เดิม) เพื่อกันพัง

-- === Live state ===
local RunningEnvirontments = true
local EnvirontmentConnections = {}
local Players_InGame = {}
local PlayerUserID = Player.UserId
local OwnedPets = {}
local Egg_Belt = {}

-- Players list
table.insert(EnvirontmentConnections, Players.PlayerRemoving:Connect(function(plr)
    local idx = table.find(Players_InGame, plr.Name)
    if idx then table.remove(Players_InGame, idx) end
end))
table.insert(EnvirontmentConnections, Players.PlayerAdded:Connect(function(plr)
    table.insert(Players_InGame, plr.Name)
end))
for _, plr in ipairs(Players:GetPlayers()) do
    table.insert(Players_InGame, plr.Name)
end

-- Egg belt tracking
table.insert(EnvirontmentConnections, Egg_Belt_Folder.ChildRemoved:Connect(function(egg)
    task.wait(0.05)
    local uid = egg and tostring(egg)
    if uid then Egg_Belt[uid] = nil end
end))
table.insert(EnvirontmentConnections, Egg_Belt_Folder.ChildAdded:Connect(function(egg)
    task.wait(0.05)
    if not egg then return end
    local uid = tostring(egg)
    Egg_Belt[uid] = { UID = uid, Mutate = (egg:GetAttribute("M") or "None"), Type = (egg:GetAttribute("T") or "BasicEgg") }
end))
for _, egg in ipairs(Egg_Belt_Folder:GetChildren()) do
    task.spawn(function()
        local uid = tostring(egg)
        Egg_Belt[uid] = { UID = uid, Mutate = (egg:GetAttribute("M") or "None"), Type = (egg:GetAttribute("T") or "BasicEgg") }
    end)
end

-- Pets tracking
table.insert(EnvirontmentConnections, Pet_Folder.ChildRemoved:Connect(function(pet)
    task.wait(0.05)
    local uid = pet and tostring(pet)
    if uid then OwnedPets[uid] = nil end
end))
table.insert(EnvirontmentConnections, Pet_Folder.ChildAdded:Connect(function(pet)
    task.wait(0.1)
    if not pet then return end
    local uid = tostring(pet)
    if pet:GetAttribute("UserId") ~= PlayerUserID then return end
    local primary = pet.PrimaryPart or pet:FindFirstChild("RootPart") or pet:WaitForChild("RootPart")
    local cashBB = primary and (primary:FindFirstChild("GUI/IdleGUI") or primary:FindFirstChild("GUI") or primary:FindFirstChild("IdleGUI"))
    local cashFrame = cashBB and (cashBB:FindFirstChild("CashF") or cashBB:FindFirstChild("CashFrame") or cashBB:FindFirstChild("Cash"))
    local cashTXT = cashFrame and (cashFrame:FindFirstChild("TXT") or cashFrame:FindFirstChild("TextLabel"))
    local di = OwnedPetData:FindFirstChild(uid) and OwnedPetData[uid]:FindFirstChild("DI")
    local grid = di and Vector3.new(di:GetAttribute("X") or 0, di:GetAttribute("Y") or 0, di:GetAttribute("Z") or 0) or nil
    OwnedPets[uid] = setmetatable({
        GridCoord = grid,
        UID = uid,
        Type = primary and primary:GetAttribute("Type"),
        Mutate = primary and primary:GetAttribute("Mutate"),
        Model = pet,
        RootPart = primary,
        RE = primary and primary:FindFirstChild("RE", true),
        IsBig = (primary and (primary:GetAttribute("BigValue") ~= nil)) or false
    }, {
        __index = function(tb, ind)
            if ind == "Coin" then return (cashTXT and GetCash(cashTXT.Text)) end
            return rawget(tb, ind)
        end
    })
end))
for _, pet in ipairs(Pet_Folder:GetChildren()) do
    task.spawn(function()
        if pet:GetAttribute("UserId") ~= PlayerUserID then return end
        local uid = tostring(pet)
        local primary = pet.PrimaryPart or pet:FindFirstChild("RootPart") or pet:WaitForChild("RootPart")
        local cashBB = primary and (primary:FindFirstChild("GUI/IdleGUI") or primary:FindFirstChild("GUI") or primary:FindFirstChild("IdleGUI"))
        local cashFrame = cashBB and (cashBB:FindFirstChild("CashF") or cashBB:FindFirstChild("CashFrame") or cashBB:FindFirstChild("Cash"))
        local cashTXT = cashFrame and (cashFrame:FindFirstChild("TXT") or cashFrame:FindFirstChild("TextLabel"))
        local di = OwnedPetData:FindFirstChild(uid) and OwnedPetData[uid]:FindFirstChild("DI")
        local grid = di and Vector3.new(di:GetAttribute("X") or 0, di:GetAttribute("Y") or 0, di:GetAttribute("Z") or 0) or nil
        OwnedPets[uid] = setmetatable({
            GridCoord = grid,
            UID = uid,
            Type = primary and primary:GetAttribute("Type"),
            Mutate = primary and primary:GetAttribute("Mutate"),
            Model = pet,
            RootPart = primary,
            RE = primary and primary:FindFirstChild("RE", true),
            IsBig = (primary and (primary:GetAttribute("BigValue") ~= nil)) or false
        }, {
            __index = function(tb, ind)
                if ind == "Coin" then return (cashTXT and GetCash(cashTXT.Text)) end
                return rawget(tb, ind)
            end
        })
    end)
end

-- === Config ===
local Configuration = {
    Main = { AutoCollect = false, Collect_Delay = 5, Collect_Type = "Delay", Collect_Between = { Min = 100000, Max = 1000000 }, },
    Pet  = { AutoFeed = false, AutoFeed_Foods = {}, AutoFeed_Delay = 3, AutoFeed_Type = "", CollectPet_Type = "All",
             CollectPet_Auto = false, CollectPet_Mutations = {}, CollectPet_Pets = {}, CollectPet_Delay = 5, },
    Egg  = { AutoHatch = false, Hatch_Delay = 15, AutoBuyEgg = false, AutoBuyEgg_Delay = 1, Mutations = {}, Types = {}, },
    Shop = { Food = { AutoBuy = false, AutoBuy_Delay = 1, Foods = {}, }, },
    Players = {
        SelectPlayer = "", SelectType = "",
        -- NOTE: เพิ่มตัวกรองส่ง Pet
        GiftPet_FilterType = "All",      -- All | Match Pet | Match Mutation | Match Pet&Mutation
        GiftPet_Pets = {},
        GiftPet_Mutations = {},
    },
    Event = { AutoClaim = false, AutoClaim_Delay = 3, },
    AntiAFK = false,
    Waiting = false,
}

-- === UI Window ===
local Window = Fluent:CreateWindow({
    Title = GameName, SubTitle = "by Meowy",
    TabWidth = 160, Size = UDim2.fromOffset(522, 414),
    Acrylic = true, Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    About = Window:AddTab({ Title = "About", Icon = "" }),
    Main = Window:AddTab({ Title = "Main Features", Icon = "" }),
    Pet  = Window:AddTab({ Title = "Pet Features", Icon = "" }),
    Egg  = Window:AddTab({ Title = "Egg Features", Icon = "" }),
    Shop = Window:AddTab({ Title = "Shop Features", Icon = "" }),
    Event= Window:AddTab({ Title = "Event Feature", Icon = "" }),
    Players = Window:AddTab({ Title = "Players Features", Icon = "" }),
    Settings= Window:AddTab({ Title = "Settings", Icon = "settings" }),
}
local Options = Fluent.Options

-- === Main Tab ===
do
    Tabs.Main:AddSection("Main")
    Tabs.Main:AddToggle("AutoCollect",{
        Title = "Auto Collect", Default = false,
        Callback = function(v) Configuration.Main.AutoCollect = v end
    })
    Tabs.Main:AddSection("Settings")
    Tabs.Main:AddSlider("AutoCollect Delay",{
        Title="Collect Delay", Description="Set Collect Delay",
        Default=5, Min=1, Max=30, Rounding=0,
        Callback=function(v) Configuration.Main.Collect_Delay = v end
    })
    Tabs.Main:AddDropdown("CollectCash Type",{
        Title="Select Type", Values={"Delay","Between"}, Multi=false, Default="Delay",
        Callback=function(v) Configuration.Main.Collect_Type = v end
    })
    Tabs.Main:AddInput("CollectCash_Num1",{ Title="Min Coin", Default=100000, Numeric=true, Finished=false,
        Callback=function(v) Configuration.Main.Collect_Between.Min = tonumber(v) or Configuration.Main.Collect_Between.Min end })
    Tabs.Main:AddInput("CollectCash_Num2",{ Title="Max Coin", Default=1000000, Numeric=true, Finished=false,
        Callback=function(v) Configuration.Main.Collect_Between.Max = tonumber(v) or Configuration.Main.Collect_Between.Max end })
end

-- === Pet Tab ===
do
    Tabs.Pet:AddSection("Main")
    Tabs.Pet:AddToggle("Auto Feed",{ Title="Auto Feed", Default=false,
        Callback=function(v) Configuration.Pet.AutoFeed = v end })
    Tabs.Pet:AddToggle("Auto Collect Pet",{ Title="Auto Collect Pet", Default=false,
        Description="Auto Collect Pet with selected type (All Pet Type will not work with this)",
        Callback=function(v) Configuration.Pet.CollectPet_Auto = v end })

    Tabs.Pet:AddButton({
        Title="Collect Pet", Description="Collect Pets with Collect Pet Type (this will not collect big pet)",
        Callback=function()
            Window:Dialog({
                Title="Collect Pet Alert", Content="Are you sure?",
                Buttons = {
                    { Title="Yes", Callback=function()
                        local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE", 10)
                        if not CharacterRE then return end
                        local CollectType = Configuration.Pet.CollectPet_Type
                        local function tryCollect(UID, PetData)
                            if PetData.RE then pcall(function() PetData.RE:FireServer("Claim") end) end
                            pcall(function() CharacterRE:FireServer("Del", UID) end)
                        end
                        if CollectType == "All" then
                            for UID, PetData in pairs(OwnedPets) do
                                if PetData and not PetData.IsBig then tryCollect(UID, PetData) end
                            end
                        elseif CollectType == "Match Pet" then
                            for UID, PetData in pairs(OwnedPets) do
                                if PetData and not PetData.IsBig and Configuration.Pet.CollectPet_Pets[PetData.Type] then
                                    tryCollect(UID, PetData)
                                end
                            end
                        elseif CollectType == "Match Mutation" then
                            for UID, PetData in pairs(OwnedPets) do
                                if PetData and not PetData.IsBig and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                                    tryCollect(UID, PetData)
                                end
                            end
                        elseif CollectType == "Match Pet&Mutation" then
                            for UID, PetData in pairs(OwnedPets) do
                                if PetData and not PetData.IsBig
                                and Configuration.Pet.CollectPet_Pets[PetData.Type]
                                and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                                    tryCollect(UID, PetData)
                                end
                            end
                        end
                    end},
                    { Title="No", Callback=function() end }
                }
            })
        end
    })

    Tabs.Pet:AddSection("Settings")
    Tabs.Pet:AddSlider("AutoFeed Delay",{ Title="Feed Delay", Description="Set Feed Delay",
        Default=3, Min=3, Max=30, Rounding=0, Callback=function(v) Configuration.Pet.AutoFeed_Delay = v end })
    Tabs.Pet:AddSlider("AutoCollectPet Delay",{ Title="Auto Collect Pet Delay", Description="Set Auto Collect Pet Delay",
        Default=5, Min=5, Max=60, Rounding=0, Callback=function(v) Configuration.Pet.CollectPet_Delay = v end })
    Tabs.Pet:AddDropdown("Pet Feed_Type",{ Title="Select Type", Values={"BestFood","SelectFood"}, Multi=false, Default="",
        Callback=function(v) Configuration.Pet.AutoFeed_Type = v end })
    Tabs.Pet:AddDropdown("Pet Feed_Food",{ Title="Select Foods", Values=PetFoods_InGame, Multi=true, Default={},
        Callback=function(v) Configuration.Pet.AutoFeed_Foods = v end })
    Tabs.Pet:AddDropdown("CollectPet Type",{ Title="Collect Pet Type", Description="Select Collect Pet Type for Auto/Manual",
        Values={"All","Match Pet","Match Mutation","Match Pet&Mutation"}, Multi=false, Default="All",
        Callback=function(v) Configuration.Pet.CollectPet_Type = v end })
    Tabs.Pet:AddDropdown("CollectPet Pets",{ Title="Collect Pets", Description="Specific Pets for Auto/Manual",
        Values=Pets_InGame, Multi=true, Default={}, Callback=function(v) Configuration.Pet.CollectPet_Pets = v end })
    Tabs.Pet:AddDropdown("CollectPet Mutations",{ Title="Collect Mutations", Description="Mutations for Auto/Manual",
        Values=Mutations_InGame, Multi=true, Default={}, Callback=function(v) Configuration.Pet.CollectPet_Mutations = v end })
end

-- === Egg Tab ===
do
    Tabs.Egg:AddSection("Main")
    Tabs.Egg:AddToggle("Auto Hatch",{ Title="Auto Hatch", Default=false, Callback=function(v) Configuration.Egg.AutoHatch = v end })
    Tabs.Egg:AddToggle("Auto Egg",{ Title="Auto Buy Egg", Default=false, Callback=function(v) Configuration.Egg.AutoBuyEgg = v end })

    Tabs.Egg:AddSection("Settings")
    Tabs.Egg:AddSlider("AutoHatch Delay",{ Title="Hatch Delay", Description="Set Auto Hatch Delay",
        Default=15, Min=15, Max=60, Rounding=0, Callback=function(v) Configuration.Egg.Hatch_Delay = v end })
    Tabs.Egg:AddSlider("AutoBuyEgg Delay",{ Title="Auto Buy Egg Delay", Description="Set Auto Buy Egg Delay",
        Default=1, Min=0.1, Max=3, Rounding=1, Callback=function(v) Configuration.Egg.AutoBuyEgg_Delay = v end })
    Tabs.Egg:AddDropdown("Egg Type",{ Title="Types", Values=Eggs_InGame, Multi=true, Default={},
        Callback=function(v) Configuration.Egg.Types = v end })
    Tabs.Egg:AddDropdown("Egg Mutations",{ Title="Mutations", Values=Mutations_InGame, Multi=true, Default={},
        Callback=function(v) Configuration.Egg.Mutations = v end })
end

-- === Shop Tab ===
do
    Tabs.Shop:AddSection("Main")
    Tabs.Shop:AddToggle("Auto BuyFood",{ Title="Auto Buy Food", Default=false, Callback=function(v) Configuration.Shop.Food.AutoBuy = v end })
    Tabs.Shop:AddSection("Settings")
    Tabs.Shop:AddSlider("AutoBuyFood Delay",{ Title="Auto Buy Food Delay", Description="Set Auto Buy Food Delay",
        Default=1, Min=0.1, Max=3, Rounding=1, Callback=function(v) Configuration.Shop.Food.AutoBuy_Delay = v end })
    Tabs.Shop:AddDropdown("Foods Dropdown",{ Title="Foods", Values=PetFoods_InGame, Multi=true, Default={},
        Callback=function(v) Configuration.Shop.Food.Foods = v end })
end

-- === Event Tab ===
do
    Tabs.Event:AddParagraph({ Title="Event Information", Content=string.format("Current Event : %s", EventName) })
    Tabs.Event:AddSection("Main")
    Tabs.Event:AddToggle("Auto Claim Event Quest",{ Title="Auto Claim", Description="Auto Claim Event Quests",
        Default=false, Callback=function(v) Configuration.Event.AutoClaim = v end })
    Tabs.Event:AddSection("Settings")
    Tabs.Event:AddSlider("Event_AutoClaim Delay",{ Title="Auto Claim Delay", Description="Set Auto Claim Quest Delay",
        Default=3, Min=3, Max=30, Rounding=0, Callback=function(v) Configuration.Event.AutoClaim_Delay = v end })
end

-- === Players Tab ===
do
    Tabs.Players:AddSection("Main")
    Tabs.Players:AddButton({
        Title="Send Gift", Description="Send Gift",
        Callback=function()
            Window:Dialog({
                Title="Send Gift Alert", Content="Are you sure?",
                Buttons = {
                    { Title="Yes", Callback=function()
                        local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE", 10)
                        local GiftRE = GameRemoteEvents:WaitForChild("GiftRE", 10)
                        local GiftType = Configuration.Players.SelectType
                        local GiftPlayer = Players:FindFirstChild(Configuration.Players.SelectPlayer)
                        if not (CharacterRE and GiftRE and GiftPlayer) then
                            safeNotify("Gift", "ขาด RE หรือผู้เล่นเป้าหมาย", 6)
                            return
                        end
                        Configuration.Waiting = true
                        if GiftType == "Pets" then
                            local filterType = Configuration.Players.GiftPet_FilterType
                            local wantPets  = Configuration.Players.GiftPet_Pets
                            local wantMutas = Configuration.Players.GiftPet_Mutations

                            for _, PetNode in ipairs(OwnedPetData:GetChildren()) do
                                if PetNode and not PetNode:GetAttribute("D") then
                                    local uid = PetNode.Name
                                    local meta = OwnedPets[uid] -- มีเมื่อ spawn
                                    local pType = meta and meta.Type or nil
                                    local pMuta = meta and meta.Mutate or nil

                                    local function passFilter()
                                        if filterType == "All" then return true end
                                        if filterType == "Match Pet" then return (pType ~= nil) and (wantPets[pType] == true) end
                                        if filterType == "Match Mutation" then return (pMuta ~= nil) and (wantMutas[pMuta] == true) end
                                        if filterType == "Match Pet&Mutation" then
                                            return (pType ~= nil) and (pMuta ~= nil) and (wantPets[pType] == true) and (wantMutas[pMuta] == true)
                                        end
                                        return false
                                    end

                                    if (meta == nil and filterType == "All") or (meta ~= nil and passFilter()) then
                                        pcall(function() CharacterRE:FireServer("Focus", uid) end)
                                        task.wait(0.6)
                                        pcall(function() GiftRE:FireServer(GiftPlayer) end)
                                        task.wait(0.6)
                                    end
                                end
                            end
                        elseif GiftType == "Foods" then
                            local InventoryData = Data:FindFirstChild("Asset")
                            if InventoryData then
                                for FoodName, Amount in pairs(InventoryData:GetAttributes()) do
                                    if FoodName and table.find(PetFoods_InGame, FoodName) and Amount > 0 then
                                        for i = 1, Amount do
                                            pcall(function() CharacterRE:FireServer("Focus", FoodName) end)
                                            task.wait(0.5)
                                            pcall(function() GiftRE:FireServer(GiftPlayer) end)
                                            task.wait(0.5)
                                        end
                                    end
                                end
                            end
                        elseif GiftType == "Eggs" then
                            for _, Egg in ipairs(OwnedEggData:GetChildren()) do
                                if Egg and not Egg:FindFirstChild("DI") then
                                    pcall(function() CharacterRE:FireServer("Focus", Egg.Name) end)
                                    task.wait(0.6)
                                    pcall(function() GiftRE:FireServer(GiftPlayer) end)
                                    task.wait(0.6)
                                end
                            end
                        else
                            safeNotify("Gift", "กรุณาเลือก Gift Type ก่อน", 6)
                        end
                        Configuration.Waiting = false
                    end},
                    { Title="No", Callback=function() end }
                }
            })
        end
    })

    Tabs.Players:AddSection("Settings")
    local Players_Dropdown = Tabs.Players:AddDropdown("Players Dropdown",{
        Title="Select Player", Values=Players_InGame, Multi=false, Default="",
        Callback=function(v) Configuration.Players.SelectPlayer = v end
    })
    Tabs.Players:AddDropdown("GiftType Dropdown",{
        Title="Gift Type", Values={"Pets","Foods","Eggs"}, Multi=false, Default="",
        Callback=function(v) Configuration.Players.SelectType = v end
    })

    -- NOTE: ตัวกรองการส่ง Pet
    Tabs.Players:AddDropdown("GiftPet Filter Type",{
        Title="Gift Pet Filter", Description="คัดกรอง Pet ที่จะส่ง",
        Values={"All","Match Pet","Match Mutation","Match Pet&Mutation"}, Multi=false, Default="All",
        Callback=function(v) Configuration.Players.GiftPet_FilterType = v end
    })
    Tabs.Players:AddDropdown("GiftPet Pets",{
        Title="Gift Pets (Types)", Description="เลือกประเภท Pet ที่ต้องการส่ง",
        Values=Pets_InGame, Multi=true, Default={},
        Callback=function(v) Configuration.Players.GiftPet_Pets = v end
    })
    Tabs.Players:AddDropdown("GiftPet Mutations",{
        Title="Gift Pet Mutations", Description="เลือกมิวเทชันของ Pet ที่ต้องการส่ง",
        Values=Mutations_InGame, Multi=true, Default={},
        Callback=function(v) Configuration.Players.GiftPet_Mutations = v end
    })

    -- อัปเดตรายชื่อผู้เล่นในดรอปดาวน์เมื่อเข้า/ออก
    table.insert(EnvirontmentConnections, Players.PlayerAdded:Connect(function()
        pcall(function() Players_Dropdown:SetValues(Players_InGame) end)
    end))
    table.insert(EnvirontmentConnections, Players.PlayerRemoving:Connect(function()
        pcall(function() Players_Dropdown:SetValues(Players_InGame) end)
    end))
end

-- === Settings / About ===
do
    Tabs.About:AddParagraph({ Title="Credit", Content="Script create by Meowy / godyt_2.0 (patched by assistant)" })
    Tabs.Settings:AddToggle("AntiAFK",{ Title="Anti AFK", Default=false, Callback=function(v)
        Configuration.AntiAFK = v
        local thr = v and 99999999999 or 1080
        pcall(function() ServerReplicatedDict:SetAttribute("AFK_THRESHOLD", thr) end)
    end})
end

-- Save/Interface
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/"..game.PlaceId)
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)
safeNotify("Fluent", "The script has been loaded.", 8)

-- === Workers ===
task.defer(function() -- Anti AFK
    local VirtualUser = game:GetService("VirtualUser")
    local sig = ServerReplicatedDict:GetAttributeChangedSignal("AFK_THRESHOLD")
    table.insert(EnvirontmentConnections, sig:Connect(function()
        local thr = Configuration.AntiAFK and 99999999999 or 1080
        pcall(function() ServerReplicatedDict:SetAttribute("AFK_THRESHOLD", thr) end)
    end))
    while RunningEnvirontments do
        if Configuration.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
        task.wait(30)
    end
end)

task.defer(function() -- Auto Collect cash on pets
    while RunningEnvirontments do
        if Configuration.Main.AutoCollect then
            for _, pet in pairs(OwnedPets) do
                local RE = pet.RE
                local Coin = tonumber(pet.Coin) or 0
                if Configuration.Main.Collect_Type == "Delay" then
                    if RE then pcall(function() RE:FireServer("Claim") end) end
                elseif Configuration.Main.Collect_Type == "Between" then
                    if (Configuration.Main.Collect_Between.Min < Coin and Coin < Configuration.Main.Collect_Between.Max) and RE then
                        pcall(function() RE:FireServer("Claim") end)
                    end
                end
            end
        end
        task.wait(Configuration.Main.Collect_Delay)
    end
end)

local function GetBestPetFood(FoodList, OwnedFoods)
    local best = ""
    for _, v in ipairs(FoodList) do
        if OwnedFoods[v] then best = v end
    end
    return best
end
local function GetFood(OwnedFoods)
    local best = ""
    for _, v in ipairs(PetFoods_InGame) do
        if Configuration.Pet.AutoFeed_Foods[v] and OwnedFoods[v] then best = v end
    end
    return best
end

task.defer(function() -- Auto Feed Pet (เฉพาะ Big)
    local PetRE = GameRemoteEvents:WaitForChild("PetRE", 10)
    local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE", 10)
    while RunningEnvirontments do
        if Configuration.Pet.AutoFeed and not Configuration.Waiting and Configuration.Pet.AutoFeed_Type ~= "" then
            local InventoryData = Data:FindFirstChild("Asset")
            local Data_Inventory = InventoryData and InventoryData:GetAttributes() or {}
            for _, petNode in ipairs(OwnedPetData:GetChildren()) do
                local pet = OwnedPets[petNode.Name]
                if pet and pet.IsBig and not petNode:GetAttribute("Feed") then
                    local food = (Configuration.Pet.AutoFeed_Type == "BestFood" and GetBestPetFood(PetFoods_InGame, Data_Inventory))
                              or (Configuration.Pet.AutoFeed_Type == "SelectFood" and GetFood(Data_Inventory))
                    if food ~= "" and CharacterRE and PetRE then
                        pcall(function() CharacterRE:FireServer("Focus", food) end)
                        task.wait(0.4)
                        pcall(function() PetRE:FireServer("Feed", pet.UID) end)
                        task.wait(0.4)
                        pcall(function() CharacterRE:FireServer("Focus") end)
                    end
                end
            end
        end
        task.wait(Configuration.Pet.AutoFeed_Delay)
    end
end)

task.defer(function() -- Auto Collect Pet (ตามตัวกรอง)
    local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE", 10)
    while RunningEnvirontments do
        local CollectType = Configuration.Pet.CollectPet_Type
        if Configuration.Pet.CollectPet_Auto and not Configuration.Waiting and CollectType ~= "All" then
            if CollectType == "Match Pet" then
                for UID, PetData in pairs(OwnedPets) do
                    if PetData and not PetData.IsBig and Configuration.Pet.CollectPet_Pets[PetData.Type] then
                        if PetData.RE then pcall(function() PetData.RE:FireServer("Claim") end) end
                        if CharacterRE then pcall(function() CharacterRE:FireServer("Del", UID) end) end
                    end
                end
            elseif CollectType == "Match Mutation" then
                for UID, PetData in pairs(OwnedPets) do
                    if PetData and not PetData.IsBig and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                        if PetData.RE then pcall(function() PetData.RE:FireServer("Claim") end) end
                        if CharacterRE then pcall(function() CharacterRE:FireServer("Del", UID) end) end
                    end
                end
            elseif CollectType == "Match Pet&Mutation" then
                for UID, PetData in pairs(OwnedPets) do
                    if PetData and not PetData.IsBig
                    and Configuration.Pet.CollectPet_Pets[PetData.Type]
                    and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                        if PetData.RE then pcall(function() PetData.RE:FireServer("Claim") end) end
                        if CharacterRE then pcall(function() CharacterRE:FireServer("Del", UID) end) end
                    end
                end
            end
        end
        task.wait(Configuration.Pet.CollectPet_Delay)
    end
end)

task.defer(function() -- Auto Hatch
    while RunningEnvirontments do
        if Configuration.Egg.AutoHatch then
            for _, egg in ipairs(OwnedEggData:GetChildren()) do
                local hatchable = ((#egg:GetChildren() > 0) and egg:GetAttribute("D") and (ServerTime.Value >= egg:GetAttribute("D")))
                if hatchable then
                    local EggModel = BlockFolder:FindFirstChild(egg.Name)
                    local RootPart = EggModel and (EggModel.PrimaryPart or EggModel:FindFirstChild("RootPart"))
                    local RF = RootPart and RootPart:FindFirstChild("RF")
                    if RF then pcall(function() RF:InvokeServer("Hatch") end) end
                end
            end
        end
        task.wait(Configuration.Egg.Hatch_Delay)
    end
end)

task.defer(function() -- Auto Claim Event Quests
    local Tasks = EventTaskData and EventTaskData:FindFirstChild("Tasks")
    local EventRE = ResEvent and GameRemoteEvents:FindFirstChild(tostring(ResEvent).."RE")
    while RunningEnvirontments do
        if Tasks and EventRE and Configuration.Event.AutoClaim then
            for _, Quest in ipairs(Tasks:GetChildren()) do
                pcall(function() EventRE:FireServer({ event = "claimreward", id = Quest:GetAttribute("Id") }) end)
            end
        end
        task.wait(Configuration.Event.AutoClaim_Delay)
    end
end)

task.defer(function() -- Auto Buy Egg
    local RE = GameRemoteEvents:WaitForChild("CharacterRE", 10)
    while RunningEnvirontments do
        if RE and Configuration.Egg.AutoBuyEgg and not Configuration.Waiting then
            for _, egg in pairs(Egg_Belt) do
                local okType = Configuration.Egg.Types[egg.Type]
                local okMuta = Configuration.Egg.Mutations[egg.Mutate]
                if okType and okMuta then pcall(function() RE:FireServer("BuyEgg", egg.UID) end) end
            end
        end
        task.wait(Configuration.Egg.AutoBuyEgg_Delay)
    end
end)

task.defer(function() -- Auto Buy Food
    local FoodStore = Data:FindFirstChild("FoodStore")
    local LST = FoodStore and FoodStore:FindFirstChild("LST")
    local RE = GameRemoteEvents:FindFirstChild("FoodStoreRE")
    while RunningEnvirontments do
        if RE and LST and Configuration.Shop.Food.AutoBuy and not Configuration.Waiting then
            for foodName, stock in pairs(LST:GetAttributes()) do
                if stock > 0 and Configuration.Shop.Food.Foods[foodName] then
                    pcall(function() RE:FireServer(foodName) end)
                end
            end
        end
        task.wait(Configuration.Shop.Food.AutoBuy_Delay)
    end
end)

Window.Root.Destroying:Once(function()
    RunningEnvirontments = false
    for _, c in ipairs(EnvirontmentConnections) do
        pcall(function() c:Disconnect() end)
    end
end)

-- Save
SaveManager:LoadAutoloadConfig()
getgenv().MeowyBuildAZoo = Window

if game.PlaceId == 105555311806207 then
    if MeowyBuildAZoo then
        MeowyBuildAZoo:Destroy()
    end
    repeat task.wait(1) until game:IsLoaded()
    local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
    local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
    local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

    local RunningEnvirontments = true
    local GameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)["Name"] or "None"

    local EnvirontmentConnections = {}
    local Players = game:GetService("Players")
    local Player = Players.LocalPlayer
    local Players_InGame = {}
    local PlayerUserID = Player.UserId
    local Data = Player:WaitForChild("PlayerGui",60):WaitForChild("Data",60)
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local GameRemoteEvents = ReplicatedStorage:WaitForChild("Remote",30)
    local Pet_Folder = workspace:WaitForChild("Pets")
    local IslandName = Player:GetAttribute("AssignedIslandName")
    local Island = workspace:WaitForChild("Art"):WaitForChild(IslandName)
    local BlockFolder = workspace:WaitForChild("PlayerBuiltBlocks")
    local ServerTime = ReplicatedStorage:WaitForChild("Time")
    local InGameConfig = ReplicatedStorage:WaitForChild("Config")
    local Egg_Belt_Folder = ReplicatedStorage:WaitForChild("Eggs"):WaitForChild(IslandName)
    local ServerReplicatedDict = ReplicatedStorage:WaitForChild("ServerDictReplicated")
    local OwnedPetData = Data:WaitForChild("Pets")
    local OwnedEggData = Data:WaitForChild("Egg")

    -- helper ให้เข้ากับ signature ของ Place
    local vector = { create = function(x,y,z) return Vector3.new(x,y,z) end }

    local Eggs_InGame = require(InGameConfig:WaitForChild("ResEgg"))["__index"]
    local Mutations_InGame = require(InGameConfig:WaitForChild("ResMutate"))["__index"]
    local PetFoods_InGame = require(InGameConfig:WaitForChild("ResPetFood"))["__index"]
    local Pets_InGame = require(InGameConfig:WaitForChild("ResPet"))["__index"]

    -- เก็บกริดฟาร์ม
    local Grids = {}
    for _,grid in pairs(Island:GetDescendants()) do
        if grid:IsA("BasePart") and string.find(tostring(grid), "Farm") then
            table.insert(Grids, {
                GridCoord = grid:GetAttribute("IslandCoord"),
                GridPos = grid.Position
            })
        end
    end

    -- Event data
    local EventTaskData; local ResEvent; local EventName = "None";
    for _,Data_Folder in pairs(Data:GetChildren()) do
        local IsEventTaskData = (tostring(Data_Folder):match("^(.*)EventTaskData$"))
        if IsEventTaskData then EventTaskData = Data_Folder break end
    end
    for _,v in pairs(ReplicatedStorage:GetChildren()) do
        local IsEventData = (tostring(v):match("^(.*)Event$"))
        if IsEventData then ResEvent = v EventName = IsEventData break end
    end

    local InventoryData = Data:WaitForChild("Asset",30)
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
    for _,plr in pairs(Players:GetPlayers()) do
        table.insert(Players_InGame,plr.Name)
    end

    local OwnedPets = {}
    local Egg_Belt = {}
    table.insert(EnvirontmentConnections,Egg_Belt_Folder.ChildRemoved:Connect(function(egg)
        task.wait(0.1)
        local eggUID = tostring(egg) or "None"
        if egg and Egg_Belt[eggUID] then Egg_Belt[eggUID] = nil end
    end))
    table.insert(EnvirontmentConnections,Egg_Belt_Folder.ChildAdded:Connect(function(egg)
        task.wait(0.1)
        local eggUID = tostring(egg) or "None"
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
    local function GetCash(TXT)
        if TXT then
            local cash = string.gsub(TXT,"[$,]","")
            return tonumber(cash)
        end
        return 0
    end

    -- Map OwnedPets พร้อม ProduceSpeed
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

    local Configuration = {
        Main = {
            AutoCollect = false, Collect_Delay = 5,
            Collect_Type = "Delay",
            Collect_Between = {["Min"] = 100000,["Max"] = 1000000},
        },
        Pet = {
            AutoFeed = false, AutoFeed_Foods = {},
            AutoPlacePet = false,
            AutoFeed_Delay = 3, AutoFeed_Type = "",
            CollectPet_Type = "All", CollectPet_Auto = false,
            CollectPet_Mutations = {}, CollectPet_Pets = {},
            CollectPet_Delay = 5,
            CollectPet_Between = {["Min"] = 100000,["Max"] = 1000000},

            -- ▼▼ NEW: โหมด Range สำหรับ Auto Place Pet
            PlacePet_Mode = "All",           -- "All" | "Match" | "Range"
            PlacePet_Types = {},             -- ใช้เมื่อ PlacePet_Mode = "Match"
            PlacePet_Mutations = {},         -- ใช้เมื่อ PlacePet_Mode = "Match"
            AutoPlacePet_Delay = 1.0,

            -- ▼▼ NEW: ช่วงค่าเงินต่อวิ (จาก inventory UI) สำหรับโหมด "Range"
            PlacePet_Between = { Min = 0, Max = 1e18 },
        },

        Egg = {
            AutoHatch = false, Hatch_Delay = 15,
            AutoBuyEgg = false, AutoBuyEgg_Delay = 1,
            AutoPlaceEgg = false, AutoPlaceEgg_Delay = 1.0,
            Mutations = {}, Types = {},
        },
        Shop = { Food = { AutoBuy = false, AutoBuy_Delay = 1, Foods = {} } },
        Players = {
            SelectPlayer = "",
            SelectType = "",
            SendPet_Type = "All",
            Pet_Type = {},
            Pet_Mutations = {},
            -- ▼ เพิ่มใหม่
            Food_Selected = {},      -- map ของชนิดอาหารที่เลือก {Meat=true, Apple=true}
            Food_Amounts  = {},      -- map จำนวนต่อชนิด {Meat=3, Apple=1}
            Food_AmountPick = "",    -- ชนิดที่กำลังเลือกเพื่อกรอกจำนวน
        },
        
        Event = { AutoClaim = false, AutoClaim_Delay = 3 },
        AntiAFK = false, Waiting = false,
    }

    local Window = Fluent:CreateWindow({
        Title = GameName, SubTitle = "by DemiGodz",
        TabWidth = 160, Size = UDim2.fromOffset(522, 414),
        Acrylic = true, Theme = "Dark", MinimizeKey = Enum.KeyCode.LeftControl
    })

    local Tabs = {
        About = Window:AddTab({ Title = "About", Icon = "" }),
        Main = Window:AddTab({ Title = "Main Features", Icon = "" }),
        Pet = Window:AddTab({ Title = "Pet Features", Icon = "" }),
        Egg = Window:AddTab({ Title = "Egg Features", Icon = "" }),
        Shop = Window:AddTab({ Title = "Shop Features", Icon = "" }),
        Event = Window:AddTab({ Title = "Event Feature", Icon = "" }),
        Players = Window:AddTab({ Title = "Players Features", Icon = "" }),
        Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
    }

    local Options = Fluent.Options

    do
        -- Main
        Tabs.Main:AddSection("Main")
        Tabs.Main:AddToggle("AutoCollect",{ Title = "Auto Collect", Default = false, Callback = function(v) Configuration.Main.AutoCollect = v end })
        Tabs.Main:AddSection("Settings")
        Tabs.Main:AddSlider("AutoCollect Delay",{ Title = "Collect Delay", Default = 5, Min = 1, Max = 30, Rounding = 0, Callback = function(v) Configuration.Main.Collect_Delay = v end })
        Tabs.Main:AddDropdown("CollectCash Type",{ Title = "Select Type", Values = {"Delay","Between"}, Multi = false, Default = "Delay", Callback = function(v) Configuration.Main.Collect_Type = v end })
        Tabs.Main:AddInput("CollectCash_Num1",{ Title = "Min Coin", Default = 100000, Numeric = true, Finished = false, Callback = function(v) Configuration.Main.Collect_Between.Min = tonumber(v) end })
        Tabs.Main:AddInput("CollectCash_Num2",{ Title = "Max Coin", Default = 1000000, Numeric = true, Finished = false, Callback = function(v) Configuration.Main.Collect_Between.Max = tonumber(v) end })

        -- Pet
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
                            if CollectType == "All" then
                                for UID,PetData in pairs(OwnedPets) do
                                    if PetData and not PetData.IsBig then
                                        if PetData.RE then PetData.RE:FireServer("Claim") end
                                        CharacterRE:FireServer("Del",UID)
                                    end
                                end
                            elseif CollectType == "Match Pet" then
                                for UID,PetData in pairs(OwnedPets) do
                                    if PetData and not PetData.IsBig and Configuration.Pet.CollectPet_Pets[PetData.Type] then
                                        if PetData.RE then PetData.RE:FireServer("Claim") end
                                        CharacterRE:FireServer("Del",UID)
                                    end
                                end
                            elseif CollectType == "Match Mutation" then
                                for UID,PetData in pairs(OwnedPets) do
                                    if PetData and not PetData.IsBig and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                                        if PetData.RE then PetData.RE:FireServer("Claim") end
                                        CharacterRE:FireServer("Del",UID)
                                    end
                                end
                            elseif CollectType == "Match Pet&Mutation" then
                                for UID,PetData in pairs(OwnedPets) do
                                    if PetData and not PetData.IsBig and Configuration.Pet.CollectPet_Pets[PetData.Type] and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                                        if PetData.RE then PetData.RE:FireServer("Claim") end
                                        CharacterRE:FireServer("Del",UID)
                                    end
                                end
                            elseif CollectType == "Range" then
                                local minV = tonumber(Configuration.Pet.CollectPet_Between.Min) or 0
                                local maxV = tonumber(Configuration.Pet.CollectPet_Between.Max) or math.huge
                                for UID, PetData in pairs(OwnedPets) do
                                    if PetData and not PetData.IsBig then
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
        Tabs.Pet:AddDropdown("CollectPet Pets",{ Title = "Collect Pets", Values = Pets_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.CollectPet_Pets = v end })
        Tabs.Pet:AddDropdown("CollectPet Mutations",{ Title = "Collect Mutations", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Pet.CollectPet_Mutations = v end })
        Tabs.Pet:AddInput("CollectCash_Num1",{ Title = "Min Coin", Default = 100000, Numeric = true, Finished = false, Callback = function(v) Configuration.Pet.CollectPet_Between.Min = tonumber(v) end })
        Tabs.Pet:AddInput("CollectCash_Num2",{ Title = "Max Coin", Default = 1000000, Numeric = true, Finished = false, Callback = function(v) Configuration.Pet.CollectPet_Between.Max = tonumber(v) end })
        -- ====== Pet > Auto Place Pet UI ======
        Tabs.Pet:AddSection("Auto Place Pet Settings")

        Tabs.Pet:AddDropdown("PlacePet Mode", {
            Title = "Place Mode",
            Values = {"All","Match","Range"}, -- ▼▼ NEW: เพิ่ม "Range"
            Multi = false,
            Default = "All",
            Callback = function(v)
                Configuration.Pet.PlacePet_Mode = v
            end
        })

        Tabs.Pet:AddDropdown("PlacePet Types", {
            Title = "Place Types (Match)",
            Description = "เลือกประเภทสัตว์ที่จะวาง (ใช้เมื่อ Place Mode = Match)",
            Values = Pets_InGame,
            Multi = true,
            Default = {},
            Callback = function(v)
                Configuration.Pet.PlacePet_Types = v
            end
        })

        Tabs.Pet:AddDropdown("PlacePet Mutations", {
            Title = "Place Mutations (Match)",
            Description = "เลือกมิวเทชันที่จะวาง (ใช้เมื่อ Place Mode = Match)",
            Values = Mutations_InGame,
            Multi = true,
            Default = {},
            Callback = function(v)
                Configuration.Pet.PlacePet_Mutations = v
            end
        })

        Tabs.Pet:AddSlider("AutoPlacePet Delay", {
            Title = "Auto Place Pet Delay",
            Description = "ดีเลย์การพยายามวางสัตว์ในแต่ละครั้ง (วิ)",
            Default = 1,
            Min = 0.1,
            Max = 5,
            Rounding = 1,
            Callback = function(v)
                Configuration.Pet.AutoPlacePet_Delay = v
            end
        })

        -- ▼▼ NEW: ช่องกรอก Min/Max สำหรับโหมด Range
        Tabs.Pet:AddInput("PlacePet_MinIncome", {
            Title = "Min income/s (Range)",
            Default = tostring(Configuration.Pet.PlacePet_Between.Min or 0),
            Numeric = true, Finished = true,
            Callback = function(v)
                local n = tonumber(v) or 0
                Configuration.Pet.PlacePet_Between.Min = n
            end
        })
        Tabs.Pet:AddInput("PlacePet_MaxIncome", {
            Title = "Max income/s (Range)",
            Default = tostring(Configuration.Pet.PlacePet_Between.Max or 1000000),
            Numeric = true, Finished = true,
            Callback = function(v)
                local n = tonumber(v) or math.huge
                Configuration.Pet.PlacePet_Between.Max = n
            end
        })
        -- ====== /Auto Place Pet UI ======
        -- Egg
        Tabs.Egg:AddSection("Main")
        Tabs.Egg:AddToggle("Auto Hatch",{ Title = "Auto Hatch", Default = false, Callback = function(v) Configuration.Egg.AutoHatch = v end })
        Tabs.Egg:AddToggle("Auto Egg",{ Title = "Auto Buy Egg", Default = false, Callback = function(v) Configuration.Egg.AutoBuyEgg = v end })
        Tabs.Egg:AddToggle("Auto Place Egg",{ Title = "Auto Place Egg", Default = false, Callback = function(v) Configuration.Egg.AutoPlaceEgg = v end })
        Tabs.Egg:AddSection("Settings")
        Tabs.Egg:AddSlider("AutoHatch Delay",{ Title = "Hatch Delay", Default = 15, Min = 15, Max = 60, Rounding = 0, Callback = function(v) Configuration.Egg.Hatch_Delay = v end })
        Tabs.Egg:AddSlider("AutoBuyEgg Delay",{ Title = "Auto Buy Egg Delay", Default = 1, Min = 0.1, Max = 3, Rounding = 1, Callback = function(v) Configuration.Egg.AutoBuyEgg_Delay = v end })
        Tabs.Egg:AddSlider("AutoPlaceEgg Delay",{ Title = "Auto Place Egg Delay", Default = 1, Min = 0.1, Max = 5, Rounding = 1, Callback = function(v) Configuration.Egg.AutoPlaceEgg_Delay = v end })
        Tabs.Egg:AddDropdown("Egg Type",{ Title = "Types", Values = Eggs_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Egg.Types = v end })
        Tabs.Egg:AddDropdown("Egg Mutations",{ Title = "Mutations", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Egg.Mutations = v end })

        -- Shop
        Tabs.Shop:AddSection("Main")
        Tabs.Shop:AddToggle("Auto BuyFood",{ Title = "Auto Buy Food", Default = false, Callback = function(v) Configuration.Shop.Food.AutoBuy = v end })
        Tabs.Shop:AddSection("Settings")
        Tabs.Shop:AddSlider("AutoBuyFood Delay",{ Title = "Auto Buy Food Delay", Default = 1, Min = 0.1, Max = 3, Rounding = 1, Callback = function(v) Configuration.Shop.Food.AutoBuy_Delay = v end })
        Tabs.Shop:AddDropdown("Foods Dropdown",{ Title = "Foods", Values = PetFoods_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Shop.Food.Foods = v end })

        -- Event
        Tabs.Event:AddParagraph({ Title = "Event Information", Content = string.format("Current Event : %s",EventName) })
        Tabs.Event:AddSection("Main")
        Tabs.Event:AddToggle("Auto Claim Event Quest",{ Title = "Auto Claim", Default = false, Callback = function(v) Configuration.Event.AutoClaim = v end })
        Tabs.Event:AddSection("Settings")
        Tabs.Event:AddSlider("Event_AutoClaim Delay",{ Title = "Auto Claim Delay", Default = 3, Min = 3, Max = 30, Rounding = 0, Callback = function(v) Configuration.Event.AutoClaim_Delay = v end })

        -- Players
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
                            Configuration.Waiting = true
                            if GiftType == "All_Pets" then
                                for _,PetData in pairs(OwnedPetData:GetChildren()) do
                                    if PetData and not PetData:GetAttribute("D") then
                                        CharacterRE:FireServer("Focus",PetData.Name) task.wait(0.75)
                                        GiftRE:FireServer(GiftPlayer) task.wait(0.75)
                                    end
                                end
                            elseif GiftType == "Match Pet" then
                                for _,PetData in pairs(OwnedPetData:GetChildren()) do
                                    if PetData then
                                        local petType = PetData:GetAttribute("T")
                                        if petType and Configuration.Players.Pet_Type[petType] then
                                            CharacterRE:FireServer("Focus", PetData.Name) task.wait(0.75)
                                            GiftRE:FireServer(GiftPlayer) task.wait(0.75)
                                        end
                                    end
                                end
                            elseif GiftType == "All_Foods" then
                                for FoodName,FoodAmount in pairs(InventoryData:GetAttributes()) do
                                    if FoodName and table.find(PetFoods_InGame,FoodName) then
                                        for i = 1,FoodAmount do
                                            CharacterRE:FireServer("Focus",FoodName) task.wait(0.75)
                                            GiftRE:FireServer(GiftPlayer) task.wait(0.75)
                                        end
                                    end
                                end
                            elseif GiftType == "Select_Foods" then
                                -- ส่งเฉพาะชนิดที่เลือก พร้อมจำนวนต่อชนิดจาก Food_Amounts (ดีฟอลต์ 1)
                                if not InventoryData then InventoryData = Data:FindFirstChild("Asset") end
                                local inv = InventoryData and InventoryData:GetAttributes() or {}
                                local selected = Configuration.Players.Food_Selected or {}
                                local amounts  = Configuration.Players.Food_Amounts  or {}
                            
                                for foodName, picked in pairs(selected) do
                                    if picked and table.find(PetFoods_InGame, foodName) then
                                        local have = tonumber(inv[foodName] or 0)
                                        local want = tonumber(amounts[foodName] or 1)
                                        local sendN = math.max(0, math.min(have, want))
                            
                                        for i = 1, sendN do
                                            CharacterRE:FireServer("Focus", foodName)
                                            task.wait(0.75)
                                            GiftRE:FireServer(GiftPlayer)
                                            task.wait(0.75)
                                        end
                                    end
                                end                            
                            elseif GiftType == "All_Eggs" then
                                for _,Egg in pairs(OwnedEggData:GetChildren()) do
                                    if Egg and not Egg:FindFirstChild("DI") then
                                        CharacterRE:FireServer("Focus",Egg.Name) task.wait(0.75)
                                        GiftRE:FireServer(GiftPlayer) task.wait(0.75)
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
        Tabs.Players:AddDropdown("GiftType Dropdown",{ Title = "Gift Type", Values = {"All_Pets","Match Pet","Match Pet&Mutation","All_Foods","Select_Foods","All_Eggs"}, Multi = false, Default = "", Callback = function(v) Configuration.Players.SelectType = v end })
        -- เลือกชนิดอาหารที่จะส่ง (ใช้กับ Select_Foods)
        Tabs.Players:AddDropdown("Gift Foods", {
            Title = "Foods to Gift (Select)",
            Description = "เลือกชนิดอาหารที่จะส่ง (ใช้เมื่อ Gift Type = Select_Foods)",
            Values = PetFoods_InGame,
            Multi = true,
            Default = {},
            Callback = function(v)
                Configuration.Players.Food_Selected = v   -- map boolean
            end,
        })

        -- เลือกชนิดที่จะ “ตั้งจำนวน”
        local PickFoodDD = Tabs.Players:AddDropdown("Pick Food Amount", {
            Title = "Pick Food to set amount",
            Values = PetFoods_InGame,
            Multi = false,
            Default = "",
            Callback = function(v)
                Configuration.Players.Food_AmountPick = v
            end,
        })

        -- กรอกจำนวนสำหรับชนิดที่เลือก
        Tabs.Players:AddInput("Set Food Amount", {
            Title = "Set Amount for picked food",
            Default = 1,
            Placeholder = "จำนวนสำหรับชนิดที่เลือก",
            Numeric = true,
            Finished = true,
            Callback = function(v)
                local food = Configuration.Players.Food_AmountPick
                if food and food ~= "" then
                    local n = math.max(1, math.floor(tonumber(v) or 1))
                    Configuration.Players.Food_Amounts[food] = n
                end
            end,
        })

        -- ปุ่มลัด: ตั้งจำนวนเริ่มต้น (1) ให้ทุกชนิดที่เลือกไว้
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

        Tabs.Players:AddDropdown("Pet Type",{ Title = "Select Pet Type", Values = Pets_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Players.Pet_Type = v end })
        Tabs.Players:AddDropdown("Pet Mutations",{ Title = "Select Mutations", Values = Mutations_InGame, Multi = true, Default = {}, Callback = function(v) Configuration.Players.Pet_Mutations = v end })
        table.insert(EnvirontmentConnections,Players_List_Updated.Event:Connect(function(newList) Players_Dropdown:SetValues(newList) end))

        -- About/Settings
        Tabs.About:AddParagraph({ Title = "Credit", Content = "Script create by DemiGodz" })
        Tabs.Settings:AddToggle("AntiAFK",{ Title = "Anti AFK", Default = false, Callback = function(v)
            ServerReplicatedDict:SetAttribute("AFK_THRESHOLD",(v == false and 1080 or v == true and 99999999999))
            Configuration.AntiAFK = v
        end })
    end

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

   -- ========= Helpers for placing (Egg/Pet) =========
   -- ▼▼ NEW: อ่านค่า "เงินต่อวิ" ของสัตว์ในกระเป๋า จาก PlayerGui UI ตาม UID
  -- อ่านค่า "เงินต่อวิ" ของสัตว์ในกระเป๋า จาก PlayerGui UI ตาม UID
local function GetInventoryIncomePerSecByUID(uid: string)
    if not uid or uid == "" then return nil end

    local pg = Player:FindFirstChild("PlayerGui")
    if not pg then return nil end

    -- path: PlayerGui.ScreenStorage.Frame.ContentPet.ScrollingFrame[UID].BTN.Stat.Price.Value
    local screenStorage = pg:FindFirstChild("ScreenStorage")
    if not screenStorage then return nil end
    local frame = screenStorage:FindFirstChild("Frame")
    if not frame then return nil end
    local contentPet = frame:FindFirstChild("ContentPet")
    if not contentPet then return nil end
    local scrolling = contentPet:FindFirstChild("ScrollingFrame")
    if not scrolling then return nil end

    -- หา item ตามชื่อ UID (ถ้าไม่เจอ ลองวนหาเผื่อมีการ wrap)
    local item = scrolling:FindFirstChild(uid)
    if not item then
        for _, ch in ipairs(scrolling:GetChildren()) do
            if ch.Name == uid then item = ch break end
        end
    end
    if not item then return nil end

    -- ลึกลงไปหา BTN/Stat/Price
    local btn  = item:FindFirstChild("BTN") or item:FindFirstChildWhichIsA("Frame")
    if not btn then return nil end
    local stat = btn:FindFirstChild("Stat") or btn:FindFirstChildWhichIsA("Frame")
    if not stat then return nil end
    local price = stat:FindFirstChild("Price") or stat:FindFirstChildWhichIsA("Frame")
    if not price then return nil end

    -- 1) กรณีมี Value เป็น NumberValue/IntValue/StringValue
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

    -- 2) กรณีเป็น TextLabel/TextButton หรืออื่นๆ ที่มี property .Text เช่น "$12,345 / sec"
    local function readText(inst)
        local ok, txt = pcall(function() return inst.Text end) -- << ไม่ใช้ rawget
        if ok and txt then
            local n = tonumber((tostring(txt):gsub("[^%d%.]", "")))
            if n then return n end
        end
        return nil
    end
    -- ลองตรงๆ ที่ Price เอง
    local n = readText(price)
    if n then return n end
    -- ลองหา TextLabel/TextButton ข้างใน
    local textLike = price:FindFirstChildWhichIsA("TextLabel") or price:FindFirstChildWhichIsA("TextButton")
    if textLike then
        n = readText(textLike)
        if n then return n end
    end
    -- เผื่อซ้อนลึก: วนหา TextLabel ใดๆ
    for _, d in ipairs(price:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            n = readText(d)
            if n then return n end
        end
    end

    return nil
end


local vector = vector or { create = function(x,y,z) return Vector3.new(x,y,z) end }

local function _ck(v) return v and (tostring(v.X)..","..tostring(v.Z)) or nil end

-- กริดว่าง: จากสัตว์/ไข่ที่วางแล้ว (ดูทั้ง workspace และ Data)
local function _occupied()
    local occ = {}
    for _, P in pairs(OwnedPets) do
        if P and P.GridCoord then occ[_ck(P.GridCoord)] = true end
    end
    for _, E in ipairs(OwnedEggData:GetChildren()) do
        local di = E:FindFirstChild("DI")
        if di then
            local v = Vector3.new(di:GetAttribute("X") or 0, di:GetAttribute("Y") or 0, di:GetAttribute("Z") or 0)
            occ[_ck(v)] = true
        end
    end
    return occ
end

local function GetFreeGridPos()
    local occ = _occupied()
    for _, g in ipairs(Grids) do
        if g.GridCoord and not occ[_ck(g.GridCoord)] then
            return g.GridPos
        end
    end
    return nil
end

-- snap ให้เป็นกึ่งกลาง และ raycast หา Y “พื้นจริง”
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

local function ensureNear(position, maxDist)
    local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if (hrp.Position - position).Magnitude > (maxDist or 12) then
        hrp.CFrame = CFrame.new(position + Vector3.new(0, 3.5, 0))
        task.wait(0.4)
    end
end

-- รอผลสำเร็จ: สำหรับไข่→มี DI, สำหรับสัตว์→โมเดลไปโผล่ใน workspace.Pets
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
        if OwnedPets[uid] ~= nil then return true end -- เรา map จาก workspace.Pets อยู่แล้ว
        task.wait(0.1)
    end
    return false
end
-- ========= /Helpers =========


    -- ===== Auto Feed Pet
    task.defer(function()
        local Data_OwnedPets = Data:WaitForChild("Pets",30)
        local PetRE = GameRemoteEvents:WaitForChild("PetRE")
        local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE")
        local FoodList = PetFoods_InGame
        while true and RunningEnvirontments do
            if Configuration.Pet.AutoFeed and not Configuration.Waiting and Configuration.Pet.AutoFeed_Type ~= "" then
                if not InventoryData then InventoryData = Data:FindFirstChild("Asset") end
                local Data_Inventory = InventoryData:GetAttributes()
                for _,petCfg in pairs(Data_OwnedPets:GetChildren()) do
                    local petModel = OwnedPets[petCfg.Name] or nil
                    if not (petModel and petModel.IsBig) then continue end
                    if petCfg and not petCfg:GetAttribute("Feed") then
                        local Food = (Configuration.Pet.AutoFeed_Type == "BestFood" and (function()
                            local best = ""
                            for i,v in ipairs(FoodList) do if Data_Inventory[v] then best = v end end
                            return best
                        end)() or Configuration.Pet.AutoFeed_Type == "SelectFood" and (function()
                            local best = ""
                            for i,v in ipairs(PetFoods_InGame) do if Configuration.Pet.AutoFeed_Foods[v] and Data_Inventory[v] then best = v end end
                            return best
                        end)())
                        if Food and Food ~= "" then
                            CharacterRE:FireServer("Focus",Food) task.wait(0.5)
                            PetRE:FireServer("Feed",petModel.UID) task.wait(0.5)
                            CharacterRE:FireServer("Focus")
                        end
                    end
                end
            end
            task.wait(Configuration.Pet.AutoFeed_Delay)
        end
    end)

    -- ===== Auto Collect Pet (ตามโหมดที่เลือก)
    task.defer(function()
        local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE",30)
        while true and RunningEnvirontments do
            if Configuration.Pet.CollectPet_Auto and not Configuration.Waiting and Configuration.Pet.CollectPet_Type ~= "All" then
                local CollectType = Configuration.Pet.CollectPet_Type
                if CollectType == "Match Pet" then
                    for UID,PetData in pairs(OwnedPets) do
                        if PetData and not PetData.IsBig and Configuration.Pet.CollectPet_Pets[PetData.Type] then
                            if PetData.RE then PetData.RE:FireServer("Claim") end
                            CharacterRE:FireServer("Del",UID)
                        end
                    end
                elseif CollectType == "Match Mutation" then
                    for UID,PetData in pairs(OwnedPets) do
                        if PetData and not PetData.IsBig and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                            if PetData.RE then PetData.RE:FireServer("Claim") end
                            CharacterRE:FireServer("Del",UID)
                        end
                    end
                elseif CollectType == "Match Pet&Mutation" then
                    for UID,PetData in pairs(OwnedPets) do
                        if PetData and not PetData.IsBig and Configuration.Pet.CollectPet_Pets[PetData.Type] and Configuration.Pet.CollectPet_Mutations[PetData.Mutate] then
                            if PetData.RE then PetData.RE:FireServer("Claim") end
                            CharacterRE:FireServer("Del",UID)
                        end
                    end
                elseif CollectType == "Range" then
                    local minV = tonumber(Configuration.Pet.CollectPet_Between.Min) or 0
                    local maxV = tonumber(Configuration.Pet.CollectPet_Between.Max) or math.huge
                    for UID,PetData in pairs(OwnedPets) do
                        if PetData and not PetData.IsBig then
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

    -- ===== Auto Hatch
    task.defer(function()
        local OwnedEggs = Data:WaitForChild("Egg")
        while true and RunningEnvirontments do
            if Configuration.Egg.AutoHatch then
                for _,egg in pairs(OwnedEggs:GetChildren()) do
                    local Hatchable = ((#egg:GetChildren() > 0) and egg:GetAttribute("D") and (ServerTime.Value >= egg:GetAttribute("D")))
                    if Hatchable then
                        local Egg = BlockFolder:FindFirstChild(egg.Name)
                        local RootPart = Egg and (Egg.PrimaryPart or Egg:FindFirstChild("RootPart"))
                        local RF = RootPart and RootPart:FindFirstChild("RF")
                        if RF then task.spawn(function() RF:InvokeServer("Hatch") end) end
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
        while true and RunningEnvirontments do
            if Configuration.Egg.AutoBuyEgg and not Configuration.Waiting then
                for _,egg in pairs(Egg_Belt) do
                    local EggType = egg.Type
                    local EggMutation = egg.Mutate
                    if (Configuration.Egg.Types[EggType]) and (Configuration.Egg.Mutations[EggMutation]) then
                        if RE then RE:FireServer("BuyEgg",egg.UID) end
                    end
                end
            end
            task.wait(Configuration.Egg.AutoBuyEgg_Delay)
        end
    end)

        -- ===== Auto Place Egg =====
    task.defer(function()
        local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE", 30)
        while true and RunningEnvirontments do
            if Configuration.Egg.AutoPlaceEgg and not Configuration.Waiting then
                -- เลือกไข่ยังไม่วาง + ผ่านฟิลเตอร์ (ว่าง = ผ่านทั้งหมด)
                local chosenEgg
                local typeOn = next(Configuration.Egg.Types) ~= nil
                local mutOn  = next(Configuration.Egg.Mutations) ~= nil
                for _, egg in ipairs(OwnedEggData:GetChildren()) do
                    if egg and not egg:FindFirstChild("DI") then
                        local t = egg:GetAttribute("T") or "BasicEgg"
                        local m = egg:GetAttribute("M") or "None"
                        local okT = (not typeOn) or Configuration.Egg.Types[t]
                        local okM = (not mutOn)  or Configuration.Egg.Mutations[m]
                        if okT and okM then chosenEgg = egg break end
                    end
                end

                if chosenEgg then
                    local grid = GetFreeGridPos()
                    if grid then
                        local dst = GroundAtGrid(grid)

                        -- เข้าใกล้จุด, โฟกัสถือไข่
                        ensureNear(dst, 12)
                        CharacterRE:FireServer("Focus", chosenEgg.Name)
                        task.wait(0.45)

                        -- ส่งแบบ args + unpack (ตามที่เกมใช้)
                        local args = { "Place", { DST = vector.create(dst.X, dst.Y, dst.Z), ID = chosenEgg.Name } }
                        print("Try place:", chosenEgg and chosenEgg.Name or petCfg and petCfg.Name, "DST:", dst)

                        CharacterRE:FireServer(unpack(args))

                        task.wait(0.2)
                        CharacterRE:FireServer("Focus") -- un-focus

                        -- ยืนยันผล
                        if not waitEggPlaced(chosenEgg, 3) then
                            warn("[AutoPlaceEgg] place not confirmed (no DI).")
                        end
                    end
                end
            end
            task.wait(Configuration.Egg.AutoPlaceEgg_Delay or 1.0)
        end
    end)


        -- ===== Auto Place Pet =====
        task.defer(function()
            local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE", 30)
    
            local function pickPet()
                local mode = Configuration.Pet.PlacePet_Mode
                local typeOn = (mode == "Match") and (next(Configuration.Pet.PlacePet_Types) ~= nil)
                local mutOn  = (mode == "Match") and (next(Configuration.Pet.PlacePet_Mutations) ~= nil)
    
                if mode == "Range" then
                    local minV = tonumber(Configuration.Pet.PlacePet_Between.Min) or 0
                    local maxV = tonumber(Configuration.Pet.PlacePet_Between.Max) or math.huge
    
                    -- เลือก “สัตว์ในกระเป๋า” (ยังไม่ถูกวาง => ไม่มีใน OwnedPets)
                    -- ที่ income/s จาก UI อยู่ในช่วง [minV, maxV]
                    for _, petCfg in ipairs(OwnedPetData:GetChildren()) do
                        local uid = petCfg.Name
                        if not OwnedPets[uid] then
                            local inc = GetInventoryIncomePerSecByUID(uid)
                            if inc and inc >= minV and inc <= maxV then
                                return petCfg
                            end
                        end
                    end
                    return nil
                end
    
                -- เดิม: All/Match
                for _, petCfg in ipairs(OwnedPetData:GetChildren()) do
                    local uid = petCfg.Name
                    if not OwnedPets[uid] then
                        if mode == "All" then
                            return petCfg
                        elseif mode == "Match" then
                            local t = petCfg:GetAttribute("T")
                            local m = petCfg:GetAttribute("M") or "None"
                            local okT = (not typeOn) or Configuration.Pet.PlacePet_Types[t]
                            local okM = (not mutOn)  or Configuration.Pet.PlacePet_Mutations[m]
                            if okT and okM then return petCfg end
                        end
                    end
                end
                return nil
            end
    
            while true and RunningEnvirontments do
                if Configuration.Pet.AutoPlacePet and not Configuration.Waiting then
                    local petCfg = pickPet()
                    if petCfg then
                        local grid = GetFreeGridPos()
                        if grid then
                            local dst = GroundAtGrid(grid)
    
                            ensureNear(dst, 12)
                            CharacterRE:FireServer("Focus", petCfg.Name)
                            task.wait(0.45)
    
                            local args = { "Place", { DST = vector.create(dst.X, dst.Y, dst.Z), ID = petCfg.Name } }
                            print("Try place:", petCfg and petCfg.Name, "DST:", dst)
                            CharacterRE:FireServer(unpack(args))
    
                            task.wait(0.2)
                            CharacterRE:FireServer("Focus")
    
                            if not waitPetPlaced(petCfg.Name, 3) then
                                warn("[AutoPlacePet] place not confirmed (no model/OwnedPets map).")
                            end
                        end
                    end
                end
                task.wait(Configuration.Pet.AutoPlacePet_Delay or 1.0)
            end
        end)
    

    -- ===== /Auto Place Pet =====


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

    -- ===== Cleanup
    Window.Root.Destroying:Once(function()
        RunningEnvirontments = false
        for _,connection in pairs(EnvirontmentConnections) do
            if connection then pcall(function() connection:Disconnect() end) end
        end
    end)

    SaveManager:LoadAutoloadConfig()
    getgenv().MeowyBuildAZoo = Window
end

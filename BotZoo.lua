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
            AutoFeed_Delay = 3, AutoFeed_Type = "",
            CollectPet_Type = "All", CollectPet_Auto = false,
            CollectPet_Mutations = {}, CollectPet_Pets = {},
            CollectPet_Delay = 5,
            CollectPet_Between = {["Min"] = 100000,["Max"] = 1000000},
        },
        Egg = {
            AutoHatch = false, Hatch_Delay = 15,
            AutoBuyEgg = false, AutoBuyEgg_Delay = 1,
            AutoPlaceEgg = false, AutoPlaceEgg_Delay = 1.0,
            Mutations = {}, Types = {},
        },
        Shop = { Food = { AutoBuy = false, AutoBuy_Delay = 1, Foods = {} } },
        Players = { SelectPlayer = "", SelectType = "", SendPet_Type = "All", Pet_Type = {}, Pet_Mutations = {} },
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
        Tabs.Players:AddDropdown("GiftType Dropdown",{ Title = "Gift Type", Values = {"All_Pets","Match Pet","Match Pet&Mutation","All_Foods","All_Eggs"}, Multi = false, Default = "", Callback = function(v) Configuration.Players.SelectType = v end })
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

    -- ===== Helpers Auto Place Egg
    local function CoordKey(v) if not v then return nil end return tostring(v.X)..","..tostring(v.Z) end
    local function BuildOccupiedCoordSet()
        local occ = {}
        -- จาก OwnedPets ที่แมปไว้ (เร็ว)
        for _, PetData in pairs(OwnedPets) do
            local g = PetData and PetData.GridCoord
            if g then occ[CoordKey(g)] = true end
        end
        -- จาก Data Egg (ถ้าไข่วางแล้วจะมี DI)
        for _, EggCfg in ipairs(OwnedEggData:GetChildren()) do
            local di = EggCfg:FindFirstChild("DI")
            if di then
                local gv = Vector3.new(di:GetAttribute("X") or 0, di:GetAttribute("Y") or 0, di:GetAttribute("Z") or 0)
                occ[CoordKey(gv)] = true
            end
        end
        return occ
    end
    local function GetFreeGridPos()
        local occ = BuildOccupiedCoordSet()
        for idx, gridData in ipairs(Grids) do
            local gc = gridData.GridCoord
            if gc then
                if not occ[CoordKey(gc)] then
                    return gridData.GridPos, idx
                end
            end
        end
        return nil
    end

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

    -- ===== Auto Place Egg (TP + Focus + Place) =====
    task.defer(function()
        local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE", 30)
        local function SurfaceFromGridPos(gridPos) return Vector3.new(gridPos.X, gridPos.Y + 12, gridPos.Z) end

        while true and RunningEnvirontments do
            if Configuration.Egg.AutoPlaceEgg and not Configuration.Waiting then
                -- เลือกไข่ที่ยังไม่ถูกวาง + ผ่านฟิลเตอร์ Type/Mutation
                local chosenEgg = nil
                for _, egg in ipairs(OwnedEggData:GetChildren()) do
                    if egg and (not egg:FindFirstChild("DI")) then
                        local eggType = egg:GetAttribute("T") or "BasicEgg"
                        local eggMut  = egg:GetAttribute("M") or "None"
                        local typeOK = (next(Configuration.Egg.Types) == nil) or (Configuration.Egg.Types[eggType] == true)
                        local mutOK  = (next(Configuration.Egg.Mutations) == nil) or (Configuration.Egg.Mutations[eggMut] == true)
                        if typeOK and mutOK then chosenEgg = egg break end
                    end
                end

                if chosenEgg then
                    local gridPos = GetFreeGridPos()
                    if gridPos then
                        local surfacePosition = SurfaceFromGridPos(gridPos)

                        -- TP ไปที่จุดวาง (ใกล้ ๆ)
                        local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            hrp.CFrame = CFrame.new(surfacePosition + Vector3.new(0, 4, 0))
                            task.wait(0.25)
                        end

                        -- ถือไข่ในมือ (Focus)
                        CharacterRE:FireServer("Focus", chosenEgg.Name)
                        task.wait(0.25)

                        -- Place
                        local ok, err = pcall(function()
                            CharacterRE:FireServer("Place", {
                                DST = vector.create(surfacePosition.X, surfacePosition.Y, surfacePosition.Z),
                                ID  = chosenEgg.Name
                            })
                        end)

                        -- ปลด Focus
                        task.wait(0.15)
                        CharacterRE:FireServer("Focus")

                        if not ok then
                            warn("[AutoPlaceEgg] Place failed: " .. tostring(err))
                        else
                            task.wait(0.35) -- เผื่อเซิร์ฟอัปเดต
                        end
                    else
                        task.wait(0.6) -- ไม่มีที่ว่าง
                    end
                end
            end
            task.wait(Configuration.Egg.AutoPlaceEgg_Delay or 1.0)
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

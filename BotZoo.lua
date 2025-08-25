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
    
    local Eggs_InGame = require(InGameConfig:WaitForChild("ResEgg"))["__index"]
    local Mutations_InGame = require(InGameConfig:WaitForChild("ResMutate"))["__index"]
    local PetFoods_InGame = require(InGameConfig:WaitForChild("ResPetFood"))["__index"]
    local Pets_InGame = require(InGameConfig:WaitForChild("ResPet"))["__index"]
    local Grids = {}
    for _,grid in pairs(Island:GetChildren()) do
        if grid:IsA("BasePart") and string.find(tostring(grid),"Farm") then
            table.insert(Grids,{GridCoord = grid:GetAttribute("IslandCoord"),GridPos = grid.CFrame.Position})
        end
    end
    
    local EventTaskData;
    local ResEvent;
    local EventName = "None";
    for _,Data_Folder in pairs(Data:GetChildren()) do
        local IsEventTaskData = (tostring(Data_Folder):match("^(.*)EventTaskData$"))
        if IsEventTaskData then
            EventTaskData = Data_Folder
            break
        end
    end
    for _,v in pairs(ReplicatedStorage:GetChildren()) do
        local IsEventData = (tostring(v):match("^(.*)Event$"))
        if IsEventData then
            ResEvent = v
            EventName = IsEventData
            break
        end
    end
    local InventoryData = Data:WaitForChild("Asset",30)
    local Players_List_Updated = Instance.new("BindableEvent")
    table.insert(EnvirontmentConnections,Players.PlayerRemoving:Connect(function(plr)
        local plr = table.find(Players_InGame,plr.Name)
        if plr then table.remove(Players_InGame,plr) end
        Players_List_Updated:Fire(Players_InGame)
    end))
    table.insert(EnvirontmentConnections,Players.PlayerAdded:Connect(function(plr)
        table.insert(Players_InGame,plr.Name)
        Players_List_Updated:Fire(Players_InGame)
    end))
    for _,plr in pairs(Players:GetPlayers()) do
        --if plr == Player then continue end
        table.insert(Players_InGame,plr.Name)
    end
    
    local OwnedPets = {}
    local Egg_Belt = {}
    table.insert(EnvirontmentConnections,Egg_Belt_Folder.ChildRemoved:Connect(function(egg)
        task.wait(0.1)
        local eggUID = tostring(egg) or "None"
        if egg and Egg_Belt[eggUID] then
            Egg_Belt[eggUID] = nil
        end
    end))
    table.insert(EnvirontmentConnections,Egg_Belt_Folder.ChildAdded:Connect(function(egg)
        task.wait(0.1)
        local eggUID = tostring(egg) or "None"
        if egg then
            Egg_Belt[eggUID] = {UID = eggUID,Mutate = (egg:GetAttribute("M") or "None"),Type = (egg:GetAttribute("T") or "BasicEgg")}
        end
    end))
    for _,egg in pairs(Egg_Belt_Folder:GetChildren()) do
        task.spawn(pcall,function()
            local eggUID = tostring(egg) or "None"
            if egg then
                Egg_Belt[eggUID] = {UID = eggUID,Mutate = (egg:GetAttribute("M") or "None"),Type = (egg:GetAttribute("T") or "BasicEgg")}
            end
        end)
    end
    
    table.insert(EnvirontmentConnections,Pet_Folder.ChildRemoved:Connect(function(pet)
        task.wait(0.1)
        local petUID = tostring(pet) or "None"
        if pet and OwnedPets[petUID] then
            OwnedPets[petUID] = nil
        end
    end))
    local function GetCash(TXT)
        if TXT then
            local cash = string.gsub(TXT,"[$,]","")
            return tonumber(cash)
        end
        return 0
    end
    local function GetFreeGrid()
        local occupiedGrids = {}
        for _, pet in pairs(Pets) do
            if pet.GridCoord then
                local key = pet.GridCoord.X .. "," .. pet.GridCoord.Z
                occupiedGrids[key] = true
            end
        end
        for _, egg in pairs(Eggs) do
            if egg.GridCoord then
                local key = egg.GridCoord.X .. "," .. egg.GridCoord.Z
                occupiedGrids[key] = true
            end
        end
        for index, gridData in pairs(Grids) do
            if gridData.GridCoord then
                local key = gridData.GridCoord.X .. "," .. gridData.GridCoord.Z
                if not occupiedGrids[key] then
                    return gridData.GridPos, index
                end
            end
        end
        
        return nil
    end
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
        if pet and pet:GetAttribute("UserId") == PlayerUserID then
            if not petPrimaryPart then petPrimaryPart = pet.PrimaryPart or pet:FindFirstChild("RootPart") or pet:WaitForChild("RootPart") end
            OwnedPets[petUID] = setmetatable({GridCoord = GridCoord,UID = petUID,Type = (petPrimaryPart:GetAttribute("Type")),Mutate = (petPrimaryPart:GetAttribute("Mutate")),Model = pet,RootPart = (petPrimaryPart),RE = (petPrimaryPart and petPrimaryPart:FindFirstChild("RE",true)),IsBig = (petPrimaryPart and (petPrimaryPart:GetAttribute("BigValue") ~= nil))},{__index = (function(tb,ind) if ind == "Coin" then return (CashTXT and GetCash(CashTXT.Text)) end return rawget(tb,ind) end)})
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
            if pet and IsOwned then
                OwnedPets[petUID] = setmetatable({GridCoord = GridCoord,UID = petUID,Type = (petPrimaryPart:GetAttribute("Type")),Mutate = (petPrimaryPart:GetAttribute("Mutate")),Model = pet,RootPart = (petPrimaryPart),RE = (petPrimaryPart and petPrimaryPart:FindFirstChild("RE",true)),IsBig = (petPrimaryPart and (petPrimaryPart:GetAttribute("BigValue") ~= nil))},{__index = (function(tb,ind) if ind == "Coin" then return (CashTXT and GetCash(CashTXT.Text)) end return rawget(tb,ind) end)})
            end
        end)
    end
    
    local Configuration = {
        Main = {
            AutoCollect = false,
            Collect_Delay = 5,
            Collect_Type = "Delay",
            Collect_Between = {["Min"] = 100000,["Max"] = 1000000},
        },
        Pet = {
            AutoFeed = false,
            AutoFeed_Foods = {},
            AutoFeed_Delay = 3,
            AutoFeed_Type = "",
            CollectPet_Type = "All",
            CollectPet_Auto = false,
            CollectPet_Mutations = {},
            CollectPet_Pets = {},
            CollectPet_Delay = 5,
        },
        Egg = {
            AutoHatch = false,
            Hatch_Delay = 15,
            AutoBuyEgg = false,
            AutoBuyEgg_Delay = 1,
            Mutations = {},
            Types = {},
        },
        Shop = {
            Food = {
                AutoBuy = false,
                AutoBuy_Delay = 1,
                Foods = {},
            },
        },
        Players = {
            SelectPlayer = "",
            SelectType = "",
            SendPet_Type = "All",
            Pet_Type = {},
            Pet_Mutations = {},
        },
        Event = {
            AutoClaim = false,
            AutoClaim_Delay = 3,
        },
        AntiAFK = false,
        Waiting = false,
    }
    
    local Window = Fluent:CreateWindow({
        Title = GameName,
        SubTitle = "by Meowy",
        TabWidth = 160,
        Size = UDim2.fromOffset(522, 414),
        Acrylic = true,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.LeftControl
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
        -- \\ Main Tab // --
        Tabs.Main:AddSection("Main")
        local AutoCollect_Toggle = Tabs.Main:AddToggle("AutoCollect",{
            Title = "Auto Collect",
            Default = false,
            Callback = function(Value)
                Configuration.Main.AutoCollect = Value
            end})
        Tabs.Main:AddSection("Settings")
        local AutoCollect_Delay = Tabs.Main:AddSlider("AutoCollect Delay", {
            Title = "Collect Delay",
            Description = "Set Collect Delay",
            Default = 5,
            Min = 1,
            Max = 30,
            Rounding = 0,
            Callback = function(Value)
                Configuration.Main.Collect_Delay = Value
            end
        })
        Tabs.Main:AddDropdown("CollectCash Type", {
            Title = "Select Type",
            Values = {"Delay","Between"},
            Multi = false,
            Default = "Delay",
            Callback = function(Value)
                Configuration.Main.Collect_Type = Value
            end,
        })
        Tabs.Main:AddInput("CollectCash_Num1", {
            Title = "Min Coin",
            Default = 100000,
            Placeholder = "Input Number",
            Numeric = true, -- Only allows numbers
            Finished = false, -- Only calls callback when you press enter
            Callback = function(Value)
                Configuration.Main.Collect_Between["Min"] = tonumber(Value)
            end
        })
        Tabs.Main:AddInput("CollectCash_Num2", {
            Title = "Max Coin",
            Default = 1000000,
            Placeholder = "Input Number",
            Numeric = true, -- Only allows numbers
            Finished = false, -- Only calls callback when you press enter
            Callback = function(Value)
                Configuration.Main.Collect_Between["Max"] = tonumber(Value)
            end
        })
        -- \\ Pet Tab // --
        Tabs.Pet:AddSection("Main")
        local AutoFeed_Toggle = Tabs.Pet:AddToggle("Auto Feed",{
            Title = "Auto Feed",
            Default = false,
            Callback = function(Value)
                Configuration.Pet.AutoFeed = Value
            end})
        local AutoCollectPet_Toggle = Tabs.Pet:AddToggle("Auto Collect Pet",{
            Title = "Auto Collect Pet",
            Description = "Auto Collect Pet with selected type (All Pet Type will not work with this)",
            Default = false,
            Callback = function(Value)
                Configuration.Pet.CollectPet_Auto = Value
            end})
        Tabs.Pet:AddButton({
            Title = "Collect Pet",
            Description = "Collect Pets with Collect Pet Type (this will not collect big pet)",
            Callback = function()
                Window:Dialog({
                    Title = "Collect Pet Alert",
                    Content = "Are you sure?",
                    Buttons = {
                        {
                            Title = "Yes",
                            Callback = function()
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
                                end
                            end
                        },
                        {
                            Title = "No",
                            Callback = function()
                                
                            end
                        }
                    }
                })
            end
        })
        Tabs.Pet:AddSection("Settings")
        Tabs.Pet:AddSlider("AutoFeed Delay", {
            Title = "Feed Delay",
            Description = "Set Feed Delay",
            Default = 3,
            Min = 3,
            Max = 30,
            Rounding = 0,
            Callback = function(Value)
                Configuration.Pet.AutoFeed_Delay = Value
            end
        })
        local AutoHatch_Delay = Tabs.Pet:AddSlider("AutoCollectPet Delay", {
            Title = "Auto Collect Pet Delay",
            Description = "Set Auto Collect Pet Delay",
            Default = 5,
            Min = 5,
            Max = 60,
            Rounding = 0,
            Callback = function(Value)
                Configuration.Pet.CollectPet_Delay = Value
            end
        })
        Tabs.Pet:AddDropdown("Pet Feed_Type", {
            Title = "Select Type",
            Values = {"BestFood","SelectFood"},
            Multi = false,
            Default = "",
            Callback = function(Value)
                Configuration.Pet.AutoFeed_Type = Value
            end,
        })
        Tabs.Pet:AddDropdown("Pet Feed_Food", {
            Title = "Select Foods",
            Values = PetFoods_InGame,
            Multi = true,
            Default = {},
            Callback = function(Value)
                Configuration.Pet.AutoFeed_Foods = Value
            end,
        })
        Tabs.Pet:AddDropdown("CollectPet Type", {
            Title = "Collect Pet Type",
            Description = "Select Collect Pet Type for Auto/Manual Collect Pet and Collect Pet",
            Values = {"All","Match Pet","Match Mutation","Match Pet&Mutation"},
            Multi = false,
            Default = "All",
            Callback = function(Value)
                Configuration.Pet.CollectPet_Type = Value
            end,
        })
        Tabs.Pet:AddDropdown("CollectPet Pets", {
            Title = "Collect Pets",
            Description = "Collect Specific Pets for Auto/Manual Collect Pet",
            Values = Pets_InGame,
            Multi = true,
            Default = {},
            Callback = function(Value)
                Configuration.Pet.CollectPet_Pets = Value
            end,
        })
        Tabs.Pet:AddDropdown("CollectPet Mutations", {
            Title = "Collect Mutations",
            Description = "Collect Pets with Specific Mutations for Auto/Manual Collect Pet",
            Values = Mutations_InGame,
            Multi = true,
            Default = {},
            Callback = function(Value)
                Configuration.Pet.CollectPet_Mutations = Value
            end,
        })
    
        -- \\ Egg Tab // --
        local EggTabMain = Tabs.Egg:AddSection("Main")
        local AutoHatch_Toggle = Tabs.Egg:AddToggle("Auto Hatch",{
            Title = "Auto Hatch",
            Default = false,
            Callback = function(Value)
                Configuration.Egg.AutoHatch = Value
            end})
        local AutoBuyEgg_Toggle = Tabs.Egg:AddToggle("Auto Egg",{
            Title = "Auto Buy Egg",
            Default = false,
            Callback = function(Value)
                Configuration.Egg.AutoBuyEgg = Value
            end})
        local EggTabSettings = Tabs.Egg:AddSection("Settings")
        local AutoHatch_Delay = Tabs.Egg:AddSlider("AutoHatch Delay", {
            Title = "Hatch Delay",
            Description = "Set Auto Hatch Delay",
            Default = 15,
            Min = 15,
            Max = 60,
            Rounding = 0,
            Callback = function(Value)
                Configuration.Egg.Hatch_Delay = Value
            end
        })
        local AutoBuyEgg_Delay = Tabs.Egg:AddSlider("AutoBuyEgg Delay", {
            Title = "Auto Buy Egg Delay",
            Description = "Set Auto Buy Egg Delay",
            Default = 1,
            Min = 0.1,
            Max = 3,
            Rounding = 1,
            Callback = function(Value)
                Configuration.Egg.AutoBuyEgg_Delay = Value
            end
        })
        local EggType_Dropdown = Tabs.Egg:AddDropdown("Egg Type", {
            Title = "Types",
            Values = Eggs_InGame,
            Multi = true,
            Default = {},
            Callback = function(Value)
                Configuration.Egg.Types = Value
            end,
        })
        local Mutations_Dropdown = Tabs.Egg:AddDropdown("Egg Mutations", {
            Title = "Mutations",
            Values = Mutations_InGame,
            Multi = true,
            Default = {},
            Callback = function(Value)
                Configuration.Egg.Mutations = Value
            end,
        })
        -- \\ Shop Tab // --
        Tabs.Shop:AddSection("Main")
        local AutoBuyFood_Toggle = Tabs.Shop:AddToggle("Auto BuyFood",{
            Title = "Auto Buy Food",
            Default = false,
            Callback = function(Value)
                Configuration.Shop.Food.AutoBuy = Value
            end})
        Tabs.Shop:AddSection("Settings")
        local AutoBuyFood_Delay = Tabs.Shop:AddSlider("AutoBuyFood Delay", {
            Title = "Auto Buy Food Delay",
            Description = "Set Auto Buy Food Delay",
            Default = 1,
            Min = 0.1,
            Max = 3,
            Rounding = 1,
            Callback = function(Value)
                Configuration.Shop.Food.AutoBuy_Delay = Value
            end
        })
        local Foods_Dropdown = Tabs.Shop:AddDropdown("Foods Dropdown", {
            Title = "Foods",
            Values = PetFoods_InGame,
            Multi = true,
            Default = {},
            Callback = function(Value)
                Configuration.Shop.Food.Foods = Value
            end,
        })
        -- \\ Event Tab // --
        Tabs.Event:AddParagraph({
            Title = "Event Information",
            Content = string.format("Current Event : %s",EventName),
        })
        Tabs.Event:AddSection("Main")
        Tabs.Event:AddToggle("Auto Claim Event Quest",{
            Title = "Auto Claim",
            Description = "Auto Claim Event Quests",
            Default = false,
            Callback = function(Value)
                Configuration.Event.AutoClaim = Value
            end
        })
        Tabs.Event:AddSection("Settings")
        Tabs.Event:AddSlider("Event_AutoClaim Delay", {
            Title = "Auto Claim Delay",
            Description = "Set Auto Claim Quest Delay",
            Default = 3,
            Min = 3,
            Max = 30,
            Rounding = 0,
            Callback = function(Value)
                Configuration.Event.AutoClaim_Delay = Value
            end
        })
        -- \\ Players Tab // --
        Tabs.Players:AddSection("Main")
        Tabs.Players:AddButton({
            Title = "Send Gift",
            Description = "Send Gift",
            Callback = function()
                Window:Dialog({
                    Title = "Send Gift Alert",
                    Content = "Are you sure?",
                    Buttons = {
                        {
                            Title = "Yes",
                            Callback = function()
                                local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE")
                                local GiftRE = GameRemoteEvents:WaitForChild("GiftRE")
                                local GiftType = Configuration.Players.SelectType
                                local GiftPlayer = Players:FindFirstChild(Configuration.Players.SelectPlayer)
                                if not GiftPlayer then return end
                                Configuration.Waiting = true
                                if GiftType == "All_Pets" then
                                    for _,PetData in pairs(OwnedPetData:GetChildren()) do
                                        if PetData and not PetData:GetAttribute("D") then
                                            CharacterRE:FireServer("Focus",PetData.Name)
                                            task.wait(0.75)
                                            GiftRE:FireServer(GiftPlayer)
                                            task.wait(0.75)
                                        end
                                    end
                                elseif GiftType == "Match Pet" then
                                    for _,PetData in pairs(OwnedPetData:GetChildren()) do
                                        if PetData and Configuration.Players.Pet_Type[PetData.Type] then
                                            CharacterRE:FireServer("Focus",PetData.Name)
                                            task.wait(0.75)
                                            GiftRE:FireServer(GiftPlayer)
                                            task.wait(0.75)
                                        end
                                    end
                                elseif GiftType == "All_Foods" then
                                    for FoodName,FoodAmount in pairs(InventoryData:GetAttributes()) do
                                        if FoodName and table.find(PetFoods_InGame,FoodName) then
                                            for i = 1,FoodAmount do
                                                CharacterRE:FireServer("Focus",FoodName)
                                                task.wait(0.75)
                                                GiftRE:FireServer(GiftPlayer)
                                                task.wait(0.75)
                                            end
                                        end
                                    end
                                elseif GiftType == "All_Eggs" then
                                    for _,Egg in pairs(OwnedEggData:GetChildren()) do
                                        if Egg and not Egg:FindFirstChild("DI") then
                                            CharacterRE:FireServer("Focus",Egg.Name)
                                            task.wait(0.75)
                                            GiftRE:FireServer(GiftPlayer)
                                            task.wait(0.75)
                                        end
                                    end
                                end
                                Configuration.Waiting = false
                            end
                        },
                        {
                            Title = "No",
                            Callback = function()
                                
                            end
                        }
                    }
                })
            end
        })
        Tabs.Players:AddSection("Settings")
        local Players_Dropdown = Tabs.Players:AddDropdown("Players Dropdown", {
            Title = "Select Player",
            Values = Players_InGame,
            Multi = false,
            Default = "",
            Callback = function(Value)
                Configuration.Players.SelectPlayer = Value
            end,
        })
        Tabs.Players:AddDropdown("GiftType Dropdown", {
            Title = "Gift Type",
            Values = {"All_Pets","Match Pet","Match Pet&Mutation","All_Foods","All_Eggs"},
            Multi = false,
            Default = "",
            Callback = function(Value)
                Configuration.Players.SelectType = Value
            end,
        })
        Tabs.Players:AddDropdown("Pet Type", {
            Title = "Select Pet Type",
            Description = "Select Pet Type",
            Values = Pets_InGame,
            Multi = true,
            Default = {},
            Callback = function(Value)
                Configuration.Players.Pet_Type = Value
            end,
        })
        Tabs.Players:AddDropdown("Pet Mutations", {
            Title = "Select Mutations",
            Description = "Select Pets Mutations",
            Values = Mutations_InGame,
            Multi = true,
            Default = {},
            Callback = function(Value)
                Configuration.Players.Pet_Mutations = Value
            end,
        })
        table.insert(EnvirontmentConnections,Players_List_Updated.Event:Connect(function(newList)
            Players_Dropdown:SetValues(newList)
        end))
        -- \\ About Tab // --
        Tabs.About:AddParagraph({
            Title = "Credit",
            Content = "Script create by Meowy / godyt_2.0"
        })
        -- \\ Settings Tab // --
        local AntiAFK_Toggle = Tabs.Settings:AddToggle("AntiAFK",{
            Title = "Anti AFK",
            Default = false,
            Callback = function(Value)
                ServerReplicatedDict:SetAttribute("AFK_THRESHOLD",(Value == false and 1080 or Value == true and 99999999999))
                Configuration.AntiAFK = Value
            end,
        })
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
    
    Fluent:Notify({
        Title = "Fluent",
        Content = "The script has been loaded.",
        Duration = 8
    })
    
    task.defer(function() -- Anti AFK
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
    
    task.defer(function() -- Auto Collect
        local Data_OwnedPets = Data:WaitForChild("Pets")
        local PetRE = GameRemoteEvents:WaitForChild("PetRE")
        local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE")
        local FoodList = PetFoods_InGame
        while true and RunningEnvirontments do
            if Configuration.Main.AutoCollect then
                for _,pet in pairs(OwnedPets) do
                    local RE = pet.RE
                    local Coin = tonumber(pet.Coin)
                    if Configuration.Main.Collect_Type == "Delay" then
                        if RE then
                            RE:FireServer("Claim")
                        end
                    elseif Configuration.Main.Collect_Type == "Between" and (Configuration.Main.Collect_Between["Min"] < Coin and Coin < Configuration.Main.Collect_Between["Max"]) then
                        if RE then
                            RE:FireServer("Claim")
                        end
                    end
                end
            end
            task.wait(Configuration.Main.Collect_Delay)
        end
    end)
    
    function GetBestPetFood(FoodList,OwnedFoods)
        local BestFood = ""
        for i,v in ipairs(FoodList) do
            if OwnedFoods[v] then
                BestFood = v
            end
        end
        return BestFood
    end
    
    function GetFood(OwnedFoods)
        local BestFood = ""
        for i,v in ipairs(PetFoods_InGame) do
            if Configuration.Pet.AutoFeed_Foods[v] and OwnedFoods[v] then
                BestFood = v
            end
        end
        return BestFood
    end
    
    task.defer(function() -- Auto Feed Pet
        local Data_OwnedPets = Data:WaitForChild("Pets",30)
        local PetRE = GameRemoteEvents:WaitForChild("PetRE")
        local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE")
        local FoodList = PetFoods_InGame
        while true and RunningEnvirontments do
            if Configuration.Pet.AutoFeed and not Configuration.Waiting and Configuration.Pet.AutoFeed_Type ~= "" then
                if not InventoryData then InventoryData = Data:FindFirstChild("Asset") end
                local Data_Inventory = InventoryData:GetAttributes()
                for _,pet in pairs(Data_OwnedPets:GetChildren()) do
                    local petData = pet
                    local pet = OwnedPets[pet.Name] or nil
                    if not (pet and pet.IsBig) then continue end
                    if petData and not petData:GetAttribute("Feed") then
                        local Food = (Configuration.Pet.AutoFeed_Type == "BestFood" and GetBestPetFood(FoodList,Data_Inventory) or Configuration.Pet.AutoFeed_Type == "SelectFood" and GetFood(Data_Inventory))
                        if Food then
                            CharacterRE:FireServer("Focus",Food)
                            task.wait(0.5)
                            PetRE:FireServer("Feed",pet.UID)
                            task.wait(0.5)
                            CharacterRE:FireServer("Focus")
                        end
                    end
                end
            end
            task.wait(Configuration.Pet.AutoFeed_Delay)
        end
    end)
    
    task.defer(function() -- Auto Collect Pet
    local CharacterRE = GameRemoteEvents:WaitForChild("CharacterRE",30)
    local CollectType = Configuration.Pet.CollectPet_Type
        while true and RunningEnvirontments do
                if Configuration.Pet.CollectPet_Auto and not Configuration.Waiting and Configuration.Pet.CollectPet_Type ~= "All" then
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
                end
            end
            task.wait(Configuration.Pet.CollectPet_Delay)
        end
    end)
    
    task.defer(function() -- Auto Hatch
        local OwnedEggs = Data:WaitForChild("Egg")
        while true and RunningEnvirontments do
            if Configuration.Egg.AutoHatch then
                for _,egg in pairs(OwnedEggs:GetChildren()) do
                    local Hatchable = ((#egg:GetChildren() > 0) and egg:GetAttribute("D") and (ServerTime.Value >= egg:GetAttribute("D")))
                    if Hatchable then
                        local Egg = BlockFolder:FindFirstChild(egg.Name)
                        local RootPart = Egg and (Egg.PrimaryPart or Egg:FindFirstChild("RootPart"))
                        local RF = RootPart and RootPart:FindFirstChild("RF")
                        if RF then
                            task.spawn(function()
                                RF:InvokeServer("Hatch")
                            end)
                        end
                    end
                end
            end
            task.wait(Configuration.Egg.Hatch_Delay)
        end
    end)
    
    task.defer(function() -- Auto Claim Event Quests
        local Tasks;
        local EventRE = ResEvent and GameRemoteEvents:WaitForChild(tostring(ResEvent).."RE")
        if EventTaskData then
            Tasks = EventTaskData:WaitForChild("Tasks")
        end
        while true and RunningEnvirontments do
            if Tasks and EventRE and Configuration.Event.AutoClaim then
                for _,Quest in pairs(Tasks:GetChildren()) do
                    EventRE:FireServer({event = "claimreward",id = Quest:GetAttribute("Id")})
                end
            end
            task.wait(Configuration.Event.AutoClaim_Delay)
        end
    end)
    
    task.defer(function() -- Auto Buy Egg
        local RE = GameRemoteEvents:WaitForChild("CharacterRE",30)
        while true and RunningEnvirontments do
            if Configuration.Egg.AutoBuyEgg and not Configuration.Waiting then
                for _,egg in pairs(Egg_Belt) do
                    local EggType = (egg.Type)
                    local EggMutation = (egg.Mutate)
                    if not (Configuration.Egg.Types[EggType] and Configuration.Egg.Mutations[EggMutation]) then continue end
                    if RE then
                        RE:FireServer("BuyEgg",egg.UID)
                    end
                end
            end
            task.wait(Configuration.Egg.AutoBuyEgg_Delay)
        end
    end)
    
    task.defer(function() -- Auto Buy Food
        local FoodList = Data:WaitForChild("FoodStore",30):WaitForChild("LST",30)
        local RE = GameRemoteEvents:WaitForChild("FoodStoreRE")
        while true and RunningEnvirontments do
            if Configuration.Shop.Food.AutoBuy and not Configuration.Waiting then
                for foodName,stockAmount in pairs(FoodList:GetAttributes()) do
                    if stockAmount > 0 and Configuration.Shop.Food.Foods[foodName] then
                        if RE then
                            RE:FireServer(foodName)
                        end
                    end
                end
            end
            task.wait(Configuration.Shop.Food.AutoBuy_Delay)
        end
    end)
    
    Window.Root.Destroying:Once(function()
        RunningEnvirontments = false
        for _,connection in pairs(EnvirontmentConnections) do
            if connection then
                pcall(function()
                    connection:Disconnect()
                end)
            end
        end
    end)
    
    SaveManager:LoadAutoloadConfig()
    getgenv().MeowyBuildAZoo = Window
    end

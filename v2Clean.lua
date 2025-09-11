--==============================================================
-- Build A Zoo (Zebub.lua) - REORGANIZED LAYOUT (logic unchanged)
--==============================================================

--== EARLY EXIT FOR OTHER GAMES
if game.PlaceId and game.PlaceId ~= 105555311806207 then return end

--== GUARD RE-RUN
if MeowyBuildAZoo then MeowyBuildAZoo:Destroy() end
repeat task.wait(1) until game:IsLoaded()

--==============================================================
-- 0) LIBS + SERVICES + GLOBALS
--==============================================================
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players                 = game:GetService("Players")
local ReplicatedStorage       = game:GetService("ReplicatedStorage")
local CollectionService       = game:GetService("CollectionService")
local ProximityPromptService  = game:GetService("ProximityPromptService")
local VirtualInputManager     = game:GetService("VirtualInputManager")
local HttpService             = game:GetService("HttpService")

local LocalPlayer             = Players.LocalPlayer
local vector = { create = function(x, y, z) return Vector3.new(x, y, z) end }

-- Persistent / runtime states
local settingsLoaded          = false
local updateCustomUISelection -- forward-declare

-- Selection states
local selectedTypeSet         = {}
local selectedMutationSet     = {}
local selectedFruits          = {}
local selectedFeedFruits      = {}
local selectedEggTypes        = {}
local selectedMutations       = {}

-- Toggles/threads (declared early so close handlers can see them)
local autoClaimEnabled, autoClaimThread, autoClaimDelay = false, nil, 0.1
local autoHatchEnabled, autoHatchThread = false, nil
local autoBuyEnabled,   autoBuyThread   = false, nil
local autoPlaceEnabled, autoPlaceThread = false, nil
local autoUnlockEnabled,autoUnlockThread= false, nil
local autoDeleteEnabled,autoDeleteThread= false, nil
local autoUpgradeEnabled, autoUpgradeThread = false, nil
local autoBuyFruitEnabled, autoBuyFruitThread = false, nil
local autoFeedEnabled, autoFeedThread = false, nil
local antiAFKEnabled, antiAFKConnection = false, nil
local autoDinoEnabled, autoDinoThread = false, nil

-- Configs (lazy-loaded)
local eggConfig, conveyorConfig, petFoodConfig, mutationConfig = {}, {}, {}, {}

-- Small helpers
local function waitForSettingsReady(extraDelay)
    while not settingsLoaded do task.wait(0.1) end
    if extraDelay and extraDelay > 0 then task.wait(extraDelay) end
end

--==============================================================
-- 1) WINDOW & TABS (GROUPED TOGETHER)
--==============================================================
local Window = WindUI:CreateWindow({
    Title = "Build A Zoo",
    Icon = "app-window-mac",
    IconThemed = true,
    Author = "Zebux",
    Folder = "Zebux",
    Size = UDim2.fromOffset(520, 360),
    Transparent = true,
    Theme = "Dark",
})

local Tabs = {}
Tabs.MainSection = Window:Section({ Title = "🤖 Auto Helpers", Opened = true })

-- keep all menu tabs here together
Tabs.MainTab  = Tabs.MainSection:Tab({ Title = "🏠 | Main"})
Tabs.EggTab   = Tabs.MainSection:Tab({ Title = "🥚 | Eggs"})
Tabs.ShopTab  = Tabs.MainSection:Tab({ Title = "🛒 | Shop"})
Tabs.PackTab  = Tabs.MainSection:Tab({ Title = "🎁 | Get Packs"})
Tabs.FruitTab = Tabs.MainSection:Tab({ Title = "🍎 | Fruit Store"})
Tabs.FeedTab  = Tabs.MainSection:Tab({ Title = "🍽️ | Auto Feed"})
Tabs.SaveTab  = Tabs.MainSection:Tab({ Title = "💾 | Save Settings"})

Window:EditOpenButton({ Title = "Build A Zoo", Icon = "monitor", Draggable = true })

--==============================================================
-- 2) CONFIG LOADERS / LOOKUPS / GENERIC HELPERS
--==============================================================
local function loadEggConfig()
    local ok, cfg = pcall(function()
        local m = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ResEgg")
        return require(m)
    end)
    eggConfig = ok and type(cfg)=="table" and cfg or {}
end

local function loadConveyorConfig()
    local ok, cfg = pcall(function()
        local m = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ResConveyor")
        return require(m)
    end)
    conveyorConfig = ok and type(cfg)=="table" and cfg or {}
end

local function loadPetFoodConfig()
    local ok, cfg = pcall(function()
        local m = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ResPetFood")
        return require(m)
    end)
    petFoodConfig = ok and type(cfg)=="table" and cfg or {}
end

local function loadMutationConfig()
    local ok, cfg = pcall(function()
        local m = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ResMutate")
        return require(m)
    end)
    mutationConfig = ok and type(cfg)=="table" and cfg or {}
end

local function getAssignedIslandName()
    return LocalPlayer and LocalPlayer:GetAttribute("AssignedIslandName") or nil
end

local function getPlayerNetWorth()
    if not LocalPlayer then return 0 end
    local a = LocalPlayer:GetAttribute("NetWorth")
    if type(a)=="number" then return a end
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local n = ls and ls:FindFirstChild("NetWorth")
    return (n and n.Value) or 0
end

local function playerRoot()
    local c = LocalPlayer and LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end

--==============================================================
-- 3) PERSISTENCE (WindUI Config + Custom selections)
--==============================================================
local ConfigManager = Window.ConfigManager
local zebuxConfig   = ConfigManager:CreateConfig("zebuxConfig")

local customSelections = {
    eggSelections  = { eggs = {}, mutations = {} },
    fruitSelections = {},
    feedFruitSelections = {},
}

local function saveCustomSelections()
    pcall(function()
        writefile("Zebux_CustomSelections.json", HttpService:JSONEncode(customSelections))
    end)
end

local function loadCustomSelections()
    local ok, data = pcall(function()
        if isfile("Zebux_CustomSelections.json") then
            return HttpService:JSONDecode(readfile("Zebux_CustomSelections.json"))
        end
    end)
    if ok and data then
        customSelections = data
        -- apply to runtime
        selectedTypeSet, selectedMutationSet = {}, {}
        for _, id in ipairs((data.eggSelections and data.eggSelections.eggs) or {}) do
            selectedTypeSet[id] = true
        end
        for _, id in ipairs((data.eggSelections and data.eggSelections.mutations) or {}) do
            selectedMutationSet[id] = true
        end
        selectedFruits, selectedFeedFruits = {}, {}
        for _, id in ipairs(data.fruitSelections or {}) do selectedFruits[id] = true end
        for _, id in ipairs(data.feedFruitSelections or {}) do selectedFeedFruits[id] = true end
    end
end

updateCustomUISelection = function(uiType, selections)
    if uiType == "eggSelections" then
        customSelections.eggSelections = { eggs = {}, mutations = {} }
        for eggId, on in pairs(selections.eggs or {}) do if on then table.insert(customSelections.eggSelections.eggs, eggId) end end
        for mutId, on in pairs(selections.mutations or {}) do if on then table.insert(customSelections.eggSelections.mutations, mutId) end end
    elseif uiType == "fruitSelections" then
        customSelections.fruitSelections = {}
        for fruitId, on in pairs(selections) do if on then table.insert(customSelections.fruitSelections, fruitId) end end
    elseif uiType == "feedFruitSelections" then
        customSelections.feedFruitSelections = {}
        for fruitId, on in pairs(selections) do if on then table.insert(customSelections.feedFruitSelections, fruitId) end end
    end
    saveCustomSelections()
end

--==============================================================
-- 4) UI HELPERS / DROPDOWN SYNC
--==============================================================
local function syncAutoPlaceFiltersFromUI()
    local function getMulti(elm)
        if not elm then return {} end
        local tries = {
            function() return elm:GetValue and elm:GetValue() end,
            function() return elm.Value end,
            function() return elm.Get and elm:Get() end,
            function() return elm.Selected end,
            function() return elm.GetSelected and elm:GetSelected() end,
        }
        local raw
        for _, f in ipairs(tries) do
            local ok, v = pcall(f); if ok and v ~= nil then raw = v break end
        end
        local out = {}
        if type(raw)=="table" then
            for i,v in ipairs(raw) do table.insert(out, v) end
            if #out==0 then for k,v in pairs(raw) do if v==true then table.insert(out, k) end end end
        end
        return out
    end
    local eggs = getMulti(_G.__placeEggDropdown)  ; if #eggs>0 then selectedEggTypes = eggs end
    local muts = getMulti(_G.__placeMutationDD)   ; if #muts>0 then selectedMutations = muts end
end

--==============================================================
-- 5) GAME WORLD HELPERS (belts / tiles / occupancy / pets)
--==============================================================
local function getIslandBelts(islandName)
    local art = workspace:FindFirstChild("Art"); if not art then return {} end
    local island = art:FindFirstChild(islandName or ""); if not island then return {} end
    local env = island:FindFirstChild("ENV"); if not env then return {} end
    local root = env:FindFirstChild("Conveyor"); if not root then return {} end
    local out = {}
    for i=1,9 do
        local c = root:FindFirstChild("Conveyor"..i)
        local b = c and c:FindFirstChild("Belt")
        if b then table.insert(out, b) end
    end
    return out
end

local function getActiveBelt(islandName)
    local belts = getIslandBelts(islandName)
    if #belts==0 then return nil end
    local hrp = playerRoot(); local p = hrp and hrp.Position or Vector3.new()
    local best, score = nil, nil
    for _, belt in ipairs(belts) do
        local eggs, sample = 0, nil
        for _, ch in ipairs(belt:GetChildren()) do
            if ch:IsA("Model") then
                eggs += 1
                if not sample then local ok, cf = pcall(function() return ch:GetPivot() end); if ok and cf then sample = cf.Position end end
            end
        end
        sample = sample or (belt.Parent and (belt.Parent:FindFirstChildWhichIsA("BasePart", true) or {}).Position) or p
        local dist = (sample - p).Magnitude
        local s = eggs*100000 - dist
        if not score or s>score then score, best = s, belt end
    end
    return best
end

-- Tiles
local function getIslandNumberFromName(islandName)
    local m = islandName and islandName:match("Island_(%d+)") or nil
    m = m or (islandName and islandName:match("(%d+)"))
    return m and tonumber(m) or nil
end

local function getFarmParts(islandNumber)
    if not islandNumber then return {} end
    local art = workspace:FindFirstChild("Art"); if not art then return {} end
    local island = art:FindFirstChild("Island_"..tostring(islandNumber))
    if not island then
        for _, ch in ipairs(art:GetChildren()) do
            if ch.Name:match("^Island[_-]?"..tostring(islandNumber).."$") then island = ch break end
        end
        if not island then return {} end
    end
    local farm = {}
    local function scan(p)
        for _, c in ipairs(p:GetChildren()) do
            if c:IsA("BasePart") and c.Name:match("^Farm_split_%d+_%d+_%d+$") then
                if c.Size == Vector3.new(8,8,8) and c.CanCollide then table.insert(farm, c) end
            end
            scan(c)
        end
    end
    scan(island)

    -- filter locked by ENV/Locks
    local unlocked, locksFolder = {}, island:FindFirstChild("ENV") and island.ENV:FindFirstChild("Locks")
    if locksFolder then
        local lockedAreas = {}
        for _, m in ipairs(locksFolder:GetChildren()) do
            if m:IsA("Model") then
                local fp = m:FindFirstChild("Farm")
                if fp and fp:IsA("BasePart") and fp.Transparency==0 then
                    table.insert(lockedAreas, {pos = fp.Position, size = fp.Size})
                end
            end
        end
        for _, part in ipairs(farm) do
            local locked = false
            for _, L in ipairs(lockedAreas) do
                local half = L.size/2
                if  part.Position.X >= L.pos.X-half.X and part.Position.X <= L.pos.X+half.X
                and part.Position.Z >= L.pos.Z-half.Z and part.Position.Z <= L.pos.Z+half.Z then
                    locked = true break
                end
            end
            if not locked then table.insert(unlocked, part) end
        end
    else
        unlocked = farm
    end
    return unlocked
end

-- Pet presence on tiles
local function getPlayerPetConfigurations()
    local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    local data = pg and pg:FindFirstChild("Data")
    local pets = data and data:FindFirstChild("Pets")
    local out = {}
    if pets then
        for _, cfg in ipairs(pets:GetChildren()) do
            if cfg:IsA("Configuration") then table.insert(out, {name=cfg.Name, config=cfg}) end
        end
    end
    return out
end

local function getPlayerPetsInWorkspace()
    local names = {}
    for _, p in ipairs(getPlayerPetConfigurations()) do names[p.name]=true end
    local list, root = {}, workspace:FindFirstChild("Pets")
    if not root then return list end
    for _, m in ipairs(root:GetChildren()) do
        if names[m.Name] and m:IsA("Model") then
            local ok, cf = pcall(function() return m:GetPivot() end)
            table.insert(list, {name=m.Name, model=m, position= ok and cf.Position or (m.PrimaryPart and m.PrimaryPart.Position) or Vector3.new()})
        end
    end
    return list
end

--==============================================================
-- 6) EGGS / INVENTORY HELPERS
--==============================================================
local function getEggContainer()
    local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    local data = pg and pg:FindFirstChild("Data")
    return data and data:FindFirstChild("Egg") or nil
end

-- read mutation from player's Data.Egg[UID] attribute M (Dino->Jurassic)
local function getEggMutationFromData(eggUID)
    local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui"); if not pg then return nil end
    local data = pg:FindFirstChild("Data"); if not data then return nil end
    local container = data:FindFirstChild("Egg"); if not container then return nil end
    local ec = container:FindFirstChild(eggUID); if not ec then return nil end
    local m = ec:GetAttribute("M")
    if m == "Dino" then m = "Jurassic" end
    return m
end

local function listAvailableEggUIDs()
    local eg, out = getEggContainer(), {}
    if not eg then return out end
    for _, ch in ipairs(eg:GetChildren()) do
        if #ch:GetChildren()==0 then
            local t = ch:GetAttribute("T")
            local mut = getEggMutationFromData(ch.Name)
            table.insert(out, { uid = ch.Name, type = t or ch.Name, mutation = mut })
        end
    end
    return out
end

--==============================================================
-- 7) MAIN TAB: AUTO CLAIM MONEY
--==============================================================
local function getOwnedPetNames()
    local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    local data = pg and pg:FindFirstChild("Data")
    local container = data and data:FindFirstChild("Pets")
    local names = {}
    if container then
        for _, ch in ipairs(container:GetChildren()) do
            local n = ch:IsA("ValueBase") and tostring(ch.Value) or tostring(ch.Name)
            if n and n~="" then table.insert(names, n) end
        end
    end
    return names
end

local function claimMoneyForPet(petName)
    local pets = workspace:FindFirstChild("Pets"); if not pets then return false end
    local m = pets:FindFirstChild(petName); if not m then return false end
    local root = m:FindFirstChild("RootPart"); if not root then return false end
    local re = root:FindFirstChild("RE"); if not re or not re.FireServer then return false end
    local ok, err = pcall(function() re:FireServer("Claim") end)
    if not ok then warn("Claim failed for "..tostring(petName)..": "..tostring(err)) end
    return ok
end

local function runAutoClaim()
    while autoClaimEnabled do
        local ok, err = pcall(function()
            local names = getOwnedPetNames()
            if #names==0 then task.wait(0.8) return end
            for _, n in ipairs(names) do claimMoneyForPet(n); task.wait(autoClaimDelay) end
        end)
        if not ok then warn("Auto Claim error: "..tostring(err)); task.wait(1) end
    end
end

local autoClaimToggle = Tabs.MainTab:Toggle({
    Title = "💰 Auto Get Money",
    Desc  = "Automatically collects money from your pets",
    Value = false,
    Callback = function(state)
        autoClaimEnabled = state
        waitForSettingsReady(0.2)
        if state and not autoClaimThread then
            autoClaimThread = task.spawn(function() runAutoClaim(); autoClaimThread=nil end)
            WindUI:Notify({ Title="💰 Auto Claim", Content="Started!", Duration=3 })
        end
    end
})

local autoClaimDelaySlider = Tabs.MainTab:Slider({
    Title="⏰ Claim Speed",
    Desc ="How fast to collect (lower = faster)",
    Default=100, Min=0, Max=1000, Rounding=0,
    Callback = function(v) autoClaimDelay = math.clamp((tonumber(v) or 100)/1000,0,2) end
})

--==============================================================
-- 8) EGGS TAB: HATCH / BUY / PLACE / UNLOCK / DELETE
--==============================================================
-- 8.1 Auto Hatch
local function isReadyText(t)
    if type(t)~="string" then return false end
    if t:match("^%s*$") then return true end
    local num = t:match("^%s*(%d+%.?%d*)%s*%%%s*$")
    if num and tonumber(num) and tonumber(num)>=100 then return true end
    local L = t:lower()
    return L:find("hatch",1,true) or L:find("ready",1,true) or false
end

local function isHatchReady(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("TextLabel") and d.Name=="TXT" and d.Parent and d.Parent.Name=="TimeBar" then
            if isReadyText(d.Text) then return true end
        end
        if d:IsA("ProximityPrompt") and type(d.ActionText)=="string" then
            if d.ActionText:lower():find("hatch",1,true) then return true end
        end
    end
    return false
end

local function getOwnerUserIdDeep(inst)
    local cur = inst
    while cur and cur~=workspace do
        if cur.GetAttribute then
            local uid = cur:GetAttribute("UserId")
            if type(uid)=="number" then return uid end
            if type(uid)=="string" then local n=tonumber(uid); if n then return n end end
        end
        cur = cur.Parent
    end
    return nil
end

local function playerOwnsInstance(inst)
    local uid = getOwnerUserIdDeep(inst)
    return LocalPlayer and uid and uid==LocalPlayer.UserId
end

local function collectOwnedEggs()
    local root = workspace:FindFirstChild("PlayerBuiltBlocks")
    local list = {}
    if root then
        for _, m in ipairs(root:GetChildren()) do
            if m:IsA("Model") and playerOwnsInstance(m) then table.insert(list, m) end
        end
        if #list==0 then
            for _, m in ipairs(root:GetDescendants()) do
                if m:IsA("Model") and playerOwnsInstance(m) then table.insert(list, m) end
            end
        end
    end
    return list
end

local function pressPromptE(prompt)
    if typeof(prompt)~="Instance" or not prompt:IsA("ProximityPrompt") then return false end
    if _G and typeof(_G.fireproximityprompt)=="function" then
        local s = pcall(function() _G.fireproximityprompt(prompt, prompt.HoldDuration or 0) end)
        if s then return true end
    end
    pcall(function() prompt.RequiresLineOfSight=false; prompt.Enabled=true end)
    local key = prompt.KeyboardKeyCode; if key==Enum.KeyCode.Unknown or not key then key = Enum.KeyCode.E end
    local hold = prompt.HoldDuration or 0
    VirtualInputManager:SendKeyEvent(true, key, false, game)
    if hold>0 then task.wait(hold+0.05) end
    VirtualInputManager:SendKeyEvent(false, key, false, game)
    return true
end

local function walkTo(pos, timeout)
    local ch = LocalPlayer and LocalPlayer.Character; if not ch then return false end
    local hum = ch:FindFirstChildOfClass("Humanoid"); if not hum then return false end
    hum:MoveTo(pos); return hum.MoveToFinished:Wait(timeout or 5)
end

local function getModelPosition(model)
    local ok, cf = pcall(function() return model:GetPivot() end)
    if ok and cf then return cf.Position end
    local pp = model.PrimaryPart or model:FindFirstChild("RootPart")
    return pp and pp.Position or nil
end

local function tryHatchModel(model)
    if not playerOwnsInstance(model) then return false, "Not owner" end
    local prompt
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("ProximityPrompt") then prompt = d; break end
    end
    if not prompt then return false, "No prompt" end
    local pos = getModelPosition(model); if not pos then return false, "No pos" end
    walkTo(pos, 6)
    local hrp = playerRoot()
    if hrp and (hrp.Position - pos).Magnitude > (prompt.MaxActivationDistance or 10)-1 then
        local dir = (pos - hrp.Position).Unit
        hrp.CFrame = CFrame.new(pos - dir*1.5, pos); task.wait(0.1)
    end
    return pressPromptE(prompt)
end

local function runAutoHatch()
    while autoHatchEnabled do
        local ok, err = pcall(function()
            local owned = collectOwnedEggs()
            if #owned==0 then task.wait(1.0) return end
            local eggs = {}
            for _, m in ipairs(owned) do if isHatchReady(m) then table.insert(eggs, m) end end
            if #eggs==0 then task.wait(0.8) return end
            local me = (playerRoot() and playerRoot().Position) or Vector3.new()
            table.sort(eggs, function(a,b)
                local pa = getModelPosition(a) or Vector3.new()
                local pb = getModelPosition(b) or Vector3.new()
                return (pa-me).Magnitude < (pb-me).Magnitude
            end)
            for _, m in ipairs(eggs) do tryHatchModel(m); task.wait(0.2) end
        end)
        if not ok then warn("Auto Hatch error: "..tostring(err)); task.wait(1) end
    end
end

local autoHatchToggle = Tabs.EggTab:Toggle({
    Title="⚡ Auto Hatch Eggs", Desc="Walk & hatch automatically", Value=false,
    Callback=function(state)
        autoHatchEnabled = state; waitForSettingsReady(0.2)
        if state and not autoHatchThread then
            autoHatchThread = task.spawn(function() runAutoHatch(); autoHatchThread=nil end)
            WindUI:Notify({ Title="⚡ Auto Hatch", Content="Started!", Duration=3 })
        end
    end
})

Tabs.EggTab:Button({
    Title="⚡ Hatch Nearest Egg", Desc="Hatch closest ready egg",
    Callback=function()
        local owned = collectOwnedEggs(); if #owned==0 then WindUI:Notify({Title="⚡ Auto Hatch", Content="No eggs", Duration=3}); return end
        local eggs = {}; for _, m in ipairs(owned) do if isHatchReady(m) then table.insert(eggs, m) end end
        if #eggs==0 then WindUI:Notify({Title="⚡ Auto Hatch", Content="No eggs ready", Duration=3}); return end
        local me = (playerRoot() and playerRoot().Position) or Vector3.new()
        table.sort(eggs, function(a,b)
            local pa = getModelPosition(a) or Vector3.new()
            local pb = getModelPosition(b) or Vector3.new()
            return (pa-me).Magnitude < (pb-me).Magnitude
        end)
        local ok = tryHatchModel(eggs[1])
        WindUI:Notify({ Title = ok and "🎉 Hatched!" or "❌ Hatch Failed", Content = eggs[1].Name, Duration=3 })
    end
})

-- 8.2 Egg Selection UI (external module)
local EggSelection = loadstring(game:HttpGet("https://raw.githubusercontent.com/ZebuxHub/Main/refs/heads/main/EggSelection.lua"))()
local eggSelectionVisible = false

Tabs.EggTab:Button({
    Title="🥚 Open Egg Selection UI",
    Desc="Choose egg types & mutations (glass UI)",
    Callback=function()
        if not eggSelectionVisible then
            EggSelection.Show(
                function(selectedItems)
                    selectedTypeSet, selectedMutationSet = {}, {}
                    if selectedItems then
                        for id, on in pairs(selectedItems) do
                            if on then
                                if     id=="Golden" or id=="Diamond" or id=="Electric" or id=="Fire" or id=="Jurassic" then
                                    selectedMutationSet[id] = true
                                else
                                    selectedTypeSet[id] = true
                                end
                            end
                        end
                    end
                    updateCustomUISelection("eggSelections", {eggs=selectedTypeSet, mutations=selectedMutationSet})
                end,
                function(v) eggSelectionVisible=v end,
                selectedTypeSet, selectedMutationSet
            )
            eggSelectionVisible = true
        else
            EggSelection.Hide(); eggSelectionVisible=false
        end
    end
})

-- 8.3 Auto Buy Eggs (event-driven on belt)
local function getEggPriceByType(eggType)
    local target = tostring(eggType)
    for key, value in pairs(eggConfig) do
        if type(value)=="table" then
            local t = value.Type or value.Name or value.type or value.name or tostring(key)
            if tostring(t)==target then
                local price = value.Price or value.price or value.Cost or value.cost
                if type(price)=="number" then return price end
                if type(value.Base)=="table" and type(value.Base.Price)=="number" then return value.Base.Price end
            end
        end
    end
    return nil
end

local function shouldBuyEggInstance(eggInstance, money)
    if not eggInstance or not eggInstance:IsA("Model") then return false end
    local eggType = eggInstance:GetAttribute("Type") or eggInstance:GetAttribute("EggType") or eggInstance:GetAttribute("Name")
    if not eggType then return false end
    eggType = tostring(eggType)

    if selectedTypeSet and next(selectedTypeSet) and not selectedTypeSet[eggType] then return false end

    if selectedMutationSet and next(selectedMutationSet) then
        local mut = getEggMutationFromData(eggInstance.Name)
        if not mut or not selectedMutationSet[mut] then return false end
    end

    local price = eggInstance:GetAttribute("Price") or getEggPriceByType(eggType)
    return type(price)=="number" and money>=price
end

local function buyEggByUID(uid)
    pcall(function() ReplicatedStorage.Remote.CharacterRE:FireServer("BuyEgg", uid) end)
end
local function focusEggByUID(uid)
    pcall(function() ReplicatedStorage.Remote.CharacterRE:FireServer("Focus", uid) end)
end

local beltConnections = {}
local function cleanupBeltConnections() for _, c in ipairs(beltConnections) do pcall(function() c:Disconnect() end) end; beltConnections={} end
local buyingInProgress = false

local function buyEggInstantly(eggModel)
    if buyingInProgress then return end
    buyingInProgress = true
    local money = getPlayerNetWorth()
    if shouldBuyEggInstance(eggModel, money) then
        buyEggByUID(eggModel.Name); focusEggByUID(eggModel.Name)
    end
    buyingInProgress = false
end

local function setupBeltMonitoring(belt)
    if not belt then return end
    local function onChildAdded(ch) if autoBuyEnabled and ch:IsA("Model") then task.wait(0.1); buyEggInstantly(ch) end end
    table.insert(beltConnections, belt.ChildAdded:Connect(onChildAdded))
    -- periodic sweep
    local th = task.spawn(function()
        while autoBuyEnabled do
            for _, ch in ipairs(belt:GetChildren()) do if ch:IsA("Model") then buyEggInstantly(ch) end end
            task.wait(0.5)
        end
    end)
    table.insert(beltConnections, { Disconnect=function() th=nil end })
end

local function runAutoBuy()
    while autoBuyEnabled do
        local island = getAssignedIslandName()
        if not island or island=="" then task.wait(1) goto continue end
        local active = getActiveBelt(island)
        if not active then task.wait(1) goto continue end
        cleanupBeltConnections(); setupBeltMonitoring(active)
        while autoBuyEnabled do
            if getAssignedIslandName() ~= island then break end
            task.wait(0.5)
        end
        ::continue::
    end
    cleanupBeltConnections()
end

local autoBuyToggle = Tabs.EggTab:Toggle({
    Title="🥚 Auto Buy Eggs", Desc="Buy on belt instantly", Value=false,
    Callback=function(state)
        autoBuyEnabled = state; waitForSettingsReady(0.2)
        if state and not autoBuyThread then
            autoBuyThread = task.spawn(function() runAutoBuy(); autoBuyThread=nil end)
            WindUI:Notify({ Title="🥚 Auto Buy", Content="Started!", Duration=3 })
        else
            if not state then cleanupBeltConnections() end
        end
    end
})

-- 8.4 Auto Place Egg (filters + event-driven)
Tabs.EggTab:Section({ Title = "🥚 Auto Place Egg"})
_G.__placeEggDropdown = Tabs.EggTab:Dropdown({
    Title="🥚 Pick Pet Types", Desc="Choose which pets to place",
    Values={"BasicEgg","RareEgg","SuperRareEgg","EpicEgg","LegendEgg","PrismaticEgg","HyperEgg","VoidEgg","BowserEgg","DemonEgg","BoneDragonEgg","UltraEgg","DinoEgg","FlyEgg","UnicornEgg","AncientEgg"},
    Value={}, Multi=true, AllowNone=true,
    Callback=function(sel) selectedEggTypes = sel end
})

_G.__placeMutationDD = Tabs.EggTab:Dropdown({
    Title="🧬 Pick Mutations", Desc="Leave empty = all",
    Values={"Golden","Diamond","Electric","Fire","Jurassic"},
    Value={}, Multi=true, AllowNone=true,
    Callback=function(sel) selectedMutations = sel end
})

local availableEggs, availableTiles = {}, {}
local function updateAvailableEggs()
    local eggs = listAvailableEggUIDs()
    availableEggs = {}
    local typeSet, mutSet = {}, {}
    for _, t in ipairs(selectedEggTypes) do typeSet[t]=true end
    for _, m in ipairs(selectedMutations) do mutSet[m]=true end
    for _, e in ipairs(eggs) do
        local okType = (not next(typeSet)) or typeSet[e.type]
        local okMut  = (not next(mutSet))  or (e.mutation and mutSet[e.mutation])
        if okType and okMut then table.insert(availableEggs, e) end
    end
end

local function scanAllTilesAndModels()
    local name = getAssignedIslandName(); local num = getIslandNumberFromName(name)
    local farm = getFarmParts(num)
    local tileMap = {}

    for i, part in ipairs(farm) do
        local surface = Vector3.new(part.Position.X, part.Position.Y + 12, part.Position.Z)
        tileMap[surface] = { part=part, index=i, available=true }
    end

    -- eggs in PlayerBuiltBlocks
    local root = workspace:FindFirstChild("PlayerBuiltBlocks")
    if root then
        for _, m in ipairs(root:GetChildren()) do
            if m:IsA("Model") then
                local pos = m:GetPivot().Position
                for surface, info in pairs(tileMap) do
                    if info.available then
                        local dx = math.abs(pos.X - surface.X)
                        local dz = math.abs(pos.Z - surface.Z)
                        local dy = math.abs(pos.Y - surface.Y)
                        if math.sqrt(dx*dx + dz*dz) < 4.0 and dy < 20.0 then
                            info.available=false
                        end
                    end
                end
            end
        end
    end

    -- pets in workspace.Pets
    for _, pet in ipairs(getPlayerPetsInWorkspace()) do
        local pos = pet.position
        for surface, info in pairs(tileMap) do
            if info.available then
                local dx = math.abs(pos.X - surface.X)
                local dz = math.abs(pos.Z - surface.Z)
                local dy = math.abs(pos.Y - surface.Y)
                if math.sqrt(dx*dx + dz*dz) < 4.0 and dy < 20.0 then
                    info.available=false
                end
            end
        end
    end

    return tileMap
end

local function updateAvailableTiles()
    availableTiles = {}
    local map = scanAllTilesAndModels()
    for surface, info in pairs(map) do
        if info.available then table.insert(availableTiles, {part=info.part, index=info.index, surfacePos=surface}) end
    end
end

local placingInProgress = false
local function placeEggInstantly(eggInfo, tileInfo)
    if placingInProgress then return false end
    placingInProgress = true
    local petUID, tilePart = eggInfo.uid, tileInfo.part

    -- equip deploy slot 2
    local dep = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("Data") and LocalPlayer.PlayerGui.Data:FindFirstChild("Deploy")
    if dep then dep:SetAttribute("S2", "Egg_"..petUID) end
    -- hold key 2
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Two, false, game); task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Two, false, game); task.wait(0.1)

    -- teleport
    local ch = LocalPlayer.Character; local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CFrame = CFrame.new(tilePart.Position); task.wait(0.1) end

    local surface = Vector3.new(tilePart.Position.X, tilePart.Position.Y + (tilePart.Size.Y/2), tilePart.Position.Z)
    local ok = pcall(function()
        ReplicatedStorage.Remote.CharacterRE:FireServer("Place",{DST=vector.create(surface.X,surface.Y,surface.Z), ID=petUID})
    end)

    if ok then
        task.wait(0.3)
        local built = workspace:FindFirstChild("PlayerBuiltBlocks")
        local confirmed = false
        if built then
            for _, m in ipairs(built:GetChildren()) do
                if m:IsA("Model") and m.Name==petUID then confirmed=true break end
            end
        end
        if confirmed then
            -- purge used items
            for i, e in ipairs(availableEggs) do if e.uid==petUID then table.remove(availableEggs,i) break end end
            for i, t in ipairs(availableTiles) do if t.index==tileInfo.index then table.remove(availableTiles,i) break end end
            placingInProgress=false; return true
        end
    end
    -- fail: drop the tile to avoid spam retry
    for i, t in ipairs(availableTiles) do if t.index==tileInfo.index then table.remove(availableTiles,i) break end end
    placingInProgress=false; return false
end

local function attemptPlacement()
    if #availableEggs==0 or #availableTiles==0 then return end
    local maxAttempts = math.min(#availableEggs, #availableTiles, 1) -- conservative burst
    local tries=0
    while #availableEggs>0 and #availableTiles>0 and tries<maxAttempts do
        tries+=1
        local ok = placeEggInstantly(availableEggs[1], availableTiles[1])
        task.wait(ok and 0.2 or 0.1)
    end
end

local placeConnections = {}
local function cleanupPlaceConnections() for _, c in ipairs(placeConnections) do pcall(function() c:Disconnect() end) end; placeConnections={} end

local function setupPlacementMonitoring()
    local eggContainer = getEggContainer()
    if eggContainer then
        table.insert(placeConnections, eggContainer.ChildAdded:Connect(function(ch)
            if not autoPlaceEnabled then return end
            if #ch:GetChildren()==0 then task.wait(0.2); updateAvailableEggs(); attemptPlacement() end
        end))
        table.insert(placeConnections, eggContainer.ChildRemoved:Connect(function() if autoPlaceEnabled then updateAvailableEggs() end end))
    end
    local built = workspace:FindFirstChild("PlayerBuiltBlocks")
    if built then
        local f = function() if autoPlaceEnabled then task.wait(0.2); updateAvailableTiles(); attemptPlacement() end end
        table.insert(placeConnections, built.ChildAdded:Connect(f))
        table.insert(placeConnections, built.ChildRemoved:Connect(f))
    end
    local pets = workspace:FindFirstChild("Pets")
    if pets then
        local f = function() if autoPlaceEnabled then task.wait(0.2); updateAvailableTiles(); attemptPlacement() end end
        table.insert(placeConnections, pets.ChildAdded:Connect(f))
        table.insert(placeConnections, pets.ChildRemoved:Connect(f))
    end
    -- periodic pump
    local th = task.spawn(function()
        while autoPlaceEnabled do
            updateAvailableEggs(); updateAvailableTiles(); attemptPlacement()
            task.wait(1.5)
        end
    end)
    table.insert(placeConnections, { Disconnect=function() th=nil end })
end

local function runAutoPlace()
    while autoPlaceEnabled do
        local island = getAssignedIslandName()
        if not island or island=="" then task.wait(1) goto continue end
        cleanupPlaceConnections(); setupPlacementMonitoring()
        while autoPlaceEnabled do
            if getAssignedIslandName() ~= island then break end
            task.wait(0.5)
        end
        ::continue::
    end
    cleanupPlaceConnections()
end

local autoPlaceToggle = Tabs.EggTab:Toggle({
    Title="🏠 Auto Place Egg",
    Desc ="Place pets on empty tiles automatically",
    Value=false,
    Callback=function(state)
        autoPlaceEnabled = state
        waitForSettingsReady(0.2)
        if state then
            syncAutoPlaceFiltersFromUI()
            pcall(function() updateAvailableEggs(); updateAvailableTiles(); attemptPlacement() end)
            if not autoPlaceThread then
                autoPlaceThread = task.spawn(function() runAutoPlace(); autoPlaceThread=nil end)
                WindUI:Notify({ Title="🏠 Auto Place Egg", Content="Started!", Duration=3 })
            end
        else
            cleanupPlaceConnections()
        end
    end
})

-- 8.5 Auto Unlock Tiles
local function getLockedTiles()
    local out = {}
    local name = getAssignedIslandName(); if not name then return out end
    local art = workspace:FindFirstChild("Art"); if not art then return out end
    local island = art:FindFirstChild(name); if not island then return out end
    local env = island:FindFirstChild("ENV"); if not env then return out end
    local locks = env:FindFirstChild("Locks"); if not locks then return out end
    for _, m in ipairs(locks:GetChildren()) do
        if m:IsA("Model") then
            local farm = m:FindFirstChild("Farm")
            if farm and farm:IsA("BasePart") and farm.Transparency==0 then
                table.insert(out, { modelName=m.Name, farmPart=farm, cost=farm:GetAttribute("LockCost") })
            end
        end
    end
    return out
end

local function unlockTile(lockInfo)
    local ok = pcall(function() ReplicatedStorage.Remote.CharacterRE:FireServer("Unlock", lockInfo.farmPart) end)
    return ok
end

local function runAutoUnlock()
    while autoUnlockEnabled do
        local ok, err = pcall(function()
            local locks = getLockedTiles()
            if #locks==0 then task.wait(2) return end
            local net = getPlayerNetWorth()
            for _, L in ipairs(locks) do
                if not autoUnlockEnabled then break end
                local cost = tonumber(L.cost) or 0
                if net >= cost then if unlockTile(L) then task.wait(0.5) else task.wait(0.2) end end
            end
            task.wait(3)
        end)
        if not ok then warn("Auto Unlock error: "..tostring(err)); task.wait(1) end
    end
end

local autoUnlockToggle = Tabs.EggTab:Toggle({
    Title="🔓 Auto Unlock Tiles",
    Desc ="Unlock when affordable",
    Value=false,
    Callback=function(state)
        autoUnlockEnabled = state; waitForSettingsReady(0.2)
        if state and not autoUnlockThread then
            autoUnlockThread = task.spawn(function() runAutoUnlock(); autoUnlockThread=nil end)
            WindUI:Notify({ Title="🔓 Auto Unlock", Content="Started!", Duration=3 })
        end
    end
})

Tabs.EggTab:Button({
    Title="🔓 Unlock All Affordable Now",
    Desc ="Try to unlock every affordable tile",
    Callback=function()
        local locks = getLockedTiles()
        local net = getPlayerNetWorth()
        local count=0
        for _, L in ipairs(locks) do
            local cost = tonumber(L.cost) or 0
            if net>=cost and unlockTile(L) then count+=1; task.wait(0.1) end
        end
        WindUI:Notify({ Title="🔓 Unlock Complete", Content=("Unlocked "..tostring(count).." tiles! 🎉"), Duration=3 })
    end
})

-- 8.6 Auto Delete (speed threshold)
local deleteSpeedThreshold = 100
local autoDeleteSpeedSlider = Tabs.EggTab:Input({
    Title="Speed Threshold", Desc="Delete pets with speed below this",
    Value="100",
    Callback=function(v) deleteSpeedThreshold = tonumber(v) or 100 end
})

local function runAutoDelete()
    while autoDeleteEnabled do
        local ok, err = pcall(function()
            local pets = workspace:FindFirstChild("Pets"); if not pets then task.wait(1) return end
            local myId = Players.LocalPlayer.UserId
            local victims = {}
            for _, pet in ipairs(pets:GetChildren()) do
                if pet:IsA("Model") then
                    local uid = pet:GetAttribute("UserId")
                    if uid and tonumber(uid)==myId then
                        local root = pet:FindFirstChild("RootPart")
                        local idleGUI = root and root:FindFirstChild("GUI/IdleGUI", true)
                        local speedLabel = idleGUI and idleGUI:FindFirstChild("Speed")
                        if speedLabel and speedLabel:IsA("TextLabel") then
                            local num = tonumber((speedLabel.Text or ""):match("%d+"))
                            if num and num < deleteSpeedThreshold then
                                table.insert(victims, pet.Name)
                            end
                        end
                    end
                end
            end
            if #victims==0 then task.wait(2) return end
            for _, name in ipairs(victims) do
                pcall(function() ReplicatedStorage.Remote.CharacterRE:FireServer("Del", name) end)
                task.wait(0.5)
            end
            task.wait(3)
        end)
        if not ok then warn("Auto Delete error: "..tostring(err)); task.wait(1) end
    end
end

local autoDeleteToggle = Tabs.EggTab:Toggle({
    Title="Auto Delete", Desc="Delete slow pets (yours only)", Value=false,
    Callback=function(state)
        autoDeleteEnabled = state; waitForSettingsReady(0.2)
        if state and not autoDeleteThread then
            autoDeleteThread = task.spawn(function() runAutoDelete(); autoDeleteThread=nil end)
            WindUI:Notify({ Title="Auto Delete", Content="Started", Duration=3 })
        end
    end
})

--==============================================================
-- 9) SHOP TAB: AUTO UPGRADE CONVEYOR
--==============================================================
Tabs.ShopTab:Section({ Title="🛒 Auto Upgrade Conveyor", Icon="arrow-up" })
local shopParagraph = Tabs.ShopTab:Paragraph({ Title="🛒 Shop Status", Desc="Shows upgrade progress", Image="activity", ImageSize=22 })
local shopStatus = { lastAction="Ready", upgradesTried=0, upgradesDone=0 }
local function setShopStatus(msg)
    shopStatus.lastAction = msg
    if shopParagraph and shopParagraph.SetDesc then
        shopParagraph:SetDesc(string.format("Upgrades: %d done\nLast: %s", shopStatus.upgradesDone, shopStatus.lastAction))
    end
end

local function fireConveyorUpgrade(index)
    local ok, err = pcall(function() ReplicatedStorage.Remote.ConveyorRE:FireServer("Upgrade", tonumber(index) or index) end)
    if not ok then warn("Conveyor Upgrade failed: "..tostring(err)) end
    return ok
end

local function parseConveyorIndexFromId(idStr)
    local n = tostring(idStr):match("(%d+)"); return n and tonumber(n) or nil
end

local purchasedUpgrades = {}
local function chooseAffordableUpgrades(netWorth)
    local actions = {}
    for key, entry in pairs(conveyorConfig) do
        if type(entry)=="table" then
            local cost = entry.Cost or entry.Price or (entry.Base and entry.Base.Price)
            if type(cost)=="string" then cost = tonumber((tostring(cost):gsub("[^%d%.]",""))) end
            local idLike = entry.ID or entry.Id or entry.Name or key
            local idx = parseConveyorIndexFromId(idLike)
            if idx and type(cost)=="number" and netWorth>=cost and idx>=1 and idx<=9 and not purchasedUpgrades[idx] then
                table.insert(actions, { idx=idx, cost=cost })
            end
        end
    end
    table.sort(actions, function(a,b) return a.idx < b.idx end)
    return actions
end

local autoUpgradeToggle = Tabs.ShopTab:Toggle({
    Title="🛒 Auto Upgrade Conveyor", Desc="Upgrade when you have enough money", Value=false,
    Callback=function(state)
        autoUpgradeEnabled = state; waitForSettingsReady(0.2)
        if state and not autoUpgradeThread then
            autoUpgradeThread = task.spawn(function()
                if not next(conveyorConfig) then loadConveyorConfig() end
                while autoUpgradeEnabled do
                    if not next(conveyorConfig) then setShopStatus("Waiting for config..."); loadConveyorConfig(); task.wait(1) end
                    local net = getPlayerNetWorth()
                    local acts = chooseAffordableUpgrades(net)
                    if #acts==0 then setShopStatus("Waiting for money (NetWorth "..tostring(net)..")"); task.wait(0.8)
                    else
                        for _, a in ipairs(acts) do
                            setShopStatus(string.format("Upgrading %d (cost %s)", a.idx, tostring(a.cost)))
                            if fireConveyorUpgrade(a.idx) then shopStatus.upgradesDone += 1; purchasedUpgrades[a.idx]=true end
                            shopStatus.upgradesTried += 1; task.wait(0.2)
                        end
                    end
                end
            end)
            setShopStatus("Started upgrading!"); WindUI:Notify({ Title="🛒 Shop", Content="Auto upgrade started!", Duration=3 })
        else
            if not state then setShopStatus("Stopped"); WindUI:Notify({ Title="🛒 Shop", Content="Auto upgrade stopped", Duration=3 }) end
        end
    end
})

Tabs.ShopTab:Button({
    Title="🛒 Upgrade All Now",
    Desc ="Upgrade everything affordable",
    Callback=function()
        local net = getPlayerNetWorth()
        local acts = chooseAffordableUpgrades(net)
        if #acts==0 then setShopStatus("No upgrades affordable (NetWorth "..tostring(net)..")"); return end
        for _, a in ipairs(acts) do
            if fireConveyorUpgrade(a.idx) then shopStatus.upgradesDone += 1; purchasedUpgrades[a.idx]=true end
            shopStatus.upgradesTried += 1; task.wait(0.1)
        end
        setShopStatus("Upgraded "..tostring(#acts).." items!")
    end
})

Tabs.ShopTab:Button({
    Title="🔄 Reset Upgrade Memory",
    Desc ="Clear purchased memory (session)",
    Callback=function()
        purchasedUpgrades = {}; setShopStatus("Memory reset!")
        WindUI:Notify({ Title="🛒 Shop", Content="Upgrade memory cleared!", Duration=3 })
    end
})

--==============================================================
-- 10) PACK TAB: AUTO CLAIM DINO
--==============================================================
local lastDinoAt = 0
local function fireDinoClaim()
    local ok, err = pcall(function() ReplicatedStorage.Remote.DinoEventRE:FireServer({event="onlinepack"}) end)
    if not ok then warn("DinoClaim fire failed: "..tostring(err)) end
    return ok
end
local function getDinoClaimText()
    local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui"); if not pg then return nil end
    local gui = pg:FindFirstChild("ScreenDinoOnLinePack"); if not gui then return nil end
    local root = gui:FindFirstChild("Root"); if not root then return nil end
    local freeBtn = root:FindFirstChild("FreeBtn"); if not freeBtn then return nil end
    local frame = freeBtn:FindFirstChild("Frame"); if not frame then return nil end
    local count = frame:FindFirstChild("Count"); if count and count:IsA("TextLabel") then return count.Text end
    return nil
end
local function getDinoProgressText()
    local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui"); if not pg then return nil end
    local gui = pg:FindFirstChild("ScreenDinoOnLinePack"); if not gui then return nil end
    local root = gui:FindFirstChild("Root"); if not root then return nil end
    local bar = root:FindFirstChild("ProgressBar"); if not bar then return nil end
    local t = bar:FindFirstChild("Text"); if not t then return nil end
    local lbl = t:FindFirstChild("Text"); if lbl and lbl:IsA("TextLabel") then return lbl.Text end
    return nil
end
local function canClaimDino()
    local txt = getDinoClaimText()
    if txt and (txt:find("Claim%(x0%)") or txt:find("Claim%(0%)")) then return false, "No claims remaining" end
    if txt and txt~="" then return true, "Ready to claim" end
    return false, "Cannot read claim status"
end
local function runAutoDino()
    while autoDinoEnabled do
        local ok, reason = canClaimDino()
        if ok then
            if os.clock()-(lastDinoAt or 0) > 2 then
                if fireDinoClaim() then lastDinoAt=os.clock(); WindUI:Notify({ Title="🦕 Auto Claim Dino", Content="Claimed! 🎉", Duration=3 }) end
            end
            task.wait(2)
        else
            task.wait(1)
        end
    end
end

local autoDinoToggle = Tabs.PackTab:Toggle({
    Title="🦕 Auto Claim Dino", Desc="Auto-claim when ready", Value=false,
    Callback=function(state)
        autoDinoEnabled = state; waitForSettingsReady(0.2)
        if state and not autoDinoThread then
            autoDinoThread = task.spawn(function() runAutoDino(); autoDinoThread=nil end)
            WindUI:Notify({ Title="🦕 Auto Claim Dino", Content="Started!", Duration=3 })
        end
    end
})

Tabs.PackTab:Button({
    Title="🦕 Claim Dino Now", Desc="Try claim now",
    Callback=function()
        local ok, reason = canClaimDino()
        if ok then
            if fireDinoClaim() then lastDinoAt=os.clock(); WindUI:Notify({ Title="🦕 Claim Dino", Content="Claimed! 🎉", Duration=3 }) end
        else
            WindUI:Notify({ Title="🦕 Claim Dino", Content="Cannot claim: "..tostring(reason), Duration=3 })
        end
    end
})

Tabs.PackTab:Button({
    Title="🔍 Check Dino Status", Desc="Show current status",
    Callback=function()
        local claimText = getDinoClaimText() or "Unknown"
        local progressText = getDinoProgressText() or "Unknown"
        local ok, reason = canClaimDino()
        local msg = ("Claim Text: "..claimText.."\nProgress: "..progressText.."\nCan Claim: "..tostring(ok).."\nReason: "..tostring(reason))
        WindUI:Notify({ Title="🔍 Dino Status", Content=msg, Duration=8 })
    end
})

--==============================================================
-- 11) FRUIT TAB: SELECTION + AUTO BUY FRUIT
--==============================================================
local FruitSelection = loadstring(game:HttpGet("https://raw.githubusercontent.com/ZebuxHub/Main/refs/heads/main/FruitSelection.lua"))()
local fruitSelectionVisible = false

Tabs.FruitTab:Button({
    Title="🍎 Open Fruit Selection UI",
    Desc ="Pick fruits to auto-buy",
    Callback=function()
        if not fruitSelectionVisible then
            FruitSelection.Show(
                function(sel) selectedFruits = sel; updateCustomUISelection("fruitSelections", sel) end,
                function(v) fruitSelectionVisible=v end,
                selectedFruits
            )
            fruitSelectionVisible=true
        else
            FruitSelection.Hide(); fruitSelectionVisible=false
        end
    end
})

local FruitData = { -- price strings -> parsed on demand
    Strawberry={Price="5,000"}, Blueberry={Price="20,000"}, Watermelon={Price="80,000"},
    Apple={Price="400,000"}, Orange={Price="1,200,000"}, Corn={Price="3,500,000"},
    Banana={Price="12,000,000"}, Grape={Price="50,000,000"}, Pear={Price="200,000,000"},
    Pineapple={Price="600,000,000"}, GoldMango={Price="2,000,000,000"},
    BloodstoneCycad={Price="8,000,000,000"}, ColossalPinecone={Price="40,000,000,000"},
    VoltGinkgo={Price="80,000,000,000"},
}
local function parsePrice(s) return type(s)=="number" and s or tonumber((s or ""):gsub(",","")) or 0 end

local function getFoodStoreLST()
    local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui"); if not pg then return nil end
    local data = pg:FindFirstChild("Data"); if not data then return nil end
    return data:FindFirstChild("FoodStore") and data.FoodStore:FindFirstChild("LST") or nil
end

local function isFruitInStock(fruitId)
    local lst = getFoodStoreLST(); if not lst then return false end
    local cands = { fruitId, fruitId:lower(), fruitId:upper(), fruitId:gsub(" ","_"), fruitId:gsub(" ","_"):lower() }
    for _, k in ipairs(cands) do
        local a = lst:GetAttribute(k)
        if type(a)=="number" and a>0 then return true end
        local lbl = lst:FindFirstChild(k)
        if lbl and lbl:IsA("TextLabel") then
            local n = tonumber((lbl.Text or ""):match("%d+")); if n and n>0 then return true end
        end
    end
    return false
end

local function runAutoBuyFruit()
    while autoBuyFruitEnabled do
        if selectedFruits and next(selectedFruits) then
            local net = getPlayerNetWorth()
            local bought = false
            for fid, on in pairs(selectedFruits) do
                if on and FruitData[fid] then
                    if isFruitInStock(fid) then
                        local price = parsePrice(FruitData[fid].Price)
                        if net >= price then
                            local ok = pcall(function() ReplicatedStorage.Remote.FoodStoreRE:FireServer(fid) end)
                            if ok then bought=true end
                            task.wait(0.5)
                        else
                            task.wait(0.5)
                        end
                    else
                        task.wait(0.5)
                    end
                end
            end
            task.wait(bought and 1 or 2)
        else
            task.wait(2)
        end
    end
end

local autoBuyFruitToggle = Tabs.FruitTab:Toggle({
    Title="🍎 Auto Buy Fruit", Desc="Buy selected fruits when affordable", Value=false,
    Callback=function(state)
        autoBuyFruitEnabled = state; waitForSettingsReady(0.2)
        if state and not autoBuyFruitThread then
            autoBuyFruitThread = task.spawn(function() runAutoBuyFruit(); autoBuyFruitThread=nil end)
            WindUI:Notify({ Title="🍎 Auto Buy Fruit", Content="Started!", Duration=3 })
        end
    end
})

--==============================================================
-- 12) FEED TAB: FEED FRUIT SELECTION + AUTO FEED
--==============================================================
local FeedFruitSelection = loadstring(game:HttpGet("https://raw.githubusercontent.com/ZebuxHub/Main/refs/heads/main/FeedFruitSelection.lua"))()
local AutoFeedSystem     = loadstring(game:HttpGet("https://raw.githubusercontent.com/ZebuxHub/Main/refs/heads/main/AutoFeedSystem.lua"))()
local feedFruitSelectionVisible = false

Tabs.FeedTab:Button({
    Title="🍎 Open Feed Fruit Selection UI",
    Desc ="Choose fruits for feeding",
    Callback=function()
        if not feedFruitSelectionVisible then
            FeedFruitSelection.Show(
                function(sel) selectedFeedFruits = sel; updateCustomUISelection("feedFruitSelections", sel) end,
                function(v) feedFruitSelectionVisible=v end,
                selectedFeedFruits
            )
            feedFruitSelectionVisible = true
        else
            FeedFruitSelection.Hide(); feedFruitSelectionVisible=false
        end
    end
})

local autoFeedToggle = Tabs.FeedTab:Toggle({
    Title="🍽️ Auto Feed Pets", Desc="Feed Big Pets when hungry", Value=false,
    Callback=function(state)
        autoFeedEnabled = state; waitForSettingsReady(0.2)
        if state and not autoFeedThread then
            autoFeedThread = task.spawn(function()
                local function getSelected()
                    if not selectedFeedFruits or not next(selectedFeedFruits) then
                        pcall(function()
                            if isfile("Zebux_FeedFruitSelections.json") then
                                local d = HttpService:JSONDecode(readfile("Zebux_FeedFruitSelections.json"))
                                if d and d.fruits then selectedFeedFruits={}; for _, id in ipairs(d.fruits) do selectedFeedFruits[id]=true end end
                            end
                        end)
                    end
                    return selectedFeedFruits
                end
                local ok, err = pcall(function() AutoFeedSystem.runAutoFeed(autoFeedEnabled, {}, function() end, getSelected) end)
                if not ok then
                    warn("Auto Feed thread error: "..tostring(err))
                    WindUI:Notify({ Title="⚠️ Auto Feed Error", Content="Auto Feed stopped: "..tostring(err), Duration=5 })
                end
                autoFeedThread=nil
            end)
            WindUI:Notify({ Title="🍽️ Auto Feed", Content="Started!", Duration=3 })
        end
    end
})

--==============================================================
-- 13) SAVE TAB: SAVE/LOAD/EXPORT/IMPORT/RESET + ANTI-AFK
--==============================================================
local function registerUIElements()
    local function reg(k, elm) if elm then zebuxConfig:Register(k, elm) end end
    reg("autoBuyEnabled", autoBuyToggle)
    reg("autoHatchEnabled", autoHatchToggle)
    reg("autoClaimEnabled", autoClaimToggle)
    reg("autoPlaceEnabled", autoPlaceToggle)
    reg("autoUnlockEnabled", autoUnlockToggle)
    reg("autoDeleteEnabled", autoDeleteToggle)
    reg("autoDinoEnabled", autoDinoToggle)
    reg("autoUpgradeEnabled", autoUpgradeToggle)
    reg("autoBuyFruitEnabled", autoBuyFruitToggle)
    reg("autoFeedEnabled", autoFeedToggle)
    reg("placeEggDropdown", _G.__placeEggDropdown)
    reg("placeMutationDropdown", _G.__placeMutationDD)
    reg("autoClaimDelaySlider", autoClaimDelaySlider)
    reg("autoDeleteSpeedSlider", autoDeleteSpeedSlider)
end

local function setupAntiAFK()
    if antiAFKEnabled then return end
    antiAFKEnabled = true
    antiAFKConnection = Players.LocalPlayer.Idled:Connect(function()
        local vu = game:GetService("VirtualUser")
        vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
    WindUI:Notify({ Title="🛡️ Anti-AFK", Content="Activated!", Duration=3 })
end

local function disableAntiAFK()
    if not antiAFKEnabled then return end
    antiAFKEnabled=false
    if antiAFKConnection then antiAFKConnection:Disconnect(); antiAFKConnection=nil end
    WindUI:Notify({ Title="🛡️ Anti-AFK", Content="Deactivated.", Duration=3 })
end

Tabs.SaveTab:Section({ Title="💾 Save & Load", Icon="save" })
Tabs.SaveTab:Paragraph({ Title="💾 Settings Manager", Desc="Save your current settings!" , Image="save", ImageSize=18 })

Tabs.SaveTab:Button({
    Title="💾 Manual Save", Desc="Save all settings",
    Callback=function()
        zebuxConfig:Save(); saveCustomSelections()
        WindUI:Notify({ Title="💾 Settings Saved", Content="Saved! 🎉", Duration=3 })
    end
})

Tabs.SaveTab:Button({
    Title="📂 Manual Load", Desc="Load saved settings",
    Callback=function()
        zebuxConfig:Load(); loadCustomSelections(); syncAutoPlaceFiltersFromUI()
        WindUI:Notify({ Title="📂 Settings Loaded", Content="Loaded! 🎉", Duration=3 })
    end
})

Tabs.SaveTab:Button({
    Title="🛡️ Toggle Anti-AFK", Desc="Enable/Disable Anti-AFK",
    Callback=function() if antiAFKEnabled then disableAntiAFK() else setupAntiAFK() end end
})

Tabs.SaveTab:Button({
    Title="🔄 Manual Load Settings", Desc="Load (WindUI + Custom)",
    Callback=function()
        local ok1, e1 = pcall(function() zebuxConfig:Load() end)
        if not ok1 then warn("Load WindUI config failed: "..tostring(e1)) end
        local ok2, e2 = pcall(function() loadCustomSelections() end)
        syncAutoPlaceFiltersFromUI()
        if ok2 then
            WindUI:Notify({ Title="✅ Manual Load", Content="Settings loaded!", Duration=3 })
        else
            warn("Load custom selections failed: "..tostring(e2))
            WindUI:Notify({ Title="⚠️ Manual Load", Content="Loaded but custom failed", Duration=3 })
        end
    end
})

Tabs.SaveTab:Button({
    Title="📤 Export Settings", Desc="Copy to clipboard",
    Callback=function()
        local ok, err = pcall(function()
            local data = { windUIConfig = ConfigManager:AllConfigs(), customSelections = customSelections }
            setclipboard(HttpService:JSONEncode(data))
        end)
        WindUI:Notify({
            Title = ok and "📤 Settings Exported" or "❌ Export Failed",
            Content = ok and "Copied to clipboard! 🎉" or ("Failed: "..tostring(err)),
            Duration = 3
        })
    end
})

Tabs.SaveTab:Button({
    Title="📥 Import Settings", Desc="Paste from clipboard",
    Callback=function()
        local ok, err = pcall(function()
            local data = HttpService:JSONDecode(getclipboard())
            if not data or not data.windUIConfig then error("Invalid format") end
            for cfgName, cfgData in pairs(data.windUIConfig) do
                local cfg = ConfigManager:GetConfig(cfgName); if cfg then cfg:LoadFromData(cfgData) end
            end
            if data.customSelections then customSelections = data.customSelections; saveCustomSelections() end
        end)
        WindUI:Notify({
            Title = ok and "📥 Settings Imported" or "❌ Import Failed",
            Content = ok and "Imported successfully! 🎉" or ("Failed: "..tostring(err)),
            Duration = 3
        })
    end
})

Tabs.SaveTab:Button({
    Title="🔄 Reset Settings", Desc="Reset everything to default",
    Callback=function()
        Window:Dialog({
            Title="🔄 Reset Settings",
            Content="Are you sure to reset all?",
            Icon="alert-triangle",
            Buttons={
                { Title="❌ Cancel", Variant="Secondary", Callback=function() end },
                { Title="✅ Reset", Variant="Primary", Callback=function()
                    local ok, err = pcall(function()
                        -- delete WindUI config file(s)
                        for _, f in ipairs(listfiles("WindUI/Zebux/config")) do
                            if f:match("zebuxConfig%.json$") then delfile(f) end
                        end
                        if isfile("Zebux_CustomSelections.json") then delfile("Zebux_CustomSelections.json") end
                        customSelections = { eggSelections={eggs={},mutations={}}, fruitSelections={}, feedFruitSelections={} }
                        autoBuyEnabled=false; autoHatchEnabled=false; autoClaimEnabled=false; autoPlaceEnabled=false
                        autoUnlockEnabled=false; autoDeleteEnabled=false; autoDinoEnabled=false; autoUpgradeEnabled=false
                        autoBuyFruitEnabled=false; autoFeedEnabled=false
                        selectedTypeSet,selectedMutationSet,selectedFruits,selectedFeedFruits,selectedEggTypes,selectedMutations = {},{},{},{},{},{}
                        -- try soft refresh UIs if exist
                        local function safeRefresh(ui, name)
                            if ui and ui.RefreshContent then pcall(function() ui.RefreshContent() end) end
                        end
                        safeRefresh(EggSelection,"EggSelection")
                        safeRefresh(FruitSelection,"FruitSelection")
                        safeRefresh(FeedFruitSelection,"FeedFruitSelection")
                        WindUI:Notify({ Title="🔄 Settings Reset", Content="All defaults restored! 🎉", Duration=3 })
                    end)
                    if not ok then
                        warn("Reset failed: "..tostring(err))
                        WindUI:Notify({ Title="⚠️ Reset Error", Content="Some items failed to reset.", Duration=3 })
                    end
                end }
            }
        })
    end
})

--==============================================================
-- 14) AUTO-LOAD SETTINGS (AFTER UI EXISTS)
--==============================================================
task.spawn(function()
    task.wait(3)
    WindUI:Notify({ Title="📂 Loading Settings", Content="Loading your saved settings...", Duration=2 })
    registerUIElements()
    zebuxConfig:Load()
    loadCustomSelections()
    syncAutoPlaceFiltersFromUI()
    task.delay(0.5, syncAutoPlaceFiltersFromUI)
    WindUI:Notify({ Title="📂 Auto-Load Complete", Content="Settings loaded! 🎉", Duration=3 })
    settingsLoaded = true
end)

--==============================================================
-- 15) SAFE WINDOW CLOSE
--==============================================================
local ok, err = pcall(function()
    Window:OnClose(function()
        autoBuyEnabled=false; autoPlaceEnabled=false; autoFeedEnabled=false
        autoHatchEnabled=false; autoClaimEnabled=false; autoUnlockEnabled=false
        autoDeleteEnabled=false; autoUpgradeEnabled=false; autoBuyFruitEnabled=false
        autoDinoEnabled=false
        print("UI closed.")
    end)
end)
if not ok then warn("Failed to set window close handler: "..tostring(err)) end

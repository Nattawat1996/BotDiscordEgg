--// =================== Luarmor Loader GUI (Fixed & Full + Auto Close UI) ===================
repeat task.wait() until game:IsLoaded()

-- ========== Replace These Variables ==========
local Hub               = "DemiGodz Hub"
local Hub_Script_ID     = "c124e3a0238a88cf35213a260ddf81d2"   -- <- ค่าเริ่มต้น (default)
local Discord_Invite    = ""   -- เช่น "abc123"
local UI_Theme          = "Dark"  -- "Dark" | "Light" (ตาม Fluent)

-- เปิด/ปิดปุ่มลิงก์รับคีย์ (Ad/Rewards)
local Linkvertise_Enabled = false
local Linkvertise_Link    = ""   -- เช่น https://ads.luarmor.net/get_key?for=YOUR-PROJECT
local Lootlabs_Enabled    = false
local Lootlabs_Link       = ""   -- เช่น https://ads.luarmor.net/get_key?for=YOUR-PROJECT
-- ============================================

-- (ตัวอย่าง) แมปเกม → script_id
local PlaceIDs = {
    -- [PLACE_ID] = "SCRIPT_ID",
    [105555311806207] = "c124e3a0238a88cf35213a260ddf81d2",
}

-- ================== Utilities / Safe wrappers ==================
local function safe(p, ...)
    local ok, res = pcall(p, ...)
    return ok, res
end

local function httpget(url, nobypass)
    local ok, res = pcall(function()
        return game:HttpGet(url, not nobypass)  -- true = bypass cache
    end)
    if ok then return res end
    warn("HttpGet failed:", res)
    return nil
end

-- ================== Pick Script ID (per game.PlaceId) ==================
local CURRENT_SCRIPT_ID = PlaceIDs[game.PlaceId] or Hub_Script_ID

-- ================== File APIs (optional) ==================
local CAN_FS = (typeof(isfile) == "function") and (typeof(writefile) == "function") and (typeof(readfile) == "function")
local function ensureFolder(name)
    if not CAN_FS then return end
    if typeof(makefolder) == "function" then
        pcall(makefolder, name)
    end
end

ensureFolder(Hub)
local KEY_FILE = string.format("%s/Key.txt", Hub)

-- ================== Load UI (Fluent) & Luarmor SDK ==================
local UI = nil
do
    local src = httpget("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua")
    if not src then
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Loader";
            Text  = "โหลด UI ไม่ได้ (GitHub). จะใช้ระบบแจ้งเตือนแบบง่ายแทน";
            Duration = 8;
        })
    else
        local ok, obj = pcall(loadstring(src))
        if ok then UI = obj else warn("Load Fluent failed:", obj) end
    end
end

local API = nil
do
    local src = httpget("https://sdkAPI-public.luarmor.net/library.lua")
    if not src then
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Loader";
            Text  = "โหลด Luarmor SDK ไม่ได้";
            Duration = 8;
        })
        return
    end
    local ok, obj = pcall(loadstring, src)
    if not ok then
        warn("Load SDK failed:", obj)
        return
    end
    API = obj()
    API.script_id = CURRENT_SCRIPT_ID
end

-- ================== Read saved key (optional) ==================
local saved_key = nil
if CAN_FS and isfile(KEY_FILE) then
    local ok, k = pcall(readfile, KEY_FILE)
    if ok and type(k) == "string" and #k > 0 then
        saved_key = k
    end
end

-- ================== Cleanup UI helper (ปิด/ลบ GUI เมื่อผ่านคีย์) ==================
local function cleanupUI()
    -- 1) ถ้า Fluent มีเมธอด Destroy ก็ใช้ก่อน
    if UI and UI.Destroy then
        pcall(function() UI:Destroy() end)
    end
    -- 2) เผื่อบางกรณี Fluent ไม่ลบทั้งหมด: กวาดล้าง ScreenGui ที่เกี่ยวข้อง
    local CoreGui = game:FindFirstChildOfClass("CoreGui")
    if CoreGui then
        for _, g in ipairs(CoreGui:GetChildren()) do
            if g:IsA("ScreenGui") then
                local n = string.lower(g.Name)
                if n:find("fluent") or n:find("loader") or n:find("luarmor") then
                    pcall(function() g:Destroy() end)
                end
            end
        end
    end
end

-- ================== Notify helper ==================
local function notify(title, content, duration)
    duration = duration or 8
    if UI and UI.Notify then
        UI:Notify({ Title = title, Content = content, Duration = duration })
    else
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = title, Text = content, Duration = duration
            })
        end)
        rconsoleprint(string.format("[Notify] %s: %s\n", title, content))
    end
end

-- ================== Key check & load ==================
local function checkKeyAndLoad(input_key)
    local key = tostring(input_key or saved_key or "")
    if key == "" then
        notify("Key Required", "กรุณาใส่คีย์ก่อนใช้งาน", 8)
        return
    end

    -- Luarmor ใช้ตัวแปร script_key (global) ตอนโหลดสคริปต์จริง
    getgenv().script_key = key

    -- 1) ตรวจคีย์ล่วงหน้า
    local ok, status = pcall(function()
        return API.check_key(getgenv().script_key)
    end)

    if not ok or type(status) ~= "table" or not status.code then
        notify("Key Check Failed", "ตรวจคีย์ไม่สำเร็จ (เครือข่าย/บริการ) — ลองใหม่อีกครั้ง", 10)
        return
    end

    if status.code == "KEY_VALID" then
        -- บันทึกคีย์
        if CAN_FS then pcall(function() writefile(KEY_FILE, key) end) end
        notify("Key Valid", "กำลังโหลดสคริปต์จริง...", 4)

        -- 🔻 ปิด/ลบ GUI ทันทีที่ผ่านคีย์ (จุดที่เพิ่ม)
        cleanupUI()

        -- 2) โหลดสคริปต์จริง (Luarmor)
        local ok2, err = pcall(function()
            API.load_script()
        end)
        if not ok2 then
            -- ถ้าโหลดไม่สำเร็จ อาจแจ้งเตือนให้ผู้ใช้รันใหม่ (UI ถูกปิดไปแล้วตามที่ต้องการ)
            notify("Load Failed", "โหลดสคริปต์จริงไม่สำเร็จ: "..tostring(err), 10)
        end
    else
        local map = {
            KEY_INCORRECT    = "คีย์ไม่ถูกต้อง",
            KEY_INVALID      = "คีย์ไม่ถูกต้อง/ไม่มีอยู่",
            KEY_EXPIRED      = "คีย์หมดอายุ",
            KEY_HWID_LOCKED  = "คีย์ติด HWID อุปกรณ์อื่น (โปรดขอรีเซ็ต HWID)",
        }
        notify("Key Not Valid", (map[status.code] or ("ไม่ผ่าน: "..tostring(status.code)))..
            (status.message and (" • "..tostring(status.message)) or ""), 10)
    end
end

-- ================== Auto-check if saved key exists ==================
if saved_key and saved_key ~= "" then
    task.spawn(function()
        task.wait(0.25)
        checkKeyAndLoad(saved_key)
    end)
end

-- ================== Build GUI ==================
if UI and UI.CreateWindow then
    local Window = UI:CreateWindow({
        Title   = Hub,
        SubTitle= "Loader",
        TabWidth= 160,
        Size    = UDim2.fromOffset(580, 320),
        Acrylic = false,
        Theme   = UI_Theme,
        MinimizeKey = Enum.KeyCode.End,
    })

    local Tabs = {
        Main = Window:AddTab({ Title = "Key", Icon = "" })
    }

    local Input = Tabs.Main:AddInput("KeyInput", {
        Title = "Enter Key:",
        Default = saved_key or "",
        Placeholder = "ตัวอย่าง: agKhRikQP..",
        Numeric = false,
        Finished = false,
    })

    if Linkvertise_Enabled and Linkvertise_Link ~= "" then
        Tabs.Main:AddButton({
            Title = "Get Key (Linkvertise)",
            Callback = function()
                if setclipboard then setclipboard(Linkvertise_Link) end
                notify("Copied To Clipboard", "คัดลอกลิงก์รับคีย์ (Linkvertise) แล้ว", 12)
            end,
        })
    end

    if Lootlabs_Enabled and Lootlabs_Link ~= "" then
        Tabs.Main:AddButton({
            Title = "Get Key (Lootlabs)",
            Callback = function()
                if setclipboard then setclipboard(Lootlabs_Link) end
                notify("Copied To Clipboard", "คัดลอกลิงก์รับคีย์ (Lootlabs) แล้ว", 12)
            end,
        })
    end

    Tabs.Main:AddButton({
        Title = "Check Key",
        Callback = function()
            checkKeyAndLoad(Input.Value)
        end,
    })

    Tabs.Main:AddButton({
        Title = "Join Discord",
        Callback = function()
            if Discord_Invite == "" then
                notify("Discord", "ยังไม่ตั้งลิงก์เชิญ Discord_Invite", 8)
                return
            end
            if setclipboard then setclipboard(Discord_Invite) end
            notify("Copied To Clipboard", "คัดลอกลิงก์ Discord แล้ว", 8)

            local HttpService = game:GetService("HttpService")
            local req = http_request or request or syn and syn.request
            if req then
                safe(req, {
                    Url = "http://127.0.0.1:6463/rpc?v=1",
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json", ["origin"] = "https://discord.com" },
                    Body = HttpService:JSONEncode({
                        args = { code = Discord_Invite },
                        cmd  = "INVITE_BROWSER",
                        nonce= "."
                    }),
                })
            end
        end,
    })

    Window:SelectTab(1)
    notify(Hub, "Loader พร้อมใช้งาน", 6)
else
    -- Fallback console
    rconsoleprint("==== "..Hub.." Loader (Console Fallback) ====\n")
    rconsoleprint("วางคีย์ของคุณ แล้วกด Enter:\n")
    if rconsoleinput then
        local key = rconsoleinput()
        checkKeyAndLoad(key)
    else
        notify("Loader", "UI โหลดไม่ได้และไม่มีคอนโซลอินพุต โปรดแก้เน็ต/ตัวรัน", 10)
    end
end
-- =================== End ===================

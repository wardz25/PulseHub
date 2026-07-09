-- PULSE HUB v8 — NodeHub style
-- Left sidebar: Market | List Harga | Snipe
-- Market sub-tabs: Listing | Rejoin | Misc

-- v8.309: AUTO RE-EXEC di PALING AWAL - daftarin queue_on_teleport sebelum apapun.
-- biar pas teleport (HOP/rejoin/anti-bot), queue keburu kedaftar walau script blm kelar.
do
    local SCRIPT_URL = "https://raw.githubusercontent.com/alzafabocahbocah-boop/ronihub/main/market"
    local payload = 'loadstring(game:HttpGet("'..SCRIPT_URL..'"))()'
    local q = queue_on_teleport or (syn and syn.queue_on_teleport) or queueonteleport
    if q then
        pcall(function() q(payload) end)
        warn("[PulseMarket] auto re-exec aktif (queue_on_teleport)")
    else
        warn("[PulseMarket] executor gak support queue_on_teleport")
    end
end

local VERSION = "8.319"
local VERSION_DATE = "v8.304: pisah kotak EXPORT v8.303: fix tombol YA PAKAI ke-block (ZIndex) IMPORT"

warn("============================================")
warn("  PULSE HUB LOADING - VERSI 8.319")
warn("  (kalau ini gak muncul, file lama yg jalan)")
warn("============================================")

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- v8.279: bunuh GUI PULSE HUB lama (dr load sebelumnya) biar gak dobel.
-- DIBUNGKUS task.spawn biar local di dalam gak nambah ke scope chunk utama
-- (Luau limit 200 local/chunk — v8.278 nembus limit gara2 blok ini gak dibungkus).
task.spawn(function()
    pcall(function()
        for _, where in ipairs({ pg, game:GetService("CoreGui") }) do
            for _, g in ipairs(where:GetChildren()) do
                if g:IsA("ScreenGui") and (g.Name == "PulseMarketGui" or g.Name:find("PulseMarket", 1, true)
                   or g.Name:find("PulseV8", 1, true)) then
                    pcall(function() g:Destroy() end)
                end
            end
        end
    end)
end)

_G.PulseV8 = _G.PulseV8 or {}
local function L(s) table.insert(_G.PulseV8, s) print("[ZV8]", s) end

-- ===== v8.46: Anti-AFK (cegah kick karena idle 20 menit) =====
-- v8.107: MULTI-METHOD anti-AFK (cobain semua biar mana yg jalan)
local antiAfkEnabled = true  -- v8.70: di-override dari state file setelah load
do
    -- Method 1: VirtualUser
    local _, VirtualUser = pcall(function() return game:GetService("VirtualUser") end)
    -- Method 2: VirtualInputManager (executor-friendly alternative)
    local _, VIM = pcall(function() return game:GetService("VirtualInputManager") end)
    -- Method 3: Camera nudge
    local lastCamCFrame = nil

    -- Reactive: tangkep player.Idled event (cegah kick langsung)
    if VirtualUser then
        player.Idled:Connect(function()
            if not antiAfkEnabled then return end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(), workspace.CurrentCamera)
            end)
            L("[anti-afk] Idled event → reactive trigger")
        end)
        L("[anti-afk] reactive hook (VirtualUser) installed")
    end

    -- PROAKTIF — periodic loop every 2 min (lebih agresif dari 5 min)
    task.spawn(function()
        local tickCount = 0
        while task.wait(120) do  -- 2 menit
            if antiAfkEnabled then
                tickCount = tickCount + 1
                local methods_tried = {}

                -- Method 1: VirtualUser ClickButton
                if VirtualUser then
                    local ok = pcall(function()
                        VirtualUser:CaptureController()
                        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera)
                        task.wait(0.05)
                        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera)
                    end)
                    table.insert(methods_tried, ok and "VU✓" or "VU✗")
                end

                -- Method 2: VirtualInputManager mouse move
                if VIM then
                    local ok = pcall(function()
                        VIM:SendMouseMoveEvent(100, 100, game)
                        task.wait(0.05)
                        VIM:SendMouseMoveEvent(101, 101, game)
                    end)
                    table.insert(methods_tried, ok and "VIM✓" or "VIM✗")
                end

                -- Method 3: Tiny camera nudge (activity heuristic)
                local cam = workspace.CurrentCamera
                if cam then
                    local ok = pcall(function()
                        local cf = cam.CFrame
                        cam.CFrame = cf * CFrame.new(0.001, 0, 0)
                        task.wait(0.05)
                        cam.CFrame = cf
                    end)
                    table.insert(methods_tried, ok and "CAM✓" or "CAM✗")
                end

                -- Method 4: Character humanoid jump (subtle — only every 5 ticks = 10min)
                if tickCount % 5 == 0 then
                    local char = player.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local ok = pcall(function() hum.Jump = true end)
                        table.insert(methods_tried, ok and "JUMP✓" or "JUMP✗")
                    end
                end

                L("[anti-afk] tick#"..tickCount.." | "..table.concat(methods_tried, " ")
                  .." | next 2min")
            end
        end
    end)
    L("[anti-afk] proactive loop installed (2min, multi-method)")
end

-- ===== v8.28: STATE FILE (BH.myBoothUuid persistence) — semua di BH =====
local BH = {}
do
    BH.STATE_FILE = "PulseMarket_state.json"
    function BH.saveMarketState(s)
        if not writefile then L("[State] ❌ writefile not available — cannot persist"); return end
        -- v8.47: sanitize math.huge → nil (JSON gak support Infinity)
        local clean = {}
        for k, v in pairs(s) do
            if k == "listingRules" and type(v) == "table" then
                clean[k] = {}
                for i, r in ipairs(v) do
                    local cr = {}
                    for rk, rv in pairs(r) do
                        if rv ~= math.huge then cr[rk] = rv end
                    end
                    clean[k][i] = cr
                end
            else
                clean[k] = v
            end
        end
        local ok, err = pcall(function()
            writefile(BH.STATE_FILE, HttpService:JSONEncode(clean))
        end)
        if not ok then L("[State] ❌ save failed: "..tostring(err)) end
    end
    function BH.loadMarketState()
        if not (isfile and readfile and isfile(BH.STATE_FILE)) then
            L("[State] no state file (first run)")
            return {}
        end
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(BH.STATE_FILE)) end)
        if not ok then L("[State] ❌ load failed (corrupt file?)"); return {} end
        local rc = data.listingRules and #data.listingRules or 0
        L("[State] ✅ loaded — rules="..rc.." myBoothUuid="..(data.myBoothUuid and "set" or "none"))
        return data or {}
    end
    BH.marketState = BH.loadMarketState()
    BH.myBoothUuid = BH.marketState.myBoothUuid
    if BH.myBoothUuid then L("[State] cached myBoothUuid: "..BH.myBoothUuid:sub(1,16).."...") end
    -- v8.314: DEFAULT AUTO-ON buat fitur Misc (cuma kalau belum pernah diset user).
    -- auto-start, auto-claim booth, auto-rejoin, auto-switch depan = default ON.
    -- rejoin interval default 25 menit.
    do
        BH.marketState.settings = BH.marketState.settings or {}
        local S = BH.marketState.settings
        if BH.marketState.autoStart == nil then BH.marketState.autoStart = true end
        if S.autoRejoinEnabled == nil then S.autoRejoinEnabled = true end
        if S.autoSwitchFront == nil then S.autoSwitchFront = true end
        -- v8.319: PAKSA rejoin interval 18 menit SELALU tiap load (abaikan setting manual).
        -- semua akun 18m, cegah kick idle 20m. auto-rejoin dipaksa ON.
        S.rejoinIntervalMin = "18"
        S.autoRejoinEnabled = true
        if BH.marketState.autoClaim == nil then BH.marketState.autoClaim = true end
        -- v8.317: PAKSA semua akun (termasuk yg udah punya rules lama) pakai default rules ini.
        -- pakai penanda versi: kalau defaultRulesVer != target, timpa SEKALI lalu tandai.
        -- jadi ketimpa cuma sekali (pas update), abis itu user bebas edit tanpa ketimpa lagi.
        local DEFAULT_RULES_VER = "2026-list-v1"
        if BH.marketState.defaultRulesVer ~= DEFAULT_RULES_VER then
            BH.marketState.listingRules = {
                {type="Brontosaurus", min=6, max=6.4, price=140, maxListings=3},
                {type="Ice Golem", min=6, max=6.4, price=170, maxListings=3},
                {type="Peryton", min=6, max=6.4, price=290, maxListings=3},
                {type="Ruby Squid", min=6, max=6.4, price=129, maxListings=3},
                {type="Reindeer", min=6, max=7, price=150, maxListings=1},
                {type="Reindeer", min=7, max=8, price=100, maxListings=1},
                {type="Nutcracker", min=6, max=7, price=200, maxListings=2},
                {type="Reindeer", min=8, max=9, price=120, maxListings=1},
                {type="Reindeer", min=9, max=10, price=150, maxListings=1},
                {type="Reindeer", min=10, max=11, price=550, maxListings=1},
                {type="Yeti", min=8, max=9, price=3000, maxListings=1},
                {type="Nutcracker", min=7, max=8, price=400, maxListings=1},
                {type="Nutcracker", min=8, max=9, price=600, maxListings=1},
                {type="Nutcracker", min=9, max=10, price=800, maxListings=1},
                {type="Nutcracker", min=10, max=11, price=1500, maxListings=1},
                {type="Gilded Choc Peryton", min=6.2, max=6.4, price=5034, maxListings=1},
                {type="Gilded Choc Peryton", min=6, max=6.2, price=3500, maxListings=1},
                {type="Mimic Octopus", min=6, max=6.4, price=142, maxListings=2},
                {type="Spider", min=6, max=6.4, price=174, maxListings=2},
                {type="Empress Bee", min=6, max=6.4, price=180, maxListings=2},
                {type="Peacock", min=6, max=6.4, price=220, maxListings=2},
                {type="Diamond Panther", min=6, max=6.4, price=133, maxListings=2},
                {type="Fire Wisp", min=6, max=6.4, price=135, maxListings=8},
                {type="Seal", min=6, max=6.4, price=100, maxListings=2},
                {type="Peacock", min=3, max=4, price=98, maxListings=2},
                {type="Mimic Octopus", min=3, max=4, price=102, maxListings=2},
            }
            BH.marketState.defaultRulesVer = DEFAULT_RULES_VER
        end
        pcall(function() BH.saveMarketState(BH.marketState) end)
    end
    -- v8.70: load anti-afk pref dari state (default true kalo gak ada)
    if BH.marketState.antiAfkEnabled ~= nil then
        antiAfkEnabled = BH.marketState.antiAfkEnabled
    end

    -- v8.127: centralized settings save — semua input/toggle bisa persist
    BH.marketState.settings = BH.marketState.settings or {}
    -- v8.133: fix boolean false bug (return false correctly, not default)
    function BH.getSetting(key, default)
        local v = BH.marketState.settings[key]
        if v == nil then return default end
        return v
    end
    function BH.setSetting(key, val)
        BH.marketState.settings[key] = val
        BH.saveMarketState(BH.marketState)
        L("[Settings] saved "..key.."="..tostring(val))  -- v8.133: log
    end
    -- Auto-bind a TextBox to persist its value on FocusLost
    function BH.bindInput(box, key)
        local saved = BH.getSetting(key, nil)
        if saved ~= nil then
            box.Text = tostring(saved)
            L("[Settings] restored input "..key.."="..tostring(saved))
        end
        box.FocusLost:Connect(function() BH.setSetting(key, box.Text) end)
    end
    -- Auto-bind a toggle handle (from addToggleRow) — needs handle to expose .set()
    function BH.bindToggle(handle, key)
        local saved = BH.getSetting(key, nil)
        if saved ~= nil then
            if handle.set then
                handle.set(saved == true)
                L("[Settings] restored toggle "..key.."="..tostring(saved == true))
            else
                L("[Settings] ⚠ "..key..": handle has no .set method")
            end
        end
        -- Wrap getter: each click → save
        local origGet = handle.get
        handle.get = function() return origGet() end
        if handle.onChange then handle.onChange(function(v) BH.setSetting(key, v) end) end
    end
end

-- ===== v8.122: APS (ActivePetsService) — source of truth Age/BaseWeight/Mutation =====
-- ASYNC INIT + PERSISTENT CACHE: bisa cache APS data di garden, pake di market
do
    local ZAPS = {api = nil, mutMap = nil, ready = false}
    local cache, cacheTime = {}, {}
    local dsCache, dsCacheTime = nil, 0
    local TTL, DS_TTL = 5, 8
    local APS_CACHE_FILE = "PulseMarket_APS_cache.json"
    local persistentCache = {}  -- uuid → {BaseWeight, Level, MutationType, savedAt}

    -- Load persistent cache dari file (kalo ada dari sesi sebelumnya di garden)
    pcall(function()
        if isfile and readfile and isfile(APS_CACHE_FILE) then
            local raw = readfile(APS_CACHE_FILE)
            local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
            if ok and type(data) == "table" then
                persistentCache = data
                local cnt = 0
                for _ in pairs(persistentCache) do cnt = cnt + 1 end
                L("[APS] loaded "..cnt.." entries from cache file")
            end
        end
    end)

    -- Save persistent cache to file
    local function savePersistentCache()
        if not writefile then return end
        pcall(function() writefile(APS_CACHE_FILE, HttpService:JSONEncode(persistentCache)) end)
    end

    local function brace(uuid)
        local k = tostring(uuid)
        if k:sub(1,1) ~= "{" then k = "{"..k.."}" end
        return k
    end

    function ZAPS.getPetData(uuid)
        if not ZAPS.api or not uuid then return nil end
        local key = brace(uuid)
        local now = tick()
        if cache[key] and (now - (cacheTime[key] or 0)) < TTL then return cache[key] end
        local ok, info = pcall(function() return ZAPS.api:GetPetData(player.Name, key) end)
        if ok and info and info.PetData then
            cache[key] = info; cacheTime[key] = now
            return info
        end
        return nil
    end

    function ZAPS.getAllPets()
        if not ZAPS.api then return {} end
        local now = tick()
        if dsCache and (now - dsCacheTime) < DS_TTL then return dsCache end
        local ok, ds = pcall(function() return ZAPS.api:GetPlayerDatastorePetData(player.Name) end)
        if ok and ds and ds.PetInventory and ds.PetInventory.Data then
            dsCache = ds.PetInventory.Data; dsCacheTime = now
            return dsCache
        end
        return {}
    end

    function ZAPS.getAge(uuid)
        -- v8.124: Priority 0 = memory container
        if ZAPS.memContainer then
            local key = brace(uuid)
            local entry = ZAPS.memContainer[key]
            if type(entry) == "table" and entry.PetData and entry.PetData.Level then
                return entry.PetData.Level
            end
        end
        local info = ZAPS.getPetData(uuid)
        if info and info.PetData and info.PetData.Level then return info.PetData.Level end
        -- fallback ke persistent cache
        local key = brace(uuid)
        local pc = persistentCache[key]
        if pc and pc.Level then return pc.Level end
        return nil
    end

    function ZAPS.getBaseKg(uuid)
        local key = brace(uuid)
        -- v8.124: Priority 0 = memory container (bypass require, works di market!)
        if ZAPS.memContainer then
            local entry = ZAPS.memContainer[key]
            if type(entry) == "table" and entry.PetData and entry.PetData.BaseWeight then
                return entry.PetData.BaseWeight
            end
        end
        -- Priority 1: query langsung 1 pet via API
        local info = ZAPS.getPetData(uuid)
        if info and info.PetData and info.PetData.BaseWeight then return info.PetData.BaseWeight end
        -- v8.245 Priority 2: DATASTORE LENGKAP (seluruh inventory, termasuk pet yg gak
        -- ada di memory container & gak lagi dipegang). Ini sumber BaseWeight paling lengkap.
        local ds = ZAPS.getAllPets()
        if ds then
            local entry = ds[key] or ds[tostring(uuid)] or ds[(tostring(uuid):gsub("[{}]",""))]
            if type(entry) == "table" and entry.PetData and entry.PetData.BaseWeight then
                return entry.PetData.BaseWeight
            end
        end
        -- fallback ke persistent cache
        local pc = persistentCache[key]
        if pc and pc.BaseWeight then return pc.BaseWeight end
        return nil
    end

    -- v8.124: scan getgc untuk find UUID→PetData container (bypass require!)
    function ZAPS.findMemoryContainer()
        if not getgc then return nil, 0 end
        local best, bestCount, bestScore = nil, 0, 0
        -- v8.248: kumpulin UUID pet kita sendiri (dari backpack) buat verifikasi container yg BENAR
        local myUuids = {}
        pcall(function()
            local plr = Players.LocalPlayer
            local bp = plr and plr:FindFirstChild("Backpack")
            if bp then
                for _, t in ipairs(bp:GetChildren()) do
                    if t:IsA("Tool") then
                        local u = t:GetAttribute("PET_UUID")
                        if u then
                            local k = tostring(u)
                            if k:sub(1,1) ~= "{" then k = "{"..k.."}" end
                            myUuids[k] = true
                        end
                    end
                end
            end
        end)
        local ok = pcall(function()
            for _, obj in pairs(getgc(true)) do
                if type(obj) == "table" then
                    -- v8.248: hitung entry valid (key string UUID-like + value tabel ber-PetData).
                    -- Cek banyak entry, bukan cuma 1 sample (lebih robust).
                    local validEntries = 0
                    local containsMine = false
                    local scanned = 0
                    for k, v in pairs(obj) do
                        if type(k) == "string" and #k >= 32 and k:find("-")
                           and type(v) == "table" and rawget(v, "PetData") then
                            validEntries = validEntries + 1
                            if myUuids[k] then containsMine = true end
                        end
                        scanned = scanned + 1
                        if scanned > 800 then break end  -- jangan scan tabel kegedean
                    end
                    if validEntries >= 3 then
                        -- v8.248: container yg BERISI pet kita SELALU menang (paling akurat,
                        -- mirip cek "sample UUID in container: YES"). Kalo gak ketemu, pilih terbesar.
                        local score = validEntries + (containsMine and 1000000 or 0)
                        if score > bestScore then
                            best = obj; bestCount = validEntries; bestScore = score
                        end
                    end
                end
            end
        end)
        return best, bestCount
    end

    -- v8.122: populate persistent cache dari APS (call kalo APS work)
    -- Cache semua pet di datastore, save ke file
    function ZAPS.populateCache()
        if not ZAPS.api then return 0 end
        local ds = ZAPS.getAllPets()
        local newCount = 0
        for uuid, entry in pairs(ds) do
            if entry.PetData then
                local pd = entry.PetData
                if pd.BaseWeight and pd.Level then
                    persistentCache[uuid] = {
                        BaseWeight = pd.BaseWeight,
                        Level = pd.Level,
                        MutationType = pd.MutationType,
                        savedAt = os.time(),
                    }
                    newCount = newCount + 1
                end
            end
        end
        if newCount > 0 then
            savePersistentCache()
            L("[APS] populated cache: "..newCount.." pets saved to file")
        end
        return newCount
    end

    -- v8.120: diagnostic — sample lookup buat verify APS bener-bener kasih data
    function ZAPS.diagnose()
        if not ZAPS.api then L("[APS-DIAG] api=nil"); return end
        local bp = player and player:FindFirstChild("Backpack")
        if not bp then return end
        local sample, sampleCount = nil, 0
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("PET_UUID") then
                sampleCount = sampleCount + 1
                if not sample then sample = t end
                if sampleCount >= 3 then break end
            end
        end
        if not sample then L("[APS-DIAG] no pet in bp"); return end
        local uuid = sample:GetAttribute("PET_UUID")
        local braced = tostring(uuid)
        if braced:sub(1,1) ~= "{" then braced = "{"..braced.."}" end
        local ok, info = pcall(function() return ZAPS.api:GetPetData(player.Name, braced) end)
        L("[APS-DIAG] sample '"..sample.Name.."' uuid="..braced:sub(1,20).."...")
        L("[APS-DIAG] ok="..tostring(ok).." has PetData="..tostring(info and info.PetData and true or false))
        if ok and info and info.PetData then
            L("[APS-DIAG] Level="..tostring(info.PetData.Level)..
              " BaseWeight="..tostring(info.PetData.BaseWeight)..
              " MutationType="..tostring(info.PetData.MutationType))
        end
    end

    function ZAPS.getMutation(uuid)
        -- v8.124: Priority 0 = memory container
        if ZAPS.memContainer then
            local key = brace(uuid)
            local entry = ZAPS.memContainer[key]
            if type(entry) == "table" and entry.PetData and entry.PetData.MutationType then
                local code = entry.PetData.MutationType
                local name = ZAPS.mutMap and ZAPS.mutMap[code] or tostring(code)
                return code, name
            end
        end
        local info = ZAPS.getPetData(uuid)
        if info and info.PetData and info.PetData.MutationType then
            local code = info.PetData.MutationType
            local name = ZAPS.mutMap and ZAPS.mutMap[code] or tostring(code)
            return code, name
        end
        return nil, nil
    end

    function ZAPS.isFav(uuid)
        local info = ZAPS.getPetData(uuid)
        if info and info.PetData then return info.PetData.IsFavorite == true end
        return false
    end

    getgenv().PulseAPS = ZAPS

    -- v8.124: GETGC-FIRST INIT — bypass require entirely!
    -- Game's own scripts udah load APS data ke memory. getgc baca langsung.
    task.spawn(function()
        -- Step 1: Scan getgc untuk memory container (FAST + RELIABLE)
        ZAPS.memContainer, ZAPS.memContainerCount = ZAPS.findMemoryContainer()
        if ZAPS.memContainer then
            L("[APS] memContainer FOUND: "..ZAPS.memContainerCount.." entries (bypass require!)")
        else
            L("[APS] memContainer NOT FOUND — fallback ke require")
        end

        -- Step 2: SELALU coba require (buat datastore lengkap + fallback + mutMap)
        -- v8.245: dulu cuma di-require kalo container GAGAL. Padahal container sering cuma
        -- berisi sebagian pet (yg lagi aktif). API datastore = SELURUH inventory + BaseWeight.
        do
            local attempt = 0
            while not ZAPS.api and attempt < 3 do
                attempt = attempt + 1
                local attemptDone = false
                task.spawn(function()
                    pcall(function()
                        local modules = RS:FindFirstChild("Modules")
                        if not modules then return end
                        local petServices = modules:FindFirstChild("PetServices")
                        if not petServices then return end
                        local apsMod = petServices:FindFirstChild("ActivePetsService")
                        if not apsMod then return end
                        ZAPS.api = require(apsMod)
                    end)
                    attemptDone = true
                end)
                local waited = 0
                while not attemptDone and waited < 5 do task.wait(0.5); waited = waited + 0.5 end
                if not ZAPS.api and attempt < 3 then task.wait(3) end
            end
        end

        -- Step 3: Load mutMap (untuk decode MutationType code → name)
        pcall(function()
            local data = RS:FindFirstChild("Data")
            if not data then return end
            local petReg = data:FindFirstChild("PetRegistry")
            if not petReg then return end
            local mutReg = petReg:FindFirstChild("PetMutationRegistry")
            if not mutReg then return end
            local mr = require(mutReg)
            if mr and mr.EnumToPetMutation then ZAPS.mutMap = mr.EnumToPetMutation end
        end)

        ZAPS.ready = true
        L("[APS] FINAL: memContainer="..(ZAPS.memContainer and ZAPS.memContainerCount.." entries" or "FAIL")..
          " api="..(ZAPS.api and "OK" or "FAIL")..
          " mutMap="..(ZAPS.mutMap and "OK" or "FAIL"))
        -- v8.245: cek datastore lengkap (sumber BaseWeight semua pet)
        if ZAPS.api then
            task.spawn(function()
                local ds = ZAPS.getAllPets()
                local n = 0
                if type(ds) == "table" then for _ in pairs(ds) do n = n + 1 end end
                L("[APS] datastore inventory: "..n.." pets (BaseWeight tersedia tanpa pegang pet)")
            end)
        else
            L("[APS] ⚠ api=FAIL → datastore gak bisa diakses. BaseWeight cuma dari container/pegang pet.")
        end

        -- Populate persistent cache kalo ada memContainer
        if ZAPS.memContainer then
            task.wait(0.5)
            local cnt = 0
            for uuid, entry in pairs(ZAPS.memContainer) do
                if type(entry) == "table" and entry.PetData and entry.PetData.BaseWeight then
                    persistentCache[uuid] = {
                        BaseWeight = entry.PetData.BaseWeight,
                        Level = entry.PetData.Level,
                        MutationType = entry.PetData.MutationType,
                        savedAt = os.time(),
                    }
                    cnt = cnt + 1
                end
            end
            if cnt > 0 then savePersistentCache(); L("[APS] saved "..cnt.." entries to cache file") end
        end

        -- UI refresh
        task.wait(0.3)
        pcall(function()
            if BH.refreshPriceCounts then BH.refreshPriceCounts() end
        end)

        -- Periodic memContainer re-scan (catch new pets/keep reference live)
        -- v8.238: akun baru sering telat load container — scan agresif di awal
        task.spawn(function()
            -- 2 menit pertama: scan tiap 5 detik (cepet detect di akun baru)
            for i = 1, 24 do
                task.wait(5)
                local new, newCnt = ZAPS.findMemoryContainer()
                if new and newCnt > 0 then
                    ZAPS.memContainer = new; ZAPS.memContainerCount = newCnt
                    if BH.refreshPriceCounts then pcall(BH.refreshPriceCounts) end
                end
            end
            -- setelah itu: scan tiap 60 detik
            while true do
                task.wait(60)
                local new, newCnt = ZAPS.findMemoryContainer()
                if new and newCnt > 0 then
                    ZAPS.memContainer = new; ZAPS.memContainerCount = newCnt
                end
            end
        end)
    end)
end

-- ===== v8.35: MUTATION strip helper (sync sama inventory.lua) =====
do
    BH.MUTATION_NAMES = {
        -- Single-word mutations (sorted alphabetical)
        "Alienated","Ancient","Angelic","Aromatic","Ascended","Astral","Aurora",
        "Bearded","Blazing","Blessed","Blossoming","Bloodlust",
        "Celestial","Chaotic","Chilled","Chocolate","Christmas","Chromatic","Corrupt","Corrupted",
        "Cosmic","Crocodile","Crystal","Cursed",
        "Dawn","Demonic","Diamond","Disco","Divine","Dreadbound",
        "Eclipse","Eclipsed","Eldritch","Enchanted","Ethereal","Everchanted",
        "Fiery","Forger","Fried","Frostbite","Frozen",
        "Galactic","GIANT","Giraffe","Ghostly","Glacial","Glimmering","Gold","Golden",
        "HyperHunger","Holy",
        "Icy","Infernal","Inferno","Inverted","IronSkin",
        "JollyDecorator","JUMBO",
        "Lion","Lunar","Luminous",
        "Mega","MerryNursery","Mimic","Mini","Moonlit","Mystic","Mythic",
        "Nightmare","Nocturnal","Nutty",
        "Oxpecker",
        "Peppermint","Phantom","Plasma","Prismatic","Primal",
        "Radiant","Rainbow","Rhino","Rideable","Royal",
        "Shadow","Shiny","Shocked","Silver","SpiritSparkle","Solar","Soulflame","Sparkling","Spectral","Starlit","Stellar","Storm",
        "Tempest","Tethered","Tiny","Toxic","Tranquil","Twilight",
        "UFO",
        "Venom","Verdant","Volcanic",
        "Wet","Windy",
        "Zombified",
        -- Multi-word variants
        "Christmas Rally","ChristmasRally",
        "Giant Bean","GiantBean",
        "Giant Golem","GiantGolem",
        "Hyper Hunger",
        "Iron Skin",
        "Jolly Decorator",
        "Merry Nursery","MerryNursery",
        "Spirit Sparkle",
    }

    -- v8.91: Comprehensive list of Grow A Garden pet types (sorted alphabetical)
    -- Used by Auto Snipe picker to show ALL pets, not just yang ada di server
    BH.PET_NAMES = {
        "Anchovy","Ankylosaurus","Axolotl",
        "Bald Eagle","Bandit Raccoon","Bat","Bear Bee","Bee","Black Bunny",
        "Blood Hedgehog","Blood Kiwi","Blood Owl","Brontosaurus","Brown Mouse",
        "Bunny","Butterfly",
        "Capybara","Carnotaurus","Cat","Caterpillar","Cerberus","Cheetah",
        "Chicken","Chocolate Crow","Chocolate Lab","Compsognathus","Cooked Owl",
        "Cow","Crab","Cyclops",
        "Demon","Dilophosaurus","Disco Bee","Dog","Dragonfly","Duck",
        "Echo Frog","Elephant",
        "Falcon","Fennec Fox","Firefly","Flamingo","Frog","Frosted Owl",
        "Giant Ant","Giraffe","Gold Fish","Golden Bee","Golden Lab","Grey Mouse",
        "Griffin",
        "Hamster","Hedgehog","Honey Bee","Horse","Hyena",
        "Iguanodon",
        "Jaguar","Jellyfish",
        "Kappa","Kiwi","Koala","Koi",
        "Lich","Lion","Lobster","Lobster King",
        "Manatee","Manticore","Megalodon","Microraptor","Mimic Octopus",
        "Mole","Monkey","Mosasaurus","Moth","Mythic Egg",
        "Night Owl",
        "Octopus","Orange Tabby","Ostrich","Otter","Owl",
        "Pachycephalosaurus","Panda","Parrot","Peacock","Penguin","Petal Bee",
        "Phoenix","Pig","Plesiosaurus","Polar Bear","Praying Mantis","Pterodactyl",
        "Queen Bee",
        "Raccoon","Raptor","Red Dragon","Red Fox","Red Giant Ant","Rhino","Rooster",
        "Salamander","Scorpion","Sea Otter","Sea Turtle","Seagull","Seal","Shark",
        "Silver Monkey","Skunk","Sloth","Snail","Sphinx","Spinosaurus","Spotted Deer",
        "Squirrel","Starfish","Stegosaurus","Sun Bear","Swan",
        "T-Rex","Tarantula Hawk","Tiger","Toucan","Tortoise","Triceratops","Turtle",
        "Unicorn",
        "Vampire Bat","Vulture",
        "Walrus","Wasp","Whale","Wolf",
        "Yeti",
        "Zebra",
        -- new/event pets
        "Easter Bunny","Witch Cat","Pumpkin Cat","Skeleton Dog",
        "Spirit Fox","Festive Fawn","Holiday Owl",
        "Gilded Choc Peryton","Peryton",
    }

    -- v8.92: Discover ALL pet types dari game data (game punya ~421 pet)
    -- Path persis dari revsy.lua: RS.Data.PetRegistry.PetList (421 pets)
    -- Fallback: RS.Assets.Animations.PetAnimations (204 pets)
    BH.discoverPetNames = function()
        local found = {}
        local RS = game:GetService("ReplicatedStorage")

        -- Primary: RS.Data.PetRegistry.PetList (require'd module, keys = pet names)
        pcall(function()
            local petList = RS:FindFirstChild("Data")
                and RS.Data:FindFirstChild("PetRegistry")
                and RS.Data.PetRegistry:FindFirstChild("PetList")
            if petList then
                local ok, mod = pcall(function() return require(petList) end)
                if ok and type(mod) == "table" then
                    for petName, _ in pairs(mod) do
                        if type(petName) == "string" and #petName > 1 then
                            found[petName] = true
                        end
                    end
                end
            end
        end)

        -- Fallback: RS.Assets.Animations.PetAnimations (children = pet names)
        pcall(function()
            local petAnim = RS:FindFirstChild("Assets")
                and RS.Assets:FindFirstChild("Animations")
                and RS.Assets.Animations:FindFirstChild("PetAnimations")
            if petAnim then
                for _, p in ipairs(petAnim:GetChildren()) do
                    local n = p.Name
                    if n and #n > 1 then
                        found[n] = true
                    end
                end
            end
        end)

        local list = {}
        for name in pairs(found) do table.insert(list, name) end
        local count = #list
        if count > 0 then
            L("[PetDiscover] found "..count.." pet types from RS.Data.PetRegistry.PetList")
        else
            L("[PetDiscover] gak nemu PetRegistry — pake hardcoded list fallback")
        end
        return list
    end

    -- Run discover saat module load (silently)
    BH.PET_NAMES_DISCOVERED = {}
    BH.PET_NAMES_SET = {}  -- v8.104: set untuk O(1) lookup
    task.spawn(function()
        task.wait(2)  -- kasih waktu RS replicate
        local ok, names = pcall(BH.discoverPetNames)
        if ok and names and #names > 0 then
            BH.PET_NAMES_DISCOVERED = names
            -- v8.104: build set version
            for _, n in ipairs(names) do BH.PET_NAMES_SET[n] = true end
        end
    end)
    BH.MUTATION_PREFIXES = {}
    for _, m in ipairs(BH.MUTATION_NAMES) do
        table.insert(BH.MUTATION_PREFIXES, m..", ")  -- "Galactic, "
        table.insert(BH.MUTATION_PREFIXES, m.." ")   -- "Galactic "
    end

    -- v8.69: Mutation multipliers — seed + auto-learn at runtime
    -- mult = displayed_kg_at_age_1 / raw_BaseWeight
    BH.MUTATION_MULT = {
        -- Confirmed seed values
        Everchanted = 1.10,
        EV          = 1.10,  -- legacy short-code (kalo server return code instead of name)
        -- Mutation lain auto-learned saat script lihat pet-nya
    }

    -- v8.69: Helper — convert kg saat ini ke kg pas age 1 (growth formula linear)
    function BH.kgAtAge1(currentKg, age)
        if not currentKg or not age or age < 1 then return nil end
        if age == 1 then return currentKg end
        return currentKg * 11 / (age + 10)
    end

    -- v8.69: Learn mult dari satu sample. Aman dipanggil berulang.
    function BH.learnMutationMult(mut, baseWeight, displayedKgAtAge1)
        if not mut or mut == "" or mut == "None" then return false end
        if not baseWeight or baseWeight <= 0 then return false end
        if not displayedKgAtAge1 or displayedKgAtAge1 <= 0 then return false end
        local mult = displayedKgAtAge1 / baseWeight
        -- Sanity check: mult masuk akal antara 0.5x – 5x
        if mult < 0.5 or mult > 5.0 then return false end
        local existing = BH.MUTATION_MULT[mut]
        -- Prefer sample baru kalo beda signifikan, atau first time
        if not existing or math.abs(existing - mult) > 0.02 then
            BH.MUTATION_MULT[mut] = mult
            L(string.format("[MutLearn] '%s' mult = %.4f (base=%.3f, kg@1=%.3f)",
                mut, mult, baseWeight, displayedKgAtAge1))
            return true
        end
        return false
    end

    -- v8.69: Scan TBC data, auto-learn semua mutation yang ke-detect
    function BH.autoLearnMutations()
        if not BH.TBC then return 0 end
        local data = BH.getMyBoothData()
        if not data or not data.Items then return 0 end
        local learned = 0
        for _, item in pairs(data.Items) do
            if item.PetData then
                local pd = item.PetData
                local mut = pd.MutationType
                if mut and mut ~= "" and mut ~= "None" then
                    local bw = pd.BaseWeight
                    -- Defensive: petData field name bisa beda-beda
                    local currentKg = pd.Weight or pd.CurrentWeight or pd.Kg or pd.kg
                    local age = pd.Age or pd.Level or pd.age
                    if bw and currentKg and age then
                        local kgAt1 = BH.kgAtAge1(currentKg, age)
                        if BH.learnMutationMult(mut, bw, kgAt1) then
                            learned = learned + 1
                        end
                    end
                end
            end
        end
        if learned > 0 then
            L(string.format("[MutLearn] %d mutation baru ke-learn dari TBC", learned))
        end
        return learned
    end

    -- v8.46: TradeBoothController — kunci akses data booth server-wide
    BH.TBC = nil
    pcall(function()
        local Modules = RS:WaitForChild("Modules", 10)
        local TBCFolder = Modules and Modules:WaitForChild("TradeBoothControllers", 5)
        local TBCModule = TBCFolder and TBCFolder:WaitForChild("TradeBoothController", 5)
        if TBCModule then BH.TBC = require(TBCModule) end
    end)
    if BH.TBC then L("✓ TBC loaded — booth data via API") else L("⚠ TBC gak ke-load, fallback ke workspace scan") end

    -- v8.46: Fetch booth data dari TBC (work tanpa TP, tanpa streaming)
    function BH.fetchBoothData(targetPlayer)
        if not BH.TBC then return nil end
        targetPlayer = targetPlayer or player
        local ok, data = pcall(function() return BH.TBC:GetPlayerBoothData(targetPlayer) end)
        if ok and type(data) == "table" then return data end
        return nil
    end

    function BH.getMyBoothData()
        return BH.fetchBoothData(player)
    end

    -- v8.46: Compute base weight as displayed at age 1 (sesuai rule lama)
    -- Formula: BaseWeight × mutation_multiplier
    function BH.computeBaseKgFromPetData(petData)
        if not petData then return 0 end
        -- v8.109: pake raw BaseWeight langsung (server authoritative), NO mut multiplier
        return petData.BaseWeight or 0
    end

    -- v8.46: Count active listings dari TBC data (akurat, no streaming)
    -- v8.47: accept optional dataIn untuk skip redundant fetches
    function BH.countActiveFromData(rule, dataIn)
        local data = dataIn or BH.getMyBoothData()
        if not data or not data.Listings then return 0 end
        local count = 0
        for _, listing in pairs(data.Listings) do
            if listing.ItemType == "Pet" and listing.ItemId then
                local item = data.Items and data.Items[listing.ItemId]
                if item and item.PetData then
                    local rawType = tostring(item.PetType or "")
                    -- v8.180: strip mutation prefix biar "Frozen Ice Golem" match rule "Ice Golem"
                    local pBase = (BH.getBaseName and rawType ~= "") and BH.getBaseName(rawType) or rawType
                    -- v8.180: KG basis age-1 normalized (× 1.1) — match dgn rule input
                    local bw = tonumber(item.PetData.BaseWeight) or 0
                    local baseKg = bw * 1.1
                    local typeOk = (not rule.type) or rule.type == pBase or rule.type == rawType
                    local kgOk = baseKg >= rule.min and baseKg <= rule.max
                    if typeOk and kgOk then count = count + 1 end
                end
            end
        end
        return count
    end

    -- v8.46: Detect booth-mu dari TBC (no scan, no streaming)
    function BH.detectMyBoothFromTBC()
        local data = BH.getMyBoothData()
        if data and data.Booth then
            local clean = tostring(data.Booth):gsub("[{}]", "")
            if clean ~= "" then
                BH.myBoothUuid = clean
                -- v8.131 CRITICAL FIX: merge ke marketState, JANGAN replace
                -- sebelumnya: saveMarketState({myBoothUuid=clean}) → WIPE semua state lain
                BH.marketState.myBoothUuid = clean
                pcall(function() BH.saveMarketState(BH.marketState) end)
                return clean
            end
        end
        return nil
    end

    function BH.getBaseName(name)
        if not name or name == "" then return name end
        -- v8.104: kalo nama input PERSIS pet name (e.g. "Mimic Octopus"), return as-is
        -- Cegah strip-an salah ("Mimic Octopus" → "Octopus") karena "Mimic" ke-overlap mutation list
        if BH.PET_NAMES_SET and BH.PET_NAMES_SET[name] then
            return name
        end
        local result = name
        local changed = true
        -- Strip multi-layer mutations (e.g. "Shocked, Galactic Peacock" → "Peacock")
        while changed do
            changed = false
            for _, prefix in ipairs(BH.MUTATION_PREFIXES) do
                if result:sub(1, #prefix) == prefix then
                    local stripped = result:sub(#prefix + 1)
                    if stripped == "" then break end
                    result = stripped
                    changed = true
                    -- v8.104: kalo hasil strip udah match pet name valid, STOP (don't over-strip)
                    if BH.PET_NAMES_SET and BH.PET_NAMES_SET[result] then
                        return result
                    end
                    break
                end
            end
        end
        return result
    end
end

-- ===== v8.37: maxKGCache — tiru inventory.lua untuk mutated pet detection =====
-- Mutated pet Tool.Name gak punya [Age N], tapi base type sama (e.g. "Everchanted Peacock" → "Peacock")
-- Strategy: cache baseKG dari non-mutated yang punya age → reuse buat mutated
do
    BH.maxKGCache = {}

    -- Parse pet display name dari Tool.Name (sebelum "[")
    function BH.getPetName(item)
        local n = item.Name or ""
        return n:match("^(.-)%s*%[") or n
    end

    -- Parse age dari item (return nil kalo gak ketemu)
    function BH.getAgeFromItem(item)
        -- Try attribute
        for _, attr in ipairs({"Age","age","Level","Lvl","PetAge","PetLevel"}) do
            local v = item:GetAttribute(attr)
            if v and tonumber(v) and tonumber(v) >= 1 then return tonumber(v) end
        end
        -- Try child
        for _, name in ipairs({"Age","age","Level","Lvl"}) do
            local c = item:FindFirstChild(name)
            if c and c:IsA("ValueBase") and tonumber(c.Value) then return tonumber(c.Value) end
        end
        -- Parse name
        local n = item.Name or ""
        for _, pat in ipairs({
            "%[Age%s+(%d+)%]","%[Age(%d+)%]",
            "%[Lv%s+(%d+)%]","%[Level%s+(%d+)%]","%[Lvl%s+(%d+)%]",
        }) do
            local m = n:match(pat) if m then return tonumber(m) end
        end
        if n:match("%[Age%s*MAX%]") or n:match("%[MAX%]") then return 100 end
        return nil
    end

    -- Parse current KG dari Tool.Name "[X.XX KG]"
    function BH.getKGFromItem(item)
        local n = item.Name or ""
        local kg = n:match("%[([%d.]+)%s*KG%]")
        return kg and tonumber(kg) or nil
    end

    -- Scan backpack, build cache dari pet yang punya age
    function BH.buildMaxKGCache()
        BH.maxKGCache = {}
        local bp = player:FindFirstChild("Backpack")
        if not bp then return end
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and (item:FindFirstChild("PetToolLocal") or item:GetAttribute("PET_UUID")) then
                local name = BH.getPetName(item)
                local age = BH.getAgeFromItem(item)
                local kg = BH.getKGFromItem(item)
                if name and age and kg and age >= 1 then
                    local baseKG = kg * 11 / (age + 10)
                    -- Index by full name + base name
                    local existing = BH.maxKGCache[name]
                    if not existing or baseKG > existing then BH.maxKGCache[name] = baseKG end
                    local base = BH.getBaseName(name)
                    if base ~= name then
                        local existingBase = BH.maxKGCache[base]
                        if not existingBase or baseKG > existingBase then BH.maxKGCache[base] = baseKG end
                    end
                end
            end
        end
        -- v8.69: auto-learn mutation multipliers sekalian
        pcall(function() BH.autoLearnMutations() end)
    end

    -- Lookup cache: try by Tool.Name, then f attribute (booth tool fallback)
    function BH.getCachedBaseKG(item)
        if type(item) == "string" then
            -- Backward compat: kalo dikasih string (name)
            if BH.maxKGCache[item] then return BH.maxKGCache[item] end
            local base = BH.getBaseName(item)
            if BH.maxKGCache[base] then return BH.maxKGCache[base] end
            return nil
        end
        -- Item-based lookup
        if not item then return nil end
        -- Try 1: by display name (backpack pets)
        local name = BH.getPetName(item)
        if name and BH.maxKGCache[name] then return BH.maxKGCache[name] end
        if name then
            local base = BH.getBaseName(name)
            if BH.maxKGCache[base] then return BH.maxKGCache[base] end
        end
        -- Try 2: by f attribute (booth tools where Name is "{uuid}")
        local ok, f = pcall(function() return item:GetAttribute("f") end)
        if ok and f then
            local fStr = tostring(f)
            if BH.maxKGCache[fStr] then return BH.maxKGCache[fStr] end
            local fBase = BH.getBaseName(fStr)
            if BH.maxKGCache[fBase] then return BH.maxKGCache[fBase] end
        end
        return nil
    end
end

local CoreGui = game:GetService("CoreGui")
pcall(function() CoreGui:FindFirstChild("PulseV8"):Destroy() end)
local gui = Instance.new("ScreenGui") gui.Name = "PulseV8" gui.Parent = CoreGui gui.ResetOnSpawn = false

-- ===== STYLE =====
local C = {
    bg = Color3.fromRGB(8, 8, 8),
    panel = Color3.fromRGB(15, 15, 15),
    card = Color3.fromRGB(22, 22, 22),
    input = Color3.fromRGB(28, 28, 28),
    accent = Color3.fromRGB(255, 215, 0),
    accentDim = Color3.fromRGB(180, 150, 0),
    text = Color3.fromRGB(245, 245, 245),
    textDim = Color3.fromRGB(160, 160, 160),
    success = Color3.fromRGB(80, 200, 130),
    danger = Color3.fromRGB(220, 80, 90),
}
-- v8.250: di server GARDEN, ganti accent gold → merah crimson gelap (elegan, bukan norak).
-- Server market tetep gold. Deteksi: garden = gak ada Workspace.TradeWorld.
if Workspace:FindFirstChild("TradeWorld") == nil then
    C.accent = Color3.fromRGB(200, 50, 55)
    C.accentDim = Color3.fromRGB(140, 30, 35)
end
local FB = Enum.Font.GothamBold
local FM = Enum.Font.GothamMedium
local F = Enum.Font.Gotham

-- ===== MAIN FRAME =====
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 640, 0, 400) main.Position = UDim2.new(0.5, -320, 0.5, -200)
main.BackgroundColor3 = C.bg main.BorderSizePixel = 0
main.Active = true main.Draggable = true main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = C.accent mainStroke.Thickness = 2

-- ===== TITLE BAR =====
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 44) titleBar.BackgroundTransparency = 1 titleBar.Parent = main

local logoLbl = Instance.new("TextLabel")
logoLbl.Size = UDim2.new(0, 60, 1, 0) logoLbl.Position = UDim2.new(0, 16, 0, 0)
logoLbl.BackgroundTransparency = 1 logoLbl.Text = "⚡"
logoLbl.TextColor3 = C.accent logoLbl.Font = FB logoLbl.TextSize = 18
logoLbl.TextXAlignment = Enum.TextXAlignment.Left logoLbl.Parent = titleBar

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(0, 170, 1, 0) titleLbl.Position = UDim2.new(0, 50, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "PULSE HUB v"..VERSION
titleLbl.TextColor3 = C.accent titleLbl.Font = FB titleLbl.TextSize = 13
titleLbl.TextXAlignment = Enum.TextXAlignment.Left titleLbl.Parent = titleBar

-- v8.154: status indicator di title bar (samping logo) — mirror dari statsLbl listing panel
do
    local headerStatusLbl = Instance.new("TextLabel")
    headerStatusLbl.Size = UDim2.new(1, -270, 1, 0) headerStatusLbl.Position = UDim2.new(0, 224, 0, 0)
    headerStatusLbl.BackgroundTransparency = 1
    headerStatusLbl.Text = ""
    headerStatusLbl.TextColor3 = C.success headerStatusLbl.Font = Enum.Font.Code headerStatusLbl.TextSize = 11
    headerStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
    headerStatusLbl.TextTruncate = Enum.TextTruncate.AtEnd
    headerStatusLbl.Parent = titleBar
    BH.headerStatusLbl = headerStatusLbl
end

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 28) closeBtn.Position = UDim2.new(1, -42, 0.5, -14)
closeBtn.BackgroundColor3 = C.card closeBtn.AutoButtonColor = false
closeBtn.Text = "—" closeBtn.TextColor3 = C.accent
closeBtn.Font = FB closeBtn.TextSize = 18 closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Floating Z logo button (when minimized)
local zBtn = Instance.new("TextButton")
zBtn.Size = UDim2.new(0, 56, 0, 56) zBtn.Position = UDim2.new(0, 20, 0.5, -28)
zBtn.BackgroundColor3 = C.card zBtn.AutoButtonColor = false
zBtn.Text = "Z" zBtn.TextColor3 = C.accent
zBtn.Font = FB zBtn.TextSize = 28
zBtn.Active = true zBtn.Draggable = true
zBtn.Visible = false zBtn.Parent = gui
Instance.new("UICorner", zBtn).CornerRadius = UDim.new(1, 0)
local zStroke = Instance.new("UIStroke", zBtn)
zStroke.Color = C.accent zStroke.Thickness = 2
zStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
zStroke.Transparency = 0.2

closeBtn.MouseButton1Click:Connect(function()
    main.Visible = false
    zBtn.Visible = true
end)
zBtn.MouseButton1Click:Connect(function()
    main.Visible = true
    zBtn.Visible = false
end)

-- Separator
local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, -32, 0, 1) sep.Position = UDim2.new(0, 16, 0, 44)
sep.BackgroundColor3 = C.accent sep.BorderSizePixel = 0 sep.BackgroundTransparency = 0.7
sep.Parent = main

-- ============================================================
-- v8.301: TEMPLATE MANAGER (SALIN TEMPLATE) di title bar.
-- List template lokal (nama + x hapus), pilih -> popup konfirmasi ->
-- apply. Bisa simpan baru dari setting skrg + import/export kode.
-- SEMUA di do-block: NOL local chunk utama (limit-200 Luau!). ASCII only.
-- ============================================================
do
    local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local function b64enc(data)
        return ((data:gsub(".", function(x)
            local r, b = "", x:byte()
            for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
            return r
        end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
            if #x < 6 then return "" end
            local c = 0
            for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
            return B64:sub(c + 1, c + 1)
        end) .. ({ "", "==", "=" })[#data % 3 + 1])
    end
    local function b64dec(data)
        data = data:gsub("[^" .. B64 .. "=]", "")
        return (data:gsub("=", ""):gsub(".", function(x)
            local r, f = "", (B64:find(x, 1, true) - 1)
            for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0") end
            return r
        end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
            if #x ~= 8 then return "" end
            local c = 0
            for i = 1, 8 do c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0) end
            return string.char(c)
        end))
    end
    local function sanitize(v)
        if type(v) ~= "table" then
            if v == math.huge or v == -math.huge then return nil end
            return v
        end
        local out = {}
        for k, vv in pairs(v) do local cv = sanitize(vv); if cv ~= nil then out[k] = cv end end
        return out
    end

    -- ===== penyimpanan template lokal (file terpisah dari state) =====
    local TPL_FILE = "PulseMarket_templates.json"
    local templates = {}   -- array of { name=, state= }
    local function loadTemplates()
        if isfile and readfile and isfile(TPL_FILE) then
            local ok, data = pcall(function() return HttpService:JSONDecode(readfile(TPL_FILE)) end)
            if ok and type(data) == "table" then templates = data end
        end
    end
    local function saveTemplates()
        if writefile then pcall(function() writefile(TPL_FILE, HttpService:JSONEncode(templates)) end) end
    end
    loadTemplates()

    -- restore math.huge di rules setelah decode
    local function fixRules(st)
        if type(st) == "table" and type(st.listingRules) == "table" then
            for _, r in ipairs(st.listingRules) do
                if type(r) == "table" then
                    r.max = r.max or math.huge
                    r.maxListings = r.maxListings or math.huge
                    r.min = r.min or 0
                    r.price = r.price or 100
                end
            end
        end
        return st
    end

    -- apply state ke marketState aktif (tanpa ganti referensi)
    local function applyState(st)
        st = fixRules(st)
        for k in pairs(BH.marketState) do BH.marketState[k] = nil end
        for k, v in pairs(st) do BH.marketState[k] = v end
        if type(BH.marketState.listingRules) ~= "table" then BH.marketState.listingRules = {} end
        local nRules = #BH.marketState.listingRules
        -- v8.308: pakai BH.listingRules (di-expose dari tab Listing yg didefinisikan belakangan).
        local lr = BH.listingRules
        local synced = false
        if lr then
            for i = #lr, 1, -1 do lr[i] = nil end
            for i, r in ipairs(BH.marketState.listingRules) do lr[i] = r end
            BH.marketState.listingRules = lr
            synced = true
        end
        BH.saveMarketState(BH.marketState)
        -- v8.311: refresh UI + return status buat ditampilin di popup (biar keliatan tanpa console).
        local rebuiltOk = false
        if BH.rebuildRulesUI then
            rebuiltOk = pcall(BH.rebuildRulesUI)
        end
        print("[PulseMarket] applyState: "..nRules.." rule | sync="..tostring(synced).." | rebuild="..tostring(rebuiltOk))
        return nRules, synced, rebuiltOk
    end

    -- ===== tombol title bar: SALIN TEMPLATE (buka manager) =====
    local tplBtn = Instance.new("TextButton")
    tplBtn.Size = UDim2.new(0, 96, 0, 24) tplBtn.Position = UDim2.new(1, -150, 0.5, -12)
    tplBtn.BackgroundColor3 = C.card tplBtn.AutoButtonColor = false
    tplBtn.Text = "SALIN TEMPLATE" tplBtn.TextColor3 = C.text
    tplBtn.Font = FB tplBtn.TextSize = 9 tplBtn.Parent = titleBar
    Instance.new("UICorner", tplBtn).CornerRadius = UDim.new(0, 5)
    do local s = Instance.new("UIStroke", tplBtn); s.Color = C.accent; s.Thickness = 1; s.Transparency = 0.5 end

    -- ===== popup manager =====
    local pop = Instance.new("Frame")
    pop.Size = UDim2.new(0, 380, 0, 448) pop.Position = UDim2.new(0.5, -190, 0.5, -224)
    pop.BackgroundColor3 = C.bg pop.BorderSizePixel = 0 pop.Visible = false
    pop.ZIndex = 200 pop.Parent = main
    Instance.new("UICorner", pop).CornerRadius = UDim.new(0, 10)
    do local s = Instance.new("UIStroke", pop); s.Color = C.accent; s.Thickness = 1.5; s.Transparency = 0.3 end

    local popTitle = Instance.new("TextLabel")
    popTitle.Size = UDim2.new(1, -40, 0, 28) popTitle.Position = UDim2.new(0, 14, 0, 8)
    popTitle.BackgroundTransparency = 1 popTitle.Text = "SALIN TEMPLATE"
    popTitle.TextColor3 = C.accent popTitle.Font = FB popTitle.TextSize = 14
    popTitle.TextXAlignment = Enum.TextXAlignment.Left popTitle.ZIndex = 201 popTitle.Parent = pop

    local popClose = Instance.new("TextButton")
    popClose.Size = UDim2.new(0, 26, 0, 26) popClose.Position = UDim2.new(1, -32, 0, 8)
    popClose.BackgroundColor3 = C.card popClose.Text = "X" popClose.TextColor3 = C.danger
    popClose.Font = FB popClose.TextSize = 12 popClose.ZIndex = 201 popClose.Parent = pop
    Instance.new("UICorner", popClose).CornerRadius = UDim.new(0, 6)
    popClose.MouseButton1Click:Connect(function() pop.Visible = false end)

    -- list template (scroll)
    local listSF = Instance.new("ScrollingFrame")
    listSF.Size = UDim2.new(1, -28, 0, 176) listSF.Position = UDim2.new(0, 14, 0, 42)
    listSF.BackgroundColor3 = C.card listSF.BorderSizePixel = 0
    listSF.ScrollBarThickness = 4 listSF.CanvasSize = UDim2.new(0, 0, 0, 0)
    listSF.AutomaticCanvasSize = Enum.AutomaticSize.Y listSF.ZIndex = 201 listSF.Parent = pop
    Instance.new("UICorner", listSF).CornerRadius = UDim.new(0, 8)
    local listLay = Instance.new("UIListLayout")
    listLay.Padding = UDim.new(0, 4) listLay.SortOrder = Enum.SortOrder.LayoutOrder listLay.Parent = listSF
    Instance.new("UIPadding", listSF).PaddingTop = UDim.new(0, 6)

    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size = UDim2.new(1, -28, 0, 28) statusLbl.Position = UDim2.new(0, 14, 0, 414)
    statusLbl.BackgroundTransparency = 1 statusLbl.Text = ""
    statusLbl.TextColor3 = C.textDim statusLbl.Font = FM statusLbl.TextSize = 11
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left statusLbl.TextYAlignment = Enum.TextYAlignment.Top
    statusLbl.TextWrapped = true statusLbl.ZIndex = 201 statusLbl.Parent = pop
    local function setStatus(txt, col)
        statusLbl.Text = txt statusLbl.TextColor3 = col or C.textDim
    end

    -- konfirmasi mini (di dalam pop): "Anda yakin pakai template ini?"
    -- v8.303: ZIndex TINGGI (300+) + posisi nutup penuh biar tombol ga ke-block elemen lain
    -- v8.305: overlay penuh nutup popup pas konfirmasi muncul (block touch elemen lain,
    -- termasuk TextBox editable yg nangkep input walau ZIndex rendah)
    local overlay = Instance.new("TextButton")
    overlay.Size = UDim2.new(1, 0, 1, 0) overlay.Position = UDim2.new(0, 0, 0, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0) overlay.BackgroundTransparency = 0.5
    overlay.Text = "" overlay.AutoButtonColor = false overlay.BorderSizePixel = 0
    overlay.Visible = false overlay.ZIndex = 350 overlay.Active = true overlay.Parent = pop
    overlay.MouseButton1Click:Connect(function() end)  -- serap klik, jangan tembus
    Instance.new("UICorner", overlay).CornerRadius = UDim.new(0, 10)

    -- kotak konfirmasi di TENGAH overlay (bukan numpuk list)
    local confirm = overlay   -- alias biar handler lama (confirm.Visible) tetep jalan
    local confBox = Instance.new("Frame")
    confBox.Size = UDim2.new(0, 300, 0, 130) confBox.Position = UDim2.new(0.5, -150, 0.5, -65)
    confBox.BackgroundColor3 = C.bg confBox.BorderSizePixel = 0
    confBox.ZIndex = 351 confBox.Parent = overlay
    Instance.new("UICorner", confBox).CornerRadius = UDim.new(0, 10)
    do local s = Instance.new("UIStroke", confBox); s.Color = C.accent; s.Thickness = 2; s.Transparency = 0.2 end
    local confirmLbl = Instance.new("TextLabel")
    confirmLbl.Size = UDim2.new(1, -24, 0, 56) confirmLbl.Position = UDim2.new(0, 12, 0, 12)
    confirmLbl.BackgroundTransparency = 1 confirmLbl.Text = "JAMAL KAMU BENERAN SUKA SAMA AGUS?"
    confirmLbl.TextColor3 = C.text confirmLbl.Font = FM confirmLbl.TextSize = 13
    confirmLbl.TextWrapped = true confirmLbl.TextXAlignment = Enum.TextXAlignment.Left
    confirmLbl.TextYAlignment = Enum.TextYAlignment.Top
    confirmLbl.ZIndex = 352 confirmLbl.Parent = confBox
    local yesBtn = Instance.new("TextButton")
    yesBtn.Size = UDim2.new(0, 130, 0, 38) yesBtn.Position = UDim2.new(0, 12, 1, -50)
    yesBtn.BackgroundColor3 = C.accent yesBtn.Text = "YA AKU SUKA AGUS" yesBtn.TextColor3 = Color3.new(0,0,0)
    yesBtn.Font = FB yesBtn.TextSize = 10 yesBtn.TextWrapped = true yesBtn.ZIndex = 352 yesBtn.Parent = confBox
    Instance.new("UICorner", yesBtn).CornerRadius = UDim.new(0, 6)
    local noBtn = Instance.new("TextButton")
    noBtn.Size = UDim2.new(0, 130, 0, 38) noBtn.Position = UDim2.new(1, -142, 1, -50)
    noBtn.BackgroundColor3 = C.input noBtn.Text = "AKU TIDAK SUKA AGUS" noBtn.TextColor3 = C.textDim
    noBtn.Font = FB noBtn.TextSize = 10 noBtn.TextWrapped = true noBtn.ZIndex = 352 noBtn.Parent = confBox
    Instance.new("UICorner", noBtn).CornerRadius = UDim.new(0, 6)

    local pendingIdx = nil
    local rebuildList  -- fwd decl

    yesBtn.MouseButton1Click:Connect(function()
        if pendingIdx and templates[pendingIdx] then
            local t = templates[pendingIdx]
            local nRules, synced, rebuiltOk = applyState(fixRules(t.state or {}))
            BH.marketState.settingName = t.name
            BH.saveMarketState(BH.marketState)
            -- v8.311: status detail biar keliatan template kebaca/enggak tanpa buka console
            local msg = "'"..tostring(t.name).."': "..tostring(nRules or 0).." rule"
            if (nRules or 0) == 0 then
                msg = msg .. " (KOSONG! template ga ada rules)"
            elseif not synced or not rebuiltOk then
                msg = msg .. " ke-load tapi UI ga refresh - RELOAD sc"
            else
                msg = msg .. " dipakai. cek List Harga."
            end
            setStatus(msg, (nRules or 0) > 0 and C.accent or C.danger)
            confirm.Visible = false; overlay.Visible = false
            if rebuildList then rebuildList() end
        end
    end)
    noBtn.MouseButton1Click:Connect(function() confirm.Visible = false; overlay.Visible = false; pendingIdx = nil end)

    rebuildList = function()
        for _, c in ipairs(listSF:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
        end
        if #templates == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, -12, 0, 40) empty.BackgroundTransparency = 1
            empty.Text = "belum ada template. simpan setting skrg atau import kode."
            empty.TextColor3 = C.textDim empty.Font = FM empty.TextSize = 11
            empty.TextWrapped = true empty.ZIndex = 202 empty.Parent = listSF
            return
        end
        local activeName = BH.marketState.settingName
        for i, t in ipairs(templates) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -12, 0, 32) row.BackgroundColor3 = C.input
            row.BorderSizePixel = 0 row.LayoutOrder = i row.ZIndex = 202 row.Parent = listSF
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
            local isActive = (activeName and t.name == activeName)
            if isActive then
                local s = Instance.new("UIStroke", row); s.Color = C.accent; s.Thickness = 2
                row.BackgroundColor3 = C.card
            end
            -- nama (klik = pilih)
            local pick = Instance.new("TextButton")
            pick.Size = UDim2.new(1, -40, 1, 0) pick.Position = UDim2.new(0, 0, 0, 0)
            pick.BackgroundTransparency = 1 pick.Text = "  " .. tostring(t.name)
            pick.TextColor3 = isActive and C.accent or C.text
            pick.Font = isActive and FB or FM pick.TextSize = 12
            pick.TextXAlignment = Enum.TextXAlignment.Left pick.ZIndex = 203 pick.Parent = row
            pick.MouseButton1Click:Connect(function()
                pendingIdx = i
                confirmLbl.Text = "JAMAL KAMU BENERAN SUKA SAMA AGUS?"
                overlay.Visible = true; confirm.Visible = true
            end)
            -- tombol x (hapus)
            local xb = Instance.new("TextButton")
            xb.Size = UDim2.new(0, 28, 0, 24) xb.Position = UDim2.new(1, -32, 0.5, -12)
            xb.BackgroundColor3 = C.bg xb.Text = "x" xb.TextColor3 = C.danger
            xb.Font = FB xb.TextSize = 13 xb.ZIndex = 203 xb.Parent = row
            Instance.new("UICorner", xb).CornerRadius = UDim.new(0, 5)
            xb.MouseButton1Click:Connect(function()
                table.remove(templates, i)
                saveTemplates()
                rebuildList()
                setStatus("template '" .. tostring(t.name) .. "' dihapus.", C.danger)
            end)
        end
    end
    rebuildList()

    -- ===== baris bawah: nama + SIMPAN BARU + IMPORT + EXPORT =====
    local nameBox = Instance.new("TextBox")
    nameBox.Size = UDim2.new(0, 150, 0, 26) nameBox.Position = UDim2.new(0, 14, 0, 224)
    nameBox.BackgroundColor3 = C.input nameBox.TextColor3 = C.text
    nameBox.Font = FM nameBox.TextSize = 11 nameBox.PlaceholderText = "nama template baru"
    nameBox.Text = "" nameBox.ClearTextOnFocus = false nameBox.BorderSizePixel = 0
    nameBox.ZIndex = 201 nameBox.Parent = pop
    Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 6)

    local saveNewBtn = Instance.new("TextButton")
    saveNewBtn.Size = UDim2.new(0, 92, 0, 26) saveNewBtn.Position = UDim2.new(0, 170, 0, 224)
    saveNewBtn.BackgroundColor3 = C.card saveNewBtn.Text = "SIMPAN BARU" saveNewBtn.TextColor3 = C.text
    saveNewBtn.Font = FB saveNewBtn.TextSize = 10 saveNewBtn.ZIndex = 201 saveNewBtn.Parent = pop
    Instance.new("UICorner", saveNewBtn).CornerRadius = UDim.new(0, 6)
    do local s = Instance.new("UIStroke", saveNewBtn); s.Color = C.accent; s.Thickness = 1; s.Transparency = 0.5 end
    saveNewBtn.MouseButton1Click:Connect(function()
        local nm = nameBox.Text
        if not nm or nm:gsub("%s", "") == "" then setStatus("isi nama template dulu", C.danger); return end
        -- simpan snapshot marketState skrg
        table.insert(templates, { name = nm, state = sanitize(BH.marketState) })
        saveTemplates()
        BH.marketState.settingName = nm
        BH.saveMarketState(BH.marketState)
        nameBox.Text = ""
        rebuildList()
        setStatus("template '" .. nm .. "' disimpan dari setting sekarang.", C.accent)
    end)

    local expBtn = Instance.new("TextButton")
    expBtn.Size = UDim2.new(0, 88, 0, 26) expBtn.Position = UDim2.new(0, 268, 0, 224)
    expBtn.BackgroundColor3 = C.card expBtn.Text = "EXPORT AKTIF" expBtn.TextColor3 = C.text
    expBtn.Font = FB expBtn.TextSize = 9 expBtn.ZIndex = 201 expBtn.Parent = pop
    Instance.new("UICorner", expBtn).CornerRadius = UDim.new(0, 6)
    do local s = Instance.new("UIStroke", expBtn); s.Color = C.accent; s.Thickness = 1; s.Transparency = 0.5 end

    -- ===== KOTAK EXPORT (khusus nampilin kode hasil export, buat di-copy) =====
    local expLbl = Instance.new("TextLabel")
    expLbl.Size = UDim2.new(1, -28, 0, 14) expLbl.Position = UDim2.new(0, 14, 0, 258)
    expLbl.BackgroundTransparency = 1 expLbl.Text = "KODE EXPORT (copy dari sini):"
    expLbl.TextColor3 = C.textDim expLbl.Font = FM expLbl.TextSize = 10
    expLbl.TextXAlignment = Enum.TextXAlignment.Left expLbl.ZIndex = 201 expLbl.Parent = pop

    local codeBox = Instance.new("TextBox")
    codeBox.Size = UDim2.new(1, -28, 0, 44) codeBox.Position = UDim2.new(0, 14, 0, 274)
    codeBox.BackgroundColor3 = C.input codeBox.TextColor3 = C.text
    codeBox.Font = Enum.Font.Code codeBox.TextSize = 10
    codeBox.TextXAlignment = Enum.TextXAlignment.Left codeBox.TextYAlignment = Enum.TextYAlignment.Top
    codeBox.TextWrapped = true codeBox.MultiLine = true codeBox.ClearTextOnFocus = false
    codeBox.PlaceholderText = "pencet EXPORT AKTIF -> kode muncul di sini (auto-copy)"
    codeBox.Text = "" codeBox.BorderSizePixel = 0 codeBox.ZIndex = 201 codeBox.Parent = pop
    Instance.new("UICorner", codeBox).CornerRadius = UDim.new(0, 6)

    -- ===== KOTAK IMPORT (khusus paste kode dari akun lain) =====
    local impLbl = Instance.new("TextLabel")
    impLbl.Size = UDim2.new(1, -28, 0, 14) impLbl.Position = UDim2.new(0, 14, 0, 324)
    impLbl.BackgroundTransparency = 1 impLbl.Text = "PASTE KODE IMPORT di sini:"
    impLbl.TextColor3 = C.textDim impLbl.Font = FM impLbl.TextSize = 10
    impLbl.TextXAlignment = Enum.TextXAlignment.Left impLbl.ZIndex = 201 impLbl.Parent = pop

    local impBox = Instance.new("TextBox")
    impBox.Size = UDim2.new(1, -134, 0, 44) impBox.Position = UDim2.new(0, 14, 0, 340)
    impBox.BackgroundColor3 = C.input impBox.TextColor3 = C.text
    impBox.Font = Enum.Font.Code impBox.TextSize = 10
    impBox.TextXAlignment = Enum.TextXAlignment.Left impBox.TextYAlignment = Enum.TextYAlignment.Top
    impBox.TextWrapped = true impBox.MultiLine = true impBox.ClearTextOnFocus = false
    impBox.PlaceholderText = "paste kode dari akun lain..."
    impBox.Text = "" impBox.BorderSizePixel = 0 impBox.ZIndex = 201 impBox.Parent = pop
    Instance.new("UICorner", impBox).CornerRadius = UDim.new(0, 6)

    local impCodeBtn = Instance.new("TextButton")
    impCodeBtn.Size = UDim2.new(0, 110, 0, 44) impCodeBtn.Position = UDim2.new(1, -124, 0, 340)
    impCodeBtn.BackgroundColor3 = C.card impCodeBtn.Text = "IMPORT KODE" impCodeBtn.TextColor3 = C.accent
    impCodeBtn.Font = FB impCodeBtn.TextSize = 10 impCodeBtn.ZIndex = 202 impCodeBtn.Parent = pop
    Instance.new("UICorner", impCodeBtn).CornerRadius = UDim.new(0, 6)
    do local s = Instance.new("UIStroke", impCodeBtn); s.Color = C.accent; s.Thickness = 1; s.Transparency = 0.5 end

    -- EXPORT AKTIF: v8.312 - export RINGKAS. cuma listingRules (yg dibutuh pindah
    -- antar-akun), format kompak array (bukan JSON verbose) -> kode jauh lebih PENDEK,
    -- ga gampang kepotong pas transfer antar-HP.
    expBtn.MouseButton1Click:Connect(function()
        local nm = BH.marketState.settingName or "tanpa-nama"
        local rules = BH.marketState.listingRules or {}
        -- format kompak: tiap rule jadi 1 baris "type|min|max|price|maxListings|eggSource"
        -- pisah antar-rule pakai ";". jauh lebih pendek dari JSON.
        local parts = {}
        for _, r in ipairs(rules) do
            local mx = r.max
            if mx == math.huge then mx = "" end
            local ml = r.maxListings
            if ml == math.huge then ml = "" end
            parts[#parts+1] = table.concat({
                tostring(r.type or ""), tostring(r.min or ""), tostring(mx or ""),
                tostring(r.price or ""), tostring(ml or ""), tostring(r.eggSource or "")
            }, "|")
        end
        local raw = "R1:" .. nm .. "~" .. table.concat(parts, ";")
        local code = "PULSE3:" .. b64enc(raw)
        codeBox.Text = code
        local copied = false
        if setclipboard then copied = pcall(function() setclipboard(code) end)
        elseif toclipboard then copied = pcall(function() toclipboard(code) end) end
        setStatus("export '" .. nm .. "' (" .. #rules .. " rule, " .. #code .. " char)" .. (copied and " ke-copy!" or " (copy manual dari kotak)"), C.accent)
    end)

    -- IMPORT KODE: paste (dari impBox) -> decode -> simpan sbg template baru di list
    impCodeBtn.MouseButton1Click:Connect(function()
        local code = impBox.Text
        if not code or code:gsub("%s","") == "" then setStatus("paste kode dulu di kotak import", C.danger); return end
        code = code:gsub("%s", "")
        local ver = code:sub(1, 6)
        -- v8.312: format PULSE3 (ringkas). decode -> parse "R1:nama~type|min|max|price|ml|egg;..."
        if ver == "PULSE3:" then
            local raw = nil
            local okd = pcall(function() raw = b64dec(code:sub(7)) end)
            if not okd or not raw or not raw:find("^R1:") then setStatus("kode PULSE3 invalid", C.danger); return end
            raw = raw:sub(4)   -- buang "R1:"
            local nm, body = raw:match("^(.-)~(.*)$")
            if not nm then nm = "import"; body = raw end
            local rules = {}
            for chunk in tostring(body):gmatch("[^;]+") do
                local f = {}
                for v in (chunk .. "|"):gmatch("(.-)|") do f[#f+1] = v end
                if #f >= 4 then
                    local mx = tonumber(f[3]); if not mx or f[3] == "" then mx = math.huge end
                    local ml = tonumber(f[5]); if not ml or f[5] == "" then ml = math.huge end
                    rules[#rules+1] = {
                        type = (f[1] ~= "" and f[1]) or nil,
                        min = tonumber(f[2]) or 0,
                        max = mx,
                        price = tonumber(f[4]) or 0,
                        maxListings = ml,
                        eggSource = (f[6] and f[6] ~= "" and f[6]) or nil,
                    }
                end
            end
            if #rules == 0 then setStatus("kode PULSE3: 0 rule (kosong?)", C.danger); return end
            table.insert(templates, { name = nm, state = sanitize({ listingRules = rules }) })
            saveTemplates()
            impBox.Text = ""
            rebuildList()
            setStatus("import '" .. tostring(nm) .. "' (" .. #rules .. " rule). pilih di list buat pakai.", C.accent)
            return
        end
        -- format lama PULSE2/PULSE1 (JSON)
        if ver == "PULSE2:" or ver == "PULSE1:" then code = code:sub(7) end
        local ok, json = pcall(function() return b64dec(code) end)
        if not ok or not json or json == "" then setStatus("kode invalid (decode gagal)", C.danger); return end
        local ok2, data = pcall(function() return HttpService:JSONDecode(json) end)
        if not ok2 or type(data) ~= "table" then setStatus("kode invalid", C.danger); return end
        local st = nil
        if data.marketState and type(data.marketState) == "table" then st = data.marketState
        elseif data.listingRules then st = { listingRules = data.listingRules, settings = data.settings or {} } end
        if not st then setStatus("kode invalid (ga ada data)", C.danger); return end
        local nm = data.name or ("import-" .. (#templates + 1))
        table.insert(templates, { name = nm, state = sanitize(st) })
        saveTemplates()
        impBox.Text = ""
        rebuildList()
        setStatus("kode di-import jadi template '" .. tostring(nm) .. "'. pilih di list buat pakai.", C.accent)
    end)

    tplBtn.MouseButton1Click:Connect(function()
        pop.Visible = not pop.Visible
        if pop.Visible then confirm.Visible = false; overlay.Visible = false; rebuildList() end
    end)
end


-- ===== SIDEBAR =====
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 130, 1, -60) sidebar.Position = UDim2.new(0, 10, 0, 52)
sidebar.BackgroundTransparency = 1 sidebar.Parent = main
local sbLayout = Instance.new("UIListLayout")
sbLayout.Padding = UDim.new(0, 5) sbLayout.Parent = sidebar

-- ===== CONTENT AREA =====
local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -156, 1, -60) contentArea.Position = UDim2.new(0, 146, 0, 52)
contentArea.BackgroundTransparency = 1 contentArea.Parent = main

-- ===== SIDEBAR BUTTONS =====
local sbBtns = {}
local panels = {}
local activeTab = "MARKET"

local function makeSbBtn(name, comingSoon)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 34) b.AutoButtonColor = false
    b.BackgroundColor3 = C.card b.BorderSizePixel = 0
    b.Text = "" b.Parent = sidebar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", b)
    stroke.Color = C.accent
    stroke.Thickness = 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Transparency = 0.3

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -16, 1, 0) lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1 lbl.Text = name
    lbl.TextColor3 = C.textDim lbl.Font = FB lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left lbl.Parent = b

    if comingSoon then
        local badge = Instance.new("TextLabel")
        badge.Size = UDim2.new(0, 50, 0, 16) badge.Position = UDim2.new(1, -58, 0.5, -8)
        badge.BackgroundColor3 = C.accent badge.BorderSizePixel = 0
        badge.Text = "soon" badge.TextColor3 = Color3.fromRGB(40, 30, 0)
        badge.Font = FB badge.TextSize = 10 badge.Parent = b
        Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)
    end

    sbBtns[name] = {btn=b, stroke=stroke, lbl=lbl}
    b.MouseButton1Click:Connect(function()
        activeTab = name
        for n, data in pairs(sbBtns) do
            if n == name then
                data.stroke.Thickness = 1.5
                data.lbl.TextColor3 = C.accent
            else
                data.stroke.Thickness = 0
                data.lbl.TextColor3 = C.textDim
            end
        end
        for n, p in pairs(panels) do p.Visible = (n == name) end
    end)
    return b
end

makeSbBtn("MARKET")
makeSbBtn("SHOP")
makeSbBtn("LIST HARGA")
makeSbBtn("SNIPE")
makeSbBtn("HOP SERVER")
makeSbBtn("HISTORY SELL")
makeSbBtn("GARDEN")

-- ===== PANELS =====
local function makePanel(name)
    local p = Instance.new("Frame")
    p.Size = UDim2.new(1, 0, 1, 0) p.BackgroundTransparency = 1
    p.Visible = (name == "MARKET") p.Parent = contentArea
    panels[name] = p
    return p
end
local marketPanel = makePanel("MARKET")
makePanel("SHOP")  -- v8.274: JANGAN pakai local (tembus limit 200 local Luau). akses via panels["SHOP"]
local pricePanel = makePanel("LIST HARGA")
local snipePanel = makePanel("SNIPE")
local hopServerPanel = makePanel("HOP SERVER")
makePanel("HISTORY SELL")  -- v8.156: store via panels table
local gardenPanel = makePanel("GARDEN")
BH.gardenPanel = gardenPanel  -- store for cross-scope access

-- v8.49: detect garden server (no TradeWorld = garden)
local isGardenServer = (Workspace:FindFirstChild("TradeWorld") == nil)
BH.isGardenServer = isGardenServer  -- v8.237: simpen ke BH biar loop auto-rejoin bisa akses
if isGardenServer then
    -- Hide MARKET/LIST HARGA/SNIPE/HOP SERVER/HISTORY tabs, show GARDEN by default
    sbBtns.MARKET.btn.Visible = false
    sbBtns["LIST HARGA"].btn.Visible = false
    sbBtns.SNIPE.btn.Visible = false
    sbBtns["HOP SERVER"].btn.Visible = false
    sbBtns["HISTORY SELL"].btn.Visible = false
    marketPanel.Visible = false
    gardenPanel.Visible = true
    -- override default tab visual ke GARDEN
    task.spawn(function()
        task.wait(0.1)
        for n, d in pairs(sbBtns) do
            if n == "GARDEN" then
                d.stroke.Thickness = 1.5
                d.lbl.TextColor3 = C.accent
            else
                d.stroke.Thickness = 0
                d.lbl.TextColor3 = C.textDim
            end
        end
    end)
else
    -- v8.86: di server market, sembunyiin tab GARDEN (cuma muncul di server garden)
    sbBtns.GARDEN.btn.Visible = false
end

-- Activate Market default
task.spawn(function()
    task.wait(0.05)
    sbBtns.MARKET.stroke.Thickness = 1.5
    sbBtns.MARKET.lbl.TextColor3 = C.accent
end)

-- ===== SUB-TABS (Market) =====
local subTabBar = Instance.new("Frame")
subTabBar.Size = UDim2.new(1, 0, 0, 34) subTabBar.BackgroundTransparency = 1
subTabBar.Parent = marketPanel
local subTabLayout = Instance.new("UIListLayout") subTabLayout.FillDirection = Enum.FillDirection.Horizontal
subTabLayout.Padding = UDim.new(0, 5) subTabLayout.Parent = subTabBar

local subPanels = {}
local subBtns = {}
local function makeSubPanel(name)
    local sp = Instance.new("Frame")
    sp.Size = UDim2.new(1, 0, 1, -42) sp.Position = UDim2.new(0, 0, 0, 42)
    sp.BackgroundColor3 = C.panel sp.BorderSizePixel = 0
    sp.Visible = false sp.Parent = marketPanel
    Instance.new("UICorner", sp).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", sp) stroke.Color = C.accent stroke.Thickness = 1 stroke.Transparency = 0.7
    subPanels[name] = sp
    return sp
end

local function makeSubBtn(name)
    local b = Instance.new("TextButton")
    -- v8.49: scale-fit (4 tab muat any width)
    b.Size = UDim2.new(0.245, -6, 1, 0) b.AutoButtonColor = false
    b.BackgroundColor3 = C.card b.BorderSizePixel = 0
    b.Text = "" b.Parent = subTabBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", b)
    stroke.Color = C.accent
    stroke.Thickness = 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Transparency = 0.3

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0) lbl.BackgroundTransparency = 1
    lbl.Text = name lbl.TextColor3 = C.textDim
    lbl.Font = FB lbl.TextSize = 12
    lbl.TextStrokeTransparency = 1 lbl.Parent = b

    subBtns[name] = {btn=b, stroke=stroke, lbl=lbl}
    b.MouseButton1Click:Connect(function()
        for n, data in pairs(subBtns) do
            if n == name then
                data.btn.BackgroundColor3 = C.card
                data.stroke.Thickness = 1.5
                data.lbl.TextColor3 = C.accent
            else
                data.btn.BackgroundColor3 = C.card
                data.stroke.Thickness = 0
                data.lbl.TextColor3 = C.textDim
            end
        end
        for n, sp in pairs(subPanels) do sp.Visible = (n == name) end
    end)
    return b
end

makeSubBtn("Listing")
makeSubBtn("Rejoin")
makeSubBtn("Misc")
makeSubBtn("Pantau")
local listingPanel = makeSubPanel("Listing")
local rejoinPanel = makeSubPanel("Rejoin")
local miscPanel = makeSubPanel("Misc")
local pantauPanel = makeSubPanel("Pantau")

-- v8.49: listingPanel scrollable (biar content gak ke-cut di small frame)
do
    local outer = listingPanel
    outer.Visible = true  -- listing default tab, set outer visible
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = C.accent
    scroll.CanvasSize = UDim2.new(0, 0, 0, 340)
    scroll.Parent = outer
    listingPanel = scroll
end

-- v8.48: miscPanel scrollable biar content gak ke-cut
do
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = C.accent
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = miscPanel
    miscPanel = scroll  -- redirect cards ke scrollable area
end

listingPanel.Visible = true
subBtns.Listing.stroke.Thickness = 1.5
subBtns.Listing.lbl.TextColor3 = C.accent

-- ===== HELPERS =====
local function lblOf(parent, text, x, y, w, h, color, size, font)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0, w, 0, h or 22) l.Position = UDim2.new(0, x, 0, y)
    l.BackgroundTransparency = 1 l.Text = text
    l.TextColor3 = color or C.text
    l.Font = font or FM l.TextSize = size or 12
    l.TextXAlignment = Enum.TextXAlignment.Left l.Parent = parent
    return l
end
local function boxOf(parent, x, y, w, h, default)
    local b = Instance.new("TextBox")
    b.Size = UDim2.new(0, w, 0, h or 32) b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = C.input b.BorderSizePixel = 0
    b.Text = default or "" b.TextColor3 = C.text
    b.PlaceholderColor3 = C.textDim
    b.Font = F b.TextSize = 14 b.ClearTextOnFocus = false b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local pad = Instance.new("UIPadding") pad.PaddingLeft = UDim.new(0, 10) pad.Parent = b
    return b
end
local function btnOf(parent, x, y, w, h, text, color, textColor)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, h) b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color or C.accent b.AutoButtonColor = false
    b.Text = text b.TextColor3 = textColor or Color3.fromRGB(20, 20, 20)
    b.Font = FB b.TextSize = 13 b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

-- ============================================================
-- LISTING PANEL
-- ============================================================
local listPad = Instance.new("UIPadding") listPad.PaddingTop = UDim.new(0, 14)
listPad.PaddingLeft = UDim.new(0, 14) listPad.PaddingRight = UDim.new(0, 14) listPad.PaddingBottom = UDim.new(0, 14)
listPad.Parent = listingPanel

-- Stats card — v8.154: HIDE (status mirror ke title bar)
local statsCard = Instance.new("Frame")
statsCard.Size = UDim2.new(1, 0, 0, 0) statsCard.BackgroundColor3 = C.card statsCard.BorderSizePixel = 0
statsCard.Visible = false
statsCard.Parent = listingPanel
Instance.new("UICorner", statsCard).CornerRadius = UDim.new(0, 8)
local statsLbl = Instance.new("TextLabel")
statsLbl.Size = UDim2.new(1, -20, 1, -8) statsLbl.Position = UDim2.new(0, 12, 0, 4)
statsLbl.BackgroundTransparency = 1 statsLbl.Text = "Ready — tambah rules lalu klik START"
statsLbl.TextColor3 = C.success statsLbl.Font = Enum.Font.Code statsLbl.TextSize = 14
statsLbl.TextXAlignment = Enum.TextXAlignment.Left statsLbl.TextYAlignment = Enum.TextYAlignment.Top
statsLbl.TextWrapped = true statsLbl.Parent = statsCard

-- v8.154: mirror statsLbl ke headerStatusLbl di title bar
statsLbl:GetPropertyChangedSignal("Text"):Connect(function()
    if BH.headerStatusLbl then BH.headerStatusLbl.Text = statsLbl.Text end
end)
statsLbl:GetPropertyChangedSignal("TextColor3"):Connect(function()
    if BH.headerStatusLbl then BH.headerStatusLbl.TextColor3 = statsLbl.TextColor3 end
end)
if BH.headerStatusLbl then
    BH.headerStatusLbl.Text = statsLbl.Text
    BH.headerStatusLbl.TextColor3 = statsLbl.TextColor3
end

-- Rules list (added pet+kg+price combos) — v8.154: extend up (was y=68, sekarang y=0)
local rulesScroll = Instance.new("ScrollingFrame")
rulesScroll.Size = UDim2.new(1, 0, 0, 158) rulesScroll.Position = UDim2.new(0, 0, 0, 0)
rulesScroll.BackgroundColor3 = C.card rulesScroll.BorderSizePixel = 0
rulesScroll.ScrollBarThickness = 4 rulesScroll.Parent = listingPanel
Instance.new("UICorner", rulesScroll).CornerRadius = UDim.new(0, 8)
local rulesLayout = Instance.new("UIListLayout")
rulesLayout.Padding = UDim.new(0, 4) rulesLayout.Parent = rulesScroll
local rulesPad = Instance.new("UIPadding")
rulesPad.PaddingTop = UDim.new(0, 6) rulesPad.PaddingLeft = UDim.new(0, 8) rulesPad.PaddingRight = UDim.new(0, 8)
rulesPad.Parent = rulesScroll

local rulesEmptyLbl = Instance.new("TextLabel")
rulesEmptyLbl.Size = UDim2.new(1, 0, 1, 0) rulesEmptyLbl.BackgroundTransparency = 1
rulesEmptyLbl.Text = "Rules kosong — tambah rule di bawah, atau START tanpa rule = list semua pet"
rulesEmptyLbl.TextColor3 = C.textDim rulesEmptyLbl.Font = FM rulesEmptyLbl.TextSize = 12
rulesEmptyLbl.TextWrapped = true rulesEmptyLbl.Parent = rulesScroll

-- Pet Type Dropdown
lblOf(listingPanel, "SELECT PET TYPE", 0, 168, 200, 18, C.accent, 13, FB)
local typeDrop = Instance.new("TextButton")
typeDrop.Size = UDim2.new(1, 0, 0, 36) typeDrop.Position = UDim2.new(0, 0, 0, 188)
typeDrop.BackgroundColor3 = C.input typeDrop.AutoButtonColor = false
typeDrop.BorderSizePixel = 0 typeDrop.Text = ""
typeDrop.Parent = listingPanel
Instance.new("UICorner", typeDrop).CornerRadius = UDim.new(0, 6)
local typeDropStroke = Instance.new("UIStroke", typeDrop)
typeDropStroke.Color = C.accent typeDropStroke.Thickness = 1
typeDropStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
typeDropStroke.Transparency = 0.5
local typeDropLbl = Instance.new("TextLabel")
typeDropLbl.Size = UDim2.new(1, -50, 1, 0) typeDropLbl.Position = UDim2.new(0, 12, 0, 0)
typeDropLbl.BackgroundTransparency = 1 typeDropLbl.Text = "Pilih Pet Type..."
typeDropLbl.TextColor3 = C.text typeDropLbl.Font = FM typeDropLbl.TextSize = 15
typeDropLbl.TextXAlignment = Enum.TextXAlignment.Left typeDropLbl.Parent = typeDrop
local typeDropArrow = Instance.new("TextLabel")
typeDropArrow.Size = UDim2.new(0, 30, 1, 0) typeDropArrow.Position = UDim2.new(1, -36, 0, 0)
typeDropArrow.BackgroundTransparency = 1 typeDropArrow.Text = "▼"
typeDropArrow.TextColor3 = C.accent typeDropArrow.Font = FB typeDropArrow.TextSize = 13
typeDropArrow.Parent = typeDrop

-- v8.49: 1-row compact (5 item scale-fit) — MIN KG | MAX KG | PRICE | MAX LIST | + ADD
lblOf(listingPanel, "MIN KG", 0, 230, 70, 14, C.textDim, 10, FB)
local minKgBox = Instance.new("TextBox")
minKgBox.Size = UDim2.new(0.18, -3, 0, 30) minKgBox.Position = UDim2.new(0, 0, 0, 248)
minKgBox.BackgroundColor3 = C.input minKgBox.BorderSizePixel = 0
minKgBox.Text = "" minKgBox.TextColor3 = C.text
minKgBox.PlaceholderText = "0" minKgBox.PlaceholderColor3 = C.textDim
minKgBox.Font = F minKgBox.TextSize = 12
minKgBox.ClearTextOnFocus = false minKgBox.Parent = listingPanel
Instance.new("UICorner", minKgBox).CornerRadius = UDim.new(0, 5)

lblOf(listingPanel, "MAX KG", 0, 230, 70, 14, C.textDim, 10, FB).Position = UDim2.new(0.19, 0, 0, 230)
local maxKgBox = Instance.new("TextBox")
maxKgBox.Size = UDim2.new(0.18, -3, 0, 30) maxKgBox.Position = UDim2.new(0.19, 0, 0, 248)
maxKgBox.BackgroundColor3 = C.input maxKgBox.BorderSizePixel = 0
maxKgBox.Text = "" maxKgBox.TextColor3 = C.text
maxKgBox.PlaceholderText = "∞" maxKgBox.PlaceholderColor3 = C.textDim
maxKgBox.Font = F maxKgBox.TextSize = 12
maxKgBox.ClearTextOnFocus = false maxKgBox.Parent = listingPanel
Instance.new("UICorner", maxKgBox).CornerRadius = UDim.new(0, 5)

lblOf(listingPanel, "PRICE", 0, 230, 70, 14, C.textDim, 10, FB).Position = UDim2.new(0.38, 0, 0, 230)
local priceBox = Instance.new("TextBox")
priceBox.Size = UDim2.new(0.18, -3, 0, 30) priceBox.Position = UDim2.new(0.38, 0, 0, 248)
priceBox.BackgroundColor3 = C.input priceBox.BorderSizePixel = 0
priceBox.Text = "" priceBox.TextColor3 = C.text
priceBox.PlaceholderText = "100" priceBox.PlaceholderColor3 = C.textDim
priceBox.Font = F priceBox.TextSize = 12
priceBox.ClearTextOnFocus = false priceBox.Parent = listingPanel
Instance.new("UICorner", priceBox).CornerRadius = UDim.new(0, 5)

lblOf(listingPanel, "MAX LIST", 0, 230, 70, 14, C.textDim, 10, FB).Position = UDim2.new(0.57, 0, 0, 230)
local maxListBox = Instance.new("TextBox")
maxListBox.Size = UDim2.new(0.18, -3, 0, 30) maxListBox.Position = UDim2.new(0.57, 0, 0, 248)
maxListBox.BackgroundColor3 = C.input maxListBox.BorderSizePixel = 0
maxListBox.Text = "" maxListBox.TextColor3 = C.text
maxListBox.PlaceholderText = "∞" maxListBox.PlaceholderColor3 = C.textDim
maxListBox.Font = F maxListBox.TextSize = 12
maxListBox.ClearTextOnFocus = false maxListBox.Parent = listingPanel
Instance.new("UICorner", maxListBox).CornerRadius = UDim.new(0, 5)

local addRuleBtn = Instance.new("TextButton")
addRuleBtn.Size = UDim2.new(0.24, -3, 0, 30) addRuleBtn.Position = UDim2.new(0.76, 0, 0, 248)
addRuleBtn.BackgroundColor3 = C.accent addRuleBtn.AutoButtonColor = true
addRuleBtn.Text = "+ ADD" addRuleBtn.TextColor3 = Color3.new(0, 0, 0)
addRuleBtn.Font = FB addRuleBtn.TextSize = 12
addRuleBtn.BorderSizePixel = 0 addRuleBtn.Parent = listingPanel
Instance.new("UICorner", addRuleBtn).CornerRadius = UDim.new(0, 6)

-- v8.49: DELAY/RETRY hidden (default 2 & 2, akses via getters)
local delayBox = Instance.new("TextBox")
delayBox.Visible = false delayBox.Text = "2" delayBox.Parent = listingPanel
local retryBox = Instance.new("TextBox")
retryBox.Visible = false retryBox.Text = "2" retryBox.Parent = listingPanel

-- START full width
local startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.new(1, 0, 0, 36) startBtn.Position = UDim2.new(0, 0, 0, 290)
startBtn.BackgroundColor3 = C.card startBtn.AutoButtonColor = false
startBtn.Text = "⚡ START" startBtn.TextColor3 = C.textDim
startBtn.Font = FB startBtn.TextSize = 15 startBtn.Parent = listingPanel
Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0, 8)
BH.startStroke = Instance.new("UIStroke", startBtn)
BH.startStroke.Color = C.accent BH.startStroke.Thickness = 1.5
BH.startStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border BH.startStroke.Transparency = 0.4

-- UNLIST ALL button (hidden, kept for compat)
local unlistAllListingBtn = Instance.new("TextButton")
unlistAllListingBtn.Size = UDim2.new(0, 1, 0, 1)
unlistAllListingBtn.Position = UDim2.new(0, 0, 0, 0)
unlistAllListingBtn.BackgroundColor3 = C.card unlistAllListingBtn.AutoButtonColor = false
unlistAllListingBtn.Text = "📋 UNLIST ALL" unlistAllListingBtn.TextColor3 = C.danger
unlistAllListingBtn.Font = FB unlistAllListingBtn.TextSize = 14
unlistAllListingBtn.Visible = false
unlistAllListingBtn.Parent = listingPanel
Instance.new("UICorner", unlistAllListingBtn).CornerRadius = UDim.new(0, 8)
do
    local s = Instance.new("UIStroke", unlistAllListingBtn)
    s.Color = C.danger s.Thickness = 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border s.Transparency = 0.4
end

-- Dummy stopBtn variable so handler bindings below don't crash (we wire StartBtn to do both)
local stopBtn = startBtn



-- ============================================================
-- LIST HARGA (Mirror of rules with editable price) PANEL
-- ============================================================
local plPad = Instance.new("UIPadding")
plPad.PaddingTop = UDim.new(0, 14) plPad.PaddingLeft = UDim.new(0, 14)
plPad.PaddingRight = UDim.new(0, 14) plPad.PaddingBottom = UDim.new(0, 14)
plPad.Parent = pricePanel

-- v8.72: hide header biar tab rules lebar
local lhTitleLbl = lblOf(pricePanel, "💰  LIST HARGA (Rules)", 0, 0, 400, 28, C.accent, 18, FB)
local lhDescLbl = lblOf(pricePanel, "Sama kayak rules di Listing — bisa tambah & edit harga di sini.", 0, 32, 700, 20, C.textDim, 13)
lhTitleLbl.Visible = false
lhDescLbl.Visible = false

-- ===== BACKPACK STATS CARD =====
-- Forward declare labels (used by refreshBackpackStats later)
local lhPetCount, lhFavCount, lhCapacity
do
    -- v8.74: stats card compact — 40% kiri (search ambil 60% kanan)
    local statsCardLH = Instance.new("Frame")
    statsCardLH.Size = UDim2.new(0.4, -4, 0, 24) statsCardLH.Position = UDim2.new(0, 0, 0, 0)
    statsCardLH.BackgroundTransparency = 1
    statsCardLH.Parent = pricePanel

    lhPetCount = Instance.new("TextLabel")
    lhPetCount.Size = UDim2.new(1, 0, 1, 0) lhPetCount.Position = UDim2.new(0, 0, 0, 0)
    lhPetCount.BackgroundTransparency = 1
    lhPetCount.Text = "0 pet"
    lhPetCount.TextColor3 = C.textDim lhPetCount.Font = FM lhPetCount.TextSize = 11
    lhPetCount.TextXAlignment = Enum.TextXAlignment.Left
    lhPetCount.TextYAlignment = Enum.TextYAlignment.Center
    lhPetCount.RichText = true lhPetCount.Parent = statsCardLH

    -- v8.72: kept for backward compat, hidden
    lhFavCount = Instance.new("TextLabel")
    lhFavCount.Visible = false lhFavCount.Parent = statsCardLH
    lhCapacity = Instance.new("TextLabel")
    lhCapacity.Visible = false lhCapacity.Parent = statsCardLH
end

-- v8.73: priceScroll fill all space (search removed, header hidden, FAV/CAPACITY hidden)
local priceScroll = Instance.new("ScrollingFrame")
priceScroll.Size = UDim2.new(1, 0, 1, -32) priceScroll.Position = UDim2.new(0, 0, 0, 28)
priceScroll.BackgroundColor3 = C.card priceScroll.BorderSizePixel = 0
priceScroll.ScrollBarThickness = 4 priceScroll.Parent = pricePanel
Instance.new("UICorner", priceScroll).CornerRadius = UDim.new(0, 8)
local priceLayout = Instance.new("UIListLayout") priceLayout.Padding = UDim.new(0, 4) priceLayout.Parent = priceScroll
local pricePadInner = Instance.new("UIPadding")
pricePadInner.PaddingTop = UDim.new(0, 6) pricePadInner.PaddingLeft = UDim.new(0, 6) pricePadInner.PaddingRight = UDim.new(0, 6)
pricePadInner.PaddingBottom = UDim.new(0, 6) pricePadInner.Parent = priceScroll

-- Add rule form (mirror of Listing tab)
lblOf(pricePanel, "SELECT PET TYPE", 0, 344, 200, 18, C.accent, 13, FB)
local lhTypeDrop = Instance.new("TextButton")
lhTypeDrop.Size = UDim2.new(1, 0, 0, 36) lhTypeDrop.Position = UDim2.new(0, 0, 0, 364)
lhTypeDrop.BackgroundColor3 = C.input lhTypeDrop.AutoButtonColor = false
lhTypeDrop.BorderSizePixel = 0 lhTypeDrop.Text = "" lhTypeDrop.Parent = pricePanel
Instance.new("UICorner", lhTypeDrop).CornerRadius = UDim.new(0, 6)
local lhTypeDropStroke = Instance.new("UIStroke", lhTypeDrop)
lhTypeDropStroke.Color = C.accent lhTypeDropStroke.Thickness = 1
lhTypeDropStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
lhTypeDropStroke.Transparency = 0.5
local lhTypeDropLbl = Instance.new("TextLabel")
lhTypeDropLbl.Size = UDim2.new(1, -50, 1, 0) lhTypeDropLbl.Position = UDim2.new(0, 12, 0, 0)
lhTypeDropLbl.BackgroundTransparency = 1 lhTypeDropLbl.Text = "Pilih Pet Type..."
lhTypeDropLbl.TextColor3 = C.text lhTypeDropLbl.Font = FM lhTypeDropLbl.TextSize = 15
lhTypeDropLbl.TextXAlignment = Enum.TextXAlignment.Left lhTypeDropLbl.Parent = lhTypeDrop
local lhTypeDropArrow = Instance.new("TextLabel")
lhTypeDropArrow.Size = UDim2.new(0, 30, 1, 0) lhTypeDropArrow.Position = UDim2.new(1, -36, 0, 0)
lhTypeDropArrow.BackgroundTransparency = 1 lhTypeDropArrow.Text = "▼"
lhTypeDropArrow.TextColor3 = C.accent lhTypeDropArrow.Font = FB lhTypeDropArrow.TextSize = 13
lhTypeDropArrow.Parent = lhTypeDrop

lblOf(pricePanel, "MIN KG", 0, 410, 70, 18, C.textDim, 12, FB)
local lhMinKgBox = boxOf(pricePanel, 0, 430, 90, 34, "")
lhMinKgBox.PlaceholderText = "0"
lhMinKgBox.TextSize = 14
lblOf(pricePanel, "MAX KG", 100, 410, 70, 18, C.textDim, 12, FB)
local lhMaxKgBox = boxOf(pricePanel, 100, 430, 90, 34, "")
lhMaxKgBox.PlaceholderText = "∞"
lhMaxKgBox.TextSize = 14
lblOf(pricePanel, "PRICE", 200, 410, 70, 18, C.textDim, 12, FB)
local lhPriceBox = boxOf(pricePanel, 200, 430, 90, 34, "")
lhPriceBox.PlaceholderText = "100"
lhPriceBox.TextSize = 14
lblOf(pricePanel, "MAX LIST", 300, 410, 80, 18, C.textDim, 12, FB)
local lhMaxListBox = boxOf(pricePanel, 300, 430, 90, 34, "")
lhMaxListBox.PlaceholderText = "∞"
lhMaxListBox.TextSize = 14
local lhAddBtn = btnOf(pricePanel, 400, 430, 110, 34, "+ ADD", C.accent)
lhAddBtn.TextSize = 14

-- v8.47: hide rule-add form (add rules dari tab Listing aja)
do
    lhTypeDrop.Visible = false
    lhMinKgBox.Visible = false
    lhMaxKgBox.Visible = false
    lhPriceBox.Visible = false
    lhMaxListBox.Visible = false
    lhAddBtn.Visible = false
    for _, c in ipairs(pricePanel:GetChildren()) do
        if c:IsA("TextLabel") then
            local t = c.Text
            if t == "SELECT PET TYPE" or t == "MIN KG" or t == "MAX KG"
               or t == "PRICE" or t == "MAX LIST" then
                c.Visible = false
            end
        end
    end
end

-- v8.74: small search box di kanan (40% stats kiri | 60% search kanan)
local priceSearchText = ""
do
    local lhSearchBox = Instance.new("TextBox")
    lhSearchBox.Size = UDim2.new(0.6, -4, 0, 22)
    lhSearchBox.Position = UDim2.new(0.4, 4, 0, 1)
    lhSearchBox.BackgroundColor3 = C.input
    lhSearchBox.BorderSizePixel = 0
    lhSearchBox.Text = ""
    lhSearchBox.TextColor3 = C.text
    lhSearchBox.PlaceholderText = "🔍 cari rule..."
    lhSearchBox.PlaceholderColor3 = C.textDim
    lhSearchBox.Font = F
    lhSearchBox.TextSize = 11
    lhSearchBox.TextXAlignment = Enum.TextXAlignment.Left
    lhSearchBox.ClearTextOnFocus = false
    lhSearchBox.Parent = pricePanel
    Instance.new("UICorner", lhSearchBox).CornerRadius = UDim.new(0, 5)
    local lhSearchPad = Instance.new("UIPadding")
    lhSearchPad.PaddingLeft = UDim.new(0, 8)
    lhSearchPad.Parent = lhSearchBox

    lhSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        priceSearchText = lhSearchBox.Text or ""
        rebuildRulesUI()
    end)
end

-- ============================================================
-- PET TYPE MODAL (popup overlay)
-- ============================================================
local modalOverlay = Instance.new("Frame")
modalOverlay.Size = UDim2.new(1, 0, 1, 0) modalOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
modalOverlay.BackgroundTransparency = 0.5 modalOverlay.BorderSizePixel = 0
modalOverlay.Visible = false modalOverlay.ZIndex = 10 modalOverlay.Parent = main

local modal = Instance.new("Frame")
modal.Size = UDim2.new(0, 360, 0, 420) modal.Position = UDim2.new(0.5, -180, 0.5, -210)
modal.BackgroundColor3 = C.panel modal.BorderSizePixel = 0
modal.ZIndex = 11 modal.Parent = modalOverlay
Instance.new("UICorner", modal).CornerRadius = UDim.new(0, 10)
local modalStroke = Instance.new("UIStroke", modal)
modalStroke.Color = C.accent modalStroke.Thickness = 1.5
modalStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
modalStroke.Transparency = 0.3

local modalTitle = Instance.new("TextLabel")
modalTitle.Size = UDim2.new(1, -50, 0, 40) modalTitle.Position = UDim2.new(0, 16, 0, 8)
modalTitle.BackgroundTransparency = 1 modalTitle.Text = "Select Pet Type"
modalTitle.TextColor3 = C.accent modalTitle.Font = FB modalTitle.TextSize = 16
modalTitle.TextXAlignment = Enum.TextXAlignment.Left modalTitle.ZIndex = 11 modalTitle.Parent = modal

local modalClose = Instance.new("TextButton")
modalClose.Size = UDim2.new(0, 28, 0, 28) modalClose.Position = UDim2.new(1, -36, 0, 14)
modalClose.BackgroundColor3 = C.card modalClose.AutoButtonColor = false
modalClose.Text = "✕" modalClose.TextColor3 = C.accent
modalClose.Font = FB modalClose.TextSize = 14
modalClose.ZIndex = 12 modalClose.Parent = modal
Instance.new("UICorner", modalClose).CornerRadius = UDim.new(0, 6)
local modalCloseStroke = Instance.new("UIStroke", modalClose)
modalCloseStroke.Color = C.accent modalCloseStroke.Thickness = 1
modalCloseStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
modalCloseStroke.Transparency = 0.4
modalClose.MouseButton1Click:Connect(function() modalOverlay.Visible = false end)

local modalSearch = Instance.new("TextBox")
modalSearch.Size = UDim2.new(1, -32, 0, 32) modalSearch.Position = UDim2.new(0, 16, 0, 54)
modalSearch.BackgroundColor3 = C.input modalSearch.BorderSizePixel = 0
modalSearch.Text = "" modalSearch.TextColor3 = C.text
modalSearch.PlaceholderText = "Search..."
modalSearch.PlaceholderColor3 = C.textDim
modalSearch.Font = F modalSearch.TextSize = 13
modalSearch.ClearTextOnFocus = false
modalSearch.ZIndex = 11 modalSearch.Parent = modal
Instance.new("UICorner", modalSearch).CornerRadius = UDim.new(0, 6)
local mspad = Instance.new("UIPadding") mspad.PaddingLeft = UDim.new(0, 10) mspad.Parent = modalSearch

local modalList = Instance.new("ScrollingFrame")
modalList.Size = UDim2.new(1, -32, 1, -106) modalList.Position = UDim2.new(0, 16, 0, 96)
modalList.BackgroundTransparency = 1 modalList.BorderSizePixel = 0
modalList.ScrollBarThickness = 4 modalList.ZIndex = 11 modalList.Parent = modal
local modalListLayout = Instance.new("UIListLayout")
modalListLayout.Padding = UDim.new(0, 4) modalListLayout.Parent = modalList

-- Open modal when dropdown clicked
typeDrop.MouseButton1Click:Connect(function()
    modalOverlay.Visible = true
end)
-- Click overlay outside modal closes
modalOverlay.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local pos = input.Position
        local mp, ms = modal.AbsolutePosition, modal.AbsoluteSize
        if pos.X < mp.X or pos.X > mp.X + ms.X or pos.Y < mp.Y or pos.Y > mp.Y + ms.Y then
            modalOverlay.Visible = false
        end
    end
end)

-- ============================================================
-- RULES LOGIC (multiple pet+kg+price combos)
-- ============================================================
local selectedType = nil  -- nil = all pet types (used by modal picker + add rule)
local listingRules = {}
BH.listingRules = listingRules  -- v8.308: expose biar applyState (title bar, didefinisikan lebih awal) bisa sync
local rebuildRulesUI  -- forward declare so buildRuleRow can call it

local function buildRuleRow(parent, r, idx, big)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, big and 46 or 34)
    row.BackgroundColor3 = C.input row.BorderSizePixel = 0 row.Parent = parent
    row:SetAttribute("RuleIdx", idx)  -- v8.130: tag for in-place refresh
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local fSize = big and 13 or 10                    -- v8.87: 11→10 (compact)
    local rowH = big and 32 or 24                     -- v8.87: 28→24
    local rowOff = big and -16 or -12

    -- Helper for editable cell with icon + label color
    local function makeCell(x, w, icon, iconColor, valColor, val, onChange)
        local wrap = Instance.new("Frame")
        wrap.Size = UDim2.new(0, w, 0, rowH)
        wrap.Position = UDim2.new(0, x, 0.5, rowOff)
        wrap.BackgroundColor3 = C.card wrap.BorderSizePixel = 0 wrap.Parent = row
        Instance.new("UICorner", wrap).CornerRadius = UDim.new(0, 5)
        local s = Instance.new("UIStroke", wrap)
        s.Color = iconColor s.Thickness = 1
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Transparency = 0.6
        local ic = Instance.new("TextLabel")
        ic.Size = UDim2.new(0, 12, 1, 0) ic.Position = UDim2.new(0, 2, 0, 0)  -- v8.87: 16→12
        ic.BackgroundTransparency = 1 ic.Text = icon
        ic.Font = F ic.TextSize = fSize - 1 ic.Parent = wrap
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, -16, 1, 0) box.Position = UDim2.new(0, 14, 0, 0)  -- v8.87: -20/18 → -16/14
        box.BackgroundTransparency = 1
        box.Text = val box.TextColor3 = valColor
        box.Font = FB box.TextSize = fSize
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.ClearTextOnFocus = false box.Parent = wrap
        -- v8.282: apply pas FocusLost (Enter/klik luar) — BUKAN tiap karakter.
        -- dulu pakai GetPropertyChangedSignal("Text") -> tiap ketik/hapus ke-apply,
        -- jadi pas user hapus angka mau ganti, nilai setengah keburu ke-set / batal.
        box.FocusLost:Connect(function() onChange(box.Text) end)
        return wrap, box
    end

    -- v8.88: count match badge buat LIST HARGA (parent == priceScroll)
    -- Hitung berapa pet di INVENTORY (backpack) yang match rule ini (type + KG range)
    local isPricePanel = (parent == priceScroll)
    local function countInventoryMatch()
        if BH.countMyPetsForRule then
            return BH.countMyPetsForRule(r)
        end
        return 0
    end

    -- Type label (with optional [N] count badge for LIST HARGA)
    local typeLbl = Instance.new("TextLabel")
    typeLbl.Name = "TypeLbl"  -- v8.130: named for in-place refresh
    typeLbl.Size = UDim2.new(0, 100, 1, 0) typeLbl.Position = UDim2.new(0, 6, 0, 0)
    typeLbl.BackgroundTransparency = 1
    typeLbl.TextColor3 = C.text typeLbl.Font = FB typeLbl.TextSize = fSize + 1
    typeLbl.TextXAlignment = Enum.TextXAlignment.Left
    typeLbl.TextTruncate = Enum.TextTruncate.AtEnd
    local typeText = r.type or "All"
    if isPricePanel then
        typeLbl.RichText = true
        local cnt = countInventoryMatch()
        typeLbl.Text = string.format("<font color='#22D3EE'>[%d]</font> %s", cnt, typeText)
    else
        typeLbl.Text = typeText
    end
    typeLbl.Parent = row

    -- v8.186: helper buat save state setiap kali cell edit
    local function saveAfterEdit()
        BH.marketState.listingRules = listingRules
        BH.saveMarketState(BH.marketState)
        -- v8.284: pas ubah rule (harga/kg/dll), PAUSE listing 5s. tiap ubah lagi
        -- timer reset (tick()+5), jadi selama user masih ngedit terus nunggu.
        BH.listPauseUntil = tick() + 5
        L("[Listing] rule diubah → pause listing 5s")
    end

    -- Editable MIN KG (v8.87: shrunk 64→42)
    makeCell(108, 42, "↓", C.textDim, C.text, tostring(r.min), function(txt)
        local n = tonumber(txt)
        if n and n >= 0 then r.min = n; saveAfterEdit() end
    end)

    -- Editable MAX KG (v8.87: shrunk 64→42)
    local maxKgStr = r.max == math.huge and "∞" or tostring(r.max)
    makeCell(154, 42, "↑", C.textDim, C.text, maxKgStr, function(txt)
        if txt == "" or txt == "∞" or txt == "inf" then
            r.max = math.huge; saveAfterEdit()
        else
            local n = tonumber(txt)
            if n and n > 0 then r.max = n; saveAfterEdit() end
        end
    end)

    -- Editable PRICE (v8.87: shrunk 86→66)
    makeCell(200, 66, "💰", C.accent, C.accent, tostring(r.price), function(txt)
        local n = tonumber(txt)
        if n and n > 0 then r.price = n; saveAfterEdit() end
    end)

    -- Editable MAX LIST (v8.87: shrunk 70→42)
    local mlStr = (r.maxListings == math.huge) and "∞" or tostring(r.maxListings or "∞")
    makeCell(270, 42, "📋", C.success, C.success, mlStr, function(txt)
        if txt == "" or txt == "∞" or txt == "inf" then
            r.maxListings = math.huge; saveAfterEdit()
        else
            local n = tonumber(txt)
            if n and n > 0 then r.maxListings = n; saveAfterEdit() end
        end
    end)

    -- Delete button (v8.87: shrunk 30→24)
    local delBtn = Instance.new("TextButton")
    delBtn.Size = UDim2.new(0, 24, 0, rowH)
    delBtn.Position = UDim2.new(1, -28, 0.5, rowOff)
    delBtn.BackgroundColor3 = C.danger delBtn.AutoButtonColor = false
    delBtn.Text = "✕" delBtn.TextColor3 = Color3.new(1,1,1)
    delBtn.Font = FB delBtn.TextSize = 12 delBtn.Parent = row
    Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 4)
    delBtn.MouseButton1Click:Connect(function()
        table.remove(listingRules, idx)
        rebuildRulesUI()
        -- v8.47: persist
        BH.marketState.listingRules = listingRules
        BH.saveMarketState(BH.marketState)
    end)
end

function rebuildRulesUI()
    -- Clear Listing tab rules
    for _, c in ipairs(rulesScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    -- Clear List Harga rules
    if priceScroll then
        for _, c in ipairs(priceScroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
    end

    if #listingRules == 0 then
        rulesEmptyLbl.Visible = true
        rulesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        if priceScroll then priceScroll.CanvasSize = UDim2.new(0, 0, 0, 0) end
        return
    end
    rulesEmptyLbl.Visible = false

    for idx, r in ipairs(listingRules) do
        buildRuleRow(rulesScroll, r, idx, false)  -- listing: compact (always show all)
        if priceScroll then
            -- v8.47: filter by search text di LIST HARGA
            local searchOk = true
            if priceSearchText and priceSearchText ~= "" then
                local q = priceSearchText:lower()
                local typeName = (r.type or "all"):lower()
                searchOk = typeName:find(q, 1, true) ~= nil
            end
            if searchOk then
                buildRuleRow(priceScroll, r, idx, false)  -- v8.73: compact (was true/bigger)
            end
        end
    end
    rulesScroll.CanvasSize = UDim2.new(0, 0, 0, rulesLayout.AbsoluteContentSize.Y + 12)
    if priceScroll and priceLayout then
        priceScroll.CanvasSize = UDim2.new(0, 0, 0, priceLayout.AbsoluteContentSize.Y + 16)
    end
end
BH.rebuildRulesUI = rebuildRulesUI  -- v8.308: expose biar applyState (title bar) bisa refresh UI

-- v8.130: refresh count badges WITHOUT destroy/rebuild (anti keyboard close)
BH.refreshPriceCounts = function()
    pcall(function()
        if not priceScroll then return end
        for _, row in ipairs(priceScroll:GetChildren()) do
            if row:IsA("Frame") and row:GetAttribute("RuleIdx") then
                local idx = row:GetAttribute("RuleIdx")
                local r = listingRules[idx]
                if r then
                    local lbl = row:FindFirstChild("TypeLbl")
                    if lbl and BH.countMyPetsForRule then
                        local cnt = BH.countMyPetsForRule(r) or 0
                        local typeText = r.type or "All"
                        lbl.Text = string.format("<font color='#22D3EE'>[%d]</font> %s", cnt, typeText)
                    end
                end
            end
        end
    end)
end

addRuleBtn.MouseButton1Click:Connect(function()
    local picked = {}
    for k in pairs(BH.selectedTypes) do table.insert(picked, k) end
    if #picked == 0 then
        typeDropLbl.Text = "⚠️ Pilih pet dulu!"
        typeDropLbl.TextColor3 = Color3.fromRGB(255, 120, 120)
        task.delay(2, function()
            local cnt = 0; for _ in pairs(BH.selectedTypes) do cnt = cnt + 1 end
            if cnt == 0 then
                typeDropLbl.Text = "Pilih Pet Type..."
                typeDropLbl.TextColor3 = C.text
            end
        end)
        return
    end
    local minKg = tonumber(minKgBox.Text) or 0
    local maxKg = tonumber(maxKgBox.Text) or math.huge
    local price = tonumber(priceBox.Text) or 100
    local maxList = tonumber(maxListBox.Text) or math.huge
    table.sort(picked)
    for _, petName in ipairs(picked) do
        table.insert(listingRules, {
            type = petName, min = minKg, max = maxKg,
            price = price, maxListings = maxList,
        })
    end
    rebuildRulesUI()
    BH.marketState.listingRules = listingRules
    BH.saveMarketState(BH.marketState)
    L("[State] saved "..#listingRules.." rule(s) (added "..#picked..")")
    minKgBox.Text = ""
    maxKgBox.Text = ""
    priceBox.Text = ""
    maxListBox.Text = ""
    BH.selectedTypes = {}
    selectedType = nil
    typeDropLbl.Text = "Pilih Pet Type..."
    lhTypeDropLbl.Text = "Pilih Pet Type..."
end)

-- List Harga add rule (same flow)
lhAddBtn.MouseButton1Click:Connect(function()
    local picked = {}
    for k in pairs(BH.selectedTypes) do table.insert(picked, k) end
    if #picked == 0 then
        lhTypeDropLbl.Text = "⚠️ Pilih pet dulu!"
        lhTypeDropLbl.TextColor3 = Color3.fromRGB(255, 120, 120)
        task.delay(2, function()
            local cnt = 0; for _ in pairs(BH.selectedTypes) do cnt = cnt + 1 end
            if cnt == 0 then
                lhTypeDropLbl.Text = "Pilih Pet Type..."
                lhTypeDropLbl.TextColor3 = C.text
            end
        end)
        return
    end
    local minKg = tonumber(lhMinKgBox.Text) or 0
    local maxKg = tonumber(lhMaxKgBox.Text) or math.huge
    local price = tonumber(lhPriceBox.Text) or 100
    local maxList = tonumber(lhMaxListBox.Text) or math.huge
    table.sort(picked)
    for _, petName in ipairs(picked) do
        table.insert(listingRules, {
            type = petName, min = minKg, max = maxKg,
            price = price, maxListings = maxList,
        })
    end
    rebuildRulesUI()
    BH.marketState.listingRules = listingRules
    BH.saveMarketState(BH.marketState)
    L("[State] saved "..#listingRules.." rule(s) (added "..#picked..")")
    lhMinKgBox.Text = ""
    lhMaxKgBox.Text = ""
    lhPriceBox.Text = ""
    lhMaxListBox.Text = ""
    BH.selectedTypes = {}
    selectedType = nil
    typeDropLbl.Text = "Pilih Pet Type..."
    lhTypeDropLbl.Text = "Pilih Pet Type..."
end)

-- List Harga dropdown opens same modal (modal sets typeDropLbl AND lhTypeDropLbl via modal click handler patch below)
lhTypeDrop.MouseButton1Click:Connect(function()
    modalOverlay.Visible = true
end)

-- v8.47: Restore listingRules dari state file (persist across rejoin)
if BH.marketState.listingRules and type(BH.marketState.listingRules) == "table" then
    for _, r in ipairs(BH.marketState.listingRules) do
        -- math.huge gak ke-serialize ke JSON, jadi nil → restore ke math.huge
        if r.max == nil then r.max = math.huge end
        if r.maxListings == nil then r.maxListings = math.huge end
        table.insert(listingRules, r)
    end
    L("[State] restored "..#listingRules.." rule(s) from previous session")
end

rebuildRulesUI()

-- ============================================================
-- REJOIN PANEL
-- ============================================================
-- Collapsible card helper
local function makeCollapsibleCard(parent, title, defaultExpanded)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -8, 0, 44)
    card.BackgroundColor3 = C.card
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = parent
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke", card)
    s.Color = C.accent s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Transparency = 0.5

    local header = Instance.new("TextButton")
    header.Size = UDim2.new(1, 0, 0, 44)
    header.BackgroundTransparency = 1 header.AutoButtonColor = false
    header.Text = "" header.Parent = card

    local hLbl = Instance.new("TextLabel")
    hLbl.Size = UDim2.new(1, -50, 1, 0) hLbl.Position = UDim2.new(0, 16, 0, 0)
    hLbl.BackgroundTransparency = 1 hLbl.Text = title
    hLbl.TextColor3 = C.accent hLbl.Font = FB hLbl.TextSize = 15
    hLbl.TextXAlignment = Enum.TextXAlignment.Left hLbl.Parent = header

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 30, 1, 0) arrow.Position = UDim2.new(1, -36, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = defaultExpanded and "▼" or "▶"
    arrow.TextColor3 = C.accent arrow.Font = FB arrow.TextSize = 13
    arrow.Parent = header

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, -24, 0, 0) body.Position = UDim2.new(0, 12, 0, 44)
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.BackgroundTransparency = 1
    body.Visible = defaultExpanded body.Parent = card

    local bodyLayout = Instance.new("UIListLayout")
    bodyLayout.Padding = UDim.new(0, 6) bodyLayout.Parent = body
    local bodyPad = Instance.new("UIPadding")
    bodyPad.PaddingBottom = UDim.new(0, 12) bodyPad.Parent = body

    local expanded = defaultExpanded
    local function update()
        if expanded then
            card.Size = UDim2.new(1, -8, 0, 44 + bodyLayout.AbsoluteContentSize.Y + 12)
        else
            card.Size = UDim2.new(1, -8, 0, 44)
        end
    end
    bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
    header.MouseButton1Click:Connect(function()
        expanded = not expanded
        body.Visible = expanded
        arrow.Text = expanded and "▼" or "▶"
        update()
    end)
    task.spawn(function() task.wait(0.1) update() end)
    return body
end

-- Row helpers
local function addInputRow(parent, label, default, placeholder)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32) row.BackgroundTransparency = 1 row.Parent = parent
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65, 0, 1, 0) lbl.BackgroundTransparency = 1
    lbl.Text = label lbl.TextColor3 = C.text lbl.Font = FM lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left lbl.Parent = row
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.35, -8, 0, 26) box.Position = UDim2.new(0.65, 8, 0.5, -13)
    box.BackgroundColor3 = C.input box.BorderSizePixel = 0
    box.Text = default or "" box.TextColor3 = C.text
    box.PlaceholderText = placeholder or ""
    box.PlaceholderColor3 = C.textDim
    box.Font = F box.TextSize = 13
    box.TextXAlignment = Enum.TextXAlignment.Center
    box.ClearTextOnFocus = false box.Parent = row
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    return box
end

local function addReadOnlyRow(parent, label, valueFn)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 28) row.BackgroundTransparency = 1 row.Parent = parent
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65, 0, 1, 0) lbl.BackgroundTransparency = 1
    lbl.Text = label lbl.TextColor3 = C.text lbl.Font = FM lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left lbl.Parent = row
    local v = Instance.new("TextLabel")
    v.Size = UDim2.new(0.35, -8, 1, 0) v.Position = UDim2.new(0.65, 8, 0, 0)
    v.BackgroundTransparency = 1 v.Text = "..."
    v.TextColor3 = C.accent v.Font = FB v.TextSize = 14
    v.TextXAlignment = Enum.TextXAlignment.Center v.Parent = row
    task.spawn(function()
        while row.Parent do
            local ok, val = pcall(valueFn)
            v.Text = ok and tostring(val) or "?"
            task.wait(2)
        end
    end)
    return v
end

local function addToggleRow(parent, label, defaultState)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32) row.BackgroundTransparency = 1 row.Parent = parent
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -56, 1, 0) lbl.BackgroundTransparency = 1
    lbl.Text = label lbl.TextColor3 = C.text lbl.Font = FM lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left lbl.Parent = row
    local tBg = Instance.new("Frame")
    tBg.Size = UDim2.new(0, 44, 0, 22) tBg.Position = UDim2.new(1, -44, 0.5, -11)
    tBg.BackgroundColor3 = defaultState and C.accent or C.input
    tBg.BorderSizePixel = 0 tBg.Parent = row
    Instance.new("UICorner", tBg).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = defaultState and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = Color3.new(1,1,1) knob.BorderSizePixel = 0 knob.Parent = tBg
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0) btn.BackgroundTransparency = 1
    btn.Text = "" btn.AutoButtonColor = false btn.Parent = tBg
    local state = defaultState
    local listeners = {}
    local handle = {
        get = function() return state end,
        set = function(v)
            state = v and true or false
            tBg.BackgroundColor3 = state and C.accent or C.input
            knob.Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
        end,
        onChange = function(fn) table.insert(listeners, fn) end,
    }
    btn.MouseButton1Click:Connect(function()
        handle.set(not state)
        for _, fn in ipairs(listeners) do pcall(fn, state) end
    end)
    return handle
end

local function addButtonRow(parent, label, color)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36) btn.AutoButtonColor = false
    btn.BackgroundColor3 = color or C.accent btn.BorderSizePixel = 0
    btn.Text = label btn.TextColor3 = Color3.fromRGB(20, 20, 20)
    btn.Font = FB btn.TextSize = 14 btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

-- Rejoin scroll container
local rejoinScroll = Instance.new("ScrollingFrame")
rejoinScroll.Size = UDim2.new(1, -24, 1, -24)
rejoinScroll.Position = UDim2.new(0, 12, 0, 12)
rejoinScroll.BackgroundTransparency = 1 rejoinScroll.BorderSizePixel = 0
rejoinScroll.ScrollBarThickness = 4 rejoinScroll.Parent = rejoinPanel
local rejoinSLayout = Instance.new("UIListLayout")
rejoinSLayout.Padding = UDim.new(0, 10) rejoinSLayout.Parent = rejoinScroll
task.spawn(function()
    while rejoinScroll.Parent do
        rejoinScroll.CanvasSize = UDim2.new(0, 0, 0, rejoinSLayout.AbsoluteContentSize.Y + 16)
        task.wait(0.3)
    end
end)

-- ===== Section 1: Auto Reconnect / Rejoin =====
local rejBody = makeCollapsibleCard(rejoinScroll, "Auto Reconnect / Rejoin", true)
-- v8.193: tampilin server info di paling atas
addReadOnlyRow(rejBody, "Server ID", function()
    return tostring(game.JobId):sub(1, 16).."..."
end)
addReadOnlyRow(rejBody, "Current Players", function()
    return tostring(#Players:GetPlayers()).." / "..tostring(Players.MaxPlayers or "?")
end)
local intervalBox = addInputRow(rejBody, "Rejoin every (minutes)", "", "0 = off")
local listingBox = addInputRow(rejBody, "Rejoin after N sukses listing", "", "0 = off")
local elapsedRow = addReadOnlyRow(rejBody, "Elapsed time (min)", function()
    return string.format("%.1f", (workspace.DistributedGameTime or 0) / 60)
end)
local autoRejoinToggle = addToggleRow(rejBody, "Auto Rejoin (interval)", false)
-- v8.191: Auto-rejoin kalo server <10 players + anti-same-server (compare names)
BH.autoRejoinLowPopToggle = addToggleRow(rejBody, "Auto-Rejoin server kosong (<10)", false)
-- v8.225: Auto-switch ke booth depan kalo lo dapet booth belakang
BH.autoSwitchFrontToggle = addToggleRow(rejBody, "Auto-Switch ke booth DEPAN kalo available", false)
local rejoinBtn = addButtonRow(rejBody, "🔀 HOP NOW", C.accent)

-- v8.127: bind rejoin settings to persist
-- v8.319: interval PAKSA 18m - kotak read-only, selalu 18 (abaikan input manual).
pcall(function()
    intervalBox.Text = "18"
    intervalBox.TextEditable = false
    BH.setSetting("rejoinIntervalMin", "18")
end)
BH.bindInput(listingBox, "rejoinAfterListings")
BH.bindToggle(autoRejoinToggle, "autoRejoinEnabled")
BH.bindToggle(BH.autoRejoinLowPopToggle, "autoRejoinLowPop")
BH.bindToggle(BH.autoSwitchFrontToggle, "autoSwitchFront")

-- ===== Section 2: Hop Server =====
local hopBody = makeCollapsibleCard(rejoinScroll, "Hop Server (cari server lain)", false)
addReadOnlyRow(hopBody, "Current Players", function()
    return tostring(#Players:GetPlayers())
end)
local hopAutoMinBox = addInputRow(hopBody, "Auto-hop kalau player ≤", "5", "")
local hopMinPlayersBox = addInputRow(hopBody, "Min players di server baru", "15", "")
local hopMaxPlayersBox = addInputRow(hopBody, "Max players di server baru", "30", "")
local hopTargetBox = addInputRow(hopBody, "Target players (ideal)", "25", "")
-- v8.74: delay check interval (menit) — sebelumnya hardcoded 1 menit
local hopDelayBox = addInputRow(hopBody, "Delay check (menit)", "1", "")
local hopForeignToggle = addToggleRow(hopBody, "Skip server kalau banyak Indo", false)
local autoHopToggle = addToggleRow(hopBody, "Auto Hop Server", false)
local hopNowBtn = addButtonRow(hopBody, "🔀 HOP NOW", C.accent)
local hopScanBtn = addButtonRow(hopBody, "🔍 SCAN PLAYER SEKARANG", C.card)

-- v8.127: bind hop settings to persist
BH.bindInput(hopAutoMinBox, "hopAutoMin")
BH.bindInput(hopMinPlayersBox, "hopMinPlayers")
BH.bindInput(hopMaxPlayersBox, "hopMaxPlayers")
BH.bindInput(hopTargetBox, "hopTarget")
BH.bindInput(hopDelayBox, "hopDelay")
BH.bindToggle(hopForeignToggle, "hopForeign")
BH.bindToggle(autoHopToggle, "autoHopEnabled")

-- v8.130: persist listing rule input fields too
BH.bindInput(minKgBox,   "lastMinKg")
BH.bindInput(maxKgBox,   "lastMaxKg")
BH.bindInput(priceBox,   "lastPrice")
BH.bindInput(maxListBox, "lastMaxList")

-- For backward compat - autoRejoinBox alias + hopMinBox alias
local autoRejoinBox = listingBox
local hopMinBox = hopAutoMinBox

-- ============================================================
-- MISC PANEL
-- ============================================================
local miscPad = Instance.new("UIPadding")
miscPad.PaddingTop = UDim.new(0, 14) miscPad.PaddingLeft = UDim.new(0, 14)
miscPad.PaddingRight = UDim.new(0, 14) miscPad.PaddingBottom = UDim.new(0, 14)
miscPad.Parent = miscPanel
local miscLayout = Instance.new("UIListLayout") miscLayout.Padding = UDim.new(0, 10) miscLayout.SortOrder = Enum.SortOrder.LayoutOrder miscLayout.Parent = miscPanel

local function makeCard(parent, height)
    local c = Instance.new("Frame")
    c.Size = UDim2.new(1, 0, 0, height) c.BackgroundColor3 = C.card c.BorderSizePixel = 0
    c.Parent = parent
    Instance.new("UICorner", c).CornerRadius = UDim.new(0, 8)
    return c
end

-- BOOTH MGMT CARD
local boothCard = makeCard(miscPanel, 120)
lblOf(boothCard, "🏠  BOOTH", 14, 10, 200, 22, C.accent, 14, FB)
lblOf(boothCard, "Auto-claim booth empty (unlist all dipindah ke Pantau)", 14, 32, 400, 18, C.textDim, 11)
local claimBtn = btnOf(boothCard, 14, 54, 140, 26, "🏠 CLAIM BOOTH", C.accent)
-- v8.43: Auto-Claim toggle | v8.132: persist
local autoClaimState = (BH.marketState and BH.marketState.autoClaim) == true
local autoClaimBtn = btnOf(boothCard, 14, 86, 200, 26,
    autoClaimState and "🤖 Auto-Claim: ON" or "🤖 Auto-Claim: OFF",
    autoClaimState and C.success or C.danger)
autoClaimBtn.MouseButton1Click:Connect(function()
    autoClaimState = not autoClaimState
    autoClaimBtn.Text = autoClaimState and "🤖 Auto-Claim: ON" or "🤖 Auto-Claim: OFF"
    autoClaimBtn.BackgroundColor3 = autoClaimState and C.success or C.danger
    -- v8.132: persist
    if BH.marketState then
        BH.marketState.autoClaim = autoClaimState
        BH.saveMarketState(BH.marketState)
    end
    L(autoClaimState and "[Auto-Claim] enabled (check 15s)" or "[Auto-Claim] disabled")
end)


-- DISPLAY PET CARD
local petCard = makeCard(miscPanel, 86)
lblOf(petCard, "👜  DISPLAY PET", 14, 10, 250, 22, C.accent, 14, FB)
lblOf(petCard, "Auto-equip pet biar keliatan di booth", 14, 32, 400, 18, C.textDim, 11)
-- v8.70: load dari state, default true
local autoEquipState = true
if BH.marketState and BH.marketState.autoEquip ~= nil then autoEquipState = BH.marketState.autoEquip end
local autoEquipBtn = btnOf(petCard, 14, 54, 140, 26,
    autoEquipState and "👜 Equip: ON" or "👜 Equip: OFF",
    autoEquipState and C.success or C.danger)
local equipMode = (BH.marketState and BH.marketState.equipMode) or "BIGGEST"
local equipModeBtn = btnOf(petCard, 164, 54, 140, 26, "📦 "..equipMode, C.card, C.text)
-- v8.254: pilih JENIS pet yg di-equip (cuma jenis ini yg dipajang). "ALL" = semua.
-- pakai BH.equipPetType (bukan local) biar gak nambah local var di scope utama.
BH.equipPetType = (BH.marketState and BH.marketState.equipPetType) or "ALL"
BH.equipTypeBtn = btnOf(petCard, 314, 54, 150, 26,
    "🐾 "..(BH.equipPetType == "ALL" and "Semua Jenis" or BH.equipPetType), C.card, C.text)

-- v8.46: ANTI-AFK CARD (wrapped in do-block to manage local count)
do
    local afkCard = makeCard(miscPanel, 86)
    lblOf(afkCard, "🚫  ANTI-AFK", 14, 10, 250, 22, C.accent, 14, FB)
    lblOf(afkCard, "Cegah kick karena idle (~20 menit)", 14, 32, 400, 18, C.textDim, 11)
    local antiAfkBtn = btnOf(afkCard, 14, 54, 160, 26,
        antiAfkEnabled and "🚫 Anti-AFK: ON" or "🚫 Anti-AFK: OFF",
        antiAfkEnabled and C.success or C.danger)
    antiAfkBtn.MouseButton1Click:Connect(function()
        antiAfkEnabled = not antiAfkEnabled
        antiAfkBtn.Text = antiAfkEnabled and "🚫 Anti-AFK: ON" or "🚫 Anti-AFK: OFF"
        antiAfkBtn.BackgroundColor3 = antiAfkEnabled and C.success or C.danger
        -- v8.70: persist
        if BH.marketState then
            BH.marketState.antiAfkEnabled = antiAfkEnabled
            BH.saveMarketState(BH.marketState)
        end
        L(antiAfkEnabled and "[anti-afk] ON" or "[anti-afk] OFF")
    end)
end

-- MIGRATE CARD
local migCard = makeCard(miscPanel, 86)
lblOf(migCard, "➡  AUTO MIGRATE", 14, 10, 250, 22, C.accent, 14, FB)
lblOf(migCard, "Pindah ke booth front row kalo kosong (DEFAULT OFF)", 14, 32, 400, 18, C.textDim, 11)
-- v8.49: default OFF (user complain auto-pindah booth tanpa diminta) + persist state
local autoMigState = (BH.marketState and BH.marketState.autoMigrate) == true
local autoMigBtn = btnOf(migCard, 14, 54, 140, 26,
    autoMigState and "🤖 Auto: ON" or "🤖 Auto: OFF",
    autoMigState and C.success or C.danger)
local migNowBtn = btnOf(migCard, 164, 54, 140, 26, "➡ MIGRATE NOW", C.accent)

-- SKIN CARD
local skinCard = makeCard(miscPanel, 86)
lblOf(skinCard, "🎨  BOOTH SKIN", 14, 10, 250, 22, C.accent, 14, FB)
lblOf(skinCard, "Pilih skin booth (perlu buka skin selector di game)", 14, 32, 400, 18, C.textDim, 11)
local skinPickBtn = btnOf(skinCard, 14, 54, 200, 26, "🎨 BUKA SKIN PICKER", C.accent)

-- v8.49: TRAVEL TO GARDEN card — TP balik dari market ke garden
do
    local travelCard = makeCard(miscPanel, 86)
    lblOf(travelCard, "🌱  TRAVEL TO GARDEN", 14, 10, 300, 22, C.accent, 14, FB)
    lblOf(travelCard, "TP balik dari trade world ke garden/plot lo", 14, 32, 400, 18, C.textDim, 11)
    local travelBtn = btnOf(travelCard, 14, 54, 220, 26, "🌱 GO TO GARDEN", C.success)
    travelBtn.TextColor3 = Color3.new(1, 1, 1)
    local travelStatus = lblOf(travelCard, "", 240, 56, 200, 22, C.textDim, 10)

    BH.travelToGarden = function()
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            travelStatus.Text = "❌ no character"
            travelStatus.TextColor3 = C.danger
            return false
        end

        -- Method 1: Cari garden cam part di Workspace (cek banyak nama umum)
        local candidates = {
            "FarmCamPart", "GardenCamPart", "SpawnCamPart", "MainSpawnPart",
            "HomeCamPart", "PlotCamPart", "MainCamPart", "GameCamPart",
            "BackToGardenPart", "LeaveTradePart",
        }
        for _, name in ipairs(candidates) do
            local part = Workspace:FindFirstChild(name)
            if part and part:IsA("BasePart") then
                hrp.CFrame = part.CFrame + Vector3.new(0, 5, 0)
                travelStatus.Text = "✅ "..name
                travelStatus.TextColor3 = C.success
                L("[Travel] ✅ TP ke "..name)
                return true
            end
        end

        -- Method 2: Cari farm/plot punya lo
        for _, parentName in ipairs({"Farms", "Plots", "PlayerFarms", "Gardens"}) do
            local plots = Workspace:FindFirstChild(parentName)
            if plots then
                for _, plot in ipairs(plots:GetChildren()) do
                    local owner = plot:GetAttribute("Owner") or plot:GetAttribute("a")
                        or plot:GetAttribute("UserId") or plot:GetAttribute("OwnerId")
                    local isMine = (owner == player.Name)
                        or (tostring(owner) == tostring(player.UserId))
                        or (plot.Name == player.Name)
                        or (plot.Name == tostring(player.UserId))
                    if isMine then
                        local prim = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart", true)
                        if prim then
                            hrp.CFrame = prim.CFrame + Vector3.new(0, 10, 0)
                            travelStatus.Text = "✅ ke plot lo"
                            travelStatus.TextColor3 = C.success
                            L("[Travel] ✅ TP ke plot lo di "..parentName)
                            return true
                        end
                    end
                end
            end
        end

        -- Method 3: Cari remote dengan nama travel/teleport/leave
        for _, c in ipairs(RS:GetDescendants()) do
            if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                local n = c.Name:lower()
                if (n:find("leavetrad") or n:find("backtogarden") or n:find("returntogarden")
                    or n:find("teleporttofarm") or n:find("gohome")) then
                    pcall(function()
                        if c:IsA("RemoteFunction") then c:InvokeServer()
                        else c:FireServer() end
                    end)
                    travelStatus.Text = "✅ remote: "..c.Name
                    travelStatus.TextColor3 = C.success
                    L("[Travel] fired remote "..c:GetFullName())
                    return true
                end
            end
        end

        travelStatus.Text = "❌ gak nemu garden"
        travelStatus.TextColor3 = C.danger
        L("[Travel] ❌ gak nemu garden cam / plot / remote")
        return false
    end

    travelBtn.MouseButton1Click:Connect(function()
        travelStatus.Text = "loading..."
        task.spawn(BH.travelToGarden)
    end)
end

-- v8.155: AGE LOCK card — multi-select, pet age 1 dan/atau 100 (kg predictable)
do
    local ageCard = makeCard(miscPanel, 118)
    ageCard.LayoutOrder = -5
    lblOf(ageCard, "🔒  AGE LOCK (currently INACTIVE)", 14, 10, 380, 22, C.textDim, 14, FB)
    lblOf(ageCard, "Filter age di-pause (bikin auto-start break). Toggle disimpen aja.", 14, 32, 480, 18, C.textDim, 11)

    -- Load saved state (table format: {[1]=true, [100]=true})
    BH.ageLockAllowed = {}
    if BH.marketState and type(BH.marketState.ageLockAllowed) == "table" then
        for k, v in pairs(BH.marketState.ageLockAllowed) do
            local n = tonumber(k)
            if n and v then BH.ageLockAllowed[n] = true end
        end
    end

    local btnAge1 = btnOf(ageCard, 14, 56, 130, 30, "AGE 1", C.card)
    local btnAge100 = btnOf(ageCard, 152, 56, 140, 30, "AGE 100", C.card)
    local btnClear = btnOf(ageCard, 300, 56, 80, 30, "ANY", C.card)
    local ageStatusLbl = lblOf(ageCard, "Allowed: any age", 14, 92, 480, 18, C.textDim, 10)

    local function refreshBtns()
        local s = BH.ageLockAllowed or {}
        btnAge1.BackgroundColor3 = s[1] and C.success or C.card
        btnAge1.TextColor3 = s[1] and Color3.new(0,0,0) or C.text
        btnAge100.BackgroundColor3 = s[100] and C.success or C.card
        btnAge100.TextColor3 = s[100] and Color3.new(0,0,0) or C.text
        -- ANY button hijau kalo gak ada yg di-toggle (= any age)
        local none = not (s[1] or s[100])
        btnClear.BackgroundColor3 = none and C.accent or C.card
        btnClear.TextColor3 = none and Color3.new(0,0,0) or C.text

        -- status text
        local picked = {}
        if s[1] then table.insert(picked, "Age 1") end
        if s[100] then table.insert(picked, "Age 100") end
        if #picked == 0 then
            ageStatusLbl.Text = "Allowed: any age"
        else
            ageStatusLbl.Text = "Allowed: "..table.concat(picked, " + ")
        end
    end
    refreshBtns()

    local function persistAge()
        if BH.marketState then
            BH.marketState.ageLockAllowed = {}
            for k, v in pairs(BH.ageLockAllowed) do
                BH.marketState.ageLockAllowed[tostring(k)] = v
            end
            BH.saveMarketState(BH.marketState)
        end
    end

    btnAge1.MouseButton1Click:Connect(function()
        BH.ageLockAllowed[1] = (not BH.ageLockAllowed[1]) and true or nil
        refreshBtns(); persistAge()
        L("[AgeLock] Age 1 toggled — set="..tostring(BH.ageLockAllowed[1] or "off"))
    end)
    btnAge100.MouseButton1Click:Connect(function()
        BH.ageLockAllowed[100] = (not BH.ageLockAllowed[100]) and true or nil
        refreshBtns(); persistAge()
        L("[AgeLock] Age 100 toggled — set="..tostring(BH.ageLockAllowed[100] or "off"))
    end)
    btnClear.MouseButton1Click:Connect(function()
        BH.ageLockAllowed = {}
        refreshBtns(); persistAge()
        L("[AgeLock] cleared → any age")
    end)
end

-- v8.48: AUTO-START card — auto klik START pas script load (kalau rules ada)
do
    local autoStartCard = makeCard(miscPanel, 86)
    lblOf(autoStartCard, "🚀  AUTO-START", 14, 10, 250, 22, C.accent, 14, FB)
    lblOf(autoStartCard, "Auto klik START pas script di-load (saved across rejoin)", 14, 32, 460, 18, C.textDim, 11)
    local autoStartBtn = btnOf(autoStartCard, 14, 54, 220, 26, "🚀 Auto-Start: OFF", C.danger)
    -- Init dari state
    BH.autoStart = BH.marketState.autoStart == true
    if BH.autoStart then
        autoStartBtn.Text = "🚀 Auto-Start: ON"
        autoStartBtn.BackgroundColor3 = C.success
    end
    autoStartBtn.MouseButton1Click:Connect(function()
        BH.autoStart = not BH.autoStart
        autoStartBtn.Text = BH.autoStart and "🚀 Auto-Start: ON" or "🚀 Auto-Start: OFF"
        autoStartBtn.BackgroundColor3 = BH.autoStart and C.success or C.danger
        L("[Auto-Start] "..(BH.autoStart and "enabled" or "disabled"))
        -- Save ke state
        BH.marketState.autoStart = BH.autoStart
        BH.saveMarketState(BH.marketState)
        -- v8.176: kalo user toggle ON dan blm running, langsung fire onStartClick
        if BH.autoStart and BH.onStartClick then
            task.spawn(function()
                task.wait(0.5)
                local running = BH.getIsRunning and BH.getIsRunning() or false
                if BH.autoStart and not running then
                    L("🚀 [Auto-Start] toggle ON → langsung fire onStartClick")
                    pcall(BH.onStartClick)
                end
            end)
        end
    end)
end

-- v8.189: BUYER TRACKER card — notif sale + count buyer, frequent buyer (>5x) muncul di HISTORY SELL
do
    local btCard = makeCard(miscPanel, 86)
    lblOf(btCard, "📊  BUYER TRACKER & NOTIF", 14, 10, 300, 22, C.accent, 14, FB)
    lblOf(btCard, "Notif tiap sale + count buyer, yg beli >5x masuk list copy", 14, 32, 480, 18, C.textDim, 11)
    local btState = (BH.marketState and BH.marketState.buyerTrackerEnabled) == true
    local btBtn = btnOf(btCard, 14, 54, 220, 26, btState and "📊 Tracker: ON" or "📊 Tracker: OFF", btState and C.success or C.danger)
    BH.buyerTrackerEnabled = btState
    btBtn.MouseButton1Click:Connect(function()
        BH.buyerTrackerEnabled = not BH.buyerTrackerEnabled
        btBtn.Text = BH.buyerTrackerEnabled and "📊 Tracker: ON" or "📊 Tracker: OFF"
        btBtn.BackgroundColor3 = BH.buyerTrackerEnabled and C.success or C.danger
        BH.marketState.buyerTrackerEnabled = BH.buyerTrackerEnabled
        BH.saveMarketState(BH.marketState)
        L("[Buyer-Tracker] "..(BH.buyerTrackerEnabled and "enabled" or "disabled"))
    end)
end

-- v8.189: Buyer counts + Notif system + Sale watcher (IIFE to escape 200-local limit)
;(function()
BH.buyerCounts = (BH.marketState and BH.marketState.buyerCounts) or {}
BH.frequentBuyerThreshold = 5  -- > 5x masuk frequent list

-- Notif banner di top screen (auto-fade)
local notifQueue = {}
local notifShowing = false
BH.showNotif = function(text, color)
    table.insert(notifQueue, {text = text, color = color or C.accent})
    if notifShowing then return end
    notifShowing = true
    task.spawn(function()
        while #notifQueue > 0 do
            local n = table.remove(notifQueue, 1)
            local banner = Instance.new("Frame")
            banner.Size = UDim2.new(0, 400, 0, 40)
            banner.Position = UDim2.new(0.5, -200, 0, -50)
            banner.BackgroundColor3 = C.panel
            banner.BorderSizePixel = 0
            banner.ZIndex = 100
            banner.Parent = gui
            Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 8)
            local stroke = Instance.new("UIStroke", banner)
            stroke.Color = n.color; stroke.Thickness = 2
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, -20, 1, 0)
            lbl.Position = UDim2.new(0, 10, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = n.text
            lbl.TextColor3 = n.color
            lbl.Font = FB
            lbl.TextSize = 13
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextTruncate = Enum.TextTruncate.AtEnd
            lbl.ZIndex = 101
            lbl.Parent = banner
            -- Slide in
            banner:TweenPosition(UDim2.new(0.5, -200, 0, 20), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.4, true)
            task.wait(3)
            -- Slide out
            banner:TweenPosition(UDim2.new(0.5, -200, 0, -50), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.3, true)
            task.wait(0.4)
            banner:Destroy()
        end
        notifShowing = false
    end)
end

-- Setup watcher — listen BoothHistoryTemplate ChildAdded buat detect sale baru
task.spawn(function()
    task.wait(5)
    local LP = game:GetService("Players").LocalPlayer
    local tbh = LP.PlayerGui:WaitForChild("TradeBoothHistory", 30)
    if not tbh then L("[Buyer-Tracker] TradeBoothHistory GUI gak ketemu"); return end
    local sf = tbh.Frame:WaitForChild("ScrollingFrame", 5)
    if not sf then L("[Buyer-Tracker] ScrollingFrame gak ketemu"); return end

    sf.ChildAdded:Connect(function(template)
        if template.Name ~= "BoothHistoryTemplate" then return end
        if not BH.buyerTrackerEnabled then return end
        task.wait(0.3)
        pcall(function()
            local spacer = template:FindFirstChild("Spacer")
            if not spacer then return end
            local title = spacer:FindFirstChild("Title")
            if not title then return end
            local label = title:FindFirstChild("Label")
            if not label or tostring(label.Text) ~= "Sold" then return end  -- skip purchases

            local plrLbl = title:FindFirstChild("PlrName")
            local buyerName = plrLbl and tostring(plrLbl.Text) or "?"
            local petName = spacer:FindFirstChild("ItemName") and tostring(spacer.ItemName.Text) or "?"
            local price = spacer:FindFirstChild("Price") and spacer.Price:FindFirstChild("Amount")
                          and tostring(spacer.Price.Amount.Text) or "?"

            -- Increment count
            BH.buyerCounts[buyerName] = (BH.buyerCounts[buyerName] or 0) + 1
            local cnt = BH.buyerCounts[buyerName]
            BH.marketState.buyerCounts = BH.buyerCounts
            BH.saveMarketState(BH.marketState)

            -- Notif banner
            BH.showNotif(string.format("🛒 SOLD: %s @ %s → %s (%dx)", petName, price, buyerName, cnt), C.success)
            L(string.format("🛒 [Buyer-Tracker] %s @ %s → %s (total %dx)", petName, price, buyerName, cnt))

            -- Refresh frequent buyers UI kalo udah > threshold
            if cnt >= BH.frequentBuyerThreshold and BH.refreshFrequentBuyers then
                BH.refreshFrequentBuyers()
            end
        end)
    end)

    L("[Buyer-Tracker] watcher INSTALLED")
end)
end)()

-- v8.145: AUTO-UNLIST NON-MATCH card — auto unlist pet di booth yg gak match rule
do
    local cleanCard = makeCard(miscPanel, 110)
    cleanCard.LayoutOrder = -10  -- v8.154: paling atas MISC
    lblOf(cleanCard, "🧹  AUTO-CLEAN BOOTH", 14, 10, 360, 22, C.accent, 14, FB)
    lblOf(cleanCard, "Unlist pet non-match rule + cap kelebihan maxListings (cek 10s)", 14, 32, 480, 18, C.textDim, 11)
    local cleanState = (BH.marketState and BH.marketState.autoCleanNonMatch) == true
    local cleanBtn = btnOf(cleanCard, 14, 54, 220, 26,
        cleanState and "🧹 Auto-Clean: ON" or "🧹 Auto-Clean: OFF",
        cleanState and C.success or C.danger)
    local cleanNowBtn = btnOf(cleanCard, 244, 54, 130, 26, "▶ CLEAN NOW", C.accent)
    local cleanStatus = lblOf(cleanCard, "Idle.", 14, 84, 480, 18, C.textDim, 10)

    BH.autoCleanNonMatch = cleanState

    -- v8.145: function buat cek apa listing match rule yg ada
    local function checkListingMatchesRule(listing, item)
        if not item or not item.PetData then return false end
        local pType = tostring(item.PetType or "")
        local pd = item.PetData
        local kg = BH.computeBaseKgFromPetData(pd)
        local price = tonumber(listing.Price) or 0
        for _, r in ipairs(listingRules) do
            local typeOk = (r.type == pType or r.type == "All" or not r.type or r.type == "")
            local kgOk = kg >= (r.min or 0) and kg <= (r.max or math.huge)
            local priceOk = price == (r.price or 0)
            if typeOk and kgOk and priceOk then return true end
        end
        return false
    end

    BH.scanForNonMatch = function()
        -- Resolve removeRE if nil
        if not removeRE then
            pcall(function()
                removeRE = RS:FindFirstChild("GameEvents")
                    and RS.GameEvents:FindFirstChild("TradeEvents")
                    and RS.GameEvents.TradeEvents:FindFirstChild("Booths")
                    and RS.GameEvents.TradeEvents.Booths:FindFirstChild("RemoveListing")
            end)
        end
        if not removeRE then return 0, 0, "removeRE nil" end
        if #listingRules == 0 then return 0, 0, "no rules" end

        local data = BH.fetchBoothData(player)
        if not data or not data.Listings then return 0, 0, "no booth data" end

        -- v8.150: Group listings by matching rule index, then cap by maxListings
        -- FIX: KG basis age-1 (×1.1), strip mutation prefix dari pType
        local function findMatchingRuleIdx(listing, item)
            if not item or not item.PetData then return nil end
            local rawType = tostring(item.PetType or "")
            local pType = (BH.getBaseName and rawType ~= "") and BH.getBaseName(rawType) or rawType
            local pd = item.PetData
            local bw = tonumber(pd.BaseWeight) or 0
            local ageOneKg = bw * 1.1   -- age-1 normalized (cocok dgn rule input)
            local price = tonumber(listing.Price) or 0
            for idx, r in ipairs(listingRules) do
                local typeOk = (r.type == pType or r.type == rawType or r.type == "All" or not r.type or r.type == "")
                local kgOk = ageOneKg >= (r.min or 0) and ageOneKg <= (r.max or math.huge)
                local priceOk = price == (r.price or 0)
                if typeOk and kgOk and priceOk then return idx end
            end
            return nil
        end

        local listingsByRule = {}  -- ruleIdx → {uuids}
        local nonMatching = {}
        local totalListings = 0

        for listingUuid, listing in pairs(data.Listings) do
            if listing.ItemType == "Pet" and listing.ItemId then
                totalListings = totalListings + 1
                local item = data.Items and data.Items[listing.ItemId]
                if item and item.PetData then
                    local ruleIdx = findMatchingRuleIdx(listing, item)
                    if ruleIdx then
                        listingsByRule[ruleIdx] = listingsByRule[ruleIdx] or {}
                        table.insert(listingsByRule[ruleIdx], listingUuid)
                    else
                        table.insert(nonMatching, listingUuid)
                    end
                end
            end
        end

        -- Build unlist queue
        local toUnlist = {}
        -- 1. Non-matching pets (gak ada di rule manapun)
        for _, uuid in ipairs(nonMatching) do
            table.insert(toUnlist, uuid)
        end
        -- 2. Excess pet di rule yg punya maxListings
        local excessCount = 0
        for idx, uuids in pairs(listingsByRule) do
            local r = listingRules[idx]
            local maxAllowed = r.maxListings or math.huge
            if maxAllowed ~= math.huge and #uuids > maxAllowed then
                for i = maxAllowed + 1, #uuids do
                    table.insert(toUnlist, uuids[i])
                    excessCount = excessCount + 1
                end
            end
        end

        L(string.format("[Auto-Clean] scan: total=%d, non-match=%d, excess=%d, will unlist=%d",
            totalListings, #nonMatching, excessCount, #toUnlist))

        -- v8.150: SAFETY GUARD — kalo 100% listing classified non-match, abort.
        -- Itu hampir pasti bug (KG mismatch atau pet type wrong), bukan keadaan asli
        -- v8.185: SMARTER safety guard — bedakan price-only mismatch (legitimate, user ganti harga)
        -- vs type/kg mismatch (suspicious, probably bug match logic)
        -- Re-scan: hitung berapa pet yg gagal CUMA gara price (TYPE + KG match)
        local priceOnlyMismatch = 0
        for listingUuid, listing in pairs(data.Listings) do
            if listing.ItemType == "Pet" and listing.ItemId then
                local item = data.Items and data.Items[listing.ItemId]
                if item and item.PetData then
                    local rawType = tostring(item.PetType or "")
                    local pType = (BH.getBaseName and rawType ~= "") and BH.getBaseName(rawType) or rawType
                    local bw = tonumber(item.PetData.BaseWeight) or 0
                    local ageOneKg = bw * 1.1
                    for _, r in ipairs(listingRules) do
                        local typeOk = (r.type == pType or r.type == rawType or r.type == "All" or not r.type or r.type == "")
                        local kgOk = ageOneKg >= (r.min or 0) and ageOneKg <= (r.max or math.huge)
                        if typeOk and kgOk then
                            priceOnlyMismatch = priceOnlyMismatch + 1
                            break
                        end
                    end
                end
            end
        end

        if totalListings > 0 and #nonMatching == totalListings and #listingRules > 0 then
            -- Kalo SEMUA non-match TAPI sebagian besar (>50%) cuma gara price → legitimate (user ganti harga)
            -- Lanjut unlist; sc bakal re-list di harga baru
            if priceOnlyMismatch > totalListings * 0.5 then
                L(string.format("[Auto-Clean] %d/%d non-match karena PRICE only → lanjut unlist (user ganti harga)",
                    priceOnlyMismatch, totalListings))
            else
                L("[Auto-Clean] ⚠⚠⚠ SEMUA listing classified non-match (bukan price-issue) — kemungkinan bug match logic, ABORT")
                -- log sample rule + sample listing untuk diagnose
                local sampleRule = listingRules[1]
                L("[Auto-Clean] sample rule: type='"..tostring(sampleRule.type).."' min="..tostring(sampleRule.min).." max="..tostring(sampleRule.max).." price="..tostring(sampleRule.price))
                for listingUuid, listing in pairs(data.Listings) do
                    if listing.ItemType == "Pet" and listing.ItemId then
                        local item = data.Items and data.Items[listing.ItemId]
                        if item and item.PetData then
                            local bw = tonumber(item.PetData.BaseWeight) or 0
                            L("[Auto-Clean] sample listing: type='"..tostring(item.PetType).."' BW="..bw.." → age1Kg="..(bw*1.1).." price="..tostring(listing.Price))
                            break
                        end
                    end
                end
                return 0, 0, "SAFETY ABORT — 100% non-match"
            end
        end

        if #toUnlist == 0 then return 0, totalListings - #nonMatching, "all OK" end

        -- PARALLEL unlist batch
        local removed = 0
        local pending = #toUnlist
        local boothUuid = BH.myBoothUuid and tostring(BH.myBoothUuid):gsub("[{}]","") or nil

        for _, listingUuid in ipairs(toUnlist) do
            task.spawn(function()
                local cleanListing = tostring(listingUuid):gsub("[{}]","")
                local itemId = data.Listings[listingUuid] and data.Listings[listingUuid].ItemId
                local cleanItem = itemId and tostring(itemId):gsub("[{}]","") or nil
                local attempts = {
                    {cleanListing},
                    {"{"..cleanListing.."}"},
                }
                if cleanItem then table.insert(attempts, {cleanItem}) end
                if boothUuid then table.insert(attempts, {boothUuid, cleanListing}) end
                for _, args in ipairs(attempts) do
                    if not removeRE then break end
                    local ok, r1
                    if removeRE:IsA("RemoteFunction") then
                        ok, r1 = pcall(function() return removeRE:InvokeServer(unpack(args)) end)
                    else
                        ok, r1 = pcall(function() removeRE:FireServer(unpack(args)); return true end)
                    end
                    if ok and (r1 == true or r1 == nil or (type(r1) == "string" and not r1:lower():find("error") and not r1:lower():find("fail"))) then
                        removed = removed + 1
                        if BH.markUnlistedByMe then BH.markUnlistedByMe(listingUuid) end  -- v8.156
                        break
                    end
                end
                pending = pending - 1
            end)
            task.wait(0.05)  -- stagger
        end

        -- Wait all done
        local waitStart = tick()
        while pending > 0 and (tick() - waitStart) < 20 do
            task.wait(0.3)
        end

        return removed, totalListings - #nonMatching, string.format("non-match=%d, excess=%d", #nonMatching, excessCount)
    end

    -- CLEAN NOW button — manual trigger
    cleanNowBtn.MouseButton1Click:Connect(function()
        task.spawn(function()
            cleanStatus.Text = "🔍 Scanning booth..."
            cleanStatus.TextColor3 = C.accent
            local removed, matched, msg = BH.scanForNonMatch()
            cleanStatus.Text = string.format("✅ Removed %d non-match | %d match | %s", removed, matched, msg)
            cleanStatus.TextColor3 = (removed > 0) and C.success or C.textDim
            L(string.format("[Auto-Clean] manual: removed=%d matched=%d (%s)", removed, matched, msg))
        end)
    end)

    -- Toggle
    cleanBtn.MouseButton1Click:Connect(function()
        BH.autoCleanNonMatch = not BH.autoCleanNonMatch
        cleanBtn.Text = BH.autoCleanNonMatch and "🧹 Auto-Clean: ON" or "🧹 Auto-Clean: OFF"
        cleanBtn.BackgroundColor3 = BH.autoCleanNonMatch and C.success or C.danger
        if BH.marketState then
            BH.marketState.autoCleanNonMatch = BH.autoCleanNonMatch
            BH.saveMarketState(BH.marketState)
        end
        L("[Auto-Clean] "..(BH.autoCleanNonMatch and "enabled (check tiap 10s)" or "disabled"))
    end)

    -- Background watchdog — cek tiap 10s
    task.spawn(function()
        task.wait(15)  -- initial delay biar semua init kelar
        while gui.Parent do
            if BH.autoCleanNonMatch and #listingRules > 0 then
                local ok, removed, matched, msg = pcall(BH.scanForNonMatch)
                if ok and removed and removed > 0 then
                    cleanStatus.Text = string.format("Auto: removed %d non-match", removed)
                    cleanStatus.TextColor3 = C.success
                    L(string.format("[Auto-Clean] BG: removed=%d matched=%d", removed, matched or 0))
                end
            end
            task.wait(10)
        end
    end)
end


-- v8.49: PET TYPES card — breakdown pet di backpack per type
do
    local petTypesCard = makeCard(miscPanel, 240)
    lblOf(petTypesCard, "📋  PET TYPES (di backpack)", 14, 10, 360, 22, C.accent, 14, FB)
    local totLbl = lblOf(petTypesCard, "Total: 0 pets", 14, 32, 360, 18, C.text, 12, FM)
    local ptRefreshBtn = btnOf(petTypesCard, 280, 14, 80, 22, "🔄 REFRESH", C.accent)
    ptRefreshBtn.TextSize = 10

    local ptScroll = Instance.new("ScrollingFrame")
    ptScroll.Size = UDim2.new(1, -20, 0, 170)
    ptScroll.Position = UDim2.new(0, 10, 0, 56)
    ptScroll.BackgroundColor3 = C.input
    ptScroll.BorderSizePixel = 0
    ptScroll.ScrollBarThickness = 4
    ptScroll.ScrollBarImageColor3 = C.accent
    ptScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    ptScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ptScroll.Parent = petTypesCard
    Instance.new("UICorner", ptScroll).CornerRadius = UDim.new(0, 6)
    local ptLayout = Instance.new("UIListLayout")
    ptLayout.Padding = UDim.new(0, 2) ptLayout.Parent = ptScroll
    local ptPad = Instance.new("UIPadding")
    ptPad.PaddingTop = UDim.new(0, 4) ptPad.PaddingBottom = UDim.new(0, 4)
    ptPad.PaddingLeft = UDim.new(0, 6) ptPad.PaddingRight = UDim.new(0, 6)
    ptPad.Parent = ptScroll

    BH.refreshPetTypes = function()
        for _, c in ipairs(ptScroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local bp = player:FindFirstChild("Backpack")
        if not bp then totLbl.Text = "Total: 0 | no backpack"; return end

        local total, favC = 0, 0
        local tc = {}
        for _, t in ipairs(bp:GetChildren()) do
            if isPet(t) then
                total = total + 1
                if isFav(t) then favC = favC + 1 end
                local pt = getPetType(t)
                local kg = getCurrentKg(t)
                if not tc[pt] then tc[pt] = {n=0, mn=math.huge, mx=0} end
                tc[pt].n = tc[pt].n + 1
                if kg > 0 then
                    tc[pt].mn = math.min(tc[pt].mn, kg)
                    tc[pt].mx = math.max(tc[pt].mx, kg)
                end
            end
        end
        local nTypes = 0 for _ in pairs(tc) do nTypes = nTypes + 1 end
        totLbl.Text = string.format("Total: %d pets  |  ⭐ %d fav  |  %d types", total, favC, nTypes)

        local sorted = {}
        for pt, info in pairs(tc) do table.insert(sorted, {pt=pt, info=info}) end
        table.sort(sorted, function(a, b) return a.info.n > b.info.n end)

        for i, e in ipairs(sorted) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -8, 0, 22)
            row.BackgroundColor3 = (i % 2 == 0) and C.bg or C.card
            row.BorderSizePixel = 0 row.Parent = ptScroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
            local nm = Instance.new("TextLabel")
            nm.Size = UDim2.new(0.55, -4, 1, 0) nm.Position = UDim2.new(0, 8, 0, 0)
            nm.BackgroundTransparency = 1 nm.Text = e.pt
            nm.TextColor3 = C.text nm.Font = FM nm.TextSize = 11
            nm.TextXAlignment = Enum.TextXAlignment.Left
            nm.TextTruncate = Enum.TextTruncate.AtEnd nm.Parent = row
            local cn = Instance.new("TextLabel")
            cn.Size = UDim2.new(0.20, 0, 1, 0) cn.Position = UDim2.new(0.55, 0, 0, 0)
            cn.BackgroundTransparency = 1 cn.Text = "×"..e.info.n
            cn.TextColor3 = C.accent cn.Font = FB cn.TextSize = 11
            cn.TextXAlignment = Enum.TextXAlignment.Center cn.Parent = row
            local kg = Instance.new("TextLabel")
            kg.Size = UDim2.new(0.25, 0, 1, 0) kg.Position = UDim2.new(0.75, 0, 0, 0)
            kg.BackgroundTransparency = 1
            kg.Text = (e.info.mx > 0) and string.format("%.1f-%.1f", e.info.mn, e.info.mx) or "-"
            kg.TextColor3 = C.textDim kg.Font = FM kg.TextSize = 10
            kg.TextXAlignment = Enum.TextXAlignment.Right kg.Parent = row
        end
    end

    ptRefreshBtn.MouseButton1Click:Connect(BH.refreshPetTypes)

    -- Auto-refresh on backpack change
    local function bindBp()
        local bp = player:FindFirstChild("Backpack")
        if not bp then return end
        bp.ChildAdded:Connect(function() task.wait(0.1); pcall(BH.refreshPetTypes) end)
        bp.ChildRemoved:Connect(function() task.wait(0.1); pcall(BH.refreshPetTypes) end)
    end
    bindBp()
    player.CharacterAdded:Connect(function() task.wait(1); bindBp(); pcall(BH.refreshPetTypes) end)

    -- Initial scan after isPet/getPetType are defined (they're defined later, so delay)
    task.spawn(function()
        task.wait(2)
        pcall(BH.refreshPetTypes)
    end)
end

-- ============================================================
-- PANTAU BOOTH PANEL (v8.39)
-- ============================================================
do
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 14) pad.PaddingLeft = UDim.new(0, 14)
    pad.PaddingRight = UDim.new(0, 14) pad.PaddingBottom = UDim.new(0, 14)
    pad.Parent = pantauPanel

    -- Header card
    local hdrCard = Instance.new("Frame")
    hdrCard.Size = UDim2.new(1, 0, 0, 64)
    hdrCard.BackgroundColor3 = C.card
    hdrCard.BorderSizePixel = 0
    hdrCard.Parent = pantauPanel
    Instance.new("UICorner", hdrCard).CornerRadius = UDim.new(0, 8)

    lblOf(hdrCard, "📋  PANTAU BOOTH-MU", 14, 8, 240, 22, C.accent, 14, FB)
    local statusLbl = lblOf(hdrCard, "Klik REFRESH untuk scan", 14, 30, 380, 18, C.textDim, 11)
    local refreshBtn = btnOf(hdrCard, 14, 50, 100, 26, "🔄 REFRESH", C.accent)
    local unlistOneBtn = btnOf(hdrCard, 122, 50, 130, 26, "🗑️ UNLIST PILIH", C.danger)
    local unlistAllBtn = btnOf(hdrCard, 260, 50, 120, 26, "🗑️ UNLIST ALL", C.danger)

    -- Scrollable list area
    local listFrame = Instance.new("Frame")
    listFrame.Size = UDim2.new(1, 0, 1, -78)
    listFrame.Position = UDim2.new(0, 0, 0, 74)
    listFrame.BackgroundColor3 = C.bg
    listFrame.BorderSizePixel = 0
    listFrame.Parent = pantauPanel
    Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 8)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -8, 1, -8)
    scroll.Position = UDim2.new(0, 4, 0, 4)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = C.accent
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = listFrame
    local scrollLayout = Instance.new("UIListLayout")
    scrollLayout.Padding = UDim.new(0, 6)
    scrollLayout.Parent = scroll
    Instance.new("UIPadding", scroll).PaddingRight = UDim.new(0, 4)

    -- Tracker for selected listings (for batch unlist)
    local selectedUuids = {}

    local function clearList()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        selectedUuids = {}
    end

    local function refreshList()
        clearList()
        selectedUuids = {}

        -- v8.46: TBC data — instant, no streaming, no TP
        statusLbl.Text = "🔄 Fetching booth data..."
        statusLbl.TextColor3 = C.textDim

        if not BH.TBC then
            statusLbl.Text = "❌ TBC gak ke-load. Close + reopen script."
            statusLbl.TextColor3 = C.danger
            return
        end

        local data = BH.getMyBoothData()
        if not data then
            statusLbl.Text = "❌ Gagal fetch data (TBC error)"
            statusLbl.TextColor3 = C.danger
            return
        end

        local boothUuid = data.Booth
        if not boothUuid or boothUuid == "" then
            statusLbl.Text = "⚠ Lo belum CLAIM booth. Claim dulu di game."
            statusLbl.TextColor3 = C.danger
            return
        end

        -- Save booth UUID
        local clean = tostring(boothUuid):gsub("[{}]","")
        BH.myBoothUuid = clean
        -- v8.131: merge, don't replace
        BH.marketState.myBoothUuid = clean
        pcall(function() BH.saveMarketState(BH.marketState) end)

        -- Collect listings
        local listings = {}
        if data.Listings then
            for listingUuid, l in pairs(data.Listings) do
                local item = data.Items and l.ItemId and data.Items[l.ItemId]
                table.insert(listings, {
                    listingUuid = listingUuid,
                    price = tonumber(l.Price) or 0,
                    itemType = l.ItemType,
                    itemId = l.ItemId,
                    item = item,
                })
            end
        end
        table.sort(listings, function(a, b) return a.price < b.price end)

        statusLbl.Text = "📦 "..#listings.." listing  •  Booth "..clean:sub(1,8).."...  •  Tap utk pilih"
        statusLbl.TextColor3 = C.success

        for i, l in ipairs(listings) do
            local frame = Instance.new("Frame")
            frame.Size = UDim2.new(1, 0, 0, 64)
            frame.BackgroundColor3 = C.card
            frame.BorderSizePixel = 0
            frame.Parent = scroll
            Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

            local stroke = Instance.new("UIStroke", frame)
            stroke.Color = C.accent
            stroke.Thickness = 0
            stroke.Transparency = 0.3

            -- Extract info from PetData
            local pType = "?"
            local mutType = ""
            local levelStr = "?"
            local baseRaw = "?"
            local baseAdj = "?"
            local petName = ""

            if l.item then
                pType = tostring(l.item.PetType or "?")
                local pd = l.item.PetData
                if pd then
                    mutType = tostring(pd.MutationType or "")
                    levelStr = tostring(pd.Level or "?")
                    petName = tostring(pd.Name or "")
                    if tonumber(pd.BaseWeight) then
                        baseRaw = string.format("%.2f", pd.BaseWeight)
                        local adj = BH.computeBaseKgFromPetData(pd)
                        baseAdj = string.format("%.2f", adj)
                    end
                end
            elseif l.itemType then
                pType = tostring(l.itemType)  -- "Holdable" etc
            end

            local title = i..". "..pType
            if mutType ~= "" then title = title.." ["..mutType.."]" end
            if petName ~= "" then title = title.."  ~"..petName end
            lblOf(frame, title, 12, 6, 320, 18, C.text, 13, FB)

            local info = string.format("Base %s  •  @age1 %s  •  Lv %s", baseRaw, baseAdj, levelStr)
            lblOf(frame, info, 12, 24, 320, 16, C.textDim, 11)

            lblOf(frame, "💰 "..tostring(l.price).."  •  L "..tostring(l.listingUuid):sub(1,8).."...", 12, 42, 300, 16, C.textDim, 11)

            local clickBtn = Instance.new("TextButton")
            clickBtn.Size = UDim2.new(1, 0, 1, 0)
            clickBtn.BackgroundTransparency = 1
            clickBtn.Text = ""
            clickBtn.Parent = frame
            local lUuid = l.listingUuid
            clickBtn.MouseButton1Click:Connect(function()
                if selectedUuids[lUuid] then
                    selectedUuids[lUuid] = nil
                    stroke.Thickness = 0
                    frame.BackgroundColor3 = C.card
                else
                    selectedUuids[lUuid] = true
                    stroke.Thickness = 1.5
                    frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
                end
            end)
        end
    end

    refreshBtn.MouseButton1Click:Connect(function()
        task.spawn(refreshList)
    end)

    -- Unlist selected listings
    unlistOneBtn.MouseButton1Click:Connect(function()
        task.spawn(function()
            local toUnlist = {}
            for uuid, _ in pairs(selectedUuids) do table.insert(toUnlist, uuid) end
            if #toUnlist == 0 then
                statusLbl.Text = "⚠ Belum pilih listing (tap di list)"
                statusLbl.TextColor3 = C.danger
                return
            end

            -- v8.139: guard — kalo removeRE nil, coba TBC method dulu
            local useTbcMethod = nil
            -- v8.143: AKSES DIRECT VIA PATH — debug confirm path exist, bypass cached removeRE
            local directRE = nil
            pcall(function()
                directRE = RS:FindFirstChild("GameEvents")
                    and RS.GameEvents:FindFirstChild("TradeEvents")
                    and RS.GameEvents.TradeEvents:FindFirstChild("Booths")
                    and RS.GameEvents.TradeEvents.Booths:FindFirstChild("RemoveListing")
            end)
            if directRE then
                removeRE = directRE
                L("[Pantau] ✅ direct path: removeRE = "..directRE.ClassName)
            else
                statusLbl.Text = "⏳ Wait remote replicate..."
                statusLbl.TextColor3 = C.accent
                pcall(function()
                    directRE = RS:WaitForChild("GameEvents", 15)
                        :WaitForChild("TradeEvents", 5)
                        :WaitForChild("Booths", 5)
                        :WaitForChild("RemoveListing", 10)
                end)
                if directRE then
                    removeRE = directRE
                    L("[Pantau] ✅ WaitForChild: removeRE found")
                end
            end
            if not removeRE then
                L("[Pantau] removeRE NIL — cari TBC method...")
                if BH.TBC then
                    for _, mname in ipairs({"RemoveListing", "Unlist", "DeleteListing", "RemoveItem", "Delist"}) do
                        if type(BH.TBC[mname]) == "function" then
                            useTbcMethod = mname
                            L("[Pantau] ✅ pake TBC."..mname)
                            break
                        end
                    end
                end
                if not useTbcMethod then
                    statusLbl.Text = "❌ removeRE & TBC method semua nil"
                    statusLbl.TextColor3 = C.danger
                    L("[Pantau] ❌ removeRE nil + TBC gak punya unlist method. Cek log [Init] TBC methods.")
                    return
                end
            end

            statusLbl.Text = "🗑️ Unlist "..#toUnlist.." pet (parallel)..."
            statusLbl.TextColor3 = C.accent

            -- v8.144: PARALLEL batched unlist
            local removed = 0
            local failed = 0
            local BATCH_SIZE = 10
            local data = BH.getMyBoothData()
            local boothUuid = BH.myBoothUuid and tostring(BH.myBoothUuid):gsub("[{}]","") or nil

            local function tryUnlistOne(listingUuid)
                local itemId = data and data.Listings and data.Listings[listingUuid] and data.Listings[listingUuid].ItemId
                local cleanListing = tostring(listingUuid):gsub("[{}]","")
                local bracedListing = "{"..cleanListing.."}"
                local cleanItem = itemId and tostring(itemId):gsub("[{}]","") or nil

                local attempts = {
                    {label="listing-clean", args={cleanListing}},
                    {label="listing-braced", args={bracedListing}},
                }
                if cleanItem then
                    table.insert(attempts, {label="item-clean", args={cleanItem}})
                end
                if boothUuid then
                    table.insert(attempts, {label="booth+listing", args={boothUuid, cleanListing}})
                end

                -- TBC fallback
                if useTbcMethod then
                    local ok = pcall(function() return BH.TBC[useTbcMethod](BH.TBC, cleanListing) end)
                    if ok then return true, "TBC."..useTbcMethod end
                    ok = pcall(function() return BH.TBC[useTbcMethod](BH.TBC, bracedListing) end)
                    if ok then return true, "TBC."..useTbcMethod.." (braced)" end
                    return false, "TBC failed"
                end

                for _, a in ipairs(attempts) do
                    if not removeRE then return false, "removeRE nil" end
                    local ok, r1
                    if removeRE:IsA("RemoteFunction") then
                        ok, r1 = pcall(function() return removeRE:InvokeServer(unpack(a.args)) end)
                    else
                        ok, r1 = pcall(function() removeRE:FireServer(unpack(a.args)); return true end)
                    end
                    local isSuccess = (ok and r1 == true)
                        or (ok and r1 == nil)
                        or (ok and type(r1) == "string" and not r1:lower():find("error") and not r1:lower():find("fail") and not r1:lower():find("not"))
                    if isSuccess then return true, a.label end
                end
                return false, "all_formats_failed"
            end

            -- Batch processing
            for batchStart = 1, #toUnlist, BATCH_SIZE do
                local batchEnd = math.min(batchStart + BATCH_SIZE - 1, #toUnlist)
                local pending = batchEnd - batchStart + 1

                for i = batchStart, batchEnd do
                    task.spawn(function()
                        local success, info = tryUnlistOne(toUnlist[i])
                        if success then
                            removed = removed + 1
                            if BH.markUnlistedByMe then BH.markUnlistedByMe(toUnlist[i]) end  -- v8.156
                        else
                            failed = failed + 1
                            L("[Pantau] ["..i.."] ✗ "..tostring(info))
                        end
                        pending = pending - 1
                    end)
                    task.wait(0.05)
                end

                -- Wait batch complete
                local waitStart = tick()
                while pending > 0 and (tick() - waitStart) < 15 do
                    statusLbl.Text = string.format("🗑️ Batch %d-%d: %d✓ (pending %d)", batchStart, batchEnd, removed, pending)
                    task.wait(0.3)
                end

                if batchEnd < #toUnlist then task.wait(0.3) end
            end

            statusLbl.Text = "✅ Unlisted "..removed.." / "..#toUnlist
            statusLbl.TextColor3 = (removed == #toUnlist) and C.success or C.accent
            L("[Pantau] DONE: "..removed.."/"..#toUnlist)
            task.wait(1)
            refreshList()
        end)
    end)

    -- v8.47: UNLIST ALL button — unlist semua listing di booth-mu
    -- v8.78: rate-limit aware + fresh TBC fetch + detailed error log
    unlistAllBtn.MouseButton1Click:Connect(function()
        task.spawn(function()
            statusLbl.Text = "🔄 Fetching booth data..."
            statusLbl.TextColor3 = C.textDim

            if not BH.TBC then
                statusLbl.Text = "❌ TBC gak load"
                statusLbl.TextColor3 = C.danger
                return
            end

            -- v8.143: AKSES DIRECT VIA PATH — debug confirm path exist
            do
                local directRE = nil
                pcall(function()
                    directRE = RS:FindFirstChild("GameEvents")
                        and RS.GameEvents:FindFirstChild("TradeEvents")
                        and RS.GameEvents.TradeEvents:FindFirstChild("Booths")
                        and RS.GameEvents.TradeEvents.Booths:FindFirstChild("RemoveListing")
                end)
                if directRE then
                    removeRE = directRE
                    L("[Unlist-ALL] ✅ direct path: removeRE = "..directRE.ClassName)
                else
                    statusLbl.Text = "⏳ Wait remote replicate..."
                    statusLbl.TextColor3 = C.accent
                    pcall(function()
                        directRE = RS:WaitForChild("GameEvents", 15)
                            :WaitForChild("TradeEvents", 5)
                            :WaitForChild("Booths", 5)
                            :WaitForChild("RemoveListing", 10)
                    end)
                    if directRE then
                        removeRE = directRE
                        L("[Unlist-ALL] ✅ WaitForChild: removeRE found")
                    end
                end
            end
            if not removeRE then
                -- v8.106: coba pake TBC method kalo removeRE total gak ada
                if BH.TBC then
                    L("[Unlist-ALL] removeRE missing, coba TBC method")
                    local tbcMethods = {"RemoveListing", "Unlist", "DeleteListing", "RemoveItem"}
                    local foundMethod = nil
                    for _, mname in ipairs(tbcMethods) do
                        if type(BH.TBC[mname]) == "function" then
                            foundMethod = mname; break
                        end
                    end
                    if foundMethod then
                        L("[Unlist-ALL] TBC method: "..foundMethod)
                        statusLbl.Text = "🔄 Pake TBC."..foundMethod
                        -- Try TBC method (signature unknown — best effort)
                        -- Fetch listings dan call method per listing
                        local data = BH.fetchBoothData(player)
                        if data and data.Listings then
                            local count = 0
                            for listingUuid, _ in pairs(data.Listings) do
                                local ok = pcall(function()
                                    BH.TBC[foundMethod](BH.TBC, listingUuid)
                                end)
                                if ok then count = count + 1 end
                                task.wait(0.3)
                            end
                            statusLbl.Text = "✅ "..count.." via TBC"
                            statusLbl.TextColor3 = C.success
                            return
                        end
                    else
                        L("[Unlist-ALL] TBC pun gak punya method unlist. Dump all TBC method names:")
                        for k, v in pairs(BH.TBC) do
                            if type(v) == "function" then L("  TBC."..k) end
                        end
                    end
                end
                statusLbl.Text = "❌ removeRE gak ada (cek log)"
                statusLbl.TextColor3 = C.danger
                L("[Unlist-ALL] ❌ removeRE not found, gak bisa unlist")
                return
            end

            -- v8.78: FRESH fetch (jangan pake cache yang mungkin stale)
            local data = BH.fetchBoothData(player)
            if not data or not data.Listings then
                statusLbl.Text = "❌ Gak ada data booth"
                statusLbl.TextColor3 = C.danger
                L("[Unlist-ALL] ❌ TBC return no Listings")
                return
            end

            -- Collect semua listingUuid
            local allUuids = {}
            for listingUuid, _ in pairs(data.Listings) do
                table.insert(allUuids, listingUuid)
            end

            if #allUuids == 0 then
                statusLbl.Text = "ℹ Booth-mu kosong"
                statusLbl.TextColor3 = C.textDim
                L("[Unlist-ALL] booth kosong (0 listings di TBC)")
                return
            end

            L("[Unlist-ALL] start: "..#allUuids.." listings (PARALLEL batch=10)")
            statusLbl.Text = "🗑️ Unlist "..#allUuids.." pet (parallel)..."
            statusLbl.TextColor3 = C.accent

            -- v8.144: PARALLEL batched unlist — fire 10 at once
            local removed = 0
            local failed = 0
            local rateLimited = false
            local BATCH_SIZE = 10
            local boothUuid = BH.myBoothUuid and tostring(BH.myBoothUuid):gsub("[{}]","") or nil
            local bracedBooth = boothUuid and ("{"..boothUuid.."}") or nil

            -- Helper untuk unlist 1 pet (run di task.spawn)
            local function tryUnlistOne(listingUuid, idx)
                local itemId = data.Listings[listingUuid] and data.Listings[listingUuid].ItemId
                local cleanListing = tostring(listingUuid):gsub("[{}]","")
                local bracedListing = "{"..cleanListing.."}"
                local cleanItem = itemId and tostring(itemId):gsub("[{}]","") or nil
                local bracedItem = itemId and ("{"..(cleanItem or "").."}") or nil

                local attempts = {
                    {label="listing-clean", args={cleanListing}},
                    {label="listing-braced", args={bracedListing}},
                }
                if cleanItem then
                    table.insert(attempts, {label="item-clean", args={cleanItem}})
                    table.insert(attempts, {label="item-braced", args={bracedItem}})
                end
                if boothUuid then
                    table.insert(attempts, {label="booth+listing-clean", args={boothUuid, cleanListing}})
                end

                for _, a in ipairs(attempts) do
                    if not removeRE then return false, "removeRE nil" end
                    local ok, r1
                    if removeRE:IsA("RemoteFunction") then
                        ok, r1 = pcall(function() return removeRE:InvokeServer(unpack(a.args)) end)
                    else
                        ok, r1 = pcall(function() removeRE:FireServer(unpack(a.args)); return true end)
                    end
                    local isSuccess = (ok and r1 == true)
                        or (ok and r1 == nil)
                        or (ok and type(r1) == "string" and not r1:lower():find("error") and not r1:lower():find("fail"))
                    if isSuccess then
                        return true, a.label
                    end
                    -- detect rate limit
                    if ok and type(r1) == "string" then
                        local lo = r1:lower()
                        if lo:find("please wait") or lo:find("cooldown") or lo:find("too fast") or lo:find("rate") then
                            return false, "RATE_LIMIT:"..r1:sub(1, 80)
                        end
                    end
                end
                return false, "all_formats_failed"
            end

            -- Batch processing
            for batchStart = 1, #allUuids, BATCH_SIZE do
                if rateLimited then break end
                local batchEnd = math.min(batchStart + BATCH_SIZE - 1, #allUuids)
                local pending = batchEnd - batchStart + 1
                local batchRemoved = 0
                local batchFailed = 0

                statusLbl.Text = string.format("🗑️ Batch %d-%d / %d (parallel)", batchStart, batchEnd, #allUuids)

                -- Fire batch in parallel
                for i = batchStart, batchEnd do
                    task.spawn(function()
                        local success, info = tryUnlistOne(allUuids[i], i)
                        if success then
                            batchRemoved = batchRemoved + 1
                            removed = removed + 1
                            if BH.markUnlistedByMe then BH.markUnlistedByMe(allUuids[i]) end  -- v8.156
                        else
                            batchFailed = batchFailed + 1
                            failed = failed + 1
                            if info and info:find("RATE_LIMIT") then
                                rateLimited = true
                                L("[Unlist-ALL] ⏳ RATE LIMIT detected — stopping further batches")
                            end
                        end
                        pending = pending - 1
                    end)
                    task.wait(0.05)  -- small stagger
                end

                -- Wait for batch to complete
                local waitStart = tick()
                while pending > 0 and (tick() - waitStart) < 15 do
                    statusLbl.Text = string.format("🗑️ Batch %d-%d: %d✓ %d✗ (pending %d)", batchStart, batchEnd, batchRemoved, batchFailed, pending)
                    task.wait(0.3)
                end

                L(string.format("[Unlist-ALL] batch %d-%d: %d✓ %d✗", batchStart, batchEnd, batchRemoved, batchFailed))

                -- Small pause between batches
                if batchEnd < #allUuids and not rateLimited then
                    task.wait(0.5)
                end
            end

            local color = removed == #allUuids and C.success or (removed > 0 and C.accent or C.danger)
            statusLbl.Text = string.format("✅ %d / %d unlisted", removed, #allUuids)
            statusLbl.TextColor3 = color
            L("[Unlist-ALL] DONE: "..removed.."/"..#allUuids.." (failed: "..failed..")")
            task.wait(1)
            refreshList()
        end)
    end)

    -- Auto-refresh saat tab dibuka
    subBtns.Pantau.btn.MouseButton1Click:Connect(function()
        task.wait(0.1)  -- biar tab switching dulu
        task.spawn(refreshList)
    end)
end

-- ============================================================
-- SNIPE PANEL (Manual + Otomatis sub-tabs)
-- ============================================================
-- Forward declarations (these are used by snipe scanner later)
local snRefreshBtn, snCountLbl, snSearch, snScroll, snScrollLayout
local snMinAge, snMaxAge, snMinKg, snMaxKg, snMinPrice, snMaxPrice
-- v8.62: simpan di BH biar accessible di luar do-block tanpa nambah local
BH.snSubBtns = {}
BH.snSubPanels = {}

do
-- v8.73: Snipe sub-tab bar — compact (was h=40 y=12, now h=26 y=8)
local snSubTabBar = Instance.new("Frame")
snSubTabBar.Size = UDim2.new(1, -24, 0, 26) snSubTabBar.Position = UDim2.new(0, 12, 0, 8)
snSubTabBar.BackgroundTransparency = 1 snSubTabBar.Parent = snipePanel
do local l = Instance.new("UIListLayout") l.FillDirection = Enum.FillDirection.Horizontal
l.Padding = UDim.new(0, 8) l.Parent = snSubTabBar end

local function makeSnSubPanel(name)
    local sp = Instance.new("Frame")
    -- v8.73: panel start y=40 (was 60) — sub-tab smaller
    sp.Size = UDim2.new(1, -24, 1, -44) sp.Position = UDim2.new(0, 12, 0, 40)
    sp.BackgroundColor3 = C.panel sp.BorderSizePixel = 0
    sp.Visible = false sp.Parent = snipePanel
    Instance.new("UICorner", sp).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", sp) stroke.Color = C.accent stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border stroke.Transparency = 0.7
    BH.snSubPanels[name] = sp
    return sp
end
local function makeSnSubBtn(name)
    local b = Instance.new("TextButton")
    -- v8.257: 4 visible tabs (Manual, Otomatis, History, Index Hop) — Buy hidden
    b.Size = UDim2.new(0.25, -6, 1, 0) b.AutoButtonColor = false
    b.BackgroundColor3 = C.card b.BorderSizePixel = 0
    b.Text = "" b.Parent = snSubTabBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)  -- v8.73: smaller corner
    local stroke = Instance.new("UIStroke", b)
    stroke.Color = C.accent stroke.Thickness = 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border stroke.Transparency = 0.3
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0) lbl.BackgroundTransparency = 1
    lbl.Text = name lbl.TextColor3 = C.textDim
    lbl.Font = FB lbl.TextSize = 10 lbl.Parent = b  -- v8.73: 12 → 10
    BH.snSubBtns[name] = {btn=b, stroke=stroke, lbl=lbl}
    b.MouseButton1Click:Connect(function()
        for n, d in pairs(BH.snSubBtns) do
            if n == name then
                d.stroke.Thickness = 1.5
                d.lbl.TextColor3 = C.accent
            else
                d.stroke.Thickness = 0
                d.lbl.TextColor3 = C.textDim
            end
        end
        for n, sp in pairs(BH.snSubPanels) do sp.Visible = (n == name) end
    end)
    return b
end

makeSnSubBtn("Manual")
makeSnSubBtn("Buy")           -- v8.96: kept for Server Hunter backend, button hidden
makeSnSubBtn("Otomatis")
makeSnSubBtn("History")       -- v8.96: NEW — snipe history
makeSnSubBtn("Index Hop")    -- v8.257: NEW — auto hop server via Index FindSellers
local snManualPanel = makeSnSubPanel("Manual")
local snBuyPanel = makeSnSubPanel("Buy")
local snAutoPanel = makeSnSubPanel("Otomatis")
local snHistoryPanel = makeSnSubPanel("History")  -- v8.96
local snIndexPanel = makeSnSubPanel("Index Hop")  -- v8.257
snManualPanel.Visible = true
BH.snSubBtns.Manual.stroke.Thickness = 1.5
BH.snSubBtns.Manual.lbl.TextColor3 = C.accent
-- v8.96: Hide tab Buy (user request — udah ada tab Manual yang sama fungsinya)
BH.snSubBtns.Buy.btn.Visible = false

-- ===== MANUAL SNIPE TAB =====
local snPad = Instance.new("UIPadding")
snPad.PaddingTop = UDim.new(0, 14) snPad.PaddingLeft = UDim.new(0, 14)
snPad.PaddingRight = UDim.new(0, 14) snPad.PaddingBottom = UDim.new(0, 14)
snPad.Parent = snManualPanel

-- v8.73: title, subtitle, count label di-hide — search jadi y=0
lblOf(snManualPanel, "🎯  SNIPE MANUAL", 0, 0, 400, 24, C.accent, 14, FB).Visible = false
lblOf(snManualPanel, "Scan semua pet — auto-refresh 10s", 0, 24, 600, 16, C.textDim, 10).Visible = false

-- v8.49: hide refresh+TP, counter inline
snRefreshBtn = btnOf(snManualPanel, 0, 0, 1, 1, "🔄 MUAT ULANG", C.accent)
snRefreshBtn.Visible = false
local snTpBtn = btnOf(snManualPanel, 0, 0, 1, 1, "🗺 TP TRADE", C.success)
snTpBtn.Visible = false
snCountLbl = Instance.new("TextLabel")
snCountLbl.Size = UDim2.new(1, 0, 0, 16) snCountLbl.Position = UDim2.new(0, 0, 0, 42)
snCountLbl.BackgroundTransparency = 1
snCountLbl.Text = "Loading scan..."
snCountLbl.TextColor3 = C.success snCountLbl.Font = FM snCountLbl.TextSize = 10
snCountLbl.TextXAlignment = Enum.TextXAlignment.Left snCountLbl.Parent = snManualPanel
snCountLbl.Visible = false  -- v8.73: hidden (text updates still happen in code, just not displayed)

-- TP handler (kept for compat — bisa di-call dari handler)
snTpBtn.MouseButton1Click:Connect(function()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local tradeCam = Workspace:FindFirstChild("TradeworldCamPart")
        or Workspace:FindFirstChild("LoadingCamPart")
    if tradeCam and tradeCam:IsA("BasePart") then
        hrp.CFrame = tradeCam.CFrame + Vector3.new(0, 5, 0)
    else
        local TW = Workspace:FindFirstChild("TradeWorld")
        local Booths = TW and TW:FindFirstChild("Booths")
        local firstBooth = Booths and Booths:GetChildren()[1]
        if firstBooth then
            local prim = firstBooth.PrimaryPart or firstBooth:FindFirstChildWhichIsA("BasePart")
            if prim then hrp.CFrame = prim.CFrame + Vector3.new(0, 5, 0) end
        end
    end
end)

-- Search box (80%)
snSearch = Instance.new("TextBox")
snSearch.Size = UDim2.new(0.8, -4, 0, 28) snSearch.Position = UDim2.new(0, 0, 0, 0)  -- v8.74: 100% → 80%
snSearch.BackgroundColor3 = C.input snSearch.BorderSizePixel = 0
snSearch.Text = (BH.marketState and BH.marketState.snSearch) or ""
snSearch.TextColor3 = C.text
snSearch.PlaceholderText = "🔍 search pet name or type..."
snSearch.PlaceholderColor3 = C.textDim
snSearch.Font = F snSearch.TextSize = 12
snSearch.ClearTextOnFocus = false snSearch.Parent = snManualPanel
Instance.new("UICorner", snSearch).CornerRadius = UDim.new(0, 6)
do local p = Instance.new("UIPadding")
p.PaddingLeft = UDim.new(0, 12) p.Parent = snSearch end

-- v8.74: refresh button (20% kanan)
snRefreshBtn.Size = UDim2.new(0.2, 0, 0, 28)
snRefreshBtn.Position = UDim2.new(0.8, 4, 0, 0)
snRefreshBtn.Text = "🔄"
snRefreshBtn.TextSize = 14
snRefreshBtn.Visible = true

-- Filter chips row
local snFilterFrame = Instance.new("Frame")
snFilterFrame.Size = UDim2.new(1, 0, 0, 28) snFilterFrame.Position = UDim2.new(0, 0, 0, 34)  -- v8.73: y=96 → 34
snFilterFrame.BackgroundTransparency = 1 snFilterFrame.Parent = snManualPanel
do local l = Instance.new("UIListLayout") l.FillDirection = Enum.FillDirection.Horizontal
l.Padding = UDim.new(0, 4) l.Parent = snFilterFrame end

local function makeFilterBox(parent, placeholder, w)
    local b = Instance.new("TextBox")
    b.Size = UDim2.new(0, w or 60, 1, 0)
    b.BackgroundColor3 = C.input b.BorderSizePixel = 0
    b.Text = "" b.TextColor3 = C.text
    b.PlaceholderText = placeholder
    b.PlaceholderColor3 = C.textDim
    b.Font = F b.TextSize = 11
    b.TextXAlignment = Enum.TextXAlignment.Center
    b.ClearTextOnFocus = false b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end

snMinAge = makeFilterBox(snFilterFrame, "Age ≥", 60)
snMaxAge = makeFilterBox(snFilterFrame, "Age ≤", 60)
snMinKg = makeFilterBox(snFilterFrame, "KG ≥", 60)
snMaxKg = makeFilterBox(snFilterFrame, "KG ≤", 60)
snMinPrice = makeFilterBox(snFilterFrame, "Price ≥", 70)
snMaxPrice = makeFilterBox(snFilterFrame, "Price ≤", 70)
-- v8.70: restore filter values dari state file
if BH.marketState then
    snMinAge.Text = BH.marketState.snMinAge or ""
    snMaxAge.Text = BH.marketState.snMaxAge or ""
    snMinKg.Text = BH.marketState.snMinKg or ""
    snMaxKg.Text = BH.marketState.snMaxKg or ""
    snMinPrice.Text = BH.marketState.snMinPrice or ""
    snMaxPrice.Text = BH.marketState.snMaxPrice or ""
end
local snResetBtn = Instance.new("TextButton")
snResetBtn.Size = UDim2.new(0, 60, 1, 0) snResetBtn.AutoButtonColor = false
snResetBtn.BackgroundColor3 = C.danger
snResetBtn.Text = "Reset" snResetBtn.TextColor3 = Color3.new(1,1,1)
snResetBtn.Font = FB snResetBtn.TextSize = 11 snResetBtn.Parent = snFilterFrame
Instance.new("UICorner", snResetBtn).CornerRadius = UDim.new(0, 5)

-- Table header
local snHeader = Instance.new("Frame")
snHeader.Size = UDim2.new(1, 0, 0, 22) snHeader.Position = UDim2.new(0, 0, 0, 72)  -- v8.73: y=134 → 72
snHeader.BackgroundColor3 = C.card snHeader.BorderSizePixel = 0
snHeader.Parent = snManualPanel
Instance.new("UICorner", snHeader).CornerRadius = UDim.new(0, 4)
local function snHdr(text, x, w)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(w, 0, 1, 0) l.Position = UDim2.new(x, 4, 0, 0)
    l.BackgroundTransparency = 1 l.Text = text
    l.TextColor3 = C.accent l.Font = FB l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left l.Parent = snHeader
end
snHdr("Pet Type", 0, 0.20)
snHdr("Mutation", 0.20, 0.14)
snHdr("KG", 0.34, 0.10)
snHdr("Owner", 0.44, 0.22)
snHdr("Price", 0.66, 0.14)
snHdr("Action", 0.80, 0.18)

-- Listings table (big now!)
snScroll = Instance.new("ScrollingFrame")
snScroll.Size = UDim2.new(1, 0, 1, -98) snScroll.Position = UDim2.new(0, 0, 0, 98)  -- v8.73: y=160 → 98
snScroll.BackgroundColor3 = C.card snScroll.BorderSizePixel = 0
snScroll.ScrollBarThickness = 4 snScroll.Parent = snManualPanel
Instance.new("UICorner", snScroll).CornerRadius = UDim.new(0, 8)
snScrollLayout = Instance.new("UIListLayout")
snScrollLayout.Padding = UDim.new(0, 3) snScrollLayout.Parent = snScroll
do local p = Instance.new("UIPadding")
p.PaddingTop = UDim.new(0, 4) p.PaddingLeft = UDim.new(0, 4) p.PaddingRight = UDim.new(0, 4)
p.Parent = snScroll end

-- v8.84: ===== AUTO SNIPE TAB (auto-buy berdasarkan rules) =====
-- Continuously scan market di server ini, auto-buy pet yang match rules
BH.autoSnipe = BH.autoSnipe or {
    active = false,
    rules = {},          -- list of {petType, mutation, maxKg, maxPrice}
    bought = {},         -- listingUuid → true (skip yang udah dibeli)
    cooldown = {},       -- v8.265: listingUuid → tick() terakhir gagal (retry setelah 2s)
    boughtCount = 0,
}
-- Restore rules dari state file
if BH.marketState and BH.marketState.autoSnipeRules then
    BH.autoSnipe.rules = BH.marketState.autoSnipeRules
end
-- v8.258: restore filter asal egg (all/prem/biasa)
BH.autoSnipe.eggSource = (BH.marketState and BH.marketState.autoSnipeEggSource) or "all"
-- v8.265: pastikan cooldown table ada (kalau autoSnipe udah dibuat sebelumnya)
BH.autoSnipe.cooldown = BH.autoSnipe.cooldown or {}

do
    local snAutoPad = Instance.new("UIPadding")
    snAutoPad.PaddingTop = UDim.new(0, 10) snAutoPad.PaddingLeft = UDim.new(0, 12)
    snAutoPad.PaddingRight = UDim.new(0, 12) snAutoPad.PaddingBottom = UDim.new(0, 10)
    snAutoPad.Parent = snAutoPanel

    -- Helper untuk bikin input box
    local function makeAutoInput(xs, ws, ph, ts)
        local b = Instance.new("TextBox")
        b.Size = UDim2.new(ws, -3, 0, 26)
        b.Position = UDim2.new(xs, xs == 0 and 0 or 3, 0, 0)
        b.BackgroundColor3 = C.input b.BorderSizePixel = 0
        b.Text = "" b.TextColor3 = C.text
        b.PlaceholderText = ph b.PlaceholderColor3 = C.textDim
        b.Font = F b.TextSize = ts or 11
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.ClearTextOnFocus = false
        b.Parent = snAutoPanel
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 8) pad.Parent = b
        return b
    end

    -- v8.90: Remove Mutasi field, Pet Type jadi picker button (no overlay, inside Otomatis panel only)
    -- Row 1 (y=0): Pet Type btn (45%) | Max KG (25%) | Max Price (30%)

    -- Pet Type as button (opens inline picker)
    local petTypeBtn = Instance.new("TextButton")
    petTypeBtn.Size = UDim2.new(0.45, -3, 0, 26)
    petTypeBtn.Position = UDim2.new(0, 0, 0, 0)
    petTypeBtn.BackgroundColor3 = C.input
    petTypeBtn.BorderSizePixel = 0
    petTypeBtn.Text = "🐾 Tap to pick" petTypeBtn.TextColor3 = C.textDim
    petTypeBtn.Font = F petTypeBtn.TextSize = 11
    petTypeBtn.TextXAlignment = Enum.TextXAlignment.Left
    petTypeBtn.AutoButtonColor = false
    petTypeBtn.Parent = snAutoPanel
    Instance.new("UICorner", petTypeBtn).CornerRadius = UDim.new(0, 5)
    local petTypePad = Instance.new("UIPadding")
    petTypePad.PaddingLeft = UDim.new(0, 8) petTypePad.PaddingRight = UDim.new(0, 8)
    petTypePad.Parent = petTypeBtn

    BH.autoSnipe.typeInput = petTypeBtn
    BH.autoSnipe.pickedPetType = ""
    BH.autoSnipe.selectedTypes = BH.autoSnipe.selectedTypes or {}  -- v8.127: multi-select set
    local function setPetType(val)
        BH.autoSnipe.pickedPetType = val or ""
        if val and val ~= "" then
            petTypeBtn.Text = val
            petTypeBtn.TextColor3 = C.text
        else
            petTypeBtn.Text = "🐾 Tap to pick"
            petTypeBtn.TextColor3 = C.textDim
        end
    end
    BH.autoSnipe.setPetType = setPetType
    -- v8.127: update label based on multi-select state
    local function updateSnipeLabel()
        local cnt = 0
        local first = nil
        for k in pairs(BH.autoSnipe.selectedTypes) do
            cnt = cnt + 1
            if not first then first = k end
        end
        if cnt == 0 then
            petTypeBtn.Text = "🐾 Tap to pick"
            petTypeBtn.TextColor3 = C.textDim
            BH.autoSnipe.pickedPetType = ""
        elseif cnt == 1 then
            petTypeBtn.Text = first
            petTypeBtn.TextColor3 = C.text
            BH.autoSnipe.pickedPetType = first
        else
            petTypeBtn.Text = first.." +"..(cnt-1)
            petTypeBtn.TextColor3 = C.text
            BH.autoSnipe.pickedPetType = first
        end
    end
    BH.autoSnipe.updateLabel = updateSnipeLabel

    BH.autoSnipe.minKgInput = makeAutoInput(0.45, 0.13, "Min KG")
    BH.autoSnipe.kgInput = makeAutoInput(0.58, 0.13, "Max KG")
    BH.autoSnipe.priceInput = makeAutoInput(0.71, 0.29, "💰 Max Price")
    BH.autoSnipe.minKgInput.TextXAlignment = Enum.TextXAlignment.Center
    BH.autoSnipe.kgInput.TextXAlignment = Enum.TextXAlignment.Center
    BH.autoSnipe.priceInput.TextXAlignment = Enum.TextXAlignment.Center

    -- Pet picker (overlay HANYA di dalam snAutoPanel, gak interfere tab lain)
    local petPicker = Instance.new("Frame")
    petPicker.Size = UDim2.new(1, 0, 1, -88)
    petPicker.Position = UDim2.new(0, 0, 0, 84)
    petPicker.BackgroundColor3 = C.card
    petPicker.BorderSizePixel = 0
    petPicker.Visible = false
    petPicker.ZIndex = 50
    petPicker.Parent = snAutoPanel
    Instance.new("UICorner", petPicker).CornerRadius = UDim.new(0, 6)
    local pickerStroke = Instance.new("UIStroke")
    pickerStroke.Color = C.accent pickerStroke.Thickness = 1
    pickerStroke.Parent = petPicker

    local pickerHeader = Instance.new("TextLabel")
    pickerHeader.Size = UDim2.new(1, -36, 0, 24)
    pickerHeader.Position = UDim2.new(0, 8, 0, 4)
    pickerHeader.BackgroundTransparency = 1
    pickerHeader.Text = "🐾 Pilih Pet Type"
    pickerHeader.TextColor3 = C.accent
    pickerHeader.Font = FB pickerHeader.TextSize = 12
    pickerHeader.TextXAlignment = Enum.TextXAlignment.Left
    pickerHeader.ZIndex = 51 pickerHeader.Parent = petPicker

    -- v8.127: DONE button (multi-select)
    local pickerDoneBtn = Instance.new("TextButton")
    pickerDoneBtn.Size = UDim2.new(0, 60, 0, 24)
    pickerDoneBtn.Position = UDim2.new(1, -94, 0, 4)
    pickerDoneBtn.BackgroundColor3 = C.accent
    pickerDoneBtn.Text = "✓ DONE" pickerDoneBtn.TextColor3 = Color3.new(0, 0, 0)
    pickerDoneBtn.Font = FB pickerDoneBtn.TextSize = 10
    pickerDoneBtn.BorderSizePixel = 0
    pickerDoneBtn.ZIndex = 51 pickerDoneBtn.Parent = petPicker
    Instance.new("UICorner", pickerDoneBtn).CornerRadius = UDim.new(0, 4)
    pickerDoneBtn.MouseButton1Click:Connect(function()
        petPicker.Visible = false
    end)

    local pickerCloseBtn = Instance.new("TextButton")
    pickerCloseBtn.Size = UDim2.new(0, 24, 0, 24)
    pickerCloseBtn.Position = UDim2.new(1, -28, 0, 4)
    pickerCloseBtn.BackgroundColor3 = C.danger
    pickerCloseBtn.Text = "✕" pickerCloseBtn.TextColor3 = Color3.new(1,1,1)
    pickerCloseBtn.Font = FB pickerCloseBtn.TextSize = 11
    pickerCloseBtn.BorderSizePixel = 0
    pickerCloseBtn.ZIndex = 51 pickerCloseBtn.Parent = petPicker
    Instance.new("UICorner", pickerCloseBtn).CornerRadius = UDim.new(0, 4)
    pickerCloseBtn.MouseButton1Click:Connect(function()
        petPicker.Visible = false
    end)

    -- v8.92: Search box (essential untuk ~400 pets)
    local pickerSearch = Instance.new("TextBox")
    pickerSearch.Size = UDim2.new(1, -16, 0, 24)
    pickerSearch.Position = UDim2.new(0, 8, 0, 32)
    pickerSearch.BackgroundColor3 = C.input
    pickerSearch.Text = ""
    pickerSearch.PlaceholderText = "🔍 Search pet name..."
    pickerSearch.PlaceholderColor3 = C.textDim
    pickerSearch.TextColor3 = C.text
    pickerSearch.Font = F pickerSearch.TextSize = 11
    pickerSearch.TextXAlignment = Enum.TextXAlignment.Left
    pickerSearch.BorderSizePixel = 0
    pickerSearch.ClearTextOnFocus = false
    pickerSearch.ZIndex = 51 pickerSearch.Parent = petPicker
    Instance.new("UICorner", pickerSearch).CornerRadius = UDim.new(0, 4)
    local searchPad = Instance.new("UIPadding")
    searchPad.PaddingLeft = UDim.new(0, 8) searchPad.PaddingRight = UDim.new(0, 8)
    searchPad.Parent = pickerSearch

    local pickerScroll = Instance.new("ScrollingFrame")
    pickerScroll.Size = UDim2.new(1, -8, 1, -64)
    pickerScroll.Position = UDim2.new(0, 4, 0, 60)
    pickerScroll.BackgroundTransparency = 1
    pickerScroll.BorderSizePixel = 0
    pickerScroll.ScrollBarThickness = 4
    pickerScroll.ScrollBarImageColor3 = C.accent
    pickerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    pickerScroll.ZIndex = 51
    pickerScroll.Parent = petPicker
    local pickerLayout = Instance.new("UIListLayout")
    pickerLayout.Padding = UDim.new(0, 3)
    pickerLayout.Parent = pickerScroll

    local function populatePicker(filter)
        for _, c in ipairs(pickerScroll:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
        end
        filter = filter and filter:lower() or ""

        local seen = {}
        -- v8.92: Primary — pet types yang ke-discover dari game (~400 pets)
        if BH.PET_NAMES_DISCOVERED then
            for _, name in ipairs(BH.PET_NAMES_DISCOVERED) do
                seen[name] = true
            end
        end
        -- Fallback — hardcoded BH.PET_NAMES (~100 pets)
        if BH.PET_NAMES then
            for _, name in ipairs(BH.PET_NAMES) do
                seen[name] = true
            end
        end
        -- Tambahin dari backpack (pet baru / event yang gak ada di list)
        local bp = player and player:FindFirstChild("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and (t:FindFirstChild("PetToolLocal") or t:GetAttribute("PET_UUID")) then
                    local pType = tostring(t:GetAttribute("f") or "")
                    if pType ~= "" and pType ~= "?" then
                        local base = (BH.getBaseName and pType ~= "") and BH.getBaseName(pType) or pType
                        seen[base] = true
                    end
                end
            end
        end
        -- Tambahin dari TBC items (pet di booth lain)
        if BH.TBC then
            for _, pp in ipairs(Players:GetPlayers()) do
                local data = BH.fetchBoothData and BH.fetchBoothData(pp)
                if data and data.Items then
                    for _, item in pairs(data.Items) do
                        if item.PetType then
                            local base = (BH.getBaseName) and BH.getBaseName(tostring(item.PetType)) or tostring(item.PetType)
                            seen[base] = true
                        end
                    end
                end
            end
        end

        local list = {}
        for k in pairs(seen) do
            if filter == "" or k:lower():find(filter, 1, true) then
                table.insert(list, k)
            end
        end
        table.sort(list)

        for _, name in ipairs(list) do
            local sel = BH.autoSnipe.selectedTypes[name] == true
            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1, -8, 0, 26)
            row.BackgroundColor3 = sel and C.accent or C.input
            row.Text = (sel and "✓ " or "  ")..name
            row.TextColor3 = sel and Color3.new(0,0,0) or C.text
            row.Font = sel and FB or F
            row.TextSize = 11
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.BorderSizePixel = 0
            row.ZIndex = 52 row.Parent = pickerScroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
            row.MouseButton1Click:Connect(function()
                if BH.autoSnipe.selectedTypes[name] then
                    BH.autoSnipe.selectedTypes[name] = nil
                else
                    BH.autoSnipe.selectedTypes[name] = true
                end
                updateSnipeLabel()
                populatePicker(pickerSearch.Text)
            end)
        end

        -- Show stat: how many found
        local statLbl = Instance.new("TextLabel")
        statLbl.Size = UDim2.new(1, -8, 0, 20)
        statLbl.BackgroundTransparency = 1
        statLbl.Text = filter == "" and ("Total: "..#list.." pet types") or ("Match: "..#list.." pet")
        statLbl.TextColor3 = C.textDim
        statLbl.Font = F statLbl.TextSize = 10
        statLbl.TextXAlignment = Enum.TextXAlignment.Right
        statLbl.LayoutOrder = -1  -- prepend
        statLbl.ZIndex = 52 statLbl.Parent = pickerScroll

        pickerScroll.CanvasSize = UDim2.new(0, 0, 0, pickerLayout.AbsoluteContentSize.Y + 8)
    end

    -- Search filter live
    pickerSearch:GetPropertyChangedSignal("Text"):Connect(function()
        populatePicker(pickerSearch.Text)
    end)

    petTypeBtn.MouseButton1Click:Connect(function()
        pickerSearch.Text = ""
        populatePicker("")
        petPicker.Visible = true
    end)

    -- Row 2 (y=30): + ADD RULE (40%) | START/STOP (60%)
    BH.autoSnipe.addBtn = btnOf(snAutoPanel, 0, 0, 1, 1, "+ ADD RULE", C.accent)
    BH.autoSnipe.addBtn.Size = UDim2.new(0.4, -3, 0, 26)
    BH.autoSnipe.addBtn.Position = UDim2.new(0, 0, 0, 30)
    BH.autoSnipe.addBtn.TextSize = 11

    BH.autoSnipe.toggleBtn = btnOf(snAutoPanel, 0, 0, 1, 1, "▶ START AUTO-BUY", C.success)
    BH.autoSnipe.toggleBtn.Size = UDim2.new(0.6, 0, 0, 26)
    BH.autoSnipe.toggleBtn.Position = UDim2.new(0.4, 3, 0, 30)
    BH.autoSnipe.toggleBtn.TextSize = 11

    -- v8.258: Row 3 (y=62): filter asal egg (Semua/Prem/Biasa)
    BH.autoSnipe.eggBtn = btnOf(snAutoPanel, 0, 0, 1, 1, "🥚 Egg: Semua", C.card, C.text)
    BH.autoSnipe.eggBtn.Size = UDim2.new(1, 0, 0, 24)
    BH.autoSnipe.eggBtn.Position = UDim2.new(0, 0, 0, 62)
    BH.autoSnipe.eggBtn.TextSize = 11
    local function eggLabel()
        local es = BH.autoSnipe.eggSource or "all"
        return es == "prem" and "🥚 Egg: Prem only"
            or es == "biasa" and "🥚 Egg: Biasa only"
            or "🥚 Egg: Semua"
    end
    BH.autoSnipe.eggBtn.Text = eggLabel()
    BH.autoSnipe.eggBtn.MouseButton1Click:Connect(function()
        local es = BH.autoSnipe.eggSource or "all"
        es = (es == "all") and "prem" or (es == "prem") and "biasa" or "all"
        BH.autoSnipe.eggSource = es
        BH.autoSnipe.eggBtn.Text = eggLabel()
        if BH.marketState then BH.marketState.autoSnipeEggSource = es; BH.saveMarketState(BH.marketState) end
        L("[AutoSnipe] filter egg: "..es)
    end)

    -- Row 4 (y=90): status label
    BH.autoSnipe.statusLbl = Instance.new("TextLabel")
    BH.autoSnipe.statusLbl.Size = UDim2.new(1, 0, 0, 18)
    BH.autoSnipe.statusLbl.Position = UDim2.new(0, 0, 0, 90)
    BH.autoSnipe.statusLbl.BackgroundTransparency = 1
    BH.autoSnipe.statusLbl.Text = "Idle — tambah rule lalu klik START"
    BH.autoSnipe.statusLbl.TextColor3 = C.textDim
    BH.autoSnipe.statusLbl.Font = FM
    BH.autoSnipe.statusLbl.TextSize = 10
    BH.autoSnipe.statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    BH.autoSnipe.statusLbl.Parent = snAutoPanel

    -- Row 5 (y=112 → bottom): Rules list scroll
    BH.autoSnipe.scroll = Instance.new("ScrollingFrame")
    BH.autoSnipe.scroll.Size = UDim2.new(1, 0, 1, -116)
    BH.autoSnipe.scroll.Position = UDim2.new(0, 0, 0, 112)
    BH.autoSnipe.scroll.BackgroundColor3 = C.card
    BH.autoSnipe.scroll.BorderSizePixel = 0
    BH.autoSnipe.scroll.ScrollBarThickness = 4
    BH.autoSnipe.scroll.ScrollBarImageColor3 = C.accent
    BH.autoSnipe.scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    BH.autoSnipe.scroll.Parent = snAutoPanel
    Instance.new("UICorner", BH.autoSnipe.scroll).CornerRadius = UDim.new(0, 6)
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3) layout.Parent = BH.autoSnipe.scroll
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4) pad.PaddingLeft = UDim.new(0, 4) pad.PaddingRight = UDim.new(0, 4)
    pad.Parent = BH.autoSnipe.scroll
    BH.autoSnipe.layout = layout

    -- Rebuild rules UI
    BH.autoSnipe.rebuildRules = function()
        for _, c in ipairs(BH.autoSnipe.scroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        for idx, r in ipairs(BH.autoSnipe.rules) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -8, 0, 28)
            row.BackgroundColor3 = C.input row.BorderSizePixel = 0
            row.Parent = BH.autoSnipe.scroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

            local info = Instance.new("TextLabel")
            info.Size = UDim2.new(1, -110, 1, 0) info.Position = UDim2.new(0, 8, 0, 0)
            info.BackgroundTransparency = 1
            local mutStr = (r.mutation and r.mutation ~= "") and (" ["..r.mutation.."]") or ""
            local kgStr = ""
            if r.minKg and r.minKg > 0 then kgStr = kgStr.." ≥"..r.minKg.."kg" end
            if r.maxKg and r.maxKg > 0 then kgStr = kgStr.." ≤"..r.maxKg.."kg" end
            local typeStr = (r.petType and r.petType ~= "") and r.petType or "any"
            info.Text = string.format("<b>%s</b>%s%s • <font color='#FFD700'>≤%s</font>",
                typeStr, mutStr, kgStr, tostring(r.maxPrice))
            info.RichText = true
            info.TextColor3 = C.text info.Font = FM info.TextSize = 11
            info.TextXAlignment = Enum.TextXAlignment.Left
            info.TextTruncate = Enum.TextTruncate.AtEnd
            info.Parent = row

            -- v8.302: tombol egg PER-RULE (override global). siklus: ikut > prem > biasa > semua > ikut
            local eggRuleBtn = Instance.new("TextButton")
            eggRuleBtn.Size = UDim2.new(0, 46, 0, 22)
            eggRuleBtn.Position = UDim2.new(1, -104, 0.5, -11)
            eggRuleBtn.BackgroundColor3 = C.card
            eggRuleBtn.TextColor3 = C.text eggRuleBtn.Font = FM eggRuleBtn.TextSize = 9
            eggRuleBtn.BorderSizePixel = 0 eggRuleBtn.Parent = row
            Instance.new("UICorner", eggRuleBtn).CornerRadius = UDim.new(0, 4)
            local function eggRuleLabel()
                local rs = BH.autoSnipe.rules[idx] and BH.autoSnipe.rules[idx].eggSource
                if rs == "prem" then return "prem" end
                if rs == "biasa" then return "biasa" end
                if rs == "all" then return "semua" end
                return "ikut"
            end
            local function eggRuleColor()
                local rs = BH.autoSnipe.rules[idx] and BH.autoSnipe.rules[idx].eggSource
                eggRuleBtn.TextColor3 = rs and C.accent or C.textDim
            end
            eggRuleBtn.Text = eggRuleLabel()
            eggRuleColor()
            eggRuleBtn.MouseButton1Click:Connect(function()
                if not BH.autoSnipe.rules[idx] then return end
                local rs = BH.autoSnipe.rules[idx].eggSource
                if rs == nil then rs = "prem"
                elseif rs == "prem" then rs = "biasa"
                elseif rs == "biasa" then rs = "all"
                else rs = nil end
                BH.autoSnipe.rules[idx].eggSource = rs
                eggRuleBtn.Text = eggRuleLabel()
                eggRuleColor()
                if BH.marketState then
                    BH.marketState.autoSnipeRules = BH.autoSnipe.rules
                    pcall(function() BH.saveMarketState(BH.marketState) end)
                end
            end)

            -- v8.127: EDIT button
            local editBtn = Instance.new("TextButton")
            editBtn.Size = UDim2.new(0, 24, 0, 22)
            editBtn.Position = UDim2.new(1, -54, 0.5, -11)
            editBtn.BackgroundColor3 = C.accent
            editBtn.Text = "✏️" editBtn.TextColor3 = Color3.new(0,0,0)
            editBtn.Font = FB editBtn.TextSize = 10
            editBtn.BorderSizePixel = 0 editBtn.Parent = row
            Instance.new("UICorner", editBtn).CornerRadius = UDim.new(0, 4)
            editBtn.MouseButton1Click:Connect(function()
                -- Inline edit: replace info with input boxes
                info.Visible = false
                editBtn.Visible = false

                -- v8.236: 4 inputs in edit row — petType, minKg, maxKg, price
                local function mkEdit(x, w, txt, ph)
                    local e = Instance.new("TextBox")
                    e.Size = UDim2.new(0, w, 0, 22)
                    e.Position = UDim2.new(0, x, 0.5, -11)
                    e.BackgroundColor3 = C.card
                    e.Text = tostring(txt or "")
                    e.PlaceholderText = ph
                    e.PlaceholderColor3 = C.textDim
                    e.TextColor3 = C.text e.Font = F e.TextSize = 10
                    e.ClearTextOnFocus = false e.BorderSizePixel = 0
                    e.TextXAlignment = Enum.TextXAlignment.Center
                    e.Parent = row
                    Instance.new("UICorner", e).CornerRadius = UDim.new(0, 4)
                    return e
                end

                local typeEdit  = mkEdit(8,   70, r.petType or "", "type")
                local minKgEdit = mkEdit(82,  40, (r.minKg and r.minKg > 0) and r.minKg or "", "min")
                local maxKgEdit = mkEdit(126, 40, (r.maxKg and r.maxKg > 0) and r.maxKg or "", "max")
                local priceEdit = mkEdit(170, 55, r.maxPrice or 0, "price")

                local okBtn = Instance.new("TextButton")
                okBtn.Size = UDim2.new(0, 24, 0, 22)
                okBtn.Position = UDim2.new(1, -54, 0.5, -11)
                okBtn.BackgroundColor3 = C.success
                okBtn.Text = "✓" okBtn.TextColor3 = Color3.new(0,0,0)
                okBtn.Font = FB okBtn.TextSize = 12
                okBtn.BorderSizePixel = 0 okBtn.Parent = row
                Instance.new("UICorner", okBtn).CornerRadius = UDim.new(0, 4)
                okBtn.MouseButton1Click:Connect(function()
                    local newType = typeEdit.Text
                    local newMin = tonumber(minKgEdit.Text) or 0
                    local newMax = tonumber(maxKgEdit.Text) or 0
                    local newPrice = tonumber(priceEdit.Text) or r.maxPrice
                    BH.autoSnipe.rules[idx].petType = newType
                    BH.autoSnipe.rules[idx].minKg = newMin
                    BH.autoSnipe.rules[idx].maxKg = newMax
                    BH.autoSnipe.rules[idx].maxPrice = newPrice
                    if BH.marketState then
                        BH.marketState.autoSnipeRules = BH.autoSnipe.rules
                        pcall(function() BH.saveMarketState(BH.marketState) end)
                    end
                    BH.autoSnipe.rebuildRules()
                end)
            end)

            local delBtn = Instance.new("TextButton")
            delBtn.Size = UDim2.new(0, 24, 0, 22)
            delBtn.Position = UDim2.new(1, -28, 0.5, -11)
            delBtn.BackgroundColor3 = C.danger
            delBtn.Text = "✕" delBtn.TextColor3 = Color3.new(1,1,1)
            delBtn.Font = FB delBtn.TextSize = 10
            delBtn.BorderSizePixel = 0 delBtn.Parent = row
            Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 4)
            delBtn.MouseButton1Click:Connect(function()
                table.remove(BH.autoSnipe.rules, idx)
                BH.autoSnipe.rebuildRules()
                if BH.marketState then
                    BH.marketState.autoSnipeRules = BH.autoSnipe.rules
                    pcall(function() BH.saveMarketState(BH.marketState) end)
                end
            end)
        end
        BH.autoSnipe.scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    end -- end BH.autoSnipe.rebuildRules

    -- Add rule handler — v8.127: multi-pet loop
    BH.autoSnipe.addBtn.MouseButton1Click:Connect(function()
        local maxPrice = tonumber(BH.autoSnipe.priceInput.Text)
        if not maxPrice or maxPrice <= 0 then
            BH.autoSnipe.statusLbl.Text = "❌ Max Price wajib diisi (angka > 0)"
            BH.autoSnipe.statusLbl.TextColor3 = C.danger
            return
        end
        -- Gather selected pet types
        local picked = {}
        for k in pairs(BH.autoSnipe.selectedTypes) do table.insert(picked, k) end
        if #picked == 0 then
            -- Fallback: kalo gak ada selection tapi single pickedPetType kosong → wajib pilih
            if not BH.autoSnipe.pickedPetType or BH.autoSnipe.pickedPetType == "" then
                BH.autoSnipe.statusLbl.Text = "❌ Pilih pet type dulu"
                BH.autoSnipe.statusLbl.TextColor3 = C.danger
                return
            end
            picked = {BH.autoSnipe.pickedPetType}
        end
        table.sort(picked)
        local maxKg = tonumber(BH.autoSnipe.kgInput.Text) or 0
        local minKg = tonumber(BH.autoSnipe.minKgInput.Text) or 0
        for _, petName in ipairs(picked) do
            table.insert(BH.autoSnipe.rules, {
                petType = petName,
                mutation = "",
                minKg = minKg,
                maxKg = maxKg,
                maxPrice = maxPrice,
            })
        end
        BH.autoSnipe.selectedTypes = {}
        BH.autoSnipe.setPetType("")
        BH.autoSnipe.minKgInput.Text = ""
        BH.autoSnipe.kgInput.Text = ""
        BH.autoSnipe.priceInput.Text = ""
        BH.autoSnipe.rebuildRules()
        if BH.marketState then
            BH.marketState.autoSnipeRules = BH.autoSnipe.rules
            pcall(function() BH.saveMarketState(BH.marketState) end)
        end
        BH.autoSnipe.statusLbl.Text = "✅ Added "..#picked.." rule(s) ("..#BH.autoSnipe.rules.." total)"
        BH.autoSnipe.statusLbl.TextColor3 = C.success
    end)

    -- Toggle handler
    BH.autoSnipe.toggleBtn.MouseButton1Click:Connect(function()
        BH.autoSnipe.active = not BH.autoSnipe.active
        if BH.autoSnipe.active then
            if #BH.autoSnipe.rules == 0 then
                BH.autoSnipe.statusLbl.Text = "❌ Tambah rule dulu sebelum START"
                BH.autoSnipe.statusLbl.TextColor3 = C.danger
                BH.autoSnipe.active = false
                return
            end
            BH.autoSnipe.toggleBtn.Text = "⛔ STOP AUTO-BUY"
            BH.autoSnipe.toggleBtn.BackgroundColor3 = C.danger
            BH.autoSnipe.statusLbl.Text = "🎯 Active — scanning..."
            BH.autoSnipe.statusLbl.TextColor3 = C.accent
            L("[AutoSnipe] START dengan "..#BH.autoSnipe.rules.." rule(s)")
        else
            BH.autoSnipe.toggleBtn.Text = "▶ START AUTO-BUY"
            BH.autoSnipe.toggleBtn.BackgroundColor3 = C.success
            BH.autoSnipe.statusLbl.Text = "⛔ Stopped. Bought "..BH.autoSnipe.boughtCount.." pet"
            BH.autoSnipe.statusLbl.TextColor3 = C.textDim
            L("[AutoSnipe] STOPPED. Total bought: "..BH.autoSnipe.boughtCount)
        end
        -- v8.94: persist active state biar survive rejoin
        if BH.marketState then
            BH.marketState.autoSnipeActive = BH.autoSnipe.active
            pcall(function() BH.saveMarketState(BH.marketState) end)
        end
    end)

    -- v8.94: Restore active state setelah rejoin
    if BH.marketState and BH.marketState.autoSnipeActive and #BH.autoSnipe.rules > 0 then
        BH.autoSnipe.active = true
        BH.autoSnipe.toggleBtn.Text = "⛔ STOP AUTO-BUY"
        BH.autoSnipe.toggleBtn.BackgroundColor3 = C.danger
        BH.autoSnipe.statusLbl.Text = "🎯 Auto-resumed setelah rejoin — scanning..."
        BH.autoSnipe.statusLbl.TextColor3 = C.accent
        L("[AutoSnipe] AUTO-RESUMED setelah rejoin dengan "..#BH.autoSnipe.rules.." rule(s)")
    end

    BH.autoSnipe.rebuildRules()
end

-- v8.96: ===== SNIPE HISTORY TAB =====
-- Daftar pet yang berhasil di-snipe sama Auto Snipe (persist setelah rejoin)
BH.autoSnipe.history = BH.autoSnipe.history or {}
-- Restore history from state
if BH.marketState and BH.marketState.autoSnipeHistory then
    BH.autoSnipe.history = BH.marketState.autoSnipeHistory
end

do
    local histPad = Instance.new("UIPadding")
    histPad.PaddingTop = UDim.new(0, 10) histPad.PaddingLeft = UDim.new(0, 12)
    histPad.PaddingRight = UDim.new(0, 12) histPad.PaddingBottom = UDim.new(0, 10)
    histPad.Parent = snHistoryPanel

    -- Header card (count + clear button)
    local histHdr = Instance.new("Frame")
    histHdr.Size = UDim2.new(1, 0, 0, 26)
    histHdr.Position = UDim2.new(0, 0, 0, 0)
    histHdr.BackgroundTransparency = 1
    histHdr.Parent = snHistoryPanel

    local histCountLbl = Instance.new("TextLabel")
    histCountLbl.Size = UDim2.new(0.7, 0, 1, 0)
    histCountLbl.BackgroundTransparency = 1
    histCountLbl.Text = "0 pet sniped"
    histCountLbl.TextColor3 = C.accent
    histCountLbl.Font = FB
    histCountLbl.TextSize = 13
    histCountLbl.TextXAlignment = Enum.TextXAlignment.Left
    histCountLbl.Parent = histHdr

    local histClearBtn = Instance.new("TextButton")
    histClearBtn.Size = UDim2.new(0.3, -3, 1, 0)
    histClearBtn.Position = UDim2.new(0.7, 3, 0, 0)
    histClearBtn.BackgroundColor3 = C.danger
    histClearBtn.Text = "🗑 CLEAR"
    histClearBtn.TextColor3 = Color3.new(1, 1, 1)
    histClearBtn.Font = FB
    histClearBtn.TextSize = 11
    histClearBtn.BorderSizePixel = 0
    histClearBtn.Parent = histHdr
    Instance.new("UICorner", histClearBtn).CornerRadius = UDim.new(0, 5)

    -- Scroll list
    local histScroll = Instance.new("ScrollingFrame")
    histScroll.Size = UDim2.new(1, 0, 1, -32)
    histScroll.Position = UDim2.new(0, 0, 0, 32)
    histScroll.BackgroundColor3 = C.card
    histScroll.BorderSizePixel = 0
    histScroll.ScrollBarThickness = 4
    histScroll.ScrollBarImageColor3 = C.accent
    histScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    histScroll.Parent = snHistoryPanel
    Instance.new("UICorner", histScroll).CornerRadius = UDim.new(0, 6)
    local histLayout = Instance.new("UIListLayout")
    histLayout.Padding = UDim.new(0, 3)
    histLayout.Parent = histScroll
    local histScrollPad = Instance.new("UIPadding")
    histScrollPad.PaddingTop = UDim.new(0, 4) histScrollPad.PaddingLeft = UDim.new(0, 4)
    histScrollPad.PaddingRight = UDim.new(0, 4) histScrollPad.Parent = histScroll

    -- Helper: format relative time
    local function fmtTime(ts)
        if not ts then return "?" end
        local elapsed = os.time() - ts
        if elapsed < 60 then return elapsed.."s ago" end
        if elapsed < 3600 then return math.floor(elapsed / 60).."m ago" end
        if elapsed < 86400 then return math.floor(elapsed / 3600).."h ago" end
        return math.floor(elapsed / 86400).."d ago"
    end

    local function rebuildHistory()
        for _, c in ipairs(histScroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        histCountLbl.Text = #BH.autoSnipe.history.." pet sniped"
        if #BH.autoSnipe.history == 0 then
            local emptyLbl = Instance.new("TextLabel")
            emptyLbl.Size = UDim2.new(1, -8, 0, 40)
            emptyLbl.BackgroundTransparency = 1
            emptyLbl.Text = "📭 belum ada pet yang ke-snipe"
            emptyLbl.TextColor3 = C.textDim
            emptyLbl.Font = F emptyLbl.TextSize = 12
            emptyLbl.TextXAlignment = Enum.TextXAlignment.Center
            emptyLbl.Parent = histScroll
            histScroll.CanvasSize = UDim2.new(0, 0, 0, 40)
            return
        end
        for _, entry in ipairs(BH.autoSnipe.history) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -8, 0, 30)
            row.BackgroundColor3 = C.input
            row.BorderSizePixel = 0
            row.Parent = histScroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

            local info = Instance.new("TextLabel")
            info.Size = UDim2.new(0.7, -4, 1, 0)
            info.Position = UDim2.new(0, 8, 0, 0)
            info.BackgroundTransparency = 1
            local mutStr = (entry.mutation and entry.mutation ~= "-" and entry.mutation ~= "")
                and (" ["..entry.mutation.."]") or ""
            -- v8.268: nama MERAH kalau prem, PUTIH kalau biasa
            local nameHex = entry.isPrem and "#FF5050" or "#FFFFFF"
            -- v8.271: tampilkan egg asal
            local eggStr = entry.eggName and (" • <font color='#88CCFF'>"..entry.eggName.."</font>") or ""
            info.Text = string.format("<b><font color='%s'>%s</font></b>%s • <font color='#FFD700'>%s</font> • by %s%s",
                nameHex, entry.petType or "?", mutStr, tostring(entry.price or 0), entry.seller or "?", eggStr)
            info.RichText = true
            info.TextColor3 = C.text
            info.Font = F info.TextSize = 11
            info.TextXAlignment = Enum.TextXAlignment.Left
            info.TextTruncate = Enum.TextTruncate.AtEnd
            info.Parent = row

            local timeLbl = Instance.new("TextLabel")
            timeLbl.Size = UDim2.new(0.3, -8, 1, 0)
            timeLbl.Position = UDim2.new(0.7, 0, 0, 0)
            timeLbl.BackgroundTransparency = 1
            timeLbl.Text = fmtTime(entry.ts)
            timeLbl.TextColor3 = C.textDim
            timeLbl.Font = F timeLbl.TextSize = 10
            timeLbl.TextXAlignment = Enum.TextXAlignment.Right
            timeLbl.Parent = row
        end
        histScroll.CanvasSize = UDim2.new(0, 0, 0, histLayout.AbsoluteContentSize.Y + 12)
    end
    BH.autoSnipe.rebuildHistory = rebuildHistory

    -- Clear button
    histClearBtn.MouseButton1Click:Connect(function()
        BH.autoSnipe.history = {}
        if BH.marketState then
            BH.marketState.autoSnipeHistory = {}
            pcall(function() BH.saveMarketState(BH.marketState) end)
        end
        rebuildHistory()
    end)

    -- Refresh saat tab dibuka (refresh fmtTime)
    if BH.snSubBtns.History and BH.snSubBtns.History.btn then
        BH.snSubBtns.History.btn.MouseButton1Click:Connect(function()
            task.spawn(function() task.wait(0.05); rebuildHistory() end)
        end)
    end

    -- Initial build
    rebuildHistory()
end

-- v8.75: ===== SERVER HUNTER TAB (gantiin Buy yang mubazir) =====
-- Auto-hop ke server lain sampe nemu pet sesuai kriteria
BH.snBuy = {}
BH.hunt = BH.hunt or {active = false, scanned = 0}
do
    local snBuyPad = Instance.new("UIPadding")
    snBuyPad.PaddingTop = UDim.new(0, 10) snBuyPad.PaddingLeft = UDim.new(0, 12)
    snBuyPad.PaddingRight = UDim.new(0, 12) snBuyPad.PaddingBottom = UDim.new(0, 10)
    snBuyPad.Parent = snBuyPanel

    -- Row 1 (y=0): Pet Type (60%) | Mutation (38%)
    BH.snBuy.search = Instance.new("TextBox")
    BH.snBuy.search.Size = UDim2.new(0.6, -3, 0, 26) BH.snBuy.search.Position = UDim2.new(0, 0, 0, 0)
    BH.snBuy.search.BackgroundColor3 = C.input BH.snBuy.search.BorderSizePixel = 0
    BH.snBuy.search.Text = "" BH.snBuy.search.TextColor3 = C.text
    BH.snBuy.search.PlaceholderText = "🐾 Pet type (Peacock, Giraffe, ...)"
    BH.snBuy.search.PlaceholderColor3 = C.textDim
    BH.snBuy.search.Font = F BH.snBuy.search.TextSize = 11
    BH.snBuy.search.ClearTextOnFocus = false BH.snBuy.search.Parent = snBuyPanel
    Instance.new("UICorner", BH.snBuy.search).CornerRadius = UDim.new(0, 5)
    local p1 = Instance.new("UIPadding") p1.PaddingLeft = UDim.new(0, 8) p1.Parent = BH.snBuy.search

    BH.snBuy.mutation = Instance.new("TextBox")
    BH.snBuy.mutation.Size = UDim2.new(0.4, -3, 0, 26) BH.snBuy.mutation.Position = UDim2.new(0.6, 3, 0, 0)
    BH.snBuy.mutation.BackgroundColor3 = C.input BH.snBuy.mutation.BorderSizePixel = 0
    BH.snBuy.mutation.Text = "" BH.snBuy.mutation.TextColor3 = C.text
    BH.snBuy.mutation.PlaceholderText = "✨ Mutation (opt)"
    BH.snBuy.mutation.PlaceholderColor3 = C.textDim
    BH.snBuy.mutation.Font = F BH.snBuy.mutation.TextSize = 11
    BH.snBuy.mutation.ClearTextOnFocus = false BH.snBuy.mutation.Parent = snBuyPanel
    Instance.new("UICorner", BH.snBuy.mutation).CornerRadius = UDim.new(0, 5)
    local p2 = Instance.new("UIPadding") p2.PaddingLeft = UDim.new(0, 8) p2.Parent = BH.snBuy.mutation

    -- Row 2 (y=30): Min KG | Max KG | Max Price
    BH.snBuy.minKg = Instance.new("TextBox")
    BH.snBuy.minKg.Size = UDim2.new(0.25, -3, 0, 26) BH.snBuy.minKg.Position = UDim2.new(0, 0, 0, 30)
    BH.snBuy.minKg.BackgroundColor3 = C.input BH.snBuy.minKg.BorderSizePixel = 0
    BH.snBuy.minKg.Text = "" BH.snBuy.minKg.TextColor3 = C.text
    BH.snBuy.minKg.PlaceholderText = "Min KG"
    BH.snBuy.minKg.PlaceholderColor3 = C.textDim
    BH.snBuy.minKg.Font = F BH.snBuy.minKg.TextSize = 11
    BH.snBuy.minKg.TextXAlignment = Enum.TextXAlignment.Center
    BH.snBuy.minKg.ClearTextOnFocus = false BH.snBuy.minKg.Parent = snBuyPanel
    Instance.new("UICorner", BH.snBuy.minKg).CornerRadius = UDim.new(0, 5)

    BH.snBuy.maxKg = Instance.new("TextBox")
    BH.snBuy.maxKg.Size = UDim2.new(0.25, -3, 0, 26) BH.snBuy.maxKg.Position = UDim2.new(0.25, 3, 0, 30)
    BH.snBuy.maxKg.BackgroundColor3 = C.input BH.snBuy.maxKg.BorderSizePixel = 0
    BH.snBuy.maxKg.Text = "" BH.snBuy.maxKg.TextColor3 = C.text
    BH.snBuy.maxKg.PlaceholderText = "Max KG"
    BH.snBuy.maxKg.PlaceholderColor3 = C.textDim
    BH.snBuy.maxKg.Font = F BH.snBuy.maxKg.TextSize = 11
    BH.snBuy.maxKg.TextXAlignment = Enum.TextXAlignment.Center
    BH.snBuy.maxKg.ClearTextOnFocus = false BH.snBuy.maxKg.Parent = snBuyPanel
    Instance.new("UICorner", BH.snBuy.maxKg).CornerRadius = UDim.new(0, 5)

    BH.snBuy.maxPrice = Instance.new("TextBox")
    BH.snBuy.maxPrice.Size = UDim2.new(0.5, -3, 0, 26) BH.snBuy.maxPrice.Position = UDim2.new(0.5, 3, 0, 30)
    BH.snBuy.maxPrice.BackgroundColor3 = C.input BH.snBuy.maxPrice.BorderSizePixel = 0
    BH.snBuy.maxPrice.Text = "" BH.snBuy.maxPrice.TextColor3 = C.text
    BH.snBuy.maxPrice.PlaceholderText = "💰 Max Price"
    BH.snBuy.maxPrice.PlaceholderColor3 = C.textDim
    BH.snBuy.maxPrice.Font = F BH.snBuy.maxPrice.TextSize = 11
    BH.snBuy.maxPrice.TextXAlignment = Enum.TextXAlignment.Center
    BH.snBuy.maxPrice.ClearTextOnFocus = false BH.snBuy.maxPrice.Parent = snBuyPanel
    Instance.new("UICorner", BH.snBuy.maxPrice).CornerRadius = UDim.new(0, 5)

    -- Row 3 (y=64): START HUNT (full width, toggles to STOP when active)
    BH.snBuy.refresh = btnOf(snBuyPanel, 0, 0, 1, 1, "🎯 START HUNT", C.accent)
    BH.snBuy.refresh.Size = UDim2.new(1, 0, 0, 30)
    BH.snBuy.refresh.Position = UDim2.new(0, 0, 0, 64)
    BH.snBuy.refresh.TextSize = 12

    -- Row 4 (y=100): Status label
    BH.snBuy.countLbl = Instance.new("TextLabel")
    BH.snBuy.countLbl.Size = UDim2.new(1, 0, 0, 18) BH.snBuy.countLbl.Position = UDim2.new(0, 0, 0, 100)
    BH.snBuy.countLbl.BackgroundTransparency = 1
    BH.snBuy.countLbl.Text = "Idle — isi kriteria lalu klik START HUNT"
    BH.snBuy.countLbl.TextColor3 = C.textDim BH.snBuy.countLbl.Font = FM BH.snBuy.countLbl.TextSize = 10
    BH.snBuy.countLbl.TextXAlignment = Enum.TextXAlignment.Left BH.snBuy.countLbl.Parent = snBuyPanel

    -- Row 5 (y=122 → bottom): Results scroll
    BH.snBuy.scroll = Instance.new("ScrollingFrame")
    BH.snBuy.scroll.Size = UDim2.new(1, 0, 1, -126) BH.snBuy.scroll.Position = UDim2.new(0, 0, 0, 122)
    BH.snBuy.scroll.BackgroundColor3 = C.card BH.snBuy.scroll.BorderSizePixel = 0
    BH.snBuy.scroll.ScrollBarThickness = 4 BH.snBuy.scroll.ScrollBarImageColor3 = C.accent
    BH.snBuy.scroll.CanvasSize = UDim2.new(0, 0, 0, 0) BH.snBuy.scroll.Parent = snBuyPanel
    Instance.new("UICorner", BH.snBuy.scroll).CornerRadius = UDim.new(0, 6)
    BH.snBuy.layout = Instance.new("UIListLayout") BH.snBuy.layout.Padding = UDim.new(0, 3) BH.snBuy.layout.Parent = BH.snBuy.scroll
    local snBuyScrollPad = Instance.new("UIPadding")
    snBuyScrollPad.PaddingTop = UDim.new(0, 4) snBuyScrollPad.PaddingLeft = UDim.new(0, 4) snBuyScrollPad.PaddingRight = UDim.new(0, 4)
    snBuyScrollPad.Parent = BH.snBuy.scroll

    -- v8.75: restore hunt criteria dari state file
    if BH.marketState and BH.marketState.hunt then
        local h = BH.marketState.hunt
        BH.snBuy.search.Text = h.petType or ""
        BH.snBuy.mutation.Text = h.mutation or ""
        BH.snBuy.minKg.Text = h.minKg or ""
        BH.snBuy.maxKg.Text = h.maxKg or ""
        BH.snBuy.maxPrice.Text = h.maxPrice or ""
    end
end


-- Reset filters
snResetBtn.MouseButton1Click:Connect(function()
    snSearch.Text = ""
    snMinAge.Text = "" snMaxAge.Text = ""
    snMinKg.Text = "" snMaxKg.Text = ""
    snMinPrice.Text = "" snMaxPrice.Text = ""
    -- v8.70: persist reset
    if BH.marketState then
        BH.marketState.snSearch = ""
        BH.marketState.snMinAge = "" BH.marketState.snMaxAge = ""
        BH.marketState.snMinKg = "" BH.marketState.snMaxKg = ""
        BH.marketState.snMinPrice = "" BH.marketState.snMaxPrice = ""
        BH.saveMarketState(BH.marketState)
    end
end)

-- v8.257: ===== INDEX HOP TAB — auto hop server via FindSellers =====
-- Pilih banyak jenis pet. Kalau pet target (jenis) gak ketemu di server dlm X menit,
-- panggil FindSellers("Pet",{PetData={PetType=jenis}}) -> game auto-hop ke server yg ada pet itu.
do
    local hp = snIndexPanel
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0,14) pad.PaddingLeft = UDim.new(0,14)
    pad.PaddingRight = UDim.new(0,14) pad.PaddingBottom = UDim.new(0,14)
    pad.Parent = hp

    lblOf(hp, "🌐  INDEX HOP", 0, 0, 300, 22, C.accent, 14, FB)
    lblOf(hp, "Auto pindah server cari jenis pet (via Index)", 0, 24, 400, 16, C.textDim, 11)

    BH.indexHop = BH.indexHop or {}
    BH.indexHop.selectedTypes = BH.indexHop.selectedTypes or {}
    if BH.marketState and BH.marketState.indexHopTypes then
        BH.indexHop.selectedTypes = BH.marketState.indexHopTypes
    end
    BH.indexHop.intervalSec = (BH.marketState and BH.marketState.indexHopInterval) or 5
    BH.indexHop.active = false

    -- tombol pilih jenis (multi)
    BH.indexHop.pickBtn = btnOf(hp, 0, 48, 1, 26, "🐾 Pilih Jenis Pet", C.card, C.text)
    BH.indexHop.pickBtn.Size = UDim2.new(1, 0, 0, 26)
    BH.indexHop.pickBtn.TextSize = 11

    -- label jenis terpilih
    BH.indexHop.selLbl = lblOf(hp, "Belum pilih jenis", 0, 80, 400, 16, C.textDim, 10)

    local function updateSelLbl()
        local picked = {}
        for k in pairs(BH.indexHop.selectedTypes) do table.insert(picked, k) end
        if #picked == 0 then
            BH.indexHop.selLbl.Text = "Belum pilih jenis"
            BH.indexHop.selLbl.TextColor3 = C.textDim
        else
            table.sort(picked)
            BH.indexHop.selLbl.Text = "Target: "..table.concat(picked, ", ")
            BH.indexHop.selLbl.TextColor3 = C.accent
        end
    end
    BH.indexHop.updateSelLbl = updateSelLbl
    updateSelLbl()

    -- interval (menit)
    lblOf(hp, "Cek tiap (detik):", 0, 102, 120, 20, C.text, 11)
    BH.indexHop.intervalBox = Instance.new("TextBox")
    BH.indexHop.intervalBox.Size = UDim2.new(0, 60, 0, 24)
    BH.indexHop.intervalBox.Position = UDim2.new(0, 124, 0, 100)
    BH.indexHop.intervalBox.BackgroundColor3 = C.card
    BH.indexHop.intervalBox.Text = tostring(BH.indexHop.intervalSec)
    BH.indexHop.intervalBox.PlaceholderText = "5"
    BH.indexHop.intervalBox.TextColor3 = C.text
    BH.indexHop.intervalBox.Font = FM BH.indexHop.intervalBox.TextSize = 12
    BH.indexHop.intervalBox.ClearTextOnFocus = false
    BH.indexHop.intervalBox.Parent = hp
    Instance.new("UICorner", BH.indexHop.intervalBox).CornerRadius = UDim.new(0,6)
    BH.indexHop.intervalBox.FocusLost:Connect(function()
        local v = tonumber(BH.indexHop.intervalBox.Text)
        if v and v >= 1 then
            BH.indexHop.intervalSec = v
            if BH.marketState then BH.marketState.indexHopInterval = v; BH.saveMarketState(BH.marketState) end
        else
            BH.indexHop.intervalBox.Text = tostring(BH.indexHop.intervalSec)
        end
    end)

    -- v8.261: max harga — kalau pet jenis ada TAPI > harga ini, tetap hop
    lblOf(hp, "Max harga (0=abaikan):", 0, 130, 150, 20, C.text, 11)
    BH.indexHop.maxPrice = (BH.marketState and BH.marketState.indexHopMaxPrice) or 0
    BH.indexHop.priceBox = Instance.new("TextBox")
    BH.indexHop.priceBox.Size = UDim2.new(0, 100, 0, 24)
    BH.indexHop.priceBox.Position = UDim2.new(0, 156, 0, 128)
    BH.indexHop.priceBox.BackgroundColor3 = C.card
    BH.indexHop.priceBox.Text = tostring(BH.indexHop.maxPrice)
    BH.indexHop.priceBox.PlaceholderText = "0"
    BH.indexHop.priceBox.TextColor3 = C.text
    BH.indexHop.priceBox.Font = FM BH.indexHop.priceBox.TextSize = 12
    BH.indexHop.priceBox.ClearTextOnFocus = false
    BH.indexHop.priceBox.Parent = hp
    Instance.new("UICorner", BH.indexHop.priceBox).CornerRadius = UDim.new(0,6)
    BH.indexHop.priceBox.FocusLost:Connect(function()
        local v = tonumber((BH.indexHop.priceBox.Text or ""):gsub(",",""))
        if v and v >= 0 then
            BH.indexHop.maxPrice = v
            if BH.marketState then BH.marketState.indexHopMaxPrice = v; BH.saveMarketState(BH.marketState) end
        else
            BH.indexHop.priceBox.Text = tostring(BH.indexHop.maxPrice)
        end
    end)

    -- v8.266: filter asal egg Index Hop sendiri (semua/prem/biasa)
    BH.indexHop.eggSource = (BH.marketState and BH.marketState.indexHopEggSource) or "all"
    BH.indexHop.eggBtn = btnOf(hp, 0, 162, 1, 26, "🥚 Egg: Semua", C.card, C.text)
    BH.indexHop.eggBtn.Size = UDim2.new(1, 0, 0, 26)
    BH.indexHop.eggBtn.Position = UDim2.new(0, 0, 0, 162)
    BH.indexHop.eggBtn.TextSize = 11
    local function ihEggLabel()
        local es = BH.indexHop.eggSource or "all"
        return es == "prem" and "🥚 Egg: Prem only"
            or es == "biasa" and "🥚 Egg: Biasa only"
            or "🥚 Egg: Semua"
    end
    BH.indexHop.eggBtn.Text = ihEggLabel()
    BH.indexHop.eggBtn.MouseButton1Click:Connect(function()
        local es = BH.indexHop.eggSource or "all"
        es = (es == "all") and "prem" or (es == "prem") and "biasa" or "all"
        BH.indexHop.eggSource = es
        BH.indexHop.eggBtn.Text = ihEggLabel()
        if BH.marketState then BH.marketState.indexHopEggSource = es; BH.saveMarketState(BH.marketState) end
    end)

    -- toggle start/stop
    BH.indexHop.toggleBtn = btnOf(hp, 0, 194, 1, 28, "▶ START INDEX HOP", C.success)
    BH.indexHop.toggleBtn.Size = UDim2.new(0.62, -3, 0, 28)
    BH.indexHop.toggleBtn.Position = UDim2.new(0, 0, 0, 194)
    BH.indexHop.toggleBtn.TextSize = 11

    -- v8.260: tombol Hop Now (langsung hop sekarang, buat testing)
    BH.indexHop.hopNowBtn = btnOf(hp, 0, 194, 1, 28, "⚡ HOP NOW", C.accent)
    BH.indexHop.hopNowBtn.Size = UDim2.new(0.38, 0, 0, 28)
    BH.indexHop.hopNowBtn.Position = UDim2.new(0.62, 3, 0, 194)
    BH.indexHop.hopNowBtn.TextSize = 11

    -- status
    BH.indexHop.statusLbl = lblOf(hp, "Idle — pilih jenis + START", 0, 228, 400, 32, C.textDim, 10)
    BH.indexHop.statusLbl.TextWrapped = true
    BH.indexHop.statusLbl.Size = UDim2.new(1, 0, 0, 32)

    -- picker jenis pet (multi) — pakai BH.allPetTypes
    BH.indexHop.pickBtn.MouseButton1Click:Connect(function()
        local types = BH.allPetTypes or {}
        if #types == 0 then
            BH.indexHop.statusLbl.Text = "⚠ daftar pet belum ke-load, buka tab History dulu / tunggu"
            BH.indexHop.statusLbl.TextColor3 = C.danger
            return
        end
        local ov = Instance.new("Frame")
        ov.Size = UDim2.new(1,0,1,0); ov.BackgroundColor3 = Color3.new(0,0,0)
        ov.BackgroundTransparency = 0.5; ov.ZIndex = 70; ov.Parent = gui
        local box = Instance.new("Frame")
        box.Size = UDim2.new(0, 320, 0, 420); box.Position = UDim2.new(0.5, -160, 0.5, -210)
        box.BackgroundColor3 = C.panel; box.BorderSizePixel = 0; box.ZIndex = 71; box.Parent = ov
        Instance.new("UICorner", box).CornerRadius = UDim.new(0,10)
        Instance.new("UIStroke", box).Color = C.accent
        local tt = lblOf(box, "🐾 Pilih Jenis (multi)", 12, 8, 240, 22, C.accent, 13, FB)
        tt.ZIndex = 72
        local xb = Instance.new("TextButton")
        xb.Size = UDim2.new(0,26,0,22); xb.Position = UDim2.new(1,-34,0,8)
        xb.BackgroundColor3 = C.danger; xb.Text = "X"; xb.TextColor3 = C.text
        xb.Font = FB; xb.TextSize = 12; xb.ZIndex = 72; xb.Parent = box
        Instance.new("UICorner", xb).CornerRadius = UDim.new(0,4)
        local sb = Instance.new("TextBox")
        sb.Size = UDim2.new(1,-24,0,30); sb.Position = UDim2.new(0,12,0,38)
        sb.BackgroundColor3 = C.card; sb.Text = ""; sb.PlaceholderText = "cari jenis..."
        sb.TextColor3 = C.text; sb.Font = FM; sb.TextSize = 12; sb.ClearTextOnFocus = false
        sb.ZIndex = 72; sb.Parent = box
        Instance.new("UICorner", sb).CornerRadius = UDim.new(0,6)
        local sf = Instance.new("ScrollingFrame")
        sf.Size = UDim2.new(1,-20,1,-110); sf.Position = UDim2.new(0,10,0,74)
        sf.BackgroundTransparency = 1; sf.ScrollBarThickness = 3; sf.BorderSizePixel = 0
        sf.CanvasSize = UDim2.new(0,0,0,0); sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
        sf.ZIndex = 72; sf.Parent = box
        local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0,4); ll.Parent = sf
        local doneBtn = btnOf(box, 12, 0, 1, 28, "✓ SELESAI", C.success)
        doneBtn.Size = UDim2.new(1,-24,0,28); doneBtn.Position = UDim2.new(0,12,1,-36)
        doneBtn.ZIndex = 72
        local function build(filter)
            for _, c in ipairs(sf:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
            filter = (filter or ""):lower()
            for _, nm in ipairs(types) do
                if filter == "" or nm:lower():find(filter, 1, true) then
                    local sel = BH.indexHop.selectedTypes[nm] == true
                    local b = Instance.new("TextButton")
                    b.Size = UDim2.new(1,0,0,28); b.BackgroundColor3 = sel and C.accent or C.card
                    b.Text = (sel and "✓ " or "   ")..nm
                    b.TextColor3 = sel and Color3.fromRGB(17,17,17) or C.text
                    b.TextXAlignment = Enum.TextXAlignment.Left
                    b.Font = FM; b.TextSize = 12; b.ZIndex = 73; b.Parent = sf
                    Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
                    local lp = Instance.new("UIPadding"); lp.PaddingLeft = UDim.new(0,8); lp.Parent = b
                    b.MouseButton1Click:Connect(function()
                        if BH.indexHop.selectedTypes[nm] then
                            BH.indexHop.selectedTypes[nm] = nil
                        else
                            BH.indexHop.selectedTypes[nm] = true
                        end
                        build(sb.Text)
                        updateSelLbl()
                        if BH.marketState then
                            BH.marketState.indexHopTypes = BH.indexHop.selectedTypes
                            BH.saveMarketState(BH.marketState)
                        end
                    end)
                end
            end
        end
        build("")
        sb:GetPropertyChangedSignal("Text"):Connect(function() build(sb.Text) end)
        xb.MouseButton1Click:Connect(function() ov:Destroy() end)
        doneBtn.MouseButton1Click:Connect(function() ov:Destroy() end)
    end)

    -- toggle handler
    BH.indexHop.toggleBtn.MouseButton1Click:Connect(function()
        BH.indexHop.active = not BH.indexHop.active
        if BH.indexHop.active then
            local picked = {}
            for k in pairs(BH.indexHop.selectedTypes) do table.insert(picked, k) end
            if #picked == 0 then
                BH.indexHop.active = false
                BH.indexHop.statusLbl.Text = "❌ Pilih jenis pet dulu"
                BH.indexHop.statusLbl.TextColor3 = C.danger
                return
            end
            BH.indexHop.toggleBtn.Text = "⛔ STOP INDEX HOP"
            BH.indexHop.toggleBtn.BackgroundColor3 = C.danger
            BH.indexHop.statusLbl.Text = "🌐 Active — cek pet tiap "..BH.indexHop.intervalSec.." detik"
            BH.indexHop.statusLbl.TextColor3 = C.accent
            BH.indexHop.lastHop = tick()
            L("[IndexHop] START — "..#picked.." jenis, interval "..BH.indexHop.intervalSec.."s")
        else
            BH.indexHop.toggleBtn.Text = "▶ START INDEX HOP"
            BH.indexHop.toggleBtn.BackgroundColor3 = C.success
            BH.indexHop.statusLbl.Text = "⛔ Stopped"
            BH.indexHop.statusLbl.TextColor3 = C.textDim
            L("[IndexHop] STOP")
        end
    end)

    -- v8.266: tombol HOP NOW — langsung hop server biasa (tanpa nunggu interval)
    BH.indexHop.hopNowBtn.MouseButton1Click:Connect(function()
        BH.indexHop.statusLbl.Text = "⚡ Hop Now — pindah server..."
        BH.indexHop.statusLbl.TextColor3 = C.accent
        BH.indexHop.hopNowBtn.Text = "⚡ ..."
        task.spawn(function()
            if BH.indexHop.doHop then
                local ok, info = BH.indexHop.doHop()
                if ok then
                    BH.indexHop.statusLbl.Text = "⚡ Hop server..."
                    L("[IndexHop] HOP NOW -> hop server")
                else
                    BH.indexHop.statusLbl.Text = "⚠ "..tostring(info)
                    L("[IndexHop] HOP NOW gagal: "..tostring(info))
                end
            elseif BH.manualHop then
                BH.manualHop()
                BH.indexHop.statusLbl.Text = "⚡ Hop server..."
            else
                BH.indexHop.statusLbl.Text = "⚠ fungsi hop belum siap, tunggu sebentar"
            end
            task.wait(1)
            BH.indexHop.hopNowBtn.Text = "⚡ HOP NOW"
        end)
    end)
end

end  -- end do block for snipe UI


-- ============================================================
-- LOGIC
-- ============================================================
-- v8.52: safe remote access (di garden server TradeEvents gak ada)
-- v8.141: Use WaitForChild + lazy retry — RemoveListing kadang lambat replicate ke client
-- v8.142: more aggressive + diagnostic + background retry loop
local createRE, removeRE, buyRE, claimRE, removeBoothRE
local function resolveRemotes(timeout)
    timeout = timeout or 5
    local diag = {}
    pcall(function()
        local GE = RS:FindFirstChild("GameEvents") or RS:WaitForChild("GameEvents", timeout)
        if not GE then table.insert(diag, "GE=nil"); return end
        table.insert(diag, "GE="..GE.Name)
        local TE = GE:FindFirstChild("TradeEvents") or GE:WaitForChild("TradeEvents", timeout)
        if not TE then table.insert(diag, "TE=nil"); return end
        table.insert(diag, "TE="..TE.Name)
        local Booths = TE:FindFirstChild("Booths") or TE:WaitForChild("Booths", timeout)
        if not Booths then table.insert(diag, "Booths=nil"); return end
        table.insert(diag, "Booths="..Booths.Name)
        -- Dump all Booths children sekali doang biar tau apa yg available
        local children = {}
        for _, c in ipairs(Booths:GetChildren()) do table.insert(children, c.Name) end
        table.insert(diag, "Booths.children=["..table.concat(children, ",").."]")
        if not createRE then createRE = Booths:FindFirstChild("CreateListing") or Booths:WaitForChild("CreateListing", timeout) end
        if not removeRE then removeRE = Booths:FindFirstChild("RemoveListing") or Booths:WaitForChild("RemoveListing", timeout) end
        if not buyRE then buyRE = Booths:FindFirstChild("BuyListing") or Booths:WaitForChild("BuyListing", timeout) end
        if not claimRE then claimRE = Booths:FindFirstChild("ClaimBooth") or Booths:WaitForChild("ClaimBooth", timeout) end
        if not removeBoothRE then removeBoothRE = Booths:FindFirstChild("RemoveBooth") or Booths:WaitForChild("RemoveBooth", timeout) end
    end)
    -- v8.257: resolve FindSellers (Index hop) — cari recursive, lokasi bisa beda
    if not BH.findSellersRE then
        pcall(function()
            BH.findSellersRE = RS:FindFirstChild("FindSellers", true)
        end)
    end
    return removeRE ~= nil, diag
end

-- Initial attempt
local _ok, _diag = resolveRemotes(5)
L("[Init] resolveRemotes initial — removeRE="..(removeRE and "FOUND" or "nil").." | "..table.concat(_diag or {}, " | "))

-- v8.142: BACKGROUND retry loop — kalo init missed, terus coba sampai dapet (max 60s)
task.spawn(function()
    local startTime = tick()
    while not removeRE and (tick() - startTime) < 60 do
        task.wait(2)
        local ok = resolveRemotes(3)
        if ok then
            L("[Init] ✅ removeRE finally found via background retry (after "..math.floor(tick()-startTime).."s)")
            break
        end
    end
    if not removeRE then
        L("[Init] ⚠ removeRE STILL nil setelah 60s background retry — manual lookup needed")
    end
end)
pcall(function()
    local Booths = RS:FindFirstChild("GameEvents")
        and RS.GameEvents:FindFirstChild("TradeEvents")
        and RS.GameEvents.TradeEvents:FindFirstChild("Booths")
    if Booths then
        if not createRE then createRE = Booths:FindFirstChild("CreateListing") end
        if not removeRE then removeRE = Booths:FindFirstChild("RemoveListing") end
        -- v8.105: fallback names (kalo game rename)
        if not removeRE then
            for _, alt in ipairs({"UnlistItem", "Unlist", "DeleteListing", "RemoveItem", "Delist"}) do
                removeRE = Booths:FindFirstChild(alt)
                if removeRE then
                    L("[Init] removeRE alt-name found: "..alt)
                    break
                end
            end
        end
        if not removeRE then
            -- Dump all RE names di Booths buat debug
            local names = {}
            for _, c in ipairs(Booths:GetChildren()) do table.insert(names, c.Name) end
            L("[Init] ⚠ RemoveListing NOT FOUND! Booths children: "..table.concat(names, ", "))
        end
        if not buyRE then buyRE = Booths:FindFirstChild("BuyListing") end
        if not claimRE then claimRE = Booths:FindFirstChild("ClaimBooth") end
        if not removeBoothRE then removeBoothRE = Booths:FindFirstChild("RemoveBooth") end
    end
end)

-- v8.106: AGGRESSIVE FALLBACK — scan SEMUA RemoteEvent/RemoteFunction di RS
-- yang namanya mengandung "remove" atau "unlist" or "delete" + "list"/"item"
if not removeRE then
    L("[Init] 🔍 Aggressive scan: cari removeRE di seluruh RS...")
    local candidates = {}
    local function scanFolder(obj, depth)
        if depth > 6 then return end
        for _, c in ipairs(obj:GetChildren()) do
            if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                local n = c.Name:lower()
                local hasRemove = n:find("remove") or n:find("unlist") or n:find("delist") or n:find("delete")
                local hasList = n:find("list") or n:find("item") or n:find("pet") or n:find("booth")
                if hasRemove and hasList then
                    table.insert(candidates, c)
                    L("[Init] candidate: "..c:GetFullName().." ("..c.ClassName..")")
                end
            elseif c:IsA("Folder") or c:IsA("Configuration") then
                scanFolder(c, depth + 1)
            end
        end
    end
    pcall(function() scanFolder(RS, 0) end)
    -- Prefer one that contains "list" AND "remove"/"unlist"
    for _, c in ipairs(candidates) do
        local n = c.Name:lower()
        if (n:find("remove") or n:find("unlist") or n:find("delist")) and n:find("list") then
            removeRE = c
            L("[Init] ✅ removeRE PICKED: "..c:GetFullName())
            break
        end
    end
    -- Fallback: ambil yang pertama kalo gak ada match strict
    if not removeRE and #candidates > 0 then
        removeRE = candidates[1]
        L("[Init] ⚠ removeRE fallback (1st match): "..candidates[1]:GetFullName())
    end
    if not removeRE then
        L("[Init] ❌❌❌ removeRE bener-bener gak ada di RS. Coba pake TBC method.")
    end
end

-- v8.140: deep dump SEMUA remote candidates buat unlist (since TBC cuma punya 3 method)
task.spawn(function()
    task.wait(3)
    if removeRE then
        L("[Init] ✅ removeRE: "..removeRE.ClassName.." @ "..removeRE:GetFullName())
    else
        L("[Init] ⚠⚠⚠ removeRE NIL — dumping ALL booth/list remotes in RS:")
        local found = {}
        local function scan(folder, depth)
            if depth > 10 then return end
            for _, c in ipairs(folder:GetChildren()) do
                if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                    local n = c.Name:lower()
                    local p = c:GetFullName():lower()
                    -- catch wider range: anything with booth/list/trade/market in name OR path
                    if n:find("booth") or n:find("list") or n:find("trade") or n:find("market")
                       or n:find("sell") or n:find("buy") or n:find("remove") or n:find("delete")
                       or n:find("unlist") or n:find("delist") or n:find("clear")
                       or p:find("booth") or p:find("trade") then
                        table.insert(found, c)
                        L("[Init] 📡 "..c.ClassName.." | "..c:GetFullName())
                    end
                elseif c:IsA("Folder") or c:IsA("Configuration") or c:IsA("ModuleScript") then
                    pcall(function() scan(c, depth+1) end)
                end
            end
        end
        pcall(function() scan(RS, 0) end)
        L("[Init] dump total: "..#found.." candidates")
    end
    if BH.TBC then
        local methods = {}
        for k, v in pairs(BH.TBC) do
            if type(v) == "function" then table.insert(methods, k) end
        end
        L("[Init] TBC methods ("..#methods.."): "..table.concat(methods, ", "):sub(1, 300))
    end
end)
local skinRE
pcall(function() skinRE = RS.GameEvents.TradeBoothSkinService.Equip end)

local function isPet(t) return t:IsA("Tool") and (t:FindFirstChild("PetToolLocal") or t:GetAttribute("PET_UUID")) end
local function isFav(t)
    if t:GetAttribute("IsFavorite") == true then return true end
    if t:GetAttribute("Favorite") == true then return true end
    return (t:FindFirstChild("Favorite") or t:FindFirstChild("IsFavorite")) ~= nil
end
local function getPetType(t) return tostring(t:GetAttribute("f") or "?") end

-- Current weight: try child NumberValue 'Weight' first, fallback ke name parse
local function getCurrentKg(t)
    -- Try child NumberValue (game format for booth tools + maybe backpack)
    for _, name in ipairs({"Weight", "weight", "KG", "kg"}) do
        local child = t:FindFirstChild(name)
        if child and child:IsA("ValueBase") then
            local v = tonumber(child.Value)
            if v and v > 0 then return v end
        end
    end
    -- Try attribute
    for _, attr in ipairs({"Weight", "weight", "KG", "kg", "w"}) do
        local v = t:GetAttribute(attr)
        if v and tonumber(v) and tonumber(v) > 0 then return tonumber(v) end
    end
    -- Fallback: parse from name like "Peryton [6.4 KG]"
    return tonumber(string.match(t.Name, "%[([%d%.]+)%s*[Kk][Gg]%]")) or 0
end

-- Get age: try API, child value, attribute, name patterns
local function getAge(t)
    -- Try API first (Pulse APS)
    local uuid = t:GetAttribute("PET_UUID")
    if uuid and getgenv and getgenv().PulseAPS and getgenv().PulseAPS.getAge then
        local age = getgenv().PulseAPS.getAge(uuid)
        if age then return age end
    end
    -- Try child NumberValue 'Age'
    for _, name in ipairs({"Age", "age", "Level", "Lvl"}) do
        local child = t:FindFirstChild(name)
        if child and child:IsA("ValueBase") then
            local v = tonumber(child.Value)
            if v and v >= 1 then return v end
        end
    end
    -- Try attribute
    for _, attr in ipairs({"Age", "age", "Level", "Lvl"}) do
        local v = t:GetAttribute(attr)
        if v and tonumber(v) and tonumber(v) >= 1 then return tonumber(v) end
    end
    -- Parse from name
    local name = t.Name
    for _, pat in ipairs({
        "%[Age%s+(%d+)%]", "%[Age(%d+)%]",
        "%[Lv%s+(%d+)%]", "%[Lv(%d+)%]",
        "%[Level%s+(%d+)%]", "%[Level(%d+)%]",
        "%[Lvl%s+(%d+)%]", "%[Lvl(%d+)%]",
        "Age%s*[:=]%s*(%d+)",
    }) do
        local m = name:match(pat)
        if m then return tonumber(m) end
    end
    if name:match("%[Age%s*MAX%]") or name:match("%[MAX%]") then return 100 end
    -- v8.103: return nil kalo bener-bener gak tau (BUKAN default 1!)
    -- Yang lama default 1 → confusing dengan pet TRUE age 1
    return nil
end

-- Base weight (at age 1) — try attributes, fallback to FORMULA: baseKG = kg * 11 / (age + 10)
local BASE_KG_ATTRS = {
    "BASE_KG","PET_BASE_KG","BaseKG","BaseWeight",
    "PET_BASE_WEIGHT","BASE_WEIGHT","PET_KG_BASE",
    "StartingWeight","STARTING_KG",
}
local function getBaseKg(t)
    -- v8.245: PRIORITAS 1 — BaseWeight ASLI dari server (via APS: container/API/datastore).
    -- Ini akurat untuk age BERAPA PUN (35, 70, 100) karena BaseWeight gak tergantung age/mutasi.
    -- Server simpen base age-0; ×1.1 = normalize ke age-1 (cocok rule).
    local okU, uuid = pcall(function() return t:GetAttribute("PET_UUID") end)
    if okU and uuid and getgenv().PulseAPS then
        local bw = getgenv().PulseAPS.getBaseKg(uuid)
        if bw and bw > 0 then return bw * 1.1, "APS-age1" end
    end
    -- PRIORITAS 2 — kalo BaseWeight server gak ada, hitung dari display + age (kalo age kebaca).
    -- Akurat juga, asal age-nya bener. Rumus: base = display × 11 / (age+10).
    local disp = getCurrentKg(t)
    local age = getAge(t)
    if disp and disp > 0 and age and age >= 0 then
        return disp * 11 / (age + 10), "formula"
    end
    -- v8.246: JANGAN pakai getCachedBaseKG di sini. Cache di-index per JENIS (nama),
    -- jadi SEMUA pet sejenis dapet base yg SAMA (mis. semua Everchanted Mimic = 6.071),
    -- padahal display tiap pet beda → pet yg harusnya >6.1 ikut lolos. BUG terbukti di log.
    -- PRIORITAS 3 (jaring terakhir) — age nil & BaseWeight server gak ada (pet mutasi).
    -- Asumsi mature age-100, hitung PER-PET dari display masing2: base = display × 11/110.
    -- Ini ngasih base beda tiap pet (61.36->6.136, 62.29->6.229) jadi filter max jalan bener.
    -- CATATAN: kalo pet sebenernya muda (age<100), hasil under-estimate — tapi mayoritas
    -- pet mutasi yg di-list udah mature. Idealnya BaseWeight server (PRIORITAS 1) yg kepake.
    if disp and disp > 0 then
        return disp * 11 / 110, "formula-mature"
    end
    return nil, "unknown"
end

-- v8.88: count pet di backpack yang match rule (untuk badge [N] di LIST HARGA)
BH.countMyPetsForRule = function(r)
    local bp = player and player:FindFirstChild("Backpack")
    if not bp then return 0 end
    local ruleType = r.type
    local ruleMin = r.min or 0
    local ruleMax = (r.max == math.huge) and math.huge or r.max
    local count = 0
    local debugInfo = {checked=0, typeMatch=0, kgMatch=0, hasBase=0, noBase=0}
    for _, t in ipairs(bp:GetChildren()) do
        if isPet(t) then
            debugInfo.checked = debugInfo.checked + 1
            local pType = getPetType(t)
            local pBase = (BH.getBaseName and pType ~= "") and BH.getBaseName(pType) or pType
            local typeOk = (not ruleType) or (pBase == ruleType) or (pType == ruleType)
            if typeOk then
                debugInfo.typeMatch = debugInfo.typeMatch + 1
                local baseKg = getBaseKg(t)
                if baseKg then debugInfo.hasBase = debugInfo.hasBase + 1
                else debugInfo.noBase = debugInfo.noBase + 1 end
                if baseKg and baseKg >= ruleMin and (ruleMax == math.huge or baseKg <= ruleMax) then
                    debugInfo.kgMatch = debugInfo.kgMatch + 1
                    count = count + 1
                end
            end
        end
    end
    -- v8.122: log diagnostic kalo count==0 tapi ada typeMatch (debug bug)
    if count == 0 and debugInfo.typeMatch > 0 and ruleType then
        L("[COUNT-DIAG] r='"..ruleType.."' "..ruleMin.."-"..(ruleMax==math.huge and "∞" or ruleMax)..
          " | checked="..debugInfo.checked..
          " typeMatch="..debugInfo.typeMatch..
          " hasBase="..debugInfo.hasBase..
          " noBase="..debugInfo.noBase..
          " kgMatch="..debugInfo.kgMatch)
    end
    return count
end

local function getBoothState(b)
    local di = b:FindFirstChild("DynamicInstances")
    -- Scan booth descendants for TextLabels (booth signs)
    for _, d in ipairs(b:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local txt = tostring(d.Text or "")
            local lowTxt = string.lower(txt)
            if lowTxt:find("unclaimed", 1, true) then
                return "unclaimed"
            end
            -- Check if booth sign shows player name
            if string.find(lowTxt, string.lower(player.Name), 1, true) then
                return "mine"
            end
        end
    end
    -- Fallback: check tool attributes (in case OWNER attr exists)
    if di then
        for _, c in ipairs(di:GetChildren()) do
            if c:IsA("Tool") then
                local owner = c:GetAttribute("OWNER") or c:GetAttribute("a")
                    or c:GetAttribute("Owner") or c:GetAttribute("Seller")
                    or c:GetAttribute("PlayerName")
                if owner == player.Name then return "mine" end
            end
        end
    end
    if di and #di:GetChildren() > 0 then return "owned" end
    return "unknown"
end

local function findMyBooth(Booths)
    for _, b in ipairs(Booths:GetChildren()) do
        if (b:IsA("Model") or b:IsA("Folder")) and getBoothState(b) == "mine" then
            return b
        end
    end
end

local function listPet(uuidBraced, price)
    -- Unequip pet first if currently equipped (game won't let you list equipped pets)
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            for _, t in ipairs(char:GetChildren()) do
                if t:IsA("Tool") then
                    local u = t:GetAttribute("PET_UUID")
                    if u and ("{"..tostring(u):gsub("[{}]", "").."}") == uuidBraced then
                        hum:UnequipTools()
                        task.wait(0.15)
                        break
                    end
                end
            end
        end
    end

    -- v8.30: helper untuk detect UUID format (hex-hex-hex-hex-hex)
    local function looksLikeUuid(s)
        if type(s) ~= "string" then return false end
        return s:match("^%{?%x+%-%x+%-%x+%-%x+%-%x+%}?$") ~= nil
    end

    -- v8.30: helper untuk parse error string dari any return val
    -- v8.79: handle tables / booleans / numbers untuk extract error info
    local function extractErr(rets)
        for i = 2, 5 do
            local v = rets[i]
            if type(v) == "string" and not looksLikeUuid(v) then
                return v
            elseif type(v) == "table" then
                -- Common error table shapes
                if v.Message then return tostring(v.Message) end
                if v.message then return tostring(v.message) end
                if v.error then return tostring(v.error) end
                if v.err then return tostring(v.err) end
                if v.reason then return tostring(v.reason) end
                if v[1] and type(v[1]) == "string" then return tostring(v[1]) end
            elseif type(v) == "number" then
                return "errcode:"..tostring(v)
            end
        end
        return nil
    end

    -- v8.79: dump full rets structure for diagnostics
    local function dumpRets(rets)
        local parts = {}
        for i = 1, 5 do
            local v = rets[i]
            local t = type(v)
            local s
            if v == nil and i > 2 then break end  -- stop at trailing nils
            if t == "string" then
                s = '"'..v:sub(1,40)..(#v > 40 and "..." or "")..'"'
            elseif t == "table" then
                local kv = {}
                local cnt = 0
                for k, val in pairs(v) do
                    cnt = cnt + 1
                    if cnt <= 4 then
                        table.insert(kv, tostring(k).."="..tostring(val):sub(1,20))
                    end
                end
                if cnt > 4 then table.insert(kv, "...+"..(cnt-4)) end
                s = "{"..table.concat(kv, ", ").."}"
            else
                s = tostring(v)
            end
            table.insert(parts, "["..i.."]"..t..":"..s)
        end
        return table.concat(parts, " | ")
    end

    -- Try with braced UUID first
    local rets = {pcall(function() return createRE:InvokeServer("Pet", uuidBraced, price) end)}

    if rets[1] then
        -- (true, uuid)
        if rets[2] == true and looksLikeUuid(rets[3]) then return true, rets[3] end
        -- direct uuid return
        if looksLikeUuid(rets[2]) then return true, rets[2] end
        -- v8.80: (true) only — server accept tapi gak return UUID, tetap dianggap sukses
        -- Bukti: user lihat pet di booth setelah rejoin meski script log "fail"
        if rets[2] == true then return true, "ok-no-uuid" end
        -- v8.80: (true, true) — confirmation truthy without UUID
        if rets[2] and rets[2] ~= false and type(rets[2]) ~= "string" and not looksLikeUuid(rets[2]) then
            -- pcall ok + non-error truthy value → likely success
            -- Tapi cuma kalo gak ada error string di rets[3..5]
            local hasErr = false
            for i = 2, 5 do
                if type(rets[i]) == "string" and not looksLikeUuid(rets[i]) then
                    hasErr = true; break
                end
            end
            if not hasErr then return true, "ok-truthy:"..tostring(rets[2]):sub(1,20) end
        end
    end

    -- v8.76: kalo error rate-limit, JANGAN retry pake clean UUID — itu cuma nge-spam server
    local firstErr = extractErr(rets) or ""
    local firstErrLow = firstErr:lower()
    if firstErrLow:find("please wait") or firstErrLow:find("cooldown") or firstErrLow:find("too fast") then
        return false, firstErr
    end

    -- v8.79: save first attempt dump untuk diagnostic
    local firstDump = dumpRets(rets)

    -- Try without braces (only for non-rate-limit errors)
    local clean = uuidBraced:gsub("[{}]", "")
    rets = {pcall(function() return createRE:InvokeServer("Pet", clean, price) end)}

    if rets[1] then
        if rets[2] == true and looksLikeUuid(rets[3]) then return true, rets[3] end
        if looksLikeUuid(rets[2]) then return true, rets[2] end
        -- v8.80: lenient detection juga untuk attempt kedua
        if rets[2] == true then return true, "ok-no-uuid-clean" end
        if rets[2] and rets[2] ~= false and type(rets[2]) ~= "string" and not looksLikeUuid(rets[2]) then
            local hasErr = false
            for i = 2, 5 do
                if type(rets[i]) == "string" and not looksLikeUuid(rets[i]) then
                    hasErr = true; break
                end
            end
            if not hasErr then return true, "ok-truthy-clean:"..tostring(rets[2]):sub(1,20) end
        end
    end

    -- v8.30: kalau gak sukses, ambil error message
    local err = extractErr(rets) or "unknown"

    -- v8.79: kalau "unknown" → embed raw dump biar bisa diagnose
    if err == "unknown" then
        local secondDump = dumpRets(rets)
        err = "unknown|braced:"..firstDump.."|clean:"..secondDump
    end
    return false, err
end

-- ===== PICKER (modal-based, MULTI select v8.127) =====
local KNOWN_PETS = {
    "Peacock","Peryton","Elephant","Mimic Octopus","Bearded Dragon","Griffin","Empress Bee","Echo Frog","Tanuki","Dragonfly","Caterpillar","Snail","Bee","Cat","Dog","Hamster","Rabbit","Fox","Wolf","Bear","Lion","Tiger","Panda","Monkey","Dolphin","Shark","Whale","Octopus","Crab","Lobster","Turtle","Snake","Lizard","Frog","Toad","Chicken","Duck","Goose","Swan","Eagle","Hawk","Owl","Parrot","Penguin","Flamingo","Pelican","Crocodile","Hippo","Giraffe","Zebra","Cheetah","Leopard","Kangaroo","Koala","Sloth","Squirrel","Mole","Mouse","Bat","Pig","Cow","Sheep","Goat","Horse","Llama","Alpaca","Hedgehog","Raccoon","Skunk","Beaver","Spider","Scorpion","Polar Bear","Grizzly Bear","Honey Bee","Bumble Bee","Wasp","Butterfly","Moth","Ladybug","Firefly","Mantis","Toucan","Vulture","Raven","Crow","Sparrow","Robin","Dragon","Phoenix","Unicorn","Pegasus",
}
-- v8.127: multi-select state stored in BH (avoid 200-local limit)
BH.selectedTypes = BH.selectedTypes or {}

do
    -- Add DONE button at top of modal
    local modalDoneBtn = Instance.new("TextButton")
    modalDoneBtn.Size = UDim2.new(0, 80, 0, 28)
    modalDoneBtn.Position = UDim2.new(1, -88, 0, 8)
    modalDoneBtn.BackgroundColor3 = C.accent
    modalDoneBtn.BorderSizePixel = 0
    modalDoneBtn.Text = "✓ DONE"
    modalDoneBtn.TextColor3 = Color3.new(0, 0, 0)
    modalDoneBtn.Font = FB
    modalDoneBtn.TextSize = 12
    modalDoneBtn.ZIndex = 12
    modalDoneBtn.Parent = modal
    Instance.new("UICorner", modalDoneBtn).CornerRadius = UDim.new(0, 5)

    local function updatePickerLabel()
        local cnt = 0
        local first = nil
        for k in pairs(BH.selectedTypes) do
            cnt = cnt + 1
            if not first then first = k end
        end
        local txt
        if cnt == 0 then txt = "Pilih Pet Type..."
        elseif cnt == 1 then txt = first
        else txt = first.." +"..(cnt-1).." lainnya"
        end
        typeDropLbl.Text = txt
        lhTypeDropLbl.Text = txt
        typeDropLbl.TextColor3 = C.text
        lhTypeDropLbl.TextColor3 = C.text
        selectedType = first  -- legacy single-value compat
    end
    BH.updatePickerLabel = updatePickerLabel

    modalDoneBtn.MouseButton1Click:Connect(function()
        modalOverlay.Visible = false
    end)

    local function scanPetTypes()
        local types = {}
        local TW = Workspace:FindFirstChild("TradeWorld")
        if TW then
            local Booths = TW:FindFirstChild("Booths")
            if Booths then
                for _, b in ipairs(Booths:GetDescendants()) do
                    if b:IsA("Tool") then
                        local f = b:GetAttribute("f")
                        if f then types[tostring(f)] = true end
                    end
                end
            end
        end
        local bp = player:FindFirstChild("Backpack")
        if bp then for _, t in ipairs(bp:GetChildren()) do if isPet(t) then types[getPetType(t)] = true end end end
        return types
    end

    local function populateModalList()
        for _, c in ipairs(modalList:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end

        local typesMap = {}
        for _, t in ipairs(KNOWN_PETS) do typesMap[t] = 0 end
        for t, _ in pairs(scanPetTypes()) do typesMap[t] = 0 end

        -- v8.153: scan SEMUA pet types dari game registry (~493 entries)
        pcall(function()
            local data = RS:FindFirstChild("Data")
            local petReg = data and data:FindFirstChild("PetRegistry")
            local petList = petReg and petReg:FindFirstChild("PetList")
            if petList then
                if petList:IsA("ModuleScript") then
                    local ok, m = pcall(require, petList)
                    if ok and type(m) == "table" then
                        for name, _ in pairs(m) do
                            if type(name) == "string" then typesMap[name] = typesMap[name] or 0 end
                        end
                    end
                else
                    for _, c in ipairs(petList:GetChildren()) do
                        if c:IsA("ModuleScript") then
                            typesMap[c.Name] = typesMap[c.Name] or 0
                        end
                    end
                end
            end
            -- Alt path: RS.PetData or RS.Pets folder
            for _, alt in ipairs({"PetData", "Pets", "PetTypes"}) do
                local f = RS:FindFirstChild(alt)
                if f then
                    for _, c in ipairs(f:GetChildren()) do
                        if c:IsA("ModuleScript") or c:IsA("Folder") then
                            typesMap[c.Name] = typesMap[c.Name] or 0
                        end
                    end
                end
            end
        end)

        local bp = player:FindFirstChild("Backpack")
        if bp then for _, t in ipairs(bp:GetChildren()) do
            if isPet(t) and not isFav(t) then typesMap[getPetType(t)] = (typesMap[getPetType(t)] or 0) + 1 end
        end end

        local types = {}
        for t, c in pairs(typesMap) do table.insert(types, {name=t, count=c}) end
        table.sort(types, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)

        local sf = string.lower(modalSearch.Text or "")

        local function makeItem(label, value)
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, -8, 0, 38) b.AutoButtonColor = false
            local sel = BH.selectedTypes[value] == true
            b.BackgroundColor3 = sel and C.accent or C.card
            b.BorderSizePixel = 0
            b.Text = (sel and "✓ " or "  ")..label
            b.TextColor3 = sel and Color3.new(0,0,0) or C.text
            b.Font = sel and FB or FM
            b.TextSize = 14
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.Parent = modalList
            b.ZIndex = 12
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
            local s = Instance.new("UIStroke", b)
            s.Color = C.accent s.Thickness = 1
            s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            s.Transparency = sel and 0 or 0.6
            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0, 12) pad.Parent = b
            b.MouseButton1Click:Connect(function()
                if BH.selectedTypes[value] then BH.selectedTypes[value] = nil
                else BH.selectedTypes[value] = true end
                updatePickerLabel()
                populateModalList()
            end)
        end

        for _, p in ipairs(types) do
            if sf == "" or string.find(string.lower(p.name), sf, 1, true) then
                local label = p.name..(p.count > 0 and "  ("..p.count..")" or "")
                makeItem(label, p.name)
            end
        end

        modalList.CanvasSize = UDim2.new(0, 0, 0, modalListLayout.AbsoluteContentSize.Y + 8)
    end

    modalSearch:GetPropertyChangedSignal("Text"):Connect(populateModalList)
    typeDrop.MouseButton1Click:Connect(populateModalList)
end

-- ===== PET INVENTORY BROWSER =====
local perTypePrices = {}  -- keep for compat with startBtn
local refreshBackpackStats  -- forward declare

do
    -- Detect inventory capacity (Grow A Garden uses leaderstats or player attribute)
    local function getInventoryCapacity()
        for _, attr in ipairs({"MaxInventory", "InventoryCapacity", "MaxPets", "PetCapacity", "MaxStorage", "BackpackSize"}) do
            local v = player:GetAttribute(attr)
            if v and tonumber(v) then return tonumber(v) end
        end
        local ls = player:FindFirstChild("leaderstats")
        if ls then
            for _, c in ipairs(ls:GetChildren()) do
                if c.Name:find("[Cc]apacity") or c.Name:find("[Mm]ax") then
                    if c:IsA("ValueBase") then return tonumber(c.Value) end
                end
            end
        end
        for _, name in ipairs({"Data", "Stats", "PlayerData"}) do
            local d = player:FindFirstChild(name)
            if d then
                for _, c in ipairs(d:GetChildren()) do
                    if c.Name:find("[Cc]apacity") or c.Name:find("[Mm]ax[Ii]nv") then
                        if c:IsA("ValueBase") then return tonumber(c.Value) end
                    end
                end
            end
        end
        return nil
    end

    -- Refresh stats card in List Harga tab
    refreshBackpackStats = function()
        local bp = player:FindFirstChild("Backpack")
        if not bp then return end
        local total, favCount = 0, 0
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then
                local itemType = t:GetAttribute("ItemType") or t:GetAttribute("PetType")
                if itemType == "Pet" then
                    total = total + 1
                    if t:GetAttribute("IsFavorite") == true or t:GetAttribute("Favorite") == true then
                        favCount = favCount + 1
                    end
                end
            end
        end
        local nonFav = total - favCount
        lhPetCount.Text = total.." pet"
        -- v8.72: FAV+CAPACITY hidden, no update
        -- v8.88: trigger refresh count badges di LIST HARGA juga
        if BH.refreshPriceCounts then pcall(BH.refreshPriceCounts) end
    end

    -- Auto refresh on backpack changes
    local function setupBackpackHooks()
        local bp = player:FindFirstChild("Backpack")
        if not bp then return end
        bp.ChildAdded:Connect(refreshBackpackStats)
        bp.ChildRemoved:Connect(refreshBackpackStats)
    end
    setupBackpackHooks()
    player.CharacterAdded:Connect(function() task.wait(1) setupBackpackHooks() refreshBackpackStats() end)

    -- Periodic refresh (every 5s)
    task.spawn(function()
        while gui.Parent do
            task.wait(5)
            pcall(refreshBackpackStats)
        end
    end)
end

local function refreshPriceList() if refreshBackpackStats then refreshBackpackStats() end end

-- ===== START AUTO LIST (toggle) =====
local stopReq = false
local isRunning = false
BH.getIsRunning = function() return isRunning end  -- v8.176: expose buat Auto-Start toggle
local startGradient
local startGradTask

local function setStartIdle()
    isRunning = false
    startBtn.BackgroundColor3 = C.card
    startBtn.TextColor3 = C.textDim
    startBtn.Text = "⚡ START"
    BH.startStroke.Color = C.accent
    BH.startStroke.Transparency = 0.5
    BH.startStroke.Thickness = 1.5
    -- Stop & remove animated gradient
    if startGradient then
        pcall(function() startGradient:Destroy() end)
        startGradient = nil
    end
end

local function setStartRunning()
    isRunning = true
    -- KEEP background gray (NOT yellow), only animate outline
    startBtn.BackgroundColor3 = C.card
    startBtn.TextColor3 = C.accent
    startBtn.Text = "⏸ STOP"
    BH.startStroke.Color = Color3.fromRGB(255, 255, 255)  -- white base so gradient shows
    BH.startStroke.Thickness = 2
    BH.startStroke.Transparency = 0

    -- Add rotating gradient on outline (sweeping border animation)
    if startGradient then pcall(function() startGradient:Destroy() end) end
    startGradient = Instance.new("UIGradient")
    startGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.accent),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 200)),
        ColorSequenceKeypoint.new(1, C.accent),
    })
    startGradient.Parent = BH.startStroke

    -- Spin the gradient
    task.spawn(function()
        local r = 0
        while isRunning and startGradient and startGradient.Parent do
            r = (r + 4) % 360
            startGradient.Rotation = r
            task.wait(0.03)
        end
    end)
end
setStartIdle()

local function setStats(text, color)
    statsLbl.Text = text
    statsLbl.TextColor3 = color or C.success
end

-- ===== v8.28: BOOTH HELPERS (same BH table from state) =====
do
    function BH.getMyBoothObj()
        if not BH.myBoothUuid then return nil end
        local TW = Workspace:FindFirstChild("TradeWorld")
        local Booths = TW and TW:FindFirstChild("Booths")
        if not Booths then return nil end
        for _, b in ipairs(Booths:GetChildren()) do
            if b.Name:gsub("[{}]","") == BH.myBoothUuid then return b end
        end
        return nil
    end

    function BH.countInBooth(booth, rule)
        if not booth then return 0 end
        local di = booth:FindFirstChild("DynamicInstances")
        if not di then return 0 end
        local count = 0
        for _, t in ipairs(di:GetChildren()) do
            if t:IsA("Tool") then
                local pType = getPetType(t)
                local pBaseType = BH.getBaseName(pType)  -- v8.35: strip mutations
                local baseKg = getBaseKg(t)  -- v8.119: strict APS, nil = skip
                local typeOk = (not rule.type) or rule.type == pBaseType
                local kgOk = baseKg and baseKg >= rule.min and baseKg <= rule.max
                if typeOk and kgOk then count = count + 1 end
            end
        end
        return count
    end

    function BH.countInAllBooths(rule)
        local TW = Workspace:FindFirstChild("TradeWorld")
        local Booths = TW and TW:FindFirstChild("Booths")
        if not Booths then return 0 end
        local total = 0
        for _, b in ipairs(Booths:GetChildren()) do
            total = total + BH.countInBooth(b, rule)
        end
        return total
    end

    function BH.ensureBoothsStreamed()
        local TW = Workspace:FindFirstChild("TradeWorld")
        local Booths = TW and TW:FindFirstChild("Booths")
        if not Booths then return end
        for _, b in ipairs(Booths:GetChildren()) do
            local part = b:FindFirstChildWhichIsA("BasePart", true)
            if part then pcall(function() player:RequestStreamAroundAsync(part.Position) end) end
        end
        task.wait(2)
    end

    -- v8.83: Stream HANYA booth-mu (hemat, fast, no global stream needed)
    -- Multiple rounds untuk reliability. Tujuannya: DynamicInstances ke-load di workspace
    -- biar kita bisa scan UUID listed pet langsung dari Tool.Name.
    function BH.streamMyBooth()
        if not BH.myBoothUuid then return false, "no_booth_uuid" end
        local myBooth = BH.getMyBoothObj()
        if not myBooth then return false, "booth_not_in_workspace" end
        local part = myBooth:FindFirstChildWhichIsA("BasePart", true)
        if not part then return false, "no_basepart" end
        -- v8.84: 2 rounds aja (was 3), total ~0.6s instead of 1.2s
        for i = 1, 2 do
            pcall(function() player:RequestStreamAroundAsync(part.Position) end)
            task.wait(0.3)
        end
        return true, "ok"
    end

    -- v8.84: Smart stream — cuma stream kalo workspace count mismatch TBC
    -- Kalo booth udah ke-stream dari cycle sebelumnya, skip biar gak waste 0.6s tiap cycle
    function BH.streamMyBoothIfNeeded()
        if not BH.myBoothUuid then return false, "no_booth" end
        local myBooth = BH.getMyBoothObj()
        if not myBooth then
            -- Booth gak ada di workspace sama sekali → stream
            return BH.streamMyBooth()
        end
        local di = myBooth:FindFirstChild("DynamicInstances")
        local workspaceCount = di and #di:GetChildren() or 0

        -- Compare with expected count dari TBC
        local expectedCount = 0
        if BH.TBC then
            local data = BH.getMyBoothData()
            if data and data.Listings then
                for _, l in pairs(data.Listings) do
                    if l.ItemType == "Pet" then
                        expectedCount = expectedCount + 1
                    end
                end
            end
        end

        if workspaceCount < expectedCount then
            -- Workspace miss → stream
            return BH.streamMyBooth()
        end
        return true, "cached"  -- workspace already accurate
    end

    function BH.detectMyBooth(listedCleanUuid)
        if BH.myBoothUuid then return end
        task.wait(1)
        local TW = Workspace:FindFirstChild("TradeWorld")
        local Booths = TW and TW:FindFirstChild("Booths")
        if not Booths then return end
        for _, b in ipairs(Booths:GetChildren()) do
            local di = b:FindFirstChild("DynamicInstances")
            if di then
                for _, t in ipairs(di:GetChildren()) do
                    if t.Name:gsub("[{}]","") == listedCleanUuid then
                        BH.myBoothUuid = b.Name:gsub("[{}]","")
                        BH.marketState.myBoothUuid = BH.myBoothUuid
                        BH.saveMarketState(BH.marketState)
                        L("⭐ Booth-mu DETECTED: "..BH.myBoothUuid:sub(1,16).."...")
                        L("  💾 Saved to state.json")
                        return
                    end
                end
            end
        end
    end

    -- v8.40: Detect booth via OWNER attribute (gak perlu list dulu)
    -- Scan semua booth, kalo tool punya OWNER == player.Name → itu booth-mu
    function BH.detectMyBoothByOwner()
        local TW = Workspace:FindFirstChild("TradeWorld")
        local Booths = TW and TW:FindFirstChild("Booths")
        if not Booths then return nil end
        local playerName = player.Name
        for _, b in ipairs(Booths:GetChildren()) do
            local di = b:FindFirstChild("DynamicInstances")
            if di then
                for _, t in ipairs(di:GetChildren()) do
                    if t:IsA("Tool") then
                        local owner = t:GetAttribute("OWNER") or t:GetAttribute("a")
                        if owner and tostring(owner) == playerName then
                            local boothUuid = b.Name:gsub("[{}]","")
                            BH.myBoothUuid = boothUuid
                            BH.marketState.myBoothUuid = boothUuid
                            BH.saveMarketState(BH.marketState)
                            return boothUuid
                        end
                    end
                end
            end
        end
        return nil
    end

    -- v8.41: Detect booth via PROXIMITY player → booth terdekat
    -- Useful setelah click BOOTH button (game auto-TP ke booth claimed)
    function BH.detectMyBoothByProximity(maxDist)
        maxDist = maxDist or 35
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end

        local TW = Workspace:FindFirstChild("TradeWorld")
        local Booths = TW and TW:FindFirstChild("Booths")
        if not Booths then return nil end

        local closest, closestDist = nil, math.huge
        for _, b in ipairs(Booths:GetChildren()) do
            local part = b:FindFirstChildWhichIsA("BasePart", true)
            if part then
                local d = (part.Position - hrp.Position).Magnitude
                if d < closestDist then
                    closestDist = d
                    closest = b
                end
            end
        end

        if closest and closestDist <= maxDist then
            local boothUuid = closest.Name:gsub("[{}]","")
            BH.myBoothUuid = boothUuid
            BH.marketState.myBoothUuid = boothUuid
            BH.saveMarketState(BH.marketState)
            return boothUuid
        end
        return nil
    end

    -- v8.41: Cari + click tombol BOOTH di PlayerGui (game auto-TP)
    function BH.clickBoothButton()
        local pg = player:FindFirstChild("PlayerGui")
        if not pg then return false end

        local found = nil
        for _, gui in ipairs(pg:GetDescendants()) do
            if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                local txt = tostring(gui.Text or ""):lower():gsub("%s","")
                local nm = gui.Name:lower()
                if txt == "booth" or nm == "booth" or (nm:find("booth") and not nm:find("history")) then
                    -- Hindari "Booth History" button
                    if nm ~= "boothhistory" and not nm:find("history") then
                        found = gui
                        break
                    end
                end
            end
            -- Coba juga TextLabel "BOOTH" yang dibungkus parent button
            if gui:IsA("TextLabel") then
                local txt = tostring(gui.Text or ""):lower():gsub("%s","")
                if txt == "booth" then
                    -- Cari parent yang clickable
                    local parent = gui.Parent
                    while parent and parent ~= pg do
                        if parent:IsA("TextButton") or parent:IsA("ImageButton") then
                            found = parent
                            break
                        end
                        parent = parent.Parent
                    end
                    if found then break end
                end
            end
        end

        if not found then return false end

        -- Fire click via getconnections (work di Delta)
        local clicked = false
        pcall(function()
            if getconnections then
                for _, conn in ipairs(getconnections(found.MouseButton1Click)) do
                    pcall(function() conn:Fire() end)
                    clicked = true
                end
                for _, conn in ipairs(getconnections(found.Activated)) do
                    pcall(function() conn:Fire() end)
                    clicked = true
                end
            end
        end)
        return clicked
    end

    -- v8.40: Validate cached UUID still has tools (kalo enggak, clear cache & re-detect)
    -- v8.42: Verify booth ini PUNYA player (sign text atau tool OWNER)
    -- Return: true = punya kita, false = unclaimed, nil = gak bisa verify
    function BH.verifyBoothOwnership(booth)
        if not booth then return nil end
        local playerName = player.Name
        local playerNameLow = playerName:lower()

        -- Method 1: Cek sign text (e.g. "@playerName's Booth")
        local foundUnclaimed = false
        for _, d in ipairs(booth:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                local txt = tostring(d.Text or ""):lower()
                if txt:find(playerNameLow, 1, true) then
                    return true  -- KONFIRM punya kita
                end
                if txt:find("unclaimed", 1, true) then
                    foundUnclaimed = true
                end
            end
        end

        -- Method 2: Cek tool OWNER di DynamicInstances
        local di = booth:FindFirstChild("DynamicInstances")
        if di then
            for _, t in ipairs(di:GetChildren()) do
                if t:IsA("Tool") then
                    local owner = t:GetAttribute("OWNER") or t:GetAttribute("a")
                    if owner and tostring(owner) == playerName then
                        return true  -- KONFIRM via tool OWNER
                    end
                end
            end
        end

        if foundUnclaimed then return false end  -- unclaimed booth
        return nil  -- uncertain
    end

    -- v8.44: Passive detect — TANPA click button (no UI side effects)
    -- Untuk dipanggil di cycle/auto-claim (silent)
    function BH.passiveDetectMyBooth()
        -- v8.46: TBC first — fastest, no streaming dependency
        if BH.TBC then
            local uuid = BH.detectMyBoothFromTBC()
            if uuid then return uuid, "tbc" end
        end

        -- Cached check
        if BH.myBoothUuid then
            local b = BH.getMyBoothObj()
            if b then
                local owned = BH.verifyBoothOwnership(b)
                if owned == true then return BH.myBoothUuid, "cached" end
                if owned == false then
                    BH.myBoothUuid = nil
                    BH.marketState.myBoothUuid = nil
                    BH.saveMarketState(BH.marketState)
                end
            end
        end

        -- Stream + OWNER scan
        BH.ensureBoothsStreamed()
        task.wait(0.5)
        local uuid = BH.detectMyBoothByOwner()
        if uuid then return uuid, "owner" end

        -- Proximity fallback (kalo kebetulan deket booth-mu)
        uuid = BH.detectMyBoothByProximity(35)
        if uuid then
            local owned = BH.verifyBoothOwnership(BH.getMyBoothObj())
            if owned == true then return uuid, "proximity+verified" end
            -- proximity hit booth lain (e.g. lo nyamping booth player lain), batalkan
            BH.myBoothUuid = nil
            BH.marketState.myBoothUuid = nil
            BH.saveMarketState(BH.marketState)
        end

        return nil, "not-found"
    end

    -- v8.41+v8.42: Smart detect (DENGAN click BOOTH btn) — untuk Pantau/explicit use
    function BH.smartDetectMyBooth()
        -- Sudah cached? confirm cepat via getMyBoothObj
        if BH.myBoothUuid then
            local b = BH.getMyBoothObj()
            if b then
                -- Verify kalo masih punya kita (claim mungkin udah un-claimed)
                local owned = BH.verifyBoothOwnership(b)
                if owned == false then
                    -- Cached booth udah unclaimed, clear cache
                    BH.myBoothUuid = nil
                    BH.marketState.myBoothUuid = nil
                    BH.saveMarketState(BH.marketState)
                else
                    return BH.myBoothUuid, "cached"
                end
            end
        end

        -- Method 1: Click BOOTH button → wait → proximity → VERIFY
        local btnClicked = BH.clickBoothButton()
        if btnClicked then
            task.wait(2.5)  -- biar TP done + streaming
            BH.ensureBoothsStreamed()

            -- Cari booth terdekat (manual, JANGAN langsung save)
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local TW = Workspace:FindFirstChild("TradeWorld")
                local Booths = TW and TW:FindFirstChild("Booths")
                if Booths then
                    local closest, closestDist = nil, math.huge
                    for _, b in ipairs(Booths:GetChildren()) do
                        local part = b:FindFirstChildWhichIsA("BasePart", true)
                        if part then
                            local d = (part.Position - hrp.Position).Magnitude
                            if d < closestDist then
                                closestDist = d
                                closest = b
                            end
                        end
                    end

                    if closest and closestDist <= 35 then
                        -- VERIFY ownership SEBELUM save
                        local owned = BH.verifyBoothOwnership(closest)
                        if owned == true then
                            local uuid = closest.Name:gsub("[{}]","")
                            BH.myBoothUuid = uuid
                            BH.marketState.myBoothUuid = uuid
                            BH.saveMarketState(BH.marketState)
                            return uuid, "booth-btn + verified"
                        elseif owned == false then
                            -- BOOTH btn ngarahin ke unclaimed → user belum claim
                            return nil, "user-belum-claim-booth"
                        end
                        -- owned == nil: uncertain, lanjutin coba method lain
                    end
                end
            end
        end

        -- Method 2: OWNER attribute scan (broader scan)
        BH.ensureBoothsStreamed()
        task.wait(1)
        local uuid = BH.detectMyBoothByOwner()
        if uuid then return uuid, "owner attribute" end

        return nil, "tidak-ketemu"
    end

    function BH.validateOrRedetect()
        if BH.myBoothUuid then
            local b = BH.getMyBoothObj()
            if b then
                local di = b:FindFirstChild("DynamicInstances")
                if di and #di:GetChildren() > 0 then return true end  -- valid
                -- empty → could be: empty booth OR streaming not done OR wrong booth
                -- Try owner detect to confirm
                local detected = BH.detectMyBoothByOwner()
                if detected and detected ~= BH.myBoothUuid then
                    L("[State] cached booth UUID stale, re-detected: "..detected:sub(1,16))
                    return true
                end
                return true  -- assume cached is still right, just empty/streaming
            else
                -- Cached booth gak ada di workspace, re-detect
                BH.myBoothUuid = nil
                local detected = BH.detectMyBoothByOwner()
                if detected then
                    L("[State] re-detected booth: "..detected:sub(1,16))
                    return true
                end
                return false
            end
        else
            local detected = BH.detectMyBoothByOwner()
            return detected ~= nil
        end
    end
end


BH.onStartClick = function()
    -- If already running → request stop
    if isRunning then
        stopReq = true
        L("⛔ STOP requested")
        return
    end
    -- v8.129: guard — wajib ada minimal 1 rule sebelum START
    if #listingRules == 0 then
        L("⚠️ Tambah rule LIST HARGA dulu sebelum START")
        if startBtn then
            local origText = startBtn.Text
            local origColor = startBtn.BackgroundColor3
            startBtn.Text = "⚠️ Tambah rule dulu!"
            startBtn.BackgroundColor3 = C.danger
            task.delay(2, function()
                if not isRunning then
                    startBtn.Text = origText
                    startBtn.BackgroundColor3 = origColor
                end
            end)
        end
        return
    end
    -- Start
    setStartRunning()
    task.spawn(function()
        stopReq = false
        L("")
        L("==== START AUTO LIST (Auto-Replenish) ====")
        local delaySec = tonumber(delayBox.Text) or 3
        local maxRetry = tonumber(retryBox.Text) or 2
        local autoRejoinN = tonumber(autoRejoinBox.Text) or 0
        local replenishInterval = 3  -- v8.26: cepat (3s) — begitu sold langsung list

        L("Rules: "..#listingRules)
        for i, r in ipairs(listingRules) do
            local maxStr = r.max == math.huge and "∞" or tostring(r.max)
            local mlStr = (r.maxListings == math.huge or not r.maxListings) and "∞" or tostring(r.maxListings)
            L("  ["..i.."] "..(r.type or "All").." | KG "..r.min.."–"..maxStr.." | 💰"..r.price.." | 📋"..mlStr)
        end
        L("Delay: "..delaySec.." | Replenish interval: "..replenishInterval.."s")

        -- Tracking per rule: UUIDs yang udah kita list
        local myListed = {}
        for i, _ in ipairs(listingRules) do myListed[i] = {} end

        -- v8.48: state flags supaya log gak spam pas backpack habis
        local zeroMatchLogged = {}  -- per rule index, true kalo "0 available" udah di-log
        local wasIdleLastCycle = false
        local idleCyclesCount = 0

        -- v8.76: per-pet rate-limit cooldown tracking
        -- pet yang kena "please wait" di-defer 35 detik biar server cooldown selesai dulu
        local rateLimitedUntil = {}  -- clean_uuid -> tick when can retry
        local rateLimitedCount = {}   -- clean_uuid -> consecutive failures (untuk exponential backoff)
        -- v8.77: GLOBAL rate-limit — pause SEMUA listing kalo server udah mulai rate-limit
        -- Tujuannya: hentiin attempt ke pet lain biar server-side cooldown bisa kelar
        local globalRateLimitUntil = 0
        local globalRateLimitCount = 0

        -- v8.47: TBC data cache (refresh setelah list atau 1s TTL)
        local tbcDataCache = nil
        local tbcDataT = 0
        local function getCachedTbcData()
            local now = tick()
            if not tbcDataCache or (now - tbcDataT) > 1 then
                tbcDataCache = BH.getMyBoothData()
                tbcDataT = now
            end
            return tbcDataCache
        end
        local function invalidateTbcCache()
            tbcDataCache = nil
        end

        local TW = Workspace:FindFirstChild("TradeWorld")
        local Booths = TW and TW:FindFirstChild("Booths")

        -- v8.45: countActive — max(boothScan, sessionTracking)
        -- Mencegah over-list kalo booth scan return 0 (tools gak ke-stream)
        local function countActive(ri)
            local rule = listingRules[ri]
            if not rule then return 0 end
            -- v8.47: auto-init untuk rule yang baru ditambahin saat script lagi running
            if not myListed[ri] then myListed[ri] = {} end

            -- v8.47: TBC available → TRUST it (real-time, auto-update kalo pet kejual/unlist)
            -- Session tracking masih dipake sebagai cap pendek dalam satu cycle iter
            if BH.TBC then
                local tbcCount = BH.countActiveFromData(rule, getCachedTbcData())
                -- Session count (UUID di cycle ini, lebih agresif buat cegah double-list di transition)
                local sessionCount = 0
                for _ in pairs(myListed[ri]) do sessionCount = sessionCount + 1 end
                -- Max: kalo TBC belum update setelah listing baru, session-nya yang cap
                -- TBC dropping (pet kejual) → returns lower → bisa list lagi
                return math.max(tbcCount, sessionCount)
            end

            -- Fallback (no TBC): session + workspace booth max
            local sessionCount = 0
            for _ in pairs(myListed[ri]) do sessionCount = sessionCount + 1 end
            local boothCount = 0
            if BH.myBoothUuid then
                local myBooth = BH.getMyBoothObj()
                if myBooth then boothCount = BH.countInBooth(myBooth, rule) end
            end
            return math.max(sessionCount, boothCount)
        end

        -- Helper: rescan workspace, prune sold/unlisted UUIDs
        local function rescanAndPrune()
            if not Booths then return end
            -- Force-stream
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            for _, b in ipairs(Booths:GetChildren()) do
                local part = b:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    pcall(function() player:RequestStreamAroundAsync(part.Position) end)
                end
            end
            task.wait(2)

            -- For each rule, check which UUIDs still exist
            for ri, uuidSet in pairs(myListed) do
                for uuid, _ in pairs(uuidSet) do
                    local found = false
                    for _, booth in ipairs(Booths:GetChildren()) do
                        local di = booth:FindFirstChild("DynamicInstances")
                        if di then
                            for _, t in ipairs(di:GetChildren()) do
                                if t:IsA("Tool") and t.Name:gsub("[{}]","") == uuid then
                                    found = true; break
                                end
                            end
                        end
                        if found then break end
                    end
                    if not found then
                        myListed[ri][uuid] = nil  -- sold/unlisted, free up slot
                    end
                end
            end
        end

        -- Helper: list pets matching rules (single pass through backpack)
        local function listMatchingPets()
            -- v8.283: kalau rule baru diubah, pause listing 10s (skip cycle).
            if BH.listPauseUntil and tick() < BH.listPauseUntil then
                local sisa = math.ceil(BH.listPauseUntil - tick())
                L("[Listing] pause aktif ("..sisa.."s lagi) — skip cycle")
                return 0
            end
            local bp = player:FindFirstChild("Backpack")
            if not bp then return 0 end

            -- v8.37: build maxKGCache dulu (cache baseKG dari non-mutated buat reuse di mutated)
            BH.buildMaxKGCache()
            local cacheCount = 0
            for _ in pairs(BH.maxKGCache) do cacheCount = cacheCount + 1 end
            if cacheCount > 0 then L("  KG cache built: "..cacheCount.." entries") end

            local pets = {}
            local mutatedDebugCount = 0  -- v8.111: log first 5 mutated pets
            for _, t in ipairs(bp:GetChildren()) do
                if isPet(t) and not isFav(t) then
                    local uuid = tostring(t:GetAttribute("PET_UUID") or t.Name)
                    local clean = uuid:gsub("^{",""):gsub("}$","")
                    local pType = getPetType(t)
                    local pBaseType = BH.getBaseName(pType)  -- v8.35: strip mutations
                    local currentKg = getCurrentKg(t)
                    local baseKg, baseKgSrc = getBaseKg(t)
                    -- v8.119: strict APS-only. baseKg nil = pet ke-skip dari rule matching
                    -- v8.111: detect mutation untuk diagnostic
                    local petName = t.Name or ""
                    local isMut = false
                    for _, prefix in ipairs(BH.MUTATION_PREFIXES or {}) do
                        if petName:sub(1, #prefix) == prefix then isMut = true; break end
                    end
                    if isMut and mutatedDebugCount < 5 then
                        mutatedDebugCount = mutatedDebugCount + 1
                        local age = getAge(t)
                        L("  🔬 MUT#"..mutatedDebugCount..": '"..petName.."'")
                        L("     pType='"..pType.."' pBaseType='"..pBaseType.."'")
                        L("     kg="..tostring(currentKg).." age="..tostring(age)..
                          " baseKg="..tostring(baseKg).." src="..tostring(baseKgSrc or "?"))
                    end
                    table.insert(pets, {
                        braced="{"..clean.."}", clean=clean,
                        type=pType, baseType=pBaseType,
                        wt=baseKg, currentKg=currentKg, wtSrc=baseKgSrc,
                        isMut=isMut, petName=petName,
                    })
                end
            end

            -- v8.36: PRE-SCAN booth-mu → kumpulin UUID yang udah listed (skip nanti)
            -- Pet TETEP ada di backpack walaupun udah listed (game's behavior)
            local alreadyListed = {}
            local alreadyListedCount = 0
            local workspaceCount = 0
            if BH.myBoothUuid then
                local myBooth = BH.getMyBoothObj()
                if myBooth then
                    local di = myBooth:FindFirstChild("DynamicInstances")
                    if di then
                        for _, t in ipairs(di:GetChildren()) do
                            if t:IsA("Tool") then
                                local boothUuid = t.Name:gsub("[{}]","")
                                alreadyListed[boothUuid] = true
                                alreadyListedCount = alreadyListedCount + 1
                                workspaceCount = workspaceCount + 1
                            end
                        end
                    end
                end
            end

            -- v8.81: ALSO build alreadyListed dari TBC (authoritative)
            -- Workspace scan sering miss karena streaming, TBC always accurate
            -- Defensive: coba semua kemungkinan field yang mungkin nyimpan pet UUID
            local tbcAddedCount = 0
            if BH.TBC then
                local data = getCachedTbcData()
                if data and data.Listings then
                    -- Build map: backpack pet UUID → tool ref biar bisa match by attributes
                    local petUuidSet = {}
                    for _, p in ipairs(pets) do petUuidSet[p.clean] = true end

                    for listingKey, listing in pairs(data.Listings) do
                        if listing.ItemType == "Pet" then
                            -- Collect semua kemungkinan UUID dari listing+item
                            local candidates = {}
                            local function addCand(v)
                                if v then
                                    local cv = tostring(v):gsub("[{}]","")
                                    if cv ~= "" then candidates[cv] = true end
                                end
                            end
                            addCand(listingKey)
                            addCand(listing.ItemId)
                            addCand(listing.PetUUID); addCand(listing.PetUuid)
                            local item = data.Items and listing.ItemId and data.Items[listing.ItemId]
                            if item then
                                addCand(item.UUID); addCand(item.Uuid); addCand(item.id); addCand(item.Id); addCand(item.ID)
                                addCand(item.PetUUID); addCand(item.PetUuid)
                                if item.PetData then
                                    local pd = item.PetData
                                    addCand(pd.UUID); addCand(pd.Uuid); addCand(pd.id); addCand(pd.Id); addCand(pd.ID)
                                    addCand(pd.PetUUID); addCand(pd.PetUuid); addCand(pd.PetID); addCand(pd.PetId)
                                end
                            end

                            -- Kalo salah satu candidate match backpack pet → mark alreadyListed
                            for cand, _ in pairs(candidates) do
                                if petUuidSet[cand] and not alreadyListed[cand] then
                                    alreadyListed[cand] = true
                                    alreadyListedCount = alreadyListedCount + 1
                                    tbcAddedCount = tbcAddedCount + 1
                                end
                            end
                        end
                    end
                end
            end

            if BH.myBoothUuid then
                if tbcAddedCount > 0 then
                    L("  Sudah listed di booth-mu: "..alreadyListedCount.." pet (workspace:"..workspaceCount..", TBC:+"..tbcAddedCount..")")
                else
                    L("  Sudah listed di booth-mu: "..alreadyListedCount.." pet")
                end
            else
                L("  Booth belum cached — list dulu 1 buat detect")
            end

            -- v8.34: log how many pets match each rule (v8.35: pakai baseType)
            for ri, r in ipairs(listingRules) do
                local matchCount = 0
                local skipCount = 0
                local mutCount = 0
                -- v8.246: DIAG per-pet — set BH.DEBUG_MATCH=true di console kalo mau cek detail
                if BH.DEBUG_MATCH then
                    L(string.format("[MATCH-DIAG] rule#%d type='%s' min=%s max=%s",
                        ri, tostring(r.type), tostring(r.min), tostring(r.max)))
                end
                for _, p in ipairs(pets) do
                    local typeOk = (not r.type) or r.type == p.baseType
                    -- v8.119: skip pet kalo wt nil (APS gak ada data)
                    local kgOk = p.wt and p.wt >= r.min and p.wt <= r.max
                    if typeOk and BH.DEBUG_MATCH then
                        L(string.format("[MATCH-DIAG]   '%s' wt=%s cur=%s src=%s kgOk=%s (%s..%s)",
                            tostring(p.petName):sub(1,24), tostring(p.wt), tostring(p.currentKg),
                            tostring(p.wtSrc), tostring(kgOk), tostring(r.min), tostring(r.max)))
                    end
                    if typeOk and kgOk then
                        if alreadyListed[p.clean] then
                            skipCount = skipCount + 1
                        else
                            matchCount = matchCount + 1
                            if p.type ~= p.baseType then mutCount = mutCount + 1 end
                        end
                    end
                end
                local extras = {}
                if mutCount > 0 then table.insert(extras, mutCount.." mutated") end
                if skipCount > 0 then table.insert(extras, skipCount.." sudah listed") end
                local info = #extras > 0 and (" ("..table.concat(extras, ", ")..")") or ""

                -- v8.48: log "0 available" ONCE per rule, biar gak spam kalo backpack habis
                if matchCount == 0 then
                    if not zeroMatchLogged[ri] then
                        L("  r"..ri.." ("..(r.type or "All").." "..r.min.."-"..(r.max==math.huge and "∞" or r.max).."): 0 available — abaikan sampai ada pet baru")
                        -- log pet type yang sama (untuk debug kg miss)
                        local sameTypeList = {}
                        for _, p in ipairs(pets) do
                            local typeOk = (not r.type) or r.type == p.baseType
                            if typeOk and not alreadyListed[p.clean] then
                                table.insert(sameTypeList, p)
                            end
                        end
                        if #sameTypeList > 0 then
                            L("    └─ "..#sameTypeList.." "..(r.type or "All").." di backpack TAPI kg gak match:")
                            for i, p in ipairs(sameTypeList) do
                                if i <= 6 then
                                    L(string.format("        • %s: base=%.2f cur=%.2f", p.type, p.wt or 0, p.currentKg or 0))
                                end
                            end
                            if #sameTypeList > 6 then
                                L("        ... +"..(#sameTypeList-6).." more")
                            end
                        end
                        zeroMatchLogged[ri] = true
                    end
                    -- else: silent (udah pernah di-log, abaikan)
                else
                    -- Ada pet match → log normal + reset flag (kalo sebelumnya 0)
                    if zeroMatchLogged[ri] then
                        L("  ▶ r"..ri.." ("..(r.type or "All").."): "..matchCount.." pet baru tersedia!")
                        zeroMatchLogged[ri] = nil
                    end
                    L("  r"..ri.." ("..(r.type or "All").." "..r.min.."-"..(r.max==math.huge and "∞" or r.max).."): "..matchCount.." available"..info)
                end
            end

            local listedNow = 0
            local listAttempts = 0  -- v8.47: pace lister biar gak spam
            -- v8.78: failure tracking per cycle untuk diagnostic summary
            local failStats = {rateLimit=0, favorited=0, equipped=0, invalid=0, boothFull=0,
                              price=0, alreadyListed=0, generic=0, unknown=0}
            -- v8.77: kalo global rate-limit aktif, exit early
            if tick() < globalRateLimitUntil then
                local waitLeft = math.ceil(globalRateLimitUntil - tick())
                L("   ⏸ Global rate-limit aktif — skip cycle ini, wait "..waitLeft.."s")
                setStats("Server rate-limited — pause "..waitLeft.."s", C.danger)
                return 0
            end
            for _, p in ipairs(pets) do
                if stopReq then break end

                -- v8.36: Skip pets yang udah listed di booth-mu
                if not alreadyListed[p.clean] then
                    -- v8.76: Skip pets yang masih dalam rate-limit cooldown
                    local cooldownEnd = rateLimitedUntil[p.clean]
                    if cooldownEnd and tick() < cooldownEnd then
                        -- skip silently (already logged once when first failed)
                    else
                    -- Find matching rule with available slot (v8.35: pakai baseType)
                    local rule, ruleIdx = nil, nil
                    local debugDecisions = nil  -- v8.111: nil until mutated pet seen
                    if #listingRules == 0 then
                        rule = {price = perTypePrices[p.baseType] or perTypePrices[p.type] or 100, maxListings = math.huge}
                        ruleIdx = 0
                    else
                        for ri, r in ipairs(listingRules) do
                            local ml = r.maxListings or math.huge
                            local active = countActive(ri)
                            -- v8.119: skip pet kalo wt nil (APS gak ada data)
                            if p.wt and ((not r.type) or r.type == p.baseType) and p.wt >= r.min and p.wt <= r.max and active < ml then
                                rule, ruleIdx = r, ri
                                break
                            end
                        end
                    end
                    -- v8.183: hide MUT skip spam (was too noisy after v8.180 fix)

                    if rule then
                        -- v8.47: pace BEFORE listPet (always runs, gak peduli result)
                        if listAttempts > 0 then
                            task.wait(delaySec)
                        end
                        listAttempts = listAttempts + 1

                        local mlInfo = ruleIdx > 0 and (" [r"..ruleIdx.."]") or ""
                        L(p.type.." (base "..string.format("%.1f", p.wt).."kg) @ "..rule.price..mlInfo)
                        local ok, idOrErr = listPet(p.braced, rule.price)

                        if ok then
                            -- v8.36: TRUST server response — (true, uuid) = listed
                            -- Pet tetep di backpack (game's behavior), tapi udah ke-list di booth
                            if ruleIdx > 0 then
                                if not myListed[ruleIdx] then myListed[ruleIdx] = {} end  -- v8.47: safe init
                                myListed[ruleIdx][p.clean] = true
                            end
                            listedNow = listedNow + 1
                            alreadyListed[p.clean] = true  -- mark biar cycle ini gak nyoba lagi
                            invalidateTbcCache()  -- v8.47: data baru, force refresh next countActive
                            -- v8.76: clear rate-limit history kalo pet ini akhirnya berhasil
                            rateLimitedCount[p.clean] = nil
                            rateLimitedUntil[p.clean] = nil
                            -- v8.77: reset global counter — server udah accept lagi, kasi kondisi fresh
                            globalRateLimitCount = 0
                            L("   ✅ listing: "..tostring(idOrErr):sub(1,12))
                            setStats("Listed "..listedNow.." this round", C.accent)

                            -- Detect booth pertama kali (kalo belum cached)
                            if not BH.myBoothUuid then
                                task.wait(1)  -- replication delay
                                local TW = Workspace:FindFirstChild("TradeWorld")
                                local Booths = TW and TW:FindFirstChild("Booths")
                                if Booths then
                                    for _, b in ipairs(Booths:GetChildren()) do
                                        local di = b:FindFirstChild("DynamicInstances")
                                        if di then
                                            for _, t in ipairs(di:GetChildren()) do
                                                if t:IsA("Tool") and t.Name:gsub("[{}]","") == p.clean then
                                                    BH.myBoothUuid = b.Name:gsub("[{}]","")
                                                    BH.marketState.myBoothUuid = BH.myBoothUuid
                                                    BH.saveMarketState(BH.marketState)
                                                    L("   ⭐ Booth-mu DETECTED: "..BH.myBoothUuid:sub(1,16))
                                                    L("   💾 Saved to state.json")
                                                    break
                                                end
                                            end
                                        end
                                        if BH.myBoothUuid then break end
                                    end
                                end
                            end
                            -- v8.47: delay udah dipindah ke front (sebelum listPet), gak perlu di sini
                        else
                            -- v8.78: VERBOSE error log — full error + classify + show pet context
                            local errStr = tostring(idOrErr or "false")
                            local errLow = errStr:lower()
                            -- Full error (up to 150 char biar gak terlalu panjang, tapi cukup buat diagnose)
                            local errShow = #errStr > 150 and (errStr:sub(1,150).."...") or errStr
                            local petInfo = string.format("%s base=%.2fkg cur=%.2fkg uuid=%s",
                                p.type, p.wt or 0, p.currentKg or 0, p.clean:sub(1,12))
                            L("   ❌ FAIL ["..petInfo.."]")
                            L("      err: "..errShow)

                            if errLow:find("please wait") or errLow:find("cooldown") or errLow:find("too fast") then
                                failStats.rateLimit = failStats.rateLimit + 1
                                -- v8.76: per-pet cooldown — defer pet ini biar gak ke-retry sebelum server cooldown selesai
                                local failCount = (rateLimitedCount[p.clean] or 0) + 1
                                rateLimitedCount[p.clean] = failCount
                                -- Exponential backoff: 35s → 60s → 90s → max 120s
                                local cooldownSec = math.min(35 + (failCount - 1) * 25, 120)
                                rateLimitedUntil[p.clean] = tick() + cooldownSec
                                L("      → ⏳ RATE-LIMIT, defer "..cooldownSec.."s (fail #"..failCount..")")

                                -- v8.77: GLOBAL pause — stop semua listing biar server cooldown beneran kelar
                                -- Exponential global backoff: 45s → 75s → 105s → max 180s
                                globalRateLimitCount = globalRateLimitCount + 1
                                local globalSec = math.min(45 + (globalRateLimitCount - 1) * 30, 180)
                                globalRateLimitUntil = tick() + globalSec
                                L("      → 🛑 GLOBAL PAUSE "..globalSec.."s (hit #"..globalRateLimitCount..")")
                                setStats("Rate limited — pause "..globalSec.."s", C.danger)
                                break  -- exit for loop, jangan attempt pet berikutnya
                            elseif errLow:find("favorit") then
                                failStats.favorited = failStats.favorited + 1
                                L("      → ⏭ SKIP (favorited, unfav dulu kalo mau di-list)")
                                alreadyListed[p.clean] = true  -- v8.78: mark biar gak retry tiap cycle
                            elseif errLow:find("equip") or errLow:find("equipped") then
                                failStats.equipped = failStats.equipped + 1
                                L("      → ⏭ Pet ke-equip, listPet seharusnya udah unequip — coba lagi cycle nanti")
                            elseif errLow:find("not found") or errLow:find("invalid") or errLow:find("does not exist") then
                                failStats.invalid = failStats.invalid + 1
                                L("      → ⏭ Pet/UUID gak valid (stale data?) — refresh & retry")
                                -- Force re-scan next cycle by invalidating cache
                                invalidateTbcCache()
                            elseif errLow:find("booth") and (errLow:find("full") or errLow:find("limit") or errLow:find("max")) then
                                failStats.boothFull = failStats.boothFull + 1
                                L("      → ⏹ Booth penuh — set maxListings rule lebih rendah")
                                break  -- gak ada gunanya lanjut, semua bakal fail
                            elseif errLow:find("price") or errLow:find("cost") then
                                failStats.price = failStats.price + 1
                                L("      → ⏭ Price issue (kerendahan/ketinggian?) — current: "..rule.price)
                                alreadyListed[p.clean] = true  -- v8.78: mark biar gak spam
                            elseif errLow:find("already") or errLow:find("duplicate") or errLow:find("exists") then
                                failStats.alreadyListed = failStats.alreadyListed + 1
                                L("      → ⏭ Udah listed (state sync issue), mark sebagai listed")
                                alreadyListed[p.clean] = true
                                if ruleIdx > 0 then
                                    if not myListed[ruleIdx] then myListed[ruleIdx] = {} end
                                    myListed[ruleIdx][p.clean] = true
                                end
                                invalidateTbcCache()
                            elseif errStr == "false" or errStr == "unknown" or errStr:sub(1, 8) == "unknown|" then
                                failStats.generic = failStats.generic + 1
                                -- v8.79: server return false tanpa pesan — dump raw response untuk diagnose
                                L("      → ⚠ Generic rejection. Kirim log ini ke developer biar bisa add handler.")
                                -- Cek tool attributes biar tau ada flag aneh
                                local bp = player:FindFirstChild("Backpack")
                                if bp then
                                    local tool = nil
                                    for _, t in ipairs(bp:GetChildren()) do
                                        if t:IsA("Tool") then
                                            local u = t:GetAttribute("PET_UUID")
                                            if u and tostring(u):gsub("[{}]","") == p.clean then
                                                tool = t; break
                                            end
                                        end
                                    end
                                    if tool then
                                        local attrs = {}
                                        for k, v in pairs(tool:GetAttributes()) do
                                            local vs = tostring(v):sub(1, 30)
                                            table.insert(attrs, k.."="..vs)
                                        end
                                        L("      tool attrs: "..table.concat(attrs, ", "))
                                    end
                                end
                                -- v8.80: VERIFY via TBC — listing mungkin actually sukses meski response weird
                                -- (user observation: pet muncul di booth setelah rejoin meski script log "fail")
                                invalidateTbcCache()
                                task.wait(1.5)  -- kasih waktu server replicate
                                local freshData = BH.fetchBoothData(player)
                                if freshData and freshData.Items then
                                    -- v8.81: dump 1 sample item structure (sekali per cycle) biar bisa diagnose UUID field
                                    if failStats.generic == 1 then  -- first generic fail in cycle
                                        for itemId, item in pairs(freshData.Items) do
                                            local fields = {}
                                            table.insert(fields, "itemId="..tostring(itemId):sub(1,16))
                                            for k, v in pairs(item) do
                                                if type(v) ~= "table" then
                                                    table.insert(fields, k.."="..tostring(v):sub(1,20))
                                                end
                                            end
                                            if item.PetData and type(item.PetData) == "table" then
                                                for k, v in pairs(item.PetData) do
                                                    if type(v) ~= "table" then
                                                        table.insert(fields, "pd."..k.."="..tostring(v):sub(1,20))
                                                    end
                                                end
                                            end
                                            L("      TBC item sample: "..table.concat(fields, ", "):sub(1, 300))
                                            break  -- just 1 sample
                                        end
                                    end

                                    -- Cari pet UUID kita di Items (sebagai itemId atau PET_UUID attribute)
                                    local foundListed = false
                                    for itemKey, item in pairs(freshData.Items) do
                                        -- Cek itemKey sendiri (kalo TBC pake pet UUID sebagai key)
                                        if tostring(itemKey):gsub("[{}]","") == p.clean then
                                            foundListed = true; break
                                        end
                                        if item.PetData then
                                            for _, f in ipairs({"UUID","Uuid","PetUUID","PetUuid","id","Id","ID","PetID","PetId"}) do
                                                local v = item.PetData[f]
                                                if v and tostring(v):gsub("[{}]","") == p.clean then
                                                    foundListed = true; break
                                                end
                                            end
                                        end
                                        if foundListed then break end
                                    end
                                    if foundListed then
                                        L("      → ✅ TBC verify: pet TERNYATA listed! Reclassify as success.")
                                        listedNow = listedNow + 1
                                        alreadyListed[p.clean] = true
                                        rateLimitedCount[p.clean] = nil
                                        rateLimitedUntil[p.clean] = nil
                                        if ruleIdx > 0 then
                                            if not myListed[ruleIdx] then myListed[ruleIdx] = {} end
                                            myListed[ruleIdx][p.clean] = true
                                        end
                                        failStats.generic = failStats.generic - 1  -- undo
                                    else
                                        -- v8.81: pet really gak ada di TBC tapi server reject — mark alreadyListed
                                        -- sebagai safety biar gak loop. Restart script kalo ini false positive.
                                        L("      → 🛑 Pet gak ke-detect di TBC tapi server reject. Mark skip biar gak loop.")
                                        alreadyListed[p.clean] = true
                                    end
                                end
                            else
                                failStats.unknown = failStats.unknown + 1
                                L("      → ⚠ Unknown error type — kasih log ini ke developer biar bisa di-handle")
                            end
                        end
                    end
                    end  -- v8.76: end cooldown skip else
                end
            end
            -- v8.78: end-of-cycle failure summary (kalo ada yang fail)
            local totalFails = 0
            for _, n in pairs(failStats) do totalFails = totalFails + n end
            if totalFails > 0 then
                local parts = {}
                if failStats.rateLimit > 0 then table.insert(parts, failStats.rateLimit.." rate-limit") end
                if failStats.favorited > 0 then table.insert(parts, failStats.favorited.." favorited") end
                if failStats.equipped > 0 then table.insert(parts, failStats.equipped.." equipped") end
                if failStats.invalid > 0 then table.insert(parts, failStats.invalid.." invalid-uuid") end
                if failStats.boothFull > 0 then table.insert(parts, failStats.boothFull.." booth-full") end
                if failStats.price > 0 then table.insert(parts, failStats.price.." price-issue") end
                if failStats.alreadyListed > 0 then table.insert(parts, failStats.alreadyListed.." already-listed") end
                if failStats.generic > 0 then table.insert(parts, failStats.generic.." generic-false") end
                if failStats.unknown > 0 then table.insert(parts, failStats.unknown.." unknown") end
                L("│ 📊 Cycle summary: ✅ "..listedNow.." listed | ❌ "..totalFails.." failed → "..table.concat(parts, ", "))
            elseif listedNow > 0 then
                L("│ 📊 Cycle summary: ✅ "..listedNow.." listed (no failures)")
            end
            return listedNow
        end

        -- ============ MAIN AUTO-REPLENISH LOOP ============
        local totalListed = 0
        local cycleNum = 0
        while not stopReq do
            cycleNum = cycleNum + 1
            L("")
            L("==== CYCLE "..cycleNum.." ====")

            -- v8.46+v8.47: stream cuma kalo TBC gak loaded (TBC bypasses streaming entirely)
            -- v8.83: ALWAYS stream booth-mu di awal cycle — workspace scan ngandelin ini
            -- v8.84: tapi pake streamMyBoothIfNeeded → skip kalo workspace count udah match TBC
            if not BH.TBC then
                setStats("Streaming booths...", C.accent)
                BH.ensureBoothsStreamed()
            else
                setStats("Cycle "..cycleNum, C.accent)
                -- Smart stream: cuma kalo perlu (workspace miss vs TBC)
                pcall(BH.streamMyBoothIfNeeded)
                -- Fallback: kalo booth-mu masih belum di workspace setelah smart stream
                if BH.myBoothUuid and not BH.getMyBoothObj() then
                    L("  ⚠ booth-mu belum ke-stream, full stream...")
                    BH.ensureBoothsStreamed()
                end
            end

            -- v8.40+v8.41+v8.44: auto-detect booth PASSIVE (no BOOTH btn click, silent)
            if not BH.myBoothUuid then
                local detected, method = BH.passiveDetectMyBooth()
                if detected then
                    L("⭐ Booth-mu DETECTED (via "..method.."): "..detected:sub(1,16))
                    L("  💾 Saved to state.json")
                else
                    L("⚠ Booth gak ke-detect passive — pakai session fallback")
                end
            end

            -- v8.38: build cache EARLIER (sebelum countActive) biar booth count benar
            BH.buildMaxKGCache()

            -- v8.47: Prune myListed berdasarkan TBC reality
            -- (pet yang udah kejual / unlist → hapus dari session tracking)
            -- Biar count drop ke real, dan cycle bisa list lagi.
            invalidateTbcCache()  -- pastikan fetch fresh data
            if BH.TBC then
                local data = getCachedTbcData()
                if data and data.Listings then
                    local stillListed = {}
                    for _, l in pairs(data.Listings) do
                        if l.ItemId then
                            stillListed[tostring(l.ItemId):gsub("[{}]","")] = true
                        end
                    end
                    for ri, uuidSet in pairs(myListed) do
                        local before = 0
                        for _ in pairs(uuidSet) do before = before + 1 end
                        for u in pairs(uuidSet) do
                            if not stillListed[u] then uuidSet[u] = nil end
                        end
                        local after = 0
                        for _ in pairs(uuidSet) do after = after + 1 end
                        if before ~= after then
                            L("  r"..ri.." pruned: "..before.." → "..after.." (pet kejual/unlisted)")
                        end
                    end
                end
            end

            -- Show current count per rule (real count dari booth scan)
            for ri, r in ipairs(listingRules) do
                local ml = r.maxListings or math.huge
                local cur = countActive(ri)
                local mlStr = ml == math.huge and "∞" or tostring(ml)
                local boothInfo = BH.myBoothUuid and " [my booth]" or " [all booths fallback]"
                L("  r"..ri..": "..cur.."/"..mlStr.." active"..boothInfo)
            end

            -- List new pets
            setStats("Cycle "..cycleNum..": listing...", C.accent)
            local listed = listMatchingPets()
            totalListed = totalListed + listed
            L("Cycle "..cycleNum.." done: "..listed.." new listed (total session: "..totalListed..")")

            -- v8.47: cek backpack drained — DON'T STOP, cuma wait lebih lama
            -- v8.82: account alreadyListed pets — kalo semua backpack pet udah listed, gak ada yang bisa di-fill
            local hasNonFullRule = false
            local canFillSomeRule = false
            local bp = player:FindFirstChild("Backpack")

            -- v8.82: build alreadyListed set dari TBC (sama logic kayak di listMatchingPets)
            local alreadyListedSet = {}
            if BH.TBC then
                local data = getCachedTbcData()
                if data and data.Listings then
                    for listingKey, listing in pairs(data.Listings) do
                        if listing.ItemType == "Pet" then
                            local function _add(v)
                                if v then
                                    local cv = tostring(v):gsub("[{}]","")
                                    if cv ~= "" then alreadyListedSet[cv] = true end
                                end
                            end
                            _add(listingKey); _add(listing.ItemId)
                            local item = data.Items and listing.ItemId and data.Items[listing.ItemId]
                            if item then
                                _add(item.UUID); _add(item.Uuid); _add(item.id); _add(item.Id); _add(item.ID)
                                _add(item.PetUUID); _add(item.PetUuid)
                                if item.PetData then
                                    local pd = item.PetData
                                    _add(pd.UUID); _add(pd.Uuid); _add(pd.id); _add(pd.Id); _add(pd.ID)
                                    _add(pd.PetUUID); _add(pd.PetUuid); _add(pd.PetID); _add(pd.PetId)
                                end
                            end
                        end
                    end
                end
            end
            -- Fallback workspace booth scan
            if BH.myBoothUuid then
                local myBooth = BH.getMyBoothObj()
                if myBooth then
                    local di = myBooth:FindFirstChild("DynamicInstances")
                    if di then
                        for _, t in ipairs(di:GetChildren()) do
                            if t:IsA("Tool") then
                                alreadyListedSet[t.Name:gsub("[{}]","")] = true
                            end
                        end
                    end
                end
            end

            for ri, r in ipairs(listingRules) do
                local ml = r.maxListings or math.huge
                if countActive(ri) < ml then
                    hasNonFullRule = true
                    -- Cek backpack ada pet match rule ini DAN belum listed?
                    if bp then
                        for _, t in ipairs(bp:GetChildren()) do
                            if isPet(t) and not isFav(t) then
                                local petUuid = tostring(t:GetAttribute("PET_UUID") or t.Name):gsub("^{",""):gsub("}$","")
                                if not alreadyListedSet[petUuid] then
                                    local pType = getPetType(t)
                                    local currentKg = getCurrentKg(t)
                                    local baseKg = getBaseKg(t) or currentKg
                                    if (not r.type or r.type == pType)
                                       and baseKg >= r.min and baseKg <= r.max then
                                        canFillSomeRule = true
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                if canFillSomeRule then break end
            end

            -- v8.47: kalo backpack drained, MASUK MODE IDLE (gak STOP)
            -- v8.48: log idle SEKALI per transisi (gak spam tiap cycle)
            local isIdle = (hasNonFullRule and not canFillSomeRule and #listingRules > 0)
            if isIdle then
                idleCyclesCount = idleCyclesCount + 1
                if not wasIdleLastCycle then
                    L("  💤 IDLE — gak ada pet match rules, abaikan sampai ada yang baru")
                    setStats("💤 IDLE — nunggu pet kejual / pet baru", C.textDim)
                end
                wasIdleLastCycle = true
            else
                if wasIdleLastCycle then
                    L("  ▶ RESUME — backpack ada pet baru (idle "..idleCyclesCount.." cycle)")
                    idleCyclesCount = 0
                end
                wasIdleLastCycle = false
            end

            -- Auto-rejoin check
            if autoRejoinN > 0 and totalListed >= autoRejoinN then
                L("🔄 AUTO-REJOIN setelah "..totalListed.." total listed")
                task.wait(1)
                -- v8.233: pakai hopToBestServer (scan 5000 + rame) bukan matchmaking
                if BH.manualHop then
                    L("[AutoRejoin-Listed] pakai hopToBestServer")
                    BH.manualHop()
                else
                    pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
                end
                return
            end

            -- v8.48: idle mode pakai wait 30s (lebih tenang), normal 3s
            local waitTime = isIdle and 30 or replenishInterval

            if not stopReq then
                if not isIdle then
                    setStats("Replenish idle — "..waitTime.."s", C.success)
                end
                for i = 1, waitTime do
                    if stopReq then break end
                    task.wait(1)
                end
            end
        end

        L("==== STOPPED — total listed: "..totalListed.." ====")
        setStats("Stopped — "..totalListed.." total listed", C.success)
        setStartIdle()
    end)
end
startBtn.MouseButton1Click:Connect(BH.onStartClick)

-- v8.179: ONE-SHOT auto-start fire (gak spam). Fire SEKALI begitu siap (max 60s wait for rules).
-- Re-fire mid-session = lewat toggle OFF/ON (v8.176 handler langsung fire)
task.spawn(function()
    task.wait(2)
    L("🚀 [Auto-Start] === STATE DIAGNOSTIC ===")
    if BH.marketState then
        L("🚀   state.autoStart="..tostring(BH.marketState.autoStart).." | rules="..tostring(BH.marketState.listingRules and #BH.marketState.listingRules or "nil"))
    end
    L("🚀   BH.autoStart="..tostring(BH.autoStart).." | listingRules="..#listingRules)

    -- FALLBACK recover dari state
    if (BH.autoStart == nil or BH.autoStart == false) and BH.marketState and BH.marketState.autoStart == true then
        BH.autoStart = true
        L("🚀 [Auto-Start] FALLBACK → ON")
    end

    -- Wait conditions met (max 60s buat handle slow init)
    local maxWait = 60
    local waited = 0
    while gui.Parent and waited < maxWait do
        if not BH.autoStart then
            L("🚀 [Auto-Start] autoStart=OFF, exit (user bisa toggle ON anytime)")
            return
        end
        if isRunning then
            L("🚀 [Auto-Start] isRunning=true, exit (manual start sudah jalan)")
            return
        end
        if #listingRules > 0 then
            L("🚀 [Auto-Start] ✓ FIRING onStartClick (sekali)...")
            local ok, err = pcall(BH.onStartClick)
            L(ok and "🚀 [Auto-Start] ✅ FIRED" or ("✗ [Auto-Start] ❌ "..tostring(err)))
            return  -- ONE-SHOT, exit setelah fire
        end
        task.wait(3)
        waited = waited + 3
    end
    L("⚠ [Auto-Start] timeout (rules tetep kosong selama 60s)")
end)

-- ===== REJOIN (HOP NOW) =====
-- v8.198: explicit hop with comprehensive fallback chain
BH.lastHopClickTime = 0
rejoinBtn.MouseButton1Click:Connect(function()
    -- v8.218: cooldown 10s biar gak rate-limit Roblox API
    local now = os.time()
    if now - BH.lastHopClickTime < 10 then
        local left = 10 - (now - BH.lastHopClickTime)
        L(string.format("⏳ [HopNow] cooldown, tunggu %d detik (anti rate-limit)", left))
        return
    end
    BH.lastHopClickTime = now

    L("==== HOP NOW (click) ====")
    task.spawn(function()
        task.wait(0.3)

        -- v8.210: Cuma 1 step — hopToBestServer (streaming ≥25, fallback 22-24)
        -- Step 2 manual fetch dihapus (redundant + causing low-pop hop bug)
        L("[HopNow] panggil hopToBestServer")
        if BH.manualHop then
            local ok, err = pcall(BH.manualHop)
            L("[HopNow] manualHop returned ok="..tostring(ok).." err="..tostring(err))
        else
            L("[HopNow] BH.manualHop = nil, gak bisa hop")
            return
        end

        -- Hint Anti-Scam kalo masih di server sama
        task.wait(4)
        local current = tostring(game.JobId)
        if game.JobId == current then
            L("⚠ [HopNow] masih di server sama setelah teleport. KEMUNGKINAN game 'Anti Scam' feature aktif.")
            L("    → Buka Settings game (gear ⚙️) → cari 'Anti Scam' → matikan → coba HOP NOW lagi.")
        end
    end)
end)

-- ===== AUTO REJOIN (interval-based) =====
task.spawn(function()
    while gui.Parent do
        task.wait(30) -- check every 30s
        -- v8.237: garden server JANGAN auto-hop (cuma market yg hop)
        if BH.isGardenServer then
            -- skip — garden anchor, gak ikut hop walaupun toggle ON
        elseif autoRejoinToggle.get() then
            local intervalMin = tonumber(intervalBox.Text) or 0
            -- v8.318: PAKSA max 18 menit (cegah kick idle 20m) walau user set lebih tinggi
            if intervalMin <= 0 or intervalMin > 18 then intervalMin = 18 end
            if intervalMin > 0 then
                local elapsedMin = (workspace.DistributedGameTime or 0) / 60
                if elapsedMin >= intervalMin then
                    L("==== AUTO-REJOIN ====")
                    L("Interval "..intervalMin.."min reached ("..string.format("%.1f", elapsedMin).." min elapsed)")
                    task.wait(1)
                    -- v8.233: pake hopToBestServer (scan 5000 + rame) bukan matchmaking
                    if BH.manualHop then
                        L("[AutoRejoin] pakai hopToBestServer (scan rame)")
                        BH.manualHop()
                    else
                        L("[AutoRejoin] fallback matchmaking Teleport")
                        pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
                    end
                    return
                end
            end
        end
    end
end)

-- ===== v8.191: AUTO-REJOIN LOW-POP + ANTI-SAME-SERVER =====
;(function()
    local HttpService = game:GetService("HttpService")
    local STATE_FILE = "pulse_lastServer.json"

    -- Save snapshot server saat ini (sebelum rejoin)
    local function saveServerSnapshot(reason)
        local names = {}
        for _, p in ipairs(Players:GetPlayers()) do
            table.insert(names, p.Name)
        end
        local data = {
            jobId = tostring(game.JobId),
            names = names,
            count = #names,
            time = os.time(),
            reason = reason or "manual",
            retries = 0,
        }
        pcall(function() writefile(STATE_FILE, HttpService:JSONEncode(data)) end)
        L("📸 Saved server snapshot: jobId="..tostring(game.JobId):sub(1,12).." players="..#names.." reason="..tostring(reason))
    end

    -- Hook ke rejoin button + interval auto-rejoin biar nge-save snapshot juga
    rejoinBtn.MouseButton1Click:Connect(function()
        if BH.autoRejoinLowPopToggle.get() then
            saveServerSnapshot("manual_btn")
        end
    end)

    -- v8.194: Helper fetch server list + pick different server (avoid same JobId)
    local function fetchAndHop(reasonLabel)
        -- v8.211: pakai hopToBestServer (streaming ≥25 / fallback 22-24)
        -- ganti logic lama yg filter cuma ≥10 + random
        L("🎯 [Low-Pop] panggil hopToBestServer (reason: "..tostring(reasonLabel)..")")
        if BH.manualHop then
            BH.manualHop()
        else
            L("⚠ [Low-Pop] BH.manualHop nil, fallback Teleport matchmaking")
            pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
        end
    end

    -- Watchdog: tunggu 5 menit dulu (biar server kasih kesempatan populate),
    -- terus cek tiap 30s. Kalo player <10 + toggle ON, hop ke server lain.
    local lastTrigger = 0
    task.spawn(function()
        -- v8.237: garden server gak ikut low-pop hop
        if BH.isGardenServer then
            L("⏰ [Low-Pop] garden server — watchdog DISABLED (anchor)")
            return
        end
        L("⏰ [Low-Pop] standby 5 menit dulu sebelum cek...")
        task.wait(300) -- 5 menit
        L("⏰ [Low-Pop] start watchdog (cek tiap 30s)")
        while gui.Parent do
            task.wait(30)
            if BH.autoRejoinLowPopToggle.get() then
                local count = #Players:GetPlayers()
                if count < 10 and (os.time() - lastTrigger) > 60 then
                    lastTrigger = os.time()
                    L("🔄 [Low-Pop] server cuma "..count.." players (<10), hop server...")
                    saveServerSnapshot("low_pop_"..count)
                    task.wait(1.5)
                    fetchAndHop("low_pop_"..count)
                    return
                end
            end
        end
    end)

    -- INIT: pas script load, cek file. Kalo same server detected, rejoin lagi.
    task.spawn(function()
        task.wait(8) -- tunggu Players:GetPlayers() ke-populate

        -- v8.237: garden server gak ikut same-server re-hop
        if BH.isGardenServer then return end
        if not (isfile and isfile(STATE_FILE)) then return end
        local prev
        local ok = pcall(function()
            prev = HttpService:JSONDecode(readfile(STATE_FILE))
        end)
        if not ok or type(prev) ~= "table" then return end

        if prev.time and (os.time() - prev.time) > 600 then
            pcall(function() delfile(STATE_FILE) end)
            return
        end

        if not BH.autoRejoinLowPopToggle.get() then
            pcall(function() delfile(STATE_FILE) end)
            return
        end

        -- Same JobId = pasti same server
        local currentJobId = tostring(game.JobId)
        local sameJobId = (prev.jobId == currentJobId)

        -- Overlap check via player names
        local currentNamesSet = {}
        for _, p in ipairs(Players:GetPlayers()) do
            currentNamesSet[p.Name] = true
        end
        local overlap = 0
        local prevTotal = #(prev.names or {})
        for _, n in ipairs(prev.names or {}) do
            if currentNamesSet[n] then overlap = overlap + 1 end
        end
        local overlapPct = prevTotal > 0 and (overlap / prevTotal * 100) or 0

        L(string.format("🔍 [Same-Server Check] prev=%s curr=%s | overlap %d/%d (%.0f%%)",
            tostring(prev.jobId):sub(1,12), currentJobId:sub(1,12),
            overlap, prevTotal, overlapPct))

        local retries = (prev.retries or 0)

        if sameJobId or overlapPct >= 50 then
            -- v8.195: NO RAPID RETRY — respect 5-min cooldown
            -- Watchdog akan handle setelah 5 min standby
            L(string.format("⚠ [Same-Server] same server detected (jobId match: %s). Tunggu watchdog cycle berikutnya (5 min).", tostring(sameJobId)))
            -- Keep file BUT mark as 'detected' supaya watchdog tau ini server yg pernah ditinggalin
            prev.retries = (prev.retries or 0) + 1
            prev.detectedAt = os.time()
            pcall(function() writefile(STATE_FILE, HttpService:JSONEncode(prev)) end)
        else
            L("✅ [Same-Server] different server (overlap < 50%), OK")
            pcall(function() delfile(STATE_FILE) end)
        end
    end)
end)()

-- ===== HOP SERVER =====
-- v8.218: simple per-page fetcher dgn retry on fail
local function getServerPage(cursor)
    local req = (syn and syn.request) or (fluxus and fluxus.request)
                or (krnl and krnl.request) or http_request or request or httprequest
    if (http and http.request) then req = http.request end

    local url = "https://games.roblox.com/v1/games/"..tostring(game.PlaceId).."/servers/Public?sortOrder=Desc&limit=100"
    if cursor then url = url .. "&cursor=" .. tostring(cursor) end

    -- Retry up to 3x with exponential backoff (1s, 2s, 4s)
    for attempt = 1, 3 do
        if req then
            local ok, response = pcall(function() return req({Url = url, Method = "GET"}) end)
            if ok and response then
                local body = response.Body or response.body or response.body_string
                local status = response.StatusCode or response.status_code
                if body and (not status or status == 200) then
                    local okd, data = pcall(function() return game:GetService("HttpService"):JSONDecode(body) end)
                    if okd and data and data.data then return data end
                elseif status == 429 then
                    L("[getServerPage] rate limit (429), retry "..attempt.."/3 dgn delay")
                end
            end
        end
        local okg, body = pcall(function() return game:HttpGet(url) end)
        if okg and body then
            local okd, data = pcall(function() return game:GetService("HttpService"):JSONDecode(body) end)
            if okd and data and data.data then return data end
        end

        if attempt < 3 then task.wait(2 ^ attempt) end -- 2s, 4s
    end
    return nil
end

-- v8.208: backwards-compat — collect 100 ≥20-player servers (still used by manual fetch fallback)
local function getServerList()
    local accepted = {}
    local cursor = nil
    local totalScanned = 0
    for page = 1, 20 do
        local data = getServerPage(cursor)
        if not data or not data.data then break end
        totalScanned = totalScanned + #data.data
        for _, s in ipairs(data.data) do
            if (s.playing or 0) >= 20 then
                table.insert(accepted, s)
                if #accepted >= 20 then break end
            end
        end
        if #accepted >= 20 then break end
        cursor = data.nextPageCursor
        if not cursor or cursor == "" then break end
    end
    L(string.format("[getServerList] scanned %d, accepted %d (≥20 players)", totalScanned, #accepted))
    return accepted
end

-- Heuristic: detect Indonesian-style names
-- Indonesian gamers often: short names, vocaloid/anime refs, "ID/IDN" suffix, x_xx patterns
local function looksIndonesian(name)
    local lower = string.lower(name)
    -- Common Indo gamer patterns
    if lower:find("indo") or lower:find("idn") or lower:find("jkt")
       or lower:find("bdg") or lower:find("sby") or lower:find("nkri")
       or lower:find("wibu") or lower:find("kamu") or lower:find("aku") then
        return true
    end
    -- Common Indo names
    for _, n in ipairs({"budi","andi","rizki","rian","aji","dimas","fajar","reza","rama",
                         "anto","yoga","irfan","bayu","arif","papa","mama","saputra","wijaya",
                         "putra","saputri","tan","wati","yanto","yati"}) do
        if lower:find(n, 1, true) then return true end
    end
    return false
end

-- Scan players in current server, return (totalPlayers, indoCount, foreignCount, names)
local function scanCurrentPlayers()
    local total, indo, foreign = 0, 0, 0
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        total = total + 1
        local n = p.DisplayName or p.Name
        local label = n
        if looksIndonesian(n) or looksIndonesian(p.Name) then
            indo = indo + 1
            label = "🇮🇩 "..n
        else
            foreign = foreign + 1
            label = "🌍 "..n
        end
        table.insert(names, label)
    end
    return total, indo, foreign, names
end

-- v8.213: save last hop info biar bisa di-cek di server baru
BH.LAST_HOP_FILE = "pulse_lastHop.json"
BH.saveLastHop = function(tier, server)
    if not writefile then return end
    pcall(function()
        writefile(BH.LAST_HOP_FILE, HttpService:JSONEncode({
            tier = tier,
            playing = server.playing or 0,
            maxPlayers = server.maxPlayers or 30,
            jobId = tostring(server.id):sub(1, 16),
            time = os.time(),
        }))
    end)
end

-- v8.222: detect booth user di baris depan (Y<=6) atau belakang (Y>=8)
-- Keep function buat future use, gak ada auto-action sekarang
BH.BOOTH_Y_THRESHOLD = 7
BH.checkBoothPosition = function()
    local userNameLow = string.lower(player.Name)
    local displayLow = player.DisplayName and string.lower(player.DisplayName) or nil
    local function isMine(b)
        for _, d in ipairs(b:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                local txt = string.lower(tostring(d.Text or ""))
                if string.find(txt, userNameLow, 1, true) then return true end
                if displayLow and string.find(txt, displayLow, 1, true) then return true end
            end
        end
        return false
    end
    local found = nil
    local function scan(parent, depth)
        if depth > 6 or found then return end
        for _, c in ipairs(parent:GetChildren()) do
            if found then return end
            if c.Name == "Booth" and c:IsA("Model") then
                if isMine(c) then
                    local ok, cf = pcall(function() return c:GetPivot() end)
                    if ok then found = {booth = c, pos = cf.Position} end
                end
            end
            pcall(function() scan(c, depth+1) end)
        end
    end
    scan(workspace, 0)
    if found then
        local row = (found.pos.Y <= BH.BOOTH_Y_THRESHOLD) and "DEPAN" or "BELAKANG"
        return found.pos.Y, row, found.booth
    end
    return nil, nil, nil
end

-- v8.225: hitung berapa booth DEPAN yg unclaimed
BH.countFrontUnclaimed = function()
    local count = 0
    local TW = workspace:FindFirstChild("TradeWorld")
    local Booths = TW and TW:FindFirstChild("Booths")
    if not Booths then return 0 end
    for _, parentFolder in ipairs(Booths:GetChildren()) do
        for _, c in ipairs(parentFolder:GetDescendants()) do
            if c.Name == "Booth" and c:IsA("Model") then
                local ok, cf = pcall(function() return c:GetPivot() end)
                if ok and cf.Position.Y <= BH.BOOTH_Y_THRESHOLD then
                    for _, d in ipairs(c:GetDescendants()) do
                        if d:IsA("TextLabel") or d:IsA("TextButton") then
                            local txt = string.lower(tostring(d.Text or ""))
                            if txt:find("unclaimed", 1, true) then
                                count = count + 1
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    return count
end

-- v8.226: function buat switch (dipake dari watchdog + event listener)
BH.autoSwitchCooldown = 0
BH.switchGiveUpUntil = 0
BH.switchAttempts = 0
BH.doAutoSwitch = function(reason)
    if not BH.autoSwitchFrontToggle or not BH.autoSwitchFrontToggle.get() then return end
    local now = tick()

    -- v8.228: give-up window — kalo udah coba 3x fail, give-up 5 menit
    if now < (BH.switchGiveUpUntil or 0) then return end

    -- v8.228: Cooldown 30s antar switch attempt (was 5s, terlalu agresif)
    if now - (BH.autoSwitchCooldown or 0) < 30 then return end
    BH.autoSwitchCooldown = now

    local y, row, currentBooth = BH.checkBoothPosition()
    if not y or row ~= "BELAKANG" then return end

    local frontAvail = BH.countFrontUnclaimed()
    if frontAvail == 0 then return end

    L(string.format("⚡ [AutoSwitch:%s] booth BELAKANG (Y=%.0f), %d DEPAN kosong → SWITCH (attempt #%d)",
        reason or "?", y, frontAvail, (BH.switchAttempts or 0) + 1))
    if removeBoothRE and currentBooth then
        pcall(function() removeBoothRE:FireServer(currentBooth) end)
        task.wait(0.3)
    end
    if BH.tryClaim then task.spawn(function() BH.tryClaim(true) end) end -- v8.229: forceFast

    -- v8.228: verify after 3s (was 5s), kalo masih BELAKANG → count as failed
    task.spawn(function()
        task.wait(3)
        local newY, newRow = BH.checkBoothPosition()
        if newRow == "BELAKANG" then
            BH.switchAttempts = (BH.switchAttempts or 0) + 1
            L(string.format("⚠ [AutoSwitch] masih BELAKANG (Y=%.0f) — attempt %d/3", newY or 0, BH.switchAttempts))
            if BH.switchAttempts >= 3 then
                BH.switchGiveUpUntil = tick() + 300 -- give up 5 menit
                BH.switchAttempts = 0
                L("⚠ [AutoSwitch] 3x gagal — pause 5 menit. Manual claim atau HOP kalo mau coba lagi.")
            end
        else
            -- Sukses dapet depan, reset counter
            BH.switchAttempts = 0
            L(string.format("✅ [AutoSwitch] sukses pindah ke DEPAN (Y=%.0f)", newY or 0))
        end
    end)
end

-- v8.232: INSTANT CLAIM dari event-driven — skip semua scan, pake reference langsung
BH.instantClaimFront = function(unclaimedBoothModel)
    if not BH.autoSwitchFrontToggle or not BH.autoSwitchFrontToggle.get() then return end
    local now = tick()
    if now < (BH.switchGiveUpUntil or 0) then return end
    if now - (BH.autoSwitchCooldown or 0) < 30 then return end
    BH.autoSwitchCooldown = now

    local y, row, currentBooth = BH.checkBoothPosition()
    if not y or row ~= "BELAKANG" then return end

    -- Walk up untuk dapet UUID folder (claimRE expects ini)
    local TW = workspace:FindFirstChild("TradeWorld")
    local Booths = TW and TW:FindFirstChild("Booths")
    if not Booths then return end
    local toClaim = unclaimedBoothModel
    while toClaim and toClaim.Parent and toClaim.Parent ~= Booths do
        toClaim = toClaim.Parent
    end
    if not toClaim or toClaim.Parent ~= Booths then return end

    -- Cek Y biar yakin DEPAN (sanity)
    local ok, cf = pcall(function() return unclaimedBoothModel:GetPivot() end)
    if not ok or cf.Position.Y > BH.BOOTH_Y_THRESHOLD then return end

    -- Get teleport part
    local part = unclaimedBoothModel:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end

    L(string.format("⚡⚡ [InstantClaim] %s Y=%.0f (attempt #%d)",
        toClaim.Name:sub(1, 12), cf.Position.Y, (BH.switchAttempts or 0) + 1))

    -- 1. Release current (instant)
    if removeBoothRE and currentBooth then
        pcall(function() removeBoothRE:FireServer(currentBooth) end)
    end

    -- 2. Teleport + claim IMMEDIATELY (no scan, no extra wait)
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CFrame = part.CFrame + Vector3.new(0, 5, 0) end
    task.wait(0.1) -- minimal biar teleport replicate
    if claimRE then pcall(function() claimRE:FireServer(toClaim) end) end
    L("⚡⚡ [InstantClaim] DONE")

    -- 3. Verify after 3s
    task.spawn(function()
        task.wait(3)
        local newY, newRow = BH.checkBoothPosition()
        if newRow == "BELAKANG" then
            BH.switchAttempts = (BH.switchAttempts or 0) + 1
            L(string.format("⚠ [InstantClaim] masih BELAKANG — attempt %d/3", BH.switchAttempts))
            if BH.switchAttempts >= 3 then
                BH.switchGiveUpUntil = tick() + 300
                BH.switchAttempts = 0
                L("⚠ [InstantClaim] 3x gagal — pause 5 menit")
            end
        else
            BH.switchAttempts = 0
            L(string.format("✅ [InstantClaim] sukses DEPAN (Y=%.0f)", newY or 0))
        end
    end)
end

-- v8.226: event-driven hook untuk INSTANT detect saat front booth ke-unclaim
BH.hookFrontBoothSigns = function()
    local TW = workspace:FindFirstChild("TradeWorld")
    local Booths = TW and TW:FindFirstChild("Booths")
    if not Booths then return 0 end
    local hookCount = 0
    for _, parent in ipairs(Booths:GetChildren()) do
        for _, c in ipairs(parent:GetDescendants()) do
            if c.Name == "Booth" and c:IsA("Model") then
                local ok, cf = pcall(function() return c:GetPivot() end)
                if ok and cf.Position.Y <= BH.BOOTH_Y_THRESHOLD then
                    local boothRef = c -- closure capture
                    for _, d in ipairs(c:GetDescendants()) do
                        if (d:IsA("TextLabel") or d:IsA("TextButton")) and not d:GetAttribute("_pulseHooked") then
                            d:SetAttribute("_pulseHooked", true)
                            pcall(function()
                                d:GetPropertyChangedSignal("Text"):Connect(function()
                                    local txt = string.lower(tostring(d.Text or ""))
                                    if txt:find("unclaimed", 1, true) then
                                        -- v8.232: pakai instant path (skip re-scan)
                                        BH.instantClaimFront(boothRef)
                                    end
                                end)
                                hookCount = hookCount + 1
                            end)
                        end
                    end
                end
            end
        end
    end
    return hookCount
end

-- v8.234: fast scanner — return first front booth unclaimed (gak hitung total)
BH.findFirstFrontUnclaimed = function()
    local TW = workspace:FindFirstChild("TradeWorld")
    local Booths = TW and TW:FindFirstChild("Booths")
    if not Booths then return nil end
    local function scan(parent, depth)
        if depth > 6 then return nil end
        for _, c in ipairs(parent:GetChildren()) do
            if c.Name == "Booth" and c:IsA("Model") then
                local ok, cf = pcall(function() return c:GetPivot() end)
                if ok and cf.Position.Y <= BH.BOOTH_Y_THRESHOLD then
                    for _, d in ipairs(c:GetDescendants()) do
                        if d:IsA("TextLabel") or d:IsA("TextButton") then
                            local txt = string.lower(tostring(d.Text or ""))
                            if txt:find("unclaimed", 1, true) then
                                return c -- FOUND, return early
                            end
                        end
                    end
                end
            else
                local found = scan(c, depth+1)
                if found then return found end
            end
        end
        return nil
    end
    return scan(Booths, 0)
end

-- v8.226: hook signs + polling watchdog (gabungan: instant via event, fallback via polling)
task.spawn(function()
    task.wait(1) -- v8.234: 3s → 1s (immediate start)

    -- v8.234: IMMEDIATE check pas script load (kalo front udah kosong dari awal)
    if BH.autoSwitchFrontToggle and BH.autoSwitchFrontToggle.get() then
        local front = BH.findFirstFrontUnclaimed()
        if front then
            L("⚡⚡ [InstantClaim] FOUND front unclaimed at script load!")
            BH.instantClaimFront(front)
        end
    end

    local n = BH.hookFrontBoothSigns()
    L(string.format("⚡ [AutoSwitch] %d sign DEPAN ke-hook (event-driven)", n))

    while true do
        if BH.autoSwitchFrontToggle and BH.autoSwitchFrontToggle.get() then
            -- v8.234: polling pakai fast path (instantClaimFront) bukan doAutoSwitch slow
            local front = BH.findFirstFrontUnclaimed()
            if front then
                BH.instantClaimFront(front)
            end
        end
        task.wait(2)
    end
end)

-- Hook ulang tiap 60s (handle new signs)
task.spawn(function()
    task.wait(75)
    while true do
        if BH.autoSwitchFrontToggle and BH.autoSwitchFrontToggle.get() then
            local n = BH.hookFrontBoothSigns()
            if n > 0 then L(string.format("⚡ [AutoSwitch] %d sign baru ke-hook", n)) end
        end
        task.wait(60)
    end
end)

-- v8.217: TeleportInitFailed listener buat detect GameFull / fail
BH.teleportFailFlag = false
BH.teleportFailMsg = nil
if not BH.teleportListenerInstalled then
    pcall(function()
        TeleportService.TeleportInitFailed:Connect(function(p, result, errMsg)
            if p == player then
                BH.teleportFailFlag = true
                BH.teleportFailMsg = tostring(errMsg or result)
            end
        end)
    end)
    BH.teleportListenerInstalled = true
end

-- v8.219: avoid collision dgn alt account lain yg pake sc ini (same device)
BH.USERS_FILE = "pulse_activeUsers.json"
BH.savePresence = function(jobId)
    if not writefile or not isfile or not readfile then return end
    pcall(function()
        local data = {}
        if isfile(BH.USERS_FILE) then
            local ok, parsed = pcall(function() return HttpService:JSONDecode(readfile(BH.USERS_FILE)) end)
            if ok and type(parsed) == "table" then data = parsed end
        end
        data[tostring(player.UserId)] = {
            jobId = tostring(jobId or game.JobId),
            name = player.Name,
            time = os.time(),
        }
        writefile(BH.USERS_FILE, HttpService:JSONEncode(data))
    end)
end
BH.getOtherJobIds = function()
    local ids = {}
    if not isfile or not readfile then return ids end
    pcall(function()
        if isfile(BH.USERS_FILE) then
            local data = HttpService:JSONDecode(readfile(BH.USERS_FILE)) or {}
            local myUid = tostring(player.UserId)
            local now = os.time()
            for uid, info in pairs(data) do
                if uid ~= myUid and type(info) == "table" and info.jobId
                    and (now - (info.time or 0)) < 600 then
                    ids[info.jobId] = info.name or uid
                end
            end
        end
    end)
    return ids
end

-- Auto-save current jobId tiap 30s
task.spawn(function()
    while true do
        BH.savePresence(game.JobId)
        task.wait(30)
    end
end)

local function hopToBestServer()
    L("==== HOP SERVER ====")
    local MAX_PAGES = 50  -- v8.221: 5000 server (up from 2000) buat coverage lebih luas
    L(string.format("Scan max %d page (%d server), pick busiest descending: 30→29→28→...", MAX_PAGES, MAX_PAGES*100))

    local currentJobId = tostring(game.JobId)
    local cursor = nil
    local allServers = {}

    -- Step 1: Scan semua page, collect server yg available (bukan current, ada slot)
    for page = 1, MAX_PAGES do
        local data = getServerPage(cursor)
        if not data or not data.data then
            if page == 1 then L("[ERR] page 1 fetch fail") return end
            break
        end
        for _, s in ipairs(data.data) do
            local pl = s.playing or 0
            local maxP = s.maxPlayers or 30
            if s.id ~= currentJobId and pl < maxP then
                table.insert(allServers, s)
            end
        end
        cursor = data.nextPageCursor
        if not cursor or cursor == "" then break end
    end

    if #allServers == 0 then
        L("[ERR] gak ada server available, fallback matchmaking")
        BH.saveLastHop("ULTIMATE", {playing=0, maxPlayers=0, id="matchmaking"})
        pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
        return
    end

    -- Step 2: Sort descending by playing (busiest first: 30, 29, 28, ...)
    table.sort(allServers, function(a, b) return (a.playing or 0) > (b.playing or 0) end)

    -- v8.220: split priority (no alt) vs fallback (with alt) — both sorted busiest first
    local otherIds = BH.getOtherJobIds()
    local otherCount = 0
    for _ in pairs(otherIds) do otherCount = otherCount + 1 end

    local priorityServers = {} -- busiest yg gak ada alt account
    local fallbackServers = {} -- busiest yg ada alt account (used as last resort)
    for _, s in ipairs(allServers) do
        if otherIds[tostring(s.id)] then
            table.insert(fallbackServers, s)
        else
            table.insert(priorityServers, s)
        end
    end

    if otherCount > 0 then
        local names = {}
        for _, n in pairs(otherIds) do table.insert(names, n) end
        L(string.format("[Multi-acc] %d account aktif (%s) | priority:%d server | fallback:%d server",
            otherCount, table.concat(names, ", "), #priorityServers, #fallbackServers))
    end

    L(string.format("Total %d server | top:%d/%d | bottom:%d/%d",
        #allServers,
        allServers[1].playing or 0, allServers[1].maxPlayers or 0,
        allServers[#allServers].playing or 0, allServers[#allServers].maxPlayers or 0))

    -- Step 3: Try priority first (busiest tanpa alt), kalo abis fallback (busiest dgn alt)
    local function tryTeleport(s, label, idx)
        L(string.format("[%s #%d] %d/%d players (jobId=%s)",
            label, idx, s.playing or 0, s.maxPlayers or 0, tostring(s.id):sub(1,12)))
        BH.saveLastHop(label.."_"..idx, s)
        BH.savePresence(s.id)
        BH.teleportFailFlag = false
        BH.teleportFailMsg = nil
        task.wait(0.2)
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, player)
        end)
        if not ok then
            L("[WARN] pcall fail: "..tostring(err).." → next")
            return false
        end
        local waited = 0
        while waited < 3 and not BH.teleportFailFlag do
            task.wait(0.2)
            waited = waited + 0.2
        end
        if BH.teleportFailFlag then
            L("[WARN] teleport gagal: "..tostring(BH.teleportFailMsg).." → next candidate")
            return false
        end
        return true -- success
    end

    -- Priority loop (avoid collision, tetep busiest first)
    local maxPriority = math.min(30, #priorityServers)
    for i = 1, maxPriority do
        if tryTeleport(priorityServers[i], "PRI", i) then return end
    end

    -- v8.221: NO forced fallback ke alt server. Kalo priority habis, langsung matchmaking
    -- (user request: jangan paksa ke 1 server, mending scan lebih banyak)
    if #fallbackServers > 0 then
        L(string.format("[Multi-acc] priority habis (%d), SKIP fallback alt-server, langsung matchmaking", maxPriority))
    end

    -- Ultimate fallback
    L("[ULTIMATE] priority habis → matchmaking (game pilih server)")
    BH.saveLastHop("ULTIMATE", {playing=0, maxPlayers=0, id="matchmaking"})
    pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
end

hopNowBtn.MouseButton1Click:Connect(function() task.spawn(hopToBestServer) end)

-- v8.196: expose hopToBestServer ke BH supaya tombol HOP NOW (rejoin tab) bisa pakai juga
BH.manualHop = function() task.spawn(hopToBestServer) end

-- v8.197: log startup status
task.spawn(function()
    task.wait(2)
    local httpName = "NONE"
    if syn and syn.request then httpName = "syn.request"
    elseif fluxus and fluxus.request then httpName = "fluxus.request"
    elseif krnl and krnl.request then httpName = "krnl.request"
    elseif http_request then httpName = "http_request"
    elseif request then httpName = "request"
    elseif httprequest then httpName = "httprequest"
    elseif http and http.request then httpName = "http.request"
    end
    L(string.format("[Startup] HOP ready=%s | http=%s | jobId=%s",
        tostring(BH.manualHop ~= nil), httpName, tostring(game.JobId):sub(1,12)))

    -- v8.213: cek last hop info
    if isfile and isfile(BH.LAST_HOP_FILE) then
        pcall(function()
            local data = HttpService:JSONDecode(readfile(BH.LAST_HOP_FILE))
            if data and data.time and (os.time() - data.time) < 120 then
                local txt = string.format("Last Hop: tier=%s → %d/%d players (jobId=%s) | %ds ago",
                    tostring(data.tier), tonumber(data.playing) or 0, tonumber(data.maxPlayers) or 0,
                    tostring(data.jobId), os.time() - data.time)
                L("📍 "..txt)
                -- v8.214: auto-copy ke clipboard
                local copyFn = setclipboard or toclipboard or (Clipboard and Clipboard.set)
                if copyFn then
                    pcall(function() copyFn(txt) end)
                    L("📋 [auto-copy] info ke clipboard")
                end
            end
        end)
    end
end)

-- v8.99: ===== HOP SERVER TAB — PLAYER BLACKLIST =====
-- Auto-hop ke server lain kalo ada player blacklisted di server ini
-- v8.101: WRAP dalam function biar punya 200-local quota sendiri (cegah hit main-chunk limit)
BH.hopBlacklist = BH.hopBlacklist or {
    names = {},     -- list of lowercase usernames
    active = false, -- enable auto-hop
}
-- Restore from state
if BH.marketState and BH.marketState.hopBlacklist then
    BH.hopBlacklist.names = BH.marketState.hopBlacklist.names or {}
    BH.hopBlacklist.active = BH.marketState.hopBlacklist.active or false
end

BH.setupHopServerTab = function()
    local function saveHopBlacklist()
    if not BH.marketState then return end
    BH.marketState.hopBlacklist = {
        names = BH.hopBlacklist.names,
        active = BH.hopBlacklist.active,
    }
    pcall(function() BH.saveMarketState(BH.marketState) end)
end

do
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 12) pad.PaddingLeft = UDim.new(0, 14)
    pad.PaddingRight = UDim.new(0, 14) pad.PaddingBottom = UDim.new(0, 14)
    pad.Parent = hopServerPanel

    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 26) title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🚫 PLAYER BLACKLIST"
    title.TextColor3 = C.accent title.Font = FB title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = hopServerPanel

    local desc = Instance.new("TextLabel")
    desc.Size = UDim2.new(1, 0, 0, 18) desc.Position = UDim2.new(0, 0, 0, 28)
    desc.BackgroundTransparency = 1
    desc.Text = "Kalo ada player di list ini join → auto hop ke server lain"
    desc.TextColor3 = C.textDim desc.Font = F desc.TextSize = 11
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.Parent = hopServerPanel

    -- Input row + ADD button
    local inputBox = Instance.new("TextBox")
    inputBox.Size = UDim2.new(0.7, -4, 0, 30) inputBox.Position = UDim2.new(0, 0, 0, 54)
    inputBox.BackgroundColor3 = C.input inputBox.BorderSizePixel = 0
    inputBox.Text = "" inputBox.TextColor3 = C.text
    inputBox.PlaceholderText = "Username yang mau di-blacklist..."
    inputBox.PlaceholderColor3 = C.textDim
    inputBox.Font = F inputBox.TextSize = 12
    inputBox.TextXAlignment = Enum.TextXAlignment.Left
    inputBox.ClearTextOnFocus = false
    inputBox.Parent = hopServerPanel
    Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 5)
    local inputPad = Instance.new("UIPadding")
    inputPad.PaddingLeft = UDim.new(0, 10) inputPad.Parent = inputBox

    local addBtn = Instance.new("TextButton")
    addBtn.Size = UDim2.new(0.3, 0, 0, 30) addBtn.Position = UDim2.new(0.7, 4, 0, 54)
    addBtn.BackgroundColor3 = C.accent addBtn.BorderSizePixel = 0
    addBtn.Text = "+ ADD" addBtn.TextColor3 = Color3.fromRGB(20,20,20)
    addBtn.Font = FB addBtn.TextSize = 12
    addBtn.AutoButtonColor = false addBtn.Parent = hopServerPanel
    Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 5)

    -- Toggle: Auto-hop active
    local toggleRow = Instance.new("Frame")
    toggleRow.Size = UDim2.new(1, 0, 0, 32) toggleRow.Position = UDim2.new(0, 0, 0, 92)
    toggleRow.BackgroundTransparency = 1 toggleRow.Parent = hopServerPanel
    local toggleLbl = Instance.new("TextLabel")
    toggleLbl.Size = UDim2.new(1, -56, 1, 0) toggleLbl.BackgroundTransparency = 1
    toggleLbl.Text = "Auto-hop kalo player blacklisted detected"
    toggleLbl.TextColor3 = C.text toggleLbl.Font = FM toggleLbl.TextSize = 12
    toggleLbl.TextXAlignment = Enum.TextXAlignment.Left toggleLbl.Parent = toggleRow
    local tBg = Instance.new("Frame")
    tBg.Size = UDim2.new(0, 44, 0, 22) tBg.Position = UDim2.new(1, -44, 0.5, -11)
    tBg.BackgroundColor3 = BH.hopBlacklist.active and C.accent or C.input
    tBg.BorderSizePixel = 0 tBg.Parent = toggleRow
    Instance.new("UICorner", tBg).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = BH.hopBlacklist.active and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = Color3.new(1,1,1) knob.BorderSizePixel = 0 knob.Parent = tBg
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(1, 0, 1, 0) toggleBtn.BackgroundTransparency = 1
    toggleBtn.Text = "" toggleBtn.AutoButtonColor = false toggleBtn.Parent = tBg
    toggleBtn.MouseButton1Click:Connect(function()
        BH.hopBlacklist.active = not BH.hopBlacklist.active
        tBg.BackgroundColor3 = BH.hopBlacklist.active and C.accent or C.input
        knob.Position = BH.hopBlacklist.active and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
        saveHopBlacklist()
        L("[Blacklist] auto-hop: "..(BH.hopBlacklist.active and "ON" or "OFF"))
    end)

    -- Status label
    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size = UDim2.new(1, 0, 0, 18) statusLbl.Position = UDim2.new(0, 0, 0, 128)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Text = ""
    statusLbl.TextColor3 = C.textDim statusLbl.Font = F statusLbl.TextSize = 10
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left statusLbl.Parent = hopServerPanel

    -- Blacklist scroll
    local listScroll = Instance.new("ScrollingFrame")
    listScroll.Size = UDim2.new(1, 0, 1, -156)
    listScroll.Position = UDim2.new(0, 0, 0, 152)
    listScroll.BackgroundColor3 = C.card listScroll.BorderSizePixel = 0
    listScroll.ScrollBarThickness = 4 listScroll.ScrollBarImageColor3 = C.accent
    listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    listScroll.Parent = hopServerPanel
    Instance.new("UICorner", listScroll).CornerRadius = UDim.new(0, 6)
    local listLayout = Instance.new("UIListLayout") listLayout.Padding = UDim.new(0, 4)
    listLayout.Parent = listScroll
    local listPad = Instance.new("UIPadding")
    listPad.PaddingTop = UDim.new(0, 4) listPad.PaddingLeft = UDim.new(0, 4)
    listPad.PaddingRight = UDim.new(0, 4) listPad.Parent = listScroll

    local function rebuildBlacklist()
        for _, c in ipairs(listScroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        if #BH.hopBlacklist.names == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, -8, 0, 40) empty.BackgroundTransparency = 1
            empty.Text = "(belum ada player di blacklist)"
            empty.TextColor3 = C.textDim empty.Font = F empty.TextSize = 11
            empty.TextXAlignment = Enum.TextXAlignment.Center
            empty.Parent = listScroll
            listScroll.CanvasSize = UDim2.new(0, 0, 0, 40)
            statusLbl.Text = "Blacklist kosong"
            return
        end
        for idx, name in ipairs(BH.hopBlacklist.names) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -8, 0, 30)
            row.BackgroundColor3 = C.input row.BorderSizePixel = 0
            row.Parent = listScroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size = UDim2.new(1, -38, 1, 0) nameLbl.Position = UDim2.new(0, 10, 0, 0)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Text = "🚫 "..name
            nameLbl.TextColor3 = C.text nameLbl.Font = FM nameLbl.TextSize = 12
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.Parent = row

            local delBtn = Instance.new("TextButton")
            delBtn.Size = UDim2.new(0, 24, 0, 22)
            delBtn.Position = UDim2.new(1, -28, 0.5, -11)
            delBtn.BackgroundColor3 = C.danger
            delBtn.Text = "✕" delBtn.TextColor3 = Color3.new(1,1,1)
            delBtn.Font = FB delBtn.TextSize = 11
            delBtn.BorderSizePixel = 0 delBtn.Parent = row
            Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 4)
            delBtn.MouseButton1Click:Connect(function()
                table.remove(BH.hopBlacklist.names, idx)
                saveHopBlacklist()
                rebuildBlacklist()
            end)
        end
        listScroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
        statusLbl.Text = #BH.hopBlacklist.names.." player blacklisted"
    end

    addBtn.MouseButton1Click:Connect(function()
        local name = inputBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            statusLbl.Text = "❌ ketik username dulu"
            statusLbl.TextColor3 = C.danger
            return
        end
        -- Cek duplikat (case-insensitive)
        local lowName = name:lower()
        for _, existing in ipairs(BH.hopBlacklist.names) do
            if existing:lower() == lowName then
                statusLbl.Text = "❌ "..name.." udah ada di blacklist"
                statusLbl.TextColor3 = C.danger
                return
            end
        end
        table.insert(BH.hopBlacklist.names, name)
        saveHopBlacklist()
        inputBox.Text = ""
        rebuildBlacklist()
        statusLbl.Text = "✅ "..name.." added"
        statusLbl.TextColor3 = C.success
    end)

    rebuildBlacklist()
end

-- v8.99: Background watcher — check current players + listen PlayerAdded
local function checkBlacklistedInServer()
    if not BH.hopBlacklist.active then return end
    if #BH.hopBlacklist.names == 0 then return end
    -- Build lookup set
    local lookup = {}
    for _, n in ipairs(BH.hopBlacklist.names) do
        lookup[n:lower()] = n
    end
    for _, pp in ipairs(Players:GetPlayers()) do
        if pp ~= player then
            local origName = lookup[pp.Name:lower()] or lookup[(pp.DisplayName or ""):lower()]
            if origName then
                L("[Blacklist] 🚫 DETECTED: "..pp.Name.." matches blacklist '"..origName.."' → HOP NOW")
                task.spawn(hopToBestServer)
                return true
            end
        end
    end
    return false
end

-- Initial check (10s after load — biar player udah replicate)
task.spawn(function()
    task.wait(10)
    pcall(checkBlacklistedInServer)
end)

-- PlayerAdded listener — instant detect saat ada yang join
Players.PlayerAdded:Connect(function(pp)
    task.wait(1)  -- wait for full player data
    if not BH.hopBlacklist.active or #BH.hopBlacklist.names == 0 then return end
    for _, n in ipairs(BH.hopBlacklist.names) do
        if pp.Name:lower() == n:lower() or (pp.DisplayName or ""):lower() == n:lower() then
            L("[Blacklist] 🚫 "..pp.Name.." JOINED — blacklisted, HOP NOW")
            pcall(hopToBestServer)
            return
        end
    end
end)

-- Periodic re-check tiap 30s (safety net kalo PlayerAdded miss)
task.spawn(function()
    while gui.Parent do
        task.wait(30)
        pcall(checkBlacklistedInServer)
    end
end)
end  -- end of setupHopServerTab function
BH.setupHopServerTab()  -- v8.101: invoke once at load

-- Scan players button
hopScanBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        L("")
        L("==== SCAN PLAYERS DI SERVER INI ====")
        local total, indo, foreign, names = scanCurrentPlayers()
        L(string.format("Total: %d | 🇮🇩 Indo: %d (%.0f%%) | 🌍 Asing: %d (%.0f%%)",
            total, indo, total > 0 and (indo/total*100) or 0,
            foreign, total > 0 and (foreign/total*100) or 0))
        for _, n in ipairs(names) do L("  "..n) end
        L("================================")
    end)
end)

-- Auto hop loop (when current players drops below min, OR too many Indo players)
-- v8.74: delay configurable via hopDelayBox (default 1 menit, min 0.5 menit = 30 detik)
task.spawn(function()
    while gui.Parent do
        local delayMin = tonumber(hopDelayBox.Text) or 1
        if delayMin < 0.5 then delayMin = 0.5 end  -- safety: minimal 30 detik
        if delayMin > 60 then delayMin = 60 end    -- safety: maksimal 1 jam
        task.wait(delayMin * 60)
        if autoHopToggle.get() then
            local minPlayers = tonumber(hopAutoMinBox.Text) or 0
            local current = #Players:GetPlayers()
            local shouldHop = false
            local reason = ""
            if current <= minPlayers then
                shouldHop = true
                reason = "players ("..current..") ≤ min ("..minPlayers..")"
            elseif hopForeignToggle.get() then
                local total, indo, foreign = scanCurrentPlayers()
                if total > 0 and indo > foreign then
                    shouldHop = true
                    reason = "Indo ("..indo..") > Asing ("..foreign..")"
                end
            end
            if shouldHop then
                L("[AUTO-HOP] "..reason)
                hopToBestServer()
                return
            end
        end
    end
end)

-- ===== UNLIST ALL v4 — no TP, smart cache, logical stream =====
-- v8.32: Pakai BH.myBoothUuid kalo ada → langsung scan booth-mu, no TP
--        Kalo gak ada → brute-force, lalu cache hasil
local function unlistAllInternal()
    L("┌─ UNLIST ALL v4 START ─────────")
    setStats("Cari booth...", C.accent)

    local TW = Workspace:FindFirstChild("TradeWorld")
    if not TW then L("│ ✗ TradeWorld gak ada"); setStats("FAIL: TradeWorld", C.danger); return 0 end
    local Booths = TW:FindFirstChild("Booths")
    if not Booths then L("│ ✗ Booths gak ada"); setStats("FAIL: Booths", C.danger); return 0 end

    -- v8.40+v8.41+v8.44: auto-detect booth PASSIVE kalo belum cached (no BOOTH btn)
    if not BH.myBoothUuid then
        L("│ Booth belum cached, passive-detect...")
        setStats("Detect booth...", C.accent)
        local detected, method = BH.passiveDetectMyBooth()
        if detected then
            L("│ ⭐ Booth detected via "..method..": "..detected:sub(1,16))
            L("│ 💾 Saved")
        end
    end

    -- ===== FAST PATH: kalo booth-mu udah cached =====
    if BH.myBoothUuid then
        L("│ ✓ Booth-mu cached: "..BH.myBoothUuid:sub(1,16))
        local myBooth = BH.getMyBoothObj()
        if myBooth then
            -- Stream HANYA booth-mu (logical, no TP)
            setStats("Stream booth-mu...", C.accent)
            local part = myBooth:FindFirstChildWhichIsA("BasePart", true)
            if part then
                for round = 1, 2 do
                    pcall(function() player:RequestStreamAroundAsync(part.Position) end)
                    task.wait(1)
                end
            end
            task.wait(1)

            -- Scan + unlist langsung
            local di = myBooth:FindFirstChild("DynamicInstances")
            local removed = 0
            if di then
                local tools = di:GetChildren()
                L("│ Tools di booth-mu: "..#tools)
                setStats("Unlisting "..#tools.."...", C.accent)
                for _, t in ipairs(tools) do
                    if stopReq then L("│ ⛔ STOP"); break end
                    if t:IsA("Tool") then
                        local uuid = t.Name:gsub("[{}]","")
                        local ok, ret = pcall(function() return removeRE:InvokeServer(uuid) end)
                        if ok and ret == true then
                            removed = removed + 1
                            L("│ ["..removed.."] ✅ "..uuid:sub(1,12).."...")
                            setStats("Unlisted "..removed, C.accent)
                        else
                            L("│ ⚠ "..uuid:sub(1,12)..": "..tostring(ret))
                        end
                        task.wait(0.3)
                    end
                end
            end
            L("│ Done. Removed: "..removed)
            L("└─────────────────────────")
            setStats(removed > 0 and "✅ Unlisted "..removed or "0 listings di booth", removed > 0 and C.success or C.danger)
            return removed
        else
            L("│ ⚠ Cached booth gak ada di workspace — clear cache")
            BH.myBoothUuid = nil
            BH.marketState.myBoothUuid = nil
            BH.saveMarketState(BH.marketState)
        end
    end

    -- ===== FALLBACK: brute-force, detect booth, cache =====
    L("│ Booth belum cached — brute-force mode")
    setStats("Brute-force (first time)...", C.accent)

    -- Stream parallel all booths (no TP)
    local boothPositions = {}
    for _, b in ipairs(Booths:GetChildren()) do
        local part = b:FindFirstChildWhichIsA("BasePart", true)
        if part then table.insert(boothPositions, part.Position) end
    end
    L("│ Stream "..#boothPositions.." areas, 3 rounds")
    for round = 1, 3 do
        for _, pos in ipairs(boothPositions) do
            pcall(function() player:RequestStreamAroundAsync(pos) end)
        end
        task.wait(1.5)
    end
    task.wait(2)

    -- Collect & brute-force unlist
    local removed = 0
    local rejected = 0
    local detectedBoothObj = nil

    for _, booth in ipairs(Booths:GetChildren()) do
        if stopReq then break end
        if detectedBoothObj and booth ~= detectedBoothObj then
            -- udah ketemu booth-mu, skip
        else
            local di = booth:FindFirstChild("DynamicInstances")
            if di then
                for _, t in ipairs(di:GetChildren()) do
                    if stopReq then break end
                    if t:IsA("Tool") then
                        local uuid = t.Name:gsub("[{}]","")
                        local ok, ret = pcall(function() return removeRE:InvokeServer(uuid) end)
                        task.wait(0.3)
                        if ok and ret == true then
                            removed = removed + 1
                            if not detectedBoothObj then
                                detectedBoothObj = booth
                                BH.myBoothUuid = booth.Name:gsub("[{}]","")
                                BH.marketState.myBoothUuid = BH.myBoothUuid
                                BH.saveMarketState(BH.marketState)
                                L("│ ⭐ BOOTH-MU DETECTED: "..BH.myBoothUuid:sub(1,16))
                                L("│ 💾 Saved — next time gak perlu brute-force")
                            end
                            L("│ ["..removed.."] ✅ "..uuid:sub(1,12).."...")
                            setStats("Unlisted "..removed, C.accent)
                        elseif ok and ret == false then
                            rejected = rejected + 1
                        end
                    end
                end
            end
        end
    end

    L("│ Done. Removed: "..removed.." | Rejected: "..rejected)
    L("└─────────────────────────")
    setStats(removed > 0 and "✅ Unlisted "..removed or "0 listings — booth-mu kosong?", removed > 0 and C.success or C.danger)
    return removed
end
local function runUnlistAll()
    task.spawn(function()
        stopReq = false
        L("")
        local n = unlistAllInternal()
        L("Final removed: "..n)
    end)
end
unlistAllListingBtn.MouseButton1Click:Connect(runUnlistAll)

-- ===== CLAIM BOOTH =====
local function tryClaim(forceFast)
    L("")
    L("==== CLAIM BOOTH ====")
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then L("[skip] no char") return end

    -- v8.229: skip TBC + findMyBooth check kalo forceFast (dipanggil dari Auto-Switch)
    -- karena kita BARU release booth, TBC mungkin masih stale
    if not forceFast then
        if BH.TBC then
            local data = BH.getMyBoothData()
            if data and data.Booth then
                BH.myBoothUuid = data.Booth
                L("[OK] booth-mu udah ada (via TBC): "..tostring(data.Booth):sub(1, 16).."...")
                return
            end
        end
    end

    local TW = Workspace:FindFirstChild("TradeWorld")
    local Booths = TW and TW:FindFirstChild("Booths")
    if not Booths then L("[skip] gak di TradeWorld") return end
    if not forceFast then
        if findMyBooth(Booths) then L("[OK] booth-mu udah ada (via workspace)") return end
    end

    -- v8.227: DEEP SCAN — handle nested struktur Booths.{uuid}.Default.Booth
    local unclaimed = {}
    local function scanDeep(parent, depth)
        if depth > 6 then return end
        for _, c in ipairs(parent:GetChildren()) do
            if c.Name == "Booth" and c:IsA("Model") and getBoothState(c) == "unclaimed" then
                local nearestDist, nearestPart = math.huge, nil
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") then
                        local d = (p.Position - hrp.Position).Magnitude
                        if d < nearestDist then nearestDist=d; nearestPart=p end
                    end
                end
                local pos = nil
                local ok, cf = pcall(function() return c:GetPivot() end)
                if ok then pos = cf.Position end
                if pos and nearestPart then
                    table.insert(unclaimed, {
                        booth = c, pos = pos, part = nearestPart,
                        dist = nearestDist, isFront = (pos.Y <= 7)
                    })
                end
            else
                pcall(function() scanDeep(c, depth+1) end)
            end
        end
    end
    scanDeep(Booths, 0)

    if #unclaimed == 0 then L("[ERR] gak nemu unclaimed booth (deep scan)") return end

    local frontCount, backCount = 0, 0
    for _, u in ipairs(unclaimed) do
        if u.isFront then frontCount = frontCount + 1 else backCount = backCount + 1 end
    end
    L(string.format("Unclaimed: %d depan (Y≤7), %d belakang (Y≥8)", frontCount, backCount))

    table.sort(unclaimed, function(a, b)
        if a.isFront ~= b.isFront then return a.isFront end
        return a.dist < b.dist
    end)

    local target = unclaimed[1]
    local rowLabel = target.isFront and "DEPAN ✓" or "BELAKANG (depan udah habis)"
    L(string.format("Target: %s | %s | Y=%.1f | jarak=%.0f",
        target.booth.Name:sub(1, 12).."...", rowLabel, target.pos.Y, target.dist))
    hrp.CFrame = target.part.CFrame + Vector3.new(0, 5, 0)
    task.wait(0.2)

    -- v8.230: walk up tree — claimRE butuh DIRECT child of Booths (mungkin UUID folder, bukan Booth Model)
    local toClaim = target.booth
    while toClaim and toClaim.Parent and toClaim.Parent ~= Booths do
        toClaim = toClaim.Parent
    end
    if not toClaim or toClaim.Parent ~= Booths then
        L("[ERR] gak nemu argument valid buat claimRE (parent tree weird)")
        return
    end
    L(string.format("Claim arg: %s (Class=%s)", toClaim.Name:sub(1,16), toClaim.ClassName))
    pcall(function() claimRE:FireServer(toClaim) end)
    L("Claimed!")
end
claimBtn.MouseButton1Click:Connect(function() task.spawn(tryClaim) end)
BH.tryClaim = tryClaim -- v8.225: expose biar auto-switch watchdog bisa call

-- ===== AUTO-CLAIM BACKGROUND LOOP (v8.43) =====
-- v8.101: WRAP dalam function biar locals dapet quota tersendiri
BH.setupMiscTab = function()
-- v8.49: pakai TBC sebagai PRIMARY detection (authoritative, fast)
task.spawn(function()
    task.wait(2) -- v8.231: initial cuma 2 detik (sebelumnya 15s) — race start cepet
    local firstRun = true
    while gui.Parent do
        if autoClaimState then
            local hasMyBooth = false

            -- v8.49: Method PRIMARY: TBC (instant + authoritative)
            if BH.TBC then
                local data = BH.getMyBoothData()
                if data and data.Booth then
                    hasMyBooth = true
                    BH.myBoothUuid = data.Booth  -- update cache
                end
            end

            -- Fallback 1: cached booth masih valid?
            if not hasMyBooth and BH.myBoothUuid then
                local b = BH.getMyBoothObj()
                if b then
                    local owned = BH.verifyBoothOwnership(b)
                    if owned == true then hasMyBooth = true end
                end
            end

            -- Fallback 2: scan OWNER attribute (lebih luas)
            if not hasMyBooth then
                local detected = BH.detectMyBoothByOwner()
                if detected then hasMyBooth = true end
            end

            -- Kalo gak punya booth → claim baru
            if not hasMyBooth then
                L("[Auto-Claim] gak punya booth (TBC + 2 fallback miss) → claim...")
                tryClaim()
                task.wait(3)
                BH.passiveDetectMyBooth()
            end
            -- else: silent (don't spam "already have booth" tiap 15s)
        end
        -- v8.231: interval di end loop (first iter immediate, then 15s)
        if firstRun then firstRun = false; task.wait(1) else task.wait(15) end
    end
end)

-- ===== AUTO-EQUIP TOGGLE =====
autoEquipBtn.MouseButton1Click:Connect(function()
    autoEquipState = not autoEquipState
    autoEquipBtn.Text = autoEquipState and "👜 Equip: ON" or "👜 Equip: OFF"
    autoEquipBtn.BackgroundColor3 = autoEquipState and C.success or C.danger
    -- v8.70: persist
    if BH.marketState then BH.marketState.autoEquip = autoEquipState; BH.saveMarketState(BH.marketState) end
end)
local MODES = {"BIGGEST", "RAREST", "RANDOM"}
equipModeBtn.MouseButton1Click:Connect(function()
    for i, m in ipairs(MODES) do
        if m == equipMode then equipMode = MODES[(i % #MODES) + 1]; break end
    end
    equipModeBtn.Text = "📦 "..equipMode
    -- v8.70: persist
    if BH.marketState then BH.marketState.equipMode = equipMode; BH.saveMarketState(BH.marketState) end
end)

-- v8.254: picker JENIS pet — kumpulkan jenis unik dari backpack, pilih satu (atau ALL)
BH.equipTypeBtn.MouseButton1Click:Connect(function()
    -- kumpulkan jenis pet unik di backpack
    local types = {}
    local seen = {}
    local bp = player:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if isPet(t) then
                local nm = BH.getPetName(t)
                if nm and nm ~= "" and not seen[nm] then
                    seen[nm] = true
                    table.insert(types, nm)
                end
            end
        end
    end
    table.sort(types)
    table.insert(types, 1, "ALL")  -- opsi semua jenis di atas

    -- overlay + box picker
    local ov = Instance.new("Frame")
    ov.Size = UDim2.new(1,0,1,0); ov.BackgroundColor3 = Color3.new(0,0,0)
    ov.BackgroundTransparency = 0.5; ov.ZIndex = 60; ov.Parent = gui
    local box = Instance.new("Frame")
    box.Size = UDim2.new(0, 300, 0, 360); box.Position = UDim2.new(0.5, -150, 0.5, -180)
    box.BackgroundColor3 = C.panel; box.BorderSizePixel = 0; box.ZIndex = 61; box.Parent = ov
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)
    local st = Instance.new("UIStroke", box); st.Color = C.accent; st.Thickness = 1.5
    local tt = lblOf(box, "🐾 Pilih Jenis Pet", 14, 10, 250, 22, C.accent, 14, FB)
    tt.ZIndex = 62
    local xb = Instance.new("TextButton")
    xb.Size = UDim2.new(0,26,0,22); xb.Position = UDim2.new(1,-34,0,8)
    xb.BackgroundColor3 = C.danger; xb.Text = "X"; xb.TextColor3 = C.text
    xb.Font = FB; xb.TextSize = 12; xb.ZIndex = 62; xb.Parent = box
    Instance.new("UICorner", xb).CornerRadius = UDim.new(0,6)
    local sb = Instance.new("TextBox")
    sb.Size = UDim2.new(1,-28,0,30); sb.Position = UDim2.new(0,14,0,38)
    sb.BackgroundColor3 = C.card; sb.Text = ""; sb.PlaceholderText = "cari jenis..."
    sb.TextColor3 = C.text; sb.Font = FM; sb.TextSize = 12; sb.ClearTextOnFocus = false
    sb.ZIndex = 62; sb.Parent = box
    Instance.new("UICorner", sb).CornerRadius = UDim.new(0,6)
    local sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.new(1,-20,1,-80); sf.Position = UDim2.new(0,10,0,74)
    sf.BackgroundTransparency = 1; sf.ScrollBarThickness = 3; sf.BorderSizePixel = 0
    sf.CanvasSize = UDim2.new(0,0,0,0); sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.ZIndex = 62; sf.Parent = box
    local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0,4); ll.Parent = sf
    local function build(filter)
        for _, c in ipairs(sf:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        filter = (filter or ""):lower()
        for _, nm in ipairs(types) do
            if filter == "" or nm:lower():find(filter, 1, true) then
                local b = Instance.new("TextButton")
                b.Size = UDim2.new(1,0,0,30); b.BackgroundColor3 = (nm == BH.equipPetType) and C.accent or C.card
                b.Text = (nm == "ALL") and "Semua Jenis" or nm
                b.TextColor3 = (nm == BH.equipPetType) and Color3.fromRGB(17,17,17) or C.text
                b.Font = FM; b.TextSize = 12; b.ZIndex = 63; b.Parent = sf
                Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
                b.MouseButton1Click:Connect(function()
                    BH.equipPetType = nm
                    BH.equipTypeBtn.Text = "🐾 "..(nm == "ALL" and "Semua Jenis" or nm)
                    if BH.marketState then BH.marketState.equipPetType = nm; BH.saveMarketState(BH.marketState) end
                    L("[👜] jenis pet display: "..nm)
                    ov:Destroy()
                end)
            end
        end
    end
    build("")
    sb:GetPropertyChangedSignal("Text"):Connect(function() build(sb.Text) end)
    xb.MouseButton1Click:Connect(function() ov:Destroy() end)
end)

local function getRarityScore(name)
    local s = string.lower(name or "")
    if string.find(s, "nightmare") then return 100 end
    if string.find(s, "rainbow") then return 95 end
    if string.find(s, "venom") then return 90 end
    if string.find(s, "golden") then return 85 end
    if string.find(s, "everchanted") then return 80 end
    if string.find(s, "mythic") then return 75 end
    if string.find(s, "ufo") then return 70 end
    return 0
end

local function getDisplayPet()
    local bp = player:FindFirstChild("Backpack")
    if not bp then return end
    local cand = {}
    for _, t in ipairs(bp:GetChildren()) do
        if isPet(t) and not isFav(t) then
            -- v8.254: filter jenis pet (kalau bukan ALL, cuma equip jenis terpilih)
            local okType = true
            if BH.equipPetType and BH.equipPetType ~= "ALL" then
                okType = (BH.getPetName(t) == BH.equipPetType)
            end
            if okType then
                local wt = tonumber(string.match(t.Name, "%[(%d+%.?%d*)%s*KG%]")) or 0
                table.insert(cand, {tool=t, wt=wt, rarity=getRarityScore(t.Name)})
            end
        end
    end
    if #cand == 0 then return end
    if equipMode == "BIGGEST" then table.sort(cand, function(a,b) return a.wt > b.wt end)
    elseif equipMode == "RAREST" then table.sort(cand, function(a,b)
        if a.rarity ~= b.rarity then return a.rarity > b.rarity end
        return a.wt > b.wt
    end)
    else return cand[math.random(1, #cand)].tool end
    return cand[1].tool, cand[1].wt
end

task.spawn(function()
    while gui.Parent do
        task.wait(4)
        if autoEquipState then
            local char = player.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                -- cek tool yg lagi dipegang
                local heldTool = nil
                for _, c in ipairs(char:GetChildren()) do if c:IsA("Tool") then heldTool = c; break end end
                -- v8.256: kalau jenis dipilih, pastikan pet yg dipegang SESUAI jenis.
                -- kalau pegang pet salah -> unequip dulu biar bisa ganti ke yg bener.
                if heldTool and BH.equipPetType and BH.equipPetType ~= "ALL" and hum then
                    local heldType = isPet(heldTool) and BH.getPetName(heldTool) or nil
                    if heldType ~= BH.equipPetType then
                        -- pet salah / bukan pet -> lepas
                        pcall(function() hum:UnequipTools() end)
                        task.wait(0.3)
                        heldTool = nil
                    end
                end
                if not heldTool and hum then
                    local pet, wt = getDisplayPet()
                    if pet then
                        pcall(function() hum:EquipTool(pet) end)
                        L("[👜] equip "..pet.Name:sub(1, 26))
                    end
                end
            end
        end
    end
end)

-- ===== AUTO-MIGRATE =====
autoMigBtn.MouseButton1Click:Connect(function()
    autoMigState = not autoMigState
    autoMigBtn.Text = autoMigState and "🤖 Auto: ON" or "🤖 Auto: OFF"
    autoMigBtn.BackgroundColor3 = autoMigState and C.success or C.danger
    -- v8.49: persist preferensi user (state file)
    if BH.marketState then
        BH.marketState.autoMigrate = autoMigState
        BH.saveMarketState(BH.marketState)
    end
    L("[Auto-Migrate] "..(autoMigState and "enabled" or "disabled"))
end)

local function detectRows()
    local TW = Workspace:FindFirstChild("TradeWorld")
    local Booths = TW and TW:FindFirstChild("Booths")
    if not Booths then return {} end
    local positions = {}
    for _, b in ipairs(Booths:GetChildren()) do
        if b:IsA("Model") then
            local pp = b.PrimaryPart or b:FindFirstChildWhichIsA("BasePart", true)
            if pp then table.insert(positions, {b=b, p=pp.Position}) end
        end
    end
    if #positions < 4 then return {} end
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, e in ipairs(positions) do
        minX = math.min(minX, e.p.X); maxX = math.max(maxX, e.p.X)
        minZ = math.min(minZ, e.p.Z); maxZ = math.max(maxZ, e.p.Z)
    end
    local useX = (maxX - minX) < (maxZ - minZ)
    local mid = useX and (minX+maxX)/2 or (minZ+maxZ)/2
    local rows = {}
    for _, e in ipairs(positions) do
        local v = useX and e.p.X or e.p.Z
        rows[e.b] = v < mid and "A" or "B"
    end
    return rows
end

local function migrateToFront()
    L("")
    L("==== MIGRATE ====")
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local TW = Workspace:FindFirstChild("TradeWorld")
    local Booths = TW and TW:FindFirstChild("Booths")
    if not Booths then return end
    local mine = findMyBooth(Booths)
    if not mine then L("[skip] gak ada booth") return end
    local rows = detectRows()
    if rows[mine] == "A" then L("[OK] udah di front") return end
    local nearestDist, target, part = math.huge, nil, nil
    for _, b in ipairs(Booths:GetChildren()) do
        if b:IsA("Model") and getBoothState(b) == "unclaimed" and rows[b] == "A" then
            for _, p in ipairs(b:GetDescendants()) do
                if p:IsA("BasePart") then
                    local d = (p.Position - hrp.Position).Magnitude
                    if d < nearestDist then nearestDist=d; target=b; part=p end
                end
            end
        end
    end
    if not target then L("[skip] gak ada front kosong") return end
    L("Target: "..target.Name:sub(1,12).."...")
    L("Step 1: unlist")
    unlistAllInternal()
    task.wait(1)
    L("Step 2: remove booth")
    if removeBoothRE then pcall(function() removeBoothRE:FireServer(mine) end) end
    task.wait(1.5)
    L("Step 3: TP + claim front")
    hrp.CFrame = part.CFrame + Vector3.new(0, 5, 0)
    task.wait(1)
    pcall(function() claimRE:FireServer(target) end)
    L("Done")
end
migNowBtn.MouseButton1Click:Connect(function() task.spawn(migrateToFront) end)

task.spawn(function()
    while gui.Parent do
        task.wait(15)
        if autoMigState then
            local TW = Workspace:FindFirstChild("TradeWorld")
            local Booths = TW and TW:FindFirstChild("Booths")
            if Booths then
                local mine = findMyBooth(Booths)
                local rows = detectRows()
                if mine and rows[mine] == "B" then
                    local hasFrontEmpty = false
                    for _, b in ipairs(Booths:GetChildren()) do
                        if b:IsA("Model") and rows[b] == "A" and getBoothState(b) == "unclaimed" then
                            hasFrontEmpty = true; break
                        end
                    end
                    if hasFrontEmpty then
                        L("[AUTO-MIG] front kosong, migrating...")
                        migrateToFront()
                    end
                end
            end
        end
    end
end)

-- ===== SKIN PICKER (open standalone) =====
skinPickBtn.MouseButton1Click:Connect(function()
    L("==== SKIN PICKER ====")
    L("Buka skin selector di game manual (tap booth → skin)")
    L("Kalo udah kebuka, klik tile yang ada di UI game itu")
    L("Atau jalanin booth_skin_v2.lua secara terpisah")
end)
end  -- end setupMiscTab
BH.setupMiscTab()  -- v8.101: invoke once

-- ===== SNIPE SCANNER =====
BH.setupSnipeScanner = function()
-- v8.69: parseMutation pake BH.MUTATION_NAMES (lengkap ~90 mutations) via getBaseName
-- Otomatis handle multi-layer mutation ("Shocked, Galactic Peacock" → "Shocked, Galactic")
local function parseMutation(name, baseType)
    if not name or name == "" then return "-" end
    -- Strip "[Age X]" "[X KG]" dulu → display name aja
    local petName = name:match("^(.-)%s*%[") or name
    -- Strip mutation prefix berlapis → dapet base name
    local base = BH.getBaseName(petName)
    if base == petName then return "-" end  -- pet biasa, no mutation
    -- Mutation = petName minus base (trim trailing comma/space)
    local mut = petName:sub(1, #petName - #base):gsub("[,%s]+$", "")
    return mut ~= "" and mut or "-"
end

local function findPriceForTool(tool, booth)
    -- Try direct attributes first
    for _, attr in ipairs({"Price","PRICE","p","price","ListingPrice","listingPrice","Cost","COST"}) do
        local v = tool:GetAttribute(attr)
        if v and tonumber(v) and tonumber(v) > 0 then return tonumber(v) end
    end
    -- Try to find price label in booth GUI (above the pet)
    if booth then
        for _, d in ipairs(booth:GetDescendants()) do
            if d:IsA("TextLabel") then
                local txt = tostring(d.Text or "")
                local num = string.match(txt, "(%d[%d,%.]*)%s*$")
                if num then
                    num = tostring(num):gsub(",", "")
                    local n = tonumber(num)
                    if n and n > 0 and n < 1e12 then
                        -- Heuristic: label near this tool's name
                        local toolType = tool:GetAttribute("f")
                        if toolType and string.find(string.lower(d.Name or ""), "price") then
                            return n
                        end
                    end
                end
            end
        end
    end
    return nil
end

local scanCache = {}
local scanDiag = "(belum scan)"

local function scanBoothListings()
    scanCache = {}
    L("======= SNIPE SCAN START (TBC) =======")

    -- v8.46: Use TBC.GetPlayerBoothData → iterate all players, no streaming
    if BH.TBC then
        local totalPlayers = 0
        local boothsFound = 0
        local listingsTotal = 0
        local mineCount = 0

        for _, pp in ipairs(Players:GetPlayers()) do
            totalPlayers = totalPlayers + 1
            local data = BH.fetchBoothData(pp)
            if data and data.Booth and data.Listings then
                boothsFound = boothsFound + 1
                for listingUuid, listing in pairs(data.Listings) do
                    listingsTotal = listingsTotal + 1
                    if listing.ItemType == "Pet" and listing.ItemId then
                        local item = data.Items and data.Items[listing.ItemId]
                        if item and item.PetData then
                            local pd = item.PetData
                            local kg = BH.computeBaseKgFromPetData(pd)
                            local mut = tostring(pd.MutationType or "")
                            local pType = tostring(item.PetType or "?")
                            local petNick = tostring(pd.Name or "")
                            -- v8.258: asal egg (buat filter prem vs biasa)
                            local hatchedFrom = tostring(pd.HatchedFrom or "")
                            local isPrem = hatchedFrom:lower():find("premium") ~= nil
                            -- Combined search-friendly name
                            local searchName = pType
                            if mut ~= "" then searchName = mut.." "..searchName end
                            if petNick ~= "" then searchName = searchName.." ~"..petNick end

                            local isMine = (pp == player)
                            if isMine then mineCount = mineCount + 1 end

                            table.insert(scanCache, {
                                type = pType,
                                mutation = (mut ~= "" and mut or "-"),
                                age = tonumber(pd.Level) or 0,
                                kg = kg,
                                price = tonumber(listing.Price) or 0,
                                owner = pp.Name,
                                sellerPlayer = pp,  -- v8.48: simpan player ref buat buy
                                name = searchName,
                                listingUuid = listingUuid,
                                itemId = listing.ItemId,
                                boothUuid = data.Booth,
                                isMine = isMine,
                                hatchedFrom = hatchedFrom,  -- v8.258
                                isPrem = isPrem,            -- v8.258
                            })
                        end
                    end
                end
            end
        end

        L(string.format("Players:%d | Booths:%d | Listings:%d | Cached:%d | Mine:%d",
            totalPlayers, boothsFound, listingsTotal, #scanCache, mineCount))
        L("======= SCAN END =======")
        scanDiag = string.format("Players:%d Booths:%d Listings:%d Mine:%d",
            totalPlayers, boothsFound, listingsTotal, mineCount)
        -- v8.87: expose scanCache via BH for buildRuleRow count badges
        BH.scanCache = scanCache
        BH.scanCacheTime = tick()
        -- Notify LIST HARGA tab to refresh counts
        if BH.refreshPriceCounts then pcall(BH.refreshPriceCounts) end
        return
    end

    -- Fallback: workspace scan (kalo TBC gak loaded)
    L("⚠ TBC gak loaded, fallback ke workspace scan")
    local diagLines = {}

    -- Inspect workspace top level (always log so user can see)
    local wsTop = {}
    for _, c in ipairs(Workspace:GetChildren()) do
        table.insert(wsTop, c.Name)
    end
    L("Workspace top ("..#wsTop.."): "..table.concat(wsTop, ", "):sub(1, 150))

    -- Try multiple paths to find booths
    local TW = Workspace:FindFirstChild("TradeWorld")
    local Booths
    if TW then
        table.insert(diagLines, "TW✓")
        L("✓ TradeWorld found")
        local twChildren = {}
        for _, c in ipairs(TW:GetChildren()) do table.insert(twChildren, c.Name) end
        L("TradeWorld children: "..table.concat(twChildren, ", "):sub(1, 150))
        Booths = TW:FindFirstChild("Booths")
    else
        table.insert(diagLines, "TW✗")
        L("✗ TradeWorld NOT in Workspace top — kamu mungkin di area lain")
    end
    if not Booths then
        Booths = Workspace:FindFirstChild("Booths")
        if Booths then
            table.insert(diagLines, "Booths(alt)✓")
            L("✓ Booths found at Workspace.Booths")
        end
    else
        table.insert(diagLines, "Booths✓")
        L("✓ Booths found at Workspace.TradeWorld.Booths")
    end
    if not Booths then
        -- Recursive search for any folder/model named "Booths"
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d.Name == "Booths" and (d:IsA("Folder") or d:IsA("Model")) then
                Booths = d
                table.insert(diagLines, "Booths(search)✓")
                L("✓ Booths found via search at "..d:GetFullName())
                break
            end
        end
    end
    if not Booths then
        scanDiag = "Booths gak nemu — coba TP ke Trade World"
        L("✗ Booths gak ditemukan dimanapun")
        L("→ Coba klik booth/trade area di game dulu biar streaming load")
        L("======= SCAN END (FAIL) =======")
        return
    end

    -- =========== FORCE STREAMING around all booths ===========
    -- Game pake StreamingEnabled, jadi tools di booth jauh gak ke-load.
    -- Pake RequestStreamAroundAsync biar server load semua area booth.
    local boothPositions = {}
    for _, booth in ipairs(Booths:GetChildren()) do
        if booth:IsA("Model") or booth:IsA("Folder") then
            local pos = nil
            -- Try various ways to find booth position
            local defaultModel = booth:FindFirstChild("Default")
            if defaultModel then
                if defaultModel:IsA("Model") and defaultModel.PrimaryPart then
                    pos = defaultModel.PrimaryPart.Position
                else
                    local part = defaultModel:FindFirstChildWhichIsA("BasePart", true)
                    if part then pos = part.Position end
                end
            end
            if not pos then
                local part = booth:FindFirstChildWhichIsA("BasePart", true)
                if part then pos = part.Position end
            end
            if pos then table.insert(boothPositions, pos) end
        end
    end
    L("Force-streaming "..#boothPositions.." booth areas...")
    for _, pos in ipairs(boothPositions) do
        pcall(function() player:RequestStreamAroundAsync(pos) end)
    end
    L("Wait 3 detik biar streaming load semua tools...")
    task.wait(3)

    local boothCount, dynCount, toolCount, mineCount = 0, 0, 0, 0
    local plantCount, petCount, otherCount = 0, 0, 0
    local firstToolDumped = false
    for _, booth in ipairs(Booths:GetChildren()) do
        if booth:IsA("Model") or booth:IsA("Folder") then
            boothCount = boothCount + 1
            local di = booth:FindFirstChild("DynamicInstances")
            if di then
                dynCount = dynCount + 1
                for _, tool in ipairs(di:GetChildren()) do
                    if tool:IsA("Tool") then
                        toolCount = toolCount + 1

                        -- Dump structure of first tool encountered (one time only)
                        if not firstToolDumped then
                            firstToolDumped = true
                            L("--- Sample Tool dari booth ---")
                            L("  Name: "..tool.Name:sub(1, 36))
                            local attrs = {}
                            for k, v in pairs(tool:GetAttributes()) do
                                table.insert(attrs, k.."="..tostring(v):sub(1,15))
                            end
                            L("  Attrs("..#attrs.."): "..table.concat(attrs, ", "):sub(1, 200))
                            local kids = {}
                            for _, c in ipairs(tool:GetChildren()) do
                                table.insert(kids, c.ClassName.."'"..c.Name.."'")
                            end
                            L("  Kids: "..table.concat(kids, ", "):sub(1, 150))
                        end

                        -- Filter: pet vs plant via ItemType attribute
                        local itemType = tool:GetAttribute("ItemType")
                            or tool:GetAttribute("PetType")
                            or tool:GetAttribute("itemType")

                        if itemType == "Pet" then petCount = petCount + 1
                        elseif itemType then plantCount = plantCount + 1
                        else otherCount = otherCount + 1 end

                        -- Owner detection
                        local owner = tool:GetAttribute("OWNER")
                            or tool:GetAttribute("Owner")
                            or tool:GetAttribute("a")
                            or tool:GetAttribute("Seller")
                            or "?"

                        if owner == player.Name then
                            mineCount = mineCount + 1
                        elseif itemType == "Pet" then  -- ONLY scan pets (skip plants)
                            local pType = tostring(tool:GetAttribute("f") or "?")

                            -- Weight from name or child or attribute
                            local kg = 0
                            local wChild = tool:FindFirstChild("Weight")
                            if wChild and wChild:IsA("ValueBase") then
                                kg = tonumber(wChild.Value) or 0
                            end
                            if kg == 0 then
                                kg = tonumber(string.match(tool.Name, "%[([%d%.]+)%s*[Kk][Gg]%]")) or 0
                            end

                            -- Age (best effort — most pet names don't have it)
                            local age = 0
                            local aChild = tool:FindFirstChild("Age")
                            if aChild and aChild:IsA("ValueBase") then
                                age = tonumber(aChild.Value) or 0
                            end
                            if age == 0 then
                                age = tonumber(string.match(tool.Name, "%[Age%s+(%d+)%]")) or 0
                            end

                            -- Mutation from name (e.g. "Venom Peacock [...]")
                            local mut = parseMutation(tool.Name, pType)
                            local price = findPriceForTool(tool, booth)
                            table.insert(scanCache, {
                                type = pType, mutation = mut, age = age, kg = kg,
                                price = price, owner = owner, tool = tool,
                                booth = booth, name = tool.Name,
                            })
                        end
                    end
                end
            end
        end
    end
    L(string.format("Booths:%d | DynInst:%d | Tools:%d (🐾Pet:%d, 🌱Plant:%d, ?:%d)",
        boothCount, dynCount, toolCount, petCount, plantCount, otherCount))
    L(string.format("Mine:%d | Found Pet listings: %d", mineCount, #scanCache))

    -- If 0 tools, sample first booth's structure
    if toolCount == 0 and boothCount > 0 then
        L("⚠ Booths ada tapi 0 tools. Sample booth structure:")
        local sampleBooth = Booths:GetChildren()[1]
        if sampleBooth then
            L("  '"..sampleBooth.Name.."' ("..sampleBooth.ClassName..")")
            for _, c in ipairs(sampleBooth:GetChildren()) do
                L("    "..c.ClassName.." '"..c.Name.."' ("..#c:GetChildren().." kids)")
            end
        end
    end
    L("======= SCAN END =======")

    scanDiag = string.format("Booths:%d Tools:%d Mine:%d Found:%d",
        boothCount, toolCount, mineCount, #scanCache)
    -- v8.87: expose scanCache via BH for buildRuleRow count badges
    BH.scanCache = scanCache
    BH.scanCacheTime = tick()
    if BH.refreshPriceCounts then pcall(BH.refreshPriceCounts) end
end

local function renderSnipe()
    for _, c in ipairs(snScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    local sf = string.lower(snSearch.Text or "")
    local minAge = tonumber(snMinAge.Text) or 0
    local maxAge = tonumber(snMaxAge.Text) or math.huge
    local minKg = tonumber(snMinKg.Text) or 0
    local maxKg = tonumber(snMaxKg.Text) or math.huge
    local minPrice = tonumber(snMinPrice.Text) or 0
    local maxPrice = tonumber(snMaxPrice.Text) or math.huge

    local shown = 0
    for _, p in ipairs(scanCache) do
        local nameMatch = sf == "" or string.find(string.lower(p.name), sf, 1, true)
            or string.find(string.lower(p.type), sf, 1, true)
        local ageOk = p.age >= minAge and p.age <= maxAge
        local kgOk = p.kg >= minKg and p.kg <= maxKg
        local priceOk = true
        if p.price then
            priceOk = p.price >= minPrice and p.price <= maxPrice
        end
        if nameMatch and ageOk and kgOk and priceOk then
            shown = shown + 1
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -8, 0, 32) row.BackgroundColor3 = C.input
            row.BorderSizePixel = 0 row.Parent = snScroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

            local function cell(text, x, w, color, font, size)
                local l = Instance.new("TextLabel")
                l.Size = UDim2.new(w, -4, 1, 0) l.Position = UDim2.new(x, 4, 0, 0)
                l.BackgroundTransparency = 1 l.Text = tostring(text)
                l.TextColor3 = color or C.text
                l.Font = font or FM l.TextSize = size or 11
                l.TextXAlignment = Enum.TextXAlignment.Left
                l.TextTruncate = Enum.TextTruncate.AtEnd l.Parent = row
            end
            -- v8.47: layout baru — Type | Mutation | KG | Owner (tengah) | Price | BUY
            -- v8.267: nama pet MERAH kalau dari egg prem, PUTIH kalau egg biasa
            local nameColor = p.isPrem and Color3.fromRGB(255, 80, 80) or C.text
            cell(p.type, 0, 0.20, nameColor, FB)
            cell(p.mutation, 0.20, 0.14, C.accent)
            cell(string.format("%.1f", p.kg), 0.34, 0.10, C.textDim)
            cell(p.owner:sub(1, 12), 0.44, 0.22, C.textDim)  -- owner di TENGAH
            cell(p.price and tostring(p.price) or "?", 0.66, 0.14,
                p.price and C.accent or C.textDim, FB)

            -- BUY button (langsung sebelah price)
            local buyBtn = Instance.new("TextButton")
            buyBtn.Size = UDim2.new(0.18, -4, 0, 24)
            buyBtn.Position = UDim2.new(0.80, 4, 0.5, -12)
            buyBtn.BackgroundColor3 = (p.price and p.listingUuid) and C.success or C.textDim
            buyBtn.Text = "💰 BUY"
            buyBtn.TextColor3 = Color3.new(1, 1, 1)
            buyBtn.Font = FB buyBtn.TextSize = 11
            buyBtn.BorderSizePixel = 0
            buyBtn.AutoButtonColor = (p.listingUuid ~= nil)
            buyBtn.Parent = row
            Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 4)

            if p.listingUuid then
                buyBtn.MouseButton1Click:Connect(function()
                    if not buyRE then
                        buyBtn.Text = "✗ NO RE"
                        buyBtn.BackgroundColor3 = C.danger
                        return
                    end
                    buyBtn.Text = "..."
                    buyBtn.BackgroundColor3 = C.accent
                    task.spawn(function()
                        local clean = tostring(p.listingUuid):gsub("[{}]","")
                        local seller = p.sellerPlayer

                        -- v8.72: format confirmed via debug hook capture:
                        -- BuyListing:InvokeServer(sellerPlayer, listingUuidClean)
                        if not seller then
                            buyBtn.Text = "✗ NO SELLER"
                            buyBtn.BackgroundColor3 = C.danger
                            L("[Buy] ❌ sellerPlayer is nil — re-scan dulu")
                            return
                        end

                        local ok, r1, r2 = pcall(function()
                            return buyRE:InvokeServer(seller, clean)
                        end)
                        L("[Buy] result: ok="..tostring(ok)
                            .." r1="..tostring(r1):sub(1,40)
                            .." r2="..tostring(r2):sub(1,40))

                        -- Success kriteria: pcall ok + r1 not false/error string
                        -- Server return bisa: true | nil | "OK" | error string
                        local success = ok and (r1 == true or r1 == nil or r1 == "OK"
                            or (type(r1) == "string" and not r1:lower():find("err") and not r1:lower():find("fail")))

                        if success then
                            buyBtn.Text = "✅ OK"
                            buyBtn.BackgroundColor3 = C.success
                            L("[Buy] ✅ "..p.type.." @ "..tostring(p.price))
                            task.wait(2)
                            row:Destroy()
                        else
                            buyBtn.Text = "✗ FAIL"
                            buyBtn.BackgroundColor3 = C.danger
                            L("[Buy] ❌ failed — possibly listing dah ke-beli orang lain / lo gak ada duit")
                        end
                    end)
                end)
            end
        end
    end
    if #scanCache == 0 then
        snCountLbl.Text = "0 listings | "..scanDiag
        snCountLbl.TextColor3 = C.danger
    else
        snCountLbl.Text = "Total: "..#scanCache.." | Showing: "..shown.." | "..scanDiag
        snCountLbl.TextColor3 = C.textDim
    end
    snScroll.CanvasSize = UDim2.new(0, 0, 0, snScrollLayout.AbsoluteContentSize.Y + 8)
end

-- v8.75: Server Hunter render — filter by all criteria, trigger hop kalo gak match
local function renderBuy()
    for _, c in ipairs(BH.snBuy.scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    local petType = string.lower(BH.snBuy.search.Text or "")
    local mutation = string.lower(BH.snBuy.mutation.Text or "")
    local minKg = tonumber(BH.snBuy.minKg.Text) or 0
    local maxKg = tonumber(BH.snBuy.maxKg.Text) or math.huge
    local maxPrice = tonumber(BH.snBuy.maxPrice.Text) or math.huge

    -- Filter by all criteria
    local sorted = {}
    for _, p in ipairs(scanCache) do
        if not p.isMine then
            local typeOk = petType == "" or string.find(string.lower(p.type or ""), petType, 1, true)
            local mutOk = mutation == "" or string.find(string.lower(p.mutation or ""), mutation, 1, true)
            local kgOk = (p.kg or 0) >= minKg and (p.kg or 0) <= maxKg
            local priceOk = p.price and p.price <= maxPrice
            if typeOk and mutOk and kgOk and priceOk then
                table.insert(sorted, p)
            end
        end
    end
    table.sort(sorted, function(a, b) return (a.price or 0) < (b.price or 0) end)

    -- Update status
    if BH.hunt.active then
        local s = "Hunting (server #"..(BH.hunt.scanned or 0)..") — "
        if #sorted > 0 then
            BH.snBuy.countLbl.Text = "✅ "..s.."FOUND "..#sorted.." matches!"
            BH.snBuy.countLbl.TextColor3 = C.success
            -- v8.75: kalo match ketemu, stop auto-hop (user bisa beli manual / restart hunt)
            BH.hunt.active = false
            BH.snBuy.refresh.Text = "🎯 START HUNT"
            BH.snBuy.refresh.BackgroundColor3 = C.accent
            if BH.marketState then
                BH.marketState.hunt = BH.marketState.hunt or {}
                BH.marketState.hunt.active = false
                pcall(function() BH.saveMarketState(BH.marketState) end)
            end
            L("[HUNT] ✅ FOUND in server #"..(BH.hunt.scanned or 0).." — hunt auto-stopped")
        else
            BH.snBuy.countLbl.Text = s.."0 match, hopping to next server..."
            BH.snBuy.countLbl.TextColor3 = C.accent
            -- Trigger hop after delay
            task.spawn(function()
                task.wait(3)
                if BH.hunt.active and #sorted == 0 then
                    L("[HUNT] no match in server #"..(BH.hunt.scanned or 0)..", hopping...")
                    pcall(hopToBestServer)
                end
            end)
        end
    else
        BH.snBuy.countLbl.Text = #sorted > 0
            and ("📋 "..#sorted.." match (idle — START HUNT untuk auto-hop)")
            or "Idle — isi kriteria lalu klik START HUNT"
        BH.snBuy.countLbl.TextColor3 = #sorted > 0 and C.success or C.textDim
    end

    for i, p in ipairs(sorted) do
        if i > 50 then break end
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 36)
        row.BackgroundColor3 = C.input
        row.BorderSizePixel = 0 row.Parent = BH.snBuy.scroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

        -- Pet info (left)
        local info = Instance.new("TextLabel")
        info.Size = UDim2.new(1, -100, 1, 0) info.Position = UDim2.new(0, 8, 0, 0)
        info.BackgroundTransparency = 1
        local mutTag = (p.mutation and p.mutation ~= "-" and p.mutation ~= "") and (" ["..p.mutation.."]") or ""
        info.Text = string.format("<b>%s%s</b>  %.1fkg  •  Lv%d  •  <font color='#FFD700'>💰%s</font>  •  by %s",
            p.type, mutTag, p.kg or 0, p.age or 0, tostring(p.price or "?"), (p.owner or "?"):sub(1,12))
        info.RichText = true
        info.TextColor3 = C.text info.Font = FM info.TextSize = 11
        info.TextXAlignment = Enum.TextXAlignment.Left
        info.TextTruncate = Enum.TextTruncate.AtEnd
        info.Parent = row

        -- BUY button
        local buyBtn = Instance.new("TextButton")
        buyBtn.Size = UDim2.new(0, 80, 0, 26) buyBtn.Position = UDim2.new(1, -86, 0.5, -13)
        buyBtn.BackgroundColor3 = C.success
        buyBtn.Text = "💰 BUY" buyBtn.TextColor3 = Color3.new(1, 1, 1)
        buyBtn.Font = FB buyBtn.TextSize = 12
        buyBtn.BorderSizePixel = 0 buyBtn.Parent = row
        Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 5)

        buyBtn.MouseButton1Click:Connect(function()
            buyBtn.Text = "..."
            buyBtn.BackgroundColor3 = C.accent
            task.spawn(function()
                if not buyRE then
                    buyBtn.Text = "✗ NO RE"
                    return
                end
                local listingUuid = p.listingUuid
                if not listingUuid then
                    buyBtn.Text = "✗ NO UUID"
                    buyBtn.BackgroundColor3 = C.danger
                    return
                end
                local clean = tostring(listingUuid):gsub("[{}]","")
                local seller = p.sellerPlayer

                -- v8.72: confirmed format BuyListing(sellerPlayer, listingUuidClean)
                if not seller then
                    buyBtn.Text = "✗ NO SELLER"
                    buyBtn.BackgroundColor3 = C.danger
                    L("[Buy] ❌ sellerPlayer is nil")
                    return
                end

                local ok, r1, r2 = pcall(function()
                    return buyRE:InvokeServer(seller, clean)
                end)
                L("[Buy] result: ok="..tostring(ok)
                    .." r1="..tostring(r1):sub(1,40)
                    .." r2="..tostring(r2):sub(1,40))

                local success = ok and (r1 == true or r1 == nil or r1 == "OK"
                    or (type(r1) == "string" and not r1:lower():find("err") and not r1:lower():find("fail")))

                if success then
                    buyBtn.Text = "✅ OK"
                    buyBtn.BackgroundColor3 = C.success
                    L("[Buy] ✅ bought "..p.type.." @ "..tostring(p.price))
                    task.wait(2)
                    row:Destroy()
                else
                    buyBtn.Text = "✗ FAIL"
                    buyBtn.BackgroundColor3 = C.danger
                    L("[Buy] ❌ failed (listing dah ke-beli / duit kurang)")
                end
            end)
        end)
    end

    BH.snBuy.scroll.CanvasSize = UDim2.new(0, 0, 0, BH.snBuy.layout.AbsoluteContentSize.Y + 8)
end

do
    snRefreshBtn.MouseButton1Click:Connect(function()
        snCountLbl.Text = "Scanning..."
        task.spawn(function()
            scanBoothListings()
            renderSnipe()
        end)
    end)
    for _, b in ipairs({snSearch, snMinAge, snMaxAge, snMinKg, snMaxKg, snMinPrice, snMaxPrice}) do
        b:GetPropertyChangedSignal("Text"):Connect(renderSnipe)
    end
    -- v8.70: save filter values on focus lost
    local function saveFilters()
        if not BH.marketState then return end
        BH.marketState.snSearch = snSearch.Text
        BH.marketState.snMinAge = snMinAge.Text
        BH.marketState.snMaxAge = snMaxAge.Text
        BH.marketState.snMinKg = snMinKg.Text
        BH.marketState.snMaxKg = snMaxKg.Text
        BH.marketState.snMinPrice = snMinPrice.Text
        BH.marketState.snMaxPrice = snMaxPrice.Text
        BH.saveMarketState(BH.marketState)
    end
    for _, b in ipairs({snSearch, snMinAge, snMaxAge, snMinKg, snMaxKg, snMinPrice, snMaxPrice}) do
        b.FocusLost:Connect(saveFilters)
    end

    -- v8.47: auto-refresh every 10s
    task.spawn(function()
        while true do
            task.wait(10)
            -- Skip kalo SNIPE panel gak visible biar hemat resource
            if snManualPanel and snManualPanel.Visible then
                pcall(function()
                    scanBoothListings()
                    renderSnipe()
                end)
            elseif snBuyPanel and snBuyPanel.Visible then
                pcall(function()
                    scanBoothListings()
                    renderBuy()
                end)
            end
        end
    end)

    -- v8.47: auto-refresh sekali pas pertama buka SNIPE tab
    -- v8.73: juga trigger pas klik SNIPE sidebar (kalo Manual udah aktif, click sub-tab gak ke-fire)
    local function triggerInitialScan()
        task.wait(0.1)
        if #scanCache == 0 then
            task.spawn(function()
                pcall(scanBoothListings)
                if snManualPanel and snManualPanel.Visible then
                    pcall(renderSnipe)
                elseif snBuyPanel and snBuyPanel.Visible then
                    pcall(renderBuy)
                end
            end)
        end
    end
    pcall(function()
        BH.snSubBtns.Manual.btn.MouseButton1Click:Connect(triggerInitialScan)
    end)
    pcall(function()
        if sbBtns.SNIPE and sbBtns.SNIPE.btn then
            sbBtns.SNIPE.btn.MouseButton1Click:Connect(triggerInitialScan)
        end
    end)
    -- v8.73: also try kick scan kalo SNIPE udah visible pas script load
    task.spawn(function()
        task.wait(1.5)
        if snipePanel and snipePanel.Visible and #scanCache == 0 then
            pcall(scanBoothListings)
            if snManualPanel and snManualPanel.Visible then pcall(renderSnipe) end
        end
    end)

    -- v8.88: pas LIST HARGA tab dibuka → rebuild rules UI (refresh inventory count badge)
    -- (Gak perlu scan market karena count dari backpack langsung)
    if sbBtns["LIST HARGA"] and sbBtns["LIST HARGA"].btn then
        sbBtns["LIST HARGA"].btn.MouseButton1Click:Connect(function()
            task.spawn(function() pcall(rebuildRulesUI) end)
        end)
    end

    -- v8.84: ===== AUTO SNIPE — scan + buy loop =====
    -- Continuously scan market, match each entry against user rules, buy on match
    task.spawn(function()
        local function matchRule(p, rule)
            -- petType: substring match (case insensitive). Kosong = match semua.
            if rule.petType and rule.petType ~= "" then
                local needle = string.lower(rule.petType)
                local hay = string.lower(p.type or "")
                if not string.find(hay, needle, 1, true) then return false end
            end
            -- mutation: substring match. Kosong = match semua.
            if rule.mutation and rule.mutation ~= "" then
                local needle = string.lower(rule.mutation)
                local hay = string.lower(p.mutation or "")
                if not string.find(hay, needle, 1, true) then return false end
            end
            -- maxKg: optional. 0 atau nil = no limit
            if rule.maxKg and rule.maxKg > 0 then
                if (p.kg or 0) > rule.maxKg then return false end
            end
            -- v8.235: minKg: optional. 0 atau nil = no minimum
            if rule.minKg and rule.minKg > 0 then
                if (p.kg or 0) < rule.minKg then return false end
            end
            -- maxPrice: wajib
            if not p.price or p.price > rule.maxPrice then return false end
            -- v8.302: filter asal egg PER-RULE. rule.eggSource override; nil = ikut global.
            local es = rule.eggSource or BH.autoSnipe.eggSource or "all"
            if es == "prem" and not p.isPrem then return false end
            if es == "biasa" and p.isPrem then return false end
            return true
        end

        while gui.Parent do
            -- v8.94: NO DELAY — secepet mungkin biar duluan dari script lain
            -- Idle (not active): wait 1s biar gak bikin lag. Active: minimal wait.
            if not BH.autoSnipe.active then
                task.wait(1)  -- idle sleep
            else
                task.wait()  -- 1 frame (~16ms) — secepet Roblox bisa
            end

            if not BH.autoSnipe.active then
                -- not running, skip
            elseif #BH.autoSnipe.rules == 0 then
                -- no rules
            elseif not buyRE then
                BH.autoSnipe.statusLbl.Text = "❌ buyRE belum cached (klik SNIPE dulu)"
                BH.autoSnipe.statusLbl.TextColor3 = C.danger
            else
                -- v8.95: INLINE lightweight scan — NO logging, NO verbose stats
                -- v8.251: PARALEL — query semua pemain serempak (task.spawn), bukan 1-1 berurutan.
                -- Di server rame (30 org) ini mangkas scan dari ~3-5s jadi <0.5s.
                local autoCache = {}
                if BH.TBC then
                    local plist = Players:GetPlayers()
                    local pending = 0
                    local results = {}
                    for _, pp in ipairs(plist) do
                        if pp ~= player then  -- skip diri sendiri
                            pending = pending + 1
                            task.spawn(function()
                                local ok, data = pcall(function()
                                    return BH.TBC:GetPlayerBoothData(pp)
                                end)
                                if ok and data and data.Listings then
                                    results[pp] = data
                                end
                                pending = pending - 1
                            end)
                        end
                    end
                    -- tunggu semua thread selesai (timeout ~1.5s biar gak nyangkut)
                    local waited = 0
                    while pending > 0 and waited < 1.5 do
                        waited = waited + task.wait()
                    end
                    -- olah hasil yg udah masuk
                    for pp, data in pairs(results) do
                        local items = data.Items
                        for listingUuid, listing in pairs(data.Listings) do
                            if listing.ItemType == "Pet" and listing.ItemId then
                                local item = items and items[listing.ItemId]
                                if item and item.PetData then
                                    local pd = item.PetData
                                    local kg = (BH.computeBaseKgFromPetData and BH.computeBaseKgFromPetData(pd)) or 0
                                    local mut = tostring(pd.MutationType or "")
                                    -- v8.270: hatchedFrom + isPrem (biar filter egg auto snipe jalan + bisa di-log)
                                    local hatchedFrom = tostring(pd.HatchedFrom or "")
                                    local isPrem = hatchedFrom:lower():find("premium") ~= nil
                                    table.insert(autoCache, {
                                        type = tostring(item.PetType or "?"),
                                        mutation = (mut ~= "" and mut or "-"),
                                        kg = kg,
                                        price = tonumber(listing.Price) or 0,
                                        owner = pp.Name,
                                        sellerPlayer = pp,
                                        listingUuid = listingUuid,
                                        hatchedFrom = hatchedFrom,
                                        isPrem = isPrem,
                                    })
                                end
                            end
                        end
                    end
                end

                local boughtThisRound = 0
                for _, p in ipairs(autoCache) do
                    if not BH.autoSnipe.active then break end
                    -- v8.265: skip kalau udah BERHASIL dibeli, ATAU lagi cooldown (baru gagal <2s lalu)
                    local cd = BH.autoSnipe.cooldown[p.listingUuid]
                    local onCooldown = cd and (tick() - cd) < 2
                    if not BH.autoSnipe.bought[p.listingUuid] and not onCooldown then
                        for _, rule in ipairs(BH.autoSnipe.rules) do
                            if matchRule(p, rule) then
                                -- v8.271: GUARD final filter egg tepat sebelum fire (anti-bocor/race)
                                local esNow = BH.autoSnipe.eggSource or "all"
                                local skipEgg = (esNow == "prem" and not p.isPrem)
                                            or (esNow == "biasa" and p.isPrem)
                                if skipEgg then
                                    -- gak cocok filter egg terkini -> skip, jangan beli
                                else
                                -- v8.265: JANGAN mark bought dulu — tandai cooldown biar gak spam,
                                -- mark bought HANYA kalau buy sukses (di bawah). Gagal -> bisa retry.
                                BH.autoSnipe.cooldown[p.listingUuid] = tick()
                                -- BUY in parallel — no wait, fire immediately
                                local clean = tostring(p.listingUuid):gsub("[{}]","")
                                local seller, listingUuid = p.sellerPlayer, p.listingUuid
                                local petType, petMut, petPrice, petOwner =
                                    p.type, p.mutation, p.price, p.owner
                                local petPrem = p.isPrem and true or false  -- v8.268
                                local petEgg = p.hatchedFrom or "?"  -- v8.270
                                task.spawn(function()
                                    local ok, ret = pcall(function()
                                        return buyRE:InvokeServer(seller, clean)
                                    end)
                                    if ok and (ret == true or ret == nil) then
                                        -- v8.265: sukses -> baru mark bought permanen
                                        BH.autoSnipe.bought[listingUuid] = true
                                        BH.autoSnipe.boughtCount = BH.autoSnipe.boughtCount + 1
                                        -- v8.270: log egg asal (prem/biasa) buat verifikasi filter
                                        L(string.format("[AutoSnipe] ✅ Bought %s%s @ %s from %s | EGG: %s (%s)",
                                            petType or "?",
                                            (petMut and petMut ~= "-" and " ["..petMut.."]") or "",
                                            tostring(petPrice), petOwner or "?",
                                            petEgg, petPrem and "PREM" or "biasa"))
                                        BH.autoSnipe.statusLbl.Text = string.format(
                                            "✅ %d bought | latest: %s @ %s",
                                            BH.autoSnipe.boughtCount,
                                            petType or "?", tostring(petPrice))
                                        BH.autoSnipe.statusLbl.TextColor3 = C.success
                                        -- v8.268: append ke history + persist (max 100 entries)
                                        table.insert(BH.autoSnipe.history, 1, {
                                            petType = petType,
                                            mutation = petMut,
                                            price = petPrice,
                                            seller = petOwner,
                                            isPrem = petPrem,
                                            eggName = petEgg,
                                            ts = os.time(),
                                        })
                                        while #BH.autoSnipe.history > 100 do
                                            table.remove(BH.autoSnipe.history)
                                        end
                                        if BH.marketState then
                                            BH.marketState.autoSnipeHistory = BH.autoSnipe.history
                                            pcall(function() BH.saveMarketState(BH.marketState) end)
                                        end
                                        if BH.autoSnipe.rebuildHistory then
                                            pcall(BH.autoSnipe.rebuildHistory)
                                        end
                                    else
                                        L(string.format("[AutoSnipe] ❌ Buy fail %s: %s",
                                            petType or "?", tostring(ret):sub(1, 50)))
                                    end
                                end)
                                boughtThisRound = boughtThisRound + 1
                                break  -- match satu rule → next pet
                                end  -- v8.271: tutup else guard filter egg
                            end
                        end
                    end
                end

                if boughtThisRound == 0 and BH.autoSnipe.active then
                    BH.autoSnipe.statusLbl.Text = string.format(
                        "🔍 Scanning... %d listings | %d bought total",
                        #autoCache, BH.autoSnipe.boughtCount)
                    BH.autoSnipe.statusLbl.TextColor3 = C.accent
                end
            end
        end
    end)

    -- v8.257: ===== INDEX HOP — loop cek pet target, kalau gak ada -> FindSellers (auto hop) =====
    task.spawn(function()
        -- cek apakah jenis pet target ADA di booth server ini (via scanCache/TBC)
        -- v8.266: cek pet target ADA + sesuai filter egg + harga <= maxPrice
        local function petTypeExistsHere(targetSet)
            if not BH.TBC then return false end
            local maxP = BH.indexHop.maxPrice or 0
            local es = BH.indexHop.eggSource or "all"
            for _, pp in ipairs(Players:GetPlayers()) do
                if pp ~= player then
                    local ok, data = pcall(function() return BH.TBC:GetPlayerBoothData(pp) end)
                    if ok and data and data.Listings and data.Items then
                        for _, listing in pairs(data.Listings) do
                            if listing.ItemType == "Pet" and listing.ItemId then
                                local item = data.Items[listing.ItemId]
                                if item and item.PetType and targetSet[tostring(item.PetType)] then
                                    local price = tonumber(listing.Price) or math.huge
                                    -- cek egg filter: prem = HatchedFrom ada "premium", biasa = enggak
                                    local pd = item.PetData
                                    local hf = pd and tostring(pd.HatchedFrom or ""):lower() or ""
                                    local isPrem = hf:find("premium") ~= nil
                                    local eggOk = (es == "all")
                                        or (es == "prem" and isPrem)
                                        or (es == "biasa" and not isPrem)
                                    local priceOk = (maxP <= 0) or (price <= maxP)
                                    if eggOk and priceOk then
                                        return true  -- ada pet cocok (jenis+egg+harga)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            return false  -- gak ada yg cocok -> hop
        end

        -- v8.266: hop server biasa (TeleportToPlaceInstance via BH.manualHop), BUKAN FindSellers
        BH.indexHop.doHop = function()
            if BH.manualHop then
                BH.manualHop()  -- hopToBestServer (server rame, scan 5000)
                return true, "hop server"
            end
            return false, "fungsi hop belum siap"
        end

        while gui.Parent do
            task.wait(BH.indexHop.intervalSec or 5)
            if BH.indexHop and BH.indexHop.active then
                local targetSet = BH.indexHop.selectedTypes or {}
                local picked = false
                for _ in pairs(targetSet) do picked = true break end
                if not picked then
                    if BH.indexHop.statusLbl then
                        BH.indexHop.statusLbl.Text = "❌ pilih jenis pet dulu"
                        BH.indexHop.statusLbl.TextColor3 = C.danger
                    end
                else
                    -- cek: ada pet cocok (jenis + egg filter + harga) di server ini?
                    local existsHere = petTypeExistsHere(targetSet)
                    if existsHere then
                        -- ADA pet cocok -> berhenti hop, diam di server ini
                        if BH.indexHop.statusLbl then
                            BH.indexHop.statusLbl.Text = "✅ Pet cocok ADA di server ini — stop hop"
                            BH.indexHop.statusLbl.TextColor3 = C.success
                        end
                        L("[IndexHop] pet cocok ada di server ini — diam")
                    else
                        -- GAK ADA pet cocok -> hop ke server lain
                        if BH.indexHop.statusLbl then
                            BH.indexHop.statusLbl.Text = "🔍 Pet gak ada/gak cocok — hop server..."
                            BH.indexHop.statusLbl.TextColor3 = C.accent
                        end
                        L("[IndexHop] pet gak cocok — hop ke server lain")
                        local ok, info = BH.indexHop.doHop()
                        if ok then
                            -- lagi TP, kasih jeda biar pindah kelar
                            task.wait(5)
                        else
                            L("[IndexHop] "..tostring(info))
                            if BH.indexHop.statusLbl then
                                BH.indexHop.statusLbl.Text = "⚠ "..tostring(info)
                                BH.indexHop.statusLbl.TextColor3 = C.textDim
                            end
                            task.wait(2)
                        end
                    end
                end
            end
        end
    end)


    local function saveHuntState()
        if not BH.marketState then return end
        BH.marketState.hunt = {
            active = BH.hunt.active,
            petType = BH.snBuy.search.Text,
            mutation = BH.snBuy.mutation.Text,
            minKg = BH.snBuy.minKg.Text,
            maxKg = BH.snBuy.maxKg.Text,
            maxPrice = BH.snBuy.maxPrice.Text,
            scanned = BH.hunt.scanned or 0,
        }
        pcall(function() BH.saveMarketState(BH.marketState) end)
    end

    BH.snBuy.refresh.MouseButton1Click:Connect(function()
        BH.hunt.active = not BH.hunt.active
        if BH.hunt.active then
            -- START
            BH.hunt.scanned = 0
            BH.snBuy.refresh.Text = "⛔ STOP HUNT"
            BH.snBuy.refresh.BackgroundColor3 = C.danger
            BH.snBuy.countLbl.Text = "🎯 Hunt started — scanning server #1..."
            BH.snBuy.countLbl.TextColor3 = C.accent
            L("[HUNT] START — type="..BH.snBuy.search.Text.." mut="..BH.snBuy.mutation.Text
                .." kg="..BH.snBuy.minKg.Text.."-"..BH.snBuy.maxKg.Text
                .." maxPrice="..BH.snBuy.maxPrice.Text)
            saveHuntState()
            task.spawn(function()
                BH.hunt.scanned = 1
                pcall(scanBoothListings)
                pcall(renderBuy)  -- renderBuy will trigger hop kalo no match
            end)
        else
            -- STOP
            BH.snBuy.refresh.Text = "🎯 START HUNT"
            BH.snBuy.refresh.BackgroundColor3 = C.accent
            BH.snBuy.countLbl.Text = "⛔ Hunt stopped"
            BH.snBuy.countLbl.TextColor3 = C.textDim
            L("[HUNT] STOPPED by user")
            saveHuntState()
        end
    end)
    -- Auto-rerun renderBuy ketika kriteria berubah (live filter)
    for _, b in ipairs({BH.snBuy.search, BH.snBuy.mutation, BH.snBuy.minKg, BH.snBuy.maxKg, BH.snBuy.maxPrice}) do
        b:GetPropertyChangedSignal("Text"):Connect(function() pcall(renderBuy) end)
        b.FocusLost:Connect(saveHuntState)
    end

    BH.snSubBtns.Buy.btn.MouseButton1Click:Connect(function()
        task.wait(0.1)
        if #scanCache == 0 then
            task.spawn(function()
                pcall(scanBoothListings)
                pcall(renderBuy)
            end)
        else
            pcall(renderBuy)
        end
    end)

    -- v8.75: AUTO-RESUME hunt kalo state-nya active pas script load
    -- (misal: user start hunt → script hop → game reload → continue hunt otomatis)
    task.spawn(function()
        task.wait(3)
        if BH.marketState and BH.marketState.hunt and BH.marketState.hunt.active then
            BH.hunt.active = true
            BH.hunt.scanned = (BH.marketState.hunt.scanned or 0) + 1
            BH.snBuy.refresh.Text = "⛔ STOP HUNT"
            BH.snBuy.refresh.BackgroundColor3 = C.danger
            L("[HUNT] AUTO-RESUME from state, scanning server #"..BH.hunt.scanned)
            pcall(scanBoothListings)
            pcall(renderBuy)
        end
    end)
end

end  -- end setupSnipeScanner function
BH.setupSnipeScanner()

-- ===== INIT =====
L("════════════════════════════════════")
L("  PULSE HUB v"..VERSION)
L("  Build: "..VERSION_DATE)
L("════════════════════════════════════")
L("")
L("Tab kiri:")
L("  • MARKET (default) - Listing/Rejoin/Misc")
L("  • LIST HARGA - rules + backpack stats")
L("  • SNIPE - manual scan + auto (soon)")
L("")
L("Cek tab LIST HARGA buat liat:")
L("  - Total pet di backpack")
L("  - Fav count")
L("  - Inventory capacity")


-- v8.158: HISTORY SELL panel — ported dari standalone history_sell.lua design
;(function()
    local hp = panels["HISTORY SELL"]
    if not hp then return end

    local HIST_FILE = "pulse_market_history.json"

    local salesHistory = {}
    local salesByKey = {}
    local elapsedStartEpoch = os.time()  -- v8.159: pake os.time() biar persistent
    local selectedType = nil
    local sortMode = "newest"

    -- v8.159: Load dari file
    pcall(function()
        if isfile and isfile(HIST_FILE) then
            local ok, data = pcall(function() return HttpService:JSONDecode(readfile(HIST_FILE)) end)
            if ok and type(data) == "table" then
                if type(data.history) == "table" then
                    salesHistory = data.history
                    for _, e in ipairs(salesHistory) do
                        if e.key then salesByKey[e.key] = true end
                    end
                end
                if tonumber(data.elapsedStartEpoch) then
                    elapsedStartEpoch = tonumber(data.elapsedStartEpoch)
                end
            end
        end
    end)

    local function saveHist()
        pcall(function()
            if writefile then
                writefile(HIST_FILE, HttpService:JSONEncode({
                    history = salesHistory,
                    elapsedStartEpoch = elapsedStartEpoch,
                }))
            end
        end)
    end

    -- Resolve remotes
    local fetchHistRE, addHistRE
    pcall(function()
        local Booths = RS:WaitForChild("GameEvents", 5)
            and RS.GameEvents:WaitForChild("TradeEvents", 5)
            and RS.GameEvents.TradeEvents:WaitForChild("Booths", 5)
        if Booths then
            fetchHistRE = Booths:WaitForChild("FetchHistory", 5)
            addHistRE = Booths:WaitForChild("AddToHistory", 5)
        end
    end)
    L("[Hist] FetchHistory="..(fetchHistRE and "OK" or "nil").." AddToHistory="..(addHistRE and "OK" or "nil"))

    -- Scan PetRegistry untuk picker modal
    local allPetTypes = {}
    pcall(function()
        local data = RS:FindFirstChild("Data")
        local petReg = data and data:FindFirstChild("PetRegistry")
        local petList = petReg and petReg:FindFirstChild("PetList")
        if petList then
            if petList:IsA("ModuleScript") then
                local ok, m = pcall(require, petList)
                if ok and type(m) == "table" then
                    for name, _ in pairs(m) do
                        if type(name) == "string" then table.insert(allPetTypes, name) end
                    end
                end
            else
                for _, c in ipairs(petList:GetChildren()) do
                    if c:IsA("ModuleScript") then table.insert(allPetTypes, c.Name) end
                end
            end
        end
        for _, alt in ipairs({"PetData", "Pets", "PetTypes"}) do
            local f = RS:FindFirstChild(alt)
            if f then
                for _, c in ipairs(f:GetChildren()) do
                    if c:IsA("ModuleScript") or c:IsA("Folder") then
                        table.insert(allPetTypes, c.Name)
                    end
                end
            end
        end
    end)
    do
        local seen, uniq = {}, {}
        for _, n in ipairs(allPetTypes) do
            if not seen[n] then seen[n] = true; table.insert(uniq, n) end
        end
        table.sort(uniq)
        allPetTypes = uniq
    end
    BH.allPetTypes = allPetTypes  -- v8.257: dipakai picker Index Hop juga
    L("[Hist] PetRegistry loaded "..#allPetTypes.." types")

    -- ===== Panel padding =====
    do
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 14) pad.PaddingLeft = UDim.new(0, 14)
        pad.PaddingRight = UDim.new(0, 14) pad.PaddingBottom = UDim.new(0, 14)
        pad.Parent = hp
    end

    -- ===== Stats card =====
    local statsCard = Instance.new("Frame")
    statsCard.Size = UDim2.new(1, 0, 0, 78)
    statsCard.BackgroundColor3 = C.card
    statsCard.BorderSizePixel = 0
    statsCard.Parent = hp
    Instance.new("UICorner", statsCard).CornerRadius = UDim.new(0, 8)

    local bigTotal = Instance.new("TextLabel")
    bigTotal.Size = UDim2.new(1, -130, 1, 0) bigTotal.Position = UDim2.new(0, 14, 0, 0)
    bigTotal.BackgroundTransparency = 1 bigTotal.Text = "🪙 0"
    bigTotal.TextColor3 = C.accent bigTotal.Font = FB bigTotal.TextSize = 30
    bigTotal.TextXAlignment = Enum.TextXAlignment.Left
    bigTotal.TextYAlignment = Enum.TextYAlignment.Center
    bigTotal.Parent = statsCard

    local subStats = Instance.new("TextLabel")
    subStats.Size = UDim2.new(0, 120, 0, 20) subStats.Position = UDim2.new(1, -130, 0, 10)
    subStats.BackgroundTransparency = 1 subStats.Text = "0 sold"
    subStats.TextColor3 = C.textDim subStats.Font = FM subStats.TextSize = 11
    subStats.TextXAlignment = Enum.TextXAlignment.Right
    subStats.Parent = statsCard

    local elapsedLbl = Instance.new("TextLabel")
    elapsedLbl.Size = UDim2.new(0, 120, 0, 20) elapsedLbl.Position = UDim2.new(1, -130, 0, 32)
    elapsedLbl.BackgroundTransparency = 1 elapsedLbl.Text = "⏱  0s"
    elapsedLbl.TextColor3 = C.accent elapsedLbl.Font = Enum.Font.Code elapsedLbl.TextSize = 13
    elapsedLbl.TextXAlignment = Enum.TextXAlignment.Right
    elapsedLbl.Parent = statsCard

    local lastSaleLbl = Instance.new("TextLabel")
    lastSaleLbl.Size = UDim2.new(0, 120, 0, 18) lastSaleLbl.Position = UDim2.new(1, -130, 0, 54)
    lastSaleLbl.BackgroundTransparency = 1 lastSaleLbl.Text = "—"
    lastSaleLbl.TextColor3 = C.textDim lastSaleLbl.Font = FM lastSaleLbl.TextSize = 10
    lastSaleLbl.TextXAlignment = Enum.TextXAlignment.Right
    lastSaleLbl.Parent = statsCard

    -- ===== Action row =====
    local actionRow = Instance.new("Frame")
    actionRow.Size = UDim2.new(1, 0, 0, 30) actionRow.Position = UDim2.new(0, 0, 0, 88)
    actionRow.BackgroundTransparency = 1
    actionRow.Parent = hp

    local clearBtn = Instance.new("TextButton")
    clearBtn.Size = UDim2.new(0, 90, 0, 30) clearBtn.Position = UDim2.new(0, 0, 0, 0)
    clearBtn.BackgroundColor3 = C.card clearBtn.AutoButtonColor = false
    clearBtn.Text = "CLEAR" clearBtn.TextColor3 = C.danger
    clearBtn.Font = FB clearBtn.TextSize = 12 clearBtn.BorderSizePixel = 0
    clearBtn.Parent = actionRow
    Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 6)

    -- v8.190: replace Sort dgn USER LIST — opens modal with copyable buyer names
    local userListBtn = Instance.new("TextButton")
    userListBtn.Size = UDim2.new(0, 130, 0, 30) userListBtn.Position = UDim2.new(0, 98, 0, 0)
    userListBtn.BackgroundColor3 = C.card userListBtn.AutoButtonColor = false
    userListBtn.Text = "👥 USER LIST" userListBtn.TextColor3 = C.accent
    userListBtn.Font = FB userListBtn.TextSize = 12 userListBtn.BorderSizePixel = 0
    userListBtn.Parent = actionRow
    Instance.new("UICorner", userListBtn).CornerRadius = UDim.new(0, 6)

    -- Hidden sortBtn (keep ref biar gak break sortBtn handler di line 8998)
    local sortBtn = Instance.new("TextButton")
    sortBtn.Visible = false
    sortBtn.Text = "Sort: NEWEST"
    sortBtn.Parent = actionRow

    local typeBtn = Instance.new("TextButton")
    typeBtn.Size = UDim2.new(1, -350, 0, 30) typeBtn.Position = UDim2.new(0, 236, 0, 0)
    typeBtn.BackgroundColor3 = C.card typeBtn.AutoButtonColor = false
    typeBtn.Text = "▼  All Pets" typeBtn.TextColor3 = C.text
    typeBtn.Font = FB typeBtn.TextSize = 12 typeBtn.BorderSizePixel = 0
    typeBtn.Parent = actionRow
    Instance.new("UICorner", typeBtn).CornerRadius = UDim.new(0, 6)

    -- ===== List frame =====
    local listFrame = Instance.new("Frame")
    listFrame.Size = UDim2.new(1, 0, 1, -150) listFrame.Position = UDim2.new(0, 0, 0, 128)
    listFrame.BackgroundColor3 = C.bg listFrame.BorderSizePixel = 0
    listFrame.Parent = hp
    Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 8)

    -- v8.190: stub refreshFrequentBuyers (modal-based skrng, dipanggil from watcher gak ngapa2in)
    BH.refreshFrequentBuyers = function() end

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -8, 1, -8) scroll.Position = UDim2.new(0, 4, 0, 4)
    scroll.BackgroundTransparency = 1 scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4 scroll.ScrollBarImageColor3 = C.accent
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = listFrame
    do
        local lay = Instance.new("UIListLayout")
        lay.Padding = UDim.new(0, 4) lay.Parent = scroll
        local spad = Instance.new("UIPadding")
        spad.PaddingTop = UDim.new(0, 6) spad.PaddingBottom = UDim.new(0, 6)
        spad.PaddingLeft = UDim.new(0, 6) spad.PaddingRight = UDim.new(0, 6)
        spad.Parent = scroll
    end

    local footerLbl = Instance.new("TextLabel")
    footerLbl.Size = UDim2.new(1, 0, 0, 18) footerLbl.Position = UDim2.new(0, 0, 1, -16)
    footerLbl.BackgroundTransparency = 1 footerLbl.Text = "Idle"
    footerLbl.TextColor3 = C.textDim footerLbl.Font = Enum.Font.Code footerLbl.TextSize = 10
    footerLbl.TextXAlignment = Enum.TextXAlignment.Left
    footerLbl.Parent = hp

    -- ===== Helpers =====
    local entryDumpedOnce = false  -- v8.181: dump 1st entry struct
    local unknownDumpCount = 0     -- v8.182: dump entries yg parse jadi "?"
    local function dumpEntry(e, label)
        local parts = {}
        for k, v in pairs(e) do
            if type(v) == "table" then
                local sub = {}
                for k2, v2 in pairs(v) do
                    if type(v2) == "table" then
                        local sub2 = {}
                        for k3, v3 in pairs(v2) do
                            table.insert(sub2, tostring(k3).."="..tostring(v3):sub(1,20))
                        end
                        table.insert(sub, tostring(k2).."={"..table.concat(sub2,",").."}")
                    else
                        table.insert(sub, tostring(k2).."="..tostring(v2):sub(1, 30))
                    end
                end
                table.insert(parts, tostring(k).."={"..table.concat(sub, ",").."}")
            else
                table.insert(parts, tostring(k).."("..type(v)..")="..tostring(v):sub(1, 40))
            end
        end
        L("")
        L("════════════ HIST DUMP ("..(label or "entry")..") ════════════")
        L("[Hist] "..table.concat(parts, " | "):sub(1, 900))
        L("════════════════════════════════════")
        L("")
    end

    local function parseEntry(e)
        if type(e) ~= "table" then return nil end
        -- v8.181: dump first entry biar tau struktur actual
        if not entryDumpedOnce then
            entryDumpedOnce = true
            dumpEntry(e, "SAMPLE")
        end
        local t = tonumber(e.Time or e.Timestamp or e.time or e.At or e.SoldAt or e.PurchasedAt) or os.time()
        local price = tonumber(e.Price or e.price or e.Cost or e.Amount or e.SoldPrice) or 0
        -- v8.181+182: lebih banyak fallback + nested Item + listing nested
        local petType = e.PetType or e.petType or e.ItemType or e.itemType or e.ItemName or e.Name or e.itemName
        local mut, kg = nil, 0
        local petData = e.PetData or e.petData
        -- nested e.Item
        if e.Item and type(e.Item) == "table" then
            petType = petType or e.Item.PetType or e.Item.petType or e.Item.Name or e.Item.ItemName
            petData = petData or e.Item.PetData or e.Item.petData
        end
        -- nested e.Listing
        if e.Listing and type(e.Listing) == "table" then
            petType = petType or e.Listing.PetType or e.Listing.ItemType
            petData = petData or e.Listing.PetData
        end
        if type(petData) == "table" then
            if tonumber(petData.BaseWeight) then kg = petData.BaseWeight * 1.1 end
            mut = petData.MutationType or petData.Mutation
            petType = petType or petData.PetType or petData.Type or petData.Name
        elseif tonumber(e.BaseWeight) then
            kg = e.BaseWeight * 1.1
        end
        -- v8.182: kalo masih "?", dump struct ini buat diagnose (max 3 dump)
        if (not petType or petType == "") and unknownDumpCount < 5 then
            unknownDumpCount = unknownDumpCount + 1
            dumpEntry(e, "UNKNOWN#"..unknownDumpCount)
        end
        if not petType or petType == "" then petType = "?" end
        local key = tostring(e.Id or e.UUID or e.ListingId or e.ItemId or e.ListingUUID or e.listingId or "")
        if key == "" then key = tostring(t).."_"..tostring(price).."_"..tostring(petType) end
        return {time = t, petType = tostring(petType), kg = kg, price = price, key = key, mut = mut}
    end

    local function addEntry(e)
        local p = parseEntry(e)
        if not p then return false end
        if salesByKey[p.key] then return false end
        salesByKey[p.key] = true
        table.insert(salesHistory, p)
        saveHist()  -- v8.159: persist on add
        return true
    end

    local function purgeOld()
        local cutoff = os.time() - 24*3600
        local fresh, keys = {}, {}
        local removed = 0
        for _, e in ipairs(salesHistory) do
            if (e.time or 0) >= cutoff then
                table.insert(fresh, e); keys[e.key] = true
            else
                removed = removed + 1
            end
        end
        salesHistory = fresh; salesByKey = keys
        if removed > 0 then saveHist() end
    end

    local function timeAgo(t)
        local diff = os.time() - (t or 0)
        if diff < 0 then return "—" end
        if diff < 60 then return diff.."s" end
        if diff < 3600 then return math.floor(diff/60).."m" end
        if diff < 86400 then return math.floor(diff/3600).."h"..math.floor((diff%3600)/60).."m" end
        return math.floor(diff/86400).."d"
    end

    local function fmtNum(n)
        local s = tostring(n)
        local k
        while true do
            s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
            if k == 0 then break end
        end
        return s
    end

    local function renderRow(entry)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 48)
        row.BackgroundColor3 = C.card row.BorderSizePixel = 0
        row.Parent = scroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local stripe = Instance.new("Frame")
        stripe.Size = UDim2.new(0, 4, 1, -10) stripe.Position = UDim2.new(0, 4, 0, 5)
        stripe.BackgroundColor3 = (entry.price >= 500) and C.success
            or (entry.price >= 200) and C.accent or C.textDim
        stripe.BorderSizePixel = 0 stripe.Parent = row
        Instance.new("UICorner", stripe).CornerRadius = UDim.new(1, 0)

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(0, 200, 0, 20) nameLbl.Position = UDim2.new(0, 16, 0, 6)
        nameLbl.BackgroundTransparency = 1 nameLbl.Text = entry.petType
        nameLbl.TextColor3 = C.text nameLbl.Font = FB nameLbl.TextSize = 14
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd nameLbl.Parent = row

        if entry.mut then
            local mutBadge = Instance.new("TextLabel")
            mutBadge.Size = UDim2.new(0, 30, 0, 16) mutBadge.Position = UDim2.new(0, 220, 0, 8)
            mutBadge.BackgroundColor3 = Color3.fromRGB(150, 100, 200)
            mutBadge.Text = tostring(entry.mut) mutBadge.TextColor3 = Color3.new(1, 1, 1)
            mutBadge.Font = FB mutBadge.TextSize = 10
            mutBadge.Parent = row
            Instance.new("UICorner", mutBadge).CornerRadius = UDim.new(0, 3)
        end

        local subLbl = Instance.new("TextLabel")
        subLbl.Size = UDim2.new(0, 250, 0, 16) subLbl.Position = UDim2.new(0, 16, 0, 26)
        subLbl.BackgroundTransparency = 1
        local kgTxt = (entry.kg and entry.kg > 0) and string.format("%.1fkg", entry.kg) or "—"
        subLbl.Text = kgTxt .. "   •   " .. timeAgo(entry.time).." ago"
        subLbl.TextColor3 = C.textDim subLbl.Font = FM subLbl.TextSize = 11
        subLbl.TextXAlignment = Enum.TextXAlignment.Left subLbl.Parent = row

        local priceLbl = Instance.new("TextLabel")
        priceLbl.Size = UDim2.new(0, 80, 1, 0) priceLbl.Position = UDim2.new(1, -90, 0, 0)
        priceLbl.BackgroundTransparency = 1 priceLbl.Text = "🪙 "..tostring(entry.price)
        priceLbl.TextColor3 = C.accent priceLbl.Font = FB priceLbl.TextSize = 15
        priceLbl.TextXAlignment = Enum.TextXAlignment.Right priceLbl.Parent = row
        local rpad = Instance.new("UIPadding") rpad.PaddingRight = UDim.new(0, 10); rpad.Parent = row
    end

    local function refreshUI()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
        end
        purgeOld()
        -- Filter
        local sorted = {}
        for _, s in ipairs(salesHistory) do
            if not selectedType or s.petType == selectedType then
                table.insert(sorted, s)
            end
        end
        -- Total dari filtered subset
        local total = 0
        for _, s in ipairs(sorted) do total = total + (tonumber(s.price) or 0) end
        bigTotal.Text = "🪙 "..fmtNum(total)
        subStats.Text = #sorted.." sold"..(selectedType and "  ("..selectedType..")" or "")

        if #salesHistory > 0 then
            local latest = 0
            for _, s in ipairs(salesHistory) do
                if (s.time or 0) > latest then latest = s.time end
            end
            lastSaleLbl.Text = "last: "..timeAgo(latest).." ago"
        else
            lastSaleLbl.Text = "no sales yet"
        end

        if sortMode == "newest" then
            table.sort(sorted, function(a, b) return (a.time or 0) > (b.time or 0) end)
        elseif sortMode == "price_high" then
            table.sort(sorted, function(a, b) return (a.price or 0) > (b.price or 0) end)
        elseif sortMode == "price_low" then
            table.sort(sorted, function(a, b) return (a.price or 0) < (b.price or 0) end)
        end
        for _, e in ipairs(sorted) do renderRow(e) end

        if #salesHistory == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, -20, 0, 40)
            empty.BackgroundTransparency = 1
            empty.Text = "Belum ada penjualan"
            empty.TextColor3 = C.textDim empty.Font = FM empty.TextSize = 12
            empty.Parent = scroll
        elseif #sorted == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, -20, 0, 40)
            empty.BackgroundTransparency = 1
            empty.Text = "Tidak ada hasil untuk '"..tostring(selectedType).."'"
            empty.TextColor3 = C.textDim empty.Font = FM empty.TextSize = 12
            empty.Parent = scroll
        end
    end

    -- ===== v8.184: PARSE dari PlayerGui.TradeBoothHistory templates (data udah ke-render disitu) =====
    -- Native UI auto-populate ke ScrollingFrame, kita tinggal baca aja
    local function parseFromNativeUI()
        local entries = {}
        local LP = game:GetService("Players").LocalPlayer
        local tbh = LP.PlayerGui:FindFirstChild("TradeBoothHistory")
        if not tbh then return entries end
        local frame = tbh:FindFirstChild("Frame")
        if not frame then return entries end
        local sf = frame:FindFirstChild("ScrollingFrame")
        if not sf then return entries end

        for _, tmpl in ipairs(sf:GetChildren()) do
            if tmpl.Name == "BoothHistoryTemplate" then
                pcall(function()
                    local spacer = tmpl:FindFirstChild("Spacer")
                    if not spacer then return end
                    local title = spacer:FindFirstChild("Title")
                    local itemNameLbl = spacer:FindFirstChild("ItemName")
                    local priceFrame = spacer:FindFirstChild("Price")
                    local timeLbl = spacer:FindFirstChild("Time")
                    if not (title and itemNameLbl and priceFrame and timeLbl) then return end

                    local labelLbl = title:FindFirstChild("Label")
                    local plrLbl = title:FindFirstChild("PlrName")
                    local amountLbl = priceFrame:FindFirstChild("Amount")
                    if not (labelLbl and amountLbl) then return end

                    -- Filter: cuma "Sold" (skip "Bought")
                    local kind = tostring(labelLbl.Text)
                    if kind ~= "Sold" then return end

                    local petName = tostring(itemNameLbl.Text)
                    local priceStr = tostring(amountLbl.Text):gsub("[^%d]", "")
                    local price = tonumber(priceStr) or 0
                    local plrName = plrLbl and tostring(plrLbl.Text) or ""
                    local timeStr = tostring(timeLbl.Text)
                    -- timeStr format: "02:44 PM (05/22/26)"
                    local key = petName.."_"..price.."_"..plrName.."_"..timeStr

                    table.insert(entries, {
                        PetType = petName,
                        Price = price,
                        Time = os.time(),  -- exact unknown, pake current
                        BuyerName = plrName,
                        TimeStr = timeStr,
                        Id = key,
                    })
                end)
            end
        end
        return entries
    end

    -- ===== Fetch dari server =====
    -- v8.187: SKIP UI parse — UI templates udah berisi history LAMA, kalo di-import otomatis bakal masuk history sc
    -- dengan time = sekarang (misleading "7m ago" padahal sebenarnya dari berhari-hari lalu).
    -- Sekarang refresh CUMA trigger FetchHistory remote → kalo server fire AddToHistory, baru add.
    -- Pet sold beneran di sesi ini → AddToHistory fire → masuk history.
    local fetching = false
    local function fetchHistory()
        if fetching then return end
        fetching = true
        footerLbl.Text = "Trigger fetch..." footerLbl.TextColor3 = C.accent
        task.spawn(function()
            -- Reset attribute + invoke remote (trigger server resend)
            pcall(function() game.Players.LocalPlayer:SetAttribute("_boothHistoryFetched", false) end)
            if fetchHistRE then
                pcall(function() fetchHistRE:InvokeServer() end)
            end
            task.wait(1.5)
            fetching = false
            purgeOld()
            refreshUI()
            footerLbl.Text = string.format("✓ listen mode | total=%d | %s", #salesHistory, os.date("%H:%M:%S"))
            footerLbl.TextColor3 = C.success
            L("[Hist] refresh: listen-only mode, "..#salesHistory.." total")
        end)
    end

    -- v8.187: tombol IMPORT OLD - manual import dari UI templates (kalo user mau load history lama)
    -- Pindah TypeBtn ke kanan biar muat IMPORT
    local importOldBtn = Instance.new("TextButton")
    importOldBtn.Size = UDim2.new(0, 100, 0, 30)
    importOldBtn.Position = UDim2.new(1, -110, 0, 0)
    importOldBtn.BackgroundColor3 = Color3.fromRGB(220, 140, 40)
    importOldBtn.Text = "⬆ IMPORT OLD"
    importOldBtn.TextColor3 = Color3.new(0, 0, 0)
    importOldBtn.Font = FB
    importOldBtn.TextSize = 10
    importOldBtn.BorderSizePixel = 0
    importOldBtn.AutoButtonColor = false
    importOldBtn.Parent = actionRow
    Instance.new("UICorner", importOldBtn).CornerRadius = UDim.new(0, 6)

    importOldBtn.MouseButton1Click:Connect(function()
        task.spawn(function()
            local entries = parseFromNativeUI()
            local added = 0
            for _, e in ipairs(entries) do
                if addEntry(e) then added = added + 1 end
            end
            purgeOld(); refreshUI()
            footerLbl.Text = string.format("⬆ IMPORTED +%d dari UI templates", added)
            footerLbl.TextColor3 = C.accent
        end)
    end)

    -- ===== Realtime AddToHistory subscribe =====
    if addHistRE then
        addHistRE.OnClientEvent:Connect(function(...)
            local args = {...}
            for _, a in ipairs(args) do
                if type(a) == "table" and addEntry(a) then
                    purgeOld(); refreshUI()
                    footerLbl.Text = "🔔 NEW SALE @ "..os.date("%H:%M:%S")
                    footerLbl.TextColor3 = C.success
                end
            end
        end)
    end

    -- ===== v8.190: USER LIST Modal (buyer list dgn copy) =====
    local userPicker = Instance.new("Frame")
    userPicker.Size = UDim2.new(0, 320, 0, 380)
    userPicker.Position = UDim2.new(0.5, -160, 0.5, -190)
    userPicker.BackgroundColor3 = C.panel
    userPicker.BorderSizePixel = 0
    userPicker.Visible = false
    userPicker.ZIndex = 50
    userPicker.Parent = hp
    Instance.new("UICorner", userPicker).CornerRadius = UDim.new(0, 10)
    do
        local s = Instance.new("UIStroke", userPicker)
        s.Color = C.accent; s.Thickness = 1; s.Transparency = 0.5
    end

    do
        local uTitle = Instance.new("TextLabel")
        uTitle.Size = UDim2.new(1, -50, 0, 30) uTitle.Position = UDim2.new(0, 12, 0, 8)
        uTitle.BackgroundTransparency = 1 uTitle.Text = "User List"
        uTitle.TextColor3 = C.accent uTitle.Font = FB uTitle.TextSize = 14
        uTitle.TextXAlignment = Enum.TextXAlignment.Left
        uTitle.ZIndex = 51 uTitle.Parent = userPicker

        local uClose = Instance.new("TextButton")
        uClose.Size = UDim2.new(0, 28, 0, 28) uClose.Position = UDim2.new(1, -36, 0, 8)
        uClose.BackgroundColor3 = C.card uClose.AutoButtonColor = false
        uClose.Text = "×" uClose.TextColor3 = C.text
        uClose.Font = FB uClose.TextSize = 16 uClose.BorderSizePixel = 0
        uClose.ZIndex = 51 uClose.Parent = userPicker
        Instance.new("UICorner", uClose).CornerRadius = UDim.new(0, 5)
        uClose.MouseButton1Click:Connect(function() userPicker.Visible = false end)
    end

    local uSearch = Instance.new("TextBox")
    uSearch.Size = UDim2.new(1, -24, 0, 30) uSearch.Position = UDim2.new(0, 12, 0, 44)
    uSearch.BackgroundColor3 = C.input uSearch.BorderSizePixel = 0
    uSearch.Text = "" uSearch.PlaceholderText = "🔍  Cari username..."
    uSearch.PlaceholderColor3 = C.textDim
    uSearch.TextColor3 = C.text uSearch.Font = FM uSearch.TextSize = 12
    uSearch.ClearTextOnFocus = false uSearch.ZIndex = 51
    uSearch.Parent = userPicker
    Instance.new("UICorner", uSearch).CornerRadius = UDim.new(0, 5)

    local uScroll = Instance.new("ScrollingFrame")
    uScroll.Size = UDim2.new(1, -24, 1, -90) uScroll.Position = UDim2.new(0, 12, 0, 82)
    uScroll.BackgroundTransparency = 1 uScroll.BorderSizePixel = 0
    uScroll.ScrollBarThickness = 4 uScroll.ScrollBarImageColor3 = C.accent
    uScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    uScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    uScroll.ZIndex = 51 uScroll.Parent = userPicker
    do
        local lay = Instance.new("UIListLayout")
        lay.Padding = UDim.new(0, 4); lay.Parent = uScroll
    end

    local function refreshUserList()
        for _, c in ipairs(uScroll:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
        end
        local query = tostring(uSearch.Text):lower()
        local sorted = {}
        for name, cnt in pairs(BH.buyerCounts or {}) do
            if query == "" or tostring(name):lower():find(query, 1, true) then
                table.insert(sorted, {name = name, count = cnt})
            end
        end
        table.sort(sorted, function(a, b)
            if a.count == b.count then return a.name < b.name end
            return a.count > b.count
        end)

        if #sorted == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, 0, 0, 30) empty.BackgroundTransparency = 1
            empty.Text = "Belum ada buyer ke-track"
            empty.TextColor3 = C.textDim empty.Font = FM empty.TextSize = 11
            empty.ZIndex = 52 empty.Parent = uScroll
            return
        end

        for _, u in ipairs(sorted) do
            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1, 0, 0, 32)
            row.BackgroundColor3 = C.card
            row.AutoButtonColor = false
            row.Text = ""
            row.ZIndex = 52
            row.Parent = uScroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

            local nlbl = Instance.new("TextLabel")
            nlbl.Size = UDim2.new(1, -50, 1, 0) nlbl.Position = UDim2.new(0, 12, 0, 0)
            nlbl.BackgroundTransparency = 1
            nlbl.Text = u.name
            nlbl.TextColor3 = C.text nlbl.Font = FM nlbl.TextSize = 12
            nlbl.TextXAlignment = Enum.TextXAlignment.Left
            nlbl.TextTruncate = Enum.TextTruncate.AtEnd
            nlbl.ZIndex = 53 nlbl.Parent = row

            local cntLbl = Instance.new("TextLabel")
            cntLbl.Size = UDim2.new(0, 40, 1, 0) cntLbl.Position = UDim2.new(1, -46, 0, 0)
            cntLbl.BackgroundTransparency = 1
            cntLbl.Text = "("..u.count..")"
            cntLbl.TextColor3 = C.accent cntLbl.Font = FB cntLbl.TextSize = 11
            cntLbl.ZIndex = 53 cntLbl.Parent = row

            row.MouseButton1Click:Connect(function()
                local copyFn = setclipboard or (toclipboard) or (writeclipboard)
                if copyFn then
                    pcall(copyFn, u.name)
                    nlbl.Text = "✓ "..u.name.." copied!"
                    nlbl.TextColor3 = C.success
                    task.delay(1.2, function()
                        if nlbl.Parent then
                            nlbl.Text = u.name
                            nlbl.TextColor3 = C.text
                        end
                    end)
                else
                    nlbl.Text = "✗ executor no clipboard fn"
                    nlbl.TextColor3 = C.danger
                end
            end)
        end
    end

    uSearch:GetPropertyChangedSignal("Text"):Connect(refreshUserList)
    userListBtn.MouseButton1Click:Connect(function()
        userPicker.Visible = not userPicker.Visible
        if userPicker.Visible then refreshUserList() end
    end)

    -- ===== Pet Type Picker Modal =====
    local picker = Instance.new("Frame")
    picker.Size = UDim2.new(0, 320, 0, 380)
    picker.Position = UDim2.new(0.5, -160, 0.5, -190)
    picker.BackgroundColor3 = C.panel picker.BorderSizePixel = 0
    picker.Visible = false picker.ZIndex = 50
    picker.Parent = hp
    Instance.new("UICorner", picker).CornerRadius = UDim.new(0, 10)
    do
        local s = Instance.new("UIStroke", picker)
        s.Color = C.accent; s.Thickness = 1; s.Transparency = 0.5
    end

    do
        local pTitle = Instance.new("TextLabel")
        pTitle.Size = UDim2.new(1, -50, 0, 30) pTitle.Position = UDim2.new(0, 12, 0, 8)
        pTitle.BackgroundTransparency = 1 pTitle.Text = "Pilih jenis pet"
        pTitle.TextColor3 = C.accent pTitle.Font = FB pTitle.TextSize = 14
        pTitle.TextXAlignment = Enum.TextXAlignment.Left
        pTitle.ZIndex = 51 pTitle.Parent = picker

        local pClose = Instance.new("TextButton")
        pClose.Size = UDim2.new(0, 28, 0, 28) pClose.Position = UDim2.new(1, -36, 0, 8)
        pClose.BackgroundColor3 = C.card pClose.AutoButtonColor = false
        pClose.Text = "×" pClose.TextColor3 = C.text
        pClose.Font = FB pClose.TextSize = 16 pClose.BorderSizePixel = 0
        pClose.ZIndex = 51 pClose.Parent = picker
        Instance.new("UICorner", pClose).CornerRadius = UDim.new(0, 5)
        pClose.MouseButton1Click:Connect(function() picker.Visible = false end)
    end

    local pSearch = Instance.new("TextBox")
    pSearch.Size = UDim2.new(1, -24, 0, 30) pSearch.Position = UDim2.new(0, 12, 0, 44)
    pSearch.BackgroundColor3 = C.input pSearch.BorderSizePixel = 0
    pSearch.Text = "" pSearch.PlaceholderText = "🔍  Cari nama pet..."
    pSearch.PlaceholderColor3 = C.textDim
    pSearch.TextColor3 = C.text pSearch.Font = FM pSearch.TextSize = 12
    pSearch.ClearTextOnFocus = false
    pSearch.TextXAlignment = Enum.TextXAlignment.Left
    pSearch.ZIndex = 51 pSearch.Parent = picker
    Instance.new("UICorner", pSearch).CornerRadius = UDim.new(0, 6)
    do
        local p = Instance.new("UIPadding")
        p.PaddingLeft = UDim.new(0, 10) p.PaddingRight = UDim.new(0, 10) p.Parent = pSearch
    end

    local allRowBtn = Instance.new("TextButton")
    allRowBtn.Size = UDim2.new(1, -24, 0, 32) allRowBtn.Position = UDim2.new(0, 12, 0, 84)
    allRowBtn.BackgroundColor3 = C.card allRowBtn.AutoButtonColor = false
    allRowBtn.Text = "✓  All Pets" allRowBtn.TextColor3 = C.accent
    allRowBtn.Font = FB allRowBtn.TextSize = 13
    allRowBtn.TextXAlignment = Enum.TextXAlignment.Left allRowBtn.BorderSizePixel = 0
    allRowBtn.ZIndex = 51 allRowBtn.Parent = picker
    Instance.new("UICorner", allRowBtn).CornerRadius = UDim.new(0, 5)
    do
        local p = Instance.new("UIPadding")
        p.PaddingLeft = UDim.new(0, 12) p.Parent = allRowBtn
    end

    local pScroll = Instance.new("ScrollingFrame")
    pScroll.Size = UDim2.new(1, -24, 1, -136) pScroll.Position = UDim2.new(0, 12, 0, 124)
    pScroll.BackgroundColor3 = C.card pScroll.BorderSizePixel = 0
    pScroll.ScrollBarThickness = 4 pScroll.ScrollBarImageColor3 = C.accent
    pScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    pScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    pScroll.ZIndex = 51 pScroll.Parent = picker
    Instance.new("UICorner", pScroll).CornerRadius = UDim.new(0, 6)
    do
        local lay = Instance.new("UIListLayout")
        lay.Padding = UDim.new(0, 3) lay.Parent = pScroll
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 4) pad.PaddingBottom = UDim.new(0, 4)
        pad.PaddingLeft = UDim.new(0, 4) pad.PaddingRight = UDim.new(0, 4)
        pad.Parent = pScroll
    end

    local function renderPicker(filter)
        for _, c in ipairs(pScroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        filter = (filter or ""):lower()
        if not selectedType then
            allRowBtn.BackgroundColor3 = C.accent
            allRowBtn.TextColor3 = Color3.new(0, 0, 0)
            allRowBtn.Text = "✓  All Pets"
        else
            allRowBtn.BackgroundColor3 = C.card
            allRowBtn.TextColor3 = C.text
            allRowBtn.Text = "   All Pets"
        end
        local salesByType = {}
        for _, s in ipairs(salesHistory) do
            salesByType[s.petType] = (salesByType[s.petType] or 0) + 1
        end
        local typesSet = {}
        for _, n in ipairs(allPetTypes) do typesSet[n] = true end
        for t in pairs(salesByType) do typesSet[t] = true end
        local list = {}
        for n in pairs(typesSet) do
            table.insert(list, {name = n, count = salesByType[n] or 0})
        end
        table.sort(list, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)
        for _, it in ipairs(list) do
            if filter == "" or it.name:lower():find(filter, 1, true) then
                local b = Instance.new("TextButton")
                b.Size = UDim2.new(1, -8, 0, 30)
                b.BackgroundColor3 = (selectedType == it.name) and C.accent or C.card
                b.TextColor3 = (selectedType == it.name) and Color3.new(0,0,0) or C.text
                b.BorderSizePixel = 0 b.AutoButtonColor = false
                b.Text = it.name..(it.count > 0 and "   ("..it.count..")" or "")
                b.Font = FM b.TextSize = 12
                b.TextXAlignment = Enum.TextXAlignment.Left
                b.ZIndex = 52 b.Parent = pScroll
                Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
                local p = Instance.new("UIPadding") p.PaddingLeft = UDim.new(0, 12); p.Parent = b
                b.MouseButton1Click:Connect(function()
                    selectedType = it.name
                    typeBtn.Text = "▼  "..it.name
                    picker.Visible = false
                    refreshUI()
                end)
            end
        end
    end

    pSearch:GetPropertyChangedSignal("Text"):Connect(function() renderPicker(pSearch.Text) end)
    allRowBtn.MouseButton1Click:Connect(function()
        selectedType = nil
        typeBtn.Text = "▼  All Pets"
        picker.Visible = false
        refreshUI()
    end)
    typeBtn.MouseButton1Click:Connect(function()
        picker.Visible = not picker.Visible
        if picker.Visible then renderPicker(pSearch.Text or "") end
    end)

    -- ===== Buttons =====
    clearBtn.MouseButton1Click:Connect(function()
        salesHistory = {} salesByKey = {} elapsedStartEpoch = os.time()
        saveHist()
        refreshUI()
        footerLbl.Text = "Cleared (local view)" footerLbl.TextColor3 = C.textDim
    end)
    sortBtn.MouseButton1Click:Connect(function()
        if sortMode == "newest" then sortMode = "price_high"; sortBtn.Text = "Sort: PRICE HIGH"
        elseif sortMode == "price_high" then sortMode = "price_low"; sortBtn.Text = "Sort: PRICE LOW"
        else sortMode = "newest"; sortBtn.Text = "Sort: NEWEST" end
        refreshUI()
    end)

    -- ===== Auto-fetch saat tab dibuka =====
    hp:GetPropertyChangedSignal("Visible"):Connect(function()
        if hp.Visible then task.spawn(fetchHistory) end
    end)

    -- ===== Elapsed timer (1s tick) =====
    task.spawn(function()
        while gui.Parent do
            if hp.Visible then
                local sec = os.time() - elapsedStartEpoch
                local txt
                if sec < 60 then txt = sec.."s"
                elseif sec < 3600 then txt = math.floor(sec/60).."m "..(sec%60).."s"
                elseif sec < 86400 then txt = math.floor(sec/3600).."h "..math.floor((sec%3600)/60).."m"
                else txt = math.floor(sec/86400).."d "..math.floor((sec%86400)/3600).."h" end
                elapsedLbl.Text = "⏱  "..txt
            end
            task.wait(1)
        end
    end)

    -- ===== Refresh relative timestamps tiap 30s =====
    task.spawn(function()
        while gui.Parent do
            task.wait(30)
            if hp.Visible and #salesHistory > 0 then refreshUI() end
        end
    end)

    -- ===== Initial fetch =====
    -- v8.187: SKIP auto-fetch on load — supaya UI templates lama gak ke-import otomatis sebagai entry baru.
    -- User bisa klik IMPORT OLD button kalo mau load history dari template UI.
    -- Sale baru sesi ini → auto masuk via AddToHistory event subscribe.

    -- v8.189: Refresh frequent buyers on init
    if BH.refreshFrequentBuyers then BH.refreshFrequentBuyers() end

    refreshUI()
end)()


-- v8.253: ambil batas pet inventory (MaxPetsInInventory) dari memory game.
-- cache 5s biar getgc gak berat. ambil nilai TERBESAR valid (hindari template default).
local _pulseMaxPetsCache, _pulseMaxPetsTime = nil, 0
local function getMaxPetsPulse()
    if _pulseMaxPetsCache and (tick() - _pulseMaxPetsTime) < 5 then return _pulseMaxPetsCache end
    local best = nil
    if getgc then
        pcall(function()
            for _, obj in ipairs(getgc(true)) do
                if type(obj) == "table" then
                    local mp = rawget(obj, "MaxPetsInInventory")
                    if type(mp) == "number" and mp > 0 then
                        if not best or mp > best then best = mp end
                    end
                end
            end
        end)
    end
    -- fallback: atribut player kalau memory gak ketemu
    if not best then
        for _, attr in ipairs({"MaxPetsInInventory", "MaxPets", "MaxInventory"}) do
            local v = player:GetAttribute(attr)
            if v and tonumber(v) and tonumber(v) > 0 then best = tonumber(v) break end
        end
    end
    _pulseMaxPetsCache = best; _pulseMaxPetsTime = tick()
    return best
end

-- v8.49: GARDEN PANEL UI build (server-detect)
BH.buildGardenPanel = function()
    local gp = BH.gardenPanel
    if not gp then return end

    local btnPad = 4
    local btnRow = Instance.new("Frame")
    btnRow.Size = UDim2.new(1, -28, 0, 28) btnRow.Position = UDim2.new(0, 14, 0, 14)
    btnRow.BackgroundTransparency = 1 btnRow.Parent = gp

    -- v8.160: restore Auto Accept Gift/Trade (KHUSUS garden server)
    local gGiftBtn = Instance.new("TextButton")
    gGiftBtn.Size = UDim2.new(0.33, -btnPad, 1, 0)
    gGiftBtn.Position = UDim2.new(0, 0, 0, 0)
    gGiftBtn.BackgroundColor3 = C.card gGiftBtn.AutoButtonColor = false
    gGiftBtn.Text = "Auto Accept Gift: OFF" gGiftBtn.TextColor3 = C.textDim
    gGiftBtn.Font = FM gGiftBtn.TextSize = 11
    gGiftBtn.BorderSizePixel = 0 gGiftBtn.Parent = btnRow
    Instance.new("UICorner", gGiftBtn).CornerRadius = UDim.new(0, 6)

    local gTradeBtn = Instance.new("TextButton")
    gTradeBtn.Size = UDim2.new(0.33, -btnPad, 1, 0)
    gTradeBtn.Position = UDim2.new(0.335, btnPad/2, 0, 0)
    gTradeBtn.BackgroundColor3 = C.card gTradeBtn.AutoButtonColor = false
    gTradeBtn.Text = "Auto Accept Trade: OFF" gTradeBtn.TextColor3 = C.textDim
    gTradeBtn.Font = FM gTradeBtn.TextSize = 11
    gTradeBtn.BorderSizePixel = 0 gTradeBtn.Parent = btnRow
    Instance.new("UICorner", gTradeBtn).CornerRadius = UDim.new(0, 6)

    local gTravelBtn = Instance.new("TextButton")
    gTravelBtn.Size = UDim2.new(0.33, -btnPad, 1, 0)
    gTravelBtn.Position = UDim2.new(0.67, btnPad, 0, 0)
    gTravelBtn.BackgroundColor3 = C.card
    gTravelBtn.AutoButtonColor = false
    gTravelBtn.Text = "🚀 TP Market" gTravelBtn.TextColor3 = C.textDim
    gTravelBtn.Font = FM gTravelBtn.TextSize = 11
    gTravelBtn.BorderSizePixel = 0 gTravelBtn.Parent = btnRow
    Instance.new("UICorner", gTravelBtn).CornerRadius = UDim.new(0, 6)

    -- ===== Auto-Accept logic (gift + trade) — DEFERRED scan biar buildGardenPanel gak block =====
    BH.autoGift = (BH.marketState and BH.marketState.autoGift) == true
    BH.autoTrade = (BH.marketState and BH.marketState.autoTrade) == true

    local function refreshAcceptUI()
        gGiftBtn.Text = "Auto Accept Gift: "..(BH.autoGift and "ON" or "OFF")
        gGiftBtn.TextColor3 = BH.autoGift and C.accent or C.textDim
        gTradeBtn.Text = "Auto Accept Trade: "..(BH.autoTrade and "ON" or "OFF")
        gTradeBtn.TextColor3 = BH.autoTrade and C.accent or C.textDim
    end
    refreshAcceptUI()

    gGiftBtn.MouseButton1Click:Connect(function()
        BH.autoGift = not BH.autoGift
        refreshAcceptUI()
        if BH.marketState then BH.marketState.autoGift = BH.autoGift; BH.saveMarketState(BH.marketState) end
        L("[AutoAccept] gift "..(BH.autoGift and "ON" or "OFF"))
    end)
    gTradeBtn.MouseButton1Click:Connect(function()
        BH.autoTrade = not BH.autoTrade
        refreshAcceptUI()
        if BH.marketState then BH.marketState.autoTrade = BH.autoTrade; BH.saveMarketState(BH.marketState) end
        L("[AutoAccept] trade "..(BH.autoTrade and "ON" or "OFF"))
    end)

    -- v8.168: AUTO-ACCEPT precise — port dari leveling sc (v12.10 confirmed working)
    -- Gift: GiftPet(uuid, name, sender) -> AcceptPetGift(true, uuid)
    -- Trade: SendRequest(tradeID, sender, ts) -> RespondRequest(tradeID, true) + spam Accept button

    -- v8.252: klik tombol Accept di popup Gift_Notification biar POPUP HILANG + pet keterima.
    -- Popup gift masuk: Gift_Notification/Frame/Gift_Notification/<Holder>/Frame/Accept (ImageButton).
    -- Tombol TIDAK simpan uuid -> klik UI = cara utama (server handle via handler client).
    local function _fireGuiBtn(btn)
        if not btn then return false end
        local ok = false
        if getconnections then
            pcall(function()
                for _, c in ipairs(getconnections(btn.MouseButton1Click)) do
                    if c.Fire then pcall(function() c:Fire() end)
                    elseif c.Function then pcall(function() c.Function() end) end
                    ok = true
                end
            end)
            pcall(function()
                for _, c in ipairs(getconnections(btn.MouseButton1Down)) do
                    if c.Fire then pcall(function() c:Fire() end)
                    elseif c.Function then pcall(function() c.Function() end) end
                end
            end)
            pcall(function()
                for _, c in ipairs(getconnections(btn.Activated)) do
                    if c.Fire then pcall(function() c:Fire() end)
                    elseif c.Function then pcall(function() c.Function() end) end
                    ok = true
                end
            end)
        end
        if firesignal then
            pcall(function() firesignal(btn.MouseButton1Down) end)
            pcall(function() firesignal(btn.MouseButton1Click) end)
            pcall(function() firesignal(btn.Activated) end)
            ok = true
        end
        return ok
    end

    local function acceptAllGiftPopups()
        local clicked = 0
        pcall(function()
            local pgg = player:FindFirstChild("PlayerGui")
            local gn = pgg and pgg:FindFirstChild("Gift_Notification")
            if not gn then return end
            local outer = gn:FindFirstChild("Frame")
            local inner = outer and (outer:FindFirstChild("Gift_Notification") or outer) or nil
            local container = inner or gn
            for _, holder in ipairs(container:GetChildren()) do
                local accept
                local fr = holder:FindFirstChild("Frame")
                if fr then accept = fr:FindFirstChild("Accept") end
                if not accept then
                    for _, dd in ipairs(holder:GetDescendants()) do
                        if dd.Name == "Accept" and dd:IsA("GuiButton") then accept = dd break end
                    end
                end
                if accept and accept:IsA("GuiButton") then
                    local vis = true
                    pcall(function() vis = accept.Visible end)
                    if vis then
                        if _fireGuiBtn(accept) then clicked = clicked + 1 end
                    end
                end
            end
        end)
        return clicked
    end

    task.spawn(function()
        task.wait(1)
        local ge = RS:FindFirstChild("GameEvents")
        if not ge then L("[AutoAccept] no GameEvents"); return end

        -- ===== GIFT =====
        local giftPetRE = ge:FindFirstChild("GiftPet")
        local acceptPetGiftRE = ge:FindFirstChild("AcceptPetGift")
        if giftPetRE and giftPetRE:IsA("RemoteEvent") then
            local count = 0
            giftPetRE.OnClientEvent:Connect(function(petUUID, petName, senderUsername)
                if not BH.autoGift then return end
                -- backup: fire remote kalau uuid valid
                if acceptPetGiftRE and acceptPetGiftRE:IsA("RemoteEvent") and type(petUUID) == "string" and #petUUID > 8 then
                    pcall(function() acceptPetGiftRE:FireServer(true, petUUID) end)
                end
                -- utama: klik tombol Accept di popup (popup hilang + pet keterima)
                task.spawn(function()
                    for _ = 1, 10 do
                        if not BH.autoGift then break end
                        local n = acceptAllGiftPopups()
                        if n > 0 then
                            count = count + 1
                            L("[AutoAccept-gift] klik "..n.." popup #"..count.." from "..tostring(senderUsername))
                            task.wait(0.3)
                        else
                            task.wait(0.25)
                        end
                    end
                end)
            end)
            L("[AutoAccept] gift hook INSTALLED (GiftPet -> klik popup Accept)")
        else
            L("[AutoAccept] WARN: GiftPet gak ketemu")
        end

        -- v8.252: loop pemindai mandiri — tangkap popup yg udah ada saat toggle ON,
        -- atau popup tanpa OnClientEvent. Tidak bergantung event.
        task.spawn(function()
            while true do
                task.wait(0.8)
                if BH.autoGift then
                    pcall(acceptAllGiftPopups)
                end
            end
        end)

        -- ===== TRADE =====
        local te = ge:FindFirstChild("TradeEvents")
        if te then
            local sendReqRE = te:FindFirstChild("SendRequest")
            local respondReqRE = te:FindFirstChild("RespondRequest")
            local acceptRE = te:FindFirstChild("Accept")
            local confirmRE = te:FindFirstChild("Confirm")

            local lastTradeID = nil
            local tradeAccCount = 0
            local spamRunning = false

            local function findTradeAcceptBtn()
                local pg = player:FindFirstChild("PlayerGui")
                local tui = pg and pg:FindFirstChild("TradingUI")
                local lt = tui and tui:FindFirstChild("LiveTrade")
                if not lt or not lt.Visible then return nil end
                local opts = lt:FindFirstChild("Options")
                local acc = opts and opts:FindFirstChild("Accept")
                return acc
            end

            local function spamConfirm()
                local btn = findTradeAcceptBtn()
                if not btn then return false end
                -- Fire Activated signal (yg game pake)
                if firesignal then pcall(function() firesignal(btn.Activated) end) end
                if getconnections then
                    pcall(function()
                        for _, c in ipairs(getconnections(btn.Activated)) do
                            pcall(function() c:Fire() end)
                        end
                    end)
                end
                -- Brute force remote backup
                if lastTradeID then
                    if confirmRE then pcall(function() confirmRE:FireServer(lastTradeID) end) end
                    if acceptRE then pcall(function() acceptRE:FireServer(lastTradeID) end) end
                end
                return true
            end

            local function startSpammer()
                if spamRunning then return end
                spamRunning = true
                task.spawn(function()
                    local iter = 0
                    while BH.autoTrade and spamRunning do
                        iter = iter + 1
                        local stillTrade = spamConfirm()
                        if not stillTrade then
                            if iter > 1 then L("[AutoAccept-trade] spammer stop (window closed)") end
                            break
                        end
                        if iter == 1 then L("[AutoAccept-trade] spammer started") end
                        task.wait(3)
                    end
                    spamRunning = false
                end)
            end

            for _, r in ipairs(te:GetChildren()) do
                if r:IsA("RemoteEvent") then
                    local lname = r.Name:lower()
                    if not (lname:find("history") or lname:find("inventory")) then
                        r.OnClientEvent:Connect(function(...)
                            if not BH.autoTrade then return end
                            local args = {...}
                            -- Extract tradeID dari arg[1]
                            if type(args[1]) == "string" and #args[1] > 20 and args[1]:find("%-") then
                                lastTradeID = args[1]
                            end
                            if lname:find("cancel") or lname:find("reject") or lname:find("decline") then
                                spamRunning = false
                                return
                            end
                            -- Stage 1: SendRequest -> RespondRequest(tradeID, true)
                            if r == sendReqRE and respondReqRE and lastTradeID then
                                local ok = pcall(function() respondReqRE:FireServer(lastTradeID, true) end)
                                if ok then
                                    tradeAccCount = tradeAccCount + 1
                                    L("[AutoAccept-trade] RespondRequest("..lastTradeID:sub(1,8)..", true)")
                                    task.delay(2, startSpammer)
                                end
                                return
                            end
                            -- Stage 2/3: UpdateTradeState -> spam
                            if r.Name == "UpdateTradeState" then
                                startSpammer()
                            end
                        end)
                    end
                end
            end
            L("[AutoAccept] trade hook INSTALLED (SendRequest -> RespondRequest + Accept button spam)")
        else
            L("[AutoAccept] WARN: TradeEvents folder gak ketemu")
        end
    end)

    gTravelBtn.MouseButton1Click:Connect(function()
        L("[TP-Market] mencari 'Travel to Farmer Market' button...")
        local fired = false
        local pg = player:FindFirstChild("PlayerGui")

        -- Method 1: scan PlayerGui buat button "Travel to Farmer Market" / "Trade" tab
        if pg then
            for _, d in ipairs(pg:GetDescendants()) do
                if (d:IsA("TextButton") or d:IsA("ImageButton")) and not fired then
                    local txt = ""
                    if d:IsA("TextButton") then txt = tostring(d.Text or "") end
                    local fullText = (txt.." "..d.Name):lower()
                    if fullText:find("travel.*market") or fullText:find("farmer.*market")
                       or fullText:find("travel.*trade") or fullText:find("travel.*farmer")
                       or fullText:find("totrademarket") or fullText:find("tofarmermarket") then
                        L("[TP-Market] found button: "..d:GetFullName().." text='"..txt.."'")
                        -- Make sure parent chain is visible
                        local cur = d.Parent
                        while cur and cur ~= pg do
                            if cur:IsA("Frame") or cur:IsA("ScrollingFrame") then
                                if not cur.Visible then cur.Visible = true end
                            end
                            cur = cur.Parent
                        end
                        -- Fire button: Activated signal + click event
                        pcall(function()
                            if firesignal then firesignal(d.Activated) end
                            if getconnections then
                                for _, c in ipairs(getconnections(d.MouseButton1Click)) do
                                    pcall(function() c:Fire() end)
                                end
                                for _, c in ipairs(getconnections(d.Activated)) do
                                    pcall(function() c:Fire() end)
                                end
                            end
                        end)
                        L("[TP-Market] ✅ fired button")
                        fired = true
                        break
                    end
                end
            end
        end
        if fired then return end

        -- Method 2: TP character ke portal part di workspace
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("BasePart") then
                    local n = d.Name:lower()
                    if n:find("marketportal") or n:find("tradeportal") or n:find("farmermarket")
                       or n:find("marketteleport") or n:find("tradeteleport") then
                        hrp.CFrame = d.CFrame + Vector3.new(0, 5, 0)
                        L("[TP-Market] ✅ TP char ke portal: "..d:GetFullName())
                        fired = true
                        break
                    end
                end
            end
        end
        if fired then return end

        -- Method 3: Fire remote dengan keyword
        for _, c in ipairs(RS:GetDescendants()) do
            if (c:IsA("RemoteEvent") or c:IsA("RemoteFunction")) and not fired then
                local n = c.Name:lower()
                if n:find("farmermarket") or n:find("tofarmer") or n:find("travelto")
                   or n:find("trademarket") or n:find("entermarket") or n:find("gotomarket") then
                    L("[TP-Market] try remote: "..c:GetFullName())
                    pcall(function()
                        if c:IsA("RemoteFunction") then c:InvokeServer()
                        else c:FireServer() end
                    end)
                    fired = true
                    break
                end
            end
        end
        if fired then L("[TP-Market] ✅ remote fired"); return end

        -- Method 4: Diagnostic — list all relevant buttons
        L("[TP-Market] ❌ no method work. Diagnostic, kandidat buttons:")
        if pg then
            local count = 0
            for _, d in ipairs(pg:GetDescendants()) do
                if (d:IsA("TextButton") or d:IsA("ImageButton")) and count < 10 then
                    local txt = d:IsA("TextButton") and tostring(d.Text or "") or ""
                    if txt ~= "" and (txt:lower():find("market") or txt:lower():find("trade")
                       or txt:lower():find("travel") or txt:lower():find("farmer")) then
                        L("  • "..d:GetFullName().." text='"..txt:sub(1,40).."'")
                        count = count + 1
                    end
                end
            end
            if count == 0 then L("  (gak nemu button apapun yg related)") end
        end
    end)

    local statsCard = Instance.new("Frame")
    statsCard.Size = UDim2.new(1, -28, 0, 44) statsCard.Position = UDim2.new(0, 14, 0, 50)
    statsCard.BackgroundColor3 = C.card statsCard.BorderSizePixel = 0
    statsCard.Parent = gp
    Instance.new("UICorner", statsCard).CornerRadius = UDim.new(0, 8)
    local gStatsLbl = Instance.new("TextLabel")
    gStatsLbl.Size = UDim2.new(1, -20, 1, -8) gStatsLbl.Position = UDim2.new(0, 12, 0, 4)
    gStatsLbl.BackgroundTransparency = 1
    gStatsLbl.Text = "Loading backpack..."
    gStatsLbl.TextColor3 = C.text gStatsLbl.Font = FM gStatsLbl.TextSize = 11
    gStatsLbl.TextXAlignment = Enum.TextXAlignment.Left
    gStatsLbl.TextYAlignment = Enum.TextYAlignment.Top
    gStatsLbl.TextWrapped = true gStatsLbl.Parent = statsCard

    -- v8.148: Filter tabs (ALL / 60kg+ / 60kg-) — based on age-1 normalized base weight
    local gardenFilter = "all"  -- "all", "60plus", "60minus"
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -28, 0, 28) tabBar.Position = UDim2.new(0, 14, 0, 100)
    tabBar.BackgroundTransparency = 1 tabBar.Parent = gp
    local function makeTab(text, x, w)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 1, 0) b.Position = UDim2.new(0, x, 0, 0)
        b.BackgroundColor3 = C.card b.AutoButtonColor = false
        b.Text = text b.TextColor3 = C.textDim
        b.Font = FB b.TextSize = 12 b.BorderSizePixel = 0
        b.Parent = tabBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        return b
    end
    local tabAll = makeTab("ALL", 0, 70)
    local tab60p = makeTab("60kg+", 76, 70)
    local tab60m = makeTab("60kg-", 152, 70)
    local tabGift = makeTab("🎁 GIFT", 228, 90)
    local function setTabActive(active)
        for _, b in ipairs({tabAll, tab60p, tab60m, tabGift}) do
            b.BackgroundColor3 = C.card
            b.TextColor3 = C.textDim
        end
        if active == "all" then tabAll.BackgroundColor3 = C.accent; tabAll.TextColor3 = Color3.new(0,0,0)
        elseif active == "60plus" then tab60p.BackgroundColor3 = C.accent; tab60p.TextColor3 = Color3.new(0,0,0)
        elseif active == "60minus" then tab60m.BackgroundColor3 = C.accent; tab60m.TextColor3 = Color3.new(0,0,0)
        elseif active == "gift" then tabGift.BackgroundColor3 = C.success; tabGift.TextColor3 = Color3.new(0,0,0)
        end
    end
    setTabActive("all")

    local gListScroll = Instance.new("ScrollingFrame")
    gListScroll.Size = UDim2.new(1, -28, 1, -142) gListScroll.Position = UDim2.new(0, 14, 0, 134)
    gListScroll.BackgroundColor3 = C.input gListScroll.BorderSizePixel = 0
    gListScroll.ScrollBarThickness = 4 gListScroll.ScrollBarImageColor3 = C.accent
    gListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    gListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    gListScroll.Parent = gp
    Instance.new("UICorner", gListScroll).CornerRadius = UDim.new(0, 6)
    do
        local lay = Instance.new("UIListLayout")
        lay.Padding = UDim.new(0, 3) lay.Parent = gListScroll
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 4) pad.PaddingBottom = UDim.new(0, 4)
        pad.PaddingLeft = UDim.new(0, 6) pad.PaddingRight = UDim.new(0, 6)
        pad.Parent = gListScroll
    end

    -- v8.151: 🎁 AUTO GIFT CARD — same area as gListScroll, toggled via tab
    local giftCard = Instance.new("Frame")
    giftCard.Size = gListScroll.Size
    giftCard.Position = gListScroll.Position
    giftCard.BackgroundColor3 = C.input
    giftCard.BorderSizePixel = 0
    giftCard.Visible = false  -- initial hidden, ALL tab default
    giftCard.Parent = gp
    Instance.new("UICorner", giftCard).CornerRadius = UDim.new(0, 6)

    -- ===== Gift state =====
    local giftSelectedTargets = {}  -- {[name]=true}
    local giftSelectedPets = {}  -- {[type]=true}
    local giftActive = false
    local giftStopReq = false
    local giftSent, giftFailed = 0, 0
    local giftMatchCount = 0

    -- Load from state
    if BH.marketState and BH.marketState.gardenGift then
        local g = BH.marketState.gardenGift
        if type(g.targets) == "table" then
            for _, n in ipairs(g.targets) do giftSelectedTargets[n] = true end
        end
        if type(g.pets) == "table" then
            for _, n in ipairs(g.pets) do giftSelectedPets[n] = true end
        end
    end

    local function persistGiftState()
        if not BH.marketState then return end
        local targets, pets = {}, {}
        for n in pairs(giftSelectedTargets) do table.insert(targets, n) end
        for n in pairs(giftSelectedPets) do table.insert(pets, n) end
        BH.marketState.gardenGift = {
            targets = targets, pets = pets,
            kg = (giftKgBox and giftKgBox.Text) or "",
            age = (giftAgeBox and giftAgeBox.Text) or "",
            active = giftActive,
        }
        BH.saveMarketState(BH.marketState)
    end

    -- ===== Layout inside giftCard =====
    -- Row 1: Title + TOTAL match count
    local gTitleLbl = Instance.new("TextLabel")
    gTitleLbl.Size = UDim2.new(1, -120, 0, 26) gTitleLbl.Position = UDim2.new(0, 12, 0, 8)
    gTitleLbl.BackgroundTransparency = 1 gTitleLbl.Text = "🎁 AUTO GIFT"
    gTitleLbl.TextColor3 = C.accent gTitleLbl.Font = FB gTitleLbl.TextSize = 15
    gTitleLbl.TextXAlignment = Enum.TextXAlignment.Left gTitleLbl.Parent = giftCard

    local gTotalLbl = Instance.new("TextLabel")
    gTotalLbl.Size = UDim2.new(0, 110, 0, 26) gTotalLbl.Position = UDim2.new(1, -120, 0, 8)
    gTotalLbl.BackgroundTransparency = 1 gTotalLbl.Text = "Match: 0"
    gTotalLbl.TextColor3 = C.text gTotalLbl.Font = FB gTotalLbl.TextSize = 14
    gTotalLbl.TextXAlignment = Enum.TextXAlignment.Right gTotalLbl.Parent = giftCard

    -- Row 2: Target picker + Pet picker
    local gTargetBtn = Instance.new("TextButton")
    gTargetBtn.Size = UDim2.new(0.5, -16, 0, 30) gTargetBtn.Position = UDim2.new(0, 12, 0, 42)
    gTargetBtn.BackgroundColor3 = C.card gTargetBtn.AutoButtonColor = false
    gTargetBtn.Text = "🎯 Target..." gTargetBtn.TextColor3 = C.text
    gTargetBtn.Font = FM gTargetBtn.TextSize = 12 gTargetBtn.BorderSizePixel = 0
    gTargetBtn.Parent = giftCard
    Instance.new("UICorner", gTargetBtn).CornerRadius = UDim.new(0, 5)

    local gPetBtn = Instance.new("TextButton")
    gPetBtn.Size = UDim2.new(0.5, -16, 0, 30) gPetBtn.Position = UDim2.new(0.5, 4, 0, 42)
    gPetBtn.BackgroundColor3 = C.card gPetBtn.AutoButtonColor = false
    gPetBtn.Text = "🐾 Pet Type..." gPetBtn.TextColor3 = C.text
    gPetBtn.Font = FM gPetBtn.TextSize = 12 gPetBtn.BorderSizePixel = 0
    gPetBtn.Parent = giftCard
    Instance.new("UICorner", gPetBtn).CornerRadius = UDim.new(0, 5)

    -- Row 3: KG min + Age min
    local function lblFor(parent, text, x, y, w)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(0, w, 0, 18) l.Position = UDim2.new(0, x, 0, y)
        l.BackgroundTransparency = 1 l.Text = text l.TextColor3 = C.textDim
        l.Font = FM l.TextSize = 11 l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = parent
        return l
    end
    lblFor(giftCard, "KG min:", 12, 80, 60)
    giftKgBox = Instance.new("TextBox")
    giftKgBox.Size = UDim2.new(0, 70, 0, 26) giftKgBox.Position = UDim2.new(0, 72, 0, 78)
    giftKgBox.BackgroundColor3 = C.card giftKgBox.Text = ""
    giftKgBox.PlaceholderText = "0" giftKgBox.TextColor3 = C.text
    giftKgBox.Font = FM giftKgBox.TextSize = 12 giftKgBox.BorderSizePixel = 0
    giftKgBox.ClearTextOnFocus = false giftKgBox.Parent = giftCard
    Instance.new("UICorner", giftKgBox).CornerRadius = UDim.new(0, 4)

    lblFor(giftCard, "Age min:", 160, 80, 60)
    giftAgeBox = Instance.new("TextBox")
    giftAgeBox.Size = UDim2.new(0, 70, 0, 26) giftAgeBox.Position = UDim2.new(0, 220, 0, 78)
    giftAgeBox.BackgroundColor3 = C.card giftAgeBox.Text = ""
    giftAgeBox.PlaceholderText = "0" giftAgeBox.TextColor3 = C.text
    giftAgeBox.Font = FM giftAgeBox.TextSize = 12 giftAgeBox.BorderSizePixel = 0
    giftAgeBox.ClearTextOnFocus = false giftAgeBox.Parent = giftCard
    Instance.new("UICorner", giftAgeBox).CornerRadius = UDim.new(0, 4)

    -- Load saved values
    if BH.marketState and BH.marketState.gardenGift then
        if BH.marketState.gardenGift.kg then giftKgBox.Text = BH.marketState.gardenGift.kg end
        if BH.marketState.gardenGift.age then giftAgeBox.Text = BH.marketState.gardenGift.age end
    end
    giftKgBox.FocusLost:Connect(persistGiftState)
    giftAgeBox.FocusLost:Connect(persistGiftState)

    -- Row 4: GIFT toggle + counters
    local giftToggle = Instance.new("TextButton")
    giftToggle.Size = UDim2.new(0.5, -16, 0, 32) giftToggle.Position = UDim2.new(0, 12, 0, 116)
    giftToggle.BackgroundColor3 = C.danger giftToggle.AutoButtonColor = false
    giftToggle.Text = "🎁 GIFT: OFF" giftToggle.TextColor3 = Color3.new(0, 0, 0)
    giftToggle.Font = FB giftToggle.TextSize = 13 giftToggle.BorderSizePixel = 0
    giftToggle.Parent = giftCard
    Instance.new("UICorner", giftToggle).CornerRadius = UDim.new(0, 5)

    local giftCounterLbl = Instance.new("TextLabel")
    giftCounterLbl.Size = UDim2.new(0.5, -16, 0, 32) giftCounterLbl.Position = UDim2.new(0.5, 4, 0, 116)
    giftCounterLbl.BackgroundTransparency = 1 giftCounterLbl.Text = "Sent: 0   Failed: 0"
    giftCounterLbl.TextColor3 = C.text giftCounterLbl.Font = FM giftCounterLbl.TextSize = 13
    giftCounterLbl.TextXAlignment = Enum.TextXAlignment.Left giftCounterLbl.Parent = giftCard

    local giftStatusLbl = Instance.new("TextLabel")
    giftStatusLbl.Size = UDim2.new(1, -24, 0, 22) giftStatusLbl.Position = UDim2.new(0, 12, 0, 154)
    giftStatusLbl.BackgroundTransparency = 1 giftStatusLbl.Text = "Status: idle"
    giftStatusLbl.TextColor3 = C.textDim giftStatusLbl.Font = FM giftStatusLbl.TextSize = 11
    giftStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
    giftStatusLbl.TextTruncate = Enum.TextTruncate.AtEnd giftStatusLbl.Parent = giftCard

    -- Helper labels (under status)
    local giftPickedLbl = Instance.new("TextLabel")
    giftPickedLbl.Size = UDim2.new(1, -24, 0, 18) giftPickedLbl.Position = UDim2.new(0, 12, 0, 180)
    giftPickedLbl.BackgroundTransparency = 1 giftPickedLbl.Text = "Targets: 0 | Pet types: 0"
    giftPickedLbl.TextColor3 = C.textDim giftPickedLbl.Font = FM giftPickedLbl.TextSize = 11
    giftPickedLbl.TextXAlignment = Enum.TextXAlignment.Left giftPickedLbl.Parent = giftCard

    -- ===== Gift remote setup =====
    local outGiftRE = nil
    local outPGS = nil
    pcall(function()
        local ge = RS:FindFirstChild("GameEvents")
        if ge then outGiftRE = ge:FindFirstChild("PetGiftingService") end
        if not outGiftRE then outGiftRE = RS:FindFirstChild("PetGiftingService", true) end
    end)
    pcall(function()
        local mods = RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("PetServices")
        local gm = mods and mods:FindFirstChild("PetGiftingInputService")
        if gm then
            local ok, mod = pcall(require, gm)
            if ok then outPGS = mod end
        end
    end)

    -- ===== Helpers =====
    local function isFavPet(t)
        if t:GetAttribute("FAVORITE") == true then return true end
        if t:GetAttribute("IsFavorited") == true then return true end
        if t:GetAttribute("Favorited") == true then return true end
        return false
    end

    local function petMatchesGiftFilter(t)
        if not isPet(t) then return false end
        if isFavPet(t) then return false end  -- skip favorit
        local pt = getPetType(t)
        local baseName = (BH.getBaseName and pt ~= "") and BH.getBaseName(pt) or pt
        -- Pet type filter
        local hasPetFilter = next(giftSelectedPets) ~= nil
        if hasPetFilter then
            if not (giftSelectedPets[baseName] or giftSelectedPets[pt]) then return false end
        end
        -- KG min filter (basis age-1)
        local kgMin = tonumber(giftKgBox.Text) or 0
        if kgMin > 0 then
            local bk = getBaseKg(t)
            if not bk or bk < kgMin then return false end
        end
        -- Age min filter
        local ageMin = tonumber(giftAgeBox.Text) or 0
        if ageMin > 0 then
            local age = getAge(t) or 0
            if age < ageMin then return false end
        end
        return true
    end

    local function findGiftPlayer(name)
        if not name or name == "" then return nil end
        local low = name:lower()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and (p.Name:lower() == low or p.DisplayName:lower() == low) then return p end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and (p.Name:lower():find(low, 1, true) or p.DisplayName:lower():find(low, 1, true)) then return p end
        end
        return nil
    end

    local function giftPetToTarget(targetPlayer, petTool)
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        -- v8.272: dipercepat (0.1/0.25/0.4 -> equip 0.12 / give 0.18, hapus unequip + fire ganda)
        pcall(function() hum:EquipTool(petTool) end)
        task.wait(0.12)
        local sent = false
        if outPGS and outPGS.GivePet then
            pcall(function() outPGS.GivePet(targetPlayer) end)
            task.wait(0.18)
            if not petTool.Parent then return true end
        end
        if outGiftRE then
            local uuid = petTool:GetAttribute("PET_UUID")
            local u = tostring(uuid)
            if u:sub(1,1) ~= "{" then u = "{"..u.."}" end
            pcall(function() outGiftRE:FireServer("GivePet", targetPlayer, u) end)
            task.wait(0.18)
            if not petTool.Parent then sent = true end
        end
        return sent
    end

    -- Update displays
    local function updateGiftDisplay()
        local nt = 0; for _ in pairs(giftSelectedTargets) do nt = nt + 1 end
        local np = 0; for _ in pairs(giftSelectedPets) do np = np + 1 end
        gTargetBtn.Text = nt > 0 and ("🎯 "..nt.." target") or "🎯 Target..."
        gPetBtn.Text = np > 0 and ("🐾 "..np.." pet type") or "🐾 Pet Type..."
        giftPickedLbl.Text = string.format("Targets: %d | Pet types: %d", nt, np)
        -- Refresh match count
        local bp = player:FindFirstChild("Backpack")
        local cnt = 0
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if petMatchesGiftFilter(t) then cnt = cnt + 1 end
            end
        end
        giftMatchCount = cnt
        gTotalLbl.Text = "Match: "..cnt
    end

    -- Refresh match count periodically
    task.spawn(function()
        while giftCard.Parent do
            if giftCard.Visible then pcall(updateGiftDisplay) end
            task.wait(2)
        end
    end)

    -- ===== Target Picker Modal =====
    local function openTargetPicker()
        local overlay = Instance.new("Frame")
        overlay.Size = UDim2.new(1, 0, 1, 0) overlay.Position = UDim2.new(0, 0, 0, 0)
        overlay.BackgroundColor3 = Color3.new(0, 0, 0) overlay.BackgroundTransparency = 0.5
        overlay.ZIndex = 200 overlay.Parent = gui

        local mFrame = Instance.new("Frame")
        mFrame.Size = UDim2.new(0, 360, 0, 380)
        mFrame.Position = UDim2.new(0.5, -180, 0.5, -190)
        mFrame.BackgroundColor3 = C.bg mFrame.BorderSizePixel = 0
        mFrame.ZIndex = 201 mFrame.Parent = overlay
        Instance.new("UICorner", mFrame).CornerRadius = UDim.new(0, 8)
        local s = Instance.new("UIStroke", mFrame); s.Color = C.accent; s.Thickness = 2

        local tbar = Instance.new("Frame")
        tbar.Size = UDim2.new(1, 0, 0, 36) tbar.BackgroundColor3 = C.card
        tbar.BorderSizePixel = 0 tbar.ZIndex = 202 tbar.Parent = mFrame
        Instance.new("UICorner", tbar).CornerRadius = UDim.new(0, 8)

        local tlbl = Instance.new("TextLabel")
        tlbl.Size = UDim2.new(1, -120, 1, 0) tlbl.Position = UDim2.new(0, 12, 0, 0)
        tlbl.BackgroundTransparency = 1 tlbl.Text = "Target (multi)"
        tlbl.TextColor3 = C.accent tlbl.Font = FB tlbl.TextSize = 14
        tlbl.TextXAlignment = Enum.TextXAlignment.Left tlbl.ZIndex = 202 tlbl.Parent = tbar

        local doneBtn = Instance.new("TextButton")
        doneBtn.Size = UDim2.new(0, 60, 0, 24) doneBtn.Position = UDim2.new(1, -110, 0.5, -12)
        doneBtn.BackgroundColor3 = C.success doneBtn.Text = "DONE"
        doneBtn.TextColor3 = Color3.new(0, 0, 0) doneBtn.Font = FB doneBtn.TextSize = 11
        doneBtn.BorderSizePixel = 0 doneBtn.AutoButtonColor = false
        doneBtn.ZIndex = 203 doneBtn.Parent = tbar
        Instance.new("UICorner", doneBtn).CornerRadius = UDim.new(0, 4)

        local clrBtn = Instance.new("TextButton")
        clrBtn.Size = UDim2.new(0, 40, 0, 24) clrBtn.Position = UDim2.new(1, -46, 0.5, -12)
        clrBtn.BackgroundColor3 = C.danger clrBtn.Text = "CLR"
        clrBtn.TextColor3 = Color3.new(1, 1, 1) clrBtn.Font = FB clrBtn.TextSize = 11
        clrBtn.BorderSizePixel = 0 clrBtn.AutoButtonColor = false
        clrBtn.ZIndex = 203 clrBtn.Parent = tbar
        Instance.new("UICorner", clrBtn).CornerRadius = UDim.new(0, 4)

        local searchBox = Instance.new("TextBox")
        searchBox.Size = UDim2.new(1, -24, 0, 28) searchBox.Position = UDim2.new(0, 12, 0, 46)
        searchBox.BackgroundColor3 = C.card searchBox.Text = ""
        searchBox.PlaceholderText = "Cari player..." searchBox.TextColor3 = C.text
        searchBox.Font = FM searchBox.TextSize = 12 searchBox.BorderSizePixel = 0
        searchBox.ClearTextOnFocus = false searchBox.ZIndex = 202 searchBox.Parent = mFrame
        Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 4)

        local pScroll = Instance.new("ScrollingFrame")
        pScroll.Size = UDim2.new(1, -24, 1, -90) pScroll.Position = UDim2.new(0, 12, 0, 82)
        pScroll.BackgroundColor3 = C.card pScroll.BorderSizePixel = 0
        pScroll.ScrollBarThickness = 4 pScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        pScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        pScroll.ZIndex = 202 pScroll.Parent = mFrame
        Instance.new("UICorner", pScroll).CornerRadius = UDim.new(0, 4)
        local lay = Instance.new("UIListLayout"); lay.Padding = UDim.new(0, 3); lay.Parent = pScroll
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 4) pad.PaddingBottom = UDim.new(0, 4)
        pad.PaddingLeft = UDim.new(0, 4) pad.PaddingRight = UDim.new(0, 4)
        pad.Parent = pScroll

        local function renderList(filter)
            for _, c in ipairs(pScroll:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end
            filter = (filter or ""):lower()
            local items = {}
            local seen = {}
            -- Selected first
            for n in pairs(giftSelectedTargets) do
                local p = findGiftPlayer(n)
                table.insert(items, {name=n, online=(p ~= nil), picked=true})
                seen[n:lower()] = true
            end
            -- Online players
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= player and not seen[p.Name:lower()] then
                    table.insert(items, {name=p.Name, online=true, picked=false})
                end
            end
            for _, it in ipairs(items) do
                if filter == "" or it.name:lower():find(filter, 1, true) then
                    local row = Instance.new("TextButton")
                    row.Size = UDim2.new(1, -4, 0, 28)
                    if it.picked then
                        row.BackgroundColor3 = C.success
                        row.TextColor3 = Color3.new(0, 0, 0)
                    else
                        row.BackgroundColor3 = C.bg
                        row.TextColor3 = C.text
                    end
                    row.Text = (it.picked and "v " or "  ")..it.name..(it.online and "" or " (offline)")
                    row.Font = FM row.TextSize = 12 row.TextXAlignment = Enum.TextXAlignment.Left
                    row.BorderSizePixel = 0 row.AutoButtonColor = false
                    row.ZIndex = 203 row.Parent = pScroll
                    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
                    Instance.new("UIPadding", row).PaddingLeft = UDim.new(0, 10)
                    row.MouseButton1Click:Connect(function()
                        if giftSelectedTargets[it.name] then
                            giftSelectedTargets[it.name] = nil
                        else
                            giftSelectedTargets[it.name] = true
                        end
                        persistGiftState()
                        updateGiftDisplay()
                        renderList(searchBox.Text)
                    end)
                end
            end
        end
        renderList("")
        searchBox:GetPropertyChangedSignal("Text"):Connect(function() renderList(searchBox.Text) end)

        doneBtn.MouseButton1Click:Connect(function() overlay:Destroy() end)
        clrBtn.MouseButton1Click:Connect(function()
            giftSelectedTargets = {}
            persistGiftState()
            updateGiftDisplay()
            renderList(searchBox.Text)
        end)
    end
    gTargetBtn.MouseButton1Click:Connect(openTargetPicker)

    -- ===== Pet Picker Modal =====
    local function openPetPicker()
        local overlay = Instance.new("Frame")
        overlay.Size = UDim2.new(1, 0, 1, 0)
        overlay.BackgroundColor3 = Color3.new(0, 0, 0) overlay.BackgroundTransparency = 0.5
        overlay.ZIndex = 200 overlay.Parent = gui

        local mFrame = Instance.new("Frame")
        mFrame.Size = UDim2.new(0, 360, 0, 380)
        mFrame.Position = UDim2.new(0.5, -180, 0.5, -190)
        mFrame.BackgroundColor3 = C.bg mFrame.BorderSizePixel = 0
        mFrame.ZIndex = 201 mFrame.Parent = overlay
        Instance.new("UICorner", mFrame).CornerRadius = UDim.new(0, 8)
        local s = Instance.new("UIStroke", mFrame); s.Color = C.accent; s.Thickness = 2

        local tbar = Instance.new("Frame")
        tbar.Size = UDim2.new(1, 0, 0, 36) tbar.BackgroundColor3 = C.card
        tbar.BorderSizePixel = 0 tbar.ZIndex = 202 tbar.Parent = mFrame
        Instance.new("UICorner", tbar).CornerRadius = UDim.new(0, 8)

        local tlbl = Instance.new("TextLabel")
        tlbl.Size = UDim2.new(1, -120, 1, 0) tlbl.Position = UDim2.new(0, 12, 0, 0)
        tlbl.BackgroundTransparency = 1 tlbl.Text = "Pet Type (multi)"
        tlbl.TextColor3 = C.accent tlbl.Font = FB tlbl.TextSize = 14
        tlbl.TextXAlignment = Enum.TextXAlignment.Left tlbl.ZIndex = 202 tlbl.Parent = tbar

        local doneBtn = Instance.new("TextButton")
        doneBtn.Size = UDim2.new(0, 60, 0, 24) doneBtn.Position = UDim2.new(1, -110, 0.5, -12)
        doneBtn.BackgroundColor3 = C.success doneBtn.Text = "DONE"
        doneBtn.TextColor3 = Color3.new(0, 0, 0) doneBtn.Font = FB doneBtn.TextSize = 11
        doneBtn.BorderSizePixel = 0 doneBtn.AutoButtonColor = false
        doneBtn.ZIndex = 203 doneBtn.Parent = tbar
        Instance.new("UICorner", doneBtn).CornerRadius = UDim.new(0, 4)

        local clrBtn = Instance.new("TextButton")
        clrBtn.Size = UDim2.new(0, 40, 0, 24) clrBtn.Position = UDim2.new(1, -46, 0.5, -12)
        clrBtn.BackgroundColor3 = C.danger clrBtn.Text = "CLR"
        clrBtn.TextColor3 = Color3.new(1, 1, 1) clrBtn.Font = FB clrBtn.TextSize = 11
        clrBtn.BorderSizePixel = 0 clrBtn.AutoButtonColor = false
        clrBtn.ZIndex = 203 clrBtn.Parent = tbar
        Instance.new("UICorner", clrBtn).CornerRadius = UDim.new(0, 4)

        local searchBox = Instance.new("TextBox")
        searchBox.Size = UDim2.new(1, -24, 0, 28) searchBox.Position = UDim2.new(0, 12, 0, 46)
        searchBox.BackgroundColor3 = C.card searchBox.Text = ""
        searchBox.PlaceholderText = "Cari pet type..." searchBox.TextColor3 = C.text
        searchBox.Font = FM searchBox.TextSize = 12 searchBox.BorderSizePixel = 0
        searchBox.ClearTextOnFocus = false searchBox.ZIndex = 202 searchBox.Parent = mFrame
        Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 4)

        local pScroll = Instance.new("ScrollingFrame")
        pScroll.Size = UDim2.new(1, -24, 1, -90) pScroll.Position = UDim2.new(0, 12, 0, 82)
        pScroll.BackgroundColor3 = C.card pScroll.BorderSizePixel = 0
        pScroll.ScrollBarThickness = 4 pScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        pScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        pScroll.ZIndex = 202 pScroll.Parent = mFrame
        Instance.new("UICorner", pScroll).CornerRadius = UDim.new(0, 4)
        local lay = Instance.new("UIListLayout"); lay.Padding = UDim.new(0, 3); lay.Parent = pScroll
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 4) pad.PaddingBottom = UDim.new(0, 4)
        pad.PaddingLeft = UDim.new(0, 4) pad.PaddingRight = UDim.new(0, 4)
        pad.Parent = pScroll

        local function renderList(filter)
            for _, c in ipairs(pScroll:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end
            filter = (filter or ""):lower()
            -- Collect from backpack
            local types = {}
            local bp = player:FindFirstChild("Backpack")
            if bp then
                for _, t in ipairs(bp:GetChildren()) do
                    if isPet(t) then
                        local pt = getPetType(t)
                        local base = (BH.getBaseName and pt ~= "") and BH.getBaseName(pt) or pt
                        types[base] = (types[base] or 0) + 1
                    end
                end
            end
            -- Add already-selected types
            for n in pairs(giftSelectedPets) do
                if not types[n] then types[n] = 0 end
            end
            -- Sort: selected first, then count
            local sorted = {}
            for name, count in pairs(types) do
                table.insert(sorted, {name=name, count=count, picked=giftSelectedPets[name] == true})
            end
            table.sort(sorted, function(a, b)
                if a.picked ~= b.picked then return a.picked end
                if a.count ~= b.count then return a.count > b.count end
                return a.name < b.name
            end)
            for _, it in ipairs(sorted) do
                if filter == "" or it.name:lower():find(filter, 1, true) then
                    local row = Instance.new("TextButton")
                    row.Size = UDim2.new(1, -4, 0, 28)
                    if it.picked then
                        row.BackgroundColor3 = C.success
                        row.TextColor3 = Color3.new(0, 0, 0)
                    else
                        row.BackgroundColor3 = C.bg
                        row.TextColor3 = C.text
                    end
                    row.Text = (it.picked and "v " or "  ")..it.name.."  ×"..it.count
                    row.Font = FM row.TextSize = 12 row.TextXAlignment = Enum.TextXAlignment.Left
                    row.BorderSizePixel = 0 row.AutoButtonColor = false
                    row.ZIndex = 203 row.Parent = pScroll
                    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
                    Instance.new("UIPadding", row).PaddingLeft = UDim.new(0, 10)
                    row.MouseButton1Click:Connect(function()
                        if giftSelectedPets[it.name] then
                            giftSelectedPets[it.name] = nil
                        else
                            giftSelectedPets[it.name] = true
                        end
                        persistGiftState()
                        updateGiftDisplay()
                        renderList(searchBox.Text)
                    end)
                end
            end
        end
        renderList("")
        searchBox:GetPropertyChangedSignal("Text"):Connect(function() renderList(searchBox.Text) end)

        doneBtn.MouseButton1Click:Connect(function() overlay:Destroy() end)
        clrBtn.MouseButton1Click:Connect(function()
            giftSelectedPets = {}
            persistGiftState()
            updateGiftDisplay()
            renderList(searchBox.Text)
        end)
    end
    gPetBtn.MouseButton1Click:Connect(openPetPicker)

    -- ===== GIFT LOOP =====
    local function startOutGift()
        if giftActive then return end
        local nt = 0; for _ in pairs(giftSelectedTargets) do nt = nt + 1 end
        if nt == 0 then
            giftStatusLbl.Text = "❌ Belum pilih target"
            giftStatusLbl.TextColor3 = C.danger
            return
        end
        if not outGiftRE and not outPGS then
            giftStatusLbl.Text = "❌ Gift remote/module gak ada"
            giftStatusLbl.TextColor3 = C.danger
            return
        end
        giftActive = true
        giftStopReq = false
        giftSent, giftFailed = 0, 0
        giftCounterLbl.Text = "Sent: 0   Failed: 0"
        giftToggle.Text = "🎁 GIFT: ON"
        giftToggle.BackgroundColor3 = C.success
        giftStatusLbl.Text = "Status: starting..."
        giftStatusLbl.TextColor3 = C.accent
        persistGiftState()

        task.spawn(function()
            math.randomseed(tick())
            while not giftStopReq do
                -- Refresh pool
                local pool = {}
                local seenP = {}
                for n in pairs(giftSelectedTargets) do
                    local p = findGiftPlayer(n)
                    if p and not seenP[p] then table.insert(pool, p); seenP[p] = true end
                end
                if #pool == 0 then
                    giftStatusLbl.Text = "Waiting: target offline semua..."
                    giftStatusLbl.TextColor3 = C.danger
                    task.wait(5)
                else
                    local bp = player:FindFirstChild("Backpack")
                    if not bp then task.wait(2)
                    else
                        local matching = {}
                        for _, t in ipairs(bp:GetChildren()) do
                            if petMatchesGiftFilter(t) then table.insert(matching, t) end
                        end
                        if #matching == 0 then
                            giftStatusLbl.Text = "Waiting: no pet match filter..."
                            giftStatusLbl.TextColor3 = C.accent
                            task.wait(5)
                        else
                            local petTool = matching[math.random(1, #matching)]
                            local target = pool[math.random(1, #pool)]
                            giftStatusLbl.Text = "→ "..target.Name:sub(1,14).." : "..petTool.Name:sub(1,18)
                            giftStatusLbl.TextColor3 = C.accent
                            local ok = giftPetToTarget(target, petTool)
                            if ok then giftSent = giftSent + 1 else giftFailed = giftFailed + 1 end
                            giftCounterLbl.Text = "Sent: "..giftSent.."   Failed: "..giftFailed
                            task.wait(0.15)  -- v8.272: dipercepat (dulu 1.5 -> lambat banget)
                        end
                    end
                end
            end
            giftActive = false
            giftToggle.Text = "🎁 GIFT: OFF"
            giftToggle.BackgroundColor3 = C.danger
            giftStatusLbl.Text = "Stopped (Sent: "..giftSent..")"
            giftStatusLbl.TextColor3 = C.textDim
            persistGiftState()
        end)
    end

    local function stopOutGift()
        if not giftActive then return end
        giftStopReq = true
        giftStatusLbl.Text = "Stopping..."
        giftStatusLbl.TextColor3 = C.accent
    end

    giftToggle.MouseButton1Click:Connect(function()
        if giftActive then stopOutGift() else startOutGift() end
    end)

    -- Resume on load
    if BH.marketState and BH.marketState.gardenGift and BH.marketState.gardenGift.active then
        task.spawn(function()
            task.wait(3)
            startOutGift()
        end)
    end

    updateGiftDisplay()

    BH.refreshGardenStats = function()
        for _, c in ipairs(gListScroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local bp = player:FindFirstChild("Backpack")
        if not bp then gStatsLbl.Text = "no backpack"; return end
        local total, favC = 0, 0
        local tc = {}
        for _, t in ipairs(bp:GetChildren()) do
            if isPet(t) then
                total = total + 1
                if isFav(t) then favC = favC + 1 end
                local pt = getPetType(t)
                local kg = getCurrentKg(t)
                -- v8.148: get age-1 normalized base weight buat filter
                local baseKg = getBaseKg(t)
                -- Apply filter
                local include = true
                if gardenFilter == "60plus" and baseKg < 6 then include = false end
                if gardenFilter == "60minus" and baseKg >= 6 then include = false end
                if include then
                    if not tc[pt] then tc[pt] = {n=0, mn=math.huge, mx=0, baseSum=0} end
                    tc[pt].n = tc[pt].n + 1
                    tc[pt].baseSum = tc[pt].baseSum + baseKg
                    if kg > 0 then
                        tc[pt].mn = math.min(tc[pt].mn, kg)
                        tc[pt].mx = math.max(tc[pt].mx, kg)
                    end
                end
            end
        end
        local nTypes = 0 for _ in pairs(tc) do nTypes = nTypes + 1 end
        local filterLabel = gardenFilter == "all" and "" or (" ["..gardenFilter.."]")
        -- v8.253: tampilkan batas inventory (cur/max), kayak "185/210 pets"
        local maxP = getMaxPetsPulse()
        local petsStr = maxP and (total.."/"..maxP) or tostring(total)
        gStatsLbl.Text = string.format("%s pets  |  %d fav  |  %d types%s", petsStr, favC, nTypes, filterLabel)
        local sorted = {}
        for pt, info in pairs(tc) do table.insert(sorted, {pt=pt, info=info}) end
        table.sort(sorted, function(a, b) return a.info.n > b.info.n end)
        for i, e in ipairs(sorted) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -8, 0, 32)  -- v8.149: 26 → 32 lebih tinggi lagi
            row.BackgroundColor3 = (i % 2 == 0) and C.bg or C.card
            row.BorderSizePixel = 0 row.Parent = gListScroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
            local nm = Instance.new("TextLabel")
            nm.Size = UDim2.new(0.55, -4, 1, 0) nm.Position = UDim2.new(0, 10, 0, 0)
            nm.BackgroundTransparency = 1 nm.Text = e.pt
            nm.TextColor3 = C.text nm.Font = FM nm.TextSize = 15  -- v8.149: 13 → 15
            nm.TextXAlignment = Enum.TextXAlignment.Left
            nm.TextTruncate = Enum.TextTruncate.AtEnd nm.Parent = row
            local cn = Instance.new("TextLabel")
            cn.Size = UDim2.new(0.20, 0, 1, 0) cn.Position = UDim2.new(0.55, 0, 0, 0)
            cn.BackgroundTransparency = 1 cn.Text = "×"..e.info.n
            cn.TextColor3 = C.accent cn.Font = FB cn.TextSize = 15  -- v8.149: 13 → 15
            cn.TextXAlignment = Enum.TextXAlignment.Center cn.Parent = row
            local kg = Instance.new("TextLabel")
            kg.Size = UDim2.new(0.25, 0, 1, 0) kg.Position = UDim2.new(0.75, 0, 0, 0)
            kg.BackgroundTransparency = 1
            kg.Text = (e.info.mx > 0) and string.format("%.1f-%.1f", e.info.mn, e.info.mx) or "-"
            kg.TextColor3 = C.textDim kg.Font = FM kg.TextSize = 13  -- v8.149: 12 → 13
            kg.TextXAlignment = Enum.TextXAlignment.Right kg.Parent = row
        end
    end

    -- v8.152: removed gGiftBtn/gTradeBtn refs (auto-accept moved to garden sc)

    -- v8.148: wire tab clicks | v8.151: gift tab
    local function showListTab()
        gListScroll.Visible = true
        giftCard.Visible = false
    end
    local function showGiftTab()
        gListScroll.Visible = false
        giftCard.Visible = true
        pcall(updateGiftDisplay)
    end
    tabAll.MouseButton1Click:Connect(function() gardenFilter = "all"; setTabActive("all"); showListTab(); pcall(BH.refreshGardenStats) end)
    tab60p.MouseButton1Click:Connect(function() gardenFilter = "60plus"; setTabActive("60plus"); showListTab(); pcall(BH.refreshGardenStats) end)
    tab60m.MouseButton1Click:Connect(function() gardenFilter = "60minus"; setTabActive("60minus"); showListTab(); pcall(BH.refreshGardenStats) end)
    tabGift.MouseButton1Click:Connect(function() setTabActive("gift"); showGiftTab() end)

    do
        local bp = player:FindFirstChild("Backpack")
        if bp then
            bp.ChildAdded:Connect(function() task.wait(0.1); pcall(BH.refreshGardenStats) end)
            bp.ChildRemoved:Connect(function() task.wait(0.1); pcall(BH.refreshGardenStats) end)
        end
    end

    task.spawn(function()
        task.wait(2)
        pcall(BH.refreshGardenStats)
    end)
end

-- v8.273: ===== SHOP — AUTO BUY SEED & GEAR =====
-- v8.280: dibungkus task.spawn(function) (bukan 'do') — 'do...end' TIDAK bikin
-- scope fungsi, jadi local-nya tetap kehitung di chunk utama -> nembus limit 200.
-- pakai fungsi = local pindah ke scope fungsi -> chunk utama lega.
task.spawn(function()
    local shopPanel = panels["SHOP"]  -- v8.274: ambil dari panels (bukan local di main chunk)
    local RS = game:GetService("ReplicatedStorage")
    -- resolve remote buy
    local function getGE() return RS:FindFirstChild("GameEvents") end
    local buySeedRE = getGE() and getGE():FindFirstChild("BuySeedStock")
    local buyGearRE = getGE() and getGE():FindFirstChild("BuyGearStock")
    if not buySeedRE then buySeedRE = RS:FindFirstChild("BuySeedStock", true) end
    if not buyGearRE then buyGearRE = RS:FindFirstChild("BuyGearStock", true) end

    -- baca daftar nama seed/gear dari RS.Data (atau modul). return array nama.
    local function readDataList(modName)
        local out = {}
        pcall(function()
            local data = RS:FindFirstChild("Data")
            local mod = data and data:FindFirstChild(modName)
            if mod then
                local t = require(mod)
                if type(t) == "table" then
                    for k, v in pairs(t) do
                        if type(k) == "string" then table.insert(out, k) end
                    end
                end
            end
        end)
        table.sort(out)
        return out
    end

    BH.autoShop = BH.autoShop or {
        active = false,
        seeds = {},   -- {[name]=true} dipilih
        gears = {},   -- {[name]=true} dipilih
    }
    -- restore dari state
    if BH.marketState then
        BH.autoShop.seeds = BH.marketState.autoShopSeeds or {}
        BH.autoShop.gears = BH.marketState.autoShopGears or {}
    end
    local function saveShop()
        if BH.marketState then
            BH.marketState.autoShopSeeds = BH.autoShop.seeds
            BH.marketState.autoShopGears = BH.autoShop.gears
            BH.saveMarketState(BH.marketState)
        end
    end

    -- ===== UI =====
    lblOf(shopPanel, "🛒 AUTO BUY SEED & GEAR", 0, 6, 320, 20, C.accent, 14, FB)
    lblOf(shopPanel, "Pilih item, ON, beli terus selama stock ada", 0, 28, 360, 16, C.textDim, 11)

    -- counter status
    local statusLbl = lblOf(shopPanel, "Idle", 0, 48, 360, 16, C.textDim, 11)

    -- tombol pilih seed
    local seedBtn = btnOf(shopPanel, 0, 72, 175, 32, "🌱 Pilih Seed", C.card, C.text)
    local gearBtn = btnOf(shopPanel, 185, 72, 175, 32, "⚙️ Pilih Gear", C.card, C.text)
    local seedSelLbl = lblOf(shopPanel, "Seed: -", 0, 110, 360, 16, C.textDim, 10)
    local gearSelLbl = lblOf(shopPanel, "Gear: -", 0, 128, 360, 16, C.textDim, 10)

    local function updateSelLbls()
        local s = {}; for n in pairs(BH.autoShop.seeds) do table.insert(s, n) end
        local g = {}; for n in pairs(BH.autoShop.gears) do table.insert(g, n) end
        seedSelLbl.Text = "Seed: " .. (#s > 0 and table.concat(s, ", ") or "-")
        gearSelLbl.Text = "Gear: " .. (#g > 0 and table.concat(g, ", ") or "-")
    end
    updateSelLbls()

    -- popup multi-select (dipakai buat seed & gear)
    local function openPicker(title, listFn, selTable)
        local old = gui:FindFirstChild("ShopPicker")
        if old then old:Destroy() end
        local pk = Instance.new("Frame")
        pk.Name = "ShopPicker"
        pk.Size = UDim2.new(0, 280, 0, 360)
        pk.Position = UDim2.new(0.5, -140, 0.5, -180)
        pk.BackgroundColor3 = C.panel; pk.ZIndex = 9000; pk.Parent = gui
        Instance.new("UICorner", pk).CornerRadius = UDim.new(0, 10)
        local st = Instance.new("UIStroke", pk); st.Color = C.border
        local ti = Instance.new("TextLabel")
        ti.Size = UDim2.new(1, -50, 0, 30); ti.Position = UDim2.new(0, 10, 0, 6)
        ti.BackgroundTransparency = 1; ti.Text = title; ti.TextColor3 = C.accent
        ti.Font = FB; ti.TextSize = 14; ti.TextXAlignment = Enum.TextXAlignment.Left
        ti.ZIndex = 9001; ti.Parent = pk
        local xb = Instance.new("TextButton")
        xb.Size = UDim2.new(0, 28, 0, 28); xb.Position = UDim2.new(1, -34, 0, 6)
        xb.BackgroundColor3 = C.danger; xb.Text = "X"; xb.TextColor3 = Color3.fromRGB(255,255,255)
        xb.Font = FB; xb.TextSize = 14; xb.ZIndex = 9001; xb.Parent = pk
        Instance.new("UICorner", xb).CornerRadius = UDim.new(0, 6)
        xb.MouseButton1Click:Connect(function() pk:Destroy() end)
        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, -16, 1, -46); scroll.Position = UDim2.new(0, 8, 0, 40)
        scroll.BackgroundTransparency = 1; scroll.ScrollBarThickness = 5
        scroll.CanvasSize = UDim2.new(0,0,0,0); scroll.ZIndex = 9001; scroll.Parent = pk
        local lay = Instance.new("UIListLayout"); lay.Padding = UDim.new(0, 3); lay.Parent = scroll
        local names = listFn()
        if #names == 0 then
            local e = Instance.new("TextLabel")
            e.Size = UDim2.new(1, 0, 0, 40); e.BackgroundTransparency = 1
            e.Text = "(gak ketemu data — coba di server market)"; e.TextColor3 = C.textDim
            e.Font = FM; e.TextSize = 11; e.ZIndex = 9002; e.Parent = scroll
        end
        for _, name in ipairs(names) do
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, 0, 0, 28); b.BackgroundColor3 = C.card
            b.Font = FM; b.TextSize = 12; b.TextXAlignment = Enum.TextXAlignment.Left
            b.ZIndex = 9002; b.Parent = scroll
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
            local function refresh()
                b.Text = (selTable[name] and "  ✓ " or "    ") .. name
                b.TextColor3 = selTable[name] and C.accent or C.text
            end
            refresh()
            b.Activated:Connect(function()
                selTable[name] = (not selTable[name]) or nil
                refresh(); updateSelLbls(); saveShop()
            end)
        end
        scroll.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 6)
    end
    seedBtn.MouseButton1Click:Connect(function()
        openPicker("🌱 Pilih Seed", function() return readDataList("SeedData") end, BH.autoShop.seeds)
    end)
    gearBtn.MouseButton1Click:Connect(function()
        openPicker("⚙️ Pilih Gear", function() return readDataList("GearData") end, BH.autoShop.gears)
    end)

    -- toggle ON/OFF
    local toggleBtn = btnOf(shopPanel, 0, 154, 360, 38, "▶ START AUTO BUY", C.success, Color3.fromRGB(17,17,17))
    local function setToggleVisual()
        toggleBtn.Text = BH.autoShop.active and "⛔ STOP AUTO BUY" or "▶ START AUTO BUY"
        toggleBtn.BackgroundColor3 = BH.autoShop.active and C.danger or C.success
    end
    toggleBtn.MouseButton1Click:Connect(function()
        BH.autoShop.active = not BH.autoShop.active
        setToggleVisual()
        statusLbl.Text = BH.autoShop.active and "Aktif — beli selama stock ada" or "Idle"
        statusLbl.TextColor3 = BH.autoShop.active and C.accent or C.textDim
    end)
    setToggleVisual()

    -- ===== LOOP BELI =====
    local bought = 0
    task.spawn(function()
        while gui.Parent do
            task.wait(1)
            if BH.autoShop.active then
                local did = 0
                -- beli seed yg dipilih
                for name in pairs(BH.autoShop.seeds) do
                    if buySeedRE then
                        pcall(function() buySeedRE:FireServer(name) end)
                        did = did + 1
                    end
                end
                -- beli gear yg dipilih
                for name in pairs(BH.autoShop.gears) do
                    if buyGearRE then
                        pcall(function() buyGearRE:FireServer(name) end)
                        did = did + 1
                    end
                end
                if did > 0 then
                    bought = bought + did
                    statusLbl.Text = "Beli... total fire: "..bought
                    statusLbl.TextColor3 = C.accent
                end
            end
        end
    end)
end)

-- v8.49: build garden panel after all helpers defined
pcall(BH.buildGardenPanel)

-- v8.137: wrap di pcall — populateModalList scoped di do-block, refreshPriceList/refreshBackpackStats juga bisa nil. Crash di sini = kill watchdog
pcall(function() if populateModalList then populateModalList() end end)
pcall(function() if refreshPriceList then refreshPriceList() end end)
pcall(function() if refreshBackpackStats then refreshBackpackStats() end end)
task.spawn(function()
    task.wait(1)
    pcall(tryClaim)
end)

-- v8.178: watchdog dipindah ke line ~6286 (right after onStartClick wired) biar gak ke-kill kalo crash di UI build

-- ===== v8.276: AUTO BUY TRADING TICKET (Sheckles, KHUSUS server garden) =====
-- Ditaruh di AKHIR script (setelah UI kebangun) + self-contained (gak pakai
-- local luar) biar gak ganggu inisialisasi UI. Jalan otomatis tanpa GUI/toggle.
-- fire BuyGearStock(namaTiket) tiap 5s. game auto-tolak kalau stock habis /
-- Sheckles kurang -> aman. pas habis "nunggu" sendiri sampai restock.
task.spawn(function()
    local rs = game:GetService("ReplicatedStorage")
    local ws = game:GetService("Workspace")
    -- garden server = gak ada TradeWorld
    if ws:FindFirstChild("TradeWorld") ~= nil then return end
    -- auto-detect nama tiket dari GearData (fallback "Trading Ticket")
    local ticketName = "Trading Ticket"
    pcall(function()
        local dataF = rs:FindFirstChild("Data")
        local mod = dataF and dataF:FindFirstChild("GearData")
        if mod then
            local ok, tbl = pcall(require, mod)
            if ok and type(tbl) == "table" then
                for k, v in pairs(tbl) do
                    local nm
                    if type(k) == "string" then nm = k
                    elseif type(v) == "table" then nm = v.Name or v.ItemName or v.DisplayName end
                    if type(nm) == "string" then
                        local low = nm:lower()
                        if low:find("trading", 1, true) and low:find("ticket", 1, true) then
                            ticketName = nm; break
                        end
                    end
                end
            end
        end
    end)
    print("[AutoTicket] server garden — auto-buy '"..ticketName.."' aktif (Sheckles)")
    local ge = rs:FindFirstChild("GameEvents")
    local re = ge and ge:FindFirstChild("BuyGearStock")
    if not re then
        print("[AutoTicket] BuyGearStock remote gak ketemu — auto-buy batal")
        return
    end
    while true do
        task.wait(5)
        pcall(function() re:FireServer(ticketName) end)
    end
end)
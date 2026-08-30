-- Chờ client tải hoàn tất trước khi khởi tạo singleton, UI và các vòng chạy.
repeat task.wait() until game:IsLoaded() and game:GetService("Players").LocalPlayer

-- Chỉ cho phép một phiên Kaitun V4 chạy trong cùng client.
-- Chạy lại sẽ giữ nguyên tiến trình cũ và chỉ bật lại UI nếu nó đang bị đóng.
if getgenv().__KaitunV4Singleton then
    if typeof(getgenv().__KaitunV4Singleton.ui) == "Instance"
        and getgenv().__KaitunV4Singleton.ui.Parent then
        getgenv().__KaitunV4Singleton.ui.Enabled = true
    end
    warn("Kaitun V4 đang chạy - bỏ qua lần thực thi trùng.")
    return
end
getgenv().__KaitunV4Singleton = {state = "loading"}

-- ═════════════════════════════════════════════════════
-- CONFIG — chỉnh tại đây khi dùng full source
-- Khi dùng loadstring: set getgenv().Config TRƯỚC loadstring(), giá trị ở đây sẽ là fallback
-- ═════════════════════════════════════════════════════
local _SRC = {
    ["Mode"]                           = 1,   -- 1: hop FM + group trial | 2: treo sv đợi FM, không group
    ["Team"]                           = "Marines",
    ["Farm Fragments"]                 = { autoraid = false, autotyrant = false },
    ["Gear"]                           = "A-B-B",
    ["ChangeBestGear"]                 = true,
    ["V3 Door Distance"]               = 50,
    ["FM_API"]                         = "", -- trống = dùng Full Moon feed của coordinator
    ["API Base URL"]                   = "http://gamma.pikamc.vn:25632",
    ["V3 Countdown"]                   = 6,
    ["V3 File Poll"]                   = 0.10,
    ["V3 Ready Freshness"]             = 2.0,
    ["V3 Require Different Races"]     = true,
    ["V3 Fire Count"]                  = 1,
    ["V3 Fire Interval"]               = 0.05,
    ["Pair Temple Timeout"]            = 35,
    ["Pair Sticky Until Trial Complete"] = true,
    ["Pair Release After Trial"]       = true,
    ["Pair Requeue Delay"]             = 15,
    ["Pair Force Temple Interval"]     = 0.8,
    ["LimitMainUpPerGroup"]            = 4,   -- tối đa main/group (max 10)
    ["Training Islands"]               = { "Haunted Castle", "Cake Land", "Peanut + Ice Cream", "Tiki Outpost", "Great Tree", "Port Town" },
    -- Movement lấy từ auto_factory.lua: Heartbeat step + float force + noclip.
    ["Fly Speed"]                      = 280,
    ["Fly Force"]                      = 100000,
    ["Fly Snap Distance"]              = 8,
    ["Use Trial Exit Entrance"]        = true, -- dùng TeleportBack hợp lệ từ Trial/Temple -> Great Tree
    -- Bring/attack lấy từ auto_boss_source_style.lua (không dùng phần Core).
    ["Attack Range"]                   = 30,
    ["Attack Delay"]                   = 0,
    ["Bring Mobs"]                     = true,
    ["Bring Mob Count"]                = 2,
    ["Bring Mob Radius"]               = 200,
    ["Cyborg V4 Bring Mob Radius"]     = 500,
    ["Bring Activation Range"]         = 50,
    ["Bring Player Safe Range"]        = 300,
    ["Bring Mob Interval"]             = 0.10,
    ["Bring Mob Spread"]               = 2,
    ["Simulation Radius"]              = 5000,
}
do
    local _ext = getgenv().Config
    if _ext then
        -- loadstring mode: giá trị từ getgenv() ưu tiên, _SRC chỉ điền field còn thiếu
        for k, v in pairs(_SRC) do
            if _ext[k] == nil then _ext[k] = v end
        end
        getgenv().Config = _ext
    else
        -- full source mode: dùng _SRC trực tiếp
        getgenv().Config = _SRC
    end
end

-- Mode1 — cấu hình nhóm cho Mode 1 (hop FM + trial chung)
-- Khi dùng loadstring: set getgenv().Mode1 TRƯỚC loadstring() để override
-- mỗi block = 1 nhóm | thêm/bớt block = thêm/bớt nhóm
-- Không tự tạo group mẫu. Nếu loader không set Mode1 thì danh sách
-- rỗng và client không đăng ký group nào lên API.
getgenv().Mode1 = getgenv().Mode1 or {}

-- Mode2 — cấu hình cho Mode 2 (treo sv chờ FM, không hop group)
-- Khi dùng loadstring: set getgenv().Mode2 TRƯỚC loadstring() để override
getgenv().Mode2 = getgenv().Mode2 or {
    ["ListHelperMode2"] = {},  -- danh sách username helper (Mode 2 dùng list này)
}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")
local CollectionService = game:GetService("CollectionService")

-- Chọn team phải chạy trước mọi WaitForChild của Map/Temple/combat.
-- Khi còn ở màn hình PICK A SIDE, các thành phần đó có thể chưa được
-- tạo, khiến script kẹt và không bao giờ chạy tới SetTeam.
local Player = Players.LocalPlayer
local LocalPlayer = Player
local PlayerGui = Player:WaitForChild("PlayerGui")
local CommF_ = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")

local cfg = getgenv().Config or {}
local team = cfg["Team"] or getgenv().Team or "Marines"
team = tostring(team)
if team == "Pirate" then team = "Pirates" end
if team ~= "Marines" and team ~= "Pirates" then team = "Marines" end

-- Chỉ bắt đầu tính 1 giây sau khi bảng PICK A SIDE thực sự hiện.
-- Nếu bắt đầu đếm ngay từ game:IsLoaded(), bảng có thể xuất hiện muộn
-- và người dùng sẽ thấy script chọn team gần như ngay lập tức.
if not Player.Team then
    while not Player.Team do
        local chooseTeam = PlayerGui:FindFirstChild("ChooseTeam", true)
        local visible = false
        if chooseTeam then
            local ok, value = pcall(function() return chooseTeam.Visible end)
            visible = not ok or value == true
        end
        if visible then break end
        task.wait(0.1)
    end
    if not Player.Team then task.wait(1) end
end

repeat
    pcall(function() CommF_:InvokeServer("SetTeam", team) end)
    task.wait(0.5)
until Player.Team and Player.Team.Name == team
task.wait(2)

-- Rerun-safe: phiên trước có thể đã chuyển Temple khỏi MapStash sang workspace.Map.
-- Không WaitForChild vô hạn ở MapStash vì child sẽ không quay lại cho tới khi rejoin.
local worldMap = workspace:WaitForChild("Map")
if not worldMap:FindFirstChild("Temple of Time") then
    local mapStash = ReplicatedStorage:WaitForChild("MapStash")
    local temple = mapStash:FindFirstChild("Temple of Time")
    if not temple then
        temple = mapStash:WaitForChild("Temple of Time", 5)
    end
    if temple then temple.Parent = worldMap end
end

-- Rerun-safe: getgenv().Config có thể còn giữ list cũ từ lần chạy trước.
-- Chỉ migrate list còn hai tên đảo rời; config mới/tùy chỉnh vẫn được giữ.
do
    local configuredIslands = getgenv().Config and getgenv().Config["Training Islands"]
    if type(configuredIslands) == "table" then
        local usesLegacyIslands = false
        for _, islandName in ipairs(configuredIslands) do
            if islandName == "Ice Cream Island" or islandName == "Peanut Island" then
                usesLegacyIslands = true
                break
            end
        end
        if usesLegacyIslands then
            getgenv().Config["Training Islands"] = {
                "Haunted Castle", "Cake Land", "Peanut + Ice Cream",
                "Tiki Outpost", "Great Tree", "Port Town"
            }
        end
    end
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Net = Modules:WaitForChild("Net")
local RegisterAttack = Net:WaitForChild("RE/RegisterAttack")
local RegisterHit = Net:WaitForChild("RE/RegisterHit")

if workspace:GetAttribute("MAP") and workspace:GetAttribute("MAP") ~= "Sea3" then
    ReplicatedStorage.Remotes.CommF_:InvokeServer("TravelZou")
end

if not isfile("cache_iron.json") then writefile("cache_iron.json", "{}") end
local ok, cache = pcall(function() return HttpService:JSONDecode(readfile("cache_iron.json")) end)
if not ok then cache = {} end
cache[game.JobId] = math.floor(tick())
writefile("cache_iron.json", HttpService:JSONEncode(cache))

getgenv().TyrantConfig = getgenv().TyrantConfig or {
    Team = "Marines",
    Weapon = "Dragon Talon",
    AutoBuyDragonTalon = true,
    AutoBuso = true,
    TweenSpeed = 330,
    FarmHeight = 18,
    BossHeight = 25,
    AttackDistance = 105,
    AttackDelay = 0.03,
    BringMobs = true
}

if not getgenv().Config then
    getgenv().Config = {
        ["Team"] = "Marines",
        ["ChangeBestGear"] = true,
        ["Gear"] = "A-B-B",
        ["Farm Fragments"] = { autoraid = false, autotyrant = true },
        ["V3 Door Distance"] = 50,
        ["Training Islands"] = { "Haunted Castle", "Cake Land", "Peanut + Ice Cream", "Tiki Outpost", "Great Tree", "Port Town" }
    }
end

local bestGearForRace = {
    Ghoul = "B-B-A", Cyborg = "A-B-B", Mink = "B-B-A",
    Skypiea = "B-B-A", Human = "B-A-A", Fishman = "B-A-A"
}

if not getgenv().Config["Gear"] or #getgenv().Config["Gear"] ~= 5 then
    getgenv().Config["Gear"] = getgenv().Config["Gear"] or "A-B-B"
end

-- Whitelist main/help: rawMainList = nhiều acc main, ưu tiên acc đầu tiên có mặt.
local isUper = false
local isAlly = false
local mainAccountName = ""
local isMain = false
local isallies = {}

local MainPriorityList = {}
local HelpWhitelist = {}
local HopFMWhitelist = {}  -- rỗng = tất cả đều được hop FM

do
    local _modeInit = tonumber((getgenv().Config or {})["Mode"] or 1)
    if _modeInit == 2 then
        -- Mode 2: helper list từ Mode2["ListHelperMode2"]
        local m2 = getgenv().Mode2 or {}
        for _, h in ipairs(m2["ListHelperMode2"] or {}) do
            h = tostring(h):gsub("^%s+", ""):gsub("%s+$", "")
            if h ~= "" then HelpWhitelist[h] = true end
        end
        -- Mode 2 không dùng HopFM whitelist (không tự hop tìm FM)
    else
        -- Mode 1: đọc từ Mode1 groups
        local ghGroups = getgenv().Mode1 or {}
        for _, grp in ipairs(ghGroups) do
            if type(grp) == "table" then
                for _, h in ipairs(grp.helpers or {}) do
                    h = tostring(h):gsub("^%s+", ""):gsub("%s+$", "")
                    if h ~= "" then HelpWhitelist[h] = true end
                end
                for _, name in ipairs(grp.hopfm or {}) do
                    name = tostring(name):gsub("^%s+", ""):gsub("%s+$", "")
                    if name ~= "" then HopFMWhitelist[name] = true end
                end
            end
        end
    end
end

getgenv().UpdateRoles = function()
    -- Nếu tên nằm trong HelpWhitelist → role = helper. Ngược lại → mainup.
    if HelpWhitelist[Player.Name] == true then
        -- Acc là helper - tìm main đang có mặt trong server
        local foundMain = ""
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= Player and not HelpWhitelist[p.Name] then
                foundMain = p.Name
                break
            end
        end
        isUper = false
        isAlly = true
        mainAccountName = foundMain
    else
        -- Acc không có trong helper list → 100% được coi là mainup
        isUper = true
        isAlly = false
        mainAccountName = Player.Name
    end

    isMain = isUper

    -- Cập nhật danh sách đồng minh
    isallies = {}
    if isUper then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Name ~= Player.Name and HelpWhitelist[p.Name] then
                isallies[p.Name] = true
            end
        end
    elseif isAlly then
        if mainAccountName ~= "" then isallies[mainAccountName] = true end
    end
end

-- Chạy lần đầu tiên
getgenv().UpdateRoles()

getgenv().Config["Team"] = getgenv().Config["Team"]
    and (getgenv().Config["Team"] == "Marines" or getgenv().Config["Team"] == "Pirates")
    and getgenv().Config["Team"] or "Marines"

local module = {}
repeat task.wait() until game:IsLoaded() and Player

local toidangkiemtraloadingscreen = tick()
repeat
    task.wait()
    if tick() - toidangkiemtraloadingscreen > 5 then
        ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", game.JobId)
    end
until not Player.PlayerGui:FindFirstChild("LoadingScreen")

local player = Player
local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")

function module:eq()
    for _, L in pairs(player.Backpack:GetChildren()) do
        if L:IsA("Tool") and L["ToolTip"] == "Melee" and not _G.USESWORD then
            local a = pcall(function() player.Character.Humanoid:EquipTool(L) end)
            if a then break end
        elseif L:IsA("Tool") and L["ToolTip"] == "Sword" and _G.USESWORD then
            local a = pcall(function() player.Character.Humanoid:EquipTool(L) end)
            if a then break end
        end
    end
end

-- Pha FFA sau Trial luôn cần fighting style, không phụ thuộc _G.USESWORD.
function module:eqMelee()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid then return false end

    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") then
            local toolTip = tostring(tool.ToolTip or "")
            if toolTip == "Melee" or toolTip == "Fighting Style" then return true end
        end
    end
    for _, tool in ipairs(player.Backpack:GetChildren()) do
        if tool:IsA("Tool") then
            local toolTip = tostring(tool.ToolTip or "")
            if toolTip == "Melee" or toolTip == "Fighting Style" then
                local ok = pcall(function() humanoid:EquipTool(tool) end)
                return ok and tool.Parent == character
            end
        end
    end
    return false
end

function module:haki()
    if not player.Character:FindFirstChild("HasBuso") then
        ReplicatedStorage.Remotes.CommF_:InvokeServer("Buso")
    end
end

-- ══════════════════════════════════════════════════════════════
-- FLIGHT CONTROLLER — lấy cơ chế Heartbeat movement từ auto_factory.lua.
-- Không tạo Tween mới ở mỗi call. Call sau chỉ cập nhật target của hành trình
-- hiện tại, nhờ vậy các loop bám cửa/mob không liên tục cancel và giật ngược.
-- ══════════════════════════════════════════════════════════════
local previousFlightCleanup = getgenv().KaitunV4FlightCleanup
if type(previousFlightCleanup) == "function" then pcall(previousFlightCleanup) end

local FlightConfig = {
    Speed = math.max(tonumber(getgenv().Config["Fly Speed"]) or 280, 1),
    Force = math.max(tonumber(getgenv().Config["Fly Force"]) or 100000, 0),
    SnapDistance = math.max(tonumber(getgenv().Config["Fly Snap Distance"]) or 8, 1),
}

local FlightState = {
    enabled = true,
    active = false,
    holdAtTarget = false,
    target = nil,
    speed = FlightConfig.Speed,
    snapDistance = FlightConfig.SnapDistance,
    floatForce = nil,
    floatRoot = nil,
    previousPlatformStand = nil,
    platformHumanoid = nil,
    collisionState = setmetatable({}, { __mode = "k" }),
    addedTeleportTag = false,
    noclipPredicate = nil,
    connections = {},
}

local function flightCharacterParts()
    local character = player.Character
    if not character then return nil, nil, nil end
    return character,
        character:FindFirstChild("HumanoidRootPart"),
        character:FindFirstChildOfClass("Humanoid")
end

local function flightStopVelocity(root)
    if not root then return end
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function flightMarkTeleporting()
    pcall(function()
        if not CollectionService:HasTag(player, "Teleporting") then
            CollectionService:AddTag(player, "Teleporting")
            FlightState.addedTeleportTag = true
        end
    end)
end

local function flightEnsureFloat(root)
    if not root then return end
    if FlightState.floatForce and FlightState.floatForce.Parent == root then return end
    if FlightState.floatForce then
        pcall(function() FlightState.floatForce:Destroy() end)
    end
    FlightState.floatForce = nil
    FlightState.floatRoot = nil

    for _, forceName in ipairs({ "KaitunV4FlightForce", "BodyClip", "AutoFactoryFloatForce" }) do
        local stale = root:FindFirstChild(forceName)
        if stale then pcall(function() stale:Destroy() end) end
    end

    local force = Instance.new("BodyVelocity")
    force.Name = "KaitunV4FlightForce"
    force.Velocity = Vector3.zero
    force.MaxForce = Vector3.new(FlightConfig.Force, FlightConfig.Force, FlightConfig.Force)
    force.P = 10000
    force.Parent = root
    FlightState.floatForce = force
    FlightState.floatRoot = root
end

local function flightShouldNoclip()
    if FlightState.active then return true end
    local predicate = FlightState.noclipPredicate
    if type(predicate) ~= "function" then return false end
    local ok, enabled = pcall(predicate)
    return ok and enabled == true
end

local function flightRestoreCollisions()
    if flightShouldNoclip() then return end
    for part, oldCanCollide in pairs(FlightState.collisionState) do
        if part and part.Parent then
            pcall(function() part.CanCollide = oldCanCollide end)
        end
    end
    table.clear(FlightState.collisionState)
end

local function flightRestoreCharacter()
    local force = FlightState.floatForce
    FlightState.floatForce = nil
    FlightState.floatRoot = nil
    if force then pcall(function() force:Destroy() end) end

    local _, root = flightCharacterParts()
    flightStopVelocity(root)

    local humanoid = FlightState.platformHumanoid
    if humanoid and humanoid.Parent and FlightState.previousPlatformStand ~= nil then
        pcall(function() humanoid.PlatformStand = FlightState.previousPlatformStand end)
    end
    FlightState.previousPlatformStand = nil
    FlightState.platformHumanoid = nil

    if FlightState.addedTeleportTag then
        pcall(function() CollectionService:RemoveTag(player, "Teleporting") end)
        FlightState.addedTeleportTag = false
    end
    flightRestoreCollisions()
end

local function flightCancel(restoreCharacter)
    FlightState.active = false
    FlightState.holdAtTarget = false
    FlightState.target = nil
    FlightState.speed = FlightConfig.Speed
    FlightState.snapDistance = FlightConfig.SnapDistance
    if restoreCharacter then flightRestoreCharacter() end
end

local function flightLeaveSeat(root, humanoid)
    flightCancel(true)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
    humanoid.Sit = false
    humanoid.Jump = true
    task.wait(0.1)
    if root.Parent then root.CFrame = root.CFrame * CFrame.new(0, 10, 0) end
end

function module:topos(targetCFrame, v36, overrideSpeed, holdAtTarget)
    if not FlightState.enabled then return false, "controller_stopped" end
    if typeof(targetCFrame) ~= "CFrame" then return false, "target_not_cframe" end
    local _, root, humanoid = flightCharacterParts()
    if not root or not humanoid or humanoid.Health <= 0 then
        return false, "character_not_ready"
    end
    if humanoid.Sit and not v36 then
        flightLeaveSeat(root, humanoid)
        return false, "leaving_seat"
    end

    local distance = (root.Position - targetCFrame.Position).Magnitude
    local snapDistance = FlightConfig.SnapDistance
    if distance <= snapDistance then
        if holdAtTarget == true then
            flightEnsureFloat(root)
            if FlightState.previousPlatformStand == nil then
                FlightState.previousPlatformStand = humanoid.PlatformStand
                FlightState.platformHumanoid = humanoid
            end
            humanoid.PlatformStand = true
            flightMarkTeleporting()
            flightStopVelocity(root)
            root.CFrame = targetCFrame
            flightStopVelocity(root)
            FlightState.active = true
            FlightState.holdAtTarget = true
            FlightState.target = targetCFrame
            FlightState.speed = math.max(tonumber(overrideSpeed) or FlightConfig.Speed, 1)
            FlightState.snapDistance = snapDistance
            return true, "hold"
        end
        flightCancel(false)
        flightMarkTeleporting()
        flightStopVelocity(root)
        root.CFrame = targetCFrame
        flightStopVelocity(root)
        flightRestoreCharacter()
        return true, "snap"
    end

    local speed = math.max(tonumber(overrideSpeed) or FlightConfig.Speed, 1)
    if FlightState.active then
        FlightState.target = targetCFrame
        FlightState.speed = speed
        FlightState.snapDistance = snapDistance
        FlightState.holdAtTarget = holdAtTarget == true
        return true, "move_updated"
    end

    flightEnsureFloat(root)
    if FlightState.previousPlatformStand == nil then
        FlightState.previousPlatformStand = humanoid.PlatformStand
        FlightState.platformHumanoid = humanoid
    end
    humanoid.PlatformStand = true
    flightMarkTeleporting()
    flightStopVelocity(root)
    FlightState.active = true
    FlightState.holdAtTarget = holdAtTarget == true
    FlightState.target = targetCFrame
    FlightState.speed = speed
    FlightState.snapDistance = snapDistance
    return true, "move_started"
end

function module:holdTopos(targetCFrame, overrideSpeed)
    return module:topos(targetCFrame, false, overrideSpeed, true)
end

function module:cancelTopos()
    flightCancel(true)
end

table.insert(FlightState.connections, RunService.Heartbeat:Connect(function(dt)
    if not FlightState.active then return end
    local _, root, humanoid = flightCharacterParts()
    local targetCFrame = FlightState.target
    if not root or not humanoid or humanoid.Health <= 0 or not targetCFrame then
        flightCancel(true)
        return
    end

    local offset = targetCFrame.Position - root.Position
    local remaining = offset.Magnitude
    if remaining <= FlightState.snapDistance then
        root.CFrame = targetCFrame
        flightStopVelocity(root)
        if FlightState.holdAtTarget then
            flightEnsureFloat(root)
            humanoid.PlatformStand = true
            return
        end
        flightCancel(true)
        return
    end

    local frameTime = math.min(math.max(tonumber(dt) or (1 / 60), 0), 0.1)
    local step = math.min(FlightState.speed * frameTime, remaining)
    local newPosition = root.Position + offset.Unit * step

    humanoid.PlatformStand = true
    flightEnsureFloat(root)
    root.CFrame = CFrame.new(newPosition) * targetCFrame.Rotation
    flightStopVelocity(root)
end))

table.insert(FlightState.connections, RunService.Stepped:Connect(function()
    local shouldNoclip = flightShouldNoclip()
    local character = player.Character
    if shouldNoclip and character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if FlightState.collisionState[part] == nil then
                    FlightState.collisionState[part] = part.CanCollide
                end
                part.CanCollide = false
            end
        end
    elseif not shouldNoclip and next(FlightState.collisionState) then
        flightRestoreCollisions()
    end
end))

table.insert(FlightState.connections, player.CharacterAdded:Connect(function()
    flightCancel(true)
    table.clear(FlightState.collisionState)
end))

getgenv().KaitunV4FlightCleanup = function()
    FlightState.enabled = false
    for _, connection in ipairs(FlightState.connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(FlightState.connections)
    FlightState.noclipPredicate = nil
    flightCancel(true)
end

function module:tele(v)
    if v then
        ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", v)
    else
        ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", game.JobId)
    end
end

function module:noclip(v)
    local predicate = nil
    if type(v) == "function" then
        predicate = v
    elseif type(v) == "string" then
        local ok, compiled = pcall(loadstring, v)
        if ok and type(compiled) == "function" then predicate = compiled end
    elseif v == true then
        predicate = function() return true end
    end
    FlightState.noclipPredicate = predicate
end

function module:getdis(x, y)
    y = y or player.Character.HumanoidRootPart.CFrame
    return (x.Position - y.Position).Magnitude
end

player.Idled:connect(function()
    game:GetService("VirtualUser"):Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    task.wait(1)
    game:GetService("VirtualUser"):Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
end)

local topofgreattree = CFrame.new(3035.15137, 2281.15918, -7325.19189)

function getdoor(vv)
    vv = vv or player.Data.Race.Value
    local temple = workspace.Map:FindFirstChild("Temple of Time")
    if not temple then return nil end
    local corridor = temple:FindFirstChild(vv .. "Corridor")
    if not corridor then return nil end
    local door = corridor:FindFirstChild("Door")
    if not door then return nil end
    return door:FindFirstChild("Entrance")
end

function getdis(...) return module:getdis(...) end

local topos = function(v)
    pcall(function()
        if getdis(v) > 2500 and getdis(CFrame.new(28310.0234, 14895.1123, 109.456741)) < 1500 then
        end
    end)
    return module:topos(v)
end

local pos_plr_trial = {
    CFrame.new(28692.3477, 14887.5605, -53.7669983),
    CFrame.new(28782.7246, 14898.9902, -59.6069946),
    CFrame.new(28700.875, 14888.2598, -154.110992),
    CFrame.new(28795.7715, 14888.2598, -112.917999),
    CFrame.new(28658.4551, 14888.2598, -121.372009),
    CFrame.new(28742.4688, 14887.5596, -18.2120056)
}

function isplrshouldkill(plr)
    if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health > 0 then
        for i, v in pairs(pos_plr_trial) do
            if getdis(plr.Character.HumanoidRootPart.CFrame, v) < 5 then return true end
        end
    end
    return false
end

local race_abilities = {
    ["Human"] = "Last Resort",
    ["Mink"] = "Agility",
    ["Fishman"] = "Water Body",
    ["Skypiea"] = "Heavenly Blood",
    ["Ghoul"] = "Heightened Senses",
    ["Cyborg"] = "Energy Core"
}

local races_trial_place = {
    ["Human"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of Strength"),
    ["Mink"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of Speed"),
    ["Fishman"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of Water"),
    ["Skypiea"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of the King"),
    ["Ghoul"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of Carnage"),
    ["Cyborg"] = workspace._WorldOrigin.Locations:WaitForChild("Trial of the Machine")
}

_G.playersinserver = {}
function updateplayers()
    if not _G.playersinserver then _G.playersinserver = {} end
    local players = {}
    for i, v in pairs(game.Players:GetChildren()) do
        players[v] = {
            ["Race"] = v.Data.Race.Value,
            ["Door"] = (function()
                local x, y = pcall(function()
                    return workspace.Map["Temple of Time"]:WaitForChild(v.Data.Race.Value .. "Corridor"):WaitForChild("Door"):WaitForChild("Entrance")
                end)
                if x then return y end
                return nil
            end)()
        }
    end
    _G.playersinserver = players
end

function isshouldturnonability()
    local count = 0
    for i, v in pairs(workspace.Characters:GetChildren()) do
        if v.Name ~= player.Name and v:FindFirstChild("HumanoidRootPart") then
            local theirrace = game.Players:FindFirstChild(v.Name).Data.Race.Value
            local corridor = workspace.Map["Temple of Time"]:FindFirstChild(theirrace .. "Corridor")
            local race_door = corridor and corridor:FindFirstChild("Door")
            race_door = race_door and race_door:FindFirstChild("Entrance")
            local abilityName = race_abilities[theirrace]
            if race_door and abilityName and getdis(race_door.CFrame, v.HumanoidRootPart.CFrame) < 10 then
                if v.HumanoidRootPart:FindFirstChild(abilityName) then
                    count = count + 1
                end
            end
        end
    end
    return count >= 2
end

local v4Started = false
function talktoonggianaodo()
    if v4Started then return end
    v4Started = true
    local ok, thua = pcall(function()
        return CommF_:InvokeServer("RaceV4Progress", "Check")
    end)
    if not ok then v4Started = false; return end
    if thua == 1 then
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Check") end)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Begin") end)
    elseif thua == 2 then
        local startAt = tick()
        repeat
            task.wait(0.5)
            pcall(function() CommF_:InvokeServer("RaceV4Progress", "Teleport") end)
            pcall(function() topos(CFrame.new(3028, 2281, -7325)) end)
        until module:getdis(CFrame.new(28286.35546875, 14896.5078125, 102.62469482422)) <= 15
            or tick() - startAt > 30  -- timeout 30s
    else
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Check") end)
        task.wait(1)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Continue") end)
    end
    v4Started = false
end

function getBlueGear()
    if not game.workspace.Map:FindFirstChild("MysticIsland") then return nil end
    for o, c in pairs(game.workspace.Map.MysticIsland:GetChildren()) do
        if c:IsA("MeshPart") and c.MeshId == "rbxassetid://10153114969" then return c end
    end
end

function isnight()
    local c = game.Lighting.ClockTime
    return c >= 16 or c < 5
end

function isfullmoon()
    return game:GetService("Lighting"):GetAttribute("MoonPhase") == 5
end

module:noclip([[return true]])

function getmob1(pos)
    local allmobs = {}
    for i, v in pairs(workspace.Enemies:GetChildren()) do
        if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid")
            and v.Humanoid.Health > 0 and getdis(v.HumanoidRootPart.CFrame, pos) < 1000 then
            table.insert(allmobs, v)
        end
    end
    return allmobs
end

function checkmob_(v)
    return v and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0
end

function noideaforname(v)
    if isallies[v.Name] then return false end
    return true
end

function getplayers(all)
    local plrs = {}
    for i, v in pairs(game.Players:GetPlayers()) do
        if v ~= player and v.Character then
            if all then
                if v.Character:FindFirstChild("Humanoid") and v.Character:FindFirstChild("HumanoidRootPart") and v.Character.Humanoid.Health > 0 then
                    for _, pos in pairs(pos_plr_trial) do
                        if getdis(v.Character.HumanoidRootPart.CFrame, pos) < 10 then plrs[v.Character] = true end
                    end
                end
            else
                if v ~= game.Players:FindFirstChild(mainAccountName) and noideaforname(v) then
                    if v.Character:FindFirstChild("Humanoid") and v.Character:FindFirstChild("HumanoidRootPart") and v.Character.Humanoid.Health > 0 then
                        for _, pos in pairs(pos_plr_trial) do
                            if getdis(v.Character.HumanoidRootPart.CFrame, pos) < 10 then plrs[v.Character] = true end
                        end
                    end
                end
            end
        end
    end
    return plrs
end

function checkbackpack(v)
    return player.Backpack:FindFirstChild(v) or player.Character:FindFirstChild(v)
end

local V4StatusCache = { at = 0, data = nil }
local V4_STATUS_CACHE_TIME = 0.75

function getLocalRaceName()
    local race = "Unknown"
    pcall(function() race = tostring(Players.LocalPlayer.Data.Race.Value) end)
    return race
end

function invokeUpgradeRace(action)
    return CommF_:InvokeServer("UpgradeRace", action)
end

function invalidateV4Status()
    V4StatusCache.at = 0
    V4StatusCache.data = nil
end

function readRaceV4Progress()
    local ok, progress = pcall(function()
        return CommF_:InvokeServer("RaceV4Progress", "Check")
    end)
    if ok then return tonumber(progress) end
    return nil
end

function getV4Status(forceRefresh)
    if not forceRefresh and V4StatusCache.data and tick() - V4StatusCache.at < V4_STATUS_CACHE_TIME then
        return V4StatusCache.data
    end

    local state = {
        key = "unknown", 
        label = "UNKNOWN",
        detail = "Unable to read Race V4 status",
        code = nil, 
        progress = nil, 
        cost = 0,
        canTrial = false, 
        needsTraining = false, 
        needsPurchase = false, 
        complete = false,
        remainingTraining = nil, 
        completedTraining = nil, 
        gear = nil,
        race = getLocalRaceName(), 
        energy = 0, 
        transformed = false
    }

    local character = Players.LocalPlayer.Character
    if not character then
        state.key = "waiting_character"
        state.label = "WAITING CHARACTER"
        state.detail = "Waiting for character to load"
        V4StatusCache.at = tick()
        V4StatusCache.data = state
        return state
    end

    local raceEnergy = character:FindFirstChild("RaceEnergy")
    local raceTransformed = character:FindFirstChild("RaceTransformed")
    if raceEnergy then state.energy = tonumber(raceEnergy.Value) or 0 end
    if raceTransformed then state.transformed = raceTransformed.Value == true end

    -- RaceTransformed chỉ tồn tại trong lúc biến hình nên không thể dùng sự tồn
    -- tại của object này để kết luận acc chưa mở V4. Luôn hỏi UpgradeRace trước;
    -- nhờ vậy lượt training 0/3 -> 1/3 vẫn được nhận là code 6 sau khi biến hình
    -- kết thúc, thay vì rơi nhầm vào chuỗi quest và teleport lên Great Tree.
    local upgradeOk, code, progress, cost = pcall(function()
        return invokeUpgradeRace("Check")
    end)

    code = tonumber(code)
    progress = tonumber(progress)
    cost = tonumber(cost) or 0

    if not upgradeOk or code == nil then
        -- UpgradeRace chưa có trạng thái hợp lệ mới được fallback sang chuỗi
        -- RaceV4Progress ban đầu. Check lỗi tạm thời trên acc đang biến hình chỉ
        -- được báo retry, tuyệt đối không chạy teleport quest.
        if not raceTransformed then
            local questProgress = readRaceV4Progress()
            local abilityName = race_abilities[state.race]
            local hasV3Ability = abilityName and checkbackpack(abilityName) ~= nil
            state.progress = questProgress

            if questProgress == nil then
                state.key = "check_failed"
                state.label = "V4 CHECK FAILED"
                state.detail = "Race V4 status is temporarily unavailable"
            elseif hasV3Ability and questProgress >= 4 then
                state.key = "first_trial_ready"
                state.label = "FIRST TRIAL READY"
                state.detail = "V3 is ready; waiting for Full Moon trial"
                state.canTrial = true
            elseif questProgress == 0 then
                state.key = "v4_quest_not_started"
                state.label = "V4 QUEST NOT STARTED"
                state.detail = "Defeat rip_indra and begin the Race V4 quest"
            elseif questProgress == 1 then
                state.key = "v4_quest_begin"
                state.label = "BEGIN V4 QUEST"
                state.detail = "Talk to Sealed King to begin the Great Tree step"
            elseif questProgress == 2 then
                state.key = "go_great_tree"
                state.label = "GO TO GREAT TREE"
                state.detail = "Use the Great Tree entrance to reach Temple of Time"
            elseif questProgress == 3 then
                state.key = "continue_v4_quest"
                state.label = "CONTINUE V4 QUEST"
                state.detail = "Return to Sealed King and continue the quest"
            elseif questProgress == 4 or questProgress == 5 then
                state.key = "first_trial_preparation"
                state.label = "FIRST TRIAL PREPARATION"
                state.detail = hasV3Ability and "V3 detected; preparing first trial" or "V3 ability was not detected"
                state.canTrial = hasV3Ability
            else
                state.key = "starting_v4"
                state.label = "STARTING V4 PROCESS"
                state.detail = "Completing the Race V4 prerequisite steps"
            end

            V4StatusCache.at = tick()
            V4StatusCache.data = state
            return state
        end

        state.key = "check_failed"
        state.label = "V4 CHECK FAILED"
        state.detail = "UpgradeRace Check remote failed"
        V4StatusCache.at = tick()
        V4StatusCache.data = state
        return state
    end

    state.code = code
    state.progress = progress
    state.cost = cost

    if code == 0 then
        state.key = "trial_ready"
        state.label = "READY FOR TRIAL"
        state.detail = "Training requirement completed"
        state.canTrial = true
        state.gear = progress
    elseif code == 1 then
        state.key = "training_stage_1"
        state.label = "TRAINING REQUIRED"
        state.detail = "Train Race V4 energy before the next upgrade"
        state.needsTraining = true
    elseif code == 2 then
        state.key = "buy_gear_1"
        state.label = "BUY NEXT GEAR"
        state.detail = "First Race V4 gear upgrade is available"
        state.needsPurchase = true
    elseif code == 3 then
        state.key = "training_stage_2"
        state.label = "TRAINING REQUIRED"
        state.detail = "Train again to improve transformation duration"
        state.needsTraining = true
    elseif code == 4 then
        state.key = "buy_duration_upgrade"
        state.label = "BUY DURATION UPGRADE"
        state.detail = "Transformation limit upgrade is available"
        state.needsPurchase = true
    elseif code == 5 then
        state.key = "completed"
        state.label = "RACE V4 COMPLETED"
        state.detail = "All Race V4 upgrades are complete"
        state.complete = true
    elseif code == 6 then
        local completed = math.clamp((progress or 2) - 2, 0, 3)
        local remaining = math.max(0, 3 - completed)
        state.key = "three_session_training"
        state.label = remaining > 0 and "TRAINING REQUIRED" or "TRAINING CHECKING"
        state.completedTraining = completed
        state.remainingTraining = remaining
        state.detail = "Additional sessions: " .. tostring(completed) .. "/3 completed"
        state.needsTraining = remaining > 0
    elseif code == 7 then
        state.key = "buy_next_upgrade"
        state.label = "BUY NEXT UPGRADE"
        state.detail = "The next Race V4 upgrade is available"
        state.needsPurchase = true
    elseif code == 8 then
        local remaining = math.max(0, 10 - (progress or 0))
        state.key = "mastery_training"
        state.label = remaining > 0 and "MASTERY TRAINING" or "MASTERY COMPLETE"
        state.remainingTraining = remaining
        state.completedTraining = math.clamp(progress or 0, 0, 10)
        state.detail = remaining > 0
            and (tostring(remaining) .. " mastery training sessions remaining")
            or "All optional mastery sessions are complete"
        state.needsTraining = remaining > 0
        state.complete = remaining <= 0
    elseif code == 9 then
        state.key = "special_race_path"
        state.label = "SPECIAL RACE PATH"
        state.detail = "This race uses a different V4 upgrade path"
    else
        state.key = "not_ready"
        state.label = "NOT TRIAL READY"
        state.detail = "Unknown UpgradeRace state: " .. tostring(code)
    end

    -- BẢN FIX MẠNH NHẤT: Bịp script, ép acc Help phải làm đệ dù Max V4
    if isAlly then
        state.complete = false
        state.canTrial = true
        state.needsPurchase = false
        state.needsTraining = false
        state.key = "trial_ready"
        state.label = "READY FOR TRIAL"
        state.detail = "Helper is ready to support"
    end
    --[[
    if npcText:match("train") or npcText:match("mastery") or npcText:match("use your powers") then
        state.needsTraining = true
        state.canTrial = false
        state.needsPurchase = false
        state.label = "NEEDS TRAINING"
    end]]
    V4StatusCache.at = tick()
    V4StatusCache.data = state
    return state
end

function getdialogoftemple()
    return getV4Status(true).detail
end

function trialable(forceRefresh)
    local state = getV4Status(forceRefresh == true)
    if isAlly then
        return true, state.gear or 5
    end

    if state.canTrial then
        return true, state.gear
    end
    if state.complete then
        return false, "completed"
    end
    if state.needsPurchase then
        local fragments = 0
        pcall(function() fragments = tonumber(Players.LocalPlayer.Data.Fragments.Value) or 0 end)
        if state.cost > 0 and fragments >= state.cost then
            local ok, bought = pcall(function()
                return invokeUpgradeRace("Buy")
            end)
            invalidateV4Status()
            if ok and bought then return false, "upgrade_bought" end
            return false, "buy_failed"
        end
        return false, "raiding"
    end
    if state.needsTraining then
        return false, 
        state.remainingTraining or "training"
    end
    return false, 
    state.key
end

-- ══════════════════════════════════════════════════════════════
-- SOURCE-STYLE COMBAT + BRING MOB
-- Tham khảo auto_boss_source_style.lua; cố ý không lấy bất kỳ Core logic nào.
-- ══════════════════════════════════════════════════════════════
-- Khai báo trước SourceBringMob để cơ chế riêng của Cyborg dùng đúng cùng cờ
-- training với luồng Temple/hop ở phía dưới.
local isCurrentlyTraining = false
local previousCombatCleanup = getgenv().KaitunV4CombatCleanup
if type(previousCombatCleanup) == "function" then pcall(previousCombatCleanup) end

local AttackConfig = {
    AttackDistance = math.max(tonumber(getgenv().Config["Attack Range"]) or 30, 1),
    AttackMobs = true,
    AttackPlayers = false,
    AttackCooldown = math.max(tonumber(getgenv().Config["Attack Delay"]) or 0, 0),
    AutoClickEnabled = false,
    BringMobs = getgenv().Config["Bring Mobs"] ~= false,
    BringMobCount = math.max(math.floor(tonumber(getgenv().Config["Bring Mob Count"]) or 2), 1),
    BringMobRadius = math.max(tonumber(getgenv().Config["Bring Mob Radius"]) or 200, 1),
    CyborgV4BringMobRadius = math.max(tonumber(getgenv().Config["Cyborg V4 Bring Mob Radius"]) or 500, 1),
    BringActivationRange = math.max(tonumber(getgenv().Config["Bring Activation Range"]) or 50, 1),
    BringPlayerSafeRange = math.max(tonumber(getgenv().Config["Bring Player Safe Range"]) or 300, 0),
    BringMobInterval = math.max(tonumber(getgenv().Config["Bring Mob Interval"]) or 0.10, 0.05),
    BringMobSpread = math.max(math.floor(tonumber(getgenv().Config["Bring Mob Spread"]) or 2), 0),
    SimulationRadius = math.max(tonumber(getgenv().Config["Simulation Radius"]) or 5000, 0),
}

local SourceCombatState = {
    currentMob = nil,
    lastAttack = 0,
    lastEquip = 0,
    lastBringMob = 0,
    lastBringCount = 0,
    lastSimulationRadius = 0,
    lastCombatResolve = -math.huge,
    registerAttack = nil,
    registerHit = nil,
    combatUtil = nil,
    fruitCombo = 0,
}

local function sourceIsAlive(entity)
    if not entity or not entity.Parent then return false end
    local humanoid = entity:FindFirstChild("Humanoid")
    local root = entity:FindFirstChild("HumanoidRootPart")
    return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

local function sourceStopVelocity(root)
    if not root then return end
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function sourceSizePart(mob)
    getgenv().AttackingMob = mob
    if not sourceIsAlive(mob) then return end
    local character = Player.Character
    local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
    local mobRoot = mob:FindFirstChild("HumanoidRootPart")
    if not playerRoot or not mobRoot
        or (playerRoot.Position - mobRoot.Position).Magnitude > AttackConfig.BringActivationRange then
        return
    end
    pcall(function()
        for _, part in ipairs(mob:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
        end
    end)
end

local function sourceExpandSimulationRadius()
    local now = tick()
    if now - SourceCombatState.lastSimulationRadius < 1 then return end
    SourceCombatState.lastSimulationRadius = now
    local env = getgenv()
    local setter = rawget(env, "sethiddenproperty")
    if type(setter) ~= "function" and type(sethiddenproperty) == "function" then
        setter = sethiddenproperty
    end
    if type(setter) == "function" then
        pcall(setter, Player, "SimulationRadius", AttackConfig.SimulationRadius)
    end
end

local function sourceHasOtherPlayerNear(position, radius)
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= Player then
            local character = other.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - position).Magnitude <= radius then return true end
        end
    end
    return false
end

local function sourceHasNetworkOwnership(part)
    local env = getgenv()
    local checker = rawget(env, "isnetworkowner")
    if type(checker) ~= "function" and type(isnetworkowner) == "function" then
        checker = isnetworkowner
    end
    if type(checker) ~= "function" then return true end
    local ok, owned = pcall(checker, part)
    return not ok or owned == true
end

local function SourceBringMob(target)
    SourceCombatState.currentMob = sourceIsAlive(target) and target or nil
    if not AttackConfig.BringMobs or not SourceCombatState.currentMob then
        SourceCombatState.lastBringCount = 0
        return 0, "disabled"
    end

    local now = tick()
    if now - SourceCombatState.lastBringMob < AttackConfig.BringMobInterval then
        return SourceCombatState.lastBringCount, "throttle"
    end
    SourceCombatState.lastBringMob = now

    local character = Player.Character
    local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not playerRoot or not targetRoot then
        SourceCombatState.lastBringCount = 0
        return 0, "missing_root"
    end
    if (playerRoot.Position - targetRoot.Position).Magnitude > AttackConfig.BringActivationRange then
        SourceCombatState.lastBringCount = 0
        return 0, "too_far"
    end

    sourceExpandSimulationRadius()
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return 0, "enemies_missing" end

    -- Cyborg chỉ được bỏ giới hạn số lượng trong đúng phiên training và khi
    -- V4 đang biến hình. Các tộc/trạng thái khác vẫn giữ Bring Mob Count.
    local cyborgV4Training = false
    pcall(function()
        local transformed = character:FindFirstChild("RaceTransformed")
        cyborgV4Training = isCurrentlyTraining
            and getLocalRaceName() == "Cyborg"
            and transformed ~= nil
            and transformed.Value == true
    end)

    local selected = {}
    local maxAdditional = cyborgV4Training
        and math.huge
        or math.max(AttackConfig.BringMobCount - 1, 0)
    local effectiveBringRadius = cyborgV4Training
        and AttackConfig.CyborgV4BringMobRadius
        or AttackConfig.BringMobRadius
    for _, mob in ipairs(enemies:GetChildren()) do
        if #selected >= maxAdditional then break end
        if mob ~= target and mob:IsA("Model") and mob.Name == target.Name
            and not mob:FindFirstChild("Ignored") and sourceIsAlive(mob) then
            local mobRoot = mob:FindFirstChild("HumanoidRootPart")
            if mobRoot
                and (mobRoot.Position - targetRoot.Position).Magnitude <= effectiveBringRadius
                and not sourceHasOtherPlayerNear(mobRoot.Position, AttackConfig.BringPlayerSafeRange)
                and sourceHasNetworkOwnership(mobRoot) then
                table.insert(selected, mob)
            end
        end
    end

    local brought = 0
    local anchor = targetRoot.CFrame
    for _, mob in ipairs(selected) do
        local mobRoot = mob:FindFirstChild("HumanoidRootPart")
        if mobRoot and mobRoot.Parent then
            sourceSizePart(mob)
            local moved = pcall(function()
                sourceStopVelocity(mobRoot)
                mobRoot.CFrame = anchor * CFrame.new(
                    0,
                    math.random(0, AttackConfig.BringMobSpread),
                    math.random(0, AttackConfig.BringMobSpread)
                )
                sourceStopVelocity(mobRoot)
            end)
            if moved then brought = brought + 1 end
        end
    end

    getgenv().AttackingMob = target
    SourceCombatState.lastBringCount = brought
    return brought, brought > 0 and "brought" or "no_candidate"
end

local function sourceResolveCombat()
    if SourceCombatState.registerAttack and SourceCombatState.registerHit
        and SourceCombatState.combatUtil then return true end
    if tick() - SourceCombatState.lastCombatResolve < 2 then return false end
    SourceCombatState.lastCombatResolve = tick()

    local combatModule = Modules:FindFirstChild("CombatUtil")
    if not combatModule then return false end
    local combatOk, combatApi = pcall(function() return require(combatModule) end)
    if not combatOk or type(combatApi) ~= "table" then return false end

    local attackRemote = Net:FindFirstChild("RE/RegisterAttack") or RegisterAttack
    local hitRemote = RegisterHit
    local netOk, netApi = pcall(function() return require(Net) end)
    if netOk and type(netApi) == "table" and type(netApi.RemoteEvent) == "function" then
        local hitOk, resolvedHit = pcall(function()
            return netApi:RemoteEvent("RegisterHit", true)
        end)
        if hitOk and resolvedHit then hitRemote = resolvedHit end
    end
    if not attackRemote or not hitRemote then return false end

    SourceCombatState.registerAttack = attackRemote
    SourceCombatState.registerHit = hitRemote
    SourceCombatState.combatUtil = combatApi
    return true
end

local SourceAllowedHitParts = {
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    UpperTorso = true, LowerTorso = true, Head = true,
}

local function sourceGetCombatModels()
    local models, seen = {}, {}
    local function add(model)
        if model and not seen[model] then
            local targetPlayer = Players:GetPlayerFromCharacter(model)
            if targetPlayer and (targetPlayer == Player or not noideaforname(targetPlayer)) then return end
            seen[model] = true
            table.insert(models, model)
        end
    end
    if AttackConfig.AttackMobs then
        local enemies = Workspace:FindFirstChild("Enemies")
        if enemies then for _, model in ipairs(enemies:GetChildren()) do add(model) end end
    end
    add(SourceCombatState.currentMob)
    if AttackConfig.AttackPlayers then
        local characters = Workspace:FindFirstChild("Characters")
        if characters then for _, model in ipairs(characters:GetChildren()) do add(model) end end
    end
    return models
end

local function sourceGetBladeHitParts(radius)
    local character = Player.Character
    local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not character or not playerRoot then return {} end
    local parts = {}
    local baseRadius = math.max(tonumber(radius) or AttackConfig.AttackDistance, 1)

    for _, model in ipairs(sourceGetCombatModels()) do
        if model:IsA("Model") and model ~= character
            and model:IsDescendantOf(Workspace) and sourceIsAlive(model) then
            local modelRoot = model:FindFirstChild("HumanoidRootPart")
            if modelRoot and modelRoot:IsA("BasePart") then
                local effectiveRadius = Players:GetPlayerFromCharacter(model)
                    and (baseRadius / 1.5) or baseRadius
                local partRadius = effectiveRadius + modelRoot.Size.X / 2
                local activationRadius = 10 + partRadius
                local samples = { modelRoot.Position }
                if modelRoot.Size.Y > 5 then
                    table.insert(samples, (
                        modelRoot.CFrame * CFrame.new(0, (-modelRoot.Size.Y * 1.5) + 3, 0)
                    ).Position)
                end
                local active = false
                for _, sample in ipairs(samples) do
                    if (sample - playerRoot.Position).Magnitude < activationRadius then
                        active = true
                        break
                    end
                end
                if active then
                    for _, part in ipairs(model:GetDescendants()) do
                        if part:IsA("BasePart")
                            and (part.Position - playerRoot.Position).Magnitude <= partRadius then
                            table.insert(parts, part)
                        end
                    end
                end
            end
        end
    end
    return parts
end

local function sourceAttackAOE(radius)
    if not sourceResolveCombat() then return nil end
    local combatUtil = SourceCombatState.combatUtil
    local hits, seenRigs = {}, {}
    for _, part in ipairs(sourceGetBladeHitParts(radius)) do
        if SourceAllowedHitParts[part.Name] then
            local rigOk, rig = pcall(function() return combatUtil:GetRigOfHitPart(part) end)
            if rigOk and rig and not seenRigs[rig] then
                local vulnerableOk, vulnerable = pcall(function()
                    return combatUtil:IsVulnerable(rig)
                end)
                if vulnerableOk and vulnerable then
                    seenRigs[rig] = true
                    table.insert(hits, { rig, part })
                end
            end
        end
    end
    return #hits > 0 and hits or nil
end

local function sourceSendHit(hits)
    if not hits or not sourceResolveCombat() then return false, "combat_missing" end
    local primary = table.remove(hits, 1)
    if not primary or not primary[2] then
        table.clear(hits)
        return false, "no_primary"
    end
    local ok = pcall(function()
        SourceCombatState.registerAttack:FireServer(0)
        SourceCombatState.registerHit:FireServer(primary[2], hits)
    end)
    table.clear(hits)
    if not ok then
        SourceCombatState.registerAttack = nil
        SourceCombatState.registerHit = nil
        return false, "remote_error"
    end
    SourceCombatState.lastAttack = tick()
    return true, "source_remote"
end

local function sourceClosestTarget(radius)
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local closest, closestDistance = nil, math.huge
    for _, model in ipairs(sourceGetCombatModels()) do
        local targetRoot = model and model:FindFirstChild("HumanoidRootPart")
        if targetRoot and sourceIsAlive(model) then
            local distance = (targetRoot.Position - root.Position).Magnitude
            if distance <= radius and distance < closestDistance then
                closest, closestDistance = model, distance
            end
        end
    end
    return closest
end

local function sourceFruitM1(tool, target)
    local character = Player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
    if not root or not targetRoot then return false end
    local leftClickRemote = tool:FindFirstChild("LeftClickRemote")
    if not leftClickRemote then return false end
    SourceCombatState.fruitCombo = SourceCombatState.fruitCombo % 5 + 1
    if tool.Name == "Mammoth-Mammoth" then
        leftClickRemote:FireServer(targetRoot.Position)
    else
        local offset = targetRoot.Position - root.Position
        local direction = offset.Magnitude > 0.001 and offset.Unit or root.CFrame.LookVector
        leftClickRemote:FireServer(direction, SourceCombatState.fruitCombo)
    end
    return true
end

local function sourceInputFallback(tool)
    local ok = pcall(function()
        if tool then tool:Activate() end
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
    if ok then SourceCombatState.lastAttack = tick() end
    return ok, ok and "input_fallback" or "input_error"
end

local FastAttack = {}
FastAttack.__index = FastAttack

function FastAttack.new()
    return setmetatable({ Connections = {} }, FastAttack)
end

function FastAttack:Attack()
    if not AttackConfig.AutoClickEnabled then return false, "disabled" end
    local now = tick()
    if AttackConfig.AttackCooldown > 0
        and now - SourceCombatState.lastAttack < AttackConfig.AttackCooldown then
        return false, "cooldown"
    end

    local character = Player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local tool = character and character:FindFirstChildOfClass("Tool")
    if not character or not humanoid or humanoid.Health <= 0 or not tool then
        return false, "not_ready"
    end
    local stun = character:FindFirstChild("Stun")
    local busy = character:FindFirstChild("Busy")
    -- Hộp chọn Quest/NPC đặt Busy=true. Khi vòng farm đã khóa một mob thật,
    -- vẫn cho source remote đánh mob đó; ngoài farm vẫn tôn trọng Busy.
    local hasLockedFarmMob = sourceIsAlive(SourceCombatState.currentMob)
    if humanoid.Sit or (stun and stun.Value > 0)
        or (busy and busy.Value and not hasLockedFarmMob) then
        return false, "blocked"
    end

    local toolTip = tostring(tool.ToolTip or "")
    local target = sourceClosestTarget(math.max(AttackConfig.AttackDistance, 70))
    if toolTip == "Blox Fruit" then
        if target then
            local callOk, fired = pcall(sourceFruitM1, tool, target)
            if callOk and fired then
                SourceCombatState.lastAttack = now
                return true, "fruit_m1"
            end
        end
        return false, "no_fruit_target"
    end
    if toolTip == "Gun" then
        if not target then return false, "no_target" end
        return sourceInputFallback(tool)
    end
    if toolTip ~= "Melee" and toolTip ~= "Fighting Style" and toolTip ~= "Sword" then
        return false, "unsupported_tool"
    end
    if not target then return false, "no_target" end

    local hits = sourceAttackAOE(AttackConfig.AttackDistance)
    if hits then return sourceSendHit(hits) end
    return sourceInputFallback(tool)
end

local AttackInstance = FastAttack.new()
table.insert(AttackInstance.Connections, RunService.Stepped:Connect(function()
    if not AttackConfig.AutoClickEnabled then return end
    pcall(function() module:haki() end)
    pcall(function() AttackInstance:Attack() end)
end))

getgenv().KaitunV4CombatCleanup = function()
    AttackConfig.AutoClickEnabled = false
    SourceCombatState.currentMob = nil
    for _, connection in ipairs(AttackInstance.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(AttackInstance.Connections)
end

_G.ShouldSendData = false
local issobusy = false

local JOB_ID = game.JobId
local USERNAME = Players.LocalPlayer.Name
local readySent = false
local abilityCooldown = 0

-- ─── LOCAL GROUP STATE (set từ Mode1 ngay khi load, không chờ API) ───
local myGroupId           = ""
local myGroupHelpers      = {}
local myGroupMainUsername = mainAccountName

-- Đọc group config và set local group ngay lập tức
local function initLocalGroup()
    if not (isUper or isAlly) then return end
    local ghGroups = getgenv().Mode1 or {}
    for _, grp in ipairs(ghGroups) do
        if type(grp) ~= "table" or not grp.name then continue end
        local helpers = grp.helpers or {}
        -- Helper: check nếu mình thuộc nhóm này
        if isAlly then
            for _, h in ipairs(helpers) do
                if tostring(h) == USERNAME then
                    myGroupId = grp.name    -- ID = tên nhóm (NhomA, NhomB,...)
                    myGroupHelpers = helpers
                    myGroupMainUsername = mainAccountName
                    return
                end
            end
        end
        -- Main: KHÔNG tự gán group tại đây!
        -- Server sẽ assign dựa trên LimitMainUpPerGroup để phân phối đều
        -- myGroupId sẽ được điền từ processSyncResponse sau khi API trả về
    end
end
initLocalGroup()

local matchState = {
    assigned      = (myGroupId ~= ""),
    group_id      = myGroupId,
    main_username = myGroupMainUsername,
    main_job_id   = game.JobId,  -- luôn init bằng jobId hiện tại (như old.lua)
    helpers       = myGroupHelpers,
    all_in_job    = true,
}
local lastHopAt     = 0
local lastHopTarget = ""
local currentFullMoon = false
local pairAllInJobAt  = tick()
local lastPairGroupId = myGroupId
local SCRIPT_START_AT = tick()   -- dùng để block hop trong vài giây đầu
local HOP_STARTUP_DELAY = 15     -- giây chờ trước khi cho phép hop

task.spawn(function()
    while task.wait(2) do
        if getgenv().UpdateRoles then
            getgenv().UpdateRoles()
        end
        if matchState and myGroupId == "" and (isUper or isAlly) then
            initLocalGroup()
        end
    end
end)

local blockHopAfterTrial = false
pcall(function()
    if isfile("piggyv4_trial_hop.txt") then
        local content = readfile("piggyv4_trial_hop.txt")
        if content == "true" then
            -- Set NGAY LẬP TỨC để block hop kể từ giây đầu, không đợi 5s
            blockHopAfterTrial = true
            task.spawn(function()
                task.wait(5)
                local hasHelper = false
                for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
                    if HelpWhitelist[p.Name] == true then
                        hasHelper = true
                        break
                    end
                end
                if hasHelper then
                    -- Có Helper → cho phép hop tìm FM bình thường
                    blockHopAfterTrial = false
                    status("Phát hiện Helper → Tiếp tục hop tìm FM")
                else
                    -- Không có Helper → giữ block, ở im server này
                    status("Không thấy Helper → Ở im server này")
                end
                writefile("piggyv4_trial_hop.txt", "false")
            end)
        end
    end
end)

local mainJobId = game.JobId
local matchTeleportAt = 0
local scheduledRoundId = ""
local handledRoundId = ""
local lastReadyWrite = 0
local currentTaskStatus = "starting"
local pairAssignedAt = tick()
-- pairAllInJobAt và lastPairGroupId đã khai báo trước task.spawn
local pairTempleReadyAt = 0
local lastTempleReadyCount = 0
local localRequeueBlockUntil = 0
local releasingGroup = false
local gearClaimInProgress = false
-- Khóa dùng chung cho khoảng chuyển trạng thái ngay sau khi mua/đổi gear.
-- Trong lúc khóa, mọi task hop và force Temple phải đứng yên cho tới khi
-- training thật sự bắt đầu hoặc server xác nhận V4 đã hoàn tất.
local postGearWorkPending = false
local postGearActionAt = 0
local postGearReason = ""
local urgentSyncNeeded = false
local lastTempleForceAt = 0
local lastTempleProgressAt = 0
local lastTempleDistance = math.huge
local pairTrialCycleStarted = false
local pairV3ActivatedAt = 0
-- isCurrentlyTraining đã khai báo trước SourceBringMob để toàn bộ luồng combat,
-- Temple và hop cùng đọc/ghi một local duy nhất.

local function markPostGearWork(reason)
    postGearWorkPending = true
    postGearActionAt = tick()
    postGearReason = tostring(reason or "gear_updated")
    readySent = false
    pairTempleReadyAt = 0
    lastTempleReadyCount = 0
    lastTempleForceAt = 0
    lastTempleProgressAt = 0
    lastTempleDistance = math.huge
    pairTrialCycleStarted = false
    pairV3ActivatedAt = 0
    urgentSyncNeeded = true
    if matchState then matchState.assigned = false end
    pcall(function() module:cancelTopos() end)
end

local function clearPostGearWork()
    postGearWorkPending = false
    postGearActionAt = 0
    postGearReason = ""
    urgentSyncNeeded = true
end

local PAIR_TEMPLE_TIMEOUT = math.max(15, tonumber(getgenv().Config["Pair Temple Timeout"]) or 35)
local stickyPairSetting = getgenv().Config["Pair Sticky Until Trial Complete"]
if stickyPairSetting == nil then
    stickyPairSetting = getgenv().Config["Pair Sticky Until Gear"]
end
local PAIR_STICKY_UNTIL_TRIAL_COMPLETE = stickyPairSetting ~= false
local PAIR_RELEASE_AFTER_TRIAL = getgenv().Config["Pair Release After Trial"] ~= false
local PAIR_REQUEUE_DELAY = math.max(5, tonumber(getgenv().Config["Pair Requeue Delay"]) or 15)
local PAIR_FORCE_TEMPLE_INTERVAL = math.max(0.25, tonumber(getgenv().Config["Pair Force Temple Interval"]) or 0.8)
local V3_DOOR_DISTANCE = math.max(10, tonumber(getgenv().Config["V3 Door Distance"]) or 50)
local API_BASE    = tostring(getgenv().Config["API Base URL"] or "http://localhost:3000"):gsub("/+$", "")

local FM_API_BASE = (function()
    local cfgUrl = tostring(getgenv().FM_API_URL or getgenv().Config["FM_API"] or ""):gsub("^%s+", ""):gsub("%s+$", "")
    -- Trống thì dùng feed Full Moon do coordinator tự tổng hợp.
    return (cfgUrl ~= "") and cfgUrl or (API_BASE .. "/server/api/moon")
end)()
local V3_FILE_ROOT     = tostring(getgenv().Config["V3 File Folder"] or "KaitunV4Sync")

local LIMIT_MAIN_PER_GROUP = math.max(1, math.min(10, tonumber(getgenv().Config["LimitMainUpPerGroup"]) or 4))
local SCRIPT_MODE = math.max(1, math.min(2, tonumber(getgenv().Config["Mode"]) or 1))

-- ══ FM JOIN CACHE (in-memory only) ══
local FM_CACHE_EXPIRE = 180
local fmJoinedCache   = {}

local function markFMJoined(jobId)
    if not jobId or jobId == "" then return end
    local now = math.floor(v3ServerNow() or os.time())
    fmJoinedCache[jobId] = now
end

local function isFMCached(jobId)
    local ts = fmJoinedCache[jobId]
    if not ts then return false end
    local now = math.floor(v3ServerNow() or os.time())
    return (now - ts) < FM_CACHE_EXPIRE
end

local function checkCanHopFM()
    local ghGroups = getgenv().Mode1 or {}
    local hasAnyHopFM = false
    local isListed = false

    for _, grp in ipairs(ghGroups) do
        if type(grp) == "table" and grp.hopfm then
            for _, name in ipairs(grp.hopfm) do
                name = tostring(name):gsub("^%s+", ""):gsub("%s+$", "")
                if name ~= "" then
                    hasAnyHopFM = true
                    if name == USERNAME then
                        isListed = true
                    end
                end
            end
        end
    end

    -- Main tuyệt đối không tự đọc FM feed để hop, vì như vậy sẽ đi vòng qua
    -- cửa sổ Help-first của API. Nếu hopfm rỗng thì mọi Help đều được quyền
    -- tìm server; nếu có danh sách thì chỉ Help được liệt kê mới tìm.
    if not isAlly then return false end
    if not hasAnyHopFM then return true end
    return isListed
end

-- ══ FM SERVER FINDER ══
-- Gọi FM_API để tìm server đang có Full Moon
-- Ưu tiên: IsNight=true + player 3-7 (optimal) + chưa cached
-- Fallback: 3+ player → bất kỳ IsNight server
-- ClockTime priority đã bị bỏ
local lastFmApiAt     = 0
local lastFmApiResult = nil   -- cache kết quả để tránh gọi API liên tục
local FM_API_INTERVAL = 4     -- gọi lại mỗi 4s (tăng tốc độ detect FM)
local FM_HOP_DELAY    = 2     -- startup delay riêng cho FM hop

local function findFMServer()
    if FM_API_BASE == "" then return nil end
    local r = req()
    if not r then return nil end
    local ok, res = pcall(function()
        return r({ Url = FM_API_BASE, Method = "GET", Headers = {} })
    end)
    if not ok or not res or res.StatusCode ~= 200 then return nil end
    local ok2, parsed = pcall(jsonDecode, res.Body)
    if not ok2 or type(parsed) ~= "table" then return nil end

    local servers = parsed.data or parsed
    if type(servers) ~= "table" then return nil end

    -- Lọc: IsNight=true + khác server hiện tại + chưa trong FM cache
    local best37  = nil   -- 3-7 player (optimal)
    local best3p  = nil   -- 3+ player (fallback)
    local bestAny = nil   -- bất kỳ IsNight (fallback cuối)

    for _, s in ipairs(servers) do
        if type(s) ~= "table" then continue end
        local jobId   = tostring(s.JobId or s.jobId or "")
        local isNight = s.IsNight == true or s.isNight == true
        if jobId == "" or jobId == game.JobId then continue end
        if not isNight then continue end
        if isFMCached(jobId) then continue end  -- bỏ qua sv đã join/thất bại

        local playersStr  = tostring(s.Players or s.players or "0/12")
        local playerCount = tonumber(playersStr:match("^(%d+)")) or 0

        if playerCount >= 3 and playerCount <= 7 and not best37 then
            best37 = jobId
        end
        if playerCount >= 3 and not best3p then
            best3p = jobId
        end
        if not bestAny then
            bestAny = jobId
        end

        if best37 and best3p and bestAny then break end
    end

    return best37 or best3p or bestAny
end


local V3_COUNTDOWN     = math.max(1, tonumber(getgenv().Config["V3 Countdown"]) or 6)
local V3_FILE_POLL     = math.max(0.05, tonumber(getgenv().Config["V3 File Poll"]) or 0.10)
local V3_READY_FRESHNESS = math.max(0.8, tonumber(getgenv().Config["V3 Ready Freshness"]) or 2.0)
local V3_REQUIRE_DIFFERENT_RACES = getgenv().Config["V3 Require Different Races"] ~= false
local V3_FIRE_COUNT    = math.max(1, math.floor(tonumber(getgenv().Config["V3 Fire Count"]) or 1))
local V3_FIRE_INTERVAL = math.max(0.03, tonumber(getgenv().Config["V3 Fire Interval"]) or 0.05)

local lastFmState     = false
urgentSyncNeeded = false


function req()
    return http_request or http and http.request or request or syn and syn.request
end

function jsonEncode(t)
    return HttpService:JSONEncode(t)
end

function jsonDecode(s)
    return HttpService:JSONDecode(s)
end

function getRole()
    if isUper then return "main" end
    if isAlly then return "helper" end
    return "none"
end

-- ── STATUS API ──

function apiPost(path, body)
    local r = req()
    if not r then return nil end
    local ok, result = pcall(function()
        local response = r({
            Url     = API_BASE .. path,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = jsonEncode(body)
        })
        if response and response.StatusCode == 200 then
            local ok2, data = pcall(jsonDecode, response.Body)
            if ok2 then return data end
        end
        return nil
    end)
    if ok then return result end
    return nil
end

function apiGet(path)
    local r = req()
    if not r then return nil end
    local ok, result = pcall(function()
        local response = r({
            Url     = API_BASE .. path,
            Method  = "GET",
            Headers = { ["Content-Type"] = "application/json" }
        })
        if response and response.StatusCode == 200 then
            local ok2, data = pcall(jsonDecode, response.Body)
            if ok2 then return data end
        end
        return nil
    end)
    if ok then return result end
    return nil
end

-- apiPostForced: blocking, không bị block bởi rate-limit nội bộ
local function apiPostForced(path, body)
    local r = req()
    if not r then return nil end
    local ok, result = pcall(function()
        local response = r({
            Url     = API_BASE .. path,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = jsonEncode(body)
        })
        if response and response.StatusCode == 200 then
            local ok2, data = pcall(jsonDecode, response.Body)
            if ok2 then return data end
        end
        return nil
    end)
    if ok then return result end
    return nil
end

-- Phân tích Mode1 thành danh sách group để gửi lên API
function parseGroupHopConfig()
    local ghGroups = getgenv().Mode1 or {}
    local groups   = {}
    for _, grp in ipairs(ghGroups) do
        if type(grp) == "table" and grp.name then
            table.insert(groups, {
                id      = grp.name,    -- ID = tên nhóm
                name    = grp.name,
                helpers = grp.helpers or {}
            })
        end
    end
    return #groups, groups
end

-- assignToGroup không còn cần thiết — sync loop /v4info xử lý
function assignToGroup() end

function resetLocalPairState()
    mainJobId        = game.JobId
    readySent        = false
    scheduledRoundId = ""
    handledRoundId = ""
    lastPairGroupId = myGroupId
    pairAssignedAt = tick()
    pairAllInJobAt = tick()
    pairTempleReadyAt = 0
    lastTempleReadyCount = 0
    lastTempleForceAt = 0
    lastTempleProgressAt = 0
    lastTempleDistance = math.huge
    pairTrialCycleStarted = false
    pairV3ActivatedAt = 0
end

function releaseCurrentGroup(reason)
    reason = tostring(reason or "completed")
    resetLocalPairState()
    -- Đẩy trạng thái mới lên API ở vòng chính kế tiếp để Main sau nhận lượt
    -- ngay, không phải chờ hết chu kỳ sync thường.
    urgentSyncNeeded = true
    return true
end

function computeQueueReady()
    if not (isnight() and isfullmoon()) then return false, "waiting_full_moon" end
    local ok, canTrial = pcall(function()
        local ready = trialable()
        return ready == true
    end)
    if ok and canTrial then return true, "ready_for_pair" end
    return false, "not_trial_ready"
end

function getCurrentUpgearTurn()
    if myGroupMainUsername ~= "" then return myGroupMainUsername end
    if mainAccountName ~= "" then return mainAccountName end
    if isUper then return USERNAME end
    return nil
end

function isOtherUpgearTraining()
    -- Helper: main của group (được gán từ API) đang train
    if not isAlly then return false end
    local mainName = myGroupMainUsername ~= "" and myGroupMainUsername or mainAccountName
    return mainName ~= ""
end

function isMyUpgearTurn()
    return isUper and myGroupMainUsername ~= "" and myGroupMainUsername == USERNAME
end


function updateDynamicGroupConfig(response)
    -- Không còn dùng — group config giờ cố định từ whitelist, không
    -- nhận dữ liệu động từ server nữa.
end

function refreshMatch()
    -- matchState.main_job_id được cập nhật bởi sync loop bên dưới
    return matchState
end

function sendMainJob()
    return matchState
end

function getMainJob()
    if isUper then return game.JobId end
    if matchState and matchState.main_job_id and matchState.main_job_id ~= "" then
        return matchState.main_job_id
    end
    return mainJobId
end

-- ── SYNC LOOP (request duy nhất mỗi 3s) ──
-- Gửi toàn bộ status lên API, nhận về group info + members status trong 1 response.
-- Thay thế hoàn toàn: heartbeat + assignToGroup + refreshMatch + startup flush.
local function buildGroupConfig()
    local ghGroups = getgenv().Mode1 or {}
    local groups   = {}
    for _, grp in ipairs(ghGroups) do
        if type(grp) == "table" and grp.name then
            groups[#groups + 1] = {
                id      = grp.name,    -- ID = tên nhóm (NhomA, NhomB,...)
                name    = grp.name,
                helpers = grp.helpers or {}
            }
        end
    end
    return #groups, groups
end

local currentApiV3Command = nil

local function processSyncResponse(resp)
    if not resp then return end

    -- Cập nhật V3 command nhận từ API
    if resp.command and type(resp.command) == "table" then
        currentApiV3Command = resp.command
    else
        currentApiV3Command = nil
    end

    -- Cập nhật myGroupId từ API response
    -- Quan trọng cho MAIN accounts: server mới là nơi quyết định assign group
    if resp.group and type(resp.group.id) == "string" and resp.group.id ~= "" then
        myGroupId = resp.group.id
        -- Luôn cập nhật helpers mỗi lần (không chỉ khi groupId đổi)
        if type(resp.group.helpers) == "table" then
            myGroupHelpers = resp.group.helpers
        end
        -- mains[1] là leader do API chọn. Cả Main và Help phải cùng dùng
        -- giá trị này để Main đang xếp hàng không tự nhận mình là đúng lượt.
        if type(resp.group.mains) == "table" and resp.group.mains[1] then
            myGroupMainUsername = tostring(resp.group.mains[1])
        end
        matchState.group_id = myGroupId
        matchState.assigned = true
    end

    local accounts = resp.accounts or {}
    local nowTs = math.floor(v3ServerNow() or os.time())
    local FM_FRESH_SECONDS = 25  -- chỉ trust FM data nếu account update trong 25s qua

    -- API mới phát JobId theo hai pha: Help trước, Main sau. Khi field này có
    -- mặt thì không tự quét accounts nữa; nếu không Main sẽ nhìn thấy Help có
    -- Full Moon và hop trước khi hết cửa sổ ưu tiên.
    if type(resp.joinTarget) == "table" then
        local joinTarget = resp.joinTarget
        local targetJobId = tostring(joinTarget.jobId or "")
        if joinTarget.allowed == true and targetJobId ~= "" then
            matchState.main_job_id = targetJobId
        else
            matchState.main_job_id = game.JobId
        end
        return
    end

    -- [2] Kiểm tra group: ai đang có FM (fresh data) — logic đồng nhất cho cả main lẫn helper
    local allNames = {myGroupMainUsername}
    for _, h in ipairs(myGroupHelpers) do table.insert(allNames, h) end
    for _, name in ipairs(allNames) do
        if name ~= USERNAME then
            local s = accounts[name]
            if s and s.jobId and s.jobId ~= "" then
                local age = nowTs - (tonumber(s.updatedAt) or 0)
                if age >= 0 and age <= FM_FRESH_SECONDS then
                    if s.fullMoon == true then
                        matchState.main_job_id = tostring(s.jobId)
                        return
                    end
                end
            end
        end
    end

    -- [3] Không ai có FM (hoặc data stale) → ở yên
    matchState.main_job_id = game.JobId
end

-- Dùng HttpService để escape username/group đúng chuẩn JSON.
-- includeGroups=true khi chưa có group (cần server assign)
local function sendSync(includeGroups)
    local r = req()
    if not r then return nil end

    local v4s = nil
    pcall(function() v4s = getV4Status(false) end)
    local frags = 0
    pcall(function() frags = tonumber(Players.LocalPlayer.Data.Fragments.Value) or 0 end)
    local race = ""
    pcall(function() race = tostring(Players.LocalPlayer.Data.Race.Value) end)
    local doorState = { alive = true, nearDoor = false, timerVisible = false, distance = math.huge }
    pcall(function() doorState = localDoorState() end)

    local doorDist = (not doorState.distance or doorState.distance == math.huge)
        and -1 or math.floor(doorState.distance * 100) / 100

    local soluong, groups = buildGroupConfig()
    local payload = {
        v               = 1,
        username        = tostring(USERNAME or ""),
        role            = tostring(getRole() or "none"),
        groupId         = tostring(currentGroupId() or ""),
        placeId         = tostring(game.PlaceId),
        jobId           = tostring(game.JobId),
        fullMoon        = currentFullMoon == true,
        nearFM          = false,
        alive           = doorState.alive == true,
        ready           = readySent == true,
        race            = race,
        canTrial        = v4s ~= nil and v4s.canTrial == true,
        -- Vừa mua gear thì buộc API nhả lượt Main ngay, kể cả UpgradeRace
        -- còn trả cache canTrial trong vài nhịp đầu.
        needsTraining   = postGearWorkPending == true
            or (v4s ~= nil and v4s.needsTraining == true),
        needsPurchase   = v4s ~= nil and v4s.needsPurchase == true,
        complete        = v4s ~= nil and v4s.complete == true,
        energy          = tonumber(v4s and v4s.energy) or 0,
        transformed     = v4s ~= nil and v4s.transformed == true,
        fragments       = tonumber(frags) or 0,
        doorDistance    = tonumber(doorDist) or -1,
        timerVisible    = doorState.timerVisible == true,
        updatedAt       = math.floor(v3ServerNow() or os.time()),
        firedRound      = tostring(handledRoundId or ""),
        soluonggroup    = soluong,
        limitMainUp     = LIMIT_MAIN_PER_GROUP,
    }
    if includeGroups then payload.groups = groups end

    local body = jsonEncode(payload)

    local ok, resp = pcall(function()
        local res = r({ Url = API_BASE .. "/v4info", Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
        if res and res.StatusCode == 200 then
            local ok2, d = pcall(jsonDecode, res.Body)
            if ok2 then return d end
        end
        return nil
    end)
    return ok and resp or nil
end

-- Sync loop 2s: gửi full status mỗi cycle
-- Startup sync: gửi ngay khi load để xóa jobId cũ
task.spawn(function()
    task.wait(0.2)
    pcall(function()
        local resp = sendSync(true)
        if resp then processSyncResponse(resp) end
    end)
end)



function autoEquipGear()
    local gearConfig = getgenv().Config["Gear"]
    if not gearConfig or #gearConfig ~= 5 then return end
    local slot1Type = string.sub(gearConfig, 1, 1)
    local slot2Type = string.sub(gearConfig, 3, 3)
    local slot3Type = string.sub(gearConfig, 5, 5)

    local accessoryMap = {
        ["A"] = { "Pale Scarf", "Pink Coat", "Valentine's Necklace", "Black Cape", "Swan Glasses", "Tomoe Ring", "Dark Coat", "Musketeer Hat", "Kitsune Mask", "Kitsune Ribbon", "Lei", "Pretty Helmet" },
        ["B"] = { "Ghoul Mask", "Winter Sky", "Black Spikey Coat", "Koko's Glasses", "Berserker Mask", "Warrior Helmet", "Water Key Necklace", "Pilot Helmet" },
        ["C"] = { "Marine Cap", "Swordsman Hat", "Usoap's Hat", "Choppa's Hat", "Robin's Glasses", "Namis Glasses", "Brook's Glasses", "Bobby's Glasses", "Jaw's Glasses", "Bear Ears", "Cool Shades", "Skeleton Mask" }
    }

    function getPriority(accessoryName)
        for tier, names in pairs(accessoryMap) do
            for _, name in ipairs(names) do
                if accessoryName:find(name) then
                    return tier == "A" and 3 or tier == "B" and 2 or 1
                end
            end
        end
        return 0
    end

    function findBestAccessoryInBackpack()
        local best, bestPriority = nil, -1
        for _, tool in ipairs(Players.LocalPlayer.Backpack:GetChildren()) do
            if tool:IsA("Accessory") then
                local priority = getPriority(tool.Name)
                if priority > bestPriority then bestPriority = priority; best = tool end
            end
        end
        return best
    end

    local character = Players.LocalPlayer.Character
    if not character then return end

    function equipToSlot(slotIndex, desiredType)
        local currentAccessory = character:FindFirstChildOfClass("Accessory")
        if currentAccessory and currentAccessory.Name:find("Accessory") then
            local currentPriority = getPriority(currentAccessory.Name)
            local desiredPriority = desiredType == "-" and 99 or (accessoryMap[desiredType] and (desiredType == "A" and 3 or desiredType == "B" and 2 or 1) or 0)
            if currentPriority >= desiredPriority then return end
        end
        local bestBackpack = findBestAccessoryInBackpack()
        if bestBackpack then
            local backpackPriority = getPriority(bestBackpack.Name)
            local desiredPriority = desiredType == "-" and 0 or (accessoryMap[desiredType] and (desiredType == "A" and 3 or desiredType == "B" and 2 or 1) or 0)
            if backpackPriority >= desiredPriority then
                Players.LocalPlayer.Character.Humanoid:EquipTool(bestBackpack)
            end
        end
    end

    if Players.LocalPlayer.Backpack:FindFirstChildOfClass("Accessory") then
        equipToSlot(1, slot1Type)
    end
end

function checkgear()
    if gearClaimInProgress or not CommF_ then return false end
    gearClaimInProgress = true

    local function finish(result)
        gearClaimInProgress = false
        return result
    end

    local function snapshot(clockData)
        local details = clockData and clockData.RaceDetails
        if type(details) ~= "table" then return nil end

        local gears = type(details.Gears) == "table" and details.Gears or {}
        local gearParts = {}
        for index = 1, 3 do
            gearParts[index] = tostring(gears[index] or "")
        end

        return {
            hadPoint = clockData.HadPoint == true,
            raceLevel = tonumber(clockData.RaceLevel) or 0,
            a = tonumber(details.A) or 0,
            b = tonumber(details.B) or 0,
            c = tonumber(details.C) or 0,
            completed = tonumber(details.Completed) or tonumber(clockData.Completed) or 0,
            gears = table.concat(gearParts, "|"),
            rawGears = { gearParts[1], gearParts[2], gearParts[3] }
        }
    end

    local ok, beforeData = pcall(function()
        return CommF_:InvokeServer("TempleClock", "Check")
    end)
    local before = ok and snapshot(beforeData) or nil
    if not before then return finish(false) end

    -- Lấy config gear (Mặc định hoặc Tối ưu theo tộc)
    local pattern = getgenv().Config and getgenv().Config["Gear"] or "B-B-A"
    if getgenv().Config and getgenv().Config["ChangeBestGear"] then
        local race = Players.LocalPlayer.Data.Race.Value
        if bestGearForRace and bestGearForRace[race] then 
            pattern = bestGearForRace[race] 
        end
    end

    local g1, g2, g3 = tostring(pattern):match("^([AB])%-([AB])%-([AB])$")
    if not g1 or not g2 or not g3 then
        g1, g2, g3 = "B", "B", "A"
    end

    local convert = { A = "Alpha", B = "Omega" }
    local targetGears = { convert[g1], convert[g2], convert[g3] }
    local installedCount = before.a + before.b

    -- === TÍNH NĂNG MỚI: TỰ ĐỘNG XOAY/ĐỔI GEAR KHI ĐÃ MAX V4 ===
    if installedCount >= 3 then
        local changedAny = false
        for i = 1, 3 do
            -- Nếu gear hiện tại khác với gear mong muốn trong Config, tiến hành đổi
            if before.rawGears[i] ~= "" and before.rawGears[i] ~= targetGears[i] then
                local slotNameToChange = "Gear" .. tostring(i + 1)
                local changedOk, changedResult = pcall(function()
                    return CommF_:InvokeServer("TempleClock", "ChangeGear", slotNameToChange, targetGears[i])
                end)
                if changedOk and changedResult ~= false then changedAny = true end
                task.wait(0.5)
            end
        end
        
        if changedAny then
            markPostGearWork("temple_clock_change_gear")
            invalidateV4Status()
            finish(true)
            if isUper and isMyUpgearTurn() and matchState and matchState.assigned then
                task.spawn(function() releaseCurrentGroup("gear_changed") end)
            end
            return true
        end
        
        -- Nếu gear đã chuẩn theo Config -> Không cần đổi, pass qua
        finish(false)
        if isUper and isMyUpgearTurn() and matchState and matchState.assigned then
            task.spawn(function() releaseCurrentGroup("gear_maxed_and_perfect") end)
        end
        return false
    end

    -- === TÍNH NĂNG CŨ: CLAIM (LẤY) GEAR MỚI KHI CÓ POINT ===
    if beforeData.HadPoint ~= true then
        return finish(false)
    end

    local slotName = nil
    local choose = nil
    local isFirstGear = before.raceLevel < 2

    if isFirstGear then
        slotName = "Gear1"
    else
        if installedCount < 0 or installedCount > 2 then
            return finish(false)
        end

        local slotIndex = installedCount + 2
        local slotPattern = { g1, g2, g3 }
        slotName = "Gear" .. tostring(slotIndex)
        choose = convert[slotPattern[installedCount + 1]]

        -- Luật của Blox Fruits: Tối đa 2 Alpha hoặc 2 Omega
        if before.a >= 2 then
            choose = "Omega"
        elseif before.b >= 2 then
            choose = "Alpha"
        elseif choose ~= "Alpha" and choose ~= "Omega" then
            choose = "Omega"
        end
    end

    local spentOk, spentResult = pcall(function()
        if isFirstGear then
            return CommF_:InvokeServer("TempleClock", "SpendPoint")
        end
        return CommF_:InvokeServer("TempleClock", "SpendPoint", slotName, choose)
    end)

    if not spentOk or spentResult == false then
        return finish(false)
    end

    -- Khóa Temple ngay khi server đã nhận SpendPoint, không chờ vòng verify
    -- kết thúc; đây là cửa sổ race-condition từng kéo nhân vật lên lại Temple.
    markPostGearWork("temple_clock_spend_point")
    invalidateV4Status()

    local claimed = false
    for _ = 1, 12 do
        task.wait(0.35)
        local verifyOk, verifyData = pcall(function()
            return CommF_:InvokeServer("TempleClock", "Check")
        end)
        local after = verifyOk and snapshot(verifyData) or nil

        if after and verifyData.HadPoint == false then
            local progressionChanged
            if isFirstGear then
                progressionChanged = after.raceLevel > before.raceLevel
                    or after.completed ~= before.completed
                    or after.gears ~= before.gears
            else
                progressionChanged = after.a ~= before.a
                    or after.b ~= before.b
                    or after.gears ~= before.gears
                    or after.completed ~= before.completed
            end

            if progressionChanged then
                claimed = true
                break
            end
        end
    end

    if claimed then
        invalidateV4Status()
        finish(true)
        if isUper and isMyUpgearTurn() and matchState and matchState.assigned then
            task.spawn(function() releaseCurrentGroup("gear_claimed") end)
        end
        return true
    end

    return finish(false)
end

task.spawn(function()
    while task.wait(5) do
        if Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("Humanoid") then
            pcall(autoEquipGear)
        end
    end
end)

task.spawn(function()
    while task.wait(1) do
        if isUper and isMyUpgearTurn() and matchState and matchState.assigned then
            pcall(checkgear)
        end
    end
end)

local isCurrentGroupInThisServer

function localDoorState()
    local door = getdoor()
    local char = Players.LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local distance = math.huge
    if door and hrp then
        distance = (door.Position - hrp.Position).Magnitude
    end
    local timerVisible = false
    pcall(function()
        timerVisible = Players.LocalPlayer.PlayerGui.Main.Timer.Visible == true
    end)
    local alive = hum ~= nil and hum.Health > 0
    local nearDoor = alive and door ~= nil and distance <= V3_DOOR_DISTANCE
    return {
        door = door,
        distance = distance,
        nearDoor = nearDoor,
        timerVisible = timerVisible,
        alive = alive
    }
end

local TEMPLE_ENTRY_POSITION = Vector3.new(28310.0234, 14895.1123, 109.456741)
local EntranceRoutes = {
    Sea3 = {
        TrialToGreatTree = {
            ArrivalCFrame = topofgreattree,
            InteractionCFrame = CFrame.new(28603.7305, 14896.5352, 105.38382),
            TempleCenter = TEMPLE_ENTRY_POSITION,
            -- Trial nằm rất cao; đôi lúc nhân vật rơi sâu dưới Temple trước khi
            -- state training cập nhật. Bán kính lớn vẫn không chạm các đảo Sea 3.
            TempleRadius = 18000,
            TempleMinY = 8000,
            Attempts = 3,
            InteractionDelay = 0.7,
            VerifyTimeout = 3.0,
        }
    }
}

local function isInsideTempleForTraining(root, route)
    return root ~= nil
        and route ~= nil
        and ((root.Position - route.TempleCenter).Magnitude <= route.TempleRadius
            or root.Position.Y >= route.TempleMinY)
end

local trialExitRouteActive = false

local function useTrialExitRoute(roleLabel, shouldAbort)
    if getgenv().Config["Use Trial Exit Entrance"] == false then
        return true, "disabled"
    end

    local route = EntranceRoutes.Sea3 and EntranceRoutes.Sea3.TrialToGreatTree
    local character = Players.LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not route or not root then return false, "route_not_ready" end
    if not isInsideTempleForTraining(root, route) then return true, "not_needed" end
    if trialExitRouteActive then return false, "already_running" end

    if type(shouldAbort) == "function" and shouldAbort() then
        return false, "aborted"
    end

    trialExitRouteActive = true
    local function finish(ok, reason)
        trialExitRouteActive = false
        return ok, reason
    end

    -- Không PivotTo thẳng xuống Great Tree: server có thể phục hồi vị trí Temple
    -- rồi flight controller lại kéo xuống, gây vòng lặp xuống -> bật lên -> xuống.
    -- Đứng đúng điểm tương tác và dùng remote TeleportBack để server tự dịch chuyển.
    status(tostring(roleLabel) .. " using Trial exit -> Great Tree")
    module:cancelTopos()
    for attempt = 1, route.Attempts do
        if type(shouldAbort) == "function" and shouldAbort() then
            module:cancelTopos()
            return finish(false, "aborted")
        end

        character = Players.LocalPlayer.Character
        root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            module:cancelTopos()
            return finish(false, "character_lost")
        end

        module:cancelTopos()
        pcall(function()
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.Sit = false end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            character:PivotTo(route.InteractionCFrame)
            root.CFrame = route.InteractionCFrame
        end)
        module:holdTopos(route.InteractionCFrame)
        task.wait(route.InteractionDelay)

        -- Phải thả BodyVelocity/PlatformStand trước khi server teleport, nếu
        -- không flight controller có thể giữ lại target ở Temple.
        module:cancelTopos()
        local remoteOk, remoteResult = pcall(function()
            return CommF_:InvokeServer("RaceV4Progress", "TeleportBack")
        end)

        local verifyUntil = tick() + route.VerifyTimeout
        repeat
            task.wait(0.1)
            character = Players.LocalPlayer.Character
            root = character and character:FindFirstChild("HumanoidRootPart")
            if root
                and not isInsideTempleForTraining(root, route)
                and (root.Position - route.ArrivalCFrame.Position).Magnitude <= 2500 then
                module:cancelTopos()
                status(tostring(roleLabel) .. " exited Trial -> Great Tree")
                return finish(true, "teleport_back")
            end
        until tick() >= verifyUntil

        status(string.format(
            "%s Trial exit retry (%d/%d): %s",
            tostring(roleLabel),
            attempt,
            route.Attempts,
            remoteOk and tostring(remoteResult) or tostring(remoteResult)
        ))
    end

    module:cancelTopos()
    return finish(false, "teleport_back_failed")
end

function isInsideOwnTrial()
    local race = ""
    pcall(function() race = Players.LocalPlayer.Data.Race.Value end)
    local trialLocation = races_trial_place[race]
    if trialLocation then
        local ok, distance = pcall(function() return getdis(trialLocation.CFrame) end)
        if ok and distance < 1500 then return true end
    end
    local timerVisible = false
    pcall(function() timerVisible = Players.LocalPlayer.PlayerGui.Main.Timer.Visible == true end)
    return timerVisible
end

function forceMatchedAccountToTemple()
    -- Một khi đã bắt đầu train, mọi tín hiệu Temple cũ đều hết hiệu lực.
    -- Không cho task ghép nhóm đổi target flight hoặc requestEntrance ngược lên.
    if isCurrentlyTraining then return false end
    if gearClaimInProgress or postGearWorkPending then
        readySent = false
        pcall(function() module:cancelTopos() end)
        return false
    end
    local currentV4 = nil
    pcall(function() currentV4 = getV4Status(false) end)
    if currentV4 and (currentV4.needsTraining or currentV4.needsPurchase) then
        readySent = false
        return false
    end
    if not isCurrentGroupInThisServer() or not (isnight() and isfullmoon()) then return false end
    if isInsideOwnTrial() then return true end
    if tick() - lastTempleForceAt < PAIR_FORCE_TEMPLE_INTERVAL then return false end
    lastTempleForceAt = tick()

    if not workspace.Map:FindFirstChild("Temple of Time") then
        local templeRef = ReplicatedStorage.MapStash:FindFirstChild("Temple of Time")
        if templeRef then templeRef.Parent = workspace.Map end
    end

    local door = getdoor()
    local char = Players.LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        status("Paired - waiting character before Temple")
        return false
    end

    local templeDistance = (root.Position - TEMPLE_ENTRY_POSITION).Magnitude
    if not door or templeDistance > 3000 then
        status("Paired - entering Temple of Time")
        pcall(function() CommF_:InvokeServer("requestEntrance", TEMPLE_ENTRY_POSITION) end)
        return false
    end

    local distance = (door.Position - root.Position).Magnitude
    if distance + 20 < lastTempleDistance then
        lastTempleDistance = distance
        lastTempleProgressAt = tick()
    elseif lastTempleProgressAt <= 0 then
        lastTempleProgressAt = tick()
    end

    if distance > V3_DOOR_DISTANCE then
        status(string.format("Paired - flying to race door (%.0f)", distance))
        pcall(function() module:holdTopos(door.CFrame) end)
        if tick() - lastTempleProgressAt > 8 then
            lastTempleProgressAt = tick()
            pcall(function() CommF_:InvokeServer("requestEntrance", TEMPLE_ENTRY_POSITION) end)
            task.wait(0.25)
            pcall(function() module:holdTopos(door.CFrame) end)
        end
        return false
    end

    pcall(function() module:holdTopos(door.CFrame) end)
    status("Paired - at race door")
    return true
end

function v3ServerNow()
    local ok, value = pcall(function() return Workspace:GetServerTimeNow() end)
    if ok and tonumber(value) then return tonumber(value) end
    return tick()
end

function sanitizeFilePart(value)
    value = tostring(value or "unknown")
    value = value:gsub("[^%w%-%_%.]", "_")
    if value == "" then value = "unknown" end
    return value
end

-- ── GROUP UTILS ──

function currentGroupId()
    return myGroupId
end

function currentGroupMembers()
    -- 1 main + 2 helper cần cho V3 fire
    local members = {}
    local seen    = {}
    local function add(name)
        name = tostring(name or "")
        if name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(members, name)
        end
    end
    add(myGroupMainUsername)
    for _, name in ipairs(myGroupHelpers) do add(name) end
    return members
end

isCurrentGroupInThisServer = function()
    if not matchState or not matchState.assigned or myGroupId == "" then return false end
    -- Chỉ Main leader mới thuộc bộ ba đang Trial; Main khác phải chờ lượt.
    if isUper then return isMyUpgearTurn() end
    -- Helper: chỉ khi main đang ở cùng server
    return tostring(matchState.main_job_id or "") == tostring(game.JobId)
end

function writeOwnDoorFile(force)
    if not isCurrentGroupInThisServer() then readySent = false; return false end
    if not force and tick() - lastReadyWrite < V3_FILE_POLL then return readySent end
    lastReadyWrite = tick()

    local doorState = localDoorState()
    local race = ""
    pcall(function() race = Players.LocalPlayer.Data.Race.Value end)
    local ready = tick() >= abilityCooldown
        and doorState.alive
        and doorState.nearDoor
        and not doorState.timerVisible

    readySent = ready

    return ready
end
-- Alias
apiPostStatus = writeOwnDoorFile

function readReadyFiles()
    if myGroupId == "" then return 0, false, {}, "no_group" end
    local members = currentGroupMembers()
    if #members ~= 3 then return 0, false, {}, "need_exactly_3_members" end

    -- Gọi API ready check của server để đồng bộ qua internet
    local r = req()
    if not r then return 0, false, {}, "http_request_unavailable" end

    local url = API_BASE .. "/v4info/ready/" .. tostring(myGroupId) 
        .. "?jobId=" .. tostring(game.JobId)
        .. "&username=" .. HttpService:UrlEncode(tostring(USERNAME))
        .. "&freshness=" .. tostring(V3_READY_FRESHNESS)
        .. "&requireDiffRaces=" .. tostring(V3_REQUIRE_DIFFERENT_RACES)

    local ok, res = pcall(function()
        return r({ Url = url, Method = "GET", Headers = {} })
    end)

    if not ok or not res or res.StatusCode ~= 200 then
        return 0, false, {}, "api_error"
    end

    local ok2, data = pcall(jsonDecode, res.Body)
    if not ok2 or type(data) ~= "table" then
        return 0, false, {}, "api_parse_error"
    end

    local readyCount = tonumber(data.readyCount) or 0
    local allReady = data.allReady == true
    local records = data.records or {}
    local reason = data.reason or "waiting"

    if not allReady then
        if reason == "duplicate_race" then
            return readyCount, false, records, "duplicate_race"
        elseif reason == "need_3_members" then
            return readyCount, false, records, "need_exactly_3_members"
        elseif reason == "not_leader" then
            return readyCount, false, records, "not_leader"
        else
            return readyCount, false, records, "waiting_files"
        end
    end

    return readyCount, true, records, "ready"
end

function readV3Command()
    local data = currentApiV3Command
    if not data then return nil end
    if tostring(data.group_id or "") ~= currentGroupId() then return nil end
    if tostring(data.job_id or "") ~= tostring(game.JobId) then return nil end
    local now = v3ServerNow()
    local expiresAt = tonumber(data.expires_at) or 0
    if expiresAt <= now then return nil end
    return data
end

function writeV3Command(command)
    if myGroupId == "" then return false end
    local res = apiPost("/v4info/command/" .. tostring(myGroupId), command)
    return res ~= nil
end

function mainCreateRound()
    if not isUper or not isMyUpgearTurn() or not isCurrentGroupInThisServer() then return nil end

    local current = readV3Command()
    if current then return current end

    local count, allReady, _, reason = readReadyFiles()
    if not allReady then
        if reason == "duplicate_race" then
            status("V3 files 3/3 but races are duplicated")
        elseif reason == "need_exactly_3_members" then
            status("V3 file sync needs exactly 1 Main + 2 Help")
        elseif reason == "not_leader" then
            status("Waiting API leader turn before V3")
        elseif reason == "workspace_folder_unavailable" then
            status("Cannot open shared executor workspace folder")
        else
            status("V3 workspace ready " .. tostring(count) .. "/3")
        end
        return nil
    end

    local now = v3ServerNow()
    local fireAt = now + V3_COUNTDOWN
    local roundId = sanitizeFilePart(USERNAME) .. "_" .. tostring(math.floor(fireAt * 1000))
    local command = {
        version = 1,
        group_id = currentGroupId(),
        job_id = game.JobId,
        main_username = USERNAME,
        members = currentGroupMembers(),
        round_id = roundId,
        created_at = now,
        fire_at = fireAt,
        expires_at = fireAt + 10,
        countdown = V3_COUNTDOWN
    }

    if writeV3Command(command) then
        status("V3 workspace 3/3 - countdown " .. tostring(V3_COUNTDOWN) .. "s")
        return command
    end
    status("Failed to write V3 command file")
    return nil
end

function commandHasCurrentUser(command)
    for _, name in ipairs(command.members or {}) do
        if tostring(name) == USERNAME then return true end
    end
    return false
end

function waitForSharedFireTime(fireAt)
    while true do
        local remaining = fireAt - v3ServerNow()
        if remaining <= 0 then return end
        status(string.format("V3 countdown %.2fs", remaining))
        if remaining > 0.25 then
            task.wait(math.min(0.10, math.max(0.03, remaining - 0.15)))
        else
            RunService.Heartbeat:Wait()
        end
    end
end

function scheduleWorkspaceRound(command)
    local roundId = tostring(command and command.round_id or "")
    local fireAt = tonumber(command and command.fire_at) or 0
    if roundId == "" or fireAt <= 0 then return false end
    if roundId == handledRoundId or roundId == scheduledRoundId then return false end
    if not commandHasCurrentUser(command) then return false end

    scheduledRoundId = roundId
    task.spawn(function()
        waitForSharedFireTime(fireAt)

        local validGroup = isCurrentGroupInThisServer()
            and tostring(command.group_id or "") == currentGroupId()
            and tostring(command.job_id or "") == tostring(game.JobId)
        local doorState = localDoorState()
        local fired = false

        if validGroup and doorState.nearDoor and not doorState.timerVisible then
            status("Activating Race V3 from shared workspace time")
            for index = 1, V3_FIRE_COUNT do
                pcall(function()
                    ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
                end)
                if index < V3_FIRE_COUNT then task.wait(V3_FIRE_INTERVAL) end
            end
            handledRoundId = roundId
            abilityCooldown = tick() + 30
            readySent = false
            fired = true
            if isUper and isMyUpgearTurn() then
                pairTrialCycleStarted = true
                pairV3ActivatedAt = tick()
            end
        else
            status("V3 countdown ended but account left its race door")
        end

        scheduledRoundId = ""
        writeOwnDoorFile(true)
        return fired
    end)
    return true
end

local activatingAbility = false

function tryActivateAbility()
    if activatingAbility then return false end
    if isUper and not isMyUpgearTurn() then return false end
    if not isCurrentGroupInThisServer() then return false end

    -- Thread này chạy nền liên tục. Khi đang train ở ngoài Temple,
    -- không cho nó ghi đè status hoặc tạo round V3 từ xa.
    local doorState = localDoorState()
    if not doorState.alive or not doorState.nearDoor or doorState.timerVisible then
        readySent = false
        return false
    end

    activatingAbility = true
    writeOwnDoorFile(false)

    local command = nil
    if isUper and isMyUpgearTurn() then
        command = mainCreateRound()
    else
        command = readV3Command()
        if not command then
            local _, ownReady = pcall(writeOwnDoorFile, false)
            if ownReady then status("At race door - waiting Main file countdown") end
        end
    end

    activatingAbility = false
    if command then return scheduleWorkspaceRound(command) end
    return false
end

task.spawn(function()
    while task.wait(V3_FILE_POLL) do
        pcall(tryActivateAbility)
    end
end)

local TyrState = {
    AttackLoaded = false, Farming = true, CurrentMode = "STARTING",
    CurrentTarget = nil, LastStatus = "",
    TrackedBreakables = setmetatable({}, { __mode = "k" }),
    CachedBreakables = {}, LastBreakableScan = 0
}

local TIKI_CENTER = CFrame.new(-16682.7, 215, 524.2)
local TYRANT_ENTRANCE = CFrame.new(-16342.5, 174, 1397)
local ARENA_CENTER = Vector3.new(-16335, 174, 1397)
local DRAGON_TALON_BUY_POS = CFrame.new(5661.616211, 1211.299438, 865.999451)

local TikiMobs = {
    ["Isle Outlaw"] = true, ["Island Boy"] = true, ["Sun-kissed Warrior"] = true,
    ["Isle Champion"] = true, ["Serpent Hunter"] = true, ["Skull Slayer"] = true
}

local TrainingIslandData = {
    ["Haunted Castle"] = {
        Position = CFrame.new(-9530.61035, 200.860657, 5763.13477),
        Mobs = { ["Reborn Skeleton"] = true, ["Living Zombie"] = true, ["Demonic Soul"] = true, ["Possessed Mummy"] = true }
    },
    ["Cake Land"] = {
        Position = CFrame.new(-2020, 60, -12550),
        Mobs = {
            ["Cookie Crafter"] = true,
            ["Cake Guard"] = true,
            ["Baking Staff"] = true,
            ["Head Baker"] = true
        },
        MobRoutes = {
            ["Cookie Crafter"] = {
                CFrame.new(-2499.165, 36.672, -12165.021),
                CFrame.new(-2321.712, 36.672, -12216.787),
                CFrame.new(-2423.400, 36.672, -12265.764),
                CFrame.new(-2212.892, 36.672, -11969.256),
                CFrame.new(-2464.478, 36.672, -12049.936),
                CFrame.new(-2246.376, 36.672, -12126.943),
                CFrame.new(-2342.876, 36.672, -12009.240),
            },
            ["Cake Guard"] = {
                CFrame.new(-1471.126, 36.672, -12436.842),
                CFrame.new(-1531.415, 36.672, -12132.443),
                CFrame.new(-1703.079, 36.672, -12238.959),
                CFrame.new(-1418.509, 36.672, -12255.717),
                CFrame.new(-1682.626, 36.672, -12395.287),
            },
            ["Baking Staff"] = {
                CFrame.new(-1759.290, 36.672, -12994.834),
                CFrame.new(-1800.501, 36.672, -12818.326),
                CFrame.new(-1980.438, 36.672, -12983.842),
                CFrame.new(-1828.798, 36.672, -12699.443),
                CFrame.new(-1720.853, 36.672, -13087.123),
                CFrame.new(-1847.181, 36.672, -13132.506),
            },
            ["Head Baker"] = {
                CFrame.new(-2151.376, 52.273, -13033.396),
                CFrame.new(-2100.704, 52.273, -12720.967),
                CFrame.new(-2263.353, 52.273, -12711.389),
                CFrame.new(-2389.228, 52.273, -13018.334),
                CFrame.new(-2251.579, 52.273, -13033.396),
                CFrame.new(-2369.087, 52.273, -12807.920),
            },
        }
    },
    ["Tiki Outpost"] = {
        Position = CFrame.new(-16490.9727, 98.1144867, 1245.58984, -0.034969449, 0, 0.999388516, 0, 1, 0, -0.999388516, 0, -0.034969449),
        Mobs = {
            ["Isle Outlaw"] = true, ["Island Boy"] = true,
            ["Sun-kissed Warrior"] = true, ["Isle Champion"] = true,
            ["Serpent Hunter"] = true, ["Skull Slayer"] = true
        },
        -- Chỉ dùng để bay tới camp và kích hoạt streaming; mục tiêu đánh vẫn phải
        -- là mob sống thật trong workspace.Enemies.
        MobRoutes = {
            ["Isle Outlaw"] = {
                CFrame.new(-16289.492, 20.544, -179.445),
                CFrame.new(-16351.781, 20.635, -282.453),
                CFrame.new(-16163.422, 10.511, -99.359),
                CFrame.new(-16122.406, 10.635, -257.352),
            },
            ["Island Boy"] = {
                CFrame.new(-16883.352, 20.641, -251.844),
                CFrame.new(-16991.727, 10.516, -186.188),
                CFrame.new(-16905.305, 10.511, -73.500),
                CFrame.new(-16661.570, 54.565, -252.969),
                CFrame.new(-16764.320, 20.547, -118.797),
            },
            ["Sun-kissed Warrior"] = {
                CFrame.new(-16402.037, 54.565, 1083.514),
                CFrame.new(-16052.453, 11.633, 1061.915),
                CFrame.new(-16186.422, 20.547, 1098.086),
                CFrame.new(-16153.367, 10.633, 942.446),
            },
            ["Isle Champion"] = {
                CFrame.new(-16816.555, 21.547, 968.485),
                CFrame.new(-16733.744, 20.544, 1070.883),
                CFrame.new(-16940.805, 10.501, 1070.860),
            },
            ["Serpent Hunter"] = {
                CFrame.new(-16542.029, 48.429, 1789.211),
                CFrame.new(-16449.619, 68.588, 1714.080),
                CFrame.new(-16534.164, 96.734, 1597.735),
                CFrame.new(-16536.023, 106.375, 1347.141),
                CFrame.new(-16621.420, 121.394, 1290.690),
            },
            ["Skull Slayer"] = {
                CFrame.new(-16795.910, 68.589, 1795.871),
                CFrame.new(-16829.428, 191.564, 1753.422),
                CFrame.new(-16956.299, 189.676, 1640.221),
                CFrame.new(-16985.727, 57.549, 1632.822),
                CFrame.new(-16811.570, 85.412, 1542.235),
            },
        }
    },
    ["Great Tree"] = {
    Positions = {
        CFrame.new(2527.22119, 88.0126953, -7554.48096, -0.999390602, -0.0349089168, -1.05798244e-06, 1.05798244e-06, -6.05583191e-05, 1, -0.0349089168, 0.999390483, 6.05583191e-05),
        CFrame.new(2923.90332, 91.6738281, -7734.71631, 0.997561574, -0, -0.0697919354, 0, 1, -0, 0.0697919354, 0, 0.997561574),
        CFrame.new(3778.4248, 116.34375, -6938.81641, -0.667134643, -0.731317759, 0.141794443, -0.207926333, 2.65836716e-05, -0.978144467, 0.71533066, -0.682036817, -0.152077913)
    },    
    Mobs = {
        ["Marine Commodore"] = true,
        ["Marine Rear Admiral"] = true
    }
},
    ["Peanut + Ice Cream"] = {
        Positions = {
            CFrame.new(-2087.0561523438, 11.722011566162, -10002.080078125),
            CFrame.new(-851.74633789062, 65.819496154785, -10932.150390625),
        },
        Mobs = {
            ["Peanut Scout"] = true,
            ["Peanut President"] = true,
            ["Ice Cream Chef"] = true,
            ["Ice Cream Commander"] = true
        },
        MobRoutes = {
            ["Peanut Scout"] = {
                CFrame.new(-2087.0561523438, 11.722011566162, -10002.080078125),
            },
            ["Peanut President"] = {
                CFrame.new(-2087.0561523438, 11.722011566162, -10002.080078125),
            },
            ["Ice Cream Chef"] = {
                CFrame.new(-851.74633789062, 65.819496154785, -10932.150390625),
            },
            ["Ice Cream Commander"] = {
                CFrame.new(-851.74633789062, 65.819496154785, -10932.150390625),
            },
        }
    },
    ["Port Town"] = {
        Positions = {
            CFrame.new(-172.031281, 52.8853912, 5851.12793, 0.965929627, -0, -0.258804798, 0, 1, -0, 0.258804798, 0, 0.965929627),
            CFrame.new(-638.581543, 50.9266357, 5627.74951, 0.258864343, 0, 0.965913713, 0, 1, 0, -0.965913713, 0, 0.258864343),
            CFrame.new(-61.3757935, 48.8545227, 6151.30762, 0.965929627, -0, -0.258804798, 0, 1, -0, 0.258804798, 0, 0.965929627),
            CFrame.new(-662.967041, 65.9991913, 5804.41699, 0.965938151, 0.050586991, -0.253780305, -4.01213765e-06, 0.980709016, 0.195473209, 0.258773029, -0.188813999, 0.947304487)
        },
        Mobs = { ["Pirate Millionaire"] = true, ["Pistol Billionaire"] = true }
    }
}

local TrainingIslandOrder = getgenv().Config["Training Islands"] or {
    "Haunted Castle", "Cake Land", "Peanut + Ice Cream", "Tiki Outpost", "Great Tree", "Port Town"
}

local MAX_ACCS_PER_ISLAND = 2
local myAssignedIsland = nil
-- isCurrentlyTraining đã khai báo cùng pair state để luồng Temple cũng nhìn thấy.
isCurrentlyTraining = false  -- flag block hop khi đang training

local ISLAND_LEASE_SECONDS = 60

-- Đọc island list từ API (thay thế readIslandSyncFile từ file)
function readIslandSyncFile()
    local result = apiGet("/v4info/island")
    if type(result) ~= "table" then return {} end
    -- Convert format API → format cũ { island: {count, users, lastUpdate} }
    local formatted = {}
    for island, data in pairs(result) do
        formatted[island] = {
            count      = tonumber(data.count) or 0,
            users      = data.users or {},
            lastUpdate = tick()
        }
    end
    return formatted
end

function writeIslandSyncFile(data)
    -- Server tự quản lý state — không cần ghi toàn bộ
end

function assignTrainingIsland()
    -- Assignment phải cố định cả lúc đang bay tới đảo. Nếu query lại khi còn ở xa,
    -- API đã tính chính account này ở đảo cũ và client sẽ đổi qua đảo trống khác.
    if myAssignedIsland and TrainingIslandData[myAssignedIsland] then
        return myAssignedIsland
    end

    -- Chỉ chọn mới khi chưa có assignment hoặc dữ liệu đảo không còn hợp lệ.
    local assignments = readIslandSyncFile()

    local bestIsland = nil
    local bestCount  = math.huge
    for _, islandName in ipairs(TrainingIslandOrder) do
        local entry = assignments[islandName] or { count = 0 }
        local count = entry.count or 0
        if count < MAX_ACCS_PER_ISLAND and count < bestCount then
            bestCount = count
            bestIsland = islandName
        end
    end
    if not bestIsland then
        for _, islandName in ipairs(TrainingIslandOrder) do
            local entry = assignments[islandName] or { count = 0 }
            local count = entry.count or 0
            if count < bestCount then
                bestCount = count
                bestIsland = islandName
            end
        end
    end

    bestIsland = bestIsland or TrainingIslandOrder[1]
    myAssignedIsland = bestIsland

    -- Đăng ký assignment với API
    apiPost("/v4info/island", { username = USERNAME, island = bestIsland })

    return bestIsland
end

function updateIslandHeartbeat()
    if not myAssignedIsland then return end
    apiPost("/v4info/island", { username = USERNAME, island = myAssignedIsland })
end

task.spawn(function()
    while task.wait(15) do
        pcall(updateIslandHeartbeat)
    end
end)

function countAccountsAtIsland(islandName)
    local data = TrainingIslandData[islandName]
    if not data then return 0 end
    local islandPos
    if data.Positions then
        islandPos = data.Positions[1].Position
    else
        islandPos = data.Position.Position
    end
    local count = 0
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= Players.LocalPlayer and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - islandPos).Magnitude < 1000 then
                count = count + 1
            end
        end
    end
    return count
end

local function findAliveTrainingMob(mobName)
    if type(mobName) ~= "string" then return nil end
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end
    local character = Players.LocalPlayer.Character
    local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
    local closestMob = nil
    local closestDistance = math.huge

    -- Chỉ lấy mob đang sống thật trong workspace; ReplicatedStorage chỉ là template.
    for _, mob in ipairs(enemies:GetChildren()) do
        if mob:IsA("Model") and mob.Name == mobName and mob.Name ~= "Blank Buddy" then
            local humanoid = mob:FindFirstChildWhichIsA("Humanoid")
            local root = mob:FindFirstChild("HumanoidRootPart")
            if humanoid and root and humanoid.Health > 0 then
                local distance = playerRoot and (root.Position - playerRoot.Position).Magnitude or 0
                if distance < closestDistance then
                    closestMob = mob
                    closestDistance = distance
                end
            end
        end
    end
    return closestMob
end

function CheckMonster(...)
    for _, mobName in ipairs({ ... }) do
        local mob = findAliveTrainingMob(mobName)
        if mob then return mob end
    end
    return false
end

function forceReassignIsland()
    myAssignedIsland = nil
end

function TyrTweenTo(targetCF, speed)
    if typeof(targetCF) ~= "CFrame" then return false end
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    local moveSpeed = math.max(tonumber(speed) or getgenv().TyrantConfig.TweenSpeed or FlightConfig.Speed, 1)
    local initialDistance = (root.Position - targetCF.Position).Magnitude
    local timeout = math.max(initialDistance / moveSpeed + 2, 10)
    local started = tick()

    repeat
        local ok = module:topos(targetCF, false, moveSpeed)
        if not ok then task.wait(0.1) else task.wait(0.05) end
        root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root then break end
        if (root.Position - targetCF.Position).Magnitude <= FlightConfig.SnapDistance + 2 then
            module:cancelTopos()
            root.CFrame = targetCF
            flightStopVelocity(root)
            return true
        end
    until tick() - started > timeout

    module:cancelTopos()
    return false
end

function TyrGetEnemyFolders()
    local folders = {}
    local enemies = Workspace:FindFirstChild("Enemies")
    if enemies then folders[#folders + 1] = enemies end
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    if origin and origin:FindFirstChild("Enemies") then folders[#folders + 1] = origin.Enemies end
    return folders
end

function TyrBaseEnemyName(name)
    local clean = tostring(name or "")
    clean = clean:gsub("%s*%[Lv%.%s*%d+%]", ""):gsub("%s*%[Lv%s*%d+%]", "")
    clean = clean:gsub("%s*%[Boss%]", ""):gsub("%s*%[Raid Boss%]", "")
    return clean:gsub("%s+$", "")
end

function TyrIsTikiMob(enemy)
    return enemy and TikiMobs[TyrBaseEnemyName(enemy.Name)] == true
end

function TyrIsTyrant(enemy)
    if not enemy then return false end
    return string.find(string.lower(enemy.Name), "tyrant", 1, true) ~= nil
end

function TyrFindTyrant()
    for _, folder in ipairs(TyrGetEnemyFolders()) do
        for _, enemy in ipairs(folder:GetChildren()) do
            local hum = enemy:FindFirstChildOfClass("Humanoid")
            local root = enemy:FindFirstChild("HumanoidRootPart")
            if hum and root and hum.Health > 0 and TyrIsTyrant(enemy) then return enemy end
        end
    end
    return nil
end

function TyrGetNearestTikiMob()
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, folder in ipairs(TyrGetEnemyFolders()) do
        for _, enemy in ipairs(folder:GetChildren()) do
            local hum = enemy:FindFirstChildOfClass("Humanoid")
            local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
            if hum and enemyRoot and hum.Health > 0 and TyrIsTikiMob(enemy) then
                local distance = (root.Position - enemyRoot.Position).Magnitude
                if distance < nearestDist then nearest = enemy; nearestDist = distance end
            end
        end
    end
    return nearest
end

function TyrFindTikiOutpost()
    local map = Workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("TikiOutpost")
end

function TyrIsEyeActive(eye)
    if not eye or not eye:IsA("BasePart") then return false end
    local color = eye.Color
    return eye.Transparency < 0.85 and color.R >= 0.75 and color.R > color.G * 1.35 and color.R > color.B * 1.20
end

function TyrAreTyrantEyesReady()
    local tiki = TyrFindTikiOutpost()
    if not tiki then return false end
    local islandModel = tiki:FindFirstChild("IslandModel")
    if not islandModel then return false end
    local eye1 = islandModel:FindFirstChild("Eye1", true)
    local eye2 = islandModel:FindFirstChild("Eye2", true)
    return TyrIsEyeActive(eye1) and TyrIsEyeActive(eye2)
end

function TyrGetObjectPart(object)
    if not object or not object.Parent then return nil end
    if object:IsA("BasePart") then return object end
    if object:IsA("Model") then
        return object.PrimaryPart or object:FindFirstChild("HumanoidRootPart")
            or object:FindFirstChild("Head") or object:FindFirstChildWhichIsA("BasePart", true)
    end
    return object:FindFirstChildWhichIsA("BasePart", true)
end

function TyrIsNearArena(object, radius)
    local part = TyrGetObjectPart(object)
    return part and (part.Position - ARENA_CENTER).Magnitude <= (radius or 240)
end

function TyrHasBreakableName(object)
    local name = string.lower(object.Name)
    return string.find(name, "vase", 1, true) or string.find(name, "pot", 1, true)
        or string.find(name, "jar", 1, true) or string.find(name, "urn", 1, true)
        or string.find(name, "breakable", 1, true) or string.find(name, "destructible", 1, true)
end

function TyrHasBreakableData(object)
    for _, attribute in ipairs({ "Health", "HP", "HitPoints", "Breakable", "Destructible" }) do
        if object:GetAttribute(attribute) ~= nil then return true end
    end
    local ok, tags = pcall(function() return CollectionService:GetTags(object) end)
    if ok then
        for _, tag in ipairs(tags) do
            local lowerTag = string.lower(tag)
            if string.find(lowerTag, "break", 1, true) or string.find(lowerTag, "destroy", 1, true)
                or string.find(lowerTag, "vase", 1, true) or string.find(lowerTag, "pot", 1, true) then
                return true
            end
        end
    end
    return false
end

function TyrIsArenaBreakable(object)
    if not object or not object.Parent or not TyrIsNearArena(object, 260) then return false end
    local lowerName = string.lower(object.Name)
    if lowerName == "tyrantentrance" or lowerName == "bossarena1" or lowerName == "bossarena2"
        or lowerName == "eye1" or lowerName == "eye2" then return false end
    return TyrHasBreakableName(object) or TyrHasBreakableData(object) or TyrState.TrackedBreakables[object] == true
end

function TyrGetArenaBreakables(forceRefresh)
    if not forceRefresh and tick() - TyrState.LastBreakableScan < 0.45 then
        local validCache = {}
        for _, data in ipairs(TyrState.CachedBreakables) do
            if data.Object and data.Object.Parent and data.Part and data.Part.Parent then
                validCache[#validCache + 1] = data
            end
        end
        TyrState.CachedBreakables = validCache
        return TyrState.CachedBreakables
    end
    TyrState.LastBreakableScan = tick()
    local results = {}
    local added = {}
    function AddCandidate(object)
        if object and not added[object] and TyrIsArenaBreakable(object) then
            local part = TyrGetObjectPart(object)
            if part then added[object] = true; results[#results + 1] = { Object = object, Part = part } end
        end
    end
    for object in pairs(TyrState.TrackedBreakables) do AddCandidate(object) end
    local tiki = TyrFindTikiOutpost()
    if tiki then
        for _, object in ipairs(tiki:GetDescendants()) do
            if object:IsA("Model") or object:IsA("BasePart") then AddCandidate(object) end
        end
    end
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    if origin then
        for _, object in ipairs(origin:GetDescendants()) do
            if object:IsA("Model") or object:IsA("BasePart") then
                if TyrIsNearArena(object, 260) then AddCandidate(object) end
            end
        end
    end
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if root then
        table.sort(results, function(a, b)
            return (a.Part.Position - root.Position).Magnitude < (b.Part.Position - root.Position).Magnitude
        end)
    end
    TyrState.CachedBreakables = results
    return TyrState.CachedBreakables
end

function TyrLoadAttack()
    if TyrState.AttackLoaded then return end
    TyrState.AttackLoaded = true
    -- Dùng chung SourceStyle AttackInstance; không tạo loop/remote mã hóa riêng.
    getgenv().TyrantFastAttack = function()
        return AttackInstance:Attack()
    end
end

function TyrNormalAttack(duration)
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local previousAutoClick = AttackConfig.AutoClickEnabled
    AttackConfig.AutoClickEnabled = true
    local started = tick()
    repeat
        pcall(function() AttackInstance:Attack() end)
        if TyrState.CurrentMode == "VASES" then
            local tool = char:FindFirstChildOfClass("Tool")
            pcall(function() sourceInputFallback(tool) end)
        end
        task.wait(0.06)
    until tick() - started >= (duration or 0.6) or TyrFindTyrant()
    AttackConfig.AutoClickEnabled = previousAutoClick
end

function TyrBuyDragonTalon()
    local char = LocalPlayer.Character
    if char and (char:FindFirstChild("Dragon Talon") or char:FindFirstChild("DragonTalon")) then return true end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp and (bp:FindFirstChild("Dragon Talon") or bp:FindFirstChild("DragonTalon")) then return true end
    if not getgenv().TyrantConfig.AutoBuyDragonTalon then return false end
    local commf = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
    if not commf then return false end
    status("Buying Dragon Talon")
    TyrTweenTo(DRAGON_TALON_BUY_POS, getgenv().TyrantConfig.TweenSpeed)
    task.wait(0.8)
    for _ = 1, 15 do
        pcall(function() commf:InvokeServer("BuyDragonTalon") end)
        task.wait(0.5)
        local c = LocalPlayer.Character
        local b = LocalPlayer:FindFirstChild("Backpack")
        if (c and (c:FindFirstChild("Dragon Talon") or c:FindFirstChild("DragonTalon")))
            or (b and (b:FindFirstChild("Dragon Talon") or b:FindFirstChild("DragonTalon"))) then
            return true
        end
    end
    return false
end

function TyrNormalizeName(name)
    return tostring(name or ""):gsub("%s+", ""):lower()
end

function TyrEnsureWeapon()
    local char = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local config = getgenv().TyrantConfig
    function findTool(toolName)
        if char then
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") and TyrNormalizeName(tool.Name) == TyrNormalizeName(toolName) then return tool end
            end
        end
        if bp then
            for _, tool in ipairs(bp:GetChildren()) do
                if tool:IsA("Tool") and TyrNormalizeName(tool.Name) == TyrNormalizeName(toolName) then return tool end
            end
        end
        return nil
    end
    local requested = findTool(config.Weapon)
    if requested then
        if requested.Parent ~= char then hum:EquipTool(requested); task.wait(0.15) end
        return findTool(config.Weapon)
    end
    if TyrNormalizeName(config.Weapon) == TyrNormalizeName("Dragon Talon") then TyrBuyDragonTalon() end
    local fallback = (char and char:FindFirstChildWhichIsA("Tool")) or (bp and bp:FindFirstChildWhichIsA("Tool"))
    if fallback and fallback.Parent ~= char then hum:EquipTool(fallback); task.wait(0.15) end
    return char and char:FindFirstChildWhichIsA("Tool")
end

function TyrFarmEnemy(enemy, isBoss)
    local hum = enemy and enemy:FindFirstChildOfClass("Humanoid")
    local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart")
    if not hum or not enemyRoot or hum.Health <= 0 then return end
    TyrState.CurrentTarget = enemy
    TyrState.CurrentMode = isBoss and "BOSS" or "MOBS"
    SourceCombatState.currentMob = enemy
    AttackConfig.AutoClickEnabled = true
    local config = getgenv().TyrantConfig
    local stuckAt = tick()
    local previousHealth = hum.Health
    while enemy.Parent and hum.Parent and enemyRoot.Parent and hum.Health > 0 do
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local playerHum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if not root or not playerHum or playerHum.Health <= 0 then break end
        TyrEnsureWeapon()
        sourceSizePart(enemy)
        if not isBoss then SourceBringMob(enemy) end
        local height = isBoss and config.BossHeight or config.FarmHeight
        local target = CFrame.new(enemyRoot.Position + Vector3.new(0, height, 0), enemyRoot.Position)
        module:topos(target, false, config.TweenSpeed)
        if hum.Health < previousHealth then previousHealth = hum.Health; stuckAt = tick()
        elseif tick() - stuckAt > 15 then
            module:topos(target, false, math.max(config.TweenSpeed * 1.5, FlightConfig.Speed))
            TyrNormalAttack(0.5)
            stuckAt = tick()
        end
        task.wait(0.05)
    end
    module:cancelTopos()
    if SourceCombatState.currentMob == enemy then SourceCombatState.currentMob = nil end
    AttackConfig.AutoClickEnabled = false
    TyrState.CurrentTarget = nil
end

function TyrBreakVases()
    TyrState.CurrentMode = "VASES"
    TyrState.CurrentTarget = nil
    status("Eyes red - breaking vases")
    TyrTweenTo(TYRANT_ENTRANCE, getgenv().TyrantConfig.TweenSpeed)
    task.wait(0.5)
    local round = 0
    while TyrAreTyrantEyesReady() and not TyrFindTyrant() do
        local breakables = TyrGetArenaBreakables()
        if #breakables > 0 then
            for _, data in ipairs(breakables) do
                if TyrFindTyrant() then return end
                if data.Part and data.Part.Parent then
                    local target = CFrame.new(data.Part.Position + Vector3.new(0, 6, 0), data.Part.Position)
                    TyrTweenTo(target, getgenv().TyrantConfig.TweenSpeed)
                    TyrNormalAttack(0.55)
                end
            end
        end
        round = round + 1
        local radius = 42
        local points = 12
        for index = 1, points do
            if TyrFindTyrant() then return end
            local angle = math.rad((index - 1) * (360 / points) + (round % 2) * 15)
            local point = ARENA_CENTER + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
            TyrTweenTo(CFrame.new(point + Vector3.new(0, 7, 0), ARENA_CENTER), getgenv().TyrantConfig.TweenSpeed)
            TyrNormalAttack(0.7)
        end
        TyrTweenTo(CFrame.new(ARENA_CENTER + Vector3.new(0, 8, 0)), getgenv().TyrantConfig.TweenSpeed)
        TyrNormalAttack(1)
        task.wait(0.8)
    end
end

function TyrSetupRegenTracker()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local regen = remotes and remotes:FindFirstChild("RegenModel")
    if not regen or not regen:IsA("RemoteEvent") then return end
    regen.OnClientEvent:Connect(function(encoded)
        local object = nil
        if typeof(encoded) == "Instance" then object = encoded
        elseif type(_G.Encode) == "function" then pcall(function() object = _G.Encode(encoded) end) end
        if object and typeof(object) == "Instance" and TyrIsNearArena(object, 280) then
            TyrState.TrackedBreakables[object] = true
        end
    end)
end

function TyrSetupBringMobs()
    -- SourceBringMob được gọi theo target trong TyrFarmEnemy; không tạo thêm
    -- Heartbeat kéo toàn bộ mob, không phá Animator và không dùng math.huge.
    AttackConfig.BringMobs = getgenv().Config["Bring Mobs"] ~= false
        and getgenv().TyrantConfig.BringMobs ~= false
end

local tyrantFarmingActive = false
local tyrantFarmingTask = nil
local tyrantSetupDone = false
local tyrantFragmentTarget = 10000

function stopTyrantFarming()
    tyrantFarmingActive = false
    TyrState.Farming = false
    tyrantFarmingTask = nil
    AttackConfig.AutoClickEnabled = false
    SourceCombatState.currentMob = nil
end

function startTyrantFarming(targetFragments)
    tyrantFragmentTarget = math.max(0, tonumber(targetFragments) or tyrantFragmentTarget or 10000)
    if tyrantFarmingTask then return end
    if not tyrantSetupDone then
        tyrantSetupDone = true
        TyrSetupRegenTracker()
        TyrSetupBringMobs()
        TyrLoadAttack()
        TyrBuyDragonTalon()
    end
    tyrantFarmingActive = true
    TyrState.Farming = true
    tyrantFarmingTask = task.spawn(function()
        while tyrantFarmingActive do
            local v4State = getV4Status(false)
            local frags = tonumber(LocalPlayer.Data.Fragments.Value) or 0
            if v4State.canTrial or v4State.complete or frags >= tyrantFragmentTarget then break end

            local config = getgenv().TyrantConfig
            if config.AutoBuso then
                local c = LocalPlayer.Character
                if c and not c:FindFirstChild("HasBuso") then
                    pcall(function() CommF_:InvokeServer("Buso") end)
                end
            end
            local playerHum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if not playerHum or playerHum.Health <= 0 then
                status("Respawning before fragment farm")
                task.wait(1)
            else
                local moonSuffix = (isnight() and isfullmoon()) and " | Full Moon" or ""
                local tyrant = TyrFindTyrant()
                if tyrant then
                    status("Fighting Tyrant for V4 fragments" .. moonSuffix)
                    TyrFarmEnemy(tyrant, true)
                elseif TyrAreTyrantEyesReady() then
                    status("Breaking vases for Tyrant" .. moonSuffix)
                    TyrBreakVases()
                else
                    TyrState.CurrentMode = "MOBS"
                    TyrState.CurrentTarget = nil
                    status("Farming V4 fragments " .. tostring(frags) .. "/" .. tostring(tyrantFragmentTarget) .. moonSuffix)
                    TyrEnsureWeapon()
                    local mob = TyrGetNearestTikiMob()
                    if mob then TyrFarmEnemy(mob, false)
                    else TyrTweenTo(TIKI_CENTER, config.TweenSpeed); task.wait(0.8) end
                end
            end
        end
        tyrantFarmingTask = nil
        tyrantFarmingActive = false
        TyrState.Farming = false
        invalidateV4Status()
    end)
end

function handleFragmentFarming(requiredFragments)
    local farmConfig = getgenv().Config["Farm Fragments"]
    if not farmConfig then return false end

    local state = getV4Status(false)
    if state.canTrial or state.complete then
        if tyrantFarmingActive then stopTyrantFarming() end
        return false
    end

    local target = math.max(0, tonumber(requiredFragments) or 10000)
    local frags = tonumber(LocalPlayer.Data.Fragments.Value) or 0
    if frags >= target then
        if tyrantFarmingActive then stopTyrantFarming() end
        return false
    end

    if type(farmConfig) == "table" and farmConfig.autotyrant then
        startTyrantFarming(target)
        return tyrantFarmingActive
    end
    return false
end

function buyPendingV4Upgrade(v4State, roleLabel)
    if not v4State or not v4State.needsPurchase then return false end
    roleLabel = tostring(roleLabel or "Account")
    local fragments = tonumber(LocalPlayer.Data.Fragments.Value) or 0
    local cost = tonumber(v4State.cost) or 0

    if cost > 0 and fragments < cost then
        if handleFragmentFarming(cost) then return true end
        status(roleLabel .. " needs " .. tostring(cost - fragments) .. " more fragments for V4")
        return true
    end

    if tyrantFarmingActive then stopTyrantFarming() end
    status(roleLabel .. " buying V4 upgrade")
    local wasPostGearPending = postGearWorkPending
    markPostGearWork("upgrade_race_buy")
    local ok, bought = pcall(function() return invokeUpgradeRace("Buy") end)
    invalidateV4Status()
    -- Giữ đúng hợp đồng cũ của UpgradeRace: chỉ coi là mua thành công khi
    -- remote trả giá trị truthy; nil/false phải mở khóa để vòng sau retry.
    local purchaseAccepted = ok and not not bought
    if purchaseAccepted then
        status(roleLabel .. " V4 upgrade purchased")
    else
        if not wasPostGearPending then clearPostGearWork() end
        status(roleLabel .. " V4 purchase failed - retrying")
    end
    task.wait(0.6)
    return true
end

-- V4 Awakening dùng phím Y. CommE/ActivateAbility là kỹ năng V3 nên tuyệt đối
-- không gọi ở luồng training. Nếu bảng Quest đang giữ Busy, chỉ nhả Busy trong
-- lúc gửi Y rồi khôi phục ngay để GUI vẫn giữ nguyên như game mặc định.
local lastRaceTransformAttempt = 0
local INITIAL_V4_QUEST_STATES = {
    v4_quest_not_started = true,
    v4_quest_begin = true,
    go_great_tree = true,
    continue_v4_quest = true,
    first_trial_preparation = true,
    starting_v4 = true,
}

local function tryActivateRaceTransformation()
    local character = Players.LocalPlayer.Character
    if not character then return false end

    local energy = character:FindFirstChild("RaceEnergy")
    local transformed = character:FindFirstChild("RaceTransformed")
    if not energy or energy.Value < 1 or not transformed or transformed.Value then
        return false
    end

    local now = tick()
    if now - lastRaceTransformAttempt < 0.25 then return false end
    lastRaceTransformAttempt = now

    local busy = character:FindFirstChild("Busy")
    local restoreBusy = busy ~= nil and busy.Value == true
    if restoreBusy then
        pcall(function() busy.Value = false end)
    end

    local keySent = pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Y, false, game)
        RunService.Heartbeat:Wait()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Y, false, game)
    end)

    if restoreBusy and busy and busy.Parent then
        pcall(function() busy.Value = true end)
    end
    return keySent
end

function runRaceTrainingWork(trainingState, roleLabel)
    roleLabel = tostring(roleLabel or "Account")
    local trainingCycleRequested = trainingState == "training" or type(trainingState) == "number"
    local character = Players.LocalPlayer.Character
    if not character then
        status(roleLabel .. " waiting character")
        task.wait(1)
        return false
    end

    local initialV4State = getV4Status(false)
    if initialV4State.complete then
        status(roleLabel .. " Race V4 completed")
        return true
    end
    if initialV4State.canTrial and not isAlly and not trainingCycleRequested then
        -- Helper luôn canTrial=true (faked), nên skip check này cho helper
        status(roleLabel .. " training complete - ready for trial")
        return true
    end
    if initialV4State.needsPurchase and not isAlly then
        buyPendingV4Upgrade(initialV4State, roleLabel)
        return false
    end

    -- Giữa các session, game có thể gỡ RaceTransformed dù UpgradeRace
    -- vẫn báo needsTraining. Trường hợp đó phải tiếp tục farm năng
    -- lượng, không được chạy lại quest/Teleport lên đỉnh Great Tree.
    if not character:FindFirstChild("RaceTransformed")
        and not initialV4State.needsTraining
        and not trainingCycleRequested then
        if INITIAL_V4_QUEST_STATES[initialV4State.key] then
            status(roleLabel .. " " .. tostring(initialV4State.label))
            talktoonggianaodo()
        else
            -- Trạng thái chuyển tiếp/check lỗi sau một lượt training chỉ được
            -- refresh; không bao giờ teleport tới NPC của nhiệm vụ mở V4.
            status(roleLabel .. " waiting V4 training state: " .. tostring(initialV4State.key))
            task.wait(0.4)
        end
        invalidateV4Status()
        return false
    end

    if tyrantFarmingActive then stopTyrantFarming() end

    -- Set flag: đang training → block hop trong main loop
    isCurrentlyTraining = true
    AttackConfig.AutoClickEnabled = false

    local fullMoonTraining = isnight() and isfullmoon()
    local remainingText = type(trainingState) == "number" and (" (" .. tostring(trainingState) .. " left)") or ""
    status(roleLabel .. (fullMoonTraining and " Full Moon - training" or " training") .. remainingText)

    local nextReadyCheck = 0
    local cycleFinished = false
    local function shouldStopTrainingCycle()
        if cycleFinished then return true end
        if tick() < nextReadyCheck then return false end
        nextReadyCheck = tick() + 0.8

        -- Helper: check RaceTransformed còn tồn tại không (= đang train)
        -- Không dùng canTrial vì helper luôn canTrial=true (faked)
        if isAlly then
            local char = Players.LocalPlayer.Character
            if not char or not char:FindFirstChild("RaceTransformed") then
                cycleFinished = true
                status(roleLabel .. " training session ended")
                return true
            end
            return false
        end

        local state = getV4Status(true)
        if state.complete then
            cycleFinished = true
            status(roleLabel .. " Race V4 completed")
            return true
        end
        if state.needsPurchase then
            cycleFinished = true
            status(roleLabel .. " training complete - V4 upgrade available")
            return true
        end
        -- Sau Trial đôi lúc server trả đồng thời canTrial=true cũ và
        -- needsTraining=true mới. Training phải được ưu tiên, nếu không luồng
        -- thoát sẽ tự hủy rồi nhánh Temple kéo nhân vật lên lại.
        if state.needsTraining then return false end
        if state.canTrial then
            cycleFinished = true
            status(roleLabel .. " training complete - ready for trial")
            return true
        end
        return false
    end

    pcall(tryActivateRaceTransformation)

    -- Sau Trial dùng TeleportBack do server xác nhận để xuống Great Tree ổn định.
    local routeReady, routeReason = useTrialExitRoute(roleLabel, shouldStopTrainingCycle)
    if not routeReady then
        if cycleFinished then
            AttackConfig.AutoClickEnabled = false
            invalidateV4Status()
            isCurrentlyTraining = false
            return true
        end
        status(roleLabel .. " Trial exit route retry: " .. tostring(routeReason))
        isCurrentlyTraining = false
        return false
    end

    -- Lấy island 1 lần, không re-query trong suốt cycle
    local islandName = assignTrainingIsland()
    if not islandName then
        -- Tất cả island bận hoặc API lỗi → reset flag và chờ vòng sau
        status(roleLabel .. " no island available - retry next cycle")
        isCurrentlyTraining = false
        return false
    end
    local islandData = TrainingIslandData[islandName]
    if not islandData then
        status(roleLabel .. " unknown island: " .. tostring(islandName) .. " - retry")
        forceReassignIsland()  -- xóa cache island sắt
        isCurrentlyTraining = false
        return false
    end
    local trainingPositions = nil
    if islandData.Positions then
        trainingPositions = islandData.Positions
    elseif islandData.Position then
        trainingPositions = { islandData.Position }
    else
        status("Island has no position data")
        isCurrentlyTraining = false
        return false
    end

    -- Đã xác nhận đúng trạng thái training và có đích farm hợp lệ. Từ đây cờ
    -- isCurrentlyTraining tự chặn Temple; có thể kết thúc khóa hậu mua gear.
    if postGearWorkPending then clearPostGearWork() end

    local currentPosIndex = 1
    local function getCurrentPos()
        return trainingPositions[currentPosIndex]
    end

    local function advancePosition()
        currentPosIndex = currentPosIndex + 1
        if currentPosIndex > #trainingPositions then currentPosIndex = 1 end
    end

    local ATTACK_RANGE = 15  -- khoảng cách đứng trên mob khi đánh
    local trainingPosition = getCurrentPos()
    local trainingTarget = trainingPosition * CFrame.new(0, ATTACK_RANGE, 0)
    if getdis(trainingTarget) >= 1500 then
        status(roleLabel .. " moving to [" .. tostring(islandName) .. "] for training")
        -- Giữ nguyên assignment và block cycle cho tới khi tới đúng đảo.
        -- Trả về giữa đường làm main loop gọi lại rồi đổi target liên tục.
        while getdis(trainingTarget) > FlightConfig.SnapDistance + 2 and not shouldStopTrainingCycle() do
            module:holdTopos(trainingTarget)
            task.wait(0.05)
        end
        if not cycleFinished then module:holdTopos(trainingTarget) end
    end

    local mobNames = {}
    for name in pairs(islandData.Mobs) do
        table.insert(mobNames, name)
    end
    table.sort(mobNames)

    -- Mỗi sweep khóa cứng một loại mob. Chỉ khi không còn instance sống nào
    -- của loại đó mới chuyển ngay sang loại/camp khác, không dùng timer 1.5s.
    local lockedMobName = nil
    local clearedThisSweep = {}
    local mobRoutes = type(islandData.MobRoutes) == "table" and islandData.MobRoutes or {}
    local lockedMobSeenAlive = false
    local lockedRouteIndex = 1
    local routeReachedAt = 0
    local ROUTE_STREAM_TIME = 0.35

    local function finishLockedMob()
        if lockedMobName then clearedThisSweep[lockedMobName] = true end
        lockedMobName = nil
        lockedMobSeenAlive = false
        lockedRouteIndex = 1
        routeReachedAt = 0
        SourceCombatState.currentMob = nil
        AttackConfig.AutoClickEnabled = false
        advancePosition()
    end

    local function chooseClosestUnlockedMob()
        local currentCharacter = Players.LocalPlayer.Character
        local playerRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
        local bestName = nil
        local bestMob = nil
        local bestDistance = math.huge

        for _, mobName in ipairs(mobNames) do
            if not clearedThisSweep[mobName] then
                local candidate = findAliveTrainingMob(mobName)
                local candidateRoot = candidate and candidate:FindFirstChild("HumanoidRootPart")
                if candidateRoot then
                    local distance = playerRoot and (candidateRoot.Position - playerRoot.Position).Magnitude or 0
                    if distance < bestDistance then
                        bestName = mobName
                        bestMob = candidate
                        bestDistance = distance
                    end
                end
            end
        end
        return bestName, bestMob
    end

    local function chooseUnclearedMobRoute()
        for _, mobName in ipairs(mobNames) do
            local routes = mobRoutes[mobName]
            if not clearedThisSweep[mobName] and type(routes) == "table" and #routes > 0 then
                return mobName
            end
        end
        return nil
    end

    local function chooseNextMobForSweep()
        local mobName, mob = chooseClosestUnlockedMob()
        if mob then return mobName, mob end

        local routeMobName = chooseUnclearedMobRoute()
        if routeMobName then return routeMobName, nil end

        -- Đã kiểm tra hết mob/camp trong sweep; mở sweep mới để nhận mob respawn.
        table.clear(clearedThisSweep)
        mobName, mob = chooseClosestUnlockedMob()
        if mob then return mobName, mob end
        return chooseUnclearedMobRoute(), nil
    end

    while not shouldStopTrainingCycle() do
        local mob = nil
        local navigatingRoute = false
        if lockedMobName then
            mob = findAliveTrainingMob(lockedMobName)
            if mob then
                lockedMobSeenAlive = true
                routeReachedAt = 0
            elseif lockedMobSeenAlive then
                -- Đã từng thấy/giết loại này và hiện không còn con nào
                -- sống trong workspace: chuyển loại ngay, không quét lại route.
                finishLockedMob()
            else
                -- Chỉ dùng route khi loại mob này chưa từng được stream.
                local routes = mobRoutes[lockedMobName]
                local route = type(routes) == "table" and routes[lockedRouteIndex] or nil
                if route then
                    navigatingRoute = true
                    local routeTarget = route * CFrame.new(0, ATTACK_RANGE, 0)
                    module:holdTopos(routeTarget)
                    status(roleLabel .. " [" .. tostring(islandName) .. "] loading " .. tostring(lockedMobName))

                    if getdis(routeTarget) <= FlightConfig.SnapDistance + 10 then
                        if routeReachedAt <= 0 then
                            routeReachedAt = tick()
                        elseif tick() - routeReachedAt >= ROUTE_STREAM_TIME then
                            mob = findAliveTrainingMob(lockedMobName)
                            if mob then
                                lockedMobSeenAlive = true
                                routeReachedAt = 0
                                navigatingRoute = false
                            else
                                lockedRouteIndex = lockedRouteIndex + 1
                                routeReachedAt = 0
                                if lockedRouteIndex > #routes then
                                    finishLockedMob()
                                    navigatingRoute = false
                                end
                            end
                        end
                    else
                        routeReachedAt = 0
                    end
                else
                    finishLockedMob()
                end
            end
        end

        if not lockedMobName then
            lockedMobName, mob = chooseNextMobForSweep()
            lockedMobSeenAlive = mob ~= nil
            lockedRouteIndex = 1
            routeReachedAt = 0
            local routes = lockedMobName and mobRoutes[lockedMobName] or nil
            navigatingRoute = not mob and type(routes) == "table" and #routes > 0
        end

        if navigatingRoute then
            SourceCombatState.currentMob = nil
            AttackConfig.AutoClickEnabled = false
            task.wait(0.05)
        elseif not mob then
            SourceCombatState.currentMob = nil
            AttackConfig.AutoClickEnabled = false
            status(roleLabel .. " [" .. tostring(islandName) .. "] waiting for mobs...")
            module:holdTopos(getCurrentPos() * CFrame.new(0, ATTACK_RANGE, 0))
            task.wait(0.35)
            advancePosition()
        else
            repeat
                task.wait()
                module:eq()
                module:haki()
                pcall(function()
                    SourceCombatState.currentMob = mob
                    sourceSizePart(mob)
                    SourceBringMob(mob)
                    AttackConfig.AutoClickEnabled = true
                    status(roleLabel .. " [" .. tostring(islandName) .. "] locked " .. tostring(lockedMobName) .. " + charge")
                    -- Farm mode giữ BodyVelocity/PlatformStand khi đã tới target.
                    local hrp = mob:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        module:holdTopos(hrp.CFrame * CFrame.new(0, ATTACK_RANGE, 0))
                    end
                    tryActivateRaceTransformation()
                end)
            until not checkmob_(mob) or shouldStopTrainingCycle()
            if SourceCombatState.currentMob == mob then SourceCombatState.currentMob = nil end
            AttackConfig.AutoClickEnabled = false
        end
    end

    AttackConfig.AutoClickEnabled = false
    invalidateV4Status()
    -- Giữ nguyên đảo đã được API phân cho toàn bộ phiên chạy. Xóa assignment
    -- ở đây khiến lần train kế tiếp tính chính acc này ở đảo cũ rồi chọn đảo
    -- trống khác, tạo hiện tượng bay qua lại giữa các đảo sau mỗi chu kỳ V4.
    isCurrentlyTraining = false
    return cycleFinished
end

function runWaitingAccountWork()
    local roleLabel = isUper and "Main" or "Help"
    local fullMoonNow = isnight() and isfullmoon()
    -- Luôn đọc fresh: sau invalidateV4Status(), cache đã clear → fetch mới từ server
    local v4State = getV4Status(postGearWorkPending)

    -- Sau khi remote mua/đổi gear thành công, không tin canTrial cũ của
    -- TempleClock. Riêng UpgradeRace("Buy") được mở khóa khi canTrial mới đã
    -- xuất hiện để Main có thể hop Full Moon. needsPurchase được phép retry
    -- sau một khoảng ngắn nếu lần mua chưa thật sự cập nhật.
    if postGearWorkPending then
        if v4State.complete then
            clearPostGearWork()
            if tyrantFarmingActive then stopTyrantFarming() end
            status("Race V4 completed after gear update")
            return
        elseif postGearReason == "upgrade_race_buy" and v4State.canTrial then
            -- UpgradeRace("Buy") là bước chuẩn bị cho Trial kế tiếp. Khi server
            -- đã trả canTrial, phải mở khóa ngay để dedicated hop task nhận
            -- JobId Full Moon từ API. Không áp dụng nhánh này cho TempleClock:
            -- trạng thái canTrial ở đó có thể là dữ liệu cũ trước khi gear đổi.
            clearPostGearWork()
            readySent = false
            status("V4 upgrade ready - waiting Full Moon server")
        elseif v4State.needsTraining then
            -- Đi tiếp xuống nhánh training bên dưới.
        elseif v4State.needsPurchase and tick() - postGearActionAt >= 2 then
            -- Server vẫn báo chưa mua: cho phép retry có kiểm soát.
        else
            readySent = false
            invalidateV4Status()
            status("Waiting V4 state after gear update: " .. tostring(postGearReason))
            task.wait(0.4)
            return
        end
    end

    -- FIX: ưu tiên training/needsPurchase TRƯỚC canTrial
    -- Tránh cache stale (canTrial=true cũ) chặn training loop
    if v4State.needsTraining or v4State.needsPurchase then
        if v4State.needsPurchase then
            buyPendingV4Upgrade(v4State, roleLabel)
            return
        end
        if tyrantFarmingActive then stopTyrantFarming() end
        local trainingState = v4State.remainingTraining or (v4State.needsTraining and "training" or v4State.key)
        local trainingDone = runRaceTrainingWork(trainingState, roleLabel)
        if trainingDone then invalidateV4Status() end
        return
    end

    if v4State.canTrial then
        if tyrantFarmingActive then stopTyrantFarming() end
        if fullMoonNow then
            status("Full Moon + trial-ready - waiting auto pair 1 Main + 2 Help")
        else
            status("Ready for trial - waiting Full Moon and auto pair")
        end
        return
    end

    if v4State.complete then
        if tyrantFarmingActive then stopTyrantFarming() end
        status("Race V4 completed - no more training needed")
        return
    end

    if tyrantFarmingActive then stopTyrantFarming() end
    local trainingState = v4State.remainingTraining or (v4State.needsTraining and "training" or v4State.key)
    local trainingDone = runRaceTrainingWork(trainingState, roleLabel)
    if trainingDone then
        invalidateV4Status()
    end
end

-- ══════════════════════════════════════════════════════════════
-- DEDICATED API SYNC LOOP — hoàn toàn độc lập với main loop
-- Đảm bảo account luôn live trên API mỗi 2s, kể cả khi:
--   • runRaceTrainingWork() đang block main loop hàng phút
--   • task.wait(5) của hop teleport
--   • bất kỳ task.wait() nào khác trong main loop
-- ══════════════════════════════════════════════════════════════
if isUper or isAlly then
    task.spawn(function()
        task.wait(1.5)  -- đợi script init xong hoàn toàn
        while true do
            -- Tốc độ sync: 0.5s khi đang FM hoặc Near FM → phản hồi nhanh
            -- 2s khi bình thường → tiết kiệm tài nguyên
            local _syncInterval = currentFullMoon and 0.5 or 2
            task.wait(_syncInterval)
            pcall(function()
                -- Cập nhật FM state trong sync loop
                local fmCheck = false
                pcall(function() fmCheck = isnight() and isfullmoon() end)
                if fmCheck ~= currentFullMoon then
                    currentFullMoon = fmCheck
                end
                local resp = sendSync(myGroupId == "")
                if resp then processSyncResponse(resp) end
            end)
        end
    end)
end

-- ════════════════════════════════════════════════════
-- MAIN HOP TASK: dùng matchState.main_job_id (sync từ API) làm nguồn chính
-- API processSyncResponse cập nhật main_job_id mỗi 0.5-2s
-- ════════════════════════════════════════════════════
if isUper and SCRIPT_MODE == 1 then
    task.spawn(function()
        task.wait(HOP_STARTUP_DELAY + 3)
        while true do
            task.wait(1)
            pcall(function()
                -- Chỉ hop khi training xong
                if isCurrentlyTraining or blockHopAfterTrial or postGearWorkPending then return end
                local v4s = nil
                pcall(function() v4s = getV4Status(false) end)
                if v4s and (v4s.needsTraining or v4s.needsPurchase) then return end

                -- Nguồn chính: matchState.main_job_id được sync từ API mỗi 0.5s
                local target = nil
                if matchState and matchState.main_job_id
                    and matchState.main_job_id ~= ""
                    and matchState.main_job_id ~= game.JobId then
                    target = matchState.main_job_id
                    status("📡 Main hop → FM " .. tostring(target):sub(1,8) .. " (API)")
                end

                if target then
                    task.wait(0.5)
                    pcall(function()
                        ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer("teleport", target)
                    end)
                    task.wait(8)
                end
            end)
        end
    end)
end

spawn(function()
    while task.wait(0.1) do
        if not isUper and not isAlly then
            status("Set Main or Help = true")
            task.wait(2)
            continue
        end

        local nowTick = tick()

        -- ════════════════════════════════════════════════════
        -- [1] FM DETECT → workspace + API tức thì (1 cục)
        -- Chạy trong main loop để đảm bảo detect ngay khi xảy ra
        -- ════════════════════════════════════════════════════
        local fmNow = false
        local isNightNow = false
        pcall(function()
            isNightNow = isnight()
            fmNow = isNightNow and isfullmoon()
        end)

        if fmNow ~= lastFmState then
            lastFmState = fmNow
            currentFullMoon = fmNow
            urgentSyncNeeded = true
            if not fmNow and SCRIPT_MODE == 2 then
                task.spawn(function()
                    local _exitTimeout = tick() + 180
                    while tick() < _exitTimeout do
                        local _inTrial = false
                        pcall(function() _inTrial = isInsideOwnTrial() end)
                        if not _inTrial and not isCurrentlyTraining then break end
                        task.wait(3)
                    end
                    status("⚠ Mode 2: FM kết thúc — rời server...")
                    task.wait(2)
                    pcall(function() TeleportService:Teleport(game.PlaceId) end)
                end)
            end
        else
            currentFullMoon = fmNow
        end

        -- ════════════════════════════════════════════════════
        -- [3] API SYNC — chỉ urgent sync tại đây (FM thay đổi tức thì)
        -- Normal sync 2s đã do dedicated loop ở trên xử lý
        -- ════════════════════════════════════════════════════
        if (isUper or isAlly) and urgentSyncNeeded then
            urgentSyncNeeded = false
            task.spawn(function()
                pcall(function()
                    local resp = sendSync(myGroupId == "")
                    if resp then processSyncResponse(resp) end
                end)
            end)
        end

        -- ════════════════════════════════════════════════════
        -- [2] V4 STATE + matchState.assigned (trực tiếp trong loop)
        -- ════════════════════════════════════════════════════
        if matchState then
            if myGroupId == "" and (isUper or isAlly) then initLocalGroup() end
            local v4s = nil
            pcall(function() v4s = getV4Status(false) end)
            local needsIndependentWork = postGearWorkPending
                or (v4s and (v4s.needsTraining or v4s.needsPurchase))
            if needsIndependentWork then
                matchState.assigned = false
            else
                matchState.assigned = (myGroupId ~= "")
            end
            matchState.group_id      = myGroupId
            matchState.main_username = myGroupMainUsername
            local list = {}
            for _, h in ipairs(myGroupHelpers) do table.insert(list, h) end
            matchState.helpers = list
        end

        -- ════════════════════════════════════════════════════
        -- [3] API SYNC — chỉ urgent sync tại đây (FM thay đổi tức thì)
        -- Normal sync mỗi 2s đã do dedicated loop ở trên xử lý
        -- ════════════════════════════════════════════════════
        if (isUper or isAlly) and urgentSyncNeeded then
            urgentSyncNeeded = false
            task.spawn(function()
                pcall(function()
                    local resp = sendSync(myGroupId == "")
                    if resp then processSyncResponse(resp) end
                end)
            end)
        end


        -- ════════════════════════════════════════════════════
        -- [4] HOP CHECK: FM_API → workspace → API backup
        -- Skip hop khi đang training/needsPurchase
        -- isCurrentlyTraining: flag từ runRaceTrainingWork (block cả helper)
        -- 6s timeout: join thất bại → cache jobId + tìm sv mới (3-7 player)
        -- 2min timeout: main không vào được sv helper → clear FM signal
        -- ════════════════════════════════════════════════════
        local v4sForHop = nil
        pcall(function() v4sForHop = getV4Status(false) end)
        -- isCurrentlyTraining bắt cả helper (helper có needsTraining=false vì faked)
        local skipHopForWork = isCurrentlyTraining
            or blockHopAfterTrial
            or postGearWorkPending
            or (v4sForHop and (v4sForHop.needsTraining or v4sForHop.needsPurchase))

        -- Mode 2: không hop (treo trong server chờ FM)
        if SCRIPT_MODE == 2 then skipHopForWork = true end

        if not skipHopForWork and nowTick - SCRIPT_START_AT > HOP_STARTUP_DELAY then
            local hopTarget = nil
            local canHopFM = checkCanHopFM()

            -- [4a] FM_API: chỉ HopFM whitelist account
            -- Đánh dấu cache khi đã vào đúng sv FM thành công
            if lastFmApiResult == game.JobId then
                markFMJoined(game.JobId)
                lastFmApiResult = nil
            end
            if not currentFullMoon and FM_API_BASE ~= "" and canHopFM
                and nowTick - SCRIPT_START_AT > FM_HOP_DELAY then
                if nowTick - lastFmApiAt >= FM_API_INTERVAL then
                    lastFmApiAt = nowTick
                    status("FM API: tìm server FM...")
                    task.spawn(function()
                        local found = findFMServer()
                        if found and found ~= game.JobId then
                            lastFmApiResult = found
                        else
                            lastFmApiResult = nil
                        end
                    end)
                end
                if lastFmApiResult and lastFmApiResult ~= game.JobId then
                    hopTarget = lastFmApiResult
                    status("FM API → hop " .. tostring(hopTarget):sub(1,8) .. "...")
                end
            end

            -- [4b] API matchState.main_job_id (sync từ processSyncResponse)
            if not hopTarget and matchState
                and matchState.main_job_id and matchState.main_job_id ~= ""
                and matchState.main_job_id ~= game.JobId then
                hopTarget = matchState.main_job_id
            end

            if hopTarget then
                if hopTarget ~= lastHopTarget then
                    -- Target mới: bắt đầu timer, teleport ngay
                    lastHopAt     = nowTick
                    lastHopTarget = hopTarget
                    status("Hopping → " .. tostring(hopTarget):sub(1, 8) .. "...")
                    pcall(function()
                        ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer("teleport", hopTarget)
                    end)
                    task.wait(5)
                    continue
                else
                    local elapsed = nowTick - lastHopAt
                    if elapsed >= 6 then
                        -- 6s: vẫn chưa vào được → cache jobId thất bại, refetch ngay
                        status("⏱ FM join timeout 6s → bỏ " .. tostring(hopTarget):sub(1,8) .. " + tìm sv mới")
                        markFMJoined(hopTarget)
                        lastFmApiResult = nil
                        lastFmApiAt     = 0
                        lastHopTarget   = ""
                        if elapsed >= 120 and not canHopFM then
                            if matchState then matchState.main_job_id = game.JobId end
                            status("⚠ 2min timeout - HopFM tìm server mới")
                        end
                    else
                        -- Retry teleport
                        status("Retry hop → " .. tostring(hopTarget):sub(1, 8) .. "...")
                        pcall(function()
                            ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer("teleport", hopTarget)
                        end)
                        task.wait(5)
                        continue
                    end
                end
            end
        end

        -- ════════════════════════════════════════════════════
        -- [5] TRAINING / TRIAL (dựa vào matchState.assigned từ [2])
        -- ════════════════════════════════════════════════════
        if not matchState or not matchState.assigned then
            -- pcall: tránh 1 lỗi nhỏ làm crash toàn bộ main loop
            local wok, werr = pcall(runWaitingAccountWork)
            if not wok then
                isCurrentlyTraining = false  -- safety reset
                status("⚠ training err: " .. tostring(werr):sub(1, 60))
                task.wait(1)
            end
            task.wait(0.2)
            continue
        end

        -- Một group có thể chứa nhiều Main nhưng chỉ mains[1] của API được
        -- dùng 2 Help ở vòng hiện tại. Main xếp hàng vẫn sync/hop cùng server,
        -- nhưng không được vào cửa hay tạo command V3 trước lượt.
        if isUper and not isMyUpgearTurn() then
            readySent = false
            status("Queued - waiting V4 turn behind " .. tostring(myGroupMainUsername))
            task.wait(0.5)
            continue
        end

        -- FIX: dùng fresh V4 check thay vì cache
        -- Tránh stale canTrial=true sau khi training reset
        local pairedV4State = getV4Status(false)
        -- Nếu cache có thể stale (canTrial=true nhưng needsTraining=true), force fresh
        if pairedV4State.canTrial and pairedV4State.needsTraining then
            invalidateV4Status()
            pairedV4State = getV4Status(true)
        end
        local pairedReady = pairedV4State.canTrial == true and not pairedV4State.needsTraining
        local pairedTrainingState = pairedV4State.remainingTraining
            or (pairedV4State.needsTraining and "training" or pairedV4State.key)

        if isUper and isMyUpgearTurn() then
            local trialOrTimerActive = isInsideOwnTrial()
            local ffaStarted = false
            pcall(function()
                ffaStarted = workspace.Map["Temple of Time"].FFABorder.Forcefield.Transparency == 0
            end)
            if trialOrTimerActive or ffaStarted then
                pairTrialCycleStarted = true
            end
        end

        if not pairedReady then
            pairTempleReadyAt = 0
            lastTempleReadyCount = 0
            local trialCycleConfirmed = pairTrialCycleStarted or pairV3ActivatedAt > 0 or handledRoundId ~= "" or isInsideOwnTrial()
            local postTrialWorkAvailable = pairedV4State.needsTraining == true or pairedV4State.needsPurchase == true
            if PAIR_RELEASE_AFTER_TRIAL and isUper and isMyUpgearTurn() and trialCycleConfirmed and postTrialWorkAvailable then
                pairTrialCycleStarted = true
                status("Trial completed - releasing pair for next Main")
                releaseCurrentGroup("trial_completed")
                task.wait(1)
                continue
            end

            if pairedV4State.complete then
                if tyrantFarmingActive then stopTyrantFarming() end
                status("Paired account has completed Race V4")
                if isUper and isMyUpgearTurn() then releaseCurrentGroup("race_v4_completed") end
                task.wait(1)
            elseif pairedV4State.needsPurchase then
                buyPendingV4Upgrade(pairedV4State, isUper and "Main" or "Help")
                task.wait(0.2)
            else
                if tyrantFarmingActive then stopTyrantFarming() end
                status("Paired but not trial-ready - continue training")
                -- pcall: tránh crash main loop khi training có lỗi
                local tok, terr = pcall(runRaceTrainingWork, pairedTrainingState, isUper and "Main" or "Help")
                if not tok then
                    isCurrentlyTraining = false
                    AttackConfig.AutoClickEnabled = false
                    SourceCombatState.currentMob = nil
                    status("⚠ pair train err: " .. tostring(terr):sub(1, 50))
                end
                task.wait(0.2)
            end
            continue
        end

        local fullMoonNow = isnight() and isfullmoon()
        if not fullMoonNow then
            pairTempleReadyAt = 0
            lastTempleReadyCount = 0
            -- FIX: dù pairedReady=true, nếu account vẫn cần training → training ngay
            -- Tránh stuck "waiting Full Moon" khi cache stale canTrial=true
            local freshV4 = getV4Status(true)  -- force fresh để không tin vào cache
            if freshV4.needsTraining or freshV4.needsPurchase then
                invalidateV4Status()       -- reset cache
                matchState.assigned = false  -- thoát paired mode, về runWaitingAccountWork
                runWaitingAccountWork()
                task.wait(0.2)
                continue
            end
            if PAIR_STICKY_UNTIL_TRIAL_COMPLETE then
                status("Trial-ready pair locked until this Trial is completed")
            elseif isUper and isMyUpgearTurn() and pairAssignedAt > 0 and tick() - pairAssignedAt > 8 then
                releaseCurrentGroup("full_moon_ended")
            else
                status("Trial-ready pair reserved - waiting Full Moon")
            end
            task.wait(1)
            continue
        end

        if tyrantFarmingActive then stopTyrantFarming() end

        if pairAllInJobAt > 0 and pairTempleReadyAt <= 0 then
            pairTempleReadyAt = tick()
            lastTempleReadyCount = 0
        end

        forceMatchedAccountToTemple()
        if isUper and isMyUpgearTurn() and pairTempleReadyAt > 0 then
            local timeoutAnchor = math.max(pairTempleReadyAt, lastTempleProgressAt or 0)
            if tick() - timeoutAnchor > PAIR_TEMPLE_TIMEOUT then
                local readyCount = 0
                pcall(function() readyCount = select(1, readReadyFiles()) end)

                if readyCount > lastTempleReadyCount then
                    lastTempleReadyCount = readyCount
                    pairTempleReadyAt = tick()
                elseif readyCount < 3 and not isInsideOwnTrial() then
                    if PAIR_STICKY_UNTIL_TRIAL_COMPLETE then
                        pairTempleReadyAt = tick()
                        lastTempleProgressAt = tick()
                        lastTempleDistance = math.huge
                        readySent = false
                        status("Temple ready timeout - keeping pair until Trial completes")
                    else
                        releaseCurrentGroup("temple_ready_timeout")
                        task.wait(1)
                        continue
                    end
                end
            end
        end

        local doorCallOk, doorResult = pcall(function()
            return ReplicatedStorage.Remotes.CommF_:InvokeServer("CheckTempleDoor")
        end)
        local checktempledoor = doorCallOk and doorResult == true
        if not checktempledoor then
            status(doorCallOk and "Temple door is not available yet" or "CheckTempleDoor remote failed")
            task.wait(0.5)
        else
            _G.ShouldSendData = false
            local ab, AB = trialable()
            if not ab then
                if AB == "raiding" then
                    local boss = workspace.Enemies:FindFirstChild("Cake Prince") 
                        or workspace.Enemies:FindFirstChild("Dough King")
                    if boss then
                        SourceCombatState.currentMob = boss
                        AttackConfig.AutoClickEnabled = true
                        repeat wait()
                            pcall(function() topos(boss.HumanoidRootPart.CFrame * CFrame.new(0, 25, 0)) end)
                            module:eq()
                            module:haki()
                        until not checkmob_(boss)
                        SourceCombatState.currentMob = nil
                        AttackConfig.AutoClickEnabled = false
                    end
                elseif AB == "training" or type(AB) == "number" then
                    -- Sau trial, needsTraining -> chạy training đúng island
                    status("Not trial-ready -> running training work")
                    runWaitingAccountWork()
                    task.wait(0.5)
                else
                    -- Các state khác (needsPurchase, v.v.)
                    runWaitingAccountWork()
                    task.wait(0.5)
                end
            end
            _G.ShouldSendData = true
            if not workspace.Map:FindFirstChild("Temple of Time") then
                local templeRef = ReplicatedStorage.MapStash:FindFirstChild("Temple of Time")
                if templeRef then templeRef.Parent = workspace.Map end
            elseif workspace.Map["Temple of Time"].FFABorder.Forcefield.Transparency == 0 then
                if isMain then
                    status("Killing players after trial...")
                    module:eqMelee()
                    module:haki()
                    AttackConfig.AttackPlayers = true
                    AttackConfig.AutoClickEnabled = true
                    for plr, i in pairs(getplayers(true)) do
                        if plr then
                            SourceCombatState.currentMob = plr
                            repeat
                                task.wait()
                                module:eqMelee()
                                module:haki()
                                pcall(function()
                                    topos(plr.HumanoidRootPart.CFrame * CFrame.new((function()
                                        local x, y, z = 0, 3, 0
                                        x = math.random(1, 4); z = math.random(1, 4)
                                        if math.random(1, 2) == 1 then x = x * -1 end
                                        if math.random(1, 2) == 1 then z = z * -1 end
                                        return x, y, z
                                    end)()))
                                end)
                            until not plr or not plr.Parent or not plr:FindFirstChild("Humanoid")
                                or not plr:FindFirstChild("HumanoidRootPart") or plr.Humanoid.Health <= 0
                                or workspace.Map["Temple of Time"].FFABorder.Forcefield.Transparency == 1
                        end
                    end
                    SourceCombatState.currentMob = nil
                    AttackConfig.AutoClickEnabled = false
                    AttackConfig.AttackPlayers = false
                -- Main (isUper and isMyUpgearTurn()) KHÔNG BAO GIỜ tự reset
                -- character trong lúc trial đang chạy, bất kể vai trò cũ
                -- của API trả về đúng/sai. Chỉ Help (Ally hoặc Helper không
                -- phải lượt) mới reset để dọn đường cho Main.
                elseif isUper and isMyUpgearTurn() then
                    status("Main is in trial - never auto-reset")
                elseif isAlly then
                    status("Resetting after trial...")
                    Players.LocalPlayer.Character.Humanoid.Health = 0
                elseif isUper and not isMyUpgearTurn() then
                    status("Helper - resetting after trial...")
                    Players.LocalPlayer.Character.Humanoid.Health = 0
                end
            else
                local race_trial_place
                if races_trial_place[Players.LocalPlayer.Data.Race.Value] then
                    race_trial_place = races_trial_place[Players.LocalPlayer.Data.Race.Value]
                end
                if race_trial_place and getdis(race_trial_place.CFrame) < 1500 then
                    status("Doing trial")
                    local myrace = Players.LocalPlayer.Data.Race.Value
                    if myrace == "Mink" then
                        topos(workspace.Map.MinkTrial.Ceiling.CFrame * CFrame.new(0, -20, 0))
                    elseif myrace == "Skypiea" then
                        pcall(function() topos(workspace.Map.SkyTrial.Model.FinishPart.CFrame) end)
                    elseif myrace == "Cyborg" then
                        pcall(function() topos(workspace.Map.CyborgTrial.Floor.CFrame * CFrame.new(0, 500, 0)) end)
                    elseif myrace == "Human" or myrace == "Ghoul" then
                        for i, v in pairs(workspace.Enemies:GetChildren()) do
                            if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                                if getdis(v.HumanoidRootPart.CFrame, race_trial_place.CFrame) < 1500 then
                                    SourceCombatState.currentMob = v
                                    AttackConfig.AutoClickEnabled = true
                                    repeat
                                        task.wait(); module:eq(); module:haki()
                                        pcall(function() topos(v:FindFirstChild("HumanoidRootPart").CFrame * CFrame.new(0, 30, 0)) end)
                                    until not v or not v:FindFirstChild("HumanoidRootPart") or not v:FindFirstChild("Humanoid") or v.Humanoid.Health <= 0
                                    SourceCombatState.currentMob = nil
                                    AttackConfig.AutoClickEnabled = false
                                end
                            end
                        end
                    elseif myrace == "Fishman" then
                        for i, v in pairs(workspace.SeaBeasts:GetChildren()) do
                            pcall(function()
                                if v:FindFirstChild("Health") and v.Health.Value > 0 and v:FindFirstChild("HumanoidRootPart") and getdis(v.HumanoidRootPart.CFrame, race_trial_place) < 1500 then
                                    repeat
                                        task.wait()
                                        if not Players.LocalPlayer.Backpack:FindFirstChild("Sharkman Karate") then
                                            ReplicatedStorage.Remotes.CommF_:InvokeServer("BuySharkmanKarate")
                                        end
                                        topos(v.HumanoidRootPart.CFrame * CFrame.new(0, 500, 0))
                                        _G.SHOULDSPAMSKILLS = true
                                    until not v or not v:FindFirstChild("Health") or v.Health.Value <= 0 or not v:FindFirstChild("HumanoidRootPart")
                                    _G.SHOULDSPAMSKILLS = false
                                end
                            end)
                        end
                    end
                else
                    if Players.LocalPlayer.PlayerGui.Main.Timer.Visible == false then
                        local khang = nil
                        local timeout = 0
                        repeat
                            task.wait(); khang = getdoor(); timeout = timeout + 1
                            if timeout > 300 then break end
                        until khang ~= nil
                        if khang and getdis(khang.CFrame) < 1500 then
                            module:holdTopos(khang.CFrame)
                            status("At door - waiting")
                            if trialable() then
                                if isUper then
                                    if isMyUpgearTurn() then
                                        readySent = true
                                        status("Ready trials")
                                    else
                                        readySent = false
                                        status("waiting my turn")
                                        task.wait(1)
                                    end
                                elseif isAlly then
                                    readySent = true
                                    status("Helper ready")
                                end
                            else
                                if isUper and not isMyUpgearTurn() then
                                    status("waiting turn")
                                    task.wait(1)
                                end
                            end
                        else
                            ReplicatedStorage.Remotes.CommF_:InvokeServer("requestEntrance", Vector3.new(28310.0234, 14895.1123, 109.456741))
                        end
                    end
                end
            end

            if tryActivateAbility() then task.wait(0.2) end
        end
    end
end)

local fruits = {
    ["Buddha-Buddha"] = true, ["T-Rex-T-Rex"] = true, ["Dragon-Dragon"] = true, ["Yeti-Yeti"] = true,
    ["Leopard-Leopard"] = true, ["Venom-Venom"] = true, ["Phoenix-Phoenix"] = true, ["Kitsune-Kitsune"] = true,
    ["Mammoth-Mammoth"] = true, ["Gas-Gas"] = true, ["Portal-Portal"] = true
}
local isvalidtooltip = { ["Melee"] = true, ["Blox Fruit"] = true, ["Sword"] = true, ["Gun"] = true }
local isvalidnameui = { ["Z"] = true, ["X"] = true, ["C"] = true, ["V"] = true, ["F"] = true }

function getallweapon()
    local weapon = {}
    for i, v in pairs(Players.LocalPlayer.Backpack:GetChildren()) do
        if v:IsA("Tool") and isvalidtooltip[v.ToolTip] then table.insert(weapon, v) end
    end
    for i, v in pairs(Players.LocalPlayer.Character:GetChildren()) do
        if v:IsA("Tool") and isvalidtooltip[v.ToolTip] then table.insert(weapon, v) end
    end
    return weapon
end

function EquipTool(v)
    local thua = Players.LocalPlayer.Backpack:FindFirstChild(v)
    if thua then Players.LocalPlayer.Character.Humanoid:EquipTool(thua) end
end

_G.SHOULDSPAMSKILLS = false

spawn(function()
    while task.wait(0.1) do
        if _G.SHOULDSPAMSKILLS then
            local weapon = getallweapon()
            for i, v in pairs(weapon) do
                if not Players.LocalPlayer.PlayerGui.Main.Skills:FindFirstChild(v.Name) then EquipTool(v.Name) end
            end
            for i, v in pairs(weapon) do
                if v.Parent ~= Players.LocalPlayer.Character then EquipTool(v.Name) end
                local ui = Players.LocalPlayer.PlayerGui.Main.Skills:FindFirstChild(v.Name)
                if ui then
                    for _, vl in pairs(ui:GetChildren()) do
                        if isvalidnameui[vl.Name] then
                            local cooldown_frame = vl:WaitForChild("Cooldown")
                            local title_frame = vl:WaitForChild("Title")
                            if title_frame.TextColor3 == Color3.new(1, 1, 1) or title_frame.TextColor3 == Color3.fromRGB(255, 255, 255) then
                                if cooldown_frame.Size == UDim2.new(0, 0, 1, -1) then
                                    if vl.Name == "V" then
                                        if not fruits[ui.Name] then
                                            game:service("VirtualInputManager"):SendKeyEvent(true, "V", false, game)
                                            task.wait(0.1)
                                            game:service("VirtualInputManager"):SendKeyEvent(false, "V", false, game)
                                            task.wait(1.5)
                                        end
                                    else
                                        game:service("VirtualInputManager"):SendKeyEvent(true, vl.Name, false, game)
                                        task.wait(0.1)
                                        game:service("VirtualInputManager"):SendKeyEvent(false, vl.Name, false, game)
                                        task.wait(1.5)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

local Ec = Players.LocalPlayer
function Bc(x)
    if not x then return false end
    local L = x:FindFirstChild("Humanoid")
    return L and L["Health"] > 0
end
function Pc(x, L)
    local V = Players:GetPlayers()
    local H = {}
    local r = (x:GetPivot())["Position"]
    local leader = Players:FindFirstChild(mainAccountName)
    for _, a in ipairs(V) do
        if a ~= Ec and a ~= leader and a["Character"] and noideaforname(a) then
            local xp = a["Character"]:FindFirstChild("HumanoidRootPart")
            if xp and Bc(a["Character"]) then
                if (xp["Position"] - r)["Magnitude"] <= L then table["insert"](H, a["Character"]) end
            end
        end
    end
    for _, a in ipairs(workspace["Enemies"]:GetChildren()) do
        local xp = a:FindFirstChild("HumanoidRootPart")
        if a ~= leader and xp and Bc(a) then
            if (xp["Position"] - r)["Magnitude"] <= L then table["insert"](H, a) end
        end
    end
    return H
end

function hopRandom()
    local ServerBrowser = ReplicatedStorage:WaitForChild("__ServerBrowser")
    for i = 1, 100 do
        local ok, servers = pcall(function() return ServerBrowser:InvokeServer(i) end)
        if ok and servers then
            for jobId, info in pairs(servers) do
                if jobId ~= game.JobId and (info.Count or 0) < 12 then
                    pcall(function() ServerBrowser:InvokeServer("teleport", jobId) end)
                    task.wait(0.3)
                    return true
                end
            end
        end
    end
    return false
end

local trialDoneHandled = false
local postTrialHopDone = false  -- *** THÊM FLAG NÀY ***

spawn(function()
    while task.wait(1) do
        if not isUper then
            trialDoneHandled = false
            postTrialHopDone = false
            continue
        end

        local v4state = nil
        pcall(function() v4state = getV4Status(false) end)
        if not v4state then continue end
        local trialJustDone = v4state.needsTraining == true or v4state.needsPurchase == true

        if trialJustDone and not trialDoneHandled and not postTrialHopDone then
            trialDoneHandled = true
            postTrialHopDone = true  -- *** LOCK, không hop nữa trong session này ***

            if v4state.needsTraining then
                status("Trial xong -> can training -> UpdateRoles + hop farm mob")
            elseif v4state.needsPurchase then
                status("Trial xong -> can mua upgrade -> UpdateRoles + hop")
            end

            if getgenv().UpdateRoles then
                pcall(getgenv().UpdateRoles)
            end

            -- Invalidate cache ngay để 2s loop đọc trạng thái mới nhất từ server
            invalidateV4Status()

            matchState.assigned = false
            matchState.group_id = ""
            releaseCurrentGroup("trial_done")

            -- Block hop NGAY trước khi chờ, tránh main loop hop trong 10s này
            blockHopAfterTrial = true

            -- Chờ 10s rồi hop random sang server khác
            status("Trial xong - chờ 10s rồi hop random...")
            task.wait(10)
            invalidateV4Status()

            -- Đọc lại trạng thái sau 10s. Nếu vẫn còn việc hậu Trial/gear thì
            -- ở lại server để train/retry, không hop random giữa chừng.
            local freshPostTrial = nil
            pcall(function() freshPostTrial = getV4Status(true) end)
            local mustStayForPostTrialWork = postGearWorkPending
                or (freshPostTrial and (freshPostTrial.needsTraining or freshPostTrial.needsPurchase))

            if mustStayForPostTrialWork or isCurrentlyTraining then
                blockHopAfterTrial = false
                status("Trial xong - ưu tiên xử lý training/gear, không hop")
            else
                pcall(function()
                    writefile("piggyv4_trial_hop.txt", "true")
                end)
                status("Trial xong -> đang hop random...")
                pcall(hopRandom)
            end
        end

        -- *** CHỈ reset trialDoneHandled, KHÔNG reset postTrialHopDone ***
        -- postTrialHopDone chỉ reset khi v4 complete hoặc canTrial lại
        if not trialJustDone and v4state.complete ~= true then
            trialDoneHandled = false
            -- postTrialHopDone GIỮ NGUYÊN để không hop lại
        end

        -- Reset hoàn toàn khi v4 complete hoặc canTrial (vòng mới)
        if v4state.complete or v4state.canTrial then
            trialDoneHandled = false
            postTrialHopDone = false
        end
    end
end)
_G[Players.LocalPlayer.Name] = true
getgenv().UseSeaUi = true

function createUI()
    local UserInputService = game:GetService("UserInputService")
    
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "KaitunPiggyUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = CoreGui

    -- Main Panel
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(0, 460, 0, 220)
    Frame.Position = UDim2.new(0.5, -230, 0, 10)
    Frame.BackgroundColor3 = Color3.fromRGB(25, 18, 22)
    Frame.BackgroundTransparency = 0.25
    Frame.BorderSizePixel = 0
    Frame.Parent = ScreenGui

    -- UI Corner
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 10)
    Corner.Parent = Frame

    -- UI Stroke (Viền màu hồng neon)
    local Stroke = Instance.new("UIStroke")
    Stroke.Color = Color3.fromRGB(255, 105, 180) -- Hot Pink
    Stroke.Thickness = 2
    Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    Stroke.Parent = Frame

    -- Title
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 30)
    Title.Position = UDim2.new(0, 0, 0, 5)
    Title.BackgroundTransparency = 1
    Title.Text = "Kaitun Piggy V4"
    Title.TextColor3 = Color3.fromRGB(255, 120, 190)
    Title.TextSize = 16
    Title.Font = Enum.Font.Arcade
    Title.Parent = Frame

    -- Grid / List container
    local Container = Instance.new("Frame")
    Container.Size = UDim2.new(0.92, 0, 0.82, 0)
    Container.Position = UDim2.new(0.04, 0, 0.16, 0)
    Container.BackgroundTransparency = 1
    Container.Parent = Frame

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 3)
    layout.Parent = Container

    -- Các dòng label
    local function createLabel(name, defaultVal, order)
        local Line = Instance.new("Frame")
        Line.Size = UDim2.new(1, 0, 0, 18)
        Line.BackgroundTransparency = 1
        Line.LayoutOrder = order
        Line.Parent = Container

        local Label = Instance.new("TextLabel")
        Label.Size = UDim2.new(0.2, 0, 1, 0)
        Label.BackgroundTransparency = 1
        Label.Text = name
        Label.TextColor3 = Color3.fromRGB(240, 200, 210)
        Label.TextSize = 13
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.TextYAlignment = Enum.TextYAlignment.Top
        Label.Font = Enum.Font.Arcade
        Label.Parent = Line

        local Val = Instance.new("TextLabel")
        Val.Size = UDim2.new(0.8, 0, 1, 0)
        Val.Position = UDim2.new(0.2, 0, 0, 0)
        Val.BackgroundTransparency = 1
        Val.Text = defaultVal
        Val.TextColor3 = Color3.fromRGB(255, 255, 255)
        Val.TextSize = 13
        Val.TextXAlignment = Enum.TextXAlignment.Left
        Val.TextYAlignment = Enum.TextYAlignment.Top
        Val.TextWrapped = true
        Val.Font = Enum.Font.Arcade
        Val.Parent = Line

        return Val
    end

    local PlayerVal   = createLabel("Player :", "Loading...", 1)
    local RoleVal     = createLabel("Role :", "Loading...", 2)
    local RaceVal     = createLabel("Race :", "Loading...", 3)
    local FragVal     = createLabel("Frag :", "0", 4)
    local PairVal     = createLabel("Pair :", "WAITING", 5)
    local MoonVal     = createLabel("Moon :", "NO FULL MOON", 6)
    local V4Val       = createLabel("V4 :", "Checking...", 7)
    local StatusVal   = createLabel("Status :", "Loading...", 8)
    local ServerVal   = createLabel("Server :", "0/12", 9)

    -- Đổi màu giá trị cho đồng điệu màu hồng
    PlayerVal.TextColor3 = Color3.fromRGB(255, 180, 200)
    RoleVal.TextColor3 = Color3.fromRGB(255, 105, 180)
    RaceVal.TextColor3 = Color3.fromRGB(255, 180, 200)
    FragVal.TextColor3 = Color3.fromRGB(255, 220, 100)
    PairVal.TextColor3 = Color3.fromRGB(255, 105, 180)
    MoonVal.TextColor3 = Color3.fromRGB(255, 180, 200)
    V4Val.TextColor3 = Color3.fromRGB(255, 180, 200)
    StatusVal.TextColor3 = Color3.fromRGB(255, 255, 255)
    ServerVal.TextColor3 = Color3.fromRGB(255, 180, 200)

    -- Cho phép drag thả UI
    local dragging, dragInput, dragStart, startPos
    Frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Frame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    Frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            Frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    return ScreenGui, StatusVal, PlayerVal, RoleVal, RaceVal, FragVal, PairVal, MoonVal, V4Val, ServerVal
end

local UI, StatusVal, PlayerVal, RoleVal, RaceVal, FragVal, PairVal, MoonVal, V4Val, ServerVal = createUI()
getgenv().__KaitunV4Singleton.state = "running"
getgenv().__KaitunV4Singleton.ui = UI

function status(text)
    currentTaskStatus = tostring(text or "idle")
    if StatusVal then StatusVal.Text = currentTaskStatus end
end

status("idle")

function formatNumber(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    while true do
        local replaced, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        text = replaced
        if count == 0 then break end
    end
    return text
end

function formatV4Info(v4State)
    v4State = v4State or { label = "UNKNOWN", energy = 0, transformed = false }
    local energyPercent = math.floor(math.clamp(tonumber(v4State.energy) or 0, 0, 1) * 100 + 0.5)
    local transformText = v4State.transformed and "ON" or "OFF"
    local detail = ""

    if v4State.needsPurchase then
        detail = " | Cost: " .. formatNumber(v4State.cost) .. " F"
    elseif v4State.code == 6 then
        detail = " | Sessions: " .. tostring(v4State.completedTraining or 0) .. "/3"
    elseif v4State.code == 8 then
        detail = " | Remaining: " .. tostring(v4State.remainingTraining or 0)
    elseif v4State.canTrial and v4State.gear ~= nil then
        detail = " | Gear: " .. tostring(v4State.gear)
    elseif v4State.code ~= nil then
        detail = " | State: " .. tostring(v4State.code)
    elseif v4State.progress ~= nil then
        detail = " | Quest: " .. tostring(v4State.progress)
    end

    return tostring(v4State.label or "UNKNOWN")
        .. detail
        .. " | Energy: " .. tostring(energyPercent) .. "%"
        .. " | Transform: " .. transformText
end

function getV4StatusColor(v4State)
    if v4State and v4State.complete then return Color3.fromRGB(90, 220, 255) end
    if v4State and v4State.canTrial then return Color3.fromRGB(90, 255, 130) end
    if v4State and v4State.needsPurchase then return Color3.fromRGB(255, 170, 70) end
    if v4State and v4State.needsTraining then return Color3.fromRGB(255, 220, 90) end
    return Color3.fromRGB(255, 255, 255)
end

task.spawn(function()
    while task.wait(0.5) do
        local fragments = 0
        local race = "Unknown"
        pcall(function()
            fragments = Players.LocalPlayer.Data.Fragments.Value
            race = Players.LocalPlayer.Data.Race.Value
        end)
        local roleText = isUper and "MAIN" or (isAlly and "HELP" or "NONE")
        local pairText = matchState and matchState.assigned and "PAIRED" or "WAITING"
        local moonText = (isnight() and isfullmoon()) and "FULL MOON" or "NO FULL MOON"
        local v4State = getV4Status(false)
        
        if PlayerVal then PlayerVal.Text = USERNAME end
        if RoleVal then RoleVal.Text = roleText end
        if RaceVal then RaceVal.Text = tostring(race) end
        if FragVal then FragVal.Text = formatNumber(fragments) end
        if PairVal then PairVal.Text = pairText end
        if MoonVal then MoonVal.Text = moonText end
        if V4Val then
            V4Val.Text = formatV4Info(v4State)
            V4Val.TextColor3 = getV4StatusColor(v4State)
        end
        if ServerVal then
            ServerVal.Text = tostring(#Players:GetPlayers()) .. "/12"
        end
    end
end)

-- RaidScan for WoW 1.12.1
-- Simple channel scanner for raid announcements
-- SavedVariables: RaidScanDB

local ADDON = "RaidScan"
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_CHANNEL")

-- default DB
local defaults = {
    enabled = true,
    keywords = {
        "raid", "lfm", "lf", "lfg", "szukam", "poszukujemy", "poszukuje", "boost", "pug",
        "lf1m","lf2m","lf3m","lf4m","need", "looking", "grp", "group"
    },
    channels = { -- names (case-insensitive fragments) to monitor; empty = auto-detect "world"
        -- by default empty: we detect typical localized names
    },
    recent = {}, -- optional: last matches (in-session)
    cooldown = 5, -- seconds per author to avoid repeating
}

-- runtime table to prevent spam per author
local lastSeen = {}

-- ensure DB
if not RaidScanDB then RaidScanDB = {} end
for k,v in pairs(defaults) do
    if RaidScanDB[k] == nil then RaidScanDB[k] = v end
end

-- utility lowercase
local function lc(s) if not s then return "" end return string.lower(s) end

-- check if channel should be monitored
local function channelMatches(channelName)
    if not channelName then return false end
    local c = lc(channelName)
    -- common localized names to detect "world" channels
    if c:find("world") or c:find("świat") or c:find("swiat") or c:find("ogólny") or c:find("ogolny") then
        return true
    end
    -- custom configured fragments
    for _,frag in ipairs(RaidScanDB.channels) do
        if frag and frag ~= "" and c:find(lc(frag)) then
            return true
        end
    end
    -- if user explicitly added no channels, still accept common ones only
    return false
end

-- check keywords
local function messageHasKeyword(msg)
    if not msg then return false end
    local m = lc(msg)
    for _,kw in ipairs(RaidScanDB.keywords) do
        if kw and kw ~= "" then
            local pattern = "%f[%w]" .. lc(kw) .. "%f[%W]" -- word boundary-like
            -- fallback simple find if pattern fails
            if m:find(pattern) or m:find(lc(kw), 1, true) then
                return true
            end
        end
    end
    return false
end

-- add entry to in-session recent log (keep last 200)
local function logMatch(time, channel, author, msg)
    table.insert(RaidScanDB.recent, 1, {time=time, channel=channel, author=author, msg=msg})
    if #RaidScanDB.recent > 200 then
        for i=201, #RaidScanDB.recent do RaidScanDB.recent[i] = nil end
    end
end

-- show to default chat frame
local function notify(author, channel, msg)
    local text = string.format("|cff00ff00[%s]|r |cffffff00%s|r: %s", ADDON, author or "?", msg or "")
    DEFAULT_CHAT_FRAME:AddMessage(text)
end

-- Event handler
frame:SetScript("OnEvent", function(self, event, ...)
    if not RaidScanDB.enabled then return end
    if event == "CHAT_MSG_CHANNEL" then
        local msg, author, _, channelString, _, _, _, channelName = ...
        -- channelName sometimes nil in older clients; attempt to extract from channelString
        if not channelName and channelString then
            channelName = channelString
        end
        if not channelMatches(channelName) then return end
        if not messageHasKeyword(msg) then return end

        -- cooldown per author
        local now = time()
        local authorKey = author or "?"
        if lastSeen[authorKey] and (now - lastSeen[authorKey]) < RaidScanDB.cooldown then
            return
        end
        lastSeen[authorKey] = now

        -- record and notify
        logMatch(now, channelName, author, msg)
        notify(author, channelName, msg)
    end
end)

-- Slash commands
SLASH_RAIDSCAN1 = "/raidscan"
SLASH_RAIDSCAN2 = "/rs"

local function showHelp()
    print("|cff00ff00RaidScan|r komendy:")
    print("/raidscan on - włącz skaner")
    print("/raidscan off - wyłącz skaner")
    print("/raidscan keywords - pokaż aktualne słowa kluczowe")
    print("/raidscan addkw <słowo> - dodaj słowo kluczowe")
    print("/raidscan delkw <słowo> - usuń słowo kluczowe")
    print("/raidscan channels - pokaż nasłuchiwane fragmenty nazw kanałów")
    print("/raidscan addch <fragment> - nasłuchuj kanału zawierającego ten fragment")
    print("/raidscan delch <fragment> - usuń fragment kanału")
    print("/raidscan recent - pokaż ostatnie dopasowania (w sesji)")
    print("/raidscan clear - wyczyść zapis recent")
    print("/raidscan cooldown <s> - ustaw cooldown (sekundy) na autora")
end

local function splitFirst(arg)
    if not arg or arg == "" then return nil end
    local a,b = arg:match("^(%S+)%s*(.*)$")
    return a,b
end

SlashCmdList["RAIDSCAN"] = function(msg)
    local cmd, rest = splitFirst(msg)
    if not cmd or cmd == "" then showHelp(); return end
    cmd = lc(cmd)

    if cmd == "on" then
        RaidScanDB.enabled = true
        print("RaidScan włączony.")
    elseif cmd == "off" then
        RaidScanDB.enabled = false
        print("RaidScan wyłączony.")
    elseif cmd == "keywords" then
        print("Aktualne słowa kluczowe:")
        for i,kw in ipairs(RaidScanDB.keywords) do print(i..". "..kw) end
    elseif cmd == "addkw" and rest and rest ~= "" then
        table.insert(RaidScanDB.keywords, rest)
        print("Dodano słowo kluczowe: "..rest)
    elseif cmd == "delkw" and rest and rest ~= "" then
        local found=false
        for i,kw in ipairs(RaidScanDB.keywords) do
            if lc(kw) == lc(rest) then
                table.remove(RaidScanDB.keywords, i)
                print("Usunięto słowo kluczowe: "..rest)
                found=true
                break
            end
        end
        if not found then print("Nie znaleziono takiego słowa kluczowego.") end
    elseif cmd == "channels" then
        print("Nasłuchiwane fragmenty nazw kanałów:")
        if #RaidScanDB.channels == 0 then print("(domyślne: automatyczna detekcja kanału światowego)") end
        for i,v in ipairs(RaidScanDB.channels) do print(i..". "..v) end
    elseif cmd == "addch" and rest and rest ~= "" then
        table.insert(RaidScanDB.channels, rest)
        print("Dodano fragment kanału: "..rest)
    elseif cmd == "delch" and rest and rest ~= "" then
        local found=false
        for i,v in ipairs(RaidScanDB.channels) do
            if lc(v) == lc(rest) then
                table.remove(RaidScanDB.channels, i)
                print("Usunięto fragment kanału: "..rest)
                found=true
                break
            end
        end
        if not found then print("Nie znaleziono takiego fragmentu.") end
    elseif cmd == "recent" then
        if #RaidScanDB.recent == 0 then print("Brak dopasowań w tej sesji.") return end
        print("Ostatnie dopasowania:")
        for i,entry in ipairs(RaidScanDB.recent) do
            local t = date("%H:%M:%S", entry.time or time())
            print(string.format("[%s] %s @%s: %s", t, entry.channel or "?", entry.author or "?", entry.msg or ""))
            if i >= 30 then break end
        end
    elseif cmd == "clear" then
        RaidScanDB.recent = {}
        print("Wyczyszczono log recent.")
    elseif cmd == "cooldown" and rest and tonumber(rest) then
        local v = tonumber(rest)
        RaidScanDB.cooldown = v
        print("Ustawiono cooldown na autora: "..v.."s")
    else
        showHelp()
    end
end

-- On load message
print("|cff00ff00RaidScan|r załadowany. Użyj /raidscan by skonfigurować.")

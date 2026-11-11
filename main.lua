-- Automation plugin: scripts that find and press buttons on the screen, and force stop an
-- app and retry when something gets stuck.
--
-- The Play Store's button texts change between versions and languages, so they live in
-- the settings: when a version changes them, fix them in Settings without touching the
-- code. Several candidates can be written in one field, separated by "|"; whichever is on
-- the screen gets pressed. To learn the right text, focus the button and listen.
--
-- The texts are written in English and translated with _() from the files in languages/
-- (tr.json for Turkish); setting labels and script descriptions are translated by DuyGör
-- itself. The button texts in the settings are not translated: they follow the language
-- of the app on the screen, not the plugin's. Script ids and setting names stay as they
-- were, so gestures and saved settings keep working after an update.

local PLAY = "com.android.vending"
local STEP_WAIT = 10000   -- how long to wait for each button (ms)

settings.define({
  { name = "profil", label = "Step 1: profile button", type = "text",
    default = "Hesap ve ayarlar|Hesap|Account and settings" },
  { name = "yonet", label = "Step 2: manage apps", type = "text",
    default = "Uygulamaları ve cihazı yönet|Uygulamaları ve cihazı yönetin|Manage apps & device|Manage apps and device" },
  { name = "denetle", label = "Step 3: check for updates", type = "text",
    default = "Güncellemeleri kontrol et|Güncellemeleri denetle|Güncellemeleri kontrol edin|Check for updates" },
  { name = "ayrinti", label = "Button that opens the list of updates", type = "text",
    default = "Ayrıntıları göster|Ayrıntıları görün|Güncellemeler mevcut|See details|Updates available" },
  { name = "hepsi", label = "Update all button", type = "text",
    default = "Tümünü güncelle|Update all" },
  { name = "otomatik", label = "If there are updates, also press Update all", type = "check", default = false },
  { name = "yanitla", label = "Answer button in the notification of apps like WhatsApp",
    type = "text", default = "Yanıtla|Cevapla|Answer" },
})

-- "a|b|c" -> { "a", "b", "c" }
local function candidates(settingName)
  local list = {}
  for part in (settings.get(settingName) or ""):gmatch("[^|]+") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then list[#list + 1] = part end
  end
  return list
end

-- Looks for whichever candidate appears on the screen first, for up to ms.
local function findAny(settingName, ms)
  local list = candidates(settingName)
  local start = os.time()
  repeat
    for i, text in ipairs(list) do
      local node = find(text)
      if node then return node, text end
    end
    wait(400)
  until os.time() - start >= ms / 1000
  return nil
end

local function clickAny(settingName, ms)
  local node, text = findAny(settingName, ms)
  if node and node:click() then
    log("clicked", settingName, text)
    return true
  end
  log("not found", settingName)
  return false
end

local function playInFront(ms)
  local start = os.time()
  repeat
    if app.front() == PLAY then return true end
    wait(300)
  until os.time() - start >= ms / 1000
  return false
end

-- One attempt: Play is open, go through the steps. True if the updates page opened.
local function openUpdatesPage()
  if not playInFront(10000) then return false end
  if not clickAny("profil", STEP_WAIT) then return false end
  if not clickAny("yonet", STEP_WAIT) then return false end
  -- This page has either "Check for updates" or, if updates were already found,
  -- "See details" straight away.
  if not findAny("ayrinti", 2000) and not clickAny("denetle", STEP_WAIT) then
    return false
  end
  return true
end

local function announceResult()
  local details = findAny("ayrinti", 8000)
  if not details then
    speak(_("Updates checked. No pending updates."))
    return
  end
  details:click()
  local updateAll = findAny("hepsi", 5000)
  if updateAll and settings.get("otomatik") then
    updateAll:click()
    speak(_("Updates started."))
  else
    speak(_("There are updates. The list is open."))
  end
end

script("playGuncelle", "Check Play Store updates", function()
  for attempt = 1, 2 do
    if attempt == 2 then
      speak(_("The updates page did not open. Force stopping and reopening the Play Store."))
      if not app.forceStop(PLAY) then
        log("could not force stop Play, reopening anyway")
      end
      wait(1000)
    else
      speak(_("Opening the Play Store."))
    end
    if not app.open(PLAY) then
      playSound("error")
      speak(_("Could not open the Play Store."))
      return
    end
    if openUpdatesPage() then
      announceResult()
      return
    end
  end
  playSound("error")
  speak(_("The updates page did not open in two attempts. Check the button texts in the plugin's settings."))
end, { timeout = 150 })

script("playKapat", "Force stop the Play Store", function()
  if app.forceStop(PLAY) then
    speak(_("The Play Store was stopped."))
  else
    speak(_("Could not stop the Play Store."))
  end
end, { timeout = 30 })

-- If a call is ringing (a phone call, or an app call such as WhatsApp), the screen
-- reader's own Magic tap action is used: it answers a SIM call through Android, an app
-- call through the answer button on the screen, and asks for permission if needed.
-- If nothing seems to ring, the answer button in the notification is tried.
local function ringing()
  local ok1, phone = pcall(function() return context:getSystemService("phone"):getCallState() end)
  local ok2, audio = pcall(function() return context:getSystemService("audio"):getMode() end)
  return (ok1 and phone == 1)    -- TelephonyManager.CALL_STATE_RINGING
      or (ok2 and audio == 1)    -- AudioManager.MODE_RINGTONE (app calls too)
end

script("cagriYanitla", "Answer the incoming call", function()
  if ringing() then
    action("MEDIA_CALL")
    return
  end
  system.notifications()
  local node = findAny("yanitla", 3000)
  if node and node:click() then return end
  system.back()
  speak(_("No call to answer."))
end, { timeout = 20 })

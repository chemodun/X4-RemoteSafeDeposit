-- Remote Safe Deposit - optional hotkeys and their switches on hotkey_api's Hotkey Management page.
-- Without hotkey_api, Register_Request never fires and nothing here runs.

---@diagnostic disable-next-line: unresolved-require
local ffi = require("ffi")
local C   = ffi.C
ffi.cdef [[
  typedef uint64_t UniverseID;
  UniverseID GetPlayerID(void);
  void SaveUIUserData(void);
]]

local PAGE             = 1972092449
-- Must not match any page name gameoptions' submenuHandler resolves before its optionDefinitions fallback.
local SETTINGS_PAGE_ID = "rsd_hotkey_settings"
local NAV_ROW_ID       = "rsd_hotkey_settings_nav"

-- MD (Hotkey_Safe_Deposit, Hotkey_Pilot_Inventory) does the range check and opens the menu.
local HOTKEYS = {
  { option = "hqHotkeyEnabled",    id = "remotesafedeposit_hq",    control = "hotkey_hq",    label = 500, name = function() return ReadText(1010, 50) end },
  { option = "pilotHotkeyEnabled", id = "remotesafedeposit_pilot", control = "hotkey_pilot", label = 501, name = function() return ReadText(PAGE, 101) end },
}

local optionsHooked = false

local function debugEnabled()
  local config = GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "$RemoteSafeDepositConfig")
  return (type(config) == "table") and (config.debugLevel == "debug" or config.debugLevel == "trace")
end

-- Lua Log API is optional: without it the Lua side stays silent.
local function Debug(message, ...)
  if UIDebug and debugEnabled() then
    UIDebug("RemoteSafeDeposit: " .. string.format(message, ...))
  end
end

-- The savedvariable is declared in ui.xml; read it at use time, never cache it.
local function getOption(id)
  return (RemoteSafeDeposit_Options ~= nil) and (RemoteSafeDeposit_Options[id] == true)
end

local function setOption(id, value)
  ---@diagnostic disable-next-line: global-in-non-module
  RemoteSafeDeposit_Options = RemoteSafeDeposit_Options or {}
  RemoteSafeDeposit_Options[id] = value
end

local function fire(hotkey, params)
  local object = params and params.object
  Debug("hotkey %s fired, object %s", hotkey.id, tostring(object))
  if object then
    AddUITriggeredEvent("RemoteSafeDeposit", hotkey.control, ConvertStringToLuaID(tostring(object)))
  else
    AddUITriggeredEvent("RemoteSafeDeposit", hotkey.control)
  end
end

local function settingsPage()
  local page = { name = function() return ReadText(PAGE, 1) end }
  for _, hotkey in ipairs(HOTKEYS) do
    table.insert(page, {
      id        = "rsd_" .. hotkey.option,
      name      = function() return ReadText(PAGE, hotkey.label) end,
      value     = function() return getOption(hotkey.option) and ReadText(1001, 4825) or ReadText(1001, 8942) end,
      valuetype = "button",
      callback  = function()
        local enabled = not getOption(hotkey.option)
        setOption(hotkey.option, enabled)
        C.SaveUIUserData()
        Debug("%s set to %s", hotkey.option, tostring(enabled))
        -- Every slot goes unconfirmed and hotkey_api frees the ones nobody registers again.
        HotkeyApi.BroadcastReloaded()
      end,
    })
  end
  return page
end

-- HotkeyApi.OnDisplayOptions first: the callback list runs in pairs() order. It is idempotent.
local function onDisplayOptions(options, config)
  if not (HotkeyApi and HotkeyApi.OnDisplayOptions and HotkeyApi.managementPageId) then
    return options
  end
  options = HotkeyApi.OnDisplayOptions(options, config)

  local definitions = config and config.optionDefinitions
  local page        = definitions and definitions[HotkeyApi.managementPageId]
  if not page then
    return options
  end

  -- Before the nav row, or a click on it does nothing.
  if not definitions[SETTINGS_PAGE_ID] then
    definitions[SETTINGS_PAGE_ID] = settingsPage()
  end

  for _, row in ipairs(page) do
    if (type(row) == "table") and (row.id == NAV_ROW_ID) then
      return options
    end
  end

  table.insert(page, { id = "line" })
  -- No callback: onSelectElement tests it before submenu.
  table.insert(page, { id = NAV_ROW_ID, name = function() return ReadText(PAGE, 1) end, submenu = SETTINGS_PAGE_ID })
  Debug("settings row added to the Hotkey Management page")
  return options
end

local function hookOptions()
  if optionsHooked then
    return
  end
  local optionsMenu = Helper.getMenu("OptionsMenu")
  if not (optionsMenu and (type(optionsMenu.registerCallback) == "function")) then
    Debug("OptionsMenu unavailable")
    return
  end
  optionsMenu.registerCallback("displayOptions_modifyOptions", onDisplayOptions)
  optionsHooked = true
end

local function onRegisterRequest()
  if not (HotkeyApi and HotkeyApi.RegisterAction) then
    return
  end
  hookOptions()

  for _, hotkey in ipairs(HOTKEYS) do
    if getOption(hotkey.option) then
      HotkeyApi.RegisterAction({
        id               = hotkey.id,
        area             = "map;pilot;fps",
        isObjectRequired = false,
        name             = hotkey.name(),
        version          = 1,
        actionLua        = function(params) fire(hotkey, params) end,
      })
      Debug("%s registered", hotkey.id)
    else
      Debug("%s disabled, not registered", hotkey.id)
    end
  end
end

-- File scope: the loader's inits have no fixed order against hotkey_api's first request.
RegisterEvent("HotkeyApi.Register_Request", onRegisterRequest)

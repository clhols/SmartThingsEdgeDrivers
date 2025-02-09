-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local WindowCovering = zcl_clusters.WindowCovering
local windowShadeDefaults = require "st.zigbee.defaults.windowShade_defaults"

local device_management = require "st.zigbee.device_management"

local LEVEL_UPDATE_TIMEOUT = "__level_update_timeout"

local YOOLAX_WINDOW_SHADE_FINGERPRINTS = {
    { mfr = "Yookee", model = "D10110" },                                 -- Yookee Window Treatment
    { mfr = "yooksmart", model = "D10110" }                               -- yooksmart Window Treatment
}

local function is_yoolax_window_shade(opts, driver, device)
  for _, fingerprint in ipairs(YOOLAX_WINDOW_SHADE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function set_shade_level(driver, device, value, command)
  local level = 100 - value
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
  local timer = device.thread:call_with_delay(30, function ()
    -- for some reason the device isn't updating us about its state so we'll send another bind request
    device:send(device_management.build_bind_request(device, WindowCovering.ID, driver.environment_info.hub_zigbee_eui))
    device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:configure_reporting(device, 0, 600, 1))
    device:send_to_component(command.component, WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
    device:set_field(LEVEL_UPDATE_TIMEOUT, nil)
  end)
  device:set_field(LEVEL_UPDATE_TIMEOUT, timer)
end

local function window_shade_level_cmd(driver, device, command)
  set_shade_level(driver, device, command.value, command)
end

local function window_shade_preset_cmd(driver, device, command)
  set_shade_level(driver, device, device.preferences.presetPosition, command)
end

local function set_window_shade_level(level)
  return function(driver, device, cmd)
    set_shade_level(driver, device, level, cmd)
  end
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  local timer = device:get_field(LEVEL_UPDATE_TIMEOUT)
  if timer then
    device.thread:cancel_timer(timer)
    device:set_field(LEVEL_UPDATE_TIMEOUT, nil)
  end
  windowShadeDefaults.default_current_lift_percentage_handler(driver, device, {value = 100 - value.value}, zb_rx)
end

local yoolax_window_shade = {
  NAME = "yoolax window shade",
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd,
      [capabilities.windowShade.commands.open.NAME] = set_window_shade_level(100),
      [capabilities.windowShade.commands.close.NAME] = set_window_shade_level(0),
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_preset_cmd
    }
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      }
    }
  },
  can_handle = is_yoolax_window_shade
}

return yoolax_window_shade

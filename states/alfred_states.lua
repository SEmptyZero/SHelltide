local settings      = require 'core.settings'
local tracker       = require "core.tracker"

local plugin_label = "s_helltide"

local alfred_states = {}

alfred_states.ALFRED_TRIGGERED = {
    enter = function(sm)
        console.print("ALFRED: ALFRED_TRIGGERED")
        if settings.salvage and PLUGIN_alfred_the_butler then
            PLUGIN_alfred_the_butler.resume()
            PLUGIN_alfred_the_butler.trigger_tasks_with_teleport(plugin_label, function()
                if sm:get_previous_state() == "WAIT_AFTER_MAIDEN" then
                    sm:change_state("WAIT_AFTER_MAIDEN")
                else
                    sm:change_state("EXPLORE_HELLTIDE")
                end
            end)
        end
    end,
    execute = function(sm)
    end,
}

return alfred_states

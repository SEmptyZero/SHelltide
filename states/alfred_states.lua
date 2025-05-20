local settings      = require 'core.settings'
local tracker       = require "core.tracker"
local explorerlite  = require "core.explorerlite"

local plugin_label = "s_helltide"

local alfred_states = {}

alfred_states.ALFRED_TRIGGERED = {
    enter = function(sm)
        console.print("ALFRED: ALFRED_TRIGGERED")
        explorerlite.toggle_anti_stuck = false
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
    exit = function(sm)
        explorerlite.toggle_anti_stuck = true
    end,
}

return alfred_states

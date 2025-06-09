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

            if sm:get_previous_state() == "OBOLS_IN_CERRIGAR" then
                PLUGIN_alfred_the_butler.trigger_tasks(plugin_label, function()
                    sm:change_state("OBOLS_IN_CERRIGAR")
                end)
            else
                PLUGIN_alfred_the_butler.trigger_tasks_with_teleport(plugin_label, function()
                    if sm:get_previous_state() == "WAIT_AFTER_MAIDEN" then
                        sm:change_state("WAIT_AFTER_MAIDEN")
                    else
                        sm:change_state("EXPLORE_HELLTIDE")
                    end
                end)
            end
        end
    end,
    exit = function(sm)
        explorerlite.toggle_anti_stuck = true
    end,
}

alfred_states.TEST_STATE = {
    enter = function(sm)
        console.print("ALFRED: TEST_STATE")
        explorerlite.toggle_anti_stuck = false
    end,
    execute = function(sm)

        on_key_press(function(key)
            if key == 0x20 then -- Use 0x20 for spacebar
                explorerlite:clear_path_and_target()
                local cursor_pos = get_cursor_position()
                local a = utility.set_height_of_valid_position(cursor_pos)
                explorerlite:set_custom_target(a)
            end

            if key == 0x56 then -- Use 0x21 for left arrow key
                explorerlite:clear_path_and_target()
                local vec = vec3:new(216.226562, -601.409180, 6.959961)
                local a = utility.set_height_of_valid_position(vec)
                explorerlite:set_custom_target(a)
            end
        end)

        explorerlite:move_to_target()
    end,
    exit = function(sm)
    end,
}

return alfred_states

local utils          = require "core.utils"
local tracker        = require "core.tracker"
local explorerlite   = require "core.explorerlite"
local enums          = require "data.enums"
local gui            = require "gui"

local chests_states = {}

chests_states.NEW_CHEST_FOUND = {
    enter = function(sm)
        console.print("HELLTIDE: NEW_CHEST_FOUND")
        local current_chest = tracker.current_chest

        if not utils.is_chest_already_tracked(current_chest, tracker) then
            local found_pos = current_chest:get_position()
            local found_name = current_chest:get_skin_name()
            table.insert(tracker.chests_found, { target = current_chest, name = found_name, position = found_pos, price = enums.helltide_chests_info[found_name], time = get_time_since_inject() })
        end

        local current_cinders = get_helltide_coin_cinders()
        if current_cinders >= utils.get_chest_cost(current_chest:get_skin_name()) then
            sm:change_state("MOVING_TO_CHEST")
            return
        end
        
        tracker.current_chest = nil
        sm:change_state("EXPLORE_HELLTIDE")
    end,
}

chests_states.ALREADY_CHEST_FOUND = {
    enter = function(sm)
        console.print("HELLTIDE: ALREADY_CHEST_FOUND")
        local current_chest = tracker.current_chest

        local current_chest_pos = current_chest:get_position()
        local chest_tracked = utils.get_chest_tracked(current_chest_pos, tracker)
        if chest_tracked then
            local price = chest_tracked.price
            local current_cinders = get_helltide_coin_cinders()
            if current_cinders >= price then
                sm:change_state("MOVING_TO_CHEST")
                return
            end
        end
        
        
        tracker.current_chest = nil
        sm:change_state("EXPLORE_HELLTIDE")
    end,
}

local current_helltide_chest_pos = nil
chests_states.MOVING_TO_CHEST = {
    enter = function(sm)
        console.print("HELLTIDE: MOVING_TO_CHEST")
        explorerlite.is_task_running = false
        if tracker.navigate_to_waypoint_chest then
            current_helltide_chest_pos = tracker.navigate_to_waypoint_chest
        else
            current_helltide_chest_pos = tracker.current_chest:get_position()
        end
        explorerlite:clear_path_and_target()
    end,
    execute = function(sm)

        if not utils.is_in_helltide() then
            sm:change_state("RETURN_CITY")
            return
        end
        
        local nearby_enemies = utils.find_enemies_in_radius_with_z(current_helltide_chest_pos, 15, 2)
        if #nearby_enemies > 1 and utils.distance_to(current_helltide_chest_pos) < 15 then
            orbwalker.set_clear_toggle(true)
            local pos_first_enemy = nearby_enemies[1]:get_position()
            if utils.distance_to(nearby_enemies[1]) > 10 then
                explorerlite:set_custom_target(pos_first_enemy)
                explorerlite:move_to_target()
            else
                if tracker.check_time("random_circle_delay_helltide", 1.3) and pos_first_enemy then
                    local new_pos = utils.get_random_point_circle(pos_first_enemy, 9, 1.2)
                    explorerlite:set_custom_target(new_pos)
                    if explorerlite:is_custom_target_valid() then
                        tracker.clear_key("random_circle_delay_helltide")
                    end
                end
                
                if explorerlite:is_custom_target_valid() then
                    explorerlite:move_to_target()
                end
            end
        else
            orbwalker.set_clear_toggle(false)
            if current_helltide_chest_pos then
                if utils.distance_to_ignore_z(current_helltide_chest_pos) > 1.9 or utils.distance_to(current_helltide_chest_pos) > 1.9 then
                    explorerlite:set_custom_target(current_helltide_chest_pos)
                    explorerlite:move_to_target()
                else
                    sm:change_state("INTERACT_CHEST")
                end
            end
        end
    end,
    exit = function(sm)
    end,
}
local current_chest_pos = nil
chests_states.MOVING_TO_SILENT_CHEST = {
    enter = function(sm)
        console.print("HELLTIDE: MOVING_TO_SILENT_CHEST")
        explorerlite.is_task_running = false
        current_chest_pos = tracker.current_chest:get_position()
    end,
    execute = function(sm)

        if not utils.is_in_helltide() then
            sm:change_state("RETURN_CITY")
            return
        end

        if current_chest_pos then
            if utils.distance_to_ignore_z(current_chest_pos) > 1.9 or utils.distance_to(current_chest_pos) > 1.9 then
                explorerlite:set_custom_target(current_chest_pos)
                explorerlite:move_to_target()
            else
                sm:change_state("INTERACT_CHEST")
            end
        end
    end,
    exit = function(sm)
    end,
}

local current_chest_interactable = nil
chests_states.INTERACT_CHEST = {
    enter = function(sm)
        explorerlite.is_task_running = true
        console.print("HELLTIDE: INTERACT_CHEST")
        current_chest_interactable = utils.find_target_by_position(tracker.navigate_to_waypoint_chest)
        if current_chest_interactable then
            tracker.current_chest = current_chest_interactable
            tracker.navigate_to_waypoint_chest = nil
        else
            current_chest_interactable = tracker.current_chest
        end
    end,
    execute = function(sm)
        if current_chest_interactable then
            local success = interact_object(current_chest_interactable)
            if success then
                if not current_chest_interactable:is_interactable() then
                    sm:change_state("WAIT_AFTER_INTERECTION")
                end
            end
        end
    end,
}

chests_states.WAIT_AFTER_INTERECTION = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: WAIT_AFTER_INTERECTION")
        tracker.clear_key("helltide_wait_after_interaction")
    end,
    execute = function(sm)
        if LooteerPlugin.getSettings("looting") then
            tracker.clear_key("helltide_wait_after_interaction")
        end

        if not tracker.check_time("helltide_move_around_delay", 0.9) and current_chest_interactable then
            local new_pos = utils.get_random_point_circle(current_chest_interactable:get_position(), 4, 1.2)
            explorerlite:set_custom_target(new_pos)
            if explorerlite:is_custom_target_valid() then
                explorerlite:move_to_target()
                tracker.clear_key("helltide_move_around_delay")
            end
        end
        
        if tracker.check_time("helltide_wait_after_interaction", 3) then
            tracker.clear_key("helltide_wait_after_interaction")

            if tracker.current_chest:is_interactable() then
                sm:change_state("MOVING_TO_CHEST")
                return
            end

            if gui.elements.return_to_origin_toggle:get() and tracker.last_position_waypoint_index ~= nil then
                tracker.return_point = tracker.last_position_waypoint_index
                sm:change_state("BACKTRACKING_TO_WAYPOINT")
                return
            end

            sm:change_state("EXPLORE_HELLTIDE")
        end
    end,
    exit = function(sm)
        if tracker.current_chest:is_interactable() then
            return
        end
        
        for i, tracked in ipairs(tracker.chests_found) do
            if tracked.position:dist_to(tracker.current_chest:get_position()) < 1 then
                table.remove(tracker.chests_found, i)
                tracker.opened_chests_count = tracker.opened_chests_count + 1
                break
            end
        end

        tracker.current_chest = nil
        current_chest_interactable = nil
    end,
}

return chests_states

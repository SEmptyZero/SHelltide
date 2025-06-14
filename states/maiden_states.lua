local utils          = require "core.utils"
local tracker        = require "core.tracker"
local explorerlite   = require "core.explorerlite"
local explore_states = require "states.explore_states"
local gui            = require "gui"
local combat_manager = require "core.combat_manager"
local a_star_waypoint = require "core.a_star_waypoints"

local maiden_states = {}

local function get_all_altars()
    tracker.unique_altars = {}
    local targets = utils.find_targets_in_radius(tracker.current_maiden_position, 20)
    for _, obj in ipairs(targets) do
        if obj:get_skin_name() == "S04_SMP_Succuboss_Altar_A_Dyn" then
            table.insert(tracker.unique_altars, { target = obj, name = obj:get_skin_name(), pos = obj:get_position() })
        end
    end

    return tracker.unique_altars
end

maiden_states.GOTO_MAIDEN = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: GOTO_MAIDEN")
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(false)
        end

        if #tracker.waypoints > 0 and utils.distance_to(tracker.waypoints[1]) > 8 then
            local nearest_index = explore_states:find_closest_waypoint_index(tracker.waypoints)
            tracker.waypoint_index = nearest_index
            console.print("Waypoint di partenza selezionato: " .. nearest_index)
        end
    end,
    execute = function(sm)
        local i = a_star_waypoint.get_closest_waypoint_index(tracker.waypoints,tracker.current_maiden_position)
        if not i then
            console.print("Nessun waypoint trovato vicino a return_point!")
            return
        end
        
        local reached = a_star_waypoint.navigate_to_waypoint(tracker.waypoints,tracker.waypoint_index,i)
        
        if not explorerlite.is_in_traversal_state then
            utils.handle_orbwalker_auto_toggle(2, 2)
        end
        
        if reached then
            tracker.waypoint_index = i
            sm:change_state("GAP_ALTARS")
            return
        end
    end,
    exit = function(sm)
    end,
}

maiden_states.GAP_ALTARS = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: GAP_ALTARS")
    end,
    execute = function(sm)
        if utils.distance_to(tracker.current_maiden_position) > 2 then
            explorerlite:set_custom_target(tracker.current_maiden_position)
            explorerlite:move_to_target()
        else
            sm:change_state("CLEANING_MAIDEN_AREA")
        end
    end,
}

maiden_states.CLEANING_MAIDEN_AREA = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: CLEANING_MAIDEN_AREA")
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(true)
        end
    end,
    execute = function(sm)
        local nearby_enemies = utils.find_enemies_in_radius(tracker.current_maiden_position, 8)
        if #nearby_enemies > 1 then
            local pos_first_enemy = nearby_enemies[1]:get_position()
            if utils.distance_to(nearby_enemies[1]) > 10 then
                explorerlite:set_custom_target(pos_first_enemy)
                explorerlite:move_to_target()
            else
                if tracker.check_time("random_circle_delay_helltide", 1.3) and pos_first_enemy then
                    local new_pos = utils.get_random_point_circle(pos_first_enemy, 9, 2)
                    if new_pos and not explorerlite:is_custom_target_valid() then
                        explorerlite:set_custom_target(new_pos)
                        tracker.clear_key("random_circle_delay_helltide")
                    end
                end
                
                explorerlite:move_to_target()
            end
        else
            if utils.distance_to(tracker.current_maiden_position) > 2 then
                explorerlite:set_custom_target(tracker.current_maiden_position)
                explorerlite:move_to_target()
            else
                sm:change_state("SEARCHING_MAIDEN_ALTAR")
            end
        end
    end,
    exit = function(sm)
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(false)
        end
    end,
}

local search_altar = nil
maiden_states.SEARCHING_MAIDEN_ALTAR = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: SEARCHING_MAIDEN_ALTAR")
    end,
    execute = function(sm)

        --check if im in helltide + se non ho i cuori esco
        if not utils.is_in_helltide() then
            sm:change_state("RETURN_CITY")
            return
        end

        if not tracker.check_time("helltide_wait_before_search_altar", 0.8) then
            return
        end

        local altars = utils.find_targets_in_radius(tracker.current_maiden_position, 20)
        for _, obj in ipairs(altars) do
            if obj and obj:is_interactable() and obj:get_skin_name() == "S04_SMP_Succuboss_Altar_A_Dyn" then
                search_altar = obj
                sm:change_state("PLACE_HEARTS")
                return
            end
        end

        sm:change_state("MAIDEN_IS_COMING")
    end,
    exit = function(sm)
        tracker.helltide_wait_before_search_altar = nil
    end,
}

maiden_states.PLACE_HEARTS = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: PLACE_HEARTS")
    end,
    execute = function(sm)
        if LooteerPlugin.getSettings("looting") then
            return
        end

        local altarPos = search_altar:get_position()
        local playerPos = tracker.player_position

        if playerPos:dist_to(altarPos) > 2 then
            explorerlite:set_custom_target(altarPos)
            explorerlite:move_to_target()
        else
            sm:change_state("INTERACT_ALTAR")
            return
        end
    end,
    exit = function(sm)
    end,
}

maiden_states.INTERACT_ALTAR = {
    enter = function(sm)
        explorerlite.is_task_running = true
        console.print("HELLTIDE: INTERACT_ALTAR")
    end,
    execute = function(sm)
        local targetAltar = search_altar
        local success = interact_object(targetAltar)
        if success then
            if not targetAltar:is_interactable() then
                sm:change_state("CLEANING_MAIDEN_AREA")
            end
        end
        
    end,
    exit = function(sm)
    end,
}



--S04_demon_succubus_miniboss
maiden_states.MAIDEN_IS_COMING = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: MAIDEN_IS_COMING")
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(true)
        end
        tracker.clear_key("helltide_ended_timeout")
    end,
    execute = function(sm)
        if LooteerPlugin.getSettings("looting") then
            return
        end

        if utils.distance_to(tracker.current_maiden_position) > 17 then
            explorerlite:set_custom_target(tracker.current_maiden_position)
            explorerlite:move_to_target()
            return
        end

        local altar = utils.find_closest_target("S04_SMP_Succuboss_Altar_A_Dyn")
        if altar and altar:is_interactable() then
            sm:change_state("WAIT_AFTER_MAIDEN")
            return
        end

        if not utils.is_in_helltide() then
            local maiden_found = false
            local get_maiden = utils.find_closest_target("S04_demon_succubus_miniboss")
            if get_maiden and utils.distance_to(get_maiden:get_position()) < 40 then
                maiden_found = true
            end

            if tracker.check_time("helltide_ended_timeout", 60) and not maiden_found then
                console.print("HELLTIDE: Timeout reached after Helltide ended and not maiden found, exiting ritual")
                sm:change_state("WAIT_AFTER_MAIDEN")
                return
            end
        end

        combat_manager.kite_enemies()
    end,
    exit = function(sm)
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(false)
        end
        tracker.clear_key("helltide_ended_timeout")
    end,
}

maiden_states.WAIT_AFTER_MAIDEN = {
    enter = function(sm)
        explorerlite.is_task_running = true
        console.print("HELLTIDE: WAIT_AFTER_MAIDEN")
        tracker.clear_key("helltide_wait_after_fight_maiden")
    end,
    execute = function(sm)
        if LooteerPlugin.getSettings("looting") then
            tracker.clear_key("helltide_wait_after_fight_maiden")
        end

        if tracker.check_time("helltide_wait_after_fight_maiden", 2) then
            tracker.clear_key("helltide_wait_after_fight_maiden")
            local current_hearts = get_helltide_coin_hearts()

            if tracker.check_time("helltide_switch_to_farm_chests", gui.elements.maiden_slider_maiden_time:get() * 60) or current_hearts < 3 then
                tracker.clear_key("helltide_switch_to_farm_chests")
                tracker.check_time("helltide_switch_to_farm_maiden", gui.elements.maiden_slider_helltide_chests_time:get() * 60)
                
                if gui.elements.maiden_return_to_origin_toggle:get() and tracker.last_position_waypoint_index ~= nil then
                    tracker.return_point = tracker.last_position_waypoint_index
                    sm:change_state("BACKTRACKING_TO_WAYPOINT")
                    return
                end
                
                sm:change_state("EXPLORE_HELLTIDE")
                return
            end

            if utils.should_activate_alfred() then
                sm:change_state("ALFRED_TRIGGERED")
                return
            end

            sm:change_state("GAP_ALTARS")
            return
        end
    end,
    exit = function(sm)
    end,
}

return maiden_states

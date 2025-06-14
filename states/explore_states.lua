local utils          = require "core.utils"
local tracker        = require "core.tracker"
local explorerlite   = require "core.explorerlite"
local settings       = require "core.settings"
local enums          = require "data.enums"
local gui            = require "gui"
local a_star_waypoint         = require "core.a_star_waypoints"

local explore_states = {}

local function load_waypoints(file)
    if file == "menestad" then
        tracker.waypoints = require("waypoints.menestad")
        console.print("Loaded waypoints: menestad")
    elseif file == "marowen" then
        tracker.waypoints = require("waypoints.marowen")
        console.print("Loaded waypoints: marowen")
    elseif file == "ironwolfs" then
        tracker.waypoints = require("waypoints.ironwolfs")
        console.print("Loaded waypoints: ironwolfs")
    elseif file == "wejinhani" then
        tracker.waypoints = require("waypoints.wejinhani")
        console.print("Loaded waypoints: wejinhani")
    elseif file == "jirandai" then
        tracker.waypoints = require("waypoints.jirandai")
        console.print("Loaded waypoints: jirandai")
    else
        console.print("No waypoints loaded")
    end
end

local function check_and_load_waypoints()
    for _, tp in ipairs(enums.helltide_tps) do
        local match = false
        for _, zone in ipairs(tp.name) do
            if utils.player_in_zone(zone) then
                match = true
                break
            end
        end

        if match then
            tracker.current_zone = tp.file
            load_waypoints(tp.file)
            tracker.current_maiden_position = enums.maiden_positions[tp.file][1] or nil
            if tracker.current_maiden_position then
                console.print("Loaded maiden position: " .. tp.file)
            end
            return true
        end
    end
    
    return false
end

function explore_states:find_closest_waypoint_index(waypoints)
    local index = nil
    local closest_coordinate = 10000

    for i, coordinate in ipairs(waypoints) do
        if utils.distance_to(coordinate) < closest_coordinate then
            closest_coordinate = utils.distance_to(coordinate)
            index = i
        end
    end
    return index
end


local skipStates = {
    NEW_CHEST_FOUND = true,
    MOVING_TO_CHEST = true,
    INTERACT_CHEST = true,
    WAIT_AFTER_INTERECTION = true,
    ALREADY_CHEST_FOUND = true,
    --
    WAIT_AFTER_FIGHT = true,
    SEARCHING_HELLTIDE = true,
    LAP_COMPLETED = true,
    RESTART = true,
    BACKTRACKING_TO_WAYPOINT = true,
}

explore_states.BACKTRACKING_TO_WAYPOINT = {
    enter = function(sm)
        console.print("HELLTIDE: BACKTRACKING_TO_WAYPOINT")
        explorerlite.is_task_running = false
        --LooteerPlugin.setSettings("enabled", false)
    end,
    execute = function(sm)
        if not tracker.return_point then
            console.print("Null return_point")
            return
        end

        local reached = a_star_waypoint.navigate_to_waypoint(tracker.waypoints,tracker.waypoint_index,tracker.return_point)
        
        if not explorerlite.is_in_traversal_state then
            utils.handle_orbwalker_auto_toggle(2, 2)
        end
        
        if reached then
            tracker.waypoint_index = tracker.return_point
            sm:change_state("EXPLORE_HELLTIDE")
        end
    end,
    exit = function(sm)
        --LooteerPlugin.setSettings("enabled", true)
        tracker.last_position_waypoint_index = nil
        if sm:get_previous_state() == "SEARCHING_MAIDEN_ALTAR" then
            tracker.clear_key("helltide_delay_trigger_maiden")
        end
    end,
}

explore_states.NAVIGATE_TO_WAYPOINT = {
    enter = function(sm)
        console.print("HELLTIDE: NAVIGATE_TO_WAYPOINT")
        explorerlite.is_task_running = false
        --LooteerPlugin.setSettings("enabled", false)
    end,
    execute = function(sm)
        if not tracker.return_point then
            console.print("Null return_point")
            return
        end

        local i = a_star_waypoint.get_closest_waypoint_index(tracker.waypoints, tracker.return_point)
        if not i then
            console.print("Nessun waypoint trovato vicino a return_point!")
            return
        end

        local reached = a_star_waypoint.navigate_to_waypoint(tracker.waypoints,tracker.waypoint_index, i)

        if not explorerlite.is_in_traversal_state then
            utils.handle_orbwalker_auto_toggle(2, 2)
        end

        if reached then
            tracker.waypoint_index = i
            local is_valid_tracked_chest = utils.get_chest_tracked(tracker.navigate_to_waypoint_chest, tracker)
            local is_valid_chest = utils.find_helltide_chest_by_position(is_valid_tracked_chest.position)
            if is_valid_chest then
                tracker.current_chest = is_valid_chest
                tracker.current_chest_saved_pos = is_valid_tracked_chest.position
                sm:change_state("MOVING_TO_CHEST")
            else
                tracker.current_chest = nil
                tracker.navigate_to_waypoint_chest = nil
                sm:change_state("EXPLORE_HELLTIDE")
            end
        end
    end,
}

explore_states.EXPLORE_HELLTIDE = {
    enter = function(sm)
        console.print("HELLTIDE: EXPLORE_HELLTIDE")
        explorerlite.is_task_running = false
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(false)
        end
        tracker.clear_key("explore_helltide_traversal_periodic_check")

        if skipStates[sm:get_previous_state()] then
            return
        end
        
        if #tracker.waypoints > 0 and utils.distance_to(tracker.waypoints[1]) > 8 then
            local nearest_index = explore_states:find_closest_waypoint_index(tracker.waypoints)
            tracker.waypoint_index = nearest_index
            console.print("Waypoint di partenza selezionato: " .. nearest_index)
        end
    end,
    execute = function(sm)
        
        if LooteerPlugin.getSettings("looting") then
            return
        end
        
        if not utils.is_in_helltide() then
            sm:change_state("RETURN_CITY")
            return
        end

        if tracker.waypoint_index > #tracker.waypoints or tracker.waypoint_index < 1 or #tracker.waypoints == 0 then
            sm:change_state("LAP_COMPLETED")
            return
        end

        if utils.should_activate_obols() then
            sm:change_state("OBOLS_TRIGGERED")
            return
        end

        if utils.should_activate_alfred() then
            local nearby_enemies = utils.find_enemies_in_radius_with_z(tracker.player_position, 15, 2)
            
            if #nearby_enemies > 0 then
                if not gui.elements.manual_clear_toggle:get() then
                    orbwalker.set_clear_toggle(true)
                end
                local random_enemy = nearby_enemies[math.random(#nearby_enemies)]
                local pos_enemy = random_enemy:get_position()
                
                if utils.distance_to(random_enemy) > 10 then
                    explorerlite:set_custom_target(pos_enemy)
                    explorerlite:move_to_target()
                else
                    if tracker.check_time("random_circle_delay_alfred", 1.3) and pos_enemy then
                        local new_pos = utils.get_random_point_circle(pos_enemy, 9, 2)
                        if new_pos and not explorerlite:is_custom_target_valid() then
                            explorerlite:set_custom_target(new_pos)
                            tracker.clear_key("random_circle_delay_alfred")
                        end
                    end
                    explorerlite:move_to_target()
                end
            else
                if not gui.elements.manual_clear_toggle:get() then
                    orbwalker.set_clear_toggle(false)
                end
                sm:change_state("ALFRED_TRIGGERED")
                return
            end
        end

        local current_hearts = get_helltide_coin_hearts()
        if tracker.check_time("helltide_switch_to_farm_maiden", gui.elements.maiden_slider_helltide_chests_time:get() * 60) and current_hearts >= 3 then
            tracker.clear_key("helltide_switch_to_farm_maiden")
            tracker.check_time("helltide_switch_to_farm_chests", gui.elements.maiden_slider_maiden_time:get() * 60)
            tracker.last_position_waypoint_index = tracker.waypoint_index
            tracker.current_maiden_position = utils.get_closest_position(tracker.current_zone)
            sm:change_state("GOTO_MAIDEN")
            return
        end

        --local k = vec3:new(-1424.652344, -125.912109, 90.891602)
        --local reached = explorerlite:navigate_to_target(vec3:new(-1733.708008, -1196.139648, 11.426758))
        --[[local reached = explore_states:navigate_to_waypoint(1)
        if reached then
            console.print("Ofdfsdfdsfs")
        end]]
        --local a = explore_states:navigate_to_waypoint(1)
        --explorerlite:set_custom_target(vec3:new(216.226562, -601.409180, 6.959961))
        --explorerlite:set_custom_target(vec3:new(-565.189758, -368.133087, 35.649544))
        --explorerlite:set_custom_target(vec3:new(-1794.236938, -1281.271606, 0.839844))
        --explorerlite:set_custom_target(vec3:new(-825.754883, 427.040588, 3.966681))
        --explorerlite:set_custom_target(get_cursor_position())
        --explorerlite:move_to_target()
        --explorerlite:follow_segmented_path(tracker.waypoints[1])

        --explorerlite:set_custom_target(vec3:new(-1794.236938, -1281.271606, 0.839844))
        --explorerlite:move_to_target()

        if not explorerlite.is_in_traversal_state then
            utils.handle_orbwalker_auto_toggle(2, 2)
        end

        --START FIGHT ENEMIES
        if tracker.check_time("helltide_delay_fight_enemies", 0.8) then
            tracker.clear_key("helltide_delay_fight_enemies")
            local enemies = tracker.all_actors
            for _, obj in ipairs(enemies) do
                local obj_pos = obj:get_position()
                if utils.is_valid_target(obj) and math.abs(tracker.player_position:z() - obj_pos:z()) <= 0.80 and obj_pos:dist_to(tracker.player_position) < 15 then
                    tracker.target_selector = obj
                    sm:change_state("FIGHT_ELITE_CHAMPION")
                    return
                end
            end
        end
        --FINISH FIGHT ENEMIES

        --START HELLTIDE CHESTS
        if tracker.check_time("helltide_delay_find_chests", 0.9) then
            tracker.clear_key("helltide_delay_find_chests")
            for chest_name, _ in pairs(enums.helltide_chests_info) do
                local chest_found = utils.find_closest_target(chest_name)
                if chest_found and chest_found:is_interactable() and utils.distance_to(chest_found) < 35 and math.abs(tracker.player_position:z() - chest_found:get_position():z()) <= 3 then
                    if not utils.is_chest_already_tracked(chest_found, tracker) then
                        tracker.current_chest = chest_found
                        sm:change_state("NEW_CHEST_FOUND")
                        return
                    else
                        local chest_tracked = utils.get_chest_tracked(chest_found:get_position(), tracker)
                        if chest_tracked then
                            local time_elapsed = get_time_since_inject() - chest_tracked.time
                            if time_elapsed > 15 or sm:get_previous_state() == "NAVIGATE_TO_WAYPOINT" then
                                chest_tracked.time = get_time_since_inject()
                                tracker.current_chest = chest_found
                                sm:change_state("ALREADY_CHEST_FOUND")
                                return
                            end
                        end
                    end
                end
            end
        end
        --FINISH HELLTIDE CHESTS

        --START SILENT CHESTS HELLTIDE
        if tracker.check_time("helltide_delay_find_silent_chests", 1.8) then
            tracker.clear_key("helltide_delay_find_silent_chests")
            if gui.elements.open_silent_chests_toggle:get() then
                local player_consumable_items = tracker.local_player:get_consumable_items()
                for _, item in pairs(player_consumable_items) do
                    if item:get_skin_name() == "GamblingCurrency_Key" then
                        local silent_chest = utils.find_closest_target("Hell_Prop_Chest_Rare_Locked_GamblingCurrency")
                        if silent_chest and silent_chest:is_interactable() and utils.distance_to(silent_chest) < 25 then
                            tracker.current_chest = silent_chest
                            tracker.current_chest_saved_pos = silent_chest:get_position()
                            sm:change_state("MOVING_TO_SILENT_CHEST")
                            return
                        end
                    end
                end
            end
        end
        --FINISH SILENT CHESTS HELLTIDE

        --START BACK TRACKING CHESTS HELLTIDE
        local current_cinders = get_helltide_coin_cinders()
        if tracker.check_time("delay_back_tracking_check", 3) then
            tracker.clear_key("delay_back_tracking_check")

            for _, tracked in pairs(tracker.chests_found) do
                local current_cinders = get_helltide_coin_cinders()
                --console.print(tracked.name .. " | " .. tracked.price)
                if current_cinders >= tracked.price then
                    tracker.return_point = tracked.position
                    tracker.last_position_waypoint_index = tracker.waypoint_index
                    tracker.navigate_to_waypoint_chest = tracked.position
                    console.print("Waypoint before go: " ..tracker.last_position_waypoint_index)
                    sm:change_state("NAVIGATE_TO_WAYPOINT")
                    return
                end
            end
            --console.print("Count chests found: ".. #tracker.chests_found)
        end
        --FINISH BACK TRACKING CHESTS HELLTIDE

        --START MOVE TROUGH WAYPOINT HELLTIDE
        local current_waypoint = tracker.waypoints[tracker.waypoint_index]
        if current_waypoint then
            local distance = utils.distance_to(current_waypoint)

            if distance < 3.5 then 
                tracker.waypoint_index = tracker.waypoint_index + 1
            else
                if explorerlite:is_custom_target_valid() then
                    explorerlite:move_to_target()
                else
                    local rand_pos = utils.get_random_point_circle(current_waypoint, 2, math.huge)
                    if rand_pos then
                        explorerlite:set_custom_target(rand_pos)
                    end
                end        
            end
        end
        --FINISH MOVE TROUGH WAYPOINT HELLTIDE

    end,
}


explore_states.LAP_COMPLETED = {
    enter = function(sm)
        console.print("HELLTIDE: LAP_COMPLETED")
    end,
    execute = function(sm)
        if tracker.check_time("next_cycle_helltide", 2) then
            tracker.clear_key("next_cycle_helltide")
            sm:change_state("RESTART")
        end
    end,
}

explore_states.RETURN_CITY = {
    enter = function(sm)
        console.print("HELLTIDE: RETURN_CITY")
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(false)
        end
        explorerlite.toggle_anti_stuck = false
    end,
    execute = function(sm)
        local reached = a_star_waypoint.navigate_to_waypoint(tracker.waypoints,tracker.waypoint_index, 1)

        if reached then
            sm:change_state("SEARCHING_HELLTIDE")
        end
    end,
    exit = function(sm)
        explorerlite.toggle_anti_stuck = true
    end,
}

explore_states.INIT = {
    execute = function(sm)
        if utils.is_loading_or_limbo() then
            return
        end

        console.print("HELLTIDE: INIT")
        explorerlite.is_task_running = true
        tracker.waypoints = {}
        explorerlite:clear_path_and_target()

        local waypoints_loaded = check_and_load_waypoints()
        if waypoints_loaded and tracker.waypoints and #tracker.waypoints > 0 then
            console.print("HELLTIDE: INIT WAYPOINTS")
            tracker.waypoint_index = 1
            tracker.chests_found = {}
            tracker.opened_chests_count = 0
            tracker.clear_key("helltide_delay_trigger_maiden")

            tracker.clear_key("helltide_switch_to_farm_maiden")
            tracker.clear_key("helltide_switch_to_farm_chests")

            if type(tracker.waypoints) ~= "table" then
                console.print("Error: waypoints is not a table")
                return
            end

            local current_hearts = get_helltide_coin_hearts()
            if gui.elements.maiden_enable_first_maiden_toggle:get() and current_hearts >= 3 then
                tracker.clear_key("helltide_switch_to_farm_maiden")
                tracker.check_time("helltide_switch_to_farm_chests", gui.elements.maiden_slider_maiden_time:get() * 60)
                tracker.last_position_waypoint_index = tracker.waypoint_index
                tracker.current_maiden_position = utils.get_closest_position(tracker.current_zone)
                sm:change_state("GOTO_MAIDEN")
                return
            else
                tracker.clear_key("helltide_switch_to_farm_chests")
                tracker.check_time("helltide_switch_to_farm_maiden", gui.elements.maiden_slider_helltide_chests_time:get() * 60)
                sm:change_state("EXPLORE_HELLTIDE")
                return
            end
        end
    end,
}

explore_states.RESTART = {
    enter = function(sm)
        console.print("HELLTIDE: RESTART")
        explorerlite.is_task_running = true

        check_and_load_waypoints()
        tracker.waypoint_index = 1

        sm:change_state("EXPLORE_HELLTIDE")
    end,
}

explore_states.RESURRECT_AND_RETURN = {
    enter = function(sm)
        console.print("HELLTIDE: RESURRECT_AND_RETURN entered.")
        explorerlite.is_task_running = false
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(false)
        end
        explorerlite:clear_path_and_target()
    end,
    execute = function(sm)

        if tracker.local_player:is_dead() then
            revive_at_checkpoint()
            return
        end

        local prev_state = sm:get_previous_state()

        if prev_state == "ALFRED_TRIGGERED" then
            sm:change_state("ALFRED_TRIGGERED")
            return
        end

        local reached = a_star_waypoint.navigate_to_waypoint(tracker.waypoints,tracker.waypoint_index, tracker.waypoint_index)
        if not explorerlite.is_in_traversal_state then
            utils.handle_orbwalker_auto_toggle(2, 2)
        end

        if reached then
            if prev_state == "MOVING_TO_CHEST" or prev_state == "INTERACT_CHEST" or prev_state == "WAIT_AFTER_INTERECTION" or prev_state == "MOVING_TO_SILENT_CHEST" or prev_state == "WAIT_AFTER_FIGHT" then
                sm:change_state("EXPLORE_HELLTIDE")
                return
            end

            sm:change_state(prev_state)
        end
    end,
    exit = function(sm)
        console.print("HELLTIDE: Exiting RESURRECT_AND_RETURN.")
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(false)
        end
    end,
}

return explore_states

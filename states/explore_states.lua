local utils          = require "core.utils"
local tracker        = require "core.tracker"
local explorerlite   = require "core.explorerlite"
local settings       = require "core.settings"
local enums          = require "data.enums"
local gui            = require "gui"

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

function explore_states:get_closest_waypoint_index(target_position, min_margin)
    local min_dist = math.huge
    local closest_index = nil
    min_margin = min_margin or 2

    for i, wp in ipairs(tracker.waypoints) do
        local d = target_position:dist_to(wp)
        if d >= min_margin and d < min_dist then
            min_dist = d
            closest_index = i
        end
    end

    return closest_index
end

function explore_states:find_traversal_actor(interect)
    local actors = actors_manager:get_all_actors()
    local player_pos = tracker.player_position
    local curr_actor = nil
    interact = interact or true
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        local actor_pos = actor:get_position()
        if name:match("[Tt]raversal") and actor:is_interactable() and utils.calculate_distance(player_pos, actor_pos) < 3.5 then
            --console.print("Match?")
            --local actor_pos = actor:get_position()
            orbwalker.set_clear_toggle(true)
            if math.abs(actor_pos:z() - player_pos:z()) <= 4 then
                curr_actor = actor
                break
            end
        end
    end

    if interact then
        return interact_object(curr_actor)
    end

    return curr_actor
end

function explore_states:near_traversal_actor()
    local actors = actors_manager:get_all_actors()
    local player_pos = tracker.player_position

    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        local actor_pos = actor:get_position()
        if name:match("[Tt]raversal") and actor:is_interactable() and utils.calculate_distance(player_pos, actor_pos) < 10 then
            return true
        end
    end

    return false
end

function explore_states:navigate_to_waypoint(target_index)
    local waypoints = tracker.waypoints
    if not waypoints or #waypoints == 0 then
        return false
    end

    local current_index = tracker.waypoint_index or 1

    if tracker.current_target_index == nil or tracker.current_target_index ~= target_index or tracker.a_start_waypoint_path == nil then
        tracker.current_target_index = target_index
        local range_threshold = 80
        local path = explorerlite:a_star_waypoint(waypoints, current_index, target_index, range_threshold)
        if not path then
            return false
        end

        tracker.a_start_waypoint_path = path
        tracker.current_path_index = 1
        console.print(table.concat(path, " -> "))
    end

    local path = tracker.a_start_waypoint_path
    local player_pos = tracker.player_position
    local current_path_index = tracker.current_path_index
    local current_wp = waypoints[path[current_path_index]]

    if player_pos:dist_to(current_wp) < 3 then
        if current_path_index == #path then
            return true
        else
            tracker.current_path_index = tracker.current_path_index + 1
        end
    end

    local next_wp = waypoints[path[tracker.current_path_index]]
    if next_wp then
        explorerlite:set_custom_target(next_wp)
        explorerlite:move_to_target()
    end

    return false
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

local function is_valid_target(enemy)
    return enemy
       and (enemy:is_elite() or enemy:is_champion() or enemy:is_boss())
       and enemy:is_enemy()
       and not enemy:is_untargetable()
       and not enemy:is_dead()
       and not enemy:is_immune()
end

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

        local reached = explore_states:navigate_to_waypoint(tracker.return_point)
        
        local enemies = utils.find_enemies_in_radius(tracker.player_position, 3)
        if #enemies > 0 or explore_states:near_traversal_actor() then
            orbwalker.set_clear_toggle(true)
        else
            orbwalker.set_clear_toggle(false)
        end
        
        if reached then
            tracker.waypoint_index = tracker.return_point
            sm:change_state("EXPLORE_HELLTIDE")
        end

        --[[if tracker.check_time("traversal_delay_helltide", 4.5) then
            tracker.clear_key("traversal_delay_helltide")
            local f = explore_states:find_traversal_actor()
            if f then
                console.print("HELLTIDE: INTECRACT TRAVERSAL")
                orbwalker.set_clear_toggle(false)
            end
        end]]
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

        local i = explore_states:get_closest_waypoint_index(tracker.return_point)
        if not i then
            console.print("Nessun waypoint trovato vicino a return_point!")
            return
        end

        local reached = explore_states:navigate_to_waypoint(i)

        local enemies = utils.find_enemies_in_radius(tracker.player_position, 3)
        if #enemies > 0 or explore_states:near_traversal_actor() then
            orbwalker.set_clear_toggle(true)
        else
            orbwalker.set_clear_toggle(false)
        end

        if reached then
            tracker.waypoint_index = tracker.return_point
            sm:change_state("EXPLORE_HELLTIDE")
        end

        --[[if tracker.check_time("traversal_delay_helltide", 4.5) then
            tracker.clear_key("traversal_delay_helltide")
            local f = explore_states:find_traversal_actor()
            if f then
                console.print("HELLTIDE: INTECRACT TRAVERSAL")
                orbwalker.set_clear_toggle(false)
            end
        end]]
    end,
    exit = function(sm)
        --LooteerPlugin.setSettings("enabled", true)
    end,
}

explore_states.EXPLORE_HELLTIDE = {
    enter = function(sm)
        console.print("HELLTIDE: EXPLORE_HELLTIDE")
        explorerlite.is_task_running = false
        orbwalker.set_clear_toggle(false)

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
        

        if utils.should_activate_alfred() then
            sm:change_state("ALFRED_TRIGGERED")
            return
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
        --explorerlite:set_custom_target(k)
        --explorerlite:move_to_target()

        local enemies = utils.find_enemies_in_radius(tracker.player_position, 3)
        if #enemies > 0 or explore_states:near_traversal_actor() then
            orbwalker.set_clear_toggle(true)
        else
            orbwalker.set_clear_toggle(false)
        end

        --START FIGHT ENEMIES
        if tracker.check_time("helltide_delay_fight_enemies", 1.3) then
            tracker.clear_key("helltide_delay_fight_enemies")
            local enemies = actors_manager.get_all_actors()
            for _, obj in ipairs(enemies) do
                local obj_pos = obj:get_position()
                if is_valid_target(obj) and math.abs(tracker.player_position:z() - obj_pos:z()) <= 0.80 and obj_pos:dist_to(tracker.player_position) < 15 then
                    tracker.target_selector = obj
                    sm:change_state("FIGHT_ELITE_CHAMPION")
                    return
                end
            end
        end
        --FINISH FIGHT ENEMIES

        --START HELLTIDE CHESTS
        if tracker.check_time("helltide_delay_find_chests", 1.6) then
            tracker.clear_key("helltide_delay_find_chests")
            for chest_name, _ in pairs(enums.helltide_chests_info) do
                local chest_found = utils.find_closest_target(chest_name)
                if chest_found and chest_found:is_interactable() and utils.distance_to(chest_found) < 35 and math.abs(tracker.player_position:z() - chest_found:get_position():z()) <= 4 then
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
                            sm:change_state("MOVING_TO_CHEST")
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
                    tracker.last_position_waypoint_index =  tracker.waypoint_index
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
                    local randomized_waypoint = utils.get_random_point_circle(current_waypoint, 1.5, 3)
                    if distance > 0 and distance < 6.6 then
                        explorerlite:set_custom_target(current_waypoint)
                    else
                        explorerlite:set_custom_target(randomized_waypoint)
                    end
                    explorerlite:move_to_target()
                end        
            end
        end
        --FINISH MOVE TROUGH WAYPOINT HELLTIDE

        --[[if tracker.check_time("traversal_delay_helltide", 4.5) then
            tracker.clear_key("traversal_delay_helltide")
            local f = explore_states:find_traversal_actor()
            if f then
                console.print("HELLTIDE: INTECRACT TRAVERSAL")
                orbwalker.set_clear_toggle(false)
            end
        end]]

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
    end,
    execute = function(sm)
        local reached = explore_states:navigate_to_waypoint(1)

        local enemies = utils.find_enemies_in_radius(tracker.player_position, 3)
        if #enemies > 0 or explore_states:near_traversal_actor() then
            orbwalker.set_clear_toggle(true)
        else
            orbwalker.set_clear_toggle(false)
        end

        if reached then
            sm:change_state("SEARCHING_HELLTIDE")
        end
    end,
}

explore_states.INIT = {
    execute = function(sm)
        if utils.is_loading_or_limbo() then
            return
        end

        console.print("HELLTIDE: INIT")
        explorerlite.is_task_running = true

        local waypoints_loaded = check_and_load_waypoints()
        if waypoints_loaded then
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

return explore_states

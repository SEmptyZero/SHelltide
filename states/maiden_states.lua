local utils          = require "core.utils"
local tracker        = require "core.tracker"
local explorerlite   = require "core.explorerlite"
local explore_states = require "states.explore_states"
local gui            = require "gui"

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
        orbwalker.set_clear_toggle(false)

        if #tracker.waypoints > 0 and utils.distance_to(tracker.waypoints[1]) > 8 then
            local nearest_index = explore_states:find_closest_waypoint_index(tracker.waypoints)
            tracker.waypoint_index = nearest_index
            console.print("Waypoint di partenza selezionato: " .. nearest_index)
        end
    end,
    execute = function(sm)
        local i = explore_states:get_closest_waypoint_index(tracker.current_maiden_position)
        if not i then
            console.print("Nessun waypoint trovato vicino a return_point!")
            return
        end
        
        local reached = explore_states:navigate_to_waypoint(i)
        
        if explorerlite.is_in_gizmo_traversal_state then
            local enemies = utils.find_enemies_in_radius(tracker.player_position, 3)
            if #enemies > 0 then
                orbwalker.set_clear_toggle(true)
            else
                orbwalker.set_clear_toggle(false)
            end
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
        orbwalker.set_clear_toggle(true)
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
            if utils.distance_to(tracker.current_maiden_position) > 2 then
                explorerlite:set_custom_target(tracker.current_maiden_position)
                explorerlite:move_to_target()
            else
                sm:change_state("SEARCHING_MAIDEN_ALTAR")
            end
        end
    end,
    exit = function(sm)
        orbwalker.set_clear_toggle(false)
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

function update_maiden_enemies()
    local maiden_pos = tracker.current_maiden_position
    local radius = 16
    local nearby_enemies = utils.find_targets_in_radius(maiden_pos, radius)

    tracker.maiden_enemies = {}

    for _, enemy in ipairs(nearby_enemies) do
        if not enemy:is_dead() 
           and (enemy:is_enemy() or enemy:is_elite() or enemy:is_champion()) 
           and not enemy:is_interactable() 
           and not enemy:is_untargetable() then
            table.insert(tracker.maiden_enemies, enemy)
        end
    end
end

local strafe_direction = 1
local last_direction_change = 0
local direction_change_interval = math.random(3, 7)

function kite_enemies()
    update_maiden_enemies()

    local safe_min_distance = 6
    local safe_max_distance = 9
    local max_radius = 15

    local enemy_count = #tracker.maiden_enemies
    if enemy_count == 0 then
        local random_angle = math.random() * 2 * math.pi
        local random_distance = math.random() * 20
        local random_pos = vec3:new(
            tracker.current_maiden_position:x() + random_distance * math.cos(random_angle),
            tracker.current_maiden_position:y() + random_distance * math.sin(random_angle),
            tracker.current_maiden_position:z()
        )

        random_pos = utility.set_height_of_valid_position(random_pos)

        if utility.is_point_walkeable(random_pos) then
            explorerlite:set_custom_target(random_pos)
            explorerlite:move_to_target()
        end

        return
    end

    local player_pos = tracker.player_position

    local closest_enemy, closest_dist = nil, math.huge
    for _, enemy in ipairs(tracker.maiden_enemies) do
        local enemy_pos = enemy:get_position()
        local dist = utils.distance_to(enemy_pos)
        if dist < closest_dist then
            closest_dist = dist
            closest_enemy = enemy
        end
    end

    local move_dir = nil

    if closest_dist < safe_min_distance then
        local enemy_pos = closest_enemy:get_position()
        move_dir = vec3:new(
            player_pos:x() - enemy_pos:x(),
            player_pos:y() - enemy_pos:y(),
            player_pos:z() - enemy_pos:z()
        ):normalize()

    elseif closest_dist > safe_max_distance then
        local enemy_pos = closest_enemy:get_position()
        move_dir = vec3:new(
            enemy_pos:x() - player_pos:x(),
            enemy_pos:y() - player_pos:y(),
            enemy_pos:z() - player_pos:z()
        ):normalize()

    else
        local current_time = get_time_since_inject()
        if current_time - last_direction_change > direction_change_interval then
            strafe_direction = strafe_direction * -1
            last_direction_change = current_time
            direction_change_interval = math.random(3, 7)
        end

        local enemy_pos = closest_enemy:get_position()
        local angle_to_enemy = math.atan2(player_pos:y() - enemy_pos:y(), player_pos:x() - enemy_pos:x())
        local rotation_speed = 20 * math.pi / 180 * strafe_direction
        local rotated_angle = angle_to_enemy + current_time * rotation_speed

        move_dir = vec3:new(math.cos(rotated_angle), math.sin(rotated_angle), 0):normalize()
    end

    local target_distance = math.min(math.max(closest_dist, safe_min_distance), safe_max_distance)

    local function find_walkable_position(base_dir, distance)
        local angle_offsets = {0, 15, -15, 30, -30, 45, -45, 60, -60, 90, -90, 120, -120, 150, -150, 180}
        local step = 0.5

        for _, angle_deg in ipairs(angle_offsets) do
            local angle_rad = math.rad(angle_deg)
            local rotated_dir = vec3:new(
                base_dir:x() * math.cos(angle_rad) - base_dir:y() * math.sin(angle_rad),
                base_dir:x() * math.sin(angle_rad) + base_dir:y() * math.cos(angle_rad),
                base_dir:z()
            ):normalize()

            for adjusted_distance = distance, safe_min_distance, -step do
                local candidate = vec3:new(
                    player_pos:x() + rotated_dir:x() * adjusted_distance,
                    player_pos:y() + rotated_dir:y() * adjusted_distance,
                    player_pos:z() + rotated_dir:z() * adjusted_distance
                )
                candidate = utility.set_height_of_valid_position(candidate)

                if utility.is_point_walkeable(candidate) and utils.calculate_distance(candidate, tracker.current_maiden_position) <= max_radius then
                    return candidate
                end
            end
        end

        return nil
    end

    local valid_pos = find_walkable_position(move_dir, target_distance)

    if valid_pos then
        explorerlite:set_custom_target(valid_pos)
        explorerlite:move_to_target()
    end
end

--S04_demon_succubus_miniboss
maiden_states.MAIDEN_IS_COMING = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: MAIDEN_IS_COMING")
        orbwalker.set_clear_toggle(true)
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

        kite_enemies()
    end,
    exit = function(sm)
        orbwalker.set_clear_toggle(false)
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
                
                if gui.elements.maiden_return_to_origin_toggle:get() and tracker.last_position_waypoint_index ~= nil then --tracker.current_chest:get_skin_name() == "Hell_Prop_Chest_Rare_Locked_GamblingCurrency" then
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

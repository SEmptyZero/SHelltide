local utils          = require "core.utils"
local tracker        = require "core.tracker"
local explorerlite   = require "core.explorerlite"
local explore_states = require "states.explore_states"
local gui            = require "gui"

local maiden_states = {}
local maiden_position

local function get_all_altars()
    tracker.unique_altars = {}
    local targets = utils.find_targets_in_radius(maiden_position, 10)
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
        maiden_position = tracker.current_maiden_position
        LooteerPlugin.setSettings("enabled", false)
        --console.print(tostring(LooteerPlugin.getSettings("enabled")))
    end,
    execute = function(sm)
        --console.print(tostring(LooteerPlugin.getSettings("enabled")))
        
        local i = explore_states:get_closest_waypoint_index(maiden_position)
        if not i then
            console.print("Nessun waypoint trovato vicino a return_point!")
            return
        end
        
        local reached = explore_states:navigate_to_waypoint(i)
        if reached then
            tracker.waypoint_index = i
            sm:change_state("GAP_ALTARS")
        end

        if tracker.check_time("traversal_delay_helltide", 4.5) then
            tracker.clear_key("traversal_delay_helltide")
            local f = explore_states:find_traversal_actor()
            if f then
                console.print("HELLTIDE: INTECRACT TRAVERSAL")
                orbwalker.set_clear_toggle(false)
            end
        end
    end,
    exit = function(sm)
        LooteerPlugin.setSettings("enabled", true)
    end,
}

maiden_states.GAP_ALTARS = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: GAP_ALTARS")
    end,
    execute = function(sm)
        if utils.distance_to(maiden_position) > 2 then
            explorerlite:set_custom_target(maiden_position)
            explorerlite:move_to_target()
        else
            sm:change_state("SEARCHING_MAIDEN_ALTAR")
        end
    end,
}

maiden_states.SEARCHING_MAIDEN_ALTAR = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: SEARCHING_MAIDEN_ALTAR")
    end,
    execute = function(sm)

    if tracker.attempts_maiden_track and tracker.attempts_maiden_track <= 0 then
        --console.print("hero?")
        if gui.elements.maiden_return_to_origin_toggle:get() and tracker.last_position_waypoint_index ~= nil then --tracker.current_chest:get_skin_name() == "Hell_Prop_Chest_Rare_Locked_GamblingCurrency" then
            --console.print("WOOOOOOO")
            tracker.return_point = tracker.last_position_waypoint_index
            --console.print("TORNO AL WAYPOINT: ".. tracker.last_position_waypoint_index)
            sm:change_state("BACKTRACKING_TO_WAYPOINT")
            return
        end

        tracker.clear_key("helltide_delay_trigger_maiden")
        sm:change_state("EXPLORE_HELLTIDE")
        return
    end

    local altars = get_all_altars()
    if altars and #altars >= 2 then
        local current_hearts = get_helltide_coin_hearts()
        local interactable_altars = {}
        for i, altar in ipairs(altars) do
            local valid_altar = utils.find_target_by_position_and_name(altar.pos, altar.name)
            if valid_altar and valid_altar:is_interactable() then
                table.insert(interactable_altars, valid_altar)
            end
        end
        local count = #interactable_altars
        if count == 0 then
            sm:change_state("MAIDEN_IS_COMING")
            return
        elseif count >= 1 and count <= 3 and current_hearts >= count then
            sm:change_state("PLACE_HEARTS")
            return
        end
    end

    --tracker.clear_key("helltide_delay_trigger_maiden")
    --sm:change_state("EXPLORE_HELLTIDE")

    end,
    exit = function(sm)
        
    end,
}

maiden_states.PLACE_HEARTS = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: PLACE_HEARTS")
    end,
    execute = function(sm)
        if #tracker.unique_altars == 0 then
            console.print("Tutti gli altari interagiti, cambio stato a MAIDEN_IS_COMING")
            sm:change_state("MAIDEN_IS_COMING")
            return
        end

        local targetAltar = tracker.unique_altars[1]
        local altarPos = targetAltar.pos
        local playerPos = tracker.player_position

        if playerPos:dist_to(altarPos) > 3 then
            explorerlite:set_custom_target(altarPos)
            explorerlite:move_to_target()
        else
            sm:change_state("INTERACT_ALTAR")
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
        local targetAltar = tracker.unique_altars[1]
        if not targetAltar then
            sm:change_state("PLACE_HEARTS")
            return
        end

        local success = interact_object(targetAltar.target)
        if success then
            if not targetAltar.target:is_interactable() then
                table.remove(tracker.unique_altars, 1)
                sm:change_state("PLACE_HEARTS")
            end
        end
        
    end,
    exit = function(sm)
    end,
}

function update_maiden_enemies()
    local maiden_pos = maiden_position
    local radius = 15
    local nearby_enemies = utils.find_targets_in_radius(maiden_pos, radius)  -- Ritorna i nemici nel raggio specificato

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

function move_away_from_enemies()
    update_maiden_enemies()
    
    local enemy_count = #tracker.maiden_enemies
    if enemy_count == 0 then return end

    local safe_distance = 7
    local sum_x, sum_y, sum_z = 0, 0, 0
    for _, enemy in ipairs(tracker.maiden_enemies) do
        local pos = enemy:get_position()
        sum_x = sum_x + pos:x()
        sum_y = sum_y + pos:y()
        sum_z = sum_z + pos:z()
    end
    local centroid = vec3:new(sum_x / enemy_count, sum_y / enemy_count, sum_z / enemy_count)

    local dx = maiden_position:x() - centroid:x()
    local dy = maiden_position:y() - centroid:y()
    local base_angle = math.atan2(dy, dx)

    local rotation_speed = 20 * math.pi / 180
    local final_angle = base_angle + get_time_since_inject() * rotation_speed

    local new_pos = vec3:new(
        centroid:x() + safe_distance * math.cos(final_angle),
        centroid:y() + safe_distance * math.sin(final_angle),
        centroid:z()
    )

    if not utility.is_point_walkeable(new_pos) then
        local found = false
        local step = 0.5
        local adjusted_distance = safe_distance
        while adjusted_distance > 0 do
            local candidate = vec3:new(
                centroid:x() + adjusted_distance * math.cos(final_angle),
                centroid:y() + adjusted_distance * math.sin(final_angle),
                centroid:z()
            )
            candidate = utility.set_height_of_valid_position(candidate)
            if utility.is_point_walkeable(candidate) then
                new_pos = candidate
                found = true
                break
            end
            adjusted_distance = adjusted_distance - step
        end
        if not found then
            return
        end
    end

    explorerlite:set_custom_target(new_pos)
    explorerlite:move_to_target()
end

--S04_demon_succubus_miniboss
local maiden_boss = nil
maiden_states.MAIDEN_IS_COMING = {
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: MAIDEN_IS_COMING")
        orbwalker.set_clear_toggle(true)
        delay_start = 0
        maiden_boss = nil
    end,
    execute = function(sm)
        if LooteerPlugin.getSettings("looting") then
            return
        end

        move_away_from_enemies()

        if not maiden_boss then
            maiden_boss = utils.find_closest_target("S04_demon_succubus_miniboss")
        end

        if maiden_boss then
            if maiden_boss:is_dead() then
                --RANGE DI LOOTER???
                if utils.distance_to(maiden_boss) > 4 then
                    explorerlite:set_custom_target(maiden_boss:get_position())
                    explorerlite:move_to_target()
                else
                    tracker.attempts_maiden_track = tracker.attempts_maiden_track - 1
                    sm:change_state("WAIT_AFTER_MAIDEN")
                end
            end
        end
        
    end,
    exit = function(sm)
        orbwalker.set_clear_toggle(false)
        maiden_boss = nil
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
            sm:change_state("GAP_ALTARS")
        end
    end,
    exit = function(sm)
    end,
}

return maiden_states

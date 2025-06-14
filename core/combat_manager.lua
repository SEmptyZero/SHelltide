local utils         = require "core.utils"
local tracker       = require "core.tracker"
local explorerlite  = require "core.explorerlite"

local combat_manager = {}

local boss_approach_timer = 0
local boss_approach_duration = 2
local boss_approach_cooldown = 8
local last_boss_approach = 0
local circle_angle = 0
local circle_direction = 1

local function handle_boss_approach(current_time)
    if not tracker.maiden_boss then
        return false
    end

    if current_time - last_boss_approach > boss_approach_cooldown then
        if boss_approach_timer == 0 then
            boss_approach_timer = current_time
        end

        if current_time - boss_approach_timer < boss_approach_duration then
            local boss_pos = tracker.maiden_boss:get_position()
            if utils.distance_to(boss_pos) > 3 then
                explorerlite:set_custom_target(boss_pos)
                explorerlite:move_to_target()
            end
            return true
        else
            boss_approach_timer = 0
            last_boss_approach = current_time
        end
    end
    return false
end

local function kite_around_enemies(enemies_center, maiden_pos, max_radius)
    if not enemies_center then return end

    circle_angle = circle_angle + (circle_direction * 0.8)
    if circle_angle > 360 then circle_angle = 0
    elseif circle_angle < 0 then circle_angle = 360 end

    if math.random() < 0.01 then
        circle_direction = circle_direction * -1
    end

    local circle_radius = 8
    local angle_rad = math.rad(circle_angle)
    local target_pos = vec3:new(
        enemies_center:x() + circle_radius * math.cos(angle_rad),
        enemies_center:y() + circle_radius * math.sin(angle_rad),
        enemies_center:z()
    )

    target_pos = utility.set_height_of_valid_position(target_pos)

    if utility.is_point_walkeable(target_pos) and utils.calculate_distance(target_pos, maiden_pos) <= max_radius then
        explorerlite:set_custom_target(target_pos)
        explorerlite:move_to_target()
    end
end

local function move_randomly_around_maiden(maiden_pos, max_radius, min_dist, max_dist)
    local random_angle = math.random() * 2 * math.pi
    local random_distance = math.random(min_dist, max_dist)
    local random_pos = vec3:new(
        maiden_pos:x() + random_distance * math.cos(random_angle),
        maiden_pos:y() + random_distance * math.sin(random_angle),
        maiden_pos:z()
    )

    random_pos = utility.set_height_of_valid_position(random_pos)

    if utility.is_point_walkeable(random_pos) and utils.calculate_distance(random_pos, maiden_pos) <= max_radius then
        explorerlite:set_custom_target(random_pos)
        explorerlite:move_to_target()
    end
end

local function update_maiden_combat_state()
    local maiden_pos = tracker.current_maiden_position
    if not maiden_pos then return nil end

    local radius = 20
    local nearby_objects = utils.find_targets_in_radius(maiden_pos, radius)

    tracker.maiden_enemies = {}
    tracker.maiden_boss = nil

    local center_x, center_y, center_z = 0, 0, 0
    local regular_enemy_count = 0

    for _, obj in ipairs(nearby_objects) do
        if not obj:is_dead() 
           and (obj:is_enemy() or obj:is_elite() or obj:is_champion()) 
           and not obj:is_interactable() 
           and not obj:is_untargetable() then
            
            if obj:get_skin_name() == "S04_demon_succubus_miniboss" then
                tracker.maiden_boss = obj
            else
                table.insert(tracker.maiden_enemies, obj)
                local pos = obj:get_position()
                center_x = center_x + pos:x()
                center_y = center_y + pos:y()
                center_z = center_z + pos:z()
                regular_enemy_count = regular_enemy_count + 1
            end
        end
    end

    if regular_enemy_count > 0 then
        return vec3:new(center_x / regular_enemy_count, center_y / regular_enemy_count, center_z / regular_enemy_count)
    end
    
    return nil
end

function combat_manager.kite_enemies()
    if not tracker.check_time("combat_manager_kite_throttle", 0.2) then
        return
    end
    
    local enemies_center = update_maiden_combat_state()
    
    local current_time = get_time_since_inject()
    local maiden_pos = tracker.current_maiden_position
    local max_radius = 18
    
    local has_regular_enemies = enemies_center ~= nil
    local has_boss = tracker.maiden_boss ~= nil
    
    if has_boss and handle_boss_approach(current_time) then
        tracker.clear_key("combat_manager_kite_throttle")
        return
    end

    if has_regular_enemies then
        kite_around_enemies(enemies_center, maiden_pos, max_radius)
    elseif has_boss then
        move_randomly_around_maiden(maiden_pos, max_radius, 5, 12)
    else
        move_randomly_around_maiden(maiden_pos, max_radius, 8, 15)
    end
    
    tracker.clear_key("combat_manager_kite_throttle")
end

return combat_manager
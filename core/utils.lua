local utils    = {}
local enums = require "data.enums"
local tracker = require "core.tracker"
local settings = require "core.settings"
local gui = require "gui"

function utils.distance_to(target)
    local player_pos = tracker.player_position
    local target_pos

    if not target then
        return nil
    end

    if target.get_position then
        target_pos = target:get_position()
    elseif target.x then
        target_pos = target
    end

    if not player_pos or not target_pos then
        return nil
    end

    return player_pos:dist_to(target_pos)
end

function utils.distance_to_ignore_z(target)
    local player_pos = tracker.player_position
    local target_pos

    if not target then
        return nil
    end

    if target.get_position then
        target_pos = target:get_position()
    elseif target.x then
        target_pos = target
    end

    if not player_pos or not target_pos then
        return nil
    end

    return player_pos:dist_to_ignore_z(target_pos)
end

---Returns wether the player is in the zone name specified
---@param zname string
function utils.player_in_zone(zname)
    return get_current_world():get_current_zone_name() == zname
end

function utils.get_consumable_info(item)
    if not item then
        console.print("Error: Item is nil")
        return nil
    end
    local info = {}
    -- Helper function to safely get item properties
    local function safe_get(func, default)
        local success, result = pcall(func)
        return success and result or default
    end
    -- Get the item properties
    info.name = safe_get(function() return item:get_name() end, "Unknown")
    return info
end

function utils.is_in_helltide()
    local buffs = tracker.local_player:get_buffs()
    if not buffs then return false end
    
    for _, buff in ipairs(buffs) do
        if buff.name_hash == 1066539 then
            return true
        end
    end
    return false
end

function utils.get_random_point_circle(targetPos, ray, max_z_diff)
    local player = tracker.player_position
    max_z_diff = max_z_diff or 1
    
    local angle = math.random() * 2 * math.pi
    local r = ray * math.sqrt(math.random())
    local newPos = vec3:new(
        targetPos:x() + math.cos(angle) * r,
        targetPos:y() + math.sin(angle) * r,
        targetPos:z()
    )
    newPos = utility.set_height_of_valid_position(newPos)

    local z_check_passed = (max_z_diff == nil) or (max_z_diff == math.huge) or (math.abs(newPos:z() - player:z()) <= max_z_diff)

    if z_check_passed then
        if utility.is_point_walkeable(newPos) then
            return newPos
        end
    end
    

    return targetPos
end

function utils.find_closest_target(name)
    local actors = tracker.all_actors
    local closest_target = nil
    local closest_distance = math.huge

    for _, actor in pairs(actors) do
        if actor:get_skin_name():match(name) then
            local actor_pos = actor:get_position()
            local distance = utils.distance_to(actor_pos)
            if distance < closest_distance then
                closest_target = actor
                closest_distance = distance
            end
        end
    end

    if closest_target then
        return closest_target
    end
    return nil
end

function utils.find_target_by_position_n_name(targetPos, name, tol)
    tol = tol or 1
    local all_targets = tracker.all_actors
    for _, obj in ipairs(all_targets) do
        local pos = obj:get_position()
        if pos and targetPos and pos:dist_to(targetPos) < tol and obj:get_skin_name() == name then
            return obj
        end
    end
    return nil
end

function utils.find_helltide_chest_by_position(targetPos)
    tol = 2
    local all_targets = tracker.all_actors
    for _, obj in ipairs(all_targets) do
        local pos = obj:get_position()
        if pos and targetPos and pos:dist_to_ignore_z(targetPos) < tol then
            local skin_name = obj:get_skin_name()
            if enums.helltide_chests_info[skin_name] then
                return obj
            end
        end
    end
    return nil
end

function utils.find_gambling_chest_by_position(targetPos)
    local tol = 2
    local all_targets = tracker.all_actors
    for _, obj in ipairs(all_targets) do
        local pos = obj:get_position()
        if pos and targetPos and pos:dist_to_ignore_z(targetPos) < tol then
            local skin_name = obj:get_skin_name()
            if skin_name == "Hell_Prop_Chest_Rare_Locked_GamblingCurrency" then
                return obj
            end
        end
    end
    return nil
end

function utils.is_chest_already_tracked(chest, tracker, tolerance)
    tolerance = tolerance or 1
    if not chest then
        return false
    end
    local chest_pos = chest:get_position()
    if not chest_pos then
        return false
    end
    for _, tracked in ipairs(tracker.chests_found) do
        if tracked.position and chest_pos:dist_to(tracked.position) < tolerance then
            return true
        end
    end
    return false
end

function utils.get_chest_tracked(pos, tracker, tolerance)
    tolerance = tolerance or 1
    if not pos then
        return nil
    end
    for _, tracked in ipairs(tracker.chests_found) do
        if tracked then
            if tracked.position and pos:dist_to(tracked.position) < tolerance then
                return tracked
            end
        end
    end
    return nil
end

function utils.get_chest_cost(chest_name)
    local chest_info = enums.helltide_chests_info[chest_name]
    if chest_info then
        return chest_info
    else
        return nil
    end
end

function utils.find_targets_in_radius(center, radius)
    local targets_in_range = {}
    local all_targets = tracker.all_actors
    for _, obj in ipairs(all_targets) do
        local pos = obj:get_position()
        if pos and center and pos:dist_to(center) <= radius then
            table.insert(targets_in_range, obj)
        end
    end
    return targets_in_range
end

function utils.find_enemies_in_radius(center, radius)
    local targets_in_range = {}
    local all_targets = tracker.all_actors
    for _, obj in ipairs(all_targets) do
        local pos = obj:get_position()
        if pos and center and pos:dist_to(center) <= radius and obj:is_enemy() and not obj:is_dead() and not obj:is_untargetable() then
            table.insert(targets_in_range, obj)
        end
    end
    return targets_in_range
end

function utils.find_enemies_in_radius_with_z(center, radius, z_pos)
    z_pos = z_pos or 0.80
    local targets_in_range = {}
    local all_targets = tracker.all_actors
    for _, obj in ipairs(all_targets) do
        local pos = obj:get_position()
        if pos and center and pos:dist_to(center) <= radius and obj:is_enemy() and not obj:is_dead() and not obj:is_untargetable() and math.abs(tracker.player_position:z() - obj:get_position():z()) <= z_pos then
            table.insert(targets_in_range, obj)
        end
    end
    return targets_in_range
end

function utils.calculate_distance(pos1, pos2)
    -- Case 1: pos2 is a game object with get_position method
    if type(pos2.get_position) == "function" then
        return pos1:dist_to_ignore_z(pos2:get_position())
    end
    
    -- Case 2: pos2 is a vector object
    if type(pos2.x) == "function" then
        return pos1:dist_to_ignore_z(pos2)
    end
    
    -- Case 3: pos2 is our stored position table
    if type(pos2.x) == "number" then
        return pos1:dist_to_ignore_z(vec3:new(pos2.x, pos2.y, pos2.z))
    end
    
    -- If we get here, we don't know how to handle the input
    console.print("Warning: Unknown position type in calculate_distance")
    return 0
end

function utils.should_activate_alfred()
    if settings.salvage and PLUGIN_alfred_the_butler then
        local status = PLUGIN_alfred_the_butler.get_status()
        if status.enabled and #tracker.local_player:get_inventory_items() >= 25 and (status.sell_count > 0 or status.salvage_count > 0) then
            return true
        end
    end
    return false
end

function utils.should_activate_obols()
    local olbs = tracker.local_player:get_obols()
    local gamble_enabled = gui.elements.gamble_toggle:get()
    local obols_threshold = gui.elements.obols_threshold_slider:get()
    
    if gamble_enabled and olbs >= obols_threshold then
        return true
    end
    return false
end

function utils.get_closest_position(zone)
    local maiden_waypoints = enums.maiden_positions[zone]
    local closest_pos = nil
    local closest_distance = math.huge

    for _, pos in ipairs(maiden_waypoints) do
        local distance = utils.distance_to(pos)

        if distance < closest_distance then
            closest_distance = distance
            closest_pos = pos
        end
    end

    return closest_pos
end

function utils.is_loading_or_limbo()
    local current_world = world.get_current_world()
    if not current_world then
        return true
    end
    local world_name = current_world:get_name()
    return world_name:find("Limbo") ~= nil or world_name:find("Loading") ~= nil
end

function utils.is_valid_target(enemy)
    if not enemy then
        return false
    end
    
    local base_conditions = enemy:is_enemy() and not enemy:is_untargetable() and not enemy:is_dead() and not enemy:is_immune()
    
    if not base_conditions then
        return false
    end
    
    local is_special_enemy = enemy:is_elite() or enemy:is_champion() or enemy:is_boss()
    
    local enemy_name = enemy:get_skin_name() or ""
    local is_goblin = enemy_name:match("[Gg]oblin")
    
    return is_special_enemy or is_goblin
end

function utils.handle_orbwalker_auto_toggle(radius, min_enemies_count)
    if gui.elements.manual_clear_toggle:get() then
        return
    end
    
    radius = radius or 1.5
    min_enemies_count = min_enemies_count or 0


    local enemies = utils.find_enemies_in_radius(tracker.player_position, radius)
    if #enemies > min_enemies_count then
        orbwalker.set_clear_toggle(true)
    else
        orbwalker.set_clear_toggle(false)
    end
end

return utils
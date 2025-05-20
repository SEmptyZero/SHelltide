local tracker = require "core.tracker"
local gui = require "gui"

local MinHeap = {}
MinHeap.__index = MinHeap

local floor = math.floor
local abs = math.abs
local sqrt = math.sqrt
local max = math.max
local min = math.min
local time = os.time
local table_insert = table.insert
local random = math.random

local setHeight = utility.set_height_of_valid_position
local isWalkable = utility.is_point_walkeable

local cached_all_gizmos_details = nil
local last_gizmo_cache_update_time = 0
local gizmo_cache_duration = 3

function MinHeap.new(compare)
    return setmetatable({
        heap = {},
        index_map = {},
        compare = compare
    }, MinHeap)
end

function MinHeap:contains(value)
    return self.index_map[value] ~= nil
end

function MinHeap:push(value)
    self.heap[#self.heap+1] = value
    self.index_map[value] = #self.heap
    self:siftUp(#self.heap)
end

function MinHeap:peek()
    return self.heap[1]
end

function MinHeap:empty()
    return #self.heap == 0
end

function MinHeap:update(value)
    local index = self.index_map[value]
    if not index then return end
    self:siftUp(index)
    self:siftDown(index)
end

function MinHeap:siftUp(index)
    local parent = floor(index / 2)
    while index > 1 and self.compare(self.heap[index], self.heap[parent]) do
        self.heap[index], self.heap[parent] = self.heap[parent], self.heap[index]
        
        self.index_map[self.heap[index]] = index
        self.index_map[self.heap[parent]] = parent

        index = parent
        parent = floor(index / 2)
    end
end

function MinHeap:siftDown(index)
    local size = #self.heap
    while true do
        local smallest = index
        local left = 2 * index
        local right = 2 * index + 1
        if left <= size and self.compare(self.heap[left], self.heap[smallest]) then
            smallest = left
        end
        if right <= size and self.compare(self.heap[right], self.heap[smallest]) then
            smallest = right
        end
        if smallest == index then break end

        self.heap[index], self.heap[smallest] = self.heap[smallest], self.heap[index]
        
        self.index_map[self.heap[index]]   = index
        self.index_map[self.heap[smallest]] = smallest

        index = smallest
    end
end

function MinHeap:pop()
    local root = self.heap[1]
    self.index_map[root] = nil
    if #self.heap > 1 then
        self.heap[1] = self.heap[#self.heap]
        self.index_map[self.heap[1]] = 1
    end
    self.heap[#self.heap] = nil
    if #self.heap > 0 then
        self:siftDown(1)
    end
    return root
end

function vec3.__add(v1, v2)
    return vec3:new(v1:x() + v2:x(), v1:y() + v2:y(), v1:z() + v2:z())
end


local utils = require "core.utils"
local settings = require "core.settings"
local explorerlite = {
    enabled = false,
    is_task_running = false, --added to prevent boss dead pathing 
    traversal_interaction_radius = 3.0,
    is_in_gizmo_traversal_state = false, -- Added for gizmo orbwalker toggle
    toggle_anti_stuck = true,
}
local target_position = nil
local grid_size = 2            -- Size of grid cells in meters
local max_target_distance = 180 -- Maximum distance for a new target
local target_distance_states = {180, 120, 40, 20, 5}
local target_distance_index = 1
local last_position = nil
local last_move_time = 0

local last_a_star_call = 0.0
local last_call_time = 0.0

-- A* pathfinding variables
local current_path = {}
local path_index = 1

-- Neue Variable für die letzte Bewegungsrichtung
local last_movement_direction = nil

local recent_points_penalty = {}
local min_movement_to_recalculate = 1.0
local recalculate_interval = 1.5

--ai fix for kill monsters path
function explorerlite:clear_path_and_target()
    target_position = nil
    current_path = {}
    path_index = 1
    last_position = nil  -- Reset anche last_position per forzare un ricalcolo completo
    last_movement_direction = nil -- Reset last known movement direction

    if self.is_in_gizmo_traversal_state then
        orbwalker.set_clear_toggle(false)
        self.is_in_gizmo_traversal_state = false
    end
end

local function calculate_distance(point1, point2)
    if not point1 or not point2 then return math.huge end
    if not point1.x or not point2.x then -- Check if they are objects with get_position
        local p1_actual = point1.get_position and point1:get_position() or point1
        local p2_actual = point2.get_position and point2:get_position() or point2
        if not p1_actual or not p2_actual or not p1_actual.x or not p2_actual.x then return math.huge end
        return p1_actual:dist_to_ignore_z(p2_actual)
    end
    return point1:dist_to_ignore_z(point2)
end

local point_cache = setmetatable({}, { __mode = "k" })

local function get_grid_key(point)
    if not point or not point.x then return "" end -- Safe guard
    local cached_key = point_cache[point]
    if cached_key then
        return cached_key
    end

    local gx = floor(point:x() / grid_size)
    local gy = floor(point:y() / grid_size)
    local gz = floor(point:z() / grid_size)
    local new_key = gx .. "," .. gy .. "," .. gz

    point_cache[point] = new_key

    return new_key
end

local function update_recent_points(point)
    recent_points_penalty[point] = os.time() + 12
end

local function heuristic(a, b, wall_cache)
    local dx = math.abs(a:x() - b:x())
    local dy = math.abs(a:y() - b:y())
    local base_cost = grid_size * (dx + dy)

    local wall_penalty = 0
    if is_near_wall(a, wall_cache) then
        wall_penalty = 30
    end

    local recent_penalty = recent_points_penalty[a] and recent_points_penalty[a] > os.time() and 20 or 0

    return base_cost + wall_penalty + recent_penalty
end

function is_near_wall(point, current_run_cache)
    local point_key_for_cache = nil
    if current_run_cache then
        point_key_for_cache = get_grid_key(point)
        if current_run_cache[point_key_for_cache] ~= nil then
            return current_run_cache[point_key_for_cache]
        end
    end

    local wall_check_distance = 1
    local directions = {
        { x = 1, y = 0 }, { x = -1, y = 0 }, { x = 0, y = 1 }, { x = 0, y = -1 },
        { x = 1, y = 1 }, { x = 1, y = -1 }, { x = -1, y = 1 }, { x = -1, y = -1 }
    }

    local px, py, pz = point:x(), point:y(), point:z()
    for i = 1, #directions do
        local dir = directions[i]
        local check_point = vec3:new(
            px + dir.x * wall_check_distance,
            py + dir.y * wall_check_distance,
            pz
        )
        check_point = setHeight(check_point)
        if not isWalkable(check_point) then
            if current_run_cache and point_key_for_cache then
                current_run_cache[point_key_for_cache] = true
            end
            return true
        end
    end

    if current_run_cache and point_key_for_cache then
        current_run_cache[point_key_for_cache] = false
    end
    return false
end

local neighbor_directions = {
    { x = 1, y = 0 },  { x = -1, y = 0 },
    { x = 0, y = 1 },  { x = 0, y = -1 },
    { x = 1, y = 1 },  { x = 1, y = -1 },
    { x = -1, y = 1 }, { x = -1, y = -1 }
}

local max_height_difference = 1.2
local max_uphill_difference = 1.0
local max_downhill_difference = 1.4

local max_safe_direct_drop = 1.0

-- NEW HELPER FUNCTIONS START
local function determine_gizmo_type(gizmo_actor_name)
    if not gizmo_actor_name or type(gizmo_actor_name) ~= "string" then
        return "GenericTraversal" -- Default if name is invalid
    end

    if gizmo_actor_name:match("[Tt]raversal_[Gg]izmo") and gizmo_actor_name:match("Jump") then
        return "Jump"
    elseif gizmo_actor_name:match("[Tt]raversal_[Gg]izmo") and 
           (gizmo_actor_name:match("[Uu]p") or gizmo_actor_name:match("[Dd]own")) then
        return "Stair"
    else
        return "GenericTraversal" -- Fallback
    end
end

local function find_paired_gizmo(source_gizmo_info, all_gizmos_list)
    local source_name = source_gizmo_info.name
    local source_pos = source_gizmo_info.position
    local source_type = source_gizmo_info.type
    
    if source_type == "Jump" then
        local max_jump_pair_dist = 15.0
        for _, target_gizmo_info in ipairs(all_gizmos_list) do
            if target_gizmo_info.actor ~= source_gizmo_info.actor and target_gizmo_info.type == "Jump" then
                local distance = source_pos:dist_to(target_gizmo_info.position)
                if distance <= max_jump_pair_dist then
                    return target_gizmo_info
                end
            end
        end
    elseif source_type == "Stair" then
        local is_up = source_name:match("[Uu]p") ~= nil
        local max_stair_pair_dist = 18.0
        local min_height_diff = 1.2
        
        local best_match = nil
        local best_match_distance = max_stair_pair_dist
        local best_match_height_diff = 0
        
        for _, target_gizmo_info in ipairs(all_gizmos_list) do
            if target_gizmo_info.actor ~= source_gizmo_info.actor and target_gizmo_info.type == "Stair" then
                local target_is_up = target_gizmo_info.name:match("[Uu]p") ~= nil
                
                if is_up ~= target_is_up then
                    local distance = source_pos:dist_to(target_gizmo_info.position)
                    
                    local height_diff = math.abs(source_pos:z() - target_gizmo_info.position:z())
                    
                    local source_base = source_name:gsub("_[Uu]p$", ""):gsub("_[Dd]own$", "")
                    local target_base = target_gizmo_info.name:gsub("_[Uu]p$", ""):gsub("_[Dd]own$", "")
                    
                    if distance <= max_stair_pair_dist and height_diff >= min_height_diff then
                        if source_base == target_base then
                            return target_gizmo_info
                        end
                        
                        if distance < best_match_distance or (distance == best_match_distance and height_diff > best_match_height_diff) then
                            best_match = target_gizmo_info
                            best_match_distance = distance
                            best_match_height_diff = height_diff
                        end
                    end
                end
            end
        end
        
        if best_match then
            return best_match
        end
    end
    
    return nil
end

local function get_walkable_grid_entry_near_gizmo(gizmo_actual_position)
    local corrected_gizmo_pos = setHeight(vec3:new(gizmo_actual_position:x(), gizmo_actual_position:y(), gizmo_actual_position:z()))
    if isWalkable(corrected_gizmo_pos) then
        return corrected_gizmo_pos
    end
    
    local min_dist_sq_to_gizmo = math.huge
    local closest_walkable_point = nil
    local gizmo_x, gizmo_y, gizmo_z = gizmo_actual_position:x(), gizmo_actual_position:y(), gizmo_actual_position:z()
    
    local grid_x = math.floor(gizmo_x / grid_size) * grid_size
    local grid_y = math.floor(gizmo_y / grid_size) * grid_size
    
    for dx = -1, 1 do
        for dy = -1, 1 do
            local grid_point = vec3:new(
                grid_x + dx * grid_size,
                grid_y + dy * grid_size,
                gizmo_z
            )
            
            local corrected_grid_point = setHeight(grid_point)
            
            if isWalkable(corrected_grid_point) then
                local dist_sq = (corrected_grid_point:x() - gizmo_x)^2 + 
                                (corrected_grid_point:y() - gizmo_y)^2 + 
                                (corrected_grid_point:z() - gizmo_z)^2
                
                if dist_sq < min_dist_sq_to_gizmo then
                    min_dist_sq_to_gizmo = dist_sq
                    closest_walkable_point = corrected_grid_point
                end
            end
        end
    end
    
    if closest_walkable_point then
        return closest_walkable_point
    end
    
    for radius = 1, 5, 0.5 do
        for angle = 0, 315, 45 do  -- Check 8 directions
            local rad = math.rad(angle)
            local test_pos = vec3:new(
                gizmo_x + math.cos(rad) * radius,
                gizmo_y + math.sin(rad) * radius,
                gizmo_z
            )
            
            local corrected_pos = setHeight(test_pos)
            
            if isWalkable(corrected_pos) then
                -- Calculate squared distance 
                local dist_sq = (corrected_pos:x() - gizmo_x)^2 + 
                                (corrected_pos:y() - gizmo_y)^2 + 
                                (corrected_pos:z() - gizmo_z)^2
                
                if dist_sq < min_dist_sq_to_gizmo then
                    min_dist_sq_to_gizmo = dist_sq
                    closest_walkable_point = corrected_pos
                    
                    if has_line_of_sight(closest_walkable_point, gizmo_actual_position) then
                        return closest_walkable_point
                    end
                end
            end
        end
    end
    
    if closest_walkable_point then
        return closest_walkable_point
    end
    
    return nil
end

local function has_line_of_sight(point_a, point_b)
    local distance = calculate_distance(point_a, point_b)
    if distance > 50 then return false end
    local step_size = grid_size / 2
    local steps = math.ceil(distance / step_size)
    if steps == 0 then return true end

    for i = 1, steps - 1 do
        local t = i / steps
        local intermediate = vec3:new(
            point_a:x() + (point_b:x() - point_a:x()) * t,
            point_a:y() + (point_b:y() - point_a:y()) * t,
            point_a:z() + (point_b:z() - point_a:z()) * t
        )
        intermediate = setHeight(intermediate)
        if not isWalkable(intermediate) then
            return false
        end
    end
    return true
end

local function get_neighbors(point, all_gizmos_details_list)
    local neighbors = {}
    local existing_neighbor_keys = {} -- For tracking unique neighbor keys

    local px, py, pz = point:x(), point:y(), point:z()
    local current_point_key = get_grid_key(point)
    -- A point cannot be its own neighbor in this context, 
    -- so implicitly, current_point_key won't be added to existing_neighbor_keys for itself.

    -- Standard Neighbors
    for i = 1, #neighbor_directions do
        local dir = neighbor_directions[i]
        if not last_movement_direction 
           or (dir.x ~= -last_movement_direction.x or dir.y ~= -last_movement_direction.y) then
            
            local neighbor_candidate_pos = vec3:new(
                px + dir.x * grid_size,
                py + dir.y * grid_size,
                pz
            )
            local final_neighbor_pos = setHeight(neighbor_candidate_pos)
            local final_neighbor_pos_key = get_grid_key(final_neighbor_pos)

            if final_neighbor_pos_key ~= current_point_key and not existing_neighbor_keys[final_neighbor_pos_key] then
                local height_difference = final_neighbor_pos:z() - pz
                
                if isWalkable(final_neighbor_pos) then
                    local is_valid_standard_neighbor = false
                    if height_difference > 0 then -- UPHILL
                        if math.abs(height_difference) <= max_uphill_difference or is_traversable_slope(point, final_neighbor_pos, max_uphill_difference) then
                            is_valid_standard_neighbor = true
                        end
                    else -- DOWNHILL or FLAT
                        if utils.is_safe_descent(point, final_neighbor_pos, max_safe_direct_drop, is_traversable_slope, max_downhill_difference) then
                            is_valid_standard_neighbor = true
                        end
                    end

                    if is_valid_standard_neighbor and has_line_of_sight(point, final_neighbor_pos) then
                        table.insert(neighbors, { point = final_neighbor_pos, is_gizmo_entry = false })
                        existing_neighbor_keys[final_neighbor_pos_key] = true
                    end
                end
            end
        end
    end

    if all_gizmos_details_list then
        local current_gizmo_data_for_link = nil
        for _, gizmo_data in ipairs(all_gizmos_details_list) do
            if gizmo_data.walkable_entry then
                local walkable_entry_key = get_grid_key(gizmo_data.walkable_entry)
                if walkable_entry_key == current_point_key then
                    current_gizmo_data_for_link = gizmo_data
                    break
                end
            end
        end
        
        if current_gizmo_data_for_link then
            local paired_gizmo_info = find_paired_gizmo(current_gizmo_data_for_link, all_gizmos_details_list)
            if paired_gizmo_info and paired_gizmo_info.walkable_entry then
                local target_node = paired_gizmo_info.walkable_entry
                local target_node_key = get_grid_key(target_node)

                if target_node_key ~= current_point_key and not existing_neighbor_keys[target_node_key] then
                    table.insert(neighbors, { 
                        point = target_node, 
                        is_gizmo_entry = true, 
                        gizmo_type = current_gizmo_data_for_link.type .. "Link", 
                        from_gizmo_actor = current_gizmo_data_for_link.actor, 
                        to_gizmo_actor = paired_gizmo_info.actor 
                    })
                    existing_neighbor_keys[target_node_key] = true
                end
            end
        end

        for _, gizmo_data in ipairs(all_gizmos_details_list) do
            if gizmo_data.walkable_entry then
                local gizmo_entry_point = gizmo_data.walkable_entry
                local gizmo_entry_point_key = get_grid_key(gizmo_entry_point)

                if gizmo_entry_point_key ~= current_point_key and not existing_neighbor_keys[gizmo_entry_point_key] then
                    local distance_to_gizmo = calculate_distance(point, gizmo_entry_point)
                    
                    if distance_to_gizmo <= (explorerlite.traversal_interaction_radius + grid_size * 2.0) and 
                       distance_to_gizmo > 0.1 then
                        
                        if has_line_of_sight(point, gizmo_entry_point) then
                            table.insert(neighbors, { 
                                point = gizmo_entry_point, 
                                is_gizmo_entry = true, 
                                gizmo_type = gizmo_data.type .. "Approach", 
                                original_gizmo_actor = gizmo_data.actor 
                            })
                            existing_neighbor_keys[gizmo_entry_point_key] = true
                        end
                    end
                end
            end
        end
    end
    return neighbors
end

function is_traversable_slope(start_point, end_point, max_allowed_total_height_diff)
    local total_height_diff = math.abs(end_point:z() - start_point:z())
    if total_height_diff == 0 then
        return true
    end
    if total_height_diff > max_allowed_total_height_diff then
        return false
    end

    local step_count = 3
    for i = 1, step_count do
        local t = i / (step_count + 1)
        local check_point = vec3:new(
            start_point:x() + (end_point:x() - start_point:x()) * t,
            start_point:y() + (end_point:y() - start_point:y()) * t,
            start_point:z() + (end_point:z() - start_point:z()) * t
        )
        check_point = setHeight(check_point)
        
        local check_height_diff = math.abs(check_point:z() - start_point:z())
        if not isWalkable(check_point) or check_height_diff > max_height_difference * 1.2 then
            return false
        end
    end
    
    local distance_2d = math.sqrt(
        (end_point:x() - start_point:x())^2 + 
        (end_point:y() - start_point:y())^2
    )
    local height_diff = end_point:z() - start_point:z()
    local slope_angle = math.abs(math.atan2(height_diff, distance_2d))

    return slope_angle <= math.rad(35)
end

local function smooth_path(path)
    if #path < 2 then return path end
    local min_distance = grid_size
    local smooth = {}
    smooth[#smooth+1] = path[1]
    local current_index = 1
    while current_index < #path do
        local next_index = current_index + 1
        
        for i = #path, current_index + 1, -1 do
            if has_line_of_sight(path[current_index], path[i]) and 
               calculate_distance(path[current_index], path[i]) >= min_distance then
                next_index = i
                break
            end
        end
        smooth[#smooth+1] = path[next_index]
        current_index = next_index
    end
    return smooth
end

local function reconstruct_path(came_from, current)
    local reversed_path = { current }
    while came_from[get_grid_key(current)] do
        current = came_from[get_grid_key(current)]
        reversed_path[#reversed_path+1] = current
    end

    local path = {}
    for i = #reversed_path, 1, -1 do
        path[#reversed_path - i + 1] = reversed_path[i]
    end

    local filtered_path = smooth_path(path)
    return filtered_path
end


local function a_star(start, goal)
    local current_time_for_gizmo_cache = os.time()
    cached_all_gizmos_details = {}
    
    if tracker.all_actors then
        for _, actor in ipairs(tracker.all_actors) do
            if actor then
                local actor_name = actor:get_skin_name()
                local actor_pos = actor:get_position()

                if actor_name and type(actor_name) == "string" and actor_pos and not actor_pos:is_zero() and actor_name:match("[Tt]raversal_[Gg]izmo") then
                    local gizmo_type_determined = determine_gizmo_type(actor_name)
                    
                    if gizmo_type_determined == "Jump" or gizmo_type_determined == "Stair" or gizmo_type_determined == "Climb" then
                        local walkable_entry = get_walkable_grid_entry_near_gizmo(actor_pos)
                        if walkable_entry then
                            table.insert(cached_all_gizmos_details, {
                                actor = actor,
                                name = actor_name,
                                position = actor_pos,
                                type = gizmo_type_determined,
                                walkable_entry = walkable_entry
                            })
                        end
                    end
                end
            end
        end
    end
    
    last_gizmo_cache_update_time = current_time_for_gizmo_cache

    local closed_set = {}
    local came_from = {}
    local start_key = get_grid_key(start)
    local g_score = { [start_key] = 0 }
    local wall_detection_cache = {} 
    local f_score = { [start_key] = heuristic(start, goal, wall_detection_cache) }
    local iterations = 0

    local best_node = start
    local best_distance = calculate_distance(start, goal)

    local open_set = MinHeap.new(function(a, b)
        return f_score[get_grid_key(a)] < f_score[get_grid_key(b)]
    end)
    open_set:push(start)

    while not open_set:empty() do
        iterations = iterations + 1
        local current = open_set:pop()
        local current_key = get_grid_key(current)

        local current_distance = calculate_distance(current, goal)
        if current_distance < best_distance then
            best_distance = current_distance
            best_node = current
        end

        if current_distance < grid_size then
            max_target_distance = target_distance_states[1]
            target_distance_index = 1
            local raw_path = reconstruct_path(came_from, current)
            return raw_path
        end

        if iterations > 2000 then
            break
        end

        closed_set[current_key] = true

        local neighbors_data = get_neighbors(current, cached_all_gizmos_details)
        for i = 1, #neighbors_data do
            local neighbor_info = neighbors_data[i]
            local neighbor = neighbor_info.point
            local neighbor_key = get_grid_key(neighbor)

            if not closed_set[neighbor_key] then
                local tentative_g_score
                local edge_cost

                if neighbor_info.gizmo_type and neighbor_info.gizmo_type:match("Link$") then
                    edge_cost = 0.01
                else
                    edge_cost = calculate_distance(current, neighbor)
                    if neighbor_info.is_gizmo_entry then
                        if neighbor_info.gizmo_type and neighbor_info.gizmo_type:match("Approach$") then
                            edge_cost = edge_cost * 0.3
                        end
                    end
                end
                
                tentative_g_score = g_score[current_key] + edge_cost
                
                if not g_score[neighbor_key] or tentative_g_score < g_score[neighbor_key] then
                    came_from[neighbor_key] = current
                    g_score[neighbor_key] = tentative_g_score
                    f_score[neighbor_key] = tentative_g_score + heuristic(neighbor, goal, wall_detection_cache)
                    if open_set:contains(neighbor) then
                        open_set:update(neighbor)
                    else
                        open_set:push(neighbor)
                    end
                end
            end
        end
    end

    local partial_path = reconstruct_path(came_from, best_node)
    return partial_path
end

function explorerlite:set_custom_target(target)
    target_position = target
end

local function move_to_target()
    if explorerlite.is_task_running then
        return
    end

    local player_pos = tracker.player_position
    if not player_pos then return end
    
    if target_position then
        local distance_to_target = calculate_distance(player_pos, target_position)
        if distance_to_target > 500 then

            explorerlite:clear_path_and_target()
            return
        end
        
        local significant_position_change = false
        if last_position and calculate_distance(player_pos, last_position) > 25 then

            significant_position_change = true
        end

        local current_core_time = get_time_since_inject and get_time_since_inject() or os.time()
        local distance_since_last_calc = calculate_distance(player_pos, last_position or player_pos)
        local time_since_last_call = current_core_time - (last_a_star_call or 0)

        if not current_path or #current_path == 0 or path_index > #current_path 
            or significant_position_change
            or (time_since_last_call >= recalculate_interval and distance_since_last_calc >= min_movement_to_recalculate) then
            
            if explorerlite.is_in_gizmo_traversal_state and (#current_path == 0 or path_index > #current_path) then
                 orbwalker.set_clear_toggle(false)
                 explorerlite.is_in_gizmo_traversal_state = false
            end

            current_path = a_star(player_pos, target_position)
            path_index = 1
            last_a_star_call = current_core_time
            last_position = vec3:new(player_pos:x(), player_pos:y(), player_pos:z())

            if not current_path or #current_path == 0 then
                return 
            end
        end

        if not current_path or #current_path == 0 then return end

        local next_point = current_path[path_index]
        if next_point and not next_point:is_zero() then
            pathfinder.request_move(next_point)
        else
            if path_index < #current_path then
                path_index = path_index + 1
            else
                 explorerlite:clear_path_and_target()
            end
            return
        end

        if calculate_distance(player_pos, next_point) < grid_size * 1.2 then
            local reached_this_point = next_point

            local is_gizmo_entry_node = false
            if cached_all_gizmos_details then
                local reached_key = get_grid_key(reached_this_point) -- Get key for current point
                for _, gizmo_detail in ipairs(cached_all_gizmos_details) do
                    if gizmo_detail.walkable_entry then
                        local gizmo_entry_key = get_grid_key(gizmo_detail.walkable_entry) -- Get key for gizmo entry
                        if gizmo_entry_key == reached_key then
                            is_gizmo_entry_node = true
                            -- For debugging, you could add: print("ExplorerLite: Matched gizmo entry node: " .. (gizmo_detail.name or 'Unknown Gizmo') .. " at key: " .. reached_key)
                            break
                        end
                    end
                end
            end

            if is_gizmo_entry_node then
                orbwalker.set_clear_toggle(true)
                explorerlite.is_in_gizmo_traversal_state = true
            elseif explorerlite.is_in_gizmo_traversal_state then
                orbwalker.set_clear_toggle(false)
                explorerlite.is_in_gizmo_traversal_state = false
            end

            if path_index < #current_path then
                local prev_node_for_direction = player_pos
                if path_index > 1 and current_path[path_index-1] then
                    prev_node_for_direction = current_path[path_index-1]
                end
                local dx = next_point:x() - prev_node_for_direction:x()
                local dy = next_point:y() - prev_node_for_direction:y()
                local threshold = grid_size * 0.4
                if abs(dx) >= threshold or abs(dy) >= threshold then
                    last_movement_direction = { x = (abs(dx) >= threshold and (dx > 0 and 1 or -1) or 0), 
                                                y = (abs(dy) >= threshold and (dy > 0 and 1 or -1) or 0) }
                end

                update_recent_points(reached_this_point)
                path_index = path_index + 1
            else
                if calculate_distance(player_pos, target_position) < grid_size * 1.5 then
                    explorerlite:clear_path_and_target()
                else
                    current_path = {}
                    if explorerlite.is_in_gizmo_traversal_state then
                         orbwalker.set_clear_toggle(false)
                         explorerlite.is_in_gizmo_traversal_state = false
                    end
                end
            end
        end
    end
end


local function move_to_target_aggresive()
    if target_position then
        pathfinder.force_move_raw(target_position)
    else
        pathfinder.force_move_raw(vec3:new(9.204102, 8.915039, 0.000000))
    end
end

function explorerlite:is_custom_target_valid()
    if not target_position or target_position:is_zero() then
        return false
    end
    if not isWalkable(target_position) then
        return false
    end
    local player_pos = tracker.player_position
    if not player_pos then return false end

    local path = a_star(player_pos, target_position)
    if path and #path > 0 then
        return true
    end

    return false
end

-----------------------------------------------------------------------------------------------------------------------------------------
------A_START_WAYPOINT FOR WAYPOINTS NAVIGATION
-----------------------------------------------------------------------------------------------------------------------------------------
function explorerlite:a_star_waypoint(start_index, target_index, range_threshold)

    local waypoints = tracker.waypoints
    if not waypoints or type(waypoints) ~= "table" or #waypoints == 0 then
        console.print("11111111111111111111111111")
        return nil
    end

    if type(start_index) ~= "number" or start_index < 1 then
        console.print("22222222222222222222222222")
        return nil
    end

    if type(target_index) ~= "number" or target_index < 1 or target_index > #waypoints then
        console.print("33333333333333333333333333")
        return nil
    end

    if type(range_threshold) ~= "number" or range_threshold <= 0 then
        console.print("44444444444444444444444444")
        return nil
    end

    local start_node = waypoints[start_index]
    local target_node = waypoints[target_index]

    if not start_node or type(start_node.dist_to) ~= "function" then
        console.print("55555555555555555555555555")
        return nil
    end

    if not target_node or type(target_node.dist_to) ~= "function" then
        console.print("66666666666666666666666666")
        return nil
    end

    local came_from = {}
    local g_score = {}
    local f_score = {}

    for i = 1, #waypoints do
        g_score[i] = math.huge
        f_score[i] = math.huge
    end

    g_score[start_index] = 0
    f_score[start_index] = start_node:dist_to(target_node)

    local open_set = MinHeap.new(function(idx_a, idx_b)
        return f_score[idx_a] < f_score[idx_b]
    end)

    open_set:push(start_index)
    local open_set_lookup = {[start_index] = true}

    local iterations = 0
    local max_iterations = #waypoints * 10

    while not open_set:empty() do
        iterations = iterations + 1
        if iterations > max_iterations then
            return nil 
        end

        local current_idx = open_set:pop()
        open_set_lookup[current_idx] = false

        if current_idx == target_index then
            local full_path = {}
            local cur = target_index
            while cur do
                table.insert(full_path, 1, cur)
                if cur == start_index and not came_from[cur] then
                    break
                end
                cur = came_from[cur]
                if cur and (#full_path > #waypoints) then
                    return nil 
                end
            end
            if #full_path == 0 or full_path[1] ~= start_index then
                return nil
            end
            return full_path
        end

        local current_node = waypoints[current_idx]
        if not current_node or type(current_node.dist_to) ~= "function" then
            goto continue_loop
        end
        
        for i = 1, #waypoints do
            if i == current_idx then goto continue_neighbor_loop end

            local neighbor_node = waypoints[i]
            if not neighbor_node or type(neighbor_node.dist_to) ~= "function" then
                goto continue_neighbor_loop
            end

            local distance = current_node:dist_to(neighbor_node)

            if distance <= range_threshold then
                local tentative_g_score = g_score[current_idx] + distance
                if tentative_g_score < g_score[i] then
                    came_from[i] = current_idx
                    g_score[i] = tentative_g_score
                    f_score[i] = tentative_g_score + neighbor_node:dist_to(target_node)
                    
                    if not open_set_lookup[i] then
                        open_set:push(i)
                        open_set_lookup[i] = true
                    else
                        open_set:update(i) 
                    end
                end
            end
            ::continue_neighbor_loop::
        end
        ::continue_loop::
    end
    return nil
end


local STUCK_TIME_THRESHOLD = 3.0
local STUCK_DISTANCE_THRESHOLD = 0.3
local step_size = 1

local function is_player_stuck()
    local current_pos = tracker.player_position
    if not current_pos then return false end

    local current_precise_time = get_time_since_inject and get_time_since_inject() or os.time()

    if not last_position or not last_position.x then
        last_position = vec3:new(current_pos:x(), current_pos:y(), current_pos:z())
        last_move_time = current_precise_time
        return false
    end

    if calculate_distance(current_pos, last_position) >= STUCK_DISTANCE_THRESHOLD then
        last_position = vec3:new(current_pos:x(), current_pos:y(), current_pos:z())
        last_move_time = current_precise_time
        return false
    end

    if (current_precise_time - last_move_time) >= STUCK_TIME_THRESHOLD then
        return true -- Stuck
    end

    return false -- Not stuck yet
end

local function find_safe_unstuck_point()
    local player_pos = tracker.player_position
    if not player_pos then return nil end
    
    for distance_unstuck = 3, 15, 1 do
        for angle = 0, 360, 30 do
            local rad = math.rad(angle)
            local candidate_point = vec3:new(
                player_pos:x() + math.cos(rad) * distance_unstuck,
                player_pos:y() + math.sin(rad) * distance_unstuck,
                player_pos:z()
            )

            candidate_point = setHeight(candidate_point)

            if isWalkable(candidate_point) then

                return candidate_point
            end
        end

    end

    return nil
end

local movement_spell_id = {
    288106, -- Teleport Sorcerer
    358761, -- Rogue dash
    355606, -- Rogue shadow step
    1663206, -- spiritborn hunter
    1871821, -- spiritborn soar
    337031,
}

local function use_evade_to_unstuck(destination)
    local local_player = tracker.local_player
    if not local_player then return false end

    if not destination or not isWalkable(destination) then 

        return false
    end

    for _, spell_id in ipairs(movement_spell_id) do
        if local_player:is_spell_ready(spell_id) then

            local success = cast_spell.position(spell_id, destination, 3.0)
            if success then

                return true
            else

            end
        end
    end


    return false
end

local function handle_stuck_player()
    if is_player_stuck() then
        local unstuck_point = find_safe_unstuck_point()
        if unstuck_point then
            if use_evade_to_unstuck(unstuck_point) then
                local player_pos_after_evade = tracker.player_position
                if player_pos_after_evade and player_pos_after_evade.x then
                    last_position = vec3:new(player_pos_after_evade:x(), player_pos_after_evade:y(), player_pos_after_evade:z())
                end
                last_move_time = get_time_since_inject and get_time_since_inject() or os.time()
                explorerlite:clear_path_and_target()
            else
                explorerlite:set_custom_target(unstuck_point)
                current_path = {}
            end
        else
             explorerlite:clear_path_and_target() 
        end
    end
end

function explorerlite:move_to_target()
    if settings.aggresive_movement then
        move_to_target_aggresive()
    else
        move_to_target()
    end
end

on_update(function()
    if not settings.enabled then
        return
    end

    if explorerlite.is_task_running then
         return -- Don't run explorer logic if a task is running
    end

    if explorerlite.toggle_anti_stuck then
        handle_stuck_player()
    end

    local world = world.get_current_world()
    if world then
        local world_name = world:get_name()
        if world_name and (world_name:match("Sanctuary") or world_name:match("Limbo")) then -- Aggiunto check per world_name nil
            return
        end
    end
end)

on_render(function()
    if not settings.enabled or not gui.elements.debug_toggle:get() then
        return
    end

    local player_pos = tracker.player_position
    if not player_pos then
        return
    end

    -- Draw Player Position
    graphics.circle_3d(player_pos, 0.5, color_white(200), 2)
    graphics.text_3d("PLAYER\\nZ: " .. string.format("%.2f", player_pos:z()), player_pos + vec3:new(0,0,1), 10, color_white(255))

    -- Draw Target Position
    if target_position then
        local target_draw_pos = target_position
        if type(target_position.get_position) == "function" then
            target_draw_pos = target_position:get_position()
        end
        if target_draw_pos and target_draw_pos.x then
            graphics.line_3d(player_pos, target_draw_pos, color_red(150), 2)
            graphics.circle_3d(target_draw_pos, 0.7, color_red(200), 2)
            graphics.text_3d("TARGET\\nZ: " .. string.format("%.2f", target_draw_pos:z()), target_draw_pos + vec3:new(0,0,1), 10, color_red(255))
        end
    end

    -- Draw Current Path
    if current_path and #current_path > 0 then
        for i = 1, #current_path do
            local point = current_path[i]
            if point and point.x then
                local path_color = color_yellow(150)
                local text_color = color_yellow(255)
                local circle_radius = 0.3
                if i == path_index then
                    path_color = color_green(200)
                    text_color = color_green(255)
                    circle_radius = 0.5
                elseif i < path_index then
                     path_color = color_white(150)
                end

                graphics.circle_3d(point, circle_radius, path_color, 2)
                graphics.text_3d(i .. "\\nZ: " .. string.format("%.2f", point:z()), point + vec3:new(0,0,0.5), 8, text_color)

                if i > 1 then
                    local prev_point = current_path[i-1]
                    if prev_point and prev_point.x then
                         graphics.line_3d(prev_point, point, path_color, 1)
                    end
                end
            end
        end
    end

    -- Draw Neighbors Analysis (Render Safe)
    if player_pos and player_pos.x then
        local all_candidate_neighbors_data = {}
        local ppx, ppy, ppz = player_pos:x(), player_pos:y(), player_pos:z()

        for _, dir_table in ipairs(neighbor_directions) do
            local raw_n = vec3:new(ppx + dir_table.x * grid_size, ppy + dir_table.y * grid_size, ppz)
            local final_n = setHeight(raw_n)
            table.insert(all_candidate_neighbors_data, {raw = raw_n, final = final_n, dir = dir_table})
        end

        local gizmos_for_render = cached_all_gizmos_details or {}
        local valid_neighbors_data_from_func = get_neighbors(player_pos, gizmos_for_render) 
        local valid_neighbor_map_render = {}
        for _, vn_data in ipairs(valid_neighbors_data_from_func) do
             local vn_vec3 = vn_data.point 
             if vn_vec3 and vn_vec3.x then
                valid_neighbor_map_render[get_grid_key(vn_vec3)] = true
             end
        end

        graphics.text_3d("Neighbors (V/C): " .. #valid_neighbors_data_from_func .. "/" .. #all_candidate_neighbors_data, player_pos + vec3:new(0, 1.5, 2.5), 10, color_orange(255))

        for _, c_neighbor_info in ipairs(all_candidate_neighbors_data) do
            local neighbor_final_pos_render = c_neighbor_info.final
            if neighbor_final_pos_render and neighbor_final_pos_render.x then
                local is_valid_render = valid_neighbor_map_render[get_grid_key(neighbor_final_pos_render)]
                local neighbor_color_render = is_valid_render and color_purple(150) or color_white(100)
                local line_thickness_render = is_valid_render and 2 or 1
                local text_info_render = ""
                local height_diff_val_render = neighbor_final_pos_render:z() - ppz

                if isWalkable(neighbor_final_pos_render) then
                    if height_diff_val_render > 0 then 
                        if math.abs(height_diff_val_render) <= max_uphill_difference then text_info_render = "UP_STEP" else text_info_render = "UP_SLOPE?" end
                        if not is_valid_render and (math.abs(height_diff_val_render) > max_uphill_difference and not is_traversable_slope(player_pos, neighbor_final_pos_render, max_uphill_difference)) then text_info_render = "UP_SLOPE_FAIL" end
                    else 
                        if height_diff_val_render >= -0.1 then text_info_render = "FLAT" else text_info_render = "DOWN" end
                        if not utils.is_safe_descent(player_pos, neighbor_final_pos_render, max_safe_direct_drop, is_traversable_slope, max_downhill_difference) then 
                            text_info_render = "UNSAFE_DROP"
                        end
                    end
                else
                    text_info_render = "NOT_WALKABLE"
                end
                if is_valid_render then text_info_render = "VALID_N " .. text_info_render end

                graphics.line_3d(player_pos, neighbor_final_pos_render, neighbor_color_render, line_thickness_render)
                graphics.circle_3d(neighbor_final_pos_render, 0.25, neighbor_color_render, line_thickness_render)
                graphics.text_3d(text_info_render .. "\\nZ:" .. string.format("%.1f", neighbor_final_pos_render:z()) .. " dZ:" .. string.format("%.1f", height_diff_val_render), neighbor_final_pos_render + vec3:new(0,0,0.3), 6, neighbor_color_render)
            end
        end
    end
    
    -- Draw Stuck Status
    if is_player_stuck() then
        graphics.text_3d("STATUS: STUCK", player_pos + vec3:new(0, -1.5, 2), 12, color_red(255), true)
    else
        graphics.text_3d("STATUS: OK", player_pos + vec3:new(0, -1.5, 2), 10, color_green(200))
    end
end)

return explorerlite
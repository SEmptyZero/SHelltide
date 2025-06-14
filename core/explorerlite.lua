local tracker = require "core.tracker"
local gui = require "gui"
local traversal = require "core.traversal"

local MinHeap = {}
MinHeap.__index = MinHeap

local floor = math.floor
local abs = math.abs
local sqrt = math.sqrt
local max = math.max
local min = math.min
local table_insert = table.insert
local random = math.random

local setHeight = utility.set_height_of_valid_position
local isWalkable = utility.is_point_walkeable

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
    is_task_running = false,
    is_in_traversal_state = false,
    toggle_anti_stuck = true,
}
local target_position = nil
local grid_size = 1
local last_position = nil
local last_move_time = 0

local last_a_star_call = 0.0
local last_call_time = 0.0

local current_path = {}
local path_index = 1

local last_movement_direction = nil

local recent_points_penalty = {}
local min_movement_to_recalculate = 1.0
local recalculate_interval = 1.5

function explorerlite:clear_path_and_target()
    target_position = nil
    current_path = {}
    path_index = 1
    last_position = nil
    last_movement_direction = nil
    
    if self.is_in_traversal_state then
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(false)
        end
        self.is_in_traversal_state = false
    end
end

local function calculate_distance(point1, point2)
    if not point1 or not point2 then return math.huge end
    if not point1.x or not point2.x then
        local p1_actual = point1.get_position and point1:get_position() or point1
        local p2_actual = point2.get_position and point2:get_position() or point2
        if not p1_actual or not p2_actual or not p1_actual.x or not p2_actual.x then return math.huge end
        return p1_actual:dist_to_ignore_z(p2_actual)
    end
    return point1:dist_to_ignore_z(point2)
end

local point_cache = setmetatable({}, { __mode = "k" })

local function get_grid_key(point)
    if not point or not point.x then return "" end
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
    recent_points_penalty[point] = get_time_since_inject() + 12
end

local function cleanup_expired_recent_points()
    local current_time = get_time_since_inject()
    for point, expire_time in pairs(recent_points_penalty) do
        if expire_time <= current_time then
            recent_points_penalty[point] = nil
        end
    end
end

local last_cleanup_time = 0
local cleanup_interval = 30 -- seconds

local function heuristic(a, b, wall_cache)
    local current_time = get_time_since_inject()
    if current_time - last_cleanup_time > cleanup_interval then
        cleanup_expired_recent_points()
        last_cleanup_time = current_time
    end

    local dx = abs(a:x() - b:x())
    local dy = abs(a:y() - b:y())
    local base_cost = sqrt(dx*dx + dy*dy)

    local wall_penalty = 0
    if is_near_wall(a, wall_cache) then
        wall_penalty = 30
    end

    local recent_penalty = recent_points_penalty[a] and recent_points_penalty[a] > get_time_since_inject() and 20 or 0

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

local function get_neighbors(point)
    local neighbors = {}

    local px, py, pz = point:x(), point:y(), point:z()
    local current_point_key = get_grid_key(point)

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

            if final_neighbor_pos_key ~= current_point_key then
                if isWalkable(final_neighbor_pos) then
                    table.insert(neighbors, { point = final_neighbor_pos })
                end
            end
        end
    end

    traversal.add_traversal_neighbors(neighbors, point, current_point_key)

    return neighbors
end

local function optimize_path(raw_path)
    if not raw_path or #raw_path <= 2 then
        return raw_path
    end

    local optimized_path = { raw_path[1] }
    local current_index = 1

    while current_index < #raw_path do
        local current_point = raw_path[current_index]
        local furthest_reachable = current_index + 1
        
        if not traversal.is_traversal_entry_point(current_point) then
            for test_index = current_index + 2, #raw_path do
                local test_point = raw_path[test_index]
                
                if traversal.is_traversal_entry_point(test_point) then
                    break
                end
                
                if not has_line_of_sight(current_point, test_point) then
                    break
                end

                furthest_reachable = test_index
            end
        end
        
        table.insert(optimized_path, raw_path[furthest_reachable])
        current_index = furthest_reachable
    end

    return optimized_path
end

local function reconstruct_path(came_from, current)
    local reversed_path = { current }
    while came_from[get_grid_key(current)] do
        current = came_from[get_grid_key(current)]
        reversed_path[#reversed_path+1] = current
    end

    local raw_path = {}
    for i = #reversed_path, 1, -1 do
        raw_path[#reversed_path - i + 1] = reversed_path[i]
    end

    return optimize_path(raw_path)
end

local function a_star(start, goal)
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
            local raw_path = reconstruct_path(came_from, current)
            return raw_path
        end

        if iterations > 100000 then
        end

        closed_set[current_key] = true

        local neighbors_data = get_neighbors(current)
        for i = 1, #neighbors_data do
            local neighbor_info = neighbors_data[i]
            local neighbor = neighbor_info.point
            local neighbor_key = get_grid_key(neighbor)

            if not closed_set[neighbor_key] then
                local edge_cost
                
                if neighbor_info.is_traversal_entry and neighbor_info.traversal_type and neighbor_info.traversal_type:match("Link$") then
                    edge_cost = 0.1
                else
                    edge_cost = calculate_distance(current, neighbor)
                end
                
                local tentative_g_score = g_score[current_key] + edge_cost
                
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

function explorerlite:can_reach_target(start, goal)
    if not start or not goal then
        return false
    end
    
    if not isWalkable(start) or not isWalkable(goal) then
        return false
    end
    
    local path = a_star(start, goal)
    if not path or #path == 0 then
        return false
    end
    
    local last_path_point = path[#path]
    local distance_to_goal = calculate_distance(last_path_point, goal)
    
    return distance_to_goal <= grid_size * 2.0
end

function explorerlite:move_to_target()
    if explorerlite.is_task_running then
        return
    end

    local player_pos = tracker.player_position
    if not player_pos then return end
    
    if target_position then
        if not isWalkable(target_position) then
            explorerlite:clear_path_and_target()
            return
        end
        
        local distance_to_target = calculate_distance(player_pos, target_position)

        local current_core_time = get_time_since_inject and get_time_since_inject()
        local distance_since_last_calc = calculate_distance(player_pos, last_position or player_pos)
        local time_since_last_call = current_core_time - (last_a_star_call or 0)

        if not current_path or #current_path == 0 or path_index > #current_path 
            or (time_since_last_call >= recalculate_interval and distance_since_last_calc >= min_movement_to_recalculate) then
            
            current_path = a_star(player_pos, target_position)
            path_index = 1
            last_a_star_call = current_core_time
            last_position = vec3:new(player_pos:x(), player_pos:y(), player_pos:z())

            if not current_path or #current_path == 0 then
                return 
            end
            
            local last_path_point = current_path[#current_path]
            local distance_to_final_target = calculate_distance(last_path_point, target_position)
            if distance_to_final_target > grid_size * 2.0 then
                explorerlite:clear_path_and_target()
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

        local function check_upcoming_traversal()
            local look_ahead_range = math.min(3, #current_path - path_index)
            for i = 0, look_ahead_range do
                local check_index = path_index + i
                if check_index <= #current_path then
                    local point_to_check = current_path[check_index]
                    local is_traversal, pair = traversal.is_traversal_entry_point(point_to_check)
                    if is_traversal then
                        return true, pair, point_to_check
                    end
                end
            end
            return false, nil, nil
        end

        local function check_recent_traversal()
            local look_back_range = math.min(3, path_index - 1)
            for i = 0, look_back_range do
                local check_index = path_index - i
                if check_index >= 1 then
                    local point_to_check = current_path[check_index]
                    local is_traversal, pair = traversal.is_traversal_entry_point(point_to_check)
                    if is_traversal then
                        return true, pair, point_to_check
                    end
                end
            end
            return false, nil, nil
        end

        if calculate_distance(player_pos, next_point) < grid_size * 1.2 then
            local reached_this_point = next_point

            local upcoming_traversal, upcoming_pair, upcoming_point = check_upcoming_traversal()
            local recent_traversal, recent_pair, recent_point = check_recent_traversal()
            local current_traversal, current_pair = traversal.is_traversal_entry_point(reached_this_point)

            if upcoming_traversal and not explorerlite.is_in_traversal_state then
                orbwalker.set_clear_toggle(true)
                explorerlite.is_in_traversal_state = true
            end

            if not upcoming_traversal and not current_traversal and not recent_traversal and explorerlite.is_in_traversal_state then
                if not gui.elements.manual_clear_toggle:get() then
                    orbwalker.set_clear_toggle(false)
                end
                explorerlite.is_in_traversal_state = false
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
                end
            end
        end
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

    return true
end

local STUCK_TIME_THRESHOLD = 3.0
local STUCK_DISTANCE_THRESHOLD = 0.3
local step_size = 1

local function is_player_stuck()
    local current_pos = tracker.player_position
    if not current_pos then return false end

    local current_precise_time = get_time_since_inject and get_time_since_inject()

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
        return true
    end

    return false
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
                last_move_time = get_time_since_inject and get_time_since_inject()
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

on_update(function()
    if not settings.enabled then
        return
    end

    traversal.update_cache()

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

    local fk = false
    if fk then
        -- Draw Neighbor Grid (Green = Walkable, Red = Non-Walkable)
        local grid_range = 15 -- How many cells to show in each direction
        local ppx, ppy, ppz = player_pos:x(), player_pos:y(), player_pos:z()
        
        -- Calculate the grid coordinates of the player position (same as A* algorithm)
        local player_grid_x = floor(ppx / grid_size)
        local player_grid_y = floor(ppy / grid_size)
        local player_grid_z = floor(ppz / grid_size)
        
        for x = -grid_range, grid_range do
            for y = -grid_range, grid_range do
                -- Skip center (player position)
                if not (x == 0 and y == 0) then
                    -- Calculate grid coordinates relative to player
                    local grid_x = player_grid_x + x
                    local grid_y = player_grid_y + y
                    local grid_z = player_grid_z

                    -- Convert back to world coordinates (this matches A* grid exactly)
                    local grid_point = vec3:new(
                        grid_x * grid_size,
                        grid_y * grid_size,
                        grid_z * grid_size
                    )
                    grid_point = setHeight(grid_point)

                    -- Check if walkable
                    local is_walkable = isWalkable(grid_point)
                    local circle_size = 0.2

                    -- Make closer points more opaque
                    local distance_from_player = calculate_distance(player_pos, grid_point)

                    if is_walkable then
                        grid_color = color_green(200)
                    else
                        grid_color = color_red(200)
                    end

                    -- Draw the grid point
                    graphics.circle_3d(grid_point, circle_size, grid_color, 1)

                    -- Add Z coordinate for closer points
                    --if distance_from_player < 8 then
                    --    local z_info = string.format("%.1f", grid_point:z())
                    --    graphics.text_3d(z_info, grid_point + vec3:new(0,0,0.3), 18, grid_color)
                    --end
                end
            end
        end
    end

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
    
    -- Draw Stuck Status
    if is_player_stuck() then
        graphics.text_3d("STATUS: STUCK", player_pos + vec3:new(0, -1.5, 2), 12, color_red(255), true)
    else
        graphics.text_3d("STATUS: OK", player_pos + vec3:new(0, -1.5, 2), 10, color_green(200))
    end
    
    -- Draw Persistent Traversal Pairs Debug
    local persistent_pairs = traversal.get_cached_pairs()
    local persistent_count = traversal.get_persistent_pairs_count()
    
    -- Show persistent pairs count
    graphics.text_3d("PERSISTENT PAIRS: " .. persistent_count, player_pos + vec3:new(0, 1.5, 3), 12, color_cyan(255))
    
    if persistent_pairs and #persistent_pairs > 0 then
        for i, pair in ipairs(persistent_pairs) do
            if pair.walkable1 and pair.walkable2 and pair.marker1 and pair.marker2 then
                -- Draw connections between walkable points
                graphics.line_3d(pair.walkable1, pair.walkable2, color_cyan(180), 3)
                
                -- Draw walkable points (entry/exit points)
                graphics.circle_3d(pair.walkable1, 0.8, color_cyan(220), 3)
                graphics.circle_3d(pair.walkable2, 0.8, color_cyan(220), 3)
                
                -- Draw markers
                graphics.circle_3d(pair.marker1.position, 0.6, color_orange(200), 2)
                graphics.circle_3d(pair.marker2.position, 0.6, color_orange(200), 2)
                
                -- Draw lines from markers to walkable points
                graphics.line_3d(pair.marker1.position, pair.walkable1, color_orange(150), 1)
                graphics.line_3d(pair.marker2.position, pair.walkable2, color_orange(150), 1)
                
                -- Draw gizmos
                graphics.circle_3d(pair.gizmo1.position, 0.4, color_purple(200), 2)
                graphics.circle_3d(pair.gizmo2.position, 0.4, color_purple(200), 2)
                
                -- Draw lines from gizmos to markers
                graphics.line_3d(pair.gizmo1.position, pair.marker1.position, color_purple(100), 1)
                graphics.line_3d(pair.gizmo2.position, pair.marker2.position, color_purple(100), 1)
                
                -- Add text labels
                local mid_point = vec3:new(
                    (pair.walkable1:x() + pair.walkable2:x()) / 2,
                    (pair.walkable1:y() + pair.walkable2:y()) / 2,
                    (pair.walkable1:z() + pair.walkable2:z()) / 2 + 1
                )
                
                local pair_type = pair.type or "Unknown"
                graphics.text_3d("TRAVERSAL " .. i .. "\\nType: " .. pair_type .. "\\nPERSISTENT", mid_point, 10, color_cyan(255))
                
                -- Label walkable points
                graphics.text_3d("ENTRY", pair.walkable1 + vec3:new(0, 0, 0.5), 8, color_cyan(255))
                graphics.text_3d("EXIT", pair.walkable2 + vec3:new(0, 0, 0.5), 8, color_cyan(255))
                
                -- Label markers
                graphics.text_3d("M1", pair.marker1.position + vec3:new(0, 0, 0.3), 8, color_orange(255))
                graphics.text_3d("M2", pair.marker2.position + vec3:new(0, 0, 0.3), 8, color_orange(255))
                
                -- Label gizmos  
                graphics.text_3d("G1", pair.gizmo1.position + vec3:new(0, 0, 0.3), 8, color_purple(255))
                graphics.text_3d("G2", pair.gizmo2.position + vec3:new(0, 0, 0.3), 8, color_purple(255))
            end
        end
    end
end)

return explorerlite
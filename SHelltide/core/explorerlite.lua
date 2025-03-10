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
    --table_insert(self.heap, value)
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
}
local target_position = nil
local grid_size = 2            -- Size of grid cells in meters
local max_target_distance = 180 -- Maximum distance for a new target
local target_distance_states = {180, 120, 40, 20, 5}
local target_distance_index = 1
local unstuck_target_distance = 15 -- Maximum distance for an unstuck target
local stuck_threshold = 2      -- Seconds before the character is considered "stuck"
local last_position = nil
local last_move_time = 0
local stuck_check_interval = 15  -- Check every 2 seconds
local stuck_distance_threshold = 0.5  -- Consider stuck if moved less than 0.5 units
local last_stuck_check_time = 0
local last_stuck_check_position = nil
local original_target = nil

local last_a_star_call = 0.0
local last_call_time = 0.0

-- A* pathfinding variables
local current_path = {}
local path_index = 1

-- Neue Variable für die letzte Bewegungsrichtung
local last_movement_direction = nil

--ai fix for kill monsters path
function explorerlite:clear_path_and_target()
    target_position = nil
    current_path = {}
    path_index = 1
end

local function calculate_distance(point1, point2)
    if not point2.x and point2 then
        return point1:dist_to_ignore_z(point2:get_position())
    end
    return point1:dist_to_ignore_z(point2)
end

local point_cache = setmetatable({}, { __mode = "k" })

local function get_grid_key(point)
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

local function find_unstuck_target()
    console.print("Finding unstuck target.")
    local player_pos = tracker.player_position
    local valid_targets = {}

    for x = -unstuck_target_distance, unstuck_target_distance, grid_size do
        for y = -unstuck_target_distance, unstuck_target_distance, grid_size do
            local point = vec3:new(
                player_pos:x() + x,
                player_pos:y() + y,
                player_pos:z()
            )
            point = setHeight(point)

            local distance = calculate_distance(player_pos, point)
            if isWalkable(point) and distance >= 2 and distance <= unstuck_target_distance then
                --table_insert(valid_targets, point)
                valid_targets[#valid_targets+1] = point
            end
        end
    end

    if #valid_targets > 0 then
        return valid_targets[random(#valid_targets)]
    end

    return nil
end

explorerlite.find_unstuck_target = find_unstuck_target


local function handle_stuck_player()
    local current_time = time()
    local player_pos = tracker.player_position

    if not last_stuck_check_position then
        last_stuck_check_position = player_pos
        last_stuck_check_time = current_time
        return false
    end

    if current_time - last_stuck_check_time >= stuck_check_interval then
        local distance_moved = calculate_distance(player_pos, last_stuck_check_position)

        if distance_moved < stuck_distance_threshold then
            console.print("Player appears to be stuck. Finding temporary target.")
            original_target = target_position
            local temp_target = find_unstuck_target()
            if temp_target then
                target_position = temp_target
                --console.print("Temporary target set: " .. tostring(temp_target))

            else
                console.print("Failed to find temporary target.")
            end
            return true
        elseif original_target and distance_moved >= stuck_distance_threshold * 2 then
            console.print("Player has moved. Returning to original target.")
            target_position = original_target
            original_target = nil
        end

        last_stuck_check_position = player_pos
        last_stuck_check_time = current_time
    end

    return false
end

local function heuristic(a, b)
    local dx = math.abs(a:x() - b:x())
    local dy = math.abs(a:y() - b:y())
    local D = grid_size
    local D2 = grid_size * 1.414
    local wall_penalty = 0

    if is_near_wall(a) then
        wall_penalty = 30
    end

    local base_cost = D * (dx + dy) + (D2 - 2 * D) * math.min(dx, dy)
    return base_cost + wall_penalty
end

function is_near_wall(point)
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
            return true
        end
    end
    return false
end

local neighbor_directions = {
    { x = 1, y = 0 },  { x = -1, y = 0 },
    { x = 0, y = 1 },  { x = 0, y = -1 },
    { x = 1, y = 1 },  { x = 1, y = -1 },
    { x = -1, y = 1 }, { x = -1, y = -1 }
}
local function get_neighbors(point)
    local neighbors = {}
    local px, py, pz = point:x(), point:y(), point:z()
    for i = 1, #neighbor_directions do
        local dir = neighbor_directions[i]
        if not last_movement_direction 
           or (dir.x ~= -last_movement_direction.x or dir.y ~= -last_movement_direction.y) then
            local neighbor = vec3:new(
                px + dir.x * grid_size,
                py + dir.y * grid_size,
                pz
            )
            neighbor = setHeight(neighbor)
            if isWalkable(neighbor) then
                neighbors[#neighbors+1] = neighbor
            end
        end
    end

    if #neighbors == 0 and last_movement_direction then
        local back_neighbor = vec3:new(
            px - last_movement_direction.x * grid_size,
            py - last_movement_direction.y * grid_size,
            pz
        )
        back_neighbor = setHeight(back_neighbor)
        if isWalkable(back_neighbor) then
            neighbors[#neighbors+1] = back_neighbor
        end
    end

    return neighbors
end


local function has_line_of_sight(point_a, point_b)
    local distance = calculate_distance(point_a, point_b)
    local step_size = grid_size / 2
    local steps = math.ceil(distance / step_size)
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
    local closed_set = {}
    local came_from = {}
    local start_key = get_grid_key(start)
    local g_score = { [start_key] = 0 }
    local f_score = { [start_key] = heuristic(start, goal) }
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
            time_f = time()
            local raw_path = reconstruct_path(came_from, current)
            return raw_path
        end

        if iterations > 2000 then
            break
        end

        closed_set[current_key] = true

        local neighbors = get_neighbors(current)
        for i = 1, #neighbors do
            local neighbor = neighbors[i]
            local neighbor_key = get_grid_key(neighbor)
            if not closed_set[neighbor_key] then
                local tentative_g_score = g_score[current_key] + calculate_distance(current, neighbor)
                if not g_score[neighbor_key] or tentative_g_score < g_score[neighbor_key] then
                    came_from[neighbor_key] = current
                    g_score[neighbor_key] = tentative_g_score
                    f_score[neighbor_key] = tentative_g_score + heuristic(neighbor, goal)
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


local function check_if_stuck()
    --console.print("Checking if character is stuck.")
    local current_pos = tracker.player_position
    local current_time = time()

    if last_position and calculate_distance(current_pos, last_position) < 0.1 then
        if current_time - last_move_time > stuck_threshold then
            return true
        end
    else
        last_move_time = current_time
    end

    last_position = current_pos

    return false
end

explorerlite.check_if_stuck = check_if_stuck

function explorerlite:set_custom_target(target)
    target_position = target
end

function explorerlite:movement_spell_to_target(target)
    local local_player = tracker.local_player
    if not local_player then return end

    local movement_spell_id = {
        288106, -- Sorcerer teleport
        358761, -- Rogue dash
        355606, -- Rogue shadow step
        1663206, -- spiritborn hunter 
        1871821, -- spiritborn soar
    }

    if settings.use_evade_as_movement_spell then
        table_insert(movement_spell_id, 337031) -- General Evade
    end

    -- Check if the dash spell is off cooldown and ready to cast
    for _, spell_id in ipairs(movement_spell_id) do
        if local_player:is_spell_ready(spell_id) then
            -- Cast the dash spell towards the target's position
            local success = cast_spell.position(spell_id, target, 3.0) -- A little delay or else rogue goes turbo in dashing
            if success then
                console.print("Successfully used movement spell to target.")
            else
                console.print("Failed to use movement spell.")
            end
        else
            console.print("Movement spell on cooldown.")
        end
    end
end

local function move_to_target()
    if explorerlite.is_task_running then
        return  -- Do not set a path if a task is running
    end

    if target_position then
        local player_pos = tracker.player_position
        if calculate_distance(player_pos, target_position) > 500 then
            current_path = {}
            path_index = 1
            return
        end

        local current_core_time = get_time_since_inject()
        local time_since_last_call = current_core_time - last_a_star_call

        if not current_path or #current_path == 0 or path_index > #current_path or time_since_last_call >= 0.75 then
            path_index = 1
            current_path = nil
            current_path = a_star(player_pos, target_position)
            last_a_star_call = current_core_time

            if not current_path then
                console.print("No path found to target. Finding new target.")
                return
            end
        end

        local next_point = current_path[path_index]
        if next_point and not next_point:is_zero() then
            pathfinder.request_move(next_point)
            --pathfinder.force_move(next_point)
        end

        if next_point and next_point.x and not next_point:is_zero() and calculate_distance(player_pos, next_point) < grid_size then
            local direction = {
                x = next_point:x() - player_pos:x(),
                y = next_point:y() - player_pos:y()
            }
            last_movement_direction = direction
            path_index = path_index + 1
        end

        if calculate_distance(player_pos, target_position) < 2 then
            target_position = nil
            current_path = {}
            path_index = 1
        end
    else
        -- Move to center if no target
        console.print("No target found. Moving to center.")
        pathfinder.force_move_raw(vec3:new(9.204102, 8.915039, 0.000000))
    end
end

local function move_to_target_aggresive()
    if target_position then
        pathfinder.force_move_raw(target_position)
    else
        -- Move to center if no target
        console.print("No target found. Moving to center.")
        pathfinder.force_move_raw(vec3:new(9.204102, 8.915039, 0.000000))
    end
end


function explorerlite:move_to_target()
    if handle_stuck_player() then
        -- If we've just set a temporary target, we want to move to it immediately
        if settings.aggresive_movement then
            move_to_target_aggresive()
        else
            move_to_target()
        end
        return
    end

    if settings.aggresive_movement then
        move_to_target_aggresive()
    else
        move_to_target()
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
    local path = a_star(player_pos, target_position)
    if path and #path > 0 then
        return true
    end
    return false
end

-----------------------------------------------------------------------------------------------------------------------------------------
------DIJKSTRA FOR WAYPOINTS NAVIGATION
-----------------------------------------------------------------------------------------------------------------------------------------
function explorerlite:dijkstra(waypoints, start_index, target_index, range_threshold)
    local distances = {}
    local prev = {}
    local unvisited = {}
    for i, wp in ipairs(waypoints) do
        distances[i] = math.huge
        unvisited[i] = true
    end
    distances[start_index] = 0

    while true do
        local current = nil
        local current_distance = math.huge
        for i, _ in pairs(unvisited) do
            if distances[i] < current_distance then
                current_distance = distances[i]
                current = i
            end
        end

        if current == nil or current == target_index then
            break
        end

        unvisited[current] = nil

        for i, wp in ipairs(waypoints) do
            if unvisited[i] then
                local d = waypoints[current]:dist_to(wp)
                if d <= range_threshold then
                    local alt = distances[current] + d
                    if alt < distances[i] then
                        distances[i] = alt
                        prev[i] = current
                    end
                end
            end
        end
    end

    local path = {}
    local cur = target_index
    while cur do
        table.insert(path, 1, cur)
        cur = prev[cur]
    end

    if path[1] ~= start_index then
        return nil
    end

    return path
end


on_update(function()
    if not settings.enabled then
        return
    end

    if explorerlite.is_task_running then
         return -- Don't run explorer logic if a task is running
    end

    local world = world.get_current_world()
    if world then
        local world_name = world:get_name()
        if world_name:match("Sanctuary") or world_name:match("Limbo") then
            return
        end
        -- Check if the player is not in Cerrigar
        if not utils.player_in_zone("Scos_Cerrigar") then
            return -- Exit the function if not in Cerrigar
        end
    end

    local current_core_time = get_time_since_inject()
    if current_core_time - last_call_time > 0.45 then
        last_call_time = current_core_time

        local is_stuck = check_if_stuck()
        if is_stuck then
            console.print("Character was stuck. Finding new target and attempting revive")
            target_position = find_target(false)
            target_position = setHeight(target_position)
            last_move_time = time()
            current_path = {}
            path_index = 1

            local local_player = tracker.local_player
            if local_player and local_player:is_dead() then
                revive_at_checkpoint()
            end
        end
    end
end)

on_render(function()
    if not settings.enabled then
        return
    end

    -- dont slide frames here so drawings feel smooth
    if gui.elements.debug_toggle:get() then
        if target_position then
            if target_position.x then
                graphics.text_3d("TARGET_1", target_position, 20, color_red(255))
            else
                if target_position and target_position:get_position() then
                    graphics.text_3d("TARGET_2", target_position:get_position(), 20, color_orange(255))
                end
            end
        end

        if current_path then
            for i, point in ipairs(current_path) do
                local color = (i == path_index) and color_green(255) or color_yellow(255)
                --graphics.text_3d("PATH_1\n".. (point:z() - tracker.player_position:z()), point, 15, color)
                graphics.text_3d("PATH_1", point, 15, color)
            end
        end
    end
end)

return explorerlite

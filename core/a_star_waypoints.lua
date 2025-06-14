local tracker = require "core.tracker"
local explorerlite = require "core.explorerlite"

local a_star_waypoints = {}
-- MinHeap implementation for A* algorithm
local MinHeap = {}
MinHeap.__index = MinHeap

local floor = math.floor

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

function a_star_waypoints.a_star_waypoint(waypoints, start_index, target_index, range_threshold)
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
            local height_diff = math.abs((current_node:z() or current_node:y() or 0) - (neighbor_node:z() or neighbor_node:y() or 0))

            if distance <= range_threshold and height_diff <= 3 then
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

function a_star_waypoints.get_closest_waypoint_index(waypoints, target_position, min_margin)
    local min_dist = math.huge
    local closest_index = nil
    min_margin = min_margin or 2

    for i, wp in ipairs(waypoints) do
        local d = target_position:dist_to(wp)
        if d >= min_margin and d < min_dist then
            min_dist = d
            closest_index = i
        end
    end

    return closest_index
end

function a_star_waypoints.navigate_to_waypoint(waypoints, start_index, target_index)
    if not waypoints or #waypoints == 0 then
        return false
    end

    local current_index = start_index or 1

    if tracker.current_target_index == nil or tracker.current_target_index ~= target_index or tracker.a_start_waypoint_path == nil then
        tracker.current_target_index = target_index
        local range_threshold = 35
        local path = a_star_waypoints.a_star_waypoint(waypoints, current_index, target_index, range_threshold)
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
            tracker.a_start_waypoint_path = nil
            tracker.current_target_index = nil
            tracker.current_path_index = nil
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

return a_star_waypoints
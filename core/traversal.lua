local tracker = require "core.tracker"

local traversal = {}

local cached_traversal_pairs = {}
local traversal_entry_points = {}
local persistent_traversal_pairs = {}
local last_traversal_cache_update = 0
local traversal_cache_duration = 2.0

local UP_DOWN_Z_THRESHOLD = 5.0
local JUMP_DISTANCE_THRESHOLD = 8.0
local MARKER_ASSOCIATION_RADIUS = 5.0

local SPATIAL_GRID_SIZE = 15.0

local setHeight = utility.set_height_of_valid_position
local isWalkable = utility.is_point_walkeable
local grid_size = 1

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

local function get_grid_key(point)
    if not point or not point.x then return "" end
    local gx = math.floor(point:x() / grid_size)
    local gy = math.floor(point:y() / grid_size)
    local gz = math.floor(point:z() / grid_size)
    return gx .. "," .. gy .. "," .. gz
end

local function build_spatial_grid(objects)
    local grid = {}
    for _, obj in ipairs(objects) do
        local pos = obj.position
        if pos and pos.x then
            local key_x = math.floor(pos:x() / SPATIAL_GRID_SIZE)
            local key_y = math.floor(pos:y() / SPATIAL_GRID_SIZE)
            local key = key_x .. "," .. key_y
            if not grid[key] then
                grid[key] = {}
            end
            table.insert(grid[key], obj)
        end
    end
    return grid
end

local function get_nearby_from_grid(grid, position)
    local nearby_objects = {}
    if not position or not position.x then return nearby_objects end

    local key_x = math.floor(position:x() / SPATIAL_GRID_SIZE)
    local key_y = math.floor(position:y() / SPATIAL_GRID_SIZE)
    
    for dx = -1, 1 do
        for dy = -1, 1 do
            local key = (key_x + dx) .. "," .. (key_y + dy)
            if grid[key] then
                for _, obj in ipairs(grid[key]) do
                    table.insert(nearby_objects, obj)
                end
            end
        end
    end
    return nearby_objects
end

local function find_nearest_walkable_neighbor(target_point)
    local best_point = nil
    local best_distance = math.huge
    
    local corrected_point = setHeight(target_point)
    if isWalkable(corrected_point) then
        return corrected_point
    end
    
    for radius = 1, 5, 0.5 do
        for angle = 0, 315, 45 do
            local rad = math.rad(angle)
            local test_point = vec3:new(
                target_point:x() + math.cos(rad) * radius,
                target_point:y() + math.sin(rad) * radius,
                target_point:z()
            )
            
            test_point = setHeight(test_point)
            if isWalkable(test_point) then
                local distance = calculate_distance(target_point, test_point)
                if distance < best_distance then
                    best_distance = distance
                    best_point = test_point
                end
            end
        end
        
        if best_point then
            return best_point
        end
    end
    
    return best_point
end

local function get_gizmo_type(gizmo_name)
    if not gizmo_name or type(gizmo_name) ~= "string" then
        return nil
    end
    
    if gizmo_name:match("Jump") then
        return "Jump"
    elseif gizmo_name:match("Up") then
        return "Up"
    elseif gizmo_name:match("Down") then
        return "Down"
    end
    
    return nil
end

local function find_gizmo_pairs(gizmos)
    local pairs = {}
    local gizmo_grid = build_spatial_grid(gizmos)
    local processed_pairs = {}

    for _, gizmo1 in ipairs(gizmos) do
        local nearby_gizmos = get_nearby_from_grid(gizmo_grid, gizmo1.position)
        for _, gizmo2 in ipairs(nearby_gizmos) do
            if gizmo1 ~= gizmo2 then
                local key1 = gizmo1.actor:get_skin_name() .. get_grid_key(gizmo1.position)
                local key2 = gizmo2.actor:get_skin_name() .. get_grid_key(gizmo2.position)
                local pair_key = key1 < key2 and (key1 .. key2) or (key2 .. key1)

                if not processed_pairs[pair_key] then
                    if gizmo1.type == "Jump" and gizmo2.type == "Jump" then
                        local distance = calculate_distance(gizmo1.position, gizmo2.position)
                        if distance <= JUMP_DISTANCE_THRESHOLD then
                            table.insert(pairs, { gizmo1 = gizmo1, gizmo2 = gizmo2, type = "Jump" })
                        end
                    elseif (gizmo1.type == "Up" and gizmo2.type == "Down") or 
                           (gizmo1.type == "Down" and gizmo2.type == "Up") then
                        local z_diff = math.abs(gizmo1.position:z() - gizmo2.position:z())
                        local distance = calculate_distance(gizmo1.position, gizmo2.position)
                        if z_diff >= UP_DOWN_Z_THRESHOLD and distance <= JUMP_DISTANCE_THRESHOLD then
                            table.insert(pairs, { 
                                gizmo1 = gizmo1, 
                                gizmo2 = gizmo2, 
                                type = "UpDown",
                                z_difference = z_diff,
                                distance = distance
                            })
                        end
                    end
                    processed_pairs[pair_key] = true
                end
            end
        end
    end
    
    return pairs
end

local function is_actor_valid(actor)
    return actor and actor:get_skin_name() and actor:get_position() and not actor:get_position():is_zero()
end

local function get_pair_key(gizmo, marker)
    if not gizmo or not gizmo.actor or not marker or not marker.actor then
        return nil
    end
    local gizmo_name = gizmo.actor:get_skin_name() or ""
    local marker_name = marker.actor:get_skin_name() or ""
    local gizmo_pos = gizmo.actor:get_position()
    local marker_pos = marker.actor:get_position()
    
    if not gizmo_pos or not marker_pos then return nil end
    
    return string.format("%s_%.1f_%.1f_%.1f_%s_%.1f_%.1f_%.1f", 
        gizmo_name, gizmo_pos:x(), gizmo_pos:y(), gizmo_pos:z(),
        marker_name, marker_pos:x(), marker_pos:y(), marker_pos:z())
end

local function cleanup_persistent_pairs()
    local to_remove = {}
    
    for key, pair in pairs(persistent_traversal_pairs) do
        if not is_actor_valid(pair.gizmo1.actor) or 
           not is_actor_valid(pair.gizmo2.actor) or
           not is_actor_valid(pair.marker1.actor) or 
           not is_actor_valid(pair.marker2.actor) then
            table.insert(to_remove, key)
        end
    end
    
    for _, key in ipairs(to_remove) do
        persistent_traversal_pairs[key] = nil
    end
end

local function associate_markers_to_gizmos(gizmo_pairs, markers)
    local complete_pairs = {}
    
    cleanup_persistent_pairs()
    for _, persistent_pair in pairs(persistent_traversal_pairs) do
        table.insert(complete_pairs, persistent_pair)
    end
    
    local used_gizmos = {}
    local used_markers = {}
    
    for _, pair in pairs(persistent_traversal_pairs) do
        used_gizmos[pair.gizmo1.actor] = true
        used_gizmos[pair.gizmo2.actor] = true
        used_markers[pair.marker1.actor] = true
        used_markers[pair.marker2.actor] = true
    end
    
    local marker_grid = build_spatial_grid(markers)

    for _, gizmo_pair in ipairs(gizmo_pairs) do
        if not used_gizmos[gizmo_pair.gizmo1.actor] and not used_gizmos[gizmo_pair.gizmo2.actor] then
            local marker1, marker2 = nil, nil
            local best_dist1, best_dist2 = math.huge, math.huge
            
            local nearby_markers1 = get_nearby_from_grid(marker_grid, gizmo_pair.gizmo1.position)
            for _, marker in ipairs(nearby_markers1) do
                if not used_markers[marker.actor] then
                    local distance = calculate_distance(gizmo_pair.gizmo1.position, marker.position)
                    if distance <= MARKER_ASSOCIATION_RADIUS then
                        local z_diff = math.abs(gizmo_pair.gizmo1.position:z() - marker.position:z())
                        local total_distance = distance + z_diff * 0.5
                        
                        if total_distance < best_dist1 then
                            best_dist1 = total_distance
                            marker1 = marker
                        end
                    end
                end
            end
            
            local nearby_markers2 = get_nearby_from_grid(marker_grid, gizmo_pair.gizmo2.position)
            for _, marker in ipairs(nearby_markers2) do
                if not used_markers[marker.actor] and marker ~= marker1 then
                    local distance = calculate_distance(gizmo_pair.gizmo2.position, marker.position)
                    if distance <= MARKER_ASSOCIATION_RADIUS then
                        local z_diff = math.abs(gizmo_pair.gizmo2.position:z() - marker.position:z())
                        local total_distance = distance + z_diff * 0.5
                        
                        if total_distance < best_dist2 then
                            best_dist2 = total_distance
                            marker2 = marker
                        end
                    end
                end
            end
            
            if marker1 and marker2 then
                local walkable1 = find_nearest_walkable_neighbor(marker1.position)
                local walkable2 = find_nearest_walkable_neighbor(marker2.position)
                
                if walkable1 and walkable2 then
                    local new_pair = {
                        gizmo1 = gizmo_pair.gizmo1,
                        gizmo2 = gizmo_pair.gizmo2,
                        marker1 = marker1,
                        marker2 = marker2,
                        walkable1 = walkable1,
                        walkable2 = walkable2,
                        type = gizmo_pair.type
                    }
                    
                    table.insert(complete_pairs, new_pair)
                    
                    local pair_key1 = get_pair_key(gizmo_pair.gizmo1, marker1)
                    local pair_key2 = get_pair_key(gizmo_pair.gizmo2, marker2)
                    if pair_key1 and pair_key2 then
                        local persistent_key = pair_key1 .. "_" .. pair_key2
                        persistent_traversal_pairs[persistent_key] = new_pair
                    end
                    
                    used_gizmos[gizmo_pair.gizmo1.actor] = true
                    used_gizmos[gizmo_pair.gizmo2.actor] = true
                    used_markers[marker1.actor] = true
                    used_markers[marker2.actor] = true
                end
            end
        end
    end
    
    return complete_pairs
end

function traversal.update_cache()
    local current_time = get_time_since_inject()
    if current_time - last_traversal_cache_update < traversal_cache_duration then
        return
    end
    
    cleanup_persistent_pairs()
    
    cached_traversal_pairs = {}
    
    if not tracker.all_actors then
        return
    end
    
    local gizmos = {}
    local markers = {}
    
    for _, actor in ipairs(tracker.all_actors) do
        if actor then
            local actor_name = actor:get_skin_name()
            local actor_pos = actor:get_position()
            
            if actor_name and actor_pos and not actor_pos:is_zero() then
                if actor_name:match("Traversal_Gizmo") then
                    local gizmo_type = get_gizmo_type(actor_name)
                    if gizmo_type then
                        table.insert(gizmos, {
                            actor = actor,
                            name = actor_name,
                            position = actor_pos,
                            type = gizmo_type
                        })
                    end
                elseif actor_name:match("MarkerLocation_TraversalExit") then
                    table.insert(markers, {
                        actor = actor,
                        name = actor_name,
                        position = actor_pos
                    })
                end
            end
        end
    end
    
    if #gizmos >= 2 and #markers >= 2 then
        local gizmo_pairs = find_gizmo_pairs(gizmos)
        cached_traversal_pairs = associate_markers_to_gizmos(gizmo_pairs, markers)
    end

    traversal_entry_points = {}
    for _, pair in ipairs(cached_traversal_pairs) do
        if pair.walkable1 and pair.walkable2 then
            local key1 = get_grid_key(pair.walkable1)
            traversal_entry_points[key1] = pair
            local key2 = get_grid_key(pair.walkable2)
            traversal_entry_points[key2] = pair
        end
    end
    
    last_traversal_cache_update = current_time
end

function traversal.get_cached_pairs()
    return cached_traversal_pairs
end

function traversal.clear_persistent_cache()
    persistent_traversal_pairs = {}
    cached_traversal_pairs = {}
    traversal_entry_points = {}
end

function traversal.get_persistent_pairs_count()
    local count = 0
    for _ in pairs(persistent_traversal_pairs) do
        count = count + 1
    end
    return count
end

function traversal.add_traversal_neighbors(neighbors, current_point, current_point_key)
    if not cached_traversal_pairs then
        return
    end
    
    for _, pair in ipairs(cached_traversal_pairs) do
        local walkable1_key = get_grid_key(pair.walkable1)
        local walkable2_key = get_grid_key(pair.walkable2)
        
        if walkable1_key == current_point_key then
            table.insert(neighbors, {
                point = pair.walkable2,
                is_traversal_entry = true,
                traversal_type = pair.type .. "Link",
                from_marker = pair.marker1,
                to_marker = pair.marker2,
                traversal_pair = pair
            })
        elseif walkable2_key == current_point_key then
            table.insert(neighbors, {
                point = pair.walkable1,
                is_traversal_entry = true,
                traversal_type = pair.type .. "Link",
                from_marker = pair.marker2,
                to_marker = pair.marker1,
                traversal_pair = pair
            })
        end
    end
end

function traversal.is_traversal_entry_point(point)
    if not cached_traversal_pairs or not point then
        return false
    end
    
    local point_key = get_grid_key(point)
    local pair = traversal_entry_points[point_key]
    
    if pair then
        return true, pair
    end
    
    return false
end

return traversal 
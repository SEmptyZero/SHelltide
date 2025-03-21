local tracker = {
    local_player,
    player_position,

    waypoints = {},                     --EXPLORE STATES
    waypoint_index,                     --EXPLORE STATES
    a_start_waypoint_path,              --EXPLORE STATES
    current_path_index,                 --EXPLORE STATES

    chests_found = {},                  --CHESTS STATES
    current_chest,                      --CHESTS STATES
    helltide_wait_after_interaction,    --CHESTS STATES
    opened_chests_count,                --CHESTS STATES

    target_selector,                    --FIGHT STATES
    random_circle_delay_helltide,       --FIGHT STATES
    helltide_wait_after_fight,          --FIGHT STATES

    altar_found,                        --MAIDEN STATES
    unique_altars = {},                 --MAIDEN STATES
    maiden_enemies = {},                --MAIDEN STATES
    current_maiden_position,            --MAIDEN STATES
    helltide_wait_after_fight_maiden,   --MAIDEN STATES
    attempts_maiden_track,              --MAIDEN STATES

    traversal_delay_helltide,           --EXPLORE STATES
    next_cycle_helltide,                --EXPLORE STATES
    delay_back_tracking_check,          --EXPLORE STATES
    return_point,                       --EXPLORE STATES
    last_position_waypoint_index,       --EXPLORE STATES

    wait_in_town,                       --SEARCH HELLTIDE
}

function tracker.check_time(key, delay)
    local current_time = get_time_since_inject()
    if not tracker[key] then
        tracker[key] = { start = current_time, delay = delay }
    end
    if current_time - tracker[key].start >= tracker[key].delay then
        return true
    end
    return false
end

function tracker.clear_key(key)
    tracker[key] = nil
end

function tracker.time_left(key)
    if not tracker[key] then
        return "00:00:00"
    end

    local current_time = get_time_since_inject()
    local elapsed = current_time - tracker[key].start
    local remaining = tracker[key].delay - elapsed
    if remaining < 0 then
        remaining = 0
    end

    local hours = math.floor(remaining / 3600)
    local minutes = math.floor((remaining % 3600) / 60)
    local seconds = remaining % 60
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end


return tracker
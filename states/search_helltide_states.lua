local utils     = require "core.utils"
local tracker   = require "core.tracker"
local enums     = require "data.enums"
local explorerlite = require "core.explorerlite"
local traversal = require "core.traversal"

local current_city_index = 0

local search_helltide_states = {}

function is_time_between_55_and_00()
    local current_time = os.date("*t")
    local minutes = current_time.min
    return (minutes >= 55) and (minutes <= 59)
end

function is_loading_or_limbo()
    local current_world = world.get_current_world()
    if not current_world then
        return true
    end
    local world_name = current_world:get_name()
    return world_name:find("Limbo") ~= nil or world_name:find("Loading") ~= nil
end

search_helltide_states.SEARCHING_HELLTIDE = {
    enter = function(sm)
        explorerlite.toggle_anti_stuck = false
        traversal.clear_persistent_cache()
    end,
    execute = function(sm)
        if is_time_between_55_and_00() and not utils.is_in_helltide() then
            return
        end

        console.print(get_current_world():get_current_zone_name())

        if not utils.is_in_helltide() then
            console.print("HELLTIDE: SEARCHING_HELLTIDE")
            sm:change_state("TELEPORTING")
        else
            sm:change_state("INIT")
        end
    end,
    exit = function(sm)
        explorerlite.toggle_anti_stuck = true
    end,
}

search_helltide_states.TELEPORTING = {
    enter = function(sm)
        current_city_index = (current_city_index % #enums.helltide_tps) + 1
        tracker.wait_in_town = nil
        teleport_to_waypoint(enums.helltide_tps[current_city_index].id)
        sm:change_state("WAITING_FOR_TELEPORT")
        explorerlite.toggle_anti_stuck = false
    end,
    exit = function(sm)
        explorerlite.toggle_anti_stuck = true
    end,
}

search_helltide_states.WAITING_FOR_TELEPORT = {
    enter = function(sm)
        explorerlite.toggle_anti_stuck = false
    end,
    execute = function(sm)
        if is_loading_or_limbo() then
            tracker.clear_key("wait_in_town")
        end

        if utils.is_in_helltide() then
            sm:change_state("SEARCHING_HELLTIDE")
        elseif tracker.check_time("wait_in_town", 5) then
            tracker.clear_key("wait_in_town")
            sm:change_state("TELEPORTING")
        end

    end,
    exit = function(sm)
        explorerlite.toggle_anti_stuck = true
    end,
}

return search_helltide_states

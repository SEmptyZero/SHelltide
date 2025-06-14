local utils          = require "core.utils"
local tracker        = require "core.tracker"
local explorerlite   = require "core.explorerlite"
local gui            = require "gui"

local battles_states = {}

local DIST_FIGHT = 15
local DELAY_FIGHT = 1
local DIST_ENGAGE_OR_REPOSITION = 10
local FIGHT_STATE_TIMEOUT = 30

battles_states.FIGHT_ELITE_CHAMPION = {
    
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: FIGHT_ELITE_CHAMPION")
        explorerlite:clear_path_and_target()
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(true)
        end
        
        tracker.clear_key("limit_state_fight")
        if not tracker.target_selector then
            local enemies = tracker.all_actors
            for _, obj in ipairs(enemies) do
                if utils.is_valid_target(obj) and obj:get_position():dist_to(tracker.player_position) < DIST_FIGHT then
                    tracker.target_selector = obj
                    return
                end
            end
            sm:change_state("WAIT_AFTER_FIGHT")
        end
    end,
    
    execute = function(sm)
        
        if tracker.check_time("limit_state_fight", FIGHT_STATE_TIMEOUT) then
            console.print("LIMIT RACHED EXIT STATE")
            sm:change_state("WAIT_AFTER_FIGHT")
            return
        end

        local target = tracker.target_selector
        if not target or target:is_dead() then
            sm:change_state("FIGHT_ELITE_CHAMPION")
            return
        end
        
        local target_pos = target:get_position()
        if utils.distance_to(target) > DIST_ENGAGE_OR_REPOSITION then
            explorerlite:set_custom_target(target_pos)
            explorerlite:move_to_target()
        else
            if tracker.check_time("random_circle_delay_helltide", 1.3) and target_pos then
                local new_pos = utils.get_random_point_circle(target_pos, 9, 2)
                if new_pos and not explorerlite:is_custom_target_valid() then
                    explorerlite:set_custom_target(new_pos)
                    tracker.clear_key("random_circle_delay_helltide")
                end
            end

            explorerlite:move_to_target()
        end
        

    end,
    
    exit = function(sm)
        tracker.target_selector = nil
    end,
}

battles_states.WAIT_AFTER_FIGHT = {
    enter = function(sm)
        explorerlite.is_task_running = true
        console.print("HELLTIDE: WAIT_AFTER_FIGHT")
        tracker.clear_key("helltide_wait_after_fight")
        explorerlite:clear_path_and_target()
    end,
    execute = function(sm)
        if LooteerPlugin.getSettings("looting") then
            tracker.clear_key("helltide_wait_after_fight")
        end

        if tracker.check_time("helltide_wait_after_fight", DELAY_FIGHT) then
            tracker.clear_key("helltide_wait_after_fight")
            sm:change_state("EXPLORE_HELLTIDE")
        end
    end,
    exit = function(sm)
        if not gui.elements.manual_clear_toggle:get() then
            orbwalker.set_clear_toggle(false)
        end
    end,
}

return battles_states

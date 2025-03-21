local utils          = require "core.utils"
local tracker        = require "core.tracker"
local explorerlite   = require "core.explorerlite"

local battles_states = {}

local DIST_FIGHT = 15
local DELAY_FIGHT = 1

local function is_valid_target(enemy)
    return enemy
       and (enemy:is_elite() or enemy:is_champion() or enemy:is_boss())
       and enemy:is_enemy()
       and not enemy:is_untargetable()
       and not enemy:is_dead()
       and not enemy:is_immune()
end

battles_states.FIGHT_ELITE_CHAMPION = {
    
    enter = function(sm)
        explorerlite.is_task_running = false
        console.print("HELLTIDE: FIGHT_ELITE_CHAMPION")
        orbwalker.set_clear_toggle(true)
        
        tracker.clear_key("limit_state_fight")
        if not tracker.target_selector then
            local enemies = actors_manager.get_all_actors()
            for _, obj in ipairs(enemies) do
                if is_valid_target(obj) and obj:get_position():dist_to(tracker.player_position) < DIST_FIGHT then
                    tracker.target_selector = obj
                    return
                end
            end
            sm:change_state("WAIT_AFTER_FIGHT")
        end
    end,
    
    execute = function(sm)
        
        if tracker.check_time("limit_state_fight", 30) then
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
        if utils.distance_to(target) > 10 then
            explorerlite:set_custom_target(target_pos)
            explorerlite:move_to_target()
        else
            if tracker.check_time("random_circle_delay_helltide", 1.3) and target_pos then
                local new_pos = utils.get_random_point_circle(target_pos, 9, 1.2)
                explorerlite:set_custom_target(new_pos)
                if explorerlite:is_custom_target_valid() then
                    tracker.clear_key("random_circle_delay_helltide")
                end
            end
            
            if explorerlite:is_custom_target_valid() then
                explorerlite:move_to_target()
            end
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
        orbwalker.set_clear_toggle(false)
    end,
}

return battles_states

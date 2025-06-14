local settings      = require 'core.settings'
local tracker       = require "core.tracker"
local explorerlite  = require "core.explorerlite"
local enums         = require "data.enums"
local utils         = require "core.utils"
local gui           = require "gui"

local obols_states = {}

function is_loading_or_limbo()
    local current_world = world.get_current_world()
    if not current_world then
        return true
    end
    local world_name = current_world:get_name()
    return world_name:find("Limbo") ~= nil or world_name:find("Loading") ~= nil
end

function get_gambler()
    local actors = tracker.all_actors
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        if name == "TWN_Scos_Cerrigar_Vendor_Gambler" and actor:is_interactable() then
            return actor
        end
    end
    return nil
end

function get_town_portal()
    local actors = tracker.all_actors
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        if name == "TownPortal" and actor:is_interactable() then
            return actor
        end
    end
    return nil
end

local olbs_triggered_pos = nil
obols_states.OBOLS_TRIGGERED = {
    enter = function(sm)
        console.print("OLBS: OLBS_TRIGGERED")
        explorerlite.toggle_anti_stuck = false
        olbs_triggered_pos = tracker.player_position
    end,
    execute = function(sm)
        if utils.player_in_zone("Scos_Cerrigar") and not is_loading_or_limbo() then
            sm:change_state("OBOLS_IN_CERRIGAR")
            return
        end

        local nearby_enemies = utils.find_enemies_in_radius_with_z(olbs_triggered_pos, 15, 2)
            
        if #nearby_enemies > 0 then
            if not gui.elements.manual_clear_toggle:get() then
                orbwalker.set_clear_toggle(true)
            end
            local random_enemy = nearby_enemies[math.random(#nearby_enemies)]
            local pos_enemy = random_enemy:get_position()
            
            if utils.distance_to(random_enemy) > 10 then
                explorerlite:set_custom_target(pos_enemy)
                explorerlite:move_to_target()
            else
                if tracker.check_time("random_circle_delay_alfred", 1.3) and pos_enemy then
                    local new_pos = utils.get_random_point_circle(pos_enemy, 9, 2)
                    if new_pos and not explorerlite:is_custom_target_valid() then
                        explorerlite:set_custom_target(new_pos)
                        tracker.clear_key("random_circle_delay_alfred")
                    end
                end
                explorerlite:move_to_target()
            end
        else
            if not gui.elements.manual_clear_toggle:get() then
                orbwalker.set_clear_toggle(false)
            end
            if tracker.check_time("teleport_timer_3_seconds", 3) then
                teleport_to_waypoint(enums.waypoints.CERRIGAR)
                tracker.clear_key("teleport_timer_3_seconds")
            end
        end
    end,
    exit = function(sm)
        explorerlite.toggle_anti_stuck = true
    end,
}

obols_states.OBOLS_IN_CERRIGAR = {
    enter = function(sm)
        console.print("OLBS: OBOLS_IN_CERRIGAR")
        explorerlite.toggle_anti_stuck = false
    end,
    execute = function(sm)
        if not tracker.check_time("olbs_cerrigar_delay", 2) then
            return
        end

        if #tracker.local_player:get_inventory_items() >= 25 then
            sm:change_state("ALFRED_TRIGGERED")
            return
        end

        local player_obols = tracker.local_player:get_obols()   

        if player_obols < 100 then
            sm:change_state("OBOLS_BACK_TO_PORTAL")
            return
        end
        
        local gambler = get_gambler()
        local pos_gambler = vec3:new(-1675.5198974609, -599.21429443359, 36.919921875)
        explorerlite:set_custom_target(pos_gambler)
        explorerlite:move_to_target()

        if gambler then


            if utils.distance_to(gambler) < 2 or loot_manager.is_in_vendor_screen() then
                if not loot_manager.is_in_vendor_screen() then
                    interact_vendor(gambler)
                end

                if loot_manager.is_in_vendor_screen() then
                    local vendor_items = loot_manager.get_vendor_items()
                    if type(vendor_items) == "userdata" and vendor_items.size then
                        local size = vendor_items:size()     
                        local affordable_items = {}
                        
                        for i = 1, size do
                            local item = vendor_items:get(i)
                            if item then
                                local display_name = item:get_display_name()
                                local price = item:get_price()

                                local skin_name = item:get_skin_name()
                                local name = item:get_name()
                                local sno_id = item:get_sno_id()

                                local current_class = gui.get_character_class()
                                local selected_category_index = gui.elements.gamble_category[current_class]:get() + 1
                                local selected_category = gui.gamble_categories[current_class][selected_category_index]
                                
                                if display_name == selected_category and price and player_obols and price <= player_obols then
                                    local success = loot_manager.buy_item(item)
                                end
                            end
                        end
                    end
                end
            end
        end
    end,
    exit = function(sm)
        tracker.clear_key("olbs_cerrigar_delay")
        explorerlite.toggle_anti_stuck = true
    end,
}

obols_states.OBOLS_BACK_TO_PORTAL = {
    enter = function(sm)
        console.print("OLBS: OBOLS_BACK_TO_PORTAL")
    end,
    execute = function(sm)
        local pos_town_portal = vec3:new(-1656.7141113281, -598.21716308594, 36.28515625)
        explorerlite:set_custom_target(pos_town_portal)
        explorerlite:move_to_target()

        local town_portal = get_town_portal()
        if town_portal then
            if utils.distance_to(town_portal) then
                interact_vendor(town_portal)
            end
        end

        if utils.is_in_helltide() then
            sm:change_state("EXPLORE_HELLTIDE")
        end
    end,
}

return obols_states

local state_machine             = require "core.state_machine"
local explore_states            = require "states.explore_states"
local chests_states             = require "states.chests_states"
local battles_states            = require "states.battles_states"
local search_helltide_states    = require "states.search_helltide_states"
local alfred_states             = require "states.alfred_states"
local maiden_states             = require "states.maiden_states"
local utils                     = require "core.utils"
local tracker                   = require "core.tracker"
local explorerlite              = require "core.explorerlite"
local settings                  = require "core.settings"
local gui                       = require "gui"
local obols_states               = require "states.obols_states"

local helltide_states = {}
for k, v in pairs(explore_states) do
    helltide_states[k] = v
end
for k, v in pairs(chests_states) do
    helltide_states[k] = v
end
for k, v in pairs(battles_states) do
    helltide_states[k] = v
end
for k, v in pairs(search_helltide_states) do
    helltide_states[k] = v
end
for k, v in pairs(alfred_states) do
    helltide_states[k] = v
end
for k, v in pairs(maiden_states) do
    helltide_states[k] = v
end
for k, v in pairs(obols_states) do
    helltide_states[k] = v
end

local helltide_task = {
    name = "Explore Helltide",
    sm = nil,

    shouldExecute = function()
        return true
    end,

    Execute = function(self)
        if not self.sm then
            self.sm = state_machine.new("SEARCHING_HELLTIDE", helltide_states)
            --self.sm = state_machine.new("INIT", helltide_states)
            --self.sm = state_machine.new("TEST_STATE", helltide_states)
            tracker.chests_found = {}
            tracker.opened_chests_count = 0
            tracker.clear_key("helltide_delay_trigger_maiden")
            console.print("STATE MACHINE OK")
        end

        if tracker.local_player and tracker.local_player:is_dead() then
            if self.sm and self.sm:get_current_state() ~= "RESURRECT_AND_RETURN" then 
                console.print("HELLTIDE: Player died.")
                tracker.death_recovery_waypoint_index = tracker.waypoint_index
                console.print("HELLTIDE: Stored death recovery waypoint index: " .. tracker.death_recovery_waypoint_index)
                
                self.sm:change_state("RESURRECT_AND_RETURN")
                return
            end
        end

        self.sm:update()
    end,

    get_next_helltide_msg = function(self)
        if is_time_between_55_and_00() then
            local now = os.time()
            local current_time = os.date("*t", now)
            local remaining_seconds = (60 - current_time.min) * 60 - current_time.sec
            local minutes = math.floor(remaining_seconds / 60)
            local seconds = remaining_seconds % 60
            return string.format("%02d:%02d", minutes, seconds)
        else
            return ""
        end
    end,

    get_helltide_time_remaining = function(self)
        if not is_time_between_55_and_00() then
            local now = os.time()
            local current_time = os.date("*t", now)
            local remaining_seconds = (55 - current_time.min) * 60 - current_time.sec
            local minutes = math.floor(remaining_seconds / 60)
            local seconds = remaining_seconds % 60
            return string.format("%02d:%02d", minutes, seconds)
        else
            return ""
        end
    end,

    get_chests_opened_msg = function(self)
        return tracker.opened_chests_count
    end,

    get_missed_chests_msg = function(self)
        if #tracker.chests_found == 0 then
            return "0"
        end

        local string_complete = #tracker.chests_found .."\n"
        for i = 1, #tracker.chests_found, 2 do
            string_complete = string_complete .. tracker.chests_found[i].name
            if i + 1 <= #tracker.chests_found then
                string_complete = string_complete .. "   |   " .. tracker.chests_found[i+1].name
            end
            string_complete = string_complete .. "\n"
        end
    
        return string_complete
    end,

    get_next_maiden_msg = function(self)
        if tracker.helltide_switch_to_farm_chests == nil then
            return tracker.time_left("helltide_switch_to_farm_maiden")
        end

        return ""
    end,

    get_next_chests_msg = function(self)
        if tracker.helltide_switch_to_farm_maiden == nil then
            return tracker.time_left("helltide_switch_to_farm_chests")
        end

        return ""
    end,
}

return helltide_task

local gui          = require "gui"
local task_manager = require "core.task_manager"
local settings     = require "core.settings"
local tracker      = require "core.tracker"

local function update_locals()
    tracker.local_player = get_local_player()
    tracker.player_position = tracker.local_player and tracker.local_player:get_position()
    tracker.all_actors = actors_manager.get_all_actors()
end

local function main_pulse()
    settings:update_settings()
    if not tracker.local_player or not settings.enabled then return end
    task_manager.execute_tasks()
end

local function render_pulse()
    if not tracker.local_player or not settings.enabled then return end
    local current_task = task_manager.get_current_task()
    gui.draw_status(current_task)
end

local colors = {
    common_monsters = color_white(255),
    champion_monsters = color_blue(255),
    elite_monsters = color_orange(255),
    boss_monsters = color_red(255),

    chests = color_white(255),
    resplendent_chests = color_purple(255),
    resources = color_green_pastel(255),

    shrines = color_gold(255),
    objectives = color_green(255),
}

gui.elements.debug_toggle:set(false)

SHelltidePlugin = {
    enable = function()
        gui.elements.main_toggle:set(true)
    end,
    disable = function()
        gui.elements.main_toggle:set(false)
    end,
    status = function()
        return {
            ['enabled'] = gui.elements.main_toggle:get(),
            ['task'] = task_manager.get_current_task().sm:get_current_state()
        }
    end,
}

on_update(function()
    update_locals()
    main_pulse()
end)

on_render_menu(gui.render)
on_render(render_pulse)
on_render(function()
    if type(tracker.waypoints) == "table" and gui.elements.debug_toggle:get() then
        for i, waypoint in ipairs(tracker.waypoints) do
            local dist = tracker.player_position:dist_to(waypoint)
            if dist <= 13 then
                graphics.circle_3d(waypoint, 1, colors.objectives, 1)
                graphics.text_3d("WP " .. i, waypoint, 15, colors.objectives)
            end
        end
    end
    --graphics.circle_3d(vec3:new(216.226562, -601.409180, 6.959961), 140, color_red(255), 1)
    --graphics.circle_3d(vec3:new(216.226562, -601.409180, 6.959961), 120, colors.objectives, 1)
    --if tracker.current_maiden_position and gui.elements.debug_toggle:get() then
    --    graphics.circle_3d(tracker.current_maiden_position, 16, colors.objectives, 1)
    --end
    --graphics.text_3d(tostring(get_player_position():x()), get_player_position(), 16, color_white(255))
    --if tracker.player_position and gui.elements.debug_toggle:get() then
    --    graphics.circle_3d(tracker.player_position, 3, colors.objectives, 1)
    --    graphics.text_3d(tracker.player_position:x() .. " | " .. tracker.player_position:y() .. " | " .. tracker.player_position:z(), tracker.player_position, 15, colors.objectives)
    --end
end)

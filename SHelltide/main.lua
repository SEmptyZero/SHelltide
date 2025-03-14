local gui          = require "gui"
local task_manager = require "core.task_manager"
local settings     = require "core.settings"
local tracker      = require "core.tracker"

local function update_locals()
    tracker.local_player = get_local_player()
    tracker.player_position = tracker.local_player and tracker.local_player:get_position()
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
                --graphics.circle_3d(waypoint, 5, colors.objectives, 1)
                graphics.circle_3d(waypoint, 1, colors.objectives, 1)
                --graphics.text_3d("WP " .. i .."\nZ: " .. waypoint:z(), waypoint, 15, colors.objectives)
                graphics.text_3d("WP " .. i, waypoint, 15, colors.objectives)
            end
        end
    end
    --graphics.circle_3d(vec3:new(216.226562, -601.409180, 6.959961), 140, color_red(255), 1)
    --graphics.circle_3d(vec3:new(216.226562, -601.409180, 6.959961), 120, colors.objectives, 1)
    if tracker.target_selector then
        --graphics.circle_3d(tracker.target_selector:get_position(), 16, colors.objectives, 1)
    end
    --graphics.text_3d(tostring(get_player_position():x()), get_player_position(), 16, color_white(255))
    --graphics.circle_3d(get_cursor_position(), 2, colors.objectives, 1)
end)

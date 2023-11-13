const std = @import("std");
const prism = @import("prism");
const needle = @import("needle.zig");

pub fn main() !void {
    try prism.init();
    try prism.graphics.init();
    const window = try prism.Window.create(.{
        .size = .{
            .width = 800,
            .height = 480,
        },
        .interaction = .{
            .exit_on_close = true,
        },
        .title = "~ S T I T C H I N G ~",
    });
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    const renderer = try prism.graphics.Renderer.create(window, allocator);
    defer renderer.destroy();
    defer window.destroy();
    const pid = try std.Thread.spawn(.{}, needle.init, .{ renderer, "script.lua" });
    defer pid.join();
    defer needle.deinit();
    prism.run();
}

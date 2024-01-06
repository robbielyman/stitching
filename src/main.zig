const std = @import("std");
const prism = @import("prism");
const Needle = @import("needle.zig");
const ziglua = @import("ziglua");

pub fn main() !void {
    try prism.init();
    defer prism.deinit();
    const graphics = try prism.Graphics(.Native).init();
    const window = try prism.Window.create(.{
        .size = .{
            .width = 800,
            .height = 480,
        },
        .exit_on_close = true,
        .title = "~ S T I T C H I N G ~",
    });
    defer window.destroy();

    const context = prism.Graphics(.Native).RenderingContext.create(graphics);
    defer context.destroy();

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const filename = try parseArgs(allocator);

    var needle: Needle = .{
        .lvm = try ziglua.Lua.init(allocator),
        .context = context,
        .widget = undefined,
    };
    defer needle.deinit();
    try needle.init(allocator, filename);

    window.setContent(needle.widget);

    prism.run();
}

fn parseArgs(allocator: std.mem.Allocator) ![]const u8 {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    const filename = args.next() orelse return error.NoFilename;
    return try allocator.dupeZ(u8, filename);
}

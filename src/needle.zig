const std = @import("std");
const prism = @import("prism");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const wrap = ziglua.wrap;

var context: *prism.graphics.Renderer = undefined;
var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var lvm: Lua = undefined;

pub fn init(render_context: *prism.graphics.Renderer, filename: [:0]const u8) !void {
    context = render_context;
    gpa = .{};
    const allocator = gpa.allocator();
    lvm = try Lua.init(allocator);
    lvm.openLibs();

    lvm.newTable();
    register_stitching("pixel_shader_compile", wrap(pixel_shader_compile));
    register_stitching("pixel_shader_submit", wrap(pixel_shader_submit));

    lvm.setGlobal("_stitching");

    const cmd = try std.fmt.allocPrint(allocator, "dofile(\"{s}\")\n", .{filename});
    defer allocator.free(cmd);
    try run_code(cmd);
}

pub fn deinit() void {
    lvm.close();
    _ = gpa.deinit();
}

fn register_stitching(name: [:0]const u8, f: ziglua.CFn) void {
    lvm.pushFunction(f);
    lvm.setField(-2, name);
}

fn pixel_shader_compile(l: *Lua) i32 {
    if (l.getTop() != 1)
        l.raiseErrorStr("requires one argument!", .{});
    const source = l.toBytes(1) catch unreachable;
    const pipeline = context.compilePixelShader(source) catch l.raiseErrorStr("shader compilation failed!", .{});
    l.pushLightUserdata(pipeline.handle);
    return 1;
}

fn pixel_shader_submit(l: *Lua) i32 {
    if (l.getTop() != 1)
        l.raiseErrorStr("requires one argument!", .{});
    const pipeline = l.toUserdata(anyopaque, 1) catch unreachable;
    context.commands.append(.{
        .PixelShader = .{
            .pipeline = pipeline,
        },
    }) catch @panic("OOM!");
    return 0;
}

fn run_code(code: []const u8) !void {
    try lvm.loadBuffer(code, "s_run_code", .text);
    try docall(&lvm, 0, 0);
}

fn lua_print(l: *Lua) i32 {
    const n = l.getTop();
    l.checkStackErr(2, "too many results to print");
    _ = l.getGlobal("print") catch unreachable;
    l.insert(1);
    l.call(n, 0);
    return 0;
}

fn message_handler(l: *Lua) i32 {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    const t = l.typeOf(1);
    switch (t) {
        .string => {
            const msg = l.toBytes(1) catch unreachable;
            l.pop(1);
            l.traceback(l, msg, 6);
        },
        else => {
            const msg = std.fmt.allocPrintZ(
                allocator,
                "(error object is a {s} value)",
                .{l.typeName(t)},
            ) catch @panic("OOM!");
            l.pop(1);
            l.traceback(l, msg, 6);
        },
    }
    return 1;
}

fn docall(l: *Lua, nargs: i32, nres: i32) !void {
    const base = l.getTop() - nargs;
    l.pushFunction(wrap(message_handler));
    l.insert(base);
    l.protectedCall(nargs, nres, base) catch {
        l.remove(base);
        _ = lua_print(l);
    };
    l.remove(base);
}

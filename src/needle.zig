const std = @import("std");
const prism = @import("prism");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const wrap = ziglua.wrap;
const Graphics = prism.Graphics(.Native);
const Needle = @This();

lvm: Lua,
context: Graphics.RenderingContext,
widget: prism.Widget,

pub fn init(
    self: *Needle,
    allocator: std.mem.Allocator,
    filename: []const u8,
) !void {
    self.lvm.openLibs();

    self.lvm.newTable();
    self.registerStitching("pixel_shader_compile", wrap(pixelShaderCompile));
    self.registerStitching("pixel_shader_widget", wrap(pixelShaderWidget));
    self.lvm.pushLightUserdata(self);
    self.lvm.setField(-2, "_ctx");

    self.lvm.setGlobal("_stitching");

    const cmd = try std.fmt.allocPrint(allocator, "dofile(\"{s}\")\n", .{filename});
    defer allocator.free(cmd);
    try self.runCode(cmd);
}

pub fn deinit(self: *Needle) void {
    defer self.lvm.close();
    self.runCode("cleanup()") catch return;
}

fn registerStitching(self: *Needle, name: [:0]const u8, f: ziglua.CFn) void {
    self.lvm.pushFunction(f);
    self.lvm.setField(-2, name);
}

fn getContext(l: *Lua) !*Needle {
    _ = try l.getGlobal("_stitching");
    const kind = l.getField(-1, "_ctx");
    if (kind != .light_userdata) return error.BadType;
    return try l.toUserdata(Needle, -1);
}

fn pixelShaderCompile(l: *Lua) i32 {
    if (l.getTop() != 1)
        l.raiseErrorStr("requires one argument!", .{});
    const source_ptr = l.toString(1) catch l.raiseErrorStr("string expected, got %s", .{l.typeName(l.typeOf(1)).ptr});
    const ctx = getContext(l) catch l.raiseErrorStr("unable to get context!", .{});
    const pipeline = Graphics.PixelShader.define(
        ctx.context,
        std.mem.sliceTo(source_ptr, 0),
        null,
        null,
    ) catch l.raiseErrorStr("compilation failed!", .{});
    l.pushLightUserdata(pipeline.handle);
    return 1;
}

fn pixelShaderWidget(l: *Lua) i32 {
    if (l.getTop() != 1)
        l.raiseErrorStr("requires one argument!", .{});
    const pipeline = l.toUserdata(anyopaque, 1) catch l.raiseErrorStr("shader (userdata) expected got %s", .{l.typeName(l.typeOf(1)).ptr});
    const shader: Graphics.PixelShader = .{
        .handle = pipeline,
    };
    const ctx = getContext(l) catch l.raiseErrorStr("unable to get context!", .{});
    const widget = shader.widget(
        ctx.context,
        .{ .fraction = 1 },
        .{ .fraction = 1 },
        null,
    ) catch l.raiseErrorStr("error creating widget!", .{});
    l.pushLightUserdata(widget.handle);

    ctx.widget = widget;
    return 1;
}

fn runCode(self: *Needle, code: []const u8) !void {
    try self.lvm.loadBuffer(code, "s_run_code", .text);
    try doCall(&self.lvm, 0, 0);
}

fn luaPrint(l: *Lua) i32 {
    const n = l.getTop();
    l.checkStackErr(2, "too many results to print");
    _ = l.getGlobal("print") catch unreachable;
    l.insert(1);
    l.call(n, 0);
    return 0;
}

fn messageHandler(l: *Lua) i32 {
    var buf: [8 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    const t = l.typeOf(1);
    switch (t) {
        .string => {
            const msg = l.toBytes(1) catch unreachable;
            l.pop(1);
            l.traceback(l, msg, 1);
        },
        else => {
            const msg = std.fmt.allocPrintZ(
                allocator,
                "(error object is a {s} value)",
                .{l.typeName(t)},
            ) catch @panic("OOM!");
            l.pop(1);
            l.traceback(l, msg, 1);
        },
    }
    return 1;
}

fn doCall(l: *Lua, nargs: i32, nres: i32) !void {
    const base = l.getTop() - nargs;
    l.pushFunction(wrap(messageHandler));
    l.insert(base);
    l.protectedCall(nargs, nres, base) catch {
        l.remove(base);
        _ = luaPrint(l);
    };
    l.remove(base);
}

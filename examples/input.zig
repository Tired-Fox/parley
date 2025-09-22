const std = @import("std");
const parley = @import("parley");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allo = arena.allocator();

    var value = try parley.Input.init(allo, .{ .prompt = "Enter your tag:" })
        .interact();
    defer allo.free(value);

    std.debug.print("RESULT: {s}\n", .{value});

    value = try parley.Input.init(arena.allocator(), .{
        .prompt = "Enter your tag:",
        .password = .hidden,
        .password_toggle = .{ .code = .char(' ') },
    })
        .interact();
    defer allo.free(value);

    std.debug.print("RESULT: {s}\n", .{value});

    var valueOpt = try parley.Input.init(allo, .{ .prompt = "Enter your tag:" })
        .interactOpt();
    defer allo.free(value);

    if (valueOpt) |v| {
        std.debug.print("RESULT: {s}\n", .{v});
    } else {
        std.debug.print("RESULT: \"\"\n", .{});
    }

    valueOpt = try parley.Input.init(arena.allocator(), .{
        .prompt = "Enter your tag:",
        .password = .replaced,
        .password_toggle = .{ .code = .char(' ') },
    })
        .interactOpt();
    defer allo.free(value);

    if (valueOpt) |v| {
        std.debug.print("RESULT: {s}\n", .{v});
    } else {
        std.debug.print("RESULT: \"\"\n", .{});
    }
}

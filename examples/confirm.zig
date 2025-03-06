const std = @import("std");
const parley = @import("parley");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // Prompt the user allowing them to press `Enter` for the default value of `true`
    _ = try parley.Confirm.init(arena.allocator(), .{ .prompt = "Are you a programmer?", .default = true })
        .interact();

    // Prompt the user allowing them to press `q` or `esc` for a `null` response
    // erase the prompt after interaction
    _ = try parley.Confirm.init(arena.allocator(), .{ .prompt = "Is the sky blue?", .report = false })
        .interactOpt();

    // Prompt the user allowing forcing them to select `yes` or `no`
    _ = try parley.Confirm.init(arena.allocator(), .{ .prompt = "Do you have 20 fingers?" })
        .interact();
}

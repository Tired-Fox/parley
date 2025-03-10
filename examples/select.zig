const std = @import("std");
const parley = @import("parley");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const result = try parley.Select
        .init(arena.allocator(), .{
            .prompt = "Select Prompt:",
            .items = &.{
                "One",
                "Two",
                "Three",
                "Four",
                "Five",
                "Six",
                "Seven",
            },
            .hint = .default,
            .max_length = 4,
        })
        .interact();
    std.debug.print("{d}\n", .{ result });

    const result_opt = try parley.Select
        .init(arena.allocator(), .{
            .prompt = "Optional Select Prompt:",
            .items = &.{
                "One",
                "Two",
                "Three",
                "Four",
                "Five",
                "Six",
                "Seven",
            },
            .hint = .custom("[up/down - Move]"),
            .report = false,
        })
        .interactOpt();
    std.debug.print("{?}\n", .{ result_opt });
}

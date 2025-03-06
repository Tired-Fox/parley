const std = @import("std");
const parley = @import("parley");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const result = try parley.MultiSelect
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
    {
        defer arena.allocator().free(result);
        std.debug.print("{any}\n", .{ result });
    }

    const result_opt = try parley.MultiSelect
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
    if (result_opt) |r| {
        defer arena.allocator().free(r);
        std.debug.print("{any}\n", .{ r });
    }
}

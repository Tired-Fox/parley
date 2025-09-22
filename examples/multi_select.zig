const std = @import("std");
const parley = @import("parley");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = try parley.MultiSelect
        .init(allocator, .{
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
        defer allocator.free(result);
        std.debug.print("{any}\n", .{ result });
    }

    const result_opt = try parley.MultiSelect
        .init(allocator, .{
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
        defer allocator.free(r);
        std.debug.print("{any}\n", .{ r });
    }
}

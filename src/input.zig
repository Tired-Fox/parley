const std = @import("std");
const zerm = @import("zerm");

const getTermSize = zerm.action.getTermSize;
const Stream = zerm.Stream;
const Line = zerm.action.Line;
const Cursor = zerm.action.Cursor;
const Character = zerm.action.Character;
const EventStream = zerm.event.EventStream;
const execute = zerm.execute;

pub const Options = struct {
    /// Whether to report the chosen selection after interaction
    report: bool = true,
    /// Prompt to display to the user
    prompt: ?[]const u8 = null,

    /// The method for displaying hidden passwords
    ///
    /// Setting this value will also set this input to be a password input
    password: ?enum { hidden, replaced } = null,
    /// The key match that should be used to toggle whether the password should
    /// be displayed or not
    password_toggle: ?zerm.event.KeyEvent.Match = null,
};

allocator: std.mem.Allocator,
options: Options,

pub fn init(allocator: std.mem.Allocator, options: Options) @This() {
    return .{
        .allocator = allocator,
        .options = options,
    };
}

/// Interact with the user allowing them to enter text or `quit`.
pub fn interactOnOpt(self: *const @This(), stream: Stream) !?[]const u8 {
    var event_stream = EventStream.init(self.allocator);
    defer event_stream.deinit();
    const console_output = zerm.Utf8ConsoleOutput.init();
    defer console_output.deinit();

    var input = std.ArrayList(u21).init(self.allocator);
    var pos: usize = 0;

    if (self.options.prompt) |prompt| {
        try execute(stream, .{ prompt, ' ', Cursor { .save = true }});
    } else {
        try execute(stream, .{ Cursor { .save = true }});
    }

    var hidden = self.options.password != null;

    while (true) {
        if (try event_stream.parseEvent()) |event| {
            switch (event) {
                .key => |key| {
                    if (key.match(.{ .code = .esc })) {
                        input.deinit();
                        return null;
                    }

                    if (key.match(.{ .code = .enter })) break;

                    if (key.match(.{ .code = .backspace }) and input.items.len > 0) {
                        _ = input.orderedRemove(pos -| 1);
                        pos -|= 1;
                        if (hidden and self.options.password == .hidden) continue;
                        try execute(stream, .{
                            Cursor { .left = 1 },
                            Character { .delete = 1 },
                        });
                    }

                    if (!hidden and key.match(.{ .code = .left }) and pos > 1) {
                        pos -= 1;
                        try execute(stream, .{ Cursor { .left = 1 }});
                    }

                    if (!hidden and key.match(.{ .code = .right }) and pos < input.items.len) {
                        pos += 1;
                        try execute(stream, .{ Cursor { .right = 1 }});
                    }

                    if (!hidden and key.match(.{ .code = .end }) and pos < input.items.len) {
                        try execute(stream, .{ Cursor { .right = @intCast(input.items.len -| pos) }});
                        pos = input.items.len;
                    }

                    if (!hidden and key.match(.{ .code = .home }) and pos > 1) {
                        try execute(stream, .{ Cursor { .left = @intCast(pos) }});
                        pos = 0;
                    }

                    if (self.options.password) |password| {
                        if (self.options.password_toggle) |toggle_key| {
                            if (key.match(toggle_key)) {
                                if (hidden) {
                                    hidden = false;

                                    const data = try charToUtf8(self.allocator, input.items);
                                    defer self.allocator.free(data);

                                    try execute(stream, .{
                                        Cursor { .restore = true },
                                        Line { .erase = .to_end },
                                        data
                                    });
                                } else {
                                    hidden = true;
                                    switch (password) {
                                        .hidden => try execute(stream, .{
                                            Cursor { .restore = true },
                                            Line { .erase = .to_end },
                                        }),
                                        .replaced => {
                                            var replacement = std.ArrayList(u8).init(self.allocator);
                                            defer replacement.deinit();
                                            try replacement.appendNTimes('*', input.items.len);
                                            try execute(stream, .{
                                                Cursor { .restore = true },
                                                Line { .erase = .to_end },
                                                replacement.items
                                            });
                                        }
                                    }
                                }
                                continue;
                            }
                        }
                    }

                    if (key.code == .character and key.kind == .press) {
                        try input.insert(pos, key.code.character);

                        if (hidden) {
                            if (self.options.password == .replaced) try execute(stream, .{ '*' });
                        } else if (pos < input.items.len - 1) {
                            try execute(stream, .{
                                Character { .insert = 1 },
                                key.code.character,
                            });
                        } else {
                            try execute(stream, .{ key.code.character });
                        }
                        pos += 1;
                    }
                },
                else => {}
            }
        }
    }

    if (self.options.report) {
        try execute(stream, .{ "\n" });
    } else {
        try execute(stream, .{ Line { .delete = 1 }});
    }

    if (input.items.len == 0) {
        input.deinit();
        return  null;
    }

    return try charToUtf8(self.allocator, input.items);
}

/// Interact with the user allowing them to enter text.
pub fn interactOn(self: *const @This(), stream: Stream) ![]const u8 {
    var event_stream = EventStream.init(self.allocator);
    defer event_stream.deinit();
    const console_output = zerm.Utf8ConsoleOutput.init();
    defer console_output.deinit();

    var input = std.ArrayList(u21).init(self.allocator);
    defer input.deinit();
    var pos: usize = 0;

    if (self.options.prompt) |prompt| {
        try execute(stream, .{ prompt, ' ', Cursor { .save = true }});
    } else {
        try execute(stream, .{ Cursor { .save = true }});
    }

    var hidden = self.options.password != null;

    while (true) {
        if (try event_stream.parseEvent()) |event| {
            switch (event) {
                .key => |key| {
                    if (
                        key.match(.{ .code = .enter })
                        and input.items.len > 0
                    ) break;

                    if (key.match(.{ .code = .backspace }) and input.items.len > 0) {
                        _ = input.orderedRemove(pos -| 1);
                        pos -|= 1;
                        if (hidden and self.options.password == .hidden) continue;
                        try execute(stream, .{
                            Cursor { .left = 1 },
                            Character { .delete = 1 },
                        });
                    }

                    if (!hidden and key.match(.{ .code = .left }) and pos > 1) {
                        pos -= 1;
                        try execute(stream, .{ Cursor { .left = 1 }});
                    }

                    if (!hidden and key.match(.{ .code = .right }) and pos < input.items.len) {
                        pos += 1;
                        try execute(stream, .{ Cursor { .right = 1 }});
                    }

                    if (!hidden and key.match(.{ .code = .end }) and pos < input.items.len) {
                        try execute(stream, .{ Cursor { .right = @intCast(input.items.len -| pos) }});
                        pos = input.items.len;
                    }

                    if (!hidden and key.match(.{ .code = .home }) and pos > 1) {
                        try execute(stream, .{ Cursor { .left = @intCast(pos) }});
                        pos = 0;
                    }

                    if (self.options.password) |password| {
                        if (self.options.password_toggle) |toggle_key| {
                            if (key.match(toggle_key)) {
                                if (hidden) {
                                    hidden = false;

                                    const data = try charToUtf8(self.allocator, input.items);
                                    defer self.allocator.free(data);

                                    try execute(stream, .{
                                        Cursor { .restore = true },
                                        Line { .erase = .to_end },
                                        data
                                    });
                                } else {
                                    hidden = true;
                                    switch (password) {
                                        .hidden => try execute(stream, .{
                                            Cursor { .restore = true },
                                            Line { .erase = .to_end },
                                        }),
                                        .replaced => {
                                            var replacement = std.ArrayList(u8).init(self.allocator);
                                            defer replacement.deinit();
                                            try replacement.appendNTimes('*', input.items.len);
                                            try execute(stream, .{
                                                Cursor { .restore = true },
                                                Line { .erase = .to_end },
                                                replacement.items
                                            });
                                        }
                                    }
                                }
                                continue;
                            }
                        }
                    }

                    if (key.code == .character and key.kind == .press) {
                        try input.insert(pos, key.code.character);

                        if (hidden) {
                            if (self.options.password == .replaced) try execute(stream, .{ '*' });
                        } else if (pos < input.items.len - 1) {
                            try execute(stream, .{
                                Character { .insert = 1 },
                                key.code.character,
                            });
                        } else {
                            try execute(stream, .{ key.code.character });
                        }
                        pos += 1;
                    }
                },
                else => {}
            }
        }
    }

    if (self.options.report) {
        try execute(stream, .{ '\n' });
    } else {
        try execute(stream, .{ Line { .delete = 1 }});
    }

    return try charToUtf8(self.allocator, input.items);
}

fn charToUtf8(allocator: std.mem.Allocator, input: []const u21) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    for (input) |char| {
        var buff: [4]u8 = @splat(0);
        const size = try std.unicode.utf8Encode(char, &buff);
        if (size > 0) {
            try result.appendSlice(buff[0..@intCast(size)]);
        }
    }
    return try result.toOwnedSlice();
}

/// Interact with the user allowing them to enter text or `quit`.
///
/// Output is displayed to Stderr
pub fn interactOpt(self: *const @This()) !?[]const u8 {
    return try self.interactOnOpt(.stderr);
}

/// Interact with the user allowing them to enter text.
///
/// Output is displayed to Stderr
pub fn interact(self: *const @This()) ![]const u8 {
    return try self.interactOn(.stderr);
}

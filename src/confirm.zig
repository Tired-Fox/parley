const std = @import("std");
const zerm = @import("zerm");

const getTermSize = zerm.action.getTermSize;
const Stream = zerm.Stream;
const Cursor = zerm.action.Cursor;
const Line = zerm.action.Line;
const EventStream = zerm.event.EventStream;
const execute = zerm.execute;

pub const Options = struct {
    /// Whether to report the chosen selection after interaction
    report: bool = true,
    /// Default value if the user presses `Enter`
    default: ?bool = null,
    /// Prompt to display to the user
    prompt: ?[]const u8 = null,
};

allocator: std.mem.Allocator,
options: Options,

pub fn init(allocator: std.mem.Allocator, options: Options) @This() {
    return .{
        .allocator = allocator,
        .options = options,
    };
}

/// Interact with the user allowing them to select `yes`, `no`, or quit.
pub fn interactOnOpt(self: *const @This(), stream: Stream) !?bool {
    var event_stream = EventStream.init(self.allocator);
    defer event_stream.deinit();
    const console_output = zerm.Utf8ConsoleOutput.init();
    defer console_output.deinit();

    var confirmed: ?bool = self.options.default;

    var hint = "[y/n]";
    if (self.options.default) |default| {
        hint = if (default) "[Y/n]" else "[y/N]";
    }

    if (self.options.prompt) |prompt| {
        try execute(stream, .{
            prompt,
            ' ',
            Cursor { .save = true },
            hint
        });
    } else {
        try execute(stream, .{
            Cursor { .save = true },
            hint
        });
    }

    while (true) {
        if (try event_stream.parseEvent()) |event| {
            switch (event) {
                .key => |key| {
                    if (key.matches(&.{ 
                        .{ .code = .esc },
                        .{ .code = .char('q') },
                    })) {
                        confirmed = null;
                        break;
                    }

                    if (key.matches(&.{ 
                        .{ .code = .enter }
                    })) break;

                    if (key.matches(&.{ 
                        .{ .code = .char('n') },
                        .{ .code = .char('N') },
                    })) {
                        confirmed = false;
                        break;
                    }

                    if (key.matches(&.{ 
                        .{ .code = .char('y') },
                        .{ .code = .char('Y') }
                    })) {
                        confirmed = true;
                        break;
                    }
                },
                else => {}
            }
        }
    }

    if (self.options.report) {
        try execute(stream, .{
            Cursor { .restore = true },
            Line { .erase = .to_end },
            if (confirmed) |c| if (c) "yes\n" else "no\n" else "\n"
        });
    } else {
        try execute(stream, .{
            Line { .delete = 1 },
        });
    }

    return confirmed;
}

/// Interact with the user allowing them to select `yes`, `no`.
pub fn interactOn(self: *const @This(), stream: Stream) !bool {
    var event_stream = EventStream.init(self.allocator);
    defer event_stream.deinit();
    const console_output = zerm.Utf8ConsoleOutput.init();
    defer console_output.deinit();

    var confirmed: ?bool = self.options.default;

    var hint = "[y/n]";
    if (self.options.default) |default| {
        hint = if (default) "[Y/n]" else "[y/N]";
    }

    if (self.options.prompt) |prompt| {
        try execute(stream, .{
            prompt,
            ' ',
            Cursor { .save = true },
            hint
        });
    } else {
        try execute(stream, .{
            Cursor { .save = true },
            hint
        });
    }

    while (true) {
        if (try event_stream.parseEvent()) |event| {
            switch (event) {
                .key => |key| {
                    if (
                        key.match(.{ .code = .enter })
                        and self.options.default != null
                    ) break;

                    if (key.matches(&.{ 
                        .{ .code = .char('n') },
                        .{ .code = .char('N') },
                    })) {
                        confirmed = false;
                        break;
                    }

                    if (key.matches(&.{ 
                        .{ .code = .char('y') },
                        .{ .code = .char('Y') }
                    })) {
                        confirmed = true;
                        break;
                    }
                },
                else => {}
            }
        }
    }

    if (self.options.report) {
        try execute(stream, .{
            Cursor { .restore = true },
            Line { .erase = .to_end },
            if (confirmed) |c| if (c) "yes\n" else "no\n" else "\n"
        });
    } else {
        try execute(stream, .{
            Line { .delete = 1 },
        });
    }

    return confirmed.?;
}

/// Interact with the user allowing them to select `yes`, `no`, or quit.
///
/// Output is displayed to Stderr
pub fn interactOpt(self: *const @This()) !?bool {
    return try self.interactOnOpt(.stderr);
}

/// Interact with the user allowing them to select `yes`, `no`.
///
/// Output is displayed to Stderr
pub fn interact(self: *const @This()) !bool {
    return try self.interactOn(.stderr);
}

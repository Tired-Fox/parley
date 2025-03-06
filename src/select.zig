const std = @import("std");
const zerm = @import("zerm");

const getTermSize = zerm.action.getTermSize;
const getCursorPos = zerm.action.getCursorPos;
const Stream = zerm.Stream;
const Style = zerm.style.Style;
const Line = zerm.action.Line;
const Cursor = zerm.action.Cursor;
const Character = zerm.action.Character;
const EventStream = zerm.event.EventStream;
const execute = zerm.execute;

allocator: std.mem.Allocator,
options: Options,

pub const Options = struct {
    items: []const []const u8,
    prompt: ?[]const u8 = null,
    hint: ?Hint = null,
    report: bool = true,
    default: ?usize = null,
    max_length: ?usize = null,
    highlight: Style = .{ .fg = .magenta },

    pub const Hint = union(enum) {
        none,
        message: []const u8,

        pub const default: @This() = .{ .none = {} };
        pub fn custom(m: []const u8) @This() {
            return .{ .message = m };
        }
    };
};

pub fn init(allo: std.mem.Allocator, opts: Options) @This() {
    return .{
        .allocator = allo,
        .options = opts,
    };
}

pub fn interact(self: *const @This()) !usize {
    return try self.interactOn(.stderr);
}

pub fn interactOpt(self: *const @This()) !?usize {
    return try self.interactOnOpt(.stderr);
}

fn clear(stream: Stream, lines: usize) !void {
    try execute(stream, .{ Cursor { .restore = true }, Line { .delete = @intCast(lines) } });
}

const RenderOptions = struct {
    lines: usize,
    index: ?usize = null,
    optional: bool = false,
};

fn render(self: *const @This(), stream: Stream, ops: RenderOptions) !usize {
    const rows = (try getTermSize())[1];

    var row: usize = 0;
    var queue = zerm.Queue.init(stream);
    if (ops.lines > 0) {
        try queue.writeAll(.{ Cursor { .restore = true }, Line { .delete = @intCast(ops.lines) } });
    }

    if (self.options.prompt) |prompt| {
        try queue.writeAll(.{ prompt, "\r\n" });
        row += 1;
    }

    const current = @min(ops.index orelse 0, self.options.items.len - 1);

    const height = @min(if (self.options.hint != null and rows >= 4) rows -| 2 -| row else rows -| row, self.options.max_length orelse rows) -| 1;
    const half: usize = @intFromFloat(@ceil(@as(f32, @floatFromInt(height)) / 2.0));
    const left = if (current == self.options.items.len - 1) height else half;

    const min = current -| left;
    const max = @min(current + (height - (current - min)) + 1, self.options.items.len);

    for (self.options.items[min..current]) |item| {
        try queue.writeAll(.{ "[ ] ", item, "\r\n" });
        row += 1;
    }

    {
        try queue.writeAll(.{ self.options.highlight, if (ops.index != null) "[x] " else "[ ] ", self.options.items[current], self.options.highlight.reset(), "\r\n" });
        row += 1;
    }

    for (self.options.items[current + 1..max]) |item| {
        try queue.writeAll(.{ "[ ] ", item, "\r\n" });
        row += 1;
    }

    if (self.options.hint != null and rows >= 4) {
        switch (self.options.hint.?) {
            .none => try queue.writeAll(.{ "\r\n", if (ops.optional) "[↑↓ - Move, Esc - Quit]" else "[↑↓ - Move]", "\r\n" }),
            .message => |message| try queue.writeAll(.{ "\r\n", message, "\r\n" }),
        }
        row += 2;
    }

    try queue.flush();
    return row;
}

pub fn interactOn(self: *const @This(), stream: Stream) !usize {
    var event_stream = EventStream.init(self.allocator);
    defer event_stream.deinit();
    const console_output = zerm.Utf8ConsoleOutput.init();
    defer console_output.deinit();

    var selected: usize = if (self.options.default)|default| @min(default, self.options.items.len -| 1) else 0;

    var lines = try self.render(stream, .{ .lines = 0, .index = selected });
    try execute(stream, .{ Cursor { .col = 1, .up = @intCast(lines) } });
    try execute(stream, .{ Cursor { .save = true }, Cursor { .down = @intCast(lines) } });

    while (true) {
        if (try event_stream.parseEvent()) |event| {
            switch (event) {
                .key => |key| {
                    if (key.match(.{ .code = .enter })) break;

                    if (key.match(.{ .code = .down })) {
                        selected = @min(selected + 1, self.options.items.len - 1);
                        lines = try self.render(stream, .{ .lines = lines, .index = selected });
                    }

                    if (key.match(.{ .code = .up })) {
                        selected -|= 1;
                        lines = try self.render(stream, .{ .lines = lines, .index = selected });
                    }
                },
                else => {}
            }
        }
    }

    try clear(stream, lines);
    if (self.options.report) {
        const item = if (self.options.items.len > 0) self.options.items[selected] else "";
        if (self.options.prompt) |prompt| {
            try execute(stream, .{ prompt, ' ', item, "\r\n" });
        } else {
            try execute(stream, .{ item, "\r\n" });
        }
    }

    return selected;
}

pub fn interactOnOpt(self: *const @This(), stream: Stream) !?usize {
    var event_stream = EventStream.init(self.allocator);
    defer event_stream.deinit();
    const console_output = zerm.Utf8ConsoleOutput.init();
    defer console_output.deinit();

    var selected: ?usize = if (self.options.default)|default| @min(default, self.options.items.len -| 1) else null;

    var lines = try self.render(stream, .{ .lines = 0, .index = selected, .optional = true });
    try execute(stream, .{ Cursor { .col = 1, .up = @intCast(lines) } });
    try execute(stream, .{ Cursor { .save = true }, Cursor { .down = @intCast(lines) } });

    while (true) {
        if (try event_stream.parseEvent()) |event| {
            switch (event) {
                .key => |key| {
                    if (key.matches(&.{ 
                        .{ .code = .esc },
                        .{ .code = .char('q') },
                    })) {
                        selected = null;
                        break;
                    }

                    if (key.match(.{ .code = .enter })) break;

                    if (key.match(.{ .code = .down })) {
                        selected = if (selected) |i| @min(i + 1, self.options.items.len - 1) else 0;
                        lines = try self.render(stream, .{ .lines = lines, .index = selected, .optional = true });
                    }

                    if (key.match(.{ .code = .up })) {
                        selected = if (selected) |i| i -| 1 else self.options.items.len -| 1;
                        lines = try self.render(stream, .{ .lines = lines, .index = selected, .optional = true });
                    }
                },
                else => {}
            }
        }
    }

    try clear(stream, lines);
    if (self.options.report) {
        const item = if (self.options.items.len > 0 and selected != null) self.options.items[selected.?] else "";
        if (self.options.prompt) |prompt| {
            try execute(stream, .{ prompt, ' ', item, "\r\n" });
        } else {
            try execute(stream, .{ item, "\r\n" });
        }
    }

    return selected;
}

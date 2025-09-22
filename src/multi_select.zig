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
const Queue = zerm.Queue;

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

/// User is responsible for freeing the returned slice of selected indexes
pub fn interact(self: *const @This()) ![]usize {
    return try self.interactOn(.stderr);
}

/// User is responsible for freeing the returned slice of selected indexes
pub fn interactOpt(self: *const @This()) !?[]usize {
    return try self.interactOnOpt(.stderr);
}

fn clear(stream: Stream, lines: usize) !void {
    try execute(stream, .{ Cursor { .restore = true }, Line { .delete = @intCast(lines) } });
}

const RenderOptions = struct {
    lines: usize,
    index: ?usize,
    selected: []usize,
    optional: bool = false,
};

fn contains(T: type, haystack: []const T, needle: T) bool {
    for (haystack) |h| if (std.meta.eql(h, needle)) return true;
    return false;
}
fn indexOf(T: type, haystack: []const T, needle: T) ?usize {
    for (haystack, 0..) |h, i| if (std.meta.eql(h, needle)) return i;
    return null;
}

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

    for (self.options.items[min..current], min..current) |item, i| {
        if (contains(usize, ops.selected, i)) {
            try queue.writeAll(.{ "[x] ", item, "\r\n" });
        } else {
            try queue.writeAll(.{ "[ ] ", item, "\r\n" });
        }
        row += 1;
    }

    {
        const item = self.options.items[current];
        if (contains(usize, ops.selected, current)) {
            try queue.writeAll(.{ self.options.highlight, "[x] ", item, self.options.highlight.reset(), "\r\n" });
        } else {
            try queue.writeAll(.{ self.options.highlight, "[ ] ", item, self.options.highlight.reset(), "\r\n" });
        }
        row += 1;
    }

    for (self.options.items[current + 1..max], (current + 1)..max) |item, i| {
        if (contains(usize, ops.selected, i)) {
            try queue.writeAll(.{ "[x] ", item, "\r\n" });
        } else {
            try queue.writeAll(.{ "[ ] ", item, "\r\n" });
        }
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

/// User is responsible for freeing the returned slice of selected indexes
pub fn interactOn(self: *const @This(), stream: Stream) ![]usize {
    var event_stream = EventStream.init(self.allocator);
    defer event_stream.deinit();
    const console_output = zerm.Utf8ConsoleOutput.init();
    defer console_output.deinit();

    var selected: std.ArrayList(usize) = .empty;
    errdefer selected.deinit(self.allocator);
    var index: usize = if (self.options.default)|default| @min(default, self.options.items.len -| 1) else 0;

    var lines = try self.render(stream, .{ .lines = 0, .index = index, .selected=selected.items });
    try execute(stream, .{ Cursor { .col = 1, .up = @intCast(lines) } });
    try execute(stream, .{ Cursor { .save = true }, Cursor { .down = @intCast(lines) } });

    while (true) {
        if (try event_stream.parseEvent()) |event| {
            switch (event) {
                .key => |key| {
                    if (key.match(.{ .code = .enter }) and selected.items.len > 0) break;
                    if (key.match(.{ .code = .char(' ') })) {
                        if (indexOf(usize, selected.items, index)) |idx| {
                            _ = selected.swapRemove(idx);
                        } else {
                            try selected.append(self.allocator, index);
                        }
                        lines = try self.render(stream, .{ .lines = lines, .index = index, .selected=selected.items });
                    }

                    if (key.match(.{ .code = .down })) {
                        index = @min(index + 1, self.options.items.len - 1);
                        lines = try self.render(stream, .{ .lines = lines, .index = index, .selected=selected.items });
                    }

                    if (key.match(.{ .code = .up })) {
                        index -|= 1;
                        lines = try self.render(stream, .{ .lines = lines, .index = index, .selected=selected.items });
                    }
                },
                else => {}
            }
        }
    }

    try clear(stream, lines);
    if (self.options.report) {
        if (selected.items.len > 0) {
            var queue = Queue.init(stream);
            if (self.options.prompt) |prompt| {
                try queue.writeAll(.{ prompt, ' ' });
            }
            try queue.write(self.options.items[selected.items[0]]);
            for (1..selected.items.len) |i| {
                try queue.writeAll(.{ ", ", self.options.items[selected.items[i]] });
            }
            try queue.write("\r\n");
            try queue.flush();
        }
    }

    return try selected.toOwnedSlice(self.allocator);
}

/// User is responsible for freeing the returned slice of selected indexes
pub fn interactOnOpt(self: *const @This(), stream: Stream) !?[]usize {
    var event_stream = EventStream.init(self.allocator);
    defer event_stream.deinit();
    const console_output = zerm.Utf8ConsoleOutput.init();
    defer console_output.deinit();

    var selected: std.ArrayList(usize) = .empty;
    defer selected.deinit(self.allocator);
    var index: usize = if (self.options.default)|default| @min(default, self.options.items.len -| 1) else 0;

    var lines = try self.render(stream, .{ .lines = 0, .index = index, .optional = true, .selected=selected.items });
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
                        selected.clearAndFree(self.allocator);
                        break;
                    }

                    if (key.match(.{ .code = .enter })) break;
                    if (key.match(.{ .code = .char(' ') })) {
                        if (indexOf(usize, selected.items, index)) |idx| {
                            _ = selected.swapRemove(idx);
                        } else {
                            try selected.append(self.allocator, index);
                        }
                        lines = try self.render(stream, .{ .lines = lines, .index = index, .optional = true, .selected=selected.items });
                    }

                    if (key.match(.{ .code = .down })) {
                        index = @min(index + 1, self.options.items.len - 1);
                        lines = try self.render(stream, .{ .lines = lines, .index = index, .optional = true, .selected=selected.items });
                    }

                    if (key.match(.{ .code = .up })) {
                        index = index -| 1;
                        lines = try self.render(stream, .{ .lines = lines, .index = index, .optional = true, .selected=selected.items });
                    }
                },
                else => {}
            }
        }
    }

    try clear(stream, lines);
    if (self.options.report) {
        var queue = Queue.init(stream);
        if (self.options.prompt) |prompt| {
            try queue.writeAll(.{ prompt, ' ' });
        }

        if (selected.items.len > 0) {
            try queue.write(self.options.items[selected.items[0]]);
            for (1..selected.items.len) |i| {
                try queue.writeAll(.{ ", ", self.options.items[selected.items[i]] });
            }
            try queue.write("\r\n");
        } else {
            try queue.write("null");
        }

        try queue.flush();
    }

    if (selected.items.len > 0) {
        return try selected.toOwnedSlice(self.allocator);
    } else {
        return null;
    }
}

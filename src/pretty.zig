const std = @import("std");
const color = @import("color.zig");

const Allocator = std.mem.Allocator;
const Color = color.Color;

const PrettyLine = struct {
    line_type: Type,
    contents: []const u8,

    const Type = enum {
        Whatis,
        Desc,
        Cmd,
        Arg,
        Other,
    };

    /// Parse a slice of string slices into a heap array of PrettyLine structs.
    pub fn parseLines(allocator: *Allocator, line_slices: []const []const u8) ![]@This() {
        var lines_rich = try allocator.alloc(@This(), line_slices.len);
        for (line_slices) |l, i| {
            lines_rich[i] = @This().parseLine(l);
        }
        return lines_rich;
    }

    pub fn parseLine(l: []const u8) @This() {
        if (l.len > 0) {
            return switch (l[0]) {
                '>' => .{ .line_type = @This().Type.Whatis, .contents = l[2..] },
                '-' => .{ .line_type = @This().Type.Desc, .contents = l[2..] },
                '`' => .{ .line_type = @This().Type.Cmd, .contents = l[1 .. l.len - 1] },
                else => .{ .line_type = @This().Type.Other, .contents = l },
            };
        } else {
            return .{ .line_type = @This().Type.Other, .contents = "" };
        }
    }

    pub fn prettyPrint(self: *const @This(), writer: anytype) !void {
        _ = try writer.write(self.colorCode());

        var ind = self.indentWidth();
        while (ind > 0) : (ind -= 1) {
            _ = try writer.write(" ");
        }

        try self.printLine(writer);
    }

    pub fn printLine(self: *const @This(), writer: anytype) !void {
        if (self.contents.len > 0) {
            var i: usize = 1;
            while (i < self.contents.len) : (i += 1) {
                const curr = self.contents[i];
                const prev = self.contents[i - 1];

                if (curr == '{' and prev == '{') {
                    _ = try writer.write(Color.BrightRed.code());
                    i += 1;
                } else if (curr == '}' and prev == '}') {
                    _ = try writer.write(self.colorCode());
                    i += 1;
                } else {
                    _ = try writer.write(&[_]u8{prev});
                }
            }

            const last = self.contents[self.contents.len - 1];
            if (self.contents.len > 2) {
                const last_prev = self.contents[self.contents.len - 2];
                if (last != '}' and last_prev != '}') {
                    _ = try writer.write(&[_]u8{last});
                }
            } else {
                _ = try writer.write(&[_]u8{last});
            }
        }

        _ = try writer.write("\n");
    }

    fn colorCode(self: *const @This()) []const u8 {
        return switch (self.line_type) {
            .Whatis => Color.reset(),
            .Desc => Color.Green.code(),
            .Cmd => Color.Red.code(),
            .Arg => Color.BrightRed.code(),
            .Other => Color.reset(),
        };
    }

    fn indentWidth(self: *const @This()) u8 {
        return switch (self.line_type) {
            .Whatis => 0,
            .Desc => 2,
            .Cmd => 6,
            .Arg => 0,
            .Other => 0,
        };
    }

    fn argSize(self: *const @This()) usize {
        var count: usize = 0;
        var i: usize = 1;
        while (i < self.contents.len) : (i += 1) {
            const curr = self.contents[i];
            const prev = self.contents[i - 1];

            if (curr == '{' and prev == '{') count += 1;
        }
        return count * (Color.BrightRed.code().len + self.colorCode().len);
    }

    fn lineSize(self: *const @This()) usize {
        return self.contents.len + self.colorCode().len + self.indentWidth() + self.argSize();
    }
};

/// Add colors and indentation to the tldr page.
pub fn prettify(allocator: *Allocator, contents: []const u8) ![]const u8 {
    const line_slices = try lines(allocator, contents);
    defer allocator.free(line_slices);

    const skip_lines = 2;
    const lines_rich = try PrettyLine.parseLines(allocator, line_slices[skip_lines..]);

    const pretty: []u8 = try allocator.alloc(u8, prettySize(lines_rich));
    var stream = std.io.fixedBufferStream(pretty);
    var buffered_stream = std.io.bufferedWriter(stream.writer());

    for (lines_rich) |l| {
        _ = try l.prettyPrint(buffered_stream.writer());
    }
    _ = try buffered_stream.write(Color.reset());

    try buffered_stream.flush();
    return stream.getWritten();
}

/// Split up the page by lines.
fn lines(allocator: *Allocator, contents: []const u8) ![]const []const u8 {
    const line_slices = try allocator.alloc([]const u8, countLines(contents));
    var slice: usize = 0;
    var end: usize = 0;
    var start: usize = 0;

    while (end < contents.len) : (end += 1) {
        if (contents[end] == '\n') {
            line_slices[slice] = contents[start..end];
            start = end + 1;
            slice += 1;
        }
    }

    return line_slices;
}

/// Count the number of lines in the tldr page.
fn countLines(contents: []const u8) usize {
    var count: usize = 0;
    for (contents) |c| {
        if (c == '\n') count += 1;
    }
    return count;
}

/// We're adding terminal escapes and indentation into the tldr page
/// contents, making it longer. Calculate the new size.
fn prettySize(pretty_line: []const PrettyLine) usize {
    var count: usize = pretty_line.len;

    for (pretty_line) |l| {
        count += l.lineSize();
    }
    count += Color.reset().len;

    return count;
}

test "countLines" {
    var multi_line_string =
        \\ something
        \\ ~spanning~
        \\ multiple
        \\ lines
        \\
    ;

    std.testing.expectEqual(@as(usize, 4), countLines(multi_line_string));
}

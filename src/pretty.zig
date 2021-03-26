const std = @import("std");
const color = @import("color.zig");

const Allocator = std.mem.Allocator;
const Color = color.Color;

const Line = struct {
    line_type: Type,
    contents: []const u8,

    const Type = enum {
        Whatis,
        Desc,
        Cmd,
        Arg,
        Other,
    };

    pub fn parseLine(l: []const u8) @This() {
        if (l.len > 0) {
            return switch (l[0]) {
                '>' => .{ .line_type = Line.Type.Whatis, .contents = l[2..] },
                '-' => .{ .line_type = Line.Type.Desc, .contents = l[2..] },
                '`' => .{ .line_type = Line.Type.Cmd, .contents = l[1 .. l.len - 1] },
                else => .{ .line_type = Line.Type.Other, .contents = l },
            };
        } else {
            return .{ .line_type = Line.Type.Other, .contents = "" };
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
};

/// Add colors and indentation to the tldr page.
pub fn prettify(allocator: *Allocator, contents: []const u8) ![]const u8 {
    const pretty: []u8 = try allocator.alloc(u8, prettySize(contents) * 4); // TODO: Calc actual size needed.
    var stream = std.io.fixedBufferStream(pretty);
    var buffered_stream = std.io.bufferedWriter(stream.writer());

    const contentsLines: []const []const u8 = try lines(allocator, contents);
    defer allocator.free(contentsLines);

    // Skip the title in the first 2 lines.
    for (contentsLines[2..]) |l| {
        _ = try Line.parseLine(l).prettyPrint(buffered_stream.writer());
    }
    _ = try buffered_stream.write(Color.reset());

    try buffered_stream.flush();
    return stream.getWritten();
}

/// Split up the page by lines.
fn lines(allocator: *Allocator, contents: []const u8) ![]const []const u8 {
    const lineSlices = try allocator.alloc([]const u8, countLines(contents));
    var slice: usize = 0;
    var end: usize = 0;
    var start: usize = 0;

    while (end < contents.len) : (end += 1) {
        if (contents[end] == '\n') {
            lineSlices[slice] = contents[start..end];
            start = end + 1;
            slice += 1;
        }
    }

    return lineSlices;
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
fn prettySize(contents: []const u8) usize {
    var count: usize = 0;
    var i: usize = 1;

    while (contents[i] != '\n') : (i += 1) {}

    while (i < contents.len) : (i += 1) {
        var curr = contents[i];
        var prev = contents[i - 1];

        if (curr == '{' and prev == '{') count += 1;
        if (curr == '-' and prev == '\n') count += 1;
        if (curr == '`' and prev == '\n') count += 1;
        if (curr == '>' and prev == '\n') count += 1;
    }

    return contents.len + count * 16;
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

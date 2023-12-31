const std = @import("std");
const color = @import("color.zig");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
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

        fn colorCode(this: *const @This()) []const u8 {
            return switch (this.*) {
                .Whatis => Color.reset(),
                .Desc => Color.Green.code(),
                .Cmd => Color.Red.code(),
                .Arg => Color.BrightRed.code(),
                .Other => Color.reset(),
            };
        }
    };

    /// Parse a slice of string slices into a heap array of PrettyLine structs.
    pub fn parseLines(
        allocator: Allocator,
        line_slices: []const []const u8,
    ) ![]@This() {
        var lines_rich = try allocator.alloc(@This(), line_slices.len);
        for (line_slices) |l, i| lines_rich[i] = @This().parseLine(l);
        return lines_rich;
    }

    pub fn parseLine(l: []const u8) @This() {
        if (l.len == 0) return .{ .line_type = .Other, .contents = "" };

        return switch (l[0]) {
            '>' => .{ .line_type = .Whatis, .contents = l[2..] },
            '-' => .{ .line_type = .Desc, .contents = l[2..] },
            '`' => .{ .line_type = .Cmd, .contents = l[1 .. l.len - 1] },
            else => .{ .line_type = .Other, .contents = l },
        };
    }

    pub fn prettyPrint(this: *const @This(), writer: anytype) !void {
        _ = try writer.write(this.line_type.colorCode());
        var ind = this.indentWidth();
        while (ind > 0) : (ind -= 1) _ = try writer.write(" ");
        try this.printLine(writer);
    }

    pub fn printLine(this: *const @This(), writer: anytype) !void {
        if (this.contents.len > 0) {
            var i: usize = 1;
            while (i < this.contents.len) : (i += 1) {
                const curr = this.contents[i];
                const prev = this.contents[i - 1];

                if (curr == '{' and prev == '{') {
                    _ = try writer.write(Type.Arg.colorCode());
                    i += 1;
                } else if (curr == '}' and prev == '}') {
                    _ = try writer.write(this.line_type.colorCode());
                    i += 1;
                } else {
                    _ = try writer.write(&[_]u8{prev});
                }
            }

            const last = this.contents[this.contents.len - 1];
            if (this.contents.len > 2) {
                const last_prev = this.contents[this.contents.len - 2];
                if (last != '}' or last_prev != '}')
                    _ = try writer.write(&[_]u8{last});
            } else _ = try writer.write(&[_]u8{last});
        }

        _ = try writer.write("\n");
    }

    fn indentWidth(this: *const @This()) u8 {
        return switch (this.line_type) {
            .Whatis => 0,
            .Desc => 2,
            .Cmd => 6,
            .Arg => 0,
            .Other => 0,
        };
    }
};

/// Add colors and indentation to the tldr page.
pub fn prettify(allocator: Allocator, contents: []const u8, writer: anytype) !void {
    const line_slices = try lines(allocator, contents);
    defer allocator.free(line_slices);

    const skip_lines = 2;
    const lines_rich = try PrettyLine.parseLines(allocator, line_slices[skip_lines..]);
    defer allocator.free(lines_rich);

    var buffered_stream = std.io.bufferedWriter(writer);
    for (lines_rich) |l| _ = try l.prettyPrint(buffered_stream.writer());
    _ = try buffered_stream.write(Color.reset());
    _ = try buffered_stream.write("\n");

    try buffered_stream.flush();
}

pub fn prettifyPagesList(pages_list: anytype, writer: anytype) !void {
    for (pages_list.items) |entry| {
        try writer.print("{s}{s}{s} // {s}{s}{s}\n", .{
            PrettyLine.Type.Cmd.colorCode(),
            entry.name,
            Color.Black.code(),

            PrettyLine.Type.Desc.colorCode(),
            entry.desc,
            Color.reset(),
        });
    }
}

/// Split up the page by lines.
fn lines(allocator: Allocator, contents: []const u8) ![]const []const u8 {
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

const std = @import("std");
const color = @import("color.zig");
const pages = @import("pages.zig");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Color = color.Color;

const PrettyLine = struct {
    variant: Variant,
    contents: []const u8,

    const Variant = enum {
        Whatis,
        Desc,
        Cmd,
        Arg,
        Blank,

        fn colorCode(this: *const Variant) []const u8 {
            return switch (this.*) {
                .Whatis => Color.reset(),
                .Desc => Color.Green.code(),
                .Cmd => Color.Red.code(),
                .Arg => Color.BrightRed.code(),
                .Blank => Color.reset(),
            };
        }

        fn indentation(this: Variant) u8 {
            return switch (this) {
                .Whatis => 0,
                .Desc => 2,
                .Cmd => 6,
                .Arg => 0,
                .Blank => 0,
            };
        }
    };

    /// Parse page `contents` into a heap array of PrettyLine structs.
    /// Skips first two lines as they aren't printed.
    fn parse(al: Allocator, contents: []const u8) ![]PrettyLine {
        var lines = std.mem.splitScalar(u8, contents, '\n');
        for (0..2) |_| _ = lines.next() orelse return error.malformed_page;

        var line_count: usize = 0;
        while (lines.next()) |_| line_count += 1;
        lines.reset();
        for (0..2) |_| _ = lines.next() orelse return error.malformed_page;

        var i: usize = 0;
        var pretty_lines = try al.alloc(PrettyLine, line_count);
        while (lines.next()) |l| : (i += 1) pretty_lines[i] = line: {
            if (l.len == 0) break :line .{ .variant = .Blank, .contents = "" };
            break :line switch (l[0]) {
                '>' => .{ .variant = .Whatis, .contents = l[2..] },
                '-' => .{ .variant = .Desc, .contents = l[2..] },
                '`' => .{ .variant = .Cmd, .contents = l[1 .. l.len - 1] },
                else => return error.malformed_page,
            };
        };

        return pretty_lines;
    }

    // Write prettified `line` to `w`.
    fn write(
        line: *const PrettyLine,
        al: Allocator,
        w: *std.Io.Writer,
        options_length: OptionsLength,
    ) !void {
        try w.writeAll(line.variant.colorCode());
        var ind = line.variant.indentation();
        while (ind > 0) : (ind -= 1) try w.writeAll(" ");

        switch (line.variant) {
            .Blank => {},
            .Cmd => try line.writeCmd(al, w, options_length),
            else => try w.writeAll(line.contents),
        }
        try w.writeAll("\n");
    }

    fn writeCmd(
        line: *const PrettyLine,
        al: Allocator,
        w: *std.Io.Writer,
        options_length: OptionsLength,
    ) !void {
        const c = line.contents;
        if (c.len == 0) return error.malformed_page;

        var arr: std.ArrayList(u8) = try .initCapacity(al, c.len);
        defer arr.deinit(al);

        var i: usize = 0;
        while (std.mem.indexOfPos(u8, c, i, "{{")) |open_brace| {
            try arr.print(al, "{s}", .{c[i..open_brace]});

            const close_brace = std.mem.indexOfPos(u8, c, open_brace, "}}") orelse
                return error.malformed_page;
            if (open_brace + 2 == close_brace) return error.malformed_page;
            const arg = c[open_brace + 2 .. close_brace];

            if (std.mem.startsWith(u8, arg, "[") and std.mem.endsWith(u8, arg, "]")) {
                var short_long_toks = std.mem.tokenizeAny(u8, arg, "[]|");
                const short = short_long_toks.next() orelse return error.malformed_page;
                const long = short_long_toks.next() orelse return error.malformed_page;
                switch (options_length) {
                    .short => try arr.print(al, "{s}", .{short}),
                    .long => try arr.print(al, "{s}", .{long}),
                    .both => try arr.print(al, "{s}[{s}|{s}]{s}", .{
                        Variant.Arg.colorCode(),
                        short,
                        long,
                        line.variant.colorCode(),
                    }),
                }
            } else try arr.print(al, "{s}{s}{s}", .{
                Variant.Arg.colorCode(),
                arg,
                line.variant.colorCode(),
            });

            i = close_brace + 2;
        }
        try arr.print(al, "{s}", .{c[i..]});

        // Escaped braces ('\{\{' and '\}\}') must be unescaped.
        while (std.mem.indexOf(u8, arr.items, "\\{\\{")) |ei| try arr.replaceRange(al, ei, 4, "{{");
        while (std.mem.indexOf(u8, arr.items, "\\}\\}")) |ei| try arr.replaceRange(al, ei, 4, "}}");

        try w.writeAll(arr.items);
    }
};

pub const OptionsLength = enum { short, long, both };

/// Add colors and indentation to the tldr page.
pub fn prettify(
    al: Allocator,
    contents: []const u8,
    w: *std.Io.Writer,
    options_length: OptionsLength,
) !void {
    const pretty_lines = try PrettyLine.parse(al, contents);
    for (pretty_lines) |l| try l.write(al, w, options_length);
    try w.writeAll(Color.reset());
}

pub fn prettifyPagesList(pages_list: []pages.PageInfo, w: *std.Io.Writer) !void {
    for (pages_list) |entry| {
        try w.print("{s}{s}{s} // {s}{s}{s}\n", .{
            PrettyLine.Variant.Cmd.colorCode(),
            entry.name,
            Color.Black.code(),

            PrettyLine.Variant.Desc.colorCode(),
            entry.desc,
            Color.reset(),
        });
    }
}

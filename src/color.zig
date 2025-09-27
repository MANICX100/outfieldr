const std = @import("std");

const term_esc = "\x1b[";

pub var enabled: bool = undefined;

pub const Color = enum {
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
    BrightBlack,
    BrightRed,
    BrightGreen,
    BrightYellow,
    BrightBlue,
    BrightMagenta,
    BrightCyan,
    BrightWhite,

    pub fn reset() []const u8 {
        return if (enabled) term_esc ++ "0m" else "";
    }

    pub fn code(comptime this: *const Color) []const u8 {
        return if (enabled) comptime std.fmt.comptimePrint(
            "{s}{}m",
            .{ term_esc, this.fg() },
        ) else "";
    }

    fn fg(comptime this: *const Color) u8 {
        return switch (this.*) {
            .Black => 30,
            .Red => 31,
            .Green => 32,
            .Yellow => 33,
            .Blue => 34,
            .Magenta => 35,
            .Cyan => 36,
            .White => 37,
            .BrightBlack => 90,
            .BrightRed => 91,
            .BrightGreen => 92,
            .BrightYellow => 93,
            .BrightBlue => 94,
            .BrightMagenta => 95,
            .BrightCyan => 96,
            .BrightWhite => 97,
        };
    }

    fn bg(comptime this: *const Color) u8 {
        return this.fg() + 10;
    }
};

test "color codes foreground only" {
    enabled = true;
    try std.testing.expectEqualSlices(u8, "\x1b[30m", Color.Black.code());
    try std.testing.expectEqualSlices(u8, "\x1b[30m", Color.Black.code());
    try std.testing.expectEqualSlices(u8, "\x1b[31m", Color.Red.code());
    try std.testing.expectEqualSlices(u8, "\x1b[32m", Color.Green.code());
    try std.testing.expectEqualSlices(u8, "\x1b[33m", Color.Yellow.code());
    try std.testing.expectEqualSlices(u8, "\x1b[34m", Color.Blue.code());
    try std.testing.expectEqualSlices(u8, "\x1b[35m", Color.Magenta.code());
    try std.testing.expectEqualSlices(u8, "\x1b[36m", Color.Cyan.code());
    try std.testing.expectEqualSlices(u8, "\x1b[37m", Color.White.code());
    try std.testing.expectEqualSlices(u8, "\x1b[90m", Color.BrightBlack.code());
    try std.testing.expectEqualSlices(u8, "\x1b[91m", Color.BrightRed.code());
    try std.testing.expectEqualSlices(u8, "\x1b[92m", Color.BrightGreen.code());
    try std.testing.expectEqualSlices(u8, "\x1b[93m", Color.BrightYellow.code());
    try std.testing.expectEqualSlices(u8, "\x1b[94m", Color.BrightBlue.code());
    try std.testing.expectEqualSlices(u8, "\x1b[95m", Color.BrightMagenta.code());
    try std.testing.expectEqualSlices(u8, "\x1b[96m", Color.BrightCyan.code());
    try std.testing.expectEqualSlices(u8, "\x1b[97m", Color.BrightWhite.code());
}

test "color code reset" {
    enabled = true;
    try std.testing.expectEqualSlices(u8, "\x1b[0m", Color.reset());
}

test "color codes foreground" {
    enabled = true;
    try std.testing.expectEqual(@as(u8, 30), Color.Black.fg());
    try std.testing.expectEqual(@as(u8, 31), Color.Red.fg());
    try std.testing.expectEqual(@as(u8, 32), Color.Green.fg());
    try std.testing.expectEqual(@as(u8, 33), Color.Yellow.fg());
    try std.testing.expectEqual(@as(u8, 34), Color.Blue.fg());
    try std.testing.expectEqual(@as(u8, 35), Color.Magenta.fg());
    try std.testing.expectEqual(@as(u8, 36), Color.Cyan.fg());
    try std.testing.expectEqual(@as(u8, 37), Color.White.fg());
}

test "color codes background" {
    enabled = true;
    try std.testing.expectEqual(@as(u8, 40), Color.Black.bg());
    try std.testing.expectEqual(@as(u8, 41), Color.Red.bg());
    try std.testing.expectEqual(@as(u8, 42), Color.Green.bg());
    try std.testing.expectEqual(@as(u8, 43), Color.Yellow.bg());
    try std.testing.expectEqual(@as(u8, 44), Color.Blue.bg());
    try std.testing.expectEqual(@as(u8, 45), Color.Magenta.bg());
    try std.testing.expectEqual(@as(u8, 46), Color.Cyan.bg());
    try std.testing.expectEqual(@as(u8, 47), Color.White.bg());
}

test "bright color codes foreground" {
    enabled = true;
    try std.testing.expectEqual(@as(u8, 90), Color.BrightBlack.fg());
    try std.testing.expectEqual(@as(u8, 91), Color.BrightRed.fg());
    try std.testing.expectEqual(@as(u8, 92), Color.BrightGreen.fg());
    try std.testing.expectEqual(@as(u8, 93), Color.BrightYellow.fg());
    try std.testing.expectEqual(@as(u8, 94), Color.BrightBlue.fg());
    try std.testing.expectEqual(@as(u8, 95), Color.BrightMagenta.fg());
    try std.testing.expectEqual(@as(u8, 96), Color.BrightCyan.fg());
    try std.testing.expectEqual(@as(u8, 97), Color.BrightWhite.fg());
}

test "bright color codes background" {
    enabled = true;
    try std.testing.expectEqual(@as(u8, 100), Color.BrightBlack.bg());
    try std.testing.expectEqual(@as(u8, 101), Color.BrightRed.bg());
    try std.testing.expectEqual(@as(u8, 102), Color.BrightGreen.bg());
    try std.testing.expectEqual(@as(u8, 103), Color.BrightYellow.bg());
    try std.testing.expectEqual(@as(u8, 104), Color.BrightBlue.bg());
    try std.testing.expectEqual(@as(u8, 105), Color.BrightMagenta.bg());
    try std.testing.expectEqual(@as(u8, 106), Color.BrightCyan.bg());
    try std.testing.expectEqual(@as(u8, 107), Color.BrightWhite.bg());
}

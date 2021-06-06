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

    pub fn code(comptime this: *const @This()) []const u8 {
        if (enabled) {
            comptime {
                @setEvalBranchQuota(2000);
                return std.fmt.comptimePrint("{s}{}m", .{ term_esc, this.fg() });
            }
        } else {
            return "";
        }
    }

    fn fg(comptime this: *const @This()) comptime u8 {
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

    fn bg(comptime this: *const @This()) comptime u8 {
        return this.fg() + 10;
    }
};

test "color codes foreground only" {
    std.testing.expectEqualSlices(u8, "\\033[30m", Color.Black.code());
    std.testing.expectEqualSlices(u8, "\\033[30m", Color.Black.code());
    std.testing.expectEqualSlices(u8, "\\033[31m", Color.Red.code());
    std.testing.expectEqualSlices(u8, "\\033[32m", Color.Green.code());
    std.testing.expectEqualSlices(u8, "\\033[33m", Color.Yellow.code());
    std.testing.expectEqualSlices(u8, "\\033[34m", Color.Blue.code());
    std.testing.expectEqualSlices(u8, "\\033[35m", Color.Magenta.code());
    std.testing.expectEqualSlices(u8, "\\033[36m", Color.Cyan.code());
    std.testing.expectEqualSlices(u8, "\\033[37m", Color.White.code());
    std.testing.expectEqualSlices(u8, "\\033[90m", Color.BrightBlack.code());
    std.testing.expectEqualSlices(u8, "\\033[91m", Color.BrightRed.code());
    std.testing.expectEqualSlices(u8, "\\033[92m", Color.BrightGreen.code());
    std.testing.expectEqualSlices(u8, "\\033[93m", Color.BrightYellow.code());
    std.testing.expectEqualSlices(u8, "\\033[94m", Color.BrightBlue.code());
    std.testing.expectEqualSlices(u8, "\\033[95m", Color.BrightMagenta.code());
    std.testing.expectEqualSlices(u8, "\\033[96m", Color.BrightCyan.code());
    std.testing.expectEqualSlices(u8, "\\033[97m", Color.BrightWhite.code());
}

test "color code reset" {
    std.testing.expectEqualSlices(u8, "\\033[0m", Color.reset());
}

test "color codes foreground" {
    std.testing.expectEqual(@as(u8, 30), Color.Black.fg());
    std.testing.expectEqual(@as(u8, 31), Color.Red.fg());
    std.testing.expectEqual(@as(u8, 32), Color.Green.fg());
    std.testing.expectEqual(@as(u8, 33), Color.Yellow.fg());
    std.testing.expectEqual(@as(u8, 34), Color.Blue.fg());
    std.testing.expectEqual(@as(u8, 35), Color.Magenta.fg());
    std.testing.expectEqual(@as(u8, 36), Color.Cyan.fg());
    std.testing.expectEqual(@as(u8, 37), Color.White.fg());
}

test "color codes background" {
    std.testing.expectEqual(@as(u8, 40), Color.Black.bg());
    std.testing.expectEqual(@as(u8, 41), Color.Red.bg());
    std.testing.expectEqual(@as(u8, 42), Color.Green.bg());
    std.testing.expectEqual(@as(u8, 43), Color.Yellow.bg());
    std.testing.expectEqual(@as(u8, 44), Color.Blue.bg());
    std.testing.expectEqual(@as(u8, 45), Color.Magenta.bg());
    std.testing.expectEqual(@as(u8, 46), Color.Cyan.bg());
    std.testing.expectEqual(@as(u8, 47), Color.White.bg());
}

test "bright color codes foreground" {
    std.testing.expectEqual(@as(u8, 90), Color.BrightBlack.fg());
    std.testing.expectEqual(@as(u8, 91), Color.BrightRed.fg());
    std.testing.expectEqual(@as(u8, 92), Color.BrightGreen.fg());
    std.testing.expectEqual(@as(u8, 93), Color.BrightYellow.fg());
    std.testing.expectEqual(@as(u8, 94), Color.BrightBlue.fg());
    std.testing.expectEqual(@as(u8, 95), Color.BrightMagenta.fg());
    std.testing.expectEqual(@as(u8, 96), Color.BrightCyan.fg());
    std.testing.expectEqual(@as(u8, 97), Color.BrightWhite.fg());
}

test "bright color codes background" {
    std.testing.expectEqual(@as(u8, 100), Color.BrightBlack.bg());
    std.testing.expectEqual(@as(u8, 101), Color.BrightRed.bg());
    std.testing.expectEqual(@as(u8, 102), Color.BrightGreen.bg());
    std.testing.expectEqual(@as(u8, 103), Color.BrightYellow.bg());
    std.testing.expectEqual(@as(u8, 104), Color.BrightBlue.bg());
    std.testing.expectEqual(@as(u8, 105), Color.BrightMagenta.bg());
    std.testing.expectEqual(@as(u8, 106), Color.BrightCyan.bg());
    std.testing.expectEqual(@as(u8, 107), Color.BrightWhite.bg());
}

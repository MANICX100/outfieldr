const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn printUsage(prog_name: []const u8, w: *std.Io.Writer) !void {
    try w.print(
        \\Usage: {s} [flags] <page>
        \\
        \\Flags:
        \\  -h, --help                 Display this help and exit.
        \\  -v, --version              Display version information and exit.
        \\  -L, --language <language>  Page language.
        \\  -p, --platform <platform>  Platform target.
        \\  -u, --update               Update local TLDR pages cache.
        \\  -R, --random               Fetch a random page.
        \\  -l, --list                 List all available pages with descriptons.
        \\  --short-options            Display options in shortform when available
        \\  --long-options             Display options in longform when available (Default)
        \\  --list-languages           List all supported languages.
        \\  --list-platforms           List all supported operating systems.
        \\  --color <color>            Enable or disable colored output.
        \\
    , .{prog_name});
}

pub const examples =
    \\
    \\Examples:
    \\
    \\ # View the TLDR page for ip:
    \\ tldr ip
    \\
    \\ # View a multi-word TLDR page:
    \\ tldr git rebase
    \\
    \\ # Specify the languge and OS of the page
    \\ tldr --language es --platform osx brew
    \\
    \\ # Update fresh TLDR pages and view page for chown
    \\ tldr --update chown
    \\
;

pub const Args = struct {
    prog_name: []const u8,
    help: bool,
    version: bool,

    language: ?[]const u8,
    platform: ?[]const u8,
    short_options: bool,
    long_options: bool,

    update: bool,
    list: bool,
    random: bool,
    list_languages: bool,
    list_platforms: bool,
    color: ?ColorChoices,

    positionals: ?[]const []const u8,
};

pub const Error = error{
    missing_argument,
    bad_color_arg,
    unrecognized_argument,
    no_prog_name,
};

pub const ColorChoices = enum { auto, off, on };

pub const Status = struct { bad_arg: []const u8 };

pub fn parse(al: Allocator, argv: [][*:0]u8, status: *Status) Error!Args {
    var args = std.mem.zeroes(Args);

    if (argv.len == 0) return Error.no_prog_name;
    args.prog_name = std.mem.span(argv[0]);

    var posargs = std.ArrayList([]const u8).initCapacity(al, 10) catch unreachable;
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = std.mem.span(argv[i]);

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            args.help = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            args.version = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--update")) {
            args.update = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--list")) {
            args.list = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-R") or std.mem.eql(u8, arg, "--random")) {
            args.random = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--short-options")) {
            args.short_options = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--long-options")) {
            args.long_options = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--list-languages")) {
            args.list_languages = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--list-platforms")) {
            args.list_platforms = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-L") or std.mem.eql(u8, arg, "--language")) {
            if (i == argv.len - 1) {
                status.* = .{ .bad_arg = arg };
                return Error.missing_argument;
            }
            args.language = std.mem.span(argv[i + 1]);
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--platform")) {
            if (i == argv.len - 1) {
                status.* = .{ .bad_arg = arg };
                return Error.missing_argument;
            }
            args.platform = std.mem.span(argv[i + 1]);
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "--color")) {
            if (i == argv.len - 1) {
                status.* = .{ .bad_arg = arg };
                return Error.missing_argument;
            }
            const color_str = std.mem.span(argv[i + 1]);
            i += 1;
            args.color = std.meta.stringToEnum(ColorChoices, color_str) orelse {
                status.* = .{ .bad_arg = arg };
                return Error.bad_color_arg;
            };
            continue;
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            status.* = .{ .bad_arg = arg };
            return Error.unrecognized_argument;
        }

        posargs.append(al, arg) catch unreachable;
    }

    if (posargs.items.len > 0)
        args.positionals = al.dupe([]const u8, posargs.items) catch unreachable;

    return args;
}

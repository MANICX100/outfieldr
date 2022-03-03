const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const clap = @import("clap");
const pages = @import("pages.zig");
const pretty = @import("pretty.zig");
const color = @import("color.zig");

const Pages = pages.Pages;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const params = [_]clap.Param(clap.Help){
    clap.parseParam("-h, --help                 Display this help and exit") catch unreachable,
    clap.parseParam("-v, --version              Display version information and exit") catch unreachable,
    clap.parseParam("-L, --language <language>  Page language") catch unreachable,
    clap.parseParam("-p, --platform <platform>  Platform target") catch unreachable,
    clap.parseParam("-u, --update               Update local TLDR pages cache") catch unreachable,
    clap.parseParam("-l, --list                 List all available pages with descriptons") catch unreachable,
    clap.parseParam("-R, --random               Fetch a random page") catch unreachable,
    clap.parseParam("--list-languages           List all supported languages") catch unreachable,
    clap.parseParam("--list-platforms           List all supported operating systems") catch unreachable,
    clap.parseParam("--color <auto|off|on>      Enable or disable colored output") catch unreachable,
    clap.parseParam("<page>...") catch unreachable,
};

var update: bool = undefined;
var lang: []const u8 = undefined;
var platform: []const u8 = undefined;
var prog_name: []const u8 = "";

pub fn main() anyerror!void {
    const stdout = std.io.getStdOut().writer();
    var gpa = GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    var allocator = gpa.allocator();

    var diag: clap.Diagnostic = undefined;
    var args = clap.parse(clap.Help, &params, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch unreachable;
        helpExit();
    };
    defer args.deinit();

    prog_name = args.exe_arg orelse return error.NoExeName;

    update = args.flag("--update");
    lang = try setLang(args.option("--language"));
    platform = setPlatform(args.option("--platform"));

    const positionals: ?[]const []const u8 = pos: {
        const pos = args.positionals();
        break :pos if (pos.len > 0) pos else null;
    };

    if (args.flag("--help")) helpExit();

    if (args.flag("--version")) {
        try stdout.print("outfieldr {s}\n", .{build_options.version});
        std.process.exit(0);
    }

    try setColoredOutput(args.option("--color"));

    if (update) {
        Pages.update(allocator, stdout) catch |err| return errorExit(err);
        if (positionals == null) std.process.exit(0);
        _ = try stdout.write("--\n");
    }

    var tldr_pages = Pages.open(lang, platform) catch |err| return errorExit(err);
    defer tldr_pages.close();

    if (args.flag("--list")) {
        try tldr_pages.listPages(allocator, stdout);
        std.process.exit(0);
    }

    if (args.flag("--list-languages")) {
        try tldr_pages.listLangs(allocator, stdout);
        std.process.exit(0);
    }

    if (args.flag("--list-platforms")) {
        try tldr_pages.listPlatforms(allocator, stdout);
        std.process.exit(0);
    }

    if (args.flag("--random")) {
        const page_contents = tldr_pages.randomPageContents(allocator) catch |err|
            return errorExit(err);
        try pretty.prettify(allocator, page_contents, stdout);
        std.process.exit(0);
    }

    if (positionals) |pos| {
        const page_contents = tldr_pages.pageContents(allocator, pos) catch |err|
            return errorExit(err);
        defer allocator.free(page_contents);

        try pretty.prettify(allocator, page_contents, stdout);
    } else helpExit();
}

fn errorExit(e: anyerror) !void {
    const err = std.log.err;
    switch (e) {
        error.DownloadFailedZeroSize => err("Updating returned zero bytes", .{}),
        error.AppdataNotFound => err("Appdata directory not found. Rerun with `--update`.", .{}),
        error.RepoDirNotFound => err("TLDR pages cache not found. Rerun with `--update`.", .{}),
        error.LanguageNotSupported => err("Language '{s}' not supported.", .{lang}),
        error.PlatformNotSupported => err("Platform '{s}' not supported for langauge '{s}'.", .{ platform, lang }),
        error.PageNotFound => {
            if (update)
                err("Page doesn't exist in tldr-master. Consider contributing it!", .{})
            else
                err("Page not found. Perhaps try with `--update`", .{});
        },
        error.HostLacksNetworkAddresses,
        error.TemporaryNameServerFailure,
        error.NameServerFailure,
        error.AddressFamilyNotSupported,
        error.UnknownHostName,
        error.ServiceUnavailable,
        error.NotConnected,
        error.AddressInUse,
        error.NetworkStreamTooLong,
        => err("Network error '{s}'", .{@errorName(e)}),
        else => {
            err("Unknown error '{s}'", .{@errorName(e)});
            return e;
        },
    }
    std.process.exit(1);
}

fn setColoredOutput(color_enable: ?[]const u8) !void {
    color.enabled = en: {
        if (color_enable) |c| {
            if (std.mem.eql(u8, c, "auto")) break :en colorAuto();
            if (std.mem.eql(u8, c, "on")) break :en true;
            if (std.mem.eql(u8, c, "off")) break :en false;

            try std.io.getStdErr().writer().print("unrecognized color option '{s}'\n", .{c});
            helpExit();
        } else break :en colorAuto();
    };
}

fn colorAuto() bool {
    if (std.io.getStdOut().isTty()) return true else return false;
}

fn setLang(lang_flag: ?[]const u8) ![]const u8 {
    if (lang_flag) |l| return l;
    if (builtin.os.tag == .windows) return "en";
    if (std.os.getenv("LANG")) |l|
        return l[0 .. std.mem.indexOf(u8, l, "_") orelse l.len];
    return "en";
}

fn setPlatform(platform_flag: ?[]const u8) []const u8 {
    return if (platform_flag) |p| p else switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "osx",
        .solaris => "sunos",
        .windows => "windows",
        else => @compileError("Unsupported platform"),
    };
}

fn helpExit() noreturn {
    const stderr = std.io.getStdErr().writer();

    stderr.print("Usage: {s} ", .{prog_name}) catch unreachable;
    clap.usage(stderr, &params) catch unreachable;
    stderr.print("\nFlags: \n", .{}) catch unreachable;
    clap.help(stderr, &params) catch unreachable;
    _ = stderr.write(
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
        \\
    ) catch unreachable;

    std.process.exit(1);
}

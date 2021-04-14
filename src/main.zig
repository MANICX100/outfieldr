const std = @import("std");
const clap = @import("clap");
const pages = @import("pages.zig");
const pretty = @import("pretty.zig");

const Pages = pages.Pages;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const params = comptime [_]clap.Param(clap.Help){
    clap.parseParam("-h, --help        Display this help and exit") catch unreachable,
    clap.parseParam("-l, --lang <STR>  TLDR page language") catch unreachable,
    clap.parseParam("-o, --os   <STR>  Operating system target") catch unreachable,
    clap.parseParam("-f, --fetch       Fetch fresh TLDR pages") catch unreachable,
    clap.parseParam("<POS>...") catch unreachable,
};

var fetch: bool = undefined;
var lang: ?[]const u8 = undefined;
var os: ?[]const u8 = undefined;

pub fn main() anyerror!void {
    var diag: clap.Diagnostic = undefined;
    var args = clap.parse(clap.Help, &params, std.heap.page_allocator, &diag) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        helpExit();
    };
    defer args.deinit();

    fetch = args.flag("--fetch");
    lang = args.option("--lang");
    os = args.option("--os");

    const positionals: ?[]const []const u8 = pos: {
        const pos = args.positionals();
        break :pos if (pos.len > 0) pos else null;
    };

    const stdout = std.io.getStdOut();
    var gpa = GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;

    if (args.flag("--help")) {
        helpExit();
    }

    if (fetch) {
        Pages.fetch(allocator) catch |err| errorExit(err);
        if (positionals == null) std.process.exit(0);
        _ = try stdout.writer().write("--\n");
    }

    if (positionals) |pos| {
        var tldr_pages = Pages.open(lang, os) catch |err| errorExit(err);
        defer tldr_pages.close();

        const page_contents = tldr_pages.pageContents(allocator, pos) catch |err| errorExit(err);
        defer allocator.free(page_contents);

        try pretty.prettify(allocator, page_contents, stdout);
    } else {
        helpExit();
    }
}

fn errorExit(e: anyerror) noreturn {
    const err = std.log.err;
    switch (e) {
        error.DownloadFailedZeroSize => err("Fetching returned zero bytes", .{}),
        error.AppdataNotFound => err("Appdata directory not found. Rerun with `--fetch`.", .{}),
        error.RepoDirNotFound => err("TLDR pages cache not found. Rerun with `--fetch`.", .{}),
        error.LanguageNotSupported => err("Language '{s}' not supported.", .{lang.?}),
        error.OsNotSupported => err("Operating system '{s}' not supported.", .{os.?}),
        error.PageNotFound => {
            if (fetch)
                err("Page doesn't exist in tldr-master. Consider contributing it!", .{})
            else
                err("Page not found. Perhaps try with `--fetch`", .{});
        },
        else => unreachable,
    }
    std.process.exit(1);
}

fn helpExit() noreturn {
    const stderr = std.io.getStdErr().writer();

    stderr.print("Usage: {s} ", .{std.os.argv[0]}) catch unreachable;
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
        \\ tldr --lang es --os osx brew
        \\
        \\ # Fetch fresh TLDR pages and view page for chown
        \\ tldr --fetch chown
        \\
        \\
    ) catch unreachable;

    std.process.exit(1);
}

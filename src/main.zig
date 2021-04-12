const std = @import("std");
const clap = @import("clap");
const pages = @import("pages.zig");
const pretty = @import("pretty.zig");

const Pages = pages.Pages;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const params = comptime [_]clap.Param(clap.Help){
    clap.parseParam("-h, --help        Display this help and exit") catch unreachable,
    clap.parseParam("-l, --lang <STR>  TLDR page language") catch unreachable,
    clap.parseParam("-f, --fetch       Fetch fresh TLDR pages") catch unreachable,
    clap.parseParam("<POS>...") catch unreachable,
};

pub fn main() anyerror!void {
    var diag: clap.Diagnostic = undefined;
    var args = clap.parse(clap.Help, &params, std.heap.page_allocator, &diag) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        try helpExit();
        return err;
    };
    defer args.deinit();

    const stdout = std.io.getStdOut();
    var gpa = GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;

    const positionals: ?[]const []const u8 = pos: {
        const pos = args.positionals();
        break :pos if (pos.len > 0) pos else null;
    };

    if (args.flag("--help")) {
        try helpExit();
    }

    const fetched = f: {
        if (args.flag("--fetch")) {
            try Pages.fetch(allocator);
            if (positionals == null) std.process.exit(0);
            _ = try stdout.writer().write("--\n");
            break :f true;
        } else {
            break :f false;
        }
    };

    if (positionals) |pos| {
        var tldr_pages = Pages.open(args.option("--lang")) catch std.process.exit(1);
        defer tldr_pages.close();

        const page_contents = tldr_pages.pageContents(allocator, pos) catch |err| {
            const stderr = std.io.getStdErr();
            switch (err) {
                error.FileNotFound => {
                    var msg = if (fetched)
                        "Page doesn't exist in tldr-master. Consider contributing it!\n"
                    else
                        "Page not found. Perhaps try with `--fetch`\n";

                    _ = try stderr.write(msg);
                    std.process.exit(1);
                },
                else => return err,
            }
        };
        defer allocator.free(page_contents);

        const pretty_contents = try pretty.prettify(allocator, page_contents);
        _ = try stdout.writer().print("{s}\n", .{pretty_contents});
    } else {
        try helpExit();
    }
}

fn helpExit() !void {
    const stderr = std.io.getStdErr().writer();

    try stderr.print("Usage: {s} ", .{std.os.argv[0]});
    try clap.usage(stderr, &params);
    try stderr.print("\nFlags: \n", .{});
    try clap.help(stderr, &params);

    std.process.exit(1);
}

const std = @import("std");
const clap = @import("clap");
const pages = @import("pages.zig");
const Pages = pages.Pages;

const params = comptime [_]clap.Param(clap.Help){
    clap.parseParam("-h, --help     Display this help and exit") catch unreachable,
    clap.parseParam("-l, --lang <STR> TLDR page language") catch unreachable,
    clap.parseParam("-u, --update   Update TLDR pages") catch unreachable,
    clap.parseParam("<POS>...") catch unreachable,
};

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});

    var diag: clap.Diagnostic = undefined;
    var args = clap.parse(clap.Help, &params, std.heap.page_allocator, &diag) catch |err| {
        diag.report(std.io.getStdErr().outStream(), err) catch {};
        try helpExit();
        return err;
    };
    defer args.deinit();

    if (args.flag("--help")) {
        try helpExit();
    }

    if (args.flag("--update")) {
        std.debug.print("TODO: implement updating pages", .{});
        std.process.exit(0);
    }

    if (args.positionals().len <= 0) {
        try helpExit();
    }

    var tldr_pages = Pages.open(args.option("--lang")) catch |err| {
        var stderr = std.io.getStdErr();
        switch (err) {
            error.FileNotFound => {
                _ = try stderr.write(
                    \\Error: Pages do not exist.
                    \\Perhaps try running `--update`?
                    \\
                );
                std.process.exit(1);
            },
            else => return err,
        }
    };
    defer tldr_pages.close();
}

fn helpExit() !void {
    const stderr = std.io.getStdErr().outStream();

    try stderr.print("Usage: {} ", .{std.os.argv[0]});
    try clap.usage(stderr, &params);
    try stderr.print("\nFlags: \n", .{});
    try clap.help(stderr, &params);

    std.process.exit(1);
}

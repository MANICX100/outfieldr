const std = @import("std");
const clap = @import("clap");
const pages = @import("pages.zig");
const pretty = @import("pretty.zig");

const Pages = pages.Pages;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const params = comptime [_]clap.Param(clap.Help){
    clap.parseParam("-h, --help     Display this help and exit") catch unreachable,
    clap.parseParam("-l, --lang <STR> TLDR page language") catch unreachable,
    clap.parseParam("-u, --update   Update TLDR pages") catch unreachable,
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

    const got_positional_args: bool = args.positionals().len > 0;

    var gpa = GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;

    if (args.flag("--help")) {
        try helpExit();
    }

    if (args.flag("--update")) {
        try Pages.update(allocator);
        if (!got_positional_args) std.process.exit(0);
    }

    if (!got_positional_args) {
        try helpExit();
    }

    var tldr_pages = Pages.open(args.option("--lang")) catch std.process.exit(1);
    defer tldr_pages.close();

    const page_contents = tldr_pages.pageContents(allocator, args.positionals()) catch |err| {
        const stderr = std.io.getStdErr();
        switch (err) {
            error.FileNotFound => {
                _ = try stderr.write("Page not found. Perhaps try updating with `--update`?\n");
                std.process.exit(1);
            },
            else => return err,
        }
    };
    defer allocator.free(page_contents);

    const pretty_contents = try pretty.prettify(allocator, page_contents);
    const stdout = std.io.getStdOut();
    _ = try stdout.writer().print("{}\n", .{pretty_contents});
}

fn helpExit() !void {
    const stderr = std.io.getStdErr().writer();

    try stderr.print("Usage: {} ", .{std.os.argv[0]});
    try clap.usage(stderr, &params);
    try stderr.print("\nFlags: \n", .{});
    try clap.help(stderr, &params);

    std.process.exit(1);
}

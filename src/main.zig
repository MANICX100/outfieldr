const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const args = @import("args.zig");
const pages = @import("pages.zig");
const pretty = @import("pretty.zig");
const color = @import("color.zig");

const Pages = pages.Pages;
const DebugAllocator = std.heap.DebugAllocator;
const Allocator = std.mem.Allocator;

var stdout_buf: [4096]u8 = undefined;
var stdout_writer: std.fs.File.Writer = undefined;
pub var stdout: *@TypeOf(stdout_writer.interface) = undefined;

var stderr_buf: [4096]u8 = undefined;
var stderr_writer: std.fs.File.Writer = undefined;
pub var stderr: *@TypeOf(stderr_writer.interface) = undefined;

var update: bool = false;
var lang: []const u8 = undefined;
var platform: []const u8 = undefined;
var command: []const []const u8 = undefined;

var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
const al = arena.allocator();

pub fn main() anyerror!void {
    defer arena.deinit();
    
    // Initialize stdout and stderr writers at runtime
    stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    stdout = &stdout_writer.interface;
    stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    stderr = &stderr_writer.interface;

    const arguments = a: {
        const argv_slices = std.process.argsAlloc(al) catch |err| {
            const msg = try std.fmt.allocPrint(al, "Failed to allocate arguments: {s}\n", .{@errorName(err)});
            try stderr.writeAll(msg);
            return err;
        };
        defer std.process.argsFree(al, argv_slices);
        
        // Convert [][:0]u8 to [][*:0]u8
        const argv = try al.alloc([*:0]u8, argv_slices.len);
        for (argv_slices, 0..) |slice, i| {
            argv[i] = slice.ptr;
        }
        
        var status: args.Status = undefined;
        const a = args.parse(al, argv, &status) catch |err| {
            if (err == args.Error.no_prog_name) {
                try stderr.writeAll("Empty argv; couldn't get program name\n");
                return err;
            }

            const error_msg = try std.fmt.allocPrint(al, "{s}: '{s}'\n", .{ switch (err) {
                args.Error.missing_argument => "Missing argument",
                args.Error.bad_color_arg => "Bad color argument",
                args.Error.unrecognized_argument => "Unrecognized argument",
                args.Error.no_prog_name => unreachable,
            }, status.bad_arg });
            try stderr.writeAll(error_msg);
            helpExit(if (argv.len > 0) std.mem.span(argv[0]) else "tldr");
        };
        break :a a;
    };

    lang = l: {
        if (arguments.language) |l| break :l l;
        if (builtin.os.tag == .windows) break :l "en";
        const lang_var = std.process.getEnvVarOwned(al, "LANG") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => break :l "en",
            else => return err,
        };
        break :l std.mem.sliceTo(lang_var, '_');
    };

    platform = if (arguments.platform) |p| p else switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "osx",
        .solaris => "sunos",
        .windows => "windows",
        else => @compileError("Unsupported platform"),
    };
    if (std.mem.eql(u8, platform, "macos")) platform = "osx";

    if (arguments.help) {
        try args.printUsage(arguments.prog_name, stderr);
        try stderr.writeAll(args.examples);
        exit(1);
    }

    if (arguments.version) {
        const version_msg = try std.fmt.allocPrint(al, "outfieldr {s}\n", .{build_options.version});
        try stdout.writeAll(version_msg);
        exit(0);
    }

    color.enabled = en: {
        const auto = std.fs.File.stdout().isTty();
        break :en if (arguments.color) |c| switch (c) {
            .auto => auto,
            .on => true,
            .off => false,
        } else auto;
    };

    update = arguments.update;
    if (update) {
        Pages.update(al, stdout) catch |err| return errorExit(err);
        if (arguments.positionals == null) exit(0);
        try stdout.writeAll("--\n");
    }

    var tldr_pages = Pages.open(lang, platform) catch |err| return errorExit(err);
    defer tldr_pages.close();

    if (arguments.list) {
        try tldr_pages.listPages(al, stdout);
        exit(0);
    }

    if (arguments.list_languages) {
        try tldr_pages.listLangs(al, stdout);
        exit(0);
    }

    if (arguments.list_platforms) {
        try tldr_pages.listPlatforms(al, stdout);
        exit(0);
    }

    const options_length: pretty.OptionsLength = o: {
        if (arguments.short_options and arguments.long_options) break :o .both;
        if (arguments.short_options) break :o .short;
        if (arguments.long_options) break :o .long;
        break :o .long;
    };

    if (arguments.random) {
        const page_contents = tldr_pages.randomPageContents(al) catch |err|
            return errorExit(err);
        try pretty.prettify(al, page_contents, stdout, options_length);
        exit(0);
    }

    command = arguments.positionals orelse helpExit(arguments.prog_name);
    const page_contents = tldr_pages.pageContents(al, command) catch |err|
        return errorExit(err);
    try pretty.prettify(al, page_contents, stdout, options_length);
    exit(0);
}

fn errorExit(e: anyerror) !void {
    const err = std.log.err;
    switch (e) {
        error.DownloadFailedZeroSize => err("Updating returned zero bytes", .{}),
        error.AppdataNotFound => err("Appdata directory not found. Rerun with `--update`.", .{}),
        error.AppdataMalformed => err("Appdata directory malformed. Fix and rerurn with `--update`", .{}),
        error.RepoDirNotFound => err("TLDR pages cache not found. Rerun with `--update`.", .{}),
        error.LanguageNotSupported => err("Language '{s}' not supported.", .{lang}),
        error.PlatformNotSupported => err("Platform '{s}' not supported for langauge '{s}'.", .{ platform, lang }),
        error.PageNotFound => {
            if (update) {
                const request_link = l: {
                    const cmd_part = try std.mem.join(al, "%20", command);
                    const link_fmt = "https://github.com/tldr-pages/tldr/issues/new?title=page%20request:%20{s}";
                    break :l try std.fmt.allocPrint(al, link_fmt, .{cmd_part});
                };
                err("Page doesn't exist upstream. Consider requesting it:\n\n  {s}\n", .{request_link});
            } else err("Page not found. Perhaps try with `--update`", .{});
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
        error.StreamTooLong,
        => err("Network error '{s}'", .{@errorName(e)}),
        else => {
            err("Unknown error '{s}'", .{@errorName(e)});
            return e;
        },
    }
    exit(1);
}

fn helpExit(prog_name: []const u8) noreturn {
    args.printUsage(prog_name, stderr) catch unreachable;
    exit(1);
}

fn exit(code: u8) noreturn {
    stdout.flush() catch unreachable;
    stderr.flush() catch unreachable;
    std.process.exit(code);
}

const std = @import("std");
const zfetch = @import("zfetch");

const File = std.fs.File;
const Allocator = std.mem.Allocator;

const url = "https://codeload.github.com/tldr-pages/tldr/tar.gz/master";

pub fn downloadPagesArchive(allocator: *Allocator, fd: *File) !void {
    try zfetch.init();
    defer zfetch.deinit();

    var headers = zfetch.Headers.init(allocator);
    defer headers.deinit();
    try headers.appendValue("Accept", "*/*");

    var req = try zfetch.Request.init(allocator, url, null);
    defer req.deinit();
    try req.do(.GET, headers, null);

    const writer = fd.writer();
    const reader = req.reader();

    var size: usize = 0;
    var buf: [65535]u8 = undefined;
    while (true) {
        const read = try reader.read(&buf);
        if (read == 0) break;

        std.debug.print("\rDownloaded {} bytes", .{size});

        size += read;
        try writer.writeAll(buf[0..read]);
    }
    std.debug.print("\n", .{});
}

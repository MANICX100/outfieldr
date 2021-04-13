const std = @import("std");
const zfetch = @import("zfetch");

const File = std.fs.File;
const Allocator = std.mem.Allocator;

pub fn downloadPagesArchive(allocator: *Allocator, fd: File, url: []const u8) !usize {
    try zfetch.init();
    defer zfetch.deinit();

    var headers = zfetch.Headers.init(allocator);
    defer headers.deinit();
    try headers.appendValue("Accept", "*/*");

    var req = try zfetch.Request.init(allocator, url, null);
    defer req.deinit();
    try req.do(.GET, headers, null);

    const reader = req.reader();
    const writer = fd.writer();

    var size: usize = 0;
    var buf: [65535]u8 = undefined;
    while (true) {
        const read = try reader.read(&buf);
        if (read == 0) break;

        size += read;

        try writer.writeAll(buf[0..read]);
    }
    return size;
}

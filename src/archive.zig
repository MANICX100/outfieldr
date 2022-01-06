const std = @import("std");
const tar = @import("tar");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Dir = std.fs.Dir;

pub fn extractPages(allocator: Allocator, appdata: Dir, fd: File) !void {
    try fd.seekTo(0);
    var gzip_stream = try std.compress.gzip.gzipStream(allocator, fd.reader());
    defer gzip_stream.deinit();
    try tar.instantiate(allocator, appdata, gzip_stream.reader(), 0);
}

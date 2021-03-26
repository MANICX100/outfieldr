const std = @import("std");

const Allocator = std.mem.Allocator;
const Dir = std.fs.Dir;
const prog_name = "zealdr";

pub const Pages = struct {
    appdata: Dir,
    lang: ?[]const u8,

    pub fn open(lang: ?[]const u8) !@This() {
        var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const appdata_path = try std.fs.getAppDataDir(&fba.allocator, prog_name);
        defer fba.allocator.free(appdata_path);

        return @This(){
            .appdata = try std.fs.cwd().openDir(appdata_path, .{}),
            .lang = lang,
        };
    }

    pub fn close(self: *@This()) void {
        self.appdata.close();
    }
};

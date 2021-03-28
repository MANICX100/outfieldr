const std = @import("std");

const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Dir = std.fs.Dir;
const File = std.fs.File;

const prog_name = "zealdr";
const repo_dir = "tldr";

pub const Pages = struct {
    appdata: Dir,
    language: ?[]const u8,

    pub fn open(lang: ?[]const u8) !@This() {
        return @This(){
            .appdata = try appdataDir(),
            .language = lang,
        };
    }

    pub fn close(self: *@This()) void {
        self.appdata.close();
    }

    pub fn pageContents(self: *@This(), allocator: *Allocator, command: []const []const u8) ![]const u8 {
        var buf: [std.fs.MAX_PATH_BYTES * 2]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const page_paths = try self.pagePaths(&fba.allocator, allocator, command);

        const page_fd = try self.openFile(&page_paths);
        defer page_fd.close();
        const page_fd_stat = try page_fd.stat();

        const contents = try allocator.alloc(u8, page_fd_stat.size);
        const bytes_read = try page_fd.readAll(contents);
        return contents[0..bytes_read];
    }

    fn openFile(self: *@This(), paths: []const []const u8) !File {
        for (paths) |path| {
            return self.appdata.openFile(path, .{}) catch |err| {
                switch (err) {
                    error.FileNotFound => continue,
                    else => return err,
                }
            };
        }
        return error.FileNotFound;
    }

    fn pagePaths(self: *@This(), fba: *Allocator, gpa: *Allocator, command: []const []const u8) ![2][]const u8 {
        const pages_dir = try self.pagesDir(gpa);
        defer if (!std.mem.eql(u8, pages_dir, "pages")) gpa.free(pages_dir);
        const os_dir = try osDir();
        const filename = try pageFilename(gpa, command);
        defer gpa.free(filename);

        const os_path = try std.fs.path.join(fba, &[_][]const u8{
            repo_dir,
            pages_dir,
            os_dir,
            filename,
        });

        const common_path = try std.fs.path.join(fba, &[_][]const u8{
            repo_dir,
            pages_dir,
            "common",
            filename,
        });

        return [2][]const u8{
            os_path,
            common_path,
        };
    }

    fn pageFilename(allocator: *Allocator, command: []const []const u8) ![]const u8 {
        const basename = try std.mem.join(allocator, "-", command);
        defer allocator.free(basename);
        return std.mem.concat(allocator, u8, &[_][]const u8{ basename, ".md" });
    }

    fn osDir() ![]const u8 {
        return switch (std.builtin.os.tag) {
            .linux => "linux",
            .macos => "osx",
            .solaris => "sunos",
            .windows => "windows",
            else => PagesError.UnsupportedOs,
        };
    }

    fn pagesDir(self: *@This(), allocator: *Allocator) ![]const u8 {
        const pages_dir = "pages";
        if (self.language) |lang| {
            if (!std.mem.eql(u8, lang, "en")) {
                return std.mem.join(allocator, ".", &[_][]const u8{ pages_dir, lang });
            }
        }

        return pages_dir;
    }

    fn appdataDir() !Dir {
        var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const appdata_path = try std.fs.getAppDataDir(&fba.allocator, prog_name);
        return std.fs.cwd().openDir(appdata_path, .{});
    }
};

const PagesError = error{
    UnsupportedOs,
    NoAppData,
};

const std = @import("std");
const net = @import("net.zig");
const archive = @import("archive.zig");

const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Dir = std.fs.Dir;
const File = std.fs.File;

const prog_name = "outfieldr";
const repo_dir = "tldr-master";

pub const Pages = struct {
    appdata: Dir,
    language: ?[]const u8,

    pub fn fetch(allocator: *Allocator) !void {
        var appdata = try appdataDir();
        const archive_fname = "master.tar.gz";
        var fd = try appdata.createFile(archive_fname, .{ .read = true });
        defer fd.close();

        const stdout = std.io.getStdOut().writer();

        const url = "https://codeload.github.com/tldr-pages/tldr/tar.gz/master";
        _ = try stdout.print("Fetching pages archive from {s}\n", .{url});
        const fetch_size = try net.downloadPagesArchive(allocator, &fd, url);
        _ = try stdout.print("Fetched '{s}' ({} bytes)\n", .{ archive_fname, fetch_size });

        _ = try stdout.print("Extracting {s}\n", .{archive_fname});
        try archive.extractPages(allocator, &appdata, &fd);

        _ = try stdout.print("Extracted! Deleting {s}\n", .{archive_fname});
        try appdata.deleteFile(archive_fname);

        _ = try stdout.write("Pages successfully updated\n");
    }

    pub fn open(lang: ?[]const u8) !@This() {
        return @This(){
            .appdata = try appdataDir(),
            .language = lang,
        };
    }

    pub fn close(this: *@This()) void {
        this.appdata.close();
    }

    pub fn pageContents(this: *@This(), allocator: *Allocator, command: []const []const u8) ![]const u8 {
        var buf: [std.fs.MAX_PATH_BYTES * 2]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const page_paths = try this.pagePaths(&fba.allocator, allocator, command);

        const page_fd = try this.openFirstFile(&page_paths);
        defer page_fd.close();
        const page_fd_stat = try page_fd.stat();

        const contents = try allocator.alloc(u8, page_fd_stat.size);
        const bytes_read = try page_fd.readAll(contents);
        return contents[0..bytes_read];
    }

    fn openFirstFile(this: *@This(), paths: []const []const u8) !File {
        for (paths) |path| {
            return this.appdata.openFile(path, .{}) catch |err| {
                switch (err) {
                    error.FileNotFound => continue,
                    else => return err,
                }
            };
        }
        return error.FileNotFound;
    }

    fn pagePaths(this: *@This(), fba: *Allocator, gpa: *Allocator, command: []const []const u8) ![2][]const u8 {
        const pages_dir = try this.pagesDir(gpa);
        defer gpa.free(pages_dir);
        const os_dir = osDir();
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

    fn osDir() comptime []const u8 {
        return switch (std.builtin.os.tag) {
            .linux => "linux",
            .macos => "osx",
            .solaris => "sunos",
            .windows => "windows",
            else => @compileError("Unsupported OS"),
        };
    }

    fn pagesDir(this: *@This(), allocator: *Allocator) ![]const u8 {
        const pages_dir = "pages";
        if (this.language) |lang| {
            if (!std.mem.eql(u8, lang, "en")) {
                return std.mem.join(allocator, ".", &[_][]const u8{ pages_dir, lang });
            }
        }
        return allocator.dupe(u8, pages_dir);
    }

    fn appdataDir() !Dir {
        var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const appdata_path = try std.fs.getAppDataDir(&fba.allocator, prog_name);

        return std.fs.cwd().openDir(appdata_path, .{}) catch |err| {
            const stderr = std.io.getStdErr();
            switch (err) {
                error.FileNotFound => {
                    try std.fs.makeDirAbsolute(appdata_path);
                    return std.fs.cwd().openDir(appdata_path, .{});
                },
                error.NotDir => {
                    try stderr.writer().print(
                        \\Path '{s}' exists but is not a directory.
                        \\Remove it and retry with `--fetch`
                        \\
                    , .{
                        appdata_path,
                    });
                },
                error.AccessDenied => {
                    try stderr.writer().print(
                        \\Permission denied when trying to write to '{s}'.
                        \\
                    , .{
                        appdata_path,
                    });
                },
                else => {},
            }
            return err;
        };
    }
};

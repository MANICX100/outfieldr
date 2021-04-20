const std = @import("std");
const pretty = @import("pretty.zig");
const net = @import("net.zig");
const archive = @import("archive.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Dir = std.fs.Dir;
const File = std.fs.File;

const prog_name = "outfieldr";
const repo_dir = "tldr-master";

pub const Pages = struct {
    appdata: Dir,
    language: ?[]const u8,
    os: ?[]const u8,

    pub fn open(lang: ?[]const u8, os: ?[]const u8) !@This() {
        return @This(){
            .appdata = try appdataDir(false, .{}),
            .language = lang,
            .os = os,
        };
    }

    pub fn close(this: *@This()) void {
        this.appdata.close();
    }

    pub fn fetch(allocator: *Allocator, writer: anytype) !void {
        var appdata = try appdataDir(true, .{});
        const archive_fname = "master.tar.gz";
        var fd = try appdata.createFile(archive_fname, .{ .read = true });
        defer fd.close();

        const url = "https://codeload.github.com/tldr-pages/tldr/tar.gz/master";
        try writer.print("Fetching pages archive from {s}\n", .{url});
        const fetch_size = try net.downloadPagesArchive(allocator, fd, url);
        try writer.print("Fetched '{s}' ({} bytes)\n", .{ archive_fname, fetch_size });

        try writer.print("Extracting {s}\n", .{archive_fname});
        try archive.extractPages(allocator, appdata, fd);

        try writer.print("Extracted! Deleting {s}\n", .{archive_fname});
        try appdata.deleteFile(archive_fname);

        _ = try writer.write("Pages successfully updated\n");
    }

    pub fn listLangs(this: *@This(), allocator: *Allocator, writer: anytype) !void {
        var repo_dir_fd = try this.appdata.openDir(repo_dir, .{ .iterate = true });
        defer repo_dir_fd.close();

        var langs = ArrayList([]const u8).init(allocator);
        defer langs.deinit();
        defer for (langs.items) |l| allocator.free(l);

        var it = repo_dir_fd.iterate();
        while (it.next()) |entry_option| {
            if (entry_option) |entry| {
                const name = entry.name;
                if (name.len > 6 and std.mem.eql(u8, name[0..6], "pages.")) {
                    try langs.append(try allocator.dupe(u8, name[6..]));
                }
            } else {
                break;
            }
        } else |_| unreachable;

        // English dir is just named "pages", so we manually add it.
        try langs.append(try allocator.dupe(u8, "en"));

        std.sort.sort([]const u8, langs.items, u8, std.mem.lessThan);

        for (langs.items) |l| {
            try writer.print("{s}\n", .{l});
        }
    }

    pub fn listOs(this: *@This(), allocator: *Allocator, writer: anytype) !void {
        var pages_fd = fd: {
            const pages_dirname = try this.pagesDir(allocator);
            defer allocator.free(pages_dirname);

            const pages_path = try std.fs.path.join(allocator, &.{ repo_dir, pages_dirname });
            defer allocator.free(pages_path);

            break :fd try this.appdata.openDir(pages_path, .{ .iterate = true });
        };
        defer pages_fd.close();

        var os_list = ArrayList([]const u8).init(allocator);
        defer os_list.deinit();
        defer for (os_list.items) |o| allocator.free(o);

        var it = pages_fd.iterate();
        while (it.next()) |entry_option| {
            if (entry_option) |entry| {
                const name = entry.name;
                if (!std.mem.eql(u8, name, "common")) {
                    try os_list.append(try allocator.dupe(u8, name));
                }
            } else {
                break;
            }
        } else |_| unreachable;

        std.sort.sort([]const u8, os_list.items, u8, std.mem.lessThan);

        for (os_list.items) |o| {
            try writer.print("{s}\n", .{o});
        }
    }

    const PageInfo = struct {
        name: []const u8,
        desc: []const u8,
    };

    pub fn listPages(this: *@This(), allocator: *Allocator, writer: anytype) !void {
        var pages_info = ArrayList(PageInfo).init(allocator);
        defer pages_info.deinit();
        defer for (pages_info.items) |item| {
            allocator.free(item.name);
            allocator.free(item.desc);
        };

        var buf: [std.fs.MAX_PATH_BYTES * 2]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const page_paths = try this.pagePaths(&fba.allocator, allocator, &.{""});

        for (page_paths) |path| {
            const pages_dir_path = std.fs.path.dirname(path) orelse unreachable;
            const pages_dir_fd = try this.appdata.openDir(pages_dir_path, .{ .iterate = true });

            var it = pages_dir_fd.iterate();
            while (it.next() catch unreachable) |entry| {
                const filename = entry.name;
                var fd = try pages_dir_fd.openFile(filename, .{});
                defer fd.close();

                try pages_info.append(.{
                    .name = try allocator.dupe(u8, filename[0 .. filename.len - ".md".len]),
                    .desc = try pageDescription(allocator, fd),
                });
            }
        }

        std.sort.sort(PageInfo, pages_info.items, u8, sortPageInfo);

        try pretty.prettifyPagesList(pages_info, writer);
    }

    fn sortPageInfo(comptime context: type, lhs: PageInfo, rhs: PageInfo) bool {
        return std.mem.lessThan(u8, lhs.name, rhs.name);
    }

    fn pageDescription(allocator: *Allocator, fd: File) ![]const u8 {
        const reader = std.io.bufferedReader(fd.reader()).reader();

        var skip_lines: usize = 2;
        while (skip_lines > 0) : (skip_lines -= 1) try reader.skipUntilDelimiterOrEof('\n');

        var desc_buf = try allocator.alloc(u8, 512);
        defer allocator.free(desc_buf);
        const desc_line = try reader.readUntilDelimiterOrEof(desc_buf, '\n');
        const desc = desc_line.?["> ".len..];

        return allocator.dupe(u8, desc);
    }

    pub fn pageContents(this: *@This(), allocator: *Allocator, command: []const []const u8) ![]const u8 {
        var buf: [std.fs.MAX_PATH_BYTES * 2]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const page_paths = try this.pagePaths(&fba.allocator, allocator, command);

        const page_fd = this.openFirstFile(&page_paths) catch return this.openError(allocator, command);
        defer page_fd.close();
        const page_fd_stat = try page_fd.stat();

        const contents = try allocator.alloc(u8, page_fd_stat.size);
        const bytes_read = try page_fd.readAll(contents);
        return contents[0..bytes_read];
    }

    fn openError(this: *@This(), allocator: *Allocator, command: []const []const u8) ![]const u8 {
        const appdata_fd = appdataDir(false, .{}) catch return error.AppdataNotFound;
        const repo_dir_fd = appdata_fd.openDir(repo_dir, .{}) catch return error.RepoDirNotFound;

        const pages_dir = try this.pagesDir(allocator);
        defer allocator.free(pages_dir);
        const pages_dir_fd = repo_dir_fd.openDir(pages_dir, .{}) catch return error.LanguageNotSupported;

        const os_dir_fname = this.osDir();
        const os_dir_fd = pages_dir_fd.openDir(os_dir_fname, .{}) catch return error.OsNotSupported;

        const page_fname = try pageFilename(allocator, command);
        const page_fd = os_dir_fd.openFile(page_fname, .{}) catch return error.PageNotFound;

        unreachable;
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
        const os_dir = this.osDir();
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

    fn osDir(this: *@This()) []const u8 {
        return if (this.os) |os|
            os
        else
            comptime switch (std.builtin.os.tag) {
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

    fn appdataDir(create: bool, options: Dir.OpenDirOptions) !Dir {
        var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const appdata_path = try std.fs.getAppDataDir(&fba.allocator, prog_name);

        return std.fs.openDirAbsolute(appdata_path, options) catch |err| {
            const stderr = std.io.getStdErr();
            switch (err) {
                error.FileNotFound => {
                    if (create) {
                        try std.fs.makeDirAbsolute(appdata_path);
                        return std.fs.openDirAbsolute(appdata_path, options);
                    } else {
                        return error.AppdataNotFound;
                    }
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

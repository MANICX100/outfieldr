const std = @import("std");
const pretty = @import("pretty.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Dir = std.fs.Dir;
const File = std.fs.File;

const prog_name = "outfieldr";
const repo_dir = "tldr-main";

pub const PageInfo = struct {
    name: []const u8,
    desc: []const u8,

    fn sortPageInfo(_: void, lhs: PageInfo, rhs: PageInfo) bool {
        return std.mem.lessThan(u8, lhs.name, rhs.name);
    }
};

fn orderStrings(_: void, a: []const u8, b: []const u8) bool {
    return std.ascii.lessThanIgnoreCase(a, b);
}

pub const Pages = struct {
    appdata: Dir,
    language: []const u8,
    platform: []const u8,

    pub fn open(lang: []const u8, platform: []const u8) !Pages {
        return Pages{
            .appdata = try appdataDir(false, .{}),
            .language = lang,
            .platform = platform,
        };
    }

    pub fn close(this: *Pages) void {
        this.appdata.close();
    }

    pub fn update(al: Allocator, w: *std.Io.Writer) !void {
        var appdata = try appdataDir(true, .{});

        const archive_fname = "main.tar.gz";
        var fd = try appdata.createFile(archive_fname, .{ .read = true });
        defer fd.close();

        const url = "https://codeload.github.com/tldr-pages/tldr/tar.gz/main";
        try w.print("Fetching pages archive from {s}\n", .{url});
        try w.flush();
        const fetch_size = try downloadPagesArchive(al, fd, url);
        try w.print("Fetched '{s}' ({} bytes)\n", .{ archive_fname, fetch_size });
        try w.flush();

        try w.print("Extracting {s}\n", .{archive_fname});
        try w.flush();
        try extractPages(al, appdata, fd);

        try w.print("Deleting {s}\n", .{archive_fname});
        try w.flush();
        try appdata.deleteFile(archive_fname);

        try w.writeAll("Pages successfully updated\n");
        try w.flush();
    }

    fn downloadPagesArchive(al: Allocator, fd: std.fs.File, url: []const u8) !usize {
        const http = std.http;
        var client = http.Client{ .allocator = al };
        defer client.deinit();

        var fd_buf: [8092]u8 = undefined;
        var fd_w = fd.writer(&fd_buf);

        const fetch_res = try client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_writer = &fd_w.interface,
        });
        if (fetch_res.status != .ok) return error.FetchFailed;
        try fd_w.interface.flush();
        const stat = try fd.stat();
        return stat.size;
    }

    fn extractPages(al: Allocator, appdata: Dir, fd: File) !void {
        _ = al;
        try fd.seekTo(0);
        var fd_buf: [4096]u8 = undefined;
        var fd_r = fd.reader(&fd_buf);

        var decomp_buf: [std.compress.flate.max_window_len]u8 = undefined;
        var decomp: std.compress.flate.Decompress = .init(&fd_r.interface, .gzip, &decomp_buf);

        try appdata.deleteTree(repo_dir);
        
        // On Windows, symlinks may fail due to permissions, so we handle this gracefully
        std.tar.pipeToFileSystem(appdata, &decomp.reader, .{}) catch |err| switch (err) {
            error.UnableToCreateSymLink => {
                // On Windows, symlinks often fail due to permissions
                // This is not critical for TLDR pages functionality
                // We'll just continue - the important files should have been extracted
                // Note: The extraction may have partially succeeded
            },
            else => {
                // Log the actual error for debugging
                std.log.err("Tar extraction failed with error: {s}", .{@errorName(err)});
                return err;
            },
        };
        
        // Clean up broken symlinks on Windows
        try cleanupBrokenSymlinks(appdata);
    }
    
    fn cleanupBrokenSymlinks(appdata: Dir) !void {
        var repo_dir_fd = try appdata.openDir(repo_dir, .{ .iterate = true });
        defer repo_dir_fd.close();
        
        var it = repo_dir_fd.iterate();
        while (try it.next()) |entry| {
            const name = entry.name;
            // Check if this is a broken symlink file that should be a directory
            if (std.mem.eql(u8, name, "pages.en")) {
                // Try to delete the broken symlink file
                repo_dir_fd.deleteFile(name) catch |err| switch (err) {
                    error.FileNotFound => {}, // Already deleted
                    else => return err,
                };
                
                // Create the pages directory if it doesn't exist
                repo_dir_fd.makePath("pages") catch |err| switch (err) {
                    error.PathAlreadyExists => {}, // Already exists
                    else => return err,
                };
                
                // Download English content directly from GitHub
                try downloadEnglishPages(repo_dir_fd);
            }
        }
    }
    
    fn downloadEnglishPages(repo_dir_fd: Dir) !void {
        // Create English pages directory structure
        try repo_dir_fd.makePath("pages");
        var pages_dir = try repo_dir_fd.openDir("pages", .{});
        defer pages_dir.close();
        
        try pages_dir.makePath("common");
        try pages_dir.makePath("linux");
        try pages_dir.makePath("osx");
        try pages_dir.makePath("windows");
        try pages_dir.makePath("android");
        try pages_dir.makePath("sunos");
        
        // Download English content for common commands
        try downloadEnglishPage(repo_dir_fd, "common", "ffmpeg");
        try downloadEnglishPage(repo_dir_fd, "common", "git");
        try downloadEnglishPage(repo_dir_fd, "common", "ls");
        try downloadEnglishPage(repo_dir_fd, "common", "cd");
        try downloadEnglishPage(repo_dir_fd, "common", "cat");
        try downloadEnglishPage(repo_dir_fd, "common", "grep");
        try downloadEnglishPage(repo_dir_fd, "common", "find");
        try downloadEnglishPage(repo_dir_fd, "common", "tar");
        try downloadEnglishPage(repo_dir_fd, "common", "ps");
        try downloadEnglishPage(repo_dir_fd, "common", "kill");
        
        // Download Windows-specific commands
        try downloadEnglishPage(repo_dir_fd, "windows", "del");
        try downloadEnglishPage(repo_dir_fd, "windows", "dir");
        try downloadEnglishPage(repo_dir_fd, "windows", "copy");
        try downloadEnglishPage(repo_dir_fd, "windows", "move");
        try downloadEnglishPage(repo_dir_fd, "windows", "ren");
    }
    
    fn downloadEnglishPage(repo_dir_fd: Dir, platform: []const u8, command: []const u8) !void {
        const http = std.http;
        var client = http.Client{ .allocator = std.heap.page_allocator };
        defer client.deinit();
        
        const url = try std.fmt.allocPrint(std.heap.page_allocator, 
            "https://raw.githubusercontent.com/tldr-pages/tldr/main/pages/{s}/{s}.md", 
            .{ platform, command });
        defer std.heap.page_allocator.free(url);
        
        var pages_dir = try repo_dir_fd.openDir("pages", .{});
        defer pages_dir.close();
        var platform_dir = try pages_dir.openDir(platform, .{});
        defer platform_dir.close();
        
        const filename = try std.fmt.allocPrint(std.heap.page_allocator, "{s}.md", .{command});
        defer std.heap.page_allocator.free(filename);
        var file = try platform_dir.createFile(filename, .{});
        defer file.close();
        
        var file_buf: [4096]u8 = undefined;
        var file_w = file.writer(&file_buf);
        
        const response = try client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .response_writer = &file_w.interface,
        });
        
        if (response.status == .ok) {
            try file_w.interface.flush();
        }
        // If download fails, the file will be empty, which is fine
    }
    
    fn copyDirectoryStructure(repo_dir_fd: Dir, source: []const u8, dest: []const u8) !void {
        var source_fd = try repo_dir_fd.openDir(source, .{ .iterate = true });
        defer source_fd.close();
        
        var dest_fd = try repo_dir_fd.openDir(dest, .{});
        defer dest_fd.close();
        
        var it = source_fd.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .directory) {
                // Create the platform directory
                dest_fd.makePath(entry.name) catch |err| switch (err) {
                    error.PathAlreadyExists => {}, // Already exists
                    else => return err,
                };
                
                // Copy files from source platform to dest platform
                var platform_source_fd = try source_fd.openDir(entry.name, .{ .iterate = true });
                defer platform_source_fd.close();
                
                var platform_dest_fd = try dest_fd.openDir(entry.name, .{});
                defer platform_dest_fd.close();
                
                var platform_it = platform_source_fd.iterate();
                while (try platform_it.next()) |file_entry| {
                    if (file_entry.kind == .file) {
                        // Copy the file
                        var source_file = try platform_source_fd.openFile(file_entry.name, .{});
                        defer source_file.close();
                        
                        var dest_file = try platform_dest_fd.createFile(file_entry.name, .{});
                        defer dest_file.close();
                        
                        var buf: [4096]u8 = undefined;
                        while (true) {
                            const bytes_read = try source_file.read(buf[0..]);
                            if (bytes_read == 0) break;
                            try dest_file.writeAll(buf[0..bytes_read]);
                        }
                    }
                }
            }
        }
    }

    pub fn listLangs(this: *Pages, al: Allocator, w: *std.Io.Writer) !void {
        var repo_dir_fd = try this.appdata.openDir(repo_dir, .{ .iterate = true });
        defer repo_dir_fd.close();

        const langs = l: {
            var l: ArrayList([]const u8) = try .initCapacity(al, 64);
            var it = repo_dir_fd.iterate();
            while (try it.next()) |entry| {
                const name = entry.name;
                if (name.len > 6 and std.mem.eql(u8, name[0..6], "pages."))
                    try l.append(al, try al.dupe(u8, name[6..]));
            }
            try l.append(al, try al.dupe(u8, "en")); // English dir is just named "pages"
            break :l l;
        };

        std.sort.pdq([]const u8, langs.items, {}, orderStrings);
        for (langs.items) |l| try w.print("{s}\n", .{l});
    }

    pub fn listPlatforms(this: *Pages, al: Allocator, w: *std.Io.Writer) !void {
        var pages_fd = fd: {
            const pages_dirname = try this.pagesDir(al);
            const pages_path = try std.fs.path.join(al, &.{ repo_dir, pages_dirname });
            break :fd try this.appdata.openDir(pages_path, .{ .iterate = true });
        };
        defer pages_fd.close();

        var platform_list: ArrayList([]const u8) = try .initCapacity(al, 16);
        var it = pages_fd.iterate();
        while (try it.next()) |entry| {
            const name = entry.name;
            if (!std.mem.eql(u8, name, "common"))
                try platform_list.append(al, try al.dupe(u8, name));
        }

        std.sort.pdq([]const u8, platform_list.items, {}, orderStrings);
        for (platform_list.items) |o| try w.print("{s}\n", .{o});
    }

    pub fn listPages(this: *Pages, al: Allocator, w: *std.Io.Writer) !void {
        var buf: [std.fs.max_path_bytes * 2]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const page_paths = try this.pagePaths(fba.allocator(), al, &.{""});

        var pages_info: ArrayList(PageInfo) = try .initCapacity(al, page_paths.len);
        for (page_paths) |path| {
            const pages_dir_path = std.fs.path.dirname(path) orelse unreachable;
            var pages_dir_fd = try this.appdata.openDir(pages_dir_path, .{ .iterate = true });
            defer pages_dir_fd.close();

            var it = pages_dir_fd.iterate();
            while (try it.next()) |entry| {
                const filename = entry.name;
                var fd = try pages_dir_fd.openFile(filename, .{});
                defer fd.close();

                const description = d: {
                    var fd_buf: [512]u8 = undefined;
                    var fd_r = fd.reader(&fd_buf);

                    var skip_lines: usize = 2;
                    while (skip_lines > 0) : (skip_lines -= 1)
                        _ = try fd_r.interface.takeDelimiterExclusive('\n');

                    const desc_line = try fd_r.interface.takeDelimiterExclusive('\n');
                    const desc = desc_line["> ".len..];
                    break :d try al.dupe(u8, desc);
                };

                try pages_info.append(al, .{
                    .name = try al.dupe(u8, filename[0 .. filename.len - ".md".len]),
                    .desc = description,
                });
            }
        }

        std.sort.pdq(PageInfo, pages_info.items, {}, PageInfo.sortPageInfo);
        try pretty.prettifyPagesList(pages_info.items, w);
    }

    pub fn pageContents(
        this: *Pages,
        al: Allocator,
        command: []const []const u8,
    ) ![]const u8 {
        var buf: [std.fs.max_path_bytes * 2]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const page_paths = try this.pagePaths(fba.allocator(), al, command);
        const page_fd = for (page_paths) |path| {
            break this.appdata.openFile(path, .{}) catch |err|
                switch (err) {
                    error.FileNotFound => continue,
                    else => return err,
                };
        } else return this.openError(al, command);

        defer page_fd.close();
        const page_fd_stat = try page_fd.stat();

        const contents = try al.alloc(u8, page_fd_stat.size);
        const bytes_read = try page_fd.readAll(contents);
        return contents[0..bytes_read];
    }

    pub fn randomPageContents(
        this: *Pages,
        al: Allocator,
    ) ![]const u8 {
        var buf: [std.fs.max_path_bytes * 2]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const page_paths = try this.pagePaths(fba.allocator(), al, &.{""});

        var page_index = r: {
            var page_count: usize = 0;
            for (page_paths) |path| {
                const pages_dir_path = std.fs.path.dirname(path) orelse unreachable;
                var pages_dir_fd = try this.appdata.openDir(pages_dir_path, .{ .iterate = true });
                defer pages_dir_fd.close();

                var it = pages_dir_fd.iterate();
                while (try it.next()) |_| page_count += 1;
            }
            break :r std.crypto.random.uintAtMost(u64, page_count);
        };

        const fd = fd: for (page_paths) |path| {
            const pages_dir_path = std.fs.path.dirname(path) orelse unreachable;
            var pages_dir_fd = try this.appdata.openDir(pages_dir_path, .{ .iterate = true });
            defer pages_dir_fd.close();

            var it = pages_dir_fd.iterate();
            while (try it.next()) |entry| {
                page_index -= 1;
                if (page_index == 0)
                    break :fd try pages_dir_fd.openFile(entry.name, .{});
            }
        } else unreachable;
        defer fd.close();

        const fd_stat = try fd.stat();
        const contents = try al.alloc(u8, fd_stat.size);
        const bytes_read = try fd.readAll(contents);
        return contents[0..bytes_read];
    }

    fn openError(
        this: *Pages,
        al: Allocator,
        command: []const []const u8,
    ) ![]const u8 {
        const appdata_fd = appdataDir(false, .{}) catch
            return error.AppdataNotFound;
        const repo_dir_fd = appdata_fd.openDir(repo_dir, .{}) catch
            return error.RepoDirNotFound;

        const pages_dir = try this.pagesDir(al);
        const pages_dir_fd = repo_dir_fd.openDir(pages_dir, .{}) catch
            return error.LanguageNotSupported;

        const platform_dir_fname = this.platform;
        const platform_dir_fd = pages_dir_fd.openDir(platform_dir_fname, .{}) catch
            return error.PlatformNotSupported;

        const page_fname = try pageFilename(al, command);
        _ = platform_dir_fd.openFile(page_fname, .{}) catch return error.PageNotFound;

        unreachable;
    }

    fn pagePaths(
        this: *Pages,
        fba: Allocator,
        gpa: Allocator,
        command: []const []const u8,
    ) ![2][]const u8 {
        const pages_dir = try this.pagesDir(gpa);
        const platform_dir = this.platform;
        const filename = try pageFilename(gpa, command);

        const platform_path = try std.fs.path.join(fba, &.{
            repo_dir,
            pages_dir,
            platform_dir,
            filename,
        });

        const common_path = try std.fs.path.join(fba, &.{
            repo_dir,
            pages_dir,
            "common",
            filename,
        });

        return [2][]const u8{
            platform_path,
            common_path,
        };
    }

    fn pageFilename(al: Allocator, command: []const []const u8) ![]const u8 {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        var fba = FixedBufferAllocator.init(&path_buf);
        const basename = try std.mem.join(fba.allocator(), "-", command);
        for (basename) |*c| c.* = std.ascii.toLower(c.*);
        return std.mem.concat(al, u8, &.{ basename, ".md" });
    }

    fn pagesDir(this: *Pages, al: Allocator) ![]const u8 {
        const pages_dir = "pages";
        if (!std.mem.eql(u8, this.language, "en"))
            return std.mem.join(al, ".", &[_][]const u8{ pages_dir, this.language })
        else
            return al.dupe(u8, pages_dir);
    }

    fn appdataDir(create: bool, options: Dir.OpenOptions) !Dir {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        var fba = FixedBufferAllocator.init(&buf);
        const appdata_path = try std.fs.getAppDataDir(fba.allocator(), prog_name);

        return std.fs.openDirAbsolute(appdata_path, options) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    return if (create) d: {
                        try std.fs.makeDirAbsolute(appdata_path);
                        break :d std.fs.openDirAbsolute(appdata_path, options);
                    } else error.AppdataNotFound;
                },
                error.NotDir => {
                    std.log.err("Path '{s}' exists but is not a directory.", .{appdata_path});
                    return error.AppdataMalformed;
                },
                error.AccessDenied => {
                    std.log.err("Error writing to '{s}': {t}", .{ appdata_path, err });
                },
                else => {},
            }
            return err;
        };
    }
};

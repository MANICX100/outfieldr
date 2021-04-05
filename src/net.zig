const std = @import("std");
const c = @cImport({
    @cInclude("curl/curl.h");
    @cInclude("stdio.h");
});

const Dir = std.fs.Dir;
const File = std.fs.File;

const url = "http://github.com/tldr-pages/tldr/archive/master.tar.gz";

pub fn downloadPagesArchive(fd: *File) !void {
    if (c.curl_easy_init()) |http_handle| {
        defer c.curl_easy_cleanup(http_handle);

        if (c.curl_easy_setopt(http_handle, .CURLOPT_URL, url) != .CURLE_OK)
            return error.CurlSetUrlFailed;

        if (c.curl_easy_setopt(http_handle, .CURLOPT_FAILONERROR, @intCast(c_long, 1)) != .CURLE_OK)
            return error.CurlFailOnErrorFailed;

        if (c.curl_easy_setopt(http_handle, .CURLOPT_WRITEFUNCTION, writeToFileCallback) != .CURLE_OK)
            return error.CurlWriteFunctionFailed;

        if (c.curl_easy_setopt(http_handle, .CURLOPT_WRITEDATA, fd) != .CURLE_OK)
            return error.CurlWriteDataFailed;

        if (c.curl_easy_setopt(http_handle, .CURLOPT_FOLLOWLOCATION, @intCast(c_long, 1)) != .CURLE_OK)
            return error.CurlFollowLocationFailed;

        if (c.curl_easy_perform(http_handle) != .CURLE_OK)
            return error.CurlPerformFailed;
    } else
        return error.CurlEasyInitFailed;
}

fn writeToFileCallback(data: *c_void, size: c_uint, nmemb: c_uint, user_data: *c_void) callconv(.C) c_uint {
    var file = @intToPtr(*File, @ptrToInt(user_data));
    var typed_data = @intToPtr([*]u8, @ptrToInt(data));
    _ = file.write(typed_data[0..nmemb * size]) catch return 0;
    return nmemb * size;
}

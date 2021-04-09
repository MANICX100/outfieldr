const std = @import("std");
const c = @cImport({
    @cInclude("curl/curl.h");
    @cInclude("stdio.h");
});

const File = std.fs.File;

const url = "http://github.com/tldr-pages/tldr/archive/master.tar.gz";

pub fn downloadPagesArchive(fd: *File) !void {
    const http_handle = c.curl_easy_init() orelse return error.CurlEasyInitFailed;
    defer c.curl_easy_cleanup(http_handle);

    try curlEasySetOpt(http_handle, .CURLOPT_URL, url);
    try curlEasySetOpt(http_handle, .CURLOPT_FAILONERROR, @intCast(c_long, 1));
    try curlEasySetOpt(http_handle, .CURLOPT_WRITEFUNCTION, writeToFileCallback);
    try curlEasySetOpt(http_handle, .CURLOPT_WRITEDATA, fd);
    try curlEasySetOpt(http_handle, .CURLOPT_FOLLOWLOCATION, @intCast(c_long, 1));

    if (c.curl_easy_perform(http_handle) != .CURLE_OK)
        return error.CurlPerformFailed;
}

fn curlEasySetOpt(curl: *c.CURL, comptime option: c.CURLoption, val: anytype) !void {
    if (c.curl_easy_setopt(curl, option, val) != .CURLE_OK)
        return switch (option) {
            .CURLOPT_URL => error.CurlSetUrlFailed,
            .CURLOPT_FAILONERROR => error.CurlFailedOnErrorFailed,
            .CURLOPT_WRITEFUNCTION => error.CurlWriteFunctionFailed,
            .CURLOPT_WRITEDATA => error.CurlWriteDataFailed,
            .CURLOPT_FOLLOWLOCATION => error.CurlFollowLocationFailed,
            else => @compileError("Curl option does not have a corresponding Zig error"),
        };
}

fn writeToFileCallback(data: *c_void, size: c_uint, nmemb: c_uint, user_data: *c_void) callconv(.C) c_uint {
    var file = @intToPtr(*File, @ptrToInt(user_data));
    var typed_data = @intToPtr([*]u8, @ptrToInt(data));
    _ = file.write(typed_data[0 .. nmemb * size]) catch return 0;
    return nmemb * size;
}

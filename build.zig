const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version = std.SemanticVersion{ .major = 1, .minor = 1, .patch = 1 };

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "tldr",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // Convert SemanticVersion to a string
    var version_buf: [16]u8 = undefined;
    const version_str = std.fmt.bufPrint(&version_buf, "{}.{}.{}", .{
        version.major,
        version.minor,
        version.patch,
    }) catch unreachable;

    // Pass version as a compile-time option
    const options = b.addOptions();
    options.addOption([]const u8, "version", version_str);
    exe.root_module.addOptions("build_options", options);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const options = b.addOptions();

    var code: u8 = undefined;
    const git_tag = try b.execAllowFail(
        &.{ "git", "describe", "--tags" },
        &code,
        std.ChildProcess.StdIo.Ignore,
    );
    const git_hash = try b.execAllowFail(
        &.{ "git", "rev-parse", "--short", "HEAD" },
        &code,
        std.ChildProcess.StdIo.Ignore,
    );
    const version = b.fmt("v{s}-{s} ({s}-{s})", .{
        git_tag[0 .. git_tag.len - 1],
        git_hash[0 .. git_hash.len - 1],
        @tagName(builtin.cpu.arch),
        @tagName(builtin.os.tag),
    });
    options.addOption([]const u8, "version", version);

    const exe = b.addExecutable("tldr", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    exe.setOutputDir("bin");
    exe.addOptions("build_options", options);
    for (Packages.all) |pkg| exe.addPackage(pkg);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const clean_step = b.step("clean", "Clean build artifacts");
    clean_step.makeFn = struct {
        fn make(_: *std.build.Step) anyerror!void {
            const cwd = std.fs.cwd();
            try cwd.deleteTree("bin");
            try cwd.deleteTree("zig-out");
            try cwd.deleteTree("zig-cache");
        }
    }.make;

    const fmt = b.addFmt(&.{"src"});
    const fmt_step = b.step("fmt", "Format all source code");
    fmt_step.dependOn(&fmt.step);
}

const Packages = struct {
    const clap = std.build.Pkg{
        .name = "clap",
        .path = std.build.FileSource{ .path = "lib/zig-clap/clap.zig" },
    };

    const tar = std.build.Pkg{
        .name = "tar",
        .path = std.build.FileSource{ .path = "./lib/tar/src/main.zig" },
    };

    const hzzp = std.build.Pkg{
        .name = "hzzp",
        .path = std.build.FileSource{ .path = "./lib/hzzp/src/main.zig" },
    };

    const iguanaTLS = std.build.Pkg{
        .name = "iguanaTLS",
        .path = std.build.FileSource{ .path = "./lib/iguanaTLS/src/main.zig" },
    };

    const network = std.build.Pkg{
        .name = "network",
        .path = std.build.FileSource{ .path = "./lib/zig-network/network.zig" },
    };

    const uri = std.build.Pkg{
        .name = "uri",
        .path = std.build.FileSource{ .path = "./lib/zig-uri/uri.zig" },
    };

    const zfetch = std.build.Pkg{
        .name = "zfetch",
        .path = std.build.FileSource{ .path = "./lib/zfetch/src/main.zig" },
        .dependencies = &[_]std.build.Pkg{ hzzp, iguanaTLS, network, uri },
    };

    const all = &[_]std.build.Pkg{ clap, tar, zfetch };
};

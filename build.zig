const std = @import("std");
const Io = std.Io;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("httpz", httpz.module("httpz"));

    b.installArtifact(exe);

    const runExe = b.addRunArtifact(exe);

    if (b.args) |args| {
        runExe.addArgs(args);
    }

    const runStep = b.step("run", "start the application");
    runStep.dependOn(&runExe.step);
}

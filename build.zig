const std = @import("std");
const Io = std.Io;

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.graph.host,
        }),
    });

    b.installArtifact(exe);

    const runExe = b.addRunArtifact(exe);

    if (b.args) |args| {
        runExe.addArgs(args);
    }

    const runStep = b.step("run", "start the application");
    runStep.dependOn(&runExe.step);
}

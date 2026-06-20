const std = @import("std");
const print = std.debug.print;

pub fn main(init: std.process.Init) !void {
    const runResult = std.process.run(init.gpa, init.io, .{ .argv = &.{ "ytdlp", "-U" } }) catch |err| switch (err) {
        error.FileNotFound => {
            print("could not find the executable ytdlp in path\n", .{});
            return error.ytdlpExecutableNotFound;
        },
        else => return err,
    };
    defer init.gpa.free(runResult.stdout);
    defer init.gpa.free(runResult.stderr);

    print("program finished, {s}, {any}\n", .{ runResult.stdout, runResult.term.exited });
}

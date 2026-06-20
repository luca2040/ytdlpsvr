const std = @import("std");
const builtin = @import("builtin");

const printErr = std.log.err;
const printMsg = std.log.info;

const ytdlp = @import("ytdlp.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const alloc = switch (builtin.mode) {
        .Debug => init.gpa,
        else => arena.allocator(),
    };
    const io = init.io;

    const ytdlpVersion = try ytdlp.checkVersion(alloc, io);
    defer alloc.free(ytdlpVersion);

    printMsg("ytdlp version: {s}", .{ytdlpVersion});

    ytdlp.update(alloc, io) catch |e| printErr("error {any} updating version\n", .{e});

    const meta = try ytdlp.retrieveMetadata(alloc, io, "https://www.youtube.com/watch?v=QWdDzqT-JJ0");
    defer meta.deinit();

    printMsg("id {s} - title {s}", .{ meta.value.id, meta.value.title });

    const filename = try std.fmt.allocPrint(alloc, "{s} - [{s}]", .{ meta.value.title, meta.value.id });
    defer alloc.free(filename);

    try ytdlp.downloadAudio(alloc, io, "https://www.youtube.com/watch?v=QWdDzqT-JJ0", filename);
}

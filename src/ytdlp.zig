const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const printErr = std.log.err;
const printWarn = std.log.warn;
const printMsg = std.log.info;

pub fn checkVersion(
    alloc: Allocator,
    io: Io,
) ![]const u8 {
    const runResult = std.process.run(
        alloc,
        io,
        .{ .argv = &.{ "ytdlp", "--version" } },
    ) catch |err| switch (err) {
        error.FileNotFound => {
            printErr("could not find the executable ytdlp in path", .{});
            return error.ytdlpExecutableNotFound;
        },
        else => return err,
    };
    defer alloc.free(runResult.stdout);
    defer alloc.free(runResult.stderr);

    switch (runResult.term) {
        .exited => |code| {
            if (code != 0) {
                printErr("error {d} gettig version: {s} {s}", .{ code, runResult.stderr, runResult.stdout });
                return error.ytdlpErrorGettingVersion;
            }

            return try alloc.dupe(u8, std.mem.trim(u8, runResult.stdout, "\r\n"));
        },
        else => {
            printErr("ytdlp did not exit normally", .{});
            return error.ytdlpErrorGettingVersion;
        },
    }
}

pub fn update(
    alloc: Allocator,
    io: Io,
) !void {
    const runResult = try std.process.run(
        alloc,
        io,
        .{ .argv = &.{ "ytdlp", "-U" } },
    );
    defer alloc.free(runResult.stdout);
    defer alloc.free(runResult.stderr);

    switch (runResult.term) {
        .exited => |code| {
            if (code != 0) {
                printErr("error {d} updating ytdlp: {s} {s}", .{ code, runResult.stderr, runResult.stdout });
                return error.ytdlpErrorUpdating;
            }
        },
        else => {
            printErr("ytdlp did not exit normally", .{});
            return error.ytdlpErrorUpdating;
        },
    }
}

const Metadata = struct {
    title: []u8,
    id: []u8,
};

pub fn retrieveMetadata(
    alloc: Allocator,
    io: Io,
    url: []const u8,
) !std.json.Parsed(Metadata) {
    const runResult = try std.process.run(
        alloc,
        io,
        .{ .argv = &.{
            "ytdlp",
            "--no-playlist",
            "--print",
            "{\"id\":\"%(id)s\",\"title\":\"%(title)s\"}",
            url,
        } },
    );
    defer alloc.free(runResult.stdout);
    defer alloc.free(runResult.stderr);

    switch (runResult.term) {
        .exited => |code| {
            if (code != 0) {
                printErr("error {d} getting metadata: {s} {s}", .{ runResult.term.exited, runResult.stdout, runResult.stderr });
                return error.ytdlpErrorGettingMetadata;
            }
        },
        else => {
            printErr("ytdlp did not exit normally", .{});
            return error.ytdlpErrorGettingMetadata;
        },
    }

    const parsed = try std.json.parseFromSlice(Metadata, alloc, runResult.stdout, .{});
    return parsed;
}

pub fn downloadAudio(alloc: Allocator, io: Io, url: []const u8) ![]u8 {
    const runResult = try std.process.run(
        alloc,
        io,
        .{ .argv = &.{
            "ytdlp",
            "--no-playlist",
            "-f",
            "bestaudio",
            "-o",
            "/tmp/ytdlpsvr_temp_audio.mp3",
            "-x",
            "--force-overwrites",
            "--audio-format",
            "mp3",
            "--audio-quality",
            "0",
            url,
        } },
    );
    defer alloc.free(runResult.stdout);
    defer alloc.free(runResult.stderr);

    switch (runResult.term) {
        .exited => |code| {
            if (code != 0) {
                printErr("error {d} downloading: {s}", .{ runResult.term.exited, runResult.stderr });
                return error.ytdlpErrorDownloadingAudio;
            }
        },
        else => {
            printErr("ytdlp did not exit normally", .{});
            return error.ytdlpErrorDownloadingAudio;
        },
    }

    const tmpDir = try std.Io.Dir.openDirAbsolute(io, "/tmp", .{});
    const data = try std.Io.Dir.readFileAlloc(tmpDir, io, "ytdlpsvr_temp_audio.mp3", alloc, .unlimited);
    errdefer alloc.free(data);

    try std.Io.Dir.deleteFile(tmpDir, io, "ytdlpsvr_temp_audio.mp3");

    printMsg("downloading messages: {s} {s}", .{ runResult.stderr, runResult.stdout });
    return data;
}

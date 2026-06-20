const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const printErr = std.log.err;
const printWarn = std.log.warn;
const printMsg = std.log.info;

pub fn checkVersion(alloc: Allocator, io: Io) ![]const u8 {
    const runResult = std.process.run(alloc, io, .{ .argv = &.{ "ytdlp", "--version" } }) catch |err| switch (err) {
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

pub fn update(alloc: Allocator, io: Io) !void {
    const runResult = try std.process.run(alloc, io, .{ .argv = &.{ "ytdlp", "-U" } });
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

pub fn retrieveMetadata(alloc: Allocator, io: Io, url: []const u8) !std.json.Parsed(Metadata) {
    const runResult = try std.process.run(alloc, io, .{ .argv = &.{
        "ytdlp",
        "--no-playlist",
        "--print",
        "{\"id\":\"%(id)s\",\"title\":\"%(title)s\"}",
        url,
    } });
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

const Progress = struct {
    status: []u8,
    percent: f32,
    downloaded: u64,
    total: u64,
    speed: f32,
    eta: u64,
};

pub fn downloadAudio(alloc: Allocator, io: Io, url: []const u8, filepath: []const u8) !void {
    const progressTemplate =
        "PROGRESS{\"status\":\"%(progress.status)s\",\"percent\":%(progress.percent|0)s,\"downloaded\":%(progress.downloaded_bytes|0)s,\"total\":%(progress.total_bytes|0)s,\"speed\":%(progress.speed|0)s,\"eta\":%(progress.eta|0)s}";

    var child = try std.process.spawn(io, .{
        .argv = &.{
            "ytdlp",
            "--no-playlist",
            "-f",
            "bestaudio",
            "-o",
            filepath,
            "-x",
            "--audio-format",
            "mp3",
            "--newline",
            "--progress-delta",
            "1",
            "--progress-template",
            progressTemplate,
            url,
        },
        .stdout = .pipe,
        .stderr = .pipe,
    });

    var buffer: [4096]u8 = undefined;

    while (true) {
        const n = child.stdout.?.readStreaming(io, &.{&buffer}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        if (n == 0) {
            continue;
        }

        const data = buffer[0..n];

        if (std.mem.startsWith(u8, data, "PROGRESS")) {
            const parsed = try std.json.parseFromSlice(Progress, alloc, data[8..n], .{});
            defer parsed.deinit();

            const pval = parsed.value;
            var percent = pval.percent;

            if (percent == 0)
                percent = @as(f32, @floatFromInt(pval.downloaded)) / @as(f32, @floatFromInt(pval.total));

            printMsg(
                "status: {s}\npercent: {d}%\ndownloaded: {d}\ntotal: {d}\nspeed: {d}\neta: {d}",
                .{
                    pval.status,
                    percent * 100.0,
                    pval.downloaded,
                    pval.total,
                    pval.speed,
                    pval.eta,
                },
            );
        }
    }

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| {
            if (code != 0) {
                printErr("error code {d} downloading", .{code});
                return error.ytdlpErrorDownloadingAudio;
            }
        },
        else => {
            printErr("ytdlp did not exit normally", .{});
            return error.ytdlpErrorDownloadingAudio;
        },
    }
}

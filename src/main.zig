const std = @import("std");
const builtin = @import("builtin");
const httpz = @import("httpz");

const printErr = std.log.err;
const printMsg = std.log.info;

const ytdlp = @import("ytdlp.zig");

const AppState = struct {
    io: std.Io,
    lastUpdateTime: i64,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const ytdlpVersion = try ytdlp.checkVersion(allocator, init.io);
    defer allocator.free(ytdlpVersion);

    printMsg("ytdlp version: {s}", .{ytdlpVersion});

    var state: AppState = .{
        .io = init.io,
        .lastUpdateTime = 0,
    };

    var server = try httpz.Server(*AppState).init(init.io, allocator, .{
        .address = .all(5882),
    }, &state);
    defer {
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.get("/download", downloadAudio, .{});

    try server.listen();
}

fn downloadAudio(
    appState: *AppState,
    req: *httpz.Request,
    res: *httpz.Response,
) !void {
    const qs = try req.query();
    const url = qs.get("url") orelse {
        res.status = 400;
        try res.json(.{
            .err = "missing url parameter",
        }, .{});
        return;
    };

    const now = std.Io.Clock.real.now(appState.io).toSeconds();
    if ((now - appState.lastUpdateTime) > (24 * 60 * 60)) { // run every 24 hours
        printMsg("updating yt dlp", .{});
        appState.lastUpdateTime = now;

        ytdlp.update(res.arena, appState.io) catch |e| printErr("error {any} updating version", .{e});
    }

    printMsg("retrieving metadata", .{});

    const meta = ytdlp.retrieveMetadata(res.arena, appState.io, url) catch |e| {
        printErr("error {any}", .{e});

        res.status = 500;
        try res.json(.{
            .err = "error retrieving metadata",
        }, .{});
        return;
    };
    defer meta.deinit();

    printMsg("id {s} - title {s}", .{ meta.value.id, meta.value.title });

    const filename = std.fmt.allocPrint(res.arena, "{s} - [{s}]", .{ meta.value.title, meta.value.id }) catch |e| {
        printErr("error {any}", .{e});

        res.status = 500;
        try res.json(.{
            .err = "error allocating filename",
        }, .{});
        return;
    };
    const safeFilename = sanitizeFilename(res.arena, filename) catch |e| {
        printErr("error {any}", .{e});

        res.status = 500;
        try res.json(.{
            .err = "error sanitizing filename",
        }, .{});
        return;
    };

    printMsg("starting download of url: {s}", .{url});

    const musicData = ytdlp.downloadAudio(res.arena, appState.io, url) catch |e| {
        printErr("error {any}", .{e});

        res.status = 500;
        try res.json(.{
            .err = "error downloading audio",
        }, .{});
        return;
    };

    printMsg("download finished", .{});

    res.status = 200;

    res.header(
        "Content-Type",
        "audio/mpeg",
    );

    const headerStr = std.fmt.allocPrint(res.arena, "attachment; filename=\"{s}.mp3\"", .{safeFilename}) catch |e| {
        printErr("error {any}", .{e});

        res.status = 500;
        try res.json(.{
            .err = "error generating headers",
        }, .{});
        return;
    };
    res.header(
        "Content-Disposition",
        headerStr,
    );

    res.header(
        "Content-Length",
        std.fmt.allocPrint(
            res.arena,
            "{d}",
            .{musicData.len},
        ) catch unreachable,
    );

    res.body = musicData;
}

fn sanitizeFilename(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, input.len);
    errdefer out.deinit(allocator);

    for (input) |c| {
        switch (c) {
            '/',
            '\\',
            ':',
            '*',
            '?',
            '"',
            '<',
            '>',
            '|',
            => {
                try out.append(allocator, '_');
            },

            0...31 => {
                try out.append(allocator, '_');
            },

            else => {
                try out.append(allocator, c);
            },
        }
    }

    while (out.items.len > 0 and
        (out.items[out.items.len - 1] == ' ' or
            out.items[out.items.len - 1] == '.'))
    {
        _ = out.pop();
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "unknown");
    }

    if (out.items.len > 200) {
        out.shrinkRetainingCapacity(200);
    }

    return out.toOwnedSlice(allocator);
}

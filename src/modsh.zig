//! Mod Shell. The base shell for the entire project.

// Standard Lib
const std = @import("std");
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const process = std.process;

// Mod Shell
const sh_opts = @import("modsh_options");
    
const BUFSIZE: usize = 1024;

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    
    try shLoop(alloc, stdin, stdout, stderr);
}

/// Shell Loop. This is the main loop for ModSh. It takes an Allocator (`alloc`), an Input Reader (`in`) to process from, and both an Output Writer (`out`) and Error Writer (`err`) to provide feedback to.
pub fn shLoop(alloc: mem.Allocator, in: anytype, out: anytype, err: anytype) !void {
    var history = if (sh_opts.shell_builtins != .None) std.ArrayList([]const u8).init(alloc);

    // TODO: Figure out why ChildProcess needs to be referenced in this function for ReleaseSmall (but works fine for other Release Options).
    _ = try std.ChildProcess.exec(.{
        .allocator = alloc,
        .argv = &.{ "whoami" },
    });

    while (true) {
        // Shell Prefix
        switch (sh_opts.shell_prefix_kind) {
            .None => try out.print("> ", .{}),
            .Text => try out.print("{s} > ", .{ sh_opts.shell_prefix }),
            .Command => {
                const shell_prefix: []u8 = (try std.ChildProcess.exec(.{ 
                    .allocator = alloc,
                    .argv = &.{ sh_opts.shell_prefix },
                })).stdout;
                defer alloc.free(shell_prefix);
                try out.print("modsh | {s} > ", .{ shell_prefix[0..(shell_prefix.len - 1)] });
            }
        }

        // Get Arguments
        const line = try in.readUntilDelimiterOrEofAlloc(alloc, '\n', BUFSIZE) orelse continue;
        if (@intFromEnum(sh_opts.shell_builtins) > @intFromEnum(@TypeOf(sh_opts.shell_builtins).Bare) and line[0] != '!') try history.append(try alloc.dupe(u8, line));
        defer alloc.free(line);
        const args = try splitArgs(line, alloc);
        defer alloc.free(args);

        // Parse Arguments
        switch (sh_opts.shell_builtins) {
            .None => {
                execRawArgs(args, alloc, out, err) catch |exec_err| switch (exec_err) {
                    error.ResultError => continue,
                    else => |other_error| return other_error,
                };
            },
            .Bare => {
                if (try execBareArgs(args, alloc, out, err)) continue;
                break;
            },
            .Basic => {
                if (try execBasicArgs(args, &history, alloc, out, err)) continue;
                break;
            },
            else => @compileError("The provided kind of Shell Builtins is not yet implemented."),
        }
    }

}

/// Split the provided String (`line`) to Arguments.
fn splitArgs(line: []const u8, alloc: mem.Allocator) ![]const []const u8 {
    var args_list = std.ArrayList([]const u8).init(alloc);
    defer args_list.deinit();
    var tokens = mem.splitAny(u8, line, " \n");
    while (tokens.next()) |tok| try args_list.append(tok);
    return try args_list.toOwnedSlice();
}

/// Execute Raw Arguments.
fn execRawArgs(args: []const []const u8, alloc: mem.Allocator, out: anytype, err: anytype) !void {
    const result = std.ChildProcess.exec(.{
        .allocator = alloc,
        .argv = args,
    }) catch |result_err| {
        try err.print("There was an issue running '{s}'.", .{ args[0] });
        try err.print("{any}\n", .{ result_err });
        return error.ResultError;
    };
    if (result.stderr.len > 0) try err.print("{s}\n", .{ result.stderr });
    if (result.stdout.len > 0) try out.print("{s}\n", .{ result.stdout });
    defer {
        alloc.free(result.stdout);
        alloc.free(result.stderr);
    }
}

/// Execute Arguments with Bare Builtins. This will return a Boolean to determine if the shell should continue or not.
fn execBareArgs(args: []const []const u8, alloc: mem.Allocator, out: anytype, err: anytype) !bool {
    if (mem.eql(u8, args[0], "cd")) {
        process.changeCurDir(args[1]) catch |cd_err| switch (cd_err) {
            error.AccessDenied => try out.print("Insufficient Privileges. Access Denied!\n", .{}),
            else => |other_error| return other_error,
        };
        return true;
    }
    if (mem.eql(u8, args[0], "exit")) {
        try out.print("Exiting!\n", .{});
        process.cleanExit();
        return false;
    }
    execRawArgs(args, alloc, out, err) catch |exec_err| switch (exec_err) {
        error.ResultError => return true,
        else => |other_error| return other_error,
    };
    return true;
}

/// Execute Arguments with Basic Builtins. This will return a Boolean to determine if the shell should continue or not.
fn execBasicArgs(args: []const []const u8, history: *std.ArrayList([]const u8), alloc: mem.Allocator, out: anytype, err: anytype) !bool {
    if (mem.eql(u8, args[0], "history")) {
        try writeHistory(history.*, out);
        return true;
    }
    if (args[0][0] == '!' and history.items.len > 0) {
        const line_num = 
            if (args[0][1] == '!') history.items.len - 1 
            else fmt.parseInt(usize, args[0][1..], 0) catch {
                try err.print("'{s}' is not a valid command reference.\n", .{ args[0][1..] });
                return true;
            };
        const history_args = try splitArgs(history.items[line_num], alloc);
        try history.append(history.items[line_num]);
        return try execBasicArgs(history_args, history, alloc, out, err); 
    }
    return execBareArgs(args, alloc, out, err);
}

/// Write the provided History (`history`) to the provided Writer (`out`).
fn writeHistory(history: std.ArrayList([]const u8), out: anytype) !void {
    for (history.items, 0..) |item, idx| try out.print("{d}: {s}\n", .{ idx, item });
    try out.print("\n", .{});
}

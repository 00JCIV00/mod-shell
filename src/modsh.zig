//! Mod Shell. The base shell for the entire project.

// Standard Lib
const std = @import("std");
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
        if (sh_opts.shell_builtins != .None) try history.append(try alloc.dupe(u8, line));
        defer alloc.free(line);
        const args = genArgs: {
            var args_list = std.ArrayList([]const u8).init(alloc);
            defer args_list.deinit();
            var tokens = mem.splitAny(u8, line, " \n");
            while (tokens.next()) |tok| try args_list.append(tok);
            break :genArgs try args_list.toOwnedSlice();
        };
        defer alloc.free(args);

        // Parse Arguments
        switch (sh_opts.shell_builtins) {
            .None => {},
            .Basic => {
                if (mem.eql(u8, args[0], "cd")) {
                    try process.changeCurDir(args[1]);
                    continue;
                }
                if (mem.eql(u8, args[0], "history")) {
                    try writeHistory(history, out);
                    continue;
                }
                if (mem.eql(u8, args[0], "exit")) {
                    try out.print("Exiting!\n", .{});   
                    process.cleanExit();
                    return;
                }
            },
            else => @compileError("The provided Shell Builtins type is not yet implemented."),
        }
        execRawArgs(args, alloc, out, err) catch |exec_err| switch (exec_err) {
            error.ResultError => continue,
            else => |other_error| return other_error,
        };
    }

}

/// Execute Raw Arguments
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

/// Write the provided History (`history`) to the provided Writer (`out`).
fn writeHistory(history: std.ArrayList([]const u8), out: anytype) !void {
    for (history.items, 0..) |item, idx| try out.print("{d}: {s}\n", .{ idx, item });
}

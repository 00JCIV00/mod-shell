const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });
    b.exe_dir = "./bin";

    // Mod Shell Executable
    const modsh_exe = b.addExecutable(.{
        .name = "mod-shell",
        .root_source_file = .{ .path = "src/modsh.zig" },
        .target = target,
        .optimize = optimize,
    });
    // - Build Options
    const modsh_options = b.addOptions();
    // -- Shell Prefix
    const ShellPrefixKind = enum {
        None,
        Text,
        Command,
    };
    modsh_options.addOption(ShellPrefixKind, "shell_prefix_kind",
        b.option(ShellPrefixKind, "shell_prefix_kind", "Choose the kind of Shell Prefix to use [default=None]") orelse .None
    );
    modsh_options.addOption([]const u8, "shell_prefix",
        b.option([]const u8, "shell_prefix", "Specify the Text or Command to use for the Shell Prefix [default=modsh]") orelse "modsh"
    );
    // -- Shell Builtins
    const ShellBuiltins = enum {
        /// None = No Builtin funcitionality.
        None,
        /// Basic = Basic Builtin functionality (cd, history, exit)
        Basic,
        /// Advanced = Advanced Builtin functionality (jobs, up/down arrows for history, tab completion)
        Advanced,
    };
    modsh_options.addOption(ShellBuiltins, "shell_builtins", 
        b.option(ShellBuiltins, "shell_builtins", "Choose the kind of Shell Builtin functionality to include [default=None]") orelse .None
    );
    // -- Add All Shell Build Options
    modsh_exe.addOptions("modsh_options", modsh_options);
    // - Build Step
    const build_modsh = b.addInstallArtifact(modsh_exe, .{});
    const build_modsh_step = b.step("shell", "Build the standalone ModSh executable");
    build_modsh_step.dependOn(&build_modsh.step);

    b.installArtifact(modsh_exe);

    const run_cmd = b.addRunArtifact(modsh_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/modsh.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

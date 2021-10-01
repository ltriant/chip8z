const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("chip8z", "main.zig");
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.linkSystemLibrary("SDL2");
    exe.linkLibC();
    exe.install();
}

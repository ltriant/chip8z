//
// chip8z -- a CHIP-8 emulator
//

const std = @import("std");

const fs = std.fs;
const io = std.io;
const log = std.log;
const process = std.process;
const time = std.time;

const allocator = std.heap.page_allocator;
const c = @cImport({
    @cInclude("SDL.h");
});

const chip8 = @import("chip8.zig");

const ErrorSet = error{SDLError};

// Global log level
pub const log_level: log.Level = .warn;

// Screen dimensions
const ScreenWidth = 64;
const ScreenHeight = 32;
const ScreenFactor = 10;

// Run the CPU at 500Hz
const ClockRate = 500.0;
const MillisPerClock = @floatToInt(i64, (1.0 / ClockRate) * 1000.0);

// The sound and delay timers clock at 60Hz
const TimerClockRate = 60.0;
const MillisPerTimerClock = @floatToInt(i64, (1.0 / TimerClockRate) * 1000.0);

fn powerUp(machine: *chip8.Chip8) !void {
    var window = c.SDL_CreateWindow("chip8z", 100, 100, ScreenWidth * ScreenFactor, ScreenHeight * ScreenFactor, c.SDL_WINDOW_SHOWN);

    if (window == null) {
        log.warn("Unable to create window: {s}", .{c.SDL_GetError()});
        return ErrorSet.SDLError;
    }
    defer c.SDL_DestroyWindow(window);

    var surface = c.SDL_GetWindowSurface(window);
    var event: c.SDL_Event = undefined;
    var quit = false;

    var timerClockNow: i64 = time.milliTimestamp();
    var clockNow: i64 = undefined;

    while (!quit) {
        clockNow = time.milliTimestamp();

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_1 => {
                            machine.keyDown(0x01);
                        },
                        c.SDLK_2 => {
                            machine.keyDown(0x02);
                        },
                        c.SDLK_3 => {
                            machine.keyDown(0x03);
                        },
                        c.SDLK_4 => {
                            machine.keyDown(0x0c);
                        },
                        c.SDLK_q => {
                            machine.keyDown(0x04);
                        },
                        c.SDLK_w => {
                            machine.keyDown(0x05);
                        },
                        c.SDLK_e => {
                            machine.keyDown(0x06);
                        },
                        c.SDLK_r => {
                            machine.keyDown(0x0d);
                        },
                        c.SDLK_a => {
                            machine.keyDown(0x07);
                        },
                        c.SDLK_s => {
                            machine.keyDown(0x08);
                        },
                        c.SDLK_d => {
                            machine.keyDown(0x09);
                        },
                        c.SDLK_f => {
                            machine.keyDown(0x0e);
                        },
                        c.SDLK_z => {
                            machine.keyDown(0x0a);
                        },
                        c.SDLK_x => {
                            machine.keyDown(0x00);
                        },
                        c.SDLK_c => {
                            machine.keyDown(0x0b);
                        },
                        c.SDLK_v => {
                            machine.keyDown(0x0f);
                        },

                        else => {},
                    }
                },
                c.SDL_KEYUP => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_1 => {
                            machine.keyUp(0x01);
                        },
                        c.SDLK_2 => {
                            machine.keyUp(0x02);
                        },
                        c.SDLK_3 => {
                            machine.keyUp(0x03);
                        },
                        c.SDLK_4 => {
                            machine.keyUp(0x0c);
                        },
                        c.SDLK_q => {
                            machine.keyUp(0x04);
                        },
                        c.SDLK_w => {
                            machine.keyUp(0x05);
                        },
                        c.SDLK_e => {
                            machine.keyUp(0x06);
                        },
                        c.SDLK_r => {
                            machine.keyUp(0x0d);
                        },
                        c.SDLK_a => {
                            machine.keyUp(0x07);
                        },
                        c.SDLK_s => {
                            machine.keyUp(0x08);
                        },
                        c.SDLK_d => {
                            machine.keyUp(0x09);
                        },
                        c.SDLK_f => {
                            machine.keyUp(0x0e);
                        },
                        c.SDLK_z => {
                            machine.keyUp(0x0a);
                        },
                        c.SDLK_x => {
                            machine.keyUp(0x00);
                        },
                        c.SDLK_c => {
                            machine.keyUp(0x0b);
                        },
                        c.SDLK_v => {
                            machine.keyUp(0x0f);
                        },

                        else => {},
                    }
                },
                else => {},
            }
        }

        const should_render = machine.step();

        if (should_render) {
            for (machine.Screen) |row, y| {
                for (row) |cell, x| {
                    var rect = c.SDL_Rect{
                        .x = @intCast(c_int, x * ScreenFactor),
                        .y = @intCast(c_int, y * ScreenFactor),
                        .w = ScreenFactor,
                        .h = ScreenFactor,
                    };

                    var color = [3]u8{ 0x30, 0x30, 0x30 };
                    if (cell == 1) {
                        color = [3]u8{ 0x30, 0xbb, 0x30 };
                    }

                    var rv = c.SDL_FillRect(surface, &rect, c.SDL_MapRGB(surface.*.format, color[0], color[1], color[2]));
                    if (rv != 0) {
                        log.warn("Failed to fill rect: {s}", .{c.SDL_GetError()});
                        return ErrorSet.SDLError;
                    }
                }
            }

            if (c.SDL_UpdateWindowSurface(window) != 0) {
                log.warn("Failed to update window surface: {s}", .{c.SDL_GetError()});
                return ErrorSet.SDLError;
            }
        }

        const now = time.milliTimestamp();
        var timeDiff = now - clockNow;

        if (timeDiff < MillisPerClock) {
            const timeToSleep = @intCast(u64, MillisPerClock - timeDiff);
            time.sleep(timeToSleep * time.ns_per_ms);
        }

        timeDiff = now - timerClockNow;
        if (timeDiff >= MillisPerTimerClock) {
            machine.tickTimers();
            timerClockNow = now;

            if (machine.ST > 0) {
                log.info("BEEP! BEEP!", .{});
            }
        }
    }
}

pub fn main() !void {
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len == 1) {
        log.warn("usage: {s} <rom>", .{args[0]});
        process.exit(1);
    }

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        log.warn("Unable to initialise SDL: {s}", .{c.SDL_GetError()});
        return ErrorSet.SDLError;
    }
    defer c.SDL_Quit();

    const dir = fs.cwd();
    const file = try dir.openFile(args[1], .{ .read = true });
    defer file.close();

    var prgRom: [4096]u8 = undefined;
    const reader = file.reader();
    const nBytes = try reader.readAll(prgRom[0..]);
    log.info("Read {} bytes of PRG ROM", .{nBytes});

    var machine = chip8.Chip8.init(prgRom[0..nBytes]);
    try powerUp(&machine);
}

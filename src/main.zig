//
// chip8z -- a CHIP-8 emulator
//

const std = @import("std");

const fs = std.fs;
const io = std.io;
const log = std.log;
const mem = std.mem;
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
const MillisPerClock: i64 = @intFromFloat((1.0 / ClockRate) * 1000.0);

// Poll for keyboard events at 60Hz
const KeyboardPollRate = 60.0;
const MillisPerKeyboardPoll: i64 = @intFromFloat((1.0 / KeyboardPollRate) * 1000.0);

// The sound and delay timers clock at 60Hz
const TimerClockRate = 60.0;
const MillisPerTimerClock: i64 = @intFromFloat(std.math.floor((1.0 / TimerClockRate) * 1000.0));

// The number of audio samples to produce for a beep
const SamplesPerBeep = 8192;

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
    var keyboardClockNow: i64 = time.milliTimestamp();

    while (!quit) {
        clockNow = time.milliTimestamp();
        const should_render = machine.step();

        if (should_render) {
            for (machine.Screen, 0..) |row, y| {
                for (row, 0..) |cell, x| {
                    var rect = c.SDL_Rect{
                        .x = @intCast(x * ScreenFactor),
                        .y = @intCast(y * ScreenFactor),
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

        // Cap the frame-rate
        var timeDiff = now - clockNow;
        if (timeDiff < MillisPerClock) {
            const timeToSleep: u64 = @intCast(MillisPerClock - timeDiff);
            time.sleep(timeToSleep * time.ns_per_ms);
        }

        // Clock the timers
        timeDiff = now - timerClockNow;
        if (timeDiff >= MillisPerTimerClock) {
            machine.tickTimers();
            timerClockNow = now;

            if (machine.ST > 0) {
                beep();
            }
        }

        // Poll for keyboard events
        timeDiff = now - keyboardClockNow;
        if (timeDiff >= MillisPerKeyboardPoll) {
            while (c.SDL_PollEvent(&event) != 0) {
                switch (event.type) {
                    c.SDL_QUIT => quit = true,
                    c.SDL_KEYDOWN => {
                        switch (event.key.keysym.sym) {
                            c.SDLK_1 => machine.keyDown(0x01),
                            c.SDLK_2 => machine.keyDown(0x02),
                            c.SDLK_3 => machine.keyDown(0x03),
                            c.SDLK_4 => machine.keyDown(0x0c),
                            c.SDLK_q => machine.keyDown(0x04),
                            c.SDLK_w => machine.keyDown(0x05),
                            c.SDLK_e => machine.keyDown(0x06),
                            c.SDLK_r => machine.keyDown(0x0d),
                            c.SDLK_a => machine.keyDown(0x07),
                            c.SDLK_s => machine.keyDown(0x08),
                            c.SDLK_d => machine.keyDown(0x09),
                            c.SDLK_f => machine.keyDown(0x0e),
                            c.SDLK_z => machine.keyDown(0x0a),
                            c.SDLK_x => machine.keyDown(0x00),
                            c.SDLK_c => machine.keyDown(0x0b),
                            c.SDLK_v => machine.keyDown(0x0f),
                            else => {},
                        }
                    },
                    c.SDL_KEYUP => {
                        switch (event.key.keysym.sym) {
                            c.SDLK_1 => machine.keyUp(0x01),
                            c.SDLK_2 => machine.keyUp(0x02),
                            c.SDLK_3 => machine.keyUp(0x03),
                            c.SDLK_4 => machine.keyUp(0x0c),
                            c.SDLK_q => machine.keyUp(0x04),
                            c.SDLK_w => machine.keyUp(0x05),
                            c.SDLK_e => machine.keyUp(0x06),
                            c.SDLK_r => machine.keyUp(0x0d),
                            c.SDLK_a => machine.keyUp(0x07),
                            c.SDLK_s => machine.keyUp(0x08),
                            c.SDLK_d => machine.keyUp(0x09),
                            c.SDLK_f => machine.keyUp(0x0e),
                            c.SDLK_z => machine.keyUp(0x0a),
                            c.SDLK_x => machine.keyUp(0x00),
                            c.SDLK_c => machine.keyUp(0x0b),
                            c.SDLK_v => machine.keyUp(0x0f),
                            else => {},
                        }
                    },
                    else => {},
                }
            }

            keyboardClockNow = now;
        }
    }
}

var playback_device_id: c.SDL_AudioDeviceID = undefined;

fn beep() void {
    const tone_volume: f32 = 0.1;
    const period: usize = 44100 / 415; // if it's not Baroque, don't fix it! *groan*
    var buf = mem.zeroes([SamplesPerBeep]f32);

    var s: usize = 0;
    while (s < SamplesPerBeep) {
        if (((s / period) % 2) == 0) {
            buf[s] = tone_volume;
        } else {
            buf[s] = -tone_volume;
        }

        s += 1;
    }

    const rv = c.SDL_QueueAudio(playback_device_id, &buf, buf.len);

    if (rv != 0) {
        log.warn("Unable to queue audio samples: {s}", .{c.SDL_GetError()});
    }
}

pub fn main() !void {
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len == 1) {
        log.warn("usage: {s} <rom>", .{args[0]});
        process.exit(1);
    }

    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) != 0) {
        log.warn("Unable to initialise SDL: {s}", .{c.SDL_GetError()});
        return ErrorSet.SDLError;
    }
    defer c.SDL_Quit();

    //
    // Setup audio
    //

    var want_spec: c.SDL_AudioSpec = undefined;
    // 44.1kHz
    want_spec.freq = 44100;
    // Prefer f32s
    want_spec.format = c.AUDIO_F32;
    // Stereo
    want_spec.channels = 2;
    // The number of samples to hold in the buffer
    want_spec.samples = 1024;
    // Prefer to queue audio samples
    want_spec.callback = null;

    var have_spec: c.SDL_AudioSpec = undefined;

    playback_device_id = c.SDL_OpenAudioDevice(null, c.SDL_FALSE, &want_spec, &have_spec, c.SDL_AUDIO_ALLOW_FORMAT_CHANGE);

    if (playback_device_id == 0) {
        log.warn("Unable to initialise audio: {s}", .{c.SDL_GetError()});
    } else {
        log.info("Device ID: {}, channels: {}, freq: {} Hz, samples: {}", .{ playback_device_id, have_spec.channels, have_spec.freq, have_spec.samples });
    }

    // Unpause the audio device, otherwise nothing will play...
    c.SDL_PauseAudioDevice(playback_device_id, c.SDL_FALSE);

    //
    // Read the ROM data
    //

    const dir = fs.cwd();
    const file = try dir.openFile(args[1], .{ .mode = .read_only });
    defer file.close();

    var prgRom: [4096]u8 = undefined;
    const reader = file.reader();
    const nBytes = try reader.readAll(prgRom[0..]);
    log.info("Read {} bytes of PRG ROM", .{nBytes});

    //
    // Create the CHIP-8 machine and go!
    //

    var machine = chip8.Chip8.init(prgRom[0..nBytes]);
    try powerUp(&machine);
}

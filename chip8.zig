const std = @import("std");
const log = std.log;
const mem = std.mem;
const os = std.os;

const ScreenWidth = 64;
const ScreenHeight = 32;

const PrgRomAddress = 0x200;
const StackAddress = 0xEA0;
const ScreenAddress = 0xF00;

pub const Chip8 = struct {
    Screen: [ScreenHeight][ScreenWidth]u1,
    KeyDown: [16]bool,

    // Memory Map:
    // +---------------+= 0xFFF (4095) End of Chip-8 RAM
    // |               |
    // |               |= 0xF00 (3840) Start of screen
    // |               |= 0xEA0 (3744) Start of stack
    // |               |
    // |               |
    // | 0x200 to 0xFFF|
    // |     Chip-8    |
    // | Program / Data|
    // |     Space     |
    // |               |
    // |               |
    // |               |
    // +- - - - - - - -+= 0x600 (1536) Start of ETI 660 Chip-8 programs
    // |               |
    // |               |
    // |               |
    // +---------------+= 0x200 (512) Start of most Chip-8 programs
    // | 0x000 to 0x1FF|
    // | Reserved for  |
    // |  interpreter  |
    // +---------------+= 0x000 (0) Start of Chip-8 RAM
    RAM: [4096]u8,

    // 16 general purpose 8-bit registers
    V: [16]u8,

    // This register is generally used to store memory addresses, so only the lowest
    // (rightmost) 12 bits are usually used.
    I: u16,

    // Sound timer. Decrements at 60Hz when non-zero.
    ST: u8,

    // Delay timer. Decrements at 60Hz when non-zero.
    DT: u8,

    // Program counter
    PC: usize,

    // Stack pointer
    SP: usize,

    // When we're waiting for an input key, this is the register that the key gets
    // written to.
    WaitingForKeyPress: bool,
    KeyWaitRegister: usize,

    pub fn init(prgRom: []u8) Chip8 {
        // Programs may also refer to a group of sprites representing the hexadecimal
        // digits 0 through F. These sprites are 5 bytes long, or 8x5 pixels. The data
        // should be stored in the interpreter area of Chip-8 memory (0x000 to 0x1FF).
        const hex_digits = [_]u8{
            0xf0, 0x90, 0x90, 0x90, 0xf0, // 0
            0x20, 0x60, 0x20, 0x20, 0x70, // 1
            0xf0, 0x10, 0xf0, 0x80, 0xf0, // 2
            0xf0, 0x10, 0xf0, 0x10, 0xf0, // 3
            0x90, 0x90, 0xf0, 0x10, 0x10, // 4
            0xf0, 0x80, 0xf0, 0x10, 0xf0, // 5
            0xf0, 0x80, 0xf0, 0x90, 0xf0, // 6
            0xf0, 0x10, 0x20, 0x40, 0x40, // 7
            0xf0, 0x90, 0xf0, 0x90, 0xf0, // 8
            0xf0, 0x90, 0xf0, 0x10, 0xf0, // 9
            0xf0, 0x90, 0xf0, 0x90, 0x90, // A
            0xe0, 0x90, 0xe0, 0x90, 0xe0, // B
            0xf0, 0x80, 0x80, 0x80, 0xf0, // C
            0xe0, 0x90, 0x90, 0x90, 0xe0, // D
            0xf0, 0x80, 0xf0, 0x80, 0xf0, // E
            0xf0, 0x80, 0xf0, 0x80, 0x80, // F
        };

        var ram: [4096]u8 = undefined;
        mem.set(u8, ram[0..], 0);
        mem.copy(u8, ram[0..], hex_digits[0..]);
        mem.copy(u8, ram[PrgRomAddress..], prgRom[0..]);

        var screen: [ScreenHeight][ScreenWidth]u1 = undefined;
        for (screen) |*row| {
            mem.set(u1, row[0..], 0);
        }

        var keys: [16]bool = undefined;
        mem.set(bool, keys[0..], false);

        var v: [16]u8 = undefined;
        mem.set(u8, v[0..], 0);

        return Chip8{
            .Screen = screen,
            .KeyDown = keys,
            .RAM = ram,
            .V = v,
            .I = 0,
            .ST = 0,
            .DT = 0,
            .PC = PrgRomAddress,
            .SP = 0x0000,
            .WaitingForKeyPress = false,
            .KeyWaitRegister = 0,
        };
    }

    pub fn step(self: *Chip8) bool {
        if (self.WaitingForKeyPress) {
            return false;
        }

        const op1 = self.RAM[self.PC];
        const op2 = self.RAM[self.PC + 1];
        const opcode = (@intCast(u16, op1) << 8) | @intCast(u16, op2);
        const nnn = ((@intCast(u16, op1) & 0x0f) << 8) | @intCast(u16, op2);

        var shouldRender = false;

        switch (op1 & 0xf0) {
            0x00 => {
                if (opcode == 0x00e0) {
                    log.info("{X:0>4} CLS", .{self.PC});
                    for (self.Screen) |*row| {
                        mem.set(u1, row[0..], 0);
                    }
                    self.PC += 2;
                } else if (opcode == 0x00ee) {
                    // The stack is an array of 16-bit values, used to store the address that the
                    // interpreter should return to when finished with a subroutine.
                    self.SP -= 2;
                    const ret = (@intCast(u16, self.RAM[StackAddress + self.SP + 1]) << 8) | @intCast(u16, self.RAM[StackAddress + self.SP]);
                    log.info("{X:0>4} RET = {X:0>4}", .{ self.PC, ret });
                    self.PC = ret;
                } else {
                    log.info("{X:0>4} SYS #{X:0>4}", .{ self.PC, nnn });
                    self.PC = @intCast(usize, nnn);
                }
            },

            0x10 => {
                log.info("{X:0>4} JP #{X:0>4}", .{ self.PC, nnn });
                self.PC = @intCast(usize, nnn);
            },

            0x20 => {
                // The stack is an array of 16-bit values, used to store the address that the interpreter
                // should return to when finished with a subroutine.
                log.info("{X:0>4} CALL #{X:0>4}", .{ self.PC, nnn });
                const nextPC = self.PC + 2;
                self.RAM[StackAddress + self.SP] = @intCast(u8, nextPC & 0x00ff);
                self.RAM[StackAddress + self.SP + 1] = @intCast(u8, (nextPC & 0xff00) >> 8);
                self.SP += 2;
                self.PC = @intCast(usize, nnn);
            },

            0x30 => {
                const vx = @intCast(usize, op1 & 0x0f);
                log.info("{X:0>4} SE V{} ({X:0>4}), #{X:0>2}", .{ self.PC, vx, self.V[vx], op2 });

                if (self.V[vx] == op2) {
                    self.PC += 2;
                }

                self.PC += 2;
            },

            0x40 => {
                const vx = @intCast(usize, op1 & 0x0f);
                log.info("{X:0>4} SNE V{}, #{X:0>2}", .{ self.PC, vx, op2 });

                if (self.V[vx] != op2) {
                    self.PC += 2;
                }

                self.PC += 2;
            },

            0x50 => {
                const vx = @intCast(usize, op1 & 0x0f);
                const vy = @intCast(usize, op2 & 0xf0) >> 4;

                log.info("{X:0>4} SE V{}, V{}", .{ self.PC, vx, vy });

                if (self.V[vx] == self.V[vy]) {
                    self.PC += 2;
                }

                self.PC += 2;
            },

            0x60 => {
                const vx = @intCast(usize, op1 & 0x0f);
                log.info("{X:0>4} LD V{}, #{X:0>2}", .{ self.PC, vx, op2 });
                self.V[vx] = op2;
                self.PC += 2;
            },

            0x70 => {
                const vx = @intCast(usize, op1 & 0x0f);
                log.info("{X:0>4} ADD V{}, #{X:0>2}", .{ self.PC, vx, op2 });

                const v = @addWithOverflow(u8, self.V[vx], op2, &self.V[vx]);
                if (v) {
                    log.info("  result = {}", .{self.V[vx]});
                }
                self.PC += 2;
            },

            0x80 => {
                const vx = @intCast(usize, op1 & 0x0f);
                const vy = @intCast(usize, op2 & 0xf0) >> 4;

                switch (op2 & 0x0f) {
                    0x00 => {
                        log.info("{X:0>4} LD V{}, V{}", .{ self.PC, vx, vy });
                        self.V[vx] = self.V[vy];
                    },
                    0x01 => {
                        log.info("{X:0>4} OR V{}, V{}", .{ self.PC, vx, vy });
                        self.V[vx] |= self.V[vy];
                    },
                    0x02 => {
                        log.info("{X:0>4} AND V{}, V{}", .{ self.PC, vx, vy });
                        self.V[vx] &= self.V[vy];
                    },
                    0x03 => {
                        log.info("{X:0>4} XOR V{}, V{}", .{ self.PC, vx, vy });
                        self.V[vx] ^= self.V[vy];
                    },
                    0x04 => {
                        log.info("{X:0>4} ADD V{}, V{}", .{ self.PC, vx, vy });
                        const rv = @intCast(u16, self.V[vx]) + @intCast(u16, self.V[vy]);
                        self.V[vx] = @intCast(u8, rv & 0x00ff);

                        if (rv > 255) {
                            self.V[0xF] = 1;
                        } else {
                            self.V[0xF] = 0;
                        }
                    },
                    0x05 => {
                        log.info("{X:0>4} SUB V{}, V{}", .{ self.PC, vx, vy });
                        if (self.V[vy] > self.V[vx]) {
                            self.V[0xF] = 0;
                        } else {
                            self.V[0xF] = 1;
                        }

                        // Subtracting Y from X is the same as adding the two's complement of Y with overflow.
                        var tmp_vy: u8 = 0;
                        var v = @addWithOverflow(u8, ~self.V[vy], 1, &tmp_vy);
                        v = @addWithOverflow(u8, self.V[vx], tmp_vy, &self.V[vx]);
                        if (v) {
                            log.info("  result = {}", .{self.V[vx]});
                        }
                    },
                    0x06 => {
                        log.info("{X:0>4} SHR V{}", .{ self.PC, vx });
                        self.V[0xF] = self.V[vx] & 0x01;
                        self.V[vx] >>= 1;
                    },
                    0x07 => {
                        log.info("{X:0>4} SUBN V{}, V{}", .{ self.PC, vx, vy });
                        if (self.V[vx] > self.V[vy]) {
                            self.V[0xF] = 0;
                        } else {
                            self.V[0xF] = 1;
                        }

                        // Subtracting Y from X is the same as adding the two's complement of Y with overflow.
                        var v = @addWithOverflow(u8, ~self.V[vx], 1, &self.V[vx]);
                        v = @addWithOverflow(u8, self.V[vy], self.V[vx], &self.V[vx]);
                        if (v) {
                            log.info("  result = {}", .{self.V[vx]});
                        }
                    },
                    0x0e => {
                        log.info("{X:0>4} SHL V{}", .{ self.PC, vx });
                        self.V[0xF] = (self.V[vx] & 0x80) >> 7;
                        self.V[vx] <<= 1;
                    },
                    else => {},
                }

                self.PC += 2;
            },

            0x90 => {
                const vx = @intCast(usize, op1 & 0x0f);
                const vy = @intCast(usize, op2 & 0xf0) >> 4;

                log.info("{X:0>4} SNE V{}, V{}", .{ self.PC, vx, vy });

                if (self.V[vx] != self.V[vy]) {
                    self.PC += 2;
                }

                self.PC += 2;
            },

            0xa0 => {
                log.info("{X:0>4} LD I, #{X:0>4}", .{ self.PC, nnn });
                self.I = nnn;
                self.PC += 2;
            },

            0xb0 => {
                log.info("{X:0>4} JP V0, #{X:0>4}", .{ self.PC, nnn });
                self.PC = @intCast(u16, self.V[0]) + nnn;
            },

            0xc0 => {
                const vx = @intCast(usize, op1 & 0x0f);

                log.info("{X:0>4} RND V{}, #{X:0>2}", .{ self.PC, vx, op2 });
                var rnd: [1]u8 = undefined;
                os.getrandom(&rnd) catch |err| {
                    log.info("Unable to getrandom: {s}", .{err});
                };
                self.V[vx] = rnd[0] & op2;
                self.PC += 2;
            },

            0xd0 => {
                const vx = self.V[@intCast(usize, op1 & 0x0f)];
                const vy = self.V[@intCast(usize, op2 & 0xf0) >> 4];
                const n_rows = @intCast(usize, op2) & 0x0f;

                log.info("{X:0>4} DRW V{}, V{}, {X:0>2}", .{ self.PC, vx, vy, n_rows });

                self.V[0xF] = 0;
                var y: usize = 0;
                while (y < n_rows) {
                    const sprite_row = self.RAM[@intCast(usize, self.I) + y];
                    const screen_y = (vy + y) % ScreenHeight;

                    var x: usize = 0;
                    while (x < 8) {
                        const val = (sprite_row >> (7 - @intCast(u3, x))) & 1;
                        const screen_x = (vx + x) % ScreenWidth;

                        if ((self.Screen[screen_y][screen_x] == 1) and (val == 1)) {
                            self.V[0xF] |= 1;
                        }

                        self.Screen[screen_y][screen_x] ^= @intCast(u1, val);

                        x += 1;
                    }
                    y += 1;
                }

                shouldRender = true;
                self.PC += 2;
            },

            0xe0 => {
                const vx = @intCast(usize, op1 & 0x0f);
                const idx = @intCast(usize, self.V[vx]);

                switch (op2) {
                    0x9e => {
                        log.info("{X:0>4} SKP V{}", .{ self.PC, vx });

                        if (self.KeyDown[idx]) {
                            self.PC += 2;
                        }

                        self.PC += 2;
                    },
                    0xa1 => {
                        log.info("{X:0>4} SKNP V{}", .{ self.PC, vx });

                        if (!self.KeyDown[idx]) {
                            self.PC += 2;
                        }

                        self.PC += 2;
                    },

                    else => {},
                }
            },

            0xf0 => {
                const vx = @intCast(usize, op1 & 0x0f);

                switch (op2) {
                    0x07 => {
                        log.info("{X:0>4} LD V{}, DT", .{ self.PC, vx });
                        self.V[vx] = self.DT;
                    },
                    0x0a => {
                        log.info("{X:0>4} LD V{}, K", .{ self.PC, vx });
                        self.WaitingForKeyPress = true;
                        self.KeyWaitRegister = vx;
                    },
                    0x15 => {
                        log.info("{X:0>4} LD DT, V{}", .{ self.PC, vx });
                        self.DT = self.V[vx];
                    },
                    0x18 => {
                        log.info("{X:0>4} LD ST, V{}", .{ self.PC, vx });
                        self.ST = self.V[vx];
                    },
                    0x1e => {
                        log.info("{X:0>4} ADD I, V{}", .{ self.PC, vx });
                        self.I += self.V[vx];
                    },
                    0x29 => {
                        log.info("{X:0>4} LD F, V{}", .{ self.PC, vx });
                        self.I = self.V[vx] * 5;
                    },
                    0x33 => {
                        log.info("{X:0>4} LD B, V{}", .{ self.PC, vx });

                        const hundreds = self.V[vx] / 100;
                        self.RAM[self.I] = hundreds;

                        const tens = (self.V[vx] - (hundreds * 100)) / 10;
                        self.RAM[self.I + 1] = tens;

                        const units = self.V[vx] - (hundreds * 100) - (tens * 10);
                        self.RAM[self.I + 2] = units;
                    },
                    0x55 => {
                        log.info("{X:0>4} LD [I], V{}", .{ self.PC, vx });

                        var i: usize = 0;
                        while (i <= vx) {
                            self.RAM[self.I + i] = self.V[i];
                            i += 1;
                        }
                    },
                    0x65 => {
                        log.info("{X:0>4} LD V{}, [I]", .{ self.PC, vx });

                        var i: usize = 0;
                        while (i <= vx) {
                            self.V[i] = self.RAM[self.I + i];
                            i += 1;
                        }
                    },

                    else => {},
                }

                self.PC += 2;
            },

            else => {
                log.info("{X:0>4} error 0x{X:0>2}", .{ self.PC, op1 });
            },
        }

        return shouldRender;
    }

    pub fn keyDown(self: *Chip8, key: usize) void {
        self.KeyDown[key] = true;

        if (self.WaitingForKeyPress) {
            self.WaitingForKeyPress = false;
            self.V[self.KeyWaitRegister] = @intCast(u8, key);
        }
    }

    pub fn keyUp(self: *Chip8, key: usize) void {
        self.KeyDown[key] = false;
    }

    pub fn tickTimers(self: *Chip8) void {
        if (self.DT > 0) {
            self.DT -= 1;
        }

        if (self.ST > 0) {
            self.ST -= 1;
        }
    }
};

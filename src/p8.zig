const rl = @import("raylib");
const std = @import("std");

pub const P8 = struct {
    camera: rl.Camera2D,

    sheet: rl.Texture2D,
    sounds: [8]rl.Sound,

    rand: std.Random,
    prng: std.Random.Xoshiro256,

    pub const Palette = enum(u4) {
        black = 0,
        dark_blue = 1,
        dark_purple = 2,
        dark_green = 3,
        brown = 4,
        dark_grey = 5,
        light_grey = 6,
        white = 7,
        red = 8,
        orange = 9,
        yellow = 10,
        green = 11,
        blue = 12,
        lavender = 13,
        pink = 14,
        light_peach = 15,

        pub const palette: [16]rl.Color = .{
            .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .{ .r = 29, .g = 43, .b = 83, .a = 255 },
            .{ .r = 126, .g = 37, .b = 83, .a = 255 },
            .{ .r = 0, .g = 135, .b = 81, .a = 255 },
            .{ .r = 171, .g = 82, .b = 54, .a = 255 },
            .{ .r = 95, .g = 87, .b = 79, .a = 255 },
            .{ .r = 194, .g = 195, .b = 199, .a = 255 },
            .{ .r = 255, .g = 241, .b = 232, .a = 255 },
            .{ .r = 255, .g = 0, .b = 77, .a = 255 },
            .{ .r = 255, .g = 163, .b = 0, .a = 255 },
            .{ .r = 255, .g = 236, .b = 39, .a = 255 },
            .{ .r = 0, .g = 228, .b = 54, .a = 255 },
            .{ .r = 41, .g = 173, .b = 255, .a = 255 },
            .{ .r = 131, .g = 118, .b = 156, .a = 255 },
            .{ .r = 255, .g = 119, .b = 168, .a = 255 },
            .{ .r = 255, .g = 204, .b = 170, .a = 255 },
        };

        pub fn toColor(self: Palette) rl.Color {
            return palette[@intFromEnum(self)];
        }
    };

    pub fn init(self: *P8) void {
        self.camera = rl.Camera2D{
            .offset = rl.Vector2.zero(),
            .rotation = 0,
            .target = rl.Vector2.zero(),
            .zoom = 1,
        };

        var seed: u64 = 0;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch @panic("random setup failed");

        self.prng = std.Random.Xoshiro256.init(seed);

        self.rand = self.prng.random();

        const image = rl.loadImageFromMemory(
            ".png",
            @embedFile("assets/spritesheet.png"),
        ) catch unreachable;

        self.sheet = rl.loadTextureFromImage(image) catch unreachable;

        for (0..8) |i| {
            const wav = switch (i) {
                0 => @embedFile("assets/mygame_sfx_0.wav"),
                1 => @embedFile("assets/mygame_sfx_1.wav"),
                2 => @embedFile("assets/mygame_sfx_2.wav"),
                3 => @embedFile("assets/mygame_sfx_3.wav"),
                4 => @embedFile("assets/mygame_sfx_4.wav"),
                5 => @embedFile("assets/mygame_sfx_5.wav"),
                6 => @embedFile("assets/mygame_sfx_6.wav"),
                7 => @embedFile("assets/mygame_sfx_7.wav"),
                else => unreachable,
            };

            const wave = rl.loadWaveFromMemory(".wav", wav) catch unreachable;
            defer rl.unloadWave(wave);

            self.sounds[i] = rl.loadSoundFromWave(wave);
        }
    }

    pub fn rnd(self: *const P8, max: f32) f32 {
        return self.rand.float(f32) * max;
    }

    pub fn rndInt(self: *const P8, max: u16) u16 {
        return self.rand.intRangeAtMost(u16, 0, max);
    }

    pub fn rndChoose(self: *const P8, comptime T: type, options: []const T) T {
        return options[self.rand.int(usize) % options.len];
    }

    pub fn circfill(_: *const P8, x: f32, y: f32, r: f32, c: P8.Palette) void {
        rl.drawCircleSector(
            rl.Vector2{ .x = x, .y = y },
            r,
            0,
            360,
            5,
            c.toColor(),
        );
    }

    pub fn sfx(self: *const P8, n: u8) void {
        rl.playSound(self.sounds[n]);
    }

    pub fn spr(self: *const P8, n: u8, x: f32, y: f32, flip_x: bool, flip_y: bool) void {
        const sprite_size = 8;

        const source: rl.Rectangle = .{
            .x = @as(f32, @floatFromInt(n % 16)) * sprite_size,
            .y = @as(f32, @floatFromInt(n / 16)) * sprite_size,
            .width = if (flip_x) -sprite_size else sprite_size,
            .height = if (flip_y) -sprite_size else sprite_size,
        };

        const dest = rl.Vector2{ .x = x, .y = y };

        rl.drawTextureRec(
            self.sheet,
            source,
            dest,
            rl.Color.white,
        );
    }

    pub fn cls(
        _: *const P8,
    ) void {
        rl.clearBackground(.white);
    }
};

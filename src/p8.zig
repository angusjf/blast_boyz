const rl = @import("raylib");
const std = @import("std");

var palette: [16]rl.Color = undefined;

pub const P8 = struct {
    camera: rl.Camera2D,

    sheet: rl.Texture2D,
    sounds: [8]rl.Sound,

    rand: std.Random,
    prng: std.Random.Xoshiro256,

    pub fn init(self: *P8) void {
        self.camera = rl.Camera2D{
            .offset = rl.Vector2.zero(),
            .rotation = 0,
            .target = rl.Vector2.zero(),
            .zoom = 1,
        };

        palette = .{
            rl.Color.fromInt(0x000000), // black
            rl.Color.fromInt(0x1D2B53), // dark-blue
            rl.Color.fromInt(0x7E2553), // dark-purple
            rl.Color.fromInt(0x008751), // dark-green
            rl.Color.fromInt(0xAB5236), // brown
            rl.Color.fromInt(0x5F574F), // dark-grey
            rl.Color.fromInt(0xC2C3C7), // light-grey
            rl.Color.fromInt(0xFFF1E8), // white
            rl.Color.fromInt(0xFF004D), // red
            rl.Color.fromInt(0xFFA300), // orange
            rl.Color.fromInt(0xFFEC27), // yellow
            rl.Color.fromInt(0x00E436), // green
            rl.Color.fromInt(0x29ADFF), // blue
            rl.Color.fromInt(0x83769C), // lavender
            rl.Color.fromInt(0xFF77A8), // pink
            rl.Color.fromInt(0xFFCCAA), // light-peach
        };

        var seed: u64 = undefined;
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

    pub fn rndChoose(self: *const P8, options: []const u16) u16 {
        return options[self.rand.int(usize) % options.len];
    }

    pub fn circfill(_: *const P8, x: f32, y: f32, r: f32, c: u16) void {
        rl.drawCircleSector(
            rl.Vector2{ .x = x, .y = y },
            r,
            0,
            360,
            5,
            palette[c],
        );
    }

    pub fn sfx(self: *const P8, n: u8) void {
        rl.playSound(self.sounds[n]);
    }

    pub fn spr(self: *const P8, n: u8, x: f32, y: f32, flip_x: bool, flip_y: bool) void {
        const sprite_size = 8;

        const source: rl.Rectangle = .{
            .x = @as(f32, @floatFromInt(n)) * sprite_size,
            .y = 0,
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

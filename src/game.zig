const rl = @import("raylib");
const std = @import("std");

pub const Buttons = struct {
    left_hit: bool = false,
    right_hit: bool = false,
    up_hit: bool = false,
    x_hit: bool = false,
    left_held: bool = false,
    right_held: bool = false,
    up_held: bool = false,
    x_held: bool = false,
};

const player_sprites = [2]struct {
    norm: u8,
    jump: u8,
    fall: u8,
    down: u8,
}{
    .{
        .norm = 5,
        .jump = 21,
        .fall = 37,
        .down = 53,
    },
    .{
        .norm = 6,
        .jump = 22,
        .fall = 38,
        .down = 54,
    },
};

const bomb_spr = 3;
const bomb_red_spr = 19;

const bg_sprite = 4;

const block_sprite = 2;

const grav = 0.35;
const jump = 4.5;
const throw = 4;
const walk = 20;
const fric = 0.1;
const gem_fric = 0.95;
const bomb_life = 240;

const State = struct {
    players: [2]Player,
    ticks: u16,
    paused: bool,
    active: u1,
    blocks: std.ArrayList(Vec2),
    bombs: std.ArrayList(Bomb),
    particles: std.ArrayList(Particle),
    shake: f32,
};

var sheet: ?rl.Texture2D = null;

const Player = struct {
    vx: f32,
    vy: f32,
    flip: bool,
    x: f32,
    y: f32,
    grounded: bool,
    carry: bool,
};

var state: State = undefined;

const Vec2 = struct { x: f32, y: f32 };

const Bomb = struct { x: f32, y: f32, vx: f32, vy: f32, t: u16 };

const Particle = struct {
    type: u16,
    t: u16,
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    r: f32,
    c: u16,
};

var blocks_buf: [64]Vec2 = undefined;
var bombs_buf: [64]Bomb = undefined;
var particles_buf: [1024]Particle = undefined;

var rand: std.Random = undefined;
var prng: std.Random.Xoshiro256 = undefined;

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a * (1 - t) + b * t;
}

var palette: [16]rl.Color = undefined;

pub fn init(active: u1) !void {
    prng = std.Random.Xoshiro256.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch @panic("random setup failed");
        break :blk seed;
    });

    rand = prng.random();

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

    state = .{
        .players = [2]Player{
            .{
                .vx = 0,
                .vy = -1,
                .flip = false,
                .x = 8,
                .y = 23,
                .grounded = false,
                .carry = false,
            },
            .{
                .vx = 0,
                .vy = -1,
                .flip = true,
                .x = 112,
                .y = 10,
                .grounded = false,
                .carry = false,
            },
        },
        .ticks = 0,
        .paused = true,
        .active = active,
        .blocks = .initBuffer(&blocks_buf),
        .bombs = .initBuffer(&bombs_buf),
        .particles = .initBuffer(&particles_buf),
        .shake = 0,
    };

    for (0..16) |x| {
        for (0..16) |y| {
            const m = mget(x, y);
            if (m == block_sprite) {
                state.blocks.appendAssumeCapacity(.{
                    .x = @floatFromInt(x * 8),
                    .y = @floatFromInt(y * 8),
                });
            } else if (m >= 7 and m <= 11) {
                // add(gems, { m=m, x=x*8, y=y*8, vx=0, vy=0 })
            }
        }
    }
}

fn mget(x: usize, y: usize) u16 {
    const map =
        \\0000000000000000
        \\0000000000000000
        \\0000000000000000
        \\0000111000000000
        \\0000000000000000
        \\0000000000000111
        \\0000000000000000
        \\0000000000000000
        \\0000000000000000
        \\1110000000111100
        \\0000000000000000
        \\0000000000000000
        \\1111000000000000
        \\0000000000000000
        \\0000000011110000
        \\0000000000000000
        \\0000000000000000
        \\0000000000000000
        \\
    ;

    return switch (map[y * 17 + x]) {
        '1' => block_sprite,
        else => 0,
    };
}

fn control(p: *Player, buttons: Buttons) void {
    if (buttons.left_held) {
        p.vx = -walk;
        p.flip = true;
    } else if (buttons.right_held) {
        p.vx = walk;

        p.flip = false;
    }

    if (buttons.up_hit and p.vy == 0) {
        p.vy = -jump;
        sfx(0);
    }

    if (buttons.x_hit) {
        if (p.carry) {
            sfx(6);

            var dx: f32 = if (p.flip) -throw else throw;

            if (!(buttons.left_held or buttons.right_held))
                dx /= 10;

            state.bombs.items[0].vy += -throw + p.vy / 15;
            state.bombs.items[0].vx = dx + p.vx / 15;

            p.carry = false;
        } else {
            if (bomb_near(p.x, p.y)) |_| {
                sfx(2);
                p.carry = true;
            }
        }
    }
}

fn rnd(max: f32) f32 {
    return rand.float(f32) * max;
}

fn rndInt(max: u16) u16 {
    return rand.intRangeAtMost(u16, 0, max);
}

fn rndChoose(options: []const u16) u16 {
    return options[rand.int(usize) % options.len];
}

pub fn update(user_buttons: Buttons, network_buttons: Buttons) !void {
    state.shake = lerp(state.shake, 0, 0.3);
    //
    // if paused then
    //   if btn(0) and btn(1)
    //     and btn(2) and btn(4) then
    //     paused = false
    //     sfx(3)
    //     return
    //   else
    //     return
    //   end
    // end
    //
    state.ticks +%= 1;

    if (state.ticks % 100 == 99 and state.bombs.items.len == 0)
        state.bombs.appendAssumeCapacity(.{
            .x = 10 + rnd(100),
            .y = 0,
            .vx = 0,
            .vy = 0,
            .t = 0,
        });

    for (state.bombs.items) |bomb| {
        if (state.ticks % 10 == 0) {
            const particle = Particle{
                .type = 0,
                .t = rndInt(150),
                .x = bomb.x + rnd(5),
                .y = bomb.y + rnd(5) - 2,
                .vx = (rnd(1) - 1) / 2,
                .vy = (rnd(1) - 1) / 2,
                .r = rnd(2),
                .c = rndChoose(&[_]u16{ 5, 9, 10, 13 }),
            };
            state.particles.appendBounded(particle) catch {};
        }
    }

    control(&state.players[state.active], user_buttons);
    control(&state.players[
        switch (state.active) {
            0 => 1,
            1 => 0,
        }
    ], network_buttons);

    for (&state.players) |*player| {
        player.vy += grav;
        player.vx *= fric;

        if (player.x + player.vx < 0) {
            player.x = 0 - player.vx;
            player.vx *= -1;
        } else if (player.x + player.vx > 128 - 8) {
            player.x = 128 - 8;
            player.vx *= -1;
        } else {
            player.x += player.vx;
        }

        const d2b = dist_to_block(player.x, player.y);

        if (player.vy > d2b) {
            player.y += d2b;
            player.vy = 0;
            if (!player.grounded) {
                sfx(4);
                player.grounded = true;
            }
        } else {
            player.y += player.vy;
        }

        if (player.vy != 0) {
            player.grounded = false;
        }

        player.y = @mod(player.y + 128, 128);
    }

    for (state.bombs.items, 0..) |*bomb, i| {
        if (bomb.t == bomb_life) {
            explode(bomb);
            _ = state.bombs.swapRemove(i);
        }

        for (state.players) |p| {
            if (p.carry) {
                bomb.vx = 0;
                bomb.vy = 0;
                bomb.x = p.x;
                bomb.y = p.y - 7;
                break;
            }
        } else {
            bomb.vy += grav;
            bomb.vx *= gem_fric;

            if (bomb.x + bomb.vx < 0) {
                bomb.x = 0 - bomb.vx;
                bomb.vx *= -1;
                state.shake = 2;
            } else if (bomb.x + bomb.vx > 128 - 8) {
                bomb.x = 128 - bomb.vx - 8;
                bomb.vx *= -1;
                state.shake = 2;
            } else {
                bomb.x += bomb.vx;
            }

            const d2b = dist_to_block(bomb.x, bomb.y);

            if (bomb.vy > d2b) {
                if (bomb.vy > 0.5) {
                    sfx(7);
                }
                bomb.y += d2b;
                bomb.vy = -bomb.vy / 4;
                bomb.vx = bomb.vy / 2 * (rnd(1) - 0.5);
            } else {
                bomb.y += bomb.vy;
            }
        }
        bomb.t += 1;
    }

    for (state.particles.items, 0..) |*s, i| {
        if (s.t <= 0) {
            _ = state.particles.swapRemove(i);

            // TODO figure out
            break;
        } else {
            s.x += s.vx;
            s.y += s.vy;
            s.t -= 1;
        }
    }
}

fn circfill(x: f32, y: f32, r: f32, c: u16) void {
    rl.drawCircleSector(
        rl.Vector2{ .x = x, .y = y },
        r,
        0,
        360,
        5,
        palette[c],
    );
}

pub fn draw() !void {
    rl.clearBackground(.white);

    //   palt()
    //
    //   if shake > 0.1 then
    //     camera(rnd(shake) - shake/2,
    //            rnd(shake) - shake/2)
    //   else
    //     camera(0, 0)
    //     camera(0, 0)
    //   end
    //
    // for 0,15 do
    //   for y=0,15 do
    //     spr(bg_sprite, x * 8, y * 8)
    //   end
    // end
    //

    for (state.particles.items) |s| {
        circfill(s.x, s.y, s.r, s.c);
    }
    //
    //   palt(0b0000000100000000)
    //
    for (state.blocks.items) |block| {
        spr(block_sprite, block.x, block.y, false, false);
    }

    for (0..2) |p| {
        const player_sprite = if (state.players[p].vy < 0)
            player_sprites[p].jump
        else
            (if (state.players[p].vy > 0)
                player_sprites[p].fall
            else
                player_sprites[p].norm);

        spr(
            player_sprite,
            state.players[p].x,
            state.players[p].y,
            state.players[p].flip,
            false,
        );
    }

    //   palt(12)

    for (state.bombs.items) |bomb| {
        var mod: u16 = undefined;
        if (bomb.t > bomb_life * 0.8) {
            mod = 5;
        } else if (bomb.t > bomb_life * 0.6) {
            mod = 10;
        } else if (bomb.t > bomb_life * 0.4) {
            mod = 20;
        } else {
            mod = 100;
        }

        var bomb_anim: u8 = bomb_spr;
        if ((state.ticks / mod) % 2 != 1) {
            bomb_anim = bomb_red_spr;
        }

        spr(bomb_anim, bomb.x, bomb.y, false, false);
    }
}

fn sfx(n: u8) void {
    const data: []const u8 = switch (n) {
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

    const wave = rl.loadWaveFromMemory(".wav", data) catch unreachable;

    const sound = rl.loadSoundFromWave(wave);

    rl.unloadWave(wave);

    rl.playSound(sound);
}

fn spr(n: u8, x: f32, y: f32, flip_x: bool, flip_y: bool) void {
    const sprite_size = 8;

    if (sheet == null) {
        const image = rl.loadImageFromMemory(
            ".png",
            @embedFile("assets/spritesheet.png"),
        ) catch unreachable;
        sheet = rl.loadTextureFromImage(image) catch unreachable;
    }

    const source: rl.Rectangle = .{
        .x = @as(f32, @floatFromInt(n)) * sprite_size,
        .y = 0,
        .width = if (flip_x) -sprite_size else sprite_size,
        .height = if (flip_y) -sprite_size else sprite_size,
    };

    const dest = rl.Vector2{ .x = x, .y = y };

    rl.drawTextureRec(
        sheet.?,
        source,
        dest,
        rl.Color.white,
    );
}

fn explode(bomb: *Bomb) void {
    sfx(1);
    state.shake = 10;

    for (&state.players) |*p| {
        p.carry = false;

        const dx = p.x - bomb.x;
        const dy = p.y - bomb.y;
        const dist = std.math.sqrt(dx * dx + dy * dy) + 1;
        const force = 10;
        p.vx += std.math.sign(dx) * force / dist;
        p.vy += std.math.sign(dy - 1) * force / dist;
    }

    for (1..20) |_| {
        state.particles.appendBounded(.{
            .type = 1,
            .t = rndInt(50),
            .x = bomb.x + rnd(10) - 5,
            .y = bomb.y + rnd(10) - 5,
            .vx = rnd(2) - 1,
            .vy = rnd(2) - 1,
            .r = rnd(5),
            .c = rndChoose(&[_]u16{ 5, 6, 7, 13 }),
        }) catch unreachable;
    }
}

fn bomb_near(x: f32, y: f32) ?Bomb {
    for (state.bombs.items) |bomb| {
        if (x > bomb.x - 8 and
            x < bomb.x + 8 and
            y > bomb.y - 8 and
            y < bomb.y + 8)
        {
            return bomb;
        }
    }
    return null;
}

fn dist_to_block(x: f32, y: f32) f32 {
    var d2b: f32 = 999;

    for (state.blocks.items) |block| {
        if (x > block.x - 8 and x < block.x + 8 and y + 8 <= block.y) {
            d2b = @min(d2b, block.y - (y + 8));
        }
    }

    return d2b;
}

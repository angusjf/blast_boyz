const std = @import("std");
const rl = @import("raylib");
const P8 = @import("p8.zig").P8;

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
const bomb_fric = 0.95;
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
    c: P8.Palette,
};

var blocks_buf: [64]Vec2 = undefined;
var bombs_buf: [64]Bomb = undefined;
var particles_buf: [1024]Particle = undefined;

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a * (1 - t) + b * t;
}

var p8: P8 = undefined;

pub fn init(active: u1) !void {
    p8.init();

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
        p8.sfx(0);
    }

    if (buttons.x_hit) {
        if (p.carry) {
            p8.sfx(6);

            var dx: f32 = if (p.flip) -throw else throw;

            if (!(buttons.left_held or buttons.right_held))
                dx /= 10;

            state.bombs.items[0].vy += -throw + p.vy / 15;
            state.bombs.items[0].vx = dx + p.vx / 15;

            p.carry = false;
        } else {
            if (bomb_near(p.x, p.y)) |_| {
                p8.sfx(2);
                p.carry = true;
            }
        }
    }
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
            .x = 10 + p8.rnd(100),
            .y = 0,
            .vx = 0,
            .vy = 0,
            .t = 0,
        });

    for (state.bombs.items) |bomb| {
        if (state.ticks % 10 == 0) {
            const particle = Particle{
                .type = 0,
                .t = p8.rndInt(150),
                .x = bomb.x + p8.rnd(5),
                .y = bomb.y + p8.rnd(5) - 2,
                .vx = (p8.rnd(1) - 1) / 2,
                .vy = (p8.rnd(1) - 1) / 2,
                .r = p8.rnd(2) + 1,
                .c = p8.rndChoose(P8.Palette, &[_]P8.Palette{
                    P8.Palette.dark_grey,
                    P8.Palette.orange,
                    P8.Palette.black,
                    P8.Palette.lavender,
                }),
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
            player.x = 0;
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
                p8.sfx(4);
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
            bomb.vx *= bomb_fric;

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
                    p8.sfx(7);
                }
                bomb.y += d2b;
                bomb.vy = -bomb.vy / 4;
                bomb.vx = bomb.vy / 2 * (p8.rnd(1) - 0.5);
            } else {
                bomb.y += bomb.vy;
            }
            bomb.y = @mod(bomb.y + 128, 128);
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

pub fn draw() !void {
    p8.camera.begin();
    defer p8.camera.end();

    if (state.shake > 0.1) {
        p8.camera.offset.x = p8.rnd(state.shake) - state.shake / 2;
        p8.camera.offset.y = p8.rnd(state.shake) - state.shake / 2;
    } else {
        p8.camera.offset.x = 0;
        p8.camera.offset.y = 0;
    }

    {
        // var total_x: f32 = 0;
        // var total_y: f32 = 0;

        // for (state.players) |p| {
        //     total_x += p.x;
        //     total_y += p.y;
        // }

        // total_x /= state.players.len;
        // total_y /= state.players.len;

        // TODO camera follows lads
        // p8.camera.target.x = total_x;
        // p8.camera.target.y = total_y;
    }

    p8.cls();

    {
        var y: f32 = -16;
        while (y < 144) : (y += 8) {
            var x: f32 = -16;
            while (x < 144) : (x += 8) {
                p8.spr(bg_sprite, x, y, false, false);
            }
        }
    }

    for (state.particles.items) |s| {
        p8.circfill(s.x, s.y, s.r, s.c);
    }

    for (state.blocks.items) |block| {
        p8.spr(block_sprite, block.x, block.y, false, false);
    }

    for (0..2) |p| {
        const player_sprite: u8 = spr: {
            if (state.players[p].vy < 0) {
                break :spr player_sprites[p].jump;
            } else if (state.players[p].vy > 0) {
                break :spr player_sprites[p].fall;
            } else if (state.players[p].carry) {
                break :spr player_sprites[p].down;
            } else {
                break :spr player_sprites[p].norm;
            }
        };

        p8.spr(
            player_sprite,
            state.players[p].x,
            state.players[p].y,
            state.players[p].flip,
            false,
        );
    }

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

        p8.spr(bomb_anim, bomb.x, bomb.y, false, false);
    }
}

fn explode(bomb: *Bomb) void {
    p8.sfx(1);
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
            .t = p8.rndInt(50),
            .x = bomb.x + p8.rnd(10) - 5,
            .y = bomb.y + p8.rnd(10) - 5,
            .vx = p8.rnd(2) - 1,
            .vy = p8.rnd(2) - 1,
            .r = p8.rnd(5),
            .c = p8.rndChoose(P8.Palette, &[_]P8.Palette{
                P8.Palette.dark_grey,
                P8.Palette.light_grey,
                P8.Palette.white,
                P8.Palette.lavender,
            }),
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

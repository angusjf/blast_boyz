const std = @import("std");
const rl = @import("raylib");
const game = @import("game.zig");

const PORT: u16 = 50000;

fn broadcastDiscovery(fd: std.posix.fd_t) !void {
    std.debug.print("sending discovery request to 255.255.255.255\n", .{});

    var broadcast = std.posix.sockaddr.in{
        .family = std.posix.AF.INET,
        .port = std.mem.nativeToBig(u16, PORT),
        .addr = 0xFFFFFFFF,
        .zero = .{0} ** 8,
    };

    const req = "slim easy";

    _ = try std.posix.sendto(
        fd,
        req,
        0,
        @ptrCast(&broadcast),
        @sizeOf(std.posix.sockaddr.in),
    );
}

fn bindSocket(fd: std.posix.fd_t, port: u16) !void {
    var addr = std.posix.sockaddr.in{
        .family = std.posix.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = 0, //std.posix.in_addr{ .s_addr = 0 },
        .zero = .{0} ** 8,
    };

    try std.posix.bind(
        fd,
        @ptrCast(&addr),
        @sizeOf(std.posix.sockaddr.in),
    );
}

var is_connected = false;

fn getNetworkButtons(fd: std.posix.fd_t, network_keys: *game.Buttons) void {
    var from: std.posix.sockaddr.in = undefined;
    var from_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);

    _ = std.posix.recvfrom(
        fd,
        std.mem.asBytes(network_keys),
        0,
        @ptrCast(&from),
        &from_len,
    ) catch |err| switch (err) {
        error.WouldBlock => return,
        else => {
            std.debug.print("recv error: {}\n", .{err});
            return;
        },
    };
}

fn listenForFriend(fd: std.posix.fd_t) ?std.posix.sockaddr.in {
    var from: std.posix.sockaddr.in = undefined;
    var from_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);

    var buf: [512]u8 = undefined;
    const n = std.posix.recvfrom(
        fd,
        &buf,
        0,
        @ptrCast(&from),
        &from_len,
    ) catch |err| switch (err) {
        error.WouldBlock => return null,
        else => {
            std.debug.print("recv error: {}\n", .{err});
            @panic("ERROR RECV");
        },
    };

    return if (std.mem.eql(u8, buf[0..n], "lesgo"))
        from
    else
        null;
}

pub fn main() !void {
    var args = std.process.args();

    _ = args.skip();

    const player, const network = args: {
        var p: u1 = 0;
        var n = false;
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "p1")) {
                p = 0;
            } else if (std.mem.eql(u8, arg, "p2")) {
                p = 1;
            } else if (std.mem.eql(u8, arg, "offline")) {
                n = false;
            } else {
                @panic("must be p1, p2 or offline");
            }
        }
        break :args .{ p, n };
    };

    std.debug.print("{d}", .{player});

    const scale = 4;
    const width = 128;
    const height = 128;

    rl.initWindow(width * scale, width * scale, "Blast Boyz");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const target: rl.RenderTexture2D = try rl.loadRenderTexture(width, height);
    rl.setTextureFilter(target.texture, rl.TextureFilter.point);
    rl.initAudioDevice();

    var sock: std.posix.socket_t = undefined;
    defer if (network) std.posix.close(sock);

    var from: std.posix.sockaddr.in = undefined;

    if (network) {
        // get a socket and set domain, type and protocol flags
        sock = try std.posix.socket(
            std.posix.AF.INET,
            std.posix.SOCK.DGRAM,
            std.posix.IPPROTO.UDP,
        );

        {
            var flags: std.posix.O = @bitCast(@as(u32, @truncate(
                try std.posix.fcntl(sock, std.posix.F.GETFL, 0),
            )));

            // modify
            flags.NONBLOCK = true;

            _ = try std.posix.fcntl(
                sock,
                std.posix.F.SETFL,
                @intCast(@as(u32, @bitCast(flags))),
            );
        }

        if (player == 0) {
            std.debug.print("putting socket in broadcast mode.\n", .{});

            const yes: c_int = 1;
            try std.posix.setsockopt(
                sock,
                std.posix.SOL.SOCKET,
                std.posix.SO.BROADCAST,
                std.mem.asBytes(&yes),
            );
        }

        try bindSocket(sock, PORT);

        if (player == 0) {
            var last_broadcast: i64 = 0;
            while (true) {
                const now = std.time.milliTimestamp();
                if (now - last_broadcast > 1000) {
                    std.debug.print("broadcasting\n", .{});
                    try broadcastDiscovery(sock);
                    last_broadcast = now;
                }

                if (listenForFriend(sock)) |ad| {
                    from = ad;
                    std.debug.print("found!\n", .{});

                    break;
                }
            }
        } else {
            var from_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
            var buf: [512]u8 = undefined;
            while (true) {
                std.debug.print("waiting for broadcast,,..\n", .{});
                const n = std.posix.recvfrom(
                    sock,
                    &buf,
                    0,
                    @ptrCast(&from),
                    &from_len,
                ) catch |err| switch (err) {
                    error.WouldBlock => {
                        continue;
                    },
                    else => {
                        std.debug.print("recv error: {}\n", .{err});
                        @panic("ERROR RECV");
                    },
                };
                std.debug.print("got my broadcaste: {s}\n", .{buf[0..n]});
                break;
            }

            std.debug.print("... now sendin lesgo,,.. {any}\n", .{from});

            _ = try std.posix.sendto(
                sock,
                "lesgo",
                0,
                @ptrCast(&from),
                @sizeOf(std.posix.sockaddr.in),
            );

            std.debug.print("... sent!\n", .{});
        }
    }

    try game.init(player);
    var network_buttons = game.Buttons{};
    var user_buttons = game.Buttons{};

    while (!rl.windowShouldClose()) {
        user_buttons = .{
            .left_hit = rl.isKeyPressed(rl.KeyboardKey.left),
            .right_hit = rl.isKeyPressed(rl.KeyboardKey.right),
            .up_hit = rl.isKeyPressed(rl.KeyboardKey.up),
            .x_hit = rl.isKeyPressed(rl.KeyboardKey.x),
            .left_held = rl.isKeyDown(rl.KeyboardKey.left),
            .right_held = rl.isKeyDown(rl.KeyboardKey.right),
            .up_held = rl.isKeyDown(rl.KeyboardKey.up),
            .x_held = rl.isKeyDown(rl.KeyboardKey.x),
        };

        if (network) {
            getNetworkButtons(sock, &network_buttons);

            _ = try std.posix.sendto(
                sock,
                std.mem.asBytes(&user_buttons),
                0,
                @ptrCast(&from),
                @sizeOf(std.posix.sockaddr.in),
            );
        }

        try game.update(user_buttons, network_buttons);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.beginTextureMode(target);

        try game.draw();

        rl.endTextureMode();
        const src = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(target.texture.width),
            .height = @floatFromInt(-target.texture.height),
        };

        const dst = rl.Rectangle{
            .x = 0,
            .y = 0,
            .width = width * scale,
            .height = height * scale,
        };

        rl.drawTexturePro(
            target.texture,
            src,
            dst,
            rl.Vector2.zero(),
            0,
            rl.Color.white,
        );
    }
}

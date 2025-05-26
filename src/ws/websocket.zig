const std = @import("std");
const net = std.net;
const crypto = std.crypto;
const base64 = std.base64;
const mem = std.mem;

const aio = @import("aio");
const coro = @import("coro");

const Request = @import("http").Request;
const Frame = @import("./frame.zig");
const Opcode = Frame.Opcode;

const WebSocket = @This();

pub const Error = error{
    InvalidHandshake,
    InvalidFrame,
    UnsupportedFrame,
    ConnectionClosed,
};

buffer: [4096]u8 = undefined,
socket: std.posix.socket_t,
allocator: std.mem.Allocator,
key: []const u8,

pub fn handshake(ws: WebSocket) !void {
    const encoded = secAccept(ws.key);
    const response = try std.fmt.allocPrint(ws.allocator, "HTTP/1.1 101 Switching Protocols\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Accept: {s}\r\n\r\n", .{encoded});

    try coro.io.single(.send, .{ .socket = ws.socket, .buffer = response });
}

pub fn secAccept(key: []const u8) [28]u8 {
    var h = std.crypto.hash.Sha1.init(.{});
    var buf: [20]u8 = undefined;

    h.update(key);
    h.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    h.final(&buf);

    var ret: [28]u8 = undefined;
    const encoded = std.base64.standard.Encoder.encode(&ret, &buf);
    std.debug.assert(encoded.len == ret.len);
    return ret;
}

/// Reads exactly `count` bytes from socket
fn readExact(ws: WebSocket, buf: []u8) !void {
    var total_read: usize = 0;
    while (total_read < buf.len) {
        var len: usize = 0;
        try coro.io.single(.recv, .{ .socket = ws.socket, .buffer = buf, .out_read = &len });
        total_read += len;
    }
}

pub fn readFrame(ws: WebSocket) !Frame {

    // Read first 2 bytes
    var byte1: [1]u8 = undefined;
    try ws.readExact(&byte1);
    var byte2: [1]u8 = undefined;
    try ws.readExact(&byte2);

    const fin = (byte1[0] & 0x80) != 0;
    const rsv1 = (byte1[0] & 0x40) != 0;
    const rsv2 = (byte1[0] & 0x20) != 0;
    const rsv3 = (byte1[0] & 0x10) != 0;
    const opcode = @as(Opcode, @enumFromInt(byte1[0] & 0x0F));

    const masked = (byte2[0] & 0x80) != 0;
    var payload_len: u64 = byte2[0] & 0x7F;

    var masking_key: ?[4]u8 = null;

    if (payload_len == 126) {
        var len_bytes: [2]u8 = undefined;
        try ws.readExact(&len_bytes);
        payload_len = mem.readInt(u16, &len_bytes, .big);
    } else if (payload_len == 127) {
        var len_bytes: [8]u8 = undefined;
        try ws.readExact(&len_bytes);
        payload_len = mem.readInt(u64, &len_bytes, .big);
    }

    if (masked) {
        var key: [4]u8 = undefined;
        try ws.readExact(&key);
        masking_key = key;
    }

    if (payload_len > ws.buffer.len) {
        return Error.InvalidFrame;
    }

    var buffer: [4096]u8 = undefined;

    const payload = buffer[0..payload_len];
    try ws.readExact(payload);

    if (masked) {
        if (masking_key) |key| {
            for (payload, 0..) |*byte, i| {
                byte.* ^= key[i % 4];
            }
        }
    }

    return Frame{
        .fin = fin,
        .rsv1 = rsv1,
        .rsv2 = rsv2,
        .rsv3 = rsv3,
        .opcode = opcode,
        .masked = masked,
        .payload_len = payload_len,
        .masking_key = masking_key,
        .payload = payload,
    };
}

pub fn sendFrame(ws: WebSocket, opcode: Opcode, payload: []const u8) !void {
    var header: [14]u8 = undefined;
    var header_len: usize = 2;

    header[0] = 0x80 | @as(u8, @intFromEnum(opcode));

    if (payload.len <= 125) {
        header[1] = @as(u8, @intCast(payload.len));
    } else if (payload.len <= 65535) {
        header[1] = 126;
        mem.writeInt(u16, header[2..4], @as(u16, @intCast(payload.len)), .big);
        header_len += 2;
    } else {
        header[1] = 127;
        mem.writeInt(u64, header[2..10], @as(u64, @intCast(payload.len)), .big);
        header_len += 8;
    }
    try coro.io.single(.send, .{ .socket = ws.socket, .buffer = header[0..header_len] });
    try coro.io.single(.send, .{ .socket = ws.socket, .buffer = payload });
}

pub fn close(ws: WebSocket) void {
    try coro.io.single(.close_socket, .{ .socket = ws.socket });
}

pub fn run(self: WebSocket) void {
    self.handshake() catch |err| {
        std.debug.print("Handshake failed: {}\n", .{err});
    };

    while (true) {
        const frame = self.readFrame() catch |err| {
            std.debug.print("Failed to read frame: {}\n", .{err});
            break;
        };

        switch (frame.opcode) {
            .text => {
                std.debug.print("Received text frame: {s}\n", .{frame.payload});
                self.sendFrame(.text, frame.payload) catch |err| {
                    std.debug.print("Failed to send frame: {}\n", .{err});
                    break;
                };
            },
            .binary => {
                std.debug.print("Received binary frame ({} bytes)\n", .{frame.payload.len});
                self.sendFrame(.binary, frame.payload) catch |err| {
                    std.debug.print("Failed to send frame: {}\n", .{err});
                    break;
                };
            },
            .close => {
                std.debug.print("Received close frame\n", .{});
                self.sendFrame(.close, &[0]u8{}) catch |err| {
                    std.debug.print("Failed to send frame: {}\n", .{err});
                    break;
                };
                break;
            },
            .ping => {
                std.debug.print("Received ping frame\n", .{});
                self.sendFrame(.pong, frame.payload) catch |err| {
                    std.debug.print("Failed to send frame: {}\n", .{err});
                    break;
                };
            },
            .pong => {
                std.debug.print("Received pong frame\n", .{});
            },
            else => {
                std.debug.print("Received unsupported frame opcode: {}\n", .{frame.opcode});
                self.sendFrame(.close, &[0]u8{}) catch |err| {
                    std.debug.print("Failed to send frame: {}\n", .{err});
                    break;
                };
                break;
            },
        }
    }
}

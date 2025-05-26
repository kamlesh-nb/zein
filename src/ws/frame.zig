const std = @import("std");

pub const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

pub const Frame = @This();

fin: bool,
rsv1: bool,
rsv2: bool,
rsv3: bool,
opcode: Opcode,
masked: bool,
payload_len: u64,
masking_key: ?[4]u8,
payload: []u8,

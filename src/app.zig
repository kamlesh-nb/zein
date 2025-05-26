const std = @import("std");

const aio = @import("aio");
const coro = @import("coro");

const Router = @import("router.zig").Router;
const http = @import("http");
const Request = http.Request;
const Response = http.Response;
const Status = http.Status;

const Middleware = @import("./interfaces/middleware.zig").MiddleWare;
const Handler = @import("./interfaces/handler.zig").Handler;
const WebSocket = @import("./ws/websocket.zig");

const App = @This();

server: std.posix.socket_t = undefined,
scheduler: coro.Scheduler = undefined,
router: Router = undefined,
address: std.net.Address,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, ip: anytype, port: u16) !App {
    return App{
        .router = try Router.init(allocator, "static"),
        .allocator = allocator,
        .scheduler = try coro.Scheduler.init(allocator, .{}),
        .address = std.net.Address.initIp4(ip, port),
    };
}

fn accept(self: *App) !std.posix.socket_t {
    var client_sock: std.posix.socket_t = undefined;
    try coro.io.single(.accept, .{ .socket = self.server, .out_socket = &client_sock });
    return client_sock;
}

fn process(self: *App, socket: std.posix.socket_t) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer _ = arena.deinit();

    const arena_alloc = arena.allocator();

    var req = Request.new(arena_alloc, socket) catch |e| {
        std.log.err("Failed to initialize Request: {}\n", .{e});
        return;
    };

    var res = Response.new(arena_alloc, socket) catch |e| {
        std.log.err("Failed to initialize Request: {}\n", .{e});
        return;
    };

    req.read() catch |err| {
        std.log.err("Failed to parse request: {}, \n{s}\n", .{ err, req.method.toString() });
        res.status = Status.bad_request;
        res.write("Bad Request") catch {};
        try res.send();
        return;
    };

    if (req.headers.get("sec-websocket-key")) |key| {
        const ws = WebSocket{ .socket = socket, .allocator = self.allocator, .key = key };
        _ = try self.scheduler.spawn(WebSocket.run, .{ws}, .{});
    } else {
        try self.router.handle(&req, &res);
        try res.send();
        try coro.io.single(.close_socket, .{ .socket = socket });
    }
}

pub fn use(self: *App, middleware: Middleware) !void {
    try self.router.middlewares.append(middleware);
}

pub fn useStatic(self: *App, static_path: []const u8) !void {
    try self.router.useStatic(static_path);
}

pub fn addRouteHandler(self: *App, handler: Handler) !void {
    try self.router.handlers.append(handler);
}

fn run(self: *App) !void {
    while (true) {
        const sock = try self.accept();
        _ = try self.scheduler.spawn(process, .{ self, sock }, .{});
    }
}

pub fn deinit(self: *App) void {
    coro.io.single(.close_socket, .{ .socket = self.server }) catch {
        std.log.err("Failed to close socket", .{});
    };
    self.scheduler.deinit();
    self.router.deinit();
}

pub fn listen(self: *App) !void {
    try coro.io.single(.socket, .{
        .domain = std.posix.AF.INET,
        .flags = std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC,
        .protocol = std.posix.IPPROTO.TCP,
        .out_socket = &self.server,
    });
    errdefer coro.io.single(.close_socket, .{ .socket = self.server }) catch {};

    std.posix.setsockopt(self.server, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1))) catch |err| {
        std.log.err("Could not set socket options: {s}", .{@errorName(err)});
    };

    std.posix.bind(self.server, &self.address.any, self.address.getOsSockLen()) catch |err| {
        switch (err) {
            error.AddressInUse => {
                std.log.err("Failed to bind: Address already in use (port {})", .{self.address.getPort()});
                return error.AddressAlreadyInUse;
            },
            else => |e| {
                std.log.err("Failed to bind: {s}", .{@errorName(err)});
                return e;
            },
        }
    };

    std.posix.listen(self.server, 128) catch |err| {
        std.log.err("Failed to listen: {s}", .{@errorName(err)});
    };
    std.log.info("Listening on {any}", .{self.address});

    _ = try self.scheduler.spawn(run, .{self}, .{});
    try self.scheduler.run(.wait);
}

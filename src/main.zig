const std = @import("std");
pub const App = @import("app.zig");
pub const Handler = @import("handler.zig").Handler;
pub const Middleware = @import("middleware.zig").MiddleWare;

const UserHandler = @import("./user_handler.zig").UserHandler;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    var app = try App.init(allocator, .{ 127, 0, 0, 1 }, 2369);
    try app.useStatic("static");

    var userHandler = UserHandler.new();

    try app.addRouteHandler(userHandler.handler());

    try app.listen();
}

const std = @import("std");
pub const App = @import("app.zig");
pub const Handler = @import("./interfaces/handler.zig").Handler;
pub const Middleware = @import("./interfaces/middleware.zig").MiddleWare;

const UserHandler = @import("./user_handler.zig").UserHandler;
const TestMiddleware = @import("./test_middleware.zig").TestMiddleWare;
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    var app = try App.init(allocator, .{ 127, 0, 0, 1 }, 2369);
    try app.useStatic("static");
    
    var testMiddleware = TestMiddleware.new("Hello, World!");
    try app.use(testMiddleware.middleware());

    var userHandler = UserHandler.new();

    try app.addRouteHandler(userHandler.handler());

    try app.listen();
}

const std = @import("std");
const http = @import("http");
const Request = http.Request;
const Response = http.Response;
const Method = http.Method;
const Status = http.Status;

const Handler = @import("./interfaces/handler.zig").Handler;

pub const UserHandler = struct {
    method: Method = .get,
    route: []const u8 = "/users/:id/:name/:age",

    pub fn new() UserHandler {
        return UserHandler{};
    }

    pub fn handle(ptr: *anyopaque, allocator: std.mem.Allocator, request: *Request, response: *Response) anyerror!void {
        const self: *UserHandler = @ptrCast(@alignCast(ptr));
        _ = self;
        _ = allocator;

        const id = request.params.get("id").?;
        const name = request.params.get("name").?;
        const age = request.params.get("age").?;

        try response.json(.{
            .id = id,
            .name = name,
            .age = age,
        });
    }

    pub fn handler(self: *UserHandler) Handler {
        return Handler{
            .ptr = self,
            .method = self.method,
            .route = self.route,
            .handleFn = handle,
        };
    }
};

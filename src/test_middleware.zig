const std = @import("std");
const http = @import("http");
const Request = http.Request;
const Response = http.Response;

const MiddleWare = @import("./interfaces/middleware.zig").MiddleWare;

pub const TestMiddleWare = struct {
    data: []const u8,

    pub fn new(data: []const u8) TestMiddleWare {
        return TestMiddleWare{ .data = data };
    }

    pub fn execute(ptr: *anyopaque, allocator: std.mem.Allocator, request: *Request, response: *Response) anyerror!void {
        const self: *TestMiddleWare = @ptrCast(@alignCast(ptr));
        _ = allocator;
        _= response;
        std.debug.print("path: {s}", .{request.path});
        std.debug.print("\ndata: {s}\n", .{self.data});
    }

    pub fn middleware(self: *TestMiddleWare) MiddleWare {
        return MiddleWare{
            .ptr = self,
            .executeFn = execute,
        };
    }
};

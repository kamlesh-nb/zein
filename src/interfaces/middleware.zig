const std = @import("std");
const http = @import("http");
const Request = http.Request;
const Response = http.Response;

pub const MiddleWare = struct {
    ptr: *anyopaque,
    executeFn: *const fn (ptr: *anyopaque, arena: std.mem.Allocator, request: *Request, response: *Response) anyerror!void,

    pub fn execute(self: MiddleWare, arena: std.mem.Allocator, request: *Request, response: *Response) anyerror!void {
        return self.executeFn(self.ptr, arena, request, response);
    }
};

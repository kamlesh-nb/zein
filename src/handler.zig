const std = @import("std");
const http = @import("http");
const Request = http.Request;
const Response = http.Response;
const Method = http.Method;

pub const Handler = struct {
    ptr: *anyopaque,
    method: Method,
    route: []const u8,
    handleFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, request: *Request, response: *Response) anyerror!void,

    pub fn handle(self: Handler, allocator: std.mem.Allocator, request: *Request, response: *Response) anyerror!void {
        return self.handleFn(self.ptr, allocator, request, response);
    }
};

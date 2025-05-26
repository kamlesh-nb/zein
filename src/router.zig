const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const aio = @import("aio");

const Handler = @import("./interfaces/handler.zig").Handler;
const Middleware = @import("./interfaces/middleware.zig").MiddleWare;

const HandlerList = @import("handlers.zig").HandlerList;
const MiddleWareList = @import("middlewares.zig").MiddleWareList;

const http = @import("http");
const Request = http.Request;
const Response = http.Response;
const Method = http.Method;
const Status = http.Status;
const Mime = http.Mime;

pub const Routes = struct {};

pub const Router = struct {
    allocator: std.mem.Allocator,
    handlers: HandlerList, //std.ArrayList(Handler),
    middlewares: MiddleWareList, //std.ArrayList(Middleware),
    static_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, dir: []const u8) !Router {
        return Router{
            .allocator = allocator,
            .handlers = HandlerList.init(allocator), //std.ArrayList(Handler).init(allocator),
            .middlewares = MiddleWareList.init(allocator), //std.ArrayList(Middleware).init(allocator),
            .static_dir = dir,
        };
    }

    pub fn deinit(self: *Router) void {
        self.handlers.deinit();
        self.middlewares.deinit();
        if (self.static_dir) |dir| {
            self.allocator.free(dir);
        }
    }

    pub fn useStatic(self: *Router, static_path: []const u8) !void {
        const sp = try self.allocator.dupe(u8, static_path);
        self.static_dir = sp;
    }

    pub fn use(self: *Router, middleware: Middleware) !void {
        try self.middlewares.append(middleware);
    }

    pub fn add(self: *Router, handler: Handler) !void {
        try self.handlers.append(handler);
    }

    fn isApiRequest(self: *Router, request: *Request) bool {
        _ = self;
        if (std.mem.startsWith(u8, request.path, "/api") or std.mem.startsWith(u8, request.path, "/htmx")) {
            return true;
        } else {
            return false;
        }
    }

    fn matchRoute(self: *Router, method: Method, route: []const u8) ?*Handler {
        // for (self.handlers.items) |handler| {
        //     if ((handler.method == method) and (std.mem.eql(u8, handler.route, route))) {
        //         return handler;
        //     }
        // }
        var hit = self.handlers.iterator();
        while (hit.next()) |handler| {
            if ((handler.method == method) and (std.mem.eql(u8, handler.route, route))) {
                return handler;
            }
        }
        return null;
    }

    pub fn handle(self: *Router, req: *Request, res: *Response) !void {
        // for (self.middlewares.items) |mw| {
        //     try mw.execute(self.allocator, req, res);
        // }
        var mit = self.middlewares.iterator();
        while (mit.next()) |mw| {
            try mw.execute(self.allocator, req, res);
        }

        const isApi = self.isApiRequest(req);
        if (isApi) {
            if (self.matchRoute(req.method, req.route.items)) |handler| {
                try handler.handle(self.allocator, req, res);
            } else {
                res.status = .not_found;
            }
        } else {
            var static_path = std.ArrayList(u8).init(self.allocator);
            if (std.mem.eql(u8, req.path, "/")) {
                try static_path.appendSlice("/index.html");
            } else {
                try static_path.appendSlice(req.path);
            }

            const full_path = try fs.path.join(self.allocator, &[_][]const u8{ self.static_dir, static_path.items[1..] });
            defer self.allocator.free(full_path);

            if (fs.cwd().openFile(full_path, .{})) |file| {
                defer file.close();

                const stat = try file.stat();
                const ext = fs.path.extension(full_path);
                if (Mime.fromExtension(ext[1..ext.len])) |mime| {
                    try res.setHeader("Content-Type", mime.toHttpString());
                }
                try res.setHeader("Connection", "Close");

                res.status = Status.ok;
                const buff = try file.readToEndAlloc(self.allocator, stat.size);

                try res.body.buffer.appendSlice(buff);
            } else |e| {
                if (e == error.FileNotFound) {
                    res.status = .not_found;
                } else if (e == error.AccessDenied) {
                    res.status = .forbidden;
                } else {
                    res.status = .internal_server_error;
                }
            }
        }
    }
};

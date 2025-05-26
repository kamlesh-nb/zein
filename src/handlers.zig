const std = @import("std");
const Handler = @import("./interfaces/handler.zig").Handler;
const http = @import("http");
const Method = http.Method;

pub const HandlerNode = struct {
    data: Handler,
    next: ?*HandlerNode,

    pub fn init(allocator: std.mem.Allocator, handler: Handler) !*HandlerNode {
        const node = try allocator.create(HandlerNode);
        node.* = .{
            .data = handler,
            .next = null,
        };
        return node;
    }

    pub fn deinit(self: *HandlerNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub const HandlerList = struct {
    head: ?*HandlerNode,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HandlerList {
        return .{
            .head = null,
            .allocator = allocator,
        };
    }

    pub fn append(self: *HandlerList, handler: Handler) !void {
        const new_node = try HandlerNode.init(self.allocator, handler);

        if (self.head == null) {
            self.head = new_node;
            return;
        }

        var current = self.head;
        while (current.?.next) |next| {
            current = next;
        }
        current.?.next = new_node;
    }

    pub fn remove(self: *HandlerList, method: Method, route: []const u8) void {
        var current = self.head;
        var prev: ?*HandlerNode = null;

        while (current) |node| {
            if (node.data.method == method and std.mem.eql(u8, node.data.route, route)) {
                if (prev) |p| {
                    p.next = node.next;
                } else {
                    self.head = node.next;
                }
                node.deinit(self.allocator);
                return;
            }
            prev = current;
            current = node.next;
        }
    }

    pub fn find(self: *HandlerList, method: Method, route: []const u8) ?*Handler {
        var current = self.head;
        while (current) |node| {
            if (node.data.method == method and std.mem.eql(u8, node.data.route, route)) {
                return &node.data;
            }
            current = node.next;
        }
        return null;
    }

    pub fn deinit(self: *HandlerList) void {
        var current = self.head;
        while (current) |node| {
            const next = node.next;
            node.deinit(self.allocator);
            current = next;
        }
        self.head = null;
    }

    pub fn length(self: *HandlerList) usize {
        var count: usize = 0;
        var current = self.head;
        while (current) |node| {
            count += 1;
            current = node.next;
        }
        return count;
    }

    pub const Iterator = struct {
        current: ?*HandlerNode,

        pub fn next(self: *Iterator) ?*Handler {
            if (self.current) |node| {
                self.current = node.next;
                return &node.data;
            }
            return null;
        }

        // Reset iterator to the beginning (requires head of the list)
        pub fn reset(self: *Iterator, head: ?*HandlerNode) void {
            self.current = head;
        }
    };

    pub fn iterator(self: *HandlerList) Iterator {
        return Iterator{
            .current = self.head,
        };
    }
};

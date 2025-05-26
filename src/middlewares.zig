const std = @import("std");
const MiddleWare = @import("./interfaces/middleware.zig").MiddleWare;
const http = @import("http");
const Request = http.Request;
const Response = http.Response;

pub const MiddleWareNode = struct {
    data: MiddleWare,
    next: ?*MiddleWareNode,

    pub fn init(allocator: std.mem.Allocator, middleware: MiddleWare) !*MiddleWareNode {
        const node = try allocator.create(MiddleWareNode);
        node.* = .{
            .data = middleware,
            .next = null,
        };
        return node;
    }

    pub fn deinit(self: *MiddleWareNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub const MiddleWareList = struct {
    head: ?*MiddleWareNode,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MiddleWareList {
        return .{
            .head = null,
            .allocator = allocator,
        };
    }

    // Append a new middleware to the end of the list
    pub fn append(self: *MiddleWareList, middleware: MiddleWare) !void {
        const new_node = try MiddleWareNode.init(self.allocator, middleware);

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

    pub fn deinit(self: *MiddleWareList) void {
        var current = self.head;
        while (current) |node| {
            const next = node.next;
            node.deinit(self.allocator);
            current = next;
        }
        self.head = null;
    }

    pub fn length(self: *MiddleWareList) usize {
        var count: usize = 0;
        var current = self.head;
        while (current) |node| {
            count += 1;
            current = node.next;
        }
        return count;
    }

    pub const Iterator = struct {
        current: ?*MiddleWareNode,

        pub fn next(self: *Iterator) ?*MiddleWare {
            if (self.current) |node| {
                self.current = node.next;
                return &node.data;
            }
            return null;
        }

        // Reset iterator to the beginning (requires head of the list)
        pub fn reset(self: *Iterator, head: ?*MiddleWareNode) void {
            self.current = head;
        }
    };

    pub fn iterator(self: *MiddleWareList) Iterator {
        return Iterator{
            .current = self.head,
        };
    }
};

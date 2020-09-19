const std = @import("std");
const warn = std.debug.warn;
const gallocator = std.heap.page_allocator;

pub fn Graph(comptime T: type) type {
    return struct {
        N: usize,
        root: ?*Node,
        vertices: ?std.StringHashMap(*Node),
        graph: ?std.AutoHashMap(*Node, std.ArrayList(*Node)),
        allocator: *std.mem.Allocator,
        visited: ?std.StringHashMap(i32),
        stack: ?std.ArrayList(*Node),

        const Self = @This();

        pub const Node = struct {
            name: []const u8,
            data: T,

            pub fn init(n: []const u8, d: T) Node {
                return Node{
                    .name = n,
                    .data = d
                };
            }
        };

        pub fn init(alloc: *std.mem.Allocator) Self {
            return Self{
                .N = 0,
                .root = null,
                .vertices = null,
                .graph = null,
                .visited = null,
                .stack = null,
                .allocator = alloc
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.graph.?.entries) |entry| {
                if (entry.used == true) {
                    self.allocator.destroy(entry.kv.key);
                    for (entry.kv.value.items) |v| {
                        self.allocator.destroy(v);
                    }
                }
            }
            self.graph.?.deinit();

            for (self.vertices.?.entries) |entry| {
                if (entry.used == true) {
                    self.allocator.destroy(entry.kv.value);
                }
            }
            self.vertices.?.deinit();
            
            self.N = 0;
        }

        pub fn addVertex(self: *Self, n: []const u8, d: T) !void {
            if (self.root == null) {
                var rt = try self.allocator.create(Node);
                errdefer self.allocator.destroy(rt);
                rt.* = Node.init(n, d);
                
                self.root = rt;
                self.vertices = std.StringHashMap(*Node).init(self.allocator);
                _ = try self.vertices.?.put(rt.name, rt);

                self.graph = std.AutoHashMap(*Node, std.ArrayList(*Node)).init(self.allocator);
                _ = try self.graph.?.put(rt, std.ArrayList(*Node).init(self.allocator));

                self.N += 1;
                return;
            }

            if (self.vertices.?.contains(n) == false) {
                var node = try self.allocator.create(Node);
                errdefer self.allocator.destroy(node);
                node.* = Node.init(n, d);

                _ = try self.vertices.?.put(node.name, node);
                _ = try self.graph.?.put(node, std.ArrayList(*Node).init(self.allocator));
            }

            self.N += 1;
        }

        pub fn addEdge(self: *Self, n1: []const u8, d1: T, n2: []const u8, d2: T) !void {
            if (self.vertices == null or self.vertices.?.contains(n1) == false ){
                try self.addVertex(n1, d1);
            }

            if (self.vertices.?.contains(n2) == false){
                try self.addVertex(n2, d2);
            }

            var node1: *Node = self.vertices.?.getValue(n1).?;
            var node2: *Node = self.vertices.?.getValue(n2).?;

            var arr1: std.ArrayList(*Node) = self.graph.?.getValue(node1).?;
            var arr2: std.ArrayList(*Node) = self.graph.?.getValue(node2).?;
            
            try arr1.append(node2);
            try arr2.append(node1);

            _ = try self.graph.?.put(node1, arr1);
            _ = try self.graph.?.put(node2, arr2);

        }

        pub fn print(self: *Self) void {
            warn("\r\n", .{});
            warn("Size: {}\r\n", .{self.N});
            warn("\r\n", .{});
            warn("Root: {}\r\n", .{self.root});
            warn("\r\n", .{});
            warn("Vertices:\r\n", .{});
            for (self.vertices.?.entries) |entry| {
                if (entry.used == true) {
                    warn("\r\n{}\r\n", .{entry.kv.key});
                }
            }
            warn("\r\n", .{});
            warn("Graph:\r\n", .{});
            for (self.graph.?.entries) |entry| {
                if (entry.used == true) {
                    warn("\r\nConnections: {}  =>", .{entry.kv.key});
                    for (entry.kv.value.items) |v, i| {
                        warn("  {}  =>", .{v.*});
                    }
                    warn("|| \r\n", .{});
                }
            }
            warn("\r\n", .{});
        }

        fn topoDriver(self: *Self, node: []const u8) !bool {
            // In the process of visiting this vertex, we reach the same vertex again. 
            // Return to stop the process. (#cond1)
            if (self.visited.?.getValue(node).? == 1) {
                return false;
            } 

            // Finished visiting this vertex, it is now marked black. (#cond2)
            if (self.visited.?.getValue(node).? == 2) {
                return true;
            }

            // Color the node grey, indicating that it is being processed, and initiate a loop
            // to visit all its neighbors. If we reach the same vertex again, return (#cond1)
            _ = try self.visited.?.put(node, 1);
            
            var nodePtr: *Node = self.vertices.?.getValue(node).?;
            var neighbors: std.ArrayList(*Node) = self.graph.?.getValue(nodePtr).?;
            for (neighbors.items) |n| {
                // warn("\r\n nbhr: {} ", .{n});
                if (self.visited.?.getValue(n.name).? == 0 ) {
                    var check: bool = self.topoDriver(n.name) catch unreachable;
                    if (check == false) {
                        return false;
                    }
                }
            }

            // Finish processing the current node and mark it black.
            _ = try self.visited.?.put(node, 2);
            
            // Add node to stack of visited nodes.
            try self.stack.?.append(nodePtr);
            // warn("\r\n reach {} ", .{nodePtr});

            return true;

        }

        pub fn topoSort(self: *Self) !std.ArrayList(*Node) {
            self.visited = std.StringHashMap(i32).init(self.allocator);
            defer self.visited.?.deinit();

            self.stack = std.ArrayList(*Node).init(self.allocator);
            defer self.stack.?.deinit();

            var result = std.ArrayList(*Node).init(self.allocator);

            // Initially, color all the nodes white, to mark them unvisited.
            for (self.vertices.?.entries) |entry| {
                if (entry.used == true) {
                    _ = try self.visited.?.put(entry.kv.key, 0);
                }
            }

            for (self.vertices.?.entries) |entry| {
                if (entry.used == true) {
                    if (self.visited.?.getValue(entry.kv.key).? == 0 ) {
                        var check: bool = self.topoDriver(entry.kv.key) catch unreachable;
                        if (check == false) {
                            for (self.stack.?.items) |n| {
                                try result.append(n);
                            }
                            return result;
                        }
                    }
                }
            }

            for (self.stack.?.items) |n| {
                try result.append(n);
            }
            return result;
        }

        pub fn sccFind(self: *Self){

        }

        pub fn dfs(self: *Self) !std.ArrayList(*Node) {

        }

        pub fn bfs(self: *Self) !std.ArrayList(*Node) {
            var queue = std.ArrayList(*Node).init(self.allocator);
            defer queue.deinit();

        }

        pub fn kruskal(self: *Self) !std.ArrayList(*Node) {

        }

        pub fn prim(self: *Self) !std.ArrayList(*Node) {

        }

        pub fn dijiksta(self: *Self) !std.ArrayList(*Node) {

        }

    };
}

pub fn main() anyerror!void {
    warn("\r\n", .{});
    var graph = Graph(i32).init(gallocator);
    defer graph.deinit();

    try graph.addEdge("A", 10, "B", 20);
    try graph.addEdge("B", 20, "C", 40);
    try graph.addEdge("C", 110, "A", 10);
    try graph.addEdge("A", 10, "A", 10);
    graph.print();

    warn("\r\n", .{});
    warn("\r\nTopoSort: ", .{});
    var res = try graph.topoSort();
    defer res.deinit();

    for (res.items) |n| {
        warn("\r\n stack: {} ", .{n});
    }
    warn("\r\n", .{});
    
}

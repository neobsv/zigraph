const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const gallocator = std.heap.page_allocator;

pub fn Graph(comptime T: type) type {
    return struct {
        N: usize,
        connected: usize,
        root: ?*Node,
        vertices: ?std.StringHashMap(*Node),
        graph: ?std.AutoHashMap(*Node, std.ArrayList(*Edge)),
        allocator: *std.mem.Allocator,

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

        pub const Edge = struct {
            node: *Node,
            weight: u32,

            pub fn init(n1: *Node, w: u32) Edge {
                return Edge {
                    .node = n1,
                    .weight = w
                };
            }
        };

        pub fn init(alloc: *std.mem.Allocator) Self {
            return Self{
                .N = 0,
                .connected = 0,
                .root = null,
                .vertices = null,
                .graph = null,
                .allocator = alloc
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.graph.?.entries) |entry| {
                if (entry.used == true) {
                    self.allocator.destroy(entry.kv.key);
                    for (entry.kv.value.items) |v| {
                        self.allocator.destroy(v.node);
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

                self.graph = std.AutoHashMap(*Node, std.ArrayList(*Edge)).init(self.allocator);
                _ = try self.graph.?.put(rt, std.ArrayList(*Edge).init(self.allocator));

                self.N += 1;
                return;
            }

            if (self.vertices.?.contains(n) == false) {
                var node = try self.allocator.create(Node);
                errdefer self.allocator.destroy(node);
                node.* = Node.init(n, d);

                _ = try self.vertices.?.put(node.name, node);
                _ = try self.graph.?.put(node, std.ArrayList(*Edge).init(self.allocator));
            }

            self.N += 1;
        }

        pub fn addEdge(self: *Self, n1: []const u8, d1: T, n2: []const u8, d2: T, w: u32) !void {
            if (self.vertices == null or self.vertices.?.contains(n1) == false ){
                try self.addVertex(n1, d1);
            }

            if (self.vertices.?.contains(n2) == false){
                try self.addVertex(n2, d2);
            }

            var node1: *Node = self.vertices.?.getValue(n1).?;
            var node2: *Node = self.vertices.?.getValue(n2).?;

            var arr1: std.ArrayList(*Edge) = self.graph.?.getValue(node1).?;
            var arr2: std.ArrayList(*Edge) = self.graph.?.getValue(node2).?;
            
            var edge1 = try self.allocator.create(Edge);
            errdefer self.allocator.destroy(edge1);
            edge1.* = Edge.init(node1, w);

            var edge2 = try self.allocator.create(Edge);
            errdefer self.allocator.destroy(edge2);
            edge2.* = Edge.init(node2, w);

            try arr1.append(edge2);
            try arr2.append(edge1);

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

        fn topoDriver(self: *Self, node: []const u8, visited: *std.StringHashMap(i32), stack: *std.ArrayList(*Node)) !bool {
            // In the process of visiting this vertex, we reach the same vertex again.
            // Return to stop the process. (#cond1)
            if (visited.getValue(node).? == 1) {
                return false;
            } 

            // Finished visiting this vertex, it is now marked 2. (#cond2)
            if (visited.getValue(node).? == 2) {
                return true;
            }

            // Color the node 1, indicating that it is being processed, and initiate a loop
            // to visit all its neighbors. If we reach the same vertex again, return (#cond1)
            _ = try visited.put(node, 1);
            
            var nodePtr: *Node = self.vertices.?.getValue(node).?;
            var neighbors: std.ArrayList(*Edge) = self.graph.?.getValue(nodePtr).?;
            for (neighbors.items) |n| {
                // warn("\r\n nbhr: {} ", .{n});
                if (visited.getValue(n.node.name).? == 0 ) {
                    var check: bool = self.topoDriver(n.node.name, visited, stack) catch unreachable;
                    if (check == false) {
                        return false;
                    }
                }
            }

            // Finish processing the current node and mark it 2.
            _ = try visited.put(node, 2);
            
            // Add node to stack of visited nodes.
            try stack.append(nodePtr);
            // warn("\r\n reach {} ", .{nodePtr});

            return true;

        }

        pub fn topoSort(self: *Self) !std.ArrayList(*Node) {
            var visited = std.StringHashMap(i32).init(self.allocator);
            defer visited.deinit();

            var stack = std.ArrayList(*Node).init(self.allocator);
            defer stack.deinit();

            var result = std.ArrayList(*Node).init(self.allocator);

            // Initially, color all the nodes 0, to mark them unvisited.
            for (self.vertices.?.entries) |entry| {
                if (entry.used == true) {
                    _ = try visited.put(entry.kv.key, 0);
                }
            }

            for (self.vertices.?.entries) |entry| {
                if (entry.used == true) {
                    if (visited.getValue(entry.kv.key).? == 0 ) {
                        var check: bool = self.topoDriver(entry.kv.key, &visited, &stack) catch unreachable;
                        if (check == false) {
                            for (stack.items) |n| {
                                try result.append(n);
                            }
                            return result;
                        }
                        self.connected += 1;
                    }
                }
            }

            for (stack.items) |n| {
                try result.append(n);
            }
            return result;
        }

        pub fn dfs(self: *Self) !std.ArrayList(*Node) {
            var visited = std.StringHashMap(i32).init(self.allocator);
            defer visited.deinit();

            var result = std.ArrayList(*Node).init(self.allocator);

            // Initially, color all the nodes 0, to mark them unvisited.
            for (self.vertices.?.entries) |entry| {
                if (entry.used == true) {
                    _ = try visited.put(entry.kv.key, 0);
                }
            }

            var stack = std.ArrayList(*Node).init(self.allocator);
            defer stack.deinit();

            try stack.append(self.root.?);

            while (stack.items.len > 0) {
                var current: *Node = stack.pop();

                var neighbors: std.ArrayList(*Edge) = self.graph.?.getValue(current).?;
                for (neighbors.items) |n| {
                    // warn("\r\n nbhr: {} ", .{n});
                    if (visited.getValue(n.node.name).? == 0 ) {
                        try stack.append(n.node);
                        _ = try visited.put(n.node.name, 1);
                        try result.append(n.node);
                    }
                }
            }
            
            return result;
        }

        pub fn bfs(self: *Self) !std.ArrayList(*Node) {
            var visited = std.StringHashMap(i32).init(self.allocator);
            defer visited.deinit();

            var result = std.ArrayList(*Node).init(self.allocator);

            // Initially, color all the nodes 0, to mark them unvisited.
            for (self.vertices.?.entries) |entry| {
                if (entry.used == true) {
                    _ = try visited.put(entry.kv.key, 0);
                }
            }

            var qu = std.ArrayList(*Node).init(self.allocator);
            defer qu.deinit();

            try qu.append(self.root.?);

            while (qu.items.len > 0) {
                var current: *Node = qu.orderedRemove(0);

                var neighbors: std.ArrayList(*Edge) = self.graph.?.getValue(current).?;
                for (neighbors.items) |n| {
                    // warn("\r\n nbhr: {} ", .{n});
                    if (visited.getValue(n.node.name).? == 0 ) {
                        try qu.append(n.node);
                        _ = try visited.put(n.node.name, 1);
                        try result.append(n.node);
                    }
                }
            }
            
            return result;
        }

        // pub fn kruskal(self: *Self) !std.ArrayList(*Node) {

        // }

        // pub fn prim(self: *Self) !std.ArrayList(*Node) {

        // }

        pub const Element = struct {
            node: []const u8,
            distance: i32,
        };
        pub fn minCompare(a: Element, b: Element) bool {
            return a.distance < b.distance;
        }

        pub fn dijikstra(self: *Self, src: []const u8, dst: []const u8) !std.ArrayList(Element) {

            var result = std.ArrayList(Element).init(self.allocator);

            if ( (self.vertices.?.contains(src) == false) or (self.vertices.?.contains(dst) == false) ){
                return result;
            }

            var source: *Node = self.vertices.?.getValue(src).?;

            var pq = std.PriorityQueue(Element).init(self.allocator, minCompare);
            defer pq.deinit();

            var visited = std.StringHashMap(i32).init(self.allocator);
            defer visited.deinit();

            var distances = std.StringHashMap(i32).init(self.allocator);
            defer distances.deinit();

            // Initially, push all the nodes into the invisited hashmap with a distance of infinity (-1).
            for (self.vertices.?.entries) |entry| {
                if (entry.used == true and !mem.eql(u8, source.name, entry.kv.key)) {
                    _ = try distances.put(entry.kv.key, 9999);
                    try pq.add(Element{.node= entry.kv.key, .distance= 9999});
                }
            }

            _ = try distances.put(src, 0);
            try pq.add(Element{.node= source.name, .distance= 0});
            
            while (pq.count() > 0) {
                var current: Element = pq.remove();

                if (mem.eql(u8, current.node, dst)) {
                    break;
                }

                if (!visited.contains(current.node)) {
                    var nodePtr: *Node = self.vertices.?.getValue(current.node).?;
                    var neighbors: std.ArrayList(*Edge) = self.graph.?.getValue(nodePtr).?;

                    for (neighbors.items) |n| {
                        // Update the distance values from all neighbors, to the current node
                        // and obtain the shortest distance to the current node from all of its neighbors.
                        var best_dist = distances.getValue(n.node.name).?;
                        var n_dist = @intCast(i32, current.distance + @intCast(i32, n.weight));

                        // warn("\r\n n1 {} nbhr {} ndist {} best {}", .{current.node, n.node.name, n_dist, best_dist});
                        if (n_dist < best_dist) {
                            _ = try distances.put(n.node.name, n_dist);
                        
                            // Update distance in the priority queue -> decrease priority
                            var modIndex: usize = 0;
                            for (pq.items) |item, i| {
                                if (mem.eql(u8, item.node, n.node.name)) {
                                    modIndex = i;
                                    break;
                                }
                            }
                            _ = pq.removeIndex(modIndex);
                            try pq.add(Element{.node= n.node.name, .distance= n_dist});
                        }
                    }

                    // After updating all the distances to all neighbors, get the 
                    // best leading edge from the closest neighbor to this node. Mark that
                    // distance as the best distance to this node, and add it to the results.
                    var best = distances.getValue(current.node).?;
                    try result.append(Element{.node= current.node, .distance= best});
                    _ = try visited.put(current.node, 1);                
                }

            }

            return result;
        }

        // pub fn tarjan(self: *Self){

        // }

    };
}



pub fn main() anyerror!void {

    var graph = Graph(i32).init(gallocator);
    defer graph.deinit();

    try graph.addEdge("A", 10, "B", 20, 1);
    try graph.addEdge("B", 20, "C", 40, 2);
    try graph.addEdge("C", 110, "A", 10, 3);
    try graph.addEdge("A", 10, "A", 10, 0);
    graph.print();

    warn("\r\nTopoSort: ", .{});
    var res = try graph.topoSort();
    defer res.deinit();

    for (res.items) |n| {
        warn("\r\n stack: {} ", .{n});
    }
    warn("\r\n", .{});

    warn("\r\nConnected components: {}", .{graph.connected});

    warn("\r\n", .{});
    warn("\r\nBFS: ", .{});
    var res1 = try graph.bfs();
    defer res1.deinit();

    for (res1.items) |n| {
        warn("\r\n bfs result: {} ", .{n});
    }
    warn("\r\n", .{});

    warn("\r\n", .{});
    warn("\r\nDFS: ", .{});
    var res2 = try graph.dfs();
    defer res2.deinit();

    for (res2.items) |n| {
        warn("\r\n dfs result: {} ", .{n});
    }
    warn("\r\n", .{});


    // Graph with no self loops for dijiksta.
    var graph2 = Graph(i32).init(gallocator);
    defer graph2.deinit();

    try graph2.addEdge("A", 1, "B", 1, 1);
    try graph2.addEdge("B", 1, "C", 1, 2);
    try graph2.addEdge("C", 1, "D", 1, 5);
    try graph2.addEdge("D", 1, "B", 1, 4);
    graph2.print();

    warn("\r\n", .{});
    warn("\r\nDijikstra: ", .{});
    var res3 = try graph2.dijikstra("A", "D");
    defer res3.deinit();

    for (res3.items) |n| {
        warn("\r\n dijikstra: {} ", .{n});
    }
    warn("\r\n", .{});
    
}

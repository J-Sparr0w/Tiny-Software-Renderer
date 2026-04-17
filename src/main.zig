const std = @import("std");
const Phoenix = @import("Phoenix");


const ColorFormat = enum(u3){
    grayscale = 1 ,
    rgb = 3,
    rgba = 4,
};

const TGAColor = union(ColorFormat){
    grayscale: [1]u8,
    rgb: [3]u8,
    rgba: [4]u8,

    const Self = @This();

    pub fn bytesPerPixel(self: Self) usize{
        switch(self){
            .grayscale =>  return 1,
            .rgb =>  return 3,
            .rgba =>  return 4,
        }
    }

    pub fn toGrayscale(intensity: u8) Self {
        return .{
            .rgb = u8[1]{intensity}
        };
    }

    pub fn toRgb(colors: [3]u8) Self {
        return .{
            .rgb = colors
        };
    }

    pub fn toRgba(colors: [4]u8) Self {
        return .{
            .rgba = colors
        };
    }

    pub fn to_slice(self: Self) [] const u8{
        return switch(self) {
            .grayscale => |arr|  arr[0..],
            .rgb => |arr|  arr[0..],
            .rgba => |arr|  arr[0..]
        };
    }

};

const white: TGAColor = TGAColor.toRgba(.{ 255, 255, 255, 255 }); // attention, BGRA order
const green: TGAColor = TGAColor.toRgba(.{ 0, 255, 0, 255 });
const red: TGAColor = TGAColor.toRgba(.{ 0, 0, 255, 255 });
const blue: TGAColor = TGAColor.toRgba(.{ 255, 128, 64, 255 });
const yellow: TGAColor = TGAColor.toRgba(.{ 0, 200, 255, 255 });

// Image Type Field
   //  0  -  No image data included.
   //  1  -  Uncompressed, color-mapped images.
   //  2  -  Uncompressed, RGB images.
   //  3  -  Uncompressed, black and white images.
   //  9  -  Runlength encoded color-mapped images.
   // 10  -  Runlength encoded RGB images.
   // 11  -  Compressed, black and white images.
   // 32  -  Compressed color-mapped data, using Huffman, Delta, and
   //        runlength encoding.
   // 33  -  Compressed color-mapped data, using Huffman, Delta, and
   //        runlength encoding.  4-pass quadtree-type process.

const ImageDataType = enum(u8){
    NoImage = 0,
    UncompresedColorMapped = 1,
    UncompresedRgb = 2,
    UncompresedGrayscale = 3,
    RleColorMapped = 9,
    RleRgb = 10,
    CompressedGrayscale = 11,
    HuffmanDeltaRleColorMapped = 32,
    HuffmanDeltaRleQuadTreeColorMapped = 33,
};

const TGAHeader = extern struct{
    id_length: u8 = 0,
    colour_map_type: u8 = 0,
    image_type: ImageDataType = .UncompresedRgb,
    colour_map_origin: u16  align(1) = 0,
    colour_map_length:u16 align(1) = 0,
    colour_map_depth: u8 = 0,
    x_origin: u16 align(1) = 0,
    y_origin: u16 align(1) = 0,
    width: u16 align(1) = 64,
    height: u16 align(1) = 64,
    bits_per_pixel: u8 align(1) = 32, // 24 or 32
    image_descriptor: u8 align(1) = 0,
};



const TGAImage = struct  {

    allocator: std.mem.Allocator,
    data: std.ArrayList(u8),
    // bytes_per_pixel
    bpp: ColorFormat,
    header: TGAHeader,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, image_format: ColorFormat,w: u16, h: u16) !Self{
        var data: std.ArrayList(u8) = try .initCapacity(allocator, w*h*@intFromEnum(image_format));

        data.expandToCapacity();

        @memset(data.items, 0);
        var i: usize = 3;
        while(i<data.items.len) : (i+=4){
            data.items[i] = 255;
        }

        // std.log.debug("bpp<3 = {}", .{4 << 3});

        return .{
            .allocator = allocator,
            .data = data,
            .bpp = image_format,
            .header = TGAHeader{
                .width =  w,
                .height = h,
            }
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit(self.allocator);
    }

    pub fn set(self: *Self, x: u32, y: u32, color: TGAColor) !void{

        const w = self.width();
        const h = self.height();

        if ((x < 0) or ( y<0 ) or ( x >= w) or ( y >= h )) return;

        const start = (x+y*w)*@intFromEnum(self.bpp);

        const color_slice = color.to_slice();
        std.log.debug("color: {}", .{color});
        @memcpy(self.data.items[start..start + color.bytesPerPixel()], color_slice);
    }

    pub fn write_tga_file(self: Self, file_name: [] const u8) !void {
        const file = try std.fs.cwd().createFile(file_name, .{});
        defer file.close();
        const header: [18]u8 = @bitCast(self.header);
        const data: [] const u8 = self.data.items;
        const developer_area  = [_]u8{0}**4;
        const extension_area  = [_]u8{0}**4;
        const footer =  [18]u8{'T','R','U','E','V','I','S','I','O','N','-','X','F','I','L','E','.',0};

        std.log.debug("data: {any}", .{data});
        // for (data,0..) |item,i| {
        //     if(item!=0){
        //         std.log.debug("item: {d} at i: {d}", .{item, i});
        //     }
        // }

        try file.writeAll(header[0..]);
        try file.writeAll(data);
        try file.writeAll(&developer_area);
        try file.writeAll(&extension_area);
        try file.writeAll(&footer);

        std.log.debug("Written to file: {s}",.{file_name});

        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = try std.process.getCwd(&buf);

        std.debug.print("cwd: {s}\n", .{cwd});
    }

    pub fn width(self: Self) u16 {
        return self.header.width;
    }

    pub fn height(self: Self) u16 {
        return self.header.height;
    }

//     void flip_horizontally();
//     void flip_vertically();
//     TGAColor get(const int x, const int y) const;
//     void set(const int x, const int y, const TGAColor &c);
//     int width()  const;
//     int height() const;
// private:
//     bool   load_rle_data(std::ifstream &in);
//     bool unload_rle_data(std::ofstream &out) const;
};

pub fn f(x: u32) f32 {
    return    @floatFromInt(x);
}

pub fn draw_line_first(ax: u32, ay: u32, bx: u32, by: u32, framebuffer: *TGAImage) void{

    const step = 0.05;
    var t: f32 = 0.0;
    while (t<1.0) : (t+=step){
        const x: u32 = @intFromFloat(f(ax) + t*(f(bx) - f(ax)) );
        const y: u32 = @intFromFloat(f(ay) + t*(f(by) - f(ay)) );

        try framebuffer.set(x, y, blue);
    }

}





pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("size of header: {}\n", .{@sizeOf(TGAHeader)});
    std.debug.print("align of header: {}\n", .{@alignOf(TGAHeader)});
    std.debug.print("size of color: {}\n", .{@sizeOf(TGAColor)});
    std.debug.print("align of color: {}\n", .{@alignOf(TGAColor)});
    std.debug.print("align of color: {}\n", .{TGAHeader{.width = 500}});

    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("THERE IS MEMORY LEAKS");
    }

    var framebuffer = try TGAImage.init(allocator, ColorFormat.rgba, 64, 64);
    defer framebuffer.deinit();

    const ax =  7;
    const ay =  3;

    const bx = 12;
    const by = 37;

    const cx = 62;
    const cy = 53;

    draw_line_first(ax, ay, bx, by, &framebuffer);
    draw_line_first(ax, ay, cx, cy, &framebuffer);
    draw_line_first(bx, by, cx, cy, &framebuffer);

    try framebuffer.set(ax, ay, red);
    try framebuffer.set(bx, by, green);
    try framebuffer.set(cx, cy, yellow);

    try framebuffer.write_tga_file("output.tga");

    try Phoenix.bufferedPrint();
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

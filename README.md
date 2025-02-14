# DoubleSlice

Startup Time Allocated Lists for Zig

## Running Tests

`zig build --watch test  -Doptimize=ReleaseSafe`

## Installing the Library


1. Declare zBench as a dependency in `build.zig.zon`:

   ```diff
   .{
       .name = "my-project",
       .version = "1.0.0",
       .paths = .{""},
       .dependencies = .{
   +       .zbench = .{
   +           .url = "https://github.com/stoand/double_slice/archive/<COMMIT>.tar.gz",
   +       },
       },
   }
   ```

2. Add the module in `build.zig`:

   ```diff
   const std = @import("std");

   pub fn build(b: *std.Build) void {
       const target = b.standardTargetOptions(.{});
       const optimize = b.standardOptimizeOption(.{});

   +   const opts = .{ .target = target, .optimize = optimize };
   +   const double_slice_module = b.dependency("double_slice", opts).module("double_slice");

       const exe = b.addExecutable(.{
           .name = "test",
           .root_source_file = b.path("src/main.zig"),
           .target = target,
           .optimize = optimize,
       });
   +   exe.root_module.addImport("double_slice", double_slice_module);
       exe.install();

       ...
   }

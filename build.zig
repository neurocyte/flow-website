const std = @import("std");
const zine = @import("zine");

pub fn build(b: *std.Build) !void {
    _ = zine.website(b, .{
        .title = "Flow Editor",
        .host_url = "https://flow-editor.dev",
        .content_dir_path = "content",
        .layouts_dir_path = "layouts",
        .assets_dir_path = "assets",
    });

    const install_step = b.addInstallFile(b.path("install"), "install");
    b.getInstallStep().dependOn(&install_step.step);
}

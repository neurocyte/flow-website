const std = @import("std");
const zine = @import("zine");

pub fn build(b: *std.Build) !void {
    _ = zine.website(b, .{
        .title = "Flow Control: a progammer's text editor",
        .host_url = "https://flow-control.dev",
        .content_dir_path = "content",
        .layouts_dir_path = "layouts",
        .assets_dir_path = "assets",
    });

    const install_step = b.addInstallFile(b.path("install"), "install");
    b.getInstallStep().dependOn(&install_step.step);

    const install_key = b.addInstallFile(b.path("public.gpg"), "public.gpg");
    b.getInstallStep().dependOn(&install_key.step);

    const install_font = b.addInstallFile(b.path("assets/fonts/AcPlus_IBM_VGA_9x16.ttf"), "fonts/AcPlus_IBM_VGA_9x16.ttf");
    b.getInstallStep().dependOn(&install_font.step);

    const install_font2 = b.addInstallFile(b.path("assets/fonts/Iosevka-Regular.woff2"), "fonts/Iosevka-Regular.woff2");
    b.getInstallStep().dependOn(&install_font2.step);
}

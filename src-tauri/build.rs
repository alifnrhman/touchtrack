use std::{env, path::PathBuf, process::Command};
fn main() {
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    let target = env::var("TARGET").unwrap();
    let swift_target = if target.starts_with("aarch64") {
        "arm64-apple-macosx14.0"
    } else {
        "x86_64-apple-macosx14.0"
    };
    let status = Command::new("swiftc")
        .arg("-module-cache-path")
        .arg(out.join("swift-cache"))
        .args([
            "-parse-as-library",
            "-emit-library",
            "-static",
            "-module-name",
            "TouchBar",
            "-target",
            swift_target,
            "native/touchbar/TouchBar.swift",
            "native/touchbar/Lyrics.swift",
            "native/touchbar/NativeSafety.swift",
            "native/touchbar/TTMLLyrics.swift",
            "native/touchbar/AdBlocker.swift",
            "native/touchbar/GlobalTouchBar.swift",
            "-o",
        ])
        .arg(out.join("libTouchBar.a"))
        .status()
        .expect("Swift compiler required");
    assert!(status.success(), "Swift build failed");
    println!("cargo:rerun-if-changed=native/touchbar/TouchBar.swift");
    println!("cargo:rerun-if-changed=native/touchbar/Lyrics.swift");
    println!("cargo:rerun-if-changed=native/touchbar/NativeSafety.swift");
    println!("cargo:rerun-if-changed=native/touchbar/TTMLLyrics.swift");
    println!("cargo:rerun-if-changed=native/touchbar/AdBlocker.swift");
    println!("cargo:rerun-if-changed=../dist/player-adapter.js");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-search=native=/usr/lib/swift");
    println!("cargo:rustc-link-lib=static=TouchBar");
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
    for f in ["AppKit", "WebKit", "Foundation", "CoreText", "ImageIO"] {
        println!("cargo:rustc-link-lib=framework={f}");
    }
    let sdk = Command::new("xcrun")
        .args(["--sdk", "macosx", "--show-sdk-path"])
        .output()
        .expect("macOS SDK required");
    assert!(sdk.status.success());
    let sdk = String::from_utf8(sdk.stdout).unwrap();
    let object = out.join("GlobalTouchBarBridge.o");
    let status = Command::new("xcrun")
        .args([
            "clang",
            "-fobjc-arc",
            "-target",
            swift_target,
            "-isysroot",
            sdk.trim(),
            "-c",
            "native/touchbar/GlobalTouchBarBridge.m",
            "-o",
        ])
        .arg(&object)
        .status()
        .expect("Objective-C compiler required");
    assert!(status.success(), "Private API bridge compilation failed");
    let status = Command::new("ar")
        .arg("crs")
        .arg(out.join("libGlobalTouchBarBridge.a"))
        .arg(object)
        .status()
        .unwrap();
    assert!(status.success());
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=GlobalTouchBarBridge");
    println!("cargo:rerun-if-changed=native/touchbar/GlobalTouchBar.swift");
    println!("cargo:rerun-if-changed=native/touchbar/GlobalTouchBarBridge.m");
    tauri_build::build();
}

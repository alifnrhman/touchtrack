#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod player;
use player::{PlayerCommand, PlayerState};
use std::{
    ffi::{c_char, c_void, CStr, CString},
    sync::Mutex,
};
use tauri::{
    menu::{CheckMenuItem, Menu, MenuItem, Submenu},
    Manager,
};
static STATE: Mutex<Option<PlayerState>> = Mutex::new(None);
extern "C" {
    fn ytm_attach(view: *mut c_void, script: *const c_char);
    fn ytm_render(state: *const c_char);
    fn ytm_dispatch(command: *const c_char);
    fn ytm_show_status();
    fn ytm_toggle_lyrics();
    fn ytm_adblock_enabled() -> bool;
    fn ytm_toggle_adblock() -> bool;
}
#[no_mangle]
pub unsafe extern "C" fn ytm_state(json: *const c_char) {
    if json.is_null() {
        return;
    }
    let bytes = CStr::from_ptr(json).to_bytes();
    if bytes.len() > 16384 {
        return;
    }
    let Ok(mut state) = serde_json::from_slice::<PlayerState>(bytes) else {
        return;
    };
    if !state.validate() {
        return;
    }
    let Ok(value) = serde_json::to_string(&state) else {
        return;
    };
    if let Ok(mut slot) = STATE.lock() {
        *slot = Some(state);
    }
    if let Ok(value) = CString::new(value) {
        ytm_render(value.as_ptr());
    }
}
#[no_mangle]
pub unsafe extern "C" fn ytm_command(json: *const c_char) {
    if json.is_null() {
        return;
    }
    let bytes = CStr::from_ptr(json).to_bytes();
    if bytes.len() > 256 {
        return;
    }
    let Ok(command) = serde_json::from_slice::<PlayerCommand>(bytes) else {
        return;
    };
    let allowed = STATE
        .lock()
        .ok()
        .and_then(|s| s.clone())
        .is_some_and(|s| match command {
            PlayerCommand::Next => s.can_next,
            PlayerCommand::Previous => s.can_previous,
            PlayerCommand::Seek { time } => {
                s.can_seek
                    && time.is_finite()
                    && time >= 0.
                    && s.duration.is_some_and(|d| time <= d)
            }
            _ => s.current_time.is_some(),
        });
    if allowed {
        ytm_dispatch(json);
    }
}
// Keep login navigation in a separate, unmodified WebView within this app.
fn is_login_destination(url: &tauri::Url) -> bool {
    url.scheme() == "https"
        && url.username().is_empty()
        && url.password().is_none()
        && url.port_or_known_default() == Some(443)
        && match url.host_str() {
            Some(
                "accounts.google.com"
                | "accounts.youtube.com"
                | "consent.google.com"
                | "consent.youtube.com",
            ) => true,
            Some("music.youtube.com" | "www.youtube.com") => {
                matches!(url.path(), "/signin" | "/signin/" | "/ServiceLogin")
            }
            _ => false,
        }
}
fn auth_navigation_allowed(url: &tauri::Url) -> bool {
    url.scheme() == "https"
        && url.username().is_empty()
        && url.password().is_none()
        && url.port_or_known_default() == Some(443)
        && matches!(
            url.host_str(),
            Some(
                "accounts.google.com"
                    | "accounts.youtube.com"
                    | "consent.google.com"
                    | "consent.youtube.com"
                    | "music.youtube.com"
                    | "www.youtube.com"
            )
        )
}

fn open_sign_in(app: &tauri::AppHandle) {
    let handle = app.clone();
    // Navigation callbacks must return before constructing another WebView.
    let _ = app.run_on_main_thread(move || {
        if let Some(window) = handle.get_webview_window("signin") {
            let _ = window.show(); let _ = window.set_focus(); return;
        }
        let result = tauri::WebviewWindowBuilder::new(&handle, "signin", tauri::WebviewUrl::External(
            "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F".parse().unwrap()))
            .title("Google Sign In — Touchtrack")
            .inner_size(600., 720.)
            // Both windows use WebKit's persistent default data store. Do not attach
            // the music adapter, content blockers, or music compatibility user agent here.
            .on_navigation(auth_navigation_allowed)
            .on_page_load(|window, page| {
                if page.event() == tauri::webview::PageLoadEvent::Finished
                    && page.url().scheme() == "https"
                    && page.url().host_str() == Some("music.youtube.com") {
                    let _ = window.close();
                }
            })
            .build();
        match result {
            Ok(window) => {
                let app = handle.clone();
                window.on_window_event(move |event| {
                    if matches!(event, tauri::WindowEvent::Destroyed) {
                        if let Some(music) = app.get_webview_window("music") {
                            let _ = music.reload(); let _ = music.set_focus();
                        }
                    }
                });
            }
            Err(error) => eprintln!("Unable to open sign-in window: {error}"),
        }
    });
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let sign = MenuItem::with_id(app, "sign", "Sign In…", true, None::<&str>)?;
            let reload =
                MenuItem::with_id(app, "reload", "Reload Music", true, Some("CmdOrCtrl+R"))?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, Some("CmdOrCtrl+Q"))?;
            let toggle =
                MenuItem::with_id(app, "toggle", "Play / Pause", true, Some("CmdOrCtrl+Space"))?;
            let next = MenuItem::with_id(app, "next", "Next Track", true, None::<&str>)?;
            let previous =
                MenuItem::with_id(app, "previous", "Previous Track", true, None::<&str>)?;
            let status = MenuItem::with_id(app, "status", "Player Status…", true, None::<&str>)?;
            let lyrics = MenuItem::with_id(
                app,
                "lyrics",
                "Toggle Touch Bar Lyrics",
                true,
                Some("CmdOrCtrl+L"),
            )?;
            let adblock = CheckMenuItem::with_id(
                app,
                "adblock",
                "Block Ads (reloads music)",
                true,
                unsafe { ytm_adblock_enabled() },
                None::<&str>,
            )?;
            let submenu = Submenu::with_items(
                app,
                "Touchtrack",
                true,
                &[
                    &sign, &reload, &toggle, &previous, &next, &lyrics, &adblock, &status, &quit,
                ],
            )?;
            app.set_menu(Menu::with_items(app, &[&submenu])?)?;
            app.on_menu_event(move |app, event| match event.id().as_ref() {
                "quit" => app.exit(0),
                "status" => unsafe { ytm_show_status() },
                "lyrics" => unsafe { ytm_toggle_lyrics() },
                "adblock" => {
                    let enabled = unsafe { ytm_toggle_adblock() };
                    let _ = adblock.set_checked(enabled);
                }
                "toggle" | "next" | "previous" => {
                    if let Ok(json) =
                        CString::new(format!("{{\"type\":\"{}\"}}", event.id().as_ref()))
                    {
                        unsafe { ytm_command(json.as_ptr()) }
                    }
                }
                "reload" => {
                    if let Some(w) = app.get_webview_window("music") {
                        let _ = w.reload();
                    }
                }
                "sign" => open_sign_in(app),
                _ => {}
            });
            let popup_app = app.handle().clone();
            let navigation_app = app.handle().clone();
            let window = tauri::WebviewWindowBuilder::new(
                app,
                "music",
                tauri::WebviewUrl::App("index.html".into()),
            )
            .on_new_window(move |u, _| {
                if is_login_destination(&u) {
                    open_sign_in(&popup_app);
                }
                tauri::webview::NewWindowResponse::Deny
            })
            .on_navigation(move |u| {
                if is_login_destination(u) {
                    open_sign_in(&navigation_app);
                    return false;
                }
                u.scheme() == "tauri"
                    || (cfg!(debug_assertions)
                        && u.scheme() == "http"
                        && u.host_str() == Some("localhost")
                        && u.port() == Some(5173))
                    || (u.scheme() == "http" && u.host_str() == Some("tauri.localhost"))
                    || (u.scheme() == "https" && u.host_str() == Some("music.youtube.com"))
            })
            .title("Touchtrack")
            .inner_size(1100., 760.)
            .build()?;
            let script = CString::new(include_str!("../../dist/player-adapter.js"))?;
            window.with_webview(move |p| unsafe { ytm_attach(p.inner(), script.as_ptr()) })?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Application failed");
}

#[cfg(test)]
mod auth_tests {
    use super::*;
    #[test]
    fn routes_login_but_keeps_music_and_untrusted_urls_out() {
        for url in [
            "https://accounts.google.com/ServiceLogin",
            "https://music.youtube.com/signin",
            "https://www.youtube.com/signin?action_handle_signin=true",
        ] {
            assert!(is_login_destination(&url.parse().unwrap()), "{url}");
        }
        for url in [
            "https://music.youtube.com/",
            "https://music.youtube.com/watch?v=test",
            "https://accounts.google.com.evil.test/",
            "http://accounts.google.com/",
            "https://accounts.google.com:444/",
            "https://user@accounts.google.com/",
        ] {
            assert!(!is_login_destination(&url.parse().unwrap()), "{url}");
        }
    }
}

use serde::{Deserialize, Serialize};
#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PlayerState {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    #[serde(default = "default_playback_rate")]
    pub playback_rate: f64,
    pub artwork_url: Option<String>,
    pub duration: Option<f64>,
    pub current_time: Option<f64>,
    pub is_playing: bool,
    #[serde(default)]
    pub is_ad: bool,
    pub can_seek: bool,
    pub can_next: bool,
    pub can_previous: bool,
}
fn default_playback_rate() -> f64 {
    1.0
}
impl PlayerState {
    pub fn validate(&mut self) -> bool {
        if [&self.title, &self.artist, &self.album]
            .iter()
            .any(|s| s.as_ref().is_some_and(|s| s.len() > 4096))
        {
            return false;
        }
        if [self.duration, self.current_time]
            .into_iter()
            .flatten()
            .any(|n| !n.is_finite() || n < 0. || n > 604800.)
        {
            return false;
        }
        if let (Some(t), Some(d)) = (self.current_time, self.duration) {
            self.current_time = Some(t.min(d));
        }
        if !self.playback_rate.is_finite() || self.playback_rate <= 0.0 || self.playback_rate > 4.0
        {
            self.playback_rate = 1.0;
        }
        self.can_seek &= self.duration.is_some_and(|n| n > 0.);
        if self
            .artwork_url
            .as_ref()
            .is_some_and(|s| !artwork_allowed(s))
        {
            self.artwork_url = None;
        }
        true
    }
}
fn artwork_allowed(s: &str) -> bool {
    if s.len() > 4096 {
        return false;
    }
    tauri::Url::parse(s).is_ok_and(|u| {
        u.scheme() == "https"
            && u.port_or_known_default() == Some(443)
            && u.username().is_empty()
            && u.password().is_none()
            && u.host_str().is_some_and(|h| {
                ["ytimg.com", "googleusercontent.com", "ggpht.com"]
                    .iter()
                    .any(|d| h == *d || h.ends_with(&format!(".{d}")))
            })
    })
}
#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "lowercase", deny_unknown_fields)]
pub enum PlayerCommand {
    Play,
    Pause,
    Toggle,
    Next,
    Previous,
    Seek { time: f64 },
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_invalid_times() {
        let mut s = PlayerState::default();
        s.duration = Some(f64::NAN);
        assert!(!s.validate());
        s.duration = Some(-1.);
        assert!(!s.validate());
    }
    #[test]
    fn clamps_and_restricts_artwork() {
        let mut s = PlayerState::default();
        s.duration = Some(10.);
        s.current_time = Some(20.);
        s.artwork_url = Some("https://ytimg.com.evil.test/a".into());
        assert!(s.validate());
        assert_eq!(s.current_time, Some(10.));
        assert!(s.artwork_url.is_none());
        assert!(artwork_allowed("https://i.ytimg.com/a"));
        assert!(!artwork_allowed("file:///tmp/a"));
    }
    #[test]
    fn rejects_unknown_commands() {
        assert!(serde_json::from_str::<PlayerCommand>(r#"{"type":"exec","code":"x"}"#).is_err());
    }
}

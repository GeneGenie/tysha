import Foundation

/// Developer-tweakable knobs for the optional background-music bed.
///
/// The track `bg_music_start_from_45sec.mp3` plays quietly under the per-phase
/// cues for the whole session. Change `backgroundMusicStartSec` to move where the
/// loop begins (and restarts), or `backgroundMusicVolume` to balance it against
/// the phase sounds. Set the file to one that is not in the bundle to disable it.
enum AudioConfig {
    /// Bundle resource name (without extension) for the background bed.
    static let backgroundMusicFile = "bg_music_start_from_45sec"

    /// Where playback starts, and where each loop restarts (seconds into the file).
    static let backgroundMusicStartSec: TimeInterval = 90

    /// 0...1. Kept low so phase cues stay in front.
    static let backgroundMusicVolume: Float = 0.55

    /// 0...1. Breathing-cue volume (inhale/exhale clips). Kept below full
    /// so the music bed stays audible underneath.
    static let breathVolume: Float = 0.4
}

# Audio Management Fix - Cross-Device Audio Handling

## Problem
Videos started muted but still overrode device audio (music, podcasts). Users wanted to:
- Listen to device music while using the app
- Have audio recordings/files override device audio only when explicitly playing them
- Videos should never interfere with device audio

## Solution
Implemented proper `AVAudioSession` category management with three distinct configurations:

### 1. **Ambient Mode (Default - App Startup)**
- **Configuration**: `.ambient` category with `.duckOthers` option
- **Behavior**: Device music/audio continues playing but is ducked (quieter) while the app uses audio
- **Activated**: On app startup in `ContentView.body.task`
- **Function**: `configureAudioSessionForAppUse()`
- **Result**: Users can listen to music while scrolling through posts

### 2. **Playback Mode (Explicit Audio Play)**
- **Configuration**: `.playback` category with no options
- **Behavior**: App audio takes priority and interrupts device audio
- **Activated**: When user explicitly plays/unmutes audio
- **Functions Used**:
  - `configureAudioSessionForExplicitAudioPlayback()` - Switch to playback mode
  - In `playAudioPost()` - For draft audio recordings
  - In `playAudioFile()` (PostCardView) - For posted audio/songs
- **Result**: Audio recordings and audio files get full audio priority when actively playing

### 3. **Reset to Ambient (After Audio Stops)**
- **Configuration**: Return to `.ambient` with `.duckOthers`
- **Behavior**: Device music resumes to normal volume
- **Activated**: When audio playback completes
- **Functions Used**:
  - `resetAudioSessionToAmbient()`
  - Called in `playRecordedAudio()` completion
  - Called in `stopAudioPlaybackDotsAnimation()` 
  - Called in `stopAudioRecording()`
  - Called in `resetAudioRecordingState()`
- **Result**: Smooth return to music after audio content finishes

## Implementation Details

### New Helper Functions (ContentView)
```swift
private func configureAudioSessionForAppUse()
private func configureAudioSessionForExplicitAudioPlayback()
private func resetAudioSessionToAmbient()
```

### Modified Functions
1. **Audio Recording & Playback (Draft)**
   - `startAudioRecording()` - Removed audio session setup (relies on ambient mode)
   - `stopAudioRecording()` - Added `resetAudioSessionToAmbient()`
   - `playRecordedAudio()` - Added `resetAudioSessionToAmbient()` on completion
   - `playAudioPost()` - Updated to use `configureAudioSessionForExplicitAudioPlayback()`
   - `resetAudioRecordingState()` - Added `resetAudioSessionToAmbient()`

2. **Audio Playback (Posted Audio/Songs - PostCardView)**
   - `playAudioFile()` - Explicit `.playback` category setup
   - `stopAudioPlaybackDotsAnimation()` - Added `resetAudioSessionToAmbient()`

3. **App Initialization (ContentView)**
   - `body.task` - Added `configureAudioSessionForAppUse()` call

## Video Behavior
- **Video playback**: Remains muted by default (`isMuted: true` in LoopingVideoPlayer)
- **Audio session**: Videos do NOT change audio session, leaving it in ambient mode
- **Result**: Music continues uninterrupted, videos play silently as intended

## Audio Types Behavior

| Audio Type | Initial State | When Playing | When Stopped |
|-----------|---------------|--------------|--------------|
| Device Music | Playing | Ducked to background | Resumes normal volume |
| Video (muted) | Muted | (N/A - stays muted) | N/A |
| Audio Recording | Not playing | Plays full volume (takes over) | Music resumes |
| Audio Post | Not playing | Plays full volume (takes over) | Music resumes |
| Song Post | Not playing | Plays full volume (takes over) | Music resumes |

## User Experience Flow

### Scenario 1: User wants to listen to their music while scrolling
1. App starts → audio session set to ambient
2. User opens music app → music plays at normal volume
3. User scrolls through posts → if video appears, it's muted (music continues)
4. ✅ User hears their music uninterrupted

### Scenario 2: User wants to listen to an audio recording they made
1. User navigates to draft audio post
2. User taps play button on audio recording
3. Audio session switches to playback mode → device music pauses/ducks
4. Audio recording plays at full volume
5. Recording finishes → audio session resets to ambient → music resumes
6. ✅ User hears their recording clearly, then music resumes

### Scenario 3: User wants to view/unmute a video
1. User scrolls to video post
2. Video plays muted by default (music continues)
3. If user unmutes video (future UI feature), audio session would switch to playback
4. ✅ Video audio takes priority when explicitly enabled

## Technical Notes
- Uses iOS AVAudioSession framework standard categories
- `.ambient` with `.duckOthers` allows mixing but lowers other audio
- `.playback` without options takes full priority
- Audio session state is properly managed through lifecycle
- Compatible with all iOS versions supporting SwiftUI

## Testing Recommendations
1. ✅ Play music from device, scroll through posts with videos
2. ✅ Play audio recording while music is playing - verify music pauses
3. ✅ Stop audio recording - verify music resumes
4. ✅ Unmute video (when feature added) - verify audio takes over
5. ✅ Background/foreground transitions - verify audio session state maintained

## Files Modified
- `Spot/ContentView.swift`
  - Added 3 audio session helper functions
  - Updated 8 audio-related functions
  - Modified app initialization in body.task

## Related Code
- Audio recording: Lines 8670-8710
- Audio playback (draft): Lines 8732-8780
- Audio playback (posted): Lines 11907-11980
- App initialization: Lines 1108-1120

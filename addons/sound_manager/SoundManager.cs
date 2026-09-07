#nullable enable

using Godot;
using Godot.Collections;

namespace Lefrec
{
	public partial class SoundManager : Node
	{
		private static Node? instance;
		public static Node Instance
		{
			get => instance ??= (Node)Engine.GetSingleton("SoundManager");
		}

		#region Volume

		public static float GetVolume(int busIndex)
			=> (float)Instance.Call("get_volume", busIndex);

		public static void SetVolume(int busIndex, float volume)
			=> Instance.Call("set_volume", busIndex, volume);

		public static bool GetMute(int busIndex)
			=> (bool)Instance.Call("get_mute", busIndex);

		public static void SetMute(int busIndex, bool enabled)
			=> Instance.Call("set_mute", busIndex, enabled);

		#endregion

		#region Effects

		public static AudioEffect GetEffect(int busIndex, int effectIndex)
			=> (AudioEffect)(GodotObject)Instance.Call("get_effect", busIndex, effectIndex);

		public static Array<AudioEffect> GetEffects(int busIndex)
			=> (Array<AudioEffect>)Instance.Call("get_effects", busIndex);

		public static void AddEffect(int busIndex, AudioEffect effect, int index = -1)
			=> Instance.Call("add_effect", busIndex, effect, index);

		public static void SetEffect(int busIndex, int effectIndex, bool enabled)
			=> Instance.Call("set_effect", busIndex, effectIndex, enabled);

		public static void RemoveEffect(int busIndex, int effectIndex)
			=> Instance.Call("remove_effect", busIndex, effectIndex);

		public static void ClearEffects(int busIndex)
			=> Instance.Call("clear_effects", busIndex);

		#endregion

		#region Master

		public static int GetMasterIndex()
			=> (int)Instance.Call("get_master_index");

		#endregion

		#region Sound Effects

		public static int GetSoundEffectsIndex()
			=> (int)Instance.Call("get_sound_effects_index");

		public static AudioStreamPlayer PlaySoundEffect(AudioStream resource, string overrideBus = "")
			=> (AudioStreamPlayer)(GodotObject)Instance.Call("play_sound_effect", resource, overrideBus);

		public static void StopSoundEffect(AudioStream resource)
			=> Instance.Call("stop_sound_effect", resource);

		public static void SetSoundEffectsBus(string bus)
			=> Instance.Call("set_sound_effects_bus", bus);

		#endregion

		#region UI Sounds

		public static int GetUISoundsIndex()
			=> (int)Instance.Call("get_ui_sounds_index");

		public static AudioStreamPlayer PlayUISound(AudioStream resource, string overrideBus = "")
			=> (AudioStreamPlayer)(GodotObject)Instance.Call("play_ui_sound", resource, overrideBus);

		public static void StopUISound(AudioStream resource)
			=> Instance.Call("stop_ui_sound", resource);

		public static void SetUISoundsBus(string bus)
			=> Instance.Call("set_ui_sounds_bus", bus);

		#endregion

		#region Ambient Sounds

		public static int GetAmbientSoundsIndex()
			=> (int)Instance.Call("get_ambient_sounds_index");

		public static AudioStreamPlayer PlayAmbientSound(AudioStream resource, float fadeInDuration = 0.0f, string overrideBus = "")
			=> (AudioStreamPlayer)(GodotObject)Instance.Call("play_ambient_sound", resource, fadeInDuration, overrideBus);

		public static void StopAmbientSound(AudioStream resource, float fadeOutDuration = 0.0f)
			=> Instance.Call("stop_ambient_sound", resource, fadeOutDuration);

		public static void StopAllAmbientSounds(float fadeOutDuration = 0.0f)
			=> Instance.Call("stop_all_ambient_sounds", fadeOutDuration);

		public static void SetAmbientSoundBus(string bus)
			=> Instance.Call("set_ambient_sound_bus", bus);

		#endregion

		#region Music

		public static int GetMusicIndex()
			=> (int)Instance.Call("get_music_index");

		public static AudioStreamPlayer PlayMusic(AudioStream resource, float position = 0.0f, float volume = 1.0f, float crossFadeDuration = 0.0f, string overrideBus = "")
			=> (AudioStreamPlayer)(GodotObject)Instance.Call("play_music", resource, position, volume, crossFadeDuration, overrideBus);

		public static bool IsMusicPlaying()
			=> (bool)Instance.Call("is_music_playing");

		public static bool IsMusicPlaying(AudioStream resource)
			=> (bool)Instance.Call("is_music_playing", resource);

		public static bool IsMusicTrackPlaying(string resourcePath)
			=> (bool)Instance.Call("is_music_track_playing", resourcePath);

		public static Array<AudioStream> GetCurrentlyPlayingMusic()
			=> (Array<AudioStream>)Instance.Call("get_currently_playing_music");

		public static Array<string> GetCurrentlyPlayingMusicTracks()
			=> (Array<string>)Instance.Call("get_currently_playing_music_tracks");

		public static Array<string> GetMusicTrackHistory()
			=> (Array<string>)Instance.Call("get_music_track_history");

		public static string GetLastPlayedMusicTrack()
			=> (string)Instance.Call("get_last_played_music_track");

		public static void PauseMusic()
			=> Instance.Call("pause_music");

		public static void PauseMusic(AudioStream resource)
			=> Instance.Call("pause_music", resource);

		public static void ResumeMusic()
			=> Instance.Call("resume_music");

		public static void ResumeMusic(AudioStream resource)
			=> Instance.Call("resume_music", resource);

		public static void StopMusic(float fadeOutDuration = 0.0f)
			=> Instance.Call("stop_music", fadeOutDuration);

		public static void SetMusicBus(string bus)
			=> Instance.Call("set_music_bus", bus);

		#endregion
	}
}

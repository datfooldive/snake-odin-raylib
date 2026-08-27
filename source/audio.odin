package game

import "core:c"
import "core:math"
import rl "vendor:raylib"

// Procedural audio: everything generated at runtime, no asset files.

SR :: 22050

sfx_eat:   rl.Sound
sfx_die:   rl.Sound
sfx_slow:  rl.Sound
sfx_phase: rl.Sound
sfx_level: rl.Sound

bgm:     rl.Music
bgm_wav: []u8 // must stay alive, Music streams from it

audio_ok: bool
bgm_on:  bool = true
sfx_on:  bool = true

m2f :: proc(n: i32) -> f32 {
	return 440 * math.pow(2, (f32(n) - 69) / 12)
}

put16 :: proc(b: []u8, off: int, v: u16) {
	b[off] = u8(v & 0xff)
	b[off + 1] = u8(v >> 8)
}

put32 :: proc(b: []u8, off: int, v: u32) {
	b[off] = u8(v & 0xff)
	b[off + 1] = u8((v >> 8) & 0xff)
	b[off + 2] = u8((v >> 16) & 0xff)
	b[off + 3] = u8(v >> 24)
}

// pitch sweep, optional square mix, exponential decay
tone :: proc(dur, f0, f1, vol: f32, square: bool, decay: f32) -> []i16 {
	n := int(dur * SR)
	buf := make([]i16, n)
	phase: f32 = 0
	for i := 0; i < n; i += 1 {
		t := f32(i) / f32(n)
		f := f0 + (f1 - f0) * t
		phase += f / f32(SR)
		v := math.sin(phase * 2 * math.PI)
		if square {
			v = (1.0 if v > 0 else -1.0) * 0.6 + v * 0.4
		}
		buf[i] = i16(v * math.exp(-t * decay) * vol * 32767)
	}
	return buf
}

noise :: proc(dur, vol, decay: f32) -> []i16 {
	n := int(dur * SR)
	buf := make([]i16, n)
	for i := 0; i < n; i += 1 {
		t := f32(i) / f32(n)
		buf[i] = i16((rf() * 2 - 1) * math.exp(-t * decay) * vol * 32767)
	}
	return buf
}

mix_into :: proc(dst, src: []i16, at: f32) {
	off := int(at * SR)
	for i := 0; i < len(src); i += 1 {
		j := off + i
		if j < 0 || j >= len(dst) {
			continue
		}
		v := i32(dst[j]) + i32(src[i])
		if v > 32000 {
			v = 32000
		}
		if v < -32000 {
			v = -32000
		}
		dst[j] = i16(v)
	}
}

wave_sound :: proc(pcm: []i16, vol: f32) -> rl.Sound {
	w := rl.Wave {
		frameCount = c.uint(len(pcm)),
		sampleRate = SR,
		sampleSize = 16,
		channels = 1,
		data = &pcm[0],
	}
	s := rl.LoadSoundFromWave(w)
	rl.SetSoundVolume(s, vol)
	return s
}

// 16-bit mono PCM -> WAV file bytes
wav_bytes :: proc(pcm: []i16) -> []u8 {
	n := len(pcm) * 2
	buf := make([]u8, 44 + n)
	copy_bytes :: proc(h: []u8, off: int, s: string) {
		for ch, i in s {
			h[off + i] = u8(ch)
		}
	}
	copy_bytes(buf, 0, "RIFF")
	put32(buf, 4, u32(36 + n))
	copy_bytes(buf, 8, "WAVE")
	copy_bytes(buf, 12, "fmt ")
	put32(buf, 16, 16)      // fmt chunk size
	put16(buf, 20, 1)       // PCM
	put16(buf, 22, 1)       // mono
	put32(buf, 24, SR)      // sample rate
	put32(buf, 28, SR * 2)  // byte rate
	put16(buf, 32, 2)       // block align
	put16(buf, 34, 16)      // bits
	copy_bytes(buf, 36, "data")
	put32(buf, 40, u32(n))
	for s, i in pcm {
		put16(buf, 44 + i * 2, u16(s))
	}
	return buf
}

make_bgm :: proc() -> []i16 {
	bpm: f32 = 132
	beat := 60.0 / bpm
	eighth := beat / 2
	bars := 8
	buf := make([]i16, int(f32(bars) * 4 * beat * SR))

	// Bright C-major hook over C/F/Am/G.
	lead := [64]i32{
		64, 67, 72, 67, 64, 67, 72, 74,
		76, 74, 72, 67, 69, 67, 64, -1,
		65, 69, 72, 69, 65, 69, 72, 74,
		76, 72, 69, 67, 69, 72, 74, -1,
		69, 72, 76, 72, 69, 72, 76, 79,
		76, 74, 72, 69, 67, 69, 72, -1,
		67, 71, 74, 71, 67, 71, 74, 76,
		79, 76, 74, 71, 72, 74, 72, -1,
	}
	for n, i in lead {
		if n < 0 {
			continue
		}
		f := m2f(n)
		mix_into(buf, tone(eighth * 0.78, f, f, 0.13, true, 3.5), f32(i) * eighth)
		mix_into(buf, tone(eighth * 0.7, f * 2, f * 2, 0.025, false, 5), f32(i) * eighth)
	}

	// Bouncy root/octave bass follows C/F/Am/G.
	bass_root := [8]i32{48, 48, 41, 41, 45, 45, 43, 43}
	for b := 0; b < bars; b += 1 {
		for e := 0; e < 8; e += 2 {
			note := bass_root[b]
			if e == 2 || e == 6 {
				note += 12
			}
			f := m2f(note)
			mix_into(buf, tone(beat * 0.65, f, f, 0.18, true, 4), f32(b * 8 + e) * eighth)
		}
	}

	// Light arcade beat; offbeat hats keep it moving.
	for b := 0; b < bars; b += 1 {
		for e := 0; e < 8; e += 1 {
			t := f32(b * 8 + e) * eighth
			if e == 0 || e == 4 {
				mix_into(buf, tone(0.11, 125, 48, 0.36, false, 9), t)
			}
			if e == 2 || e == 6 {
				mix_into(buf, noise(0.055, 0.09, 12), t)
			}
			if e & 1 == 1 {
				mix_into(buf, noise(0.022, 0.045, 16), t)
			}
		}
	}
	return buf
}

init_audio :: proc() {
	if audio_ok {
		return
	}
	rl.InitAudioDevice()
	if !rl.IsAudioDeviceReady() {
		return
	}

	sfx_eat = wave_sound(tone(0.09, 520, 1040, 0.5, true, 4), 0.7)

	die_pcm := make([]i16, int(0.7 * f32(SR)))
	mix_into(die_pcm, noise(0.5, 0.5, 5), 0)
	mix_into(die_pcm, tone(0.65, 300, 55, 0.5, true, 3), 0)
	mix_into(die_pcm, tone(0.15, 120, 40, 0.6, false, 8), 0)
	sfx_die = wave_sound(die_pcm, 0.8)

	slow_pcm := make([]i16, int(0.5 * SR))
	mix_into(slow_pcm, tone(0.5, 880, 110, 0.4, false, 2), 0)
	mix_into(slow_pcm, tone(0.5, 1760, 220, 0.2, false, 3), 0)
	sfx_slow = wave_sound(slow_pcm, 0.6)

	phase_pcm := make([]i16, 45 * SR / 100)
	mix_into(phase_pcm, tone(0.45, 220, 1760, 0.35, false, 2), 0)
	mix_into(phase_pcm, tone(0.45, 226, 1808, 0.25, false, 2), 0) // detune shimmer
	sfx_phase = wave_sound(phase_pcm, 0.6)

	level_pcm := make([]i16, SR / 2)
	mix_into(level_pcm, tone(0.18, m2f(69), m2f(69), 0.4, true, 4), 0)
	mix_into(level_pcm, tone(0.18, m2f(72), m2f(72), 0.4, true, 4), 0.13)
	mix_into(level_pcm, tone(0.24, m2f(76), m2f(76), 0.4, true, 3), 0.26)
	sfx_level = wave_sound(level_pcm, 0.65)

	bgm_wav = wav_bytes(make_bgm())
	bgm = rl.LoadMusicStreamFromMemory(".wav", &bgm_wav[0], c.int(len(bgm_wav)))
	bgm.looping = true
	rl.SetMusicVolume(bgm, 0.35)
	if bgm_on {
		rl.PlayMusicStream(bgm)
	}

	audio_ok = true
}

set_bgm :: proc(on: bool) {
	bgm_on = on
	if !audio_ok {
		return
	}
	if on {
		rl.ResumeMusicStream(bgm)
	} else {
		rl.PauseMusicStream(bgm)
	}
}

play :: proc(s: rl.Sound) {
	if audio_ok && sfx_on {
		rl.PlaySound(s)
	}
}

update_audio :: proc() {
	if audio_ok && bgm_on {
		rl.UpdateMusicStream(bgm)
	}
}

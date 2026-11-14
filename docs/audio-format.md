# Audio

Welcome: WAV container, mono, signed PCM 16-bit, 8000 Hz. Playlists: WAV container, mono, signed PCM 16-bit, 16000 Hz, with Asterisk's `.wav16` extension. Playback paths omit extensions. G.722 enables wideband where negotiated, with ulaw/alaw fallback; retain master recordings elsewhere.

```bash
ffmpeg -i input.mp3 -ar 8000 -ac 1 -c:a pcm_s16le audio/welcome/greeting.wav
ffmpeg -i input.mp3 -ar 16000 -ac 1 -c:a pcm_s16le -f wav audio/audiobooks/1.wav16
```

`-f wav` is required because FFmpeg may not infer a WAV container from `.wav16`. Use contiguous names starting at 1. Directories, symlinks, unexpected files, gaps and wrong formats fail validation. Each deployment derives counts from local files. Empty directories disable playback with a warning and clear call-time log/hangup. Missing deployed audio likewise fails safely.

Counters `magic/audiobook_next` and `magic/music_next` are read from AstDB, initialized to 1, bounded to the current count and advanced **before** playback. Exactly one track plays per call, wrapping at the count. Early hangup still advances. Deploy does not touch AstDB or its runtime-selected file. Simultaneous calls to one playlist are not guaranteed atomic in v1; intended for one handset.

```bash
./scripts/reset-rotation.sh audiobooks
./scripts/reset-rotation.sh music
./scripts/reset-rotation.sh all
```

These reset only the selected next-track key to 1. After reducing a playlist, old deployed files remain unused. To reclaim storage, stop calls, back up the sounds directory and manually remove only the unreferenced numeric files after reviewing the new count. There is no implicit pruning.

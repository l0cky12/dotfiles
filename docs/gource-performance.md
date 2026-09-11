# Gource render performance

`hypr/.config/hypr/scripts/gource-dotfiles.sh` renders the complete repository
at 1280x720 and 30 fps, feeds uncompressed PPM frames to FFmpeg, and preserves
the fast source timestamps during playback. The expensive work is therefore
generating and encoding every source frame.

## Measured context

At the time of this note the repository has 139 commits over about 149 days.
A 1280x720 RGB PPM frame is about 2.6 MiB before pipe overhead; 30 such frames
per second is roughly 79 MiB/s of raw frame data. This makes PPM generation and
CPU H.264 encoding the likely bottlenecks, rather than Git-log discovery.

## Options, in descending expected impact

| Change | Expected effect | Trade-off |
| --- | --- | --- |
| Render at `-960x540` | 1.78 times fewer pixels than the current 1280x720, reducing Gource draw work, PPM pipe bandwidth, and encoding work. | The video is 540p and noticeably softer fullscreen. |
| Use `--output-framerate 25` | Gource officially supports 25, 30, and 60 fps for PPM output; 25 fps emits 17% fewer frames than 30. | Motion is less smooth. |
| Use `libx264 -preset ultrafast` | The script already uses x264's fastest preset, which reduces CPU encoding time. | Larger file and/or lower compression efficiency at the same CRF. |
| Use `h264_nvenc -preset p1` or `p2` with a quality rate-control setting | This FFmpeg build exposes NVIDIA's H.264 encoder, whose documentation labels `p1` fastest and `p2` faster. Hardware encoding can free the CPU and complete the H.264 stage faster. | It accelerates encoding only: Gource still renders frames and transfers PPM through the CPU. NVENC must be tested on the actual GPU/driver; encoder availability in FFmpeg does not prove the runtime device is usable. Quality/size differ from x264, and the current host has no `nvidia-smi` command available to confirm the assumed RTX 3070. |
| Add `--no-vsync` | Gource documents it as disabling VSync, which can remove display-sync pacing. | Its benefit must be benchmarked with PPM output; the requested output frame rate still limits emitted frames. |
| Hide nonessential elements such as `--hide bloom` and omit `--key` / `--highlight-users` | Gource can hide the bloom display element and documents each overlay option. This may lower rendering cost. | Changes the look. The payoff is likely smaller than resolution/FPS/encoder changes. |
| Cap `--max-files` or use `--start-date` / `--stop-date` | Gource discards files over `--max-files` and can limit the timeline by date. This reduces scene and/or history work. | It no longer shows the complete repository. |
| Cache a generated Gource custom log | Gource notes that log generation may be slow for large projects and supports `--output-custom-log` then replaying that log. | For this small local Git history it is unlikely to matter. A persistent cache needs invalidation when history changes; a temporary log does not save a later run. |

## Recommended experiment order

1. Keep the complete history but try 960x540 or 25 fps if still faster output
   outweighs fullscreen detail and motion smoothness.
2. If encoding remains the slow stage, test an NVENC command on a short bounded
   slice before making it the default. Use a CPU fallback when the test fails.
3. If Gource remains the slow stage, decide whether the visual compromise of
   25 fps or 720p is acceptable. There is no encoder-only change that removes
   Gource's OpenGL/PPM rendering cost.

The existing extremely small `--seconds-per-day` and `--auto-skip-seconds`
already minimize simulated timeline time. Lowering them further mostly reduces
the number of unique frames and makes playback choppier.

## Primary sources

- [Gource README: PPM output, allowed output frame rates, rendering controls, and log caching](https://github.com/acaudwell/Gource/blob/master/README.md)
- [FFmpeg codec documentation](https://ffmpeg.org/ffmpeg-codecs.html)
- [FFmpeg filter documentation (`setpts`)](https://ffmpeg.org/ffmpeg-filters.html#setpts)

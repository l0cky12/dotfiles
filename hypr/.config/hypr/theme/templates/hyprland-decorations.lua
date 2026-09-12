-- ~/.config/hypr/conf/decorations.lua
-- GENERATED — do not edit. Source: themes/{{ theme_slug }}/colors.toml
-- Theme: {{ theme_name }} ({{ theme_mode }})
--
-- Gaps are intentionally identical across every theme: switching palette must
-- not reflow window management. Personality lives in rounding, border width,
-- opacity and blur.

hl.config({
    general = {
        border_size = {{ border_width }},
        gaps_in = {{ gaps_in }},
        gaps_out = {{ gaps_out }},
        float_gaps = {{ gaps_out }},
        col = {
            active_border = {
                colors = { "{{ hypr_rgba(border_active) }}", "{{ hypr_rgba(accent_alt) }}" },
                angle = {{ degrees(border_angle) }},
            },
            inactive_border = "{{ hypr_rgba(border) }}",
        },
    },
    decoration = {
        rounding = {{ rounding }},
        rounding_power = 2.0,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        fullscreen_opacity = 1.0,
        shadow = {
            enabled = {{ on(shadow_opacity > 0) }},
            range = {{ shadow_range }},
            render_power = {{ shadow_render_power }},
            color = "{{ hypr_rgba(shadow, shadow_opacity) }}",
        },
        blur = {
            enabled = true,
            size = {{ blur_size }},
            passes = {{ blur_passes }},
            ignore_opacity = true,
            new_optimizations = true,
            xray = false,
            noise = {{ blur_noise }},
            contrast = {{ blur_contrast }},
            brightness = {{ blur_brightness }},
            vibrancy = {{ blur_vibrancy }},
        },
    },
})

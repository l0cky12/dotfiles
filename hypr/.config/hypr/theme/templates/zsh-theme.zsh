# ~/.config/zsh/current-theme.zsh
# GENERATED from themes/{{ theme_slug }}/colors.toml — do not edit.
# Theme: {{ theme_name }} ({{ theme_mode }})
#
# .zshrc sources this AFTER ~/.p10k.zsh, so these override the prompt's palette.
# The prompt's *shape* is left alone: .p10k.zsh's filled-powerline design
# (POWERLEVEL9K_MODE=nerdfont-v3,  separators, coloured segment
# backgrounds) is preserved and only recoloured. Only segments that carry
# meaning are touched; everything else inherits kitty's ANSI palette, themed
# from the same source.
#
# Mapping (deliberately restrained):
#   path            -> accent          git branch     -> accent_alt
#   clean git       -> green           dirty git      -> yellow
#   failed command  -> red             timing / clock -> muted
#   prompt char     -> accent / red
#
# Every foreground drawn on a coloured background is chosen by contrast rather
# than assumed to be white, so the light themes stay readable.

# Truecolor hex in kitty (COLORTERM=truecolor); nearest xterm-256 index
# everywhere else, so an ssh session or a TERM=linux console still gets the
# right relationships between segments even if not the exact hue.
if [[ "$COLORTERM" == (truecolor|24bit) ]]; then
  typeset -gA _th=(
    accent        '{{ accent }}'          on_accent     '{{ fg_on(accent) }}'
    accent_alt    '{{ accent_alt }}'      on_accent_alt '{{ fg_on(accent_alt) }}'
    fg            '{{ foreground }}'      fg_bright     '{{ foreground_bright }}'
    muted         '{{ muted }}'           surface       '{{ surface }}'
    surface_alt   '{{ surface_alt }}'     bg            '{{ background }}'
    red           '{{ red }}'             on_red        '{{ fg_on(red) }}'
    green         '{{ green }}'           on_green      '{{ fg_on(green) }}'
    yellow        '{{ yellow }}'          on_yellow     '{{ fg_on(yellow) }}'
    blue          '{{ blue }}'            on_blue       '{{ fg_on(blue) }}'
    magenta       '{{ magenta }}'         cyan          '{{ cyan }}'
  )
else
  typeset -gA _th=(
    accent        {{ x256(accent) }}      on_accent     {{ x256(fg_on(accent)) }}
    accent_alt    {{ x256(accent_alt) }}  on_accent_alt {{ x256(fg_on(accent_alt)) }}
    fg            {{ x256(foreground) }}  fg_bright     {{ x256(foreground_bright) }}
    muted         {{ x256(muted) }}       surface       {{ x256(surface) }}
    surface_alt   {{ x256(surface_alt) }} bg            {{ x256(background) }}
    red           {{ x256(red) }}         on_red        {{ x256(fg_on(red)) }}
    green         {{ x256(green) }}       on_green      {{ x256(fg_on(green)) }}
    yellow        {{ x256(yellow) }}      on_yellow     {{ x256(fg_on(yellow)) }}
    blue          {{ x256(blue) }}        on_blue       {{ x256(fg_on(blue)) }}
    magenta       {{ x256(magenta) }}     cyan          {{ x256(cyan) }}
  )
fi

# ── powerlevel10k ────────────────────────────────────────────────────────────

# os_icon — quiet plate, accent glyph. Deliberately not the loudest segment.
typeset -g POWERLEVEL9K_OS_ICON_BACKGROUND=$_th[surface_alt]
typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=$_th[accent]

# path — the one segment that gets the accent plate
typeset -g POWERLEVEL9K_DIR_BACKGROUND=$_th[accent]
typeset -g POWERLEVEL9K_DIR_FOREGROUND=$_th[on_accent]
typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=$_th[on_accent]
typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=$_th[on_accent]
typeset -g POWERLEVEL9K_DIR_NOT_WRITABLE_BACKGROUND=$_th[red]
typeset -g POWERLEVEL9K_DIR_NOT_WRITABLE_FOREGROUND=$_th[on_red]

# git — state is carried by the plate colour, which is the whole point
typeset -g POWERLEVEL9K_VCS_CLEAN_BACKGROUND=$_th[green]
typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=$_th[on_green]
typeset -g POWERLEVEL9K_VCS_MODIFIED_BACKGROUND=$_th[yellow]
typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=$_th[on_yellow]
typeset -g POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND=$_th[accent_alt]
typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=$_th[on_accent_alt]
typeset -g POWERLEVEL9K_VCS_CONFLICTED_BACKGROUND=$_th[red]
typeset -g POWERLEVEL9K_VCS_CONFLICTED_FOREGROUND=$_th[on_red]
typeset -g POWERLEVEL9K_VCS_LOADING_BACKGROUND=$_th[surface]
typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND=$_th[muted]

# command result — success stays quiet, failure is the loud one
typeset -g POWERLEVEL9K_STATUS_OK_BACKGROUND=$_th[surface]
typeset -g POWERLEVEL9K_STATUS_OK_FOREGROUND=$_th[green]
typeset -g POWERLEVEL9K_STATUS_OK_PIPE_BACKGROUND=$_th[surface]
typeset -g POWERLEVEL9K_STATUS_OK_PIPE_FOREGROUND=$_th[green]
typeset -g POWERLEVEL9K_STATUS_ERROR_BACKGROUND=$_th[red]
typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=$_th[on_red]
typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_BACKGROUND=$_th[red]
typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_FOREGROUND=$_th[on_red]
typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_BACKGROUND=$_th[red]
typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_FOREGROUND=$_th[on_red]

# prompt character
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_FOREGROUND=$_th[accent]
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VICMD_FOREGROUND=$_th[accent]
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIVIS_FOREGROUND=$_th[accent]
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIOWR_FOREGROUND=$_th[accent]
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_FOREGROUND=$_th[red]
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VICMD_FOREGROUND=$_th[red]
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIVIS_FOREGROUND=$_th[red]
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIOWR_FOREGROUND=$_th[red]

# secondary information — muted on a quiet plate
typeset -g POWERLEVEL9K_TIME_BACKGROUND=$_th[surface]
typeset -g POWERLEVEL9K_TIME_FOREGROUND=$_th[muted]
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_BACKGROUND=$_th[surface]
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=$_th[muted]
typeset -g POWERLEVEL9K_BACKGROUND_JOBS_BACKGROUND=$_th[surface]
typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=$_th[cyan]
typeset -g POWERLEVEL9K_CONTEXT_BACKGROUND=$_th[surface]
typeset -g POWERLEVEL9K_CONTEXT_FOREGROUND=$_th[cyan]
typeset -g POWERLEVEL9K_CONTEXT_ROOT_BACKGROUND=$_th[red]
typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=$_th[on_red]
typeset -g POWERLEVEL9K_VIRTUALENV_BACKGROUND=$_th[surface]
typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND=$_th[accent_alt]
typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX_FOREGROUND=$_th[muted]
typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX_FOREGROUND=$_th[muted]
typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_PREFIX_FOREGROUND=$_th[muted]

# ── companions ───────────────────────────────────────────────────────────────
# autosuggestions must read as dimmer than real input but still be legible —
# exactly the `muted` role. Uses a 256 index because zsh-syntax-highlighting
# styles take terminal colours, not hex.
typeset -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg={{ x256(muted) }}"

# fzf / fzf-tab
export FZF_DEFAULT_OPTS="--color=fg:{{ x256(foreground) }},fg+:{{ x256(foreground_bright) }},bg:-1,bg+:{{ x256(surface_alt) }},hl:{{ x256(accent) }},hl+:{{ x256(accent) }},info:{{ x256(muted) }},marker:{{ x256(green) }},prompt:{{ x256(accent) }},spinner:{{ x256(accent_alt) }},pointer:{{ x256(accent) }},header:{{ x256(muted) }},border:{{ x256(border) }}"

# So other tooling can react to light vs dark without re-parsing the palette.
export DESKTOP_THEME='{{ theme_slug }}'
export DESKTOP_THEME_MODE='{{ theme_mode }}'

unset _th

# Fish shell configuration

# ============================================================================
# Catppuccin Mocha Theme
# ============================================================================
# Syntax highlighting colors
set -g fish_color_normal cdd6f4
set -g fish_color_command 89b4fa
set -g fish_color_keyword cba6f7
set -g fish_color_quote a6e3a1
set -g fish_color_redirection f5c2e7
set -g fish_color_end fab387
set -g fish_color_error f38ba8
set -g fish_color_param f2cdcd
set -g fish_color_comment 6c7086
set -g fish_color_selection --background=313244
set -g fish_color_search_match --background=313244
set -g fish_color_operator f5c2e7
set -g fish_color_escape f2cdcd
set -g fish_color_autosuggestion 6c7086
set -g fish_color_cancel f38ba8
set -g fish_color_cwd f9e2af
set -g fish_color_user 94e2d5
set -g fish_color_host 89b4fa
set -g fish_color_host_remote a6e3a1
set -g fish_color_status f38ba8

# Pager colors
set -g fish_pager_color_progress 6c7086
set -g fish_pager_color_prefix cba6f7
set -g fish_pager_color_completion cdd6f4
set -g fish_pager_color_description 6c7086
set -g fish_pager_color_selected_background --background=313244

# ============================================================================
# Key bindings
# ============================================================================
# Ctrl+K to clear screen
bind \ck 'clear; commandline -f repaint'

# ============================================================================
# Aliases
# ============================================================================
# Source shared aliases if available
if test -f ~/.aliases
    source ~/.aliases
else
    echo "Warning: ~/.aliases not found; script aliases not loaded."
end

# Additional key bindings can be added here

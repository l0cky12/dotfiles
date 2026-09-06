# Convenience launchers. Preserve any command, alias, or function that already
# owns one of these names.
if ! whence -w -- ai >/dev/null 2>&1; then
  alias ai='ai-agent'
fi

if ! whence -w -- ai-claude >/dev/null 2>&1; then
  alias ai-claude='ai-agent --agent claude'
fi

if ! whence -w -- ai-codex >/dev/null 2>&1; then
  alias ai-codex='ai-agent --agent codex'
fi

if ! whence -w -- ai-opencode >/dev/null 2>&1; then
  alias ai-opencode='ai-agent --agent opencode'
fi

if ! whence -w -- ai-t3code >/dev/null 2>&1; then
  alias ai-t3code='ai-agent --agent t3code'
fi

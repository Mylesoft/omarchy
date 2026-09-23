#!/bin/bash
# Launch a specific Omarchy coding agent in a TUI without changing the default.
# Mirrors the unattended flags from omarchy-agent.

set -euo pipefail

agent="${1:-}"
if [[ -z $agent ]]; then
  echo "Usage: launch-agent.sh <agent-id>" >&2
  exit 1
fi

[[ $PWD == "$HOME" && -d $HOME/Work ]] && cd "$HOME/Work"

case "$agent" in
opencode)
  command=(opencode --auto)
  ;;
agy)
  command=(agy --dangerously-skip-permissions)
  ;;
copilot)
  command=(copilot --allow-all)
  ;;
crush)
  command=(crush --yolo)
  ;;
claude)
  command=(claude --permission-mode auto)
  ;;
grok)
  command=(grok --permission-mode bypassPermissions)
  ;;
openclaw)
  command=(omarchy-launch-openclaw --tui)
  ;;
codex)
  command=(codex --approve-for-me)
  ;;
cursor-agent)
  command=(cursor-agent --yolo --trust)
  ;;
hermes)
  command=(hermes --yolo)
  ;;
muse)
  command=(muse --approval-mode never)
  ;;
omp)
  command=(omp --auto-approve)
  ;;
ori)
  command=(ori code)
  ;;
pi)
  command=(pi)
  ;;
fireworks)
  # Usage / billing provider only — open the agent picker instead.
  exec omarchy-agent --pick
  ;;
*)
  echo "Unknown agent: $agent" >&2
  exit 1
  ;;
esac

if ! command -v "${command[0]}" >/dev/null 2>&1 && [[ ${command[0]} != omarchy-launch-openclaw ]]; then
  echo "${command[0]} is not installed" >&2
  exit 1
fi

exec omarchy-launch-tui --app-id=org.omarchy.agent "${command[@]}"

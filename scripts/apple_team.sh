# Sourced by the iOS archive scripts. Provides the Apple Developer team ID without it living in git.
#
# The team ID comes from the APPLE_TEAM_ID environment variable, or from signing.local.env at the repo root
# (gitignored; copy signing.local.env.example to create it).
#
#   require_apple_team                 exits with instructions if no team ID is available
#   export_options_with_team <plist>   prints the path of a temporary copy of an ExportOptions plist with
#                                      teamID filled in (the tracked plists deliberately omit it)

_APPLE_TEAM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${APPLE_TEAM_ID:-}" && -f "$_APPLE_TEAM_ROOT/signing.local.env" ]]; then
  # shellcheck disable=SC1091
  source "$_APPLE_TEAM_ROOT/signing.local.env"
fi

require_apple_team() {
  if [[ -z "${APPLE_TEAM_ID:-}" || "$APPLE_TEAM_ID" == "XXXXXXXXXX" ]]; then
    echo "No Apple Developer team ID. Copy signing.local.env.example to signing.local.env and set APPLE_TEAM_ID," >&2
    echo "or run with APPLE_TEAM_ID=<your team id> in the environment." >&2
    exit 1
  fi
  export APPLE_TEAM_ID
}

export_options_with_team() {
  local source_plist="$1"
  local with_team
  with_team="$(mktemp -t ExportOptions).plist"
  cp "$source_plist" "$with_team"
  /usr/libexec/PlistBuddy -c "Add :teamID string $APPLE_TEAM_ID" "$with_team" >/dev/null
  echo "$with_team"
}

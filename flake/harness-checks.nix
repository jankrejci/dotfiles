# Checks on the agent instruction files
#
# - claude-md-limit: CLAUDE.md stays within its line budget
# - instruction-paths: paths named in CLAUDE.md and .claude/ must exist
{
  pkgs,
  root,
}: let
  claudeMdMaxLines = 200;
in {
  # CLAUDE.md loads on every session and adherence drops as it grows. Detail that
  # does not fit moves to a path-scoped rule rather than the budget moving.
  claude-md-limit = pkgs.runCommand "claude-md-limit" {} ''
    lines=$(wc -l < ${root}/CLAUDE.md)
    echo "CLAUDE.md: $lines lines of ${toString claudeMdMaxLines}"
    [ "$lines" -le ${toString claudeMdMaxLines} ] || {
      echo "CLAUDE.md is over budget, move detail into .claude/rules/" >&2
      exit 1
    }
    touch $out
  '';

  # A stale path sends every later session looking for a file that is gone, and
  # nothing else in the flake reads these files, so nothing else would notice.
  instruction-paths = pkgs.runCommand "instruction-paths" {nativeBuildInputs = [pkgs.ripgrep];} ''
    cd ${root}
    failed=0
    # rg writes to a file first because a process substitution hides its exit
    # status, and a crash would look like a tree with no paths to check. Exit 1
    # only means no match.
    rg_status=0
    rg --no-heading --no-line-number --only-matching --replace '$1' '`([^` ]+)`' CLAUDE.md .claude --glob '*.md' > "$TMPDIR/tokens" || rg_status=$?
    [ "$rg_status" -le 1 ] || exit "$rg_status"
    while IFS=: read -r file token; do
      path=''${token%%:*}
      path=''${path%/}
      case "$path" in
        # Placeholders and shell syntax name no file. The service name is the
        # placeholder the authoring docs use for a module yet to be written.
        *'<'* | *'$'* | *'*'* | *'{'* | *'#'* | *'='* | *myservice*) continue ;;
        flake/* | homelab/* | modules/* | hosts/* | users/* | pkgs/* | scripts/* | docs/* | secrets/* | .claude/*)
          [ -e "$path" ] && continue
          ;;
        # A bare file name is written relative to whatever the text is about, so
        # it only has to exist somewhere in the tree.
        *.nix | *.md)
          [ -n "$(find . -name "$path" -print -quit)" ] && continue
          ;;
        *) continue ;;
      esac
      echo "$file: $path does not exist" >&2
      failed=1
    done < "$TMPDIR/tokens"
    [ "$failed" = 0 ] || exit 1
    touch $out
  '';
}

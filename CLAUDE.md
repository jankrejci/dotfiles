# Claude Code Agent Configuration

## Context
Home network infrastructure secured behind Netbird mesh VPN. Defense-in-depth: services on localhost, nginx TLS termination, firewall restricts to VPN interface.

## Role
Senior software engineer with 10+ years NixOS/functional programming experience.

## Core Principles
- **Simplicity First**: Simple and idiomatic solutions over clever ones
- **Check Docs First**: Always check existing documentation before building custom solutions
- **Nix Philosophy**: Reproducibility, declarative configuration, immutability
- **Code Quality**: Follow established patterns in codebase
- **Document Intent**: Write concise code comments explaining the why

## Critical Thinking
- **Question Everything**: Be skeptical of all suggestions
- **No Praise**: Evaluate ideas on technical merit only
- **Verify, Don't Trust**: Test assumptions through code/docs
- **Honest Disagreement**: Push back on suboptimal approaches
- **Self-Critique**: Question if your solution is truly simplest

## Working Style
- Read existing code patterns before making changes
- Use ripgrep/grep to understand codebase
- Prefer editing existing files over creating new ones
- Run `nix flake check` after changes
- Run `nix fmt` before committing
- Keep responses concise and action-oriented

**Safe commands:** Run these without user confirmation:
- `nix build*`, `nix eval*`, `nix flake check`, `nix flake show`
- `nix-store --query*`, `nix path-info*`, `nix why-depends*`
- `git status`, `git diff`, `git log`, `git show`
- **Avoid nesting**: Use guard clauses and early returns
- **Comments**: Write proper sentences, NEVER use parentheses for asides!!!
- **No size claims**: NEVER write MB/GB savings in comments

## Git Commit Format
```
module: Title in imperative style

- lowercase bullet describing implementation detail
- another bullet if needed
```

**Rules:**
- Title: capital letter after colon, imperative verb
- Body: bullet points only, lowercase start, NO prose paragraphs
- NO Co-Authored-By, NO Claude signatures, NO emojis

Split unrelated changes into separate commits.

**Atomic commits:** Each commit must:
- Pass `nix flake check` and `nix fmt`
- Be a single logical change that can be reviewed in isolation
- Build progressively toward the goal so history is easy to follow

Prefer too many small commits over too few during development. Commits will be
compacted before merge anyway, but reviewability during development matters.

**NEVER push to remote.** User will push when ready.

## Git Branch Cleanup
Before merging, consolidate the branch into clean logical commits:

**Cleanup Process:**
1. Create backup: `git branch backup-branch`
2. Soft reset: `git reset --soft origin/main`
3. Unstage all: `git reset HEAD -- .`
4. Commit in logical groups by file/feature
5. Verify: `nix flake check`

**Principles:**
- One logical change per commit
- Squash duplicate/related changes
- Drop commits that are immediately superseded
- Preserve struggle documentation in code comments, not commit history
- When commits are interleaved across files, soft reset is cleaner than rebase
- Always separate CLAUDE.md changes from code commits

**For scripted rebase** when commits are not interleaved:
```bash
GIT_SEQUENCE_EDITOR='script.sh' git rebase -i origin/main
```

## Shell Script Style
- Use `|| { }` pattern for guard clauses instead of nested if-else
- Avoid else branches whenever possible
- If disabling shellcheck, always add comment explaining why
- Use `local -r` for immutable local variables
- Helper functions should `exit 1` on fatal errors

## Communication Style
- Direct and concise
- Skip unnecessary explanations
- Technical terminology appropriate
- No praise/validation - objective evaluation only
- **No weasel words**: Never use "likely", "probably", "might be". Either you know the cause from evidence or you don't know. Say "I don't know" when uncertain.
- **Questions are questions**: When user asks "do we need X?" or "is this useful?", answer the question with analysis. Do not treat questions as implicit instructions to change code. Only explicit imperatives are instructions.

## Connectivity Safety
**CRITICAL: Never break your own access path**

Remote machines via VPN only:
- NEVER run `netbird down` while SSH'd via VPN
- NEVER delete peer from dashboard while needing remote access
- If changes affect connectivity: inform user, let them execute locally

**Before renaming interfaces, ports, or service identifiers:**
- Run `grep -r "old_name"` across the entire codebase
- Update ALL hardcoded references before deploying
- Firewall rules, systemd units, and nginx configs often have hardcoded names

## Netbird Architecture
Two-tier VPN setup for different access patterns:

**System client** (`netbird-homelab`, port 51820):
- Setup key enrollment, always running as system service
- For infrastructure: SSH, monitoring, node scraping
- Machine-based policies, no expiration
- Module: `modules/netbird-homelab.nix`
- Used by: servers via headless.nix, RPi via raspberry.nix

**User client** (`netbird-user`, port 51821):
- Runs as systemd user service on desktops
- SSO login via tray UI, user-based policies
- Module: `modules/netbird-user.nix`
- Used by: desktops via desktop.nix
- User must authenticate via tray UI before VPN works

**Module structure:**
- `networking.nix` - general networking, no netbird config
- `netbird-homelab.nix` - system client for servers/RPi
- `netbird-user.nix` - user client for desktops

**Limitation:** Cannot run both clients simultaneously due to routing table conflict.
See: https://github.com/netbirdio/netbird/issues/2023

### Declarative Configuration

Declarative Netbird API management was prototyped but abandoned for now. The approach
worked but had a fundamental limitation: peer IDs change on re-enrollment, making
automatic group membership sync impractical. Manual dashboard management is simpler
until Netbird supports stable peer identifiers or setup-key-based group assignment.

Future work: revisit when Netbird adds stable identifiers or setup key groups feature.

## Development Workflow

### Agents and Skills

**Agents** run in isolated contexts for heavy lifting:

| Agent | Role |
|-------|------|
| `analyze` | Research codebase, create implementation plan |
| `develop` | Implement changes according to plan |
| `verify` | Run checks, test, and review code quality |
| `deploy` | Deploy to target machine |

**Skills** are user-invoked workflows:

| Skill | Purpose |
|-------|---------|
| `/commit` | Create atomic commits with chunk-based staging |
| `/branch-cleanup` | Squash fixups before merge |
| `/new-service` | Create homelab service module from template |
| `/nix-dev` | Develop and debug Nix expressions |
| `/review-branch` | Review all branch changes against origin/main |

### Token Efficiency

Main agent responsibilities:
- Quick analysis to understand the task
- Delegate heavy work to agents
- Present results to user

Main agent must NOT:
- Read many files to understand codebase (delegate to analyze)
- Make multi-file changes directly (delegate to develop)

### Iterative Workflow

```
[1] Clarify → [2] Analyze → [3] Develop → [4] Commit → [5] User Review → [6] Deploy
                  ↑                            ↓              |
                  └────────────── fixup ───────┴──────────────┘
```

**Stage 1: Clarify**
- Ask questions if requirements are ambiguous
- For trivial tasks, skip to develop

**Stage 2: Analyze** (approval required)
- Invoke `analyze` agent for non-trivial tasks
- Present plan to user, wait for approval

**Stage 3: Develop**
- Invoke `develop` agent with approved plan
- Agent implements ONE logical change
- Agent runs `nix flake check`

**Stage 4: Commit**
- Use `/commit` skill or commit directly
- Create ONE commit for the logical change
- STOP for user review

**Stage 5: User Review**
- User reviews with tuicr or similar tool
- If changes needed → create fixup commit → return to review
- If approved → continue to next change or deploy

**Stage 6: Deploy** (approval required)
- Only if user requests
- Invoke `deploy` agent

### Fixup Workflow

After review feedback:
```bash
# Make fixes, then:
git commit --fixup=HEAD

# Before merge, user runs /branch-cleanup to squash
```

### Rules

- Work iteratively: one logical change → commit → review → repeat
- Use fixup commits for iterations, not branch reset
- NEVER batch many commits without user review between them
- NEVER push to remote
- Delegate heavy exploration to agents to save main context tokens

## Scripts
See `scripts.nix` for available commands. Key ones:
- `nix run .#deploy-config <hostname>` - Deploy config remotely
- `nix run .#build-sdcard <hostname>` - Build RPi SD card image

## Repository Structure

```
flake.nix              # Entry point, uses flake-parts
flake/                 # Flake-parts modules
  default.nix          # Imports all flake modules
  options.nix          # Flake and NixOS-level homelab options
  packages.nix         # perSystem: formatter, packages, checks
  hosts.nix            # Host definitions and nixosConfigurations
  deploy.nix           # deploy-rs node configuration
  images.nix           # ISO and SD card image builders
homelab/               # Service modules with homelab.X.enable pattern
modules/               # Base NixOS modules (common, ssh, networking)
hosts/                 # Host-specific configuration overrides
users/                 # User configurations
pkgs/                  # Custom packages
scripts.nix            # Deployment and utility scripts
```

**Flake-parts pattern:**
- `flake.nix` imports `./flake` which re-exports from submodules
- `perSystem` in `packages.nix` handles per-architecture outputs
- `flake.*` options in `options.nix` for cross-module data sharing
- Host config in `hosts.nix` injects `homelab.*` options into NixOS modules

**Adding a new service:**
1. Create `homelab/myservice.nix` with `homelab.myservice.enable` option
2. Add to `homelab/default.nix` imports
3. Enable in host definition in `flake/hosts.nix`

## LoRaWAN Gateway

See `homelab/lorawan-gateway.nix` for full GNSS architecture documentation.

Key finding: GPS time sync requires working GPIO14 for UART TX to send UBX
commands. Some RPi boards have dead GPIO14. Use RPi 3B, not 3B+.

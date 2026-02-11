# MCP server for retrieving health metrics from Runalyze.
# Requires a Runalyze premium account and personal API token.
#
# Register the server in Claude Code:
#   claude mcp add --scope user --transport stdio runalyze \
#     -e RUNALYZE_API_TOKEN=<your-token> \
#     -- $(nix build --no-link --print-out-paths '.#runalyze-mcp-server')/bin/runalyze-mcp-server
#
# Available tools: activities, activity details, HRV, sleep, resting heart rate.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchYarnDeps,
  fixup-yarn-lock,
  nodejs,
  yarn,
  makeWrapper,
}:
stdenvNoCC.mkDerivation rec {
  pname = "runalyze-mcp-server";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "floriankimmel";
    repo = "runalyze-mcp-server";
    rev = "1a4e847e94594e67160ccb7d777c2c40fc9f9d53";
    hash = "sha256-NTCqIRpp6JF9hiSdTCTYYpxRg9ba+BGg6AwSjgXpw+I=";
  };

  offlineCache = fetchYarnDeps {
    yarnLock = "${src}/yarn.lock";
    hash = "sha256-4Blwqri1XekAr1uo5k/7uldtAIRzfm/p2sW48DcrrF8=";
  };

  nativeBuildInputs = [yarn nodejs fixup-yarn-lock makeWrapper];

  configurePhase = ''
    runHook preConfigure
    export HOME=$TMPDIR
    yarn config --offline set yarn-offline-mirror $offlineCache
    fixup-yarn-lock yarn.lock
    yarn install --offline --frozen-lockfile --ignore-scripts --no-progress --non-interactive
    patchShebangs node_modules
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    yarn --offline build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/runalyze-mcp-server
    cp -r dist node_modules package.json $out/lib/runalyze-mcp-server/

    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/runalyze-mcp-server \
      --add-flags "$out/lib/runalyze-mcp-server/dist/main.js"
    runHook postInstall
  '';

  meta = {
    description = "MCP server for Runalyze health and fitness data";
    homepage = "https://github.com/floriankimmel/runalyze-mcp-server";
    license = lib.licenses.mit;
    mainProgram = "runalyze-mcp-server";
  };
}

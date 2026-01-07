# Import Google Keep notes to Memos with preserved timestamps.
# Usage: import-keep <memos_url> <access_token> <keep_folder>
{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "import-keep";
  version = "1.0.0";

  src = ./.;
  format = "other";

  propagatedBuildInputs = [python3Packages.requests];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp import_keep.py $out/bin/import-keep
    chmod +x $out/bin/import-keep

    runHook postInstall
  '';

  meta = {
    description = "Import Google Keep notes to Memos";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}

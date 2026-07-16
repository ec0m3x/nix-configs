{
  stdenv,
  autoPatchelfHook,
  fetchurl,
}:
stdenv.mkDerivation {
  pname = "wolow-companion";
  version = "1.0.0";

  src = fetchurl {
    url = "https://storage.jackbaker.dev/downloads/linux/wolow-companion-linux-amd64.tar.gz";
    sha256 = "G5kE1QARB2969Bd4Fh3I5/BvOyxM8vZwZbpt21MZHa4=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [autoPatchelfHook];

  installPhase = ''
    runHook preInstall

    install -Dm755 wolow-companion $out/bin/wolow-companion

    runHook postInstall
  '';

  meta = {
    description = "Wolow Companion - remote power management daemon for the Wolow Wake-on-LAN app";
    homepage = "https://wolow.site";
    platforms = ["x86_64-linux"];
  };
}

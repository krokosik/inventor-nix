{ wineWow64Packages, fetchurl }:
(wineWow64Packages.unstableFull.override { embedInstallers = false; }).overrideAttrs (old: {
  version = "11.4";
  src = fetchurl {
    url = "https://dl.winehq.org/wine/source/11.x/wine-11.4.tar.xz";
    hash = "sha256-GXCkY4HTvCxE1lHQgzY3Dkme64tT3JPL0c5UT3EV5Zg=";
  };
  patches = old.patches ++ [ ../patches/wbemprox-timezone.patch ];
})

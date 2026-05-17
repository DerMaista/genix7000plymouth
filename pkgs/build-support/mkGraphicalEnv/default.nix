{
  lib,
  buildFHSEnv,
  pkgs,
  mesa,
}:

oldDrv:
let
  prefer = primary: fallback: let p = lib.attrByPath primary null pkgs; in if p != null then p else lib.attrByPath fallback (throw "Missing dependency: ${lib.concatStringsSep "." primary} or ${lib.concatStringsSep "." fallback}") pkgs;

  mesaDrivers =
    _: [
      pkgs.mesa
      pkgs.libGL
      pkgs.libglvnd
      (prefer [ "libx11" ] [ "xorg" "libX11" ])
      (prefer [ "libxext" ] [ "xorg" "libXext" ])
      (prefer [ "libxdamage" ] [ "xorg" "libXdamage" ])
      (prefer [ "libxfixes" ] [ "xorg" "libXfixes" ])
      (prefer [ "libxi" ] [ "xorg" "libXi" ])
      (prefer [ "libxrandr" ] [ "xorg" "libXrandr" ])
      (prefer [ "libxrender" ] [ "xorg" "libXrender" ])
      pkgs.wayland
    ];
in
buildFHSEnv {
  inherit (oldDrv)
    pname
    version
    meta
    ;

  targetPkgs =
    pkgs':
    [
      (oldDrv.override (
        lib.filterAttrs (
          name: value: lib.any (path': name == path') (lib.attrNames oldDrv.override.__functionArgs)
        ) pkgs'
      ))
    ]
    ++ mesaDrivers pkgs';

  runScript = lib.getExe oldDrv;
  executableName = oldDrv.meta.mainProgram;

  profile = ''
    export LIBGL_DRIVERS_PATH=/run/opengl-driver/lib
    export LD_LIBRARY_PATH=/run/opengl-driver/lib:${lib.makeLibraryPath (mesaDrivers pkgs)}:$LD_LIBRARY_PATH
  '';

  extraInstallCommands = ''
    mkdir -p $out/run/opengl-driver
    ln -s ${mesa}/lib $out/run/opengl-driver/lib
  '';
}

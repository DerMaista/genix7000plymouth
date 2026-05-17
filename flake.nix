{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    genix7000 = {
      url = "github:DerMaista/genix7000";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      let
        lib' = nixpkgs.lib;
        defaultColors = [
          "#cd3535"
          "#cd6b35"
          "#cdb835"
          "#35cd62"
          "#35cdc1"
          "#3577cd"
          "#9a35cd"
        ];
        overlay = final: prev: {
          lib = lib'.recursiveUpdate prev.lib {
            types = final.callPackage "${self}/lib/types.nix" { };
          };
          mkGraphicalEnv = final.callPackage "${self}/pkgs/build-support/mkGraphicalEnv" { };
          openscad-unstable-fhs =
            final.callPackage "${self}/pkgs/by-name/openscad-unstable-fhs/package.nix"
              { };
          genix-to-image = prev.writeScriptBin "to-image" (
            builtins.replaceStrings
              [
                "./genix.scad"
                "openscad"
                "/usr/bin/env nu"
                "ffmpeg"
                "convert"
              ]
              [
                ("${inputs.genix7000}/genix.scad")
                (prev.lib.getExe final.openscad-unstable-fhs) # Latest stable (from 2021!) has a bug relevant to this project
                (prev.lib.getExe prev.nushell)
                (prev.lib.getExe prev.ffmpeg)
                (prev.lib.getExe' prev.imagemagick "convert")
              ]
              (builtins.readFile "${inputs.genix7000}/to-image.nu")
          );
          mkGenixFrameToImageArgs =
            { defaultFrameRate ? 15, defaultDuration ? 1 }:
            name: rawArgs:
            let
              # Extract internal fields before validation
              frameNum = rawArgs._frameNum or 0;
              totalFrames = rawArgs._totalFrames or 1;
              argsToValidate = builtins.removeAttrs rawArgs [ "_frameNum" "_totalFrames" "fps" "duration" ];
              args = validateArgs argsToValidate (
                mkGenixFrameArgsType {
                  inherit defaultFrameRate defaultDuration;
                }
              );
            in
            {
              animationEsc = builtins.replaceStrings ["$"] ["\\$"] (toString args.animation);
              toImageArgs = [
                "--num"
                (toString args.numLambdas)
                "--thick"
                (toString args.lambdaThickness)
                "--imgsize"
                "${toString args.imageWidth},${toString args.imageHeight}"
                "--offset"
                "${toString args.offsetX},${toString args.offsetY}"
                "--gaps"
                "${toString args.gapsX},${toString args.gapsY}"
                "--rotation"
                (toString args.rotation)
                "--angle"
                (toString args.angle)
                "--clipr"
                (toString args.clipRadius)
                "--cliprot"
                (toString args.clipRotation)
                "--clipinv"
                (if args.clipInverse then "true" else "false")
                "--rainbow"
                (if args.rainbow then "true" else "false")
                "--fps"
                (toString args.fps)
                "--duration"
                (toString args.duration)
                "--animation"
                (toString args.animation)
                "--frame-num"
                (toString frameNum)
                "--total-frames"
                (toString totalFrames)
                name
              ] ++ prev.lib.optionals (args.background != "") [
                "--background"
                args.background
              ] ++ args.colors;
              background = args.background;
            };
          mkGenixVideoToImageArgs =
            { defaultFrameRate ? 15, defaultDuration ? 1 }:
            name: rawArgs:
            let
              # Keep fps/duration controlled by mkGenixPlymouthTheme frameRate/duration.
              argsToValidate = builtins.removeAttrs rawArgs [ "fps" "duration" ];
              args = validateArgs argsToValidate (
                mkGenixFrameArgsType {
                  inherit defaultFrameRate defaultDuration;
                }
              );
            in
            {
              toImageArgs = [
                "--num"
                (toString args.numLambdas)
                "--thick"
                (toString args.lambdaThickness)
                "--imgsize"
                "${toString args.imageWidth},${toString args.imageHeight}"
                "--offset"
                "${toString args.offsetX},${toString args.offsetY}"
                "--gaps"
                "${toString args.gapsX},${toString args.gapsY}"
                "--rotation"
                (toString args.rotation)
                "--angle"
                (toString args.angle)
                "--clipr"
                (toString args.clipRadius)
                "--cliprot"
                (toString args.clipRotation)
                "--clipinv"
                (if args.clipInverse then "true" else "false")
                "--rainbow"
                (if args.rainbow then "true" else "false")
                "--fps"
                (toString args.fps)
                "--duration"
                (toString args.duration)
                "--animation"
                (toString args.animation)
                name
              ] ++ prev.lib.optionals (args.background != "") [
                "--background"
                args.background
              ] ++ args.colors;
            };
          mkGenixFrame =
            name: rawArgs:
            let
              frameSvg = builtins.replaceStrings [ ".png" ] [ ".svg" ] name;
              frameData = final.mkGenixFrameToImageArgs { } frameSvg rawArgs;
              toImageArgs = builtins.filter (
                arg: arg != "--background" && arg != frameData.background
              ) frameData.toImageArgs;
              animationEsc = frameData.animationEsc;
              in
            prev.runCommand name
              {
                nativeBuildInputs = [
                  final.genix-to-image
                  final.imagemagick
                ];
              }
              ''
                toImageArgs=()
                ${prev.lib.concatMapStringsSep "\n" (arg: "toImageArgs+=(" + prev.lib.escapeShellArg arg + ")") toImageArgs}
                to-image "''${toImageArgs[@]}"
                convert "${frameSvg}" $out
                if [[ -n "${frameData.background}" ]]; then
                  tmpPng="$out.tmp.png"
                  convert "$out" "$tmpPng"
                  convert "$tmpPng" -background "${frameData.background}" -flatten "$out"
                  rm "$tmpPng"
                fi
              '';
          mkGenixPlymouthTheme =
            {
              name,
              animation,
              duration,
              frameRate ? 15,
              baseArgs ? {},
            }:
            let
              frameCount = frameRate * duration;
              frameIndices = prev.lib.range 0 (frameCount - 1);
              frameCommands = builtins.concatStringsSep "\n" (
                map (
                  frame:
                  let
                    frameName = prev.lib.fixedWidthString 10 "0" (toString frame);
                    frameArgs = baseArgs // animation (frame / (frameRate + 0.0)) // {
                      _frameNum = frame + 1;
                      _totalFrames = frameCount;
                    };
                    frameData = final.mkGenixFrameToImageArgs {
                      defaultFrameRate = frameRate;
                      defaultDuration = duration;
                    } "frame-${frameName}.png" frameArgs;
                  in
                  ''
                    toImageArgs=()
                    ${prev.lib.concatMapStringsSep "\n" (arg: "toImageArgs+=(" + prev.lib.escapeShellArg arg + ")") frameData.toImageArgs}
                    (
                      cd "$themeDir"
                      to-image "''${toImageArgs[@]}"
                    )
                  ''
                )
                frameIndices
              );
              frameImages = builtins.concatStringsSep "\n" (
                map (
                  frame:
                  let
                    frameName = prev.lib.fixedWidthString 10 "0" (toString frame);
                  in
                  "frameImages[${toString frame}] = Image(\"frame-${frameName}.png\");"
                ) frameIndices
              );
              themeScript = ''
                # Generated by genix7000plymouth
                # Cycle through pre-rendered frame images.
                NUM = ${toString frameCount};
                SPEED = 1;

                ${frameImages}

                frameSprite = Sprite();
                frameSprite.SetX(Window.GetX() + (Window.GetWidth(0) / 2 - frameImages[0].GetWidth() / 2));
                frameSprite.SetY(Window.GetY() + (Window.GetHeight(0) / 2 - frameImages[0].GetHeight() / 2));

                progress = 0;

                fun refresh_callback ()
                {
                  frameSprite.SetImage(frameImages[Math.Int(progress / SPEED) % NUM]);
                  progress++;
                }

                Plymouth.SetRefreshFunction(refresh_callback);
                refresh_callback();
              '';
              themeScriptFile = prev.writeText "${name}.script" themeScript;
            in
            prev.runCommand name {
              nativeBuildInputs = [
                final.genix-to-image
                final.ffmpeg
              ];
            } (
              ''
                themeDir="$out/share/plymouth/themes/${name}"
                mkdir -p "$themeDir"

                ${frameCommands}

                ffmpeg -hide_banner -loglevel warning -framerate ${toString frameRate} -i "$themeDir/frame-%010d.png" "$themeDir/animation.mp4"
              ''
              + "\n"
              + ''
                cp ${themeScriptFile} "$themeDir/${name}.script"
                cat > "$themeDir/${name}.plymouth" <<EOF
                [Plymouth Theme]
                Name=${name}
                Description=Generated genix7000 theme
                Comment=Generated by genix7000plymouth
                ModuleName=script

                [script]
                ImageDir=$themeDir
                ScriptFile=$themeDir/${name}.script
                EOF
              ''
            );
        };
        # System doesn't matter here, only overlays do
        inherit (import nixpkgs { system = "x86_64-linux"; overlays = [ overlay ]; }) lib;
        validateArgs =
          args: argsType:
          (lib.evalModules {
            modules = [
              {
                options.args = lib.mkOption {
                  type = argsType;
                };
              }
              {
                config.args = args;
              }
            ];
          }).options.args.value;
        mkGenixFrameArgsType = { defaultFrameRate ? 15, defaultDuration ? 1 }:
          lib.types.submodule {
            options = {
              numLambdas = lib.mkOption {
                type = lib.types.int;
                default = 6;
                description = "Number of lambdas";
              };
              lambdaThickness = lib.mkOption {
                type = lib.types.int;
                default = 20;
                description = "Lambda thickness (unknown units)";
              };
              imageWidth = lib.mkOption {
                type = lib.types.int;
                default = 256;
                description = "Image width (in px)";
              };
              imageHeight = lib.mkOption {
                type = lib.types.int;
                default = 256;
                description = "Image height (in px)";
              };
              offsetX = lib.mkOption {
                type = lib.types.int;
                default = -24;
                description = "X offset of lambda (unknown units)";
              };
              offsetY = lib.mkOption {
                type = lib.types.int;
                default = -42;
                description = "Y offset of lambda (unknown units)";
              };
              gapsX = lib.mkOption {
                type = lib.types.int;
                default = 3;
                description = "X offset after clipping (use for gaps) (unknown units)";
              };
              gapsY = lib.mkOption {
                type = lib.types.int;
                default = -5;
                description = "Y offset after clipping (use for gaps) (unknown units)";
              };
              rotation = lib.mkOption {
                type = lib.types.int;
                default = 0;
                description = "Rotation of each lambda (in degrees)";
              };
              angle = lib.mkOption {
                type = lib.types.int;
                default = 30;
                description = "Lambda arm angle (in degrees)";
              };
              clipRadius = lib.mkOption {
                type = lib.types.int;
                default = 92;
                description = "Clipping n-gon radius (unknown units)";
              };
              clipRotation = lib.mkOption {
                type = lib.types.int;
                default = 0;
                description = "Clipping n-gon rotation (in degrees)";
              };
              clipInverse = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Reverse clipping order";
              };
              colors = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = defaultColors;
                description = "Color palette to use";
              };
              rainbow = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Animate lambdas through a rainbow loop (for video outputs)";
              };
              background = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Solid background color for video output (empty = transparent)";
              };
              fps = lib.mkOption {
                type = lib.types.int;
                default = defaultFrameRate;
                description = "Video frame rate (frames per second) when generating videos";
              };
              duration = lib.mkOption {
                type = lib.types.int;
                default = defaultDuration;
                description = "Video duration in seconds when generating videos";
              };
              animation = lib.mkOption {
                type = lib.types.str;
                default = "{ }";
                description = "Animation function (nu expression) used for video generation";
              };
            };
          };
      in
      {
        systems = nixpkgs.lib.platforms.linux;
        perSystem =
          {
            system,
            pkgs,
            lib,
            ...
          }:
          {
            _module.args.pkgs = import nixpkgs {
              inherit system;
              overlays = [ overlay ];
            };
            packages = {
              inherit (pkgs) openscad-unstable-fhs genix-to-image;
              testGenixFrame = pkgs.mkGenixFrame "test-genix-frame.png" { };
              testGenixPlymouthTheme = pkgs.mkGenixPlymouthTheme {
                name = "test-genix-plymouth-theme";
                animation = time: {
                  # Wait WTF nix doesn't have ANY common math stuff?!
                  lambdaThickness = builtins.floor (if time <= 1 then 20 + time * 10 else 20 + (2 - time) * 10);
                  rotation = builtins.floor (if time <= 1 then time * 180 else (2 - time) * 180);
                };
                frameRate = 30;
                duration = 4;
                baseArgs = {
                  rainbow = false;
                };
                
              };
            };
          };
        flake = {
          nixosModules = {
            genix7000 =
              {
                config,
                pkgs,
                lib,
                ...
              }:
                let
                  pkgs' = pkgs.extend overlay;
                in
                {
                options = {
                  boot.plymouth.genix7000 = {
                    enable = lib.mkEnableOption "automatically generated genix7000 boot animations";
                    numLambdas = lib.mkOption {
                      type = lib.types.int;
                      default = 6;
                      description = "Number of lambdas";
                    };
                    lambdaThickness = lib.mkOption {
                      type = lib.types.int;
                      default = 20;
                      description = "Lambda thickness (unknown units)";
                    };
                    imageWidth = lib.mkOption {
                      type = lib.types.int;
                      default = 256;
                      description = "Image width (in px)";
                    };
                    imageHeight = lib.mkOption {
                      type = lib.types.int;
                      default = 256;
                      description = "Image height (in px)";
                    };
                    offsetX = lib.mkOption {
                      type = lib.types.int;
                      default = -24;
                      description = "X offset of lambda (unknown units)";
                    };
                    offsetY = lib.mkOption {
                      type = lib.types.int;
                      default = -42;
                      description = "Y offset of lambda (unknown units)";
                    };
                    gapsX = lib.mkOption {
                      type = lib.types.int;
                      default = 3;
                      description = "X offset after clipping (use for gaps) (unknown units)";
                    };
                    gapsY = lib.mkOption {
                      type = lib.types.int;
                      default = -5;
                      description = "Y offset after clipping (use for gaps) (unknown units)";
                    };
                    rotation = lib.mkOption {
                      type = lib.types.int;
                      default = 0;
                      description = "Rotation of each lambda (in degrees)";
                    };
                    angle = lib.mkOption {
                      type = lib.types.int;
                      default = 30;
                      description = "Lambda arm angle (in degrees)";
                    };
                    clipRadius = lib.mkOption {
                      type = lib.types.int;
                      default = 92;
                      description = "Clipping n-gon radius (unknown units)";
                    };
                    clipRotation = lib.mkOption {
                      type = lib.types.int;
                      default = 0;
                      description = "Clipping n-gon rotation (in degrees)";
                    };
                    clipInverse = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = "Reverse clipping order";
                    };
                    colors = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = defaultColors;
                      description = "Color palette to use";
                    };
                    rainbow = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = "Animate lambdas through a rainbow loop (for video outputs)";
                    };
                    background = lib.mkOption {
                      type = lib.types.str;
                      default = "";
                      description = "Solid background color for video output (empty = transparent)";
                    };
                    animation = lib.mkOption {
                      type = lib.types.functionTo (lib.types.attrsOf lib.types.anything);
                      example = ''
                        time: {
                          lambdaThickness = builtins.floor (if time <= 1 then 20 + time * 10 else 20 + (2 - time) * 10);
                          rotation = builtins.floor (if time <= 1 then time * 180 else (2 - time) * 180);
                        };
                      '';
                      description = "A function that takes the frame time (0.0 to 1.0) and returns per-frame overrides (only fields you want to change)";
                    };
                    frameRate = lib.mkOption {
                      type = lib.types.int;
                      default = 15;
                      description = "The frame rate (in frames per second) of the animation";
                    };
                    duration = lib.mkOption {
                      type = lib.types.int;
                      example = 4;
                      description = "The length (in seconds) of the animation";
                    };
                    test = lib.mkOption {
                      type = lib.types.str;
                      default = "false";
                      description = "remove me pls";
                    };
                  };
                };
                config =
                  let
                    cfg = config.boot.plymouth.genix7000;
                      baseArgs = builtins.removeAttrs cfg [
                        "enable"
                        "animation"
                        "frameRate"
                        "duration"
                        "test"
                      ];
                  in
                  lib.mkIf cfg.enable {
                    boot.plymouth = {
                      themePackages = [
                        (pkgs'.mkGenixPlymouthTheme {
                          name = "genix7000-autogenerated-theme";
                            animation = cfg.animation;
                            baseArgs = baseArgs;
                          inherit (cfg) frameRate duration;
                        })
                      ];
                      theme = "genix7000-autogenerated-theme";
                      genix7000.test = builtins.concatStringsSep " " (
                        map lib.escapeShellArg (
                          (pkgs'.mkGenixFrameToImageArgs {
                            defaultFrameRate = cfg.frameRate;
                            defaultDuration = cfg.duration;
                            } "genix7000-test" (baseArgs // cfg.animation 0)).toImageArgs
                        )
                      );
                    };
                  };
              };
          };
        };
      }
    );
}

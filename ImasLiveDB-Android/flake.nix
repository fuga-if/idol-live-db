{
  description = "ImasLiveDB Android devShell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    { self, ... }@inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      perSystem =
        { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # Android SDK composition (SDK 35, build-tools 35.0.0, + emulator + system image)
          androidSdk = (pkgs.androidenv.override { licenseAccepted = true; }).composeAndroidPackages {
            platformVersions = [ "35" ];
            buildToolsVersions = [ "35.0.0" ];
            includeEmulator = true;
            includeSystemImages = true;
            abiVersions = [ "x86_64" ];
          };
        in
        {
          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.jdk17
              androidSdk.androidsdk
              pkgs.kotlin-language-server
            ];

            CLOUDKIT_API_TOKEN = "";

            shellHook = ''
              export ANDROID_HOME=${androidSdk.androidsdk}/libexec/android-sdk
              export ANDROID_SDK_ROOT=${androidSdk.androidsdk}/libexec/android-sdk
              export JAVA_HOME=${pkgs.jdk17}
              export GRADLE_USER_HOME=$(pwd)/.gradle
              echo "🍀 Android devShell activated"
              echo "   ANDROID_HOME=$ANDROID_HOME"
              echo "   JAVA_HOME=$JAVA_HOME"
            '';
          };
        };
    };
}

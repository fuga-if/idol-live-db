{
  description = "ImasLiveDB development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    swift-overlay.url = "github:Comamoca/swift-overlay";
  };

  outputs =
    { self, ... }@inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      # swift-overlay の対応システムに合わせる (x86_64-darwin は overlay が廃止)
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem =
        { pkgs, system, ... }:
        let
          # Cross-platform Swift ツール (Linux / macOS 両方で使える)
          # swift.bin.latest は swift-overlay が提供 (Swift 6.3.3)
          # swiftpm / sourcekit-lsp / swift-format は Swift 6.3.3 配布物に同梱されているため、
          # nixpkgs 版を入れると Swift 5.x のビルドがトリガーされるので使わない。
          swiftPkgs = [
            inputs.swift-overlay.packages.${system}.default   # Swift 6.3.3 (swift, swift-format, sourcekit-lsp, swift-package 等同梱)
          ] ++ (with pkgs; [
            swiftlint                                         # 静的解析 (pre-built binary, Swift 5 をビルドしない)
          ]);

          # macOS 専用ツール (Xcode 依存)
          macOnlyPkgs = with pkgs; [
            xcodegen        # Xcode プロジェクト生成 (project.yml → .xcodeproj)
          ];

          # 全プラットフォーム向け共通ツール
          commonPkgs = with pkgs; [
            nodejs
            python3
            sqlite
            nixd
            typescript-language-server
          ];
        in
        {
          devShells.default = pkgs.mkShell {
            packages = commonPkgs
              ++ swiftPkgs
              ++ pkgs.lib.optionals pkgs.stdenv.isDarwin macOnlyPkgs;

            shellHook = ''
              echo "🍀 ImasLiveDB devShell activated"
              echo "   Platform : ${pkgs.stdenv.system}"
              echo "   Node.js  : $(node --version 2>/dev/null || echo 'N/A')"
              echo "   Python   : $(python3 --version 2>/dev/null || echo 'N/A')"
              echo "   SQLite   : $(sqlite3 --version 2>/dev/null || echo 'N/A')"
              echo "   Swift    : $(swift --version 2>/dev/null | head -1 || echo 'N/A')"
              ${pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
                echo "   XcodeGen : $(xcodegen --version 2>/dev/null || echo 'N/A')"
              ''}
            '';
          };
        };
    };
}

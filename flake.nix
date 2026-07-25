{
  description = "ImasLiveDB development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    { self, ... }@inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      perSystem =
        { pkgs, ... }:
        let
          # Cross-platform Swift ツール (Linux / macOS 両方で使える)
          swiftPkgs = with pkgs; [
            swift           # コンパイラ (nixpkgs は 5.10.1)
            swiftpm         # Swift Package Manager
            sourcekit-lsp   # LSP (コード補完・診断)
            swift-format    # フォーマッター
            swiftlint       # 静的解析
          ];

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

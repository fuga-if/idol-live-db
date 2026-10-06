//! P名刺の名前の書体のファイルが、コアの一覧 (`card_name_fonts`・`card_designs`) と揃っていること。
//!
//! 書体のファイルは `tools/build_card_name_fonts.py` が作り、iOS / Android / Web が同じものを
//! 同梱する。一覧に書体を足したのにファイルを作り忘れる・PostScript 名を間違える
//! (端末で書体が引けず、黙って既定の書体で出る) を、ここで止める。

use std::path::PathBuf;

use imas_core::domain::producer_card::{card_designs, card_name_fonts, CardNameFont};

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..")
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack.windows(needle.len()).any(|w| w == needle)
}

#[test]
fn app_fonts_exist_with_postscript_names() {
    for info in card_name_fonts() {
        let path = repo()
            .join("fonts/card-name")
            .join(format!("{}.ttf", info.file_stem));
        let bytes = std::fs::read(&path).unwrap_or_else(|_| panic!("{} が無い", path.display()));
        // name 表は Mac (ASCII) か Windows (UTF-16BE) のどちらかで PostScript 名を持つ。
        let utf16: Vec<u8> = info
            .postscript_name
            .encode_utf16()
            .flat_map(|u| u.to_be_bytes())
            .collect();
        assert!(
            contains(&bytes, info.postscript_name.as_bytes()) || contains(&bytes, &utf16),
            "{} に PostScript 名 {} が無い",
            path.display(),
            info.postscript_name
        );
    }
}

#[test]
fn web_styles_cover_every_font_and_design() {
    let faces = std::fs::read_to_string(repo().join("web/src/styles/card-fonts.css"))
        .expect("card-fonts.css");
    let components = std::fs::read_to_string(repo().join("web/src/styles/components.css"))
        .expect("components.css");
    for info in card_name_fonts() {
        if info.font != CardNameFont::default() {
            assert!(
                faces.contains(&format!("'IMAS Card {}'", info.key)),
                "card-fonts.css に IMAS Card {} が無い",
                info.key
            );
        }
    }
    // Web は自作の画像を持たない (QR に画像は入らない) ので、自作の画像は入場証で描く。
    for info in card_designs().into_iter().filter(|d| !d.uses_face_image) {
        assert!(
            components.contains(&format!("[data-design=\"{}\"]", info.key)),
            "components.css に data-design=\"{}\" が無い",
            info.key
        );
    }
}

/// 使わなくなった書体を同梱し続けない (アプリ・Web の容量)。
#[test]
fn no_unused_fonts_are_bundled() {
    let stems: Vec<String> = card_name_fonts().into_iter().map(|f| f.file_stem).collect();
    for entry in std::fs::read_dir(repo().join("fonts/card-name")).expect("fonts/card-name") {
        let name = entry.unwrap().file_name().into_string().unwrap();
        if let Some(stem) = name.strip_suffix(".ttf") {
            assert!(
                stems.iter().any(|s| s == stem),
                "使っていない書体 {name} が残っている"
            );
        }
    }
    let keys: Vec<String> = card_name_fonts().into_iter().map(|f| f.key).collect();
    for entry in std::fs::read_dir(repo().join("web/public/fonts/card")).expect("web fonts") {
        let name = entry.unwrap().file_name().into_string().unwrap();
        assert!(
            keys.contains(&name),
            "使っていない Web の書体 {name} が残っている"
        );
    }
}

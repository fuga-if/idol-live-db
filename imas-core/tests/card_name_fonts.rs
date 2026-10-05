//! P名刺の名前の書体のファイルが、コアの一覧 (`card_name_fonts`) と揃っていること。
//!
//! 書体のファイルは `tools/build_card_name_fonts.py` が作り、iOS / Android / Web が同じものを
//! 同梱する。一覧に書体を足したのにファイルを作り忘れる・PostScript 名を間違える
//! (端末で書体が引けず、黙って既定の書体で出る) を、ここで止める。

use std::path::PathBuf;

use imas_core::domain::producer_card::{card_name_fonts, CardNameFont};

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
fn web_styles_cover_every_font() {
    let faces = std::fs::read_to_string(repo().join("web/src/styles/card-fonts.css"))
        .expect("card-fonts.css");
    let components = std::fs::read_to_string(repo().join("web/src/styles/components.css"))
        .expect("components.css");
    for info in card_name_fonts() {
        assert!(
            components.contains(&format!("[data-font=\"{}\"]", info.key)),
            "components.css に data-font=\"{}\" が無い",
            info.key
        );
        if info.font != CardNameFont::default() {
            assert!(
                faces.contains(&format!("'IMAS Card {}'", info.key)),
                "card-fonts.css に IMAS Card {} が無い",
                info.key
            );
        }
    }
}

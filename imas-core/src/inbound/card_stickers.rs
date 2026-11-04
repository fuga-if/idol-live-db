//! 名刺の表に置く素材の FFI 面。ロジックは domain::card_stickers。

use crate::domain::card_stickers::CardSticker;

#[uniffi::export]
pub fn card_stickers_max() -> u32 {
    crate::domain::card_stickers::MAX_CARD_STICKERS as u32
}

#[uniffi::export]
pub fn card_sticker_clamp(sticker: CardSticker) -> CardSticker {
    crate::domain::card_stickers::card_sticker_clamp(&sticker)
}

#[uniffi::export]
pub fn card_stickers_normalize(stickers: Vec<CardSticker>) -> Vec<CardSticker> {
    crate::domain::card_stickers::card_stickers_normalize(&stickers)
}

#[uniffi::export]
pub fn card_stickers_add(stickers: Vec<CardSticker>, id: String) -> Vec<CardSticker> {
    crate::domain::card_stickers::card_stickers_add(&stickers, &id)
}

#[uniffi::export]
pub fn card_stickers_update(stickers: Vec<CardSticker>, sticker: CardSticker) -> Vec<CardSticker> {
    crate::domain::card_stickers::card_stickers_update(&stickers, &sticker)
}

#[uniffi::export]
pub fn card_stickers_remove(stickers: Vec<CardSticker>, id: String) -> Vec<CardSticker> {
    crate::domain::card_stickers::card_stickers_remove(&stickers, &id)
}

#[uniffi::export]
pub fn card_stickers_bring_to_front(stickers: Vec<CardSticker>, id: String) -> Vec<CardSticker> {
    crate::domain::card_stickers::card_stickers_bring_to_front(&stickers, &id)
}

#[uniffi::export]
pub fn card_stickers_to_json(stickers: Vec<CardSticker>) -> String {
    crate::domain::card_stickers::card_stickers_to_json(&stickers)
}

#[uniffi::export]
pub fn card_stickers_from_json(json: String) -> Vec<CardSticker> {
    crate::domain::card_stickers::card_stickers_from_json(&json)
}

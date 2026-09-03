/**
 * 部品が「読むフィールドだけ」を宣言した構造的な型。
 *
 * ページ / DTO の型は `src/lib/schema/**` (imas-core の DTO から ts-rs が生成) が正で、
 * 部品はそちらを直接 import する。ここに残すのは、`Ref` 丸ごとではなく素の値
 * (名前・モノグラム・themeKey) だけを受ける葉の部品のための最小限の型。
 * **値の作り方 (join / filter / sort / 色の決定) はここにも部品にも書かない (INV-1)。**
 */

/** `Ref` の部分集合。行や札の描画に必要な分だけ。`Ref` はこれを満たす。 */
export interface RefLike {
  readonly name: string;
  readonly path: string;
  readonly sub?: string | null;
  readonly themeKey?: string;
  readonly artworkUrl?: string | null;
  readonly monogram?: string | null;
}

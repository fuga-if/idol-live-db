/**
 * 部品が「読むフィールドだけ」を宣言した構造的な型。
 *
 * 正のスキーマは `src/lib/schema/**` (imas-core の DTO から ts-rs が生成) で、
 * ここはその部分集合を構造的に受けるための受け皿にすぎない。
 * **値の作り方 (join / filter / sort / 色の決定) はここにも部品にも書かない (INV-1)。**
 */

/** 他ページへのリンク 1 個。`path` は Rust が encode 済みで出す完成形 URL。 */
export interface RefLike {
  readonly name: string;
  readonly path: string;
  readonly kind?: string;
  readonly sub?: string | null;
  readonly themeKey?: string;
  readonly artworkUrl?: string | null;
  readonly monogram?: string | null;
}

/** パンくず 1 段。 */
export interface CrumbLike {
  readonly name: string;
  readonly path: string;
}

/** ページの SEO ブロック。文面も robots も canonical も Rust が決める。 */
export interface SeoLike {
  readonly title: string;
  readonly description: string;
  readonly canonical: string;
  readonly ogImage: string;
  readonly robots?: string;
  readonly jsonLd?: unknown;
  readonly breadcrumbs?: readonly CrumbLike[];
}

/** 「アプリで開く」導線。 */
export interface AppOpenLike {
  readonly appStoreUrl: string;
  readonly deeplink?: string | null;
  readonly deeplinkKind?: string | null;
  readonly note: string;
}

/** 現在地つきの切替リンク (ブランド / 年 / 都道府県…)。選択状態は URL が持つ。 */
export interface NavLinkLike {
  readonly name: string;
  readonly path: string;
  readonly current?: boolean;
  readonly count?: number | null;
}

/** サイト共通の外部リンク。値の出所は `meta.json` の `app` (Rust が出す)。 */
export interface AppLinksLike {
  readonly appStoreUrl: string;
  readonly hashtag: string;
  readonly privacyUrl: string;
  readonly supportUrl: string;
  readonly termsUrl: string;
  readonly repositoryUrl: string;
}

/** レイアウトが読む `meta.json` の部分集合。 */
export interface SiteMetaLike {
  readonly todayJst: string;
  readonly generatedAt: string;
  readonly dataVersion?: string | null;
  readonly app: AppLinksLike;
}

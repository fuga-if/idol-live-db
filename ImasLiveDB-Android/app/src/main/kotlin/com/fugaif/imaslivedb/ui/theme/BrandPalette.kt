package com.fugaif.imaslivedb.ui.theme

// iOS の `BrandPalette` および master.sqlite の `brands.color` と一致させる。
object BrandPalette {
    private val colors = mapOf(
        "765as" to "#fe0000",
        "961" to "#520000",
        "876" to "#656a75",
        "cg" to "#2681c8",
        "ml" to "#ffc30b",
        "sidem" to "#0fbe94",
        "sc" to "#6bb6b9",
        "gakuen" to "#f39800",
        "other" to "#8e8e93"
    )

    /** 既知ブランドのhex。未知またはnullならnull。 */
    fun hex(brandId: String?): String? = colors[brandId]
}

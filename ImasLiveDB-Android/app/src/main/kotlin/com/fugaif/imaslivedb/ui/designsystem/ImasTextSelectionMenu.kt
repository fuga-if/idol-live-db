package com.fugaif.imaslivedb.ui.designsystem

import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.TextToolbar
import androidx.compose.ui.platform.TextToolbarStatus
import androidx.compose.ui.text.TextRange

/**
 * 文字を選んだときのメニュー (切り取り・コピーの並び) に足す項目 (iOS `ImasTextSelectionAction`)。
 * 押すと選んでいる範囲 (UTF-16 の位置) を渡す。
 */
class ImasTextSelectionAction(val title: String, val onClick: (TextRange) -> Unit)

/**
 * 入力欄の選択メニューに [ImasTextSelectionAction] を足す [TextToolbar]。Compose 既定の
 * (`AndroidTextToolbar`) と同じく浮く ActionMode で出し、字を選んでいるときだけ足した項目を先頭に置く。
 * [selection] はメニューを押した時点の選択を読む。
 */
internal class ImasTextSelectionToolbar(
    private val view: View,
    var actions: List<ImasTextSelectionAction>,
    var selection: () -> TextRange
) : TextToolbar {
    private var actionMode: ActionMode? = null
    private var rect = Rect.Zero
    private var onCopy: (() -> Unit)? = null
    private var onPaste: (() -> Unit)? = null
    private var onCut: (() -> Unit)? = null
    private var onSelectAll: (() -> Unit)? = null

    override var status: TextToolbarStatus = TextToolbarStatus.Hidden
        private set

    override fun showMenu(
        rect: Rect,
        onCopyRequested: (() -> Unit)?,
        onPasteRequested: (() -> Unit)?,
        onCutRequested: (() -> Unit)?,
        onSelectAllRequested: (() -> Unit)?
    ) {
        this.rect = rect
        onCopy = onCopyRequested
        onPaste = onPasteRequested
        onCut = onCutRequested
        onSelectAll = onSelectAllRequested
        val mode = actionMode
        if (mode == null) {
            status = TextToolbarStatus.Shown
            actionMode = view.startActionMode(callback, ActionMode.TYPE_FLOATING)
        } else {
            mode.invalidate()
            mode.invalidateContentRect()
        }
    }

    override fun hide() {
        status = TextToolbarStatus.Hidden
        actionMode?.finish()
        actionMode = null
    }

    private val callback = object : ActionMode.Callback2() {
        override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean = true

        override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean {
            menu.clear()
            var order = 0
            // 足した項目は字を選んでいるとき (コピーできるとき) だけ出す。
            if (onCopy != null) {
                actions.forEachIndexed { index, action ->
                    menu.add(Menu.NONE, EXTRA_BASE + index, order++, action.title)
                        .setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
                }
            }
            onCut?.let { menu.add(Menu.NONE, ID_CUT, order++, android.R.string.cut) }
            onCopy?.let { menu.add(Menu.NONE, ID_COPY, order++, android.R.string.copy) }
            onPaste?.let { menu.add(Menu.NONE, ID_PASTE, order++, android.R.string.paste) }
            onSelectAll?.let { menu.add(Menu.NONE, ID_SELECT_ALL, order++, android.R.string.selectAll) }
            return true
        }

        override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
            when (val id = item.itemId) {
                ID_CUT -> onCut?.invoke()
                ID_COPY -> onCopy?.invoke()
                ID_PASTE -> onPaste?.invoke()
                ID_SELECT_ALL -> onSelectAll?.invoke()
                else -> actions.getOrNull(id - EXTRA_BASE)?.onClick?.invoke(selection())
            }
            mode.finish()
            return true
        }

        override fun onDestroyActionMode(mode: ActionMode) {
            actionMode = null
            status = TextToolbarStatus.Hidden
        }

        override fun onGetContentRect(mode: ActionMode, view: View, outRect: android.graphics.Rect) {
            outRect.set(rect.left.toInt(), rect.top.toInt(), rect.right.toInt(), rect.bottom.toInt())
        }
    }

    private companion object {
        const val ID_CUT = 1
        const val ID_COPY = 2
        const val ID_PASTE = 3
        const val ID_SELECT_ALL = 4
        const val EXTRA_BASE = 100
    }
}

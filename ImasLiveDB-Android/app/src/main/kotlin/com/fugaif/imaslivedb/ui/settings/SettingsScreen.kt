package com.fugaif.imaslivedb.ui.settings

import android.content.pm.PackageManager
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("設定") })
        }
    ) { innerPadding ->
        if (state.isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
            return@Scaffold
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            // フィルタ設定
            item {
                SettingsSectionTitle("フィルタ設定")
                DefaultBrandPicker(
                    brands = state.brands,
                    onBrandSelected = { /* SharedPreferences を直接更新 */ }
                )
                HorizontalDivider()
            }

            // データ
            item {
                SettingsSectionTitle("データ")
                SettingsInfoRow("スキーマバージョン", state.schemaVersion)
                SettingsInfoRow("データバージョン", state.dataVersion)
                HorizontalDivider()
            }

            // データ統計
            state.databaseStats?.let { stats ->
                item {
                    SettingsSectionTitle("データ統計")
                    SettingsInfoRow("楽曲数", "${stats.songCount}曲")
                    SettingsInfoRow("アイドル数", "${stats.idolCount}人")
                    SettingsInfoRow("イベント数", "${stats.eventCount}件")
                    SettingsInfoRow("公演数", "${stats.showCount}公演")
                    HorizontalDivider()
                }
            }

            // クレジット
            item {
                SettingsSectionTitle("クレジット")
                CreditText("本アプリは株式会社バンダイナムコエンターテインメント様とは一切関係のない非公式ファンメイドアプリです。")
                CreditText("キャラクターデータ: im@sparql")
                CreditText("楽曲・ライブ等のデータ参照元: アイマスDB (https://imas-db.jp/) ※独自に集計・整形しています")
                val version = try {
                    context.packageManager.getPackageInfo(context.packageName, 0).versionName
                } catch (_: PackageManager.NameNotFoundException) {
                    null
                }
                version?.let { SettingsInfoRow("アプリバージョン", it) }
                HorizontalDivider()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DefaultBrandPicker(
    brands: List<com.fugaif.imaslivedb.data.model.Brand>,
    onBrandSelected: (String?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    var selectedLabel by rememberSaveable { mutableStateOf("すべて") }

    val allItems = listOf(null to "すべて") + brands.map { it.id to it.shortName }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        OutlinedTextField(
            value = selectedLabel,
            onValueChange = {},
            readOnly = true,
            label = { Text("デフォルトブランド") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor()
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            allItems.forEach { (id, label) ->
                DropdownMenuItem(
                    text = { Text(label) },
                    onClick = {
                        selectedLabel = label
                        onBrandSelected(id)
                        expanded = false
                    }
                )
            }
        }
    }
}

@Composable
private fun SettingsSectionTitle(title: String) {
    com.fugaif.imaslivedb.ui.components.ImasSectionHeader(title = title, tight = true)
}

@Composable
private fun SettingsInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f)
        )
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
    HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
}

@Composable
private fun CreditText(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
    )
}

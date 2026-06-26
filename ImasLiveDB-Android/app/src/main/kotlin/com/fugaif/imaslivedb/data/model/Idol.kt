package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "idols")
data class Idol(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "brand_id")
    val brandId: String,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "name_kana")
    val nameKana: String?,

    @ColumnInfo(name = "name_romaji")
    val nameRomaji: String?,

    @ColumnInfo(name = "color")
    val color: String?,

    @ColumnInfo(name = "sort_order")
    val sortOrder: Int,

    @ColumnInfo(name = "birthday")
    val birthday: String?,

    @ColumnInfo(name = "blood_type")
    val bloodType: String?,

    @ColumnInfo(name = "height")
    val height: Double?,

    @ColumnInfo(name = "weight")
    val weight: Double?,

    @ColumnInfo(name = "birth_place")
    val birthPlace: String?,

    @ColumnInfo(name = "age")
    val age: Int?,

    @ColumnInfo(name = "bust")
    val bust: Double?,

    @ColumnInfo(name = "waist")
    val waist: Double?,

    @ColumnInfo(name = "hip")
    val hip: Double?,

    @ColumnInfo(name = "constellation")
    val constellation: String?,

    @ColumnInfo(name = "hobbies")
    val hobbies: String?,

    @ColumnInfo(name = "talents")
    val talents: String?,

    @ColumnInfo(name = "description")
    val description: String?,

    @ColumnInfo(name = "gender")
    val gender: String?,

    @ColumnInfo(name = "handedness")
    val handedness: String?
)

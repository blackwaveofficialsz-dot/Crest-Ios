package com.blackwave.crest.feature.home

internal fun canSubmitPassword(hasPassword: Boolean, current: String, new: String, confirmation: String): Boolean =
    (!hasPassword || current.isNotEmpty()) && new.length in 7..16 && new == confirmation

internal fun passwordValidationMessage(new: String, confirmation: String): String? = when {
    new.isNotEmpty() && new.length !in 7..16 -> "新密码长度需为 7 至 16 位"
    confirmation.isNotEmpty() && new != confirmation -> "两次输入的新密码不一致"
    else -> null
}

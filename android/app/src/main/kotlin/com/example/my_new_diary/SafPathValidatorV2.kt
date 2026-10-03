package com.example.my_new_diary

internal object SafPathValidatorV2 {
    fun requireSafeName(value: String?, requireJson: Boolean): String {
        if (value.isNullOrEmpty() || value == "." || value == ".." ||
            value.contains('/') || value.contains('\\') || value.contains("://") ||
            (requireJson && !value.endsWith(".json"))) {
            throw IllegalArgumentException("Unsafe sync filename.")
        }
        return value
    }
}

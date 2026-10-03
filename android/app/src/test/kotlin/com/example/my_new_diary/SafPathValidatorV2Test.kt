package com.example.my_new_diary

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class SafPathValidatorV2Test {
    @Test
    fun acceptsProtocolLeafNames() {
        assertEquals("entry.json", SafPathValidatorV2.requireSafeName("entry.json", true))
        assertEquals("image.jpg", SafPathValidatorV2.requireSafeName("image.jpg", false))
    }

    @Test
    fun rejectsTraversalUrisAndNestedPaths() {
        listOf("../entry.json", "folder/entry.json", "folder\\entry.json", "file://entry.json")
            .forEach { value ->
                assertThrows(IllegalArgumentException::class.java) {
                    SafPathValidatorV2.requireSafeName(value, value.endsWith(".json"))
                }
            }
    }
}

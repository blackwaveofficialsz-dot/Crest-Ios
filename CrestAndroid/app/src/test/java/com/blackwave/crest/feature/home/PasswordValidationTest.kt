package com.blackwave.crest.feature.home

import org.junit.Assert.*
import org.junit.Test

class PasswordValidationTest {
    @Test fun existingPasswordRequiresCurrentPasswordAndMatchingConfirmation() {
        assertFalse(canSubmitPassword(true, "", "1234567", "1234567"))
        assertFalse(canSubmitPassword(true, "current", "1234567", "7654321"))
        assertTrue(canSubmitPassword(true, "current", "1234567", "1234567"))
        assertTrue(canSubmitPassword(false, "", "1234567", "1234567"))
    }

    @Test fun acceptsOnlySevenThroughSixteenCharactersWithoutTruncatingInput() {
        for (length in listOf(0, 6, 7, 16, 17)) {
            val password = "x".repeat(length)
            assertEquals(length in 7..16, canSubmitPassword(false, "", password, password))
        }
    }

    @Test fun validationMatchesIOSPriorityAndDoesNotWarnOnUntouchedFields() {
        assertNull(passwordValidationMessage("", ""))
        assertEquals("新密码长度需为 7 至 16 位", passwordValidationMessage("short", "different"))
        assertEquals("两次输入的新密码不一致", passwordValidationMessage("1234567", "different"))
        assertNull(passwordValidationMessage("1234567", ""))
        assertNull(passwordValidationMessage("1234567", "1234567"))
    }
}

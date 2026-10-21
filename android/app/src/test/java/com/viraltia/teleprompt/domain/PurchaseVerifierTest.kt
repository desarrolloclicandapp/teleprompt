package com.viraltia.teleprompt.domain

import org.junit.Assert.*
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64

class PurchaseVerifierTest {
    @Test fun rejectsTamperedReceiptsAndOtherKeys() {
        val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val other = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val receipt = "{\"productId\":\"lifetime_unlock\",\"purchaseState\":0}"
        val signature = Signature.getInstance("SHA1withRSA").run {
            initSign(pair.private); update(receipt.toByteArray()); Base64.getEncoder().encodeToString(sign())
        }
        val publicKey = Base64.getEncoder().encodeToString(pair.public.encoded)
        assertTrue(PurchaseVerifier.verify(publicKey, receipt, signature))
        assertFalse(PurchaseVerifier.verify(publicKey, receipt + " ", signature))
        assertFalse(PurchaseVerifier.verify(Base64.getEncoder().encodeToString(other.public.encoded), receipt, signature))
    }
    @Test fun absentConfigurationNeverUnlocks() {
        assertFalse(PurchaseVerifier.verify("", "receipt", "signature"))
        assertFalse(PurchaseVerifier.verify("invalid", "receipt", "invalid"))
    }
}

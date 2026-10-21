package com.viraltia.teleprompt.domain

import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

object PurchaseVerifier {
    fun verify(publicKey: String, receipt: String, signature: String): Boolean {
        if (publicKey.isBlank() || receipt.isBlank() || signature.isBlank()) return false
        return try {
            val key = KeyFactory.getInstance("RSA").generatePublic(
                X509EncodedKeySpec(Base64.getDecoder().decode(publicKey)))
            Signature.getInstance("SHA1withRSA").run {
                initVerify(key); update(receipt.toByteArray(Charsets.UTF_8))
                verify(Base64.getDecoder().decode(signature))
            }
        } catch (_: Exception) { false }
    }
}

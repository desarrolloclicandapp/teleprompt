package com.viraltia.teleprompt.data

import android.content.Context
import com.android.billingclient.api.Purchase
import com.viraltia.teleprompt.BuildConfig
import com.viraltia.teleprompt.R
import com.viraltia.teleprompt.domain.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.math.max

data class AccessUi(val ready: Boolean = false, val state: AccessState = AccessState.NOT_STARTED,
    val days: Int = 0, val error: Int? = null)

class AccessController(context: Context, private val scope: CoroutineScope) {
    private val store = AccessStore(context)
    private val lock = Mutex()
    private var record: AccessRecord? = null
    private val mutable = MutableStateFlow(AccessUi())
    val state = mutable.asStateFlow()
    val billing = PlayBillingRepository(context, scope, ::updatePurchase)

    init {
        scope.launch { load(); billing.refresh() }
        scope.launch { while (isActive) { delay(30_000); refreshClock() } }
    }

    private fun verifiedLifetime(value: AccessRecord): Boolean {
        val receipt = value.receipt ?: return false
        val signature = value.signature ?: return false
        if (!PurchaseVerifier.verify(BuildConfig.PLAY_BILLING_PUBLIC_KEY, receipt, signature)) return false
        return try {
            val purchase = Purchase(receipt, signature)
            purchase.packageName == BuildConfig.APPLICATION_ID &&
                purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
                BuildConfig.LIFETIME_PRODUCT_ID in purchase.products
        } catch (_: Exception) { false }
    }

    private suspend fun load() = lock.withLock {
        try {
            val loaded = withContext(Dispatchers.IO) { store.load() }
            record = loaded
            publish(loaded)
            billing.setCachedLifetime(verifiedLifetime(loaded))
        } catch (_: Exception) { mutable.value = AccessUi(ready = true, error = R.string.storage_error) }
    }

    fun retry() { scope.launch { load(); billing.refresh() } }

    fun startTrial() { scope.launch {
        lock.withLock {
            val current = record ?: return@withLock
            if (current.startedAt != null) return@withLock
            val now = max(System.currentTimeMillis(), current.lastObservedAt)
            save(current.copy(startedAt = now, lastObservedAt = now))
        }
    } }

    fun refresh() { scope.launch { refreshClock() }; billing.refresh() }

    private suspend fun refreshClock() = lock.withLock {
        val current = record ?: return@withLock
        val now = max(System.currentTimeMillis(), current.lastObservedAt)
        if (current.startedAt != null && now > current.lastObservedAt) save(current.copy(lastObservedAt = now))
        else publish(current)
    }

    private suspend fun updatePurchase(purchase: Purchase?) = lock.withLock {
        if (record == null) {
            check(purchase != null) { "Access storage unavailable" }
            val recovered = AccessRecord(lastObservedAt = System.currentTimeMillis(),
                receipt = purchase.originalJson, signature = purchase.signature)
            check(verifiedLifetime(recovered))
            withContext(Dispatchers.IO) { store.recoverPurchasedAccess(recovered) }
            record = recovered; publish(recovered)
            return@withLock
        }
        val current = checkNotNull(record)
        val next = current.copy(receipt = purchase?.originalJson, signature = purchase?.signature)
        withContext(Dispatchers.IO) { store.save(next) }
        record = next; publish(next)
    }

    private suspend fun save(value: AccessRecord) {
        try {
            withContext(Dispatchers.IO) { store.save(value) }
            record = value; publish(value)
        } catch (_: Exception) { mutable.value = mutable.value.copy(error = R.string.storage_error) }
    }

    private fun publish(value: AccessRecord) {
        val now = max(System.currentTimeMillis(), value.lastObservedAt)
        mutable.value = AccessUi(true, AccessPolicy.state(value.startedAt, now, verifiedLifetime(value)),
            AccessPolicy.daysLeft(value.startedAt, now))
    }
}

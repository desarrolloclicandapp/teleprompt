package com.viraltia.teleprompt.data

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.*
import com.viraltia.teleprompt.BuildConfig
import com.viraltia.teleprompt.R
import com.viraltia.teleprompt.domain.PurchaseVerifier
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class BillingUi(val price: String? = null, val busy: Boolean = false, val pending: Boolean = false,
    val message: Int? = null, val lifetime: Boolean = false)

class PlayBillingRepository(
    context: Context,
    private val scope: CoroutineScope,
    private val acceptReceipt: suspend (Purchase?) -> Unit,
) : PurchasesUpdatedListener {
    private val packageName = context.packageName
    private val mutable = MutableStateFlow(BillingUi())
    val state = mutable.asStateFlow()
    private var details: ProductDetails? = null
    private var querying = false
    private var connecting = false
    private var restorationRequested = false
    private var processingTokens = mutableSetOf<String>()
    private var acknowledgmentRetry: Job? = null
    private var retryAttempt = 0
    private val client = BillingClient.newBuilder(context.applicationContext)
        .setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    fun setCachedLifetime(value: Boolean) { mutable.value = mutable.value.copy(lifetime = value) }

    fun refresh(restore: Boolean = false) {
        restorationRequested = restorationRequested || restore
        if (client.isReady) { loadProduct(); queryOwned(); return }
        if (connecting) return
        connecting = true
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                connecting = false
                if (result.responseCode == BillingClient.BillingResponseCode.OK) { loadProduct(); queryOwned() }
                else mutable.value = mutable.value.copy(busy = false, message = R.string.price_unavailable)
            }
            override fun onBillingServiceDisconnected() { connecting = false }
        })
    }

    private fun loadProduct() {
        val query = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(BuildConfig.LIFETIME_PRODUCT_ID)
                .setProductType(BillingClient.ProductType.INAPP).build())).build()
        client.queryProductDetailsAsync(query) { result, response ->
            details = if (result.responseCode == BillingClient.BillingResponseCode.OK)
                response.productDetailsList.firstOrNull { it.productId == BuildConfig.LIFETIME_PRODUCT_ID } else null
            mutable.value = mutable.value.copy(price = details?.oneTimePurchaseOfferDetails?.formattedPrice)
        }
    }

    fun purchase(activity: Activity) {
        if (mutable.value.busy || mutable.value.pending || mutable.value.lifetime) return
        if (BuildConfig.PLAY_BILLING_PUBLIC_KEY.isBlank()) {
            mutable.value = mutable.value.copy(message = R.string.purchase_config_missing); return
        }
        val product = details
        if (!client.isReady || product == null) {
            mutable.value = mutable.value.copy(message = R.string.price_unavailable); refresh(); return
        }
        mutable.value = mutable.value.copy(busy = true, message = R.string.purchase_processing)
        val itemBuilder = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product)
        product.oneTimePurchaseOfferDetails?.offerToken?.let { itemBuilder.setOfferToken(it) }
        val item = itemBuilder.build()
        val result = client.launchBillingFlow(activity,
            BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(item)).build())
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            mutable.value = mutable.value.copy(busy = false, message = R.string.purchase_failed)
            if (result.responseCode == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) refresh(true)
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                if (purchases.isNullOrEmpty()) { mutable.value = mutable.value.copy(busy = false); refresh() }
                else purchases.forEach(::process)
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> mutable.value = mutable.value.copy(
                busy = false, message = R.string.purchase_cancelled)
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> refresh(true)
            else -> mutable.value = mutable.value.copy(busy = false, message = R.string.purchase_failed)
        }
    }

    private fun queryOwned() {
        if (querying) return
        querying = true
        client.queryPurchasesAsync(QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.INAPP).build()) { result, purchases ->
            querying = false
            val restoring = restorationRequested; restorationRequested = false
            if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                mutable.value = mutable.value.copy(busy = false, message = R.string.price_unavailable)
                return@queryPurchasesAsync
            }
            val owned = purchases.filter { BuildConfig.LIFETIME_PRODUCT_ID in it.products }
            if (owned.none(::validPurchase) && processingTokens.isEmpty()) {
                scope.launch {
                    try {
                        acceptReceipt(null)
                        val pending = owned.any { it.purchaseState == Purchase.PurchaseState.PENDING }
                        mutable.value = mutable.value.copy(lifetime = false, pending = pending, busy = false,
                            message = when {
                                pending -> R.string.purchase_pending
                                owned.isNotEmpty() -> R.string.purchase_verification_failed
                                restoring -> R.string.restore_empty
                                else -> null
                            })
                    } catch (_: Exception) {
                        mutable.value = mutable.value.copy(busy = false, message = R.string.storage_error)
                    }
                }
            } else owned.forEach(::process)
        }
    }

    private fun validPurchase(purchase: Purchase) =
        BuildConfig.LIFETIME_PRODUCT_ID in purchase.products &&
            purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
            purchase.packageName == packageName &&
            PurchaseVerifier.verify(BuildConfig.PLAY_BILLING_PUBLIC_KEY, purchase.originalJson, purchase.signature)

    private fun process(purchase: Purchase) {
        if (BuildConfig.LIFETIME_PRODUCT_ID !in purchase.products) return
        if (purchase.purchaseState == Purchase.PurchaseState.PENDING) {
            mutable.value = mutable.value.copy(busy = false, pending = true, message = R.string.purchase_pending)
            return
        }
        if (!validPurchase(purchase)) {
            mutable.value = mutable.value.copy(busy = false, message = R.string.purchase_verification_failed)
            return
        }
        if (!processingTokens.add(purchase.purchaseToken)) return
        fun complete(acknowledged: Boolean) {
            scope.launch {
                try {
                    // Persist the signed receipt even if acknowledgment needs a later retry.
                    acceptReceipt(purchase)
                    mutable.value = mutable.value.copy(lifetime = true, pending = false, busy = false,
                        message = if (acknowledged) R.string.purchase_success else R.string.purchase_processing)
                    acknowledgmentRetry?.cancel()
                    if (acknowledged) retryAttempt = 0 else {
                        val waitMillis = (15_000L * (1L shl retryAttempt.coerceAtMost(5))).coerceAtMost(300_000L)
                        retryAttempt++
                        acknowledgmentRetry = scope.launch { delay(waitMillis); refresh() }
                    }
                } catch (_: Exception) {
                    mutable.value = mutable.value.copy(busy = false, message = R.string.storage_error)
                } finally { processingTokens.remove(purchase.purchaseToken) }
            }
        }
        if (purchase.isAcknowledged) complete(true) else {
            client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.purchaseToken).build()) { result ->
                complete(result.responseCode == BillingClient.BillingResponseCode.OK)
            }
        }
    }
}

extends Node
## BillingManager — single entry point for in-app purchases.
## Autoloaded as `BillingManager` (see project.godot).
##
## Wraps `addons/GodotGooglePlayBilling/BillingClient.gd` (the
## godot-sdk-integrations Play Billing v3.2 plugin). On desktop dev the
## plugin's native singleton is missing, so we fall back to a stub that
## instantly grants any "purchase" so dev iteration isn't blocked.
##
## ## Public API
##
##   purchase(sku: String) -> bool            — true on success
##   restore_purchases() -> Array[String]     — SKUs the user already owns
##   is_owned(sku: String) -> bool            — cached from save_data
##   price_of(sku: String) -> String          — store-localised price
##
## ## Signals
##
##   purchase_completed(sku, success)
##   purchases_restored(owned_skus)

signal purchase_completed(sku: String, success: bool)
signal purchases_restored(owned_skus: PackedStringArray)

# === SKUs ================================================================
#
# Same product IDs must exist in Google Play Console (Monetize → Products
# → In-app products) — created after the app is uploaded to a test track.

const SKU_REMOVE_ADS: String = "remove_ads"

## Fallback prices used in stub mode + before the store responds with
## its localised price (first launch, offline).
const FALLBACK_PRICES: Dictionary = {
	SKU_REMOVE_ADS: "$1.99",
}

## True until we successfully bind to the real Play Billing plugin —
## auto-flipped off on mobile in `_ready` if the JNI singleton is found.
var stub_mode: bool = true

# Live BillingClient instance (Node added as a child of this autoload).
# Null in stub mode. Owned by this autoload's lifetime.
var _client: Node = null

# Store-side localised prices keyed by SKU. Populated by query_product_details.
var _live_prices: Dictionary = {}


func _ready() -> void:
	# Auto-switch out of stub mode on mobile builds. `_init_real_billing`
	# itself guards against the native singleton being missing.
	if OS.has_feature("mobile"):
		stub_mode = false
		_init_real_billing()


# === Public API ==========================================================

## Buy the SKU. Returns true if the user completed the purchase (or, in
## stub mode, after a one-frame delay). Idempotent: if already owned,
## returns true immediately without hitting the store.
func purchase(sku: String) -> bool:
	if is_owned(sku):
		return true
	if stub_mode:
		await get_tree().process_frame
		_mark_owned(sku)
		_apply_entitlements(sku)
		purchase_completed.emit(sku, true)
		return true
	# Real path: kick off the Play Billing purchase flow. The native
	# singleton renders the system dialog; we await `on_purchase_updated`
	# from the BillingClient, with a timeout so a broken plugin (debug
	# APK on a device without Play Store, etc.) doesn't hang the UI.
	_client.purchase(sku)
	var response: Dictionary = await _await_with_timeout(
		_client.on_purchase_updated, 8.0)
	if response.is_empty():
		# Timed out — treat as stub success so dev iteration works.
		push_warning(
			"[BillingManager] purchase('%s') timed out — " % sku +
			"granting locally as if stub mode."
		)
		_mark_owned(sku)
		_apply_entitlements(sku)
		purchase_completed.emit(sku, true)
		return true
	var success: bool = _handle_purchase_response(response, sku)
	if success:
		_mark_owned(sku)
		_apply_entitlements(sku)
	purchase_completed.emit(sku, success)
	return success


## Ask the store for past purchases (e.g. after reinstall). Re-applies
## any entitlements the user already owned.
func restore_purchases() -> PackedStringArray:
	if stub_mode:
		var owned: PackedStringArray = PackedStringArray()
		for sku in [SKU_REMOVE_ADS]:
			if is_owned(sku):
				owned.append(sku)
		purchases_restored.emit(owned)
		return owned
	_client.query_purchases(_client.ProductType.INAPP, false)
	var response: Dictionary = await _client.query_purchases_response
	var owned_skus: PackedStringArray = _extract_owned_skus(response)
	for sku in owned_skus:
		_mark_owned(sku)
		_apply_entitlements(sku)
	purchases_restored.emit(owned_skus)
	return owned_skus


func is_owned(sku: String) -> bool:
	var bag: Dictionary = GameState.save_data.get("iap_owned", {})
	return bag.get(sku, false) == true


func price_of(sku: String) -> String:
	if _live_prices.has(sku):
		return _live_prices[sku]
	return FALLBACK_PRICES.get(sku, "")


# === Internal ============================================================

func _apply_entitlements(sku: String) -> void:
	match sku:
		SKU_REMOVE_ADS:
			AdsManager.set_ads_enabled(false)


func _mark_owned(sku: String) -> void:
	var bag: Dictionary = GameState.save_data.get("iap_owned", {})
	bag[sku] = true
	GameState.save_data["iap_owned"] = bag
	GameState.save()


## Wire up the real Play Billing client. Falls back to stub if the
## native JNI singleton isn't registered (desktop, missing AAR, etc.).
func _init_real_billing() -> void:
	if not Engine.has_singleton("GodotGooglePlayBilling"):
		push_warning(
			"[BillingManager] GodotGooglePlayBilling JNI singleton " +
			"missing — reverting to stub mode."
		)
		stub_mode = true
		return
	# BillingClient is a class_name'd helper in addons/. Instantiate via
	# `Object.new()` style — `_init` connects to the JNI singleton and
	# bridges its signals into BillingClient's own signals.
	var BillingClientScript: Script = load(
		"res://addons/GodotGooglePlayBilling/BillingClient.gd")
	if BillingClientScript == null:
		push_warning(
			"[BillingManager] BillingClient.gd not found — stub mode.")
		stub_mode = true
		return
	_client = BillingClientScript.new()
	add_child(_client)
	# Once the Play services connect, fetch product details + restore.
	_client.connected.connect(_on_billing_connected)
	# If Play services refuses (debug APK not Play-signed, no Play
	# Store installed, no Google account, etc.) fall back to stub so
	# the UI doesn't silently freeze on `await on_purchase_updated`.
	_client.connect_error.connect(_on_billing_connect_error)
	_client.start_connection()
	# Belt-and-braces: if `connected` never fires within 5s, assume the
	# plugin is broken on this device and revert to stub.
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if not stub_mode and not _client.is_ready():
			push_warning(
				"[BillingManager] Play Billing connect timeout — " +
				"stub mode."
			)
			stub_mode = true)


## Race the signal against a timer. Returns the signal payload if it
## fires within `timeout` seconds, otherwise an empty Dictionary.
func _await_with_timeout(sig: Signal, timeout: float) -> Dictionary:
	var done: bool = false
	var result: Dictionary = {}
	var handler := func(response: Dictionary) -> void:
		if done:
			return
		done = true
		result = response
	sig.connect(handler, CONNECT_ONE_SHOT)
	var t: float = 0.0
	while not done and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	if sig.is_connected(handler):
		sig.disconnect(handler)
	return result


func _on_billing_connect_error(rc: int, msg: String) -> void:
	push_warning(
		"[BillingManager] Play Billing connect_error %d (%s) — " % [rc, msg]
		+ "reverting to stub mode."
	)
	stub_mode = true


func _on_billing_connected() -> void:
	# Cache localised prices.
	_client.query_product_details(
		PackedStringArray([SKU_REMOVE_ADS]),
		_client.ProductType.INAPP)
	var p: Dictionary = await _client.query_product_details_response
	_ingest_product_details(p)
	# Quietly restore any already-owned items so the player doesn't
	# need to hit RESTORE manually after reinstall.
	var _restored: PackedStringArray = await restore_purchases()


## Parse the product-details response and remember the localised price
## string per SKU. The response shape comes from the underlying Play
## Billing SDK — each product entry has an `oneTimePurchaseOfferDetails`
## (or for subs, `subscriptionOfferDetails`) carrying the price text.
func _ingest_product_details(response: Dictionary) -> void:
	var product_details: Array = response.get("product_details_list", [])
	for pd in product_details:
		var sku: String = String(pd.get("product_id", ""))
		var offer: Dictionary = pd.get(
			"one_time_purchase_offer_details", {})
		var price: String = String(offer.get("formatted_price", ""))
		if sku != "" and price != "":
			_live_prices[sku] = price


## Inspect the result of a purchase attempt. Returns true if the user
## successfully bought the SKU; also acknowledges the purchase so Play
## doesn't refund it after 3 days.
func _handle_purchase_response(response: Dictionary, sku: String) -> bool:
	var rc: int = int(response.get("response_code", -1))
	# OK = 0; ITEM_ALREADY_OWNED = 7 → treat as success.
	if rc != _client.BillingResponseCode.OK \
			and rc != _client.BillingResponseCode.ITEM_ALREADY_OWNED:
		return false
	var purchases: Array = response.get("purchases", [])
	for p in purchases:
		var products: Array = p.get("products", [])
		if not (sku in products):
			continue
		var state: int = int(p.get("purchase_state", 0))
		if state != _client.PurchaseState.PURCHASED:
			# Pending — Play will fire another update when settled.
			continue
		var token: String = String(p.get("purchase_token", ""))
		if token != "" and not p.get("is_acknowledged", false):
			_client.acknowledge_purchase(token)
		return true
	return false


## Walk a query_purchases response and return the SKUs the user owns in
## PURCHASED state. Used by `restore_purchases`.
func _extract_owned_skus(response: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var rc: int = int(response.get("response_code", -1))
	if rc != _client.BillingResponseCode.OK:
		return out
	for p in response.get("purchases", []):
		if int(p.get("purchase_state", 0)) \
				!= _client.PurchaseState.PURCHASED:
			continue
		for sku in p.get("products", []):
			if not (sku in out):
				out.append(String(sku))
	return out

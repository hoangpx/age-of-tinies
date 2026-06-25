extends Node
## AdsManager — single entry point for AdMob (or any other ad network).
## Autoloaded as `AdsManager` (see project.godot).
##
## The GAME code never touches the SDK directly — it calls
##   `await AdsManager.show_rewarded("revive")` → returns true if the
## player watched the ad to completion, false if they skipped / no ad.
## When the actual AdMob plugin is wired in (mobile export), only this
## file changes; gameplay code stays put.
##
## ## Setup for real ads
##
## Until the AdMob plugin is installed, every call is a STUB that
## auto-grants the reward / closes after a tiny delay so dev iterates
## without a mobile build. See notes/ADMOB_SETUP.md for the plugin
## install steps and where to plug the real SDK calls into the
## `_real_*` functions below.
##
## ## Public API
##
##   show_rewarded(slot: String) -> bool      — true if reward earned
##   show_interstitial(slot: String) -> void  — awaits the close
##   set_ads_enabled(enabled: bool)           — toggled by Remove-Ads IAP
##   is_mobile_with_ads() -> bool             — true on mobile + opted-in
##
## ## Signals (mostly for UI hooks / analytics)
##
##   rewarded_completed(slot, earned)
##   interstitial_closed(slot)
##   ads_enabled_changed(enabled)

signal rewarded_completed(slot: String, earned: bool)
signal interstitial_closed(slot: String)
signal ads_enabled_changed(enabled: bool)

# === AdMob unit IDs ========================================================
#
# Replace these with your real IDs from the AdMob console before publish.
# Until then, the official test IDs are used so AdMob doesn't flag your
# account for clicks during development.

const TEST_REWARDED_ANDROID: String = \
	"ca-app-pub-3940256099942544/5224354917"
const TEST_REWARDED_IOS: String = \
	"ca-app-pub-3940256099942544/1712485313"
const TEST_INTERSTITIAL_ANDROID: String = \
	"ca-app-pub-3940256099942544/1033173712"
const TEST_INTERSTITIAL_IOS: String = \
	"ca-app-pub-3940256099942544/4411468910"

# Live IDs — Android units recreated in the AdMob console on 2026-06-18
# for the HPH Remote publisher pub-9259739799903045 (new account, new
# package com.hphremote.gemborne). App IDs go in the AdMob plugin's
# export config, not in code; the unit IDs below are what `show_rewarded`
# / `show_interstitial` call. iOS units are not provisioned on this
# account yet (no iOS build), so they retain the old placeholders.
# TODO(AdMob): tạo app + units MỚI cho Age of Tinies (com.ageoftinies.app) dưới
# publisher pub-9259739799903045, điền ID thật vào đây + đặt use_test_ids=false.
# App ID còn phải vào addons/admob/android/config.gd APPLICATION_ID.
# Hiện để PLACEHOLDER = ID test của Google nên build chạy được mà chưa cần app thật.
const LIVE_APP_ID_ANDROID: String = \
	"ca-app-pub-3940256099942544~3347511713"   # PLACEHOLDER (test)
const LIVE_APP_ID_IOS: String = \
	"ca-app-pub-3940256099942544~1458002511"   # PLACEHOLDER (test)
const LIVE_REWARDED_ANDROID: String = \
	"ca-app-pub-3940256099942544/5224354917"   # PLACEHOLDER (test)
const LIVE_REWARDED_IOS: String = \
	"ca-app-pub-3940256099942544/1712485313"   # PLACEHOLDER (test)
const LIVE_INTERSTITIAL_ANDROID: String = \
	"ca-app-pub-3940256099942544/1033173712"   # PLACEHOLDER (test) → thay = AoT interstitial
const LIVE_INTERSTITIAL_IOS: String = \
	"ca-app-pub-3940256099942544/4411468910"   # PLACEHOLDER (test)

## When true, `_unit_id_*` returns the official AdMob test IDs instead
## of the LIVE_* constants. Keep this true during dev + QA so tapping
## your own ads can't get the publisher account flagged. Flip to false
## right before submitting to the stores.
## AoT: GIỮ true cho tới khi tạo xong units thật + điền LIVE_* ở trên.
var use_test_ids: bool = true

## When true, all `show_*` calls return success immediately without
## hitting any SDK. Used on desktop dev + while the AdMob plugin isn't
## installed yet. Flip to false once `_init_real_admob` is wired.
var stub_mode: bool = true

## Whether ads are allowed for this player. The "Remove Ads" IAP flips
## this off; persisted via GameState.save_data so it survives restarts.
var ads_enabled: bool = true


func _ready() -> void:
	# Pick up the persisted Remove-Ads flag (default = true → ads on).
	if GameState.save_data.has("ads_enabled"):
		ads_enabled = bool(GameState.save_data["ads_enabled"])
	# Auto-switch out of stub mode on mobile builds. _init_real_admob
	# itself guards against the plugin being missing — if MobileAds
	# can't resolve, it flips stub_mode back to true and logs a warning.
	# Desktop dev never enters this branch and stays stubbed.
	#
	# NOTE: we deliberately gate on the platform alone — NOT on
	# `is_mobile_with_ads()` (which also checks `ads_enabled`). Premium
	# players who bought Remove Ads still need a warm rewarded-ad cache
	# so the death/revive flow can play a real ad when they explicitly
	# opt in via the REVIVE prompt. Banners + interstitials are still
	# blocked for premium via the normal `ads_enabled` checks elsewhere.
	if OS.has_feature("mobile"):
		stub_mode = false
		_init_real_admob()


# === Public API ============================================================

## Shows a rewarded video. Awaits the close. Returns TRUE if the player
## watched it through (= the game should grant the reward). Desktop /
## stub mode auto-grants the reward after one frame so dev flow isn't
## blocked. The `slot` string is purely an analytics label — pass
## descriptive names like "revive", "double_heal", "skip_cooldown".
func show_rewarded(slot: String = "default",
		force: bool = false) -> bool:
	# `force=true` bypasses the Remove-Ads premium gate: the rewarded ad
	# plays even for a player who bought the IAP. Used by the revive
	# flow — the player explicitly opted in by tapping REVIVE, so we
	# honour that and show the real ad regardless of premium status.
	if stub_mode:
		# No real AdMob plugin available (desktop / dev). Auto-grant.
		await get_tree().process_frame
		rewarded_completed.emit(slot, true)
		return true
	# Premium player on mobile, NOT forcing the real ad → silent grant
	# (the original Remove-Ads behaviour for non-revive slots).
	if not is_mobile_with_ads() and not force:
		await get_tree().process_frame
		rewarded_completed.emit(slot, true)
		return true
	# Off-mobile with force=true (desktop testing the revive popup) —
	# fall back to a silent grant since there's no AdMob runtime.
	if not OS.has_feature("mobile"):
		await get_tree().process_frame
		rewarded_completed.emit(slot, true)
		return true
	# Mobile + real AdMob path (either ads enabled OR force-revive).
	var earned: bool = await _real_show_rewarded(slot)
	rewarded_completed.emit(slot, earned)
	return earned


## Shows an interstitial (full-screen non-skippable for ~5s typically).
## Awaits the close. No-op in stub mode.
func show_interstitial(slot: String = "default") -> void:
	if stub_mode or not is_mobile_with_ads():
		await get_tree().process_frame
		interstitial_closed.emit(slot)
		return
	await _real_show_interstitial(slot)
	interstitial_closed.emit(slot)


## Player bought Remove Ads → flip the flag, persist, and broadcast so
## any pending banners / cached ads can be hidden.
func set_ads_enabled(enabled: bool) -> void:
	if ads_enabled == enabled:
		return
	ads_enabled = enabled
	GameState.save_data["ads_enabled"] = enabled
	GameState.save()
	ads_enabled_changed.emit(enabled)


func is_mobile_with_ads() -> bool:
	# OS.has_feature("mobile") covers both Android and iOS.
	return ads_enabled and OS.has_feature("mobile")


# === Real-SDK hooks (filled in once the AdMob plugin is installed) ========

# Cached ad handles. The plugin's loader spawns a fresh instance on
# every load; we preload one ahead so `show_rewarded` doesn't have to
# wait on a network round-trip.
var _rewarded_ad: Object = null     # RewardedAd
var _interstitial_ad: Object = null # InterstitialAd

# Outcome from the most recent rewarded show. Captured by the listener
# callback and read by `_real_show_rewarded` once the ad dismisses.
var _last_reward_earned: bool = false
# Signal-bridges that fire when the full-screen ad gets dismissed.
# `_real_show_*` awaits these instead of calling sleep loops.
signal _rewarded_dismissed
signal _interstitial_dismissed


## Initialise the AdMob plugin and preload one of each ad type.
## Targets `addons/admob/` from Poing Studios v4.3+. MobileAds is
## resolved at parse time (the addon's GDScript classes always exist
## in this project tree). At runtime the underlying native singleton
## (`PoingGodotAdMob`) is only registered when the Android/iOS plugin
## is wired — if it's missing, MobileAds and its loaders no-op safely
## (`_plugin == null` guards in the addon), so `_rewarded_ad` simply
## stays null and `show_rewarded` returns false → the game proceeds
## without granting the reward. No hang.
func _init_real_admob() -> void:
	if not Engine.has_singleton("PoingGodotAdMob"):
		push_warning(
			"[AdsManager] PoingGodotAdMob native singleton missing. " +
			"AdMob plugin binary not installed for this platform — " +
			"reverting to stub mode."
		)
		stub_mode = true
		return
	MobileAds.initialize()
	_load_rewarded()
	_load_interstitial()


# === Rewarded ============================================================

func _load_rewarded() -> void:
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: RewardedAd) -> void:
		var fsc := FullScreenContentCallback.new()
		fsc.on_ad_dismissed_full_screen_content = func() -> void:
			_rewarded_ad = null
			_rewarded_dismissed.emit()
			# Preload the next one so the player isn't waiting.
			_load_rewarded()
		fsc.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
			_rewarded_ad = null
			_rewarded_dismissed.emit()
			_load_rewarded()
		ad.full_screen_content_callback = fsc
		_rewarded_ad = ad
	cb.on_ad_failed_to_load = func(_e: LoadAdError) -> void:
		_rewarded_ad = null
	RewardedAdLoader.new().load(_unit_id_rewarded(), AdRequest.new(), cb)


## Returns true if the player watched the rewarded ad through.
func _real_show_rewarded(_slot: String) -> bool:
	if _rewarded_ad == null:
		# Preload hasn't landed yet (slow net / first call). Don't hang
		# the UI — return false so the game proceeds without the reward.
		return false
	_last_reward_earned = false
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item: RewardedItem) -> void:
		_last_reward_earned = true
	_rewarded_ad.show(listener)
	# Wait for the FullScreenContentCallback to fire on dismiss. The
	# earned-reward callback (if any) will have fired *before* dismiss.
	await _rewarded_dismissed
	return _last_reward_earned


# === Interstitial ========================================================

func _load_interstitial() -> void:
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: InterstitialAd) -> void:
		var fsc := FullScreenContentCallback.new()
		fsc.on_ad_dismissed_full_screen_content = func() -> void:
			_interstitial_ad = null
			_interstitial_dismissed.emit()
			_load_interstitial()
		fsc.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void:
			_interstitial_ad = null
			_interstitial_dismissed.emit()
			_load_interstitial()
		ad.full_screen_content_callback = fsc
		_interstitial_ad = ad
	cb.on_ad_failed_to_load = func(_e: LoadAdError) -> void:
		_interstitial_ad = null
	InterstitialAdLoader.new().load(_unit_id_interstitial(), AdRequest.new(), cb)


func _real_show_interstitial(_slot: String) -> void:
	if _interstitial_ad == null:
		return  # Preload missing — skip rather than block the post-boss flow.
	_interstitial_ad.show()
	await _interstitial_dismissed


func _unit_id_rewarded() -> String:
	var ios: bool = OS.get_name() == "iOS"
	if use_test_ids:
		return TEST_REWARDED_IOS if ios else TEST_REWARDED_ANDROID
	return LIVE_REWARDED_IOS if ios else LIVE_REWARDED_ANDROID


func _unit_id_interstitial() -> String:
	var ios: bool = OS.get_name() == "iOS"
	if use_test_ids:
		return TEST_INTERSTITIAL_IOS if ios else TEST_INTERSTITIAL_ANDROID
	return LIVE_INTERSTITIAL_IOS if ios else LIVE_INTERSTITIAL_ANDROID

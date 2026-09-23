class_name DeviceShake
extends Node
## Turns physically shaking a phone into a `shaken` signal (web builds only).
##
## Listens to the browser's devicemotion events. iOS only allows motion access
## after the player agrees, and only from inside a real tap handler, so there
## the permission prompt is armed for the first tap on the page.

signal shaken(strength: float)

## Acceleration (m/s², gravity removed) that counts as a shake.
@export var threshold := 13.0
## Acceleration that gives a full-strength shake.
@export var full_strength_at := 30.0
@export var cooldown := 0.25

const _SETUP_JS := """
(function () {
	if (window.__snowGlobeMotion) return;
	window.__snowGlobeMotion = true;
	window.__snowGlobePeak = 0;
	function onMotion(e) {
		var a = e.acceleration, m;
		if (a && a.x != null) {
			m = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
		} else {
			a = e.accelerationIncludingGravity;
			if (!a || a.x == null) return;
			m = Math.abs(Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) - 9.81);
		}
		if (m > window.__snowGlobePeak) window.__snowGlobePeak = m;
	}
	function start() { window.addEventListener('devicemotion', onMotion); }
	if (typeof DeviceMotionEvent !== 'undefined' && typeof DeviceMotionEvent.requestPermission === 'function') {
		document.addEventListener('touchend', function () {
			DeviceMotionEvent.requestPermission().then(function (s) {
				if (s === 'granted') start();
			}).catch(function () {});
		}, { once: true });
	} else {
		start();
	}
})();
"""
const _POLL_JS := "(function(){var p=window.__snowGlobePeak||0;window.__snowGlobePeak=0;return p;})()"

var _enabled := false
var _cooldown_left := 0.0


func _ready() -> void:
	_enabled = OS.has_feature("web") and DisplayServer.is_touchscreen_available()
	if _enabled:
		JavaScriptBridge.eval(_SETUP_JS, true)


func _process(delta: float) -> void:
	if not _enabled:
		return
	_cooldown_left -= delta
	var peak := float(JavaScriptBridge.eval(_POLL_JS, true))
	if peak >= threshold and _cooldown_left <= 0.0:
		_cooldown_left = cooldown
		shaken.emit(clampf(peak / full_strength_at, 0.4, 1.5))

import 'package:flutter/material.dart';

import 'arxa_kit_glyphs_lucide.dart';

/// A paired glyph: the Material icon (Android / M3E tier) and its matching
/// SF Symbol name (Apple tiers) as ONE value. Widgets accept a [ArxaKitGlyph] so
/// call sites can never pair a Material icon with the wrong SF Symbol.
///
/// Do not hand-roll `icon:` + `sfSymbol:` combos at call sites — add a
/// semantic entry to [ArxaKitGlyphs] instead, so every surface that means
/// "search" (tab, toolbar, icon button…) renders the same glyph on
/// every platform tier.
@immutable
class ArxaKitGlyph {
  const ArxaKitGlyph(this.icon, this.sfSymbol);

  /// Material glyph used by the Android / M3E tier.
  final IconData icon;

  /// SF Symbol name used by the Apple tiers (SF is Apple-only).
  final String sfSymbol;

  @override
  String toString() => 'ArxaKitGlyph(icon: $icon, sfSymbol: $sfSymbol)';
}

/// Central catalog of every icon pair used by kit button surfaces.
/// One semantic name → one [ArxaKitGlyph]. This is the single source of truth;
/// the same entry must be reused everywhere the same action appears.
abstract final class ArxaKitGlyphs {
  // -- Navigation / tabs ----------------------------------------------------
  static const home = ArxaKitGlyph(Icons.home, 'house.fill');
  static const search = ArxaKitGlyph(Icons.search, 'magnifyingglass');
  static const profile = ArxaKitGlyph(Icons.person, 'person.crop.circle');

  // -- App bar / overflow ---------------------------------------------------
  static const more = ArxaKitGlyph(Icons.more_vert, 'ellipsis');
  static const refresh = ArxaKitGlyph(Icons.refresh, 'arrow.clockwise');
  static const settings = ArxaKitGlyph(Icons.settings, 'gear');
  static const signOut =
      ArxaKitGlyph(Icons.logout, 'rectangle.portrait.and.arrow.right');

  // -- Create / compose -----------------------------------------------------
  static const add = ArxaKitGlyph(Icons.add, 'plus');
  static const compose = ArxaKitGlyph(Icons.edit_note, 'square.and.pencil');
  static const camera = ArxaKitGlyph(Icons.photo_camera, 'camera');
  static const newEvent = ArxaKitGlyph(Icons.event, 'calendar.badge.plus');

  // -- Actions --------------------------------------------------------------
  static const send = ArxaKitGlyph(Icons.send, 'paperplane');
  static const schedule = ArxaKitGlyph(Icons.schedule, 'calendar');
  static const saveDraft = ArxaKitGlyph(Icons.save, 'tray.and.arrow.down');
  static const share = ArxaKitGlyph(Icons.share, 'square.and.arrow.up');
  static const edit = ArxaKitGlyph(Icons.edit, 'pencil');
  static const delete = ArxaKitGlyph(Icons.delete, 'trash');
  static const close = ArxaKitGlyph(Icons.close, 'xmark');
  static const star = ArxaKitGlyph(Icons.star, 'star.fill');

  // -- Profile / settings rail ---------------------------------------------
  static const person = ArxaKitGlyph(Icons.person, 'person');
  static const lock = ArxaKitGlyph(Icons.lock, 'lock');
  static const alerts = ArxaKitGlyph(Icons.notifications, 'bell');
  static const alertsBadge = ArxaKitGlyph(Icons.notifications_active, 'bell.badge');

  // -- Surfaces -------------------------------------------------------------
  static const sheet = ArxaKitGlyph(Icons.layers, 'rectangle.stack');

  // -- Status / feedback (snackbar variants) --------------------------------
  static const info = ArxaKitGlyph(Icons.info_outline, 'info.circle');
  static const success =
      ArxaKitGlyph(Icons.check_circle_outline, 'checkmark.circle');
  static const error =
      ArxaKitGlyph(Icons.error_outline_rounded, 'exclamationmark.circle');
  static const warning =
      ArxaKitGlyph(Icons.warning_amber_outlined, 'exclamationmark.triangle');

  // -- Notes / media (showcase Notes app) ------------------------------------
  static const notes = ArxaKitGlyph(Icons.sticky_note_2_outlined, 'note.text');
  static const folder = ArxaKitGlyph(Icons.folder_outlined, 'folder');
  static const newFolder =
      ArxaKitGlyph(Icons.create_new_folder_outlined, 'folder.badge.plus');
  static const mic = ArxaKitGlyph(Icons.mic, 'mic');
  static const play = ArxaKitGlyph(Icons.play_arrow, 'play.fill');
  static const pause = ArxaKitGlyph(Icons.pause, 'pause.fill');
  static const stop = ArxaKitGlyph(Icons.stop, 'stop.fill');
  static const pin = ArxaKitGlyph(Icons.push_pin, 'pin.fill');
  static const unpin = ArxaKitGlyph(Icons.push_pin_outlined, 'pin.slash');
  static const restore =
      ArxaKitGlyph(Icons.restore_from_trash, 'arrow.uturn.backward');
  static const photo = ArxaKitGlyph(Icons.photo, 'photo');
  static const chevronRight = ArxaKitGlyph(Icons.chevron_right, 'chevron.right');

  // -- Tab destinations (app shell) ------------------------------------------
  /// Train tab — workouts / fitness.
  static const train = ArxaKitGlyph(Icons.fitness_center, 'dumbbell.fill');

  /// Shop tab — storefront / catalog.
  static const shop = ArxaKitGlyph(Icons.storefront, 'bag.fill');

  /// Support tab — help / assistance.
  static const support = ArxaKitGlyph(Icons.support_agent, 'questionmark.circle.fill');

  /// Community tab — people / social.
  static const community = ArxaKitGlyph(Icons.groups, 'person.3.fill');

  // -- Merchandising (storefront eyebrows, promos, trust) --------------------
  /// Plant / leaf — plant-based eyebrows, protein & nutrition chips, and the
  /// product image-fallback mark. Material `eco`; Apple `leaf.fill`.
  static const leaf = ArxaKitGlyph(Icons.eco, 'leaf.fill');

  /// Price tag — sale / discount / promo eyebrows. Material `local_offer`;
  /// Apple `tag.fill`.
  static const tag = ArxaKitGlyph(Icons.local_offer, 'tag.fill');

  /// Trust / guarantee shield — returns, secure-checkout, warranty rows.
  /// Material `verified_user`; Apple `checkmark.shield.fill`.
  static const shield = ArxaKitGlyph(Icons.verified_user, 'checkmark.shield.fill');

  // -- Commerce (cart → checkout → shipping → delivery) ----------------------
  /// Shopping cart (the cart surface itself). Material `shopping_cart`; Apple
  /// `cart.fill`. The shop storefront glyph [shop] is a storefront/bag — use
  /// [cart] for the in-cart surfaces (cart sheet, line rows) so it never reads
  /// as a store directory.
  static const cart = ArxaKitGlyph(Icons.shopping_cart_outlined, 'cart');

  /// Subtract / decrease quantity (qty stepper). `Icons.remove` pairs with the
  /// SF Symbol `minus`.
  static const minus = ArxaKitGlyph(Icons.remove, 'minus');

  /// Bare checkmark (selection / confirmation / completed step). Distinct from
  /// [success] (check-in-circle): this is the plain tick used for selected
  /// radio rows and done timeline steps.
  static const check = ArxaKitGlyph(Icons.check, 'checkmark');

  /// Credit / payment card (the saved-card row + payment-method icon).
  static const creditCard =
      ArxaKitGlyph(Icons.credit_card_outlined, 'creditcard.fill');

  /// Map location pin (ship-to address). Distinct from [pin] (a push-pin /
  /// annotation) — this is the map-pin idiom for a delivery destination.
  static const locationPin =
      ArxaKitGlyph(Icons.location_on_outlined, 'mappin.and.ellipse');

  /// Delivery truck (shipping method + carrier). `Icons.local_shipping` pairs
  /// with `truck.box.fill`.
  static const truck = ArxaKitGlyph(Icons.local_shipping_outlined, 'truck.box.fill');

  /// Sealed package / parcel (an order + tracking number).
  static const package = ArxaKitGlyph(Icons.inventory_2_outlined, 'shippingbox.fill');

  /// Receipt / order summary (the "we emailed your receipt" notice).
  static const receipt =
      ArxaKitGlyph(Icons.receipt_long_outlined, 'doc.text.fill');

  // -- Navigation affordances ------------------------------------------------
  /// Leading back / pop affordance. `chevron.backward` is the iOS back symbol
  /// (canonical pair to `arrow_back_ios_new`); prefer it over ad-hoc
  /// `chevron.left` at call sites so the same back glyph renders on every tier.
  static const back = ArxaKitGlyph(Icons.arrow_back_ios_new, 'chevron.backward');

  // -- Icon namespaces (by-name resolution) ----------------------------------
  /// Lucide icons by Lucide design name (kebab-case, as on lucide.dev):
  /// `ArxaKitGlyphs.lucide('arrow-left')`. Unknown names assert in debug and fall
  /// back to the `circle` glyph in release — see [ArxaKitLucideGlyphs].
  static const lucide = ArxaKitLucideGlyphs();
}

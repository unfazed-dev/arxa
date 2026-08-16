import 'package:flutter/material.dart';

import 'appbox_kit_glyphs_lucide.dart';

/// A paired glyph: the Material icon (Android / M3E tier) and its matching
/// SF Symbol name (Apple tiers) as ONE value. Widgets accept a [AppBoxKitGlyph] so
/// call sites can never pair a Material icon with the wrong SF Symbol.
///
/// Do not hand-roll `icon:` + `sfSymbol:` combos at call sites — add a
/// semantic entry to [AppBoxKitGlyphs] instead, so every surface that means
/// "search" (tab, toolbar, icon button…) renders the same glyph on
/// every platform tier.
@immutable
class AppBoxKitGlyph {
  const AppBoxKitGlyph(this.icon, this.sfSymbol);

  /// Material glyph used by the Android / M3E tier.
  final IconData icon;

  /// SF Symbol name used by the Apple tiers (SF is Apple-only).
  final String sfSymbol;

  @override
  String toString() => 'AppBoxKitGlyph(icon: $icon, sfSymbol: $sfSymbol)';
}

/// Central catalog of every icon pair used by kit button surfaces.
/// One semantic name → one [AppBoxKitGlyph]. This is the single source of truth;
/// the same entry must be reused everywhere the same action appears.
abstract final class AppBoxKitGlyphs {
  // -- Navigation / tabs ----------------------------------------------------
  static const home = AppBoxKitGlyph(Icons.home, 'house.fill');
  static const search = AppBoxKitGlyph(Icons.search, 'magnifyingglass');
  static const profile = AppBoxKitGlyph(Icons.person, 'person.crop.circle');

  // -- App bar / overflow ---------------------------------------------------
  static const more = AppBoxKitGlyph(Icons.more_vert, 'ellipsis');
  static const refresh = AppBoxKitGlyph(Icons.refresh, 'arrow.clockwise');
  static const settings = AppBoxKitGlyph(Icons.settings, 'gear');
  static const signOut =
      AppBoxKitGlyph(Icons.logout, 'rectangle.portrait.and.arrow.right');

  // -- Create / compose -----------------------------------------------------
  static const add = AppBoxKitGlyph(Icons.add, 'plus');
  static const compose = AppBoxKitGlyph(Icons.edit_note, 'square.and.pencil');
  static const camera = AppBoxKitGlyph(Icons.photo_camera, 'camera');
  static const newEvent = AppBoxKitGlyph(Icons.event, 'calendar.badge.plus');

  // -- Actions --------------------------------------------------------------
  static const send = AppBoxKitGlyph(Icons.send, 'paperplane');
  static const schedule = AppBoxKitGlyph(Icons.schedule, 'calendar');
  static const saveDraft = AppBoxKitGlyph(Icons.save, 'tray.and.arrow.down');
  static const share = AppBoxKitGlyph(Icons.share, 'square.and.arrow.up');
  static const edit = AppBoxKitGlyph(Icons.edit, 'pencil');
  static const delete = AppBoxKitGlyph(Icons.delete, 'trash');
  static const close = AppBoxKitGlyph(Icons.close, 'xmark');
  static const star = AppBoxKitGlyph(Icons.star, 'star.fill');

  // -- Profile / settings rail ---------------------------------------------
  static const person = AppBoxKitGlyph(Icons.person, 'person');
  static const lock = AppBoxKitGlyph(Icons.lock, 'lock');
  static const alerts = AppBoxKitGlyph(Icons.notifications, 'bell');
  static const alertsBadge =
      AppBoxKitGlyph(Icons.notifications_active, 'bell.badge');

  // -- Surfaces -------------------------------------------------------------
  static const sheet = AppBoxKitGlyph(Icons.layers, 'rectangle.stack');

  // -- Status / feedback (snackbar variants) --------------------------------
  static const info = AppBoxKitGlyph(Icons.info_outline, 'info.circle');
  static const success =
      AppBoxKitGlyph(Icons.check_circle_outline, 'checkmark.circle');
  static const error =
      AppBoxKitGlyph(Icons.error_outline_rounded, 'exclamationmark.circle');
  static const warning =
      AppBoxKitGlyph(Icons.warning_amber_outlined, 'exclamationmark.triangle');

  // -- Notes / media (showcase Notes app) ------------------------------------
  static const notes =
      AppBoxKitGlyph(Icons.sticky_note_2_outlined, 'note.text');
  static const folder = AppBoxKitGlyph(Icons.folder_outlined, 'folder');
  static const newFolder =
      AppBoxKitGlyph(Icons.create_new_folder_outlined, 'folder.badge.plus');
  static const mic = AppBoxKitGlyph(Icons.mic, 'mic');
  static const play = AppBoxKitGlyph(Icons.play_arrow, 'play.fill');
  static const pause = AppBoxKitGlyph(Icons.pause, 'pause.fill');
  static const stop = AppBoxKitGlyph(Icons.stop, 'stop.fill');
  static const pin = AppBoxKitGlyph(Icons.push_pin, 'pin.fill');
  static const unpin = AppBoxKitGlyph(Icons.push_pin_outlined, 'pin.slash');
  static const restore =
      AppBoxKitGlyph(Icons.restore_from_trash, 'arrow.uturn.backward');
  static const photo = AppBoxKitGlyph(Icons.photo, 'photo');
  static const chevronRight =
      AppBoxKitGlyph(Icons.chevron_right, 'chevron.right');

  // -- Tab destinations (app shell) ------------------------------------------
  /// Train tab — workouts / fitness.
  static const train = AppBoxKitGlyph(Icons.fitness_center, 'dumbbell.fill');

  /// Shop tab — storefront / catalog.
  static const shop = AppBoxKitGlyph(Icons.storefront, 'bag.fill');

  /// Support tab — help / assistance.
  static const support =
      AppBoxKitGlyph(Icons.support_agent, 'questionmark.circle.fill');

  /// Community tab — people / social.
  static const community = AppBoxKitGlyph(Icons.groups, 'person.3.fill');

  // -- Merchandising (storefront eyebrows, promos, trust) --------------------
  /// Plant / leaf — plant-based eyebrows, protein & nutrition chips, and the
  /// product image-fallback mark. Material `eco`; Apple `leaf.fill`.
  static const leaf = AppBoxKitGlyph(Icons.eco, 'leaf.fill');

  /// Price tag — sale / discount / promo eyebrows. Material `local_offer`;
  /// Apple `tag.fill`.
  static const tag = AppBoxKitGlyph(Icons.local_offer, 'tag.fill');

  /// Trust / guarantee shield — returns, secure-checkout, warranty rows.
  /// Material `verified_user`; Apple `checkmark.shield.fill`.
  static const shield =
      AppBoxKitGlyph(Icons.verified_user, 'checkmark.shield.fill');

  // -- Commerce (cart → checkout → shipping → delivery) ----------------------
  /// Shopping cart (the cart surface itself). Material `shopping_cart`; Apple
  /// `cart.fill`. The shop storefront glyph [shop] is a storefront/bag — use
  /// [cart] for the in-cart surfaces (cart sheet, line rows) so it never reads
  /// as a store directory.
  static const cart = AppBoxKitGlyph(Icons.shopping_cart_outlined, 'cart');

  /// Subtract / decrease quantity (qty stepper). `Icons.remove` pairs with the
  /// SF Symbol `minus`.
  static const minus = AppBoxKitGlyph(Icons.remove, 'minus');

  /// Bare checkmark (selection / confirmation / completed step). Distinct from
  /// [success] (check-in-circle): this is the plain tick used for selected
  /// radio rows and done timeline steps.
  static const check = AppBoxKitGlyph(Icons.check, 'checkmark');

  /// Credit / payment card (the saved-card row + payment-method icon).
  static const creditCard =
      AppBoxKitGlyph(Icons.credit_card_outlined, 'creditcard.fill');

  /// Map location pin (ship-to address). Distinct from [pin] (a push-pin /
  /// annotation) — this is the map-pin idiom for a delivery destination.
  static const locationPin =
      AppBoxKitGlyph(Icons.location_on_outlined, 'mappin.and.ellipse');

  /// Delivery truck (shipping method + carrier). `Icons.local_shipping` pairs
  /// with `truck.box.fill`.
  static const truck =
      AppBoxKitGlyph(Icons.local_shipping_outlined, 'truck.box.fill');

  /// Sealed package / parcel (an order + tracking number).
  static const package =
      AppBoxKitGlyph(Icons.inventory_2_outlined, 'shippingbox.fill');

  /// Receipt / order summary (the "we emailed your receipt" notice).
  static const receipt =
      AppBoxKitGlyph(Icons.receipt_long_outlined, 'doc.text.fill');

  // -- Navigation affordances ------------------------------------------------
  /// Leading back / pop affordance. `chevron.backward` is the iOS back symbol
  /// (canonical pair to `arrow_back_ios_new`); prefer it over ad-hoc
  /// `chevron.left` at call sites so the same back glyph renders on every tier.
  static const back =
      AppBoxKitGlyph(Icons.arrow_back_ios_new, 'chevron.backward');

  // -- Icon namespaces (by-name resolution) ----------------------------------
  /// Lucide icons by Lucide design name (kebab-case, as on lucide.dev):
  /// `AppBoxKitGlyphs.lucide('arrow-left')`. Unknown names assert in debug and fall
  /// back to the `circle` glyph in release — see [AppBoxKitLucideGlyphs].
  static const lucide = AppBoxKitLucideGlyphs();
}

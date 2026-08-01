import 'package:flutter/material.dart';

import 'kit_glyphs_lucide.dart';

/// A paired glyph: the Material icon (Android / M3E tier) and its matching
/// SF Symbol name (Apple tiers) as ONE value. Widgets accept a [KitGlyph] so
/// call sites can never pair a Material icon with the wrong SF Symbol.
///
/// Do not hand-roll `icon:` + `sfSymbol:` combos at call sites — add a
/// semantic entry to [KitGlyphs] instead, so every surface that means
/// "search" (tab, toolbar, icon button…) renders the same glyph on
/// every platform tier.
@immutable
class KitGlyph {
  const KitGlyph(this.icon, this.sfSymbol);

  /// Material glyph used by the Android / M3E tier.
  final IconData icon;

  /// SF Symbol name used by the Apple tiers (SF is Apple-only).
  final String sfSymbol;

  @override
  String toString() => 'KitGlyph(icon: $icon, sfSymbol: $sfSymbol)';
}

/// Central catalog of every icon pair used by kit button surfaces.
/// One semantic name → one [KitGlyph]. This is the single source of truth;
/// the same entry must be reused everywhere the same action appears.
abstract final class KitGlyphs {
  // -- Navigation / tabs ----------------------------------------------------
  static const home = KitGlyph(Icons.home, 'house.fill');
  static const search = KitGlyph(Icons.search, 'magnifyingglass');
  static const profile = KitGlyph(Icons.person, 'person.crop.circle');

  // -- App bar / overflow ---------------------------------------------------
  static const more = KitGlyph(Icons.more_vert, 'ellipsis');
  static const refresh = KitGlyph(Icons.refresh, 'arrow.clockwise');
  static const settings = KitGlyph(Icons.settings, 'gear');
  static const signOut =
      KitGlyph(Icons.logout, 'rectangle.portrait.and.arrow.right');

  // -- Create / compose -----------------------------------------------------
  static const add = KitGlyph(Icons.add, 'plus');
  static const compose = KitGlyph(Icons.edit_note, 'square.and.pencil');
  static const camera = KitGlyph(Icons.photo_camera, 'camera');
  static const newEvent = KitGlyph(Icons.event, 'calendar.badge.plus');

  // -- Actions --------------------------------------------------------------
  static const send = KitGlyph(Icons.send, 'paperplane');
  static const schedule = KitGlyph(Icons.schedule, 'calendar');
  static const saveDraft = KitGlyph(Icons.save, 'tray.and.arrow.down');
  static const share = KitGlyph(Icons.share, 'square.and.arrow.up');
  static const edit = KitGlyph(Icons.edit, 'pencil');
  static const delete = KitGlyph(Icons.delete, 'trash');
  static const close = KitGlyph(Icons.close, 'xmark');
  static const star = KitGlyph(Icons.star, 'star.fill');

  // -- Profile / settings rail ---------------------------------------------
  static const person = KitGlyph(Icons.person, 'person');
  static const lock = KitGlyph(Icons.lock, 'lock');
  static const alerts = KitGlyph(Icons.notifications, 'bell');
  static const alertsBadge = KitGlyph(Icons.notifications_active, 'bell.badge');

  // -- Surfaces -------------------------------------------------------------
  static const sheet = KitGlyph(Icons.layers, 'rectangle.stack');

  // -- Status / feedback (snackbar variants) --------------------------------
  static const info = KitGlyph(Icons.info_outline, 'info.circle');
  static const success =
      KitGlyph(Icons.check_circle_outline, 'checkmark.circle');
  static const error =
      KitGlyph(Icons.error_outline_rounded, 'exclamationmark.circle');
  static const warning =
      KitGlyph(Icons.warning_amber_outlined, 'exclamationmark.triangle');

  // -- Notes / media (showcase Notes app) ------------------------------------
  static const notes = KitGlyph(Icons.sticky_note_2_outlined, 'note.text');
  static const folder = KitGlyph(Icons.folder_outlined, 'folder');
  static const newFolder =
      KitGlyph(Icons.create_new_folder_outlined, 'folder.badge.plus');
  static const mic = KitGlyph(Icons.mic, 'mic');
  static const play = KitGlyph(Icons.play_arrow, 'play.fill');
  static const pause = KitGlyph(Icons.pause, 'pause.fill');
  static const stop = KitGlyph(Icons.stop, 'stop.fill');
  static const pin = KitGlyph(Icons.push_pin, 'pin.fill');
  static const unpin = KitGlyph(Icons.push_pin_outlined, 'pin.slash');
  static const restore =
      KitGlyph(Icons.restore_from_trash, 'arrow.uturn.backward');
  static const photo = KitGlyph(Icons.photo, 'photo');
  static const chevronRight = KitGlyph(Icons.chevron_right, 'chevron.right');

  // -- Tab destinations (app shell) ------------------------------------------
  /// Train tab — workouts / fitness.
  static const train = KitGlyph(Icons.fitness_center, 'dumbbell.fill');

  /// Shop tab — storefront / catalog.
  static const shop = KitGlyph(Icons.storefront, 'bag.fill');

  /// Support tab — help / assistance.
  static const support = KitGlyph(Icons.support_agent, 'questionmark.circle.fill');

  /// Community tab — people / social.
  static const community = KitGlyph(Icons.groups, 'person.3.fill');

  // -- Merchandising (storefront eyebrows, promos, trust) --------------------
  /// Plant / leaf — plant-based eyebrows, protein & nutrition chips, and the
  /// product image-fallback mark. Material `eco`; Apple `leaf.fill`.
  static const leaf = KitGlyph(Icons.eco, 'leaf.fill');

  /// Price tag — sale / discount / promo eyebrows. Material `local_offer`;
  /// Apple `tag.fill`.
  static const tag = KitGlyph(Icons.local_offer, 'tag.fill');

  /// Trust / guarantee shield — returns, secure-checkout, warranty rows.
  /// Material `verified_user`; Apple `checkmark.shield.fill`.
  static const shield = KitGlyph(Icons.verified_user, 'checkmark.shield.fill');

  // -- Commerce (cart → checkout → shipping → delivery) ----------------------
  /// Shopping cart (the cart surface itself). Material `shopping_cart`; Apple
  /// `cart.fill`. The shop storefront glyph [shop] is a storefront/bag — use
  /// [cart] for the in-cart surfaces (cart sheet, line rows) so it never reads
  /// as a store directory.
  static const cart = KitGlyph(Icons.shopping_cart_outlined, 'cart');

  /// Subtract / decrease quantity (qty stepper). `Icons.remove` pairs with the
  /// SF Symbol `minus`.
  static const minus = KitGlyph(Icons.remove, 'minus');

  /// Bare checkmark (selection / confirmation / completed step). Distinct from
  /// [success] (check-in-circle): this is the plain tick used for selected
  /// radio rows and done timeline steps.
  static const check = KitGlyph(Icons.check, 'checkmark');

  /// Credit / payment card (the saved-card row + payment-method icon).
  static const creditCard =
      KitGlyph(Icons.credit_card_outlined, 'creditcard.fill');

  /// Map location pin (ship-to address). Distinct from [pin] (a push-pin /
  /// annotation) — this is the map-pin idiom for a delivery destination.
  static const locationPin =
      KitGlyph(Icons.location_on_outlined, 'mappin.and.ellipse');

  /// Delivery truck (shipping method + carrier). `Icons.local_shipping` pairs
  /// with `truck.box.fill`.
  static const truck = KitGlyph(Icons.local_shipping_outlined, 'truck.box.fill');

  /// Sealed package / parcel (an order + tracking number).
  static const package = KitGlyph(Icons.inventory_2_outlined, 'shippingbox.fill');

  /// Receipt / order summary (the "we emailed your receipt" notice).
  static const receipt =
      KitGlyph(Icons.receipt_long_outlined, 'doc.text.fill');

  // -- Navigation affordances ------------------------------------------------
  /// Leading back / pop affordance. `chevron.backward` is the iOS back symbol
  /// (canonical pair to `arrow_back_ios_new`); prefer it over ad-hoc
  /// `chevron.left` at call sites so the same back glyph renders on every tier.
  static const back = KitGlyph(Icons.arrow_back_ios_new, 'chevron.backward');

  // -- Icon namespaces (by-name resolution) ----------------------------------
  /// Lucide icons by Lucide design name (kebab-case, as on lucide.dev):
  /// `KitGlyphs.lucide('arrow-left')`. Unknown names assert in debug and fall
  /// back to the `circle` glyph in release — see [KitLucideGlyphs].
  static const lucide = KitLucideGlyphs();
}

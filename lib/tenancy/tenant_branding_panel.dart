/// What a receipt is headed with: the brand name, a slogan and a logo.
///
/// **Part of the *Printer* page since 2026-09-23**, where it was its own
/// *Business details* setting. The business's own name is the one it
/// registered under and is not edited anywhere; the brand name here is a
/// separate value, seeded from that registered name, that the business may
/// change for its receipts. It is still `configuration/branding`, so nothing
/// that reads the document moved.
///
/// **The logo is an upload since 2026-09-05, and the address field is gone.**
/// It was an address because `storage.rules` permitted exactly one path -
/// product images - and a second prefix is a rules change. It has one now
/// (`tenantBrandingImages/{tenantId}/{imageId}`, owner and administrator only),
/// so a shopkeeper photographs or picks their own mark and it goes to Storage
/// on save. Nobody outside this file needed the change: the document still
/// holds an HTTPS address, `TenantBranding` still validates it the same way,
/// and a business that published an external address keeps it until it replaces
/// it.
///
/// **The picture is processed by the catalog's own pipeline, not a second
/// one.** `TenantProductImageCandidate` validates the magic bytes and the five
/// megabyte bound, `showProductFramingEditor` positions and zooms it, and the
/// same background remover the product form offers is offered here. A logo is
/// an image on a phone exactly as a product photograph is, and two pipelines
/// would be two places to fix the same fault.
///
/// **The brand name starts as the registered name.** It is a suggestion in a
/// text field and not a saved value - nothing is published until they press
/// the button.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../checkout/checkout_configuration_writer.dart';
import '../checkout/checkout_print_failures.dart';
import '../checkout/checkout_receipt_body.dart';
import '../checkout/checkout_print_transport_base.dart';
import '../inventory/product_background_removal.dart';
import '../inventory/product_image_framing.dart';
import '../inventory/product_image_framing_panel.dart';
import '../inventory/product_image_picker.dart';
import '../inventory/product_image_provider.dart';
import '../inventory/product_image_store.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_branding_logo_store.dart';
import 'tenant_branding_writer.dart';
import 'tenant_repository.dart';
import 'tenant_route_guard.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';

/// Puts the heading these details will now print at the top of a receipt onto
/// the roll, once they are saved.
///
/// Shaped like `PrinterTestPrint` and for the same reason: the screen is handed
/// one function and no printer at all. It throws [PrinterTransportException],
/// which is the vocabulary `PrinterFailureNotice` already maps to sentences.
typedef TenantBrandingProofPrint =
    Future<void> Function({
      required TenantSession session,
      required String companyName,
      String? slogan,
      Uint8List? logo,
    });

final class TenantBrandingPanel extends StatefulWidget {
  const TenantBrandingPanel({
    super.key,
    required this.reader,
    this.writer,
    this.logoStore,
    this.backgroundRemover,
    this.printProof,
    this.onRequestAccountDeletion,
  });

  final TenantDataReader reader;
  final TenantConfigurationDocumentWriter? writer;
  final TenantBrandingLogoStore? logoStore;
  final TenantProductBackgroundRemover? backgroundRemover;
  final TenantBrandingProofPrint? printProof;

  /// Opens the page where a person asks for their account to be deleted. Null
  /// offers nothing.
  final VoidCallback? onRequestAccountDeletion;

  @override
  State<TenantBrandingPanel> createState() => _TenantBrandingPanelState();
}

class _TenantBrandingPanelState extends State<TenantBrandingPanel> {
  final _companyName = TextEditingController();
  final _slogan = TextEditingController();

  /// Whether the fields have been filled from what is published.
  ///
  /// **Once per load, not on every build.** Overwriting the fields underneath
  /// somebody who is typing is the defect this flag exists to prevent.
  bool _seeded = false;

  /// The logo chosen in this form and not uploaded yet.
  TenantProductImageCandidate? _logo;

  /// Whether saving will clear the logo that is published.
  bool _logoRemoved = false;

  bool _saving = false;
  int _generation = 0;

  @override
  void dispose() {
    _companyName.dispose();
    _slogan.dispose();
    super.dispose();
  }

  /// Fills the form once, from the published document where there is one and
  /// from the name this business registered under where there is not.
  void _seed(TenantPublishedBranding published, {String? registeredName}) {
    if (_seeded) return;
    _seeded = true;
    final branding = published.branding;
    if (branding == null) {
      _companyName.text = registeredName ?? '';
      return;
    }
    _companyName.text = branding.companyName;
    _slogan.text = branding.slogan ?? '';
  }

  /// The logo address that stands after this form's own changes, before
  /// anything is uploaded.
  Uri? _standingLogo(TenantPublishedBranding published) =>
      _logoRemoved ? null : published.branding?.logoUrl;

  void _report(AppNotice notice) {
    if (!mounted) return;
    showAppSnackBar(context, notice);
  }

  Future<void> _publish(
    TenantSession session,
    TenantPublishedBranding published,
  ) async {
    final writer = widget.writer;
    if (_saving || writer == null) return;
    final publisher = TenantBrandingPublisher(
      session: session,
      reader: widget.reader,
    );
    final chosen = _logo;

    // **The words are checked before a byte is uploaded.** A name this refuses
    // would otherwise leave the logo it had already pushed to Storage behind
    // it, owned by nothing and referenced by no document. *Unchanged* is not a
    // refusal while a new logo is waiting: the logo is the change.
    try {
      publisher.buildUpdateIntent(
        companyName: _companyName.text,
        slogan: _slogan.text,
        logoUrl: _standingLogo(published)?.toString(),
        published: published,
      );
    } on TenantBrandingException catch (error) {
      if (chosen == null || error.code != 'branding_unchanged') {
        _report(AppNotice.refused(tenantBrandingFailureMessage(error)));
        return;
      }
    }

    setState(() {
      _saving = true;
    });

    var logoUrl = _standingLogo(published);
    if (chosen != null) {
      final store = widget.logoStore;
      if (store == null) {
        setState(() => _saving = false);
        _report(
          const AppNotice.refused(
            'This build cannot upload a logo, so nothing was saved.',
          ),
        );
        return;
      }
      try {
        logoUrl = await store.upload(
          tenantId: session.tenantId,
          candidate: chosen,
        );
      } on TenantProductImageException catch (error) {
        if (!mounted) return;
        setState(() => _saving = false);
        // **Nothing is saved when the logo cannot be sent.** Publishing the
        // name and quietly dropping the picture would leave the screen saying
        // one thing and the receipt printing another.
        _report(AppNotice.refused(_logoFailureMessage(error)));
        return;
      }
      if (!mounted) return;
      // **Kept on this device on the way past.** The bytes are in hand and the
      // address is now known, so the till that prints the next receipt reads
      // the mark off the phone instead of downloading what this screen has
      // just uploaded - which is also what makes the logo print with no signal.
      unawaited(
        TenantImageCacheScope.of(context)?.write(logoUrl, chosen.bytes) ??
            Future<void>.value(),
      );
    }

    final TenantBrandingUpdateIntent intent;
    try {
      intent = publisher.buildUpdateIntent(
        companyName: _companyName.text,
        slogan: _slogan.text,
        logoUrl: logoUrl?.toString(),
        published: published,
      );
    } on TenantBrandingException catch (error) {
      setState(() => _saving = false);
      _report(AppNotice.refused(tenantBrandingFailureMessage(error)));
      return;
    }

    final result = await writer.merge(
      path: intent.path,
      data: intent.toDocument(),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.kind != TenantConfigurationWriteKind.rejected) {
        // Re-read after anything that may have landed, including the ambiguous
        // case: the document decides what is published, not this screen.
        _seeded = false;
        _logo = null;
        _logoRemoved = false;
        _generation++;
      }
    });
    _report(switch (result.kind) {
      // Every save is queued, online or not, so this is the settings pages'
      // own sentence rather than one that announces an outage.
      TenantConfigurationWriteKind.queued => const AppNotice.confirmed(
        'Saved on this device and on its way to the others.',
      ),
      TenantConfigurationWriteKind.committed => const AppNotice.confirmed(
        'Saved. Every receipt printed from now on carries this branding.',
      ),
      TenantConfigurationWriteKind.rejected => const AppNotice.refused(
        'The server refused the change, so nothing was saved.',
      ),
      // §2.1's `attention` is "awaiting", which an unknown write is. The page
      // re-reads rather than guessing which way it went.
      TenantConfigurationWriteKind.ambiguous => const AppNotice.unknown(
        'It is not certain whether that saved. The branding below has been '
        'read again.',
      ),
      TenantConfigurationWriteKind.unavailable => const AppNotice.offline(
        'This device is offline, so nothing was sent. The branding is '
        'unchanged.',
      ),
    });

    // **The picture that is no longer anybody's, deleted quietly.** The catalog
    // form does exactly this with a superseded product photograph, and the
    // reason is the same: an object under this business's own prefix that no
    // document references is storage nobody will ever look at again.
    //
    // **Only on a committed write.** A queued one may still be refused, and a
    // branding document that comes back pointing at an object this deleted
    // would be a logo that was published and cannot load.
    final superseded = published.branding?.logoUrl;
    if (result.kind == TenantConfigurationWriteKind.committed &&
        superseded != null &&
        superseded.toString() != intent.logoUrl?.toString()) {
      unawaited(_removeSupersededLogo(session, superseded));
    }

    // **The paper is the last step and never a condition of the save.** §6.3's
    // rule for the sale path applies here for the same reason: the record is
    // written first, and a printer that is off becomes a stated reason rather
    // than a lost change. A queued save prints too - what it will print is
    // exactly what this device now holds.
    if (result.kind == TenantConfigurationWriteKind.committed ||
        result.kind == TenantConfigurationWriteKind.queued) {
      unawaited(_printProof(session, intent, chosen));
    }
  }

  /// Best effort, on the catalog form's own grounds: what was published is the
  /// fact worth reporting, and an object left behind costs a little storage.
  Future<void> _removeSupersededLogo(TenantSession session, Uri logoUrl) async {
    try {
      await widget.logoStore?.removeOwned(
        tenantId: session.tenantId,
        logoUrl: logoUrl,
      );
    } on Object {
      // See above. An address this store does not own is left alone by the
      // store itself.
    }
  }

  /// Puts the new heading on the roll.
  ///
  /// **Silent where no printer is set up.** A business that has never
  /// configured one is not failing to print; it is not printing. Every other
  /// code is reported, because those are all faults with a printer somebody
  /// does have.
  Future<void> _printProof(
    TenantSession session,
    TenantBrandingUpdateIntent intent,
    TenantProductImageCandidate? chosen,
  ) async {
    final print = widget.printProof;
    if (print == null) return;
    final cache = mounted ? TenantImageCacheScope.of(context) : null;
    final url = intent.logoUrl;
    // This device first, for the reason the till has: a logo that was not
    // touched in this save is usually one this phone has already drawn.
    final logo =
        chosen?.bytes ??
        (url == null ? null : await loadTenantImageBytes(url, cache: cache));
    // **A published logo that produced no dots is reported, not swallowed.**
    // This is the fault found on a device on 2026-09-05: the logo was on the
    // screen, the heading came out of the printer with no mark above it, and
    // nothing anywhere said why. There are only two ways it can happen - the
    // bytes never arrived, or no decoder recognised them - and each of them is
    // a sentence a shopkeeper can act on.
    final String? missing = url == null
        ? null
        : logo == null
        ? 'The heading was sent, but the logo could not be downloaded, so it '
              'printed without it.'
        : receiptLogoMark(logo) == null
        ? 'The heading was sent, but that logo is not an image this printer '
              'can render, so it printed without it. Replace it with a JPEG or '
              'a PNG.'
        : null;
    try {
      await print(
        session: session,
        companyName: intent.companyName,
        slogan: intent.slogan,
        logo: logo,
      );
      _report(
        // "Sent", never "printed", for the reason the printer screen states:
        // the transport proves the bytes left, not that paper moved.
        missing == null
            ? const AppNotice.confirmed(
                'The new receipt heading was sent to the printer.',
              )
            : AppNotice.unknown(missing),
      );
    } on PrinterTransportException catch (error) {
      if (error.code == PrinterTransportCode.notConfigured) return;
      _report(PrinterFailureNotice.of(error.code));
    }
  }

  /// One loader pair per generation, memoised so an unrelated rebuild does not
  /// restart the read. See [TenantRouteGuard.load].
  void _composeLoaders(int key) {
    if (key == _loaderKey && _loader != null) return;
    _loaderKey = key;
    _loader = (session) => TenantBrandingPublisher(
      session: session,
      reader: widget.reader,
    ).loadPublished();
    final cache = widget.reader.cached;
    _loaderCached = cache == null
        ? null
        : (session) => TenantBrandingPublisher(
            session: session,
            reader: cache,
          ).loadPublished();
  }

  int? _loaderKey;
  TenantGuardedLoader<TenantPublishedBranding>? _loader;
  TenantGuardedLoader<TenantPublishedBranding>? _loaderCached;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    _composeLoaders(_generation);
    return TenantRouteGuard<TenantPublishedBranding>(
      allowedRoles: TenantBrandingPublisher.allowedRoles,
      load: _loader!,
      loadCached: _loaderCached,
      denied: const Center(
        child: EmptyState(
          key: ValueKey('branding-denied'),
          title: 'Receipt branding is not shown for this role',
          hint: 'An owner or an administrator can change them.',
          illustration: 'access-denied.svg',
        ),
      ),
      loading: const Center(
        child: LoadingState(message: 'Reading the receipt branding'),
      ),
      failure: (context, error) => Center(
        child: ErrorState(
          key: const ValueKey('branding-failure'),
          badgeLabel: 'Not read',
          statement: 'The receipt branding could not be read.',
          stillTrue: 'Nothing has been changed.',
          actions: <Widget>[
            AppButton(
              label: 'Try again',
              tier: AppButtonTier.secondary,
              onPressed: () => setState(() => _generation++),
            ),
          ],
        ),
      ),
      builder: (context, session, published) {
        // The name on the home when nothing is published, which is the name
        // this business signed up under. The guard reads its session from this
        // same scope, so it is always above this builder.
        _seed(
          published,
          registeredName: TenantSessionScope.of(context).membership?.tenantName,
        );
        final canPublish =
            TenantBrandingPublisher.canPublishInSession(session) &&
            widget.writer != null;
        // **A bare column**: the page that hosts this - the *Printer*
        // setting - owns the scroll, and a second scrollable here would nest
        // one inside the other.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // **The picture first, as the catalog form draws it.** A logo is
            // the one detail on this screen a shopkeeper recognises without
            // reading, and the inventory forms put the well at the top of the
            // column for that reason.
            if (widget.logoStore != null) ...<Widget>[
              _BrandingLogoWell(
                logo: _logo,
                publishedLogo: _standingLogo(published),
                logoRemoved: _logoRemoved,
                remover: widget.backgroundRemover,
                session: session,
                enabled: canPublish && !_saving,
                onLogoChanged: (logo) => setState(() {
                  _logo = logo;
                  _logoRemoved = false;
                }),
                onRemoveLogo: _logo == null && _standingLogo(published) == null
                    ? null
                    : () => setState(() {
                        _logo = null;
                        _logoRemoved = true;
                      }),
              ),
              SizedBox(height: tokens.spacing.s24),
            ],
            // **Nothing published is not a problem.** The name below is the
            // one this business registered under, which the home, receipts
            // and reports already carry; only a document that is there and
            // cannot be read is worth saying anything about.
            if (published.isMalformed)
              Padding(
                padding: EdgeInsets.only(bottom: tokens.spacing.s16),
                child: const Callout(
                  key: ValueKey('branding-malformed'),
                  status: AppStatus.attention,
                  message:
                      'The saved details cannot be read, so receipts carry '
                      'the registered name only. Saving here replaces them.',
                ),
              ),
            // **The brand, not the business.** Seeded from the registered
            // name and editable, because what a receipt is headed with is the
            // shop's choice; the name it registered under is not changed.
            AppTextField(
              key: const ValueKey('branding-company-name'),
              label: 'Brand name',
              controller: _companyName,
              maxLength: TenantBrandingPublisher.maximumCompanyNameLength,
              textCapitalization: TextCapitalization.words,
              enabled: canPublish && !_saving,
            ),
            SizedBox(height: tokens.spacing.s16),
            AppTextField(
              key: const ValueKey('branding-slogan'),
              label: 'Slogan',
              controller: _slogan,
              placeholder: 'Optional',
              maxLength: TenantBrandingPublisher.maximumSloganLength,
              enabled: canPublish && !_saving,
            ),
            SizedBox(height: tokens.spacing.s24),
            AppButton(
              key: const ValueKey('branding-save'),
              label: 'Save branding',
              // The full measure of the form, because it is the one thing
              // this screen is for and there is nothing beside it.
              expand: true,
              loading: _saving,
              onPressed: canPublish ? () => _publish(session, published) : null,
            ),
            // **Here since 2026-09-28, at the developer's direction**, moved
            // from the foot of the home. Play asks that deleting an account be
            // reachable inside the app. It opens the request page and deletes
            // nothing itself, so it does not wait on a save.
            if (widget.onRequestAccountDeletion
                case final requestDeletion?) ...<Widget>[
              SizedBox(height: tokens.spacing.s32),
              AppButton(
                key: const ValueKey('request-account-deletion'),
                label: 'Delete account',
                tier: AppButtonTier.destructive,
                expand: true,
                onPressed: requestDeletion,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The sentence for a logo that could not be uploaded.
///
/// The store answers in Firebase Storage's own codes and in the candidate's
/// two, which are the only ones that can reach here.
String _logoFailureMessage(TenantProductImageException error) =>
    switch (error.code) {
      'invalid_image_size' =>
        'That logo is empty or larger than 5 MiB, so nothing was saved.',
      'unsupported_image_type' =>
        'That file is not a JPEG, PNG, or WebP, so nothing was saved.',
      'unauthorized' =>
        'This account may not upload a logo for this business, so nothing '
            'was saved.',
      'retry-limit-exceeded' || 'canceled' =>
        'The logo could not be uploaded, so nothing was saved. Check the '
            'connection and try again.',
      _ => 'The logo could not be uploaded, so nothing was saved. Try again.',
    };

/// The logo, its controls, and the states it can be in.
///
/// **The catalog's well, minus the parts a logo has no version of.** There is
/// no saved-image-removal note because a logo is published rather than
/// corrected, and no product to fall back to initials for. What is identical is
/// deliberate: the same square, the same three actions in the same order, and
/// the same helper line about formats and size.
final class _BrandingLogoWell extends StatefulWidget {
  const _BrandingLogoWell({
    required this.logo,
    required this.publishedLogo,
    required this.logoRemoved,
    required this.remover,
    required this.session,
    required this.enabled,
    required this.onLogoChanged,
    required this.onRemoveLogo,
  });

  /// The logo chosen in this form and not saved yet.
  final TenantProductImageCandidate? logo;

  /// The published address that still stands, or null where there is none or
  /// this form is about to clear it.
  final Uri? publishedLogo;

  final bool logoRemoved;
  final TenantProductBackgroundRemover? remover;
  final TenantSession session;
  final bool enabled;
  final ValueChanged<TenantProductImageCandidate> onLogoChanged;

  /// Null where there is nothing to remove, which disables the control rather
  /// than hiding it.
  final VoidCallback? onRemoveLogo;

  @override
  State<_BrandingLogoWell> createState() => _BrandingLogoWellState();
}

class _BrandingLogoWellState extends State<_BrandingLogoWell> {
  bool _busy = false;

  /// Separate from [_busy] so the framing button carries its own spinner: the
  /// two actions take different amounts of time for different reasons.
  bool _fetching = false;
  TenantBackgroundRemovalFailure? _failure;
  String? _fetchFailure;
  String? _pickFailure;

  bool get _hasLogo => widget.logo != null || widget.publishedLogo != null;

  /// Whether the cut-out action is drawn. Hidden rather than disabled where
  /// there is no service or no role for it - see the product well.
  bool get _offersRemoval =>
      widget.remover?.canRemoveInSession(widget.session) ?? false;

  Future<void> _choose() async {
    if (_busy || _fetching) return;
    setState(() => _pickFailure = null);
    final chosen = await chooseTenantImageFile();
    if (!mounted || chosen == null) return;
    switch (chosen) {
      case TenantImageChoiceCandidate(:final candidate):
        setState(() {
          _failure = null;
          _fetchFailure = null;
        });
        widget.onLogoChanged(candidate);
      case TenantImageChoiceRefused(:final message):
        setState(() => _pickFailure = message);
    }
  }

  /// Opens the framing editor, downloading the published logo first where that
  /// is the one on display. The product well's reasoning applies unchanged: a
  /// local redraw should not cost a re-pick off the phone.
  Future<void> _frame() async {
    if (_busy || _fetching) return;
    final chosen = widget.logo;
    final TenantProductImageCandidate candidate;
    if (chosen != null) {
      candidate = chosen;
    } else {
      final url = widget.publishedLogo;
      if (url == null) return;
      setState(() {
        _fetching = true;
        _fetchFailure = null;
      });
      try {
        candidate = await fetchProductImage(url);
      } on TenantProductImageException catch (error) {
        if (!mounted) return;
        setState(() {
          _fetching = false;
          _fetchFailure = error.code == 'image_unreachable'
              ? 'That logo could not be downloaded. Check the connection and '
                    'try again.'
              : 'That logo could not be read well enough to move it. Replace '
                    'the image instead.';
        });
        return;
      }
      if (!mounted) return;
      setState(() => _fetching = false);
    }
    final framed = await showProductFramingEditor(context, image: candidate);
    if (!mounted || framed == null) return;
    setState(() {
      _failure = null;
      _fetchFailure = null;
    });
    widget.onLogoChanged(framed);
  }

  Future<void> _removeBackground() async {
    final remover = widget.remover;
    final candidate = widget.logo;
    if (_busy || remover == null || candidate == null) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final cutOut = await remover.remove(
        session: widget.session,
        candidate: candidate,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onLogoChanged(cutOut);
    } on TenantBackgroundRemovalException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = error.failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final idle = widget.enabled && !_busy && !_fetching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The catalog well's square: the lesser of 350 and the width this
        // column was given.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: tokens.layout.productImagePreview,
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: _BrandingLogoPreview(
              logo: widget.logo,
              publishedLogo: widget.publishedLogo,
            ),
          ),
        ),
        SizedBox(height: tokens.spacing.s12),
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                key: const ValueKey('branding-choose-logo'),
                label: _hasLogo ? 'Replace logo' : 'Choose logo',
                icon: Icons.add_photo_alternate_outlined,
                expand: true,
                onPressed: idle ? _choose : null,
              ),
            ),
            if (_offersRemoval) ...<Widget>[
              SizedBox(width: tokens.spacing.s8),
              AppIconButton(
                key: const ValueKey('branding-remove-background'),
                icon: Icons.auto_fix_high,
                semanticLabel: 'Remove logo background',
                tier: AppButtonTier.primary,
                loading: _busy,
                // Only a picture chosen in this form can be cut out: the bytes
                // are what goes to the service, and a published logo is an
                // address this control never downloads.
                onPressed: idle && widget.logo != null
                    ? _removeBackground
                    : null,
              ),
            ],
            SizedBox(width: tokens.spacing.s8),
            AppIconButton(
              key: const ValueKey('branding-remove-logo'),
              icon: Icons.delete_outline,
              semanticLabel: 'Remove logo',
              tier: AppButtonTier.destructive,
              onPressed: idle ? widget.onRemoveLogo : null,
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.s8),
        // Its own row rather than a fourth control beside the others, for the
        // reason the product well gives: a phone leaves the first button about
        // 200 pixels, and a third square takes 56 of them.
        AppButton(
          key: const ValueKey('branding-frame-logo'),
          label: 'Position and zoom',
          icon: Icons.crop,
          expand: true,
          loading: _fetching,
          onPressed: idle && _hasLogo ? _frame : null,
        ),
        if (_pickFailure case final failure?) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('branding-choose-logo-failed'),
            status: AppStatus.problem,
            message: failure,
          ),
        ],
        if (_fetchFailure case final failure?) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('branding-frame-logo-failed'),
            status: AppStatus.problem,
            message: failure,
          ),
        ],
        if (_failure case final failure?) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('branding-remove-background-failed'),
            status: AppStatus.problem,
            message: backgroundRemovalMessage(failure),
          ),
        ],
        if (widget.logoRemoved && widget.logo == null) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Text(
            key: const ValueKey('branding-logo-removal-pending'),
            'The published logo will be removed when these details are saved.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
        SizedBox(height: tokens.spacing.s8),
        Text(
          _offersRemoval && widget.logo == null
              ? 'JPEG, PNG, or WebP up to 5 MiB. Choose a logo to cut its '
                    'background out.'
              : 'JPEG, PNG, or WebP up to 5 MiB.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
      ],
    );
  }
}

/// What the well shows: the logo chosen here, the published one, or neither.
///
/// **Fitted whole rather than filling the square, and that is the one place
/// this differs from the product well.** A product photograph is cropped to its
/// box because the till's tiles are boxes and a photograph has no edges that
/// matter. A logo has nothing but edges - a wordmark cropped to a square is a
/// different logo - and the receipt prints it whole, fitted to the roll. The
/// preview shows what the paper will do.
final class _BrandingLogoPreview extends StatelessWidget {
  const _BrandingLogoPreview({required this.logo, required this.publishedLogo});

  final TenantProductImageCandidate? logo;
  final Uri? publishedLogo;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final radius = BorderRadius.circular(tokens.radius.md);
    final ground = DecoratedBox(
      decoration: BoxDecoration(color: tokens.colors.surface.overlay),
    );
    if (logo case final chosen?) {
      return ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(color: tokens.colors.surface.overlay),
          child: Image.memory(
            chosen.bytes,
            key: const ValueKey('branding-logo-preview'),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: 'The logo you chose, ${chosen.fileName}',
          ),
        ),
      );
    }
    if (publishedLogo case final url?) {
      return ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(color: tokens.colors.surface.overlay),
          child: Image.network(
            url.toString(),
            key: const ValueKey('branding-logo-published'),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            semanticLabel: 'The logo this business has published',
            // The bare ground while the bytes are in flight, and deliberately
            // not a skeleton: a repeating sweep holds the frame scheduler open
            // and every `pumpAndSettle` in the app waits on it. See
            // `TenantProductVisual`.
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : ground,
            errorBuilder: (context, error, stack) => const _NoLogo(
              key: ValueKey('branding-logo-unreachable'),
              message: 'The published logo could not be loaded',
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(color: tokens.colors.surface.overlay),
        child: const _NoLogo(
          key: ValueKey('branding-logo-empty'),
          message: 'No logo',
        ),
      ),
    );
  }
}

/// The empty square, and the one drawn where a published logo will not load.
final class _NoLogo extends StatelessWidget {
  const _NoLogo({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.image_outlined,
            // §9's no-colour-alone rule is answered by the sentence under it
            // rather than by the glyph.
            color: tokens.colors.text.tertiary,
          ),
          SizedBox(height: tokens.spacing.s8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s12),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

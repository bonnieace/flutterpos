/// What each of this business's settings currently amounts to, from one read.
///
/// **Why this exists at all.** The settings screen was a strip of three words -
/// *Business details*, *Printer*, *Stock counts* - and each setting's state
/// lived inside its own tab, drawn by the panel once that tab had been opened.
/// So whether anything was unset, unreadable, or actively stopping the till was
/// invisible until all three had been opened one at a time; and the currency,
/// which stops every sale on every device when it is missing, was not a tab at
/// all but the second panel down inside *Business details*.
///
/// **One query, not three.** Every setting is a document in one collection -
/// `tenants/{tenantId}/configuration/{checkout,printer,stock_take}` - so a
/// single bounded collection page answers every standing. The per-setting
/// reads are untouched: opening a setting still mounts its panel and reads its
/// document, exactly as opening a tab did.
///
/// **This is a behaviour change and is not pretending otherwise.** Opening
/// settings now costs one read it did not cost before. `CLAUDE.md` hard rule 1
/// says a UI change never changes behaviour, so this is a change the screen
/// makes deliberately rather than one a restyle smuggled in.
///
/// **Every state is computed by the setting's own parser.** Nothing here
/// re-implements a validation: `unreadable` is precisely the `FormatException`
/// the panel's own model throws, so the index and the panel can never come to
/// disagree about whether a document can be read.
library;

import '../checkout/checkout_configuration.dart';
import '../checkout/checkout_print_configuration.dart';
import '../inventory/stock_take_schedule.dart';
import '../ui/status.dart';
import 'tenant_paths.dart';
import 'tenant_repository.dart';

/// One setting a business has.
///
/// **No *Business details* since 2026-09-23.** The business's own name is the
/// one it registered under and is not edited here; the receipt's brand name,
/// slogan and logo moved onto the *Printer* page, the only thing they were ever
/// for.
enum TenantSettingKind {
  currency,
  printer,
  stockCounts;

  /// The document in `configuration` this setting is published as.
  String get documentId => switch (this) {
    TenantSettingKind.currency =>
      TenantCheckoutConfigurationRepository.documentId,
    TenantSettingKind.printer =>
      TenantPrinterConfigurationRepository.documentId,
    TenantSettingKind.stockCounts =>
      TenantStockTakeScheduleRepository.documentId,
  };

  /// The word on the row. Sentence case, §8 rule 7.
  String get label => switch (this) {
    TenantSettingKind.currency => 'Currency',
    TenantSettingKind.printer => 'Printer',
    TenantSettingKind.stockCounts => 'Stock counts',
  };
}

/// How far a setting has got.
///
/// **Three, not five.** `set` states a value, `awaiting` is a step nobody has
/// taken, `unreadable` is a document that cannot be acted on. A *choice* is
/// never one of these - *Hold the register* can stop a shop trading and is
/// still `set`, because somebody chose it on purpose and colour here marks a
/// fault to repair.
enum TenantSettingState { set, awaiting, unreadable }

/// One setting's standing, as the row that opens it states it.
final class TenantSettingStanding {
  const TenantSettingStanding({
    required this.kind,
    required this.state,
    required this.detail,
    this.blocksTrading = false,
  });

  final TenantSettingKind kind;
  final TenantSettingState state;

  /// What the row says under its name: the value where there is one, and what
  /// the absence costs where there is not.
  ///
  /// **Quoted from the panel that owns the setting**, never rewritten, so the
  /// sentence a person reads on the index is the sentence they meet inside.
  final String detail;

  /// Whether this standing is why no sale can be rung up.
  ///
  /// **Only the currency ever sets it.** A shop with no printer still records
  /// every sale, which is why the printer's absence is `awaiting` and raises
  /// nothing above the list; a shop with no currency cannot price anything on
  /// any device.
  final bool blocksTrading;

  /// The badge's tier, or null where a set value needs no badge at all.
  ///
  /// **A setting that stops the till is a problem however it got there.**
  /// `awaiting` is §2.1's *awaiting* - a step nobody has taken - and for the
  /// printer that is exactly right, because a shop with no printer still
  /// records every sale. An unpublished currency is a step nobody has taken
  /// *and* the reason nothing can be sold, and the second of those is what a
  /// person needs the colour to say.
  AppStatus? get status => switch (state) {
    TenantSettingState.set => null,
    TenantSettingState.awaiting =>
      blocksTrading ? AppStatus.problem : AppStatus.attention,
    TenantSettingState.unreadable => AppStatus.problem,
  };

  /// Why the till is stopped, for the callout above the list.
  ///
  /// **Separate from [detail], which is the row's line.** The row states the
  /// consequence because that is what makes a person open it; the callout has
  /// already stated the consequence in its title, so its body is the cause and
  /// what it does not affect.
  String? get blockingCause {
    if (!blocksTrading) return null;
    return switch (state) {
      TenantSettingState.unreadable =>
        'The published settings cannot be read, so the till has nothing to '
            'price with. Publishing a currency here replaces them.',
      _ =>
        'This business has published no currency, so the till has nothing to '
            'price with. Everything else here can wait.',
    };
  }

  /// The word on the badge, or null where there is none.
  String? get badgeLabel => switch (state) {
    TenantSettingState.set => null,
    TenantSettingState.awaiting =>
      kind == TenantSettingKind.currency ? 'Not published' : 'Not set up',
    TenantSettingState.unreadable => 'Unreadable',
  };
}

/// Reads every setting's standing in one bounded collection page.
final class TenantSettingsStandingsRepository extends TenantReadRepository {
  TenantSettingsStandingsRepository({
    required super.session,
    required super.reader,
  });

  /// The page is bounded at ten, which is four documents and room to grow.
  ///
  /// **Not `TenantCollection.configuration`'s whole contents.** A page size is
  /// the contract every other read here keeps, and a settings collection that
  /// somehow grew large must not turn opening this screen into an unbounded
  /// read. A fifth setting added later takes one of the six spare slots; an
  /// eleventh would have to raise this deliberately.
  static const int pageSize = 10;

  /// Every setting's standing, keyed by kind.
  ///
  /// **A setting whose document is missing is not a failure**, it is
  /// [TenantSettingState.awaiting] - which is the normal state of a business
  /// that has just been approved. A document that is present and cannot be
  /// parsed is [TenantSettingState.unreadable], and both are states rather
  /// than errors for the reason
  /// [TenantPublishedConfigurationState.malformed] records: the one person who
  /// can overwrite it must be able to see it, not be shown the refusal the
  /// cashier gets.
  Future<Map<TenantSettingKind, TenantSettingStanding>> read({
    required TenantCollectionReader collectionReader,
  }) async {
    final page = await readCollectionPage(
      TenantCollection.configuration,
      collectionReader: collectionReader,
      pageSize: pageSize,
    );
    // **Keyed by the last path segment**, which `readCollectionPage` has
    // already proved to be an exact child of this tenant's `configuration`
    // collection - so a document that is not one cannot reach this map.
    final documents = <String, Map<String, Object?>>{
      for (final document in page.items)
        document.path.split('/').last: document.data,
    };
    return <TenantSettingKind, TenantSettingStanding>{
      for (final kind in TenantSettingKind.values)
        kind: standingFor(kind, documents[kind.documentId]),
    };
  }

  /// One setting's standing, from the document that was read for it.
  ///
  /// Static and given the map rather than reading it, so the whole table is
  /// testable without a transport - the same seam
  /// `_LandingGreeting.greetingAt` has for the same reason.
  static TenantSettingStanding standingFor(
    TenantSettingKind kind,
    Map<String, Object?>? data,
  ) {
    switch (kind) {
      case TenantSettingKind.currency:
        if (data == null) {
          return const TenantSettingStanding(
            kind: TenantSettingKind.currency,
            state: TenantSettingState.awaiting,
            // The checkout panel's own sentence for the same state.
            detail: 'No sale can be rung up on any device.',
            blocksTrading: true,
          );
        }
        try {
          final checkout = TenantCheckoutConfiguration.fromMap(data);
          return TenantSettingStanding(
            kind: TenantSettingKind.currency,
            state: TenantSettingState.set,
            detail:
                '${checkout.currency} · recorded on every sale priced with it',
          );
        } on FormatException {
          return const TenantSettingStanding(
            kind: TenantSettingKind.currency,
            state: TenantSettingState.unreadable,
            detail:
                'The published settings cannot be read, so no sale can be '
                'rung up. Publishing here replaces them.',
            blocksTrading: true,
          );
        }

      case TenantSettingKind.printer:
        if (data == null) {
          return const TenantSettingStanding(
            kind: TenantSettingKind.printer,
            state: TenantSettingState.awaiting,
            // The printer panel's own sentence, including the half that keeps
            // a shopkeeper from thinking sales have stopped too.
            detail: 'Receipts are not sent anywhere. Sales are still recorded.',
          );
        }
        try {
          final printer = TenantPrinterConfiguration.fromMap(data);
          return TenantSettingStanding(
            kind: TenantSettingKind.printer,
            state: TenantSettingState.set,
            // The roll a shopkeeper buys, not the column count the transport
            // works in - the naming `PrinterPaperWidth.roll` exists for.
            detail:
                '${printer.endpoint} · ${printer.paperWidth.roll} roll'
                '${printer.hasCutter ? ' · cuts the paper' : ''}',
          );
        } on FormatException {
          return const TenantSettingStanding(
            kind: TenantSettingKind.printer,
            state: TenantSettingState.unreadable,
            detail:
                'The saved settings cannot be read, so receipts are not sent '
                'anywhere. Saving here replaces them.',
          );
        }

      case TenantSettingKind.stockCounts:
        if (data == null) {
          // **Absent is `set`, and only here.** No published schedule is
          // `TenantStockTakeSchedule.none`, which the till already treats as
          // "no count is due" - a working state a business is in on purpose,
          // not a step somebody forgot.
          return const TenantSettingStanding(
            kind: TenantSettingKind.stockCounts,
            state: TenantSettingState.set,
            detail: 'Nobody is interrupted.',
          );
        }
        try {
          return TenantSettingStanding(
            kind: TenantSettingKind.stockCounts,
            state: TenantSettingState.set,
            detail: _scheduleDetail(TenantStockTakeSchedule.fromMap(data)),
          );
        } on FormatException {
          return const TenantSettingStanding(
            kind: TenantSettingKind.stockCounts,
            state: TenantSettingState.unreadable,
            // The stock take panel's own two halves: nobody is asked, and
            // nothing at the register changes.
            detail:
                'Nobody is being asked to count while it stays that way, and '
                'the register is unaffected.',
          );
        }
    }
  }

  /// `Ask at the register · Mon, Thu · 4 people counting`.
  static String _scheduleDetail(TenantStockTakeSchedule schedule) {
    final enforcement = switch (schedule.enforcement) {
      TenantStockTakeEnforcement.off => 'Nobody is interrupted',
      TenantStockTakeEnforcement.prompt => 'Ask at the register',
      TenantStockTakeEnforcement.block => 'Hold the register',
    };
    final days = <int>[...schedule.weekdays]..sort();
    final people = schedule.assignments.length;
    return <String>[
      enforcement,
      if (days.isNotEmpty) days.map(_weekdayLabel).join(', '),
      if (people > 0) '$people ${people == 1 ? 'person' : 'people'} counting',
    ].join(' · ');
  }

  /// The three letters the stock take panel's own day buttons wear.
  static String _weekdayLabel(int weekday) => switch (weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    _ => 'Sun',
  };
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../services/video_call_service.dart';
import '../../theme/kleuren.dart';

/// Gedeeld actief-gesprek-scherm voor tablet én familie. Zelfde UI aan
/// beide kanten: één scherm, één ophangen-knop, twee video's.
///
/// Twee entry-points:
/// - Met [tokenToJoin] niet-null: de callee-flow (tablet komt hier
///   binnen na Beantwoorden op InkomendGesprekScherm). Scherm doet zelf
///   [VideoCallService.join] in initState en toont ondertussen een
///   dementie-vriendelijke 'Verbinden met {naam}…'-status.
/// - Met [tokenToJoin] null: de caller-flow (familie komt hier binnen
///   nadat BelScherm de room al opgezet heeft en de callee join'de).
///   Scherm gaat direct in de actief-fase; join is al gedaan.
///
/// Fase-lifecycle:
/// - _Fase.verbinden — grote rustige tekst, geen spinner
/// - _Fase.actief   — remote-video groot als beschikbaar, anders self-
///   view groot met 'Wachten tot {naam} verschijnt…'-overlay
/// - _Fase.fout     — foutmelding + sluiten-knop
///
/// Auto-pop bij [VideoCallService.roomNotifier] == null (remote heeft
/// opgehangen of netwerk-verlies). Alleen actief in _Fase.actief zodat
/// een race met een lopende join het scherm niet voortijdig sluit.
///
/// [PopScope] canPop:false blokkeert back-swipe/-knop — ophangen is de
/// enige uitweg. Dispose regelt altijd hangup zodat een force-navigate
/// of proces-kill de LiveKit-room niet open laat.
class GesprekScherm extends StatefulWidget {
  final String remoteNaam;
  final String? tokenToJoin;

  const GesprekScherm({
    super.key,
    required this.remoteNaam,
    this.tokenToJoin,
  });

  @override
  State<GesprekScherm> createState() => _GesprekSchermState();
}

enum _Fase { verbinden, actief, fout }

class _GesprekSchermState extends State<GesprekScherm> {
  late _Fase _fase;
  String _foutmelding = '';
  bool _gepop = false;

  /// BEL-S2 defensieve laag. Als de tegenpartij weggaat maar
  /// VideoCallService's ParticipantDisconnectedEvent-listener om welke
  /// reden dan ook zou missen (LiveKit-race, subscription-fout), dan
  /// blijft de gebruiker anders in de "Wachten tot X verschijnt…"-overlay
  /// hangen. Deze timer pop't ons scherm alsnog na ~5s stilte.
  ///
  /// Alleen bewapend nadat we ooit een remote hebben GEZIEN — voorkomt
  /// dat het scherm bij de START-fase (nog niemand verbonden) meteen
  /// weer sluit. Cancel bij nieuwe remote of eigen ophangen.
  bool _kregOoitRemote = false;
  Timer? _remoteWegTimer;
  Room? _huidigeRoom;

  @override
  void initState() {
    super.initState();
    _fase = widget.tokenToJoin != null ? _Fase.verbinden : _Fase.actief;
    VideoCallService.roomNotifier.addListener(_opRoomChange);
    _volgHuidigeRoom();
    if (widget.tokenToJoin != null) {
      _startJoin();
    }
  }

  /// Attach een luisteraar aan de actuele room (Room is ChangeNotifier).
  /// Rebind bij room-wissel via [_opRoomChange]. Idempotent — dubbele
  /// attach doet niets.
  void _volgHuidigeRoom() {
    final room = VideoCallService.roomNotifier.value;
    if (identical(room, _huidigeRoom)) return;
    _huidigeRoom?.removeListener(_opRoomVerandert);
    _huidigeRoom = room;
    room?.addListener(_opRoomVerandert);
    if (room != null) _opRoomVerandert();
  }

  /// Reageert op elke room-notify (participant-join, participant-leave,
  /// track-updates). Bewaakt de "ooit remote gehad → nu weg → wacht kort
  /// dan pop"-heuristiek als vangnet naast BEL-D FIX4 / BEL-S2 in
  /// VideoCallService.
  void _opRoomVerandert() {
    final room = _huidigeRoom;
    if (room == null) return;
    final hebRemote = room.remoteParticipants.isNotEmpty;
    if (hebRemote) {
      if (!_kregOoitRemote) _kregOoitRemote = true;
      _remoteWegTimer?.cancel();
      _remoteWegTimer = null;
      return;
    }
    // Remote is 0. Alleen actie als we ooit een remote hadden EN in
    // actief-fase EN geen timer al draait.
    if (!_kregOoitRemote) return;
    if (_fase != _Fase.actief) return;
    if (_remoteWegTimer != null) return;
    _remoteWegTimer = Timer(const Duration(seconds: 5), () {
      final rNu = _huidigeRoom;
      if (rNu == null || rNu.remoteParticipants.isNotEmpty) return;
      // Nog steeds leeg na 5s — behandel als "andere kant is weg" en
      // sluit netjes. Hangup zet roomNotifier=null, _opRoomChange pop't.
      unawaited(VideoCallService.hangup());
      _popEenmaal();
    });
  }

  Future<void> _startJoin() async {
    try {
      await VideoCallService.join(widget.tokenToJoin!);
      if (!mounted) return;
      setState(() => _fase = _Fase.actief);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.fout;
        _foutmelding = e.toString();
      });
    }
  }

  void _opRoomChange() {
    // BEL-S2: re-bind de room-listener zodra roomNotifier een nieuw
    // Room-instance krijgt. Nu de room wisselt (bijv. na een cold-start
    // of hangup + nieuwe join) blijft _opRoomVerandert aan de juiste
    // room hangen.
    _volgHuidigeRoom();
    if (VideoCallService.roomNotifier.value != null) return;
    // Room is null — verbroken door remote of eigen hangup. Alleen
    // pop als we in actief-fase zijn: tijdens verbinden kan een race
    // met join() een korte null-flikker geven die we niet als
    // "verbroken" willen tellen.
    if (_fase != _Fase.actief) return;
    _popEenmaal();
  }

  Future<void> _ophangen() async {
    if (_gepop) return;
    _gepop = true;
    await VideoCallService.hangup();
    _popEenmaal();
  }

  void _popEenmaal() {
    if (!mounted) return;
    if (!Navigator.of(context).canPop()) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    VideoCallService.roomNotifier.removeListener(_opRoomChange);
    // BEL-S2 opruimen: cancel timer + detach van room-notifier.
    _remoteWegTimer?.cancel();
    _remoteWegTimer = null;
    _huidigeRoom?.removeListener(_opRoomVerandert);
    _huidigeRoom = null;
    // Onvoorwaardelijke hangup: dekt back-swipe (mag niet, maar
    // defense-in-depth), force-navigate en proces-kill. Idempotent.
    unawaited(VideoCallService.hangup());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Category 2 — bewust full-bleed: zwarte achtergrond loopt via
    // edge-to-edge achter de systeem-balken. Alle bedieningselementen
    // (ophangen-knop, local-video-thumbnail) zitten binnen SafeArea.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _bouwInhoud()),
      ),
    );
  }

  Widget _bouwInhoud() {
    switch (_fase) {
      case _Fase.verbinden:
        return _bouwVerbinden();
      case _Fase.actief:
        return _bouwActief();
      case _Fase.fout:
        return _bouwFout();
    }
  }

  /// Dementie-vriendelijke tussenstatus: alleen grote rustige tekst,
  /// geen spinner-geweld. De ontvanger zit nooit naar een leeg of
  /// bevroren scherm.
  Widget _bouwVerbinden() {
    return Center(
      child: Padding(padding: const EdgeInsets.all(32),
        child: Text('Verbinden met ${widget.remoteNaam}…',
            style: const TextStyle(color: kWhite, fontSize: 28,
                fontWeight: FontWeight.w800),
            textAlign: TextAlign.center)),
    );
  }

  Widget _bouwActief() {
    return ValueListenableBuilder<Room?>(
      valueListenable: VideoCallService.roomNotifier,
      builder: (context, room, _) {
        if (room == null) {
          // Wordt bijna direct gepop door _opRoomChange, maar toont
          // kort iets nets in plaats van een lege ColoredBox.
          return _bouwVerbroken();
        }
        return AnimatedBuilder(
          animation: room,
          builder: (context, _) {
            final remoteTrack = _remoteVideoTrack(room);
            final localTrack = _localVideoTrack(room);
            if (remoteTrack == null) {
              return _bouwWachten(localTrack);
            }
            return _bouwGesprek(remoteTrack, localTrack);
          },
        );
      },
    );
  }

  /// Self-view groot in beeld met een rustige overlay 'Wachten tot
  /// {naam} verschijnt…'. Ontvanger ziet nooit een leeg scherm nadat
  /// de verbinding staat maar vóór de remote video binnenkomt.
  Widget _bouwWachten(VideoTrack? localTrack) {
    return Stack(children: [
      Positioned.fill(
        child: localTrack == null
            ? const ColoredBox(color: Colors.black)
            : VideoTrackRenderer(localTrack),
      ),
      Positioned(
        top: 32, left: 20, right: 20,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(14)),
          child: Text('Wachten tot ${widget.remoteNaam} verschijnt…',
              style: const TextStyle(color: kWhite, fontSize: 20,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
        ),
      ),
      Positioned(
        bottom: 32, left: 0, right: 0,
        child: Center(child: _ophangKnop()),
      ),
    ]);
  }

  Widget _bouwGesprek(VideoTrack remoteTrack, VideoTrack? localTrack) {
    return Stack(children: [
      Positioned.fill(child: VideoTrackRenderer(remoteTrack)),
      if (localTrack != null)
        Positioned(
          bottom: 130, right: 20,
          child: Container(
            width: 150, height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kWhite, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: VideoTrackRenderer(localTrack),
            ),
          ),
        ),
      Positioned(
        bottom: 32, left: 0, right: 0,
        child: Center(child: _ophangKnop()),
      ),
    ]);
  }

  Widget _bouwVerbroken() {
    return Center(
      child: Text('Gesprek beëindigd',
          style: TextStyle(color: kWhite.withOpacity(0.9), fontSize: 20,
              fontWeight: FontWeight.w700)),
    );
  }

  Widget _bouwFout() {
    return Center(
      child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: kRood, size: 48),
          const SizedBox(height: 16),
          const Text('Verbinding mislukt',
              style: TextStyle(color: kWhite, fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_foutmelding,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          _ophangKnop(label: 'Sluiten'),
        ])),
    );
  }

  Widget _ophangKnop({String label = 'Ophangen'}) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: kRood,
        foregroundColor: kWhite,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: _ophangen,
      icon: const Icon(Icons.call_end_rounded, size: 28),
      label: Text(label,
          style: const TextStyle(fontSize: 20,
              fontWeight: FontWeight.w900)),
    );
  }

  /// Eerste remote video-track die actief (niet-null) is. In LiveKit
  /// Dart 2.x is remoteParticipants een Map<String, RemoteParticipant>
  /// per identity. Voor V3 is er precies één remote (de andere kant);
  /// de loop is voorbereiding op multiparty in latere fasen.
  VideoTrack? _remoteVideoTrack(Room room) {
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        final track = pub.track;
        if (track != null) return track;
      }
    }
    return null;
  }

  VideoTrack? _localVideoTrack(Room room) {
    final pubs = room.localParticipant?.videoTrackPublications ?? const [];
    return pubs.isNotEmpty ? pubs.first.track : null;
  }
}

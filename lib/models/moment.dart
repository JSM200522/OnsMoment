class Moment {
  final String id;
  final String vanUid;
  final String vanNaam;
  final String naarUid;
  final String type; // 'audio' | 'foto' | 'video' | 'muziek'
  final String mediaUrl;
  final String? bericht;
  final DateTime geplandOp;
  final bool herhalen;
  final bool afgespeeld;
  final DateTime? afgespeeldOp;

  Moment({
    required this.id, required this.vanUid, required this.vanNaam,
    required this.naarUid, required this.type, required this.mediaUrl,
    this.bericht, required this.geplandOp,
    this.herhalen = false, this.afgespeeld = false, this.afgespeeldOp,
  });

  factory Moment.fromFirestore(Map<String, dynamic> d, String id) => Moment(
    id: id, vanUid: d['vanUid']??'', vanNaam: d['vanNaam']??'Familie',
    naarUid: d['naarUid']??'', type: d['type']??'audio',
    mediaUrl: d['mediaUrl']??'', bericht: d['bericht'],
    geplandOp: DateTime.fromMillisecondsSinceEpoch(d['geplandOp']),
    herhalen: d['herhalen']??false, afgespeeld: d['afgespeeld']??false,
    afgespeeldOp: d['afgespeeldOp']!=null
        ? DateTime.fromMillisecondsSinceEpoch(d['afgespeeldOp']) : null,
  );

  Map<String, dynamic> toFirestore() => {
    'vanUid': vanUid, 'vanNaam': vanNaam, 'naarUid': naarUid,
    'type': type, 'mediaUrl': mediaUrl, 'bericht': bericht,
    'geplandOp': geplandOp.millisecondsSinceEpoch,
    'herhalen': herhalen, 'afgespeeld': afgespeeld,
    'afgespeeldOp': afgespeeldOp?.millisecondsSinceEpoch,
  };

  String get typeIcon { switch(type) {
    case 'audio': return '🎙️'; case 'foto': return '📸';
    case 'video': return '🎬'; case 'muziek': return '🎵';
    default: return '💬'; }}

  String get typeLabel { switch(type) {
    case 'audio': return 'Stemberichtje'; case 'foto': return 'Foto';
    case 'video': return 'Filmpje'; case 'muziek': return 'Muziek';
    default: return 'Bericht'; }}
}

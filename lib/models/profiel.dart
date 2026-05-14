class Profiel {
  final String uid, naam, rol;
  final String? fotoUrl, tabletUid, wektijd, favorietLiedje;
  Profiel({required this.uid, required this.naam, required this.rol,
    this.fotoUrl, this.tabletUid, this.wektijd, this.favorietLiedje});
  factory Profiel.fromFirestore(Map<String, dynamic> d, String uid) => Profiel(
    uid: uid, naam: d['naam']??'', rol: d['rol']??'familie',
    fotoUrl: d['fotoUrl'], tabletUid: d['tabletUid'],
    wektijd: d['wektijd'], favorietLiedje: d['favorietLiedje'],
  );
  Map<String, dynamic> toFirestore() => {
    'naam': naam, 'rol': rol, 'fotoUrl': fotoUrl,
    'tabletUid': tabletUid, 'wektijd': wektijd,
    'favorietLiedje': favorietLiedje,
  };
}

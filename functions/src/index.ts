/**
 * Cloud Functions voor Ons Moment push-meldingen.
 *
 * Runtime: Node 22, region europe-west1 (matcht Firestore eur3 multi-region),
 * firebase-functions v2 API.
 *
 * Commit 3a: alleen boilerplate — nog geen exports. De onNieuwMoment
 * Firestore-trigger volgt in commit 3b, met payload-conventie:
 * - notification.android.channel_id via PushService.channelIdVoorGeluid
 *   (lib/services/push_service.dart in de Flutter-app — houd synchroon)
 * - data.momentId → tik op tray-melding opent bijbehorende popup
 */

// Bewust nog geen exports — een deploy op deze staat produceert
// "0 functions to deploy", wat expliciet is voor de skelet-fase.
export {};

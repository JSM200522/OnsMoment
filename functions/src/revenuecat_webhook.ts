/**
 * revenuecatWebhook — server-only tier/abonnement updates (FASE D-2).
 *
 * RevenueCat POST'ert bij elke subscription-wijziging (INITIAL_PURCHASE,
 * RENEWAL, CANCELLATION, EXPIRATION, BILLING_ISSUE, PRODUCT_CHANGE) naar
 * deze endpoint. Deze Cloud Function verifieert de payload en schrijft
 * server-side de bijgewerkte tier + abonnement.actief + abonnement.vervalOp
 * naar gebruikers/{uid} — de enige weg om die velden te muteren want de
 * D-1 Firestore-rules blokkeren client-writes op tier/abonnement.
 *
 * SECURITY:
 * Verificatie via een gedeelde Authorization-header. RevenueCat's
 * dashboard laat toe om een custom Authorization-header mee te sturen op
 * elke webhook-call (bijv. 'Bearer <secret>'). Wij zetten die secret in
 * Firebase Secret Manager (REVENUECAT_WEBHOOK_SECRET) en checken hem hier.
 * Deze aanpak is eenvoudiger dan HMAC-signature-verificatie en wordt
 * expliciet aanbevolen door RevenueCat voor webhooks.
 *
 * Zolang REVENUECAT_WEBHOOK_SECRET niet is gezet, wijst de function
 * elke request af met 503 — nooit accidenteel open.
 *
 * Firebase user-koppeling: de app roept
 * `Purchases.logIn(uid)` aan zodra een user is ingelogd. RevenueCat
 * neemt die uid over als `app_user_id` en stuurt hem mee in elk event
 * (event.app_user_id). Dat is onze sleutel naar gebruikers/{uid}.
 *
 * ENTITLEMENTS:
 * RevenueCat definieert de entitlements 'klein' en 'groot' (elk gekoppeld
 * aan de bijbehorende maand+jaar-producten). We mappen event-payloads
 * naar tier = 'klein' | 'groot' op basis van de actieve entitlement.
 */

import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import * as admin from 'firebase-admin';

const REVENUECAT_WEBHOOK_SECRET = defineSecret('REVENUECAT_WEBHOOK_SECRET');

// Events waarop we een actief abonnement TERUG zetten naar Firestore.
const ACTIEF_EVENTS = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'PRODUCT_CHANGE',
  'UNCANCELLATION',
]);

// Events die abonnement.actief=false zetten (tier blijft tot vervalOp).
const INACTIEF_EVENTS = new Set([
  'CANCELLATION',       // user heeft opgezegd; loopt door tot vervalOp
  'EXPIRATION',         // definitief afgelopen
  'BILLING_ISSUE',      // betaling mislukt
  'SUBSCRIPTION_PAUSED',
]);

// Events die we loggen maar niet naar Firestore schrijven.
const NEGEER_EVENTS = new Set([
  'TEST',               // RevenueCat dashboard "Send test webhook"
  'TRANSFER',           // abonnement verplaatst tussen accounts
  'SUBSCRIBER_ALIAS',   // uid-alias, geen tier-wijziging
]);

interface RcEventPayload {
  event: {
    type?: string;
    app_user_id?: string;
    original_app_user_id?: string;
    product_id?: string;
    entitlement_ids?: string[];
    entitlement_id?: string;
    expiration_at_ms?: number;
    id?: string;
  };
  api_version?: string;
}

/**
 * Map entitlement-IDs uit de payload naar onze tier-string.
 * RevenueCat kan zowel entitlement_ids (v2, array) als entitlement_id
 * (v1, string) sturen — we accepteren beide.
 */
function bepaalTier(payload: RcEventPayload): 'klein' | 'groot' | null {
  const ids = payload.event.entitlement_ids
    ?? (payload.event.entitlement_id ? [payload.event.entitlement_id] : []);
  if (ids.includes('groot')) return 'groot';
  if (ids.includes('klein')) return 'klein';
  return null;
}

export const revenuecatWebhook = onRequest(
  {
    region: 'europe-west1',
    secrets: [REVENUECAT_WEBHOOK_SECRET],
    // RevenueCat retry't zelf tot 5x met exponential backoff, dus 60s
    // is ruim voldoende. Memory-default is prima — geen media in scope.
    timeoutSeconds: 60,
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method not allowed');
      return;
    }

    // Signature-verificatie via Authorization-header.
    const secret = REVENUECAT_WEBHOOK_SECRET.value().trim();
    if (!secret) {
      logger.error('REVENUECAT_WEBHOOK_SECRET niet geconfigureerd');
      res.status(503).send('Server not configured');
      return;
    }
    const auth = req.get('Authorization') ?? '';
    const verwacht = `Bearer ${secret}`;
    if (auth !== verwacht) {
      logger.warn('webhook auth mismatch', {
        heeftHeader: auth.length > 0,
        headerLengte: auth.length,
      });
      res.status(401).send('Unauthorized');
      return;
    }

    const payload = req.body as RcEventPayload | undefined;
    const evt = payload?.event;
    if (!evt || typeof evt.type !== 'string') {
      logger.warn('webhook zonder geldig event', { body: req.body });
      res.status(400).send('Invalid payload');
      return;
    }

    const type = evt.type;
    const uid = (evt.app_user_id ?? '').trim();

    if (NEGEER_EVENTS.has(type)) {
      logger.info('webhook event genegeerd', { type, uid, eventId: evt.id });
      res.status(200).send('OK (ignored)');
      return;
    }

    // Voor TEST-events accepteert RevenueCat dashboard elke 2xx als
    // "endpoint reachable" — al door NEGEER_EVENTS afgehandeld.

    if (!uid) {
      logger.warn('webhook zonder app_user_id — skip', { type, eventId: evt.id });
      res.status(200).send('OK (no uid)');
      return;
    }

    const db = admin.firestore();
    const gebruikersRef = db.collection('gebruikers').doc(uid);

    try {
      if (ACTIEF_EVENTS.has(type)) {
        const tier = bepaalTier(payload!);
        if (!tier) {
          logger.warn('actief-event zonder herkenbare entitlement', {
            type, uid, eventId: evt.id,
            entitlements: evt.entitlement_ids ?? evt.entitlement_id,
          });
          res.status(200).send('OK (no entitlement)');
          return;
        }
        const vervalOp = typeof evt.expiration_at_ms === 'number'
          ? admin.firestore.Timestamp.fromMillis(evt.expiration_at_ms)
          : null;
        await gebruikersRef.set({
          tier,
          abonnement: {
            actief: true,
            vervalOp,
            laatsteEvent: type,
            laatsteEventOp: admin.firestore.FieldValue.serverTimestamp(),
            productId: evt.product_id ?? null,
          },
        }, { merge: true });
        logger.info('tier gezet via webhook', {
          type, uid, tier, vervalOp: vervalOp?.toMillis() ?? null,
        });
        res.status(200).send('OK');
        return;
      }

      if (INACTIEF_EVENTS.has(type)) {
        // Tier blijft staan — user houdt toegang tot vervalOp. Alleen
        // abonnement.actief gaat op false zodat trial-lock hem straks
        // richting PakketKeuzeScherm kan sturen bij verval.
        await gebruikersRef.set({
          abonnement: {
            actief: false,
            laatsteEvent: type,
            laatsteEventOp: admin.firestore.FieldValue.serverTimestamp(),
          },
        }, { merge: true });
        logger.info('abonnement inactief-flag gezet via webhook', {
          type, uid,
        });
        res.status(200).send('OK');
        return;
      }

      // Onbekend event-type: log + accepteer (nooit retry veroorzaken).
      logger.info('webhook onbekend event-type — accept', {
        type, uid, eventId: evt.id,
      });
      res.status(200).send('OK (unknown)');
    } catch (e) {
      logger.error('webhook Firestore-write faalde', {
        type, uid, error: String(e),
      });
      // 500 zodat RevenueCat retry't — Firestore-storing is tijdelijk.
      res.status(500).send('Internal error');
    }
  },
);

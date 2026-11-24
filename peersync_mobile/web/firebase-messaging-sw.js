/*
 * PeerSync — Firebase Cloud Messaging background worker (web).
 *
 * The Firebase JS SDK registers this file under the dedicated scope
 * `/firebase-cloud-messaging-push-scope`, so it does not replace Flutter's own
 * generated `flutter_service_worker.js` (which caches the app shell for offline
 * use). Both workers therefore coexist.
 *
 * This worker only runs while the tab is closed or in the background; when the
 * app is in the foreground, `PushNotificationService` handles the message in
 * Dart so the user sees an in-app banner instead of a duplicate system
 * notification.
 */

/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/11.0.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.0.2/firebase-messaging-compat.js');

// Must match DefaultFirebaseOptions.web in lib/firebase_options.dart.
firebase.initializeApp({
  apiKey: 'AIzaSyBuevBh5QmuwMuOpw3tAZRsamAHXAFgE-U',
  appId: '1:2017657524:web:b8387e3f50eddef9280de1',
  messagingSenderId: '2017657524',
  projectId: 'peersync-11326',
  authDomain: 'peersync-11326.firebaseapp.com',
  storageBucket: 'peersync-11326.firebasestorage.app',
  measurementId: 'G-HVXFXLKSLW',
});

const messaging = firebase.messaging();

// Fallback for messages that arrive without a `notification` block: build the
// notification ourselves from the data payload.
messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};

  const title = notification.title || data.title || 'PeerSync';
  const body =
    notification.body ||
    data.body ||
    data.description ||
    'You have a new update in PeerSync.';

  const destination = data.destination || 'dashboard';

  self.registration.showNotification(title, {
    body: body,
    icon: 'icons/Icon-192.png',
    badge: 'icons/favicon-48.png',
    tag: data.notificationId || data.type || 'peersync',
    renotify: false,
    data: { destination: destination, url: data.url || './' },
  });
});

// Focus an existing PeerSync tab when the notification is tapped, or open one.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const destination =
    (event.notification.data && event.notification.data.destination) ||
    'dashboard';

  const targetUrl = new URL('./?destination=' + destination, self.location.origin)
    .href;

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if (client.url.startsWith(self.registration.scope) && 'focus' in client) {
            if ('navigate' in client) {
              client.navigate(targetUrl).catch(() => {});
            }
            return client.focus();
          }
        }
        return self.clients.openWindow(targetUrl);
      }),
  );
});

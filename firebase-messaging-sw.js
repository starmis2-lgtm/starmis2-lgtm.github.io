/* ===== GITHUB REPO  ·  file name: firebase-messaging-sw.js ===== */
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBU-9r2Yr9lVyjKlHQ_iP_m89g3Me07zcY',
  authDomain: 'sg-compliance-256ad.firebaseapp.com',
  projectId: 'sg-compliance-256ad',
  storageBucket: 'sg-compliance-256ad.firebasestorage.app',
  messagingSenderId: '705866355489',
  appId: '1:705866355489:web:dfd48cb6ff18d603632460'
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  const n = payload.notification || {};
  self.registration.showNotification(n.title || 'Compliance Checklist', {
    body: n.body || '',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    tag: 'cc-' + (n.title || 'msg'),
    data: { url: '/' }
  });
});

self.addEventListener('notificationclick', function (e) {
  e.notification.close();
  e.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true })
    .then(function (list) {
      for (let i = 0; i < list.length; i++) {
        if (list[i].url.indexOf(self.location.origin) === 0 && 'focus' in list[i]) {
          return list[i].focus();
        }
      }
      return clients.openWindow('/');
    }));
});

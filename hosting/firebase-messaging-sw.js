// Background push handler for the web app.
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBOM4IBHOF_RRmT8GlnrfXZEyGaJSBYl0I',
  appId: '1:719992577476:web:3c855bff713f9139979891',
  messagingSenderId: '719992577476',
  projectId: 'mdn777-bbed6',
  authDomain: 'mdn777-bbed6.firebaseapp.com',
  storageBucket: 'mdn777-bbed6.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = (payload.notification && payload.notification.title) || 'Staff Connect';
  const body = (payload.notification && payload.notification.body) || '';
  self.registration.showNotification(title, {
    body: body,
    icon: '/app/icons/Icon-192.png',
    data: payload.data || {},
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow('/app/'));
});

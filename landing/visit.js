/* Visitor statistics for statistics.claudeswitch.dev. One beacon per arrival on the site: moving
   between pages and reloading are skipped. Nothing is stored in the browser and no cookie is set;
   the collector counts unique visitors with a daily hash and never stores the IP address. */
(function () {
  try {
    var nav = performance.getEntriesByType('navigation')[0];
    if ((nav && nav.type === 'reload') || document.referrer.indexOf(location.origin) === 0) return;
    var utm = new URLSearchParams(location.search);
    var body = JSON.stringify({
      path: location.pathname,
      referrer: document.referrer || null,
      utm_source: utm.get('utm_source'),
      utm_medium: utm.get('utm_medium'),
      utm_campaign: utm.get('utm_campaign'),
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      locale: navigator.language
    });
    navigator.sendBeacon('https://claude-switch-telemetry-507906352164.europe-west1.run.app/visit',
      new Blob([body], { type: 'text/plain' }));
  } catch (e) {
    // Statistics never get in the way of the page.
  }
})();

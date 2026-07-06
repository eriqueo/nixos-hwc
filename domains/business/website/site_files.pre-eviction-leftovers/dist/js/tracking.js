/**
 * Heartwood Craft — Analytics & Attribution Layer
 * Pushes events to dataLayer for GTM to route to GA4 + Google Ads
 */

// ============================================
// Initialize dataLayer
// ============================================
window.dataLayer = window.dataLayer || [];

// ============================================
// A. UTM ATTRIBUTION PERSISTENCE
// ============================================
(function() {
  var params = new URLSearchParams(window.location.search);
  var utmKeys = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term', 'gclid'];
  var hasUtm = utmKeys.some(function(k) { return params.get(k); });

  if (hasUtm && !sessionStorage.getItem('hwc_attribution')) {
    var attribution = {};
    utmKeys.forEach(function(k) {
      var v = params.get(k);
      if (v) {
        attribution[k] = v;
        sessionStorage.setItem('hwc_' + k, v);
      }
    });
    attribution.referrer = document.referrer || '';
    attribution.landing_page = window.location.pathname;
    attribution.timestamp = new Date().toISOString();
    sessionStorage.setItem('hwc_attribution', JSON.stringify(attribution));
  } else if (!sessionStorage.getItem('hwc_attribution')) {
    sessionStorage.setItem('hwc_attribution', JSON.stringify({
      referrer: document.referrer || '',
      landing_page: window.location.pathname,
      timestamp: new Date().toISOString()
    }));
  }

  var views = parseInt(sessionStorage.getItem('hwc_pages_viewed') || '0', 10);
  sessionStorage.setItem('hwc_pages_viewed', String(views + 1));
})();

// ============================================
// B. EVENT HELPER (push to dataLayer)
// ============================================
function hwcTrack(name, params) {
  window.dataLayer.push(Object.assign({ event: name }, params || {}));
}

// Make available globally for the calculator app
window.hwcTrack = hwcTrack;

// ============================================
// C. SITEWIDE EVENTS
// ============================================
document.addEventListener('DOMContentLoaded', function() {

  // Phone clicks (TIER 1 — primary conversion)
  document.querySelectorAll('a[href^="tel:"]').forEach(function(link) {
    link.addEventListener('click', function() {
      hwcTrack('phone_call_click', {
        click_location: getSection(link),
        page_path: window.location.pathname
      });
    });
  });

  // Email clicks (TIER 2)
  document.querySelectorAll('a[href^="mailto:"]').forEach(function(link) {
    link.addEventListener('click', function() {
      hwcTrack('email_click', {
        click_location: getSection(link),
        page_path: window.location.pathname
      });
    });
  });

  // CTA clicks (TIER 3) — skip phone/email links already tracked above
  document.querySelectorAll('a[href*="/contact"], a.btn-primary, a.btn-secondary, a.btn-get-started').forEach(function(link) {
    var href = link.getAttribute('href') || '';
    if (href.indexOf('tel:') === 0 || href.indexOf('mailto:') === 0) return;

    link.addEventListener('click', function() {
      hwcTrack('cta_click', {
        cta_text: link.textContent.trim().substring(0, 50),
        cta_url: href,
        cta_location: getSection(link),
        page_path: window.location.pathname
      });
    });
  });

  // Service tile clicks (TIER 3)
  document.querySelectorAll('.service-card, [data-service-tile]').forEach(function(tile) {
    tile.addEventListener('click', function() {
      var name = tile.dataset.serviceTile ||
                 (tile.querySelector('h3, .service-title') ? tile.querySelector('h3, .service-title').textContent.trim() : 'unknown');
      hwcTrack('service_tile_click', {
        service_name: name,
        page_path: window.location.pathname
      });
    });
  });

  // Form start: first focus on any form input (TIER 2)
  var formStarted = {};
  document.querySelectorAll('form').forEach(function(form) {
    var formId = form.id || 'unknown';
    form.querySelectorAll('input, select, textarea').forEach(function(el) {
      el.addEventListener('focus', function() {
        if (!formStarted[formId]) {
          formStarted[formId] = true;
          hwcTrack('form_start', {
            form_id: formId,
            form_location: window.location.pathname
          });
        }
      }, { once: true });
    });
  });

  // Nav clicks (TIER 3)
  document.querySelectorAll('nav a, .nav-list a, .nav-mobile-list a').forEach(function(link) {
    link.addEventListener('click', function() {
      hwcTrack('nav_click', {
        nav_item: link.textContent.trim(),
        page_path: window.location.pathname
      });
    });
  });
});

function getSection(el) {
  var section = el.closest('[data-section]');
  if (section) return section.dataset.section;
  if (el.closest('header, .site-header')) return 'header';
  if (el.closest('footer, .site-footer')) return 'footer';
  if (el.closest('.hero, .hero-section')) return 'hero';
  return 'page';
}

// ============================================
// D. PAGE-SPECIFIC TRACKING
// ============================================
(function() {
  var path = window.location.pathname;

  // Portfolio page: track section views (TIER 3)
  if (path === '/our-work/' || path === '/our-work') {
    var observedSections = {};
    var observer = new IntersectionObserver(function(entries) {
      entries.forEach(function(entry) {
        if (entry.isIntersecting) {
          var name = entry.target.dataset.portfolioSection || 'unknown';
          if (!observedSections[name]) {
            observedSections[name] = true;
            hwcTrack('portfolio_section_view', { section_name: name });
          }
        }
      });
    }, { threshold: 0.3 });

    document.querySelectorAll('[data-portfolio-section]').forEach(function(el) {
      observer.observe(el);
    });
  }

  // Blog posts: track 50% read depth (TIER 3)
  if (path.match(/^\/[a-z0-9]/) && document.querySelector('.blog-body')) {
    var articleContent = document.querySelector('.blog-body');
    var halfwayFired = false;
    window.addEventListener('scroll', function checkScroll() {
      if (halfwayFired) return;
      var rect = articleContent.getBoundingClientRect();
      var articleTop = rect.top + window.scrollY;
      var halfway = articleTop + (rect.height / 2);
      if (window.scrollY + window.innerHeight >= halfway) {
        halfwayFired = true;
        hwcTrack('blog_post_read', { post_slug: path.replace(/^\/|\/$/g, '') });
        window.removeEventListener('scroll', checkScroll);
      }
    }, { passive: true });
  }

  // Service page views (TIER 3)
  var serviceMap = {
    '/bathroom/remodeling/': 'bathroom',
    '/basement/remodeling/': 'basement',
    '/remodeling/': 'general',
    '/aging-in-place/': 'universal_design'
  };
  if (serviceMap[path]) {
    hwcTrack('service_page_view', { service_type: serviceMap[path] });
  }
})();

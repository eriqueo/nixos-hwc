/**
 * Heartwood Craft — Analytics & Attribution Layer
 * GA4 engagement events + UTM attribution passthrough
 */

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
      if (v) attribution[k] = v;
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
// B. GA4 CUSTOM EVENTS
// ============================================
document.addEventListener('DOMContentLoaded', function() {
  // Phone clicks
  document.querySelectorAll('a[href^="tel:"]').forEach(function(link) {
    link.addEventListener('click', function() {
      gtag('event', 'phone_click', {
        click_location: getSection(link)
      });
    });
  });

  // Email clicks
  document.querySelectorAll('a[href^="mailto:"]').forEach(function(link) {
    link.addEventListener('click', function() {
      gtag('event', 'email_click', {
        click_location: getSection(link)
      });
    });
  });

  // CTA clicks
  document.querySelectorAll('a[href*="/contact"], a.btn-primary, a.btn-secondary').forEach(function(link) {
    link.addEventListener('click', function() {
      gtag('event', 'cta_click', {
        cta_text: link.textContent.trim().substring(0, 50),
        cta_url: link.getAttribute('href'),
        cta_location: getSection(link),
        page_path: window.location.pathname
      });
    });
  });

  // Form start: first focus on any form input
  var formStarted = false;
  document.querySelectorAll('form input, form select, form textarea').forEach(function(el) {
    el.addEventListener('focus', function() {
      if (!formStarted) {
        formStarted = true;
        gtag('event', 'form_start', { form_location: window.location.pathname });
      }
    }, { once: true });
  });

  // Nav clicks
  document.querySelectorAll('nav a, .nav-list a').forEach(function(link) {
    link.addEventListener('click', function() {
      gtag('event', 'nav_click', { nav_item: link.textContent.trim() });
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
// C. PAGE-SPECIFIC TRACKING
// ============================================
(function() {
  var path = window.location.pathname;

  // Portfolio page: track section views
  if (path === '/our-work/' || path === '/our-work') {
    var observedSections = {};
    var observer = new IntersectionObserver(function(entries) {
      entries.forEach(function(entry) {
        if (entry.isIntersecting) {
          var name = entry.target.dataset.portfolioSection || 'unknown';
          if (!observedSections[name]) {
            observedSections[name] = true;
            gtag('event', 'portfolio_section_view', { section_name: name });
          }
        }
      });
    }, { threshold: 0.3 });

    document.querySelectorAll('[data-portfolio-section]').forEach(function(el) {
      observer.observe(el);
    });
  }

  // Blog posts: track 50% read depth
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
        gtag('event', 'blog_post_read', { post_slug: path.replace(/^\/|\/$/g, '') });
        window.removeEventListener('scroll', checkScroll);
      }
    }, { passive: true });
  }

  // Service pages
  var serviceMap = {
    '/bathroom/remodeling/': 'bathroom',
    '/basement/remodeling/': 'basement',
    '/remodeling/': 'general'
  };
  if (serviceMap[path]) {
    gtag('event', 'service_page_view', { service_type: serviceMap[path] });
  }
})();

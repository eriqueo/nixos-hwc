document.addEventListener('DOMContentLoaded', () => {

  // ============================================
  // 1. MOBILE NAVIGATION
  // ============================================
  const navToggle = document.querySelector('.nav-toggle');
  const navMobile = document.getElementById('nav-mobile');

  if (navToggle && navMobile) {
    navToggle.addEventListener('click', () => {
      const isOpen = !navMobile.hidden;
      navMobile.hidden = isOpen;
      navToggle.classList.toggle('active', !isOpen);
      navToggle.setAttribute('aria-expanded', String(!isOpen));
    });

    // Accordion dropdowns in mobile nav
    navMobile.querySelectorAll('.nav-mobile-dropdown-toggle').forEach(btn => {
      btn.addEventListener('click', () => {
        const dropdown = btn.nextElementSibling;
        if (!dropdown) return;
        const isOpen = !dropdown.hidden;
        dropdown.hidden = isOpen;
        btn.setAttribute('aria-expanded', String(!isOpen));
      });
    });

    // Close mobile nav when a link is clicked
    navMobile.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', () => {
        navMobile.hidden = true;
        navToggle.classList.remove('active');
        navToggle.setAttribute('aria-expanded', 'false');
      });
    });

    // Close mobile nav when clicking outside
    document.addEventListener('click', (e) => {
      if (!navMobile.hidden && !navMobile.contains(e.target) && !navToggle.contains(e.target)) {
        navMobile.hidden = true;
        navToggle.classList.remove('active');
        navToggle.setAttribute('aria-expanded', 'false');
      }
    });
  }

  // ============================================
  // 2. DESKTOP DROPDOWN NAVIGATION
  // ============================================
  const dropdownParents = document.querySelectorAll('.nav-dropdown-parent');
  let dropdownTimeout;

  dropdownParents.forEach(parent => {
    const toggle = parent.querySelector('.nav-dropdown-toggle');
    const dropdown = parent.querySelector('.nav-dropdown');
    if (!toggle || !dropdown) return;

    parent.addEventListener('mouseenter', () => {
      clearTimeout(dropdownTimeout);
      toggle.setAttribute('aria-expanded', 'true');
    });

    parent.addEventListener('mouseleave', () => {
      dropdownTimeout = setTimeout(() => {
        toggle.setAttribute('aria-expanded', 'false');
      }, 150);
    });

    // Keyboard: focus opens dropdown
    toggle.addEventListener('focus', () => {
      toggle.setAttribute('aria-expanded', 'true');
    });

    // Close on focusout if focus left the parent entirely
    parent.addEventListener('focusout', (e) => {
      if (!parent.contains(e.relatedTarget)) {
        toggle.setAttribute('aria-expanded', 'false');
      }
    });
  });

  // Escape key closes any open dropdown
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      dropdownParents.forEach(parent => {
        const toggle = parent.querySelector('.nav-dropdown-toggle');
        if (toggle) toggle.setAttribute('aria-expanded', 'false');
      });
    }
  });

  // ============================================
  // 3. STICKY HEADER
  // ============================================
  const header = document.getElementById('site-header');
  let ticking = false;

  if (header) {
    const onScroll = () => {
      if (!ticking) {
        requestAnimationFrame(() => {
          header.classList.toggle('scrolled', window.scrollY > 100);
          ticking = false;
        });
        ticking = true;
      }
    };
    window.addEventListener('scroll', onScroll, { passive: true });
  }

  // ============================================
  // 4. SMOOTH SCROLL
  // ============================================
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', (e) => {
      const targetId = anchor.getAttribute('href');
      if (targetId === '#') return;
      const target = document.querySelector(targetId);
      if (!target) return;

      e.preventDefault();
      const headerHeight = header ? header.offsetHeight : 0;
      const top = target.getBoundingClientRect().top + window.scrollY - headerHeight;
      window.scrollTo({ top, behavior: 'smooth' });

      // Close mobile nav if open
      if (navMobile && !navMobile.hidden) {
        navMobile.hidden = true;
        navToggle.classList.remove('active');
        navToggle.setAttribute('aria-expanded', 'false');
      }
    });
  });

  // ============================================
  // 5. FORM HANDLING
  // ============================================
  document.querySelectorAll('form[data-webhook]').forEach(form => {
    const webhookUrl = form.getAttribute('data-webhook');
    const successEl = form.parentElement.querySelector('.form-success');
    const errorEl = form.parentElement.querySelector('.form-error-state');

    // Clear validation on input
    form.querySelectorAll('input, select, textarea').forEach(field => {
      field.addEventListener('input', () => {
        const parent = field.closest('.form-field');
        if (parent) {
          parent.classList.remove('error');
          const msg = parent.querySelector('.form-error-msg');
          if (msg) msg.hidden = true;
        }
      });
    });

    form.addEventListener('submit', async (e) => {
      e.preventDefault();

      // Validate required fields
      let hasErrors = false;
      form.querySelectorAll('[required]').forEach(field => {
        const parent = field.closest('.form-field');
        const msg = parent ? parent.querySelector('.form-error-msg') : null;
        const isEmpty = !field.value.trim();
        const isEmailInvalid = field.type === 'email' && field.value && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(field.value);

        if (isEmpty || isEmailInvalid) {
          hasErrors = true;
          if (parent) parent.classList.add('error');
          if (msg) msg.hidden = false;
        } else {
          if (parent) parent.classList.remove('error');
          if (msg) msg.hidden = true;
        }
      });

      if (hasErrors) return;

      // Disable submit button
      const submitBtn = form.querySelector('[type="submit"]');
      const btnText = submitBtn.querySelector('.btn-text');
      const btnLoading = submitBtn.querySelector('.btn-loading');
      submitBtn.disabled = true;
      if (btnText) btnText.hidden = true;
      if (btnLoading) btnLoading.hidden = false;

      // Build payload
      const payload = {
        name: form.querySelector('[name="name"]')?.value || '',
        email: form.querySelector('[name="email"]')?.value || '',
        phone: form.querySelector('[name="phone"]')?.value || '',
        service: form.querySelector('[name="service"]')?.value || '',
        message: form.querySelector('[name="message"]')?.value || '',
        source_page: window.location.pathname,
        timestamp: new Date().toISOString()
      };

      // Attribution from sessionStorage
      try {
        var attr = JSON.parse(sessionStorage.getItem('hwc_attribution') || '{}');
        payload.utm_source = attr.utm_source || null;
        payload.utm_medium = attr.utm_medium || null;
        payload.utm_campaign = attr.utm_campaign || null;
        payload.gclid = attr.gclid || null;
        payload.referrer = attr.referrer || null;
        payload.landing_page = attr.landing_page || null;
        payload.pages_viewed = parseInt(sessionStorage.getItem('hwc_pages_viewed') || '0', 10);
      } catch(e) {}

      try {
        const res = await fetch(webhookUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        if (res.ok) {
          form.hidden = true;
          if (successEl) successEl.hidden = false;
          if (typeof gtag === 'function') {
            gtag('event', 'form_submit', {
              form_location: window.location.pathname,
              service_selected: payload.service || ''
            });
          }
        } else {
          throw new Error('Non-2xx response');
        }
      } catch {
        submitBtn.disabled = false;
        if (btnText) btnText.hidden = false;
        if (btnLoading) btnLoading.hidden = true;
        if (errorEl) errorEl.hidden = false;
        if (typeof gtag === 'function') {
          gtag('event', 'form_error', { form_location: window.location.pathname });
        }
      }
    });
  });

  // ============================================
  // 6. SCROLL ANIMATIONS
  // ============================================
  const animateEls = document.querySelectorAll('.animate-in');
  if (animateEls.length && 'IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          // Stagger animations within grids
          const parent = entry.target.parentElement;
          if (parent && (parent.classList.contains('services-grid') || parent.classList.contains('testimonial-grid') || parent.classList.contains('blog-grid'))) {
            const siblings = Array.from(parent.children);
            const index = siblings.indexOf(entry.target);
            entry.target.style.transitionDelay = `${index * 0.1}s`;
          }
          entry.target.classList.add('visible');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.1 });

    animateEls.forEach(el => observer.observe(el));
  }

  // ============================================
  // 7. IMAGE LIGHTBOX
  // ============================================
  document.querySelectorAll('[data-lightbox]').forEach(img => {
    img.style.cursor = 'zoom-in';
    img.addEventListener('click', () => {
      const overlay = document.createElement('div');
      overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.9);z-index:9999;display:flex;align-items:center;justify-content:center;cursor:zoom-out;';

      const closeBtn = document.createElement('button');
      closeBtn.textContent = '\u00D7';
      closeBtn.style.cssText = 'position:absolute;top:1rem;right:1.5rem;background:none;border:none;color:white;font-size:2.5rem;cursor:pointer;line-height:1;z-index:10000;';
      closeBtn.setAttribute('aria-label', 'Close lightbox');

      const fullImg = document.createElement('img');
      fullImg.src = img.src;
      fullImg.alt = img.alt || '';
      fullImg.style.cssText = 'max-width:90vw;max-height:90vh;object-fit:contain;border-radius:4px;';

      const close = () => overlay.remove();
      overlay.addEventListener('click', close);
      closeBtn.addEventListener('click', (e) => { e.stopPropagation(); close(); });
      document.addEventListener('keydown', function handler(e) {
        if (e.key === 'Escape') { close(); document.removeEventListener('keydown', handler); }
      });

      overlay.appendChild(closeBtn);
      overlay.appendChild(fullImg);
      document.body.appendChild(overlay);
    });
  });

});

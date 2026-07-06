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

      // Honeypot check: silently fake success for bots
      const hp = form.querySelector('[name="website"]');
      if (hp && hp.value) {
        form.hidden = true;
        if (successEl) successEl.hidden = false;
        return;
      }

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
  // 7. IMAGE LIGHTBOX (gallery-aware)
  // ============================================
  // Build gallery groups: each .project-images is a gallery, plus standalone [data-lightbox] imgs.
  const galleries = [];
  document.querySelectorAll('.project-images').forEach(container => {
    const imgs = Array.from(container.querySelectorAll('img'));
    if (!imgs.length) return;
    const groupIdx = galleries.length;
    galleries.push(imgs);
    imgs.forEach((img, i) => {
      img.dataset.galleryGroup = groupIdx;
      img.dataset.galleryIndex = i;
    });
  });
  // Standalone lightbox images (not in a gallery)
  document.querySelectorAll('[data-lightbox]').forEach(img => {
    if (img.dataset.galleryGroup != null) return;
    const groupIdx = galleries.length;
    galleries.push([img]);
    img.dataset.galleryGroup = groupIdx;
    img.dataset.galleryIndex = 0;
  });

  // Lightbox open/navigate
  function openLightbox(groupIdx, startIdx) {
    const group = galleries[groupIdx];
    if (!group || !group.length) return;
    let idx = startIdx;

    const overlay = document.createElement('div');
    overlay.className = 'hwc-lightbox';

    const closeBtn = document.createElement('button');
    closeBtn.className = 'hwc-lightbox__close';
    closeBtn.innerHTML = '&times;';
    closeBtn.setAttribute('aria-label', 'Close');

    const fullImg = document.createElement('img');
    fullImg.draggable = false;

    const counter = document.createElement('div');
    counter.className = 'hwc-lightbox__counter';

    overlay.appendChild(closeBtn);
    overlay.appendChild(fullImg);

    let prevBtn, nextBtn;
    if (group.length > 1) {
      prevBtn = document.createElement('button');
      prevBtn.className = 'hwc-lightbox__prev';
      prevBtn.innerHTML = '&#8249;';
      prevBtn.setAttribute('aria-label', 'Previous');
      nextBtn = document.createElement('button');
      nextBtn.className = 'hwc-lightbox__next';
      nextBtn.innerHTML = '&#8250;';
      nextBtn.setAttribute('aria-label', 'Next');
      overlay.appendChild(prevBtn);
      overlay.appendChild(nextBtn);
      overlay.appendChild(counter);
    }

    function show(i) {
      idx = (i + group.length) % group.length;
      fullImg.src = group[idx].src;
      fullImg.alt = group[idx].alt || '';
      if (counter) counter.textContent = (idx + 1) + ' / ' + group.length;
    }

    function close() {
      overlay.classList.remove('active');
      setTimeout(() => overlay.remove(), 200);
      document.removeEventListener('keydown', onKey);
    }

    function onKey(e) {
      if (e.key === 'Escape') close();
      if (e.key === 'ArrowRight' && group.length > 1) show(idx + 1);
      if (e.key === 'ArrowLeft' && group.length > 1) show(idx - 1);
    }

    overlay.addEventListener('click', (e) => {
      if (e.target === overlay || e.target === fullImg) close();
    });
    closeBtn.addEventListener('click', (e) => { e.stopPropagation(); close(); });
    if (prevBtn) prevBtn.addEventListener('click', (e) => { e.stopPropagation(); show(idx - 1); });
    if (nextBtn) nextBtn.addEventListener('click', (e) => { e.stopPropagation(); show(idx + 1); });
    document.addEventListener('keydown', onKey);

    // Touch swipe
    let touchStartX = 0;
    overlay.addEventListener('touchstart', (e) => { touchStartX = e.changedTouches[0].clientX; }, { passive: true });
    overlay.addEventListener('touchend', (e) => {
      const dx = e.changedTouches[0].clientX - touchStartX;
      if (Math.abs(dx) > 50 && group.length > 1) show(dx < 0 ? idx + 1 : idx - 1);
    });

    show(idx);
    document.body.appendChild(overlay);
    requestAnimationFrame(() => overlay.classList.add('active'));
  }

  // Bind clicks on all gallery images
  galleries.forEach((group, gi) => {
    group.forEach((img, ii) => {
      img.style.cursor = 'zoom-in';
      img.addEventListener('click', (e) => {
        e.stopPropagation();
        openLightbox(gi, ii);
      });
    });
  });

});

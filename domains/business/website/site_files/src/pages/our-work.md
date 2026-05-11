---
title: Our Work | Heartwood Craft Portfolio
meta_description: >-
  Portfolio of bathroom remodels, decks, timber framing, and custom builds by
  Heartwood Craft in Bozeman, MT. Real project photos from Big Sky to the
  Gallatin Valley.
h1: Our Work
hero_image: /img/portfolio/timber_framing/timber-frame-raising-crew-lift.webp
hero_subtitle: >-
  From heavy timber frames in Big Sky to bathroom remodels in Bozeman — every
  project reflects the same standard.
hero_eyebrow: Portfolio
content_wide: true
permalink: /our-work/
layout: layouts/page-simple.njk
show_services: false
show_testimonials: false
show_cta: false
show_form: false
---
<!-- Category Navigation -->
<nav class="portfolio-nav" aria-label="Portfolio categories">
  <ul class="portfolio-nav__list">
    <li><a href="#bathrooms" class="portfolio-nav__link">Bathrooms</a></li>
    <li><a href="#decks" class="portfolio-nav__link">Decks</a></li>
    <li><a href="#timber" class="portfolio-nav__link">Timber Framing</a></li>
    <li><a href="#interiors" class="portfolio-nav__link">Interiors</a></li>
    <li><a href="#porches" class="portfolio-nav__link">Porches</a></li>
    <li><a href="#custom" class="portfolio-nav__link">Custom Builds</a></li>
  </ul>
</nav>

<!-- Bathrooms & Basements -->
<section id="bathrooms" class="portfolio-section">
  <div class="portfolio-section__header">
    <span class="portfolio-section__eyebrow">Bathrooms & Basements</span>
    <h2 class="portfolio-section__title">Full Remodels, Start to Finish</h2>
    <p class="portfolio-section__desc">
      Complete bathroom and basement remodels are the core of what we do at Heartwood Craft. Each project moves through a structured process — existing condition assessment, 3D design, and careful execution. <a href="/calculator/">Get a ballpark estimate</a> or <a href="/bathroom/remodeling/">learn about our bathroom process</a>.
    </p>
  </div>
  {% for item in curated.portfolio_bathrooms %}{% if item.hero %}
  <img src="{{ item.src }}" alt="{{ item.alt }}" class="portfolio-hero-img" loading="lazy">
  {% endif %}{% endfor %}
  <div class="portfolio-gallery">
    {% for item in curated.portfolio_bathrooms %}{% if not item.hero %}
    <figure class="portfolio-gallery__item">
      <img src="{{ item.src }}" alt="{{ item.alt }}" loading="lazy">
      <div class="portfolio-gallery__overlay">
        <span class="portfolio-gallery__caption">{{ item.caption }}</span>
      </div>
    </figure>
    {% endif %}{% endfor %}
  </div>
</section>

<!-- Testimonial Break -->
<div class="portfolio-testimonial">
  <div class="portfolio-testimonial__inner">
    <div class="portfolio-testimonial__stars">★★★★★</div>
    <p class="portfolio-testimonial__text">"Eric's attention to detail and communication throughout the project was outstanding. The finished bathroom exceeded our expectations."</p>
    <p class="portfolio-testimonial__author"><strong>Bozeman Homeowner</strong> · Bathroom Remodel</p>
  </div>
</div>

<!-- Custom Decks -->
<section id="decks" class="portfolio-section">
  <div class="portfolio-section__header">
    <span class="portfolio-section__eyebrow">Custom Decks</span>
    <h2 class="portfolio-section__title">Built for Montana's Climate</h2>
    <p class="portfolio-section__desc">
      Cedar and composite decks engineered for freeze-thaw cycles. Footings below the 36-inch frost line, galvanized hardware, and flashing details that protect your home for decades. <a href="/deck-calculator/">Estimate your deck project</a>.
    </p>
  </div>
  {% for item in curated.portfolio_decks %}{% if item.hero %}
  <img src="{{ item.src }}" alt="{{ item.alt }}" class="portfolio-hero-img" loading="lazy">
  {% endif %}{% endfor %}
  <div class="portfolio-gallery">
    {% for item in curated.portfolio_decks %}{% if not item.hero %}
    <figure class="portfolio-gallery__item">
      <img src="{{ item.src }}" alt="{{ item.alt }}" loading="lazy">
      <div class="portfolio-gallery__overlay">
        <span class="portfolio-gallery__caption">{{ item.caption }}</span>
      </div>
    </figure>
    {% endif %}{% endfor %}
  </div>
</section>

<!-- Timber Framing -->
<section id="timber" class="portfolio-section">
  <div class="portfolio-section__header">
    <span class="portfolio-section__eyebrow">Timber Framing</span>
    <h2 class="portfolio-section__title">Heavy Timber & Structural Work</h2>
    <p class="portfolio-section__desc">
      Post-and-beam framing and structural carpentry — years of building in Alaska and Big Sky, where every joint is visible and precision isn't optional. These connections carry serious loads through Montana's snow seasons.
    </p>
  </div>
  {% for item in curated.portfolio_timber %}{% if item.hero %}
  <img src="{{ item.src }}" alt="{{ item.alt }}" class="portfolio-hero-img" loading="lazy">
  {% endif %}{% endfor %}
  <div class="portfolio-gallery">
    {% for item in curated.portfolio_timber %}{% if not item.hero %}
    <figure class="portfolio-gallery__item">
      <img src="{{ item.src }}" alt="{{ item.alt }}" loading="lazy">
      <div class="portfolio-gallery__overlay">
        <span class="portfolio-gallery__caption">{{ item.caption }}</span>
      </div>
    </figure>
    {% endif %}{% endfor %}
  </div>
</section>

<!-- Testimonial Break -->
<div class="portfolio-testimonial">
  <div class="portfolio-testimonial__inner">
    <div class="portfolio-testimonial__stars">★★★★★</div>
    <p class="portfolio-testimonial__text">"Professional, organized, and the craftsmanship speaks for itself. We couldn't be happier with the finished project."</p>
    <p class="portfolio-testimonial__author"><strong>Gallatin Valley Client</strong> · Residential Remodel</p>
  </div>
</div>

<!-- Interior Work -->
<section id="interiors" class="portfolio-section">
  <div class="portfolio-section__header">
    <span class="portfolio-section__eyebrow">Interior Work</span>
    <h2 class="portfolio-section__title">Trim, Cabinetry & Finish Carpentry</h2>
    <p class="portfolio-section__desc">
      The details you interact with every day — drawers that close smoothly, crown molding in tight miters, built-ins that fit the space exactly. Interior work requires patience and an understanding of how wood moves in Montana's seasonal extremes.
    </p>
  </div>
  {% for item in curated.portfolio_interiors %}{% if item.hero %}
  <img src="{{ item.src }}" alt="{{ item.alt }}" class="portfolio-hero-img" loading="lazy">
  {% endif %}{% endfor %}
  <div class="portfolio-gallery">
    {% for item in curated.portfolio_interiors %}{% if not item.hero %}
    <figure class="portfolio-gallery__item">
      <img src="{{ item.src }}" alt="{{ item.alt }}" loading="lazy">
      <div class="portfolio-gallery__overlay">
        <span class="portfolio-gallery__caption">{{ item.caption }}</span>
      </div>
    </figure>
    {% endif %}{% endfor %}
  </div>
</section>

<!-- Porches & Exterior -->
<section id="porches" class="portfolio-section">
  <div class="portfolio-section__header">
    <span class="portfolio-section__eyebrow">Porches & Exterior</span>
    <h2 class="portfolio-section__title">Curb Appeal That Holds Up</h2>
    <p class="portfolio-section__desc">
      Front porches, covered entries, siding, and exterior trim. Porch projects often uncover rotted substructure or inadequate flashing — we address structural issues alongside the visible work so it holds up through Montana winters.
    </p>
  </div>
  {% for item in curated.portfolio_porches %}{% if item.hero %}
  <img src="{{ item.src }}" alt="{{ item.alt }}" class="portfolio-hero-img" loading="lazy">
  {% endif %}{% endfor %}
  <div class="portfolio-gallery">
    {% for item in curated.portfolio_porches %}{% if not item.hero %}
    <figure class="portfolio-gallery__item">
      <img src="{{ item.src }}" alt="{{ item.alt }}" loading="lazy">
      <div class="portfolio-gallery__overlay">
        <span class="portfolio-gallery__caption">{{ item.caption }}</span>
      </div>
    </figure>
    {% endif %}{% endfor %}
  </div>
</section>

<!-- Custom Builds -->
<section id="custom" class="portfolio-section">
  <div class="portfolio-section__header">
    <span class="portfolio-section__eyebrow">Custom Builds</span>
    <h2 class="portfolio-section__title">One-of-a-Kind Projects</h2>
    <p class="portfolio-section__desc">
      Work that doesn't come from a catalog. A homeowner has a specific vision — a piece of furniture, a feature wall, a structure that doesn't fit a standard category — and we figure out how to build it so it looks right and holds up.
    </p>
  </div>
  {% for item in curated.portfolio_custom %}{% if item.hero %}
  <img src="{{ item.src }}" alt="{{ item.alt }}" class="portfolio-hero-img" loading="lazy">
  {% endif %}{% endfor %}
  <div class="portfolio-gallery">
    {% for item in curated.portfolio_custom %}{% if not item.hero %}
    <figure class="portfolio-gallery__item">
      <img src="{{ item.src }}" alt="{{ item.alt }}" loading="lazy">
      <div class="portfolio-gallery__overlay">
        <span class="portfolio-gallery__caption">{{ item.caption }}</span>
      </div>
    </figure>
    {% endif %}{% endfor %}
  </div>
</section>

<!-- Closing CTA -->
<div class="portfolio-cta">
  <h2 class="portfolio-cta__heading">Tell Us About Your Project</h2>
  <p class="portfolio-cta__sub">
    Whether it's a bathroom remodel, deck build, or something completely custom — we'd like to hear what you have in mind.
  </p>
  <a href="/contact/" class="btn btn-primary">Request a Consultation</a>
  <a href="/how-it-works/" class="btn btn-secondary">See Our Process</a>
</div>

<script>
(function() {
  const nav = document.querySelector('.portfolio-nav');
  if (!nav) return;
  const links = nav.querySelectorAll('.portfolio-nav__link');
  const sections = document.querySelectorAll('.portfolio-section');
  
  function updateActive() {
    let current = '';
    sections.forEach(function(s) {
      if (window.scrollY >= s.offsetTop - 180) {
        current = s.id;
      }
    });
    links.forEach(function(link) {
      link.classList.toggle('active', link.getAttribute('href') === '#' + current);
    });
  }
  
  window.addEventListener('scroll', updateActive, { passive: true });
  updateActive();
  
  // Smooth scroll for nav links
  links.forEach(function(link) {
    link.addEventListener('click', function(e) {
      e.preventDefault();
      var target = document.querySelector(this.getAttribute('href'));
      if (target) {
        target.scrollIntoView({ behavior: 'smooth' });
      }
    });
  });
})();
</script>

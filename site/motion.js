// Rolige animasjoner med GSAP. Siden fungerer helt uten dette skriptet:
// innholdet skjules bare når html har klassen "motion", som settes i <head>
// og fjernes igjen hvis GSAP ikke lastes.
(function () {
  var root = document.documentElement;
  if (!root.classList.contains('motion')) return;
  if (!window.gsap || !window.ScrollTrigger) {
    root.classList.remove('motion');
    return;
  }

  gsap.registerPlugin(ScrollTrigger);
  gsap.defaults({ ease: 'power3.out', duration: 0.8 });

  // Hero: teksten bygger seg opp når siden åpnes.
  gsap.fromTo('.hero-text > *, .hero-art',
    { autoAlpha: 0, y: 24 },
    { autoAlpha: 1, y: 0, stagger: 0.12, delay: 0.1 });

  // Hero: innholdet glir litt saktere bort enn fjellkammen når du scroller.
  gsap.to('.hero .wrap', {
    y: 60,
    ease: 'none',
    scrollTrigger: { trigger: '.hero', start: 'top top', end: 'bottom top', scrub: true }
  });

  // Elementer som kommer inn fra under når de blir synlige.
  function reveal(targets, trigger, stagger) {
    if (typeof trigger === 'string' && !document.querySelector(trigger)) return;
    gsap.fromTo(targets,
      { autoAlpha: 0, y: 32 },
      {
        autoAlpha: 1, y: 0, stagger: stagger || 0,
        scrollTrigger: { trigger: trigger, start: 'top 85%', once: true }
      });
  }

  document.querySelectorAll('.section h2').forEach(function (h) {
    var lead = h.nextElementSibling && h.nextElementSibling.matches('.section-lead, .lead')
      ? h.nextElementSibling : null;
    reveal(lead ? [h, lead] : h, h, 0.1);
  });

  reveal('.cards .card', '.cards', 0.1);
  reveal('.price-note', '.price-note');
  reveal('.site-card', '.site-grid', 0.12);
  reveal('.steps .step', '.steps', 0.15);
  reveal('.about > div > p', '.about', 0.12);
  reveal('#kontakt .form, #contact .form', '.contact .form');

  document.querySelectorAll('.app').forEach(function (app) {
    reveal(app.querySelector('.app-info'), app);
    reveal(app.querySelectorAll('.shots img, .web-shots img'), app, 0.12);
  });
})();

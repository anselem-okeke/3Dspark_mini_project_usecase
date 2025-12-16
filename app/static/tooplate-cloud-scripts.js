/*

Tooplate 2142 Cloud Sync

https://www.tooplate.com/view/2142-cloud-sync

*/


// JavaScript Document

        // Interactive Pricing Calculator
        const teamSlider = document.getElementById('teamSlider');
        const storageSlider = document.getElementById('storageSlider');
        const teamSizeDisplay = document.getElementById('teamSize');
        const storageSizeDisplay = document.getElementById('storageSize');
        
        const starterPriceEl = document.getElementById('starterPrice');
        const proPriceEl = document.getElementById('proPrice');
        const enterprisePriceEl = document.getElementById('enterprisePrice');

        function calculatePricing() {
            const teamSize = parseInt(teamSlider.value);
            const storageSize = parseInt(storageSlider.value);
            
            // Update displays
            teamSizeDisplay.textContent = teamSize;
            storageSizeDisplay.textContent = storageSize + ' GB';
            
            // Calculate prices based on team size and storage
            const baseStarterPrice = 29;
            const baseProPrice = 149;
            const baseEnterprisePrice = 299;
            
            // Price per additional team member
            const teamMultiplier = Math.max(1, teamSize / 10);
            const storageMultiplier = Math.max(1, storageSize / 500);
            
            const starterPrice = Math.round(baseStarterPrice * Math.min(teamMultiplier, 2) * Math.min(storageMultiplier, 1.5));
            const proPrice = Math.round(baseProPrice * Math.min(teamMultiplier, 3) * Math.min(storageMultiplier, 2));
            const enterprisePrice = Math.round(baseEnterprisePrice * teamMultiplier * storageMultiplier);
            
            // Animate price changes
            animatePrice(starterPriceEl, starterPrice);
            animatePrice(proPriceEl, proPrice);
            animatePrice(enterprisePriceEl, enterprisePrice);
        }

        function animatePrice(element, newPrice) {
            const currentPrice = parseInt(element.textContent);
            const difference = newPrice - currentPrice;
            const steps = 20;
            const stepValue = difference / steps;
            let step = 0;
            
            const interval = setInterval(() => {
                step++;
                element.textContent = Math.round(currentPrice + (stepValue * step));
                
                if (step >= steps) {
                    element.textContent = newPrice;
                    clearInterval(interval);
                }
            }, 20);
        }

        teamSlider.addEventListener('input', calculatePricing);
        storageSlider.addEventListener('input', calculatePricing);

        // Scroll animations
        window.addEventListener('scroll', () => {
            const nav = document.querySelector('nav');
            if (window.scrollY > 100) {
                nav.style.padding = '0.5rem 2rem';
                nav.style.background = 'rgba(15, 23, 42, 0.95)';
            } else {
                nav.style.padding = '1rem 2rem';
                nav.style.background = 'rgba(15, 23, 42, 0.8)';
            }
        });

        // Smooth scrolling for navigation links
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', function (e) {
                e.preventDefault();
                const target = document.querySelector(this.getAttribute('href'));
                if (target) {
                    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
                    // Close mobile menu if open
                    mobileNav.classList.remove('active');
                    mobileMenuToggle.classList.remove('active');
                }
            });
        });

        // Mobile menu functionality
        const mobileMenuToggle = document.getElementById('mobileMenuToggle');
        const mobileNav = document.getElementById('mobileNav');

        mobileMenuToggle.addEventListener('click', function() {
            this.classList.toggle('active');
            mobileNav.classList.toggle('active');
        });

        // Close mobile menu when clicking outside
        document.addEventListener('click', function(e) {
            if (!mobileMenuToggle.contains(e.target) && !mobileNav.contains(e.target)) {
                mobileNav.classList.remove('active');
                mobileMenuToggle.classList.remove('active');
            }
        });

        // Contact form handling
        const contactForm = document.getElementById('contactForm');
        contactForm.addEventListener('submit', function(e) {
            e.preventDefault();
            
            // Get form values
            const formData = {
                name: document.getElementById('name').value,
                email: document.getElementById('email').value,
                company: document.getElementById('company').value,
                subject: document.getElementById('subject').value,
                message: document.getElementById('message').value
            };
            
            // Simulate form submission
            const submitButton = this.querySelector('.submit-button');
            const originalText = submitButton.textContent;
            submitButton.textContent = 'Sending...';
            submitButton.disabled = true;
            
            // Simulate API call
            setTimeout(() => {
                submitButton.textContent = 'Message Sent! ✓';
                submitButton.style.background = 'var(--secondary)';
                
                // Reset form
                this.reset();
                
                // Reset button after 3 seconds
                setTimeout(() => {
                    submitButton.textContent = originalText;
                    submitButton.style.background = '';
                    submitButton.disabled = false;
                }, 3000);
            }, 1500);
        });

        // Animate stats on scroll
        const observerOptions = {
            threshold: 0.5,
            rootMargin: '0px'
        };

        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.style.animation = 'fadeInUp 0.8s ease-out forwards';
                }
            });
        }, observerOptions);

        // Observe stat cards
        document.querySelectorAll('.stat-card').forEach(card => {
            observer.observe(card);
        });

        // Hero background image rotation
        const heroBackgrounds = document.querySelectorAll('.hero-bg');
        let currentBgIndex = 0;

        function rotateBackgrounds() {
            // Remove active class from all backgrounds
            heroBackgrounds.forEach(bg => bg.classList.remove('active'));
            
            // Add active class to current background
            heroBackgrounds[currentBgIndex].classList.add('active');
            
            // Move to next background
            currentBgIndex = (currentBgIndex + 1) % heroBackgrounds.length;
        }

        // Start with first image
        heroBackgrounds[0].classList.add('active');

        // Rotate every 5 seconds
        setInterval(rotateBackgrounds, 5000);
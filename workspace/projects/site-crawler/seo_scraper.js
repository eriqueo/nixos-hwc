// SEO Competitor Analysis Bookmarklet - Readable Version
// This is the formatted version for editing - DO NOT use this as bookmarklet
// Use the minified version from bookmarklet_ready_to_paste.txt

javascript:(function(){
    // Remove existing analysis if present
    if (document.getElementById('seo-analysis')) {
        document.getElementById('seo-analysis').remove();
    }

    // Create main container
    const analysisDiv = document.createElement('div');
    analysisDiv.id = 'seo-analysis';
    analysisDiv.style.cssText = 'position:fixed;top:10px;right:10px;width:420px;max-height:85vh;background:white;border:2px solid #333;border-radius:8px;padding:20px;font-family:Arial,sans-serif;font-size:12px;z-index:10000;overflow-y:auto;box-shadow:0 4px 20px rgba(0,0,0,0.3);';
    
    // Show loading state
    analysisDiv.innerHTML = '<div style="text-align:center;padding:20px;"><h3 style="margin:0 0 15px 0;">Analyzing SEO...</h3><div style="width:100%;background:#f0f0f0;border-radius:10px;overflow:hidden;"><div id="progress-bar" style="width:0%;height:20px;background:#4CAF50;transition:width 0.3s;"></div></div><div id="progress-text" style="margin-top:10px;color:#666;">Starting analysis...</div></div>';
    document.body.appendChild(analysisDiv);

    // Progress tracking
    let progress = 0;
    const totalSteps = 10;
    
    function updateProgress(step, message) {
        progress = (step / totalSteps) * 100;
        const progressBar = document.getElementById('progress-bar');
        const progressText = document.getElementById('progress-text');
        if (progressBar) progressBar.style.width = progress + '%';
        if (progressText) progressText.textContent = message;
    }

    // Error handling wrapper
    function safeExecute(fn, fallback = 'Error occurred') {
        try {
            return fn();
        } catch (error) {
            console.warn('SEO Analysis Error:', error);
            return fallback;
        }
    }

    // Get meta tag content
    function getMetaContent(name) {
        return safeExecute(() => {
            const meta = document.querySelector('meta[name="' + name + '"], meta[property="' + name + '"]');
            return meta ? meta.getAttribute('content') : 'Not found';
        }, 'Not found');
    }

    // Get schema markup data
    function getSchemaData() {
        return safeExecute(() => {
            const scripts = document.querySelectorAll('script[type="application/ld+json"]');
            const schemas = [];
            scripts.forEach(script => {
                try {
                    const data = JSON.parse(script.textContent);
                    if (data['@type']) {
                        schemas.push(data['@type']);
                    } else if (data['@graph']) {
                        data['@graph'].forEach(item => {
                            if (item['@type']) schemas.push(item['@type']);
                        });
                    }
                } catch(e) {
                    console.warn('Schema parsing error:', e);
                }
            });
            return schemas.length > 0 ? schemas.join(', ') : 'None found';
        }, 'Analysis failed');
    }

    // Get heading structure
    function getHeadingStructure() {
        return safeExecute(() => {
            const headings = {};
            ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].forEach(tag => {
                const elements = document.querySelectorAll(tag);
                headings[tag.toUpperCase()] = elements.length;
            });
            return headings;
        }, {H1: 0, H2: 0, H3: 0, H4: 0, H5: 0, H6: 0});
    }

    // Get link analysis
    function getLinks() {
        return safeExecute(() => {
            const allLinks = document.querySelectorAll('a[href]');
            let internal = 0, external = 0;
            
            allLinks.forEach(link => {
                const href = link.getAttribute('href');
                if (href.startsWith('/') || href.startsWith(window.location.origin)) {
                    internal++;
                } else if (href.startsWith('http')) {
                    external++;
                }
            });
            
            return { internal, external, total: allLinks.length };
        }, { internal: 0, external: 0, total: 0 });
    }

    // Get image analysis
    function getImageAnalysis() {
        return safeExecute(() => {
            const images = document.querySelectorAll('img');
            let withAlt = 0, withTitle = 0, lazy = 0;
            
            images.forEach(img => {
                if (img.alt && img.alt.trim() !== '') withAlt++;
                if (img.title && img.title.trim() !== '') withTitle++;
                if (img.loading === 'lazy' || img.getAttribute('data-src')) lazy++;
            });
            
            return {
                total: images.length,
                withAlt,
                withTitle,
                lazy,
                missingAlt: images.length - withAlt
            };
        }, { total: 0, withAlt: 0, withTitle: 0, lazy: 0, missingAlt: 0 });
    }

    // Get technical SEO data
    function getTechnicalSEO() {
        return safeExecute(() => {
            const canonical = document.querySelector('link[rel="canonical"]');
            const robots = getMetaContent('robots');
            const viewport = getMetaContent('viewport');
            const charset = document.querySelector('meta[charset]');
            
            return {
                canonical: canonical ? canonical.href : 'Not set',
                robots: robots,
                viewport: viewport,
                charset: charset ? charset.getAttribute('charset') : 'Not set',
                https: window.location.protocol === 'https:',
                pageSpeed: performance.timing ? 
                    Math.round((performance.timing.loadEventEnd - performance.timing.navigationStart) / 1000) + 's' : 
                    'Unknown'
            };
        }, {});
    }

    // Get page information
    function getPageInfo() {
        return safeExecute(() => {
            const wordCount = document.body.innerText.split(/\s+/).length;
            const lastModified = document.lastModified;
            
            return {
                wordCount,
                lastModified,
                language: document.documentElement.lang || 'Not set',
                doctype: document.doctype ? document.doctype.name : 'Unknown'
            };
        }, {});
    }

    // File download function
    function downloadFile(content, filename, type) {
        const blob = new Blob([content], { type: type });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }

    // Convert data to CSV format
    function convertToCSV(data) {
        const rows = [
            ['Property', 'Value'],
            ['URL', data.url],
            ['Title', data.title],
            ['Title Length', data.titleLength],
            ['Description', data.description],
            ['Description Length', data.descriptionLength],
            ['H1 Count', data.headings.H1],
            ['H2 Count', data.headings.H2],
            ['Internal Links', data.links.internal],
            ['External Links', data.links.external],
            ['Total Images', data.images.total],
            ['Images with Alt', data.images.withAlt],
            ['Schema Types', data.schema],
            ['HTTPS', data.technical.https],
            ['Load Time', data.technical.pageSpeed],
            ['Word Count', data.pageInfo.wordCount]
        ];
        
        return rows.map(row => row.map(cell => '"' + cell + '"').join(',')).join('\n');
    }

    // Main analysis function
    async function runAnalysis() {
        try {
            updateProgress(1, 'Analyzing basic SEO elements...');
            const title = document.title || 'No title';
            const description = getMetaContent('description');
            
            updateProgress(2, 'Checking social media tags...');
            const socialData = {
                ogTitle: getMetaContent('og:title'),
                ogDescription: getMetaContent('og:description'),
                ogImage: getMetaContent('og:image'),
                twitterCard: getMetaContent('twitter:card')
            };

            updateProgress(3, 'Analyzing heading structure...');
            const headings = getHeadingStructure();

            updateProgress(4, 'Counting links...');
            const links = getLinks();

            updateProgress(5, 'Analyzing images...');
            const images = getImageAnalysis();

            updateProgress(6, 'Checking schema markup...');
            const schema = getSchemaData();

            updateProgress(7, 'Analyzing technical SEO...');
            const technical = getTechnicalSEO();

            updateProgress(8, 'Getting page information...');
            const pageInfo = getPageInfo();

            updateProgress(9, 'Compiling results...');
            
            const seoData = {
                timestamp: new Date().toISOString(),
                url: window.location.href,
                domain: window.location.hostname,
                title: title,
                titleLength: title.length,
                description: description,
                descriptionLength: description.length,
                keywords: getMetaContent('keywords'),
                ...socialData,
                schema: schema,
                headings: headings,
                links: links,
                images: images,
                technical: technical,
                pageInfo: pageInfo
            };

            updateProgress(10, 'Analysis complete!');
            
            setTimeout(() => displayResults(seoData), 500);
            
        } catch (error) {
            displayError(error);
        }
    }

    // Display error message
    function displayError(error) {
        analysisDiv.innerHTML = '<div style="text-align:center;padding:20px;"><h3 style="color:red;margin:0 0 15px 0;">Analysis Failed</h3><p style="color:#666;margin-bottom:15px;">An error occurred during analysis:</p><p style="background:#f5f5f5;padding:10px;border-radius:4px;font-family:monospace;font-size:11px;">' + error.message + '</p><button onclick="document.getElementById(\'seo-analysis\').remove()" style="background:#ff4444;color:white;border:none;padding:8px 16px;border-radius:4px;cursor:pointer;margin-top:15px;">Close</button></div>';
    }

    // Display results
    function displayResults(seoData) {
        // Store data globally for clipboard access
        window.seoDataGlobal = seoData;
        
        const domain = seoData.domain.replace(/[^a-zA-Z0-9]/g, '_');
        const timestamp = new Date().toISOString().slice(0, 10);
        const filename = 'seo_analysis_' + domain + '_' + timestamp;

        const reportHTML = '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:15px;"><h3 style="margin:0;color:#333;">SEO Analysis Complete ✓</h3><button onclick="document.getElementById(\'seo-analysis\').remove()" style="background:#ff4444;color:white;border:none;padding:5px 10px;border-radius:3px;cursor:pointer;">×</button></div><div style="margin-bottom:10px;padding:8px;background:#e8f5e8;border-radius:4px;"><strong>✓ Analysis successful!</strong><br><small>Analyzed: ' + seoData.domain + ' at ' + new Date(seoData.timestamp).toLocaleString() + '</small></div><div style="margin-bottom:15px;"><h4 style="margin:10px 0 5px 0;color:#666;">Basic SEO</h4><div><strong>Title:</strong> ' + seoData.title.substring(0, 50) + '... <span style="color:' + (seoData.titleLength > 60 ? 'red' : seoData.titleLength < 30 ? 'orange' : 'green') + ';">(' + seoData.titleLength + ' chars)</span></div><div><strong>Description:</strong> ' + seoData.description.substring(0, 50) + '... <span style="color:' + (seoData.descriptionLength > 160 ? 'red' : seoData.descriptionLength < 120 ? 'orange' : 'green') + ';">(' + seoData.descriptionLength + ' chars)</span></div><div><strong>Word Count:</strong> ' + seoData.pageInfo.wordCount + '</div></div><div style="margin-bottom:15px;"><h4 style="margin:10px 0 5px 0;color:#666;">Content Structure</h4><div><strong>H1:</strong> ' + seoData.headings.H1 + ' <span style="color:' + (seoData.headings.H1 === 1 ? 'green' : 'red') + ';">' + (seoData.headings.H1 === 1 ? '✓' : seoData.headings.H1 === 0 ? '(Missing)' : '(Multiple)') + '</span></div><div><strong>H2:</strong> ' + seoData.headings.H2 + ' | <strong>H3:</strong> ' + seoData.headings.H3 + '</div><div><strong>Internal Links:</strong> ' + seoData.links.internal + ' | <strong>External:</strong> ' + seoData.links.external + '</div></div><div style="margin-bottom:15px;"><h4 style="margin:10px 0 5px 0;color:#666;">Images & Media</h4><div><strong>Total Images:</strong> ' + seoData.images.total + '</div><div><strong>With Alt Text:</strong> ' + seoData.images.withAlt + ' <span style="color:green;">✓</span></div><div><strong>Missing Alt:</strong> ' + seoData.images.missingAlt + ' <span style="color:' + (seoData.images.missingAlt > 0 ? 'red' : 'green') + ';">' + (seoData.images.missingAlt > 0 ? '⚠' : '✓') + '</span></div><div><strong>Lazy Loading:</strong> ' + seoData.images.lazy + ' images</div></div><div style="margin-bottom:15px;"><h4 style="margin:10px 0 5px 0;color:#666;">Technical SEO</h4><div><strong>HTTPS:</strong> ' + (seoData.technical.https ? '✓' : '✗') + '</div><div><strong>Canonical:</strong> ' + (seoData.technical.canonical !== 'Not set' ? '✓' : '✗') + '</div><div><strong>Viewport:</strong> ' + (seoData.technical.viewport !== 'Not found' ? '✓' : '✗') + '</div><div><strong>Load Time:</strong> ' + seoData.technical.pageSpeed + '</div><div><strong>Schema:</strong> ' + seoData.schema + '</div></div><div style="margin-top:20px;padding-top:15px;border-top:1px solid #ccc;"><h4 style="margin:0 0 10px 0;color:#666;">Export Options</h4><div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px;"><button onclick="downloadFile(JSON.stringify(window.seoDataGlobal,null,2),\'' + filename + '.json\',\'application/json\')" style="background:#2196F3;color:white;border:none;padding:8px 12px;border-radius:4px;cursor:pointer;font-size:11px;">📄 Download JSON</button><button onclick="downloadFile(convertToCSV(window.seoDataGlobal),\'' + filename + '.csv\',\'text/csv\')" style="background:#4CAF50;color:white;border:none;padding:8px 12px;border-radius:4px;cursor:pointer;font-size:11px;">📊 Download CSV</button></div><button onclick="navigator.clipboard.writeText(JSON.stringify(window.seoDataGlobal,null,2)).then(()=>alert(\'✓ Data copied to clipboard!\')).catch(()=>alert(\'Copy failed - try selecting text manually\'))" style="background:#FF9800;color:white;border:none;padding:8px 12px;border-radius:4px;cursor:pointer;width:100%;font-size:11px;">📋 Copy to Clipboard</button></div>';

        analysisDiv.innerHTML = reportHTML;

        // Add functions to global scope for button access
        window.downloadFile = downloadFile;
        window.convertToCSV = convertToCSV;
    }

    // Make draggable
    let isDragging = false;
    let currentX, currentY, initialX, initialY;

    analysisDiv.addEventListener('mousedown', function(e) {
        if (e.target.tagName !== 'BUTTON' && e.target.tagName !== 'INPUT') {
            isDragging = true;
            initialX = e.clientX - analysisDiv.offsetLeft;
            initialY = e.clientY - analysisDiv.offsetTop;
            analysisDiv.style.cursor = 'grabbing';
        }
    });

    document.addEventListener('mousemove', function(e) {
        if (isDragging) {
            currentX = e.clientX - initialX;
            currentY = e.clientY - initialY;
            analysisDiv.style.left = currentX + 'px';
            analysisDiv.style.top = currentY + 'px';
            analysisDiv.style.right = 'auto';
        }
    });

    document.addEventListener('mouseup', function() {
        if (isDragging) {
            isDragging = false;
            analysisDiv.style.cursor = 'default';
        }
    });

    // Start analysis
    runAnalysis();

})();

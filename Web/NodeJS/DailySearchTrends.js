const express = require('express');
const axios = require('axios');
const xml2js = require('xml2js');
const ejs = require('ejs');
const app = express();
const port = 3002;

// Full list of countries that support Google "Daily Search Trends" RSS
//npm install express axios ejs xml2js
//node server.js
const COUNTRIES = {
    'AR': 'Argentina',
    'AU': 'Australia',
    'AT': 'Austria',
    'BE': 'Belgium',
    'BR': 'Brazil',
    'CA': 'Canada',
    'CL': 'Chile',
    'CO': 'Colombia',
    'CZ': 'Czechia',
    'DK': 'Denmark',
    'EG': 'Egypt',
    'FI': 'Finland',
    'FR': 'France',
    'DE': 'Germany',
    'GR': 'Greece',
    'HK': 'Hong Kong',
    'HU': 'Hungary',
    'IN': 'India',
    'ID': 'Indonesia',
    'IE': 'Ireland',
    'IL': 'Israel',
    'IT': 'Italy',
    'JP': 'Japan',
    'KE': 'Kenya',
    'MY': 'Malaysia',
    'MX': 'Mexico',
    'NL': 'Netherlands',
    'NZ': 'New Zealand',
    'NG': 'Nigeria',
    'NO': 'Norway',
    'PE': 'Peru',
    'PH': 'Philippines',
    'PL': 'Poland',
    'PT': 'Portugal',
    'RO': 'Romania',
    'RU': 'Russia',
    'SA': 'Saudi Arabia',
    'SG': 'Singapore',
    'ZA': 'South Africa',
    'KR': 'South Korea',
    'ES': 'Spain',
    'SE': 'Sweden',
    'CH': 'Switzerland',
    'TW': 'Taiwan',
    'TH': 'Thailand',
    'TR': 'Turkey',
    'UA': 'Ukraine',
    'GB': 'United Kingdom',
    'US': 'United States',
    'VN': 'Vietnam'
};

// ============================================================================
// INLINED VIEW (formerly views/index.ejs)
// The entire EJS template is embedded here so the app runs as a single file.
// ============================================================================
const INDEX_TEMPLATE = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Global Trends: <%= currentGeo %></title>
    
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/jsvectormap/dist/css/jsvectormap.min.css" />
    
    <style>
        :root {
            --bg-color: #f0f2f5;
            --card-bg: #ffffff;
            --text-main: #202124;
            --text-muted: #5f6368;
            --accent: #4285f4;
            --border-radius: 16px;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-main);
            margin: 0;
            padding: 20px;
        }

        /* --- Header & Controls --- */
        .controls-area {
            max-width: 1600px;
            margin: 0 auto 20px auto;
            background: var(--card-bg);
            padding: 15px 25px;
            border-radius: var(--border-radius);
            box-shadow: 0 2px 8px rgba(0,0,0,0.06);
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 15px;
        }

        .brand h1 { margin: 0; font-size: 1.5rem; color: var(--text-main); }
        .brand span { color: var(--accent); font-weight: 800; }

        .toolbar {
            display: flex;
            align-items: center;
            gap: 12px;
            flex-wrap: wrap;
        }

        select, button, input[type="number"] {
            padding: 10px 14px;
            font-size: 0.9rem;
            border-radius: 8px;
            border: 1px solid #ddd;
            background: #fff;
            transition: all 0.2s;
        }
        
        button { cursor: pointer; }
        button:hover, select:hover { background-color: #f8f9fa; border-color: #bbb; }
        
        button.active {
            background-color: var(--accent);
            color: white;
            border-color: var(--accent);
        }

        input[type="number"] {
            width: 60px;
            padding-right: 5px;
        }

        /* --- Auto-Rotate Toggle --- */
        .toggle-group {
            display: flex;
            align-items: center;
            gap: 10px;
            background: #f8f9fa;
            padding: 6px 12px;
            border-radius: 8px;
            border: 1px solid #eee;
        }

        .toggle-wrapper {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 0.9rem;
            font-weight: 600;
            color: var(--text-muted);
        }
        .switch { position: relative; display: inline-block; width: 40px; height: 22px; }
        .switch input { opacity: 0; width: 0; height: 0; }
        .slider {
            position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0;
            background-color: #ccc; transition: .4s; border-radius: 34px;
        }
        .slider:before {
            position: absolute; content: ""; height: 16px; width: 16px; left: 3px; bottom: 3px;
            background-color: white; transition: .4s; border-radius: 50%;
        }
        input:checked + .slider { background-color: var(--accent); }
        input:checked + .slider:before { transform: translateX(18px); }

        /* --- Map --- */
        #map-container {
            width: 100%;
            height: 250px;
            background: #e9e9e9;
            border-radius: var(--border-radius);
            margin: 0 auto 30px auto;
            max-width: 1600px;
            overflow: hidden;
            border: 1px solid #e0e0e0;
        }

        /* --- CENTERED GRID LAYOUT --- */
        .grid-container {
            width: 100%;
            display: flex;
            justify-content: center;
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
            gap: 24px;
            width: 100%;
            max-width: 1600px;
        }

        /* --- INFINITE SCROLL CAROUSEL --- */
        .carousel-wrapper {
            display: none;
            width: 100%;
            overflow: hidden;
            position: relative;
            padding: 20px 0;
            mask-image: linear-gradient(to right, transparent, black 5%, black 95%, transparent);
            -webkit-mask-image: linear-gradient(to right, transparent, black 5%, black 95%, transparent);
        }

        .carousel-track {
            display: flex;
            gap: 30px;
            width: max-content;
            animation: scroll-left 60s linear infinite; 
        }

        .carousel-track:hover { animation-play-state: paused; }

        @keyframes scroll-left {
            0% { transform: translateX(0); }
            100% { transform: translateX(-50%); } 
        }

        .carousel-card { width: 350px; flex-shrink: 0; }

        /* --- SHARED CARD STYLES --- */
        .card {
            background: var(--card-bg);
            border-radius: var(--border-radius);
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            overflow: hidden;
            display: flex;
            flex-direction: column;
            transition: transform 0.2s, box-shadow 0.2s;
            height: 100%;
            border: 1px solid #f0f0f0;
        }
        
        .card:hover { transform: translateY(-4px); box-shadow: 0 10px 20px rgba(0,0,0,0.12); }

        .card-header { position: relative; height: 180px; background-color: #eee; }
        .card-img { width: 100%; height: 100%; object-fit: cover; }
        
        .card-overlay {
            position: absolute; bottom: 0; left: 0; right: 0;
            background: linear-gradient(to top, rgba(0,0,0,0.9), transparent);
            padding: 15px; color: white;
        }
        
        .trend-title { 
            margin: 0; font-size: 1.25rem; font-weight: 600; 
            line-height: 1.3; text-shadow: 0 1px 2px rgba(0,0,0,0.5); 
        }
        
        .traffic-badge {
            position: absolute; top: 12px; right: 12px;
            background: rgba(66, 133, 244, 0.95); color: #fff;
            padding: 4px 10px; border-radius: 20px;
            font-size: 0.75rem; font-weight: 700;
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }

        .card-body { padding: 15px; flex-grow: 1; display: flex; flex-direction: column; gap: 12px; }
        
        .news-item { display: flex; gap: 12px; text-decoration: none; color: inherit; align-items: flex-start; }
        .news-thumb { width: 50px; height: 50px; border-radius: 8px; object-fit: cover; background: #eee; flex-shrink: 0; }
        .news-info { display: flex; flex-direction: column; }
        .news-title { 
            font-size: 0.9rem; font-weight: 500; color: #1a73e8; 
            line-height: 1.3; margin-bottom: 2px;
            display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
        }
        .news-source { font-size: 0.75rem; color: #80868b; }

        .meta {
            padding: 12px 15px; background: #fafafa;
            font-size: 0.75rem; color: #888; text-align: right;
            border-top: 1px solid #f0f0f0;
        }

        @media (max-width: 768px) {
            .controls-area { flex-direction: column; align-items: stretch; padding: 15px; }
            .toolbar { justify-content: space-between; }
            .toggle-group { width: 100%; justify-content: space-between; margin-bottom: 10px; }
            .grid { justify-content: center; }
            #map-container { height: 180px; }
        }
    </style>
</head>
<body>

    <div class="controls-area">
        <div class="brand">
            <h1>Global <span>Trends</span></h1>
        </div>

        <div class="toolbar">
            <select id="countrySelector" onchange="changeCountry(this.value)">
                <% Object.keys(countries).forEach(code => { %>
                    <option value="<%= code %>" <%= currentGeo === code ? 'selected' : '' %>>
                        <%= countries[code] %>
                    </option>
                <% }) %>
            </select>

            <div class="toggle-group">
                <div class="toggle-wrapper">
                    <label class="switch">
                        <input type="checkbox" id="autoRotateToggle" onchange="toggleAutoRotate()">
                        <span class="slider"></span>
                    </label>
                    <span>Rotate</span>
                </div>
                <div style="display:flex; align-items:center; gap:5px; font-size:0.9rem; color:var(--text-muted);">
                    <input type="number" id="rotateInterval" value="15" min="5" max="300" onchange="updateInterval()">
                    <span>sec</span>
                </div>
            </div>
            
            <div class="btn-group">
                <button id="btn-grid" class="active" onclick="setView('grid')">Grid</button>
                <button id="btn-carousel" onclick="setView('carousel')">Auto-Scroll</button>
            </div>
        </div>
    </div>

    <div id="map-container"></div>

    <% if (typeof error !== 'undefined') { %>
        <div style="text-align:center; padding:40px; color:#d93025;"><%= error %></div>
    <% } else { %>
        
        <div id="view-grid" class="grid-container">
            <div class="grid">
                <% trends.forEach(trend => { %> <%- includeCard(trend) %> <% }) %>
            </div>
        </div>

        <div id="view-carousel" class="carousel-wrapper">
            <div class="carousel-track">
                <% trends.forEach(trend => { %>
                    <div class="carousel-card"> <%- includeCard(trend) %> </div>
                <% }) %>
                <% trends.forEach(trend => { %>
                    <div class="carousel-card"> <%- includeCard(trend) %> </div>
                <% }) %>
            </div>
        </div>
    <% } %>

    <% function includeCard(trend) { %>
        <div class="card">
            <div class="card-header">
                <% if (trend.mainPicture) { %>
                    <img src="<%= trend.mainPicture %>" class="card-img" onerror="this.style.display='none'">
                <% } else { %>
                    <div style="width:100%; height:100%; background:#e0e0e0;"></div>
                <% } %>
                <div class="traffic-badge"><%= trend.traffic %></div>
                <div class="card-overlay"><h2 class="trend-title"><%= trend.title %></h2></div>
            </div>
            <div class="card-body">
                <% trend.news.slice(0, 3).forEach(news => { %>
                    <a href="<%= news.url %>" class="news-item" target="_blank">
                        <% if (news.picture) { %> <img src="<%= news.picture %>" class="news-thumb"> <% } %>
                        <div class="news-info">
                            <span class="news-title"><%= news.title %></span>
                            <span class="news-source"><%= news.source %></span>
                        </div>
                    </a>
                <% }) %>
            </div>
            <div class="meta"><%= new Date(trend.pubDate).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}) %></div>
        </div>
    <% return ''; } %>

    <script src="https://cdn.jsdelivr.net/npm/jsvectormap/dist/js/jsvectormap.min.js"><\/script>
    <script src="https://cdn.jsdelivr.net/npm/jsvectormap/dist/maps/world.js"><\/script>

    <script>
        // --- CONFIGURATION ---
        const countryCodes = <%- JSON.stringify(Object.keys(countries)) %>;
        let rotationTimer = null;
        const STALE_REFRESH_MS = 15 * 60 * 1000; // 15 Minutes

        // --- MAP SETUP ---
        const map = new jsVectorMap({
            selector: '#map-container',
            map: 'world',
            zoomButtons: false,
            zoomOnScroll: false,
            regionStyle: {
                initial: { fill: '#d1d5db' },
                selected: { fill: '#4285f4' }
            },
            selectedRegions: ["<%= currentGeo %>"],
            onRegionClick: (e, code) => changeCountry(code)
        });

        // --- INITIALIZATION ---
        function initSettings() {
            // Restore User Settings
            const savedView = localStorage.getItem('viewMode') || 'grid';
            setView(savedView);

            const savedInterval = localStorage.getItem('rotateInterval') || '15';
            document.getElementById('rotateInterval').value = savedInterval;

            const isEnabled = localStorage.getItem('autoRotate') === 'true';
            const toggle = document.getElementById('autoRotateToggle');
            if (toggle) {
                toggle.checked = isEnabled;
                if (isEnabled) startRotationTimer();
            }

            // Start "Stale Data" Refresh Timer
            // If the user sits on this page for 15 minutes, force a reload to get new news.
            setTimeout(() => {
                console.log("Data is stale (15m elapsed). Refreshing...");
                window.location.reload();
            }, STALE_REFRESH_MS);
        }

        // --- LOGIC ---
        function toggleAutoRotate() {
            const toggle = document.getElementById('autoRotateToggle');
            const isChecked = toggle.checked;
            localStorage.setItem('autoRotate', isChecked);
            
            if (isChecked) startRotationTimer();
            else stopRotationTimer();
        }

        function updateInterval() {
            const val = document.getElementById('rotateInterval').value;
            localStorage.setItem('rotateInterval', val);
            const toggle = document.getElementById('autoRotateToggle');
            if (toggle.checked) {
                stopRotationTimer();
                startRotationTimer();
            }
        }

        function startRotationTimer() {
            if (rotationTimer) clearInterval(rotationTimer);
            let seconds = parseInt(document.getElementById('rotateInterval').value) || 15;
            if (seconds < 5) seconds = 5;
            
            rotationTimer = setInterval(() => {
                const current = "<%= currentGeo %>";
                let next;
                do {
                    next = countryCodes[Math.floor(Math.random() * countryCodes.length)];
                } while (next === current); 
                window.location.href = '/?geo=' + next;
            }, seconds * 1000);
        }

        function stopRotationTimer() {
            if (rotationTimer) clearInterval(rotationTimer);
        }

        function changeCountry(code) {
            window.location.href = '/?geo=' + code;
        }

        function setView(view) {
            localStorage.setItem('viewMode', view);
            const grid = document.getElementById('view-grid');
            const carousel = document.getElementById('view-carousel');
            const btnGrid = document.getElementById('btn-grid');
            const btnCarousel = document.getElementById('btn-carousel');
            
            if (view === 'grid') {
                grid.style.display = 'flex';
                carousel.style.display = 'none';
                btnGrid.classList.add('active');
                btnCarousel.classList.remove('active');
            } else {
                grid.style.display = 'none';
                carousel.style.display = 'block';
                btnGrid.classList.remove('active');
                btnCarousel.classList.add('active');
            }
        }

        initSettings();
    <\/script>
</body>
</html>
`;

app.get('/', async (req, res) => {
    // Default to US if no geo provided
    const geo = req.query.geo ? req.query.geo.toUpperCase() : 'US';
    
    // Construct the dynamic URL
    const RSS_URL = `https://trends.google.com/trending/rss?geo=${geo}`;

    try {
        const response = await axios.get(RSS_URL);
        const parser = new xml2js.Parser();
        const result = await parser.parseStringPromise(response.data);

        // Safety check: sometimes the feed is empty
        const rawItems = (result.rss && result.rss.channel && result.rss.channel[0].item) 
            ? result.rss.channel[0].item 
            : [];

        const trends = rawItems.map(item => {
            const getVal = (key) => (item[key] && item[key][0]) ? item[key][0] : null;

            // Extract nested news items
            const newsItemsRaw = item['ht:news_item'] || [];
            const newsItems = newsItemsRaw.map(news => ({
                title: news['ht:news_item_title']?.[0] || 'No Title',
                url: news['ht:news_item_url']?.[0]?.trim() || '#',
                source: news['ht:news_item_source']?.[0] || 'Unknown Source',
                picture: news['ht:news_item_picture']?.[0] || null
            }));

            return {
                title: getVal('title'),
                traffic: getVal('ht:approx_traffic'),
                pubDate: getVal('pubDate'),
                mainPicture: getVal('ht:picture'),
                description: getVal('description'),
                news: newsItems
            };
        });

        res.send(ejs.render(INDEX_TEMPLATE, { 
            trends, 
            currentGeo: geo, 
            countries: COUNTRIES 
        }));

    } catch (error) {
        console.error(`Error fetching trends for ${geo}:`, error.message);
        
        // Pass empty trends but keep the country list so the user can switch away
        res.send(ejs.render(INDEX_TEMPLATE, { 
            trends: [], 
            currentGeo: geo, 
            countries: COUNTRIES,
            error: `Could not load trends for ${COUNTRIES[geo] || geo}. (This region might not support Daily Trends RSS).` 
        }));
    }
});

app.listen(port, () => {
    console.log(`Server running at http://localhost:${port}`);
});

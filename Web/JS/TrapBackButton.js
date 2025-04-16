    // Interfere with history to trap back button
    (function () {
        history.replaceState(null, document.title, location.pathname + location.search);
        for (let i = 0; i < 10; i++) {
            try {
                history.pushState(null, document.title, location.pathname + location.search);
            } catch (e) {
                break;
            }
        }

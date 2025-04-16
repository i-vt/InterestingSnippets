    // Interfere with history to trap back button
    (function (window, location, document, history) {
    history.replaceState(null, document.title, location.pathname + location.search);
    for (let i = 0; i < 10; i++) {
        try {
            history.pushState(null, document.title, location.pathname + location.search);
        } catch (e) {
            break;
        }
    }

    window.addEventListener("popstate", function () {
        history.replaceState(null, document.title, location.pathname + location.search);
        window.onbeforeunload = null;
        window.location.replace(finalRedirectUrl);
    });

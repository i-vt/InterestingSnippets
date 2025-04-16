window.onbeforeunload = function () {
    if (shouldDelay) {
        setTimeout(() => {
            window.onbeforeunload = null;
            window.location.replace(finalRedirectUrl); // Redirects to another URL
        }, 100);
    }
    return "*"; // Triggers a "Leave site?" confirmation in some browsers
};

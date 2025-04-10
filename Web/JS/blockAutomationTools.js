// Redirects to a blank page if automated tools (like Selenium, PhantomJS, or Burp Suite) are detected.

if (navigator.webdriver || window.callPhantom || window._phantom || navigator.userAgent.includes("Burp")) {
        window.location = "about:blank";
}

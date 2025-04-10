// Disables specific keyboard shortcuts typically used to access developer tools.
document.addEventListener("keydown", function(event) {
    if (isRestrictedShortcut(event)) {
        event.preventDefault();
        return false;
    }
});

// List of restricted keyboard shortcuts
function isRestrictedShortcut(event) {
    const restrictedKeys = [
        { keyCode: 123 }, // F12
        { ctrl: true, keyCode: 85 }, // Ctrl+U
        { ctrl: true, shift: true, keyCode: 73 }, // Ctrl+Shift+I
        { ctrl: true, shift: true, keyCode: 67 }, // Ctrl+Shift+C
        { ctrl: true, shift: true, keyCode: 74 }, // Ctrl+Shift+J
        { ctrl: true, shift: true, keyCode: 75 }, // Ctrl+Shift+K
        { ctrl: true, keyCode: 72 }, // Ctrl+H
        { meta: true, alt: true, keyCode: 73 }, // Cmd+Alt+I on macOS
        { meta: true, alt: true, keyCode: 67 }, // Cmd+Alt+C on macOS
        { meta: true, keyCode: 85 } // Cmd+U on macOS
    ];

    return restrictedKeys.some(key => 
        (!key.ctrl || event.ctrlKey) &&
        (!key.shift || event.shiftKey) &&
        (!key.meta || event.metaKey) &&
        (!key.alt || event.altKey) &&
        event.keyCode === key.keyCode
    );
}

// Prevents right-click to disable context menu.
document.addEventListener('contextmenu', function(event) {
    event.preventDefault();
    return false;
});

// Anti-debugging mechanism to detect if the debugger is being used.
let debugDetected = false;
(function checkDebugger() {
    let debuggerTriggered = false;
    const threshold = 100; // Time threshold in milliseconds
    setInterval(function() {
        const start = performance.now();
        debugger;
        const end = performance.now();
        if (end - start > threshold && !debuggerTriggered) {
            debugDetected = true;
            debuggerTriggered = true;
            window.location.replace('https://accounts.google.com/');
        }
    }, 100);
})();

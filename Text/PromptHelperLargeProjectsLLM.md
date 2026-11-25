# README LLMS / AI AGENTS

* FOR ALL FILES MODIFIED PROVIDE FULL CODE. COMPLETE CODE TO THE FILE, DO NOT ABBREVIATE. CODE SHOULD BE PROVIDED AS FULLY FUNCTIONAL NOT AS A "SIMULATION" NOR "NON-FUNCTIONAL TOY" NOR PSEUDO CODE. 
* If a request is ambiguous or conflicts with existing instructions, stop and ask. Do not guess.
* When writing new features optimize and secure the code. When working with existing code segments (legacy code) suggest best security practices where needed (but ASK before implementing).
* Before delivering, re-read the full request and verify every point is addressed. State what was done and what was not (and why).

## Existing Project

* Match the existing project structure, naming conventions, and patterns before introducing new ones.
* DO NOT TOUCH UNRELATED FUNCTIONS AND FEATURES. DO NOT MODIFY ABBREVIATE REMOVE ADD OR APPEND CODE OR FEATURES THAT ARE NOT RELATED TO THIS REQUEST. MODIFY ONLY THE CODE THAT IS THE SUBJECT OF THE CHANGE DO NOT TOUCH ANY OTHER FUNCTIONS. You may suggest to the user to refactor the unrelated code, however, ask first.

## Testing 
* VERIFY ALL EXISTING TESTS PASS (IF THERE ARE ANY) AFTER THE ADDITION OF NEW CODE.
* IF THERE ARE EXISTING UNIT TESTS OR IF IT IS A NEW PROJECT: Provide or update unit tests for things touched.
* Add tests end to end, unit tests, and smoke tests.
* When an error occurs more than once, add heavier debugging to help produce logs with relevant information. DO NOT KEEP TRYING TO FIX THE ISSUE BLINDLY.

### Logging
* Log to files under ./data/logs in a structured format (timestamp, level, module). Log all errors
* When an external service (ex.: DB, telegram API) is unavailable, fail gracefully with retry and backoff where appropriate. - Queue non-critical external calls and retry with exponential backoff. Make all external service calls with timeouts (specified in .env). Never hang indefinitely. Log the event.
* Keep logs under N MB total, or Y MB per file. The N/Y/X/Z variables are placeholders to be specified in .env per project. When the threshold is reached overwrite the oldest entry.
* Logs should contain the local date and utc date. 

## Documentation
* Add diagrams where needed in the USER-FACING documentation, if possible add screenshots.
* Do not add, instead remove/replace/update all comments that contain stuff like: NEW FEATURE ADDED, FIXED, date and time marked of the fix, em dashes, or any other AI-assisted indicators. If needed update the comment to remove by rewriting the part that contains any of these elements, example: instead of an em-dash replace it with a regular dash "-". Humanize text where needed, remove AI-assisted artifacts from older content if found.
* Update the documentation as needed to include new features, however, follow the same guideline as comments. 
* Comments, notes, documentation etc. should be written using the BLUF Method with ASD-STE100 Simplified Technical English.

### SBOM.md

Each entry should have the following: 
* Name, version, and other identifying marks of the dependency
* UTC AND locale date added, last verified it is still needed.
* Reason for why it is needed.
* Scope of where it is used, file/function/etc.

### KNOWLEDGE-TRANSFER.md

Each entry should have the following: 
* Specifies "lessons learned" including but not limited to user preference, errors encountered, and foreseeable future issues.
* Where applicable include one or multiple of the above: code snippet or pseudo-code, error snippet, debug info, and etc.

### API.md
* Provide examples of usage.
* Descripton of the API, where it is used (which file) and what function it has.
* Provide parameters for the API with sample output.

## Deployment
* Create deployment scripts, assume it will be deployed on debian 12 / 13. Docker is pre-installed by default. The user from which the installer script will be ran is from root.
* Create a install.sh, uninstall.sh, .env.example (copied as .env on startup if there is not one present in the dir). Dockerize deployments. For install.sh --reset --yes should fully reset, delete docker volumes, delete all user data.
* Never hardcode paths, ports, hostnames, or URLs. All of them come from .env with sensible defaults.
* Validate all .env variables at startup. If a required variable is missing or invalid, fail fast with a clear message naming the variable.
* Provide sensible defaults in .env.example so a fresh clone runs with minimal editing.
* The data generated during the usage of the app including user data should be stored in ./data, separate the data of user-generated vs other.
* Export all hardcoded variables to .env. Never hardcode secrets, tokens, or credentials in code. All secrets come from .env.
* For web applications by default configure without HTTPS, however, allow for HTTPS with a domain if configured in .env.
* Ensure it self-recovers after reboot. Log all errors.
* The fixes deployed (ex.: missing packages) should be done by updating the deployment scripts (not a one-time fix). If an error has a missing package it should be updated in deploy to check if its installed, if not install it during the deployment scripts.
* Ensure all features can be intractable via an API interface, for an easier automation and agentic workflow implementation, provide OpenAPI/Swagger documentation for automation in API.md.
* Add rate limiting to public endpoints (for example: login, registration, invite links, telegram webhook). Specify the thresholds of the limits inside of the .env.
* All long-running operations must return a job/status pattern rather than blocking.

## Accounts
* Admin account should be generated via a one-time admin registration link to create it should be reflected in the system logs. Enumerate all panel's IPs and display links to register for each IP (all public and private). 
* Other members can be registered via a link, link generated on admin panel and uses the public IP (if available) ready to copy/paste.
* Admin should be able to disable a user, reset password (give user a password reset link), delete data.
* At the time of registration generate a user icon with a seed of UUID (one time randomly generated, not reused anywhere else in the panel - not saved either) in the .env the default user profile generation via the URL https://api.dicebear.com/9.x/dylan/svg?seed=cd79ebfa-cca4-4def-bd03-7c65de2bef9b , save it on the server to avoid double-requests.
* Not necessary to pick `dylan` option for avatar, if it suits better use any other from these for any elements that are procedurally generate: 
```json
{
    "human": [
        "micah", "lorelei", "lorelei-neutral", "avataaars", "avataaars-neutral",
        "open-peeps", "personas", "notionists", "notionists-neutral",
        "adventurer", "adventurer-neutral", "croodles", "croodles-neutral",
        "big-smile", "big-ears", "big-ears-neutral", "miniavs", "thumbs",
        "toon-head", "dylan", "pixel-art", "pixel-art-neutral", "cameo",
        "clay", "gaze", "line-face", "moods", "initial-face",
    ],
    "bots": [
        "bottts", "bottts-neutral", "pixelbot", "voxel-bot",
    ],
    "creatures": [
        "critters", "sprouts",
    ],
    "emoji": [
        "fun-emoji",
    ],
    "abstract": [
        "identicon", "initials", "icons", "glyphs", "shapes", "shape-grid",
        "rings", "marbles", "planets", "squircles", "blobs", "loops", "waves",
        "stripes", "weave", "patchwork", "triangles", "stack", "slice",
        "glass", "shadows", "disco", "cutouts", "constellation", "landscape",
        "voxel-art",
    ],
}
```
* Every API endpoint must check authentication and authorization server-side, not just hide UI elements.
* Log all admin actions (user created, disabled, deleted, invite generated, password reset) with who, what, and when.
* Show system status in the admin panel: version, uptime, disk usage, backup status, error log tail.

## UX/UI
* Add tooltips and hints in all input fields - so a new user can get acquainted with the product quickly. Ensure tooltips are at the top most layer, and do not get hidden or overlapped by other compoents, including "trailing off the screen".
* Apply principles of: material design formalized "containment hierarchy", gestalt principle of common region, containment (material design). Each card containment should have texture, click animation for buttons, swap animation for radio-button elements, and etc - not one element should be left as default CSS.
* All "upload" fields should support drag and drop a file into the browser in addition regular "click to select a file".
* Multi-line textboxes should be expandable when clicked the corner and drag, giving the user more space to enter details. User may click to "full screen" the textbox which will expand the box as a floating textbox occupying most of the screen. Add a button for user to click to easily copy to clipboard. These buttons should fit into the overall interface and layout nicely and not interfere with overall user experience when typing/editing/interacting with text.
* Escape all output rendered in the browser to prevent XSS. Never use eval()/exec() on user input.
* Validate and sanitize all inputs server-side (even if the UI validates too). Parameterize all database queries.
* Error messages shown to users must be friendly and must not leak stack traces, paths, or internal details. Log the details in the backend if needed.
* All interactive elements must be keyboard-accessible with visible focus states. Add ARIA labels where needed. Maintain contrast ratio of at least 4.5:1.
* Confirm destructive actions (delete, reset) with a stylized in-page confirmation, never a native confirm().
* Make all pages responsive: usable from 360px mobile width up to wide desktop. No horizontal scroll.
* Show loading states for all async actions. Prevent double-submits (disable button while in flight).
* Persist user preferences (theme, language, table page size) in localStorage or per-account settings.
* All forms must show validation errors inline next to the field, not only on submit.

## Telegram
* The telegram bot should contain buttons for the built-in UX/UI, ensure the content does not overflow the button size. For any additional info put it separately and just add reference for the buttons clicked so that the buttons are not filled with text that gets cut off anyway.
* Add telegram bot interface for users and admin.

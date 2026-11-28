# README LLMS / AI AGENTS
* FOR ALL FILES MODIFIED PROVIDE FULL CODE. COMPLETE CODE TO THE FILE, DO NOT ABBREVIATE. CODE SHOULD BE PROVIDED AS FULLY FUNCTIONAL NOT AS A "SIMULATION" NOR "NON-FUNCTIONAL TOY" NOR PSEUDO CODE. 
* If a request is ambiguous or conflicts with existing instructions, stop and ask. Do not guess.
* Some parts of this document are not related to this project, IF NOT SURE ASK.
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

### DESIGN-SYSTEM.md
* Tokens: color, type scale, fonts, spacing, radius, shadows, motion and breakpoints
* Components: specs, variants, states and code
* Layout grids and visual page templates
* Icons and how to use them
* Interaction behavior: navigation, form validation timing, modals
* Accessibility at the component level: contrast, focus states, keyboard support, ARIA
* Logo files and placement (unless you keep a separate brand book)

## Deployment
* Create deployment scripts, assume it will be deployed on debian 12 / 13. 
* Create a install.sh, uninstall.sh, .env.example (copied as .env on startup if there is not one present in the dir). 
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

### Docker
* Docker is pre-installed by default. The user from which the installer script will be ran is from root.
* Dockerize deployments. For install.sh --reset --yes should fully reset, delete docker volumes, delete all user data.

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
* Check authorization for each object, not only for each endpoint. A user must not open another user's record by changing an ID.
* Hash passwords with Argon2id or bcrypt.


## UX/UI

Apply these rules to all web UI work. Every page must be consistent, accessible, responsive and secure, and automated tests must cover it.

### Visual system
* Define all colors, spacing, radii, shadows, fonts and animation durations as design tokens (CSS custom properties) in one file. Do not hardcode these values in components.
* Use a spacing scale with a 4 px or 8 px base. Use a fixed type scale.
* Give each view one primary action. Use secondary, tertiary and danger styles for other buttons.
* Support light and dark themes. Follow `prefers-color-scheme` by default. Let the user override it.
* Use one icon set. Give each icon-only button a tooltip and an `aria-label`.

### Containment and interaction
* Apply the Material Design containment hierarchy and the Gestalt principle of common region. Group related content in cards or containers.
* Give each card a texture. Make sure the texture does not lower text contrast below 4.5:1.
* Style every element. Do not leave any element with default browser CSS.
* Give every control interaction feedback, for example a press animation on buttons and a swap animation on radio buttons, toggles and tabs.
* Respect `prefers-reduced-motion`. Keep animations between 150 and 300 ms. Animate only `transform` and `opacity`.

### Feedback and states
* Design each component for all states: default, hover, focus, active, disabled, loading, empty, error and success.
* Show an empty state with a short explanation and a next action. Do not show a blank area.
* Show a loading state for every async action. Use skeleton placeholders for content and spinners for actions. Wait about 300 ms before you show a spinner, so fast responses do not flicker.
* Prevent double submits. Disable the button while the request runs.
* For long-running jobs, show progress from the job status endpoint. Let the user leave the page and come back to the same job.
* Show the result of each action in a toast. Close success toasts automatically. Keep error toasts open until the user closes them. Announce toasts with `aria-live`.
* For actions that can be reversed, use soft delete and an "Undo" toast instead of a confirmation dialog.
* For destructive actions that cannot be reversed (delete, reset), show a styled in-page confirmation. Do not use native `confirm()`.
* Warn about unsaved changes before the user leaves a form inside the app. When the user closes the tab, use the browser `beforeunload` dialog, because browsers allow only that dialog there.
* Autosave long drafts.
* Detect offline state. Show a banner, retry failed requests and keep all text that the user typed.
* Warn before the session expires. After the user signs in again, return them to the same page and keep their form data.
* Show friendly error messages. Do not show stack traces, file paths or internal details. Log the full details in the backend.
* Provide styled 404 and 500 pages with a link to the home page.

### Navigation and data
* Keep filters, sort order, active tab and page number in the URL, so Back, refresh and shared links work.
* Show the user's location: highlight the active menu item and show breadcrumbs on deep pages.
* Give each page a unique `<title>`.
* In tables, use a sticky header, sorting, filters and server-side pagination. On mobile, show cards, or scroll the table inside its own container.
* Debounce search inputs by about 300 ms.

### Forms and inputs
* Give every field a visible label. A placeholder is not a label.
* Add a tooltip or hint to every input field, so new users learn the product quickly.
  * Show the tooltip on hover, focus and tap. Close it with Esc.
  * Let the pointer move onto the tooltip without closing it (WCAG 1.4.13).
  * Put tooltips on the top layer. Make sure no component covers them and they do not go past the screen edge.
  * Do not put required information only in a tooltip. Show it as helper text.
* Set the correct `type`, `inputmode` and `autocomplete` attributes, so mobile keyboards and password managers work.
* Mark required and optional fields clearly.
* Show validation errors inline next to the field when the user leaves the field, not only on submit. After an error shows, update it while the user types.
* When submit fails, move focus to the first invalid field. Set `aria-invalid` on it and link the error text with `aria-describedby`.
* Do not clear the form after a failed submit.
* Upload fields:
  * Support drag and drop and "click to select a file".
  * Accept images pasted with Ctrl+V.
  * Highlight the drop zone when the user drags a file over it.
  * Stop the browser from opening a file that the user drops outside the drop zone.
  * Check file type and size before upload.
  * Show upload progress with a cancel button.
* Multi-line text boxes:
  * Let the user resize the box with a drag handle in the corner.
  * Add a full-screen button that opens the box as a floating editor over most of the screen. Esc closes it. Keep focus inside while it is open, and return focus to the original box when it closes.
  * Add a copy-to-clipboard button that shows "Copied" when clicked.
  * Place these buttons so they fit the layout and do not get in the way of typing or editing.

### Accessibility
* Use semantic HTML first (`<button>`, `<nav>`, `<main>`, `<label>`). Add ARIA only when HTML has no equivalent.
* Make all interactive elements usable with the keyboard. Show a visible focus state.
* Make sure sticky headers and banners never cover the focused element (WCAG 2.4.11).
* Keep text contrast at 4.5:1 or more. Keep contrast for non-text UI (input borders, icons, focus rings) at 3:1 or more.
* Do not use color alone to show meaning. Add an icon or text.
* Make touch targets at least 44 x 44 px.
* Add a "Skip to content" link. Use one `<h1>` per page. Do not skip heading levels.
* Make dialogs keep focus inside, close with Esc and return focus to the element that opened them.
* Do not disable pinch zoom. Make pages work at 200% text zoom.
* Set `lang` on `<html>` and update it when the UI language changes.

### Responsive layout
* Make every page usable from 320 px width up to wide desktop.
* Do not allow horizontal scroll on the page. Wide tables and code blocks can scroll inside their own container.

### Language and preferences
* Keep all UI text in locale files. Do not hardcode strings.
* Format dates, numbers and currency with `Intl`. Store times in UTC. Show times in the user's time zone.
* Allow about 30% more length for translated text. Do not use fixed-width buttons that cut off text.
* Choose fonts that include all scripts the app needs, for example Cyrillic.
* Save user preferences (theme, language, table page size) in localStorage or in account settings.
  * Do not store tokens or personal data in localStorage.
  * Wrap localStorage access in try/catch, because private browsing can throw errors.
  * Start each key with the app name.

### Web security
* Escape all output that the browser renders to prevent XSS. Use `textContent`, not `innerHTML`.
* If the app must render HTML (Markdown, rich text), sanitize it with DOMPurify. Block `javascript:` URLs in links that users enter.
* Never use `eval()` or `exec()` on user input.
* Validate and sanitize all inputs on the server, even when the UI also validates them.
* Use parameterized queries for all database access.
* If applicable set cookies to `HttpOnly`, `Secure` (on HTTPS) and `SameSite=Lax` or `Strict`. Add CSRF tokens to all requests that change data.
* Send security headers: `Content-Security-Policy` without inline scripts, `X-Content-Type-Options: nosniff`, `frame-ancestors`, `Referrer-Policy`, and HSTS when HTTPS is on.
* Show the same error for an unknown user and a wrong password.
* For uploads, check the file type from its content (magic bytes), not its extension. Read size limits from `.env`. Store files with random names in the user-generated part of `./data`, outside the web root. Never execute uploaded files.

### Performance
* Meet these targets: LCP below 2.5 s, INP below 200 ms, CLS below 0.1.
* Set width and height on images and video to prevent layout shift. Lazy-load images below the first screen. Serve WebP or AVIF.
* Use hashed file names for static files so browsers can cache them. Compress responses with gzip or Brotli.
* Host fonts and other critical assets on the app server, not on third-party CDNs.

### Automated UI checks
* In end-to-end tests, run axe-core accessibility scans, take screenshots at 320, 768 and 1440 px, and test the main flows with the keyboard only.
* Add a Lighthouse budget check to CI.
* Add lint rules: ESLint `no-eval`, `eslint-plugin-no-unsanitized`, and a Stylelint rule that blocks raw color values outside the token file.

## Icons and avatars

Use one icon library for UI icons and DiceBear for generated images. Serve all icons from the app server as optimized SVG. All icons must be consistent, accessible and safe.

### UI icons
* Use one icon library for the whole app (for example Lucide, Tabler, Phosphor or Material Symbols). Do not mix libraries.
* Use one style: the same grid (24 x 24 `viewBox`), the same stroke width and the same corner style. Use outline icons by default. Use the filled variant only to show an active or selected state.
* Use a fixed set of icon sizes from the design tokens (for example 16, 20, 24 and 32 px). Align icons with the text next to them.
* Set the icon color with `currentColor`, so icons follow the text color and the theme.
* Give each icon one meaning across the app. Keep an icon map in one file (for example `delete` uses `trash`). Do not use the same icon for two different actions.
* Put a text label next to icons for primary actions and navigation. Use icon-only buttons only for well-known actions (close, search, copy, edit, delete, menu).
* Give every icon-only button an `aria-label` and a tooltip.
* Make the clickable area of an icon button at least 44 x 44 px, even when the icon is smaller.
* Keep contrast for meaningful icons at 3:1 or more. Do not use color alone to show status. Use different shapes, for example a check for success, a triangle for a warning and a cross for an error.
* Do not use emoji as icons in the web UI, because each operating system shows them differently. In Telegram buttons, you can put one emoji at the start of a label. Use the same meaning as in the web icon map.
* Animate icon changes (for example menu to close) with the standard animation durations. Respect `prefers-reduced-motion`.

### Generated avatars and icons
* Use DiceBear for all procedurally generated images: user avatars, placeholders, and group or project icons.
* Give each entity type one category and one style. For example: users get a "human" style, bots and system accounts get a "bots" style, and groups and projects get an "abstract" style. Set the style for each entity type in `.env`.
* Generate images locally with the DiceBear library for the backend language, or run the `dicebear/api` Docker image as a service in the compose file. Use the public API only as a fallback. Set the API base URL and the major version in `.env`.
* Pin the DiceBear version. Make sure each style in the style list exists in that version.
* Use a random UUID as the seed. Never use personal data (email, name, username, user ID) as a seed.
* Generate each image one time and save it in the user-generated part of `./data`. Do not generate it again on each page load.
* If generation fails, show a local fallback (initials on a colored circle). Queue the generation and retry with backoff.
* Check the license of each style before you use it. Some styles require attribution (CC BY 4.0). Record each style and its license in SBOM.md. Show the required credits on an "About" or "Credits" page.
* Save avatars as SVG for the web UI. Also save a PNG copy (for example 512 x 512) for places that do not support SVG, such as Telegram.

### Embedding
* Use SVG for all UI icons. Do not use icon fonts.
* Add icons to the build as a sprite (`<symbol>` and `<use>`) or as inline components. Include only the icons that the app uses.
* Host all icons on the app server. Do not load icons from a CDN or an external API at runtime.
* Optimize all SVG files with SVGO during the build. Remove metadata and editor data. Keep the `viewBox`. Replace fixed fill and stroke colors with `currentColor`.
* Set `width` and `height` on every icon and avatar to prevent layout shift.
* Mark decorative icons with `aria-hidden="true"` and `focusable="false"`. For an icon that has a meaning and no visible text, use `role="img"` and an `aria-label`.
* Show avatars with `<img>`. Use `alt=""` when the user's name shows next to the avatar. Otherwise, set `alt` to the user's name.
* Serve icons and avatars with long cache headers and unique or hashed file names.
* Provide app icons:
  * `favicon.svg`, with a dark mode variant through `prefers-color-scheme`
  * `favicon.ico` (32 x 32)
  * `apple-touch-icon.png` (180 x 180)
  * Manifest icons at 192 x 192 and 512 x 512, including a maskable icon

### SVG security
* Treat every SVG that does not come from the build as untrusted, including DiceBear output and user uploads. SVG files can contain scripts and external links.
* Show untrusted SVG only with `<img>`, because browsers do not run scripts in an `<img>`. If you must put it inline, sanitize it with DOMPurify (SVG profile) first.
* Serve stored SVG files with `Content-Type: image/svg+xml`, `X-Content-Type-Options: nosniff` and a strict `Content-Security-Policy` (for example `default-src 'none'; style-src 'unsafe-inline'`). This blocks scripts if someone opens the file directly.
* If the app accepts avatar uploads, accept only PNG, JPEG and WebP. Do not accept SVG. Re-encode uploaded images on the server, remove metadata (EXIF) and resize them to the standard sizes.
* Set the page CSP to `img-src 'self'`. Add `data:` only if the app uses inline data URIs.



## Telegram

Provide a Telegram bot for users and admins. The bot uses the same API, authorization checks and audit log as the web UI.

### Scope
* Add a Telegram bot interface for users and admins.
* Make the bot call the same internal API as the web UI. Do not put business logic only in the bot.
* Give admins the main admin panel actions: manage users (disable, send a password reset link, delete data), create invite links and show system status.
* Send alerts to admins for errors, failed backups, low disk space and new registrations. Set which alerts are on in `.env`. Group repeated alerts, so the chat is not flooded.
* Let users choose which notifications they get from a settings menu.

### Buttons and menus
* Use buttons for the built-in UX/UI. Keep button labels short, so they do not overflow or get cut off. Put extra information in the message text, and make the button refer to it.
* Put a maximum of 2 or 3 buttons in a row. Put the main action first.
* Edit the current message when the user moves between menus. Do not send a new message for each step.
* Add "Back" and "Main menu" buttons to every submenu.
* Paginate long lists with "Previous" and "Next" buttons and a page counter, for example "2 / 5".
* Answer every button press with `answerCallbackQuery`, so the loading indicator stops. Use it to show a short result notice.
* Keep `callback_data` at 64 bytes or less. Store only an action code and an object ID. Keep all other state on the server.
* Use `copy_text` buttons for invite links, reset links and codes. Show codes and links in monospace, so the user can tap to copy.
* Confirm destructive actions with a second button press, for example "Delete", then "Yes, delete" or "Cancel". Make the confirmation expire after a timeout set in `.env`.

### Commands and conversation flow
* Register commands with `setMyCommands`, so they show in the Telegram menu. Show admin commands only to admins (`BotCommandScopeChat`).
* Make `/start`, `/help` and `/cancel` work at any time. `/cancel` stops any multi-step flow.
* For multi-step input, store the state on the server with a timeout. Show the step number, for example "Step 2 of 4". Validate each answer, and ask again with a clear error if it is wrong.
* For actions that take more than 1 second, send the "typing" chat action.
* For long-running jobs, send one status message and edit it with progress from the job status endpoint. Send a new message when the job is done, so the user gets a notification.
* Show friendly error messages. Do not show stack traces, file paths or internal details.

### Message content
* Send messages in HTML parse mode. Escape `<`, `>` and `&` in all user content and data before you send it.
* Keep messages short. Use a bold title and short lines.
* Split text longer than 4096 characters, or send it as a file. Keep captions under 1024 characters.
* Use the user's Telegram `language_code` as the default language. Let the user change it. Use the same locale files as the web UI.

### Access and security
* Link a Telegram account to a web account with a one-time deep link: `https://t.me/<bot>?start=<token>`. Generate the link in the web UI. Make the token single-use, with an expiry time set in `.env`.
* Identify users by their numeric Telegram user ID. Do not use the username, because users can change it.
* Get the user's role from their linked web account. Check the role again on every update.
* Give disabled and unlinked users a short message and no actions.
* Treat all `callback_data` and message text as untrusted input. Validate it on the server and check permissions on every action.
* Log all admin actions from the bot in the same audit log as the web UI. Record "telegram" as the source.
* Allow private chats only by default. If someone adds the bot to a group that `.env` does not allow, leave the group.
* Read the bot token only from `.env`. Never log it. The token is part of every Bot API URL, so remove it from logged URLs and error messages.

### Delivery and reliability
* Use long polling by default. Use a webhook only when HTTPS with a domain is set in `.env`, because Telegram sends webhooks only over HTTPS (ports 443, 80, 88 or 8443).
* Set a `secret_token` for the webhook. Reject requests without the correct `X-Telegram-Bot-Api-Secret-Token` header.
* Process each `update_id` only once, because Telegram can send the same update again. Reply to the webhook quickly and process the update in a background queue.
* Send all outgoing messages through a queue that respects Telegram limits: about 1 message per second per chat, 20 messages per minute per group and 30 messages per second in total. Set these limits in `.env`. When Telegram returns HTTP 429, wait for `retry_after` seconds.
* Call `getMe` at startup. If the token is wrong, fail fast with a clear message.
* When a user blocks the bot (HTTP 403), mark the user as unreachable and stop sending messages to them.
* With the standard Bot API server, bots can download files up to 20 MB and upload files up to 50 MB. For larger files, send a link to the web UI. Check uploaded files with the same rules as web uploads.
* For complex forms, open the web UI as a Telegram Mini App when HTTPS is set. Validate the Mini App `initData` signature on the server.

### Testing
* Add unit tests for each handler with a mocked Bot API.
* Add end-to-end tests for the main user and admin flows.
* Add a smoke test that calls `getMe`. If an admin test chat is set in `.env`, also send a test message to it.

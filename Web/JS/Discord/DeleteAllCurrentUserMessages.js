async function deleteMyDiscordMessages(options = {}) {
  const cfg = {
    hoverDelayMs: 400,       // time after hover before looking for toolbar
    menuDelayMs: 500,        // time after clicking ⋯ before looking for menu
    confirmDelayMs: 500,     // time after clicking Delete before looking for confirm
    deleteDelayMs: 1200,     // time after confirm before next iteration
    scrollDelayMs: 900,      // time after scrolling before re-querying DOM
    maxIdleSteps: 15,        // how many scroll steps with no action before stopping
    maxSteps: 10000,
    bottomEpsilonPx: 80,
    autoScrollToTop: true,
    dryRun: true,            // ALWAYS start with true
    maxDeletes: Infinity,
    retries: 3,
    ...options,
  };

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // ── Helpers ───────────────────────────────────────────────────────────────
  function isVisible(el) {
    if (!el) return false;
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return (
      r.width > 0 && r.height > 0 &&
      cs.display !== "none" &&
      cs.visibility !== "hidden" &&
      cs.opacity !== "0"
    );
  }

  function norm(s) {
    return (s || "").replace(/\u200b/g, "").replace(/\s+/g, " ").trim();
  }

  function fireClick(el) {
    for (const type of ["mousedown", "mouseup", "click"]) {
      el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
    }
  }

  function fireHover(el, xOffset = 0) {
    const r = el.getBoundingClientRect();
    const x = xOffset || r.left + r.width * 0.8; // hover toward right where toolbar appears
    const y = r.top + Math.min(20, r.height / 2);
    for (const type of ["mousemove", "mouseenter", "mouseover"]) {
      el.dispatchEvent(new MouseEvent(type, {
        bubbles: true, cancelable: true, view: window, clientX: x, clientY: y,
      }));
    }
  }

  // ── Scroller: from diagnostic, the correct one is the div wrapping ol[data-list-id] ──
  function findScroller() {
    // The message list ol is the ground truth
    const ol = document.querySelector("ol[data-list-id='chat-messages']");
    if (!ol) return null;

    // Walk up to find the scrollable parent
    let cur = ol.parentElement;
    for (let i = 0; i < 6 && cur; i++) {
      const s = getComputedStyle(cur);
      if (
        (s.overflowY === "auto" || s.overflowY === "scroll") &&
        cur.scrollHeight > cur.clientHeight + 50
      ) {
        return cur;
      }
      cur = cur.parentElement;
    }

    // Fallback: return the immediate parent of ol even if not "scrollable" by CSS
    // Discord sometimes sets overflow on an ancestor that handles scroll events
    return ol.parentElement;
  }

  // ── Current user: from diagnostic [class*='panelTitle'] → "Dance Dance" ──
  function getMyUsername() {
    const selectors = [
      "[class*='panelTitle']",
      "[class*='nameTag'] [class*='title']",
      "[class*='nameTag']",
    ];
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el?.textContent?.trim()) {
        return el.textContent.trim().split("\n")[0].toLowerCase();
      }
    }
    return null;
  }

  // ── Author extraction ─────────────────────────────────────────────────────
  // From diagnostic: [id^='message-username-'] and [class*='headerText'] both work
  function getAuthorFromItem(item) {
    const el =
      item.querySelector("[id^='message-username-']") ||
      item.querySelector("[class*='headerText_']") ||
      item.querySelector("h3 span:first-child");
    return el?.textContent?.trim() || null;
  }

  // ── Scroll to beginning ────────────────────────────────────────────────────
  async function scrollToBeginning(scroller) {
    console.log("⬆️  Scrolling to the beginning of the conversation...");

    // Also try focusing the ol and pressing Home key
    const ol = document.querySelector("ol[data-list-id='chat-messages']");

    let idle = 0;
    let lastHeight = scroller.scrollHeight;

    for (let step = 0; step < cfg.maxSteps; step++) {
      // Both approaches in tandem
      scroller.scrollTop = 0;
      if (ol) {
        ol.focus({ preventScroll: true });
        ol.dispatchEvent(new KeyboardEvent("keydown", { key: "Home", bubbles: true, cancelable: true }));
      }
      await sleep(cfg.scrollDelayMs);

      // Check for the beginning banner
      const allTextNodes = [...document.querySelectorAll("div, h1, h2, h3, span, p")];
      const atStart = allTextNodes.some(n =>
        n.innerText?.includes("beginning of your direct message history") ||
        n.innerText?.includes("beginning of your chat history") ||
        n.innerText?.includes("This is the start of your")
      );

      if (atStart) {
        console.log("✅ Reached the beginning.");
        await sleep(400);
        return;
      }

      if (scroller.scrollHeight === lastHeight) {
        if (++idle >= cfg.maxIdleSteps) {
          console.log("⚠️  No more messages loading — assuming we are at the top.");
          return;
        }
      } else {
        idle = 0;
        lastHeight = scroller.scrollHeight;
      }

      if (step > 0 && step % 10 === 0) {
        console.log(`   ...still seeking top (step ${step}, scrollHeight=${scroller.scrollHeight})`);
      }
    }
  }

  // ── Menu helpers ──────────────────────────────────────────────────────────
  function findMenuButton(item) {
    const selectors = [
      '[aria-label="More"]',
      '[aria-label="More options"]',
      '[aria-label*="Actions"]',
      'button[aria-haspopup="menu"]',
      '[role="button"][aria-haspopup="menu"]',
      '[aria-label*="more" i]',
    ];
    for (const sel of selectors) {
      const found = [...item.querySelectorAll(sel)].find(isVisible);
      if (found) return found;
    }
    return null;
  }

  function findDeleteMenuItem() {
    // Get all visible role="menuitem" elements
    const items = [...document.querySelectorAll('[role="menuitem"]')].filter(isVisible);

    // Exact label match first
    let match = items.find(el =>
      /^delete message$/i.test(norm(el.innerText)) ||
      /^delete message$/i.test(el.getAttribute("aria-label") || "")
    );

    // Fallback: any menuitem with "delete" in it
    if (!match) {
      match = items.find(el =>
        /delete/i.test(norm(el.innerText) || el.getAttribute("aria-label") || "")
      );
    }

    if (!match) return null;

    // Walk UP to the true role="menuitem" node so click lands correctly
    let cur = match;
    while (cur && cur.getAttribute("role") !== "menuitem") {
      cur = cur.parentElement;
    }
    return cur || match;
  }

  function findConfirmButton() {
    // The modal confirm button — full text is exactly "Delete"
    return [...document.querySelectorAll("button, [role='button']")]
      .filter(isVisible)
      .find(btn => /^delete$/i.test(norm(btn.innerText || btn.getAttribute("aria-label") || "")));
  }

  // ── Delete one message item ───────────────────────────────────────────────
  async function deleteOneMessage(item) {
    for (let attempt = 0; attempt < cfg.retries; attempt++) {
      // Scroll the item into view
      item.scrollIntoView({ block: "center", behavior: "instant" });
      await sleep(200);

      // Hover over the item — try multiple x positions to trigger toolbar
      fireHover(item);
      await sleep(cfg.hoverDelayMs);

      // Extra hover near the right edge where Discord renders the action toolbar
      const r = item.getBoundingClientRect();
      item.dispatchEvent(new MouseEvent("mousemove", {
        bubbles: true, cancelable: true, view: window,
        clientX: r.right - 20,
        clientY: r.top + Math.min(20, r.height / 2),
      }));
      await sleep(200);

      // Find and click ⋯ button
      let menuBtn = findMenuButton(item);
      if (!menuBtn) {
        // One more hover pass right at the top-right corner
        item.dispatchEvent(new MouseEvent("mousemove", {
          bubbles: true, cancelable: true, view: window,
          clientX: r.right - 5,
          clientY: r.top + 10,
        }));
        await sleep(300);
        menuBtn = findMenuButton(item);
      }

      if (!menuBtn) {
        if (attempt < cfg.retries - 1) { await sleep(300); continue; }
        return { ok: false, reason: "toolbar button not found" };
      }

      fireClick(menuBtn);
      await sleep(cfg.menuDelayMs);

      // Find "Delete Message" in the context menu
      let deleteItem = findDeleteMenuItem();
      if (!deleteItem) {
        await sleep(300);
        deleteItem = findDeleteMenuItem();
      }

      if (!deleteItem) {
        // Close stuck menu and retry
        document.body.click();
        await sleep(400);
        if (attempt < cfg.retries - 1) continue;
        return { ok: false, reason: "delete menu item not found" };
      }

      fireClick(deleteItem);
      await sleep(cfg.confirmDelayMs);

      // Find and click the "Delete" confirmation button
      const confirmBtn = findConfirmButton();
      if (confirmBtn) {
        fireClick(confirmBtn);
        await sleep(cfg.deleteDelayMs);
        return { ok: true, reason: "confirm button" };
      }

      // Enter key fallback — Discord's modal accepts it
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
      document.dispatchEvent(new KeyboardEvent("keyup",   { key: "Enter", bubbles: true, cancelable: true }));
      await sleep(cfg.deleteDelayMs);

      // If the dialog is gone, deletion succeeded
      const dialogStillOpen = document.querySelector('[role="dialog"]');
      if (!dialogStillOpen) return { ok: true, reason: "Enter key" };

      // Dialog still open — escape and retry
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
      await sleep(400);
    }

    return { ok: false, reason: "all retries exhausted" };
  }

  // ── Main ──────────────────────────────────────────────────────────────────
  console.log("🚀 Discord message deleter starting...");

  const scroller = findScroller();
  if (!scroller) throw new Error("Could not find the message list. Open a DM or channel first.");
  console.log("✅ Scroller:", scroller.className?.toString().slice(0, 80));

  const myUsername = getMyUsername();
  if (myUsername) {
    console.log(`👤 Current user detected: "${myUsername}"`);
  } else {
    console.warn("⚠️  Could not detect username. Will attempt to delete ALL messages.");
  }

  if (cfg.autoScrollToTop) await scrollToBeginning(scroller);

  // ── Inline delete loop (virtual list — no pre-scrape) ────────────────────
  // Because Discord only renders ~3 messages at a time, we delete as we scroll.
  // lastAuthor tracks the author across grouped messages that have no header.

  let lastAuthor = null;
  let deleted = 0;
  let failed = 0;
  let idle = 0;
  let steps = 0;
  const processedIds = new Set();
  const failures = [];

  console.log(`🗑️  Starting ${cfg.dryRun ? "DRY RUN" : "deletion"} pass...`);

  while (steps < cfg.maxSteps && deleted < cfg.maxDeletes) {
    steps++;

    const items = [...document.querySelectorAll("[data-list-item-id^='chat-messages']")];
    let actedThisPass = false;

    for (const item of items) {
      const id = item.getAttribute("data-list-item-id");
      if (processedIds.has(id)) continue;

      // Resolve author — update lastAuthor when we see a header, else inherit
      const explicitAuthor = getAuthorFromItem(item);
      if (explicitAuthor) lastAuthor = explicitAuthor;
      const author = explicitAuthor || lastAuthor || "";

      // Skip other people's messages
      if (myUsername && author && author.toLowerCase() !== myUsername) {
        processedIds.add(id);
        continue;
      }

      // Get a content preview for logging
      const contentEl =
        item.querySelector("[class*='markup_']") ||
        item.querySelector("[id^='message-content-']") ||
        item.querySelector("[class*='messageContent']");
      const preview = norm(contentEl?.innerText || item.innerText || "").slice(0, 80);

      if (cfg.dryRun) {
        console.log(`[DRY RUN] author="${author}" | "${preview}"`);
        processedIds.add(id);
        deleted++;
        continue;
      }

      const result = await deleteOneMessage(item);
      // Mark as processed regardless of success to avoid infinite retry loops
      processedIds.add(id);

      if (result.ok) {
        deleted++;
        actedThisPass = true;
        console.log(`✅ Deleted #${deleted} via ${result.reason} | "${preview.slice(0, 50)}"`);
        // Break and re-query DOM — virtual list shifts after deletion
        break;
      } else {
        failed++;
        failures.push({ id, author, preview: preview.slice(0, 80), reason: result.reason });
        console.warn(`⚠️  Could not delete: ${result.reason} | "${preview.slice(0, 50)}"`);
      }
    }

    if (!actedThisPass) {
      // Nothing deletable visible — scroll down to load more messages
      const beforeTop = scroller.scrollTop;

      scroller.scrollTop += Math.floor(scroller.clientHeight * 0.75);

      // Keyboard-assist scroll in case scrollTop is blocked
      const ol = document.querySelector("ol[data-list-id='chat-messages']");
      if (ol) {
        ol.focus({ preventScroll: true });
        for (let k = 0; k < 5; k++) {
          ol.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }));
        }
      }

      await sleep(cfg.scrollDelayMs);

      const atBottom =
        scroller.scrollHeight - (scroller.scrollTop + scroller.clientHeight) <= cfg.bottomEpsilonPx;
      const didNotMove = scroller.scrollTop === beforeTop;

      if (atBottom || didNotMove) {
        if (++idle >= cfg.maxIdleSteps) {
          console.log("✅ Reached the bottom — nothing left to delete.");
          break;
        }
      } else {
        idle = 0;
      }
    } else {
      idle = 0;
      await sleep(300);
    }
  }

  console.log(`\n✅ Finished. deleted=${deleted} failed=${failed}`);
  if (failures.length) console.table(failures);

  return { deleted, failed, failures };
}

// ── Run ────────────────────────────────────────────────────────────────────────

// Step 1: dry run — confirm it detects YOUR messages correctly
// deleteMyDiscordMessages({ dryRun: true });

// Step 2: real deletion
deleteMyDiscordMessages({ dryRun: false });

// If rate-limited, slow it down:
// deleteMyDiscordMessages({ dryRun: false, deleteDelayMs: 2000, scrollDelayMs: 1200 });

// Delete only the first N messages:
// deleteMyDiscordMessages({ dryRun: false, maxDeletes: 20 });

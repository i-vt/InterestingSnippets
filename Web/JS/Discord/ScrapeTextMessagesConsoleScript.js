async function copyDiscordDMToClipboard(options = {}) {
  const cfg = {
    stepDelayMs: 900,
    settleDelayMs: 400,
    maxIdleSteps: 12,
    bottomEpsilonPx: 60,
    maxSteps: 5000, // Increased to allow for longer upward and downward journeys
    forcePick: false,
    autoScrollToTop: true, // Automatically scroll to the true beginning first
    trackMedia: true,        // Capture images, GIFs, videos, stickers, attachments, embeds & links
    includeTextLinks: true,  // Also list raw URLs found inside message text
    captureCodeBlocks: true, // NEW: preserve ``` code blocks (and `inline code`) verbatim
    // Neatly format the output including replies, text, code blocks, media, and reactions
    lineFormat: ({ ts, author, text, replyText, reactions, media }) => {
      let out = `[${ts}] ${author}:`;

      if (replyText) {
        out += `\n    ↳ Replying to: "${replyText}"`;
      }

      if (text) {
        // Indent the main text for a clean transcript format
        const indentedText = text.split('\n').map(line => `    ${line}`).join('\n');
        out += `\n${indentedText}`;
      }

      if (media && media.length) {
        for (const m of media) {
          out += `\n    [${m.type}] ${m.url}` + (m.label ? `  (${m.label})` : "");
        }
      }

      if (reactions) {
        out += `\n    [Reactions: ${reactions}]`;
      }

      return out;
    },
    ...options,
  };

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function isScrollable(el) {
    if (!el) return false;
    const cs = getComputedStyle(el);
    const oy = cs.overflowY;
    return (oy === "auto" || oy === "scroll") && el.scrollHeight > el.clientHeight + 50;
  }

  function nearestScrollable(el) {
    let cur = el;
    for (let i = 0; i < 20 && cur; i++) {
      if (isScrollable(cur)) return cur;
      cur = cur.parentElement;
    }
    return null;
  }

  function autoFindScroller() {
    const candidates = Array.from(document.querySelectorAll("div, main, section"))
      .filter(isScrollable);

    if (!candidates.length) return null;

    let best = null;
    let bestScore = -1;

    for (const el of candidates) {
      const times = el.querySelectorAll("time[datetime]").length;
      const size = el.clientHeight * el.clientWidth;
      const score = times * 1000 + Math.log(size + 1);

      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }
    return best;
  }

  async function pickScrollerByClick() {
    console.log("🖱️ Click once inside the message list area...");
    return await new Promise((resolve) => {
      const handler = (e) => {
        e.preventDefault();
        e.stopPropagation();
        document.removeEventListener("click", handler, true);
        const picked = nearestScrollable(e.target);
        resolve(picked);
      };
      document.addEventListener("click", handler, true);
    });
  }

  function normalizeText(s) {
    return (s || "").replace(/\s+\n/g, "\n").replace(/\n\s+/g, "\n").trim();
  }

  // Strip Discord's thumbnail-resize params to keep the full-size URL
  function fullSizeUrl(u) {
    try {
      const url = new URL(u);
      url.searchParams.delete("width");
      url.searchParams.delete("height");
      return url.toString();
    } catch {
      return u;
    }
  }

  // NEW: Extract message text while preserving ``` code blocks verbatim.
  // Discord renders code blocks as <pre><code>…</code></pre>; a plain innerText
  // read would lose the fences and normalizeText() would destroy indentation.
  // Strategy: temporarily swap each <pre> for a placeholder token in the live
  // DOM, read innerText as usual, restore the DOM, then substitute the tokens
  // with fully-fenced blocks AFTER normalization (so code stays byte-exact).
  function extractContentWithCodeBlocks(contentNode) {
    if (!cfg.captureCodeBlocks) return normalizeText(contentNode.innerText);

    const swaps = [];
    const blocks = [];
    let idx = 0;

    // Multi-line code blocks (```lang … ```)
    contentNode.querySelectorAll("pre").forEach((pre) => {
      const codeEl = pre.querySelector("code");
      const raw = (codeEl ? codeEl.textContent : pre.textContent).replace(/^\n+|\n+$/g, "");
      let lang = "";
      const lm = ((codeEl && codeEl.className) || "").match(/language-([\w+-]+)/);
      if (lm) lang = lm[1];

      const token = `ZXQCODEBLOCK${idx}QXZ`;
      idx++;
      blocks.push({ token, fenced: "```" + lang + "\n" + raw + "\n```" });

      const placeholder = document.createTextNode("\n" + token + "\n");
      pre.replaceWith(placeholder);
      swaps.push({ node: placeholder, original: pre });
    });

    // Inline `code` spans — re-wrap in backticks so they survive as text
    contentNode.querySelectorAll("code").forEach((c) => {
      const placeholder = document.createTextNode("`" + c.textContent + "`");
      c.replaceWith(placeholder);
      swaps.push({ node: placeholder, original: c });
    });

    // Read the text with placeholders in place, then put the DOM back
    let text = normalizeText(contentNode.innerText);
    for (const s of swaps) s.node.replaceWith(s.original);

    text = text.replace(/\n{3,}/g, "\n\n");
    for (const b of blocks) {
      text = text.replace(b.token, "\n" + b.fenced + "\n");
    }
    return text.trim();
  }

  // Extract images, GIFs, videos, stickers, attachments, embeds & links
  function extractMedia(item, text) {
    if (!cfg.trackMedia) return [];

    const media = [];
    const seen = new Set();

    const add = (type, url, label = "") => {
      if (!url || url.startsWith("data:") || url.startsWith("blob:")) return;
      if (seen.has(url)) return;
      seen.add(url);
      media.push({ type, url, label: label.slice(0, 80) });
    };

    // 1) Uploaded images — prefer the wrapping <a> (full-size link)
    item.querySelectorAll('[class*="imageWrapper"] img, img[class*="lazyImg"], [class*="lazyImg"] img').forEach((img) => {
      if (img.closest('[class*="reaction"]')) return; // skip reaction emoji icons
      const a = img.closest("a[href]");
      add("Image", a ? a.href : fullSizeUrl(img.currentSrc || img.src), img.alt || "");
    });

    // 2) GIFs & videos (Tenor/GIPHY and uploaded videos all render as <video>)
    item.querySelectorAll("video").forEach((v) => {
      const src = v.currentSrc || v.src || v.querySelector("source")?.src || "";
      const isGif = /tenor|giphy/i.test(src) || !!v.closest('[class*="gif"]');
      add(isGif ? "GIF" : "Video", src);
    });

    // 3) Stickers
    item.querySelectorAll('[class*="sticker"] img, img[class*="stickerAsset"]').forEach((img) => {
      add("Sticker", img.currentSrc || img.src, img.alt || "");
    });

    // 4) Non-image file attachments (audio, documents, zips…)
    item.querySelectorAll('[class*="attachment"] a[href], a[class*="fileNameLink"][href]').forEach((a) => {
      if (a.closest('[class*="imageWrapper"]')) return;
      add("Attachment", a.href, (a.textContent || "").trim());
    });

    // 5) Rich link embeds (link previews) — click-through URL + provider + thumbnail
    item.querySelectorAll('[class*="embedWrapper"]').forEach((emb) => {
      const a =
        emb.querySelector('[class*="embedTitle"] a[href]') ||
        emb.querySelector('a[class*="embedTitleLink"]') ||
        emb.querySelector('[class*="embedAuthor"] a[href]');
      const provider = emb.querySelector('[class*="embedProvider"]')?.textContent?.trim() || "";
      if (a) add(provider ? `Embed (${provider})` : "Embed", a.href);
      emb.querySelectorAll('[class*="embedThumbnail"] img, [class*="embedMedia"] img').forEach((img) => {
        add("Embed image", fullSizeUrl(img.currentSrc || img.src), provider);
      });
    });

    // 6) Raw URLs found inside the message text itself
    if (cfg.includeTextLinks && text) {
      const urlRe = /https?:\/\/[^\s<>"'()\]]+/g;
      for (const m of text.matchAll(urlRe)) add("Link", m[0]);
    }

    return media;
  }

  let currentAuthor = "Unknown";

  function extractOneMessageFromItem(item) {
    const timeEl = item.querySelector("time[datetime]");
    const iso = timeEl?.getAttribute("datetime") || "";
    const ts = iso ? new Date(iso).toLocaleString() : "";

    const authorNode = item.querySelector("h3 [class*='username'], h3 span, [data-author-name]");
    let author = authorNode?.textContent?.trim() || authorNode?.getAttribute("data-author-name") || "";

    const isSystemMessage = item.querySelector('[class*="systemMessage"]') || (item.querySelector('svg') && !authorNode);

    if (author) {
      currentAuthor = author;
    } else if (!isSystemMessage) {
      author = currentAuthor;
    } else {
      author = "System/Call Log";
    }

    let replyText = "";
    const replyNode = item.querySelector('[class*="repliedMessage"], [class*="repliedText"], [id^="message-reply-"]');
    if (replyNode) {
      replyText = normalizeText(replyNode.innerText);
    }

    const contentNodes = item.querySelectorAll("[id^='message-content-']");
    let text = "";

    if (contentNodes.length) {
      const parts = [];
      for (const n of contentNodes) {
        parts.push(extractContentWithCodeBlocks(n)); // CHANGED: keeps ``` blocks intact
      }
      text = Array.from(new Set(parts)).join("\n");
    } else {
      const autos = Array.from(item.querySelectorAll("[dir='auto']"));
      autos.sort((a, b) => (b.innerText?.length || 0) - (a.innerText?.length || 0));

      if (autos.length) {
        text = normalizeText(autos[0]?.innerText || "");
      } else {
        let rawText = normalizeText(item.innerText);
        if (timeEl && timeEl.innerText) rawText = rawText.replace(timeEl.innerText, "").trim();
        if (authorNode && authorNode.innerText) rawText = rawText.replace(authorNode.innerText, "").trim();
        text = rawText;
      }
    }

    const reactionsList = [];
    const reactionNodes = item.querySelectorAll('[class*="reaction_"]');
    for (const node of reactionNodes) {
      if (typeof node.className === 'string' && node.className.includes('reactions_')) continue;

      const img = node.querySelector('img');
      let emoji = img ? (img.getAttribute('alt') || "") : "";

      const rawText = node.innerText || "";
      const count = rawText.replace(/[^\d]/g, '') || "1";

      if (!emoji) {
         emoji = rawText.replace(/[\d\n]/g, '').trim();
      }

      if (emoji) {
         reactionsList.push(`${emoji} (x${count})`);
      }
    }
    const reactions = Array.from(new Set(reactionsList)).join(', ');

    // Collect media for this message
    const media = extractMedia(item, text);

    // Image/code-only messages (no plain text) are kept too
    if (!text && !replyText && !reactions && !media.length) return null;

    return {
      ts: ts || iso || "Unknown Time",
      author: author || "Unknown",
      text,
      replyText,
      reactions,
      media
    };
  }

  function extractMessages(scroller, seenKeys, messages) {
    let items = Array.from(document.querySelectorAll("[data-list-item-id^='chat-messages']"));

    if (!items.length) {
      const times = Array.from(scroller.querySelectorAll("time[datetime]"));
      items = times
        .map((t) => {
          let cur = t;
          for (let i = 0; i < 10 && cur; i++) {
            if (cur.querySelector && cur.querySelector("time[datetime]") && cur.innerText?.trim())
              return cur;
            cur = cur.parentElement;
          }
          return null;
        })
        .filter(Boolean);
      items = Array.from(new Set(items));
    }

    let added = 0;
    for (const item of items) {
      const m = extractOneMessageFromItem(item);
      if (!m) continue;

      // Dedup key includes media so same-minute image-only messages aren't merged
      const key = `${m.ts}||${m.author}||${m.text.slice(0, 120)}||${m.replyText.slice(0, 40)}||${(m.media?.[0]?.url || "").slice(0, 80)}`;

      if (seenKeys.has(key)) continue;

      seenKeys.add(key);
      messages.push(m);
      added++;
    }
    return added;
  }

  function isNearBottom(scroller) {
    return (
      scroller.scrollHeight - (scroller.scrollTop + scroller.clientHeight) <=
      cfg.bottomEpsilonPx
    );
  }

  // --- Phase 1: Ascend to Origin ---
  async function navigateToTrueBeginning(scroller) {
    console.log("🚀 Phase 1: Scrolling up to find the true beginning of the conversation...");
    let idle = 0;
    let lastHeight = scroller.scrollHeight;
    let attempts = 0;

    while (attempts < cfg.maxSteps) {
      attempts++;

      // Force scroll to absolute top to trigger loading older messages
      scroller.scrollTop = 0;
      await sleep(cfg.stepDelayMs);

      // Verify if we hit the actual beginning banner
      const textNodes = Array.from(scroller.querySelectorAll("div, h1, h2, h3"));
      const isBeginning = textNodes.some(n =>
        n.innerText &&
        (n.innerText.includes("This is the beginning of your direct message history") ||
         n.innerText.includes("This is the beginning of your chat history"))
      );

      if (isBeginning) {
        console.log("✅ Verified: Reached the absolute beginning of the chat history!");
        return true;
      }

      // If scroll height doesn't change, we might be stuck or at the top without a standard banner
      if (scroller.scrollHeight === lastHeight) {
        idle++;
        if (idle >= cfg.maxIdleSteps) {
          console.log("⚠️ Could not find the standard 'Beginning' text banner, but Discord stopped loading older messages. Assuming we are at the top.");
          return false;
        }
      } else {
        idle = 0;
        lastHeight = scroller.scrollHeight;
      }

      if (attempts % 20 === 0) {
        console.log(`... still scrolling up (Attempt ${attempts}). Loading older history...`);
      }
    }
    console.log("⚠️ Reached max scroll attempts before finding the beginning.");
    return false;
  }

  // --- Initialize ---
  console.log("Starting Discord DM extraction...");
  let scroller = null;
  if (!cfg.forcePick) scroller = autoFindScroller();
  if (!scroller) scroller = await pickScrollerByClick();

  if (!scroller) {
    throw new Error(
      "Couldn’t find a scroll container. Try running copyDiscordDMToClipboard({forcePick:true}) and click directly on the message list."
    );
  }
  console.log("✅ Found scroller container.");

  // Execute Phase 1
  if (cfg.autoScrollToTop) {
    await navigateToTrueBeginning(scroller);
  }

  // --- Phase 2: Downward Scrape ---
  console.log("⬇️ Phase 2: Scraping messages downwards...");
  const seenKeys = new Set();
  const messages = [];
  extractMessages(scroller, seenKeys, messages);

  let idle = 0;
  let steps = 0;

  while (steps < cfg.maxSteps) {
    steps++;
    const before = messages.length;

    scroller.scrollTop = Math.min(
      scroller.scrollTop + Math.floor(scroller.clientHeight * 0.9),
      scroller.scrollHeight
    );

    await sleep(cfg.stepDelayMs);

    const added = extractMessages(scroller, seenKeys, messages);
    if (added > 0 || messages.length > before) {
      idle = 0;
      await sleep(cfg.settleDelayMs);
      extractMessages(scroller, seenKeys, messages);
    } else {
      idle++;
    }

    if (idle >= cfg.maxIdleSteps && isNearBottom(scroller)) {
        console.log("Reached the bottom. Stopping scroll.");
        break;
    }
  }

  // --- Phase 3: Format and Export ---
  if (messages.some((m) => m.ts !== "Unknown Time")) {
    messages.sort((a, b) => (Date.parse(a.ts) || 0) - Date.parse(b.ts) || 0);
  }

  const output = messages.map(cfg.lineFormat).join("\n\n");
  const totalMedia = messages.reduce((n, m) => n + (m.media?.length || 0), 0);

  try {
    await navigator.clipboard.writeText(output);
    console.log(`✅ Success! Copied ${messages.length} items (${totalMedia} media files/links) to clipboard.`);
  } catch (e) {
    console.warn("Clipboard write failed; pushing to console as fallback.", e);
    console.log("Data Output:\n", output);
    window.prompt(`Copied ${messages.length} messages. If the text below is cut off, check the developer console for the full output:`, "See browser console.");
  }

  return { count: messages.length, mediaCount: totalMedia };
}

// Run the script
copyDiscordDMToClipboard();

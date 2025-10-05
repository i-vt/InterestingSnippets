/**
 * ============================================================
 *  SMS Utility
 *  ------------------------------------------------------------
 *  Provides a cross-platform method to open the default SMS app
 *  with a pre-filled message body and a randomly selected recipient.
 *  Works on iOS, Android, and desktop browsers (copy fallback).
 * ============================================================
 */

/**
 * List of recipient phone numbers.
 * Use E.164 format (recommended) or valid local formats.
 * One number will be randomly selected for each message.
 */
const SMS_NUMBERS = [
  "+12134981239",
  "+17633571235",
];

/**
 * Message body to prefill in the SMS application.
 * Encoded for inclusion in a URL.
 */
const SMS_BODY = encodeURIComponent(
  "I’m very interested in participating in AI training work."
);

/**
 * Selects a random phone number from the configured list.
 * @returns {string} A sanitized phone number string, or an empty string if none configured.
 */
function pickNumber() {
  if (!Array.isArray(SMS_NUMBERS) || SMS_NUMBERS.length === 0) return "";
  const idx = Math.floor(Math.random() * SMS_NUMBERS.length);
  return SMS_NUMBERS[idx].replace(/\s+/g, "");
}

/**
 * Copies text to the clipboard (used for desktop fallback).
 * @param {string} text - The text to copy.
 * @returns {boolean} True if successful, false otherwise.
 */
function copyText(text) {
  try {
    const ta = document.createElement("textarea");
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand("copy");
    document.body.removeChild(ta);
    return ok;
  } catch {
    return false;
  }
}

/**
 * Opens the default SMS application with a prefilled message.
 * - iOS: Uses "sms:+15551234567&body=..."
 * - Android: Uses "sms:+15551234567?body=..."
 * - Desktop: Copies the message to clipboard as a fallback.
 */
function sendSMS() {
  const num = pickNumber();
  if (!num) {
    alert("No SMS number is configured.");
    return;
  }

  const ua = navigator.userAgent || navigator.vendor || window.opera;
  const isAndroid = /Android/i.test(ua);
  const isIOS = /iPhone|iPad|iPod/i.test(ua);

  let link = "";
  if (isIOS) {
    link = `sms:${num}&body=${SMS_BODY}`;
  } else if (isAndroid) {
    link = `sms:${num}?body=${SMS_BODY}`;
  } else {
    const copied = copyText(`${num} — ${decodeURIComponent(SMS_BODY)}`);
    alert(
      copied
        ? "Number and message copied! Open your phone to send the SMS."
        : "Please send an SMS manually to: " + num
    );
    return;
  }

  window.location.href = link;
}

/**
 * ============================================================
 *  Example Usage
 * ============================================================
 * Add a button in your HTML to trigger the function:
 *
 *  <button id="smsButton">Send SMS</button>
 *
 *  <script>
 *    document
 *      .getElementById("smsButton")
 *      .addEventListener("click", (e) => {
 *        e.preventDefault();
 *        sendSMS();
 *      });
 *  </script>
 */

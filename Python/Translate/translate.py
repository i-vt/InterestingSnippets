import time
import threading
import queue

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, WebDriverException


class Translate:

    def __init__(self, timeout=20, page_resolve_timeout=10, max_start_retries=2):

        self.timeout = timeout
        self.page_resolve_timeout = page_resolve_timeout
        self.max_start_retries = max_start_retries

        self.driver = None
        self.textarea = None
        self.last_translation = ""

    def _start_driver_once(self):
        """Start a Chrome driver and attempt to load Translate (single attempt)."""
        driver = webdriver.Chrome()

        # Hard cap for page load; Selenium will raise TimeoutException if exceeded.
        driver.set_page_load_timeout(self.page_resolve_timeout)

        # Try to load the page. If it doesn't load in time, this throws.
        driver.get("https://translate.google.com")

        # Light "resolved" signal: page has an interactive DOM.
        # (Optional but helps ensure it's not a blank/hung state)
        WebDriverWait(driver, self.page_resolve_timeout).until(
            lambda d: d.execute_script("return document.readyState") in ("interactive", "complete")
        )

        return driver

    def _start_driver_in_new_thread(self, out_q: "queue.Queue"):
        """
        Worker function: start driver and put (driver, err) into queue.
        """
        driver = None
        err = None
        try:
            driver = self._start_driver_once()
        except Exception as e:
            err = e
            # If driver exists but we're failing, ensure we kill it.
            if driver:
                try:
                    driver.quit()
                except Exception:
                    pass
                driver = None
        out_q.put((driver, err))

    def start(self):
        last_err = None

        for attempt in range(1, self.max_start_retries + 1):
            # If we already have a driver from previous run, ensure it's dead.
            self.close()

            out_q = queue.Queue(maxsize=1)
            t = threading.Thread(target=self._start_driver_in_new_thread, args=(out_q,), daemon=True)
            t.start()
            try:
                driver, err = out_q.get(timeout=self.page_resolve_timeout + 2)
            except queue.Empty:
                # Thread didn't report back: treat as hung attempt.
                err = TimeoutException(
                    f"Start attempt hung > {self.page_resolve_timeout}s (no result returned)"
                )
                driver = None

            if driver and err is None:
                self.driver = driver
                print(f"✅ Browser started. (attempt {attempt}/{self.max_start_retries})")
                return

            last_err = err
            print(
                f"⚠️ Start attempt {attempt}/{self.max_start_retries} failed "
                f"(page didn't resolve in {self.page_resolve_timeout}s). "
                f"Error: {type(last_err).__name__}: {last_err}"
            )

        raise RuntimeError(
            f"Failed to start/resolve Translate after {self.max_start_retries} attempts. "
            f"Last error: {type(last_err).__name__}: {last_err}"
        )

    # ---------------------------
    # Your existing functionality
    # ---------------------------

    def accept_cookies(self, cookie_timeout=3):
        """Accept cookies if banner appears
        
        Args:
            cookie_timeout: Seconds to wait for cookie banner (default 3s)
        """
        if not self.driver:
            raise RuntimeError("Driver not initialized. Call start() first.")

        wait = WebDriverWait(self.driver, cookie_timeout)  # Short timeout
        try:
            accept = wait.until(EC.element_to_be_clickable(
                (By.XPATH, "//button[contains(., 'Accept all')]")
            ))
            accept.click()
            print("✅ Accepted cookies.")
            time.sleep(1)
            return True
        except TimeoutException:
            print("ℹ️ No cookie banner found (continuing).")
            return False

    def setup_textarea(self):
        """Locate and store the source textarea element"""
        if not self.driver:
            raise RuntimeError("Driver not initialized. Call start() first.")

        wait = WebDriverWait(self.driver, self.timeout)
        self.textarea = wait.until(EC.presence_of_element_located(
            (By.CSS_SELECTOR, "textarea[aria-label*='Source']")
        ))
        print("✅ Textarea located.")

    def enter_text(self, text):
        """
        Clear textarea and enter new text using JavaScript to handle all Unicode characters.
        """
        if not self.textarea:
            raise RuntimeError("Textarea not initialized. Call setup_textarea() first.")

        self.driver.execute_script(
            "arguments[0].value = arguments[1];"
            "arguments[0].dispatchEvent(new Event('input', { bubbles: true }));",
            self.textarea,
            text
        )
        time.sleep(0.5)
        print(f"✅ Text entered (length: {len(text)} chars).")

    def get_current_translation(self):
        """Get the current translation text from the page."""
        if not self.driver:
            return None

        try:
            elements = self.driver.find_elements(By.CSS_SELECTOR, "span[jsname='W297wb']")
            if not elements:
                return None
            full_translation = " ".join(elem.text.strip() for elem in elements if elem.text.strip())
            return full_translation
        except Exception:
            return None

    def wait_for_new_translation(self, old_text, timeout=None):
        """Wait for translation to change from old_text and stabilize."""
        if timeout is None:
            timeout = self.timeout

        start_time = time.time()
        stable_text = None
        stable_count = 0

        while time.time() - start_time < timeout:
            current_text = self.get_current_translation()

            if current_text and current_text != old_text and len(current_text) > 0:
                if current_text == stable_text:
                    stable_count += 1
                    if stable_count >= 3:
                        return current_text
                else:
                    stable_text = current_text
                    stable_count = 1

            time.sleep(0.5)

        return stable_text

    def translate(self, text, wait_time=2):
        """Translate text and return the result."""
        self.enter_text(text)
        time.sleep(wait_time)

        translation = self.wait_for_new_translation(self.last_translation)

        if translation:
            print(f"💬 Translation: {translation[:100]}..." if len(translation) > 100 else f"💬 Translation: {translation}")
            self.last_translation = translation
            return translation

        fallback = self.get_current_translation()
        if fallback:
            print(f"💬 Translation (may be partial): {fallback[:100]}..." if len(fallback) > 100 else f"💬 Translation (may be partial): {fallback}")
            self.last_translation = fallback
        else:
            print("❌ Could not extract translation")
        return fallback

    def close(self):
        """Close the browser"""
        if self.driver:
            try:
                self.driver.quit()
            except Exception:
                pass
            self.driver = None
            self.textarea = None
            print("✅ Browser closed.")

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False


def main():
    with Translate(timeout=20, page_resolve_timeout=10, max_start_retries=3) as translator:
        translator.accept_cookies()  
        translator.setup_textarea()
        translator.translate("Hola!")
        translator.translate("Que tal?")
        time.sleep(5)


if __name__ == "__main__":
    main()

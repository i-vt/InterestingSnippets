import os
import time
from translate import Translate
from concurrent.futures import ThreadPoolExecutor
from queue import Queue
from threading import Lock

PARTS_DIR = "./part_files"
OUTPUT_DIR = "./translated_files"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Thread-safe locks
print_lock = Lock()
stats_lock = Lock()

# Global statistics
stats = {
    "completed": 0,
    "failed": 0,
    "skipped": 0,
    "total_processed": 0,
    "translator_restarts": 0
}

def thread_safe_print(*args, **kwargs):
    """Thread-safe print function."""
    with print_lock:
        print(*args, **kwargs)

def update_stats(key, increment=1):
    """Thread-safe statistics update."""
    with stats_lock:
        stats[key] += increment

def is_already_translated(filepath: str):
    """Check if a file has already been translated."""
    filename = os.path.basename(filepath)
    output_path = os.path.join(OUTPUT_DIR, f"{filename}_translated.txt")
    return os.path.exists(output_path)

def translate_single_file(translator: Translate, filepath: str, thread_id: int, translation_timeout: int = 120):
    """
    Translate a single file using an existing translator instance.
    Returns 'success', 'restart', or 'failed'.
    """
    filename = os.path.basename(filepath)
    output_path = os.path.join(OUTPUT_DIR, f"{filename}_translated.txt")
    
    # Double-check if already translated
    if is_already_translated(filepath):
        update_stats("skipped")
        thread_safe_print(f"⏭️  [Thread-{thread_id}] Already translated: {filename}")
        return 'success'
    
    try:
        with open(filepath, "r", encoding="utf-8") as file:
            text = file.read().strip()
    except Exception as ex:
        thread_safe_print(f"❌ [Thread-{thread_id}] Error reading file {filename}: {ex}")
        return 'failed'
    
    try:
        thread_safe_print(f"🔄 [Thread-{thread_id}] Translating {filename}...")
        start_time = time.time()
        
        # Attempt translation with timeout tracking
        translated_text = translator.translate(text, wait_time=3)
        
        elapsed = time.time() - start_time
        thread_safe_print(f"⏱️  [Thread-{thread_id}] Translation took {elapsed:.1f} seconds")
        
        # Check if translation took too long (might indicate lag)
        if elapsed > translation_timeout:
            thread_safe_print(f"⚠️  [Thread-{thread_id}] Translation took too long ({elapsed:.1f}s > {translation_timeout}s)")
            return 'restart'
        
        # Check if we got a valid translation
        if not translated_text or len(translated_text.strip()) == 0:
            thread_safe_print(f"❌ [Thread-{thread_id}] No translation returned for {filename}")
            return 'restart'
        
        # Save the translation
        with open(output_path, "w", encoding="utf-8") as out_file:
            out_file.write(translated_text)
        
        update_stats("completed")
        thread_safe_print(f"✅ [Thread-{thread_id}] Success: {filename}")
        return 'success'
        
    except Exception as ex:
        thread_safe_print(f"❌ [Thread-{thread_id}] Error translating {filename}: {ex}")
        # Determine if this is a browser/page failure that requires restart
        error_str = str(ex).lower()
        if any(keyword in error_str for keyword in ['session', 'chrome', 'driver', 'browser', 'connection', 'disconnected', 'timeout']):
            thread_safe_print(f"🔄 [Thread-{thread_id}] Browser/page error detected, needs restart")
            return 'restart'
        return 'failed'

def initialize_translator(thread_id: int, timeout: int = 300, max_attempts: int = 5):
    """
    Initialize and set up a new translator instance with retry logic.
    Returns translator or None if all attempts fail.
    """
    for attempt in range(1, max_attempts + 1):
        try:
            thread_safe_print(f"🚀 [Thread-{thread_id}] Initializing translator (attempt {attempt}/{max_attempts})...")
            translator = Translate(timeout=timeout)
            translator.start()
            
            # Try to accept cookies
            try:
                translator.accept_cookies()
            except Exception as ex:
                thread_safe_print(f"⚠️  [Thread-{thread_id}] Cookie acceptance failed (continuing anyway): {ex}")
            
            translator.setup_textarea()
            thread_safe_print(f"✅ [Thread-{thread_id}] Translator ready")
            return translator
            
        except Exception as ex:
            thread_safe_print(f"❌ [Thread-{thread_id}] Failed to initialize translator (attempt {attempt}/{max_attempts}): {ex}")
            if attempt < max_attempts:
                wait_time = min(attempt * 5, 30)  # Exponential backoff, max 30s
                thread_safe_print(f"⏳ [Thread-{thread_id}] Waiting {wait_time}s before retry...")
                time.sleep(wait_time)
            else:
                thread_safe_print(f"💀 [Thread-{thread_id}] Failed to initialize translator after {max_attempts} attempts")
                return None
    
    return None

def safe_close_translator(translator: Translate, thread_id: int):
    """Safely close a translator, catching any exceptions."""
    if translator:
        try:
            translator.close()
            thread_safe_print(f"🛑 [Thread-{thread_id}] Translator closed")
        except Exception as ex:
            thread_safe_print(f"⚠️  [Thread-{thread_id}] Error closing translator (ignoring): {ex}")

def worker_thread(thread_id: int, work_queue: Queue, total_files: int):
    """
    Worker thread that processes files from the queue.
    Keeps the translator running until an error occurs, then restarts it.
    Thread is resilient and will keep trying to restart on failures.
    """
    translator = None
    consecutive_failures = 0
    max_consecutive_failures = 3
    files_processed = 0
    restart_after_files = 100  # Optional: restart every N files for memory management
    max_restart_attempts = 10  # Maximum times to try restarting translator before giving up on thread
    restart_attempts = 0
    
    try:
        while True:
            # Ensure we have a working translator
            if translator is None:
                translator = initialize_translator(thread_id)
                update_stats("translator_restarts")
                restart_attempts += 1
                
                if translator is None:
                    if restart_attempts >= max_restart_attempts:
                        thread_safe_print(f"💀 [Thread-{thread_id}] Failed to restart translator after {max_restart_attempts} attempts. Thread terminating.")
                        break
                    else:
                        # Wait before trying again
                        wait_time = min(restart_attempts * 10, 60)
                        thread_safe_print(f"⏳ [Thread-{thread_id}] Waiting {wait_time}s before next restart attempt...")
                        time.sleep(wait_time)
                        continue
                else:
                    # Successfully restarted
                    restart_attempts = 0
                    consecutive_failures = 0
                    files_processed = 0
            
            # Get next file from queue
            try:
                file_path = work_queue.get_nowait()
            except:
                # Queue is empty, we're done
                thread_safe_print(f"✅ [Thread-{thread_id}] No more files to process, shutting down")
                break
            
            filename = os.path.basename(file_path)
            update_stats("total_processed")
            
            # Show progress
            remaining = work_queue.qsize()
            processed = total_files - remaining
            thread_safe_print(f"\n{'='*60}")
            thread_safe_print(f"📄 [Thread-{thread_id}] Progress: {processed}/{total_files} | File: {filename}")
            thread_safe_print(f"{'='*60}")
            
            # Attempt translation
            result = translate_single_file(translator, file_path, thread_id, translation_timeout=120)
            
            if result == 'success':
                consecutive_failures = 0
                files_processed += 1
                
                # Optional: Restart translator after N files for memory management
                if files_processed >= restart_after_files:
                    thread_safe_print(f"🔄 [Thread-{thread_id}] Restarting translator after {files_processed} files (preventive maintenance)...")
                    safe_close_translator(translator, thread_id)
                    translator = None
                    time.sleep(2)
                    
            elif result == 'restart':
                consecutive_failures += 1
                thread_safe_print(f"⚠️  [Thread-{thread_id}] Translation needs restart. Consecutive failures: {consecutive_failures}/{max_consecutive_failures}")
                
                # Restart translator
                if consecutive_failures >= max_consecutive_failures:
                    thread_safe_print(f"🔄 [Thread-{thread_id}] Too many consecutive failures, restarting translator...")
                    safe_close_translator(translator, thread_id)
                    translator = None
                    time.sleep(5)
                    
                    # Put file back in queue for retry
                    work_queue.put(file_path)
                    thread_safe_print(f"🔁 [Thread-{thread_id}] Re-queued {filename} for retry")
                else:
                    # Just restart immediately without waiting for max failures
                    thread_safe_print(f"🔄 [Thread-{thread_id}] Restarting translator due to browser/page error...")
                    safe_close_translator(translator, thread_id)
                    translator = None
                    time.sleep(3)
                    
                    # Put file back in queue for retry
                    work_queue.put(file_path)
                    thread_safe_print(f"🔁 [Thread-{thread_id}] Re-queued {filename} for retry")
                    
            else:  # result == 'failed'
                update_stats("failed")
                consecutive_failures += 1
                thread_safe_print(f"❌ [Thread-{thread_id}] File failed: {filename}")
                
                # Don't restart translator for file-level failures, just continue
                if consecutive_failures >= max_consecutive_failures * 2:
                    # Too many failures, restart as precaution
                    thread_safe_print(f"🔄 [Thread-{thread_id}] Too many failures overall, restarting translator as precaution...")
                    safe_close_translator(translator, thread_id)
                    translator = None
                    time.sleep(5)
                    consecutive_failures = 0
            
            # Mark task as done
            work_queue.task_done()
            
            # Small delay between files
            time.sleep(0.5)
    
    except Exception as ex:
        thread_safe_print(f"💀 [Thread-{thread_id}] Unexpected thread exception: {ex}")
        import traceback
        thread_safe_print(traceback.format_exc())
    
    finally:
        # Clean up translator when thread is done
        safe_close_translator(translator, thread_id)

def get_all_part_files(directory: str):
    """
    Get all files named like 'part_123123.txt', sorted numerically by the number.
    """
    parts = [
        os.path.join(directory, f)
        for f in os.listdir(directory)
        if f.startswith("part_") and f.endswith(".txt")
    ]
    
    # Sort numerically by the digits after 'part_'
    def extract_number(filename):
        try:
            return int(os.path.splitext(filename)[0].split("_")[1])
        except (IndexError, ValueError):
            return 0
    
    return sorted(parts, key=lambda x: extract_number(os.path.basename(x)))

if __name__ == "__main__":
    NUM_THREADS = 2  # Number of parallel browser windows
    
    all_parts = get_all_part_files(PARTS_DIR)
    print(f"📂 Found {len(all_parts)} total files.")
    
    # Filter out already translated files
    files_to_translate = [f for f in all_parts if not is_already_translated(f)]
    already_done = len(all_parts) - len(files_to_translate)
    
    if already_done > 0:
        print(f"⏭️  Skipping {already_done} already translated files")
    
    if not files_to_translate:
        print("✅ All files have already been translated!")
        exit(0)
    
    print(f"📝 {len(files_to_translate)} files remaining to translate.")
    print(f"🔀 Using {NUM_THREADS} parallel threads")
    print(f"🔥 Each thread will keep its browser running and auto-restart on failures\n")
    
    # Create work queue and add all files
    work_queue = Queue()
    for file_path in files_to_translate:
        work_queue.put(file_path)
    
    start_time = time.time()
    
    try:
        # Create thread pool and start workers
        with ThreadPoolExecutor(max_workers=NUM_THREADS) as executor:
            # Submit worker threads
            futures = [
                executor.submit(worker_thread, i + 1, work_queue, len(files_to_translate))
                for i in range(NUM_THREADS)
            ]
            
            # Wait for all threads to complete
            for future in futures:
                try:
                    future.result()
                except Exception as ex:
                    thread_safe_print(f"❌ Thread exception: {ex}")
    
    except KeyboardInterrupt:
        thread_safe_print("\n⚠️  Interrupted by user. Shutting down gracefully...")
    
    finally:
        elapsed_time = time.time() - start_time
        
        print("\n" + "="*60)
        print("✅ Translation process complete!")
        print(f"📊 Summary:")
        print(f"   - Already translated (skipped): {already_done}")
        print(f"   - Newly completed: {stats['completed']}")
        print(f"   - Skipped during run: {stats['skipped']}")
        print(f"   - Failed: {stats['failed']}")
        print(f"   - Translator restarts: {stats['translator_restarts']}")
        print(f"   - Total files: {len(all_parts)}")
        print(f"   - Time elapsed: {elapsed_time/60:.1f} minutes")
        if stats['completed'] > 0:
            print(f"   - Avg time per file: {elapsed_time/stats['completed']:.1f} seconds")
        print("="*60)

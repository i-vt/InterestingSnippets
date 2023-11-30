import threading

def my_function():
    for i in range(5):
        print(f"Thread: {threading.current_thread().name}, Count: {i}")

# Create two threads
thread1 = threading.Thread(target=my_function, name="Thread 1")
thread2 = threading.Thread(target=my_function, name="Thread 2")
thread3 = threading.Thread(target=my_function, name="Thread 3")

# Start the threads
thread1.start()
thread2.start()

# Wait for completion of a thread
while thread3.is_alive():
    print("Thread is still running")
    time.sleep(1)

# Synchronize: Wait for both threads to finish
thread1.join()
thread2.join()

print("Main thread is done.")


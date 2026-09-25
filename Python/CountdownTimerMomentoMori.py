import time
from tqdm import tqdm
import threading
from datetime import datetime, timedelta
import calendar

def minutes_until_end_of_day():
    now = datetime.now()
    end_of_day = datetime.combine(now.date(), datetime.max.time())
    delta = end_of_day - now
    return delta.total_seconds() // 60

def minutes_until_end_of_week():
    now = datetime.now()
    days_until_end_of_week = 6 - now.weekday()  # Monday is 0 and Sunday is 6
    end_of_week = (now + timedelta(days=days_until_end_of_week)).replace(hour=23, minute=59, second=59, microsecond=999999)
    delta = end_of_week - now
    return delta.total_seconds() // 60

def minutes_until_end_of_month():
    now = datetime.now()
    last_day_of_month = calendar.monthrange(now.year, now.month)[1]
    end_of_month = now.replace(day=last_day_of_month, hour=23, minute=59, second=59, microsecond=999999)
    delta = end_of_month - now
    return delta.total_seconds() // 60

def minutes_until_end_of_year():
    now = datetime.now()
    end_of_year = now.replace(month=12, day=31, hour=23, minute=59, second=59, microsecond=999999)
    delta = end_of_year - now
    return delta.total_seconds() // 60

def minutes_until_specific_date(target_date_str):
    now = datetime.now()
    target_date = datetime.strptime(target_date_str, '%Y-%m-%d %H:%M:%S')
    
    delta = target_date - now
    return int(delta.total_seconds() // 60)


def format_time(seconds):
    mins, secs = divmod(seconds, 60)
    return f"{mins:02d}:{secs:02d}"
def update_progress_bar(task_name, duration):
    with tqdm(total=duration, desc=task_name, bar_format="{desc}: {bar} {n_fmt}/{total_fmt} [{elapsed}/{remaining}]") as pbar:
        for elapsed in range(duration):
            time.sleep(1)
            pbar.set_postfix_str(f"{format_time(elapsed)}/{format_time(duration)}")
            pbar.update(1)

def banner():
    print(r"""


---------------------------------------------------------------------------

    ___  ___                           _         ___  ___           _ 
    |  \/  |                          | |        |  \/  |          (_)
    | .  . | ___  _ __ ___   ___ _ __ | |_ ___   | .  . | ___  _ __ _ 
    | |\/| |/ _ \| '_ ` _ \ / _ \ '_ \| __/ _ \  | |\/| |/ _ \| '__| |
    | |  | | (_) | | | | | |  __/ | | | || (_) | | |  | | (_) | |  | |
    \_|  |_/\___/|_| |_| |_|\___|_| |_|\__\___/  \_|  |_/\___/|_|  |_|
                                                                      
                                                                      

    [ Do not waste time, live and enjoy life now. ]

https://github.com/i-vt
---------------------------------------------------------------------------


Time left until the end of:
""")

if __name__ == "__main__":
    banner()
    timers = {
        "Day": 60 * minutes_until_end_of_day(),
        #"Week": 60 * minutes_until_end_of_week(), 
        #"Month": 60 * minutes_until_end_of_month(),
        #"Year": 60 * minutes_until_end_of_year(),
        #"Your 90s": 60 * minutes_until_specific_date('2150-01-01 00:00:00'),
        #Don't forget to customize this for yourself :)

    }


    threads = []
    for task_name, duration in timers.items():
        thread = threading.Thread(target=update_progress_bar, args=(task_name, int(duration)))
        threads.append(thread)
        thread.start()

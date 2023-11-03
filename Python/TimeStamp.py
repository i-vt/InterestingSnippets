import datetime

# Get string of current time as a timestamp: "yyyymmddHHMMSS"
def timestamp() -> str:
  current = datetime.datetime.now()
  return current.strftime("%Y%m%d%H%M%S")


import os
import asyncio
from opentele.td import TDesktop
from opentele.api import UseCurrentSession

async def convert_sessions():
    # Set the root directory to the current working directory
    root_dir = "." 
    
    for folder_name in os.listdir(root_dir):
        folder_path = os.path.join(root_dir, folder_name)
        
        # Check if the item is a directory
        if os.path.isdir(folder_path):
            tdata_path = os.path.join(folder_path, "tdata")
            
            # Check if the "tdata" subfolder actually exists inside it
            if os.path.isdir(tdata_path):
                print(f"[*] Found tdata for {folder_name}. Converting...")
                session_filename = f"{folder_name}.session"
                
                try:
                    # 1. Load the Telegram Desktop tdata folder using TDesktop
                    td = TDesktop(tdata_path)
                    
                    # Verify the data was loaded successfully
                    if not td.isLoaded():
                        print(f"[!] Failed to load valid accounts for {folder_name}. Skipping...")
                        continue
                    
                    # 2. Convert it to a Telethon client object
                    client = await td.ToTelethon(session=session_filename, flag=UseCurrentSession)
                    
                    # 3. Connect to finalize and write the SQLite .session file
                    await client.connect()
                    
                    # 4. Disconnect to safely close the database lock
                    if await client.is_user_authorized():
                        print(f"[+] Successfully converted and verified: {session_filename}")
                    else:
                        print(f"[-] Warning: {session_filename} converted, but session may be logged out.")
                        
                    await client.disconnect()
                    
                except Exception as e:
                    print(f"[!] Failed to convert {folder_name}: {e}")

if __name__ == "__main__":
    asyncio.run(convert_sessions())

import os
import shutil
import sys
from pathlib import Path
from datetime import datetime

def get_backup_path(browser_name):
    """Get the backup path based on the browser name."""
    documents_path = Path.home() / 'Documents'
    backup_path = documents_path / f"{browser_name}_backup_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    backup_path.mkdir(parents=True, exist_ok=True)
    return backup_path

def backup_browser_data(source_paths, backup_path):
    """Copy files from source paths to backup path."""
    for source in source_paths:
        if source.exists():
            destination = backup_path / source.name
            try:
                if source.is_file():
                    shutil.copy2(source, destination)
                elif source.is_dir():
                    shutil.copytree(source, destination, dirs_exist_ok=True)
                print(f"Backed up: {source} to {destination}")
            except Exception as e:
                print(f"Failed to backup {source}: {e}")
        else:
            print(f"Source path does not exist: {source}")

def backup_chrome():
    """Backup Chrome data."""
    if sys.platform.startswith('win'):  # Windows
        chrome_paths = [
            Path(os.getenv('LOCALAPPDATA')) / 'Google' / 'Chrome' / 'User Data' / 'Default' / 'Cookies',
            Path(os.getenv('LOCALAPPDATA')) / 'Google' / 'Chrome' / 'User Data' / 'Default' / 'Login Data',
            Path(os.getenv('LOCALAPPDATA')) / 'Google' / 'Chrome' / 'User Data' / 'Default' / 'History',
            Path(os.getenv('LOCALAPPDATA')) / 'Google' / 'Chrome' / 'User Data' / 'Default' / 'Bookmarks',
            Path(os.getenv('LOCALAPPDATA')) / 'Google' / 'Chrome' / 'User Data' / 'Default' / 'Preferences',
            Path(os.getenv('LOCALAPPDATA')) / 'Google' / 'Chrome' / 'User Data' / 'Default' / 'Extensions',
            Path(os.getenv('LOCALAPPDATA')) / 'Google' / 'Chrome' / 'User Data' / 'Default' / 'Web Data',  # Autofill data
        ]
    elif sys.platform.startswith('linux'):  # Linux
        chrome_paths = [
            Path.home() / '.config' / 'google-chrome' / 'Default' / 'Cookies',
            Path.home() / '.config' / 'google-chrome' / 'Default' / 'Login Data',
            Path.home() / '.config' / 'google-chrome' / 'Default' / 'History',
            Path.home() / '.config' / 'google-chrome' / 'Default' / 'Bookmarks',
            Path.home() / '.config' / 'google-chrome' / 'Default' / 'Preferences',
            Path.home() / '.config' / 'google-chrome' / 'Default' / 'Extensions',
            Path.home() / '.config' / 'google-chrome' / 'Default' / 'Web Data',  # Autofill data
        ]
    elif sys.platform.startswith('darwin'):  # macOS
        chrome_paths = [
            Path.home() / 'Library' / 'Application Support' / 'Google' / 'Chrome' / 'Default' / 'Cookies',
            Path.home() / 'Library' / 'Application Support' / 'Google' / 'Chrome' / 'Default' / 'Login Data',
            Path.home() / 'Library' / 'Application Support' / 'Google' / 'Chrome' / 'Default' / 'History',
            Path.home() / 'Library' / 'Application Support' / 'Google' / 'Chrome' / 'Default' / 'Bookmarks',
            Path.home() / 'Library' / 'Application Support' / 'Google' / 'Chrome' / 'Default' / 'Preferences',
            Path.home() / 'Library' / 'Application Support' / 'Google' / 'Chrome' / 'Default' / 'Extensions',
            Path.home() / 'Library' / 'Application Support' / 'Google' / 'Chrome' / 'Default' / 'Web Data',  # Autofill data
        ]
    else:
        print("Unsupported OS for Chrome backup")
        return

    backup_path = get_backup_path("Chrome")
    backup_browser_data(chrome_paths, backup_path)

def backup_firefox():
    """Backup Firefox data."""
    if sys.platform.startswith('win'):  # Windows
        firefox_profile_path = Path(os.getenv('APPDATA')) / 'Mozilla' / 'Firefox' / 'Profiles'
    elif sys.platform.startswith('linux'):  # Linux
        firefox_profile_path = Path.home() / '.mozilla' / 'firefox'
    elif sys.platform.startswith('darwin'):  # macOS
        firefox_profile_path = Path.home() / 'Library' / 'Application Support' / 'Firefox' / 'Profiles'
    else:
        print("Unsupported OS for Firefox backup")
        return

    # Check if the profile path exists
    if not firefox_profile_path.exists():
        print(f"Firefox profile path does not exist: {firefox_profile_path}")
        return

    # Check for profile directories with various suffixes
    profile_suffixes = ['.default-release', '.default', '.dev-edition-default', '.esr', '']
    found_profiles = False

    for profile in firefox_profile_path.iterdir():
        if profile.is_dir() and any(profile.name.endswith(suffix) for suffix in profile_suffixes):
            firefox_paths = [
                profile / 'cookies.sqlite',
                profile / 'logins.json',
                profile / 'key4.db',
                profile / 'places.sqlite',  # Contains browsing history and bookmarks
                profile / 'prefs.js',  # Preferences
                profile / 'extensions',  # Extensions directory
                profile / 'formhistory.sqlite',  # Autofill data
            ]
            backup_path = get_backup_path("Firefox")
            backup_browser_data(firefox_paths, backup_path)
            found_profiles = True

    if not found_profiles:
        print("No valid Firefox profile found for backup.")

def backup_opera():
    """Backup Opera data."""
    if sys.platform.startswith('win'):  # Windows
        opera_paths = [
            Path(os.getenv('APPDATA')) / 'Opera Software' / 'Opera Stable' / 'Cookies',
            Path(os.getenv('APPDATA')) / 'Opera Software' / 'Opera Stable' / 'Login Data',
            Path(os.getenv('APPDATA')) / 'Opera Software' / 'Opera Stable' / 'History',
            Path(os.getenv('APPDATA')) / 'Opera Software' / 'Opera Stable' / 'Bookmarks',
            Path(os.getenv('APPDATA')) / 'Opera Software' / 'Opera Stable' / 'Preferences',
            Path(os.getenv('APPDATA')) / 'Opera Software' / 'Opera Stable' / 'Extensions',
            Path(os.getenv('APPDATA')) / 'Opera Software' / 'Opera Stable' / 'Web Data',  # Autofill data
        ]
    elif sys.platform.startswith('linux'):  # Linux
        opera_paths = [
            Path.home() / '.config' / 'opera' / 'Cookies',
            Path.home() / '.config' / 'opera' / 'Login Data',
            Path.home() / '.config' / 'opera' / 'History',
            Path.home() / '.config' / 'opera' / 'Bookmarks',
            Path.home() / '.config' / 'opera' / 'Preferences',
            Path.home() / '.config' / 'opera' / 'Extensions',
            Path.home() / '.config' / 'opera' / 'Web Data',  # Autofill data
        ]
    elif sys.platform.startswith('darwin'):  # macOS
        opera_paths = [
            Path.home() / 'Library' / 'Application Support' / 'com.operasoftware.Opera' / 'Cookies',
            Path.home() / 'Library' / 'Application Support' / 'com.operasoftware.Opera' / 'Login Data',
            Path.home() / 'Library' / 'Application Support' / 'com.operasoftware.Opera' / 'History',
            Path.home() / 'Library' / 'Application Support' / 'com.operasoftware.Opera' / 'Bookmarks',
            Path.home() / 'Library' / 'Application Support' / 'com.operasoftware.Opera' / 'Preferences',
            Path.home() / 'Library' / 'Application Support' / 'com.operasoftware.Opera' / 'Extensions',
            Path.home() / 'Library' / 'Application Support' / 'com.operasoftware.Opera' / 'Web Data',  # Autofill data
        ]
    else:
        print("Unsupported OS for Opera backup")
        return

    backup_path = get_backup_path("Opera")
    backup_browser_data(opera_paths, backup_path)

def backup_brave():
    """Backup Brave data."""
    if sys.platform.startswith('win'):  # Windows
        brave_paths = [
            Path(os.getenv('LOCALAPPDATA')) / 'BraveSoftware' / 'Brave-Browser' / 'User Data' / 'Default' / 'Cookies',
            Path(os.getenv('LOCALAPPDATA')) / 'BraveSoftware' / 'Brave-Browser' / 'User Data' / 'Default' / 'Login Data',
            Path(os.getenv('LOCALAPPDATA')) / 'BraveSoftware' / 'Brave-Browser' / 'User Data' / 'Default' / 'History',
            Path(os.getenv('LOCALAPPDATA')) / 'BraveSoftware' / 'Brave-Browser' / 'User Data' / 'Default' / 'Bookmarks',
            Path(os.getenv('LOCALAPPDATA')) / 'BraveSoftware' / 'Brave-Browser' / 'User Data' / 'Default' / 'Preferences',
            Path(os.getenv('LOCALAPPDATA')) / 'BraveSoftware' / 'Brave-Browser' / 'User Data' / 'Default' / 'Extensions',
            Path(os.getenv('LOCALAPPDATA')) / 'BraveSoftware' / 'Brave-Browser' / 'User Data' / 'Default' / 'Web Data',  # Autofill data
        ]
    elif sys.platform.startswith('linux'):  # Linux
        brave_paths = [
            Path.home() / '.config' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Cookies',
            Path.home() / '.config' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Login Data',
            Path.home() / '.config' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'History',
            Path.home() / '.config' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Bookmarks',
            Path.home() / '.config' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Preferences',
            Path.home() / '.config' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Extensions',
            Path.home() / '.config' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Web Data',  # Autofill data
        ]
    elif sys.platform.startswith('darwin'):  # macOS
        brave_paths = [
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Cookies',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Login Data',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'History',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Bookmarks',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Preferences',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Extensions',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Web Data',  # Autofill data
        ]
    elif sys.platform.startswith('darwin'):  # macOS
        brave_paths = [
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Cookies',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Login Data',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'History',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Bookmarks',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Preferences',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Extensions',
            Path.home() / 'Library' / 'Application Support' / 'BraveSoftware' / 'Brave-Browser' / 'Default' / 'Web Data',  # Autofill data
        ]
    else:
        print("Unsupported OS for Brave backup")
        return

    backup_path = get_backup_path("Brave")
    backup_browser_data(brave_paths, backup_path)

def backup_edge():
    """Backup Edge data."""
    if sys.platform.startswith('win'):  # Windows
        edge_paths = [
            Path(os.getenv('LOCALAPPDATA')) / 'Microsoft' / 'Edge' / 'User Data' / 'Default' / 'Cookies',
            Path(os.getenv('LOCALAPPDATA')) / 'Microsoft' / 'Edge' / 'User Data' / 'Default' / 'Login Data',
            Path(os.getenv('LOCALAPPDATA')) / 'Microsoft' / 'Edge' / 'User Data' / 'Default' / 'History',
            Path(os.getenv('LOCALAPPDATA')) / 'Microsoft' / 'Edge' / 'User Data' / 'Default' / 'Bookmarks',
            Path(os.getenv('LOCALAPPDATA')) / 'Microsoft' / 'Edge' / 'User Data' / 'Default' / 'Preferences',
            Path(os.getenv('LOCALAPPDATA')) / 'Microsoft' / 'Edge' / 'User Data' / 'Default' / 'Extensions',
            Path(os.getenv('LOCALAPPDATA')) / 'Microsoft' / 'Edge' / 'User Data' / 'Default' / 'Web Data',  # Autofill data
        ]
    elif sys.platform.startswith('linux'):  # Linux
        edge_paths = [
            Path.home() / '.config' / 'microsoft-edge' / 'Default' / 'Cookies',
            Path.home() / '.config' / 'microsoft-edge' / 'Default' / 'Login Data',
            Path.home() / '.config' / 'microsoft-edge' / 'Default' / 'History',
            Path.home() / '.config' / 'microsoft-edge' / 'Default' / 'Bookmarks',
            Path.home() / '.config' / 'microsoft-edge' / 'Default' / 'Preferences',
            Path.home() / '.config' / 'microsoft-edge' / 'Default' / 'Extensions',
            Path.home() / '.config' / 'microsoft-edge' / 'Default' / 'Web Data',  # Autofill data
        ]
    elif sys.platform.startswith('darwin'):  # macOS
        edge_paths = [
            Path.home() / 'Library' / 'Application Support' / 'Microsoft Edge' / 'Default' / 'Cookies',
            Path.home() / 'Library' / 'Application Support' / 'Microsoft Edge' / 'Default' / 'Login Data',
            Path.home() / 'Library' / 'Application Support' / 'Microsoft Edge' / 'Default' / 'History',
            Path.home() / 'Library' / 'Application Support' / 'Microsoft Edge' / 'Default' / 'Bookmarks',
            Path.home() / 'Library' / 'Application Support' / 'Microsoft Edge' / 'Default' / 'Preferences',
            Path.home() / 'Library' / 'Application Support' / 'Microsoft Edge' / 'Default' / 'Extensions',
            Path.home() / 'Library' / 'Application Support' / 'Microsoft Edge' / 'Default' / 'Web Data',  # Autofill data
        ]
    else:
        print("Unsupported OS for Edge backup")
        return

    backup_path = get_backup_path("Edge")
    backup_browser_data(edge_paths, backup_path)

def backup_internet_explorer():
    """Backup Internet Explorer data."""
    if not sys.platform.startswith('win'):  # Windows only
        print("Internet Explorer backup is only supported on Windows.")
        return

    ie_paths = [
        Path(os.getenv('APPDATA')) / 'Microsoft' / 'Windows' / 'Cookies',
        Path(os.getenv('LOCALAPPDATA')) / 'Microsoft' / 'Windows' / 'History',
        Path(os.getenv('LOCALAPPDATA')) / 'Microsoft' / 'Internet Explorer' / 'User Data',  # Cache and temp files
        Path(os.getenv('APPDATA')) / 'Microsoft' / 'Internet Explorer' / 'Quick Launch',  # Preferences
    ]

    backup_path = get_backup_path("Internet Explorer")
    backup_browser_data(ie_paths, backup_path)

def main():
    """Run all backup functions."""
    backup_chrome()
    backup_firefox()
    backup_opera()
    backup_brave()
    backup_edge()
    backup_internet_explorer()

if __name__ == '__main__':
    main()

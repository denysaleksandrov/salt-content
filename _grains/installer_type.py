# C:\salt\conf\grains\installer_type.py
# Custom grain to determine if Salt Minion was installed via MSI or EXE
# Specific to Windows systems - not for Linux/MacOS
# store this file in /srv/salt/_grains/installer_type.py
# To update grains: salt <windows_minion_ids> saltutil.sync_grains
# Usage: salt '*' grains.get installer_type
##################################################################
import winreg

def installer_type():
    result = None
    paths = [
        r"Software\Microsoft\Windows\CurrentVersion\Uninstall",
        r"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    ]

    for path in paths:
        try:
            h = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, path)
            for i in range(winreg.QueryInfoKey(h)[0]):
                sub = winreg.EnumKey(h, i)
                sk = winreg.OpenKey(h, sub)
                try:
                    name = winreg.QueryValueEx(sk, "DisplayName")[0]
                    if "Salt Minion" in name:
                        try:
                            msi = winreg.QueryValueEx(sk, "WindowsInstaller")[0]
                            result = "msi" if msi == 1 else "exe"
                        except:
                            # If WindowsInstaller value doesn't exist, check UninstallString
                            try:
                                uninstall = winreg.QueryValueEx(sk, "UninstallString")[0]
                                result = "msi" if "msiexec" in uninstall.lower() else "exe"
                            except:
                                # Default to exe if we can't determine
                                result = "undetermined-exe"
                        return {"installer_type": result}
                except:
                    pass
        except:
            pass

    return {"installer_type": result}
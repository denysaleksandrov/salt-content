# State file to update or downgrade the salt-minion on RHEL and Windows systems
# Sample command: salt '<minionid>' state.sls update5 pillar='{"target_version": "3006.17"}'

{% set target_version = salt['pillar.get']('target_version', 'latest') %}

# Define variables
{% if grains['os_family'] == 'RedHat' %}
  # RHEL: Manage both packages to avoid dependency locks
  {% set packages_to_manage = ['salt', 'salt-minion'] %}
  {% set service_name = 'salt-minion' %}

  {% set restart_cmd = 'nohup sh -c "sleep 15; systemctl restart salt-minion" > /dev/null 2>&1 &' %}
  {% set pre_mask = 'systemctl mask salt-minion' %}
  {% set post_unmask = 'systemctl unmask salt-minion' %}

  # LOGIC SWITCH: If we are on RHEL and targeting a specific version (downgrade/pin),
  # we switch to 'cmd.run' to bypass Salt's pkg module dependency issues.
  {% if target_version != 'latest' %}
    {% set install_type = 'rhel_cmd' %}
  {% else %}
    {% set install_type = 'pkg' %}
  {% endif %}

{% elif grains['os_family'] == 'Windows' %}
  # --- WINDOWS INSTALLER DETECTION ---
  # 1. Check for custom grain 'installer_type'
  {% set installer_type = salt['grains.get']('installer_type') %}


  # 2. Fallback: If grain is missing, detect via Registry
  {% if not installer_type %}
    # PowerShell to get the UninstallString. MSI uses MsiExec.exe; EXE uses uninst.exe.
    # We use cmd.run during Jinja rendering to dynamically set this variable.
    {% set ps_check = "Get-ChildItem HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -like 'Salt Minion*'} | Select-Object -ExpandProperty UninstallString" %}
    {% set uninstall_string = salt['cmd.run'](ps_check, shell='powershell') %}

    {% if 'MsiExec.exe' in uninstall_string %}
      {% set installer_type = 'msi' %}
    {% else %}
      {% set installer_type = 'exe' %}
    {% endif %}
  {% endif %}

  # 3. Set Package Name based on Type
  # These names correspond to standard Salt WinRepo definitions
  {% if installer_type == 'msi' %}
    {% set packages_to_manage = ['salt-minion-msi-py3'] %}
  {% else %}
    {% set packages_to_manage = ['salt-minion-py3'] %}
  {% endif %}
  # -----------------------------------

  {% set service_name = 'salt-minion' %}
  {% set restart_cmd = 'powershell -command "Start-Sleep -Seconds 120; Restart-Service -Name salt-minion -Force"' %}
  
  # WINDOWS PINNING:
  # If 'latest' is requested, force pin to 3006.17 to avoid upgrading to 3007.x branch.
  {% if target_version == 'latest' %}
    {% set target_version = '3006.25' %}
  {% endif %}

  # WINDOWS WORKAROUND:
  # Use 'module.run' to force execution, bypassing state idempotency issues during downgrades.
  {% set install_type = 'win_module' %}

{% endif %}

# -- Execution Block --

{% if grains['os_family'] in ['RedHat', 'Windows'] %}

# [RHEL ONLY] Mask service
{% if grains['os_family'] == 'RedHat' %}
mask_service_to_prevent_rpm_restart:
  cmd.run:
    - name: {{ pre_mask }}
    - unless: systemctl is-enabled {{ service_name }} | grep masked
    - require_in:
      - install_or_downgrade_minion
{% endif %}

# [ALL] Perform the Package Upgrade/Downgrade
install_or_downgrade_minion:
  {% if install_type in ['pkg', 'rhel_cmd'] %}
  # RHEL WORKAROUND: Raw DNF command
  cmd.run:
    - name: dnf install -y {% for pkg in packages_to_manage %}{{ pkg }}-{{ target_version }} {% endfor %}
    - unless: rpm -q {% for pkg in packages_to_manage %}{{ pkg }}-{{ target_version }} {% endfor %}

  {% elif install_type == 'win_module' %}
  # WINDOWS WORKAROUND: Force install via execution module
  module.run:
    - pkg.install:
      - name: {{ packages_to_manage[0] }}
      - version: {{ target_version }}
    # Check if we are already at the correct version to preserve idempotency
    - unless:
      - cmd: 'salt-call --local pkg.version {{ packages_to_manage[0] }} | findstr /C:"{{ target_version }}"'

  {% else %}
  # Standard Logic (RHEL Upgrades)
    {% if target_version == 'latest' %}
  pkg.latest:
    - pkgs: {{ packages_to_manage }}
    {% else %}
  pkg.installed:
    - pkgs:
      {% for pkg in packages_to_manage %}
      - {{ pkg }}: {{ target_version }}
      {% endfor %}
    - allow_updates: True
    - allow_downgrade: True
    - ignore_epoch: True
    {% endif %}
    - refresh: True
  {% endif %}

# [RHEL ONLY] Unmask service
{% if grains['os_family'] == 'RedHat' %}
unmask_service_after_install:
  cmd.run:
    - name: {{ post_unmask }}
    - require:
      - install_or_downgrade_minion
{% endif %}

# [ALL] Trigger Delayed Restart
{% if grains['os_family'] == 'RedHat' %}
schedule_delayed_restart:
  cmd.run:
    - name: {{ restart_cmd }}
    - bg: True
    - onchanges:
      - install_or_downgrade_minion
{% else %}
schedule_delayed_restart:
  cmd.run:
    - name: {{ restart_cmd }} 
    - bg: True
    - onchanges:
      - install_or_downgrade_minion
{% endif %}
{% endif %}

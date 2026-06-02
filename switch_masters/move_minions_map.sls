# filename: /srv/salt/switch_masters/move_minions_map.sls
# state to switch minions from one master to another

{% set minion = salt['grains.get']('os') %}
# name old master and set new master ip address
{% import_yaml 'switch_masters/files/minions.yaml' as mm %}
{% set oldmaster = mm['oldmaster'] %}
{% set newmaster = mm['newmaster'] %}

# remove minion_master.pub key
{% if minion == 'Windows' %}
remove_master_key:
  file.absent:
    - name: c:\ProgramData\Salt Project\Salt\conf\pki\minion\minion_master.pub

change_master_assignment:
  file.replace:
    - name: c:\ProgramData\Salt Project\Salt\conf\minion 
    - pattern: 'master: {{oldmaster}}'
    - repl: 'master: {{newmaster}}'
    - require:
      - remove_master_key
{% else %}
remove_master_key:
  file.absent:
    - name: /etc/salt/pki/minion/minion_master.pub

# modify minion config file
change_master_assignment:
  file.replace:
    - name: /etc/salt/minion.d/minion.conf 
    - pattern: 'master: {{oldmaster}}'
    - repl: 'master: {{newmaster}}'
    - require:
      - remove_master_key
{% endif %}
# restart salt-minion
restart_salt_minion:
  service.running:
    - name: salt-minion 
    - require:
      - change_master_assignment
    - watch:
      - change_master_assignment


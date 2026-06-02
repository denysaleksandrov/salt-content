# Orchestration to move Minions from one master to another
# Sample command: salt-run state.orch switch_masters --async


{% import_yaml 'switch_masters/files/minions.yaml' as mm %}
{% set minions = mm['minionids'] %}

{% if minions %}
{% for minion in minions %}
move_minions_{{ minion }}:
  salt.state:
    - tgt: {{ minion }}
    - sls:
      - switch_masters.move_minions_map
    - saltenv: main

remove_minion_{{ minion }}:
  cmd.run:
    - name: salt-key -yd {{ minion }}
    - order: Last

{% endfor %}    
{% else %}
no_minions:
  test.configurable_test_state:
    - name: No minions to move
    - result: True 
    - changes: False 
    - comment: No minions to move
{% endif %}

# generation of minionIDs in preparation for switching masters
# filename: /srv/salt/switch_masters/files/minionids.sls
# Command: salt <oldmaster_minionid> state.apply switch_masters.files.minionids pillar='{"oldmaster": "oldmaster", "newmaster": "newmaster"}' test=1

{% set minions = salt['saltutil.runner']('manage.up') %}
{% set oldmaster = salt['pillar.get']('oldmaster') %}
{% set newmaster = salt['pillar.get']('newmaster') %}

create_minion_list:
  file.managed:
    - name: /srv/salt/switch_masters/minions.yaml
    - source: salt://switch_masters/files/maptmpl.yaml
    - template: jinja
    - defaults:
        minions: {{ minions }}
        oldmaster: {{ oldmaster }}
        newmaster: {{ newmaster }}


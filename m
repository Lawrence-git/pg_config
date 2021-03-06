---
# Assumptions: 
#    - postmaster  is not running
#    - ansible executes as unix user 'postgres'
#    - cluster has been initialized and pg_hda allows role 'postres'to connect 
#    - we will not configure osx hosts because psycopg2 might be hard to install through macports
# Post conditions:
#   - pg_hba.conf is updated  or left untouchd, depending on user options 
#   - created postgres roles with passwords
#   - added to template1
#   - created  databases, extensions, languages, and set privs
#   - enabled replication via uses 'postgres' and 'replication' (see pg_hba.conf)


  - name:           fail unless ansible executing as unix user postgres
    when:           not (ansible_user_id == "postgres")
    fail:           msg="Detected ansible_user_id='{{ ansible_user_id}}'. This role must run as 'postgres'"

  - name:           ensure postmaster is running 
    shell:          "pg_ctl -D {{ cluster }} start"
    ignore_errors:  yes
    environment:  
      PATH:        "{{ ansible_env.HOME }}/dist-pg/bin:{{ ansible_env.PATH}}:/usr/bin"

  - name:          extra packages
    include:       "{{ ansible_os_family }}.yml"
    become_user:   root
    become:        yes

  - name:        /var/log/postgres
    become_user: root
    become:      yes
    file:        path=/var/log/postgresql   state=directory   owner=postgres   group=postgres   mode=0750



############################### Roles  ##############################################################################
  - name:            create postgres and replication
    when:             
                   - postgres_passwd    is defined
                   - repl_and_pg_roles 
    postgresql_user:  name="{{item.name}}"   role_attr_flags="{{item.attr}}"  password="{{ item.passwd |default(omit) }}"  encrypted=yes  ssl_mode="prefer"   port="{{ port }}" login_password="{{postgres_passwd|default(omit)}}"  login_host=localhost 
    with_items:
        - { name: postgres,      passwd: "{{postgres_passwd}}", attr: superuser   }
        - { name: replication,   passwd: "{{postgres_passwd}}", attr: replication }

  - name:             create roles 
    postgresql_user:  name="{{item.name}}"   role_attr_flags="{{item.attr | default(omit)}}" password="{{item.passwd|default(omit)}}"  encrypted="yes"  ssl_mode="prefer"   port="{{ port }}" login_password="{{postgres_passwd|default(omit)}}"  login_host=localhost 
    with_items: "{{  users  }}"


#################################### config_files ##################################################################
  - name:            pg_hba.conf
    template:        src="pg_hba.conf.j2"  dest="{{cluster}}/pg_hba.conf"    owner=postgres 
    when:            pg_hba

    #copy:            src="{{ item }}"  dest="{{ cluster}}/"  owner=postgres  mode=0640
    #with_fileglob:
    #- pg_*.conf
################################## template1   ######################################################################
  - name: plpgsql
    postgresql_lang:  db=template1  lang=plpgsql   trust=yes  state=present port="{{ port }}" login_password="{{postgres_passwd|default(omit)}}"  login_host="localhost"
    
################################### Databases  #####################################################################
  - name:   db bench
    postgresql_db: name="bench" owner="ioannis" encoding="UTF-8" lc_collate="en_US.UTF-8"  template=template0  port="{{ port }}" login_password="{{postgres_passwd|default(omit)}}"  login_host="localhost"

  - name:   db ioannis
    postgresql_db: name="ioannis" owner="ioannis" encoding="UTF-8" lc_collate="en_US.UTF-8"  template=template0  port="{{ port }}" login_password="{{postgres_passwd|default(omit)}}"  login_host="localhost"

################################# Extensions  #######################################################################
  - name:            ext for database ioannis
    postgresql_ext:  name={{item}}  db=ioannis port="{{ port }}" login_password="{{postgres_passwd|default(omit)}}"  login_host="localhost"
    with_items:
         - pgtap
           #- pg_stat_statements #- pg_qualstats #- pg_stat_kcache


################################ Privs     ###########################################################################
  - name:  privs for database postgres 
    postgresql_privs:   db="postgres"  privs=CONNECT  type=database  roles="{{item}}" port="{{ port }}" login_password="{{postgres_passwd|default(omit)}}"  login_host="localhost"
    with_items:
        - nagios
        - ioannis

  - postgresql_privs:   db="postgres" grant_option="no"  privs="INSERT,UPDATE"  type="table" obj="ALL_IN_SCHEMA"  schema="public" roles="{{item}}"  port="{{ port }}" login_password="{{postgres_passwd|default(omit)}}"  login_host="localhost"
    with_items:
        - nagios

################################## Reload, then Stop postmaster unless user wanted otherwise
  - name:            reload {{ cluster}} 
    shell:          "pg_ctl -D {{ cluster }} reload"
    environment:  
          PATH:     "{{ ansible_env.PATH }}:{{ ansible_env.HOME }}/dist-pg/bin:/usr/bin"

  - name:            keep postmaster running ?
    when:            not (keep_running)
    ignore_errors:   yes
    shell:          "pg_ctl -D {{ cluster }} stop"
    environment:  
          PATH:     "{{ ansible_env.PATH }}:{{ ansible_env.HOME }}/dist-pg/bin:/usr/bin"

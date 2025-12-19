from trino.dbapi import connect
from trino.auth import BasicAuthentication

# Connessione con autenticazione
conn = connect(
    host='localhost',
    port=8080,
    user='admin',
    http_scheme='http',
    catalog='hive',
    schema='default'
)

# Esegui una query
cur = conn.cursor()
cur.execute('SHOW SCHEMAS')
rows = cur.fetchall()
for row in rows:
    print(row)

cur.close()
conn.close()